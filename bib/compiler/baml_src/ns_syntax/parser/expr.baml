// port: baml_parser/src/expr.rs @ d9be6853b
//
// Expressions: a Pratt loop over `BinaryOp`'s table, with the postfix forms
// (calls, members, indexing, `catch`, object literals) handled in the same
// loop, and the primaries. Every operand is a node.
//
// How tokens may be read in a position arrives as `Restrictions`, a
// parameter: whether a line break can end the expression, whether a `{`
// after it belongs to the enclosing construct, whether a postfix `catch`
// does. A delimiter clears them all.
//
// `NUMBER` (bigint, integer and float literals) is the same private const in
// expr.rs, lookahead.rs, patterns.rs and types.rs; the namespace has one, in
// lookahead.baml.

// port: baml_parser/src/expr.rs::Restrictions @ d9be6853b
// How the tokens of an expression may be read in the position it is parsed
// in. Not where the parser is: what the position permits.
// deviation: Rust's bitflags are a class of four flags. `Restrictions::empty()`
// is `Restrictions.empty()`, `Restrictions::STATEMENT` is
// `Restrictions.statement()`, `Restrictions::BRACE_IS_BODY` alone is
// `Restrictions.empty().before_body()`, `r.contains(FLAG)` reads the field,
// and `r | FLAG` is `Restrictions { ...r, flag: true }`.
class Restrictions {
    // The position's items are separated by lines (a block's statements, a
    // `match`'s arms, the file's items): a line break ends the expression when
    // what follows could begin another one. Inside a delimiter a line break is
    // whitespace.
    line_separated: bool,
    // A `{` after the expression opens the enclosing construct's body (`if c {`,
    // `while c {`, `match x {`, `spawn n {`, `for ... in xs {`). An object
    // literal or a class destructure is taken there only when its matching `}`
    // is followed by something that continues the expression, or by the body's
    // own `{`.
    brace_is_body: bool,
    // A postfix `catch` belongs to the prefix form around this expression
    // (`throw x catch ...` is `(throw x) catch ...`), not to it.
    no_catch: bool,
    match_guard: bool,

    // port: baml_parser/src/expr.rs::Restrictions::empty @ d9be6853b
    function empty() -> Restrictions throws never {
        Restrictions {
            line_separated: false,
            brace_is_body: false,
            no_catch: false,
            match_guard: false,
        }
    }

    // port: baml_parser/src/expr.rs::Restrictions::STATEMENT @ d9be6853b
    // Statement position: a line break can end the expression.
    function statement() -> Restrictions throws never {
        Restrictions {
            line_separated: true,
            brace_is_body: false,
            no_catch: false,
            match_guard: false,
        }
    }

    // port: baml_parser/src/expr.rs::Restrictions::before_body @ d9be6853b
    // The same position, with a `{` after the expression reserved for the
    // enclosing construct's body.
    function before_body(self) -> Restrictions throws never {
        Restrictions { ...self, brace_is_body: true }
    }

    // port: baml_parser/src/expr.rs::Restrictions::brace_literal_allowed @ d9be6853b
    // Whether the brace literal opening at significant index `open` may be
    // taken here.
    function brace_literal_allowed(self, cur: Cursor, open: int) -> bool throws never {
        !self.brace_is_body || brace_literal_before_body(cur, open)
    }
}

// port: baml_parser/src/expr.rs::EXPR_NAME @ d9be6853b
// A name in expression position: a word, a contextual keyword, or `client`.
const EXPR_NAME: KindSet = IDENT.union(KindSet.of([TokenKind.Client]));

// port: baml_parser/src/expr.rs::EXPR_START @ d9be6853b
// Every token that can begin an expression. `<` only begins a generic
// lambda; see `at_expression_start`.
const EXPR_START: KindSet = EXPR_NAME.union(STRING_TOKEN).union(NUMBER).union(
    KindSet.of(
        [
            TokenKind.BacktickStart,
            TokenKind.LParen,
            TokenKind.LBracket,
            TokenKind.LBrace,
            TokenKind.If,
            TokenKind.Match,
            TokenKind.Throw,
            TokenKind.Return,
            TokenKind.Break,
            TokenKind.Continue,
            TokenKind.Less,
            TokenKind.Minus,
            TokenKind.Not,
            TokenKind.Tilde,
            TokenKind.PlusPlus,
            TokenKind.MinusMinus,
            TokenKind.Await,
            TokenKind.Spawn,
        ],
    ),
);

// port: baml_parser/src/expr.rs::ITEM_KEYWORD @ d9be6853b
// Item keywords no statement can begin with: inside a block or an arm list
// one of these means the `}` was forgotten. `client` begins a path, `test`
// and `testset` a nested test.
const ITEM_KEYWORD: KindSet = KindSet.of(
    [
        TokenKind.Class,
        TokenKind.Enum,
        TokenKind.Interface,
        TokenKind.Function,
        TokenKind.Implements,
        TokenKind.Implement,
        TokenKind.Generator,
        TokenKind.RetryPolicy,
        TokenKind.TemplateString,
    ],
);

// port: baml_parser/src/expr.rs::STATEMENT_KEYWORD @ d9be6853b
// Statement keywords: inside a brace literal one of these means the `}` was
// forgotten.
const STATEMENT_KEYWORD: KindSet = ITEM_KEYWORD.union(
    KindSet.of(
        [
            TokenKind.Let,
            TokenKind.Return,
            TokenKind.While,
            TokenKind.For,
            TokenKind.Break,
            TokenKind.Continue,
            TokenKind.Throw,
            TokenKind.Defer,
        ],
    ),
);

// port: baml_parser/src/expr.rs::at_expression_start @ d9be6853b
// Whether an expression can begin at the cursor. A `<` does only as a generic
// lambda (otherwise it is a comparison continuing the expression before it),
// and a `catch_all_panics` opens a clause, not an expression.
function at_expression_start(cur: Cursor) -> bool throws never {
    cur.at_in(EXPR_START)
        && (!cur.at(TokenKind.Less) || looks_like_generic_lambda(cur))
        && !at_catch_clause_start(cur)
}

