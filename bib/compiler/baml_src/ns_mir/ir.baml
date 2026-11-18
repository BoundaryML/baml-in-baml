// port: baml_compiler2_mir/src/ir.rs @ d9be6853b
//
// MIR data structures: functions as control flow graphs, basic blocks,
// statements, terminators, places, operands, rvalues and constants.
//
// Restructured (BAML forces it):
// - Ids are `int`s: `BlockId`, `Local`, and the declaration handles Rust
//   holds as `ClassRef`, `EnumRef`, `FunctionRef`, `GlobalRef` (and the
//   `FunctionLoc` / `LetLoc` of an identity). No root is served from an
//   interface here (`root.hir.is_served_from_interface`), so every `*Ref`
//   is its Source lane, an interned loc `int`, as in `root.hir_ty`'s
//   infer.baml and callable.baml. Where `root.hir_ty.layout` answers a
//   `DeclRefSource<int> | DeclRefExternal<int>` union, take the Source
//   lane's `value`.
// - `Name` is `string`, `Span` is `root.base.Span`, `Vec<u8>` is `int[]`.
// - MIR's type aliases are the `root.types` family members (the family is
//   monomorphic over `DeclName`): `RuntimeTy`, `RealizedTy`, `TyTemplate`.
//   Rust's `TyTemplateInterface` (the template interface constraint) is
//   `root.types.TyTemplateInterfaceConstraint`.
// - Data enums are unions of classes `<Enum><Variant>`; a single unnamed
//   payload is the field `value`. Multi-field tuple variants name their
//   fields: `Rvalue::Array(ty, elements)` is `RvalueArray { element_ty,
//   elements }`, `Rvalue::Map(k, v, entries)` is `RvalueMap { key_ty,
//   value_ty, entries }`. Fields named after a BAML keyword get a `_`
//   (`class_`, `interface_`). Methods of a union are free functions
//   `<enum>_<method>`; `Display` impls are `<type>_to_string`.
// - `CellId` (a `subenum` of `Place`) is the union `PlaceLocal |
//   PlaceCapture` of the very same classes, so a cell id is a place with no
//   conversion.
// - Vec fields the lowering mutates through `&mut` stay arrays, shared by
//   reference: `MirFunctionBody.blocks` / `.locals`, `BasicBlock.statements`,
//   `MirFunction.lambdas`. Where Rust moves one out with `mem::take` /
//   `mem::replace` (the builder handoff around a lambda, the optimizer's
//   statement rewrites), the port must put a fresh array in its place and
//   keep the old one; never alias the two.
// - `OptLevel`'s derived order is Zero < One < Two: `opt >= OptLevel::Two`
//   is `opt == OptLevel.Two`, `opt >= OptLevel::One` is `opt !=
//   OptLevel.Zero`. Its `Default` is `OptLevel.One`.
//
// Not ported: `MirFunctionId::display` (a lazily formatted wrapper; call
// `mir_function_id_display_name`), `Operand::constant` and `Place::local`
// (one-line constructors: write `OperandConstant { value: c }` and
// `PlaceLocal { value: l }`), the salsa `SalsaValue` impls and the derived
// `Debug`s.

// port: baml_compiler2_mir/src/ir.rs::OptLevel @ d9be6853b
// Optimization level controlling both MIR lowering and bytecode emission.
// - `Zero`: no inlining of user-named locals; compiler temps are still
//   optimized. Bytecode closely mirrors the source structure.
// - `One` (default): full emit optimization (inline single-use locals, copy
//   propagation, stack carry) but no MIR-level constant folding.
// - `Two`: everything in `One` plus MIR-level constant folding and advanced
//   transforms.
enum OptLevel {
    Zero,
    One,
    Two,
}

// port: baml_compiler2_mir/src/ir.rs::Landing @ d9be6853b
// What the VM lands in a handler block with: the frame slots it writes the
// caught error and its `baml.errors.Context` into before jumping there.
class Landing {
    error_local: int,
    context_local: int,
}

// port: baml_compiler2_mir/src/ir.rs::MirFunctionBody @ d9be6853b
// The bytecode body of a MIR function: blocks, locals, and the entry block.
class MirFunctionBody {
    // All basic blocks in the function.
    blocks: BasicBlock[],
    // Entry block index (always 0 by convention).
    entry: int,
    // Local variable declarations.
    locals: LocalDecl[],

    // port: baml_compiler2_mir/src/ir.rs::MirFunctionBody::block @ d9be6853b
    function block(self, id: int) -> BasicBlock throws never {
        self.blocks[id]
    }

    // port: baml_compiler2_mir/src/ir.rs::MirFunctionBody::local @ d9be6853b
    function local(self, id: int) -> LocalDecl throws never {
        self.locals[id]
    }

    // port: baml_compiler2_mir/src/ir.rs::MirFunctionBody::handlers @ d9be6853b
    // The handler blocks (those some block unwinds to), with what the VM
    // lands in each with. Restructured: the lazy iterator is an array.
    function handlers(self) -> (int, Landing)[] throws never {
        self.blocks.filter_map((block) -> {
            let landing = block.landing
                ?? return null;
            (block.id, landing)
        })
    }

    // port: baml_compiler2_mir/src/ir.rs::MirFunctionBody::is_handler @ d9be6853b
    function is_handler(self, block: int) -> bool throws never {
        self.blocks[block].landing != null
    }

    // port: baml_compiler2_mir/src/ir.rs::MirFunctionBody::unwind_error_locals @ d9be6853b
    // `(handler_block, error_local)` pairs, one per handler. Restructured:
    // the lazy iterator is an array.
    function unwind_error_locals(self) -> (int, int)[] throws never {
        self.handlers().map((handler) -> {
            (handler.0, handler.1.error_local)
        })
    }
}

