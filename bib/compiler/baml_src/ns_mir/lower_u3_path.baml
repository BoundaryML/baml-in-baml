// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// Path expressions (lower.rs "3.3: Path expression lowering"):
// `lower_path_expr`, `lower_multi_segment_path_as_field_chain`, and
// `lower_item_ref`.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - `lower_path_expr` (385 lines) is split along its own blocks, called in
//   order: `lower_path_expr_ladder` (the value-rooted ladder match),
//   `lower_path_expr_flat` (the flat resolution match), and
//   `lower_path_expr_member` (virtual-bound method values, `default.<m>`,
//   field chains, enum variants). The first two return whether they lowered
//   the path; Rust returns from inside the match. The bound-receiver operand
//   both matches build word for word is `lower_path_expr_receiver`.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_path_expr @ d9be6853b
function lower_path_expr(
    ctx: LoweringContext,
    expr_id: int,
    segments: string[],
    dest: Place,
) -> void throws MirInternalError {
    // Multi-segment paths (baml.http.fetch, self.field, obj.method): check
    // TIR resolution first.
    if (segments.length() > 1) {
        // A value-rooted ladder takes priority over the flat resolution map:
        // the checker records a local-rooted path's members in the ladder
        // and only package-rooted paths in the flat map.
        if (lower_path_expr_ladder(ctx, expr_id, segments, dest)) {
            return;
        }
        // Flat resolutions (set by `infer_multi_segment_path` for
        // package-rooted paths like baml.fs.open, baml.env.get).
        if (lower_path_expr_flat(ctx, expr_id, segments, dest)) {
            return;
        }
        lower_path_expr_member(ctx, expr_id, segments, dest);
        return;
    }

    let name = segments[0];

    let place = place_for_path(ctx, expr_id, name);
    if (place != null) {
        ctx.builder.assign(dest, RvalueUse { value: OperandCopy { value: place } });
        return;
    }
    if (binding_id_for_path(ctx, expr_id, name) != null) {
        throw internal_error(ctx, `unresolved local: ${name}`, expr_id);
    }
    // A global the checker resolved (bare, or qualified and rewritten to its
    // bare name, in this package or a served one) reads its slot.
    let global_root = tir_global_root(ctx, expr_id);
    if (global_root != null) {
        ctx.builder.assign(
            dest,
            RvalueUse {
                value: OperandConstant { value: ConstantGlobalItem { value: global_root.binding } },
            },
        );
        return;
    }

    let sm = ctx.source_map;
    let span_start = if (sm != null) {
        sm.expr_span(expr_id).start
    } else {
        0
    };

    let resolved = root.hir.resolve_name_at(ctx.db, ctx.file, span_start, name, scope_name = ctx.scope_func_name);
    match (resolved) {
        let item: root.hir.ResolvedNameItem => lower_item_ref(ctx, expr_id, item.value, dest),
        let builtin: root.hir.ResolvedNameBuiltin => {
            lower_item_ref(ctx, expr_id, builtin.value, dest)
        },
        root.hir.ResolvedNameLocal | root.hir.ResolvedNameUnknown => {
            if (tir_expr_type(ctx, expr_id) != null) {
                // TIR recorded a type for this expr, so it was handled as a
                // package path intermediate (`baml` in
                // `baml.HttpMethod.Get`). Emit a null placeholder: the outer
                // field access produces the real value.
                ctx.builder.assign(
                    dest,
                    RvalueUse { value: OperandConstant { value: ConstantNull {} } },
                );
            } else {
                throw internal_error(ctx, `unresolved name: ${name}`, expr_id);
            }
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_path_expr @ d9be6853b
// The ladder block of `lower_path_expr`. The final member's resolution
// decides the shape: a method or free item makes the path a callee
// reference (a function constant; `lower_call` prepends the receiver), a
// field a pure field chain. For `user.profile.items.slice` the ladder is
// [Field{profile}, Field{items}, Method{slice}]. Returns whether it lowered
// the path.
function lower_path_expr_ladder(
    ctx: LoweringContext,
    expr_id: int,
    segments: string[],
    dest: Place,
) -> bool throws MirInternalError {
    let resolution = tir_path_final_resolution(ctx, expr_id);
    match (resolution) {
        let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            match (method.callee) {
                let inherent: root.hir_ty.MethodCalleeInherent => {
                    if (method.receiver == root.hir_ty.Receiver.Bound) {
                        // A `self`-less method referenced through a receiver
                        // (`let m = f.make`): nothing to bind. TIR rejects
                        // that, so it is unreachable in a compiling program.
                        let takes_self = root.hir_ty.callable_takes_self(ctx.db, inherent.value);
                        // Bound method reference: lower the receiver and
                        // emit MakeBoundMethod.
                        let item = root.hir_ty.member_resolution_callable(method, ctx.db);
                        if (item != null) {
                            if (!takes_self) {
                                throw internal_error(ctx, "static method reached through a value receiver", expr_id);
                            }
                            let receiver_op = lower_path_expr_receiver(ctx, expr_id, segments);
                            assign_bound_method_value(ctx, expr_id, dest, item, receiver_op);
                            return true;
                        }
                    } else {
                        // Unbound inherent method reference: the function
                        // value, carrying the instantiation the reference
                        // infers.
                        let item = root.hir_ty.member_resolution_callable(method, ctx.db);
                        if (item != null) {
                            let value = function_item_value(ctx, expr_id, item);
                            ctx.builder.assign(dest, value);
                            return true;
                        }
                    }
                },
                _ => {
                    if (method.receiver == root.hir_ty.Receiver.Bound) {
                        // A VALUE-rooted interface-method reference
                        // (`let f = x.eq`) captures the receiver and binds
                        // its impl at runtime: the virtual-bound road in
                        // `lower_path_expr_member`. A `self`-LESS member has
                        // no receiver to bind; TIR rejects it.
                        if (!callee_takes_self(ctx, method.callee)) {
                            throw internal_error(ctx, "static method reached through a value receiver", expr_id);
                        }
                    } else {
                        // A TYPE-rooted interface-item reference
                        // (`let f = Widget.make`, `sort_by(Comparable.compare)`):
                        // the type-keyed resolution of the
                        // `(Self, interface, item)` triple as a value. An
                        // interface item has no global function symbol.
                        lower_type_keyed_item_reference(ctx, expr_id, method.callee, dest);
                        return true;
                    }
                },
            }
        },
        let free: root.hir_ty.MemberResolutionFree => {
            // Free function reference: the function value, carrying the
            // instantiation the reference infers.
            let item = root.hir_ty.member_resolution_callable<root.types.Ty>(free, ctx.db);
            if (item != null) {
                let value = function_item_value(ctx, expr_id, item);
                ctx.builder.assign(dest, value);
                return true;
            }
        },
        root.hir_ty.MemberResolutionField => {
            // Local-rooted field access: chain field projections.
            lower_multi_segment_path_as_field_chain(ctx, expr_id, segments, dest);
            return true;
        },
        // A variant, or a virtual field read on an existential: handled by
        // the expression-type check in `lower_path_expr_member`.
        root.hir_ty.MemberResolutionVariant
            | root.hir_ty.MemberResolutionInterfaceVirtualField<root.types.Ty> =>
        {},
        null => {},
    }
    false
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_path_expr @ d9be6853b
// The flat-resolution block of `lower_path_expr` (the `resolutions` map,
// set by `infer_multi_segment_path` for package-rooted paths). Returns
// whether it lowered the path.
function lower_path_expr_flat(
    ctx: LoweringContext,
    expr_id: int,
    segments: string[],
    dest: Place,
) -> bool throws MirInternalError {
    let resolution = tir_resolution(ctx, expr_id);
    match (resolution) {
        let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            match (method.callee) {
                root.hir_ty.MethodCalleeInherent => {
                    let item = root.hir_ty.member_resolution_callable(method, ctx.db);
                    if (method.receiver == root.hir_ty.Receiver.Bound) {
                        // Bound method reference via flat resolutions: emit
                        // MakeBoundMethod.
                        if (item != null) {
                            let receiver_op = lower_path_expr_receiver(ctx, expr_id, segments);
                            assign_bound_method_value(ctx, expr_id, dest, item, receiver_op);
                            return true;
                        }
                    } else {
                        // Unbound inherent method reference: the function
                        // value, carrying the instantiation the reference
                        // infers.
                        if (item != null) {
                            let value = function_item_value(ctx, expr_id, item);
                            ctx.builder.assign(dest, value);
                            return true;
                        }
                    }
                },
                _ => {
                    // Bound: a value-rooted interface-method reference, the
                    // virtual-bound road in `lower_path_expr_member`.
                    // Unbound: a TYPE-rooted interface-item VALUE reference,
                    // as in the ladder.
                    if (method.receiver == root.hir_ty.Receiver.Unbound) {
                        lower_type_keyed_item_reference(ctx, expr_id, method.callee, dest);
                        return true;
                    }
                },
            }
        },
        let free: root.hir_ty.MemberResolutionFree => {
            let item = root.hir_ty.member_resolution_callable<root.types.Ty>(free, ctx.db);
            if (item != null) {
                let value = function_item_value(ctx, expr_id, item);
                ctx.builder.assign(dest, value);
                return true;
            }
        },
        // Handled by the expression-type check in `lower_path_expr_member`
        // (a virtual field read on an existential falls through to the
        // general lowering).
        root.hir_ty.MemberResolutionVariant
            | root.hir_ty.MemberResolutionInterfaceVirtualField<root.types.Ty> =>
        {},
        root.hir_ty.MemberResolutionField => {
            // Local-rooted field access: the root segment is a local; chain
            // through class fields.
            lower_multi_segment_path_as_field_chain(ctx, expr_id, segments, dest);
            return true;
        },
        null => {},
    }
    false
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_path_expr @ d9be6853b
// The receiver operand of a bound method reference `a.m` / `a.b.m`: the
// root's place for a one-segment receiver (null when it has none), else the
// receiver lowered as a field chain into a temp typed as the whole path.
function lower_path_expr_receiver(
    ctx: LoweringContext,
    expr_id: int,
    segments: string[],
) -> Operand throws MirInternalError {
    let receiver_segments = segments.slice(0, segments.length() - 1);
    if (receiver_segments.length() == 1) {
        let receiver_root = path_receiver_root(ctx, expr_id, segments[0]);
        if (receiver_root != null) {
            OperandCopy { value: receiver_root }
        } else {
            OperandConstant { value: ConstantNull {} }
        }
    } else {
        // Multi-segment receiver (`cfg.encoder`): lower as a field chain.
        let recv_ty = expr_ty(ctx, expr_id);
        let recv_local = ctx.builder.declare_local(recv_ty);
        lower_multi_segment_path_as_field_chain(ctx, expr_id, receiver_segments, PlaceLocal { value: recv_local });
        operand_copy_local(recv_local)
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_path_expr @ d9be6853b
// The tail of `lower_path_expr`'s multi-segment case, after the ladder and
// flat matches fell through.
function lower_path_expr_member(
    ctx: LoweringContext,
    expr_id: int,
    segments: string[],
    dest: Place,
) -> void throws MirInternalError {
    // An interface method referenced as a VALUE on a generic- or
    // interface-typed receiver (`let f = x.eq`): bind the receiver's impl
    // method by its runtime type at bind time. The declaring interface is
    // resolved BEFORE lowering the receiver so a field access (no such
    // method) falls through without lowering the prefix twice. A qualified
    // method reference resolved above, so the receiver is always
    // `segments[..len-1]`.
    if (segments.length() >= 2 && allows_interface_method_dispatch(ctx, expr_id)) {
        let recv_root = path_receiver_root(ctx, expr_id, segments[0]);
        if (recv_root != null) {
            let method_name = segments[segments.length() - 1];
            let recv_seg_idx = if (segments.length() == 2) {
                0
            } else {
                segments.length() - 2
            };
            let recv_tir_ty = tir_path_segment_type(ctx, expr_id, recv_seg_idx);
            let final_resolution = tir_path_final_resolution(ctx, expr_id);
            let view: InterfaceTypeView? = if (final_resolution != null) {
                virtual_method_view_of(final_resolution)
            } else {
                null
            };
            if (view == null && recv_tir_ty != null) {
                view = interface_dispatch_target_for_member(ctx, recv_tir_ty, method_name);
            }
            if (view == null && recv_tir_ty != null) {
                view = dispatch_target_for_concrete(ctx, recv_tir_ty, method_name);
            }
            if (view != null && mir_interface_declares_method(ctx, view.0, method_name)) {
                let receiver_segments = segments.slice(0, segments.length() - 1);
                let recv_local = lower_path_receiver_to_local(ctx, expr_id, receiver_segments, recv_root);
                emit_virtual_bound_method(ctx, expr_id, recv_local, view, method_name, dest);
                return;
            }
        }
    }
    // `default.<method>` as a value: the interface's default body bound to
    // `self`, over the frame an adopted default runs in (what
    // `default.<method>(..)` calls with), never the override.
    if (segments.length() == 2 && is_default_receiver_root(ctx, expr_id, segments)) {
        let delegation = default_delegation(ctx, expr_id, segments[1]);
        if (delegation != null) {
            let default_loc = delegation.0;
            let frame_tys = delegation.1;
            let self_local_ = self_local(ctx);
            if (self_local_ == null) {
                throw internal_error(ctx, "`default.<method>` as a value outside a method with `self`", expr_id);
            }
            let generic_params = enclosing_generic_params(ctx);
            let type_arg_templates = frame_tys.map((ty) -> root.types.TyTemplate {
                ty_to_template(ctx, ty, generic_params)
            });
            // A generic default method's own arguments follow the frame, as
            // a bound inherent method's follow the receiver's.
            let inferred = inferred_value_type_arg_templates(ctx, expr_id, default_loc);
            if (inferred != null) {
                root.base.extend(type_arg_templates, inferred);
            }
            ctx.builder.assign(
                dest,
                RvalueMakeBoundMethod {
                    func: default_loc,
                    receiver: OperandCopy { value: value_place(ctx, self_local_) },
                    frame: BoundFrameExplicit { value: type_arg_templates },
                },
            );
            return;
        }
    }
    // `default.<field>` as a value: the field-chain lowerer maps the
    // `default` root to `self` viewed as the interface. (The call form is
    // intercepted earlier in `lower_call`, and the method VALUE form just
    // above, so this only catches the field form.)
    if (
        binding_id_for_path(ctx, expr_id, segments[0]) != null
            || is_default_receiver_root(ctx, expr_id, segments)
    ) {
        lower_multi_segment_path_as_field_chain(ctx, expr_id, segments, dest);
        return;
    }
    // An enum variant (`Status.Active` lowered to Path(["Status","Active"])).
    match (tir_expr_type(ctx, expr_id)) {
        let variant: root.types.TyEnumVariant => {
            let enum_ref = enum_ref_of(ctx, variant.name);
            let index = enum_variant_index(ctx, enum_ref, variant.variant);
            ctx.builder.assign(
                dest,
                RvalueUse {
                    value: OperandConstant {
                        value: ConstantEnumVariant { enum_ref: enum_ref, index: index },
                    },
                },
            );
            return;
        },
        _ => {},
    }
    // Namespace intermediate or unresolved: emit a null placeholder.
    ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_multi_segment_path_as_field_chain @ d9be6853b
// Lower a multi-segment `Path` expression (`a.b.c`) as chained field
// projections. The first segment is resolved as a local variable;
// subsequent segments are projected as class slots (the declaration's
// layout, by identity) or map keys (fallback).
function lower_multi_segment_path_as_field_chain(
    ctx: LoweringContext,
    expr_id: int,
    segments: string[],
    dest: Place,
) -> void throws MirInternalError {
    let root_place = place_for_path(ctx, expr_id, segments[0]);
    let current_place: Place = PlaceLocal { value: 0 };
    let current_ty: root.types.RuntimeTy = root.types.TyUnknown {};
    if (root_place != null) {
        // The local itself, or the value in its cell: either way the root's
        // type is the local's, refined by TIR.
        current_ty
            = match (root_place) {
                let p: PlaceLocal => refined_root_local_ty(ctx, expr_id, p.value),
                let p: PlaceDeref => match (p.value) {
                    let cell: PlaceLocal => refined_root_local_ty(ctx, expr_id, cell.value),
                    PlaceCapture => {
                        let ty = path_root_ty(ctx, expr_id);
                        if (ty == null) {
                            throw internal_error(ctx, "the checker recorded no type for a captured path root", expr_id);
                        }
                        ty
                    },
                },
                PlaceCapture | PlaceField | PlaceIndex => {
                    baml.sys.panic("path roots are locals or the values in cells")
                },
            };
        current_place = root_place;
    } else {
        let root_local = load_top_level_let_root(ctx, expr_id);
        if (root_local != null) {
            current_ty = ctx.builder.local_ty(root_local);
            current_place = PlaceLocal { value: root_local };
        } else {
            let self_local_ = if (is_default_receiver_root(ctx, expr_id, segments)) {
                self_local(ctx)
            } else {
                null
            };
            if (self_local_ == null) {
                // Root not found as a local or capture; emit null.
                ctx.builder.assign(
                    dest,
                    RvalueUse { value: OperandConstant { value: ConstantNull {} } },
                );
                return;
            }
            // `default.<field>` denotes the enclosing `self` viewed at the
            // declaring interface. TIR typed the root as an interface, so
            // reuse that and let the interface-prefix routing below resolve
            // the field view (the same path as `self.as<I>.field`).
            current_place = value_place(ctx, self_local_);
            current_ty = path_root_ty(ctx, expr_id) ?? ctx.builder.local_ty(self_local_);
        }
    }

    let skip_next_segment = false;
    let seg_idx = 1;
    while (seg_idx < segments.length()) {
        let seg = segments[seg_idx];
        if (skip_next_segment) {
            skip_next_segment = false;
            seg_idx += 1;
            continue;
        }
        let is_last = seg_idx + 1 == segments.length();
        let interface_prefix = interface_receiver_for_path_prefix(ctx, expr_id, seg_idx - 1, seg);
        let class_receiver = class_receiver_for_path_prefix(ctx, expr_id, seg_idx - 1, current_ty);
        if (class_receiver != null) {
            let class_ = class_ref_of(ctx, class_receiver.0);
            let class_type_args = class_receiver.1;
            // The slot carries the receiver's class type-args substituted
            // into the declared field type, so chained access through
            // generic positions (`b.value.name` where `b: Box<User>`) keeps
            // the class type rather than the erased runtime metadata.
            let slot = class_field_slot(ctx, class_, seg, class_type_args);
            if (slot != null) {
                current_place = PlaceField { base: current_place, field: slot.0 };
                current_ty = slot.1;
                seg_idx += 1;
                continue;
            }
            if (!is_last) {
                let qualified = `${seg}.${segments[seg_idx + 1]}`;
                let qualified_slot = class_field_slot(ctx, class_, qualified, class_type_args);
                if (qualified_slot != null) {
                    current_place = PlaceField { base: current_place, field: qualified_slot.0 };
                    current_ty = qualified_slot.1;
                    skip_next_segment = true;
                    seg_idx += 1;
                    continue;
                }
            }
        }

        let target_ty = path_segment_ty(ctx, expr_id, seg_idx);
        if (target_ty == null) {
            throw internal_error(ctx, "the checker recorded no type for a path segment", expr_id);
        }
        let target_place: Place = if (is_last) {
            dest
        } else {
            PlaceLocal { value: ctx.builder.declare_local(target_ty) }
        };
        let base_local: int = match (current_place) {
            let p: PlaceLocal => p.value,
            _ => {
                let local = ctx.builder.declare_local(current_ty);
                ctx.builder.assign(
                    PlaceLocal { value: local },
                    RvalueUse { value: OperandCopy { value: current_place } },
                );
                local
            },
        };
        if (
            interface_prefix != null
                && try_lower_interface_field_access(
                    ctx,
                    base_local,
                    interface_prefix.0,
                    interface_prefix.1,
                    interface_prefix.2,
                    seg,
                    target_place,
                )
        ) {
            if (is_last) {
                return;
            }
            current_place = target_place;
            current_ty = target_ty;
            seg_idx += 1;
            continue;
        }
        match (current_ty) {
            let iface: root.types.RuntimeTyInterface => {
                // An interface-typed prefix with no recorded or derived
                // view: an access TIR rejected. Loud, like the expression
                // road.
                throw internal_error(
                    ctx,
                    `MIR failed to resolve field access .${seg} against interface '${iface.name.name}': TIR recorded no virtual-field view for it`,
                    expr_id,
                );
            },
            _ => {},
        }
        // Dynamic map key fallback
        let key_local = ctx.builder.declare_local(root.types.TyString {});
        ctx.builder.assign(
            PlaceLocal { value: key_local },
            RvalueUse { value: OperandConstant { value: ConstantString { value: seg } } },
        );
        emit_map_call(
            ctx,
            "index",
            [OperandCopy { value: current_place }, operand_copy_local(key_local)],
            target_place,
        );
        if (is_last) {
            return;
        }
        current_place = target_place;
        current_ty = target_ty;
        seg_idx += 1;
    }

    ctx.builder.assign(dest, RvalueUse { value: OperandCopy { value: current_place } });
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_item_ref @ d9be6853b
function lower_item_ref(
    ctx: LoweringContext,
    expr_id: int,
    def: root.hir.Definition,
    dest: Place,
) -> void throws MirInternalError {
    // An item TIR typed as an enum variant is that variant's value.
    match (tir_expr_type(ctx, expr_id)) {
        let variant: root.types.TyEnumVariant => {
            let enum_ref = enum_ref_of(ctx, variant.name);
            let index = enum_variant_index(ctx, enum_ref, variant.variant);
            ctx.builder.assign(
                dest,
                RvalueUse {
                    value: OperandConstant {
                        value: ConstantEnumVariant { enum_ref: enum_ref, index: index },
                    },
                },
            );
            return;
        },
        _ => {},
    }
    // A function reference becomes a pooled function-value wrapper at emit;
    // a top-level `let` (a client, ...) is a plain read of the global slot
    // `$init` filled.
    let constant: Constant = match (def) {
        let f: root.hir.DefinitionFunction => {
            let value = function_item_value(ctx, expr_id, f.value);
            ctx.builder.assign(dest, value);
            return;
        },
        let binding: root.hir.DefinitionLet => ConstantGlobalItem { value: binding.value },
        root.hir.DefinitionClass
            | root.hir.DefinitionEnum
            | root.hir.DefinitionInterface
            | root.hir.DefinitionTypeAlias =>
        {
            // A type declaration is not a value; the checker rejects the
            // reference, so a compiling program never reaches here.
            throw internal_error(ctx, "a type declaration referenced as a value", expr_id);
        },
    };
    ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: constant } });
}
