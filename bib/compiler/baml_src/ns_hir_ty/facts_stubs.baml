// port: baml_compiler2_hir_ty/src/facts.rs::definition_of @ d9be6853b
// The source definition a qualified type name points at, if its package is
// served from source and declares the item.
function definition_of(
    db: root.hir.Db,
    name: root.types.DeclName,
) -> root.hir.Definition? throws never {
    baml.sys.panic("definition_of: not ported")
}
