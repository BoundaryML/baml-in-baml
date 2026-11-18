// port: baml_compiler2_mir/src/optimize/effects.rs::tests @ d9be6853b
//
// Rust's `i128` reference arithmetic is `bigint`; `checked_div` /
// `checked_rem` by zero (`None`) fails the test as Rust's `expect` does.

test "arithmetic proofs cover extremes and interior values" {
    let min = root.types.INT63_MIN;
    let max = root.types.INT63_MAX;
    let values = [min, min + 1, -3, -1, 0, 1, 3, max - 1, max];
    let ops = [
        root.mir.BinOp.Add,
        root.mir.BinOp.Sub,
        root.mir.BinOp.Mul,
        root.mir.BinOp.Div,
        root.mir.BinOp.Mod,
    ];
    for (let lo in values) {
        for (
            let hi in values.filter((n) -> {
                n >= lo
            })
        ) {
            for (let rhs_lo in values) {
                for (
                    let rhs_hi in values.filter((n) -> {
                        n >= rhs_lo
                    })
                ) {
                    for (let op in ops) {
                        let proof = Range { lo: lo, hi: hi }.arithmetic(op, Range { lo: rhs_lo, hi: rhs_hi });
                        if (proof == null) {
                            continue;
                        }
                        for (
                            let a in values.filter((n) -> {
                                lo <= n && n <= hi
                            })
                        ) {
                            for (
                                let b in values.filter((n) -> {
                                    rhs_lo <= n && n <= rhs_hi
                                })
                            ) {
                                let x = 0n + a;
                                let y = 0n + b;
                                if ((op == root.mir.BinOp.Div || op == root.mir.BinOp.Mod) && b == 0) {
                                    baml.sys.panic("proven arithmetic must not divide by zero");
                                }
                                let result = match (op) {
                                    root.mir.BinOp.Add => x + y,
                                    root.mir.BinOp.Sub => x - y,
                                    root.mir.BinOp.Mul => x * y,
                                    root.mir.BinOp.Div => x / y,
                                    root.mir.BinOp.Mod => x % y,
                                };
                                assert.is_true(0n + proof.lo <= result && result <= 0n + proof.hi);
                            }
                        }
                    }
                }
            }
        }
    }
}

test "joins widen only growing bounds and forget disagreeing aliases" {
    let local = 1;
    let facts = Facts.default();
    facts.integers.set(local, Range.exact(0));
    facts.aliases.set(2, local);
    let incoming = Facts.default();
    incoming.integers.set(local, Range { lo: 0, hi: 1 });
    incoming.aliases.set(2, 3);
    assert.is_true(facts.merge(incoming, true));
    assert.equal(facts.integers[local], Range { lo: 0, hi: root.types.INT63_MAX });
    assert.equal(facts.aliases.length(), 0);
    assert.is_true(!facts.merge(incoming, true));
}
