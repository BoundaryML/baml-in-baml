// Items of other crates that MIR needs and that are not ported yet, in their
// Rust names. Each belongs in another namespace (named in its header) and
// lives here only because the MIR ports may edit `ns_mir/` alone: move it to
// its home when that file is next touched, and update the callers.
//
// Not here, also needed by MIR and missing from `root.hir_ty.layout`:
// `class_field_count`, `class_field_index`, `class_field_ty`,
// `enum_variant_index`, `enum_variants`, `interface_member` (MIR's
// `DeclaredMember`), `interface_ref_of`, `interface_requires_closure`,
// `lang_class`; most of `baml_type/src/template.rs` (`TyTemplate`
// substitution and display); `package_interface::ExportedFunction` and
// `extern_loc::extern_function_row` / `extern_interface_method` (whose
// lookups are none here: no root is served from an interface). The units
// that reach them add them to this file.

// port: baml_compiler2_hir_ty/src/layout.rs::class_head @ d9be6853b
// Home: `root.hir_ty` (layout.baml). The head a class declaration is spelled
// by.
function class_head(
    db: root.hir.Db,
    class_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> root.types.DeclName throws never {
    match (class_) {
        let source: root.hir.DeclRefSource<int> => {
            root.hir_ty.class_qualified_name(db, source.value)
        },
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic("class_head: a root served from its interface is not ported")
        },
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::enum_head @ d9be6853b
// Home: `root.hir_ty` (layout.baml). The head an enum declaration is spelled
// by.
function enum_head(
    db: root.hir.Db,
    enum_ref: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> root.types.DeclName throws never {
    match (enum_ref) {
        let source: root.hir.DeclRefSource<int> => {
            root.hir_ty.qualify_def(
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

// port: baml_compiler2_hir_ty/src/layout.rs::package_interfaces @ d9be6853b
// Home: `root.hir_ty` (layout.baml). Also `package_declarations` for
// interfaces: every interface `root_id` declares, in declaration order.
// Restructured as `root.hir_ty.package_aliases` is: the lazy iterator is an
// array, and the served lane (none here) panics.
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

// port: baml_compiler2_hir_ty/src/layout.rs::interface_method_names @ d9be6853b
// Home: `root.hir_ty` (layout.baml). The names of the methods an interface
// declares, required and default, in declaration order.
function interface_method_names(
    db: root.hir.Db,
    interface_: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> string[] throws never {
    match (interface_) {
        let source: root.hir.DeclRefSource<int> => {
            root.hir.interface_data(db, source.value).methods.map((method) -> {
                root.hir.function_data(db, method).name
            })
        },
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic("interface_method_names: a root served from its interface is not ported")
        },
    }
}

// port: baml_type/src/template.rs::TyTemplate::for_each_type_arg_ref @ d9be6853b
// Home: `root.types`. Every frame type-argument slot (`TyTypeArgRef`) the
// template reads, in visit order.
function ty_template_for_each_type_arg_ref(
    template: root.types.TyTemplate,
    f: (int) -> void throws never,
) -> void throws never {
    visit_template(template, (node) -> {
        match (node) {
            let r: root.types.TyTypeArgRef => f(r.index),
            _ => {},
        }
    });
}

// port: baml_type/src/template.rs::visit_template @ d9be6853b
// Home: `root.types`. Pre-order walk of a template and every nested
// template.
function visit_template(
    template: root.types.TyTemplate,
    visitor: (root.types.TyTemplate) -> void throws never,
) -> void throws never {
    visitor(template);
    match (template) {
        let t: root.types.TyTemplateList => visit_template(t.elem, visitor),
        let t: root.types.TyTemplateMap => {
            visit_template(t.key, visitor);
            visit_template(t.value, visitor);
        },
        let t: root.types.TyTemplateUnion => {
            for (let member in t.members) {
                visit_template(member, visitor);
            }
        },
        let t: root.types.TyTemplateTuple => {
            for (let item in t.items) {
                visit_template(item, visitor);
            }
        },
        let t: root.types.TyTemplateClass => {
            for (let arg in t.args) {
                visit_template(arg, visitor);
            }
        },
        let t: root.types.TyTemplateInterface => {
            for (let arg in t.args) {
                visit_template(arg, visitor);
            }
            for (let binding in t.associated_types) {
                visit_template(binding.ty, visitor);
            }
        },
        let t: root.types.TyTemplateFunction => {
            for (let param in t.params) {
                visit_template(param.ty, visitor);
            }
            visit_template(t.ret, visitor);
            visit_template(t.throws_, visitor);
        },
        let t: root.types.TyTemplateFuture => {
            visit_template(t.value, visitor);
            visit_template(t.error, visitor);
        },
        let t: root.types.TyTemplateAssociatedTypeProjection => {
            visit_template(t.base, visitor);
            for (let generic in t.interface_.generics) {
                visit_template(generic, visitor);
            }
            for (let binding in t.interface_.associated_types) {
                visit_template(binding.ty, visitor);
            }
        },
        _ => {},
    }
}

// port: baml_compiler2_hir_ty/src/layout.rs::InterfaceMember @ d9be6853b
// Home: `root.hir_ty` (layout.baml), as `InterfaceMember`. What one interface
// declaration says a member name is. MIR imports it as `DeclaredMember`
// (lower.rs's own `InterfaceMember` is the resolved view across a `requires`
// closure), and that is its name here.
type DeclaredMember = DeclaredMemberMethod | DeclaredMemberField;

class DeclaredMemberMethod {
}

// A field, at its position in the interface's own declared field list.
class DeclaredMemberField {
    index: int,
}

// port: baml_compiler2_hir_ty/src/package_interface.rs::ExportedFunction @ d9be6853b
// Home: `root.hir_ty` (package_interface_stubs.baml). A served package's
// exported function row. No root is served from an interface here, so MIR
// never holds one; the lookups that answer it (`extern_function_row`) are
// none. Not ported: the fields `target` (`ExternalCallTarget`) and
// `linkability` (`ExternalLinkability`), whose types are not ported.
class ExportedFunction {
    name: string,
    params: root.types.FunctionParamTy[],
    return_type: root.types.Ty,
    callable_throws: root.types.Ty,
    generic_params: root.types.ParamTy[],
    generic_param_bounds: root.types.InterfaceConstraint[][],
    builtin_kind: root.ast.BuiltinKind?,
}