// port: baml_compiler2_mir/src/ir.rs::MirFunctionKind @ d9be6853b
// Whether a MIR function has a bytecode body or is a Rust-bound builtin.
type MirFunctionKind = MirFunctionKindBytecode | MirFunctionKindBuiltin;

// Has a body that will be compiled to bytecode.
class MirFunctionKindBytecode {
    value: MirFunctionBody,
}

// Rust-bound builtin: `SysOp` (Io) or `NativeUnresolved` (Vm).
class MirFunctionKindBuiltin {
    value: root.ast.BuiltinKind,
}

// port: baml_compiler2_mir/src/ir.rs::RuntimeSignature @ d9be6853b
// Runtime signature metadata stamped onto a compiled `Function` object: the
// one shape both producers fill (emit for top-level declarations,
// `lower_lambda` for lambdas). Every type is the one the declaration has,
// not the one it spells: an unwritten position takes TIR's inferred type.
class RuntimeSignature {
    // Parameter names, in declaration order.
    param_names: string[],
    // Parameter types, parallel to `param_names`, as templates over the
    // callee frame's De Bruijn type-arg slots.
    param_types: root.types.TyTemplate[],
    // Whether each parameter has a default, parallel to `param_names`.
    param_has_default: bool[],
    // The return type, a template over the callee frame's type-arg slots.
    return_type: root.types.TyTemplate,
    // The throws type, a template; `never` is cannot-throw.
    throws_type: root.types.TyTemplate,
    // The declaration's joined `///` doc-comment lines, if any.
    docstring: string?,
    // Display strings for the generic type parameters (`T extends Bound`).
    display_type_params: string[],
    // The name of each type-argument slot in the callee frame, in slot order:
    // an owner's type parameters (an interface method's `Self` first), then
    // the function's own. A lambda's frame is the enclosing one.
    type_param_names: string[],
    // Interface bounds, parallel to the callee frame's generic slots.
    generic_param_bounds: RuntimeInterfaceBound[][],
    // Display strings for the parameter types, parallel to `param_names`.
    display_param_types: string[],
    // Display string for the return type.
    display_return_type: string,
}

// port: baml_compiler2_mir/src/ir.rs::RuntimeInterfaceBound @ d9be6853b
// Loc-free, templated form of one declared generic interface bound; emit
// converts it to the VM's `InterfaceBound`.
class RuntimeInterfaceBound {
    interface_: root.types.DeclName,
    args: root.types.TyTemplate[],
    assoc: (string, root.types.TyTemplate)[],
}

// port: baml_compiler2_mir/src/ir.rs::MirInternalError @ d9be6853b
// A point where lowering could not produce code for a CHECKED program: what
// the checker recorded and what lowering finds disagree, which is a compiler
// bug and never a user error. A function or initializer that hits one has
// no MIR; lowering answers with this instead, and the compile fails.
// Rust's `Result<_, MirInternalError>` (`Lowered<T>`) is `throws
// MirInternalError`: `?` is plain propagation.
class MirInternalError {
    message: string,
    // The source being lowered when the inconsistency was found.
    span: root.base.Span?,

    // port: baml_compiler2_mir/src/ir.rs::impl Display for MirInternalError @ d9be6853b
    implements baml.ToString {
        function to_string(self) -> string throws never {
            self.message
        }
    }
}

// port: baml_compiler2_mir/src/ir.rs::MirFunction @ d9be6853b
// A function represented as a control flow graph.
class MirFunction {
    // Parameter count.
    arity: int,
    // Source span for error reporting.
    span: root.base.Span?,
    // The function's identity: its declaration, or (for a lambda or a
    // tagged-template body closure) the function it was lowered inside plus
    // its ordinal there.
    identity: MirFunctionId,
    // Whether this function has bytecode or is a builtin.
    kind: MirFunctionKind,
    // Child lambda functions, indexed by `lambda_idx` in
    // `RvalueMakeClosure`.
    lambdas: MirFunction[],
    // Runtime signature metadata, set by `lower_lambda` for lambdas only.
    signature: RuntimeSignature?,
}

// port: baml_compiler2_mir/src/ir.rs::impl Display for BlockId @ d9be6853b
// `BlockId` is an `int`.
function block_id_to_string(id: int) -> string throws never {
    `bb${id}`
}

// port: baml_compiler2_mir/src/ir.rs::impl Display for Local @ d9be6853b
// `Local` is an `int`.
function local_to_string(local: int) -> string throws never {
    `_${local}`
}

// port: baml_compiler2_mir/src/ir.rs::LocalDecl @ d9be6853b
// Declaration of a local variable or temporary.
class LocalDecl {
    // Variable name (null for compiler temporaries).
    name: string?,
    // Type of this local.
    ty: root.types.RuntimeTy,
    // Source span where this local is declared.
    span: root.base.Span?,
    // Source span where this local is in scope (debugger metadata).
    scope_span: root.base.Span?,
    // Whether a nested closure captures this local: its slot then holds a
    // cell from the binding's `StatementKindFreshCell` onward (parameters
    // from frame entry), and every access goes through `PlaceDeref`. Set
    // when the local is declared, from HIR's capture analysis.
    is_captured: bool,
}

// port: baml_compiler2_mir/src/ir.rs::BasicBlock @ d9be6853b
// A sequence of statements ending with a terminator.
class BasicBlock {
    id: int,
    // Statements executed in order.
    statements: Statement[],
    // How this block exits (required after construction).
    terminator: Terminator?,
    // Source span covering this block.
    span: root.base.Span?,
    // Source span for the terminator.
    terminator_span: root.base.Span?,
    // The handler a throw or panic raised anywhere in this block unwinds to
    // (the lexically enclosing `catch` handler or `defer` landing pad), or
    // null to leave the frame. Fixed when the block is created.
    unwind: int?,
    // The innermost handler whose body this block is lexically part of: a
    // throw here chains onto that handler's error context. A handler block
    // is part of its own body.
    handling: int?,
    // Set on a handler block: what the VM lands here with.
    landing: Landing?,
    // Whether this block is part of a `defer` body, which runs shielded from
    // cancellation. Fixed at creation, like `unwind`.
    shielded: bool,

