// port: baml_compiler2_mir/src/memory.rs @ d9be6853b
//
// What a MIR instruction reads and writes, as sets of resources: frame
// slots, cells, frame type-argument slots, heap fields and elements, and
// the order of observable effects. The one place that answers "what does
// this rvalue read" and "what does this instruction write", for the MIR
// optimizer and the emitter.
//
// Restructured (BAML forces it):
// - `HashSet<Local>`, `HashSet<u32>`, `HashSet<usize>` are `map<int, bool>`.
// - A set of `CellId`s is `map<int, CellId>`, keyed by `cell_key` (a
//   local's cell `2 * local`, a capture's `2 * index + 1`: injective, so
//   two cells share a key exactly when they are the same cell) with the
//   cell itself (a `cell_copy`, never the MIR's own place) as the value, so
//   the set can be iterated. Used by `Resources.cells` and
//   `spawn_shared_cells`.
// - The `&mut impl FnMut` visitors are closures `(..) -> void`.
// - `spawn_shared_cells`'s local `Defs` and `Walk` structs are the
//   namespace classes `Defs` and `Walk`, `Walk`'s methods free of borrows.
// - `CellId::try_from(place)` is a `match` on the place (`PlaceLocal` and
//   `PlaceCapture` are the cell ids).

// Not in Rust: the key of a cell in a `CellId` set (see the header).
function cell_key(cell: CellId) -> int throws never {
    match (cell) {
        let l: PlaceLocal => 2 * l.value,
        let c: PlaceCapture => 2 * c.value + 1,
    }
}

// Not in Rust: a copy of a cell id taken from MIR, for a set that outlives
// the instruction it came from. The optimizer rewrites places in place, and
// a set holding the MIR's own `PlaceLocal` would then disagree with its
// `cell_key`. Rust's `CellId` is `Copy`.
function cell_copy(cell: CellId) -> CellId throws never {
    match (cell) {
        let l: PlaceLocal => PlaceLocal { value: l.value },
        let c: PlaceCapture => PlaceCapture { value: c.value },
    }
}

// port: baml_compiler2_mir/src/memory.rs::Resources @ d9be6853b
// A set of resources, read by an evaluation or written by an instruction.
// Restructured: `cells` is keyed by `cell_key` (see the header). Rust's
// `Default` is `Resources.empty()`.
class Resources {
    // Frame slots holding values (registers).
    locals: map<int, bool>,
    // Cells, through a captured local or a capture slot.
    cells: map<int, CellId>,
    // Frame type-argument slots: the `TypeArgRef` leaves of a template,
    // which a `BindType` rebinds.
    type_slots: map<int, bool>,
    // Heap fields by index, on any object.
    fields: map<int, bool>,
    // Container elements and lengths, of any container.
    elements: bool,
    // Every heap location at once: every field, element, and cell. Read by
    // an access this module cannot name (an interface field resolved at
    // run time); written by anything that may run arbitrary code.
    heap: bool,
    // The order of observable effects. Read by an evaluation that can
    // trap, because the trap is itself an event; written by every
    // observable instruction.
    order: bool,

    // port: baml_compiler2_mir/src/memory.rs::Resources (derive Default) @ d9be6853b
    function empty() -> Resources throws never {
        Resources {
            locals: {},
            cells: {},
            type_slots: {},
            fields: {},
            elements: false,
            heap: false,
            order: false,
        }
    }

    // port: baml_compiler2_mir/src/memory.rs::Resources::is_empty @ d9be6853b
    function is_empty(self) -> bool throws never {
        self.locals.length() == 0
            && self.cells.length() == 0
            && self.type_slots.length() == 0
            && self.fields.length() == 0
            && !self.elements
            && !self.heap
            && !self.order
    }

    // port: baml_compiler2_mir/src/memory.rs::Resources::extend @ d9be6853b
    function extend(self, other: Resources) -> void throws never {
        for (let local in other.locals.keys()) {
            self.locals[local] = true;
        }
        for (let key in other.cells.keys()) {
            self.cells[key] = other.cells[key];
        }
        for (let slot in other.type_slots.keys()) {
            self.type_slots[slot] = true;
        }
        for (let field in other.fields.keys()) {
            self.fields[field] = true;
        }
        self.elements = self.elements || other.elements;
        self.heap = self.heap || other.heap;
        self.order = self.order || other.order;
    }

