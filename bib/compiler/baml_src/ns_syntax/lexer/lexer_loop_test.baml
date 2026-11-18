// port: baml_syntax/src/lexer/tests.rs @ d9be6853b
// The lexer tests built on loops or helpers, and the asserts the table port
// in `lexer_test.baml` left out. A test whose table asserts are already in
// `lexer_test.baml` is named here with a `(loop asserts)` suffix.

// The significant token kinds of `text` (the kinds of Rust's `sig`).
function sig_kinds(text: string) -> TokenKind[] throws never {
    lex(text).kinds.filter((kind) -> {
        !is_trivia(kind)
    })
}

// port: tests.rs::every_fixed_spelling_lexes_to_its_kind @ d9be6853b
test "every fixed spelling lexes to its kind" {
    let all_kinds = (reflect.Type.of<TokenKind>().as_enum() ?? baml.sys.panic("TokenKind is an enum")).values();
    for (let value in all_kinds) {
        let kind = reflect.Enum.value_of<TokenKind>(value.name) catch (e) {
            reflect.errors.InvalidArgument => baml.sys.panic("a declared variant name"),
        };
        // `${` is only a token inside template text.
        if (
            !(is_keyword(kind) || is_contextual_keyword(kind) || is_punct(kind))
                || kind == TokenKind.DollarLBrace
        ) {
            continue;
        }
        let spelling = describe(kind);
        assert.equal(lexed(spelling, trivia = true), [`${kind} ${spelling}`]);
    }
}

// port: tests.rs::line_comments_sharing_the_directive_prefix @ d9be6853b
// (the loop; the other asserts are in `lexer_test.baml`). A `//b…` that is
// not a directive is one line comment.
test "line comments sharing the directive prefix (loop asserts)" {
    for (let text in ["//b", "//ba", "//bam", "//baml", "//baml x", "//bad comment", "//b`x`"]) {
        assert.equal(lexed(text, trivia = true), [`LineComment ${text}`]);
    }
}

// port: tests.rs::backtick_templates @ d9be6853b
// (the kinds-only asserts; the others are in `lexer_test.baml`).
test "backtick templates (loop asserts)" {
    // `$${x}` is `$` then an interpolation.
    assert.equal(
        sig_kinds("`$${x}`"),
        [
            TokenKind.BacktickStart,
            TokenKind.TemplateChunk,
            TokenKind.DollarLBrace,
            TokenKind.Word,
            TokenKind.RBrace,
            TokenKind.BacktickEnd,
        ],
    );
    // Braces inside a nested string or comment don't end the interpolation.
    assert.equal(
        sig_kinds("`${\"}\"}`"),
        [
            TokenKind.BacktickStart,
            TokenKind.DollarLBrace,
            TokenKind.String,
            TokenKind.RBrace,
            TokenKind.BacktickEnd,
        ],
    );
    assert.equal(
        sig_kinds("`${ x // }\n}`"),
        [
            TokenKind.BacktickStart,
            TokenKind.DollarLBrace,
            TokenKind.Word,
            TokenKind.RBrace,
            TokenKind.BacktickEnd,
        ],
    );
    // Nested blocks and a nested template inside an interpolation.
    assert.equal(
        sig_kinds("`${ if c { `in` } }`"),
        [
            TokenKind.BacktickStart,
            TokenKind.DollarLBrace,
            TokenKind.If,
            TokenKind.Word,
            TokenKind.LBrace,
            TokenKind.BacktickStart,
            TokenKind.TemplateChunk,
            TokenKind.BacktickEnd,
            TokenKind.RBrace,
            TokenKind.RBrace,
            TokenKind.BacktickEnd,
        ],
    )
}

// port: tests.rs::token_indices_line_up @ d9be6853b
test "token indices line up" {
    let tokens = lex("let x = 1;");
    assert.equal(tokens.kinds[0], TokenKind.Let);
    assert.equal([tokens.starts[2], tokens.starts[3]], [4, 5]);
    assert.equal(tokens.kinds.length(), 8)
}

