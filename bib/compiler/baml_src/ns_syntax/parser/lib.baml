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

// port: baml_compiler_diagnostics/src/to_diagnostic.rs::typed_parse_error_diagnostic.
// The diagnostic for a parse error in `file`, in the shape
// `reflect.Package.compile` reports. The ids predate the typed parser: an
// unexpected token is E0010, an escape that does not decode E0109, a
// directive problem E0105.
function parse_error_diagnostic(error: ParseError, file: string) -> reflect.Diagnostic throws never {
  let range = parse_error_range(error);
  let (let code, let headline, let label) = match (error) {
    let e: UnexpectedToken => ("E0010", "unexpected token", `expected \`${e.expected}\`, found \`${e.found}\``),
    let e: UnexpectedEof => ("E0009", "unexpected end of file", `expected \`${e.expected}\`, found end of file`),
    let e: InvalidSyntax => ("E0010", "invalid syntax", e.message),
    let e: AmbiguousUnion => ("E0175", AMBIGUOUS_UNION_MESSAGE, ambiguous_union_label(e.groupings)),
    let e: RemovedFeature => ("E0098", "removed language feature", e.message),
    let e: InvalidStringEscape => ("E0109", root.base.escape_issue_message(e.issue), root.base.escape_issue_label(e.issue)),
    let e: InvalidDirective => ("E0105", e.message, "invalid directive"),
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