    // port: baml_compiler2_mir/src/ir.rs::BasicBlock::new @ d9be6853b
    // A new empty basic block.
    function new(id: int) -> BasicBlock throws never {
        BasicBlock {
            id: id,
            statements: [],
            terminator: null,
            span: null,
            terminator_span: null,
            unwind: null,
            handling: null,
            landing: null,
            shielded: false,
        }
    }

    // port: baml_compiler2_mir/src/ir.rs::BasicBlock::is_terminated @ d9be6853b
    function is_terminated(self) -> bool throws never {
        self.terminator != null
    }
}

// port: baml_compiler2_mir/src/ir.rs::Statement @ d9be6853b
// A single MIR statement (does not transfer control).
class Statement {
    kind: StatementKind,
    span: root.base.Span?,
}

// port: baml_compiler2_mir/src/ir.rs::LogLevel @ d9be6853b
// Log level for the `Log` intrinsic.
enum LogLevel {
    Info,
    Debug,
    Warn,
    Error,
}

// port: baml_compiler2_mir/src/ir.rs::IntrinsicOp @ d9be6853b
// Compiler intrinsic operations, lowered from calls to `$compiler_intrinsic`
// functions into `StatementKindIntrinsic` (inline side effects that do not
// split the control-flow graph).
type IntrinsicOp = IntrinsicOpLog
    | IntrinsicOpBindType
    | IntrinsicOpApplyTraceHook
    | IntrinsicOpBuiltinTraceHook;

// `log.info`, `log.debug`, `log.warn`, `log.error`: emit a `$baml_log` event.
class IntrinsicOpLog {
    value: LogLevel,
}

// Bind an exact runtime type value into this bytecode frame's type slot (a
// frame type-argument index, the space `TyTemplateTypeArgRef` reads).
class IntrinsicOpBindType {
    value: int,
}

// Resolve a declaration hook and begin the target after it returns.
class IntrinsicOpApplyTraceHook {
}

// Apply a standard mode hook directly, without a callable or Options value.
class IntrinsicOpBuiltinTraceHook {
    value: BuiltinTraceHook,
}

// port: baml_compiler2_mir/src/ir.rs::BuiltinTraceHook @ d9be6853b
enum BuiltinTraceHook {
    Hidden,
    Timing,
    Span,
    Rich,
    EmptySpan,
}

// port: baml_compiler2_mir/src/ir.rs::StatementKind @ d9be6853b
// The kind of a MIR statement.
type StatementKind = StatementKindAssign
    | StatementKindDrop
    | StatementKindFreshCell
    | StatementKindIntrinsic
    | StatementKindVirtualFieldStore
    | StatementKindNop;

// Assign a value to a place: `_1 = <rvalue>`.
class StatementKindAssign {
    destination: Place,
    value: Rvalue,
}

// Drop a value (run destructor if any).
class StatementKindDrop {
    value: Place,
}

// Give a captured local a new cell: the slot now points at a cell no closure
// has captured yet. Emitted where the binding is created, so each loop
// iteration's closures get their own cell. The new cell holds null, or with
// `carry_value` the value of the cell it replaces (a C-style `for` header
// binding copied into the next iteration). Only targets a local whose
// `is_captured` is set; every access of that local is dominated by one of
// its `FreshCell`s.
class StatementKindFreshCell {
    local: int,
    carry_value: bool,
}

// Compiler intrinsic: a void side effect (log, send event).
class StatementKindIntrinsic {
    op: IntrinsicOp,
    args: Operand[],
}

// Write an interface field on a receiver whose concrete type is not known
// statically: the store counterpart of `RvalueVirtualFieldAccess`.
class StatementKindVirtualFieldStore {
    iface: root.types.TyTemplateInterfaceConstraint,
    receiver: Operand,
    field_index: int,
    field: string,
    value: Operand,
}

// No-op (placeholder for removed statements).
class StatementKindNop {
}

// port: baml_compiler2_mir/src/ir.rs::SwitchKey @ d9be6853b
// One arm key of a `TerminatorSwitch`. A class arm names its declaration;
// whoever lays it into an image assigns the tag. A primitive kind's tag is a
// fixed constant.
type SwitchKey = SwitchKeyInt | SwitchKeyClass;

// A fixed integer: an int literal, an enum discriminant, or a primitive
// kind's tag.
class SwitchKeyInt {
    value: int,
}

// The tag of this class declaration (a class loc).
class SwitchKeyClass {
    value: int,
}

// port: baml_compiler2_mir/src/ir.rs::TypeTest @ d9be6853b
// What a type test decides membership in, as lowering determined it. A
// nominal test names its declaration.
type TypeTest = TypeTestClass | TypeTestEnum | TypeTestTemplate;

// An instance of `class_` at `args`; with none, any instance of it.
class TypeTestClass {
    class_: int,
    args: root.types.TyTemplate[],
}

// A value of this enum (an enum loc).
class TypeTestEnum {
    value: int,
}

// Any other type, decided against the template: never a class or an enum.
class TypeTestTemplate {
    value: root.types.TyTemplate,
}

// port: baml_compiler2_mir/src/ir.rs::TypeTest::for_each_type_arg_ref @ d9be6853b
// Every frame type-argument slot the test reads.
function type_test_for_each_type_arg_ref(
    test_: TypeTest,
    f: (int) -> void throws never,
) -> void throws never {
    match (test_) {
        let t: TypeTestClass => {
            for (let arg in t.args) {
                root.types.ty_template_for_each_type_arg_ref(arg, f);
            }
        },
        TypeTestEnum => {},
        let t: TypeTestTemplate => root.types.ty_template_for_each_type_arg_ref(t.value, f),
    }
}

