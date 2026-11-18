// port: baml_compiler2_hir/src/item_tree.rs @ d9be6853b
//
// Position-independent item storage for `compiler2_hir`. `ItemTree` stores
// minimal item representations keyed by name-based ids (`LocalItemId`s, here
// `int`s), indexed by name, not source position.
//
// deviation: Rust's `Index<LocalItemId<Marker>>` impls are not ported: index
// the map for the kind directly (`tree.functions[id]`, `tree.classes[id]`,
// ...).

// port: baml_compiler2_hir/src/item_tree.rs::ItemTree @ d9be6853b
// Position-independent item storage for a single file. A finished value:
// everything needed to build it (the collision counter, the source map) lives
// in `ItemTreeBuilder`.
class ItemTree {
    functions: map<int, Function>,
    classes: map<int, Class>,
    enums: map<int, Enum>,
    interfaces: map<int, Interface>,
    type_aliases: map<int, TypeAlias>,
    lets: map<int, Let>,
    // Every `implements` block, keyed by a stable impl id. `impl_order`
    // orders it.
    impls: map<int, ImplBlock>,
    // The impl ids in source order: coherence needs a deterministic order to
    // pick a winner among overlapping impls.
    impl_order: int[],
    // BEP-044: for a class method declared inside an `implements I {}` block,
    // the unresolved interface target path. Absent for class-level methods
    // and interface default methods.
    method_to_iface_target: map<int, root.ast.TypeExpr>,
    method_to_iface_associated_type_bindings: map<int, root.ast.AssociatedTypeBindingDef[]>,
    // Method -> owning item. Inverse of `Class.methods` /
    // `Interface.methods` / a free impl's `ImplBlock.methods`; absent for
    // top-level functions.
    method_owners: map<int, ItemTreeMethodOwner>,

    // port: baml_compiler2_hir/src/item_tree.rs::ItemTree::default @ d9be6853b
    // `#[derive(Default)]`: the empty tree.
    function default_() -> ItemTree throws never {
        ItemTree {
            functions: {},
            classes: {},
            enums: {},
            interfaces: {},
            type_aliases: {},
            lets: {},
            impls: {},
            impl_order: [],
            method_to_iface_target: {},
            method_to_iface_associated_type_bindings: {},
            method_owners: {},
        }
    }

    // port: baml_compiler2_hir/src/item_tree.rs::ItemTree::enclosing_type_generic_params @ d9be6853b
    // Generic parameters of the type declaration enclosing `method`: the
    // class's for a class method, the interface's for an interface default
    // method, empty for top-level functions and free-impl methods (an impl
    // block's generics are threaded by the impl-specific paths).
    function enclosing_type_generic_params(self, method: int) -> GenericParam[] throws never {
        match (self.method_owners.get(method)) {
            let owner: ItemTreeMethodOwnerClass => self.classes[owner.value].generic_params,
            let owner: ItemTreeMethodOwnerInterface => self.interfaces[owner.value].generic_params,
            _ => [],
        }
    }
}
