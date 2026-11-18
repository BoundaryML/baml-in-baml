// port: baml_base/src/escape.rs::tests @ d9be6853b

// port: escape.rs::tests::issue_kinds
function issue_kinds(input: string) -> EscapeIssueKind[] throws never {
    string_literal_escape_issues(input).map((issue) -> {
        issue.kind
    })
}

// port: escape.rs::tests::issue_spans. Each issue's text, read back from
// `input` by its byte offsets.
function issue_spans(input: string) -> string[] throws never {
    let bytes = input.to_utf8();
    string_literal_escape_issues(input).map((issue) -> {
        string.from_utf8(bytes.slice(issue.start, issue.start + issue.len)) catch (e) {
            baml.errors.InvalidArgument => baml.sys.panic("an issue covers whole characters"),
        }
    })
}

// An issue with only `start`, `text`, `kind` and `literal` set: the fields
// the Rust test compares as a tuple.
function issue_fields(
    start: int,
    text: string,
    kind: EscapeIssueKind,
    literal: LiteralKind,
) -> EscapeIssue throws never {
    EscapeIssue {
        start: start,
        len: 0,
        text: text,
        kind: kind,
        literal: literal,
        suggest_raw_string: false,
    }
}

// port: escape.rs::tests::message. The message of the one issue in `issues`.
function message(issues: EscapeIssue[]) -> string throws never {
    if (issues.length() != 1) {
        baml.sys.panic(`expected one issue, got ${issues}`);
    }
    escape_issue_message(issues[0])
}

test "decodes simple escapes" {
    assert.equal(unescape_string_literal(r"line\nbreak"), "line\nbreak");
    assert.equal(unescape_string_literal(r"tab\there"), "tab\there");
    assert.equal(unescape_string_literal(r"cr\rhere"), "cr\rhere");
    assert.equal(unescape_string_literal(r"nul\0here"), "nul\0here");
    assert.equal(unescape_string_literal(r"back\\slash"), "back\\slash");
    assert.equal(unescape_string_literal("say \\\"hi\\\""), "say \"hi\"");
    assert.equal(unescape_string_literal(r"it\'s"), "it's");
    assert.equal(unescape_string_literal(r"a\bb"), "a\u{0008}b");
    assert.equal(unescape_string_literal(r"a\fb"), "a\u{000C}b");
    assert.equal(unescape_string_literal(r"https:\/\/x.com"), "https://x.com");
    assert.equal(unescape_string_literal(r"a\`b\$c"), "a`b$c");
    assert.equal(issue_kinds("\\n\\t\\r\\b\\f\\0\\\\\\\"\\'\\`\\$\\/"), [])
}

test "nul is never octal" {
    assert.equal(unescape_string_literal(r"\01"), "\u{0}1");
    assert.equal(issue_kinds(r"\01"), []);
    assert.equal(issue_kinds(r"\101"), [Unknown { ch: "1" }])
}

test "decodes ascii hex escapes" {
    assert.equal(unescape_string_literal(r"\x41\x7f\x00"), "A\u{7F}\u{0}");
    assert.equal(issue_kinds(r"\x41\x7F"), [])
}

test "rejects non ascii or malformed hex escapes" {
    assert.equal(issue_kinds(r"\xE9"), [NonAsciiHex { byte: 0xE9 }]);
    assert.equal(issue_spans(r"a\xE9b"), [r"\xE9"]);
    assert.equal(issue_kinds(r"\x4"), [InvalidHex {}]);
    assert.equal(issue_spans(r"\x4g"), [r"\x4"]);
    assert.equal(issue_spans(r"\x"), [r"\x"])
}

test "decodes unicode escapes" {
    assert.equal(unescape_string_literal(r"é"), "é");
    assert.equal(unescape_string_literal(r"中"), "中");
    assert.equal(unescape_string_literal(r"\u{41}"), "A");
    assert.equal(unescape_string_literal(r"\u{1F600}"), "😀");
    assert.equal(unescape_string_literal(r"\u{10FFFF}"), "\u{10FFFF}");
    assert.equal(unescape_string_literal(r"\u{1F_600}"), "😀");
    assert.equal(unescape_string_literal(r"\u{4_1}"), "A");
    assert.equal(unescape_string_literal(r"\u{00_0041}"), "A")
}

