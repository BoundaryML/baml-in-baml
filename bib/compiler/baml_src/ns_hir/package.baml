// port: baml_compiler2_hir/src/package.rs @ d9be6853b
//
// Package-level cross-file symbol aggregation. A package IS a source root:
// package identity is the root's id, every package-level query is keyed on
// it, and a package reaches another only through an edge in its own
// `dependencies`, under the name that edge carries. `package_items` merges all
// `namespace_items` of a package into one lookup structure, the top-level
// cross-file query the TIR layer resolves names with.

// port: baml_compiler2_hir/src/package.rs::NamespaceShadow @ d9be6853b
// A namespace name that shadows a root-level declaration.
class NamespaceShadow {
    // The namespace name that shadows (e.g. "foo" from `ns_foo/`).
    ns_name: string,
    // The full namespace path (e.g. `["foo"]` or `["foo", "bar"]`).
    ns_path: string[],
    // The root-level definition being shadowed.
    shadowed_def: Definition,

    // port: baml_compiler2_hir/src/package.rs::NamespaceShadow::to_diagnostic @ d9be6853b
    // The error, at the item's name.
    function to_diagnostic(self, db: Db) -> ValidationDiagnostic throws never {
        let def = self.shadowed_def;
        let file = definition_file(def, db);
        let file_id = file;

        // Look up the name span from file contributions.
        let contribs = file_symbol_contributions(db, file);
        let name_span = contribs.types.concat(contribs.values).find((pair) -> {
            pair.1.definition == def
        })?.1.name_span;

        let kind = definition_source_kind_name(def, db);
        let message = `\`${self.ns_name}\` is both a root-level ${kind} and the namespace \`ns_${self.ns_name}/\``;

        let diag = ValidationDiagnostic.error(root.diagnostics.NAMESPACE_NAME_COLLISION, message);

        if (name_span != null) {
            diag
                = diag.with_primary(
                    root.base.Span { file_id: file_id, range: name_span },
                    `rename this ${kind} or the namespace: \`${self.ns_name}.X\` reads a member of the ${kind}, \`root.${self.ns_name}.X\` an item of the namespace`,
                );
        }

        diag.with_phase(DiagnosticPhase.Validation)
    }
}

// ── Roots as packages ──────────────────────────────────────────────────────

// port: baml_compiler2_hir/src/package.rs::workspace_roots @ d9be6853b
// The `Workspace`-kind source roots, in table order.
function workspace_roots(db: Db) -> int[] throws never {
    db.memo.workspace_roots.get(0, () -> {
        db.root_order.filter((root_id) -> {
            db.source_root(root_id).kind == root.base.SourceRootKind.Workspace
        })
    })
}

// port: baml_compiler2_hir/src/package.rs::visible_packages @ d9be6853b
// The packages `viewer` can see: itself, then its dependency closure in
// deterministic order. Every "which impls (or items) exist?" question is asked
// from a package and answered over exactly this set.
function visible_packages(db: Db, viewer: int) -> int[] throws never {
    db.memo.visible_packages.get(viewer, () -> {
        [viewer].concat(package_dependency_closure(db, viewer))
    })
}

// port: baml_compiler2_hir/src/package.rs::world_roots @ d9be6853b
// The roots emitted into `root_id`'s program, `root_id` and its dependency
// closure, in source-root table order (`Stdlib < Dependency < Workspace <
// Dynamic`), so the stdlib keeps its user-independent prefix of every index
// space.
function world_roots(db: Db, root_id: int) -> int[] throws never {
    db.memo.world_roots.get(root_id, () -> {
        let visible = visible_packages(db, root_id);
        db.root_order.filter((candidate) -> {
            visible.includes(candidate)
        })
    })
}

// port: baml_compiler2_hir/src/package.rs::world_files @ d9be6853b
// Every file of `world_roots`, root by root in table order, each root's files
// in its own order: the file set a program built for `root_id` is emitted from.
function world_files(db: Db, root_id: int) -> int[] throws never {
    db.memo.world_files.get(root_id, () -> {
        world_roots(db, root_id).flat_map((world_root) -> {
            db.source_root(world_root).files
        })
    })
}

