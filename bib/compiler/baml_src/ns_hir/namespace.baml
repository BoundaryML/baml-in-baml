// port: baml_compiler2_hir/src/namespace.rs @ d9be6853b
//
// Namespace-level cross-file symbol aggregation. `namespace_items` merges the
// `FileSymbolContributions` of every file of one (package, namespace path).
// Files merge in path order, so "first definition wins" is deterministic.
// Duplicate names are recorded as conflicts but still resolve, to the first.
//
// `NamespaceId` is an `int` interned by `db.namespaces` (`db.baml`).

// port: baml_compiler2_hir/src/namespace.rs::namespace_item_names @ d9be6853b
// The name of every item the files of `namespace_id` declare, read off their
// ASTs: a layer below the semantic index, so the index builder may ask while
// it runs. Sorted and deduplicated, for `namespace_declares`.
function namespace_item_names(db: Db, namespace_id: int) -> string[] throws never {
    db.memo.namespace_item_names.get(namespace_id, () -> {
        let key = db.namespaces.get(namespace_id);
        let names = namespace_files(db, key.package, key.path)
            .flat_map((file) -> {
                file_ast(db, file).items.filter_map((item) -> {
                    item_name(item)
                })
            })
            .sort_by((left, right) -> {
                left.cmp(right)
            });
        // `Vec::dedup`: drop each name equal to the one before it.
        names.reduce(
            (kept: string[], name: string) -> {
                if (kept.at(kept.length() - 1) != name) {
                    kept.push(name);
                }
                kept
            },
            [],
        )
    })
}

// The files of `package` in the namespace `ns_path`, in the package's order.
// Shared by `namespace_item_names` and `namespace_items`.
function namespace_files(db: Db, package: int, ns_path: string[]) -> int[] throws never {
    db.source_root(package).files.filter((file) -> {
        file_package(db, file).namespace_path == ns_path
    })
}

// port: baml_compiler2_hir/src/namespace.rs::item_name @ d9be6853b
// The name an item declares, if it declares one (an `implements` block
// declares none).
function item_name(item: root.ast.Item) -> string? throws never {
    match (item) {
        let f: root.ast.ItemFunction => f.value.name,
        let c: root.ast.ItemClass => c.value.name,
        let e: root.ast.ItemEnum => e.value.name,
        let ta: root.ast.ItemTypeAlias => ta.value.name,
        let l: root.ast.ItemLet => l.value.name,
        let i: root.ast.ItemInterface => i.value.name,
        root.ast.ItemImplementsFor => null,
    }
}

// port: baml_compiler2_hir/src/namespace.rs::namespace_declares @ d9be6853b
// Whether the namespace `namespace` of `package` declares an item named
// `name`, in either the type or the value namespace.
// deviation: a linear `includes` instead of Rust's binary search over the
// sorted names; same answer.
function namespace_declares(
    db: Db,
    package: int,
    namespace: string[],
    name: string,
) -> bool throws never {
    namespace_item_names(db, db.namespaces.intern(package, namespace)).includes(name)
}

// port: baml_compiler2_hir/src/namespace.rs::ConflictEntry @ d9be6853b
// One entry in a namespace conflict: the definition and its name span.
class ConflictEntry {
    definition: Definition,
    name_span: root.syntax.TextRange,
}

// port: baml_compiler2_hir/src/namespace.rs::NameConflict @ d9be6853b
// A name defined more than once within a namespace.
class NameConflict {
    name: string,
    // All definitions for this name, in alphabetical file order.
    entries: ConflictEntry[],

    // port: baml_compiler2_hir/src/namespace.rs::NameConflict::to_diagnostic @ d9be6853b
    // The duplicate-name error, with every definition annotated across files.
    function to_diagnostic(self, db: Db) -> ValidationDiagnostic throws never {
        let first = self.entries[0];
        let rest = self.entries.slice(1, self.entries.length());

        let first_kind = definition_source_kind(first.definition, db);
        let kinds_match = rest.every((e) -> {
            definition_source_kind(e.definition, db) == first_kind
        });
        let message = if (kinds_match) {
            `duplicate ${definition_kind_as_str(first_kind)} \`${self.name}\``
        } else {
            let kind_list = self.entries.map((e) -> {
                definition_source_kind_name(e.definition, db)
            });
            `name \`${self.name}\` defined ${self.entries.length()} times as: ${kind_list.join(", ")}`
        };

        let diag = ValidationDiagnostic.error(root.diagnostics.DUPLICATE_NAME, message);

        let first_file_id = definition_file(first.definition, db);
        diag
            = diag.with_secondary(
                root.base.Span { file_id: first_file_id, range: first.name_span },
                `first defined as ${definition_source_kind_name(first.definition, db)} here`,
            );

        for (let entry in rest) {
            let file_id = definition_file(entry.definition, db);
            diag
                = diag.with_primary(
                    root.base.Span { file_id: file_id, range: entry.name_span },
                    `duplicate ${definition_source_kind_name(entry.definition, db)} definition`,
                );
        }

        diag.with_phase(DiagnosticPhase.Validation)
    }
}

