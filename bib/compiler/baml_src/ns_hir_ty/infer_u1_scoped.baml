// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// Unit 1 of the K4 plan, part four: block-scoped `let type T = ...`
// bindings (binding, closing, the escape rule for values and effects, and
// body type lowering through the scoped overlay), plus the free scoped
// relaxation functions (`RelaxationVariance`, `nearest_scoped_relaxation`,
// `scoped_params_in`).
//
// Restructured (BAML forces it): `RelaxationVariance`'s methods are free
// functions `relaxation_variance_<method>`; `scoped_params_in` takes the
// pool its handle indexes, and its `&mut impl FnMut` visitor is a closure.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::bind_scoped_type @ d9be6853b
// `let type T extends ... = operand else { ... };`: mint the block-scoped
// rigid parameter, give it its declared bounds, and record where its runtime
// type comes from. The operand, the bounds and the `else` block are judged
// BEFORE the new name enters scope, so none of them can refer to `T`.
function bind_scoped_type(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    stmt: int,
    name: string,
    operand: int,
    else_branch: int?,
) -> void throws never {
    validate_runtime_type_operand(ctx, body, operand);
    let bounds = scoped_type_bounds(ctx, stmt);
    // The statement checks each bound at run time. A miss runs the `else`
    // block, which must diverge like a `let ... else`; a bounded statement
    // without one is reported where it is visited.
    finish_let_else(ctx, body, else_branch);
    // The parameter's identity is its statement's index in the body: exact
    // (two statements never share an index) and source-derived, so it is
    // stable across runs. A scoped parameter never leaves its body, so no
    // cross-body component is needed.
    let binding = ScopedTypeBinding {
        name: name,
        parameter: root.types.ParamTy { index: root.types.SCOPED_PARAM_BIT | stmt, name: name },
        operand: operand,
        bounds: bounds,
    };
    // The bounds join the param env exactly as a declared generic
    // parameter's do: obligations, member lookup, and the written-type
    // well-formedness judgment all read `T`'s conjunction from there.
    if (binding.bounds.length() > 0) {
        ctx.facts.add_bounds(binding.parameter, binding.bounds);
        ctx.lower.add_bounds(binding.parameter, binding.bounds);
    }
    ctx.result.type_bindings.set(stmt, binding);
    ctx.table.bind_scoped_param(binding.parameter);
    ctx.scoped_type_bindings.push(binding);
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::scoped_type_bounds @ d9be6853b
// The written `extends` bounds of a `let type` statement as interface
// constraints. Each is judged like a generic parameter's bound: an
// unresolved name or a `_` reports at the bound, and a type that is not an
// interface (or is `reflect.AnyFunction`) reports and is left out.
function scoped_type_bounds(
    ctx: InferenceContext,
    stmt: int,
) -> root.types.InterfaceConstraint[] throws never {
    let type_refs = ctx.type_refs.stmt_type_binding_bounds.get(stmt)
        ?? return [];
    let bounds: root.types.InterfaceConstraint[] = [];
    for (let type_ref in type_refs) {
        let (let lowered, let diagnostics) = lower_body_type_ref_at(
            ctx,
            type_ref,
            TypePosition.ConstraintHead,
            HolePolicyForbidden { reason: NoInferReason.TypeBinding },
        );
        queue_body_lowering_diagnostics(ctx, diagnostics);
        let diagnosed = root.types.any_node(lowered, (node) -> bool {
            node is root.types.TyError
        });
        let plain = reject_holes(lowered);
        let bound = root.types.as_interface(plain);
        if (bound != null) {
            // As for a generic parameter, the reflection-only function
            // interface is not a bound.
            if (
                root.types.decl_name_is_lang_root_type(
                    bound.name,
                    root.hir.lang_roots(ctx.db),
                    root.base.LangPackage.Reflect,
                    "AnyFunction",
                )
            ) {
                report(
                    ctx,
                    PendingDiagAnnotWf {
                        type_ref: type_ref,
                        error: TirTypeErrorBuiltinInterfaceNotABound { interface_: bound.name },
                    },
                );
            } else {
                bounds.push(bound);
            }
        } else if (!diagnosed) {
            report(
                ctx,
                PendingDiagAnnotWf {
                    type_ref: type_ref,
                    error: TirTypeErrorGenericBoundNotInterface { bound: plain },
                },
            );
        }
    }
    bounds
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish_scoped_type_bindings @ d9be6853b
// Close the `let type T = ...` bindings this block introduced. Nothing typed
// by a closed binding may be observable afterwards: the binding re-executes
// on every pass through its block and may bind `T` to a different type each
// time, so a `T`-typed value that outlived the block could enter a
// container whose element type it no longer satisfies. Hence:
// - the block's VALUE leaves only through an expected type that mentions no
//   closed binding and admits it (`-> unknown`, `let v: unknown = { ... }`),
//   or not at all when the value is discarded; otherwise E0172 at the tail
//   and the `Error` fill;
// - flow narrowings typed by a closed binding end here (the binding reverts
//   to its declared type);
// - the effect channel is judged where it is consumed
//   (`drop_escaping_effects`): a declared clause already judged each
//   contribution at its throw and publishes nothing.
//
// Interior expression and pattern tables keep the rigid identity: MIR binds
// the frame slot from them.
function finish_scoped_type_bindings(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    checkpoint: int,
    block: int,
    tail: int?,
    block_ty: int,
    expected: Expectation,
) -> int throws never {
    if (ctx.scoped_type_bindings.length() == checkpoint) {
        return block_ty;
    }
    let pool = ctx.table.pool;
    let outer_universe = checkpoint;
    let at = tail ?? block;
    let closing = ctx.scoped_type_bindings.slice(checkpoint, ctx.scoped_type_bindings.length()).map((binding) -> root.types.ParamTy {
        binding.parameter
    });
    generalize_closing_scope(ctx, outer_universe, closing, at);
    // After the leak check, not before: the check itself relates types and
    // may refuse one on a road with no anchor, and this block's tail is the
    // last place such a refusal can be reported against the binding it
    // names.
    let escapes = ctx.journals.anchorless_escapes;
    ctx.journals.anchorless_escapes = [];
    for (let escape in escapes) {
        let (let param, let value) = escape;
        if (closing.includes(param)) {
            report_scoped_type_escape(ctx, at, param, value, ScopedTypeEscapeKindInferred {});
        } else {
            ctx.journals.anchorless_escapes.push((param, value));
        }
    }
    root.syntax.truncate(ctx.scoped_type_bindings, checkpoint);
    ctx.table.close_scopes_to(outer_universe);
    let narrowed: (root.hir.BindingId, int)[] = [];
    for (let binding in ctx.flow.keys()) {
        let ty = ctx.flow[binding];
        if (pool.has_typevar(ty) || pool.has_infer(ty)) {
            narrowed.push((binding, ty));
        }
    }
    for (let entry in narrowed) {
        if (escaping_scoped_param(ctx, entry.1) != null) {
            ctx.flow.delete(entry.0);
        }
    }
    let escaped = escaping_scoped_param(ctx, block_ty)
        ?? return block_ty;
    match (expected) {
        // Nobody reads the value, so its slot takes the top type: no reader
        // can observe the binding through it.
        //
        // The top type rather than `null`, which would be a claim: the block
        // DID produce a value of some type, and MIR still lowers the
        // expression that made it. `unknown` says "something, and nobody is
        // looking", which is what a discarded position means; `null` would
        // say the expression yields the unit value and put every later
        // reader of this slot's type at odds with the code. Nothing is erased
        // by it either: the interior tables keep the rigid type, and this
        // fills only the discarded slot.
        ExpectationDiscarded => pool.add(root.types.TyUnknown {}),
        let e: ExpectationHasType => {
            let context = ctx.table.resolve_completely(e.value);
            // Where the unit type is expected the value is not leaving at
            // all: it is one the author did not discard, and reports as
            // that.
            if (tail != null && is_unit_ty(ctx, context)) {
                ctx.unit_positions.set(tail, (value_tail(body, tail), UnitContext.Block));
                check_fits(ctx, tail, block_ty, context);
                return pool.add(root.types.TyError {});
            }
            let vetted = if (escaping_scoped_param(ctx, context) == null) {
                context
            } else {
                null
            };
            publish_scoped_value(ctx, at, escaped, block_ty, vetted)
        },
        ExpectationNone => publish_scoped_value(ctx, at, escaped, block_ty, null),
        // The context is already diagnosed; a second report here would only
        // cascade.
        ExpectationErroneous => pool.add(root.types.TyError {}),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::publish_scoped_value @ d9be6853b
// A value typed by a binding that is closing leaves only through a context
// that admits it and is ground (an open one would SOLVE to the escaping
// type) and that the caller has vetted as free of the closing binding; the
// value then takes the context's type. Otherwise E0172 at `at` and the
// `Error` fill. Shared by a block's tail and a `return`.
function publish_scoped_value(
    ctx: InferenceContext,
    at: int,
    escaped: root.types.ParamTy,
    value: int,
    context: int?,
) -> int throws never {
    if (context != null && !ctx.table.pool.has_infer(context)) {
        let saved_anchor = ctx.obligation_anchor;
        ctx.obligation_anchor = at;
        let fits = sub(ctx, value, context);
        ctx.obligation_anchor = saved_anchor;
        if (fits) {
            return context;
        }
    }
    report_scoped_type_escape(ctx, at, escaped, value, ScopedTypeEscapeKindValue {})
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::frame_scoped_param @ d9be6853b
// The first binding `ty` mentions (through solved variables) that the
// return frame with `floor` opened (at or past `floor` in the binding
// stack) and so closes before the frame publishes its value.
function frame_scoped_param(
    ctx: InferenceContext,
    ty: int,
    floor: int,
) -> root.types.ParamTy? throws never {
    let resolved = ctx.table.resolve_completely(ty);
    let opened = ctx.scoped_type_bindings.slice(floor, ctx.scoped_type_bindings.length());
    let escaped: root.types.ParamTy? = null;
    scoped_params_in(ctx.table.pool, resolved, (param) -> void {
        if (
            escaped == null
                && opened.some((binding) -> bool {
                    binding.parameter == param
                })
        ) {
            escaped = param;
        }
    });
    escaped
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::generalize_closing_scope @ d9be6853b
// rustc's leak check at a scope exit. A variable minted inside the block
// outlives it (as the block's value, in an outer binding's bounds, in a
// deferred obligation), so once the block's parameters die it may not be
// solved to one of them. A variable whose bounds already mention a closing
// parameter IS a value of that parameter and is solved now, while the
// parameter is still open, so the block's value check sees it; every other
// open variable the block minted moves out to the enclosing universe. Then
// every open class is judged once more: a bound naming a parameter the
// class may not take (deposited while the class was still inner, or carried
// into an outer class by a deposit, a union, or an assignment, and decided
// only now) is an escape, reported at the bound's own deposit and filled
// with `Error`. This is the same universe rule the deposit applies eagerly,
// applied at the last moment the bound's anchor is still the right place to
// report.
function generalize_closing_scope(
    ctx: InferenceContext,
    outer_universe: int,
    closing: root.types.ParamTy[],
    at: int,
) -> void throws never {
    while (true) {
        let progressed = false;
        for (let var in ctx.table.unsolved_vars_deeper_than(outer_universe)) {
            let bounds = ctx.table.var_bounds(var);
            let decides_a_closing_param = bounds.lowers.concat(bounds.uppers).some((bound) -> bool {
                closing_param_in(ctx, bound.ty, closing) != null
            });
            if (decides_a_closing_param && try_solve_bounded_var(ctx, var, bounds)) {
                progressed = true;
            }
        }
        if (!progressed) {
            break;
        }
    }
    for (let var in ctx.table.unsolved_vars_deeper_than(outer_universe)) {
        ctx.table.demote_to(var, outer_universe);
    }
    for (let entry in ctx.table.unsolved_bounded_vars()) {
        let (let var, let bounds) = entry;
        let escaped: (root.types.ParamTy, root.hir_ty.infer.Bound)? = null;
        for (let candidate in bounds.lowers.concat(bounds.uppers)) {
            let candidate_param = ctx.table.escaping_scoped_param(var, candidate.ty);
            if (candidate_param != null) {
                escaped = (candidate_param, candidate);
                break;
            }
        }
        if (escaped == null) {
            continue;
        }
        let (let param, let bound) = escaped;
        let value = ctx.table.resolve_completely(bound.ty);
        report_scoped_type_escape(ctx, bound.anchor ?? at, param, value, ScopedTypeEscapeKindInferred {});
        refuse_with_error_fill(ctx, var);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::closing_param_in @ d9be6853b
// The first parameter of `closing` that `ty` mentions through solved
// variables.
function closing_param_in(
    ctx: InferenceContext,
    ty: int,
    closing: root.types.ParamTy[],
) -> root.types.ParamTy? throws never {
    let resolved = ctx.table.resolve_completely(ty);
    let found: root.types.ParamTy? = null;
    scoped_params_in(ctx.table.pool, resolved, (param) -> void {
        if (found == null && closing.includes(param)) {
            found = param;
        }
    });
    found
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::escaping_scoped_param @ d9be6853b
// The first block-scoped parameter `ty` mentions (through solved variables)
// whose binding is no longer in scope.
function escaping_scoped_param(ctx: InferenceContext, ty: int) -> root.types.ParamTy? throws never {
    let resolved = ctx.table.resolve_completely(ty);
    let escaped: root.types.ParamTy? = null;
    scoped_params_in(ctx.table.pool, resolved, (param) -> void {
        if (
            escaped == null
                && !ctx.scoped_type_bindings.some((binding) -> bool {
                    binding.parameter == param
                })
        ) {
            escaped = param;
        }
    });
    escaped
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::refuse_with_error_fill @ d9be6853b
// Fills a class an escape refusal just reported on with `Error`: a solved
// class owes no "cannot infer" of its own, so the refusal's report stands
// alone.
function refuse_with_error_fill(ctx: InferenceContext, var: int) -> void throws never {
    ctx.table.solve(var, ctx.table.pool.add(root.types.TyError {}));
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_scoped_type_escape @ d9be6853b
function report_scoped_type_escape(
    ctx: InferenceContext,
    at: int,
    param: root.types.ParamTy,
    value: int,
    kind: ScopedTypeEscapeKind,
) -> int throws never {
    report(ctx, PendingDiagScopedTypeEscapesBlock { at: at, name: param.name, value: value, kind: kind });
    ctx.table.pool.add(root.types.TyError {})
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::drop_escaping_effects @ d9be6853b
// The effect channel's escape rule: whoever consumes a channel PUBLISHES its
// contributions (an inferred owner or lambda clause as its surface, a
// `catch` as its arms' bindings), so a contribution typed by a scoped
// binding whose block has closed is reported at its throw (E0172) and
// dropped.
//
// `declared` is the clause's own NAMED half, which only a PARTIAL clause
// (`throws X | _`) brings here: a closed clause judged every contribution at
// the throw and publishes nothing, and an omitted one names nothing. A name
// the author wrote that already admits the contribution says everything a
// caller needs, so the surface carries the name and the contribution needs
// no entry of its own: it is not an escape. That is the same verdict, by the
// same relation, that a closed clause reaches at the throw; an open clause
// can only reach it here, where its named half is known. Deciding by the
// relation rather than by the contribution's nearest relaxation is
// equivalent and needs no relaxation: the relaxation is the LEAST supertype
// free of the binding, so it fits a binding-free name exactly when the
// contribution itself does.
function drop_escaping_effects(
    ctx: InferenceContext,
    channel: (int, int)[],
    declared: int?,
) -> (int, int)[] throws never {
    let kept: (int, int)[] = [];
    for (let entry in channel) {
        let (let at, let contribution) = entry;
        let param = escaping_scoped_param(ctx, contribution);
        if (param == null) {
            kept.push((at, contribution));
            continue;
        }
        if (declared != null && declared_name_publishes(ctx, contribution, declared)) {
            continue;
        }
        report_scoped_type_escape(ctx, at, param, contribution, ScopedTypeEscapeKindThrown { relaxation: null });
        // Only the members that NAME the binding are unpublishable. A `throw`
        // of `string | T` still tells the caller a `string` can come out, and
        // dropping the whole contribution would lose that fact from an
        // inferred clause and from a `catch`'s arm set, where a missing fact
        // changes arm reachability rather than just wording.
        let members = match (ctx.table.pool.kinds[ctx.table.resolve_completely(contribution)]) {
            let u: root.types.InferTyUnion => u.members,
            _ => {
                continue;
            },
        };
        let publishable = members.filter((member) -> bool {
            escaping_scoped_param(ctx, member) == null
        });
        if (publishable.length() > 0) {
            kept.push((at, union_of(ctx, publishable)));
        }
    }
    kept
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::declared_name_publishes @ d9be6853b
// Whether the names a clause WROTE already admit `contribution`, so a caller
// reading the surface learns nothing more from the contribution itself.
//
// A clause's open remainder is not a name: `_` is instantiated as an effect
// variable that the body's own contributions fill, so it is stripped before
// the question is asked; otherwise every clause would "admit" everything
// through its own hole. What is left must be ground, or the answer is not
// provable and the contribution is treated as escaping (the conservative
// direction: the author can always widen the name they wrote).
function declared_name_publishes(
    ctx: InferenceContext,
    contribution: int,
    declared: int,
) -> bool throws never {
    let pool = ctx.table.pool;
    let resolved_contribution = ctx.table.resolve_completely(contribution);
    if (pool.has_infer(resolved_contribution)) {
        return false;
    }
    let resolved_declared = ctx.table.resolve_completely(declared);
    let named = match (pool.kinds[resolved_declared]) {
        let u: root.types.InferTyUnion => {
            let named_members = u.members.filter((member) -> bool {
                !pool.has_infer(member)
            });
            if (named_members.length() == 0) {
                return false;
            }
            union_of(ctx, named_members)
        },
        _ => resolved_declared,
    };
    !pool.has_infer(named)
        && !pool.has_error(named)
        && cached_subtype(ctx, resolved_contribution, named)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::scoped_type_params @ d9be6853b
function scoped_type_params(ctx: InferenceContext) -> root.types.ParamTy[] throws never {
    ctx.scoped_type_bindings.map((binding) -> root.types.ParamTy {
        binding.parameter
    })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::scoped_type_param_heads @ d9be6853b
// Whether a lexical name claims the head of a path (a body `type` binding or
// a generic parameter in scope) and so shadows every item and package of
// that spelling, as in Rust. The one answer every path form reads: type
// paths, value paths, constructors, patterns. Nothing shadows a package the
// compiler named by identity.
function scoped_type_param_heads(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
) -> bool throws never {
    match (head) {
        root.hir.PathHeadLang => false,
        root.hir.PathHeadPackage | root.hir.PathHeadPlain => {
            let name = segments.at(0)
                ?? return false;
            scoped_type_param(ctx, name) != null || ctx.lower.lexical_generic(name) != null
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::scoped_type_param @ d9be6853b
function scoped_type_param(
    ctx: InferenceContext,
    name: string,
) -> root.types.ParamTy? throws never {
    ctx.scoped_type_bindings
        .find_last((binding) -> bool {
            binding.name == name
        })
        ?.parameter
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lower_scoped_type_ref_at @ d9be6853b
// Lower a body-owned type reference through the lexical `let type T = ...`
// overlay, so a scoped name resolves to its rigid parameter.
function lower_scoped_type_ref_at(
    ctx: InferenceContext,
    store: root.hir.TypeRefStore,
    type_ref: int,
    position: TypePosition,
    holes: HolePolicy,
) -> (root.types.LoweringTy, LoweringDiag[]) throws never {
    ctx.lower.lower_type_ref_with_overlay_and_diagnostics(
        store,
        type_ref,
        position,
        scoped_type_params(ctx),
        holes,
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::queue_body_lowering_diagnostics @ d9be6853b
function queue_body_lowering_diagnostics(
    ctx: InferenceContext,
    diagnostics: LoweringDiag[],
) -> void throws never {
    for (let diagnostic in diagnostics) {
        ctx.journals.pending_diags.push(
            PendingDiagBodyAnnot {
                type_ref: ctx.type_refs.diagnostic_id(diagnostic.type_ref),
                kind: diagnostic.kind,
            },
        );
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lower_body_type_ref_at @ d9be6853b
// Lower a body type reference at `position`; `holes` says whether the
// position has something to infer a `_` from (a `let` annotation does, a
// `let type T extends I = ...` bound does not).
function lower_body_type_ref_at(
    ctx: InferenceContext,
    type_ref: root.hir.BodyTypeRefId,
    position: TypePosition,
    holes: HolePolicy,
) -> (root.types.LoweringTy, LoweringDiag[]) throws never {
    let type_refs = ctx.type_refs;
    lower_scoped_type_ref_at(ctx, type_refs.store, type_refs.raw_id(type_ref), position, holes)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lower_scoped_type_path @ d9be6853b
function lower_scoped_type_path(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
) -> root.types.LoweringTy throws never {
    ctx.lower.lower_type_path_with_overlay(head, segments, scoped_type_params(ctx))
}

// port: baml_compiler2_hir_ty/src/infer.rs::RelaxationVariance @ d9be6853b
// The direction a position relates to the value it describes, for
// `nearest_scoped_relaxation`: a `throws` clause (like a return) is a
// supertype of what is thrown; a function type's parameters flip it.
enum RelaxationVariance {
    Covariant,
    Contravariant,
}

// port: baml_compiler2_hir_ty/src/infer.rs::RelaxationVariance::flip @ d9be6853b
function relaxation_variance_flip(
    relaxation_variance: RelaxationVariance,
) -> RelaxationVariance throws never {
    match (relaxation_variance) {
        RelaxationVariance.Covariant => RelaxationVariance.Contravariant,
        RelaxationVariance.Contravariant => RelaxationVariance.Covariant,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::RelaxationVariance::bound @ d9be6853b
// The type a bare block-scoped parameter relaxes to in this direction.
function relaxation_variance_bound(
    relaxation_variance: RelaxationVariance,
) -> root.types.Ty throws never {
    match (relaxation_variance) {
        RelaxationVariance.Covariant => root.types.TyUnknown {},
        RelaxationVariance.Contravariant => root.types.TyNever {},
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::nearest_scoped_relaxation @ d9be6853b
// The nearest type free of block-scoped parameters that still relates to
// `ty` in `variance`'s direction (a supertype when covariant, a subtype when
// contravariant), following the subtyping rules: a bare parameter becomes
// the direction's bound (`unknown`, or `never` under a function
// parameter); a union relaxes its members and simplifies (`T | int` ->
// `unknown`; under a parameter, `(T | int) -> void` -> `(int) -> void`); a
// function flips the direction for its parameters and keeps it for the
// return and throws (`() -> T throws T` -> `() -> unknown throws unknown`);
// mention inside collapses it whole (`T[]` -> `unknown`).
//
// This is what a clause outside the block may say about a value typed by
// the binding; it is never applied for the author: they write it.
function nearest_scoped_relaxation(
    ty: root.types.Ty,
    variance: RelaxationVariance,
) -> root.types.Ty throws never {
    if (!mentions_scoped_param(ty)) {
        return ty;
    }
    match (ty) {
        root.types.TyTypeVar => relaxation_variance_bound(variance),
        let u: root.types.TyUnion => {
            let flat: root.types.Ty[] = [];
            let push = (member: root.types.Ty) -> void {
                if (!flat.includes(member)) {
                    flat.push(member);
                }
            };
            for (let member in u.members) {
                let relaxed = nearest_scoped_relaxation(member, variance);
                match (relaxed) {
                    // The top type absorbs the union; the bottom type
                    // vanishes from it.
                    root.types.TyUnknown => {
                        return relaxed;
                    },
                    root.types.TyNever => {},
                    let inner: root.types.TyUnion => {
                        for (let inner_member in inner.members) {
                            push(inner_member);
                        }
                    },
                    _ => push(relaxed),
                }
            }
            match (flat.length()) {
                0 => root.types.TyNever {},
                1 => flat[0],
                _ => root.types.TyUnion { members: flat },
            }
        },
        let f: root.types.TyFunction => {
            root.types.TyFunction {
                params: f.params.map((param) -> root.types.FunctionParamTy {
                    root.types.FunctionParamTy {
                        name: param.name,
                        ty: nearest_scoped_relaxation(param.ty, relaxation_variance_flip(variance)),
                        mode: param.mode,
                    }
                }),
                ret: nearest_scoped_relaxation(f.ret, variance),
                throws_: nearest_scoped_relaxation(f.throws_, variance),
            }
        },
        root.types.TyTuple
            | root.types.TyClass
            | root.types.TyInterface
            | root.types.TyList
            | root.types.TyMap
            | root.types.TyFuture
            | root.types.TyAssociatedTypeProjection =>
        {
            relaxation_variance_bound(variance)
        },
        // Leaves cannot mention a parameter; the guard above returns them.
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.TyLiteral
            | root.types.TyEnum
            | root.types.TyEnumVariant
            | root.types.TyRustType
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst
            | root.types.TyTypeAlias
            | root.types.TyUnknown
            | root.types.TyNever
            | root.types.TyError =>
        {
            ty
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::scoped_params_in @ d9be6853b
// Every block-scoped parameter (`let type T = ...`, marked by
// `SCOPED_PARAM_BIT`) that `ty` mentions, in walk order.
function scoped_params_in(
    pool: root.types.InferPool,
    ty: int,
    visit: (root.types.ParamTy) -> void throws never,
) -> void throws never {
    if (!pool.has_typevar(ty)) {
        return;
    }
    let kind = pool.kinds[ty];
    if let v: root.types.TyTypeVar = kind {
        if (v.param.is_scoped()) {
            visit(v.param);
        }
    }
    for (let child in root.types.children_infer_ty(kind)) {
        scoped_params_in(pool, child, visit);
    }
}
