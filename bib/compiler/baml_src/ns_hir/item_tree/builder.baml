// port: baml_compiler2_hir/src/item_tree/builder.rs @ d9be6853b
//
// Construction-time state for the `ItemTree`. `next_index` is the collision
// counter used while handing out local item ids; it has no meaning once the
// tree is built. The builder also owns the `ItemTreeSourceMap`, so allocating
// an item and recording its spans is a single call.

// port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder @ d9be6853b
// Builds an `ItemTree` and its `ItemTreeSourceMap` together.
class ItemTreeBuilder {
    tree: ItemTree,
    source_map: ItemTreeSourceMap,
    // Collision tracker: kind -> hash -> next available index.
    next_index: map<ItemKind, map<int, int>>,

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::new @ d9be6853b
    function new() -> ItemTreeBuilder throws never {
        ItemTreeBuilder {
            tree: ItemTree.default_(),
            source_map: ItemTreeSourceMap.default_(),
            next_index: {},
        }
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::finish @ d9be6853b
    // The tree and its source map; `next_index` is dropped.
    function finish(self) -> (ItemTree, ItemTreeSourceMap) throws never {
        (self.tree, self.source_map)
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::alloc_id @ d9be6853b
    // Allocate a collision-resistant id for an item.
    function alloc_id(self, kind: ItemKind, name: string) -> int throws never {
        let h = hash_name(name);
        let by_hash = self.next_index.get_or_insert(kind, {});
        let index = by_hash.get(h) ?? 0;
        by_hash[h] = index + 1;
        local_item_id_new(h, index)
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::alloc_function @ d9be6853b
    // Allocate a function, recording its name span in the source map.
    function alloc_function(self, f: root.ast.FunctionDef) -> int throws never {
        let id = self.alloc_id(ItemKind.Function, f.name);
        self.source_map.function_name_spans[id] = f.name_span;
        let params = f.params.map((p) -> {
            FunctionParam {
                name: p.name,
                type_expr: p.type_expr,
                default: match (p.default) {
                    let expr: int => DefaultExprRef { function_: id, expr: expr },
                    _ => null,
                },
                span: p.span,
                name_span: p.name_span,
            }
        });
        self.tree.functions[id]
            = Function {
                name: f.name,
                generic_params: f.generic_params,
                params: params,
                defaults: f.defaults,
                return_type: f.return_type,
                throws_: f.throws_,
                body: f.body,
                declarative_meta: f.declarative_meta,
                metadata: f.metadata,
                docstring: f.docstring,
                header_title: f.header_title,
                is_tagged_template_tag: f.is_tagged_template_tag,
                trace_hook: f.trace_hook,
                span: f.span,
            };
        id
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::alloc_class @ d9be6853b
    // Allocate a class, recording its field name spans in the source map.
    // `attrs` and `field_attrs` (parallel to `c.fields`) are lowered by the
    // caller so their diagnostics land with the rest of the file's.
    function alloc_class(
        self,
        c: root.ast.ClassDef,
        attrs: ClassAttrs,
        field_attrs: ClassFieldAttrs[],
    ) -> int throws never {
        let id = self.alloc_id(ItemKind.Class, c.name);
        self.source_map.class_name_spans[id] = c.name_span;
        self.source_map.class_field_spans[id]
            = c.fields.map((f) -> {
                f.name_span
            });
        // Rust zips the two lists, which it asserts have one length.
        let fields = baml.Array.generate(c.fields.length(), (i: int) -> ClassField {
            let f = c.fields[i];
            ClassField {
                name: f.name,
                type_expr: f.type_expr,
                attrs: field_attrs[i],
                docstring: f.docstring,
            }
        });
        self.tree.classes[id]
            = Class {
                name: c.name,
                generic_params: c.generic_params,
                fields: fields,
                methods: [],
                attrs: attrs,
                docstring: c.docstring,
                span: c.span,
            };
        id
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::record_method_interface_target @ d9be6853b
    // Record the `implements I { ... }` block a method was declared under, so
    // `default.<name>()` calls in its body can resolve back to the interface.
    // Both halves are always written together.
    function record_method_interface_target(
        self,
        method: int,
        target: root.ast.TypeExpr,
        associated_type_bindings: root.ast.AssociatedTypeBindingDef[],
    ) -> void throws never {
        self.tree.method_to_iface_target[method] = target;
        self.tree.method_to_iface_associated_type_bindings[method] = associated_type_bindings;
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::set_class_methods @ d9be6853b
    // Attach method ids to an already-allocated class, recording each
    // method's owner in the same call.
    function set_class_methods(self, class_id: int, methods: int[]) -> void throws never {
        for (let method in methods) {
            self.record_method_owner(method, ItemTreeMethodOwnerClass { value: class_id });
        }
        if let class_: Class = self.tree.classes.get(class_id) {
            class_.methods = methods;
        }
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::record_method_owner @ d9be6853b
    // A method belongs to exactly one item (Rust debug-asserts it is not
    // recorded twice).
    function record_method_owner(
        self,
        method: int,
        owner: ItemTreeMethodOwner,
    ) -> void throws never {
        self.tree.method_owners[method] = owner;
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::alloc_impl @ d9be6853b
    // Allocate a stable id for an `implements` block. `iface_head` and
    // `for_head` seed the id (impls have no declared name); the collision
    // index disambiguates impls that share both heads.
    function alloc_impl(
        self,
        iface_head: string,
        for_head: string,
        block: ImplBlock,
    ) -> int throws never {
        let h = hash_impl_key(iface_head, for_head);
        let by_hash = self.next_index.get_or_insert(ItemKind.Impl, {});
        let index = by_hash.get(h) ?? 0;
        by_hash[h] = index + 1;
        let id = local_item_id_new(h, index);
        self.tree.impl_order.push(id);
        // A method belongs to its impl block wherever the block is written:
        // the in-class spelling is pure syntax.
        for (let method in block.methods) {
            self.record_method_owner(method, ItemTreeMethodOwnerImpl { value: id });
        }
        self.tree.impls[id] = block;
        id
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::alloc_enum @ d9be6853b
    // Allocate an enum, recording its variant name spans in the source map.
    // `variant_attrs` is parallel to `e.variants`.
    function alloc_enum(
        self,
        e: root.ast.EnumDef,
        attrs: EnumAttrs,
        variant_attrs: EnumVariantAttrs[],
    ) -> int throws never {
        let id = self.alloc_id(ItemKind.Enum, e.name);
        self.source_map.enum_name_spans[id] = e.name_span;
        self.source_map.enum_variant_spans[id]
            = e.variants.map((v) -> {
                v.name_span
            });
        let variants = baml.Array.generate(e.variants.length(), (i: int) -> EnumVariant {
            let v = e.variants[i];
            EnumVariant { name: v.name, attrs: variant_attrs[i], docstring: v.docstring }
        });
        self.tree.enums[id]
            = Enum {
                name: e.name,
                variants: variants,
                attrs: attrs,
                docstring: e.docstring,
                span: e.span,
            };
        id
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::alloc_function_signature @ d9be6853b
    // Allocate a REQUIRED (bodyless) interface method as an ordinary
    // `Function` item: one item kind for every method, a null `body` the only
    // difference.
    function alloc_function_signature(self, m: root.ast.MethodSigDef) -> int throws never {
        let id = self.alloc_id(ItemKind.Function, m.name);
        self.source_map.function_name_spans[id] = m.name_span;
        let params = m.params.map((p) -> {
            FunctionParam {
                name: p.name,
                type_expr: p.type_expr,
                default: null,
                span: p.span,
                name_span: p.name_span,
            }
        });
        self.tree.functions[id]
            = Function {
                name: m.name,
                generic_params: m.generic_params,
                params: params,
                defaults: m.defaults,
                return_type: m.return_type,
                throws_: m.throws_,
                body: null,
                declarative_meta: null,
                metadata: root.ast.FunctionMetadata {
                    origin: root.ast.FunctionOrigin.UserDefined,
                    is_language_internal: false,
                    trace_passthrough: false,
                    explicit_trace_passthrough: false,
                },
                docstring: m.docstring,
                // An interface's method signature has no `//#` title.
                header_title: null,
                is_tagged_template_tag: false,
                trace_hook: null,
                span: m.span,
            };
        id
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::alloc_interface @ d9be6853b
    // Allocate an interface (BEP-044). `method_ids` are the function ids for
    // EVERY method (defaults via `alloc_function`, required signatures via
    // `alloc_function_signature`) in declaration-list order.
    function alloc_interface(
        self,
        i: root.ast.InterfaceDef,
        method_ids: int[],
    ) -> int throws never {
        let id = self.alloc_id(ItemKind.Interface, i.name);
        self.source_map.interface_name_spans[id] = i.name_span;
        self.source_map.interface_field_spans[id]
            = i.fields.map((f) -> {
                f.name_span
            });
        self.source_map.interface_method_spans[id]
            = i.required_methods.map((m) -> {
                m.name_span
            });
        for (let method in method_ids) {
            self.record_method_owner(method, ItemTreeMethodOwnerInterface { value: id });
        }
        let fields = i.fields.map((f) -> {
            InterfaceField { name: f.name, type_expr: f.type_expr, docstring: f.docstring }
        });
        self.tree.interfaces[id]
            = Interface {
                name: i.name,
                generic_params: i.generic_params,
                requires_: i.requires_,
                fields: fields,
                associated_types: i.associated_types,
                methods: method_ids,
                docstring: i.docstring,
                span: i.span,
            };
        id
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::alloc_type_alias @ d9be6853b
    function alloc_type_alias(self, ta: root.ast.TypeAliasDef) -> int throws never {
        let id = self.alloc_id(ItemKind.TypeAlias, ta.name);
        self.source_map.type_alias_name_spans[id] = ta.name_span;
        self.tree.type_aliases[id]
            = TypeAlias {
                name: ta.name,
                type_expr: ta.type_expr,
                span: ta.span,
                docstring: ta.docstring,
            };
        id
    }

    // port: baml_compiler2_hir/src/item_tree/builder.rs::ItemTreeBuilder::alloc_let @ d9be6853b
    function alloc_let(self, l: root.ast.LetDef) -> int throws never {
        let id = self.alloc_id(ItemKind.Let, l.name);
        self.tree.lets[id]
            = Let {
                name: l.name,
                type_annotation: l.type_annotation,
                initializer: l.initializer,
                origin: l.origin,
                docstring: l.docstring,
                span: l.span,
                name_span: l.name_span,
            };
        id
    }
}
