// port: baml_compiler2_hir_ty/src/interfaces.rs::tests @ d9be6853b
//
// `int()` / `string()` are the variant literals; `test_heads::no_aliases()`
// and `test_heads::alias_ctx(&empty)` are `root.types.alias_ctx({})`.

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::qtn @ d9be6853b
// A head in the nameless workspace root (`test_heads::new("user", ..)`).
function qtn(namespace: string[], name: string) -> root.types.DeclName throws never {
    root.types.DeclName { pkg: root.hir_ty.USER_ROOT, namespace: namespace, name: name }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::class @ d9be6853b
function class_(
    namespace: string[],
    name: string,
    args: root.types.Ty[],
) -> root.types.Ty throws never {
    root.types.TyClass { name: qtn(namespace, name), args: args }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::interface @ d9be6853b
function interface_(name: string, args: root.types.Ty[]) -> root.types.Ty throws never {
    root.types.TyInterface { name: qtn([], name), args: args, associated_types: [] }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::param @ d9be6853b
function param(name: string) -> root.types.ParamTy throws never {
    root.types.ParamTy { index: 0, name: name }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::type_var @ d9be6853b
function type_var(name: string) -> root.types.Ty throws never {
    root.types.TyTypeVar { param: param(name) }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::match_ty_pattern_rejects_repeated_type_var_conflict @ d9be6853b
test "match ty pattern rejects repeated type var conflict" {
    let pattern = class_([], "Pair", [type_var("T"), type_var("T")]);
    let good = class_([], "Pair", [root.types.TyInt {}, root.types.TyInt {}]);
    let bad = class_([], "Pair", [root.types.TyInt {}, root.types.TyString {}]);
    let params = [param("T")];
    assert.equal(
        match_ty_patterns([(pattern, good)], params, root.types.alias_ctx({})) != null,
        true,
    );
    assert.equal(match_ty_patterns([(pattern, bad)], params, root.types.alias_ctx({})), null)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::match_ty_pattern_matches_enum_variant_against_enum @ d9be6853b
test "match ty pattern matches enum variant against enum" {
    let side = root.types.TyEnum { name: qtn([], "Side") };
    let side_left = root.types.TyEnumVariant { name: qtn([], "Side"), variant: "Left" };
    let other = root.types.TyEnumVariant { name: qtn([], "Coin"), variant: "Heads" };
    // `Side.Left` matches a `for Side` pattern.
    assert.equal(match_ty_patterns([(side, side_left)], [], root.types.alias_ctx({})) != null, true);
    // A variant of a different enum does not.
    assert.equal(match_ty_patterns([(side, other)], [], root.types.alias_ctx({})), null)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::match_ty_pattern_handles_nested_interface_args @ d9be6853b
test "match ty pattern handles nested interface args" {
    let pattern = interface_("Container", [root.types.TyList { elem: type_var("T") }]);
    let actual = interface_("Container", [root.types.TyList { elem: root.types.TyInt {} }]);
    let bindings = match_ty_patterns([(pattern, actual)], [param("T")], root.types.alias_ctx({}))
        ?? baml.sys.panic("nested list arg should bind T");
    assert.equal(bindings.get(param("T")), root.types.TyInt {})
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::contains_bound_typevar_checks_interface_associated_bindings @ d9be6853b
test "contains bound typevar checks interface associated bindings" {
    let ty = root.types.TyInterface {
        name: qtn([], "Source"),
        args: [],
        associated_types: [root.types.AssociatedType { name: "Item", ty: root.types.TyList { elem: type_var("T") } }],
    };
    assert.equal(root.types.contains_bound_typevar(ty, [param("T")]), true);
    assert.equal(root.types.contains_bound_typevar(ty, [param("U")]), false)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::match_ty_pattern_uses_full_qualified_type_names @ d9be6853b
test "match ty pattern uses full qualified type names" {
    let pattern = class_(["alpha"], "Thing", []);
    let same_short_name = class_(["beta"], "Thing", []);
    // The same short name in different namespaces does not match.
    assert.equal(
        match_ty_patterns([(pattern, same_short_name)], [], root.types.alias_ctx({})),
        null,
    )
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::tests::match_ty_pattern_unions_are_order_insensitive_with_bindings @ d9be6853b
test "match ty pattern unions are order insensitive with bindings" {
    let pattern = root.types.TyUnion { members: [type_var("T"), root.types.TyString {}] };
    let actual = root.types.TyUnion { members: [root.types.TyString {}, root.types.TyInt {}] };
    let bindings = match_ty_patterns([(pattern, actual)], [param("T")], root.types.alias_ctx({}))
        ?? baml.sys.panic("union members should be matched by type, not position");
    assert.equal(bindings.get(param("T")), root.types.TyInt {})
}

// `baml.Concrete` declares `type` for every concrete type; another interface
// declaring it keeps the name, so neither call below is ambiguous (E0121).
test "a type member another interface declares is not ambiguous with baml.Concrete" {
    let source = `
        interface Kind {
            function type() -> string throws never;
        }
        class Leaf { v: int }
        implement Kind for Leaf {
            function type() -> string { "leaf" }
        }
        function bound<K extends Kind & baml.Concrete>() -> string { K.type() }
        function direct() -> string { Leaf.type() }
    `;
    assert.equal(
        root.check({ "a.baml": source }).map((d) -> {
            d.code
        }),
        [],
    );
}
