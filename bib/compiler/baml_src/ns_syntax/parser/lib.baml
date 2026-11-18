// port: baml_parser/src/lib.rs @ d9be6853b
//
// The parser: a file's text to its typed tree. The tree is complete for any
// input: a required position the text does not fill is a `Missing`, tokens
// that fit no node are a `Bogus`, and both only ever appear alongside an
// error in `Parse.errors`.

// port: lib.rs::Parse. A parsed file.
class Parse {
  tree: SourceFile,
  tokens: Tokens,
  errors: ParseError[],
}

// port: lib.rs::parse. Parse `text` completely.
function parse(text: string) -> Parse throws never {
  let input = Input.new(text);
  let p = Parser.new(Cursor.new(input), Sink.new());
  let tree = source_file(p);
  Parse { tree: tree, tokens: input.tokens, errors: p.out.errors }
}

// The text of a parse diagnostic. (A tuple, `let (code, headline, label) =
// match ...`, once the nightly toolchain has tuples.)
class ParseDiagnosticText {
  code: string,
  headline: string,
  label: string,
}

// port: baml_compiler_diagnostics/src/to_diagnostic.rs::typed_parse_error_diagnostic.
// The diagnostic for a parse error in `file`, in the shape
// `reflect.Package.compile` reports. The ids predate the typed parser: an
// unexpected token is E0010, an escape that does not decode E0109, a
// directive problem E0105.
function parse_error_diagnostic(error: ParseError, file: string) -> reflect.Diagnostic throws never {
  let range = parse_error_range(error);
  let text = match (error) {
    let e: UnexpectedToken => ParseDiagnosticText {
      code: "E0010",
      headline: "unexpected token",
      label: `expected \`${e.expected}\`, found \`${e.found}\``,
    },
    let e: UnexpectedEof => ParseDiagnosticText {
      code: "E0009",
      headline: "unexpected end of file",
      label: `expected \`${e.expected}\`, found end of file`,
    },
    let e: InvalidSyntax => ParseDiagnosticText { code: "E0010", headline: "invalid syntax", label: e.message },
    let e: AmbiguousUnion => ParseDiagnosticText {
      code: "E0175",
      headline: AMBIGUOUS_UNION_MESSAGE,
      label: ambiguous_union_label(e.groupings),
    },
    let e: RemovedFeature => ParseDiagnosticText { code: "E0098", headline: "removed language feature", label: e.message },
    let e: InvalidStringEscape => ParseDiagnosticText {
      code: "E0109",
      headline: root.base.escape_issue_message(e.issue),
      label: root.base.escape_issue_label(e.issue),
    },
    let e: InvalidDirective => ParseDiagnosticText { code: "E0105", headline: e.message, label: "invalid directive" },
  };
  reflect.Diagnostic {
    code: text.code,
    span: reflect.Span { file: file, start: range.start, end: range.end },
    message: `${text.headline}: ${text.label}`,
    severity: "error",
    phase: "parse",
    headline: text.headline,
    primary_label: text.label,
    message_highlights: [],
    annotations: [],
    related_info: [],
  }
}
