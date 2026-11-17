// port: baml_syntax/src/lexer/tests.rs @ d9be6853b
// The table-style asserts, carried over by a one-off script. Tests built
// on loops or helpers are ported by hand below the generated ones.

// not ported (no table asserts): every_fixed_spelling_lexes_to_its_kind
test "composites that are not tokens split" {
    assert.equal(sig("a ?? b"), ["Word a", "Question ?", "Question ?", "Word b"]);
    assert.equal(sig("x >> 1"), ["Word x", "Greater >", "Greater >", "Integer 1"]);
    assert.equal(sig("x >>= 1"), ["Word x", "Greater >", "Greater >", "Equals =", "Integer 1"]);
    assert.equal(sig("...."), ["DotDotDot ...", "Dot ."]);
    assert.equal(sig("x->y"), ["Word x-", "Greater >", "Word y"]);
}

test "words hyphens and dollars" {
    assert.equal(sig("gpt-4o a- a--b x-1"), ["Word gpt-4o", "Word a-", "Word a--b", "Word x-1"]);
    assert.equal(sig("Foo$bar"), ["Word Foo$bar"]);
    assert.equal(sig("foo$"), ["Word foo", "Dollar $"]);
    assert.equal(sig("$foo-bar"), ["Word $foo", "Minus -", "Word bar"]);
    assert.equal(sig("$1"), ["Dollar $", "Integer 1"]);
    assert.equal(sig("_ _1"), ["Underscore _", "Word _1"]);
    assert.equal(
        sig("get_client catch_all_panics catch_all classy"),
        ["Word get_client", "CatchAllPanics catch_all_panics", "CatchAll catch_all", "Word classy"],
    );
    assert.equal(sig("type-x type"), ["Word type-x", "Type type"]);
}

test "non ascii outside strings is one error per char" {
    assert.equal(toks("'"), ["Error '"]);
}

test "numbers" {
    assert.equal(
        sig("42n 42na 42n.5"),
        ["Bigint 42n", "Bigint 42n", "Word a", "Bigint 42n", "Dot .", "Integer 5"],
    );
    assert.equal(sig("0xfn 1e5n"), ["Bigint 0xfn", "Float 1e5", "Word n"]);
    assert.equal(
        sig("0x 0b_ 0X1F 0b123 0o18"),
        ["Integer 0x", "Integer 0b_", "Integer 0X1F", "Integer 0b123", "Integer 0o18"],
    );
    assert.equal(
        sig("0xG 0b1f 0x1.5"),
        ["Integer 0x", "Word G", "Integer 0b1", "Word f", "Integer 0x1", "Dot .", "Integer 5"],
    );
    assert.equal(
        sig("3.foo 1._5"),
        ["Integer 3", "Dot .", "Word foo", "Integer 1", "Dot .", "Word _5"],
    );
    assert.equal(
        sig("1..2 1...2 1.5.3"),
        [
            "Integer 1",
            "DotDot ..",
            "Integer 2",
            "Integer 1",
            "DotDotDot ...",
            "Integer 2",
            "Float 1.5",
            "Dot .",
            "Integer 3",
        ],
    );
    assert.equal(
        sig("1_.5 1_000.000_1 1e1_ 1_0e1_0 1_"),
        ["Float 1_.5", "Float 1_000.000_1", "Float 1e1_", "Float 1_0e1_0", "Integer 1_"],
    );
    assert.equal(
        sig("1e 1e_1 1e+ 1.e5"),
        [
            "Integer 1",
            "Word e",
            "Integer 1",
            "Word e_1",
            "Integer 1",
            "Word e",
            "Plus +",
            "Integer 1",
            "Dot .",
            "Word e5",
        ],
    );
    assert.equal(
        sig("1.0 3.14 1E3 1e-3 2e+5 1.5e-3"),
        ["Float 1.0", "Float 3.14", "Float 1E3", "Float 1e-3", "Float 2e+5", "Float 1.5e-3"],
    );
}