// port: baml_compiler2_mir/src/ir.rs::TypeTest::template @ d9be6853b
// The type the test decides membership in, as a template: what a display
// shows.
function type_test_template(
    db: root.hir.Db,
    test_: TypeTest,
) -> root.types.TyTemplate throws never {
    match (test_) {
        let t: TypeTestClass => {
            root.types.TyTemplateClass {
                name: root.hir_ty.class_head(db, root.hir.DeclRefSource { value: t.class_ }),
                args: t.args,
            }
        },
        let t: TypeTestEnum => {
            root.types.TyEnum {
                name: root.hir_ty.enum_head(db, root.hir.DeclRefSource { value: t.value }),
            }
        },
        let t: TypeTestTemplate => t.value,
    }
}

// port: baml_compiler2_mir/src/ir.rs::Terminator @ d9be6853b
// How a basic block transfers control. Every basic block ends with exactly
// one terminator.
type Terminator = TerminatorGoto
    | TerminatorBranch
    | TerminatorNarrowBind
    | TerminatorSwitch
    | TerminatorReturn
    | TerminatorCall
    | TerminatorVirtualCall
    | TerminatorUnreachable
    | TerminatorSysOp
    | TerminatorSpawn
    | TerminatorAwait
    | TerminatorAwaitAny
    | TerminatorThrow
    | TerminatorRethrow
    | TerminatorShortCircuit;

// Unconditional jump to another block.
class TerminatorGoto {
    target: int,
}

// Conditional branch based on a boolean.
class TerminatorBranch {
    condition: Operand,
    then_block: int,
    else_block: int,
}

// Test one value and bind that same value to `destination` on success.
class TerminatorNarrowBind {
    source: Operand,
    test_: TypeTest,
    destination: int,
    then_block: int,
    else_block: int,
}

// Multi-way branch on an integer discriminant or a value's type tag.
class TerminatorSwitch {
    discriminant: Operand,
    // Arms: (key, target block).
    arms: (SwitchKey, int)[],
    // Default target if no arm matches.
    otherwise: int,
    // Whether the arms cover every possible value: the last arm's
    // comparison can then be skipped.
    exhaustive: bool,
    // Symbolic names for arm keys (debug metadata only).
    arm_names: (SwitchKey, string)[],
}

// Return from function; the return value is already in `_0`.
class TerminatorReturn {
}

// Call a function.
class TerminatorCall {
    // Whether the final `args` operand is an invocation trace attachment.
    has_trace: bool,
    // The value slots this site was checked against, leading type arguments
    // excluded. Null only for compiler-synthesized calls.
    argument_layout: root.types.CallLayout?,
    callee: Operand,
    // The first `ntypeargs` operands are type-argument values, followed by
    // the regular value arguments.
    args: Operand[],
    ntypeargs: int,
    destination: Place,
    // Block to jump to after the call returns normally.
    target: int,
    // Block to jump to if the call throws (for catch).
    unwind: int?,
}

// Open-world virtual interface-method dispatch: the implementation is
// resolved at run time from the concrete type of `args[ntypeargs +
// self_arg]` against `iface`, then invoked like a direct call.
class TerminatorVirtualCall {
    has_trace: bool,
    argument_layout: root.types.CallLayout?,
    // The interface to resolve against, pushed with `LoadType`.
    iface: root.types.TyTemplateInterfaceConstraint,
    // The interface method to dispatch.
    method: string,
    // `args[..ntypeargs]` are method-level type-argument values; the rest are
    // the value args in the method's declared parameter order.
    args: Operand[],
    ntypeargs: int,
    // Index among the value args of the one whose runtime type is `Self`.
    self_arg: int,
    destination: Place,
    target: int,
    unwind: int?,
}

// Unreachable code: reaching it is a compiler bug.
class TerminatorUnreachable {
}

// Invoke a sys-op and bind its return value into `destination`. Suspend
// point: control returns to the embedder.
class TerminatorSysOp {
    callee: Operand,
    args: Operand[],
    destination: Place,
    target: int,
    unwind: int?,
}

// Launch a `baml.spawn.Plan<T, E>` as a new task and bind its `Future<T, E>`
// into `future`. Launching never throws.
class TerminatorSpawn {
    plan: Operand,
    future: Place,
    resume: int,
}

// Await a future: suspend until its result is ready.
class TerminatorAwait {
    future: Place,
    destination: Place,
    target: int,
    unwind: int?,
}

// `baml.future.__await_any(futures)`: suspend until the first of an array of
// futures settles, then bind its `int` index (in input order).
class TerminatorAwaitAny {
    futures: Operand,
    destination: Place,
    target: int,
    unwind: int?,
}

// Throw an error value, unwinding to the nearest catch handler.
class TerminatorThrow {
    value: Operand,
}

// Re-throw a caught error value with the context it was caught with.
class TerminatorRethrow {
    value: Operand,
    // Its `baml.errors.Context`: the landing's context local.
    context: Operand,
}

// Short-circuit `&&` / `||` / `??`: on the short-circuit edge, assign
// `operand` to `destination` and go to `join`; otherwise go to `eval_rhs`,
// which assigns `destination` and goes to `join`.
class TerminatorShortCircuit {
    operand: Operand,
    kind: ShortCircuitKind,
    destination: Place,
    eval_rhs: int,
    join: int,
}

// port: baml_compiler2_mir/src/ir.rs::ShortCircuitKind @ d9be6853b
enum ShortCircuitKind {
    And,
    Or,
    Coalesce,
}

