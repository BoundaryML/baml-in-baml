// The Rust compiler as `baml check` runs it: the oracle for the Type gate.
//
// `reflect.Package._compile` (oracle.baml) loads the stdlib as precompiled
// package interfaces; `baml check` compiles a project against the stdlib as
// users see it. Through HIR the two agree. In type checking they do not:
// the interface lane skips stdlib bodies (init io), hides private fields,
// drops some markers (`//baml:tagged_string`) and impls, so on
// `baml_tests/baml_src` it reports ~280 diagnostics `baml check` does not.
// Our compiler, like `baml check`, sees the stdlib's source.
//
// A unit's files are written under `CLI_PROJECT/baml_src` and checked there.
// `baml check` prints no machine-readable diagnostics, so its text is parsed:
// `path:line:col-line:col severity[code]: headline` (`path:line:col` for a
// zero-width span), then indented
// `primary: label` / `secondary ...` lines. Columns count characters.

// A scratch project (gitignored), relative to bib/compiler.
const CLI_PROJECT: string = ".cli_oracle";

function cli_prepare() -> void throws baml.errors.Io {
    if (!baml.fs.exists(CLI_PROJECT)) {
        baml.fs.mkdir(CLI_PROJECT, baml.fs.MkdirOptions { recursive: true });
        baml.fs.write(`${CLI_PROJECT}/baml.toml`, "[package]\nname = \"cli_oracle\"\n");
        baml.sys.run("baml", args = ["agent", "install"], cwd = CLI_PROJECT, capture_output = true) catch_all (e) {
            _ => null,
        };
    }
}

// Byte offset of 1-based `line`, 1-based character `col`, in `text`.
function cli_offset(lines: string[], line: int, col: int) -> int throws never {
    let offset = 0;
    for (let i = 0; i < line - 1 && i < lines.length(); i += 1) {
        offset += lines[i].to_utf8().length() + 1;
    }
    if (line - 1 >= lines.length()) {
        return offset;
    }
    offset + lines[line - 1].slice(0, col - 1).to_utf8().length()
}

// One diagnostic `baml check` printed: its code, span and comparison key.
class CliDiagnostic {
    code: string,
    // `file:start-end`, byte offsets.
    at: string,
    key: string,
}

// A unit whose only file is the unit itself has the path "": it is written
// under this name, and read back as "".
const CLI_UNNAMED: string = "_unit.baml";

