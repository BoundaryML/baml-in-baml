// Stubs for K4 unit 1 (expressions, statements): every function of infer.rs
// that the unit owns, in namespace `hir_ty`, with its BAML signature. Each
// panics until the unit ports it; the unit replaces this file and deletes it.
// Signatures follow infer.baml's conventions: `InferenceContext` methods take
// `ctx` first; a free function over interned types with no context takes the
// pool first.

// port: baml_compiler2_hir_ty/src/infer.rs::RelaxationVariance @ d9be6853b
enum RelaxationVariance {
    Covariant,
    Contravariant,
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::metadata_key @ d9be6853b
function metadata_key(ctx: InferenceContext, expr: int) -> root.hir.ExprMetadataKey? throws never {
    baml.sys.panic("metadata_key: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr_body @ d9be6853b
function infer_expr_body(ctx: InferenceContext, body: root.ast.ExprBody) -> void throws never {
    baml.sys.panic("infer_expr_body: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::backfill_untyped_patterns @ d9be6853b
function backfill_untyped_patterns(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
) -> void throws never {
    baml.sys.panic("backfill_untyped_patterns: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::register_property_shorthands @ d9be6853b
function register_property_shorthands(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
) -> void throws never {
    baml.sys.panic("register_property_shorthands: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_expr @ d9be6853b
function check_expr(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: int,
) -> int throws never {
    baml.sys.panic("check_expr: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_expr_fits @ d9be6853b
function check_expr_fits(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: int,
) -> (int, bool) throws never {
    baml.sys.panic("check_expr_fits: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_branch @ d9be6853b
function infer_branch(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    branch: int,
    expected: Expectation,
) -> int throws never {
    baml.sys.panic("infer_branch: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_inferred @ d9be6853b
function check_inferred(
    ctx: InferenceContext,
    expr: int,
    ty: int,
    expected: int,
) -> int throws never {
    baml.sys.panic("check_inferred: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_fits @ d9be6853b
function check_fits(ctx: InferenceContext, expr: int, ty: int, expected: int) -> bool throws never {
    baml.sys.panic("check_fits: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr_with_hint @ d9be6853b
function infer_expr_with_hint(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: int?,
) -> int throws never {
    baml.sys.panic("infer_expr_with_hint: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_throw @ d9be6853b
function infer_throw(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    value: int,
) -> void throws never {
    baml.sys.panic("infer_throw: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_return @ d9be6853b
function infer_return(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    value: int?,
    at: DiagnosticLocation,
) -> void throws never {
    baml.sys.panic("infer_return: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::unit_verdict @ d9be6853b
function unit_verdict(ctx: InferenceContext, expected: int?) -> UnitVerdict throws never {
    baml.sys.panic("unit_verdict: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::settle_unit @ d9be6853b
function settle_unit(
    ctx: InferenceContext,
    site: UnitSite,
    verdict: UnitVerdict,
) -> (int, UnitSite?) throws never {
    baml.sys.panic("settle_unit: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::implicit_unit @ d9be6853b
function implicit_unit(
    ctx: InferenceContext,
    expr: int,
    form: UnitSiteForm,
    verdict: UnitVerdict,
) -> int throws never {
    baml.sys.panic("implicit_unit: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::take_units @ d9be6853b
function take_units(ctx: InferenceContext, expr: int) -> UnitSite[] throws never {
    baml.sys.panic("take_units: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::join_units @ d9be6853b
function join_units(
    ctx: InferenceContext,
    parts: (int, UnitSite[])[],
    expected: Expectation,
) -> UnitSite[] throws never {
    baml.sys.panic("join_units: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::is_unit_ty @ d9be6853b
function is_unit_ty(ctx: InferenceContext, ty: int) -> bool throws never {
    baml.sys.panic("is_unit_ty: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_if_branches @ d9be6853b
function infer_if_branches(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    then_branch: int,
    else_branch: int?,
    expected: Expectation,
    enter: (InferenceContext, IfSide) -> void,
) -> int throws never {
    baml.sys.panic("infer_if_branches: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_lone_if @ d9be6853b
function infer_lone_if(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    branch: int,
    expected: Expectation,
) -> int throws never {
    baml.sys.panic("infer_lone_if: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::probe @ d9be6853b
function probe(ctx: InferenceContext) -> ProbeCheckpoint throws never {
    baml.sys.panic("probe: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::rollback_probe @ d9be6853b
function rollback_probe(ctx: InferenceContext, probe: ProbeCheckpoint) -> void throws never {
    baml.sys.panic("rollback_probe: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::owner_function @ d9be6853b
function owner_function(ctx: InferenceContext) -> int? throws never {
    baml.sys.panic("owner_function: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::global_initializer @ d9be6853b
function global_initializer(ctx: InferenceContext) -> string? throws never {
    baml.sys.panic("global_initializer: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::suppressed @ d9be6853b
function suppressed(ctx: InferenceContext, what: Suppress) -> bool throws never {
    baml.sys.panic("suppressed: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::with_suppressed @ d9be6853b
function with_suppressed<R>(
    ctx: InferenceContext,
    what: Suppress,
    f: (InferenceContext) -> R,
) -> R throws never {
    baml.sys.panic("with_suppressed: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report @ d9be6853b
function report(ctx: InferenceContext, diag: PendingDiag) -> void throws never {
    baml.sys.panic("report: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr @ d9be6853b
function infer_expr(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: Expectation,
) -> int throws never {
    baml.sys.panic("infer_expr: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_stmt @ d9be6853b
function infer_stmt(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    stmt: int,
) -> void throws never {
    baml.sys.panic("infer_stmt: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::condition_is_statically_true @ d9be6853b
function condition_is_statically_true(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    condition: int,
) -> bool throws never {
    baml.sys.panic("condition_is_statically_true: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::bind_scoped_type @ d9be6853b
function bind_scoped_type(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    stmt: int,
    name: string,
    operand: int,
    else_branch: int?,
) -> void throws never {
    baml.sys.panic("bind_scoped_type: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::scoped_type_bounds @ d9be6853b
function scoped_type_bounds(
    ctx: InferenceContext,
    stmt: int,
) -> root.types.InterfaceConstraint[] throws never {
    baml.sys.panic("scoped_type_bounds: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish_scoped_type_bindings @ d9be6853b
function finish_scoped_type_bindings(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    checkpoint: int,
    block: int,
    tail: int?,
    block_ty: int,
    expected: Expectation,
) -> int throws never {
    baml.sys.panic("finish_scoped_type_bindings: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::publish_scoped_value @ d9be6853b
function publish_scoped_value(
    ctx: InferenceContext,
    at: int,
    escaped: root.types.ParamTy,
    value: int,
    context: int?,
) -> int throws never {
    baml.sys.panic("publish_scoped_value: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::frame_scoped_param @ d9be6853b
function frame_scoped_param(
    ctx: InferenceContext,
    ty: int,
    floor: int,
) -> root.types.ParamTy? throws never {
    baml.sys.panic("frame_scoped_param: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::generalize_closing_scope @ d9be6853b
function generalize_closing_scope(
    ctx: InferenceContext,
    outer_universe: int,
    closing: root.types.ParamTy[],
    at: int,
) -> void throws never {
    baml.sys.panic("generalize_closing_scope: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::closing_param_in @ d9be6853b
function closing_param_in(
    ctx: InferenceContext,
    ty: int,
    closing: root.types.ParamTy[],
) -> root.types.ParamTy? throws never {
    baml.sys.panic("closing_param_in: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::escaping_scoped_param @ d9be6853b
function escaping_scoped_param(ctx: InferenceContext, ty: int) -> root.types.ParamTy? throws never {
    baml.sys.panic("escaping_scoped_param: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::refuse_with_error_fill @ d9be6853b
function refuse_with_error_fill(ctx: InferenceContext, var: int) -> void throws never {
    baml.sys.panic("refuse_with_error_fill: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_scoped_type_escape @ d9be6853b
function report_scoped_type_escape(
    ctx: InferenceContext,
    at: int,
    param: root.types.ParamTy,
    value: int,
    kind: ScopedTypeEscapeKind,
) -> int throws never {
    baml.sys.panic("report_scoped_type_escape: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::drop_escaping_effects @ d9be6853b
function drop_escaping_effects(
    ctx: InferenceContext,
    channel: (int, int)[],
    declared: int?,
) -> (int, int)[] throws never {
    baml.sys.panic("drop_escaping_effects: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::declared_name_publishes @ d9be6853b
function declared_name_publishes(
    ctx: InferenceContext,
    contribution: int,
    declared: int,
) -> bool throws never {
    baml.sys.panic("declared_name_publishes: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::scoped_type_params @ d9be6853b
function scoped_type_params(ctx: InferenceContext) -> root.types.ParamTy[] throws never {
    baml.sys.panic("scoped_type_params: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::scoped_type_param_heads @ d9be6853b
function scoped_type_param_heads(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
) -> bool throws never {
    baml.sys.panic("scoped_type_param_heads: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::scoped_type_param @ d9be6853b
function scoped_type_param(
    ctx: InferenceContext,
    name: string,
) -> root.types.ParamTy? throws never {
    baml.sys.panic("scoped_type_param: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lower_scoped_type_ref_at @ d9be6853b
function lower_scoped_type_ref_at(
    ctx: InferenceContext,
    store: root.hir.TypeRefStore,
    type_ref: int,
    position: TypePosition,
    holes: HolePolicy,
) -> (root.types.LoweringTy, LoweringDiag[]) throws never {
    baml.sys.panic("lower_scoped_type_ref_at: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::queue_body_lowering_diagnostics @ d9be6853b
function queue_body_lowering_diagnostics(
    ctx: InferenceContext,
    diagnostics: LoweringDiag[],
) -> void throws never {
    baml.sys.panic("queue_body_lowering_diagnostics: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lower_body_type_ref_at @ d9be6853b
function lower_body_type_ref_at(
    ctx: InferenceContext,
    type_ref: root.hir.BodyTypeRefId,
    position: TypePosition,
    holes: HolePolicy,
) -> (root.types.LoweringTy, LoweringDiag[]) throws never {
    baml.sys.panic("lower_body_type_ref_at: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lower_scoped_type_path @ d9be6853b
function lower_scoped_type_path(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
) -> root.types.LoweringTy throws never {
    baml.sys.panic("lower_scoped_type_path: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_let @ d9be6853b
function infer_let(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    pattern: int,
    initializer: int?,
    else_branch: int?,
) -> void throws never {
    baml.sys.panic("infer_let: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_assign @ d9be6853b
function infer_assign(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    target: int,
    value: int,
    op: root.ast.AssignOp?,
) -> void throws never {
    baml.sys.panic("infer_assign: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_path_assignment_target @ d9be6853b
function check_path_assignment_target(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    target: int,
) -> void throws never {
    baml.sys.panic("check_path_assignment_target: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::pattern_ascription_ty @ d9be6853b
function pattern_ascription_ty(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    sub: int,
) -> int? throws never {
    baml.sys.panic("pattern_ascription_ty: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish_let_else @ d9be6853b
function finish_let_else(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    else_branch: int?,
) -> void throws never {
    baml.sys.panic("finish_let_else: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::RelaxationVariance::flip @ d9be6853b
function relaxation_variance_flip(
    relaxation_variance: RelaxationVariance,
) -> RelaxationVariance throws never {
    baml.sys.panic("relaxation_variance_flip: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::RelaxationVariance::bound @ d9be6853b
function relaxation_variance_bound(
    relaxation_variance: RelaxationVariance,
) -> root.types.Ty throws never {
    baml.sys.panic("relaxation_variance_bound: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::nearest_scoped_relaxation @ d9be6853b
function nearest_scoped_relaxation(
    ty: root.types.Ty,
    variance: RelaxationVariance,
) -> root.types.Ty throws never {
    baml.sys.panic("nearest_scoped_relaxation: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::scoped_params_in @ d9be6853b
function scoped_params_in(
    pool: root.types.InferPool,
    ty: int,
    visit: (root.types.ParamTy) -> void,
) -> void throws never {
    baml.sys.panic("scoped_params_in: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::may_become_unit @ d9be6853b
function may_become_unit(pool: root.types.InferPool, ty: int) -> bool throws never {
    baml.sys.panic("may_become_unit: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::value_tail @ d9be6853b
function value_tail(body: root.ast.ExprBody, expr: int) -> int throws never {
    baml.sys.panic("value_tail: not ported (U1)")
}