    // port: baml_compiler2_mir/src/memory.rs::Resources::touches_heap @ d9be6853b
    // Whether the set names any heap location.
    function touches_heap(self) -> bool throws never {
        self.heap || self.elements || self.fields.length() != 0 || self.cells.length() != 0
    }

    // port: baml_compiler2_mir/src/memory.rs::Resources::intersects @ d9be6853b
    // Whether some resource is in both sets. Symmetric: `heap` on either
    // side meets any heap location on the other.
    function intersects(self, other: Resources) -> bool throws never {
        (self.heap && other.touches_heap())
            || (other.heap && self.touches_heap())
            || (self.elements && other.elements)
            || (self.order && other.order)
            || self.fields.keys().some((field) -> {
                other.fields.has(field)
            })
            || self.cells.keys().some((cell) -> {
                other.cells.has(cell)
            })
            || self.locals.keys().some((local) -> {
                other.locals.has(local)
            })
            || self.type_slots.keys().some((slot) -> {
                other.type_slots.has(slot)
            })
    }
}

// port: baml_compiler2_mir/src/memory.rs::ClobberModel @ d9be6853b
// How writes to frame slots are judged.
class ClobberModel {
    // Whether a register write is an observable event. A slot is invisible
    // outside its frame, so only a catch handler in the same frame can see
    // one slot's value after a trap elsewhere in the frame; a body with no
    // handler has no observer of them.
    registers_observed: bool,

    // port: baml_compiler2_mir/src/memory.rs::ClobberModel::for_body @ d9be6853b
    function for_body(body: MirFunctionBody) -> ClobberModel throws never {
        ClobberModel { registers_observed: body.handlers().length() != 0 }
    }
}

// port: baml_compiler2_mir/src/memory.rs::walk_operand_places @ d9be6853b
// Walk every place an operand names, calling `f` for each.
function walk_operand_places(
    operand: Operand,
    f: (Place) -> void throws never,
) -> void throws never {
    match (operand) {
        let c: OperandCopy => f(c.value),
        let m: OperandMove => f(m.value),
        OperandConstant => {},
    }
}

// port: baml_compiler2_mir/src/memory.rs::walk_rvalue_places @ d9be6853b
// Walk every place an rvalue reads, calling `f` for each. The one traversal
// every reader of an rvalue's operands goes through, so no two can disagree
// about which operands evaluating it touches.
function walk_rvalue_places(rvalue: Rvalue, f: (Place) -> void throws never) -> void throws never {
    match (rvalue) {
        let r: RvalueUse => walk_operand_places(r.value, f),
        let r: RvalueBinaryOp => {
            walk_operand_places(r.left, f);
            walk_operand_places(r.right, f);
        },
        let r: RvalueUnaryOp => walk_operand_places(r.operand, f),
        let r: RvalueArray => {
            for (let elem in r.elements) {
                walk_operand_places(elem, f);
            }
        },
        let r: RvalueConcatStrings => {
            for (let elem in r.value) {
                walk_operand_places(elem, f);
            }
        },
        RvalueUint8Array => {},
        let r: RvalueMap => {
            for (let entry in r.entries) {
                walk_operand_places(entry.0, f);
                walk_operand_places(entry.1, f);
            }
        },
        let r: RvalueAggregate => {
            for (let field in r.fields) {
                walk_operand_places(field, f);
            }
        },
        let r: RvalueDiscriminant => f(r.value),
        let r: RvalueTypeTag => f(r.value),
        let r: RvalueLen => f(r.value),
        let r: RvalueIsType => walk_operand_places(r.operand, f),
        let r: RvalueIsTypeTag => walk_operand_places(r.operand, f),
        let r: RvalueSatisfiesBound => walk_operand_places(r.ty, f),
        let r: RvalueMakeClosure => {
            for (let cap in r.captures) {
                walk_operand_places(cap, f);
            }
        },
        let r: RvalueMakeBoundMethod => walk_operand_places(r.receiver, f),
        let r: RvalueMakeVirtualBoundMethod => walk_operand_places(r.receiver, f),
        let r: RvalueVirtualFieldAccess => walk_operand_places(r.receiver, f),
        let r: RvalueMakeVirtualFunction => {
            for (let arg in r.type_args) {
                walk_operand_places(arg, f);
            }
        },
        // No place operands: the templates are compile-time data.
        RvalueLoadType | RvalueTraceHookSettings | RvalueCurrentPackage | RvalueMakeGenericFunction => {},
        let r: RvalueMakeGenericFunctionFromValue => walk_operand_places(r.value, f),
    }
}

