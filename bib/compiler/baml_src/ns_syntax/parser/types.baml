// port: baml_parser/src/types.rs @ d9be6853b
//
// Type expressions: `int`, `map<K, V>`, `T?`, `T[]`, `A | B`, `(a: A) -> R`,
// `(Base as Iface).Item`, literal types. Modifiers and unions are nodes,
// built around the operand they apply to.
//
// Nothing crosses function boundaries. A type is parsed greedily (a function
// type binds looser than `|`), and E0175, the one diagnostic that depends on
// a construct's surroundings, is decided afterwards from the finished tree by
// `report_ambiguous_unions`.
//
// `NUMBER` is the one in lookahead.baml (see the deviation there).

// port: baml_parser/src/types.rs::MEMBER_NAME @ d9be6853b
// Token kinds legal as a `.member` name: names plus the declaration keywords
// a declaration may use as a member name.
const MEMBER_NAME: KindSet = IDENT.union(
    KindSet.of(
        [
            TokenKind.Class,
            TokenKind.Enum,
            TokenKind.Function,
            TokenKind.Implements,
            TokenKind.Implement,
            TokenKind.Extends,
            TokenKind.Requires,
            TokenKind.Interface,
            TokenKind.Client,
        ],
    ),
);

// port: baml_parser/src/types.rs::TYPE_START_PUNCT @ d9be6853b
// What starts a type besides a name, a string or a number.
const TYPE_START_PUNCT: KindSet = KindSet.of([TokenKind.LParen, TokenKind.Less]);

// port: baml_parser/src/types.rs::reject_unmatched_greater @ d9be6853b
// After a type at depth zero, where a `>` closes nothing: each extra one is
// skipped and all of them are reported once, at the first.
function reject_unmatched_greater(p: Parser) -> void throws never {
    let mark = p.cur.mark();
    let extra = 0;
    while (p.cur.at(TokenKind.Greater)) {
        p.cur.skip();
        extra += 1;
    }
    if (extra > 0) {
        let range = p.cur.text_range(p.cur.range_from(mark));
        p.error(`unmatched \`>\` in type expression (found ${extra} extra)`, range);
    }
}

// port: baml_parser/src/types.rs::is_at_type_start @ d9be6853b
// Whether the current token can start a type.
function is_at_type_start(cur: Cursor) -> bool throws never {
    cur.at_ident()
        || cur.at_in(STRING_TOKEN)
        || cur.at_in(NUMBER)
        || cur.at_in(TYPE_START_PUNCT)
        || (cur.at(TokenKind.Minus) && cur.nth_in(1, NUMBER))
}

// port: baml_parser/src/types.rs::type_mark @ d9be6853b
// The start token of a parsed type, for nodes wrapping it.
// deviation: a field shared by every member of a union is not readable
// through the union (E0007), so the span is read per member.
function type_mark(p: Parser, ty: AnyType) -> Mark throws never {
    let span = match (ty) {
        let t: PathType => t.span,
        let t: LiteralType => t.span,
        let t: ParenType => t.span,
        let t: TupleType => t.span,
        let t: FunctionType => t.span,
        let t: OptionalType => t.span,
        let t: ArrayType => t.span,
        let t: UnionType => t.span,
        let t: QualifiedPath => t.span,
        let t: Bogus => t.span,
    };
    p.mark_of(span)
}

// port: baml_parser/src/types.rs::any_type @ d9be6853b
// A type expression; `Missing` when nothing here starts one. The entry point
// from outside this file: once the whole type is built, its ambiguous
// function/union boundaries are reported (E0175).
function any_type(p: Parser) -> AnyType | Missing throws never {
    let ty = type_expr(p);
    if (ty is Missing) {
        return ty;
    }
    report_ambiguous_unions(p, ty);
    ty
}

// port: baml_parser/src/types.rs::type_operand @ d9be6853b
// One union operand with its modifiers, for a position whose own `|` means
// something else (a pattern alternative). A function type's return and
// `throws` unions are still its own, and reported as ambiguous where they are.
function type_operand(p: Parser) -> AnyType | Missing throws never {
    let ty = type_postfix(p);
    if (ty is Missing) {
        return ty;
    }
    report_ambiguous_unions(p, ty);
    ty
}

