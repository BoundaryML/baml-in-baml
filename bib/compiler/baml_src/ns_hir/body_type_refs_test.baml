// port: baml_compiler2_hir/src/body_type_refs.rs::tests @ d9be6853b

// `body.exprs.alloc(e)`: pushes `e` and returns its id.
function body_type_refs_test_alloc_expr(
    body: root.ast.ExprBody,
    e: root.ast.Expr,
) -> int throws never {
    body.exprs.push(e) - 1
}

// `body.stmts.alloc(s)`: pushes `s` and returns its id.
function body_type_refs_test_alloc_stmt(
    body: root.ast.ExprBody,
    s: root.ast.Stmt,
) -> int throws never {
    body.stmts.push(s) - 1
}

// port: baml_compiler2_hir/src/body_type_refs.rs::tests::expression_type_arguments_preserve_order_and_identity @ d9be6853b
test "expression type arguments preserve order and identity" {
    let body = root.ast.ExprBody.new();
    let callee = body_type_refs_test_alloc_expr(body, root.ast.ExprPath { value: root.base.Path.new(["f"]) });
    let int_span = root.syntax.TextRange { start: 10, end: 13 };
    let string_span = root.syntax.TextRange { start: 15, end: 21 };
    let call = body_type_refs_test_alloc_expr(
        body,
        root.ast.ExprCall {
            callee: callee,
            type_args: [
                root.ast.TypeExpr { kind: root.ast.TypeExprKindInt {}, span: int_span },
                root.ast.TypeExpr { kind: root.ast.TypeExprKindString {}, span: string_span },
            ],
            args: [],
        },
    );

    let (let refs, let source_map) = collect_body_type_refs(body);
    let slots = refs.expr_type_args.get(call) ?? baml.sys.panic("call type slots");
    assert.equal(slots.length(), 2);
    assert.equal(source_map.span(slots[0]), int_span);
    assert.equal(source_map.span(slots[1]), string_span);
    assert.is_type<TypeRefKindString>(refs.store.get(refs.raw_id(slots[1])).kind);
}

// port: baml_compiler2_hir/src/body_type_refs.rs::tests::only_type_binding_bounds_are_type_references @ d9be6853b
test "only type binding bounds are type references" {
    let body = root.ast.ExprBody.new();
    let unbounded_operand = body_type_refs_test_alloc_expr(body, root.ast.ExprPath { value: root.base.Path.new(["runtime_type"]) });
    let unbounded = body_type_refs_test_alloc_stmt(
        body,
        root.ast.StmtTypeBinding {
            name: "R",
            operand: unbounded_operand,
            bounds: [],
            else_branch: null,
        },
    );
    let bounded_operand = body_type_refs_test_alloc_expr(body, root.ast.ExprPath { value: root.base.Path.new(["runtime_type"]) });
    let first_span = root.syntax.TextRange { start: 30, end: 31 };
    let second_span = root.syntax.TextRange { start: 34, end: 35 };
    let bound = (name: string, span: root.syntax.TextRange) -> root.ast.TypeExpr {
        root.ast.TypeExpr {
            kind: root.ast.TypeExprKindPath {
                path: root.base.Path.new([name]),
                generic_args: [],
                associated_type_bindings: [],
            },
            span: span,
        }
    };
    let bounded = body_type_refs_test_alloc_stmt(
        body,
        root.ast.StmtTypeBinding {
            name: "S",
            operand: bounded_operand,
            bounds: [bound("A", first_span), bound("B", second_span)],
            else_branch: null,
        },
    );

    let (let refs, let source_map) = collect_body_type_refs(body);
    // An unbounded binding has no type references; its operand is a body
    // expression.
    assert.is_true(!refs.stmt_type_binding_bounds.has(unbounded));
    let slots = refs.stmt_type_binding_bounds.get(bounded) ?? baml.sys.panic("bounded binding type references");
    assert.equal(slots.length(), 2);
    assert.equal(source_map.span(slots[0]), first_span);
    assert.equal(source_map.span(slots[1]), second_span);
}
