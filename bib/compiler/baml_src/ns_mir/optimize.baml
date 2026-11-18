// port: baml_compiler2_mir/src/optimize.rs @ d9be6853b
//
// Post-lowering MIR optimization passes. Runs after the builder and
// performs:
// 1. CFG cleanup, copy propagation, and dead store/local elimination to
//    convergence
// 2. Scalar constant folding and branch simplification at O2, within that
//    loop
// 3. Infallible operand-prefix materialization at O1 and above
// 4. RPO block reordering
//
// `optimize/effects.rs` and `optimize/values.rs` are namespace
// `mir.optimize` (`ns_optimize/`).
//
// Restructured (BAML forces it):
// - Rust rewrites through `&mut Local` / `&mut Place` / `&mut Operand` /
//   `&mut Rvalue` / `&mut Statement` / `&mut Terminator`. Here those
//   functions RETURN the rewritten value (an `int`, a new `Place`, ...),
//   and the caller stores it into the containing field or array: an
//   operand that changes variant cannot be replaced through a parameter,
//   and IR nodes are shared references, so a rewrite in place of a shared
//   node would be applied twice. No function here mutates an IR node;
//   mutated in place are only `MirFunctionBody` fields,
//   `BasicBlock` fields and the block-owned `statements` arrays (rebuilt
//   wholesale where Rust rewrites every statement). A rewriter returns its
//   argument itself where nothing in it can change. Where Rust clones a
//   substitution into each use (`apply_subst_to_operand`), each use gets
//   its own operand; a `Constant` is shared, as it is never rewritten.
// - `block.clone()` (dead blocks, RPO) is `BasicBlock { ...block, id }`: the
//   old `blocks` array is dropped, so sharing its statement arrays is safe.
//   `local_decl.clone()` shares the `LocalDecl`; the old `locals` array is
//   dropped too.
// - `HashSet<BlockId>` / `HashSet<Local>` are `bool[]` or `map<int, bool>`;
//   `Vec<Option<_>>` maps are `(int?)[]`.
// - `verify_mir` runs after every optimization (Rust: `cfg!(debug_assertions)`,
//   the profile its tests run in). Its `name: &dyn Display`, formatted only
//   inside a failing assertion, is a closure `() -> string`. Rust's `{:?}`
//   of a `BlockId` is spelled `BlockId(n)`.
// - The nested `fn`s of `collect_place_bound_locals` are free functions
//   (`scan_place`, ...); `verify_definite_assignment`'s local `State` is a
//   class and its `join` a free function.

// port: baml_compiler2_mir/src/optimize.rs::optimize_function @ d9be6853b
// Run all optimization passes on a MIR function.
function optimize_function(db: root.hir.Db, func: MirFunction, opt: OptLevel) -> void throws never {
    let body = match (func.kind) {
        let kind: MirFunctionKindBytecode => kind.value,
        // nothing to clean up on builtins
        MirFunctionKindBuiltin => {
            return;
        },
    };
    optimize_body(body, func.arity, opt);
    verify_mir(db, body, func.arity, () -> {
        mir_function_id_display_name(db, func.identity)
    });
}

// port: baml_compiler2_mir/src/optimize.rs::optimize_function_body @ d9be6853b
// Run all cleanup phases directly on a `MirFunctionBody`. Used for
// let-binding initializers, which are lowered as bodies without the
// enclosing `MirFunction` wrapper (arity = 0).
function optimize_function_body(
    db: root.hir.Db,
    body: MirFunctionBody,
    opt: OptLevel,
) -> void throws never {
    optimize_body(body, 0, opt);
    verify_mir(db, body, 0, () -> {
        "$init_let._"
    });
}

// port: baml_compiler2_mir/src/optimize.rs::optimize_body @ d9be6853b
function optimize_body(body: MirFunctionBody, arity: int, opt: OptLevel) -> void throws never {
    let size = () -> (int, int, int) {
        let statements = body.blocks.reduce(
            (sum, block) -> {
                sum + block.statements.length()
            },
            0,
        );
        (body.blocks.length(), body.locals.length(), statements)
    };
    while (true) {
        let before = size();
        eliminate_dead_blocks(body);
        merge_passthrough_blocks(body);
        if (opt == OptLevel.Two) {
            root.mir.optimize.fold_constants(body, arity);
            eliminate_dead_blocks(body);
        }
        root.mir.optimize.remove_trivial_drops(body);
        root.mir.optimize.eliminate_dead_stores(body, arity, opt);
        propagate_copies(body, arity);
        eliminate_dead_locals(body, arity);
        merge_passthrough_blocks(body);
        if (before == size()) {
            break;
        }
    }
    if (opt != OptLevel.Zero) {
        root.mir.optimize.materialize_operand_prefixes(body);
    }
    reorder_blocks_rpo(body);
}

// ============================================================================
// Phase 1: Dead block elimination
// ============================================================================

// port: baml_compiler2_mir/src/optimize.rs::eliminate_dead_blocks @ d9be6853b
// Phase 1: Remove unreachable blocks via BFS from entry.
function eliminate_dead_blocks(body: MirFunctionBody) -> void throws never {
    // BFS to find all reachable blocks. A block's handler is reachable from
    // it: a throw or panic anywhere in the block lands there.
    let reachable = baml.Array.filled(body.blocks.length(), false);
    let reached = 1;
    let queue = [body.entry];
    reachable[body.entry] = true;

    while let block_id: int = queue.shift() {
        let block = body.blocks[block_id];
        let successors: int[] = [];
        let term = block.terminator;
        if (term != null) {
            root.base.extend(successors, terminator_successors(term));
        }
        root.base.push_some(successors, block.unwind);
        for (let succ in successors) {
            if (!reachable[succ]) {
                reachable[succ] = true;
                reached += 1;
                queue.push(succ);
            }
        }
    }

    // If all blocks are reachable, nothing to do
    if (reached == body.blocks.length()) {
        return;
    }

    // Build old -> new BlockId mapping (only reachable blocks, preserving
    // order)
    let old_to_new: (int?)[] = baml.Array.filled(body.blocks.length(), null);
    let new_blocks: BasicBlock[] = [];
    for (let block in body.blocks) {
        if (reachable[block.id]) {
            let new_id = new_blocks.length();
            old_to_new[block.id] = new_id;
            new_blocks.push(BasicBlock { ...block, id: new_id });
        }
    }

    // Rewrite all BlockId references in terminators and handler edges
    for (let block in new_blocks) {
        let term = block.terminator;
        if (term != null) {
            block.terminator = rewrite_block_ids_in_terminator(term, old_to_new);
        }
        rewrite_handler_refs(block, old_to_new);
    }

    // Rewrite entry block
    body.entry = old_to_new[body.entry] ?? baml.sys.panic("entry block must be reachable");

    body.blocks = new_blocks;
}

