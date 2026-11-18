// port: baml_compiler2_mir/src/escape.rs @ d9be6853b
//
// Which heap objects another thread may reach.
//
// BEP-034 `spawn` lets several VMs share one heap, so every container
// access takes a lock and every field access is atomic. An object only this
// thread can reach needs neither. This analysis finds those objects, per
// function body, so each backend can pick the unsynchronized accessor at an
// access site whose object is thread-local.
//
// An object is thread-local when it was allocated by this invocation and no
// reference to it can have left the invocation's thread: it never reached a
// call the analysis cannot see through, a spawn, a sys-op, a cell, a
// closure, the runtime, or a heap object that is itself not thread-local.
// Returning it is not a leak: the invocation is over by then, and the
// caller sees an unknown call result, which is never thread-local.
//
// The model is unification-based points-to (Steensgaard): one abstract node
// per local, merged by every copy, with one `contents` node standing for
// every field and element of the objects a node holds. Field- and
// flow-insensitive, so linear in the size of the body. A node is shared
// when anything it holds may be reachable from another thread, or did not
// come from an allocation this analysis saw; sharing flows from a node to
// its contents. Everything the analysis cannot name is shared, so a missed
// case costs a lock, never a race.
//
// Restructured (BAML forces it):
// - Locality masks are `bigint`, not `u64`: a mask has one bit per
//   parameter up to `MASKED_PARAMS = 64`, and `NEVER` is all 64 bits set,
//   which BAML's 63-bit `int` cannot hold. A `bigint` keeps every bit,
//   compares by value (`NEVER`, `0n`), and has `|`, `&` and `<<`, so every
//   mask expression reads as Rust's. Two `int` halves would split each
//   operation in two, and a `bool[]` per mask would make the equality tests
//   element walks.
// - `FunctionRef` / `ClassRef` are their Source lane, a loc `int` (ir.baml):
//   `DeclRef::Source(f)` always matches and `DeclRef::External` never
//   occurs, so `Builtins::effect`'s external arm and `may_finalize`'s
//   non-source early return are absent.
// - The `RefCell` caches (`Types.fields`, `Builtins.effects`) are plain
//   maps; Rust's `entry().or_insert_with` is a `has` test, since a cached
//   value may be null.
// - Borrowed views (`&Types`, `&Builtins`, `&[bool]`, `&Summary`) are
//   shared references, never mutated through.
// - `Reason` is `Copy` in Rust; its instances here are never mutated, so
//   sharing one between nodes is the same.
// - `coverage`'s `record` / `place` closures capture what Rust passes as
//   `&mut dyn FnMut`.
// - `EFFECTS` holds `(native key, Effect)` pairs; `Effect.keeps` and
//   `ReturnsFresh.value` are `int[]`.
//
// Not ported: the hot-swap early return in `can_summarize` (added upstream
// after `BASE`).

// port: baml_compiler2_mir/src/escape.rs::NEVER @ d9be6853b
// Locality mask of a node that is shared whatever the caller passes:
// `u64::MAX`.
const NEVER: bigint = 18446744073709551615n;

// port: baml_compiler2_mir/src/escape.rs::MASKED_PARAMS @ d9be6853b
// Parameters past this many are always shared: a locality mask has one bit
// per parameter.
const MASKED_PARAMS: int = 64;

