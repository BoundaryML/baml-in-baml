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
  mismatches: CorpusMismatch[],
}

function parse_corpus(dir: string) -> CorpusReport throws baml.errors.Io | baml.errors.ParseError {
  let paths = baml.glob.new("**/*.baml").scan(dir);
  let mismatches: CorpusMismatch[] = [];
  for (let path in paths) {
    let comparison = compare_parse({path: baml.fs.read(`${dir}/${path}`)});
    if (comparison.ours != comparison.rust) {
      mismatches.push(CorpusMismatch { path: path, rust: comparison.rust, ours: comparison.ours });
    }
  }
  CorpusReport { files: paths.length(), matched: paths.length() - mismatches.length(), mismatches: mismatches }
}

// One line per directory, then the first `limit` mismatches of each.
function corpus_summary(dirs: string[], limit: int = 5) -> string throws baml.errors.Io | baml.errors.ParseError {
  dirs.map((dir) -> {
    let report = parse_corpus(dir);
    let head = `${dir}: ${report.matched}/${report.files} files match`;
    let shown = report.mismatches.slice(0, limit).map((m) -> {
      `  ${m.path}\n    rust: ${m.rust.join("\n          ")}\n    ours: ${m.ours.join("\n          ")}`
    });
    [head].concat(shown).join("\n")
  }).join("\n")
}
