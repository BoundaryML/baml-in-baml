// port: baml_compiler2_mir/src/optimize.rs::tests @ d9be6853b

// port: baml_compiler2_mir/src/optimize.rs::tests::reassigned_parameter_copies_stop_at_source_or_destination_writes::assign @ d9be6853b
function assign_local(local: int, operand: Operand) -> Statement {
    Statement {
        kind: StatementKindAssign {
            destination: PlaceLocal { value: local },
            value: RvalueUse { value: operand },
        },
        span: null,
    }
}

test "reassigned parameter copies stop at source or destination writes" {
    let writes: (int?)[] = [null, 1, 2];
    for (let write in writes) {
        let block = BasicBlock.new(0);
        block.statements
            = [
                assign_local(1, OperandConstant { value: ConstantInt { value: 7 } }),
                assign_local(2, operand_copy_local(1)),
            ];
        if (write != null) {
            block.statements.push(
                assign_local(write, OperandConstant { value: ConstantInt { value: 9 } }),
            );
        }
        block.statements.push(assign_local(0, operand_copy_local(2)));
        block.terminator = TerminatorReturn {};
        let names: (string?)[] = [null, "parameter", null];
        let body = MirFunctionBody {
            blocks: [block],
            entry: 0,
            locals: names.map((name) -> {
                LocalDecl {
                    name: name,
                    ty: root.types.TyInt {},
                    span: null,
                    scope_span: null,
                    is_captured: false,
                }
            }),
        };
        propagate_block_param_copies(body, 1);
        let expected = if (write == null) {
            1
        } else {
            2
        };
        let statements = body.blocks[0].statements;
        let last = statements[statements.length() - 1];
        let read = match (last.kind) {
            StatementKindAssign {
                value: RvalueUse { value: OperandCopy { value: PlaceLocal { value: let local } } },
            } =>
            {
                local
            },
            _ => null,
        };
        assert.equal(read, expected);
    }
}
