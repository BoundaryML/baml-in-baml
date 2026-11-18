// MIR equivalence: our compiler's MIR against the Rust compiler's, for any
// program.
//
//   baml run oracle.mir_equiv -- --dir path/to/project
//
// The Rust side is `bib/tools/mir_oracle` (build it once:
// `cargo build --release` there), which prints, for every `.baml` file of a
// directory in path order, a `// file: <path>` line and the
// `display_function` of each function in declaration order (as
// `baml_tests/src/compiler2_mir/mod.rs::render_mir` does). `mir_dump` prints
// ours the same way, so the two texts compare function by function.

// The dump tool and its scratch input, relative to bib/compiler.
const MIR_ORACLE_BIN: string = "../tools/mir_oracle/target/release/mir_oracle";
const MIR_ORACLE_DIR: string = ".mir_oracle";

function opt_level_arg(opt: root.mir.OptLevel) -> string throws never {
    match (opt) {
        root.mir.OptLevel.Zero => "0",
        root.mir.OptLevel.One => "1",
        root.mir.OptLevel.Two => "2",
    }
}

// Our MIR for `files` (one workspace package) in mir_oracle's format.
function mir_dump(
    files: map<string, string>,
    opt: root.mir.OptLevel = root.mir.OptLevel.Two,
    db: root.hir.Db? = null,
) -> string throws never {
    let db_ = db ?? root.stdlib_db();
    let workspace = root.db.add_root(db_, "", root.base.SourceRootKind.Workspace, null, []);
    let paths = files.keys();
    paths.sort_by((a, b) -> { a.cmp(b) });
    let ids: map<string, int> = {};
    for (let path in paths) {
        ids[path] = root.db.add_file(db_, workspace, path, files[path]);
    }
    let out: string[] = [];
    for (let path in paths) {
        out.push(`// file: ${path}\n`);
        let functions = root.hir.file_functions(db_, ids[path]).concat([]);
        functions.sort_by_key((f) -> {
            root.hir.function_source_map(db_, f).span.start
        });
        for (let f in functions) {
            // A panic in our lowering (a stub, a bug) is that function's
            // output; the rest still print.
            let task: baml.future.Future<string, never> = spawn {
                let mir = root.mir.lower_function(db_, f, opt) catch (e) {
                    let err: root.mir.MirInternalError => err,
                };
                match (mir) {
                    let err: root.mir.MirInternalError => `!! MIR lowering failed: ${err.message}`,
                    let m: root.mir.MirFunction => root.mir.display_function(db_, m),
                }
            };
            let settled = await baml.future.all_settled([task]);
            let text = match (settled[0]) {
                let ok: baml.future.Success<string> => ok.value,
                let panicked: baml.future.Panicked => {
                    db_.cycles.reset();
                    `!! panic: ${`${panicked.panic}`.split("\n")[0]}`
                },
                _ => {
                    db_.cycles.reset();
                    "!! failed"
                },
            };
            out.push(`${text}\n`);
        }
    }
    out.join("")
}

// mir_oracle's MIR for `files`.
function mir_rust(
    files: map<string, string>,
    opt: root.mir.OptLevel = root.mir.OptLevel.Two,
) -> string throws baml.errors.Io {
    if (!baml.fs.exists(MIR_ORACLE_BIN)) {
        baml.sys.panic("bib/tools/mir_oracle is not built: run `cargo build --release` there");
    }
    // A directory per call, so concurrent runs do not share their input.
    let scratch = `${MIR_ORACLE_DIR}/${baml.random.SystemRandom.get().random_int()}`;
    for (let path in files.keys()) {
        let full = `${scratch}/${path}`;
        let parts = full.split("/");
        baml.fs.mkdir(parts.slice(0, parts.length() - 1).join("/"), baml.fs.MkdirOptions { recursive: true });
        baml.fs.write(full, files[path]);
    }
    let run = baml.sys.run(
        MIR_ORACLE_BIN,
        args = [scratch, "--opt", opt_level_arg(opt)],
        capture_output = true,
    ) catch_all (e) {
        _ => baml.sys.panic("cannot run mir_oracle"),
    };
    baml.fs.remove_dir_all(scratch);
    string.from_utf8(run.stdout) catch_all (e) {
        _ => baml.sys.panic("mir_oracle printed invalid UTF-8"),
    }
}

// A dump split into its functions, keyed `<file>#<n>` (the n-th function of
// the file in declaration order), so a function one side failed to lower
// still lines up with the other side's.
function split_dump(text: string) -> (string, string)[] throws never {
    let out: (string, string)[] = [];
    let file = "";
    let n = 0;
    let key = "";
    let body: string[] = [];
    let flush = () -> void {
        if (key != "") {
            out.push((key, body.join("\n")));
        }
        key = "";
        body = [];
    };
    for (let line in text.split("\n")) {
        if (line.starts_with("// file: ")) {
            flush();
            file = line.slice(9, line.length());
            n = 0;
        } else if (line.starts_with("fn ") || line.starts_with("!! ")) {
            flush();
            key = `${file}#${n}`;
            n += 1;
            body.push(line);
        } else if (key != "") {
            body.push(line);
        }
    }
    flush();
    out
}

class MirMismatch {
    function_: string,
    // The first differing line, 1-based within the function, and both sides.
    line: int,
    rust: string,
    ours: string,
}

