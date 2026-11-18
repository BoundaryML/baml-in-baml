// port: baml_compiler2_hir_ty/src/impls.rs @ d9be6853b
//
// Not ported (package K3). The data types and stubs that facts.rs and
// lower.rs read.
//
// Restructured: Rust's interned `Ty` is a handle into a global pool; here it
// is an `int` into `db.ty_memo.pool`. A function with no `db` takes the pool
// first.

// port: baml_compiler2_hir_ty/src/impls.rs::ImplFacts @ d9be6853b
// One resolved impl header. Not ported: `methods`.
class ImplFacts {
    interface_: root.types.ClosedInterface,
    for_ty_pattern: root.types.ClosedTy,
    generic_params: (root.types.ParamTy, root.types.ClosedInterface[])[],
    associated_types: (string, root.types.ClosedTy)[],
}

// port: baml_compiler2_hir_ty/src/impls.rs::ImplHeaderResolution @ d9be6853b
// One impl block's header resolution.
type ImplHeaderResolution = ImplHeaderResolutionUnresolved
    | ImplHeaderResolutionPoisoned
    | ImplHeaderResolutionNotImplementor
    | ImplHeaderResolutionResolved;

class ImplHeaderResolutionUnresolved {
}

class ImplHeaderResolutionPoisoned {
    unconstrained: string[],
}

class ImplHeaderResolutionNotImplementor {
    // The written subject, as lowered: the E0138 payload.
    target: root.types.Ty,
    facts: ImplFacts,
}

class ImplHeaderResolutionResolved {
    value: ImplFacts,
}

