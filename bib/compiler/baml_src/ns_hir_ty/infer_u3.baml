// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 3, calls: `infer_call` and the passes around it, argument
// matching (`check_call_args`), the callee roads (`infer_callee`,
// `member_callee`, `interface_member_callee`, the `default.` receiver) and
// the unspecialized generic method value report. Lambdas, instantiation and
// generic arguments are in infer_u3_lambda.baml; the context helpers,
// expectation shapes and writeback recorders in infer_u3_helpers.baml.
//
// Restructured (BAML forces it):
// - `InferenceContext` methods are free functions taking `ctx` first.
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so every `FunctionRef` is its Source lane, a function loc `int`, and the
//   `DeclRef::External` arms are dropped. With them goes
//   `report_mounted_reserved_call`, which reports only for an External
//   callee.
// - The large functions are split along Rust's own blocks:
//   `check_call_args` (`check_call_args_not_callable`,
//   `check_call_args_arity`), `infer_callee` (`infer_callee_item_path`,
//   `infer_callee_receiver`) and `member_callee` (`member_callee_union`,
//   `member_callee_non_inherent`).
//
// Not ported (one-line forwards or accessors; the call sites read the
// target directly): `lang` (`root.hir.lang_roots(ctx.db)`), `viewpoint`
// (`Viewpoint.for_file(ctx.db, ctx.owner_file)`), `viewer`
// (`root.hir.file_package(ctx.db, ctx.owner_file).root_id`),
// `interface_short_name` (`root.hir.interface_data(ctx.db, i).name`),
// `expand_alias_ty` (`expand_alias_head(ctx.table.pool, ty, ctx.facts)`),
// `write_member_resolution` (`ctx.result.member_resolutions[expr] = r`) and
// `instantiation_args` (`instantiation_args_at` at its default position).

// The legacy `baml.llm` helpers whose schema parameter
// `seed_implicit_llm_schema` seeds (Rust's repeated `matches!` list).
const LEGACY_LLM_HELPERS: string[] = ["render_prompt", "build_request", "build_request_stream"];

