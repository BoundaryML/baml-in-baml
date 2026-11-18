// port: baml_base/src/escape.rs @ d9be6853b
//
// String-literal escape decoding: the single source of truth for escape
// sequences across the compiler, for `"..."`, backtick `...` and `b"..."`
// literals. Raw `r"..."` literals process no escapes.
//
// Recognized escapes (every literal):
// - `\\`, `\"`, `\'`, `\``, `\$`, `\/`
// - `\n`, `\t`, `\r`, `\b` (U+0008), `\f` (U+000C), `\0` (always NUL; BAML
//   has no octal escapes, so `\01` is NUL followed by `1`)
// - `\xHH`: exactly two hex digits. Strings accept `\x00`-`\x7F` only; byte
//   strings accept any byte value.
// - `\uHHHH` and `\u{H...}` (strings only): `\u{...}` takes 1-6 hex digits,
//   with `_` allowed between digits. A high surrogate immediately followed by
//   a low surrogate, in either form, combines into one code point.
//   An unpaired surrogate is invalid.
//
// Anything else after a backslash is an `EscapeIssue`. Decoding is lenient:
// an offending sequence is kept verbatim in the decoded value, and the
// compiler reports it through the `*_escape_issues` functions, which run the
// same scanner.
//
// deviation: the scanner walks the input as characters (`string.chars()`),
// not bytes; lengths inside the scanner are in characters, and an issue's
// `start`/`len` are converted to byte offsets when it is recorded.

// port: escape.rs::unescape_string_literal. Decode escapes for a regular
// `"..."` string literal body (quotes already stripped).
function unescape_string_literal(input: string) -> string throws never {
    decode_str(input, LiteralKind.Quoted, [])
}

// port: escape.rs::unescape_backtick_string_literal. Decode escapes for a
// backtick string literal body (delimiters already stripped).
function unescape_backtick_string_literal(input: string) -> string throws never {
    decode_str(input, LiteralKind.Backtick, [])
}

// port: escape.rs::unescape_byte_string_literal. Decode escapes for a
// `b"..."` byte string literal body.
function unescape_byte_string_literal(input: string) -> uint8array throws never {
    let bytes: int[] = [];
    scan(
        input,
        LiteralKind.Bytes,
        (piece) -> {
            match (piece) {
                let c: Char => push_utf8(bytes, c.ch),
                let b: Byte => {
                    bytes.push(b.byte);
                },
                let v: Verbatim => push_utf8(bytes, v.text),
            };
        },
        [],
    );
    uint8array.from_array(bytes) catch (e) {
        baml.errors.InvalidArgument => baml.sys.panic("decoded bytes are in 0..=255"),
    }
}

// port: escape.rs::string_literal_escape_issues. Invalid escape sequences in
// a regular `"..."` string literal body. Offsets are byte offsets into
// `input`.
function string_literal_escape_issues(input: string) -> EscapeIssue[] throws never {
    let issues: EscapeIssue[] = [];
    scan(
        input,
        LiteralKind.Quoted,
        (piece) -> {},
        issues,
    );
    issues
}

// port: escape.rs::backtick_string_literal_escape_issues. Invalid escape
// sequences in one literal-text run of a backtick string literal.
function backtick_string_literal_escape_issues(input: string) -> EscapeIssue[] throws never {
    let issues: EscapeIssue[] = [];
    scan(
        input,
        LiteralKind.Backtick,
        (piece) -> {},
        issues,
    );
    issues
}

// port: escape.rs::byte_string_literal_escape_issues. Invalid escape
// sequences and non-ASCII characters in a `b"..."` byte string literal body.
function byte_string_literal_escape_issues(input: string) -> EscapeIssue[] throws never {
    let issues: EscapeIssue[] = [];
    scan(
        input,
        LiteralKind.Bytes,
        (piece) -> {},
        issues,
    );
    issues
}