test "comments" {
    assert.equal(toks("// a  \r\nx"), ["LineComment // a  ", "Newline \r\n", "Word x"]);
    assert.equal(toks("//# section\n"), ["HeaderComment //# section", "Newline \n"]);
    assert.equal(toks("/// doc"), ["DocComment /// doc"]);
    assert.equal(toks("////x"), ["LineComment ////x"]);
    assert.equal(toks("///#"), ["DocComment ///#"]);
    assert.equal(toks("//baml:mut_self"), ["DirectiveComment //baml:mut_self"]);
    assert.equal(toks("// baml:x"), ["LineComment // baml:x"]);
    assert.equal(toks("// #"), ["LineComment // #"]);
    assert.equal(toks("//====="), ["LineComment //====="]);
    assert.equal(toks("///="), ["DocComment ///="]);
    assert.equal(
        toks("#!/usr/bin/env baml\nx"),
        ["LineComment #!/usr/bin/env baml", "Newline \n", "Word x"],
    );
    assert.equal(toks("#!="), ["LineComment #!="]);
    assert.equal(toks("/* a **/x"), ["BlockComment /* a **/", "Word x"]);
    assert.equal(toks("/**/"), ["BlockComment /**/"]);
    assert.equal(
        toks("/* /* */ */"),
        ["BlockComment /* /* */", "Whitespace  ", "Star *", "Slash /"],
    );
    assert.equal(toks("/*/ x"), ["UnclosedBlockComment /*/ x"]);
    assert.equal(toks("/* */= x"), ["BlockComment /* */", "Equals =", "Whitespace  ", "Word x"]);
    assert.equal(toks("/* open"), ["UnclosedBlockComment /* open"]);
    assert.equal(toks("/*= x"), ["UnclosedBlockComment /*= x"]);
    assert.equal(toks("/* a\n*/ b"), ["BlockComment /* a\n*/", "Whitespace  ", "Word b"]);
}

test "line comments sharing the directive prefix" {
    assert.equal(
        toks("x //bad\ny"),
        ["Word x", "Whitespace  ", "LineComment //bad", "Newline \n", "Word y"],
    );
    assert.equal(toks("//baml:x"), ["DirectiveComment //baml:x"]);
    assert.equal(toks("//#x"), ["HeaderComment //#x"]);
    assert.equal(toks("///x"), ["DocComment ///x"]);
}

// line_comments_sharing_the_directive_prefix: 1 assert(s) not in table form, not ported

test "stray hash" {
    assert.equal(toks("#\n\nclass"), ["Hash #", "Newline \n", "Newline \n", "Class class"]);
    assert.equal(toks("# x"), ["Hash #", "Whitespace  ", "Word x"]);
    assert.equal(toks("#!x"), ["LineComment #!x"]);
    assert.equal(toks("#\"x\"#"), ["LegacyHashString #\"x\"#"]);
}

test "strings" {
    assert.equal(toks("\"a\\\"b\""), ["String \"a\\\"b\""]);
    assert.equal(toks("\"a\\\\\" "), ["String \"a\\\\\"", "Whitespace  "]);
    assert.equal(toks("\"a\\\\\\\"b\""), ["String \"a\\\\\\\"b\""]);
    assert.equal(toks("\"\\ \""), ["String \"\\ \""]);
    assert.equal(toks("\"a\nb\""), ["String \"a\nb\""]);
    assert.equal(toks("\"#! not a comment\""), ["String \"#! not a comment\""]);
    assert.equal(toks("\"http://x\""), ["String \"http://x\""]);
    assert.equal(
        sig("r\"\\d+\\\"\" b\"x\" r \"x\" rb\"x\" bar\"x\" 1r\"x\""),
        [
            "RawString r\"\\d+\\\"\"",
            "ByteString b\"x\"",
            "Word r",
            "String \"x\"",
            "Word rb",
            "String \"x\"",
            "Word bar",
            "String \"x\"",
            "Integer 1",
            "RawString r\"x\"",
        ],
    );
    assert.equal(toks("\"ab  \n"), ["UnclosedString \"ab", "Whitespace   ", "Newline \n"]);
    assert.equal(toks("\"ab\\   "), ["UnclosedString \"ab\\   "]);
    assert.equal(toks("r\"x"), ["UnclosedRawString r\"x"]);
    assert.equal(toks("b\"x"), ["UnclosedByteString b\"x"]);
}

