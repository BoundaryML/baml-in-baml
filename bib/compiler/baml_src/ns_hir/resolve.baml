// port: baml_compiler2_hir/src/resolve.rs @ d9be6853b
//
// On-demand name resolution. `resolve_name_at` walks the scope chain
// upward from an offset, checking each scope's bindings, then reads
// `package_items` for top-level names in the file's OWN namespace. Anything
// else is written qualified and resolves through `resolve_path_at`. There is
// no pre-built resolution map: each call re-derives the answer from the
// (cached) scope tree.

// port: baml_compiler2_hir/src/resolve.rs::ResolvedName @ d9be6853b
// What a name resolves to, innermost scope first: let-bindings of the scope,
// parameters of the enclosing function or lambda, the same in each ancestor
// scope, then package-level names of the file's own namespace.
type ResolvedName = ResolvedNameLocal
    | ResolvedNameItem
    | ResolvedNameBuiltin
    | ResolvedNameUnknown;

// Local variable (let binding or parameter).
class ResolvedNameLocal {
    name: string,
    definition_site: DefinitionSite?,
}

// A top-level item from the file's own `package_items`.
class ResolvedNameItem {
    value: Definition,
}

// An item from a dependency package (e.g. `baml`).
class ResolvedNameBuiltin {
    value: Definition,
}

// Could not resolve.
class ResolvedNameUnknown {
}

// port: baml_compiler2_hir/src/resolve.rs::resolve_name_at @ d9be6853b
// port: baml_compiler2_hir/src/resolve.rs::resolve_name_at_in_scope @ d9be6853b
// Resolve a bare `name` at `at_offset` in `file`, honoring local shadowing (a
// local wins over any item of the same name). `scope_name` disambiguates
// companion functions that share a span by requiring the scope name to match
// (Rust's `resolve_name_at_in_scope`; `resolve_name_at` passes none).
function resolve_name_at(
    db: Db,
    file: int,
    at_offset: int,
    name: string,
    scope_name: string? = null,
) -> ResolvedName throws never {
    let index = file_semantic_index(db, file);
    let scope_id = index.scope_at_offset(at_offset, scope_name);

    // Walk ancestor scopes from innermost to outermost.
    for (let ancestor_id in index.ancestor_scopes(scope_id)) {
        let scope = index.scopes[ancestor_id];

        // Class body names are not visible to methods or lambdas by bare name
        // (field access goes through member resolution).
        if (scope.kind == ScopeKind.Class && ancestor_id != scope_id) {
            continue;
        }

        // Let-bindings in this scope (latest first, for shadowing), then
        // parameters (for Function/Lambda scopes).
        let local = scope_locals(index, ancestor_id, at_offset).find((l) -> {
            l.0 == name
        });
        if (local != null) {
            return ResolvedNameLocal { name: name, definition_site: local.1 };
        }

        // At File/Package scope, resolve through the package items of the
        // file's OWN namespace only: everything outside it is written qualified,
        // with no outward walk to a parent namespace and no fall through into a
        // dependency (`resolve_path_at` resolves qualified names).
        if (scope.kind == ScopeKind.File || scope.kind == ScopeKind.Package) {
            let own_items = own_namespace(db, file);
            let def = own_items?.values.get(name) ?? own_items?.types.get(name);
            if (def != null) {
                return ResolvedNameItem { value: def };
            }
        }
    }

    ResolvedNameUnknown {}
}

// port: baml_compiler2_hir/src/resolve.rs::ScopeName @ d9be6853b
// One name that resolves at a position, with what it resolves to.
class ScopeName {
    name: string,
    kind: ScopeNameKind,
}

// port: baml_compiler2_hir/src/resolve.rs::ScopeNameKind @ d9be6853b
// What an enumerated name is. Local and Item mirror `ResolvedName`; a bare
// package name is not a value, it can only root a qualified path.
type ScopeNameKind = ScopeNameKindLocal | ScopeNameKindItem | ScopeNameKindPackage;

