// port: baml_base/src/language.rs @ d9be6853b
//
// The compiler-owned registry of built-in language constructs: the schema
// attributes and the well-known client configuration keys.

// port: language.rs::SchemaAttributeArguments
type SchemaAttributeArguments = SchemaAttributeArgumentsNone | SchemaAttributeArgumentsString;

// port: language.rs::SchemaAttributeArguments::None. A flag attribute.
class SchemaAttributeArgumentsNone {
}

// port: language.rs::SchemaAttributeArguments::String. One string argument;
// `placeholder` names it in a signature.
class SchemaAttributeArgumentsString {
    placeholder: string,
}

// port: language.rs::AttributePosition. Where a schema attribute is written:
// a member position takes `@name` trailing the member, a block position takes
// `@@name` inside the declaration's body.
enum AttributePosition {
    // `@name` trailing a class field.
    ClassField,
    // `@name` trailing an interface field.
    InterfaceField,
    // `@name` trailing an enum variant.
    EnumVariant,
    // `@@name` inside a class body.
    Class,
    // `@@name` inside an enum body.
    Enum,
    // `@@name` inside an interface body.
    Interface,
    // `@@name` on a function, method, or interface method signature.
    Function,
}

// port: language.rs::AttributePosition::sigil. The prefix an attribute is
// written with at `position`.
function attribute_position_sigil(position: AttributePosition) -> string throws never {
    match (position) {
        AttributePosition.ClassField
            | AttributePosition.InterfaceField
            | AttributePosition.EnumVariant =>
        {
            "@"
        },
        AttributePosition.Class
            | AttributePosition.Enum
            | AttributePosition.Interface
            | AttributePosition.Function =>
        {
            "@@"
        },
    }
}

// port: language.rs::AttributePosition::describe. The position as a
// diagnostic reads it, article included.
function attribute_position_describe(position: AttributePosition) -> string throws never {
    match (position) {
        AttributePosition.ClassField => "a class field",
        AttributePosition.InterfaceField => "an interface field",
        AttributePosition.EnumVariant => "an enum variant",
        AttributePosition.Class => "a class",
        AttributePosition.Enum => "an enum",
        AttributePosition.Interface => "an interface",
        AttributePosition.Function => "a function",
    }
}

// port: language.rs::SchemaAttributeSpec. Semantic metadata for a built-in
// schema attribute.
class SchemaAttributeSpec {
    name: string,
    arguments: SchemaAttributeArguments,
    repeatable: bool,
    // The positions the attribute has meaning at. Anywhere else it is an error:
    // an attribute the compiler knows but does not read at a position would
    // otherwise be accepted and silently ignored.
    positions: AttributePosition[],

    // port: language.rs::SchemaAttributeSpec::signature. The attribute without
    // its contextual `@`/`@@` prefix.
    function signature(self) -> string throws never {
        match (self.arguments) {
            SchemaAttributeArgumentsNone => self.name,
            let args: SchemaAttributeArgumentsString => `${self.name}("${args.placeholder}")`,
        }
    }

    // port: language.rs::SchemaAttributeSpec::allows
    function allows(self, position: AttributePosition) -> bool throws never {
        self.positions.includes(position)
    }
}

// port: language.rs::DATA_MEMBERS_AND_BLOCKS. No schema attribute has meaning
// on an interface or its fields (a contract, not a concrete data type: nothing
// is ever parsed or rendered *as* one) or on a function. Those positions exist
// so that writing one there is an error rather than an accepted no-op.
const DATA_MEMBERS_AND_BLOCKS: AttributePosition[] = [
    AttributePosition.ClassField,
    AttributePosition.EnumVariant,
    AttributePosition.Class,
    AttributePosition.Enum,
];

// port: language.rs::DATA_MEMBERS
const DATA_MEMBERS: AttributePosition[] = [AttributePosition.ClassField, AttributePosition.EnumVariant];

