// port: baml_type/src/defs.rs @ d9be6853b
//
// Canonical schema-level definitions: classes, enums, functions and type
// aliases as they appear in the compiled schema. Rust's `Ty` here is the
// default (`TypeName`) head; it is DeclName-headed like every family member.
// Nothing in the workspace at d9be6853b reads these types.

// port: baml_type/src/defs.rs::SchemaDefs @ d9be6853b
class SchemaDefs {
    classes: ClassDef[],
    enums: EnumDef[],
    functions: FunctionDef[],
    type_aliases: TypeAliasDef[],
}

// port: baml_type/src/defs.rs::ClassDef @ d9be6853b
// A class with resolved field types and propagated attributes.
class ClassDef {
    name: string,
    fields: FieldDef[],
    description: string?,
    alias: string?,
}

// port: baml_type/src/defs.rs::FieldDef @ d9be6853b
class FieldDef {
    name: string,
    ty: Ty,
    description: string?,
    alias: string?,
    skip: bool,
}

// port: baml_type/src/defs.rs::EnumDef @ d9be6853b
class EnumDef {
    name: string,
    variants: EnumVariantDef[],
    description: string?,
    alias: string?,
}

// port: baml_type/src/defs.rs::EnumVariantDef @ d9be6853b
class EnumVariantDef {
    name: string,
    description: string?,
    alias: string?,
    skip: bool,
}

// port: baml_type/src/defs.rs::FunctionDef @ d9be6853b
class FunctionDef {
    name: string,
    params: ParamDef[],
    return_type: Ty,
    body_kind: FunctionBodyKind,
}

// port: baml_type/src/defs.rs::ParamDef @ d9be6853b
class ParamDef {
    name: string,
    ty: Ty,
}

// port: baml_type/src/defs.rs::FunctionBodyKind @ d9be6853b
// How the runtime dispatches a function body.
type FunctionBodyKind = FunctionBodyKindLlm | FunctionBodyKindExpr | FunctionBodyKindMissing;

// A declarative LLM function with a client reference.
class FunctionBodyKindLlm {
    client_: string,
}

// An imperative expression function, compiled to bytecode.
class FunctionBodyKindExpr {
}

// The body is missing (error recovery in HIR).
class FunctionBodyKindMissing {
}

// port: baml_type/src/defs.rs::TypeAliasDef @ d9be6853b
class TypeAliasDef {
    name: string,
    resolves_to: Ty,
}
