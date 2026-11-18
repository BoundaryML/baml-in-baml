// port: baml_tests/src/type_spec/fixtures.rs @ d9be6853b
//
// Directory-driven type conformance checks, read in place from upstream's
// `type_spec/fixtures/`. Every conforming fixture must satisfy its caret
// annotations and clean-by-default error channel; only SNAPSHOT_EXAMPLES
// render a full inferred-node dump, compared with upstream's insta snapshot
// as `insta::assert_snapshot!` compares them (`snapshot_body`,
// `snapshot_matches`).
//
//   baml run oracle.type_spec.type_spec_summary
//
// Restructured:
// - Rust's rayon pool (`FIXTURE_WORKERS`, `check_conforming_fixtures`'s
//   `workers`) is one task per fixture, run in order on one shared stdlib
//   Db (each fixture its own workspace root): a panic stops that fixture
//   only and counts as its failure, with the panic message.
// - The `conforming_fixtures` test is a function returning the report; the
//   test below asserts it is clean and `type_spec_summary` prints it.
//   `insta::assert_snapshot!` is `snapshot_body` plus `snapshot_matches`
//   (ports of insta 1.47.2, the version upstream locks), checked in
//   `TypeSpecReport.failed_snapshots`.
//
// Not ported: `bounded_pool_preserves_order_and_results` (it tests the rayon
// pool, which has no counterpart).

// Upstream's fixture and snapshot directories, relative to this project.
const TYPE_SPEC_DIR: string = "../../baml_language/crates/baml_tests/src/type_spec";

// port: baml_tests/src/type_spec/fixtures.rs::CheckedFixture @ d9be6853b
class CheckedFixture {
    name: string,
    snapshot: bool,
    outcome: FixtureOutcome,
}

// port: baml_tests/src/type_spec/fixtures.rs::check_conforming_fixtures @ d9be6853b
// Checks every fixture at `paths`, in order. Each runs in its own task on
// `db`; a fixture that panics fails with the panic message, and the Db
// (left mid-query) is rebuilt for the rest.
function check_conforming_fixtures(
    paths: string[],
) -> CheckedFixture[] throws baml.errors.Io | baml.errors.ParseError {
    let db = root.stdlib_db();
    let checked: CheckedFixture[] = [];
    for (let path in paths) {
        let name = fixture_name(path);
        let fixture = baml.fs.read(path);
        let snapshot = SNAPSHOT_EXAMPLES.some((example) -> {
            example.0 == name
        });
        let fixture_db = db;
        let task: baml.future.Future<FixtureOutcome, never> = spawn { run_fixture(fixture_db, fixture, snapshot) };
        let settled = await baml.future.all_settled([task]);
        let outcome = match (settled[0]) {
            let ok: baml.future.Success<FixtureOutcome> => ok.value,
            let panicked: baml.future.Panicked => {
                db = root.stdlib_db();
                FixtureOutcome { hir_ty: [`PANIC ${panicked.panic}`], dump: "" }
            },
            _ => {
                db = root.stdlib_db();
                FixtureOutcome { hir_ty: ["PANIC (task failed)"], dump: "" }
            },
        };
        checked.push(CheckedFixture { name: name, snapshot: snapshot, outcome: outcome });
    }
    checked
}

// port: baml_tests/src/type_spec/fixtures.rs::SNAPSHOT_EXAMPLES @ d9be6853b
// Golden dumps are opt-in: (fixture name, why it is a golden).
const SNAPSHOT_EXAMPLES: (string, string)[] = [
    ("reduce_literal_seed_widens", "Generic inference widens a literal seed."),
    ("null_guard_early_return", "Flow narrowing survives a diverging branch."),
    ("lambda_param_from_method_slot", "Contextual lambda parameter inference."),
    ("throws_mutual_recursion_fixpoint", "Recursive effect inference reaches a fixpoint."),
    ("match_rigid_arm_not_exhaustive", "Generic match error and non-exhaustiveness dump."),
];