// port: baml_parser/src/expr.rs::expr @ d9be6853b
// An expression, or a reported `Missing` when nothing here begins one. An
// assignment operator after it is an error here: an assignment is a
// statement, which only `stmt_expr`'s callers read.
function expr(p: Parser, r: Restrictions) -> AnyExpr | Missing throws never {
    let deep = p.enter_nesting("an expression");
    if (deep) {
        return deep;
    }
    let result = expr_bp(p, 0, r);
    p.leave_nesting();
    if (result is Missing) {
        return result;
    }
    reject_assignment(p, result, r);
    result
}

// port: baml_parser/src/expr.rs::stmt_expr @ d9be6853b
// An expression at the start of a statement line or of a `for` step, the
// positions an assignment may stand in: an assignment operator after it is
// left for the caller, which reads the assignment.
function stmt_expr(p: Parser, r: Restrictions) -> AnyExpr | Missing throws never {
    let deep = p.enter_nesting("an expression");
    if (deep) {
        return deep;
    }
    let result = expr_bp(p, 0, r);
    p.leave_nesting();
    result
}

// port: baml_parser/src/expr.rs::reject_assignment @ d9be6853b
// `(x = 5)`, `f(x = 5)`, `let y = x = 5`: an assignment where only a value may
// stand. Reported once over the whole assignment; its right-hand side is read
// for its extent only, so nothing inside it is reported or kept.
function reject_assignment(p: Parser, lhs: AnyExpr, r: Restrictions) -> void throws never {
    if (!p.cur.at_assign_op()) {
        return;
    }
    let mark = p.mark_of(node_span(lhs));
    p.probe((p) -> {
        p.cur.eat_assign_op();
        if (at_expression_start(p.cur)) {
            expr(p, r);
        }
    });
    let range = p.cur.text_range(p.cur.range_from(mark));
    p.error("assignment is not allowed in expression position; assignment is a statement", range);
}

// port: baml_parser/src/expr.rs::expr_bp @ d9be6853b
// An expression whose operators bind at least `min_bp`.
function expr_bp(p: Parser, min_bp: int, r: Restrictions) -> AnyExpr | Missing throws never {
    let lhs = prefix(p, r);
    if (lhs is Missing) {
        return lhs;
    }
    expr_from(p, lhs, r, min_bp = min_bp)
}

