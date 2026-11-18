// port: baml_parser/src/stmts.rs @ d9be6853b
//
// Blocks and statements. A block's statements are separated by lines; its
// value is the final expression with no `;`. A `//#` line in a block is a
// statement of its own.

// port: stmts.rs::block. The block its `{` opens, through its `}`. An
// unclosed block ends at an item keyword, which no statement can begin with.
function block(p: Parser, l: int) -> Block throws never {
    let lines = BodyLines { stmts: [], tail: null };
    // Too deep: the interior is skipped as reported, the block empty.
    if (p.enter_nesting("a block") == null) {
        lines = body_lines(p, null);
        p.leave_nesting();
    }
    let r = p.expect(TokenKind.RBrace);
    Block { span: p.span_from(Mark { idx: l }), l: l, stmts: lines.stmts, tail: lines.tail, r: r }
}

// port: stmts.rs::body_block. The `{ ... }` a construct's header is followed
// by, or the reported `Missing` named `expected`.
function body_block(p: Parser, expected: string) -> Block | Missing throws never {
    let l = p.cur.eat(TokenKind.LBrace)
        ?? return p.missing(expected);
    block(p, l)
}

// The lines of a body: its statements and its tail expression.
// deviation: Rust returns the tuple `(Vec<AnyStmt>, Option<AnyExpr>)`.
class BodyLines {
    stmts: AnyStmt[],
    tail: AnyExpr?,
}

// port: stmts.rs::body_lines. The lines of a body up to its `}` (or the end
// of the input, or an item keyword): the statements and the tail expression,
// if the last line is one with no `;`. `first` is an expression the caller
// already parsed as the body's first line.
function body_lines(p: Parser, first: AnyExpr?) -> BodyLines throws never {
    let stmts: AnyStmt[] = [];
    if (first != null) {
        match (expr_line(p, first)) {
            let line: LineStmt => {
                stmts.push(line.stmt);
            },
            let line: LineTail => {
                return BodyLines { stmts: stmts, tail: line.expr };
            },
        }
    }
    while (true) {
        header_stmts(p, stmts);
        if (p.cur.at(TokenKind.RBrace) || p.cur.at_end() || p.cur.at_in(ITEM_KEYWORD)) {
            break;
        }
        match (stmt(p)) {
            let line: LineStmt => {
                stmts.push(line.stmt);
            },
            let line: LineTail => {
                return BodyLines { stmts: stmts, tail: line.expr };
            },
        }
    }
    BodyLines { stmts: stmts, tail: null }
}

// port: stmts.rs::header_stmts. The `//#` lines between the last statement
// and the next token, each a statement.
function header_stmts(p: Parser, stmts: AnyStmt[]) -> void throws never {
    for (let token in p.cur.headers_ahead()) {
        stmts.push(
            p.out.header_stmt(
                HeaderStmt { span: TokenRange { start: token, end: token + 1 }, token: token },
            ),
        );
    }
}

// port: stmts.rs::Line. What one line of a block parsed to.
type Line = LineStmt | LineTail;

class LineStmt {
    stmt: AnyStmt,
}

// An expression with no `;` that the block's `}` follows: its value.
class LineTail {
    expr: AnyExpr,
}

