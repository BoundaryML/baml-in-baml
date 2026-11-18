// port: baml_compiler2_ast/src/lower_type_expr.rs @ d9be6853b
//
// Type-expression rules shared by every reader: the named-type table
// (`lower_from_type_name_with_generic_args`) and the wildcard checks.
// Types carry no attributes (BEP-075); `@` attributes belong to declarations.

// port: baml_compiler2_ast/src/lower_type_expr.rs::lower_from_type_name_with_generic_args @ d9be6853b
// A named type: a compiler alias (`int`, `map`, `json`, ...), `_`,
// `$rust_type`, or a path. A compiler alias with the wrong number of type
// arguments is reported and recovers to `unknown`.
function lower_from_type_name_with_generic_args(
    name: string,
    generic_args: TypeExpr[],
    associated_type_bindings: AssociatedTypeBinding[],
    span: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> TypeExpr throws never {
    let path = TypeExprKindPath {
        path: root.base.Path.new(name.split(".")),
        generic_args: generic_args,
        associated_type_bindings: associated_type_bindings,
    };
    let alias = compiler_alias_by_spelling(name);
    if (alias == null) {
        let kind: TypeExprKind = match (name) {
            "_" => TypeExprKindInfer {},
            "$rust_type" => TypeExprKindRust {},
            _ => path,
        };
        return TypeExpr { kind: kind, span: span };
    }
    if (generic_args.length() != alias.arity || associated_type_bindings.length() > 0) {
        diags.push(
            LoweringDiagnosticInvalidBuiltinTypeArguments {
                name: name,
                expected: alias.arity,
                got: generic_args.length(),
                associated_bindings: associated_type_bindings.length(),
                span: span,
            },
        );
        // The syntax parsed successfully. Recover without a second, misleading
        // "could not parse type expression" diagnostic.
        return TypeExpr { kind: TypeExprKindUnknown {}, span: span };
    }
    let kind: TypeExprKind = match (alias.target) {
        AliasTarget.Int => TypeExprKindInt {},
        AliasTarget.Bigint => TypeExprKindBigint {},
        AliasTarget.Float => TypeExprKindFloat {},
        AliasTarget.String => TypeExprKindString {},
        AliasTarget.Bool => TypeExprKindBool {},
        AliasTarget.Null => TypeExprKindNull {},
        AliasTarget.Uint8Array => TypeExprKindUint8Array {},
        AliasTarget.Image => TypeExprKindMedia { kind: root.base.MediaKind.Image },
        AliasTarget.Audio => TypeExprKindMedia { kind: root.base.MediaKind.Audio },
        AliasTarget.Video => TypeExprKindMedia { kind: root.base.MediaKind.Video },
        AliasTarget.Pdf => TypeExprKindMedia { kind: root.base.MediaKind.Pdf },
        AliasTarget.Never => TypeExprKindNever {},
        // `void` is the unit type's second spelling: it denotes `null` in every
        // position, so it lowers to the very same node.
        AliasTarget.Void => TypeExprKindNull {},
        AliasTarget.Unknown => TypeExprKindUnknown {},
        AliasTarget.Type => TypeExprKindType {},
        // Arity checked above: exactly a key and a value.
        AliasTarget.Map => TypeExprKindMap { key: generic_args[0], value: generic_args[1] },
        AliasTarget.Json => {
            TypeExprKindPath {
                path: root.base.Path.compiler(
                    alias.definition ?? baml.sys.panic("json has an alias declaration"),
                ),
                generic_args: generic_args,
                associated_type_bindings: associated_type_bindings,
            }
        },
        AliasTarget.Future => path,
        AliasTarget.List => baml.sys.panic("arrays use postfix syntax"),
    };
    TypeExpr { kind: kind, span: span }
}

// port: baml_compiler2_ast/src/lower_type_expr.rs::check_throws_wildcard @ d9be6853b
// Validate `_` placement in a `throws` clause, neutralizing illegal holes.
// `_` is the open-contract marker (`throws AppError | _` or bare `throws _`),
// allowed as a top-level member of the clause and left in place (the TIR
// firewall fills it from the inferred throw set). A `_` nested inside a
// thrown type (`throws Err<_>`) has nothing to infer from; it is reported
// and rewritten to an error sentinel (see `check_wildcard_type`).
function check_throws_wildcard(
    type_expr: TypeExpr,
    span: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> void throws never {
    match (type_expr.kind) {
        // Bare `throws _`: the whole error set is inferred; keep the hole.
        TypeExprKindInfer => {},
        let union: TypeExprKindUnion => {
            for (let v in union.variants) {
                // A top-level `_` member is the open slot (kept); anything deeper is
                // a non-inferable nested hole (rewritten to an error).
                if (!(v.kind is TypeExprKindInfer)) {
                    check_wildcard_type(v, "a `throws` clause", span, diags);
                }
            }
        },
        _ => check_wildcard_type(type_expr, "a `throws` clause", span, diags),
    }
}

// port: baml_compiler2_ast/src/lower_type_expr.rs::check_wildcard_type @ d9be6853b
// Reject and neutralize the `_` wildcard type at a declaration-site type
// position (a signature parameter/return, a field, an alias, a generic
// bound), where there is nothing local to infer a hole from. Every
// occurrence at any depth is reported (`WildcardTypeNotAllowed`) and
// rewritten to `TypeExprKindError`, which lowers to the `Ty::Error` sentinel
// rather than an inference hole. Holes reach type checking only from a `let`
// annotation, a top-level `throws` member, and the expression-context type
// positions, each of which fills or rejects the hole itself.
function check_wildcard_type(
    type_expr: TypeExpr,
    context: string,
    span: root.syntax.TextRange,
    diags: LoweringDiagnostic[],
) -> void throws never {
    match (type_expr.kind) {
        TypeExprKindInfer => {
            diags.push(LoweringDiagnosticWildcardTypeNotAllowed { context: context, span: span });
            // Neutralize: a hole must never survive into TIR type checking.
            type_expr.kind = TypeExprKindError {};
        },
        let optional: TypeExprKindOptional => {
            check_wildcard_type(optional.inner, context, span, diags)
        },
        let list: TypeExprKindList => check_wildcard_type(list.inner, context, span, diags),
        let m: TypeExprKindMap => {
            check_wildcard_type(m.key, context, span, diags);
            check_wildcard_type(m.value, context, span, diags);
        },
        let union: TypeExprKindUnion => {
            for (let v in union.variants) {
                check_wildcard_type(v, context, span, diags);
            }
        },
        let path: TypeExprKindPath => {
            for (let arg in path.generic_args) {
                check_wildcard_type(arg, context, span, diags);
            }
            for (let binding in path.associated_type_bindings) {
                check_wildcard_type(binding.ty, context, span, diags);
            }
        },
        let function_type: TypeExprKindFunction => {
            for (let p in function_type.params) {
                check_wildcard_type(p.ty, context, span, diags);
            }
            check_wildcard_type(function_type.ret, context, span, diags);
            if let throws_clause: TypeExpr = function_type.throws_ {
                check_wildcard_type(throws_clause, context, span, diags);
            }
        },
        let projection: TypeExprKindAssociatedTypeProjection => {
            check_wildcard_type(projection.base, context, span, diags);
            if let iface: TypeExpr = projection.interface_ {
                check_wildcard_type(iface, context, span, diags);
            }
        },
        // Primitives and other leaves cannot contain a wildcard.
        _ => {},
    }
}

// needs foundation: baml_type/src/compiler_aliases.rs, the part the type-name
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

// needs foundation: compiler_aliases::CompilerAlias, the fields read here.
// `definition` is the declaration as the compiler spells it.
class CompilerAlias {
    target: AliasTarget,
    arity: int,
    definition: string[]?,
}

// needs foundation: compiler_aliases::by_spelling over `ALL`'s
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