// port: escape.rs::EscapeIssue. A sequence in a literal body that does not
// decode. The decoded value keeps it verbatim.
class EscapeIssue {
    // Byte offset of the start of the sequence (normally the backslash).
    start: int,
    // Byte length of the offending sequence.
    len: int,
    // The offending source text, `len` bytes from `start`.
    text: string,
    kind: EscapeIssueKind,
    // The kind of literal the sequence appears in, so messages can quote it in
    // the same syntax.
    literal: LiteralKind,
    // Whether an unknown escape's message also suggests a raw `r"..."` string.
    // Starts true for quoted literals; the caller clears it where raw strings
    // aren't accepted (types, patterns, attributes, ...).
    suggest_raw_string: bool,
}

// port: escape.rs::LiteralKind. The kind of literal an `EscapeIssue` comes
// from.
enum LiteralKind {
    // `"..."`
    Quoted,
    // `...` in backticks
    Backtick,
    // `b"..."`
    Bytes,
}

// port: escape.rs::EscapeIssueKind
type EscapeIssueKind = Unknown
    | LongUnicode
    | NamedUnicode
    | InvalidHex
    | NonAsciiHex
    | InvalidUnicode
    | OutOfRange
    | LoneSurrogate
    | UnicodeInByteString
    | NonAsciiInByteString;

// `\` followed by a character that is not an escape (e.g. `\d`, `\v`).
class Unknown {
    ch: string,
}

// `\UHHHHHHHH` (Python's long Unicode escape).
class LongUnicode {
}

// `\N{name}` (Python's named Unicode escape).
class NamedUnicode {
}

// `\x` not followed by two hex digits.
class InvalidHex {
}

// `\x80`-`\xFF` outside a byte string.
class NonAsciiHex {
    byte: int,
}

// A malformed `\u` escape.
class InvalidUnicode {
    error: UnicodeEscapeError,
}

// `\u{...}` naming a value above U+10FFFF.
class OutOfRange {
}

// A surrogate code point that is not half of a high/low pair.
class LoneSurrogate {
    value: int,
}

// A `\u` escape in a byte string. `utf8` holds the code point's UTF-8
// encoding when the escape is otherwise valid.
class UnicodeInByteString {
    utf8: int[]?,
}

// A literal non-ASCII character in a byte string.
class NonAsciiInByteString {
    ch: string,
}

// port: escape.rs::UnicodeEscapeError. Why a `\u` escape is malformed.
type UnicodeEscapeError = Malformed
    | Unterminated
    | InvalidChar
    | Empty
    | TooLong
    | MisplacedUnderscore;

// `\u` followed by neither four hex digits nor `{`.
class Malformed {
}

// `\u{` without a closing `}`.
class Unterminated {
}

// A character other than a hex digit or `_` inside `\u{...}`.
class InvalidChar {
    ch: string,
}

// `\u{}`.
class Empty {
}

// More than six hex digits inside `\u{...}`.
class TooLong {
}

// `_` at the start or end of the digits in `\u{...}`.
class MisplacedUnderscore {
}

// port: escape.rs::EscapeIssueKind::label. A short label for the offending
// span.
// deviation: takes the whole issue, as the diagnostic layer holds one.
function escape_issue_label(issue: EscapeIssue) -> string throws never {
    match (issue.kind) {
        Unknown {} => "unknown escape",
        LongUnicode {} | NamedUnicode {} => "unsupported escape",
        NonAsciiInByteString {} => "non-ASCII character",
        _ => "invalid escape",
    }
}

// port: escape.rs::LiteralKind::quote. `body` spelled as a literal of this
// kind, so a message quotes source text in the same syntax the user wrote it
// in.
function quote(literal: LiteralKind, body: string) -> string throws never {
    match (literal) {
        LiteralKind.Quoted => `"${body}"`,
        LiteralKind.Bytes => `b"${body}"`,
        LiteralKind.Backtick if body.includes("`") => `\`\` ${body} \`\``,
        LiteralKind.Backtick => `\`${body}\``,
    }
}

