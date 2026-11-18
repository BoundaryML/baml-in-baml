// The BAML compiler, written in BAML. Entry point mirrors
// reflect.Package.compile: source files in, diagnostics out.
// So far: parse diagnostics only.

// Where the stdlib sources are read from (`ns_db/project.baml`), relative to
// this project.
const STDLIB_DIR: string = "../../baml_language/crates/baml_builtins2/baml_std";

function check(files: map<string, string>) -> reflect.Diagnostic[] throws never {
  check_with(stdlib_db(), files)
}

// A Db holding only the stdlib, for `check_with`.
function stdlib_db() -> root.hir.Db throws never {
  root.db.project_db(STDLIB_DIR, {}) catch_all (e) {
    _ => baml.sys.panic(`cannot read the stdlib under ${STDLIB_DIR}`),
  }
}

// `check`, on a Db that already holds the stdlib: `files` become a new
// workspace root. Every cache is keyed by file or root id, so one Db can
// check many independent workspaces and compiles the stdlib once.
function check_with(db: root.hir.Db, files: map<string, string>) -> reflect.Diagnostic[] throws never {
  let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
  for (let path in files.keys()) {
    root.db.add_file(db, workspace, path, files[path]);
  }
  let file_ids = db.source_root(workspace).files;
  let diagnostics = file_ids.flat_map((file) -> { check_file(db, file) })
    .concat(package_level_diagnostics(db, workspace));
  // port: collect_compiler2_diagnostics's final sort: by file, then position.
  let rank: map<string, int> = {};
  for (let i = 0; i < file_ids.length(); i += 1) {
    rank[db.file(file_ids[i]).path] = i;
  }
  sort_diagnostics(diagnostics, rank)
}

// port: baml_db/src/check.rs::package_level_diagnostics @ d9be6853b. Cross-file
// name conflicts and namespace shadows of a package (phase "validation"),
// computed outside `check_file`. Rust runs it over every package with files;
// the stdlib packages have none, so only the workspace is checked here.
function package_level_diagnostics(db: root.hir.Db, package: int) -> reflect.Diagnostic[] throws never {
  let items = root.hir.package_items(db, package);
  items.conflicts().map((conflict) -> { conflict.to_diagnostic(db).finish(db) })
    .concat(items.shadows().map((shadow) -> { shadow.to_diagnostic(db).finish(db) }))
}

// port: baml_db/src/check.rs::check_file @ d9be6853b. One file's
// diagnostics in the order its steps produce them (parse, CST to AST
// lowering, HIR, then the Type-phase steps in check_file_types.baml),
// deduplicated.
function check_file(db: root.hir.Db, file: int) -> reflect.Diagnostic[] throws never {
  let source = db.file(file);
  let raw_parse_errors = root.syntax.parse(source.text).errors;
  let parse_errors = raw_parse_errors.map((error) -> {
    root.syntax.parse_error_diagnostic(error, source.path)
  });
  let index = root.hir.file_semantic_index(db, file);
  let extra = index.extra;
  let hir = if (extra) {
    extra.lowering_diagnostics.map((d) -> { root.ast.to_diagnostic(d, source.path) })
      .concat(extra.diagnostics.map((d) -> { root.hir.to_diagnostic(d, source.path) }))
  } else {
    []
  };
  let types = check_file_types(db, file, raw_parse_errors).map((d) -> { owned_diagnostic(db, d) });
  dedup_adjacent(parse_errors.concat(hir).concat(types))
}

// port: baml_db/src/check.rs::sort_diagnostics. By file (its position in
// `rank`), then primary span start, then headline, then span end; stable, and
// diagnostics without a span last.
function sort_diagnostics(diagnostics: reflect.Diagnostic[], rank: map<string, int>) -> reflect.Diagnostic[] throws never {
  diagnostics.sort_by_key((d) -> {
    let span = d.span;
    DiagnosticOrder {
      file: if (span) { rank.get(span.file ?? "") ?? 0 } else { rank.length() },
      start: span?.start ?? 0,
      headline: d.headline,
      end: span?.end ?? 0,
    }
  })
}

// The order diagnostics are reported in.
class DiagnosticOrder {
  file: int,
  start: int,
  headline: string,
  end: int,

  implements baml.ops.Equals {}

  implements baml.ops.Compare {
    function cmp(self, other: Self) -> baml.ops.Ordering throws never {
      let by_file = self.file.cmp(other.file);
      if (by_file != baml.ops.Ordering.Equal) {
        return by_file;
      }
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
