// Stubs for `hir_ty` items MIR unit 2 needs that are not ported yet, with
// their Rust signatures, in their home namespace. Each panics until the unit
// that ports `hir_ty`'s layout and impl surface replaces it; this file is
// deleted at merge.
//
// Signatures follow layout.baml: an `InterfaceRef` / `ImplRef` /
// `FunctionRef` is its lane union or, where the callers hold only the Source
// lane, an `int`. Rust's `layout::InterfaceMember` is MIR's
// `root.mir.DeclaredMember` (ns_mir/gaps.baml), and `ClosedTy` /
// `ClosedInterface` are `root.types`'.

// port: baml_compiler2_hir_ty/src/layout.rs::interface_ref_of @ d9be6853b
// The interface `head` names, wherever it is declared.
function interface_ref_of(
    db: root.hir.Db,
    head: root.types.DeclName,
) -> root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int> | null throws never {
    baml.sys.panic("interface_ref_of: not ported (layout stub, MIR U2)")
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_member @ d9be6853b
// What one interface declaration says `member` is, directly (not through its
// `requires` closure).
function interface_member(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
    member: string,
) -> root.mir.DeclaredMember? throws never {
    baml.sys.panic("interface_member: not ported (layout stub, MIR U2)")
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_requires_closure @ d9be6853b
// `interface_` and every interface its `requires` reach, breadth first, each
// once.
function interface_requires_closure(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] throws never {
    baml.sys.panic("interface_requires_closure: not ported (layout stub, MIR U2)")
}

// port: baml_compiler2_hir_ty/src/impls.rs::concrete_callee_target @ d9be6853b
// The `(Self, interface)` a statically matched impl's method dispatches on,
// realized at the carried frame. `block` and `func` are Source-lane locs.
function concrete_callee_target(
    db: root.hir.Db,
    block: int,
    func: int,
    frame: root.types.Ty[],
) -> (root.types.ClosedTy, root.types.ClosedInterface) throws never {
    baml.sys.panic("concrete_callee_target: not ported (impls stub, MIR U2)")
}
