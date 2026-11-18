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

// port: baml_compiler2_hir_ty/src/extern_loc.rs::extern_function_row @ d9be6853b
// The exported row of a served function. MIR's `ExportedFunction` lives in
// `ns_mir/gaps.baml` until its home is ported.
function extern_function_row(
    db: root.hir.Db,
    function_: int,
) -> root.mir.ExportedFunction throws never {
    baml.sys.panic("extern_function_row: not ported")
}

// port: baml_compiler2_hir_ty/src/layout.rs::class_field_count @ d9be6853b
// How many slots an instance of `class_` has. Ported for real (the object
// literal lowering needs it), over the Source lane: MIR's `ClassRef` is a
// class loc `int`.
function class_field_count(db: root.hir.Db, class_: int) -> int throws never {
    resolve_class_fields(db, class_).length()
}

// port: baml_compiler2_hir_ty/src/layout.rs::class_field_index @ d9be6853b
// The slot of the field named `field`, if the class declares one. Ported for
// real, as `class_field_count`.
function class_field_index(db: root.hir.Db, class_: int, field: string) -> int? throws never {
    resolve_class_fields(db, class_).find_index((entry) -> {
        entry.0 == field
    })
}
