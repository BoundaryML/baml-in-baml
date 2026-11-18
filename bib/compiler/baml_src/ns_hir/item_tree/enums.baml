// port: baml_compiler2_hir/src/item_tree/enums.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_tree/enums.rs::EnumVariant @ d9be6853b
// An enum variant stored in the `ItemTree`.
class EnumVariant {
    name: string,
    // The variant's lowered `@` attributes.
    attrs: EnumVariantAttrs,
    // Joined `///` doc-comment lines preceding this declaration.
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_tree/enums.rs::Enum @ d9be6853b
class Enum {
    name: string,
    // Variants of the enum, in declaration order.
    variants: EnumVariant[],
    // The enum's lowered `@@` attributes.
    attrs: EnumAttrs,
    // Joined `///` doc-comment lines preceding this declaration.
    docstring: string?,
    // Full source span of the enum declaration.
    span: root.syntax.TextRange,
}
