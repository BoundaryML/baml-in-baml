// port: baml_compiler2_hir_ty/src/interfaces.rs @ d9be6853b
//
// The `interfaces` module's own file. Rust re-exports `interfaces/*` into
// this module, so everything here and in its sibling files is
// `root.hir_ty.interfaces.*`, as Rust's paths are.
//
// Ported so far: the data types and stubs the type checker's message layer
// (`check_types.baml`) reads.

// port: baml_compiler2_hir_ty/src/interfaces.rs::InterfaceImplOrigin @ d9be6853b
// Where an `implements` block was written. Diagnostic metadata only.
type InterfaceImplOrigin = InterfaceImplOriginInBodyClass | InterfaceImplOriginOutOfBody;

// `implements I { ... }` written in the class body.
class InterfaceImplOriginInBodyClass {
    class_qtn: root.types.DeclName,
}

// `implement<...> I for <for_target>`: any out-of-body impl.
class InterfaceImplOriginOutOfBody {
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::ResolvedInterface @ d9be6853b
// An interface declaration resolved from a path: its interface loc id plus
// its fully qualified identity.
class ResolvedInterface {
    loc: int,
    qtn: root.types.DeclName,
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolve_path_to_interface_identity @ d9be6853b
// Resolve a path type expression to an interface declaration and its
// identity; null when the path doesn't resolve to an interface.
function resolve_path_to_interface_identity(
    db: root.hir.Db,
    target: root.ast.TypeExpr,
    pkg_items: root.hir.PackageItems,
    current_ns: string[],
) -> ResolvedInterface? throws never {
    baml.sys.panic("resolve_path_to_interface_identity: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interfaces_declaring_associated_type @ d9be6853b
// The interface locs that declare associated type `member`, across the
// `requires` closures of `roots`, each counted once, in a stable order.
function interfaces_declaring_associated_type(
    db: root.hir.Db,
    roots: int[],
    member: string,
) -> int[] throws never {
    baml.sys.panic("interfaces_declaring_associated_type: not ported")
}
