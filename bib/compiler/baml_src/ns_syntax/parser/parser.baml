// port: baml_parser/src/parser.rs @ d9be6853b
//
// The parser: a `Cursor` over the tokens, a `Sink` for the diagnostics, and
// the combinators that need both. Grammar code lives in the grammar files as
// free functions over `p`.
//
// Rust's `impl Parse for X { fn parse(p, head) }` is `parse_x(p, head)` here.
// Rust allocates a node with `p.alloc(mark, X { .. })`; here the grammar
// writes `X { span: p.span_from(mark), .. }`.

// port: parser.rs::MAX_NESTING. The deepest nesting of expressions, types,
// patterns and blocks the parser reads; past it the construct is reported and
// skipped.
const MAX_NESTING: int = 128;

// A list member and, when it found no separator after it, the message for one
// being required there ("',' or '}' after ...").
class Member<T> {
    item: T,
    missing_sep: string?,
}

class Parser {
    cur: Cursor,
    out: Sink,
    // How many expressions, types, patterns and blocks are open.
    depth: int,

    function new(cur: Cursor, out: Sink) -> Parser throws never {
        Parser { cur: cur, out: out, depth: 0 }
    }

    // port: Parser::alloc. The span of a node from `mark` to the last consumed
    // token.
    function span_from(self, mark: Mark) -> TokenRange throws never {
        self.cur.range_from(mark)
    }

    // port: Parser::eat_name. A `Name` from the current token if its kind is in
    // `set` (a subset of the name tokens): the position decides which names it
    // accepts.
    function eat_name(self, set: KindSet) -> Name? throws never {
        let token = self.cur.eat_in(set)
            ?? return null;
        self.name(token)
    }

    // port: Parser::name. The `Name` node of a consumed name token: exactly that
    // token, however much has been read since.
    function name(self, token: int) -> Name throws never {
        Name { span: TokenRange { start: token, end: token + 1 }, token: token }
    }

    // port: Parser::expect_name. A `Name` from `set`, or a reported `Missing`
    // named `expected`.
    function expect_name(self, set: KindSet, expected: string) -> Name | Missing throws never {
        self.eat_name(set) ?? self.missing(expected)
    }

    // port: Parser::mark_of. Where a node starts: the mark for a wrapper built
    // around it after it was parsed (a binary expression around its left
    // operand).
    function mark_of(self, span: TokenRange) -> Mark throws never {
        Mark { idx: span.start }
    }

    // ----- diagnostics at the cursor --------------------------------------------------

    // "Expected `expected`, found <the current token>".
    function unexpected_error(self, expected: string) -> ParseError throws never {
        let range = self.cur.error_range();
        let kind = self.cur.kind(0);
        if (kind == null) {
            return UnexpectedEof { expected: expected, range: range };
        }
        UnexpectedToken { expected: expected, found: found_name(kind), range: range }
    }

    // Report "expected ..., found ..." at the current token and continue.
    function unexpected(self, expected: string) -> void throws never {
        self.out.report(self.unexpected_error(expected));
    }

    function error(self, message: string, range: TextRange) -> void throws never {
        self.out.report(InvalidSyntax { message: message, range: range });
    }

    function error_here(self, message: string) -> void throws never {
        self.error(message, self.cur.error_range());
    }

    function removed(self, message: string, range: TextRange) -> void throws never {
        self.out.report(RemovedFeature { message: message, range: range });
    }

    // ----- missing ---------------------------------------------------------------------

    // port: expect::<K>. The token, or a reported `Missing` named by the
    // token's own spelling.
    function expect(self, kind: TokenKind) -> int | Missing throws never {
        self.cur.eat(kind) ?? self.missing(found_name(kind))
    }

    // port: expect_in::<S>. One of a set of tokens, or a reported `Missing`
    // named by `expected`.
    function expect_in(self, set: KindSet, expected: string) -> int | Missing throws never {
        self.cur.eat_in(set) ?? self.missing(expected)
    }

