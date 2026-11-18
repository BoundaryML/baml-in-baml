// Pins pretty.baml's output byte for byte against the Rust printer: a MIR
// body built by hand as Rust lowers `SingleCatchWildcard` at O2, printed and
// compared with its block of baml_tests' corpus snapshot
// (`snapshots/baml_src/ns_fixtures/ns_catch_throw/mir.snap`).

const PRETTY_TEST_SOURCE: string = `
    function MayFail(x: int) -> string {
        match (x) {
            0 => throw "string error",
            _ => "ok"
        }
    }

    function SingleCatchWildcard(x: int) -> string {
        MayFail(x) catch (e) {
            _ => "caught"
        }
    }
`;

// The expected text, one line each (a trailing newline after the last).
const PRETTY_TEST_EXPECTED_LINES: string[] = [
    "fn user.fixtures.catch_throw.SingleCatchWildcard(x: int) -> string {",
    "    // Locals:",
    "    let _0: string // _0 // return",
    "    let _1: int // x // param",
    "    let _2: unknown // e",
    "    let _3: unknown",
    "    let _4: bool",
    "",
    "    bb0 [unwind bb1]: {",
    "        _0 = call const fn user.fixtures.catch_throw.MayFail(copy _1) -> [bb3, unwind: bb1];",
    "    }",
    "",
    "    bb1 [landing _2, _3] [handling bb1]: {",
    "        _4 = is_type_tag(copy _2, PANIC);",
    "        branch copy _4 -> [bb4, bb2];",
    "    }",
    "",
    "    bb2 [handling bb1]: {",
    "        _0 = const \"caught\";",
    "        goto -> bb3;",
    "    }",
    "",
    "    bb3: {",
    "        return;",
    "    }",
    "",
    "    bb4 [handling bb1]: {",
    "        rethrow copy _2 with copy _3;",
    "    }",
    "}",
];

// The loc of the workspace function named `name` in `file`.
function pretty_test_function(db: root.hir.Db, file: int, name: string) -> int throws never {
    let tree = root.hir.file_item_tree(db, file);
    for (let id in tree.functions.keys()) {
        let loc = db.function_locs.intern(file, id);
        if (root.hir.function_data(db, loc).name == name) {
            return loc;
        }
    }
    baml.sys.panic(`no function ${name}`)
}

function pretty_test_local(name: string?, ty: root.types.RuntimeTy) -> LocalDecl throws never {
    LocalDecl { name: name, ty: ty, span: null, scope_span: null, is_captured: false }
}

test "display_function prints a catch body as the Rust printer does" {
    let db = root.db.project_db(
        root.STDLIB_DIR,
        { "ns_fixtures/ns_catch_throw/catch_throw.baml": PRETTY_TEST_SOURCE },
    );
    let file = db.source_root(db.root_order[db.root_order.length() - 1]).files[0];
    let may_fail = pretty_test_function(db, file, "MayFail");
    let single = pretty_test_function(db, file, "SingleCatchWildcard");

    let bb0 = BasicBlock.new(0);
    bb0.unwind = 1;
    bb0.terminator
        = TerminatorCall {
            has_trace: false,
            argument_layout: null,
            callee: OperandConstant { value: ConstantFunction { value: may_fail } },
            args: [operand_copy_local(1)],
            ntypeargs: 0,
            destination: PlaceLocal { value: 0 },
            target: 3,
            unwind: 1,
        };
    let bb1 = BasicBlock.new(1);
    bb1.landing = Landing { error_local: 2, context_local: 3 };
    bb1.handling = 1;
    bb1.statements
        = [
            Statement {
                kind: StatementKindAssign {
                    destination: PlaceLocal { value: 4 },
                    value: RvalueIsTypeTag { operand: operand_copy_local(2), tag: -2 },
                },
                span: null,
            },
        ];
    bb1.terminator
        = TerminatorBranch { condition: operand_copy_local(4), then_block: 4, else_block: 2 };
    let bb2 = BasicBlock.new(2);
    bb2.handling = 1;
    bb2.statements
        = [
            Statement {
                kind: StatementKindAssign {
                    destination: PlaceLocal { value: 0 },
                    value: RvalueUse {
                        value: OperandConstant { value: ConstantString { value: "caught" } },
                    },
                },
                span: null,
            },
        ];
    bb2.terminator = TerminatorGoto { target: 3 };
    let bb3 = BasicBlock.new(3);
    bb3.terminator = TerminatorReturn {};
    let bb4 = BasicBlock.new(4);
    bb4.handling = 1;
    bb4.terminator
        = TerminatorRethrow { value: operand_copy_local(2), context: operand_copy_local(3) };

    let func = MirFunction {
        arity: 1,
        span: null,
        identity: MirFunctionIdDeclared { value: single },
        kind: MirFunctionKindBytecode {
            value: MirFunctionBody {
                blocks: [bb0, bb1, bb2, bb3, bb4],
                entry: 0,
                locals: [
                    pretty_test_local("_0", root.types.TyString {}),
                    pretty_test_local("x", root.types.TyInt {}),
                    pretty_test_local("e", root.types.TyUnknown {}),
                    pretty_test_local(null, root.types.TyUnknown {}),
                    pretty_test_local(null, root.types.TyBool {}),
                ],
            },
        },
        lambdas: [],
        signature: null,
    };
    assert.equal(display_function(db, func), PRETTY_TEST_EXPECTED_LINES.join("\n") + "\n");
}

test "rust_float_display matches Rust's f64 Display" {
    assert.equal(rust_float_display(1.0), "1");
    assert.equal(rust_float_display(0.5), "0.5");
    assert.equal(rust_float_display(-2.0), "-2");
    assert.equal(rust_float_display(1.0 / 0.0), "inf");
}

test "Names prints templates as Rust's Display and Debug do" {
    let names = Names.of(root.hir.Db.new());
    let frame_list: root.types.TyTemplate = root.types.TyTemplateList { elem: root.types.TyTypeArgRef { index: 0 } };
    assert.equal(names.template(frame_list), "#0[]");
    let union_: root.types.TyTemplate = root.types.TyTemplateUnion { members: [root.types.TyInt {}, root.types.TyNull {}] };
    assert.equal(names.template(root.types.TyTemplateList { elem: union_ }), "(int | null)[]");
    assert.equal(template_debug(root.types.TyInt {}, names), "Int");
    assert.equal(template_debug(root.types.TyTypeArgRef { index: 0 }, names), "TypeArgRef(0)");
}