test "pairs surrogates in any form" {
    for (let pair in [r"😀", r"\uD83D\u{DE00}", r"\u{D83D}\uDE00", r"\u{D83D}\u{DE00}"]) {
        assert.equal(unescape_string_literal(pair), "😀");
        assert.equal(issue_kinds(pair), []);
    }
}

test "rejects unpaired surrogates" {
    assert.equal(issue_kinds(r"\uD83D"), [LoneSurrogate { value: 0xD83D }]);
    assert.equal(issue_kinds(r"\uDE00"), [LoneSurrogate { value: 0xDE00 }]);
    assert.equal(
        issue_kinds(r"\u{DE00}\uD83D"),
        [LoneSurrogate { value: 0xDE00 }, LoneSurrogate { value: 0xD83D }],
    );
    // A high surrogate followed by something other than a low surrogate
    // reports only the high surrogate; the next escape decodes normally.
    assert.equal(issue_spans(r"\uD83DA"), [r"\uD83D"]);
    assert.equal(unescape_string_literal(r"\uD83DA"), "\\uD83DA");
    assert.equal(issue_spans(r"\uD83Dx\uDE00"), [r"\uD83D", r"\uDE00"])
}

test "rejects malformed unicode escapes" {
    assert.equal(issue_kinds(r"\u12"), [InvalidUnicode { error: Malformed {} }]);
    assert.equal(issue_spans(r"\u12x"), [r"\u12"]);
    assert.equal(issue_kinds(r"\u{}"), [InvalidUnicode { error: Empty {} }]);
    assert.equal(issue_kinds(r"\u{41"), [InvalidUnicode { error: Unterminated {} }]);
    assert.equal(issue_spans(r"\u{41 x}"), [r"\u{41"]);
    assert.equal(issue_kinds(r"\u{12g4}"), [InvalidUnicode { error: InvalidChar { ch: "g" } }]);
    assert.equal(issue_spans(r"\u{12g4}"), [r"\u{12g"]);
    assert.equal(issue_kinds(r"\u{0000041}"), [InvalidUnicode { error: TooLong {} }]);
    assert.equal(issue_kinds(r"\u{_41}"), [InvalidUnicode { error: MisplacedUnderscore {} }]);
    assert.equal(issue_kinds(r"\u{41_}"), [InvalidUnicode { error: MisplacedUnderscore {} }]);
    assert.equal(issue_kinds(r"\u{1__F}"), [InvalidUnicode { error: MisplacedUnderscore {} }]);
    assert.equal(issue_kinds(r"\u{110000}"), [OutOfRange {}])
}

test "rejects python unicode escapes" {
    assert.equal(issue_kinds(r"\U0001F600"), [LongUnicode {}]);
    assert.equal(issue_spans(r"\U0001F600!"), [r"\U0001F600"]);
    assert.equal(issue_kinds(r"\N{GRINNING FACE}"), [NamedUnicode {}]);
    assert.equal(issue_spans(r"\N{GRINNING FACE}!"), [r"\N{GRINNING FACE}"])
}

test "rejects unknown escapes" {
    for (let input in [r"\d+", r"\v", r"\a", r"\e", r"\q"]) {
        assert.equal(issue_kinds(input), [Unknown { ch: input.at(1) ?? "" }]);
    }
    assert.equal(issue_spans(r"a\d+b\é"), [r"\d", r"\é"]);
    // Unknown escapes are kept verbatim by the lenient decoder.
    assert.equal(unescape_string_literal(r"\d+"), r"\d+")
}

test "rejects line continuation" {
    assert.equal(issue_kinds("a\\\nb"), [Unknown { ch: "\n" }]);
    // The span stops at the backslash so it stays on one line.
    assert.equal(issue_spans("a\\\nb"), ["\\"])
}

test "issue offsets are byte offsets" {
    let issues = string_literal_escape_issues(r"é\q");
    assert.equal(issues[0].start, 2);
    assert.equal(issues[0].len, 2)
}

test "handles empty plain and trailing backslash" {
    assert.equal(unescape_string_literal(""), "");
    assert.equal(unescape_string_literal("plain text"), "plain text");
    assert.equal(unescape_string_literal("trailing\\"), "trailing\\")
}

