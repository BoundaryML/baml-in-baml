// port: baml_compiler2_hir/src/item_data/common.rs @ d9be6853b
//
// Item-data pieces shared by more than one item kind. Mirrors
// `item_tree/common`.
//
// The `item_data` queries are the firewall over the `ItemTree`: each item is
// split into `*_data` (semantic, span-free, `TypeRef`s; what type checking
// reads) and `*_source_map` (spans only; what diagnostics and the IDE read).
// Each query takes a `*Loc` id and nothing else.

// port: baml_compiler2_hir/src/item_data/common.rs::GenericParamData @ d9be6853b
// A generic parameter paired with its `&`-separated bounds, lowered into the
// owning item's type-ref arena. The bound set is a conjunction.
class GenericParamData {
    name: string,
    bounds: int[],
}

// port: baml_compiler2_hir/src/item_data/common.rs::lower_generic_params @ d9be6853b
// Lower a declaration's generic parameters into `type_refs`. Bounds are
// allocated in declaration order, so ids stay a pure function of the item's
// shape.
function lower_generic_params(
    params: GenericParam[],
    type_refs: TypeRefBuilder,
) -> GenericParamData[] throws never {
    params.map((param) -> {
        GenericParamData {
            name: param.name,
            bounds: param.bounds.map((bound) -> {
                type_refs.lower(bound)
            }),
        }
    })
}

// port: baml_compiler2_hir/src/item_data/common.rs::FunctionParamData @ d9be6853b
class FunctionParamData {
    name: string,
    type_ref: int?,
    // Whether a default expression was supplied. The expression itself lives
    // in `function_parameter_defaults`.
    has_default: bool,
}

// port: baml_compiler2_hir/src/item_data/common.rs::FieldData @ d9be6853b
// A class field.
class FieldData {
    name: string,
    // Always present: a field written without a type recovers as
    // `TypeRefKindError`.
    type_ref: int,
    // The field's lowered `@` attributes.
    attrs: ClassFieldAttrs,
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/common.rs::InterfaceFieldData @ d9be6853b
// An interface field: a signature only, with no attributes.
class InterfaceFieldData {
    name: string,
    // Always present, as for `FieldData.type_ref`.
    type_ref: int,
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/common.rs::AssociatedTypeBindingData @ d9be6853b
class AssociatedTypeBindingData {
    name: string,
    type_ref: int?,
}

// port: baml_compiler2_hir/src/item_data/common.rs::AssociatedTypeBindingSourceMap @ d9be6853b
class AssociatedTypeBindingSourceMap {
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

// port: baml_compiler2_hir/src/item_data/common.rs::InterfaceFieldLinkData @ d9be6853b
class InterfaceFieldLinkData {
    interface_field: string,
    class_field: string,
}

// port: baml_compiler2_hir/src/item_data/common.rs::InterfaceFieldLinkSourceMap @ d9be6853b
class InterfaceFieldLinkSourceMap {
    span: root.syntax.TextRange,
    interface_field_span: root.syntax.TextRange,
    class_field_span: root.syntax.TextRange,
}