class MirEquivReport {
    functions: int,
    matched: int,
    mismatches: MirMismatch[],
    // Functions only one side printed.
    rust_only: string[],
    ours_only: string[],
}

// Compare our MIR with Rust's for `files`, function by function.
function mir_equiv_files(
    files: map<string, string>,
    opt: root.mir.OptLevel = root.mir.OptLevel.Two,
    db: root.hir.Db? = null,
) -> MirEquivReport throws baml.errors.Io {
    let rust = split_dump(mir_rust(files, opt = opt));
    let ours_list = split_dump(mir_dump(files, opt = opt, db = db));
    let ours: map<string, string> = {};
    for (let entry in ours_list) {
        ours[entry.0] = entry.1;
    }
    let report = MirEquivReport { functions: rust.length(), matched: 0, mismatches: [], rust_only: [], ours_only: [] };
    let rust_keys: map<string, bool> = {};
    for (let entry in rust) {
        rust_keys[entry.0] = true;
        let mine = ours.get(entry.0);
        if (mine == null) {
            report.rust_only.push(entry.0);
        } else if (mine == entry.1) {
            report.matched += 1;
        } else {
            let a = entry.1.split("\n");
            let b = mine.split("\n");
            let i = 0;
            while (i < a.length() && i < b.length() && a[i] == b[i]) {
                i += 1;
            }
            report.mismatches.push(
                MirMismatch {
                    function_: `${entry.0} ${a[0]}`,
                    line: i + 1,
                    rust: if (i < a.length()) { a[i] } else { "<end>" },
                    ours: if (i < b.length()) { b[i] } else { "<end>" },
                },
            );
        }
    }
    for (let entry in ours_list) {
        if (!rust_keys.has(entry.0)) {
            report.ours_only.push(entry.0);
        }
    }
    report
}

function render_mir_report(name: string, r: MirEquivReport, limit: int) -> string throws never {
    let lines = [
        `${name}: ${r.matched}/${r.functions} functions match, ${r.mismatches.length()} differ, ${r.rust_only.length()} rust-only, ${r.ours_only.length()} ours-only`,
    ];
    for (let m in r.mismatches.slice(0, limit)) {
        lines.push(`  ${m.function_}\n    line ${m.line}\n    rust: ${m.rust}\n    ours: ${m.ours}`);
    }
    for (let k in r.rust_only.slice(0, limit)) {
        lines.push(`  rust-only: ${k}`);
    }
    for (let k in r.ours_only.slice(0, limit)) {
        lines.push(`  ours-only: ${k}`);
    }
    lines.join("\n")
}

function read_baml_dir(dir: string) -> map<string, string> throws baml.errors.Io | baml.errors.ParseError {
    let files: map<string, string> = {};
    for (let path in baml.glob.new("**/*.baml").scan(dir)) {
        files[path] = baml.fs.read(`${dir}/${path}`);
    }
    files
}

// Every `.baml` file under `dir` as one package: our MIR vs Rust's.
function mir_equiv(dir: string, opt: int = 2, limit: int = 10) -> string throws baml.errors.Io | baml.errors.ParseError {
    let level = if (opt == 0) {
        root.mir.OptLevel.Zero
    } else if (opt == 1) {
        root.mir.OptLevel.One
    } else {
        root.mir.OptLevel.Two
    };
    render_mir_report(dir, mir_equiv_files(read_baml_dir(dir), opt = level), limit)
}

// The corpora the MIR gate runs over: programs that check clean (MIR lowers
// checked programs only).
const MIR_GATE_CORPORA: (string, CorpusUnit)[] = [
    ("../../baml_language/crates/baml_tests/baml_src", "whole"),
];

// Every corpus unit, our MIR vs Rust's. A unit runs in its own task, so a
// panic in our lowering stops only that unit.
function mir_equiv_gate(opt: int = 2, limit: int = 10) -> string throws baml.errors.Io | baml.errors.ParseError {
    let level = if (opt == 0) {
        root.mir.OptLevel.Zero
    } else if (opt == 1) {
        root.mir.OptLevel.One
    } else {
        root.mir.OptLevel.Two
    };
    let blocks: string[] = [];
    for (let corpus in MIR_GATE_CORPORA) {
        let dir = corpus.0;
        let paths = baml.glob.new("**/*.baml").scan(dir);
        for (let group in corpus_units(paths, corpus.1)) {
            let files: map<string, string> = {};
            for (let path in group.paths) {
                files[path.slice(group.prefix.length(), path.length())] = baml.fs.read(`${dir}/${path}`);
            }
            let task: baml.future.Future<MirEquivReport, never> = spawn {
                mir_equiv_files(files, opt = level) catch_all (e) {
                    _ => baml.sys.panic(`oracle failed: ${e}`),
                }
            };
            let settled = await baml.future.all_settled([task]);
            let name = `${dir} ${group.name}`;
            match (settled[0]) {
                let ok: baml.future.Success<MirEquivReport> => {
                    blocks.push(render_mir_report(name, ok.value, limit));
                },
                let panicked: baml.future.Panicked => {
                    blocks.push(`${name}: PANIC ${panicked.panic}`);
                },
                _ => {
                    blocks.push(`${name}: failed`);
                },
            }
        }
    }
    blocks.join("\n")
}
