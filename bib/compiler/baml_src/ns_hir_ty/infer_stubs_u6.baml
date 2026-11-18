// Stubs for K4 unit 6 (queries, finish): every function of infer.rs that the
// unit owns, in namespace `hir_ty`, with its BAML signature. Each panics
// until the unit ports it; the unit replaces this file and deletes it.
// Signatures follow infer.baml's conventions: `InferenceContext` methods take
// `ctx` first; a free function over interned types with no context takes the
// pool first.

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
