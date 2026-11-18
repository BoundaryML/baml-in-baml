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
// This file holds the type declarations; the `InferenceContext` methods
// are stubbed in `infer_stubs_u1.baml` (namespace `hir_ty.infer`) until
// ported. Interned types are `int`s; `FxHashMap`/`FxHashSet` are `map`s.

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
