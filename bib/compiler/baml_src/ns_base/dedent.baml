// port: baml_base/src/dedent.rs @ d9be6853b

// port: baml_base/src/dedent.rs::dedent_backtick. Strip the layout
// of a backtick string literal (BEP-049 section 12): `\r\n` and lone `\r`
// become `\n`; a single-line literal is unchanged; a multiline one loses
// every leading line break and all body-final ASCII layout whitespace, then
// the longest exact leading-whitespace prefix shared by its nonblank lines;
// lines of only ASCII layout become empty and leading empty lines go.
function dedent_backtick(text: string) -> string throws never {
    let normalized = text.replace_all("\r\n", "\n").replace_all("\r", "\n");
    if (!normalized.includes("\n")) {
        return normalized;
    }
    let chars = normalized.chars();
    let start = 0;
    while (start < chars.length() && chars[start] == "\n") {
        start += 1;
    }
    let end = chars.length();
    while (end > start && is_layout_whitespace(chars[end - 1])) {
        end -= 1;
    }
    let body = chars.slice(start, end).join("");
    let lines = if (body) {
        body.split("\n")
    } else {
        []
    };
    let strip = common_indent(lines);
    let dedented = lines.map((line) -> {
        if (
            line.chars().some((c) -> {
                !is_layout_whitespace(c)
            })
        ) {
            line.slice(strip.length(), line.length())
        } else {
            ""
        }
    });
    let first = 0;
    while (first < dedented.length() && !dedented[first]) {
        first += 1;
    }
    dedented.slice(first, dedented.length()).join("\n")
}

// port: baml_base/src/dedent.rs::is_layout_whitespace. Whitespace
// that is source layout rather than authored Unicode text.
function is_layout_whitespace(c: string) -> bool throws never {
    c == " " || c == "\t" || c == "\n"
}

// port: baml_base/src/dedent.rs::common_indent. The longest exact
// leading-whitespace prefix across the nonblank lines.
function common_indent(lines: string[]) -> string throws never {
    let common: string? = null;
    for (let line in lines) {
        if (
            line.chars().every((c) -> {
                is_layout_whitespace(c)
            })
        ) {
            continue;
        }
        let chars = line.chars();
        let n = 0;
        while (n < chars.length() && chars[n].is_whitespace()) {
            n += 1;
        }
        let ws = chars.slice(0, n);
        if (common == null) {
            common = ws.join("");
        } else {
            // The longest common prefix, character by character.
            let prev = common.chars();
            let k = 0;
            while (k < prev.length() && k < ws.length() && prev[k] == ws[k]) {
                k += 1;
            }
            common = prev.slice(0, k).join("");
        }
    }
    common ?? ""
}
