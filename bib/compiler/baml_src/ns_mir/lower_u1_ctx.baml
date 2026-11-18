// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// Unit 1 of the MIR plan, part two: the `LoweringContext` methods of unit 1
// (the plan's lower.rs 1918-2279, 2539-3275 and 4317-4529): language-package
// lookups, declaration refs and type tests, interface views, bindings and
// captures, defers and shields, the `tir_*` accessors over the
// `InferenceResult` tables, the runtime type conversion, and the
// expression/pattern type and template accessors.
//
// Restructured (BAML forces it), as in lower.baml: methods are free
// functions taking `ctx: LoweringContext` first; associated functions
// without `self` (`associated_binding_ty`, `scope_is_descendant_or_self`,
// `virtual_field_view_of`, ...) are plain free functions. `ClassRef` /
// `EnumRef` / `FunctionRef` / `GlobalRef` are their Source lane's `int`
// loc: a head the layout answers with an `External` ref panics (no root is
// served from an interface here).
//
// Not ported: `LoweringContext::lang` (a forward to `lang_roots`): call
// `root.hir.lang_roots(ctx.db)`.
//
// Changed signature: `spelled` returns the printed type (Rust returns the
// wire-headed `RuntimeTy<TypeName>`, which a message then prints; the
// family cannot spell that type, see pretty.baml).

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::runtime @ d9be6853b
// The crossing from this program's compile-time types to the wire.
function runtime(ctx: LoweringContext) -> RuntimeLowering throws never {
    RuntimeLowering { aliases: ctx.resolved_aliases, db: ctx.db }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lang_function @ d9be6853b
// A function the language ships and lowering targets by identity
// (`baml.sys.panic`, the `baml.ops` drivers, ...), whichever lane serves the
// package. Its absence is a compiler/stdlib mismatch.
function lang_function(
    ctx: LoweringContext,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> int throws never {
    let found = root.hir_ty.lang_function(ctx.db, package, namespace, name);
    if (found != null) {
        return found;
    }
    let path = namespace.concat([name]).join(".");
    baml.sys.panic(
        `internal compiler error: the \`${root.base.lang_package_manifest_name(package)}\` package declares no \`${path}\``,
    )
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lang_class_method @ d9be6853b
// `lang_function` for a class-inherent method of a language package's root
// class (`baml.String.from`, `baml.Array.slice`).
function lang_class_method(
    ctx: LoweringContext,
    package: root.base.LangPackage,
    class_: string,
    method: string,
) -> int throws never {
    let found = root.hir_ty.lang_class_method(ctx.db, package, class_, method);
    if (found != null) {
        return found;
    }
    baml.sys.panic(
        `internal compiler error: the \`${root.base.lang_package_manifest_name(package)}\` package declares no \`${class_}.${method}\``,
    )
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_lang_method @ d9be6853b
// Whether `func` is the method `owner.name` of a language package's root
// class or interface: the identity twin of a rendered-name test.
// `callable_display_name` is the function's declared name.
function is_lang_method(
    ctx: LoweringContext,
    func: int,
    package: root.base.LangPackage,
    owner: string,
    name: string,
) -> bool throws never {
    callee_owner_is_lang(ctx, func, package, owner)
        && root.hir.function_data(ctx.db, func).name == name
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::callee_owner_is_lang @ d9be6853b
// Whether `func` is owned by `owner`, a language package's root type.
function callee_owner_is_lang(
    ctx: LoweringContext,
    func: int,
    package: root.base.LangPackage,
    owner: string,
) -> bool throws never {
    let head = root.hir_ty.callable_owner_type(ctx.db, func);
    head != null
        && root.types.decl_name_is_lang_root_type(head, root.hir.lang_roots(ctx.db), package, owner)
}

// The Source lane of a layout ref: every declaration is a source one here.
function source_ref(
    decl_ref: root.hir.DeclRefSource<int> | root.hir.DeclRefExternal<int>,
) -> int throws never {
    match (decl_ref) {
        let source: root.hir.DeclRefSource<int> => source.value,
        root.hir.DeclRefExternal<int> => {
            baml.sys.panic("a root served from its interface is not ported")
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enum_ref_of @ d9be6853b
// The declaration an enum head names, wherever it lives. TIR admits an enum
// type only by resolving its declaration, so a head that names none here is
// an internal inconsistency, never a state to fall open on.
function enum_ref_of(
    ctx: LoweringContext,
    qtn: root.types.DeclName,
) -> int throws MirInternalError {
    let found = root.hir_ty.enum_ref_of(ctx.db, qtn);
    if (found == null) {
        throw internal_error_here(
            ctx,
            `TIR admitted the enum \`${qtn.name}\`, which no declaration in this compilation names`,
        );
    }
    source_ref(found)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enum_variant_index @ d9be6853b
// The discriminant of `variant` in `enum_ref`'s declared order. TIR admitted
// the variant against this very declaration, so a miss is a compiler bug.
function enum_variant_index(
    ctx: LoweringContext,
    enum_ref: int,
    variant: string,
) -> int throws MirInternalError {
    let index = root.hir_ty.enum_variant_index(ctx.db, root.hir.DeclRefSource { value: enum_ref }, variant);
    if (index == null) {
        throw internal_error_here(
            ctx,
            `TIR admitted the variant \`${variant}\` of \`${enum_display_name(ctx.db, enum_ref)}\`, which the enum does not declare`,
        );
    }
    index
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lang_class @ d9be6853b
// A class the language ships and lowering constructs by identity
// (`baml.TaggedString`, `baml.spawn.Params`), whichever lane serves the
// package. Its absence is a compiler/stdlib mismatch.
function lang_class(
    ctx: LoweringContext,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> int throws never {
    let path = namespace.concat([name]).join(".");
    let found = root.hir_ty.lang_class(ctx.db, package, namespace, name)
        ?? baml.sys.panic(
            `internal error: the \`${package}\` language package declares no class \`${path}\``,
        );
    source_ref(found)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_ref_of @ d9be6853b
// The declaration a class head names, wherever it lives. TIR admits a class
// type only by resolving its declaration, so a head that names none here is
// an internal inconsistency, never a state to fall open on.
function class_ref_of(
    ctx: LoweringContext,
    head: root.types.DeclName,
) -> int throws MirInternalError {
    let found = root.hir_ty.class_ref_of(ctx.db, head);
    if (found == null) {
        throw internal_error_here(
            ctx,
            `TIR admitted the class \`${head.name}\`, which no declaration in this compilation names`,
        );
    }
    source_ref(found)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_test @ d9be6853b
// A type test of `template`, stated by declaration where it is nominal: a
// class or an enum is tested by the declaration its head names.
function type_test(
    ctx: LoweringContext,
    template: root.types.TyTemplate,
) -> TypeTest throws MirInternalError {
    match (template) {
        let c: root.types.TyTemplateClass => {
            TypeTestClass { class_: class_ref_of(ctx, c.name), args: c.args }
        },
        let e: root.types.TyEnum => TypeTestEnum { value: enum_ref_of(ctx, e.name) },
        _ => TypeTestTemplate { value: template },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_field_slot @ d9be6853b
// Where `field` sits in `class_`'s layout and the type it holds there, with
// the receiver's class arguments substituted into the declared field type,
// so a generic position (`item: T` in `Box<T>`) reads as the concrete
// receiver-side binding. Null when the class declares no such field.
function class_field_slot(
    ctx: LoweringContext,
    class_: int,
    field: string,
    class_type_args: root.types.RuntimeTy[],
) -> (int, root.types.RuntimeTy)? throws never {
    let class_ref = root.hir.DeclRefSource { value: class_ };
    let index = root.hir_ty.class_field_index(ctx.db, class_ref, field)
        ?? return null;
    let declared = root.hir_ty.class_field_ty(ctx.db, class_ref, field)
        ?? baml.sys.panic("the field just indexed is declared");
    let class_generic_params = root.hir_ty.class_generic_params(ctx.db, class_ref);
    let template = tir2_to_template(declared, runtime(ctx), class_generic_params);
    (index, root.types.ty_template_substitute_symbolic(template, class_type_args))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::display_viewpoint @ d9be6853b
// The viewpoint a function's DISPLAY fields (`display_param_types`,
// `display_return_type`) spell types from: the package's root namespace,
// facing a host that reads the package as a whole (`Viewpoint::user_facing`).
function display_viewpoint(ctx: LoweringContext) -> root.hir_ty.Viewpoint throws never {
    root.hir_ty.Viewpoint.for_namespace(ctx.db, ctx.db.file(ctx.file).root)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::baml_iter_decl @ d9be6853b
// `baml.iter.<name>` as a compile-time head, or null without the stdlib.
function baml_iter_decl(ctx: LoweringContext, name: string) -> root.types.DeclName? throws never {
    let baml = root.hir.lang_roots(ctx.db).get(root.base.LangPackage.Baml)
        ?? return null;
    root.types.DeclName { pkg: baml, namespace: ["iter"], name: name }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::baml_decl @ d9be6853b
// `baml.<namespace>.<name>` as a head. Lowering names one only for a
// construct the language package itself defines the meaning of (a `for`
// loop's iterator protocol, an ordering operator), so the package's absence
// there is a compiler/stdlib mismatch.
function baml_decl(
    ctx: LoweringContext,
    namespace: string,
    name: string,
) -> root.types.DeclName throws never {
    let baml = root.hir.lang_roots(ctx.db).get(root.base.LangPackage.Baml)
        ?? baml.sys.panic(
            `internal error: lowering names \`baml.${namespace}.${name}\`, but the \`baml\` language package is not installed`,
        );
    root.types.DeclName { pkg: baml, namespace: [namespace], name: name }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::baml_iter_done_ty @ d9be6853b
function baml_iter_done_ty(ctx: LoweringContext) -> root.types.RuntimeTy throws never {
    root.types.RuntimeTyClass { name: baml_decl(ctx, "iter", "Done"), args: [] }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::spelled @ d9be6853b
// A MIR type rendered canonically, for a message. Restructured: returns the
// text (heads by `RuntimeLowering::wire`, which is the canonical
// viewpoint's `wire_head`, as `Names` spells them).
function spelled(ctx: LoweringContext, ty: root.types.RuntimeTy) -> string throws never {
    Names.of(ctx.db).ty(ty)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::associated_binding_ty @ d9be6853b
function associated_binding_ty(
    bindings: (string, root.types.Ty)[],
    name: string,
) -> root.types.Ty? throws never {
    bindings.find((binding) -> {
        binding.0 == name
    })?.1
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::substitute_class_params_in_interface_view @ d9be6853b
// The view with a class's parameters replaced by the class's arguments; an
// unargued parameter stays itself.
function substitute_class_params_in_interface_view(
    view: InterfaceTypeView,
    class_params: root.types.ParamTy[],
    class_args: root.types.Ty[],
) -> InterfaceTypeView throws never {
    if (class_params.length() == 0) {
        return view;
    }
    let bindings: map<root.types.ParamTy, root.types.Ty> = {};
    let pairs = if (class_params.length() < class_args.length()) {
        class_params.length()
    } else {
        class_args.length()
    };
    for (let i = 0; i < pairs; i += 1) {
        bindings[class_params[i]] = class_args[i];
    }
    for (let param in class_params) {
        if (!bindings.has(param)) {
            bindings[param] = root.types.TyTypeVar { param: param };
        }
    }
    (
        view.0,
        view.1.map((ty) -> {
            root.types.substitute_ty(ty, bindings)
        }),
        view.2.map((binding) -> {
            (binding.0, root.types.substitute_ty(binding.1, bindings))
        }),
    )
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_view_for_class_tir_ty @ d9be6853b
// The `target_tn` view a class's in-body `implements` blocks provide. A
// served class's witnesses are impl rows, read through the impl registry
// instead (none here).
function interface_view_for_class_tir_ty(
    ctx: LoweringContext,
    class_qtn: root.types.DeclName,
    class_args: root.types.Ty[],
    target_tn: root.types.DeclName,
) -> InterfaceTypeView? throws never {
    let class_loc = match (root.hir_ty.class_ref_of(ctx.db, class_qtn)) {
        let source: root.hir.DeclRefSource<int> => source.value,
        _ => {
            return null;
        },
    };
    let class_params = root.hir_ty.class_generic_frame(ctx.db, class_loc);
    for (let impl_loc in root.hir.class_impls(ctx.db, class_loc)) {
        let impl_block = root.hir.impl_block_data(ctx.db, impl_loc);
        let view = resolve_implements_target_view(
            ctx,
            impl_block.type_refs,
            impl_block.interface_target,
            impl_block.associated_type_bindings,
            class_loc,
        )
            ?? return null;
        let views = interface_closure_type_name_views(ctx, view.0, view.1, view.2)
            ?? return null;
        for (let candidate in views) {
            if (candidate.0 == target_tn) {
                return substitute_class_params_in_interface_view(candidate, class_params, class_args);
            }
        }
    }
    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::realized_interface_view_for @ d9be6853b
// The realized view of the `target_tn` interface a receiver of type
// `actual_ty` provides: through its own `requires` closure for an
// interface-existential receiver (`target_tn` may be the interface itself or
// a `requires` parent), or through one of its impls for a concrete-headed
// receiver, enumerated via the canonical L1 substrate.
function realized_interface_view_for(
    ctx: LoweringContext,
    actual_ty: root.types.Ty,
    target_tn: root.types.DeclName,
) -> InterfaceTypeView? throws never {
    match (actual_ty) {
        let i: root.types.TyInterface => {
            let assoc = i.associated_types.map((binding) -> {
                (binding.name, binding.ty)
            });
            let views = interface_closure_type_name_views(ctx, i.name, i.args, assoc)
                ?? return null;
            return views.find((view) -> {
                view.0 == target_tn
            });
        },
        _ => {},
    }
    for (let impl_view in l1_impl_views_for_recv(ctx, actual_ty, target_tn)) {
        let views = interface_closure_type_name_views(ctx, impl_view.0, impl_view.1, impl_view.2);
        if (views == null) {
            continue;
        }
        let view = views.find((candidate) -> {
            candidate.0 == target_tn
        });
        if (view != null) {
            return view;
        }
    }
    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_view_for_tir_ty @ d9be6853b
function interface_view_for_tir_ty(
    ctx: LoweringContext,
    ty: root.types.Ty,
    target_tn: root.types.DeclName,
) -> InterfaceTypeView? throws never {
    match (ty) {
        let i: root.types.TyInterface => {
            let assoc = i.associated_types.map((binding) -> {
                (binding.name, binding.ty)
            });
            let views = interface_closure_type_name_views(ctx, i.name, i.args, assoc)
                ?? return null;
            views.find((view) -> {
                view.0 == target_tn
            })
        },
        let c: root.types.TyClass => {
            interface_view_for_class_tir_ty(ctx, c.name, c.args, target_tn)
                ?? realized_interface_view_for(ctx, ty, target_tn)
        },
        let a: root.types.TyTypeAlias if !ctx.resolved_aliases.recursive.has(a.name) => {
            let target = ctx.resolved_aliases.aliases.get(a.name);
            let through_target = if (target != null) {
                interface_view_for_tir_ty(ctx, target, target_tn)
            } else {
                null
            };
            through_target ?? realized_interface_view_for(ctx, ty, target_tn)
        },
        let v: root.types.TyTypeVar => {
            for (let bound in ctx.generic_param_bounds.get(v.param) ?? []) {
                let view = interface_view_for_tir_ty(ctx, plain_interface_ty(bound), target_tn);
                if (view != null) {
                    return view;
                }
            }
            null
        },
        root.types.TyAssociatedTypeProjection => {
            let resolved = resolve_ty_projections(ctx, ty);
            if (resolved != ty) {
                return interface_view_for_tir_ty(ctx, resolved, target_tn);
            }
            for (let bound in resolve_projection_bounds(ctx, ty)) {
                let view = interface_view_for_tir_ty(ctx, bound, target_tn);
                if (view != null) {
                    return view;
                }
            }
            null
        },
        _ => realized_interface_view_for(ctx, ty, target_tn),
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::iterable_view_for_tir_ty @ d9be6853b
function iterable_view_for_tir_ty(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> InterfaceTypeView? throws never {
    interface_view_for_tir_ty(ctx, ty, baml_decl(ctx, "iter", "Iterable"))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::scope_is_descendant_or_self @ d9be6853b
function scope_is_descendant_or_self(
    index: root.hir.FileSemanticIndex,
    scope_id: int,
    ancestor_id: int,
) -> bool throws never {
    let current: int? = scope_id;
    while let id: int = current {
        if (id == ancestor_id) {
            return true;
        }
        current = index.scopes[id].parent;
    }
    false
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::binding_id_for_pattern_site_name @ d9be6853b
// The HIR binding `name` introduces in `pattern` at `site`, searched in the
// scopes under the current one, scope by scope in id order.
function binding_id_for_pattern_site_name(
    ctx: LoweringContext,
    pattern: int,
    site: root.hir.DefinitionSite,
    name: string,
) -> root.hir.BindingId? throws never {
    let index = root.hir.file_semantic_index(ctx.db, ctx.file);
    let source_map = ctx.source_map;
    let pattern_span = if (source_map != null) {
        source_map.pattern_span(pattern)
    } else {
        null
    };
    for (let scope_idx = 0; scope_idx < index.scope_bindings.length(); scope_idx += 1) {
        if (!scope_is_descendant_or_self(index, scope_idx, ctx.current_scope)) {
            continue;
        }
        let bindings = index.scope_bindings[scope_idx].bindings;
        for (let binding_idx = 0; binding_idx < bindings.length(); binding_idx += 1) {
            let binding = bindings[binding_idx];
            let range = binding.name_range;
            let pattern_matches_name_range = pattern_span == null
                || pattern_span == range
                || (pattern_span.start <= range.start && range.end <= pattern_span.end);
            if (
                binding.site == site
                    && binding.pattern == pattern
                    && binding.name == name
                    && pattern_matches_name_range
            ) {
                return root.hir.BindingId.local(scope_idx, binding_idx);
            }
        }
    }
    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::binding_is_captured @ d9be6853b
// Whether a nested closure captures `binding`, per HIR's capture analysis.
// That analysis is complete before MIR runs: a capture through any depth of
// nesting marks the binding in its declaring scope.
function binding_is_captured(
    ctx: LoweringContext,
    binding: root.hir.BindingId,
) -> bool throws never {
    let index = root.hir.file_semantic_index(ctx.db, ctx.file);
    let scope = index.scope_bindings.at(binding.scope);
    scope != null && scope.captured_bindings.has(binding)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::value_place @ d9be6853b
// The place holding a binding's value: the local itself, or the cell behind
// it when a closure captures the binding.
function value_place(ctx: LoweringContext, local: int) -> Place throws never {
    if (ctx.builder.local_decl(local).is_captured) {
        PlaceDeref { value: PlaceLocal { value: local } }
    } else {
        PlaceLocal { value: local }
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::self_local @ d9be6853b
// The local holding the method's `self` parameter, while lowering the
// method's own frame. Inside a nested lambda `self` is a capture rather than
// a local (Rust's own BUG note: `default.<method>` there is an internal
// error).
function self_local(ctx: LoweringContext) -> int? throws never {
    let binding = ctx.self_binding
        ?? return null;
    ctx.binding_locals.get(binding)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_binding_is_captured @ d9be6853b
// `binding_is_captured` for the binding `name` introduces in `pattern` at
// `site`.
function pattern_binding_is_captured(
    ctx: LoweringContext,
    pattern: int,
    site: root.hir.DefinitionSite,
    name: string,
) -> bool throws never {
    let binding_id = binding_id_for_pattern_site_name(ctx, pattern, site, name);
    binding_id != null && binding_is_captured(ctx, binding_id)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::binding_id_for_statement_name @ d9be6853b
function binding_id_for_statement_name(
    ctx: LoweringContext,
    stmt_id: int,
    pattern: int,
    name: string,
) -> root.hir.BindingId? throws never {
    binding_id_for_pattern_site_name(ctx, pattern, root.hir.DefinitionSiteStatement { value: stmt_id }, name)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::captured_locals_of_statement @ d9be6853b
// The captured locals among the bindings `stmt` declared (a `let`; any
// other statement declares none). The statement must already be lowered.
function captured_locals_of_statement(ctx: LoweringContext, stmt: int) -> int[] throws never {
    let pattern = match (ctx.body.stmts[stmt]) {
        let s: root.ast.StmtLet => s.pattern,
        _ => {
            return [];
        },
    };
    root.ast.pattern_bound_names(ctx.body.patterns[pattern], ctx.body.patterns)
        .filter_map((name) -> {
            binding_id_for_statement_name(ctx, stmt, pattern, name)
        })
        .filter_map((binding_id) -> {
            ctx.binding_locals.get(binding_id)
        })
        .filter((local) -> {
            ctx.builder.local_decl(local).is_captured
        })
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::recell_per_iteration @ d9be6853b
function recell_per_iteration(ctx: LoweringContext, locals: int[]) -> void throws never {
    for (let local in locals) {
        ctx.builder.recell_with_current_value(local);
    }
}

// Rust's derived `Debug` of a `DefinitionSite` (ids as `la_arena`'s
// `Idx::<T>(n)`), for internal-error messages.
function definition_site_debug(site: root.hir.DefinitionSite) -> string throws never {
    match (site) {
        let s: root.hir.DefinitionSiteStatement => `Statement(Idx::<Stmt>(${s.value}))`,
        let s: root.hir.DefinitionSiteParameter => `Parameter(${s.value})`,
        let s: root.hir.DefinitionSitePatternBinding => `PatternBinding(Idx::<Pattern>(${s.value}))`,
        let s: root.hir.DefinitionSiteCatchBinding => `CatchBinding(Idx::<Pattern>(${s.value}))`,
    }
}

// The binding `name` introduces in `pattern` at `site`, or the internal
// error `declare_binding` and `bind_existing_local` both raise when HIR
// registered none. Restructured: Rust repeats this `ok_or_else` in both.
function hir_binding_or_error(
    ctx: LoweringContext,
    pattern: int,
    site: root.hir.DefinitionSite,
    name: string,
) -> root.hir.BindingId throws MirInternalError {
    let binding_id = binding_id_for_pattern_site_name(ctx, pattern, site, name);
    if (binding_id == null) {
        throw internal_error_here(
            ctx,
            `no HIR binding for \`${name}\` at ${definition_site_debug(site)} within scope FileScopeId(${ctx.current_scope})`,
        );
    }
    binding_id
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::declare_binding @ d9be6853b
// Declare the local that holds the binding `name` introduces in `pattern`
// at `site`, creating its cell if a closure captures it. The one way to
// obtain a local for a user-visible name: it records the local under the
// binding's HIR identity and, when a closure captures the binding, cells it
// right here, where the binding is created. Emit the initializing store
// after this, never before. The site is part of the binding's identity.
function declare_binding(
    ctx: LoweringContext,
    pattern: int,
    site: root.hir.DefinitionSite,
    name: string,
    ty: root.types.RuntimeTy,
) -> int throws MirInternalError {
    let binding_id = hir_binding_or_error(ctx, pattern, site, name);
    let local = if (binding_is_captured(ctx, binding_id)) {
        ctx.builder.declare_captured_local(name, ty, null)
    } else {
        ctx.builder.declare_local(ty, name = name)
    };
    ctx.binding_locals[binding_id] = local;
    local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::declare_parameter @ d9be6853b
// Declare the local for parameter `param_idx` of the function or lambda
// being lowered. A captured parameter is celled by the frame preamble rather
// than here: the caller has already written its value into the slot.
function declare_parameter(
    ctx: LoweringContext,
    param_idx: int,
    name: string,
    ty: root.types.RuntimeTy,
) -> int throws never {
    let binding_id = root.hir.BindingId.parameter(ctx.current_scope, param_idx);
    let local = if (binding_is_captured(ctx, binding_id)) {
        ctx.builder.declare_captured_local(name, ty, null)
    } else {
        ctx.builder.declare_local(ty, name = name)
    };
    ctx.binding_locals[binding_id] = local;
    local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::bind_existing_local @ d9be6853b
// Record that the binding `name` introduces in `pattern` at `site` is held
// by `local`, a slot the runtime writes directly (a caught error or its
// stack trace). Only for a binding no closure captures.
function bind_existing_local(
    ctx: LoweringContext,
    pattern: int,
    site: root.hir.DefinitionSite,
    name: string,
    local: int,
) -> void throws MirInternalError {
    let binding_id = hir_binding_or_error(ctx, pattern, site, name);
    if (binding_is_captured(ctx, binding_id)) {
        throw internal_error_here(ctx, `\`${name}\` is captured; it needs its own local from \`declare_binding\``);
    }
    ctx.binding_locals[binding_id] = local;
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_resolution @ d9be6853b
function path_resolution(
    ctx: LoweringContext,
    expr_id: int,
) -> root.hir.PathResolution? throws never {
    root.hir.file_semantic_index(ctx.db, ctx.file).path_resolution(expr_metadata_key(ctx, expr_id))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::hir_binding_id_for_path @ d9be6853b
function hir_binding_id_for_path(
    ctx: LoweringContext,
    expr_id: int,
) -> root.hir.BindingId? throws never {
    match (path_resolution(ctx, expr_id)) {
        let local: root.hir.PathResolutionLocal => local.value,
        root.hir.PathResolutionItem | null => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::binding_id_for_path @ d9be6853b
// A path the checker resolved to a global names no local: TIR records a
// global root only where nothing shadows it, and its bare form can still
// spell one (`with_bare_global_paths`). Tagged-template body parameters are
// synthetic bindings: a HIR binding wins only inside the tagged body scope,
// where it is a real lexical shadow.
function binding_id_for_path(
    ctx: LoweringContext,
    expr_id: int,
    name: string,
) -> root.hir.BindingId? throws never {
    if (tir_global_root(ctx, expr_id) != null) {
        return null;
    }
    let hir_binding = hir_binding_id_for_path(ctx, expr_id);
    let tagged_binding = ctx.tagged_body_param_bindings.get(name)
        ?? return hir_binding;
    if (hir_binding == null) {
        return tagged_binding;
    }
    let index = root.hir.file_semantic_index(ctx.db, ctx.file);
    if (index.ancestor_scopes(hir_binding.scope).includes(tagged_binding.scope)) {
        hir_binding
    } else {
        tagged_binding
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::local_for_path @ d9be6853b
function local_for_path(ctx: LoweringContext, expr_id: int, name: string) -> int? throws never {
    let binding_id = binding_id_for_path(ctx, expr_id, name)
        ?? return null;
    ctx.binding_locals.get(binding_id)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::refined_root_local_ty @ d9be6853b
// The type of a path root held by `local`, preferring what TIR inferred for
// the root expression. When TIR knows a more specific type than the local's
// `unknown` declaration, the declaration is refined too, so the emitter can
// resolve field names for display.
function refined_root_local_ty(
    ctx: LoweringContext,
    expr_id: int,
    local: int,
) -> root.types.RuntimeTy throws never {
    let tir_root = path_root_ty(ctx, expr_id)
        ?? return ctx.builder.local_ty(local);
    if (ctx.builder.local_ty(local) is root.types.TyUnknown && !(tir_root is root.types.TyUnknown)) {
        ctx.builder.set_local_ty(local, tir_root);
    }
    tir_root
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::place_for_path @ d9be6853b
// The place holding the value of the binding `name` resolves to at
// `expr_id`: a local, or the value behind a cell for a captured binding or a
// capture.
function place_for_path(ctx: LoweringContext, expr_id: int, name: string) -> Place? throws never {
    let binding_id = binding_id_for_path(ctx, expr_id, name)
        ?? return null;
    let local = ctx.binding_locals.get(binding_id);
    if (local != null) {
        return value_place(ctx, local);
    }
    let capture = ctx.capture_indices?.get(binding_id);
    if (capture != null) {
        return PlaceDeref { value: PlaceCapture { value: capture } };
    }
    if (ctx.tagged_body_param_bindings.get(name) == binding_id) {
        let transitive = ensure_transitive_capture(ctx, binding_id);
        return PlaceDeref { value: PlaceCapture { value: transitive } };
    }
    null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ensure_transitive_capture @ d9be6853b
// Return the current lambda's capture index for `binding_id`, allocating a
// fresh one (and signalling the parent to forward it via
// `transitive_captures_needed`) when it isn't captured yet.
function ensure_transitive_capture(
    ctx: LoweringContext,
    binding_id: root.hir.BindingId,
) -> int throws never {
    let existing = ctx.capture_indices?.get(binding_id);
    if (existing != null) {
        return existing;
    }
    let captures = ctx.capture_indices;
    if (captures == null) {
        captures = {};
        ctx.capture_indices = captures;
    }
    let idx = captures.length();
    captures[binding_id] = idx;
    ctx.transitive_captures_needed.push(binding_id);
    idx
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::replay_defers_to_depth @ d9be6853b
// Re-lower the `defer` bodies armed at `[defer_depth..]` of `defer_stack`,
// in reverse declaration order (LIFO): BEP-042. Each body is re-lowered
// inline so it reads the live enclosing locals at THIS exit point; it does
// not truncate the stack. A body unwinds to the handler in force where its
// defer was armed. Rust's `.to_vec()` is a `slice`, a fresh array.
function replay_defers_to_depth(
    ctx: LoweringContext,
    defer_depth: int,
) -> void throws MirInternalError {
    let defers = ctx.defer_stack.slice(defer_depth, ctx.defer_stack.length());
    if (defers.length() == 0) {
        return;
    }
    let exit_unwind = ctx.builder.current_unwind;
    for (let i = defers.length() - 1; i >= 0; i -= 1) {
        if (ctx.builder.is_current_terminated()) {
            break;
        }
        let armed = defers[i];
        ctx.builder.transition_unwind(armed.unwind);
        lower_shielded_defer_body(ctx, armed.body);
    }
    ctx.builder.transition_unwind(exit_unwind);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_shielded_defer_body @ d9be6853b
// Lower one copy of a `defer` body shielded from cancellation: its blocks
// are stamped `shielded`, and the engine does not deliver `Cancelled` inside
// them, so cleanup may suspend (BEP-034's shield, implicit for `defer`).
function lower_shielded_defer_body(
    ctx: LoweringContext,
    body: int,
) -> void throws MirInternalError {
    shielded(ctx, (this: LoweringContext) -> void throws MirInternalError {
        let tmp = this.builder.declare_local(expr_ty(this, body));
        lower_expr(this, body, PlaceLocal { value: tmp });
    })
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::shielded @ d9be6853b
// Lower with `f` shielded from cancellation: the blocks it creates are
// stamped `shielded`, and the shield closes when it returns, so a shield is
// never opened without being closed. Restructured: `R` may carry a
// `MirInternalError` (Rust's `Lowered`), so `f` declares it, and the shield
// also closes on the throw.
function shielded<R>(
    ctx: LoweringContext,
    f: (LoweringContext) -> R throws MirInternalError,
) -> R throws MirInternalError {
    let shield = ctx.builder.enter_shield();
    let result = f(ctx) catch (e) {
        MirInternalError => {
            ctx.builder.leave_shield(shield);
            throw e;
        },
    };
    ctx.builder.leave_shield(shield);
    result
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::verify_bindings_recorded @ d9be6853b
// Every binding HIR registered in the scopes this body lowers has a local:
// the tripwire for a declaration site that bypassed `declare_binding`.
// Nested lambda subtrees are skipped (lowered in their own context), and so
// are the statements of `unlowered_block`, a desugared block the lowering
// replaced wholesale (a tagged template's static layout).
function verify_bindings_recorded(
    ctx: LoweringContext,
    root_scope: int,
    unlowered_block: int?,
) -> void throws never {
    let index = root.hir.file_semantic_index(ctx.db, ctx.file);
    let root_s = index.scopes[root_scope];
    let unlowered_stmts: int[] = if (unlowered_block != null) {
        match (ctx.body.exprs[unlowered_block]) {
            let block: root.ast.ExprBlock => block.stmts,
            _ => baml.sys.panic("a desugared template body is a block"),
        }
    } else {
        []
    };
    let owner = function_owner_short_name(ctx.db, ctx.builder.owner);
    for (let scope_id = root_scope; scope_id < root_s.descendants.end; scope_id += 1) {
        if (inside_nested_lambda(index, scope_id, root_scope)) {
            continue;
        }
        let scope = index.scope_bindings.at(scope_id);
        if (scope == null) {
            continue;
        }
        for (let binding_idx = 0; binding_idx < scope.bindings.length(); binding_idx += 1) {
            let binding = scope.bindings[binding_idx];
            let site = binding.site;
            if (site is root.hir.DefinitionSiteStatement && unlowered_stmts.includes(site.value)) {
                continue;
            }
            if (!ctx.binding_locals.has(root.hir.BindingId.local(scope_id, binding_idx))) {
                baml.sys.panic(
                    `lowering ${owner} gave no local to \`${binding.name}\` (registered by ${definition_site_debug(site)} in scope FileScopeId(${scope_id}))`,
                );
            }
        }
        if (scope_id == root_scope) {
            for (let param in scope.params) {
                if (!ctx.binding_locals.has(root.hir.BindingId.parameter(scope_id, param.1))) {
                    baml.sys.panic(`lowering ${owner} gave no local to parameter \`${param.0}\``);
                }
            }
        }
    }
}

// Whether `scope_id` or an ancestor below `root_scope` is a lambda scope:
// Rust's `successors(Some(scope_id), parent).take_while(|id| *id !=
// root_scope).any(..)` in `verify_bindings_recorded`.
function inside_nested_lambda(
    index: root.hir.FileSemanticIndex,
    scope_id: int,
    root_scope: int,
) -> bool throws never {
    let current: int? = scope_id;
    while let id: int = current {
        if (id == root_scope) {
            return false;
        }
        if (index.scopes[id].kind == root.hir.ScopeKind.Lambda) {
            return true;
        }
        current = index.scopes[id].parent;
    }
    false
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::expr_metadata_key @ d9be6853b
// The semantic-index key of an expression of the arena being lowered
// (`current_metadata_scope`).
function expr_metadata_key(
    ctx: LoweringContext,
    expr_id: int,
) -> root.hir.ExprMetadataKey throws never {
    root.hir.ExprMetadataKey.new(ctx.current_metadata_scope, expr_id)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pat_metadata_key @ d9be6853b
function pat_metadata_key(ctx: LoweringContext, pat_id: int) -> PatMetadataKey throws never {
    (ctx.current_metadata_scope, pat_id)
}

// --- Inference views: point lookups into `hir_ty`'s results for the arena
// being lowered (`ctx.inference_root`), keyed by the arena's own ids.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_tables @ d9be6853b
function tir_tables(
    ctx: LoweringContext,
) -> root.hir_ty.InferenceResult<root.types.Ty>? throws never {
    ctx.tables.of(ctx.inference_root)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_expr_type @ d9be6853b
function tir_expr_type(ctx: LoweringContext, expr: int) -> root.types.Ty? throws never {
    let tables = tir_tables(ctx)
        ?? return null;
    tables.type_of_expr.get(expr)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_pat_type @ d9be6853b
function tir_pat_type(ctx: LoweringContext, pat: int) -> root.types.Ty? throws never {
    let tables = tir_tables(ctx)
        ?? return null;
    tables.type_of_pat.get(pat)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_resolution @ d9be6853b
function tir_resolution(
    ctx: LoweringContext,
    expr: int,
) -> root.hir_ty.MemberResolution? throws never {
    let tables = tir_tables(ctx)
        ?? return null;
    tables.member_resolutions.get(expr)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_field_view_of @ d9be6853b
// The interface view and field index a recorded member resolution carries
// when it is a virtual-field read; every other resolution kind is null.
// Authoritative, and preferred over re-deriving a view from the receiver's
// type: it is the only thing that answers a union receiver.
function virtual_field_view_of(
    resolution: root.hir_ty.MemberResolution,
) -> (InterfaceTypeView, int)? throws never {
    let field = match (resolution) {
        let r: root.hir_ty.MemberResolutionInterfaceVirtualField<root.types.Ty> => r,
        _ => {
            return null;
        },
    };
    match (field.view) {
        let i: root.types.TyInterface => {
            let assoc = i.associated_types.map((binding) -> {
                (binding.name, binding.ty)
            });
            ((i.name, i.args, assoc), field.field_index)
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_method_view_of @ d9be6853b
// The interface view a recorded member resolution dispatches a method
// through, when it is a virtual slot bound to its receiver; every other
// resolution kind is null.
function virtual_method_view_of(
    resolution: root.hir_ty.MemberResolution,
) -> InterfaceTypeView? throws never {
    let method = match (resolution) {
        let r: root.hir_ty.MemberResolutionMethod<root.types.Ty>
            if r.receiver == root.hir_ty.Receiver.Bound => r,
        _ => {
            return null;
        },
    };
    let view = match (method.callee) {
        let v: root.hir_ty.MethodCalleeVirtual<root.types.Ty> => v.view,
        _ => {
            return null;
        },
    };
    match (view) {
        let i: root.types.TyInterface => {
            (
                i.name,
                i.args,
                i.associated_types.map((binding) -> {
                    (binding.name, binding.ty)
                }),
            )
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_virtual_field_view @ d9be6853b
function tir_virtual_field_view(
    ctx: LoweringContext,
    expr: int,
) -> (InterfaceTypeView, int)? throws never {
    let resolution = tir_resolution(ctx, expr)
        ?? return null;
    virtual_field_view_of(resolution)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_segment_virtual_field_view @ d9be6853b
// The recorded virtual-field view of member segment `seg_idx` of a path
// ladder (1-based within the path: segment 0 is the root), resolved through
// the interface the access was CHECKED against.
function tir_path_segment_virtual_field_view(
    ctx: LoweringContext,
    expr: int,
    seg_idx: int,
) -> (InterfaceTypeView, int)? throws never {
    if (seg_idx < 1) {
        return null;
    }
    let resolution = tir_path_member_resolution(ctx, expr, seg_idx - 1)
        ?? return null;
    virtual_field_view_of(resolution)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_is_exhaustive_match @ d9be6853b
function tir_is_exhaustive_match(ctx: LoweringContext, expr: int) -> bool throws never {
    let tables = tir_tables(ctx);
    tables == null || tables.is_exhaustive_match(expr)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path @ d9be6853b
// The value-rooted ladder recorded for a path expression.
function tir_path(
    ctx: LoweringContext,
    expr: int,
) -> root.hir_ty.ResolvedPath<root.types.Ty>? throws never {
    let tables = tir_tables(ctx)
        ?? return null;
    tables.path_resolutions.get(expr)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_root_type @ d9be6853b
function tir_path_root_type(ctx: LoweringContext, expr: int) -> root.types.Ty? throws never {
    let path = tir_path(ctx, expr)
        ?? return null;
    path.segments.at(0)?.ty
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_global_root @ d9be6853b
// The top-level `let` TIR resolved this path expression's leading segments
// to, with how many segments name it.
function tir_global_root(ctx: LoweringContext, expr: int) -> root.hir_ty.GlobalRoot? throws never {
    let tables = tir_tables(ctx)
        ?? return null;
    tables.global_roots.get(expr)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_segment_type @ d9be6853b
function tir_path_segment_type(
    ctx: LoweringContext,
    expr: int,
    seg_idx: int,
) -> root.types.Ty? throws never {
    let path = tir_path(ctx, expr)
        ?? return null;
    path.segments.at(seg_idx)?.ty
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_member_resolution @ d9be6853b
// The resolution of member segment `member_index` (0 = the first member
// after the root) of a fully resolved ladder.
function tir_path_member_resolution(
    ctx: LoweringContext,
    expr: int,
    member_index: int,
) -> root.hir_ty.MemberResolution? throws never {
    let path = tir_path(ctx, expr)
        ?? return null;
    path.member_resolution(member_index)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_final_resolution @ d9be6853b
// The final segment's resolution of a fully resolved ladder: what a
// value-rooted path names.
function tir_path_final_resolution(
    ctx: LoweringContext,
    expr: int,
) -> root.hir_ty.MemberResolution? throws never {
    let path = tir_path(ctx, expr)
        ?? return null;
    path.final_member_resolution()
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_call_plan @ d9be6853b
function tir_call_plan(
    ctx: LoweringContext,
    expr: int,
) -> root.hir_ty.CallPlan<root.types.Ty>? throws never {
    let tables = tir_tables(ctx)
        ?? return null;
    tables.call_plans.get(expr)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_type_binding @ d9be6853b
function tir_type_binding(
    ctx: LoweringContext,
    stmt: int,
) -> root.hir_ty.ScopedTypeBinding? throws never {
    let tables = tir_tables(ctx)
        ?? return null;
    tables.type_bindings.get(stmt)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_truthy_condition @ d9be6853b
function tir_truthy_condition(ctx: LoweringContext, expr: int) -> bool throws never {
    let tables = tir_tables(ctx);
    tables != null && tables.is_truthy_condition(expr)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::convert_tir_ty_for_runtime @ d9be6853b
// Resolve associated-type projections against the bounds the compiler
// knows statically; anything still symbolic (a `TypeVar` or a projection off
// one) is kept faithfully so the runtime can resolve it from the receiver's
// actual type. Type variables are deliberately not erased.
function convert_tir_ty_for_runtime(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> root.types.RuntimeTy throws never {
    let resolved = resolve_ty_projections(ctx, ty);
    let runtime_ready = runtime_ready_ty(resolved);
    runtime(ctx).convert(runtime_ready)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::runtime_ready_ty @ d9be6853b
// A checked type's runtime representation: literal freshness is a
// compile-time property and drops, and a slotless effect parameter has no
// frame slot to name. The error sentinel is NOT handled here: a checked
// world carries none, and one that slipped through is refused loudly by the
// conversion.
function runtime_ready_ty(ty: root.types.Ty) -> root.types.Ty throws never {
    match (ty) {
        let v: root.types.TyTypeVar if is_slotless_effect_param(v.param) => root.types.TyUnknown {},
        let l: root.types.TyLiteral => {
            root.types.TyLiteral { value: l.value, freshness: root.types.Freshness.Regular }
        },
        let c: root.types.TyClass => {
            root.types.TyClass { name: c.name, args: c.args.map(runtime_ready_ty) }
        },
        let i: root.types.TyInterface => {
            root.types.TyInterface {
                name: i.name,
                args: i.args.map(runtime_ready_ty),
                associated_types: i.associated_types.map((binding) -> {
                    root.types.AssociatedType {
                        name: binding.name,
                        ty: runtime_ready_ty(binding.ty),
                    }
                }),
            }
        },
        let l: root.types.TyList => root.types.TyList { elem: runtime_ready_ty(l.elem) },
        let m: root.types.TyMap => {
            root.types.TyMap { key: runtime_ready_ty(m.key), value: runtime_ready_ty(m.value) }
        },
        let u: root.types.TyUnion => root.types.TyUnion { members: u.members.map(runtime_ready_ty) },
        let t: root.types.TyTuple => root.types.TyTuple { items: t.items.map(runtime_ready_ty) },
        let f: root.types.TyFunction => {
            root.types.TyFunction {
                params: f.params.map((param) -> {
                    root.types.FunctionParamTy {
                        name: param.name,
                        ty: runtime_ready_ty(param.ty),
                        mode: param.mode,
                    }
                }),
                ret: runtime_ready_ty(f.ret),
                throws_: runtime_ready_ty(f.throws_),
            }
        },
        let f: root.types.TyFuture => {
            root.types.TyFuture {
                value: runtime_ready_ty(f.value),
                error: runtime_ready_ty(f.error),
            }
        },
        // The interface annotation carries component types (generics and
        // associated-type bindings); erase compiler-only types within them
        // too, matching the `Interface` arm above.
        let p: root.types.TyAssociatedTypeProjection => {
            root.types.TyAssociatedTypeProjection {
                base: runtime_ready_ty(p.base),
                interface_: root.types.map_tys(p.interface_, runtime_ready_ty),
                member: p.member,
            }
        },
        _ => ty,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_signature_runtime_ty @ d9be6853b
// Lower a method-signature type expression (a parameter or return type) to
// a runtime type, in the owner's declaration environment: `hir_ty`'s
// `owner_self_ty` and `owner_impl_target` resolve `Self` and, through it,
// each `Self.Assoc` projection.
function lower_signature_runtime_ty(
    ctx: LoweringContext,
    te: root.ast.TypeExpr,
    pkg_items: root.hir.PackageItems,
    ns_context: string[],
) -> root.types.RuntimeTy throws never {
    let generic_params = enclosing_generic_params(ctx);
    let generic_param_bounds = enclosing_generic_param_bounds(ctx);
    let func_loc = ctx.func_loc;
    let self_ty: root.types.Ty? = null;
    let impl_target: root.types.InterfaceConstraint? = null;
    if (func_loc != null) {
        self_ty = root.hir_ty.owner_self_ty(ctx.db, func_loc);
        impl_target = root.hir_ty.owner_impl_target(ctx.db, func_loc, generic_params);
    }
    let builder = root.hir.TypeRefBuilder.new();
    let id = builder.lower(te);
    let (let store, _) = builder.finish();
    let lower_ctx = root.hir_ty.lower_ctx_for_package(ctx.db, pkg_items, ns_context.concat([]))
        .with_frame(generic_params)
        .with_bounds(generic_param_bounds)
        .with_self_ty(self_ty)
        .with_impl_target(impl_target);
    let tir_ty = root.hir_ty.reject_holes(lower_ctx.lower_type_ref(store, id));
    convert_tir_ty_for_runtime(ctx, tir_ty)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::expr_ty @ d9be6853b
// The checker's type for an expression, as a runtime type. The checker types
// every expression of a body it accepts, so a missing entry is an internal
// inconsistency, never a type to stand in for.
function expr_ty(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.RuntimeTy throws MirInternalError {
    let ty = tir_expr_type(ctx, expr_id);
    if (ty == null) {
        throw internal_error(ctx, "no type recorded for expression", expr_id);
    }
    convert_tir_ty_for_runtime(ctx, ty)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_type_arg_templates @ d9be6853b
// The `TyTemplate` slice for the class-level type args of a class
// construction expression; empty for non-generic (or unresolved) classes.
function class_type_arg_templates(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.TyTemplate[] throws never {
    let generic_params = enclosing_generic_params(ctx);
    match (tir_expr_type(ctx, expr_id)) {
        let c: root.types.TyClass if c.args.length() > 0 => {
            c.args.map((arg) -> {
                ty_to_template(ctx, arg, generic_params)
            })
        },
        _ => [],
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::array_element_template @ d9be6853b
// The element-type template for an array-literal expression (the `T` of its
// `T[]` static type), for `RvalueArray`. A generic element maps to a
// `TypeArgRef`. The checker types every array literal as a list.
function array_element_template(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.TyTemplate throws MirInternalError {
    let generic_params = enclosing_generic_params(ctx);
    match (tir_expr_type(ctx, expr_id)) {
        let l: root.types.TyList => ty_to_template(ctx, l.elem, generic_params),
        _ => {
            throw internal_error(ctx, "the checker typed an array literal as no list", expr_id);
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tuple_element_templates @ d9be6853b
function tuple_element_templates(
    ctx: LoweringContext,
    expr_id: int,
    arity: int,
) -> root.types.TyTemplate[] throws MirInternalError {
    let generic_params = enclosing_generic_params(ctx);
    match (tir_expr_type(ctx, expr_id)) {
        let t: root.types.TyTuple if t.items.length() == arity => {
            t.items.map((slot) -> {
                ty_to_template(ctx, slot, generic_params)
            })
        },
        _ => {
            throw internal_error(ctx, "the checker typed a tuple literal as no tuple of its arity", expr_id);
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::map_kv_templates @ d9be6853b
// The key/value type templates for a map-literal expression (the `K`/`V` of
// its `map<K, V>` static type), for `RvalueMap`.
function map_kv_templates(
    ctx: LoweringContext,
    expr_id: int,
) -> (root.types.TyTemplate, root.types.TyTemplate) throws MirInternalError {
    let generic_params = enclosing_generic_params(ctx);
    match (tir_expr_type(ctx, expr_id)) {
        let m: root.types.TyMap => {
            (
                ty_to_template(ctx, m.key, generic_params),
                ty_to_template(ctx, m.value, generic_params),
            )
        },
        _ => {
            throw internal_error(ctx, "the checker typed a map literal as no map", expr_id);
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::object_class_type_arg_templates @ d9be6853b
// The type-argument templates of an object literal: its written type args
// as TIR resolved them (the call plan keyed at the expression), or, for
// `Box { .. }`, the class type TIR inferred for it. Never re-lowered from
// syntax.
function object_class_type_arg_templates(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.TyTemplate[] throws never {
    let plan = tir_call_plan(ctx, expr_id);
    if (plan != null && plan.slots.length() > 0) {
        let generic_params = enclosing_generic_params(ctx);
        return plan.slots.map((slot) -> {
            ty_to_template(ctx, slot.emission_ty, generic_params)
        });
    }
    class_type_arg_templates(ctx, expr_id)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pat_ty @ d9be6853b
// The checker's type for a pattern binding, as a runtime type. Like
// `expr_ty`, a missing entry is an internal inconsistency.
function pat_ty(ctx: LoweringContext, pat_id: int) -> root.types.RuntimeTy throws MirInternalError {
    let ty = tir_pat_type(ctx, pat_id);
    if (ty == null) {
        throw MirInternalError {
            message: "no type recorded for pattern",
            span: span_for_pat(ctx, pat_id) ?? ctx.builder.current_source_span,
        };
    }
    convert_tir_ty_for_runtime(ctx, ty)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_root_ty @ d9be6853b
// The TIR-inferred root segment type for a multi-segment Path expression;
// null if no root type was recorded (e.g. single-segment paths).
function path_root_ty(ctx: LoweringContext, expr_id: int) -> root.types.RuntimeTy? throws never {
    let ty = tir_path_root_type(ctx, expr_id)
        ?? return null;
    convert_tir_ty_for_runtime(ctx, ty)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::top_level_let_at @ d9be6853b
// The top-level `let` this path expression's root names, if any: a global
// variable, a `client` declaration, or a Session submission's persisted root
// binding. The checker records every such root, qualified (lowered here as
// the bare `x` it names) or bare.
function top_level_let_at(ctx: LoweringContext, expr_id: int) -> int? throws never {
    tir_global_root(ctx, expr_id)?.binding
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_root_is_top_level_let @ d9be6853b
// Whether a path expression's root names a top-level `let`: whether it
// denotes a runtime value even though it is not a lexical binding.
function path_root_is_top_level_let(ctx: LoweringContext, expr_id: int) -> bool throws never {
    top_level_let_at(ctx, expr_id) != null
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::load_top_level_let_root @ d9be6853b
// Materialize a top-level `let`'s current value into a temp, when the path
// root resolves to one. The temp takes TIR's recorded root type when there
// is one, else `unknown`. A materialized copy is handed out rather than the
// global-read local: emit virtualizes a `Use(Constant::GlobalItem)` temp,
// and `RvalueLen` takes a `Place`, which a virtualized place does not
// survive.
function load_top_level_let_root(ctx: LoweringContext, expr_id: int) -> int? throws never {
    let global = top_level_let_at(ctx, expr_id)
        ?? return null;
    let root_ty: root.types.RuntimeTy = path_root_ty(ctx, expr_id) ?? root.types.TyUnknown {};
    let root_local = ctx.builder.declare_local(root_ty);
    ctx.builder.assign(
        PlaceLocal { value: root_local },
        RvalueUse { value: OperandConstant { value: ConstantGlobalItem { value: global } } },
    );
    let materialized = ctx.builder.declare_local(root_ty);
    ctx.builder.assign(
        PlaceLocal { value: materialized },
        RvalueUse { value: operand_copy_local(root_local) },
    );
    materialized
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_segment_ty @ d9be6853b
// The TIR-inferred type of `segments[..=seg_idx]` for a multi-segment
// local-rooted Path expression; null if not recorded.
function path_segment_ty(
    ctx: LoweringContext,
    expr_id: int,
    seg_idx: int,
) -> root.types.RuntimeTy? throws never {
    let ty = tir_path_segment_type(ctx, expr_id, seg_idx)
        ?? return null;
    convert_tir_ty_for_runtime(ctx, ty)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_type_annotation @ d9be6853b
// Resolve a `TypeExpr` annotation directly to a `RuntimeTy`, with the
// enclosing function's generic params in scope so a type variable in the
// annotation (`let item: T => ..`) resolves faithfully to a `TypeVar`.
function resolve_type_annotation(
    ctx: LoweringContext,
    ty_expr: root.ast.TypeExpr,
) -> root.types.RuntimeTy throws never {
    runtime(ctx).convert(lower_type_annotation_tir(ctx, ty_expr))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_type_annotation_tir @ d9be6853b
// Lower a pattern's type annotation to TIR with the enclosing function's
// generic params in scope, so `TypeVar`s survive and a typed pattern test
// lowers to a `TypeArgRef` template.
function lower_type_annotation_tir(
    ctx: LoweringContext,
    ty_expr: root.ast.TypeExpr,
) -> root.types.Ty throws never {
    let generic_params = enclosing_generic_params(ctx);
    let generic_param_bounds = enclosing_generic_param_bounds(ctx);
    let pkg_info = root.hir.file_package(ctx.db, ctx.file);
    let pkg_items = root.hir.package_items(ctx.db, pkg_info.root_id);
    lower_expr_in_scope(
        ctx.db,
        ty_expr,
        pkg_items,
        pkg_info.namespace_path,
        generic_params,
        generic_param_bounds,
        body_self_tir_ty(ctx),
    )
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::span_for_expr @ d9be6853b
// A `Span` from an expression's source range; null without a source map
// (e.g. synthesized bodies).
function span_for_expr(ctx: LoweringContext, expr_id: int) -> root.base.Span? throws never {
    let sm = ctx.source_map
        ?? return null;
    root.base.Span { file_id: ctx.db.file(ctx.file).id, range: sm.expr_span(expr_id) }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::span_for_pat @ d9be6853b
// A `Span` from a pattern's source range.
function span_for_pat(ctx: LoweringContext, pat_id: int) -> root.base.Span? throws never {
    let sm = ctx.source_map
        ?? return null;
    root.base.Span { file_id: ctx.db.file(ctx.file).id, range: sm.pattern_span(pat_id) }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::span_for_stmt @ d9be6853b
// A `Span` from a statement's source range.
function span_for_stmt(ctx: LoweringContext, stmt_id: int) -> root.base.Span? throws never {
    let sm = ctx.source_map
        ?? return null;
    root.base.Span { file_id: ctx.db.file(ctx.file).id, range: sm.stmt_span(stmt_id) }
}