// port: baml_compiler2_hir_ty/src/impls.rs::ImplHeaderResolution::for_display @ d9be6853b
// The facts to show for the header, resolved or not an implementor.
function impl_header_resolution_for_display(
    resolution: ImplHeaderResolution,
) -> ImplFacts? throws never {
    match (resolution) {
        let r: ImplHeaderResolutionResolved => r.value,
        let r: ImplHeaderResolutionNotImplementor => r.facts,
        ImplHeaderResolutionUnresolved | ImplHeaderResolutionPoisoned => null,
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::AliasOnlyFacts @ d9be6853b
// The fact-poor equality impl matching uses. Not ported: its memo and its
// `TypeContext` impl.
class AliasOnlyFacts {
    db: root.hir.Db,
}

// port: baml_compiler2_hir_ty/src/impls.rs::ResolvedImpl @ d9be6853b
// A selected implementation. Not ported: its fields.
class ResolvedImpl {
    // port: baml_compiler2_hir_ty/src/impls.rs::ResolvedImpl::implemented_view @ d9be6853b
    function implemented_view(
        self,
        db: root.hir.Db,
        self_ty: int,
    ) -> root.types.InferInterfaceConstraint throws never {
        baml.sys.panic("ResolvedImpl::implemented_view: not ported")
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::ResolvedImplementation @ d9be6853b
// An explicit implementation, or the language-provided structural default.
type ResolvedImplementation = ResolvedImplementationExplicit
    | ResolvedImplementationStructuralDefault;

class ResolvedImplementationExplicit {
    value: ResolvedImpl,
}

class ResolvedImplementationStructuralDefault {
    value: root.types.StructuralInterface,
}

// port: baml_compiler2_hir_ty/src/impls.rs::REQUIRES_CLOSURE_FUEL @ d9be6853b
const REQUIRES_CLOSURE_FUEL: int = 64;

// port: baml_compiler2_hir_ty/src/impls.rs::resolve_implementation @ d9be6853b
function resolve_implementation(
    db: root.hir.Db,
    concrete: int,
    interface_: root.types.InferInterfaceConstraint,
) -> ResolvedImplementation? throws never {
    baml.sys.panic("resolve_implementation: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::structural_interface_roots @ d9be6853b
function structural_interface_roots(
    db: root.hir.Db,
) -> root.types.InferInterfaceConstraint[] throws never {
    baml.sys.panic("structural_interface_roots: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::structural_interface @ d9be6853b
function structural_interface(
    db: root.hir.Db,
    name: root.types.DeclName,
) -> root.types.StructuralInterface? throws never {
    baml.sys.panic("structural_interface: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::is_structural_interface @ d9be6853b
function is_structural_interface(
    db: root.hir.Db,
    interface_: root.types.InferInterfaceConstraint,
) -> bool throws never {
    baml.sys.panic("is_structural_interface: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::demote_concrete_type_member @ d9be6853b
// Edits `declarers` in place.
function demote_concrete_type_member<T>(
    lang: root.base.LangRoots,
    member: string,
    declarers: T[],
    interface_: (T) -> root.types.DeclName,
) -> void {
    baml.sys.panic("demote_concrete_type_member: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::impl_views_for_type @ d9be6853b
function impl_views_for_type(
    db: root.hir.Db,
    viewer: int,
    concrete: root.types.Ty,
    structural: (root.types.DeclName) -> bool,
) -> root.types.InterfaceConstraint[] {
    baml.sys.panic("impl_views_for_type: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::direct_requires_closure_plain @ d9be6853b
function direct_requires_closure_plain(
    db: root.hir.Db,
    root_: root.types.InterfaceConstraint,
    self_ty: root.types.Ty,
    fuel: int,
) -> root.types.InterfaceConstraint[] throws never {
    baml.sys.panic("direct_requires_closure_plain: not ported")
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::prefer_explicit_members @ d9be6853b
// Edits `candidates` in place.
function prefer_explicit_members<T>(
    db: root.hir.Db,
    viewer: int,
    facts: Facts,
    receiver: int,
    candidates: T[],
    interface_: (T) -> root.types.InferInterfaceConstraint,
) -> void {
    baml.sys.panic("prefer_explicit_members: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::impl_facts @ d9be6853b
// One impl block's header resolution.
function impl_facts(db: root.hir.Db, block: int) -> ImplHeaderResolution throws never {
    baml.sys.panic("impl_facts: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::interned_ty @ d9be6853b
function interned_ty(pool: root.types.InferPool, ty: root.types.Ty) -> int throws never {
    baml.sys.panic("interned_ty: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::try_interned_ty @ d9be6853b
function try_interned_ty(pool: root.types.InferPool, ty: root.types.Ty) -> int? throws never {
    baml.sys.panic("try_interned_ty: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::conditional_structural_verdict @ d9be6853b
function conditional_structural_verdict(
    db: root.hir.Db,
    facts: Facts,
    ty: int,
    interface_: root.types.InferInterfaceConstraint,
) -> bool? throws never {
    baml.sys.panic("conditional_structural_verdict: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::implements_interface @ d9be6853b
function implements_interface(
    db: root.hir.Db,
    concrete: int,
    interface_: root.types.InferInterfaceConstraint,
) -> bool throws never {
    baml.sys.panic("implements_interface: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::interface_requires @ d9be6853b
function interface_requires(
    db: root.hir.Db,
    sub: root.types.InferInterfaceConstraint,
    sup: root.types.InferInterfaceConstraint,
    self_ty: int,
    fuel: int,
) -> bool throws never {
    baml.sys.panic("interface_requires: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::realized_assoc_bound_plain @ d9be6853b
function realized_assoc_bound_plain(
    db: root.hir.Db,
    target: root.types.InterfaceConstraint,
    self_ty: root.types.Ty,
    member: string,
) -> root.types.Ty? throws never {
    baml.sys.panic("realized_assoc_bound_plain: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::requires_heads @ d9be6853b
function requires_heads(
    db: root.hir.Db,
    root_: root.types.InferInterfaceConstraint,
    self_ty: int,
    fuel: int,
) -> root.types.InferInterfaceConstraint[] throws never {
    baml.sys.panic("requires_heads: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::head_matches @ d9be6853b
function head_matches(
    have: root.types.InferInterfaceConstraint,
    want: root.types.InferInterfaceConstraint,
    eq: AliasOnlyFacts,
) -> bool throws never {
    baml.sys.panic("head_matches: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::eq_admitted @ d9be6853b
// Restructured: Rust's `eq: &impl TypeContext` is the one context facts.rs
// passes, `AliasOnlyFacts`.
function eq_admitted(a: int, b: int, eq: AliasOnlyFacts) -> bool throws never {
    baml.sys.panic("eq_admitted: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::realized_assoc_default @ d9be6853b
function realized_assoc_default(
    db: root.hir.Db,
    target: root.types.InferInterfaceConstraint,
    self_ty: int,
    member: string,
) -> int? throws never {
    baml.sys.panic("realized_assoc_default: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::resolve_impl @ d9be6853b
function resolve_impl(
    db: root.hir.Db,
    concrete: int,
    interface_: root.types.InferInterfaceConstraint,
) -> ResolvedImpl? throws never {
    baml.sys.panic("resolve_impl: not ported")
}

// port: baml_compiler2_hir_ty/src/impls.rs::resolved_pin @ d9be6853b
function resolved_pin(
    db: root.hir.Db,
    resolved: ResolvedImpl,
    self_ty: int,
    member: string,
) -> int? throws never {
    baml.sys.panic("resolved_pin: not ported")
}