    // port: expect_as::<K>. The token, or a reported `Missing` named by
    // `expected` rather than by the token's spelling ("'=>' after pattern").
    function expect_as(self, kind: TokenKind, expected: string) -> int | Missing throws never {
        self.cur.eat(kind) ?? self.missing(expected)
    }

    // Report that `expected` is not here; the `Missing` for the position.
    function missing(self, expected: string) -> Missing throws never {
        self.out.missing(self.unexpected_error(expected))
    }

    // One level deeper into a nested construct named `what`; past `MAX_NESTING`
    // the construct is reported, the bracket group at the cursor skipped, and
    // the reported `Missing` returned for its place. Every success (null) is
    // paired with a `leave_nesting`.
    function enter_nesting(self, what: string) -> Missing? throws never {
        if (self.depth >= MAX_NESTING) {
            let missing = self.missing_because(
                `${what} nested more than ${MAX_NESTING} levels deep`,
                self.cur.error_range(),
            );
            self.cur.skip_group();
            return missing;
        }
        self.depth += 1;
        null
    }

    function leave_nesting(self) -> void throws never {
        self.depth -= 1;
    }

    // A `Missing` explained by `message` rather than by "expected X".
    function missing_because(self, message: string, range: TextRange) -> Missing throws never {
        self.out.missing(InvalidSyntax { message: message, range: range })
    }

    // ----- bogus -----------------------------------------------------------------------

    // The current token as a `Bogus`, reported as unexpected.
    function bogus_one(self, expected: string) -> Bogus throws never {
        let error = self.unexpected_error(expected);
        let mark = self.cur.mark();
        self.cur.skip();
        self.out.bogus(self.cur.range_from(mark), error)
    }

    // The tokens consumed since `mark` as a `Bogus`, with their report.
    function bogus_since(self, mark: Mark, error: ParseError) -> Bogus throws never {
        self.out.bogus(self.cur.range_from(mark), error)
    }

    // `tokens`, already consumed, as a `Bogus` with their report: for a run
    // decided on after more was read past it.
    function bogus_tokens(self, tokens: TokenRange, error: ParseError) -> Bogus throws never {
        self.out.bogus(tokens, error)
    }

    // ----- speculation -----------------------------------------------------------------

    // port: Parser::attempt. Parse with `f`, deciding afterwards: the nodes it
    // registered are kept when it returns a value and dropped when it returns
    // null. The tokens it consumed stay consumed either way and the diagnostics
    // it reported stay reported; the null is for the caller to put a `Bogus`
    // over the same tokens. Attempts nest.
    function attempt<T>(self, f: (Parser) -> T? throws never) -> T? throws never {
        let mark = self.out.checkpoint();
        let result = f(self);
        if (result == null) {
            self.out.rollback(mark, false);
        }
        result
    }

    // port: Parser::discard. Parse with `f` for its tokens and diagnostics only:
    // the nodes it registered are dropped.
    function discard(self, f: (Parser) -> void throws never) -> void throws never {
        let mark = self.out.checkpoint();
        f(self);
        self.out.rollback(mark, false);
    }

    // port: Parser::probe. Parse with `f` for its tokens only: the nodes it
    // registered *and* the diagnostics it reported are dropped. For text read to
    // find where it ends, when a diagnostic of the caller's already covers it.
    function probe<T>(self, f: (Parser) -> T throws never) -> T throws never {
        let mark = self.out.checkpoint();
        let result = f(self);
        self.out.rollback(mark, true);
        result
    }

    // ----- lists -----------------------------------------------------------------------

    // port: Parser::sep1_list. `first (sep item)*`, `first` already parsed: a
    // separator continues the list while `item` produces something (null, after
    // its own diagnostic, ends it; the separator stays as a trailing one).
    function sep1_list<T>(
        self,
        first: T,
        sep: TokenKind,
        item: (Parser) -> T? throws never,
    ) -> SepItem<T>[] throws never {
        let items: SepItem<T>[] = [SepItem { item: first, sep: null }];
        let token = self.cur.eat(sep);
        while (token != null) {
            items[items.length() - 1].sep = token;
            let next = item(self);
            if (next == null) {
                break;
            }
            items.push(SepItem { item: next, sep: null });
            token = self.cur.eat(sep);
        }
        items
    }

