// port: baml_parser/src/lib.rs @ d9be6853b
//
// The parser: a file's text to its typed tree. The tree is complete for any
// input: a required position the text does not fill is a `Missing`, tokens
// that fit no node are a `Bogus`, and both only ever appear alongside an
// error in `Parse.errors`.

// port: baml_syntax nodes::FileTree. A parsed file's text, its tokens and
// its root node; everything a later stage reads a tree through.
class FileTree {
    text: string,
    utf8: uint8array,
    tokens: Tokens,
    file: SourceFile,

    // The text of one token.
    function token_text(self, token: int) -> string throws never {
        self.tokens.text(self.utf8, token)
    }

    // port: Tokens::range
    function token_range(self, token: int) -> TextRange throws never {
        TextRange { start: self.tokens.starts[token], end: self.tokens.starts[token + 1] }
    }

    // port: Tokens::text_range. The text a run of tokens covers; an empty run is
    // the empty range at its start.
    function text_range(self, span: TokenRange) -> TextRange throws never {
        TextRange { start: self.tokens.starts[span.start], end: self.tokens.starts[span.end] }
    }

    // The source text `range` covers.
    function slice(self, range: TextRange) -> string throws never {
        string.from_utf8(self.utf8.slice(range.start, range.end)) catch (e) {
            baml.errors.InvalidArgument => {
                baml.sys.panic("ranges split the source on character boundaries")
            },
        }
    }
}

// port: lib.rs::Parse. A parsed file.
class Parse {
    tree: FileTree,
    errors: ParseError[],
}

// port: lib.rs::parse. Parse `text` completely.
function parse(text: string) -> Parse throws never {
    let input = Input.new(text);
    let p = Parser.new(Cursor.new(input), Sink.new());
    let file = source_file(p);
    Parse {
        tree: FileTree { text: text, utf8: input.utf8, tokens: input.tokens, file: file },
        errors: p.out.errors,
    }
}

// port: baml_compiler_diagnostics/src/to_diagnostic.rs::typed_parse_error_diagnostic.
// The diagnostic for a parse error in `file`, in the shape
// `reflect.Package.compile` reports. The ids predate the typed parser: an
// unexpected token is E0010, an escape that does not decode E0109, a
// directive problem E0105.
function parse_error_diagnostic(
    error: ParseError,
    file: string,
) -> reflect.Diagnostic throws never {
    let range = parse_error_range(error);
    let (let code, let headline, let label) = match (error) {
        let e: UnexpectedToken => {
            (
                root.diagnostics.UNEXPECTED_TOKEN,
                "unexpected token",
                `expected \`${e.expected}\`, found \`${e.found}\``,
            )
        },
        let e: UnexpectedEof => {
            (
                root.diagnostics.UNEXPECTED_EOF,
                "unexpected end of file",
                `expected \`${e.expected}\`, found end of file`,
            )
        },
        let e: InvalidSyntax => (root.diagnostics.INVALID_SYNTAX, "invalid syntax", e.message),
        let e: AmbiguousUnion => {
            (
                root.diagnostics.AMBIGUOUS_UNION,
                AMBIGUOUS_UNION_MESSAGE,
                ambiguous_union_label(e.groupings),
            )
        },
        let e: RemovedFeature => {
            (root.diagnostics.REMOVED_FEATURE, "removed language feature", e.message)
        },
        let e: InvalidStringEscape => {
            (
                root.diagnostics.INVALID_STRING_ESCAPE,
                root.base.escape_issue_message(e.issue),
                root.base.escape_issue_label(e.issue),
            )
        },
        let e: InvalidDirective => {
            (root.diagnostics.MALFORMED_ATTRIBUTE, e.message, "invalid directive")
        },
    };
    reflect.Diagnostic {
        code: code,
        span: reflect.Span { file: file, start: range.start, end: range.end },
        message: `${headline}: ${label}`,
        severity: "error",
        phase: "parse",
        headline: headline,
        primary_label: label,
        message_highlights: [],
        annotations: [],
        related_info: [],
    }
}
