// Stubs for K4 unit 1 (expressions, statements): every function of
// infer/flow.rs, infer/frames.rs, infer/reachability.rs that the unit owns,
// in namespace `hir_ty.infer`, with its BAML signature. Each panics until the
// unit ports it; the unit replaces this file and deletes it. Signatures
// follow infer.baml's conventions: `InferenceContext` methods take `ctx`
// first; a free function over interned types with no context takes the pool
// first.

// port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability @ d9be6853b
class Reachability {
    body: root.ast.ExprBody,
    result: root.hir_ty.WorkingResult,
    // Inference's verdicts about loops without an exit and jumps without a
    // loop.
    loop_verdicts: LoopVerdicts,

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::never_ending_loop_note @ d9be6853b
    function never_ending_loop_note(self, stmt: int) -> root.hir_ty.RelatedNote? throws never {
        baml.sys.panic("never_ending_loop_note: not ported (U1)")
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::condition @ d9be6853b
    function condition(self, expr: int) -> bool? throws never {
        baml.sys.panic("condition: not ported (U1)")
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::warn @ d9be6853b
    function warn(
        self,
        diagnostics: root.hir_ty.TirDiagnostic[],
        condition: int,
        value: bool,
        note: root.hir_ty.RelatedNote?,
    ) -> void throws never {
        baml.sys.panic("warn: not ported (U1)")
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::condition_warning @ d9be6853b
    function condition_warning(
        self,
        condition: int,
        diagnostics: root.hir_ty.TirDiagnostic[],
    ) -> int? throws never {
        baml.sys.panic("condition_warning: not ported (U1)")
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::expr_exits @ d9be6853b
    function expr_exits(self, expr: int) -> bool throws never {
        baml.sys.panic("expr_exits: not ported (U1)")
    }

    // port: baml_compiler2_hir_ty/src/infer/reachability.rs::Reachability::stmt_exits @ d9be6853b
    function stmt_exits(self, stmt: int) -> bool throws never {
        baml.sys.panic("stmt_exits: not ported (U1)")
    }
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::control_frame @ d9be6853b
function control_frame(ctx: root.hir_ty.InferenceContext) -> ControlFrame throws never {
    baml.sys.panic("control_frame: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::control_frame_mut @ d9be6853b
function control_frame_mut(ctx: root.hir_ty.InferenceContext) -> ControlFrame throws never {
    baml.sys.panic("control_frame_mut: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::enter_frame @ d9be6853b
function enter_frame(ctx: root.hir_ty.InferenceContext, kind: FrameKind) -> void throws never {
    baml.sys.panic("enter_frame: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::leave_frame @ d9be6853b
function leave_frame(ctx: root.hir_ty.InferenceContext) -> void throws never {
    baml.sys.panic("leave_frame: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::diverges @ d9be6853b
function diverges(ctx: root.hir_ty.InferenceContext) -> root.hir_ty.Diverges throws never {
    baml.sys.panic("diverges: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::set_diverges @ d9be6853b
function set_diverges(
    ctx: root.hir_ty.InferenceContext,
    diverges: root.hir_ty.Diverges,
) -> void throws never {
    baml.sys.panic("set_diverges: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::current_scope @ d9be6853b
function current_scope(ctx: root.hir_ty.InferenceContext) -> int? throws never {
    baml.sys.panic("current_scope: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::return_frame @ d9be6853b
function return_frame(ctx: root.hir_ty.InferenceContext) -> ReturnFrame throws never {
    baml.sys.panic("return_frame: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::return_frame_mut @ d9be6853b
function return_frame_mut(ctx: root.hir_ty.InferenceContext) -> ReturnFrame throws never {
    baml.sys.panic("return_frame_mut: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::return_escape @ d9be6853b
function return_escape(ctx: root.hir_ty.InferenceContext) -> ReturnEscape? throws never {
    baml.sys.panic("return_escape: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::loop_control_escape @ d9be6853b
function loop_control_escape(ctx: root.hir_ty.InferenceContext) -> LoopControlEscape? throws never {
    baml.sys.panic("loop_control_escape: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/frames.rs::InferenceContext::template_param_ty @ d9be6853b
function template_param_ty(ctx: root.hir_ty.InferenceContext, name: string) -> int? throws never {
    baml.sys.panic("template_param_ty: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::infer_test @ d9be6853b
function infer_test(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    position: TestPosition,
) -> (int, CondFacts) throws never {
    baml.sys.panic("infer_test: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::infer_short_circuit @ d9be6853b
function infer_short_circuit(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    op: ShortCircuit,
    lhs: int,
    rhs: int,
    position: TestPosition,
) -> (int, CondFacts) throws never {
    baml.sys.panic("infer_short_circuit: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::truthiness_facts @ d9be6853b
function truthiness_facts(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
) -> CondFacts throws never {
    baml.sys.panic("truthiness_facts: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::drop_members_by_truthiness @ d9be6853b
// A static method of `InferenceContext`: no `ctx`.
function drop_members_by_truthiness(
    pool: root.types.InferPool,
    scrut: int,
    drop_truthy: bool,
) -> int throws never {
    baml.sys.panic("drop_members_by_truthiness: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::null_test_facts @ d9be6853b
function null_test_facts(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    lhs: int,
    rhs: int,
) -> CondFacts? throws never {
    baml.sys.panic("null_test_facts: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::all_facts @ d9be6853b
function all_facts(
    ctx: root.hir_ty.InferenceContext,
    left: map<root.hir.BindingId, int>,
    right: map<root.hir.BindingId, int>,
) -> map<root.hir.BindingId, int> throws never {
    baml.sys.panic("all_facts: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::any_facts @ d9be6853b
function any_facts(
    ctx: root.hir_ty.InferenceContext,
    left: map<root.hir.BindingId, int>,
    right: map<root.hir.BindingId, int>,
) -> map<root.hir.BindingId, int> throws never {
    baml.sys.panic("any_facts: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::narrow_meet @ d9be6853b
function narrow_meet(ctx: root.hir_ty.InferenceContext, a: int, b: int) -> int throws never {
    baml.sys.panic("narrow_meet: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::binding_flow_ty @ d9be6853b
function binding_flow_ty(
    ctx: root.hir_ty.InferenceContext,
    binding: root.hir.BindingId,
) -> int throws never {
    baml.sys.panic("binding_flow_ty: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::binding_declared_ty @ d9be6853b
function binding_declared_ty(
    ctx: root.hir_ty.InferenceContext,
    binding: root.hir.BindingId,
) -> int throws never {
    baml.sys.panic("binding_declared_ty: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::subtract_narrow @ d9be6853b
function subtract_narrow(
    ctx: root.hir_ty.InferenceContext,
    scrut: int,
    matched: int,
) -> int throws never {
    baml.sys.panic("subtract_narrow: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::apply_facts @ d9be6853b
function apply_facts(
    ctx: root.hir_ty.InferenceContext,
    facts: map<root.hir.BindingId, int>,
) -> void throws never {
    baml.sys.panic("apply_facts: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::skip_point @ d9be6853b
function skip_point(ctx: root.hir_ty.InferenceContext) -> SkipPoint throws never {
    baml.sys.panic("skip_point: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::rejoin_skipped @ d9be6853b
function rejoin_skipped(
    ctx: root.hir_ty.InferenceContext,
    skip: SkipPoint,
    reassigned: map<root.hir.BindingId, bool>,
) -> void throws never {
    baml.sys.panic("rejoin_skipped: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::merge_flows @ d9be6853b
function merge_flows(
    ctx: root.hir_ty.InferenceContext,
    first: Flow,
    rest: Flow[],
) -> Flow throws never {
    baml.sys.panic("merge_flows: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::merge_reaching @ d9be6853b
function merge_reaching(ctx: root.hir_ty.InferenceContext, flows: Flow[]) -> Flow? throws never {
    baml.sys.panic("merge_reaching: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::enter_loop @ d9be6853b
function enter_loop(ctx: root.hir_ty.InferenceContext) -> void throws never {
    baml.sys.panic("enter_loop: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::mark_rejected_jump @ d9be6853b
function mark_rejected_jump(ctx: root.hir_ty.InferenceContext) -> void throws never {
    baml.sys.panic("mark_rejected_jump: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::innermost_loop_mut @ d9be6853b
function innermost_loop_mut(ctx: root.hir_ty.InferenceContext) -> LoopFrame throws never {
    baml.sys.panic("innermost_loop_mut: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::set_loop_header @ d9be6853b
function set_loop_header(
    ctx: root.hir_ty.InferenceContext,
    slot: root.hir_ty.LoopHeaderSlot?,
) -> void throws never {
    baml.sys.panic("set_loop_header: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::loop_header @ d9be6853b
function loop_header(
    ctx: root.hir_ty.InferenceContext,
) -> root.hir_ty.LoopHeaderSlot? throws never {
    baml.sys.panic("loop_header: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::leave_loop @ d9be6853b
function leave_loop(ctx: root.hir_ty.InferenceContext) -> LoopFrame throws never {
    baml.sys.panic("leave_loop: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::take_continues @ d9be6853b
function take_continues(ctx: root.hir_ty.InferenceContext) -> Flow[] throws never {
    baml.sys.panic("take_continues: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::record_loop_edge @ d9be6853b
function record_loop_edge(ctx: root.hir_ty.InferenceContext, edge: LoopEdge) -> void throws never {
    baml.sys.panic("record_loop_edge: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::assigned_bindings @ d9be6853b
function assigned_bindings(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    root_id: int,
) -> map<root.hir.BindingId, bool> throws never {
    baml.sys.panic("assigned_bindings: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::assigned_bindings_in @ d9be6853b
function assigned_bindings_in(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    roots: root.ast.BodyNode[],
) -> map<root.hir.BindingId, bool> throws never {
    baml.sys.panic("assigned_bindings_in: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/reachability.rs::add_diagnostics @ d9be6853b
function add_diagnostics(
    body: root.ast.ExprBody,
    result: root.hir_ty.InferenceResult<int>,
    loop_verdicts: LoopVerdicts,
    diagnostics: root.hir_ty.TirDiagnostic[],
) -> void throws never {
    baml.sys.panic("add_diagnostics: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/reachability.rs::static_condition @ d9be6853b
function static_condition(
    pool: root.types.InferPool,
    body: root.ast.ExprBody,
    type_of: (int) -> int?,
    expr: int,
) -> bool? throws never {
    baml.sys.panic("static_condition: not ported (U1)")
}

// port: baml_compiler2_hir_ty/src/infer/reachability.rs::static_truthiness @ d9be6853b
function static_truthiness(pool: root.types.InferPool, ty: int) -> bool? throws never {
    baml.sys.panic("static_truthiness: not ported (U1)")
}
