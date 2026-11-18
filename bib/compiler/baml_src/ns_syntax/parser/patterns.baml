// port: baml_parser/src/patterns.rs @ d9be6853b
//
// Patterns: bindings, wildcards, class and array destructures, types as
// patterns, and `|` alternatives. The `let`/`const` introducer of a binding
// statement is the statement's; a pattern carries one only where it
// introduces the binding itself (`match x { let y => ... }`).
//
// `NUMBER` is the one in lookahead.baml (see the deviation there).

// port: baml_parser/src/patterns.rs::PATTERN_START @ d9be6853b
// What begins a pattern besides a binding introducer.
const PATTERN_START: KindSet = IDENT.union(STRING_TOKEN).union(NUMBER).union(
    KindSet.of([TokenKind.Minus, TokenKind.LParen, TokenKind.LBracket, TokenKind.Less]),
);

// port: baml_parser/src/patterns.rs::at_pattern_start @ d9be6853b
function at_pattern_start(cur: Cursor) -> bool throws never {
    cur.at_in(PATTERN_START) || at_binding_intro(cur)
}

// port: baml_parser/src/patterns.rs::pattern @ d9be6853b
// A pattern: alternatives joined by `|`, each an atom. `Missing` (reported)
// when nothing here begins one.
function pattern(p: Parser, r: Restrictions) -> AnyPattern | Missing throws never {
    let deep = p.enter_nesting("a pattern");
    if (deep) {
        return deep;
    }
    let first = atom(p, r);
    let result = if (first is Missing) {
        first
    } else {
        union_rest(p, first, r)
    };
    p.leave_nesting();
    result
}

// port: baml_parser/src/patterns.rs::pattern_after_introducer @ d9be6853b
// The pattern after a statement's `let`/`const`, which is already consumed:
// the binding shapes (`x`, `x: pattern`, `_`, `Class { ... }`, `[...]`), then
// any `|` alternatives.
function pattern_after_introducer(p: Parser, r: Restrictions) -> AnyPattern | Missing throws never {
    let first = introduced(p, null, r);
    if (first is Missing) {
        return first;
    }
    union_rest(p, first, r)
}

// port: baml_parser/src/patterns.rs::union_rest @ d9be6853b
// `first` and the `| atom` arms after it, if any.
function union_rest(p: Parser, first: AnyPattern, r: Restrictions) -> AnyPattern throws never {
    let arms: PatternArm[] = [];
    while let pipe: int = p.cur.eat(TokenKind.Pipe) {
        let pattern = atom(p, r);
        arms.push(PatternArm { pipe: pipe, pattern: pattern });
        if (pattern is Missing) {
            break;
        }
    }
    if (!arms) {
        return first;
    }
    let mark = p.mark_of(node_span(first));
    UnionPattern { span: p.span_from(mark), first: first, arms: arms }
}

// port: baml_parser/src/patterns.rs::atom @ d9be6853b
// One alternative.
function atom(p: Parser, r: Restrictions) -> AnyPattern | Missing throws never {
    let mark = p.cur.mark();
    if (p.cur.at(TokenKind.LParen)) {
        // A `(` opens a parenthesized pattern, or a type: a function type when
        // `->` follows the `)`, a modified type when `[`/`?` does, a projection
        // when `as` is inside.
        if (looks_like_qualified_projection(p.cur) || looks_like_function_type_paren(p.cur)) {
            return type_pattern(p, mark, type_operand(p));
        }
        if (looks_like_paren_type_suffix(p.cur)) {
            return type_pattern(p, mark, any_type(p));
        }
    }
    let l = p.cur.eat(TokenKind.LParen);
    if (l != null) {
        return paren_or_tuple_pattern(p, mark, l);
    }
    if (at_binding_intro(p.cur)) {
        let introducer = p.cur.eat_in(LET_INTRODUCER);
        if (introducer != null) {
            return introduced(p, introducer, r);
        }
    }
    let bracket = p.cur.eat(TokenKind.LBracket);
    if (bracket != null) {
        return array_pattern(p, bracket);
    }
    let underscore = p.cur.eat(TokenKind.Underscore);
    if (underscore != null) {
        return WildcardPattern { span: p.span_from(mark), introducer: null, underscore: underscore };
    }
    if (p.cur.at_ident()) {
        let open = destructure_brace(p.cur);
        if (open != null && brace_allowed(p.cur, open, r)) {
            let head = p.cur.eat_in(IDENT);
            if (head != null) {
                return destructure(p, mark, null, head);
            }
        }
    }
    if (p.cur.at_in(PATTERN_START)) {
        return type_pattern(p, mark, type_operand(p));
    }
    p.missing("pattern")
}

