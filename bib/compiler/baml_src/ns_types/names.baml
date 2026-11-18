// port: baml_type/src/names.rs @ d9be6853b
//
// `QualifiedTypeName` is generic over its package key, as in Rust; the
// methods Rust writes on one instantiation (`impl DeclName`,
// `impl QualifiedTypeName<Package>`) are free functions named
// `decl_name_<method>` / `type_name_<method>`.
//
// Not ported:
// - `qualified`, `in_root`, `WireName::own` (class literals) and the `key`,
//   `namespace`, `name`, `root`, `WireName::slot`, `package`, `is_local`
//   accessors (read the fields; `package` is `package_as_name(n.pkg)`,
//   `is_local` is `n.pkg is PackageLocal`).
// - `try_map_key`: `map_key` with a closure that throws.
// - both `of_lang_item`s: `LangItem` is not ported in `ns_base`.
// - `USER_PACKAGE_NAME` (a static `Name` to borrow from) and `impl Ord for
//   Package` / `variant_rank` (orders `TypeName`-keyed sorted containers,
//   which nothing here builds).
// - `render_user_facing` and `impl Display`: `type_name_render_dotted(n,
//   true)` and `type_name_render_dotted(n, false)`.

// port: baml_type/src/names.rs::Package @ d9be6853b
// The wire's package key: which package a type is defined in, relative to the
// artifact naming it. `Local` is the artifact's own root (its spelling is a
// display decision); `Dep` is a dependency by the name the artifact's
// dependency edge gives it (e.g. `baml`).
type Package = PackageLocal | PackageDep;

// The artifact's own root.
class PackageLocal {
}

// A dependency, by the artifact's edge name for it.
class PackageDep {
    value: string,
}

// port: baml_type/src/names.rs::Package::from_name @ d9be6853b
// The wire codec from a spelling: the default self-spelling
// RESERVED_USER_PACKAGE is `Local`, any other spelling a `Dep`.
function package_from_name(name: string) -> Package throws never {
    if (name == RESERVED_USER_PACKAGE) {
        PackageLocal {}
    } else {
        PackageDep { value: name }
    }
}

// port: baml_type/src/names.rs::Package::as_name @ d9be6853b
// The package's spelling (`Local` spells as the default self name).
function package_as_name(package: Package) -> string throws never {
    match (package) {
        PackageLocal => RESERVED_USER_PACKAGE,
        let dep: PackageDep => dep.value,
    }
}

// port: baml_type/src/names.rs::QualifiedTypeName @ d9be6853b
// A declaration's package (by key `P`), namespace path and short name.
class QualifiedTypeName<P> {
    pkg: P,
    namespace: string[],
    name: string,

    // port: baml_type/src/names.rs::QualifiedTypeName::map_key @ d9be6853b
    // The same declaration under a different package key: the boundary
    // operation that converts a head (root to slot, path or spelling; slot or
    // path to root).
    function map_key<Q>(self, f: (P) -> Q) -> QualifiedTypeName<Q> {
        QualifiedTypeName { pkg: f(self.pkg), namespace: self.namespace, name: self.name }
    }

    // port: baml_type/src/names.rs::QualifiedTypeName::path_in_package @ d9be6853b
    // The `[...namespace, name]` path inside the package; the builtin
    // registries are keyed this way.
    function path_in_package(self) -> string[] throws never {
        self.namespace.concat([self.name])
    }

    // port: baml_type/src/names.rs::QualifiedTypeName::is_root_item @ d9be6853b
    // Whether this names `name` at the root namespace of its package.
    function is_root_item(self, name: string) -> bool throws never {
        self.namespace.length() == 0 && self.name == name
    }
}

// port: baml_type/src/names.rs::DeclName @ d9be6853b
// The compiler's qualified name: the declaring package is its root id.
type DeclName = QualifiedTypeName<int>;

// port: baml_type/src/names.rs::WireName @ d9be6853b
// A package interface blob's qualified name: the declaring package is a slot
// in the blob's own dependency table.
type WireName = QualifiedTypeName<DepSlot>;