// port: baml_compiler2_mir/src/ir.rs::Terminator::successors @ d9be6853b
// All successor block ids.
function terminator_successors(terminator: Terminator) -> int[] throws never {
    match (terminator) {
        let t: TerminatorGoto => [t.target],
        let t: TerminatorBranch => [t.then_block, t.else_block],
        let t: TerminatorNarrowBind => [t.then_block, t.else_block],
        let t: TerminatorSwitch => {
            let succs = t.arms.map((arm) -> {
                arm.1
            });
            succs.push(t.otherwise);
            succs
        },
        TerminatorReturn => [],
        TerminatorUnreachable => [],
        let t: TerminatorSpawn => [t.resume],
        TerminatorCall { target: let target, unwind: let unwind }
            | TerminatorVirtualCall { target: let target, unwind: let unwind }
            | TerminatorSysOp { target: let target, unwind: let unwind }
            | TerminatorAwait { target: let target, unwind: let unwind }
            | TerminatorAwaitAny { target: let target, unwind: let unwind } =>
        {
            let succs = [target];
            if (unwind != null) {
                succs.push(unwind);
            }
            succs
        },
        TerminatorThrow | TerminatorRethrow => [],
        let t: TerminatorShortCircuit => [t.eval_rhs, t.join],
    }
}

// port: baml_compiler2_mir/src/ir.rs::IndexKind @ d9be6853b
// The kind of indexing operation.
enum IndexKind {
    // `arr[i]` (array or `uint8array`).
    Array,
    // `map[key]`.
    Map,
    Tuple,
}

// port: baml_compiler2_mir/src/ir.rs::Place @ d9be6853b
// A place in memory (lvalue). Cell access is explicit: a captured local's
// slot (`PlaceLocal`) and a closure capture slot (`PlaceCapture`) hold a
// cell pointer; the value behind one is `PlaceDeref`. Only a `MakeClosure`
// capture operand and a `FreshCell` target name the pointer bare.
type Place = PlaceLocal | PlaceField | PlaceIndex | PlaceCapture | PlaceDeref;

// A local variable: `_1`. For a captured local, its cell pointer.
class PlaceLocal {
    value: int,
}

// Field access: `_1.field_idx`.
class PlaceField {
    base: Place,
    field: int,
}

// Indexing: `_1[_2]`.
class PlaceIndex {
    base: Place,
    index: int,
    kind: IndexKind,
}

// The cell pointer in the `value`-th slot of the enclosing closure's
// captures. Only valid inside a lambda body.
class PlaceCapture {
    value: int,
}

// The value in a cell: `*_1`, `*capture[0]`.
class PlaceDeref {
    value: CellId,
}

// port: baml_compiler2_mir/src/ir.rs::CellId @ d9be6853b
// The identity of a cell: the `Place` variants that name a cell pointer.
type CellId = PlaceLocal | PlaceCapture;

// port: baml_compiler2_mir/src/ir.rs::CellId::local @ d9be6853b
// The local whose slot holds this cell's pointer, if it is a local's cell.
function cell_id_local(cell: CellId) -> int? throws never {
    match (cell) {
        let l: PlaceLocal => l.value,
        PlaceCapture => null,
    }
}

// port: baml_compiler2_mir/src/ir.rs::impl Display for CellId @ d9be6853b
function cell_id_to_string(cell: CellId) -> string throws never {
    match (cell) {
        let l: PlaceLocal => local_to_string(l.value),
        let c: PlaceCapture => `capture[${c.value}]`,
    }
}

// port: baml_compiler2_mir/src/ir.rs::Place::base_local @ d9be6853b
// The base local of this place, if it is rooted in a local. Transparent
// through `Deref`.
function place_base_local(place: Place) -> int? throws never {
    match (place) {
        let l: PlaceLocal => l.value,
        let f: PlaceField => place_base_local(f.base),
        let i: PlaceIndex => place_base_local(i.base),
        let d: PlaceDeref => cell_id_local(d.value),
        PlaceCapture => null,
    }
}

// port: baml_compiler2_mir/src/ir.rs::impl Display for Place @ d9be6853b
function place_to_string(place: Place) -> string throws never {
    match (place) {
        let l: PlaceLocal => local_to_string(l.value),
        let f: PlaceField => `${place_to_string(f.base)}.${f.field}`,
        let i: PlaceIndex => `${place_to_string(i.base)}[${local_to_string(i.index)}]`,
        let c: PlaceCapture => `capture[${c.value}]`,
        let d: PlaceDeref => `*${cell_id_to_string(d.value)}`,
    }
}

// port: baml_compiler2_mir/src/ir.rs::BoundFrame @ d9be6853b
// Where a bound method's frame type arguments come from.
type BoundFrame = BoundFrameReceiver | BoundFrameExplicit;

// Curried from the receiver at bind time: its class arguments (the VM's
// `MakeBoundMethod`).
class BoundFrameReceiver {
}

// Supplied by the reference site, one template per frame slot (the VM's
// `MakeGenericBoundMethod`).
class BoundFrameExplicit {
    value: root.types.TyTemplate[],
}

// port: baml_compiler2_mir/src/ir.rs::Rvalue @ d9be6853b
// A value computation: the right-hand side of an assignment.
type Rvalue = RvalueTraceHookSettings
    | RvalueUse
    | RvalueBinaryOp
    | RvalueUnaryOp
    | RvalueConcatStrings
    | RvalueArray
    | RvalueUint8Array
    | RvalueMap
    | RvalueAggregate
    | RvalueDiscriminant
    | RvalueTypeTag
    | RvalueLen
    | RvalueIsType
    | RvalueIsTypeTag
    | RvalueSatisfiesBound
    | RvalueMakeClosure
    | RvalueMakeBoundMethod
    | RvalueMakeVirtualBoundMethod
    | RvalueMakeVirtualFunction
    | RvalueVirtualFieldAccess
    | RvalueMakeGenericFunction
    | RvalueMakeGenericFunctionFromValue
    | RvalueLoadType
    | RvalueCurrentPackage;

// Detached settings, or null when hook selection is suppressed.
class RvalueTraceHookSettings {
    with_settings: bool,
}

// Use an operand directly.
class RvalueUse {
    value: Operand,
}