// port: baml_parser/src/types.rs::type_expr @ d9be6853b
// A type expression: one union operand, or several joined by `|`. Within
// this file every type is parsed through here; `any_type` adds the
// post-parse report.
function type_expr(p: Parser) -> AnyType | Missing throws never {
    let deep = p.enter_nesting("a type");
    if (deep) {
        return deep;
    }
    let result = type_expr_at(p);
    p.leave_nesting();
    result
}

// port: baml_parser/src/types.rs::type_expr_at @ d9be6853b
function type_expr_at(p: Parser) -> AnyType | Missing throws never {
    let first = type_postfix(p);
    if (first is Missing || !p.cur.at(TokenKind.Pipe)) {
        return first;
    }
    let mark = type_mark(p, first);
    let arms: UnionArm[] = [];
    while let pipe: int = p.cur.eat(TokenKind.Pipe) {
        let ty = type_postfix(p);
        arms.push(UnionArm { pipe: pipe, ty: ty });
        if (ty is Missing) {
            // The union ends on its trailing pipe; the member is reported.
            break;
        }
    }
    UnionType { span: p.span_from(mark), first: first, arms: arms }
}

// port: baml_parser/src/types.rs::type_postfix @ d9be6853b
// One union operand with its postfix modifiers: `T`, `T?`, `T[]`, `T[]?`.
function type_postfix(p: Parser) -> AnyType | Missing throws never {
    let primary = type_primary(p);
    if (primary is Missing) {
        return primary;
    }
    let ty: AnyType = primary;
    let mark = type_mark(p, ty);
    while (true) {
        let l = p.cur.eat(TokenKind.LBracket);
        if (l != null) {
            let r = p.expect(TokenKind.RBracket);
            ty = ArrayType { span: p.span_from(mark), inner: ty, l: l, r: r };
            continue;
        }
        let q = p.cur.eat(TokenKind.Question);
        if (q == null) {
            return ty;
        }
        ty = OptionalType { span: p.span_from(mark), inner: ty, q: q };
    }
}

// port: baml_parser/src/types.rs::type_primary @ d9be6853b
function type_primary(p: Parser) -> AnyType | Missing throws never {
    // The removed `unreflect(expr)` still parses as a type atom so it recovers
    // cleanly: E0098 points at it, and the position is `Bogus`.
    if (p.cur.at(TokenKind.Unreflect) && p.cur.nth_is(1, TokenKind.LParen)) {
        return removed_unreflect(p);
    }

    // Function values cannot declare their own generic parameters, so a leading
    // `<...>` on a function type is rejected; the list is skipped and the
    // `(...) -> R` parsed so the rest of the file still parses.
    if (p.cur.at(TokenKind.Less)) {
        p.error_here("a function type cannot declare generic parameters");
        skip_angle_group(p.cur);
        let l = p.cur.eat(TokenKind.LParen);
        if (l != null) {
            return paren_group(p, l);
        }
        return p.missing("function type parameter list");
    }

    let token = p.cur.eat_in(LITERAL_TYPE_TOKEN);
    if (token != null) {
        let kind = p.cur.tokens().kinds[token];
        if (STRING_TOKEN.contains(kind)) {
            string_token_diagnostics(p, token, StringSite.Literal);
        } else if (kind == TokenKind.Float) {
            reject_float_literal_type(p, "", token);
        }
        return LiteralType {
            span: p.span_from(Mark { idx: token }),
            minus: null,
            value: AnyLiteralTypeValueScalar { token: token },
        };
    }
    let open = p.cur.eat(TokenKind.BacktickStart);
    if (open != null) {
        // A literal type is a quoted string or a number; a template is read for
        // its extent and reported.
        p.error(
            "a backtick string is not a type; a literal type is a quoted string or a number",
            p.cur.token_range(open),
        );
        let value = parse_backtick_string(p, open);
        return LiteralType { span: p.span_from(Mark { idx: open }), minus: null, value: value };
    }

    // Negative numeric literal type: `-42`. Floats still error, as the positive
    // case does.
    if (p.cur.at(TokenKind.Minus) && p.cur.nth_in(1, NUMBER)) {
        let minus = p.cur.eat(TokenKind.Minus);
        let number = p.cur.eat_in(NUMBER);
        if (minus != null && number != null) {
            if (p.cur.tokens().kinds[number] == TokenKind.Float) {
                reject_float_literal_type(p, "-", number);
            }
            return LiteralType {
                span: p.span_from(Mark { idx: minus }),
                minus: minus,
                value: AnyLiteralTypeValueScalar { token: number },
            };
        }
    }

    let head = p.cur.eat_in(IDENT);
    if (head != null) {
        return path_type(p, head);
    }
    let l = p.cur.eat(TokenKind.LParen);
    if (l != null) {
        return paren_group(p, l);
    }
    p.missing("type")
}

