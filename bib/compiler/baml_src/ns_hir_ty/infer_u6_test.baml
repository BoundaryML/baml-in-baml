// port: baml_compiler2_hir_ty/src/infer.rs::syntactic_union_tests @ d9be6853b
// Each test interns into a fresh pool (Rust's global `pool()`).

// port: baml_compiler2_hir_ty/src/infer.rs::syntactic_union_tests::singleton_collapses_to_member @ d9be6853b
test "singleton collapses to member" {
    let pool = root.types.InferPool.new();
    let int_ty = pool.add(root.types.TyInt {});
    assert.equal(syntactic_union(pool, [int_ty]), int_ty)
}

// port: baml_compiler2_hir_ty/src/infer.rs::syntactic_union_tests::empty_collapses_to_never @ d9be6853b
test "empty collapses to never" {
    let pool = root.types.InferPool.new();
    assert.equal(syntactic_union(pool, []), pool.add(root.types.TyNever {}))
}

// port: baml_compiler2_hir_ty/src/infer.rs::syntactic_union_tests::never_members_drop @ d9be6853b
test "never members drop" {
    let pool = root.types.InferPool.new();
    let int_ty = pool.add(root.types.TyInt {});
    assert.equal(syntactic_union(pool, [pool.add(root.types.TyNever {}), int_ty]), int_ty)
}

// port: baml_compiler2_hir_ty/src/infer.rs::syntactic_union_tests::nested_unions_flatten_and_dedup @ d9be6853b
// Rust's `union` helper (`Ty::union`) is the `InferTyUnion` literal.
test "nested unions flatten and dedup" {
    let pool = root.types.InferPool.new();
    let int_ty = pool.add(root.types.TyInt {});
    let string_ty = pool.add(root.types.TyString {});
    let nested = pool.add(root.types.InferTyUnion { members: [int_ty, string_ty] });
    let flat = syntactic_union(pool, [nested, int_ty]);
    assert.equal(flat, pool.add(root.types.InferTyUnion { members: [int_ty, string_ty] }))
}
