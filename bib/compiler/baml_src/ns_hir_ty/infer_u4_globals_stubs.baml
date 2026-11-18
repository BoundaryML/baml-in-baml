// Stubs for the two `globals.rs` functions K4 unit 4 calls
// (`global_value_ty`). `globals.rs` belongs to work package L, which has no
// stub file yet; its port replaces these and deletes this file.

// port: baml_compiler2_hir_ty/src/globals.rs::global_value_type @ d9be6853b
function global_value_type(db: root.hir.Db, binding: int) -> root.types.Ty? throws never {
    baml.sys.panic("global_value_type: not ported (package L)")
}
