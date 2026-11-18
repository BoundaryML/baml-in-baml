// Stubs for MIR unit 3 (expressions): every function the unit owns
// (lower.rs 4530-8090 and 10165-10905 (the MIR plan's line numbers)), in namespace `mir`, with its BAML
// signature, and the types those signatures need that the unit's range
// declares. Each function
// panics until the unit ports it; the unit moves the types and functions
// into their files (`lower.baml`, `pretty.baml`, ...) and deletes this file.
//
// Conventions (bib/IDIOMS.md; ir.baml and lower.baml's headers):
// - `LoweringContext` methods are free functions taking `ctx:
//   LoweringContext` first. Methods of a type the unit declares stay
//   methods of its class; a method of a data enum (a union) is a free
//   function `<enum>_<method>`.
// - `Lowered<T>` / `Result<T, MirInternalError>` is `T throws
//   MirInternalError`; such a stub throws `MirInternalError` with its
//   "not ported" message instead of panicking (a stub that only panics
//   would warn that its `throws` is extraneous).
// - Ids (`Local`, `BlockId`, arena ids, locs, `*Ref`s, `SourceRoot`) are
//   `int`s; `Name` is `string`; parameters named after a BAML keyword (or
//   `root`) get `_` (`root_id`).

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::convert_binop @ d9be6853b
function convert_binop(op: root.ast.BinaryOp) -> BinOp? throws never {
    baml.sys.panic("convert_binop: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_binary @ d9be6853b
function lower_binary(
    ctx: LoweringContext,
    expr_id: int,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_binary: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::equality_uses_primitive_opcode @ d9be6853b
// Whether both operands of an `==`/`!=` are the *same* primitive type, so
// the specialized comparison opcode is equivalent to the `equals_equals`
// driver (value comparison matches the unoverridable native `Equals`).
// Literals widen to their base primitive; everything else (mixed primitives,
// `uint8array`, enums, classes, containers, unions, interfaces, `unknown`)
// goes through the driver.
function equality_uses_primitive_opcode(
    ctx: LoweringContext,
    lhs: int,
    rhs: int,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "equality_uses_primitive_opcode: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_equality_via_driver @ d9be6853b
function lower_equality_via_driver(
    ctx: LoweringContext,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_equality_via_driver: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_via_ops_driver @ d9be6853b
// Emit `dest = baml.ops.<driver>(args)`: the shared shape of the operator
// dispatch drivers (`equals_equals`, `__union_add`, …, `__union_neg`). A
// driver may yield (it can call user bytecode), so the call splits the block
// and lowering resumes in a fresh one. The call terminator's destination
// must be a `Place::Local` (the emitter stores its result with
// `emit_store_place`, which only handles locals), so a projection/capture ...
function lower_via_ops_driver(
    ctx: LoweringContext,
    driver: string,
    args: Operand[],
    result_ty: root.types.RuntimeTy,
    dest: Place,
) -> void throws never {
    baml.sys.panic("lower_via_ops_driver: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::arith_primitive @ d9be6853b
// Whether `ty` is a primitive the specialized opcodes handle directly ,
// int/bigint/float, plus `string` when `include_string` (binary `+`
// concatenates; unary `-` has no string form).
// A literal counts as its base; a union counts only when every member is
// the SAME primitive kind (`int | 3`): a mixed-kind union (`int | float`)
// would let emit pick a single-kind opcode for a value of the other kind ,  ...
function arith_primitive(
    lang: root.base.LangRoots,
    ty: root.types.RuntimeTy,
    include_string: bool,
) -> bool throws never {
    baml.sys.panic("arith_primitive: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::string_concat_parts @ d9be6853b
// The parts of the chain of string `+` that `expr_id` ends, left to
// right, or `None` when it joins fewer than three. The chain follows the
// left operand, which is how `a + b + c` and a template nest. A link that
// TIR folded to a constant is one part.
function string_concat_parts(ctx: LoweringContext, expr_id: int) -> int[]? throws MirInternalError {
    throw MirInternalError { message: "string_concat_parts: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_string_add @ d9be6853b
// Whether `lhs + rhs` at `expr_id` concatenates two strings at run time.
// Below the root of a chain, a link TIR folded to a constant does not.
function is_string_add(
    ctx: LoweringContext,
    expr_id: int,
    lhs: int,
    rhs: int,
    is_root: bool,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "is_string_add: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_string_ty @ d9be6853b
// Whether every value of `ty` is a string: a string, a string literal, the
// builtin `baml.String` class (`self` in its methods), or a union of them.
function is_string_ty(lang: root.base.LangRoots, ty: root.types.RuntimeTy) -> bool throws never {
    baml.sys.panic("is_string_ty: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::arithmetic_uses_primitive_opcode @ d9be6853b
// Whether both arithmetic operands are `Self::arith_primitive` (string
// included: `+` concatenates, and TIR rejects strings under the other ops
// before lowering).
function arithmetic_uses_primitive_opcode(
    ctx: LoweringContext,
    lhs: int,
    rhs: int,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "arithmetic_uses_primitive_opcode: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_arithmetic_via_driver @ d9be6853b
// Lower `a OP b` through the `baml.ops.__union_<op>` driver: the general
// case for operands whose static types don't pin a single impl. The driver
// resolves `<typeof a as Op<typeof b>>` at runtime and tail-calls it; its
// `unknown` result is the operator's value, re-typed by `dest`.
function lower_arithmetic_via_driver(
    ctx: LoweringContext,
    expr_id: int,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_arithmetic_via_driver: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ordering_uses_primitive_opcode @ d9be6853b
// Whether both ordering operands are primitives the comparison opcodes can
// *order*: int, bigint, float, string. That reduces to
// `Self::arith_primitive` with `include_string`: which also admits the
// spellings of those four (a literal, a same-kind union like `int | 3`, and
// the builtin companion classes): so the predicate is shared rather than
// duplicated. `exec_cmpop` orders exactly those four and treats every other ...
function ordering_uses_primitive_opcode(
    ctx: LoweringContext,
    lhs: int,
    rhs: int,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "ordering_uses_primitive_opcode: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ordering_method @ d9be6853b
// The `baml.ops.Compare` method an ordering operator dispatches, or `None`
// for any other operator. Single source for both the route test in
// `Self::lower_binary` and the dispatched method name, so the two cannot
// disagree about which operators are orderings.
function ordering_method(op: root.ast.BinaryOp) -> string? throws never {
    baml.sys.panic("ordering_method: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_ordering_via_virtual_call @ d9be6853b
// Lower `a OP b` for `<`/`<=`/`>`/`>=` through `baml.ops.Compare`, resolving
// the impl at runtime from the receiver's concrete type. Mirrors
// `Self::lower_arithmetic_via_driver`, but dispatches directly instead of
// through a `baml.ops` driver function.
function lower_ordering_via_virtual_call(
    ctx: LoweringContext,
    method: string,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_ordering_via_virtual_call: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::negate_uses_primitive_opcode @ d9be6853b
// Whether the negation operand is `Self::arith_primitive` (the `Neg`
// opcode has no string form).
function negate_uses_primitive_opcode(
    ctx: LoweringContext,
    operand: int,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "negate_uses_primitive_opcode: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_negate_via_driver @ d9be6853b
// Lower `-a` through the `baml.ops.__union_neg` driver (single dispatch on
// `a`'s runtime type). Mirrors `Self::lower_arithmetic_via_driver`.
function lower_negate_via_driver(
    ctx: LoweringContext,
    expr_id: int,
    operand: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_negate_via_driver: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_short_circuit @ d9be6853b
function lower_short_circuit(
    ctx: LoweringContext,
    _expr_id: int,
    lhs: int,
    rhs: int,
    dest: Place,
    is_and: bool,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_short_circuit: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_null_coalesce @ d9be6853b
// Lower `a ?? b`: evaluate `a`, if null then evaluate `b`, otherwise use `a`.
function lower_null_coalesce(
    ctx: LoweringContext,
    expr_id: int,
    lhs: int,
    rhs: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_null_coalesce: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_chain @ d9be6853b
// Lower `OptionalChain { expr }`: set up shared null exit for the entire chain.
function lower_optional_chain(
    ctx: LoweringContext,
    _expr_id: int,
    inner: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_optional_chain: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_assign_optional_chain @ d9be6853b
// Lower an assignment whose target is wrapped in `OptionalChain`.
// Sets up null guards, then emits the assignment only on the non-null path.
function lower_assign_optional_chain(
    ctx: LoweringContext,
    inner_target: int,
    value: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_assign_optional_chain: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_assign_op_optional_chain @ d9be6853b
// Lower a compound assignment (+=, etc.) whose target is wrapped in `OptionalChain`.
function lower_assign_op_optional_chain(
    ctx: LoweringContext,
    inner_target: int,
    op: root.ast.AssignOp,
    value: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_assign_op_optional_chain: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_assign_op @ d9be6853b
// Emit `place = place OP value`: the shared body of both `AssignOp`
// lowerings (plain and `?.`-chain targets). An arithmetic op whose
// operands aren't primitive routes through the `__union_*` driver, exactly
// like the binary-expression form (`v += w` and `v = v + w` must agree);
// everything else emits the raw opcode. Mixed `bigint OP= int` does NOT
// widen the int rhs on the opcode path: the specialized `*Bigint` opcodes ...
function emit_assign_op(
    ctx: LoweringContext,
    place: Place,
    target: int,
    op: root.ast.AssignOp,
    value: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "emit_assign_op: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_member_access @ d9be6853b
// Lower `obj?.member`: null-check obj, then access member or produce null.
function lower_optional_member_access(
    ctx: LoweringContext,
    expr_id: int,
    base: int,
    field: string,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_optional_member_access: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_index @ d9be6853b
// Lower `obj?.index`: null-check obj, then index or produce null.
function lower_optional_index(
    ctx: LoweringContext,
    base: int,
    index: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_optional_index: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_index_access @ d9be6853b
// Lower the access half of `base?.index`, with the base already known
// non-null. `?.[]` is the null-safe index operator, so a null *subscript*
// must short-circuit the whole expression to null (via `bb_null`) rather
// than abort the VM: mirroring the base guard. Only a nullable-typed index
// needs the extra check; a non-null index lowers straight to the access.
function lower_optional_index_access(
    ctx: LoweringContext,
    base_local: int,
    base_ty: root.types.RuntimeTy,
    index: int,
    dest: Place,
    bb_null: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_optional_index_access: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_call @ d9be6853b
// Lower `func?.(args)`: null-check callee, then call or produce null.
function lower_optional_call(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    args: int[],
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_optional_call: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_unary @ d9be6853b
function lower_unary(
    ctx: LoweringContext,
    expr_id: int,
    op: root.ast.UnaryOp,
    expr: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_unary: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_to_operand @ d9be6853b
function lower_to_operand(ctx: LoweringContext, expr_id: int) -> Operand throws MirInternalError {
    throw MirInternalError { message: "lower_to_operand: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_throw_operand @ d9be6853b
// The operand a `throw` reads. A binding is read in place, a captured one
// through its cell, never through a temp: a thrown catch binding must
// still read the caught error's local, or it would not be a rethrow (see
// `caught_error_context`).
function lower_throw_operand(
    ctx: LoweringContext,
    expr_id: int,
) -> Operand throws MirInternalError {
    throw MirInternalError { message: "lower_throw_operand: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::internal_error @ d9be6853b
// An internal inconsistency: lowering cannot produce code here, for a
// program the checker accepted. The caller returns it, which abandons the
// unit: `lower_function` / `lower_let_body` answer with the error
// instead of MIR, and the compile fails.
function internal_error(
    ctx: LoweringContext,
    message: string,
    expr_id: int,
) -> MirInternalError throws never {
    baml.sys.panic("internal_error: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::internal_error_here @ d9be6853b
// `Self::internal_error` for a site with no expression of its own ,
// located at whatever the builder is currently lowering.
function internal_error_here(
    ctx: LoweringContext,
    message: string,
) -> MirInternalError throws never {
    baml.sys.panic("internal_error_here: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_condition_operand @ d9be6853b
// Lowers a condition/logical-operand expression to an operand,
// applying the checker-recorded truthiness coercion (,
// `Adjust::Truthy`). A `bool`-typed condition records nothing and
// lowers exactly as before; the branch terminators stay strict-bool.
function lower_condition_operand(
    ctx: LoweringContext,
    condition: int,
) -> Operand throws MirInternalError {
    throw MirInternalError { message: "lower_condition_operand: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_condition @ d9be6853b
// A predicate needs control flow, not a materialized logical value.
function lower_condition(
    ctx: LoweringContext,
    condition: int,
    on_true: int,
    on_false: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_condition: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_if @ d9be6853b
function lower_if(
    ctx: LoweringContext,
    _expr_id: int,
    condition: int,
    then_branch: int,
    else_branch: int?,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_if: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_if_let @ d9be6853b
// MIR lowering for `if let PATTERN = SCRUTINEE { THEN } else { ELSE }`.
function lower_if_let(
    ctx: LoweringContext,
    _expr_id: int,
    pattern: int,
    scrutinee: int,
    then_branch: int,
    else_branch: int?,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_if_let: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_object @ d9be6853b
function lower_object(
    ctx: LoweringContext,
    expr_id: int,
    fields: root.ast.ObjectExprField[],
    spreads: root.ast.SpreadField[],
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_object: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_member_access @ d9be6853b
function lower_member_access(
    ctx: LoweringContext,
    expr_id: int,
    base: int,
    field: string,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_member_access: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_member_access_with_base @ d9be6853b
function lower_member_access_with_base(
    ctx: LoweringContext,
    expr_id: int,
    base: int,
    field: string,
    dest: Place,
    cached_base: Operand?,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_member_access_with_base: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_receiver_for_field_access @ d9be6853b
// The interface view a field access on `base` dispatches through when
// TIR recorded no virtual-field resolution for the access itself:
// the receiver-typed derivation (`interface_dispatch_target_for_expr_member`
// a written qualifier, a `Self`/bound-conjunction receiver, a
// `default.<field>` root). There is no third rung: guessing a view from
// the receiver's ERASED runtime type was never faithful (it dropped the ...
function interface_receiver_for_field_access(
    ctx: LoweringContext,
    base: int,
    field: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("interface_receiver_for_field_access: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_receiver_for_path_prefix @ d9be6853b
// The interface view the ladder segment after `prefix_idx` reads
// `member` through. TIR's RECORDED resolution for that segment comes
// first: it names the interface the access was checked against,
// including a union prefix's shared interface, which no derivation from
// the prefix's type can recover: then the receiver-typed derivation
// off the prefix segment's (or root's) type. No erased-`RuntimeTy` ...
function interface_receiver_for_path_prefix(
    ctx: LoweringContext,
    expr_id: int,
    prefix_idx: int,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("interface_receiver_for_path_prefix: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_receiver_for_path_prefix @ d9be6853b
function class_receiver_for_path_prefix(
    ctx: LoweringContext,
    expr_id: int,
    prefix_idx: int,
    current_ty: root.types.RuntimeTy,
) -> (root.types.DeclName, root.types.RuntimeTy[])? throws never {
    baml.sys.panic("class_receiver_for_path_prefix: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_index @ d9be6853b
function lower_index(
    ctx: LoweringContext,
    base: int,
    index: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_index: not ported (U3)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_index_access @ d9be6853b
// Emit the element read for `baseindex` from already-lowered operands.
// Shared by `lower_index` and `lower_optional_index_access` so a
// side-effectful index expression is evaluated exactly once.
function emit_index_access(
    ctx: LoweringContext,
    base_op: Operand,
    base_ty: root.types.RuntimeTy,
    index_op: Operand,
    index_ty: root.types.RuntimeTy,
    dest: Place,
) -> void throws never {
    baml.sys.panic("emit_index_access: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::index_kind_of @ d9be6853b
function index_kind_of(
    ctx: LoweringContext,
    base_ty: root.types.RuntimeTy,
) -> IndexKind throws never {
    baml.sys.panic("index_kind_of: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::unfold_index_receiver @ d9be6853b
function unfold_index_receiver(
    ctx: LoweringContext,
    ty: root.types.RuntimeTy,
    seen: root.types.DeclName[],
) -> root.types.RuntimeTy throws never {
    baml.sys.panic("unfold_index_receiver: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_map_call @ d9be6853b
function emit_map_call(
    ctx: LoweringContext,
    method: string,
    args: Operand[],
    dest: Place,
) -> void throws never {
    baml.sys.panic("emit_map_call: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_resolve_to_local @ d9be6853b
// If the expression is a simple local variable reference (single-segment path
// resolving to a known local), return its Local directly without allocating
// a temp or emitting a copy.
function try_resolve_to_local(ctx: LoweringContext, expr_id: int) -> int? throws never {
    baml.sys.panic("try_resolve_to_local: not ported (U3)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::operand_to_local @ d9be6853b
// Convert an operand to a local, materializing a temp if necessary.
function operand_to_local(
    ctx: LoweringContext,
    op: Operand,
    ty: root.types.RuntimeTy,
) -> int throws never {
    baml.sys.panic("operand_to_local: not ported (U3)")
}
