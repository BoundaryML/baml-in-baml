// port: baml_compiler2_hir/src/item_tree/classes.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_tree/classes.rs::ClassField @ d9be6853b
// A class field stored in the `ItemTree`.
class ClassField {
    name: string,
    // Always present: a field written without a type recovers as
    // `TypeExprKindError`, not as an absent type.
    type_expr: root.ast.TypeExpr,
    // The field's lowered `@` attributes.
    attrs: ClassFieldAttrs,
    // Joined `///` doc-comment lines preceding this declaration.
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_tree/classes.rs::Class @ d9be6853b
class Class {
    name: string,
    // Generic type parameters, each with its bounds. Empty for non-generic
    // classes.
    generic_params: GenericParam[],
    // Fields of the class, in declaration order.
    fields: ClassField[],
    // Methods defined at the class level (function ids in the same tree). A
    // method inside an `implements I { ... }` block is the impl's.
    methods: int[],
    // The class's lowered `@@` attributes.
    attrs: ClassAttrs,
    // Joined `///` doc-comment lines preceding this declaration.
    docstring: string?,
    // Full source span of the class declaration.
    span: root.syntax.TextRange,
}
