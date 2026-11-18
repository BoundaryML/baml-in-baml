// Not a port: the line diff the snapshot suites (sweep.baml,
// pattern_corpus.baml) print when our rendering differs from an upstream
// insta snapshot, in place of insta's own diff.

// Lines of context kept around each change.
const DIFF_CONTEXT: int = 2;

// One line of the edit script: kept (" "), upstream only ("-") or ours
// only ("+").
class DiffLine {
    tag: string,
    text: string,
}

// A unified-style line diff from `expected` (upstream) to `ours`: `@@`
// hunks of changed lines with DIFF_CONTEXT lines of context; empty when the
// two are equal. A final line without its newline shows as
// `\ No newline at end of file`.
function unified_diff(expected: string, ours: string) -> string throws never {
    if (expected == ours) {
        return "";
    }
    let script = diff_script(diff_lines(expected), diff_lines(ours));
    // Which script entries a hunk shows: every change and its context.
    let shown = script.map((_) -> {
        false
    });
    for (let i = 0; i < script.length(); i += 1) {
        if (script[i].tag != " ") {
            for (
                let j = (i - DIFF_CONTEXT).max(0);
                j < (i + DIFF_CONTEXT + 1).min(script.length());
                j += 1
            ) {
                shown[j] = true;
            }
        }
    }
    let out: string[] = ["--- upstream", "+++ ours"];
    // 1-based line numbers of the next upstream and ours line.
    let old_line = 1;
    let new_line = 1;
    let i = 0;
    while (i < script.length()) {
        if (!shown[i]) {
            if (script[i].tag != "+") {
                old_line += 1;
            }
            if (script[i].tag != "-") {
                new_line += 1;
            }
            i += 1;
            continue;
        }
        let hunk: string[] = [];
        let old_start = old_line;
        let new_start = new_line;
        while (i < script.length() && shown[i]) {
            let line = script[i];
            hunk.push(`${line.tag}${line.text}`);
            if (line.tag != "+") {
                old_line += 1;
            }
            if (line.tag != "-") {
                new_line += 1;
            }
            i += 1;
        }
        out.push(
            `@@ -${old_start},${old_line - old_start} +${new_start},${new_line - new_start} @@`,
        );
        out = out.concat(hunk);
    }
    out.join("\n")
}

// `text` split into lines, each keeping a marker when it ends without a
// newline, so a missing final newline is a difference the diff shows.
function diff_lines(text: string) -> string[] throws never {
    let lines = text.split("\n");
    let last = lines.pop() ?? "";
    if (last != "") {
        lines.push(`${last}\n\\ No newline at end of file`);
    }
    lines
}

// The shortest edit script from `a` to `b` by longest common subsequence.
function diff_script(a: string[], b: string[]) -> DiffLine[] throws never {
    // lcs[i][j]: the LCS length of a[i..] and b[j..].
    let lcs: int[][] = [];
    for (let i = 0; i <= a.length(); i += 1) {
        let row: int[] = [];
        for (let j = 0; j <= b.length(); j += 1) {
            row.push(0);
        }
        lcs.push(row);
    }
    for (let i = a.length() - 1; i >= 0; i -= 1) {
        for (let j = b.length() - 1; j >= 0; j -= 1) {
            lcs[i][j]
                = if (a[i] == b[j]) {
                    lcs[i + 1][j + 1] + 1
                } else {
                    lcs[i + 1][j].max(lcs[i][j + 1])
                };
        }
    }
    let script: DiffLine[] = [];
    let i = 0;
    let j = 0;
    while (i < a.length() || j < b.length()) {
        if (i < a.length() && j < b.length() && a[i] == b[j]) {
            script.push(DiffLine { tag: " ", text: a[i] });
            i += 1;
            j += 1;
        } else if (i < a.length() && (j == b.length() || lcs[i + 1][j] >= lcs[i][j + 1])) {
            script.push(DiffLine { tag: "-", text: a[i] });
            i += 1;
        } else {
            script.push(DiffLine { tag: "+", text: b[j] });
            j += 1;
        }
    }
    script
}