// port: baml_compiler2_mir/src/memory.rs::walk_rvalue_type_slots @ d9be6853b
// Walk every frame type-arg slot an rvalue reads (the `TypeArgRef` leaves
// of each template it carries), calling `f` for each. Matched exhaustively
// on purpose, like `rvalue_can_trap`: a template carried by a new variant
// must be listed here, or a rebinding between its definition and its use
// goes unseen.
function walk_rvalue_type_slots(
    rvalue: Rvalue,
    f: (int) -> void throws never,
) -> void throws never {
    match (rvalue) {
        let r: RvalueArray => root.types.ty_template_for_each_type_arg_ref(r.element_ty, f),
        let r: RvalueMap => {
            root.types.ty_template_for_each_type_arg_ref(r.key_ty, f);
            root.types.ty_template_for_each_type_arg_ref(r.value_ty, f);
        },
        let r: RvalueAggregate => {
            match (r.kind) {
                let k: AggregateKindClass => {
                    for (let template in k.type_arg_templates) {
                        root.types.ty_template_for_each_type_arg_ref(template, f);
                    }
                },
                let k: AggregateKindTuple => {
                    for (let template in k.element_templates) {
                        root.types.ty_template_for_each_type_arg_ref(template, f);
                    }
                },
                AggregateKindArray => {},
            }
        },
        let r: RvalueIsType => type_test_for_each_type_arg_ref(r.test_, f),
        let r: RvalueSatisfiesBound => {
            root.types.ty_template_interface_for_each_type_arg_ref(r.bound, f)
        },
        let r: RvalueMakeClosure => {
            for (let template in r.type_arg_templates) {
                root.types.ty_template_for_each_type_arg_ref(template, f);
            }
        },
        let r: RvalueMakeGenericFunction => {
            for (let template in r.type_arg_templates) {
                root.types.ty_template_for_each_type_arg_ref(template, f);
            }
        },
        let r: RvalueMakeGenericFunctionFromValue => {
            for (let template in r.type_arg_templates) {
                root.types.ty_template_for_each_type_arg_ref(template, f);
            }
        },
        let r: RvalueMakeVirtualBoundMethod => {
            root.types.ty_template_interface_for_each_type_arg_ref(r.iface, f);
            for (let template in r.type_args) {
                root.types.ty_template_for_each_type_arg_ref(template, f);
            }
        },
        let r: RvalueMakeVirtualFunction => {
            root.types.ty_template_for_each_type_arg_ref(r.self_ty, f);
            root.types.ty_template_interface_for_each_type_arg_ref(r.iface, f);
        },
        let r: RvalueVirtualFieldAccess => {
            root.types.ty_template_interface_for_each_type_arg_ref(r.iface, f)
        },
        let r: RvalueLoadType => root.types.ty_template_for_each_type_arg_ref(r.value, f),
        RvalueUse
            | RvalueBinaryOp
            | RvalueUnaryOp
            | RvalueConcatStrings
            | RvalueUint8Array
            | RvalueLen
            | RvalueDiscriminant
            | RvalueTypeTag
            | RvalueIsTypeTag
            | RvalueTraceHookSettings
            | RvalueCurrentPackage =>
        {},
        let r: RvalueMakeBoundMethod => {
            match (r.frame) {
                BoundFrameReceiver => {},
                let explicit: BoundFrameExplicit => {
                    for (let template in explicit.value) {
                        root.types.ty_template_for_each_type_arg_ref(template, f);
                    }
                },
            }
        },
    }
}

// port: baml_compiler2_mir/src/memory.rs::walk_statement_type_slots @ d9be6853b
// Walk every frame type-arg slot a statement reads, calling `f` for each.
function walk_statement_type_slots(
    kind: StatementKind,
    f: (int) -> void throws never,
) -> void throws never {
    match (kind) {
        let s: StatementKindAssign => walk_rvalue_type_slots(s.value, f),
        let s: StatementKindVirtualFieldStore => {
            root.types.ty_template_interface_for_each_type_arg_ref(s.iface, f)
        },
        // A `BindType` operand is a type value in a local, not a slot read.
        StatementKindDrop | StatementKindFreshCell | StatementKindIntrinsic | StatementKindNop => {},
    }
}

