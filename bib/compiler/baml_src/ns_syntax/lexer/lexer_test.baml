// port: baml_syntax/src/lexer/tests.rs @ d9be6853b
// The table-style asserts, carried over by a one-off script. Tests built
// on loops or helpers are ported by hand below the generated ones.

// not ported (no table asserts): every_fixed_spelling_lexes_to_its_kind
test "composites that are not tokens split" {
    assert.equal(lexed("a ?? b"), ["Word a", "Question ?", "Question ?", "Word b"]);
    assert.equal(lexed("x >> 1"), ["Word x", "Greater >", "Greater >", "Integer 1"]);
    assert.equal(lexed("x >>= 1"), ["Word x", "Greater >", "Greater >", "Equals =", "Integer 1"]);
    assert.equal(lexed("...."), ["DotDotDot ...", "Dot ."]);
    assert.equal(lexed("x->y"), ["Word x-", "Greater >", "Word y"]);
}

test "words hyphens and dollars" {
    assert.equal(lexed("gpt-4o a- a--b x-1"), ["Word gpt-4o", "Word a-", "Word a--b", "Word x-1"]);
    assert.equal(lexed("Foo$bar"), ["Word Foo$bar"]);
    assert.equal(lexed("foo$"), ["Word foo", "Dollar $"]);
    assert.equal(lexed("$foo-bar"), ["Word $foo", "Minus -", "Word bar"]);
    assert.equal(lexed("$1"), ["Dollar $", "Integer 1"]);
    assert.equal(lexed("_ _1"), ["Underscore _", "Word _1"]);
    assert.equal(
        lexed("get_client catch_all_panics catch_all classy"),
        ["Word get_client", "CatchAllPanics catch_all_panics", "CatchAll catch_all", "Word classy"],
    );
    assert.equal(lexed("type-x type"), ["Word type-x", "Type type"]);
}

test "non ascii outside strings is one error per char" {
    assert.equal(lexed("'", trivia = true), ["Error '"]);
}

test "numbers" {
    assert.equal(
        lexed("42n 42na 42n.5"),
        ["Bigint 42n", "Bigint 42n", "Word a", "Bigint 42n", "Dot .", "Integer 5"],
    );
    assert.equal(lexed("0xfn 1e5n"), ["Bigint 0xfn", "Float 1e5", "Word n"]);
    assert.equal(
        lexed("0x 0b_ 0X1F 0b123 0o18"),
        ["Integer 0x", "Integer 0b_", "Integer 0X1F", "Integer 0b123", "Integer 0o18"],
    );
    assert.equal(
        lexed("0xG 0b1f 0x1.5"),
        ["Integer 0x", "Word G", "Integer 0b1", "Word f", "Integer 0x1", "Dot .", "Integer 5"],
    );
    assert.equal(
        lexed("3.foo 1._5"),
        ["Integer 3", "Dot .", "Word foo", "Integer 1", "Dot .", "Word _5"],
    );
    assert.equal(
        lexed("1..2 1...2 1.5.3"),
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
        lexed("1_.5 1_000.000_1 1e1_ 1_0e1_0 1_"),
        ["Float 1_.5", "Float 1_000.000_1", "Float 1e1_", "Float 1_0e1_0", "Integer 1_"],
    );
    assert.equal(
        lexed("1e 1e_1 1e+ 1.e5"),
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
        lexed("1.0 3.14 1E3 1e-3 2e+5 1.5e-3"),
        ["Float 1.0", "Float 3.14", "Float 1E3", "Float 1e-3", "Float 2e+5", "Float 1.5e-3"],
    );
}

