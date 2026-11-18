// Stubs for K4 unit 6 (queries, finish): every function of infer.rs that the
// unit owns, in namespace `hir_ty`, with its BAML signature. Each panics
// until the unit ports it; the unit replaces this file and deletes it.
// Signatures follow infer.baml's conventions: `InferenceContext` methods take
// `ctx` first; a free function over interned types with no context takes the
// pool first.

// port: baml_compiler2_hir_ty/src/infer.rs::LetOwnerKey @ d9be6853b
// A top-level let's identity across queries: its file's path and item id.
type LetOwnerKey = (string, int);

// port: baml_compiler2_hir_ty/src/infer.rs::InFlightLetOwner @ d9be6853b
class InFlightLetOwner {
    key: LetOwnerKey,
    inserted: bool,

    // port: baml_compiler2_hir_ty/src/infer.rs::InFlightLetOwner::enter @ d9be6853b
    function enter(db: root.hir.Db, let_binding: int) -> InFlightLetOwner throws never {
        baml.sys.panic("enter: not ported (U6)")
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_function_body_cycle_initial @ d9be6853b
function infer_function_body_cycle_initial(
    db: root.hir.Db,
    id: int,
    function_: int,
) -> InferenceResult<root.types.Ty> throws never {
    baml.sys.panic("infer_function_body_cycle_initial: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::let_owner_key @ d9be6853b
function let_owner_key(db: root.hir.Db, let_binding: int) -> LetOwnerKey throws never {
    baml.sys.panic("let_owner_key: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::let_owner_is_in_flight @ d9be6853b
function let_owner_is_in_flight(db: root.hir.Db, let_binding: int) -> bool throws never {
    baml.sys.panic("let_owner_is_in_flight: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_let_body_cycle_initial @ d9be6853b
function infer_let_body_cycle_initial(
    db: root.hir.Db,
    id: int,
    let_binding: int,
) -> InferenceResult<root.types.Ty> throws never {
    baml.sys.panic("infer_let_body_cycle_initial: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_function_body @ d9be6853b
function infer_function_body(
    db: root.hir.Db,
    function_: int,
) -> InferenceResult<root.types.Ty> throws never {
    baml.sys.panic("infer_function_body: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_let_body @ d9be6853b
function infer_let_body(
    db: root.hir.Db,
    let_binding: int,
) -> InferenceResult<root.types.Ty> throws never {
    baml.sys.panic("infer_let_body: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_parameter_defaults @ d9be6853b
function infer_parameter_defaults(
    db: root.hir.Db,
    function_: int,
) -> InferenceResult<root.types.Ty> throws never {
    baml.sys.panic("infer_parameter_defaults: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::owner_declared_bounds @ d9be6853b
function owner_declared_bounds(
    db: root.hir.Db,
    owner: root.hir.BodyOwnerId,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    baml.sys.panic("owner_declared_bounds: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_body @ d9be6853b
function infer_body(
    db: root.hir.Db,
    owner: root.hir.BodyOwnerId,
) -> InferenceResult<root.types.Ty> throws never {
    baml.sys.panic("infer_body: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::body_inferences @ d9be6853b
function body_inferences() -> int throws never {
    baml.sys.panic("body_inferences: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_body_impl @ d9be6853b
function infer_body_impl(
    db: root.hir.Db,
    owner: root.hir.BodyOwnerId,
) -> InferenceResult<root.types.Ty> throws never {
    baml.sys.panic("infer_body_impl: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::take_unresolved_infer_diagnostics @ d9be6853b
function take_unresolved_infer_diagnostics(
    ctx: InferenceContext,
) -> (DiagnosticLocation, TirTypeError)[] throws never {
    baml.sys.panic("take_unresolved_infer_diagnostics: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::taint_classes_owned_by_mismatches @ d9be6853b
function taint_classes_owned_by_mismatches(ctx: InferenceContext) -> void throws never {
    baml.sys.panic("taint_classes_owned_by_mismatches: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::direct_mismatch_holds @ d9be6853b
function direct_mismatch_holds(
    ctx: InferenceContext,
    expected: int,
    actual: int,
) -> bool throws never {
    baml.sys.panic("direct_mismatch_holds: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::taint_classes_owned_by_value_reports @ d9be6853b
function taint_classes_owned_by_value_reports(ctx: InferenceContext) -> void throws never {
    baml.sys.panic("taint_classes_owned_by_value_reports: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::solve_conflicting_classes_from_their_demand @ d9be6853b
function solve_conflicting_classes_from_their_demand(ctx: InferenceContext) -> bool throws never {
    baml.sys.panic("solve_conflicting_classes_from_their_demand: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::effect_default_keep_open @ d9be6853b
function effect_default_keep_open(ctx: InferenceContext) -> int[] throws never {
    baml.sys.panic("effect_default_keep_open: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::solve_conflicting_class_from_its_demand @ d9be6853b
function solve_conflicting_class_from_its_demand(
    ctx: InferenceContext,
    var: int,
    bounds: root.hir_ty.infer.VarBounds,
) -> bool throws never {
    baml.sys.panic("solve_conflicting_class_from_its_demand: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::conflicting_lower_bounds @ d9be6853b
function conflicting_lower_bounds(ctx: InferenceContext, root_id: int) -> (int, int)? throws never {
    baml.sys.panic("conflicting_lower_bounds: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::take_unsolved_hole_diagnostics @ d9be6853b
function take_unsolved_hole_diagnostics(
    ctx: InferenceContext,
) -> (DiagnosticLocation, TirTypeError)[] throws never {
    baml.sys.panic("take_unsolved_hole_diagnostics: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::take_writeback_backstop_diagnostics @ d9be6853b
function take_writeback_backstop_diagnostics(
    ctx: InferenceContext,
) -> (DiagnosticLocation, TirTypeError)[] throws never {
    baml.sys.panic("take_writeback_backstop_diagnostics: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::open_classes_owned @ d9be6853b
function open_classes_owned(ctx: InferenceContext, ty: int) -> bool throws never {
    baml.sys.panic("open_classes_owned: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::unsolved_undiagnosed_root @ d9be6853b
function unsolved_undiagnosed_root(ctx: InferenceContext, var: int) -> int? throws never {
    baml.sys.panic("unsolved_undiagnosed_root: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
function finish(
    ctx: InferenceContext,
    body: root.ast.ExprBody?,
) -> InferenceResult<root.types.Ty> throws never {
    baml.sys.panic("finish: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::required_for_notes @ d9be6853b
function required_for_notes(
    ctx: InferenceContext,
    at: int,
    required_for: root.hir_ty.infer.RequiredFor[],
) -> RelatedNote[] throws never {
    baml.sys.panic("required_for_notes: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::with_unsolved_pins_elided @ d9be6853b
function with_unsolved_pins_elided(ctx: InferenceContext, interface_: int) -> int throws never {
    baml.sys.panic("with_unsolved_pins_elided: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::plain_finalized @ d9be6853b
function plain_finalized(ctx: InferenceContext, ty: int) -> root.types.Ty throws never {
    baml.sys.panic("plain_finalized: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finalize_ty @ d9be6853b
function finalize_ty(ctx: InferenceContext, ty: int) -> root.types.ClosedTy throws never {
    baml.sys.panic("finalize_ty: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finalize_emission_ty @ d9be6853b
function finalize_emission_ty(ctx: InferenceContext, ty: int) -> root.types.ClosedTy throws never {
    baml.sys.panic("finalize_emission_ty: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::deduped_unions @ d9be6853b
function deduped_unions(ctx: InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("deduped_unions: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::deduped_unions_memo @ d9be6853b
function deduped_unions_memo(
    ctx: InferenceContext,
    ty: int,
    memo: map<int, int>,
) -> int throws never {
    baml.sys.panic("deduped_unions_memo: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::reduce_projections @ d9be6853b
function reduce_projections(
    ctx: InferenceContext,
    ty: root.types.ClosedTy,
    fuel: int,
) -> root.types.ClosedTy throws never {
    baml.sys.panic("reduce_projections: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::iteration_item @ d9be6853b
function iteration_item(ctx: InferenceContext, collection: int, at: int) -> int throws never {
    baml.sys.panic("iteration_item: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::canonicalize_unions @ d9be6853b
function canonicalize_unions(
    ctx: InferenceContext,
    ty: root.types.ClosedTy,
) -> root.types.ClosedTy throws never {
    baml.sys.panic("canonicalize_unions: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::resolve_bounded_vars @ d9be6853b
function resolve_bounded_vars(ctx: InferenceContext, tier: SolveTier) -> bool throws never {
    baml.sys.panic("resolve_bounded_vars: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::try_solve_bounded_var_tiered @ d9be6853b
function try_solve_bounded_var_tiered(
    ctx: InferenceContext,
    var: int,
    bounds: root.hir_ty.infer.VarBounds,
    tier: SolveTier,
) -> bool throws never {
    baml.sys.panic("try_solve_bounded_var_tiered: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::try_solve_bounded_var @ d9be6853b
function try_solve_bounded_var(
    ctx: InferenceContext,
    var: int,
    bounds: root.hir_ty.infer.VarBounds,
) -> bool throws never {
    baml.sys.panic("try_solve_bounded_var: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_contradictory_bounds @ d9be6853b
function report_contradictory_bounds(ctx: InferenceContext) -> void throws never {
    baml.sys.panic("report_contradictory_bounds: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lowers_join @ d9be6853b
function lowers_join(ctx: InferenceContext, lowers: int[], uppers: int[]) -> int? throws never {
    baml.sys.panic("lowers_join: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::structurally_resolve @ d9be6853b
function structurally_resolve(ctx: InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("structurally_resolve: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::force_occurring_vars @ d9be6853b
function force_occurring_vars(ctx: InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("force_occurring_vars: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::callback_param_for_effect @ d9be6853b
function callback_param_for_effect(
    ctx: InferenceContext,
    effect: root.types.ParamTy,
) -> string? throws never {
    baml.sys.panic("callback_param_for_effect: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::local_binding_names_at @ d9be6853b
function local_binding_names_at(ctx: InferenceContext, expr: int) -> string[] throws never {
    baml.sys.panic("local_binding_names_at: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::first_failing_blanket_bound @ d9be6853b
function first_failing_blanket_bound(
    ctx: InferenceContext,
    actual: int,
    expected: int,
) -> root.types.Ty? throws never {
    baml.sys.panic("first_failing_blanket_bound: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::pattern_overlap_verdict @ d9be6853b
function pattern_overlap_verdict(
    ctx: InferenceContext,
    pat: root.types.Ty,
    member: root.types.Ty,
) -> root.types.Overlap throws never {
    baml.sys.panic("pattern_overlap_verdict: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::overlap_alias_map @ d9be6853b
function overlap_alias_map(
    ctx: InferenceContext,
) -> map<root.types.DeclName, root.types.Ty> throws never {
    baml.sys.panic("overlap_alias_map: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::replay_solved_class_bounds @ d9be6853b
function replay_solved_class_bounds(ctx: InferenceContext) -> bool throws never {
    baml.sys.panic("replay_solved_class_bounds: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::drain_deferred_subs @ d9be6853b
function drain_deferred_subs(ctx: InferenceContext) -> bool throws never {
    baml.sys.panic("drain_deferred_subs: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::skolemize_infer @ d9be6853b
function skolemize_infer(pool: root.types.InferPool, ty: int) -> int throws never {
    baml.sys.panic("skolemize_infer: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::collect_infer_vars @ d9be6853b
function collect_infer_vars(pool: root.types.InferPool, ty: int, out: int[]) -> void throws never {
    baml.sys.panic("collect_infer_vars: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::same_head_constructor @ d9be6853b
function same_head_constructor(
    pool: root.types.InferPool,
    source: int,
    target: int,
) -> bool throws never {
    baml.sys.panic("same_head_constructor: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::mentions_param_as_value @ d9be6853b
function mentions_param_as_value(
    pool: root.types.InferPool,
    ty: int,
    param: root.types.ParamTy,
) -> bool throws never {
    baml.sys.panic("mentions_param_as_value: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::throws_mentions_param_as_value @ d9be6853b
function throws_mentions_param_as_value(
    pool: root.types.InferPool,
    throws_: int,
    param: root.types.ParamTy,
) -> bool throws never {
    baml.sys.panic("throws_mentions_param_as_value: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::function_user_generic_params @ d9be6853b
function function_user_generic_params(
    db: root.hir.Db,
    function_: int,
    signature: FunctionSignature,
) -> root.types.ParamTy[] throws never {
    baml.sys.panic("function_user_generic_params: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::signature_mentions_param @ d9be6853b
function signature_mentions_param(
    signature: FunctionSignatureTy,
    throws_: root.types.Ty,
    param: root.types.ParamTy,
) -> bool throws never {
    baml.sys.panic("signature_mentions_param: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::throws_clause_union @ d9be6853b
function throws_clause_union(facts: root.types.Ty[]) -> root.types.Ty? throws never {
    baml.sys.panic("throws_clause_union: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::mentions_scoped_param @ d9be6853b
function mentions_scoped_param(ty: root.types.Ty) -> bool throws never {
    baml.sys.panic("mentions_scoped_param: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_ty @ d9be6853b
function materialize_ty(ctx: InferenceContext, ty: int) -> root.types.Ty throws never {
    baml.sys.panic("materialize_ty: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_interface @ d9be6853b
function materialize_interface(
    ctx: InferenceContext,
    iface: root.types.InferInterfaceConstraint,
) -> root.types.InterfaceConstraint throws never {
    baml.sys.panic("materialize_interface: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_result @ d9be6853b
function materialize_result(
    ctx: InferenceContext,
    working: InferenceResult<int>,
) -> InferenceResult<root.types.Ty> throws never {
    baml.sys.panic("materialize_result: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_member_resolution @ d9be6853b
function materialize_member_resolution(
    ctx: InferenceContext,
    resolution: WorkingMemberResolution,
) -> MemberResolution throws never {
    baml.sys.panic("materialize_member_resolution: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_call_plan @ d9be6853b
function materialize_call_plan(
    ctx: InferenceContext,
    plan: CallPlan<int>,
) -> CallPlan<root.types.Ty> throws never {
    baml.sys.panic("materialize_call_plan: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::diagnostic_example_ty @ d9be6853b
function diagnostic_example_ty(pool: root.types.InferPool, ty: int) -> int throws never {
    baml.sys.panic("diagnostic_example_ty: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::finalize_member_resolution @ d9be6853b
function finalize_member_resolution(
    ctx: InferenceContext,
    resolution: WorkingMemberResolution,
) -> void throws never {
    baml.sys.panic("finalize_member_resolution: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::erase_infer @ d9be6853b
function erase_infer(pool: root.types.InferPool, ty: int) -> root.types.ClosedTy throws never {
    baml.sys.panic("erase_infer: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::rendered_plain @ d9be6853b
function rendered_plain(pool: root.types.InferPool, ty: int) -> root.types.Ty throws never {
    baml.sys.panic("rendered_plain: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_to_diagnostic_unknown @ d9be6853b
function infer_to_diagnostic_unknown(pool: root.types.InferPool, ty: int) -> int throws never {
    baml.sys.panic("infer_to_diagnostic_unknown: not ported (U6)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::widen_fresh_literal @ d9be6853b
function widen_fresh_literal(pool: root.types.InferPool, ty: int) -> int throws never {
    baml.sys.panic("widen_fresh_literal: not ported (U6)")
}
