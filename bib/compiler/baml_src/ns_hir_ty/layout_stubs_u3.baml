// Stubs MIR unit 3 needs from `baml_compiler2_hir_ty` that are not ported
// yet, with their Rust signatures. No root is served from an interface here
// (`root.hir.is_served_from_interface`), so no `ExternFunctionLoc` (an `int`
// id) ever exists and these are never reached. Deleted at the MIR merge.

// port: baml_compiler2_hir_ty/src/extern_loc.rs::ExternFunctionLoc::package @ d9be6853b
// The root of the served package that exports `function_`.
function extern_function_package(db: root.hir.Db, function_: int) -> int throws never {
    baml.sys.panic("extern_function_package: not ported")
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::extern_function_row @ d9be6853b
// The exported row of a served function. MIR's `ExportedFunction` lives in
// `ns_mir/gaps.baml` until its home is ported.
function extern_function_row(
    db: root.hir.Db,
    function_: int,
) -> root.mir.ExportedFunction throws never {
    baml.sys.panic("extern_function_row: not ported")
}