// port: baml_compiler2_hir/src/package.rs::dependency_named @ d9be6853b
// The dependency edge of `root_id` named `name`, if it has one: the ONE place
// an edge name becomes the package it reaches.
function dependency_named(db: Db, root_id: int, name: string) -> int? throws never {
    db.source_root(root_id)
        .dependencies.find((dependency) -> {
            dependency.name == name
        })
        ?.root
}

// port: baml_compiler2_hir/src/package.rs::edge_table @ d9be6853b
// A package's edge table: every package it reaches, by the name it reaches it
// under. Its manifest edges, then the language packages under their fixed
// names (reachable from every package, their own siblings included). A
// non-stdlib root already carries the prelude as explicit edges, so for it the
// fixed names add nothing.
function edge_table(db: Db, root_id: int) -> (string, int)[] throws never {
    db.memo.edge_table.get(root_id, () -> {
        let edges: (string, int)[] = db.source_root(root_id).dependencies.map((dependency) -> {
            (dependency.name, dependency.root)
        });
        let lang = lang_roots(db);
        for (let package in root.base.LANG_PACKAGES) {
            let lang_root = lang.get(package);
            if (lang_root == null) {
                continue;
            }
            let name = root.base.lang_package_manifest_name(package);
            if (
                lang_root != root_id
                    && !edges.some((edge) -> {
                        edge.0 == name
                    })
            ) {
                edges.push((name, lang_root));
            }
        }
        edges
    })
}

// port: baml_compiler2_hir/src/package.rs::ROOT_SEGMENT @ d9be6853b
// The spelling of the edge from a package to itself: Rust's `crate`.
const ROOT_SEGMENT: string = "root";

// port: baml_compiler2_hir/src/package.rs::PathHead @ d9be6853b
// How the first segment of a path is read, decided once here and handed to
// every consumer. For a WRITTEN path: a binding in scope (the caller's), an
// item of the writer's own namespace, then `root` or an edge of the writer's
// package. A compiler-written path is read by identity (`PathHeadLang`).
type PathHead = PathHeadPackage | PathHeadLang | PathHeadPlain;

// `root`, or a dependency edge of the reading package: the package (root id)
// it reaches. The rest is `<namespaces>.<item>` inside it, then members.
class PathHeadPackage {
    value: int,
}

// A language package the COMPILER named, by identity: read like `Package`,
// except that no name in any scope shadows it (rustc's `$crate`).
class PathHeadLang {
    value: int,
}

// A plain name of the surrounding scope: an item of the file's own
// namespace, or a name only a lexical scope declares. The rest of the path
// are members of what it names.
class PathHeadPlain {
}

// port: baml_compiler2_hir/src/package.rs::path_package @ d9be6853b
// The package `first` names when it heads a qualified path written in `own`:
// `root` is `own` itself, any other name is `own`'s edge of that name. A
// package's own declared name is NOT among its edges. Stdlib roots also reach
// their sibling language packages through the implicit edges of `edge_table`.
function path_package(db: Db, own: int, first: string) -> int? throws never {
    if (first == ROOT_SEGMENT) {
        return own;
    }
    let named = dependency_named(db, own, first);
    if (named != null) {
        return named;
    }
    // Language packages may use each other's public types without a cyclic
    // manifest dependency (trace.Span uses baml.errors.Context, while baml
    // already depends on trace); user packages resolve written names only
    // through their declared and prelude edges.
    if (db.source_root(own).kind != root.base.SourceRootKind.Stdlib) {
        return null;
    }
    edge_table(db, own).find((edge) -> {
        edge.0 == first
    })?.1
}

