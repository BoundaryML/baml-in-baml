// port: baml_compiler2_hir/src/item_data/impls.rs @ d9be6853b
//
// deviation: `impl_enclosing_class` (a one-line forward) is not ported; call
// `impl_class` directly.

// port: baml_compiler2_hir/src/item_data/impls.rs::ImplBlockData @ d9be6853b
// Span-free semantic data for one `implements` block, in either spelling.
// `origin` records how it was written and must NOT influence resolution,
// dispatch or coherence.
class ImplBlockData {
    for_target: int,
    generics: GenericParamData[],
    origin: root.ast.ImplOrigin,
    // Every type reference in this block's header: the for-target, its
    // generic bounds, the interface target, and associated-type bindings.
    type_refs: TypeRefStore,
    interface_target: int,
    field_links: InterfaceFieldLinkData[],
    associated_type_bindings: AssociatedTypeBindingData[],
    methods: int[],
    // Leading `///` docstring: populated for free `implements ... for ...`
    // blocks; in-body blocks carry none today.
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/impls.rs::ImplBlockSourceMap @ d9be6853b
// Spans for an `ImplBlock`, parallel to `ImplBlockData`.
class ImplBlockSourceMap {
    // Full source span of the block.
    span: root.syntax.TextRange,
    // Spans for every node in `ImplBlockData.type_refs`.
    type_refs: TypeRefSourceMap,
    // Parallel to `ImplBlockData.field_links`.
    field_links: InterfaceFieldLinkSourceMap[],
    // Parallel to `ImplBlockData.associated_type_bindings`.
    associated_type_bindings: AssociatedTypeBindingSourceMap[],
}

// port: baml_compiler2_hir/src/item_data/impls.rs::impl_block_data @ d9be6853b
// Semantic data for one `implements` block. Span-free.
function impl_block_data(db: Db, block: int) -> ImplBlockData throws never {
    db.memo.impl_block_data.get(block, () -> {
        lower_impl_block(db, block).0
    })
}

// port: baml_compiler2_hir/src/item_data/impls.rs::impl_declared_generics @ d9be6853b
// The declared generic parameters scoping an impl block's methods, with the
// `TypeRefStore` their bound refs live in.
function impl_declared_generics(
    db: Db,
    block: int,
) -> (GenericParamData[], TypeRefStore) throws never {
    let data = impl_block_data(db, block);
    (data.generics, data.type_refs)
}

// port: baml_compiler2_hir/src/item_data/impls.rs::impl_block_source_map @ d9be6853b
// Spans for one `implements` block, kept apart from `impl_block_data`.
function impl_block_source_map(db: Db, block: int) -> ImplBlockSourceMap throws never {
    db.memo.impl_block_source_map.get(block, () -> {
        lower_impl_block(db, block).1
    })
}

// port: baml_compiler2_hir/src/item_data/impls.rs::lower @ d9be6853b
// deviation: named `lower_impl_block` (see `lower_class`).
// Type refs are allocated in a fixed order (for-target, its generic bounds,
// the interface target, then associated-type bindings).
function lower_impl_block(db: Db, block: int) -> (ImplBlockData, ImplBlockSourceMap) throws never {
    let loc = db.impl_locs.get(block);
    let item_tree = file_item_tree(db, loc.file);
    let data = item_tree.impls[loc.id];
    let type_refs = TypeRefBuilder.new();
    let for_target = type_refs.lower(data.for_target);
    let generics = lower_generic_params(data.generics, type_refs);
    let interface_target = type_refs.lower(data.interface_target);
    let associated_type_bindings = data.associated_type_bindings.map((binding) -> {
        AssociatedTypeBindingData {
            name: binding.name,
            type_ref: lower_type_expr_opt(type_refs, binding.type_expr),
        }
    });
    let (let store, let spans) = type_refs.finish();

    (
        ImplBlockData {
            for_target: for_target,
            generics: generics,
            origin: data.origin,
            type_refs: store,
            interface_target: interface_target,
            field_links: data.field_links.map((link) -> {
                InterfaceFieldLinkData {
                    interface_field: link.interface_field,
                    class_field: link.class_field,
                }
            }),
            associated_type_bindings: associated_type_bindings,
            methods: data.methods.map((method) -> {
                db.function_locs.intern(loc.file, method)
            }),
            docstring: data.docstring,
        },
        ImplBlockSourceMap {
            span: data.span,
            type_refs: spans,
            field_links: data.field_links.map((link) -> {
                InterfaceFieldLinkSourceMap {
                    span: link.span,
                    interface_field_span: link.interface_field_span,
                    class_field_span: link.class_field_span,
                }
            }),
            associated_type_bindings: data.associated_type_bindings.map((binding) -> {
                AssociatedTypeBindingSourceMap { span: binding.span, name_span: binding.name_span }
            }),
        },
    )
}

// needs foundation: `Option<&TypeExpr>::map(|te| type_refs.lower(te))`,
// written at every optional type in the item-data lowerings.
function lower_type_expr_opt(
    type_refs: TypeRefBuilder,
    te: root.ast.TypeExpr?,
) -> int? throws never {
    match (te) {
        let te: root.ast.TypeExpr => type_refs.lower(te),
        _ => null,
    }
}