// port: escape.rs::impl Display for EscapeIssue. The message for `issue`.
function escape_issue_message(issue: EscapeIssue) -> string throws never {
    let literal = issue.literal;
    let text = quote(literal, issue.text);
    match (issue.kind) {
        let k: Unknown => unknown_escape_message(issue, k.ch, text),
        LongUnicode {} | NamedUnicode {} => {
            `unsupported escape sequence ${text} - use ${quote(literal, "\\u{...}")} for a Unicode code point`
        },
        InvalidHex {} => {
            `invalid escape sequence ${text} - ${quote(literal, "\\x")} must be followed by exactly two hex digits`
        },
        NonAsciiHex {} => {
            `out of range escape sequence ${text} - ${quote(literal, "\\x")} escapes in strings only go up to ${quote(literal, "\\x7F")}; use ${quote(literal, "\\u{...}")} for a non-ASCII character, or a byte string b"..." for raw bytes`
        },
        let k: InvalidUnicode => {
            `invalid escape sequence ${text} - ${unicode_escape_error_message(literal, k.error)}`
        },
        OutOfRange {} => `invalid escape sequence ${text} - the value exceeds U+10FFFF`,
        let k: LoneSurrogate => {
            `invalid escape sequence ${text} - unpaired UTF-16 surrogate U+${upper_hex(k.value, 4)}; a high surrogate (U+D800-U+DBFF) must be immediately followed by a low surrogate (U+DC00-U+DFFF)`
        },
        let k: UnicodeInByteString => {
            let fix = match (k.utf8) {
                let bytes: int[] => {
                    `did you mean ${quote(literal, hex_bytes(bytes))} (UTF-8 bytes)?`
                },
                null => `write the UTF-8 bytes with ${quote(literal, "\\xHH")}`,
            };
            `invalid escape sequence ${text} - byte strings can't contain Unicode escapes; ${fix}`
        },
        let k: NonAsciiInByteString => {
            `non-ASCII character ${text} in byte string - did you mean ${quote(literal, hex_bytes(k.ch.to_utf8().to_array()))} (UTF-8 bytes)?`
        },
    }
}

// The `Unknown` arm of `impl Display for EscapeIssue`: a blank or control
// character after the backslash is named, anything else quoted.
function unknown_escape_message(
    issue: EscapeIssue,
    c: string,
    text: string,
) -> string throws never {
    let literal = issue.literal;
    if (c.is_whitespace() || c.is_control()) {
        let message = `unknown escape sequence: ${quote(literal, "\\")} followed by ${describe_char(c)} - did you mean ${quote(literal, "\\\\")} (escaped backslash)?`;
        if (c == "\n" || c == "\r") {
            return `${message} BAML has no line continuations.`;
        }
        return message;
    }
    let raw = if (issue.suggest_raw_string) {
        ` or r"\\${c}" (raw string)`
    } else {
        ""
    };
    `unknown escape sequence ${text} - did you mean ${quote(literal, `\\\\${c}`)} (escaped backslash)${raw}?`
}

// The `InvalidUnicode` arm of `impl Display for EscapeIssue`: what is wrong
// with the `\u` escape.
function unicode_escape_error_message(
    literal: LiteralKind,
    error: UnicodeEscapeError,
) -> string throws never {
    match (error) {
        Malformed {} => {
            `expected four hex digits (${quote(literal, "\\uHHHH")}) or a braced code point (${quote(literal, "\\u{H...}")})`
        },
        Unterminated {} => "missing the closing brace",
        let e: InvalidChar => `${describe_char(e.ch)} is not a hex digit`,
        Empty {} => "expected at least one hex digit",
        TooLong {} => "at most six hex digits are allowed",
        MisplacedUnderscore {} => "underscores are only allowed between hex digits",
    }
}

// port: escape.rs::describe_char. A readable name for `c` inside a
// diagnostic message.
function describe_char(c: string) -> string throws never {
    match (c) {
        "\n" => "a newline",
        "\r" => "a carriage return",
        "\t" => "a tab",
        " " => "a space",
        _ if c.is_whitespace() || c.is_control() => `U+${upper_hex(c.code_point_at(0) ?? 0, 4)}`,
        _ => `'${c}'`,
    }
}

// port: escape.rs::hex_bytes. `\xHH` for each byte.
function hex_bytes(bytes: int[]) -> string throws never {
    bytes
        .map((b) -> {
            `\\x${upper_hex(b, 2)}`
        })
        .join("")
}

