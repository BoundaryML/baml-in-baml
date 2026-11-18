// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// Unit 1 of the K4 plan, part three: `infer_stmt`, the statement walk.
//
// Restructured (BAML forces it): `infer_stmt` keeps Rust's shape; its three
// loop arms are `infer_stmt_while`, `infer_stmt_while_let` and
// `infer_stmt_for`, called where Rust's arms sit.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_stmt @ d9be6853b
function infer_stmt(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    stmt: int,
) -> void throws never {
    match (body.stmts[stmt]) {
        let s: root.ast.StmtExpr => {
            infer_expr(ctx, body, s.value, ExpectationDiscarded {});
        },
        let s: root.ast.StmtTypeBinding => {
            if (s.bounds.length() > 0 && s.else_branch == null) {
                report(ctx, PendingDiagBoundedLetTypeRequiresElse { stmt: stmt, name: s.name });
            }
            bind_scoped_type(ctx, body, stmt, s.name, s.operand, s.else_branch);
        },
        let s: root.ast.StmtLet => infer_let(ctx, body, s.pattern, s.initializer, s.else_branch),
        let s: root.ast.StmtReturn => {
            infer_return(ctx, body, s.value, DiagnosticLocationStmt { value: stmt });
            root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
        },
        let s: root.ast.StmtThrow => {
            infer_throw(ctx, body, s.value);
            root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
        },
        // Loop-local terminators: the path past them is dead, and the flow
        // where they are taken is an edge of the innermost loop: into its exit
        // (`break`) or its update slot (`continue`). With no loop open in the
        // frame there is no edge, only an error: MIR has no target to jump
        // to.
        root.ast.StmtBreak | root.ast.StmtContinue => {
            let edge = if (body.stmts[stmt] is root.ast.StmtBreak) {
                root.hir_ty.infer.LoopEdge.Break
            } else {
                root.hir_ty.infer.LoopEdge.Continue
            };
            let keyword = root.hir_ty.infer.loop_edge_keyword(edge);
            // A rejected jump still ends the flow as written, but records no
            // edge, and the reachability pass does not report the code after
            // it: the rejection is the only report it gets.
            let rejected: PendingDiag? = match (root.hir_ty.infer.loop_control_escape(ctx)) {
                root.hir_ty.infer.LoopControlEscapeDefer => {
                    PendingDiagDeferEscape {
                        at: DiagnosticLocationStmt { value: stmt },
                        keyword: keyword,
                    }
                },
                let outside: root.hir_ty.infer.LoopControlEscapeOutsideLoop => {
                    PendingDiagLoopControlOutsideLoop {
                        stmt: stmt,
                        keyword: keyword,
                        barrier: outside.value,
                    }
                },
                // A loop is left from its body: a jump in a header slot
                // (rustc's E0590 rule) is refused.
                null => {
                    let slot = root.hir_ty.infer.loop_header(ctx);
                    if (slot != null) {
                        PendingDiagLoopControlInLoopHeader {
                            stmt: stmt,
                            keyword: keyword,
                            slot: slot,
                        }
                    } else {
                        null
                    }
                },
            };
            if (rejected != null) {
                report(ctx, rejected);
                ctx.loop_verdicts.rejected_jumps.set(stmt, true);
                root.hir_ty.infer.mark_rejected_jump(ctx);
            } else {
                root.hir_ty.infer.record_loop_edge(ctx, edge);
            }
            root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
        },
        let s: root.ast.StmtDefer => {
            // The defer body runs at scope exit; escaping control flow is
            // rejected (loop-aware: a loop opened inside the defer may
            // break/continue freely). Registration-time facts need not hold
            // when the defer runs, and its writes and divergence do not
            // happen at registration.
            let saved_flow = ctx.flow;
            ctx.flow = {};
            root.hir_ty.infer.enter_frame(ctx, root.hir_ty.infer.FrameKindDefer {});
            infer_expr(ctx, body, s.body, ExpectationDiscarded {});
            root.hir_ty.infer.leave_frame(ctx);
            ctx.flow = saved_flow;
        },
        let s: root.ast.StmtAssign => infer_assign(ctx, body, s.target, s.value, null),
        let s: root.ast.StmtAssignOp => infer_assign(ctx, body, s.target, s.value, s.op),
        let s: root.ast.StmtWhile => infer_stmt_while(ctx, body, stmt, s),
        let s: root.ast.StmtWhileLet => infer_stmt_while_let(ctx, body, stmt, s),
        let s: root.ast.StmtFor => infer_stmt_for(ctx, body, s),
        root.ast.StmtMissing | root.ast.StmtHeaderComment => {
            let children: root.ast.BodyNode[] = [];
            body.stmt_children(stmt, children);
            for (let node in children) {
                match (node) {
                    let child: root.ast.BodyNodeExpr => {
                        infer_expr(ctx, body, child.value, ExpectationNone {});
                    },
                    let child: root.ast.BodyNodeStmt => infer_stmt(ctx, body, child.value),
                }
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_stmt (the `Stmt::While` arm) @ d9be6853b
// The loop discipline (no fixpoint): drop the facts about every binding the
// loop assigns anywhere (condition, body or update slot), since the second
// evaluation of each follows the first's writes; then type each once. The
// condition is typed in that flow, the body under the condition's true
// facts, and the update slot where the body completes and where every
// `continue` lands. The loop's exits are the condition's false edge and the
// body's `break`s (a header holds no jump: E0188); the post-loop flow is
// their merge, and the code after the loop is reachable exactly when some
// exit is. The false edge leaves the havoced flow, so a zero-iteration loop
// keeps no body narrowing.
function infer_stmt_while(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    stmt: int,
    loop: root.ast.StmtWhile,
) -> void throws never {
    let after = loop.after;
    let roots: root.ast.BodyNode[] = [root.ast.BodyNodeExpr { value: loop.condition }, root.ast.BodyNodeExpr { value: loop.body }];
    if (after != null) {
        roots.push(root.ast.BodyNodeStmt { value: after });
    }
    let writes = root.hir_ty.infer.assigned_bindings_in(ctx, body, roots);
    for (let binding in writes.keys()) {
        ctx.flow.delete(binding);
    }
    root.hir_ty.infer.enter_loop(ctx);
    root.hir_ty.infer.set_loop_header(ctx, LoopHeaderSlot.WhileCondition);
    let (_, let facts) = root.hir_ty.infer.check_condition(ctx, body, loop.condition);
    root.hir_ty.infer.set_loop_header(ctx, null);
    // The false edge exists only where the condition completes: a header
    // that always returns leaves none.
    let header_completes = root.hir_ty.infer.diverges(ctx) == Diverges.Maybe;
    let header_flow = root.hir_ty.infer.copy_flow(ctx.flow);
    // The body is entered where the header completes, so under a header that
    // never does, the body is dead and records no edge.
    root.hir_ty.infer.apply_facts(ctx, facts.when_true);
    infer_expr(ctx, body, loop.body, ExpectationDiscarded {});
    if (after != null) {
        let reaching = root.hir_ty.infer.take_continues(ctx);
        if (root.hir_ty.infer.diverges(ctx) == Diverges.Maybe) {
            reaching.push(root.hir_ty.infer.copy_flow(ctx.flow));
        }
        // Nothing reaching the update slot leaves it dead code.
        let merged = root.hir_ty.infer.merge_reaching(ctx, reaching);
        if (merged != null) {
            ctx.flow = merged;
            root.hir_ty.infer.set_diverges(ctx, Diverges.Maybe);
        } else {
            root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
        }
        root.hir_ty.infer.set_loop_header(ctx, LoopHeaderSlot.ForUpdate);
        infer_stmt(ctx, body, after);
        root.hir_ty.infer.set_loop_header(ctx, null);
    }
    let frame = root.hir_ty.infer.leave_loop(ctx);
    // A statically true condition has no false edge.
    let exits = frame.breaks;
    if (header_completes && !condition_is_statically_true(ctx, body, loop.condition)) {
        let false_edge = root.hir_ty.infer.copy_flow(header_flow);
        for (let binding in facts.when_false.keys()) {
            false_edge.set(binding, facts.when_false[binding]);
        }
        exits.push(false_edge);
    }
    // An exit is reached exactly when the loop is entered (the header is
    // typed under the entry divergence, and a dead body records no edge), so
    // some exit means the entry point was live.
    let merged = root.hir_ty.infer.merge_reaching(ctx, exits);
    if (merged != null) {
        ctx.flow = merged;
        root.hir_ty.infer.set_diverges(ctx, Diverges.Maybe);
    } else if (frame.has_rejected_jump) {
        // No exit edge, but the exit the author wrote was rejected, which is
        // report enough.
        ctx.flow = header_flow;
        root.hir_ty.infer.set_diverges(ctx, Diverges.Maybe);
    } else {
        // No exit edge at all: the loop never completes, and everything
        // after it is unreachable.
        ctx.loop_verdicts.diverging_loops.set(stmt, true);
        ctx.flow = header_flow;
        root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_stmt (the `Stmt::WhileLet` arm) @ d9be6853b
function infer_stmt_while_let(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    stmt: int,
    loop: root.ast.StmtWhileLet,
) -> void throws never {
    let writes = root.hir_ty.infer.assigned_bindings_in(
        ctx,
        body,
        [
            root.ast.BodyNodeExpr { value: loop.scrutinee },
            root.ast.BodyNodeExpr { value: loop.body },
        ],
    );
    for (let binding in writes.keys()) {
        ctx.flow.delete(binding);
    }
    root.hir_ty.infer.enter_loop(ctx);
    root.hir_ty.infer.set_loop_header(ctx, LoopHeaderSlot.WhileLetScrutinee);
    let scrut_ty = infer_expr(ctx, body, loop.scrutinee, ExpectationNone {});
    root.hir_ty.infer.set_loop_header(ctx, null);
    let scrut = root.hir_ty.infer.scrutinee_demand(ctx, scrut_ty);
    let outcome = root.hir_ty.infer.lower_pattern(ctx, body, loop.pattern, scrut);
    let header_completes = root.hir_ty.infer.diverges(ctx) == Diverges.Maybe;
    let header_flow = root.hir_ty.infer.copy_flow(ctx.flow);
    // The miss edge is the loop's exit. A bare-local scrutinee keeps the
    // RESIDUAL there (consumes-gated, the `if let` rule) and has the matched
    // type in the body.
    let miss_edge = root.hir_ty.infer.copy_flow(header_flow);
    let binding = root.hir_ty.infer.narrowable_binding(ctx, body, loop.scrutinee);
    if (binding != null) {
        if (outcome.consumes_matched) {
            let residual = root.hir_ty.infer.subtract_narrow(ctx, scrut, outcome.matched_ty);
            miss_edge.set(binding, residual);
        }
        ctx.flow.set(binding, outcome.matched_ty);
    }
    infer_expr(ctx, body, loop.body, ExpectationDiscarded {});
    let frame = root.hir_ty.infer.leave_loop(ctx);
    let exits = frame.breaks;
    if (header_completes) {
        exits.push(miss_edge);
    }
    let merged = root.hir_ty.infer.merge_reaching(ctx, exits);
    if (merged != null) {
        ctx.flow = merged;
        root.hir_ty.infer.set_diverges(ctx, Diverges.Maybe);
    } else if (frame.has_rejected_jump) {
        ctx.flow = header_flow;
        root.hir_ty.infer.set_diverges(ctx, Diverges.Maybe);
    } else {
        ctx.loop_verdicts.diverging_loops.set(stmt, true);
        ctx.flow = header_flow;
        root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_stmt (the `Stmt::For` arm) @ d9be6853b
function infer_stmt_for(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    loop: root.ast.StmtFor,
) -> void throws never {
    let pool = ctx.table.pool;
    // The collection is evaluated once, at loop entry, so it is typed in the
    // entry flow.
    let collection_ty = infer_expr(ctx, body, loop.collection, ExpectationNone {});
    let resolved = ctx.table.resolve_completely(collection_ty);
    let collection = root.hir_ty.infer.matrix_scrut(ctx, resolved);
    // List elements directly; a collection that never produces a value
    // yields no element (the bottom type is iterable, as it is everything);
    // everything else through the Iterator protocol (the `iter.Iterable`
    // Item projection).
    let element = match (pool.kinds[collection]) {
        let list: root.types.InferTyList => list.elem,
        root.types.TyNever => pool.add(root.types.TyNever {}),
        _ => iteration_item(ctx, collection, loop.collection),
    };
    let outcome = root.hir_ty.infer.lower_pattern(ctx, body, loop.binding, element);
    if (
        !outcome.covers_type
            && !pool.has_error(outcome.matched_ty)
            && !pool.has_error(element)
            && !pool.has_infer(element)
    ) {
        report(ctx, PendingDiagRefutableLet { pat: loop.binding, context: IrrefutableContextKind.ForLet });
    }
    let saved = root.hir_ty.infer.diverges(ctx);
    // The exits: zero iterations (the entry flow, where the collection
    // completes), the end of the last iteration, every `continue` (the
    // header it returns to may end the loop) and every `break`. The body is
    // typed with the facts about the bindings it assigns dropped, which
    // covers every iteration after the first, and where the collection
    // completes: a collection that never does leaves the body dead.
    let exits: root.hir_ty.infer.Flow[] = [];
    if (root.hir_ty.infer.diverges(ctx) == Diverges.Maybe) {
        exits.push(root.hir_ty.infer.copy_flow(ctx.flow));
    }
    let havoced = root.hir_ty.infer.assigned_bindings(ctx, body, loop.body);
    for (let binding in havoced.keys()) {
        ctx.flow.delete(binding);
    }
    root.hir_ty.infer.enter_loop(ctx);
    infer_expr(ctx, body, loop.body, ExpectationDiscarded {});
    if (root.hir_ty.infer.diverges(ctx) == Diverges.Maybe) {
        exits.push(root.hir_ty.infer.copy_flow(ctx.flow));
    }
    let frame = root.hir_ty.infer.leave_loop(ctx);
    root.base.extend(exits, frame.continues);
    root.base.extend(exits, frame.breaks);
    let merged = root.hir_ty.infer.merge_reaching(ctx, exits);
    if (merged != null) {
        ctx.flow = merged;
        root.hir_ty.infer.set_diverges(ctx, saved);
    } else {
        // Only a diverging collection leaves no exit; the code after the loop
        // is as unreachable as after it.
        root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::condition_is_statically_true @ d9be6853b
// Whether a loop condition is `true` on every iteration.
//
// The oracle is the condition's INFERRED TYPE, not its syntax, so its reach
// is wider than the literal `while (true)`. Anything that lands on the
// literal type `true` answers yes: the literal itself; a constant fold
// (comparisons over literal operands close under `const_fold_binary`, so
// `while (1 == 1)` qualifies); a flow-narrowed binding (after
// `if (c is true)`, `while (c)` sees the narrowed `true`); a call whose
// return type is declared `-> true`. Truthiness widens it further: any
// always-truthy condition (`while ("x")`, an instance, a closure,
// `flag || true`) has no exit edge. The walk is reachability's, on the types
// resolved so far.
//
// Narrowed bindings stay sound because a loop havocs every binding it
// assigns before the condition is checked. `for (;;)` is out of scope: its
// empty condition lowers to `Expr::Missing`, not to a literal.
function condition_is_statically_true(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    condition: int,
) -> bool throws never {
    let value = root.hir_ty.infer.static_condition(
        ctx.table.pool,
        body,
        (expr) -> int? {
            let ty = ctx.result.type_of_expr.get(expr);
            if (ty != null) {
                ctx.table.resolve_completely(ty)
            } else {
                null
            }
        },
        condition,
    );
    value == true
}
