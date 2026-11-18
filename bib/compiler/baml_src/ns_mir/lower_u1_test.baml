// port: baml_compiler2_mir/src/lower.rs::indirect_call_layout_tests @ d9be6853b

// port: baml_compiler2_mir/src/lower.rs::indirect_call_layout_tests::indirect_call_body @ d9be6853b
// `_0 = call copy _1()`: a call through a function VALUE, the shape the
// value road builds for a method call TIR left unresolved.
function indirect_call_body(
    argument_layout: root.types.CallLayout?,
) -> MirFunctionBody throws never {
    let call = BasicBlock.new(0);
    call.terminator
        = TerminatorCall {
            has_trace: false,
            argument_layout: argument_layout,
            callee: operand_copy_local(1),
            args: [],
            ntypeargs: 0,
            destination: PlaceLocal { value: 0 },
            target: 1,
            unwind: null,
        };
    let done = BasicBlock.new(1);
    done.terminator = TerminatorReturn {};
    MirFunctionBody {
        blocks: [call, done],
        entry: 0,
        locals: baml.Array.generate(2, (_) -> {
            LocalDecl {
                name: null,
                ty: root.types.TyUnknown {},
                span: null,
                scope_span: null,
                is_captured: false,
            }
        }),
    }
}

test "indirect call without a checked layout is an internal error" {
    let message = "";
    check_indirect_call_layouts(indirect_call_body(null)) catch (e) {
        MirInternalError => {
            message = e.message;
        },
    };
    assert.contains(message, "no call plan");
}

test "indirect call with a checked layout lowers" {
    check_indirect_call_layouts(indirect_call_body(root.types.CallLayout { value: [] }));
}
