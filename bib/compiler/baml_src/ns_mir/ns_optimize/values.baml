// port: baml_compiler2_mir/src/optimize/values.rs @ d9be6853b
//
// Constant folding, branch simplification, dead stores, liveness and
// operand-prefix materialization.
//
// Namespace `mir.optimize` (Rust's private module `optimize::values`); MIR
// items are `root.mir.<name>`, and `super::` is `root.mir.`.
//
// Restructured (BAML forces it):
// - Rewrites through `&mut Rvalue` / `&mut Statement` return the new value,
//   as in optimize.baml, and never mutate an IR node in place: a folded
//   constant operand is shared by every use it was substituted into, so
//   `fold_concat_parts` builds a new string constant where Rust's
//   `push_str` appends to the one it owns.
// - Rust's `i64` checked arithmetic is `bigint` arithmetic range-checked by
//   `root.types.int63_new` (Rust's `Int63::new` after `checked_*`).
// - `live_out`'s const generic `PRECISE` is the parameter `precise`.
// - `prefix_operands` hands out `&mut Operand`s; here it returns the
//   operands, and `set_prefix_operand` writes one back.

// port: baml_compiler2_mir/src/optimize/values.rs::scalar @ d9be6853b
function scalar(constant: root.mir.Constant) -> bool throws never {
    match (constant) {
        root.mir.ConstantInt
            | root.mir.ConstantFloat
            | root.mir.ConstantBool
            | root.mir.ConstantString
            | root.mir.ConstantNull =>
        {
            true
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::fold_constants @ d9be6853b
// Propagate immutable scalar definitions, including named bindings. Keeping
// the definitions until ordinary DCE preserves locals used in projection
// positions.
function fold_constants(body: root.mir.MirFunctionBody, arity: int) -> void throws never {
    let defs = root.mir.count_local_defs(body);
    let constants: map<int, root.mir.Operand> = {};
    while (true) {
        let previous = constants.length();
        for (let block in body.blocks) {
            block.statements
                = block.statements.map((original) -> {
                    let statement = root.mir.apply_subst_to_statement(original, constants);
                    let assign = match (statement.kind) {
                        let s: root.mir.StatementKindAssign => s,
                        _ => {
                            return statement;
                        },
                    };
                    let value = fold_concat_parts(assign.value);
                    let folded = fold(value);
                    if (folded != null) {
                        value
                            = root.mir.RvalueUse {
                                value: root.mir.OperandConstant { value: folded },
                            };
                    }
                    match (assign.destination) {
                        let d: root.mir.PlaceLocal if d.value > arity && defs[d.value] == 1 => {
                            match (value) {
                                root.mir.RvalueUse {
                                    value: root.mir.OperandConstant { value: let constant },
                                }
                                    if scalar(constant) =>
                                {
                                    constants.set(
                                        d.value,
                                        root.mir.OperandConstant { value: constant },
                                    );
                                },
                                _ => {},
                            }
                        },
                        _ => {},
                    }
                    root.mir.Statement {
                        kind: root.mir.StatementKindAssign {
                            destination: assign.destination,
                            value: value,
                        },
                        span: statement.span,
                    }
                });
            let term = block.terminator;
            if (term != null) {
                block.terminator = root.mir.apply_subst_to_terminator(term, constants);
            }
        }
        if (constants.length() == previous) {
            break;
        }
    }

    for (let block in body.blocks) {
        let target = match (block.terminator) {
            root.mir.TerminatorBranch {
                condition: root.mir.OperandConstant { value: root.mir.ConstantBool { value: let value } },
                then_block: let then_block,
                else_block: let else_block,
            } =>
            {
                if (value) {
                    then_block
                } else {
                    else_block
                }
            },
            let t: root.mir.TerminatorShortCircuit => {
                let value = match (t.operand) {
                    root.mir.OperandConstant { value: let constant } if scalar(constant) => constant,
                    _ => null,
                };
                if (value == null) {
                    null
                } else {
                    let taken = match (t.kind) {
                        root.mir.ShortCircuitKind.And => {
                            match (value) {
                                let b: root.mir.ConstantBool => !b.value,
                                _ => {
                                    continue;
                                },
                            }
                        },
                        root.mir.ShortCircuitKind.Or => {
                            match (value) {
                                let b: root.mir.ConstantBool => b.value,
                                _ => {
                                    continue;
                                },
                            }
                        },
                        root.mir.ShortCircuitKind.Coalesce => !(value is root.mir.ConstantNull),
                    };
                    if (taken) {
                        block.statements.push(
                            root.mir.Statement {
                                kind: root.mir.StatementKindAssign {
                                    destination: t.destination,
                                    value: root.mir.RvalueUse {
                                        value: root.mir.OperandConstant { value: value },
                                    },
                                },
                                span: block.terminator_span,
                            },
                        );
                    }
                    if (taken) {
                        t.join
                    } else {
                        t.eval_rhs
                    }
                }
            },
            _ => null,
        };
        if (target != null) {
            block.terminator = root.mir.TerminatorGoto { target: target };
        }
    }
    simplify_boolean_diamonds(body);
}

// port: baml_compiler2_mir/src/optimize/values.rs::MAX_FOLDED_STRING @ d9be6853b
// Longest string constant folding builds, in bytes.
const MAX_FOLDED_STRING: int = 4096;

// port: baml_compiler2_mir/src/optimize/values.rs::fold_concat_parts @ d9be6853b
// Join the adjacent constant parts of a `RvalueConcatStrings`, as `fold`
// joins a `+` of two constants. Two parts left are a plain `+`, so `fold`
// can finish the job; one is the value itself. Restructured: returns the
// rewritten rvalue (the argument itself when it is no concatenation), and a
// joined part is a new constant.
function fold_concat_parts(value: root.mir.Rvalue) -> root.mir.Rvalue throws never {
    let parts = match (value) {
        let v: root.mir.RvalueConcatStrings => v.value,
        _ => {
            return value;
        },
    };
    let folded: root.mir.Operand[] = [];
    for (let part in parts) {
        let last = folded.at(folded.length() - 1);
        match (last, part) {
            (
                root.mir.OperandConstant { value: root.mir.ConstantString { value: let acc } },
                root.mir.OperandConstant { value: root.mir.ConstantString { value: let next } },
            )
                if acc.byte_length() + next.byte_length() <= MAX_FOLDED_STRING =>
            {
                folded[folded.length() - 1]
                    = root.mir.OperandConstant {
                        value: root.mir.ConstantString { value: `${acc}${next}` },
                    };
                continue;
            },
            _ => {},
        }
        folded.push(part);
    }
    match (folded.length()) {
        2 => root.mir.RvalueBinaryOp { op: root.mir.BinOp.Add, left: folded[0], right: folded[1] },
        1 => root.mir.RvalueUse { value: folded[0] },
        _ => root.mir.RvalueConcatStrings { value: folded },
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::fold @ d9be6853b
// Restructured: the closure `int` (`Int63::new`) is `root.types.int63_new`
// of a `bigint` result.
function fold(value: root.mir.Rvalue) -> root.mir.Constant? throws never {
    match (value) {
        root.mir.RvalueUnaryOp { op: let op, operand: root.mir.OperandConstant { value: let arg } } => {
            fold_unary(op, arg)
        },
        root.mir.RvalueBinaryOp {
            op: let op,
            left: root.mir.OperandConstant { value: let left },
            right: root.mir.OperandConstant { value: let right },
        } =>
        {
            fold_binary(op, left, right)
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::fold @ d9be6853b
// Restructured: `fold`'s unary arm.
function fold_unary(
    op: root.mir.UnaryOp,
    arg: root.mir.Constant,
) -> root.mir.Constant? throws never {
    match (op) {
        root.mir.UnaryOp.Not => {
            match (arg) {
                let a: root.mir.ConstantBool => root.mir.ConstantBool { value: !a.value },
                _ => null,
            }
        },
        root.mir.UnaryOp.Neg => {
            match (arg) {
                let a: root.mir.ConstantInt => {
                    let negated = root.types.int63_new(0n - a.value)
                        ?? return null;
                    root.mir.ConstantInt { value: negated }
                },
                let a: root.mir.ConstantFloat if a.value.is_finite() => {
                    root.mir.ConstantFloat { value: -a.value }
                },
                _ => null,
            }
        },
        root.mir.UnaryOp.Truthy => {
            let truthy = match (arg) {
                root.mir.ConstantNull => false,
                let a: root.mir.ConstantBool => a.value,
                let a: root.mir.ConstantInt => a.value != 0,
                let a: root.mir.ConstantFloat => a.value != 0.0,
                let a: root.mir.ConstantString => !a.value.is_empty(),
                _ => {
                    return null;
                },
            };
            root.mir.ConstantBool { value: truthy }
        },
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::fold @ d9be6853b
// Restructured: `fold`'s binary arm.
function fold_binary(
    op: root.mir.BinOp,
    left: root.mir.Constant,
    right: root.mir.Constant,
) -> root.mir.Constant? throws never {
    let boolean = (value: bool?) -> root.mir.Constant? {
        if (value != null) {
            root.mir.ConstantBool { value: value }
        } else {
            null
        }
    };
    match (left, right) {
        (root.mir.ConstantInt { value: let a }, root.mir.ConstantInt { value: let b }) => {
            let wide = 0n + a;
            let result: bigint = match (op) {
                root.mir.BinOp.Add => wide + b,
                root.mir.BinOp.Sub => wide - b,
                root.mir.BinOp.Mul => wide * b,
                root.mir.BinOp.Div => {
                    if (b == 0) {
                        return null;
                    }
                    wide / b
                },
                root.mir.BinOp.Mod => {
                    if (b == 0) {
                        return null;
                    }
                    wide % b
                },
                root.mir.BinOp.BitAnd => 0n + (a & b),
                root.mir.BinOp.BitOr => 0n + (a | b),
                root.mir.BinOp.BitXor => 0n + (a ^ b),
                root.mir.BinOp.Shl => {
                    0n
                        + (
                            root.types.int63_shift_left(a, b) catch (e) {
                                root.types.IntShiftErrorNegativeCount => {
                                    return null;
                                },
                            }
                        )
                },
                root.mir.BinOp.Shr => {
                    0n
                        + (
                            root.types.int63_shift_right(a, b) catch (e) {
                                root.types.IntShiftErrorNegativeCount => {
                                    return null;
                                },
                            }
                        )
                },
                _ => {
                    return boolean(compare(op, a, b));
                },
            };
            let n = root.types.int63_new(result)
                ?? return null;
            root.mir.ConstantInt { value: n }
        },
        (root.mir.ConstantFloat { value: let a }, root.mir.ConstantFloat { value: let b })
            if a.is_finite() && b.is_finite() => {
            let compared = compare(op, a, b);
            if (compared != null) {
                return root.mir.ConstantBool { value: compared };
            }
            let result = match (op) {
                root.mir.BinOp.Add => a + b,
                root.mir.BinOp.Sub => a - b,
                root.mir.BinOp.Mul => a * b,
                root.mir.BinOp.Div if b != 0.0 => a / b,
                _ => {
                    return null;
                },
            };
            if (result.is_finite()) {
                root.mir.ConstantFloat { value: result }
            } else {
                null
            }
        },
        (root.mir.ConstantBool { value: let a }, root.mir.ConstantBool { value: let b }) => {
            boolean(compare(op, a, b))
        },
        (root.mir.ConstantString { value: let a }, root.mir.ConstantString { value: let b }) => {
            if (op == root.mir.BinOp.Add && a.byte_length() + b.byte_length() <= MAX_FOLDED_STRING) {
                root.mir.ConstantString { value: `${a}${b}` }
            } else {
                boolean(compare(op, a, b))
            }
        },
        (root.mir.ConstantNull {}, root.mir.ConstantNull {}) => {
            match (op) {
                root.mir.BinOp.Eq => root.mir.ConstantBool { value: true },
                root.mir.BinOp.Ne => root.mir.ConstantBool { value: false },
                _ => null,
            }
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::compare @ d9be6853b
// Restructured: Rust's `T: PartialOrd` is `baml.ops.Compare`; equality is
// BAML's `==`.
function compare<T extends baml.ops.Compare>(op: root.mir.BinOp, a: T, b: T) -> bool? throws never {
    match (op) {
        root.mir.BinOp.Eq => a == b,
        root.mir.BinOp.Ne => a != b,
        root.mir.BinOp.Lt => a < b,
        root.mir.BinOp.Le => a <= b,
        root.mir.BinOp.Gt => a > b,
        root.mir.BinOp.Ge => a >= b,
        _ => null,
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::simplify_boolean_diamonds @ d9be6853b
function simplify_boolean_diamonds(body: root.mir.MirFunctionBody) -> void throws never {
    for (let index = 0; index < body.blocks.length(); index += 1) {
        let branch = match (body.blocks[index].terminator) {
            let t: root.mir.TerminatorBranch => t,
            _ => {
                continue;
            },
        };
        let then_block = body.blocks[branch.then_block];
        let else_block = body.blocks[branch.else_block];
        let joins = match (then_block.terminator, else_block.terminator) {
            (
                root.mir.TerminatorGoto { target: let then_join },
                root.mir.TerminatorGoto { target: let else_join },
            ) =>
            {
                (then_join, else_join)
            },
            _ => {
                continue;
            },
        };
        if (joins.0 != joins.1) {
            continue;
        }
        if (then_block.statements.length() != 1 || else_block.statements.length() != 1) {
            continue;
        }
        let values = match (then_block.statements[0].kind, else_block.statements[0].kind) {
            (
                root.mir.StatementKindAssign {
                    destination: root.mir.PlaceLocal { value: let then_local },
                    value: root.mir.RvalueUse {
                        value: root.mir.OperandConstant {
                            value: root.mir.ConstantBool { value: let then_value },
                        },
                    },
                },
                root.mir.StatementKindAssign {
                    destination: root.mir.PlaceLocal { value: let else_local },
                    value: root.mir.RvalueUse {
                        value: root.mir.OperandConstant {
                            value: root.mir.ConstantBool { value: let else_value },
                        },
                    },
                },
            ) =>
            {
                (then_local, then_value, else_local, else_value)
            },
            _ => {
                continue;
            },
        };
        if (values.0 != values.2 || values.1 == values.3) {
            continue;
        }
        let statement = root.mir.Statement {
            kind: root.mir.StatementKindAssign {
                destination: root.mir.PlaceLocal { value: values.0 },
                value: if (values.1) {
                    root.mir.RvalueUse { value: branch.condition }
                } else {
                    root.mir.RvalueUnaryOp { op: root.mir.UnaryOp.Not, operand: branch.condition }
                },
            },
            span: body.blocks[index].terminator_span,
        };
        let target = joins.0;
        body.blocks[index].statements.push(statement);
        body.blocks[index].terminator = root.mir.TerminatorGoto { target: target };
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::eliminate_dead_stores @ d9be6853b
// Backwards liveness removes individual overwritten definitions, rather than
// requiring the entire local to be unused. Potentially failing RHSs stay
// put. Restructured: a removed store's statement is replaced by a new `Nop`
// statement (Rust overwrites its kind), then dropped.
function eliminate_dead_stores(
    body: root.mir.MirFunctionBody,
    arity: int,
    opt: root.mir.OptLevel,
) -> void throws never {
    let effects = Analysis.new(body);
    let n = body.locals.length();
    let live_in: bool[][] = baml.Array.generate(body.blocks.length(), (_) -> {
        baml.Array.filled(n, false)
    });
    while (true) {
        let changed = false;
        for (let block in body.blocks.reverse()) {
            let (let live, let exceptional) = live_out(false, body, block, live_in);
            for (let statement in block.statements.reverse()) {
                transfer(statement, live, exceptional);
            }
            if (live != live_in[block.id]) {
                live_in[block.id] = live;
                changed = true;
            }
        }
        if (!changed) {
            break;
        }
    }
    for (let index = 0; index < body.blocks.length(); index += 1) {
        let block = body.blocks[index];
        let (let live, let exceptional) = live_out(false, body, block, live_in);
        let statements = block.statements;
        for (let statement_index = statements.length() - 1; statement_index >= 0; statement_index -= 1) {
            let statement = statements[statement_index];
            match (statement.kind) {
                root.mir.StatementKindAssign {
                    destination: root.mir.PlaceLocal { value: let local },
                }
                    if local > arity
                        && (opt != root.mir.OptLevel.Zero || body.locals[local].name == null)
                        && !live[local]
                        && effects.discardable[index][statement_index] =>
                {
                    statement
                        = root.mir.Statement {
                            kind: root.mir.StatementKindNop {},
                            span: statement.span,
                        };
                    statements[statement_index] = statement;
                },
                _ => {},
            }
            transfer(statement, live, exceptional);
        }
        block.statements
            = statements.filter((statement) -> {
                !(statement.kind is root.mir.StatementKindNop)
            });
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::live_in_precise @ d9be6853b
// Liveness for spilling locals across suspensions: terminator destinations
// are definitions only on normal edges, where they were assigned.
function live_in_precise(body: root.mir.MirFunctionBody) -> bool[][] throws never {
    let n = body.locals.length();
    let live_in: bool[][] = baml.Array.generate(body.blocks.length(), (_) -> {
        baml.Array.filled(n, false)
    });
    while (true) {
        let changed = false;
        for (let block in body.blocks.reverse()) {
            let (let live, let exceptional) = live_out(true, body, block, live_in);
            for (let statement in block.statements.reverse()) {
                transfer(statement, live, exceptional);
            }
            if (live != live_in[block.id]) {
                live_in[block.id] = live;
                changed = true;
            }
        }
        if (!changed) {
            break;
        }
    }
    live_in
}

// port: baml_compiler2_mir/src/optimize/values.rs::live_out @ d9be6853b
// In precise mode, kill terminator destinations only on normal edges.
// Restructured: the const generic `PRECISE` is the parameter `precise`.
function live_out(
    precise: bool,
    body: root.mir.MirFunctionBody,
    block: root.mir.BasicBlock,
    live_in: bool[][],
) -> (bool[], bool[]) throws never {
    let live = baml.Array.filled(body.locals.length(), false);
    let exceptional = baml.Array.filled(body.locals.length(), false);
    let handler = block.unwind;
    if (handler != null) {
        union(exceptional, live_in[handler]);
    }
    let term = block.terminator;
    if (term != null) {
        let edge: (root.mir.Place?, int?) = match (term) {
            root.mir.TerminatorCall { destination: let destination, unwind: let unwind }
                | root.mir.TerminatorVirtualCall { destination: let destination, unwind: let unwind }
                | root.mir.TerminatorSysOp { destination: let destination, unwind: let unwind }
                | root.mir.TerminatorAwait { destination: let destination, unwind: let unwind }
                | root.mir.TerminatorAwaitAny { destination: let destination, unwind: let unwind } =>
            {
                (destination, unwind)
            },
            let t: root.mir.TerminatorSpawn => (t.future, null),
            _ => (null, null),
        };
        let destination = if (precise) {
            edge.0
        } else {
            null
        };
        let unwind = if (precise) {
            edge.1
        } else {
            null
        };
        for (let successor in root.mir.terminator_successors(term)) {
            if (unwind == null || successor != unwind) {
                union(live, live_in[successor]);
            }
        }
        match (destination) {
            let d: root.mir.PlaceLocal => {
                live[d.value] = false;
            },
            _ => {},
        }
        if (unwind != null) {
            union(live, live_in[unwind]);
        }
        let uses = baml.Array.filled(live.length(), 0);
        root.mir.count_in_terminator(term, uses);
        for (let i = 0; i < live.length(); i += 1) {
            live[i] = live[i] || uses[i] != 0;
        }
        if (term is root.mir.TerminatorReturn) {
            live[0] = true;
        }
    }
    union(live, exceptional);
    (live, exceptional)
}

// port: baml_compiler2_mir/src/optimize/values.rs::transfer @ d9be6853b
function transfer(
    statement: root.mir.Statement,
    live: bool[],
    exceptional: bool[],
) -> void throws never {
    match (statement.kind) {
        root.mir.StatementKindAssign { destination: root.mir.PlaceLocal { value: let local } } => {
            live[local] = false;
        },
        _ => {},
    }
    let uses = baml.Array.filled(live.length(), 0);
    root.mir.count_in_statement(statement, uses);
    for (let i = 0; i < live.length(); i += 1) {
        live[i] = live[i] || uses[i] != 0;
    }
    // A panic can enter the handler before this statement stores its result.
    union(live, exceptional);
}

// port: baml_compiler2_mir/src/optimize/values.rs::union @ d9be6853b
function union(into: bool[], from: bool[]) -> void throws never {
    for (let i = 0; i < into.length() && i < from.length(); i += 1) {
        into[i] = into[i] || from[i];
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::materialize_operand_prefixes @ d9be6853b
// Put infallible constants before the next call producing a consumer
// operand. This exposes mixed prefixes like `[f(), 2, g()]` without moving
// any effectful evaluation. Stackification may still reject carrying and
// inline the constant.
function materialize_operand_prefixes(body: root.mir.MirFunctionBody) -> void throws never {
    let defs = root.mir.count_local_defs(body);
    let uses = root.mir.count_local_uses(body);
    let calls: map<int, int> = {};
    for (let block in body.blocks) {
        match (block.terminator) {
            root.mir.TerminatorCall { destination: root.mir.PlaceLocal { value: let local } }
                | root.mir.TerminatorVirtualCall { destination: root.mir.PlaceLocal { value: let local } }
                | root.mir.TerminatorSysOp { destination: root.mir.PlaceLocal { value: let local } }
                | root.mir.TerminatorAwait { destination: root.mir.PlaceLocal { value: let local } }
                if defs[local] == 1 && uses[local] == 1 =>
            {
                calls.set(local, block.id);
            },
            _ => {},
        }
    }
    for (let block_index = 0; block_index < body.blocks.length(); block_index += 1) {
        let statements = body.blocks[block_index].statements.length();
        for (let consumer_index = 0; consumer_index <= statements; consumer_index += 1) {
            let operands = prefix_operands(body.blocks[block_index], consumer_index);
            for (let index = 0; index < operands.length(); index += 1) {
                let constant = match (operands[index]) {
                    let o: root.mir.OperandConstant => o.value,
                    _ => {
                        continue;
                    },
                };
                let ty = constant_type(constant)
                    ?? continue;
                let next = operands.slice(index + 1, operands.length()).find((operand) -> {
                    !(operand is root.mir.OperandConstant)
                });
                let local = match (next) {
                    root.mir.OperandCopy { value: root.mir.PlaceLocal { value: let local } }
                        | root.mir.OperandMove { value: root.mir.PlaceLocal { value: let local } } =>
                    {
                        local
                    },
                    _ => {
                        continue;
                    },
                };
                let def_block = calls.get(local)
                    ?? continue;
                if (def_block == block_index) {
                    continue;
                }
                let temporary = body.locals.length();
                body.locals.push(
                    root.mir.LocalDecl {
                        name: null,
                        ty: ty,
                        span: null,
                        scope_span: null,
                        is_captured: false,
                    },
                );
                body.blocks[def_block].statements.push(
                    root.mir.Statement {
                        kind: root.mir.StatementKindAssign {
                            destination: root.mir.PlaceLocal { value: temporary },
                            value: root.mir.RvalueUse {
                                value: root.mir.OperandConstant { value: constant },
                            },
                        },
                        span: null,
                    },
                );
                set_prefix_operand(
                    body.blocks[block_index],
                    consumer_index,
                    index,
                    root.mir.operand_copy_local(temporary),
                );
            }
        }
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::prefix_operands @ d9be6853b
// Restructured: returns the operands themselves (a snapshot, as Rust's
// caller clones them); `set_prefix_operand` writes one back.
function prefix_operands(
    block: root.mir.BasicBlock,
    index: int,
) -> root.mir.Operand[] throws never {
    if (index == block.statements.length()) {
        return match (block.terminator) {
            let t: root.mir.TerminatorCall => t.args.concat([]),
            let t: root.mir.TerminatorVirtualCall => t.args.concat([]),
            _ => [],
        };
    }
    let value = match (block.statements[index].kind) {
        let s: root.mir.StatementKindAssign => s.value,
        _ => {
            return [];
        },
    };
    match (value) {
        let r: root.mir.RvalueBinaryOp => [r.left, r.right],
        let r: root.mir.RvalueArray => r.elements.concat([]),
        let r: root.mir.RvalueConcatStrings => r.value.concat([]),
        let r: root.mir.RvalueMap => {
            r.entries.map((entry) -> {
                entry.1
            })
        },
        let r: root.mir.RvalueAggregate if !has_field_operand(r.fields) => r.fields.concat([]),
        _ => [],
    }
}

// port: baml_compiler2_mir/src/optimize/values.rs::prefix_operands @ d9be6853b
// Restructured: the guard of `prefix_operands`' aggregate arm: whether a
// field operand reads a field projection.
function has_field_operand(fields: root.mir.Operand[]) -> bool throws never {
    fields.some((field) -> {
        match (field) {
            root.mir.OperandCopy { value: root.mir.PlaceField }
                | root.mir.OperandMove { value: root.mir.PlaceField } =>
            {
                true
            },
            _ => false,
        }
    })
}

// port: baml_compiler2_mir/src/optimize/values.rs::prefix_operands @ d9be6853b
// Restructured: the write through `prefix_operands(block, index)[operand]`.
// Rebuilds the consumer (a statement or the terminator) with that operand
// replaced.
function set_prefix_operand(
    block: root.mir.BasicBlock,
    index: int,
    operand: int,
    replacement: root.mir.Operand,
) -> void throws never {
    let replace = (operands: root.mir.Operand[]) -> root.mir.Operand[] {
        let out = operands.concat([]);
        out[operand] = replacement;
        out
    };
    if (index == block.statements.length()) {
        match (block.terminator) {
            let t: root.mir.TerminatorCall => {
                block.terminator = root.mir.TerminatorCall { ...t, args: replace(t.args) };
            },
            let t: root.mir.TerminatorVirtualCall => {
                block.terminator = root.mir.TerminatorVirtualCall { ...t, args: replace(t.args) };
            },
            _ => baml.sys.panic("no prefix operand to write"),
        }
        return;
    }
    let statement = block.statements[index];
    let assign = match (statement.kind) {
        let s: root.mir.StatementKindAssign => s,
        _ => baml.sys.panic("no prefix operand to write"),
    };
    let value: root.mir.Rvalue = match (assign.value) {
        let r: root.mir.RvalueBinaryOp => {
            if (operand == 0) {
                root.mir.RvalueBinaryOp { ...r, left: replacement }
            } else {
                root.mir.RvalueBinaryOp { ...r, right: replacement }
            }
        },
        let r: root.mir.RvalueArray => root.mir.RvalueArray { ...r, elements: replace(r.elements) },
        let r: root.mir.RvalueConcatStrings => {
            root.mir.RvalueConcatStrings { value: replace(r.value) }
        },
        let r: root.mir.RvalueMap => {
            let entries = r.entries.concat([]);
            entries[operand] = (entries[operand].0, replacement);
            root.mir.RvalueMap { ...r, entries: entries }
        },
        let r: root.mir.RvalueAggregate => {
            root.mir.RvalueAggregate { ...r, fields: replace(r.fields) }
        },
        _ => baml.sys.panic("no prefix operand to write"),
    };
    block.statements[index]
        = root.mir.Statement {
            kind: root.mir.StatementKindAssign { destination: assign.destination, value: value },
            span: statement.span,
        };
}

// port: baml_compiler2_mir/src/optimize/values.rs::constant_type @ d9be6853b
function constant_type(constant: root.mir.Constant) -> root.types.RuntimeTy? throws never {
    match (constant) {
        root.mir.ConstantInt => root.types.TyInt {},
        root.mir.ConstantFloat => root.types.TyFloat {},
        root.mir.ConstantBool => root.types.TyBool {},
        root.mir.ConstantString => root.types.TyString {},
        root.mir.ConstantNull => root.types.TyNull {},
        _ => null,
    }
}
