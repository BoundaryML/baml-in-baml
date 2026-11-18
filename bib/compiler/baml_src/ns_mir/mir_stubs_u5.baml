// Stubs for MIR unit 5 (optimize): every function the unit owns
// (optimize.rs, optimize/effects.rs, optimize/values.rs and reducible.rs), in namespace `mir`, with its BAML
// signature, and the types those signatures need that the unit's range
// declares. Each function
// panics until the unit ports it; the unit moves the types and functions
// into their files (`lower.baml`, `pretty.baml`, ...) and deletes this file.
//
// Conventions (bib/IDIOMS.md; ir.baml and lower.baml's headers):
// - `LoweringContext` methods are free functions taking `ctx:
//   LoweringContext` first. Methods of a type the unit declares stay
//   methods of its class; a method of a data enum (a union) is a free
//   function `<enum>_<method>`.
// - `Lowered<T>` / `Result<T, MirInternalError>` is `T throws
//   MirInternalError`; such a stub throws `MirInternalError` with its
//   "not ported" message instead of panicking (a stub that only panics
//   would warn that its `throws` is extraneous).
// - Ids (`Local`, `BlockId`, arena ids, locs, `*Ref`s, `SourceRoot`) are
//   `int`s; `Name` is `string`; parameters named after a BAML keyword (or
//   `root`) get `_` (`root_id`).
// - optimize/effects.rs and optimize/values.rs are files in namespace
//   `mir` like the rest (a plain `optimize/` subfolder, no `ns_`).
// - Rust's `&mut Operand` / `&mut Local` / `&mut Rvalue` in-place
//   rewrites: an operand or rvalue that changes variant (or an `int`
//   local) cannot be replaced through a parameter. The unit may return the
//   new value instead and change these signatures (they are private to
//   optimize).

// port: baml_compiler2_mir/src/optimize/effects.rs::Range @ d9be6853b
class Range {
    lo: int,
    hi: int,

