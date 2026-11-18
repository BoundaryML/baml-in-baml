// port: baml_compiler2_hir_ty/src/extern_loc.rs::mounted_class_loc @ d9be6853b
// `extern_class_loc` for a package served from its interface. Restructured:
// an `ExternClassLoc` is an `int` id, as interned locations are.
function mounted_class_loc(db: root.hir.Db, head: root.types.DeclName) -> int? throws never {
    baml.sys.panic("mounted_class_loc: not ported")
}
