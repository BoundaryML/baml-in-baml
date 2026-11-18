// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// MIR unit 2, part 1: dispatch targets (lower.rs 3390-4448 in the fork's
// tree). Which interface view a receiver dispatches through, the
// interface-item call roads (`I.m(..)`, `C.m(..)`, `(C as I).m(..)`), and the
// interface member resolution every call and field road shares.
//
// Restructured (BAML forces it, or the lane does not exist here):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so every `*Ref` is its Source lane, an `int`, and the `DeclRef::External`
//   arms are dropped: `resolution_is_method_call` answers `true` for every
//   method, and `interface_type_name` qualifies the source interface. The
//   `hir_ty` layout queries that answer a `Source | External` union
//   (`interface_ref_of`, `interface_requires_closure`, `interface_member`)
//   are unwrapped to the Source `value`; their External arm panics.
// - One-line reads of the Source lane (as `root.hir_ty`'s callable.baml):
//   `callable_display_name` is `root.hir.function_data(db, f).name`.
// - Rust's `Option::or_else` / `and_then` chains over pure lookups are
//   sequential early returns, in Rust's order.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_dispatch_target_for_member @ d9be6853b
// The interface *view* a receiver of this static type dispatches through, for
// the `member` being accessed: its own for an existential, its bound's for a
// type variable, its resolved bound's for a projection. Null for concrete
// receivers: their providing interface is resolved by
// `dispatch_target_for_concrete`.
//
// `member` is not optional: a bound list is a conjunction, so under
// `T extends A & B` a member may be declared by either conjunct while the
// emitted `virtual_call` names just one interface.
function interface_dispatch_target_for_member(
    ctx: LoweringContext,
    ty: root.types.Ty,
    member: string,
) -> InterfaceTypeView? throws never {
    match (ty) {
        let alias: root.types.TyTypeAlias => {
            if (ctx.resolved_aliases.recursive.has(alias.name)) {
                return null;
            }
            let target = ctx.resolved_aliases.aliases.get(alias.name)
                ?? return null;
            interface_dispatch_target_for_member(ctx, target, member)
        },
        root.types.TyInterface | root.types.TyTypeVar | root.types.TyAssociatedTypeProjection => {
            canonical_dispatch_view(ctx, ty, member)
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::canonical_dispatch_view @ d9be6853b
function canonical_dispatch_view(
    ctx: LoweringContext,
    ty: root.types.Ty,
    member: string,
) -> InterfaceTypeView? throws never {
    let (let determination, _) = root.hir_ty.interfaces.determine_member_interface(
        ctx.db,
        root.hir.file_package(ctx.db, ctx.file).root_id,
        enclosing_generic_param_bounds(ctx),
        ty,
        null,
        member,
        root.hir_ty.interfaces.MemberNamespace.Value,
    );
    match (determination) {
        let determined: root.hir_ty.interfaces.DeterminationDetermined => {
            let view = determined.value;
            (
                view.name,
                view.generics,
                view.associated_types.map((binding) -> {
                    (binding.name, binding.ty)
                }),
            )
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_dispatch_target_for_expr_member @ d9be6853b
// The interface view an *expression* receiver dispatches through for
// `member`; see `interface_dispatch_target_for_member`.
function interface_dispatch_target_for_expr_member(
    ctx: LoweringContext,
    expr_id: int,
    member: string,
) -> InterfaceTypeView? throws never {
    let from_param = source_param_interface_view_for_expr(ctx, expr_id, member);
    if (from_param != null) {
        return from_param;
    }
    let expr_type = tir_expr_type(ctx, expr_id);
    if (expr_type != null) {
        let from_type = interface_dispatch_target_for_member(ctx, expr_type, member);
        if (from_type != null) {
            return from_type;
        }
    }
    let self_ty = self_typevar_for_expr(ctx, expr_id);
    if (self_ty != null) {
        let from_self = interface_dispatch_target_for_member(ctx, self_ty, member);
        if (from_self != null) {
            return from_self;
        }
    }
    written_qualifier_interface_view(ctx, expr_id, member)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::allows_interface_method_dispatch @ d9be6853b
// Member lookup has already chosen fields and inherent methods. Only
// interface methods (or accesses without a resolution record) may use the
// type-based interface dispatch fallback.
function allows_interface_method_dispatch(ctx: LoweringContext, access: int) -> bool throws never {
    match (tir_resolution(ctx, access)) {
        null => true,
        let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            match (method.callee) {
                root.hir_ty.MethodCalleeVirtual<root.types.Ty>
                    | root.hir_ty.MethodCalleeConcrete<root.types.Ty> =>
                {
                    true
                },
                root.hir_ty.MethodCalleeInherent => false,
            }
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::dispatch_target_for_member_access @ d9be6853b
// The interface view used to lower a member-access expression. Optional
// member access has already guarded the null branch before the member is
// evaluated, so dispatch must use the non-null receiver type.
function dispatch_target_for_member_access(
    ctx: LoweringContext,
    access: int,
    base: int,
    member: string,
) -> InterfaceTypeView? throws never {
    if (!allows_interface_method_dispatch(ctx, access)) {
        return null;
    }
    let resolution = tir_resolution(ctx, access);
    if (resolution != null) {
        let view = virtual_method_view_of(resolution);
        if (view != null) {
            return view;
        }
    }
    if (ctx.body.exprs[access] is root.ast.ExprOptionalMemberAccess) {
        let base_ty = tir_expr_type(ctx, base);
        if (base_ty != null) {
            let narrowed = root.types.strip_null(base_ty);
            let from_narrowed = interface_dispatch_target_for_member(ctx, narrowed, member)
                ?? dispatch_target_for_concrete(ctx, narrowed, member);
            if (from_narrowed != null) {
                return from_narrowed;
            }
        }
    }
    let from_expr = interface_dispatch_target_for_expr_member(ctx, base, member);
    if (from_expr != null) {
        return from_expr;
    }
    let base_ty = tir_expr_type(ctx, base)
        ?? return null;
    dispatch_target_for_concrete(ctx, base_ty, member)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::source_param_interface_view_for_expr @ d9be6853b
function source_param_interface_view_for_expr(
    ctx: LoweringContext,
    expr_id: int,
    member: string,
) -> InterfaceTypeView? throws never {
    let segments = match (ctx.body.exprs[expr_id]) {
        let path: root.ast.ExprPath => path.value.segments,
        _ => {
            return null;
        },
    };
    if (segments.length() != 1) {
        return null;
    }
    source_param_interface_view_for_name_at(ctx, expr_id, segments[0], member)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::source_param_interface_view_for_name_at @ d9be6853b
function source_param_interface_view_for_name_at(
    ctx: LoweringContext,
    expr_id: int,
    name: string,
    member: string,
) -> InterfaceTypeView? throws never {
    let binding_id = binding_id_for_path(ctx, expr_id, name)
        ?? return null;
    source_param_interface_view_for_binding(ctx, name, binding_id, member)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::source_param_interface_view_for_binding @ d9be6853b
function source_param_interface_view_for_binding(
    ctx: LoweringContext,
    name: string,
    binding_id: root.hir.BindingId,
    member: string,
) -> InterfaceTypeView? throws never {
    let ty = source_param_tir_ty_for_binding(ctx, name, binding_id)
        ?? return null;
    interface_dispatch_target_for_member(ctx, ty, member)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::source_param_tir_ty_for_binding @ d9be6853b
function source_param_tir_ty_for_binding(
    ctx: LoweringContext,
    name: string,
    binding_id: root.hir.BindingId,
) -> root.types.Ty? throws never {
    let func_loc = ctx.func_loc
        ?? return null;
    let param_scope = ctx.source_param_scope
        ?? return null;
    let sig = root.hir.function_signature(ctx.db, func_loc);
    let param_idx = sig.params
        .map((param) -> {
            param.name
        })
        .index_of(name)
        ?? return null;
    if (binding_id != root.hir.BindingId.parameter(param_scope, param_idx)) {
        return null;
    }

    let pkg_info = root.hir.file_package(ctx.db, ctx.file);
    let pkg_items = root.hir.package_items(ctx.db, pkg_info.root_id);
    let bindings: map<root.types.ParamTy, root.types.Ty> = {};
    for (let param in enclosing_generic_params(ctx)) {
        bindings[param] = root.types.TyTypeVar { param: param };
    }
    lower_ty_with_bindings(
        ctx.db,
        sig.params[param_idx].ty.value,
        pkg_items,
        pkg_info.namespace_path,
        bindings,
        enclosing_generic_param_bounds(ctx),
    )
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::self_typevar_for_expr @ d9be6853b
function self_typevar_for_expr(ctx: LoweringContext, expr_id: int) -> root.types.Ty? throws never {
    let segments = match (ctx.body.exprs[expr_id]) {
        let path: root.ast.ExprPath => path.value.segments,
        _ => {
            return null;
        },
    };
    if (segments.length() != 1 || segments[0] != "self") {
        return null;
    }
    let self_param = enclosing_generic_params(ctx).find((param) -> {
        param.name == "Self"
    })
        ?? return null;
    if (!ctx.generic_param_bounds.has(self_param)) {
        return null;
    }
    root.types.TyTypeVar { param: self_param }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_interface_item_call @ d9be6853b
// An interface-item call, keyed off the TIR record rather than the spelling:
// any callee that resolves UNBOUND to an interface slot (`(Base as I).m(..)`,
// `I.m(..)`, `C.m(..)`, a type-rooted member access such as `K.extends`) or
// to a statically matched impl's method through a type (`Widget.make(..)`),
// and so carries its receiver (if any) as the written first argument. A
// bound access carries its receiver in the base and is routed by the member
// roads; `default.m(..)` has its own discipline.
//
// Two dispatch forms, split by whether the method takes `self`:
// - WITH a `Self`-typed argument, `Self` is DERIVED from it: the same
//   open-world `VirtualCall` the member spelling emits, dispatching on that
//   argument (`self` at 0, or the one required bare-`Self` parameter).
// - WITHOUT one, `Self` is PASSED: the resolved `Self` type becomes the type
//   operand of a `RvalueMakeVirtualFunction`, and the call proceeds as an
//   ordinary indirect call of the resolved callable. A virtual slot's `Self`
//   is the recorded instantiation's slot 0; a matched impl's is its
//   for-target realized at the carried frame.
function try_lower_interface_item_call(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    args: int[],
    dest: Place,
) -> bool throws MirInternalError {
    let item = match (tir_resolution(ctx, callee)) {
        let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            if (method.receiver != root.hir_ty.Receiver.Unbound) {
                return false;
            }
            method.callee
        },
        _ => {
            return false;
        },
    };
    match (item) {
        // The checker resolved this call to a virtual slot, so it lowers
        // through the slot or not at all: the ordinary call road would name
        // the interface's own DECLARATION of the method. A frame the checker's
        // plan and the interface's shape disagree about is an internal
        // inconsistency.
        let virtual_: root.hir_ty.MethodCalleeVirtual<root.types.Ty> => {
            let method = virtual_.method;
            let shape = interface_method_shape(ctx, virtual_.interface_, method);
            if (shape == null) {
                throw internal_error(
                    ctx,
                    `a call resolved to the interface method \`${method}\`, which its interface does not declare`,
                    expr_id,
                );
            }
            let self_arg = shape.dispatch_param;
            if (self_arg != null) {
                // The dispatched road derives `Self` from the value of
                // argument `self_arg`, so it needs only the interface VIEW
                // (the static frame prefix); the method's own type args are
                // lowered by the virtual-call machinery itself.
                let plan = tir_call_plan(ctx, expr_id);
                if (plan == null) {
                    throw internal_error(
                        ctx,
                        `a call resolved to the interface method \`${method}\` has no call plan`,
                        expr_id,
                    );
                }
                if (plan.type_args.length() != shape.frame_len) {
                    throw internal_error(
                        ctx,
                        `the call plan of the interface method \`${method}\` instantiates ${plan.type_args.length()} frame slot(s), but its frame \`[Self] ++ interface generics ++ own generics\` has ${shape.frame_len}`,
                        expr_id,
                    );
                }
                let iface_args = plan.type_args.slice(1, shape.interface_generics + 1);
                let iface_tn = interface_type_name(ctx, virtual_.interface_);
                return emit_item_call_dispatched(ctx, expr_id, args, dest, iface_tn, iface_args, method, self_arg);
            }
            let rvalue = virtual_function_rvalue(ctx, expr_id, virtual_.interface_, method);
            if (rvalue == null) {
                throw internal_error(
                    ctx,
                    `a call resolved to the interface method \`${method}\` has no resolvable frame`,
                    expr_id,
                );
            }
            emit_item_call_type_keyed(ctx, expr_id, args, dest, rvalue);
            true
        },
        let concrete: root.hir_ty.MethodCalleeConcrete<root.types.Ty> => {
            let (let self_ty, let view) = concrete_item_target(ctx, concrete.impl_block, concrete.func, concrete.frame_type_args);
            let method = root.hir.function_data(ctx.db, concrete.func).name;
            if (root.hir_ty.callable_takes_self(ctx.db, concrete.func)) {
                // A `self`-taking method dispatches on its receiver, the
                // written first argument.
                return emit_item_call_dispatched(ctx, expr_id, args, dest, view.0, view.1, method, 0);
            }
            let rvalue = type_keyed_function_rvalue(ctx, expr_id, self_ty, view, method);
            emit_item_call_type_keyed(ctx, expr_id, args, dest, rvalue);
            true
        },
        root.hir_ty.MethodCalleeInherent => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::concrete_item_target @ d9be6853b
// The `(Self, declaring interface view)` a statically matched impl's method
// dispatches on: `hir_ty`'s realization of the carried frame, keyed on the
// interface that DECLARES the method (a `requires` ancestor's impl is where
// it may live). Associated types are outputs of the impl match, never
// dispatch keys, so the view carries none.
function concrete_item_target(
    ctx: LoweringContext,
    impl_block: int,
    func: int,
    frame_type_args: root.types.Ty[],
) -> (root.types.Ty, InterfaceTypeView) throws never {
    let (let self_ty, let interface_) = root.hir_ty.concrete_callee_target(ctx.db, impl_block, func, frame_type_args);
    let pool = ctx.db.ty_memo.pool;
    let plain = interface_.to_plain(pool);
    let view = interface_view_declaring_method(ctx, (plain.name, plain.generics, []), root.hir.function_data(ctx.db, func).name);
    (pool.to_plain_closed(self_ty.ty), view)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_item_call_dispatched @ d9be6853b
// The dispatched form of an interface-item call: the written argument at
// `self_arg` (the method's one required `Self`-typed parameter, `self` at 0
// when the method takes a receiver) is the value the VM derives `Self` from.
// The call plan covers every written argument in declared order, `self`
// included, so the list is lowered ONCE and passed whole.
function emit_item_call_dispatched(
    ctx: LoweringContext,
    expr_id: int,
    args: int[],
    dest: Place,
    iface_tn: root.types.DeclName,
    iface_args: root.types.Ty[],
    method: string,
    self_arg: int,
) -> bool throws MirInternalError {
    let arg_operands = lower_call_arg_operands(ctx, expr_id, args);
    if (self_arg >= arg_operands.length()) {
        // The arguments are already emitted into the block, so falling
        // through would re-lower them on the ordinary call road and evaluate
        // a side-effecting argument twice. The dispatch parameter is a
        // required one the call plan always binds: fail at the origin.
        throw internal_error(
            ctx,
            `interface item call dispatches on argument ${self_arg} but lowered only ${arg_operands.length()} argument(s)`,
            expr_id,
        );
    }
    emit_virtual_call_with_value_operands(ctx, self_arg, arg_operands, iface_tn, iface_args, [], method, expr_id, dest)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_item_call_type_keyed @ d9be6853b
// The type-keyed form of an interface-item call: the resolved callable (a
// `RvalueMakeVirtualFunction`) called indirectly.
function emit_item_call_type_keyed(
    ctx: LoweringContext,
    expr_id: int,
    args: int[],
    dest: Place,
    rvalue: Rvalue,
) -> void throws MirInternalError {
    let arg_operands = lower_call_arg_operands(ctx, expr_id, args);
    let generic: ConstantGenericFunction? = match (rvalue) {
        RvalueUse { value: OperandConstant { value: let constant } } => {
            match (constant) {
                let g: ConstantGenericFunction => g,
                _ => null,
            }
        },
        _ => null,
    };
    if (generic != null) {
        let operands: Operand[] = [];
        for (let ty in generic.type_args) {
            let local = ctx.builder.declare_local(root.types.TyType {});
            ctx.builder.assign(
                PlaceLocal { value: local },
                RvalueLoadType { value: root.types.widen_realized_ty_to_ty_template(ty) },
            );
            operands.push(OperandCopy { value: PlaceLocal { value: local } });
        }
        for (let operand in arg_operands) {
            operands.push(operand);
        }
        let layout = call_argument_layout(ctx, expr_id, operands.length() - generic.type_args.length());
        emit_direct_structural_call(
            ctx,
            generic.func,
            operands,
            generic.type_args.length(),
            layout,
            expr_ty(ctx, expr_id),
            place_clone(dest),
        );
        return;
    }
    let callable = ctx.builder.declare_local(root.types.TyUnknown {});
    ctx.builder.assign(PlaceLocal { value: callable }, rvalue);
    emit_resolved_indirect_call(ctx, OperandCopy { value: PlaceLocal { value: callable } }, arg_operands, expr_id, dest);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_type_keyed_item_reference @ d9be6853b
// Assign the type-keyed resolution of an UNBOUND interface-item reference (a
// virtual slot's, from its recorded frame; a matched impl method's, from its
// carried frame) to `dest`.
function lower_type_keyed_item_reference(
    ctx: LoweringContext,
    expr_id: int,
    callee: root.hir_ty.MethodCallee,
    dest: Place,
) -> void throws MirInternalError {
    let rvalue = match (callee) {
        let virtual_: root.hir_ty.MethodCalleeVirtual<root.types.Ty> => {
            virtual_function_rvalue(ctx, expr_id, virtual_.interface_, virtual_.method)
        },
        let concrete: root.hir_ty.MethodCalleeConcrete<root.types.Ty> => {
            let (let self_ty, let view) = concrete_item_target(ctx, concrete.impl_block, concrete.func, concrete.frame_type_args);
            let method = root.hir.function_data(ctx.db, concrete.func).name;
            type_keyed_function_rvalue(ctx, expr_id, self_ty, view, method)
        },
        root.hir_ty.MethodCalleeInherent => {
            baml.sys.panic("an inherent method is not an interface item")
        },
    };
    // TIR admitted it, so an unresolvable frame is an internal inconsistency,
    // never the generic null placeholder.
    if (rvalue == null) {
        throw internal_error(ctx, "interface method reference has no resolvable frame", expr_id);
    }
    ctx.builder.assign(dest, rvalue);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_keyed_function_rvalue @ d9be6853b
// The `RvalueMakeVirtualFunction` resolving `method` of `view` on `self_ty`:
// the type-keyed callable of a statically matched impl's method, the impl
// re-resolved by the VM from the same `(Self, interface)`. The method's own
// type arguments are the reference's written slots or its recorded plan's
// inferred suffix.
function type_keyed_function_rvalue(
    ctx: LoweringContext,
    expr_id: int,
    self_ty: root.types.Ty,
    view: InterfaceTypeView,
    method: string,
) -> Rvalue throws never {
    let structural = structural_function_rvalue(ctx, self_ty, view.0, method);
    if (structural != null) {
        return structural;
    }
    let generic_params = enclosing_generic_params(ctx);
    let iface = tir2_interface_to_template(view.0, view.1, view.2, runtime(ctx), generic_params);
    let type_args = lower_call_type_args(ctx, expr_id, true, null);
    RvalueMakeVirtualFunction {
        self_ty: ty_to_template(ctx, self_ty, generic_params),
        iface: iface,
        method: method,
        type_args: type_args,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_type_name @ d9be6853b
// The head an interface is (its Source lane: no root is served from an
// interface here).
function interface_type_name(
    ctx: LoweringContext,
    interface_: int,
) -> root.types.DeclName throws never {
    root.hir_ty.qualify_def(
        ctx.db,
        root.hir.DefinitionInterface { value: interface_ },
        root.hir.interface_data(ctx.db, interface_).name,
    )
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_ref_of_type_name @ d9be6853b
// The interface a head names; null when the head names no interface.
function interface_ref_of_type_name(
    ctx: LoweringContext,
    name: root.types.DeclName,
) -> int? throws never {
    match (root.hir_ty.interface_ref_of(ctx.db, name)) {
        let source: root.hir.DeclRefSource<int> => source.value,
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic(
                "interface_ref_of_type_name: a root served from its interface is not ported",
            )
        },
        null => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::callee_takes_self @ d9be6853b
// Whether a method callee takes a `self` receiver.
function callee_takes_self(
    ctx: LoweringContext,
    callee: root.hir_ty.MethodCallee,
) -> bool throws MirInternalError {
    match (callee) {
        let inherent: root.hir_ty.MethodCalleeInherent => {
            root.hir_ty.callable_takes_self(ctx.db, inherent.value)
        },
        let concrete: root.hir_ty.MethodCalleeConcrete<root.types.Ty> => {
            root.hir_ty.callable_takes_self(ctx.db, concrete.func)
        },
        let virtual_: root.hir_ty.MethodCalleeVirtual<root.types.Ty> => {
            let takes_self = virtual_slot_takes_self(ctx, virtual_.interface_, virtual_.method);
            if (takes_self == null) {
                throw internal_error_here(
                    ctx,
                    `a call resolved to the virtual slot \`${virtual_.method}\`, which its interface does not declare`,
                );
            }
            takes_self
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolution_is_method_call @ d9be6853b
// Whether a resolution names a METHOD for the call roads' receiver handling.
// A source method counts by its mode (a served package's callee, by whether
// its row takes `self`; no root is served here).
function resolution_is_method_call(
    ctx: LoweringContext,
    resolution: root.hir_ty.MemberResolution,
) -> bool throws never {
    match (resolution) {
        root.hir_ty.MemberResolutionMethod<root.types.Ty> => true,
        root.hir_ty.MemberResolutionFree
            | root.hir_ty.MemberResolutionField
            | root.hir_ty.MemberResolutionVariant
            | root.hir_ty.MemberResolutionInterfaceVirtualField<root.types.Ty> =>
        {
            false
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_slot_takes_self @ d9be6853b
// Whether the method a virtual slot names takes a `self` receiver. Null when
// the slot cannot be read at all.
function virtual_slot_takes_self(
    ctx: LoweringContext,
    interface_: int,
    method: string,
) -> bool? throws never {
    interface_method_shape(ctx, interface_, method)?.takes_self
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_item_slots @ d9be6853b
// The recorded instantiation frame of an interface-item reference, split per
// the interface's shape: the STATIC prefix `[Self] ++ interface generics`
// (associated types are not slots; turbofish binds the method's OWN generics
// only), and the method's own type arguments as OPERANDS (written static
// args and scoped runtime slots alike).
function interface_item_slots(
    ctx: LoweringContext,
    expr_id: int,
    shape: InterfaceMethodShape,
) -> (root.types.Ty[], Operand[])? throws never {
    let plan = tir_call_plan(ctx, expr_id)
        ?? return null;
    if (plan.type_args.length() != shape.frame_len) {
        return null;
    }
    let prefix = plan.type_args.slice(0, shape.own_start);
    // Written turbofish (static or runtime) lowers through the shared slot
    // road; an inferred suffix is static by construction and materializes as
    // `LoadType` temps.
    let own: Operand[] = if (plan.slots.length() == 0) {
        let generic_params = enclosing_generic_params(ctx);
        plan.type_args.slice(shape.own_start, plan.type_args.length()).map((ty) -> {
            let template = ty_to_template(ctx, ty, generic_params);
            let temp = ctx.builder.declare_local(root.types.TyType {});
            ctx.builder.assign(PlaceLocal { value: temp }, RvalueLoadType { value: template });
            operand_copy_local(temp)
        })
    } else {
        lower_call_type_args(ctx, expr_id, true, null)
    };
    (prefix, own)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_function_rvalue @ d9be6853b
// Build the `RvalueMakeVirtualFunction` for an interface-item reference from
// its recorded frame: the type-keyed resolution of the `(Self, interface,
// item)` triple as a first-class callable.
function virtual_function_rvalue(
    ctx: LoweringContext,
    expr_id: int,
    interface_: int,
    method: string,
) -> Rvalue? throws never {
    let shape = interface_method_shape(ctx, interface_, method)
        ?? return null;
    let iface_tn = interface_type_name(ctx, interface_);
    let (let prefix, let own_ops) = interface_item_slots(ctx, expr_id, shape)
        ?? return null;
    let structural = structural_function_rvalue(ctx, prefix[0], iface_tn, method);
    if (structural != null) {
        return structural;
    }
    let generic_params = enclosing_generic_params(ctx);
    let iface_template = root.types.TyTemplateInterfaceConstraint {
        name: iface_tn,
        generics: prefix.slice(1, shape.interface_generics + 1).map((ty) -> {
            ty_to_template(ctx, ty, generic_params)
        }),
        // Associated types are OUTPUTS of the impl match, never frame slots:
        // dispatch keys on head + args alone.
        associated_types: [],
    };
    RvalueMakeVirtualFunction {
        self_ty: ty_to_template(ctx, prefix[0], generic_params),
        iface: iface_template,
        method: method,
        type_args: own_ops,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::call_argument_layout @ d9be6853b
// The value slots a checked call pushes. The plan describes the written
// arguments; an unbound method call (`Class.method(obj, x)`) and a virtual
// call also pass the receiver as one leading value slot. Rust's
// `layout.0.insert(0, None)` on its clone is a fresh layout here.
function call_argument_layout(
    ctx: LoweringContext,
    expr_id: int,
    value_count: int,
) -> root.types.CallLayout? throws MirInternalError {
    let pushed = if (call_trace_arg(ctx, expr_id) != null) {
        value_count - 1
    } else {
        value_count
    };
    let plan = tir_call_plan(ctx, expr_id)
        ?? return null;
    let checked = plan.argument_layout.value;
    match (pushed - checked.length()) {
        0 => root.types.CallLayout { value: checked.concat([]) },
        1 => {
            let receiver_slot: (string | null)[] = [null];
            root.types.CallLayout { value: receiver_slot.concat(checked) }
        },
        // The layout has one slot per declared parameter while `pushed` is
        // what the call site pushes, so they can only disagree when the call
        // is arity-wrong, which a CHECKED program cannot contain.
        _ => {
            throw internal_error(
                ctx,
                `lowered a call whose ${pushed} operand(s) do not match its ${checked.length()} checked parameter slot(s)`,
                expr_id,
            )
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_resolved_indirect_call @ d9be6853b
// Emit an ordinary indirect call of an already-resolved callable value: no
// type args (the callable curries its complete frame). A projection
// destination calls into a temp and assigns through in the resume block.
function emit_resolved_indirect_call(
    ctx: LoweringContext,
    callee_op: Operand,
    arg_operands: Operand[],
    expr_id: int,
    dest: Place,
) -> void throws MirInternalError {
    let argument_layout = call_argument_layout(ctx, expr_id, arg_operands.length());
    let target = ctx.builder.create_block();
    match (dest) {
        PlaceLocal => {
            ctx.builder.call_with_type_args(callee_op, arg_operands, 0, place_clone(dest), target);
            ctx.builder.set_call_layout(argument_layout);
            ctx.builder.set_current_block(target);
        },
        _ => {
            let call_ty = expr_ty(ctx, expr_id);
            let tmp = ctx.builder.declare_local(call_ty);
            ctx.builder.call_with_type_args(
                callee_op,
                arg_operands,
                0,
                PlaceLocal { value: tmp },
                target,
            );
            ctx.builder.set_call_layout(argument_layout);
            ctx.builder.set_current_block(target);
            ctx.builder.assign(place_clone(dest), RvalueUse { value: operand_copy_local(tmp) });
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::written_qualifier_interface_view @ d9be6853b
// The interface view a WRITTEN qualifier names, for either spelling that
// carries one: `expr.as<I>` and `(Base as I).item`. Both pin which interface
// the member dispatches through.
function written_qualifier_interface_view(
    ctx: LoweringContext,
    expr_id: int,
    member: string,
) -> InterfaceTypeView? throws never {
    let target = match (ctx.body.exprs[expr_id]) {
        let upcast: root.ast.ExprUpcast => upcast.target,
        let qualified: root.ast.ExprQualifiedPath => qualified.interface_,
        _ => {
            return null;
        },
    };
    let pkg_info = root.hir.file_package(ctx.db, ctx.file);
    let pkg_items = root.hir.package_items(ctx.db, pkg_info.root_id);
    let target_ty = lower_expr_in_scope(
        ctx.db,
        target,
        pkg_items,
        pkg_info.namespace_path,
        enclosing_generic_params(ctx),
        enclosing_generic_param_bounds(ctx),
        null,
    );
    interface_dispatch_target_for_member(ctx, target_ty, member)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_dispatch_target_for_tir_ty @ d9be6853b
function class_dispatch_target_for_tir_ty(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> (root.types.DeclName, root.types.RuntimeTy[])? throws never {
    match (ty) {
        let class_: root.types.TyClass => {
            (
                class_.name,
                class_.args.map((arg) -> {
                    convert_tir_ty_for_runtime(ctx, arg)
                }),
            )
        },
        root.types.TyAssociatedTypeProjection => {
            let resolved = resolve_ty_projections(ctx, ty);
            if (resolved != ty) {
                return class_dispatch_target_for_tir_ty(ctx, resolved);
            }
            // An unreduced projection's bounds are interface constraints, and
            // an interface is never a class.
            null
        },
        // A type variable's bounds are interface constraints, and an
        // interface is never a class.
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::l1_impl_views_for_recv @ d9be6853b
// Every impl block applying to `recv` (a concrete-headed receiver, possibly
// carrying the enclosing function's rigid type variables), enumerated
// through the canonical L1 substrate, with each impl's generic bounds
// discharged against this scope's bounds. Structural roots are kept only
// when their `requires` closure reaches `target_tn`.
function l1_impl_views_for_recv(
    ctx: LoweringContext,
    recv: root.types.Ty,
    target_tn: root.types.DeclName,
) -> InterfaceTypeView[] throws never {
    // Dispatch is by BASE type: a literal-typed receiver probes as its base
    // primitive; realized view members reduce through the oracle before
    // becoming dispatch types.
    let widened = widen_literal_bases(recv);
    root.hir_ty
        .impl_views_for_type(
            ctx.db,
            root.hir.file_package(ctx.db, ctx.file).root_id,
            widened,
            // Structural roots are bare names; keep those whose closure reaches
            // the target.
            (name) -> {
                let views = interface_closure_type_name_views(ctx, name, [], []);
                views != null
                    && views.some((view) -> {
                        view.0 == target_tn
                    })
            },
        )
        .map((view) -> {
            (
                view.name,
                view.generics.map((ty) -> {
                    resolve_ty_projections(ctx, ty)
                }),
                view.associated_types.map((binding) -> {
                    (binding.name, resolve_ty_projections(ctx, binding.ty))
                }),
            )
        })
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::dispatch_target_for_concrete @ d9be6853b
// The interface a *concrete* receiver provides `method` through: the
// realized view of the impl whose interface (or its `requires` closure)
// declares it. Null for non-concrete receivers (interfaces and type vars
// take their view from the type itself) and for methods no impl provides.
function dispatch_target_for_concrete(
    ctx: LoweringContext,
    recv_ty: root.types.Ty,
    method: string,
) -> InterfaceTypeView? throws never {
    // A literal-typed receiver is concrete and dispatches as its base
    // primitive, hoisted so the kind test admits `(3.0).cmp(x)`.
    let widened = widen_literal_bases(recv_ty);
    if (widened is root.types.TyTuple) {
        let compare = baml_decl(ctx, "ops", "Compare");
        let interface_ = interface_ref_of_type_name(ctx, compare)
            ?? return null;
        if (interface_method_shape(ctx, interface_, method) == null) {
            return null;
        }
        return (compare, [], []);
    }
    // Only concrete receivers. Containers are concrete too (`implements<T> I
    // for T[]`), and so is a reflected type value (`reflect.Type`).
    let concrete = match (widened) {
        root.types.TyClass
            | root.types.TyEnum
            | root.types.TyEnumVariant
            | root.types.TyTypeAlias
            | root.types.TyUnknown
            | root.types.TyFunction
            | root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.TyType
            | root.types.TyList
            | root.types.TyMap
            | root.types.TyFuture
            | root.types.TyResource
            | root.types.TyPromptAst =>
        {
            true
        },
        _ => false,
    };
    if (!concrete) {
        return null;
    }
    // Fast pre-filter: a member name no in-scope interface declares can never
    // dispatch through an impl, so skip the per-call impl enumeration.
    if (!ctx.interface_method_names.has(method)) {
        return null;
    }
    canonical_dispatch_view(ctx, widened, method)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::mir_interface_declares_method @ d9be6853b
// Whether `iface_qtn` or any interface in its `requires` closure declares a
// method named `method`. Mirrors the TIR-side check.
function mir_interface_declares_method(
    ctx: LoweringContext,
    iface_qtn: root.types.DeclName,
    method: string,
) -> bool throws never {
    let interface_ = root.hir_ty.interface_ref_of(ctx.db, iface_qtn)
        ?? return false;
    root.hir_ty.interface_requires_closure(ctx.db, interface_).some((required) -> {
        root.hir_ty.interface_member(ctx.db, required, method) is root.hir_ty.DeclaredMemberMethod
    })
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_interface_type_name @ d9be6853b
// Whether `tn` names an interface declaration: a direct question about the
// name, not a lookup in a set of known implementors.
function is_interface_type_name(
    ctx: LoweringContext,
    tn: root.types.DeclName,
) -> bool throws never {
    interface_ref_of_type_name(ctx, tn) != null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_declares @ d9be6853b
// What the interface named by `iface_tn` says `member` is, DIRECTLY (in its
// own declaration, not via its `requires` closure). Null means the name is
// not an interface this compilation can read at all, which is not the same
// as "the member is absent" (`InterfaceMemberUndeclared`).
function interface_declares(
    ctx: LoweringContext,
    iface_tn: root.types.DeclName,
    member: string,
) -> root.hir_ty.DeclaredMember? throws never {
    decl_interface_declares(ctx, iface_tn, member)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::decl_interface_declares @ d9be6853b
// `interface_declares` keyed on a resolved declaration name.
function decl_interface_declares(
    ctx: LoweringContext,
    iface_decl: root.types.DeclName,
    member: string,
) -> root.hir_ty.DeclaredMember? throws never {
    let interface_ = root.hir_ty.interface_ref_of(ctx.db, iface_decl)
        ?? return null;
    root.hir_ty.interface_member(ctx.db, interface_, member)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_interface_member @ d9be6853b
// THE interface member resolution: what `member` means in `view`, and which
// interface of `view`'s `requires` closure says so. One walk answers every
// road's question, so the call roads, the field roads, and the bound-method
// road cannot disagree about what a name is.
//
// `view`'s own interface is consulted first, then the nearest required
// ancestor. `requires` is a bound, not inheritance, so an ancestor-declared
// member is served by the implementor's separate impl of that ancestor,
// which is why the answer carries the DECLARING view.
function resolve_interface_member(
    ctx: LoweringContext,
    view: InterfaceTypeView,
    member: string,
) -> InterfaceMember throws never {
    let found = (declaring: InterfaceTypeView, declared: root.hir_ty.DeclaredMember) -> InterfaceMember {
        match (declared) {
            root.hir_ty.DeclaredMemberMethod => InterfaceMemberMethod { declaring: declaring },
            let field: root.hir_ty.DeclaredMemberField => {
                InterfaceMemberField { declaring: declaring, index: field.index }
            },
        }
    };
    let own = interface_declares(ctx, view.0, member);
    if (own != null) {
        return found(view, own);
    }
    // The closure walk repeats the root view at index 0; it was just checked,
    // and re-checking it is harmless, so the walk is consumed whole.
    let views = interface_closure_type_name_views(ctx, view.0, view.1, view.2)
        ?? return InterfaceMemberUndeclared {};
    for (let candidate in views) {
        let declared = interface_declares(ctx, candidate.0, member);
        if (declared != null) {
            return found(candidate, declared);
        }
    }
    InterfaceMemberUndeclared {}
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::dispatch_view_for_call @ d9be6853b
// The interface view an interface-mediated CALL of `member` keys on, or null
// when the call must not dispatch at all: a METHOD dispatches on its
// declaring interface; a FIELD is not dispatchable (the caller falls through
// to the value road); an UNDECLARED name declines too.
function dispatch_view_for_call(
    ctx: LoweringContext,
    view: InterfaceTypeView,
    member: string,
) -> InterfaceTypeView? throws never {
    match (resolve_interface_member(ctx, view, member)) {
        let method: InterfaceMemberMethod => method.declaring,
        InterfaceMemberField | InterfaceMemberUndeclared => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_view_declaring_method @ d9be6853b
function interface_view_declaring_method(
    ctx: LoweringContext,
    view: InterfaceTypeView,
    method: string,
) -> InterfaceTypeView throws never {
    match (resolve_interface_member(ctx, view, method)) {
        let declared: InterfaceMemberMethod => declared.declaring,
        // A FIELD is not dispatchable and an UNDECLARED member has no
        // declaring interface; the call roads decline both before reaching
        // here. Neither names a better view than the one asked about.
        InterfaceMemberField | InterfaceMemberUndeclared => view,
    }
}