// port: baml_parser/src/types.rs::reject_float_literal_type @ d9be6853b
// "float literal values are not supported" for the float token `idx`; `sign`
// prefixes the quoted text.
function reject_float_literal_type(p: Parser, sign: string, idx: int) -> void throws never {
    let text = p.cur.text_of(idx);
    let range = p.cur.token_range(idx);
    p.error(`float literal values are not supported: ${sign}${text}`, range);
}

// port: baml_parser/src/types.rs::path_type @ d9be6853b
// `segment<Args>` after the path's first name.
function path_type(p: Parser, head: int) -> PathType throws never {
    let mark = Mark { idx: head };
    let name = p.name(head);
    let segments = path_segments(p, (p: Parser) -> Name | Missing {
        p.expect_name(PATH_SEGMENT, "type name segment after '.'")
    });
    // After a dangling `.` nothing more is read for this path.
    let last = segments.at(segments.length() - 1);
    let complete = last == null || !(last.name is Missing);
    let l = if (complete) {
        p.cur.eat(TokenKind.Less)
    } else {
        null
    };
    let args = if (l != null) {
        parse_type_args(p, l)
    } else {
        null
    };
    PathType { span: p.span_from(mark), head: name, segments: segments, args: args }
}

// port: baml_parser/src/types.rs::<TypeArgs as Parse>::parse @ d9be6853b
// `T, Item = U>` on a type, after its `<`.
function parse_type_args(p: Parser, l: int) -> TypeArgs throws never {
    if (p.cur.at(TokenKind.Greater)) {
        p.unexpected("type");
    }
    let args = p.sep_list(TokenKind.Greater, TokenKind.Comma, type_arg_or_assoc_binding);
    let r = p.expect(TokenKind.Greater);
    TypeArgs { span: p.span_from(Mark { idx: l }), l: l, args: args, r: r }
}

// port: baml_parser/src/types.rs::type_arg_or_assoc_binding @ d9be6853b
// Null (reported) when nothing here starts a type argument.
function type_arg_or_assoc_binding(p: Parser) -> AnyTypeArg? throws never {
    // `Iterator<Item = int>`: the name is the associated type bound.
    if (p.cur.at_ident() && p.cur.nth_is(1, TokenKind.Equals)) {
        let name = p.eat_name(IDENT);
        let eq = if (name != null) {
            p.cur.eat(TokenKind.Equals)
        } else {
            null
        };
        if (name != null && eq != null) {
            let ty = type_expr(p);
            let mark = p.mark_of(name.span);
            return AssocTypeBinding { span: p.span_from(mark), name: name, eq: eq, ty: ty };
        }
    }
    let ty = type_expr(p);
    if (ty is Missing) {
        null
    } else {
        ty
    }
}

// port: baml_parser/src/types.rs::GroupElement @ d9be6853b
// One element of a parenthesized group, before the group's kind is known.
class GroupElement {
    mark: Mark,
    end: int,
    name: FunctionTypeParamName?,
    ty: AnyType | Missing,
    sep: int?,
}

// port: baml_parser/src/types.rs::paren_group @ d9be6853b
// After a `(`: a parenthesized type `(A | B)`, a function type
// `(a: A, B) -> R throws E`, or a qualified projection `(Base as Iface).Item`.
// The group is parsed once and the wrapper is decided by what is actually
// there: `as` after a first unnamed type makes it a projection, `->` after the
// `)` a function type, a single unnamed element a parenthesized type;
// anything else is an error. No lookahead decides anything a later consume
// has to trust.
function paren_group(p: Parser, l: int) -> AnyType throws never {
    let mark = Mark { idx: l };
    // deviation: `attempt` drops nodes on null rather than on `Err(e)`, so the
    // error leaves the closure through a captured local.
    let error: ParseError? = null;
    let ty = p.attempt((p) -> {
        match (paren_group_contents(p, l)) {
            let e: ParseError => {
                error = e;
                null
            },
            let t: AnyType => t,
        }
    });
    if (ty != null) {
        return ty;
    }
    p.bogus_since(mark, error ?? baml.sys.panic("a failed group carries its error"))
}