// Every diagnostic `baml check` reports on `files`, keyed as
// `cli_shaped_key` keys ours. The CLI prints a file's path relative to its
// namespace folder, so a path is matched against the unit's paths by suffix.
// A headline's first line is kept (its `help:` text is printed apart). A
// header line this parser does not read (an end-of-file error has no span)
// ends the previous diagnostic and is dropped.
function cli_diagnostics(
    files: map<string, string>,
) -> CliDiagnostic[] throws baml.errors.Io | baml.errors.ParseError {
    cli_prepare();
    let src = `${CLI_PROJECT}/baml_src`;
    if (baml.fs.exists(src)) {
        baml.fs.remove_dir_all(src);
    }
    let lines_of: map<string, string[]> = {};
    for (let path in files.keys()) {
        let full = `${src}/${if (path == "") { CLI_UNNAMED } else { path }}`;
        let parts = full.split("/");
        baml.fs.mkdir(
            parts.slice(0, parts.length() - 1).join("/"),
            baml.fs.MkdirOptions { recursive: true },
        );
        baml.fs.write(full, files[path]);
        lines_of[path] = files[path].split("\n");
    }
    let resolve = (printed: string) -> string {
        if (printed == CLI_UNNAMED) {
            return "";
        }
        if (lines_of.has(printed)) {
            return printed;
        }
        if (printed.starts_with("baml_src/") && lines_of.has(printed.slice(9, printed.length()))) {
            return printed.slice(9, printed.length());
        }
        lines_of.keys().find((path) -> {
            path.ends_with(`/${printed}`)
        })
            ?? printed
    };
    let run = baml.sys.run(
        "baml",
        args = ["check", "--color", "never", "-q"],
        cwd = CLI_PROJECT,
        env = { "BAML_TELEMETRY": "off" },
        capture_output = true,
    ) catch_all (e) {
        _ => baml.sys.panic("cannot run `baml check`"),
    };
    // Diagnostics are printed on stderr.
    let text = string.from_utf8(run.stderr) catch_all (e) {
        _ => "",
    };
    let out: CliDiagnostic[] = [];
    let pending: CliDiagnostic? = null;
    let headline = "";
    let label = "";
    let flush = () -> void {
        let p = pending;
        if (p != null) {
            out.push(
                CliDiagnostic {
                    code: p.code,
                    at: p.at,
                    key: `${p.code} ${p.at} ${headline} | ${label}`,
                },
            );
        }
        pending = null;
    };
    let head = baml.regex.new(
        "^(.+?):(\\d+):(\\d+)(?:-(\\d+):(\\d+))? (?:error|warning|info)\\[(E\\d+)\\]: (.*)$",
    ) catch_all (e) {
        _ => baml.sys.panic("bad diagnostic pattern"),
    };
    for (let line in text.split("\n")) {
        let found = head.match_full(line);
        if (found != null) {
            let m = found.groups;
            flush();
            let path = resolve(m[1]?.text ?? "");
            let lines = lines_of.get(path) ?? [];
            let start = cli_offset(lines, int.parse(m[2]?.text ?? "1"), int.parse(m[3]?.text ?? "1"));
            // A zero-width span prints as `line:col` alone.
            let end = if (m[4] == null) {
                start
            } else {
                cli_offset(lines, int.parse(m[4]?.text ?? "1"), int.parse(m[5]?.text ?? "1"))
            };
            pending
                = CliDiagnostic { code: m[6]?.text ?? "", at: `${path}:${start}-${end}`, key: "" };
            headline = m[7]?.text ?? "";
            label = "";
        } else if (line.starts_with("  primary: ")) {
            label = line.slice(11, line.length());
        } else if (
            line != ""
                && !line.starts_with(" ")
                && !line.starts_with("help:")
                && !line.starts_with("note:")
        ) {
            flush();
        }
    }
    flush();
    out
}

// Our diagnostics in the same shape: first headline line only.
function cli_shaped_key(d: reflect.Diagnostic) -> string throws never {
    let span = d.span;
    let at = if (span) {
        `${span.file ?? ""}:${span.start}-${span.end}`
    } else {
        "-"
    };
    `${d.code} ${at} ${d.headline.split("\n")[0]} | ${d.primary_label ?? ""}`
}

// Every diagnostic, ours vs the Rust compiler's, sorted. Rust's expected set
// takes the parse, HIR and validation diagnostics from `reflect` (exact, and
// the stdlib lane does not change them) and the rest from `baml check`: a
// CLI diagnostic at the code and span of one of those is that one, printed
// in the CLI's own way, and so is a parse error the CLI prints with the
// end-of-file span shifted (`... found end of file`).
function compare_cli(
    files: map<string, string>,
    db: root.hir.Db? = null,
) -> ParseComparison throws baml.errors.Io | baml.errors.ParseError {
    let ours = if (db) {
        root.check_with(db, files)
    } else {
        root.check(files)
    };
    let early = rust_diagnostics(files).filter((d) -> {
        d.phase != "type"
    });
    let early_at: map<string, bool> = {};
    for (let d in early) {
        let span = d.span;
        if (span) {
            early_at[`${d.code} ${span.file ?? ""}:${span.start}-${span.end}`] = true;
        }
    }
    let typed = cli_diagnostics(files).filter((c) -> {
        !early_at.has(`${c.code} ${c.at}`)
            && !((c.code == "E0010" || c.code == "E0009") && c.key.ends_with("found end of file"))
    });
    let rust = early.map(cli_shaped_key).concat(
        typed.map((c) -> {
            c.key
        }),
    );
    let mine = ours.map(cli_shaped_key);
    rust.sort_by((a, b) -> {
        a.cmp(b)
    });
    mine.sort_by((a, b) -> {
        a.cmp(b)
    });
    ParseComparison { rust: rust, ours: mine }
}