// port: baml_type/src/names.rs::PathName @ d9be6853b
// A qualified name whose declaring package is an `EdgePath` from its owner.
type PathName = QualifiedTypeName<EdgePath>;

// port: baml_type/src/names.rs::DeclName::is_lang_root_type @ d9be6853b
// Whether this is `name` at the root namespace of the installed language
// package `package` (`baml.Int`, `reflect.AnyClass`, ...). False when that
// package is not installed.
function decl_name_is_lang_root_type(
    decl: DeclName,
    lang: root.base.LangRoots,
    package: root.base.LangPackage,
    name: string,
) -> bool throws never {
    lang.is_(package, decl.pkg) && decl.is_root_item(name)
}

// port: baml_type/src/names.rs::DeclName::is_panic_type @ d9be6853b
// Whether this lives in the `baml.panics` namespace (a panic class or the
// `Panic` alias). "panics" is baml_base's PANICS_NAMESPACE.
function decl_name_is_panic_type(decl: DeclName, lang: root.base.LangRoots) -> bool throws never {
    lang.is_(root.base.LangPackage.Baml, decl.pkg)
        && decl.namespace.length() == 1
        && decl.namespace[0] == "panics"
}

// port: baml_type/src/names.rs::DeclName::builtin_primitive @ d9be6853b
// The primitive a builtin companion class stands for (`baml.Int` to `int`),
// if this is one.
function decl_name_builtin_primitive(
    decl: DeclName,
    lang: root.base.LangRoots,
) -> PrimitiveType? throws never {
    if (!lang.is_(root.base.LangPackage.Baml, decl.pkg)) {
        return null;
    }
    primitive_type_from_builtin_class_path(decl.path_in_package())
}

