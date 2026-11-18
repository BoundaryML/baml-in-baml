// port: baml_compiler2_hir_ty/src/package_interface.rs @ d9be6853b
//
// Package interfaces are not ported: the stdlib is compiled from source, so
// no root is served from an interface (bib/PORTING.md, "TIR plan").

// port: baml_compiler2_hir_ty/src/package_interface.rs::reexport_paths @ d9be6853b
// Every declaration `root_id` re-exports, by its defining identity, to the
// (namespace, name) path it is exported under.
// Restructured: Rust's `IndexMap<DeclName, (Vec<Name>, Name)>` is a list of
// (declaration, namespace, name) in insertion order.
// Rust walks `package_interface(db, root).reexports`. For a root compiled
// from source that interface is `fold_package_interface`'s, which builds
// `reexports` empty: only an interface read from a blob carries re-exports
// (`import_interface`), and no root is served from one here
// (`root.hir.is_served_from_interface`). Seeded stdlib blobs are exports of
// a source fold, so theirs are empty too. The answer is always empty.
function reexport_paths(
    db: root.hir.Db,
    root_id: int,
) -> (root.types.DeclName, string[], string)[] throws never {
    []
}

// port: baml_compiler2_hir_ty/src/package_interface.rs::ExportedFunction @ d9be6853b
// A served package's exported function row. No root is served from an
// interface here, so MIR never holds one; the lookups that answer it
// (`extern_function_row`) are not reached. Not ported: the fields `target`
// (`ExternalCallTarget`) and `linkability` (`ExternalLinkability`), whose
// types are not ported.
class ExportedFunction {
    name: string,
    params: root.types.FunctionParamTy[],
    return_type: root.types.Ty,
    callable_throws: root.types.Ty,
    // Function-level generic parameters, including any synthetic callback
    // effect parameters introduced by bounded signature elaboration.
    generic_params: root.types.ParamTy[],
    generic_param_bounds: root.types.InterfaceConstraint[][],
    builtin_kind: root.ast.BuiltinKind?,
}
