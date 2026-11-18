// port: baml_compiler2_hir_ty/src/package_interface.rs @ d9be6853b
//
// The rows and lookups of a package served from its interface that the
// declaration lowering reads. No root is served from an interface here
// (`root.hir.is_served_from_interface`), so the lookups answer nothing or
// are not reached.

// port: baml_compiler2_hir_ty/src/package_interface.rs::ExportedFieldAttrs @ d9be6853b
class ExportedFieldAttrs {
    alias: string?,
    description: string?,
    docstring: string?,
}

// port: baml_compiler2_hir_ty/src/package_interface.rs::ExportedAssociatedType @ d9be6853b
class ExportedAssociatedType {
    name: string,
    bound: root.types.InterfaceConstraint?,
    default_: root.types.Ty?,
}

// port: baml_compiler2_hir_ty/src/package_interface.rs::ExportedType @ d9be6853b
// One exported type row. Not ported: the method rows (`methods`,
// `required_methods`, `default_methods`) and an interface's `requires`
// closure, which nothing ported reads.
type ExportedType = ExportedTypeClass
    | ExportedTypeEnum
    | ExportedTypeTypeAlias
    | ExportedTypeInterface;

class ExportedTypeClass {
    qtn: root.types.DeclName,
    fields: (string, root.types.Ty, ExportedFieldAttrs)[],
    generic_params: root.types.ParamTy[],
    generic_param_bounds: root.types.InterfaceConstraint[][],
}

class ExportedTypeEnum {
    qtn: root.types.DeclName,
    variants: string[],
}

class ExportedTypeTypeAlias {
    qtn: root.types.DeclName,
    resolved: root.types.Ty,
}

class ExportedTypeInterface {
    qtn: root.types.DeclName,
    self_param: root.types.ParamTy,
    generic_params: root.types.ParamTy[],
    param_bounds: root.types.InterfaceConstraint[][],
    associated_types: ExportedAssociatedType[],
    fields: (string, root.types.Ty, ExportedFieldAttrs)[],
}

// port: baml_compiler2_hir_ty/src/package_interface.rs::ResolvedValue @ d9be6853b
// A value path's answer: a source definition, or a served package's exported
// function or top-level binding. Restructured: the extern locs are `int` ids.
type ResolvedValue = ResolvedValueSource | ResolvedValueExternal | ResolvedValueExternalLet;

class ResolvedValueSource {
    value: root.hir.Definition,
}

class ResolvedValueExternal {
    value: int,
}

class ResolvedValueExternalLet {
    value: int,
}

// port: baml_compiler2_hir_ty/src/package_interface.rs::exported_type_row @ d9be6853b
// The row `root_id`'s interface exports at `namespace.item`, following its
// re-exports. Reached only for a root served from its interface.
function exported_type_row(
    db: root.hir.Db,
    root_id: int,
    namespace: string[],
    item: string,
) -> ExportedType? throws never {
    baml.sys.panic("exported_type_row: not ported")
}

// port: baml_compiler2_hir_ty/src/package_interface.rs::mounted_type_row @ d9be6853b
// The row of `qtn` when its package is served from its interface: Rust reads
// `mounted_interface(db, root)?`, which is none for every root here.
function mounted_type_row(db: root.hir.Db, qtn: root.types.DeclName) -> ExportedType? throws never {
    null
}