// port: baml_parser/src/types.rs::paren_group_contents @ d9be6853b
// The group opened by `l` as the node it turns out to be, or the diagnostic
// when it is none of them: its elements were parsed for their own diagnostics
// and are discarded.
function paren_group_contents(p: Parser, l: int) -> AnyType | ParseError throws never {
    let mark = Mark { idx: l };

    let elements: GroupElement[] = [];
    let had_named = false;
    if (!p.cur.at(TokenKind.RParen)) {
        while (true) {
            let element_mark = p.cur.mark();
            let name = function_type_param_name(p);
            let ty = type_expr(p);
            if (!elements && name == null && !(ty is Missing)) {
                let as_kw = p.cur.eat(TokenKind.As);
                if (as_kw != null) {
                    return qualified_projection(p, l, ty, as_kw);
                }
            }
            had_named = had_named || name != null;
            if (name != null) {
                reject_function_type_default(p);
            }
            let end = p.cur.end();
            let sep = p.cur.eat(TokenKind.Comma);
            let more = sep != null && !p.cur.at(TokenKind.RParen) && !p.cur.at_end();
            elements.push(
                GroupElement { mark: element_mark, end: end, name: name, ty: ty, sep: sep },
            );
            if (!more) {
                break;
            }
        }
    }
    recover_to_paren_close(p);
    let r = p.expect(TokenKind.RParen);

    let arrow = p.cur.eat(TokenKind.Arrow);
    if (arrow != null) {
        let params = elements.map((element) -> {
            SepItem {
                item: FunctionTypeParam {
                    span: element.mark.to(element.end),
                    name: element.name,
                    ty: element.ty,
                },
                sep: element.sep,
            }
        });
        // Bare return and `throws` unions are owned by the function. A pipe
        // followed by another function head is reported as ambiguous once the
        // whole type is built, instead of silently choosing this grouping.
        let ret = type_expr(p);
        let kw = p.cur.eat(TokenKind.Throws);
        let clause = if (kw != null) {
            throws_clause(p, kw)
        } else {
            null
        };
        return FunctionType {
            span: p.span_from(mark),
            l: l,
            params: params,
            r: r,
            arrow: arrow,
            ret: ret,
            throws_clause: clause,
        };
    }

    let only = if (elements.length() == 1) {
        elements[0]
    } else {
        null
    };
    if (only != null && only.name == null && only.sep == null) {
        return ParenType { span: p.span_from(mark), l: l, inner: only.ty, r: r };
    }

    if (!had_named && elements) {
        let items = elements.filter_map((element) -> {
            let ty = element.ty;
            if (ty is Missing) {
                null
            } else {
                SepItem { item: ty, sep: element.sep }
            }
        });
        return TupleType { span: p.span_from(mark), l: l, elements: items, r: r };
    }

    // Named parameters are only legal in a function type; a group of several
    // types is neither a type nor a tuple. The element types were parsed for
    // their diagnostics; the group itself is recovered as one `Bogus`.
    let message = if (had_named) {
        "Named parameters in type expression require `->` to form a function type"
    } else {
        "a parenthesized type holds one type; a parameter list needs `->` to form a function type"
    };
    InvalidSyntax { message: message, range: p.cur.error_range() }
}

// port: baml_parser/src/types.rs::qualified_path_expr @ d9be6853b
// `Base as Interface).member` in expression position after its `(`, the
// lookahead having seen the shape: the group is the projection's. The shape
// the lookahead read is read again here with `eat`/`expect`; where the two
// disagree (the lookahead accepts any `as` inside the parens, the type grammar
// stops earlier: `(f(x) as I).m`, `([1] as I).m`) the group is one reported
// `Bogus`, never a wrong node.
function qualified_path_expr(p: Parser, l: int) -> AnyExpr throws never {
    let base = type_expr(p);
    let as_kw = if (base is Missing) {
        null
    } else {
        p.cur.eat(TokenKind.As)
    };
    if (!(base is Missing) && as_kw != null) {
        return qualified_projection(p, l, base, as_kw);
    }
    let what = if (base is Missing) {
        "a type before `as`"
    } else {
        "`as` after the type"
    };
    let error = InvalidSyntax {
        message: `a qualified projection \`(Base as Interface).member\` needs ${what}`,
        range: p.cur.error_range(),
    };
    p.cur.skip_group_interior();
    p.cur.eat(TokenKind.RParen);
    p.bogus_since(Mark { idx: l }, error)
}