// port: baml_parser/src/expr.rs::expr_from + infix @ d9be6853b
// The postfix and infix forms after `lhs`, an operand the caller parsed, each
// binding at least `min_bp` (full binding power by default).
// deviation: Rust's `expr_from(p, lhs, r)` forwards to `infix(p, lhs, 0, r)`;
// here the two are one function with a defaulted `min_bp`.
function expr_from(
    p: Parser,
    lhs: AnyExpr,
    r: Restrictions,
    min_bp: int = 0,
) -> AnyExpr throws never {
    while (true) {
        // A `//#` line is a statement: it ends the expression before it.
        if (p.cur.header_ahead() || p.cur.at_end() || line_break_ends_expr(p.cur, r)) {
            break;
        }
        let mark = p.mark_of(node_span(lhs));
        let catch_kw = if (r.no_catch) {
            null
        } else {
            p.cur.eat_in(CATCH_KW)
        };
        if (catch_kw != null) {
            lhs = catch_expr(p, lhs, catch_kw);
            continue;
        }
        let lt = if (p.cur.at(TokenKind.Less) && looks_like_generic_args(p.cur)) {
            p.cur.eat(TokenKind.Less)
        } else {
            null
        };
        if (lt != null) {
            let args = parse_generic_args(p, lt);
            lhs = GenericApplyExpr { span: p.span_from(mark), base: lhs, args: args };
            continue;
        }
        if let l: int = p.cur.eat(TokenKind.LParen) {
            let args = parse_arg_list(p, l);
            lhs = CallExpr { span: p.span_from(mark), callee: lhs, args: args };
            continue;
        }
        // A template on the next line is a statement of its own.
        let open = if (p.cur.at(TokenKind.BacktickStart) && !p.cur.has_newline_ahead()) {
            p.cur.eat(TokenKind.BacktickStart)
        } else {
            null
        };
        if (open != null) {
            let template = parse_backtick_string(p, open);
            lhs = TaggedTemplateExpr { span: p.span_from(mark), tag: lhs, template: template };
            continue;
        }
        if let l: int = p.cur.eat(TokenKind.LBracket) {
            let index = operand(p, Restrictions.empty());
            let close = p.expect(TokenKind.RBracket);
            lhs = IndexExpr { span: p.span_from(mark), base: lhs, l: l, index: index, r: close };
            continue;
        }
        if (p.cur.at_in(TUPLE_DOT) && p.cur.nth_in(1, NUMBER)) {
            let dot = p.cur.eat_in(TUPLE_DOT) ?? baml.sys.panic("tuple dot");
            let slot = p.cur.eat_in(LITERAL_EXPR_TOKEN) ?? baml.sys.panic("numeric slot");
            // deviation: Rust's `part.parse::<u32>().is_ok()` on a canonical decimal
            // is a bound on its digits: at most ten, and at most "4294967295".
            let slot_number = (part: string) -> bool {
                part
                    && part.is_ascii_numeric()
                    && (part == "0" || !part.starts_with("0"))
                    && (part.length() < 10 || (part.length() == 10 && part <= "4294967295"))
            };
            if (!p.cur.text_of(slot).split(".").every(slot_number)) {
                p.error("tuple slots must be decimal slot numbers", p.cur.token_range(slot));
            }
            lhs = TupleFieldExpr { span: p.span_from(mark), base: lhs, dot: dot, slot: slot };
            continue;
        }
        if let qdot: int = p.cur.eat(TokenKind.QuestionDot) {
            lhs
                = if let l: int = p.cur.eat(TokenKind.LParen) {
                    let args = parse_arg_list(p, l);
                    OptionalCallExpr {
                        span: p.span_from(mark),
                        callee: lhs,
                        qdot: qdot,
                        args: args,
                    }
                } else if let l: int = p.cur.eat(TokenKind.LBracket) {
                    let index = operand(p, Restrictions.empty());
                    let close = p.expect(TokenKind.RBracket);
                    OptionalIndexExpr {
                        span: p.span_from(mark),
                        base: lhs,
                        qdot: qdot,
                        l: l,
                        index: index,
                        r: close,
                    }
                } else {
                    let name = p.expect_name(MEMBER_NAME, "field name, `[`, or `(` after `?.`");
                    OptionalFieldAccessExpr {
                        span: p.span_from(mark),
                        base: lhs,
                        qdot: qdot,
                        name: name,
                    }
                };
            continue;
        }
        // `F@spec`: an attribute on the next line is never absorbed.
        let at = if (p.cur.at(TokenKind.At) && !p.cur.has_newline_ahead() && p.cur.nth_in(1, SPEC_SELECTOR)) {
            p.cur.eat(TokenKind.At)
        } else {
            null
        };
        if (at != null) {
            let selector = p.expect_in(SPEC_SELECTOR, "companion selector");
            lhs = SpecExpr { span: p.span_from(mark), base: lhs, at: at, selector: selector };
            continue;
        }
        if (looks_like_as_projection(p.cur)) {
            if let dot: int = p.cur.eat(TokenKind.Dot) {
                if let as_kw: int = p.cur.eat(TokenKind.As) {
                    let lt = p.cur.eat(TokenKind.Less);
                    let args = if (lt != null) {
                        parse_generic_args(p, lt)
                    } else {
                        p.missing("'<'")
                    };
                    lhs
                        = UpcastExpr {
                            span: p.span_from(mark),
                            base: lhs,
                            dot: dot,
                            as_kw: as_kw,
                            args: args,
                        };
                    continue;
                }
            }
        }
        if let dot: int = p.cur.eat_in(MEMBER_DOT) {
            let expected = if (p.cur.tokens().kinds[dot] == TokenKind.Dollar) {
                "field name after `'$'`"
            } else {
                "field name after `'.'`"
            };
            let name = p.expect_name(MEMBER_NAME, expected);
            lhs = FieldAccessExpr { span: p.span_from(mark), base: lhs, dot: dot, name: name };
            continue;
        }
        if (p.cur.at(TokenKind.LBrace)) {
            let ctor: AnyObjectCtor? = match (lhs) {
                let path: PathExpr => path,
                let apply: GenericApplyExpr => apply,
                _ => null,
            };
            if (ctor == null) {
                break;
            }
            let brace = p.cur.pos;
            if (!(brace_looks_like_fields(p.cur, brace) && r.brace_literal_allowed(p.cur, brace))) {
                break;
            }
            let l = p.cur.eat(TokenKind.LBrace);
            if (l == null) {
                break;
            }
            lhs = object_literal(p, mark, ctor, l);
            continue;
        }
        if (p.cur.at(TokenKind.Is)) {
            if (IS_BINDING_POWER.left < min_bp) {
                break;
            }
            let is_kw = p.cur.eat(TokenKind.Is);
            if (is_kw == null) {
                break;
            }
            let pat = pattern(p, r);
            lhs = IsExpr { span: p.span_from(mark), expr: lhs, is_kw: is_kw, pattern: pat };
            continue;
        }
        if (p.cur.at(TokenKind.Not) && !p.cur.has_newline_ahead()) {
            // A `!` after a complete expression is a non-null assertion from
            // another language; on the next line it is a prefix operator.
            p.error_here(
                "unexpected '!'; BAML has no non-null assertion operator — unwrap optionals with '?? <default>' or 'if let x: T = opt { ... }'",
            );
            p.cur.skip();
            continue;
        }
        // An assignment operator ends the expression (`>>=` before `>>`).
        if (p.cur.at_assign_op()) {
            break;
        }
        let idx = p.cur.nth(0);
        let peeked = if (idx != null) {
            binary_op_at(p.cur.tokens(), idx)
        } else {
            null
        };
        if (peeked == null) {
            break;
        }
        let binding_power = binary_binding_power(peeked);
        if (binding_power.left < min_bp) {
            break;
        }
        let op = p.cur.eat_binary_op();
        if (op == null) {
            break;
        }
        let rhs = expr_bp(p, binding_power.right, r);
        lhs = BinaryExpr { span: p.span_from(mark), lhs: lhs, op: op, rhs: rhs };
    }
    lhs
}

// port: baml_parser/src/expr.rs::line_break_ends_expr @ d9be6853b
// Whether a line break before the current token ends the expression parsed
// so far. Calls and indexing never attach across a line break. Where lines
// separate items, a token that can begin an expression ends the previous one,
// except a `-` not followed by a blank: `a\n- b` subtracts, `a\n-b` is two
// expressions. Inside a delimiter a line break is whitespace.
function line_break_ends_expr(cur: Cursor, r: Restrictions) -> bool throws never {
    if (!cur.has_newline_ahead()) {
        return false;
    }
    if (cur.at(TokenKind.LParen) || cur.at(TokenKind.LBracket)) {
        return true;
    }
    if (!r.line_separated) {
        return false;
    }
    if (cur.at(TokenKind.Minus)) {
        let idx = cur.nth(0);
        return !(idx != null && cur.blank_after(idx));
    }
    at_expression_start(cur)
}

// ----- prefix and primary -----------------------------------------------------------

