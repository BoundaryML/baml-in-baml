//! `mir_oracle <dir> [--opt 0|1|2]`: every `.baml` file under `dir` as one
//! workspace package (paths relative to `dir`), then, file by file in path
//! order and function by function in declaration order, a `// file: <path>`
//! line and each function's `display_function`, as
//! `baml_tests/src/compiler2_mir/mod.rs::render_mir` prints it. A function
//! whose lowering fails prints `!! MIR lowering failed: <error>`.

use std::{fmt::Write as _, path::Path};

use baml_compiler2_hir::item_data::{file_functions, function_source_map};
use baml_compiler2_mir::{OptLevel, lower_function, pretty::display_function};
use baml_db::{ProjectDatabase, testing::TestDbExt};

fn collect(root: &Path, dir: &Path, out: &mut Vec<(String, String)>) {
    let mut entries: Vec<_> = std::fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", dir.display()))
        .map(|e| e.expect("dir entry").path())
        .collect();
    entries.sort();
    for path in entries {
        if path.is_dir() {
            collect(root, &path, out);
        } else if path.extension().is_some_and(|ext| ext == "baml") {
            let rel = path.strip_prefix(root).expect("under root");
            let text = std::fs::read_to_string(&path).expect("utf-8 source");
            out.push((rel.to_string_lossy().replace('\\', "/"), text));
        }
    }
}

fn run() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let dir = args.first().expect("usage: mir_oracle <dir> [--opt 0|1|2]");
    let opt = match args.iter().position(|a| a == "--opt").map(|i| args[i + 1].as_str()) {
        None | Some("2") => OptLevel::Two,
        Some("1") => OptLevel::One,
        Some("0") => OptLevel::Zero,
        Some(other) => panic!("unknown opt level {other}"),
    };
    let mut sources = Vec::new();
    collect(Path::new(dir), Path::new(dir), &mut sources);

    let mut db = ProjectDatabase::new();
    db.workspace(Path::new("."));
    let files: Vec<_> = sources
        .iter()
        .map(|(path, text)| (path, db.file(path, text)))
        .collect();

    let mut out = String::new();
    for (path, file) in files {
        writeln!(out, "// file: {path}").unwrap();
        let mut functions = file_functions(&db, file).to_vec();
        functions.sort_by_key(|loc| function_source_map(&db, *loc).span.start());
        for loc in functions {
            match lower_function(&db, loc, opt).as_ref() {
                Ok(mir) => writeln!(out, "{}", display_function(&db, mir)).unwrap(),
                Err(error) => writeln!(out, "!! MIR lowering failed: {error}").unwrap(),
            }
        }
    }
    print!("{out}");
}

fn main() {
    // The compiler recurses deeply; give it the CLI's worker stack.
    std::thread::Builder::new()
        .stack_size(256 * 1024 * 1024)
        .spawn(run)
        .expect("spawn")
        .join()
        .expect("mir_oracle panicked");
}
