// port: baml_compiler2_hir/src/item_tree/interfaces.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_tree/interfaces.rs::InterfaceField @ d9be6853b
// An interface field stored in the `ItemTree`. An interface is a contract,
// not a data type, so its fields carry no attributes.
class InterfaceField {
    name: string,
    // Always present, as for `ClassField.type_expr`.
    type_expr: root.ast.TypeExpr,
    // Joined `///` doc-comment lines preceding this declaration.
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_tree/interfaces.rs::Interface @ d9be6853b
// An interface (BEP-044) stored in the `ItemTree`. ALL methods, default (with
// a body) and required (without), are `Function` entries in `methods`; a
// required method is a `Function` whose `body` is null.
class Interface {
    name: string,
    // Generic type parameters declared on the interface, each with its bounds.
    generic_params: GenericParam[],
    // Required interfaces from `requires I1, I2, ...`.
    requires_: root.ast.TypeExpr[],
    // Field signatures declared on the interface (no default values).
    fields: InterfaceField[],
    // Associated type declarations on the interface (BEP-057).
    associated_types: root.ast.AssociatedTypeDef[],
    // Every method, default and required alike, in declaration-list order
    // (defaults first, then required).
    methods: int[],
    docstring: string?,
    span: root.syntax.TextRange,
}

// port: baml_compiler2_hir/src/item_tree/interfaces.rs::ImplBlock @ d9be6853b
// An `implements` block stored in the `ItemTree`, in either spelling: an
// in-body block arrives with the class's generics and the class as its
// for-target. `origin` records how it was written and must NOT influence
// resolution, dispatch or coherence. Targets stay raw `TypeExpr`s; they are
// resolved lazily.
class ImplBlock {
    for_target: root.ast.TypeExpr,
    generics: GenericParam[],
    origin: root.ast.ImplOrigin,
    // The class whose body an in-body block was written in (its local id);
    // null for an out-of-body block.
    owner: int?,
    interface_target: root.ast.TypeExpr,
    field_links: InterfaceFieldLink[],
    associated_type_bindings: root.ast.AssociatedTypeBindingDef[],
    methods: int[],
    span: root.syntax.TextRange,
    // Leading `///` docstring; an in-body block carries none.
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_tree/interfaces.rs::InterfaceFieldLink @ d9be6853b
class InterfaceFieldLink {
    interface_field: string,
    class_field: string,
    span: root.syntax.TextRange,
    interface_field_span: root.syntax.TextRange,
    class_field_span: root.syntax.TextRange,

    // port: baml_compiler2_hir/src/item_tree/interfaces.rs::InterfaceFieldLink::from_ast @ d9be6853b
    function from_ast(link: root.ast.InterfaceFieldLinkDef) -> InterfaceFieldLink throws never {
        InterfaceFieldLink {
            interface_field: link.interface_field,
            class_field: link.class_field,
            span: link.span,
            interface_field_span: link.interface_field_span,
            class_field_span: link.class_field_span,
        }
    }
}