// port: baml_compiler2_hir/src/package.rs::path_head @ d9be6853b
// The `PathHead` of `segments`, written in the namespace `namespace` of
// `own`, once no binding has claimed the first segment. An item of that
// namespace claims it next; only then is it read as `root` or an edge. A
// package segment is a qualifier, so a lone name is never a package.
function path_head(
    db: Db,
    own: int,
    namespace: string[],
    segments: string[],
) -> PathHead throws never {
    match (segments) {
        // `root` first: nothing may be named `root` (E0176), so a refused item
        // of that name cannot take every `root.X` of its namespace down with it.
        [let first, _, ..] if first == ROOT_SEGMENT => PathHeadPackage { value: own },
        [let first, _, ..] => {
            if (namespace_declares(db, own, namespace, first)) {
                return PathHeadPlain {};
            }
            match (path_package(db, own, first)) {
                let package: int => PathHeadPackage { value: package },
                null => PathHeadPlain {},
            }
        },
        _ => PathHeadPlain {},
    }
}

// port: baml_compiler2_hir/src/package.rs::compiler_path_head @ d9be6853b
// The `PathHead` of a path the COMPILER wrote, never looked up in any scope:
// a language package's fixed name is read by identity from where the stdlib
// is installed (a plain name when it is not installed); any other first
// segment is an item of the writer's own namespace.
function compiler_path_head(db: Db, segments: string[]) -> PathHead throws never {
    match (segments) {
        [let first, _, ..] => {
            let package = root.base.lang_package_from_manifest_name(first)
                ?? return PathHeadPlain {};
            match (lang_roots(db).get(package)) {
                let lang_root: int => PathHeadLang { value: lang_root },
                null => PathHeadPlain {},
            }
        },
        [_] => PathHeadPlain {},
        _ => baml.sys.panic("a compiler-written path names an item"),
    }
}

// port: baml_compiler2_hir/src/package.rs::path_head_for @ d9be6853b
// The `PathHead` of `segments` as `origin` says it was written.
function path_head_for(
    db: Db,
    own: int,
    namespace: string[],
    origin: root.base.PathOrigin,
    segments: string[],
) -> PathHead throws never {
    match (origin) {
        root.base.PathOrigin.Written => path_head(db, own, namespace, segments),
        root.base.PathOrigin.Compiler => compiler_path_head(db, segments),
    }
}

// port: baml_compiler2_hir/src/package.rs::lang_roots @ d9be6853b
// Where the language packages are installed in this database. Rust reads an
// optional input and defaults to none installed; the Db holds the table
// itself (empty until `install_stdlib`).
function lang_roots(db: Db) -> root.base.LangRoots throws never {
    db.lang_roots
}

// port: baml_compiler2_hir/src/package.rs::package_dependency_closure @ d9be6853b
// The full transitive dependency closure of `root_id` (excluding itself), in
// deterministic breadth-first order with duplicates removed. Cycle-safe,
// though the dependency graph is a DAG by construction.
function package_dependency_closure(db: Db, root_id: int) -> int[] throws never {
    db.memo.package_dependency_closure.get(root_id, () -> {
        let seen: map<int, bool> = {};
        let order: int[] = [];
        let queue = db.source_root(root_id).dependencies.map((dependency) -> {
            dependency.root
        });
        while let dep: int = queue.shift() {
            if (dep == root_id || seen.has(dep)) {
                continue;
            }
            seen[dep] = true;
            order.push(dep);
            root.base.extend(
                queue,
                db.source_root(dep).dependencies.map((dependency) -> {
                    dependency.root
                }),
            );
        }
        order
    })
}

// port: baml_compiler2_hir/src/package.rs::is_served_from_interface @ d9be6853b
// Whether `root_id` is served from its serialized compiler interface rather
// than from source (a runtime mount, or a precompiled stdlib package).
// deviation: `SourceRoot` has no `interface` input here (the BAML compiler
// mounts no package interfaces), so no root is.
function is_served_from_interface(db: Db, root_id: int) -> bool throws never {
    false
}

// port: baml_compiler2_hir/src/package.rs::is_precompiled_stdlib @ d9be6853b
// Whether `root_id` is a compiler-built stdlib package served from its
// interface.
function is_precompiled_stdlib(db: Db, root_id: int) -> bool throws never {
    db.source_root(root_id).kind == root.base.SourceRootKind.Stdlib
        && is_served_from_interface(db, root_id)
}