// Rust's `u32::MAX`: the largest member spelling `member_callee` reads as a
// tuple index.
const U32_MAX: int = 4294967295;

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_call @ d9be6853b
// Call typing: direct calls to resolved functions instantiate the signature
// (explicit turbofish args, else fresh variables per generic param);
// calls through function-typed values check against the value's type. Two
// argument passes: non-lambda args first, so lambda signatures can be
// deduced from already-resolved param types.
function infer_call(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
    args: root.ast.CallArg[],
) -> int throws never {
    let (let callee_fn_ty, let bound_receiver) = infer_callee(ctx, body, call, callee);
    seed_implicit_llm_schema(ctx, body, call, callee, args);
    let ret = check_call_args(ctx, body, call, callee, callee_fn_ty, bound_receiver, args);
    report_constant_regex_pattern(ctx, body, call, callee);
    default_uncontracted_session_eval(ctx, body, call, callee);
    ret
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::is_regex_new @ d9be6853b
// Whether `callee` names `baml.regex.new`: a `Free { func }` resolution
// whose function is the one `baml.regex.new` resolves to.
function is_regex_new(ctx: InferenceContext, callee: int) -> bool throws never {
    let func = match (ctx.result.callee_resolution(callee)) {
        let free: MemberResolutionFree => free.func,
        _ => {
            return false;
        },
    };
    match (lang_value(ctx, root.base.LangPackage.Baml, ["regex"], "new")) {
        let value: ResolvedValueSource => {
            match (value.value) {
                let target: root.hir.DefinitionFunction => target.value == func,
                _ => false,
            }
        },
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_constant_regex_pattern @ d9be6853b
// Compile a constant `baml.regex.new` pattern now, so a typo in a literal is
// a source diagnostic instead of a throw the program has to reach. The check
// goes through the same compiler the runtime uses (`baml.regex.new`), so a
// pattern accepted here is accepted there, with the same classification and
// message. A dynamically built pattern is left alone.
// Restructured: Rust's `sys_regex::Program::compile` is `baml.regex.new`,
// whose `span_start` already counts characters (Rust's `char_offsets`).
function report_constant_regex_pattern(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
) -> void throws never {
    // Use the same parameter bindings as lowering, including reordered named
    // arguments. An unbound duplicate must not replace the pattern or dialect
    // that the call will actually use.
    let plan = ctx.result.call_plans.get(call);
    if (plan == null) {
        return;
    }
    let bindings = plan.bindings;
    let provided = (index: int) -> int? {
        bindings
            .filter_map((binding) -> {
                match (binding) {
                    let p: ParamBindingProvided if p.param_index == index => p.arg,
                    _ => null,
                }
            })
            .at(0)
    };
    let expr = provided(0);
    let backtracking_arg = provided(1);
    if (expr == null) {
        return;
    }
    let pattern = match (body.exprs[expr]) {
        let literal: root.ast.ExprLiteral => {
            match (literal.value) {
                let s: root.base.LiteralString => s.value,
                _ => {
                    return;
                },
            }
        },
        _ => {
            return;
        },
    };
    if (!is_regex_new(ctx, callee)) {
        return;
    }
    // The dialect follows the `backtracking` argument when it is itself
    // constant. When it is computed, only a pattern both dialects reject is
    // reported.
    let backtracking: bool? = if (backtracking_arg == null) {
        false
    } else {
        match (body.exprs[backtracking_arg]) {
            let literal: root.ast.ExprLiteral => {
                match (literal.value) {
                    let b: root.base.LiteralBool => b.value,
                    _ => null,
                }
            },
            _ => null,
        }
    };
    let compile = (dialect: bool) -> baml.regex.Error? {
        baml.regex.new(pattern, backtracking = dialect) catch (e) {
            baml.regex.Error => {
                return e;
            },
        };
        null
    };
    let error = if (backtracking != null) {
        compile(backtracking)
    } else if (compile(false) != null) {
        compile(true)
    } else {
        null
    };
    if (error == null) {
        return;
    }
    report(
        ctx,
        PendingDiagInvalidRegexPattern {
            expr: expr,
            kind: error.kind,
            message: error.message,
            offset: error.span_start,
        },
    );
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_call_site_builtin_values @ d9be6853b
// A builtin lowered where it is called (`log.info`, `baml.spawn.__spawn`,
// ...) has no function value, so every reference to one that is not a
// direct call's callee is refused. Judged over the resolution tables MIR
// lowers from, so no value road can miss it.
function report_call_site_builtin_values(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
) -> void throws never {
    let callees: map<int, bool> = {};
    for (let expr in body.exprs) {
        match (expr) {
            // A specialization called through parentheses (`(f<T>)(x)`) is a
            // value that is then called; the direct spelling puts the type
            // arguments on the call (`f<T>(x)`).
            let call: root.ast.ExprCall
                if !(body.exprs[call.callee] is root.ast.ExprGenericApply) => {
                callees[call.callee] = true;
            },
            // A tagged template calls its tag; which functions may be tags is
            // the template's own check.
            let template: root.ast.ExprTemplate => {
                match (template.tag) {
                    let custom: root.ast.TemplateTagCustom => {
                        callees[custom.tag] = true;
                    },
                    root.ast.TemplateTagDefault => {},
                }
            },
            _ => {},
        }
    }
    let values: int[] = [];
    let consider = (expr: int, resolution: WorkingMemberResolution) -> void {
        if (callees.has(expr)) {
            return;
        }
        let callable = member_resolution_callable<int>(resolution, ctx.db);
        if (callable == null) {
            return;
        }
        let kind = function_signature_ty(ctx.db, callable).builtin_kind;
        if (kind != null && root.ast.builtin_kind_lowers_at_call_site(kind)) {
            values.push(expr);
        }
    };
    for (let expr in ctx.result.member_resolutions.keys()) {
        consider(expr, ctx.result.member_resolutions[expr]);
    }
    for (let expr in ctx.result.path_resolutions.keys()) {
        let resolution = ctx.result.path_resolutions[expr].final_member_resolution();
        if (resolution != null) {
            consider(expr, resolution);
        }
    }
    let sorted = values.sort_by_key((expr) -> {
        expr
    });
    for (let i = 0; i < sorted.length(); i += 1) {
        if (i > 0 && sorted[i - 1] == sorted[i]) {
            continue;
        }
        report(
            ctx,
            PendingDiagCallSiteBuiltinValue {
                expr: sorted[i],
                reference: body.display_expr(sorted[i]),
            },
        );
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::validate_runtime_type_operand @ d9be6853b
// A `let type` operand: inferred once, then checked against the operand
// contract `reflect.Type | reflect.TypeView`.
function validate_runtime_type_operand(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    operand: int,
) -> void throws never {
    if (ctx.validated_runtime_operands.has(operand)) {
        return;
    }
    ctx.validated_runtime_operands[operand] = true;
    let got = infer_expr(ctx, body, operand, ExpectationNone {});
    let pool = ctx.table.pool;
    // A diagnosed operand stays quiet. Nothing else is exempt: an `unknown`
    // must be narrowed to a type with `match` or `is` before it binds. An
    // open operand deposits the contract as a bound and is re-judged once it
    // solves.
    if (pool.has_error(got)) {
        return;
    }
    // A builder's pending type is not a type until the builder is built; it
    // gets its own message naming the fix.
    let pending_type = match (pool.kinds[got]) {
        let class_: root.types.InferTyClass => {
            lang_decl(ctx, root.base.LangPackage.Reflect, ["class"], "PendingType") == class_.name
        },
        _ => false,
    };
    if (pending_type) {
        report(ctx, PendingDiagLetTypePendingOperand { expr: operand });
        return;
    }
    // The operand contract is `reflect.Type | reflect.TypeView`: a kind view
    // is accepted and converts to the `type` value it wraps at the VM's
    // type-operand boundary, never a subtyping edge.
    let expected = pool.add(
        root.types.InferTyUnion {
            members: [
                pool.add(root.types.TyType {}),
                lang_interface_ty(ctx, root.base.LangPackage.Reflect, [], "TypeView"),
            ],
        },
    );
    // The ordinary checking road: a ground mismatch is recorded here, an open
    // operand is re-judged at finish once its variable solves.
    check_inferred(ctx, operand, got, expected);
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::seed_implicit_llm_schema @ d9be6853b
// Seed the otherwise-unconstrained schema parameter of the three legacy
// `baml.llm` helper functions from their named, non-generic LLM target.
function seed_implicit_llm_schema(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
    args: root.ast.CallArg[],
) -> void throws never {
    let callee_name: string? = match (body.exprs[callee]) {
        let path: root.ast.ExprPath => path.value.segments.at(path.value.segments.length() - 1),
        let access: root.ast.ExprMemberAccess => access.member,
        let access: root.ast.ExprOptionalMemberAccess => access.member,
        _ => null,
    };
    if (callee_name == null || !LEGACY_LLM_HELPERS.includes(callee_name)) {
        return;
    }
    if (ctx.type_refs.expr_type_args.has(call)) {
        return;
    }
    let func = match (ctx.result.member_resolutions.get(callee)) {
        let free: MemberResolutionFree => free.func,
        _ => {
            return;
        },
    };
    let package = root.hir.file_package(ctx.db, ctx.db.function_locs.get(func).file);
    let data = root.hir.function_data(ctx.db, func);
    if (
        !root.hir.lang_roots(ctx.db).is_(root.base.LangPackage.Baml, package.root_id)
            || package.namespace_path != ["llm"]
            || !LEGACY_LLM_HELPERS.includes(data.name)
    ) {
        return;
    }
    let signature = function_signature_with_diagnostics(ctx.db, func).signature;
    let writable = signature.generic_params.filter((param) -> {
        !root.types.is_synthetic_effect_param(param.name)
    });
    if (writable.length() != 1) {
        return;
    }
    let schema_param = writable[0];
    let function_name_arg = args.find((arg) -> {
        arg.label == "function_name"
    })
        ?? args.at(1);
    if (function_name_arg == null) {
        return;
    }
    let function_name = match (body.exprs[function_name_arg.expr]) {
        let literal: root.ast.ExprLiteral => {
            match (literal.value) {
                let s: root.base.LiteralString => s.value,
                _ => {
                    return;
                },
            }
        },
        _ => {
            return;
        },
    };
    let path = function_name.split(".");
    let target = match (ctx.lower.resolve_value(ctx.lower.path_head(path), path)) {
        let value: ResolvedValueSource => {
            match (value.value) {
                let f: root.hir.DefinitionFunction => f.value,
                _ => {
                    return;
                },
            }
        },
        _ => {
            return;
        },
    };
    if (
        root.hir.function_llm_meta(ctx.db, target) == null
            || root.hir.function_data(ctx.db, target).generic_params.length() > 0
    ) {
        return;
    }
    let target_ret = function_signature_with_diagnostics(ctx.db, target).signature.ret;
    let ret_has_error = root.types.contains_ty_where(target_ret, (node) -> {
        node is root.types.TyError
    });
    if (ret_has_error || target_ret is root.types.TyUnknown) {
        return;
    }
    let schema_arg = ctx.result.call_plans.get(call)?.type_args.at(schema_param.index);
    if (schema_arg == null) {
        return;
    }
    ctx.table.unify(schema_arg, ctx.table.pool.from_plain(target_ret)) catch (e) {
        root.hir_ty.infer.UnifyError => {},
    };
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::default_uncontracted_session_eval @ d9be6853b
// `reflect.Session.eval(..)` without written type arguments: its first own
// generic, left open, defaults to `unknown`.
function default_uncontracted_session_eval(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
) -> void throws never {
    let callee_name: string? = match (body.exprs[callee]) {
        let path: root.ast.ExprPath => path.value.segments.at(path.value.segments.length() - 1),
        let access: root.ast.ExprMemberAccess => access.member,
        let access: root.ast.ExprOptionalMemberAccess => access.member,
        _ => null,
    };
    if (callee_name != "eval") {
        return;
    }
    if (ctx.type_refs.expr_type_args.has(call)) {
        return;
    }
    let func = match (ctx.result.member_resolutions.get(callee)) {
        let method: MemberResolutionMethod<int> if method.receiver == Receiver.Bound => {
            match (method.callee) {
                let inherent: MethodCalleeInherent => inherent.value,
                _ => {
                    return;
                },
            }
        },
        _ => {
            return;
        },
    };
    let qtn = callable_owner_type(ctx.db, func);
    if (qtn == null) {
        return;
    }
    if (
        !root.hir.lang_roots(ctx.db).is_(root.base.LangPackage.Reflect, qtn.pkg)
            || qtn.namespace.length() > 0
            || qtn.name != "Session"
            || root.hir.function_data(ctx.db, func).name != "eval"
    ) {
        return;
    }
    let generic_params = function_signature_with_diagnostics(ctx.db, func).signature.generic_params;
    let owner_count = callable_generic_frame(ctx.db, func).own_start;
    let own_index = generic_params.slice(owner_count, generic_params.length()).find_index((param) -> {
        !root.types.is_synthetic_effect_param(param.name)
    });
    if (own_index == null) {
        return;
    }
    let arg = ctx.result.call_plans.get(call)?.type_args.at(owner_count + own_index);
    if (arg == null) {
        return;
    }
    if (ctx.table.pool.has_infer(arg)) {
        ctx.table.unify(arg, ctx.table.pool.add(root.types.TyUnknown {})) catch (e) {
            root.hir_ty.infer.UnifyError => {},
        };
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_call_args @ d9be6853b
// The argument/return half of a call, shared by ordinary calls and `?.()`
// (which strips the callee's null first): labeled args match by name,
// lambdas check in the second pass, the callee's throws join the effect
// channel.
function check_call_args(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
    callee_fn_ty: int,
    bound_receiver: bool,
    args: root.ast.CallArg[],
) -> int throws never {
    let pool = ctx.table.pool;
    let seen_trace = false;
    let ordinary_args: root.ast.CallArg[] = [];
    for (let arg in args) {
        if (arg.label == "$trace") {
            if (seen_trace) {
                report(ctx, PendingDiagDuplicateNamedArg { expr: arg.expr, name: "$trace" });
            }
            seen_trace = true;
            let trace_root = root.hir.lang_roots(ctx.db).get(root.base.LangPackage.Trace);
            let expected = if (trace_root != null) {
                let trace_pkg: int = trace_root;
                syntactic_union(
                    pool,
                    ["Options", "ReservedSpan"].map((name) -> {
                        pool.add(
                            root.types.InferTyClass {
                                name: root.types.DeclName { pkg: trace_pkg, namespace: [], name: name },
                                args: [],
                            },
                        )
                    }),
                )
            } else {
                pool.add(root.types.TyError {})
            };
            check_expr(ctx, body, arg.expr, expected);
        } else {
            if (seen_trace && arg.label == null) {
                report(ctx, PendingDiagPositionalAfterNamed { expr: arg.expr });
            }
            ordinary_args.push(arg);
        }
    }
    if (seen_trace) {
        let resolution = ctx.result.callee_resolution(callee);
        let callable = if (resolution != null) {
            member_resolution_callable<int>(resolution, ctx.db)
        } else {
            null
        };
        if (
            callable != null
                && root.hir.function_body(ctx.db, callable) is root.hir.FunctionBodyBuiltin
        ) {
            report(ctx, PendingDiagTraceUnsupportedCall { expr: call });
        }
    }
    // The call is a STRUCTURE demand on the callee (rustc's `check_call`
    // structurally resolves before matching callability).
    let callee_ty = structurally_resolve(ctx, callee_fn_ty);
    let function_ = match (pool.kinds[callee_ty]) {
        let f: root.types.InferTyFunction => f,
        _ => {
            return check_call_args_not_callable(ctx, body, callee, callee_ty, ordinary_args);
        },
    };
    record_throw(ctx, callee, function_.throws_);
    // A bound method call: the receiver already fills the `self` slot, so
    // written arguments match against the remaining parameters.
    let skip = if (bound_receiver && function_.params.length() > 0) {
        1
    } else {
        0
    };
    let params = function_.params.slice(skip, function_.params.length());
    let ret = function_.ret;
    let position = (index: int) -> int? {
        if (index < params.length()) {
            index
        } else {
            null
        }
    };
    // Labels select parameters by name; unlabeled arguments fill
    // positionally. An unknown label falls back to its position for type
    // checking only.
    let matched = baml.Array.generate(ordinary_args.length(), (index) -> int? {
        let label = ordinary_args[index].label;
        if (label == null) {
            return position(index);
        }
        params.find_index((param) -> {
            param.name == label
        })
            ?? position(index)
    });
    // An UNKNOWN label's positional fallback types the value but never FILLS
    // the parameter: both the unknown-label and missing-required diagnostics
    // report.
    let label_fallback = ordinary_args.map((arg) -> {
        let label = arg.label;
        label != null
            && !params.some((param) -> {
                param.name == label
            })
    });
    for (let pass in [0, 1]) {
        for (let index = 0; index < ordinary_args.length(); index += 1) {
            let arg = ordinary_args[index];
            if ((pass == 0) == (body.exprs[arg.expr] is root.ast.ExprLambda)) {
                continue;
            }
            let param_index = matched[index];
            if (param_index != null) {
                check_expr(ctx, body, arg.expr, params[param_index].ty);
            } else {
                // Extra argument: the arity diagnostic reports it.
                infer_expr(ctx, body, arg.expr, ExpectationNone {});
            }
        }
    }
    // Parameter-ordered bindings: provided slots from the matching, omitted
    // OPTIONAL slots as defaults (required gaps get no entry).
    let slots: (int | null)[] = baml.Array.filled(params.length(), null);
    for (let index = 0; index < ordinary_args.length(); index += 1) {
        let param_index = matched[index];
        if (param_index != null && slots[param_index] == null && !label_fallback[index]) {
            slots[param_index] = ordinary_args[index].expr;
        }
    }
    check_call_args_arity(ctx, call, ordinary_args, params, matched, label_fallback, slots);
    let bindings: ParamBinding[] = [];
    for (let param_index = 0; param_index < params.length(); param_index += 1) {
        let slot = slots[param_index];
        let param_name = params[param_index].name;
        if (slot != null) {
            bindings.push(ParamBindingProvided { param_index: param_index, arg: slot });
        } else if (params[param_index].mode == root.types.FunctionParamMode.Optional && param_name != null) {
            bindings.push(
                ParamBindingOmittedDefault { param_index: param_index, param_name: param_name },
            );
        }
    }
    let plan = ctx.result.call_plans.get_or_insert(call, CallPlan.default());
    plan.argument_layout
        = root.types.CallLayout.from_modes(
            params.map((param) -> {
                (param.name, param.mode)
            }),
        );
    plan.bindings = bindings;
    ret
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_call_args @ d9be6853b
// (the not-callable arm) Not callable (or not yet typed): visit the args,
// sentinel out. A callee already carrying error/vars is a cascade, not a
// second finding, except a union whose error members are mere recovery
// arms: the concrete remainder is still provably not callable (E0006). A
// value typed `unknown` is not callable, and saying so is this diagnostic's
// whole job.
function check_call_args_not_callable(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    callee: int,
    callee_ty: int,
    args: root.ast.CallArg[],
) -> int throws never {
    let pool = ctx.table.pool;
    if (!pool.has_error(callee_ty) && !pool.has_infer(callee_ty)) {
        report(ctx, PendingDiagNotCallable { expr: callee, ty: callee_ty });
    } else {
        match (pool.kinds[callee_ty]) {
            let union_: root.types.InferTyUnion => {
                let clean = union_.members.filter((member) -> {
                    !pool.has_error(member)
                });
                let all_uncallable = clean.every((member) -> {
                    !pool.has_infer(member)
                        && match (pool.kinds[member]) {
                            root.types.InferTyFunction | root.types.TyUnknown => false,
                            _ => true,
                        }
                });
                if (clean.length() > 0 && all_uncallable) {
                    report(ctx, PendingDiagNotCallable { expr: callee, ty: syntactic_union(pool, clean) });
                }
            },
            _ => {},
        }
    }
    for (let arg in args) {
        infer_expr(ctx, body, arg.expr, ExpectationNone {});
    }
    pool.add(root.types.TyError {})
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_call_args @ d9be6853b
// (the arity and argument-form block) Arity against the parameter list,
// then the argument-form rules: a positional argument after a named one; a
// DEFAULTED parameter supplied positionally (by-name only); a repeated
// name; an unknown name.
function check_call_args_arity(
    ctx: InferenceContext,
    call: int,
    args: root.ast.CallArg[],
    params: root.types.InferFunctionParamTy[],
    matched: (int | null)[],
    label_fallback: bool[],
    slots: (int | null)[],
) -> void throws never {
    let provided = args.length();
    let required = params
        .filter((param) -> {
            param.mode == root.types.FunctionParamMode.Required
        })
        .length();
    let reports_before = ctx.journals.pending_diags.length();
    if (provided > params.length()) {
        report(ctx, PendingDiagArgCountMismatch { expr: call, expected: params.length(), got: provided });
    } else {
        let saw_named = args.some((arg) -> {
            arg.label != null
        });
        let unfilled: int[] = [];
        for (let param_index = 0; param_index < params.length(); param_index += 1) {
            if (
                params[param_index].mode == root.types.FunctionParamMode.Required
                    && slots[param_index] == null
            ) {
                unfilled.push(param_index);
            }
        }
        if (unfilled.length() > 0) {
            if (saw_named) {
                // A named call reports each missing parameter BY NAME (the
                // count would misread as positional).
                for (let param_index in unfilled) {
                    let name = params[param_index].name;
                    if (name != null) {
                        report(ctx, PendingDiagMissingNamedArg { expr: call, name: name });
                    } else {
                        report(
                            ctx,
                            PendingDiagArgCountMismatch {
                                expr: call,
                                expected: required,
                                got: provided,
                            },
                        );
                        break;
                    }
                }
            } else {
                report(ctx, PendingDiagArgCountMismatch { expr: call, expected: required, got: provided });
            }
        }
    }
    if (ctx.journals.pending_diags.length() > reports_before) {
        // The arity report owns every class the parameters carry: a slot only
        // a missing argument would have determined is its cascade.
        for (let param in params) {
            ctx.table.taint_vars_in(param.ty);
        }
    }
    let seen_named = false;
    let seen_labels: string[] = [];
    for (let index = 0; index < args.length(); index += 1) {
        let arg = args[index];
        let label = arg.label;
        let param_index = matched[index];
        if (label != null) {
            // A named argument can also duplicate a parameter already supplied
            // positionally. Report it once, including when the label itself
            // was repeated.
            let first = if (param_index != null) {
                slots[param_index]
            } else {
                null
            };
            let duplicates_binding = !label_fallback[index] && first != null && first != arg.expr;
            if (seen_labels.includes(label) || duplicates_binding) {
                report(ctx, PendingDiagDuplicateNamedArg { expr: arg.expr, name: label });
            }
            seen_labels.push(label);
            seen_named = true;
        } else if (seen_named) {
            report(ctx, PendingDiagPositionalAfterNamed { expr: arg.expr });
        } else if (param_index != null && params[param_index].mode == root.types.FunctionParamMode.Optional) {
            let name = params[param_index].name;
            if (name != null) {
                report(ctx, PendingDiagPositionalDefaultedArg { expr: arg.expr, name: name });
            }
        }
    }
    for (let arg in args) {
        let label = arg.label;
        if (label != null) {
            let name: string = label;
            let declared = params.some((param) -> {
                param.name == name
            });
            if (!declared) {
                report(ctx, PendingDiagUnknownNamedArg { expr: call, name: name });
            }
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_callee @ d9be6853b
// The callee's (instantiated) function type, plus whether its first
// parameter is already bound to a receiver (`xs.push(1)` checks `1` against
// `item`, not `self`). Direct function references and type-qualified method
// paths instantiate here because their instantiation reads the CALL site's
// turbofish, which a bare value does not have; bound method callees resolve
// through `method_resolution`; everything else is whatever the expression
// infers to.
function infer_callee(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
) -> (int, bool) throws never {
    let callee_expr = body.exprs[callee];
    // A FULLY-qualified direct call (`(Box as Sized).pick(a, b)`): the call
    // site supplies the turbofish, and `self` stays the written first
    // argument (no bound receiver), the UFCS shape.
    match (callee_expr) {
        let qualified: root.ast.ExprQualifiedPath => {
            let fn_ty = qualified_path_value(ctx, callee, qualified.member, OwnArgsCall { value: call }, callee);
            ctx.result.type_of_expr[callee] = fn_ty;
            return (fn_ty, false);
        },
        _ => {},
    }
    let segments: string[]? = match (callee_expr) {
        let path: root.ast.ExprPath => path.value.segments,
        _ => null,
    };
    if (segments != null) {
        // An INTERFACE-qualified direct call (`IqDescribable.describe(t)`):
        // turbofish-aware instantiation with bounds registered.
        if (
            segments.length() >= 2
                && (
                    !path_resolves_locally(ctx, callee)
                        || qualified_path_root_is_top_level_let(ctx, segments)
                )
        ) {
            let head = item_head(ctx, callee, segments);
            let fn_ty = interface_static_value(
                ctx,
                head,
                segments.slice(0, segments.length() - 1),
                segments[segments.length() - 1],
                OwnArgsCall { value: call },
                call,
                callee,
            );
            if (fn_ty != null) {
                ctx.result.type_of_expr[callee] = fn_ty;
                return (fn_ty, false);
            }
        }
        // `default.m(..)` inside an `implements` block: delegation to the
        // interface's DEFAULT implementation, resolved from the body owner.
        // A local named `default` shadows it.
        if (segments.length() == 2 && segments[0] == "default" && !path_resolves_locally(ctx, callee)) {
            let interface_member = default_member(ctx, segments[1]);
            if (interface_member != null) {
                let (let ty, let bound) = interface_member_callee(ctx, interface_member, call, true);
                ctx.result.type_of_expr[callee] = ty;
                return (ty, bound);
            }
        }
        let direct = infer_callee_item_path(ctx, call, callee, segments);
        if (direct != null) {
            return direct;
        }
    }
    infer_callee_receiver(ctx, body, call, callee)
        ?? (infer_expr(ctx, body, callee, ExpectationNone {}), false)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_callee @ d9be6853b
// (the item-path block) A path that names a function is a direct call; a
// type-qualified method path (`Array.filled(3, 0)`) calls a static, or an
// instance method in UFCS spelling. Null when the path is none of these.
function infer_callee_item_path(
    ctx: InferenceContext,
    call: int,
    callee: int,
    segments: string[],
) -> (int, bool)? throws never {
    if (path_resolves_locally(ctx, callee) && !qualified_path_root_is_top_level_let(ctx, segments)) {
        return null;
    }
    let written_head = item_head(ctx, callee, segments);
    if (template_param_heads(ctx, written_head, segments)) {
        return null;
    }
    // A type parameter or scoped `type` binding at the head shadows every
    // item, as in Rust: the head is read as a plain name.
    let head: root.hir.PathHead = if (scoped_type_param_heads(ctx, written_head, segments)) {
        root.hir.PathHeadPlain {}
    } else {
        written_head
    };
    let function_ = match (ctx.lower.resolve_value(head, segments)) {
        let value: ResolvedValueSource => {
            match (value.value) {
                let f: root.hir.DefinitionFunction => f.value,
                _ => null,
            }
        },
        _ => null,
    };
    if (function_ != null) {
        let signature = function_signature_with_diagnostics(ctx.db, function_).signature;
        let callee_name = root.hir.function_data(ctx.db, function_).name;
        let instantiation = write_call_type_args(ctx, call, instantiation_args_at(ctx, call, signature.generic_params, callee_name), 0);
        register_callable_instantiation(ctx, function_, instantiation, call);
        let fn_ty = instantiate_callable_signature(ctx.db, function_, instantiation);
        ctx.result.type_of_expr[callee] = fn_ty;
        ctx.result.member_resolutions[callee] = MemberResolutionFree { func: function_ };
        return (fn_ty, false);
    }
    // Class generics have no receiver to pin them, so they instantiate fresh
    // alongside the method's own.
    if (segments.length() >= 2) {
        let fn_ty = class_static_value(
            ctx,
            head,
            segments.slice(0, segments.length() - 1),
            segments[segments.length() - 1],
            OwnArgsCall { value: call },
            call,
            callee,
        );
        if (fn_ty != null) {
            ctx.result.type_of_expr[callee] = fn_ty;
            return (fn_ty, false);
        }
    }
    null
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_callee @ d9be6853b
// (the bound-method match) A bound method callee, in either AST spelling:
// `expr.name(..)` parses as MemberAccess, `local.name(..)` as a
// multi-segment Path; a method on a global (`G.m(..)`) takes the same road.
// Null when the callee is none of these.
function infer_callee_receiver(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
) -> (int, bool)? throws never {
    let pool = ctx.table.pool;
    match (body.exprs[callee]) {
        let access: root.ast.ExprMemberAccess => {
            // TYPE-qualified member spelling (`Box<int>.from_json(j)`): the
            // path ladder's static road in member clothing.
            match (body.exprs[access.base]) {
                let path: root.ast.ExprPath if !path_resolves_locally(ctx, access.base) => {
                    let head = item_head(ctx, access.base, path.value.segments);
                    let fn_ty = type_qualified_member_callee(ctx, call, access.base, head, path.value.segments, access.member, callee);
                    if (fn_ty != null) {
                        ctx.result.type_of_expr[callee] = fn_ty;
                        return (fn_ty, false);
                    }
                },
                _ => {},
            }
            let receiver = infer_expr(ctx, body, access.base, ExpectationNone {});
            let (let ty, let bound, let resolution) = member_callee(ctx, call, callee, receiver, access.member);
            ctx.result.type_of_expr[callee] = ty;
            if (resolution != null) {
                ctx.result.member_resolutions[callee] = resolution;
            }
            (ty, bound)
        },
        // `x?.method(..)`: the link peels the receiver's null (the chain
        // boundary re-unions it) and dispatches on the rest.
        let access: root.ast.ExprOptionalMemberAccess => {
            let receiver = infer_expr(ctx, body, access.base, ExpectationNone {});
            let nonnull = peel_chain_null(ctx, receiver);
            let (let ty, let bound, let resolution) = member_callee(ctx, call, callee, nonnull, access.member);
            ctx.result.type_of_expr[callee] = ty;
            if (resolution != null) {
                ctx.result.member_resolutions[callee] = resolution;
            }
            (ty, bound)
        },
        let path: root.ast.ExprPath
            if path.value.segments.length() >= 2
            && (
                path_resolves_locally(ctx, callee)
                    || template_param_heads(ctx, item_head(ctx, callee, path.value.segments), path.value.segments)
            ) => {
            let segments = path.value.segments;
            let root_ty = if (path_resolves_locally(ctx, callee)) {
                infer_path(ctx, callee)
            } else {
                // The guard admitted a tagged-template body param root.
                root.hir_ty.infer.template_param_ty(ctx, segments[0])
                    ?? pool.add(root.types.TyError {})
            };
            // Intermediate segments walk the ladder; the FINAL member resolves
            // as the callee, and its step completes the recorded path.
            let (let receiver, let steps) = walk_path_members(ctx, callee, root_ty, segments.slice(1, segments.length() - 1));
            let (let ty, let bound, let resolution) = member_callee(ctx, call, callee, receiver, segments[segments.length() - 1]);
            ctx.result.type_of_expr[callee] = ty;
            steps.push(ResolvedPathSegment { ty: ty, resolution: resolution });
            write_resolved_path(ctx, callee, steps);
            (ty, bound)
        },
        // A method called on a global (`G.m(..)`, `root.ns.G.field.m(..)`):
        // the same road as a local receiver, so the call site's turbofish and
        // arguments instantiate the method.
        let path: root.ast.ExprPath if path.value.segments.length() >= 2 => {
            let segments = path.value.segments;
            let receiver_segments = segments.slice(0, segments.length() - 1);
            let head = item_head(ctx, callee, segments);
            let global = global_root(ctx, head, receiver_segments);
            if (global == null) {
                return null;
            }
            let (let binding, let root_len) = global;
            ctx.result.global_roots[callee] = GlobalRoot { binding: binding, segments: root_len };
            let root_ty = global_value_ty(ctx, callee, binding) ?? pool.add(root.types.TyError {});
            let (let receiver, let steps) = walk_path_members(ctx, callee, root_ty, receiver_segments.slice(root_len, receiver_segments.length()));
            let (let ty, let bound, let resolution) = member_callee(ctx, call, callee, receiver, segments[segments.length() - 1]);
            ctx.result.type_of_expr[callee] = ty;
            steps.push(ResolvedPathSegment { ty: ty, resolution: resolution });
            write_resolved_path(ctx, callee, steps);
            (ty, bound)
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::member_callee @ d9be6853b
// `receiver.member` in callee position: a method (instantiated: the receiver
// pins the class generics, the call site's turbofish or fresh variables fill
// the method's own; bound iff it takes `self`), or a field holding a
// function value. `member_expr` is the member-access expression itself, the
// E0121/E0122 anchor.
function member_callee(
    ctx: InferenceContext,
    call: int,
    member_expr: int,
    receiver: int,
    member: string,
) -> (int, bool, WorkingMemberResolution?) throws never {
    let pool = ctx.table.pool;
    let viewer = root.hir.file_package(ctx.db, ctx.owner_file).root_id;
    let resolved = structurally_resolve(ctx, receiver);
    let candidate = lookup_method(ctx.db, ctx.facts, resolved, member);
    let tuple_index = baml.Int.parse(member) catch (e) {
        baml.errors.ParseError => null,
    };
    if (tuple_index != null && tuple_index >= 0 && tuple_index <= U32_MAX) {
        report(ctx, PendingDiagFunctionFieldNeedsParens { expr: member_expr });
        return (pool.add(root.types.TyError {}), false, null);
    }
    // Callee position on a UNION: the member resolves through the single
    // interface every arm shares, `Self` bound to the union.
    match (pool.kinds[resolved]) {
        let union_: root.types.InferTyUnion => {
            let found = member_callee_union(ctx, call, member_expr, resolved, union_.members, member);
            if (found != null) {
                return found;
            }
        },
        _ => {},
    }
    if (candidate == null) {
        return member_callee_non_inherent(ctx, call, member_expr, resolved, member);
    }
    // An own method does not arbitrate an interface clash: two implemented
    // interfaces declaring `member` still make the unqualified access
    // ambiguous (E0121), own method or not.
    let ambiguity = concrete_member_ambiguity(ctx.db, viewer, ctx.facts, resolved, member);
    if (ambiguity != null) {
        if (!suppressed(ctx, Suppress.MemberProbe)) {
            report(
                ctx,
                PendingDiagAmbiguousMember {
                    expr: member_expr,
                    base: resolved,
                    member: member,
                    sources: ambiguity.0,
                    is_field: ambiguity.1,
                },
            );
        }
        return (pool.add(root.types.TyError {}), false, null);
    }
    let method = candidate.method;
    if (reject_selfless_inherent_method(ctx, method, member, member_expr)) {
        return (pool.add(root.types.TyError {}), false, null);
    }
    let own_params = function_signature_ty(ctx.db, method).generic_params;
    let method_name = root.hir.function_data(ctx.db, method).name;
    let class_count = candidate.class_args.length();
    let position = if (is_reflect_package_function_lookup(ctx, method)) {
        TypePosition.ExtractionContract
    } else {
        TypePosition.Existential
    };
    let instantiation = write_call_type_args(
        ctx,
        call,
        candidate.class_args.concat(
            instantiation_args_at(ctx, call, own_params, method_name, position = position),
        ),
        class_count,
    );
    register_callable_instantiation(ctx, method, instantiation, call);
    let fn_ty = instantiate_callable_signature(ctx.db, method, instantiation);
    let bound = callable_takes_self(ctx.db, method);
    let resolution: WorkingMemberResolution = MemberResolutionMethod<int> {
        callee: MethodCalleeInherent { value: method },
        receiver: if (bound) {
            Receiver.Bound
        } else {
            Receiver.Unbound
        },
    };
    (fn_ty, bound, resolution)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::member_callee @ d9be6853b
// (the union-receiver arm) Resolves through `lookup_union_member`; null when
// no interface shared by every arm declares the member, so the caller goes
// on to the other tiers.
function member_callee_union(
    ctx: InferenceContext,
    call: int,
    member_expr: int,
    resolved: int,
    union_members: int[],
    member: string,
) -> (int, bool, WorkingMemberResolution?)? throws never {
    let error = ctx.table.pool.add(root.types.TyError {});
    let viewer = root.hir.file_package(ctx.db, ctx.owner_file).root_id;
    match (lookup_union_member(ctx.db, viewer, ctx.facts, resolved, union_members, member)) {
        let found: UnionMemberLookupFound => {
            // A union receiver is ERASED: a `self`-less member has no
            // value-derived dispatch key, exactly as through an existential.
            if (reject_selfless_instance_member(ctx, found.value, member, member_expr)) {
                return (error, false, null);
            }
            let resolution = declarer_resolution(ctx, found.value.declarer, member, Receiver.Bound);
            let (let ty, let bound) = interface_member_callee(ctx, found.value, call, true);
            (ty, bound, resolution)
        },
        let conflict: UnionMemberLookupAssociatedTypeConflict => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagUnionAssociatedTypeConflict {
                        expr: member_expr,
                        base: resolved,
                        member: member,
                        is_method: conflict.is_method,
                        types: conflict.types,
                    },
                );
            }
            (error, false, null)
        },
        let ambiguous: UnionMemberLookupAmbiguous => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagAmbiguousMember {
                        expr: member_expr,
                        base: resolved,
                        member: member,
                        sources: ambiguous.sources,
                        is_field: ambiguous.is_field,
                    },
                );
            }
            (error, false, null)
        },
        let restricted: UnionMemberLookupSelfRestricted => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagSelfRestrictedMember {
                        expr: member_expr,
                        interface_: restricted.interface_,
                        member: member,
                        position: restricted.position,
                    },
                );
            }
            (error, false, null)
        },
        UnionMemberLookupNoCommonInterface => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::member_callee @ d9be6853b
// (the no-inherent-candidate block) Interface members: existential and
// bounded-var receivers dispatch virtually; methods bind their receiver. A
// receiver still CARRYING inference variables probes the impls by
// unification instead. Then a field holding a function value; when every
// tier is exhausted, the COMMITTED member failure reports here.
function member_callee_non_inherent(
    ctx: InferenceContext,
    call: int,
    member_expr: int,
    resolved: int,
    member: string,
) -> (int, bool, WorkingMemberResolution?) throws never {
    let pool = ctx.table.pool;
    let error = pool.add(root.types.TyError {});
    let viewer = root.hir.file_package(ctx.db, ctx.owner_file).root_id;
    match (lookup_interface_member(ctx.db, viewer, ctx.facts, resolved, member)) {
        let found: InterfaceMemberLookupFound => {
            if (reject_selfless_instance_member(ctx, found.value, member, member_expr)) {
                return (error, false, null);
            }
            let resolution = declarer_resolution(ctx, found.value.declarer, member, Receiver.Bound);
            let (let ty, let bound) = interface_member_callee(ctx, found.value, call, true);
            return (ty, bound, resolution);
        },
        let ambiguous: InterfaceMemberLookupAmbiguous => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagAmbiguousMember {
                        expr: member_expr,
                        base: resolved,
                        member: member,
                        sources: ambiguous.sources,
                        is_field: ambiguous.is_field,
                    },
                );
            }
            return (error, false, null);
        },
        let projection: InterfaceMemberLookupFieldRequiresProjection => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagFieldRequiresProjection {
                        expr: member_expr,
                        base: resolved,
                        member: member,
                        interface_: projection.interface_,
                    },
                );
            }
            // Reported above: `Error` taints the expression so the missing
            // view is not restated as a type mismatch.
            return (error, false, null);
        },
        let restricted: InterfaceMemberLookupSelfRestricted => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagSelfRestrictedMember {
                        expr: member_expr,
                        interface_: restricted.interface_,
                        member: member,
                        position: restricted.position,
                    },
                );
            }
            return (error, false, null);
        },
        InterfaceMemberLookupNotFound => {},
    }
    // The var-carrying probe resolves through an impl candidate whose block
    // loc `ImplFacts` does not carry yet, so its declarer would mislabel
    // concrete dispatch as virtual: no recorded entry rather than a wrong
    // one.
    if (pool.has_infer(resolved)) {
        let interface_member = root.hir_ty.infer.probe_impl_member(ctx, resolved, member, call);
        if (interface_member != null) {
            let (let ty, let bound) = interface_member_callee(ctx, interface_member, call, true);
            return (ty, bound, null);
        }
    }
    let (let field, let field_resolution) = with_suppressed(ctx, Suppress.MemberProbe, (this) -> {
        field_access_resolved(this, call, resolved, member)
    });
    let is_field = match (field_resolution) {
        MemberResolutionField | MemberResolutionInterfaceVirtualField<int> => true,
        _ => false,
    };
    if (is_field) {
        report(ctx, PendingDiagFunctionFieldNeedsParens { expr: member_expr });
        return (error, false, null);
    }
    // A union base says "no common interface": each arm may well declare
    // `member` via different interfaces, so the bare "no member" would
    // mislead.
    if (pool.has_error(field) && !suppressed(ctx, Suppress.MemberProbe) && !pool.has_error(resolved)) {
        if (pool.has_infer(resolved)) {
            // Not a cascade: the receiver is just not inferred yet. The call is
            // already typed `Error` with no member recorded, so a later solve
            // cannot repair it.
            ctx.table.taint_vars_in(resolved);
            report(ctx, PendingDiagReceiverTypeMustBeKnown { expr: member_expr, member: member });
        } else if (pool.kinds[resolved] is root.types.InferTyUnion) {
            report(ctx, PendingDiagUnionNoCommonInterface { expr: call, base: resolved, member: member });
        } else {
            report(ctx, PendingDiagUnresolvedMember { expr: call, base: resolved, member: member });
        }
    }
    (field, false, field_resolution)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::default_receiver_target @ d9be6853b
// The `default` receiver's meaning inside an `implements` block: the block's
// target interface (its written args and associated bindings lowered in the
// owner's frame) plus the IMPLEMENTOR as `Self`. Null anywhere else.
function default_receiver_target(
    ctx: InferenceContext,
) -> (root.types.InferInterfaceConstraint, int)? throws never {
    let pool = ctx.table.pool;
    let function_ = owner_function(ctx)
        ?? return null;
    let target = root.hir.method_interface_target(ctx.db, function_)
        ?? return null;
    let target_ty = ctx.lower.lower_type_ref(
        target.type_refs,
        target.target,
        position = TypePosition.ConstraintHead,
    );
    let interface_ = match (pool.kinds[pool.from_plain(reject_holes(target_ty))]) {
        let i: root.types.InferTyInterface => i,
        _ => {
            return null;
        },
    };
    // A recorded interface target pairs with an Impl owner: class-owned
    // methods never carry one, and interface default bodies have no target.
    let self_ty = match (root.hir.method_owner(ctx.db, function_)) {
        let owner: root.hir.MethodOwnerImpl => pool.from_plain(impl_self_ty(ctx.db, owner.value)),
        _ => {
            return null;
        },
    };
    (
        root.types.infer_interface_new(
            interface_.name,
            interface_.args,
            interface_.associated_types,
        ),
        self_ty,
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::default_member @ d9be6853b
// `default.member`: delegation to the interface's DEFAULT implementation
// (Java's `I.super.m()`), resolved on the enclosing implements block's
// interface with `Self` = the implementor, restricted to members the
// interface gives meaning: a declared field or a default-bodied method.
function default_member(ctx: InferenceContext, member: string) -> InterfaceMember? throws never {
    let (let target, let self_ty) = default_receiver_target(ctx)
        ?? return null;
    let interface_ = match (definition_of(ctx.db, target.name)) {
        let def: root.hir.DefinitionInterface => def.value,
        _ => {
            return null;
        },
    };
    let data = root.hir.interface_data(ctx.db, interface_);
    let provided = data.fields.some((field) -> {
        field.name == member
    })
        || data.methods.some((method) -> {
            root.hir.function_has_body(ctx.db, method)
                && root.hir.function_data(ctx.db, method).name == member
        });
    if (!provided) {
        return null;
    }
    member_on_interface(ctx.db, ctx.facts, target, self_ty, member, false)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_member_callee @ d9be6853b
// An interface member in CALLEE position: a default method's OWN generics
// fill from the call site (turbofish or fresh vars) on top of the
// receiver-pinned interface prefix. Shared by the ground interface road and
// the probe.
function interface_member_callee(
    ctx: InferenceContext,
    interface_member: InterfaceMember,
    call: int,
    bind_self: bool,
) -> (int, bool) throws never {
    if (!interface_member.is_method) {
        report(ctx, PendingDiagFunctionFieldNeedsParens { expr: call });
        return (ctx.table.pool.add(root.types.TyError {}), false);
    }
    // A `self`-LESS method binds no receiver whatever the spelling.
    let bound = interface_member.is_method && bind_self && interface_member_takes_self(ctx, interface_member);
    let pending = interface_member.pending_own;
    if (pending != null) {
        let own_params = function_signature_ty(ctx.db, pending.callable).generic_params;
        let method_name = root.hir.function_data(ctx.db, pending.callable).name;
        let own_offset = pending.prefix.length();
        let instantiation = write_call_type_args(
            ctx,
            call,
            pending.prefix.concat(instantiation_args_at(ctx, call, own_params, method_name)),
            own_offset,
        );
        register_callable_instantiation(ctx, pending.callable, instantiation, call);
        return (
            instantiate_member_signature(ctx.db, ctx.facts, pending.callable, instantiation, pending.arms),
            bound,
        );
    }
    // A matched impl's method with no generics of its own still runs in the
    // impl's frame, and the plan carries every statically resolved callee's
    // whole frame: the impl's bindings are its owner prefix.
    match (interface_member.declarer) {
        let method: MemberDeclarerImplMethod => {
            write_call_type_args(ctx, call, method.frame_type_args, method.frame_type_args.length());
        },
        _ => {},
    }
    (interface_member.ty, bound)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_unspecialized_generic_method_value @ d9be6853b
// Generic methods follow the same realization rule as free functions: a
// bare value needs either explicit type arguments or enough contextual
// function type information to determine them.
function report_unspecialized_generic_method_value(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: Expectation,
    inferred: int,
) -> void throws never {
    if (body.exprs[expr] is root.ast.ExprGenericApply) {
        return;
    }
    let resolution = ctx.result.member_resolutions.get(expr);
    if (resolution == null) {
        return;
    }
    let reference = body.display_expr(expr);
    let had_context = expectation_only_has_type(expected) != null || suppressed(ctx, Suppress.OptionalCallee);
    let (let method, let receiver_is_bound) = match (resolution) {
        let r: MemberResolutionMethod<int> => {
            let func = method_callee_callable<int>(r.callee, ctx.db);
            if (func == null) {
                return;
            }
            (func, r.receiver == Receiver.Bound)
        },
        _ => {
            return;
        },
    };
    let user_params = callable_user_generic_params(ctx.db, method);
    if (user_params.length() == 0) {
        return;
    }
    let generic_params = user_params.map((entry) -> {
        entry.0.name
    });
    let specialization_example_is_safe = user_params.every((entry) -> {
        entry.1.length() == 0
    });
    let user_param_tys = user_params.map((entry) -> {
        entry.0
    });
    let signature = function_signature_ty(ctx.db, method);
    let throws_ = function_signature_with_diagnostics(ctx.db, method).signature.throws_;
    let has_phantom_param = user_param_tys.some((param) -> {
        !signature_mentions_param(signature, throws_, param)
    });
    let specialization_syntax_available = body.exprs[expr] is root.ast.ExprPath;
    // The value's type, and its recorded instantiation of the user
    // parameters: a phantom parameter appears in no part of the type.
    let inference_evidence = [inferred];
    let plan = ctx.result.call_plans.get(expr);
    if (plan != null) {
        for (let param in user_param_tys) {
            let arg = plan.type_args.at(param.index);
            if (arg != null) {
                inference_evidence.push(arg);
            }
        }
    }
    report(
        ctx,
        PendingDiagGenericFunctionValueNotSpecialized {
            expr: expr,
            name: root.hir.function_data(ctx.db, method).name,
            reference: reference,
            inference_evidence: inference_evidence,
            specialization_args: null,
            unconditional: !had_context || has_phantom_param,
            had_expected_type: had_context,
            generic_params: generic_params,
            binding_name: initializer_binding_name(body, expr),
            function_shape: if (!has_phantom_param) {
                generic_function_value_shape(
                    Viewpoint.for_file(ctx.db, ctx.owner_file),
                    ctx.db,
                    method,
                    user_param_tys,
                    receiver_is_bound,
                    false,
                )
            } else {
                null
            },
            annotation_ty: if (specialization_example_is_safe && !has_phantom_param) {
                inferred
            } else {
                null
            },
            specialization_example_is_safe: specialization_example_is_safe,
            specialization_syntax_available: specialization_syntax_available,
        },
    );
}
