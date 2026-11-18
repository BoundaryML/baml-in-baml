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

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_dispatch_target_for_member @ d9be6853b
// The interface *view* a receiver of this static type dispatches through, for
// the `member` being accessed: its own for an existential, its bound's for a
// type variable, its resolved bound's for a projection. `None` for concrete
// receivers: their providing interface is resolved by
// `Self::dispatch_target_for_concrete`.
function interface_dispatch_target_for_member(
    ctx: LoweringContext,
    ty: root.types.Ty,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("interface_dispatch_target_for_member: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::canonical_dispatch_view @ d9be6853b
function canonical_dispatch_view(
    ctx: LoweringContext,
    ty: root.types.Ty,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("canonical_dispatch_view: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_dispatch_target_for_expr_member @ d9be6853b
// The interface view an *expression* receiver dispatches through for `member`
// see `Self::interface_dispatch_target_for_member`.
function interface_dispatch_target_for_expr_member(
    ctx: LoweringContext,
    expr_id: int,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("interface_dispatch_target_for_expr_member: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::allows_interface_method_dispatch @ d9be6853b
// Member lookup has already chosen fields and inherent methods. Only
// interface methods (or accesses without a resolution record) may use
// the type-based interface dispatch fallback.
function allows_interface_method_dispatch(ctx: LoweringContext, access: int) -> bool throws never {
    baml.sys.panic("allows_interface_method_dispatch: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::dispatch_target_for_member_access @ d9be6853b
// The interface view used to lower a member-access expression. Optional
// member access has already guarded the null branch before the member is
// evaluated, so dispatch must use the non-null receiver type.
function dispatch_target_for_member_access(
    ctx: LoweringContext,
    access: int,
    base: int,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("dispatch_target_for_member_access: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::source_param_interface_view_for_expr @ d9be6853b
function source_param_interface_view_for_expr(
    ctx: LoweringContext,
    expr_id: int,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("source_param_interface_view_for_expr: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::source_param_interface_view_for_name_at @ d9be6853b
function source_param_interface_view_for_name_at(
    ctx: LoweringContext,
    expr_id: int,
    name: string,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("source_param_interface_view_for_name_at: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::source_param_interface_view_for_binding @ d9be6853b
function source_param_interface_view_for_binding(
    ctx: LoweringContext,
    name: string,
    binding_id: root.hir.BindingId,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("source_param_interface_view_for_binding: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::source_param_tir_ty_for_binding @ d9be6853b
function source_param_tir_ty_for_binding(
    ctx: LoweringContext,
    name: string,
    binding_id: root.hir.BindingId,
) -> root.types.Ty? throws never {
    baml.sys.panic("source_param_tir_ty_for_binding: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::self_typevar_for_expr @ d9be6853b
function self_typevar_for_expr(ctx: LoweringContext, expr_id: int) -> root.types.Ty? throws never {
    baml.sys.panic("self_typevar_for_expr: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_interface_item_call @ d9be6853b
// An interface-item call, keyed off the TIR record rather than the
// spelling: any callee that resolves UNBOUND to an interface slot ,
// `(Base as I).m(..)`, `I.m(..)`, `C.m(..)`, or a type-rooted member
// access such as `K.extends` (a contextual-keyword member is not
// accepted as a path segment): or to a statically matched impl's
// method through a type (`Widget.make(..)`, a served package's ...
function try_lower_interface_item_call(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    args: int[],
    dest: Place,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "try_lower_interface_item_call: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::concrete_item_target @ d9be6853b
// The `(Self, declaring interface view)` a statically matched impl's
// method dispatches on: `hir_ty`'s realization of the carried frame,
// keyed on the interface that DECLARES the method (a `requires`
// ancestor's impl is where it may live). Associated types are outputs
// of the impl match, never dispatch keys, so the view carries none.
function concrete_item_target(
    ctx: LoweringContext,
    impl_block: int,
    func: int,
    frame_type_args: root.types.Ty[],
) -> (root.types.Ty, InterfaceTypeView) throws never {
    baml.sys.panic("concrete_item_target: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_item_call_dispatched @ d9be6853b
// The dispatched form of an interface-item call: the written argument
// at `self_arg`: the method's one required `Self`-typed parameter,
// `self` at `0` when the method takes a receiver: is the value the VM
// derives `Self` from. The call plan covers every written argument in
// declared order, `self` included, so the list is lowered ONCE and
// passed whole.
function emit_item_call_dispatched(
    ctx: LoweringContext,
    expr_id: int,
    args: int[],
    dest: Place,
    iface_tn: root.types.DeclName,
    iface_args: root.types.Ty[],
    method: string,
    self_arg: int,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "emit_item_call_dispatched: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_item_call_type_keyed @ d9be6853b
// The type-keyed form of an interface-item call: the resolved callable
// (a `Rvalue::MakeVirtualFunction`) called indirectly.
function emit_item_call_type_keyed(
    ctx: LoweringContext,
    expr_id: int,
    args: int[],
    dest: Place,
    rvalue: Rvalue,
) -> void throws MirInternalError {
    throw MirInternalError { message: "emit_item_call_type_keyed: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_type_keyed_item_reference @ d9be6853b
// Assign the type-keyed resolution of an UNBOUND interface-item
// reference: a virtual slot's, from its recorded frame; a matched
// impl method's, from its carried frame: to `dest`.
function lower_type_keyed_item_reference(
    ctx: LoweringContext,
    expr_id: int,
    callee: root.hir_ty.MethodCallee,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_type_keyed_item_reference: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_keyed_function_rvalue @ d9be6853b
// The `Rvalue::MakeVirtualFunction` resolving `method` of `view` on
// `self_ty`: the type-keyed callable of a statically matched impl's
// method, the impl re-resolved by the VM from the same `(Self,
// interface)`. The method's own type arguments are the reference's
// written slots or its recorded plan's inferred suffix.
function type_keyed_function_rvalue(
    ctx: LoweringContext,
    expr_id: int,
    self_ty: root.types.Ty,
    view: InterfaceTypeView,
    method: string,
) -> Rvalue throws never {
    baml.sys.panic("type_keyed_function_rvalue: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_type_name @ d9be6853b
// The head an interface is, wherever it is declared.
function interface_type_name(
    ctx: LoweringContext,
    interface_: int,
) -> root.types.DeclName throws never {
    baml.sys.panic("interface_type_name: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_ref_of_type_name @ d9be6853b
// The interface a head names, wherever it is declared; `None` when the
// head names no interface.
function interface_ref_of_type_name(
    ctx: LoweringContext,
    name: root.types.DeclName,
) -> int? throws never {
    baml.sys.panic("interface_ref_of_type_name: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::callee_takes_self @ d9be6853b
// Whether a method callee takes a `self` receiver, wherever it is
// declared.
function callee_takes_self(
    ctx: LoweringContext,
    callee: root.hir_ty.MethodCallee,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "callee_takes_self: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolution_is_method_call @ d9be6853b
// Whether a resolution names a METHOD for the call roads' receiver
// handling. A source method counts by its mode; a served package's
// callee by whether its row takes `self` (its statics take the
// interface-item road before this predicate is asked).
function resolution_is_method_call(
    ctx: LoweringContext,
    resolution: root.hir_ty.MemberResolution,
) -> bool throws never {
    baml.sys.panic("resolution_is_method_call: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_slot_takes_self @ d9be6853b
// Whether the method a virtual slot names takes a `self` receiver,
// wherever the interface is declared. `None` when the slot cannot be
// read at all.
function virtual_slot_takes_self(
    ctx: LoweringContext,
    interface_: int,
    method: string,
) -> bool? throws never {
    baml.sys.panic("virtual_slot_takes_self: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_item_slots @ d9be6853b
// The recorded instantiation frame of an interface-item reference,
// split per the interface's shape: the STATIC prefix `Self ++
// interface generics` (associated types are not slots; no surface
// syntax can make the prefix runtime: turbofish binds the method's
// OWN generics only), and
// the method's own type arguments as OPERANDS: written static args and ...
function interface_item_slots(
    ctx: LoweringContext,
    expr_id: int,
    shape: InterfaceMethodShape,
) -> (root.types.Ty[], Operand[])? throws never {
    baml.sys.panic("interface_item_slots: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_function_rvalue @ d9be6853b
// Build the `Rvalue::MakeVirtualFunction` for an interface-item
// reference from its recorded frame: the type-keyed resolution of the
// `(Self, interface, item)` triple as a first-class callable. Shared by
// the `self`-less call road and the value-position roads.
function virtual_function_rvalue(
    ctx: LoweringContext,
    expr_id: int,
    interface_: int,
    method: string,
) -> Rvalue? throws never {
    baml.sys.panic("virtual_function_rvalue: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::call_argument_layout @ d9be6853b
// The value slots a checked call pushes. The plan describes the written
// arguments; an unbound method call (`Class.method(obj, x)`) and a virtual
// call also pass the receiver as one leading value slot.
function call_argument_layout(
    ctx: LoweringContext,
    expr_id: int,
    value_count: int,
) -> root.types.CallLayout? throws MirInternalError {
    throw MirInternalError { message: "call_argument_layout: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_resolved_indirect_call @ d9be6853b
// Emit an ordinary indirect call of an already-resolved callable value:
// no type args (the callable curries its complete frame). Mirrors the
// shared call tail's destination normalization: a projection
// destination calls into a temp and assigns through in the resume block.
function emit_resolved_indirect_call(
    ctx: LoweringContext,
    callee_op: Operand,
    arg_operands: Operand[],
    expr_id: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "emit_resolved_indirect_call: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::written_qualifier_interface_view @ d9be6853b
// The interface view a WRITTEN qualifier names, for either spelling that
// carries one: `expr.as<I>` and `(Base as I).item`. Both pin which
// interface the member dispatches through; only where the receiver comes
// from differs, and that is the caller's concern.
function written_qualifier_interface_view(
    ctx: LoweringContext,
    expr_id: int,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("written_qualifier_interface_view: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_dispatch_target_for_tir_ty @ d9be6853b
function class_dispatch_target_for_tir_ty(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> (root.types.DeclName, root.types.RuntimeTy[])? throws never {
    baml.sys.panic("class_dispatch_target_for_tir_ty: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::l1_impl_views_for_recv @ d9be6853b
// BEP-044 wf3 #G7: for a *concrete* receiver whose
// method is provided by a blanket / out-of-body `implements … for …` rule
// (not an in-body block), find the single interface that provides `method`
// so a direct `recv.method()` dispatches through the normal interface
// switch. Returns the interface view. TIR has already rejected the
// ambiguous (>1 interface) case with E0121, so the first declaring match ...
function l1_impl_views_for_recv(
    ctx: LoweringContext,
    recv: root.types.Ty,
    target_tn: root.types.DeclName,
) -> InterfaceTypeView[] throws never {
    baml.sys.panic("l1_impl_views_for_recv: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::dispatch_target_for_concrete @ d9be6853b
// The interface a *concrete* receiver provides `method` through: the realized
// view of the impl whose interface (or its `requires` closure) declares it.
// `None` for non-concrete receivers (interfaces/type-vars take their view from
// the type itself) and for methods no impl provides.
function dispatch_target_for_concrete(
    ctx: LoweringContext,
    recv_ty: root.types.Ty,
    method: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("dispatch_target_for_concrete: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::mir_interface_declares_method @ d9be6853b
// Whether `iface_qtn` or any interface in its `requires` closure declares a
// method named `method`. Mirrors the TIR-side check; used by
// `dispatch_target_for_concrete`.
function mir_interface_declares_method(
    ctx: LoweringContext,
    iface_qtn: root.types.DeclName,
    method: string,
) -> bool throws never {
    baml.sys.panic("mir_interface_declares_method: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_interface_type_name @ d9be6853b
// Whether `tn` names an interface declaration, wherever it is declared.
function is_interface_type_name(
    ctx: LoweringContext,
    tn: root.types.DeclName,
) -> bool throws never {
    baml.sys.panic("is_interface_type_name: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_declares @ d9be6853b
// What the interface named by `iface_tn` says `member` is, DIRECTLY: in
// its own declaration, not via its `requires` closure: wherever the
// interface is declared (`hir_ty::layout::interface_member`). `None` means
// the name is not an interface this compilation can read at all: which
// is not the same as "the member is absent" (see
// `InterfaceMember::Undeclared`).
function interface_declares(
    ctx: LoweringContext,
    iface_tn: root.types.DeclName,
    member: string,
) -> DeclaredMember? throws never {
    baml.sys.panic("interface_declares: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::decl_interface_declares @ d9be6853b
// `Self::interface_declares` keyed on a resolved declaration name: the
// form the `requires` walk already holds.
function decl_interface_declares(
    ctx: LoweringContext,
    iface_decl: root.types.DeclName,
    member: string,
) -> DeclaredMember? throws never {
    baml.sys.panic("decl_interface_declares: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_interface_member @ d9be6853b
// THE interface member resolution: what `member` means in `view`, and
// which interface of `view`'s `requires` closure says so.
function resolve_interface_member(
    ctx: LoweringContext,
    view: InterfaceTypeView,
    member: string,
) -> InterfaceMember throws never {
    baml.sys.panic("resolve_interface_member: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::dispatch_view_for_call @ d9be6853b
// The interface view an interface-mediated CALL of `member` keys on, or
// `None` when the call must not dispatch at all.
function dispatch_view_for_call(
    ctx: LoweringContext,
    view: InterfaceTypeView,
    member: string,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("dispatch_view_for_call: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_view_declaring_method @ d9be6853b
function interface_view_declaring_method(
    ctx: LoweringContext,
    view: InterfaceTypeView,
    method: string,
) -> InterfaceTypeView throws never {
    baml.sys.panic("interface_view_declaring_method: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::call_trace_arg @ d9be6853b
function call_trace_arg(ctx: LoweringContext, expr_id: int) -> int? throws never {
    baml.sys.panic("call_trace_arg: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_arg_operands @ d9be6853b
function lower_call_arg_operands(
    ctx: LoweringContext,
    expr_id: int,
    args: int[],
) -> Operand[] throws MirInternalError {
    throw MirInternalError { message: "lower_call_arg_operands: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::sysop_default_operand @ d9be6853b
// Materialize a sys-op parameter's omitted default as a constant operand.
// `$rust_io_function` callees have no bytecode body: and thus no
// default-parameter prologue: so their omitted defaults must be folded at
// the call site. The default is read from the CALLEE's own defaults arena
// (correct cross-file/cross-package, where the caller's TIR tables don't
// cover the callee). Sys-op defaults are constant literals today; a ...
function sysop_default_operand(
    ctx: LoweringContext,
    callee_loc: int,
    param_index: int,
) -> Operand throws never {
    baml.sys.panic("sysop_default_operand: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call @ d9be6853b
// Lower a call expression. `x?.m(...)` enters through
// `Self::lower_optional_method_call`, which emits the null guard and
// then re-enters here with the `x.m(...)` shape: `?.` decides *whether*
// the call happens, never *how* it is made.
function lower_call(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    args: int[],
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_call: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_optional_method_call @ d9be6853b
// Lower `x?.m(...)`: null-test the receiver, then lower the call as
// `x.m(...)` on the non-null path. Mirrors `Self::lower_optional_call`'s
// block structure: inside an enclosing `OptionalChain` the null edge joins
// the chain's shared exit; standalone (no wrapper, a shape AST lowering
// does not currently produce) it builds its own null/join blocks.
function lower_optional_method_call(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    base: int,
    member_call: root.ast.Expr,
    args: int[],
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_optional_method_call: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_normalized_callee_operand @ d9be6853b
// Lower the callee as a *value* when the direct-call paths decline it.
// For `x?.m(...)` the null guard has already run and `callee_expr` is the
// normalized `x.m` view, so lowering the arena node (`x?.m`) here would
// emit a second null test and evaluate the receiver a third time. Lower
// the member access itself instead.
function lower_normalized_callee_operand(
    ctx: LoweringContext,
    callee: int,
    callee_expr: root.ast.Expr,
) -> Operand throws MirInternalError {
    throw MirInternalError { message: "lower_normalized_callee_operand: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_with_callee @ d9be6853b
function lower_call_with_callee(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
    callee_expr: root.ast.Expr,
    args: int[],
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_call_with_callee: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::callee_uses_method_convention @ d9be6853b
// Whether `callee` resolves to a BOUND method access: i.e. the call uses
// method convention (`self` passed implicitly via the receiver). Mirrors TIR's
// `callee_uses_method_call_convention`, which strips `self` so the call
// plan's `param_index` becomes receiver-relative.
function callee_uses_method_convention(ctx: LoweringContext, callee: int) -> bool throws never {
    baml.sys.panic("callee_uses_method_convention: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::sys_op_callee @ d9be6853b
function sys_op_callee(ctx: LoweringContext, callee: int) -> int? throws never {
    baml.sys.panic("sys_op_callee: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::check_await_any @ d9be6853b
function check_await_any(ctx: LoweringContext, callee: int) -> bool throws never {
    baml.sys.panic("check_await_any: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::check_spawn @ d9be6853b
function check_spawn(ctx: LoweringContext, callee: int) -> bool throws never {
    baml.sys.panic("check_spawn: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::callee_builtin_kind @ d9be6853b
function callee_builtin_kind(
    ctx: LoweringContext,
    callee: int,
) -> root.ast.BuiltinKind? throws never {
    baml.sys.panic("callee_builtin_kind: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::sys_op_synthetic_type_arg_count @ d9be6853b
function sys_op_synthetic_type_arg_count(ctx: LoweringContext, callee: int) -> int? throws never {
    baml.sys.panic("sys_op_synthetic_type_arg_count: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::synthetic_type_arg_count_for_sys_op @ d9be6853b
function synthetic_type_arg_count_for_sys_op(
    ctx: LoweringContext,
    func_loc: int,
) -> int throws never {
    baml.sys.panic("synthetic_type_arg_count_for_sys_op: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::check_intrinsic @ d9be6853b
// Check if the callee resolves to a `$compiler_intrinsic` function and return the
// corresponding `IntrinsicOp`. Follows the same resolution pattern as
// `sys_op_synthetic_type_arg_count`.
function check_intrinsic(ctx: LoweringContext, callee: int) -> IntrinsicOp? throws never {
    baml.sys.panic("check_intrinsic: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_current_package_intrinsic @ d9be6853b
// Whether a call's callee is `reflect.Package.current`, whichever lane
// serves the stdlib: a source declaration reaches here as the callee
// operand's function, a precompiled row through the callee expression's
// external resolution (as `reflect.Type.of` is recognized).
function is_current_package_intrinsic(
    ctx: LoweringContext,
    callee: int,
    callee_operand: Operand,
) -> bool throws never {
    baml.sys.panic("is_current_package_intrinsic: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::check_type_of_intrinsic @ d9be6853b
// Detect a `reflect.Type.of<T>()` call and, if found, return the
// `TyTemplate` of its written type argument: a realized type as a
// constant, a frame type variable as a `TypeArgRef`.
function check_type_of_intrinsic(
    ctx: LoweringContext,
    callee: int,
    call_expr_id: int,
) -> root.types.TyTemplate? throws never {
    baml.sys.panic("check_type_of_intrinsic: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ty_to_template @ d9be6853b
// Recursively convert a `Tir2Ty` to a `TyTemplate`.
function ty_to_template(
    ctx: LoweringContext,
    ty: root.types.Ty,
    generic_params: root.types.ParamTy[],
) -> root.types.TyTemplate throws never {
    baml.sys.panic("ty_to_template: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enclosing_generic_params @ d9be6853b
// Return the list of generic parameter names in scope for the
// **enclosing** function being lowered.  Empty for top-level expressions
// that have no enclosing generic function.
function enclosing_generic_params(ctx: LoweringContext) -> root.types.ParamTy[] throws never {
    baml.sys.panic("enclosing_generic_params: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enclosing_runtime_type_arg_templates @ d9be6853b
function enclosing_runtime_type_arg_templates(
    ctx: LoweringContext,
) -> root.types.TyTemplate[] throws never {
    baml.sys.panic("enclosing_runtime_type_arg_templates: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enclosing_generic_param_bounds @ d9be6853b
// The interface bounds of the type variables in scope for this function body, keyed by
// name: the bounds analog of `Self::enclosing_generic_params`. Combines the function's
// own + enclosing class/interface bounds (`function_in_scope_generic_param_bounds`) with
// the enclosing out-of-body impl's generics' bounds (which that query does not cover), so a
// `T.member` projection in a method body resolves through `T`'s declared bound instead of
// erasing to `unknown`.
function enclosing_generic_param_bounds(
    ctx: LoweringContext,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    baml.sys.panic("enclosing_generic_param_bounds: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_frame_type_arg_ops @ d9be6853b
// Emit `LoadType` temps for a list of type args seeding a callee frame,
// returning one `Operand` per arg (in order). Used by the static
// `default.<method>()` bypass and by inferred-type-arg call lowering.
// `TypeVar`s are lowered against the *caller's* `enclosing_generic_params`
// so they substitute against the caller's `frame.type_args` at runtime
// (mirroring the receiver-class-type-args path for direct method calls).
function emit_frame_type_arg_ops(
    ctx: LoweringContext,
    tys: root.types.Ty[],
) -> Operand[] throws never {
    baml.sys.panic("emit_frame_type_arg_ops: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_scoped_type_binding @ d9be6853b
// `let type T extends … = operand else { … };`: evaluate the operand and
// store it in the frame slot reserved for `T`'s rigid parameter, then
// check each declared bound against the type now bound to `T`, in written
// order. A bound is a constraint, not a type: it travels as its interface,
// type arguments and the associated types it pins, and the VM asks of it
// exactly what a generic parameter's bound asks. A miss runs the `else` ...
function emit_scoped_type_binding(
    ctx: LoweringContext,
    binding: root.hir_ty.ScopedTypeBinding,
    else_branch: int?,
) -> void throws MirInternalError {
    throw MirInternalError { message: "emit_scoped_type_binding: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_operand_needs_as_type @ d9be6853b
// Whether a `let type` operand of static type `ty` needs its own
// `as_type()` before the VM binds it. The VM's type-operand boundary
// unwraps `reflect.Type` and the nine kind views itself; every other
// `reflect.TypeView` (a class of the user's own, the interface, a type
// parameter bounded by it) does not reach it as a `type` value
// otherwise. The checker admits only `reflect.Type | reflect.TypeView`, ...
function type_operand_needs_as_type(ctx: LoweringContext, ty: root.types.Ty) -> bool throws never {
    baml.sys.panic("type_operand_needs_as_type: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_operand_as_type @ d9be6853b
// The `let type` operand `value` as the VM's type-operand boundary takes
// it: a `reflect.TypeView` the VM does not unwrap itself goes through its
// own `as_type()` (`Self::type_operand_needs_as_type`).
function type_operand_as_type(
    ctx: LoweringContext,
    operand: int,
    value: Operand,
) -> Operand throws MirInternalError {
    throw MirInternalError { message: "type_operand_as_type: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::load_type_value @ d9be6853b
// A `reflect.Type` value for `ty`, realized in the enclosing frame.
function load_type_value(
    ctx: LoweringContext,
    ty: root.types.Ty,
    generic_params: root.types.ParamTy[],
) -> Operand throws never {
    baml.sys.panic("load_type_value: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::call_plan_owner_prefix @ d9be6853b
// The owner frame a statically resolved callee expects ahead of its own
// type arguments: the call plan's owner prefix. The checker records the
// whole frame of every statically resolved call on its plan, so this
// reads that answer instead of re-deriving any part of it:
function call_plan_owner_prefix(
    ctx: LoweringContext,
    call: int,
    callee: int,
    callee_operand: Operand,
) -> root.types.Ty[] throws MirInternalError {
    throw MirInternalError { message: "call_plan_owner_prefix: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_call_type_args @ d9be6853b
function lower_call_type_args(
    ctx: LoweringContext,
    call_expr_id: int,
    include_inferred: bool,
    max_count: int?,
) -> Operand[] throws never {
    baml.sys.panic("lower_call_type_args: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_generic_apply @ d9be6853b
// Lower `foo<int>` (a `GenericApply` value). If the base resolves to a
// function and all type args are fully concrete, emit a pooled,
// interned `Constant::GenericFunction` (pointer-stable; seeds
// `frame.type_args` when called). Runtime callable values (bound methods,
// closures) and parameter-dependent arguments are specialized at runtime
// while preserving their existing bindings.
function lower_generic_apply(
    ctx: LoweringContext,
    expr_id: int,
    base: int,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_generic_apply: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::specialized_function @ d9be6853b
// A function item specialized at `templates`: a pooled, interned
// constant when every argument is concrete (pointer-stable identity -
// each template narrows to the `RealizedTy` the runtime carries), else
// a value built at runtime, resolving the templates against the
// current frame (`foo<T>` inside a generic function).
function specialized_function(
    item: int,
    templates: root.types.TyTemplate[],
) -> Rvalue throws never {
    baml.sys.panic("specialized_function: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::inferred_value_type_arg_templates @ d9be6853b
// The own type arguments TIR inferred for a generic function referenced
// as a VALUE at `expr_id` (`let f: (int) -> int[] = wrap`, `xs.map(wrap)`,
// `C.make`, `x.make`), as the templates the value carries. A value has
// no call site to seed its frame, so a reference that leaves them off
// runs the function with an empty frame. `None` when the reference
// instantiates nothing of its own; written arguments (`wrap<int>`) ride ...
function inferred_value_type_arg_templates(
    ctx: LoweringContext,
    expr_id: int,
    callee: int,
) -> root.types.TyTemplate[]? throws MirInternalError {
    throw MirInternalError { message: "inferred_value_type_arg_templates: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::function_item_value @ d9be6853b
// The value of a function item referenced at `expr_id`: the pooled
// function constant, specialized at the reference's inferred own type
// arguments when it has any.
function function_item_value(
    ctx: LoweringContext,
    expr_id: int,
    item: int,
) -> Rvalue throws MirInternalError {
    throw MirInternalError { message: "function_item_value: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::assign_bound_method_value @ d9be6853b
// `dest = receiver.item` as a bound method value: the receiver
// supplies the owner prefix of the frame, and the reference's inferred
// own type arguments, when it has any, are appended to it.
function assign_bound_method_value(
    ctx: LoweringContext,
    expr_id: int,
    dest: Place,
    item: int,
    receiver: Operand,
) -> void throws MirInternalError {
    throw MirInternalError { message: "assign_bound_method_value: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::assign_specialized_bound_value @ d9be6853b
// `dest = bound`, a callable value already bound to its receiver (an
// inherent method, an interface method resolved at bind time), with the
// reference's inferred own type arguments, when it has any, appended
// to the frame the receiver supplies. `callee` is the callable the
// reference names, which sizes the own generics it carries.
function assign_specialized_bound_value(
    ctx: LoweringContext,
    expr_id: int,
    dest: Place,
    callee: int,
    bound: Rvalue,
) -> void throws MirInternalError {
    throw MirInternalError { message: "assign_specialized_bound_value: not ported (U2)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::unbound_interface_item_callee @ d9be6853b
// The callee of `base` when it is an UNBOUND interface item: the
// type-rooted spellings `I.m`, `C.m`, `(C as I).m`: wherever the
// interface is declared.
function unbound_interface_item_callee(
    ctx: LoweringContext,
    base: int,
) -> root.hir_ty.MethodCallee? throws never {
    baml.sys.panic("unbound_interface_item_callee: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_resolve_generic_apply_base @ d9be6853b
// Resolve a `GenericApply` base to the underlying function with a
// global of its own (a free function or a class-inherent static),
// wherever it is declared. `None` for bound methods, lambdas, interface
// items, or anything that is not a function path.
function try_resolve_generic_apply_base(ctx: LoweringContext, base: int) -> int? throws never {
    baml.sys.panic("try_resolve_generic_apply_base: not ported (U2)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::planned_generic_apply_type_arg_templates @ d9be6853b
// The `TyTemplate`s of a `GenericApply`'s written type args, as TIR
// resolved them (its call plan keyed at the apply expression). A
// template is `is_fully_concrete()` unless the arg names an enclosing
// type variable: then it carries a `TypeArgRef`, resolved at runtime.
function planned_generic_apply_type_arg_templates(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.TyTemplate[] throws never {
    baml.sys.panic("planned_generic_apply_type_arg_templates: not ported (U2)")
}

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
