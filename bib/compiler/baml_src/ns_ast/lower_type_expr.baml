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
    let alias = root.types.compiler_alias_by_spelling(name);
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
        root.types.AliasTarget.Int => TypeExprKindInt {},
        root.types.AliasTarget.Bigint => TypeExprKindBigint {},
        root.types.AliasTarget.Float => TypeExprKindFloat {},
        root.types.AliasTarget.String => TypeExprKindString {},
        root.types.AliasTarget.Bool => TypeExprKindBool {},
        root.types.AliasTarget.Null => TypeExprKindNull {},
        root.types.AliasTarget.Uint8Array => TypeExprKindUint8Array {},
        root.types.AliasTarget.Image => TypeExprKindMedia { kind: root.base.MediaKind.Image },
        root.types.AliasTarget.Audio => TypeExprKindMedia { kind: root.base.MediaKind.Audio },
        root.types.AliasTarget.Video => TypeExprKindMedia { kind: root.base.MediaKind.Video },
        root.types.AliasTarget.Pdf => TypeExprKindMedia { kind: root.base.MediaKind.Pdf },
        root.types.AliasTarget.Never => TypeExprKindNever {},
        // `void` is the unit type's second spelling: it denotes `null` in every
        // position, so it lowers to the very same node.
        root.types.AliasTarget.Void => TypeExprKindNull {},
        root.types.AliasTarget.Unknown => TypeExprKindUnknown {},
        root.types.AliasTarget.Type => TypeExprKindType {},
        // Arity checked above: exactly a key and a value.
        root.types.AliasTarget.Map => {
            TypeExprKindMap { key: generic_args[0], value: generic_args[1] }
        },
        root.types.AliasTarget.Json => {
            TypeExprKindPath {
                path: root.base.Path.compiler(
                    alias.definition ?? baml.sys.panic("json has an alias declaration"),
                ),
                generic_args: generic_args,
                associated_type_bindings: associated_type_bindings,
            }
        },
        root.types.AliasTarget.Future => path,
        root.types.AliasTarget.List => baml.sys.panic("arrays use postfix syntax"),
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
            if let throws_: TypeExpr = function_type.throws_ {
                check_wildcard_type(throws_, context, span, diags);
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
