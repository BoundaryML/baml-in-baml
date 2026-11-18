// port: baml_compiler2_hir/src/item_data/interfaces.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_data/interfaces.rs::InterfaceData @ d9be6853b
// Span-free semantic data for an `interface` declaration.
class InterfaceData {
    name: string,
    // Generic type parameters, each with its conjunction of bounds.
    generic_params: GenericParamData[],
    // Every type reference in this interface's signature: bounds, `requires`
    // targets, field types, associated-type bounds and defaults, and required
    // method signatures. Scoped to the item.
    type_refs: TypeRefStore,
    // Targets of `requires I1, I2, ...`.
    requires_: int[],
    // Field signatures. Interface fields cannot have default values.
    fields: InterfaceFieldData[],
    associated_types: AssociatedTypeData[],
    // EVERY method as a real function item, default and required alike (a
    // required method has no body). THE source of truth.
    methods: int[],
    // TIR-era VIEW: the bodied subset of `methods`. Derived, never authored.
    default_methods: int[],
    // TIR-era VIEW: bodyless methods re-projected into the legacy sig shape
    // (type refs in the interface's shared store). Derived, never authored.
    required_methods: InterfaceMethodSigData[],
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/interfaces.rs::AssociatedTypeData @ d9be6853b
class AssociatedTypeData {
    name: string,
    bound: int?,
    default: int?,
}

// port: baml_compiler2_hir/src/item_data/interfaces.rs::InterfaceMethodSigData @ d9be6853b
// A required (no-body) method signature on an interface.
class InterfaceMethodSigData {
    name: string,
    // Generic type parameters local to this method, each with its bounds.
    generic_params: GenericParamData[],
    params: FunctionParamData[],
    return_type: int?,
    throws_: int?,
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/interfaces.rs::InterfaceSourceMap @ d9be6853b
// Spans for an `Interface`, parallel to `InterfaceData`.
class InterfaceSourceMap {
    // Full source span of the declaration.
    span: root.syntax.TextRange,
    // Span of the interface's name token.
    name_span: root.syntax.TextRange,
    // Spans for every node in `InterfaceData.type_refs`.
    type_refs: TypeRefSourceMap,
    // Name span per field, parallel to `InterfaceData.fields`.
    field_name_spans: root.syntax.TextRange[],
    // Parallel to `InterfaceData.associated_types`.
    associated_type_spans: AssociatedTypeSourceMap[],
    // Parallel to `InterfaceData.required_methods`.
    required_method_spans: InterfaceMethodSigSourceMap[],
}

// port: baml_compiler2_hir/src/item_data/interfaces.rs::AssociatedTypeSourceMap @ d9be6853b
class AssociatedTypeSourceMap {
    span: root.syntax.TextRange,
    name_span: root.syntax.TextRange,
}

// port: baml_compiler2_hir/src/item_data/interfaces.rs::InterfaceMethodSigSourceMap @ d9be6853b
class InterfaceMethodSigSourceMap {
    span: root.syntax.TextRange,
    // Span of just the method's name.
    name_span: root.syntax.TextRange,
    // One span per parameter, parallel to `InterfaceMethodSigData.params`.
    param_spans: root.syntax.TextRange[],
}

// port: baml_compiler2_hir/src/item_data/interfaces.rs::interface_data @ d9be6853b
// Semantic data for one interface. Span-free.
function interface_data(db: Db, interface_: int) -> InterfaceData throws never {
    db.memo.interface_data.get(interface_, () -> {
        lower_interface(db, interface_).0
    })
}

// port: baml_compiler2_hir/src/item_data/interfaces.rs::interface_source_map @ d9be6853b
// Spans for one interface, kept apart from `interface_data`.
function interface_source_map(db: Db, interface_: int) -> InterfaceSourceMap throws never {
    db.memo.interface_source_map.get(interface_, () -> {
        lower_interface(db, interface_).1
    })
}

// port: baml_compiler2_hir/src/item_data/interfaces.rs::lower @ d9be6853b
// deviation: named `lower_interface` (see `lower_class`).
// Type refs are allocated in a fixed order (bounds, requires, fields,
// associated types, then required methods).
function lower_interface(
    db: Db,
    interface_: int,
) -> (InterfaceData, InterfaceSourceMap) throws never {
    let loc = db.interface_locs.get(interface_);
    let item_tree = file_item_tree(db, loc.file);
    let item_source_map = file_item_tree_source_map(db, loc.file);
    let data = item_tree.interfaces[loc.id];
    // Name spans for fields / required methods live in the item-tree source
    // map, like a class's field spans.
    let field_name_spans = item_source_map.interface_field_spans.get(loc.id) ?? [];
    let method_name_spans = item_source_map.interface_method_spans.get(loc.id);

    let type_refs = TypeRefBuilder.new();
    let generic_params = lower_generic_params(data.generic_params, type_refs);
    let requires_ = data.requires_.map((target) -> {
        type_refs.lower(target)
    });
    let fields = data.fields.map((field) -> {
        InterfaceFieldData {
            name: field.name,
            type_ref: type_refs.lower(field.type_expr),
            docstring: field.docstring,
        }
    });
    let associated_types = data.associated_types.map((assoc) -> {
        AssociatedTypeData {
            name: assoc.name,
            bound: lower_type_expr_opt(type_refs, assoc.bound),
            default: lower_type_expr_opt(type_refs, assoc.default),
        }
    });
    // The legacy required-sig view derives from the BODYLESS function items
    // (the single source of truth), re-lowered into the interface's store.
    let required_items = data.methods
        .filter((method) -> {
            item_tree.functions[method].body == null
        })
        .map((method) -> {
            item_tree.functions[method]
        });
    let required_methods = required_items.map((method) -> {
        InterfaceMethodSigData {
            name: method.name,
            generic_params: lower_generic_params(method.generic_params, type_refs),
            params: method.params.map((param) -> {
                FunctionParamData {
                    name: param.name,
                    type_ref: lower_type_expr_opt(type_refs, param.type_expr),
                    has_default: param.default != null,
                }
            }),
            return_type: lower_type_expr_opt(type_refs, method.return_type),
            throws_: lower_type_expr_opt(type_refs, method.throws_),
            docstring: method.docstring,
        }
    });
    let (let store, let spans) = type_refs.finish();

    (
        InterfaceData {
            name: data.name,
            generic_params: generic_params,
            type_refs: store,
            requires_: requires_,
            fields: fields,
            associated_types: associated_types,
            methods: data.methods.map((method) -> {
                db.function_locs.intern(loc.file, method)
            }),
            default_methods: data.methods
                .filter((method) -> {
                    item_tree.functions[method].body != null
                })
                .map((method) -> {
                    db.function_locs.intern(loc.file, method)
                }),
            required_methods: required_methods,
            docstring: data.docstring,
        },
        InterfaceSourceMap {
            span: data.span,
            // Recorded at allocation (Rust: `unreachable!` when missing).
            name_span: item_source_map.interface_name_spans[loc.id],
            type_refs: spans,
            field_name_spans: field_name_spans,
            associated_type_spans: data.associated_types.map((assoc) -> {
                AssociatedTypeSourceMap { span: assoc.span, name_span: assoc.name_span }
            }),
            required_method_spans: baml.Array.generate(required_items.length(), (i: int) -> InterfaceMethodSigSourceMap {
                let method = required_items[i];
                InterfaceMethodSigSourceMap {
                    span: method.span,
                    name_span: method_name_spans?.at(i) ?? root.syntax.TextRange.empty(0),
                    param_spans: method.params.map((param) -> {
                        param.span
                    }),
                }
            }),
        },
    )
}