// port: baml_parser/src/patterns.rs::brace_allowed @ d9be6853b
// Whether a destructure's `{` at significant index `open` may be taken here:
// always, unless a `{` after the pattern is the enclosing construct's body
// (`if x is Class {`), when only a `{` whose match is followed by the body's
// own `{` or an expression continuation is.
function brace_allowed(cur: Cursor, open: int, r: Restrictions) -> bool throws never {
    !r.brace_is_body || brace_literal_before_body(cur, open)
}

// port: baml_parser/src/patterns.rs::introduced @ d9be6853b
// The shapes a binding introducer takes: `_`, `Class { ... }`, `name`,
// `name: pattern`. `introducer` is the token when the pattern introduces the
// binding itself, null when the statement did (`let x = ...`); then an array
// pattern may follow too, since the statement's introducer covers it.
function introduced(
    p: Parser,
    introducer: int?,
    r: Restrictions,
) -> AnyPattern | Missing throws never {
    let mark = if (introducer != null) {
        Mark { idx: introducer }
    } else {
        p.cur.mark()
    };
    if (introducer == null && p.cur.at(TokenKind.LParen)) {
        return atom(p, r);
    }
    let underscore = p.cur.eat(TokenKind.Underscore);
    if (underscore != null) {
        return WildcardPattern { span: p.span_from(mark), introducer: introducer, underscore: underscore };
    }
    if (introducer == null) {
        let l = p.cur.eat(TokenKind.LBracket);
        if (l != null) {
            return array_pattern(p, l);
        }
    }
    let open = if (p.cur.at_ident()) {
        destructure_brace(p.cur)
    } else {
        null
    };
    let destructures = open != null && brace_allowed(p.cur, open, r);
    let head = p.cur.eat_in(IDENT)
        ?? return p.missing("identifier after 'let'");
    if (destructures) {
        return destructure(p, mark, introducer, head);
    }
    let name = p.name(head);
    let colon = p.cur.eat(TokenKind.Colon);
    let ascription = if (colon != null) {
        PatternAscription { colon: colon, pattern: pattern(p, r) }
    } else {
        null
    };
    BindingPattern {
        span: p.span_from(mark),
        introducer: introducer,
        name: name,
        ascription: ascription,
    }
}

// port: baml_parser/src/patterns.rs::destructure @ d9be6853b
// `Class<T> { field, field: pattern }` from the class path's first name. If
// no `{` follows the path after all, the path was a type pattern.
function destructure(
    p: Parser,
    mark: Mark,
    introducer: int?,
    head: int,
) -> AnyPattern throws never {
    let path = path_type(p, head);
    let l = p.cur.eat(TokenKind.LBrace);
    if (l == null) {
        return TypePattern { span: p.span_from(mark), ty: path };
    }
    let fields = p.members(TokenKind.RBrace, STATEMENT_KEYWORD, IDENT, (p) -> {
        let name = p.eat_name(IDENT);
        if (name == null) {
            p.unexpected("field name");
            return null;
        }
        let colon = p.cur.eat(TokenKind.Colon);
        let sub = if (colon != null) {
            PatternAscription { colon: colon, pattern: pattern(p, Restrictions.empty()) }
        } else {
            null
        };
        let item = FieldPattern { span: p.span_from(p.mark_of(name.span)), name: name, sub: sub };
        let sep = p.cur.eat(TokenKind.Comma);
        Member {
            item: SepItem { item: item, sep: sep },
            missing_sep: if (sep == null) {
                "',' or '}' after field pattern"
            } else {
                null
            },
        }
    });
    let r = p.expect(TokenKind.RBrace);
    DestructurePattern {
        span: p.span_from(mark),
        introducer: introducer,
        path: path,
        l: l,
        fields: fields,
        r: r,
    }
}