class ScopeNameKindLocal {
    definition_site: DefinitionSite?,
}

class ScopeNameKindItem {
    value: Definition,
}

class ScopeNameKindPackage {
}

// port: baml_compiler2_hir/src/resolve.rs::names_in_scope_at @ d9be6853b
// Every bare name that resolves at `at_offset`, innermost first: the
// enumeration counterpart of `resolve_name_at`, with the same walk and rules.
// The first spelling of a name wins, which is what shadowing means.
function names_in_scope_at(db: Db, file: int, at_offset: int) -> ScopeName[] throws never {
    let index = file_semantic_index(db, file);
    let scope_id = index.scope_at_offset(at_offset, null);
    let spelled = index.ancestor_scopes(scope_id).flat_map((ancestor_id) -> {
        let kind = index.scopes[ancestor_id].kind;
        if (kind == ScopeKind.Class && ancestor_id != scope_id) {
            return [];
        }
        let locals: ScopeName[] = scope_locals(index, ancestor_id, at_offset).map((local) -> {
            ScopeName { name: local.0, kind: ScopeNameKindLocal { definition_site: local.1 } }
        });
        if (kind == ScopeKind.File || kind == ScopeKind.Package) {
            locals.concat(own_scope_names(db, file))
        } else {
            locals
        }
    });
    // The first spelling of a name wins.
    spelled.reduce(
        (out: ScopeName[], entry: ScopeName) -> {
            if (
                !out.some((kept) -> {
                    kept.name == entry.name
                })
            ) {
                out.push(entry);
            }
            out
        },
        [],
    )
}

// What a File or Package scope adds to `names_in_scope_at`: the values, then
// the types, of the file's own namespace, then every dependency edge NAME (a
// dependency's items are written qualified).
function own_scope_names(db: Db, file: int) -> ScopeName[] throws never {
    let namespace = own_namespace(db, file);
    let items: map<string, Definition>[] = if (namespace != null) {
        [namespace.values, namespace.types]
    } else {
        []
    };
    let item_names = items.flat_map((defs) -> {
        defs.keys().map((name) -> {
            ScopeName { name: name, kind: ScopeNameKindItem { value: defs[name] } }
        })
    });
    let package_names = db.source_root(file_package(db, file).root_id).dependencies.map((dependency) -> {
        ScopeName { name: dependency.name, kind: ScopeNameKindPackage {} }
    });
    item_names.concat(package_names)
}

// port: baml_compiler2_hir/src/resolve.rs::TypeScopeName @ d9be6853b
// One TYPE name that resolves at a position.
class TypeScopeName {
    name: string,
    kind: TypeScopeNameKind,
}

// port: baml_compiler2_hir/src/resolve.rs::TypeScopeNameKind @ d9be6853b
type TypeScopeNameKind = TypeScopeNameKindItem
    | TypeScopeNameKindGenericParam
    | TypeScopeNameKindPackage;

// A type declaration in the file's own namespace.
class TypeScopeNameKindItem {
    value: Definition,
}

// A generic parameter declared by an enclosing item (`T`).
class TypeScopeNameKindGenericParam {
}

// A dependency package name, rooting a qualified type path.
class TypeScopeNameKindPackage {
}

