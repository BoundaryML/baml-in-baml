// port: baml_type/src/compiler_aliases.rs @ d9be6853b

// port: baml_type/src/compiler_aliases.rs, the part the type-name
// table reads: each named spelling's target, arity and (for `json`) its
// declaration. `AliasTarget::Primitive(PrimitiveType)` is flattened into the
// primitive variants; `List` stays although no named spelling reaches it.
enum AliasTarget {
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
    List,
    Map,
    Future,
    Type,
    Json,
    Void,
    Never,
    Unknown,
}

// port: compiler_aliases::CompilerAlias, the fields read here.
// `definition` is the declaration as the compiler spells it.
class CompilerAlias {
    target: AliasTarget,
    arity: int,
    definition: string[]?,
}

// port: compiler_aliases::by_spelling over `ALL`'s
// `Spelling::Named` entries (the postfix array has no named spelling).
function compiler_alias_by_spelling(spelling: string) -> CompilerAlias? throws never {
    match (spelling) {
        "int" => CompilerAlias { target: AliasTarget.Int, arity: 0, definition: ["baml", "Int"] },
        "bigint" => {
            CompilerAlias { target: AliasTarget.Bigint, arity: 0, definition: ["baml", "Bigint"] }
        },
        "float" => {
            CompilerAlias { target: AliasTarget.Float, arity: 0, definition: ["baml", "Float"] }
        },
        "string" => {
            CompilerAlias { target: AliasTarget.String, arity: 0, definition: ["baml", "String"] }
        },
        "bool" => CompilerAlias { target: AliasTarget.Bool, arity: 0, definition: ["baml", "Bool"] },
        "null" => CompilerAlias { target: AliasTarget.Null, arity: 0, definition: ["baml", "Null"] },
        "uint8array" => {
            CompilerAlias {
                target: AliasTarget.Uint8Array,
                arity: 0,
                definition: ["baml", "Uint8Array"],
            }
        },
        "image" => {
            CompilerAlias {
                target: AliasTarget.Image,
                arity: 0,
                definition: ["baml", "media", "Image"],
            }
        },
        "audio" => {
            CompilerAlias {
                target: AliasTarget.Audio,
                arity: 0,
                definition: ["baml", "media", "Audio"],
            }
        },
        "video" => {
            CompilerAlias {
                target: AliasTarget.Video,
                arity: 0,
                definition: ["baml", "media", "Video"],
            }
        },
        "pdf" => {
            CompilerAlias {
                target: AliasTarget.Pdf,
                arity: 0,
                definition: ["baml", "media", "Pdf"],
            }
        },
        "map" => CompilerAlias { target: AliasTarget.Map, arity: 2, definition: ["baml", "Map"] },
        "baml.future.Future" => {
            CompilerAlias {
                target: AliasTarget.Future,
                arity: 2,
                definition: ["baml", "future", "Future"],
            }
        },
        "reflect.Type" => {
            CompilerAlias { target: AliasTarget.Type, arity: 0, definition: ["reflect", "Type"] }
        },
        "json" => {
            CompilerAlias {
                target: AliasTarget.Json,
                arity: 0,
                definition: ["baml", "json", "json"],
            }
        },
        "void" => CompilerAlias { target: AliasTarget.Void, arity: 0, definition: null },
        "never" => CompilerAlias { target: AliasTarget.Never, arity: 0, definition: null },
        "unknown" => CompilerAlias { target: AliasTarget.Unknown, arity: 0, definition: null },
        _ => null,
    }
}

// port: baml_type/src/compiler_aliases.rs @ d9be6853b
//
// The part of the compiler-alias registry the class lowering reads: lookup by
// carrier declaration, and what a carrier class denotes. Belongs in
// Restructured: the registry above is by
// spelling and drops `Construction`. A `Construction::Builtin` entry is
// exactly one whose target is not `Json`, `Void`, `Never` or `Unknown`, so
// `class_carrier` tests the target. `baml.Array` (spelled by the postfix
// `[]`, absent from the by-spelling table) is added here.

// port: baml_type/src/compiler_aliases.rs::ALL @ d9be6853b
// The entries that have a carrier declaration, by their table spelling.
const CARRIER_SPELLINGS: string[] = [
    "int",
    "bigint",
    "float",
    "string",
    "bool",
    "null",
    "uint8array",
    "image",
    "audio",
    "video",
    "pdf",
    "map",
    "baml.future.Future",
    "reflect.Type",
    "json",
];

// port: baml_type/src/compiler_aliases.rs::by_definition @ d9be6853b
// The entry whose carrier declaration is `name` under `lang`'s installed
// language packages. Keyed on the full definition path, so a user's own
// `class Int` stays nominal.
function compiler_alias_by_definition(
    lang: root.base.LangRoots,
    name: root.types.DeclName,
) -> root.types.CompilerAlias? throws never {
    let array = root.types.CompilerAlias {
        target: root.types.AliasTarget.List,
        arity: 1,
        definition: ["baml", "Array"],
    };
    let entries = CARRIER_SPELLINGS
        .map((spelling) -> {
            root.types.compiler_alias_by_spelling(spelling)
                ?? baml.sys.panic(`no compiler alias spelled ${spelling}`)
        })
        .concat([array]);
    entries.find((entry) -> {
        let definition = entry.definition;
        // port: compiler_aliases.rs::Definition::matches
        if (definition == null) {
            false
        } else {
            let package = root.base.lang_package_from_manifest_name(definition[0]);
            package != null
                && lang.is_(package, name.pkg)
                && name.path_in_package() == definition.slice(1, definition.length())
        }
    })
}

// port: baml_type/src/compiler_aliases.rs::CompilerAlias::class_carrier @ d9be6853b
// The structural type this entry's class declaration denotes when applied
// to `arity` arguments; null to stay nominal.
function compiler_alias_class_carrier(
    alias: root.types.CompilerAlias,
    arity: int,
) -> root.types.AliasTarget? throws never {
    match (alias.target) {
        root.types.AliasTarget.Json
            | root.types.AliasTarget.Void
            | root.types.AliasTarget.Never
            | root.types.AliasTarget.Unknown =>
        {
            null
        },
        _ if arity == alias.arity => alias.target,
        _ => null,
    }
}

// port: baml_type/src/compiler_aliases.rs::CompilerAlias::lower_class @ d9be6853b
// `compiler_alias_class_carrier` in the interned vocabulary: the type the
// carrier's class spelling denotes, or null to stay nominal. Restructured:
// takes the pool the handles index.
function compiler_alias_lower_class(
    pool: root.types.InferPool,
    alias: root.types.CompilerAlias,
    args: int[],
) -> int? throws never {
    let target = compiler_alias_class_carrier(alias, args.length())
        ?? return null;
    let primitive = root.types.primitive_of_target(target);
    if (primitive != null) {
        return pool.from_plain(root.types.from_primitive(primitive));
    }
    match (target) {
        root.types.AliasTarget.List => pool.add(root.types.InferTyList { elem: args[0] }),
        root.types.AliasTarget.Map => {
            pool.add(root.types.InferTyMap { key: args[0], value: args[1] })
        },
        root.types.AliasTarget.Future => {
            pool.add(root.types.InferTyFuture { value: args[0], error: args[1] })
        },
        root.types.AliasTarget.Type => pool.add(root.types.TyType {}),
        _ => null,
    }
}
