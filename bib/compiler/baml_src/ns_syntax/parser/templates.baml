// port: baml_parser/src/templates.rs @ d9be6853b
//
// Backtick templates (`BacktickString`): text chunks, `${ ... }`
// interpolations (block bodies), and the structural `${for ...}`/`${if ...}`
// blocks with their bodies nested inside. A block tag that cannot belong where
// it is (a stray `${endfor}`, a second `${else}`) is a `Bogus` part with the
// diagnostic lowering used to report for it; a wrong end tag closes the
// innermost block and is reported as a mismatch, as lowering did.
//
// The lexer has already settled what is text and where the delimiters are:
// the parser sees `BacktickStart`, `TemplateChunk`s, `${` openers whose bodies
// are ordinary code up to their `}`, and the `BacktickEnd` (or not, for an
// unclosed template).

// port: templates.rs::Tag. What a `${` opens, by the tokens right after it.
// `endfor`/`endif` are contextual: only alone before the `}` are they tags.
enum Tag {
    For,
    If,
    ElseIf,
    Else,
    Endfor,
    Endif,
    // An expression or statements.
    Interp,
}

// port: templates.rs::tag_at
function tag_at(cur: Cursor) -> Tag throws never {
    match (cur.kind(1)) {
        TokenKind.For => Tag.For,
        TokenKind.If => Tag.If,
        TokenKind.Else if cur.nth_is(2, TokenKind.If) => Tag.ElseIf,
        TokenKind.Else => Tag.Else,
        TokenKind.Endfor if cur.nth_is(2, TokenKind.RBrace) => Tag.Endfor,
        TokenKind.Endif if cur.nth_is(2, TokenKind.RBrace) => Tag.Endif,
        _ => Tag.Interp,
    }
}

// port: templates.rs::Body. Whose parts are being read: decides which tags
// end the run and which are errors there.
enum Body {
    // The template itself: every closing tag is stray.
    Template,
    // A `${for}` block: an end tag closes it, `${else}` is stray.
    For,
    // An `${if}`/`${else if}` branch: `${else}`, `${else if}` and the end tags
    // all end it.
    IfThen,
    // The `${else}` branch: a further `${else}`/`${else if}` is out of order.
    IfElse,
}

// port: templates.rs::impl Parse for BacktickString. The whole template after
// its opener.
function parse_backtick_string(p: Parser, open: int) -> BacktickString throws never {
    let ticks = p.cur.text_of(open).byte_length();
    let parts = parts(p, Body.Template);
    // An N-tick opener with no close runs to the end of the file (BEP-049 §8);
    // the usual intent behind a bare double-backtick is an empty string.
    let expected = if (ticks >= 2) {
        `Unclosed backtick string (expected ${"`".repeat(ticks)}); use "" for an empty string (BEP-049 §8)`
    } else {
        "Unclosed backtick string (expected `)"
    };
    // Reported at the opener: the close is missing where the template began,
    // not at the end of the file it ran to.
    let close = p.cur.eat(TokenKind.BacktickEnd) ?? p.missing_because(expected, p.cur.token_range(open));
    BacktickString { span: p.span_from(Mark { idx: open }), open: open, parts: parts, close: close }
}

// port: templates.rs::parts. The parts of `body` up to the tag that ends it,
// the template's close, or the end of the input.
function parts(p: Parser, body: Body) -> AnyTemplatePart[] throws never {
    let parts: AnyTemplatePart[] = [];
    while (!p.cur.at_end() && !p.cur.at(TokenKind.BacktickEnd)) {
        let token = p.cur.eat(TokenKind.TemplateChunk);
        if (token != null) {
            // Escapes are checked chunk by chunk: a chunk is one run of literal
            // text, and an escape never spans a `${`.
            let issues = root.base.backtick_string_literal_escape_issues(p.cur.text_of(token));
            let start = p.cur.token_range(token).start;
            report_escape_issues_from(p, start, issues, RawStringFix.Offered);
            parts.push(AnyTemplatePartChunk { token: token });
            continue;
        }
        if (!p.cur.at(TokenKind.DollarLBrace)) {
            // Code left over after an interpolation lost its `}` (reported there):
            // skipped up to the next part.
            p.cur.skip();
            continue;
        }
        let tag = tag_at(p.cur);
        let ends_body = match (tag) {
            Tag.Endfor | Tag.Endif => body != Body.Template,
            Tag.Else | Tag.ElseIf => body == Body.IfThen,
            _ => false,
        };
        if (ends_body) {
            break;
        }
        let stray = stray_message(tag, body);
        let open = p.cur.eat(TokenKind.DollarLBrace);
        if (open == null) {
            p.cur.skip();
            continue;
        }
        if (stray != null) {
            parts.push(stray_tag(p, open, stray));
            continue;
        }
        let for_kw = p.cur.eat(TokenKind.For);
        if (for_kw != null) {
            parts.push(parse_template_for(p, open, for_kw));
        } else {
            parts.push(interpolation(p, open));
        }
    }
    parts
}

