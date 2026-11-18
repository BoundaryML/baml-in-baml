// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// Unit 1 of the MIR plan, part one: lower.rs's free helpers ahead of
// `LoweringContext` (lines 105-1681 at the plan's numbering): the package
// alias environment, the type-lowering roads into `hir_ty`, `RuntimeLowering`
// and template lowering, the coarse-tag sufficiency proofs, the display
// names, `native_key_for`, and the interface-member types. The
// `LoweringContext` methods of unit 1 are in `lower_u1_ctx.baml`, the entry
// points in `lower_u1_entry.baml`.
//
// Restructured (BAML forces it), as in lower.baml:
// - Rust's `Option<Vec<_>>` collections (`.collect::<Option<Vec<_>>>()?`)
//   are loops that return null early (`lower_tir_templates`,
//   `lower_tir_template_bindings`, `pattern_templates_of`).
// - Every `DeclRef` (`ClassRef`, `EnumRef`, `FunctionRef`, `GlobalRef`) is
//   its Source lane, an `int` loc: no root is served from an interface here
//   (`root.hir.is_served_from_interface`), so the `External` arms of the
//   display names have nothing to name.
// - `Viewpoint::display_label` (the `Name` of `display_package`) is
//   `display_package`.
// - `lower_ref_in_scope_at` is `lower_ref_in_scope` with the position a
//   named default (Rust's `lower_ref_in_scope` only forwards to it at
//   `Existential`). `qualify_def` (a forward to `hir_ty`'s) is not ported:
//   call `root.hir_ty.qualify_def`.
// - Items of other crates MIR needs that are not ported yet are stubs:
//   `root.types.resolved_aliases_convert` (`ResolvedAliases::convert`),
//   `root.types.erase_typevars_matching`,
//   `root.types.ty_template_substitute_symbolic`,
//   `root.types.native_key_spelling` (baml_base's) in
//   `ns_types/template_stubs_u1.baml`; layout's `class_field_index`,
//   `class_field_ty`, `enum_variants`, `enum_variant_index`, `lang_class`
//   in `ns_hir_ty/layout_stubs_u1.baml`.

// port: baml_compiler2_mir/src/lower.rs::PackageAliases @ d9be6853b
// A package's memoized alias environment (`resolved_aliases_for_package`).
// Rust's `Deref` to the `ResolvedAliases` is the field `value`.
class PackageAliases {
    value: root.types.ResolvedAliases,
}

// port: baml_compiler2_mir/src/lower.rs::resolved_aliases_for_package @ d9be6853b
// Build the `ResolvedAliases` type-alias environment for a package: every
// alias visible to it (its own plus its dependency closure's), whichever lane
// each package is served from: `hir_ty`'s one alias environment
// (`interfaces::package_resolved_aliases`). An alias this environment is
// missing survives as a name nothing declares, which the runtime conversion
// rejects. Rust clones `hir_ty`'s map into the environment; neither side
// mutates it, so it is shared.
function resolved_aliases_for_package(db: root.hir.Db, pkg_id: int) -> PackageAliases throws never {
    db.mir_memo.resolved_aliases_for_package.get(db.cycles, pkg_id, () -> {
        PackageAliases {
            value: root.types.ResolvedAliases.from_aliases(
                root.hir_ty.interfaces.package_resolved_aliases(db, pkg_id),
            ),
        }
    })
}

// port: baml_compiler2_mir/src/lower.rs::lower_ty_with_bindings @ d9be6853b
// Lower a type expression, treating the `bindings` map's keys as the
// in-scope type variables, then substitute those bindings. Threads the
// in-scope typevar `bounds` so a `T.member` projection resolves through
// `T`'s bound rather than erasing to `unknown`. The AST node lowers through
// hir's firewall into a scratch store, then through `hir_ty`'s one
// type-lowering road.
function lower_ty_with_bindings(
    db: root.hir.Db,
    expr: root.ast.TypeExpr,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    bindings: map<root.types.ParamTy, root.types.Ty>,
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
) -> root.types.Ty throws never {
    let builder = root.hir.TypeRefBuilder.new();
    let id = builder.lower(expr);
    let (let store, _) = builder.finish();
    lower_ref_with_bindings(db, store, id, pkg_items, namespace_path, bindings, bounds)
}

// port: baml_compiler2_mir/src/lower.rs::lower_ref_with_bindings @ d9be6853b
// The `TypeRef`-arena twin of `lower_ty_with_bindings`, for callers holding
// firewall data (`*_data(..).type_refs` + a `TypeRefId`) rather than an AST
// node. The frame is the bindings' keys, in the map's order (Rust's
// `FxHashMap` order; the frame is looked up by identity, not position).
function lower_ref_with_bindings(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    id: int,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    bindings: map<root.types.ParamTy, root.types.Ty>,
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
) -> root.types.Ty throws never {
    let generic_params = bindings.keys();
    let ctx = root.hir_ty.lower_ctx_for_package(db, pkg_items, namespace_path.concat([]))
        .with_frame(generic_params)
        .with_bounds(root.hir_ty.interfaces.copy_bounds(bounds));
    let lowered = root.hir_ty.reject_holes(ctx.lower_type_ref(store, id));
    root.types.substitute_ty(lowered, bindings)
}

// port: baml_compiler2_mir/src/lower.rs::lower_ref_in_scope_at @ d9be6853b
// Also `lower_ref_in_scope` (the `Existential` default). The in-scope twin
// of the binding wrappers above: explicit frame, no substitution: the same
// `hir_ty` road for sites that keep their type variables rigid (turbofish
// args, annotations, dispatch targets). `implements` / dispatch targets pass
// `ConstraintHead` (written pins only, no existential completeness demands).
function lower_ref_in_scope(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    id: int,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    generic_params: root.types.ParamTy[],
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    self_ty: root.types.Ty?,
    position: root.hir_ty.TypePosition = root.hir_ty.TypePosition.Existential,
) -> root.types.Ty throws never {
    let ctx = root.hir_ty.lower_ctx_for_package(db, pkg_items, namespace_path.concat([]))
        .with_frame(generic_params.concat([]))
        .with_bounds(root.hir_ty.interfaces.copy_bounds(bounds))
        .with_self_ty(self_ty);
    root.hir_ty.reject_holes(ctx.lower_type_ref(store, id, position = position))
}

// port: baml_compiler2_mir/src/lower.rs::lower_expr_in_scope @ d9be6853b
// The AST twin of `lower_ref_in_scope` (scratch firewall store).
function lower_expr_in_scope(
    db: root.hir.Db,
    expr: root.ast.TypeExpr,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    generic_params: root.types.ParamTy[],
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    self_ty: root.types.Ty?,
) -> root.types.Ty throws never {
    let builder = root.hir.TypeRefBuilder.new();
    let id = builder.lower(expr);
    let (let store, _) = builder.finish();
    lower_ref_in_scope(db, store, id, pkg_items, namespace_path, generic_params, bounds, self_ty)
}