// port: tests.rs::text_fits_kind @ d9be6853b
// Whether `text` is something a token of `kind` can be: a fixed kind is its
// spelling, a variable kind has the shape its rule accepts. Guards the
// classification itself, which the round trip cannot.
function text_fits_kind(kind: TokenKind, text: string) -> bool throws never {
    let line_comment = (prefix: string) -> bool {
        text.starts_with(prefix) && !text.includes("\n")
    };
    let chars = text.chars();
    let len = text.byte_length();
    match (kind) {
        TokenKind.Whitespace => {
            len > 0
                && chars.every((c) -> {
                    c == " " || c == "\t"
                })
        },
        TokenKind.Newline => text == "\n" || text == "\r\n",
        TokenKind.LineComment => {
            (
                line_comment("//")
                    && (!text.starts_with("///") || text.starts_with("////"))
                    && !text.starts_with("//#")
                    && !text.starts_with("//baml:")
            )
                || line_comment("#!")
        },
        TokenKind.DocComment => line_comment("///") && !text.starts_with("////"),
        TokenKind.HeaderComment => line_comment("//#"),
        TokenKind.DirectiveComment => line_comment("//baml:"),
        TokenKind.BlockComment => len >= 4 && text.starts_with("/*") && text.ends_with("*/"),
        TokenKind.UnclosedBlockComment => {
            text.starts_with("/*") && !(len >= 4 && text.ends_with("*/"))
        },
        TokenKind.Word => {
            let first = chars.at(0);
            first != null
                && (first.is_ascii_alphabetic() || first == "_" || first == "$")
                && chars.slice(1, chars.length()).every((c) -> {
                    c.is_ascii_alphanumeric() || c == "_" || c == "-" || c == "$"
                })
        },
        TokenKind.Integer | TokenKind.Float | TokenKind.Bigint => {
            let first = chars.at(0);
            first != null
                && first.is_ascii_numeric()
                && chars.every((c) -> {
                    c.is_ascii_hex() || "_.xXoOn+-".includes(c)
                })
        },
        TokenKind.String => len >= 2 && text.starts_with("\"") && text.ends_with("\""),
        TokenKind.RawString => len >= 3 && text.starts_with("r\"") && text.ends_with("\""),
        TokenKind.ByteString => len >= 3 && text.starts_with("b\"") && text.ends_with("\""),
        TokenKind.LegacyHashString => {
            text.starts_with("#") && text.ends_with("#") && text.includes("\"")
        },
        TokenKind.UnclosedString => text.starts_with("\""),
        TokenKind.UnclosedRawString => text.starts_with("r\""),
        TokenKind.UnclosedByteString => text.starts_with("b\""),
        TokenKind.UnclosedHashString => text.starts_with("#") && text.includes("\""),
        TokenKind.BacktickStart | TokenKind.BacktickEnd => {
            len > 0
                && chars.every((c) -> {
                    c == "`"
                })
        },
        TokenKind.TemplateChunk | TokenKind.Error => len > 0,
        TokenKind.Hash => text == "#",
        let other: TokenKind => describe(other) == text,
    }
}

// port: tests.rs::kinds_fit @ d9be6853b
// The tokens of `text` that do not fit their kind, as "Kind text"; empty
// when every token fits.
function misfit_tokens(text: string) -> string[] throws never {
    let tokens = lex(text);
    let utf8 = text.to_utf8();
    let out: string[] = [];
    for (let i = 0; i < tokens.kinds.length(); i += 1) {
        let slice = tokens.text(utf8, i);
        if (!text_fits_kind(tokens.kinds[i], slice)) {
            out.push(`${tokens.kinds[i]} ${slice}`);
        }
    }
    out
}

// The corpus roots of `corpus_kinds_fit`, relative to this project (Rust
// resolves them from the `baml_syntax` crate).
const LEXER_CORPUS_ROOTS: string[] = [
    "../../baml_language/crates/baml_tests/baml_src",
    "../../baml_language/crates/baml_tests/projects",
    "../../baml_language/crates/baml_builtins2/baml_std",
    "../../baml_language/tools/type_quiz",
];

