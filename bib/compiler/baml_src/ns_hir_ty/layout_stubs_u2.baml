// Stubs for `hir_ty` items MIR unit 2 needs that are not ported yet, with
// their Rust signatures, in their home namespace. Each panics until the unit
// that ports `hir_ty`'s layout and impl surface replaces it; this file is
// deleted at merge.
//
// `ImplRef` / `FunctionRef` are their Source lane, an `int`; `ClosedTy` /
// `ClosedInterface` are `root.types`'.

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
