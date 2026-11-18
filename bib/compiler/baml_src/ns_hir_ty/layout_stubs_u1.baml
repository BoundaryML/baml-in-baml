// Stubs added by MIR unit 1 for `baml_compiler2_hir_ty/src/layout.rs`
// items MIR needs and `layout.baml` does not port yet. Each panics until
// unit U7 ports it into `layout.baml`; this file is deleted at merge. Rust
// signatures; `ClassRef` / `EnumRef` are the `DeclRef` unions, `Name` is
// `string`, `u32` is `int`.

// port: baml_compiler2_hir_ty/src/layout.rs::class_field_index @ d9be6853b
// The slot of the field named `field`, if the class declares one.
function class_field_index(
    db: root.hir.Db,
    class_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
    field: string,
) -> int? throws never {
    baml.sys.panic("layout::class_field_index: not ported (U7)")
}

// port: baml_compiler2_hir_ty/src/layout.rs::class_field_ty @ d9be6853b
// The declared type of the field named `field`, in the class's own generic
// frame, if the class declares one.
function class_field_ty(
    db: root.hir.Db,
    class_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
    field: string,
) -> root.types.Ty? throws never {
    baml.sys.panic("layout::class_field_ty: not ported (U7)")
}

// port: baml_compiler2_hir_ty/src/layout.rs::enum_variants @ d9be6853b
// The enum's variants in declaration (= discriminant) order.
function enum_variants(
    db: root.hir.Db,
    enum_ref: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> string[] throws never {
    baml.sys.panic("layout::enum_variants: not ported (U7)")
}

// port: baml_compiler2_hir_ty/src/layout.rs::enum_variant_index @ d9be6853b
// The discriminant of the variant named `variant`, if the enum declares one.
function enum_variant_index(
    db: root.hir.Db,
    enum_ref: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
    variant: string,
) -> int? throws never {
    baml.sys.panic("layout::enum_variant_index: not ported (U7)")
}

// port: baml_compiler2_hir_ty/src/layout.rs::lang_class @ d9be6853b
// A class a language package ships, by its path in the package.
function lang_class(
    db: root.hir.Db,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int> | null throws never {
    baml.sys.panic("layout::lang_class: not ported (U7)")
}
