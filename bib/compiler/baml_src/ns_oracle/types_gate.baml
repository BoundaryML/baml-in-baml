// The Type gate (bib/PORTING.md, "TIR plan"): every diagnostic, Type phase
// included, ours vs `baml check`'s (cli_oracle.baml), unit by unit.
//
//   baml run oracle.types_gate_summary
//
// Like the declaration gate, each unit runs in its own task, so a panic stops
// only that unit. Diagnostics in files listed in KNOWN_DIFFERENCES are set
// aside. Besides the per-unit result, the summary tallies the unmatched
// diagnostics by code on each side: what to port or fix next.

class TypesGateReport {
    corpus: string,
    units: int,
    matched: int,
    known: int,
    mismatches: CorpusMismatch[],
    panicked: (string, string)[],
    // code -> count of diagnostics only Rust reports / only we report.
    rust_only: map<string, int>,
    ours_only: map<string, int>,
}

// The diagnostics in `a` that `b` lacks, with multiplicity.
function missing_from(a: string[], b: string[]) -> string[] throws never {
    let left: map<string, int> = {};
    for (let key in b) {
        left[key] = (left.get(key) ?? 0) + 1;
    }
    a.filter((key) -> {
        let n = left.get(key) ?? 0;
        if (n > 0) {
            left[key] = n - 1;
            return false;
        }
        true
    })
}

function tally_codes(keys: string[], into: map<string, int>) -> void throws never {
    for (let key in keys) {
        let code = key.split(" ")[0];
        into[code] = (into.get(code) ?? 0) + 1;
    }
}

function types_gate(dir: string, unit: CorpusUnit) -> TypesGateReport throws baml.errors.Io | baml.errors.ParseError {
    let paths = baml.glob.new("**/*.baml").scan(dir);
    let db = root.stdlib_db();
    let report = TypesGateReport {
        corpus: dir,
        units: 0,
        matched: 0,
        known: 0,
        mismatches: [],
        panicked: [],
        rust_only: {},
        ours_only: {},
    };
    for (let group in corpus_units(paths, unit)) {
        let files: map<string, string> = {};
        for (let path in group.paths) {
            files[path.slice(group.prefix.length(), path.length())] = baml.fs.read(`${dir}/${path}`);
        }
        report.units += 1;
        let unit_db = db;
        let task: baml.future.Future<ParseComparison, never> = spawn {
            compare_cli(files, db = unit_db) catch_all (e) {
                _ => baml.sys.panic(`oracle failed: ${e}`),
            }
        };
        let settled = await baml.future.all_settled([task]);
        match (settled[0]) {
            let ok: baml.future.Success<ParseComparison> => {
                let comparison = ok.value;
                let is_known = (key: string) -> bool {
                    group.paths.some((path) -> {
                        KNOWN_DIFFERENCES.has(path) && key.includes(` ${path.slice(group.prefix.length(), path.length())}:`)
                    })
                };
                let rust = comparison.rust.filter((key) -> { !is_known(key) });
                let ours = comparison.ours.filter((key) -> { !is_known(key) });
                if (rust == ours) {
                    if (comparison.rust == comparison.ours) {
                        report.matched += 1;
                    } else {
                        report.known += 1;
                    }
                } else {
                    report.mismatches.push(CorpusMismatch { path: group.name, rust: rust, ours: ours });
                    tally_codes(missing_from(rust, ours), report.rust_only);
                    tally_codes(missing_from(ours, rust), report.ours_only);
                }
            },
            let panicked: baml.future.Panicked => {
                report.panicked.push((group.name, `${panicked.panic}`));
                // The Db's tracked-query stack is left mid-query: start over.
                db = root.stdlib_db();
            },
            _ => {
                report.panicked.push((group.name, "failed"));
                db = root.stdlib_db();
            },
        }
    }
    report
}

function render_tally(tally: map<string, int>) -> string throws never {
    let codes = tally.keys();
    codes.sort_by((a, b) -> { tally[b].cmp(tally[a]) });
    codes.map((code) -> { `${code} ${tally[code]}` }).join(", ")
}

// One block per corpus: the counts, the code tallies, the first `limit`
// mismatches and every panic (panic messages grouped by their first line).
function types_gate_summary(limit: int = 5) -> string throws baml.errors.Io | baml.errors.ParseError {
    DECL_GATE_CORPORA
        .map((corpus) -> {
            let r = types_gate(corpus.0, corpus.1);
            let head = `${r.corpus}: ${r.matched}/${r.units} units match (+${r.known} known), ${r.mismatches.length()} mismatches, ${r.panicked.length()} panicked`;
            let tallies = [`  rust-only: ${render_tally(r.rust_only)}`, `  ours-only: ${render_tally(r.ours_only)}`];
            let shown = r.mismatches.slice(0, limit).map((m) -> {
                `  ${m.path}\n    rust: ${m.rust.join("\n          ")}\n    ours: ${m.ours.join("\n          ")}`
            });
            let panic_counts: map<string, int> = {};
            for (let p in r.panicked) {
                let first = p.1.split("\n")[0].slice(0, 160);
                panic_counts[first] = (panic_counts.get(first) ?? 0) + 1;
            }
            let panics = panic_counts.keys().map((p) -> { `  PANIC x${panic_counts[p]}: ${p}` });
            [head].concat(tallies).concat(shown).concat(panics).join("\n")
        })
        .join("\n")
}