// port: stmts.rs::stmt
function stmt(p: Parser) -> Line throws never {
    let semi = p.cur.eat(TokenKind.Semicolon);
    if (semi != null) {
        return LineStmt { stmt: EmptyStmt { span: p.span_from(Mark { idx: semi }), semi: semi } };
    }
    if (at_let_type(p.cur)) {
        let let_kw = p.cur.eat(TokenKind.Let);
        let type_kw = p.cur.eat(TokenKind.Type);
        if (let_kw != null && type_kw != null) {
            return LineStmt { stmt: parse_type_binding_stmt(p, let_kw, type_kw) };
        }
    }
    if (at_binding_intro(p.cur)) {
        let introducer = p.cur.eat_in(LET_INTRODUCER);
        if (introducer != null) {
            return LineStmt { stmt: let_stmt(p, introducer, Semi.Own) };
        }
    }
    if (at_removed_type_binding(p.cur)) {
        return LineStmt { stmt: removed_type_binding(p) };
    }
    let keyword = keyword_stmt(p);
    if (keyword != null) {
        return LineStmt { stmt: keyword };
    }
    if (p.cur.at_in(DOC_TOKEN)) {
        // Only a declaration is documented; a body has none.
        let mark = p.cur.mark();
        let range = p.cur.error_range();
        p.cur.skip();
        return LineStmt {
            stmt: p.bogus_since(
                mark,
                InvalidDirective {
                    message: "`///` doc comments and `//baml:` directives must directly precede the declaration they belong to; use `//` for a plain comment",
                    range: range,
                },
            ),
        };
    }
    if (at_expression_start(p.cur)) {
        return match (stmt_expr(p, Restrictions.statement())) {
            let _missing: Missing => baml.sys.panic("an expression starts here"),
            let expr: AnyExpr => expr_line(p, expr),
        };
    }
    LineStmt { stmt: p.bogus_one("expression") }
}

// The `while`/`for`/`defer`/`test` arms of `stmt`: a statement its keyword
// begins, or null when none does here.
// deviation: split out of `stmt`'s if-chain.
function keyword_stmt(p: Parser) -> AnyStmt? throws never {
    let while_kw = p.cur.eat(TokenKind.While);
    if (while_kw != null) {
        return while_stmt(p, while_kw);
    }
    let for_kw = p.cur.eat(TokenKind.For);
    if (for_kw != null) {
        return parse_for_stmt(p, for_kw);
    }
    let defer_kw = p.cur.eat(TokenKind.Defer);
    if (defer_kw != null) {
        return parse_defer_stmt(p, defer_kw);
    }
    let test_kw = p.cur.eat_in(TEST_KW)
        ?? return null;
    test_def(p, [], test_kw, TestPosition.Stmt)
}

// port: stmts.rs::expr_line. The line an expression makes: an assignment
// when an assignment operator follows it; the body's tail when nothing but
// the `}` follows it; else a statement with its `;` if it has one.
function expr_line(p: Parser, expr: AnyExpr) -> Line throws never {
    let mark = p.mark_of(node_span(expr));
    let op = p.cur.eat_assign_op();
    if (op != null) {
        return LineStmt { stmt: assign_stmt(p, mark, expr, op, Restrictions.statement(), Semi.Own) };
    }
    let semi = p.cur.eat(TokenKind.Semicolon);
    let closes = p.cur.at(TokenKind.RBrace) || p.cur.at_end();
    if (semi == null && closes && !p.cur.header_ahead()) {
        return LineTail { expr: expr };
    }
    LineStmt { stmt: ExprStmt { span: p.span_from(mark), expr: expr, semi: semi } }
}

// port: stmts.rs::assign_stmt. `value;` after `target op`: the value is an
// expression, so a second assignment operator in it is reported (assignment
// does not chain).
function assign_stmt(
    p: Parser,
    mark: Mark,
    target: AnyExpr,
    op: AssignOpTok,
    r: Restrictions,
    semi: Semi,
) -> AssignStmt throws never {
    let value = expr(p, r);
    let semi_token = if (semi == Semi.Own) {
        p.cur.eat(TokenKind.Semicolon)
    } else {
        null
    };
    AssignStmt { span: p.span_from(mark), target: target, op: op, value: value, semi: semi_token }
}

// port: stmts.rs::at_let_type. `let type Name ...`: a `let` whose binding is
// simply named `type` has no name after it.
function at_let_type(cur: Cursor) -> bool throws never {
    cur.at(TokenKind.Let) && cur.nth_is(1, TokenKind.Type) && cur.nth_is_ident(2)
}

// port: stmts.rs::Semi. Whether a `let` or assignment statement owns its `;`:
// not in a C-style `for` header, where the header does (and the step has
// none).
enum Semi {
    Own,
    Leave,
}

