// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// MIR unit 2, part 3: interface and structural dispatch (lower.rs
// 11174-12202 in the fork's tree): the member-access dispatch road, the
// closed structural witnesses devirtualized to their native functions,
// `VirtualCall` emission, virtual bound methods, virtual field reads and
// stores, projection reduction through the `hir_ty` facts oracle, the
// `requires`-closure views, and the implements-block `Self`.
//
// Restructured (BAML forces it, or the lane does not exist here):
// - `LoweringContext` methods are free functions taking `ctx` first;
//   `structural_witness`'s nested `fn has_closed_implementations` is a free
//   function.
// - No root is served from an interface: `interface_method_shape` reads the
//   source declaration only (its `DeclRef::External` arm, over the
//   `extern_*` rows, is dropped), and the `requires` closure's External
//   members panic. `callable_signature` is `root.hir_ty.function_signature_ty`.
// - `baml_type::Interface::new` (which sorts associated types by name) is
//   the `InterfaceConstraint` literal with its bindings sorted;
//   `Interface::to_ty` is `plain_interface_ty`.
// - `hir_facts` clones the context's bounds (Rust's `.clone()`): the facts
//   oracle may add bounds to its own map.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_interface_dispatch @ d9be6853b
// Dispatch a method call on an interface-typed (or impl-providing concrete)
// receiver through an open-world virtual call. False (without touching the
// builder) when the receiver does not dispatch: the regular call lowering
// then runs.
function try_lower_interface_dispatch(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    base: int,
    method: string,
    args: int[],
    dest: Place,
) -> bool throws MirInternalError {
    // Same view the field form uses, so `x?.m()` dispatches on the non-null
    // receiver instead of declining on the `T | null` union.
    let view = dispatch_target_for_member_access(ctx, callee, base, method)
        ?? return false;
    // A `self`-less interface method cannot dispatch on a receiver. Asked of
    // the RECEIVER's interface, before the closure walk narrows to the
    // declaring one.
    let interface_ = interface_ref_of_type_name(ctx, view.0);
    if (interface_ != null) {
        let shape = interface_method_shape(ctx, interface_, method);
        if (shape != null && !shape.takes_self) {
            return false;
        }
    }
    // The shared call funnel devirtualizes a closed structural witness;
    // otherwise the VM resolves the impl from the runtime concrete type.
    // `dispatch_view_for_call` supplies the declaring interface, or declines
    // this road for a field.
    let (let decl_tn, let decl_args, let decl_assoc) = dispatch_view_for_call(ctx, view, method)
        ?? return false;
    let receiver_op = lower_to_operand(ctx, base);
    let receiver_ty = expr_ty(ctx, base);
    let recv_local = operand_to_local(ctx, receiver_op, receiver_ty);
    emit_virtual_call(ctx, recv_local, decl_tn, decl_args, decl_assoc, method, expr_id, args, dest)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::structural_witness::has_closed_implementations @ d9be6853b
// Concrete nominal types are not closed: a later Session submission can add
// an impl while retaining previously compiled callers. Only builtin types
// with recursively closed components can be devirtualized.
function has_closed_implementations(ty: root.types.Ty) -> bool throws never {
    match (ty) {
        let list: root.types.TyList => has_closed_implementations(list.elem),
        let map_ty: root.types.TyMap => {
            has_closed_implementations(map_ty.key) && has_closed_implementations(map_ty.value)
        },
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyBool
            | root.types.TyString
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyType
            | root.types.TyLiteral =>
        {
            true
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::structural_witness @ d9be6853b
// The structural default `self_ty` implements `interface_` by, when that is
// the implementation and every implementation of `self_ty` is closed.
function structural_witness(
    ctx: LoweringContext,
    self_ty: root.types.Ty,
    interface_: root.types.DeclName,
) -> root.types.StructuralInterface? throws never {
    if (root.hir_ty.structural_interface(ctx.db, interface_) == null) {
        return null;
    }
    if (!has_closed_implementations(self_ty)) {
        return null;
    }
    let pool = ctx.db.ty_memo.pool;
    let goal = root.types.infer_interface_new(interface_, [], []);
    match (root.hir_ty.resolve_implementation(ctx.db, pool.from_plain(self_ty), goal)) {
        let structural: root.hir_ty.ResolvedImplementationStructuralDefault => structural.value,
        root.hir_ty.ResolvedImplementationExplicit => null,
        null => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::structural_function_rvalue @ d9be6853b
// The native function a closed structural witness's primary method runs, as
// a pooled constant; null when `method` is not that method or its type
// argument does not realize.
function structural_function_rvalue(
    ctx: LoweringContext,
    self_ty: root.types.Ty,
    interface_: root.types.DeclName,
    method: string,
) -> Rvalue? throws never {
    let kind = structural_witness(ctx, self_ty, interface_)
        ?? return null;
    if (method != root.types.structural_interface_primary_method(kind)) {
        return null;
    }
    let func = lang_function(ctx, root.base.LangPackage.Baml, [], root.types.structural_interface_native_function(kind));
    let type_args: root.types.RealizedTy[] = [];
    if (root.types.structural_interface_native_type_arg_count(kind) != 0) {
        let template = ty_to_template(ctx, self_ty, enclosing_generic_params(ctx));
        let realized = root.types.narrow_ty_template_to_realized_ty(template) catch (e) {
            root.types.NarrowError => {
                return null;
            },
        };
        type_args.push(realized);
    }
    RvalueUse {
        value: OperandConstant { value: ConstantGenericFunction { func: func, type_args: type_args } },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_direct_structural_call @ d9be6853b
// A direct call of a structural witness's native function. The checked
// layout is kept only where it differs from the native function's own.
function emit_direct_structural_call(
    ctx: LoweringContext,
    func: int,
    args: Operand[],
    ntypeargs: int,
    layout: root.types.CallLayout?,
    result_ty: root.types.RuntimeTy,
    dest: Place,
) -> void throws never {
    let native_layout = root.types.CallLayout.from_modes(
        root.hir_ty.function_signature_ty(ctx.db, func).params.map((param) -> {
            (param.name, param.mode)
        }),
    );
    let call_layout = if (layout != null && layout != native_layout) {
        layout
    } else {
        null
    };
    let call_dest = if (dest is PlaceLocal) {
        dest
    } else {
        PlaceLocal { value: ctx.builder.declare_local(result_ty) }
    };
    let resume = ctx.builder.create_block();
    ctx.builder.call_with_type_args(
        OperandConstant { value: ConstantFunction { value: func } },
        args,
        ntypeargs,
        call_dest,
        resume,
    );
    ctx.builder.set_call_layout(call_layout);
    ctx.builder.set_current_block(resume);
    if (call_dest != dest) {
        ctx.builder.assign(dest, RvalueUse { value: OperandCopy { value: call_dest } });
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_call @ d9be6853b
// Emit an interface call, directly for a closed structural witness and
// otherwise through `TerminatorVirtualCall`. The receiver is the first value
// argument. Always true: the type checker has proved the receiver implements
// the interface.
function emit_virtual_call(
    ctx: LoweringContext,
    recv_local: int,
    iface_tn: root.types.DeclName,
    iface_type_args: root.types.Ty[],
    iface_assoc: (string, root.types.Ty)[],
    method: string,
    expr_id: int,
    args: int[],
    dest: Place,
) -> bool throws MirInternalError {
    let value_ops: Operand[] = [operand_copy_local(recv_local)];
    for (let operand in lower_call_arg_operands(ctx, expr_id, args)) {
        value_ops.push(operand);
    }
    emit_virtual_call_with_value_operands(ctx, 0, value_ops, iface_tn, iface_type_args, iface_assoc, method, expr_id, dest)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_call_with_value_operands @ d9be6853b
// Emit an open-world `TerminatorVirtualCall` over lowered value operands:
// `value_ops` in the method's declared parameter order, of which
// `value_ops[self_arg]` is the one the VM derives `Self` from. The method's
// own type arguments are lowered here, off the interface that DECLARES the
// method.
function emit_virtual_call_with_value_operands(
    ctx: LoweringContext,
    self_arg: int,
    value_ops: Operand[],
    iface_tn: root.types.DeclName,
    iface_type_args: root.types.Ty[],
    iface_assoc: (string, root.types.Ty)[],
    method: string,
    expr_id: int,
    dest: Place,
) -> bool throws MirInternalError {
    if (iface_type_args.length() == 0 && iface_assoc.length() == 0) {
        let receiver: int? = match (value_ops.at(self_arg)) {
            OperandCopy { value: PlaceLocal { value: let local } } => local,
            _ => null,
        };
        if (receiver != null) {
            let self_ty = root.types.widen_runtime_ty_to_ty(ctx.builder.local_ty(receiver));
            let kind = structural_witness(ctx, self_ty, iface_tn);
            if (kind != null && method == root.types.structural_interface_primary_method(kind)) {
                let layout = call_argument_layout(ctx, expr_id, value_ops.length());
                // `x.to_string()` on a primitive, like `string.from(x)`: no
                // package can override how a primitive renders (E0139), so it
                // skips the structural renderer.
                if (kind == root.types.StructuralInterface.ToString && value_ops.length() == 1) {
                    let rendering = primitive_rendering(self_ty);
                    if (rendering != null) {
                        match (rendering) {
                            PrimitiveRendering.Itself => {
                                ctx.builder.assign(dest, RvalueUse { value: value_ops[0] });
                            },
                            PrimitiveRendering.Formatted => {
                                let func = lang_function(ctx, root.base.LangPackage.Baml, [], "_to_string_primitive");
                                emit_direct_structural_call(ctx, func, value_ops, 0, layout, root.types.TyString {}, dest);
                            },
                        }
                        return true;
                    }
                }
                let structural_args: Operand[] = [];
                let native_type_arg_count = root.types.structural_interface_native_type_arg_count(kind);
                if (native_type_arg_count != 0) {
                    let ty = ty_to_template(ctx, self_ty, enclosing_generic_params(ctx));
                    let local = ctx.builder.declare_local(root.types.TyType {});
                    ctx.builder.assign(PlaceLocal { value: local }, RvalueLoadType { value: ty });
                    structural_args.push(operand_copy_local(local));
                }
                for (let operand in value_ops) {
                    structural_args.push(operand);
                }
                let func = lang_function(
                    ctx,
                    root.base.LangPackage.Baml,
                    [],
                    root.types.structural_interface_native_function(kind),
                );
                emit_direct_structural_call(
                    ctx,
                    func,
                    structural_args,
                    native_type_arg_count,
                    layout,
                    expr_ty(ctx, expr_id),
                    dest,
                );
                return true;
            }
        }
    }
    // The method's OWN generic count, read off the interface that DECLARES
    // it: the view may be a sub-interface whose `requires` ancestor declares
    // the method, so the closure is walked. A view that declares the method
    // nowhere is an internal inconsistency.
    let interface_ = interface_ref_of_type_name(ctx, iface_tn);
    if (interface_ == null) {
        throw internal_error(
            ctx,
            `virtual call through \`${iface_tn.name}\`, which names no interface`,
            expr_id,
        );
    }
    let shape: InterfaceMethodShape? = null;
    for (
        let declaring in root.hir_ty.interface_requires_closure(
            ctx.db,
            root.hir.DeclRefSource { value: interface_ },
        )
    ) {
        let declaring_loc = match (declaring) {
            let source: root.hir.DeclRefSource<int> => source.value,
            root.hir.DeclRefExternal<int> => {
                baml.sys.panic(
                    "emit_virtual_call_with_value_operands: a root served from its interface is not ported",
                )
            },
        };
        shape = interface_method_shape(ctx, declaring_loc, method);
        if (shape != null) {
            break;
        }
    }
    if (shape == null) {
        throw internal_error(
            ctx,
            `virtual call of \`${method}\` through \`${iface_tn.name}\`, whose declaration and \`requires\` closure declare no such method`,
            expr_id,
        );
    }
    let method_arg_count = shape.frame_len - shape.own_start;
    let type_arg_ops = lower_call_type_args(ctx, expr_id, true, null);
    let method_type_arg_ops: Operand[] = if (method_arg_count == 0) {
        []
    } else {
        let skip = type_arg_ops.length() - method_arg_count;
        type_arg_ops.slice(
            if (skip < 0) {
                0
            } else {
                skip
            },
            type_arg_ops.length(),
        )
    };
    let ntypeargs = method_type_arg_ops.length();
    let all_args = method_type_arg_ops.concat(value_ops);
    // A parameterized interface bakes its arguments into the template, which
    // reaches the VM through `LoadType` (substituting the caller's frame type
    // args), so an interface arg that is an enclosing generic lowers to its
    // `TypeArgRef` slot.
    let generic_params = enclosing_generic_params(ctx);
    let iface_template = tir2_interface_to_template(iface_tn, iface_type_args, iface_assoc, runtime(ctx), generic_params);
    let result_ty = expr_ty(ctx, expr_id);
    let argument_layout = call_argument_layout(ctx, expr_id, all_args.length() - ntypeargs);
    emit_virtual_call_with_operands(ctx, iface_template, method, all_args, ntypeargs, self_arg, argument_layout, result_ty, dest);
    true
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_call_with_operands @ d9be6853b
// Emit the `VirtualCall` terminator itself, given operands already lowered:
// `args` is `[method_type_args... ++ value_args...]` with exactly `ntypeargs`
// leading type args, and the dispatch argument is `args[ntypeargs +
// self_arg]` (the VM reads its runtime concrete type as `Self`). The call
// splits the block; a projection or capture destination is dispatched into a
// `result_ty` temp and assigned through in the resume block.
function emit_virtual_call_with_operands(
    ctx: LoweringContext,
    iface: root.types.TyTemplateInterfaceConstraint,
    method: string,
    args: Operand[],
    ntypeargs: int,
    self_arg: int,
    argument_layout: root.types.CallLayout?,
    result_ty: root.types.RuntimeTy,
    dest: Place,
) -> void throws never {
    let resume = ctx.builder.create_block();
    let projection_dest: Place? = null;
    let call_dest = dest;
    if (!(dest is PlaceLocal)) {
        let tmp = ctx.builder.declare_local(result_ty);
        call_dest = PlaceLocal { value: tmp };
        projection_dest = dest;
    }
    ctx.builder.virtual_call(iface, method, args, ntypeargs, self_arg, call_dest, resume);
    ctx.builder.set_call_layout(argument_layout);
    ctx.builder.set_current_block(resume);
    if (projection_dest != null) {
        ctx.builder.assign(projection_dest, RvalueUse { value: OperandCopy { value: call_dest } });
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_bound_method @ d9be6853b
// Emit an `RvalueMakeVirtualBoundMethod` binding `method` of the interface
// `view` on `recv_local`, the value analogue of `emit_virtual_call`: the VM
// resolves the receiver's impl at bind time. The method's own generics the
// reference infers append to that frame exactly as the written form does.
function emit_virtual_bound_method(
    ctx: LoweringContext,
    expr_id: int,
    recv_local: int,
    view: InterfaceTypeView,
    method: string,
    dest: Place,
) -> void throws MirInternalError {
    let (let decl_tn, let decl_args, let decl_assoc) = interface_view_declaring_method(ctx, view, method);
    // Through `tir2_to_template` like the call form: an interface arg that is
    // an enclosing generic lowers to its `TypeArgRef` frame slot.
    let generic_params = enclosing_generic_params(ctx);
    let iface_template = tir2_interface_to_template(decl_tn, decl_args, decl_assoc, runtime(ctx), generic_params);
    let bound = RvalueMakeVirtualBoundMethod {
        iface: iface_template,
        method: method,
        receiver: operand_copy_local(recv_local),
        // A written specialization reaches MIR as a generic-apply over the
        // produced value, and an inferred one is appended below, so the bind
        // itself carries none.
        type_args: [],
    };
    // The callable the reference names only sizes the own generics it
    // carries; the impl is resolved from the receiver at bind time.
    let resolution = tir_path_final_resolution(ctx, expr_id) ?? tir_resolution(ctx, expr_id);
    let callee = if (resolution != null) {
        root.hir_ty.member_resolution_callable<root.types.Ty>(resolution, ctx.db)
    } else {
        null
    };
    if (callee != null) {
        assign_specialized_bound_value(ctx, expr_id, dest, callee, bound);
        return;
    }
    if (tir_call_plan(ctx, expr_id) != null) {
        throw internal_error(ctx, "an inferred interface-method value names no callable", expr_id);
    }
    ctx.builder.assign(dest, bound);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_receiver_root @ d9be6853b
function path_receiver_root(
    ctx: LoweringContext,
    expr_id: int,
    name: string,
) -> Place? throws never {
    let place = place_for_path(ctx, expr_id, name);
    if (place != null) {
        return place;
    }
    let global = load_top_level_let_root(ctx, expr_id)
        ?? return null;
    PlaceLocal { value: global }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_path_receiver_to_local @ d9be6853b
// Lower a receiver path, excluding its method or field, to a local. Locals
// are reused; captures and field chains are materialized into temps.
function lower_path_receiver_to_local(
    ctx: LoweringContext,
    callee: int,
    receiver_segments: string[],
    recv_root: Place,
) -> int throws MirInternalError {
    let recv_ty_idx = receiver_segments.length() - 1;
    let recv_tir_ty = tir_path_segment_type(ctx, callee, recv_ty_idx);
    if (recv_tir_ty == null) {
        throw internal_error(ctx, "the checker recorded no type for a method receiver", callee);
    }
    let recv_ty = convert_tir_ty_for_runtime(ctx, recv_tir_ty);
    if (receiver_segments.length() == 1) {
        return operand_to_local(ctx, OperandCopy { value: recv_root }, recv_ty);
    }
    let local = ctx.builder.declare_local(recv_ty);
    lower_multi_segment_path_as_field_chain(ctx, callee, receiver_segments, PlaceLocal { value: local });
    local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_method_shape @ d9be6853b
// The frame shape of an interface's method: whether it takes a `self`
// receiver, and how its generic frame `[Self] ++ interface generics ++ own
// generics` divides (associated types are not slots). Null when the
// interface declares no such method. The source declaration only: no root
// is served from an interface here.
function interface_method_shape(
    ctx: LoweringContext,
    interface_: int,
    method: string,
) -> InterfaceMethodShape? throws never {
    let data = root.hir.interface_data(ctx.db, interface_);
    let fn_loc = data.methods.find((candidate) -> {
        root.hir.function_data(ctx.db, candidate).name == method
    })
        ?? return null;
    let signature = root.hir.function_signature(ctx.db, fn_loc);
    // Only the last group of the frame is the function's own declaration;
    // the rest is the interface's shape.
    let interface_generics = data.generic_params.length();
    let own_start = 1 + interface_generics;
    let frame_len = own_start + root.hir.function_data(ctx.db, fn_loc).generic_params.length();
    InterfaceMethodShape {
        takes_self: signature.params.at(0)?.name == "self",
        dispatch_param: match (root.hir_ty.callable_self_dispatch(ctx.db, fn_loc)) {
            let on_param: root.hir_ty.SelfDispatchOnParam => on_param.value,
            root.hir_ty.SelfDispatchNoSelfParam | root.hir_ty.SelfDispatchBreaks => null,
        },
        interface_generics: interface_generics,
        own_start: own_start,
        frame_len: frame_len,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_interface_field_access @ d9be6853b
// Read `field` through an interface view whose receiver's concrete type is
// not known statically, as an open-world `RvalueVirtualFieldAccess`. False
// only when no interface in the view's `requires` closure declares `field`.
// It never enumerates implementors: an interface's implementor set is open.
function try_lower_interface_field_access(
    ctx: LoweringContext,
    recv_local: int,
    iface_tn: root.types.DeclName,
    iface_type_args: root.types.Ty[],
    iface_assoc: (string, root.types.Ty)[],
    field: string,
    dest: Place,
) -> bool throws never {
    let view = (iface_tn, iface_type_args, iface_assoc);
    let (let iface, let field_index) = virtual_field_wire_target(ctx, view, field)
        ?? return false;
    emit_virtual_field_access(ctx, recv_local, iface, field_index, field, dest);
    true
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_field_wire_target @ d9be6853b
// What a virtual access to `field` through `view` puts on the wire: `view`
// narrowed to the interface that *declares* `field`, as the constraint
// template the instruction carries, with the field's index in that
// interface. Null when no interface in the closure declares `field`; the
// write path asks this before lowering any operand, so its fall-through
// stays side-effect-free.
function virtual_field_wire_target(
    ctx: LoweringContext,
    view: InterfaceTypeView,
    field: string,
) -> (root.types.TyTemplateInterfaceConstraint, int)? throws never {
    let declared = match (resolve_interface_member(ctx, view, field)) {
        let field_member: InterfaceMemberField => field_member,
        _ => {
            return null;
        },
    };
    let (let decl_tn, let decl_args, let decl_assoc) = declared.declaring;
    let generic_params = enclosing_generic_params(ctx);
    (
        tir2_interface_to_template(decl_tn, decl_args, decl_assoc, runtime(ctx), generic_params),
        declared.index,
    )
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_field_access @ d9be6853b
// Emit the open-world read of `field` off `recv_local` through `iface`.
function emit_virtual_field_access(
    ctx: LoweringContext,
    recv_local: int,
    iface: root.types.TyTemplateInterfaceConstraint,
    field_index: int,
    field: string,
    dest: Place,
) -> void throws never {
    ctx.builder.assign(
        dest,
        RvalueVirtualFieldAccess {
            iface: iface,
            receiver: operand_copy_local(recv_local),
            field_index: field_index,
            field: field,
        },
    );
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_field_assign_view @ d9be6853b
// The interface view an assignment *target* `recv.field` resolves through,
// when the field is served by an interface. TIR records a resolution for
// field reads only, so this falls back to deriving the view from the
// receiver's type. Null means the target is an ordinary place.
function virtual_field_assign_view(
    ctx: LoweringContext,
    target: int,
    base: int,
    field: string,
) -> InterfaceTypeView? throws never {
    let recorded = tir_virtual_field_view(ctx, target);
    if (recorded != null) {
        return recorded.0;
    }
    interface_receiver_for_field_access(ctx, base, field)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_field_assign_target @ d9be6853b
// The `VirtualFieldTarget` an assignment target denotes when it is an
// interface-field access, for either spelling: `a.b` reaches MIR as a
// multi-segment `Path` when its root is a local, and as a `MemberAccess`
// otherwise. Null for an ordinary place. Every fallible step runs before any
// operand is lowered, so a null leaves no emitted code behind (the caller
// re-lowers the target and value from the AST).
function virtual_field_assign_target(
    ctx: LoweringContext,
    target: int,
) -> VirtualFieldTarget? throws MirInternalError {
    match (ctx.body.exprs[target]) {
        let access: root.ast.ExprMemberAccess => {
            let base = access.base;
            let field = access.member;
            let view = virtual_field_assign_view(ctx, target, base, field)
                ?? return null;
            let (let iface, let field_index) = virtual_field_wire_target(ctx, view, field)
                ?? return null;
            let recv_op = lower_to_operand(ctx, base);
            let receiver = operand_to_local(ctx, recv_op, expr_ty(ctx, base));
            VirtualFieldTarget {
                receiver: receiver,
                field: field,
                iface: iface,
                field_index: field_index,
            }
        },
        let path: root.ast.ExprPath if path.value.segments.length() >= 2 => {
            let segments = path.value.segments;
            let field = segments[segments.length() - 1];
            let prefix_idx = segments.length() - 2;
            let view = interface_receiver_for_path_prefix(ctx, target, prefix_idx, field)
                ?? return null;
            let (let iface, let field_index) = virtual_field_wire_target(ctx, view, field)
                ?? return null;
            let recv_root = path_receiver_root(ctx, target, segments[0])
                ?? return null;
            let receiver = lower_path_receiver_to_local(ctx, target, segments.slice(0, segments.length() - 1), recv_root);
            VirtualFieldTarget {
                receiver: receiver,
                field: field,
                iface: iface,
                field_index: field_index,
            }
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_virtual_field_assign @ d9be6853b
// Lower `recv.field = value` where `recv.field` is an interface field, as a
// `StatementKindVirtualFieldStore`. False when the target is not a virtual
// interface-field access, leaving the ordinary `Place` path to it. The
// destination slot depends on the receiver's impl, so there is no `Place`.
function try_lower_virtual_field_assign(
    ctx: LoweringContext,
    target: int,
    value: int,
) -> bool throws MirInternalError {
    let field_target = virtual_field_assign_target(ctx, target)
        ?? return false;
    // The value as an operand rather than a temp: a single-use temp defined
    // here may be classified inlinable by the emitter while this statement
    // still loads it.
    let value_op = lower_to_operand(ctx, value);
    emit_interface_field_store(ctx, field_target, value_op);
    true
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_virtual_field_assign_op @ d9be6853b
// `recv.field op= value` on an interface field: read through the virtual
// access, apply the operator through the ordinary path (so operator drivers
// and overload dispatch behave as for a class field), then write back
// through the virtual store.
function try_lower_virtual_field_assign_op(
    ctx: LoweringContext,
    target: int,
    op: root.ast.AssignOp,
    value: int,
) -> bool throws MirInternalError {
    let field_target = virtual_field_assign_target(ctx, target)
        ?? return false;
    let current = ctx.builder.declare_local(expr_ty(ctx, target));
    emit_virtual_field_access(
        ctx,
        field_target.receiver,
        field_target.iface,
        field_target.field_index,
        field_target.field,
        PlaceLocal { value: current },
    );
    emit_assign_op(ctx, PlaceLocal { value: current }, target, op, value);
    emit_interface_field_store(ctx, field_target, operand_copy_local(current));
    true
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_interface_field_store @ d9be6853b
// Write `value` to `field` through an interface view, the store counterpart
// of `emit_virtual_field_access`. Infallible: the wire interface and field
// index were resolved before any operand was lowered.
function emit_interface_field_store(
    ctx: LoweringContext,
    target: VirtualFieldTarget,
    value: Operand,
) -> void throws never {
    ctx.builder.virtual_field_store(
        target.iface,
        operand_copy_local(target.receiver),
        target.field_index,
        target.field,
        value,
    );
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_ty_projections @ d9be6853b
// Reduce every determinable associated-type projection in `ty` to a
// fixpoint, via the canonical `normalize` (the checker's own reduction).
function resolve_ty_projections(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> root.types.Ty throws never {
    hir_facts(ctx).normalize(ty)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::hir_facts @ d9be6853b
// The `hir_ty` facts oracle over this context's carried bounds: the ONE
// alias, projection and subtype authority. The bounds are copied, as Rust
// clones them.
function hir_facts(ctx: LoweringContext) -> root.hir_ty.Facts throws never {
    root.hir_ty.Facts.with_bounds(
        ctx.db,
        root.hir_ty.interfaces.copy_bounds(ctx.generic_param_bounds),
    )
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_projection_bounds @ d9be6853b
// The declared bounds of an *unreduced* projection `(base as I).member`
// (interface `I`'s `type member extends J & K`, realized): a conjunction,
// empty for a non-projection or an unbounded associated type.
function resolve_projection_bounds(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> root.types.Ty[] throws never {
    match (ty) {
        let projection: root.types.TyAssociatedTypeProjection => {
            hir_facts(ctx).associated_type_bound(projection.interface_, projection.member).map((
                bound,
            ) -> {
                plain_interface_ty(bound)
            })
        },
        _ => [],
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_closure_type_name_views @ d9be6853b
// The view itself, verbatim, then every interface its `requires` closure
// reaches, realized on the view's subject with their projection pins
// reduced. Null when `iface_tn` names no interface.
function interface_closure_type_name_views(
    ctx: LoweringContext,
    iface_tn: root.types.DeclName,
    iface_type_args: root.types.Ty[],
    iface_assoc: (string, root.types.Ty)[],
) -> InterfaceTypeView[]? throws never {
    if (!is_interface_type_name(ctx, iface_tn)) {
        return null;
    }
    let root_constraint = root.types.InterfaceConstraint {
        name: iface_tn,
        generics: iface_type_args,
        associated_types: iface_assoc
            .map((binding) -> {
                root.types.AssociatedType { name: binding.0, ty: binding.1 }
            })
            .sort_by_key((binding) -> {
                binding.name
            }),
    };
    let subject = plain_interface_ty(root_constraint);
    let views: InterfaceTypeView[] = [(iface_tn, iface_type_args, iface_assoc)];
    let closure = root.hir_ty.direct_requires_closure_plain(
        ctx.db,
        root_constraint,
        subject,
        root.hir_ty.REQUIRES_CLOSURE_FUEL,
    );
    for (let reference in closure) {
        // A required interface's pins realize as PROJECTIONS on the subject;
        // the oracle reduces them here, as TIR's eager substitution did.
        views.push(
            (
                reference.name,
                reference.generics.map((ty) -> {
                    resolve_ty_projections(ctx, ty)
                }),
                reference.associated_types.map((binding) -> {
                    (binding.name, resolve_ty_projections(ctx, binding.ty))
                }),
            ),
        );
    }
    views
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_implements_target_view @ d9be6853b
// The interface view an `implements` block of `class_loc` targets: the
// written target resolved in the class's package, its arguments lowered in
// the class's frame, and its associated types bound by the block or else by
// the interface's defaults. `target` and the block's bindings index the
// block's own arena (`target_store`); the defaults index the interface's.
function resolve_implements_target_view(
    ctx: LoweringContext,
    target_store: root.hir.TypeRefStore,
    target: int,
    associated_type_bindings: root.hir.AssociatedTypeBindingData[],
    class_loc: int,
) -> InterfaceTypeView? throws never {
    let class_file = ctx.db.class_locs.get(class_loc).file;
    let class_pkg = root.hir.file_package(ctx.db, class_file);
    let class_pkg_items = root.hir.package_items(ctx.db, class_pkg.root_id);
    let target_loc = resolve_ref_to_interface_loc(ctx.db, target_store, target, class_pkg_items, class_pkg.namespace_path)
        ?? return null;
    let target_data = root.hir.interface_data(ctx.db, target_loc);
    let class_generic_params = root.hir_ty.class_generic_frame(ctx.db, class_loc);
    let target_generic_params = root.hir_ty.interface_declared_params(ctx.db, target_loc);
    let target_qtn = qualify_def(ctx.db, root.hir.DefinitionInterface { value: target_loc }, target_data.name);
    let target_args = lower_ref_interface_target_args(
        ctx.db,
        target_store,
        target,
        class_pkg_items,
        class_pkg.namespace_path,
        class_generic_params,
        root.hir_ty.class_generic_bounds(ctx.db, class_loc),
    );
    let target_iface_pkg = root.hir.file_package(ctx.db, ctx.db.interface_locs.get(target_loc).file);
    let bindings = root.types.bind_type_vars(target_generic_params, target_args);
    for (let param in class_generic_params) {
        if (!bindings.has(param)) {
            bindings[param] = root.types.TyTypeVar { param: param };
        }
    }
    let associated_bindings: (string, root.types.Ty)[] = [];
    for (let assoc in target_data.associated_types) {
        // Associated types are not frame params: a sibling reference in a
        // binding value or default is a `Self.X` projection, left symbolic
        // here and reduced through the impl's rule bindings at realization.
        let binding_ref = associated_type_bindings
            .find((binding) -> {
                binding.name == assoc.name
            })
            ?.type_ref;
        if (binding_ref != null) {
            let ty = lower_ref_with_bindings(
                ctx.db,
                target_store,
                binding_ref,
                class_pkg_items,
                class_pkg.namespace_path,
                bindings,
                root.hir_ty.class_generic_bounds(ctx.db, class_loc),
            );
            associated_bindings.push((assoc.name, ty));
            continue;
        }
        let default = assoc.default;
        if (default != null) {
            let ty = lower_ref_with_bindings(
                ctx.db,
                target_data.type_refs,
                default,
                class_pkg_items,
                target_iface_pkg.namespace_path,
                bindings,
                root.hir_ty.class_generic_bounds(ctx.db, class_loc),
            );
            associated_bindings.push((assoc.name, ty));
        }
    }
    (target_qtn, target_args, associated_bindings)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::implements_block_iface_target @ d9be6853b
// When the enclosing function is the override declared inside an
// `implements I { ... }` block, `I`'s target type expression. Null for free
// functions, top-level class methods, and interface default-method bodies.
function implements_block_iface_target(
    ctx: LoweringContext,
) -> root.hir.MethodInterfaceTarget? throws never {
    let func_loc = ctx.func_loc
        ?? return null;
    root.hir.method_interface_target(ctx.db, func_loc)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::implements_subject_tir_ty @ d9be6853b
// The enclosing implements-block's subject type: what `Self` denotes in this
// impl method's body (`root.hir_ty.impl_self_ty`). Null when the enclosing
// function is not an impl method.
function implements_subject_tir_ty(ctx: LoweringContext) -> root.types.Ty? throws never {
    let func_loc = ctx.func_loc
        ?? return null;
    match (root.hir.method_owner(ctx.db, func_loc)) {
        let impl_owner: root.hir.MethodOwnerImpl => {
            root.hir_ty.impl_self_ty(ctx.db, impl_owner.value)
        },
        // A class-owned method has no enclosing implements block, and an
        // interface default method has no implements-block target either.
        root.hir.MethodOwnerClass | root.hir.MethodOwnerInterface => null,
        null => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::body_self_tir_ty @ d9be6853b
// What a *body-position* `Self` denotes in the function being lowered: the
// rigid `Self` type variable for an interface-owned body (frame slot 0), or
// the enclosing implements-block's subject. Mirrors TIR's `body_self_ty`.
// Null for plain class methods and free functions.
function body_self_tir_ty(ctx: LoweringContext) -> root.types.Ty? throws never {
    let func_loc = ctx.func_loc
        ?? return null;
    match (root.hir.method_owner(ctx.db, func_loc)) {
        let interface_owner: root.hir.MethodOwnerInterface => {
            let self_param = root.hir_ty.interface_frame(ctx.db, interface_owner.value).at(0)
                ?? baml.sys.panic("interface frame starts with Self");
            root.types.TyTypeVar { param: self_param }
        },
        root.hir.MethodOwnerClass => null,
        root.hir.MethodOwnerImpl => implements_subject_tir_ty(ctx),
        null => null,
    }
}
