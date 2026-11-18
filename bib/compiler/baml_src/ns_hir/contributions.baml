// port: baml_compiler2_hir/src/contributions.rs @ d9be6853b
//
// Symbol contributions: what names a file adds to its package namespace.

// port: contributions.rs::DefinitionKind. Unified kind tag for any named
// definition, at any scope level: namespace-level items (Class, Function, ...)
// and intra-item members (Field, Method, Variant, Binding, Parameter).
enum DefinitionKind {
    // Namespace-level items
    Class,
    Enum,
    Interface,
    TypeAlias,
    Function,
    Client,
    Let,
    // Intra-item members
    Field,
    AssociatedType,
    Method,
    Variant,
    Binding,
    Parameter,
}

// port: baml_compiler2_hir/src/contributions.rs::DefinitionKind::as_str @ d9be6853b
// Also `impl Display for DefinitionKind`, which writes exactly this.
function definition_kind_as_str(kind: DefinitionKind) -> string throws never {
    match (kind) {
        DefinitionKind.Class => "class",
        DefinitionKind.Enum => "enum",
        DefinitionKind.Interface => "interface",
        DefinitionKind.TypeAlias => "type",
        DefinitionKind.Function => "function",
        DefinitionKind.Client => "client",
        DefinitionKind.Let => "let",
        DefinitionKind.Field => "field",
        DefinitionKind.AssociatedType => "associated type",
        DefinitionKind.Method => "method",
        DefinitionKind.Variant => "variant",
        DefinitionKind.Binding => "binding",
        DefinitionKind.Parameter => "parameter",
    }
}

// port: baml_compiler2_hir/src/contributions.rs::DefinitionKind::is_member @ d9be6853b
// Whether this kind uses dot-qualified names (e.g. `Foo.bar`). Members of a
// type use dot notation; locals use "in" phrasing.
function definition_kind_is_member(kind: DefinitionKind) -> bool throws never {
    match (kind) {
        DefinitionKind.Field
            | DefinitionKind.AssociatedType
            | DefinitionKind.Method
            | DefinitionKind.Variant =>
        {
            true
        },
        _ => false,
    }
}

// port: contributions.rs::Definition. What a single definition resolves to:
// each variant carries its interned loc (`db.class_locs`, ...).
type Definition = DefinitionClass
    | DefinitionEnum
    | DefinitionInterface
    | DefinitionTypeAlias
    | DefinitionFunction
    | DefinitionLet;

class DefinitionClass {
    value: int,
}

class DefinitionEnum {
    value: int,
}

class DefinitionInterface {
    value: int,
}

class DefinitionTypeAlias {
    value: int,
}

class DefinitionFunction {
    value: int,
}

class DefinitionLet {
    value: int,
}

// port: baml_compiler2_hir/src/contributions.rs::Definition::file @ d9be6853b
// The source file this definition lives in.
function definition_file(definition: Definition, db: Db) -> int throws never {
    match (definition) {
        let d: DefinitionClass => db.class_locs.get(d.value).file,
        let d: DefinitionEnum => db.enum_locs.get(d.value).file,
        let d: DefinitionInterface => db.interface_locs.get(d.value).file,
        let d: DefinitionTypeAlias => db.type_alias_locs.get(d.value).file,
        let d: DefinitionFunction => db.function_locs.get(d.value).file,
        let d: DefinitionLet => db.let_locs.get(d.value).file,
    }
}

// port: baml_compiler2_hir/src/contributions.rs::Definition::kind @ d9be6853b
// The unified kind tag for this definition.
function definition_kind(definition: Definition) -> DefinitionKind throws never {
    match (definition) {
        DefinitionClass => DefinitionKind.Class,
        DefinitionEnum => DefinitionKind.Enum,
        DefinitionInterface => DefinitionKind.Interface,
        DefinitionTypeAlias => DefinitionKind.TypeAlias,
        DefinitionFunction => DefinitionKind.Function,
        DefinitionLet => DefinitionKind.Let,
    }
}

// port: baml_compiler2_hir/src/contributions.rs::Definition::kind_name @ d9be6853b
// Human-readable kind label for diagnostics.
function definition_kind_name(definition: Definition) -> string throws never {
    definition_kind_as_str(definition_kind(definition))
}

// port: baml_compiler2_hir/src/contributions.rs::Definition::source_kind @ d9be6853b
// The declaration kind as written in BAML source. Some configuration
// declarations are lowered to top-level lets before HIR; keep that internal
// representation out of source-level namespace diagnostics.
function definition_source_kind(definition: Definition, db: Db) -> DefinitionKind throws never {
    if (!(definition is DefinitionLet)) {
        return definition_kind(definition);
    }
    let loc = db.let_locs.get(definition.value);
    let item_tree = file_item_tree(db, loc.file);
    match (item_tree.lets.get(loc.id)?.origin) {
        root.ast.LetOrigin.Client => DefinitionKind.Client,
        root.ast.LetOrigin.Source | null => DefinitionKind.Let,
    }
}

// port: baml_compiler2_hir/src/contributions.rs::Definition::source_kind_name @ d9be6853b
function definition_source_kind_name(definition: Definition, db: Db) -> string throws never {
    definition_kind_as_str(definition_source_kind(definition, db))
}

// port: baml_compiler2_hir/src/contributions.rs::Definition::is_language_internal @ d9be6853b
// Whether this definition is outside BAML's user-facing language surface.
function definition_is_language_internal(definition: Definition, db: Db) -> bool throws never {
    if (!(definition is DefinitionFunction)) {
        return false;
    }
    let loc = db.function_locs.get(definition.value);
    file_item_tree(db, loc.file).functions[loc.id].metadata.is_language_internal
}

// port: contributions.rs::Contribution. A symbol contribution: name,
// definition, and the span of the name token (not the full item), which
// namespace conflict diagnostics point at.
class Contribution {
    name_span: root.syntax.TextRange,
    definition: Definition,
}

// port: contributions.rs::FileSymbolContributions. Names contributed by a
// single file to its package namespace.
class FileSymbolContributions {
    // Type-namespace names (classes, enums, type aliases).
    types: (string, Contribution)[],
    // Value-namespace names (functions, template strings, clients, etc.).
    values: (string, Contribution)[],

    // port: baml_compiler2_hir/src/contributions.rs::FileSymbolContributions::new @ d9be6853b
    // Also `Default`.
    function new() -> FileSymbolContributions throws never {
        FileSymbolContributions { types: [], values: [] }
    }
}
