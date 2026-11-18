// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// Function, let and lambda bodies (lower.rs "3.1: lower_function_body"):
// `lower_function_body` and its default-parameter and trace-hook prologues,
// `lower_let_body_inner`, and `lower_lambda`.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - Every `mem::replace` / `mem::take` / `Option::take` of a context field
//   saves the old object in a local and puts a FRESH value (`[]`, `{}`,
//   `null`, a new `MirBuilder`) in the field; the restore assigns the saved
//   object back. A Rust `.clone()` snapshot of a field that is then mutated
//   in place (`lambda_param_tir_types`, `lambda_generic_params`) keeps the
//   original object as the saved value and gives the field a copy, which is
//   equivalent and never aliases the two.
// - `lower_lambda`'s capture-operand loop (shared word for word with
//   `build_tagged_body_closure`) is `lower_lambda_capture_operands`.
// - The `cfg!(debug_assertions)` binding check (`verify_bindings_recorded`)
//   always runs: it only panics on a lowering bug.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_function_body @ d9be6853b
function lower_function_body(ctx: LoweringContext) -> MirFunction throws MirInternalError {
    let db = ctx.db;
    let func_loc = ctx.func_loc ?? baml.sys.panic("lower_function_body called on non-function LoweringContext");
    let sig = root.hir.function_signature(db, func_loc);

    // Return place _0
    let pkg_info = root.hir.file_package(db, ctx.file);
    let pkg_items = root.hir.package_items(db, pkg_info.root_id);

    let ret_ty: root.types.RuntimeTy = root.types.TyNull {};
    let return_type = sig.return_type;
    if (return_type != null) {
        ret_ty
            = lower_signature_runtime_ty(ctx, return_type.value, pkg_items, pkg_info.namespace_path);
    }
    let ret = ctx.builder.declare_local(ret_ty, name = "_0");

    // Detect enclosing class for `self` parameter resolution
    let index = root.hir.file_semantic_index(db, ctx.file);
    let func_data = root.hir.function_data(db, func_loc);
    let func_span = root.hir.function_source_map(db, func_loc).span;
    // Set the function-level span on the builder so MirFunction.span is populated.
    ctx.builder.set_span(root.base.Span { file_id: ctx.file, range: func_span });
    let func_scope = root.hir.function_scope(db, func_loc)
        ?? baml.sys.panic("every item-tree function has a recorded scope");
    let func_scope_id = db.scopes.get(func_scope).id;
    let func_scope_data = index.scopes[func_scope_id];
    let method_owner = root.hir.method_owner(db, func_loc);
    // Methods declared inside an `implements` block are owned by the class,
    // but their lexical scope is the block rather than the class scope. Use
    // the item-tree owner so an unannotated `self` parameter gets the
    // concrete class type (and virtual calls keep their receiver type)
    // instead of falling back to `Any`.
    let enclosing_class_name: string? = match (method_owner) {
        let owner: root.hir.MethodOwnerClass => root.hir.class_data(db, owner.value).name,
        _ => {
            let parent_idx = func_scope_data.parent;
            if (parent_idx != null && index.scopes[parent_idx].kind == root.hir.ScopeKind.Class) {
                index.scopes[parent_idx].name
            } else {
                null
            }
        },
    };
    let enclosing_impl: root.hir.ImplBlockData? = match (method_owner) {
        let owner: root.hir.MethodOwnerImpl => root.hir.impl_block_data(db, owner.value),
        _ => null,
    };

    // Parameter locals _1..=_n
    // For `self` with no annotation, use the active rule receiver pattern
    // for out-of-body implementations, otherwise the enclosing class type.
    let param_idx = 0;
    for (let param in sig.params) {
        let param_ty = lower_function_body_param_ty(ctx, param, enclosing_impl, enclosing_class_name, pkg_items, pkg_info.namespace_path);
        declare_parameter(ctx, param_idx, param.name, param_ty);
        if (param.name == "self") {
            ctx.self_binding = root.hir.BindingId.parameter(ctx.current_scope, param_idx);
        }
        param_idx += 1;
    }

    // Entry and exit blocks
    let entry = ctx.builder.create_block();
    let exit = ctx.builder.create_block();
    ctx.exit_block = exit;
    ctx.builder.set_current_block(entry);

    let parameter_defaults = root.hir.function_parameter_defaults(db, func_loc);
    lower_default_parameter_prologue(ctx, func_data, parameter_defaults);
    lower_trace_hook_prologue(ctx, func_loc);

    // Lower root expression into return place
    let root_expr = ctx.body.root_expr;
    if (root_expr != null) {
        lower_expr(ctx, root_expr, PlaceLocal { value: ret });
    } else {
        ctx.builder.assign(
            PlaceLocal { value: ret },
            RvalueUse { value: OperandConstant { value: ConstantNull {} } },
        );
    }

    // Goto exit, emit Return terminator
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(ctx.exit_block);
    }
    ctx.builder.set_current_block(ctx.exit_block);
    ctx.builder.return_();

    verify_bindings_recorded(ctx, ctx.current_scope, null);

    // Take the builder out of ctx to call `build()`, which consumes it.
    let builder = ctx.builder;
    ctx.builder = MirBuilder.new(builder.owner, 0);
    let mir = builder.build();
    optimize_function(db, mir, ctx.opt);

    // Drain any lambda functions lowered during this function's body into the
    // MirFunction's lambdas list. The lambda_idx values in MakeClosure
    // rvalues index into this array.
    mir.lambdas = ctx.pending_lambdas;
    ctx.pending_lambdas = [];

    mir
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_function_body @ d9be6853b
// The parameter-type arm of `lower_function_body`'s parameter loop: an
// unannotated `self` takes the implements block's for-target, else the
// enclosing class, else `null`; every other parameter its signature type.
function lower_function_body_param_ty(
    ctx: LoweringContext,
    param: root.hir.SignatureParam,
    enclosing_impl: root.hir.ImplBlockData?,
    enclosing_class_name: string?,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
) -> root.types.RuntimeTy throws never {
    let is_bare_self = match (param.ty.value.kind) {
        root.ast.TypeExprKindMissing => param.name == "self",
        _ => false,
    };
    if (!is_bare_self) {
        return lower_signature_runtime_ty(ctx, param.ty.value, pkg_items, namespace_path);
    }
    if (enclosing_impl != null) {
        let generic_params = enclosing_generic_params(ctx);
        let generic_param_bounds = enclosing_generic_param_bounds(ctx);
        let tir_ty = lower_ref_in_scope(
            ctx.db,
            enclosing_impl.type_refs,
            enclosing_impl.for_target,
            pkg_items,
            namespace_path,
            generic_params,
            generic_param_bounds,
            null,
        );
        return convert_tir_ty_for_runtime(ctx, tir_ty);
    }
    if (enclosing_class_name != null) {
        let def = pkg_items.lookup_type(namespace_path, enclosing_class_name);
        if (def != null) {
            let tir_ty = root.types.TyClass {
                name: root.hir_ty.qualify_def(ctx.db, def, enclosing_class_name),
                args: [],
            };
            return runtime(ctx).convert(tir_ty);
        }
    }
    root.types.TyNull {}
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_trace_hook_prologue @ d9be6853b
function lower_trace_hook_prologue(ctx: LoweringContext, function_: int) -> void throws never {
    let plan = root.hir_ty.infer.declaration_plan(ctx.db, function_)
        ?? return;
    let all_default = plan.arguments.every((argument) -> {
        match (argument) {
            root.hir_ty.infer.HookArgumentDefault => true,
            _ => false,
        }
    });
    if (all_default) {
        let mode = builtin_trace_hook(ctx, plan.function_);
        if (mode != null) {
            ctx.builder.push_statement(
                StatementKindIntrinsic { op: IntrinsicOpBuiltinTraceHook { value: mode }, args: [] },
                null,
            );
            return;
        }
    }
    let with_settings = plan.arguments.some((argument) -> {
        match (argument) {
            root.hir_ty.infer.HookArgumentSettings => true,
            _ => false,
        }
    });
    let settings = ctx.builder.declare_local(root.types.TyUnknown {});
    ctx.builder.assign(
        PlaceLocal { value: settings },
        RvalueTraceHookSettings { with_settings: with_settings },
    );
    let enabled = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(
        PlaceLocal { value: enabled },
        RvalueBinaryOp {
            op: BinOp.Ne,
            left: operand_copy_local(settings),
            right: OperandConstant { value: ConstantNull {} },
        },
    );
    let invoke = ctx.builder.create_block();
    let finish = ctx.builder.create_block();
    let body = ctx.builder.create_block();
    ctx.builder.branch(operand_copy_local(enabled), invoke, body);
    ctx.builder.set_current_block(invoke);
    let args: Operand[] = [];
    for (let ty in plan.type_args) {
        let template = ty_to_template(ctx, ty, enclosing_generic_params(ctx));
        let local = ctx.builder.declare_local(root.types.TyUnknown {});
        ctx.builder.assign(PlaceLocal { value: local }, RvalueLoadType { value: template });
        args.push(operand_copy_local(local));
    }
    for (let arg in plan.arguments) {
        let operand: Operand = match (arg) {
            root.hir_ty.infer.HookArgumentDefault => {
                OperandConstant { value: ConstantOmittedArg {} }
            },
            root.hir_ty.infer.HookArgumentSettings => operand_copy_local(settings),
            let target: root.hir_ty.infer.HookArgumentTarget => {
                let local = ctx.binding_locals[root.hir.BindingId.parameter(ctx.current_scope, target.value)];
                OperandCopy { value: value_place(ctx, local) }
            },
        };
        args.push(operand);
    }
    let result = ctx.builder.declare_local(convert_tir_ty_for_runtime(ctx, plan.return_ty));
    ctx.builder.call_with_type_args(
        OperandConstant { value: ConstantFunction { value: plan.function_ } },
        args,
        plan.type_args.length(),
        PlaceLocal { value: result },
        finish,
    );
    ctx.builder.set_current_block(finish);
    ctx.builder.push_statement(
        StatementKindIntrinsic {
            op: IntrinsicOpApplyTraceHook {},
            args: [operand_copy_local(result)],
        },
        null,
    );
    ctx.builder.goto(body);
    ctx.builder.set_current_block(body);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::builtin_trace_hook @ d9be6853b
// Restructured: a `FunctionRef` is its Source lane (no root is served from
// an interface), so the `DeclRef::External` arm has no counterpart.
function builtin_trace_hook(
    ctx: LoweringContext,
    function_: int,
) -> BuiltinTraceHook? throws never {
    let db = ctx.db;
    if (root.hir.method_owner(db, function_) != null) {
        return null;
    }
    let package = root.hir.file_package(db, db.function_locs.get(function_).file);
    let name = root.hir.function_data(db, function_).name;
    // Declaration identity protects user hooks with the same spelling.
    if (
        !lang(ctx).is_(root.base.LangPackage.Trace, package.root_id)
            || package.namespace_path.length() != 0
    ) {
        return null;
    }
    match (name) {
        "hidden" => BuiltinTraceHook.Hidden,
        "timing" => BuiltinTraceHook.Timing,
        "span" => BuiltinTraceHook.Span,
        "empty_span" => BuiltinTraceHook.EmptySpan,
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_default_parameter_prologue @ d9be6853b
function lower_default_parameter_prologue(
    ctx: LoweringContext,
    func_data: root.hir.FunctionData,
    parameter_defaults: root.hir.FunctionParameterDefaults,
) -> void throws MirInternalError {
    let index = 0;
    while (index < func_data.params.length()) {
        let default_ref = parameter_defaults.param_default(index);
        if (default_ref == null) {
            index += 1;
            continue;
        }
        let param_local = ctx.binding_locals.get(root.hir.BindingId.parameter(ctx.current_scope, index))
            ?? baml.sys.panic("every parameter is declared before the prologue");

        let test_local = ctx.builder.declare_local(root.types.TyBool {});
        ctx.builder.assign(
            PlaceLocal { value: test_local },
            RvalueBinaryOp {
                op: BinOp.Eq,
                left: OperandCopy { value: value_place(ctx, param_local) },
                right: OperandConstant { value: ConstantOmittedArg {} },
            },
        );

        let default_block = ctx.builder.create_block();
        let next_block = ctx.builder.create_block();
        ctx.builder.branch(operand_copy_local(test_local), default_block, next_block);

        ctx.builder.set_current_block(default_block);
        let param_value = value_place(ctx, param_local);
        lower_default_expr(ctx, default_ref.expr, parameter_defaults.defaults, param_value);
        if (!ctx.builder.is_current_terminated()) {
            ctx.builder.goto(next_block);
        }

        ctx.builder.set_current_block(next_block);
        index += 1;
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_default_expr @ d9be6853b
// Rust's `defaults.exprs.clone()` handed to `with_bare_global_paths` is a
// shallow copy here with its own `exprs` array: the rewrite replaces
// entries of `exprs`, and must not reach the memoized defaults.
function lower_default_expr(
    ctx: LoweringContext,
    expr_id: int,
    defaults: root.ast.FunctionDefaults,
    dest: Place,
) -> void throws MirInternalError {
    let saved_body = ctx.body;
    ctx.body
        = with_bare_global_paths(
            root.ast.ExprBody { ...defaults.exprs, exprs: defaults.exprs.exprs.concat([]) },
            ctx.tables.of(InferenceRoot.ParameterDefaults),
        );
    let saved_source_map = ctx.source_map;
    ctx.source_map = defaults.source_map;
    let saved_metadata_scope = ctx.current_metadata_scope;
    ctx.current_metadata_scope
        = root.hir.ExprMetadataScopeParameterDefault { value: ctx.current_scope };
    let saved_root = ctx.inference_root;
    ctx.inference_root = InferenceRoot.ParameterDefaults;
    lower_expr(ctx, expr_id, dest);
    ctx.inference_root = saved_root;
    ctx.current_metadata_scope = saved_metadata_scope;
    ctx.source_map = saved_source_map;
    ctx.body = saved_body;
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_let_body_inner @ d9be6853b
// Lower a top-level let binding's initializer into a zero-arg
// `MirFunctionBody`: arity 0, a single `_0` return place, evaluating the
// initializer into `_0`. `compile_init_function` compiles it into bytecode
// whose result is stored with `StoreGlobal`.
function lower_let_body_inner(ctx: LoweringContext) -> MirFunctionBody throws MirInternalError {
    // Return place _0: an annotated global's declared type; an unannotated
    // one's value is whatever its initializer produces.
    let ret_ty: root.types.RuntimeTy = root.types.TyNull {};
    match (ctx.builder.owner) {
        let owner: FunctionOwnerLet => {
            let declared = root.hir_ty.let_declared_type(ctx.db, owner.value);
            if (declared != null) {
                ret_ty = convert_tir_ty_for_runtime(ctx, declared);
            }
        },
        _ => {},
    }
    let ret = ctx.builder.declare_local(ret_ty, name = "_0");

    // Entry and exit blocks
    let entry = ctx.builder.create_block();
    let exit = ctx.builder.create_block();
    ctx.exit_block = exit;
    ctx.builder.set_current_block(entry);

    // Lower root expression into return place
    let root_expr = ctx.body.root_expr;
    if (root_expr != null) {
        lower_expr(ctx, root_expr, PlaceLocal { value: ret });
    } else {
        ctx.builder.assign(
            PlaceLocal { value: ret },
            RvalueUse { value: OperandConstant { value: ConstantNull {} } },
        );
    }

    // Goto exit, emit Return terminator
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(ctx.exit_block);
    }
    ctx.builder.set_current_block(ctx.exit_block);
    ctx.builder.return_();

    verify_bindings_recorded(ctx, ctx.current_scope, null);

    // Take the builder out and build the MirFunctionBody
    let builder = ctx.builder;
    ctx.builder = MirBuilder.new(builder.owner, 0);
    let body = builder.build_body();
    optimize_function_body(ctx.db, body, ctx.opt);
    body
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_lambda @ d9be6853b
// Lower a lambda expression into a nested `MirFunction` and emit a
// `RvalueMakeClosure` assignment into `dest`.
//
// Saves all parent-body state, sets up a fresh builder for the lambda,
// lowers the lambda body, then restores the parent state. The completed
// `MirFunction` is pushed into `ctx.pending_lambdas`; its index becomes the
// `lambda_idx` in the emitted `MakeClosure` rvalue.
function lower_lambda(
    ctx: LoweringContext,
    func_def: root.ast.LambdaDef,
    expr_id: int,
    dest: Place,
) -> void throws MirInternalError {
    let db = ctx.db;
    let lambda_identity = MirFunctionIdSynthetic {
        parent: ctx.builder.owner,
        kind: SyntheticKind.Lambda,
        ordinal: ctx.synthetic_ordinals.next(SyntheticKind.Lambda),
    };
    let lambda_definition_span = span_for_expr(ctx, expr_id);

    // Find the lambda's FileScopeId from the HIR index. The HIR builder
    // registered a `ScopeKind.Lambda` at the lambda expression's span.
    // Two functions can carry a lambda at the same source span (an LLM
    // function and its synthesized companions share the parent's ranges):
    // prefer the lambda scope nested within the function being lowered, and
    // fall back to the first range match (as `build_tagged_body_closure`).
    let lambda_scope_id = ctx.current_scope;
    let sm = ctx.source_map;
    if (sm != null) {
        let lambda_span = sm.expr_span(expr_id);
        let index = root.hir.file_semantic_index(db, ctx.file);
        lambda_scope_id
            = index.lambda_scope_for_within(ctx.current_scope, lambda_span)
                ?? index.lambda_scope_for(lambda_span)
                ?? ctx.current_scope;
    }

    // The body is an expression in the arena already installed: a lambda
    // owns no `ExprBody`, so there is nothing to swap in.
    let lambda_root = func_def.body;
    if (lambda_root == null) {
        throw internal_error(ctx, "lambda without body", expr_id);
    }

    // Read HIR captures for this lambda scope: the exact binding identities
    // the lambda reads from enclosing scopes. `capture_indices` lets
    // path/lvalue lowering emit `PlaceCapture` without collapsing shadows by
    // name. A fresh array (Rust clones it): it is extended below.
    let hir_captures = lambda_hir_captures(ctx, lambda_scope_id);
    let lambda_capture_indices: map<root.hir.BindingId, int> = {};
    let capture_idx = 0;
    for (let capture in hir_captures) {
        lambda_capture_indices[capture.1] = capture_idx;
        capture_idx += 1;
    }

    // Save parent state.
    let saved_builder = ctx.builder;
    ctx.builder = MirBuilder.new(FunctionOwnerSynthetic { value: lambda_identity }, 0);
    let saved_binding_locals = ctx.binding_locals;
    ctx.binding_locals = {};
    let saved_catch_rethrow_locals = ctx.catch_rethrow_locals;
    ctx.catch_rethrow_locals = [];
    let saved_exit_block = ctx.exit_block;
    let saved_loop_context = ctx.loop_context;
    ctx.loop_context = null;
    // A lambda body is its own cleanup region: reset the defer stack so it
    // never replays the parent's defers, restore it after.
    let saved_defer_stack = ctx.defer_stack;
    ctx.defer_stack = [];
    let saved_current_scope = ctx.current_scope;
    let saved_metadata_scope = ctx.current_metadata_scope;
    // A lambda declares no generic parameters of its own, so its frame is
    // exactly the enclosing one and nothing is appended for the body. The
    // save/restore stays because the body may itself contain lambdas.
    // Rust's `.clone()` snapshot: the field gets a copy, the original is the
    // saved value.
    let saved_lambda_generic_params = ctx.lambda_generic_params;
    ctx.lambda_generic_params = saved_lambda_generic_params.concat([]);
    // `synthetic_ordinals` is intentionally NOT saved: its counters keep
    // incrementing across the whole function for uniqueness.
    //
    // `pending_lambdas` IS saved so each lambda collects only its own direct
    // children; the body's nested lambdas become this lambda's `.lambdas`.
    let saved_pending_lambdas = ctx.pending_lambdas;
    ctx.pending_lambdas = [];
    let saved_capture_indices = ctx.capture_indices;
    ctx.capture_indices = null;
    // After lowering the body, newly discovered transitive captures are in
    // this field; the parent's list is restored after collecting them.
    let saved_transitive_captures = ctx.transitive_captures_needed;
    ctx.transitive_captures_needed = [];

    // Switch to the lambda scope and install the capture map (always a map,
    // even for no HIR captures, so a transitive capture can extend it).
    ctx.current_scope = lambda_scope_id;
    ctx.current_metadata_scope = root.hir.ExprMetadataScopeBody { value: lambda_scope_id };
    ctx.capture_indices = lambda_capture_indices;

    // Set up a fresh builder with the correct arity.
    let arity = func_def.params.length();
    ctx.builder = MirBuilder.new(FunctionOwnerSynthetic { value: lambda_identity }, arity);
    // The lambda's definition span is its expression, so its metadata names
    // the file its body's line table points into.
    if (lambda_definition_span != null) {
        ctx.builder.set_span(lambda_definition_span);
    }

    // Keep the checked parameter types for interface dispatch inside the
    // lambda, including inferred parameters and enclosing generic bounds.
    // Rust's `.clone()` snapshot, as `lambda_generic_params` above.
    let saved_lambda_param_tir_types = ctx.lambda_param_tir_types;
    let lambda_param_tir_types: map<string, root.types.Ty> = {};
    for (let name in saved_lambda_param_tir_types.keys()) {
        lambda_param_tir_types[name] = saved_lambda_param_tir_types[name];
    }
    ctx.lambda_param_tir_types = lambda_param_tir_types;
    // The runtime signature, stamped by emit onto the compiled `Function`
    // object (lambdas have no `func_data`). It is templated over the
    // ENCLOSING frame's slots: `MakeClosure` captures that frame's type args
    // onto the closure, and the body's own `TypeArgRef`s index the same
    // list.
    let sig_frame_params = enclosing_generic_params(ctx);
    let sig_template = (tir_ty: root.types.Ty) -> root.types.TyTemplate {
        tir2_to_template(tir_ty, runtime(ctx), sig_frame_params)
    };
    // Inference owns every signature slot, whether written or omitted:
    // re-lowering annotations here would lose solved `_` holes.
    let lambda_ty = tir_expr_type(ctx, expr_id);
    let (let param_types, let return_type, let throws_type) = match (lambda_ty) {
        let f: root.types.TyFunction => (f.params, f.ret, f.throws_),
        _ => throw internal_error(ctx, "TIR recorded no function type for this lambda", expr_id),
    };
    if (param_types.length() != func_def.params.length()) {
        throw internal_error(
            ctx,
            `TIR typed this lambda with ${param_types.length()} parameter(s), but it declares ${func_def.params.length()}`,
            expr_id,
        );
    }
    let sig_return_type = sig_template(return_type);
    let sig_display_return_type = root.hir_ty.ty_spell(return_type, display_viewpoint(ctx));
    let ret_local_ty = convert_tir_ty_for_runtime(ctx, return_type);

    // Declare return place _0, then parameter locals _1..=_n.
    let ret = ctx.builder.declare_local(ret_local_ty, name = "_0");

    let sig_param_types: root.types.TyTemplate[] = [];
    let sig_display_param_types: string[] = [];
    let param_idx = 0;
    for (let param in func_def.params) {
        let tir_ty = param_types[param_idx].ty;
        ctx.lambda_param_tir_types[param.name] = tir_ty;
        let param_ty = convert_tir_ty_for_runtime(ctx, tir_ty);
        sig_param_types.push(sig_template(tir_ty));
        sig_display_param_types.push(root.hir_ty.ty_spell(tir_ty, display_viewpoint(ctx)));
        declare_parameter(ctx, param_idx, param.name, param_ty);
        param_idx += 1;
    }
    let sig_throws_type = sig_template(throws_type);

    // Create entry and exit blocks.
    let entry = ctx.builder.create_block();
    let exit_blk = ctx.builder.create_block();
    ctx.exit_block = exit_blk;
    ctx.builder.set_current_block(entry);

    // Lower the body expression into the return place.
    lower_expr(ctx, lambda_root, PlaceLocal { value: ret });

    // Terminate: goto exit, then return.
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(ctx.exit_block);
    }
    ctx.builder.set_current_block(ctx.exit_block);
    ctx.builder.return_();

    verify_bindings_recorded(ctx, lambda_scope_id, null);

    // Build the lambda MirFunction. Its direct children are the lambdas
    // lowered while lowering this body (the parent's pending ones are in
    // `saved_pending_lambdas`).
    let nested_lambdas = ctx.pending_lambdas;
    ctx.pending_lambdas = [];

    let lambda_builder = ctx.builder;
    ctx.builder = MirBuilder.new(lambda_builder.owner, 0);
    let lambda_mir = lambda_builder.build();
    optimize_function(db, lambda_mir, ctx.opt);
    // Attach nested lambdas as direct children.
    lambda_mir.lambdas = nested_lambdas;
    lambda_mir.signature
        = RuntimeSignature {
            // A lambda carries neither a docstring nor generic parameters.
            docstring: null,
            display_type_params: [],
            // Its frame is the enclosing one, captured by `MakeClosure`.
            type_param_names: root.types.RuntimeGenericLayout.new(sig_frame_params).params.map((param) -> {
                param.name
            }),
            generic_param_bounds: [],
            display_param_types: sig_display_param_types,
            display_return_type: sig_display_return_type,
            param_names: func_def.params.map((p) -> {
                p.name
            }),
            param_has_default: func_def.params.map((p) -> {
                p.default != null
            }),
            param_types: sig_param_types,
            return_type: sig_return_type,
            throws_type: sig_throws_type,
        };

    // Transitive captures that inner lambda bodies found they needed (not
    // in `hir_captures`).
    let newly_needed_transitive = ctx.transitive_captures_needed;
    ctx.transitive_captures_needed = [];

    // Restore parent state.
    ctx.lambda_param_tir_types = saved_lambda_param_tir_types;
    ctx.builder = saved_builder;
    ctx.binding_locals = saved_binding_locals;
    ctx.catch_rethrow_locals = saved_catch_rethrow_locals;
    ctx.exit_block = saved_exit_block;
    ctx.loop_context = saved_loop_context;
    ctx.defer_stack = saved_defer_stack;
    ctx.current_scope = saved_current_scope;
    ctx.current_metadata_scope = saved_metadata_scope;
    ctx.lambda_generic_params = saved_lambda_generic_params;
    ctx.capture_indices = saved_capture_indices;
    // Restore the parent's pending_lambdas (siblings of this lambda).
    ctx.pending_lambdas = saved_pending_lambdas;
    // Restore the parent's transitive captures (not ours).
    ctx.transitive_captures_needed = saved_transitive_captures;

    let capture_operands = lower_lambda_capture_operands(ctx, hir_captures, newly_needed_transitive, expr_id);

    // Push this lambda into the parent's pending_lambdas and emit MakeClosure.
    let lambda_pending_idx = ctx.pending_lambdas.length();
    ctx.pending_lambdas.push(lambda_mir);

    // A template for each enclosing generic type param, so the closure can
    // materialise them at runtime. These resolve in the OUTER frame.
    let type_arg_templates = enclosing_runtime_type_arg_templates(ctx);

    ctx.builder.assign(
        dest,
        RvalueMakeClosure {
            lambda_idx: lambda_pending_idx,
            captures: capture_operands,
            type_arg_templates: type_arg_templates,
        },
    );
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_lambda @ d9be6853b
// The HIR captures of a lambda scope, as `lower_lambda` and
// `build_tagged_body_closure` read them: a fresh array (Rust's `.clone()`),
// since the caller extends it with transitive captures.
function lambda_hir_captures(
    ctx: LoweringContext,
    lambda_scope_id: int,
) -> (string, root.hir.BindingId)[] throws never {
    let index = root.hir.file_semantic_index(ctx.db, ctx.file);
    let scope_bindings = index.scope_bindings.at(lambda_scope_id);
    if (scope_bindings == null) {
        return [];
    }
    scope_bindings.captures.concat([])
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_lambda @ d9be6853b
// The tail of `lower_lambda` (and of `build_tagged_body_closure`, word for
// word): extend `hir_captures` (in place; the caller's own copy) with the
// transitively needed bindings the body found, then build the capture
// operands from the restored parent locals and captures. Each captured
// binding must be in the parent's locals map: the operand is the cell
// pointer (the slot itself, not its value). A binding the parent has
// neither as a local nor as a capture becomes a new transitive capture of
// the parent, which then forwards it from its own capture slot.
function lower_lambda_capture_operands(
    ctx: LoweringContext,
    hir_captures: (string, root.hir.BindingId)[],
    newly_needed_transitive: root.hir.BindingId[],
    expr_id: int,
) -> Operand[] throws MirInternalError {
    let extended_hir_captures = hir_captures;
    for (let binding_id in newly_needed_transitive) {
        let present = extended_hir_captures.some((existing) -> {
            existing.1 == binding_id
        });
        if (!present) {
            extended_hir_captures.push(("_capture", binding_id));
        }
    }

    let capture_operands: Operand[] = [];
    for (let capture in extended_hir_captures) {
        let binding_id = capture.1;
        let local = ctx.binding_locals.get(binding_id);
        if (local != null) {
            // The operand is the cell pointer, which the local holds only
            // because HIR's capture analysis marked the binding when it was
            // declared. A miss here is a HIR/MIR disagreement.
            if (!ctx.builder.local_decl(local).is_captured) {
                throw internal_error(
                    ctx,
                    `closure captures ${local_to_string(local)}, which was not declared captured`,
                    expr_id,
                );
            }
            capture_operands.push(OperandCopy { value: PlaceLocal { value: local } });
            continue;
        }
        let cap_idx = ctx.capture_indices?.get(binding_id);
        if (cap_idx != null) {
            // The variable is itself a capture in the current scope.
            capture_operands.push(OperandCopy { value: PlaceCapture { value: cap_idx } });
            continue;
        }
        // Not in the current scope's locals or captures: a new transitive
        // capture of the current lambda, so its parent passes it through.
        let ci = ctx.capture_indices;
        if (ci == null) {
            ci = {};
            ctx.capture_indices = ci;
        }
        let new_idx = ci.length();
        ci[binding_id] = new_idx;
        // Signal to our parent lambda that it needs to capture this binding.
        ctx.transitive_captures_needed.push(binding_id);
        capture_operands.push(OperandCopy { value: PlaceCapture { value: new_idx } });
    }
    capture_operands
}
