// port: baml_compiler2_hir_ty/src/layout.rs @ d9be6853b
//
// Layout facts of a declaration, whichever lane declares it: the `Source`
// arm reads the item's lowered data, the `External` arm its exported row.
// Ported: the subset the type checker reaches (head to ref for classes,
// enums and aliases, `package_aliases`, `class_fields`, `alias_value`). The
// rest of layout.rs serves MIR and codegen.
//
// Restructured: a `ClassRef` (`DeclRef<ClassLoc, ExternClassLoc>`) is
// `root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>`, and so for
// the other kinds; `package_aliases`' lazy iterator is an array.
// Not ported: `source_definition` (a one-line forward to `definition_of`).

// port: baml_compiler2_hir_ty/src/layout.rs::class_ref_of @ d9be6853b
// The class `head` names, wherever it is declared.
function class_ref_of(
    db: root.hir.Db,
    head: root.types.DeclName,
) -> root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int> | null throws never {
    match (definition_of(db, head)) {
        let class_: root.hir.DefinitionClass => root.hir.DeclRefSource { value: class_.value },
        null => {
            let external = mounted_class_loc(db, head)
                ?? return null;
            root.hir.DeclRefExternal { value: external }
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::enum_ref_of @ d9be6853b
// The enum `head` names, wherever it is declared.
function enum_ref_of(
    db: root.hir.Db,
    head: root.types.DeclName,
) -> root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int> | null throws never {
    match (definition_of(db, head)) {
        let enum_def: root.hir.DefinitionEnum => root.hir.DeclRefSource { value: enum_def.value },
        null => {
            let external = mounted_enum_loc(db, head)
                ?? return null;
            root.hir.DeclRefExternal { value: external }
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::alias_ref_of @ d9be6853b
// The type alias `head` names, wherever it is declared.
function alias_ref_of(
    db: root.hir.Db,
    head: root.types.DeclName,
) -> root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int> | null throws never {
    match (definition_of(db, head)) {
        let alias: root.hir.DefinitionTypeAlias => root.hir.DeclRefSource { value: alias.value },
        null => {
            let external = mounted_alias_loc(db, head)
                ?? return null;
            root.hir.DeclRefExternal { value: external }
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::package_aliases @ d9be6853b
// Also `package_declarations` for aliases: every type alias `root_id`
// declares, on the lane the root is served on, in declaration order.
function package_aliases(
    db: root.hir.Db,
    root_id: int,
) -> (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] throws never {
    if (root.hir.is_served_from_interface(db, root_id)) {
        baml.sys.panic("package_aliases: a root served from its interface is not ported");
    }
    let out: (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] = [];
    for (let namespace in root.hir.package_items(db, root_id).namespaces) {
        for (let def in namespace.1.types.values()) {
            match (def) {
                let alias: root.hir.DefinitionTypeAlias => {
                    out.push(root.hir.DeclRefSource { value: alias.value });
                },
                _ => {},
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/layout.rs::class_fields @ d9be6853b
// The class's fields in declaration (= slot) order, each typed in the
// class's own generic frame.
function class_fields(
    db: root.hir.Db,
    class_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> (string, root.types.Ty)[] throws never {
    match (class_) {
        let source: root.hir.DeclRefSource<int> => {
            resolve_class_fields(db, source.value).map((field) -> {
                (field.0, field.1)
            })
        },
        let external: root.hir.DeclRefExternal<int> => {
            extern_class_row(db, external.value).fields.map((field) -> {
                (field.0, field.1)
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::alias_value @ d9be6853b
// The type `alias` stands for, resolved one level.
function alias_value(
    db: root.hir.Db,
    alias: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> root.types.Ty throws never {
    match (alias) {
        let source: root.hir.DeclRefSource<int> => type_alias_value(db, source.value),
        let external: root.hir.DeclRefExternal<int> => extern_alias_row(db, external.value),
    }
}