// port: baml_parser/src/expr.rs::prefix @ d9be6853b
// A prefix operator and its operand, or a primary. The operand of a prefix
// operator is parsed at `PREFIX_BINDING_POWER`, so postfix forms bind tighter:
// `!x.f()` is `!(x.f())`.
function prefix(p: Parser, r: Restrictions) -> AnyExpr | Missing throws never {
    if let op: int = p.cur.eat_in(UNARY_OP_TOKEN) {
        let operand = expr_bp(p, PREFIX_BINDING_POWER, r);
        return UnaryExpr { span: p.span_from(Mark { idx: op }), op: op, operand: operand };
    }
    if let kw: int = p.cur.eat(TokenKind.Await) {
        // `await f catch ...` catches what the await re-throws: the clause belongs
        // to the whole `await f`.
        let operand = expr_bp(p, PREFIX_BINDING_POWER, Restrictions { ...r, no_catch: true });
        return AwaitExpr { span: p.span_from(Mark { idx: kw }), kw: kw, operand: operand };
    }
    if let kw: int = p.cur.eat(TokenKind.Spawn) {
        return spawn_expr(p, kw, r);
    }
    primary(p, r)
}

// port: baml_parser/src/expr.rs::at_statement_end @ d9be6853b
// Whether the current token ends a statement: a diverging form's operand does
// not begin at one.
function at_statement_end(cur: Cursor) -> bool throws never {
    cur.at_end()
        || cur.at(TokenKind.Semicolon)
        || cur.at(TokenKind.Comma)
        || cur.at(TokenKind.RBrace)
}

// port: baml_parser/src/expr.rs::primary @ d9be6853b
function primary(p: Parser, r: Restrictions) -> AnyExpr | Missing throws never {
    if let token: int = p.cur.eat_in(LITERAL_EXPR_TOKEN) {
        return LiteralExpr { span: p.span_from(Mark { idx: token }), token: token };
    }
    if let lit: StringLit = string_lit(p, StringSite.Expr) {
        return lit;
    }
    if let open: int = p.cur.eat(TokenKind.BacktickStart) {
        return parse_backtick_string(p, open);
    }
    if let kw: int = p.cur.eat(TokenKind.Throw) {
        let payload = if (at_statement_end(p.cur)) {
            p.missing("expression after 'throw'")
        } else {
            expr(p, Restrictions { ...r, no_catch: true })
        };
        return ThrowExpr { span: p.span_from(Mark { idx: kw }), kw: kw, payload: payload };
    }
    if let kw: int = p.cur.eat(TokenKind.Return) {
        // `return x catch ...` returns the caught value: a `return` cannot throw,
        // so the clause can only be the value's.
        let value = if (at_statement_end(p.cur)) {
            null
        } else {
            ok(expr(p, r))
        };
        return ReturnExpr { span: p.span_from(Mark { idx: kw }), kw: kw, value: value };
    }
    if let kw: int = p.cur.eat(TokenKind.Break) {
        return BreakExpr { span: p.span_from(Mark { idx: kw }), kw: kw };
    }
    if let kw: int = p.cur.eat(TokenKind.Continue) {
        return ContinueExpr { span: p.span_from(Mark { idx: kw }), kw: kw };
    }
    if (p.cur.at(TokenKind.Map) && p.cur.nth_is(1, TokenKind.LBrace)) {
        if let map_kw: int = p.cur.eat(TokenKind.Map) {
            if let l: int = p.cur.eat(TokenKind.LBrace) {
                return parse_map_literal(p, map_kw, l);
            }
        }
    }
    // `env.NAME` sugar; `env.get(...)` is an ordinary path.
    if (
        p.cur.at(TokenKind.Env)
            && p.cur.nth_is(1, TokenKind.Dot)
            && p.cur.nth_is(2, TokenKind.Word)
            && !p.cur.nth_is(3, TokenKind.LParen)
    ) {
        if let env: int = p.cur.eat(TokenKind.Env) {
            if let dot: int = p.cur.eat(TokenKind.Dot) {
                let name = p.expect_name(KindSet.of([TokenKind.Word]), "identifier after 'env.'");
                return EnvAccessExpr {
                    span: p.span_from(Mark { idx: env }),
                    env: env,
                    dot: dot,
                    name: name,
                };
            }
        }
    }
    if let kw: int = p.cur.eat(TokenKind.If) {
        return if_expr(p, kw, r);
    }
    if let kw: int = p.cur.eat(TokenKind.Match) {
        return match_expr(p, kw, r);
    }
    // In a match guard, `(x) => ...` is the guard's last operand and the arm's
    // arrow, not a lambda.
    let guard_close = if (r.match_guard && p.cur.at(TokenKind.LParen)) {
        matching_close(p.cur, p.cur.pos)
    } else {
        null
    };
    let lambda = p.cur.at(TokenKind.LParen)
        && looks_like_lambda(p.cur)
        && !(guard_close != null && p.cur.kind_at_sig(guard_close + 1) == TokenKind.FatArrow);
    let projection = p.cur.at(TokenKind.LParen) && !lambda && looks_like_qualified_projection(p.cur);
    if let l: int = p.cur.eat(TokenKind.LParen) {
        if (lambda) {
            return parse_lambda_expr(p, null, l);
        }
        if (projection) {
            return qualified_path_expr(p, l);
        }
        return paren_or_tuple(p, l);
    }
    if let l: int = p.cur.eat(TokenKind.LBracket) {
        return parse_array_literal(p, l);
    }
    let map = p.cur.at(TokenKind.LBrace) && looks_like_map(p.cur);
    if let l: int = p.cur.eat(TokenKind.LBrace) {
        return if (map) {
            parse_map_literal(p, null, l)
        } else {
            block(p, l)
        };
    }
    let generic_lt = if (p.cur.at(TokenKind.Less) && looks_like_generic_lambda(p.cur)) {
        p.cur.eat(TokenKind.Less)
    } else {
        null
    };
    if let lt: int = generic_lt {
        // Lambdas are function values and cannot declare generic parameters: the
        // list is parsed for its diagnostics and kept as a `Bogus`.
        let error = InvalidSyntax {
            message: "a lambda cannot declare generic parameters",
            range: p.cur.token_range(lt),
        };
        p.discard((p) -> {
            parse_generic_param_list(p, lt);
        });
        let rejected = p.bogus_since(Mark { idx: lt }, error);
        if let l: int = p.cur.eat(TokenKind.LParen) {
            return parse_lambda_expr(p, rejected, l);
        }
        return rejected;
    }
    if let head: int = p.cur.eat_in(EXPR_NAME) {
        return parse_path_expr(p, head);
    }
    p.missing("expression")
}

