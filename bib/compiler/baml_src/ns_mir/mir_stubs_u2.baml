// Stubs for MIR unit 2 (calls, dispatch): every function the unit owns
// (lower.rs 3276-4316, 8091-10164 and 10906-11903 (the MIR plan's line numbers)), in namespace `mir`, with its BAML
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

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_interface_dispatch @ d9be6853b
// BEP-044: emit a type-tag switch over the implementor set when calling
// a method on an interface-typed receiver. Each arm invokes the
// concrete implementor's `<class>.<method>` as a static call.
function try_lower_interface_dispatch(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    base: int,
    method: string,
    args: int[],
    dest: Place,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "try_lower_interface_dispatch: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::structural_witness @ d9be6853b
function structural_witness(
    ctx: LoweringContext,
    self_ty: root.types.Ty,
    interface_: root.types.DeclName,
) -> root.types.StructuralInterface? throws never {
    baml.sys.panic("structural_witness: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::structural_function_rvalue @ d9be6853b
function structural_function_rvalue(
    ctx: LoweringContext,
    self_ty: root.types.Ty,
    interface_: root.types.DeclName,
    method: string,
) -> Rvalue? throws never {
    baml.sys.panic("structural_function_rvalue: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_direct_structural_call @ d9be6853b
function emit_direct_structural_call(
    ctx: LoweringContext,
    func: int,
    args: Operand[],
    ntypeargs: int,
    layout: root.types.CallLayout?,
    result_ty: root.types.RuntimeTy,
    dest: Place,
) -> void throws never {
    baml.sys.panic("emit_direct_structural_call: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_call @ d9be6853b
// Emit an interface call, directly for a closed structural witness and
// otherwise through `Terminator::VirtualCall`. The receiver is the first
// value argument. Always returns `true`: the type checker has proved the
// receiver implements the interface.
function emit_virtual_call(
    ctx: LoweringContext,
    recv_local: int,
    iface_tn: root.types.DeclName,
    iface_type_args: root.types.Ty[],
    iface_assoc: (string, root.types.Ty)[],
    method: string,
    expr_id: int,
    args: int[],
    dest: Place,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "emit_virtual_call: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_call_with_value_operands @ d9be6853b
// Emit an open-world `Terminator::VirtualCall` over lowered value
// operands: `value_ops` in the method's declared parameter order, of
// which `value_opsself_arg` is the one the VM derives `Self` from.
// The method's own type arguments are lowered here, off the interface
// that DECLARES the method.
function emit_virtual_call_with_value_operands(
    ctx: LoweringContext,
    self_arg: int,
    value_ops: Operand[],
    iface_tn: root.types.DeclName,
    iface_type_args: root.types.Ty[],
    iface_assoc: (string, root.types.Ty)[],
    method: string,
    expr_id: int,
    dest: Place,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "emit_virtual_call_with_value_operands: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_call_with_operands @ d9be6853b
// Emit the `VirtualCall` terminator itself, given operands that are already
// lowered. Shared by the method-call funnel (`Self::emit_virtual_call`,
// which builds its operands from an AST call) and by operator lowering,
// which has no call expression to read arguments from.
function emit_virtual_call_with_operands(
    ctx: LoweringContext,
    iface: root.types.TyTemplateInterfaceConstraint,
    method: string,
    args: Operand[],
    ntypeargs: int,
    self_arg: int,
    argument_layout: root.types.CallLayout?,
    result_ty: root.types.RuntimeTy,
    dest: Place,
) -> void throws never {
    baml.sys.panic("emit_virtual_call_with_operands: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_bound_method @ d9be6853b
// Emit an `Rvalue::MakeVirtualBoundMethod` binding `method` of the interface
// `view` on `recv_local`: the value analogue of `Self::emit_virtual_call`.
// The declaring-interface narrowing and the runtime-converted interface
// template mirror the call form; the VM resolves the receiver's impl at bind
// time and produces a `BoundMethod` carrying the impl's realized frame.
function emit_virtual_bound_method(
    ctx: LoweringContext,
    expr_id: int,
    recv_local: int,
    view: InterfaceTypeView,
    method: string,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "emit_virtual_bound_method: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_receiver_root @ d9be6853b
function path_receiver_root(
    ctx: LoweringContext,
    expr_id: int,
    name: string,
) -> Place? throws never {
    baml.sys.panic("path_receiver_root: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_path_receiver_to_local @ d9be6853b
// Lower a receiver path, excluding its method or field, to a local.
// Locals are reused; captures and field chains are materialized into temps.
function lower_path_receiver_to_local(
    ctx: LoweringContext,
    callee: int,
    receiver_segments: string[],
    recv_root: Place,
) -> int throws MirInternalError {
    throw MirInternalError { message: "lower_path_receiver_to_local: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_method_shape @ d9be6853b
// The frame shape of an interface's method, wherever the interface is
// declared: whether it takes a `self` receiver, and how its generic
// frame `Self ++ interface generics ++ own generics` divides
// (associated types are not slots). `None` when the interface declares
// no such method.
function interface_method_shape(
    ctx: LoweringContext,
    interface_: int,
    method: string,
) -> InterfaceMethodShape? throws never {
    baml.sys.panic("interface_method_shape: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_interface_field_access @ d9be6853b
// Read `field` through an interface view whose receiver's concrete type is not
// known statically, as an open-world `Rvalue::VirtualFieldAccess`.
function try_lower_interface_field_access(
    ctx: LoweringContext,
    recv_local: int,
    iface_tn: root.types.DeclName,
    iface_type_args: root.types.Ty[],
    iface_assoc: (string, root.types.Ty)[],
    field: string,
    dest: Place,
) -> bool throws never {
    baml.sys.panic("try_lower_interface_field_access: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_field_wire_target @ d9be6853b
// What a virtual access to `field` through `view` puts on the wire: `view` narrowed
// to the interface that *declares* `field`, lowered to the constraint template the
// instruction carries, paired with the field's index in that interface.
function virtual_field_wire_target(
    ctx: LoweringContext,
    view: InterfaceTypeView,
    field: string,
) -> (root.types.TyTemplateInterfaceConstraint, int)? throws never {
    baml.sys.panic("virtual_field_wire_target: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_virtual_field_access @ d9be6853b
// Emit the open-world read of `field` off `recv_local` through `iface`.
function emit_virtual_field_access(
    ctx: LoweringContext,
    recv_local: int,
    iface: root.types.TyTemplateInterfaceConstraint,
    field_index: int,
    field: string,
    dest: Place,
) -> void throws never {
    baml.sys.panic("emit_virtual_field_access: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_field_assign_view @ d9be6853b
// The interface view an assignment *target* `recv.field` resolves through, when
// the field is served by an interface rather than a slot on the receiver's own
// class.
function virtual_field_assign_view(
    ctx: LoweringContext,
    target: int,
    base: int,
    field: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("virtual_field_assign_view: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_field_assign_target @ d9be6853b
// The `VirtualFieldTarget` an assignment target denotes when it is an
// interface-field access, for either spelling: `a.b` reaches MIR as a
// multi-segment `Path` when its root is a local, and as a `MemberAccess` when the
// base is a general expression. `None` for an ordinary place.
function virtual_field_assign_target(
    ctx: LoweringContext,
    target: int,
) -> VirtualFieldTarget? throws MirInternalError {
    throw MirInternalError { message: "virtual_field_assign_target: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_virtual_field_assign @ d9be6853b
// Lower `recv.field = value` where `recv.field` is an interface field, as a
// `StatementKind::VirtualFieldStore`. Returns `false` when the target is not
// a virtual interface-field access, leaving the ordinary `Place` path to it.
function try_lower_virtual_field_assign(
    ctx: LoweringContext,
    target: int,
    value: int,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "try_lower_virtual_field_assign: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_virtual_field_assign_op @ d9be6853b
// `recv.field op= value` on an interface field: read through the virtual
// access, apply the operator, then write back through the virtual store.
// A `Place`-based read-modify-write is unavailable for the same reason as
// `Self::try_lower_virtual_field_assign`.
function try_lower_virtual_field_assign_op(
    ctx: LoweringContext,
    target: int,
    op: root.ast.AssignOp,
    value: int,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "try_lower_virtual_field_assign_op: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_interface_field_store @ d9be6853b
// Write `value` to `field` through an interface view: the store counterpart of
// `Self::emit_virtual_field_access`.
function emit_interface_field_store(
    ctx: LoweringContext,
    target: VirtualFieldTarget,
    value: Operand,
) -> void throws never {
    baml.sys.panic("emit_interface_field_store: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_ty_projections @ d9be6853b
// Reduce every determinable associated-type projection in `ty` to a fixpoint, via the
// canonical `normalize` (the checker's own reduction: no parallel resolver).
function resolve_ty_projections(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> root.types.Ty throws never {
    baml.sys.panic("resolve_ty_projections: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::hir_facts @ d9be6853b
// The `hir_ty` facts oracle over this context's carried bounds - the
// ONE alias/projection/subtype authority (aliases resolve through
// definitions directly; no precomputed map).
function hir_facts(ctx: LoweringContext) -> root.hir_ty.Facts throws never {
    baml.sys.panic("hir_facts: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_projection_bounds @ d9be6853b
// The declared bounds of an *unreduced* (symbolic-base) projection
// `(base as I).member`: interface `I`'s `type member extends J & K`, realized.
function resolve_projection_bounds(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> root.types.Ty[] throws never {
    baml.sys.panic("resolve_projection_bounds: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_closure_type_name_views @ d9be6853b
function interface_closure_type_name_views(
    ctx: LoweringContext,
    iface_tn: root.types.DeclName,
    iface_type_args: root.types.Ty[],
    iface_assoc: (string, root.types.Ty)[],
) -> InterfaceTypeView[]? throws never {
    baml.sys.panic("interface_closure_type_name_views: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_implements_target_view @ d9be6853b
function resolve_implements_target_view(
    ctx: LoweringContext,
    target_store: root.hir.TypeRefStore,
    target: int,
    associated_type_bindings: root.hir.AssociatedTypeBindingData[],
    class_loc: int,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("resolve_implements_target_view: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::implements_block_iface_target @ d9be6853b
// BEP-044: when the enclosing function is the override declared
// inside an `implements I { ... }` block, return `I`'s target type
// expression. `None` for free functions, top-level class methods,
// and interface default-method bodies.
function implements_block_iface_target(
    ctx: LoweringContext,
) -> root.hir.MethodInterfaceTarget? throws never {
    baml.sys.panic("implements_block_iface_target: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::implements_subject_tir_ty @ d9be6853b
// The enclosing implements-block's subject type: what `Self` denotes in
// this impl method's body, off the uniform
// `impl_self_ty` surface
// (the in-body-vs-free distinction is HIR's business, not MIR's).
// `None` when the enclosing function is not an impl method.
function implements_subject_tir_ty(ctx: LoweringContext) -> root.types.Ty? throws never {
    baml.sys.panic("implements_subject_tir_ty: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::body_self_tir_ty @ d9be6853b
// What a *body-position* `Self` denotes in the function being lowered ,
// the rigid `Self` type variable for an interface-owned body (carried at
// frame slot 0), or the enclosing implements-block's subject, statically
// substituted. Mirrors TIR's `body_self_ty` (`inference.rs`), so MIR's
// re-lowering of written body type expressions (explicit type args,
// pattern annotations) resolves `Self` to the same type TIR checked.
function body_self_tir_ty(ctx: LoweringContext) -> root.types.Ty? throws never {
    baml.sys.panic("body_self_tir_ty: not ported (U2)")
}
