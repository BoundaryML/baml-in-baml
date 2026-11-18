// port: baml_tests/src/type_spec/sweep.rs @ d9be6853b
//
// The whole-corpus sweep: run hir_ty over every `baml_src` file and census
// the typed surface (error-channel entries, with any panic surfaced
// verbatim). Compared with upstream's insta snapshot
// (`snapshot_body`, `snapshot_matches`: insta 1.47's reader and comparison):
//
//   baml run oracle.type_spec.sweep_summary
//
// The corpus is `baml_tests/baml_src`, read in place, loaded as one
// workspace root of a stdlib Db (Rust's `make_db` plus `db.file` per file,
// in sorted path order).
//
// Restructured:
// - Rust's `catch_unwind` around each file is one task per file (the
//   fixtures runner's discipline): a panic records `<path>: <first line>`
//   and, since the Db is left mid-query, the Db is rebuilt (same files, same
//   order, so the same file ids) for the files after it.
// - `read_corpus_files`'s `&mut Vec` out-param is the returned array;
//   `(rel, content)` pairs are `CorpusFile`s.
// - The `#[test]` is a test block over `sweep_snapshot`, which also feeds
//   `sweep_summary`. `insta::assert_snapshot!` is `snapshot_matches`
//   (insta 1.47's comparison, as the fixtures harness uses); the summary
//   prints a line diff on a mismatch.
// - `snippet` slices UTF-8 bytes, as Rust's `&str` ranges do (the corpus is
//   not all ASCII, and our string slicing is by character).

// Upstream's `baml_tests` crate (Rust's `CARGO_MANIFEST_DIR`), relative to
// this project.
const BAML_TESTS_DIR: string = "../../baml_language/crates/baml_tests";

// port: baml_tests/src/type_spec/sweep.rs::baml_src_dir @ d9be6853b
function baml_src_dir() -> string throws never {
    `${BAML_TESTS_DIR}/baml_src`
}

// A corpus file: its path relative to the corpus root and its text.
class CorpusFile {
    rel: string,
    content: string,
}

// port: baml_tests/src/type_spec/sweep.rs::read_corpus_files @ d9be6853b
// Every `.baml` file under `dir`, recursively, skipping directories whose
// name starts with `.`; paths relative to `corpus_root`, CRLF folded to LF.
function read_corpus_files(
    corpus_root: string,
    dir: string,
) -> CorpusFile[] throws baml.errors.Io | baml.errors.ParseError {
    let out: CorpusFile[] = [];
    for (let entry in baml.fs.read_dir(dir)) {
        let path = `${dir}/${entry.name}`;
        if (entry.is_dir) {
            if (entry.name.starts_with(".")) {
                continue;
            }
            out = out.concat(read_corpus_files(corpus_root, path));
        } else if (entry.name.ends_with(".baml")) {
            let rel = path.slice(corpus_root.length() + 1, path.length()).replace_all("\\", "/");
            let content = baml.fs.read(path).replace_all("\r\n", "\n");
            out.push(CorpusFile { rel: rel, content: content });
        }
    }
    out
}

// A stdlib Db with `files` loaded, in order, as one workspace root; the file
// ids are returned parallel to `files`.
function load_corpus(files: CorpusFile[]) -> (root.hir.Db, int[]) throws never {
    let db = root.stdlib_db();
    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    let ids = files.map((f) -> {
        root.db.add_file(db, workspace, f.rel, f.content)
    });
    (db, ids)
}

