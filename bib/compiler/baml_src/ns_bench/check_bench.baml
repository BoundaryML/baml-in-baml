// The workload for profiling the compiler: `check` over a corpus directory as
// one project, the way the Type gate checks `baml_tests/baml_src`.
//
//   baml run bench.check_dir -- --dir ../../baml_language/crates/baml_tests/baml_src
//
// Run with telemetry on; the per-function times are then in the `profiler`
// relation (`baml query`, see bib/PORTING.md "Speed").

class CheckBench {
    files: int,
    diagnostics: int,
    stdlib_ms: bigint,
    check_ms: bigint,
}

function check_dir(dir: string) -> CheckBench throws baml.errors.Io | baml.errors.ParseError {
    let files: map<string, string> = {};
    for (let path in baml.glob.new("**/*.baml").scan(dir)) {
        files[path] = baml.fs.read(`${dir}/${path}`);
    }
    let started = baml.time.Instant.now();
    let db = root.stdlib_db();
    let stdlib_ms = started.elapsed().to_milliseconds();
    let checked = baml.time.Instant.now();
    let diagnostics = root.check_with(db, files);
    CheckBench {
        files: files.length(),
        diagnostics: diagnostics.length(),
        stdlib_ms: stdlib_ms,
        check_ms: checked.elapsed().to_milliseconds(),
    }
}

// The quick loop: load the whole corpus as one project but check only every
// `every`-th file (`check_file` on each, as `check_with` would). Whole-project
// costs (impl candidates, package items, the stdlib) are paid as in the full
// run; only the per-file work shrinks.
function check_sample(dir: string, every: int = 15) -> CheckBench throws baml.errors.Io | baml.errors.ParseError {
    let files: map<string, string> = {};
    for (let path in baml.glob.new("**/*.baml").scan(dir)) {
        files[path] = baml.fs.read(`${dir}/${path}`);
    }
    let started = baml.time.Instant.now();
    let db = root.stdlib_db();
    let stdlib_ms = started.elapsed().to_milliseconds();
    let checked = baml.time.Instant.now();
    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    for (let path in files.keys()) {
        root.db.add_file(db, workspace, path, files[path]);
    }
    let file_ids = db.source_root(workspace).files;
    let count = 0;
    for (let i = 0; i < file_ids.length(); i += every) {
        count += root.check_file(db, file_ids[i]).length();
    }
    CheckBench {
        files: (file_ids.length() + every - 1) / every,
        diagnostics: count,
        stdlib_ms: stdlib_ms,
        check_ms: checked.elapsed().to_milliseconds(),
    }
}

// Where the sample's time goes, phase by phase, each forcing the previous
// one's memos first: parse (typed tree) of every file, AST, semantic index,
// then `check_file` on the sample.
function phase_times(dir: string, every: int = 15) -> string throws baml.errors.Io | baml.errors.ParseError {
    let files: map<string, string> = {};
    for (let path in baml.glob.new("**/*.baml").scan(dir)) {
        files[path] = baml.fs.read(`${dir}/${path}`);
    }
    let db = root.stdlib_db();
    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    for (let path in files.keys()) {
        root.db.add_file(db, workspace, path, files[path]);
    }
    let all: int[] = [];
    for (let i = 0; i < db.files.length(); i += 1) {
        all.push(i);
    }
    let t = baml.time.Instant.now();
    for (let f in all) {
        root.hir.typed_tree(db, f);
    }
    let parse_ms = t.elapsed().to_milliseconds();
    t = baml.time.Instant.now();
    for (let f in all) {
        root.hir.file_ast(db, f);
    }
    let ast_ms = t.elapsed().to_milliseconds();
    t = baml.time.Instant.now();
    for (let f in all) {
        root.hir.file_semantic_index(db, f);
    }
    let index_ms = t.elapsed().to_milliseconds();
    t = baml.time.Instant.now();
    let file_ids = db.source_root(workspace).files;
    for (let i = 0; i < file_ids.length(); i += every) {
        root.check_file(db, file_ids[i]);
    }
    let check_ms = t.elapsed().to_milliseconds();
    `files ${all.length()}: parse ${parse_ms} ms, ast ${ast_ms} ms, semantic index ${index_ms} ms, then check_file on every ${every}th workspace file ${check_ms} ms`
}
