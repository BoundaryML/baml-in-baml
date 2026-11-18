// port: baml_compiler2_hir/src/item_data/type_aliases.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_data/type_aliases.rs::TypeAliasData @ d9be6853b
// Span-free semantic data for a `type X = ...` declaration.
class TypeAliasData {
    name: string,
    // The type-reference arena owned by this alias, scoped to the item.
    type_refs: TypeRefStore,
    // Root of the aliased type. Null when the RHS was omitted or unparseable.
    value: int?,
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/type_aliases.rs::TypeAliasSourceMap @ d9be6853b
// Spans for a `TypeAlias`, parallel to `TypeAliasData`.
class TypeAliasSourceMap {
    // Full source span of the declaration.
    span: root.syntax.TextRange,
    // Span of the alias's name token.
    name_span: root.syntax.TextRange,
    // Spans for every node in `TypeAliasData.type_refs`.
    type_refs: TypeRefSourceMap,
}

// port: baml_compiler2_hir/src/item_data/type_aliases.rs::type_alias_data @ d9be6853b
// Semantic data for one type alias. Span-free.
function type_alias_data(db: Db, alias: int) -> TypeAliasData throws never {
    db.memo.type_alias_data.get(alias, () -> {
        lower_type_alias(db, alias).0
    })
}

// port: baml_compiler2_hir/src/item_data/type_aliases.rs::type_alias_source_map @ d9be6853b
// Spans for one type alias, kept apart from `type_alias_data`.
function type_alias_source_map(db: Db, alias: int) -> TypeAliasSourceMap throws never {
    db.memo.type_alias_source_map.get(alias, () -> {
        lower_type_alias(db, alias).1
    })
}

// port: baml_compiler2_hir/src/item_data/type_aliases.rs::lower @ d9be6853b
// deviation: named `lower_type_alias` (see `lower_class`).
function lower_type_alias(db: Db, alias: int) -> (TypeAliasData, TypeAliasSourceMap) throws never {
    let loc = db.type_alias_locs.get(alias);
    let item_tree = file_item_tree(db, loc.file);
    let item_source_map = file_item_tree_source_map(db, loc.file);
    let data = item_tree.type_aliases[loc.id];

    let type_refs = TypeRefBuilder.new();
    let value = lower_type_expr_opt(type_refs, data.type_expr);
    let (let store, let spans) = type_refs.finish();

    (
        TypeAliasData { name: data.name, type_refs: store, value: value, docstring: data.docstring },
        TypeAliasSourceMap {
            span: data.span,
            // Recorded at allocation (Rust: `unreachable!` when missing).
            name_span: item_source_map.type_alias_name_spans[loc.id],
            type_refs: spans,
        },
    )
}
