// port: baml_compiler2_ast/src/lower_tree/body.rs @ d9be6853b
//
// Expression bodies: a typed `Block` to `ExprBody` + `AstSourceMap`, in the
// same arenas the rowan lowering fills. The arenas, the source map and the
// desugaring helpers are `LoweringContext`'s; this file reads the typed tree
// into them. Allocation order is the rowan lowering's (children in source
// order, then the parent), so the two bodies compare equal id for id.
//
// The parser never builds the top-level `Bogus` of `AnyForInit`, `AnyForStep`,
// `AnyMatchScrutinee`, `AnyArrayPatternElement` or `AnyTypeArg`; with the
// unions flattened here, a `Bogus` in one of them is the inner expression's,
// pattern's or type's, and is lowered as that.

// port: baml_compiler2_ast/src/lower_tree/body.rs::lower_body @ d9be6853b
// Lower a function body's block.
function lower_body(
    tree: root.syntax.FileTree,
    block: root.syntax.Block,
) -> (ExprBody, AstSourceMap, LoweringDiagnostic[], EnvVarRef[]) throws never {
    let v = View { tree: tree };
    let ctx = LoweringContext.new();
    let root_expr = block_expr(ctx, v, block);
    ctx.finish(root_expr)
}

// ── Blocks and statements ─────────────────────────────────────────────────

