// port: baml_compiler2_hir/src/item_data/lets.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_data/lets.rs::LetData @ d9be6853b
// Span-free semantic data for a top-level `let` binding. The initializer is
// absent: it has its own query (`let_body`), so editing it cannot invalidate
// anything that depends only on the binding.
class LetData {
    name: string,
    origin: root.ast.LetOrigin,
    // The type-reference arena owned by this binding, scoped to the item.
    type_refs: TypeRefStore,
    // Root of the written `: T`. Null when unannotated, in which case the
    // binding's type is its initializer's.
    annotation: int?,
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/lets.rs::LetSourceMap @ d9be6853b
// Spans for a `Let`, parallel to `LetData`.
class LetSourceMap {
    // Full source span of the declaration.
    span: root.syntax.TextRange,
    // Span of just the binding's name.
    name_span: root.syntax.TextRange,
    // Spans for every node in `LetData.type_refs`.
    type_refs: TypeRefSourceMap,
}

// port: baml_compiler2_hir/src/item_data/lets.rs::let_data @ d9be6853b
// Semantic data for one `let` binding. Span-free.
function let_data(db: Db, binding: int) -> LetData throws never {
    db.memo.let_data.get(binding, () -> {
        lower_let(db, binding).0
    })
}

// port: baml_compiler2_hir/src/item_data/lets.rs::let_source_map @ d9be6853b
// Spans for one `let` binding, kept apart from `let_data`.
function let_source_map(db: Db, binding: int) -> LetSourceMap throws never {
    db.memo.let_source_map.get(binding, () -> {
        lower_let(db, binding).1
    })
}

// port: baml_compiler2_hir/src/item_data/lets.rs::lower @ d9be6853b
// deviation: named `lower_let` (see `lower_class`).
function lower_let(db: Db, binding: int) -> (LetData, LetSourceMap) throws never {
    let loc = db.let_locs.get(binding);
    let item_tree = file_item_tree(db, loc.file);
    let data = item_tree.lets[loc.id];

    let type_refs = TypeRefBuilder.new();
    let annotation = lower_type_expr_opt(type_refs, data.type_annotation);
    let (let store, let spans) = type_refs.finish();

    (
        LetData {
            name: data.name,
            origin: data.origin,
            type_refs: store,
            annotation: annotation,
            docstring: data.docstring,
        },
        LetSourceMap { span: data.span, name_span: data.name_span, type_refs: spans },
    )
}