// port: baml_parser/src/types.rs::qualified_projection @ d9be6853b
// The rest of `(Base as Interface).Member` once `base` and the `as` are
// consumed. One node serves type position (an associated type) and
// expression position (a qualified item): same spelling, same structure.
function qualified_projection(
    p: Parser,
    l: int,
    base: AnyType,
    as_kw: int,
) -> QualifiedPath throws never {
    let iface = type_expr(p);
    let r = p.expect(TokenKind.RParen);
    let dot = p.expect(TokenKind.Dot);
    let member = p.expect_name(MEMBER_NAME, "projected item name");
    QualifiedPath {
        span: p.span_from(Mark { idx: l }),
        l: l,
        base: base,
        as_kw: as_kw,
        iface: iface,
        r: r,
        dot: dot,
        member: member,
    }
}

// port: baml_parser/src/types.rs::throws_clause @ d9be6853b
// `E` after a function type's `throws`: the operand is part of the type being
// built.
function throws_clause(p: Parser, kw: int) -> ThrowsClause throws never {
    let ty = type_expr(p);
    ThrowsClause { span: p.span_from(Mark { idx: kw }), kw: kw, ty: ty }
}

// port: baml_parser/src/types.rs::<ThrowsClause as Parse>::parse @ d9be6853b
// `E` after a declaration's `throws`: a type expression of its own.
function parse_throws_clause(p: Parser, kw: int) -> ThrowsClause throws never {
    let ty = any_type(p);
    ThrowsClause { span: p.span_from(Mark { idx: kw }), kw: kw, ty: ty }
}

// port: baml_parser/src/types.rs::function_type_param_name @ d9be6853b
// `name:` / `name?:` opening a named function-type parameter, if the next
// tokens have that shape. The shape is read with `eat` after the look, so a
// disagreement is a diagnostic, never a wrong node.
function function_type_param_name(p: Parser) -> FunctionTypeParamName? throws never {
    let named = p.cur.at_in(EXPR_NAME)
        && (
            p.cur.nth_is(1, TokenKind.Colon)
                || (p.cur.nth_is(1, TokenKind.Question) && p.cur.nth_is(2, TokenKind.Colon))
        );
    if (!named) {
        return null;
    }
    reject_reserved_trace_parameter(p);
    let name = p.eat_name(EXPR_NAME)
        ?? return null;
    let question = p.cur.eat(TokenKind.Question);
    let colon = p.cur.eat(TokenKind.Colon) ?? baml.sys.panic("the shape was checked: a colon follows");
    FunctionTypeParamName { name: name, question: question, colon: colon }
}

// port: baml_parser/src/types.rs::reject_function_type_default @ d9be6853b
// A `= default` after a named function-type parameter: consumed and
// rejected; the tokens stay unowned, the expression's own diagnostics stay.
function reject_function_type_default(p: Parser) -> void throws never {
    if (!p.cur.at(TokenKind.Equals)) {
        return;
    }
    p.cur.skip();
    let default_mark = p.cur.mark();
    if (at_expression_start(p.cur)) {
        p.discard((p) -> {
            expr(p, Restrictions.empty());
        });
    }
    let range = p.cur.text_range(p.cur.range_from(default_mark));
    p.error("default expressions are not allowed in function types", range);
}

