// port: baml_compiler2_mir/src/builder.rs @ d9be6853b
//
// The MIR builder: local allocation, basic block creation, statement and
// terminator emission, and the handler / shield discipline that keeps every
// block a maximal run of code under one handler.
//
// Restructured (BAML forces it):
// - `MirBuilder`'s methods stay methods of the class. Ids (`Local`,
//   `BlockId`) are `int`s, `Name` is `string`, `Span` is `root.base.Span`.
// - `build` and `build_body` consume the builder in Rust; here they hand
//   over the builder's `blocks` / `locals` arrays by reference, so the
//   builder must not be used afterwards. Lowering a lambda swaps the
//   builder out of `LoweringContext` (`mem::replace`): put a fresh
//   `MirBuilder.new(..)` in its place and keep the old object.
// - The `#[must_use]` tokens `OutOfLine` and `Shield` are plain classes; a
//   token handed back twice is not caught.
// - Rust's `call` is `call_with_type_args` with `ntypeargs = 0` (no
//   one-line forwarder).
// - Every `assert!` is a panic with Rust's message; `debug_assert!`s are
//   dropped.

// port: baml_compiler2_mir/src/builder.rs::OutOfLine @ d9be6853b
// Where lowering was before it moved out of line to fill a handler block;
// `MirBuilder.end_out_of_line` returns there.
class OutOfLine {
    block: int,
    unwind: int?,
    handling: int?,
}

// port: baml_compiler2_mir/src/builder.rs::Shield @ d9be6853b
// An open shield (a `defer` body being lowered). `MirBuilder.enter_shield`
// opens one; handing it back to `MirBuilder.leave_shield` closes it.
class Shield {
    // The depth entered; shields close innermost first.
    depth: int,
}

// port: baml_compiler2_mir/src/builder.rs::MirBuilder @ d9be6853b
// Builder for constructing MIR functions.
class MirBuilder {
    // Whose body this builder lowers; the built function's identity.
    owner: FunctionOwner,
    arity: int,
    blocks: BasicBlock[],
    locals: LocalDecl[],
    current_block_id: int?,
    span: root.base.Span?,
    // Current source span for tagging statements/terminators.
    current_source_span: root.base.Span?,
    // The handler a throw or panic at the current lowering position unwinds
    // to: the innermost enclosing `catch` handler or `defer` landing pad.
    // Every block is stamped with it at creation, and changing it moves
    // lowering to a fresh block (`transition_unwind`).
    current_unwind: int?,
    // The innermost handler whose body is being lowered, stamped the same
    // way.
    current_handling: int?,
    // How many `defer` bodies the current lowering position is inside; a
    // block is stamped `shielded` when this is non-zero.
    shield_depth: int,

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::new @ d9be6853b
    // A new MIR builder for a function.
    function new(owner: FunctionOwner, arity: int) -> MirBuilder throws never {
        MirBuilder {
            owner: owner,
            arity: arity,
            blocks: [],
            locals: [],
            current_block_id: null,
            span: null,
            current_source_span: null,
            current_unwind: null,
            current_handling: null,
            shield_depth: 0,
        }
    }