// port: baml_compiler2_hir/src/resolve.rs::type_names_in_scope_at @ d9be6853b
// Every bare name that resolves AS A TYPE at `at_offset`: generic parameters
// of the enclosing items, the file's own namespace's types, and dependency
// package names. Builtin aliases (`int`, `string`) are the language's own
// table, enumerated by the completion layer.
function type_names_in_scope_at(db: Db, file: int, at_offset: int) -> TypeScopeName[] throws never {
    let index = file_semantic_index(db, file);
    let scope_id = index.scope_at_offset(at_offset, null);
    let spelled = index.ancestor_scopes(scope_id).flat_map((ancestor_id) -> {
        let kind = index.scopes[ancestor_id].kind;
        // Generic parameters come from the DECLARING items, exactly the frames
        // the resolver's lexical overlay reads.
        let generics: TypeScopeName[] = if (kind == ScopeKind.Function || kind == ScopeKind.Class) {
            scope_generic_param_names(db, index.scope_ids[ancestor_id]).map((name) -> {
                TypeScopeName { name: name, kind: TypeScopeNameKindGenericParam {} }
            })
        } else {
            []
        };
        if (kind == ScopeKind.File || kind == ScopeKind.Package) {
            generics.concat(own_type_scope_names(db, file))
        } else {
            generics
        }
    });
    // The first spelling of a name wins.
    spelled.reduce(
        (out: TypeScopeName[], entry: TypeScopeName) -> {
            if (
                !out.some((kept) -> {
                    kept.name == entry.name
                })
            ) {
                out.push(entry);
            }
            out
        },
        [],
    )
}

// What a File or Package scope adds to `type_names_in_scope_at`: the types
// of the file's own namespace, then every dependency edge name.
function own_type_scope_names(db: Db, file: int) -> TypeScopeName[] throws never {
    let types = own_namespace(db, file)?.types ?? {};
    let item_names = types.keys().map((name) -> {
        TypeScopeName { name: name, kind: TypeScopeNameKindItem { value: types[name] } }
    });
    let package_names = db.source_root(file_package(db, file).root_id).dependencies.map((dependency) -> {
        TypeScopeName { name: dependency.name, kind: TypeScopeNameKindPackage {} }
    });
    item_names.concat(package_names)
}

// The locals of scope `scope_id` visible at `at_offset`, in lookup order:
// its let-bindings latest first (an inner `let x` shadows an earlier one),
// then its parameters. Shared by `resolve_name_at` and
// `names_in_scope_at`.
function scope_locals(
    index: FileSemanticIndex,
    scope_id: int,
    at_offset: int,
) -> (string, DefinitionSite)[] throws never {
    let bindings = index.scope_bindings[scope_id];
    let lets: (string, DefinitionSite)[] = bindings.bindings
        .filter((binding) -> {
            index.binding_visible_at(binding, at_offset)
        })
        .map((binding) -> {
            (binding.name, binding.site)
        })
        .reverse();
    let params = bindings.params.map((param) -> (string, DefinitionSite) {
        (param.0, DefinitionSiteParameter { value: param.1 })
    });
    lets.concat(params)
}

// The items of the file's own namespace (its package's `package_items` at
// the file's namespace path), which is all a bare name reaches.
function own_namespace(db: Db, file: int) -> NamespaceItems? throws never {
    let pkg_info = file_package(db, file);
    package_items(db, pkg_info.root_id).namespace(pkg_info.namespace_path)
}

// `type_names_in_scope_at`'s generic parameters of the function or class
// that owns the scope `owner_scope_id`.
function scope_generic_param_names(db: Db, owner_scope_id: int) -> string[] throws never {
    match (scope_owner(db, owner_scope_id)) {
        let f: ScopeOwnerFunction => {
            function_data(db, f.value).generic_params.map((param) -> {
                param.name
            })
        },
        let c: ScopeOwnerClass => {
            class_data(db, c.value).generic_params.map((param) -> {
                param.name
            })
        },
        _ => [],
    }
}

// port: baml_compiler2_hir/src/resolve.rs::accessible_path_package @ d9be6853b
// The package a QUALIFIER names, with its items and the index of the first
// namespace segment. The reading is `path_head`'s: an item of the file's own
// namespace spelled like a package claims the head, `root` is this package,
// anything else is an edge of it. Null when no package is named.
function accessible_path_package(
    db: Db,
    file: int,
    segments: string[],
) -> (int, PackageItems, int)? throws never {
    let own = db.file(file).root;
    let first = segments.at(0)
        ?? return null;
    if (first != ROOT_SEGMENT) {
        let namespace = file_package(db, file).namespace_path;
        if (namespace_declares(db, own, namespace, first)) {
            return null;
        }
    }
    let package = path_package(db, own, first)
        ?? return null;
    (package, package_items(db, package), 1)
}