// port: baml_parser/src/types.rs::recover_to_paren_close @ d9be6853b
// If not at `)`: report the stray token and skip to the balancing `)` (left
// for the caller), stopping at a `}` or an unbalanced `]`.
function recover_to_paren_close(p: Parser) -> void throws never {
    if (p.cur.at(TokenKind.RParen)) {
        return;
    }
    let idx = p.cur.nth(0);
    if (idx != null) {
        p.error(`Unexpected '${p.cur.text_of(idx)}' in type expression`, p.cur.token_range(idx));
    }
    let paren_depth = 1;
    let bracket_depth = 0;
    while let kind: TokenKind = p.cur.kind(0) {
        match (kind) {
            TokenKind.LParen => {
                paren_depth += 1;
            },
            TokenKind.RParen => {
                paren_depth -= 1;
                if (paren_depth == 0) {
                    return;
                }
            },
            TokenKind.LBracket => {
                bracket_depth += 1;
            },
            TokenKind.RBracket => {
                if (bracket_depth == 0) {
                    return;
                }
                bracket_depth -= 1;
            },
            TokenKind.RBrace => {
                return;
            },
            _ => {},
        }
        p.cur.skip();
    }
}

// port: baml_parser/src/types.rs::skip_angle_group @ d9be6853b
// Skip a `<...>` group (a rejected generic parameter list), never past the
// bracket or separator that encloses it. Moves `cur`.
function skip_angle_group(cur: Cursor) -> void throws never {
    let depth = 0;
    while let kind: TokenKind = cur.kind(0) {
        match (kind) {
            TokenKind.Less => {
                depth += 1;
            },
            TokenKind.Greater => {
                depth -= 1;
                cur.skip();
                if (depth == 0) {
                    return;
                }
                continue;
            },
            TokenKind.LParen
                | TokenKind.RParen
                | TokenKind.LBrace
                | TokenKind.RBrace
                | TokenKind.RBracket
                | TokenKind.Comma =>
            {
                return;
            },
            _ => {},
        }
        cur.skip();
    }
}

// port: baml_parser/src/types.rs::removed_unreflect @ d9be6853b
// The removed `unreflect(expr)` type atom: E0098, consumed as a `Bogus`. The
// operand is parsed for its own diagnostics and discarded.
function removed_unreflect(p: Parser) -> Bogus throws never {
    let mark = p.cur.mark();
    let error = RemovedFeature {
        message: "`unreflect` was removed; bind the runtime type first with `let type T = <expr>;` and write `T` here",
        range: p.cur.error_range(),
    };
    p.cur.skip(); // unreflect
    p.cur.skip(); // (
    if (p.cur.at(TokenKind.RParen)) {
        p.error_here("`unreflect` requires an operand");
    } else if (at_expression_start(p.cur)) {
        p.discard((p) -> {
            expr(p, Restrictions.empty());
        });
    }
    if (p.cur.at(TokenKind.RParen)) {
        p.cur.skip();
    } else {
        p.unexpected("')'");
    }
    p.bogus_since(mark, error)
}

// ----- ambiguous function/union boundaries (E0175) ---------------------------------

// The pipes found ambiguous under one owner function type.
// deviation: Rust's `(Id<FunctionType>, Vec<TokenIdx>)` tuple.
class OwnerPipes {
    owner: FunctionType,
    pipes: int[],
}

// port: baml_parser/src/types.rs::report_ambiguous_unions @ d9be6853b
// Report every pipe in `root_ty` that could belong to two owners.
//
// A function type is greedy and binds looser than `|`, so `(A) -> B | C` is
// `(A) -> (B | C)`. When the member after a pipe in a function's return or
// `throws` operand is itself a function type, `(A) -> B | (C) -> D`, the other
// reading is just as complete, and the user is asked to parenthesize one of
// them. A union is an operand when it is a function type's return or `throws`
// type; the function-typed members of an operand are undelimited, so their
// own operands belong to the same outermost function, the *owner*, whose text
// the two groupings are rendered for. Parentheses, type arguments and
// parameter lists start a fresh owner. Only a syntax-complete member counts:
// an incomplete one already has its diagnostic.
function report_ambiguous_unions(p: Parser, root_ty: AnyType) -> void throws never {
    let by_owner: OwnerPipes[] = [];
    collect_ambiguous_pipes(p, root_ty, null, by_owner);
    for (let entry in by_owner) {
        let pipes = entry.pipes.sort_by_key((pipe) -> {
            pipe
        });
        render_ambiguous_unions(p, entry.owner.span, pipes);
    }
}

