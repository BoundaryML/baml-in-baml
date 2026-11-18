// port: baml_type/src/primitive.rs::tests @ d9be6853b

test "primitive aliases roundtrip" {
    for (let primitive in PRIMITIVE_TYPES) {
        assert.equal(primitive_type_from_alias(primitive_type_alias(primitive)), primitive);
    }
    assert.equal(primitive_type_from_alias("void"), null)
}

function definition_path_of(alias: string) -> string[]? throws never {
    let builtin = builtin_type_name_from_alias(alias)
        ?? return null;
    builtin_type_name_builtin_definition_path(builtin)
}

test "builtin type names distinguish definitions from intrinsics" {
    assert.equal(definition_path_of("string"), ["String"]);
    assert.equal(definition_path_of("json"), ["json", "json"]);
    assert.equal(definition_path_of("never"), null);
    assert.equal(
        builtin_type_name_from_builtin_definition_path(["json", "json"]),
        BuiltinTypeNameJson {},
    )
}