test "backtick uses the same escapes" {
    assert.equal(unescape_backtick_string_literal(r"line\nbreak"), "line\nbreak");
    assert.equal(unescape_backtick_string_literal(r"a\`b"), "a`b");
    assert.equal(unescape_backtick_string_literal(r"a\${x}b"), "a${x}b");
    assert.equal(unescape_backtick_string_literal(r"\u{1F600}"), "😀");
    let issues = backtick_string_literal_escape_issues(r"\d \v").map((issue) -> {
        issue_fields(issue.start, issue.text, issue.kind, issue.literal)
    });
    assert.equal(
        issues,
        [
            issue_fields(0, r"\d", Unknown { ch: "d" }, LiteralKind.Backtick),
            issue_fields(3, r"\v", Unknown { ch: "v" }, LiteralKind.Backtick),
        ],
    )
}

test "backtick normalizes line endings" {
    // BEP-049 §AA / TypeScript-go scanner.go:1650-1660.
    assert.equal(unescape_backtick_string_literal("line1\r\nline2"), "line1\nline2");
    assert.equal(unescape_backtick_string_literal("line1\rline2"), "line1\nline2");
    assert.equal(unescape_backtick_string_literal("a\r\nb\rc\nd"), "a\nb\nc\nd")
}

test "quote flavor does not normalize cr" {
    // The CR/CRLF normalization is backtick-specific (BEP-049 §12).
    assert.equal(unescape_string_literal("a\r\nb"), "a\r\nb")
}

test "byte strings decode escapes and any hex byte" {
    assert.equal(unescape_byte_string_literal("GIF89a"), "GIF89a".to_utf8());
    assert.equal(unescape_byte_string_literal(r"a\nb"), "a\nb".to_utf8());
    assert.equal(unescape_byte_string_literal(r"\xFF\x00\xc3").to_array(), [0xFF, 0, 0xC3]);
    assert.equal(
        unescape_byte_string_literal("\\'\\b\\f\\/\\`\\$\\\\\\\""),
        "'\u{08}\u{0C}/`$\\\"".to_utf8(),
    );
    assert.equal(byte_string_literal_escape_issues(r"\xFF\'\b\f\/\`\$"), [])
}

test "byte strings reject unicode escapes and non ascii" {
    let issues = byte_string_literal_escape_issues(r"\u{E9}");
    assert.equal(issues[0].kind, UnicodeInByteString { utf8: [0xC3, 0xA9] });
    assert.equal(issues[0].len, r"\u{E9}".byte_length());
    assert.equal(
        byte_string_literal_escape_issues(r"\u{}")[0].kind,
        UnicodeInByteString { utf8: null },
    );
    let non_ascii = byte_string_literal_escape_issues("aé");
    assert.equal(non_ascii[0].kind, NonAsciiInByteString { ch: "é" });
    assert.equal([non_ascii[0].start, non_ascii[0].len], [1, 2]);
    assert.equal(byte_string_literal_escape_issues(r"\d")[0].kind, Unknown { ch: "d" })
}

test "messages quote in the literals own syntax" {
    assert.equal(
        message(string_literal_escape_issues(r"\d")),
        "unknown escape sequence \"\\d\" - did you mean \"\\\\d\" (escaped backslash) or r\"\\d\" (raw string)?",
    );
    assert.equal(
        message(backtick_string_literal_escape_issues(r"\d")),
        r"unknown escape sequence `\d` - did you mean `\\d` (escaped backslash)?",
    );
    assert.equal(
        message(byte_string_literal_escape_issues(r"\d")),
        "unknown escape sequence b\"\\d\" - did you mean b\"\\\\d\" (escaped backslash)?",
    );
    assert.equal(
        message(string_literal_escape_issues("a\\\nb")),
        "unknown escape sequence: \"\\\" followed by a newline - did you mean \"\\\\\" (escaped backslash)? BAML has no line continuations.",
    );
    assert.equal(
        message(string_literal_escape_issues(r"\U0001F600")),
        "unsupported escape sequence \"\\U0001F600\" - use \"\\u{...}\" for a Unicode code point",
    );
    assert.equal(
        message(backtick_string_literal_escape_issues(r"\N{GRINNING FACE}")),
        r"unsupported escape sequence `\N{GRINNING FACE}` - use `\u{...}` for a Unicode code point",
    );
    assert.equal(
        message(byte_string_literal_escape_issues(r"\u{E9}")),
        "invalid escape sequence b\"\\u{E9}\" - byte strings can't contain Unicode escapes; did you mean b\"\\xC3\\xA9\" (UTF-8 bytes)?",
    );
    assert.equal(
        message(byte_string_literal_escape_issues("é")),
        "non-ASCII character b\"é\" in byte string - did you mean b\"\\xC3\\xA9\" (UTF-8 bytes)?",
    )
}
