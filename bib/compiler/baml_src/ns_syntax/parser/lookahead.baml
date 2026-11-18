// port: baml_parser/src/lookahead.rs @ d9be6853b
//
// Pure lookaheads over the significant tokens: each takes a `Cursor` and
// reads ahead without consuming (a Rust `Cursor` is passed by value; here no
// function in this file moves the cursor it is given). They decide only what
// cannot be decided after parsing without re-reading input: whether a `(`
// opens a lambda, a `<` a generic argument list, a `{` a map.

// port: baml_parser/src/lookahead.rs::PATH_SEGMENT @ d9be6853b
// Reserved words accepted as later segments of a path (`baml.spawn.Plan`).
const PATH_SEGMENT: KindSet = IDENT.union(
    KindSet.of(
        [
            TokenKind.Spawn,
            TokenKind.Await,
            TokenKind.Class,
            TokenKind.Enum,
            TokenKind.Interface,
            TokenKind.Function,
        ],
    ),
);

// port: baml_parser/src/lookahead.rs::NUMBER @ d9be6853b
// deviation: Rust declares this private const in lookahead.rs, types.rs,
// patterns.rs and expr.rs; a BAML namespace holds one, so it lives here and
// the others use it.
const NUMBER: KindSet = KindSet.of([TokenKind.Bigint, TokenKind.Integer, TokenKind.Float]);

// port: baml_parser/src/lookahead.rs::IN_TYPE_ARGS @ d9be6853b
// What may appear inside a `<...>` that is a generic argument list rather
// than a comparison: names and paths, type punctuation, literal types, and
// the punctuation of a function type.
const IN_TYPE_ARGS: KindSet = PATH_SEGMENT.union(STRING_TOKEN).union(NUMBER).union(
    KindSet.of(
        [
            TokenKind.Dot,
            TokenKind.Comma,
            TokenKind.Equals,
            TokenKind.LBracket,
            TokenKind.RBracket,
            TokenKind.Question,
            TokenKind.Pipe,
            TokenKind.Minus,
            TokenKind.LParen,
            TokenKind.RParen,
            TokenKind.Colon,
            TokenKind.Arrow,
            TokenKind.FatArrow,
        ],
    ),
);

// port: baml_parser/src/lookahead.rs::CONTINUES_AFTER_BRACE @ d9be6853b
// After the `}` of a brace literal in a position where a `{` would otherwise
// open the enclosing construct's body: tokens that continue the expression
// (so the literal was one), or a second `{` (the body itself).
const CONTINUES_AFTER_BRACE: KindSet = KindSet.of(
    [
        TokenKind.LBrace,
        TokenKind.Dot,
        TokenKind.Dollar,
        TokenKind.QuestionDot,
        TokenKind.LBracket,
        TokenKind.LParen,
    ],
);

// port: baml_parser/src/lookahead.rs::ENDS_PROJECTION_SELF @ d9be6853b
// Tokens that may end the `Self` type of a qualified projection, so that an
// `as` after one of them is the projection's and not a name.
const ENDS_PROJECTION_SELF: KindSet = PATH_SEGMENT.union(
    KindSet.of([TokenKind.Greater, TokenKind.RBracket, TokenKind.Question, TokenKind.RParen]),
);

// port: baml_parser/src/lookahead.rs::at_binding_intro @ d9be6853b
// `let`, or a contextual `const` followed by a pattern-shaped token.
function at_binding_intro(cur: Cursor) -> bool throws never {
    binding_intro_at(cur, 0)
}

// port: baml_parser/src/lookahead.rs::binding_intro_at @ d9be6853b
// `at_binding_intro` at the significant token `n` ahead.
function binding_intro_at(cur: Cursor, n: int) -> bool throws never {
    cur.nth_is(n, TokenKind.Let)
        || (
            cur.nth_is(n, TokenKind.Const)
                && (
                    cur.nth_is_ident(n + 1)
                        || cur.nth_is(n + 1, TokenKind.LBracket)
                        || cur.nth_is(n + 1, TokenKind.LParen)
                )
        )
}

// port: baml_parser/src/lookahead.rs::at_catch_clause_start @ d9be6853b
function at_catch_clause_start(cur: Cursor) -> bool throws never {
    cur.at_in(CATCH_KW)
}

