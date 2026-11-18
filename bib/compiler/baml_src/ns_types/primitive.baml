// port: baml_type/src/primitive.rs @ d9be6853b
//
// Methods of the enums here are free functions `primitive_type_<method>` /
// `builtin_type_name_<method>` (enums carry no methods).
//
// compiler_aliases.baml keys its registry only by spelling
// (`compiler_alias_by_spelling`), with `AliasTarget::Primitive` flattened
// into one target per primitive. Rust's `by_target(..).display_name()` is
// therefore the spelling match in `primitive_type_alias` /
// `builtin_type_name_alias`, `by_target(..).definition` is the spelling's
// entry, and `by_definition_path` is a search over the closed builtin set.
//
// Not ported: both `Display` impls (they are `alias`) and
// `BuiltinTypeName::target` (it only feeds `by_target`).

// port: baml_type/src/primitive.rs::PrimitiveType @ d9be6853b
enum PrimitiveType {
    Int,
    Bigint,
    Float,
    String,
    Bool,
    Null,
    Uint8Array,
    Image,
    Audio,
    Video,
    Pdf,
}

// port: baml_type/src/primitive.rs::PrimitiveType::ALL @ d9be6853b
const PRIMITIVE_TYPES: PrimitiveType[] = [
    PrimitiveType.Int,
    PrimitiveType.Bigint,
    PrimitiveType.Float,
    PrimitiveType.Bool,
    PrimitiveType.Null,
    PrimitiveType.String,
    PrimitiveType.Uint8Array,
    PrimitiveType.Image,
    PrimitiveType.Audio,
    PrimitiveType.Video,
    PrimitiveType.Pdf,
];

// port: baml_type/src/primitive.rs::PrimitiveType::builtin_class_path @ d9be6853b
// The companion class's path in the `baml` package (`["Int"]`,
// `["media", "Image"]`): the registry's definition without its package
// segment.
function primitive_type_builtin_class_path(primitive: PrimitiveType) -> string[] throws never {
    let spelled = compiler_alias_by_spelling(primitive_type_alias(primitive))?.definition
        ?? baml.sys.panic("primitives have member declarations");
    spelled.slice(1, spelled.length())
}

// port: baml_type/src/primitive.rs::PrimitiveType::from_literal @ d9be6853b
function primitive_type_from_literal(literal: root.base.Literal) -> PrimitiveType throws never {
    match (literal) {
        root.base.LiteralInt => PrimitiveType.Int,
        root.base.LiteralBigint => PrimitiveType.Bigint,
        root.base.LiteralFloat => PrimitiveType.Float,
        root.base.LiteralString => PrimitiveType.String,
        root.base.LiteralBool => PrimitiveType.Bool,
    }
}

// port: baml_type/src/primitive.rs::PrimitiveType::alias @ d9be6853b
// The lowercase primitive/keyword spelling (`string`, `int`, `image`, ...).
// Restructured: the registry's spelling for this target, matched directly.
function primitive_type_alias(primitive: PrimitiveType) -> string throws never {
    match (primitive) {
        PrimitiveType.Int => "int",
        PrimitiveType.Bigint => "bigint",
        PrimitiveType.Float => "float",
        PrimitiveType.String => "string",
        PrimitiveType.Bool => "bool",
        PrimitiveType.Null => "null",
        PrimitiveType.Uint8Array => "uint8array",
        PrimitiveType.Image => "image",
        PrimitiveType.Audio => "audio",
        PrimitiveType.Video => "video",
        PrimitiveType.Pdf => "pdf",
    }
}

// port: the `AliasTarget::Primitive(primitive)` pattern, which
// compiler_aliases.baml flattens into one target per primitive.
function primitive_of_target(target: AliasTarget) -> PrimitiveType? throws never {
    match (target) {
        AliasTarget.Int => PrimitiveType.Int,
        AliasTarget.Bigint => PrimitiveType.Bigint,
        AliasTarget.Float => PrimitiveType.Float,
        AliasTarget.String => PrimitiveType.String,
        AliasTarget.Bool => PrimitiveType.Bool,
        AliasTarget.Null => PrimitiveType.Null,
        AliasTarget.Uint8Array => PrimitiveType.Uint8Array,
        AliasTarget.Image => PrimitiveType.Image,
        AliasTarget.Audio => PrimitiveType.Audio,
        AliasTarget.Video => PrimitiveType.Video,
        AliasTarget.Pdf => PrimitiveType.Pdf,
        _ => null,
    }
}

// port: baml_type/src/primitive.rs::PrimitiveType::from_alias @ d9be6853b
// The semantic primitive a lowercase source spelling names.
function primitive_type_from_alias(alias: string) -> PrimitiveType? throws never {
    let entry = compiler_alias_by_spelling(alias)
        ?? return null;
    primitive_of_target(entry.target)
}

