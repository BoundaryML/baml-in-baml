// port: baml_compiler2_hir_ty/src/lower.rs::compiler_alias_tests @ d9be6853b

// port: baml_compiler2_hir_ty/src/test_heads.rs::lang @ d9be6853b
// The language-root table over the test roots: each language package at its
// own root, after the nameless workspace root (USER_ROOT).
function lang() -> root.base.LangRoots throws never {
    let roots: map<root.base.LangPackage, int> = {};
    for (let i = 0; i < root.base.LANG_PACKAGES.length(); i += 1) {
        roots[root.base.LANG_PACKAGES[i]] = USER_ROOT + 1 + i;
    }
    root.base.LangRoots { roots: roots, by_root: null }
}

// The compile-time head of a carrier definition spelled
// `[package, ...namespace, name]` (Rust's `Definition::decl_name`).
function carrier_decl_name(
    lang_roots: root.base.LangRoots,
    spelled: string[],
) -> root.types.DeclName throws never {
    let package = root.base.lang_package_from_manifest_name(spelled[0])
        ?? baml.sys.panic("a carrier lives in a language package");
    root.types.DeclName {
        pkg: lang_roots.get(package) ?? baml.sys.panic("the test roots install every package"),
        namespace: spelled.slice(1, spelled.length() - 1),
        name: spelled[spelled.length() - 1],
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::compiler_alias_tests::compiler_aliases_do_not_create_nominal_media_classes @ d9be6853b
test "compiler aliases do not create nominal media classes" {
    let lang_roots = lang();
    let pool = root.types.InferPool.new();
    for (let primitive in root.types.PRIMITIVE_TYPES) {
        let alias = root.types.compiler_alias_by_spelling(root.types.primitive_type_alias(primitive))
            ?? baml.sys.panic("every primitive has an alias");
        let name = carrier_decl_name(lang_roots, alias.definition ?? baml.sys.panic("primitives have carriers"));
        let expected = root.types.from_primitive(primitive);
        assert.equal(class_ty_interned(pool, lang_roots, name, []), pool.from_plain(expected));
        assert.equal(
            class_lowering_ty(lang_roots, name, []),
            root.types.widen_ty_to_lowering_ty(expected),
        );
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::compiler_alias_tests::compiler_aliases_preserve_user_defined_names @ d9be6853b
test "compiler aliases preserve user defined names" {
    let lang_roots = lang();
    let pool = root.types.InferPool.new();
    for (let path in ["user.String", "user.Image", "user.Array", "baml.other.Image"]) {
        let wire = root.types.type_name_from_dotted_path(path);
        let package = root.types.package_as_name(wire.pkg);
        // port: test_heads::new, the root named `package`.
        let pkg = if (package == "user") {
            USER_ROOT
        } else {
            lang_roots.get(
                root.base.lang_package_from_manifest_name(package)
                    ?? baml.sys.panic("a test package"),
            )
                ?? 0
        };
        let name = root.types.DeclName { pkg: pkg, namespace: wire.namespace, name: wire.name };
        match (pool.kinds[class_ty_interned(pool, lang_roots, name, [])]) {
            let c: root.types.InferTyClass => assert.equal(c.name, name),
            _ => assert.is_true(false),
        }
        match (class_lowering_ty(lang_roots, name, [])) {
            let c: root.types.LoweringTyClass => assert.equal(c.name, name),
            _ => assert.is_true(false),
        }
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::compiler_alias_tests::compiler_aliases_stay_nominal_without_the_language_root @ d9be6853b
test "compiler aliases stay nominal without the language root" {
    // A carrier spelled in a package that is not the installed `baml` root is
    // an ordinary class: identity is the root, not the name.
    let pool = root.types.InferPool.new();
    let name = carrier_decl_name(lang(), ["baml", "media", "Image"]);
    match (pool.kinds[class_ty_interned(pool, root.base.LangRoots { roots: {}, by_root: null }, name, [])]) {
        let c: root.types.InferTyClass => assert.equal(c.name, name),
        _ => assert.is_true(false),
    }
}