// port: baml_parser/src/expr.rs::impl Parse for PathExpr @ d9be6853b
// `x`, `a.b.c`: a name and the `.segment`s that follow it. The first segment
// must be a path-shaped word; later ones may be any member name, so
// `reflect.Class.extends` is one path. A `.` followed by nothing path-like
// right after the head is left to the member-access loop.
function parse_path_expr(p: Parser, head: int) -> PathExpr throws never {
    let mark = Mark { idx: head };
    let head_name = p.name(head);
    let segments: PathSegment[] = [];
    while (true) {
        if (looks_like_as_projection(p.cur)) {
            break;
        }
        let allowed = if (segments) {
            PATH_SEGMENT.union(MEMBER_NAME)
        } else {
            PATH_SEGMENT.union(KindSet.of([TokenKind.Client]))
        };
        let continues = p.cur.at(TokenKind.Dot) && p.cur.nth_in(1, allowed);
        if (p.cur.nth_in(1, NUMBER) || (!continues && !segments)) {
            break;
        }
        let dot = p.cur.eat(TokenKind.Dot);
        if (dot == null) {
            break;
        }
        let name = p.expect_name(allowed, "path segment after '.'");
        segments.push(PathSegment { dot: dot, name: name });
        if (name is Missing) {
            break;
        }
    }
    PathExpr { span: p.span_from(mark), head: head_name, segments: segments }
}

// ----- calls and literals --------------------------------------------------------------

// port: baml_parser/src/expr.rs::impl Parse for ArgList @ d9be6853b
function parse_arg_list(p: Parser, l: int) -> ArgList throws never {
    let args = p.sep_list(TokenKind.RParen, TokenKind.Comma, arg);
    let close = p.expect(TokenKind.RParen);
    ArgList { span: p.span_from(Mark { idx: l }), l: l, args: args, r: close }
}

// port: baml_parser/src/expr.rs::arg @ d9be6853b
// `value` or `label = value`; null (reported) when nothing here starts one.
function arg(p: Parser) -> Arg? throws never {
    let mark = p.cur.mark();
    let label: ArgLabel? = null;
    if (p.cur.at_in(EXPR_NAME) && p.cur.nth_is(1, TokenKind.Equals)) {
        if let name: Name = p.eat_name(EXPR_NAME) {
            if let eq: int = p.cur.eat(TokenKind.Equals) {
                label = ArgLabel { name: name, eq: eq };
            }
        }
    }
    if (label == null && !at_expression_start(p.cur)) {
        p.unexpected("expression");
        return null;
    }
    let value = operand(p, Restrictions.empty());
    Arg { span: p.span_from(mark), label: label, value: value }
}

// port: baml_parser/src/expr.rs::impl Parse for GenericArgs @ d9be6853b
// Expression-side `<T, U>`.
function parse_generic_args(p: Parser, l: int) -> GenericArgs throws never {
    let args = p.sep_list(TokenKind.Greater, TokenKind.Comma, (p) -> {
        ok(any_type(p))
    });
    let close = p.expect(TokenKind.Greater);
    GenericArgs { span: p.span_from(Mark { idx: l }), l: l, args: args, r: close }
}

// port: baml_parser/src/expr.rs::impl Parse for ArrayLiteral @ d9be6853b
// `[a, b c]`: commas between elements are optional.
function parse_array_literal(p: Parser, l: int) -> ArrayLiteral throws never {
    let elements: ArrayElement[] = [];
    while (!p.cur.at(TokenKind.RBracket) && !p.cur.at_end()) {
        let value = operand(p, Restrictions.empty());
        if (value is Missing) {
            // Reported; the token that is not an expression is skipped.
            p.cur.skip();
            continue;
        }
        let comma = p.cur.eat(TokenKind.Comma);
        elements.push(ArrayElement { value: value, comma: comma });
    }
    let close = p.expect(TokenKind.RBracket);
    ArrayLiteral { span: p.span_from(Mark { idx: l }), l: l, elements: elements, r: close }
}

// port: baml_parser/src/expr.rs::impl Parse for MapLiteral @ d9be6853b
// `{ k: v }` / `map { k: v }`: keys and values are expressions, colons
// required, commas canonical but omissible before an unambiguous next key.
function parse_map_literal(p: Parser, map_kw: int?, l: int) -> MapLiteral throws never {
    let mark = Mark { idx: map_kw ?? l };
    let entries = p.members(TokenKind.RBrace, STATEMENT_KEYWORD, EXPR_START, (p) -> Member<MapEntry>? {
        if (!at_expression_start(p.cur)) {
            p.unexpected("map key or '}'");
            return null;
        }
        let entry_mark = p.cur.mark();
        let key = expr(p, Restrictions.empty());
        if (key is Missing) {
            return null;
        }
        let colon = p.expect(TokenKind.Colon);
        let value = if (colon is Missing) {
            colon
        } else if (p.cur.at_in(STATEMENT_KEYWORD) || !at_expression_start(p.cur)) {
            p.missing("map value")
        } else {
            expr(p, Restrictions.empty())
        };
        let comma = p.cur.eat(TokenKind.Comma);
        Member {
            item: MapEntry {
                span: p.span_from(entry_mark),
                key: key,
                colon: colon,
                value: value,
                comma: comma,
            },
            missing_sep: if (comma == null) {
                "',' or '}' after map entry"
            } else {
                null
            },
        }
    });
    let close = p.expect(TokenKind.RBrace);
    MapLiteral { span: p.span_from(mark), map_kw: map_kw, l: l, entries: entries, r: close }
}

