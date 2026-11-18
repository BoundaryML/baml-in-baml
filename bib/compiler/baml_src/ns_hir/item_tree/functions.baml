// port: baml_compiler2_hir/src/item_tree/functions.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_tree/functions.rs::Function @ d9be6853b
// Full function data stored in the `ItemTree`: params and return type for
// signature queries, the body for body queries (no CST re-parsing needed).
class Function {
    name: string,
    // Generic type parameters, each with its bounds. Empty for non-generic
    // functions.
    generic_params: GenericParam[],
    // Function parameters with optional type annotations and spans.
    params: FunctionParam[],
    // Function parameter default expression arena.
    defaults: root.ast.FunctionDefaults,
    // Return type with its source span.
    return_type: root.ast.TypeExpr?,
    // Throws contract type with its source span.
    throws_: root.ast.TypeExpr?,
    // Function body: either an expression or a builtin.
    body: root.ast.FunctionBodyDef?,
    // Declarative metadata, if declared with declarative syntax.
    declarative_meta: root.ast.DeclarativeMeta?,
    metadata: root.ast.FunctionMetadata,
    // Joined `///` doc-comment lines preceding this declaration.
    docstring: string?,
    // The `//#` title directly above the declaration, for the visualizer.
    header_title: string?,
    // BEP-049 §10: set when the fn def had a `//baml:tagged_string` marker.
    is_tagged_template_tag: bool,
    trace_hook: root.ast.TraceHookDirective?,
    // Full source span of the function.
    span: root.syntax.TextRange,
}

// port: baml_compiler2_hir/src/item_tree/functions.rs::MethodOwner @ d9be6853b
// The item a method belongs to (local item ids). Recorded by the
// `ItemTreeBuilder` at the same call that establishes membership
// (`set_class_methods` / `alloc_interface` / `alloc_impl`).
// deviation: named `ItemTreeMethodOwner`, since `item_data`'s `MethodOwner`
// (the `Loc` form) shares the `hir` namespace.
type ItemTreeMethodOwner = ItemTreeMethodOwnerClass
    | ItemTreeMethodOwnerInterface
    | ItemTreeMethodOwnerImpl;

// A class-LEVEL method only. A method inside an in-body `implements I { ... }`
// block belongs to its impl block.
class ItemTreeMethodOwnerClass {
    value: int,
}

// An interface default method.
class ItemTreeMethodOwnerInterface {
    value: int,
}

// A method of an `implements` block, in-class and out-of-body alike.
class ItemTreeMethodOwnerImpl {
    value: int,
}

// port: baml_compiler2_hir/src/item_tree/functions.rs::FunctionParam @ d9be6853b
// A function parameter entry in the `ItemTree`.
class FunctionParam {
    name: string,
    type_expr: root.ast.TypeExpr?,
    default: DefaultExprRef?,
    // The whole `name: Type`, which is what a diagnostic underlines.
    span: root.syntax.TextRange,
    // The NAME token alone: what go-to-definition lands on.
    name_span: root.syntax.TextRange,
}

// port: baml_compiler2_hir/src/item_tree/functions.rs::DefaultExprRef @ d9be6853b
class DefaultExprRef {
    function_: int,
    // The default's id in the function's `FunctionDefaults`.
    expr: int,
}