// ── Package items ──────────────────────────────────────────────────────────

// port: baml_compiler2_hir/src/package.rs::PackageItemsExtra @ d9be6853b
// Rare data for `PackageItems`: present only when a conflict or shadow exists.
class PackageItemsExtra {
    conflicts: NameConflict[],
    shadows: NamespaceShadow[],
}

// port: baml_compiler2_hir/src/package.rs::PackageItems @ d9be6853b
// All items across all namespaces within a package.
class PackageItems {
    // The package these items belong to: the scope in which they, and any
    // impls resolving their members, are visible.
    root_id: int,
    // Namespace path -> items within that namespace, in discovery order
    // (Rust's `IndexMap<Vec<Name>, _>`: arrays are not map keys).
    namespaces: (string[], NamespaceItems)[],
    // Conflicts and other rare data; null when none exist.
    extra: PackageItemsExtra?,

    // port: baml_compiler2_hir/src/package.rs::PackageItems::conflicts @ d9be6853b
    function conflicts(self) -> NameConflict[] throws never {
        self.extra?.conflicts ?? []
    }

    // port: baml_compiler2_hir/src/package.rs::PackageItems::shadows @ d9be6853b
    function shadows(self) -> NamespaceShadow[] throws never {
        self.extra?.shadows ?? []
    }

    // `IndexMap::get` on `namespaces`: the items of the namespace `path`.
    function namespace(self, path: string[]) -> NamespaceItems? throws never {
        self.namespaces.find((entry) -> {
            entry.0 == path
        })?.1
    }

    // port: baml_compiler2_hir/src/package.rs::PackageItems::lookup_type @ d9be6853b
    // A type by explicit namespace path (`["llm"]`, or `[]` for root) and
    // unqualified item name.
    function lookup_type(self, namespace: string[], item: string) -> Definition? throws never {
        self.namespace(namespace)?.types.get(item)
    }

    // port: baml_compiler2_hir/src/package.rs::PackageItems::lookup_value @ d9be6853b
    // A value by explicit namespace path and unqualified item name.
    function lookup_value(self, namespace: string[], item: string) -> Definition? throws never {
        self.namespace(namespace)?.values.get(item)
    }
}

// port: baml_compiler2_hir/src/package.rs::package_items @ d9be6853b
// Merges all `namespace_items` within a package: discovers the package's
// namespace paths from its own files (in first-seen order, so short-name
// consumers pick deterministically), then asks `namespace_items` for each.
function package_items(db: Db, root_id: int) -> PackageItems throws never {
    db.memo.package_items.get(root_id, () -> {
        let ns_paths: string[][] = [];
        for (let file in db.source_root(root_id).files) {
            let ns_path = file_package(db, file).namespace_path;
            if (!ns_paths.includes(ns_path)) {
                ns_paths.push(ns_path);
            }
        }

        let namespaces: (string[], NamespaceItems)[] = [];
        let all_conflicts: NameConflict[] = [];
        for (let ns_path in ns_paths) {
            let items = namespace_items(db, db.namespaces.intern(root_id, ns_path));
            root.base.extend(all_conflicts, items.conflicts());
            namespaces.push((ns_path, items));
        }

        let shadows = namespace_shadows(namespaces);
        shadows.sort_by((a, b) -> {
            a.ns_name.cmp(b.ns_name)
        });

        all_conflicts.sort_by((a, b) -> {
            a.name.cmp(b.name)
        });

        let extra = if (all_conflicts.length() == 0 && shadows.length() == 0) {
            null
        } else {
            PackageItemsExtra { conflicts: all_conflicts, shadows: shadows }
        };

        PackageItems { root_id: root_id, namespaces: namespaces, extra: extra }
    })
}