// port: baml_parser/src/types.rs::collect_ambiguous_pipes @ d9be6853b
// The ambiguous pipes under `ty`, grouped by owner. `owner` is the function
// whose operand territory `ty` is in, if any.
function collect_ambiguous_pipes(
    p: Parser,
    ty: AnyType,
    owner: FunctionType?,
    out: OwnerPipes[],
) -> void throws never {
    match (ty) {
        let t: TupleType => {
            for (let element in t.elements) {
                collect_ambiguous_pipes(p, element.item, null, out);
            }
        },
        LiteralType | Bogus => {},
        let t: PathType => {
            let args = t.args;
            if (args != null) {
                for (let arg in args.args) {
                    match (arg.item) {
                        let binding: AssocTypeBinding => {
                            let bound = binding.ty;
                            if (!(bound is Missing)) {
                                collect_ambiguous_pipes(p, bound, null, out);
                            }
                        },
                        let arg_ty: AnyType => collect_ambiguous_pipes(p, arg_ty, null, out),
                    }
                }
            }
        },
        let t: ParenType => {
            let inner = t.inner;
            if (!(inner is Missing)) {
                collect_ambiguous_pipes(p, inner, null, out);
            }
        },
        let t: QualifiedPath => {
            collect_ambiguous_pipes(p, t.base, null, out);
            let iface = t.iface;
            if (!(iface is Missing)) {
                collect_ambiguous_pipes(p, iface, null, out);
            }
        },
        let t: OptionalType => collect_ambiguous_pipes(p, t.inner, owner, out),
        let t: ArrayType => collect_ambiguous_pipes(p, t.inner, owner, out),
        let t: UnionType => {
            collect_ambiguous_pipes(p, t.first, owner, out);
            for (let arm in t.arms) {
                let arm_ty = arm.ty;
                if (!(arm_ty is Missing)) {
                    collect_ambiguous_pipes(p, arm_ty, owner, out);
                }
            }
        },
        let t: FunctionType => collect_function_pipes(p, t, owner, out),
    }
}

// deviation: the `AnyType::Function` arm of `collect_ambiguous_pipes`, split
// out to keep that match flat.
function collect_function_pipes(
    p: Parser,
    function_ty: FunctionType,
    owner: FunctionType?,
    out: OwnerPipes[],
) -> void throws never {
    for (let param in function_ty.params) {
        let param_ty = param.item.ty;
        if (!(param_ty is Missing)) {
            collect_ambiguous_pipes(p, param_ty, null, out);
        }
    }
    let operand_owner = owner ?? function_ty;
    let ret = function_ty.ret;
    if (!(ret is Missing)) {
        collect_operand_pipes(p, ret, operand_owner, out);
    }
    let throws_ty = function_ty.throws_clause?.ty;
    if (throws_ty != null && !(throws_ty is Missing)) {
        collect_operand_pipes(p, throws_ty, operand_owner, out);
    }
}

// port: baml_parser/src/types.rs::collect_operand_pipes @ d9be6853b
// A function's return or `throws` operand: a pipe followed by a function
// type is ambiguous, and the whole operand is `owner`'s territory.
function collect_operand_pipes(
    p: Parser,
    operand: AnyType,
    owner: FunctionType,
    out: OwnerPipes[],
) -> void throws never {
    if let union: UnionType = operand {
        for (let arm in union.arms) {
            let ty = arm.ty;
            if (!(ty is Missing) && is_function_shaped(ty) && is_complete(p, ty)) {
                // deviation: Rust compares arena ids; two function types never start
                // at the same token, so the start identifies the owner.
                let entry = out.find((candidate) -> {
                    candidate.owner.span.start == owner.span.start
                });
                if (entry != null) {
                    entry.pipes.push(arm.pipe);
                } else {
                    out.push(OwnerPipes { owner: owner, pipes: [arm.pipe] });
                }
            }
        }
    }
    collect_ambiguous_pipes(p, operand, owner, out);
}

// port: baml_parser/src/types.rs::is_function_shaped @ d9be6853b
// Whether `ty` reads as a function type from the outside: one, or one under
// postfix modifiers or whole-type parentheses, which do not settle whom a
// pipe before it belongs to.
function is_function_shaped(ty: AnyType) -> bool throws never {
    let current = ty;
    while (true) {
        match (current) {
            FunctionType => {
                return true;
            },
            let t: OptionalType => {
                current = t.inner;
            },
            let t: ArrayType => {
                current = t.inner;
            },
            let t: ParenType => {
                let inner = t.inner;
                if (inner is Missing) {
                    return false;
                }
                current = inner;
            },
            TupleType | PathType | LiteralType | UnionType | QualifiedPath | Bogus => {
                return false;
            },
        }
    }
}

