// port: baml_compiler2_hir_ty/src/coherence.rs::tests @ d9be6853b
// `orphan_check`'s unit tests.

// port: baml_compiler2_hir_ty/src/coherence.rs::tests::foreign @ d9be6853b
function orphan_test_foreign(name: string) -> root.types.DeclName throws never {
    root.hir_ty.interfaces.pkg_qtn("dep", name)
}

// port: baml_compiler2_hir_ty/src/coherence.rs::tests::local_class @ d9be6853b
function orphan_test_local_class(package: string, name: string) -> root.types.Ty throws never {
    root.types.TyClass { name: root.hir_ty.interfaces.pkg_qtn(package, name), args: [] }
}

// port: baml_compiler2_hir_ty/src/coherence.rs::tests::orphan_local_interface_is_ok @ d9be6853b
test "orphan local interface is ok" {
    let iface = root.hir_ty.interfaces.pkg_qtn("me", "I");
    assert.is_true(
        orphan_check(root.hir_ty.interfaces.test_root("me"), iface, orphan_test_local_class("dep", "C"), []) is OrphanOutcomeOk,
    )
}

// port: baml_compiler2_hir_ty/src/coherence.rs::tests::orphan_foreign_interface_local_for_type_is_ok @ d9be6853b
test "orphan foreign interface local for type is ok" {
    assert.is_true(
        orphan_check(
            root.hir_ty.interfaces.test_root("me"),
            orphan_test_foreign("I"),
            orphan_test_local_class("me", "C"),
            [],
        ) is OrphanOutcomeOk,
    )
}

// port: baml_compiler2_hir_ty/src/coherence.rs::tests::orphan_foreign_interface_no_local_type_is_violation @ d9be6853b
test "orphan foreign interface no local type is violation" {
    assert.is_true(
        orphan_check(
            root.hir_ty.interfaces.test_root("me"),
            orphan_test_foreign("I"),
            orphan_test_local_class("dep", "C"),
            [],
        ) is OrphanOutcomeNoLocalType,
    )
}

// port: baml_compiler2_hir_ty/src/coherence.rs::tests::orphan_uncovered_param_before_local_type_is_violation @ d9be6853b
// `implement<T> dep.I<me.C> for T`: the bare param precedes the first local
// type (RFC-2451's covered rule).
test "orphan uncovered param before local type is violation" {
    assert.is_true(
        orphan_check(
            root.hir_ty.interfaces.test_root("me"),
            orphan_test_foreign("I"),
            root.types.TyTypeVar { param: root.types.ParamTy { index: 0, name: "T" } },
            [orphan_test_local_class("me", "C")],
        ) is OrphanOutcomeUncoveredParam,
    )
}

// port: baml_compiler2_hir_ty/src/coherence.rs::tests::orphan_local_type_in_interface_args_is_ok @ d9be6853b
// `implement dep.I<me.C> for int`: the local type may appear in the
// interface args, not only the for-type.
test "orphan local type in interface args is ok" {
    assert.is_true(
        orphan_check(
            root.hir_ty.interfaces.test_root("me"),
            orphan_test_foreign("I"),
            root.types.TyInt {},
            [orphan_test_local_class("me", "C")],
        ) is OrphanOutcomeOk,
    )
}
