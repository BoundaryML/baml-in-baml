// Compare our parse diagnostics with the Rust compiler's for every .baml file
// under a directory, one file at a time.

class CorpusMismatch {
    path: string,
    rust: string[],
    ours: string[],
}

class CorpusReport {
    files: int,
    // Compilation units compared (files, projects, or 1 for the whole).
    units: int,
    // Units whose only differences are in files listed in KNOWN_DIFFERENCES.
    known: string[],
    mismatches: CorpusMismatch[],
}

// Corpus files where our output differs from the Rust compiler's on purpose,
// with the reason. Keyed by path relative to the corpus directory.
const KNOWN_DIFFERENCES: map<string, string> = {
    "invalid_numeric_literals/negative.baml": "63-bit int: lowering rejects an i64-only literal that Rust rejects during type checking",
    "ns_type_error_repro/type_error_repro.baml": "63-bit int: lowering rejects an i64-only literal that Rust rejects during type checking",
    "ns_ints/ints.baml": "63-bit int: lowering rejects an i64-only literal that Rust rejects during type checking",
    "ns_floats/floats.baml": "63-bit int: lowering rejects an i64-only literal that Rust rejects during type checking",
    "ns_match_optimization/match_optimization.baml": "63-bit int: lowering rejects an i64-only literal that Rust rejects during type checking",
};

// How a corpus directory is compiled: each file alone, each top-level
// directory as one project (`projects/*`), or the whole directory as one
// project (`baml_src`, as upstream's corpus test compiles it).
type CorpusUnit = "file" | "project" | "whole"

function parse_corpus(
    dir: string,
    stage: "parse" | "lowering" | "hir" | "types" = "parse",
    unit: CorpusUnit = "file",
) -> CorpusReport throws baml.errors.Io | baml.errors.ParseError {
    let paths = baml.glob.new("**/*.baml").scan(dir);
    let mismatches: CorpusMismatch[] = [];
    let known: string[] = [];
    // One stdlib compile for the whole corpus; each unit is its own workspace.
    let db = if (stage == "hir" || stage == "types") { root.stdlib_db() } else { null };
    let units = corpus_units(paths, unit);
    for (let group in units) {
        // Paths inside a unit are relative to it, as a project sees them.
        let files: map<string, string> = {};
        for (let path in group.paths) {
            files[path.slice(group.prefix.length(), path.length())] = baml.fs.read(`${dir}/${path}`);
        }
        let comparison = match (stage) {
            "lowering" => compare_lowering(files),
            "hir" => compare_hir(files, db = db),
            "types" => compare_types(files, db = db),
            "parse" => compare_parse(files),
        };
        // Diagnostics in a file with a known difference are compared apart.
        let is_known = (key: string) -> bool {
            group.paths.some((path) -> {
                KNOWN_DIFFERENCES.has(path) && key.includes(` ${path.slice(group.prefix.length(), path.length())}:`)
            })
        };
        let rust = comparison.rust.filter((key) -> { !is_known(key) });
        let ours = comparison.ours.filter((key) -> { !is_known(key) });
        if (comparison.rust != comparison.ours && rust == ours) {
            known.push(group.name);
        } else if (rust != ours) {
            mismatches.push(CorpusMismatch { path: group.name, rust: rust, ours: ours });
        }
    }
    CorpusReport {
        files: paths.length(),
        units: units.length(),
        known: known,
        mismatches: mismatches,
    }
}

// A compilation unit of a corpus: its name, the prefix its paths share, and
// its files (relative to the corpus directory).
class CorpusGroup {
    name: string,
    prefix: string,
    paths: string[],
}

function corpus_units(paths: string[], unit: CorpusUnit) -> CorpusGroup[] throws never {
    match (unit) {
        "file" => paths.map((path) -> { CorpusGroup { name: path, prefix: "", paths: [path] } }),
        "whole" => [CorpusGroup { name: "(whole project)", prefix: "", paths: paths }],
        "project" => {
            let groups: map<string, string[]> = {};
            for (let path in paths) {
                groups.get_or_insert(path.split("/")[0], []).push(path);
            }
            groups.keys().map((name) -> { CorpusGroup { name: name, prefix: `${name}/`, paths: groups[name] } })
        },
    }
}

// One line per directory, then the first `limit` mismatches of each.
function corpus_summary(
    dirs: string[],
    limit: int = 5,
    stage: "parse" | "lowering" | "hir" | "types" = "parse",
    unit: CorpusUnit = "file",
) -> string throws baml.errors.Io | baml.errors.ParseError {
    dirs
        .map((dir) -> {
            let report = parse_corpus(dir, stage = stage, unit = unit);
            let head = `${dir}: ${report.units} ${unit} units (${report.files} files), ${report.known.length()} with known differences, ${report.mismatches.length()} mismatches`;
            let shown = report.mismatches.slice(0, limit).map((m) -> {
                `  ${m.path}\n    rust: ${m.rust.join("\n          ")}\n    ours: ${m.ours.join("\n          ")}`
            });
            [head].concat(shown).join("\n")
        })
        .join("\n")
}
