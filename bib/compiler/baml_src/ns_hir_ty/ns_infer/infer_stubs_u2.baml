// Stubs for K4 unit 2 (subtyping, operators, obligations): every function of
// infer/obligations.rs, infer/truthy.rs that the unit owns, in namespace
// `hir_ty.infer`, with its BAML signature. Each panics until the unit ports
// it; the unit replaces this file and deletes it. Signatures follow
// infer.baml's conventions: `InferenceContext` methods take `ctx` first; a
// free function over interned types with no context takes the pool first.

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::has_structure_operator @ d9be6853b
function has_structure_operator(
    ctx: root.hir_ty.InferenceContext,
    ty: int,
    visiting: map<int, bool>,
) -> bool throws never {
    baml.sys.panic("has_structure_operator: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::resolve_structure_operand @ d9be6853b
function resolve_structure_operand(
    ctx: root.hir_ty.InferenceContext,
    ty: int,
    visiting: map<int, bool>,
) -> int throws never {
    baml.sys.panic("resolve_structure_operand: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::register_obligation @ d9be6853b
function register_obligation(
    ctx: root.hir_ty.InferenceContext,
    obligation: Obligation,
) -> void throws never {
    baml.sys.panic("register_obligation: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::discharge_obligations_once @ d9be6853b
function discharge_obligations_once(ctx: root.hir_ty.InferenceContext) -> bool throws never {
    baml.sys.panic("discharge_obligations_once: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::attempt @ d9be6853b
function attempt(
    ctx: root.hir_ty.InferenceContext,
    obligation: Obligation,
) -> Attempt throws never {
    baml.sys.panic("attempt: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::select_impl @ d9be6853b
function select_impl(
    ctx: root.hir_ty.InferenceContext,
    goal: int,
    subject: int,
    interface_: root.types.InferInterfaceConstraint,
    at: int,
    required_for: RequiredFor[],
) -> Selection throws never {
    baml.sys.panic("select_impl: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_unique_impl @ d9be6853b
// Restructured: Rust's `Result<T, E>` is the union `T | E` (an enum `E`
// cannot be thrown from a stub without an extraneous-throws warning).
function confirm_unique_impl(
    ctx: root.hir_ty.InferenceContext,
    goal: int,
    subject: int,
    interface_: root.types.InferInterfaceConstraint,
) -> ConfirmedImpl? | Selection throws never {
    baml.sys.panic("confirm_unique_impl: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::implemented_instantiation @ d9be6853b
function implemented_instantiation(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    name: root.types.DeclName,
    arity: int,
    associated: string[],
) -> InterfaceInstantiation? throws never {
    baml.sys.panic("implemented_instantiation: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::select_object @ d9be6853b
function select_object(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    goal: root.types.InferInterfaceConstraint,
) -> Selection throws never {
    baml.sys.panic("select_object: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::select_param_env @ d9be6853b
function select_param_env(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    goal: root.types.InferInterfaceConstraint,
) -> Selection throws never {
    baml.sys.panic("select_param_env: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_param_head @ d9be6853b
function confirm_param_head(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    head: root.types.InferInterfaceConstraint,
    goal: root.types.InferInterfaceConstraint,
) -> bool throws never {
    baml.sys.panic("confirm_param_head: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::taint_goal_vars @ d9be6853b
function taint_goal_vars(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    interface_: root.types.InferInterfaceConstraint,
) -> void throws never {
    baml.sys.panic("taint_goal_vars: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::report_not_implemented @ d9be6853b
function report_not_implemented(
    ctx: root.hir_ty.InferenceContext,
    at: int,
    subject: int,
    interface_: root.types.InferInterfaceConstraint,
    required_for: RequiredFor[],
) -> void throws never {
    baml.sys.panic("report_not_implemented: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::settle_stalled_obligations @ d9be6853b
function settle_stalled_obligations(ctx: root.hir_ty.InferenceContext) -> void throws never {
    baml.sys.panic("settle_stalled_obligations: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_object @ d9be6853b
function confirm_object(
    ctx: root.hir_ty.InferenceContext,
    head: root.types.InferInterfaceConstraint,
    goal: root.types.InferInterfaceConstraint,
) -> bool throws never {
    baml.sys.panic("confirm_object: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::register_impl_bound_obligations @ d9be6853b
function register_impl_bound_obligations(
    ctx: root.hir_ty.InferenceContext,
    facts: root.hir_ty.ImplFacts,
    instantiation: map<root.types.ParamTy, int>,
    at: int,
    required_for: RequiredFor[],
) -> void throws never {
    baml.sys.panic("register_impl_bound_obligations: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_impl @ d9be6853b
function confirm_impl(
    ctx: root.hir_ty.InferenceContext,
    goal: int,
    interface_: root.types.InferInterfaceConstraint,
    facts: root.hir_ty.ImplFacts,
) -> map<root.types.ParamTy, int>? throws never {
    baml.sys.panic("confirm_impl: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_impl_subject @ d9be6853b
function confirm_impl_subject(
    ctx: root.hir_ty.InferenceContext,
    goal: int,
    facts: root.hir_ty.ImplFacts,
) -> map<root.types.ParamTy, int>? throws never {
    baml.sys.panic("confirm_impl_subject: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::probe_impl_member @ d9be6853b
function probe_impl_member(
    ctx: root.hir_ty.InferenceContext,
    receiver: int,
    name: string,
    at: int,
) -> root.hir_ty.InterfaceMember? throws never {
    baml.sys.panic("probe_impl_member: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::probe_candidate @ d9be6853b
function probe_candidate(
    ctx: root.hir_ty.InferenceContext,
    receiver: int,
    name: string,
    facts: root.hir_ty.ImplFacts,
) -> (root.hir_ty.InterfaceMember, map<root.types.ParamTy, int>)? throws never {
    baml.sys.panic("probe_candidate: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::implements_holds @ d9be6853b
function implements_holds(
    ctx: root.hir_ty.InferenceContext,
    ty: int,
    interface_: root.types.InferInterfaceConstraint,
) -> bool throws never {
    baml.sys.panic("implements_holds: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::resolve_interface_ref @ d9be6853b
function resolve_interface_ref(
    ctx: root.hir_ty.InferenceContext,
    interface_: root.types.InferInterfaceConstraint,
) -> root.types.InferInterfaceConstraint throws never {
    baml.sys.panic("resolve_interface_ref: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::widen_literal @ d9be6853b
function widen_literal(pool: root.types.InferPool, ty: int) -> int throws never {
    baml.sys.panic("widen_literal: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::interface_has_infer @ d9be6853b
function interface_has_infer(interface_: root.types.InferInterfaceConstraint) -> bool throws never {
    baml.sys.panic("interface_has_infer: not ported (U2)")
}