// port: baml_compiler2_hir/src/namespace.rs::NamespaceItemsExtra @ d9be6853b
// Rare data for `NamespaceItems`: present only when a conflict exists.
class NamespaceItemsExtra {
    conflicts: NameConflict[],
}

// port: baml_compiler2_hir/src/namespace.rs::NamespaceItems @ d9be6853b
// Merged symbol contributions for all files within a namespace.
class NamespaceItems {
    // Type-namespace items (classes, enums, type aliases). First definition
    // (alphabetically by file path) wins.
    types: map<string, Definition>,
    // Value-namespace items (functions, clients, etc.). First definition
    // (alphabetically by file path) wins.
    values: map<string, Definition>,
    // Conflicts and other rare data; null when no conflicts exist.
    extra: NamespaceItemsExtra?,

    // port: baml_compiler2_hir/src/namespace.rs::NamespaceItems::conflicts @ d9be6853b
    function conflicts(self) -> NameConflict[] throws never {
        self.extra?.conflicts ?? []
    }
}

// port: baml_compiler2_hir/src/namespace.rs::namespace_items @ d9be6853b
// Merges `file_symbol_contributions` for all files within a namespace, files
// sorted by path for a deterministic "first wins".
function namespace_items(db: Db, namespace_id: int) -> NamespaceItems throws never {
    db.memo.namespace_items.get(namespace_id, () -> {
        let key = db.namespaces.get(namespace_id);

        // The package's own files, sorted by path: edits to another package's
        // file set never touch this namespace.
        let matching_files = namespace_files(db, key.package, key.path).sort_by_key((file) -> {
            db.file(file).path
        });

        // Accumulate all contributions per name (preserving file order).
        let type_defs: map<string, Contribution[]> = {};
        let value_defs: map<string, Contribution[]> = {};
        for (let file in matching_files) {
            let contributions = file_symbol_contributions(db, file);
            group_contributions(type_defs, contributions.types);
            group_contributions(value_defs, contributions.values);
        }

        let types: map<string, Definition> = {};
        let values: map<string, Definition> = {};
        let conflicts = name_conflicts(db, type_defs, value_defs);

        for (let name in type_defs.keys()) {
            types[name] = type_defs[name][0].definition;
        }
        for (let name in value_defs.keys()) {
            values[name] = value_defs[name][0].definition;
        }

        // Sort conflicts by name for deterministic output.
        conflicts.sort_by((a, b) -> {
            a.name.cmp(b.name)
        });

        let extra = if (conflicts.length() == 0) {
            null
        } else {
            NamespaceItemsExtra { conflicts: conflicts }
        };

        NamespaceItems { types: types, values: values, extra: extra }
    })
}

// `IndexMap::entry(name).or_default().push(contrib)` for every pair.
function group_contributions(
    defs: map<string, Contribution[]>,
    contributions: (string, Contribution)[],
) -> void throws never {
    for (let pair in contributions) {
        if (!defs.has(pair.0)) {
            defs[pair.0] = [];
        }
        defs[pair.0].push(pair.1);
    }
}

// The conflicts of `namespace_items`, in first-spelling order. Lookup keeps
// type and value declarations apart, but BAML source does not: all
// namespace-level declarations of one spelling make one conflict, so mixed
// kinds don't also produce type-only or value-only diagnostics.
function name_conflicts(
    db: Db,
    type_defs: map<string, Contribution[]>,
    value_defs: map<string, Contribution[]>,
) -> NameConflict[] throws never {
    let declaration_names: map<string, bool> = {};
    for (let name in type_defs.keys().concat(value_defs.keys())) {
        declaration_names[name] = true;
    }
    declaration_names.keys().filter_map((name) -> {
        let entries = (type_defs.get(name) ?? []).concat(value_defs.get(name) ?? []);
        if (entries.length() < 2) {
            return null;
        }
        entries.sort_by((left, right) -> {
            contribution_order(db, left, right)
        });
        NameConflict {
            name: name,
            entries: entries.map((entry) -> {
                ConflictEntry { definition: entry.definition, name_span: entry.name_span }
            }),
        }
    })
}

