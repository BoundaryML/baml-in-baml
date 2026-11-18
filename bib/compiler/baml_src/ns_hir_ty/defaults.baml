// port: baml_compiler2_hir_ty/src/defaults.rs @ d9be6853b
//
// Declaration-structural parameter-default rules (pre-S17 they lived in
// TIR's builder): required-after-default ordering, `self` defaults, and
// forward references from a default to a later parameter. The default's
// TYPE check itself rides the `ParameterDefaults` body inference.
//
// Restructured:
// - `ExprId`, `StmtId` and `PatId` are `int` indexes into the `ExprBody`
//   arenas; `FxHashSet<Name>` is `map<string, bool>`.
// - The recursive walkers bind a local `visit` closure for the repeated
//   `collect_default_expr_forward_references(.., body, later_params,
//   shadowed, refs)` call; `shadowed` and `refs` are shared arrays, so the
//   closure sees every push and truncation.
// - `shadowed.truncate(n)` is `root.syntax.truncate(shadowed, n)`.

// port: baml_compiler2_hir_ty/src/defaults.rs::parameter_default_diagnostics @ d9be6853b
// The structural default rules for one function, spans resolved against the
// parameter spans and the defaults arena's own source map.
function parameter_default_diagnostics(
    db: root.hir.Db,
    function_: int,
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    let data = root.hir.function_data(db, function_);
    let source_map = root.hir.function_source_map(db, function_);
    let defaults = root.hir.function_parameter_defaults(db, function_);
    let out: (root.syntax.TextRange, TirTypeError)[] = [];
    let seen_default = false;
    let index = 0;
    while (index < data.params.length()) {
        let param = data.params[index];
        let default_ref = defaults.param_default(index);
        if (default_ref == null) {
            if (seen_default) {
                out.push(
                    (
                        source_map.param_spans[index],
                        TirTypeErrorRequiredParamAfterDefault { name: param.name },
                    ),
                );
            }
        } else {
            seen_default = true;
            let default_expr = default_ref.expr;
            let default_span = defaults.defaults.source_map.expr_span(default_expr);
            if (param.name == "self") {
                out.push((default_span, TirTypeErrorSelfParamDefault {}));
            } else {
                let later_params: map<string, bool> = {};
                data.params.slice(index + 1, data.params.length()).for_each((later) -> {
                    later_params.set(later.name, true);
                });
                default_expr_forward_references(default_expr, defaults.defaults.exprs, later_params)
                    .for_each((referenced) -> {
                        out.push(
                            (
                                default_span,
                                TirTypeErrorDefaultParamForwardReference {
                                    param: param.name,
                                    referenced: referenced,
                                },
                            ),
                        );
                    });
            }
        }
        index += 1;
    }
    out
}

// port: baml_compiler2_hir_ty/src/defaults.rs::default_expr_forward_references @ d9be6853b
function default_expr_forward_references(
    expr_id: int,
    body: root.ast.ExprBody,
    later_params: map<string, bool>,
) -> string[] throws never {
    let shadowed: string[] = [];
    let refs: string[] = [];
    collect_default_expr_forward_references(expr_id, body, later_params, shadowed, refs);
    refs
}

