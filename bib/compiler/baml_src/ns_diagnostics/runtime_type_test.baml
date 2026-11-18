// port: baml_compiler_diagnostics/src/runtime_type.rs::tests @ d9be6853b
// The cases for the constructors ported so far.

test "constructors own code and complete message" {
    let cases = [
        (mismatched_types(), "E0001", "mismatched types"),
        (
            computed_generic_argument_requires_let_type("runtime_t"),
            "E0002",
            "`runtime_t` is a value, not a type; bind its runtime type first with `let type T = runtime_t;` and write `T` here",
        ),
        (
            bounded_let_type_requires_else("V"),
            "E0111",
            "`let type V extends …` checks its bounds when it runs, so it needs an `else` block for a type that misses them",
        ),
        (
            let_type_pending_operand(),
            "E0001",
            "`let type` cannot bind a class builder's pending type; call `build()` and bind the class it returns",
        ),
        (
            scoped_type_escapes_block("Out"),
            "E0172",
            "scoped type `Out` cannot leave the block that binds it",
        ),
        (
            cannot_construct_reflection_kind("reflect.Class"),
            "E0001",
            "reflection kind `reflect.Class` cannot be constructed; obtain it from a type value",
        ),
        (
            cannot_construct_builtin_companion("baml.Int", "int", "literals", true),
            "E0166",
            "companion class `baml.Int` cannot be constructed; it only carries the methods of `int`, whose values come from literals",
        ),
        (
            cannot_construct_builtin_companion("baml.Bool", "bool", "literals", false),
            "E0166",
            "companion class `baml.Bool` cannot be constructed; it is only the companion of `bool`, whose values come from literals",
        ),
        (
            mounted_package_call_unsupported("dep.tool"),
            "E0158",
            "cannot call mounted callable `dep.tool`: this callable kind has no loc-free bytecode link contract",
        ),
    ];
    for (let case in cases) {
        assert.equal(case.0.id, case.1);
        assert.equal(case.0.message, case.2);
    }
}
