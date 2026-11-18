// The BAML compiler, written in BAML. Entry point mirrors
// reflect.Package.compile: source files in, diagnostics out.
// So far: parse diagnostics only.

function check(files: map<string, string>) -> reflect.Diagnostic[] throws never {
  files.keys().flat_map((file) -> { check_file(file, files[file]) })
}

// port: baml_db/src/check.rs::check_file @ d9be6853b (the parse step and the
// final dedup). One file's diagnostics, in the order its checks produce them.
function check_file(file: string, text: string) -> reflect.Diagnostic[] throws never {
  let diagnostics = root.syntax.parse(text).errors.map((error) -> { root.syntax.parse_error_diagnostic(error, file) });
  sort_diagnostics(dedup_adjacent(diagnostics))
}

// port: baml_db/src/check.rs::sort_diagnostics. By primary span start, then
// headline, then span end; stable, so equal keys keep their order.
function sort_diagnostics(diagnostics: reflect.Diagnostic[]) -> reflect.Diagnostic[] throws never {
  diagnostics.sort_by_key((d) -> {
    let span = d.span;
    DiagnosticOrder { start: span?.start ?? 0, headline: d.headline, end: span?.end ?? 0 }
  })
}

// The order diagnostics are reported in within a file.
class DiagnosticOrder {
  start: int,
  headline: string,
  end: int,

  implements baml.ops.Equals {}

  implements baml.ops.Compare {
    function cmp(self, other: Self) -> baml.ops.Ordering throws never {
      let by_start = self.start.cmp(other.start);
      if (by_start != baml.ops.Ordering.Equal) {
        return by_start;
      }
      let by_headline = self.headline.cmp(other.headline);
      if (by_headline != baml.ops.Ordering.Equal) {
        return by_headline;
      }
      self.end.cmp(other.end)
    }
  }
}

// port: the `dedup_by` at the end of check_file. Multiple steps can produce
// the same diagnostic; a diagnostic is dropped when the one before it has the
// same code, headline and primary span (the label is not compared, so two
// "unexpected token" errors at one token keep only the first).
function dedup_adjacent(diagnostics: reflect.Diagnostic[]) -> reflect.Diagnostic[] throws never {
  let kept: reflect.Diagnostic[] = [];
  for (let d in diagnostics) {
    let last = kept.at(kept.length() - 1);
    if (last == null || !same_report(last, d)) {
      kept.push(d);
    }
  }
  kept
}

function same_report(a: reflect.Diagnostic, b: reflect.Diagnostic) -> bool throws never {
  a.code == b.code && a.headline == b.headline && a.span == b.span
}
