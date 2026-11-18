// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs @ d9be6853b
//
// Check declaration hooks using the ordinary call checker in the target's
// generic environment. This pass never inserts an executable hook call.
//
// Restructured (BAML forces it):
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so a `FunctionRef` is its Source lane, a function loc `int`: every
//   `if let Some(DeclRef::Source(hook)) = hook` is `if (hook != null)`.
// - `HookArgument` is a union of classes; `HookArgument::Target(usize)` is
//   `HookArgumentTarget { value }`.
// - The synthetic body's arena allocations are pushes; an id is the array's
//   length before the push.
// - `checked_declaration`'s per-diagnostic closure is
//   `checked_declaration_reason`.

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::TraceHookPlan @ d9be6853b
// Checked invocation plan shared by diagnostics and executable lowering.
class TraceHookPlan {
    function_: int,
    type_args: root.types.Ty[],
    arguments: HookArgument[],
    return_ty: root.types.Ty,
}

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::HookArgument @ d9be6853b
// Parameter slots in the ordinary checked hook call, in declaration order.
type HookArgument = HookArgumentTarget | HookArgumentSettings | HookArgumentDefault;

// Resolved target parameter slot, including a method's receiver.
class HookArgumentTarget {
    value: int,
}

// Detached call-local tracing settings.
class HookArgumentSettings {
}

