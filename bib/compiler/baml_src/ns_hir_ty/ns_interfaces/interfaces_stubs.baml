// port: baml_compiler2_hir_ty/src/interfaces.rs @ d9be6853b
//
// Not ported (package K2). The data types and stubs that lower.rs and
// facts.rs read.
//
// Four judges are reached by every declaration the lowering diagnostics
// walk: `type_generic_bound_errors`, `map_key_is_hashable`,
// `resolve_interface_required_methods` and `interface_requires_cycle`. A
// panicking stub there would stop every declaration-gate unit, so these four
// answer the no-diagnostic value instead; the diagnostics they would add are
// missing until K2 lands. The rest panic.

// port: baml_compiler2_hir_ty/src/interfaces.rs::MemberNamespace @ d9be6853b
// Which member namespace a projection reads.
enum MemberNamespace {
    // Associated types, written in type position.
    Type,
    // Fields and methods, written in value position.
    Value,
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::ProjectionLowering @ d9be6853b
// A lowered projection and its determination diagnostics.
class ProjectionLowering {
    ty: root.types.Ty,
    diagnostics: root.hir_ty.TirTypeError[],
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::ResolvedInterfaceMethod @ d9be6853b
// One required method of an interface, resolved.
class ResolvedInterfaceMethod {
    name: string,
    // The full function type (params, return, declared throws).
    function_ty: root.types.Ty,
    // The method's own generic parameters with their resolved bounds.
    generic_params: (root.types.ParamTy, root.types.InterfaceConstraint[])[],
    diagnostics: root.hir_ty.TirTypeError[],
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::lower_projection @ d9be6853b
function lower_projection(
    db: root.hir.Db,
    viewer: int,
    scope_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    base: root.types.Ty,
    explicit_interface: root.types.Ty?,
    member: string,
) -> ProjectionLowering throws never {
    baml.sys.panic("lower_projection: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_declares_member @ d9be6853b
function interface_declares_member(
    db: root.hir.Db,
    qtn: root.types.DeclName,
    member: string,
    ns: MemberNamespace,
) -> bool throws never {
    baml.sys.panic("interface_declares_member: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::map_key_is_hashable @ d9be6853b
// Stub: answers true (no E0xxx map-key diagnostic); see the header.
function map_key_is_hashable(
    db: root.hir.Db,
    facts: root.hir_ty.Facts,
    key: root.types.Ty,
) -> bool throws never {
    true
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_base_without_member_pin @ d9be6853b
function interface_base_without_member_pin(
    db: root.hir.Db,
    base_ty: root.types.Ty,
    member: string,
) -> root.types.DeclName? throws never {
    baml.sys.panic("interface_base_without_member_pin: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_associated_type_default @ d9be6853b
function interface_associated_type_default(
    db: root.hir.Db,
    iface_loc: int,
    name: string,
) -> (root.types.Ty, root.hir_ty.TirTypeError[])? throws never {
    baml.sys.panic("interface_associated_type_default: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::realize_associated_default @ d9be6853b
function realize_associated_default(
    default_: root.types.Ty,
    generic_params: root.types.ParamTy[],
    interface_args: root.types.Ty[],
    self_param: root.types.ParamTy,
    self_ty: root.types.Ty,
) -> root.types.Ty throws never {
    baml.sys.panic("realize_associated_default: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::type_generic_bound_errors @ d9be6853b
// Stub: answers no errors; see the header.
function type_generic_bound_errors(
    db: root.hir.Db,
    scope_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    ty: root.types.LoweringTy,
) -> root.hir_ty.TirTypeError[] throws never {
    []
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::normalized_arg_implements_bound @ d9be6853b
function normalized_arg_implements_bound(
    ctx: root.types.TypeContext,
    arg: root.types.Ty,
    bound: root.types.InterfaceConstraint,
) -> bool throws never {
    baml.sys.panic("normalized_arg_implements_bound: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolve_interface_required_methods @ d9be6853b
// Stub: answers no methods; see the header.
function resolve_interface_required_methods(
    db: root.hir.Db,
    iface_loc: int,
) -> ResolvedInterfaceMethod[] throws never {
    []
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_requires_cycle @ d9be6853b
// Stub: answers no cycle; see the header.
function interface_requires_cycle(db: root.hir.Db, root_: int) -> string[]? throws never {
    null
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::collapse_self_assoc_projections @ d9be6853b
function collapse_self_assoc_projections(
    ty: root.types.Ty,
    self_tys: root.types.Ty[],
    iface: root.types.DeclName?,
    iface_args: root.types.Ty[],
    pins: root.types.AssociatedType[],
) -> root.types.Ty throws never {
    baml.sys.panic("collapse_self_assoc_projections: not ported")
}