    // port: Parser::sep_list. `item (sep item)*` up to `close`, a trailing
    // separator allowed. An item that cannot start (null, after its own
    // diagnostic) is skipped up to the next separator or `close`.
    function sep_list<T>(
        self,
        close: TokenKind,
        sep: TokenKind,
        item: (Parser) -> T? throws never,
    ) -> SepItem<T>[] throws never {
        let items: SepItem<T>[] = [];
        if (self.cur.at(close)) {
            return items;
        }
        while (true) {
            let parsed = item(self);
            if (parsed == null) {
                // Angle brackets nest only in a type list; in an argument or
                // parameter list `<` is a comparison.
                self.cur.skip_until(
                    KindSet.of([close, sep]),
                    angles_nest = close == TokenKind.Greater,
                );
            }
            let token = self.cur.eat(sep);
            let more = token != null && !self.cur.at(close) && !self.cur.at_end();
            if (parsed != null) {
                items.push(SepItem { item: parsed, sep: token });
            }
            if (!more) {
                break;
            }
        }
        items
    }

    // port: Parser::members. The members of a `{ ... }`/`[ ... ]` body up to
    // `close`, each parsed with its own trailing separator by `member`, which
    // returns the member and, when it found no separator after it, the message
    // for one being required there, reported unless `close` follows; after the
    // report one token is skipped unless a member can begin at it (`resume`). A
    // member that cannot start (null, after its own diagnostic) skips one token
    // the same way. A token in `boundary` (a statement keyword) ends the body
    // early: its closer was forgotten.
    function members<T>(
        self,
        close: TokenKind,
        boundary: KindSet,
        resume: KindSet,
        member: (Parser) -> Member<T>? throws never,
    ) -> T[] throws never {
        let items: T[] = [];
        while (!self.at_body_end(close, boundary)) {
            let before = self.cur.pos;
            let parsed = member(self);
            if (parsed != null) {
                items.push(parsed.item);
                let missing_sep = parsed.missing_sep;
                if (missing_sep == null) {
                    continue;
                }
                if (self.at_body_end(close, boundary)) {
                    break;
                }
                self.unexpected(missing_sep);
            } else if (self.at_body_end(close, boundary)) {
                break;
            }
            // A member that consumed nothing must not be tried again at the same
            // token: a token in `resume` that no member can start at is skipped all
            // the same, or the loop never ends.
            if (!self.cur.at_in(resume) || self.cur.pos == before) {
                self.cur.skip();
            }
        }
        items
    }

    // Whether a body ends here: at its closer, the end of input, or a token in
    // `boundary`.
    function at_body_end(self, close: TokenKind, boundary: KindSet) -> bool throws never {
        self.cur.at(close) || self.cur.at_end() || self.cur.at_in(boundary)
    }
}

// port: parser.rs::found_name. The name of a token kind in "expected ...,
// found ..." diagnostics: keywords by spelling, punctuation quoted, every kind
// of name "identifier", a string by its opening quote.
function found_name(kind: TokenKind) -> string throws never {
    match (kind) {
        TokenKind.Word
            | TokenKind.RawString
            | TokenKind.UnclosedRawString
            | TokenKind.ByteString
            | TokenKind.UnclosedByteString =>
        {
            "identifier"
        },
        TokenKind.Integer => "integer",
        TokenKind.Float => "float",
        TokenKind.Bigint => "bigint",
        TokenKind.String | TokenKind.UnclosedString => "'\"'",
        TokenKind.LegacyHashString | TokenKind.UnclosedHashString | TokenKind.Hash => "'#'",
        TokenKind.BacktickStart | TokenKind.BacktickEnd => "'`'",
        TokenKind.DollarLBrace => "'$'",
        TokenKind.Error => "error",
        _ if is_contextual_keyword(kind) => "identifier",
        _ if is_punct(kind) => `'${describe(kind)}'`,
        _ => describe(kind),
    }
}