// port: baml_compiler2_ast/src/lower_tree/body.rs::block_expr @ d9be6853b
function block_expr(ctx: LoweringContext, v: View, block: root.syntax.Block) -> int throws never {
    block_body(ctx, v, block.stmts, block.tail, v.range(block.span))
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::block_body @ d9be6853b
// A block's statements and tail as one `ExprBlock`; a `${…}` interpolation is
// one without its own node. A header after the block's last expression makes
// that expression a statement: the block then has no value. A diverging tail
// (`return x`, `throw e`, `break`, `continue`) is the statement it is in the
// rowan lowering: the block has no value.
function block_body(
    ctx: LoweringContext,
    v: View,
    stmts: root.syntax.AnyStmt[],
    tail: root.syntax.AnyExpr?,
    span: root.syntax.TextRange,
) -> int throws never {
    let stmts_out: int[] = [];
    for (let stmt in stmts) {
        let lowered = statement(ctx, v, stmt);
        if (lowered != null) {
            stmts_out.push(lowered);
        }
    }
    let tail_expr: int? = match (tail) {
        let e: root.syntax.ReturnExpr => {
            let value = if let value_node: root.syntax.AnyExpr = e.value {
                expression(ctx, v, value_node)
            } else {
                null
            };
            stmts_out.push(ctx.alloc_stmt(StmtReturn { value: value }, v.range(e.span)));
            null
        },
        let e: root.syntax.ThrowExpr => {
            let value = expr_or_missing(ctx, v, e.payload, v.range(e.span));
            stmts_out.push(ctx.alloc_stmt(StmtThrow { value: value }, v.range(e.span)));
            null
        },
        let e: root.syntax.BreakExpr => {
            stmts_out.push(ctx.alloc_stmt(StmtBreak {}, v.range(e.span)));
            null
        },
        let e: root.syntax.ContinueExpr => {
            stmts_out.push(ctx.alloc_stmt(StmtContinue {}, v.range(e.span)));
            null
        },
        let e: root.syntax.AnyExpr => expression(ctx, v, e),
        null => null,
    };
    ctx.alloc_expr(ExprBlock { stmts: stmts_out, tail_expr: tail_expr }, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::statement @ d9be6853b
// One statement; a stray `;` is none.
function statement(ctx: LoweringContext, v: View, stmt: root.syntax.AnyStmt) -> int? throws never {
    match (stmt) {
        let s: root.syntax.LetStmt => let_stmt(ctx, v, s),
        let s: root.syntax.AssignStmt => assignment(ctx, v, s),
        let s: root.syntax.ExprStmt => expr_stmt(ctx, v, s),
        root.syntax.EmptyStmt => null,
        let s: root.syntax.DeferStmt => {
            let span = v.range(s.span);
            let body = block_or_missing(ctx, v, s.body, span);
            ctx.alloc_stmt(StmtDefer { body: body }, span)
        },
        let s: root.syntax.WhileStmt => {
            let span = v.range(s.span);
            let condition = expr_or_missing(ctx, v, s.cond, span);
            let body = block_or_missing(ctx, v, s.body, span);
            ctx.alloc_stmt(
                StmtWhile {
                    condition: condition,
                    body: body,
                    after: null,
                    origin: LoopOriginWhile {},
                },
                span,
            )
        },
        let s: root.syntax.ForStmt => for_stmt(ctx, v, s),
        let s: root.syntax.HeaderStmt => header_stmt(ctx, v, s),
        let s: root.syntax.TypeBindingStmt => type_binding_stmt(ctx, v, s),
        let s: root.syntax.WhileLetStmt => while_let_stmt(ctx, v, s),
        let s: root.syntax.TestDef => nested_test_stmt(ctx, v, s),
        let s: root.syntax.Bogus => ctx.alloc_stmt(StmtMissing {}, v.range(s.span)),
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::statement (the `Expr` arm) @ d9be6853b
// deviation: split out of `statement`. Diverging forms are statements of
// their own kind; any other expression statement spans its expression, not
// its `;`.
function expr_stmt(ctx: LoweringContext, v: View, s: root.syntax.ExprStmt) -> int throws never {
    let span = v.range(s.span);
    match (s.expr) {
        let e: root.syntax.ReturnExpr => {
            let value = if let value_node: root.syntax.AnyExpr = e.value {
                expression(ctx, v, value_node)
            } else {
                null
            };
            ctx.alloc_stmt(StmtReturn { value: value }, span)
        },
        let e: root.syntax.ThrowExpr => {
            let value = expr_or_missing(ctx, v, e.payload, v.range(e.span));
            ctx.alloc_stmt(StmtThrow { value: value }, span)
        },
        root.syntax.BreakExpr => ctx.alloc_stmt(StmtBreak {}, span),
        root.syntax.ContinueExpr => ctx.alloc_stmt(StmtContinue {}, span),
        let e: root.syntax.AnyExpr => {
            let expr_span = v.range(root.syntax.node_span(e));
            let expr = expression(ctx, v, e);
            ctx.alloc_stmt(StmtExpr { value: expr }, expr_span)
        },
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::statement (the `TypeBinding` arm) @ d9be6853b
// deviation: split out of `statement`. `let type T extends A & B = e else { … }`.
function type_binding_stmt(
    ctx: LoweringContext,
    v: View,
    s: root.syntax.TypeBindingStmt,
) -> int throws never {
    let span = v.range(s.span);
    let name = match (s.name) {
        let n: root.syntax.Name => v.name(n),
        root.syntax.Missing => "<missing>",
    };
    let bounds: TypeExpr[] = [];
    let bound_list = s.bounds;
    if (bound_list != null) {
        let tys: (root.syntax.AnyType | root.syntax.Missing)[] = [bound_list.first];
        for (let arm in bound_list.rest) {
            tys.push(arm.ty);
        }
        for (let ty in tys) {
            if let t: root.syntax.AnyType = ty {
                bounds.push(lower_type(v, ctx.diags, t));
            }
        }
    }
    let operand = expr_or_missing(ctx, v, s.init, span);
    let else_block = s.else_branch?.block;
    let else_branch = if let b: root.syntax.Block = else_block {
        block_expr(ctx, v, b)
    } else {
        null
    };
    let stmt = ctx.alloc_stmt(
        StmtTypeBinding { name: name, operand: operand, bounds: bounds, else_branch: else_branch },
        span,
    );
    if let n: root.syntax.Name = s.name {
        ctx.source_map.type_binding_name_spans.set(stmt, v.name_range(n));
    }
    stmt
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::statement (the `WhileLet` arm) @ d9be6853b
// deviation: split out of `statement`.
function while_let_stmt(
    ctx: LoweringContext,
    v: View,
    s: root.syntax.WhileLetStmt,
) -> int throws never {
    let span = v.range(s.span);
    warn_const_introducer(ctx, v, s.introducer);
    if let p: root.syntax.AnyPattern = s.pattern {
        check_const_pattern(ctx, v, p, s.introducer);
    }
    let pat = match (s.pattern) {
        let p: root.syntax.AnyPattern => pattern(ctx, v, p),
        root.syntax.Missing => ctx.alloc_pattern(PatternWildcard {}, span),
    };
    let scrutinee = expr_or_missing(ctx, v, s.scrutinee, span);
    let body = block_or_missing(ctx, v, s.body, span);
    ctx.alloc_stmt(StmtWhileLet { pattern: pat, scrutinee: scrutinee, body: body }, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::statement (the `Test` arm) @ d9be6853b
// deviation: split out of `statement`. A nested `test`/`testset` registers
// against the enclosing testset's collector; anywhere else there is nothing
// to register against and the declaration is dropped, reported here as
// `TestOutsideTestset`.
function nested_test_stmt(
    ctx: LoweringContext,
    v: View,
    s: root.syntax.TestDef,
) -> int throws never {
    let span = v.range(s.span);
    let collector = ctx.testset_collector_var;
    if (collector != null) {
        let call = nested_test_register_call(ctx, v, s, collector);
        return ctx.alloc_stmt(StmtExpr { value: call }, span);
    }
    let kind = if (v.tree.tokens.kinds[s.kw] == root.syntax.TokenKind.Testset) {
        TestBlockKind.Testset
    } else {
        TestBlockKind.Test
    };
    ctx.diags.push(LoweringDiagnosticTestOutsideTestset { kind: kind, span: span });
    ctx.alloc_stmt(StmtMissing {}, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::lambda_body @ d9be6853b
// A block as a lambda's body: a `test` inside registers nowhere (test bodies
// do not nest), so the collector is cleared for its duration.
function lambda_body(ctx: LoweringContext, v: View, block: root.syntax.Block) -> int throws never {
    let saved = ctx.testset_collector_var;
    ctx.testset_collector_var = null;
    let body = block_expr(ctx, v, block);
    ctx.testset_collector_var = saved;
    body
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::testset_collector_body @ d9be6853b
// A testset's block as its collector lambda's body: a `test` inside
// registers against `collector`.
function testset_collector_body(
    ctx: LoweringContext,
    v: View,
    block: root.syntax.Block,
    collector: string,
) -> int throws never {
    let saved = ctx.testset_collector_var;
    ctx.testset_collector_var = collector;
    let body = block_expr(ctx, v, block);
    ctx.testset_collector_var = saved;
    body
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::nested_test_register_call @ d9be6853b
// A `test`/`testset` nested in a testset body, as the
// `<collector>.register_test(name, lambda, runner)` /
// `<collector>.register_test_set(name, collector_lambda, runner)` call it
// desugars to.
function nested_test_register_call(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.TestDef,
    collector: string,
) -> int throws never {
    let span = v.range(node.span);
    let is_set = v.tree.tokens.kinds[node.kw] == root.syntax.TokenKind.Testset;
    let name_expr = match (node.name) {
        let n: root.syntax.AnyExpr => expression(ctx, v, n),
        root.syntax.Missing => {
            ctx.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: "" } }, span)
        },
    };
    let body = match (node.body) {
        let b: root.syntax.Block if is_set => testset_collector_body(ctx, v, b, "testset"),
        let b: root.syntax.Block => lambda_body(ctx, v, b),
        root.syntax.Missing => ctx.alloc_expr(ExprNull {}, span),
    };
    let params: Param[] = [];
    let register = "register_test";
    if (is_set) {
        params.push(
            Param {
                name: "testset",
                type_expr: TypeExpr {
                    kind: TypeExprKindPath {
                        path: root.base.Path.compiler(["testing", "TestCollector"]),
                        generic_args: [],
                        associated_type_bindings: [],
                    },
                    span: span,
                },
                default: null,
                span: span,
                name_span: span,
            },
        );
        register = "register_test_set";
    }
    let lambda = LambdaDef {
        kind: LambdaKind.Anonymous,
        params: params,
        defaults: FunctionDefaults.empty(),
        return_type: null,
        throws_: null,
        body: body,
        span: span,
    };
    let collector_ref = ctx.alloc_expr(ExprPath { value: root.base.Path.new([collector]) }, span);
    let method_target = ctx.alloc_expr(ExprMemberAccess { base: collector_ref, member: register }, span);
    let lambda_arg = ctx.alloc_expr(ExprLambda { value: lambda }, span);
    let runner_arg = test_runner(ctx, v, node.with, span);
    ctx.alloc_expr(
        ExprCall {
            callee: method_target,
            type_args: [],
            args: [
                CallArg.positional(name_expr),
                CallArg.positional(lambda_arg),
                CallArg.positional(runner_arg),
            ],
        },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::test_runner @ d9be6853b
// The `with <runner>` of a test, or `null` when it has none.
function test_runner(
    ctx: LoweringContext,
    v: View,
    with_clause: root.syntax.WithClause?,
    span: root.syntax.TextRange,
) -> int throws never {
    let runner = with_clause?.items.at(0)?.item;
    if (runner != null) {
        return expression(ctx, v, runner);
    }
    ctx.alloc_expr(ExprNull {}, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::let_stmt @ d9be6853b
function let_stmt(ctx: LoweringContext, v: View, node: root.syntax.LetStmt) -> int throws never {
    let span = v.range(node.span);
    let pat = if let p: root.syntax.AnyPattern = node.pattern {
        pattern(ctx, v, p)
    } else {
        null
    };
    let initializer = if let e: root.syntax.AnyExpr = node.init {
        expression(ctx, v, e)
    } else {
        null
    };
    let else_block = node.else_branch?.block;
    let else_branch = if let b: root.syntax.Block = else_block {
        block_expr(ctx, v, b)
    } else {
        null
    };
    warn_const_introducer(ctx, v, node.introducer);
    if let p: root.syntax.AnyPattern = node.pattern {
        check_const_pattern(ctx, v, p, node.introducer);
    }
    let bound = pat ?? ctx.alloc_pattern(PatternWildcard {}, span);
    ctx.alloc_stmt(
        StmtLet {
            pattern: bound,
            initializer: initializer,
            origin: LetOrigin.Source,
            else_branch: else_branch,
        },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::warn_const_introducer @ d9be6853b
// A `const` introducer is reported where it is not the file-scope one.
function warn_const_introducer(
    ctx: LoweringContext,
    v: View,
    introducer: int,
) -> void throws never {
    if (v.tree.tokens.kinds[introducer] != root.syntax.TokenKind.Const) {
        return;
    }
    let span = v.token_range(introducer);
    if (ctx.file_scope_introducer != span) {
        ctx.warn_const_introducer(span);
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::assignment @ d9be6853b
// `target = value` or `target op= value`. The statement spans the assignment,
// not its `;`, as the rowan lowering spans it. Only a place can be assigned
// to; `Missing` counts so a reported syntax error does not cascade.
function assignment(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.AssignStmt,
) -> int throws never {
    let op: AssignOp? = match (node.op.op) {
        root.syntax.AssignOp.Assign => null,
        root.syntax.AssignOp.AddAssign => AssignOp.Add,
        root.syntax.AssignOp.SubAssign => AssignOp.Sub,
        root.syntax.AssignOp.MulAssign => AssignOp.Mul,
        root.syntax.AssignOp.DivAssign => AssignOp.Div,
        root.syntax.AssignOp.ModAssign => AssignOp.Mod,
        root.syntax.AssignOp.BitAndAssign => AssignOp.BitAnd,
        root.syntax.AssignOp.BitOrAssign => AssignOp.BitOr,
        root.syntax.AssignOp.BitXorAssign => AssignOp.BitXor,
        root.syntax.AssignOp.ShlAssign => AssignOp.Shl,
        root.syntax.AssignOp.ShrAssign => AssignOp.Shr,
    };
    let start = v.range(root.syntax.node_span(node.target)).start;
    let end = match (node.value) {
        let e: root.syntax.AnyExpr => v.range(root.syntax.node_span(e)).end,
        root.syntax.Missing => {
            let last = node.op.first + root.syntax.assign_op_tokens(node.op.op).length() - 1;
            v.token_range(last).end
        },
    };
    let span = root.syntax.TextRange { start: start, end: end };
    let target = expression(ctx, v, node.target);
    let value = expr_or_missing(ctx, v, node.value, span);
    if (!ctx.is_assignable_place(target)) {
        let destructure = op == null && (ctx.exprs[target] is ExprArray || ctx.exprs[target] is ExprObject);
        ctx.diags.push(
            LoweringDiagnosticInvalidAssignmentTarget {
                span: ctx.source_map.expr_span(target),
                destructure: destructure,
            },
        );
    }
    let stmt: Stmt = if (op != null) {
        StmtAssignOp { target: target, op: op, value: value }
    } else {
        StmtAssign { target: target, value: value }
    };
    ctx.alloc_stmt(stmt, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::for_stmt @ d9be6853b
function for_stmt(ctx: LoweringContext, v: View, node: root.syntax.ForStmt) -> int throws never {
    let span = v.range(node.span);
    let header: root.syntax.ForInHeader? = match (node.header) {
        let h: root.syntax.ForInHeader => h,
        let h: root.syntax.ParenForInHeader => h.header,
        let h: root.syntax.CForHeader => {
            return c_style_for(ctx, v, h, node.body, span);
        },
        root.syntax.Bogus | root.syntax.Missing => null,
    };
    let binding: int? = null;
    let collection: int? = null;
    if (header != null) {
        warn_const_introducer(ctx, v, header.introducer);
        if let p: root.syntax.AnyPattern = header.pattern {
            check_const_pattern(ctx, v, p, header.introducer);
            binding = pattern(ctx, v, p);
        }
        if let e: root.syntax.AnyExpr = header.iter {
            collection = expression(ctx, v, e);
        }
    }
    let body = if let b: root.syntax.Block = node.body {
        block_expr(ctx, v, b)
    } else {
        null
    };
    let collection_id = collection ?? ctx.alloc_expr(ExprMissing {}, span);
    let body_id = body ?? ctx.alloc_expr(ExprMissing {}, span);
    let binding_id = binding ?? ctx.alloc_pattern(PatternWildcard {}, span);
    ctx.alloc_stmt(StmtFor { binding: binding_id, collection: collection_id, body: body_id }, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::c_style_for @ d9be6853b
// `for (let i = 0; cond; step) { body }` as `{ let i = 0; while cond { body }
// after { step } }`, as the rowan lowering desugars it.
function c_style_for(
    ctx: LoweringContext,
    v: View,
    header: root.syntax.CForHeader,
    body: root.syntax.Block | root.syntax.Missing,
    span: root.syntax.TextRange,
) -> int throws never {
    let init_stmt = match (header.init) {
        let s: root.syntax.LetStmt => let_stmt(ctx, v, s),
        _ => ctx.alloc_stmt(StmtMissing {}, span),
    };
    let cond = header.cond;
    let condition = if (cond != null) {
        expression(ctx, v, cond)
    } else {
        ctx.alloc_expr(ExprMissing {}, span)
    };
    let step = header.step;
    let after_stmt = if (step != null) {
        step_stmt(ctx, v, step)
    } else {
        null
    };
    let body_id = block_or_missing(ctx, v, body, span);
    let while_stmt = ctx.alloc_stmt(
        StmtWhile {
            condition: condition,
            body: body_id,
            after: after_stmt,
            origin: LoopOriginFor { init: init_stmt },
        },
        span,
    );
    let block = ctx.alloc_expr(ExprBlock { stmts: [init_stmt, while_stmt], tail_expr: null }, span);
    ctx.alloc_stmt(StmtExpr { value: block }, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::step_stmt @ d9be6853b
// A C-style `for` step: an assignment (`i += 1`) or an expression run for its
// effect.
function step_stmt(
    ctx: LoweringContext,
    v: View,
    step: root.syntax.AnyForStep,
) -> int throws never {
    match (step) {
        let s: root.syntax.AssignStmt => assignment(ctx, v, s),
        let e: root.syntax.AnyExpr => {
            let span = v.range(root.syntax.node_span(e));
            let expr = expression(ctx, v, e);
            ctx.alloc_stmt(StmtExpr { value: expr }, span)
        },
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::header_stmt @ d9be6853b
// `//# Title`: the level is the number of `#`s, the name the rest.
function header_stmt(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.HeaderStmt,
) -> int throws never {
    let text = v.text(node.token);
    let after_slashes = if (text.starts_with("//")) {
        text.slice(2, text.length())
    } else {
        text
    };
    let chars = after_slashes.chars();
    let level = 0;
    while (level < chars.length() && chars[level] == "#") {
        level += 1;
    }
    let title = after_slashes.slice(level, after_slashes.length()).trim();
    let name = if (title) {
        title
    } else {
        "_"
    };
    ctx.alloc_stmt(StmtHeaderComment { name: name, level: level }, v.range(node.span))
}

// ── Expressions ───────────────────────────────────────────────────────────

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression @ d9be6853b
// An expression; one holding an unwrapped `?.` chain is wrapped here.
function expression(ctx: LoweringContext, v: View, expr: root.syntax.AnyExpr) -> int throws never {
    let id = expression_in_chain(ctx, v, expr);
    if (ctx.needs_chain_wrap.delete(id) != null) {
        return ctx.alloc_expr(ExprOptionalChain { expr: id }, v.range(root.syntax.node_span(expr)));
    }
    id
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expr_or_missing @ d9be6853b
function expr_or_missing(
    ctx: LoweringContext,
    v: View,
    expr: root.syntax.AnyExpr | root.syntax.Missing,
    missing_at: root.syntax.TextRange,
) -> int throws never {
    match (expr) {
        let e: root.syntax.AnyExpr => expression(ctx, v, e),
        root.syntax.Missing => ctx.alloc_expr(ExprMissing {}, missing_at),
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::block_or_missing @ d9be6853b
function block_or_missing(
    ctx: LoweringContext,
    v: View,
    block: root.syntax.Block | root.syntax.Missing,
    missing_at: root.syntax.TextRange,
) -> int throws never {
    match (block) {
        let b: root.syntax.Block => block_expr(ctx, v, b),
        root.syntax.Missing => ctx.alloc_expr(ExprMissing {}, missing_at),
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression_in_chain @ d9be6853b
// An expression as the base of a `?.` chain: not wrapped, so the chain closes
// at its outermost link.
// deviation: the longer arms are split into the `*_expr` functions below.
function expression_in_chain(
    ctx: LoweringContext,
    v: View,
    expr: root.syntax.AnyExpr,
) -> int throws never {
    let span = v.range(root.syntax.node_span(expr));
    match (expr) {
        let e: root.syntax.PathExpr => path_expr(ctx, v, e),
        let e: root.syntax.GenericApplyExpr => {
            let base = expression_in_chain(ctx, v, e.base);
            generic_apply(ctx, v, e.base, base, e.args, span)
        },
        let e: root.syntax.LiteralExpr => ctx.alloc_expr(literal_token(ctx, v, e.token), span),
        let e: root.syntax.TupleExpr => {
            let elements = e.elements.map((element) -> {
                expression(ctx, v, element.item)
            });
            ctx.alloc_expr(ExprTuple { elements: elements }, span)
        },
        let e: root.syntax.TupleFieldExpr => tuple_field_expr(ctx, v, e, span),
        let e: root.syntax.StringLit => string_literal(ctx, v, e),
        let e: root.syntax.FieldAccessExpr => {
            field_access_expr(ctx, v, expression_in_chain(ctx, v, e.base), e.name, span)
        },
        let e: root.syntax.OptionalFieldAccessExpr => {
            optional_field_access_expr(ctx, v, expression_in_chain(ctx, v, e.base), e.name, span)
        },
        let e: root.syntax.CallExpr => call_expr(ctx, v, e),
        let e: root.syntax.OptionalCallExpr => {
            let callee = expression_in_chain(ctx, v, e.callee);
            let (let args, let label_spans) = call_args(ctx, v, e.args);
            let id = ctx.alloc_expr(ExprOptionalCall { callee: callee, args: args }, span);
            ctx.record_call_arg_label_spans(id, label_spans);
            ctx.needs_chain_wrap.delete(callee);
            ctx.needs_chain_wrap.set(id, true);
            id
        },
        let e: root.syntax.IndexExpr => {
            let base = expression_in_chain(ctx, v, e.base);
            let index = expr_or_missing(ctx, v, e.index, span);
            let id = ctx.alloc_expr(ExprIndex { base: base, index: index }, span);
            if (ctx.needs_chain_wrap.delete(base) != null) {
                ctx.needs_chain_wrap.set(id, true);
            }
            id
        },
        let e: root.syntax.OptionalIndexExpr => {
            let base = expression_in_chain(ctx, v, e.base);
            let index = expr_or_missing(ctx, v, e.index, span);
            let id = ctx.alloc_expr(ExprOptionalIndex { base: base, index: index }, span);
            ctx.needs_chain_wrap.delete(base);
            ctx.needs_chain_wrap.set(id, true);
            id
        },
        let e: root.syntax.BinaryExpr => binary_expr(ctx, v, e),
        let e: root.syntax.UnaryExpr => unary_expr(ctx, v, e),
        let e: root.syntax.AwaitExpr => {
            let future = expr_or_missing(ctx, v, e.operand, span);
            ctx.alloc_expr(ExprAwait { future: future }, span)
        },
        let e: root.syntax.ThrowExpr => {
            let value = expr_or_missing(ctx, v, e.payload, span);
            ctx.alloc_expr(ExprThrow { value: value }, span)
        },
        let e: root.syntax.ReturnExpr => {
            let value = if let value_node: root.syntax.AnyExpr = e.value {
                expression(ctx, v, value_node)
            } else {
                null
            };
            ctx.alloc_expr(ExprReturn { value: value }, span)
        },
        root.syntax.BreakExpr => lower_jump_expr_at(ctx, StmtBreak {}, span),
        root.syntax.ContinueExpr => lower_jump_expr_at(ctx, StmtContinue {}, span),
        let e: root.syntax.ParenExpr => expr_or_missing(ctx, v, e.inner, span),
        let e: root.syntax.Block => block_expr(ctx, v, e),
        let e: root.syntax.IfExpr => if_expr(ctx, v, e),
        let e: root.syntax.IfLetExpr => if_let_expr(ctx, v, e),
        let e: root.syntax.MatchExpr => match_expr(ctx, v, e),
        let e: root.syntax.IsExpr => {
            let scrutinee = expression(ctx, v, e.expr);
            let pat = match (e.pattern) {
                let p: root.syntax.AnyPattern => pattern(ctx, v, p),
                root.syntax.Missing => ctx.alloc_pattern(PatternWildcard {}, span),
            };
            ctx.alloc_expr(ExprIs { scrutinee: scrutinee, pattern: pat }, span)
        },
        let e: root.syntax.UpcastExpr => upcast_expr(ctx, v, e, span),
        let e: root.syntax.QualifiedPath => qualified_path_expr(ctx, v, e, span),
        let e: root.syntax.EnvAccessExpr => env_access_expr(ctx, v, e, span),
        let e: root.syntax.SpecExpr => spec_expr(ctx, v, e, span),
        let e: root.syntax.LambdaExpr => lambda_expr(ctx, v, e),
        let e: root.syntax.ObjectLiteral => object_literal(ctx, v, e),
        let e: root.syntax.CatchExpr => catch_expr(ctx, v, e),
        let e: root.syntax.SpawnExpr => spawn_expr(ctx, v, e),
        let e: root.syntax.ArrayLiteral => {
            let elements = e.elements.map((element) -> {
                expression(ctx, v, element.value)
            });
            ctx.alloc_expr(ExprArray { elements: elements }, span)
        },
        let e: root.syntax.MapLiteral => map_expr(ctx, v, e, span),
        let e: root.syntax.BacktickString => backtick_expr(ctx, v, e),
        let e: root.syntax.TaggedTemplateExpr => tagged_template_expr(ctx, v, e),
        root.syntax.Bogus => ctx.alloc_expr(ExprMissing {}, span),
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression_in_chain (the `TupleField` arm) @ d9be6853b
// deviation: split out of `expression_in_chain`. `t.0.1` is one token; each
// slot is a member access spanning from the base to its end.
function tuple_field_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.TupleFieldExpr,
    span: root.syntax.TextRange,
) -> int throws never {
    let base = expression_in_chain(ctx, v, node.base);
    let start = v.token_range(node.slot).start;
    let optional = v.tree.tokens.kinds[node.dot] == root.syntax.TokenKind.QuestionDot;
    let parts = v.text(node.slot).split(".");
    for (let index = 0; index < parts.length(); index += 1) {
        let part = parts[index];
        let end = start + part.byte_length();
        let first_optional = optional && index == 0;
        let access: Expr = if (first_optional) {
            ExprOptionalMemberAccess { base: base, member: part }
        } else {
            ExprMemberAccess { base: base, member: part }
        };
        let next = ctx.alloc_expr(access, root.syntax.TextRange { start: span.start, end: end });
        ctx.source_map.member_access_member_spans.set(
            next,
            root.syntax.TextRange { start: start, end: end },
        );
        if (ctx.needs_chain_wrap.delete(base) != null || first_optional) {
            ctx.needs_chain_wrap.set(next, true);
        }
        base = next;
        start = end + 1;
    }
    base
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression_in_chain (the `FieldAccess` arm) @ d9be6853b
// deviation: split out of `expression_in_chain` and shared with
// `callee_without_receiver_args`, which repeats it in Rust. `base` is the
// lowered receiver; a missing name is `_`.
function field_access_expr(
    ctx: LoweringContext,
    v: View,
    base: int,
    name: root.syntax.Name | root.syntax.Missing,
    span: root.syntax.TextRange,
) -> int throws never {
    let member = if let n: root.syntax.Name = name {
        v.name(n)
    } else {
        "_"
    };
    let id = ctx.alloc_expr(ExprMemberAccess { base: base, member: member }, span);
    if let n: root.syntax.Name = name {
        ctx.source_map.member_access_member_spans.set(id, v.name_range(n));
    }
    if (ctx.needs_chain_wrap.delete(base) != null) {
        ctx.needs_chain_wrap.set(id, true);
    }
    id
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression_in_chain (the `OptionalFieldAccess` arm) @ d9be6853b
// deviation: split out as `field_access_expr` is. A `?.` link always leaves
// the chain open.
function optional_field_access_expr(
    ctx: LoweringContext,
    v: View,
    base: int,
    name: root.syntax.Name | root.syntax.Missing,
    span: root.syntax.TextRange,
) -> int throws never {
    let member = if let n: root.syntax.Name = name {
        v.name(n)
    } else {
        "_"
    };
    let id = ctx.alloc_expr(ExprOptionalMemberAccess { base: base, member: member }, span);
    if let n: root.syntax.Name = name {
        ctx.source_map.member_access_member_spans.set(id, v.name_range(n));
    }
    ctx.needs_chain_wrap.delete(base);
    ctx.needs_chain_wrap.set(id, true);
    id
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression_in_chain (the `Upcast` arm) @ d9be6853b
// deviation: split out of `expression_in_chain`. `base.as<T>`.
function upcast_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.UpcastExpr,
    span: root.syntax.TextRange,
) -> int throws never {
    let base = expression_in_chain(ctx, v, node.base);
    let first = if let args: root.syntax.GenericArgs = node.args {
        args.args.at(0)?.item
    } else {
        null
    };
    let target = if (first != null) {
        lower_type(v, ctx.diags, first)
    } else {
        TypeExpr { kind: TypeExprKindMissing {}, span: span }
    };
    let id = ctx.alloc_expr(ExprUpcast { base: base, target: target }, span);
    if (ctx.needs_chain_wrap.delete(base) != null) {
        ctx.needs_chain_wrap.set(id, true);
    }
    id
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression_in_chain (the `QualifiedPath` arm) @ d9be6853b
// deviation: split out of `expression_in_chain`. `(Base as Interface).member`.
function qualified_path_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.QualifiedPath,
    span: root.syntax.TextRange,
) -> int throws never {
    let qself = lower_type(v, ctx.diags, node.base);
    let iface = match (node.iface) {
        let ty: root.syntax.AnyType => lower_type(v, ctx.diags, ty),
        root.syntax.Missing => TypeExpr { kind: TypeExprKindMissing {}, span: span },
    };
    let member = node.member;
    if (member is root.syntax.Missing) {
        return ctx.alloc_expr(ExprMissing {}, span);
    }
    let id = ctx.alloc_expr(
        ExprQualifiedPath { qself: qself, interface_: iface, member: v.name(member) },
        span,
    );
    ctx.source_map.member_access_member_spans.set(id, v.name_range(member));
    id
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression_in_chain (the `EnvAccess` arm) @ d9be6853b
// deviation: split out of `expression_in_chain`. `env.X` is a late-bound
// reference: `baml.env.ref("X")`.
function env_access_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.EnvAccessExpr,
    span: root.syntax.TextRange,
) -> int throws never {
    let var_name = if let n: root.syntax.Name = node.name {
        v.name(n)
    } else {
        "_"
    };
    ctx.env_var_refs.push(EnvVarRef { name: var_name, range: span });
    let callee = ctx.alloc_expr(ExprPath { value: root.base.Path.compiler(["baml", "env", "ref"]) }, span);
    let arg = ctx.alloc_expr(ExprLiteral { value: root.base.LiteralString { value: var_name } }, span);
    ctx.alloc_expr(
        ExprCall { callee: callee, type_args: [], args: [CallArg.positional(arg)] },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression_in_chain (the `Spec` arm) @ d9be6853b
// deviation: split out of `expression_in_chain`. `F@spec`: the companion's
// own name, `F@spec`, as a path.
function spec_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.SpecExpr,
    span: root.syntax.TextRange,
) -> int throws never {
    let base = node.base;
    let selector = node.selector;
    if (!(base is root.syntax.PathExpr) || selector is root.syntax.Missing) {
        ctx.diags.push(LoweringDiagnosticSpecTargetNotFunctionName { span: span });
        return ctx.alloc_expr(ExprMissing {}, span);
    }
    let segments = [v.name(base.head)];
    for (let segment in base.segments) {
        let name = segment.name;
        if (name is root.syntax.Missing) {
            break;
        }
        segments.push(v.name(name));
    }
    let last = segments.pop() ?? baml.sys.panic("a path has a head");
    let suffix = v.text(selector);
    segments.push(`${last}@${suffix}`);
    ctx.alloc_expr(ExprPath { value: root.base.Path.new(segments) }, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::expression_in_chain (the `Map` arm) @ d9be6853b
// deviation: split out of `expression_in_chain`. An entry with no value is
// not one, as in the rowan lowering (the parser reported it).
function map_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.MapLiteral,
    span: root.syntax.TextRange,
) -> int throws never {
    let entries = node.entries.filter_map((entry) -> {
        let key = expression(ctx, v, entry.key);
        if let value: root.syntax.AnyExpr = entry.value {
            MapExprEntry.explicit(key, expression(ctx, v, value))
        } else {
            null
        }
    });
    ctx.alloc_expr(ExprMap { entries: entries }, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::path_expr @ d9be6853b
// `a.b.c`, or `true`/`false`/`null` as the literals they are. A path of
// several segments records each segment's span. A dangling `.` was reported;
// the path ends before it.
function path_expr(ctx: LoweringContext, v: View, node: root.syntax.PathExpr) -> int throws never {
    let span = v.range(node.span);
    let names = [v.name(node.head)];
    let ranges = [v.name_range(node.head)];
    for (let segment in node.segments) {
        let name = segment.name;
        if (name is root.syntax.Missing) {
            break;
        }
        names.push(v.name(name));
        ranges.push(v.name_range(name));
    }
    if (names.length() == 1) {
        match (names[0]) {
            "true" => {
                return ctx.alloc_expr(ExprLiteral { value: root.base.LiteralBool { value: true } }, span);
            },
            "false" => {
                return ctx.alloc_expr(ExprLiteral { value: root.base.LiteralBool { value: false } }, span);
            },
            "null" => {
                return ctx.alloc_expr(ExprNull {}, span);
            },
            _ => {},
        }
    }
    let id = ctx.alloc_expr(ExprPath { value: root.base.Path.new(names) }, span);
    if (names.length() > 1) {
        ctx.source_map.path_segment_spans.set(id, ranges);
    }
    id
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::generic_apply @ d9be6853b
// `base<T>` in value position: a specialized reference to a generic function.
// Anything but a bare path base is reported; a parenthesized path still
// specializes, so a later "must be specialized" error does not pile on.
function generic_apply(
    ctx: LoweringContext,
    v: View,
    base_node: root.syntax.AnyExpr,
    base: int,
    args: root.syntax.GenericArgs,
    span: root.syntax.TextRange,
) -> int throws never {
    let type_args = generic_args(ctx, v, args);
    if (!type_args) {
        return base;
    }
    let parenthesized_base = base_node is root.syntax.ParenExpr;
    let path_base = ctx.exprs[base] is ExprPath;
    if (parenthesized_base || !path_base) {
        ctx.diags.push(LoweringDiagnosticTypeArgsOnNonPathBase { span: span });
        if (!path_base) {
            return base;
        }
    }
    ctx.alloc_expr(ExprGenericApply { base: base, type_args: type_args }, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::generic_args @ d9be6853b
function generic_args(
    ctx: LoweringContext,
    v: View,
    args: root.syntax.GenericArgs,
) -> TypeExpr[] throws never {
    args.args.map((item) -> {
        lower_type(v, ctx.diags, item.item)
    })
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::literal_token @ d9be6853b
// A literal token in expression position.
function literal_token(ctx: LoweringContext, v: View, token: int) -> Expr throws never {
    let text = v.text(token);
    let range = v.token_range(token);
    match (v.tree.tokens.kinds[token]) {
        root.syntax.TokenKind.Integer => {
            ExprLiteral {
                value: root.base.LiteralInt { value: lower_int_literal(text, range, ctx.diags) },
            }
        },
        root.syntax.TokenKind.Bigint => {
            ExprLiteral {
                value: root.base.LiteralBigint { value: lower_bigint_literal(text, range, ctx.diags) },
            }
        },
        root.syntax.TokenKind.Float => {
            ExprLiteral { value: root.base.LiteralFloat { value: normalize_float_literal(text) } }
        },
        root.syntax.TokenKind.True => ExprLiteral { value: root.base.LiteralBool { value: true } },
        root.syntax.TokenKind.False => ExprLiteral { value: root.base.LiteralBool { value: false } },
        root.syntax.TokenKind.Null => ExprNull {},
        let kind => baml.sys.panic(`a literal expression token is a literal, not ${kind}`),
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::string_literal @ d9be6853b
// `"…"`, `r"…"`, `b"…"`, each decoded as the rowan lowering decoded it. The
// removed `#"…"#` syntax was reported by the parser and has no value.
function string_literal(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.StringLit,
) -> int throws never {
    let text = v.text(node.token);
    let span = v.range(node.span);
    let expr: Expr = match (v.tree.tokens.kinds[node.token]) {
        root.syntax.TokenKind.RawString | root.syntax.TokenKind.UnclosedRawString => {
            ExprLiteral {
                value: root.base.LiteralString { value: strip_raw_string_delimiters(text) ?? "" },
            }
        },
        root.syntax.TokenKind.ByteString | root.syntax.TokenKind.UnclosedByteString => {
            let rest = if (text.starts_with("b\"")) {
                text.slice(2, text.length())
            } else {
                null
            };
            let content = if (rest != null && rest.ends_with("\"")) {
                rest.slice(0, rest.length() - 1)
            } else {
                ""
            };
            ExprByteStringLiteral {
                value: root.base.unescape_byte_string_literal(content).to_array(),
            }
        },
        root.syntax.TokenKind.LegacyHashString | root.syntax.TokenKind.UnclosedHashString => {
            ExprMissing {}
        },
        // `String` and `UnclosedString`, the rest of `StringToken`.
        _ => ExprLiteral { value: root.base.LiteralString { value: strip_string_delimiters(text) } },
    };
    ctx.alloc_expr(expr, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::call_expr @ d9be6853b
// Type arguments on the callee are the call's: `foo<T>(x)`, and the
// receiver's on a static method of a generic class, `Box<T>.from(j)`. The
// call owns the type args; the callee is the path alone.
function call_expr(ctx: LoweringContext, v: View, node: root.syntax.CallExpr) -> int throws never {
    let span = v.range(node.span);
    let callee_node = node.callee;
    let type_args: TypeExpr[] = [];
    match (node.callee) {
        let apply: root.syntax.GenericApplyExpr => {
            callee_node = apply.base;
            type_args = generic_args(ctx, v, apply.args);
        },
        _ => {
            let receiver_args = receiver_generic_args(v, node.callee);
            if (receiver_args != null) {
                type_args = generic_args(ctx, v, receiver_args);
            }
        },
    }
    let inner = if (node.callee is root.syntax.GenericApplyExpr) {
        expression_in_chain(ctx, v, callee_node)
    } else {
        callee_without_receiver_args(ctx, v, node.callee)
    };
    let callee = if (node.callee is root.syntax.ParenExpr) {
        ctx.alloc_expr(
            ExprBlock { stmts: [], tail_expr: inner },
            v.range(root.syntax.node_span(node.callee)),
        )
    } else {
        inner
    };
    let (let lowered_args, let label_spans) = call_args(ctx, v, node.args);
    let args = ctx.complete_client_resolve_call(callee, lowered_args, span);
    let id = ctx.alloc_expr(ExprCall { callee: callee, type_args: type_args, args: args }, span);
    ctx.record_call_arg_label_spans(id, label_spans);
    if (ctx.needs_chain_wrap.delete(callee) != null) {
        ctx.needs_chain_wrap.set(id, true);
    }
    id
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::receiver_generic_args @ d9be6853b
// The `<…>` on the receiver of a member callee (`Box<T>.from(j)`): the base
// of a member-access chain that is itself a generic application, not reached
// through an `.as<…>`.
function receiver_generic_args(
    v: View,
    callee: root.syntax.AnyExpr,
) -> root.syntax.GenericArgs? throws never {
    let base = match (callee) {
        let e: root.syntax.FieldAccessExpr => e.base,
        let e: root.syntax.OptionalFieldAccessExpr => e.base,
        _ => {
            return null;
        },
    };
    match (base) {
        let e: root.syntax.GenericApplyExpr => e.args,
        root.syntax.UpcastExpr => null,
        _ => receiver_generic_args(v, base),
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::callee_without_receiver_args @ d9be6853b
// A member callee whose receiver's generic arguments the call consumed: the
// receiver lowers as its bare base, not as a `GenericApply`.
function callee_without_receiver_args(
    ctx: LoweringContext,
    v: View,
    callee: root.syntax.AnyExpr,
) -> int throws never {
    let span = v.range(root.syntax.node_span(callee));
    match (callee) {
        let e: root.syntax.FieldAccessExpr => {
            field_access_expr(ctx, v, callee_without_receiver_args(ctx, v, e.base), e.name, span)
        },
        let e: root.syntax.OptionalFieldAccessExpr => {
            optional_field_access_expr(ctx, v, callee_without_receiver_args(ctx, v, e.base), e.name, span)
        },
        let e: root.syntax.GenericApplyExpr => expression_in_chain(ctx, v, e.base),
        _ => expression_in_chain(ctx, v, callee),
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::catch_expr @ d9be6853b
// `e catch (x) { arms } catch …`: each clause protects everything before it.
function catch_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.CatchExpr,
) -> int throws never {
    let span = v.range(node.span);
    let base = expression(ctx, v, node.body);
    for (let clause_node in node.clauses) {
        let clause_span = v.range(clause_node.span);
        let kind = match (v.tree.tokens.kinds[clause_node.kw]) {
            root.syntax.TokenKind.Catch => CatchClauseKind.Catch,
            root.syntax.TokenKind.CatchAll => CatchClauseKind.CatchAll,
            root.syntax.TokenKind.CatchAllPanics => CatchClauseKind.CatchAllPanics,
            let k => baml.sys.panic(`a catch keyword, not ${k}`),
        };
        let binding = match (clause_node.binding) {
            let n: root.syntax.Name => {
                ctx.alloc_pattern(PatternBind { name: v.name(n), subpat: null }, v.name_range(n))
            },
            root.syntax.Missing => ctx.alloc_pattern(PatternWildcard {}, clause_span),
        };
        let trace_name = clause_node.trace?.name;
        let stack_trace_binding = if let n: root.syntax.Name = trace_name {
            ctx.alloc_pattern(PatternBind { name: v.name(n), subpat: null }, v.name_range(n))
        } else {
            null
        };
        let arms = clause_node.arms.map((arm) -> {
            let arm_span = v.range(arm.span);
            let pat = match (arm.pattern) {
                let p: root.syntax.AnyPattern => pattern(ctx, v, p),
                root.syntax.Missing => ctx.alloc_pattern(PatternWildcard {}, arm_span),
            };
            let body = expr_or_missing(ctx, v, arm.body, arm_span);
            ctx.alloc_catch_arm(CatchArm { pattern: pat, body: body }, arm_span)
        });
        let clause = CatchClause {
            kind: kind,
            binding: binding,
            stack_trace_binding: stack_trace_binding,
            arms: arms,
        };
        base
            = ctx.alloc_expr(
                ExprCatch { base: base, clause: clause },
                root.syntax.TextRange { start: span.start, end: clause_span.end },
            );
    }
    base
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::spawn_expr @ d9be6853b
// `spawn name with m1, m2 { body }` is
// `baml.spawn.__spawn(baml.spawn.Plan.new(body = () -> { body }, name = name).with(m1).with(m2))`.
// No block, no lambda to hang the spawn off: the expression is missing.
function spawn_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.SpawnExpr,
) -> int throws never {
    let span = v.range(node.span);
    let name = if let name_node: root.syntax.AnyExpr = node.name {
        expression(ctx, v, name_node)
    } else {
        null
    };
    let with_exprs: (int, root.syntax.TextRange)[] = [];
    let with_clause = node.with;
    if (with_clause != null) {
        for (let item in with_clause.items) {
            let item_span = v.range(root.syntax.node_span(item.item));
            with_exprs.push((expression(ctx, v, item.item), item_span));
        }
    }
    let block = node.body;
    if (block is root.syntax.Missing) {
        return ctx.alloc_expr(ExprMissing {}, span);
    }
    let block_span = v.range(block.span);
    let body = lambda_body(ctx, v, block);
    let lambda = LambdaDef {
        kind: LambdaKind.Spawn,
        params: [],
        defaults: FunctionDefaults.empty(),
        return_type: null,
        throws_: null,
        body: body,
        span: block_span,
    };
    let body_fn = ctx.alloc_expr(ExprLambda { value: lambda }, block_span);
    let plan_new = ctx.alloc_expr(
        ExprPath { value: root.base.Path.compiler(["baml", "spawn", "Plan", "new"]) },
        span,
    );
    let plan_args = [CallArg.named("body", body_fn)];
    if (name != null) {
        plan_args.push(CallArg.named("name", name));
    }
    let plan = ctx.alloc_expr(ExprCall { callee: plan_new, type_args: [], args: plan_args }, span);
    for (let modifier in with_exprs) {
        let with_member = ctx.alloc_expr(ExprMemberAccess { base: plan, member: "with" }, modifier.1);
        plan
            = ctx.alloc_expr(
                ExprCall {
                    callee: with_member,
                    type_args: [],
                    args: [CallArg.positional(modifier.0)],
                },
                modifier.1,
            );
    }
    let launch = ctx.alloc_expr(ExprPath { value: root.base.Path.compiler(["baml", "spawn", "__spawn"]) }, span);
    ctx.alloc_expr(
        ExprCall { callee: launch, type_args: [], args: [CallArg.positional(plan)] },
        span,
    )
}

// ── Lambdas and parameters ────────────────────────────────────────────────

// port: baml_compiler2_ast/src/lower_tree/body.rs::lambda_expr @ d9be6853b
// The body lowers into this arena; a `test` inside it registers nowhere.
function lambda_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.LambdaExpr,
) -> int throws never {
    let span = v.range(node.span);
    let (let params, let defaults) = lower_params(v, node.params, "lambda", "lambda parameters", ctx.diags, false, ctx.env_var_refs);
    let ret = node.ret;
    let return_type = if (ret != null) {
        lower_type(v, ctx.diags, ret)
    } else {
        null
    };
    let throws_ty = node.throws_clause?.ty;
    let throws_type = if let ty: root.syntax.AnyType = throws_ty {
        lower_type(v, ctx.diags, ty)
    } else {
        null
    };
    let body = if let b: root.syntax.Block = node.body {
        lambda_body(ctx, v, b)
    } else {
        null
    };
    let lambda = LambdaDef {
        kind: LambdaKind.Anonymous,
        params: params,
        defaults: defaults,
        return_type: return_type,
        throws_: throws_type,
        body: body,
        span: span,
    };
    ctx.alloc_expr(ExprLambda { value: lambda }, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::lower_params @ d9be6853b
// A parameter list, with its defaults in their own arena. A parameter with no
// name (reported by the parser) is dropped; its default is still lowered, as
// the rowan lowering did, so the defaults arena reads the same.
function lower_params(
    v: View,
    params: root.syntax.ParamList,
    owner_name: string,
    unsupported_default_context: string,
    diags: LoweringDiagnostic[],
    defaults_allowed: bool,
    env_var_refs: EnvVarRef[],
) -> (Param[], FunctionDefaults) throws never {
    let lowered: Param[] = [];
    // The index of the parameter a default belongs to; null for a dropped one
    // (Rust's `usize::MAX`).
    let defaults: (int?, root.syntax.AnyExpr)[] = [];
    for (let item in params.params) {
        let param = item.item;
        let default_value = param.default?.value;
        let index = lowered.length();
        if let d: root.syntax.AnyExpr = default_value {
            if (!defaults_allowed) {
                diags.push(
                    LoweringDiagnosticUnsupportedParameterDefault {
                        context: unsupported_default_context,
                        span: v.range(root.syntax.node_span(d)),
                    },
                );
            }
            defaults.push(
                (
                    if (param.name is root.syntax.Name) {
                        index
                    } else {
                        null
                    },
                    d,
                ),
            );
        }
        let name = param.name;
        if (name is root.syntax.Missing) {
            continue;
        }
        let param_name = v.name(name);
        let ascribed = param.ascription?.ty;
        let type_expr = if let ty: root.syntax.AnyType = ascribed {
            let te_span = v.range(root.syntax.node_span(ty));
            let expr = lower_type(v, diags, ty);
            check_missing_type(expr, `parameter \`${param_name}\` in \`${owner_name}\``, te_span, diags);
            check_wildcard_type(expr, "a parameter type", te_span, diags);
            TypeExpr { ...expr, span: te_span }
        } else {
            null
        };
        lowered.push(
            Param {
                name: param_name,
                type_expr: type_expr,
                default: null,
                span: v.range(param.span),
                name_span: v.name_range(name),
            },
        );
    }
    let ctx = LoweringContext.new();
    let default_ids = defaults.map((entry) -> {
        (entry.0, expression(ctx, v, entry.1))
    });
    let (let exprs, let source_map, let ctx_diags, let ctx_env_refs) = ctx.finish(null);
    for (let d in ctx_diags) {
        diags.push(d);
    }
    for (let r in ctx_env_refs) {
        env_var_refs.push(r);
    }
    for (let entry in default_ids) {
        let index = entry.0;
        if (index != null && index < lowered.length()) {
            lowered[index].default = entry.1;
        }
    }
    (lowered, FunctionDefaults { exprs: exprs, source_map: source_map })
}

// ── Object literals ───────────────────────────────────────────────────────

// port: baml_compiler2_ast/src/lower_tree/body.rs::object_literal @ d9be6853b
// `Point<T> { x: 1, y, ...rest }`. A recovered shape with no constructor
// name lowers to `Missing`, diagnostic only. Only a name keys a field of a
// constructed object (a string or template key is a map's); the rowan
// lowering read none. Shorthand `{ f }` reads the binding `f`.
function object_literal(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.ObjectLiteral,
) -> int throws never {
    let span = v.range(node.span);
    let path: root.syntax.PathExpr? = null;
    let args: root.syntax.GenericArgs? = null;
    match (node.ctor) {
        let p: root.syntax.PathExpr => {
            path = p;
        },
        let apply: root.syntax.GenericApplyExpr => {
            if let p: root.syntax.PathExpr = apply.base {
                path = p;
            }
            args = apply.args;
        },
        root.syntax.Bogus => {},
    }
    let type_args = if (args != null) {
        generic_args(ctx, v, args)
    } else {
        []
    };
    if (path == null) {
        ctx.diags.push(LoweringDiagnosticMissingObjectConstructor { span: span });
        return ctx.alloc_expr(ExprMissing {}, span);
    }
    let segments = [v.name(path.head)];
    for (let segment in path.segments) {
        let name = segment.name;
        if (name is root.syntax.Missing) {
            break;
        }
        segments.push(v.name(name));
    }
    let type_name = root.base.Path.new(segments);
    let fields: ObjectExprField[] = [];
    let field_name_spans: (int, root.syntax.TextRange)[] = [];
    let spreads: SpreadField[] = [];
    for (let position = 0; position < node.members.length(); position += 1) {
        match (node.members[position]) {
            let field: root.syntax.ObjectField => {
                let lowered = object_field(ctx, v, field);
                if (lowered != null) {
                    field_name_spans.push((lowered.0.value, lowered.1));
                    fields.push(lowered.0);
                }
            },
            let spread: root.syntax.SpreadElement => {
                if let e: root.syntax.AnyExpr = spread.value {
                    spreads.push(SpreadField { expr: expression(ctx, v, e), position: position });
                }
            },
            root.syntax.Bogus => {},
        }
    }
    let object = ctx.alloc_expr(
        ExprObject { type_name: type_name, type_args: type_args, fields: fields, spreads: spreads },
        span,
    );
    // Rust keys the span by `(object, value)`; here by object, then value.
    if (field_name_spans) {
        let spans_by_value: map<int, root.syntax.TextRange> = {};
        for (let entry in field_name_spans) {
            spans_by_value.set(entry.0, entry.1);
        }
        ctx.source_map.object_field_name_spans.set(object, spans_by_value);
    }
    object
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::object_literal (a field member) @ d9be6853b
// deviation: split out of `object_literal`. A named field and its key's
// span, or null for a field that is not one: a string or template key, or no
// value.
function object_field(
    ctx: LoweringContext,
    v: View,
    field: root.syntax.ObjectField,
) -> (ObjectExprField, root.syntax.TextRange)? throws never {
    let key = field.key;
    if (!(key is root.syntax.DottedName)) {
        return null;
    }
    let key_span = v.range(key.span);
    let key_text = dotted_text(v, key.head, key.segments);
    let field_value = field.value;
    if (field_value != null) {
        if let e: root.syntax.AnyExpr = field_value.value {
            return (ObjectExprField.explicit(key_text, expression(ctx, v, e)), key_span);
        }
        return null;
    }
    if (key.segments) {
        return null;
    }
    let binding = ctx.alloc_expr(ExprPath { value: root.base.Path.new([key_text]) }, key_span);
    (ObjectExprField.shorthand(key_text, binding), key_span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::call_args @ d9be6853b
// The arguments of a call, with the span of each label. An argument with no
// value was reported; it is not one.
function call_args(
    ctx: LoweringContext,
    v: View,
    args: root.syntax.ArgList,
) -> (CallArg[], (int, root.syntax.TextRange)[]) throws never {
    let lowered: (CallArg, root.syntax.TextRange?)[] = [];
    for (let item in args.args) {
        let arg = item.item;
        if let value: root.syntax.AnyExpr = arg.value {
            let label = arg.label;
            let expr = expression(ctx, v, value);
            if (label != null) {
                lowered.push(
                    (CallArg { label: v.name(label.name), expr: expr }, v.name_range(label.name)),
                );
            } else {
                lowered.push((CallArg { label: null, expr: expr }, null));
            }
        }
    }
    LoweringContext.finalize_call_args(lowered)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::binary_expr @ d9be6853b
// `instanceof` is removed: reported over its tokens, the expression missing.
function binary_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.BinaryExpr,
) -> int throws never {
    let span = v.range(node.span);
    let lhs = expression(ctx, v, node.lhs);
    let op = match (node.op.op) {
        root.syntax.BinaryOp.Add => BinaryOp.Add,
        root.syntax.BinaryOp.Sub => BinaryOp.Sub,
        root.syntax.BinaryOp.Mul => BinaryOp.Mul,
        root.syntax.BinaryOp.Div => BinaryOp.Div,
        root.syntax.BinaryOp.Mod => BinaryOp.Mod,
        root.syntax.BinaryOp.Eq => BinaryOp.Eq,
        root.syntax.BinaryOp.Ne => BinaryOp.Ne,
        root.syntax.BinaryOp.Lt => BinaryOp.Lt,
        root.syntax.BinaryOp.Le => BinaryOp.Le,
        root.syntax.BinaryOp.Gt => BinaryOp.Gt,
        root.syntax.BinaryOp.Ge => BinaryOp.Ge,
        root.syntax.BinaryOp.And => BinaryOp.And,
        root.syntax.BinaryOp.Or => BinaryOp.Or,
        root.syntax.BinaryOp.BitAnd => BinaryOp.BitAnd,
        root.syntax.BinaryOp.BitOr => BinaryOp.BitOr,
        root.syntax.BinaryOp.BitXor => BinaryOp.BitXor,
        root.syntax.BinaryOp.Shl => BinaryOp.Shl,
        root.syntax.BinaryOp.Shr => BinaryOp.Shr,
        root.syntax.BinaryOp.NullCoalesce => BinaryOp.NullCoalesce,
        root.syntax.BinaryOp.Instanceof => {
            let tokens = root.syntax.binary_op_tokens(node.op.op).length();
            let op_span = v.tree.text_range(
                root.syntax.TokenRange { start: node.op.first, end: node.op.first + tokens },
            );
            ctx.diags.push(LoweringDiagnosticInstanceofRemoved { span: op_span });
            return ctx.alloc_expr(ExprMissing {}, span);
        },
    };
    let rhs = expr_or_missing(ctx, v, node.rhs, span);
    ctx.alloc_expr(ExprBinary { op: op, lhs: lhs, rhs: rhs }, span)
}

// The magnitude of the smallest `int`, `2^62`: one past Rust's `i64::MAX >> 1`.
const INT_MIN_MAGNITUDE: bigint = 4611686018427387904n;

// port: baml_compiler2_ast/src/lower_tree/body.rs::unary_expr @ d9be6853b
// `~x` is `-x - 1`, every node of it synthesized; `--x` is `-(-x)`; `++x` has
// no meaning and the operand stands (as in the rowan lowering). `-<literal>`
// beyond the positive range is one negative literal (`INT_MIN`), never a
// positive intermediate the VM rejects.
function unary_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.UnaryExpr,
) -> int throws never {
    let span = v.range(node.span);
    let op = root.syntax.unary_op_from_kind(v.tree.tokens.kinds[node.op])
        ?? baml.sys.panic("a unary operator token is one of the unary operators");
    // An integer literal written directly under the operator.
    let direct_int_lit: string? = null;
    if let lit: root.syntax.LiteralExpr = node.operand {
        if (v.tree.tokens.kinds[lit.token] == root.syntax.TokenKind.Integer) {
            direct_int_lit = v.text(lit.token);
        }
    }
    let expr = expr_or_missing(ctx, v, node.operand, span);
    match (op) {
        root.syntax.UnaryOp.BitNot => {
            let prev_synth = ctx.synthesizing;
            ctx.synthesizing = true;
            let neg = ctx.alloc_expr(ExprUnary { op: UnaryOp.Neg, expr: expr }, span);
            let one = ctx.alloc_expr(ExprLiteral { value: root.base.LiteralInt { value: 1 } }, span);
            let result = ctx.alloc_expr(ExprBinary { op: BinaryOp.Sub, lhs: neg, rhs: one }, span);
            ctx.synthesizing = prev_synth;
            result
        },
        root.syntax.UnaryOp.Neg => {
            // deviation: Rust negates any magnitude up to `i64::MAX` here; BAML's
            // `int` stops at `-2^62`, so only that one value folds and a larger one
            // stays a negation (its literal is reported too large).
            let validated = if (direct_int_lit != null) {
                validate(direct_int_lit)
            } else {
                null
            };
            if let digits: (int, string) = validated {
                if (digits_value(digits.1, digits.0) == INT_MIN_MAGNITUDE) {
                    return ctx.alloc_expr(
                        ExprLiteral { value: root.base.LiteralInt { value: int.min_value() } },
                        span,
                    );
                }
            }
            ctx.alloc_expr(ExprUnary { op: UnaryOp.Neg, expr: expr }, span)
        },
        root.syntax.UnaryOp.Not => ctx.alloc_expr(ExprUnary { op: UnaryOp.Not, expr: expr }, span),
        root.syntax.UnaryOp.PreDec => {
            let inner = ctx.alloc_expr(ExprUnary { op: UnaryOp.Neg, expr: expr }, span);
            ctx.alloc_expr(ExprUnary { op: UnaryOp.Neg, expr: inner }, span)
        },
        root.syntax.UnaryOp.PreInc => expr,
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::if_expr @ d9be6853b
function if_expr(ctx: LoweringContext, v: View, node: root.syntax.IfExpr) -> int throws never {
    let span = v.range(node.span);
    let condition = expr_or_missing(ctx, v, node.cond, span);
    let then_branch = block_or_missing(ctx, v, node.then_branch, span);
    let else_node = node.else_branch?.body;
    let else_branch = if let body: root.syntax.AnyElse = else_node {
        else_body(ctx, v, body)
    } else {
        null
    };
    ctx.alloc_expr(
        ExprIf { condition: condition, then_branch: then_branch, else_branch: else_branch },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::else_body @ d9be6853b
function else_body(ctx: LoweringContext, v: View, body: root.syntax.AnyElse) -> int throws never {
    match (body) {
        let b: root.syntax.Block => block_expr(ctx, v, b),
        let e: root.syntax.IfExpr => if_expr(ctx, v, e),
        let e: root.syntax.IfLetExpr => if_let_expr(ctx, v, e),
        let b: root.syntax.Bogus => ctx.alloc_expr(ExprMissing {}, v.range(b.span)),
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::if_let_expr @ d9be6853b
function if_let_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.IfLetExpr,
) -> int throws never {
    let span = v.range(node.span);
    warn_const_introducer(ctx, v, node.introducer);
    if let p: root.syntax.AnyPattern = node.pattern {
        check_const_pattern(ctx, v, p, node.introducer);
    }
    let pat = match (node.pattern) {
        let p: root.syntax.AnyPattern => pattern(ctx, v, p),
        root.syntax.Missing => ctx.alloc_pattern(PatternWildcard {}, span),
    };
    let scrutinee = expr_or_missing(ctx, v, node.scrutinee, span);
    let then_branch = block_or_missing(ctx, v, node.then_branch, span);
    let else_node = node.else_branch?.body;
    let else_branch = if let body: root.syntax.AnyElse = else_node {
        else_body(ctx, v, body)
    } else {
        null
    };
    ctx.alloc_expr(
        ExprIfLet {
            pattern: pat,
            scrutinee: scrutinee,
            then_branch: then_branch,
            else_branch: else_branch,
        },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::match_expr @ d9be6853b
// A match with no scrutinee has it nowhere (as in the rowan lowering).
function match_expr(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.MatchExpr,
) -> int throws never {
    let span = v.range(node.span);
    let scrutinee: int? = null;
    let scrutinee_type: int? = null;
    match (node.scrutinee) {
        let paren: root.syntax.MatchParen => {
            if let e: root.syntax.AnyExpr = paren.expr {
                scrutinee = expression(ctx, v, e);
            }
            let ascribed = paren.ascription?.ty;
            if let ty: root.syntax.AnyType = ascribed {
                let ty_span = v.range(root.syntax.node_span(ty));
                scrutinee_type = ctx.alloc_type_annot(lower_type(v, ctx.diags, ty), ty_span);
            }
        },
        let e: root.syntax.AnyExpr => {
            scrutinee = expression(ctx, v, e);
        },
        root.syntax.Missing => {},
    }
    let arms = node.arms.map((arm) -> {
        let arm_span = v.range(arm.span);
        let pat = if let p: root.syntax.AnyPattern = arm.pattern {
            pattern(ctx, v, p)
        } else {
            null
        };
        let cond = arm.guard?.cond;
        let guard = if let c: root.syntax.AnyExpr = cond {
            expression(ctx, v, c)
        } else {
            null
        };
        let body = if let b: root.syntax.AnyExpr = arm.body {
            expression(ctx, v, b)
        } else {
            null
        };
        let lowered = MatchArm {
            pattern: pat ?? ctx.alloc_pattern(PatternWildcard {}, arm_span),
            guard: guard,
            body: body ?? ctx.alloc_expr(ExprMissing {}, arm_span),
        };
        ctx.alloc_match_arm(lowered, arm_span)
    });
    let scrutinee_id = scrutinee ?? ctx.alloc_expr(ExprMissing {}, root.syntax.TextRange.empty(0));
    ctx.alloc_expr(
        ExprMatch { scrutinee: scrutinee_id, scrutinee_type: scrutinee_type, arms: arms },
        span,
    )
}

// ── Patterns ──────────────────────────────────────────────────────────────

// port: baml_compiler2_ast/src/lower_tree/body.rs::pattern @ d9be6853b
// A tuple pattern of types is a tuple type; a union of one is its member; a
// `|` with nothing after it was reported and is no alternative.
function pattern(ctx: LoweringContext, v: View, pat: root.syntax.AnyPattern) -> int throws never {
    let span = v.range(root.syntax.node_span(pat));
    match (pat) {
        let p: root.syntax.BindingPattern => binding_pattern(ctx, v, p),
        let p: root.syntax.WildcardPattern => {
            let introducer = p.introducer;
            if (introducer != null) {
                warn_const_introducer(ctx, v, introducer);
            }
            ctx.alloc_pattern(PatternWildcard {}, span)
        },
        let p: root.syntax.DestructurePattern => destructure_pattern(ctx, v, p),
        let p: root.syntax.TuplePattern => {
            let elements = p.elements.map((element) -> {
                pattern(ctx, v, element.item)
            });
            let tys = elements.filter_map((id) -> {
                pattern_type_expr(ctx, id)
            });
            if (tys.length() == elements.length()) {
                ctx.alloc_pattern(
                    PatternType {
                        value: TypeExpr { kind: TypeExprKindTuple { elements: tys }, span: span },
                    },
                    span,
                )
            } else {
                ctx.alloc_pattern(PatternTuple { value: elements }, span)
            }
        },
        let p: root.syntax.ArrayPattern => array_pattern(ctx, v, p),
        let p: root.syntax.TypePattern => {
            ctx.alloc_pattern(PatternType { value: lower_type(v, ctx.diags, p.ty) }, span)
        },
        let p: root.syntax.ParenPattern => match (p.inner) {
            let inner: root.syntax.AnyPattern => pattern(ctx, v, inner),
            root.syntax.Missing => ctx.alloc_pattern(PatternWildcard {}, span),
        },
        let p: root.syntax.UnionPattern => {
            let parts = [pattern(ctx, v, p.first)];
            for (let arm in p.arms) {
                if let alt: root.syntax.AnyPattern = arm.pattern {
                    parts.push(pattern(ctx, v, alt));
                }
            }
            if (parts.length() == 1) {
                parts[0]
            } else {
                ctx.alloc_pattern(PatternOr { value: parts }, span)
            }
        },
        root.syntax.Bogus => ctx.alloc_pattern(PatternWildcard {}, span),
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::binding_pattern @ d9be6853b
function binding_pattern(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.BindingPattern,
) -> int throws never {
    let span = v.range(node.span);
    let introducer = node.introducer;
    if (introducer != null) {
        warn_const_introducer(ctx, v, introducer);
    }
    let name = v.name(node.name);
    let name_span = v.name_range(node.name);
    if (name == "const") {
        ctx.diags.push(LoweringDiagnosticReservedConstBindingName { span: name_span });
    }
    let sub = node.ascription?.pattern;
    if (introducer != null) {
        if let s: root.syntax.AnyPattern = sub {
            check_const_pattern(ctx, v, s, introducer);
        }
    }
    let subpat = if let s: root.syntax.AnyPattern = sub {
        pattern(ctx, v, s)
    } else {
        null
    };
    let id = ctx.alloc_pattern(PatternBind { name: name, subpat: subpat }, span);
    ctx.source_map.bind_name_spans.set(id, name_span);
    id
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::destructure_pattern @ d9be6853b
// `let Point<T, Item = U> { x, y: let py }`. Shorthand `{ f }` binds `f`.
function destructure_pattern(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.DestructurePattern,
) -> int throws never {
    let span = v.range(node.span);
    let introducer = node.introducer;
    if (introducer != null) {
        warn_const_introducer(ctx, v, introducer);
    }
    if (introducer != null) {
        check_const_pattern(ctx, v, node, introducer);
    }
    let path = node.path;
    let class_path = [v.name(path.head)];
    for (let segment in path.segments) {
        let name = segment.name;
        if (name is root.syntax.Missing) {
            break;
        }
        class_path.push(v.name(name));
    }
    let type_args: TypeExpr[] = [];
    let associated_type_bindings: AssociatedTypeBinding[] = [];
    let args = path.args;
    if (args != null) {
        for (let item in args.args) {
            match (item.item) {
                let binding: root.syntax.AssocTypeBinding => {
                    let ty = lower_type_or_missing(v, ctx.diags, binding.ty);
                    associated_type_bindings.push(
                        AssociatedTypeBinding { name: v.name(binding.name), ty: ty },
                    );
                },
                let ty: root.syntax.AnyType => {
                    type_args.push(lower_type(v, ctx.diags, ty));
                },
            }
        }
    }
    let fields = node.fields.map((item) -> {
        let field = item.item;
        let field_name = v.name(field.name);
        let field_span = v.name_range(field.name);
        let sub = field.sub?.pattern;
        let pat = if let s: root.syntax.AnyPattern = sub {
            pattern(ctx, v, s)
        } else {
            ctx.alloc_pattern(
                PatternBind { name: field_name, subpat: null },
                v.range(field.name.span),
            )
        };
        FieldPat { field: field_name, field_span: field_span, pat: pat }
    });
    ctx.alloc_pattern(
        PatternClass {
            class_: class_path,
            generic_args: type_args,
            associated_type_bindings: associated_type_bindings,
            fields: fields,
        },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::array_pattern @ d9be6853b
// `[a, ..rest, z]: T[]`: the elements before the first rest, the rest, the
// elements after it; a second rest is lowered and dropped.
function array_pattern(
    ctx: LoweringContext,
    v: View,
    node: root.syntax.ArrayPattern,
) -> int throws never {
    let span = v.range(node.span);
    let prefix: int[] = [];
    let rest: ArrayRestPat? = null;
    let suffix: int[] = [];
    for (let item in node.elements) {
        match (item.item) {
            let r: root.syntax.RestPattern => {
                let inner = r.pattern;
                let pat = if (inner != null) {
                    pattern(ctx, v, inner)
                } else {
                    null
                };
                if (rest == null) {
                    rest = ArrayRestPat { pat: pat };
                }
            },
            let p: root.syntax.AnyPattern => {
                let pat = pattern(ctx, v, p);
                if (rest != null) {
                    suffix.push(pat);
                } else {
                    prefix.push(pat);
                }
            },
        }
    }
    let ascribed = node.ascription?.ty;
    let ascription = if let ty: root.syntax.AnyType = ascribed {
        lower_type(v, ctx.diags, ty)
    } else {
        null
    };
    ctx.alloc_pattern(
        PatternArray { prefix: prefix, rest: rest, suffix: suffix, ascription: ascription },
        span,
    )
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::LoweringContext::lower_jump_expr_at @ d9be6853b
// `break`/`continue` in expression position: a block holding the jump.
// deviation: a free function; BAML adds no methods to a class from another file.
function lower_jump_expr_at(
    ctx: LoweringContext,
    jump: Stmt,
    span: root.syntax.TextRange,
) -> int throws never {
    let stmt = ctx.alloc_stmt(jump, span);
    ctx.alloc_expr(ExprBlock { stmts: [stmt], tail_expr: null }, span)
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::check_const_pattern @ d9be6853b
// Under a `const` introducer, every `let` inside the pattern is reported.
function check_const_pattern(
    ctx: LoweringContext,
    v: View,
    pat: root.syntax.AnyPattern,
    introducer: int,
) -> void throws never {
    let kinds = v.tree.tokens.kinds;
    if (kinds[introducer] != root.syntax.TokenKind.Const) {
        return;
    }
    let range = v.range(root.syntax.node_span(pat));
    for (let token = 0; token < kinds.length(); token += 1) {
        let span = v.token_range(token);
        let contained = range.start <= span.start && span.end <= range.end;
        if (contained && kinds[token] == root.syntax.TokenKind.Let) {
            ctx.diags.push(
                LoweringDiagnosticLetInConstDestructure {
                    span: span,
                    const_span: v.token_range(introducer),
                },
            );
        }
    }
}

// port: baml_compiler2_ast/src/lower_tree/body.rs::pattern_type_expr @ d9be6853b
// The type a pattern of types spells: a type pattern, or a union of them.
// deviation: shares the `TypeExpr` where Rust clones it.
function pattern_type_expr(ctx: LoweringContext, pat: int) -> TypeExpr? throws never {
    match (ctx.patterns[pat]) {
        let p: PatternType => p.value,
        let p: PatternOr => {
            let variants = p.value.filter_map((id) -> {
                pattern_type_expr(ctx, id)
            });
            if (variants.length() != p.value.length()) {
                return null;
            }
            TypeExpr {
                kind: TypeExprKindUnion { variants: variants },
                span: ctx.source_map.pattern_span(pat),
            }
        },
        _ => null,
    }
}
