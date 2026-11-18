// port: baml_compiler2_hir/src/item_tree/source_map.rs @ d9be6853b

// port: baml_compiler2_hir/src/item_tree/source_map.rs::ItemTreeSourceMap @ d9be6853b
// Parallel source map for `ItemTree`: name spans kept out of the semantic
// tree, keyed by local item id.
class ItemTreeSourceMap {
    // `name_span` for each class.
    class_name_spans: map<int, root.syntax.TextRange>,
    // `name_span` for each class's fields, parallel to `Class.fields`.
    class_field_spans: map<int, root.syntax.TextRange[]>,
    // `name_span` for each enum.
    enum_name_spans: map<int, root.syntax.TextRange>,
    // `name_span` for each enum's variants, parallel to `Enum.variants`.
    enum_variant_spans: map<int, root.syntax.TextRange[]>,
    // `name_span` for each function.
    function_name_spans: map<int, root.syntax.TextRange>,
    // `name_span` for each interface.
    interface_name_spans: map<int, root.syntax.TextRange>,
    // `name_span` for each interface's fields, parallel to `Interface.fields`.
    interface_field_spans: map<int, root.syntax.TextRange[]>,
    // `name_span` for each interface's required methods, in declaration order.
    interface_method_spans: map<int, root.syntax.TextRange[]>,
    // `name_span` for each type alias.
    type_alias_name_spans: map<int, root.syntax.TextRange>,

    // port: baml_compiler2_hir/src/item_tree/source_map.rs::ItemTreeSourceMap::default @ d9be6853b
    function default_() -> ItemTreeSourceMap throws never {
        ItemTreeSourceMap {
            class_name_spans: {},
            class_field_spans: {},
            enum_name_spans: {},
            enum_variant_spans: {},
            function_name_spans: {},
            interface_name_spans: {},
            interface_field_spans: {},
            interface_method_spans: {},
            type_alias_name_spans: {},
        }
    }
}
