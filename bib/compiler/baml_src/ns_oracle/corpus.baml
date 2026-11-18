// Compare our parse diagnostics with the Rust compiler's for every .baml file
// under a directory, one file at a time.

class CorpusMismatch {
    path: string,
    rust: string[],
    ours: string[],
}

class CorpusReport {
    files: int,
    matched: int,
    // Mismatches listed in KNOWN_DIFFERENCES, by path.
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

function parse_corpus(
    dir: string,
    stage: "parse" | "lowering" = "parse",
) -> CorpusReport throws baml.errors.Io | baml.errors.ParseError {
    let paths = baml.glob.new("**/*.baml").scan(dir);
    let mismatches: CorpusMismatch[] = [];
    let known: string[] = [];
    for (let path in paths) {
        let files = { path: baml.fs.read(`${dir}/${path}`) };
        let comparison = if (stage == "lowering") {
            compare_lowering(files)
        } else {
            compare_parse(files)
        };
        if (comparison.ours != comparison.rust) {
            if (KNOWN_DIFFERENCES.has(path)) {
                known.push(path);
            } else {
                mismatches.push(
                    CorpusMismatch { path: path, rust: comparison.rust, ours: comparison.ours },
                );
            }
        }
    }
    CorpusReport {
        files: paths.length(),
        matched: paths.length() - mismatches.length() - known.length(),
        known: known,
        mismatches: mismatches,
    }
}

// One line per directory, then the first `limit` mismatches of each.
function corpus_summary(
    dirs: string[],
    limit: int = 5,
    stage: "parse" | "lowering" = "parse",
) -> string throws baml.errors.Io | baml.errors.ParseError {
    dirs
        .map((dir) -> {
            let report = parse_corpus(dir, stage = stage);
            let head = `${dir}: ${report.matched}/${report.files} files match, ${report.known.length()} known differences, ${report.mismatches.length()} mismatches`;
            let shown = report.mismatches.slice(0, limit).map((m) -> {
                `  ${m.path}\n    rust: ${m.rust.join("\n          ")}\n    ours: ${m.ours.join("\n          ")}`
            });
            [head].concat(shown).join("\n")
        })
        .join("\n")
}