// port: baml_parser/src/lookahead.rs::matching_close @ d9be6853b
// The significant index of the closer matching the opener at `open`, by a
// stack of expected closers; null when the input ends or a closer is out of
// order. A `${` opens a brace, a backtick run a template.
function matching_close(cur: Cursor, open: int) -> int? throws never {
    let stack: TokenKind[] = [];
    let i = open;
    while (true) {
        let kind = cur.kind_at_sig(i)
            ?? return null;
        match (kind) {
            TokenKind.LParen => {
                stack.push(TokenKind.RParen);
            },
            TokenKind.LBracket => {
                stack.push(TokenKind.RBracket);
            },
            TokenKind.LBrace | TokenKind.DollarLBrace => {
                stack.push(TokenKind.RBrace);
            },
            TokenKind.BacktickStart => {
                stack.push(TokenKind.BacktickEnd);
            },
            TokenKind.RParen | TokenKind.RBracket | TokenKind.RBrace | TokenKind.BacktickEnd => {
                if (stack.pop() != kind) {
                    return null;
                }
                if (!stack) {
                    return i;
                }
            },
            _ => {},
        }
        i += 1;
    }
}

// port: baml_parser/src/lookahead.rs::generic_args_close @ d9be6853b
// The significant index of the `>` closing the generic argument list that
// opens at `open` (a `<`), if the tokens between can only be type arguments.
// `>` is one character, so `>>` closes two lists (only when two are open),
// and `>=`/`>>=` cannot close one at all (they are operators, so the `<` was
// a comparison).
function generic_args_close(cur: Cursor, open: int) -> int? throws never {
    let depth = 1;
    let i = open + 1;
    while (true) {
        let kind = cur.kind_at_sig(i)
            ?? return null;
        match (kind) {
            // The removed `unreflect(expr)` occupies one argument slot; its operand
            // is an expression, skipped balanced.
            TokenKind.Unreflect if cur.kind_at_sig(i + 1) == TokenKind.LParen => {
                i
                    = (
                        matching_close(cur, i + 1)
                            ?? return null
                    )
                        + 1;
                continue;
            },
            TokenKind.Less => {
                depth += 1;
            },
            TokenKind.Greater => {
                let idx = cur.sig(i)
                    ?? return null;
                match (binary_op_at(cur.tokens(), idx)) {
                    BinaryOp.Gt => {
                        depth -= 1;
                    },
                    BinaryOp.Shr if depth >= 2 => {
                        depth -= 2;
                        i += 1;
                    },
                    _ => {
                        return null;
                    },
                }
                if (depth == 0) {
                    return i;
                }
            },
            _ if IN_TYPE_ARGS.contains(kind) => {},
            _ => {
                return null;
            },
        }
        i += 1;
    }
}

// port: baml_parser/src/lookahead.rs::looks_like_generic_args @ d9be6853b
// Whether the `<` at the cursor opens generic arguments rather than a
// comparison: the list must close (`generic_args_close`) and what follows the
// `>` must not read as the right operand of a comparison. The TypeScript
// rule, so `foo<int>` is a value and `[a < b, c > d]` two comparisons.
function looks_like_generic_args(cur: Cursor) -> bool throws never {
    let close = generic_args_close(cur, cur.pos)
        ?? return false;
    let follow = close + 1;
    let kind = cur.kind_at_sig(follow);
    match (kind) {
        // A call, a generic constructor, a qualified path.
        TokenKind.LParen | TokenKind.LBrace | TokenKind.Dot => true,
        // Ambiguous with a comparison or a shift: the comparison reading wins.
        TokenKind.Less | TokenKind.LessLess | TokenKind.Greater | TokenKind.Plus | TokenKind.Minus => {
            false
        },
        null => true,
        _ => {
            let idx = cur.sig(follow);
            cur.newline_between_sig(close, follow)
                || (idx != null && binary_op_at(cur.tokens(), idx) != null)
                || !at_expression_start(at_sig(cur, follow))
                || kind == TokenKind.Comma
        },
    }
}

// port: baml_parser/src/lookahead.rs::at_sig @ d9be6853b
// A copy of `cur` positioned at significant index `i`.
function at_sig(cur: Cursor, i: int) -> Cursor throws never {
    let at = cur.copy();
    at.pos = i;
    at
}

// port: baml_parser/src/lookahead.rs::looks_like_generic_lambda @ d9be6853b
// `<T>(...` / `<T, U>(...`: a lambda with (rejected) generic parameters.
function looks_like_generic_lambda(cur: Cursor) -> bool throws never {
    if (!cur.at(TokenKind.Less) || !cur.nth_is_ident(1)) {
        return false;
    }
    match (cur.kind(2)) {
        TokenKind.Greater => cur.nth_is(3, TokenKind.LParen),
        TokenKind.Comma => {
            let i = cur.pos + 3;
            while (true) {
                let kind = cur.kind_at_sig(i)
                    ?? return false;
                if (kind == TokenKind.Greater) {
                    return cur.kind_at_sig(i + 1) == TokenKind.LParen;
                }
                i += 1;
            }
        },
        _ => false,
    }
}

