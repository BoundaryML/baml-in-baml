// port: baml_compiler2_hir/src/item_data/classes.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_data/classes.rs::ClassData @ d9be6853b
// Span-free semantic data for a `class` declaration. `methods` holds
// `FunctionLoc` ids, so a consumer can go straight to `function_data`.
class ClassData {
    name: string,
    // Generic type parameters, each with its conjunction of bounds.
    generic_params: GenericParamData[],
    // Every type reference in this class's signature (bounds and field
    // types), scoped to the item.
    type_refs: TypeRefStore,
    fields: FieldData[],
    methods: int[],
    // The class's lowered `@@` attributes.
    attrs: ClassAttrs,
    docstring: string?,
}

// port: baml_compiler2_hir/src/item_data/classes.rs::ClassSourceMap @ d9be6853b
// Spans for a `Class`, parallel to `ClassData`.
class ClassSourceMap {
    // Full source span of the declaration.
    span: root.syntax.TextRange,
    // Span of the class's name token.
    name_span: root.syntax.TextRange,
    // Spans for every node in `ClassData.type_refs`.
    type_refs: TypeRefSourceMap,
    // Name span per field, parallel to `ClassData.fields`.
    field_name_spans: root.syntax.TextRange[],
}

// port: baml_compiler2_hir/src/item_data/classes.rs::class_data @ d9be6853b
// Semantic data for one class. Span-free.
function class_data(db: Db, class_: int) -> ClassData throws never {
    db.memo.class_data.get(class_, () -> {
        lower_class(db, class_).0
    })
}

// port: baml_compiler2_hir/src/item_data/classes.rs::class_source_map @ d9be6853b
// Spans for one class, kept apart from `class_data`.
function class_source_map(db: Db, class_: int) -> ClassSourceMap throws never {
    db.memo.class_source_map.get(class_, () -> {
        lower_class(db, class_).1
    })
}

// port: baml_compiler2_hir/src/item_data/classes.rs::lower @ d9be6853b
// deviation: named `lower_class`; every Rust item-data module has its own
// private `lower`, and they share the `hir` namespace here.
// Both queries call this and keep one half. Type refs are allocated in a
// fixed order (bounds, then fields) so ids are a pure function of the
// class's shape.
function lower_class(db: Db, class_: int) -> (ClassData, ClassSourceMap) throws never {
    let loc = db.class_locs.get(class_);
    let item_tree = file_item_tree(db, loc.file);
    let item_source_map = file_item_tree_source_map(db, loc.file);
    let data = item_tree.classes[loc.id];

    let type_refs = TypeRefBuilder.new();
    let generic_params = lower_generic_params(data.generic_params, type_refs);
    let fields = data.fields.map((field) -> {
        FieldData {
            name: field.name,
            type_ref: type_refs.lower(field.type_expr),
            attrs: field.attrs,
            docstring: field.docstring,
        }
    });
    let (let store, let spans) = type_refs.finish();

    (
        ClassData {
            name: data.name,
            generic_params: generic_params,
            type_refs: store,
            fields: fields,
            methods: data.methods.map((method) -> {
                db.function_locs.intern(loc.file, method)
            }),
            attrs: data.attrs,
            docstring: data.docstring,
        },
        ClassSourceMap {
            span: data.span,
            // Recorded at allocation (Rust: `unreachable!` when missing).
            name_span: item_source_map.class_name_spans[loc.id],
            type_refs: spans,
            field_name_spans: item_source_map.class_field_spans.get(loc.id) ?? [],
        },
    )
}