// `package_items`' shadow detection: every namespace whose first segment
// names a root-level declaration.
function namespace_shadows(
    namespaces: (string[], NamespaceItems)[],
) -> NamespaceShadow[] throws never {
    let root_ns = namespaces.find((entry) -> {
        entry.0.length() == 0
    })?.1
        ?? return [];
    namespaces.filter_map((entry) -> {
        let ns_path = entry.0;
        let first_segment = ns_path.at(0)
            ?? return null;
        let def = root_ns.types.get(first_segment) ?? root_ns.values.get(first_segment)
            ?? return null;
        NamespaceShadow { ns_name: first_segment, ns_path: ns_path, shadowed_def: def }
    })
}

// ── Dependency tables ──────────────────────────────────────────────────────

// port: baml_compiler2_hir/src/package.rs::edge_path @ d9be6853b
// The shortest edge path from `owner` to `target`, as (parent, edge name,
// child) hops in order: breadth-first over the edge tables, so the located
// root is always the nearest one. Null when no edge path reaches `target`.
function edge_path(db: Db, owner: int, target: int) -> (int, string, int)[]? throws never {
    let parents: map<int, (int, string)> = {};
    let queue = [owner];
    while let current: int = queue.shift() {
        if (current == target) {
            break;
        }
        for (let edge in edge_table(db, current)) {
            let edge_root = edge.1;
            if (edge_root == owner || parents.has(edge_root)) {
                continue;
            }
            parents[edge_root] = (current, edge.0);
            queue.push(edge_root);
        }
    }
    let hops: (int, string, int)[] = [];
    let child = target;
    while let parent: (int, string) = parents.get(child) {
        hops.push((parent.0, parent.1, child));
        child = parent.0;
    }
    if (child != owner) {
        return null;
    }
    hops.reverse()
}

// port: baml_compiler2_hir/src/package.rs::edge_spelling @ d9be6853b
// `target` as `owner` locates it: the edge names of the shortest edge path,
// empty for `owner` itself. Panics when no edge path reaches `target` (the
// same internal invariant as `DependencyTable.slot`).
function edge_spelling(db: Db, owner: int, target: int) -> root.types.EdgePath throws never {
    let path = edge_path(db, owner, target) ?? baml.sys.panic(unreachable_package_message(db, owner, target));
    root.types.EdgePath {
        value: path.map((hop) -> {
            hop.1
        }),
    }
}

// port: baml_compiler2_hir/src/package.rs::edge_target @ d9be6853b
// The package `path` locates from `owner`: each edge followed through the
// edge table of the package it leaves (the inverse of `edge_spelling`). Null
// when a hop names an edge the package it leaves does not have.
function edge_target(db: Db, owner: int, path: root.types.EdgePath) -> int? throws never {
    let current = owner;
    for (let edge in path.value) {
        current
            = edge_table(db, current).find((entry) -> {
                entry.0 == edge
            })?.1
                ?? return null;
    }
    current
}

// port: baml_compiler2_hir/src/package.rs::located_head @ d9be6853b
// A compile-time head as `owner` locates it: its declaring package by edge
// path. Panics as `edge_spelling` does.
function located_head(
    db: Db,
    owner: int,
    decl: root.types.DeclName,
) -> root.types.PathName throws never {
    root.types.PathName {
        pkg: edge_spelling(db, owner, decl.pkg),
        namespace: decl.namespace,
        name: decl.name,
    }
}

// port: baml_compiler2_hir/src/package.rs::resolve_located @ d9be6853b
// The compile-time head a located name denotes from `owner` (the inverse of
// `located_head`). Null when its path leaves `owner`'s edges.
function resolve_located(
    db: Db,
    owner: int,
    name: root.types.PathName,
) -> root.types.DeclName? throws never {
    let declaring = edge_target(db, owner, name.pkg)
        ?? return null;
    root.types.DeclName { pkg: declaring, namespace: name.namespace, name: name.name }
}

// port: baml_compiler2_hir/src/package.rs::DependencyTable @ d9be6853b
// An artifact's dependency table under construction: one slot per package
// root the artifact's owner names, located through the owner's edge table
// directly or through an earlier slot's.
class DependencyTable {
    // Rust's `owner`; renamed because it clashes with the `owner()` method.
    owner_root: int,
    // Slot `k + 1`: the root it binds, and the hop (via slot, edge) that
    // located it.
    entries: (int, root.types.DepSlot, string)[],