// port: baml_compiler2_hir_ty/src/defaults.rs::collect_default_expr_forward_references @ d9be6853b
function collect_default_expr_forward_references(
    expr_id: int,
    body: root.ast.ExprBody,
    later_params: map<string, bool>,
    shadowed: string[],
    refs: string[],
) -> void throws never {
    let visit = (id: int) -> void {
        collect_default_expr_forward_references(id, body, later_params, shadowed, refs)
    };
    let visit_opt = (id: int?) -> void {
        if (id != null) {
            visit(id);
        }
    };
    match (body.exprs[expr_id]) {
        let e: root.ast.ExprPath => {
            if let root_name: string = e.value.segments.at(0) {
                if (
                    later_params.has(root_name)
                        && !shadowed.includes(root_name)
                        && !refs.includes(root_name)
                ) {
                    refs.push(root_name);
                }
            }
        },
        let e: root.ast.ExprIf => {
            visit(e.condition);
            visit(e.then_branch);
            visit_opt(e.else_branch);
        },
        let e: root.ast.ExprMatch => {
            visit(e.scrutinee);
            e.arms.for_each((arm_id) -> {
                let arm = body.match_arms[arm_id];
                let saved_len = shadowed.length();
                push_pattern_bindings(arm.pattern, body, shadowed);
                visit_opt(arm.guard);
                visit(arm.body);
                root.syntax.truncate(shadowed, saved_len);
            });
        },
        let e: root.ast.ExprIfLet => {
            visit(e.scrutinee);
            let saved_len = shadowed.length();
            push_pattern_bindings(e.pattern, body, shadowed);
            visit(e.then_branch);
            root.syntax.truncate(shadowed, saved_len);
            visit_opt(e.else_branch);
        },
        let e: root.ast.ExprIs => visit(e.scrutinee),
        let e: root.ast.ExprCatch => {
            visit(e.base);
            let clause_saved_len = shadowed.length();
            push_pattern_bindings(e.clause.binding, body, shadowed);
            if let stack_trace_binding: int = e.clause.stack_trace_binding {
                push_pattern_bindings(stack_trace_binding, body, shadowed);
            }
            e.clause.arms.for_each((arm_id) -> {
                let arm = body.catch_arms[arm_id];
                let arm_saved_len = shadowed.length();
                push_pattern_bindings(arm.pattern, body, shadowed);
                visit(arm.body);
                root.syntax.truncate(shadowed, arm_saved_len);
            });
            root.syntax.truncate(shadowed, clause_saved_len);
        },
        let e: root.ast.ExprThrow => visit(e.value),
        let e: root.ast.ExprUnary => visit(e.expr),
        let e: root.ast.ExprReturn => visit_opt(e.value),
        let e: root.ast.ExprBinary => {
            visit(e.lhs);
            visit(e.rhs);
        },
        let e: root.ast.ExprCall => {
            visit(e.callee);
            e.args.for_each((arg) -> {
                visit(arg.expr)
            });
        },
        let e: root.ast.ExprOptionalCall => {
            visit(e.callee);
            e.args.for_each((arg) -> {
                visit(arg.expr)
            });
        },
        let e: root.ast.ExprObject => {
            e.fields.for_each((field) -> {
                visit(field.value)
            });
            e.spreads.for_each((spread) -> {
                visit(spread.expr)
            });
        },
        let e: root.ast.ExprArray => e.elements.for_each(visit),
        let e: root.ast.ExprTuple => e.elements.for_each(visit),
        let e: root.ast.ExprMap => {
            e.entries.for_each((entry) -> {
                visit(entry.key);
                visit(entry.value);
            });
        },
        let e: root.ast.ExprBlock => {
            let saved_len = shadowed.length();
            e.stmts.for_each((stmt) -> {
                collect_default_stmt_forward_references(stmt, body, later_params, shadowed, refs)
            });
            visit_opt(e.tail_expr);
            root.syntax.truncate(shadowed, saved_len);
        },
        let e: root.ast.ExprMemberAccess => visit(e.base),
        let e: root.ast.ExprUpcast => visit(e.base),
        let e: root.ast.ExprOptionalMemberAccess => visit(e.base),
        let e: root.ast.ExprOptionalChain => visit(e.expr),
        let e: root.ast.ExprIndex => {
            visit(e.base);
            visit(e.index);
        },
        let e: root.ast.ExprOptionalIndex => {
            visit(e.base);
            visit(e.index);
        },
        let e: root.ast.ExprLambda => {
            let func_def = e.value;
            let saved_len = shadowed.length();
            func_def.params.for_each((param) -> {
                shadowed.push(param.name);
            });
            func_def.params.for_each((param) -> {
                if let default: int = param.default {
                    collect_default_expr_forward_references(default, func_def.defaults.exprs, later_params, shadowed, refs);
                }
            });
            visit_opt(func_def.body);
            root.syntax.truncate(shadowed, saved_len);
        },
        let e: root.ast.ExprAwait => visit(e.future),
        let e: root.ast.ExprTemplate => {
            if let tag: root.ast.TemplateTagCustom = e.tag {
                visit(tag.tag);
            }
            collect_default_expr_forward_references_in_template_segments(e.segments, body, later_params, shadowed, refs);
        },
        let e: root.ast.ExprGenericApply => visit(e.base),
        // A qualified item reference is built from two TYPES, so it can never
        // forward-reference a later parameter's default.
        root.ast.ExprLiteral
            | root.ast.ExprByteStringLiteral
            | root.ast.ExprNull
            | root.ast.ExprQualifiedPath
            | root.ast.ExprMissing =>
        {},
    }
}