// port: baml_compiler2_mir/src/optimize.rs::rewrite_block_ids_in_terminator @ d9be6853b
// Rewrite all `BlockId` references in a terminator using old->new mapping.
// Restructured: returns the rewritten terminator.
function rewrite_block_ids_in_terminator(
    term: Terminator,
    map: (int?)[],
) -> Terminator throws never {
    let remap = (id: int) -> int {
        map[id] ?? baml.sys.panic("successor block must be reachable")
    };
    let remap_unwind = (unwind: int?) -> int? {
        if (unwind != null) {
            remap(unwind)
        } else {
            null
        }
    };

    match (term) {
        let t: TerminatorGoto => TerminatorGoto { target: remap(t.target) },
        let t: TerminatorBranch => {
            TerminatorBranch {
                ...t,
                then_block: remap(t.then_block),
                else_block: remap(t.else_block),
            }
        },
        let t: TerminatorNarrowBind => {
            TerminatorNarrowBind {
                ...t,
                then_block: remap(t.then_block),
                else_block: remap(t.else_block),
            }
        },
        let t: TerminatorSwitch => {
            let arms = t.arms.map((arm) -> {
                (arm.0, remap(arm.1))
            });
            TerminatorSwitch { ...t, arms: arms, otherwise: remap(t.otherwise) }
        },
        TerminatorReturn | TerminatorUnreachable => term,
        let t: TerminatorSpawn => TerminatorSpawn { ...t, resume: remap(t.resume) },
        let t: TerminatorCall => {
            TerminatorCall { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        let t: TerminatorVirtualCall => {
            TerminatorVirtualCall { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        let t: TerminatorSysOp => {
            TerminatorSysOp { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        let t: TerminatorAwait => {
            TerminatorAwait { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        let t: TerminatorAwaitAny => {
            TerminatorAwaitAny { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        TerminatorThrow | TerminatorRethrow => term,
        let t: TerminatorShortCircuit => {
            TerminatorShortCircuit { ...t, eval_rhs: remap(t.eval_rhs), join: remap(t.join) }
        },
    }
}

// port: baml_compiler2_mir/src/optimize.rs::rewrite_handler_refs @ d9be6853b
// Rewrite a block's handler edges using an old->new mapping. A handler some
// kept block unwinds to, or is handling, is reachable from that block, so it
// is kept too.
function rewrite_handler_refs(block: BasicBlock, map: (int?)[]) -> void throws never {
    let remap = (handler: int?) -> int? {
        if (handler == null) {
            return null;
        }
        map[handler]
            ?? baml.sys.panic(`BlockId(${handler}) is a handler of a kept block but was removed`)
    };
    block.unwind = remap(block.unwind);
    block.handling = remap(block.handling);
}

// ============================================================================
// Phase 1b: Passthrough block merging
// ============================================================================

// port: baml_compiler2_mir/src/optimize.rs::rewrite_block_ids_in_terminator_with_map @ d9be6853b
// Rewrite all `BlockId` references in a terminator using a `HashMap`
// redirect map. Restructured: returns the rewritten terminator.
function rewrite_block_ids_in_terminator_with_map(
    term: Terminator,
    map: map<int, int>,
) -> Terminator throws never {
    let remap = (id: int) -> int {
        map.get(id) ?? id
    };
    let remap_unwind = (unwind: int?) -> int? {
        if (unwind != null) {
            remap(unwind)
        } else {
            null
        }
    };

    match (term) {
        let t: TerminatorGoto => TerminatorGoto { target: remap(t.target) },
        let t: TerminatorBranch => {
            TerminatorBranch {
                ...t,
                then_block: remap(t.then_block),
                else_block: remap(t.else_block),
            }
        },
        let t: TerminatorNarrowBind => {
            TerminatorNarrowBind {
                ...t,
                then_block: remap(t.then_block),
                else_block: remap(t.else_block),
            }
        },
        let t: TerminatorSwitch => {
            let arms = t.arms.map((arm) -> {
                (arm.0, remap(arm.1))
            });
            TerminatorSwitch { ...t, arms: arms, otherwise: remap(t.otherwise) }
        },
        TerminatorReturn | TerminatorUnreachable => term,
        let t: TerminatorSpawn => TerminatorSpawn { ...t, resume: remap(t.resume) },
        let t: TerminatorCall => {
            TerminatorCall { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        let t: TerminatorVirtualCall => {
            TerminatorVirtualCall { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        let t: TerminatorSysOp => {
            TerminatorSysOp { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        let t: TerminatorAwait => {
            TerminatorAwait { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        let t: TerminatorAwaitAny => {
            TerminatorAwaitAny { ...t, target: remap(t.target), unwind: remap_unwind(t.unwind) }
        },
        TerminatorThrow | TerminatorRethrow => term,
        let t: TerminatorShortCircuit => {
            TerminatorShortCircuit { ...t, eval_rhs: remap(t.eval_rhs), join: remap(t.join) }
        },
    }
}

// port: baml_compiler2_mir/src/optimize.rs::merge_passthrough_blocks @ d9be6853b
// Merge passthrough blocks: blocks with no statements and a single Goto
// terminator are eliminated by redirecting all references to them to their
// target.
function merge_passthrough_blocks(body: MirFunctionBody) -> void throws never {
    // Step 1: identify passthrough blocks (empty statements + Goto
    // terminator)
    let redirect: map<int, int> = {};
    for (let block in body.blocks) {
        if (block.statements.length() != 0) {
            continue;
        }
        match (block.terminator) {
            // Neither the entry block nor a handler is redirected: the VM
            // lands in a handler with its error slots, which the target may
            // not share.
            let t: TerminatorGoto => {
                if (block.id != body.entry && block.landing == null) {
                    redirect.set(block.id, t.target);
                }
            },
            _ => {},
        }
    }

    if (redirect.length() == 0) {
        return;
    }

    // Step 2: resolve chains (A->B->C becomes A->C)
    let resolved: map<int, int> = {};
    for (let src in redirect.keys()) {
        let target = redirect[src];
        let visited: map<int, bool> = {};
        visited.set(src, true);
        while let next: int = redirect.get(target) {
            if (visited.has(target)) {
                // cycle detected, stop
                break;
            }
            visited.set(target, true);
            target = next;
        }
        resolved.set(src, target);
    }

    // Step 3: rewrite all terminators
    for (let block in body.blocks) {
        let term = block.terminator;
        if (term != null) {
            block.terminator = rewrite_block_ids_in_terminator_with_map(term, resolved);
        }
    }

    // Handler edges need no rewrite: a handler is never redirected, and a
    // redirected passthrough block is empty, so its own handler protects no
    // instruction.

    // Step 5: entry block redirect (shouldn't happen since we excluded it,
    // but be safe)
    let new_entry = resolved.get(body.entry);
    if (new_entry != null) {
        body.entry = new_entry;
    }

    // Step 6: re-run dead block elimination to compact
    eliminate_dead_blocks(body);
}

// ============================================================================
// Phase 2a: Copy propagation
// ============================================================================

// port: baml_compiler2_mir/src/optimize.rs::collect_place_bound_locals @ d9be6853b
// Collect reads in positions that require a `Place` rather than an
// `Operand`.
//
// This includes locals used as `PlaceLocal` bases of field/index projections
// and locals used as the `index` field of `PlaceIndex`, as well as direct
// place reads such as `Len(local)`. A constant cannot replace these reads.
function collect_place_bound_locals(body: MirFunctionBody) -> map<int, bool> throws never {
    let set: map<int, bool> = {};

    for (let block in body.blocks) {
        for (let stmt in block.statements) {
            match (stmt.kind) {
                let s: StatementKindAssign => {
                    scan_place(s.destination, set);
                    scan_rvalue(s.value, set);
                },
                let s: StatementKindVirtualFieldStore => {
                    scan_operand(s.receiver, set);
                    scan_operand(s.value, set);
                },
                let s: StatementKindIntrinsic => {
                    for (let arg in s.args) {
                        scan_operand(arg, set);
                    }
                },
                let s: StatementKindDrop => scan_place_read(s.value, set),
                // Exhaustive for the same reason the substitution walk is: a
                // projected operand missed here lets copy propagation pick a
                // constant for a local that `apply_subst_to_place_locals` then
                // declines to write into the `Local`-typed position, while the
                // defining assignment is dropped regardless, leaving the
                // projection pointing at a local nothing defines.
                StatementKindFreshCell | StatementKindNop => {},
            }
        }
        match (block.terminator) {
            let t: TerminatorCall => {
                scan_operand(t.callee, set);
                for (let a in t.args) {
                    scan_operand(a, set);
                }

                scan_place(t.destination, set);
            },
            let t: TerminatorVirtualCall => {
                // No callee operand: the method is resolved at runtime from
                // `iface` (a type template, not a value local).
                for (let a in t.args) {
                    scan_operand(a, set);
                }

                scan_place(t.destination, set);
            },
            let t: TerminatorSysOp => {
                scan_operand(t.callee, set);
                for (let a in t.args) {
                    scan_operand(a, set);
                }

                scan_place(t.destination, set);
            },
            let t: TerminatorSpawn => {
                scan_operand(t.plan, set);
                scan_place(t.future, set);
            },
            let t: TerminatorBranch => scan_operand(t.condition, set),
            let t: TerminatorNarrowBind => {
                scan_operand(t.source, set);
                scan_place(PlaceLocal { value: t.destination }, set);
            },
            let t: TerminatorSwitch => scan_operand(t.discriminant, set),
            let t: TerminatorThrow => scan_operand(t.value, set),
            let t: TerminatorRethrow => {
                scan_operand(t.value, set);
                scan_operand(t.context, set);
            },
            let t: TerminatorAwait => {
                // The awaited place can be a `PlaceIndex` (e.g. `await
                // xs[_i]`): its index local is typed `Local` in the bytecode
                // and cannot be rewritten to a constant.
                scan_place_read(t.future, set);
                scan_place(t.destination, set);
            },
            let t: TerminatorAwaitAny => {
                scan_operand(t.futures, set);
                scan_place(t.destination, set);
            },
            let t: TerminatorShortCircuit => {
                scan_operand(t.operand, set);
                scan_place(t.destination, set);
            },
            _ => {},
        }
    }

    set
}

// port: baml_compiler2_mir/src/optimize.rs::collect_place_bound_locals::scan_place @ d9be6853b
function scan_place(p: Place, set: map<int, bool>) -> void throws never {
    match (p) {
        PlaceLocal => {},
        PlaceCapture => {},
        // The local behind a deref can't be replaced with a constant.
        let d: PlaceDeref => {
            let local = cell_id_local(d.value);
            if (local != null) {
                set.set(local, true);
            }
        },
        let f: PlaceField => {
            // The base local of a field projection can't be replaced with a
            // constant.
            match (f.base) {
                let l: PlaceLocal => {
                    set.set(l.value, true);
                },
                _ => {},
            }
            scan_place(f.base, set);
        },
        let i: PlaceIndex => {
            set.set(i.index, true);
            match (i.base) {
                let l: PlaceLocal => {
                    set.set(l.value, true);
                },
                _ => {},
            }
            scan_place(i.base, set);
        },
    }
}

// port: baml_compiler2_mir/src/optimize.rs::collect_place_bound_locals::scan_place_read @ d9be6853b
function scan_place_read(p: Place, set: map<int, bool>) -> void throws never {
    match (p) {
        let l: PlaceLocal => {
            set.set(l.value, true);
        },
        _ => {},
    }
    scan_place(p, set);
}

// port: baml_compiler2_mir/src/optimize.rs::collect_place_bound_locals::scan_operand @ d9be6853b
function scan_operand(op: Operand, set: map<int, bool>) -> void throws never {
    match (op) {
        let o: OperandCopy => scan_place(o.value, set),
        let o: OperandMove => scan_place(o.value, set),
        OperandConstant => {},
    }
}

// port: baml_compiler2_mir/src/optimize.rs::collect_place_bound_locals::scan_rvalue @ d9be6853b
function scan_rvalue(rv: Rvalue, set: map<int, bool>) -> void throws never {
    match (rv) {
        let r: RvalueUse => scan_operand(r.value, set),
        let r: RvalueBinaryOp => {
            scan_operand(r.left, set);
            scan_operand(r.right, set);
        },
        let r: RvalueUnaryOp => scan_operand(r.operand, set),
        RvalueUint8Array => {},
        let r: RvalueArray => {
            for (let e in r.elements) {
                scan_operand(e, set);
            }
        },
        let r: RvalueConcatStrings => {
            for (let e in r.value) {
                scan_operand(e, set);
            }
        },
        let r: RvalueMap => {
            for (let entry in r.entries) {
                scan_operand(entry.0, set);
                scan_operand(entry.1, set);
            }
        },
        let r: RvalueAggregate => {
            for (let f in r.fields) {
                scan_operand(f, set);
            }
        },
        let r: RvalueDiscriminant => scan_place_read(r.value, set),
        let r: RvalueTypeTag => scan_place_read(r.value, set),
        let r: RvalueLen => scan_place_read(r.value, set),
        let r: RvalueIsType => scan_operand(r.operand, set),
        let r: RvalueIsTypeTag => scan_operand(r.operand, set),
        let r: RvalueSatisfiesBound => scan_operand(r.ty, set),
        let r: RvalueMakeClosure => {
            for (let cap in r.captures) {
                scan_operand(cap, set);
            }
        },
        let r: RvalueMakeVirtualFunction => {
            for (let arg in r.type_args) {
                scan_operand(arg, set);
            }
        },
        let r: RvalueMakeBoundMethod => scan_operand(r.receiver, set),
        let r: RvalueMakeVirtualBoundMethod => scan_operand(r.receiver, set),
        let r: RvalueVirtualFieldAccess => scan_operand(r.receiver, set),
        let r: RvalueMakeGenericFunctionFromValue => scan_operand(r.value, set),
        // LoadType takes no local operands.
        RvalueLoadType | RvalueTraceHookSettings | RvalueCurrentPackage | RvalueMakeGenericFunction => {},
    }
}

// port: baml_compiler2_mir/src/optimize.rs::count_local_defs @ d9be6853b
// Count definition sites for each local across all blocks: assignments,
// terminator destinations, and the runtime's write of a handler's error and
// context locals when it lands there.
//
// A local is "single-definition" if it has exactly one of these. Locals
// defined in multiple branches (e.g., a temp that is assigned in both arms
// of an if-else) have a count > 1 and must not be constant-propagated;
// neither may a catch binding the handler body reassigns.
function count_local_defs(body: MirFunctionBody) -> int[] throws never {
    let defs = baml.Array.filled(body.locals.length(), 0);
    for (let handler in body.handlers()) {
        defs[handler.1.error_local] += 1;
        defs[handler.1.context_local] += 1;
    }

    for (let block in body.blocks) {
        for (let stmt in block.statements) {
            match (stmt.kind) {
                let s: StatementKindAssign => {
                    // Capture-rooted places have no local definition to
                    // count.
                    let local = place_base_local(s.destination);
                    if (local != null) {
                        defs[local] += 1;
                    }
                },
                _ => {},
            }
        }
        // Terminator destinations also count as definitions.
        let dest = match (block.terminator) {
            let t: TerminatorNarrowBind => t.destination,
            TerminatorCall { destination: let destination }
                | TerminatorVirtualCall { destination: let destination }
                | TerminatorSysOp { destination: let destination }
                | TerminatorAwait { destination: let destination }
                | TerminatorAwaitAny { destination: let destination }
                | TerminatorShortCircuit { destination: let destination } =>
            {
                place_base_local(destination)
            },
            let t: TerminatorSpawn => place_base_local(t.future),
            _ => null,
        };
        if (dest != null) {
            defs[dest] += 1;
        }
    }

    defs
}

// port: baml_compiler2_mir/src/optimize.rs::count_local_uses @ d9be6853b
function count_local_uses(body: MirFunctionBody) -> int[] throws never {
    let uses = baml.Array.filled(body.locals.length(), 0);

    for (let block in body.blocks) {
        for (let stmt in block.statements) {
            count_in_statement(stmt, uses);
        }
        let term = block.terminator;
        if (term != null) {
            count_in_terminator(term, uses);
        }
    }

    // Count uses in handler landings' error locals (VM writes into these
    // slots).
    for (let pair in body.unwind_error_locals()) {
        uses[pair.1] += 1;
    }

    // The VM also writes the caught error's `baml.errors.Context` into the
    // context slot, and the cause-chain pre-walk reads it from an
    // *enclosing* handler: a use the static analysis can't see. Keep it
    // alive even when no binding or rethrow reads it.
    for (let handler in body.handlers()) {
        uses[handler.1.context_local] += 1;
    }

    uses
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_place @ d9be6853b
function count_in_place(p: Place, uses: int[]) -> void throws never {
    let cur = p;
    while (true) {
        match (cur) {
            let l: PlaceLocal => {
                uses[l.value] += 1;
                break;
            },
            PlaceCapture => {
                // Captures have no local base: nothing to count.
                break;
            },
            let d: PlaceDeref => {
                let local = cell_id_local(d.value);
                if (local != null) {
                    uses[local] += 1;
                }
                break;
            },
            let f: PlaceField => {
                cur = f.base;
            },
            let i: PlaceIndex => {
                uses[i.index] += 1;
                cur = i.base;
            },
        }
    }
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_operand @ d9be6853b
function count_in_operand(op: Operand, uses: int[]) -> void throws never {
    match (op) {
        let o: OperandCopy => count_in_place(o.value, uses),
        let o: OperandMove => count_in_place(o.value, uses),
        OperandConstant => {},
    }
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_rvalue @ d9be6853b
function count_in_rvalue(rv: Rvalue, uses: int[]) -> void throws never {
    match (rv) {
        let r: RvalueUse => count_in_operand(r.value, uses),
        let r: RvalueBinaryOp => {
            count_in_operand(r.left, uses);
            count_in_operand(r.right, uses);
        },
        let r: RvalueUnaryOp => count_in_operand(r.operand, uses),
        RvalueUint8Array => {},
        let r: RvalueArray => {
            for (let e in r.elements) {
                count_in_operand(e, uses);
            }
        },
        let r: RvalueConcatStrings => {
            for (let e in r.value) {
                count_in_operand(e, uses);
            }
        },
        let r: RvalueMap => {
            for (let entry in r.entries) {
                count_in_operand(entry.0, uses);
                count_in_operand(entry.1, uses);
            }
        },
        let r: RvalueAggregate => {
            for (let f in r.fields) {
                count_in_operand(f, uses);
            }
        },
        let r: RvalueDiscriminant => count_in_place(r.value, uses),
        let r: RvalueTypeTag => count_in_place(r.value, uses),
        let r: RvalueLen => count_in_place(r.value, uses),
        let r: RvalueIsType => count_in_operand(r.operand, uses),
        let r: RvalueIsTypeTag => count_in_operand(r.operand, uses),
        let r: RvalueSatisfiesBound => count_in_operand(r.ty, uses),
        let r: RvalueMakeClosure => {
            for (let cap in r.captures) {
                count_in_operand(cap, uses);
            }
        },
        let r: RvalueMakeVirtualFunction => {
            for (let arg in r.type_args) {
                count_in_operand(arg, uses);
            }
        },
        let r: RvalueMakeBoundMethod => count_in_operand(r.receiver, uses),
        let r: RvalueMakeVirtualBoundMethod => count_in_operand(r.receiver, uses),
        let r: RvalueVirtualFieldAccess => count_in_operand(r.receiver, uses),
        let r: RvalueMakeGenericFunctionFromValue => count_in_operand(r.value, uses),
        // No local operands.
        RvalueLoadType | RvalueTraceHookSettings | RvalueCurrentPackage | RvalueMakeGenericFunction => {},
    }
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_statement @ d9be6853b
function count_in_statement(stmt: Statement, uses: int[]) -> void throws never {
    match (stmt.kind) {
        let s: StatementKindAssign => {
            // Count the destination place (for field/index projections) but
            // NOT for plain Local: that's a def, not a use. `PlaceCapture` is
            // a store through a cell: the capture index is not a local, so
            // no local use to count here.
            match (s.destination) {
                PlaceLocal | PlaceCapture => {},
                _ => count_in_place(s.destination, uses),
            }
            count_in_rvalue(s.value, uses);
        },
        let s: StatementKindVirtualFieldStore => {
            count_in_operand(s.receiver, uses);
            count_in_operand(s.value, uses);
        },
        let s: StatementKindDrop => count_in_place(s.value, uses),
        let s: StatementKindFreshCell => {
            uses[s.local] += 1;
        },
        StatementKindNop => {},
        let s: StatementKindIntrinsic => {
            for (let arg in s.args) {
                count_in_operand(arg, uses);
            }
        },
    }
}

// port: baml_compiler2_mir/src/optimize.rs::count_in_terminator @ d9be6853b
function count_in_terminator(term: Terminator, uses: int[]) -> void throws never {
    // For terminator destination places (Call::destination,
    // Await::destination, SysOp::destination): these are writes, so don't
    // count plain Local destinations. But if the destination is a projection
    // (Field/Index), the base local IS being read (partial update), so count
    // it.
    let count_dest_place = (p: Place) -> void {
        match (p) {
            PlaceLocal | PlaceCapture => {},
            _ => count_in_place(p, uses),
        }
    };

    match (term) {
        let t: TerminatorBranch => count_in_operand(t.condition, uses),
        let t: TerminatorNarrowBind => count_in_operand(t.source, uses),
        let t: TerminatorSwitch => count_in_operand(t.discriminant, uses),
        let t: TerminatorCall => {
            count_in_operand(t.callee, uses);
            for (let arg in t.args) {
                count_in_operand(arg, uses);
            }

            count_dest_place(t.destination);
        },
        let t: TerminatorVirtualCall => {
            // No callee operand: the method is resolved at runtime from
            // `iface`.
            for (let arg in t.args) {
                count_in_operand(arg, uses);
            }

            count_dest_place(t.destination);
        },
        let t: TerminatorSysOp => {
            count_in_operand(t.callee, uses);
            for (let arg in t.args) {
                count_in_operand(arg, uses);
            }

            count_dest_place(t.destination);
        },
        let t: TerminatorSpawn => {
            count_in_operand(t.plan, uses);
            count_dest_place(t.future);
        },
        let t: TerminatorAwait => {
            // future is a READ: the future handle being consumed
            count_in_place(t.future, uses);
            // destination is a write
            count_dest_place(t.destination);
        },
        let t: TerminatorAwaitAny => {
            // futures is a READ: the array of handles being consumed
            count_in_operand(t.futures, uses);
            // destination is a write (the winning index)
            count_dest_place(t.destination);
        },
        let t: TerminatorThrow => count_in_operand(t.value, uses),
        let t: TerminatorRethrow => {
            count_in_operand(t.value, uses);
            count_in_operand(t.context, uses);
        },
        let t: TerminatorShortCircuit => {
            count_in_operand(t.operand, uses);
            count_dest_place(t.destination);
        },
        TerminatorGoto | TerminatorReturn | TerminatorUnreachable => {},
    }
}

// port: baml_compiler2_mir/src/optimize.rs::propagate_copies @ d9be6853b
// Phase 2a: Propagate trivial copies and single-use constants.
function propagate_copies(body: MirFunctionBody, arity: int) -> void throws never {
    propagate_block_param_copies(body, arity);
    // Build substitution map: Local -> replacement Operand
    let uses = count_local_uses(body);
    let defs = count_local_defs(body);
    let place_bound = collect_place_bound_locals(body);
    let subst: map<int, Operand> = {};

    // Scan for copy-of-param: `_X = copy _Y` where Y is a param (1..=arity)
    // and single-use constants: `_X = const V` where X is used exactly once.
    //
    // SAFETY: Only propagate unnamed locals (compiler temporaries). Named
    // locals (user variables from `let`) can be reassigned, making
    // propagation unsound.
    //
    // We additionally require defs[dest] == 1 to guard against phi-like
    // temps that are assigned in multiple branches (e.g., the result temp of
    // an if-else used directly as an arithmetic operand). Such temps have a
    // single use-site but two definition-sites; propagating the last-seen
    // constant would silently use the wrong branch value.
    for (let block in body.blocks) {
        for (let stmt in block.statements) {
            match (stmt.kind) {
                StatementKindAssign {
                    destination: PlaceLocal { value: let dest },
                    value: RvalueUse { value: let operand },
                } =>
                {
                    // Skip named locals: they may be reassigned
                    if (body.locals[dest].name != null) {
                        continue;
                    }

                    // Skip locals with multiple definition sites (phi-like).
                    if (defs[dest] != 1) {
                        continue;
                    }

                    match (operand) {
                        // Copy of param: substitute. Skip locals that appear
                        // as a `PlaceIndex` index, since removing the copy
                        // would leave the destination place referencing a
                        // dead local.
                        OperandCopy { value: PlaceLocal { value: let src } }
                            if src >= 1 && src <= arity && defs[src] == 0 && !place_bound.has(dest) => {
                            subst.set(dest, operand_copy_local(src));
                        },
                        // Only erase the definition when every read can
                        // accept the constant substitution, including direct
                        // place reads.
                        let c: OperandConstant if uses[dest] == 1 && !place_bound.has(dest) => {
                            subst.set(dest, OperandConstant { value: c.value });
                        },
                        _ => {},
                    }
                },
                _ => {},
            }
        }
    }

    if (subst.length() == 0) {
        return;
    }

    // Resolve transitive chains: if _3 -> copy _1 and _4 -> copy _3, follow
    // the chain so _4 -> copy _1 directly.
    for (let key in subst.keys()) {
        let resolved = subst[key];
        while (true) {
            match (resolved) {
                OperandCopy { value: PlaceLocal { value: let src } } => {
                    let next = subst.get(src);
                    if (next != null) {
                        resolved = next;
                        continue;
                    }
                },
                _ => {},
            }
            break;
        }
        subst.set(key, resolved);
    }

    // Apply substitutions to all operands across all blocks
    for (let block in body.blocks) {
        block.statements
            = block.statements.map((stmt) -> {
                apply_subst_to_statement(stmt, subst)
            });
        let term = block.terminator;
        if (term != null) {
            block.terminator = apply_subst_to_terminator(term, subst);
        }
    }

    // Remove the dead assignment statements (where dest is in subst)
    for (let block in body.blocks) {
        block.statements
            = block.statements.filter((stmt) -> {
                match (stmt.kind) {
                    StatementKindAssign { destination: PlaceLocal { value: let dest } } => {
                        !subst.has(dest)
                    },
                    _ => true,
                }
            });
    }
}

// port: baml_compiler2_mir/src/optimize.rs::propagate_block_param_copies @ d9be6853b
// Extend parameter-copy propagation to reassigned parameters within a block,
// up to the next write to either slot. Other values are left for
// stackification: substituting their temporaries can destroy profitable
// single-use carry chains. Restructured: each block's statements are rebuilt
// into a fresh array.
function propagate_block_param_copies(body: MirFunctionBody, arity: int) -> void throws never {
    let defs = count_local_defs(body);
    for (let block in body.blocks) {
        let copies: map<int, Operand> = {};
        let statements: Statement[] = [];
        for (let original in block.statements) {
            let statement = apply_subst_to_statement(original, copies);
            statements.push(statement);
            let destination = match (statement.kind) {
                StatementKindAssign { destination: PlaceLocal { value: let local } } => local,
                let s: StatementKindFreshCell => s.local,
                _ => {
                    continue;
                },
            };
            for (let local in copies.keys()) {
                let reads_destination = match (copies[local]) {
                    OperandCopy { value: PlaceLocal { value: let source } } => source == destination,
                    _ => false,
                };
                if (local == destination || reads_destination) {
                    copies.delete(local);
                }
            }
            match (statement.kind) {
                StatementKindAssign {
                    value: RvalueUse { value: OperandCopy { value: PlaceLocal { value: let source } } },
                }
                    | StatementKindAssign {
                    value: RvalueUse { value: OperandMove { value: PlaceLocal { value: let source } } },
                }
                    if source != destination
                        && source >= 1
                        && source <= arity
                        && defs[source] > 0
                        && body.locals[destination].name == null =>
                {
                    copies.set(destination, operand_copy_local(source));
                },
                _ => {},
            }
        }
        block.statements = statements;
        let terminator = block.terminator;
        if (terminator != null) {
            block.terminator = apply_subst_to_terminator(terminator, copies);
        }
    }
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_operand @ d9be6853b
// Restructured: returns the substituted operand.
function apply_subst_to_operand(op: Operand, subst: map<int, Operand>) -> Operand throws never {
    match (op) {
        // Plain local: replace the entire operand if in subst
        OperandCopy { value: PlaceLocal { value: let l } }
            | OperandMove { value: PlaceLocal { value: let l } } =>
        {
            let replacement = subst.get(l)
                ?? return op;
            // Rust's `.cloned()`: each use gets its own operand. A
            // substitution is a plain-local read or a constant (which is
            // never rewritten in place, so the copy shares it).
            match (replacement) {
                OperandCopy { value: PlaceLocal { value: let source } } => {
                    operand_copy_local(source)
                },
                OperandMove { value: PlaceLocal { value: let source } } => {
                    OperandMove { value: PlaceLocal { value: source } }
                },
                let c: OperandConstant => OperandConstant { value: c.value },
                // Not built by any pass: a projection is substituted only
                // through `apply_subst_to_place_locals`.
                let o: OperandCopy => OperandCopy { value: o.value },
                let o: OperandMove => OperandMove { value: o.value },
            }
        },
        // Projection (Field/Index): substitute locals within the place, e.g.
        // `copy _5.0` where `_5 -> copy _1` becomes `copy _1.0`.
        let o: OperandCopy => OperandCopy { value: apply_subst_to_place_locals(o.value, subst) },
        let o: OperandMove => OperandMove { value: apply_subst_to_place_locals(o.value, subst) },
        OperandConstant => op,
    }
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_place_locals @ d9be6853b
// Substitute all Local references within a place using the subst map. Only
// substitutes when the substitution maps to a plain-local operand (i.e.,
// `copy _Y`), since projecting through a constant is not meaningful.
// Restructured: returns the substituted place.
function apply_subst_to_place_locals(p: Place, subst: map<int, Operand>) -> Place throws never {
    let local_of = (local: int) -> int {
        match (subst.get(local)) {
            OperandCopy { value: PlaceLocal { value: let new_l } }
                | OperandMove { value: PlaceLocal { value: let new_l } } =>
            {
                new_l
            },
            _ => local,
        }
    };
    match (p) {
        // Substitute bare local if it maps to another local
        let l: PlaceLocal => PlaceLocal { value: local_of(l.value) },
        // Captures are indexed into the closure's capture array: no local to
        // substitute.
        PlaceCapture => p,
        // A cell's local is a captured local's pointer, never substituted:
        // copy propagation only ever maps uncaptured temps.
        PlaceDeref => p,
        let f: PlaceField => {
            PlaceField { base: apply_subst_to_place_locals(f.base, subst), field: f.field }
        },
        // Substitute the index local if it maps to a plain local
        let i: PlaceIndex => {
            let index = local_of(i.index);
            PlaceIndex {
                base: apply_subst_to_place_locals(i.base, subst),
                index: index,
                kind: i.kind,
            }
        },
    }
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_rvalue @ d9be6853b
// Restructured: returns the substituted rvalue.
function apply_subst_to_rvalue(rv: Rvalue, subst: map<int, Operand>) -> Rvalue throws never {
    let operand = (op: Operand) -> Operand {
        apply_subst_to_operand(op, subst)
    };
    match (rv) {
        let r: RvalueUse => RvalueUse { value: operand(r.value) },
        let r: RvalueBinaryOp => {
            let left = operand(r.left);
            RvalueBinaryOp { op: r.op, left: left, right: operand(r.right) }
        },
        let r: RvalueUnaryOp => RvalueUnaryOp { op: r.op, operand: operand(r.operand) },
        RvalueUint8Array => rv,
        let r: RvalueArray => {
            RvalueArray { element_ty: r.element_ty, elements: r.elements.map(operand) }
        },
        let r: RvalueConcatStrings => RvalueConcatStrings { value: r.value.map(operand) },
        let r: RvalueMap => {
            let entries = r.entries.map((entry) -> {
                let key = operand(entry.0);
                (key, operand(entry.1))
            });
            RvalueMap { ...r, entries: entries }
        },
        let r: RvalueAggregate => RvalueAggregate { kind: r.kind, fields: r.fields.map(operand) },
        let r: RvalueDiscriminant => {
            RvalueDiscriminant { value: apply_subst_to_place_locals(r.value, subst) }
        },
        let r: RvalueTypeTag => RvalueTypeTag { value: apply_subst_to_place_locals(r.value, subst) },
        let r: RvalueLen => RvalueLen { value: apply_subst_to_place_locals(r.value, subst) },
        let r: RvalueIsType => RvalueIsType { ...r, operand: operand(r.operand) },
        let r: RvalueIsTypeTag => RvalueIsTypeTag { ...r, operand: operand(r.operand) },
        let r: RvalueSatisfiesBound => RvalueSatisfiesBound { ...r, ty: operand(r.ty) },
        let r: RvalueMakeClosure => RvalueMakeClosure { ...r, captures: r.captures.map(operand) },
        let r: RvalueMakeVirtualFunction => {
            RvalueMakeVirtualFunction { ...r, type_args: r.type_args.map(operand) }
        },
        let r: RvalueMakeBoundMethod => {
            RvalueMakeBoundMethod { ...r, receiver: operand(r.receiver) }
        },
        let r: RvalueMakeVirtualBoundMethod => {
            RvalueMakeVirtualBoundMethod { ...r, receiver: operand(r.receiver) }
        },
        let r: RvalueVirtualFieldAccess => {
            RvalueVirtualFieldAccess { ...r, receiver: operand(r.receiver) }
        },
        let r: RvalueMakeGenericFunctionFromValue => {
            RvalueMakeGenericFunctionFromValue { ...r, value: operand(r.value) }
        },
        // No local operands: nothing to substitute.
        RvalueLoadType | RvalueTraceHookSettings | RvalueCurrentPackage | RvalueMakeGenericFunction => {
            rv
        },
    }
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_statement @ d9be6853b
// Restructured: returns the substituted statement.
function apply_subst_to_statement(
    stmt: Statement,
    subst: map<int, Operand>,
) -> Statement throws never {
    let kind: StatementKind = match (stmt.kind) {
        let s: StatementKindAssign => {
            StatementKindAssign {
                destination: s.destination,
                value: apply_subst_to_rvalue(s.value, subst),
            }
        },
        let s: StatementKindIntrinsic => {
            StatementKindIntrinsic {
                op: s.op,
                args: s.args.map((arg) -> {
                    apply_subst_to_operand(arg, subst)
                }),
            }
        },
        let s: StatementKindVirtualFieldStore => {
            let receiver = apply_subst_to_operand(s.receiver, subst);
            StatementKindVirtualFieldStore {
                ...s,
                receiver: receiver,
                value: apply_subst_to_operand(s.value, subst),
            }
        },
        // Deliberately exhaustive over operand-carrying kinds: a statement
        // whose operands are missed here keeps referring to a local that
        // copy propagation has already retired, and the emitter then loads
        // a slot nothing ever stored to.
        StatementKindDrop | StatementKindFreshCell | StatementKindNop => {
            return stmt;
        },
    };
    Statement { kind: kind, span: stmt.span }
}

// port: baml_compiler2_mir/src/optimize.rs::apply_subst_to_terminator @ d9be6853b
// Restructured: returns the substituted terminator.
function apply_subst_to_terminator(
    term: Terminator,
    subst: map<int, Operand>,
) -> Terminator throws never {
    let operand = (op: Operand) -> Operand {
        apply_subst_to_operand(op, subst)
    };
    match (term) {
        let t: TerminatorBranch => TerminatorBranch { ...t, condition: operand(t.condition) },
        let t: TerminatorNarrowBind => TerminatorNarrowBind { ...t, source: operand(t.source) },
        let t: TerminatorSwitch => TerminatorSwitch { ...t, discriminant: operand(t.discriminant) },
        let t: TerminatorCall => {
            let callee = operand(t.callee);
            TerminatorCall { ...t, callee: callee, args: t.args.map(operand) }
        },
        let t: TerminatorSysOp => {
            let callee = operand(t.callee);
            TerminatorSysOp { ...t, callee: callee, args: t.args.map(operand) }
        },
        // No callee operand: only the value args are substituted.
        let t: TerminatorVirtualCall => TerminatorVirtualCall { ...t, args: t.args.map(operand) },
        let t: TerminatorSpawn => TerminatorSpawn { ...t, plan: operand(t.plan) },
        let t: TerminatorThrow => TerminatorThrow { value: operand(t.value) },
        let t: TerminatorRethrow => {
            let value = operand(t.value);
            TerminatorRethrow { value: value, context: operand(t.context) }
        },
        let t: TerminatorShortCircuit => {
            TerminatorShortCircuit { ...t, operand: operand(t.operand) }
        },
        // `future` is the awaited operand (a `PlaceLocal`); it must be
        // substituted like any other read so a propagated copy-of-param
        // (`_tmp = copy param; await _tmp`) doesn't leave the await pointing
        // at a local whose defining copy was just dead-eliminated.
        // `destination` is a write target and is intentionally left
        // untouched.
        let t: TerminatorAwait => {
            TerminatorAwait { ...t, future: apply_subst_to_place_locals(t.future, subst) }
        },
        // `futures` is the awaited array operand (a read); substitute it like
        // any other read so a propagated copy isn't left dangling after
        // dead-code elimination. `destination` (the index write) is left
        // untouched.
        let t: TerminatorAwaitAny => TerminatorAwaitAny { ...t, futures: operand(t.futures) },
        TerminatorGoto | TerminatorReturn | TerminatorUnreachable => term,
    }
}

// ============================================================================
// Phase 2b: Dead local elimination with renumbering
// ============================================================================

// port: baml_compiler2_mir/src/optimize.rs::eliminate_dead_locals @ d9be6853b
// Phase 2b: Remove dead locals and renumber densely. Restructured: Rust's
// `mem::take` of each block's statements builds a fresh array here.
function eliminate_dead_locals(body: MirFunctionBody, arity: int) -> void throws never {
    let effects = root.mir.optimize.Analysis.new(body);
    let uses = count_local_uses(body);

    for (let block in body.blocks) {
        match (block.terminator) {
            let t: TerminatorShortCircuit => {
                match (t.destination) {
                    let local: PlaceLocal
                        if local.value > arity
                        && uses[local.value] == 0
                        && t.kind != ShortCircuitKind.Coalesce => {
                        // Discard the result, not the conditional execution
                        // of the RHS.
                        let and = t.kind == ShortCircuitKind.And;
                        block.terminator
                            = TerminatorBranch {
                                condition: t.operand,
                                then_block: if (and) {
                                    t.eval_rhs
                                } else {
                                    t.join
                                },
                                else_block: if (and) {
                                    t.join
                                } else {
                                    t.eval_rhs
                                },
                            };
                    },
                    _ => {},
                }
            },
            _ => {},
        }

        let row = effects.discardable[block.id];
        let statements: Statement[] = [];
        for (let index = 0; index < block.statements.length(); index += 1) {
            let statement = block.statements[index];
            let discard = match (statement.kind) {
                StatementKindAssign { destination: PlaceLocal { value: let local } }
                    if local > arity && uses[local] == 0 && !row[index] => {
                    local
                },
                _ => null,
            };
            statements.push(statement);
            if (discard != null) {
                // Reuse the existing eval-and-drop representation. This read
                // keeps the definition alive and pins evaluation to this
                // point.
                statements.push(
                    Statement {
                        kind: StatementKindDrop { value: PlaceLocal { value: discard } },
                        span: statement.span,
                    },
                );
                uses[discard] += 1;
            }
        }
        block.statements = statements;
    }

    // Force-alive: terminator destination locals can't be removed because
    // the terminator has side effects (Call, Await, SysOp, Spawn). Even if
    // the destination local has 0 read-uses, we must keep it.
    for (let block in body.blocks) {
        let dest_local = match (block.terminator) {
            let t: TerminatorCall => place_base_local(t.destination),
            let t: TerminatorVirtualCall => place_base_local(t.destination),
            let t: TerminatorAwait => place_base_local(t.destination),
            let t: TerminatorAwaitAny => place_base_local(t.destination),
            let t: TerminatorSpawn => place_base_local(t.future),
            let t: TerminatorSysOp => place_base_local(t.destination),
            let t: TerminatorNarrowBind => t.destination,
            // Discarded boolean short circuits became Branch above. Keep
            // coalescing's destination until its null test has executed.
            let t: TerminatorShortCircuit => place_base_local(t.destination),
            _ => null,
        };
        if (dest_local != null) {
            // ensure it survives
            uses[dest_local] = uses[dest_local].max(1);
        }
    }

    // Determine which locals to keep: _0 (return) + params + any with
    // uses > 0
    let old_to_new: (int?)[] = baml.Array.filled(body.locals.length(), null);
    let new_locals: LocalDecl[] = [];

    for (let i = 0; i < body.locals.length(); i += 1) {
        let keep = i == 0 || i <= arity || uses[i] > 0;
        if (keep) {
            old_to_new[i] = new_locals.length();
            new_locals.push(body.locals[i]);
        }
    }

    // If nothing was removed, skip rewriting
    if (new_locals.length() == body.locals.length()) {
        return;
    }

    // Potentially failing evaluations gained a Drop use above. The remaining
    // dead assignments can be removed without losing effects.
    for (let block in body.blocks) {
        block.statements
            = block.statements.filter((stmt) -> {
                match (stmt.kind) {
                    // keep only if local survived
                    StatementKindAssign { destination: PlaceLocal { value: let l } } => {
                        old_to_new[l] != null
                    },
                    _ => true,
                }
            });
    }

    // Rewrite all Local references
    for (let block in body.blocks) {
        block.statements
            = block.statements.map((stmt) -> {
                rewrite_locals_in_statement(stmt, old_to_new)
            });
        let term = block.terminator;
        if (term != null) {
            block.terminator = rewrite_locals_in_terminator(term, old_to_new);
        }
    }

    // Rewrite the handler landings' error + context locals: the VM writes
    // both, so both are always live (see `count_local_uses`), and a stale one
    // would make the emitter compute a stale slot (a nested-catch
    // `baml.errors.Context` bug).
    for (let block in body.blocks) {
        let landing = block.landing;
        if (landing != null) {
            block.landing
                = Landing {
                    error_local: old_to_new[landing.error_local]
                        ?? baml.sys.panic("a landing local is always live"),
                    context_local: old_to_new[landing.context_local]
                        ?? baml.sys.panic("a landing local is always live"),
                };
        }
    }

    body.locals = new_locals;
}

// port: baml_compiler2_mir/src/optimize.rs::remap_local @ d9be6853b
// Restructured: returns the remapped local.
function remap_local(l: int, map: (int?)[]) -> int throws never {
    map[l] ?? baml.sys.panic("local must have been kept")
}

// port: baml_compiler2_mir/src/optimize.rs::remap_place @ d9be6853b
// Restructured: returns the remapped place.
function remap_place(p: Place, map: (int?)[]) -> Place throws never {
    match (p) {
        let l: PlaceLocal => PlaceLocal { value: remap_local(l.value, map) },
        // Capture indices index into the closure's captures array: no local
        // to remap.
        PlaceCapture => p,
        let d: PlaceDeref => {
            match (d.value) {
                let cell: PlaceLocal => {
                    PlaceDeref { value: PlaceLocal { value: remap_local(cell.value, map) } }
                },
                PlaceCapture => p,
            }
        },
        let f: PlaceField => PlaceField { base: remap_place(f.base, map), field: f.field },
        let i: PlaceIndex => {
            let index = remap_local(i.index, map);
            PlaceIndex { base: remap_place(i.base, map), index: index, kind: i.kind }
        },
    }
}

// port: baml_compiler2_mir/src/optimize.rs::remap_operand @ d9be6853b
// Restructured: returns the remapped operand.
function remap_operand(op: Operand, map: (int?)[]) -> Operand throws never {
    match (op) {
        let o: OperandCopy => OperandCopy { value: remap_place(o.value, map) },
        let o: OperandMove => OperandMove { value: remap_place(o.value, map) },
        OperandConstant => op,
    }
}

// port: baml_compiler2_mir/src/optimize.rs::remap_rvalue @ d9be6853b
// Restructured: returns the remapped rvalue.
function remap_rvalue(rv: Rvalue, map: (int?)[]) -> Rvalue throws never {
    let operand = (op: Operand) -> Operand {
        remap_operand(op, map)
    };
    match (rv) {
        let r: RvalueUse => RvalueUse { value: operand(r.value) },
        let r: RvalueBinaryOp => {
            let left = operand(r.left);
            RvalueBinaryOp { op: r.op, left: left, right: operand(r.right) }
        },
        let r: RvalueUnaryOp => RvalueUnaryOp { op: r.op, operand: operand(r.operand) },
        RvalueUint8Array => rv,
        let r: RvalueArray => {
            RvalueArray { element_ty: r.element_ty, elements: r.elements.map(operand) }
        },
        let r: RvalueConcatStrings => RvalueConcatStrings { value: r.value.map(operand) },
        let r: RvalueMap => {
            let entries = r.entries.map((entry) -> {
                let key = operand(entry.0);
                (key, operand(entry.1))
            });
            RvalueMap { ...r, entries: entries }
        },
        let r: RvalueAggregate => RvalueAggregate { kind: r.kind, fields: r.fields.map(operand) },
        let r: RvalueDiscriminant => RvalueDiscriminant { value: remap_place(r.value, map) },
        let r: RvalueTypeTag => RvalueTypeTag { value: remap_place(r.value, map) },
        let r: RvalueLen => RvalueLen { value: remap_place(r.value, map) },
        let r: RvalueIsType => RvalueIsType { ...r, operand: operand(r.operand) },
        let r: RvalueIsTypeTag => RvalueIsTypeTag { ...r, operand: operand(r.operand) },
        let r: RvalueSatisfiesBound => RvalueSatisfiesBound { ...r, ty: operand(r.ty) },
        let r: RvalueMakeClosure => RvalueMakeClosure { ...r, captures: r.captures.map(operand) },
        let r: RvalueMakeVirtualFunction => {
            RvalueMakeVirtualFunction { ...r, type_args: r.type_args.map(operand) }
        },
        let r: RvalueMakeBoundMethod => {
            RvalueMakeBoundMethod { ...r, receiver: operand(r.receiver) }
        },
        let r: RvalueMakeVirtualBoundMethod => {
            RvalueMakeVirtualBoundMethod { ...r, receiver: operand(r.receiver) }
        },
        let r: RvalueVirtualFieldAccess => {
            RvalueVirtualFieldAccess { ...r, receiver: operand(r.receiver) }
        },
        let r: RvalueMakeGenericFunctionFromValue => {
            RvalueMakeGenericFunctionFromValue { ...r, value: operand(r.value) }
        },
        // No local operands: nothing to remap.
        RvalueLoadType | RvalueTraceHookSettings | RvalueCurrentPackage | RvalueMakeGenericFunction => {
            rv
        },
    }
}

// port: baml_compiler2_mir/src/optimize.rs::rewrite_locals_in_statement @ d9be6853b
// Restructured: returns the rewritten statement.
function rewrite_locals_in_statement(stmt: Statement, map: (int?)[]) -> Statement throws never {
    let kind: StatementKind = match (stmt.kind) {
        let s: StatementKindAssign => {
            let destination = remap_place(s.destination, map);
            StatementKindAssign { destination: destination, value: remap_rvalue(s.value, map) }
        },
        let s: StatementKindVirtualFieldStore => {
            let receiver = remap_operand(s.receiver, map);
            StatementKindVirtualFieldStore {
                ...s,
                receiver: receiver,
                value: remap_operand(s.value, map),
            }
        },
        let s: StatementKindDrop => StatementKindDrop { value: remap_place(s.value, map) },
        let s: StatementKindFreshCell => {
            StatementKindFreshCell { local: remap_local(s.local, map), carry_value: s.carry_value }
        },
        StatementKindNop => {
            return stmt;
        },
        let s: StatementKindIntrinsic => {
            StatementKindIntrinsic {
                op: s.op,
                args: s.args.map((arg) -> {
                    remap_operand(arg, map)
                }),
            }
        },
    };
    Statement { kind: kind, span: stmt.span }
}

// port: baml_compiler2_mir/src/optimize.rs::rewrite_locals_in_terminator @ d9be6853b
// Restructured: returns the rewritten terminator.
function rewrite_locals_in_terminator(term: Terminator, map: (int?)[]) -> Terminator throws never {
    let operand = (op: Operand) -> Operand {
        remap_operand(op, map)
    };
    match (term) {
        let t: TerminatorBranch => TerminatorBranch { ...t, condition: operand(t.condition) },
        let t: TerminatorNarrowBind => {
            let source = operand(t.source);
            TerminatorNarrowBind {
                ...t,
                source: source,
                destination: remap_local(t.destination, map),
            }
        },
        let t: TerminatorSwitch => TerminatorSwitch { ...t, discriminant: operand(t.discriminant) },
        let t: TerminatorCall => {
            let callee = operand(t.callee);
            let args = t.args.map(operand);
            TerminatorCall {
                ...t,
                callee: callee,
                args: args,
                destination: remap_place(t.destination, map),
            }
        },
        let t: TerminatorSysOp => {
            let callee = operand(t.callee);
            let args = t.args.map(operand);
            TerminatorSysOp {
                ...t,
                callee: callee,
                args: args,
                destination: remap_place(t.destination, map),
            }
        },
        // No callee operand: the method is resolved at runtime from `iface`.
        let t: TerminatorVirtualCall => {
            let args = t.args.map(operand);
            TerminatorVirtualCall { ...t, args: args, destination: remap_place(t.destination, map) }
        },
        let t: TerminatorSpawn => {
            let plan = operand(t.plan);
            TerminatorSpawn { ...t, plan: plan, future: remap_place(t.future, map) }
        },
        let t: TerminatorAwait => {
            let future = remap_place(t.future, map);
            TerminatorAwait { ...t, future: future, destination: remap_place(t.destination, map) }
        },
        let t: TerminatorAwaitAny => {
            let futures = operand(t.futures);
            TerminatorAwaitAny {
                ...t,
                futures: futures,
                destination: remap_place(t.destination, map),
            }
        },
        let t: TerminatorThrow => TerminatorThrow { value: operand(t.value) },
        let t: TerminatorRethrow => {
            let value = operand(t.value);
            TerminatorRethrow { value: value, context: operand(t.context) }
        },
        let t: TerminatorShortCircuit => {
            let operand_value = operand(t.operand);
            TerminatorShortCircuit {
                ...t,
                operand: operand_value,
                destination: remap_place(t.destination, map),
            }
        },
        TerminatorGoto | TerminatorReturn | TerminatorUnreachable => term,
    }
}

// ============================================================================
// Phase 4: Post-optimization MIR validation
// ============================================================================

// port: baml_compiler2_mir/src/optimize.rs::verify_mir @ d9be6853b
// Verify MIR structural invariants after optimization. Catches invariant
// drift between lowering, optimization, and downstream consumers. `name` is
// rendered only inside a failing assertion.
function verify_mir(
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
    name: () -> string throws never,
) -> void throws never {
    let num_blocks = body.blocks.length();
    let num_locals = body.locals.length();

    // 1. Block ID / index density: block.id must equal its position.
    for (let idx = 0; idx < num_blocks; idx += 1) {
        let block = body.blocks[idx];
        if (block.id != idx) {
            baml.sys.panic(
                `block id/index mismatch in ${name()}: block.id=BlockId(${block.id}), index=bb${idx}`,
            );
        }
    }

    // 2. Every block must be terminated.
    for (let block in body.blocks) {
        if (block.terminator == null) {
            baml.sys.panic(`unterminated block BlockId(${block.id}) in MIR function ${name()}`);
        }
    }

    // 3. All BlockId references in terminators must be in-range.
    for (let block in body.blocks) {
        let term = block.terminator;
        if (term != null) {
            for (let succ in terminator_successors(term)) {
                if (succ >= num_blocks) {
                    baml.sys.panic(
                        `dangling BlockId(${succ}) in terminator of BlockId(${block.id}) in MIR function ${name()}`,
                    );
                }
            }
        }
    }

    // 4. All Local references must be in-range. Walk every Place/Operand in
    //    statements and terminators.
    let check_local = (l: int, ctx: string) -> void {
        if (l >= num_locals) {
            baml.sys.panic(
                `dangling Local ${local_to_string(l)} in ${ctx} of MIR function ${name()}`,
            );
        }
    };

    let check_place = (p: Place, ctx: string) -> void {
        let cur = p;
        while (true) {
            match (cur) {
                let l: PlaceLocal => {
                    check_local(l.value, ctx);
                    break;
                },
                // Capture index: no local to check.
                PlaceCapture => {
                    break;
                },
                // The value in a cell: a local's cell is a captured local's.
                let d: PlaceDeref => {
                    match (d.value) {
                        let cell: PlaceLocal => {
                            check_local(cell.value, ctx);
                            if (!body.local(cell.value).is_captured) {
                                baml.sys.panic(
                                    `deref of uncaptured ${local_to_string(cell.value)} in ${ctx} of MIR function ${name()}`,
                                );
                            }
                        },
                        PlaceCapture => {},
                    }
                    break;
                },
                let f: PlaceField => {
                    cur = f.base;
                },
                let i: PlaceIndex => {
                    check_local(i.index, ctx);
                    cur = i.base;
                },
            }
        }
    };

    let check_operand = (op: Operand, ctx: string) -> void {
        match (op) {
            let o: OperandCopy => check_place(o.value, ctx),
            let o: OperandMove => check_place(o.value, ctx),
            OperandConstant => {},
        }
    };

    for (let block in body.blocks) {
        let blk = `BlockId(${block.id})`;
        for (let stmt in block.statements) {
            match (stmt.kind) {
                let s: StatementKindAssign => {
                    check_place(s.destination, blk);
                    verify_rvalue_operands(
                        s.value,
                        (op) -> {
                            check_operand(op, blk)
                        },
                        (place) -> {
                            check_place(place, blk)
                        },
                    );
                },
                let s: StatementKindVirtualFieldStore => {
                    check_operand(s.receiver, blk);
                    check_operand(s.value, blk);
                },
                let s: StatementKindIntrinsic => {
                    for (let arg in s.args) {
                        check_operand(arg, blk);
                    }
                },
                let s: StatementKindDrop => check_place(s.value, blk),
                let s: StatementKindFreshCell => check_local(s.local, blk),
                // Exhaustive rather than wildcarded: an operand-carrying
                // statement kind that skips this check loses the one cheap
                // tripwire for a reference to a retired local.
                StatementKindNop => {},
            }
        }
    }

    // 4b. Also check Local references in terminators.
    for (let block in body.blocks) {
        let blk = `BlockId(${block.id})`;
        match (block.terminator) {
            let t: TerminatorBranch => check_operand(t.condition, blk),
            let t: TerminatorNarrowBind => {
                check_operand(t.source, blk);
                check_local(t.destination, blk);
            },
            let t: TerminatorSwitch => check_operand(t.discriminant, blk),
            let t: TerminatorCall => {
                check_operand(t.callee, blk);
                for (let a in t.args) {
                    check_operand(a, blk);
                }

                check_place(t.destination, blk);
            },
            let t: TerminatorVirtualCall => {
                // No callee operand: the method is resolved at runtime from
                // `iface`.
                for (let a in t.args) {
                    check_operand(a, blk);
                }

                check_place(t.destination, blk);
            },
            let t: TerminatorSysOp => {
                check_operand(t.callee, blk);
                for (let a in t.args) {
                    check_operand(a, blk);
                }

                check_place(t.destination, blk);
            },
            let t: TerminatorSpawn => {
                check_operand(t.plan, blk);
                check_place(t.future, blk);
            },
            let t: TerminatorAwait => {
                check_place(t.future, blk);
                check_place(t.destination, blk);
            },
            let t: TerminatorAwaitAny => {
                check_operand(t.futures, blk);
                check_place(t.destination, blk);
            },
            let t: TerminatorThrow => check_operand(t.value, blk),
            let t: TerminatorRethrow => {
                check_operand(t.value, blk);
                check_operand(t.context, blk);
            },
            let t: TerminatorShortCircuit => {
                check_operand(t.operand, blk);
                check_place(t.destination, blk);
            },
            _ => {},
        }
    }

    // 5. Exhaustive switches must have Unreachable otherwise block.
    for (let block in body.blocks) {
        match (block.terminator) {
            let t: TerminatorSwitch if t.exhaustive => {
                let otherwise_block = body.blocks[t.otherwise];
                let is_unreachable = otherwise_block.statements.length() == 0
                    && otherwise_block.terminator is TerminatorUnreachable;
                if (!is_unreachable) {
                    baml.sys.panic(
                        `exhaustive switch in BlockId(${block.id}) has non-unreachable default block BlockId(${t.otherwise}) in MIR function ${name()}`,
                    );
                }
            },
            _ => {},
        }
    }

    // 7. Handler edges point at handler blocks, and landings name valid
    //    locals.
    for (let block in body.blocks) {
        for (let edge in [("unwind", block.unwind), ("handling", block.handling)]) {
            let target = edge.1;
            if (target == null) {
                continue;
            }
            if (target >= num_blocks) {
                baml.sys.panic(
                    `dangling ${edge.0} BlockId(${target}) of BlockId(${block.id}) in MIR function ${name()}`,
                );
            }
            if (body.blocks[target].landing == null) {
                baml.sys.panic(
                    `${edge.0} BlockId(${target}) of BlockId(${block.id}) is not a handler block in MIR function ${name()}`,
                );
            }
        }
        let landing = block.landing;
        if (landing != null) {
            for (let local in [landing.error_local, landing.context_local]) {
                if (local >= num_locals) {
                    baml.sys.panic(
                        `dangling landing local ${local_to_string(local)} of handler BlockId(${block.id}) in MIR function ${name()}`,
                    );
                }
            }
        }
    }

    // 9. Entry block must be valid.
    if (body.entry >= num_blocks) {
        baml.sys.panic(`entry block BlockId(${body.entry}) out of range in MIR function ${name()}`);
    }

    // 10. Every read is definitely assigned; every captured access has its
    //     cell.
    verify_definite_assignment(db, body, arity, name);

    // 11. The CFG is reducible: every loop is entered only at its header.
    //     Lowering only builds such loops; this checks the passes kept it
    //     so.
    let irreducible = check(body);
    if (irreducible != null) {
        let blocks = irreducible
            .map((b) -> {
                `BlockId(${b})`
            })
            .join(", ");
        baml.sys.panic(
            `irreducible control flow in MIR function ${name()}: a cycle with more than one entry among [${blocks}]`,
        );
    }
}

// port: baml_compiler2_mir/src/optimize.rs::verify_mir @ d9be6853b
// Restructured: step 4's walk over an assignment's rvalue, its operands in
// Rust's order (`operand`) and its place reads (`place`).
function verify_rvalue_operands(
    value: Rvalue,
    operand: (Operand) -> void throws never,
    place: (Place) -> void throws never,
) -> void throws never {
    match (value) {
        let r: RvalueUse => operand(r.value),
        let r: RvalueBinaryOp => {
            operand(r.left);
            operand(r.right);
        },
        let r: RvalueUnaryOp => operand(r.operand),
        RvalueUint8Array => {},
        let r: RvalueArray => {
            for (let e in r.elements) {
                operand(e);
            }
        },
        let r: RvalueConcatStrings => {
            for (let e in r.value) {
                operand(e);
            }
        },
        let r: RvalueMap => {
            for (let entry in r.entries) {
                operand(entry.0);
                operand(entry.1);
            }
        },
        let r: RvalueAggregate => {
            for (let f in r.fields) {
                operand(f);
            }
        },
        let r: RvalueDiscriminant => place(r.value),
        let r: RvalueTypeTag => place(r.value),
        let r: RvalueLen => place(r.value),
        let r: RvalueIsType => operand(r.operand),
        let r: RvalueIsTypeTag => operand(r.operand),
        let r: RvalueSatisfiesBound => operand(r.ty),
        let r: RvalueMakeClosure => {
            for (let cap in r.captures) {
                operand(cap);
            }
        },
        let r: RvalueMakeVirtualFunction => {
            for (let arg in r.type_args) {
                operand(arg);
            }
        },
        let r: RvalueMakeBoundMethod => operand(r.receiver),
        let r: RvalueMakeVirtualBoundMethod => operand(r.receiver),
        let r: RvalueVirtualFieldAccess => operand(r.receiver),
        let r: RvalueMakeGenericFunctionFromValue => operand(r.value),
        // LoadType takes no local operands: nothing to check.
        RvalueLoadType | RvalueTraceHookSettings | RvalueCurrentPackage | RvalueMakeGenericFunction => {},
    }
}

// port: baml_compiler2_mir/src/optimize.rs::verify_definite_assignment::State @ d9be6853b
class State {
    assigned: bool[],
    celled: bool[],

    // port: baml_compiler2_mir/src/optimize.rs::verify_definite_assignment::State (derived Clone) @ d9be6853b
    function clone(self) -> State throws never {
        State { assigned: self.assigned.concat([]), celled: self.celled.concat([]) }
    }

    // port: baml_compiler2_mir/src/optimize.rs::verify_definite_assignment::State::meet @ d9be6853b
    // Intersect `other` into `self`; whether anything changed.
    function meet(self, other: State) -> bool throws never {
        let changed = false;
        for (let pair in [(self.assigned, other.assigned), (self.celled, other.celled)]) {
            let mine = pair.0;
            for (let i = 0; i < mine.length(); i += 1) {
                if (mine[i] && !pair.1[i]) {
                    mine[i] = false;
                    changed = true;
                }
            }
        }
        changed
    }
}

// port: baml_compiler2_mir/src/optimize.rs::verify_definite_assignment::join @ d9be6853b
function join(
    block: int,
    incoming: State,
    state_in: (State?)[],
    worklist: int[],
) -> void throws never {
    let existing = state_in[block];
    let changed = if (existing != null) {
        existing.meet(incoming)
    } else {
        state_in[block] = incoming.clone();
        true
    };
    if (changed) {
        worklist.push(block);
    }
}

// port: baml_compiler2_mir/src/optimize.rs::verify_definite_assignment @ d9be6853b
// Every read of a local is dominated by a write to it, and every read,
// write, or closure capture of a captured local is dominated by one of its
// `FreshCell`s: parameters by frame entry, where the emitter cells them.
//
// The cell half is what lets the emitter discard an unused deref load and
// what makes a closure created in a loop see its own iteration's binding:
// lowering creates a captured binding's cell exactly where the binding is
// created, and this check is the tripwire for a declaration site that did
// not.
//
// A forward dataflow over "definitely assigned" and "definitely celled",
// meeting by intersection. Roots are the entry block, with the parameters
// assigned (and celled when captured), and each catch handler, which the
// runtime enters with the region's error local and stack-trace local
// written. A trap anywhere in a protected block reaches the handler, so each
// body block's end-of-statements state flows there too; that over-counts
// what the handler can rely on only for locals declared inside the
// protected body, which the handler cannot name.
//
// Restructured: the dataflow is here; the checks at its fixpoint are
// `verify_definite_assignment_checks`.
function verify_definite_assignment(
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
    name: () -> string throws never,
) -> void throws never {
    let num_locals = body.locals.length();

    // What a terminator assigns on each outgoing edge. Handler edges from
    // traps are not terminator edges; they are added from the blocks'
    // `unwind`.
    let edges = (term: Terminator) -> (int, int?)[] {
        let local_of = (place: Place) -> int? {
            match (place) {
                let l: PlaceLocal => l.value,
                _ => null,
            }
        };
        match (term) {
            let t: TerminatorGoto => [(t.target, null)],
            let t: TerminatorBranch => [(t.then_block, null), (t.else_block, null)],
            let t: TerminatorNarrowBind => [(t.then_block, t.destination), (t.else_block, null)],
            let t: TerminatorSwitch => {
                let out: (int, int?)[] = t.arms.map((arm) -> {
                    let edge: (int, int?) = (arm.1, null);
                    edge
                });
                out.push((t.otherwise, null));
                out
            },
            TerminatorCall { destination: let destination, target: let target, unwind: let unwind }
                | TerminatorVirtualCall {
                destination: let destination,
                target: let target,
                unwind: let unwind,
            }
                | TerminatorSysOp { destination: let destination, target: let target, unwind: let unwind }
                | TerminatorAwait { destination: let destination, target: let target, unwind: let unwind }
                | TerminatorAwaitAny {
                destination: let destination,
                target: let target,
                unwind: let unwind,
            } =>
            {
                let out: (int, int?)[] = [(target, local_of(destination))];
                if (unwind != null) {
                    out.push((unwind, null));
                }
                out
            },
            let t: TerminatorSpawn => [(t.resume, local_of(t.future))],
            let t: TerminatorShortCircuit => [(t.eval_rhs, null), (t.join, local_of(t.destination))],
            TerminatorReturn | TerminatorUnreachable | TerminatorThrow | TerminatorRethrow => [],
        }
    };

    // The locals the runtime writes when it enters a handler, and the
    // handler each protected block traps to.
    let handler_defs: map<int, int[]> = {};
    let trap_targets: map<int, int[]> = {};
    for (let handler in body.handlers()) {
        let defs = handler_defs.get_or_insert(handler.0, []);
        defs.push(handler.1.error_local);
        defs.push(handler.1.context_local);
    }
    for (let block in body.blocks) {
        let handler = block.unwind;
        if (handler != null) {
            trap_targets.get_or_insert(block.id, []).push(handler);
        }
    }

    let entry = State {
        assigned: baml.Array.filled(num_locals, false),
        celled: baml.Array.filled(num_locals, false),
    };
    for (let param = 1; param <= arity; param += 1) {
        entry.assigned[param] = true;
        entry.celled[param] = body.local(param).is_captured;
    }

    let state_in: (State?)[] = baml.Array.filled(body.blocks.length(), null);
    let worklist: int[] = [];
    join(body.entry, entry, state_in, worklist);

    // A block's state at the end of its statements, from its entry state.
    let after_statements = (block: int) -> State {
        let state = (state_in[block] ?? baml.sys.panic("only reached blocks are processed")).clone();
        for (let local in handler_defs.get(block) ?? []) {
            state.assigned[local] = true;
        }
        for (let stmt in body.blocks[block].statements) {
            definite_assignment_transfer(state, stmt.kind);
        }
        state
    };

    while let block: int = worklist.shift() {
        let out = after_statements(block);
        for (let handler in trap_targets.get(block) ?? []) {
            join(handler, out, state_in, worklist);
        }
        let term = body.blocks[block].terminator;
        if (term != null) {
            for (let edge in edges(term)) {
                let edge_state = out.clone();
                let def = edge.1;
                if (def != null) {
                    edge_state.assigned[def] = true;
                }
                join(edge.0, edge_state, state_in, worklist);
            }
        }
    }

    // Checks, at the fixpoint, over every reached block.
    for (let idx = 0; idx < body.blocks.length(); idx += 1) {
        let reached = state_in[idx];
        if (reached == null) {
            continue;
        }
        let state = reached.clone();
        for (let local in handler_defs.get(idx) ?? []) {
            state.assigned[local] = true;
        }
        verify_definite_assignment_checks(db, body, arity, name, idx, state);
    }
}

// port: baml_compiler2_mir/src/optimize.rs::verify_definite_assignment @ d9be6853b
// Restructured: the closure `transfer`. Transfer function, without checks:
// the checks run once at the fixpoint. A store through a captured local's
// cell gives the binding its value.
function definite_assignment_transfer(state: State, kind: StatementKind) -> void throws never {
    match (kind) {
        StatementKindAssign { destination: PlaceLocal { value: let local } } => {
            state.assigned[local] = true;
        },
        StatementKindAssign { destination: PlaceDeref { value: let cell } } => {
            let local = cell_id_local(cell);
            if (local != null) {
                state.assigned[local] = true;
            }
        },
        let s: StatementKindFreshCell => {
            state.celled[s.local] = true;
            // The new cell holds `null` unless the old value was carried.
            if (!s.carry_value) {
                state.assigned[s.local] = false;
            }
        },
        StatementKindAssign
            | StatementKindDrop
            | StatementKindIntrinsic
            | StatementKindVirtualFieldStore
            | StatementKindNop =>
        {},
    }
}

// port: baml_compiler2_mir/src/optimize.rs::verify_definite_assignment @ d9be6853b
// Restructured: the checks over one reached block (`block_id`, entered
// with `state`), with Rust's `check!` macro as `fail`: a failed check
// prints the body, since the block id alone rarely says which lowering path
// is wrong. Rust's `{capture:?}` of a non-cell capture operand is spelled
// with `place_to_string` (or "a constant").
function verify_definite_assignment_checks(
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
    name: () -> string throws never,
    block_id: int,
    state: State,
) -> void throws never {
    let block = body.blocks[block_id];
    let blk = `BlockId(${block_id})`;
    let fail = (message: string) -> void {
        baml.sys.panic(`${message}\n\n${display_body(db, body, arity)}`);
    };
    let is_captured = (local: int) -> bool {
        body.local(local).is_captured
    };
    let read_local = (local: int, what: string) -> void {
        if (!state.assigned[local]) {
            fail(
                `${what} ${local_to_string(local)} in ${blk} of ${name()} before it is definitely assigned`,
            );
        }
        if (is_captured(local) && !state.celled[local]) {
            fail(
                `${what} captured ${local_to_string(local)} in ${blk} of ${name()} before its cell exists`,
            );
        }
    };
    // A value read. A bare captured local or capture is a cell pointer,
    // which only a closure capture operand or a `FreshCell` may name.
    let read_place = (place: Place) -> void {
        let cur = place;
        while (true) {
            match (cur) {
                let l: PlaceLocal => {
                    if (is_captured(l.value)) {
                        fail(
                            `bare read of captured ${local_to_string(l.value)}'s pointer in ${blk} of ${name()}`,
                        );
                    }
                    read_local(l.value, "read of");
                    break;
                },
                PlaceCapture => {
                    fail(`bare read of a capture pointer in ${blk} of ${name()}`);
                    break;
                },
                let d: PlaceDeref => {
                    let local = cell_id_local(d.value);
                    if (local != null) {
                        read_local(local, "read through");
                    }
                    break;
                },
                let f: PlaceField => {
                    cur = f.base;
                },
                let i: PlaceIndex => {
                    read_local(i.index, "index read of");
                    cur = i.base;
                },
            }
        }
    };
    let read_operand = (operand: Operand) -> void {
        match (operand) {
            let o: OperandCopy => read_place(o.value),
            let o: OperandMove => read_place(o.value),
            OperandConstant => {},
        }
    };
    // A destination: its projections are reads, and a captured local is
    // written only through its cell, which must exist.
    let write_place = (place: Place) -> void {
        match (place) {
            let l: PlaceLocal => {
                if (is_captured(l.value)) {
                    fail(
                        `bare store to captured ${local_to_string(l.value)}'s pointer in ${blk} of ${name()}`,
                    );
                }
            },
            let d: PlaceDeref => {
                let local = cell_id_local(d.value);
                if (local != null && !state.celled[local]) {
                    fail(
                        `write through captured ${local_to_string(local)} in ${blk} of ${name()} before its cell exists`,
                    );
                }
            },
            PlaceCapture => fail(`store to a bare capture pointer in ${blk} of ${name()}`),
            PlaceField | PlaceIndex => read_place(place),
        }
    };

    for (let stmt in block.statements) {
        match (stmt.kind) {
            let s: StatementKindAssign => {
                match (s.value) {
                    // A capture operand is the cell pointer: it needs the
                    // cell, not a value in it.
                    let r: RvalueMakeClosure => {
                        for (let capture in r.captures) {
                            match (capture) {
                                OperandCopy { value: PlaceLocal { value: let local } }
                                    | OperandMove { value: PlaceLocal { value: let local } } =>
                                {
                                    if (!state.celled[local]) {
                                        fail(
                                            `closure captures ${local_to_string(local)} in ${blk} of ${name()} before its cell exists`,
                                        );
                                    }
                                },
                                OperandCopy { value: PlaceCapture }
                                    | OperandMove { value: PlaceCapture } =>
                                {},
                                let o: OperandCopy => {
                                    fail(
                                        `closure capture operand copy ${place_to_string(o.value)} in ${blk} of ${name()} is not a cell pointer`,
                                    );
                                },
                                let o: OperandMove => {
                                    fail(
                                        `closure capture operand move ${place_to_string(o.value)} in ${blk} of ${name()} is not a cell pointer`,
                                    );
                                },
                                OperandConstant => {
                                    fail(
                                        `closure capture operand a constant in ${blk} of ${name()} is not a cell pointer`,
                                    );
                                },
                            }
                        }
                    },
                    _ => walk_rvalue_places(s.value, read_place),
                }
                write_place(s.destination);
            },
            let s: StatementKindFreshCell => {
                if (!is_captured(s.local)) {
                    fail(
                        `fresh_cell on ${local_to_string(s.local)} in ${blk} of ${name()}, which no closure captures`,
                    );
                }
                if (s.local <= arity) {
                    fail(
                        `fresh_cell on parameter ${local_to_string(s.local)} in ${blk} of ${name()}; parameters are celled at entry`,
                    );
                }
                if (s.carry_value) {
                    read_local(s.local, "carrying re-cell of");
                }
            },
            let s: StatementKindDrop => read_place(s.value),
            let s: StatementKindIntrinsic => {
                for (let arg in s.args) {
                    read_operand(arg);
                }
            },
            let s: StatementKindVirtualFieldStore => {
                read_operand(s.receiver);
                read_operand(s.value);
            },
            StatementKindNop => {},
        }
        definite_assignment_transfer(state, stmt.kind);
    }

    match (block.terminator) {
        let t: TerminatorBranch => read_operand(t.condition),
        let t: TerminatorNarrowBind => read_operand(t.source),
        let t: TerminatorSwitch => read_operand(t.discriminant),
        TerminatorReturn => read_local(0, "return of"),
        TerminatorCall { callee: let callee, args: let args, destination: let destination }
            | TerminatorSysOp { callee: let callee, args: let args, destination: let destination } =>
        {
            read_operand(callee);
            for (let arg in args) {
                read_operand(arg);
            }
            write_place(destination);
        },
        let t: TerminatorVirtualCall => {
            for (let arg in t.args) {
                read_operand(arg);
            }
            write_place(t.destination);
        },
        let t: TerminatorSpawn => {
            read_operand(t.plan);
            write_place(t.future);
        },
        let t: TerminatorAwait => {
            read_place(t.future);
            write_place(t.destination);
        },
        let t: TerminatorAwaitAny => {
            read_operand(t.futures);
            write_place(t.destination);
        },
        let t: TerminatorThrow => read_operand(t.value),
        let t: TerminatorRethrow => {
            read_operand(t.value);
            read_operand(t.context);
        },
        let t: TerminatorShortCircuit => {
            read_operand(t.operand);
            write_place(t.destination);
        },
        _ => {},
    }
}

// ============================================================================
// Phase 3: RPO block reordering
// ============================================================================

// port: baml_compiler2_mir/src/optimize.rs::reorder_blocks_rpo @ d9be6853b
// Phase 3: Reorder blocks into reverse-post-order.
//
// After dead block elimination (Phase 1), blocks are densely packed but
// their IDs still follow allocation order rather than execution order. RPO
// reordering ensures that `bb0 -> bb1 -> bb2 -> ...` corresponds to typical
// execution flow, making the MIR output much more readable.
function reorder_blocks_rpo(body: MirFunctionBody) -> void throws never {
    let num_blocks = body.blocks.length();
    if (num_blocks <= 1) {
        return;
    }

    // Compute RPO via iterative DFS. Seed with entry AND exception handler
    // blocks (reachable at runtime via exception table, not CFG edges).
    let visited = baml.Array.filled(num_blocks, false);
    let post_order: int[] = [];
    let stack: (int, bool)[] = [(body.entry, false)];
    for (let handler in body.handlers()) {
        stack.push((handler.0, false));
    }

    while let frame: (int, bool) = stack.pop() {
        let block_id = frame.0;
        if (frame.1) {
            post_order.push(block_id);
            continue;
        }
        if (visited[block_id]) {
            continue;
        }
        visited[block_id] = true;
        // push for post-order recording
        stack.push((block_id, true));

        let term = body.blocks[block_id].terminator;
        if (term != null) {
            // Push successors in reverse order so first successor is visited
            // first
            for (let succ in terminator_successors(term).reverse()) {
                if (!visited[succ]) {
                    stack.push((succ, false));
                }
            }
        }
    }

    // Reverse post_order to get RPO
    let rpo = post_order.reverse();

    // Check if already in RPO order (optimization: skip rewriting if nothing
    // changes)
    let already_ordered = true;
    for (let i = 0; i < rpo.length(); i += 1) {
        if (rpo[i] != i) {
            already_ordered = false;
            break;
        }
    }
    if (already_ordered && rpo.length() == num_blocks) {
        return;
    }

    // Build old -> new mapping
    let old_to_new: (int?)[] = baml.Array.filled(num_blocks, null);
    for (let new_idx = 0; new_idx < rpo.length(); new_idx += 1) {
        old_to_new[rpo[new_idx]] = new_idx;
    }

    // Reorder blocks and rewrite internal BlockId references
    let new_blocks: BasicBlock[] = [];
    for (let old_id in rpo) {
        let block = BasicBlock {
            ...body.blocks[old_id],
            id: old_to_new[old_id] ?? baml.sys.panic("a block in RPO has a new id"),
        };
        let term = block.terminator;
        if (term != null) {
            block.terminator = rewrite_block_ids_in_terminator(term, old_to_new);
        }
        new_blocks.push(block);
    }

    // Rewrite entry
    body.entry = old_to_new[body.entry] ?? baml.sys.panic("entry must be in RPO");

    for (let block in new_blocks) {
        rewrite_handler_refs(block, old_to_new);
    }

    body.blocks = new_blocks;
}