    // port: baml_compiler2_hir/src/package.rs::DependencyTable::new @ d9be6853b
    function new(owner: int) -> DependencyTable throws never {
        DependencyTable { owner_root: owner, entries: [] }
    }

    // port: baml_compiler2_hir/src/package.rs::DependencyTable::owner @ d9be6853b
    // The package the table belongs to: slot `DEP_SLOT_SELF`.
    function owner(self) -> int throws never {
        self.owner_root
    }

    // port: baml_compiler2_hir/src/package.rs::DependencyTable::slot @ d9be6853b
    // The slot `root_id` is (or becomes) bound to. A root the owner has no
    // direct edge to is located through the nearest package that does, the
    // path interned hop by hop. Panics when no edge path from the owner
    // reaches `root_id` (an internal invariant, not an input error).
    function slot(self, db: Db, root_id: int) -> root.types.DepSlot throws never {
        if (root_id == self.owner_root) {
            return root.types.DEP_SLOT_SELF;
        }
        let found = self.existing(root_id);
        if (found != null) {
            return found;
        }
        let path = edge_path(db, self.owner_root, root_id)
            ?? baml.sys.panic(unreachable_package_message(db, self.owner_root, root_id));
        for (let hop in path) {
            if (self.existing(hop.2) != null) {
                continue;
            }
            let via = if (hop.0 == self.owner_root) {
                root.types.DEP_SLOT_SELF
            } else {
                self.existing(hop.0)
                    ?? baml.sys.panic("a path's parent is interned before its child")
            };
            self.entries.push((hop.2, via, hop.1));
        }
        self.existing(root_id) ?? baml.sys.panic("the path ends at the root")
    }

    // port: baml_compiler2_hir/src/package.rs::DependencyTable::existing @ d9be6853b
    function existing(self, root_id: int) -> root.types.DepSlot? throws never {
        let index = self.entries.find_index((entry) -> {
            entry.0 == root_id
        })
            ?? return null;
        root.types.DepSlot.of_dependency_index(index)
    }

    // port: baml_compiler2_hir/src/package.rs::DependencyTable::root_of @ d9be6853b
    // The root bound to `slot`.
    function root_of(self, slot: root.types.DepSlot) -> int throws never {
        match (slot.dependency_index()) {
            null => self.owner_root,
            let index: int => self.entries[index].0,
        }
    }

    // port: baml_compiler2_hir/src/package.rs::DependencyTable::roots @ d9be6853b
    // The roots bound to slots `1..`, in slot order.
    function roots(self) -> int[] throws never {
        self.entries.map((entry) -> {
            entry.0
        })
    }

    // port: baml_compiler2_hir/src/package.rs::DependencyTable::locators @ d9be6853b
    // The table as an artifact carries it: a direct entry is `LocatorDirect`
    // with `digest(root)` (the interface payload the owner compiled against),
    // or `LocatorPrelude` for a language package (by identity, no payload); a
    // transitive entry is `LocatorTransitive`, covered by its parent's digest.
    function locators(
        self,
        db: Db,
        digest: (int) -> uint8array throws never,
    ) -> root.types.Locator[] throws never {
        let lang = lang_roots(db);
        self.entries.map((entry) -> {
            let (let entry_root, let via, let edge) = entry;
            if (!via.is_self()) {
                return root.types.LocatorTransitive { via: via, edge: edge };
            }
            match (lang.package_of(entry_root)) {
                let language: root.base.LangPackage => root.types.LocatorPrelude { value: language },
                null => root.types.LocatorDirect { edge: edge, digest: digest(entry_root) },
            }
        })
    }
}

// The panic `edge_spelling` and `DependencyTable.slot` share.
function unreachable_package_message(db: Db, owner: int, target: int) -> string throws never {
    `package \`${db.source_root(owner).path}\` names package \`${db.source_root(target).path}\`, which no edge path from it reaches`
}