// Binary operation: `_1 + _2`.
class RvalueBinaryOp {
    op: BinOp,
    left: Operand,
    right: Operand,
}

// Unary operation: `!_1`, `-_1`.
class RvalueUnaryOp {
    op: UnaryOp,
    operand: Operand,
}

// Strings joined left to right in one step; always three or more parts.
class RvalueConcatStrings {
    value: Operand[],
}

// Create an array, with its static element type (Rust's first tuple field).
class RvalueArray {
    element_ty: root.types.TyTemplate,
    elements: Operand[],
}

// Create a byte array from a literal: `b"hello"`.
class RvalueUint8Array {
    value: int[],
}

// Create a map, with its static key and value types (Rust's first two tuple
// fields) and its (key, value) entries.
class RvalueMap {
    key_ty: root.types.TyTemplate,
    value_ty: root.types.TyTemplate,
    entries: (Operand, Operand)[],
}

// Create an aggregate (array, class instance, tuple). An enum variant is a
// `ConstantEnumVariant`, never an aggregate.
class RvalueAggregate {
    kind: AggregateKind,
    fields: Operand[],
}

// Read discriminant of enum/union: `discriminant(_1)`.
class RvalueDiscriminant {
    value: Place,
}

// Extract the runtime type tag from any value: `type_tag(_1)`.
class RvalueTypeTag {
    value: Place,
}

class RvalueLen {
    value: Place,
}

// Type check for pattern matching: `is_type(_1, Type)`.
class RvalueIsType {
    operand: Operand,
    test_: TypeTest,
}

// Coarse runtime type-tag test, used where lowering proved the tag
// equivalent to the element-precise test. `tag` is a `typetag` constant.
class RvalueIsTypeTag {
    operand: Operand,
    tag: int,
}

// Whether the type value `ty` satisfies the interface bound `bound` (a
// `let type T extends I = ...` statement's check); yields a bool.
class RvalueSatisfiesBound {
    ty: Operand,
    bound: root.types.TyTemplateInterfaceConstraint,
}

// Allocate a closure object from a child lambda function: `lambda_idx`
// indexes `MirFunction.lambdas` of the enclosing function.
class RvalueMakeClosure {
    lambda_idx: int,
    captures: Operand[],
    // Templates for enclosing generic type params captured by this closure.
    type_arg_templates: root.types.TyTemplate[],
}

// Create a bound method value from a method (a function loc) and its
// receiver.
class RvalueMakeBoundMethod {
    func: int,
    receiver: Operand,
    frame: BoundFrame,
}

// Create a bound method value for an interface method whose impl is unknown
// statically: the value analogue of `TerminatorVirtualCall`.
class RvalueMakeVirtualBoundMethod {
    iface: root.types.TyTemplateInterfaceConstraint,
    method: string,
    receiver: Operand,
    // Method-level type-argument templates from the reference site.
    type_args: root.types.TyTemplate[],
}

// Resolve an interface method to an unbound callable from a `Self` TYPE.
class RvalueMakeVirtualFunction {
    self_ty: root.types.TyTemplate,
    iface: root.types.TyTemplateInterfaceConstraint,
    method: string,
    // Method-level type-argument operands from the reference site.
    type_args: Operand[],
}

// Read an interface field from a receiver whose concrete type is not known
// statically. `field_index` is the field's position in the interface's
// declared field list; `field` is for display only.
class RvalueVirtualFieldAccess {
    iface: root.types.TyTemplateInterfaceConstraint,
    receiver: Operand,
    field_index: int,
    field: string,
}

// Create a generic-function value whose type arguments depend on the
// enclosing frame's type params.
class RvalueMakeGenericFunction {
    func: int,
    type_arg_templates: root.types.TyTemplate[],
}

// Specialize a runtime callable value with explicit type arguments.
class RvalueMakeGenericFunctionFromValue {
    value: Operand,
    type_arg_templates: root.types.TyTemplate[],
}

// Materialize a `Ty` from a `TyTemplate` (`reflect.Type.of<T>()`).
class RvalueLoadType {
    value: root.types.TyTemplate,
}

// Reify the package lexically enclosing this call site.
class RvalueCurrentPackage {
}

// port: baml_compiler2_mir/src/ir.rs::Rvalue::null_test @ d9be6853b
// For `x == null` / `x != null` (a `==`/`!=` with a `null` constant on either
// side): `x`, and whether the test is negated.
function rvalue_null_test(rvalue: Rvalue) -> (Operand, bool)? throws never {
    let binary = match (rvalue) {
        let b: RvalueBinaryOp => b,
        _ => {
            return null;
        },
    };
    let negate = match (binary.op) {
        BinOp.Eq => false,
        BinOp.Ne => true,
        _ => {
            return null;
        },
    };
    if (operand_is_null(binary.right)) {
        (binary.left, negate)
    } else if (operand_is_null(binary.left)) {
        (binary.right, negate)
    } else {
        null
    }
}

// port: baml_compiler2_mir/src/ir.rs::Rvalue::null_test::is_null @ d9be6853b
// The closure `is_null` of `null_test`.
function operand_is_null(operand: Operand) -> bool throws never {
    match (operand) {
        let c: OperandConstant => c.value is ConstantNull,
        _ => false,
    }
}

