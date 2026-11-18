// port: baml_compiler2_mir/src/reducible.rs @ d9be6853b
//
// Exact reducibility test for a MIR body.
//
// Reducible means every loop has one way in: its header dominates every block
// of the loop. Structured control flow (`while`, `for`, `break`, `continue`)
// produces only such loops, and the Rust backend's structurer depends on it.
// Lowering alone never makes an irreducible graph, but optimization rewrites
// the CFG afterwards, so the verifier tests its output here.
//
// Compute dominators, delete every edge `u -> v` where `v` dominates `u`,
// and check that what remains is acyclic. A CFG is reducible exactly when
// this holds (Hecht & Ullman 1974), so the test has no false alarms. Edges
// are terminator successors plus each block's implicit edge to its `unwind`
// handler; only blocks reachable from the entry count.
//
// Restructured: Rust's `Result<(), Vec<_>>` is `int[]?` (null is `Ok`), and
// `usize::MAX` (an unreachable block's dominator and order) is
// `root.types.INT63_MAX`.

// port: baml_compiler2_mir/src/reducible.rs::check @ d9be6853b
// Check that `body`'s CFG is reducible. On failure, returns the blocks left
// once every acyclic part is peeled away: a cycle with more than one entry,
// and what only it reaches.
function check(body: MirFunctionBody) -> int[]? throws never {
    let succs = body.blocks.map((block) -> {
        let out: int[] = [];
        let term = block.terminator;
        if (term != null) {
            root.base.extend(out, terminator_successors(term));
        }
        root.base.push_some(out, block.unwind);
        out
    });
    check_graph(body.entry, succs)
}

// port: baml_compiler2_mir/src/reducible.rs::check_graph @ d9be6853b
// The reducibility test over plain successor lists.
function check_graph(entry: int, succs: int[][]) -> int[]? throws never {
    let rpo = reverse_postorder(entry, succs);
    let idom = immediate_dominators(entry, succs, rpo);
    let dominates = (a: int, b: int) -> bool {
        let node = b;
        while (true) {
            if (a == node) {
                return true;
            }
            if (node == entry) {
                return false;
            }
            node = idom[node];
        }
    };
    // Delete the dominator back edges; what remains must be acyclic.
    let forward: int[][] = baml.Array.generate(succs.length(), (_) -> {
        let edges: int[] = [];
        edges
    });
    for (let u in rpo) {
        root.base.extend(
            forward[u],
            succs[u].filter((v) -> {
                !dominates(v, u)
            }),
        );
    }
    let stuck = cycle_residue(rpo, forward);
    if (stuck.length() == 0) {
        return null;
    }
    stuck
}

// port: baml_compiler2_mir/src/reducible.rs::cycle_residue @ d9be6853b
// Peel the acyclic part off `forward` (Kahn's algorithm over the blocks in
// `rpo`); what is left lies on or behind a cycle.
function cycle_residue(rpo: int[], forward: int[][]) -> int[] throws never {
    let indegree = baml.Array.filled(forward.length(), 0);
    for (let u in rpo) {
        for (let v in forward[u]) {
            indegree[v] += 1;
        }
    }
    let ready = rpo.filter((b) -> {
        indegree[b] == 0
    });
    while let u: int = ready.pop() {
        for (let v in forward[u]) {
            indegree[v] -= 1;
            if (indegree[v] == 0) {
                ready.push(v);
            }
        }
    }
    rpo.filter((b) -> {
        indegree[b] > 0
    })
}

// port: baml_compiler2_mir/src/reducible.rs::reverse_postorder @ d9be6853b
// The blocks reachable from `entry`, in reverse postorder. Restructured: the
// stack of `(node, next successor)` pairs is two parallel arrays, since the
// top pair's counter is bumped in place.
function reverse_postorder(entry: int, succs: int[][]) -> int[] throws never {
    let postorder: int[] = [];
    let visited = baml.Array.filled(succs.length(), false);
    let nodes = [entry];
    let nexts = [0];
    visited[entry] = true;
    while (nodes.length() > 0) {
        let top = nodes.length() - 1;
        let node = nodes[top];
        let next = nexts[top];
        let succ = succs[node].at(next);
        if (succ == null) {
            postorder.push(node);
            nodes.pop();
            nexts.pop();
            continue;
        }
        nexts[top] = next + 1;
        if (!visited[succ]) {
            visited[succ] = true;
            nodes.push(succ);
            nexts.push(0);
        }
    }
    postorder.reverse()
}

// port: baml_compiler2_mir/src/reducible.rs::immediate_dominators @ d9be6853b
// Immediate dominators indexed by block (Cooper, Harvey & Kennedy, "A
// Simple, Fast Dominance Algorithm"). The entry is its own dominator;
// unreachable blocks keep `usize::MAX` (`root.types.INT63_MAX`).
function immediate_dominators(entry: int, succs: int[][], rpo: int[]) -> int[] throws never {
    let unset = root.types.INT63_MAX;
    let n = succs.length();
    let order = baml.Array.filled(n, unset);
    for (let i = 0; i < rpo.length(); i += 1) {
        order[rpo[i]] = i;
    }
    let preds: int[][] = baml.Array.generate(n, (_) -> {
        let edges: int[] = [];
        edges
    });
    for (let u in rpo) {
        for (let v in succs[u]) {
            preds[v].push(u);
        }
    }

    let idom = baml.Array.filled(n, unset);
    idom[entry] = entry;
    let intersect = (a: int, b: int) -> int {
        let x = a;
        let y = b;
        while (x != y) {
            while (order[x] > order[y]) {
                x = idom[x];
            }
            while (order[y] > order[x]) {
                y = idom[y];
            }
        }
        x
    };
    let changed = true;
    while (changed) {
        changed = false;
        for (let node in rpo.slice(1, rpo.length())) {
            let new_idom: int? = null;
            for (let p in preds[node]) {
                if (idom[p] == unset) {
                    continue;
                }
                new_idom
                    = if (new_idom == null) {
                        p
                    } else {
                        intersect(new_idom, p)
                    };
            }
            let found = new_idom ?? baml.sys.panic("a reachable block has a processed predecessor");
            if (idom[node] != found) {
                idom[node] = found;
                changed = true;
            }
        }
    }
    idom
}
