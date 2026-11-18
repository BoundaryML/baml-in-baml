// port: baml_compiler2_mir/src/optimize/values.rs::tests @ d9be6853b
//
// Rust's `i64::MAX + 1` overflow case is not ported: a BAML `int` cannot
// hold `i64::MAX` (Int63's `MAX + 1` is the same check). `f64::MAX` is its
// literal, infinity `1.0 / 0.0` and NaN `0.0 / 0.0`.

// port: baml_compiler2_mir/src/optimize/values.rs::tests::binary @ d9be6853b
function binary(
    op: root.mir.BinOp,
    left: root.mir.Constant,
    right: root.mir.Constant,
) -> root.mir.Rvalue {
    root.mir.RvalueBinaryOp {
        op: op,
        left: root.mir.OperandConstant { value: left },
        right: root.mir.OperandConstant { value: right },
    }
}

// An int constant.
function int_constant(value: int) -> root.mir.Constant {
    root.mir.ConstantInt { value: value }
}

// A float constant.
function float_constant(value: float) -> root.mir.Constant {
    root.mir.ConstantFloat { value: value }
}

test "integer folding preserves overflow and zero divisor panics" {
    let min = root.types.INT63_MIN;
    let max = root.types.INT63_MAX;
    let rejected: (root.mir.BinOp, int, int)[] = [
        (root.mir.BinOp.Div, 1, 0),
        (root.mir.BinOp.Mod, 1, 0),
        (root.mir.BinOp.Add, max, 1),
        (root.mir.BinOp.Sub, min, 1),
        (root.mir.BinOp.Mul, max, 2),
        (root.mir.BinOp.Div, min, -1),
    ];
    for (let case in rejected) {
        assert.equal(fold(binary(case.0, int_constant(case.1), int_constant(case.2))), null);
    }
    assert.equal(
        fold(
            root.mir.RvalueUnaryOp {
                op: root.mir.UnaryOp.Neg,
                operand: root.mir.OperandConstant { value: int_constant(min) },
            },
        ),
        null,
    );
    let folded: (root.mir.BinOp, int)[] = [
        (root.mir.BinOp.Add, 8),
        (root.mir.BinOp.Sub, 4),
        (root.mir.BinOp.Mul, 12),
        (root.mir.BinOp.Div, 3),
        (root.mir.BinOp.Mod, 0),
        (root.mir.BinOp.BitAnd, 2),
        (root.mir.BinOp.BitOr, 6),
        (root.mir.BinOp.BitXor, 4),
        (root.mir.BinOp.Shl, 24),
        (root.mir.BinOp.Shr, 1),
    ];
    for (let case in folded) {
        assert.equal(fold(binary(case.0, int_constant(6), int_constant(2))), int_constant(case.1));
    }
}

test "float folding rejects zero division and nonfinite values" {
    let infinity = 1.0 / 0.0;
    let nan = 0.0 / 0.0;
    let rejected: (root.mir.BinOp, float, float)[] = [
        (root.mir.BinOp.Div, 1.0, 0.0),
        (root.mir.BinOp.Div, 1.0, -0.0),
        (root.mir.BinOp.Mul, 1.7976931348623157e308, 2.0),
        (root.mir.BinOp.Add, infinity, 1.0),
        (root.mir.BinOp.Add, nan, 1.0),
    ];
    for (let case in rejected) {
        assert.equal(fold(binary(case.0, float_constant(case.1), float_constant(case.2))), null);
    }
    let folded: (root.mir.BinOp, float)[] = [
        (root.mir.BinOp.Add, 8.0),
        (root.mir.BinOp.Sub, 4.0),
        (root.mir.BinOp.Mul, 12.0),
        (root.mir.BinOp.Div, 3.0),
    ];
    for (let case in folded) {
        assert.equal(
            fold(binary(case.0, float_constant(6.0), float_constant(2.0))),
            float_constant(case.1),
        );
    }
}

test "string folding obeys the allocation limit" {
    let joined = fold(
        binary(
            root.mir.BinOp.Add,
            root.mir.ConstantString { value: "a".repeat(4095) },
            root.mir.ConstantString { value: "b" },
        ),
    );
    match (joined) {
        let s: root.mir.ConstantString => {
            assert.equal(s.value.byte_length(), 4096);
            assert.is_true(s.value.ends_with("b"));
        },
        _ => assert.is_true(false),
    }
    assert.equal(
        fold(
            binary(
                root.mir.BinOp.Add,
                root.mir.ConstantString { value: "a".repeat(4096) },
                root.mir.ConstantString { value: "b" },
            ),
        ),
        null,
    );
}

// Rust's `original.clone()`: each run starts from its own body.
function dead_store_body() -> root.mir.MirFunctionBody {
    let block = root.mir.BasicBlock.new(0);
    for (let def in [(1, 1), (2, 1), (1, 2), (2, 2)]) {
        block.statements.push(
            root.mir.Statement {
                kind: root.mir.StatementKindAssign {
                    destination: root.mir.PlaceLocal { value: def.0 },
                    value: root.mir.RvalueUse {
                        value: root.mir.OperandConstant { value: int_constant(def.1) },
                    },
                },
                span: null,
            },
        );
    }
    block.statements.push(
        root.mir.Statement {
            kind: root.mir.StatementKindAssign {
                destination: root.mir.PlaceLocal { value: 0 },
                value: root.mir.RvalueBinaryOp {
                    op: root.mir.BinOp.Add,
                    left: root.mir.operand_copy_local(1),
                    right: root.mir.operand_copy_local(2),
                },
            },
            span: null,
        },
    );
    block.terminator = root.mir.TerminatorReturn {};
    let names: (string?)[] = [null, "named", null];
    root.mir.MirFunctionBody {
        blocks: [block],
        entry: 0,
        locals: names.map((name) -> {
            root.mir.LocalDecl {
                name: name,
                ty: root.types.TyInt {},
                span: null,
                scope_span: null,
                is_captured: false,
            }
        }),
    }
}

test "dead stores preserve named definitions at o0 but optimize temporaries" {
    for (let opt in [root.mir.OptLevel.Zero, root.mir.OptLevel.One, root.mir.OptLevel.Two]) {
        let body = dead_store_body();
        eliminate_dead_stores(body, 0, opt);
        let defs = root.mir.count_local_defs(body);
        assert.equal(
            defs[1],
            if (opt == root.mir.OptLevel.Zero) {
                2
            } else {
                1
            },
        );
        assert.equal(defs[2], 1);
        if (opt == root.mir.OptLevel.Zero) {
            root.mir.optimize_body(body, 0, opt);
            let named = body.locals.find_index((local) -> {
                local.name != null
            })
                ?? baml.sys.panic("a named local survives");
            assert.equal(root.mir.count_local_defs(body)[named], 2);
        }
    }
}