// port: baml_parser/src/lookahead.rs::looks_like_lambda @ d9be6853b
// Whether the `(` at the cursor opens a lambda's parameters: `() ->`, a typed
// first parameter `(name:`, or a balanced group followed by an arrow.
function looks_like_lambda(cur: Cursor) -> bool throws never {
    if (cur.nth_is_ident(1) && cur.nth_is(2, TokenKind.Colon)) {
        return true;
    }
    let close = matching_close(cur, cur.pos)
        ?? return false;
    let next = cur.kind_at_sig(close + 1);
    next == TokenKind.Arrow || next == TokenKind.FatArrow
}

// port: baml_parser/src/lookahead.rs::looks_like_function_type_paren @ d9be6853b
// Whether the `(` at the cursor is followed, after its `)`, by `->`: a
// function type in pattern position.
function looks_like_function_type_paren(cur: Cursor) -> bool throws never {
    let close = matching_close(cur, cur.pos)
        ?? return false;
    cur.kind_at_sig(close + 1) == TokenKind.Arrow
}

// port: baml_parser/src/lookahead.rs::looks_like_paren_type_suffix @ d9be6853b
// Whether the `(` at the cursor is followed, after its `)`, by a type
// modifier (`[` or `?`): a parenthesized type such as `(int | string)[]`.
function looks_like_paren_type_suffix(cur: Cursor) -> bool throws never {
    let close = matching_close(cur, cur.pos)
        ?? return false;
    let next = cur.kind_at_sig(close + 1);
    next == TokenKind.LBracket || next == TokenKind.Question
}

// port: baml_parser/src/lookahead.rs::looks_like_qualified_projection @ d9be6853b
// `( ... as ... ) . member` at the cursor: the qualified-projection shape, the
// same in type and expression position.
function looks_like_qualified_projection(cur: Cursor) -> bool throws never {
    if (!cur.at(TokenKind.LParen)) {
        return false;
    }
    let i = cur.pos + 1;
    let paren_depth = 1;
    let angle_depth = 0;
    let saw_as = false;
    let previous: TokenKind? = null;
    while (true) {
        let kind = cur.kind_at_sig(i)
            ?? return false;
        match (kind) {
            TokenKind.LParen => {
                paren_depth += 1;
            },
            TokenKind.RParen => {
                if (paren_depth == 1) {
                    if (angle_depth != 0) {
                        return false;
                    }
                    break;
                }
                paren_depth -= 1;
            },
            TokenKind.Less => {
                angle_depth += 1;
            },
            TokenKind.Greater => {
                if (angle_depth > 0) {
                    angle_depth -= 1;
                }
            },
            TokenKind.As
                if paren_depth == 1
                && angle_depth == 0
                && previous != null
                && ENDS_PROJECTION_SELF.contains(previous) => {
                saw_as = true;
            },
            _ => {},
        }
        previous = kind;
        i += 1;
    }
    // `i` is the closing `)`.
    saw_as && cur.kind_at_sig(i + 1) == TokenKind.Dot && cur.sig_in(i + 2, MEMBER_NAME)
}

// port: baml_parser/src/lookahead.rs::looks_like_as_projection @ d9be6853b
// `. as <` at the cursor: the `.as<T>` upcast.
function looks_like_as_projection(cur: Cursor) -> bool throws never {
    cur.at(TokenKind.Dot) && cur.nth_is(1, TokenKind.As) && cur.nth_is(2, TokenKind.Less)
}

// port: baml_parser/src/lookahead.rs::looks_like_map @ d9be6853b
// Whether the `{` at the cursor opens a map literal rather than a block: a
// top-level `:` before any `,`/`;`/statement keyword says map; `{}` is an
// empty map; a `//#` header right inside says block.
function looks_like_map(cur: Cursor) -> bool throws never {
    let inside = cur.copy();
    inside.skip();
    if (inside.header_ahead()) {
        return false;
    }
    if (cur.nth_is(1, TokenKind.RBrace)) {
        return true;
    }
    let stack: TokenKind[] = [];
    let i = cur.pos + 1;
    while let kind: TokenKind = cur.kind_at_sig(i) {
        if (kind == TokenKind.Less && !stack) {
            let close = generic_args_close(cur, i);
            if (close != null) {
                i = close + 1;
                continue;
            }
        }
        match (kind) {
            TokenKind.Colon if !stack => {
                return true;
            },
            TokenKind.Comma | TokenKind.Semicolon if !stack => {
                return false;
            },
            TokenKind.Let | TokenKind.While | TokenKind.For if !stack => {
                return false;
            },
            TokenKind.LParen => {
                stack.push(TokenKind.RParen);
            },
            TokenKind.LBracket => {
                stack.push(TokenKind.RBracket);
            },
            TokenKind.LBrace | TokenKind.DollarLBrace => {
                stack.push(TokenKind.RBrace);
            },
            TokenKind.BacktickStart => {
                stack.push(TokenKind.BacktickEnd);
            },
            TokenKind.RParen | TokenKind.RBracket | TokenKind.RBrace | TokenKind.BacktickEnd
                if stack.pop() != kind => {
                return false;
            },
            _ => {},
        }
        i += 1;
    }
    false
}

