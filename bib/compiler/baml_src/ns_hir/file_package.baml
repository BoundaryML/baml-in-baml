// port: baml_compiler2_hir/src/file_package.rs @ d9be6853b
//
// Package/namespace resolution for a source file. A file's package is its
// source root (the root IS the package); its namespace chain is derived from
// `ns_*` path segments relative to the root's path.

// port: file_package.rs::PackageInfo. Package/namespace info for a file.
class PackageInfo {
    // The package the file belongs to (a root id). Rust's `root`, renamed
    // (IDIOMS: `root` is the package path).
    root_id: int,
    // Namespace path within the package, e.g. `["llm"]` for
    // `<builtin>/baml/ns_llm/llm.baml` or `ns_llm/client.baml`.
    namespace_path: string[],
}

// port: baml_compiler2_hir/src/file_package.rs::root_relative_path @ d9be6853b
// `file`'s path relative to its root: the spelling its namespace path, its
// test initializer's name, and its unit's `source_file` are derived from, so
// none of them carries the checkout's location. A file is under its root (the
// database picks a path's root by prefix); the one other shape is a path that
// is already relative, which the test harness adds to a root spelled `.`.
function root_relative_path(db: Db, file: int) -> string throws never {
    let source = db.file(file);
    let root_path = db.source_root(source.root).path;
    strip_path_prefix(source.path, root_path) ?? source.path
}

// port: baml_compiler2_hir/src/file_package.rs::extract_ns_name @ d9be6853b
// The namespace name a path component spells when it has the `ns_` prefix and
// a valid BAML identifier suffix (starts with a letter or `_`, the rest
// alphanumeric or `_`); null for non-`ns_*` components or invalid suffixes.
function extract_ns_name(component: string) -> string? throws never {
    let ns_name = root.base.strip_prefix(component, "ns_")
        ?? return null;
    let chars = ns_name.chars();
    let first = chars.at(0);
    let valid = first != null
        && (first.is_ascii_alphabetic() || first == "_")
        && chars.slice(1, chars.length()).every((c) -> {
            c.is_ascii_alphanumeric() || c == "_"
        });
    if (valid) {
        ns_name
    } else {
        null
    }
}

// port: baml_compiler2_hir/src/file_package.rs::file_package @ d9be6853b
// Which package a file belongs to, and its namespace within it. Memoized per
// file: it is called from every compiler phase.
function file_package(db: Db, file: int) -> PackageInfo throws never {
    db.memo.file_package.get(file, () -> {
        let root_id = db.file(file).root;
        let relative = root_relative_path(db, file);
        PackageInfo { root_id: root_id, namespace_path: namespace_path(relative) }
    })
}

// port: baml_compiler2_hir/src/file_package.rs::namespace_path @ d9be6853b
// The namespace of a file at `relative` to its source root: its directories
// named `ns_<identifier>`, outermost first. The file's own name never counts.
function namespace_path(relative: string) -> string[] throws never {
    let components = path_components(relative);
    if (components.length() == 0) {
        return [];
    }
    components.slice(0, components.length() - 1).filter_map((c) -> {
        if (path_component_is_normal(c)) {
            extract_ns_name(c)
        } else {
            null
        }
    })
}

// needs foundation: `std::path::Path::components` on a `/`-separated path. A
// leading `/` is the root component `/`; empty segments and `.` segments
// after the first are dropped; a leading `.` stays (Rust's `CurDir`).
function path_components(path: string) -> string[] throws never {
    let segments = path.split("/");
    let rest = segments.slice(1, segments.length()).filter((segment) -> {
        segment != "" && segment != "."
    });
    let first = segments.at(0) ?? "";
    let head: string[] = if (path.starts_with("/")) {
        ["/"]
    } else if (first != "") {
        [first]
    } else {
        []
    };
    head.concat(rest)
}

// needs foundation: `std::path::Component::Normal`: a component that is not
// the root, `.` or `..`.
function path_component_is_normal(component: string) -> bool throws never {
    component != "/" && component != "." && component != ".."
}

// needs foundation: `std::path::Path::strip_prefix`, component-wise: `path`
// with `prefix`'s components removed from its front, or null when `prefix` is
// not a prefix of `path`.
function strip_path_prefix(path: string, prefix: string) -> string? throws never {
    let path_parts = path_components(path);
    let prefix_parts = path_components(prefix);
    let n = prefix_parts.length();
    if (n > path_parts.length() || path_parts.slice(0, n) != prefix_parts) {
        return null;
    }
    path_parts.slice(n, path_parts.length()).join("/")
}