// port: tests.rs::corpus_kinds_fit @ d9be6853b
// Every `.baml` file the repo owns: each token fits its kind.
test "corpus kinds fit" {
    let files = 0;
    for (let dir in LEXER_CORPUS_ROOTS) {
        let paths = baml.glob.new("**/*.baml").scan(dir);
        // Rust's walk skips entries whose name starts with a dot.
        let visible = paths.filter((path) -> {
            !path.split("/").some((part) -> {
                part.starts_with(".")
            })
        });
        for (let path in visible) {
            let text = baml.fs.read(`${dir}/${path}`);
            assert.equal(
                { "file": `${dir}/${path}`, "misfits": misfit_tokens(text) },
                { "file": `${dir}/${path}`, "misfits": [] },
            );
            files += 1;
        }
    }
    // The whole corpus was found.
    assert.is_true(files > 500)
}

// The bytes of `random_input_round_trips`'s alphabet: BAML-ish ASCII, then
// the two bytes of `é` apart, then `e`.
const RANDOM_INPUT_ALPHABET: int[] = "abXz_$-019 \t\n\r\"'`#!/*=<>?.:;,{}()[]|&^~+%@\\".to_utf8().to_array().concat([0xC3, 0xA9]).concat(
    "e".to_utf8().to_array(),
);

// Rust's `String::from_utf8_lossy` over bytes of `RANDOM_INPUT_ALPHABET`:
// `0xC3 0xA9` is `é`, either byte alone is U+FFFD.
function lossy_text(bytes: int[]) -> string throws never {
    let out: string[] = [];
    let i = 0;
    while (i < bytes.length()) {
        let b = bytes[i];
        if (b < 0x80) {
            out.push(
                string.from_code_points([b]) catch (e) {
                    baml.errors.InvalidArgument => baml.sys.panic("ASCII is a code point"),
                },
            );
            i += 1;
        } else if (b == 0xC3 && bytes.at(i + 1) == 0xA9) {
            out.push("é");
            i += 2;
        } else {
            out.push("\u{FFFD}");
            i += 1;
        }
    }
    out.join("")
}

// port: tests.rs::random_input_round_trips @ d9be6853b
// Deterministic fuzz: random strings over a BAML-ish alphabet never panic,
// always round-trip, have no empty token, and every token fits its kind.
// The xorshift64 generator runs on `bigint` masked to 64 bits (`int` is
// narrower than Rust's `u64`).
test "random input round trips" {
    let mask = 0xFFFF_FFFF_FFFF_FFFFn;
    let state = 0x9E37_79B9_7F4A_7C15n;
    let next = () -> bigint {
        state = state ^ ((state << 13) & mask);
        state = state ^ (state >> 7);
        state = state ^ ((state << 17) & mask);
        state
    };
    let pick = (bound: int, value: bigint) -> int {
        (value % bound).to_int() catch (e) {
            baml.errors.InvalidArgument => baml.sys.panic("below `bound`"),
        }
    };
    for (let round = 0; round < 2000; round += 1) {
        let len = pick(40, next());
        let bytes: int[] = [];
        for (let j = 0; j < len; j += 1) {
            bytes.push(RANDOM_INPUT_ALPHABET[pick(RANDOM_INPUT_ALPHABET.length(), next())]);
        }
        let text = lossy_text(bytes);
        let tokens = lex(text);
        let utf8 = text.to_utf8();
        let pieces: string[] = [];
        for (let i = 0; i < tokens.kinds.length(); i += 1) {
            pieces.push(tokens.text(utf8, i));
            // No token is empty.
            assert.is_true(tokens.starts[i] < tokens.starts[i + 1]);
        }
        assert.equal(pieces.join(""), text);
        assert.equal(
            { "text": text, "misfits": misfit_tokens(text) },
            { "text": text, "misfits": [] },
        );
    }
}