// port: baml_compiler2_mir/src/escape.rs::EscapeFacts @ d9be6853b
// The thread-locality of every object a body names.
// Renamed field: `twin_needs` is `twin_needs_value` (a method shares the
// name).
class EscapeFacts {
    // Per block: the parameters its terminator's builtin call takes the
    // thread-local twin given (`needs`), or `NEVER`.
    twin_needs_value: bigint[],
    // Per block: for a call to a source function, each value argument's
    // `operand_needs`, `NEVER` for an argument with nothing to
    // synchronize; the caller passes the callee a locality mask from them.
    // Null for any other terminator.
    call_args: (bigint[]?)[],
    // The node each local's value belongs to.
    local_node: int[],
    // Per node: whether another thread may reach what it holds, as far as
    // this body knows: when a caller passes nothing it proved thread-local.
    shared: bool[],
    // Per node: the node every field and element of its objects belongs to.
    contents: (int?)[],
    // Per node: the parameters it is thread-local given, as a mask (bit `i`
    // for parameter `_{i+1}`), or `NEVER`. A caller's bit for a parameter
    // says its argument and everything reachable from it are thread-local;
    // `0` is thread-local whatever the caller passes.
    needs: bigint[],

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::calls_thread_local_twin @ d9be6853b
    // Whether `block`'s modeled builtin receiver is thread-local.
    // Consumers check the function object for an available lock-free twin.
    function calls_thread_local_twin(self, block: int) -> bool throws never {
        self.twin_needs(block) == 0n
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::twin_needs @ d9be6853b
    // The parameters `block`'s builtin call takes its lock-free twin given:
    // see `object_needs`. `NEVER` when the call has no modeled receiver.
    // Twin availability belongs to the consumer's function object.
    function twin_needs(self, block: int) -> bigint throws never {
        self.twin_needs_value.at(block) ?? NEVER
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::call_arg_needs @ d9be6853b
    // For a call to a source function in `block`, each value argument's
    // needs, from which the caller's locality mask for the callee follows:
    // bit `i` is set when argument `i`'s needs are not `NEVER` and the
    // caller's own mask covers them.
    function call_arg_needs(self, block: int) -> bigint[]? throws never {
        self.call_args.at(block)
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::contents_needs @ d9be6853b
    // The parameters every object held in a field or element of `local`'s
    // objects is thread-local given: an array iterator's array, for one.
    function contents_needs(self, local: int) -> bigint throws never {
        let node = self.local_node.at(local)
            ?? return NEVER;
        let contents = self.contents[node]
            ?? return NEVER;
        self.needs[contents]
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::object_is_thread_local @ d9be6853b
    // Whether the object `place` evaluates to is thread-local.
    function object_is_thread_local(self, place: Place) -> bool throws never {
        let node = self.object_node(place);
        node != null && !self.shared[node]
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::base_is_thread_local @ d9be6853b
    // Whether the object a field or element access goes through is
    // thread-local: the base of `place`. `false` for a place that is not a
    // projection.
    function base_is_thread_local(self, place: Place) -> bool throws never {
        match (place) {
            let p: PlaceField => self.object_is_thread_local(p.base),
            let p: PlaceIndex => self.object_is_thread_local(p.base),
            PlaceLocal | PlaceCapture | PlaceDeref => false,
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::local_is_thread_local @ d9be6853b
    // Whether every object `local` can hold is thread-local.
    function local_is_thread_local(self, local: int) -> bool throws never {
        self.object_is_thread_local(PlaceLocal { value: local })
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::contents_are_thread_local @ d9be6853b
    // Whether every object held in a field or element of `local`'s objects
    // is thread-local: an array iterator's array, for one.
    function contents_are_thread_local(self, local: int) -> bool throws never {
        let node = self.local_node.at(local)
            ?? return false;
        let contents = self.contents[node]
            ?? return false;
        !self.shared[contents]
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::object_needs @ d9be6853b
    // The parameters the object `place` evaluates to is thread-local given:
    // bit `i` requires parameter `_{i+1}` and everything reachable from it
    // to be thread-local; `0` needs no caller proof. `NEVER` for an unnamed
    // place.
    function object_needs(self, place: Place) -> bigint throws never {
        let node = self.object_node(place)
            ?? return NEVER;
        self.needs[node]
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::operand_needs @ d9be6853b
    // The parameters `operand`'s value and everything reachable from it are
    // thread-local given, the condition for passing it as a thread-local
    // argument. `0` for a value that is no object.
    function operand_needs(self, operand: Operand) -> bigint throws never {
        let place = match (operand) {
            let c: OperandCopy => c.value,
            let m: OperandMove => m.value,
            OperandConstant => {
                return 0n;
            },
        };
        let node: int? = self.object_node(place);
        if (node == null) {
            return NEVER;
        }
        let needs = 0n;
        let seen: int[] = [];
        while let current: int = node {
            needs = needs | self.needs[current];
            seen.push(current);
            let inner = self.contents[current];
            node
                = if (inner != null && !seen.includes(inner)) {
                    inner
                } else {
                    null
                };
        }
        needs
    }

    // port: baml_compiler2_mir/src/escape.rs::EscapeFacts::object_node @ d9be6853b
    function object_node(self, place: Place) -> int? throws never {
        match (place) {
            let l: PlaceLocal => self.local_node.at(l.value),
            PlaceField { base: let base } | PlaceIndex { base: let base } => {
                let node = self.object_node(base)
                    ?? return null;
                self.contents[node]
            },
            PlaceCapture | PlaceDeref => null,
        }
    }
}

// port: baml_compiler2_mir/src/escape.rs::analyze @ d9be6853b
// Classify every object `body` names. `arity` is the parameter count;
// parameters are `_1..=_arity`. Calls to functions with a summary
// (`escape_summary`) in `root_id` or the stdlib are seen through, at `opt`.
function analyze(
    db: root.hir.Db,
    root_id: int,
    body: MirFunctionBody,
    arity: int,
    opt: OptLevel,
) -> EscapeFacts throws never {
    let types = Types.new(db, root_id, body);
    let facts = build(db, body, arity, opt, null, types).finish(arity);
    let builtins = Builtins.new(db);
    let calls: ((Operand, Operand[])?)[] = body.blocks.map((block) -> {
        match (block.terminator) {
            let t: TerminatorCall => {
                let named_slot = t.argument_layout?.value.some((slot) -> {
                    slot != null
                })
                    ?? false;
                if (t.has_trace || named_slot) {
                    return null;
                }
                (t.callee, t.args.slice(t.ntypeargs, t.args.length()))
            },
            _ => null,
        }
    });
    facts.twin_needs_value
        = calls.map((call) -> {
            if (call == null) {
                return NEVER;
            }
            let effect = builtins.effect(call.0);
            if (effect == null || effect.arity <= 0) {
                return NEVER;
            }
            match (call.1.at(0)) {
                let c: OperandCopy => facts.object_needs(c.value),
                let m: OperandMove => facts.object_needs(m.value),
                _ => NEVER,
            }
        });
    facts.call_args
        = calls.map((call) -> {
            if (call == null) {
                return null;
            }
            if (static_callee(call.0) == null) {
                return null;
            }
            if (builtins.effect(call.0) != null) {
                return null;
            }
            let needs: bigint[] = call.1.map((value) -> {
                match (value) {
                    OperandCopy { value: let place } | OperandMove { value: let place }
                        if !types.immutable(place) => {
                        facts.operand_needs(value)
                    },
                    _ => NEVER,
                }
            });
            if (
                needs.some((n) -> {
                    n != NEVER
                })
            ) {
                needs
            } else {
                null
            }
        });
    facts
}

// port: baml_compiler2_mir/src/escape.rs::escape_summary @ d9be6853b
// What calling `function_` does with its arguments and result, for
// callers: its graph, restricted to what its parameters and return value
// reach, with parameters assumed thread-local. Null when the analysis
// cannot see the body (a builtin, or lowering failed), so callers treat the
// call as opaque. Memoized per OptLevel; a cycle falls back to
// `escape_summary_cycle` (salsa's `cycle_result`).
function escape_summary(db: root.hir.Db, function_: int, opt: OptLevel) -> Summary? throws never {
    db.mir_memo.escape_summary_memo(opt).get_fallback(
        db.cycles,
        function_,
        () -> {
            escape_summary_cycle(db, function_, function_, opt)
        },
        () -> {
            let root_id = db.file(db.function_locs.get(function_).file).root;
            let component = recursive_functions(db, root_id, opt).get(function_);
            if (component != null) {
                return component_summaries(db, root_id, opt, component).get(function_);
            }
            let lowered: MirFunction? = lower_function(db, function_, opt) catch (e) {
                MirInternalError => null,
            };
            let mir = lowered
                ?? return null;
            let body = match (mir.kind) {
                let b: MirFunctionKindBytecode => b.value,
                MirFunctionKindBuiltin => {
                    return null;
                },
            };
            let types = Types.new(db, root_id, body);
            build(db, body, mir.arity, opt, function_, types).summary(0, mir.arity)
        },
    )
}

// port: baml_compiler2_mir/src/escape.rs::component_summaries @ d9be6853b
// The summaries of one component of `recursive_functions`, from one graph
// of all its bodies: a call within the component joins its arguments to
// the callee's parameters and its destination to the callee's return
// value, as every call of that callee in the component does. A member
// whose body the analysis cannot see has no summary, and calls to it are
// opaque. Memoized per OptLevel, keyed by `(root_id, component)` through
// `component_keys`.
//
// Members are sorted by loc id, Rust's sort by salsa id: both are interned
// in creation order. Only the graph's internal node numbering depends on
// that order. A summary is read back structurally (which of the member's
// locals share a root, their sharing, and their contents edges, walked
// from its own parameters), and union-find merges the same sets whatever
// the numbering, so the summaries do not depend on it.
function component_summaries(
    db: root.hir.Db,
    root_id: int,
    opt: OptLevel,
    component: int,
) -> map<int, Summary> throws never {
    let key = db.mir_memo.component_keys.intern(root_id, component);
    db.mir_memo.component_summaries_memo(opt).get(db.cycles, key, () -> {
        let recursive = recursive_functions(db, root_id, opt);
        let members: (int, MirFunction, MirFunctionBody)[] = [];
        for (let function_ in recursive.keys()) {
            if (recursive[function_] != component) {
                continue;
            }
            let lowered: MirFunction? = lower_function(db, function_, opt) catch (e) {
                MirInternalError => null,
            };
            if (lowered == null) {
                continue;
            }
            match (lowered.kind) {
                let b: MirFunctionKindBytecode => members.push((function_, lowered, b.value)),
                MirFunctionKindBuiltin => {},
            }
        }
        // Node numbering, and so the summaries, must not depend on map order.
        members.sort_by_key((member) -> {
            member.0
        });
        let types: Types[] = members.map((member) -> {
            Types.new(db, root_id, member.2)
        });
        let offsets: map<int, (int, int)> = {};
        let total = 0;
        for (let member in members) {
            offsets[member.0] = (total, member.1.arity);
            total += member.2.locals.length();
        }
        let first = types.at(0)
            ?? return {};
        let graph = Graph.new(total, first);
        for (let index = 0; index < members.length(); index += 1) {
            let member = members[index];
            graph.offset = offsets[member.0].0;
            graph.types = types[index];
            walk(graph, db, member.2, member.1.arity, opt, null, offsets);
        }
        let summaries: map<int, Summary> = {};
        for (let member in members) {
            summaries[member.0] = graph.summary(offsets[member.0].0, member.1.arity);
        }
        summaries
    })
}

// port: baml_compiler2_mir/src/escape.rs::escape_summary_cycle @ d9be6853b
// A cycle `recursive_functions` did not see (a runtime-compiled
// submission): opaque, which is always sound. `_id` is salsa's query id;
// `escape_summary` passes its memo key.
function escape_summary_cycle(
    _db: root.hir.Db,
    _id: int,
    _function: int,
    _opt: OptLevel,
) -> Summary? throws never {
    null
}

// port: baml_compiler2_mir/src/escape.rs::recursive_functions @ d9be6853b
// The functions of `root_id` that can reach themselves through direct
// calls, by strongly connected component. A call within one component is
// opaque to `escape_summary`, so summaries never depend on themselves.
// Memoized per OptLevel. Rust's `FxHashMap<FunctionLoc, usize>` is a
// `map<int, int>`, filled in component order.
function recursive_functions(
    db: root.hir.Db,
    root_id: int,
    opt: OptLevel,
) -> map<int, int> throws never {
    db.mir_memo.recursive_functions_memo(opt).get(db.cycles, root_id, () -> {
        let functions: int[] = [];
        for (let file in db.source_root(root_id).files) {
            root.base.extend(functions, root.hir.file_functions(db, file));
        }
        let index: map<int, int> = {};
        for (let i = 0; i < functions.length(); i += 1) {
            index[functions[i]] = i;
        }
        let edges: int[][] = functions.map((function_) -> {
            let callees: int[] = [];
            let lowered: MirFunction? = lower_function(db, function_, opt) catch (e) {
                MirInternalError => null,
            };
            if (lowered != null) {
                direct_callees(lowered, (callee) -> {
                    let callee_index = index.get(callee);
                    if (
                        db.file(db.function_locs.get(callee).file).root == root_id
                            && callee_index != null
                    ) {
                        callees.push(callee_index);
                    }
                });
            }
            callees
        });
        let recursive: map<int, int> = {};
        let components = root.hir_ty.strongly_connected_components(edges);
        for (let id = 0; id < components.length(); id += 1) {
            let component = components[id];
            if (component.length() > 1 || edges[component[0]].includes(component[0])) {
                for (let f in component) {
                    recursive[functions[f]] = id;
                }
            }
        }
        recursive
    })
}

// port: baml_compiler2_mir/src/escape.rs::direct_callees @ d9be6853b
// Every source function `function_`'s body or lambdas call directly.
function direct_callees(
    function_: MirFunction,
    visit: (int) -> void throws never,
) -> void throws never {
    match (function_.kind) {
        let b: MirFunctionKindBytecode => {
            for (let block in b.value.blocks) {
                match (block.terminator) {
                    let t: TerminatorCall => {
                        let callee = static_callee(t.callee);
                        if (callee != null) {
                            visit(callee);
                        }
                    },
                    _ => {},
                }
            }
        },
        MirFunctionKindBuiltin => {},
    }
    for (let lambda in function_.lambdas) {
        direct_callees(lambda, visit);
    }
}

// port: baml_compiler2_mir/src/escape.rs::static_callee @ d9be6853b
function static_callee(callee: Operand) -> int? throws never {
    match (callee) {
        let c: OperandConstant => {
            match (c.value) {
                let f: ConstantFunction => f.value,
                let g: ConstantGenericFunction => g.func,
                _ => null,
            }
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/escape.rs::can_summarize @ d9be6853b
// User dependency bodies must not affect a caller's artifact: a mounted
// dependency exposes the same declarations but no MIR. Embedded stdlib
// source remains eligible in source compiles; runtime compilation can mount
// it opaque.
function can_summarize(db: root.hir.Db, caller: int, callee: int) -> bool throws never {
    let root_id = db.file(db.function_locs.get(callee).file).root;
    root_id == caller || db.source_root(root_id).kind == root.base.SourceRootKind.Stdlib
}

// port: baml_compiler2_mir/src/escape.rs::may_finalize @ d9be6853b
// Whether an instance of `class_` built in `caller` may have a finalizer.
// Read from source only where `can_summarize` sees bodies, so a user
// dependency answers the same mounted or not: anything else may.
function may_finalize(db: root.hir.Db, caller: int, class_: int) -> bool throws never {
    let root_id = db.file(db.class_locs.get(class_).file).root;
    if (root_id != caller && db.source_root(root_id).kind != root.base.SourceRootKind.Stdlib) {
        return true;
    }
    root.hir.class_data(db, class_).methods.some((method) -> {
        root.hir_ty.cleanup_method(db, method) != null
    })
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
    let graph = Graph.new(body.locals.length(), types);
    walk(graph, db, body, arity, opt, current, null);
    graph
}

// port: baml_compiler2_mir/src/escape.rs::walk @ d9be6853b
// Add `body`'s constraints to `graph`, whose locals for it start at
// `graph.offset` and whose types are `body`'s. `component` places the
// other bodies of a recursive component in the same graph: each callee's
// node offset and arity.
function walk(
    graph: Graph,
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
    opt: OptLevel,
    current: int?,
    component: map<int, (int, int)>?,
) -> void throws never {
    let builtins = Builtins.new(db);
    let iterators = array_iterators(db, body, arity);
    let walker = Walker {
        db: db,
        opt: opt,
        current: current,
        component: component,
        types: graph.types,
        builtins: builtins,
        array_iterators: iterators,
    };
    graph.cause = ReasonCaptured {};
    for (let index = 0; index < body.locals.length(); index += 1) {
        // A captured local's slot holds its cell, which closures share.
        if (body.locals[index].is_captured) {
            let node = graph.local(index);
            graph.mark_shared(node);
        }
    }
    graph.cause = ReasonHandler {};
    for (let handler in body.handlers()) {
        // The VM writes these: an in-flight error and its context.
        let landing = handler.1;
        let error = graph.local(landing.error_local);
        let context = graph.local(landing.context_local);
        graph.mark_shared(error);
        graph.mark_shared(context);
    }
    for (let block_index = 0; block_index < body.blocks.length(); block_index += 1) {
        let block = body.blocks[block_index];
        for (let statement_index = 0; statement_index < block.statements.length(); statement_index += 1) {
            graph.cause = ReasonAt { block: block_index, statement: statement_index };
            graph.statement(block.statements[statement_index].kind);
        }
        let terminator = block.terminator;
        if (terminator != null) {
            graph.cause = ReasonAt { block: block_index, statement: null };
            walker.terminator(graph, terminator);
        }
    }
    graph.cause = ReasonParameter {};
}

// port: baml_compiler2_mir/src/escape.rs::Reason @ d9be6853b
// Why an object is shared, for the coverage report.
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

// The statement (or, with no statement, the terminator) of a block.
class ReasonAt {
    block: int,
    statement: int?,
}

// port: baml_compiler2_mir/src/escape.rs::Access @ d9be6853b
// One container or field access in a body.
class Access {
    kind: AccessKind,
    // Whether the accessed object is thread-local.
    thread_local: bool,
    // For a shared object, what made it shared.
    shared_because: string?,
    // The parameters the accessed object is thread-local given
    // (`EscapeFacts.object_needs`).
    needs: bigint,
}

// port: baml_compiler2_mir/src/escape.rs::AccessKind @ d9be6853b
enum AccessKind {
    // `xs[i]`, read or written.
    Element,
    // `xs.length()` lowered to a length read.
    Length,
    // `x.field`, read or written.
    Field,
    // A call to a builtin array or map method on a receiver.
    ContainerMethod,
    // A step of `for` over an array.
    Iteration,
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
    let types = Types.new(db, root_id, body);
    let graph = build(db, body, arity, opt, null, types);
    let last = arity.min((body.locals.length() - 1).max(0));
    for (let local = 1; local <= last; local += 1) {
        graph.mark_shared(local);
    }
    let resolved = graph.resolve();
    // The same graph with its parameters left unclassified: union-find
    // roots do not depend on sharing, so its nodes are this graph's nodes.
    let facts = build(db, body, arity, opt, null, types).finish(arity);
    let builtins = Builtins.new(db);
    let iterators = array_iterators(db, body, arity);
    let accesses: Access[] = [];
    let record = (kind: AccessKind, node: int?) -> void {
        let thread_local = node != null && !facts.shared[node];
        let needs = if (node != null) {
            facts.needs[node]
        } else {
            NEVER
        };
        let shared_because: string? = if (thread_local) {
            null
        } else if (node != null) {
            describe(db, root_id, body, opt, resolved.reasons[node])
        } else {
            "not an object the analysis tracks"
        };
        accesses.push(
            Access {
                kind: kind,
                thread_local: thread_local,
                shared_because: shared_because,
                needs: needs,
            },
        );
    };
    let place = (accessed: Place) -> void {
        projections(accessed, (kind, base) -> {
            record(kind, facts.object_node(base));
        });
    };
    for (let block in body.blocks) {
        for (let statement in block.statements) {
            match (statement.kind) {
                let s: StatementKindAssign => {
                    place(s.destination);
                    walk_rvalue_places(s.value, place);
                    match (s.value) {
                        let len: RvalueLen => {
                            record(AccessKind.Length, facts.object_node(len.value))
                        },
                        _ => {},
                    }
                },
                let s: StatementKindDrop => place(s.value),
                let s: StatementKindIntrinsic => {
                    for (let arg in s.args) {
                        walk_operand_places(arg, place);
                    }
                },
                let s: StatementKindVirtualFieldStore => {
                    for (let operand in [s.receiver, s.value]) {
                        walk_operand_places(operand, place);
                    }
                },
                StatementKindFreshCell | StatementKindNop => {},
            }
        }
        let terminator = block.terminator;
        if (terminator == null) {
            continue;
        }
        let (let operands, let destinations) = terminator_places(terminator);
        for (let operand in operands) {
            walk_operand_places(operand, place);
        }
        for (let destination in destinations) {
            place(destination);
        }
        match (terminator) {
            let t: TerminatorCall if builtins.effect(t.callee) != null => {
                let receiver = match (t.args.at(t.ntypeargs)) {
                    let c: OperandCopy => facts.object_node(c.value),
                    let m: OperandMove => facts.object_node(m.value),
                    _ => null,
                };
                record(AccessKind.ContainerMethod, receiver);
            },
            TerminatorVirtualCall => {
                let call = unary_iteration_call(db, terminator);
                if (call != null && call.0 == "next" && iterators[call.1]) {
                    let array = facts.local_node[call.1];
                    record(AccessKind.Iteration, facts.contents[array]);
                }
            },
            _ => {},
        }
    }
    accesses
}

// port: baml_compiler2_mir/src/escape.rs::projections @ d9be6853b
// Each field or element access within `place`, with the place of the
// object it goes through.
function projections(
    place: Place,
    visit: (AccessKind, Place) -> void throws never,
) -> void throws never {
    match (place) {
        let p: PlaceField => {
            visit(AccessKind.Field, p.base);
            projections(p.base, visit);
        },
        let p: PlaceIndex => {
            if (p.kind == IndexKind.Array) {
                visit(AccessKind.Element, p.base);
            }
            projections(p.base, visit);
        },
        PlaceLocal | PlaceCapture | PlaceDeref => {},
    }
}

// port: baml_compiler2_mir/src/escape.rs::terminator_places @ d9be6853b
// The operands a terminator reads and the places it writes.
function terminator_places(terminator: Terminator) -> (Operand[], Place[]) throws never {
    match (terminator) {
        TerminatorGoto | TerminatorReturn | TerminatorUnreachable => ([], []),
        let t: TerminatorBranch => ([t.condition], []),
        let t: TerminatorSwitch => ([t.discriminant], []),
        let t: TerminatorNarrowBind => ([t.source], []),
        let t: TerminatorShortCircuit => ([t.operand], [t.destination]),
        let t: TerminatorCall => ([t.callee].concat(t.args), [t.destination]),
        let t: TerminatorSysOp => ([t.callee].concat(t.args), [t.destination]),
        let t: TerminatorVirtualCall => (t.args.slice(0, t.args.length()), [t.destination]),
        let t: TerminatorSpawn => ([t.plan], [t.future]),
        let t: TerminatorAwait => ([], [t.future, t.destination]),
        let t: TerminatorAwaitAny => ([t.futures], [t.destination]),
        let t: TerminatorThrow => ([t.value], []),
        let t: TerminatorRethrow => ([t.value, t.context], []),
    }
}

// port: baml_compiler2_mir/src/escape.rs::describe @ d9be6853b
function describe(
    db: root.hir.Db,
    root_id: int,
    body: MirFunctionBody,
    opt: OptLevel,
    reason: Reason,
) -> string throws never {
    let at = match (reason) {
        ReasonParameter => {
            return "parameter";
        },
        ReasonCaptured => {
            return "captured by a closure";
        },
        ReasonHandler => {
            return "caught error";
        },
        ReasonConstant => {
            return "constant or global";
        },
        ReasonCell => {
            return "read from a cell";
        },
        let r: ReasonAt => r,
    };
    let block = body.blocks[at.block];
    let statement = at.statement;
    if (statement != null) {
        return match (block.statements[statement].kind) {
            StatementKindIntrinsic { op: IntrinsicOpLog } => "logged",
            StatementKindIntrinsic => "trace hook",
            StatementKindFreshCell => "captured by a closure",
            StatementKindAssign { value: RvalueMakeClosure } => "closure",
            StatementKindAssign { value: RvalueMakeBoundMethod }
                | StatementKindAssign { value: RvalueMakeVirtualBoundMethod } =>
            {
                "bound method"
            },
            StatementKindAssign
                | StatementKindDrop
                | StatementKindVirtualFieldStore
                | StatementKindNop =>
            {
                "runtime value"
            },
        };
    }
    let name = (callee: Operand) -> string {
        let func = static_callee(callee);
        if (func != null) {
            function_display_name(db, func)
        } else {
            "a function value"
        }
    };
    match (block.terminator) {
        let t: TerminatorCall => {
            let loc = static_callee(t.callee);
            if (loc != null && can_summarize(db, root_id, loc) && escape_summary(db, loc, opt) != null) {
                `leaked by ${name(t.callee)}`
            } else {
                `opaque call ${name(t.callee)}`
            }
        },
        let t: TerminatorVirtualCall => `virtual call .${t.method}`,
        let t: TerminatorSysOp => `sys-op ${name(t.callee)}`,
        TerminatorSpawn => "spawn",
        TerminatorAwait | TerminatorAwaitAny => "await",
        TerminatorThrow | TerminatorRethrow => "throw",
        _ => "runtime value",
    }
}

// port: baml_compiler2_mir/src/escape.rs::Summary @ d9be6853b
// A callee's graph as seen from its call sites: the nodes its parameters
// and return value reach, with sharing and contents edges.
class Summary {
    // Per node: whether another thread may reach it, and its contents node.
    nodes: (bool, int?)[],
    // The node of each parameter, in declaration order.
    params: int[],
    // The node of the return value.
    ret: int,
}

// port: baml_compiler2_mir/src/escape.rs::Types @ d9be6853b
// Static types of a body's places, as far as escape analysis needs them.
// Renamed field: Rust's `root` is `root_id`. Rust's `RefCell` cache is a
// plain map.
class Types {
    db: root.hir.Db,
    body: MirFunctionBody,
    // Package owning this body, including lambdas and initializers.
    root_id: int,
    // Per class-typed local: its class's field types, by slot.
    fields: map<int, root.types.Ty[]?>,

    // port: baml_compiler2_mir/src/escape.rs::Types::may_finalize @ d9be6853b
    // `may_finalize` for a class built in this body.
    function may_finalize(self, class_: int) -> bool throws never {
        may_finalize(self.db, self.root_id, class_)
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::new @ d9be6853b
    function new(db: root.hir.Db, root_id: int, body: MirFunctionBody) -> Types throws never {
        Types { db: db, body: body, root_id: root_id, fields: {} }
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::immutable @ d9be6853b
    // Whether every value `place` can hold is immutable: a scalar, string,
    // bigint, enum or type, which holds no reference to anything mutable.
    function immutable(self, place: Place) -> bool throws never {
        match (place) {
            // A captured local's slot holds its cell.
            let l: PlaceLocal => {
                let decl = self.body.locals[l.value];
                !decl.is_captured && immutable(decl.ty)
            },
            let d: PlaceDeref => {
                match (d.value) {
                    let l: PlaceLocal => immutable(self.body.locals[l.value].ty),
                    PlaceCapture => false,
                }
            },
            let p: PlaceField => {
                let ty = self.field_ty(p.base, p.field);
                ty != null && immutable_ty(ty)
            },
            let p: PlaceIndex => {
                match (self.local_ty(p.base)) {
                    let list: root.types.RuntimeTyList => immutable(list.elem),
                    let map_ty: root.types.RuntimeTyMap => immutable(map_ty.value),
                    _ => false,
                }
            },
            PlaceCapture => false,
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::primitive_map_keys @ d9be6853b
    // Whether the map `place` holds has primitive keys, which hash and
    // compare without running user code.
    function primitive_map_keys(self, place: Place) -> bool throws never {
        match (place) {
            let p: PlaceField => {
                match (self.field_ty(p.base, p.field)) {
                    let map_ty: root.types.TyMap => primitive_ty(map_ty.key),
                    _ => false,
                }
            },
            _ => {
                match (self.local_ty(place)) {
                    let map_ty: root.types.RuntimeTyMap => is_primitive(map_ty.key),
                    _ => false,
                }
            },
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::local_ty @ d9be6853b
    function local_ty(self, place: Place) -> root.types.RuntimeTy? throws never {
        match (place) {
            let l: PlaceLocal if !self.body.locals[l.value].is_captured => {
                self.body.locals[l.value].ty
            },
            _ => null,
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Types::field_ty @ d9be6853b
    // The declared type of slot `field` of the class `base` holds, when
    // `base` is a local of a known class.
    function field_ty(self, base: Place, field: int) -> root.types.Ty? throws never {
        let local = match (base) {
            let l: PlaceLocal => l.value,
            _ => {
                return null;
            },
        };
        let class_ty = match (self.local_ty(base)) {
            let c: root.types.RuntimeTyClass => c,
            _ => {
                return null;
            },
        };
        if (!self.fields.has(local)) {
            let class_ref = root.hir_ty.class_ref_of(self.db, class_ty.name);
            self.fields[local]
                = if (class_ref != null) {
                    root.hir_ty.class_fields(self.db, class_ref).map((entry) -> {
                        entry.1
                    })
                } else {
                    null
                };
        }
        let slots = self.fields[local]
            ?? return null;
        slots.at(field)
    }
}

// port: baml_compiler2_mir/src/escape.rs::immutable @ d9be6853b
// Lowering types some temporaries `null` while they hold an object (an
// awaited future, a sys-op result), so a bare `null` proves nothing.
function immutable(ty: root.types.RuntimeTy) -> bool throws never {
    !(ty is root.types.TyNull) && immutable_value(ty)
}

// port: baml_compiler2_mir/src/escape.rs::immutable_value @ d9be6853b
function immutable_value(ty: root.types.RuntimeTy) -> bool throws never {
    match (ty) {
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyLiteral
            | root.types.TyEnum
            | root.types.TyEnumVariant =>
        {
            true
        },
        let u: root.types.RuntimeTyUnion => u.members.every(immutable_value),
        _ => false,
    }
}

// port: baml_compiler2_mir/src/escape.rs::immutable_ty @ d9be6853b
function immutable_ty(ty: root.types.Ty) -> bool throws never {
    match (ty) {
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyLiteral
            | root.types.TyEnum
            | root.types.TyEnumVariant =>
        {
            true
        },
        let u: root.types.TyUnion => u.members.every(immutable_ty),
        _ => false,
    }
}

// port: baml_compiler2_mir/src/escape.rs::primitive_ty @ d9be6853b
function primitive_ty(ty: root.types.Ty) -> bool throws never {
    match (ty) {
        root.types.TyInt | root.types.TyString | root.types.TyBool => true,
        let l: root.types.TyLiteral => {
            match (l.value) {
                root.base.LiteralInt | root.base.LiteralString | root.base.LiteralBool => true,
                _ => false,
            }
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/escape.rs::Walker @ d9be6853b
class Walker {
    db: root.hir.Db,
    opt: OptLevel,
    // The function whose summary is being built, if any: calls within its
    // recursive component are opaque.
    current: int?,
    // The bodies of a recursive component sharing this graph: a call to one
    // joins the callee's nodes directly.
    component: map<int, (int, int)>?,
    types: Types,
    builtins: Builtins,
    array_iterators: bool[],

    // port: baml_compiler2_mir/src/escape.rs::Walker::terminator @ d9be6853b
    function terminator(self, graph: Graph, terminator: Terminator) -> void throws never {
        match (terminator) {
            TerminatorGoto
                | TerminatorBranch
                | TerminatorSwitch
                | TerminatorReturn
                | TerminatorUnreachable =>
            {},
            let t: TerminatorNarrowBind => {
                let value = graph.operand(t.source);
                let destination = graph.local(t.destination);
                graph.flow(destination, value);
            },
            let t: TerminatorShortCircuit => {
                let value = graph.operand(t.operand);
                graph.write(t.destination, value);
            },
            let t: TerminatorCall => {
                // Value arguments in parameter order, or the call is opaque.
                let named_slot = t.argument_layout?.value.some((slot) -> {
                    slot != null
                })
                    ?? false;
                let positional = !t.has_trace && !named_slot;
                let values = t.args.slice(t.ntypeargs, t.args.length());
                if (positional && self.compares_against_immutable(t.callee, values)) {
                    // Reads both operands; the result is a bool.
                    return;
                }
                let effect = self.builtins.effect(t.callee);
                if (effect != null && positional && self.matches_builtin(effect, values)) {
                    let result = graph.apply_builtin(effect, values);
                    graph.write(t.destination, result);
                    return;
                }
                let member = self.component_member(t.callee);
                if (member != null && positional && member.1 == values.length()) {
                    // The callee's parameters are `_1..=_arity`, its return
                    // value `_0`, in its part of this graph.
                    let (let offset, let arity) = member;
                    for (let index = 0; index < arity; index += 1) {
                        let value = graph.operand(values[index]);
                        graph.flow(offset + 1 + index, value);
                    }
                    graph.write(t.destination, offset);
                    return;
                }
                let summary = self.summary(t.callee);
                if (summary != null && positional && summary.params.length() == values.length()) {
                    graph.apply_summary(summary, values, t.destination);
                } else {
                    graph.unknown(t.args, t.destination, t.callee);
                }
            },
            let t: TerminatorVirtualCall => {
                match (self.array_iteration(terminator)) {
                    let it: IterationIter => {
                        // The iterator holds the array.
                        let array = graph.local(it.array);
                        let iterator = graph.local(it.iterator);
                        let contents = graph.contents_of(iterator);
                        graph.flow(contents, array);
                    },
                    let next: IterationNext => {
                        let iterator = graph.local(next.iterator);
                        let item = graph.local(next.item);
                        let array = graph.contents_of(iterator);
                        let element = graph.contents_of(array);
                        graph.flow(item, element);
                    },
                    null => graph.unknown(t.args, t.destination, null),
                }
            },
            let t: TerminatorSysOp => graph.unknown(t.args, t.destination, t.callee),
            let t: TerminatorSpawn => {
                graph.leak(t.plan);
                graph.write_shared(t.future);
            },
            let t: TerminatorAwait => graph.write_shared(t.destination),
            let t: TerminatorAwaitAny => {
                graph.leak(t.futures);
                graph.write_shared(t.destination);
            },
            // A thrown value reaches the VM's in-flight error, and from
            // there any handler or caller.
            let t: TerminatorThrow => graph.leak(t.value),
            let t: TerminatorRethrow => {
                graph.leak(t.value);
                graph.leak(t.context);
            },
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Walker::component_member @ d9be6853b
    // The offset and arity of a call's target within this graph, when it
    // is a body of the component being analyzed together.
    function component_member(self, callee: Operand) -> (int, int)? throws never {
        let func = static_callee(callee)
            ?? return null;
        let component = self.component
            ?? return null;
        component.get(func)
    }

    // port: baml_compiler2_mir/src/escape.rs::Walker::summary @ d9be6853b
    // The summary of a call's target, unless it is opaque or in the same
    // recursive component as the function being summarized.
    function summary(self, callee: Operand) -> Summary? throws never {
        let func = static_callee(callee)
            ?? return null;
        if (!can_summarize(self.db, self.types.root_id, func)) {
            return null;
        }
        // A component member the call could not join is opaque: its summary
        // is the one being built.
        let component = self.component;
        if (component != null && component.has(func)) {
            return null;
        }
        let current = self.current;
        if (current != null) {
            let root_id = self.db.file(self.db.function_locs.get(current).file).root;
            let components = recursive_functions(self.db, root_id, self.opt);
            let current_component = components.get(current);
            if (
                func == current
                    || (current_component != null && components.get(func) == current_component)
            ) {
                return null;
            }
        }
        escape_summary(self.db, func, self.opt)
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
        let func = static_callee(callee);
        func != null
            && func == self.builtins.equals_equals
            && values.length() == 2
            && values.some((value) -> {
                match (value) {
                    OperandConstant { value: ConstantGlobalItem } => false,
                    OperandConstant => true,
                    let c: OperandCopy => self.types.immutable(c.value),
                    let m: OperandMove => self.types.immutable(m.value),
                }
            })
    }

    // port: baml_compiler2_mir/src/escape.rs::Walker::matches_builtin @ d9be6853b
    // Whether a call's value arguments fit `effect`: the declared arity and
    // a receiver place, whose keys, when it compares them, are primitive.
    function matches_builtin(self, effect: Effect, args: Operand[]) -> bool throws never {
        let receiver = match (args.at(0)) {
            let c: OperandCopy => c.value,
            let m: OperandMove => m.value,
            _ => {
                return false;
            },
        };
        // A key hashes and compares through `Hash` and `Equals`, which run
        // user code for anything but a primitive key.
        args.length() == effect.arity
            && (!effect.compares_keys || self.types.primitive_map_keys(receiver))
    }

    // port: baml_compiler2_mir/src/escape.rs::Walker::array_iteration @ d9be6853b
    function array_iteration(self, terminator: Terminator) -> Iteration? throws never {
        let (let method, let receiver, let destination) = unary_iteration_call(self.db, terminator)
            ?? return null;
        if (method == "iter" && self.array_iterators[destination]) {
            IterationIter { array: receiver, iterator: destination }
        } else if (method == "next" && self.array_iterators[receiver]) {
            IterationNext { iterator: receiver, item: destination }
        } else {
            null
        }
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

// port: baml_compiler2_mir/src/escape.rs::array_walks @ d9be6853b
// Iterator locals a backend may compile as an index walk over the array:
// defined once, by `xs.iter()` on an array local, not captured, and
// mentioned nowhere but as the receiver of `next`. Such an iterator is
// never observed, so the walk is the same loop without the object.
function array_walks(db: root.hir.Db, body: MirFunctionBody, arity: int) -> bool[] throws never {
    let walks = array_iterators(db, body, arity);
    for (let local = 0; local < walks.length(); local += 1) {
        walks[local] = walks[local] && local > arity && !body.locals[local].is_captured;
    }
    let mentioned = (local: int) -> void {
        if (local < walks.length()) {
            walks[local] = false;
        }
    };
    let disqualify = (place: Place) -> void {
        let base = place_base_local(place);
        if (base != null) {
            mentioned(base);
        }
        let indices: Place? = place;
        while let current: Place = indices {
            indices
                = match (current) {
                    let p: PlaceField => p.base,
                    let p: PlaceIndex => {
                        mentioned(p.index);
                        p.base
                    },
                    _ => null,
                };
        }
    };
    for (let block in body.blocks) {
        for (let statement in block.statements) {
            match (statement.kind) {
                let s: StatementKindAssign => {
                    disqualify(s.destination);
                    walk_rvalue_places(s.value, disqualify);
                },
                let s: StatementKindDrop => disqualify(s.value),
                let s: StatementKindFreshCell => disqualify(PlaceLocal { value: s.local }),
                let s: StatementKindIntrinsic => {
                    for (let arg in s.args) {
                        walk_operand_places(arg, disqualify);
                    }
                },
                let s: StatementKindVirtualFieldStore => {
                    for (let operand in [s.receiver, s.value]) {
                        walk_operand_places(operand, disqualify);
                    }
                },
                StatementKindNop => {},
            }
        }
        let landing = block.landing;
        if (landing != null) {
            disqualify(PlaceLocal { value: landing.error_local });
            disqualify(PlaceLocal { value: landing.context_local });
        }
        let terminator = block.terminator;
        if (terminator == null) {
            continue;
        }
        // The walk's own `iter` and `next` calls do not observe the
        // iterator.
        let call = unary_iteration_call(db, terminator);
        if (call != null) {
            if (call.0 == "iter") {
                disqualify(PlaceLocal { value: call.1 });
                continue;
            }
            if (call.0 == "next") {
                disqualify(PlaceLocal { value: call.2 });
                continue;
            }
        }
        let (let operands, let destinations) = terminator_places(terminator);
        for (let operand in operands) {
            walk_operand_places(operand, disqualify);
        }
        for (let destination in destinations) {
            disqualify(destination);
        }
    }
    walks
}

// port: baml_compiler2_mir/src/escape.rs::array_iterators @ d9be6853b
// Locals whose only definition is `xs.iter()` on an array: the runtime's
// `ArrayIterator`, whose `next` reads the array and nothing else.
function array_iterators(
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
) -> bool[] throws never {
    let definitions: int[] = baml.Array.filled(body.locals.length(), 0);
    let array_iter: bool[] = baml.Array.filled(body.locals.length(), false);
    let define = (place: Place) -> void {
        match (place) {
            let l: PlaceLocal => {
                definitions[l.value] += 1;
            },
            _ => {},
        }
    };
    for (let block in body.blocks) {
        for (let statement in block.statements) {
            match (statement.kind) {
                let s: StatementKindAssign => define(s.destination),
                let s: StatementKindFreshCell => define(PlaceLocal { value: s.local }),
                StatementKindDrop
                    | StatementKindIntrinsic
                    | StatementKindVirtualFieldStore
                    | StatementKindNop =>
                {},
            }
        }
        let landing = block.landing;
        if (landing != null) {
            define(PlaceLocal { value: landing.error_local });
            define(PlaceLocal { value: landing.context_local });
        }
        let terminator = block.terminator;
        if (terminator == null) {
            continue;
        }
        match (terminator) {
            let t: TerminatorVirtualCall => {
                define(t.destination);
                let call = unary_iteration_call(db, terminator);
                if (
                    call != null
                        && call.0 == "iter"
                        && call.2 > arity
                        && body.locals[call.1].ty is root.types.RuntimeTyList
                ) {
                    array_iter[call.2] = true;
                }
            },
            let t: TerminatorNarrowBind => define(PlaceLocal { value: t.destination }),
            TerminatorCall { destination: let destination }
                | TerminatorSysOp { destination: let destination }
                | TerminatorAwait { destination: let destination }
                | TerminatorAwaitAny { destination: let destination }
                | TerminatorShortCircuit { destination: let destination } =>
            {
                define(destination)
            },
            let t: TerminatorSpawn => define(t.future),
            TerminatorGoto
                | TerminatorBranch
                | TerminatorSwitch
                | TerminatorReturn
                | TerminatorUnreachable
                | TerminatorThrow
                | TerminatorRethrow =>
            {},
        }
    }
    let out: bool[] = [];
    for (let local = 0; local < array_iter.length(); local += 1) {
        out.push(array_iter[local] && definitions[local] == 1);
    }
    out
}

// port: baml_compiler2_mir/src/escape.rs::is_primitive @ d9be6853b
function is_primitive(ty: root.types.RuntimeTy) -> bool throws never {
    match (ty) {
        root.types.TyInt | root.types.TyString | root.types.TyBool => true,
        let l: root.types.TyLiteral => {
            match (l.value) {
                root.base.LiteralInt | root.base.LiteralString | root.base.LiteralBool => true,
                _ => false,
            }
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/escape.rs::Effect @ d9be6853b
// What a builtin does with its arguments (receiver at argument 0).
class Effect {
    // Value arguments, receiver included.
    arity: int,
    // Arguments that become elements or entries of the receiver.
    keeps: int[],
    returns: Returns,
    // It hashes or compares the receiver's keys.
    compares_keys: bool,
    // Passes receiver elements to user code, which may retain them.
    leaks_contents: bool,
}

// port: baml_compiler2_mir/src/escape.rs::Returns @ d9be6853b
type Returns = ReturnsNothing | ReturnsElement | ReturnsFresh;

class ReturnsNothing {
}

// An element or entry of the receiver.
class ReturnsElement {
}

// A new container of the receiver's elements and those of these arguments.
class ReturnsFresh {
    value: int[],
}

// port: baml_compiler2_mir/src/escape.rs::EFFECTS @ d9be6853b
// Effects by native key, with argument 0 the receiver. `keeps` flows the
// listed arguments into its contents; `Element` returns those contents;
// `Fresh` returns a new container holding its contents and the listed
// arguments' contents. `compares_keys` allows user hash/equality calls on
// keys, which must be treated as escaping. Empty clauses only read values.
// An unlisted builtin is opaque, which is sound.
const EFFECTS: (string, Effect)[] = [
    // String.length delegates here: reads the cached character count and
    // returns an int.
    (
        "baml.String.char_count",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsNothing {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Reads Vec length without retaining values.
    (
        "baml.Array.length",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsNothing {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Clones the selected element from the receiver.
    (
        "baml.Array.at",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsElement {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Appends the argument to the receiver Vec.
    (
        "baml.Array.push",
        Effect {
            arity: 2,
            keeps: [1],
            returns: ReturnsNothing {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Removes and returns the last receiver element.
    (
        "baml.Array.pop",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsElement {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Removes and returns the indexed receiver element.
    (
        "baml.Array.remove_at",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsElement {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Copies both input arrays into a fresh Vec.
    (
        "baml.Array.concat",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsFresh { value: [1] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Copies receiver elements into a fresh reversed Vec.
    (
        "baml.Array.reverse",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Copies the selected receiver range into a fresh Vec.
    (
        "baml.Array.slice",
        Effect {
            arity: 3,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Drops receiver elements without retaining them.
    (
        "baml.Array.clear",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsNothing {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Removes and returns the first receiver element.
    (
        "baml.Array.shift",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsElement {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Inserts the argument at the start of the receiver Vec.
    (
        "baml.Array.unshift",
        Effect {
            arity: 2,
            keeps: [1],
            returns: ReturnsNothing {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Inserts the value argument at the given receiver index.
    (
        "baml.Array.insert",
        Effect {
            arity: 3,
            keeps: [1],
            returns: ReturnsNothing {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Reads IndexMap length without retaining values.
    (
        "baml.Map.length",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsNothing {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Hashes the key and reads receiver membership.
    (
        "baml.Map.has",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsNothing {},
            compares_keys: true,
            leaks_contents: false,
        },
    ),
    // Copies receiver keys into a fresh array.
    (
        "baml.Map.keys",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Copies receiver values into a fresh array.
    (
        "baml.Map.values",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Hashes the key and stores key and value in the receiver.
    (
        "baml.Map.set",
        Effect {
            arity: 3,
            keeps: [1, 2],
            returns: ReturnsElement {},
            compares_keys: true,
            leaks_contents: false,
        },
    ),
    // Hashes the key and clones the matching receiver value.
    (
        "baml.Map.get",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsElement {},
            compares_keys: true,
            leaks_contents: false,
        },
    ),
    // Hashes the key and clones the indexed receiver value.
    (
        "baml.Map.index",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsElement {},
            compares_keys: true,
            leaks_contents: false,
        },
    ),
    // Hashes the key and removes its receiver entry.
    (
        "baml.Map.delete",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsElement {},
            compares_keys: true,
            leaks_contents: false,
        },
    ),
    // Hashes the key and stores the default if absent, returning an entry.
    (
        "baml.Map.get_or_insert",
        Effect {
            arity: 3,
            keeps: [1, 2],
            returns: ReturnsElement {},
            compares_keys: true,
            leaks_contents: false,
        },
    ),
    // Drops receiver entries without retaining them.
    (
        "baml.Map.clear",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsNothing {},
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Allocates an array of immutable string pieces.
    (
        "baml.String.split",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Allocates an array of immutable character strings.
    (
        "baml.String.chars",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Allocates an array of immutable line strings.
    (
        "baml.String.lines",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Allocates an array of scalar UTF-8 bytes.
    (
        "baml.String.to_utf8",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // Allocates an array of scalar Unicode code points.
    (
        "baml.String.to_code_points",
        Effect {
            arity: 1,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: false,
        },
    ),
    // ToString overrides receive elements, while join retains only a copied
    // Vec.
    (
        "baml.Array.join",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsNothing {},
            compares_keys: false,
            leaks_contents: true,
        },
    ),
    // Callbacks receive elements; the continuation allocates the result
    // array after they return.
    (
        "baml.Array.map",
        Effect {
            arity: 2,
            keeps: [],
            returns: ReturnsFresh { value: [] },
            compares_keys: false,
            leaks_contents: true,
        },
    ),
];

// port: baml_compiler2_mir/src/escape.rs::Builtins @ d9be6853b
// The builtins whose effect on their arguments is declared. Every other
// callee is opaque. Rust's `RefCell` cache is a plain map.
class Builtins {
    db: root.hir.Db,
    effects: map<int, Effect?>,
    // `baml.ops.equals_equals`, the `==` driver.
    equals_equals: int?,

    // port: baml_compiler2_mir/src/escape.rs::Builtins::new @ d9be6853b
    function new(db: root.hir.Db) -> Builtins throws never {
        Builtins {
            db: db,
            effects: {},
            equals_equals: root.hir_ty.lang_function(db, root.base.LangPackage.Baml, ["ops"], "equals_equals"),
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Builtins::effect @ d9be6853b
    function effect(self, callee: Operand) -> Effect? throws never {
        let func = static_callee(callee)
            ?? return null;
        if (self.effects.has(func)) {
            return self.effects[func];
        }
        let effect: Effect? = match (root.hir.function_body(self.db, func)) {
            let b: root.hir.FunctionBodyBuiltin if b.value == root.ast.BuiltinKind.Vm => {
                let key = native_key_for(self.db, func);
                EFFECTS.find((entry) -> {
                    entry.0 == key
                })?.1
            },
            _ => null,
        };
        self.effects[func] = effect;
        effect
    }
}

// port: baml_compiler2_mir/src/escape.rs::Graph @ d9be6853b
// Union-find over abstract nodes, each with a shared bit and a contents
// node. Renamed field: `shared` is `shared_value` (a method shares the
// name).
class Graph {
    // Static types: values of immutable types need no tracking.
    types: Types,
    parent: int[],
    shared_value: bool[],
    contents: (int?)[],
    // Per node: what made it shared, read only by `coverage`.
    reason: Reason[],
    // The reason recorded for anything made shared next.
    cause: Reason,
    locals: int,
    // Where the locals of the body being walked start: nonzero only for
    // the later bodies of a recursive component.
    offset: int,

    // port: baml_compiler2_mir/src/escape.rs::Graph::new @ d9be6853b
    function new(locals: int, types: Types) -> Graph throws never {
        let parent: int[] = [];
        for (let node = 0; node < locals; node += 1) {
            parent.push(node);
        }
        Graph {
            types: types,
            parent: parent,
            shared_value: baml.Array.filled(locals, false),
            contents: baml.Array.filled(locals, null),
            reason: baml.Array.filled(locals, ReasonParameter {}),
            cause: ReasonParameter {},
            locals: locals,
            offset: 0,
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::local @ d9be6853b
    function local(self, local: int) -> int throws never {
        self.offset + local
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::fresh @ d9be6853b
    function fresh(self) -> int throws never {
        let node = self.parent.length();
        self.parent.push(node);
        self.shared_value.push(false);
        self.contents.push(null);
        self.reason.push(self.cause);
        node
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::shared @ d9be6853b
    // A node for a value that may already be reachable from anywhere.
    function shared(self) -> int throws never {
        let node = self.fresh();
        self.shared_value[node] = true;
        node
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::find @ d9be6853b
    function find(self, node: int) -> int throws never {
        let current = node;
        while (self.parent[current] != current) {
            let grandparent = self.parent[self.parent[current]];
            self.parent[current] = grandparent;
            current = grandparent;
        }
        current
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::mark_shared @ d9be6853b
    function mark_shared(self, node: int) -> void throws never {
        let root_node = self.find(node);
        if (!self.shared_value[root_node]) {
            self.reason[root_node] = self.cause;
        }
        self.shared_value[root_node] = true;
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::shared_because @ d9be6853b
    // `shared`, for a value shared for `reason` rather than the cause.
    function shared_because(self, reason: Reason) -> int throws never {
        let cause = self.cause;
        self.cause = reason;
        let node = self.shared();
        self.cause = cause;
        node
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::contents_of @ d9be6853b
    // The contents node of `node`'s objects, created on first use. A value
    // that is no object has no contents; reading through one is a type
    // error the checker already rejected, so it yields a shared node.
    function contents_of(self, node: int?) -> int throws never {
        if (node == null) {
            return self.shared();
        }
        let root_node = self.find(node);
        let existing = self.contents[root_node];
        if (existing != null) {
            return self.find(existing);
        }
        let contents = self.fresh();
        self.contents[root_node] = contents;
        contents
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::operand @ d9be6853b
    // The node an operand's value belongs to; null when it is no object.
    function operand(self, operand: Operand) -> int? throws never {
        let place = match (operand) {
            let c: OperandCopy => c.value,
            let m: OperandMove => m.value,
            let c: OperandConstant => {
                return match (c.value) {
                    // A global's value is shared by every task.
                    ConstantGlobalItem => self.shared_because(ReasonConstant {}),
                    // Immutable: nothing reached through them can change.
                    ConstantInt
                        | ConstantFloat
                        | ConstantBool
                        | ConstantNull
                        | ConstantOmittedArg
                        | ConstantBigint
                        | ConstantString
                        | ConstantFunction
                        | ConstantGenericFunction
                        | ConstantEnumVariant =>
                    {
                        null
                    },
                };
            },
        };
        if (self.types.immutable(place)) {
            null
        } else {
            self.read(place)
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::read @ d9be6853b
    function read(self, place: Place) -> int throws never {
        match (place) {
            let l: PlaceLocal => self.local(l.value),
            PlaceField { base: let base } | PlaceIndex { base: let base } => {
                let base_node = self.read(base);
                self.contents_of(base_node)
            },
            PlaceCapture | PlaceDeref => self.shared_because(ReasonCell {}),
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::write @ d9be6853b
    function write(self, place: Place, value: int?) -> void throws never {
        if (self.types.immutable(place)) {
            return;
        }
        let into = match (place) {
            let l: PlaceLocal => self.local(l.value),
            PlaceField { base: let base } | PlaceIndex { base: let base } => {
                let base_node = self.read(base);
                self.contents_of(base_node)
            },
            PlaceCapture | PlaceDeref => self.shared_because(ReasonCell {}),
        };
        self.flow(into, value);
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::write_shared @ d9be6853b
    function write_shared(self, place: Place) -> void throws never {
        let shared = self.shared();
        self.write(place, shared);
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::leak @ d9be6853b
    // `operand`'s value may now be reachable from anywhere.
    function leak(self, operand: Operand) -> void throws never {
        let value = self.operand(operand);
        let shared = self.shared();
        self.flow(shared, value);
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::unknown @ d9be6853b
    // A call the analysis cannot see through: its arguments and callee
    // leak, and its result comes from anywhere.
    function unknown(
        self,
        args: Operand[],
        destination: Place,
        callee: Operand?,
    ) -> void throws never {
        for (let arg in args) {
            self.leak(arg);
        }
        if (callee != null) {
            self.leak(callee);
        }
        self.write_shared(destination);
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::statement @ d9be6853b
    function statement(self, kind: StatementKind) -> void throws never {
        match (kind) {
            let s: StatementKindAssign => {
                let value = self.rvalue(s.value);
                self.write(s.destination, value);
            },
            StatementKindDrop | StatementKindNop => {},
            let s: StatementKindFreshCell => {
                let node = self.local(s.local);
                self.mark_shared(node);
            },
            let s: StatementKindIntrinsic => {
                match (s.op) {
                    // Logged data goes to the runtime.
                    IntrinsicOpLog | IntrinsicOpApplyTraceHook => {
                        for (let arg in s.args) {
                            self.leak(arg);
                        }
                    },
                    IntrinsicOpBindType | IntrinsicOpBuiltinTraceHook => {},
                }
            },
            let s: StatementKindVirtualFieldStore => {
                // Field-insensitive: the slot resolved at run time is one of
                // the receiver's fields, all of which are its contents.
                let receiver = self.operand(s.receiver);
                let value = self.operand(s.value);
                let contents = self.contents_of(receiver);
                self.flow(contents, value);
            },
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::rvalue @ d9be6853b
    // The node an rvalue's result belongs to; null when it is no object.
    function rvalue(self, rvalue: Rvalue) -> int? throws never {
        match (rvalue) {
            let r: RvalueUse => self.operand(r.value),
            let r: RvalueArray => {
                let array = self.fresh();
                let contents = self.contents_of(array);
                for (let element in r.elements) {
                    let value = self.operand(element);
                    self.flow(contents, value);
                }
                array
            },
            let r: RvalueMap => {
                let map_node = self.fresh();
                let contents = self.contents_of(map_node);
                for (let entry in r.entries) {
                    let key = self.operand(entry.0);
                    let value = self.operand(entry.1);
                    self.flow(contents, key);
                    self.flow(contents, value);
                }
                map_node
            },
            let r: RvalueAggregate => {
                let object = self.fresh();
                let contents = self.contents_of(object);
                for (let field in r.fields) {
                    let value = self.operand(field);
                    self.flow(contents, value);
                }
                // The collector runs a garbage instance's finalizer in a VM
                // of its own, while the task that built the instance may
                // still hold what its fields hold.
                match (r.kind) {
                    let k: AggregateKindClass if self.types.may_finalize(k.class_) => {
                        let shared = self.shared();
                        self.flow(shared, contents);
                    },
                    _ => {},
                }
                object
            },
            RvalueUint8Array => self.fresh(),
            let r: RvalueVirtualFieldAccess => {
                let receiver = self.operand(r.receiver);
                self.contents_of(receiver)
            },
            // The receiver or wrapped value travels with a callable whose
            // invocation this analysis cannot see.
            let r: RvalueMakeBoundMethod => {
                self.leak(r.receiver);
                self.shared()
            },
            let r: RvalueMakeVirtualBoundMethod => {
                self.leak(r.receiver);
                self.shared()
            },
            let r: RvalueMakeGenericFunctionFromValue => {
                self.leak(r.value);
                self.shared()
            },
            // Captures are cells, already shared.
            RvalueMakeClosure
                | RvalueMakeVirtualFunction
                | RvalueMakeGenericFunction
                | RvalueLoadType
                | RvalueCurrentPackage
                | RvalueTraceHookSettings =>
            {
                self.shared()
            },
            // Scalars, or a fresh immutable string or bigint, which no
            // access site synchronizes on.
            RvalueBinaryOp
                | RvalueUnaryOp
                | RvalueDiscriminant
                | RvalueTypeTag
                | RvalueLen
                | RvalueIsType
                | RvalueIsTypeTag
                | RvalueConcatStrings
                | RvalueSatisfiesBound =>
            {
                null
            },
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::apply_builtin @ d9be6853b
    // Apply a builtin's effect to arguments `Walker.matches_builtin`
    // accepted, returning the node its result belongs to.
    function apply_builtin(self, effect: Effect, args: Operand[]) -> int? throws never {
        // An immutable receiver (a string) holds no objects: no contents.
        let receiver = self.operand(args[0]);
        let contents: int? = if (receiver != null) {
            self.contents_of(receiver)
        } else {
            null
        };
        if (effect.leaks_contents && contents != null) {
            self.mark_shared(contents);
        }
        for (let kept in effect.keeps) {
            if (contents != null) {
                let value = self.operand(args[kept]);
                self.flow(contents, value);
            } else {
                // Kept by something this graph does not name.
                self.leak(args[kept]);
            }
        }
        match (effect.returns) {
            ReturnsNothing => null,
            ReturnsElement => contents,
            let fresh: ReturnsFresh => {
                let copy = self.fresh();
                let copy_contents = self.contents_of(copy);
                self.flow(copy_contents, contents);
                for (let source in fresh.value) {
                    let source_node = self.operand(args[source]);
                    let source_contents = self.contents_of(source_node);
                    self.flow(copy_contents, source_contents);
                }
                copy
            },
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::summary @ d9be6853b
    // The summary of the body whose locals start at `offset`, as a callee
    // with `arity` parameters, before its parameters are classified.
    function summary(self, offset: int, arity: int) -> Summary throws never {
        let resolved = self.resolve();
        let last = arity.min((self.locals - (offset + 1)).max(0));
        let roots: int[] = [];
        for (let local = 0; local <= last; local += 1) {
            roots.push(resolved.roots[offset + local]);
        }
        let compact: map<int, int> = {};
        let order: int[] = [];
        let pending = roots.slice(0, roots.length());
        while let node: int = pending.pop() {
            if (compact.has(node)) {
                continue;
            }
            compact[node] = order.length();
            order.push(node);
            let inner = resolved.contents[node];
            if (inner != null) {
                pending.push(inner);
            }
        }
        Summary {
            nodes: order.map((node) -> {
                let inner = resolved.contents[node];
                (
                    resolved.shared[node],
                    if (inner != null) {
                        compact[inner]
                    } else {
                        null
                    },
                )
            }),
            params: roots.slice(1, roots.length()).map((node) -> {
                compact[node]
            }),
            ret: compact[roots[0]],
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::apply_summary @ d9be6853b
    // A call to a summarized callee: a fresh copy of its graph, joined to
    // the arguments and the destination.
    function apply_summary(
        self,
        summary: Summary,
        args: Operand[],
        destination: Place,
    ) -> void throws never {
        let copies: int[] = summary.nodes.map((node) -> {
            if (node.0) {
                self.shared()
            } else {
                self.fresh()
            }
        });
        for (let node = 0; node < summary.nodes.length(); node += 1) {
            let contents = summary.nodes[node].1;
            if (contents != null) {
                let inner = self.contents_of(copies[node]);
                self.union(inner, copies[contents]);
            }
        }
        let paired = args.length().min(summary.params.length());
        for (let index = 0; index < paired; index += 1) {
            let value = self.operand(args[index]);
            self.flow(copies[summary.params[index]], value);
        }
        self.write(destination, copies[summary.ret]);
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::flow @ d9be6853b
    // `value` may now be held wherever `into` is.
    function flow(self, into: int?, value: int?) -> void throws never {
        if (into != null && value != null) {
            self.union(into, value);
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::union @ d9be6853b
    function union(self, a: int, b: int) -> void throws never {
        let pending: (int, int)[] = [(a, b)];
        while let pair: (int, int) = pending.pop() {
            let x = self.find(pair.0);
            let y = self.find(pair.1);
            if (x == y) {
                continue;
            }
            self.parent[y] = x;
            if (!self.shared_value[x] && self.shared_value[y]) {
                self.reason[x] = self.reason[y];
            }
            self.shared_value[x] = self.shared_value[x] || self.shared_value[y];
            let x_contents = self.contents[x];
            let y_contents = self.contents[y];
            if (x_contents != null && y_contents != null) {
                pending.push((x_contents, y_contents));
            } else if (x_contents == null && y_contents != null) {
                self.contents[x] = y_contents;
            }
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::finish @ d9be6853b
    // Resolve every node to its root and push sharing into contents, with
    // each node's locality conditioned on the `arity` parameters.
    function finish(self, arity: int) -> EscapeFacts throws never {
        let params = arity.min((self.locals - 1).max(0));
        // Beyond the mask, a parameter's argument may already be shared.
        for (let local = MASKED_PARAMS + 1; local <= params; local += 1) {
            self.mark_shared(local);
        }
        let resolved = self.resolve();
        let needs = resolved.param_needs(params.min(MASKED_PARAMS));
        EscapeFacts {
            twin_needs_value: [],
            call_args: [],
            local_node: resolved.roots.slice(0, self.locals),
            shared: needs.map((n) -> {
                n != 0n
            }),
            contents: resolved.contents,
            needs: needs,
        }
    }

    // port: baml_compiler2_mir/src/escape.rs::Graph::resolve @ d9be6853b
    // Every node's root, and per root its contents and whether sharing
    // reaches it, from itself or from any node whose contents it is.
    function resolve(self) -> Resolved throws never {
        let nodes = self.parent.length();
        let roots: int[] = [];
        for (let node = 0; node < nodes; node += 1) {
            roots.push(self.find(node));
        }
        let contents: (int?)[] = baml.Array.filled(nodes, null);
        for (let node = 0; node < nodes; node += 1) {
            let inner = self.contents[node];
            if (inner != null) {
                contents[roots[node]] = roots[inner];
            }
        }
        let shared: bool[] = baml.Array.filled(nodes, false);
        // Rust's `self.reason.clone()`: a copy, since it is written below.
        let reasons = self.reason.slice(0, nodes);
        let pending: int[] = [];
        for (let node = 0; node < nodes; node += 1) {
            if (self.shared_value[node]) {
                pending.push(roots[node]);
            }
        }
        for (let node in pending) {
            shared[node] = true;
        }
        // What an object holds is shared for the reason the object is.
        while let node: int = pending.pop() {
            let inner = contents[node];
            if (inner != null) {
                let was_shared = shared[inner];
                shared[inner] = true;
                if (!was_shared) {
                    reasons[inner] = reasons[node];
                    pending.push(inner);
                }
            }
        }
        Resolved { roots: roots, shared: shared, contents: contents, reasons: reasons }
    }
}

// port: baml_compiler2_mir/src/escape.rs::Resolved @ d9be6853b
// A graph's nodes after union-find, with sharing propagated.
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
    function param_needs(self, params: int) -> bigint[] throws never {
        let needs: bigint[] = self.shared.map((shared) -> {
            if (shared) {
                NEVER
            } else {
                0n
            }
        });
        // `1 << (param - 1)`, kept as the loop advances.
        let bit = 1n;
        for (let param = 1; param <= params; param += 1) {
            let node: int? = self.roots[param];
            while let current: int = node {
                if ((needs[current] & bit) != 0n) {
                    break;
                }
                needs[current] = needs[current] | bit;
                node = self.contents[current];
            }
            bit = bit << 1n;
        }
        needs
    }
}