// port: baml_compiler2_mir/src/memory.rs::walk_terminator_type_slots @ d9be6853b
// Walk every frame type-arg slot a terminator reads, calling `f` for each.
function walk_terminator_type_slots(
    terminator: Terminator,
    f: (int) -> void throws never,
) -> void throws never {
    match (terminator) {
        let t: TerminatorNarrowBind => type_test_for_each_type_arg_ref(t.test_, f),
        let t: TerminatorVirtualCall => {
            root.types.ty_template_interface_for_each_type_arg_ref(t.iface, f)
        },
        // Call type arguments are `LoadType` temps, read where they are
        // defined. A spawned plan carries its future's types as values.
        TerminatorGoto
            | TerminatorBranch
            | TerminatorSwitch
            | TerminatorReturn
            | TerminatorCall
            | TerminatorUnreachable
            | TerminatorSysOp
            | TerminatorAwait
            | TerminatorAwaitAny
            | TerminatorSpawn
            | TerminatorThrow
            | TerminatorRethrow
            | TerminatorShortCircuit =>
        {},
    }
}

// port: baml_compiler2_mir/src/memory.rs::place_cell @ d9be6853b
// The cell a place reads or writes through, if it goes through one.
function place_cell(place: Place) -> CellId? throws never {
    match (place) {
        let d: PlaceDeref => d.value,
        let p: PlaceField => place_cell(p.base),
        let p: PlaceIndex => place_cell(p.base),
        PlaceLocal | PlaceCapture => null,
    }
}

// port: baml_compiler2_mir/src/memory.rs::rvalue_reads_cell @ d9be6853b
// Whether evaluating an rvalue reads through a cell anywhere.
function rvalue_reads_cell(rvalue: Rvalue) -> bool throws never {
    let reads = false;
    walk_rvalue_places(rvalue, (place) -> {
        reads = reads || place_cell(place) != null;
    });
    reads
}

// port: baml_compiler2_mir/src/memory.rs::spawn_shared_cells::Defs @ d9be6853b
// Where a value can have come from, indexed by what holds it. Local to
// `spawn_shared_cells` in Rust. `cell_stores` is keyed by `cell_key`.
class Defs {
    local_defs: map<int, Rvalue[]>,
    cell_stores: map<int, Rvalue[]>,
    // The argument operands of every call whose result a local holds.
    call_args: map<int, Operand[]>,
}

// port: baml_compiler2_mir/src/memory.rs::spawn_shared_cells::Walk @ d9be6853b
// Local to `spawn_shared_cells` in Rust. `followed_cells` is keyed by
// `cell_key`.
class Walk {
    pending: Rvalue[],
    followed_locals: map<int, bool>,
    followed_cells: map<int, bool>,

    // port: baml_compiler2_mir/src/memory.rs::spawn_shared_cells::Walk::follow_operand @ d9be6853b
    // Reach the closure value an operand holds: a local's single
    // definition, or the stores into the cell the operand reads through.
    function follow_operand(self, defs: Defs, operand: Operand) -> void throws never {
        let place = match (operand) {
            let c: OperandCopy => c.value,
            let m: OperandMove => m.value,
            OperandConstant => {
                return;
            },
        };
        let cell = place_cell(place);
        if (cell != null) {
            self.follow_cell(defs, cell);
            return;
        }
        let local = match (place) {
            let l: PlaceLocal => l.value,
            _ => {
                return;
            },
        };
        if (self.followed_locals.has(local)) {
            return;
        }
        self.followed_locals[local] = true;
        let local_defs = defs.local_defs.get(local);
        if (local_defs != null && local_defs.length() == 1) {
            self.pending.push(local_defs[0]);
        }
        // A call result may hold whatever the call was handed.
        for (let arg in defs.call_args.get(local) ?? []) {
            self.follow_operand(defs, arg);
        }
    }

    // port: baml_compiler2_mir/src/memory.rs::spawn_shared_cells::Walk::follow_cell @ d9be6853b
    function follow_cell(self, defs: Defs, cell: CellId) -> void throws never {
        let key = cell_key(cell);
        if (self.followed_cells.has(key)) {
            return;
        }
        self.followed_cells[key] = true;
        for (let store in defs.cell_stores.get(key) ?? []) {
            self.pending.push(store);
        }
    }
}