// port: baml_parser/src/expr.rs::OBJECT_MEMBER_START @ d9be6853b
// What may begin an object-literal member, for recovery.
const OBJECT_MEMBER_START: KindSet = EXPR_NAME.union(STRING_TOKEN).union(KindSet.of([TokenKind.BacktickStart, TokenKind.DotDotDot]));

// port: baml_parser/src/expr.rs::object_literal @ d9be6853b
// `Ctor { field: value, ...spread }` after the constructor and its `{`; `mark`
// is where the constructor began.
function object_literal(
    p: Parser,
    mark: Mark,
    ctor: AnyObjectCtor,
    l: int,
) -> ObjectLiteral throws never {
    let members = p.members(TokenKind.RBrace, STATEMENT_KEYWORD, OBJECT_MEMBER_START, (p) -> Member<AnyObjectMember>? {
        let member_mark = p.cur.mark();
        if let dots: int = p.cur.eat(TokenKind.DotDotDot) {
            let value = operand(p, Restrictions.empty());
            let comma = p.cur.eat(TokenKind.Comma);
            return Member {
                item: SpreadElement {
                    span: p.span_from(member_mark),
                    dots: dots,
                    value: value,
                    comma: comma,
                },
                missing_sep: if (comma == null) {
                    "',' or '}' after spread element"
                } else {
                    null
                },
            };
        }
        let key: AnyObjectKey = if let head: int = p.cur.eat_in(EXPR_NAME) {
            dotted_name(p, head, IDENT, "identifier")
        } else if let lit: StringLit = string_lit(p, StringSite.Expr) {
            lit
        } else if let open: int = p.cur.eat(TokenKind.BacktickStart) {
            parse_backtick_string(p, open)
        } else {
            p.unexpected("field name, spread element, or '}'");
            return null;
        };
        let shorthand = key is DottedName
            && !key.segments
            && (p.cur.at(TokenKind.Comma) || p.cur.at(TokenKind.RBrace));
        let colon = if (shorthand) {
            null
        } else {
            p.cur.eat(TokenKind.Colon)
        };
        let value: FieldValue? = null;
        if (colon != null) {
            let field_value = if (p.cur.at_in(STATEMENT_KEYWORD) || !at_expression_start(p.cur)) {
                p.missing("field value")
            } else {
                expr(p, Restrictions.empty())
            };
            value = FieldValue { colon: colon, value: field_value };
        }
        if (!shorthand && value == null) {
            p.unexpected("':'");
        }
        let comma = p.cur.eat(TokenKind.Comma);
        Member {
            item: ObjectField { span: p.span_from(member_mark), key: key, value: value, comma: comma },
            missing_sep: if (comma == null) {
                "',' or '}' after object field"
            } else {
                null
            },
        }
    });
    let close = p.expect(TokenKind.RBrace);
    ObjectLiteral { span: p.span_from(mark), ctor: ctor, l: l, members: members, r: close }
}

// ----- lambdas ------------------------------------------------------------------------

// port: baml_parser/src/expr.rs::impl Parse for LambdaExpr @ d9be6853b
// `params) -> R throws E { ... }` after its `(`, and after a rejected generic
// parameter list if there was one.
function parse_lambda_expr(
    p: Parser,
    rejected_generics: Bogus?,
    l: int,
) -> LambdaExpr throws never {
    let mark = if (rejected_generics != null) {
        p.mark_of(rejected_generics.span)
    } else {
        Mark { idx: l }
    };
    let params = param_list(p, l, Annotation.Optional);
    let arrow = p.expect_in(ANY_ARROW, "'->' after lambda parameters");
    let ret = if (p.cur.at(TokenKind.LBrace) || p.cur.at(TokenKind.Throws)) {
        null
    } else {
        ok(any_type(p))
    };
    let throws_ = if let kw: int = p.cur.eat(TokenKind.Throws) {
        parse_throws_clause(p, kw)
    } else {
        null
    };
    let body = body_block(p, "lambda body '{'");
    LambdaExpr {
        span: p.span_from(mark),
        rejected_generics: rejected_generics,
        params: params,
        arrow: arrow,
        ret: ret,
        throws_: throws_,
        body: body,
    }
}

// ----- control flow -----------------------------------------------------------------

// port: baml_parser/src/expr.rs::IfLike @ d9be6853b
// What an `if` parsed to; both an expression and an else-branch body.
type IfLike = IfExpr | IfLetExpr;

// port: baml_parser/src/expr.rs::if_expr @ d9be6853b
// After `if`: `c { } else ...` or `let p = s { } else ...`. The condition is
// parsed with a `{` reserved for the then-block.
function if_expr(p: Parser, kw: int, r: Restrictions) -> IfLike throws never {
    let mark = Mark { idx: kw };
    if (at_binding_intro(p.cur)) {
        if let introducer: int = p.cur.eat_in(LET_INTRODUCER) {
            // The pattern ends at `=`, so a destructure's `{` is never the body's.
            let pat = pattern_after_introducer(p, Restrictions.empty());
            let eq = p.expect_as(TokenKind.Equals, "'=' after if-let pattern");
            let scrutinee = if (eq is Missing) {
                eq
            } else {
                expr(p, r.before_body())
            };
            let then_branch = body_block(p, "block after if-let scrutinee");
            let otherwise = else_branch(p, r);
            return IfLetExpr {
                span: p.span_from(mark),
                kw: kw,
                introducer: introducer,
                pattern: pat,
                eq: eq,
                scrutinee: scrutinee,
                then_branch: then_branch,
                else_branch: otherwise,
            };
        }
    }
    let cond = operand(p, r.before_body());
    if_after_cond(p, mark, kw, cond, r)
}

// port: baml_parser/src/expr.rs::if_after_cond @ d9be6853b
// The branches of an `if` whose condition the caller has parsed (a template's
// `${if c}` tag is told from an if-expression by what follows the condition).
function if_after_cond(
    p: Parser,
    mark: Mark,
    kw: int,
    cond: AnyExpr | Missing,
    r: Restrictions,
) -> IfExpr throws never {
    let then_branch = body_block(p, "block after if condition");
    let otherwise = else_branch(p, r);
    IfExpr {
        span: p.span_from(mark),
        kw: kw,
        cond: cond,
        then_branch: then_branch,
        else_branch: otherwise,
    }
}

