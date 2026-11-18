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
