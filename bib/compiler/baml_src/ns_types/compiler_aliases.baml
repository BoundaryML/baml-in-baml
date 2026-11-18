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
