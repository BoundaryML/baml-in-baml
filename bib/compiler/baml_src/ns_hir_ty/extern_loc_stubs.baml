// port: baml_compiler2_hir_ty/src/extern_loc.rs::mounted_class_loc @ d9be6853b
// `extern_class_loc` for a package served from its interface. Restructured:
// an `ExternClassLoc` is an `int` id, as interned locations are.
function mounted_class_loc(db: root.hir.Db, head: root.types.DeclName) -> int? throws never {
    baml.sys.panic("mounted_class_loc: not ported")
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::mounted_enum_loc @ d9be6853b
// `extern_enum_loc` for a package served from its interface. No root is
// served from an interface here (`root.hir.is_served_from_interface`), so
// there is none. Restructured: an `ExternEnumLoc` is an `int` id.
function mounted_enum_loc(db: root.hir.Db, head: root.types.DeclName) -> int? throws never {
    null
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::mounted_alias_loc @ d9be6853b
// `extern_alias_loc` for a package served from its interface: none here, as
// for `mounted_enum_loc`. Restructured: an `ExternTypeAliasLoc` is an `int`.
function mounted_alias_loc(db: root.hir.Db, head: root.types.DeclName) -> int? throws never {
    null
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::mounted_function_named @ d9be6853b
// The function a package served from its interface exports at
// `namespace.name`: none here, as for `mounted_enum_loc`. Restructured: an
// `ExternFunctionLoc` is an `int` id.
function mounted_function_named(
    db: root.hir.Db,
    root_id: int,
    namespace: string[],
    name: string,
) -> int? throws never {
    null
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::mounted_let_named @ d9be6853b
// The top-level binding a package served from its interface exports at
// `namespace.name`: none here, as for `mounted_enum_loc`. Restructured: an
// `ExternLetLoc` is an `int` id.
function mounted_let_named(
    db: root.hir.Db,
    root_id: int,
    namespace: string[],
    name: string,
) -> int? throws never {
    null
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::extern_class_row @ d9be6853b
// The exported row of a served class. Restructured: the row is the
// `ExportedTypeClass` itself, the class an `int` id.
function extern_class_row(db: root.hir.Db, class_: int) -> ExportedTypeClass throws never {
    baml.sys.panic("extern_class_row: not ported")
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::extern_alias_row @ d9be6853b
// The resolved value of a served type alias. Restructured: the alias is an
// `int` id.
function extern_alias_row(db: root.hir.Db, alias: int) -> root.types.Ty throws never {
    baml.sys.panic("extern_alias_row: not ported")
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::mounted_interface_loc @ d9be6853b
// `extern_interface_loc` for a package served from its interface: none here,
// as for `mounted_enum_loc`. Restructured: an `ExternInterfaceLoc` is an
// `int` id.
function mounted_interface_loc(db: root.hir.Db, head: root.types.DeclName) -> int? throws never {
    null
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::extern_enum_row @ d9be6853b
// The exported row of a served enum. Restructured: the row is the
// `ExportedTypeEnum` itself, the enum an `int` id.
function extern_enum_row(db: root.hir.Db, enum_loc: int) -> ExportedTypeEnum throws never {
    baml.sys.panic("extern_enum_row: not ported")
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::extern_interface_row @ d9be6853b
// The exported row of a served interface. Restructured: the row is the
// `ExportedTypeInterface` itself, the interface an `int` id.
function extern_interface_row(
    db: root.hir.Db,
    interface_: int,
) -> ExportedTypeInterface throws never {
    baml.sys.panic("extern_interface_row: not ported")
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::extern_function_row @ d9be6853b
// The exported row of a served function. An `ExternFunctionLoc` is minted
// only from a row of a root served from its interface, and there is none
// here, so this is never reached. Restructured: the function is an `int` id.
function extern_function_row(db: root.hir.Db, function_: int) -> ExportedFunction throws never {
    baml.sys.panic("extern_function_row: not ported")
}

// port: baml_compiler2_hir_ty/src/extern_loc.rs::extern_interface_method @ d9be6853b
// The served function an interface's exported method row names: none here
// (no root is served from an interface). Restructured: an
// `ExternFunctionLoc` is an `int` id.
function extern_interface_method(
    db: root.hir.Db,
    interface_: root.types.DeclName,
    method: string,
) -> int? throws never {
    null
}
