// port: baml_compiler2_hir_ty/src/infer/reachability.rs @ d9be6853b
//
// Reachability diagnostics over finalized expression types. This pass does
// not propagate values through storage or change typing: in particular, a
// previous read or write of a shared field cannot prove its next value.
//
// Restructured: interned types are `int`s into the pool, so `add_diagnostics`
// and `Reachability` take the pool their result's types index, and
// `static_truthiness` takes it first. The `&mut dyn FnMut` type oracle is a
// closure.

// port: baml_compiler2_hir_ty/src/infer/reachability.rs::add_diagnostics @ d9be6853b
function add_diagnostics(
    pool: root.types.InferPool,
    body: root.ast.ExprBody,
    result: root.hir_ty.WorkingResult,
    loop_verdicts: LoopVerdicts,
    diagnostics: root.hir_ty.TirDiagnostic[],
) -> void throws never {
    let reachability = Reachability { pool: pool, body: body, result: result, loop_verdicts: loop_verdicts };
    for (let expr in body.exprs) {
        match (expr) {
            let e: root.ast.ExprIf => {
                let value = reachability.condition(e.condition);
                if (value != null) {
                    let unreachable = if (value) {
                        e.else_branch
                    } else {
                        e.then_branch
                    };
                    reachability.warn(
                        diagnostics,
                        e.condition,
                        value,
                        if (unreachable != null) {
                            root.hir_ty.RelatedNote {
                                location: root.hir_ty.RelatedLocationExpr { value: unreachable },
                                message: "this branch is unreachable",
                            }
                        } else {
                            null
                        },
                    );
                }
            },
            let e: root.ast.ExprBinary
                if e.op == root.ast.BinaryOp.And || e.op == root.ast.BinaryOp.Or => {
                let short_circuit = e.op == root.ast.BinaryOp.Or;
                if (reachability.condition(e.lhs) == short_circuit) {
                    reachability.warn(
                        diagnostics,
                        e.lhs,
                        short_circuit,
                        root.hir_ty.RelatedNote {
                            location: root.hir_ty.RelatedLocationExpr { value: e.rhs },
                            message: "this expression is unreachable",
                        },
                    );
                }
            },
            let e: root.ast.ExprBlock => {
                let index = e.stmts.find_index((stmt) -> {
                    reachability.stmt_exits(stmt)
                });
                if (index != null) {
                    let remaining = e.stmts.slice(index + 1, e.stmts.length());
                    let tail = e.tail_expr;
                    let primary: root.hir_ty.DiagnosticLocation? = if (remaining.length() > 0) {
                        root.hir_ty.DiagnosticLocationStmt { value: remaining[0] }
                    } else if (tail != null) {
                        root.hir_ty.DiagnosticLocationExpr { value: tail }
                    } else {
                        null
                    };
                    if (primary != null) {
                        let tail_count = if (tail != null) {
                            1
                        } else {
                            0
                        };
                        let note = reachability.never_ending_loop_note(e.stmts[index]);
                        diagnostics.push(
                            root.hir_ty.TirDiagnostic {
                                error: root.hir_ty.TirTypeErrorDeadCode {
                                    unreachable_count: remaining.length() + tail_count,
                                },
                                severity: root.hir_ty.DiagnosticSeverity.Warning,
                                primary: primary,
                                related: if (note != null) {
                                    [note]
                                } else {
                                    []
                                },
                            },
                        );
                    }
                }
            },
            _ => {},
        }
    }
    // A `while` condition that is always falsy leaves the body dead. One
    // that is always truthy makes nothing dead by itself: the loop is left
    // through its body's `break`s, or not at all, and then the code after it
    // is reported above with the condition as the reason.
    for (let stmt in body.stmts) {
        if let w: root.ast.StmtWhile = stmt {
            if (reachability.condition(w.condition) == false) {
                reachability.warn(
                    diagnostics,
                    w.condition,
                    false,
                    root.hir_ty.RelatedNote {
                        location: root.hir_ty.RelatedLocationExpr { value: w.body },
                        message: "this loop body is unreachable",
                    },
                );
            }
        }
    }
    for (let arm in body.match_arms) {
        let guard = arm.guard;
        if (guard == null) {
            continue;
        }
        let value = reachability.condition(guard);
        if (value == null) {
            continue;
        }
        let note = if (!value) {
            root.hir_ty.RelatedNote {
                location: root.hir_ty.RelatedLocationExpr { value: arm.body },
                message: "this match arm is unreachable",
            }
        } else {
            null
        };
        reachability.warn(diagnostics, guard, value, note);
    }
}

