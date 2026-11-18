// port: baml_type/src/structural_interface.rs @ d9be6853b
//
// The enum's methods are free functions `structural_interface_<method>`.

// port: baml_type/src/structural_interface.rs::StructuralInterface @ d9be6853b
// Language interfaces with a shared native implementation when no explicit
// implementation applies. The declaring interface's identity grants this
// capability; a method's spelling alone never does.
enum StructuralInterface {
    ToString,
    ToJson,
    FromJson,
    Equals,
    Hash,
    Compare,
}

// port: baml_type/src/structural_interface.rs::StructuralInterface::is_conditional @ d9be6853b
function structural_interface_is_conditional(iface: StructuralInterface) -> bool throws never {
    iface == StructuralInterface.Hash || iface == StructuralInterface.Compare
}

// port: baml_type/src/structural_interface.rs::StructuralInterface::primary_method @ d9be6853b
function structural_interface_primary_method(iface: StructuralInterface) -> string throws never {
    match (iface) {
        StructuralInterface.ToString => "to_string",
        StructuralInterface.ToJson => "to_json",
        StructuralInterface.FromJson => "from_json",
        StructuralInterface.Equals => "eq",
        StructuralInterface.Hash => "hash",
        StructuralInterface.Compare => "cmp",
    }
}

// port: baml_type/src/structural_interface.rs::StructuralInterface::native_function @ d9be6853b
function structural_interface_native_function(iface: StructuralInterface) -> string throws never {
    match (iface) {
        StructuralInterface.ToString => "_to_string_default",
        StructuralInterface.ToJson => "_to_json_default",
        StructuralInterface.FromJson => "_from_json_structural_default",
        StructuralInterface.Equals => "_equals_structural_default",
        StructuralInterface.Hash => "_hash_structural_default",
        StructuralInterface.Compare => "_compare_structural_default",
    }
}

// port: baml_type/src/structural_interface.rs::StructuralInterface::native_type_arg_count @ d9be6853b
function structural_interface_native_type_arg_count(
    iface: StructuralInterface,
) -> int throws never {
    match (iface) {
        StructuralInterface.Equals | StructuralInterface.Hash | StructuralInterface.Compare => 0,
        StructuralInterface.ToString | StructuralInterface.ToJson | StructuralInterface.FromJson => {
            1
        },
    }
}