// port: escape.rs::Piece. One unit of decoded output.
type Piece = Char | Byte | Verbatim;

class Char {
    ch: string,
}

// A raw byte from a byte string `\xHH` escape.
class Byte {
    byte: int,
}

// Source text kept as-is because it did not decode.
class Verbatim {
    text: string,
}

// port: escape.rs::decode_str
function decode_str(
    input: string,
    literal: LiteralKind,
    issues: EscapeIssue[],
) -> string throws never {
    let result: string[] = [];
    scan(
        input,
        literal,
        (piece) -> {
            match (piece) {
                let c: Char => result.push(c.ch),
                let b: Byte => result.push(char_of(b.byte)),
                let v: Verbatim => result.push(v.text),
            };
        },
        issues,
    );
    result.join("")
}

// port: escape.rs::scan. Walk `input`, emitting its decoded pieces and
// recording every sequence that does not decode in `issues`.
function scan(
    input: string,
    literal: LiteralKind,
    emit: (Piece) -> void throws never,
    issues: EscapeIssue[],
) -> void throws never {
    let chars = input.chars();
    let i = 0;
    // The byte offset of `chars[i]`.
    let at = 0;
    while (i < chars.length()) {
        let len = match (decode_at(chars, i, literal, at, issues)) {
            let d: Decoded => {
                emit(d.piece);
                d.len
            },
            let u: Undecoded => {
                let text = chars.slice(i, i + u.len).join("");
                issues.push(new_issue(at, text, u.kind, literal));
                emit(Verbatim { text: text });
                u.len
            },
        };
        at += chars.slice(i, i + len).join("").byte_length();
        i += len;
    }
}

// One step of `scan` at `chars[i]` (byte offset `at`): an escape, or a plain
// character, recording a non-ASCII one in a byte string as an issue.
function decode_at(
    chars: string[],
    i: int,
    literal: LiteralKind,
    at: int,
    issues: EscapeIssue[],
) -> Decoded | Undecoded throws never {
    let c = chars[i];
    if (c == "\\") {
        return decode_escape(chars, i, literal);
    }
    // BEP-049 §AA (TS parity): normalize line endings in backtick literal text.
    // `\r\n` and a lone `\r` become `\n`.
    if (literal == LiteralKind.Backtick && c == "\r") {
        return Decoded {
            piece: Char { ch: "\n" },
            len: if (chars.at(i + 1) == "\n") {
                2
            } else {
                1
            },
        };
    }
    if (literal == LiteralKind.Bytes && !c.is_ascii()) {
        issues.push(new_issue(at, c, NonAsciiInByteString { ch: c }, literal));
    }
    Decoded { piece: Char { ch: c }, len: 1 }
}

// The `EscapeIssue` for `text` at byte offset `start`: part of `scan`.
function new_issue(
    start: int,
    text: string,
    kind: EscapeIssueKind,
    literal: LiteralKind,
) -> EscapeIssue throws never {
    EscapeIssue {
        start: start,
        len: text.byte_length(),
        text: text,
        kind: kind,
        literal: literal,
        suggest_raw_string: literal == LiteralKind.Quoted,
    }
}

// What `decode_escape` read: the decoded piece and the sequence's length in
// characters (Rust's `Ok((piece, len))`).
class Decoded {
    piece: Piece,
    len: int,
}

// A sequence that does not decode and its length in characters (Rust's
// `Err((kind, len))`).
class Undecoded {
    kind: EscapeIssueKind,
    len: int,
}

