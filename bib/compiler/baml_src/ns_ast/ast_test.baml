// port: baml_compiler2_ast/src/ast.rs::display_expr_tests @ d9be6853b

// port: Arena::alloc, as the Rust tests' `path` and `int` helpers use it.
// Push `expr` into the body's arena and return its id.
function alloc(body: ExprBody, expr: Expr) -> int throws never {
    body.exprs.push(expr) - 1
}

// port: ast.rs::display_expr_tests::tuples_and_tuple_access_render_as_source @ d9be6853b
test "tuples and tuple access render as source" {
    let body = ExprBody.new();
    let a = alloc(body, ExprPath { value: root.base.Path.new(["a"]) });
    let b = alloc(body, ExprPath { value: root.base.Path.new(["b"]) });
    let pair = alloc(body, ExprTuple { elements: [a, b] });
    let single = alloc(body, ExprTuple { elements: [a] });
    assert.equal(body.display_expr(pair), "(a, b)");
    assert.equal(body.display_expr(single), "(a,)");

    let zero = alloc(body, ExprLiteral { value: root.base.LiteralInt { value: 0 } });
    let one = alloc(body, ExprLiteral { value: root.base.LiteralInt { value: 1 } });
    let first = alloc(body, ExprIndex { base: single, index: zero });
    let nested = alloc(body, ExprIndex { base: first, index: one });
    assert.equal(body.display_expr(nested), "(a,)[0][1]");

    let t = alloc(body, ExprPath { value: root.base.Path.new(["t"]) });
    let i = alloc(body, ExprPath { value: root.base.Path.new(["i"]) });
    let sum = alloc(body, ExprBinary { op: BinaryOp.Add, lhs: i, rhs: one });
    let computed = alloc(body, ExprIndex { base: t, index: sum });
    assert.equal(body.display_expr(computed), "t[i + 1]");
    let optional = alloc(body, ExprOptionalIndex { base: t, index: i });
    assert.equal(body.display_expr(optional), "t?.[i]")
}
