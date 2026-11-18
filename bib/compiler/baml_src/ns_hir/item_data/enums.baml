// port: baml_compiler2_hir/src/item_data/enums.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_data/enums.rs::EnumData @ d9be6853b
// Span-free semantic data for an `enum` declaration. Enums carry no type
// expressions, so there is no `TypeRefStore` here.
class EnumData {
    name: string,
    variants: EnumVariantData[],
    // The enum's lowered `@@` attributes.
    attrs: EnumAttrs,
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/enums.rs::EnumVariantData @ d9be6853b
class EnumVariantData {
    name: string,
    // The variant's lowered `@` attributes.
    attrs: EnumVariantAttrs,
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/enums.rs::EnumSourceMap @ d9be6853b
// Spans for an `Enum`, parallel to `EnumData`.
class EnumSourceMap {
    // Full source span of the declaration.
    span: root.syntax.TextRange,
    // Span of the enum's name token.
    name_span: root.syntax.TextRange,
    // Name span per variant, parallel to `EnumData.variants`.
    variant_name_spans: root.syntax.TextRange[],
}

// port: baml_compiler2_hir/src/item_data/enums.rs::enum_data @ d9be6853b
// Semantic data for one enum. Span-free.
function enum_data(db: Db, item: int) -> EnumData throws never {
    db.memo.enum_data.get(item, () -> {
        lower_enum(db, item).0
    })
}

// port: baml_compiler2_hir/src/item_data/enums.rs::enum_source_map @ d9be6853b
// Spans for one enum, kept apart from `enum_data`.
function enum_source_map(db: Db, item: int) -> EnumSourceMap throws never {
    db.memo.enum_source_map.get(item, () -> {
        lower_enum(db, item).1
    })
}

// port: baml_compiler2_hir/src/item_data/enums.rs::lower @ d9be6853b
// deviation: named `lower_enum` (see `lower_class`).
function lower_enum(db: Db, item: int) -> (EnumData, EnumSourceMap) throws never {
    let loc = db.enum_locs.get(item);
    let item_tree = file_item_tree(db, loc.file);
    let item_source_map = file_item_tree_source_map(db, loc.file);
    let data = item_tree.enums[loc.id];

    (
        EnumData {
            name: data.name,
            variants: data.variants.map((variant) -> {
                EnumVariantData {
                    name: variant.name,
                    attrs: variant.attrs,
                    docstring: variant.docstring,
                }
            }),
            attrs: data.attrs,
            docstring: data.docstring,
        },
        EnumSourceMap {
            span: data.span,
            // Recorded at allocation (Rust: `unreachable!` when missing).
            name_span: item_source_map.enum_name_spans[loc.id],
            variant_name_spans: item_source_map.enum_variant_spans.get(loc.id) ?? [],
        },
    )
}
