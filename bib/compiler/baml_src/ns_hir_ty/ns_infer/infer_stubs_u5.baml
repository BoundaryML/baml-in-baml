// Stubs for K4 unit 5 (patterns, effects): every function of infer/pat.rs
// that the unit owns, in namespace `hir_ty.infer`, with its BAML signature.
// Each panics until the unit ports it; the unit replaces this file and
// deletes it. Signatures follow infer.baml's conventions: `InferenceContext`
// methods take `ctx` first; a free function over interned types with no
// context takes the pool first.

// port: baml_compiler2_hir_ty/src/infer/pat.rs::PatternOutcome @ d9be6853b
// What lowering one pattern learned: its exhaustiveness pattern, the type it
// matches, and whether it covers its scrutinee or its own matched type.
class PatternOutcome {
    dpat: root.hir_ty.DPat,
    matched_ty: int,
    // The WRITTEN form to record when it differs from `matched_ty`.
    recorded_ty: int?,
    covers_type: bool,
    consumes_matched: bool,
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::ListHolding @ d9be6853b
// The lists a list pattern can match among one type's values.
type ListHolding = ListHoldingElements | ListHoldingAnyElements;

// Lists of exactly this element type.
class ListHoldingElements {
    value: int,
}

// Lists of any element type, among other values.
class ListHoldingAnyElements {
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::infer_match @ d9be6853b
function infer_match(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    match_expr: int,
    scrutinee: int,
    arms: int[],
    expected: root.hir_ty.Expectation,
) -> int throws never {
    baml.sys.panic("infer_match: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::scrutinee_demand @ d9be6853b
function scrutinee_demand(ctx: root.hir_ty.InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("scrutinee_demand: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::infer_is @ d9be6853b
function infer_is(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    scrutinee: int,
    pattern: int,
    position: TestPosition,
) -> (int, CondFacts) throws never {
    baml.sys.panic("infer_is: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::infer_let_destructure @ d9be6853b
function infer_let_destructure(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pattern: int,
    initializer: int?,
    has_else: bool,
) -> void throws never {
    baml.sys.panic("infer_let_destructure: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_informative_ty @ d9be6853b
function pattern_informative_ty(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
) -> int? throws never {
    baml.sys.panic("pattern_informative_ty: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::matrix_scrut @ d9be6853b
function matrix_scrut(ctx: root.hir_ty.InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("matrix_scrut: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::narrowable_binding @ d9be6853b
function narrowable_binding(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
) -> root.hir.BindingId? throws never {
    baml.sys.panic("narrowable_binding: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_pattern @ d9be6853b
function lower_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    scrut: int,
) -> PatternOutcome throws never {
    baml.sys.panic("lower_pattern: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_pattern_reaching @ d9be6853b
function lower_pattern_reaching(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    scrut: int,
    reaching: int,
) -> PatternOutcome throws never {
    baml.sys.panic("lower_pattern_reaching: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_pattern_inner @ d9be6853b
function lower_pattern_inner(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    scrut: int,
    reaching: int,
) -> PatternOutcome throws never {
    baml.sys.panic("lower_pattern_inner: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_interface_pattern @ d9be6853b
function lower_interface_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    interface_: int,
    path: string[],
    field_pats: (string, int)[],
    scrut: int,
) -> PatternOutcome throws never {
    baml.sys.panic("lower_interface_pattern: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::type_pattern_outcome @ d9be6853b
function type_pattern_outcome(
    ctx: root.hir_ty.InferenceContext,
    pat: int,
    scrut: int,
    pat_ty: int,
) -> PatternOutcome throws never {
    baml.sys.panic("type_pattern_outcome: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::tuple_type_test_never_matches @ d9be6853b
function tuple_type_test_never_matches(
    ctx: root.hir_ty.InferenceContext,
    scrut: int,
    pat_ty: int,
) -> bool throws never {
    baml.sys.panic("tuple_type_test_never_matches: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::dead_pattern_is_quiet @ d9be6853b
function dead_pattern_is_quiet(ctx: root.hir_ty.InferenceContext) -> bool throws never {
    baml.sys.panic("dead_pattern_is_quiet: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::check_pattern_type_overlap @ d9be6853b
function check_pattern_type_overlap(
    ctx: root.hir_ty.InferenceContext,
    pat: int,
    scrut: int,
    pat_ty: int,
) -> void throws never {
    baml.sys.panic("check_pattern_type_overlap: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::provably_disjoint @ d9be6853b
function provably_disjoint(
    ctx: root.hir_ty.InferenceContext,
    scrut: int,
    pat_ty: int,
) -> bool throws never {
    baml.sys.panic("provably_disjoint: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_matchable @ d9be6853b
function pattern_matchable(
    ctx: root.hir_ty.InferenceContext,
    pat: root.types.Ty,
    scrut: root.types.Ty,
) -> bool throws never {
    baml.sys.panic("pattern_matchable: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_overlaps_scrut_member @ d9be6853b
function pattern_overlaps_scrut_member(
    ctx: root.hir_ty.InferenceContext,
    pat: root.types.Ty,
    scrut: root.types.Ty,
) -> bool throws never {
    baml.sys.panic("pattern_overlaps_scrut_member: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::flatten_union_members @ d9be6853b
function flatten_union_members(
    ctx: root.hir_ty.InferenceContext,
    ty: root.types.Ty,
) -> root.types.Ty[] throws never {
    baml.sys.panic("flatten_union_members: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::expand_alias_chain @ d9be6853b
function expand_alias_chain(
    ctx: root.hir_ty.InferenceContext,
    ty: root.types.Ty,
) -> root.types.Ty throws never {
    baml.sys.panic("expand_alias_chain: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::type_pattern_outcome_inner @ d9be6853b
function type_pattern_outcome_inner(
    ctx: root.hir_ty.InferenceContext,
    scrut: int,
    pat_ty: int,
) -> PatternOutcome throws never {
    baml.sys.panic("type_pattern_outcome_inner: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::narrow_to @ d9be6853b
function narrow_to(ctx: root.hir_ty.InferenceContext, scrut: int, pat_ty: int) -> int throws never {
    baml.sys.panic("narrow_to: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::dpat_for_type @ d9be6853b
function dpat_for_type(
    ctx: root.hir_ty.InferenceContext,
    pat_ty: int,
    col: int,
) -> root.hir_ty.DPat throws never {
    baml.sys.panic("dpat_for_type: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_class_pattern @ d9be6853b
function lower_class_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    class_path: string[],
    field_pats: (string, int)[],
    scrut: int,
) -> PatternOutcome throws never {
    baml.sys.panic("lower_class_pattern: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_tuple_pattern @ d9be6853b
function lower_tuple_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    elements: int[],
    scrut: int,
) -> PatternOutcome throws never {
    baml.sys.panic("lower_tuple_pattern: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_tuple_elements @ d9be6853b
function lower_tuple_elements(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    elements: int[],
    slots: int[],
    tuple_ty: int,
) -> PatternOutcome throws never {
    baml.sys.panic("lower_tuple_elements: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_array_pattern @ d9be6853b
function lower_array_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    prefix: int[],
    rest: root.ast.ArrayRestPat?,
    suffix: int[],
    scrut: int,
) -> PatternOutcome throws never {
    baml.sys.panic("lower_array_pattern: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::collect_list_holders @ d9be6853b
function collect_list_holders(
    ctx: root.hir_ty.InferenceContext,
    ty: int,
    unfolding: int[],
    holders: (int, ListHolding)[],
) -> bool throws never {
    baml.sys.panic("collect_list_holders: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_fits @ d9be6853b
function pattern_fits(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    ty: int,
) -> bool throws never {
    baml.sys.panic("pattern_fits: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::tuple_element_fits @ d9be6853b
function tuple_element_fits(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    sub: int,
    slot: int,
) -> bool throws never {
    baml.sys.panic("tuple_element_fits: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::class_head_fits @ d9be6853b
function class_head_fits(
    ctx: root.hir_ty.InferenceContext,
    class_path: string[],
    ty: int,
) -> bool throws never {
    baml.sys.panic("class_head_fits: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::class_pattern_field_types @ d9be6853b
function class_pattern_field_types(
    ctx: root.hir_ty.InferenceContext,
    qtn: root.types.DeclName,
    args: int[],
) -> int[] throws never {
    baml.sys.panic("class_pattern_field_types: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_field_ty @ d9be6853b
function pattern_field_ty(
    ctx: root.hir_ty.InferenceContext,
    declared: int,
    args: int[],
) -> int throws never {
    baml.sys.panic("pattern_field_ty: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::reduced_for_pattern @ d9be6853b
function reduced_for_pattern(ctx: root.hir_ty.InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("reduced_for_pattern: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::dpat_ty @ d9be6853b
function dpat_ty(pool: root.types.InferPool, ty: int) -> root.types.Ty throws never {
    baml.sys.panic("dpat_ty: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::binds_without_a_type @ d9be6853b
function binds_without_a_type(body: root.ast.ExprBody, pat: int) -> bool throws never {
    baml.sys.panic("binds_without_a_type: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::takes_every_value @ d9be6853b
function takes_every_value(body: root.ast.ExprBody, pat: int) -> bool throws never {
    baml.sys.panic("takes_every_value: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::rest_pattern_shape_ok @ d9be6853b
function rest_pattern_shape_ok(body: root.ast.ExprBody, pat: int) -> bool throws never {
    baml.sys.panic("rest_pattern_shape_ok: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::scrut_members @ d9be6853b
function scrut_members(pool: root.types.InferPool, scrut: int) -> int[] throws never {
    baml.sys.panic("scrut_members: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::tuple_pattern_is_open @ d9be6853b
function tuple_pattern_is_open(pool: root.types.InferPool, ty: int) -> bool throws never {
    baml.sys.panic("tuple_pattern_is_open: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::list_holding @ d9be6853b
function list_holding(pool: root.types.InferPool, ty: int) -> ListHolding? throws never {
    baml.sys.panic("list_holding: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::collect_bind_types @ d9be6853b
function collect_bind_types(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    out: (string, int)[],
) -> void throws never {
    baml.sys.panic("collect_bind_types: not ported (U5)")
}
