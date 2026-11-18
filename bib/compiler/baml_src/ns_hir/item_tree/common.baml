// port: baml_compiler2_hir/src/item_tree/common.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_tree/common.rs::GenericParam @ d9be6853b
// Re-exported unchanged: a generic parameter carries only a name and its
// bounds (themselves `TypeExpr`s), so there is nothing for a mirror to strip.
type GenericParam = root.ast.GenericParam;

// port: baml_compiler2_hir/src/item_tree/common.rs::SchemaAttrs @ d9be6853b
// The schema metadata every data declaration can carry: what the LLM is told
// about it and the key it serializes under. Lowered and validated by
// `attrs`, the one place raw attributes are read.
class SchemaAttrs {
    // `@description("...")`.
    description: string?,
    // `@alias("...")`: the serialized key, used instead of the declared name.
    alias: string?,

    // port: baml_compiler2_hir/src/item_tree/common.rs::SchemaAttrs::default @ d9be6853b
    function default_() -> SchemaAttrs throws never {
        SchemaAttrs { description: null, alias: null }
    }
}

// port: baml_compiler2_hir/src/item_tree/common.rs::ClassFieldAttrs @ d9be6853b
// The attributes a class field can carry: one independent flag per
// attribute.
class ClassFieldAttrs {
    schema: SchemaAttrs,
    // `@skip`: left out of the schema and never parsed.
    skip: bool,
    // `@stream.done`: while streaming, the field holds its default until its
    // value is complete.
    stream_done: bool,
    // `@stream.must_exist`: the field has no default, so its class has no
    // partial parse until the field is present.
    must_exist: bool,
    // `@json.rename("...")`: the field's JSON key.
    json_rename: string?,
    // `@json.flatten`: the field holds every key no other field took.
    json_flatten: bool,
    // `@json.fallback`: the field holds the whole object, and its class is
    // the member of a union no other member's literals match.
    json_fallback: bool,
    // `@trace.redact`: telemetry records a redaction in place of the value.
    redact: bool,

    // port: baml_compiler2_hir/src/item_tree/common.rs::ClassFieldAttrs::default @ d9be6853b
    function default_() -> ClassFieldAttrs throws never {
        ClassFieldAttrs {
            schema: SchemaAttrs.default_(),
            skip: false,
            stream_done: false,
            must_exist: false,
            json_rename: null,
            json_flatten: false,
            json_fallback: false,
            redact: false,
        }
    }
}

// port: baml_compiler2_hir/src/item_tree/common.rs::EnumVariantAttrs @ d9be6853b
// The attributes an enum variant can carry.
class EnumVariantAttrs {
    schema: SchemaAttrs,
    // `@skip`: left out of the schema and never parsed.
    skip: bool,
    // `@json.rename("...")`: the variant's JSON string.
    json_rename: string?,

    // port: baml_compiler2_hir/src/item_tree/common.rs::EnumVariantAttrs::default @ d9be6853b
    function default_() -> EnumVariantAttrs throws never {
        EnumVariantAttrs { schema: SchemaAttrs.default_(), skip: false, json_rename: null }
    }
}

// port: baml_compiler2_hir/src/item_tree/common.rs::ClassAttrs @ d9be6853b
// The `@@` attributes a class can carry.
class ClassAttrs {
    schema: SchemaAttrs,
    // `@@stream.done`: an instance is never surfaced until it is complete.
    stream_done: bool,
    // `@@json.omit_nulls`: optional fields holding `null` are not written.
    json_omit_nulls: bool,
    // `@@trace.redact`: telemetry redacts every instance of the class.
    redact: bool,

    // port: baml_compiler2_hir/src/item_tree/common.rs::ClassAttrs::default @ d9be6853b
    function default_() -> ClassAttrs throws never {
        ClassAttrs {
            schema: SchemaAttrs.default_(),
            stream_done: false,
            json_omit_nulls: false,
            redact: false,
        }
    }
}

// port: baml_compiler2_hir/src/item_tree/common.rs::EnumAttrs @ d9be6853b
// The `@@` attributes an enum can carry.
class EnumAttrs {
    schema: SchemaAttrs,

    // port: baml_compiler2_hir/src/item_tree/common.rs::EnumAttrs::default @ d9be6853b
    function default_() -> EnumAttrs throws never {
        EnumAttrs { schema: SchemaAttrs.default_() }
    }
}
