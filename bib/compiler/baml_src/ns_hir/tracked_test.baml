// Fixpoint and fallback recovery of tracked queries, on a small graph: what
// each node reaches, where edges form cycles.

class ReachGraph {
    edges: map<int, int[]>,
    memo: TrackedMemo<int[]>,
    cycles: Cycles,
    // How many times each node's query body ran.
    runs: map<int, int>,

    // The sorted set of nodes reachable from `node` (itself included): a
    // fixpoint over cycles, seeded with the empty set as `callable_throws`
    // is seeded with `never`.
    function reach(self, node: int) -> int[] throws never {
        self.memo.get_fixpoint(self.cycles, node, () -> { [] }, () -> {
            self.runs[node] = (self.runs.get(node) ?? 0) + 1;
            let seen: int[] = [node];
            for (let next in self.edges.get(node) ?? []) {
                for (let n in self.reach(next)) {
                    if (!seen.includes(n)) {
                        seen.push(n);
                    }
                }
            }
            seen.sort();
            seen
        })
    }

    function fallback_reach(self, node: int) -> int[] throws never {
        self.memo.get_fallback(self.cycles, node, () -> { [-1] }, () -> {
            let seen: int[] = [node];
            for (let next in self.edges.get(node) ?? []) {
                seen = seen.concat(self.fallback_reach(next));
            }
            seen
        })
    }
}

function reach_graph(edges: map<int, int[]>) -> ReachGraph throws never {
    ReachGraph { edges: edges, memo: TrackedMemo.new("reach"), cycles: Cycles.new(), runs: {} }
}

test "a fixpoint query converges through a cycle" {
    let g = reach_graph({ 1: [2], 2: [3], 3: [1, 4] });
    assert.equal(g.reach(1), [1, 2, 3, 4]);
    assert.equal(g.reach(2), [1, 2, 3, 4]);
    assert.equal(g.reach(3), [1, 2, 3, 4]);
    assert.equal(g.reach(4), [4]);
}

test "participants of a converged cycle are final" {
    let g = reach_graph({ 1: [2], 2: [1] });
    assert.equal(g.reach(1), [1, 2]);
    let runs = g.runs[2];
    assert.equal(g.reach(2), [1, 2]);
    assert.equal(g.runs[2], runs);
}

test "nested cycles converge" {
    let g = reach_graph({ 1: [2], 2: [3, 1], 3: [2, 5], 5: [] });
    assert.equal(g.reach(1), [1, 2, 3, 5]);
    assert.equal(g.reach(3), [1, 2, 3, 5]);
}

test "a fallback query takes the fallback through a cycle" {
    let g = reach_graph({ 1: [2], 2: [1], 3: [4], 4: [] });
    assert.equal(g.fallback_reach(1), [-1]);
    assert.equal(g.fallback_reach(3), [3, 4]);
}