// An omitted optional slot; its default executes in the hook's frame.
class HookArgumentDefault {
}

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::declaration_diagnostics @ d9be6853b
function declaration_diagnostics(
    db: root.hir.Db,
    function_: int,
) -> root.hir_ty.TirDiagnostic[] throws never {
    checked_declaration(db, function_).0
}

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::declaration_plan @ d9be6853b
function declaration_plan(db: root.hir.Db, function_: int) -> TraceHookPlan? throws never {
    checked_declaration(db, function_).1
}

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::checked_declaration @ d9be6853b
function checked_declaration(
    db: root.hir.Db,
    function_: int,
) -> (root.hir_ty.TirDiagnostic[], TraceHookPlan?) throws never {
    let path = root.hir.function_trace_hook(db, function_)
        ?? return ([], null);
    let span = root.hir.function_trace_hook_span(db, function_) ?? baml.sys.panic("hook source span");
    let hook_name = path.join(".");
    let file = db.function_locs.get(function_).file;
    let package = root.hir.file_package(db, file);
    let viewpoint = root.hir_ty.Viewpoint.for_file(db, file);
    // A copy: `namespace_path` is the memoized package info's own array.
    let target_path = package.namespace_path.slice(0, package.namespace_path.length());
    match (root.hir.method_owner(db, function_)) {
        let class_: root.hir.MethodOwnerClass => {
            target_path.push(root.hir.class_data(db, class_.value).name);
        },
        let interface_: root.hir.MethodOwnerInterface => {
            target_path.push(root.hir.interface_data(db, interface_.value).name);
        },
        root.hir.MethodOwnerImpl => {
            let owner = root.hir_ty.owner_self_ty(db, function_);
            if (owner != null) {
                target_path = [root.hir_ty.ty_spell(owner, viewpoint)];
            }
        },
        null => {},
    }
    target_path.push(root.hir.function_data(db, function_).name);
    let target_name = target_path.join(".");
    let invalid = (reason: string) -> root.hir_ty.TirDiagnostic {
        root.hir_ty.TirDiagnostic {
            error: root.hir_ty.TirTypeErrorInvalidTraceHook {
                message: `Invalid trace hook \`${hook_name}\` for function \`${target_name}\`.\n${reason}`,
            },
            severity: root.hir_ty.DiagnosticSeverity.Error,
            primary: root.hir_ty.DiagnosticLocationSpan { value: span },
            related: [],
        }
    };
    let target_body = match (root.hir.function_body(db, function_)) {
        let expr_body: root.hir.FunctionBodyExpr => expr_body.value,
        _ => {
            return (
                [
                    invalid(
                        "The target has no BAML body.\nhelp: Attach the hook to a function with a BAML body.",
                    ),
                ],
                null,
            );
        },
    };
    let owner = root.hir.BodyOwnerIdFunction { value: function_ };
    let signature = root.hir_ty.function_signature_with_diagnostics(db, function_).signature;
    let lower = root.hir_ty.lower_ctx_for_file(db, file)
        .with_frame(root.hir_ty.function_generic_frame(db, function_))
        .with_bounds(root.hir_ty.owner_declared_bounds(db, owner))
        .with_self_ty(root.hir_ty.owner_self_ty(db, function_));
    // The compiler names `trace.Options` and `trace.Settings` by identity:
    // the `trace` package's own declarations under a `PathHeadLang` head,
    // which nothing the target's scope calls `trace` shadows. Without the
    // package installed there is nothing to check the hook against.
    let trace = root.hir.lang_roots(db).get(root.base.LangPackage.Trace)
        ?? return ([invalid("The `trace` package is not available, so the hook cannot be checked.")], null);
    let trace_head = root.hir.PathHeadLang { value: trace };
    let options = root.hir_ty.reject_holes(lower.lower_type_path(trace_head, ["trace", "Options"]));
    let settings = root.hir_ty.reject_holes(lower.lower_type_path(trace_head, ["trace", "Settings"]));
    let pool = db.ty_memo.pool;
    let expected = pool.from_plain(root.types.TyUnion { members: [options, root.types.TyNull {}] });
    let context = root.hir_ty.InferenceContext.new(
        db,
        owner,
        lower,
        [],
        null,
        root.hir_ty.ThrowsClauseClosed { value: pool.add(root.types.TyNever {}) },
    );

    // Reserve source IDs; these expressions must not accidentally acquire a
    // body-local resolution. Hook lookup is in the declaration's namespace.
    let body = root.ast.ExprBody.new();
    for (let i = 0; i < target_body.exprs.length(); i += 1) {
        body.exprs.push(root.ast.ExprMissing {});
    }
    let callee = body.exprs.length();
    body.exprs.push(root.ast.ExprPath { value: root.base.Path.new(path) });
    let call = body.exprs.length();
    body.exprs.push(root.ast.ExprCall { callee: callee, type_args: [], args: [] });
    body.root_expr = call;
    context.body_root = call;
    let (let hook_ty, let bound) = root.hir_ty.infer_callee(context, body, call, callee);
    let resolution = context.result.callee_resolution(callee);
    let hook = if (resolution != null) {
        root.hir_ty.member_resolution_callable<int>(resolution, db)
    } else {
        null
    };
    let is_llm = root.hir.function_llm_meta(db, function_) != null;
    let params = signature.params.filter((param) -> {
        !is_llm || !root.ast.is_injected_llm_param(param.name)
    });
    let hook_declared_here = (hook_loc: int) -> root.hir_ty.RelatedNote {
        root.hir_ty.RelatedNote {
            location: root.hir_ty.RelatedLocationItem {
                value: root.hir.DefinitionFunction { value: hook_loc },
            },
            message: "hook declared here",
        }
    };
    let callable_without_arguments = false;
    if let hook_fn: root.types.InferTyFunction = pool.kinds[hook_ty] {
        let hook_params = if (bound) {
            hook_fn.params.slice(1, hook_fn.params.length())
        } else {
            hook_fn.params
        };
        let required = hook_params
            .filter((param) -> {
                param.mode == root.types.FunctionParamMode.Required
            })
            .length();
        if (required != 0 && required != params.length() + 1) {
            let expected_params = params.map((param) -> {
                `${param.name}: ${root.hir_ty.ty_spell(param.ty, viewpoint)}`
            });
            expected_params.push("settings: trace.Settings");
            let diagnostic = invalid(
                `The hook has ${required} required parameter(s), but this target needs ${params.length() + 1}.\nExpected hook signature: (${expected_params.join(", ")}) -> trace.Options? throws never\nhelp: Accept the target's arguments in declaration order, followed by settings, or use a hook callable without arguments.`,
            );
            if let hook_loc: int = hook {
                diagnostic.related.push(hook_declared_here(hook_loc));
            }
            return ([diagnostic], null);
        }
        // The ordinary call checker below handles omitted defaults rather
        // than requiring an exactly parameterless type.
        callable_without_arguments = required == 0;
    }

    // Like tagged-template parameters, these are typed compiler inputs
    // without source bindings. Their names cannot collide with any authored
    // identifier.
    let inputs: map<string, int> = {};
    let args: root.ast.CallArg[] = [];
    if (!callable_without_arguments) {
        let index = 0;
        for (let param in params) {
            let name = `$trace_hook_arg_${index}`;
            inputs[name] = pool.from_plain(param.ty);
            args.push(root.ast.CallArg.positional(body.exprs.length()));
            body.exprs.push(root.ast.ExprPath { value: root.base.Path.new([name]) });
            index += 1;
        }
        let name = "$trace_hook_settings";
        inputs[name] = pool.from_plain(settings);
        args.push(root.ast.CallArg.positional(body.exprs.length()));
        body.exprs.push(root.ast.ExprPath { value: root.base.Path.new([name]) });
    }
    enter_frame(context, FrameKindTemplate { params: inputs });
    let result = root.hir_ty.check_call_args(context, body, call, callee, hook_ty, bound, args);
    // Defaults have a separate inference owner and are not part of the
    // callable's body throws type. This synthetic call omits every optional
    // argument, so their effects must also satisfy the hook's
    // `throws never`.
    let default_effect: int? = null;
    if let hook_loc: int = hook {
        let defaults = root.hir_ty.infer_body(db, root.hir.BodyOwnerIdParameterDefaults { value: hook_loc });
        let type_args = context.result.call_plans.get(call)?.type_args ?? [];
        let throws_ = root.hir_ty.substitute_params(pool, pool.from_plain(defaults.throws_), type_args);
        root.hir_ty.record_throw(context, call, throws_);
        // Preserve this instantiated effect through writeback so diagnostics
        // can distinguish a throwing default from the hook body's effects.
        let effect = body.exprs.length();
        body.exprs.push(root.ast.ExprMissing {});
        context.result.type_of_expr[effect] = throws_;
        default_effect = effect;
    }
    root.hir_ty.check_inferred(context, call, result, expected);
    context.result.type_of_expr[call] = result;
    let finished = root.hir_ty.finish(context, body);
    let callee_never_throws = match (finished.type_of_expr.get(callee)) {
        let function_ty: root.types.TyFunction => function_ty.throws_ is root.types.TyNever,
        _ => false,
    };
    let default_ty = if (default_effect != null) {
        finished.type_of_expr.get(default_effect)
    } else {
        null
    };
    let default_only_throws = callee_never_throws && default_ty != null && !(default_ty is root.types.TyNever);
    let diagnostics = finished.diagnostics
        .filter((diagnostic) -> {
            diagnostic.severity == root.hir_ty.DiagnosticSeverity.Error
        })
        .map((diagnostic) -> {
            let related: root.hir_ty.RelatedNote[] = [];
            let reason = checked_declaration_reason(
                diagnostic,
                related,
                viewpoint,
                pool,
                hook_name,
                hook,
                hook_ty,
                bound,
                function_,
                signature,
                params,
                args,
                default_only_throws,
            );
            if let hook_loc: int = hook {
                if (related.length() == 0) {
                    related.push(hook_declared_here(hook_loc));
                }
            }
            let rendered = invalid(reason);
            rendered.related = related;
            rendered
        });
    if (diagnostics.length() > 0) {
        return (diagnostics, null);
    }
    let hook_loc = hook
        ?? return (diagnostics, null);
    let plan = finished.call_plans.get(call)
        ?? return (diagnostics, null);
    let arguments = plan.bindings.map((binding) -> {
        match (binding) {
            root.hir_ty.ParamBindingOmittedDefault => HookArgumentDefault {},
            let provided: root.hir_ty.ParamBindingProvided => {
                let index = args.find_index((input) -> {
                    input.expr == provided.arg
                })
                    ?? baml.sys.panic("checked hook argument");
                if let param: root.hir_ty.SignatureParam = params.at(index) {
                    HookArgumentTarget {
                        value: signature.params.find_index((source) -> {
                            source.name == param.name
                        })
                            ?? baml.sys.panic("target parameter"),
                    }
                } else {
                    HookArgumentSettings {}
                }
            },
        }
    });
    (
        diagnostics,
        TraceHookPlan {
            function_: hook_loc,
            type_args: plan.type_args,
            arguments: arguments,
            return_ty: finished.type_of_expr[call],
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::checked_declaration @ d9be6853b
// One error diagnostic of the checked hook call, restated as the reason an
// invalid hook gives; related notes are pushed onto `related`.
// Restructured: `checked_declaration`'s per-diagnostic closure.
function checked_declaration_reason(
    diagnostic: root.hir_ty.TirDiagnostic,
    related: root.hir_ty.RelatedNote[],
    viewpoint: root.hir_ty.Viewpoint,
    pool: root.types.InferPool,
    hook_name: string,
    hook: int?,
    hook_ty: int,
    bound: bool,
    function_: int,
    signature: root.hir_ty.FunctionSignature,
    params: root.hir_ty.SignatureParam[],
    args: root.ast.CallArg[],
    default_only_throws: bool,
) -> string throws never {
    let spell = (ty: root.types.Ty) -> string {
        root.hir_ty.ty_spell(ty, viewpoint)
    };
    match (diagnostic.error) {
        let mismatch: root.hir_ty.TirTypeErrorTypeMismatch => {
            let input_index = match (diagnostic.primary) {
                let at: root.hir_ty.DiagnosticLocationExpr => {
                    args.find_index((arg) -> {
                        arg.expr == at.value
                    })
                },
                _ => null,
            };
            if (input_index == null) {
                return `The hook returns \`${spell(mismatch.got)}\`, but must return \`trace.Options\` or \`null\`.\nhelp: Return tracing options (for example \`trace.span(inputs = true)\`) or \`null\` to keep the current settings.`;
            }
            let index = input_index;
            let hook_index = if (bound) {
                index + 1
            } else {
                index
            };
            let hook_param_name = match (pool.kinds[hook_ty]) {
                let hook_fn: root.types.InferTyFunction => hook_fn.params.at(hook_index)?.name,
                _ => null,
            };
            let hook_param = hook_param_name ?? `#${index + 1}`;
            if let hook_loc: int = hook {
                related.push(
                    root.hir_ty.RelatedNote {
                        location: root.hir_ty.RelatedLocationParam { function_: hook_loc, index: hook_index },
                        message: `hook parameter \`${hook_param}\` expects \`${spell(mismatch.expected)}\``,
                    },
                );
            }
            let target_param = params.at(index);
            if (target_param == null) {
                return `The runtime supplies \`trace.Settings\` as the final argument, but hook parameter \`${hook_param}\` expects \`${spell(mismatch.expected)}\`.\nhelp: Make the final required hook parameter accept \`trace.Settings\`.`;
            }
            let target_name = target_param.name;
            let source_index = signature.params.find_index((param) -> {
                param.name == target_name
            })
                ?? baml.sys.panic("target parameter");
            related.push(
                root.hir_ty.RelatedNote {
                    location: root.hir_ty.RelatedLocationParam { function_: function_, index: source_index },
                    message: `target parameter \`${target_name}\` has type \`${spell(mismatch.got)}\``,
                },
            );
            `Target parameter \`${target_name}\` has type \`${spell(mismatch.got)}\`, but hook parameter \`${hook_param}\` expects \`${spell(mismatch.expected)}\`.\nhelp: Change hook parameter \`${hook_param}\` to accept \`${spell(mismatch.got)}\` or a compatible broader type.`
        },
        let violation: root.hir_ty.TirTypeErrorThrowsContractViolation if default_only_throws => {
            `The hook's omitted default expressions may throw \`${spell(violation.extra)}\`, but trace hooks require \`throws never\`.\nhelp: Handle these errors inside the default expressions.`
        },
        let violation: root.hir_ty.TirTypeErrorThrowsContractViolation => {
            `The hook may throw \`${spell(violation.extra)}\`, but trace hooks require \`throws never\`.\nhelp: Handle these errors inside the hook or its default expressions.`
        },
        root.hir_ty.TirTypeErrorUnresolvedName => {
            `Cannot resolve \`${hook_name}\` in the target's declaration scope.\nhelp: Define the hook or use its qualified function name in \`/// baml:$trace=...\`.`
        },
        let not_callable: root.hir_ty.TirTypeErrorNotCallable => {
            `\`${hook_name}\` has type \`${spell(not_callable.ty)}\` and is not callable.\nhelp: Reference a function returning \`trace.Options?\` with \`throws never\`.`
        },
        _ => root.hir_ty.tir_type_error_render(diagnostic.error, viewpoint),
    }
}
