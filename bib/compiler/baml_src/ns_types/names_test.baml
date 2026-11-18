// port: baml_type/src/names.rs::alias_tests @ d9be6853b

function baml_qtn(namespace: string[], name: string) -> TypeName throws never {
    type_name_new("baml", namespace, name)
}

test "primitive alias class path roundtrips" {
    for (let p in PRIMITIVE_TYPES) {
        assert.equal(
            primitive_type_from_builtin_class_path(primitive_type_builtin_class_path(p)),
            p,
        );
    }
}

test "from builtin class path rejects unknown" {
    assert.equal(primitive_type_from_builtin_class_path(["Nope"]), null);
    assert.equal(primitive_type_from_builtin_class_path(["media", "Nope"]), null)
}

test "builtin alias collapses primitive classes" {
    assert.equal(type_name_builtin_alias(baml_qtn([], "String")), "string");
    assert.equal(type_name_builtin_alias(baml_qtn([], "Int")), "int");
    assert.equal(type_name_builtin_alias(baml_qtn(["media"], "Image")), "image");
    assert.equal(type_name_builtin_alias(baml_qtn(["media"], "Pdf")), "pdf")
}

test "builtin primitive recognizes companion classes" {
    assert.equal(type_name_builtin_primitive(baml_qtn([], "String")), PrimitiveType.String);
    assert.equal(type_name_builtin_primitive(baml_qtn(["media"], "Image")), PrimitiveType.Image);
    assert.equal(type_name_builtin_primitive(baml_qtn(["json"], "json")), null)
}

test "builtin alias handles json special case" {
    // `json` is the `baml.json.json` type alias, not a PrimitiveType.
    assert.equal(type_name_builtin_alias(baml_qtn(["json"], "json")), "json");
    // A non-aliased `baml.json` type collapses to nothing.
    assert.equal(type_name_builtin_alias(baml_qtn(["json"], "JsonObject")), null)
}

test "builtin alias ignores user and unaliased types" {
    // A user-package `String` is never collapsed.
    assert.equal(type_name_builtin_alias(type_name_new("user", [], "String")), null);
    // A `baml` class without a primitive alias is not collapsed.
    assert.equal(type_name_builtin_alias(baml_qtn([], "SomethingElse")), null)
}