// port: baml_compiler2_mir/src/lower.rs::widen_literal_bases @ d9be6853b
// Literals widened to their bases REGARDLESS of freshness: impl dispatch is
// by base type (`hir_ty`'s operand-dispatch discipline; a `"x"`-typed
// receiver IS a string at runtime).
function widen_literal_bases(ty: root.types.Ty) -> root.types.Ty throws never {
    match (ty) {
        let l: root.types.TyLiteral => {
            root.types.from_primitive(root.types.primitive_type_from_literal(l.value))
        },
        let u: root.types.TyUnion => {
            root.types.TyUnion { members: u.members.map(widen_literal_bases) }
        },
        let l: root.types.TyList => root.types.TyList { elem: widen_literal_bases(l.elem) },
        _ => ty,
    }
}

// port: baml_compiler2_mir/src/lower.rs::PrimitiveRendering @ d9be6853b
// How `string.from` renders a value of a primitive type, which no package
// can change (E0139): a string as itself; an `int`, `float`, `bool` or
// `null` through `baml._to_string_primitive`.
enum PrimitiveRendering {
    Itself,
    Formatted,
}

// port: baml_compiler2_mir/src/lower.rs::primitive_rendering @ d9be6853b
// The `PrimitiveRendering` of every value of checked type `ty`, or null when
// `ty` admits a value that is not a primitive, or a union mixes the two
// renderings.
function primitive_rendering(ty: root.types.Ty) -> PrimitiveRendering? throws never {
    match (ty) {
        root.types.TyString => PrimitiveRendering.Itself,
        let l: root.types.TyLiteral => {
            match (l.value) {
                root.base.LiteralString => PrimitiveRendering.Itself,
                root.base.LiteralInt | root.base.LiteralFloat | root.base.LiteralBool => {
                    PrimitiveRendering.Formatted
                },
                root.base.LiteralBigint => null,
            }
        },
        root.types.TyInt | root.types.TyFloat | root.types.TyBool | root.types.TyNull => {
            PrimitiveRendering.Formatted
        },
        let u: root.types.TyUnion => {
            let first = u.members.at(0)
                ?? return null;
            let rendering = primitive_rendering(first)
                ?? return null;
            let rest = u.members.slice(1, u.members.length());
            if (
                rest.every((member) -> {
                    primitive_rendering(member) == rendering
                })
            ) {
                rendering
            } else {
                null
            }
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::resolve_ref_to_interface_loc @ d9be6853b
// Resolve a written interface reference to its declaration: the `hir_ty`
// lowering road (written pins only) plus the facts definition lookup.
function resolve_ref_to_interface_loc(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    target: int,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
) -> int? throws never {
    let lowered = lower_ref_in_scope(
        db,
        store,
        target,
        pkg_items,
        namespace_path,
        [],
        {},
        null,
        position = root.hir_ty.TypePosition.ConstraintHead,
    );
    let interface_ = match (lowered) {
        let i: root.types.TyInterface => i,
        _ => {
            return null;
        },
    };
    match (root.hir_ty.definition_of(db, interface_.name)) {
        let def: root.hir.DefinitionInterface => def.value,
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::plain_interface_ty @ d9be6853b
// An interned interface bound as the plain interface TYPE: the dispatch view
// MIR's per-param bound map holds. Rust's `Interface::to_ty`, written out.
function plain_interface_ty(bound: root.types.InterfaceConstraint) -> root.types.Ty throws never {
    root.types.TyInterface {
        name: bound.name,
        args: bound.generics,
        associated_types: bound.associated_types,
    }
}

// port: baml_compiler2_mir/src/lower.rs::tir_contains_projection @ d9be6853b
// Whether `ty` contains an associated-type projection node at any depth.
// The companion of `contains_typevar` for the other symbolic node kind: a
// projection whose base is already concrete slips past `contains_typevar`.
function tir_contains_projection(ty: root.types.Ty) -> bool throws never {
    match (ty) {
        root.types.TyAssociatedTypeProjection => true,
        let l: root.types.TyList => tir_contains_projection(l.elem),
        let m: root.types.TyMap => {
            tir_contains_projection(m.key) || tir_contains_projection(m.value)
        },
        let u: root.types.TyUnion => u.members.some(tir_contains_projection),
        let t: root.types.TyTuple => t.items.some(tir_contains_projection),
        let c: root.types.TyClass => c.args.some(tir_contains_projection),
        let i: root.types.TyInterface => {
            i.args.some(tir_contains_projection)
                || i.associated_types.some((binding) -> {
                    tir_contains_projection(binding.ty)
                })
        },
        let f: root.types.TyFuture => {
            tir_contains_projection(f.value) || tir_contains_projection(f.error)
        },
        let f: root.types.TyFunction => {
            f.params.some((param) -> {
                tir_contains_projection(param.ty)
            })
                || tir_contains_projection(f.ret)
                || tir_contains_projection(f.throws_)
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::tir_contains_symbolic @ d9be6853b
// Whether `ty` contains any symbolic node: a type variable or an
// associated-type projection: that has no realized runtime form and must be
// lowered through the structured template arms. Rust's
// `baml_type_runtime::contains_typevar` is the `contains_ty_where` walk.
function tir_contains_symbolic(ty: root.types.Ty) -> bool throws never {
    root.types.contains_ty_where(ty, (node) -> {
        node is root.types.TyTypeVar
    })
        || tir_contains_projection(ty)
}

// port: baml_compiler2_mir/src/lower.rs::TemplateMode @ d9be6853b
enum TemplateMode {
    Value,
    Pattern,
}

// port: baml_compiler2_mir/src/lower.rs::lower_tir_template @ d9be6853b
// Restructured: the `Option<Vec<_>>` collections are `lower_tir_templates`
// and `lower_tir_template_bindings`; the arms with more than a line are
// `lower_tir_template_projection`, `_class`, `_interface` and `_function`.
function lower_tir_template(
    ty: root.types.Ty,
    resolved: RuntimeLowering,
    generic_layout: root.types.RuntimeGenericLayout,
    mode: TemplateMode,
) -> root.types.TyTemplate? throws never {
    match (ty) {
        // An associated type is never a frame slot: `Self.X` stays a
        // structured projection over the `Self` slot and reduces through the
        // resolver at use.
        let p: root.types.TyAssociatedTypeProjection => {
            lower_tir_template_projection(p, resolved, generic_layout, mode)
        },
        let v: root.types.TyTypeVar => {
            let index = generic_layout.slot(v.param);
            if (index != null) {
                root.types.TyTypeArgRef { index: index }
            } else if (mode == TemplateMode.Value) {
                baml.sys.panic(`type variable not found in type args: ${v.param.name}`)
            } else {
                null
            }
        },
        let l: root.types.TyList => {
            root.types.TyTemplateList {
                elem: lower_tir_template(l.elem, resolved, generic_layout, mode)
                    ?? return null,
            }
        },
        let m: root.types.TyMap => {
            let key = lower_tir_template(m.key, resolved, generic_layout, mode)
                ?? return null;
            let value = lower_tir_template(m.value, resolved, generic_layout, mode)
                ?? return null;
            root.types.TyTemplateMap { key: key, value: value }
        },
        let u: root.types.TyUnion => {
            root.types.TyTemplateUnion {
                members: lower_tir_templates(u.members, resolved, generic_layout, mode)
                    ?? return null,
            }
        },
        let t: root.types.TyTuple => {
            root.types.TyTemplateTuple {
                items: lower_tir_templates(t.items, resolved, generic_layout, mode)
                    ?? return null,
            }
        },
        let c: root.types.TyClass => lower_tir_template_class(c, resolved, generic_layout, mode),
        let i: root.types.TyInterface => {
            lower_tir_template_interface(i, resolved, generic_layout, mode)
        },
        let f: root.types.TyFunction => lower_tir_template_function(f, resolved, generic_layout),
        let f: root.types.TyFuture => {
            let value = lower_tir_template(f.value, resolved, generic_layout, TemplateMode.Value)
                ?? return null;
            let error = lower_tir_template(f.error, resolved, generic_layout, TemplateMode.Value)
                ?? return null;
            root.types.TyTemplateFuture { value: value, error: error }
        },
        _ => realized_leaf_template(resolved.convert(ty)),
    }
}

// Rust's `tys.iter().map(|ty| lower_tir_template(..)).collect::<Option<Vec<_>>>()`.
function lower_tir_templates(
    tys: root.types.Ty[],
    resolved: RuntimeLowering,
    generic_layout: root.types.RuntimeGenericLayout,
    mode: TemplateMode,
) -> root.types.TyTemplate[]? throws never {
    let out: root.types.TyTemplate[] = [];
    for (let ty in tys) {
        out.push(
            lower_tir_template(ty, resolved, generic_layout, mode)
                ?? return null,
        );
    }
    out
}

// The associated-type bindings of an interface, each lowered; null when one
// fails. Rust's `collect::<Option<Vec<_>>>()` over `(name, ty)` pairs.
function lower_tir_template_bindings(
    bindings: root.types.AssociatedType[],
    resolved: RuntimeLowering,
    generic_layout: root.types.RuntimeGenericLayout,
    mode: TemplateMode,
) -> root.types.TyTemplateAssociatedType[]? throws never {
    let out: root.types.TyTemplateAssociatedType[] = [];
    for (let binding in bindings) {
        out.push(
            root.types.TyTemplateAssociatedType {
                name: binding.name,
                ty: lower_tir_template(binding.ty, resolved, generic_layout, mode)
                    ?? return null,
            },
        );
    }
    out
}

// The `AssociatedTypeProjection` arm of `lower_tir_template`. Always a
// projection template, never a frame slot: associated types are not frame
// slots, so a `Self.X` here has no slot to reference.
function lower_tir_template_projection(
    p: root.types.TyAssociatedTypeProjection,
    resolved: RuntimeLowering,
    generic_layout: root.types.RuntimeGenericLayout,
    mode: TemplateMode,
) -> root.types.TyTemplate? throws never {
    let base = lower_tir_template(p.base, resolved, generic_layout, mode)
        ?? return null;
    let generics = lower_tir_templates(p.interface_.generics, resolved, generic_layout, mode)
        ?? return null;
    let associated_types = lower_tir_template_bindings(p.interface_.associated_types, resolved, generic_layout, mode)
        ?? return null;
    root.types.TyTemplateAssociatedTypeProjection {
        base: base,
        interface_: root.types.TyTemplateInterfaceConstraint {
            name: p.interface_.name,
            generics: generics,
            associated_types: associated_types,
        },
        member: p.member,
    }
}

// The `Class` arm of `lower_tir_template`: structural when matching a
// pattern or when an argument is symbolic, else a realized leaf.
function lower_tir_template_class(
    c: root.types.TyClass,
    resolved: RuntimeLowering,
    generic_layout: root.types.RuntimeGenericLayout,
    mode: TemplateMode,
) -> root.types.TyTemplate? throws never {
    if (mode == TemplateMode.Pattern || c.args.some(tir_contains_symbolic)) {
        root.types.TyTemplateClass {
            name: c.name,
            args: lower_tir_templates(c.args, resolved, generic_layout, mode)
                ?? return null,
        }
    } else {
        let resolved_args = c.args.map((ty) -> {
            resolved.convert(ty)
        });
        realized_leaf_template(root.types.RuntimeTyClass { name: c.name, args: resolved_args })
    }
}

// The `Interface` arm of `lower_tir_template`: structural when matching a
// pattern or when an argument or binding is symbolic, else a realized leaf.
function lower_tir_template_interface(
    i: root.types.TyInterface,
    resolved: RuntimeLowering,
    generic_layout: root.types.RuntimeGenericLayout,
    mode: TemplateMode,
) -> root.types.TyTemplate? throws never {
    let symbolic = mode == TemplateMode.Pattern
        || i.args.some(tir_contains_symbolic)
        || i.associated_types.some((binding) -> {
            tir_contains_symbolic(binding.ty)
        });
    if (symbolic) {
        let args = lower_tir_templates(i.args, resolved, generic_layout, mode)
            ?? return null;
        let bindings = lower_tir_template_bindings(i.associated_types, resolved, generic_layout, mode)
            ?? return null;
        root.types.TyTemplateInterface { name: i.name, args: args, associated_types: bindings }
    } else {
        let resolved_args = i.args.map((ty) -> {
            resolved.convert(ty)
        });
        let resolved_bindings = i.associated_types.map((binding) -> {
            root.types.RuntimeAssociatedType {
                name: binding.name,
                ty: resolved.convert(binding.ty),
            }
        });
        realized_leaf_template(
            root.types.RuntimeTyInterface {
                name: i.name,
                args: resolved_args,
                associated_types: resolved_bindings,
            },
        )
    }
}

// The `Function` arm of `lower_tir_template`: a function type lowers in
// value mode throughout, whatever the caller's mode.
function lower_tir_template_function(
    f: root.types.TyFunction,
    resolved: RuntimeLowering,
    generic_layout: root.types.RuntimeGenericLayout,
) -> root.types.TyTemplate? throws never {
    let mode = TemplateMode.Value;
    let params: root.types.TyTemplateFunctionParamTy[] = [];
    for (let param in f.params) {
        params.push(
            root.types.TyTemplateFunctionParamTy {
                name: param.name,
                ty: lower_tir_template(param.ty, resolved, generic_layout, mode)
                    ?? return null,
                mode: param.mode,
            },
        );
    }
    let ret = lower_tir_template(f.ret, resolved, generic_layout, mode)
        ?? return null;
    let throws_ = lower_tir_template(f.throws_, resolved, generic_layout, mode)
        ?? return null;
    root.types.TyTemplateFunction { params: params, ret: ret, throws_: throws_ }
}

// port: baml_compiler2_mir/src/lower.rs::RuntimeLowering @ d9be6853b
// The checker to MIR crossing for one package: alias expansion, with every
// head kept as the declaration's identity. It also renders a head
// canonically (`wire`) for the places that SHOW one (operand metadata, a
// dump, a message) and for nothing else.
class RuntimeLowering {
    aliases: root.types.ResolvedAliases,
    db: root.hir.Db,

    // port: baml_compiler2_mir/src/lower.rs::RuntimeLowering::of @ d9be6853b
    // The crossing for `root_id`'s declarations: its memoized alias
    // environment.
    function of(db: root.hir.Db, root_id: int) -> RuntimeLowering throws never {
        RuntimeLowering { aliases: resolved_aliases_for_package(db, root_id).value, db: db }
    }

    // port: baml_compiler2_mir/src/lower.rs::RuntimeLowering::convert @ d9be6853b
    // A compile-time type as MIR carries it: aliases expanded, every head
    // still the declaration's identity. Kept as Rust's method (the crossing's
    // one conversion) over `ResolvedAliases::convert`, which is a stub here.
    function convert(self, ty: root.types.Ty) -> root.types.RuntimeTy throws never {
        root.types.resolved_aliases_convert(self.aliases, ty)
    }

    // port: baml_compiler2_mir/src/lower.rs::RuntimeLowering::wire @ d9be6853b
    // A compile-time head rendered canonically, packed into a wire name for
    // printers that take one (`Viewpoint::wire_head`): what operand metadata
    // and a dump say. Never an identity.
    function wire(self, decl: root.types.DeclName) -> root.types.TypeName throws never {
        root.hir_ty.Viewpoint.canonical(self.db).wire_head(decl)
    }
}

// port: baml_compiler2_mir/src/lower.rs::is_slotless_effect_param @ d9be6853b
// Whether `param` is a synthetic effect parameter, which has no frame slot
// by ABI and is erased wherever a template needs a slot. A block-scoped
// `type __effect_param_0 = ..` (a user binding that always has a slot) is
// excluded by its identity, not its spelling.
function is_slotless_effect_param(param: root.types.ParamTy) -> bool throws never {
    !param.is_scoped() && root.types.is_synthetic_effect_param(param.name)
}

// port: baml_compiler2_mir/src/lower.rs::tir2_to_template @ d9be6853b
// Convert a `Tir2Ty` to `TyTemplate`, mapping each type variable to its
// canonical runtime frame index.
function tir2_to_template(
    ty: root.types.Ty,
    resolved: RuntimeLowering,
    generic_params: root.types.ParamTy[],
) -> root.types.TyTemplate throws never {
    let erased = root.types.erase_typevars_matching(ty, is_slotless_effect_param);
    let generic_layout = root.types.RuntimeGenericLayout.new(generic_params);
    lower_tir_template(erased, resolved, generic_layout, TemplateMode.Value)
        ?? baml.sys.panic("value template lowering is infallible")
}

// port: baml_compiler2_mir/src/lower.rs::tir2_interface_to_template @ d9be6853b
// Lower a realized interface constraint to its template form: each generic
// argument and associated binding lowered individually, so an argument that
// is an enclosing generic becomes a `TypeArgRef`. Deliberately not
// `tir2_to_template` over a `Ty::Interface`: a dispatch site names the
// interface it resolves through, a constraint, with a single shape.
function tir2_interface_to_template(
    name: root.types.DeclName,
    args: root.types.Ty[],
    assoc: (string, root.types.Ty)[],
    resolved: RuntimeLowering,
    generic_params: root.types.ParamTy[],
) -> root.types.TyTemplateInterfaceConstraint throws never {
    root.types.TyTemplateInterfaceConstraint {
        name: name,
        generics: args.map((arg) -> {
            tir2_to_template(arg, resolved, generic_params)
        }),
        associated_types: assoc.map((binding) -> {
            root.types.TyTemplateAssociatedType {
                name: binding.0,
                ty: tir2_to_template(binding.1, resolved, generic_params),
            }
        }),
    }
}

// port: baml_compiler2_mir/src/lower.rs::realized_leaf_template @ d9be6853b
// A resolved `RuntimeTy` with no residual type variables, as a leaf
// template: it narrows to a `RealizedTy` (proving realizedness) and widens
// into a `TyTemplate`. Panics if the type still contains a type variable:
// callers guarantee realizedness (the `tir_contains_symbolic` gate).
function realized_leaf_template(ty: root.types.RuntimeTy) -> root.types.TyTemplate throws never {
    let realized = root.types.narrow_runtime_ty_to_realized_ty(ty) catch (e) {
        root.types.NarrowError => {
            baml.sys.panic(
                `realized-leaf template must be realized: \`${e.variant}\` is not a valid \`RealizedTy\``,
            )
        },
    };
    root.types.widen_realized_ty_to_ty_template(realized)
}

// port: baml_compiler2_mir/src/lower.rs::runtime_ty_is_int_only @ d9be6853b
// Whether every value of `ty` is a raw `int`: the precondition an integer
// `Switch` reads its discriminant under. Int literals count; a `bigint` or
// `float` does not.
function runtime_ty_is_int_only(ty: root.types.RuntimeTy) -> bool throws never {
    match (ty) {
        root.types.TyInt => true,
        let l: root.types.TyLiteral => l.value is root.base.LiteralInt,
        let u: root.types.RuntimeTyUnion => u.members.every(runtime_ty_is_int_only),
        _ => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::runtime_ty_is_enum_only @ d9be6853b
// Whether every value admitted by `ty` has an enum discriminant belonging to
// `enum_name`. Nullable and mixed-enum scrutinees must use the comparison
// chain so non-matching values can reach a wildcard arm.
function runtime_ty_is_enum_only(
    ty: root.types.RuntimeTy,
    enum_name: root.types.DeclName,
) -> bool throws never {
    match (ty) {
        let e: root.types.TyEnum => e.name == enum_name,
        let v: root.types.TyEnumVariant => v.name == enum_name,
        let u: root.types.RuntimeTyUnion => {
            u.members.every((member) -> {
                runtime_ty_is_enum_only(member, enum_name)
            })
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::tir2_to_pattern_template @ d9be6853b
// Convert a TIR pattern type into a complete `TyTemplate`, failing closed
// when a type variable has no runtime frame slot.
function tir2_to_pattern_template(
    ty: root.types.Ty,
    resolved: RuntimeLowering,
    generic_params: root.types.ParamTy[],
) -> root.types.TyTemplate? throws never {
    let generic_layout = root.types.RuntimeGenericLayout.new(generic_params);
    lower_tir_template(ty, resolved, generic_layout, TemplateMode.Pattern)
}

// port: baml_compiler2_mir/src/lower.rs::ty_to_pattern_template_from_resolved_ty @ d9be6853b
// Convert an already-resolved `RuntimeTy` into a complete `TyTemplate`, or
// null when any position is unresolvable: a residual type variable or
// projection (this conversion has no frame context). A realized type becomes
// a leaf; a composite decomposes structurally.
function ty_to_pattern_template_from_resolved_ty(
    ty: root.types.RuntimeTy,
) -> root.types.TyTemplate? throws never {
    match (ty) {
        root.types.TyTypeVar | root.types.RuntimeTyAssociatedTypeProjection => null,
        let l: root.types.RuntimeTyList => {
            root.types.TyTemplateList {
                elem: ty_to_pattern_template_from_resolved_ty(l.elem)
                    ?? return null,
            }
        },
        let m: root.types.RuntimeTyMap => {
            let key = ty_to_pattern_template_from_resolved_ty(m.key)
                ?? return null;
            let value = ty_to_pattern_template_from_resolved_ty(m.value)
                ?? return null;
            root.types.TyTemplateMap { key: key, value: value }
        },
        let u: root.types.RuntimeTyUnion => {
            root.types.TyTemplateUnion {
                members: pattern_templates_of(u.members)
                    ?? return null,
            }
        },
        let t: root.types.RuntimeTyTuple => {
            root.types.TyTemplateTuple {
                items: pattern_templates_of(t.items)
                    ?? return null,
            }
        },
        let c: root.types.RuntimeTyClass if c.args.length() > 0 => {
            root.types.TyTemplateClass {
                name: c.name,
                args: pattern_templates_of(c.args)
                    ?? return null,
            }
        },
        // Interfaces decompose so the membership test keeps its
        // instantiation (args + associated bindings).
        let i: root.types.RuntimeTyInterface => {
            let args = pattern_templates_of(i.args)
                ?? return null;
            let bindings: root.types.TyTemplateAssociatedType[] = [];
            for (let binding in i.associated_types) {
                bindings.push(
                    root.types.TyTemplateAssociatedType {
                        name: binding.name,
                        ty: ty_to_pattern_template_from_resolved_ty(binding.ty)
                            ?? return null,
                    },
                );
            }
            root.types.TyTemplateInterface { name: i.name, args: args, associated_types: bindings }
        },
        let f: root.types.RuntimeTyFunction => {
            let params: root.types.TyTemplateFunctionParamTy[] = [];
            for (let param in f.params) {
                params.push(
                    root.types.TyTemplateFunctionParamTy {
                        name: param.name,
                        ty: ty_to_pattern_template_from_resolved_ty(param.ty)
                            ?? return null,
                        mode: param.mode,
                    },
                );
            }
            let ret = ty_to_pattern_template_from_resolved_ty(f.ret)
                ?? return null;
            let throws_ = ty_to_pattern_template_from_resolved_ty(f.throws_)
                ?? return null;
            root.types.TyTemplateFunction { params: params, ret: ret, throws_: throws_ }
        },
        let f: root.types.RuntimeTyFuture => {
            let value = ty_to_pattern_template_from_resolved_ty(f.value)
                ?? return null;
            let error = ty_to_pattern_template_from_resolved_ty(f.error)
                ?? return null;
            root.types.TyTemplateFuture { value: value, error: error }
        },
        // A realized leaf (incl. a monomorphic class): narrow and widen.
        _ => realized_leaf_template(ty),
    }
}

// Rust's `tys.iter().map(ty_to_pattern_template_from_resolved_ty)
// .collect::<Option<Vec<_>>>()`.
function pattern_templates_of(
    tys: root.types.RuntimeTy[],
) -> root.types.TyTemplate[]? throws never {
    let out: root.types.TyTemplate[] = [];
    for (let ty in tys) {
        out.push(
            ty_to_pattern_template_from_resolved_ty(ty)
                ?? return null,
        );
    }
    out
}

// port: baml_compiler2_mir/src/lower.rs::MatchScrutinee @ d9be6853b
// The value an enclosing `match` scrutinizes, for the coarse-tag proofs.
class MatchScrutinee {
    // The local the match evaluated its scrutinee into, then each snapshot a
    // narrowing arm (`let x: T`) copies it into and tests in its place.
    locals: int[],
    // The scrutinee's resolved static type.
    ty: root.types.RuntimeTy,

    // port: baml_compiler2_mir/src/lower.rs::MatchScrutinee::new @ d9be6853b
    function new(local: int, ty: root.types.RuntimeTy) -> MatchScrutinee throws never {
        MatchScrutinee { locals: [local], ty: ty }
    }

    // port: baml_compiler2_mir/src/lower.rs::MatchScrutinee::ty_held_by @ d9be6853b
    // The scrutinee's static type when `local` holds the scrutinee.
    function ty_held_by(self, local: int) -> root.types.RuntimeTy? throws never {
        if (self.locals.includes(local)) {
            self.ty
        } else {
            null
        }
    }

    // port: baml_compiler2_mir/src/lower.rs::MatchScrutinee::record_copy @ d9be6853b
    // Records that `copy` was assigned a copy of `source`: if `source` holds
    // the scrutinee, so does `copy`.
    function record_copy(self, source: int, copy: int) -> void throws never {
        if (self.locals.includes(source)) {
            self.locals.push(copy);
        }
    }
}

// port: baml_compiler2_mir/src/lower.rs::flatten_runtime_union @ d9be6853b
// Flatten a `RuntimeTy` union into its leaf members (recursively), pushing
// each non-union leaf into `out`. A recursive alias is kept as a single
// `TypeAlias` leaf, matching `ResolvedAliases::convert`.
function flatten_runtime_union(
    ty: root.types.RuntimeTy,
    out: root.types.RuntimeTy[],
) -> void throws never {
    match (ty) {
        let u: root.types.RuntimeTyUnion => {
            for (let member in u.members) {
                flatten_runtime_union(member, out);
            }
        },
        _ => {
            out.push(ty);
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::member_is_opaque_for_tag_proof @ d9be6853b
// A scrutinee member is opaque for a coarse-tag soundness proof when it
// could dynamically resolve to a container or class instantiation its static
// type does not reveal: a type alias, a type variable, `unknown`, an
// interface, or an associated projection. A tag-sufficiency proof fails
// closed on it. Exhaustive on purpose.
function member_is_opaque_for_tag_proof(m: root.types.RuntimeTy) -> bool throws never {
    match (m) {
        root.types.TyTypeAlias
            | root.types.TyTypeVar
            | root.types.TyUnknown
            | root.types.RuntimeTyAssociatedTypeProjection
            | root.types.RuntimeTyInterface =>
        {
            true
        },
        // A union should have been flattened before this check; recurse
        // defensively so a nested one can't smuggle an opaque member past it.
        let u: root.types.RuntimeTyUnion => u.members.some(member_is_opaque_for_tag_proof),
        // Every concrete leaf carries a fixed runtime tag we can reason about.
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.RuntimeTyClass
            | root.types.TyEnum
            | root.types.TyEnumVariant
            | root.types.TyLiteral
            | root.types.RuntimeTyFunction
            | root.types.RuntimeTyFuture
            | root.types.RuntimeTyList
            | root.types.RuntimeTyMap
            | root.types.RuntimeTyTuple
            | root.types.TyRustType
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst
            | root.types.TyNever =>
        {
            false
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::TagConflatedShape @ d9be6853b
// A parametric shape whose every instantiation collapses onto one coarse
// type tag: two arms at different instantiations dedup onto the same
// jump-table slot. `Future`: every instantiation is `FUTURE`-tagged.
enum TagConflatedShape {
    List,
    Map,
    Future,
}

// port: baml_compiler2_mir/src/lower.rs::tag_conflated_shape @ d9be6853b
// The `TagConflatedShape` of `ty`, or null when its tag already pins its
// values (a primitive, a monomorphic class, ..).
function tag_conflated_shape(ty: root.types.RuntimeTy) -> TagConflatedShape? throws never {
    match (ty) {
        root.types.RuntimeTyList => TagConflatedShape.List,
        root.types.RuntimeTyMap => TagConflatedShape.Map,
        root.types.RuntimeTyFuture => TagConflatedShape.Future,
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::parametric_arm_tag_sufficient @ d9be6853b
// Whether a coarse `LIST`/`MAP`/`FUTURE` type-tag test for the parametric
// arm `arm` is a provably sound substitute for the argument-discriminating
// structural test, for values of the scrutinee's resolved static type
// `scrutinee`: every same-shape member of the scrutinee shares the arm's
// constructor identity, and every other member carries a tag that provably
// can't be the arm's. Fails closed on an opaque member. False for a
// non-parametric `arm`.
function parametric_arm_tag_sufficient(
    arm: root.types.RuntimeTy,
    scrutinee: root.types.RuntimeTy,
) -> bool throws never {
    let arm_shape = tag_conflated_shape(arm)
        ?? return false;
    let arm_id = root.hir_ty.ty_ctor_identity(root.types.widen_runtime_ty_to_ty(arm));
    let members: root.types.RuntimeTy[] = [];
    flatten_runtime_union(scrutinee, members);
    members.every((m) -> {
        let shape = tag_conflated_shape(m);
        if (shape == null) {
            // Sound iff it cannot secretly be a differing instantiation.
            !member_is_opaque_for_tag_proof(m)
        } else if (shape == arm_shape) {
            // Same shape: sound only for the arm's exact instantiation.
            root.hir_ty.ty_ctor_identity(root.types.widen_runtime_ty_to_ty(m)) == arm_id
        } else {
            // A different parametric shape carries a tag that can't be the
            // arm's.
            true
        }
    })
}

// port: baml_compiler2_mir/src/lower.rs::switch_member_tag_sufficient @ d9be6853b
// Whether the coarse type tag fully discriminates values reaching a switch
// arm whose (already union-flattened) member type is `member`, given the
// enclosing match scrutinee's resolved static type when known. Type tags
// conflate every list, every map and every instantiation of a generic class,
// and every enum shares the `ENUM` tag.
function switch_member_tag_sufficient(
    member: root.types.RuntimeTy,
    scrutinee: root.types.RuntimeTy?,
) -> bool throws never {
    match (member) {
        root.types.RuntimeTyList | root.types.RuntimeTyMap | root.types.RuntimeTyFuture => {
            scrutinee != null && parametric_arm_tag_sufficient(member, scrutinee)
        },
        // Every enum collapses onto the single shared `ENUM` type tag, so the
        // jump table can key an enum-type arm only when no other enum type
        // reaches this match.
        let e: root.types.TyEnum => {
            if (scrutinee == null) {
                return false;
            }
            let flat: root.types.RuntimeTy[] = [];
            flatten_runtime_union(scrutinee, flat);
            flat.every((m) -> {
                let m_name = enum_type_name(m);
                if (m_name != null) {
                    // Another enum type shares this arm's `ENUM` tag.
                    m_name == e.name
                } else {
                    // An opaque member could dynamically be a different enum.
                    !member_is_opaque_for_tag_proof(m)
                }
            })
        },
        // A specific variant type needs variant-level discrimination the
        // shared `ENUM` tag can't express.
        root.types.TyEnumVariant => false,
        root.types.RuntimeTyTuple => false,
        let c: root.types.RuntimeTyClass => {
            if (c.args.length() == 0) {
                return true;
            }
            if (scrutinee == null) {
                return false;
            }
            let member_id = root.hir_ty.ty_ctor_identity(root.types.widen_runtime_ty_to_ty(member));
            let flat: root.types.RuntimeTy[] = [];
            flatten_runtime_union(scrutinee, flat);
            flat.every((m) -> {
                match (m) {
                    let mc: root.types.RuntimeTyClass if mc.name == c.name => {
                        root.hir_ty.ty_ctor_identity(root.types.widen_runtime_ty_to_ty(m))
                            == member_id
                    },
                    // A different class dispatches on a different tag.
                    root.types.RuntimeTyClass => true,
                    // An opaque member may admit another instantiation of
                    // this class at runtime; the proof fails closed.
                    _ => !member_is_opaque_for_tag_proof(m),
                }
            })
        },
        _ => true,
    }
}

// port: baml_compiler2_mir/src/lower.rs::enum_type_name @ d9be6853b
// The enum type name of an enum-shaped type. A bare enum and any of its
// variants collapse onto the same shared `ENUM` type tag.
function enum_type_name(ty: root.types.RuntimeTy) -> root.types.DeclName? throws never {
    match (ty) {
        let e: root.types.TyEnum => e.name,
        let v: root.types.TyEnumVariant => v.name,
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::definition_display_name @ d9be6853b
// The name a definition links and displays as: `pkg.ns.name` for a free
// item, `pkg.ns.Class.name` for a class-inherent method, and, for an
// interface-machinery body, `pkg.ns.<display owner>.name`. An impl-provided
// body is no item of a namespace: its spelling is the package label and the
// `<(target as iface)>.m` tail alone. A canonical rendering, never an
// identity.
function definition_display_name(db: root.hir.Db, def: root.hir.Definition) -> string throws never {
    let pkg_info = root.hir.file_package(db, root.hir.definition_file(def, db));
    let namespace = match (def) {
        let f: root.hir.DefinitionFunction
            if root.hir.method_owner(db, f.value) is root.hir.MethodOwnerImpl => {
            []
        },
        _ => pkg_info.namespace_path,
    };
    dotted_name(
        root.hir_ty.Viewpoint.canonical(db).display_package(pkg_info.root_id),
        namespace,
        [definition_short_name(db, def)],
    )
}

// port: baml_compiler2_mir/src/lower.rs::global_display_name @ d9be6853b
// The display name of a top-level binding: a source `let` by its
// declaration. (An exported row of a served package has no `int` loc here.)
function global_display_name(db: root.hir.Db, global: int) -> string throws never {
    definition_display_name(db, root.hir.DefinitionLet { value: global })
}

// port: baml_compiler2_mir/src/lower.rs::definition_short_name @ d9be6853b
// The owner-qualified tail of a declaration's display name, everything after
// the package and namespace segments: `f` for a free function, `Class.m` for
// a class-inherent method, `Interface.m` for an interface's default body,
// `<(target as iface)>.m` for an impl-provided one, and the bare name for
// every other item.
function definition_short_name(db: root.hir.Db, def: root.hir.Definition) -> string throws never {
    let name = match (def) {
        let d: root.hir.DefinitionFunction => root.hir.function_data(db, d.value).name,
        let d: root.hir.DefinitionClass => root.hir.class_data(db, d.value).name,
        let d: root.hir.DefinitionEnum => root.hir.enum_data(db, d.value).name,
        let d: root.hir.DefinitionInterface => root.hir.interface_data(db, d.value).name,
        let d: root.hir.DefinitionTypeAlias => root.hir.type_alias_data(db, d.value).name,
        let d: root.hir.DefinitionLet => root.hir.let_data(db, d.value).name,
    };
    // A method's name is qualified by its owner so it gets a distinct global
    // slot instead of colliding with a same-named free function.
    let func_loc = match (def) {
        let d: root.hir.DefinitionFunction => d.value,
        _ => {
            return name;
        },
    };
    match (root.hir.method_owner(db, func_loc)) {
        let owner: root.hir.MethodOwnerClass => {
            `${root.hir.class_data(db, owner.value).name}.${name}`
        },
        // A REQUIRED method has a valid NAME but resolves to no slot: only
        // default-bodied methods are compiled.
        let owner: root.hir.MethodOwnerInterface => {
            `${root.hir.interface_data(db, owner.value).name}.${name}`
        },
        // The identity is the declaration; only the display segment is
        // synthesized: `<(target as iface)>`.
        let owner: root.hir.MethodOwnerImpl => `${impl_display_segment(db, owner.value)}.${name}`,
        null => name,
    }
}

// port: baml_compiler2_mir/src/lower.rs::dotted_name @ d9be6853b
// `package.ns..tail..`: the one dotted spelling every display name uses.
function dotted_name(package: string, namespace: string[], tail: string[]) -> string throws never {
    [package].concat(namespace).concat(tail).join(".")
}

// port: baml_compiler2_mir/src/lower.rs::impl_display_segment @ d9be6853b
// The synthesized `<(target as iface)>` display segment for an anonymous
// impl block: both halves spelled from the body's own package, generic and
// interface arguments included, associated-type pins excluded, the impl's
// own type variables as frame indices (`#0`).
function impl_display_segment(db: root.hir.Db, impl_loc: int) -> string throws never {
    let block = root.hir.impl_block_data(db, impl_loc);
    let impl_params = root.hir_ty.impl_frame(db, impl_loc);
    let impl_bounds = root.hir_ty.impl_generic_bounds(db, impl_loc);
    let file = db.impl_locs.get(impl_loc).file;
    let ctx = root.hir_ty.lower_ctx_for_file(db, file).with_frame(impl_params.concat([])).with_bounds(
        impl_bounds,
    );
    let lowered = root.hir_ty.reject_holes(
        ctx.lower_type_ref(
            block.type_refs,
            block.interface_target,
            position = root.hir_ty.TypePosition.ConstraintHead,
        ),
    );
    // Associated-type pins are excluded from the rendered identity.
    let iface_ty = match (lowered) {
        let i: root.types.TyInterface => {
            root.types.TyInterface { name: i.name, args: i.args, associated_types: [] }
        },
        _ => lowered,
    };
    let target_ty = root.hir_ty.impl_self_ty(db, impl_loc);
    let spelling = BodyPackageSpelling { db: db, body_root: root.hir.file_package(db, file).root_id };
    let target_text = render_with_frame_indices(target_ty, impl_params, spelling);
    let iface_text = render_with_frame_indices(iface_ty, impl_params, spelling);
    `<(${target_text} as ${iface_text})>`
}

// port: baml_compiler2_mir/src/lower.rs::BodyPackageSpelling @ d9be6853b
// Heads spelled from an impl body's own package: its own declarations by the
// package's display label, a dependency's by the edges that reach it
// (`edge.ns.X`), which is how the runtime renders the body's key.
class BodyPackageSpelling {
    db: root.hir.Db,
    body_root: int,

    // port: baml_compiler2_mir/src/lower.rs::impl TyRenderStrategy for BodyPackageSpelling @ d9be6853b
    implements root.types.TyRenderStrategy {
        // port: baml_compiler2_mir/src/lower.rs::BodyPackageSpelling::qtn @ d9be6853b
        // Rust's `Display` of the `EdgePath` (`root` for the package itself,
        // else the dotted edge names) is written inline.
        function qtn(self, qtn: root.types.DeclName) -> string throws never {
            let package = if (qtn.pkg == self.body_root) {
                root.hir_ty.Viewpoint.canonical(self.db).display_package(self.body_root)
            } else {
                let edges = root.hir.edge_spelling(self.db, self.body_root, qtn.pkg).value;
                if (edges.length() == 0) {
                    "root"
                } else {
                    edges.join(".")
                }
            };
            [package].concat(qtn.namespace).concat([qtn.name]).join(".")
        }

        // port: baml_compiler2_mir/src/lower.rs::BodyPackageSpelling::type_var @ d9be6853b
        function type_var(self, name: string) -> string throws never {
            name
        }
    }
}

// port: baml_compiler2_mir/src/lower.rs::interface_body_link_bounds_suffix @ d9be6853b
// The `where` suffix of an impl-provided interface body's DISPLAY: the impl's
// constraint set, rendered with frame indices. Null for anything that is not
// an impl-provided body and for an unbounded impl. Within a param the bounds
// are sorted by rendering, so a written reorder cannot fork the key.
function interface_body_link_bounds_suffix(db: root.hir.Db, func_loc: int) -> string? throws never {
    let impl_loc = match (root.hir.method_owner(db, func_loc)) {
        let owner: root.hir.MethodOwnerImpl => owner.value,
        _ => {
            return null;
        },
    };
    let impl_params = root.hir_ty.impl_frame(db, impl_loc);
    let impl_bounds = root.hir_ty.impl_generic_bounds(db, impl_loc);
    let file = db.impl_locs.get(impl_loc).file;
    let spelling = BodyPackageSpelling { db: db, body_root: root.hir.file_package(db, file).root_id };
    let parts: string[] = [];
    for (let index = 0; index < impl_params.length(); index += 1) {
        let bounds = impl_bounds.get(impl_params[index]);
        if (bounds == null || bounds.length() == 0) {
            continue;
        }
        let rendered = bounds
            .map((bound) -> {
                render_with_frame_indices(plain_interface_ty(bound), impl_params, spelling)
            })
            .sort_by_key((text) -> {
                text
            });
        parts.push(`#${index}: ${rendered.join(" + ")}`);
    }
    if (parts.length() == 0) {
        return null;
    }
    ` where ${parts.join(", ")}`
}

// port: baml_compiler2_mir/src/lower.rs::render_with_frame_indices @ d9be6853b
// Render `ty` canonically with the impl frame's type variables spelled as
// their frame indices (`#0`) instead of their declared names: the declared
// names are the block's private spelling, not part of its identity.
// Restructured: Rust rewrites through the interned `ClosedTy`'s
// `map_children`, a purely structural rebuild; here the plain `Ty`'s
// `map_children_ty` does the same.
function render_with_frame_indices(
    ty: root.types.Ty,
    frame: root.types.ParamTy[],
    spelling: root.types.TyRenderStrategy,
) -> string throws never {
    let rewritten = rewrite_frame_vars(ty, frame);
    root.types.render_with(root.types.widen_ty_to_lowering_ty(rewritten), spelling)
}

// The `rewrite` helper of `render_with_frame_indices`.
function rewrite_frame_vars(
    ty: root.types.Ty,
    frame: root.types.ParamTy[],
) -> root.types.Ty throws never {
    match (ty) {
        let v: root.types.TyTypeVar => {
            let position = frame.index_of(v.param);
            if (position != null) {
                return root.types.TyTypeVar {
                    param: root.types.ParamTy { index: position, name: `#${position}` },
                };
            }
        },
        _ => {},
    }
    root.types.map_children_ty(ty, (child) -> {
        rewrite_frame_vars(child, frame)
    })
}

// port: baml_compiler2_mir/src/lower.rs::native_key_for @ d9be6853b
// The codegen-lockstep NATIVE KEY for a builtin body: the dot-free
// `{iface as written}$for${target as written}` scheme the codegen extractor
// produces for its dispatch tables and sys-op paths, with a written `root.`
// spelled as the package (`native_key_spelling`). A KEY, not a name.
function native_key_for(db: root.hir.Db, func_loc: int) -> string throws never {
    let pkg_info = root.hir.file_package(db, db.function_locs.get(func_loc).file);
    // A native body is the standard library's own: its package is a language
    // package, keyed by its fixed name.
    let lang_package = root.hir.lang_roots(db).package_of(pkg_info.root_id)
        ?? baml.sys.panic("a native function is declared by the standard library");
    let package = root.base.lang_package_manifest_name(lang_package);
    let name = root.hir.function_data(db, func_loc).name;
    let item = match (root.hir.method_owner(db, func_loc)) {
        // A class-inherent method has no written-form target to key on: its
        // key is its display name.
        root.hir.MethodOwnerClass => {
            return definition_display_name(db, root.hir.DefinitionFunction { value: func_loc });
        },
        let owner: root.hir.MethodOwnerInterface => root.hir.interface_data(db, owner.value).name,
        let owner: root.hir.MethodOwnerImpl => {
            let block = root.hir.impl_block_data(db, owner.value);
            // An in-body block's natives are keyed by its class's name; a
            // free block's by its written for-target.
            let class_ = root.hir.impl_class(db, owner.value);
            let for_display = if (class_ != null && block.origin == root.ast.ImplOrigin.InBody) {
                root.hir.class_data(db, class_).name
            } else {
                root.types.native_key_spelling(
                    package,
                    block.type_refs.display(block.for_target).to_string(),
                )
            };
            let iface_display = root.types.native_key_spelling(
                package,
                block.type_refs.display(block.interface_target).to_string(),
            );
            [iface_display, "$for$", for_display].join("")
        },
        null => {
            return dotted_name(package, pkg_info.namespace_path, [name]);
        },
    };
    dotted_name(package, pkg_info.namespace_path, [item, name])
}

// port: baml_compiler2_mir/src/lower.rs::function_is_interface_body @ d9be6853b
// True if `func_loc` is an interface-machinery body: an impl-block method
// (in-class or free) or an interface default-method body. Class-owned
// methods are always real logical items.
function function_is_interface_body(db: root.hir.Db, func_loc: int) -> bool throws never {
    match (root.hir.method_owner(db, func_loc)) {
        root.hir.MethodOwnerInterface | root.hir.MethodOwnerImpl => true,
        root.hir.MethodOwnerClass | null => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::function_display_name @ d9be6853b
// The name a callable links as: a source declaration by
// `definition_display_name`. (A served package's row, named by its dispatch
// slot in Rust, has no `int` loc here.)
function function_display_name(db: root.hir.Db, func: int) -> string throws never {
    definition_display_name(db, root.hir.DefinitionFunction { value: func })
}

// port: baml_compiler2_mir/src/lower.rs::class_display_name @ d9be6853b
// The display name of a class: what emit renders into operand metadata.
function class_display_name(db: root.hir.Db, class_: int) -> string throws never {
    definition_display_name(db, root.hir.DefinitionClass { value: class_ })
}

// port: baml_compiler2_mir/src/lower.rs::enum_display_name @ d9be6853b
// The display name of an enum.
function enum_display_name(db: root.hir.Db, enum_ref: int) -> string throws never {
    definition_display_name(db, root.hir.DefinitionEnum { value: enum_ref })
}

// port: baml_compiler2_mir/src/lower.rs::resolution_func_loc @ d9be6853b
// The body a resolution calls directly in THIS compilation: its callable,
// when declared in source. A virtual interface method dispatches at runtime
// even when the interface declares a default. Fields, variants and virtual
// fields are not callable.
function resolution_func_loc(res: root.hir_ty.MemberResolution) -> int? throws never {
    match (res) {
        let r: root.hir_ty.MemberResolutionFree => r.func,
        let r: root.hir_ty.MemberResolutionMethod<root.types.Ty> => {
            match (r.callee) {
                let c: root.hir_ty.MethodCalleeInherent => c.value,
                let c: root.hir_ty.MethodCalleeConcrete<root.types.Ty> => c.func,
                root.hir_ty.MethodCalleeVirtual<root.types.Ty> => null,
            }
        },
        root.hir_ty.MemberResolutionField
            | root.hir_ty.MemberResolutionVariant
            | root.hir_ty.MemberResolutionInterfaceVirtualField<root.types.Ty> =>
        {
            null
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::resolution_external_function @ d9be6853b
// The exported row a resolution names, when its callee is a served
// package's. No root is served from an interface here, so every callable a
// resolution names (`member_resolution_callable`) is a source declaration
// and this is always null.
function resolution_external_function(
    db: root.hir.Db,
    res: root.hir_ty.MemberResolution,
) -> int? throws never {
    null
}

// port: baml_compiler2_mir/src/lower.rs::InterfaceTypeView @ d9be6853b
// An interface view: head, generic arguments, associated-type bindings.
type InterfaceTypeView = (root.types.DeclName, root.types.Ty[], (string, root.types.Ty)[]);

// port: baml_compiler2_mir/src/lower.rs::InterfaceMember @ d9be6853b
// What a member name means in an interface view, resolved by one walk of the
// view and its `requires` closure: `Method` is dispatchable (keyed on
// `declaring`, possibly a `requires` ancestor); `Field` is NOT dispatchable,
// whatever the field's type; `Undeclared` is nothing in the closure declares
// the name (not proof it is absent).
type InterfaceMember = InterfaceMemberMethod | InterfaceMemberField | InterfaceMemberUndeclared;

class InterfaceMemberMethod {
    declaring: InterfaceTypeView,
}

class InterfaceMemberField {
    declaring: InterfaceTypeView,
    index: int,
}

class InterfaceMemberUndeclared {
}

// port: baml_compiler2_mir/src/lower.rs::InterfaceMethodShape @ d9be6853b
// How an interface method's frame divides.
class InterfaceMethodShape {
    // Whether the method's first parameter is the `self` receiver: the SUGAR
    // question, never the dispatch one.
    takes_self: bool,
    // The declared index of the method's one required `Self`-typed
    // parameter, the value argument the VM derives `Self` from.
    dispatch_param: int?,
    // The interface's own declared generic parameter count.
    interface_generics: int,
    // Frame index where the method's OWN generics start: `1 (Self) +
    // interface generics`, clamped to the frame length.
    own_start: int,
    // Total generic-frame length.
    frame_len: int,
}

// port: baml_compiler2_mir/src/lower.rs::VirtualFieldTarget @ d9be6853b
// A virtual field access resolved down to what the instruction carries: the
// receiver, the interface that DECLARES `field` (realized at the receiver),
// and the field's index in that interface's own declared field list.
class VirtualFieldTarget {
    receiver: int,
    field: string,
    iface: root.types.TyTemplateInterfaceConstraint,
    field_index: int,
}

// port: baml_compiler2_mir/src/lower.rs::lower_ref_interface_target_args @ d9be6853b
// Lower the generic arguments of an interface target held as a `TypeRefId`
// in `store` (the `<int>` in `implements Slot<int>`). Non-`Path` targets
// contribute no arguments.
function lower_ref_interface_target_args(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    target: int,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    generic_params: root.types.ParamTy[],
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
) -> root.types.Ty[] throws never {
    match (store.get(target).kind) {
        let path: root.hir.TypeRefKindPath => {
            path.generic_args.map((arg) -> {
                lower_ref_in_scope(db, store, arg, pkg_items, namespace_path, generic_params, bounds, null)
            })
        },
        _ => [],
    }
}