// port: baml_compiler2_mir/src/memory.rs::spawn_shared_cells @ d9be6853b
// The cells a body shares with the tasks it spawns: every cell a spawned
// closure captures, and every cell a closure stored in one of those cells
// captures in turn (a spawned body that calls a captured closure reaches
// that closure's cells).
//
// Computed from MIR alone. A spawned plan is followed through the calls
// that built it (`Plan.new(body)`, then each `with`/`wrap`) to every
// closure handed to them: the body and the wrappers all run on the task. A
// local is followed through its single definition, and a cell holding a
// closure through every store into it. Emit's arithmetic specialization
// declines on these cells: another task may write them at any point.
// Restructured: Rust's `HashSet<CellId>` is a `map<int, CellId>` keyed by
// `cell_key`.
function spawn_shared_cells(body: MirFunctionBody) -> map<int, CellId> throws never {
    let local_defs: map<int, Rvalue[]> = {};
    let cell_stores: map<int, Rvalue[]> = {};
    for (let block in body.blocks) {
        for (let stmt in block.statements) {
            let assign = match (stmt.kind) {
                let s: StatementKindAssign => s,
                _ => {
                    continue;
                },
            };
            match (assign.destination) {
                let l: PlaceLocal => {
                    local_defs.get_or_insert(l.value, []).push(assign.value);
                },
                let d: PlaceDeref => {
                    cell_stores.get_or_insert(cell_key(d.value), []).push(assign.value);
                },
                PlaceCapture | PlaceField | PlaceIndex => {},
            }
        }
    }

    let call_args: map<int, Operand[]> = {};
    for (let block in body.blocks) {
        match (block.terminator) {
            TerminatorCall { args: let args, destination: PlaceLocal { value: let local } }
                | TerminatorVirtualCall { args: let args, destination: PlaceLocal { value: let local } } =>
            {
                root.base.extend(call_args.get_or_insert(local, []), args);
            },
            _ => {},
        }
    }

    let defs = Defs { local_defs: local_defs, cell_stores: cell_stores, call_args: call_args };
    let walk = Walk { pending: [], followed_locals: {}, followed_cells: {} };
    for (let block in body.blocks) {
        match (block.terminator) {
            let t: TerminatorSpawn => walk.follow_operand(defs, t.plan),
            _ => {},
        }
    }

    let shared: map<int, CellId> = {};
    while let rvalue: Rvalue = walk.pending.pop() {
        match (rvalue) {
            let r: RvalueMakeClosure => {
                for (let capture in r.captures) {
                    let place = match (capture) {
                        let c: OperandCopy => c.value,
                        let m: OperandMove => m.value,
                        OperandConstant => {
                            continue;
                        },
                    };
                    let cell: CellId = match (place) {
                        let l: PlaceLocal => l,
                        let c: PlaceCapture => c,
                        _ => baml.sys.panic("a capture operand is a cell pointer"),
                    };
                    shared[cell_key(cell)] = cell_copy(cell);
                    // The closure a shared cell holds is reachable from the
                    // task.
                    walk.follow_cell(defs, cell);
                }
            },
            let r: RvalueUse => walk.follow_operand(defs, r.value),
            _ => {},
        }
    }
    shared
}

// port: baml_compiler2_mir/src/memory.rs::place_reads @ d9be6853b
// Record the resources reading a place touches.
//
// A bare local names its slot, which for a captured local holds the cell
// pointer; the value behind it is `Deref`, which names the cell and the
// slot the pointer was loaded from. A bare capture is the pointer in the
// closure's capture array, which nothing writes.
function place_reads(place: Place, out: Resources) -> void throws never {
    match (place) {
        let l: PlaceLocal => {
            out.locals[l.value] = true;
        },
        PlaceCapture => {},
        let d: PlaceDeref => {
            out.cells[cell_key(d.value)] = cell_copy(d.value);
            let local = cell_id_local(d.value);
            if (local != null) {
                out.locals[local] = true;
            }
        },
        let p: PlaceField => {
            out.fields[p.field] = true;
            place_reads(p.base, out);
        },
        let p: PlaceIndex => {
            out.elements = true;
            out.locals[p.index] = true;
            place_reads(p.base, out);
        },
    }
}

