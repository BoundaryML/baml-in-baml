// port: baml_parser/src/error.rs @ d9be6853b
//
// Diagnostics the parser produces. Ranges are byte offsets into the parsed
// text; the layer that knows which file this was adds the file.

// port: text_size::TextRange. Bytes [start, end).
class TextRange {
    start: int,
    end: int,

    function empty(at: int) -> TextRange throws never {
        TextRange { start: at, end: at }
    }

    // port: text_size::TextRange::cover. The smallest range containing both.
    function cover(self, other: TextRange) -> TextRange throws never {
        TextRange {
            start: if (self.start < other.start) {
                self.start
            } else {
                other.start
            },
            end: if (self.end > other.end) {
                self.end
            } else {
                other.end
            },
        }
    }
}

// A required token or construct was not found where the grammar needs it.
class UnexpectedToken {
    expected: string,
    found: string,
    range: TextRange,
}

// The input ended where the grammar needs more.
class UnexpectedEof {
    expected: string,
    range: TextRange,
}

// A construct that parses but is not allowed, with a message saying why.
class InvalidSyntax {
    message: string,
    range: TextRange,
}

// A `|` that can belong to a function's return/throws union or join two
// functions (E0175). `groupings` are two explicitly parenthesized spellings
// that group the pipe differently; empty when none could be derived.
class AmbiguousUnion {
    range: TextRange,
    groupings: string[],
}

// Use of a removed language feature (E0098).
class RemovedFeature {
    message: string,
    range: TextRange,
}

// An escape sequence in a string literal that does not decode (E0109).
// `range` covers the sequence; the literal is read with it verbatim.
class InvalidStringEscape {
    issue: root.base.EscapeIssue,
    range: TextRange,
}

// A `//baml:` directive or `/// baml:$trace` hook that names no directive,
// has no hook path, repeats a hook, or precedes a declaration that takes
// none (E0105).
class InvalidDirective {
    message: string,
    range: TextRange,
}

type ParseError = UnexpectedToken
    | UnexpectedEof
    | InvalidSyntax
    | AmbiguousUnion
    | RemovedFeature
    | InvalidStringEscape
    | InvalidDirective;

// port: ParseError::AMBIGUOUS_UNION_MESSAGE
const AMBIGUOUS_UNION_MESSAGE: string = "ambiguous union";

// port: impl Display for ParseError. The message alone; the range is
// `parse_error_range`.
function parse_error_message(error: ParseError) -> string throws never {
    match (error) {
        let e: UnexpectedToken => `expected ${e.expected}, found ${e.found}`,
        let e: UnexpectedEof => `expected ${e.expected}, found EOF`,
        let e: InvalidSyntax => e.message,
        let e: RemovedFeature => e.message,
        let e: InvalidDirective => e.message,
        let e: InvalidStringEscape => root.base.escape_issue_message(e.issue),
        let e: AmbiguousUnion => [AMBIGUOUS_UNION_MESSAGE].concat(e.groupings).join("; "),
    }
}

// port: ParseError::ambiguous_union_label. One line, so concise renderers
// stay readable.
function ambiguous_union_label(groupings: string[]) -> string throws never {
    let explicit = "use parentheses to make the intended grouping explicit";
    if (!groupings) {
        return explicit;
    }
    `${explicit}: ${groupings.map((grouping) -> { `\`${grouping}\`` }).join(" or ")}`
}

// port: ParseError::range
function parse_error_range(error: ParseError) -> TextRange throws never {
    match (error) {
        let e: UnexpectedToken => e.range,
        let e: UnexpectedEof => e.range,
        let e: InvalidSyntax => e.range,
        let e: AmbiguousUnion => e.range,
        let e: RemovedFeature => e.range,
        let e: InvalidStringEscape => e.range,
        let e: InvalidDirective => e.range,
    }
}