// port: baml_type/src/names.rs::DeclName::builtin_alias @ d9be6853b
// The lowercase alias of a builtin companion class (`baml.String` to
// `string`, `baml.media.Image` to `image`, `baml.json.json` to `json`), if
// this is one.
function decl_name_builtin_alias(
    decl: DeclName,
    lang: root.base.LangRoots,
) -> string? throws never {
    if (!lang.is_(root.base.LangPackage.Baml, decl.pkg)) {
        return null;
    }
    let builtin = builtin_type_name_from_builtin_definition_path(decl.path_in_package())
        ?? return null;
    builtin_type_name_alias(builtin)
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::new @ d9be6853b
// A wire name from a package spelling (see package_from_name).
function type_name_new(pkg: string, namespace: string[], name: string) -> TypeName throws never {
    QualifiedTypeName { pkg: package_from_name(pkg), namespace: namespace, name: name }
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::local @ d9be6853b
// A type at the root namespace of the artifact's own package: a bare
// class/enum name.
function type_name_local(name: string) -> TypeName throws never {
    let pkg: Package = PackageLocal {};
    QualifiedTypeName { pkg: pkg, namespace: [], name: name }
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::is_builtin_root_type @ d9be6853b
function type_name_is_builtin_root_type(n: TypeName, name: string) -> bool throws never {
    package_as_name(n.pkg) == "baml" && n.is_root_item(name)
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::is_reflect_root_type @ d9be6853b
// type_name_is_builtin_root_type for the `reflect` package's root namespace
// (`reflect.AnyFunction`, `reflect.AnyClass`, ...).
function type_name_is_reflect_root_type(n: TypeName, name: string) -> bool throws never {
    package_as_name(n.pkg) == "reflect" && n.is_root_item(name)
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::module_path @ d9be6853b
// The flat `[package, ...namespace]` path.
function type_name_module_path(n: TypeName) -> string[] throws never {
    [package_as_name(n.pkg)].concat(n.namespace)
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::display_name @ d9be6853b
// The user-facing display name: the artifact's own package is elided,
// dependency packages are kept.
function type_name_display_name(n: TypeName) -> string throws never {
    if (n.pkg is PackageLocal) {
        n.path_in_package().join(".")
    } else {
        type_name_render_dotted(n, false)
    }
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::from_dotted_path @ d9be6853b
// Parses a dotted path: the first segment is the package, the last the short
// name, any middle segments the namespace (`"baml.json.json"` is pkg `baml`,
// ns `["json"]`, name `json`). A single bare segment is a type of the
// artifact's own package.
function type_name_from_dotted_path(path: string) -> TypeName throws never {
    let segments = path.split(".");
    let name = segments[segments.length() - 1];
    if (segments.length() == 1) {
        return type_name_local(name);
    }
    type_name_new(segments[0], segments.slice(1, segments.length() - 1), name)
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::render_dotted @ d9be6853b
// The dotted path `package.namespace.name` (no `<generic_params>` suffix).
// When `user_facing`, the artifact's own package is elided: the single
// structural source of the "no `user.` in names" rule. The canonical form
// keeps the package for dumps and identity. Rust's four-arm match on
// `(elide, namespace.is_empty())` is two ifs (a tuple of bools is not a
// matchable pattern).
function type_name_render_dotted(n: TypeName, user_facing: bool) -> string throws never {
    let namespace = n.namespace.join(".");
    let elide = user_facing && n.pkg is PackageLocal;
    let in_package = if (namespace.length() == 0) {
        n.name
    } else {
        `${namespace}.${n.name}`
    };
    if (elide) {
        in_package
    } else {
        `${package_as_name(n.pkg)}.${in_package}`
    }
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::builtin_primitive @ d9be6853b
// The primitive represented by a builtin companion class.
function type_name_builtin_primitive(n: TypeName) -> PrimitiveType? throws never {
    if (package_as_name(n.pkg) != "baml") {
        return null;
    }
    primitive_type_from_builtin_class_path(n.path_in_package())
}

// port: baml_type/src/names.rs::QualifiedTypeName<Package>::builtin_alias @ d9be6853b
// If this names a builtin `baml` companion class with a lowercase
// primitive/keyword alias, that alias: `baml.String` is `string`,
// `baml.media.Image` is `image`, `baml.json.json` is `json`. Null for any
// other type, including user types and unaliased `baml` types such as
// `baml.json.JsonObject`.
function type_name_builtin_alias(n: TypeName) -> string? throws never {
    if (package_as_name(n.pkg) != "baml") {
        return null;
    }
    let builtin = builtin_type_name_from_builtin_definition_path(n.path_in_package())
        ?? return null;
    builtin_type_name_alias(builtin)
}

// port: baml_type/src/names.rs::ADDRESSABLE_USER_PACKAGE @ d9be6853b
// How the workspace package is spelled in addressable paths (`root.ns.Foo`).
const ADDRESSABLE_USER_PACKAGE: string = "root";

// port: baml_type/src/names.rs::RESERVED_USER_PACKAGE @ d9be6853b
// The default display spelling of a nameless package that nothing depends
// on. It has no semantics and is never shown in user-facing output.
const RESERVED_USER_PACKAGE: string = "user";

// port: baml_type/src/names.rs::SYNTHETIC_EFFECT_PARAM_PREFIX @ d9be6853b
// Prefix of synthetic effect-polymorphism type parameters (`__effect_param_0`,
// ...); user-facing rendering shows them as `callback`.
const SYNTHETIC_EFFECT_PARAM_PREFIX: string = "__effect_param_";

// port: baml_type/src/names.rs::is_synthetic_effect_param @ d9be6853b
// Whether `name` is a synthesized effect-polymorphism type parameter
// (`__effect_param_N`, N all ASCII digits).
function is_synthetic_effect_param(name: string) -> bool throws never {
    let rest = root.base.strip_prefix(name, SYNTHETIC_EFFECT_PARAM_PREFIX)
        ?? return false;
    rest.length() > 0
        && rest.chars().every((c) -> {
            c >= "0" && c <= "9"
        })
}