// port: baml_parser/src/expr.rs::else_branch @ d9be6853b
function else_branch(p: Parser, r: Restrictions) -> ElseBranch? throws never {
    let kw = p.cur.eat(TokenKind.Else)
        ?? return null;
    let body: AnyElse | Missing = if let if_kw: int = p.cur.eat(TokenKind.If) {
        if_expr(p, if_kw, r)
    } else if let l: int = p.cur.eat(TokenKind.LBrace) {
        block(p, l)
    } else {
        p.missing("'if' or block after 'else'")
    };
    ElseBranch { kw: kw, body: body }
}

// port: baml_parser/src/expr.rs::match_expr @ d9be6853b
// After `match`: `(x: T) { arms }` or `x { arms }`.
// deviation: Rust's `match_with_bare_tuple` only forwards to
// `match_with_scrutinee`, which is called directly.
function match_expr(p: Parser, kw: int, r: Restrictions) -> MatchExpr throws never {
    let scrutinee: AnyMatchScrutinee | Missing = if let l: int = p.cur.eat(TokenKind.LParen) {
        let first = operand(p, Restrictions.empty());
        if let sep: int = p.cur.eat(TokenKind.Comma) {
            let elements: SepItem<AnyExpr>[] = [];
            if (!(first is Missing)) {
                elements.push(SepItem { item: first, sep: sep });
            }
            while (!p.cur.at(TokenKind.RParen) && !p.cur.at_end()) {
                let item = operand(p, Restrictions.empty());
                if (item is Missing) {
                    break;
                }
                let item_sep = p.cur.eat(TokenKind.Comma);
                elements.push(SepItem { item: item, sep: item_sep });
                if (item_sep == null) {
                    break;
                }
            }
            let close = p.expect(TokenKind.RParen);
            let tuple = TupleExpr { span: p.span_from(Mark { idx: l }), l: l, elements: elements, r: close };
            let lbrace = p.expect_as(TokenKind.LBrace, "'{' after match scrutinee");
            return match_with_scrutinee(p, kw, tuple, lbrace);
        }
        let ascription = if let colon: int = p.cur.eat(TokenKind.Colon) {
            let ty = any_type(p);
            TypeAscription { span: p.span_from(Mark { idx: colon }), colon: colon, ty: ty }
        } else {
            null
        };
        let close = p.expect(TokenKind.RParen);
        MatchParen {
            span: p.span_from(Mark { idx: l }),
            l: l,
            expr: first,
            ascription: ascription,
            r: close,
        }
    } else {
        operand(p, r.before_body())
    };
    let l = p.expect_as(TokenKind.LBrace, "'{' after match scrutinee");
    match_with_scrutinee(p, kw, scrutinee, l)
}

// port: baml_parser/src/expr.rs::match_with_scrutinee @ d9be6853b
function match_with_scrutinee(
    p: Parser,
    kw: int,
    scrutinee: AnyMatchScrutinee | Missing,
    l: int | Missing,
) -> MatchExpr throws never {
    let arms: MatchArm[] = [];
    let saw_line = false;
    if (!(l is Missing)) {
        while (!p.cur.at(TokenKind.RBrace) && !p.cur.at_end() && !p.cur.at_in(ITEM_KEYWORD)) {
            saw_line = true;
            if (!at_pattern_start(p.cur)) {
                p.unexpected("pattern");
                p.cur.skip();
                continue;
            }
            let before = p.cur.pos;
            arms.push(match_arm(p));
            // An arm that consumed nothing must not be read again here.
            if (p.cur.pos == before) {
                p.cur.skip();
            }
        }
        if (!saw_line) {
            p.unexpected("at least one match arm");
        }
    }
    let close = if (l is Missing) {
        l
    } else {
        p.expect(TokenKind.RBrace)
    };
    MatchExpr {
        span: p.span_from(Mark { idx: kw }),
        kw: kw,
        scrutinee: scrutinee,
        l: l,
        arms: arms,
        r: close,
    }
}

// port: baml_parser/src/expr.rs::match_arm @ d9be6853b
// `pattern if guard => body,`: the body is a block when a `{` follows the
// arrow, else an expression that ends at the line's end.
function match_arm(p: Parser) -> MatchArm throws never {
    let mark = p.cur.mark();
    let pat = pattern(p, Restrictions.empty());
    let guard = if let kw: int = p.cur.eat(TokenKind.If) {
        MatchGuard {
            kw: kw,
            cond: operand(p, Restrictions { ...Restrictions.statement(), match_guard: true }),
        }
    } else {
        null
    };
    let arrow = p.expect_as(TokenKind.FatArrow, "'=>' after pattern");
    let body = arm_body(p);
    let comma = p.cur.eat(TokenKind.Comma);
    MatchArm {
        span: p.span_from(mark),
        pattern: pat,
        guard: guard,
        arrow: arrow,
        body: body,
        comma: comma,
    }
}

// port: baml_parser/src/expr.rs::arm_body @ d9be6853b
// The body of a `match`/`catch` arm after its `=>`.
function arm_body(p: Parser) -> AnyExpr | Missing throws never {
    if let l: int = p.cur.eat(TokenKind.LBrace) {
        return block(p, l);
    }
    operand(p, Restrictions.statement())
}

// port: baml_parser/src/expr.rs::catch_expr @ d9be6853b
// `body catch (e) { arms } catch_all (e) { arms }` after the first clause's
// keyword: every clause that follows joins the one expression.
function catch_expr(p: Parser, body: AnyExpr, kw: int) -> AnyExpr throws never {
    let mark = p.mark_of(node_span(body));
    let clauses = [parse_catch_clause(p, kw)];
    while let next: int = p.cur.eat_in(CATCH_KW) {
        clauses.push(parse_catch_clause(p, next));
    }
    CatchExpr { span: p.span_from(mark), body: body, clauses: clauses }
}

