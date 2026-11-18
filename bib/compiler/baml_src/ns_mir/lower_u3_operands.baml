// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// Lowering helpers (lower.rs "3.7: Helper methods", up to
// `operand_to_local`): operands, internal errors, conditions, `if` /
// `if let`, object literals, member access, and indexing.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - No one-line forwarders: Rust's `lower_member_access` is
//   `lower_member_access_with_base` with its `cached_base` defaulted to
//   `null`, and `interface_receiver_for_field_access` (a forward to
//   `interface_dispatch_target_for_expr_member`) is called as its target.
// - `lower_object`'s local enum `Entry` is the union
//   `ObjectEntrySpread | ObjectEntryNamed`, and its `slot_of` closure the
//   free function `object_field_slot`.
// - `RuntimeTy::strip_null` and the `Display` / `Debug` of `RuntimeTy` are
//   `root.types.runtime_ty_strip_null` / `runtime_ty_to_string` /
//   `runtime_ty_debug`; `layout::class_field_index` / `class_field_count`
//   are `root.hir_ty`'s (the per-unit stub files).

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_to_operand @ d9be6853b
function lower_to_operand(ctx: LoweringContext, expr_id: int) -> Operand throws MirInternalError {
    let ty = expr_ty(ctx, expr_id);
    let temp = ctx.builder.declare_local(ty);
    lower_expr(ctx, expr_id, PlaceLocal { value: temp });
    operand_copy_local(temp)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_throw_operand @ d9be6853b
// The operand a `throw` reads. A binding is read in place, a captured one
// through its cell, never through a temp: a thrown catch binding must still
// read the caught error's local, or it would not be a rethrow (see
// `caught_error_context`).
function lower_throw_operand(
    ctx: LoweringContext,
    expr_id: int,
) -> Operand throws MirInternalError {
    match (ctx.body.exprs[expr_id]) {
        let path: root.ast.ExprPath if path.value.segments.length() == 1 => {
            let local = local_for_path(ctx, expr_id, path.value.segments[0]);
            if (local != null) {
                return OperandCopy { value: value_place(ctx, local) };
            }
        },
        _ => {},
    }
    lower_to_operand(ctx, expr_id)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::internal_error @ d9be6853b
// An internal inconsistency: lowering cannot produce code here, for a
// program the checker accepted. The caller throws it, which abandons the
// unit: `lower_function` / `lower_let_body` answer with the error instead
// of MIR, and the compile fails.
function internal_error(
    ctx: LoweringContext,
    message: string,
    expr_id: int,
) -> MirInternalError throws never {
    MirInternalError {
        message: message,
        span: span_for_expr(ctx, expr_id) ?? ctx.builder.current_source_span,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::internal_error_here @ d9be6853b
// `internal_error` for a site with no expression of its own: located at
// whatever the builder is currently lowering.
function internal_error_here(
    ctx: LoweringContext,
    message: string,
) -> MirInternalError throws never {
    MirInternalError { message: message, span: ctx.builder.current_source_span }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_condition_operand @ d9be6853b
// Lowers a condition / logical-operand expression to an operand, applying
// the checker-recorded truthiness coercion (`Adjust::Truthy`). A
// `bool`-typed condition records nothing and lowers exactly as before; the
// branch terminators stay strict-bool.
function lower_condition_operand(
    ctx: LoweringContext,
    condition: int,
) -> Operand throws MirInternalError {
    let op = lower_to_operand(ctx, condition);
    // `!value` performs truthiness itself, so its operand need not have a TIR
    // adjustment. Predicate lowering can remove that Not; the branch must
    // still receive an exact bool, including on this path.
    let is_bool = match (expr_ty(ctx, condition)) {
        root.types.TyBool => true,
        let lit: root.types.TyLiteral => match (lit.value) {
            root.base.LiteralBool => true,
            _ => false,
        },
        _ => false,
    };
    if (is_bool && !tir_truthy_condition(ctx, condition)) {
        return op;
    }
    let coerced = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(
        PlaceLocal { value: coerced },
        RvalueUnaryOp { op: UnaryOp.Truthy, operand: op },
    );
    operand_copy_local(coerced)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_condition @ d9be6853b
// A predicate needs control flow, not a materialized logical value.
function lower_condition(
    ctx: LoweringContext,
    condition: int,
    on_true: int,
    on_false: int,
) -> void throws MirInternalError {
    match (ctx.body.exprs[condition]) {
        let binary: root.ast.ExprBinary if binary.op == root.ast.BinaryOp.And => {
            let next = ctx.builder.create_block();
            lower_condition(ctx, binary.lhs, next, on_false);
            ctx.builder.set_current_block(next);
            lower_condition(ctx, binary.rhs, on_true, on_false);
        },
        let binary: root.ast.ExprBinary if binary.op == root.ast.BinaryOp.Or => {
            let next = ctx.builder.create_block();
            lower_condition(ctx, binary.lhs, on_true, next);
            ctx.builder.set_current_block(next);
            lower_condition(ctx, binary.rhs, on_true, on_false);
        },
        let unary: root.ast.ExprUnary if unary.op == root.ast.UnaryOp.Not => {
            lower_condition(ctx, unary.expr, on_false, on_true);
        },
        _ => {
            let operand = lower_condition_operand(ctx, condition);
            ctx.builder.branch(operand, on_true, on_false);
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_if @ d9be6853b
function lower_if(
    ctx: LoweringContext,
    _expr_id: int,
    condition: int,
    then_branch: int,
    else_branch: int?,
    dest: Place,
) -> void throws MirInternalError {
    let bb_then = ctx.builder.create_block();
    let bb_else = ctx.builder.create_block();
    let bb_join = ctx.builder.create_block();

    lower_condition(ctx, condition, bb_then, bb_else);

    ctx.builder.set_current_block(bb_then);
    lower_expr(ctx, then_branch, place_clone(dest));
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }

    ctx.builder.set_current_block(bb_else);
    if (else_branch != null) {
        lower_expr(ctx, else_branch, dest);
    } else {
        ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
    }
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }

    ctx.builder.set_current_block(bb_join);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_if_let @ d9be6853b
// MIR lowering for `if let PATTERN = SCRUTINEE { THEN } else { ELSE }`: the
// shape of a two-arm match (`PATTERN => then, _ => else`), emitted inline.
// The pattern test jumps to the then-block on success (where the pattern's
// names are bound before lowering the body) and to the else-block on
// failure.
function lower_if_let(
    ctx: LoweringContext,
    _expr_id: int,
    pattern: int,
    scrutinee: int,
    then_branch: int,
    else_branch: int?,
    dest: Place,
) -> void throws MirInternalError {
    let scrutinee_local = try_resolve_to_local(ctx, scrutinee);
    if (scrutinee_local == null) {
        let op = lower_to_operand(ctx, scrutinee);
        let ty = expr_ty(ctx, scrutinee);
        scrutinee_local = operand_to_local(ctx, op, ty);
    }

    let bb_then = ctx.builder.create_block();
    let bb_else = ctx.builder.create_block();
    let bb_join = ctx.builder.create_block();

    lower_pattern_test(ctx, scrutinee_local, pattern, bb_then, bb_else);

    // Then-branch: bind the pattern's locals, lower the body.
    ctx.builder.set_current_block(bb_then);
    bind_pattern(ctx, scrutinee_local, pattern, root.hir.DefinitionSitePatternBinding { value: pattern });
    lower_expr(ctx, then_branch, place_clone(dest));
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }

    // Else-branch: no bindings from the pattern, just lower the else (or
    // write null if absent, as a plain `if` with no else).
    ctx.builder.set_current_block(bb_else);
    if (else_branch != null) {
        lower_expr(ctx, else_branch, dest);
    } else {
        ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
    }
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }

    ctx.builder.set_current_block(bb_join);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_object @ d9be6853b
// `lower_object`'s local `enum Entry`: a spread base or an explicit field,
// at a source position.
type ObjectEntry = ObjectEntrySpread | ObjectEntryNamed;

class ObjectEntrySpread {
    position: int,
    local: int,
}

class ObjectEntryNamed {
    position: int,
    name: string,
    operand: Operand,
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_object @ d9be6853b
function lower_object(
    ctx: LoweringContext,
    expr_id: int,
    fields: root.ast.ObjectExprField[],
    spreads: root.ast.SpreadField[],
    dest: Place,
) -> void throws MirInternalError {
    let type_arg_templates = object_class_type_arg_templates(ctx, expr_id);
    // The literal constructs the declaration TIR resolved its type to; the
    // class's LAYOUT (slot order, slot count) and its wire spelling both come
    // from that declaration. TIR types every object literal, so a literal
    // with no class behind its type is a compiler bug.
    let ty = expr_ty(ctx, expr_id);
    let head = match (ty) {
        let class_ty: root.types.RuntimeTyClass => class_ty.name,
        _ => {
            throw internal_error_here(
                ctx,
                `object literal typed \`${root.types.runtime_ty_to_string(spelled(ctx, ty))}\`, which is not a class`,
            );
        },
    };
    let class_ = class_ref_of(ctx, head);

    if (spreads.length() == 0) {
        // Lower fields in class-definition order, filling unspecified slots
        // with null: source order in the literal does not match definition
        // order.
        let field_operands: Operand[] = [];
        let slot = 0;
        while (slot < root.hir_ty.class_field_count(ctx.db, root.hir.DeclRefSource<int> { value: class_ })) {
            field_operands.push(OperandConstant { value: ConstantNull {} });
            slot += 1;
        }
        for (let field in fields) {
            let idx = object_field_slot(ctx, class_, field.name);
            field_operands[idx] = lower_to_operand(ctx, field.value);
        }
        ctx.builder.assign(
            dest,
            RvalueAggregate {
                kind: AggregateKindClass { class_: class_, type_arg_templates: type_arg_templates },
                fields: field_operands,
            },
        );
        return;
    }

    // Lower spread base(s) and explicit fields eagerly (in source order),
    // then assemble the aggregate respecting override semantics: later
    // source entries override earlier ones for the same class field.
    let field_count = root.hir_ty.class_field_count(ctx.db, root.hir.DeclRefSource<int> { value: class_ });

    // Lower all spread expressions into locals.
    let spread_locals: (int, int)[] = [];
    for (let s in spreads) {
        let op = lower_to_operand(ctx, s.expr);
        let spread_ty = expr_ty(ctx, s.expr);
        spread_locals.push((s.position, operand_to_local(ctx, op, spread_ty)));
    }

    // Lower all explicit field expressions into operands. Named fields
    // occupy source positions 0.. excluding spread positions.
    let spread_positions: map<int, bool> = {};
    for (let s in spreads) {
        spread_positions[s.position] = true;
    }
    let explicit_with_pos: (int, string, Operand)[] = [];
    let pos = 0;
    for (let field in fields) {
        while (spread_positions.has(pos)) {
            pos += 1;
        }
        let cur = pos;
        pos += 1;
        explicit_with_pos.push((cur, field.name, lower_to_operand(ctx, field.value)));
    }

    // Merge all entries into one list sorted by source position.
    let entries: ObjectEntry[] = [];
    for (let spread in spread_locals) {
        entries.push(ObjectEntrySpread { position: spread.0, local: spread.1 });
    }
    for (let explicit in explicit_with_pos) {
        entries.push(
            ObjectEntryNamed { position: explicit.0, name: explicit.1, operand: explicit.2 },
        );
    }
    let sorted = entries.sort_by_key((entry) -> int {
        match (entry) {
            let e: ObjectEntrySpread => e.position,
            let e: ObjectEntryNamed => e.position,
        }
    });

    // Initialize all fields to null, then apply entries in order.
    let result: Operand[] = [];
    let slot = 0;
    while (slot < field_count) {
        result.push(OperandConstant { value: ConstantNull {} });
        slot += 1;
    }

    for (let entry in sorted) {
        match (entry) {
            let spread: ObjectEntrySpread => {
                // A spread fills every field from the base object.
                let idx = 0;
                while (idx < field_count) {
                    result[idx]
                        = OperandCopy {
                            value: PlaceField { base: PlaceLocal { value: spread.local }, field: idx },
                        };
                    idx += 1;
                }
            },
            let named: ObjectEntryNamed => {
                let idx = object_field_slot(ctx, class_, named.name);
                result[idx] = operand_clone(named.operand);
            },
        }
    }

    ctx.builder.assign(
        dest,
        RvalueAggregate {
            kind: AggregateKindClass { class_: class_, type_arg_templates: type_arg_templates },
            fields: result,
        },
    );
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_object @ d9be6853b
// `lower_object`'s `slot_of` closure. TIR admitted every written field
// against this declaration, so a field the layout does not know is a
// compiler bug, never a value silently dropped.
function object_field_slot(
    ctx: LoweringContext,
    class_: int,
    field: string,
) -> int throws MirInternalError {
    let index = root.hir_ty.class_field_index(ctx.db, root.hir.DeclRefSource<int> { value: class_ }, field);
    if (index == null) {
        throw internal_error_here(
            ctx,
            `object literal names field \`${field}\`, which \`${class_display_name(ctx.db, class_)}\` does not declare`,
        );
    }
    index
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_member_access_with_base @ d9be6853b
// Also Rust's `lower_member_access`, which is this with no `cached_base`.
function lower_member_access_with_base(
    ctx: LoweringContext,
    expr_id: int,
    base: int,
    field: string,
    dest: Place,
    cached_base: Operand? = null,
) -> void throws MirInternalError {
    let slot = tuple_slot(field);
    if (slot != null) {
        let base_ty = expr_ty(ctx, base);
        let base_op = if (cached_base != null) {
            operand_clone(cached_base)
        } else {
            lower_to_operand(ctx, base)
        };
        let base_local = ctx.builder.declare_local(base_ty);
        ctx.builder.assign(PlaceLocal { value: base_local }, RvalueUse { value: base_op });
        let index = ctx.builder.declare_local(root.types.TyInt {});
        ctx.builder.assign(
            PlaceLocal { value: index },
            RvalueUse { value: OperandConstant { value: ConstantInt { value: slot } } },
        );
        ctx.builder.assign(
            dest,
            RvalueUse {
                value: OperandCopy {
                    value: PlaceIndex {
                        base: PlaceLocal { value: base_local },
                        index: index,
                        kind: IndexKind.Tuple,
                    },
                },
            },
        );
        return;
    }
    // TIR may have resolved this to a method or free function: emit a
    // function constant (unbound) or MakeBoundMethod (bound). Field and
    // variant resolutions fall through to the lowering below.
    if (lower_member_access_resolution(ctx, expr_id, base, dest, cached_base)) {
        return;
    }

    // An interface method referenced as a VALUE on a generic- or
    // interface-typed receiver (`let f = x.eq`): bind the receiver's impl
    // method by its runtime type at bind time. The declaring interface is
    // resolved BEFORE lowering the receiver so a field access falls through
    // without evaluating the receiver twice.
    let view = dispatch_target_for_member_access(ctx, expr_id, base, field);
    if (view != null && mir_interface_declares_method(ctx, view.0, field)) {
        let recv_op = if (cached_base != null) {
            operand_clone(cached_base)
        } else {
            lower_to_operand(ctx, base)
        };
        let recv_local = ctx.builder.declare_local(expr_ty(ctx, base));
        ctx.builder.assign(PlaceLocal { value: recv_local }, RvalueUse { value: recv_op });
        emit_virtual_bound_method(ctx, expr_id, recv_local, view, field, dest);
        return;
    }

    // An enum variant (`baml.HttpMethod.Get` via a package path).
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

    lower_member_access_field(ctx, expr_id, base, field, dest, cached_base);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_member_access_with_base @ d9be6853b
// Rust's `field.parse::<usize>()`: the tuple slot a numeric member names
// (`t.0`). Rust's `usize` parse admits only ASCII digits (and a leading
// `+`, which a member name never has).
function tuple_slot(field: string) -> int? throws never {
    if (field.length() == 0 || !field.is_ascii_numeric()) {
        return null;
    }
    int.parse(field) catch (_) {
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_member_access_with_base @ d9be6853b
// The resolution block of `lower_member_access_with_base`: a method or free
// function TIR resolved the access to. Returns whether it lowered the
// access.
function lower_member_access_resolution(
    ctx: LoweringContext,
    expr_id: int,
    base: int,
    dest: Place,
    cached_base: Operand?,
) -> bool throws MirInternalError {
    let resolution = tir_resolution(ctx, expr_id);
    match (resolution) {
        let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            match (method.callee) {
                root.hir_ty.MethodCalleeInherent => {
                    if (method.receiver == root.hir_ty.Receiver.Bound) {
                        // A `self`-less method has no receiver to bind; TIR
                        // rejects one reached through a value.
                        if (!callee_takes_self(ctx, method.callee)) {
                            throw internal_error(ctx, "static method reached through a value receiver", expr_id);
                        }
                        // Bound method reference: lower the receiver and
                        // emit MakeBoundMethod.
                        let item = root.hir_ty.member_resolution_callable(method, ctx.db);
                        if (item != null) {
                            let receiver_op = if (cached_base != null) {
                                operand_clone(cached_base)
                            } else {
                                lower_to_operand(ctx, base)
                            };
                            assign_bound_method_value(ctx, expr_id, dest, item, receiver_op);
                            return true;
                        }
                    } else {
                        // Unbound method reference: the function value,
                        // carrying the instantiation the reference infers.
                        let item = root.hir_ty.member_resolution_callable(method, ctx.db);
                        if (item != null) {
                            let value = function_item_value(ctx, expr_id, item);
                            ctx.builder.assign(dest, value);
                            return true;
                        }
                    }
                },
                _ => {
                    // A member-access base is a VALUE: a `self`-taking method
                    // captures the receiver and binds its impl at runtime
                    // (the virtual-bound road); a `self`-LESS one is rejected
                    // by TIR.
                    if (!callee_takes_self(ctx, method.callee)) {
                        throw internal_error(ctx, "static method reached through a value receiver", expr_id);
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
        // Fall through: handled by the field / enum-variant / interface
        // virtual-field lowering (a virtual field read on an existential).
        _ => {},
    }
    false
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_member_access_with_base @ d9be6853b
// The regular field access at the end of `lower_member_access_with_base`.
function lower_member_access_field(
    ctx: LoweringContext,
    expr_id: int,
    base: int,
    field: string,
    dest: Place,
    cached_base: Operand?,
) -> void throws MirInternalError {
    let base_ty = expr_ty(ctx, base);
    let base_op = if (cached_base != null) {
        operand_clone(cached_base)
    } else {
        lower_to_operand(ctx, base)
    };

    // Unwrap an optional: called from `lower_optional_member_access`, the
    // base type is `T?` but already null-checked, so use the inner type.
    let unwrapped_ty = root.types.runtime_ty_strip_null(base_ty);

    // The field's slot in the receiver class's layout, if the receiver is a
    // class that declares it (an interface-typed receiver takes the virtual
    // road below).
    let field_idx: int? = match (unwrapped_ty) {
        let class_ty: root.types.RuntimeTyClass => {
            root.hir_ty.class_field_index(ctx.db, root.hir.DeclRefSource<int> { value: class_ref_of(ctx, class_ty.name) }, field)
        },
        _ => null,
    };

    let base_local = operand_to_local(ctx, base_op, base_ty);

    if (field_idx != null) {
        ctx.builder.assign(
            dest,
            RvalueUse {
                value: OperandCopy {
                    value: PlaceField { base: PlaceLocal { value: base_local }, field: field_idx },
                },
            },
        );
        return;
    }
    // TIR's own resolution first: it names the interface the access was
    // CHECKED through, including the shared interface of a union receiver,
    // which no inspection of the receiver's type can recover.
    let recorded = tir_virtual_field_view(ctx, expr_id);
    let handled_interface_field = if (recorded != null) {
        let view = recorded.0;
        try_lower_interface_field_access(ctx, base_local, view.0, view.1, view.2, field, dest)
    } else {
        // Fallback for receivers TIR recorded no virtual-field resolution
        // for: `field` selects among a bounded type variable's bound
        // conjunction, where the field may come from any conjunct.
        let derived = interface_dispatch_target_for_expr_member(ctx, base, field);
        derived != null
            && try_lower_interface_field_access(ctx, base_local, derived.0, derived.1, derived.2, field, dest)
    };
    if (handled_interface_field) {
        return;
    }
    match (unwrapped_ty) {
        let class_ty: root.types.RuntimeTyClass => {
            throw internal_error(
                ctx,
                `MIR failed to resolve field access .${field} against class definition '${class_ty.name.name}': the class declares no such field`,
                expr_id,
            );
        },
        let iface: root.types.RuntimeTyInterface => {
            // TIR resolves every accepted interface field access and records
            // the view; reaching here means the access was rejected
            // upstream.
            throw internal_error(
                ctx,
                `MIR failed to resolve field access .${field} against interface '${iface.name.name}': TIR recorded no virtual-field view for it`,
                expr_id,
            );
        },
        _ => {},
    }
    // TIR rejects `.member` on every other base (maps and `unknown`
    // included: those index with `[...]`), so reaching here means TIR left
    // the access unresolved without a diagnostic. A dynamic map read on
    // such a base would compile and misbehave.
    throw internal_error(
        ctx,
        `MIR failed to resolve member access .${field} on \`${root.types.runtime_ty_debug(unwrapped_ty)}\`: TIR recorded no resolution for it`,
        expr_id,
    );
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_receiver_for_path_prefix @ d9be6853b
// The interface view the ladder segment after `prefix_idx` reads `member`
// through. TIR's RECORDED resolution for that segment comes first (it names
// the interface the access was checked against, including a union prefix's
// shared interface), then the receiver-typed derivation off the prefix
// segment's (or root's) type. No erased-`RuntimeTy` guess.
function interface_receiver_for_path_prefix(
    ctx: LoweringContext,
    expr_id: int,
    prefix_idx: int,
    member: string,
) -> InterfaceTypeView? throws never {
    let recorded = tir_path_segment_virtual_field_view(ctx, expr_id, prefix_idx + 1);
    if (recorded != null) {
        return recorded.0;
    }
    let segment_ty = tir_path_segment_type(ctx, expr_id, prefix_idx);
    if (segment_ty != null) {
        let target = interface_dispatch_target_for_member(ctx, segment_ty, member);
        if (target != null) {
            return target;
        }
    }
    if (prefix_idx == 0) {
        let root_ty = tir_path_root_type(ctx, expr_id);
        if (root_ty != null) {
            return interface_dispatch_target_for_member(ctx, root_ty, member);
        }
    }
    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_receiver_for_path_prefix @ d9be6853b
function class_receiver_for_path_prefix(
    ctx: LoweringContext,
    expr_id: int,
    prefix_idx: int,
    current_ty: root.types.RuntimeTy,
) -> (root.types.DeclName, root.types.RuntimeTy[])? throws never {
    let tir_prefix_ty = if (prefix_idx == 0) {
        tir_path_root_type(ctx, expr_id)
    } else {
        tir_path_segment_type(ctx, expr_id, prefix_idx)
    };
    if (tir_prefix_ty != null) {
        let target = class_dispatch_target_for_tir_ty(ctx, tir_prefix_ty);
        if (target != null) {
            return target;
        }
    }
    match (current_ty) {
        let class_ty: root.types.RuntimeTyClass => (class_ty.name, class_ty.args.concat([])),
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_index @ d9be6853b
function lower_index(
    ctx: LoweringContext,
    base: int,
    index: int,
    dest: Place,
) -> void throws MirInternalError {
    let base_ty = expr_ty(ctx, base);
    let base_op = lower_to_operand(ctx, base);
    let index_ty = expr_ty(ctx, index);
    let index_op = lower_to_operand(ctx, index);
    emit_index_access(ctx, base_op, base_ty, index_op, index_ty, dest);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_index_access @ d9be6853b
// Emit the element read for `base[index]` from already-lowered operands.
// Shared by `lower_index` and `lower_optional_index_access` so a
// side-effectful index expression is evaluated exactly once.
function emit_index_access(
    ctx: LoweringContext,
    base_op: Operand,
    base_ty: root.types.RuntimeTy,
    index_op: Operand,
    index_ty: root.types.RuntimeTy,
    dest: Place,
) -> void throws never {
    let base_local = operand_to_local(ctx, base_op, base_ty);
    let index_local = operand_to_local(ctx, index_op, index_ty);

    let kind = index_kind_of(ctx, base_ty);
    if (kind == IndexKind.Map) {
        emit_map_call(ctx, "index", [operand_copy_local(base_local), operand_copy_local(index_local)], dest);
        return;
    }

    ctx.builder.assign(
        dest,
        RvalueUse {
            value: OperandCopy {
                value: PlaceIndex {
                    base: PlaceLocal { value: base_local },
                    index: index_local,
                    kind: kind,
                },
            },
        },
    );
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::index_kind_of @ d9be6853b
function index_kind_of(
    ctx: LoweringContext,
    base_ty: root.types.RuntimeTy,
) -> IndexKind throws never {
    index_kind_for(root.types.runtime_ty_strip_null(unfold_index_receiver(ctx, base_ty, [])))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::unfold_index_receiver @ d9be6853b
// `seen` is the alias stack, pushed and popped in place as in Rust.
function unfold_index_receiver(
    ctx: LoweringContext,
    ty: root.types.RuntimeTy,
    seen: root.types.DeclName[],
) -> root.types.RuntimeTy throws never {
    match (ty) {
        let alias: root.types.TyTypeAlias if !seen.includes(alias.name) => {
            let target = ctx.resolved_aliases.aliases.get(alias.name)
                ?? return ty;
            seen.push(alias.name);
            let unfolded = unfold_index_receiver(ctx, runtime(ctx).convert(target), seen);
            seen.pop();
            unfolded
        },
        let union_: root.types.RuntimeTyUnion => {
            let flat: root.types.RuntimeTy[] = [];
            for (let member in union_.members) {
                match (unfold_index_receiver(ctx, member, seen)) {
                    let inner: root.types.RuntimeTyUnion => root.base.extend(flat, inner.members),
                    let other => flat.push(other),
                }
            }
            root.types.RuntimeTyUnion { members: flat }
        },
        _ => ty,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_map_call @ d9be6853b
function emit_map_call(
    ctx: LoweringContext,
    method: string,
    args: Operand[],
    dest: Place,
) -> void throws never {
    let callee = OperandConstant {
        value: ConstantFunction {
            value: lang_class_method(ctx, root.base.LangPackage.Baml, "Map", method),
        },
    };
    let call_dest: Place = match (dest) {
        PlaceLocal => place_clone(dest),
        _ => PlaceLocal { value: ctx.builder.declare_local(root.types.TyUnknown {}) },
    };
    let resume = ctx.builder.create_block();
    // Native map operations read K/V from the typed receiver, not call type
    // arguments.
    ctx.builder.call_with_type_args(callee, args, 0, place_clone(call_dest), resume);
    ctx.builder.set_current_block(resume);
    if (call_dest != dest) {
        ctx.builder.assign(dest, RvalueUse { value: OperandCopy { value: call_dest } });
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_resolve_to_local @ d9be6853b
// If the expression is a simple local variable reference (a single-segment
// path resolving to a known local), return its local directly without
// allocating a temp or emitting a copy.
function try_resolve_to_local(ctx: LoweringContext, expr_id: int) -> int? throws never {
    match (ctx.body.exprs[expr_id]) {
        let path: root.ast.ExprPath if path.value.segments.length() == 1 => {
            let local = local_for_path(ctx, expr_id, path.value.segments[0]);
            // A captured local holds a cell pointer, not the value; the
            // caller copies the value through the cell instead.
            if (local != null && !ctx.builder.local_decl(local).is_captured) {
                return local;
            }
        },
        _ => {},
    }
    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::operand_to_local @ d9be6853b
// Convert an operand to a local, materializing a temp if necessary.
function operand_to_local(
    ctx: LoweringContext,
    op: Operand,
    ty: root.types.RuntimeTy,
) -> int throws never {
    let direct: int? = match (op) {
        let copy: OperandCopy => match (copy.value) {
            let l: PlaceLocal => l.value,
            _ => null,
        },
        let move: OperandMove => match (move.value) {
            let l: PlaceLocal => l.value,
            _ => null,
        },
        OperandConstant => null,
    };
    if (direct != null) {
        return direct;
    }
    let temp = ctx.builder.declare_local(ty);
    ctx.builder.assign(PlaceLocal { value: temp }, RvalueUse { value: op });
    temp
}

// port: baml_compiler2_mir/src/ir.rs::impl Clone for Place @ d9be6853b
// Rust's derived `Clone`: a fresh, deep copy. A `Place` the lowering puts
// in two MIR positions (where Rust clones it) must be two objects: the
// optimizer rewrites places in place (`remap_place`, `apply_subst_*`), and a
// shared object would be rewritten once per position.
function place_clone(place: Place) -> Place throws never {
    match (place) {
        let p: PlaceLocal => PlaceLocal { value: p.value },
        let p: PlaceField => PlaceField { base: place_clone(p.base), field: p.field },
        let p: PlaceIndex => PlaceIndex { base: place_clone(p.base), index: p.index, kind: p.kind },
        let p: PlaceCapture => PlaceCapture { value: p.value },
        let p: PlaceDeref => match (p.value) {
            let cell: PlaceLocal => PlaceDeref { value: PlaceLocal { value: cell.value } },
            let cell: PlaceCapture => PlaceDeref { value: PlaceCapture { value: cell.value } },
        },
    }
}

// port: baml_compiler2_mir/src/ir.rs::impl Clone for Operand @ d9be6853b
// Rust's derived `Clone`, as `place_clone`. A constant is never rewritten in
// place, so the copy shares it.
function operand_clone(operand: Operand) -> Operand throws never {
    match (operand) {
        let o: OperandCopy => OperandCopy { value: place_clone(o.value) },
        let o: OperandMove => OperandMove { value: place_clone(o.value) },
        let o: OperandConstant => OperandConstant { value: o.value },
    }
}
