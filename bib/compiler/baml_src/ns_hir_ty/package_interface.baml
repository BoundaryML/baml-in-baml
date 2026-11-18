// port: baml_compiler2_hir_ty/src/package_interface.rs @ d9be6853b
//
// Package interfaces are not ported: the stdlib is compiled from source, so
// no root is served from an interface (bib/PORTING.md, "TIR plan").

// port: baml_compiler2_hir_ty/src/package_interface.rs::reexport_paths @ d9be6853b
// Every declaration `root_id` re-exports, by its defining identity, to the
// (namespace, name) path it is exported under.
// Restructured: Rust's `IndexMap<DeclName, (Vec<Name>, Name)>` is a list of
// (declaration, namespace, name) in insertion order; a `DeclName` is not a
// map key.
function reexport_paths(db: root.hir.Db, root_id: int) -> (root.types.DeclName, string[], string)[] throws never {
    baml.sys.panic("reexport_paths: package interfaces are not ported")
}