// port: baml_compiler2_mir/src/memory.rs::rvalue_reads @ d9be6853b
// The resources evaluating an rvalue reads.
//
// `type_slots` are collected only when `track_type_slots`: walking
// templates is the expensive part of this function and only matters in a
// body that rebinds a slot, and every other body would pay it for an
// answer that cannot matter.
function rvalue_reads(
    body: MirFunctionBody,
    rvalue: Rvalue,
    track_type_slots: bool,
) -> Resources throws never {
    let out = Resources.empty();
    walk_rvalue_places(rvalue, (place) -> {
        place_reads(place, out);
    });
    // Reads beyond the operands themselves. Exhaustive so a new variant that
    // reads the heap has to say so here.
    match (rvalue) {
        // A length lives with the elements: a push changes it.
        RvalueLen => {
            out.elements = true;
        },
        RvalueTraceHookSettings => {
            out.heap = true;
            out.order = true;
        },
        // Some field of the receiver, resolved at run time: any field.
        RvalueVirtualFieldAccess => {
            out.heap = true;
        },
        // The impl registry, which a runtime registration extends.
        RvalueSatisfiesBound => {
            out.heap = true;
        },
        RvalueUse
            | RvalueBinaryOp
            | RvalueUnaryOp
            | RvalueConcatStrings
            | RvalueArray
            | RvalueUint8Array
            | RvalueMap
            | RvalueAggregate
            | RvalueDiscriminant
            | RvalueTypeTag
            | RvalueIsType
            | RvalueIsTypeTag
            | RvalueMakeClosure
            | RvalueMakeBoundMethod
            | RvalueMakeVirtualBoundMethod
            | RvalueMakeVirtualFunction
            | RvalueLoadType
            | RvalueCurrentPackage
            | RvalueMakeGenericFunction
            | RvalueMakeGenericFunctionFromValue =>
        {},
    }
    if (track_type_slots) {
        walk_rvalue_type_slots(rvalue, (slot) -> {
            out.type_slots[slot] = true;
        });
    }
    if (rvalue_can_trap(body, rvalue)) {
        out.order = true;
    }
    out
}

// port: baml_compiler2_mir/src/memory.rs::place_writes @ d9be6853b
// Record the resources a store to a place writes.
function place_writes(place: Place, out: Resources) -> void throws never {
    match (place) {
        let l: PlaceLocal => {
            out.locals[l.value] = true;
        },
        PlaceCapture => baml.sys.panic("a bare capture is a pointer nothing stores to"),
        let d: PlaceDeref => {
            out.cells[cell_key(d.value)] = cell_copy(d.value);
        },
        let p: PlaceField => {
            out.fields[p.field] = true;
            out.order = true;
        },
        PlaceIndex => {
            out.elements = true;
            out.order = true;
        },
    }
}

// port: baml_compiler2_mir/src/memory.rs::statement_clobbers @ d9be6853b
// The resources a statement writes.
function statement_clobbers(
    body: MirFunctionBody,
    model: ClobberModel,
    kind: StatementKind,
) -> Resources throws never {
    let out = Resources.empty();
    match (kind) {
        let s: StatementKindAssign => {
            place_writes(s.destination, out);
            if (model.registers_observed && out.locals.length() != 0) {
                out.order = true;
            }
            // The evaluation may trap, and the trap is an event.
            if (s.value is RvalueTraceHookSettings) {
                out.heap = true;
                out.order = true;
            } else if (rvalue_can_trap(body, s.value)) {
                out.order = true;
            }
        },
        // A destructor runs arbitrary code.
        StatementKindDrop => {
            out.heap = true;
            out.order = true;
        },
        // The slot now points at a different cell: both change.
        let s: StatementKindFreshCell => {
            out.locals[s.local] = true;
            let cell = PlaceLocal { value: s.local };
            out.cells[cell_key(cell)] = cell;
        },
        let s: StatementKindIntrinsic => {
            match (s.op) {
                IntrinsicOpLog => {
                    out.order = true;
                },
                IntrinsicOpApplyTraceHook | IntrinsicOpBuiltinTraceHook => {
                    out.order = true;
                    out.heap = true;
                },
                let bind: IntrinsicOpBindType => {
                    out.type_slots[bind.value] = true;
                },
            }
        },
        // Some field of the receiver, resolved at run time: any field.
        StatementKindVirtualFieldStore => {
            out.heap = true;
            out.order = true;
        },
        StatementKindNop => {},
    }
    out
}