// The insta file name prefix of a fixture golden.
const SNAPSHOT_PREFIX: string = "baml_tests__type_spec__fixtures__";

// port: baml_tests/src/type_spec/fixtures.rs::snapshot_examples_are_valid @ d9be6853b
test "snapshot examples are valid" {
    let names: map<string, bool> = {};
    for (let example in SNAPSHOT_EXAMPLES) {
        assert.is_true(!names.has(example.0));
        names[example.0] = true;
        assert.is_true(example.1.trim().length() > 0);
        let fixture = `${fixtures_root()}/${example.0}.baml`;
        assert.is_true(baml.fs.exists(fixture) && baml.fs.metadata(fixture).is_file);
    }
    let expected = SNAPSHOT_EXAMPLES
        .map((example) -> {
            `${SNAPSHOT_PREFIX}${example.0}.snap`
        })
        .sort_by((a, b) -> {
            a.cmp(b)
        });
    let actual = baml.fs.read_dir(`${TYPE_SPEC_DIR}/snapshots`)
        .map((entry) -> {
            entry.name
        })
        .filter((name) -> {
            name.starts_with(SNAPSHOT_PREFIX) && name.ends_with(".snap")
        })
        .sort_by((a, b) -> {
            a.cmp(b)
        });
    assert.equal(actual, expected)
}

// port: baml_tests/src/type_spec/fixtures.rs::fixtures_root @ d9be6853b
function fixtures_root() -> string throws never {
    `${TYPE_SPEC_DIR}/fixtures`
}

// port: baml_tests/src/type_spec/fixtures.rs::fixture_paths @ d9be6853b
// The `.baml` files directly in `dir`, sorted. A missing directory is an
// empty one when `allow_empty` (`pending/` disappears with its last promoted
// fixture). Rust's `extension() == "baml"`: a name ending `.baml` with a
// non-empty stem (`.baml` alone has no extension).
function fixture_paths(dir: string, allow_empty: bool) -> string[] throws baml.errors.Io {
    if (allow_empty && !baml.fs.exists(dir)) {
        return [];
    }
    let paths = baml.fs.read_dir(dir)
        .filter((entry) -> {
            entry.name.ends_with(".baml") && entry.name.length() > 5
        })
        .map((entry) -> {
            `${dir}/${entry.name}`
        })
        .sort_by((a, b) -> {
            a.cmp(b)
        });
    if (!allow_empty && paths.length() == 0) {
        baml.sys.panic(`no .baml fixtures found in ${dir}`);
    }
    paths
}

// port: baml_tests/src/type_spec/fixtures.rs::fixture_name @ d9be6853b
// The file stem.
function fixture_name(path: string) -> string throws never {
    let file = path.split("/").at(-1) ?? path;
    file.slice(0, file.last_index_of(".") ?? file.length())
}

// One golden's comparison: the upstream snapshot body and our dump.
class SnapshotResult {
    name: string,
    expected: string,
    ours: string,
}

// The run behind the `conforming_fixtures` test: every fixture's outcome and
// every golden's comparison.
class TypeSpecReport {
    fixtures: CheckedFixture[],
    snapshots: SnapshotResult[],
    // The annotation count over every fixture (the denominator of the
    // annotation tally).
    annotations: int,

    function failed_fixtures(self) -> CheckedFixture[] throws never {
        self.fixtures.filter((f) -> {
            f.outcome.hir_ty.length() > 0
        })
    }

    function failed_snapshots(self) -> SnapshotResult[] throws never {
        self.snapshots.filter((s) -> {
            !snapshot_matches(s.expected, s.ours)
        })
    }
}

