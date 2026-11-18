// port: baml_base/src/num_lit.rs @ d9be6853b

// port: baml_type/src/lib.rs::MAX_BIGINT_BITS. The bigint
// workspace cap, in bits (2^28).
const MAX_BIGINT_BITS: int = 268435456;

// port: num_lit.rs::IntLitError. Validation failure for an integer or bigint
// literal.
type IntLitError = IntLitErrorUppercaseBasePrefix
    | IntLitErrorNoDigits
    | IntLitErrorInvalidDigits
    | IntLitErrorTooLarge;

// Base prefix written uppercase (`0X1F`); `fixed` is the lowercase spelling.
class IntLitErrorUppercaseBasePrefix {
    fixed: string,
}

// Prefix with no digits after it (`0x`, `0b__`).
class IntLitErrorNoDigits {
}

// Digits invalid for the base (`0b12`): the byte offset within the token and
// the character of each offending digit.
class IntLitErrorInvalidDigits {
    base: int,
    positions: (int, string)[],
}

// Magnitude exceeds the supported integer or bigint limit.
class IntLitErrorTooLarge {
}

// port: num_lit.rs::IntLitError::message. Matching rustc's wording where it
// has an equivalent.
function int_lit_error_message(error: IntLitError) -> string throws never {
    match (error) {
        let e: IntLitErrorUppercaseBasePrefix => {
            `invalid base prefix for number literal; base prefixes are lowercase: \`${e.fixed}\``
        },
        IntLitErrorNoDigits => "no valid digits found for number",
        let e: IntLitErrorInvalidDigits => `invalid digit for a base ${e.base} literal`,
        IntLitErrorTooLarge => "integer literal is too large",
    }
}

// port: num_lit.rs::base_and_digits_start. The base, and the byte offset
// where the digits start.
function base_and_digits_start(text: string) -> (int, int) throws never {
    if (!text.starts_with("0")) {
        return (10, 0);
    }
    match (text.at(1)) {
        "x" | "X" => (16, 2),
        "o" | "O" => (8, 2),
        "b" | "B" => (2, 2),
        _ => (10, 0),
    }
}

// port: num_lit.rs::validate. `(base, digits)`, the digits being the text
// after any base prefix, underscores kept.
function validate(text: string) -> (int, string) | IntLitError throws never {
    let (let base, let start) = base_and_digits_start(text);
    let prefix_char = text.at(1) ?? "";
    if (start == 2 && prefix_char.is_ascii_uppercase()) {
        return IntLitErrorUppercaseBasePrefix {
            fixed: `${text.slice(0, 1)}${prefix_char.to_lower_case()}${text.slice(2, text.length())}`,
        };
    }
    // The prefix is ASCII, so its byte and character offsets agree.
    let digits = text.slice(start, text.length());
    let chars = digits.chars();
    if (
        chars.every((c) -> {
            c == "_"
        })
    ) {
        return IntLitErrorNoDigits {};
    }
    let positions: (int, string)[] = [];
    let offset = start;
    for (let c in chars) {
        if (c != "_" && digit_value(c, base) == null) {
            positions.push((offset, c));
        }
        offset += c.byte_length();
    }
    if (positions.length() > 0) {
        return IntLitErrorInvalidDigits { base: base, positions: positions };
    }
    (base, digits)
}

// Rust's `char::to_digit(base)`.
function digit_value(c: string, base: int) -> int? throws never {
    if (!c.is_ascii()) {
        return null;
    }
    let value = DIGITS.index_of(c.to_lower_case());
    if (value != null && value < base) {
        value
    } else {
        null
    }
}

const DIGITS: string = "0123456789abcdefghijklmnopqrstuvwxyz";

// The value of validated digits (underscores skipped) in `base`.
function digits_value(digits: string, base: int) -> bigint throws never {
    digits.chars().reduce(
        (acc, c) -> {
            match (digit_value(c, base)) {
                let d: int => acc * base + d,
                null => acc,
            }
        },
        0n,
    )
}

// i64::MAX: the bound Rust's `parse_int_literal` reads into.
const I64_MAX: bigint = 9223372036854775807n;

// port: num_lit.rs::parse_int_literal. An `INTEGER_LITERAL` token's text as
// its non-negative value; signs are the caller's.
function parse_int_literal(text: string) -> int | IntLitError throws never {
    let validated = validate(text);
    if (validated is IntLitError) {
        return validated;
    }
    let (let base, let digits) = validated;
    let value = digits_value(digits, base);
    if (value > I64_MAX) {
        return IntLitErrorTooLarge {};
    }
    // deviation: Rust bounds the value by i64::MAX and leaves the VM's 63-bit
    // `int` range to type inference; a BAML `int` cannot hold the values in
    // between, so they are reported TooLarge here.
    value.to_int() catch (e) {
        baml.errors.InvalidArgument => IntLitErrorTooLarge {},
    }
}

// port: num_lit.rs::parse_bigint_literal_with_max_bits (with the bounded
// half of parse_bigint_literal_bounded folded in). A `BIGINT_LITERAL` token's text,
// `n` already stripped, with an optional leading `-`, bounded to `max_bits`.
// A conservative significant-digit count rejects obviously oversized values
// before parsing; values near the bound are checked exactly after.
function parse_bigint_literal_with_max_bits(
    text: string,
    max_bits: int,
) -> bigint | IntLitError throws never {
    let negated = text.starts_with("-");
    let magnitude = if (negated) {
        text.slice(1, text.length())
    } else {
        text
    };
    let validated = validate(magnitude);
    if (validated is IntLitError) {
        return validated;
    }
    let (let base, let digits) = validated;
    let cleaned = digits.chars().filter((c) -> {
        c != "_"
    });
    let leading_zeros = cleaned.find_index((c) -> {
        c != "0"
    })
        ?? cleaned.length();
    let significant_digits = cleaned.length() - leading_zeros;
    let max_significant_digits = match (base) {
        2 => max_bits,
        8 | 10 => (max_bits + 2) / 3,
        16 => (max_bits + 3) / 4,
        _ => baml.sys.panic(`validated integer literal has unsupported base ${base}`),
    };
    if (significant_digits > max_significant_digits) {
        return IntLitErrorTooLarge {};
    }
    let magnitude_value = digits_value(digits, base);
    let value = if (negated) {
        -magnitude_value
    } else {
        magnitude_value
    };
    if (bigint_bits(value) > max_bits) {
        return IntLitErrorTooLarge {};
    }
    value
}

// num_bigint's `BigInt::bits`: the bit length of the magnitude, 0 for zero.
function bigint_bits(value: bigint) -> int throws never {
    if (value == 0n) {
        return 0;
    }
    let log = value.abs().ilog(2n) catch (e) {
        baml.errors.InvalidArgument => baml.sys.panic("a nonzero magnitude has a base-2 logarithm"),
    };
    let bits = log + 1n;
    bits.to_int() catch (e) {
        baml.errors.InvalidArgument => baml.sys.panic("a bit length fits in an int"),
    }
}

// port: baml_base/src/num_lit.rs::normalize_float_literal. A float
// literal's text without its `_` digit separators.
function normalize_float_literal(text: string) -> string throws never {
    text.replace_all("_", "")
}