// port: baml_compiler2_mir/src/ir.rs::Rvalue::can_discard_with @ d9be6853b
// Whether an unused evaluation can be erased, including its operand reads.
// Allocation identity is unobservable when the result does not escape, but
// evaluating an initializer can still fail (checked arithmetic or indexing).
// A bounds proof (`in_bounds`) applies to this evaluation site, not to the
// whole local. Also `can_discard`, which is this with no bounds proof
// (`in_bounds = null`).
function rvalue_can_discard(
    rvalue: Rvalue,
    in_bounds: ((Place) -> bool throws never)? = null,
) -> bool throws never {
    let operand = (op: Operand) -> bool {
        match (op) {
            OperandConstant => true,
            let c: OperandCopy => can_discard_read(c.value, in_bounds),
            let m: OperandMove => can_discard_read(m.value, in_bounds),
        }
    };
    match (rvalue) {
        let r: RvalueUse => operand(r.value),
        let r: RvalueBinaryOp => {
            let pure_op = match (r.op) {
                BinOp.Eq | BinOp.Ne | BinOp.Lt | BinOp.Le | BinOp.Gt | BinOp.Ge => true,
                BinOp.BitAnd | BinOp.BitOr | BinOp.BitXor => true,
                _ => false,
            };
            pure_op && operand(r.left) && operand(r.right)
        },
        let r: RvalueUnaryOp => {
            (r.op == UnaryOp.Not || r.op == UnaryOp.Truthy) && operand(r.operand)
        },
        let r: RvalueIsType => operand(r.operand),
        let r: RvalueIsTypeTag => operand(r.operand),
        let r: RvalueSatisfiesBound => operand(r.ty),
        let r: RvalueTypeTag => can_discard_read(r.value, in_bounds),
        let r: RvalueDiscriminant => can_discard_read(r.value, in_bounds),
        let r: RvalueLen => can_discard_read(r.value, in_bounds),
        RvalueTraceHookSettings => false,
        RvalueLoadType | RvalueCurrentPackage | RvalueUint8Array | RvalueMakeGenericFunction => true,
        // Joining strings cannot fail.
        let r: RvalueArray => r.elements.every(operand),
        let r: RvalueConcatStrings => r.value.every(operand),
        let r: RvalueAggregate => r.fields.every(operand),
        let r: RvalueMap => {
            r.entries.every((entry) -> {
                operand(entry.0) && operand(entry.1)
            })
        },
        let r: RvalueMakeClosure => r.captures.every(operand),
        let r: RvalueMakeBoundMethod => operand(r.receiver),
        // The type checker proves the implements rule and total field links
        // (E0124). Resolution failure is a VM internal invariant violation,
        // not a BAML panic; the receiver can still trap.
        let r: RvalueVirtualFieldAccess => operand(r.receiver),
        RvalueMakeVirtualBoundMethod
            | RvalueMakeVirtualFunction
            | RvalueMakeGenericFunctionFromValue =>
        {
            false
        },
    }
}

// port: baml_compiler2_mir/src/ir.rs::Rvalue::can_discard_with::read @ d9be6853b
// Whether reading `place` cannot fail.
function can_discard_read(
    place: Place,
    in_bounds: ((Place) -> bool throws never)?,
) -> bool throws never {
    match (place) {
        // A deref load cannot fail: every access of a captured local is
        // dominated by its `FreshCell` (`verify_mir`), so the cell exists.
        PlaceLocal | PlaceCapture | PlaceDeref => true,
        // A fixed field projection is type-checked, not a user accessor. An
        // indexing operation in its base still needs its own proof.
        let f: PlaceField => can_discard_read(f.base, in_bounds),
        let i: PlaceIndex => {
            can_discard_read(i.base, in_bounds) && in_bounds != null && in_bounds(place)
        },
    }
}

// port: baml_compiler2_mir/src/ir.rs::AggregateKind @ d9be6853b
// The kind of aggregate being constructed.
type AggregateKind = AggregateKindArray | AggregateKindClass | AggregateKindTuple;

class AggregateKindArray {
}

// A class instance (`class_`, a class loc, is the declaration the literal
// constructs). `type_arg_templates` is non-empty only for generic class
// instantiations, one per class-level type parameter in De Bruijn order.
class AggregateKindClass {
    class_: int,
    type_arg_templates: root.types.TyTemplate[],
}

class AggregateKindTuple {
    element_templates: root.types.TyTemplate[],
}

// port: baml_compiler2_mir/src/ir.rs::Operand @ d9be6853b
// An operand: either a place (read) or a constant.
type Operand = OperandCopy | OperandMove | OperandConstant;

// Copy value from place.
class OperandCopy {
    value: Place,
}

// Move value from place (consume it).
class OperandMove {
    value: Place,
}

// A constant value.
class OperandConstant {
    value: Constant,
}

// port: baml_compiler2_mir/src/ir.rs::Operand::copy_local @ d9be6853b
// A copy operand of a local.
function operand_copy_local(local: int) -> Operand throws never {
    OperandCopy { value: PlaceLocal { value: local } }
}

// port: baml_compiler2_mir/src/ir.rs::Constant @ d9be6853b
// A constant value in MIR.
type Constant = ConstantInt
    | ConstantBigint
    | ConstantFloat
    | ConstantString
    | ConstantBool
    | ConstantNull
    | ConstantOmittedArg
    | ConstantFunction
    | ConstantGlobalItem
    | ConstantGenericFunction
    | ConstantEnumVariant;

class ConstantInt {
    value: int,
}

class ConstantBigint {
    value: bigint,
}

class ConstantFloat {
    value: float,
}

class ConstantString {
    value: string,
}

class ConstantBool {
    value: bool,
}

class ConstantNull {
}

// Internal sentinel for omitted defaulted function parameters; user code
// cannot construct it, and callee-entry default prologues replace it.
class ConstantOmittedArg {
}

// A function reference (a function loc); only for items that ARE functions.
class ConstantFunction {
    value: int,
}

// A top-level `let` read (a let loc): the value `$init` stored in the
// binding's global slot, emitted as a plain `LoadGlobal`.
class ConstantGlobalItem {
    value: int,
}

// A generic function instantiated with concrete type arguments, emitted as a
// pooled, interned `Object::GenericFunction`.
class ConstantGenericFunction {
    func: int,
    type_args: root.types.RealizedTy[],
}

// An enum variant value: the enum's declaration (an enum loc) and the
// variant's index in declared order.
class ConstantEnumVariant {
    enum_ref: int,
    index: int,
}