test "hash strings" {
    assert.equal(toks("#\"a\"#"), ["LegacyHashString #\"a\"#"]);
    assert.equal(toks("##\"x\"#\"##"), ["LegacyHashString ##\"x\"#\"##"]);
    assert.equal(toks("#\"a\" #b"), ["LegacyHashString #\"a\" #", "Word b"]);
    assert.equal(toks("# \"a\"#"), ["LegacyHashString # \"a\"#"]);
    assert.equal(toks("#\"a\"##"), ["UnclosedHashString #\"a\"##"]);
    assert.equal(toks("##"), ["Hash #", "Hash #"]);
    assert.equal(toks("#\"a\\\"#"), ["LegacyHashString #\"a\\\"#"]);
}

test "backtick templates" {
    assert.equal(
        toks("`hi ${name}!`"),
        [
            "BacktickStart `",
            "TemplateChunk hi ",
            "DollarLBrace ${",
            "Word name",
            "RBrace }",
            "TemplateChunk !",
            "BacktickEnd `",
        ],
    );
    assert.equal(toks("`$ {x} $`"), ["BacktickStart `", "TemplateChunk $ {x} $", "BacktickEnd `"]);
    assert.equal(toks("`\\${x}`"), ["BacktickStart `", "TemplateChunk \\${x}", "BacktickEnd `"]);
    assert.equal(toks("`a\\`b`"), ["BacktickStart `", "TemplateChunk a\\`b", "BacktickEnd `"]);
    assert.equal(toks("`a\\ `"), ["BacktickStart `", "TemplateChunk a\\ ", "BacktickEnd `"]);
    assert.equal(toks("`a\n  b`"), ["BacktickStart `", "TemplateChunk a\n  b", "BacktickEnd `"]);
    assert.equal(
        toks("`see // not a comment`"),
        ["BacktickStart `", "TemplateChunk see // not a comment", "BacktickEnd `"],
    );
}

// backtick_templates: 4 assert(s) not in table form, not ported

test "multi tick templates" {
    assert.equal(
        toks("```content````"),
        ["BacktickStart ```", "TemplateChunk content`", "BacktickEnd ```"],
    );
    assert.equal(
        toks("```a`b``c```"),
        ["BacktickStart ```", "TemplateChunk a`b``c", "BacktickEnd ```"],
    );
    assert.equal(toks("`a``b"), ["BacktickStart `", "TemplateChunk a`", "BacktickEnd `", "Word b"]);
    assert.equal(toks("``x``"), ["BacktickStart ``", "TemplateChunk x", "BacktickEnd ``"]);
    assert.equal(
        toks("let x = ``\nfunction f() -> int { 1 }"),
        [
            "Let let",
            "Whitespace  ",
            "Word x",
            "Whitespace  ",
            "Equals =",
            "Whitespace  ",
            "BacktickStart ``",
            "TemplateChunk \nfunction f() -> int { 1 }",
        ],
    );
    assert.equal(toks("``\nx``"), ["BacktickStart ``", "TemplateChunk \nx", "BacktickEnd ``"]);
}

test "unterminated templates run to the end" {
    assert.equal(toks("`abc"), ["BacktickStart `", "TemplateChunk abc"]);
    assert.equal(toks("`${x"), ["BacktickStart `", "DollarLBrace ${", "Word x"]);
}

test "braces in code do not end the file" {
    assert.equal(sig("} }"), ["RBrace }", "RBrace }"]);
}

test "newline tokens" {
    assert.equal(
        toks("a\r\nb\nc\r"),
        ["Word a", "Newline \r\n", "Word b", "Newline \n", "Word c", "Error \r"],
    );
    assert.equal(toks(" \t "), ["Whitespace  \t "]);
}

// not ported (no table asserts): token_indices_line_up
// not ported (no table asserts): corpus_kinds_fit
// not ported (no table asserts): random_input_round_trips
// Test helpers, port of the top of lexer/tests.rs.

// "Kind text" for each token of `text`, trivia included or not.
function render(text: string, with_trivia: bool) -> string[] throws never {
    let tokens = lex(text);
    let utf8 = text.to_utf8();
    let out: string[] = [];
    for (let i = 0; i < tokens.len(); i += 1) {
        let kind = tokens.kinds[i];
        if (with_trivia || !is_trivia(kind)) {
            out.push(`${kind} ${tokens.text(utf8, i)}`);
        }
    }
    out
}

// port: tests.rs::toks
function toks(text: string) -> string[] throws never {
    render(text, true)
}

// port: tests.rs::sig
function sig(text: string) -> string[] throws never {
    render(text, false)
}
