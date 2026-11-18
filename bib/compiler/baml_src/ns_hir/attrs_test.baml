// port: baml_compiler2_hir/src/attrs.rs::tests @ d9be6853b

// port: attrs.rs::tests::value_for
function value_for(spec: root.base.SchemaAttributeSpec) -> AttributeValue throws never {
    match (spec.arguments) {
        root.base.SchemaAttributeArgumentsNone => AttributeValueFlag {},
        root.base.SchemaAttributeArgumentsString => AttributeValueText { value: "x" },
    }
}

// port: attrs.rs::tests::exercise. Record every attribute the table allows
// at `carrier`'s position.
function exercise(carrier: AttributeCarrier) -> void throws never {
    for (let spec in root.base.schema_attribute_specs_at(carrier.position())) {
        carrier.record(spec, value_for(spec));
    }
}

// The table and the carriers are two spellings of one vocabulary: every
// attribute the table allows at a position has a field on that position's
// carrier, so `record` never reaches its drift arm.
test "every carrier stores what the table allows" {
    exercise(ClassFieldAttrs.default_());
    exercise(EnumVariantAttrs.default_());
    exercise(ClassAttrs.default_());
    exercise(EnumAttrs.default_());
}

// The positions lowered with `reject_attributes` have no carrier, so the
// table must allow nothing there.
test "carrier less positions admit nothing" {
    for (
        let position in [
            root.base.AttributePosition.InterfaceField,
            root.base.AttributePosition.Interface,
            root.base.AttributePosition.Function,
        ]
    ) {
        assert.equal(root.base.schema_attribute_specs_at(position).length(), 0);
    }
}