// port: baml_tests/src/type_spec/sweep.rs::s15_sweep_baml_src @ d9be6853b
// The census report.
function sweep_report() -> string throws baml.errors.Io | baml.errors.ParseError {
    let corpus_root = baml_src_dir();
    let files = read_corpus_files(corpus_root, corpus_root).sort_by((a, b) -> {
        a.rel.cmp(b.rel)
    });
    let (let db, let ids) = load_corpus(files);

    let channel_entries: string[] = [];
    let panics: string[] = [];

    for (let i = 0; i < files.length(); i += 1) {
        let rel = files[i].rel;
        let content = files[i].content;
        let file_db = db;
        let file = ids[i];
        let task: baml.future.Future<ErrorChannel, never> = spawn { collect_hir_ty_error_channel(file_db, file) };
        let settled = await baml.future.all_settled([task]);
        let channel = match (settled[0]) {
            let ok: baml.future.Success<ErrorChannel> => ok.value,
            let panicked: baml.future.Panicked => {
                panics.push(`${rel}: ${first_line(`${panicked.panic}`)}`);
                db = load_corpus(files).0;
                continue;
            },
            _ => {
                panics.push(`${rel}: <task failed>`);
                db = load_corpus(files).0;
                continue;
            },
        };

        for (let section in [channel.mismatches, channel.implements_]) {
            for (let key in sorted_keys(section)) {
                let range = range_of_key(key);
                for (let entry in section[key]) {
                    channel_entries.push(
                        `${rel}:${range.start}..${range.end} \`${snippet(content, range.start, range.end)}\`: ${entry}`,
                    );
                }
            }
        }
        for (let range in channel.non_exhaustive) {
            channel_entries.push(
                `${rel}:${range.start}..${range.end} \`${snippet(content, range.start, range.end)}\`: non-exhaustive`,
            );
        }
    }

    let report = [
        `hir_ty error-channel entries: ${channel_entries.length()}\n`,
        `panics: ${panics.length()}\n`,
        "\n== hir_ty error channel\n",
    ];
    for (let entry in channel_entries) {
        report.push(`${entry}\n`);
    }
    if (panics.length() > 0) {
        report.push("\n== panics\n");
        for (let entry in panics) {
            report.push(`${entry}\n`);
        }
    }
    report.join("")
}

// port: baml_tests/src/type_spec/sweep.rs::snippet @ d9be6853b
// The source text of byte range `start..end`, newlines escaped, shortened
// to its first 10 and last 11 bytes past 24 bytes.
function snippet(content: string, start: int, end: int) -> string throws never {
    let raw = string.from_utf8(content.to_utf8().slice(start, end)) catch_all (e) {
        _ => baml.sys.panic(`snippet ${start}..${end} is not on a char boundary`),
    };
    let flat = raw.replace_all("\n", "\\n");
    let bytes = flat.to_utf8();
    if (bytes.length() <= 24) {
        return flat;
    }
    let from_bytes = (part: uint8array) -> string {
        string.from_utf8(part) catch_all (e) {
            _ => baml.sys.panic("snippet cut is not on a char boundary"),
        }
    };
    `${from_bytes(bytes.slice(0, 10))}...${from_bytes(bytes.slice(bytes.length() - 11, bytes.length()))}`
}

// port: baml_tests/src/type_spec/sweep.rs::first_line @ d9be6853b
function first_line(text: string) -> string throws never {
    text.split("\n").at(0) ?? text
}

// The insta snapshot of `s15_sweep_baml_src`.
const SWEEP_SNAPSHOT: string = "baml_tests__type_spec__sweep__s15_sweep_baml_src";

// The sweep's snapshot comparison: the upstream body and our report.
function sweep_snapshot() -> SnapshotResult throws baml.errors.Io | baml.errors.ParseError {
    let snap = baml.fs.read(`${TYPE_SPEC_DIR}/snapshots/${SWEEP_SNAPSHOT}.snap`);
    SnapshotResult {
        name: "s15_sweep_baml_src",
        expected: snapshot_body(snap),
        ours: sweep_report(),
    }
}

// `match`, or a line diff against upstream.
function sweep_summary() -> string throws baml.errors.Io | baml.errors.ParseError {
    let result = sweep_snapshot();
    if (snapshot_matches(result.expected, result.ours)) {
        `${result.name}: match`
    } else {
        `${result.name}: differs\n${unified_diff(snapshot_normalize(result.expected), snapshot_normalize(result.ours))}`
    }
}

// port: baml_tests/src/type_spec/sweep.rs::s15_sweep_baml_src @ d9be6853b
test "s15 sweep baml src" {
    let result = sweep_snapshot();
    assert.is_true(snapshot_matches(result.expected, result.ours))
}