// port: baml_compiler2_mir/src/memory.rs::terminator_clobbers @ d9be6853b
// The resources a terminator writes.
//
// A call, await, spawn, or sys-op runs code this frame cannot see (a
// closure holding one of its cells, another task, a host operation), so it
// writes every heap location; a throw is an event.
function terminator_clobbers(
    model: ClobberModel,
    terminator: Terminator,
) -> Resources throws never {
    let out = Resources.empty();
    match (terminator) {
        TerminatorGoto
            | TerminatorBranch
            | TerminatorSwitch
            | TerminatorReturn
            | TerminatorUnreachable =>
        {},
        let t: TerminatorNarrowBind => {
            out.locals[t.destination] = true;
        },
        let t: TerminatorShortCircuit => place_writes(t.destination, out),
        TerminatorCall { destination: let destination }
            | TerminatorVirtualCall { destination: let destination }
            | TerminatorSysOp { destination: let destination }
            | TerminatorAwait { destination: let destination }
            | TerminatorAwaitAny { destination: let destination } =>
        {
            place_writes(destination, out);
            out.heap = true;
            out.order = true;
        },
        let t: TerminatorSpawn => {
            place_writes(t.future, out);
            out.heap = true;
            out.order = true;
        },
        TerminatorThrow | TerminatorRethrow => {
            out.order = true;
        },
    }
    if (model.registers_observed && out.locals.length() != 0) {
        out.order = true;
    }
    out
}

// port: baml_compiler2_mir/src/memory.rs::block_entry_clobbers @ d9be6853b
// The resources the VM writes when control enters `block`: a catch handler
// receives its error and context bindings with no statement saying so.
function block_entry_clobbers(body: MirFunctionBody, block: int) -> Resources throws never {
    let out = Resources.empty();
    let landing = body.blocks[block].landing;
    if (landing != null) {
        out.locals[landing.error_local] = true;
        out.locals[landing.context_local] = true;
    }
    out
}

// port: baml_compiler2_mir/src/memory.rs::rvalue_allocates_identity @ d9be6853b
// Whether evaluating this rvalue allocates a fresh object whose identity is
// observable (mutable containers, class instances, and callable objects),
// so evaluating it more times than the program does is itself observable.
// Matched exhaustively on purpose: a wrong `false` silently miscompiles.
function rvalue_allocates_identity(rvalue: Rvalue) -> bool throws never {
    match (rvalue) {
        RvalueMap
            | RvalueArray
            | RvalueUint8Array
            | RvalueAggregate
            | RvalueMakeClosure
            | RvalueMakeBoundMethod
            | RvalueMakeVirtualBoundMethod
            | RvalueMakeVirtualFunction
            | RvalueTraceHookSettings =>
        {
            true
        },
        // A string has no identity: two joins of the same parts are equal.
        RvalueUse
            | RvalueBinaryOp
            | RvalueUnaryOp
            | RvalueConcatStrings
            | RvalueDiscriminant
            | RvalueTypeTag
            | RvalueLen
            | RvalueIsType
            | RvalueIsTypeTag
            | RvalueSatisfiesBound
            | RvalueVirtualFieldAccess
            | RvalueMakeGenericFunction
            | RvalueMakeGenericFunctionFromValue
            | RvalueLoadType
            | RvalueCurrentPackage =>
        {
            false
        },
    }
}