test "comments" {
    assert.equal(
        lexed("// a  \r\nx", trivia = true),
        ["LineComment // a  ", "Newline \r\n", "Word x"],
    );
    assert.equal(lexed("//# section\n", trivia = true), ["HeaderComment //# section", "Newline \n"]);
    assert.equal(lexed("/// doc", trivia = true), ["DocComment /// doc"]);
    assert.equal(lexed("////x", trivia = true), ["LineComment ////x"]);
    assert.equal(lexed("///#", trivia = true), ["DocComment ///#"]);
    assert.equal(lexed("//baml:mut_self", trivia = true), ["DirectiveComment //baml:mut_self"]);
    assert.equal(lexed("// baml:x", trivia = true), ["LineComment // baml:x"]);
    assert.equal(lexed("// #", trivia = true), ["LineComment // #"]);
    assert.equal(lexed("//=====", trivia = true), ["LineComment //====="]);
    assert.equal(lexed("///=", trivia = true), ["DocComment ///="]);
    assert.equal(
        lexed("#!/usr/bin/env baml\nx", trivia = true),
        ["LineComment #!/usr/bin/env baml", "Newline \n", "Word x"],
    );
    assert.equal(lexed("#!=", trivia = true), ["LineComment #!="]);
    assert.equal(lexed("/* a **/x", trivia = true), ["BlockComment /* a **/", "Word x"]);
    assert.equal(lexed("/**/", trivia = true), ["BlockComment /**/"]);
    assert.equal(
        lexed("/* /* */ */", trivia = true),
        ["BlockComment /* /* */", "Whitespace  ", "Star *", "Slash /"],
    );
    assert.equal(lexed("/*/ x", trivia = true), ["UnclosedBlockComment /*/ x"]);
    assert.equal(
        lexed("/* */= x", trivia = true),
        ["BlockComment /* */", "Equals =", "Whitespace  ", "Word x"],
    );
    assert.equal(lexed("/* open", trivia = true), ["UnclosedBlockComment /* open"]);
    assert.equal(lexed("/*= x", trivia = true), ["UnclosedBlockComment /*= x"]);
    assert.equal(
        lexed("/* a\n*/ b", trivia = true),
        ["BlockComment /* a\n*/", "Whitespace  ", "Word b"],
    );
}

test "line comments sharing the directive prefix" {
    assert.equal(
        lexed("x //bad\ny", trivia = true),
        ["Word x", "Whitespace  ", "LineComment //bad", "Newline \n", "Word y"],
    );
    assert.equal(lexed("//baml:x", trivia = true), ["DirectiveComment //baml:x"]);
    assert.equal(lexed("//#x", trivia = true), ["HeaderComment //#x"]);
    assert.equal(lexed("///x", trivia = true), ["DocComment ///x"]);
}

// line_comments_sharing_the_directive_prefix: 1 assert(s) not in table form, not ported

test "stray hash" {
    assert.equal(
        lexed("#\n\nclass", trivia = true),
        ["Hash #", "Newline \n", "Newline \n", "Class class"],
    );
    assert.equal(lexed("# x", trivia = true), ["Hash #", "Whitespace  ", "Word x"]);
    assert.equal(lexed("#!x", trivia = true), ["LineComment #!x"]);
    assert.equal(lexed("#\"x\"#", trivia = true), ["LegacyHashString #\"x\"#"]);
}

