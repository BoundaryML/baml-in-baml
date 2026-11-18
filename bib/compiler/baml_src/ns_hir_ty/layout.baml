// port: baml_compiler2_hir_ty/src/layout.rs @ d9be6853b
//
// Layout facts of a declaration, whichever lane declares it: the `Source`
// arm reads the item's lowered data, the `External` arm its exported row.
// No root is served from an interface here, so an `External` arm is never
// reached; where it reads a row the stub `ExportedType*` does not carry
// (method rows, `requires`) or an extern loc's head, it panics.
//
// Restructured: a `ClassRef` (`DeclRef<ClassLoc, ExternClassLoc>`) is
// `root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>`, and so for
// the other kinds; the `package_*` enumerators' lazy iterators are arrays;
// `layout::InterfaceMember` is `DeclaredMember` (see there).
// Not ported:
// - `source_definition` (a one-line forward to `definition_of`).
// - `Lane` and `package_declarations`: each `package_*` enumerator walks its
//   source lane itself and panics on the served one.
// - `class_crossing`: `baml_type::ClassCrossing` (crossing.rs) is not ported.

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

// port: baml_compiler2_hir_ty/src/layout.rs::class_generic_params @ d9be6853b
// The class's generic parameters, in declaration order.
function class_generic_params(
    db: root.hir.Db,
    class_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> root.types.ParamTy[] throws never {
    match (class_) {
        let source: root.hir.DeclRefSource<int> => class_generic_frame(db, source.value),
        let external: root.hir.DeclRefExternal<int> => {
            extern_class_row(db, external.value).generic_params
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

// port: baml_compiler2_hir_ty/src/layout.rs::lang_class @ d9be6853b
// The class a language package declares at `namespace.name`, whichever lane
// serves the package; null when the package is not installed or declares no
// such class.
function lang_class(
    db: root.hir.Db,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int> | null throws never {
    let root_id = root.hir.lang_roots(db).get(package)
        ?? return null;
    class_ref_of(db, root.types.DeclName { pkg: root_id, namespace: namespace, name: name })
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_ref_of @ d9be6853b
// The interface `head` names, wherever it is declared.
function interface_ref_of(
    db: root.hir.Db,
    head: root.types.DeclName,
) -> root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int> | null throws never {
    match (definition_of(db, head)) {
        let interface_: root.hir.DefinitionInterface => {
            root.hir.DeclRefSource { value: interface_.value }
        },
        null => {
            let external = mounted_interface_loc(db, head)
                ?? return null;
            root.hir.DeclRefExternal { value: external }
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::class_head @ d9be6853b
// The head a class declaration is spelled by. A served class's head is its
// extern loc's: not ported (no root is served from an interface).
function class_head(
    db: root.hir.Db,
    class_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> root.types.DeclName throws never {
    match (class_) {
        let source: root.hir.DeclRefSource<int> => class_qualified_name(db, source.value),
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic("class_head: a root served from its interface is not ported")
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::enum_head @ d9be6853b
// The head an enum declaration is spelled by.
function enum_head(
    db: root.hir.Db,
    enum_ref: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> root.types.DeclName throws never {
    match (enum_ref) {
        let source: root.hir.DeclRefSource<int> => {
            qualify_def(
                db,
                root.hir.DefinitionEnum { value: source.value },
                root.hir.enum_data(db, source.value).name,
            )
        },
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic("enum_head: a root served from its interface is not ported")
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_head @ d9be6853b
// The head an interface declaration is spelled by.
function interface_head(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> root.types.DeclName throws never {
    match (interface_) {
        let source: root.hir.DeclRefSource<int> => interface_qualified_name(db, source.value),
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic("interface_head: a root served from its interface is not ported")
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::alias_head @ d9be6853b
// The head a type alias declaration is spelled by.
function alias_head(
    db: root.hir.Db,
    alias: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> root.types.DeclName throws never {
    match (alias) {
        let source: root.hir.DeclRefSource<int> => {
            qualify_def(
                db,
                root.hir.DefinitionTypeAlias { value: source.value },
                root.hir.type_alias_data(db, source.value).name,
            )
        },
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic("alias_head: a root served from its interface is not ported")
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::package_classes @ d9be6853b
// Also `package_declarations` for classes: every class `root_id` declares,
// in declaration order. Restructured as `package_aliases` is.
function package_classes(
    db: root.hir.Db,
    root_id: int,
) -> (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] throws never {
    if (root.hir.is_served_from_interface(db, root_id)) {
        baml.sys.panic("package_classes: a root served from its interface is not ported");
    }
    let out: (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] = [];
    for (let namespace in root.hir.package_items(db, root_id).namespaces) {
        for (let def in namespace.1.types.values()) {
            match (def) {
                let class_: root.hir.DefinitionClass => {
                    out.push(root.hir.DeclRefSource { value: class_.value });
                },
                _ => {},
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/layout.rs::package_enums @ d9be6853b
// Also `package_declarations` for enums: every enum `root_id` declares, in
// declaration order. Restructured as `package_aliases` is.
function package_enums(
    db: root.hir.Db,
    root_id: int,
) -> (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] throws never {
    if (root.hir.is_served_from_interface(db, root_id)) {
        baml.sys.panic("package_enums: a root served from its interface is not ported");
    }
    let out: (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] = [];
    for (let namespace in root.hir.package_items(db, root_id).namespaces) {
        for (let def in namespace.1.types.values()) {
            match (def) {
                let enum_def: root.hir.DefinitionEnum => {
                    out.push(root.hir.DeclRefSource { value: enum_def.value });
                },
                _ => {},
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/layout.rs::package_interfaces @ d9be6853b
// Also `package_declarations` for interfaces: every interface `root_id`
// declares, in declaration order. Restructured as `package_aliases` is.
function package_interfaces(
    db: root.hir.Db,
    root_id: int,
) -> (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] throws never {
    if (root.hir.is_served_from_interface(db, root_id)) {
        baml.sys.panic("package_interfaces: a root served from its interface is not ported");
    }
    let out: (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] = [];
    for (let namespace in root.hir.package_items(db, root_id).namespaces) {
        for (let def in namespace.1.types.values()) {
            match (def) {
                let interface_: root.hir.DefinitionInterface => {
                    out.push(root.hir.DeclRefSource { value: interface_.value });
                },
                _ => {},
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/layout.rs::class_field_count @ d9be6853b
// How many slots an instance of `class_` has.
function class_field_count(
    db: root.hir.Db,
    class_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> int throws never {
    match (class_) {
        let source: root.hir.DeclRefSource<int> => resolve_class_fields(db, source.value).length(),
        let external: root.hir.DeclRefExternal<int> => {
            extern_class_row(db, external.value).fields.length()
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::class_field_index @ d9be6853b
// The slot of the field named `field`, if the class declares one.
function class_field_index(
    db: root.hir.Db,
    class_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
    field: string,
) -> int? throws never {
    let names = match (class_) {
        let source: root.hir.DeclRefSource<int> => {
            resolve_class_fields(db, source.value).map((declared) -> string {
                declared.0
            })
        },
        let external: root.hir.DeclRefExternal<int> => {
            extern_class_row(db, external.value).fields.map((declared) -> string {
                declared.0
            })
        },
    };
    names.index_of(field)
}

// port: baml_compiler2_hir_ty/src/layout.rs::class_field_ty @ d9be6853b
// The declared type of the field named `field`, in the class's own generic
// frame, if the class declares one. Reads `class_fields`, the same per-lane
// list Rust searches inline.
function class_field_ty(
    db: root.hir.Db,
    class_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
    field: string,
) -> root.types.Ty? throws never {
    for (let declared in class_fields(db, class_)) {
        if (declared.0 == field) {
            return declared.1;
        }
    }
    null
}

// port: baml_compiler2_hir_ty/src/layout.rs::enum_variants @ d9be6853b
// The enum's variants in declaration (= discriminant) order.
function enum_variants(
    db: root.hir.Db,
    enum_ref: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> string[] throws never {
    match (enum_ref) {
        let source: root.hir.DeclRefSource<int> => {
            root.hir.enum_data(db, source.value).variants.map((variant) -> string {
                variant.name
            })
        },
        let external: root.hir.DeclRefExternal<int> => extern_enum_row(db, external.value).variants,
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::enum_variant_index @ d9be6853b
// The discriminant of the variant named `variant`, if the enum declares one.
function enum_variant_index(
    db: root.hir.Db,
    enum_ref: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
    variant: string,
) -> int? throws never {
    enum_variants(db, enum_ref).index_of(variant)
}

// port: baml_compiler2_hir_ty/src/layout.rs::InterfaceMember @ d9be6853b
// What an interface's OWN declaration says a member is. Named
// `DeclaredMember` (the name MIR imports it under): `InterfaceMember` in this
// namespace is method_resolution.rs's. Methods are checked before fields; a
// field's index is its position in the interface's own declared field list,
// the index space every `VirtualFieldAccess` is baked against.
type DeclaredMember = DeclaredMemberMethod | DeclaredMemberField;

class DeclaredMemberMethod {
}

class DeclaredMemberField {
    index: int,
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_member @ d9be6853b
// What `interface_`'s own declaration (not its `requires` closure) says
// `member` is; null when it declares no such member. The served arm reads
// method rows the stub `ExportedTypeInterface` does not carry: not ported.
function interface_member(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
    member: string,
) -> DeclaredMember? throws never {
    match (interface_) {
        let source: root.hir.DeclRefSource<int> => {
            let data = root.hir.interface_data(db, source.value);
            for (let method in data.methods) {
                if (root.hir.function_data(db, method).name == member) {
                    return DeclaredMemberMethod {};
                }
            }
            let index = data.fields
                .map((field) -> string {
                    field.name
                })
                .index_of(member)
                ?? return null;
            DeclaredMemberField { index: index }
        },
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic("interface_member: a root served from its interface is not ported")
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_method_names @ d9be6853b
// Every method name `interface_`'s own declaration carries, required and
// default alike. The served arm reads method rows the stub
// `ExportedTypeInterface` does not carry: not ported.
function interface_method_names(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> string[] throws never {
    match (interface_) {
        let source: root.hir.DeclRefSource<int> => {
            root.hir.interface_data(db, source.value).methods.map((method) -> string {
                root.hir.function_data(db, method).name
            })
        },
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic("interface_method_names: a root served from its interface is not ported")
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_generic_arity @ d9be6853b
// How many generic parameters `interface_` declares (its frame minus `Self`).
function interface_generic_arity(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> int throws never {
    match (interface_) {
        let source: root.hir.DeclRefSource<int> => {
            root.hir.interface_data(db, source.value).generic_params.length()
        },
        let external: root.hir.DeclRefExternal<int> => {
            extern_interface_row(db, external.value).generic_params.length()
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_requires_heads @ d9be6853b
// The interfaces `interface_` DIRECTLY requires, by head. The served arm
// reads the `requires` closure the stub `ExportedTypeInterface` does not
// carry: not ported.
function interface_requires_heads(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> root.types.DeclName[] throws never {
    match (interface_) {
        let source: root.hir.DeclRefSource<int> => {
            let data = root.hir.interface_data(db, source.value);
            let package = root.hir.file_package(db, db.interface_locs.get(source.value).file);
            let items = root.hir.package_items(db, package.root_id);
            let out: root.types.DeclName[] = [];
            for (let target in data.requires_) {
                let head = root.hir_ty.interfaces.resolve_ref_to_interface_name(
                    db,
                    data.type_refs,
                    target,
                    items,
                    package.namespace_path,
                );
                if (head != null) {
                    out.push(head);
                }
            }
            out
        },
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic(
                "interface_requires_heads: a root served from its interface is not ported",
            )
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_requires_closure @ d9be6853b
// The transitive `requires` closure of `interface_`, the root first, in BFS
// order, crossing lanes. A required interface no lane declares is skipped;
// cycles are skipped silently (E0118 reports them).
function interface_requires_closure(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] throws never {
    let out: (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] = [];
    let queue: (root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>)[] = [interface_];
    let next = 0;
    while (next < queue.length()) {
        let current = queue[next];
        next += 1;
        if (out.includes(current)) {
            continue;
        }
        out.push(current);
        for (let head in interface_requires_heads(db, current)) {
            let parent = interface_ref_of(db, head);
            if (parent != null) {
                queue.push(parent);
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_field_names @ d9be6853b
// The interface's declared fields, by name, in declaration order: the index
// space `DeclaredMemberField` indexes.
function interface_field_names(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> string[] throws never {
    match (interface_) {
        let source: root.hir.DeclRefSource<int> => {
            root.hir.interface_data(db, source.value).fields.map((field) -> string {
                field.name
            })
        },
        let external: root.hir.DeclRefExternal<int> => {
            extern_interface_row(db, external.value).fields.map((field) -> string {
                field.0
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::InterfaceAssocDecls @ d9be6853b
// An interface's generic frame and its declared associated-type members.
class InterfaceAssocDecls {
    // The `Self` slot of the interface's frame.
    self_param: root.types.ParamTy,
    // The interface's own declared generic parameters: the frame after
    // `Self` (associated types are not slots).
    params: root.types.ParamTy[],
    // Every declared associated-type member in declaration order, with its
    // default (lowered once, with symbolic `Self`) where one is declared.
    members: (string, root.types.Ty?)[],
}

// port: baml_compiler2_hir_ty/src/layout.rs::interface_assoc_decls @ d9be6853b
// `interface_`'s frame and associated-type members, whichever lane declares
// it.
function interface_assoc_decls(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> InterfaceAssocDecls throws never {
    match (interface_) {
        let source: root.hir.DeclRefSource<int> => {
            let self_param = interface_frame(db, source.value).at(0)
                ?? baml.sys.panic("an interface frame starts with `Self`");
            let members = root.hir.interface_data(db, source.value).associated_types.map((assoc) -> (string, root.types.Ty?) {
                let default_ = root.hir_ty.interfaces.interface_associated_type_default(
                    db,
                    source.value,
                    assoc.name,
                );
                (assoc.name, default_?.0)
            });
            InterfaceAssocDecls {
                self_param: self_param,
                params: interface_declared_params(db, source.value),
                members: members,
            }
        },
        let external: root.hir.DeclRefExternal<int> => {
            let row = extern_interface_row(db, external.value);
            InterfaceAssocDecls {
                self_param: row.self_param,
                params: row.generic_params,
                members: row.associated_types.map((assoc) -> (string, root.types.Ty?) {
                    (assoc.name, assoc.default_)
                }),
            }
        },
    }
}