// port: baml_compiler2_mir/src/memory.rs::rvalue_can_trap @ d9be6853b
// Can evaluating this rvalue raise a catchable panic (`baml.panics.*`)?
//
// A trap is an observable event: moving an evaluation that can trap past a
// store, a call, or a handler boundary changes which effects run before the
// trap and which handler receives it. Only arithmetic can fail, and only `/`
// fails for every operand type. The rest are `int`-only failures (`float`
// saturates to infinity or NaN, `bigint` grows, and `string + string` is
// concatenation), so they ask `operand_could_be_int`. Bitwise and/or/xor and
// the comparisons stay in range whatever the operands are.
//
// Matched exhaustively on purpose. This is a soundness predicate, and a
// wrong `false` miscompiles silently, so a new `Rvalue` variant must fail to
// compile here rather than default into the infallible group.
function rvalue_can_trap(body: MirFunctionBody, rvalue: Rvalue) -> bool throws never {
    match (rvalue) {
        // Treat this state transition as an ordering event even when the
        // selected hook needs no allocating snapshot.
        RvalueTraceHookSettings => true,
        let r: RvalueBinaryOp => {
            match (r.op) {
                // `/` rejects a zero divisor on both numeric paths (BAML
                // throws rather than yielding IEEE infinity,
                // `OpCode::DivFloat`), so this holds whatever the operands
                // are.
                BinOp.Div => true,
                // `%` is guarded on the `int` path only; the float path
                // yields NaN.
                BinOp.Mod | BinOp.Add | BinOp.Sub | BinOp.Mul | BinOp.Shl | BinOp.Shr => {
                    operand_could_be_int(body, r.left) && operand_could_be_int(body, r.right)
                },
                BinOp.Eq
                    | BinOp.Ne
                    | BinOp.Lt
                    | BinOp.Le
                    | BinOp.Gt
                    | BinOp.Ge
                    | BinOp.BitAnd
                    | BinOp.BitOr
                    | BinOp.BitXor =>
                {
                    false
                },
            }
        },
        let r: RvalueUnaryOp => {
            match (r.op) {
                UnaryOp.Neg => operand_could_be_int(body, r.operand),
                UnaryOp.Not | UnaryOp.Truthy => false,
            }
        },
        // Reading through an index projection can raise `IndexOutOfBounds`.
        let r: RvalueUse => {
            match (r.value) {
                let c: OperandCopy => place_indexes(c.value),
                let m: OperandMove => place_indexes(m.value),
                OperandConstant => false,
            }
        },
        // Allocation can report `AllocFailure`, but that is a host resource
        // condition rather than a property of the program point, and
        // treating every allocation as a barrier would disable
        // virtualization outright. Joining strings is concatenation, never
        // arithmetic.
        RvalueArray
            | RvalueConcatStrings
            | RvalueUint8Array
            | RvalueMap
            | RvalueAggregate
            | RvalueDiscriminant
            | RvalueTypeTag
            | RvalueLen
            | RvalueIsType
            | RvalueIsTypeTag
            | RvalueSatisfiesBound
            | RvalueMakeClosure
            | RvalueMakeBoundMethod
            | RvalueMakeVirtualBoundMethod
            | RvalueVirtualFieldAccess
            | RvalueMakeGenericFunction
            | RvalueMakeGenericFunctionFromValue
            | RvalueMakeVirtualFunction
            | RvalueLoadType
            | RvalueCurrentPackage =>
        {
            false
        },
    }
}

// port: baml_compiler2_mir/src/memory.rs::place_indexes @ d9be6853b
// Whether a place goes through an index projection anywhere in its chain.
function place_indexes(place: Place) -> bool throws never {
    match (place) {
        PlaceLocal | PlaceCapture | PlaceDeref => false,
        PlaceIndex => true,
        let p: PlaceField => place_indexes(p.base),
    }
}

// port: baml_compiler2_mir/src/memory.rs::operand_could_be_int @ d9be6853b
// Could this operand hold an `int` at runtime?
//
// Deliberately answers `true` for anything whose runtime representation is
// not pinned down (a union, a type variable, a value read through a
// projection, a type family variant added later). Only a type that provably
// never holds an `int` answers `false`.
function operand_could_be_int(body: MirFunctionBody, operand: Operand) -> bool throws never {
    let place = match (operand) {
        let c: OperandConstant => {
            return c.value is ConstantInt;
        },
        let c: OperandCopy => c.value,
        let m: OperandMove => m.value,
    };
    match (place) {
        let l: PlaceLocal => ty_could_be_int(body.local(l.value).ty),
        // A captured local's declared type is the type of the value in its
        // cell.
        let d: PlaceDeref => {
            match (d.value) {
                let l: PlaceLocal => ty_could_be_int(body.local(l.value).ty),
                PlaceCapture => true,
            }
        },
        // A field / index / capture read carries no type here.
        PlaceField | PlaceIndex | PlaceCapture => true,
    }
}

// port: baml_compiler2_mir/src/memory.rs::ty_could_be_int @ d9be6853b
// See `operand_could_be_int`. The `_ => true` fallback keeps an unlisted or
// newly added variant on the conservative side.
function ty_could_be_int(ty: root.types.RuntimeTy) -> bool throws never {
    match (ty) {
        root.types.TyInt => true,
        let l: root.types.TyLiteral => l.value is root.base.LiteralInt,
        root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyMedia
            | root.types.RuntimeTyClass
            | root.types.TyEnum
            | root.types.TyEnumVariant
            | root.types.RuntimeTyList
            | root.types.RuntimeTyMap
            | root.types.RuntimeTyFunction
            | root.types.RuntimeTyFuture
            | root.types.TyRustType
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst =>
        {
            false
        },
        _ => true,
    }
}
