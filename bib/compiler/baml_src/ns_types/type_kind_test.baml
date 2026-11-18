// port: baml_type/src/type_kind.rs::tests @ d9be6853b
//
// Not ported: `companion_carriers_require_the_exact_builtin_definition`
// (the companion lookups are not ported; see type_kind.baml). The Rust
// test's `kind.class().namespace().is_empty()` holds by construction here.

test "kind names are closed and recognized" {
    for (let kind in TYPE_KINDS) {
        assert.is_true(is_type_kind_class(type_kind_class_name(kind)));
    }
    for (let path in ["reflect.Type", "reflect.class.Field", "reflect.enum.Value"]) {
        assert.is_true(!is_type_kind_class(type_name_from_dotted_path(path)));
    }
}
