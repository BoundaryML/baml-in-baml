// The Rust compiler, reached through reflection. Used only by tests to say
// what our compiler should report.

function rust_diagnostics(files: map<string, string>) -> reflect.Diagnostic[] throws never {
  let package = reflect.Package._compile(files, {}) catch (error) {
    reflect.errors.CompilationError => {
      return error.diagnostics;
    },
  };
  []
}

// What two compilers must agree on for one diagnostic: code, place, headline
// and primary label. Highlights and secondary annotations are not compared yet.
function diagnostic_key(d: reflect.Diagnostic) -> string throws never {
  let span = d.span;
  let at = if (span) { `${span.file ?? ""}:${span.start}-${span.end}` } else { "-" };
  `${d.code} ${at} ${d.headline} | ${d.primary_label ?? ""}`
}

// The parse diagnostics of `files`, from the Rust compiler and from ours, as
// comparable keys.
class ParseComparison {
  rust: string[],
  ours: string[],
}

function compare_parse(files: map<string, string>) -> ParseComparison throws never {
  ParseComparison {
    rust: rust_diagnostics(files).filter((d) -> { d.phase == "parse" }).map(diagnostic_key),
    ours: root.check(files).map(diagnostic_key),
  }
}

test "oracle reports a type error" {
  let diags = rust_diagnostics({"a.baml": "function f() -> int { \"no\" }"});
  assert.equal(diags.length() > 0, true);
  assert.equal(diags[0].severity, "error")
}

test "oracle accepts clean code" {
  assert.equal(rust_diagnostics({"a.baml": "function f() -> int { 1 }"}).length(), 0)
}
