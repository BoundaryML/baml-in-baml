// port: baml_base/src/language.rs::tests @ d9be6853b

// port: language.rs::tests::schema_attribute_positions's `names_at`
function attribute_names_at(position: AttributePosition) -> string[] throws never {
    schema_attribute_specs_at(position).map((spec) -> {
        spec.name
    })
}

test "schema attribute lookup and signatures" {
    assert.equal(schema_attribute_spec("alias")?.signature(), "alias(\"name\")");
    assert.equal(schema_attribute_spec("skip")?.signature(), "skip");
    assert.equal(schema_attribute_spec("stream.done")?.signature(), "stream.done");
    assert.is_true(schema_attribute_spec("stream.with_state") == null)
}

test "schema attribute positions" {
    assert.equal(
        attribute_names_at(AttributePosition.ClassField),
        [
            "description",
            "alias",
            "skip",
            "stream.done",
            "stream.must_exist",
            "json.rename",
            "json.flatten",
            "json.fallback",
            "trace.redact",
        ],
    );
    assert.equal(
        attribute_names_at(AttributePosition.EnumVariant),
        ["description", "alias", "skip", "json.rename"],
    );
    assert.equal(
        attribute_names_at(AttributePosition.Class),
        ["description", "alias", "stream.done", "json.omit_nulls", "trace.redact"],
    );
    assert.equal(attribute_names_at(AttributePosition.Enum), ["description", "alias"]);
    assert.equal(attribute_names_at(AttributePosition.Interface), []);
    assert.equal(attribute_names_at(AttributePosition.Function), []);
    assert.equal(attribute_names_at(AttributePosition.InterfaceField), [])
}

test "client config key lookup" {
    assert.equal(
        client_config_key_spec("request_timeout_ms")?.signature,
        "request_timeout_ms <milliseconds>",
    );
    assert.is_true(client_config_key_spec("temperature") == null)
}
