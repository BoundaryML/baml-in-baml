// Items of `baml_type/src/template.rs` MIR unit 6 (memory.rs) needs, for
// unit U7 to port into their home. Deleted at merge.

// port: baml_type/src/template.rs::TyTemplateInterface::for_each_type_arg_ref @ d9be6853b
// `TyTemplate::for_each_type_arg_ref` over every template position of the
// constraint: the generic arguments, then the associated-type bindings.
// Restructured: a method of `TyTemplateInterfaceConstraint` (Rust's
// `TyTemplateInterface`) is a free function. Implemented, not panicking:
// `root.mir.walk_*_type_slots` reach it on every interface template.
function ty_template_interface_constraint_for_each_type_arg_ref(
    iface: TyTemplateInterfaceConstraint,
    f: (int) -> void throws never,
) -> void throws never {
    for (let generic in iface.generics) {
        root.mir.ty_template_for_each_type_arg_ref(generic, f);
    }
    for (let binding in iface.associated_types) {
        root.mir.ty_template_for_each_type_arg_ref(binding.ty, f);
    }
}