// A conflict's entry order: file path, then name position, then kind name.
function contribution_order(
    db: Db,
    left: Contribution,
    right: Contribution,
) -> baml.ops.Ordering throws never {
    let by_path = db.file(definition_file(left.definition, db)).path.cmp(
        db.file(definition_file(right.definition, db)).path,
    );
    if (by_path != baml.ops.Ordering.Equal) {
        return by_path;
    }
    let by_start = left.name_span.start.cmp(right.name_span.start);
    if (by_start != baml.ops.Ordering.Equal) {
        return by_start;
    }
    definition_source_kind_name(left.definition, db).cmp(
        definition_source_kind_name(right.definition, db),
    )
}

// needs foundation: baml_compiler_diagnostics::diagnostic's `Diagnostic`
// builder as cross-file validation uses it: annotations carry a `Span` (file
// and range) and the diagnostic a phase. `ns_hir/diagnostic.baml`'s
// `Diagnostic` is the single-file, phase "hir" subset; both should become the
// one `Diagnostic` of `ns_diagnostics`. Until then this one is named
// `ValidationDiagnostic` (and `SpanAnnotation`) so the two do not collide.

// port: baml_compiler_diagnostics/src/diagnostic.rs::DiagnosticPhase @ d9be6853b
enum DiagnosticPhase {
    Parse,
    Hir,
    Validation,
    Type,
}

// port: baml_compiler_diagnostics/src/diagnostic.rs::Annotation @ d9be6853b
class SpanAnnotation {
    span: root.base.Span,
    message: string?,
    is_primary: bool,
}

// port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic @ d9be6853b
// Rust's `id` is its code here, as in `root.diagnostics`.
class ValidationDiagnostic {
    code: string,
    severity: root.base.Severity,
    message: string,
    annotations: SpanAnnotation[],
    phase: DiagnosticPhase,

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::error @ d9be6853b
    function error(code: string, message: string) -> ValidationDiagnostic throws never {
        ValidationDiagnostic {
            code: code,
            severity: root.base.Severity.Error,
            message: message,
            annotations: [],
            phase: DiagnosticPhase.Parse,
        }
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::with_phase @ d9be6853b
    function with_phase(self, phase: DiagnosticPhase) -> ValidationDiagnostic throws never {
        self.phase = phase;
        self
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::with_primary @ d9be6853b
    function with_primary(
        self,
        span: root.base.Span,
        message: string,
    ) -> ValidationDiagnostic throws never {
        self.annotations.push(SpanAnnotation { span: span, message: message, is_primary: true });
        self
    }

    // port: baml_compiler_diagnostics/src/diagnostic.rs::Diagnostic::with_secondary @ d9be6853b
    function with_secondary(
        self,
        span: root.base.Span,
        message: string,
    ) -> ValidationDiagnostic throws never {
        self.annotations.push(SpanAnnotation { span: span, message: message, is_primary: false });
        self
    }

    // The `reflect.Diagnostic`, as `Diagnostic.finish` builds it, with each
    // annotation in its own file: the first primary annotation is the span and
    // label and is left out of `annotations`.
    function finish(self, db: Db) -> reflect.Diagnostic throws never {
        let count = self.annotations.length();
        let primary_index = self.annotations.find_index((a) -> { a.is_primary }) ?? count;
        let primary = self.annotations.at(primary_index);
        let label = primary?.message;
        let message = if (label != null && label != self.message) {
            `${self.message}: ${label}`
        } else {
            self.message
        };
        let reflect_span = (span: root.base.Span) -> reflect.Span {
            reflect.Span { file: db.file(span.file_id).path, start: span.range.start, end: span.range.end }
        };
        let others = self.annotations.slice(0, primary_index).concat(self.annotations.slice(primary_index + 1, count));
        reflect.Diagnostic {
            code: self.code,
            span: if (primary != null) { reflect_span(primary.span) } else { null },
            message: message,
            severity: match (self.severity) {
                root.base.Severity.Error => "error",
                root.base.Severity.Warning => "warning",
                root.base.Severity.Info => "info",
            },
            phase: match (self.phase) {
                DiagnosticPhase.Parse => "parse",
                DiagnosticPhase.Hir => "hir",
                DiagnosticPhase.Validation => "validation",
                DiagnosticPhase.Type => "type",
            },
            headline: self.message,
            primary_label: label,
            message_highlights: [],
            annotations: others.map((a) -> {
                reflect.DiagnosticAnnotation {
                    span: reflect_span(a.span),
                    message: a.message,
                    message_highlights: [],
                    is_primary: a.is_primary,
                }
            }),
            related_info: [],
        }
    }
}
