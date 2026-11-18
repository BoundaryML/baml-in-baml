// Stubs for K4 unit 5 (patterns, effects): every function of infer.rs that
// the unit owns, in namespace `hir_ty`, with its BAML signature. Each panics
// until the unit ports it; the unit replaces this file and deletes it.
// Signatures follow infer.baml's conventions: `InferenceContext` methods take
// `ctx` first; a free function over interned types with no context takes the
// pool first.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_catch @ d9be6853b
function infer_catch(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    catch_expr: int,
    base: int,
    clause: root.ast.CatchClause,
    expected: Expectation,
) -> int throws never {
    baml.sys.panic("infer_catch: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::judge_catch_coverage @ d9be6853b
function judge_catch_coverage(
    ctx: InferenceContext,
    at: int,
    kind: root.ast.CatchClauseKind,
    received: int[],
    unhandled: int[],
    trapped_panics: int[],
    traps_every_panic: bool,
) -> void throws never {
    baml.sys.panic("judge_catch_coverage: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::every_panic @ d9be6853b
function every_panic(ctx: InferenceContext) -> int? throws never {
    baml.sys.panic("every_panic: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::panics_not_trapped @ d9be6853b
function panics_not_trapped(ctx: InferenceContext, trapped: int[]) -> int[] throws never {
    baml.sys.panic("panics_not_trapped: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::panic_subset @ d9be6853b
function panic_subset(ctx: InferenceContext, claim: int) -> int? throws never {
    baml.sys.panic("panic_subset: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::non_panic_subset @ d9be6853b
function non_panic_subset(ctx: InferenceContext, ty: int) -> int? throws never {
    baml.sys.panic("non_panic_subset: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finalize_incoming_effect @ d9be6853b
function finalize_incoming_effect(ctx: InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("finalize_incoming_effect: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::force_classes_naming @ d9be6853b
function force_classes_naming(ctx: InferenceContext, ty: int) -> bool throws never {
    baml.sys.panic("force_classes_naming: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_needless_chain @ d9be6853b
function check_needless_chain(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    base: int,
    base_ty: int,
) -> void throws never {
    baml.sys.panic("check_needless_chain: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_tag_values @ d9be6853b
function check_tag_values(ctx: InferenceContext, body: root.ast.ExprBody) -> void throws never {
    baml.sys.panic("check_tag_values: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_template_interps_strict @ d9be6853b
function check_template_interps_strict(
    ctx: InferenceContext,
    segments: root.ast.TemplateSegment[],
) -> void throws never {
    baml.sys.panic("check_template_interps_strict: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::holds_role_marker @ d9be6853b
function holds_role_marker(ctx: InferenceContext, ty: int, fuel: int) -> bool throws never {
    baml.sys.panic("holds_role_marker: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::judge_throws_contract_coverage @ d9be6853b
function judge_throws_contract_coverage(
    ctx: InferenceContext,
    contract: ThrowsContract,
) -> void throws never {
    baml.sys.panic("judge_throws_contract_coverage: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_throws_contribution @ d9be6853b
function check_throws_contribution(
    ctx: InferenceContext,
    at: int,
    contribution: int,
    declared: int,
) -> void throws never {
    baml.sys.panic("check_throws_contribution: not ported (U5)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::record_throw @ d9be6853b
function record_throw(ctx: InferenceContext, at: int, ty: int) -> void throws never {
    baml.sys.panic("record_throw: not ported (U5)")
}
