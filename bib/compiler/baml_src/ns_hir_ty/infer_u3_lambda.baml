// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 3, lambdas and instantiation: `infer_lambda`, the call-site
// instantiation road (`instantiation_args_at`, fresh generic arguments,
// computed generic arguments), the bound registration for callables and
// classes, the constructor completeness check, and the free helpers
// `function_param_pairs`, `effect_only_params`,
// `substitute_interface_params` and `call_bound_purpose`.
//
// Restructured (BAML forces it):
// - `InferenceContext` methods are free functions taking `ctx` first; a
//   free function over interned types takes the pool first.
// - `infer_lambda`'s body arm is `infer_lambda_body`.
// - `instantiation_args` (a forward at `TypePosition::Existential`) is
//   `instantiation_args_at`'s default `position`.
// - No root is served from an interface, so a `FunctionRef` is its Source
//   lane, a function loc `int`.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_lambda @ d9be6853b
// Lambda typing (rust-analyzer's `deduce_closure_signature` shape). Written
// signature slots win; unannotated slots fill from the expected function
// type flowing down, or become fresh inference variables that later uses
// can constrain. An omitted `throws` is inferred from the lambda's body.
function infer_lambda(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    def: root.ast.LambdaDef,
    expected: Expectation,
) -> int throws never {
    let pool = ctx.table.pool;
    let signature = ctx.type_refs.lambda_signatures.get(expr);
    // A union with one concrete callback arm expects that function here just
    // as much as an immediate callback does: the other arms provide no
    // lambda signature.
    let expected_ty = expectation_only_has_type(expected);
    let callback = if (expected_ty != null) {
        callback_root_fn(ctx, structurally_resolve(ctx, expected_ty))
    } else {
        null
    };
    let expected_fn = if (callback != null) {
        match (pool.kinds[callback]) {
            let f: root.types.InferTyFunction => f,
            _ => null,
        }
    } else {
        null
    };
    let expected_arity = if (expected_fn != null && expected_fn.params.length() != def.params.length()) {
        expected_fn.params.length()
    } else {
        null
    };
    if (expected_arity != null) {
        report(
            ctx,
            PendingDiagArgCountMismatch {
                expr: expr,
                expected: expected_arity,
                got: def.params.length(),
            },
        );
    }
    let written_param = (index: int) -> root.hir.BodyTypeRefId? {
        signature?.params.at(index)
    };
    let param_tys: int[] = [];
    for (let index = 0; index < def.params.length(); index += 1) {
        let annotated = written_param(index);
        let ty = if (annotated != null) {
            lower_body_annotation(ctx, annotated)
        } else if (expected_fn != null) {
            expected_fn.params.at(index)?.ty ?? pool.add(root.types.TyError {})
        } else {
            untyped_lambda_parameter_ty(ctx, expr, index, def.params[index].name)
        };
        param_tys.push(ty);
    }
    let written_ret = signature?.return_type;
    let annotated_ret = if (written_ret != null) {
        lower_body_annotation(ctx, written_ret)
    } else {
        null
    };
    if (expected_fn != null) {
        infer_lambda_deduce_signature(
            ctx,
            expected_fn,
            param_tys,
            baml.Array.generate(param_tys.length(), (index) -> {
                written_param(index) != null
            }),
            annotated_ret,
        );
    }
    let ret_expectation = annotated_ret ?? expected_fn?.ret;
    let written_throws_ref = signature?.throws_;
    let written_throws = if (written_throws_ref != null) {
        lower_body_annotation(ctx, written_throws_ref)
    } else {
        null
    };
    // Capture openness before inference solves a written effect hole.
    let coverage_clause = if (written_throws != null && !pool.has_infer(written_throws)) {
        written_throws
    } else {
        null
    };
    // The scope the lambda opened, via the semantic index's span-free lambda
    // join. Registering the deduced params there is what makes the body's
    // parameter references resolve.
    let key = metadata_key(ctx, expr);
    let lambda_scope = if (key != null) {
        ctx.index.lambda_scope(key)
    } else {
        null
    };
    if (lambda_scope != null) {
        ctx.lambda_params[lambda_scope] = param_tys;
    }
    // The lambda's OWN effect channel: defining a throwing lambda throws
    // nothing; calling it does. Only a closed contextual effect supplies value
    // context; an open effect is inferred from the body.
    let contextual_throws = if (written_throws == null && expected_fn != null) {
        let throws_ = structurally_resolve(ctx, expected_fn.throws_);
        if (
            !pool.has_infer(throws_)
                && !pool.has_error(throws_)
                && !pool.has_typevar(throws_)
                && !(pool.kinds[throws_] is root.types.TyUnknown)
        ) {
            throws_
        } else {
            null
        }
    } else {
        null
    };
    let declared_throws = written_throws ?? contextual_throws;
    let clause: ThrowsClause = if (declared_throws != null && !pool.has_infer(declared_throws)) {
        ThrowsClauseClosed { value: declared_throws }
    } else {
        ThrowsClauseInferred {}
    };
    ctx.throws_channels.push(ThrowsChannel { clause: clause, contributions: [] });
    let lambda_body = def.body;
    let ret_ty = if (lambda_body != null) {
        infer_lambda_body(ctx, body, lambda_body, ret_expectation, lambda_scope)
    } else {
        ret_expectation ?? pool.add(root.types.TyError {})
    };
    let throws_ty = infer_lambda_throws(ctx, expr, lambda_body, declared_throws, coverage_clause);
    let params = baml.Array.generate(def.params.length(), (index) -> {
        let param = def.params[index];
        root.types.InferFunctionParamTy {
            name: param.name,
            ty: param_tys[index],
            mode: if (param.default != null) {
                root.types.FunctionParamMode.Optional
            } else {
                root.types.FunctionParamMode.Required
            },
        }
    });
    let ty = pool.add(root.types.InferTyFunction { params: params, ret: ret_ty, throws_: throws_ty });
    if (expected_arity != null) {
        pool.add(root.types.TyError {})
    } else {
        ty
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_lambda @ d9be6853b
// (the signature-deduction block)
// Signature deduction from expectation (rustc's
// `check_supplied_sig_against_expectation`): a WRITTEN annotation commits
// into the expected function type's corresponding slot while that slot is
// still an unsolved inference variable, so a generic call's type argument
// is known at the call site. A slot that already resolved structurally is
// left to the ordinary argument check (unify failures are ignored here
// for the same reason). `throws` is excluded: the effect channel owns it.
// `written[i]` says whether parameter `i` carries an annotation.
function infer_lambda_deduce_signature(
    ctx: InferenceContext,
    expected_fn: root.types.InferTyFunction,
    param_tys: int[],
    written: bool[],
    annotated_ret: int?,
) -> void throws never {
    let pool = ctx.table.pool;
    for (let index = 0; index < param_tys.length(); index += 1) {
        let ty = param_tys[index];
        if (!written[index] || pool.has_error(ty)) {
            continue;
        }
        let expected_param = expected_fn.params.at(index);
        if (expected_param == null) {
            continue;
        }
        let expected_slot = structurally_resolve(ctx, expected_param.ty);
        if (pool.has_infer(expected_slot)) {
            ctx.table.unify(ty, expected_slot) catch (e) {
                root.hir_ty.infer.UnifyError => {},
            };
        }
    }
    if (annotated_ret != null && !pool.has_error(annotated_ret)) {
        let expected_ret = structurally_resolve(ctx, expected_fn.ret);
        if (pool.has_infer(expected_ret)) {
            ctx.table.unify(annotated_ret, expected_ret) catch (e) {
                root.hir_ty.infer.UnifyError => {},
            };
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_lambda @ d9be6853b
// (the effect tail) Closes the lambda's effect channel: contributions are
// checked against a declared clause (and a closed written one is recorded
// as a contract), else the inferred clause is their union.
function infer_lambda_throws(
    ctx: InferenceContext,
    expr: int,
    lambda_body: int?,
    declared_throws: int?,
    coverage_clause: int?,
) -> int throws never {
    let pool = ctx.table.pool;
    let channel = (ctx.throws_channels.pop() ?? baml.sys.panic("pushed above")).contributions;
    if (declared_throws != null) {
        for (let contribution in channel) {
            check_throws_contribution(ctx, contribution.0, contribution.1, declared_throws);
        }
    }
    if (declared_throws != null) {
        if (coverage_clause != null) {
            ctx.throws_contracts.push(
                ThrowsContract {
                    declared: coverage_clause,
                    contributions: channel,
                    at: lambda_body ?? expr,
                },
            );
        }
        declared_throws
    } else {
        // An INFERRED clause publishes every contribution as part of the
        // lambda's type, so one typed by a binding the body's own blocks
        // closed cannot stay. The inferred surface keeps literal grain.
        let kept = drop_escaping_effects(ctx, channel, null);
        if (kept.length() == 0) {
            pool.add(root.types.TyNever {})
        } else {
            union_of(
                ctx,
                kept.map((contribution) -> {
                    ctx.table.resolve_completely(contribution.1)
                }),
            )
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_lambda @ d9be6853b
// (the body arm) The body types in the owner's run and table, but under the
// lambda's metadata scope and its own callable frame, so its divergence and
// returns are the lambda's, not the owner's. Returns the lambda's return
// type.
function infer_lambda_body(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    lambda_body: int,
    ret_expectation: int?,
    lambda_scope: int?,
) -> int throws never {
    let pool = ctx.table.pool;
    root.hir_ty.infer.enter_frame(
        ctx,
        root.hir_ty.infer.FrameKindCallable {
            returns: root.hir_ty.infer.ReturnFrame {
                expected: ret_expectation,
                candidates: [],
                scoped_bindings_floor: ctx.scoped_type_bindings.length(),
            },
            scope: lambda_scope,
        },
    );
    let body_ty = if (ret_expectation != null && !pool.has_error(ret_expectation)) {
        check_expr(ctx, body, lambda_body, ret_expectation)
    } else if (ret_expectation != null) {
        infer_expr(ctx, body, lambda_body, ExpectationErroneous {})
    } else {
        infer_expr(ctx, body, lambda_body, ExpectationNone {})
    };
    // `std::mem::take` of the frame's return slot.
    let return_frame = match (root.hir_ty.infer.control_frame(ctx).kind) {
        let callable: root.hir_ty.infer.FrameKindCallable => {
            let taken = callable.returns;
            callable.returns
                = root.hir_ty.infer.ReturnFrame {
                    expected: null,
                    candidates: [],
                    scoped_bindings_floor: 0,
                };
            taken
        },
        _ => baml.sys.panic("the lambda's frame is the innermost until `leave_frame`"),
    };
    return_frame.candidates.push(
        root.hir_ty.infer.Returned { ty: body_ty, units: take_units(ctx, lambda_body) },
    );
    let joined = join_return_candidates(
        ctx,
        return_frame.candidates.map((returned) -> {
            returned.ty
        }),
    );
    // With no expected return type, every value the lambda returns joins the
    // others.
    if (ret_expectation == null) {
        join_units(
            ctx,
            return_frame.candidates.map((returned) -> {
                (returned.ty, returned.units)
            }),
            ExpectationNone {},
        );
    }
    let inferred_ret = widen_fresh(ctx, joined);
    let ret_ty = if (ret_expectation != null && !pool.has_error(ret_expectation)) {
        if (pool.has_infer(ret_expectation)) {
            sub(ctx, inferred_ret, ret_expectation);
        }
        ret_expectation
    } else {
        inferred_ret
    };
    root.hir_ty.infer.leave_frame(ctx);
    ret_ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::register_callable_instantiation @ d9be6853b
// One Implements obligation per declared bound of the callable's generic
// frame at `instantiation`, and the effect policy for every own parameter
// that occurs only in `throws` positions (`effect_only_params`):
// unconstrained, such a slot is the empty effect `never`.
function register_callable_instantiation(
    ctx: InferenceContext,
    callable: int,
    instantiation: int[],
    at: int,
) -> void throws never {
    let pool = ctx.table.pool;
    for (let param in effect_only_params(ctx.db, callable)) {
        let arg = instantiation.at(param.index);
        if (arg == null) {
            continue;
        }
        match (pool.kinds[arg]) {
            let var: root.types.TyInferVar => {
                ctx.table.promote_to_effect(var.var);
                match (ctx.journals.infer_var_origins.get(var.var)) {
                    let origin: InferVarOriginTypeParameter => {
                        origin.effect = true;
                    },
                    _ => {},
                }
            },
            _ => {},
        }
    }
    // The concreteness rule covers the callable's OWN declared params. The
    // frame PREFIX is the receiver's business: `Self` legitimately binds an
    // existential for virtual dispatch, and class/interface args were judged
    // at the receiver's own annotation.
    let frame = callable_generic_frame(ctx.db, callable);
    for (let slot = 0; slot < frame.params.length() && slot < frame.bounds.length(); slot += 1) {
        let param = frame.params[slot];
        let arg = instantiation.at(param.index);
        if (arg == null) {
            continue;
        }
        for (let bound in frame.bounds[slot]) {
            // Declared bounds are plain; the obligation machinery's vocabulary
            // is interned: ingest once per bound.
            let interface_ = root.types.infer_interface_from_constraint(pool, bound);
            root.hir_ty.infer.register_obligation(
                ctx,
                root.hir_ty.infer.obligation_implements(
                    arg,
                    substitute_interface_params(pool, interface_, instantiation),
                    at,
                    call_bound_purpose(param, frame.own_start),
                ),
            );
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::register_class_bounds @ d9be6853b
// `register_callable_instantiation` for a class instantiation: one
// Implements obligation per declared bound of the class's generic frame
// (rustc's ADT well-formedness obligations at the constructor site).
// Restructured: the substitution Rust spells out inline is
// `substitute_interface_params`.
function register_class_bounds(
    ctx: InferenceContext,
    class_: int,
    instantiation: int[],
    at: int,
) -> void throws never {
    let pool = ctx.table.pool;
    let bounds = class_generic_bounds(ctx.db, class_);
    for (let param in bounds.keys()) {
        let arg = instantiation.at(param.index);
        if (arg == null) {
            continue;
        }
        for (let bound in bounds[param]) {
            let interface_ = root.types.infer_interface_from_constraint(pool, bound);
            root.hir_ty.infer.register_obligation(
                ctx,
                root.hir_ty.infer.obligation_implements(
                    arg,
                    substitute_interface_params(pool, interface_, instantiation),
                    at,
                    root.hir_ty.infer.GoalPurpose.Bound,
                ),
            );
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::instantiation_args_at @ d9be6853b
// The instantiation vector for a generic item at a use site: explicit
// turbofish args (with `_` holes as fresh vars) where written, fresh
// variables everywhere else. Written slots align only with user-writable
// params; synthetic effect params always receive fresh effect variables.
// Also `instantiation_args` (the existential default position).
function instantiation_args_at(
    ctx: InferenceContext,
    site: int,
    generic_params: root.types.ParamTy[],
    callee: string?,
    position: TypePosition = TypePosition.Existential,
) -> int[] throws never {
    let written = ctx.type_refs.expr_type_args.get(site) ?? [];
    // Explicit turbofish counts against the WRITABLE params (synthetic effect
    // params are elaboration's, never spelled).
    let arity_reported = false;
    if (callee != null && written.length() > 0) {
        let expected = generic_params
            .filter((param) -> {
                !root.types.is_synthetic_effect_param(param.name)
            })
            .length();
        if (written.length() != expected) {
            report(
                ctx,
                PendingDiagWrongTypeArgArity {
                    expr: site,
                    callee: callee,
                    expected: expected,
                    got: written.length(),
                },
            );
            arity_reported = true;
        }
    }
    let next_written = 0;
    let slots: CallTypeArgPlan<int>[] = [];
    let instantiation: int[] = [];
    for (let param in generic_params) {
        if (root.types.is_synthetic_effect_param(param.name)) {
            instantiation.push(fresh_generic_arg(ctx, param));
            continue;
        }
        let type_ref = written.at(next_written);
        if (type_ref == null) {
            // A slot the miscounted argument list left unwritten is the arity
            // report's: the sentinel, never a second "cannot infer".
            instantiation.push(
                if (arity_reported) {
                    ctx.table.pool.add(root.types.TyError {})
                } else {
                    fresh_required_arg(ctx, param, site)
                },
            );
            continue;
        }
        next_written += 1;
        let computed = computed_generic_argument_name(ctx, type_ref, site);
        let (let lowered, let diagnostics) = lower_body_type_ref_at(ctx, type_ref, position, HolePolicyAllowed {});
        if (computed != null) {
            specialize_computed_generic_diagnostic(ctx, diagnostics, type_ref, site, computed);
        } else {
            queue_body_lowering_diagnostics(ctx, diagnostics);
        }
        let ty = reject_expr_position_holes(ctx, lowered, site);
        slots.push(CallTypeArgPlan { ty: ty, emission_ty: ty });
        instantiation.push(ty);
    }
    if (slots.length() > 0) {
        ctx.result.call_plans.get_or_insert(site, CallPlan.default()).slots = slots;
    }
    instantiation
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::is_reflect_package_function_lookup @ d9be6853b
// Whether `function_` is `reflect.Package.get_function` or `find_function`,
// whose own generics are extraction contracts.
function is_reflect_package_function_lookup(
    ctx: InferenceContext,
    function_: int,
) -> bool throws never {
    let qtn = callable_owner_type(ctx.db, function_)
        ?? return false;
    root.hir.lang_roots(ctx.db).is_(root.base.LangPackage.Reflect, qtn.pkg)
        && qtn.namespace.length() == 0
        && qtn.name == "Package"
        && ["get_function", "find_function"].includes(
            root.hir.function_data(ctx.db, function_).name,
        )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::computed_generic_argument_name @ d9be6853b
// The name a written generic argument spells when it names a VALUE and no
// type (`f<x>()` with `x` a local): such a slot needs a `let type` binding.
function computed_generic_argument_name(
    ctx: InferenceContext,
    type_ref: root.hir.BodyTypeRefId,
    site: int,
) -> string? throws never {
    let written = ctx.type_refs.store.get(ctx.type_refs.raw_id(type_ref));
    let path_ref = match (written.kind) {
        let p: root.hir.TypeRefKindPath => p,
        _ => {
            return null;
        },
    };
    let path = path_ref.path.segments;
    if (
        path.length() != 1
            || path_ref.generic_args.length() > 0
            || path_ref.associated_type_bindings.length() > 0
    ) {
        return null;
    }
    let name = path[0];
    let is_value = local_binding_names_at(ctx, site).includes(name)
        || ctx.lower.resolve_value(root.hir.PathHeadPlain {}, path) != null;
    let is_type = ctx.lower.resolve_type_definition(root.hir.PathHeadPlain {}, path) != null
        || scoped_type_param(ctx, name) != null
        || ctx.lower.generic_params.some((param) -> {
            param.name == name
        });
    if (is_value && !is_type) {
        name
    } else {
        null
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::specialize_computed_generic_diagnostic @ d9be6853b
// Replace a generic unresolved-type finding for a value-shaped slot with the
// targeted whole-slot diagnostic. Any other findings from the same lowering
// operation retain their original anchors.
function specialize_computed_generic_diagnostic(
    ctx: InferenceContext,
    diagnostics: LoweringDiag[],
    type_ref: root.hir.BodyTypeRefId,
    site: int,
    name: string,
) -> void throws never {
    let replaced = false;
    for (let lowering in diagnostics) {
        let unresolved_name = match (lowering.kind) {
            let unresolved: LoweringDiagKindUnresolved => unresolved.name,
            _ => null,
        };
        if (lowering.type_ref == ctx.type_refs.raw_id(type_ref) && unresolved_name == name) {
            replaced = true;
        } else {
            report(
                ctx,
                PendingDiagBodyAnnot {
                    type_ref: ctx.type_refs.diagnostic_id(lowering.type_ref),
                    kind: lowering.kind,
                },
            );
        }
    }
    if (replaced) {
        report(ctx, PendingDiagComputedGenericArgumentRequiresLetType { expr: site, name: name });
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::fresh_generic_arg @ d9be6853b
// A fresh variable for one generic param at a use site: synthetic effect
// params get EFFECT variables (unconstrained defaults to `never`, not
// Error).
function fresh_generic_arg(ctx: InferenceContext, param: root.types.ParamTy) -> int throws never {
    if (root.types.is_synthetic_effect_param(param.name)) {
        ctx.table.new_var_ty(policy = root.hir_ty.infer.VarPolicy.Effect)
    } else {
        ctx.table.new_var_ty()
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::fresh_required_arg @ d9be6853b
// `fresh_generic_arg` for a slot the program must determine: the variable is
// registered with its site, and one still unsolved at finalize reports E0002
// there. A synthetic effect param is never required.
function fresh_required_arg(
    ctx: InferenceContext,
    param: root.types.ParamTy,
    site: int,
) -> int throws never {
    let ty = fresh_generic_arg(ctx, param);
    if (root.types.is_synthetic_effect_param(param.name)) {
        return ty;
    }
    let var = match (ctx.table.pool.kinds[ty]) {
        let v: root.types.TyInferVar => v.var,
        _ => baml.sys.panic("a fresh generic argument is an inference variable"),
    };
    ctx.journals.infer_var_origins[var]
        = InferVarOriginTypeParameter { site: site, param: param, effect: false };
    ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_missing_required_object_fields @ d9be6853b
// Shared completeness check for local and mounted class constructors. A
// valid spread has the exact class type and therefore supplies every slot;
// without one, each omitted slot must admit its `null` initializer.
// Restructured: Rust's `NullForms` impl for the interned `Ty` is the `form`
// closure passed to `accepts_null`.
function report_missing_required_object_fields(
    ctx: InferenceContext,
    object: int,
    class_name: root.types.DeclName,
    field_types: (string, root.types.Ty)[],
    instantiation: int[],
    fields: root.ast.ObjectExprField[],
    has_spread: bool,
) -> void throws never {
    if (has_spread) {
        return;
    }
    let pool = ctx.table.pool;
    let null_form = (ty: int) -> root.types.NullFormAdmits
        | root.types.NullFormUnion<int>
        | root.types.NullFormAlias
        | root.types.NullFormRefuses {
        match (pool.kinds[ty]) {
            root.types.TyNull | root.types.TyUnknown => root.types.NullFormAdmits {},
            let u: root.types.InferTyUnion => root.types.NullFormUnion { members: u.members },
            let a: root.types.TyTypeAlias => root.types.NullFormAlias { head: a.name },
            _ => root.types.NullFormRefuses {},
        }
    };
    let missing: string[] = [];
    for (let field in field_types) {
        let name = field.0;
        if (
            fields.some((written) -> {
                written.name == name
            })
        ) {
            continue;
        }
        // Declaration types are plain; the engine ingests them here to
        // substitute and resolve.
        let field_ty = substitute_params(pool, pool.from_plain(field.1), instantiation);
        let resolved = structurally_resolve(ctx, field_ty);
        // An error sentinel means the declaration's rule is unknown, not that
        // the field is non-nullable. `null` must be a value of the type, by
        // meaning: `unknown` and an alias whose union holds `null` admit it;
        // an unconstrained type parameter admits nothing.
        let admits_null = root.types.accepts_null(resolved, null_form, (alias) -> {
            ctx.facts.alias_def(alias)
        });
        if (!pool.has_error(resolved) && !admits_null) {
            missing.push(name);
        }
    }
    if (missing.length() > 0) {
        report(
            ctx,
            PendingDiagMissingRequiredObjectFields {
                object: object,
                class_name: class_name,
                field_names: missing,
            },
        );
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::function_param_pairs @ d9be6853b
// The parameter pairs `(expected, actual)` a function subtyping judgement
// relates contravariantly, when the two lists fit the spec's shape: the same
// number of required parameters, paired positionally, and every optional
// parameter of the expected type present by name in the actual, which may
// carry further optionals of its own. Null when the lists do not fit.
function function_param_pairs(
    actual: root.types.InferFunctionParamTy[],
    expected: root.types.InferFunctionParamTy[],
) -> (int, int)[]? throws never {
    let required = (params: root.types.InferFunctionParamTy[]) -> int[] {
        params
            .filter((param) -> {
                param.mode == root.types.FunctionParamMode.Required
            })
            .map((param) -> {
                param.ty
            })
    };
    let actual_required = required(actual);
    let expected_required = required(expected);
    if (actual_required.length() != expected_required.length()) {
        return null;
    }
    let pairs = baml.Array.generate(expected_required.length(), (index) -> {
        (expected_required[index], actual_required[index])
    });
    let expected_optional = expected.filter((param) -> {
        param.mode == root.types.FunctionParamMode.Optional
    });
    for (let expected_param in expected_optional) {
        // An optional parameter is matched by its name, so an unnamed one
        // matches nothing (the canonical relation's rule, `normalize`).
        let name = expected_param.name;
        if (name == null) {
            return null;
        }
        let actual_param = actual.find((param) -> {
            param.mode == root.types.FunctionParamMode.Optional && param.name == name
        })
            ?? return null;
        pairs.push((expected_param.ty, actual_param.ty));
    }
    pairs
}

// port: baml_compiler2_hir_ty/src/infer.rs::effect_only_params @ d9be6853b
// The callable's OWN generic parameters that are effects: unbounded, and
// occurring only as a member of a `throws` type, the signature's own or a
// function-typed parameter's. Unconstrained, such a slot is `never`. A
// BOUNDED parameter is not one: its body may dispatch on the type, which
// `never` cannot answer.
function effect_only_params(db: root.hir.Db, callable: int) -> root.types.ParamTy[] throws never {
    let pool = db.ty_memo.pool;
    let frame = callable_generic_frame(db, callable);
    let signature = function_signature_ty(db, callable);
    let throws_ = pool.from_plain(function_signature_with_diagnostics(db, callable).signature.throws_);
    let params = signature.params.map((param) -> {
        pool.from_plain(param.ty)
    });
    let ret = pool.from_plain(signature.return_type);
    let effects: root.types.ParamTy[] = [];
    for (
        let slot = frame.own_start;
        slot < frame.params.length() && slot < frame.bounds.length();
        slot += 1
    ) {
        let param = frame.params[slot];
        if (frame.bounds[slot].length() > 0) {
            continue;
        }
        let as_value = params.concat([ret]).some((ty) -> {
            mentions_param_as_value(pool, ty, param)
        })
            || throws_mentions_param_as_value(pool, throws_, param);
        let mentioned = params.concat([ret, throws_]).some((ty) -> {
            ty_mentions_param(pool, ty, param)
        });
        if (mentioned && !as_value) {
            effects.push(param);
        }
    }
    effects
}

// port: baml_compiler2_hir_ty/src/infer.rs::substitute_interface_params @ d9be6853b
// `substitute_params` over every type an interface constraint carries.
function substitute_interface_params(
    pool: root.types.InferPool,
    interface_: root.types.InferInterfaceConstraint,
    args: int[],
) -> root.types.InferInterfaceConstraint throws never {
    root.types.infer_interface_new(
        interface_.name,
        interface_.generics.map((ty) -> {
            substitute_params(pool, ty, args)
        }),
        interface_.associated_types.map((binding) -> {
            root.types.InferAssociatedType {
                name: binding.name,
                ty: substitute_params(pool, binding.ty, args),
            }
        }),
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::call_bound_purpose @ d9be6853b
// The purpose of a call-site bound on frame param `param`, whose own params
// start at `own_start`. The callee's OWN params are the user's type
// arguments and must be concrete. The frame PREFIX is the receiver's: a
// coercion of the receiver.
function call_bound_purpose(
    param: root.types.ParamTy,
    own_start: int,
) -> root.hir_ty.infer.GoalPurpose throws never {
    if (param.index >= own_start) {
        root.hir_ty.infer.GoalPurpose.Bound
    } else {
        root.hir_ty.infer.GoalPurpose.Coercion
    }
}
