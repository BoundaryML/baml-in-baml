// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// The expression dispatcher (lower.rs "3.2: Core lower_expr dispatch" and
// "Literal helper"): `lower_scoped_block`, `lower_expr`, `emit_throw`,
// `caught_error_context`, `lower_await`, `default_delegation`,
// `is_default_receiver_root`, and `lower_literal`.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - `lower_expr` stays the dispatcher, with Rust's span save first and
//   restore last; its larger arms are `lower_expr_<variant>` helpers,
//   called at the arm's position with the same side effects in order.
// - `Vec::truncate` is `root.syntax.truncate` (in place, as in Rust).

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_scoped_block @ d9be6853b
function lower_scoped_block(
    ctx: LoweringContext,
    stmts: int[],
    tail_expr: int?,
    dest: Place,
) -> void throws MirInternalError {
    let type_binding_scope_start = ctx.scoped_type_binding_params.length();
    let defer_depth = ctx.defer_stack.length();
    let incoming_unwind = ctx.builder.current_unwind;

    // A defer must also run when an exception propagates out of a CALL
    // inside the block. Each defer makes the rest of the block unwind to a
    // landing pad that replays that defer, then cascades to the next-outer
    // pad / enclosing handler; a throw thus runs exactly the defers armed
    // before it. The non-throwing exits (fall-through, return,
    // break/continue) run the defers inline via `replay_defers_to_depth`,
    // each unwinding to the handler in force where it was armed, so those
    // copies never reach their own pad. Entries: (landing-pad block, the
    // defer).
    let defer_pads: (int, ArmedDefer)[] = [];
    let shared_error: int? = null;
    // Cause chain: a throw inside a defer pad (a sibling defer that throws
    // while the scope is already unwinding) is "during handling of" the
    // in-flight error. All pads in this block share one `baml.errors.Context`
    // slot; the throw funnel materializes the in-flight error into it when
    // an error reaches a pad, and the next sibling defer's throw chains onto
    // it. Lazily declared alongside `shared_error`.
    let shared_ctx: int? = null;

    for (let stmt_id in stmts) {
        let defer_body: int? = match (ctx.body.stmts[stmt_id]) {
            let defer_stmt: root.ast.StmtDefer => defer_stmt.body,
            _ => null,
        };
        if (defer_body != null) {
            if (shared_error == null) {
                shared_error = ctx.builder.declare_local(root.types.TyUnknown {});
            }
            let error_local = shared_error;
            if (shared_ctx == null) {
                shared_ctx = ctx.builder.declare_local(root.types.TyUnknown {});
            }
            let ctx_local = shared_ctx;
            // The pad unwinds to the handler in force here (the previous pad
            // or the enclosing catch), never to itself. `ctx_local` receives
            // the in-flight error's context so a sibling defer that throws
            // while unwinding chains onto it.
            let pad = ctx.builder.create_handler_block(
                Landing { error_local: error_local, context_local: ctx_local },
            );
            let armed = ArmedDefer { body: defer_body, unwind: ctx.builder.current_unwind };
            // Only the code AFTER this defer unwinds to its pad: a throw
            // before it must not run it.
            ctx.builder.transition_unwind(pad);
            // Registered for inline replay on the non-throwing exits.
            ctx.defer_stack.push(armed);
            defer_pads.push((pad, armed));
        } else {
            lower_stmt(ctx, stmt_id);
            if (ctx.builder.is_current_terminated()) {
                break;
            }
        }
    }

    // The tail expr is still inside the innermost defer region, so a throw
    // here runs the block's defers via the pad path.
    if (!ctx.builder.is_current_terminated()) {
        if (tail_expr != null) {
            lower_expr(ctx, tail_expr, dest);
        } else {
            ctx.builder.assign(
                dest,
                RvalueUse { value: OperandConstant { value: ConstantNull {} } },
            );
        }
    }

    // Normal (non-throwing) fall-through: replay defers inline.
    if (!ctx.builder.is_current_terminated()) {
        replay_defers_to_depth(ctx, defer_depth);
    }

    // What follows the block unwinds past its defers again.
    ctx.builder.transition_unwind(incoming_unwind);

    // Emit the landing pads out of line (reached via the exception table),
    // in reverse order so the innermost (last-armed) pad is laid out first.
    let pad_index = defer_pads.length() - 1;
    while (pad_index >= 0) {
        let pad = defer_pads[pad_index].0;
        let armed = defer_pads[pad_index].1;
        pad_index -= 1;
        // The pad body unwinds to the handler in force where its defer was
        // armed (see `replay_defers_to_depth`) and is its own handler body: a
        // throw inside it is "during handling of" the in-flight error.
        let out_of_line = ctx.builder.begin_out_of_line(pad, armed.unwind, pad);
        lower_shielded_defer_body(ctx, armed.body);
        // A body that completes normally re-raises the in-flight error. This
        // block unwinds to the handler in force where the defer was armed,
        // and landing there fills that handler's error AND context slots, as
        // any throw does. A rethrow, not a fresh throw, so the cause
        // pre-walk does not chain the error onto its own context.
        if (!ctx.builder.is_current_terminated()) {
            let error = shared_error ?? baml.sys.panic("a defer pad implies a shared error local exists");
            let context = shared_ctx ?? baml.sys.panic("a defer pad implies a shared context local exists");
            ctx.builder.rethrow(OperandCopy { value: PlaceLocal { value: error } }, context);
        }
        ctx.builder.end_out_of_line(out_of_line);
    }

    root.syntax.truncate(ctx.defer_stack, defer_depth);
    root.syntax.truncate(ctx.scoped_type_binding_params, type_binding_scope_start);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_expr @ d9be6853b
function lower_expr(
    ctx: LoweringContext,
    expr_id: int,
    dest: Place,
) -> void throws MirInternalError {
    match (dest) {
        let index_dest: PlaceIndex if index_dest.kind == IndexKind.Map => {
            let value = lower_to_operand(ctx, expr_id);
            let ignored = PlaceLocal { value: ctx.builder.declare_local(root.types.TyUnknown {}) };
            emit_map_call(
                ctx,
                "set",
                [
                    OperandCopy { value: index_dest.base },
                    operand_copy_local(index_dest.index),
                    value,
                ],
                ignored,
            );
            return;
        },
        _ => {},
    }
    let prev_span = ctx.builder.current_source_span;
    let span = span_for_expr(ctx, expr_id);
    if (span != null) {
        ctx.builder.current_source_span = span;
    }

    match (ctx.body.exprs[expr_id]) {
        let e: root.ast.ExprLiteral => {
            let constant = lower_literal(e.value);
            ctx.builder.assign(dest, RvalueUse { value: OperandConstant { value: constant } });
        },
        let e: root.ast.ExprByteStringLiteral => {
            ctx.builder.assign(dest, RvalueUint8Array { value: e.value });
        },
        root.ast.ExprNull => {
            ctx.builder.assign(
                dest,
                RvalueUse { value: OperandConstant { value: ConstantNull {} } },
            );
        },
        let e: root.ast.ExprPath => lower_path_expr(ctx, expr_id, e.value.segments, dest),
        let e: root.ast.ExprIf => {
            lower_if(ctx, expr_id, e.condition, e.then_branch, e.else_branch, dest)
        },
        let e: root.ast.ExprIfLet => {
            lower_if_let(ctx, expr_id, e.pattern, e.scrutinee, e.then_branch, e.else_branch, dest)
        },
        let e: root.ast.ExprBinary => lower_binary(ctx, expr_id, e.op, e.lhs, e.rhs, dest),
        let e: root.ast.ExprUnary => lower_unary(ctx, expr_id, e.op, e.expr, dest),
        let e: root.ast.ExprCall => {
            let arg_exprs = e.args.map((arg) -> {
                arg.expr
            });
            lower_call(ctx, expr_id, e.callee, arg_exprs, dest);
        },
        let e: root.ast.ExprArray => {
            let operands: Operand[] = [];
            for (let element in e.elements) {
                operands.push(lower_to_operand(ctx, element));
            }
            let element_ty = array_element_template(ctx, expr_id);
            ctx.builder.assign(dest, RvalueArray { element_ty: element_ty, elements: operands });
        },
        let e: root.ast.ExprTuple => {
            let fields: Operand[] = [];
            for (let element in e.elements) {
                fields.push(lower_to_operand(ctx, element));
            }
            let element_templates = tuple_element_templates(ctx, expr_id, fields.length());
            ctx.builder.assign(
                dest,
                RvalueAggregate {
                    kind: AggregateKindTuple { element_templates: element_templates },
                    fields: fields,
                },
            );
        },
        let e: root.ast.ExprMap => lower_expr_map(ctx, expr_id, e.entries, dest),
        let e: root.ast.ExprObject => lower_object(ctx, expr_id, e.fields, e.spreads, dest),
        let e: root.ast.ExprMemberAccess => {
            lower_member_access_with_base(ctx, expr_id, e.base, e.member, dest)
        },
        let e: root.ast.ExprUpcast => {
            // `.as<I>` is a static type projection. The runtime
            // representation is the original value.
            lower_expr(ctx, e.base, dest);
        },
        root.ast.ExprQualifiedPath => lower_expr_qualified_path(ctx, expr_id, dest),
        let e: root.ast.ExprGenericApply => lower_generic_apply(ctx, expr_id, e.base, dest),
        let e: root.ast.ExprOptionalMemberAccess => {
            lower_optional_member_access(ctx, expr_id, e.base, e.member, dest)
        },
        let e: root.ast.ExprOptionalIndex => lower_optional_index(ctx, e.base, e.index, dest),
        let e: root.ast.ExprOptionalCall => {
            let arg_exprs = e.args.map((arg) -> {
                arg.expr
            });
            lower_optional_call(ctx, expr_id, e.callee, arg_exprs, dest);
        },
        let e: root.ast.ExprIndex => lower_index(ctx, e.base, e.index, dest),
        let e: root.ast.ExprBlock => lower_scoped_block(ctx, e.stmts, e.tail_expr, dest),
        let e: root.ast.ExprMatch => lower_match(ctx, expr_id, e.scrutinee, e.arms, dest),
        let e: root.ast.ExprIs => lower_expr_is(ctx, e.scrutinee, e.pattern, dest),
        let e: root.ast.ExprCatch => lower_catch(ctx, expr_id, e.base, e.clause, dest),
        let e: root.ast.ExprThrow => {
            let val_op = lower_throw_operand(ctx, e.value);
            // Route every throw through the exception funnel (like
            // `StmtThrow`) rather than a static jump to the block's handler:
            // the funnel computes the cause chain and materializes the
            // destination handler's `baml.errors.Context`. The exception
            // table routes the throw to the same handler the static jump
            // would target, so control flow is unchanged.
            emit_throw(ctx, val_op);
            // Start a dead block for any code after this (unreachable).
            let dead = ctx.builder.create_block();
            ctx.builder.set_current_block(dead);
        },
        let e: root.ast.ExprReturn => lower_expr_return(ctx, e.value),
        let e: root.ast.ExprLambda => lower_lambda(ctx, e.value, expr_id, dest),
        let e: root.ast.ExprOptionalChain => lower_optional_chain(ctx, expr_id, e.expr, dest),
        root.ast.ExprMissing => throw internal_error(ctx, "parse error", expr_id),
        let e: root.ast.ExprTemplate => {
            match (e.tag) {
                let tag: root.ast.TemplateTagCustom => {
                    lower_tagged_template(ctx, expr_id, tag.tag, tag.body, e.segments, dest)
                },
                // Untagged: the value is the desugared `elaborated` concat
                // (built at AST lowering and type-checked by TIR). Lower it
                // directly: the structured `segments` were diagnostics-only.
                let tag: root.ast.TemplateTagDefault => lower_expr(ctx, tag.elaborated, dest),
            }
        },
        let e: root.ast.ExprAwait => lower_await(ctx, expr_id, e.future, dest),
    }

    ctx.builder.current_source_span = prev_span;
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_expr @ d9be6853b
// `lower_expr`'s `Expr::Map` arm: a fresh map filled entry by entry with
// `set`, then copied into `dest`.
function lower_expr_map(
    ctx: LoweringContext,
    expr_id: int,
    entries: root.ast.MapExprEntry[],
    dest: Place,
) -> void throws MirInternalError {
    let (let key_ty, let value_ty) = map_kv_templates(ctx, expr_id);
    let map = PlaceLocal { value: ctx.builder.declare_local(expr_ty(ctx, expr_id)) };
    ctx.builder.assign(map, RvalueMap { key_ty: key_ty, value_ty: value_ty, entries: [] });
    for (let entry in entries) {
        let key = lower_to_operand(ctx, entry.key);
        let value = lower_to_operand(ctx, entry.value);
        let ignored = PlaceLocal { value: ctx.builder.declare_local(root.types.TyUnknown {}) };
        emit_map_call(ctx, "set", [OperandCopy { value: map }, key, value], ignored);
    }
    ctx.builder.assign(dest, RvalueUse { value: OperandCopy { value: map } });
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_expr @ d9be6853b
// `lower_expr`'s `Expr::QualifiedPath` arm: `(Base as I).m` as a VALUE, an
// unbound callable resolved from the recorded frame (the same type-keyed
// road every other spelling takes). `self`, if the method takes one, stays
// an ordinary first parameter.
function lower_expr_qualified_path(
    ctx: LoweringContext,
    expr_id: int,
    dest: Place,
) -> void throws MirInternalError {
    match (tir_resolution(ctx, expr_id)) {
        let method: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            match (method.callee) {
                let callee: root.hir_ty.MethodCalleeVirtual<root.types.Ty> => {
                    lower_type_keyed_item_reference(ctx, expr_id, callee, dest);
                    return;
                },
                let callee: root.hir_ty.MethodCalleeConcrete<root.types.Ty> => {
                    lower_type_keyed_item_reference(ctx, expr_id, callee, dest);
                    return;
                },
                _ => {},
            }
        },
        _ => {},
    }
    // TIR admitted this reference, so a frame that fails to resolve here is
    // an internal inconsistency, not a user error: surface it at the origin
    // rather than as a `null` callable that fails somewhere downstream.
    throw internal_error(ctx, "qualified item reference has no resolvable frame", expr_id);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_expr @ d9be6853b
// `lower_expr`'s `Expr::Is` arm: `<scrutinee> is <pattern>`, a runtime
// pattern test that yields `true` if the pattern matches. It reuses
// `lower_pattern_test` (the match-arm engine) with two terminal blocks that
// write the boolean into `dest` and jump to a join.
function lower_expr_is(
    ctx: LoweringContext,
    scrutinee: int,
    pattern: int,
    dest: Place,
) -> void throws MirInternalError {
    let scrutinee_local = try_resolve_to_local(ctx, scrutinee);
    if (scrutinee_local == null) {
        let op = lower_to_operand(ctx, scrutinee);
        let ty = expr_ty(ctx, scrutinee);
        scrutinee_local = operand_to_local(ctx, op, ty);
    }

    let bb_true = ctx.builder.create_block();
    let bb_false = ctx.builder.create_block();
    let bb_join = ctx.builder.create_block();

    lower_pattern_test(ctx, scrutinee_local, pattern, bb_true, bb_false);

    ctx.builder.set_current_block(bb_true);
    ctx.builder.assign(
        dest,
        RvalueUse { value: OperandConstant { value: ConstantBool { value: true } } },
    );
    ctx.builder.goto(bb_join);

    ctx.builder.set_current_block(bb_false);
    ctx.builder.assign(
        dest,
        RvalueUse { value: OperandConstant { value: ConstantBool { value: false } } },
    );
    ctx.builder.goto(bb_join);

    ctx.builder.set_current_block(bb_join);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_expr @ d9be6853b
// `lower_expr`'s `Expr::Return` arm. A `return` expression (a braceless
// `catch`/`match` arm value, `_ => return 0`) transfers control to the
// function's exit: unlike `throw` it does NOT unwind to the block's
// handler. Mirrors `StmtReturn`; `dest` is never written (it diverges).
function lower_expr_return(ctx: LoweringContext, value: int?) -> void throws MirInternalError {
    // _0 is always the return place.
    let ret = 0;
    if (value != null) {
        lower_expr(ctx, value, PlaceLocal { value: ret });
    } else {
        // A bare `return` in a void function returns null. Write it: the
        // return place is defined by the IR, never by the frame's zeroed
        // slots.
        ctx.builder.assign(
            PlaceLocal { value: ret },
            RvalueUse { value: OperandConstant { value: ConstantNull {} } },
        );
    }
    // Run pending defers (LIFO) before jumping to the exit.
    replay_defers_to_depth(ctx, 0);
    ctx.builder.goto(ctx.exit_block);
    // Subsequent code is unreachable; lower it into a dead block.
    let dead = ctx.builder.create_block();
    ctx.builder.set_current_block(dead);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_throw @ d9be6853b
// Throw `value`: a rethrow carrying its landing's context when it reads a
// caught error's local (see `catch_rethrow_locals`), a new throw otherwise.
function emit_throw(ctx: LoweringContext, value: Operand) -> void throws never {
    let context = caught_error_context(ctx, value);
    if (context != null) {
        ctx.builder.rethrow(value, context);
    } else {
        ctx.builder.throw_(value);
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::caught_error_context @ d9be6853b
// The landing context local of the caught error `operand` reads, if it
// reads one.
function caught_error_context(ctx: LoweringContext, operand: Operand) -> int? throws never {
    let place: Place = match (operand) {
        let o: OperandCopy => o.value,
        let o: OperandMove => o.value,
        OperandConstant => {
            return null;
        },
    };
    let local: int = match (place) {
        let p: PlaceLocal => p.value,
        let p: PlaceDeref => {
            cell_id_local(p.value)
                ?? return null
        },
        PlaceCapture | PlaceField | PlaceIndex => {
            return null;
        },
    };
    let found = ctx.catch_rethrow_locals.find((entry) -> {
        entry.0 == local
    });
    if (found != null) {
        found.1
    } else {
        null
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_await @ d9be6853b
// Lower `await expr` into a `TerminatorAwait` whose destination is the
// awaited value.
function lower_await(
    ctx: LoweringContext,
    _expr_id: int,
    future: int,
    dest: Place,
) -> void throws MirInternalError {
    let future_local = ctx.builder.declare_local(root.types.TyNull {});
    let future_place = PlaceLocal { value: future_local };
    lower_expr(ctx, future, future_place);

    // `TerminatorAwait` requires its destination to be a `PlaceLocal`. If
    // the caller handed a projection (field/index), await into a temp local
    // and then assign through to the projection, as `lower_call` normalizes
    // its destination.
    let await_dest = dest;
    let projection_dest: Place? = null;
    match (dest) {
        PlaceLocal => {},
        _ => {
            let tmp = ctx.builder.declare_local(root.types.TyNull {});
            await_dest = PlaceLocal { value: tmp };
            projection_dest = dest;
        },
    }

    let resume = ctx.builder.create_block();
    ctx.builder.await_(future_place, await_dest, resume);
    ctx.builder.set_current_block(resume);

    if (projection_dest != null) {
        ctx.builder.assign(projection_dest, RvalueUse { value: OperandCopy { value: await_dest } });
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::default_delegation @ d9be6853b
// The delegation target of `default.<member>` at `expr_id` inside an
// `implements I { .. }` block: `I`'s default body named `member`, with the
// frame it runs in, `[Self ++ interface generics]`, exactly as the runtime
// seeds an adopted default, expressed over the enclosing impl's generic
// params. `Self` is the enclosing implements-block's subject. Associated
// types are not frame slots.
//
// `null` when `member` names no DEFAULT-BODIED method of a source interface
// target, mirroring TIR's `default_member`: a declared field and a bodyless
// required method have no default body, so the caller falls through to the
// view road.
function default_delegation(
    ctx: LoweringContext,
    expr_id: int,
    member: string,
) -> (int, root.types.Ty[])? throws MirInternalError {
    let db = ctx.db;
    let target = implements_block_iface_target(ctx)
        ?? return null;
    match (target.type_refs.get(target.target).kind) {
        root.hir.TypeRefKindPath => {},
        _ => {
            return null;
        },
    }
    let current_pkg = root.hir.file_package(db, ctx.file);
    let pkg_items = root.hir.package_items(db, current_pkg.root_id);
    let iface_loc = resolve_ref_to_interface_loc(db, target.type_refs, target.target, pkg_items, current_pkg.namespace_path)
        ?? return null;
    let default_loc = root.hir.interface_data(db, iface_loc).methods.find((loc) -> {
        root.hir.function_data(db, loc).name == member && root.hir.function_has_body(db, loc)
    })
        ?? return null;
    let generic_params = enclosing_generic_params(ctx);
    let generic_param_bounds = enclosing_generic_param_bounds(ctx);
    // `implements_block_iface_target` gated entry, and a recorded target
    // pairs with a Class / Impl owner by construction.
    let self_subject = implements_subject_tir_ty(ctx);
    if (self_subject == null) {
        throw internal_error(ctx, "`default.<member>` outside an implements-block method", expr_id);
    }
    // The target lowered whole (as the constraint head it is: written pins
    // only): its generic args.
    let lowered = lower_ref_in_scope_at(
        db,
        target.type_refs,
        target.target,
        pkg_items,
        current_pkg.namespace_path,
        generic_params,
        generic_param_bounds,
        null,
        root.hir_ty.TypePosition.ConstraintHead,
    );
    let iface_args: root.types.Ty[] = match (lowered) {
        let iface: root.types.TyInterface => iface.args,
        // A target that names no interface is refused by the check, so a
        // checked world never lowers one.
        _ => {
            throw internal_error(ctx, "an implements block's target lowered to no interface", expr_id)
        },
    };
    let frame: root.types.Ty[] = [self_subject];
    root.base.extend(frame, iface_args);
    (default_loc, frame)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_default_receiver_root @ d9be6853b
// Whether `segments` is rooted at the `default` receiver keyword and that
// keyword is not shadowed by a local of the same name. See
// `root.ast.DEFAULT_RECEIVER_KEYWORD`.
function is_default_receiver_root(
    ctx: LoweringContext,
    expr_id: int,
    segments: string[],
) -> bool throws never {
    segments.length() > 0
        && segments[0] == root.ast.DEFAULT_RECEIVER_KEYWORD
        && binding_id_for_path(ctx, expr_id, segments[0]) == null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_literal @ d9be6853b
function lower_literal(lit: root.base.Literal) -> Constant throws never {
    match (lit) {
        let l: root.base.LiteralInt => ConstantInt { value: l.value },
        let l: root.base.LiteralBigint => ConstantBigint { value: l.value },
        // A float literal stores its text: parse it (0.0 if it does not
        // parse, as Rust's `unwrap_or(0.0)`).
        let l: root.base.LiteralFloat => {
            let v = float.parse(l.value) catch (_) {
                _ => 0.0,
            };
            ConstantFloat { value: v }
        },
        let l: root.base.LiteralString => ConstantString { value: l.value },
        let l: root.base.LiteralBool => ConstantBool { value: l.value },
    }
}