    // Rust's `owner()` accessor is the field `owner`.

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::set_span @ d9be6853b
    // Set the source span for the function.
    function set_span(self, span: root.base.Span) -> void throws never {
        self.span = span;
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::declare_local @ d9be6853b
    // Declare a new local variable or temporary. Convention: `_0` is the
    // return place, `_1..=_n` are parameters (n = arity), `_n+1...` are user
    // locals and temporaries.
    function declare_local(
        self,
        name: string?,
        ty: root.types.RuntimeTy,
        span: root.base.Span?,
    ) -> int throws never {
        let id = self.locals.length();
        self.locals.push(
            LocalDecl { name: name, ty: ty, span: span, scope_span: null, is_captured: false },
        );
        id
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::declare_captured_local @ d9be6853b
    // Declare a local a closure captures, and give it its cell. A
    // non-parameter local is celled right here, in the current block, so a
    // declaration that runs once per loop iteration hands each iteration's
    // closures their own cell; emit the initializing store after this. A
    // parameter is celled by the frame preamble instead.
    function declare_captured_local(
        self,
        name: string?,
        ty: root.types.RuntimeTy,
        span: root.base.Span?,
    ) -> int throws never {
        let local = self.locals.length();
        self.locals.push(
            LocalDecl { name: name, ty: ty, span: span, scope_span: null, is_captured: true },
        );
        if (local > self.arity) {
            self.push_statement(StatementKindFreshCell { local: local, carry_value: false }, null);
        }
        local
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::temp @ d9be6853b
    // Allocate a temporary (unnamed local).
    function temp(self, ty: root.types.RuntimeTy) -> int throws never {
        self.declare_local(null, ty, null)
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::local_ty @ d9be6853b
    // The declared type of a local.
    function local_ty(self, local: int) -> root.types.RuntimeTy throws never {
        self.locals[local].ty
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::local_decl @ d9be6853b
    // The declaration of a local.
    function local_decl(self, local: int) -> LocalDecl throws never {
        self.locals[local]
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::set_local_ty @ d9be6853b
    // Refine a local's declared type once TIR has a more specific one.
    function set_local_ty(self, local: int, ty: root.types.RuntimeTy) -> void throws never {
        self.locals[local].ty = ty;
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::create_block @ d9be6853b
    // Create a new basic block. It unwinds to the handler in force here and
    // belongs to the handler body being lowered.
    function create_block(self) -> int throws never {
        let id = self.blocks.length();
        let block = BasicBlock.new(id);
        block.unwind = self.current_unwind;
        block.handling = self.current_handling;
        block.shielded = self.shield_depth > 0;
        self.blocks.push(block);
        id
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::set_current_block @ d9be6853b
    // Set the current block for emitting statements and terminators.
    function set_current_block(self, block: int) -> void throws never {
        self.current_block_id = block;
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::current_block @ d9be6853b
    // The current block id; panics if none is set. Renamed field: the Rust
    // field `current_block` is `current_block_id`, since a field cannot share
    // a method's name.
    function current_block(self) -> int throws never {
        self.current_block_id ?? baml.sys.panic("no current block set")
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::is_current_terminated @ d9be6853b
    // Whether the current block has been terminated (true when none is set).
    function is_current_terminated(self) -> bool throws never {
        let id = self.current_block_id
            ?? return true;
        self.blocks[id].is_terminated()
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::unwind @ d9be6853b
    // The handler the current lowering position unwinds to.
    function unwind(self) -> int? throws never {
        self.current_unwind
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::create_handler_block @ d9be6853b
    // Create a handler block: the VM lands in it with `landing`, and it is
    // the first block of its own handler body. It unwinds to the handler in
    // force where it is created, never to itself.
    function create_handler_block(self, landing: Landing) -> int throws never {
        let id = self.create_block();
        let block = self.blocks[id];
        block.landing = landing;
        block.handling = id;
        id
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::transition_unwind @ d9be6853b
    // Lower what follows with `unwind` as its handler. The current block
    // (created under the old handler) is left with a `goto` to a fresh block,
    // which becomes current. A current block that is still empty simply takes
    // the new handler; a terminated one needs nothing.
    function transition_unwind(self, unwind: int?) -> void throws never {
        if (self.current_unwind == unwind) {
            return;
        }
        if (unwind != null && self.blocks[unwind].landing == null) {
            baml.sys.panic(`BlockId(${unwind}) is not a handler block: nothing can unwind to it`);
        }
        if (self.is_current_terminated()) {
            self.current_unwind = unwind;
            return;
        }
        let current = self.current_block();
        if (self.blocks[current].statements.length() == 0) {
            self.blocks[current].unwind = unwind;
            self.current_unwind = unwind;
            return;
        }
        // The goto belongs to the block it leaves, under the old handler.
        let fresh = self.blocks.length();
        self.set_terminator(TerminatorGoto { target: fresh });
        self.current_unwind = unwind;
        self.create_block();
        self.current_block_id = fresh;
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::enter_shield @ d9be6853b
    // Lower what follows inside a `defer` body: shielded from cancellation.
    // Nests; handing the returned `Shield` to `leave_shield` closes it.
    function enter_shield(self) -> Shield throws never {
        let depth = self.shield_depth + 1;
        self.transition_shield(depth);
        Shield { depth: depth }
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::leave_shield @ d9be6853b
    // Close `shield`, the innermost one open.
    function leave_shield(self, shield: Shield) -> void throws never {
        self.transition_shield(shield.depth - 1);
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::transition_shield @ d9be6853b
    // Make `depth` the shield depth. Nothing more if the current block is
    // terminated or already carries the new shield state; an empty current
    // block is restamped; otherwise it is left with a `goto` (under the old
    // state) to a fresh block created under the new.
    function transition_shield(self, depth: int) -> void throws never {
        let shielded = depth > 0;
        if (self.is_current_terminated()) {
            self.shield_depth = depth;
            return;
        }
        let current = self.current_block();
        if (self.blocks[current].shielded == shielded) {
            self.shield_depth = depth;
            return;
        }
        if (self.blocks[current].statements.length() == 0) {
            self.blocks[current].shielded = shielded;
            self.shield_depth = depth;
            return;
        }
        let fresh = self.blocks.length();
        self.set_terminator(TerminatorGoto { target: fresh });
        self.shield_depth = depth;
        self.create_block();
        self.current_block_id = fresh;
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::begin_out_of_line @ d9be6853b
    // Fill `block` (a handler created earlier) with `unwind` as its handler
    // and `handling` as the handler body it is part of, leaving the current
    // block where it is; the returned token brings lowering back to it.
    function begin_out_of_line(
        self,
        block: int,
        unwind: int?,
        handling: int?,
    ) -> OutOfLine throws never {
        let out_of_line = OutOfLine {
            block: self.current_block(),
            unwind: self.current_unwind,
            handling: self.current_handling,
        };
        self.current_block_id = block;
        self.current_unwind = unwind;
        self.current_handling = handling;
        out_of_line
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::end_out_of_line @ d9be6853b
    // Return from `begin_out_of_line`.
    function end_out_of_line(self, out_of_line: OutOfLine) -> void throws never {
        self.current_block_id = out_of_line.block;
        self.current_unwind = out_of_line.unwind;
        self.current_handling = out_of_line.handling;
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::current_block_mut @ d9be6853b
    function current_block_mut(self) -> BasicBlock throws never {
        self.check_current_protection();
        let id = self.current_block_id ?? baml.sys.panic("no current block set");
        self.blocks[id]
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::check_current_protection @ d9be6853b
    // The current block must have been created under the handler in force: a
    // block's handler is fixed at creation, so lowering code into it from a
    // position with a different handler would give that code the wrong one.
    function check_current_protection(self) -> void throws never {
        let id = self.current_block_id ?? baml.sys.panic("no current block set");
        let block = self.blocks[id];
        let shielded = self.shield_depth > 0;
        if (
            block.unwind != self.current_unwind
                || block.handling != self.current_handling
                || block.shielded != shielded
        ) {
            baml.sys.panic(
                `BlockId(${id}) was created unwinding to ${block.unwind ?? "None"} (handling ${block.handling ?? "None"}, shielded ${block.shielded}) but code is being lowered into it unwinding to ${self.current_unwind ?? "None"} (handling ${self.current_handling ?? "None"}, shielded ${shielded})`,
            );
        }
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::push_statement @ d9be6853b
    // Push a statement to the current block.
    function push_statement(self, kind: StatementKind, span: root.base.Span?) -> void throws never {
        let span = span ?? self.current_source_span;
        let block = self.current_block_mut();
        if (block.terminator != null) {
            baml.sys.panic("cannot add statement to terminated block");
        }
        block.statements.push(Statement { kind: kind, span: span });
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::assign @ d9be6853b
    // Emit an assignment: `dest = value`.
    function assign(self, destination: Place, value: Rvalue) -> void throws never {
        self.push_statement(StatementKindAssign { destination: destination, value: value }, null);
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::virtual_field_store @ d9be6853b
    // Emit an open-world interface-field store.
    function virtual_field_store(
        self,
        iface: root.types.TyTemplateInterfaceConstraint,
        receiver: Operand,
        field_index: int,
        field: string,
        value: Operand,
    ) -> void throws never {
        self.push_statement(
            StatementKindVirtualFieldStore {
                iface: iface,
                receiver: receiver,
                field_index: field_index,
                field: field,
                value: value,
            },
            null,
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::recell_with_current_value @ d9be6853b
    // Give a captured local a new cell holding its current value, so the
    // closures that captured the old cell stop sharing it with what follows.
    function recell_with_current_value(self, local: int) -> void throws never {
        self.push_statement(StatementKindFreshCell { local: local, carry_value: true }, null);
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::set_terminator @ d9be6853b
    function set_terminator(self, terminator: Terminator) -> void throws never {
        let terminator_span = self.current_source_span;
        let block = self.current_block_mut();
        if (block.terminator != null) {
            baml.sys.panic("block already has a terminator");
        }
        block.terminator = terminator;
        block.terminator_span = terminator_span;
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::goto @ d9be6853b
    // Emit an unconditional goto.
    function goto(self, target: int) -> void throws never {
        self.set_terminator(TerminatorGoto { target: target });
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::branch @ d9be6853b
    // Emit a conditional branch.
    function branch(
        self,
        condition: Operand,
        then_block: int,
        else_block: int,
    ) -> void throws never {
        self.set_terminator(
            TerminatorBranch {
                condition: condition,
                then_block: then_block,
                else_block: else_block,
            },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::narrow_bind @ d9be6853b
    function narrow_bind(
        self,
        source: Operand,
        test_: TypeTest,
        destination: int,
        then_block: int,
        else_block: int,
    ) -> void throws never {
        self.set_terminator(
            TerminatorNarrowBind {
                source: source,
                test_: test_,
                destination: destination,
                then_block: then_block,
                else_block: else_block,
            },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::short_circuit @ d9be6853b
    // Emit a short-circuit `&&` / `||` / `??` terminator.
    function short_circuit(
        self,
        operand: Operand,
        kind: ShortCircuitKind,
        destination: Place,
        eval_rhs: int,
        join: int,
    ) -> void throws never {
        self.set_terminator(
            TerminatorShortCircuit {
                operand: operand,
                kind: kind,
                destination: destination,
                eval_rhs: eval_rhs,
                join: join,
            },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::switch @ d9be6853b
    // Emit a multi-way switch. If `exhaustive`, the switch covers every
    // possible discriminant value, so codegen may skip the last arm's
    // comparison.
    function switch(
        self,
        discriminant: Operand,
        arms: (SwitchKey, int)[],
        otherwise: int,
        exhaustive: bool,
        arm_names: (SwitchKey, string)[],
    ) -> void throws never {
        self.set_terminator(
            TerminatorSwitch {
                discriminant: discriminant,
                arms: arms,
                otherwise: otherwise,
                exhaustive: exhaustive,
                arm_names: arm_names,
            },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::return_ @ d9be6853b
    // Emit a return.
    function return_(self) -> void throws never {
        self.set_terminator(TerminatorReturn {});
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::call_with_type_args @ d9be6853b
    // Emit a call whose leading `ntypeargs` operands are runtime types,
    // followed by the ordinary value arguments. Also Rust's `call`, which is
    // this with `ntypeargs = 0`.
    function call_with_type_args(
        self,
        callee: Operand,
        args: Operand[],
        ntypeargs: int,
        destination: Place,
        target: int,
    ) -> void throws never {
        self.set_terminator(
            TerminatorCall {
                has_trace: false,
                argument_layout: null,
                callee: callee,
                args: args,
                ntypeargs: ntypeargs,
                destination: destination,
                target: target,
                unwind: self.current_unwind,
            },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::set_call_layout @ d9be6853b
    // Attach the checked argument layout to the call terminator just emitted.
    // The layout describes only callee parameters; one extra trailing operand
    // is the invocation's trace attachment.
    function set_call_layout(self, layout: root.types.CallLayout?) -> void throws never {
        let terminator = self.current_block_mut().terminator;
        match (terminator) {
            let call: TerminatorCall => {
                call.has_trace
                    = layout != null
                        && call.args.length() == call.ntypeargs + layout.value.length() + 1;
                call.argument_layout = layout;
            },
            let call: TerminatorVirtualCall => {
                call.has_trace
                    = layout != null
                        && call.args.length() == call.ntypeargs + layout.value.length() + 1;
                call.argument_layout = layout;
            },
            _ => baml.sys.panic("call layout requires a call terminator"),
        }
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::virtual_call @ d9be6853b
    // Resolve an interface method from the receiver's concrete type at
    // runtime.
    function virtual_call(
        self,
        iface: root.types.TyTemplateInterfaceConstraint,
        method: string,
        args: Operand[],
        ntypeargs: int,
        self_arg: int,
        destination: Place,
        target: int,
    ) -> void throws never {
        self.set_terminator(
            TerminatorVirtualCall {
                has_trace: false,
                argument_layout: null,
                iface: iface,
                method: method,
                args: args,
                ntypeargs: ntypeargs,
                self_arg: self_arg,
                destination: destination,
                target: target,
                unwind: self.current_unwind,
            },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::unreachable @ d9be6853b
    // Emit an unreachable terminator.
    function unreachable(self) -> void throws never {
        self.set_terminator(TerminatorUnreachable {});
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::throw @ d9be6853b
    // Emit a throw terminator (unwind with error value). Renamed: `throw` is
    // a BAML keyword.
    function throw_(self, value: Operand) -> void throws never {
        self.set_terminator(TerminatorThrow { value: value });
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::rethrow @ d9be6853b
    // Emit a rethrow terminator for a caught error value, carrying the
    // context its landing wrote into `context` (a landing local, never
    // captured).
    function rethrow(self, value: Operand, context: int) -> void throws never {
        self.set_terminator(
            TerminatorRethrow { value: value, context: operand_copy_local(context) },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::sys_op @ d9be6853b
    function sys_op(
        self,
        callee: Operand,
        args: Operand[],
        destination: Place,
        target: int,
    ) -> void throws never {
        self.set_terminator(
            TerminatorSysOp {
                callee: callee,
                args: args,
                destination: destination,
                target: target,
                unwind: self.current_unwind,
            },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::await_ @ d9be6853b
    // Emit an await.
    function await_(self, future: Place, destination: Place, target: int) -> void throws never {
        self.set_terminator(
            TerminatorAwait {
                future: future,
                destination: destination,
                target: target,
                unwind: self.current_unwind,
            },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::await_any @ d9be6853b
    // Emit an `await_any` terminator: suspend until the first of the
    // `futures` array settles and bind its `int` index into `destination`.
    function await_any(
        self,
        futures: Operand,
        destination: Place,
        target: int,
    ) -> void throws never {
        self.set_terminator(
            TerminatorAwaitAny {
                futures: futures,
                destination: destination,
                target: target,
                unwind: self.current_unwind,
            },
        );
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::spawn @ d9be6853b
    // Emit a spawn terminator: start `plan` as a new task and bind its
    // `Future<T, E>` handle into `future`. Renamed: `spawn` is a BAML
    // keyword.
    function spawn_(self, plan: Operand, future: Place, resume: int) -> void throws never {
        self.set_terminator(TerminatorSpawn { plan: plan, future: future, resume: resume });
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::build @ d9be6853b
    // Hand over the MIR function, under the identity the builder was opened
    // with. Panics if no blocks were created or any block is unterminated.
    function build(self) -> MirFunction throws never {
        if (self.blocks.length() == 0) {
            baml.sys.panic("function has no blocks");
        }
        self.assert_regions_closed();
        self.assert_terminated();
        MirFunction {
            arity: self.arity,
            span: self.span,
            identity: function_owner_into_identity(self.owner),
            kind: MirFunctionKindBytecode {
                value: MirFunctionBody { blocks: self.blocks, entry: 0, locals: self.locals },
            },
            lambdas: [],
            signature: null,
        }
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::build_body @ d9be6853b
    // Hand over just the `MirFunctionBody`: a let-binding initializer is a
    // body and never a `MirFunction` of its own.
    function build_body(self) -> MirFunctionBody throws never {
        if (self.blocks.length() == 0) {
            baml.sys.panic("let body has no blocks");
        }
        self.assert_regions_closed();
        self.assert_terminated();
        MirFunctionBody { blocks: self.blocks, entry: 0, locals: self.locals }
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::build @ d9be6853b
    // The loop `build` and `build_body` share: every block is terminated.
    function assert_terminated(self) -> void throws never {
        for (let block in self.blocks) {
            if (block.terminator == null) {
                baml.sys.panic(`block bb${block.id} is not terminated`);
            }
        }
    }

    // port: baml_compiler2_mir/src/builder.rs::MirBuilder::assert_regions_closed @ d9be6853b
    function assert_regions_closed(self) -> void throws never {
        if (self.current_unwind != null || self.current_handling != null || self.shield_depth != 0) {
            baml.sys.panic(
                `a handler (${self.current_unwind ?? "None"}, handling ${self.current_handling ?? "None"}) or a shield (depth ${self.shield_depth}) is still in force at build`,
            );
        }
    }
}