// port: baml_compiler2_hir/src/resolve.rs::resolve_path_at @ d9be6853b
// Resolve a path expression at a position. A single segment resolves as a
// bare name; otherwise the first segment is `root` or a package the file's
// package can spell, and the rest look up inside that package.
function resolve_path_at(
    db: Db,
    file: int,
    at_offset: int,
    segments: string[],
    scope_name: string?,
) -> ResolvedName throws never {
    if (segments.length() == 0) {
        return ResolvedNameUnknown {};
    }
    if (segments.length() == 1) {
        return resolve_name_at(db, file, at_offset, segments[0], scope_name = scope_name);
    }
    let (_, let pkg_items, let namespace_start) = accessible_path_package(db, file, segments)
        ?? return ResolvedNameUnknown {};
    let after_pkg = segments.slice(namespace_start, segments.length());
    let item = after_pkg.at(after_pkg.length() - 1)
        ?? baml.sys.panic("multi-segment path has elements after pkg prefix");
    let ns = after_pkg.slice(0, after_pkg.length() - 1);
    let def = pkg_items.lookup_value(ns, item) ?? pkg_items.lookup_type(ns, item);
    if (def != null) {
        return ResolvedNameBuiltin { value: def };
    }
    ResolvedNameUnknown {}
}

// port: baml_compiler2_hir/src/resolve.rs::resolve_namespace_prefix @ d9be6853b
// Resolve a path prefix that names a namespace: a package (`baml`, `root`)
// and/or a namespace within it. Whether the namespace lives outside the
// file's own package; null when the prefix names nothing.
function resolve_namespace_prefix(db: Db, file: int, segments: string[]) -> bool? throws never {
    let own = file_package(db, file).root_id;
    let (let package, let pkg_items, let namespace_start) = accessible_path_package(db, file, segments)
        ?? return null;
    let ns_prefix = segments.slice(namespace_start, segments.length());
    let is_namespace = ns_prefix.length() == 0
        || pkg_items.namespaces.some((entry) -> {
            starts_with(entry.0, ns_prefix)
        });
    if (!is_namespace) {
        return null;
    }
    package != own
}

// port: baml_compiler2_hir/src/resolve.rs::qualified_type_at @ d9be6853b
// The type a qualified path names (`baml.iter.Range`, `root.Point`); a bare
// name reads the file's own namespace, as `resolve_name_at` does.
function qualified_type_at(db: Db, file: int, segments: string[]) -> Definition? throws never {
    let item = segments.at(segments.length() - 1)
        ?? return null;
    let prefix = segments.slice(0, segments.length() - 1);
    if (prefix.length() == 0) {
        let pkg_info = file_package(db, file);
        return package_items(db, pkg_info.root_id).lookup_type(pkg_info.namespace_path, item);
    }
    let (_, let pkg_items, let namespace_start) = accessible_path_package(db, file, segments)
        ?? return null;
    let namespace = prefix.slice(
        if (namespace_start < prefix.length()) {
            namespace_start
        } else {
            prefix.length()
        },
        prefix.length(),
    );
    pkg_items.lookup_type(namespace, item)
}

// port: baml_compiler2_hir/src/resolve.rs::NamespaceMember @ d9be6853b
// One thing that can follow a package/namespace qualifier.
class NamespaceMember {
    name: string,
    kind: NamespaceMemberKind,
}

// port: baml_compiler2_hir/src/resolve.rs::NamespaceMemberKind @ d9be6853b
type NamespaceMemberKind = NamespaceMemberKindItem | NamespaceMemberKindNamespace;

class NamespaceMemberKindItem {
    value: Definition,
}

// A child namespace: `baml.` offers `http`, which qualifies further.
class NamespaceMemberKindNamespace {
}

