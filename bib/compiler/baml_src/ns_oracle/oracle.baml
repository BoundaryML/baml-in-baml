// The Rust compiler, reached through reflection. Used only by tests to say
// what our compiler should report.

function rust_diagnostics(files: map<string, string>) -> reflect.Diagnostic[] throws never {
    let artifact = reflect.Package._compile(files, {}) catch (error) {
        reflect.errors.CompilationError => {
            return error.diagnostics;
        },
    };
    // A successful compile still has its warnings; they live on the finished
    // package. (If the package's top-level initialization throws, its warnings
    // are lost; no corpus file does that.)
    let package = reflect.Package._finish(artifact, {}) catch_all (e) {
        _ => {
            return [];
        },
    };
    package.diagnostics()
}

// What two compilers must agree on for one diagnostic: code, place, headline
// and primary label. Highlights and secondary annotations are not compared yet.
function diagnostic_key(d: reflect.Diagnostic) -> string throws never {
    let span = d.span;
    let at = if (span) {
        `${span.file ?? ""}:${span.start}-${span.end}`
    } else {
        "-"
    };
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
        rust: rust_diagnostics(files)
            .filter((d) -> {
                d.phase == "parse"
            })
            .map(diagnostic_key),
        ours: root.check(files)
            .filter((d) -> {
                d.phase == "parse"
            })
            .map(diagnostic_key),
    }
}

// The codes CST to AST lowering reports (`LoweringDiagnostic::to_diagnostic`).
// HIR's own phase-"hir" diagnostics use other codes, so these pick out the
// lowering's share of the Rust compiler's output.
const LOWERING_CODES: string[] = ["E0001", "E0010", "E0017", "E0098", "E0108", "E0127", "E0147", "E0152", "E0171"];

// Parse, HIR-phase (lowering and HIR proper) and validation diagnostics,
// ours vs the Rust compiler's.
function compare_hir(files: map<string, string>, db: root.hir.Db? = null) -> ParseComparison throws never {
  let in_scope = (d: reflect.Diagnostic) -> bool { d.phase == "parse" || d.phase == "hir" || d.phase == "validation" };
  let ours = if (db) { root.check_with(db, files) } else { root.check(files) };
  ParseComparison {
    rust: rust_diagnostics(files).filter(in_scope).map(diagnostic_key),
    ours: ours.filter(in_scope).map(diagnostic_key),
  }
}

// Every diagnostic, Type phase included: the TIR gate.
function compare_types(files: map<string, string>, db: root.hir.Db? = null) -> ParseComparison throws never {
    let ours = if (db) { root.check_with(db, files) } else { root.check(files) };
    ParseComparison {
        rust: rust_diagnostics(files).map(diagnostic_key),
        ours: ours.map(diagnostic_key),
    }
}

// Parse and lowering diagnostics, ours vs the Rust compiler's.
function compare_lowering(files: map<string, string>) -> ParseComparison throws never {
    let in_scope = (d: reflect.Diagnostic) -> bool {
        d.phase == "parse" || (d.phase == "hir" && LOWERING_CODES.includes(d.code))
    };
    ParseComparison {
        rust: rust_diagnostics(files).filter(in_scope).map(diagnostic_key),
        ours: root.check(files).filter(in_scope).map(diagnostic_key),
    }
}

test "oracle reports a type error" {
    let diags = rust_diagnostics({ "a.baml": "function f() -> int { \"no\" }" });
    assert.equal(diags.length() > 0, true);
    assert.equal(diags[0].severity, "error")
}

test "oracle accepts clean code" {
    assert.equal(rust_diagnostics({ "a.baml": "function f() -> int { 1 }" }).length(), 0)
}
