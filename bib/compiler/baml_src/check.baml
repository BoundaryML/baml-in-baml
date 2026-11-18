// The BAML compiler, written in BAML. Entry point mirrors
// reflect.Package.compile: source files in, diagnostics out.
// So far: parse diagnostics only.

function check(files: map<string, string>) -> reflect.Diagnostic[] throws never {
    files.keys().flat_map((file) -> {
        check_file(file, files[file])
    })
}

// port: baml_db/src/check.rs::check_file @ d9be6853b. One file's
// diagnostics in the order its steps produce them (parse, then CST to AST
// lowering), deduplicated. `file` is the path relative to the package root.
function check_file(file: string, text: string) -> reflect.Diagnostic[] throws never {
    let parsed = root.syntax.parse(text);
    let (let _items, let lowering, let _env_refs) = root.ast.lower_file(parsed.tree, file, test_owner(file));
    let diagnostics = parsed.errors
        .map((error) -> {
            root.syntax.parse_error_diagnostic(error, file)
        })
        .concat(
            lowering.map((d) -> {
                root.ast.to_diagnostic(d, file)
            }),
        );
    sort_diagnostics(dedup_adjacent(diagnostics))
}

// port: baml_compiler2_hir/src/lib.rs::file_ast's test owner: `root`, or
// `root.<ns>...` from the file's namespace.
function test_owner(file: string) -> string throws never {
    ["root"].concat(namespace_path(file)).join(".")
}

// port: baml_compiler2_hir/src/file_package.rs::file_package's namespace path:
// every `ns_<identifier>` directory on the way to the file, in order.
function namespace_path(file: string) -> string[] throws never {
    let dirs = file.split("/");
    dirs.pop();
    dirs.filter_map((dir) -> {
        ns_name(dir)
    })
}

// port: file_package.rs::extract_ns_name. The namespace an `ns_` directory
// names, when the rest is an identifier.
function ns_name(dir: string) -> string? throws never {
    if (!dir.starts_with("ns_")) {
        return null;
    }
    let name = dir.slice(3, dir.length());
    let first = name.at(0)
        ?? return null;
    let valid = (first.is_ascii_alphabetic() || first == "_")
        && name.chars().every((c) -> {
            c.is_ascii_alphanumeric() || c == "_"
        });
    if (valid) {
        name
    } else {
        null
    }
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