// port: baml_compiler2_hir_ty/src/defaults.rs::collect_default_expr_forward_references_in_template_segments @ d9be6853b
// Recursive walk over a tagged-template segment tree. Same forward-reference
// collection as `collect_default_expr_forward_references` but threads
// through nested for-bodies and if-branches, pushing for-bindings onto the
// shadowed stack.
function collect_default_expr_forward_references_in_template_segments(
    segments: root.ast.TemplateSegment[],
    body: root.ast.ExprBody,
    later_params: map<string, bool>,
    shadowed: string[],
    refs: string[],
) -> void throws never {
    let visit = (id: int) -> void {
        collect_default_expr_forward_references(id, body, later_params, shadowed, refs)
    };
    let visit_segments = (inner: root.ast.TemplateSegment[]) -> void {
        collect_default_expr_forward_references_in_template_segments(inner, body, later_params, shadowed, refs)
    };
    segments.for_each((seg) -> {
        match (seg) {
            root.ast.TemplateSegmentText => {},
            let s: root.ast.TemplateSegmentInterp => visit(s.value),
            let s: root.ast.TemplateSegmentEffect => visit(s.block),
            let s: root.ast.TemplateSegmentFor => {
                visit(s.collection);
                let saved_len = shadowed.length();
                push_pattern_bindings(s.binding, body, shadowed);
                visit_segments(s.body);
                root.syntax.truncate(shadowed, saved_len);
            },
            let s: root.ast.TemplateSegmentCStyleFor => {
                // Pull the loop var's pattern + initializer out of the `init`
                // `let`.
                let init_let = match (body.stmts[s.init]) {
                    let l: root.ast.StmtLet => l,
                    _ => null,
                };
                let init_initializer = init_let?.initializer;
                let init_pattern = init_let?.pattern;
                // The initializer runs before the loop var is bound, so it
                // may reference outer names but never the loop var itself:
                // process it before shadowing.
                if (init_initializer != null) {
                    visit(init_initializer);
                }
                // Shadow the loop var, then process `cond` and the body. Both
                // see the binding (e.g. `i` in `for (let i = 0; i < n; ...)`),
                // so a later param sharing the name must not flag them as
                // forward references.
                let saved_len = shadowed.length();
                if (init_pattern != null) {
                    push_pattern_bindings(init_pattern, body, shadowed);
                }
                visit(s.cond);
                visit_segments(s.body);
                root.syntax.truncate(shadowed, saved_len);
            },
            let s: root.ast.TemplateSegmentIf => {
                s.branches.for_each((branch) -> {
                    visit(branch.condition);
                    visit_segments(branch.body);
                });
                if let eb: root.ast.TemplateSegment[] = s.else_body {
                    visit_segments(eb);
                }
            },
        }
    });
}

// port: baml_compiler2_hir_ty/src/defaults.rs::push_pattern_bindings @ d9be6853b
function push_pattern_bindings(
    pat_id: int,
    body: root.ast.ExprBody,
    shadowed: string[],
) -> void throws never {
    root.ast.pattern_bound_names(body.patterns[pat_id], body.patterns).for_each((name) -> {
        shadowed.push(name);
    });
}

// port: baml_compiler2_hir_ty/src/defaults.rs::collect_default_stmt_forward_references @ d9be6853b
function collect_default_stmt_forward_references(
    stmt_id: int,
    body: root.ast.ExprBody,
    later_params: map<string, bool>,
    shadowed: string[],
    refs: string[],
) -> void throws never {
    let visit = (id: int) -> void {
        collect_default_expr_forward_references(id, body, later_params, shadowed, refs)
    };
    let visit_opt = (id: int?) -> void {
        if (id != null) {
            visit(id);
        }
    };
    match (body.stmts[stmt_id]) {
        let s: root.ast.StmtExpr => visit(s.value),
        let s: root.ast.StmtReturn => visit_opt(s.value),
        let s: root.ast.StmtThrow => visit(s.value),
        let s: root.ast.StmtTypeBinding => {
            visit(s.operand);
            visit_opt(s.else_branch);
        },
        let s: root.ast.StmtLet => {
            visit_opt(s.initializer);
            if let else_expr: int = s.else_branch {
                // The else branch runs before the pattern's bindings exist,
                // so it can't see them: recurse with the pre-binding
                // `shadowed` set, then re-truncate after.
                let saved_len = shadowed.length();
                visit(else_expr);
                root.syntax.truncate(shadowed, saved_len);
            }
            push_pattern_bindings(s.pattern, body, shadowed);
        },
        let s: root.ast.StmtWhile => {
            visit(s.condition);
            let saved_len = shadowed.length();
            visit(s.body);
            if let after: int = s.after {
                collect_default_stmt_forward_references(after, body, later_params, shadowed, refs);
            }
            root.syntax.truncate(shadowed, saved_len);
        },
        let s: root.ast.StmtWhileLet => {
            // Scrutinee is evaluated outside the pattern's binding scope; the
            // pattern's names shadow within the body only, mirroring
            // `StmtFor` (collection then pattern then body).
            visit(s.scrutinee);
            let saved_len = shadowed.length();
            push_pattern_bindings(s.pattern, body, shadowed);
            visit(s.body);
            root.syntax.truncate(shadowed, saved_len);
        },
        let s: root.ast.StmtFor => {
            visit(s.collection);
            let saved_len = shadowed.length();
            push_pattern_bindings(s.binding, body, shadowed);
            visit(s.body);
            root.syntax.truncate(shadowed, saved_len);
        },
        let s: root.ast.StmtAssign => {
            visit(s.target);
            visit(s.value);
        },
        let s: root.ast.StmtAssignOp => {
            visit(s.target);
            visit(s.value);
        },
        let s: root.ast.StmtDefer => visit(s.body),
        root.ast.StmtBreak
            | root.ast.StmtContinue
            | root.ast.StmtMissing
            | root.ast.StmtHeaderComment =>
        {},
    }
}
