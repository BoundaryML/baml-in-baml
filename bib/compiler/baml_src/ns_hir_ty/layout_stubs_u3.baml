// Items of `baml_compiler2_hir_ty` MIR unit 3 needs that are not ported
// yet, with their Rust signatures. Deleted at the MIR merge.
//
// `extern_function_package` / `extern_function_row` panic: no root is served
// from an interface here (`root.hir.is_served_from_interface`), so no
// `ExternFunctionLoc` (an `int` id) ever exists and they are never reached.
// `class_field_count` / `class_field_index` are ported for real.

// port: baml_compiler2_hir_ty/src/extern_loc.rs::ExternFunctionLoc::package @ d9be6853b
// The root of the served package that exports `function_`.
function extern_function_package(db: root.hir.Db, function_: int) -> int throws never {
    baml.sys.panic("extern_function_package: not ported")
}

