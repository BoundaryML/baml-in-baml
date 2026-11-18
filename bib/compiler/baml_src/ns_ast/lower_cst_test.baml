// port: baml_compiler2_ast/src/lower_cst.rs::test_owner_tests @ d9be6853b

// port: lower_cst.rs::test_owner_tests::path_owner_uses_the_same_namespace_identifier_rules_as_hir @ d9be6853b
test "path owner uses the same namespace identifier rules as hir" {
    assert.equal(test_owner_from_path("ns_orders/ns_v2/tests.baml"), "root.orders.v2");
    assert.equal(test_owner_from_path("ns_123/tests.baml"), "root")
}
