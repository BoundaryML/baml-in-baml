// port: baml_tests/src/type_spec/pattern_corpus.rs @ d9be6853b
//
// The legacy pattern/exhaustiveness corpora through hir_ty: per function,
// how many of its `match` expressions hir_ty records as non-exhaustive.
// One snapshot per corpus, compared byte for byte with upstream's insta
// snapshot (header stripped, `snapshot_body`):
//
//   baml run oracle.type_spec.pattern_corpus_summary
//
// The module doc describes a two-engine sweep (hir_ty's verdict against
// TIR's E0062), but at this commit the snapshots have one column: each line
// is `<function name>: hir_ty=<n>`, where `n` is the size of
// `infer_body(db, owner).non_exhaustive_matches` for that function's body.
// There is no TIR column, so nothing refers to the retired engine and the
// port is direct.
//
// Restructured:
// - `corpus_verdicts` takes the Db: one stdlib Db is shared by the four
//   corpora, each read into its own workspace root (as `corpus.baml`),
//   instead of a fresh database per corpus.
// - Each `#[test]` is a test block over `corpus_snapshot`, which also feeds
//   `pattern_corpus_summary`; `insta::assert_snapshot!` is the equality
//   assertion, and the summary prints a line diff on a mismatch.
// - Upstream paths are relative to `baml_tests` (`BAML_TESTS_DIR`, Rust's
//   `CARGO_MANIFEST_DIR`); the corpora are read in place.

// port: baml_tests/src/type_spec/pattern_corpus.rs::corpus_verdicts @ d9be6853b
function corpus_verdicts(
    db: root.hir.Db,
    relative_path: string,
) -> string throws baml.errors.Io | baml.errors.ParseError {
    let source = baml.fs.read(`${BAML_TESTS_DIR}/${relative_path}`);
    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    let file = root.db.add_file(db, workspace, "corpus.baml", source);

    let out: string[] = [];
    for (let owner in root.hir.file_body_owners(db, file)) {
        let function_ = match (owner) {
            let f: root.hir.BodyOwnerIdFunction => f.value,
            _ => {
                continue;
            },
        };
        let data = root.hir.function_data(db, function_);
        if (root.hir.body_scope(db, owner) == null) {
            continue;
        }
        let result = root.hir_ty.infer_body(db, owner);
        let hir_count = result.non_exhaustive_matches.length();
        out.push(`${data.name}: hir_ty=${hir_count}\n`);
    }
    out.join("")
}

// The four corpus tests: (insta snapshot name, corpus path under
// `baml_tests`).
const PATTERN_CORPORA: (string, string)[] = [
    (
        "corpus__match_exhaustiveness",
        "projects/diagnostic_errors/match_exhaustiveness/match_exhaustiveness.baml",
    ),
    (
        "corpus__generic_rigid_coverage",
        "projects/diagnostic_errors/generic_rigid_coverage/main.baml",
    ),
    ("corpus__patterns_new", "baml_src/ns_fixtures/ns_patterns_new/patterns_new.baml"),
    (
        "corpus__generic_match_typevar_arm",
        "baml_src/ns_fixtures/ns_generic_match_typevar_arm/generic_match_typevar_arm.baml",
    ),
];

// The insta file name prefix of a pattern corpus snapshot.
const PATTERN_CORPUS_PREFIX: string = "baml_tests__type_spec__pattern_corpus__";

// One corpus's snapshot comparison: the upstream body and our rendering.
// `snapshot` is the insta name (`corpus__<corpus>`).
function corpus_snapshot(
    db: root.hir.Db,
    snapshot: string,
) -> SnapshotResult throws baml.errors.Io | baml.errors.ParseError {
    let corpus = PATTERN_CORPORA.find((c) -> {
        c.0 == snapshot
    })
        ?? baml.sys.panic(`unknown pattern corpus ${snapshot}`);
    let snap = baml.fs.read(`${TYPE_SPEC_DIR}/snapshots/${PATTERN_CORPUS_PREFIX}${snapshot}.snap`);
    SnapshotResult {
        name: snapshot,
        expected: snapshot_body(snap),
        ours: corpus_verdicts(db, corpus.1),
    }
}

// Every corpus: `match` or a line diff against upstream.
function pattern_corpus_summary() -> string throws baml.errors.Io | baml.errors.ParseError {
    let db = root.stdlib_db();
    let results = PATTERN_CORPORA.map((c) -> SnapshotResult throws baml.errors.Io | baml.errors.ParseError {
        corpus_snapshot(db, c.0)
    });
    let matched = results
        .filter((r) -> {
            r.expected == r.ours
        })
        .length();
    [`pattern corpus snapshots: ${matched}/${results.length()} match`]
        .concat(
            results.map((r) -> {
                if (r.expected == r.ours) {
                    `${r.name}: match`
                } else {
                    `${r.name}: differs\n${unified_diff(r.expected, r.ours)}`
                }
            }),
        )
        .join("\n")
}

// port: baml_tests/src/type_spec/pattern_corpus.rs::match_exhaustiveness_corpus @ d9be6853b
test "match exhaustiveness corpus" {
    let result = corpus_snapshot(root.stdlib_db(), "corpus__match_exhaustiveness");
    assert.equal(result.ours, result.expected)
}

// port: baml_tests/src/type_spec/pattern_corpus.rs::generic_rigid_coverage_corpus @ d9be6853b
test "generic rigid coverage corpus" {
    let result = corpus_snapshot(root.stdlib_db(), "corpus__generic_rigid_coverage");
    assert.equal(result.ours, result.expected)
}

// port: baml_tests/src/type_spec/pattern_corpus.rs::patterns_new_corpus @ d9be6853b
test "patterns new corpus" {
    let result = corpus_snapshot(root.stdlib_db(), "corpus__patterns_new");
    assert.equal(result.ours, result.expected)
}

// port: baml_tests/src/type_spec/pattern_corpus.rs::generic_match_typevar_arm_corpus @ d9be6853b
test "generic match typevar arm corpus" {
    let result = corpus_snapshot(root.stdlib_db(), "corpus__generic_match_typevar_arm");
    assert.equal(result.ours, result.expected)
}
