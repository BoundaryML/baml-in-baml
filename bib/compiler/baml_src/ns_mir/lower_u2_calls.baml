// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// MIR unit 2, part 2: call lowering (lower.rs 8284-10356 in the fork's
// tree): argument operands, the call roads of `lower_call_with_callee`,
// builtin detection (sys-ops, `await_any`, `spawn`, intrinsics,
// `reflect.Type.of`, `Package.current`), call type arguments, and generic
// application (`foo<int>`) and function values.
//
// Restructured (BAML forces it, or the lane does not exist here):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - `lower_call_with_callee` (747 lines in Rust) is split along its own
//   blocks, called in Rust's order with side effects in order:
//   `_path_dispatch` (the interface-typed path receiver road),
//   `_default_delegation` (`default.<method>(..)`), `_member_operands` /
//   `_path_operands` (the callee and argument operands of each callee
//   spelling), `_intrinsics` (the value and void intrinsics after the target
//   block), and `_emit` (type args, owner prefix, `await_any`, `spawn`,
//   sys-ops and the call itself).
// - No root is served from an interface: a served callee's call target
//   (`ExternalCallTarget`, `ExternalCallTarget::slot`) is not ported, so the
//   intrinsic checks panic on a trusted external callee whose row is an
//   intrinsic, and the method roads' `DeclRef::External` arms are dropped
//   (a virtual slot on a source interface always takes `self`).
//   `callable_display_name` is `root.hir.function_data(db, f).name`.
// - `TyTemplate::is_fully_concrete` is "narrows to a `RealizedTy`": in
//   `specialized_function` the narrowing is attempted once and a failure
//   takes the runtime road, as Rust's `all(is_fully_concrete)` then
//   `try_from` does.
// - `DeclName::of_lang_item(lang, kind.class())` over `TypeKind::ALL` is
//   `root.types.is_type_kind_class_decl` (the same test: a root-namespace
//   kind class of the installed `reflect` package).
// - `lower_call_arg_operands` pre-lowers the provided arguments in SOURCE
//   order into a map keyed by argument expression (Rust's `FxHashMap`, used
//   only for lookup), then takes them out in parameter order.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::call_trace_arg @ d9be6853b
function call_trace_arg(ctx: LoweringContext, expr_id: int) -> int? throws never {
    let call_args = match (ctx.body.exprs[expr_id]) {
        let call: root.ast.ExprCall => call.args,
        let call: root.ast.ExprOptionalCall => call.args,
        _ => {
            return null;
        },
    };
    call_args
        .find((arg) -> {
            arg.label == "$trace"
        })
        ?.expr
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_arg_operands @ d9be6853b
function lower_call_arg_operands(
    ctx: LoweringContext,
    expr_id: int,
    args: int[],
) -> Operand[] throws MirInternalError {
    let plan = tir_call_plan(ctx, expr_id);
    if (plan == null) {
        // No call plan: lower each arg in order (the type checker would have
        // already flagged any mismatch).
        let in_order: Operand[] = [];
        for (let arg in args) {
            in_order.push(lower_to_operand(ctx, arg));
        }
        return in_order;
    }

    // A sys-op (`$rust_io_function`) has no bytecode body, so it never runs
    // the default-parameter prologue: an omitted defaulted param is
    // materialized to its declared default HERE.
    let callee_expr = match (ctx.body.exprs[expr_id]) {
        let call: root.ast.ExprCall => call.callee,
        _ => null,
    };
    let sysop_callee = if (callee_expr != null) {
        sys_op_callee(ctx, callee_expr)
    } else {
        null
    };
    // A method-convention sys-op call has a receiver-relative `param_index`
    // (TIR strips `self`), but the callee's default arena is indexed
    // self-inclusive: shift omitted-default indices by one.
    let sysop_self_offset = if (sysop_callee != null && callee_expr != null && callee_uses_method_convention(ctx, callee_expr)) {
        1
    } else {
        0
    };

    // Pre-lower each provided arg in source order (the order `args` appear
    // in the call expression): it preserves the evaluation order of side
    // effects.
    let provided_args = plan.provided_args();
    let trace_arg = call_trace_arg(ctx, expr_id);
    let lowered_args: map<int, Operand> = {};
    for (let arg in args) {
        if (provided_args.includes(arg) || trace_arg == arg) {
            lowered_args[arg] = lower_to_operand(ctx, arg);
        }
    }

    let operands: Operand[] = [];
    for (let binding in plan.bindings) {
        match (binding) {
            let provided: root.hir_ty.ParamBindingProvided => {
                let operand = lowered_args.delete(provided.arg);
                if (operand == null) {
                    throw internal_error(
                        ctx,
                        "the call plan binds an argument the call expression does not have",
                        expr_id,
                    );
                }
                operands.push(operand);
            },
            let omitted: root.hir_ty.ParamBindingOmittedDefault => {
                if (sysop_callee != null) {
                    operands.push(
                        sysop_default_operand(ctx, sysop_callee, omitted.param_index + sysop_self_offset),
                    );
                } else {
                    operands.push(OperandConstant { value: ConstantOmittedArg {} });
                }
            },
        }
    }
    if (trace_arg != null) {
        let trace = lowered_args.delete(trace_arg);
        if (trace == null) {
            throw internal_error(ctx, "trace attachment was not lowered", expr_id);
        }
        operands.push(trace);
    }
    operands
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::sysop_default_operand @ d9be6853b
// Materialize a sys-op parameter's omitted default as a constant operand,
// read from the CALLEE's own defaults arena. Sys-op defaults are constant
// literals today; a non-constant default falls back to `OmittedArg`.
function sysop_default_operand(
    ctx: LoweringContext,
    callee_loc: int,
    param_index: int,
) -> Operand throws never {
    let defaults = root.hir.function_parameter_defaults(ctx.db, callee_loc);
    let default = defaults.param_default(param_index);
    let constant: Constant = if (default == null) {
        ConstantOmittedArg {}
    } else {
        match (defaults.defaults.expr(default.expr)) {
            root.ast.ExprNull => ConstantNull {},
            let literal: root.ast.ExprLiteral => lower_literal(literal.value),
            _ => ConstantOmittedArg {},
        }
    };
    OperandConstant { value: constant }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call @ d9be6853b
// Lower a call expression. `x?.m(...)` enters through
// `lower_optional_method_call`, which emits the null guard and then
// re-enters with the `x.m(...)` shape: `?.` decides *whether* the call
// happens, never *how* it is made.
function lower_call(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    args: int[],
    dest: Place,
) -> void throws MirInternalError {
    let callee_expr = ctx.body.exprs[callee];
    if let optional: root.ast.ExprOptionalMemberAccess = callee_expr {
        let member_call = root.ast.ExprMemberAccess { base: optional.base, member: optional.member };
        lower_optional_method_call(ctx, expr_id, callee, optional.base, member_call, args, dest);
        return;
    }
    lower_call_with_callee(ctx, expr_id, callee, callee_expr, args, dest);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_method_call @ d9be6853b
// Lower `x?.m(...)`: null-test the receiver, then lower the call as
// `x.m(...)` on the non-null path. Inside an enclosing `OptionalChain` the
// null edge joins the chain's shared exit; standalone it builds its own
// null/join blocks. `callee` stays the original expression id, so every TIR
// lookup keys on the node the type checker recorded.
function lower_optional_method_call(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    base: int,
    member_call: root.ast.Expr,
    args: int[],
    dest: Place,
) -> void throws MirInternalError {
    let base_op = lower_to_operand(ctx, base);

    let is_null = RvalueBinaryOp {
        op: BinOp.Eq,
        left: base_op,
        right: OperandConstant { value: ConstantNull {} },
    };
    let test_local = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(PlaceLocal { value: test_local }, is_null);

    let bb_call = ctx.builder.create_block();

    let chain_exit = ctx.chain_null_exits.at(ctx.chain_null_exits.length() - 1);
    if (chain_exit != null) {
        ctx.builder.branch(operand_copy_local(test_local), chain_exit, bb_call);

        ctx.builder.set_current_block(bb_call);
        lower_call_with_callee(ctx, expr_id, callee, member_call, args, dest);
    } else {
        let bb_null = ctx.builder.create_block();
        let bb_join = ctx.builder.create_block();

        ctx.builder.branch(operand_copy_local(test_local), bb_null, bb_call);

        ctx.builder.set_current_block(bb_call);
        lower_call_with_callee(ctx, expr_id, callee, member_call, args, dest);
        if (!ctx.builder.is_current_terminated()) {
            ctx.builder.goto(bb_join);
        }

        ctx.builder.set_current_block(bb_null);
        ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
        ctx.builder.goto(bb_join);

        ctx.builder.set_current_block(bb_join);
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_normalized_callee_operand @ d9be6853b
// Lower the callee as a *value* when the direct-call paths decline it. For
// `x?.m(...)` the null guard has already run and `callee_expr` is the
// normalized `x.m` view: lower the member access itself, not the arena node
// (which would test null again and evaluate the receiver a third time).
function lower_normalized_callee_operand(
    ctx: LoweringContext,
    callee: int,
    callee_expr: root.ast.Expr,
) -> Operand throws MirInternalError {
    if let member: root.ast.ExprMemberAccess = callee_expr {
        if (ctx.body.exprs[callee] is root.ast.ExprOptionalMemberAccess) {
            let ty = expr_ty(ctx, callee);
            let tmp = ctx.builder.declare_local(ty);
            lower_member_access(ctx, callee, member.base, member.member, PlaceLocal { value: tmp });
            return operand_copy_local(tmp);
        }
    }
    lower_to_operand(ctx, callee)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_with_callee @ d9be6853b
// The call roads, tried in order: a UFCS interface-item call, an
// interface-typed member-access receiver, `default.<method>(..)`, an
// interface-typed path receiver, then the ordinary call with its builtin
// detection. Split along Rust's blocks (see the file header).
function lower_call_with_callee(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    callee_expr: root.ast.Expr,
    args: int[],
    dest: Place,
) -> void throws MirInternalError {
    // A UFCS interface-item call, whatever its spelling: the resolution
    // record, not the syntax, routes it.
    if (try_lower_interface_item_call(ctx, expr_id, callee, args, dest)) {
        return;
    }
    if let member: root.ast.ExprMemberAccess = callee_expr {
        // An interface-typed receiver dispatches through a virtual call.
        if (
            allows_interface_method_dispatch(ctx, callee)
                && try_lower_interface_dispatch(ctx, expr_id, callee, member.base, member.member, args, dest)
        ) {
            return;
        }
    }
    if (lower_call_with_callee_default_delegation(ctx, expr_id, callee, callee_expr, args, dest)) {
        return;
    }
    if (lower_call_with_callee_path_dispatch(ctx, expr_id, callee, callee_expr, args, dest)) {
        return;
    }

    // A method call (MemberAccess, or a multi-segment Path with a Method or
    // Free resolution) passes a real-value base as `self`.
    let (let callee_operand, let arg_operands) = match (callee_expr) {
        let member: root.ast.ExprMemberAccess => {
            lower_call_with_callee_member_operands(ctx, expr_id, callee, callee_expr, member.base, args)
        },
        let path: root.ast.ExprPath => {
            lower_call_with_callee_path_operands(ctx, expr_id, callee, path.value.segments, args)
        },
        _ => {
            let callee_op = lower_to_operand(ctx, callee);
            (callee_op, lower_call_arg_operands(ctx, expr_id, args))
        },
    };

    let target = ctx.builder.create_block();
    if (
        lower_call_with_callee_intrinsics(ctx, expr_id, callee, args, callee_operand, arg_operands, dest, target)
    ) {
        return;
    }
    lower_call_with_callee_emit(ctx, expr_id, callee, callee_operand, arg_operands, dest, target);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_with_callee @ d9be6853b
// Part of `lower_call_with_callee`: `default.<method>(...)` inside an
// `implements I { ... }` block emits a static call to `I`'s default
// function, with the class's `self` forwarded as the receiver. No type-tag
// switch: the override is deliberately bypassed. False when the callee is
// not that spelling.
function lower_call_with_callee_default_delegation(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    callee_expr: root.ast.Expr,
    args: int[],
    dest: Place,
) -> bool throws MirInternalError {
    let segments = match (callee_expr) {
        let path: root.ast.ExprPath => path.value.segments,
        _ => {
            return false;
        },
    };
    if (segments.length() != 2 || !is_default_receiver_root(ctx, callee, segments)) {
        return false;
    }
    let (let default_loc, let frame_tys) = default_delegation(ctx, expr_id, segments[1])
        ?? return false;
    let callee_op = OperandConstant { value: ConstantFunction { value: default_loc } };
    let self_local = self_local(ctx);
    if (self_local == null) {
        throw internal_error(ctx, "`default.<method>(..)` outside a method with `self`", expr_id);
    }
    // The frame is the adopted default's `[Self ++ interface args]` followed
    // by a generic default method's own arguments, written or inferred, as at
    // any call.
    let all_args = emit_frame_type_arg_ops(ctx, frame_tys);
    for (let type_arg in lower_call_type_args(ctx, expr_id, true, null)) {
        all_args.push(type_arg);
    }
    let ntypeargs = all_args.length();
    all_args.push(OperandCopy { value: value_place(ctx, self_local) });
    for (let operand in lower_call_arg_operands(ctx, expr_id, args)) {
        all_args.push(operand);
    }
    let argument_layout = call_argument_layout(ctx, expr_id, all_args.length() - ntypeargs);
    let target = ctx.builder.create_block();
    ctx.builder.call_with_type_args(callee_op, all_args, ntypeargs, dest, target);
    ctx.builder.set_call_layout(argument_layout);
    ctx.builder.set_current_block(target);
    true
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_with_callee @ d9be6853b
// Part of `lower_call_with_callee`: a Path whose final segment is a method
// call on an interface-typed receiver (`<value>.<method>()`, or a field chain
// `<value>.<field>.<method>()` whose prefix is interface-typed), or on a
// concrete receiver whose method an impl provides. False when the call does
// not dispatch.
//
// A Session's top-level `let` is a global with no local of its own; the
// receiver root loads it into one. When this road declines, that load is a
// dead store and the ordinary road loads the global again (both reads are
// pure), as in Rust.
function lower_call_with_callee_path_dispatch(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    callee_expr: root.ast.Expr,
    args: int[],
    dest: Place,
) -> bool throws MirInternalError {
    let segments = match (callee_expr) {
        let path: root.ast.ExprPath => path.value.segments,
        _ => {
            return false;
        },
    };
    if (segments.length() < 2 || !allows_interface_method_dispatch(ctx, callee)) {
        return false;
    }
    let recv_root = path_receiver_root(ctx, callee, segments[0])
        ?? return false;
    let method_name = segments[segments.length() - 1];
    let prefix_idx = segments.length() - 2;
    let recv_seg_idx = if (segments.length() == 2) {
        0
    } else {
        prefix_idx
    };
    // The receiver's type: recorded by TIR at the segment just before the
    // method name; else `Self` for a bounded `self`; else a lambda
    // parameter's declared type (no `path_segment_types` entry); else a
    // function parameter's declared type (keeps a bounded `T` a type var, so
    // the method dispatches virtually).
    let recv_tir_ty = tir_path_segment_type(ctx, callee, recv_seg_idx);
    if (recv_tir_ty == null && segments.length() == 2 && segments[0] == "self") {
        let self_param = enclosing_generic_params(ctx).find((param) -> {
            param.name == "Self"
        });
        if (self_param != null && ctx.generic_param_bounds.has(self_param)) {
            recv_tir_ty = root.types.TyTypeVar { param: self_param };
        }
    }
    if (recv_tir_ty == null && segments.length() == 2) {
        recv_tir_ty = ctx.lambda_param_tir_types.get(segments[0]);
    }
    if (recv_tir_ty == null && segments.length() == 2) {
        let binding_id = binding_id_for_path(ctx, callee, segments[0]);
        if (binding_id != null) {
            recv_tir_ty = source_param_tir_ty_for_binding(ctx, segments[0], binding_id);
        }
    }

    let view: InterfaceTypeView? = null;
    let final_resolution = tir_path_final_resolution(ctx, callee);
    if (final_resolution != null) {
        view = virtual_method_view_of(final_resolution);
    }
    if (view == null) {
        if (segments.length() == 2) {
            view = source_param_interface_view_for_name_at(ctx, callee, segments[0], method_name);
        }
        if (view == null && recv_tir_ty != null) {
            view = interface_dispatch_target_for_member(ctx, recv_tir_ty, method_name);
        }
    }
    // A concrete receiver whose method comes from an impl (blanket,
    // out-of-body, or in-body): the providing interface.
    if (view == null && recv_tir_ty != null) {
        view = dispatch_target_for_concrete(ctx, recv_tir_ty, method_name);
    }
    if (view == null) {
        return false;
    }
    // A `self`-less method has no receiver to dispatch on: fall through to
    // the static roads.
    let interface_ = interface_ref_of_type_name(ctx, view.0);
    if (interface_ != null) {
        let shape = interface_method_shape(ctx, interface_, method_name);
        if (shape != null && !shape.takes_self) {
            return false;
        }
    }
    // The interface to key on, or a decline: a declared FIELD is not
    // dispatchable, and `self.<field>(..)` inside a default body spells a
    // PATH, so it lands here rather than on the member-access road.
    let (let decl_tn, let decl_args, let decl_assoc) = dispatch_view_for_call(ctx, view, method_name)
        ?? return false;
    // How many leading segments form the receiver value (the rest are type
    // qualifiers).
    let prefix_is_qualifier = segments.length() >= 3 && segments[prefix_idx] == view.0.name;
    let receiver_segments_end = if (prefix_is_qualifier) {
        prefix_idx
    } else {
        segments.length() - 1
    };
    let receiver_segments = segments.slice(0, receiver_segments_end);
    let recv_local = lower_path_receiver_to_local(ctx, callee, receiver_segments, recv_root);
    // Every interface-mediated call dispatches open-world via a virtual call;
    // the VM resolves the impl from the receiver's runtime concrete type.
    emit_virtual_call(ctx, recv_local, decl_tn, decl_args, decl_assoc, method_name, expr_id, args, dest)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_with_callee @ d9be6853b
// Part of `lower_call_with_callee`: the callee and argument operands of a
// MemberAccess callee. A Method or Free resolution calls the resolved
// callable as a plain function constant (not `MakeBoundMethod`), passing a
// real-value base as `self` when the method takes one; any other resolution
// (a callable field) is called as the value it holds.
function lower_call_with_callee_member_operands(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    callee_expr: root.ast.Expr,
    base: int,
    args: int[],
) -> (Operand, Operand[]) throws MirInternalError {
    let resolution = tir_resolution(ctx, callee);
    let method_or_free = resolution is root.hir_ty.MemberResolutionMethod<root.types.Ty>
        || resolution is root.hir_ty.MemberResolutionFree;
    if (resolution == null || !method_or_free) {
        // With NO resolution, TIR never decided what `.member` is, and
        // calling whatever a fallback read produces drops the receiver.
        if (resolution == null) {
            throw internal_error(
                ctx,
                "MIR found a method call TIR recorded no member resolution for",
                callee,
            );
        }
        let callee_op = lower_normalized_callee_operand(ctx, callee, callee_expr);
        return (callee_op, lower_call_arg_operands(ctx, expr_id, args));
    }
    // Whether the base is a value receiver or a bare type/package path:
    // type-name bases like `Label<int>.method` can have concrete TIR types
    // but are not runtime values. A Session's top-level `let` is a value.
    let base_is_value = match (ctx.body.exprs[base]) {
        let path: root.ast.ExprPath if path.value.segments.length() > 0 => {
            binding_id_for_path(ctx, base, path.value.segments[0]) != null
                || path_root_is_top_level_let(ctx, base)
        },
        _ => tir_expr_type(ctx, base) != null,
    };
    // Static methods have no `self` param and must not get the class
    // reference prepended as an argument.
    let method_takes_self = match (resolution) {
        let free: root.hir_ty.MemberResolutionFree => {
            root.hir_ty.callable_takes_self(ctx.db, free.func)
        },
        let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            match (method.callee) {
                let inherent: root.hir_ty.MethodCalleeInherent => {
                    root.hir_ty.callable_takes_self(ctx.db, inherent.value)
                },
                let concrete: root.hir_ty.MethodCalleeConcrete<root.types.Ty> => {
                    root.hir_ty.callable_takes_self(ctx.db, concrete.func)
                },
                // A virtual interface-method call on a source interface is
                // always on a receiver.
                root.hir_ty.MethodCalleeVirtual<root.types.Ty> => true,
            }
        },
        _ => false,
    };
    if (base_is_value && method_takes_self) {
        // Instance method call `arr.length()`: the receiver is passed
        // explicitly as `self`.
        let receiver_op = lower_to_operand(ctx, base);
        let item = root.hir_ty.member_resolution_callable<root.types.Ty>(resolution, ctx.db);
        let callee_op = if (item != null) {
            OperandConstant { value: ConstantFunction { value: item } }
        } else {
            lower_normalized_callee_operand(ctx, callee, callee_expr)
        };
        let all_args = [receiver_op];
        for (let operand in lower_call_arg_operands(ctx, expr_id, args)) {
            all_args.push(operand);
        }
        return (callee_op, all_args);
    }
    // A non-self method or package function reference (`Factory<int>.create(42)`,
    // `baml.Array.length(array)`). A CLASS-road `self`-less method through a
    // VALUE receiver (`b.build(9)` on `Box<int>`) skips the receiver
    // expression; the call plan still carries the class arguments its static
    // type pins.
    let item = root.hir_ty.member_resolution_callable<root.types.Ty>(resolution, ctx.db);
    let callee_op = if (item != null) {
        OperandConstant { value: ConstantFunction { value: item } }
    } else {
        lower_normalized_callee_operand(ctx, callee, callee_expr)
    };
    (callee_op, lower_call_arg_operands(ctx, expr_id, args))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_with_callee @ d9be6853b
// Part of `lower_call_with_callee`: the callee and argument operands of a
// Path callee. The value-rooted ladder first (`self.method()`,
// `obj.field.method()`: the final resolution is the method), then the flat
// resolution (a package-path method), else the path is a callable value.
function lower_call_with_callee_path_operands(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    segments: string[],
    args: int[],
) -> (Operand, Operand[]) throws MirInternalError {
    let final_resolution = tir_path_final_resolution(ctx, callee);
    let is_local_method = segments.length() >= 2
        && final_resolution != null
        && resolution_is_method_call(ctx, final_resolution);
    let flat_resolution = tir_resolution(ctx, callee);
    let is_pkg_method = !is_local_method
        && segments.length() >= 2
        && flat_resolution != null
        && resolution_is_method_call(ctx, flat_resolution);

    if (is_local_method && final_resolution != null) {
        // The last segment is the method; the ones before it form the
        // receiver, passed explicitly as `self`.
        let receiver_segments = segments.slice(0, segments.length() - 1);
        let item = root.hir_ty.member_resolution_callable<root.types.Ty>(final_resolution, ctx.db);
        let callee_op = if (item != null) {
            OperandConstant { value: ConstantFunction { value: item } }
        } else {
            lower_to_operand(ctx, callee)
        };
        let method_takes_self = match (final_resolution) {
            let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
                match (method.callee) {
                    let inherent: root.hir_ty.MethodCalleeInherent => {
                        root.hir_ty.callable_takes_self(ctx.db, inherent.value)
                    },
                    let concrete: root.hir_ty.MethodCalleeConcrete<root.types.Ty> => {
                        root.hir_ty.callable_takes_self(ctx.db, concrete.func)
                    },
                    root.hir_ty.MethodCalleeVirtual<root.types.Ty> => true,
                }
            },
            _ => false,
        };
        if (!method_takes_self) {
            // Same class-frame rule as the MemberAccess spelling: the call
            // plan carries the receiver's class arguments.
            return (callee_op, lower_call_arg_operands(ctx, expr_id, args));
        }
        let receiver_op: Operand = if (receiver_segments.length() == 1) {
            let root_place = path_receiver_root(ctx, callee, receiver_segments[0]);
            if (root_place != null) {
                OperandCopy { value: root_place }
            } else {
                OperandConstant { value: ConstantNull {} }
            }
        } else {
            // A multi-segment receiver (`user.profile.items`): lowered as a
            // field chain. Its local takes the call's type (an approximation,
            // as in Rust).
            let recv_ty = expr_ty(ctx, callee);
            let recv_local = ctx.builder.declare_local(recv_ty);
            lower_multi_segment_path_as_field_chain(ctx, callee, receiver_segments, PlaceLocal { value: recv_local });
            operand_copy_local(recv_local)
        };
        let all_args = [receiver_op];
        for (let operand in lower_call_arg_operands(ctx, expr_id, args)) {
            all_args.push(operand);
        }
        return (callee_op, all_args);
    }
    if (is_pkg_method && flat_resolution != null) {
        // A package-path method call: the same treatment.
        let item = root.hir_ty.member_resolution_callable<root.types.Ty>(flat_resolution, ctx.db);
        let callee_op = if (item != null) {
            OperandConstant { value: ConstantFunction { value: item } }
        } else {
            lower_to_operand(ctx, callee)
        };
        let root_place = path_receiver_root(ctx, callee, segments[0]);
        if (root_place != null) {
            let all_args: Operand[] = [OperandCopy { value: root_place }];
            for (let operand in lower_call_arg_operands(ctx, expr_id, args)) {
                all_args.push(operand);
            }
            return (callee_op, all_args);
        }
        return (callee_op, lower_call_arg_operands(ctx, expr_id, args));
    }
    let callee_op = lower_to_operand(ctx, callee);
    (callee_op, lower_call_arg_operands(ctx, expr_id, args))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_with_callee @ d9be6853b
// Part of `lower_call_with_callee`: the calls that lower to something other
// than a call, once the target block exists: `reflect.Type.of<T>()` (a
// `LoadType`), `Package.current()`, `.length()` of a language container (a
// `Len`), `string.from(x)` of a primitive, and the void intrinsics
// (`log.*`). True when one of them was emitted.
function lower_call_with_callee_intrinsics(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    args: int[],
    callee_operand: Operand,
    arg_operands: Operand[],
    dest: Place,
    target: int,
) -> bool throws never {
    // `reflect.Type.of<T>()`: a value-producing intrinsic, assigned to `dest`.
    let template = check_type_of_intrinsic(ctx, callee, expr_id);
    if (template != null) {
        ctx.builder.assign(dest, RvalueLoadType { value: template });
        ctx.builder.goto(target);
        ctx.builder.set_current_block(target);
        return true;
    }

    // `Package.current()` is lexical, like `reflect.Type.of`: the enclosing
    // package is this unit's own.
    if (is_current_package_intrinsic(ctx, callee, callee_operand)) {
        ctx.builder.assign(dest, RvalueCurrentPackage {});
        ctx.builder.goto(target);
        ctx.builder.set_current_block(target);
        return true;
    }

    let callee_constant: Constant? = match (callee_operand) {
        let constant: OperandConstant => constant.value,
        _ => null,
    };

    // `length` of the language's containers lowers to `Len`.
    if let function_: ConstantFunction = callee_constant {
        let is_container_length = ["Array", "Map", "Uint8Array"].some((owner) -> {
            is_lang_method(ctx, function_.value, root.base.LangPackage.Baml, owner, "length")
        });
        if (is_container_length && arg_operands.length() > 0) {
            let receiver_operand = arg_operands[0];
            let place = match (receiver_operand) {
                let copy: OperandCopy => copy.value,
                let move: OperandMove => move.value,
                OperandConstant => {
                    let tmp = ctx.builder.declare_local(root.types.TyUnknown {});
                    ctx.builder.assign(
                        PlaceLocal { value: tmp },
                        RvalueUse { value: receiver_operand },
                    );
                    PlaceLocal { value: tmp }
                },
            };
            ctx.builder.assign(dest, RvalueLen { value: place });
            ctx.builder.goto(target);
            ctx.builder.set_current_block(target);
            return true;
        }
    }

    // `string.from(x)` of a primitive: no package can override how a
    // primitive renders (E0139). A string renders as itself; an `int`,
    // `float`, `bool` or `null` goes through the one non-generic formatter.
    let string_from = if let function_: ConstantFunction = callee_constant {
        args.length() == 1
            && arg_operands.length() == 1
            && is_lang_method(ctx, function_.value, root.base.LangPackage.Baml, "String", "from")
    } else {
        false
    };
    if (string_from) {
        let arg_ty = tir_expr_type(ctx, args[0]);
        let rendering = if (arg_ty != null) {
            primitive_rendering(arg_ty)
        } else {
            null
        };
        if (rendering != null) {
            match (rendering) {
                PrimitiveRendering.Itself => {
                    ctx.builder.assign(dest, RvalueUse { value: arg_operands[0] });
                    ctx.builder.goto(target);
                },
                PrimitiveRendering.Formatted => {
                    let formatter = OperandConstant {
                        value: ConstantFunction {
                            value: lang_function(ctx, root.base.LangPackage.Baml, [], "_to_string_primitive"),
                        },
                    };
                    if (dest is PlaceLocal) {
                        ctx.builder.call_with_type_args(formatter, arg_operands, 0, dest, target);
                    } else {
                        let tmp = ctx.builder.declare_local(root.types.TyString {});
                        ctx.builder.call_with_type_args(
                            formatter,
                            arg_operands,
                            0,
                            PlaceLocal { value: tmp },
                            target,
                        );
                        ctx.builder.set_current_block(target);
                        ctx.builder.assign(dest, RvalueUse { value: operand_copy_local(tmp) });
                        return true;
                    }
                },
            }
            ctx.builder.set_current_block(target);
            return true;
        }
    }

    // A compiler intrinsic (`log.*`): a void side effect, emitted as a
    // statement, and the call's `null` result written (`dest` may be the
    // return place).
    let op = check_intrinsic(ctx, callee);
    if (op != null) {
        ctx.builder.push_statement(StatementKindIntrinsic { op: op, args: arg_operands }, null);
        ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
        ctx.builder.goto(target);
        ctx.builder.set_current_block(target);
        return true;
    }
    false
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_with_callee @ d9be6853b
// Part of `lower_call_with_callee`: the call itself. Type arguments are
// `LoadType` temps ahead of the value args (the VM pops `ntypeargs` of them
// into the new frame); a directly called method's owner frame (receiver
// class args, or a matched impl's bindings) is prepended to its own, in De
// Bruijn order. `__await_any` and `__spawn` lower to their terminators, a
// sys-op to `SysOp` (its synthetic type operands trail the value args).
// Call destinations must be locals: a projection or capture destination is
// called into a temp and assigned in a fresh block.
function lower_call_with_callee_emit(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    callee_operand: Operand,
    arg_operands: Operand[],
    dest: Place,
    target: int,
) -> void throws MirInternalError {
    let sys_op_type_arg_count = sys_op_synthetic_type_arg_count(ctx, callee);
    let is_sys_op = sys_op_type_arg_count != null;
    let call_type_arg_operands = lower_call_type_args(ctx, expr_id, true, sys_op_type_arg_count);

    // For `b.describe()` where `b: Box<int>`, `describe` is a direct call
    // `describe(b)`, so the owner-level type args are emitted here:
    //   frame.type_args = [class_T, class_U, ..., fn_A, fn_B, ...]
    let owner_prefix_tys = call_plan_owner_prefix(ctx, expr_id, callee, callee_operand);
    let type_arg_operands: Operand[] = [];
    if (owner_prefix_tys.length() > 0) {
        let generic_params = enclosing_generic_params(ctx);
        for (let ty_arg in owner_prefix_tys) {
            let template = ty_to_template(ctx, ty_arg, generic_params);
            let temp = ctx.builder.declare_local(root.types.TyType {});
            ctx.builder.assign(PlaceLocal { value: temp }, RvalueLoadType { value: template });
            type_arg_operands.push(operand_copy_local(temp));
        }
    }
    for (let operand in call_type_arg_operands) {
        type_arg_operands.push(operand);
    }
    let ntypeargs = type_arg_operands.length();

    let argument_layout = call_argument_layout(ctx, expr_id, arg_operands.length());
    // Type-arg operands lead the value-arg operands.
    let all_arg_operands_for_call = type_arg_operands.concat(arg_operands);

    // `baml.future.__await_any(futures)` lowers to an `AwaitAny` suspend
    // point (like `await`), not a call. Its single value arg is the array of
    // futures.
    if (check_await_any(ctx, callee)) {
        if (arg_operands.length() == 0) {
            throw internal_error(ctx, "`__await_any` was called with no argument", expr_id);
        }
        let futures_operand = arg_operands[0];
        match (dest) {
            let local: PlaceLocal => {
                ctx.builder.await_any(futures_operand, PlaceLocal { value: local.value }, target);
            },
            _ => {
                let call_ty = expr_ty(ctx, expr_id);
                let tmp = ctx.builder.declare_local(call_ty);
                ctx.builder.await_any(futures_operand, PlaceLocal { value: tmp }, target);
                ctx.builder.set_current_block(target);
                let after = ctx.builder.create_block();
                ctx.builder.assign(dest, RvalueUse { value: operand_copy_local(tmp) });
                ctx.builder.goto(after);
                ctx.builder.set_current_block(after);
                return;
            },
        }
        ctx.builder.set_current_block(target);
        return;
    }

    // `baml.spawn.__spawn(plan)` lowers to a `Spawn` terminator: the engine
    // starts the task.
    if (check_spawn(ctx, callee)) {
        let plan_operand = arg_operands.at(0) ?? baml.sys.panic("__spawn takes exactly one (plan) argument");
        match (dest) {
            let local: PlaceLocal => {
                ctx.builder.spawn_(plan_operand, PlaceLocal { value: local.value }, target);
                ctx.builder.set_current_block(target);
            },
            _ => {
                let call_ty = expr_ty(ctx, expr_id);
                let tmp = ctx.builder.declare_local(call_ty);
                ctx.builder.spawn_(plan_operand, PlaceLocal { value: tmp }, target);
                ctx.builder.set_current_block(target);
                let after = ctx.builder.create_block();
                ctx.builder.assign(dest, RvalueUse { value: operand_copy_local(tmp) });
                ctx.builder.goto(after);
                ctx.builder.set_current_block(after);
            },
        }
        return;
    }

    if (is_sys_op) {
        // A sys-op runs inline in the engine and binds its return value into
        // a local; any other destination is written from a temp once the op
        // has returned. Its synthetic type operands are read positionally
        // after the regular value args.
        let dest_local = match (dest) {
            let local: PlaceLocal => local.value,
            _ => ctx.builder.declare_local(root.types.TyNull {}),
        };
        let sys_op_arg_operands = arg_operands.concat(type_arg_operands);
        ctx.builder.sys_op(
            callee_operand,
            sys_op_arg_operands,
            PlaceLocal { value: dest_local },
            target,
        );
        if (!(dest is PlaceLocal)) {
            ctx.builder.set_current_block(target);
            let after = ctx.builder.create_block();
            ctx.builder.assign(dest, RvalueUse { value: operand_copy_local(dest_local) });
            ctx.builder.goto(after);
            ctx.builder.set_current_block(after);
            return;
        }
    } else {
        match (dest) {
            PlaceLocal => {
                ctx.builder.call_with_type_args(
                    callee_operand,
                    all_arg_operands_for_call,
                    ntypeargs,
                    dest,
                    target,
                );
                ctx.builder.set_call_layout(argument_layout);
            },
            _ => {
                let call_ty = expr_ty(ctx, expr_id);
                let tmp = ctx.builder.declare_local(call_ty);
                ctx.builder.call_with_type_args(
                    callee_operand,
                    all_arg_operands_for_call,
                    ntypeargs,
                    PlaceLocal { value: tmp },
                    target,
                );
                ctx.builder.set_call_layout(argument_layout);
                ctx.builder.set_current_block(target);
                let after = ctx.builder.create_block();
                ctx.builder.assign(dest, RvalueUse { value: operand_copy_local(tmp) });
                ctx.builder.goto(after);
                ctx.builder.set_current_block(after);
                return;
            },
        }
    }

    ctx.builder.set_current_block(target);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::callee_uses_method_convention @ d9be6853b
// Whether `callee` resolves to a BOUND method access, i.e. the call uses
// method convention (`self` passed implicitly via the receiver). Mirrors
// TIR's `callee_uses_method_call_convention`.
function callee_uses_method_convention(ctx: LoweringContext, callee: int) -> bool throws never {
    let uses = (resolution: root.hir_ty.MemberResolution?) -> bool {
        match (resolution) {
            let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
                method.receiver == root.hir_ty.Receiver.Bound
            },
            _ => false,
        }
    };
    uses(tir_resolution(ctx, callee)) || uses(tir_path_final_resolution(ctx, callee))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::sys_op_callee @ d9be6853b
function sys_op_callee(ctx: LoweringContext, callee: int) -> int? throws never {
    // Path callee (single- or multi-segment).
    if let path: root.ast.ExprPath = ctx.body.exprs[callee] {
        let segments = path.value.segments;
        let func_loc: int? = null;
        if (segments.length() == 1) {
            let span_start = ctx.source_map?.expr_span(callee).start ?? 0;
            func_loc
                = match (
                    root.hir.resolve_name_at(
                        ctx.db,
                        ctx.file,
                        span_start,
                        segments[0],
                        scope_name = ctx.scope_func_name,
                    )
                ) {
                    root.hir.ResolvedNameBuiltin { value: let def }
                        | root.hir.ResolvedNameItem { value: let def } =>
                    {
                        match (def) {
                            let function_: root.hir.DefinitionFunction => function_.value,
                            _ => null,
                        }
                    },
                    _ => null,
                };
        } else {
            // Multi-segment: the value-rooted ladder's final resolution first,
            // then the flat resolution (package paths).
            let final_resolution = tir_path_final_resolution(ctx, callee);
            if (final_resolution != null) {
                func_loc = resolution_func_loc(final_resolution);
            }
            if (func_loc == null) {
                let flat = tir_resolution(ctx, callee);
                if (flat != null) {
                    func_loc = resolution_func_loc(flat);
                }
            }
        }
        if (func_loc != null) {
            if let builtin: root.hir.FunctionBodyBuiltin = root.hir.function_body(ctx.db, func_loc) {
                if (builtin.value == root.ast.BuiltinKind.Io) {
                    return func_loc;
                }
            }
        }
    }

    // MemberAccess callee (`f.read`, `sock.recv`). `f?.read` resolves to the
    // same member (`?.` only decides *whether* the call happens), so an
    // optional-chained sys-op is recognized too.
    let callee_expr = ctx.body.exprs[callee];
    if (callee_expr is root.ast.ExprMemberAccess || callee_expr is root.ast.ExprOptionalMemberAccess) {
        let resolution = tir_resolution(ctx, callee);
        if (resolution != null) {
            let func_loc = resolution_func_loc(resolution);
            if (func_loc != null) {
                if let builtin: root.hir.FunctionBodyBuiltin = root.hir.function_body(ctx.db, func_loc) {
                    if (builtin.value == root.ast.BuiltinKind.Io) {
                        return func_loc;
                    }
                }
            }
        }
    }

    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::check_await_any @ d9be6853b
function check_await_any(ctx: LoweringContext, callee: int) -> bool throws never {
    callee_builtin_kind(ctx, callee) == root.ast.BuiltinKind.AwaitAny
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::check_spawn @ d9be6853b
function check_spawn(ctx: LoweringContext, callee: int) -> bool throws never {
    callee_builtin_kind(ctx, callee) == root.ast.BuiltinKind.Spawn
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::callee_builtin_kind @ d9be6853b
function callee_builtin_kind(
    ctx: LoweringContext,
    callee: int,
) -> root.ast.BuiltinKind? throws never {
    let external = trusted_external_callee(ctx, callee);
    if (external != null) {
        return external.1.builtin_kind;
    }
    // Path callee (single- or multi-segment).
    if let path: root.ast.ExprPath = ctx.body.exprs[callee] {
        let segments = path.value.segments;
        let func_loc: int? = null;
        if (segments.length() == 1) {
            let span_start = ctx.source_map?.expr_span(callee).start ?? 0;
            func_loc
                = match (
                    root.hir.resolve_name_at(
                        ctx.db,
                        ctx.file,
                        span_start,
                        segments[0],
                        scope_name = ctx.scope_func_name,
                    )
                ) {
                    root.hir.ResolvedNameBuiltin { value: let def }
                        | root.hir.ResolvedNameItem { value: let def } =>
                    {
                        match (def) {
                            let function_: root.hir.DefinitionFunction => function_.value,
                            _ => null,
                        }
                    },
                    _ => null,
                };
        } else {
            // Multi-segment: the value-rooted ladder's final resolution first,
            // then the flat resolution (package paths).
            let final_resolution = tir_path_final_resolution(ctx, callee);
            if (final_resolution != null) {
                func_loc = resolution_func_loc(final_resolution);
            }
            if (func_loc == null) {
                let flat = tir_resolution(ctx, callee);
                if (flat != null) {
                    func_loc = resolution_func_loc(flat);
                }
            }
        }
        if (func_loc != null) {
            if let builtin: root.hir.FunctionBodyBuiltin = root.hir.function_body(ctx.db, func_loc) {
                return builtin.value;
            }
        }
    }

    // MemberAccess callee (`f.read`, `sock.recv`).
    if (ctx.body.exprs[callee] is root.ast.ExprMemberAccess) {
        let resolution = tir_resolution(ctx, callee);
        if (resolution != null) {
            let func_loc = resolution_func_loc(resolution);
            if (func_loc != null) {
                if let builtin: root.hir.FunctionBodyBuiltin = root.hir.function_body(ctx.db, func_loc) {
                    return builtin.value;
                }
            }
        }
    }

    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::sys_op_synthetic_type_arg_count @ d9be6853b
function sys_op_synthetic_type_arg_count(ctx: LoweringContext, callee: int) -> int? throws never {
    // Path callee (single- or multi-segment).
    if let path: root.ast.ExprPath = ctx.body.exprs[callee] {
        let segments = path.value.segments;
        let func_loc: int? = null;
        if (segments.length() == 1) {
            let span_start = ctx.source_map?.expr_span(callee).start ?? 0;
            func_loc
                = match (
                    root.hir.resolve_name_at(
                        ctx.db,
                        ctx.file,
                        span_start,
                        segments[0],
                        scope_name = ctx.scope_func_name,
                    )
                ) {
                    root.hir.ResolvedNameBuiltin { value: let def }
                        | root.hir.ResolvedNameItem { value: let def } =>
                    {
                        match (def) {
                            let function_: root.hir.DefinitionFunction => function_.value,
                            _ => null,
                        }
                    },
                    _ => null,
                };
        } else {
            // Multi-segment: the value-rooted ladder's final resolution first,
            // then the flat resolution (package paths).
            let final_resolution = tir_path_final_resolution(ctx, callee);
            if (final_resolution != null) {
                func_loc = resolution_func_loc(final_resolution);
            }
            if (func_loc == null) {
                let flat = tir_resolution(ctx, callee);
                if (flat != null) {
                    func_loc = resolution_func_loc(flat);
                }
            }
        }
        if (func_loc != null) {
            if let builtin: root.hir.FunctionBodyBuiltin = root.hir.function_body(ctx.db, func_loc) {
                if (builtin.value == root.ast.BuiltinKind.Io) {
                    return synthetic_type_arg_count_for_sys_op(ctx, func_loc);
                }
            }
        }
    }

    // MemberAccess callee (`f.read`, `sock.recv`); `f?.read` names the same
    // member, so the optional-chained shape is a sys-op too.
    let callee_expr = ctx.body.exprs[callee];
    if (callee_expr is root.ast.ExprMemberAccess || callee_expr is root.ast.ExprOptionalMemberAccess) {
        let resolution = tir_resolution(ctx, callee);
        if (resolution != null) {
            let func_loc = resolution_func_loc(resolution);
            if (func_loc != null) {
                if let builtin: root.hir.FunctionBodyBuiltin = root.hir.function_body(ctx.db, func_loc) {
                    if (builtin.value == root.ast.BuiltinKind.Io) {
                        return synthetic_type_arg_count_for_sys_op(ctx, func_loc);
                    }
                }
            }
        }
    }

    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::synthetic_type_arg_count_for_sys_op @ d9be6853b
// The generic params of an IO builtin not already represented by an
// ordinary `type` value param: each gets a synthetic trailing operand.
function synthetic_type_arg_count_for_sys_op(
    ctx: LoweringContext,
    func_loc: int,
) -> int throws never {
    let func = root.hir.function_data(ctx.db, func_loc);
    let declared_type_value_params = func.params
        .filter((param) -> {
            let type_ref = param.type_ref;
            type_ref != null && func.type_refs.get(type_ref).kind is root.hir.TypeRefKindType
        })
        .length();
    let count = func.generic_params.length() - declared_type_value_params;
    if (count < 0) {
        0
    } else {
        count
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::check_intrinsic @ d9be6853b
// The `IntrinsicOp` of a `$compiler_intrinsic` callee (`log.*`). A served
// callee's call target is not ported: a trusted external intrinsic panics.
function check_intrinsic(ctx: LoweringContext, callee: int) -> IntrinsicOp? throws never {
    let external = trusted_external_callee(ctx, callee);
    if (external != null && external.1.builtin_kind == root.ast.BuiltinKind.Intrinsic) {
        baml.sys.panic("check_intrinsic: a served callee's call target is not ported");
    }

    // Path callee (single- or multi-segment).
    if let path: root.ast.ExprPath = ctx.body.exprs[callee] {
        let segments = path.value.segments;
        let func_loc: int? = null;
        if (segments.length() == 1) {
            let span_start = ctx.source_map?.expr_span(callee).start ?? 0;
            func_loc
                = match (
                    root.hir.resolve_name_at(
                        ctx.db,
                        ctx.file,
                        span_start,
                        segments[0],
                        scope_name = ctx.scope_func_name,
                    )
                ) {
                    root.hir.ResolvedNameBuiltin { value: let def }
                        | root.hir.ResolvedNameItem { value: let def } =>
                    {
                        match (def) {
                            let function_: root.hir.DefinitionFunction => function_.value,
                            _ => null,
                        }
                    },
                    _ => null,
                };
        } else {
            let final_resolution = tir_path_final_resolution(ctx, callee);
            if (final_resolution != null) {
                func_loc = resolution_func_loc(final_resolution);
            }
            if (func_loc == null) {
                let flat = tir_resolution(ctx, callee);
                if (flat != null) {
                    func_loc = resolution_func_loc(flat);
                }
            }
        }
        if (func_loc != null) {
            if let builtin: root.hir.FunctionBodyBuiltin = root.hir.function_body(ctx.db, func_loc) {
                if (builtin.value == root.ast.BuiltinKind.Intrinsic) {
                    let pkg = root.hir.file_package(ctx.db, ctx.db.function_locs.get(func_loc).file);
                    if (
                        !lang(ctx).is_(root.base.LangPackage.Log, pkg.root_id)
                            || pkg.namespace_path.length() != 0
                    ) {
                        return null;
                    }
                    return match (root.hir.function_data(ctx.db, func_loc).name) {
                        "info" => IntrinsicOpLog { value: LogLevel.Info },
                        "debug" => IntrinsicOpLog { value: LogLevel.Debug },
                        "warn" => IntrinsicOpLog { value: LogLevel.Warn },
                        "error" => IntrinsicOpLog { value: LogLevel.Error },
                        _ => null,
                    };
                }
            }
        }
    }

    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_current_package_intrinsic @ d9be6853b
// Whether a call's callee is `reflect.Package.current`: a source declaration
// reaches here as the callee operand's function. A served callee's call
// target is not ported: a trusted external intrinsic panics.
function is_current_package_intrinsic(
    ctx: LoweringContext,
    callee: int,
    callee_operand: Operand,
) -> bool throws never {
    let external = trusted_external_callee(ctx, callee);
    if (external != null && external.1.builtin_kind == root.ast.BuiltinKind.Intrinsic) {
        baml.sys.panic("is_current_package_intrinsic: a served callee's call target is not ported");
    }
    match (callee_operand) {
        OperandConstant { value: let constant } => {
            match (constant) {
                let function_: ConstantFunction => {
                    is_lang_method(ctx, function_.value, root.base.LangPackage.Reflect, "Package", "current")
                },
                _ => false,
            }
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::check_type_of_intrinsic @ d9be6853b
// Detect a `reflect.Type.of<T>()` call and return the `TyTemplate` of its
// written type argument: a realized type as a constant, a frame type
// variable as a `TypeArgRef`. Null when the callee is not `reflect.Type.of`
// or the call writes no type argument (the ordinary call path seeds the
// callee frame from the inferred instantiation). A served callee's call
// target is not ported: a trusted external intrinsic panics.
function check_type_of_intrinsic(
    ctx: LoweringContext,
    callee: int,
    call_expr_id: int,
) -> root.types.TyTemplate? throws never {
    // 1. The callee resolves to `reflect.Type.of`.
    let external = trusted_external_callee(ctx, callee);
    if (external != null && external.1.builtin_kind == root.ast.BuiltinKind.Intrinsic) {
        baml.sys.panic("check_type_of_intrinsic: a served callee's call target is not ported");
    }
    let path = match (ctx.body.exprs[callee]) {
        let p: root.ast.ExprPath => p,
        _ => {
            return null;
        },
    };
    let segments = path.value.segments;
    let func_loc: int? = null;
    if (segments.length() == 1) {
        let span_start = ctx.source_map?.expr_span(callee).start ?? 0;
        func_loc
            = match (
                root.hir.resolve_name_at(
                    ctx.db,
                    ctx.file,
                    span_start,
                    segments[0],
                    scope_name = ctx.scope_func_name,
                )
            ) {
                root.hir.ResolvedNameBuiltin { value: let def }
                    | root.hir.ResolvedNameItem { value: let def } =>
                {
                    match (def) {
                        let function_: root.hir.DefinitionFunction => function_.value,
                        _ => null,
                    }
                },
                _ => null,
            };
    } else {
        let final_resolution = tir_path_final_resolution(ctx, callee);
        if (final_resolution != null) {
            func_loc = resolution_func_loc(final_resolution);
        }
        if (func_loc == null) {
            let flat = tir_resolution(ctx, callee);
            if (flat != null) {
                func_loc = resolution_func_loc(flat);
            }
        }
    }
    if (func_loc == null) {
        return null;
    }
    let body = root.hir.function_body(ctx.db, func_loc);
    let is_intrinsic = match (body) {
        let builtin: root.hir.FunctionBodyBuiltin => builtin.value == root.ast.BuiltinKind.Intrinsic,
        _ => false,
    };
    if (!is_intrinsic) {
        return null;
    }
    if (!is_lang_method(ctx, func_loc, root.base.LangPackage.Reflect, "Type", "of")) {
        return null;
    }

    // 2. The written type argument, as TIR resolved it: read from the call
    // plan, never re-resolved from syntax (a `defer` body replayed under a
    // shadowing `let type T = ...` still names the parameter written at the
    // defer site).
    let type_args = match (ctx.body.exprs[call_expr_id]) {
        let call: root.ast.ExprCall => call.type_args,
        _ => {
            return null;
        },
    };
    if (type_args.length() == 0) {
        return null;
    }
    let slot = tir_call_plan(ctx, call_expr_id)?.slots.at(0)
        ?? baml.sys.panic("TIR records a call plan for a call with a written type argument");
    let generic_params = enclosing_generic_params(ctx);
    ty_to_template(ctx, slot.emission_ty, generic_params)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ty_to_template @ d9be6853b
// A `Ty` as a `TyTemplate`: a type variable at position `N` of
// `generic_params` is `TypeArgRef(N)`; everything else recurses
// structurally. Delegates to `tir2_to_template` so the two cannot drift.
function ty_to_template(
    ctx: LoweringContext,
    ty: root.types.Ty,
    generic_params: root.types.ParamTy[],
) -> root.types.TyTemplate throws never {
    tir2_to_template(ty, runtime(ctx), generic_params)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enclosing_generic_params @ d9be6853b
// The generic parameters in scope for the body being lowered: the
// function's frame (class params first for a method on a generic class),
// then the enclosing lambdas', then the visible `let type` bindings. A
// fresh array: the memoized frame is never extended in place.
function enclosing_generic_params(ctx: LoweringContext) -> root.types.ParamTy[] throws never {
    let func_loc = ctx.func_loc;
    let params: root.types.ParamTy[] = if (func_loc != null) {
        root.hir_ty.function_generic_frame(ctx.db, func_loc)
    } else {
        []
    };
    params.concat(ctx.lambda_generic_params).concat(ctx.scoped_type_binding_params)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enclosing_runtime_type_arg_templates @ d9be6853b
function enclosing_runtime_type_arg_templates(
    ctx: LoweringContext,
) -> root.types.TyTemplate[] throws never {
    root.types.RuntimeGenericLayout.new(enclosing_generic_params(ctx)).slots().map((slot) -> {
        root.types.TyTypeArgRef { index: slot }
    })
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enclosing_generic_param_bounds @ d9be6853b
// The interface bounds of the type variables in scope for this body: the
// function's declaration bounds (class prefix, interface `Self` env,
// free-impl generics, own params) plus the bounds of the `let type`
// bindings lowered so far. A fresh map: the memoized bounds are never
// extended in place.
function enclosing_generic_param_bounds(
    ctx: LoweringContext,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    let bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
    let func_loc = ctx.func_loc
        ?? return bounds;
    let declared = root.hir_ty.function_generic_bounds(ctx.db, func_loc);
    for (let param in declared.keys()) {
        bounds[param] = declared[param];
    }
    for (let param in ctx.generic_param_bounds.keys()) {
        if (param.is_scoped()) {
            bounds[param] = ctx.generic_param_bounds[param];
        }
    }
    bounds
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_frame_type_arg_ops @ d9be6853b
// Emit `LoadType` temps for type args seeding a callee frame, one operand
// per arg, in order. `TypeVar`s lower against the *caller's*
// `enclosing_generic_params`, so they substitute against the caller's frame
// at runtime.
function emit_frame_type_arg_ops(
    ctx: LoweringContext,
    tys: root.types.Ty[],
) -> Operand[] throws never {
    let ops: Operand[] = [];
    if (tys.length() == 0) {
        return ops;
    }
    let generic_params = enclosing_generic_params(ctx);
    for (let ty in tys) {
        let template = ty_to_template(ctx, ty, generic_params);
        let temp = ctx.builder.declare_local(root.types.TyType {});
        ctx.builder.assign(PlaceLocal { value: temp }, RvalueLoadType { value: template });
        ops.push(operand_copy_local(temp));
    }
    ops
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_scoped_type_binding @ d9be6853b
// `let type T extends ... = operand else { ... };`: evaluate the operand and
// store it in the frame slot reserved for `T`'s rigid parameter, then check
// each declared bound against the type now bound to `T`, in written order. A
// miss runs the `else` block, which TIR requires on a bounded statement and
// made diverge.
function emit_scoped_type_binding(
    ctx: LoweringContext,
    binding: root.hir_ty.ScopedTypeBinding,
    else_branch: int?,
) -> void throws MirInternalError {
    let operand = lower_to_operand(ctx, binding.operand);
    let value = type_operand_as_type(ctx, binding.operand, operand);
    let generic_params = enclosing_generic_params(ctx);
    let slot = root.types.RuntimeGenericLayout.new(generic_params).slot(binding.parameter)
        ?? baml.sys.panic("a scoped type parameter has a frame slot");
    ctx.builder.push_statement(
        StatementKindIntrinsic { op: IntrinsicOpBindType { value: slot }, args: [value] },
        ctx.builder.current_source_span,
    );
    if (binding.bounds.length() == 0) {
        return;
    }
    if (else_branch == null) {
        throw internal_error(
            ctx,
            "a bounded `let type` reached lowering without the `else` block TIR requires",
            binding.operand,
        );
    }
    let bound_type = load_type_value(ctx, root.types.TyTypeVar { param: binding.parameter }, generic_params);
    let miss = ctx.builder.create_block();
    for (let bound in binding.bounds) {
        let bound_template = tir2_interface_to_template(
            bound.name,
            bound.generics,
            bound.associated_types.map((assoc) -> {
                (assoc.name, assoc.ty)
            }),
            runtime(ctx),
            generic_params,
        );
        let satisfied = ctx.builder.declare_local(root.types.TyBool {});
        ctx.builder.assign(
            PlaceLocal { value: satisfied },
            RvalueSatisfiesBound { ty: bound_type, bound: bound_template },
        );
        let next = ctx.builder.create_block();
        ctx.builder.branch(operand_copy_local(satisfied), next, miss);
        ctx.builder.set_current_block(next);
    }
    let bound_block = ctx.builder.current_block();
    ctx.builder.set_current_block(miss);
    let else_ty = expr_ty(ctx, else_branch);
    let else_dest = ctx.builder.declare_local(else_ty);
    lower_expr(ctx, else_branch, PlaceLocal { value: else_dest });
    // As for `let ... else`: a recovery state could leave a fall-through.
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.unreachable();
    }
    ctx.builder.set_current_block(bound_block);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_operand_needs_as_type @ d9be6853b
// Whether a `let type` operand of static type `ty` needs its own `as_type()`
// before the VM binds it. The VM unwraps `reflect.Type` and the kind views
// itself; any other `reflect.TypeView` does not reach it as a `type` value.
function type_operand_needs_as_type(ctx: LoweringContext, ty: root.types.Ty) -> bool throws never {
    let lang = lang(ctx);
    let unwrapped_by_vm = (member: root.types.Ty) -> bool {
        match (member) {
            root.types.TyType | root.types.TyNever => true,
            let class_: root.types.TyClass => root.types.is_type_kind_class_decl(lang, class_.name),
            _ => false,
        }
    };
    match (ty) {
        let union: root.types.TyUnion => !union.members.every(unwrapped_by_vm),
        _ => !unwrapped_by_vm(ty),
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_operand_as_type @ d9be6853b
// The `let type` operand `value` as the VM's type-operand boundary takes it:
// a `reflect.TypeView` the VM does not unwrap itself goes through its own
// `as_type()`.
function type_operand_as_type(
    ctx: LoweringContext,
    operand: int,
    value: Operand,
) -> Operand throws MirInternalError {
    let operand_ty = tir_expr_type(ctx, operand);
    if (operand_ty == null || !type_operand_needs_as_type(ctx, operand_ty)) {
        return value;
    }
    let reflect = lang(ctx).get(root.base.LangPackage.Reflect);
    if (reflect == null) {
        throw internal_error(
            ctx,
            "`let type` takes a `reflect.TypeView`, but the `reflect` language package is not installed",
            operand,
        );
    }
    let type_view = root.types.DeclName { pkg: reflect, namespace: [], name: "TypeView" };
    // `TypeView` is non-generic and declares no associated types.
    let iface = tir2_interface_to_template(type_view, [], [], runtime(ctx), []);
    let converted = ctx.builder.declare_local(root.types.TyType {});
    emit_virtual_call_with_operands(
        ctx,
        iface,
        "as_type",
        [value],
        0,
        0,
        null,
        root.types.TyType {},
        PlaceLocal { value: converted },
    );
    operand_copy_local(converted)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::load_type_value @ d9be6853b
// A `reflect.Type` value for `ty`, realized in the enclosing frame.
function load_type_value(
    ctx: LoweringContext,
    ty: root.types.Ty,
    generic_params: root.types.ParamTy[],
) -> Operand throws never {
    let template = ty_to_template(ctx, ty, generic_params);
    let temp = ctx.builder.declare_local(root.types.TyType {});
    ctx.builder.assign(PlaceLocal { value: temp }, RvalueLoadType { value: template });
    operand_copy_local(temp)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::call_plan_owner_prefix @ d9be6853b
// The owner frame a statically resolved callee expects ahead of its own type
// arguments: the call plan's owner prefix (a method's receiver class args, a
// static's qualifier pins, a matched impl's bindings or `[Self, iface
// args..]`). A virtual call takes no prefix: its dispatcher supplies the
// frame of the impl it selects. A plan whose frame is narrower or wider than
// the callee's declared one is an internal inconsistency.
function call_plan_owner_prefix(
    ctx: LoweringContext,
    call: int,
    callee: int,
    callee_operand: Operand,
) -> root.types.Ty[] throws MirInternalError {
    if let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> = tir_resolution(ctx, callee) {
        if (method.callee is root.hir_ty.MethodCalleeVirtual<root.types.Ty>) {
            return [];
        }
    }
    let plan = tir_call_plan(ctx, call);
    let func: int? = match (callee_operand) {
        OperandConstant { value: let constant } => {
            match (constant) {
                let function_: ConstantFunction => function_.value,
                _ => null,
            }
        },
        _ => null,
    };
    if (func != null) {
        let frame_len = root.hir_ty.callable_generic_frame(ctx.db, func).params.length();
        let plan_len = plan?.type_args?.length() ?? 0;
        if (plan_len != frame_len) {
            throw internal_error(
                ctx,
                `the call plan of \`${root.hir.function_data(ctx.db, func).name}\` instantiates ${plan_len} frame slot(s), but its frame has ${frame_len}`,
                call,
            );
        }
    }
    if (plan == null) {
        return [];
    }
    plan.type_args.slice(0, plan.own_offset)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_type_args @ d9be6853b
// The call's type-argument operands: every WRITTEN slot of the plan (the
// plan is authoritative; written types are never re-lowered from syntax),
// else, with `include_inferred`, the inferred callable-owned suffix (the
// receiver or dispatcher supplies the owner prefix). At most `max_count`.
function lower_call_type_args(
    ctx: LoweringContext,
    call_expr_id: int,
    include_inferred: bool,
    max_count: int?,
) -> Operand[] throws never {
    let none: Operand[] = [];
    if (max_count == 0) {
        return none;
    }
    let plan = tir_call_plan(ctx, call_expr_id)
        ?? return none;

    if (plan.slots.length() > 0) {
        let limit = max_count ?? plan.slots.length();
        let generic_params = enclosing_generic_params(ctx);
        let operands: Operand[] = [];
        for (let slot in plan.slots.slice(0, limit)) {
            let template = ty_to_template(ctx, slot.emission_ty, generic_params);
            let temp = ctx.builder.declare_local(root.types.TyType {});
            ctx.builder.assign(PlaceLocal { value: temp }, RvalueLoadType { value: template });
            operands.push(operand_copy_local(temp));
        }
        return operands;
    }

    if (!include_inferred || plan.explicit) {
        return none;
    }

    // Every inferred slot is seeded, an all-`unknown` list included: a
    // callee frame always supplies every slot its templates reference.
    let inferred_type_args = plan.type_args.slice(plan.own_offset, plan.type_args.length()).map((ty) -> {
        root.types.widen_fresh(ty)
    });
    if (max_count != null) {
        inferred_type_args = inferred_type_args.slice(0, max_count);
    }
    emit_frame_type_arg_ops(ctx, inferred_type_args)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_generic_apply @ d9be6853b
// Lower `foo<int>` (a `GenericApply` value). A function base with fully
// concrete type args is a pooled, interned `ConstantGenericFunction`;
// runtime callable values and parameter-dependent arguments are specialized
// at runtime, keeping their existing bindings.
function lower_generic_apply(
    ctx: LoweringContext,
    expr_id: int,
    base: int,
    dest: Place,
) -> void throws MirInternalError {
    // An interface item has no global of its own to pool: its turbofish value
    // is the type-keyed callable the bare reference is, with the written
    // arguments in the plan keyed at this expression.
    let item_callee = unbound_interface_item_callee(ctx, base);
    if (item_callee != null) {
        lower_type_keyed_item_reference(ctx, expr_id, item_callee, dest);
        return;
    }
    let item = try_resolve_generic_apply_base(ctx, base);
    if (item == null) {
        // A value base (a local or captured generic function value): wrap
        // the runtime value in a closure carrying the frame-resolved type
        // args instead of silently erasing them.
        let value = lower_to_operand(ctx, base);
        let type_arg_templates = planned_generic_apply_type_arg_templates(ctx, expr_id);
        ctx.builder.assign(
            dest,
            RvalueMakeGenericFunctionFromValue {
                value: value,
                type_arg_templates: type_arg_templates,
            },
        );
        return;
    }
    let templates = planned_generic_apply_type_arg_templates(ctx, expr_id);
    ctx.builder.assign(dest, specialized_function(item, templates));
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::specialized_function @ d9be6853b
// A function item specialized at `templates`: a pooled, interned constant
// when every argument is concrete (each template narrows to the
// `RealizedTy` the runtime carries), else a value built at runtime,
// resolving the templates against the current frame.
function specialized_function(
    item: int,
    templates: root.types.TyTemplate[],
) -> Rvalue throws never {
    let concrete: root.types.RealizedTy[] = [];
    for (let template in templates) {
        let realized = root.types.narrow_ty_template_to_realized_ty(template) catch (e) {
            root.types.NarrowError => {
                return RvalueMakeGenericFunction { func: item, type_arg_templates: templates };
            },
        };
        concrete.push(realized);
    }
    RvalueUse {
        value: OperandConstant { value: ConstantGenericFunction { func: item, type_args: concrete } },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::inferred_value_type_arg_templates @ d9be6853b
// The own type arguments TIR inferred for a generic function referenced as a
// VALUE at `expr_id` (`xs.map(wrap)`, `C.make`, `x.make`), as the templates
// the value carries: the trailing run of `callee`'s frame, minus synthetic
// effect parameters (slot-less by ABI). Null when the reference
// instantiates nothing of its own; written arguments ride the generic-apply
// road instead.
function inferred_value_type_arg_templates(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
) -> root.types.TyTemplate[]? throws MirInternalError {
    let plan = tir_call_plan(ctx, expr_id)
        ?? return null;
    if (plan.slots.length() > 0 || plan.explicit) {
        return null;
    }
    let own = plan.type_args.slice(plan.own_offset, plan.type_args.length());
    if (own.length() == 0) {
        return null;
    }
    let frame = root.hir_ty.callable_generic_frame(ctx.db, callee).params;
    if (frame.length() < own.length()) {
        throw internal_error(
            ctx,
            "a function value's recorded instantiation is wider than its callee's frame",
            expr_id,
        );
    }
    let own_start = frame.length() - own.length();
    let generic_params = enclosing_generic_params(ctx);
    let templates: root.types.TyTemplate[] = [];
    let i = 0;
    while (i < own.length()) {
        if (!is_slotless_effect_param(frame[own_start + i])) {
            templates.push(ty_to_template(ctx, root.types.widen_fresh(own[i]), generic_params));
        }
        i += 1;
    }
    if (templates.length() == 0) {
        return null;
    }
    templates
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::function_item_value @ d9be6853b
// The value of a function item referenced at `expr_id`: the pooled function
// constant, specialized at the reference's inferred own type arguments when
// it has any.
function function_item_value(
    ctx: LoweringContext,
    expr_id: int,
    item: int,
) -> Rvalue throws MirInternalError {
    let templates = inferred_value_type_arg_templates(ctx, expr_id, item);
    if (templates != null) {
        return specialized_function(item, templates);
    }
    RvalueUse { value: OperandConstant { value: ConstantFunction { value: item } } }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::assign_bound_method_value @ d9be6853b
// `dest = receiver.item` as a bound method value: the receiver supplies the
// owner prefix of the frame, and the reference's inferred own type
// arguments, when it has any, are appended to it.
function assign_bound_method_value(
    ctx: LoweringContext,
    expr_id: int,
    dest: Place,
    item: int,
    receiver: Operand,
) -> void throws MirInternalError {
    let bound = RvalueMakeBoundMethod { func: item, receiver: receiver, frame: BoundFrameReceiver {} };
    assign_specialized_bound_value(ctx, expr_id, dest, item, bound);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::assign_specialized_bound_value @ d9be6853b
// `dest = bound`, a callable value already bound to its receiver, with the
// reference's inferred own type arguments, when it has any, appended to the
// frame the receiver supplies. `callee` sizes the own generics it carries.
function assign_specialized_bound_value(
    ctx: LoweringContext,
    expr_id: int,
    dest: Place,
    callee: int,
    bound: Rvalue,
) -> void throws MirInternalError {
    let type_arg_templates = inferred_value_type_arg_templates(ctx, expr_id, callee);
    if (type_arg_templates == null) {
        ctx.builder.assign(dest, bound);
        return;
    }
    let bound_ty = expr_ty(ctx, expr_id);
    let bound_local = ctx.builder.declare_local(bound_ty);
    ctx.builder.assign(PlaceLocal { value: bound_local }, bound);
    ctx.builder.assign(
        dest,
        RvalueMakeGenericFunctionFromValue {
            value: operand_copy_local(bound_local),
            type_arg_templates: type_arg_templates,
        },
    );
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::unbound_interface_item_callee @ d9be6853b
// The callee of `base` when it is an UNBOUND interface item: the type-rooted
// spellings `I.m`, `C.m`, `(C as I).m`.
function unbound_interface_item_callee(
    ctx: LoweringContext,
    base: int,
) -> root.hir_ty.MethodCallee? throws never {
    let resolution = tir_path_final_resolution(ctx, base) ?? tir_resolution(ctx, base)
        ?? return null;
    match (resolution) {
        let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            if (method.receiver != root.hir_ty.Receiver.Unbound) {
                return null;
            }
            match (method.callee) {
                root.hir_ty.MethodCalleeVirtual<root.types.Ty>
                    | root.hir_ty.MethodCalleeConcrete<root.types.Ty> =>
                {
                    method.callee
                },
                root.hir_ty.MethodCalleeInherent => null,
            }
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_resolve_generic_apply_base @ d9be6853b
// Resolve a `GenericApply` base to the underlying function with a global of
// its own (a free function or a class-inherent static). Null for bound
// methods, lambdas, interface items, or anything that is not a function
// path.
function try_resolve_generic_apply_base(ctx: LoweringContext, base: int) -> int? throws never {
    let is_fn = (resolution: root.hir_ty.MemberResolution) -> bool {
        match (resolution) {
            root.hir_ty.MemberResolutionFree => true,
            let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
                method.callee is root.hir_ty.MethodCalleeInherent
                    && method.receiver == root.hir_ty.Receiver.Unbound
            },
            _ => false,
        }
    };
    // Multi-segment paths: static methods, qualified free fns
    // (`baml.json.decode`).
    let final_resolution = tir_path_final_resolution(ctx, base);
    if (final_resolution != null && is_fn(final_resolution)) {
        let item = root.hir_ty.member_resolution_callable<root.types.Ty>(final_resolution, ctx.db);
        if (item != null) {
            return item;
        }
    }
    // Flat / package resolutions.
    let flat = tir_resolution(ctx, base);
    if (flat != null && is_fn(flat)) {
        let item = root.hir_ty.member_resolution_callable<root.types.Ty>(flat, ctx.db);
        if (item != null) {
            return item;
        }
    }
    // Single-name free function / builtin.
    if let path: root.ast.ExprPath = ctx.body.exprs[base] {
        let segments = path.value.segments;
        if (segments.length() == 1) {
            let span_start = ctx.source_map?.expr_span(base).start ?? 0;
            match (
                root.hir.resolve_name_at(
                    ctx.db,
                    ctx.file,
                    span_start,
                    segments[0],
                    scope_name = ctx.scope_func_name,
                )
            ) {
                root.hir.ResolvedNameItem { value: let def }
                    | root.hir.ResolvedNameBuiltin { value: let def } =>
                {
                    if let function_: root.hir.DefinitionFunction = def {
                        return function_.value;
                    }
                },
                _ => {},
            }
        }
    }
    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::planned_generic_apply_type_arg_templates @ d9be6853b
// The `TyTemplate`s of a `GenericApply`'s written type args, as TIR resolved
// them (its call plan keyed at the apply expression). A template carries a
// `TypeArgRef` when the arg names an enclosing type variable.
function planned_generic_apply_type_arg_templates(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.TyTemplate[] throws never {
    let plan = tir_call_plan(ctx, expr_id)
        ?? baml.sys.panic("TIR records a call plan for a generic apply's written type arguments");
    let generic_params = enclosing_generic_params(ctx);
    plan.slots.map((slot) -> {
        ty_to_template(ctx, slot.emission_ty, generic_params)
    })
}
