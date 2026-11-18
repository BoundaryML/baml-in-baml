// port: baml_compiler_diagnostics/src/runtime_type.rs @ d9be6853b
//
// Shared diagnostics for runtime type construction, reflection and
// rendering: each constructor picks both the id and the complete message.
//
// Ported so far: the constructors the type checker's messages use. The
// reflection, runtime-union and LLM-render constructors (and their
// `SerializedKeyContainer` / `DuplicateMemberKind` / `InvalidIdentifierKind`
// kinds) serve runtime code; `duplicate_member` and
// `duplicate_serialized_key` have HIR-local ports in `ns_hir/diagnostic.baml`.

// port: baml_compiler_diagnostics/src/runtime_type.rs::mismatched_types @ d9be6853b
// E0001: the compiler's type-mismatch headline.
function mismatched_types() -> Diagnostic throws never {
    Diagnostic.error(TYPE_MISMATCH, "mismatched types")
}

// port: baml_compiler_diagnostics/src/runtime_type.rs::computed_generic_argument_requires_let_type @ d9be6853b
// E0002: a value name written where a type argument belongs.
function computed_generic_argument_requires_let_type(name: string) -> Diagnostic throws never {
    Diagnostic.error(
        UNKNOWN_TYPE,
        `\`${name}\` is a value, not a type; bind its runtime type first with \`let type T = ${name};\` and write \`T\` here`,
    )
}

// port: baml_compiler_diagnostics/src/runtime_type.rs::bounded_let_type_requires_else @ d9be6853b
// E0111: a bounded `let type T extends I = ...;` has no `else` block.
function bounded_let_type_requires_else(name: string) -> Diagnostic throws never {
    Diagnostic.error(
        REFUTABLE_PATTERN_IN_LET,
        `\`let type ${name} extends …\` checks its bounds when it runs, so it needs an \`else\` block for a type that misses them`,
    )
}

// port: baml_compiler_diagnostics/src/runtime_type.rs::let_type_pending_operand @ d9be6853b
// E0001: a `let type` operand is a class builder's pending type.
function let_type_pending_operand() -> Diagnostic throws never {
    Diagnostic.error(
        TYPE_MISMATCH,
        "`let type` cannot bind a class builder's pending type; call `build()` and bind the class it returns",
    )
}

// port: baml_compiler_diagnostics/src/runtime_type.rs::scoped_type_escapes_block @ d9be6853b
// E0172: a value typed by a body-scoped `let type T = ...` binding would be
// observable outside the block that binds `T`.
function scoped_type_escapes_block(name: string) -> Diagnostic throws never {
    Diagnostic.error(SCOPED_TYPE_ESCAPES_BLOCK, `scoped type \`${name}\` cannot leave the block that binds it`)
}

// port: baml_compiler_diagnostics/src/runtime_type.rs::cannot_construct_reflection_kind @ d9be6853b
// E0001: sealed reflection-kind values come only from an existing `type`.
function cannot_construct_reflection_kind(class_name: string) -> Diagnostic throws never {
    Diagnostic.error(
        TYPE_MISMATCH,
        `reflection kind \`${class_name}\` cannot be constructed; obtain it from a type value`,
    )
}

// port: baml_compiler_diagnostics/src/runtime_type.rs::cannot_construct_builtin_companion @ d9be6853b
// E0166: builtin companion carriers hold no fields and are never
// instantiated. `carries_methods` is false for the empty-bodied companions.
function cannot_construct_builtin_companion(
    class_name: string,
    builtin: string,
    origin: string,
    carries_methods: bool,
) -> Diagnostic throws never {
    let role = if (carries_methods) {
        `it only carries the methods of \`${builtin}\``
    } else {
        `it is only the companion of \`${builtin}\``
    };
    Diagnostic.error(
        CANNOT_CONSTRUCT_BUILTIN_COMPANION,
        `companion class \`${class_name}\` cannot be constructed; ${role}, whose values come from ${origin}`,
    )
}

// port: baml_compiler_diagnostics/src/runtime_type.rs::mounted_package_call_unsupported @ d9be6853b
// E0158: the mounted callable has no location-free bytecode link contract.
function mounted_package_call_unsupported(path: string) -> Diagnostic throws never {
    Diagnostic.error(
        MOUNTED_PACKAGE_CALL_UNSUPPORTED,
        `cannot call mounted callable \`${path}\`: this callable kind has no loc-free bytecode link contract`,
    )
}
