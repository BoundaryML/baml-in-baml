// How many diagnostics of each code the Rust compiler reports on the corpus,
// for one phase: what a stage's gate has to reproduce, largest first.
//
//   baml run oracle.census -- --phase type

const CENSUS_CORPORA: string[] = [
    "../../baml_language/crates/baml_tests/projects/broken_syntax",
    "../../baml_language/crates/baml_tests/projects/diagnostic_errors",
    "../../baml_language/crates/baml_tests/projects/parser_stress",
    "../../baml_language/crates/baml_tests/baml_src",
];

function census(phase: string) -> string throws baml.errors.Io | baml.errors.ParseError {
    let counts: map<string, int> = {};
    let units = 0;
    for (let dir in CENSUS_CORPORA) {
        let paths = baml.glob.new("**/*.baml").scan(dir);
        let unit: CorpusUnit = if (dir.ends_with("baml_src")) { "whole" } else { "project" };
        for (let group in corpus_units(paths, unit)) {
            let files: map<string, string> = {};
            for (let path in group.paths) {
                files[path.slice(group.prefix.length(), path.length())] = baml.fs.read(`${dir}/${path}`);
            }
            units += 1;
            for (let d in rust_diagnostics(files)) {
                if (d.phase == phase) {
                    let key = `${d.code} ${d.headline.split("`")[0].trim()}`;
                    counts[key] = (counts.get(key) ?? 0) + 1;
                }
            }
        }
    }
    let keys = counts.keys();
    keys.sort_by((a, b) -> { counts[b].cmp(counts[a]) });
    let total = keys.reduce((acc, k) -> { acc + counts[k] }, 0);
    [`${total} ${phase} diagnostics, ${keys.length()} kinds, ${units} units`]
        .concat(keys.map((k) -> { `${counts[k]}\t${k}` }))
        .join("\n")
}
