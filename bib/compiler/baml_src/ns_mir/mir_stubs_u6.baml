// Stubs for MIR unit 6 (escape, memory): every function the unit owns
// (escape.rs and memory.rs), in namespace `mir`, with its BAML
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
// - Rust's `u64` need masks (`NEVER = u64::MAX`, `MASKED_PARAMS = 64`) do
//   not fit BAML's 63-bit `int`: the fields typed `int` here
//   (`EscapeFacts.needs`, `Access.needs`, ...) are the unit's to
//   represent (two ints, or a `bigint`), keeping Rust's results.
// - `escape_summary`, `component_summaries` and `recursive_functions` are
//   memoized per OptLevel in `db.mir_memo` (db.baml); `escape_summary`
//   reads with `get_fallback`, falling back to null on a cycle.

// port: baml_compiler2_mir/src/escape.rs::EscapeFacts @ d9be6853b
// Renamed field: `twin_needs` is `twin_needs_value` (a method shares the
// name).
class EscapeFacts {
    twin_needs_value: int[],
    call_args: (int[]?)[],
    local_node: int[],
    shared: bool[],
    contents: (int?)[],
    needs: int[],

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::calls_thread_local_twin @ d9be6853b
    // Whether `block`'s modeled builtin receiver is thread-local.
    // Consumers check the function object for an available lock-free twin.
    function calls_thread_local_twin(self, block: int) -> bool throws never {
        baml.sys.panic("EscapeFacts::calls_thread_local_twin: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::twin_needs @ d9be6853b
    // The parameters `block`'s builtin call takes its lock-free twin given:
    // see `Self::object_needs`. `NEVER` when the call has no modeled receiver.
    // Twin availability belongs to the consumer's function object.
    function twin_needs(self, block: int) -> int throws never {
        baml.sys.panic("EscapeFacts::twin_needs: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::call_arg_needs @ d9be6853b
    // For a call to a source function in `block`, each value argument's
    // needs, from which the caller's locality mask for the callee follows:
    // bit `i` is set when argument `i`'s needs are not `NEVER` and the
    // caller's own mask covers them.
    function call_arg_needs(self, block: int) -> int[]? throws never {
        baml.sys.panic("EscapeFacts::call_arg_needs: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::contents_needs @ d9be6853b
    // The parameters every object held in a field or element of `local`'s
    // objects is thread-local given: an array iterator's array, for one.
    function contents_needs(self, local: int) -> int throws never {
        baml.sys.panic("EscapeFacts::contents_needs: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::object_is_thread_local @ d9be6853b
    // Whether the object `place` evaluates to is thread-local.
    function object_is_thread_local(self, place: Place) -> bool throws never {
        baml.sys.panic("EscapeFacts::object_is_thread_local: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::base_is_thread_local @ d9be6853b
    // Whether the object a field or element access goes through is
    // thread-local: the base of `place`. `false` for a place that is not a
    // projection.
    function base_is_thread_local(self, place: Place) -> bool throws never {
        baml.sys.panic("EscapeFacts::base_is_thread_local: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::local_is_thread_local @ d9be6853b
    // Whether every object `local` can hold is thread-local.
    function local_is_thread_local(self, local: int) -> bool throws never {
        baml.sys.panic("EscapeFacts::local_is_thread_local: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::contents_are_thread_local @ d9be6853b
    // Whether every object held in a field or element of `local`'s objects
    // is thread-local: an array iterator's array, for one.
    function contents_are_thread_local(self, local: int) -> bool throws never {
        baml.sys.panic("EscapeFacts::contents_are_thread_local: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::object_needs @ d9be6853b
    // The parameters the object `place` evaluates to is thread-local given:
    // bit `i` requires parameter `_{i+1}` and everything reachable from it to
    // be thread-local; `0` needs no caller proof. `NEVER` for an unnamed place.
    function object_needs(self, place: Place) -> int throws never {
        baml.sys.panic("EscapeFacts::object_needs: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::operand_needs @ d9be6853b
    // The parameters `operand`'s value and everything reachable from it are
    // thread-local given, the condition for passing it as a thread-local
    // argument. `0` for a value that is no object.
    function operand_needs(self, operand: Operand) -> int throws never {
        baml.sys.panic("EscapeFacts::operand_needs: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::object_node @ d9be6853b
    function object_node(self, place: Place) -> int? throws never {
        baml.sys.panic("EscapeFacts::object_node: not ported (U6)")
    }
}

// port: baml_compiler2_mir/src/escape.rs::Reason @ d9be6853b
type Reason = ReasonParameter
    | ReasonCaptured
    | ReasonHandler
    | ReasonConstant
    | ReasonCell
    | ReasonAt;

class ReasonParameter {
}

class ReasonCaptured {
}

class ReasonHandler {
}

class ReasonConstant {
}

class ReasonCell {
}

class ReasonAt {
    block: int,
    statement: int?,
}

// port: baml_compiler2_mir/src/escape.rs::Access @ d9be6853b
class Access {
    kind: AccessKind,
    thread_local: bool,
    shared_because: string?,
    needs: int,
}

// port: baml_compiler2_mir/src/escape.rs::AccessKind @ d9be6853b
enum AccessKind {
    Element,
    Length,
    Field,
    ContainerMethod,
    Iteration,
}

// port: baml_compiler2_mir/src/escape.rs::Summary @ d9be6853b
class Summary {
    nodes: (bool, int?)[],
    params: int[],
    ret: int,
}

// port: baml_compiler2_mir/src/escape.rs::Types @ d9be6853b
// Renamed field: Rust's `root` is `root_id`. Rust's `RefCell` cache is a
// plain map.
class Types {
    db: root.hir.Db,
    body: MirFunctionBody,
    root_id: int,
    fields: map<int, root.types.Ty[]?>,

    // port: baml_compiler2_mir/src/escape.rs::Types::may_finalize @ d9be6853b
    // `may_finalize` for a class built in this body.
    function may_finalize(self, class_: int) -> bool throws never {
        baml.sys.panic("Types::may_finalize: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::new @ d9be6853b
    function new(db: root.hir.Db, root_id: int, body: MirFunctionBody) -> Types throws never {
        baml.sys.panic("Types::new: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::immutable @ d9be6853b
    // Whether every value `place` can hold is immutable: a scalar, string,
    // bigint, enum or type, which holds no reference to anything mutable.
    function immutable(self, place: Place) -> bool throws never {
        baml.sys.panic("Types::immutable: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::primitive_map_keys @ d9be6853b
    // Whether the map `place` holds has primitive keys, which hash and
    // compare without running user code.
    function primitive_map_keys(self, place: Place) -> bool throws never {
        baml.sys.panic("Types::primitive_map_keys: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::local_ty @ d9be6853b
    function local_ty(self, place: Place) -> root.types.RuntimeTy? throws never {
        baml.sys.panic("Types::local_ty: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::field_ty @ d9be6853b
    // The declared type of slot `field` of the class `base` holds, when
    // `base` is a local of a known class.
    function field_ty(self, base: Place, field: int) -> root.types.Ty? throws never {
        baml.sys.panic("Types::field_ty: not ported (U6)")
    }
}

// port: baml_compiler2_mir/src/escape.rs::Walker @ d9be6853b
class Walker {
    db: root.hir.Db,
    opt: OptLevel,
    current: int?,
    component: map<int, (int, int)>?,
    types: Types,
    builtins: Builtins,
    array_iterators: bool[],

    // port: baml_compiler2_mir/src/escape.rs::Walker::terminator @ d9be6853b
    function terminator(self, graph: Graph, terminator: Terminator) -> void throws never {
        baml.sys.panic("Walker::terminator: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Walker::component_member @ d9be6853b
    // The offset and arity of a call's target within this graph, when it is
    // a body of the component being analyzed together.
    function component_member(self, callee: Operand) -> (int, int)? throws never {
        baml.sys.panic("Walker::component_member: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Walker::summary @ d9be6853b
    // The summary of a call's target, unless it is opaque or in the same
    // recursive component as the function being summarized.
    function summary(self, callee: Operand) -> Summary? throws never {
        baml.sys.panic("Walker::summary: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Walker::compares_against_immutable @ d9be6853b
    // `a == b` through `baml.ops.equals_equals` with an immutable operand:
    // operands of different kinds compare unequal and only two instances of
    // one class run a user `Equals`, so it runs no user code.
    function compares_against_immutable(
        self,
        callee: Operand,
        values: Operand[],
    ) -> bool throws never {
        baml.sys.panic("Walker::compares_against_immutable: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Walker::matches_builtin @ d9be6853b
    // Whether a call's value arguments fit `effect`: the declared arity and
    // a receiver place, whose keys, when it compares them, are primitive.
    function matches_builtin(self, effect: Effect, args: Operand[]) -> bool throws never {
        baml.sys.panic("Walker::matches_builtin: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Walker::array_iteration @ d9be6853b
    function array_iteration(self, terminator: Terminator) -> Iteration? throws never {
        baml.sys.panic("Walker::array_iteration: not ported (U6)")
    }
}

// port: baml_compiler2_mir/src/escape.rs::Iteration @ d9be6853b
type Iteration = IterationIter | IterationNext;

class IterationIter {
    array: int,
    iterator: int,
}

class IterationNext {
    iterator: int,
    item: int,
}

// port: baml_compiler2_mir/src/escape.rs::Effect @ d9be6853b
class Effect {
    arity: int,
    keeps: int[],
    returns: Returns,
    compares_keys: bool,
    leaks_contents: bool,
}

// port: baml_compiler2_mir/src/escape.rs::Returns @ d9be6853b
type Returns = ReturnsNothing | ReturnsElement | ReturnsFresh;

class ReturnsNothing {
}

class ReturnsElement {
}

class ReturnsFresh {
    value: int[],
}

// port: baml_compiler2_mir/src/escape.rs::Builtins @ d9be6853b
// Rust's `RefCell` cache is a plain map.
class Builtins {
    db: root.hir.Db,
    effects: map<int, Effect?>,
    equals_equals: int?,

    // port: baml_compiler2_mir/src/escape.rs::Builtins::new @ d9be6853b
    function new(db: root.hir.Db) -> Builtins throws never {
        baml.sys.panic("Builtins::new: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Builtins::effect @ d9be6853b
    function effect(self, callee: Operand) -> Effect? throws never {
        baml.sys.panic("Builtins::effect: not ported (U6)")
    }
}

// port: baml_compiler2_mir/src/escape.rs::Graph @ d9be6853b
// Renamed field: `shared` is `shared_value` (a method shares the name).
class Graph {
    types: Types,
    parent: int[],
    shared_value: bool[],
    contents: (int?)[],
    reason: Reason[],
    cause: Reason,
    locals: int,
    offset: int,

    // port: baml_compiler2_mir/src/escape.rs::Graph::new @ d9be6853b
    function new(locals: int, types: Types) -> Graph throws never {
        baml.sys.panic("Graph::new: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::local @ d9be6853b
    function local(self, local: int) -> int throws never {
        baml.sys.panic("Graph::local: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::fresh @ d9be6853b
    function fresh(self) -> int throws never {
        baml.sys.panic("Graph::fresh: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::shared @ d9be6853b
    // A node for a value that may already be reachable from anywhere.
    function shared(self) -> int throws never {
        baml.sys.panic("Graph::shared: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::find @ d9be6853b
    function find(self, node: int) -> int throws never {
        baml.sys.panic("Graph::find: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::mark_shared @ d9be6853b
    function mark_shared(self, node: int) -> void throws never {
        baml.sys.panic("Graph::mark_shared: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::shared_because @ d9be6853b
    // `Self::shared`, for a value shared for `reason` rather than the cause.
    function shared_because(self, reason: Reason) -> int throws never {
        baml.sys.panic("Graph::shared_because: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::contents_of @ d9be6853b
    // The contents node of `node`'s objects, created on first use. A value
    // that is no object has no contents; reading through one is a type
    // error the checker already rejected, so it yields a shared node.
    function contents_of(self, node: int?) -> int throws never {
        baml.sys.panic("Graph::contents_of: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::operand @ d9be6853b
    // The node an operand's value belongs to; `None` when it is no object.
    function operand(self, operand: Operand) -> int? throws never {
        baml.sys.panic("Graph::operand: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::read @ d9be6853b
    function read(self, place: Place) -> int throws never {
        baml.sys.panic("Graph::read: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::write @ d9be6853b
    function write(self, place: Place, value: int?) -> void throws never {
        baml.sys.panic("Graph::write: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::write_shared @ d9be6853b
    function write_shared(self, place: Place) -> void throws never {
        baml.sys.panic("Graph::write_shared: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::leak @ d9be6853b
    // `operand`'s value may now be reachable from anywhere.
    function leak(self, operand: Operand) -> void throws never {
        baml.sys.panic("Graph::leak: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::unknown @ d9be6853b
    // A call the analysis cannot see through: its arguments and callee leak,
    // and its result comes from anywhere.
    function unknown(
        self,
        args: Operand[],
        destination: Place,
        callee: Operand?,
    ) -> void throws never {
        baml.sys.panic("Graph::unknown: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::statement @ d9be6853b
    function statement(self, kind: StatementKind) -> void throws never {
        baml.sys.panic("Graph::statement: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::rvalue @ d9be6853b
    // The node an rvalue's result belongs to; `None` when it is no object.
    function rvalue(self, rvalue: Rvalue) -> int? throws never {
        baml.sys.panic("Graph::rvalue: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::apply_builtin @ d9be6853b
    // Apply a builtin's effect to arguments `Walker::matches_builtin`
    // accepted, returning the node its result belongs to.
    function apply_builtin(self, effect: Effect, args: Operand[]) -> int? throws never {
        baml.sys.panic("Graph::apply_builtin: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::summary @ d9be6853b
    // The summary of the body whose locals start at `offset`, as a callee
    // with `arity` parameters, before its parameters are classified.
    function summary(self, offset: int, arity: int) -> Summary throws never {
        baml.sys.panic("Graph::summary: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::apply_summary @ d9be6853b
    // A call to a summarized callee: a fresh copy of its graph, joined to the
    // arguments and the destination.
    function apply_summary(
        self,
        summary: Summary,
        args: Operand[],
        destination: Place,
    ) -> void throws never {
        baml.sys.panic("Graph::apply_summary: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::flow @ d9be6853b
    // `value` may now be held wherever `into` is.
    function flow(self, into: int?, value: int?) -> void throws never {
        baml.sys.panic("Graph::flow: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::union @ d9be6853b
    function union(self, a: int, b: int) -> void throws never {
        baml.sys.panic("Graph::union: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::finish @ d9be6853b
    // Resolve every node to its root and push sharing into contents, with
    // each node's locality conditioned on the `arity` parameters.
    function finish(self, arity: int) -> EscapeFacts throws never {
        baml.sys.panic("Graph::finish: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::resolve @ d9be6853b
    // Every node's root, and per root its contents and whether sharing
    // reaches it, from itself or from any node whose contents it is.
    function resolve(self) -> Resolved throws never {
        baml.sys.panic("Graph::resolve: not ported (U6)")
    }
}

// port: baml_compiler2_mir/src/escape.rs::Resolved @ d9be6853b
class Resolved {
    roots: int[],
    shared: bool[],
    contents: (int?)[],
    reasons: Reason[],

    // port: baml_compiler2_mir/src/escape.rs::Resolved::param_needs @ d9be6853b
    // Per node, the first `params` parameters it is thread-local given: a
    // node is reachable from a parameter's argument when it is the
    // parameter's node or within its contents, and marking that parameter
    // shared would make exactly those nodes shared.
    function param_needs(self, params: int) -> int[] throws never {
        baml.sys.panic("Resolved::param_needs: not ported (U6)")
    }
}

// port: baml_compiler2_mir/src/memory.rs::Resources @ d9be6853b
class Resources {
    locals: map<int, bool>,
    cells: map<CellId, bool>,
    type_slots: map<int, bool>,
    fields: map<int, bool>,
    elements: bool,
    heap: bool,
    order: bool,

    // port: baml_compiler2_mir/src/memory.rs::Resources::is_empty @ d9be6853b
    function is_empty(self) -> bool throws never {
        baml.sys.panic("Resources::is_empty: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/memory.rs::Resources::extend @ d9be6853b
    function extend(self, other: Resources) -> void throws never {
        baml.sys.panic("Resources::extend: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/memory.rs::Resources::touches_heap @ d9be6853b
    // Whether the set names any heap location.
    function touches_heap(self) -> bool throws never {
        baml.sys.panic("Resources::touches_heap: not ported (U6)")
    }

    // port: baml_compiler2_mir/src/memory.rs::Resources::intersects @ d9be6853b
    // Whether some resource is in both sets. Symmetric: `heap` on either side
    // meets any heap location on the other.
    function intersects(self, other: Resources) -> bool throws never {
        baml.sys.panic("Resources::intersects: not ported (U6)")
    }
}

// port: baml_compiler2_mir/src/memory.rs::ClobberModel @ d9be6853b
class ClobberModel {
    registers_observed: bool,

    // port: baml_compiler2_mir/src/memory.rs::ClobberModel::for_body @ d9be6853b
    function for_body(body: MirFunctionBody) -> ClobberModel throws never {
        baml.sys.panic("ClobberModel::for_body: not ported (U6)")
    }
}

// port: baml_compiler2_mir/src/escape.rs::analyze @ d9be6853b
// Classify every object `body` names. `arity` is the parameter count;
// parameters are `_1..=_arity`. Calls to functions with a summary
// (`escape_summary`) in `root` or the stdlib are seen through, at `opt`.
function analyze(
    db: root.hir.Db,
    root_id: int,
    body: MirFunctionBody,
    arity: int,
    opt: OptLevel,
) -> EscapeFacts throws never {
    baml.sys.panic("analyze: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::escape_summary @ d9be6853b
// What calling `function` does with its arguments and result, for callers:
// its graph, restricted to what its parameters and return value reach, with
// parameters assumed thread-local. `None` when the analysis cannot see the
// body (a builtin, or lowering failed), so callers treat the call as opaque.
function escape_summary(db: root.hir.Db, function_: int, opt: OptLevel) -> Summary? throws never {
    baml.sys.panic("escape_summary: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::component_summaries @ d9be6853b
// The summaries of one component of `recursive_functions`, from one graph
// of all its bodies: a call within the component joins its arguments to the
// callee's parameters and its destination to the callee's return value, as
// every call of that callee in the component does. A member whose body the
// analysis cannot see has no summary, and calls to it are opaque.
function component_summaries(
    db: root.hir.Db,
    root_id: int,
    opt: OptLevel,
    component: int,
) -> map<int, Summary> throws never {
    baml.sys.panic("component_summaries: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::escape_summary_cycle @ d9be6853b
// A cycle `recursive_functions` did not see (a runtime-compiled
// submission): opaque, which is always sound.
function escape_summary_cycle(
    _db: root.hir.Db,
    _id: int,
    _function: int,
    _opt: OptLevel,
) -> Summary? throws never {
    baml.sys.panic("escape_summary_cycle: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::recursive_functions @ d9be6853b
// The functions of `root` that can reach themselves through direct calls,
// by strongly connected component. A call within one component is opaque
// to `escape_summary`, so summaries never depend on themselves.
function recursive_functions(
    db: root.hir.Db,
    root_id: int,
    opt: OptLevel,
) -> map<int, int> throws never {
    baml.sys.panic("recursive_functions: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::direct_callees @ d9be6853b
// Every source function `function`'s body or lambdas call directly.
function direct_callees(
    function_: MirFunction,
    visit: (int) -> void throws never,
) -> void throws never {
    baml.sys.panic("direct_callees: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::static_callee @ d9be6853b
function static_callee(callee: Operand) -> int? throws never {
    baml.sys.panic("static_callee: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::can_summarize @ d9be6853b
// User dependency bodies must not affect a caller's artifact: a mounted
// dependency exposes the same declarations but no MIR. Embedded stdlib source
// remains eligible in source compiles; runtime compilation can mount it opaque.
function can_summarize(db: root.hir.Db, caller: int, callee: int) -> bool throws never {
    baml.sys.panic("can_summarize: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::may_finalize @ d9be6853b
// Whether an instance of `class` built in `caller` may have a finalizer.
// Read from source only where `can_summarize` sees bodies, so a user
// dependency answers the same mounted or not: anything else may.
function may_finalize(db: root.hir.Db, caller: int, class_: int) -> bool throws never {
    baml.sys.panic("may_finalize: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::build @ d9be6853b
// The constraint graph of one body, before its parameters are classified.
function build(
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
    opt: OptLevel,
    current: int?,
    types: Types,
) -> Graph throws never {
    baml.sys.panic("build: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::walk @ d9be6853b
// Add `body`'s constraints to `graph`, whose locals for it start at
// `graph.offset` and whose types are `body`'s. `component` places the other
// bodies of a recursive component in the same graph: each callee's node
// offset and arity.
function walk(
    graph: Graph,
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
    opt: OptLevel,
    current: int?,
    component: map<int, (int, int)>?,
) -> void throws never {
    baml.sys.panic("walk: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::coverage @ d9be6853b
// Every container and field access in `body`, classified as `analyze`
// classifies it, with the reason for each shared one. For measuring the
// analysis, not for compiling.
function coverage(
    db: root.hir.Db,
    root_id: int,
    body: MirFunctionBody,
    arity: int,
    opt: OptLevel,
) -> Access[] throws never {
    baml.sys.panic("coverage: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::projections @ d9be6853b
// Each field or element access within `place`, with the place of the object
// it goes through.
function projections(
    place: Place,
    visit: (AccessKind, Place) -> void throws never,
) -> void throws never {
    baml.sys.panic("projections: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::terminator_places @ d9be6853b
// The operands a terminator reads and the places it writes.
function terminator_places(terminator: Terminator) -> (Operand[], Place[]) throws never {
    baml.sys.panic("terminator_places: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::describe @ d9be6853b
function describe(
    db: root.hir.Db,
    root_id: int,
    body: MirFunctionBody,
    opt: OptLevel,
    reason: Reason,
) -> string throws never {
    baml.sys.panic("describe: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::immutable @ d9be6853b
// Lowering types some temporaries `null` while they hold an object (an
// awaited future, a sys-op result), so a bare `null` proves nothing.
function immutable(ty: root.types.RuntimeTy) -> bool throws never {
    baml.sys.panic("immutable: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::immutable_value @ d9be6853b
function immutable_value(ty: root.types.RuntimeTy) -> bool throws never {
    baml.sys.panic("immutable_value: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::immutable_ty @ d9be6853b
function immutable_ty(ty: root.types.Ty) -> bool throws never {
    baml.sys.panic("immutable_ty: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::primitive_ty @ d9be6853b
function primitive_ty(ty: root.types.Ty) -> bool throws never {
    baml.sys.panic("primitive_ty: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::array_walks @ d9be6853b
// Iterator locals a backend may compile as an index walk over the array:
// defined once, by `xs.iter()` on an array local, not captured, and
// mentioned nowhere but as the receiver of `next`. Such an iterator is never
// observed, so the walk is the same loop without the object.
function array_walks(db: root.hir.Db, body: MirFunctionBody, arity: int) -> bool[] throws never {
    baml.sys.panic("array_walks: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::array_iterators @ d9be6853b
// Locals whose only definition is `xs.iter()` on an array: the runtime's
// `ArrayIterator`, whose `next` reads the array and nothing else.
function array_iterators(
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
) -> bool[] throws never {
    baml.sys.panic("array_iterators: not ported (U6)")
}

// port: baml_compiler2_mir/src/escape.rs::is_primitive @ d9be6853b
function is_primitive(ty: root.types.RuntimeTy) -> bool throws never {
    baml.sys.panic("is_primitive: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::walk_operand_places @ d9be6853b
// Walk every place an operand names, calling `f` for each.
function walk_operand_places(
    operand: Operand,
    f: (Place) -> void throws never,
) -> void throws never {
    baml.sys.panic("walk_operand_places: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::walk_rvalue_places @ d9be6853b
// Walk every place an rvalue reads, calling `f` for each. The one traversal
// every reader of an rvalue's operands goes through, so no two can disagree
// about which operands evaluating it touches.
function walk_rvalue_places(rvalue: Rvalue, f: (Place) -> void throws never) -> void throws never {
    baml.sys.panic("walk_rvalue_places: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::walk_rvalue_type_slots @ d9be6853b
// Walk every frame type-arg slot an rvalue reads: the `TypeArgRef` leaves of
// each template it carries: calling `f` for each.
function walk_rvalue_type_slots(
    rvalue: Rvalue,
    f: (int) -> void throws never,
) -> void throws never {
    baml.sys.panic("walk_rvalue_type_slots: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::walk_statement_type_slots @ d9be6853b
// Walk every frame type-arg slot a statement reads, calling `f` for each.
function walk_statement_type_slots(
    kind: StatementKind,
    f: (int) -> void throws never,
) -> void throws never {
    baml.sys.panic("walk_statement_type_slots: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::walk_terminator_type_slots @ d9be6853b
// Walk every frame type-arg slot a terminator reads, calling `f` for each.
function walk_terminator_type_slots(
    terminator: Terminator,
    f: (int) -> void throws never,
) -> void throws never {
    baml.sys.panic("walk_terminator_type_slots: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::place_cell @ d9be6853b
// The cell a place reads or writes through, if it goes through one.
function place_cell(place: Place) -> CellId? throws never {
    baml.sys.panic("place_cell: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::rvalue_reads_cell @ d9be6853b
// Whether evaluating an rvalue reads through a cell anywhere.
function rvalue_reads_cell(rvalue: Rvalue) -> bool throws never {
    baml.sys.panic("rvalue_reads_cell: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::spawn_shared_cells @ d9be6853b
// The cells a body shares with the tasks it spawns: every cell a spawned
// closure captures, and every cell a closure stored in one of those cells
// captures in turn (a spawned body that calls a captured closure reaches
// that closure's cells).
function spawn_shared_cells(body: MirFunctionBody) -> map<CellId, bool> throws never {
    baml.sys.panic("spawn_shared_cells: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::place_reads @ d9be6853b
// Record the resources reading a place touches.
function place_reads(place: Place, out: Resources) -> void throws never {
    baml.sys.panic("place_reads: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::rvalue_reads @ d9be6853b
// The resources evaluating an rvalue reads.
function rvalue_reads(
    body: MirFunctionBody,
    rvalue: Rvalue,
    track_type_slots: bool,
) -> Resources throws never {
    baml.sys.panic("rvalue_reads: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::place_writes @ d9be6853b
// Record the resources a store to a place writes.
function place_writes(place: Place, out: Resources) -> void throws never {
    baml.sys.panic("place_writes: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::statement_clobbers @ d9be6853b
// The resources a statement writes.
function statement_clobbers(
    body: MirFunctionBody,
    model: ClobberModel,
    kind: StatementKind,
) -> Resources throws never {
    baml.sys.panic("statement_clobbers: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::terminator_clobbers @ d9be6853b
// The resources a terminator writes.
function terminator_clobbers(
    model: ClobberModel,
    terminator: Terminator,
) -> Resources throws never {
    baml.sys.panic("terminator_clobbers: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::block_entry_clobbers @ d9be6853b
// The resources the VM writes when control enters `block`: a catch handler
// receives its error and context bindings with no statement saying so.
function block_entry_clobbers(body: MirFunctionBody, block: int) -> Resources throws never {
    baml.sys.panic("block_entry_clobbers: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::rvalue_allocates_identity @ d9be6853b
// Whether evaluating this rvalue allocates a fresh object whose identity is
// observable (mutable containers, class instances, and callable objects), so
// evaluating it more times than the program does is itself observable.
function rvalue_allocates_identity(rvalue: Rvalue) -> bool throws never {
    baml.sys.panic("rvalue_allocates_identity: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::rvalue_can_trap @ d9be6853b
// Can evaluating this rvalue raise a catchable panic (`baml.panics.*`)?
function rvalue_can_trap(body: MirFunctionBody, rvalue: Rvalue) -> bool throws never {
    baml.sys.panic("rvalue_can_trap: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::place_indexes @ d9be6853b
// Whether a place goes through an index projection anywhere in its chain.
function place_indexes(place: Place) -> bool throws never {
    baml.sys.panic("place_indexes: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::operand_could_be_int @ d9be6853b
// Could this operand hold an `int` at runtime?
function operand_could_be_int(body: MirFunctionBody, operand: Operand) -> bool throws never {
    baml.sys.panic("operand_could_be_int: not ported (U6)")
}

// port: baml_compiler2_mir/src/memory.rs::ty_could_be_int @ d9be6853b
// See `operand_could_be_int`. The `_ => true` fallback keeps an unlisted or
// newly added variant on the conservative side.
function ty_could_be_int(ty: root.types.RuntimeTy) -> bool throws never {
    baml.sys.panic("ty_could_be_int: not ported (U6)")
}