// The stray-tag arms of `parts`' match: the message for a tag with no place
// in `body`, or null when the tag belongs there. Only called for a tag that
// does not end `body`.
// deviation: Rust matches `(tag, body)` once, breaking in the ending arms;
// here `parts` tests those first.
function stray_message(tag: Tag, body: Body) -> string? throws never {
    match (tag) {
        Tag.Endfor => "stray ${endfor} with no matching ${for}",
        Tag.Endif => "stray ${endif} with no matching ${if}",
        Tag.Else if body == Body.IfElse => "duplicate ${else} in the same ${if} chain",
        Tag.Else => "stray ${else} outside an ${if} block",
        Tag.ElseIf if body == Body.IfElse => "${else if} after ${else} in the same ${if} chain",
        Tag.ElseIf => "stray ${else if} outside an ${if} block",
        Tag.For | Tag.If | Tag.Interp => null,
    }
}

// port: templates.rs::stray_tag. After the `${` of a tag with no place here:
// the whole tag through its `}` as a `Bogus`, reported with `message`.
function stray_tag(p: Parser, open: int, message: string) -> Bogus throws never {
    let mark = Mark { idx: open };
    let close = matching_close(p.cur, p.cur.sig_index(open));
    while (true) {
        let kind = p.cur.kind(0)
            ?? break;
        let past_close = close != null && p.cur.pos > close;
        if (past_close || (close == null && kind == TokenKind.BacktickEnd)) {
            break;
        }
        p.cur.skip();
    }
    let range = p.cur.text_range(p.cur.range_from(mark));
    p.bogus_since(mark, InvalidSyntax { message: message, range: range })
}

// port: templates.rs::interpolation. After a `${` that is not a `for` or
// closing tag: an interpolation, or an `${if c}` block tag, told apart after
// the condition is parsed: a `}` closes a tag, a `{` opens an
// if-expression's then-block.
function interpolation(p: Parser, open: int) -> AnyTemplatePart throws never {
    let mark = Mark { idx: open };
    let first: AnyExpr? = null;
    // `${if let ...}` is an if-let expression: there is no such tag.
    if (p.cur.at(TokenKind.If) && !binding_intro_at(p.cur, 1)) {
        let kw = p.cur.eat(TokenKind.If);
        if (kw != null) {
            let cond = if (at_expression_start(p.cur)) {
                expr(p, Restrictions.empty().before_body())
            } else {
                p.missing("expression")
            };
            if (!p.cur.at(TokenKind.LBrace)) {
                let close = p.expect(TokenKind.RBrace);
                let if_open = TemplateIfOpen {
                    span: p.span_from(mark),
                    open: open,
                    kw: kw,
                    cond: cond,
                    close: close,
                };
                return template_if(p, mark, if_open);
            }
            let if_expr = if_after_cond(p, Mark { idx: kw }, kw, cond, Restrictions.statement());
            first = expr_from(p, if_expr, Restrictions.statement());
        }
    }
    let lines = body_lines(p, first);
    let close = p.expect(TokenKind.RBrace);
    TemplateInterp {
        span: p.span_from(mark),
        open: open,
        stmts: lines.stmts,
        tail: lines.tail,
        close: close,
    }
}

// port: templates.rs::Block. Which block an end tag is expected to close.
// deviation: named `TemplateBlock`, as `Block` is the block node.
enum TemplateBlock {
    For,
    If,
}

// port: templates.rs::impl Parse for TemplateFor. The block after its
// `${for`, through its `${endfor}`.
function parse_template_for(p: Parser, open: int, kw: int) -> TemplateFor throws never {
    let mark = Mark { idx: open };
    let for_open = parse_template_for_open(p, open, kw);
    let open_range = p.cur.text_range(for_open.span);
    let body = parts(p, Body.For);
    let close = end_tag(p, TemplateBlock.For, open_range);
    TemplateFor { span: p.span_from(mark), open: for_open, body: body, close: close }
}

// port: templates.rs::impl Parse for TemplateForOpen. `${for header}`: the
// tag opening a loop block.
function parse_template_for_open(p: Parser, open: int, kw: int) -> TemplateForOpen throws never {
    // Inside the tag a `{` cannot be a body, only the `}` ends it; the bare
    // iterable keeps a brace literal out of the way all the same.
    let header = for_header(p, Restrictions.empty().before_body());
    let close = p.expect(TokenKind.RBrace);
    TemplateForOpen {
        span: p.span_from(Mark { idx: open }),
        open: open,
        kw: kw,
        header: header,
        close: close,
    }
}