// port: stmts.rs::let_stmt. `let pattern = init else { ... };` after its
// `let`/`const`.
function let_stmt(p: Parser, introducer: int, semi: Semi) -> LetStmt throws never {
    let pattern = pattern_after_introducer(p, Restrictions.empty());
    let eq = p.expect_as(TokenKind.Equals, "initializer (=)");
    let init = match (eq) {
        let missing: Missing => missing,
        _ => expr(p, Restrictions.statement()),
    };
    let else_branch: LetElse? = null;
    let else_kw = p.cur.eat(TokenKind.Else);
    if (else_kw != null) {
        // `else if` has no value to chain through; the `if` is left for the
        // next statement.
        let else_block = if (p.cur.at(TokenKind.If)) {
            p.missing("block after 'else' (`else if` is not valid in let-else)")
        } else {
            body_block(p, "block after 'else'")
        };
        else_branch = LetElse { kw: else_kw, block: else_block };
    }
    let semi_token = if (semi == Semi.Own) {
        p.cur.eat(TokenKind.Semicolon)
    } else {
        null
    };
    LetStmt {
        span: p.span_from(Mark { idx: introducer }),
        introducer: introducer,
        pattern: pattern,
        eq: eq,
        init: init,
        else_branch: else_branch,
        semi: semi_token,
    }
}

// port: stmts.rs::impl Parse for TypeBindingStmt. `let type T extends A & B =
// operand else { ... };`: the `else` runs when the type misses a bound, so it
// is meaningful only on the bounded form.
function parse_type_binding_stmt(
    p: Parser,
    let_kw: int,
    type_kw: int,
) -> TypeBindingStmt throws never {
    let name = p.expect_name(IDENT, "type binding name");
    let extends_kw = p.cur.eat(TokenKind.Extends);
    let bounds = if (extends_kw != null) {
        parse_generic_param_bounds(p, extends_kw)
    } else {
        null
    };
    let eq = p.expect_as(TokenKind.Equals, "'=' and the runtime type");
    let init = match (eq) {
        let missing: Missing => missing,
        _ => expr(p, Restrictions.statement()),
    };
    if (p.cur.at(TokenKind.Else) && bounds == null) {
        p.error_here(
            "`else` runs when the type misses a bound; add `extends` bounds or remove the `else` block",
        );
    }
    let else_branch: LetElse? = null;
    let else_kw = p.cur.eat(TokenKind.Else);
    if (else_kw != null) {
        else_branch = LetElse { kw: else_kw, block: body_block(p, "block after 'else'") };
    }
    let semi = p.cur.eat(TokenKind.Semicolon);
    TypeBindingStmt {
        span: p.span_from(Mark { idx: let_kw }),
        let_kw: let_kw,
        type_kw: type_kw,
        name: name,
        bounds: bounds,
        eq: eq,
        init: init,
        else_branch: else_branch,
        semi: semi,
    }
}

// port: stmts.rs::at_removed_type_binding. The removed body-level `type Name
// = ...` statement: `type` is contextual in expressions, so only the
// complete head claims the position.
function at_removed_type_binding(cur: Cursor) -> bool throws never {
    cur.at(TokenKind.Type) && cur.nth_is_ident(1) && cur.nth_is(2, TokenKind.Equals)
}

// port: stmts.rs::removed_type_binding. E0098 for a removed `type T = ...;`
// statement, spelling the `let type` replacement. The right-hand side is read
// as a type only to find where the statement ends; nothing inside it is kept
// or reported, as the statement's own diagnostic covers it.
function removed_type_binding(p: Parser) -> Bogus throws never {
    let mark = p.cur.mark();
    let name = p.cur.text_at(1) ?? "";
    let rhs_tokens = p.probe((p) -> {
        // `type`, the name, `=`.
        p.cur.skip();
        p.cur.skip();
        p.cur.skip();
        let rhs_mark = p.cur.mark();
        any_type(p);
        let range = p.cur.range_from(rhs_mark);
        p.cur.eat(TokenKind.Semicolon);
        range
    });
    let rhs = p.cur.text_of_range(rhs_tokens).trim();
    let operand = whole_unreflect_operand(rhs);
    let removed = `body-level \`type ${name} = …\` bindings were removed;`;
    let message = if (operand != null) {
        `${removed} write \`let type ${name} = ${operand};\` instead`
    } else if (rhs.includes("unreflect")) {
        // Spelling the replacement verbatim would keep the removed `unreflect`
        // inside it.
        `${removed} bind each \`unreflect\` operand with \`let type U = <expr>;\` first, then write \`let type ${name} = reflect.Type.of<…>();\` naming \`U\``
    } else {
        `${removed} write \`let type ${name} = reflect.Type.of<${rhs}>();\` instead`
    };
    let range = p.cur.text_range(p.cur.range_from(mark));
    p.bogus_since(mark, RemovedFeature { message: message, range: range })
}

