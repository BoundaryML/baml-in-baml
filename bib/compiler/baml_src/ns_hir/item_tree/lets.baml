// port: baml_compiler2_hir/src/item_tree/lets.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_tree/lets.rs::Let @ d9be6853b
// A top-level let binding stored in the `ItemTree`, with its optional
// initializer for body queries.
class Let {
    name: string,
    // The written `: T`, if any.
    type_annotation: root.ast.TypeExpr?,
    initializer: (root.ast.ExprBody, root.ast.AstSourceMap)?,
    origin: root.ast.LetOrigin,
    docstring: string?,
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}
