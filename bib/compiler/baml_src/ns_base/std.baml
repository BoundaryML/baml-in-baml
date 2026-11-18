// Stand-ins for Rust std methods the BAML stdlib does not have yet.
// Candidates for the BAML stdlib upstream.

// port: `str::trim_start_matches` with a string pattern.
function trim_start_matches(text: string, pattern: string) -> string throws never {
    let rest = text;
    while (rest.starts_with(pattern)) {
        rest = rest.slice(pattern.length(), rest.length());
    }
    rest
}

// port: `str::trim_end_matches` with a string pattern.
function trim_end_matches(text: string, pattern: string) -> string throws never {
    let rest = text;
    while (rest.ends_with(pattern)) {
        rest = rest.slice(0, rest.length() - pattern.length());
    }
    rest
}

// port: `Vec::extend`. Appends `items` to `out` in place.
function extend<T>(out: T[], items: T[]) -> void throws never {
    for (let item in items) {
        out.push(item);
    }
}

// port: `Vec::extend(Option)`. Appends `item` to `out` when present.
function push_some<T>(out: T[], item: T?) -> void throws never {
    if (item != null) {
        out.push(item);
    }
}

// port: `str::strip_prefix`.
function strip_prefix(text: string, prefix: string) -> string? throws never {
    if (text.starts_with(prefix)) {
        text.slice(prefix.length(), text.length())
    } else {
        null
    }
}