// port: language.rs::SCHEMA_ATTRIBUTE_SPECS
const SCHEMA_ATTRIBUTE_SPECS: SchemaAttributeSpec[] = [
    SchemaAttributeSpec {
        name: "description",
        arguments: SchemaAttributeArgumentsString { placeholder: "text" },
        repeatable: false,
        positions: DATA_MEMBERS_AND_BLOCKS,
    },
    SchemaAttributeSpec {
        name: "alias",
        arguments: SchemaAttributeArgumentsString { placeholder: "name" },
        repeatable: false,
        positions: DATA_MEMBERS_AND_BLOCKS,
    },
    SchemaAttributeSpec {
        name: "skip",
        arguments: SchemaAttributeArgumentsNone {},
        repeatable: false,
        positions: DATA_MEMBERS,
    },
    // BEP-075: the streaming attributes are declaration attributes. A field's
    // `@stream.done` holds the field at its default until its value is
    // complete; a class's `@@stream.done` holds the whole object.
    SchemaAttributeSpec {
        name: "stream.done",
        arguments: SchemaAttributeArgumentsNone {},
        repeatable: false,
        positions: [AttributePosition.ClassField, AttributePosition.Class],
    },
    // The field has no default, so its class has no partial parse until the
    // field is present.
    SchemaAttributeSpec {
        name: "stream.must_exist",
        arguments: SchemaAttributeArgumentsNone {},
        repeatable: false,
        positions: [AttributePosition.ClassField],
    },
    // The JSON key of a field or variant, in `baml.json` and generated SDK
    // serialization. `@alias` stays the name a model is shown.
    SchemaAttributeSpec {
        name: "json.rename",
        arguments: SchemaAttributeArgumentsString { placeholder: "key" },
        repeatable: false,
        positions: DATA_MEMBERS,
    },
    // A `map<string, json>` field that holds every key no other field took,
    // and writes them next to the other fields.
    SchemaAttributeSpec {
        name: "json.flatten",
        arguments: SchemaAttributeArgumentsNone {},
        repeatable: false,
        positions: [AttributePosition.ClassField],
    },
    // A `map<string, json>` field that makes its class the member of a union
    // that takes any object no other member's literals match. It holds the
    // whole object, and is all the class writes.
    SchemaAttributeSpec {
        name: "json.fallback",
        arguments: SchemaAttributeArgumentsNone {},
        repeatable: false,
        positions: [AttributePosition.ClassField],
    },
    // The class's optional fields holding `null` are left out when it is
    // written. A `json` field keeps its `null`, which is a value there.
    SchemaAttributeSpec {
        name: "json.omit_nulls",
        arguments: SchemaAttributeArgumentsNone {},
        repeatable: false,
        positions: [AttributePosition.Class],
    },
    // Telemetry records a redaction marker in place of the value: a field's
    // `@trace.redact` withholds that field, a class's `@@trace.redact` every
    // instance of the class whole.
    SchemaAttributeSpec {
        name: "trace.redact",
        arguments: SchemaAttributeArgumentsNone {},
        repeatable: false,
        positions: [AttributePosition.ClassField, AttributePosition.Class],
    },
];

// port: language.rs::schema_attribute_spec
function schema_attribute_spec(name: string) -> SchemaAttributeSpec? throws never {
    SCHEMA_ATTRIBUTE_SPECS.find((spec) -> {
        spec.name == name
    })
}

// port: language.rs::schema_attribute_specs_at. The schema attributes that
// have meaning at `position`, in table order.
function schema_attribute_specs_at(
    position: AttributePosition,
) -> SchemaAttributeSpec[] throws never {
    SCHEMA_ATTRIBUTE_SPECS.filter((spec) -> {
        spec.allows(position)
    })
}

// port: language.rs::ClientConfigKeySpec. Presentation-neutral identity and
// signature for a well-known client configuration key. Provider-specific
// validation remains owned by the client-options/type schema.
class ClientConfigKeySpec {
    name: string,
    signature: string,
}

// port: language.rs::CLIENT_CONFIG_KEY_SPECS
const CLIENT_CONFIG_KEY_SPECS: ClientConfigKeySpec[] = [
    ClientConfigKeySpec { name: "provider", signature: "provider <name>" },
    ClientConfigKeySpec { name: "options", signature: "options { ... }" },
    ClientConfigKeySpec { name: "model", signature: "model <name>" },
    ClientConfigKeySpec { name: "http", signature: "http { ... }" },
    ClientConfigKeySpec {
        name: "request_timeout_ms",
        signature: "request_timeout_ms <milliseconds>",
    },
    ClientConfigKeySpec { name: "retry_policy", signature: "retry_policy <name>" },
];

// port: language.rs::client_config_key_spec
function client_config_key_spec(name: string) -> ClientConfigKeySpec? throws never {
    CLIENT_CONFIG_KEY_SPECS.find((spec) -> {
        spec.name == name
    })
}
