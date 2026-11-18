// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::tests @ d9be6853b

// port: baml_compiler2_hir_ty/src/test_heads.rs::PACKAGES @ d9be6853b
// Every package a test may spell, in the order their roots are created.
const TEST_PACKAGES: string[] = [
    "ai",
    "anthropic",
    "app",
    "argpkg",
    "assert",
    "aws",
    "baml",
    "claude_code",
    "dep",
    "google",
    "ifacepkg",
    "log",
    "me",
    "openai",
    "other",
    "pinpkg",
    "reflect",
    "testing",
    "trace",
    "typesafeai",
    "user",
    "vercel",
];

// port: baml_compiler2_hir_ty/src/test_heads.rs::root @ d9be6853b
// A test package's root id. Reduced: these tests need only distinct ids,
// so a package's id is its position in TEST_PACKAGES (no database).
function test_root(package: string) -> int throws never {
    TEST_PACKAGES.find_index((name) -> {
        name == package
    })
        ?? baml.sys.panic(`test package \`${package}\` is not in TEST_PACKAGES; add it there`)
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::tests::qtn @ d9be6853b
function pkg_qtn(package: string, name: string) -> root.types.DeclName throws never {
    root.types.DeclName { pkg: test_root(package), namespace: [], name: name }
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::tests::collect_ty_packages_covers_head_and_nested_covered_args @ d9be6853b
test "collect ty packages covers head and nested covered args" {
    let ty = root.types.TyClass {
        name: pkg_qtn("user", "Box"),
        args: [root.types.TyEnum { name: pkg_qtn("dep", "Meters") }],
    };
    let out: int[] = [];
    collect_ty_packages(ty, out);
    // The for-type head's package.
    assert.equal(out.includes(test_root("user")), true);
    // The nested covered argument's package.
    assert.equal(out.includes(test_root("dep")), true)
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::tests::collect_interface_packages_covers_head_args_and_pins @ d9be6853b
test "collect interface packages covers head args and pins" {
    let iface = root.types.InterfaceConstraint {
        name: pkg_qtn("ifacepkg", "Conv"),
        generics: [root.types.TyClass { name: pkg_qtn("argpkg", "Meters"), args: [] }],
        associated_types: [
            root.types.AssociatedType {
                name: "Out",
                ty: root.types.TyEnum { name: pkg_qtn("pinpkg", "Unit") },
            },
        ],
    };
    let out: int[] = [];
    collect_interface_packages(iface, out);
    for (let package in ["ifacepkg", "argpkg", "pinpkg"]) {
        assert.equal(out.includes(test_root(package)), true);
    }
}