// port: baml_type/src/primitive.rs::PrimitiveType::from_builtin_class_path @ d9be6853b
// Inverse of primitive_type_builtin_class_path: the primitive a class path
// (relative to the `baml` package, e.g. `["media", "Image"]`) is the
// companion class for.
function primitive_type_from_builtin_class_path(path: string[]) -> PrimitiveType? throws never {
    match (builtin_type_name_from_builtin_definition_path(path)) {
        let p: BuiltinTypeNamePrimitive => p.value,
        _ => null,
    }
}

// port: baml_type/src/primitive.rs::BuiltinTypeName @ d9be6853b
// A builtin source-level type name. Primitive values have companion classes
// in the `baml` package; `json` is a stdlib type alias; `void`, `never` and
// `unknown` are compiler intrinsics with no addressable definition.
type BuiltinTypeName = BuiltinTypeNamePrimitive
    | BuiltinTypeNameJson
    | BuiltinTypeNameVoid
    | BuiltinTypeNameNever
    | BuiltinTypeNameUnknown;

class BuiltinTypeNamePrimitive {
    value: PrimitiveType,
}

class BuiltinTypeNameJson {
}

class BuiltinTypeNameVoid {
}

class BuiltinTypeNameNever {
}

class BuiltinTypeNameUnknown {
}

// port: baml_type/src/primitive.rs::BuiltinTypeName::all @ d9be6853b
// Every builtin source-level type name: what completion offers is what the
// resolver accepts.
const BUILTIN_TYPE_NAMES: BuiltinTypeName[] = PRIMITIVE_TYPES
    .map((primitive) -> {
        BuiltinTypeNamePrimitive { value: primitive }
    })
    .concat(
        [
            BuiltinTypeNameJson {},
            BuiltinTypeNameVoid {},
            BuiltinTypeNameNever {},
            BuiltinTypeNameUnknown {},
        ],
    );

// port: baml_type/src/primitive.rs::BuiltinTypeName::from_alias @ d9be6853b
function builtin_type_name_from_alias(alias: string) -> BuiltinTypeName? throws never {
    let entry = compiler_alias_by_spelling(alias)
        ?? return null;
    builtin_type_name_from_target(entry.target)
}

// port: baml_type/src/primitive.rs::BuiltinTypeName::alias @ d9be6853b
// Restructured: the registry's spelling for this target, matched directly.
function builtin_type_name_alias(builtin: BuiltinTypeName) -> string throws never {
    match (builtin) {
        let p: BuiltinTypeNamePrimitive => primitive_type_alias(p.value),
        BuiltinTypeNameJson => "json",
        BuiltinTypeNameVoid => "void",
        BuiltinTypeNameNever => "never",
        BuiltinTypeNameUnknown => "unknown",
    }
}

// port: baml_type/src/primitive.rs::BuiltinTypeName::builtin_definition_path @ d9be6853b
// The path of this type's definition relative to the `baml` package. Compiler
// intrinsics have none: the language-topic registry documents them instead.
function builtin_type_name_builtin_definition_path(
    builtin: BuiltinTypeName,
) -> string[]? throws never {
    let spelled = compiler_alias_by_spelling(builtin_type_name_alias(builtin))?.definition
        ?? return null;
    spelled.slice(1, spelled.length())
}

// port: baml_type/src/primitive.rs::BuiltinTypeName::from_target @ d9be6853b
function builtin_type_name_from_target(target: AliasTarget) -> BuiltinTypeName? throws never {
    let primitive = primitive_of_target(target);
    if (primitive != null) {
        return BuiltinTypeNamePrimitive { value: primitive };
    }
    match (target) {
        AliasTarget.Json => BuiltinTypeNameJson {},
        AliasTarget.Void => BuiltinTypeNameVoid {},
        AliasTarget.Never => BuiltinTypeNameNever {},
        AliasTarget.Unknown => BuiltinTypeNameUnknown {},
        _ => null,
    }
}

// port: baml_type/src/primitive.rs::BuiltinTypeName::from_builtin_definition_path @ d9be6853b
// Restructured: Rust asks `by_definition_path(Baml, path)` and keeps the
// targets `from_target` accepts; every such target is a BuiltinTypeName, all
// defined in `baml`, so searching BUILTIN_TYPE_NAMES answers the same.
function builtin_type_name_from_builtin_definition_path(
    path: string[],
) -> BuiltinTypeName? throws never {
    BUILTIN_TYPE_NAMES.find((builtin) -> {
        builtin_type_name_builtin_definition_path(builtin) == path
    })
}