// port: insta-1.47.2/src/snapshot.rs::Snapshot::from_file
// The text body of an insta `.snap` file. A first line `---` opens a YAML
// header that runs to the next line that is `---` (trailing whitespace
// ignored); any other first line starts a legacy header that runs to the
// first blank line. The body is the remaining lines as `BufRead::lines`
// yields them (`\n` or `\r\n` stripped), joined by `\n`.
// Not ported: parsing the header's YAML (only `snapshot_kind: binary`, which
// no type_spec golden uses, changes the comparison), so a header that is
// not valid YAML is not an error here. An unclosed YAML header panics: insta
// reads the whole file as the header, then fails to parse it or compares an
// empty body, which no non-empty dump matches.
function snapshot_body(snap: string) -> string throws never {
    let lines = snap.split("\n");
    // `split` leaves a trailing empty piece after a final newline; `lines` does not.
    if (lines.at(-1) == "") {
        lines.pop();
    }
    let at = 1;
    if (lines.length() > 0 && lines[0].trim_end() == "---") {
        while (true) {
            if (at >= lines.length()) {
                baml.sys.panic("snapshot has an unclosed insta header");
            }
            at += 1;
            if (lines[at - 1].trim_end() == "---") {
                break;
            }
        }
    } else {
        while (at < lines.length()) {
            at += 1;
            if (lines[at - 1].trim_end() == "") {
                break;
            }
        }
    }
    lines.slice(at, lines.length())
        .map((line) -> {
            if (line.ends_with("\r")) {
                line.slice(0, line.length() - 1)
            } else {
                line
            }
        })
        .join("\n")
}

// port: insta-1.47.2/src/snapshot.rs::TextSnapshotContents::normalize
// A file snapshot's contents as insta compares them: trailing whitespace
// dropped, `\r\n` read as `\n`.
function snapshot_normalize(contents: string) -> string throws never {
    contents.trim_end().replace_all("\r\n", "\n")
}

// port: insta-1.47.2/src/snapshot.rs::impl PartialEq for SnapshotContents
// Whether a stored snapshot body and a new value match, for text file
// snapshots: `matches_latest` (equal after `snapshot_normalize`), else
// `matches_legacy` (also ignoring leading `\r`/`\n` and then one leading
// `---\n`).
function snapshot_matches(stored: string, value: string) -> bool throws never {
    let legacy = (contents: string) -> string {
        let out = snapshot_normalize(contents);
        while (out.starts_with("\r") || out.starts_with("\n")) {
            out = out.slice(1, out.length());
        }
        root.base.strip_prefix(out, "---\n") ?? out
    };
    snapshot_normalize(stored) == snapshot_normalize(value) || legacy(stored) == legacy(value)
}

// port: baml_tests/src/type_spec/fixtures.rs::conforming_fixtures @ d9be6853b
function conforming_fixtures() -> TypeSpecReport throws baml.errors.Io | baml.errors.ParseError {
    let paths = fixture_paths(fixtures_root(), true);
    let checked = check_conforming_fixtures(paths);
    let annotations = paths
        .map((path) -> {
            extract_annotations(baml.fs.read(path)).length()
        })
        .reduce(
            (a, b) -> {
                a + b
            },
            0,
        );
    let snapshots = checked
        .filter((c) -> {
            c.snapshot
        })
        .map((c) -> {
            let snap = baml.fs.read(`${TYPE_SPEC_DIR}/snapshots/${SNAPSHOT_PREFIX}${c.name}.snap`);
            SnapshotResult { name: c.name, expected: snapshot_body(snap), ours: c.outcome.dump }
        });
    TypeSpecReport { fixtures: checked, snapshots: snapshots, annotations: annotations }
}

// Whether a failure line is about a type annotation or the error channel's
// `<clean>` side, for the annotation tally: one line per failing
// annotation, except unannotated channel entries and panics.
function is_annotation_failure(line: string) -> bool throws never {
    !line.includes(" expected=<clean> ") && !line.starts_with("PANIC")
}

