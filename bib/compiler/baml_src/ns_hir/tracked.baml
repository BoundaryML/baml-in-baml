// port: salsa 0.28 (the version baml_language pins) cycle handling, as far
// as the type checker's queries use it: `#[salsa::tracked]` queries that may
// be re-entered while they run.
//
// A query already on the stack that is called again is a cycle head:
//   - `cycle_initial` (fixpoint): the re-entered call returns the head's last
//     provisional value (the initial value on the first iteration); the head
//     re-runs until its result equals that value (salsa: values_equal), at
//     most MAX_CYCLE_ITERATIONS times.
//   - `cycle_result` (fallback): the re-entered call returns the fallback,
//     and every query in the cycle takes the fallback as its result.
//   - neither: a cycle is a bug, as in salsa (panic).
// A query that read a provisional value of a head still running (a cycle
// participant) is cached only for that head's current iteration; it becomes
// final when the head converges in that iteration, and is recomputed if the
// head iterates again.
//
// HIR queries never take part in a cycle and keep the plain `Memo`.

// port: salsa cycle.rs::MAX_ITERATIONS
const MAX_CYCLE_ITERATIONS = 200;

// One tracked query execution in flight.
class ActiveQuery {
    // "<memo name>:<key>"
    id: string,
    // The stack index of the outermost cycle head whose provisional value this
    // execution read, directly or through a callee; -1 if none.
    lowest_head: int,
    // Whether this execution was re-entered: it heads a cycle.
    is_head: bool,
}

// A cycle head's iteration count, and whether it has converged.
class CycleHead {
    iteration: int,
    converged: bool,
}

// The tracked-query stack of one compile, shared by every `TrackedMemo`.
class Cycles {
    stack: ActiveQuery[],
    heads: map<string, CycleHead>,

    function new() -> Cycles throws never {
        Cycles { stack: [], heads: {} }
    }

    // The running execution read the provisional value of the head at
    // stack index `head`.
    function read_provisional(self, head: int) -> void throws never {
        let top = self.stack[self.stack.length() - 1];
        if (top.lowest_head < 0 || head < top.lowest_head) {
            top.lowest_head = head;
        }
    }

    function index_of(self, id: string) -> int throws never {
        self.stack.find_index((q) -> { q.id == id }) ?? -1
    }
}

// How a tracked query recovers from a cycle through it.
type CycleRecovery = "panic" | "fixpoint" | "fallback"

// A participant's value, good for one iteration of the head it depends on.
class Provisional<V> {
    value: V,
    head: string,
    iteration: int,
}

// The cache of one tracked query, keyed like `Memo`.
class TrackedMemo<V> {
    name: string,
    values: map<int, V>,
    // Keys executing now, with their stack index.
    active: map<int, int>,
    // A cycle head's value from its last iteration.
    last_iteration: map<int, V>,
    participants: map<int, Provisional<V>>,

    function new(name: string) -> TrackedMemo<V> throws never {
        TrackedMemo { name: name, values: {}, active: {}, last_iteration: {}, participants: {} }
    }

    // A query that cannot recover from a cycle (salsa's default).
    function get(self, cycles: Cycles, key: int, compute: () -> V throws never) -> V throws never {
        self.run(cycles, key, "panic", () -> { baml.sys.panic(`cycle through ${self.name}`) }, compute)
    }

    // `cycle_initial = initial`.
    function get_fixpoint(
        self,
        cycles: Cycles,
        key: int,
        initial: () -> V throws never,
        compute: () -> V throws never,
    ) -> V throws never {
        self.run(cycles, key, "fixpoint", initial, compute)
    }

    // `cycle_result = fallback`.
    function get_fallback(
        self,
        cycles: Cycles,
        key: int,
        fallback: () -> V throws never,
        compute: () -> V throws never,
    ) -> V throws never {
        self.run(cycles, key, "fallback", fallback, compute)
    }

    function run(
        self,
        cycles: Cycles,
        key: int,
        recovery: CycleRecovery,
        initial: () -> V throws never,
        compute: () -> V throws never,
    ) -> V throws never {
        if (self.values.has(key)) {
            return self.values[key];
        }
        let id = `${self.name}:${key}`;
        // Re-entered while running: this query is a cycle head.
        let running = self.active.get(key);
        if (running != null) {
            if (recovery == "panic") {
                baml.sys.panic(`cycle through ${id}`);
            }
            if (!cycles.heads.has(id)) {
                cycles.heads[id] = CycleHead { iteration: 0, converged: false };
            }
            cycles.stack[running].is_head = true;
            cycles.read_provisional(running);
            return self.last_iteration.get(key) ?? initial();
        }
        // Computed in an earlier pass of a cycle this query took part in.
        let earlier = self.participants.get(key);
        if (earlier != null) {
            let head = cycles.heads.get(earlier.head);
            if (head != null && head.iteration == earlier.iteration) {
                if (head.converged) {
                    self.values[key] = earlier.value;
                    self.participants.delete(key);
                    return earlier.value;
                }
                let at = cycles.index_of(earlier.head);
                if (at >= 0) {
                    cycles.read_provisional(at);
                    return earlier.value;
                }
            }
            self.participants.delete(key);
        }
        while (true) {
            let index = cycles.stack.length();
            let frame = ActiveQuery { id: id, lowest_head: -1, is_head: false };
            cycles.stack.push(frame);
            self.active[key] = index;
            let computed = compute();
            cycles.stack.pop();
            self.active.delete(key);
            let value = if (recovery == "fallback" && frame.lowest_head >= 0) { initial() } else { computed };

            if (frame.is_head) {
                // Iterate this cycle to its fixpoint (with any outer head's
                // provisional value held fixed).
                let head = cycles.heads[id];
                let last = self.last_iteration.get(key) ?? initial();
                if (recovery == "fixpoint" && value != last) {
                    head.iteration += 1;
                    if (head.iteration > MAX_CYCLE_ITERATIONS) {
                        baml.sys.panic(`${id} did not converge in ${MAX_CYCLE_ITERATIONS} iterations`);
                    }
                    self.last_iteration[key] = value;
                    continue;
                }
                self.last_iteration.delete(key);
            }

            if (frame.lowest_head >= 0 && frame.lowest_head < index) {
                // A participant of a cycle whose head is still running.
                let head_id = cycles.stack[frame.lowest_head].id;
                let iteration = cycles.heads.get(head_id)?.iteration ?? 0;
                self.participants[key] = Provisional { value: value, head: head_id, iteration: iteration };
                cycles.read_provisional(frame.lowest_head);
                // A head nested in the outer cycle iterates afresh next time.
                cycles.heads.delete(id);
                return value;
            }
            if (frame.is_head) {
                cycles.heads[id].converged = true;
            }
            self.values[key] = value;
            return value;
        }
    }
}
