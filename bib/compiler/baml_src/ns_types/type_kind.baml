// port: baml_type/src/type_kind.rs @ d9be6853b
//
// The closed reflection-kind classification. TypeKind's methods are free
// functions `type_kind_<method>`.
//
// `LangItem` is not ported in `ns_base`, so `TypeKind::class` returns the
// item's name: every kind view is a class at the root namespace of the
// `reflect` package, which is the rest of the item.
//
// Not ported: `builtin_companion_of_decl`, `builtin_companion_of` and
// `companion` (the `BuiltinCompanion` struct is). They read the registry's
// `Construction` (origin, carries_methods) and `by_definition` /
// `by_type_name` lookups, and members_reachable_without_carrier, none of
// which compiler_aliases.baml ports yet.

// port: baml_type/src/type_kind.rs::TypeKind @ d9be6853b
enum TypeKind {
    Class,
    Enum,
    Union,
    Literal,
    Array,
    Map,
    Interface,
    Primitive,
    Function,
    Tuple,
}

// port: baml_type/src/type_kind.rs::TypeKind::ALL @ d9be6853b
const TYPE_KINDS: TypeKind[] = [
    TypeKind.Class,
    TypeKind.Enum,
    TypeKind.Union,
    TypeKind.Literal,
    TypeKind.Array,
    TypeKind.Map,
    TypeKind.Interface,
    TypeKind.Primitive,
    TypeKind.Function,
    TypeKind.Tuple,
];

// port: baml_type/src/type_kind.rs::TypeKind::name @ d9be6853b
// The kind's lowercase name, as messages spell it (`class-kind`).
function type_kind_name(kind: TypeKind) -> string throws never {
    match (kind) {
        TypeKind.Class => "class",
        TypeKind.Enum => "enum",
        TypeKind.Union => "union",
        TypeKind.Literal => "literal",
        TypeKind.Array => "array",
        TypeKind.Map => "map",
        TypeKind.Interface => "interface",
        TypeKind.Primitive => "primitive",
        TypeKind.Function => "function",
        TypeKind.Tuple => "tuple",
    }
}

// port: baml_type/src/type_kind.rs::TypeKind::class @ d9be6853b
// The name of the builtin class that is the sealed view for this kind:
// `reflect.<Kind>` at the root of the package.
function type_kind_class(kind: TypeKind) -> string throws never {
    match (kind) {
        TypeKind.Class => "Class",
        TypeKind.Enum => "Enum",
        TypeKind.Union => "Union",
        TypeKind.Literal => "Literal",
        TypeKind.Array => "Array",
        TypeKind.Map => "Map",
        TypeKind.Interface => "Interface",
        TypeKind.Primitive => "Primitive",
        TypeKind.Function => "Function",
        TypeKind.Tuple => "Tuple",
    }
}

// port: baml_type/src/type_kind.rs::TypeKind::class_name @ d9be6853b
// type_kind_class by wire name: a host spells a language package by its
// manifest name.
function type_kind_class_name(kind: TypeKind) -> TypeName throws never {
    type_name_new(root.base.lang_package_manifest_name(root.base.LangPackage.Reflect), [], type_kind_class(kind))
}

// port: baml_type/src/type_kind.rs::TypeKind::class_decl @ d9be6853b
// type_kind_class in the installed `reflect` package.
function type_kind_class_decl(kind: TypeKind, reflect: int) -> DeclName throws never {
    DeclName { pkg: reflect, namespace: [], name: type_kind_class(kind) }
}

// port: baml_type/src/type_kind.rs::classify_type @ d9be6853b
// Every realized runtime type in exactly one reflection kind. Shape only: no
// head is inspected.
function classify_type(ty: RealizedTy) -> TypeKind throws never {
    match (ty) {
        RealizedTyClass => TypeKind.Class,
        TyEnum => TypeKind.Enum,
        RealizedTyUnion => TypeKind.Union,
        TyLiteral | TyEnumVariant => TypeKind.Literal,
        RealizedTyList => TypeKind.Array,
        RealizedTyMap => TypeKind.Map,
        RealizedTyInterface => TypeKind.Interface,
        RealizedTyFunction => TypeKind.Function,
        RealizedTyTuple => TypeKind.Tuple,
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | RealizedTyFuture
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever =>
        {
            TypeKind.Primitive
        },
    }
}

// port: baml_type/src/type_kind.rs::is_type_kind_class @ d9be6853b
// Whether a wire name is a `reflect.<Kind>` view.
function is_type_kind_class(name: TypeName) -> bool throws never {
    package_as_name(name.pkg) == "reflect" && is_type_kind_class_path(name.namespace, name.name)
}

// port: baml_type/src/type_kind.rs::is_type_kind_class_decl @ d9be6853b
// is_type_kind_class for a compile-time head: the class must live in the
// installed `reflect` package.
function is_type_kind_class_decl(lang: root.base.LangRoots, name: DeclName) -> bool throws never {
    lang.is_(root.base.LangPackage.Reflect, name.pkg)
        && is_type_kind_class_path(name.namespace, name.name)
}

// port: baml_type/src/type_kind.rs::is_type_kind_class_path @ d9be6853b
// A root-level `<Kind>` class inside the `reflect` package.
function is_type_kind_class_path(namespace: string[], name: string) -> bool throws never {
    namespace.length() == 0
        && TYPE_KINDS.some((kind) -> {
            type_kind_class(kind) == name
        })
}

// port: baml_type/src/type_kind.rs::BuiltinCompanion @ d9be6853b
// A builtin companion carrier (`baml.Int`, `baml.Map`, ...): the builtin it
// stands for and how that builtin's values are produced instead.
class BuiltinCompanion {
    // The builtin type this class is the companion of.
    builtin: string,
    // How a value of that builtin is produced instead.
    origin: string,
    // Whether the class actually declares methods (`baml.Bool` and
    // `baml.Null` have empty bodies).
    carries_methods: bool,
    // Whether source reaches this builtin's members without naming the
    // carrier class (`int.max_value()` does; the containers do not).
    members_reachable_without_carrier: bool,
}