// port: stmts.rs::whole_unreflect_operand. The operand of a right-hand side
// that is exactly `unreflect(<operand>)`; a multi-line operand is elided
// rather than reflowed.
function whole_unreflect_operand(rhs: string) -> string? throws never {
    if (!rhs.starts_with("unreflect")) {
        return null;
    }
    let after = rhs.slice("unreflect".length(), rhs.length()).trim_start();
    if (!after.starts_with("(") || !after.ends_with(")") || after.length() < 2) {
        return null;
    }
    let inner = after.slice(1, after.length() - 1);
    // `unreflect(a) | unreflect(b)` also starts and ends with the marker's
    // parentheses; only a balanced interior is one operand.
    let depth = 0;
    for (let ch in inner.chars()) {
        if (ch == "(") {
            depth += 1;
        } else if (ch == ")") {
            depth -= 1;
            if (depth < 0) {
                return null;
            }
        }
    }
    let trimmed = inner.trim();
    if (depth != 0 || !trimmed) {
        return null;
    }
    if (trimmed.includes("\n")) {
        "…"
    } else {
        trimmed
    }
}

// port: stmts.rs::while_stmt. After `while`: `while c { }` or `while let p =
// s { }`.
function while_stmt(p: Parser, kw: int) -> AnyStmt throws never {
    let r = Restrictions.statement().before_body();
    if (at_binding_intro(p.cur)) {
        let introducer = p.cur.eat_in(LET_INTRODUCER);
        if (introducer != null) {
            // The pattern ends at `=`, so a destructure's `{` is never the body's.
            let pattern = pattern_after_introducer(p, Restrictions.empty());
            let eq = p.expect_as(TokenKind.Equals, "'=' after while-let pattern");
            let scrutinee = match (eq) {
                let missing: Missing => missing,
                _ => expr(p, r),
            };
            let body = body_block(p, "block after while-let scrutinee");
            return WhileLetStmt {
                span: p.span_from(Mark { idx: kw }),
                kw: kw,
                introducer: introducer,
                pattern: pattern,
                eq: eq,
                scrutinee: scrutinee,
                body: body,
            };
        }
    }
    let cond = if (at_expression_start(p.cur)) {
        expr(p, r)
    } else {
        p.missing("expression")
    };
    let body = body_block(p, "block after while condition");
    WhileStmt { span: p.span_from(Mark { idx: kw }), kw: kw, cond: cond, body: body }
}

// port: stmts.rs::impl Parse for ForStmt. After `for`: `for (let x in xs) {
// }`, `for let x in xs { }`, or `for (init; cond; step) { }`.
function parse_for_stmt(p: Parser, kw: int) -> ForStmt throws never {
    let header = for_header(p, Restrictions.statement().before_body());
    let body = body_block(p, "block after for expression");
    ForStmt { span: p.span_from(Mark { idx: kw }), kw: kw, header: header, body: body }
}

