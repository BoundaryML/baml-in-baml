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