// port: baml_parser/src/types.rs::is_complete @ d9be6853b
// Whether the tree under `ty` holds no `Missing` and no `Bogus`.
// deviation: Rust walks every node with the generic tree `Visitor`; there is
// no generic walk here, so the type nodes are walked by shape. A backtick
// literal type's template parts are not walked: it is complete when its
// closer is present and no registered `Bogus` lies inside it (a `Missing`
// deep in an interpolated expression is not seen).
function is_complete(p: Parser, ty: AnyType) -> bool throws never {
    match (ty) {
        Bogus => false,
        let t: PathType => path_type_complete(p, t),
        let t: LiteralType => match (t.value) {
            Bogus => false,
            let b: BacktickString => {
                !(b.close is Missing)
                    && !p.out.bogus_spans().some((span) -> {
                        b.span.start <= span.start && span.end <= b.span.end
                    })
            },
            AnyLiteralTypeValueScalar => true,
        },
        let t: ParenType => !(t.r is Missing) && type_slot_complete(p, t.inner),
        let t: TupleType => {
            !(t.r is Missing)
                && t.elements.every((element) -> {
                    is_complete(p, element.item)
                })
        },
        let t: FunctionType => function_type_complete(p, t),
        let t: OptionalType => is_complete(p, t.inner),
        let t: ArrayType => !(t.r is Missing) && is_complete(p, t.inner),
        let t: UnionType => {
            is_complete(p, t.first)
                && t.arms.every((arm) -> {
                    type_slot_complete(p, arm.ty)
                })
        },
        let t: QualifiedPath => {
            is_complete(p, t.base)
                && type_slot_complete(p, t.iface)
                && !(t.r is Missing)
                && !(t.dot is Missing)
                && !(t.member is Missing)
        },
    }
}

// port: baml_parser/src/types.rs::render_ambiguous_unions @ d9be6853b
// E0175 for each of `pipes`, with two explicit groupings of the owner
// function type spanning `span`.
function render_ambiguous_unions(p: Parser, span: TokenRange, pipes: int[]) -> void throws never {
    let cur = p.cur;
    let range = cur.sig_range(span);
    let start = range[0];
    let sig: SigToken[] = [];
    for (let i = start; i < range[1]; i += 1) {
        let idx = cur.sig(i) ?? baml.sys.panic("`span` is consumed tokens");
        let previous = if (i > start) {
            cur.sig(i - 1)
        } else {
            null
        };
        sig.push(
            SigToken {
                kind: cur.kind_at_sig(i) ?? baml.sys.panic("consumed token"),
                text: cur.text_of(idx),
                space_before: previous != null && previous + 1 != idx,
            },
        );
    }
    let pipe_positions = pipes.map((pipe) -> {
        cur.sig_index(pipe) - start
    });
    let found = groupings(sig, pipe_positions);
    for (let k = 0; k < pipes.length(); k += 1) {
        p.out.report(AmbiguousUnion { range: cur.token_range(pipes[k]), groupings: found[k] ?? [] });
    }
}

// ----- the shape walk behind `is_complete` (see the deviation there) ---------------

// A `Result<AnyType, Missing>` slot: filled, and complete.
function type_slot_complete(p: Parser, slot: AnyType | Missing) -> bool throws never {
    !(slot is Missing) && is_complete(p, slot)
}

function path_type_complete(p: Parser, t: PathType) -> bool throws never {
    if (
        t.segments.some((segment) -> {
            segment.name is Missing
        })
    ) {
        return false;
    }
    let args = t.args;
    if (args == null) {
        return true;
    }
    !(args.r is Missing)
        && args.args.every((arg) -> {
            match (arg.item) {
                let binding: AssocTypeBinding => type_slot_complete(p, binding.ty),
                let arg_ty: AnyType => is_complete(p, arg_ty),
            }
        })
}

function function_type_complete(p: Parser, t: FunctionType) -> bool throws never {
    let throws_ty = t.throws_clause?.ty;
    !(t.r is Missing)
        && t.params.every((param) -> {
            type_slot_complete(p, param.item.ty)
        })
        && type_slot_complete(p, t.ret)
        && (throws_ty == null || type_slot_complete(p, throws_ty))
}