// port: baml_compiler2_mir/src/ir.rs::MirFunctionId @ d9be6853b
// A function's identity: its declaration (a function loc), or, for a lambda
// or a tagged-template body closure, the owner it was lowered inside plus its
// ordinal there.
type MirFunctionId = MirFunctionIdDeclared | MirFunctionIdSynthetic;

class MirFunctionIdDeclared {
    value: int,
}

// The `ordinal`-th synthetic function of its `kind` lowered inside `parent`.
class MirFunctionIdSynthetic {
    parent: FunctionOwner,
    kind: SyntheticKind,
    ordinal: int,
}

// port: baml_compiler2_mir/src/ir.rs::SyntheticKind @ d9be6853b
// What a synthetic function was lowered from.
enum SyntheticKind {
    // A lambda expression.
    Lambda,
    // A tagged template's body closure.
    Tagged,
}

// port: baml_compiler2_mir/src/ir.rs::FunctionOwner @ d9be6853b
// Where a function body is lowered: a declared function (a function loc), a
// top-level `let` initializer (a let loc; lowered as a body, it only owns
// synthetic functions), or a synthetic function.
type FunctionOwner = FunctionOwnerFunction | FunctionOwnerLet | FunctionOwnerSynthetic;

class FunctionOwnerFunction {
    value: int,
}

class FunctionOwnerLet {
    value: int,
}

class FunctionOwnerSynthetic {
    value: MirFunctionId,
}

// port: baml_compiler2_mir/src/ir.rs::MirFunctionId::display_name @ d9be6853b
// The name this function displays as: the declaration's canonical display
// name, or the synthetic spelling `<lambda(owner, i)>` /
// `<tagged(owner, i)>` under an empty package segment.
function mir_function_id_display_name(db: root.hir.Db, id: MirFunctionId) -> string throws never {
    match (id) {
        let d: MirFunctionIdDeclared => {
            definition_display_name(db, root.hir.DefinitionFunction { value: d.value })
        },
        MirFunctionIdSynthetic => `.${mir_function_id_short_name(db, id)}`,
    }
}

// port: baml_compiler2_mir/src/ir.rs::MirFunctionId::short_name @ d9be6853b
// The spelling a nested synthetic function names its owner by: the
// declaration's link-name tail (`definition_short_name`), or the owner's own
// synthetic spelling.
function mir_function_id_short_name(db: root.hir.Db, id: MirFunctionId) -> string throws never {
    match (id) {
        let d: MirFunctionIdDeclared => {
            definition_short_name(db, root.hir.DefinitionFunction { value: d.value })
        },
        let s: MirFunctionIdSynthetic => {
            let kind = match (s.kind) {
                SyntheticKind.Lambda => "lambda",
                SyntheticKind.Tagged => "tagged",
            };
            `<${kind}(${function_owner_short_name(db, s.parent)}, ${s.ordinal})>`
        },
    }
}

// port: baml_compiler2_mir/src/ir.rs::FunctionOwner::short_name @ d9be6853b
// The spelling a synthetic function names this owner by.
function function_owner_short_name(db: root.hir.Db, owner: FunctionOwner) -> string throws never {
    match (owner) {
        let f: FunctionOwnerFunction => {
            definition_short_name(db, root.hir.DefinitionFunction { value: f.value })
        },
        let l: FunctionOwnerLet => {
            definition_short_name(db, root.hir.DefinitionLet { value: l.value })
        },
        let s: FunctionOwnerSynthetic => mir_function_id_short_name(db, s.value),
    }
}

// port: baml_compiler2_mir/src/ir.rs::FunctionOwner::into_identity @ d9be6853b
// The identity of a function built under this owner. A `let` initializer is
// lowered as a body, so it never builds one.
function function_owner_into_identity(owner: FunctionOwner) -> MirFunctionId throws never {
    match (owner) {
        let f: FunctionOwnerFunction => MirFunctionIdDeclared { value: f.value },
        let s: FunctionOwnerSynthetic => s.value,
        FunctionOwnerLet => {
            baml.sys.panic("a top-level let initializer is lowered as a body, never built")
        },
    }
}

// port: baml_compiler2_mir/src/ir.rs::BinOp @ d9be6853b
// Binary operations.
enum BinOp {
    // Arithmetic
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    // Comparison
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    // Bitwise
    BitAnd,
    BitOr,
    BitXor,
    Shl,
    Shr,
}

// port: baml_compiler2_mir/src/ir.rs::impl Display for BinOp @ d9be6853b
function bin_op_to_string(op: BinOp) -> string throws never {
    match (op) {
        BinOp.Add => "+",
        BinOp.Sub => "-",
        BinOp.Mul => "*",
        BinOp.Div => "/",
        BinOp.Mod => "%",
        BinOp.Eq => "==",
        BinOp.Ne => "!=",
        BinOp.Lt => "<",
        BinOp.Le => "<=",
        BinOp.Gt => ">",
        BinOp.Ge => ">=",
        BinOp.BitAnd => "&",
        BinOp.BitOr => "|",
        BinOp.BitXor => "^",
        BinOp.Shl => "<<",
        BinOp.Shr => ">>",
    }
}

// port: baml_compiler2_mir/src/ir.rs::UnaryOp @ d9be6853b
// Unary operations.
enum UnaryOp {
    Not,
    Neg,
    // Truthiness coercion: `bool(value)`, false for `false`, `null`, zero,
    // and empty string/list/map/bytes; true otherwise.
    Truthy,
}

// port: baml_compiler2_mir/src/ir.rs::impl Display for UnaryOp @ d9be6853b
function unary_op_to_string(op: UnaryOp) -> string throws never {
    match (op) {
        UnaryOp.Not => "!",
        UnaryOp.Neg => "-",
        UnaryOp.Truthy => "truthy ",
    }
}
