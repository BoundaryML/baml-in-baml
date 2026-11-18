// port: baml_compiler2_hir_ty/src/infer/flow.rs @ d9be6853b
//
// Flow-sensitive narrowing, carried directly on the structured AST walk
// (BAML has no unstructured control flow, so no CFG layer is needed):
//
// - The environment is the `flow` overlay on `InferenceContext`
//   (`BindingId -> Ty`), cloned at branch points, consulted before the
//   declared/widened binding type.
// - `CondFacts` carries a condition's `when_true`/`when_false` fact maps,
//   combined with walk-time De Morgan over `&&`/`||`/`!`. The walk that
//   types a tested expression returns them (`infer_test`): a test is judged
//   once, in the flow that holds where it is evaluated.
// - `&&` / `||` short-circuit, so their RIGHT operand is typed under the
//   left operand's facts. Only a bare local that no closure captures carries
//   a fact: BAML tasks interleave between statements, so a field path or an
//   index path, which is read a second time, can change between the test
//   and the read.
// - An operand that may be skipped (the right operand of `&&`/`||`, a `??`
//   fallback, the links of a `?.` chain after the first `?.`) is typed from
//   a `SkipPoint` and rejoined there.
// - Branch merges are divergence-aware: a diverged branch contributes
//   nothing.
// - A loop drops the facts about every binding its condition, body or
//   update slot assigns before typing each of them once, and the post-loop
//   environment is the merge of its exit edges, each with the flow where it
//   is taken. A loop with no exit edge diverges.
// - Assignments check against the DECLARED binding type, never the
//   overlay, then re-narrow the overlay to the assigned value.
// - Else-side subtraction is gated on `PatternOutcome.consumes_matched`.
//
// The `InferenceContext` methods are free functions taking `ctx` first;
// `copy_flow` is the overlay's derived `Clone`. Interned types are `int`s;
// `FxHashMap`/`FxHashSet` are `map`s.

// port: baml_compiler2_hir_ty/src/infer/flow.rs::Flow @ d9be6853b
// The narrowing overlay: a binding's flow type where a fact about it is in
// force. A binding with no entry has its declared type.
type Flow = map<root.hir.BindingId, int>;