// port: escape.rs::decode_escape. Decode the escape at `chars[i]` (a `\`).
function decode_escape(
    chars: string[],
    i: int,
    literal: LiteralKind,
) -> Decoded | Undecoded throws never {
    // A trailing backslash can't occur in a well-formed literal: it would have
    // escaped the closing delimiter. Keep it as-is.
    let c = chars.at(i + 1)
        ?? return Decoded { piece: Char { ch: "\\" }, len: 1 };
    let simple = match (c) {
        "n" => "\n",
        "t" => "\t",
        "r" => "\r",
        "b" => "\u{0008}",
        "f" => "\u{000C}",
        "0" => "\u{0}",
        "\\" | "\"" | "'" | "`" | "$" | "/" => c,
        _ => null,
    };
    if (simple != null) {
        return Decoded { piece: Char { ch: simple }, len: 2 };
    }
    match (c) {
        "x" => decode_hex_escape(chars, i, literal),
        "u" => {
            let decoded = decode_unicode_escape(chars, i);
            if (literal != LiteralKind.Bytes) {
                return decoded;
            }
            match (decoded) {
                Decoded { piece: let ch: Char, len: let len } => {
                    Undecoded {
                        kind: UnicodeInByteString { utf8: ch.ch.to_utf8().to_array() },
                        len: len,
                    }
                },
                Decoded { len: let len } => {
                    Undecoded { kind: UnicodeInByteString { utf8: null }, len: len }
                },
                let u: Undecoded => {
                    Undecoded { kind: UnicodeInByteString { utf8: null }, len: u.len }
                },
            }
        },
        "U" => Undecoded { kind: LongUnicode {}, len: 2 + hex_run(chars, i + 2, 8) },
        "N" => Undecoded { kind: NamedUnicode {}, len: named_unicode_len(chars, i) },
        // A line break after the backslash would be a line continuation, which
        // BAML doesn't support. Point at the backslash alone so the diagnostic
        // stays on one line.
        "\n" | "\r" => Undecoded { kind: Unknown { ch: c }, len: 1 },
        _ => Undecoded { kind: Unknown { ch: c }, len: 2 },
    }
}

// The `'x'` arm of `decode_escape`: `\xHH` at `chars[i]`.
function decode_hex_escape(
    chars: string[],
    i: int,
    literal: LiteralKind,
) -> Decoded | Undecoded throws never {
    let digits = hex_run(chars, i + 2, 2);
    if (digits < 2) {
        return Undecoded { kind: InvalidHex {}, len: 2 + digits };
    }
    let byte = hex_value(chars.slice(i + 2, i + 4));
    if (literal == LiteralKind.Bytes) {
        return Decoded { piece: Byte { byte: byte }, len: 4 };
    }
    if (byte < 0x80) {
        return Decoded { piece: Char { ch: char_of(byte) }, len: 4 };
    }
    Undecoded { kind: NonAsciiHex { byte: byte }, len: 4 }
}

// The `'N'` arm of `decode_escape`: `\N{name}` runs through its `}`, or is
// the two characters `\N` when no braced name follows.
function named_unicode_len(chars: string[], i: int) -> int throws never {
    if (chars.at(i + 2) != "{") {
        return 2;
    }
    for (let j = i + 3; j < chars.length(); j += 1) {
        if (chars[j] == "}") {
            return j - i + 1;
        }
    }
    2
}

// port: escape.rs::decode_unicode_escape. Decode a `\u` escape at
// `chars[i]`, pairing a high surrogate with an immediately following
// low-surrogate `\u` escape.
function decode_unicode_escape(chars: string[], i: int) -> Decoded | Undecoded throws never {
    let parsed = unicode_escape_value(chars, i);
    let high = match (parsed) {
        let u: Undecoded => {
            return u;
        },
        let v: EscapeValue => v,
    };
    let value = high.value;
    let len = high.len;
    if (is_scalar(value)) {
        return Decoded { piece: Char { ch: char_of(value) }, len: len };
    }
    if (value > 0x10FFFF) {
        return Undecoded { kind: OutOfRange {}, len: len };
    }
    if (value >= 0xD800 && value < 0xDC00 && chars.at(i + len) == "\\" && chars.at(i + len + 1) == "u") {
        let low = unicode_escape_value(chars, i + len);
        if let l: EscapeValue = low {
            if (l.value >= 0xDC00 && l.value < 0xE000) {
                let cp = 0x10000 + (value - 0xD800) * 0x400 + (l.value - 0xDC00);
                return Decoded { piece: Char { ch: char_of(cp) }, len: len + l.len };
            }
        }
    }
    Undecoded { kind: LoneSurrogate { value: value }, len: len }
}