// port: baml_parser/src/lookahead.rs::destructure_brace @ d9be6853b
// At a name: the significant index of the `{` that makes this a class
// destructure (`Class {`, `a.b.Class {`, `Class<int> {`), if there is one.
function destructure_brace(cur: Cursor) -> int? throws never {
    let i = cur.pos + 1;
    while (true) {
        match (cur.kind_at_sig(i)) {
            TokenKind.Dot if cur.sig_in(i + 1, PATH_SEGMENT) => {
                i += 2;
            },
            TokenKind.LBrace => {
                return i;
            },
            TokenKind.Less => {
                let close = generic_args_close(cur, i)
                    ?? return null;
                return if (cur.kind_at_sig(close + 1) == TokenKind.LBrace) {
                    close + 1
                } else {
                    null
                };
            },
            _ => {
                return null;
            },
        }
    }
}

// port: baml_parser/src/lookahead.rs::brace_looks_like_fields @ d9be6853b
// Whether the `{` at significant index `open` opens something field-shaped:
// `{ name:`, a shorthand `{ name,` / `{ name }`, `{ ...`, or `{}`.
function brace_looks_like_fields(cur: Cursor, open: int) -> bool throws never {
    match (cur.kind_at_sig(open + 1)) {
        TokenKind.DotDotDot | TokenKind.RBrace => true,
        let kind: TokenKind if IDENT.contains(kind) || kind == TokenKind.Client => {
            let i = open + 2;
            while (cur.kind_at_sig(i) == TokenKind.Dot && cur.nth_is_ident_at(i + 1)) {
                i += 2;
            }
            match (cur.kind_at_sig(i)) {
                TokenKind.Colon => true,
                TokenKind.Comma | TokenKind.RBrace => i == open + 2,
                _ => false,
            }
        },
        _ => false,
    }
}

// port: baml_parser/src/lookahead.rs::brace_literal_before_body @ d9be6853b
// Whether the brace literal opening at significant index `open` may be taken
// where a `{` would otherwise be the enclosing construct's body: only when
// the token after its `}` continues the expression, or is the body's own `{`.
function brace_literal_before_body(cur: Cursor, open: int) -> bool throws never {
    let close = matching_close(cur, open)
        ?? return false;
    cur.sig_in(close + 1, CONTINUES_AFTER_BRACE)
}

// port: baml_parser/src/lookahead.rs::looks_like_for_in @ d9be6853b
// At a binding introducer: whether the header is the `in` form. The pattern
// is skipped balanced; the first top-level `in` says so, a `=` or `;` says
// C-style.
function looks_like_for_in(cur: Cursor) -> bool throws never {
    let stack: TokenKind[] = [];
    let i = cur.pos + 1;
    while (true) {
        let kind = cur.kind_at_sig(i)
            ?? return false;
        match (kind) {
            TokenKind.LParen => {
                stack.push(TokenKind.RParen);
            },
            TokenKind.LBracket => {
                stack.push(TokenKind.RBracket);
            },
            TokenKind.LBrace => {
                stack.push(TokenKind.RBrace);
            },
            TokenKind.RParen | TokenKind.RBracket | TokenKind.RBrace => {
                if (stack.pop() != kind) {
                    return false;
                }
            },
            TokenKind.In if !stack => {
                return true;
            },
            TokenKind.Equals | TokenKind.Semicolon if !stack => {
                return false;
            },
            _ => {},
        }
        i += 1;
    }
}

// port: baml_parser/src/lookahead.rs::looks_like_catch_arm_ahead @ d9be6853b
// After a catch arm lost its `=>`: whether another arm's `=>` is ahead on
// this line run, before a `}`, `,` or `;` (bounded, so recovery never scans
// a whole file).
function looks_like_catch_arm_ahead(cur: Cursor) -> bool throws never {
    for (let i = cur.pos; i < cur.pos + CATCH_ARM_LOOKAHEAD; i += 1) {
        match (cur.kind_at_sig(i)) {
            null => {
                return false;
            },
            TokenKind.FatArrow => {
                return true;
            },
            TokenKind.RBrace | TokenKind.Comma | TokenKind.Semicolon => {
                return false;
            },
            _ => {},
        }
    }
    false
}

// How many tokens `looks_like_catch_arm_ahead` reads at most.
const CATCH_ARM_LOOKAHEAD: int = 64;
