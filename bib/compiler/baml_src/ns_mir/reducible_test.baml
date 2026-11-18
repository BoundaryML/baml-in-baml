// port: baml_compiler2_mir/src/reducible.rs::tests @ d9be6853b
//
// `Ok(())` is `null`; `Err(blocks)` is the residue array.

test "straight line and diamond are reducible" {
    assert.equal(check_graph(0, [[1], [2], []]), null);
    assert.equal(check_graph(0, [[1, 2], [3], [3], []]), null);
}

test "natural loops are reducible" {
    // 0 -> 1 (header) -> 2 -> 1, 1 -> 3
    assert.equal(check_graph(0, [[1], [2, 3], [1], []]), null);
    // Self-loop.
    assert.equal(check_graph(0, [[1], [1, 2], []]), null);
    // Nested loops with a break out of both and a continue of the outer.
    // 0 -> 1 (outer) -> 2 (inner) -> 3 -> {2, 1, 4}; 2 -> 1; 1 -> 4
    assert.equal(check_graph(0, [[1], [2, 4], [3, 1], [2, 1, 4], []]), null);
}

test "two entry loop is irreducible" {
    // The classic: 0 enters the 1 <-> 2 cycle at both nodes.
    assert.equal(check_graph(0, [[1, 2], [2], [1]]), [1, 2]);
}

test "jump into loop body is irreducible" {
    // Loop 1 -> 2 -> 1, but 0 also jumps straight to 2.
    assert.not_null(check_graph(0, [[1, 2], [2, 3], [1], []]));
}

test "unreachable irreducible part is ignored" {
    // 3 and 4 form a two-entry cycle with 5, but nothing reaches them.
    assert.equal(check_graph(0, [[1], [], [], [4, 5], [5], [4]]), null);
}
