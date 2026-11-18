// Stubs for K4 unit 2 (subtyping, operators, obligations): every function of
// infer.rs that the unit owns, in namespace `hir_ty`, with its BAML
// signature. Each panics until the unit ports it; the unit replaces this file
// and deletes it. Signatures follow infer.baml's conventions:
// `InferenceContext` methods take `ctx` first; a free function over interned
// types with no context takes the pool first.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::sub @ d9be6853b
function sub(ctx: InferenceContext, actual: int, expected: int) -> bool throws never {
    baml.sys.panic("sub: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::sub_residue @ d9be6853b
function sub_residue(ctx: InferenceContext, actual: int, expected: int) -> bool throws never {
    baml.sys.panic("sub_residue: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::commit_establishments_to_unknown @ d9be6853b
function commit_establishments_to_unknown(ctx: InferenceContext, ty: int) -> void throws never {
    baml.sys.panic("commit_establishments_to_unknown: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::eq_piece @ d9be6853b
function eq_piece(ctx: InferenceContext, a: int, b: int) -> bool throws never {
    baml.sys.panic("eq_piece: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::reject_scoped_escape_into_var @ d9be6853b
function reject_scoped_escape_into_var(
    ctx: InferenceContext,
    var: int,
    ty: int,
) -> bool throws never {
    baml.sys.panic("reject_scoped_escape_into_var: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::cached_equivalent @ d9be6853b
function cached_equivalent(ctx: InferenceContext, a: int, b: int) -> bool throws never {
    baml.sys.panic("cached_equivalent: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::cached_subtype @ d9be6853b
function cached_subtype(ctx: InferenceContext, sub: int, sup: int) -> bool throws never {
    baml.sys.panic("cached_subtype: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::provable_subtype @ d9be6853b
function provable_subtype(ctx: InferenceContext, sub: int, sup: int) -> bool throws never {
    baml.sys.panic("provable_subtype: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::union_of @ d9be6853b
function union_of(ctx: InferenceContext, members: int[]) -> int throws never {
    baml.sys.panic("union_of: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::join @ d9be6853b
function join(ctx: InferenceContext, members: int[]) -> int throws never {
    baml.sys.panic("join: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::join_return_candidates @ d9be6853b
function join_return_candidates(ctx: InferenceContext, candidates: int[]) -> int throws never {
    baml.sys.panic("join_return_candidates: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::widen_fresh @ d9be6853b
function widen_fresh(ctx: InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("widen_fresh: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_binary @ d9be6853b
function infer_binary(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: Expectation,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
) -> int throws never {
    baml.sys.panic("infer_binary: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_await @ d9be6853b
function infer_await(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    future: int,
) -> int throws never {
    baml.sys.panic("infer_await: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::compound_op_result @ d9be6853b
function compound_op_result(
    ctx: InferenceContext,
    at: int,
    op: root.ast.AssignOp,
    lhs: int,
    rhs: int,
) -> int throws never {
    baml.sys.panic("compound_op_result: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_index @ d9be6853b
function infer_index(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    base: int,
    index: int,
    optional: bool,
    write: bool,
) -> int throws never {
    baml.sys.panic("infer_index: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_not @ d9be6853b
function infer_not(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    operand: int,
    position: root.hir_ty.infer.TestPosition,
) -> (int, root.hir_ty.infer.CondFacts) throws never {
    baml.sys.panic("infer_not: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_unary @ d9be6853b
function infer_unary(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    op: root.ast.UnaryOp,
    operand: int,
) -> int throws never {
    baml.sys.panic("infer_unary: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::operator_or_obligation @ d9be6853b
function operator_or_obligation(
    ctx: InferenceContext,
    at: int,
    interface_: string,
    lhs: int,
    rhs: int?,
) -> int throws never {
    baml.sys.panic("operator_or_obligation: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_operator_failure @ d9be6853b
function report_operator_failure(
    ctx: InferenceContext,
    at: int,
    interface_: string,
    lhs: int,
    rhs: int?,
) -> void throws never {
    baml.sys.panic("report_operator_failure: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::dispatch_operator @ d9be6853b
function dispatch_operator(
    ctx: InferenceContext,
    interface_: string,
    lhs: int,
    rhs: int?,
) -> int throws never {
    baml.sys.panic("dispatch_operator: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::member_operator_output @ d9be6853b
function member_operator_output(
    ctx: InferenceContext,
    interface_: string,
    lhs: int,
    rhs: int?,
) -> int? throws never {
    baml.sys.panic("member_operator_output: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::peel_chain_null @ d9be6853b
function peel_chain_null(ctx: InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("peel_chain_null: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::remove_null @ d9be6853b
function remove_null(ctx: InferenceContext, ty: int) -> int throws never {
    baml.sys.panic("remove_null: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::null_coalesce @ d9be6853b
function null_coalesce(ctx: InferenceContext, inner: int, rhs: int) -> int throws never {
    baml.sys.panic("null_coalesce: not ported (U2)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::operand_members @ d9be6853b
function operand_members(
    pool: root.types.InferPool,
    lang: root.base.LangRoots,
    ty: int,
) -> int[] throws never {
    baml.sys.panic("operand_members: not ported (U2)")
}