test "strings" {
    assert.equal(lexed("\"a\\\"b\"", trivia = true), ["String \"a\\\"b\""]);
    assert.equal(lexed("\"a\\\\\" ", trivia = true), ["String \"a\\\\\"", "Whitespace  "]);
    assert.equal(lexed("\"a\\\\\\\"b\"", trivia = true), ["String \"a\\\\\\\"b\""]);
    assert.equal(lexed("\"\\ \"", trivia = true), ["String \"\\ \""]);
    assert.equal(lexed("\"a\nb\"", trivia = true), ["String \"a\nb\""]);
    assert.equal(lexed("\"#! not a comment\"", trivia = true), ["String \"#! not a comment\""]);
    assert.equal(lexed("\"http://x\"", trivia = true), ["String \"http://x\""]);
    assert.equal(
        lexed("r\"\\d+\\\"\" b\"x\" r \"x\" rb\"x\" bar\"x\" 1r\"x\""),
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
    assert.equal(
        lexed("\"ab  \n", trivia = true),
        ["UnclosedString \"ab", "Whitespace   ", "Newline \n"],
    );
    assert.equal(lexed("\"ab\\   ", trivia = true), ["UnclosedString \"ab\\   "]);
    assert.equal(lexed("r\"x", trivia = true), ["UnclosedRawString r\"x"]);
    assert.equal(lexed("b\"x", trivia = true), ["UnclosedByteString b\"x"]);
}

test "hash strings" {
    assert.equal(lexed("#\"a\"#", trivia = true), ["LegacyHashString #\"a\"#"]);
    assert.equal(lexed("##\"x\"#\"##", trivia = true), ["LegacyHashString ##\"x\"#\"##"]);
    assert.equal(lexed("#\"a\" #b", trivia = true), ["LegacyHashString #\"a\" #", "Word b"]);
    assert.equal(lexed("# \"a\"#", trivia = true), ["LegacyHashString # \"a\"#"]);
    assert.equal(lexed("#\"a\"##", trivia = true), ["UnclosedHashString #\"a\"##"]);
    assert.equal(lexed("##", trivia = true), ["Hash #", "Hash #"]);
    assert.equal(lexed("#\"a\\\"#", trivia = true), ["LegacyHashString #\"a\\\"#"]);
}

test "backtick templates" {
    assert.equal(
        lexed("`hi ${name}!`", trivia = true),
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
    assert.equal(
        lexed("`$ {x} $`", trivia = true),
        ["BacktickStart `", "TemplateChunk $ {x} $", "BacktickEnd `"],
    );
    assert.equal(
        lexed("`\\${x}`", trivia = true),
        ["BacktickStart `", "TemplateChunk \\${x}", "BacktickEnd `"],
    );
    assert.equal(
        lexed("`a\\`b`", trivia = true),
        ["BacktickStart `", "TemplateChunk a\\`b", "BacktickEnd `"],
    );
    assert.equal(
        lexed("`a\\ `", trivia = true),
        ["BacktickStart `", "TemplateChunk a\\ ", "BacktickEnd `"],
    );
    assert.equal(
        lexed("`a\n  b`", trivia = true),
        ["BacktickStart `", "TemplateChunk a\n  b", "BacktickEnd `"],
    );
    assert.equal(
        lexed("`see // not a comment`", trivia = true),
        ["BacktickStart `", "TemplateChunk see // not a comment", "BacktickEnd `"],
    );
}

// backtick_templates: 4 assert(s) not in table form, not ported

test "multi tick templates" {
    assert.equal(
        lexed("```content````", trivia = true),
        ["BacktickStart ```", "TemplateChunk content`", "BacktickEnd ```"],
    );
    assert.equal(
        lexed("```a`b``c```", trivia = true),
        ["BacktickStart ```", "TemplateChunk a`b``c", "BacktickEnd ```"],
    );
    assert.equal(
        lexed("`a``b", trivia = true),
        ["BacktickStart `", "TemplateChunk a`", "BacktickEnd `", "Word b"],
    );
    assert.equal(
        lexed("``x``", trivia = true),
        ["BacktickStart ``", "TemplateChunk x", "BacktickEnd ``"],
    );
    assert.equal(
        lexed("let x = ``\nfunction f() -> int { 1 }", trivia = true),
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
    assert.equal(
        lexed("``\nx``", trivia = true),
        ["BacktickStart ``", "TemplateChunk \nx", "BacktickEnd ``"],
    );
}

test "unterminated templates run to the end" {
    assert.equal(lexed("`abc", trivia = true), ["BacktickStart `", "TemplateChunk abc"]);
    assert.equal(lexed("`${x", trivia = true), ["BacktickStart `", "DollarLBrace ${", "Word x"]);
}

test "braces in code do not end the file" {
    assert.equal(lexed("} }"), ["RBrace }", "RBrace }"]);
}

test "newline tokens" {
    assert.equal(
        lexed("a\r\nb\nc\r", trivia = true),
        ["Word a", "Newline \r\n", "Word b", "Newline \n", "Word c", "Error \r"],
    );
    assert.equal(lexed(" \t ", trivia = true), ["Whitespace  \t "]);
}

// not ported (no table asserts): token_indices_line_up
// not ported (no table asserts): corpus_kinds_fit
// not ported (no table asserts): random_input_round_trips
// Test helper, port of `toks` and `sig` at the top of lexer/tests.rs:
// "Kind text" for each token of `text`, trivia only when asked for.
function lexed(text: string, trivia: bool = false) -> string[] throws never {
    let tokens = lex(text);
    let utf8 = text.to_utf8();
    let out: string[] = [];
    for (let i = 0; i < tokens.kinds.length(); i += 1) {
        let kind = tokens.kinds[i];
        if (trivia || !is_trivia(kind)) {
            out.push(`${kind} ${tokens.text(utf8, i)}`);
        }
    }
    out
}