// port: baml_parser/src/patterns.rs::array_pattern @ d9be6853b
// `a, ..rest]: T[]` after its `[`. Slots are patterns, so a binding is
// written `let a`.
function array_pattern(p: Parser, l: int) -> ArrayPattern throws never {
    let seen_rest = false;
    let elements = p.members(TokenKind.RBracket, KindSet.of([]), KindSet.of([]), (p) -> {
        let dots = p.cur.eat(TokenKind.DotDot);
        let element: AnyArrayPatternElement = if (dots != null) {
            if (seen_rest) {
                p.unexpected("only one '..' rest pattern is allowed in an array pattern");
            }
            seen_rest = true;
            let rest = if (!p.cur.at(TokenKind.Comma) && !p.cur.at(TokenKind.RBracket) && !p.cur.at_end()) {
                pattern(p, Restrictions.empty())
            } else {
                null
            };
            RestPattern {
                span: p.span_from(Mark { idx: dots }),
                dots: dots,
                pattern: if (rest is Missing) {
                    null
                } else {
                    rest
                },
            }
        } else if (at_pattern_start(p.cur)) {
            let inner = pattern(p, Restrictions.empty());
            if (inner is Missing) {
                return null;
            }
            inner
        } else {
            p.unexpected("pattern");
            return null;
        };
        let sep = p.cur.eat(TokenKind.Comma);
        Member {
            item: SepItem { item: element, sep: sep },
            missing_sep: if (sep == null) {
                "',' or ']' after array pattern element"
            } else {
                null
            },
        }
    });
    let r = p.expect(TokenKind.RBracket);
    let colon = p.cur.eat(TokenKind.Colon);
    let ascription = if (colon != null) {
        let ty = any_type(p);
        reject_unmatched_greater(p);
        TypeAscription { span: p.span_from(Mark { idx: colon }), colon: colon, ty: ty }
    } else {
        null
    };
    ArrayPattern {
        span: p.span_from(Mark { idx: l }),
        l: l,
        elements: elements,
        r: r,
        ascription: ascription,
    }
}

// deviation: the `(...)` branch of Rust's `atom`, split out so `atom` stays
// readable. A tuple when a `,` follows the first pattern, else a paren
// pattern.
function paren_or_tuple_pattern(p: Parser, mark: Mark, l: int) -> AnyPattern throws never {
    let inner = pattern(p, Restrictions.empty());
    let sep = p.cur.eat(TokenKind.Comma);
    if (sep == null) {
        let r = p.expect(TokenKind.RParen);
        return ParenPattern { span: p.span_from(mark), l: l, inner: inner, r: r };
    }
    let elements: SepItem<AnyPattern>[] = [];
    if (!(inner is Missing)) {
        elements.push(SepItem { item: inner, sep: sep });
    }
    while (!p.cur.at(TokenKind.RParen) && !p.cur.at_end()) {
        let item = pattern(p, Restrictions.empty());
        if (item is Missing) {
            break;
        }
        let item_sep = p.cur.eat(TokenKind.Comma);
        elements.push(SepItem { item: item, sep: item_sep });
        if (item_sep == null) {
            break;
        }
    }
    let r = p.expect(TokenKind.RParen);
    TuplePattern { span: p.span_from(mark), l: l, elements: elements, r: r }
}

// deviation: Rust's `Ok(AnyPattern::Type(p.alloc(mark, TypePattern { ty: ty? })))`,
// written three times in `atom`: the type as a pattern, or its `Missing`.
function type_pattern(
    p: Parser,
    mark: Mark,
    ty: AnyType | Missing,
) -> AnyPattern | Missing throws never {
    if (ty is Missing) {
        return ty;
    }
    TypePattern { span: p.span_from(mark), ty: ty }
}