// The raw value of a `\u` escape and its length in characters.
class EscapeValue {
    value: int,
    len: int,
}

// port: escape.rs::unicode_escape_value. Parse the raw value of a `\uHHHH`
// or `\u{H...}` escape at `chars[i]`, without checking that it is a scalar
// value.
function unicode_escape_value(chars: string[], i: int) -> EscapeValue | Undecoded throws never {
    let after_u = i + 2;
    if (chars.at(after_u) != "{") {
        let digits = hex_run(chars, after_u, 4);
        if (digits < 4) {
            return invalid_unicode(Malformed {}, 2 + digits);
        }
        return EscapeValue { value: hex_value(chars.slice(after_u, after_u + 4)), len: 6 };
    }
    let braced = after_u + 1;
    let body_len = 0;
    while (is_unicode_body_char(chars.at(braced + body_len))) {
        body_len += 1;
    }
    let body = chars.slice(braced, braced + body_len);
    // `\u{` plus the body.
    let len = 3 + body_len;
    let next = chars.at(braced + body_len);
    if (next != "}") {
        if (next != null && (next.is_alphanumeric() || next == "+" || next == "-")) {
            return invalid_unicode(InvalidChar { ch: next }, len + 1);
        }
        return invalid_unicode(Unterminated {}, len);
    }
    // Include the closing brace.
    len += 1;
    if (!body) {
        return invalid_unicode(Empty {}, len);
    }
    if (body[0] == "_" || body[body.length() - 1] == "_" || body.join("").includes("__")) {
        return invalid_unicode(MisplacedUnderscore {}, len);
    }
    let digits = body.filter((c) -> {
        c != "_"
    });
    if (digits.length() > 6) {
        return invalid_unicode(TooLong {}, len);
    }
    EscapeValue { value: hex_value(digits), len: len }
}

// The `invalid` closure of `unicode_escape_value`.
function invalid_unicode(error: UnicodeEscapeError, len: int) -> Undecoded throws never {
    Undecoded { kind: InvalidUnicode { error: error }, len: len }
}

// A character `\u{...}` reads as its body: an ASCII hex digit or `_`.
function is_unicode_body_char(c: string?) -> bool throws never {
    c != null && (c.is_ascii_hex() || c == "_")
}

// port: escape.rs::hex_run. Length of the leading ASCII-hex-digit run of
// `chars` from `start`, capped at `cap`.
function hex_run(chars: string[], start: int, cap: int) -> int throws never {
    let n = 0;
    while (n < cap && (chars.at(start + n)?.is_ascii_hex() ?? false)) {
        n += 1;
    }
    n
}

// Stand-ins for Rust std: `from_str_radix(.., 16)`, `{:0NX}`,
// `char::from_u32` and `extend_from_slice(s.as_bytes())`.

// The UTF-8 bytes of `text`, appended to `bytes`.
function push_utf8(bytes: int[], text: string) -> void throws never {
    for (let b in text.to_utf8().to_array()) {
        bytes.push(b);
    }
}

const HEX_DIGITS: string = "0123456789ABCDEF";

// The value of validated ASCII hex digits.
function hex_value(digits: string[]) -> int throws never {
    digits.reduce(
        (value, d) -> {
            value * 16 + (HEX_DIGITS.index_of(d.to_upper_case()) ?? 0)
        },
        0,
    )
}

// `value` in upper-case hex, zero-padded to `width` digits.
function upper_hex(value: int, width: int) -> string throws never {
    let digits = "";
    let rest = value;
    while (rest > 0 || digits.length() < width) {
        digits = `${HEX_DIGITS.at(rest % 16) ?? ""}${digits}`;
        rest = rest / 16;
    }
    digits
}

// Whether `value` is a Unicode scalar value (`char::from_u32` succeeds).
function is_scalar(value: int) -> bool throws never {
    value >= 0 && value <= 0x10FFFF && !(value >= 0xD800 && value < 0xE000)
}

// The character for scalar value `cp`.
function char_of(cp: int) -> string throws never {
    string.from_code_points([cp]) catch (e) {
        baml.errors.InvalidArgument => baml.sys.panic("a scalar value is a character"),
    }
}
