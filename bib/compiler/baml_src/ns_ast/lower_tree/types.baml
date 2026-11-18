// port: baml_compiler2_ast/src/lower_tree/types.rs @ d9be6853b
//
// Type expressions: `AnyType` to `TypeExpr`.

// port: baml_compiler2_ast/src/lower_tree/types.rs::lower_type_or_missing @ d9be6853b
// A type at a position where one is required; `Missing` where the text has
// none, at the point it would have been.
function lower_type_or_missing(
    cx: View,
    diags: LoweringDiagnostic[],
    ty: root.syntax.AnyType | root.syntax.Missing,
) -> TypeExpr throws never {
    match (ty) {
        let missing: root.syntax.Missing => {
            TypeExpr { kind: TypeExprKindMissing {}, span: View.missing_range(missing) }
        },
        let ty: root.syntax.AnyType => lower_type(cx, diags, ty),
    }
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::lower_type @ d9be6853b
function lower_type(
    cx: View,
    diags: LoweringDiagnostic[],
    ty: root.syntax.AnyType,
) -> TypeExpr throws never {
    match (ty) {
        let id: root.syntax.PathType => lower_path(cx, diags, id),
        let id: root.syntax.LiteralType => lower_literal(cx, diags, id),
        // Grouping only: the parens leave no trace.
        let id: root.syntax.ParenType => lower_type_or_missing(cx, diags, id.inner),
        let id: root.syntax.TupleType => {
            let elements = id.elements.map((element) -> {
                lower_type(cx, diags, element.item)
            });
            TypeExpr { kind: TypeExprKindTuple { elements: elements }, span: cx.range(id.span) }
        },
        let id: root.syntax.FunctionType => lower_function(cx, diags, id),
        let id: root.syntax.OptionalType => {
            let span = cx.range(id.span);
            let inner = lower_type(cx, diags, id.inner);
            TypeExpr { kind: TypeExprKindOptional { inner: inner }, span: span }
        },
        let id: root.syntax.ArrayType => {
            let span = cx.range(id.span);
            let inner = lower_type(cx, diags, id.inner);
            TypeExpr { kind: TypeExprKindList { inner: inner }, span: span }
        },
        let id: root.syntax.UnionType => lower_union(cx, diags, id),
        let id: root.syntax.QualifiedPath => lower_qualified(cx, diags, id),
        // The parser reported it; a removed `unreflect(…)` is one too.
        let id: root.syntax.Bogus => {
            TypeExpr { kind: TypeExprKindError {}, span: cx.range(id.span) }
        },
    }
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::lower_path @ d9be6853b
// `a.b.c<Args>`: the dotted name resolves to a primitive, a compiler alias or
// a path, with its generic arguments and associated-type bindings.
function lower_path(
    cx: View,
    diags: LoweringDiagnostic[],
    id: root.syntax.PathType,
) -> TypeExpr throws never {
    let span = cx.range(id.span);
    let name = dotted_text(cx, id.head, id.segments);
    let generic_args: TypeExpr[] = [];
    let bindings: AssociatedTypeBinding[] = [];
    for (let item in id.args?.args ?? []) {
        match (item.item) {
            let binding: root.syntax.AssocTypeBinding => {
                bindings.push(lower_binding(cx, diags, binding));
            },
            // deviation: Rust's `AnyTypeArg::Bogus` (skipped) and `AnyTypeArg::Type(AnyType::Bogus)`
            // (an error type) are one `Bogus` here. The parser only ever makes the second.
            let ty: root.syntax.AnyType => {
                generic_args.push(lower_type(cx, diags, ty));
            },
        }
    }
    lower_from_type_name_with_generic_args(name, generic_args, bindings, span, diags)
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::lower_binding @ d9be6853b
// `Item = T` inside type arguments.
function lower_binding(
    cx: View,
    diags: LoweringDiagnostic[],
    id: root.syntax.AssocTypeBinding,
) -> AssociatedTypeBinding throws never {
    let ty = lower_type_or_missing(cx, diags, id.ty);
    AssociatedTypeBinding { name: cx.name(id.name), ty: ty }
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::dotted_text @ d9be6853b
// `a.b.c` as text; a dangling `.` (reported) ends the name.
function dotted_text(
    cx: View,
    head: root.syntax.Name,
    segments: root.syntax.PathSegment[],
) -> string throws never {
    let text = cx.name(head);
    for (let segment in segments) {
        if let name: root.syntax.Name = segment.name {
            text = `${text}.${cx.name(name)}`;
        } else {
            break;
        }
    }
    text
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::lower_literal @ d9be6853b
function lower_literal(
    cx: View,
    diags: LoweringDiagnostic[],
    id: root.syntax.LiteralType,
) -> TypeExpr throws never {
    let span = cx.range(id.span);
    let negated = id.minus != null;
    let value: root.base.Literal = match (id.value) {
        let scalar: root.syntax.AnyLiteralTypeValueScalar => {
            let text = cx.text(scalar.token);
            let range = cx.token_range(scalar.token);
            match (cx.tree.tokens.kinds[scalar.token]) {
                root.syntax.TokenKind.Integer => {
                    let value = lower_int_literal(text, range, diags);
                    root.base.LiteralInt {
                        value: if (negated) {
                            -value
                        } else {
                            value
                        },
                    }
                },
                root.syntax.TokenKind.Bigint => {
                    let value = lower_bigint_literal(text, range, diags);
                    root.base.LiteralBigint {
                        value: if (negated) {
                            -value
                        } else {
                            value
                        },
                    }
                },
                root.syntax.TokenKind.Float => {
                    let text = normalize_float_literal(text);
                    root.base.LiteralFloat {
                        value: if (negated) {
                            `-${text}`
                        } else {
                            text
                        },
                    }
                },
                root.syntax.TokenKind.True => root.base.LiteralBool { value: true },
                root.syntax.TokenKind.False => root.base.LiteralBool { value: false },
                _ => root.base.LiteralString { value: string_token_value(text) },
            }
        },
        // A template as a literal type: its text between the backticks.
        let backtick: root.syntax.BacktickString => {
            root.base.LiteralString { value: backtick_interior(cx, backtick.span) }
        },
        let bogus: root.syntax.Bogus => {
            return TypeExpr { kind: TypeExprKindError {}, span: cx.range(bogus.span) };
        },
    };
    TypeExpr { kind: TypeExprKindLiteral { value: value }, span: span }
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::string_token_value @ d9be6853b
// The value of a string token: the text inside a closed pair of `"` with
// escapes decoded; otherwise the text after the opening quotes.
function string_token_value(text: string) -> string throws never {
    let trimmed = text.trim();
    if (trimmed.starts_with("\"") && trimmed.ends_with("\"") && trimmed.length() >= 2) {
        root.base.unescape_string_literal(trimmed.slice(1, trimmed.length() - 1))
    } else {
        trim_start_matches(trimmed, "\"")
    }
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::backtick_interior @ d9be6853b
// The text of a template between its opener and closer. Rust takes the node
// id; here its `span`.
function backtick_interior(cx: View, span: root.syntax.TokenRange) -> string throws never {
    trim_end_matches(trim_start_matches(cx.text_of(span), "`"), "`")
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::lower_function @ d9be6853b
function lower_function(
    cx: View,
    diags: LoweringDiagnostic[],
    id: root.syntax.FunctionType,
) -> TypeExpr throws never {
    let span = cx.range(id.span);
    let params = id.params.map((item) -> {
        let param = item.item;
        let named = param.name;
        let name = if (named) {
            cx.name(named.name)
        } else {
            null
        };
        let optional = named?.question != null;
        let ty = lower_type_or_missing(cx, diags, param.ty);
        FunctionTypeParam { name: name, optional: optional, ty: ty }
    });
    let ret = lower_type_or_missing(cx, diags, id.ret);
    let throws_ = match (id.throws_clause?.ty) {
        let ty: root.syntax.AnyType => lower_type(cx, diags, ty),
        _ => null,
    };
    TypeExpr {
        kind: TypeExprKindFunction { params: params, ret: ret, throws_: throws_ },
        span: span,
    }
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::lower_union @ d9be6853b
function lower_union(
    cx: View,
    diags: LoweringDiagnostic[],
    id: root.syntax.UnionType,
) -> TypeExpr throws never {
    let span = cx.range(id.span);
    let first = lower_type(cx, diags, id.first);
    // A `|` with nothing after it was reported; it is not a member.
    let rest = id.arms.filter_map((arm) -> {
        match (arm.ty) {
            let ty: root.syntax.AnyType => lower_type(cx, diags, ty),
            root.syntax.Missing => null,
        }
    });
    TypeExpr { kind: TypeExprKindUnion { variants: [first].concat(rest) }, span: span }
}

// port: baml_compiler2_ast/src/lower_tree/types.rs::lower_qualified @ d9be6853b
// `(Base as Interface).Member`.
function lower_qualified(
    cx: View,
    diags: LoweringDiagnostic[],
    id: root.syntax.QualifiedPath,
) -> TypeExpr throws never {
    let span = cx.range(id.span);
    let member = id.member;
    if (!(member is root.syntax.Name)) {
        // With no member there is no projection; the parser reported it.
        return TypeExpr { kind: TypeExprKindMissing {}, span: span };
    }
    let base = lower_type(cx, diags, id.base);
    let iface = lower_type_or_missing(cx, diags, id.iface);
    TypeExpr {
        kind: TypeExprKindAssociatedTypeProjection {
            base: base,
            interface_: iface,
            member: cx.name(member),
        },
        span: span,
    }
}

// needs foundation: `str::trim_start_matches` with a string pattern.
function trim_start_matches(text: string, pattern: string) -> string throws never {
    let rest = text;
    while (rest.starts_with(pattern)) {
        rest = rest.slice(pattern.length(), rest.length());
    }
    rest
}

// needs foundation: `str::trim_end_matches` with a string pattern.
function trim_end_matches(text: string, pattern: string) -> string throws never {
    let rest = text;
    while (rest.ends_with(pattern)) {
        rest = rest.slice(0, rest.length() - pattern.length());
    }
    rest
}

// needs foundation: baml_base/src/num_lit.rs::normalize_float_literal. A float
// literal's text without its `_` digit separators.
function normalize_float_literal(text: string) -> string throws never {
    text.replace_all("_", "")
}