    // port: baml_compiler2_mir/src/optimize/effects.rs::Range::exact @ d9be6853b
    function exact(n: int) -> Range throws never {
        baml.sys.panic("Range::exact: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Range::intersect @ d9be6853b
    function intersect(self, other: Range) -> Range? throws never {
        baml.sys.panic("Range::intersect: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Range::join @ d9be6853b
    function join(self, other: Range, widen: bool, domain: Range) -> Range throws never {
        baml.sys.panic("Range::join: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Range::arithmetic @ d9be6853b
    function arithmetic(self, op: BinOp, rhs: Range) -> Range? throws never {
        baml.sys.panic("Range::arithmetic: not ported (U5)")
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Number @ d9be6853b
type Number = NumberConstant | NumberLocal | NumberLength;

class NumberConstant {
    value: int,
}

class NumberLocal {
    value: int,
}

// Rust's `Length(Local, i64)`: the length of `local`, plus `offset`.
class NumberLength {
    local: int,
    offset: int,
}

// port: baml_compiler2_mir/src/optimize/effects.rs::ReadKey @ d9be6853b
type ReadKey = ReadKeyLocal | ReadKeyField | ReadKeyIndex;

class ReadKeyLocal {
    value: int,
}

// Rust's `Field(Box<Self>, usize)`.
class ReadKeyField {
    base: ReadKey,
    field: int,
}

// Rust's `Index(Box<Self>, Number, IndexKind)`.
class ReadKeyIndex {
    base: ReadKey,
    index: Number,
    kind: IndexKind,
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Condition @ d9be6853b
class Condition {
    op: BinOp,
    left: Number,
    right: Number,
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Facts @ d9be6853b
class Facts {
    aliases: map<int, int>,
    reads: map<ReadKey, int>,
    integers: map<int, Range>,
    lengths: map<int, Range>,
    length_values: map<int, (int, int)>,
    conditions: map<int, Condition>,

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::root @ d9be6853b
    function root(self, local: int) -> int throws never {
        baml.sys.panic("Facts::root: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::read_key @ d9be6853b
    function read_key(self, place: Place, body: MirFunctionBody) -> ReadKey? throws never {
        baml.sys.panic("Facts::read_key: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::number @ d9be6853b
    function number(self, operand: Operand, body: MirFunctionBody) -> Number? throws never {
        baml.sys.panic("Facts::number: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::range @ d9be6853b
    function range(self, number: Number) -> Range throws never {
        baml.sys.panic("Facts::range: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::length_value @ d9be6853b
    function length_value(self, value: Rvalue, body: MirFunctionBody) -> (int, int)? throws never {
        baml.sys.panic("Facts::length_value: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::integer_value @ d9be6853b
    function integer_value(self, value: Rvalue, body: MirFunctionBody) -> Range? throws never {
        baml.sys.panic("Facts::integer_value: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::condition @ d9be6853b
    function condition(self, operand: Operand) -> Condition? throws never {
        baml.sys.panic("Facts::condition: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::forget @ d9be6853b
    function forget(self, local: int) -> void throws never {
        baml.sys.panic("Facts::forget: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::statement @ d9be6853b
    function statement(self, statement: StatementKind, body: MirFunctionBody) -> void throws never {
        baml.sys.panic("Facts::statement: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::constrain @ d9be6853b
    function constrain(self, number: Number, range: Range) -> void throws never {
        baml.sys.panic("Facts::constrain: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::branch @ d9be6853b
    function branch(self, condition: Condition, taken: bool) -> void throws never {
        baml.sys.panic("Facts::branch: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::in_bounds @ d9be6853b
    function in_bounds(self, place: Place, body: MirFunctionBody) -> bool throws never {
        baml.sys.panic("Facts::in_bounds: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::can_discard @ d9be6853b
    function can_discard(self, value: Rvalue, body: MirFunctionBody) -> bool throws never {
        baml.sys.panic("Facts::can_discard: not ported (U5)")
    }

    // port: baml_compiler2_mir/src/optimize/effects.rs::Facts::merge @ d9be6853b
    function merge(self, other: Facts, widen: bool) -> bool throws never {
        baml.sys.panic("Facts::merge: not ported (U5)")
    }
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Analysis @ d9be6853b
class Analysis {
    discardable: bool[][],

    // port: baml_compiler2_mir/src/optimize/effects.rs::Analysis::new @ d9be6853b
    function new(body: MirFunctionBody) -> Analysis throws never {
        baml.sys.panic("Analysis::new: not ported (U5)")
    }
}

// port: baml_compiler2_mir/src/optimize.rs::optimize_function @ d9be6853b
// Run all optimization passes on a MIR function.
function optimize_function(db: root.hir.Db, func: MirFunction, opt: OptLevel) -> void throws never {
    baml.sys.panic("optimize_function: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::optimize_function_body @ d9be6853b
// Run all cleanup phases directly on a `MirFunctionBody`.
function optimize_function_body(
    db: root.hir.Db,
    body: MirFunctionBody,
    opt: OptLevel,
) -> void throws never {
    baml.sys.panic("optimize_function_body: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::optimize_body @ d9be6853b
function optimize_body(body: MirFunctionBody, arity: int, opt: OptLevel) -> void throws never {
    baml.sys.panic("optimize_body: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::eliminate_dead_blocks @ d9be6853b
// Phase 1: Remove unreachable blocks via BFS from entry.
function eliminate_dead_blocks(body: MirFunctionBody) -> void throws never {
    baml.sys.panic("eliminate_dead_blocks: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::rewrite_block_ids_in_terminator @ d9be6853b
// Rewrite all `BlockId` references in a terminator using old->new mapping.
function rewrite_block_ids_in_terminator(term: Terminator, map: int?[]) -> void throws never {
    baml.sys.panic("rewrite_block_ids_in_terminator: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::rewrite_handler_refs @ d9be6853b
// Rewrite a block's handler edges using an old->new mapping. A handler some
// kept block unwinds to, or is handling, is reachable from that block, so it
// is kept too.
function rewrite_handler_refs(block: BasicBlock, map: int?[]) -> void throws never {
    baml.sys.panic("rewrite_handler_refs: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::rewrite_block_ids_in_terminator_with_map @ d9be6853b
// Rewrite all `BlockId` references in a terminator using a `HashMap` redirect map.
function rewrite_block_ids_in_terminator_with_map(
    term: Terminator,
    map: map<int, int>,
) -> void throws never {
    baml.sys.panic("rewrite_block_ids_in_terminator_with_map: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::merge_passthrough_blocks @ d9be6853b
// Merge passthrough blocks: blocks with no statements and a single Goto terminator
// are eliminated by redirecting all references to them to their target.
function merge_passthrough_blocks(body: MirFunctionBody) -> void throws never {
    baml.sys.panic("merge_passthrough_blocks: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::collect_place_bound_locals @ d9be6853b
// Collect reads in positions that require a `Place` rather than an `Operand`.
function collect_place_bound_locals(body: MirFunctionBody) -> map<int, bool> throws never {
    baml.sys.panic("collect_place_bound_locals: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::count_local_defs @ d9be6853b
// Count definition sites for each local across all blocks: assignments,
// terminator destinations, and the runtime's write of a handler's error and
// context locals when it lands there.
function count_local_defs(body: MirFunctionBody) -> int[] throws never {
    baml.sys.panic("count_local_defs: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::count_local_uses @ d9be6853b
function count_local_uses(body: MirFunctionBody) -> int[] throws never {
    baml.sys.panic("count_local_uses: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_place @ d9be6853b
function count_in_place(p: Place, uses: int[]) -> void throws never {
    baml.sys.panic("count_in_place: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_operand @ d9be6853b
function count_in_operand(op: Operand, uses: int[]) -> void throws never {
    baml.sys.panic("count_in_operand: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_rvalue @ d9be6853b
function count_in_rvalue(rv: Rvalue, uses: int[]) -> void throws never {
    baml.sys.panic("count_in_rvalue: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_statement @ d9be6853b
function count_in_statement(stmt: Statement, uses: int[]) -> void throws never {
    baml.sys.panic("count_in_statement: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_terminator @ d9be6853b
function count_in_terminator(term: Terminator, uses: int[]) -> void throws never {
    baml.sys.panic("count_in_terminator: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::propagate_copies @ d9be6853b
// Phase 2a: Propagate trivial copies and single-use constants.
function propagate_copies(body: MirFunctionBody, arity: int) -> void throws never {
    baml.sys.panic("propagate_copies: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::propagate_block_param_copies @ d9be6853b
// Extend parameter-copy propagation to reassigned parameters within a block,
// up to the next write to either slot. Other values are left for stackification:
// substituting their temporaries can destroy profitable single-use carry chains.
function propagate_block_param_copies(body: MirFunctionBody, arity: int) -> void throws never {
    baml.sys.panic("propagate_block_param_copies: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_operand @ d9be6853b
function apply_subst_to_operand(op: Operand, subst: map<int, Operand>) -> void throws never {
    baml.sys.panic("apply_subst_to_operand: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_place_locals @ d9be6853b
// Substitute all Local references within a place using the subst map.
// Only substitutes when the substitution maps to a plain-local operand
// (i.e., `copy _Y`), since projecting through a constant is not meaningful.
function apply_subst_to_place_locals(p: Place, subst: map<int, Operand>) -> void throws never {
    baml.sys.panic("apply_subst_to_place_locals: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_rvalue @ d9be6853b
function apply_subst_to_rvalue(rv: Rvalue, subst: map<int, Operand>) -> void throws never {
    baml.sys.panic("apply_subst_to_rvalue: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_statement @ d9be6853b
function apply_subst_to_statement(stmt: Statement, subst: map<int, Operand>) -> void throws never {
    baml.sys.panic("apply_subst_to_statement: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_terminator @ d9be6853b
function apply_subst_to_terminator(
    term: Terminator,
    subst: map<int, Operand>,
) -> void throws never {
    baml.sys.panic("apply_subst_to_terminator: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::eliminate_dead_locals @ d9be6853b
// Phase 2b: Remove dead locals and renumber densely.
function eliminate_dead_locals(body: MirFunctionBody, arity: int) -> void throws never {
    baml.sys.panic("eliminate_dead_locals: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::remap_local @ d9be6853b
function remap_local(l: int, map: int?[]) -> void throws never {
    baml.sys.panic("remap_local: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::remap_place @ d9be6853b
function remap_place(p: Place, map: int?[]) -> void throws never {
    baml.sys.panic("remap_place: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::remap_operand @ d9be6853b
function remap_operand(op: Operand, map: int?[]) -> void throws never {
    baml.sys.panic("remap_operand: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::remap_rvalue @ d9be6853b
function remap_rvalue(rv: Rvalue, map: int?[]) -> void throws never {
    baml.sys.panic("remap_rvalue: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::rewrite_locals_in_statement @ d9be6853b
function rewrite_locals_in_statement(stmt: Statement, map: int?[]) -> void throws never {
    baml.sys.panic("rewrite_locals_in_statement: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::rewrite_locals_in_terminator @ d9be6853b
function rewrite_locals_in_terminator(term: Terminator, map: int?[]) -> void throws never {
    baml.sys.panic("rewrite_locals_in_terminator: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::verify_mir @ d9be6853b
// Verify MIR structural invariants after optimization.
function verify_mir(
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
    name: string,
) -> void throws never {
    baml.sys.panic("verify_mir: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::verify_definite_assignment @ d9be6853b
// Every read of a local is dominated by a write to it, and every read, write,
// or closure capture of a captured local is dominated by one of its
// `FreshCell`s: parameters by frame entry, where the emitter cells them.
function verify_definite_assignment(
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
    name: string,
) -> void throws never {
    baml.sys.panic("verify_definite_assignment: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize.rs::reorder_blocks_rpo @ d9be6853b
// Phase 3: Reorder blocks into reverse-post-order.
function reorder_blocks_rpo(body: MirFunctionBody) -> void throws never {
    baml.sys.panic("reorder_blocks_rpo: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/effects.rs::ReadKey::depends_on @ d9be6853b
function read_key_depends_on(read_key: ReadKey, local: int) -> bool throws never {
    baml.sys.panic("ReadKey::depends_on: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/effects.rs::Number::depends_on @ d9be6853b
function number_depends_on(number: Number, local: int) -> bool throws never {
    baml.sys.panic("Number::depends_on: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/effects.rs::invert @ d9be6853b
function invert(op: BinOp) -> BinOp throws never {
    baml.sys.panic("invert: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/effects.rs::remove_trivial_drops @ d9be6853b
// A local read used only to discard its result has no effect itself. Removing
// these sinks lets DCE reconsider their producers; potentially trapping
// producers will get an explicit discard again in `eliminate_dead_locals`.
function remove_trivial_drops(body: MirFunctionBody) -> void throws never {
    baml.sys.panic("remove_trivial_drops: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::scalar @ d9be6853b
function scalar(constant: Constant) -> bool throws never {
    baml.sys.panic("scalar: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::fold_constants @ d9be6853b
// Propagate immutable scalar definitions, including named bindings. Keeping the
// definitions until ordinary DCE preserves locals used in projection positions.
function fold_constants(body: MirFunctionBody, arity: int) -> void throws never {
    baml.sys.panic("fold_constants: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::fold_concat_parts @ d9be6853b
// Join the adjacent constant parts of a `Rvalue::ConcatStrings`, as
// `fold` joins a `+` of two constants. Two parts left are a plain `+`, so
// `fold` can finish the job; one is the value itself.
function fold_concat_parts(value: Rvalue) -> void throws never {
    baml.sys.panic("fold_concat_parts: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::fold @ d9be6853b
function fold(value: Rvalue) -> Constant? throws never {
    baml.sys.panic("fold: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::compare @ d9be6853b
// Restructured: Rust's `T: PartialOrd` bound is the unit's to choose.
function compare<T>(op: BinOp, a: T, b: T) -> bool? throws never {
    baml.sys.panic("compare: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::simplify_boolean_diamonds @ d9be6853b
function simplify_boolean_diamonds(body: MirFunctionBody) -> void throws never {
    baml.sys.panic("simplify_boolean_diamonds: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::eliminate_dead_stores @ d9be6853b
// Backwards liveness removes individual overwritten definitions, rather than
// requiring the entire local to be unused. Potentially failing RHSs stay put.
function eliminate_dead_stores(
    body: MirFunctionBody,
    arity: int,
    opt: OptLevel,
) -> void throws never {
    baml.sys.panic("eliminate_dead_stores: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::live_in_precise @ d9be6853b
// Liveness for spilling locals across suspensions: terminator destinations
// are definitions only on normal edges, where they were assigned.
function live_in_precise(body: MirFunctionBody) -> bool[][] throws never {
    baml.sys.panic("live_in_precise: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::live_out @ d9be6853b
// In precise mode, kill terminator destinations only on normal edges.
// Restructured: the const generic `PRECISE` is the parameter `precise`.
function live_out(
    precise: bool,
    body: MirFunctionBody,
    block: BasicBlock,
    live_in: bool[][],
) -> (bool[], bool[]) throws never {
    baml.sys.panic("live_out: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::transfer @ d9be6853b
function transfer(statement: Statement, live: bool[], exceptional: bool[]) -> void throws never {
    baml.sys.panic("transfer: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::union @ d9be6853b
function union(into: bool[], from: bool[]) -> void throws never {
    baml.sys.panic("union: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::materialize_operand_prefixes @ d9be6853b
// Put infallible constants before the next call producing a consumer operand.
// This exposes mixed prefixes like `[f(), 2, g()]` without moving any effectful
// evaluation. Stackification may still reject carrying and inline the constant.
function materialize_operand_prefixes(body: MirFunctionBody) -> void throws never {
    baml.sys.panic("materialize_operand_prefixes: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::prefix_operands @ d9be6853b
function prefix_operands(block: BasicBlock, index: int) -> Operand[] throws never {
    baml.sys.panic("prefix_operands: not ported (U5)")
}

// port: baml_compiler2_mir/src/optimize/values.rs::constant_type @ d9be6853b
function constant_type(constant: Constant) -> root.types.RuntimeTy? throws never {
    baml.sys.panic("constant_type: not ported (U5)")
}

// port: baml_compiler2_mir/src/reducible.rs::check @ d9be6853b
// Check that `body`'s CFG is reducible. On failure, returns the blocks left
// once every acyclic part is peeled away: a cycle with more than one entry,
// and what only it reaches.
function check(body: MirFunctionBody) -> int[]? throws never {
    baml.sys.panic("check: not ported (U5)")
}

// port: baml_compiler2_mir/src/reducible.rs::check_graph @ d9be6853b
// The reducibility test over plain successor lists.
function check_graph(entry: int, succs: int[][]) -> int[]? throws never {
    baml.sys.panic("check_graph: not ported (U5)")
}

// port: baml_compiler2_mir/src/reducible.rs::cycle_residue @ d9be6853b
// Peel the acyclic part off `forward` (Kahn's algorithm over the blocks in
// `rpo`); what is left lies on or behind a cycle.
function cycle_residue(rpo: int[], forward: int[][]) -> int[] throws never {
    baml.sys.panic("cycle_residue: not ported (U5)")
}

// port: baml_compiler2_mir/src/reducible.rs::reverse_postorder @ d9be6853b
// The blocks reachable from `entry`, in reverse postorder.
function reverse_postorder(entry: int, succs: int[][]) -> int[] throws never {
    baml.sys.panic("reverse_postorder: not ported (U5)")
}

// port: baml_compiler2_mir/src/reducible.rs::immediate_dominators @ d9be6853b
// Immediate dominators indexed by block (Cooper, Harvey & Kennedy, "A
// Simple, Fast Dominance Algorithm"). The entry is its own dominator;
// unreachable blocks keep `usize::MAX`.
function immediate_dominators(entry: int, succs: int[][], rpo: int[]) -> int[] throws never {
    baml.sys.panic("immediate_dominators: not ported (U5)")
}