// port: baml_compiler2_hir_ty/src/infer/flow.rs::LoopFrame @ d9be6853b
// One enclosing loop while its header, body and update slot are typed: the
// flows at the `break`s and `continue`s that bind to it, all written in its
// body.
class LoopFrame {
    // The flow at each `break`: an exit edge of the loop.
    breaks: Flow[],
    // The flow at each `continue`: an edge into a C-style loop's update
    // slot, and an exit edge of a `for let`, whose header may end the loop.
    // A `while` and a `while let` re-test their header in the havoced flow,
    // which covers these edges, so theirs go unread.
    continues: Flow[],
    // The header slot being typed, if any: a `break`/`continue` written
    // there is rejected (rustc's E0590 rule for `while` conditions), since a
    // loop is left from its body only.
    header: root.hir_ty.LoopHeaderSlot?,
    // Whether a `break`/`continue` that would have bound to this loop was
    // rejected (in its header, or behind a lambda or template inside it).
    // The author meant an exit: a loop left with no edge then completes
    // rather than reporting the code after it unreachable as well.
    has_rejected_jump: bool,
    // `block_defer_writes.length()` at loop entry. The defers armed in the
    // blocks opened inside the loop run on every `break`/`continue` edge.
    defer_floor: int,
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::LoopEdge @ d9be6853b
// The edge a `break` or `continue` takes.
enum LoopEdge {
    Break,
    Continue,
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::LoopEdge::keyword @ d9be6853b
function loop_edge_keyword(edge: LoopEdge) -> string throws never {
    match (edge) {
        LoopEdge.Break => "break",
        LoopEdge.Continue => "continue",
    }
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::LoopVerdicts @ d9be6853b
// The verdicts about a body's loops and jumps that the reachability pass
// reads from inference instead of re-deriving from syntax.
class LoopVerdicts {
    // The `while` and `while let` statements with no exit edge: a header
    // that never misses (a statically true condition, a header that always
    // returns or `continue`s) and no live `break` that binds to the loop.
    // The code after one is unreachable.
    diverging_loops: map<int, bool>,
    // The `break`/`continue` statements that were rejected (E0141, E0187,
    // E0188). A rejected jump still ends the flow as written, but the code
    // after it is not reported unreachable on top of the rejection.
    rejected_jumps: map<int, bool>,

    // port: baml_compiler2_hir_ty/src/infer/flow.rs::LoopVerdicts (derived Default) @ d9be6853b
    function default() -> Self {
        LoopVerdicts { diverging_loops: {}, rejected_jumps: {} }
    }
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::SkipPoint @ d9be6853b
// The state where an operand that may be skipped begins (the right operand
// of `&&`/`||`, a `??` fallback, the links of a `?.` chain after the first
// `?.`), for `rejoin_skipped` to resume.
class SkipPoint {
    flow: Flow,
    diverges: root.hir_ty.Diverges,
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::CondFacts @ d9be6853b
// A condition's narrowing consequences for each polarity.
class CondFacts {
    when_true: map<root.hir.BindingId, int>,
    when_false: map<root.hir.BindingId, int>,

    // port: baml_compiler2_hir_ty/src/infer/flow.rs::CondFacts (derived Default) @ d9be6853b
    function default() -> Self {
        CondFacts { when_true: {}, when_false: {} }
    }

    // port: baml_compiler2_hir_ty/src/infer/flow.rs::CondFacts::swapped @ d9be6853b
    function swapped(self) -> CondFacts throws never {
        CondFacts { when_true: self.when_false, when_false: self.when_true }
    }
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::TestPosition @ d9be6853b
// Where a test is written. A test that can never hold is reported only in a
// branch condition (`if`, `while`, a match guard): as a value it is a legal
// test that answers `false`.
enum TestPosition {
    Condition,
    Value,
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::ShortCircuit @ d9be6853b
// The operators that evaluate their right operand for one outcome of the
// left operand only.
enum ShortCircuit {
    And,
    Or,
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::impl From<ShortCircuit> for BinaryOp @ d9be6853b
function binary_op_from_short_circuit(op: ShortCircuit) -> root.ast.BinaryOp throws never {
    match (op) {
        ShortCircuit.And => root.ast.BinaryOp.And,
        ShortCircuit.Or => root.ast.BinaryOp.Or,
    }
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::Flow (derived Clone) @ d9be6853b
// A copy of the overlay, for a branch point.
function copy_flow(flow: Flow) -> Flow throws never {
    let out: Flow = {};
    for (let binding in flow.keys()) {
        out.set(binding, flow[binding]);
    }
    out
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::infer_test @ d9be6853b
// Infers an expression that is tested for truthiness and returns, with its
// type, what each outcome proves about bare locals. Leaves: `x == null` /
// `x != null`, `x is <pattern>` and a bare `x`; combinators: `&&`/`||`/`!`
// with De Morgan.
//
// The facts come from the same walk that types the expression, so each
// test is judged in the flow that holds where it is evaluated: after the
// assignments of the operands before it, and under the facts of a left
// operand that had to hold for it to run.
function infer_test(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    position: TestPosition,
) -> (int, CondFacts) throws never {
    let (let ty, let facts) = match (body.exprs[expr]) {
        let e: root.ast.ExprUnary if e.op == root.ast.UnaryOp.Not => {
            root.hir_ty.infer_not(ctx, body, e.expr, position)
        },
        let e: root.ast.ExprBinary if e.op == root.ast.BinaryOp.And => {
            infer_short_circuit(ctx, body, ShortCircuit.And, e.lhs, e.rhs, position)
        },
        let e: root.ast.ExprBinary if e.op == root.ast.BinaryOp.Or => {
            infer_short_circuit(ctx, body, ShortCircuit.Or, e.lhs, e.rhs, position)
        },
        let e: root.ast.ExprIs => infer_is(ctx, body, e.scrutinee, e.pattern, position),
        let e: root.ast.ExprBinary
            if e.op == root.ast.BinaryOp.Eq || e.op == root.ast.BinaryOp.Ne => {
            let ty = root.hir_ty.infer_expr(ctx, body, expr, root.hir_ty.ExpectationNone {});
            let facts = null_test_facts(ctx, body, e.lhs, e.rhs) ?? CondFacts.default();
            return (
                ty,
                if (e.op == root.ast.BinaryOp.Eq) {
                    facts
                } else {
                    facts.swapped()
                },
            );
        },
        _ => {
            let ty = root.hir_ty.infer_expr(ctx, body, expr, root.hir_ty.ExpectationNone {});
            return (ty, truthiness_facts(ctx, body, expr));
        },
    };
    ctx.result.type_of_expr.set(expr, ty);
    (ty, facts)
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::infer_short_circuit @ d9be6853b
// `lhs && rhs` / `lhs || rhs`.
//
// The operators short-circuit: the right operand runs only after the left
// one was true (`&&`) or false (`||`), so it is typed under the left
// operand's facts for that outcome. The facts are about bare local bindings
// that no closure captures (`narrowable_binding`): such a binding belongs
// to this call, so nothing can change it between the test on the left and
// the read on the right. A field path is read a second time on the right,
// and another task or an alias can change it between the two reads, so it
// is never narrowed.
//
// The right operand may be skipped (`rejoin_skipped`), and a binding it
// assigns no longer has the type that the left operand found, so the left
// operand's facts about it are dropped: `x is A && { x = b; true }` proves
// nothing about `x`.
function infer_short_circuit(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    op: ShortCircuit,
    lhs: int,
    rhs: int,
    position: TestPosition,
) -> (int, CondFacts) throws never {
    let (let lhs_ty, let left) = check_truthy_operand(ctx, body, lhs, true, position);
    let skip = skip_point(ctx);
    apply_facts(
        ctx,
        match (op) {
            ShortCircuit.And => left.when_true,
            ShortCircuit.Or => left.when_false,
        },
    );
    let (let rhs_ty, let right) = check_truthy_operand(ctx, body, rhs, true, position);
    let reassigned = assigned_bindings(ctx, body, rhs);
    rejoin_skipped(ctx, skip, reassigned);
    for (let binding in reassigned.keys()) {
        left.when_true.delete(binding);
        left.when_false.delete(binding);
    }
    let facts = match (op) {
        ShortCircuit.And => {
            CondFacts {
                when_true: all_facts(ctx, left.when_true, right.when_true),
                when_false: any_facts(ctx, left.when_false, right.when_false),
            }
        },
        ShortCircuit.Or => {
            CondFacts {
                when_true: any_facts(ctx, left.when_true, right.when_true),
                when_false: all_facts(ctx, left.when_false, right.when_false),
            }
        },
    };
    let pool = ctx.table.pool;
    let lhs_ty = ctx.table.resolve_completely(lhs_ty);
    let rhs_ty = ctx.table.resolve_completely(rhs_ty);
    let ty = root.hir_ty.const_fold_binary(pool, binary_op_from_short_circuit(op), lhs_ty, rhs_ty)
        ?? pool.add(root.types.TyBool {});
    (ty, facts)
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::truthiness_facts @ d9be6853b
// Truthiness: a bare narrowable value as a whole test narrows by POLARITY.
// The true branch drops always-falsy union members (`null`, `false`,
// zero/empty literals), the false branch drops always-truthy ones
// (instances, functions, non-falsy literals). Runtime-decided members
// (`string`, `int`, containers) survive both sides: the language has no
// "non-empty string" type to narrow to.
function truthiness_facts(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
) -> CondFacts throws never {
    let binding = narrowable_binding(ctx, body, expr)
        ?? return CondFacts.default();
    let pool = ctx.table.pool;
    let scrut = binding_flow_ty(ctx, binding);
    let resolved = ctx.table.resolve_completely(scrut);
    if (pool.has_error(resolved) || pool.has_infer(resolved)) {
        return CondFacts.default();
    }
    let facts = CondFacts.default();
    facts.when_true.set(binding, drop_members_by_truthiness(pool, resolved, false));
    facts.when_false.set(binding, drop_members_by_truthiness(pool, resolved, true));
    facts
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::drop_members_by_truthiness @ d9be6853b
// Set-subtraction on truthiness (the `subtract_narrow` discipline): drop the
// members whose truthiness is statically the given polarity; survivors keep
// their identity, nothing dropped leaves the type unchanged, everything
// dropped is `never`.
// A static method of `InferenceContext`: no `ctx`, takes the pool.
function drop_members_by_truthiness(
    pool: root.types.InferPool,
    scrut: int,
    drop_truthy: bool,
) -> int throws never {
    let members = match (pool.kinds[scrut]) {
        let u: root.types.InferTyUnion => u.members,
        _ => [scrut],
    };
    let dropped = if (drop_truthy) {
        Truthiness.AlwaysTruthy
    } else {
        Truthiness.AlwaysFalsy
    };
    let kept = members.filter((member) -> {
        truthiness(pool, member) != dropped
    });
    if (kept.length() == members.length()) {
        return scrut;
    }
    root.hir_ty.syntactic_union(pool, kept)
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::null_test_facts @ d9be6853b
// `x == null` / `null == x` for a narrowable `x`: true implies the null
// part, false implies the non-null part.
function null_test_facts(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    lhs: int,
    rhs: int,
) -> CondFacts? throws never {
    let other = match (body.exprs[lhs], body.exprs[rhs]) {
        (root.ast.ExprNull, _) => rhs,
        (_, root.ast.ExprNull) => lhs,
        _ => {
            return null;
        },
    };
    let binding = narrowable_binding(ctx, body, other)
        ?? return null;
    let ty = binding_flow_ty(ctx, binding);
    let resolved = ctx.table.resolve_completely(ty);
    let facts = CondFacts.default();
    facts.when_true.set(binding, ctx.table.pool.add(root.types.TyNull {}));
    facts.when_false.set(binding, root.hir_ty.remove_null(ctx, resolved));
    facts
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::all_facts @ d9be6853b
// Conjunction of fact maps: both hold, so entries merge and a shared
// binding takes the tighter type. Consumes `left` (Rust moves it).
function all_facts(
    ctx: root.hir_ty.InferenceContext,
    left: map<root.hir.BindingId, int>,
    right: map<root.hir.BindingId, int>,
) -> map<root.hir.BindingId, int> throws never {
    for (let binding in right.keys()) {
        let ty = right[binding];
        let existing = left.delete(binding);
        let entry = if (existing != null) {
            narrow_meet(ctx, existing, ty)
        } else {
            ty
        };
        left.set(binding, entry);
    }
    left
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::any_facts @ d9be6853b
// Disjunction of fact maps: only facts BOTH sides establish survive, joined.
function any_facts(
    ctx: root.hir_ty.InferenceContext,
    left: map<root.hir.BindingId, int>,
    right: map<root.hir.BindingId, int>,
) -> map<root.hir.BindingId, int> throws never {
    let out: map<root.hir.BindingId, int> = {};
    for (let binding in left.keys()) {
        let right_ty = right.get(binding);
        if (right_ty != null) {
            out.set(binding, root.hir_ty.join(ctx, [left[binding], right_ty]));
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::narrow_meet @ d9be6853b
// The tighter of two refinements of the same binding (approximate meet,
// same policy as pattern narrowing).
function narrow_meet(ctx: root.hir_ty.InferenceContext, a: int, b: int) -> int throws never {
    if (root.hir_ty.provable_subtype(ctx, a, b)) {
        a
    } else {
        b
    }
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::binding_flow_ty @ d9be6853b
// A binding's current flow type: the overlay, else the declared type (the
// recorded binding type for locals, the signature/deduced type for
// parameters, mirroring `infer_path`).
function binding_flow_ty(
    ctx: root.hir_ty.InferenceContext,
    binding: root.hir.BindingId,
) -> int throws never {
    ctx.flow.get(binding) ?? binding_declared_ty(ctx, binding)
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::binding_declared_ty @ d9be6853b
// The un-narrowed type a binding declares.
function binding_declared_ty(
    ctx: root.hir_ty.InferenceContext,
    binding: root.hir.BindingId,
) -> int throws never {
    let declared = match (binding.kind) {
        root.hir.BindingKindLocal => {
            let local = ctx.index.local_binding(binding);
            if (local != null) {
                ctx.result.type_of_pat.get(local.bind_pattern)
            } else {
                null
            }
        },
        let param: root.hir.BindingKindParameter => {
            let params = if (binding.scope == ctx.owner_scope) {
                ctx.param_tys
            } else {
                ctx.lambda_params.get(binding.scope)
            };
            params?.at(param.value)
        },
    };
    declared ?? ctx.table.pool.add(root.types.TyError {})
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::subtract_narrow @ d9be6853b
// Set-subtraction on canonical members: drop the members provably inside
// `matched`; nothing dropped leaves the scrutinee unchanged (never a
// fabricated narrower type), everything dropped is `never`.
function subtract_narrow(
    ctx: root.hir_ty.InferenceContext,
    scrut: int,
    matched: int,
) -> int throws never {
    let pool = ctx.table.pool;
    let members = match (pool.kinds[scrut]) {
        let u: root.types.InferTyUnion => u.members,
        _ => [scrut],
    };
    let kept = members.filter((member) -> {
        !root.hir_ty.provable_subtype(ctx, member, matched)
    });
    if (kept.length() == members.length()) {
        return scrut;
    }
    // Filtering never REWRITES the survivors (TS's `getTypeWithFacts`
    // shape): the structural constructor keeps each member's identity,
    // freshness included, where the canonical path would re-mark literals
    // rigid.
    root.hir_ty.syntactic_union(pool, kept)
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::apply_facts @ d9be6853b
// Applies one polarity's facts onto the flow overlay.
function apply_facts(
    ctx: root.hir_ty.InferenceContext,
    facts: map<root.hir.BindingId, int>,
) -> void throws never {
    for (let binding in facts.keys()) {
        ctx.flow.set(binding, facts[binding]);
    }
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::skip_point @ d9be6853b
// The state at the point from which an operand may be skipped; the operand
// is typed from here and `rejoin_skipped` resumes here.
function skip_point(ctx: root.hir_ty.InferenceContext) -> SkipPoint throws never {
    SkipPoint { flow: copy_flow(ctx.flow), diverges: diverges(ctx) }
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::rejoin_skipped @ d9be6853b
// Ends an operand that may not have run (`&&`/`||` right operands, `??`
// fallbacks, the links of a `?.` chain after the first `?.`): its
// divergence is not the expression's, since after `a || { return; }`
// execution can proceed, and the overlay is the one from the skip point. A
// binding the operand assigns (`reassigned`, its assigned set) keeps a
// refinement only where the taken and the skipped path agree, joined; an
// operand that diverged is not a path that reaches here, and the facts a
// test in the operand established do not outlive it.
function rejoin_skipped(
    ctx: root.hir_ty.InferenceContext,
    skip: SkipPoint,
    reassigned: map<root.hir.BindingId, bool>,
) -> void throws never {
    let taken_diverged = diverges(ctx) == root.hir_ty.Diverges.Always;
    set_diverges(ctx, skip.diverges);
    let taken_flow = ctx.flow;
    ctx.flow = skip.flow;
    if (taken_diverged) {
        return;
    }
    for (let binding in reassigned.keys()) {
        let taken = taken_flow.get(binding);
        let skipped = ctx.flow.get(binding);
        if (taken == null || skipped == null) {
            ctx.flow.delete(binding);
        } else if (taken != skipped) {
            let joined = root.hir_ty.join(ctx, [taken, skipped]);
            ctx.flow.set(binding, joined);
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::merge_flows @ d9be6853b
// The divergence-aware merge of the live paths into one point. A path that
// diverged is not among them and contributes nothing, which is why
// early-return narrowing is the ordinary merge rule and not a special case.
// A binding keeps an overlay only when EVERY path narrowed it, joined:
// narrowed on one path only, the other path keeps the wider type, so the
// join is the declared type, no overlay.
function merge_flows(
    ctx: root.hir_ty.InferenceContext,
    first: Flow,
    rest: Flow[],
) -> Flow throws never {
    let merged = first;
    for (let flow in rest) {
        let next: Flow = {};
        for (let binding in merged.keys()) {
            let other = flow.get(binding);
            if (other == null) {
                continue;
            }
            let ty = merged[binding];
            let joined = if (ty == other) {
                ty
            } else {
                root.hir_ty.join(ctx, [ty, other])
            };
            next.set(binding, joined);
        }
        merged = next;
    }
    merged
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::merge_reaching @ d9be6853b
// `merge_flows` over paths that may all have diverged: null when nothing
// reaches the point, which is then unreachable. Takes the LAST flow as the
// first, as Rust's `pop` does.
function merge_reaching(ctx: root.hir_ty.InferenceContext, flows: Flow[]) -> Flow? throws never {
    let first = flows.pop()
        ?? return null;
    merge_flows(ctx, first, flows)
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::enter_loop @ d9be6853b
// Opens the frame of a loop whose header is about to be typed.
function enter_loop(ctx: root.hir_ty.InferenceContext) -> void throws never {
    let defer_floor = ctx.block_defer_writes.length();
    control_frame(ctx).loops.push(
        LoopFrame {
            breaks: [],
            continues: [],
            header: null,
            has_rejected_jump: false,
            defer_floor: defer_floor,
        },
    );
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::mark_rejected_jump @ d9be6853b
// Records a rejected `break`/`continue` against the loop it would have bound
// to: the innermost loop open in any frame, if there is one.
function mark_rejected_jump(ctx: root.hir_ty.InferenceContext) -> void throws never {
    let frame = ctx.frames.find_last((frame) -> {
        frame.loops.length() > 0
    })
        ?? return;
    frame.loops[frame.loops.length() - 1].has_rejected_jump = true;
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::innermost_loop_mut @ d9be6853b
// The innermost loop of the frame, between `enter_loop` and `leave_loop`.
function innermost_loop_mut(ctx: root.hir_ty.InferenceContext) -> LoopFrame throws never {
    let loops = control_frame(ctx).loops;
    loops.at(loops.length() - 1) ?? baml.sys.panic("called between `enter_loop` and `leave_loop`")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::set_loop_header @ d9be6853b
// Marks which header slot of the innermost loop is being typed, or that its
// body is.
function set_loop_header(
    ctx: root.hir_ty.InferenceContext,
    slot: root.hir_ty.LoopHeaderSlot?,
) -> void throws never {
    innermost_loop_mut(ctx).header = slot;
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::loop_header @ d9be6853b
// The header slot of the innermost loop being typed, where a
// `break`/`continue` has no place.
function loop_header(
    ctx: root.hir_ty.InferenceContext,
) -> root.hir_ty.LoopHeaderSlot? throws never {
    let loops = control_frame(ctx).loops;
    loops.at(loops.length() - 1)?.header
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::leave_loop @ d9be6853b
// Closes the innermost loop's frame and hands back its edges.
function leave_loop(ctx: root.hir_ty.InferenceContext) -> LoopFrame throws never {
    control_frame(ctx).loops.pop() ?? baml.sys.panic("`leave_loop` pairs with `enter_loop`")
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::take_continues @ d9be6853b
// Takes the innermost loop's `continue` edges, for its update slot.
function take_continues(ctx: root.hir_ty.InferenceContext) -> Flow[] throws never {
    let frame = innermost_loop_mut(ctx);
    let continues = frame.continues;
    frame.continues = [];
    continues
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::record_loop_edge @ d9be6853b
// Records the flow at a `break`/`continue` as an edge of the innermost loop,
// which the caller has checked is open (`loop_control_escape`). The defers
// armed inside the loop so far run before the jump, and their writes end
// the facts about the bindings they assign. A jump the flow cannot reach
// (after a `return`, in the body of a header that never completes) is no
// edge: recording it would keep the code after the loop alive.
function record_loop_edge(ctx: root.hir_ty.InferenceContext, edge: LoopEdge) -> void throws never {
    if (diverges(ctx) == root.hir_ty.Diverges.Always) {
        return;
    }
    let frame = innermost_loop_mut(ctx);
    let flow = copy_flow(ctx.flow);
    let defers = ctx.block_defer_writes;
    for (let writes in defers.slice(frame.defer_floor, defers.length())) {
        for (let binding in writes.keys()) {
            flow.delete(binding);
        }
    }
    match (edge) {
        LoopEdge.Break => {
            frame.breaks.push(flow);
        },
        LoopEdge.Continue => {
            frame.continues.push(flow);
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::assigned_bindings @ d9be6853b
// Every narrowable binding the subtree assigns: the havoc set of a construct
// that may not run, may run again or runs at another time (a skipped
// operand, a match arm, a `catch`, a `defer`, a `for let` body).
function assigned_bindings(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    root_id: int,
) -> map<root.hir.BindingId, bool> throws never {
    assigned_bindings_in(ctx, body, [root.ast.BodyNodeExpr { value: root_id }])
}

// port: baml_compiler2_hir_ty/src/infer/flow.rs::InferenceContext::assigned_bindings_in @ d9be6853b
// `assigned_bindings` over several roots: a loop's havoc set, which spans
// its condition, body and update slot.
function assigned_bindings_in(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    roots: root.ast.BodyNode[],
) -> map<root.hir.BindingId, bool> throws never {
    let out: map<root.hir.BindingId, bool> = {};
    // The arena is a DAG (templates share expression ids between their
    // segments and desugared payload), so the walk dedupes.
    let seen: map<root.ast.BodyNode, bool> = {};
    let stack: root.ast.BodyNode[] = roots.concat([]);
    while let node: root.ast.BodyNode = stack.pop() {
        if (seen.has(node)) {
            continue;
        }
        seen.set(node, true);
        let children: root.ast.BodyNode[] = [];
        match (node) {
            let e: root.ast.BodyNodeExpr => body.expr_children(e.value, children),
            let s: root.ast.BodyNodeStmt => {
                let target = match (body.stmts[s.value]) {
                    let assign: root.ast.StmtAssign => assign.target,
                    let assign: root.ast.StmtAssignOp => assign.target,
                    _ => null,
                };
                if (target != null) {
                    let binding = narrowable_binding(ctx, body, target);
                    if (binding != null) {
                        out.set(binding, true);
                    }
                }
                body.stmt_children(s.value, children);
            },
        }
        root.base.extend(stack, children);
    }
    out
}
