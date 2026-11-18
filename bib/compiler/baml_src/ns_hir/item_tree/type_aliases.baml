// port: baml_compiler2_hir/src/item_tree/type_aliases.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_tree/type_aliases.rs::TypeAlias @ d9be6853b
class TypeAlias {
    name: string,
    // The type expression on the RHS of the alias, if present.
    type_expr: root.ast.TypeExpr?,
    // Full source span of the type alias declaration.
    span: root.syntax.TextRange,
    docstring: string?,
}
