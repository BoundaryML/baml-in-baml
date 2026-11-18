// port: baml_compiler2_hir_ty/src/defaults.rs::tests @ d9be6853b

test "a type binding operand participates in default forward references" {
    let later_params: map<string, bool> = { "later": true };
    let binding_body = root.ast.ExprBody.new();
    let value = binding_body.exprs.push(root.ast.ExprPath { value: root.base.Path.new(["later"]) }) - 1;
    let stmt = (
        binding_body.stmts.push(
            root.ast.StmtTypeBinding { name: "T", operand: value, bounds: [], else_branch: null },
        )
            - 1
    );
    let block = binding_body.exprs.push(root.ast.ExprBlock { stmts: [stmt], tail_expr: null }) - 1;
    assert.equal(default_expr_forward_references(block, binding_body, later_params), ["later"]);
}