// port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability @ d9be6853b
class Reachability {
    pool: root.types.InferPool,
    body: root.ast.ExprBody,
    result: root.hir_ty.WorkingResult,
    // Inference's verdicts about loops without an exit and jumps without a
    // loop.
    loop_verdicts: LoopVerdicts,

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::never_ending_loop_note @ d9be6853b
    // Why the code after `stmt` is dead, when `stmt` is a loop that never
    // ends because its condition is always truthy and its body never
    // `break`s: the condition is the note.
    function never_ending_loop_note(self, stmt: int) -> root.hir_ty.RelatedNote? throws never {
        let w = match (self.body.stmts[stmt]) {
            let w: root.ast.StmtWhile => w,
            _ => {
                return null;
            },
        };
        if (self.loop_verdicts.diverging_loops.has(stmt) && self.condition(w.condition) == true) {
            root.hir_ty.RelatedNote {
                location: root.hir_ty.RelatedLocationExpr { value: w.condition },
                message: "this loop never ends: its condition is always truthy and its body never breaks",
            }
        } else {
            null
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::condition @ d9be6853b
    function condition(self, expr: int) -> bool? throws never {
        static_condition(
            self.pool,
            self.body,
            (expr) -> {
                self.result.type_of_expr.get(expr)
            },
            expr,
        )
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::warn @ d9be6853b
    function warn(
        self,
        diagnostics: root.hir_ty.TirDiagnostic[],
        condition: int,
        value: bool,
        note: root.hir_ty.RelatedNote?,
    ) -> void throws never {
        // Reuse a warning on the condition's cause, including through `!`,
        // `&&`, and `||`, instead of reporting the same cause twice.
        let index = self.condition_warning(condition, diagnostics);
        if (index != null) {
            if (note != null) {
                diagnostics[index].related.push(note);
            }
            return;
        }
        let ty = self.result.type_of_expr.get(condition)
            ?? return;
        let plain = if (static_truthiness(self.pool, ty) == value && !self.pool.has_infer(ty)) {
            self.pool.to_plain_closed(ty)
        } else {
            null
        };
        diagnostics.push(
            root.hir_ty.TirDiagnostic {
                error: root.hir_ty.TirTypeErrorConditionAlwaysConstant { ty: plain, always_true: value },
                severity: root.hir_ty.DiagnosticSeverity.Warning,
                primary: root.hir_ty.DiagnosticLocationExpr { value: condition },
                related: if (note != null) {
                    [note]
                } else {
                    []
                },
            },
        );
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::condition_warning @ d9be6853b
    function condition_warning(
        self,
        condition: int,
        diagnostics: root.hir_ty.TirDiagnostic[],
    ) -> int? throws never {
        let at = root.hir_ty.DiagnosticLocationExpr { value: condition };
        let found = diagnostics.find_index((diagnostic) -> {
            diagnostic.primary == at
                && match (diagnostic.error) {
                    root.hir_ty.TirTypeErrorConditionAlwaysConstant
                        | root.hir_ty.TirTypeErrorUncalledFunctionInCondition
                        | root.hir_ty.TirTypeErrorComparisonAlwaysDisjoint =>
                    {
                        true
                    },
                    _ => false,
                }
        });
        if (found != null) {
            return found;
        }
        match (self.body.exprs[condition]) {
            let e: root.ast.ExprUnary if e.op == root.ast.UnaryOp.Not => {
                self.condition_warning(e.expr, diagnostics)
            },
            let e: root.ast.ExprBinary
                if e.op == root.ast.BinaryOp.And || e.op == root.ast.BinaryOp.Or => {
                self.condition_warning(e.lhs, diagnostics)
                    ?? self.condition_warning(e.rhs, diagnostics)
            },
            _ => null,
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::expr_exits @ d9be6853b
    function expr_exits(self, expr: int) -> bool throws never {
        match (self.body.exprs[expr]) {
            root.ast.ExprReturn | root.ast.ExprThrow => true,
            root.ast.ExprLambda => false,
            let e: root.ast.ExprBlock => {
                let tail = e.tail_expr;
                e.stmts.some((stmt) -> {
                    self.stmt_exits(stmt)
                })
                    || (tail != null && self.expr_exits(tail))
            },
            let e: root.ast.ExprIf => {
                let else_branch = e.else_branch;
                self.expr_exits(e.condition)
                    || match (self.condition(e.condition)) {
                        true => self.expr_exits(e.then_branch),
                        false => else_branch != null && self.expr_exits(else_branch),
                        null => {
                            self.expr_exits(e.then_branch)
                                && else_branch != null
                                && self.expr_exits(else_branch)
                        },
                    }
            },
            let e: root.ast.ExprBinary
                if e.op == root.ast.BinaryOp.And || e.op == root.ast.BinaryOp.Or => {
                let evaluate_rhs = e.op == root.ast.BinaryOp.And;
                self.expr_exits(e.lhs)
                    || (self.condition(e.lhs) == evaluate_rhs && self.expr_exits(e.rhs))
            },
            _ => {
                let ty = self.result.type_of_expr.get(expr);
                ty != null && self.pool.kinds[ty] is root.types.TyNever
            },
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::stmt_exits @ d9be6853b
    function stmt_exits(self, stmt: int) -> bool throws never {
        match (self.body.stmts[stmt]) {
            root.ast.StmtReturn | root.ast.StmtThrow => true,
            // A jump inference rejected (no loop takes it) is not a jump.
            root.ast.StmtBreak | root.ast.StmtContinue => {
                !self.loop_verdicts.rejected_jumps.has(stmt)
            },
            let s: root.ast.StmtExpr => self.expr_exits(s.value),
            let s: root.ast.StmtLet => {
                let initializer = s.initializer;
                initializer != null && self.expr_exits(initializer)
            },
            let s: root.ast.StmtAssign => self.expr_exits(s.value),
            let s: root.ast.StmtAssignOp => self.expr_exits(s.value),
            // A loop with no exit edge never completes: a header that never
            // misses (a statically true condition, a header that always
            // returns) and no live `break` in the body. Inference records
            // that verdict from its walk of the loop, where every `break`
            // registers with the loop it leaves.
            root.ast.StmtWhile | root.ast.StmtWhileLet => {
                self.loop_verdicts.diverging_loops.has(stmt)
            },
            // A `for let` collection runs before the loop opens: its exits
            // leave the enclosing code.
            let s: root.ast.StmtFor => self.expr_exits(s.collection),
            _ => false,
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer/reachability.rs::static_condition @ d9be6853b
// A condition's static value, when the types decide it: walk-time De Morgan
// through `!`, `&&` and `||`, down to the static truthiness of each
// operand's type as `type_of` reports it (null for an operand not typed
// yet). Inference and reachability judge the SAME walk: inference on the
// types it has while typing a loop, to decide whether a `while` condition
// has a false edge; reachability on the final types. Both operands are
// judged before they are combined, as in Rust.
function static_condition(
    pool: root.types.InferPool,
    body: root.ast.ExprBody,
    type_of: (int) -> int? throws never,
    expr: int,
) -> bool? throws never {
    match (body.exprs[expr]) {
        let e: root.ast.ExprUnary if e.op == root.ast.UnaryOp.Not => {
            let inner = static_condition(pool, body, type_of, e.expr);
            if (inner != null) {
                !inner
            } else {
                null
            }
        },
        let e: root.ast.ExprBinary if e.op == root.ast.BinaryOp.And => {
            let lhs = static_condition(pool, body, type_of, e.lhs);
            let rhs = static_condition(pool, body, type_of, e.rhs);
            if (lhs == false || rhs == false) {
                false
            } else if (lhs == true && rhs == true) {
                true
            } else {
                null
            }
        },
        let e: root.ast.ExprBinary if e.op == root.ast.BinaryOp.Or => {
            let lhs = static_condition(pool, body, type_of, e.lhs);
            let rhs = static_condition(pool, body, type_of, e.rhs);
            if (lhs == true || rhs == true) {
                true
            } else if (lhs == false && rhs == false) {
                false
            } else {
                null
            }
        },
        _ => {
            let ty = type_of(expr)
                ?? return null;
            static_truthiness(pool, ty)
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/reachability.rs::static_truthiness @ d9be6853b
function static_truthiness(pool: root.types.InferPool, ty: int) -> bool? throws never {
    match (truthiness(pool, ty)) {
        Truthiness.AlwaysTruthy => true,
        Truthiness.AlwaysFalsy => false,
        Truthiness.Runtime => null,
    }
}