// Totals, then each failing fixture with its failures, then the goldens.
function type_spec_summary() -> string throws baml.errors.Io | baml.errors.ParseError {
    let report = conforming_fixtures();
    let failed = report.failed_fixtures();
    let failed_annotations = failed
        .map((f) -> {
            f.outcome.hir_ty.filter(is_annotation_failure).length()
        })
        .reduce(
            (a, b) -> {
                a + b
            },
            0,
        );
    let fixtures_total = report.fixtures.length();
    let head = [
        `fixtures: ${fixtures_total - failed.length()}/${fixtures_total} pass, ${failed.length()} fail`,
        `annotations: ${report.annotations - failed_annotations}/${report.annotations} pass, ${failed_annotations} fail`,
        `snapshots: ${report.snapshots.length() - report.failed_snapshots().length()}/${report.snapshots.length()} match`,
    ];
    let fixtures = failed.map((f) -> {
        [`${f.name}:`]
            .concat(
                f.outcome.hir_ty.map((line) -> {
                    `  ${line}`
                }),
            )
            .join("\n")
    });
    let snapshots = report.failed_snapshots().map((s) -> {
        `snapshot ${s.name} differs:\n--- upstream\n${s.expected}\n--- ours\n${s.ours}`
    });
    head.concat(fixtures).concat(snapshots).join("\n")
}

// port: baml_tests/src/type_spec/fixtures.rs::conforming_fixtures @ d9be6853b
test "conforming fixtures" {
    let report = conforming_fixtures();
    assert.equal(
        report.failed_fixtures().map((f) -> {
            f.name
        }),
        [],
    );
    assert.equal(
        report.failed_snapshots().map((s) -> {
            s.name
        }),
        [],
    )
}

// port: baml_tests/src/type_spec/fixtures.rs::dump_selection_preserves_annotation_checks @ d9be6853b
test "dump selection preserves annotation checks" {
    let db = root.stdlib_db();
    let source = baml.fs.read(`${fixtures_root()}/reduce_literal_seed_widens.baml`);
    let with_dump = run_fixture(db, source, true);
    let without_dump = run_fixture(db, source, false);
    assert.equal(with_dump.hir_ty, []);
    assert.equal(with_dump.hir_ty, without_dump.hir_ty);
    assert.is_true(with_dump.dump.length() > 0);
    assert.equal(without_dump.dump, "");

    // Disabling a dump must not turn a wrong inferred-type expectation green.
    let marker = "// ^^^^^ int";
    let at = source.index_of(marker) ?? baml.sys.panic("fixture lost its `^^^^^ int` pin");
    let wrong_expectation = `${source.slice(0, at)}// ^^^^^ string${source.slice(at + marker.length(), source.length())}`;
    let wrong_with_dump = run_fixture(db, wrong_expectation, true);
    let wrong_without_dump = run_fixture(db, wrong_expectation, false);
    assert.is_true(wrong_with_dump.hir_ty.length() > 0);
    assert.equal(wrong_with_dump.hir_ty, wrong_without_dump.hir_ty)
}

// port: baml_tests/src/type_spec/fixtures.rs::pending_fixtures @ d9be6853b
// Empty is a success state: every pending fixture must start with its
// `// pending:` reason and must still fail.
test "pending fixtures" {
    let paths = fixture_paths(`${fixtures_root()}/pending`, true);
    let db = if (paths.length() > 0) {
        root.stdlib_db()
    } else {
        null
    };
    let failures: string[] = [];
    for (let path in paths) {
        let name = fixture_name(path);
        let fixture = baml.fs.read(path);
        let reason = fixture.split("\n")[0];
        if (
            !reason.starts_with("// pending: ")
                || reason.slice(12, reason.length()).trim().length() == 0
        ) {
            failures.push(
                `${name}: pending fixtures must start with \`// pending: <slice> <reason>\``,
            );
        }
        if (db != null && run_fixture(db, fixture, false).hir_ty.length() == 0) {
            failures.push(`${name}: pending fixture now passes; promote it to fixtures/`);
        }
    }
    assert.equal(failures, [])
}