// port: stmts.rs::for_header. After `for`: the header in one of its three
// shapes. `bare` is how the unparenthesized forms read their expressions (a
// `{` after them is the loop body, or a template tag's `}` follows).
function for_header(p: Parser, bare: Restrictions) -> AnyForHeader throws never {
    let l = p.cur.eat(TokenKind.LParen);
    if (l != null) {
        if (at_binding_intro(p.cur) && looks_like_for_in(p.cur)) {
            let introducer = p.cur.eat_in(LET_INTRODUCER);
            if (introducer != null) {
                let header = for_in_header(p, introducer, Restrictions.empty());
                let r = p.expect(TokenKind.RParen);
                return ParenForInHeader { span: p.span_from(Mark { idx: l }), l: l, header: header, r: r };
            }
        }
        return c_for_header(p, Mark { idx: l }, l, Restrictions.empty());
    }
    let mark = p.cur.mark();
    if (at_binding_intro(p.cur) && looks_like_for_in(p.cur)) {
        let introducer = p.cur.eat_in(LET_INTRODUCER);
        if (introducer != null) {
            return for_in_header(p, introducer, bare);
        }
    }
    // `for x in xs` without its `let`: the one thing wrong is named, and the
    // header is given up to where its body or tag closes.
    if (p.cur.at_ident() && p.cur.nth_is(1, TokenKind.In)) {
        let error = p.unexpected_error("'let'");
        p.cur.skip_until(
            KindSet.of([TokenKind.LBrace, TokenKind.RBrace, TokenKind.RParen]),
            angles_nest = false,
        );
        return p.bogus_since(mark, error);
    }
    // A C-style header whose `(` is missing: parsed as one, so its parts stay
    // inside the loop.
    c_for_header(p, mark, p.missing("'('"), bare)
}

// port: stmts.rs::for_in_header. `pattern in iterable` after its
// `let`/`const`, the lookahead having seen the `in`.
function for_in_header(p: Parser, introducer: int, r: Restrictions) -> ForInHeader throws never {
    let pattern = pattern_after_introducer(p, Restrictions.empty());
    let in_kw = p.expect(TokenKind.In);
    let iter = if (at_expression_start(p.cur)) {
        expr(p, r)
    } else {
        p.missing("expression")
    };
    ForInHeader {
        span: p.span_from(Mark { idx: introducer }),
        introducer: introducer,
        pattern: pattern,
        in_kw: in_kw,
        iter: iter,
    }
}

// port: stmts.rs::c_for_header. `init; cond; step)` after the `(` (`l`),
// every part optional. With the `(` missing, the `)` is not demanded either.
function c_for_header(
    p: Parser,
    mark: Mark,
    l: int | Missing,
    r: Restrictions,
) -> CForHeader throws never {
    let init = c_for_init(p, r);
    let semi1 = p.cur.eat(TokenKind.Semicolon);
    let cond = if (!p.cur.at(TokenKind.LBrace) && at_expression_start(p.cur)) {
        ok(expr(p, r))
    } else {
        null
    };
    let semi2 = p.cur.eat(TokenKind.Semicolon);
    let step = if (!p.cur.at(TokenKind.LBrace) && at_expression_start(p.cur)) {
        c_for_step(p, r)
    } else {
        null
    };
    let close = match (l) {
        let missing: Missing => p.cur.eat(TokenKind.RParen) ?? missing,
        _ => p.expect(TokenKind.RParen),
    };
    CForHeader {
        span: p.span_from(mark),
        l: l,
        init: init,
        semi1: semi1,
        cond: cond,
        semi2: semi2,
        step: step,
        r: close,
    }
}

// The `init` part of `c_for_header`: a `let` statement that leaves its `;`
// to the header, or an expression.
function c_for_init(p: Parser, r: Restrictions) -> AnyForInit? throws never {
    if (at_binding_intro(p.cur)) {
        let introducer = p.cur.eat_in(LET_INTRODUCER);
        if (introducer != null) {
            return let_stmt(p, introducer, Semi.Leave);
        }
    }
    if (at_expression_start(p.cur)) {
        ok(expr(p, r))
    } else {
        null
    }
}

// The `step` part of `c_for_header`: an assignment with no `;`, or an
// expression.
function c_for_step(p: Parser, r: Restrictions) -> AnyForStep? throws never {
    let target = ok(stmt_expr(p, r))
        ?? return null;
    let op = p.cur.eat_assign_op()
        ?? return target;
    assign_stmt(p, p.mark_of(node_span(target)), target, op, r, Semi.Leave)
}

// port: stmts.rs::impl Parse for DeferStmt. `defer { ... }`: the body is
// always a block.
function parse_defer_stmt(p: Parser, kw: int) -> DeferStmt throws never {
    let body = body_block(p, "'{' after defer");
    DeferStmt { span: p.span_from(Mark { idx: kw }), kw: kw, body: body }
}