// port: baml_compiler2_hir/src/resolve.rs::namespace_members_at @ d9be6853b
// Everything that can follow `<segments>.` when `segments` names a package or
// a namespace inside one. Null when the prefix names no reachable package or
// namespace (what tells `baml.`, a qualifier, from `some_local.`, a value).
function namespace_members_at(
    db: Db,
    file: int,
    segments: string[],
) -> NamespaceMember[]? throws never {
    let (_, let pkg_items, let namespace_start) = accessible_path_package(db, file, segments)
        ?? return null;
    let prefix = segments.slice(namespace_start, segments.length());
    let out: NamespaceMember[] = [];

    // Items declared in exactly this namespace.
    let namespace = pkg_items.namespace(prefix);
    if (namespace != null) {
        for (let name in namespace.values.keys()) {
            out.push(
                NamespaceMember {
                    name: name,
                    kind: NamespaceMemberKindItem { value: namespace.values[name] },
                },
            );
        }
        for (let name in namespace.types.keys()) {
            out.push(
                NamespaceMember {
                    name: name,
                    kind: NamespaceMemberKindItem { value: namespace.types[name] },
                },
            );
        }
    }

    // The next segment of every namespace that extends this prefix.
    for (let entry in pkg_items.namespaces) {
        let path = entry.0;
        if (path.length() > prefix.length() && starts_with(path, prefix)) {
            let child = path[prefix.length()];
            if (
                !out.some((member) -> {
                    member.name == child
                })
            ) {
                out.push(NamespaceMember { name: child, kind: NamespaceMemberKindNamespace {} });
            }
        }
    }

    if (out.length() == 0) {
        null
    } else {
        out
    }
}

// port: baml_compiler2_hir/src/resolve.rs::resolve_enum_variant @ d9be6853b
// Resolve `Enum.Variant`, the leaf of an enum-rooted type path: true only for
// a real variant, so a typo'd `Enum.Nope` stays a plain type.
function resolve_enum_variant(
    db: Db,
    file: int,
    at_offset: int,
    segments: string[],
) -> bool throws never {
    let variant = segments.at(segments.length() - 1)
        ?? return false;
    let prefix = segments.slice(0, segments.length() - 1);
    if (prefix.length() == 0) {
        return false;
    }
    let def = resolved_definition(resolve_path_at(db, file, at_offset, prefix, null))
        ?? return false;
    match (def) {
        let e: DefinitionEnum => {
            enum_data(db, e.value).variants.some((v) -> {
                v.name == variant
            })
        },
        _ => false,
    }
}

// port: baml_compiler2_hir/src/resolve.rs::resolve_field @ d9be6853b
// Resolve a field of the type named by `type_segments` (class or interface):
// true only when the field exists on that type.
function resolve_field(
    db: Db,
    file: int,
    at_offset: int,
    type_segments: string[],
    field: string,
) -> bool throws never {
    if (type_segments.length() == 0) {
        return false;
    }
    let def = resolved_definition(resolve_path_at(db, file, at_offset, type_segments, null))
        ?? return false;
    match (def) {
        let c: DefinitionClass => {
            class_data(db, c.value).fields.some((f) -> {
                f.name == field
            })
        },
        let i: DefinitionInterface => {
            interface_data(db, i.value).fields.some((f) -> {
                f.name == field
            })
        },
        _ => false,
    }
}

// needs foundation: the `ResolvedName::Item(def) | ResolvedName::Builtin(def)`
// or-pattern of `resolve_enum_variant` and `resolve_field` (BAML or-patterns
// cannot bind through two classes), and `<[T]>::starts_with`.

// The definition an `Item` or `Builtin` resolution names.
function resolved_definition(resolved: ResolvedName) -> Definition? throws never {
    match (resolved) {
        let item: ResolvedNameItem => item.value,
        let builtin: ResolvedNameBuiltin => builtin.value,
        _ => null,
    }
}

// port: `<[T]>::starts_with`. Whether `path` begins with `prefix`.
function starts_with(path: string[], prefix: string[]) -> bool throws never {
    path.length() >= prefix.length() && path.slice(0, prefix.length()) == prefix
}