// port: templates.rs::impl Parse for TemplateElif. `${else if c}` and the
// parts it guards.
function parse_template_elif(
    p: Parser,
    open: int,
    else_kw: int,
    if_kw: int,
) -> TemplateElif throws never {
    let cond = if (at_expression_start(p.cur)) {
        expr(p, Restrictions.empty().before_body())
    } else {
        p.missing("expression")
    };
    let close = p.expect(TokenKind.RBrace);
    let parts = parts(p, Body.IfThen);
    TemplateElif {
        span: p.span_from(Mark { idx: open }),
        open: open,
        else_kw: else_kw,
        if_kw: if_kw,
        cond: cond,
        close: close,
        parts: parts,
    }
}

// port: templates.rs::impl Parse for TemplateElse. `${else}` and the parts it
// guards.
function parse_template_else(p: Parser, open: int, kw: int) -> TemplateElse throws never {
    let close = p.expect(TokenKind.RBrace);
    let parts = parts(p, Body.IfElse);
    TemplateElse {
        span: p.span_from(Mark { idx: open }),
        open: open,
        kw: kw,
        close: close,
        parts: parts,
    }
}

// port: templates.rs::template_if. After the `${if c}` tag `open` at `mark`:
// the branches through `${endif}`.
function template_if(p: Parser, mark: Mark, open: TemplateIfOpen) -> TemplateIf throws never {
    let open_range = p.cur.text_range(open.span);
    let then_parts = parts(p, Body.IfThen);
    let elifs: TemplateElif[] = [];
    while (p.cur.at(TokenKind.DollarLBrace) && tag_at(p.cur) == Tag.ElseIf) {
        let elif_open = p.cur.eat(TokenKind.DollarLBrace);
        let else_kw = p.cur.eat(TokenKind.Else);
        let if_kw = p.cur.eat(TokenKind.If);
        if (elif_open == null || else_kw == null || if_kw == null) {
            break;
        }
        elifs.push(parse_template_elif(p, elif_open, else_kw, if_kw));
    }
    let else_part: TemplateElse? = null;
    if (p.cur.at(TokenKind.DollarLBrace) && tag_at(p.cur) == Tag.Else) {
        let else_open = p.cur.eat(TokenKind.DollarLBrace);
        let kw = p.cur.eat(TokenKind.Else);
        if (else_open != null && kw != null) {
            else_part = parse_template_else(p, else_open, kw);
        }
    }
    let close = end_tag(p, TemplateBlock.If, open_range);
    TemplateIf {
        span: p.span_from(mark),
        open: open,
        then_parts: then_parts,
        elifs: elifs,
        else_part: else_part,
        close: close,
    }
}

// port: templates.rs::end_tag. The end tag closing a block of kind
// `expected`, whose open tag spans `open_range`. The other end tag closes the
// block too, with a mismatch reported at it; no end tag at all leaves the
// block unclosed, reported at its open tag.
function end_tag(
    p: Parser,
    expected: TemplateBlock,
    open_range: TextRange,
) -> TemplateEndTag | Missing throws never {
    let unclosed = match (expected) {
        TemplateBlock.For => "unclosed ${for} block — expected ${endfor}",
        TemplateBlock.If => "unclosed ${if} block — expected ${endif}",
    };
    if (
        !(
            p.cur.at(TokenKind.DollarLBrace)
                && (tag_at(p.cur) == Tag.Endfor || tag_at(p.cur) == Tag.Endif)
        )
    ) {
        return p.missing_because(unclosed, open_range);
    }
    let open = p.cur.eat(TokenKind.DollarLBrace);
    let kw = p.cur.eat_in(END_TAG_KW);
    if (open == null || kw == null) {
        return p.missing_because(unclosed, open_range);
    }
    let close = p.expect(TokenKind.RBrace);
    let node = TemplateEndTag { span: p.span_from(Mark { idx: open }), open: open, kw: kw, close: close };
    let closes_for = p.cur.tokens().kinds[kw] == TokenKind.Endfor;
    let mismatch = match (expected) {
        TemplateBlock.For if !closes_for => "${for} block closed by ${endif} — expected ${endfor}",
        TemplateBlock.If if closes_for => "${if} block closed by ${endfor} — expected ${endif}",
        _ => null,
    };
    if (mismatch != null) {
        p.error(mismatch, p.cur.text_range(node.span));
    }
    node
}