// port: baml_parser/src/expr.rs::impl Parse for CatchClause @ d9be6853b
function parse_catch_clause(p: Parser, kw: int) -> CatchClause throws never {
    let l = p.expect(TokenKind.LParen);
    let binding = if (l is Missing) {
        l
    } else {
        p.expect_name(IDENT, "catch binding identifier")
    };
    let trace: TraceBinding? = null;
    if (!(l is Missing)) {
        if let comma: int = p.cur.eat(TokenKind.Comma) {
            trace = TraceBinding { comma: comma, name: p.expect_name(IDENT, "identifier") };
        }
    }
    let close = if (l is Missing) {
        l
    } else {
        p.expect(TokenKind.RParen)
    };
    let lbrace = if (l is Missing) {
        l
    } else {
        p.expect_as(TokenKind.LBrace, "catch clause body")
    };
    let arms: CatchArm[] = [];
    let saw_line = false;
    if (!(lbrace is Missing)) {
        while (!p.cur.at(TokenKind.RBrace) && !p.cur.at_end() && !p.cur.at_in(ITEM_KEYWORD)) {
            saw_line = true;
            if (!at_pattern_start(p.cur)) {
                p.unexpected("pattern");
                p.cur.skip();
                continue;
            }
            let before = p.cur.pos;
            arms.push(catch_arm(p));
            // An arm that consumed nothing (a `-` that starts no pattern, the `=>`
            // found further ahead) must not be read again here.
            if (p.cur.pos == before) {
                p.cur.skip();
            }
        }
        if (!saw_line) {
            p.unexpected("at least one catch arm");
        }
    }
    let rbrace = if (lbrace is Missing) {
        lbrace
    } else {
        p.expect(TokenKind.RBrace)
    };
    CatchClause {
        span: p.span_from(Mark { idx: kw }),
        kw: kw,
        l: l,
        binding: binding,
        trace: trace,
        r: close,
        lbrace: lbrace,
        arms: arms,
        rbrace: rbrace,
    }
}

// port: baml_parser/src/expr.rs::catch_arm @ d9be6853b
function catch_arm(p: Parser) -> CatchArm throws never {
    let mark = p.cur.mark();
    let pat = pattern(p, Restrictions.empty());
    let arrow = p.expect_as(TokenKind.FatArrow, "'=>' after catch pattern");
    let body: AnyExpr | Missing = if (arrow is Missing) {
        // Skip to where the next arm (or the body's end) can begin.
        while (
            !p.cur.at_end()
                && !p.cur.at(TokenKind.RBrace)
                && !p.cur.at(TokenKind.Comma)
                && !looks_like_catch_arm_ahead(p.cur)
        ) {
            p.cur.skip();
        }
        arrow
    } else {
        arm_body(p)
    };
    let comma = p.cur.eat(TokenKind.Comma);
    CatchArm { span: p.span_from(mark), pattern: pat, arrow: arrow, body: body, comma: comma }
}

// port: baml_parser/src/expr.rs::spawn_expr @ d9be6853b
// `name with a, b { ... }` after `spawn`: the name and modifiers end before the
// body's `{`.
function spawn_expr(p: Parser, kw: int, r: Restrictions) -> SpawnExpr throws never {
    let name = if (p.cur.at(TokenKind.LBrace) || p.cur.at(TokenKind.With) || !at_expression_start(p.cur)) {
        null
    } else {
        ok(expr(p, r.before_body()))
    };
    let with = if let with_kw: int = p.cur.eat(TokenKind.With) {
        with_clause(p, with_kw, r.before_body())
    } else {
        null
    };
    let body = body_block(p, "'{' after spawn");
    SpawnExpr { span: p.span_from(Mark { idx: kw }), kw: kw, name: name, with: with, body: body }
}

// port: baml_parser/src/expr.rs::with_clause @ d9be6853b
// `a, b` before a `{` after `with`: on `spawn`, `test` and `testset`.
function with_clause(p: Parser, kw: int, r: Restrictions) -> WithClause throws never {
    let items = p.sep_list(TokenKind.LBrace, TokenKind.Comma, (p) -> AnyExpr? {
        if (at_expression_start(p.cur)) {
            return ok(expr(p, r));
        }
        p.unexpected("expression");
        null
    });
    WithClause { span: p.span_from(Mark { idx: kw }), kw: kw, items: items }
}

// port: baml_parser/src/expr.rs::paren_or_tuple @ d9be6853b
function paren_or_tuple(p: Parser, l: int) -> AnyExpr throws never {
    let first = operand(p, Restrictions.empty());
    let sep = p.cur.eat(TokenKind.Comma);
    if (sep == null) {
        let close = p.expect(TokenKind.RParen);
        return ParenExpr { span: p.span_from(Mark { idx: l }), l: l, inner: first, r: close };
    }
    let elements: SepItem<AnyExpr>[] = [];
    if (!(first is Missing)) {
        elements.push(SepItem { item: first, sep: sep });
    }
    while (!p.cur.at(TokenKind.RParen) && !p.cur.at_end()) {
        let item = operand(p, Restrictions.empty());
        if (item is Missing) {
            break;
        }
        let item_sep = p.cur.eat(TokenKind.Comma);
        elements.push(SepItem { item: item, sep: item_sep });
        if (item_sep == null) {
            break;
        }
    }
    let close = p.expect(TokenKind.RParen);
    TupleExpr { span: p.span_from(Mark { idx: l }), l: l, elements: elements, r: close }
}

// port: baml_parser/src/expr.rs::operand @ d9be6853b
// An expression that must begin here, or a reported `Missing`.
function operand(p: Parser, r: Restrictions) -> AnyExpr | Missing throws never {
    if (at_expression_start(p.cur)) {
        return expr(p, r);
    }
    p.missing("expression")
}
