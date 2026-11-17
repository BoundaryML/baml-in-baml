// port: baml_syntax/src/lexer.rs @ d9be6853b
//
// The Rust lexer is Logos-generated. This is the same language written as a
// hand scanner over UTF-8 bytes: longest match, a fixed spelling beats `Word`
// at equal length, and the same mode stack for backtick templates. Every byte
// lands in exactly one token, so concat(tokens) == text.
//
// Byte values are written as numbers with the character in a comment.

// The extent of a literal whose end is not regular: where it ends, and
// whether its closer was found (an unclosed literal ends after its last
// non-blank character, so trailing whitespace stays trivia).
class Scan {
    end: int,
    closed: bool,
}

// port: lexer.rs::char_len, on the lead byte of a UTF-8 character.
function char_len(lead: int) -> int throws never {
    match (lead) {
        _ if lead < 128 => 1,
        _ if lead < 224 => 2,
        _ if lead < 240 => 3,
        _ => 4,
    }
}

// [a-zA-Z_]
function is_word_start(c: int) -> bool throws never {
    (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95
}

// [a-zA-Z0-9_]
function is_word_char(c: int) -> bool throws never {
    is_word_start(c) || (c >= 48 && c <= 57)
}

// [0-9]
function is_digit(c: int) -> bool throws never {
    c >= 48 && c <= 57
}

// [0-9_]
function is_digit_or_underscore(c: int) -> bool throws never {
    is_digit(c) || c == 95
}

// ' ' \t \n \r
function is_blank(c: int) -> bool throws never {
    c == 32 || c == 9 || c == 10 || c == 13
}

// port: lexer.rs::Out + the scanning state the Logos lexer keeps.
class Lexer {
    bytes: int[],
    utf8: uint8array,
    len: int,
    kinds: TokenKind[],
    starts: int[],
    // m >= 0: code at brace depth m; m < 0: a template opened by -m backticks.
    modes: int[],

    function new(text: string) -> Lexer throws never {
        let utf8 = text.to_utf8();
        let bytes = utf8.to_array();
        Lexer { bytes: bytes, utf8: utf8, len: bytes.length(), kinds: [], starts: [], modes: [0] }
    }

    // The byte at `i`, or -1 past the end.
    function at(self, i: int) -> int throws never {
        if (i < self.len) {
            return self.bytes[i];
        }
        -1
    }

    // port: Out::push. Records a token and returns its end, where lexing resumes.
    function emit(self, kind: TokenKind, start: int, end: int) -> int throws never {
        self.kinds.push(kind);
        self.starts.push(start);
        end
    }

    // port: Out::finish
    function finish(self) -> Tokens throws never {
        self.starts.push(self.len);
        Tokens { kinds: self.kinds, starts: self.starts }
    }

    // The end of a run of bytes from `i` that satisfy `keep`.
    function run_while(self, i: int, keep: (int) -> bool throws never) -> int throws never {
        let j = i;
        while (j < self.len && keep(self.bytes[j])) {
            j += 1;
        }
        j
    }

    // port: lexer.rs::to_line_end. The end of the line starting at `p`, not
    // including the newline nor the `\r` of a CRLF.
    function to_line_end(self, p: int) -> int throws never {
        let q = self.run_while(p, (c) -> {
            c != 10
        });
        if (q < self.len && q > p && self.bytes[q - 1] == 13) {
            return q - 1;
        }
        q
    }

    // port: lexer.rs::quoted_body. `body` is the first byte after the opener:
    // `\` escapes the next character, where a CRLF or a run of blanks counts as one.
    function quoted_body(self, body: int) -> Scan throws never {
        let b = self.bytes;
        let n = self.len;
        let i = body;
        let content_end = body;
        while (i < n) {
            let c = b[i];
            match (c) {
                34 => {
                    // "
                    return Scan { end: i + 1, closed: true };
                },
                92 => {
                    // \
                    i = self.escape_end(i + 1);
                    content_end = i;
                },
                _ if is_blank(c) => {
                    i += 1;
                },
                _ => {
                    i += char_len(c);
                    content_end = i;
                },
            }
        }
        Scan { end: content_end, closed: false }
    }

    // The end of what a `\\` escapes, starting right after it: a CRLF or a run
    // of blanks counts as one character.
    function escape_end(self, i: int) -> int throws never {
        match (self.at(i)) {
            -1 => i,
            13 if self.at(i + 1) == 10 => i + 2,
            32 | 9 => {
                self.run_while(i, (x) -> {
                    x == 32 || x == 9
                })
            },
            let c: int => i + char_len(c),
        }
    }

    // port: lexer.rs::hash_body. Raw (no escapes); closes at a `"` followed by
    // exactly as many `#` as the opener, blanks allowed between them.
    function hash_body(self, body: int, hashes: int) -> Scan throws never {
        let b = self.bytes;
        let n = self.len;
        let i = body;
        let content_end = body;
        while (i < n) {
            let c = b[i];
            match (c) {
                34 => {
                    let close = self.hash_closer_end(i + 1, hashes);
                    if (close != null) {
                        return Scan { end: close, closed: true };
                    }
                    i += 1;
                    content_end = i;
                },
                _ if is_blank(c) => {
                    i += 1;
                },
                _ => {
                    i += char_len(c);
                    content_end = i;
                },
            }
        }
        Scan { end: content_end, closed: false }
    }

    // After a `"` at `after - 1`: the end of its closer when exactly `hashes`
    // `#`s follow (blanks allowed between them), else null.
    function hash_closer_end(self, after: int, hashes: int) -> int? throws never {
        let run_end = self.run_while(after, (c) -> {
            c == 35 || is_blank(c)
        });
        let run = self.bytes.slice(after, run_end);
        if (
            hashes == 0
                || run
                    .filter((c) -> {
                        c == 35
                    })
                    .length()
                    != hashes
        ) {
            return null;
        }
        // The closer ends after its last `#`; trailing blanks stay trivia.
        let last_hash = run_end - 1;
        while (self.bytes[last_hash] != 35) {
            last_hash -= 1;
        }
        last_hash + 1
    }

    // port: lexer.rs::run_template. Lexes template text from `i`, inside the
    // template opened by `ticks` backticks, until `${` (push a code mode), the
    // closing run (pop) or the end of input. Returns where lexing resumes.
    // Everything before the terminator is content, so the text chunk always
    // starts at `i`.
    function run_template(self, i: int, ticks: int) -> int throws never {
        let j = i;
        while (j < self.len) {
            match (self.bytes[j]) {
                96 => {
                    // A run of backticks closes the template when it is long enough.
                    // Anchored close: the excess leading ticks are content.
                    let k = self.run_while(j, (x) -> {
                        x == 96
                    });
                    if (k - j >= ticks) {
                        self.chunk(i, k - ticks);
                        self.modes.pop();
                        return self.emit(TokenKind.BacktickEnd, k - ticks, k);
                    }
                    j = k;
                },
                36 if self.at(j + 1) == 123 => {
                    // ${
                    self.chunk(i, j);
                    self.modes.push(0);
                    return self.emit(TokenKind.DollarLBrace, j, j + 2);
                },
                _ => {
                    j += self.template_text_len(j);
                },
            }
        }
        self.chunk(i, self.len);
        self.len
    }

    // Template text [start, end) as one `TemplateChunk`, unless it is empty.
    function chunk(self, start: int, end: int) -> void throws never {
        if (end > start) {
            self.emit(TokenKind.TemplateChunk, start, end);
        }
    }

    // Length of one piece of template text at `j`: an escape (`\` and the one
    // character it escapes, a CRLF counting as one) or a single byte.
    function template_text_len(self, j: int) -> int throws never {
        if (self.bytes[j] != 92 || j + 1 >= self.len) {
            return 1;
        }
        if (self.bytes[j + 1] == 13 && self.at(j + 2) == 10) {
            return 3;
        }
        1 + char_len(self.bytes[j + 1])
    }

    // `[a-zA-Z_][a-zA-Z0-9_-]*(\$[a-zA-Z_][a-zA-Z0-9_-]*)*`, or a fixed
    // spelling when the whole word is one.
    function word(self, i: int) -> int throws never {
        let end = self.run_while(i + 1, (c) -> {
            is_word_char(c) || c == 45
        });
        let plain_end = end;
        while (self.at(end) == 36 && is_word_start(self.at(end + 1))) {
            end
                = self.run_while(end + 2, (c) -> {
                    is_word_char(c) || c == 45
                });
        }
        let kind = if (end == plain_end && end - i <= 16) {
            KEYWORDS.get(self.text(i, end)) ?? TokenKind.Word
        } else {
            TokenKind.Word
        };
        self.emit(kind, i, end)
    }

    // ASCII text of bytes [start, end).
    function text(self, start: int, end: int) -> string throws never {
        string.from_utf8(self.utf8.slice(start, end)) catch (e) {
            baml.errors.InvalidArgument => baml.sys.panic("word bytes are ASCII"),
        }
    }

    // Integer, Float and Bigint, longest match first.
    function number(self, i: int) -> int throws never {
        let c1 = self.at(i + 1);
        if (self.bytes[i] == 48 && (c1 == 120 || c1 == 88)) {
            // 0x
            let digits_end = self.run_while(i + 2, (c) -> {
                is_digit_or_underscore(c) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)
            });
            return self.integer_or_bigint(i, digits_end);
        }
        if (self.bytes[i] == 48 && (c1 == 111 || c1 == 79 || c1 == 98 || c1 == 66)) {
            // 0o, 0b
            return self.integer_or_bigint(i, self.run_while(i + 2, is_digit_or_underscore));
        }
        let int_end = self.run_while(i + 1, is_digit_or_underscore);
        if (self.at(int_end) == 110) {
            return self.emit(TokenKind.Bigint, i, int_end + 1);
        }
        let fraction_end = if (self.at(int_end) == 46 && is_digit(self.at(int_end + 1))) {
            self.run_while(int_end + 2, is_digit_or_underscore)
        } else {
            int_end
        };
        let float_end = self.exponent_end(fraction_end) ?? fraction_end;
        if (float_end > int_end) {
            return self.emit(TokenKind.Float, i, float_end);
        }
        self.emit(TokenKind.Integer, i, int_end)
    }

    // An integer ending at `digits_end`, or a bigint if an `n` follows.
    function integer_or_bigint(self, i: int, digits_end: int) -> int throws never {
        if (self.at(digits_end) == 110) {
            return self.emit(TokenKind.Bigint, i, digits_end + 1);
        }
        self.emit(TokenKind.Integer, i, digits_end)
    }

    // `[eE][+-]?[0-9][0-9_]*` at `p`, or null when there is none.
    function exponent_end(self, p: int) -> int? throws never {
        let e = self.at(p);
        if (e != 101 && e != 69) {
            return null;
        }
        let sign = self.at(p + 1);
        let digits = if (sign == 43 || sign == 45) {
            p + 2
        } else {
            p + 1
        };
        if (!is_digit(self.at(digits))) {
            return null;
        }
        self.run_while(digits + 1, is_digit_or_underscore)
    }

    // port: lexer.rs::line_comment and block_comment, after a `/`.
    function slash(self, i: int) -> int throws never {
        match (self.at(i + 1)) {
            47 => self.line_comment(i),
            42 => self.block_comment(i),
            61 => self.emit(TokenKind.SlashEquals, i, i + 2),
            _ => self.emit(TokenKind.Slash, i, i + 1),
        }
    }

    // A `//` comment, classified by what follows the slashes: `///` doc (a
    // fourth slash makes it plain), `//#` header, `//baml:` directive.
    function line_comment(self, i: int) -> int throws never {
        let c2 = self.at(i + 2);
        let kind = match (c2) {
            47 if self.at(i + 3) != 47 => TokenKind.DocComment,
            35 => TokenKind.HeaderComment,
            98 if i + 7 <= self.len && self.text(i + 2, i + 7) == "baml:" => {
                TokenKind.DirectiveComment
            },
            _ => TokenKind.LineComment,
        };
        self.emit(kind, i, self.to_line_end(i + 2))
    }

    // Not nested; closes at the first `*/`, or runs to the end unclosed.
    function block_comment(self, i: int) -> int throws never {
        let q = i + 2;
        while (q + 1 < self.len) {
            if (self.bytes[q] == 42 && self.bytes[q + 1] == 47) {
                return self.emit(TokenKind.BlockComment, i, q + 2);
            }
            q += 1;
        }
        self.emit(TokenKind.UnclosedBlockComment, i, self.len)
    }

    // port: lexer.rs::hash. A `#!` shebang line, a legacy `#"…"#` string, or a
    // stray `#`.
    function hash(self, i: int) -> int throws never {
        if (self.at(i + 1) == 33) {
            return self.emit(TokenKind.LineComment, i, self.to_line_end(i + 1));
        }
        let quote = self.run_while(i + 1, (c) -> {
            c == 35 || is_blank(c)
        });
        if (self.at(quote) != 34) {
            return self.emit(TokenKind.Hash, i, i + 1);
        }
        let hashes = self.bytes.slice(i, quote)
            .filter((c) -> {
                c == 35
            })
            .length();
        let scan = self.hash_body(quote + 1, hashes);
        let kind = if (scan.closed) {
            TokenKind.LegacyHashString
        } else {
            TokenKind.UnclosedHashString
        };
        self.emit(kind, i, scan.end)
    }

    // A `"`, `r"` or `b"` literal; `opener` is its length.
    function quoted(
        self,
        i: int,
        opener: int,
        closed: TokenKind,
        unclosed: TokenKind,
    ) -> int throws never {
        let scan = self.quoted_body(i + opener);
        self.emit(
            if (scan.closed) {
                closed
            } else {
                unclosed
            },
            i,
            scan.end,
        )
    }

    // `$name` is a word; any other `$` is `Dollar` (`${` only exists in templates).
    function dollar(self, i: int) -> int throws never {
        if (is_word_start(self.at(i + 1))) {
            return self.emit(TokenKind.Word, i, self.run_while(i + 2, is_word_char));
        }
        self.emit(TokenKind.Dollar, i, i + 1)
    }

    // A one-byte token, or the two-byte one when `second` follows.
    function one_or_two(
        self,
        i: int,
        one: TokenKind,
        second: int,
        two: TokenKind,
    ) -> int throws never {
        if (self.at(i + 1) == second) {
            return self.emit(two, i, i + 2);
        }
        self.emit(one, i, i + 1)
    }

    // port: the `lex` driver's code-mode match. Lexes one token at `i` and
    // returns where lexing resumes.
    function code_token(self, i: int, depth_at: int) -> int throws never {
        let c = self.bytes[i];
        let c1 = self.at(i + 1);
        match (c) {
            32 | 9 => {
                self.emit(
                    TokenKind.Whitespace,
                    i,
                    self.run_while(i, (x) -> {
                        x == 32 || x == 9
                    }),
                )
            },
            10 => self.emit(TokenKind.Newline, i, i + 1),
            13 => {
                if (c1 == 10) {
                    self.emit(TokenKind.Newline, i, i + 2)
                } else {
                    self.emit(TokenKind.Error, i, i + 1)
                }
            },
            34 => self.quoted(i, 1, TokenKind.String, TokenKind.UnclosedString),
            114 if c1 == 34 => self.quoted(i, 2, TokenKind.RawString, TokenKind.UnclosedRawString),
            98 if c1 == 34 => self.quoted(i, 2, TokenKind.ByteString, TokenKind.UnclosedByteString),
            _ if is_word_start(c) => self.word(i),
            _ if is_digit(c) => self.number(i),
            96 => {
                // a run of backticks opens a template
                let end = self.run_while(i, (x) -> {
                    x == 96
                });
                self.modes.push(i - end);
                self.emit(TokenKind.BacktickStart, i, end)
            },
            123 => {
                self.modes[depth_at] = self.modes[depth_at] + 1;
                self.emit(TokenKind.LBrace, i, i + 1)
            },
            125 => {
                let depth = self.modes[depth_at];
                if (depth > 0) {
                    self.modes[depth_at] = depth - 1;
                } else if (self.modes.length() > 1) {
                    // The `}` closing a `${…}` interpolation: back to template text.
                    self.modes.pop();
                }
                self.emit(TokenKind.RBrace, i, i + 1)
            },
            47 => self.slash(i),
            35 => self.hash(i),
            36 => self.dollar(i),
            40 => self.emit(TokenKind.LParen, i, i + 1),
            41 => self.emit(TokenKind.RParen, i, i + 1),
            91 => self.emit(TokenKind.LBracket, i, i + 1),
            93 => self.emit(TokenKind.RBracket, i, i + 1),
            44 => self.emit(TokenKind.Comma, i, i + 1),
            59 => self.emit(TokenKind.Semicolon, i, i + 1),
            126 => self.emit(TokenKind.Tilde, i, i + 1),
            92 => self.emit(TokenKind.Backslash, i, i + 1),
            62 => self.emit(TokenKind.Greater, i, i + 1),
            58 => self.one_or_two(i, TokenKind.Colon, 58, TokenKind.DoubleColon),
            64 => self.one_or_two(i, TokenKind.At, 64, TokenKind.AtAt),
            63 => self.one_or_two(i, TokenKind.Question, 46, TokenKind.QuestionDot),
            42 => self.one_or_two(i, TokenKind.Star, 61, TokenKind.StarEquals),
            37 => self.one_or_two(i, TokenKind.Percent, 61, TokenKind.PercentEquals),
            94 => self.one_or_two(i, TokenKind.Caret, 61, TokenKind.CaretEquals),
            33 => self.one_or_two(i, TokenKind.Not, 61, TokenKind.NotEquals),
            46 => match (c1) {
                46 if self.at(i + 2) == 46 => self.emit(TokenKind.DotDotDot, i, i + 3),
                46 => self.emit(TokenKind.DotDot, i, i + 2),
                _ => self.emit(TokenKind.Dot, i, i + 1),
            },
            45 => match (c1) {
                62 => self.emit(TokenKind.Arrow, i, i + 2),
                61 => self.emit(TokenKind.MinusEquals, i, i + 2),
                45 => self.emit(TokenKind.MinusMinus, i, i + 2),
                _ => self.emit(TokenKind.Minus, i, i + 1),
            },
            61 => match (c1) {
                62 => self.emit(TokenKind.FatArrow, i, i + 2),
                61 => self.emit(TokenKind.EqualsEquals, i, i + 2),
                _ => self.emit(TokenKind.Equals, i, i + 1),
            },
            124 => match (c1) {
                61 => self.emit(TokenKind.PipeEquals, i, i + 2),
                124 => self.emit(TokenKind.OrOr, i, i + 2),
                _ => self.emit(TokenKind.Pipe, i, i + 1),
            },
            60 => match (c1) {
                60 if self.at(i + 2) == 61 => self.emit(TokenKind.LessLessEquals, i, i + 3),
                60 => self.emit(TokenKind.LessLess, i, i + 2),
                61 => self.emit(TokenKind.LessEquals, i, i + 2),
                _ => self.emit(TokenKind.Less, i, i + 1),
            },
            43 => match (c1) {
                61 => self.emit(TokenKind.PlusEquals, i, i + 2),
                43 => self.emit(TokenKind.PlusPlus, i, i + 2),
                _ => self.emit(TokenKind.Plus, i, i + 1),
            },
            38 => match (c1) {
                61 => self.emit(TokenKind.AndEquals, i, i + 2),
                38 => self.emit(TokenKind.AndAnd, i, i + 2),
                _ => self.emit(TokenKind.And, i, i + 1),
            },
            // an unrecognised character: one whole UTF-8 character
            _ => {
                let end = i + char_len(c);
                self.emit(
                    TokenKind.Error,
                    i,
                    if (end < self.len) {
                        end
                    } else {
                        self.len
                    },
                )
            },
        }
    }
}

// port: lexer.rs::lex
function lex(text: string) -> Tokens throws never {
    let lexer = Lexer.new(text);
    let i = 0;
    while (i < lexer.len) {
        let top_at = lexer.modes.length() - 1;
        let top = lexer.modes[top_at];
        i
            = if (top < 0) {
                lexer.run_template(i, -top)
            } else {
                lexer.code_token(i, top_at)
            };
    }
    lexer.finish()
}
