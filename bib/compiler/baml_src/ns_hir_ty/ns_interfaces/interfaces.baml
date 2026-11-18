// port: baml_compiler2_hir_ty/src/interfaces.rs @ d9be6853b
//
// Interface resolution substrate: path-to-interface resolution and identity,
// the transitive `requires` closure, associated-type binding lowering, the
// generic type-pattern matcher impl resolution uses, written-type bound
// checks and item-projection determination. Rust re-exports `interfaces/*`
// into this module, so everything here and in its sibling files is
// `root.hir_ty.interfaces.*`, as Rust's paths are.
//
// Restructured (BAML forces it):
// - A `TypeVarBoundsMap` (and every `FxHashMap<ParamTy, Vec<Interface>>`) is
//   a `map<ParamTy, InterfaceConstraint[]>`; Rust's `.clone()` of one is
//   `copy_bounds`. A `TypeBindings` clone is `root.types.copy_bindings`.
// - An `AssociatedBindings` (`Vec<(Name, Ty)>`) is an `AssociatedType[]`
//   (IDIOMS: `AssociatedType` is Rust's `(Name, Ty)` pair).
//   `InterfaceClosureEntry` and its queue twin are classes; an
//   `FxHashSet<InterfaceLoc>` is a `map<int, bool>`, and the closure walk's
//   set of entries an array probed by structural equality.
// - `lower_ref_in` / `lower_ref_in_at` are one function with
//   `position = Existential`, as lower.baml's `lower_type_ref` is.
// - The pattern matcher's `Option<()>` is `bool`; `&mut TypeBindings` is the
//   shared map, which the callee edits.
// - `InterfaceDeclScope::ctx` (a one-line forward to `ctx_with` over the
//   scope's own generics and bounds) is not ported: callers write
//   `scope.ctx_with(scope.generics, scope.bounds)`.
// - `baml_type::Interface::new` (which sorts the bindings by name) is the
//   sorted literal, as in lib.baml; a struct literal keeps Rust's order.
// - `crate::layout::alias_head` (not in layout.baml) is inlined in
//   `package_declared_aliases`; its served-alias arm is unreachable here
//   (`package_aliases` panics for a root served from its interface).
//
// Not ported:
// - `interface_requires` (this file's, taking a `PackageResolutionContext`)
//   and `existential_associated_default`: `PackageResolutionContext` is not
//   ported and nothing on the type-check path calls them.
// - `resolve_ref_to_interface` and `enum_variant_names`: one-line forwards
//   (write `resolve_ref_to_interface_identity(..)?.loc` and
//   `root.hir_ty.uncached_enum_variants`).
// - `mounted_declares_member` / `mounted_declared_kind` and the mounted-row
//   branch of `interface_declares_member` / `interface_declared_kind`: the
//   stub `ExportedTypeInterface` carries no method rows, and
//   `mounted_type_row` is null for every root here (no root is served from
//   an interface). Likewise the `mounted_interface_loc` branch of
//   `collect_type_generic_bound_errors`.

// port: baml_compiler2_hir_ty/src/interfaces.rs::InterfaceClosureEntry @ d9be6853b
// One interface of a `requires` closure, realized: its loc, its generic
// arguments and its associated-type bindings.
class InterfaceClosureEntry {
    loc: int,
    args: root.types.Ty[],
    associated_bindings: root.types.AssociatedType[],
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::InterfaceClosureQueueEntry @ d9be6853b
// A pending closure entry with the interfaces on its path from the root.
class InterfaceClosureQueueEntry {
    loc: int,
    args: root.types.Ty[],
    associated_bindings: root.types.AssociatedType[],
    ancestors: map<int, bool>,
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::TypeVarBoundsMap @ d9be6853b
// Rust's derived `Clone` of a param-bounds map.
function copy_bounds(
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    let out: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
    for (let param in bounds.keys()) {
        out[param] = bounds[param];
    }
    out
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::LowerScope @ d9be6853b
// The one lowering seam: the items view, namespace, rigid params, plain
// bounds and optional plain `Self` a written type lowers under.
class LowerScope {
    db: root.hir.Db,
    package_items: root.hir.PackageItems,
    ns_context: string[],
    generic_params: root.types.ParamTy[],
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    self_ty: root.types.Ty?,
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::scope_ctx @ d9be6853b
function scope_ctx(scope: LowerScope) -> root.hir_ty.LowerCtx throws never {
    root.hir_ty.lower_ctx_for_package(scope.db, scope.package_items, scope.ns_context)
        .with_frame(scope.generic_params.concat([]))
        .with_bounds(copy_bounds(scope.bounds))
        .with_self_ty(scope.self_ty)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::lower_ref_in_at @ d9be6853b
// Also `lower_ref_in` (the existential default). Lower one type reference
// through the scope, pushing its lowering diagnostics into `diags`.
function lower_ref_in(
    scope: LowerScope,
    store: root.hir.TypeRefStore,
    id: int,
    diags: root.hir_ty.TirTypeError[],
    position: root.hir_ty.TypePosition = root.hir_ty.TypePosition.Existential,
) -> root.types.Ty throws never {
    let ctx = scope_ctx(scope);
    let (let lowered, let lowering_diagnostics) = ctx.lower_type_ref_with_diagnostics(store, id, position = position);
    for (let diag in lowering_diagnostics) {
        diags.push(root.hir_ty.lowering_diag_error(diag.kind));
    }
    root.hir_ty.reject_holes(lowered)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::lower_expr_in_at @ d9be6853b
// `lower_ref_in` over an AST type expression, lowered into a scratch arena.
function lower_expr_in_at(
    scope: LowerScope,
    expr: root.ast.TypeExpr,
    position: root.hir_ty.TypePosition,
    diags: root.hir_ty.TirTypeError[],
) -> root.types.Ty throws never {
    let builder = root.hir.TypeRefBuilder.new();
    let id = builder.lower(expr);
    let (let store, _) = builder.finish();
    lower_ref_in(scope, store, id, diags, position = position)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_self_param @ d9be6853b
// `Self`: the interface frame's universal slot 0.
function interface_self_param(db: root.hir.Db, iface_loc: int) -> root.types.ParamTy throws never {
    root.hir_ty.interface_frame(db, iface_loc).at(0)
        ?? baml.sys.panic("interface frame starts with Self")
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::collapse_self_assoc_projections @ d9be6853b
// Collapse `Self.X` projections through the pins resolved so far. Only
// projections whose base IS this interface's `Self` (the symbolic param or
// the realized receiver) and whose qualifier matches at its generics too
// collapse; foreign bases keep theirs.
function collapse_self_assoc_projections(
    ty: root.types.Ty,
    self_tys: root.types.Ty[],
    iface: root.types.DeclName?,
    iface_args: root.types.Ty[],
    pins: root.types.AssociatedType[],
) -> root.types.Ty throws never {
    let iface_name = iface
        ?? return ty;
    if (pins.length() == 0) {
        return ty;
    }
    root.types.rewrite_ty(ty, (node) -> {
        match (node) {
            let p: root.types.TyAssociatedTypeProjection
                if p.interface_.name == iface_name
                && p.interface_.generics == iface_args
                && self_tys.includes(p.base) => {
                pins
                    .find((pin) -> {
                        pin.name == p.member
                    })
                    ?.ty
            },
            _ => null,
        }
    })
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::identity_bindings @ d9be6853b
// One binding per param mapping it to itself as a rigid var: the identity
// substitution seed.
function identity_bindings(
    generic_params: root.types.ParamTy[],
) -> root.types.TypeBindings throws never {
    let bindings: root.types.TypeBindings = {};
    for (let param in generic_params) {
        bindings[param] = root.types.TyTypeVar { param: param };
    }
    bindings
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::append_params @ d9be6853b
function append_params(
    parent: root.types.ParamTy[],
    names: string[],
) -> root.types.ParamTy[] throws never {
    let params = parent.concat([]);
    root.types.ParamTy.extend_frame(params, names);
    params
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_declared_param_bounds @ d9be6853b
// The interface's declared-parameter bounds, keyed by the declared params.
// Only interface-shaped bounds contribute; lowering errors are the
// declaration's own diagnostics, dropped here. Each bound lowers in the
// interface's scope, so it may project through another param's or `Self`'s.
function interface_declared_param_bounds(
    db: root.hir.Db,
    iface_loc: int,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    let data = root.hir.interface_data(db, iface_loc);
    let frame = root.hir_ty.interface_frame(db, iface_loc);
    let declared = root.hir_ty.interface_declared_params(db, iface_loc);
    let ctx = root.hir_ty.lower_ctx_for_file(db, db.interface_locs.get(iface_loc).file)
        .with_frame(frame)
        .with_bounds(root.hir_ty.interface_scope_bounds(db, iface_loc));
    let bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
    for (let i = 0; i < declared.length() && i < data.generic_params.length(); i += 1) {
        let constraints = data.generic_params[i].bounds.filter_map((id) -> {
            root.types.as_interface(
                root.hir_ty.reject_holes(
                    ctx.lower_type_ref(
                        data.type_refs,
                        id,
                        position = root.hir_ty.TypePosition.ConstraintHead,
                    ),
                ),
            )
        });
        if (constraints.length() != 0) {
            bounds[declared[i]] = constraints;
        }
    }
    bounds
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::package_resolved_aliases @ d9be6853b
// Every type alias visible to `pkg_id` (its own plus its dependency
// closure's), resolved to its one-level value.
function package_resolved_aliases(
    db: root.hir.Db,
    pkg_id: int,
) -> map<root.types.DeclName, root.types.Ty> throws never {
    db.ty_memo.package_resolved_aliases.get(db.cycles, pkg_id, () -> {
        let aliases: map<root.types.DeclName, root.types.Ty> = {};
        let packages = [pkg_id].concat(root.hir.package_dependency_closure(db, pkg_id));
        for (let pkg in packages) {
            package_declared_aliases(db, pkg, aliases);
        }
        aliases
    })
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::package_declared_aliases @ d9be6853b
// The aliases `pkg` declares, whichever lane serves it; the first
// declaration of a head wins.
function package_declared_aliases(
    db: root.hir.Db,
    pkg: int,
    out: map<root.types.DeclName, root.types.Ty>,
) -> void throws never {
    for (let alias in root.hir_ty.package_aliases(db, pkg)) {
        // `crate::layout::alias_head`, inlined.
        let head = match (alias) {
            let source: root.hir.DeclRefSource<int> => {
                root.hir_ty.qualify_def(
                    db,
                    root.hir.DefinitionTypeAlias { value: source.value },
                    root.hir.type_alias_data(db, source.value).name,
                )
            },
            root.hir.DeclRefExternal<int> => {
                baml.sys.panic("alias_head: a served alias is not ported")
            },
        };
        if (!out.has(head)) {
            out[head] = root.hir_ty.alias_value(db, alias);
        }
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::normalized_alias_map @ d9be6853b
// `package_resolved_aliases` with every body folded toward the union
// canonical form the overlap machinery assumes.
function normalized_alias_map(
    db: root.hir.Db,
    pkg_id: int,
) -> map<root.types.DeclName, root.types.Ty> throws never {
    db.ty_memo.normalized_alias_map.get(db.cycles, pkg_id, () -> {
        let resolved = package_resolved_aliases(db, pkg_id);
        let enum_variants = (qtn: root.types.DeclName) -> string[]? {
            root.hir_ty.uncached_enum_variants(db, qtn)
        };
        let aliases: map<root.types.DeclName, root.types.Ty> = {};
        for (let name in resolved.keys()) {
            aliases[name] = root.types.nf(resolved[name], enum_variants);
        }
        aliases
    })
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::InterfaceTypeAssocLowering @ d9be6853b
// The inputs for lowering a required interface's associated bindings at a
// `requires` site.
class InterfaceTypeAssocLowering {
    db: root.hir.Db,
    iface_loc: int,
    iface: root.hir.InterfaceData,
    interface_args: root.types.Ty[],
    explicit_associated_bindings: root.hir.AssociatedTypeBindingRef[],
    // The arena the explicit bindings' `ty` ids index: the requiring item's
    // `type_refs` (the bindings are written at the `requires` site).
    binding_type_refs: root.hir.TypeRefStore,
    binding_pkg_items: root.hir.PackageItems,
    binding_namespace_path: string[],
    outer_bindings: root.types.TypeBindings,
    // The requiring interface as a constraint (its associated types pinned to
    // the realized bindings), so `Item = Self.Item` resolves `Self.Item` onto
    // it. Null only if that interface's qtn can't be resolved.
    self_bound: root.types.InterfaceConstraint?,
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::InterfaceImplOrigin @ d9be6853b
// Where an `implements` block was written. Diagnostic metadata only.
type InterfaceImplOrigin = InterfaceImplOriginInBodyClass | InterfaceImplOriginOutOfBody;

// `implements I { ... }` written in the class body.
class InterfaceImplOriginInBodyClass {
    class_qtn: root.types.DeclName,
}

// `implement<...> I for <for_target>`: any out-of-body impl.
class InterfaceImplOriginOutOfBody {
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::ResolvedInterface @ d9be6853b
// An interface declaration resolved from a path: its interface loc id plus
// its fully qualified identity.
class ResolvedInterface {
    loc: int,
    qtn: root.types.DeclName,
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::normalized_arg_implements_bound @ d9be6853b
// Whether `arg` (already normalized) implements the interface `bound`. A
// concrete type implements it through its impls; a bounded type variable or
// projection satisfies it iff one of its carried bounds is, or transitively
// requires, `bound`. An error sentinel satisfies it (no cascade).
function normalized_arg_implements_bound(
    ctx: root.types.TypeContext,
    arg: root.types.Ty,
    bound: root.types.InterfaceConstraint,
) -> bool throws never {
    let carried_bounds = match (arg) {
        root.types.TyError => {
            return true;
        },
        let v: root.types.TyTypeVar => ctx.type_var_bound(v.param),
        let p: root.types.TyAssociatedTypeProjection => {
            ctx.associated_type_bound(p.interface_, p.member)
        },
        // A concrete argument implements the bound directly through its impls.
        _ => {
            return ctx.implements_interface(arg, bound);
        },
    };
    carried_bounds.some((have) -> {
        carried_bound_satisfies(ctx, have, bound) || ctx.interface_requires(have, bound)
    })
        || ctx.implements_interface(arg, bound)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::carried_bound_satisfies @ d9be6853b
// Whether a bound `have` carried by a type variable (or projection)
// discharges a required `bound`: same interface, equivalent generics, and
// `have` pins every associated type `bound` pins.
function carried_bound_satisfies(
    ctx: root.types.TypeContext,
    have: root.types.InterfaceConstraint,
    bound: root.types.InterfaceConstraint,
) -> bool throws never {
    have.name == bound.name
        && have.generics.length() == bound.generics.length()
        && root.types.zip_all(have.generics, bound.generics, (h, b) -> {
            ctx.equivalent(h, b)
        })
        && bound.associated_types.every((bound_pin) -> {
            have.associated_types.some((have_pin) -> {
                have_pin.name == bound_pin.name && ctx.equivalent(have_pin.ty, bound_pin.ty)
            })
        })
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::lower_interface_associated_bindings @ d9be6853b
// An impl block's associated-type bindings, in the interface's declaration
// order: a written binding lowers in the impl's scope with `Self` a rigid
// variable bounded by the interface at the pins resolved so far; an omitted
// one fills the interface's default realized at the impl's receiver.
function lower_interface_associated_bindings(
    db: root.hir.Db,
    iface_loc: int,
    iface: root.hir.InterfaceData,
    interface_args: root.types.Ty[],
    self_ty: root.types.Ty,
    // The arena the block bindings' `type_ref` ids index: the impl block's
    // own `type_refs`.
    binding_type_refs: root.hir.TypeRefStore,
    block_associated_bindings: root.hir.AssociatedTypeBindingData[],
    binding_pkg_items: root.hir.PackageItems,
    binding_namespace_path: string[],
    generic_params: root.types.ParamTy[],
    caller_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    diagnostics: root.hir_ty.TirTypeError[],
) -> root.types.AssociatedType[] throws never {
    let self_param = interface_self_param(db, iface_loc);
    let iface_params = root.hir_ty.interface_declared_params(db, iface_loc);
    let iface_qtn = interface_loc_qtn(db, iface_loc);
    let value_scope = generic_params.concat([self_param]);
    let value_bindings = identity_bindings(generic_params);
    value_bindings[self_param] = self_ty;
    let resolved_pins: root.types.AssociatedType[] = [];
    let default_bindings = root.types.bind_type_vars(iface_params, interface_args);
    let self_var = root.types.TyTypeVar { param: self_param };

    for (let assoc in iface.associated_types) {
        let binding = block_associated_bindings.find((binding) -> {
            binding.name == assoc.name
        });
        let type_ref = binding?.type_ref;
        let ty: root.types.Ty? = if (type_ref != null) {
            let bounds = copy_bounds(caller_bounds);
            if (iface_qtn != null) {
                bounds[self_param]
                    = [
                        root.types.InterfaceConstraint {
                            name: iface_qtn,
                            generics: interface_args,
                            associated_types: resolved_pins.concat([]).sort_by_key((pin) -> {
                                pin.name
                            }),
                        },
                    ];
            }
            let scope = LowerScope {
                db: db,
                package_items: binding_pkg_items,
                ns_context: binding_namespace_path,
                generic_params: value_scope,
                bounds: bounds,
                self_ty: root.types.TyTypeVar { param: self_param },
            };
            root.types.substitute_ty(
                lower_ref_in(scope, binding_type_refs, type_ref, diagnostics),
                value_bindings,
            )
        } else {
            // Fill the omitted default at the impl's receiver: `Self` is the
            // for-type, so a Self-referencing default reduces through the impl.
            let found = interface_associated_type_default(db, iface_loc, assoc.name);
            if (found == null) {
                null
            } else {
                let realized = realize_associated_default(found.0, iface_params, interface_args, self_param, self_ty);
                root.types.substitute_ty(realized, default_bindings)
            }
        };
        if (ty == null) {
            continue;
        }
        // A sibling reference (`type Items = Self.Item[]`) is a projection
        // over `Self`; the earlier witness is its value.
        let collapsed = collapse_self_assoc_projections(ty, [self_var, self_ty], iface_qtn, interface_args, resolved_pins);
        resolved_pins.push(root.types.AssociatedType { name: assoc.name, ty: collapsed });
    }
    resolved_pins
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::complete_interface_associated_bindings_from_tys @ d9be6853b
// An interface's associated bindings completed from already-lowered types,
// in declaration order. With `fill_defaults` false an unbound member stays
// absent (a rigid `Self` keeps `Self.X` symbolic: its implementor may
// override the default).
function complete_interface_associated_bindings_from_tys(
    db: root.hir.Db,
    iface_loc: int,
    iface: root.hir.InterfaceData,
    interface_args: root.types.Ty[],
    associated_bindings: root.types.AssociatedType[],
    fill_defaults: bool,
) -> root.types.AssociatedType[] throws never {
    let self_param = interface_self_param(db, iface_loc);
    let iface_params = root.hir_ty.interface_declared_params(db, iface_loc);
    let iface_qtn = interface_loc_qtn(db, iface_loc);
    let bindings = root.types.bind_type_vars(iface_params, interface_args);
    let self_var = root.types.TyTypeVar { param: self_param };
    // The members resolved so far, in declaration order: a later member's
    // `Self.X` projection collapses through them.
    let resolved_pins: root.types.AssociatedType[] = [];

    for (let assoc in iface.associated_types) {
        let written = associated_bindings.find((pin) -> {
            pin.name == assoc.name
        });
        if (written != null) {
            let ty = root.types.substitute_ty(written.ty, bindings);
            let collapsed = collapse_self_assoc_projections(ty, [self_var], iface_qtn, interface_args, resolved_pins);
            resolved_pins.push(root.types.AssociatedType { name: assoc.name, ty: collapsed });
            continue;
        }
        if (!fill_defaults) {
            continue;
        }
        // Fill the default at this interface realized on the receiver: `Self`
        // is that existential (its generic args plus the bindings resolved so
        // far).
        let found = interface_associated_type_default(db, iface_loc, assoc.name);
        if (found == null || iface_qtn == null) {
            continue;
        }
        let self_ty = root.types.TyInterface {
            name: iface_qtn,
            args: interface_args,
            associated_types: resolved_pins.concat([]),
        };
        let realized = realize_associated_default(found.0, iface_params, interface_args, self_param, self_ty);
        let ty = root.types.substitute_ty(realized, bindings);
        let collapsed = collapse_self_assoc_projections(ty, [self_var, self_ty], iface_qtn, interface_args, resolved_pins);
        resolved_pins.push(root.types.AssociatedType { name: assoc.name, ty: collapsed });
    }
    resolved_pins
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::InterfaceDeclScope @ d9be6853b
// Owned ingredients for lowering a type written inside an interface's own
// declaration: its generic params as rigid type variables and a symbolic
// `Self` (a rigid variable bounded by this interface at those params).
class InterfaceDeclScope {
    db: root.hir.Db,
    pkg_items: root.hir.PackageItems,
    ns: string[],
    // `Self` followed by the interface's declared generic parameters.
    generics: root.types.ParamTy[],
    // The interface's declared bounds plus the `Self` bound.
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    self_param: root.types.ParamTy,

    // port: baml_compiler2_hir_ty/src/interfaces.rs::InterfaceDeclScope::new @ d9be6853b
    function new(db: root.hir.Db, iface_loc: int) -> InterfaceDeclScope throws never {
        let iface = root.hir.interface_data(db, iface_loc);
        let pkg_info = root.hir.file_package(db, db.interface_locs.get(iface_loc).file);
        let pkg_items = root.hir.package_items(db, pkg_info.root_id);
        // `Self` plus the declared params: the frame's universal prefix.
        let declared_len = root.hir_ty.interface_declared_params(db, iface_loc).length();
        let generics = root.hir_ty.interface_frame(db, iface_loc).slice(0, declared_len + 1);
        let self_param = generics.at(0) ?? baml.sys.panic("interface frame starts with Self");
        let self_constraint = root.types.InterfaceConstraint {
            name: root.hir_ty.qualify_def(
                db,
                root.hir.DefinitionInterface { value: iface_loc },
                iface.name,
            ),
            generics: generics.slice(1, generics.length()).map((p) -> {
                root.types.TyTypeVar { param: p }
            }),
            associated_types: [],
        };
        let bounds = interface_declared_param_bounds(db, iface_loc);
        bounds[self_param] = [self_constraint];
        InterfaceDeclScope {
            db: db,
            pkg_items: pkg_items,
            ns: pkg_info.namespace_path,
            generics: generics,
            bounds: bounds,
            self_param: self_param,
        }
    }

    // port: baml_compiler2_hir_ty/src/interfaces.rs::InterfaceDeclScope::ctx_with @ d9be6853b
    // A lowering scope with `generics` / `bounds` (this scope's, or extended
    // with a method's own parameters).
    function ctx_with(
        self,
        generics: root.types.ParamTy[],
        bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    ) -> LowerScope throws never {
        LowerScope {
            db: self.db,
            package_items: self.pkg_items,
            ns_context: self.ns,
            generic_params: generics,
            bounds: bounds,
            self_ty: root.types.TyTypeVar { param: self.self_param },
        }
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_associated_type_default @ d9be6853b
// An associated type's `default`, lowered once against the interface's own
// scope (rigid generic params, symbolic `Self`), with its lowering
// diagnostics; null when the associated type has no default. The
// `(interface, name)` key is interned in `db.ty_memo.assoc_members`.
function interface_associated_type_default(
    db: root.hir.Db,
    iface_loc: int,
    name: string,
) -> (root.types.Ty, root.hir_ty.TirTypeError[])? throws never {
    let key = db.ty_memo.assoc_members.intern(iface_loc, name);
    db.ty_memo.interface_associated_type_default.get(db.cycles, key, () -> {
        let iface = root.hir.interface_data(db, iface_loc);
        let assoc = iface.associated_types.find((assoc) -> {
            assoc.name == name
        })
            ?? return null;
        let default_ = assoc.default
            ?? return null;
        let scope = InterfaceDeclScope.new(db, iface_loc);
        let diagnostics: root.hir_ty.TirTypeError[] = [];
        let lowered = lower_ref_in(scope.ctx_with(scope.generics, scope.bounds), iface.type_refs, default_, diagnostics);
        (lowered, diagnostics)
    })
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::ResolvedInterfaceFields @ d9be6853b
// An interface's declared fields resolved against its own scope.
class ResolvedInterfaceFields {
    fields: (string, root.types.Ty)[],
    // Type lowering diagnostics: (error, span of the type annotation).
    diagnostics: (root.hir_ty.TirTypeError, root.syntax.TextRange)[],
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolve_interface_fields @ d9be6853b
// Resolve an interface's declared field types in its own scope.
function resolve_interface_fields(
    db: root.hir.Db,
    iface_loc: int,
) -> ResolvedInterfaceFields throws never {
    db.ty_memo.resolve_interface_fields.get(db.cycles, iface_loc, () -> {
        let iface = root.hir.interface_data(db, iface_loc);
        let iface_spans = root.hir.interface_source_map(db, iface_loc);
        let scope = InterfaceDeclScope.new(db, iface_loc);
        let fields: (string, root.types.Ty)[] = [];
        let diagnostics: (root.hir_ty.TirTypeError, root.syntax.TextRange)[] = [];
        for (let field in iface.fields) {
            let field_diags: root.hir_ty.TirTypeError[] = [];
            let ty = lower_ref_in(
                scope.ctx_with(scope.generics, scope.bounds),
                iface.type_refs,
                field.type_ref,
                field_diags,
            );
            let span = iface_spans.type_refs.span(field.type_ref);
            for (let d in field_diags) {
                diagnostics.push((d, span));
            }
            fields.push((field.name, ty));
        }
        ResolvedInterfaceFields { fields: fields, diagnostics: diagnostics }
    })
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::ResolvedInterfaceMethod @ d9be6853b
// A required interface method's declaration-site resolved signature.
// `function_ty` keeps `Self` symbolic; a required method with no written
// `throws` carries `throws unknown`.
class ResolvedInterfaceMethod {
    name: string,
    // The full function type (params, return, declared throws).
    function_ty: root.types.Ty,
    // The method's own generic parameters with their resolved bounds.
    generic_params: (root.types.ParamTy, root.types.InterfaceConstraint[])[],
    diagnostics: root.hir_ty.TirTypeError[],
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolve_interface_required_methods @ d9be6853b
// Every required method signature of an interface resolved at its
// declaration site, in declaration order (parallel to
// `InterfaceData.required_methods`).
function resolve_interface_required_methods(
    db: root.hir.Db,
    iface_loc: int,
) -> ResolvedInterfaceMethod[] throws never {
    db.ty_memo.resolve_interface_required_methods.get(db.cycles, iface_loc, () -> {
        let iface = root.hir.interface_data(db, iface_loc);
        let scope = InterfaceDeclScope.new(db, iface_loc);
        iface.required_methods.map((sig) -> {
            let diagnostics: root.hir_ty.TirTypeError[] = [];
            let spec = InterfaceMethodSpec.from_required(iface, sig);
            // The method's own generics join the interface's for lowering;
            // its bounds resolve in the interface scope.
            let method_generics = append_params(scope.generics, spec.generic_param_names());
            let own_params = method_generics.slice(scope.generics.length(), method_generics.length());
            let bounds = copy_bounds(scope.bounds);
            let generic_params: (root.types.ParamTy, root.types.InterfaceConstraint[])[] = [];
            for (let i = 0; i < own_params.length() && i < spec.generics.length(); i += 1) {
                let ifaces = lower_generic_param_interface_bounds(
                    db,
                    spec.bound_refs,
                    spec.generics[i].bounds,
                    scope.pkg_items,
                    scope.ns,
                    method_generics,
                    diagnostics,
                );
                bounds[own_params[i]] = ifaces;
                generic_params.push((own_params[i], ifaces));
            }
            let function_ty = spec.to_function_ty(scope.ctx_with(method_generics, bounds), diagnostics);
            ResolvedInterfaceMethod {
                name: sig.name,
                function_ty: function_ty,
                generic_params: generic_params,
                diagnostics: diagnostics,
            }
        })
    })
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::realize_associated_default @ d9be6853b
// Realize an associated type's default at a concrete receiver: `self_ty`
// for the symbolic `Self`, `interface_args` for the interface's params.
function realize_associated_default(
    default_: root.types.Ty,
    generic_params: root.types.ParamTy[],
    interface_args: root.types.Ty[],
    self_param: root.types.ParamTy,
    self_ty: root.types.Ty,
) -> root.types.Ty throws never {
    let bindings = root.types.bind_type_vars(generic_params, interface_args);
    bindings[self_param] = self_ty;
    root.types.substitute_ty(default_, bindings)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::lower_interface_type_associated_bindings @ d9be6853b
// A required interface's associated bindings at a `requires` site: explicit
// bindings lower in the requiring scope (resolving `Self` onto the requiring
// interface when known), omitted ones fill their defaults eagerly.
function lower_interface_type_associated_bindings(
    ctx: InterfaceTypeAssocLowering,
    diagnostics: root.hir_ty.TirTypeError[],
) -> root.types.AssociatedType[] throws never {
    let self_param = interface_self_param(ctx.db, ctx.iface_loc);
    let iface_params = root.hir_ty.interface_declared_params(ctx.db, ctx.iface_loc);
    let bindings = root.types.bind_type_vars(iface_params, ctx.interface_args);
    for (let param in ctx.outer_bindings.keys()) {
        if (!bindings.has(param)) {
            bindings[param] = ctx.outer_bindings[param];
        }
    }
    // The interface's declared parameter bounds, so a `T.member` projection
    // resolves `T`'s declaring interface.
    let iface_bounds = interface_declared_param_bounds(ctx.db, ctx.iface_loc);
    let iface_qtn = interface_loc_qtn(ctx.db, ctx.iface_loc);
    let self_var = root.types.TyTypeVar { param: self_param };
    let resolved_pins: root.types.AssociatedType[] = [];

    for (let assoc in ctx.iface.associated_types) {
        let binding = ctx.explicit_associated_bindings.find((binding) -> {
            binding.name == assoc.name
        });
        if (binding != null) {
            // The value may project `Self.Assoc` onto the requiring interface,
            // so it lowers through a context that resolves `Self`.
            let self_bound = ctx.self_bound;
            let lowered = if (self_bound != null) {
                let bounds = copy_bounds(iface_bounds);
                bounds[self_param] = [self_bound];
                let generic_params = bindings.keys();
                if (!generic_params.includes(self_param)) {
                    generic_params.push(self_param);
                }
                let scope = LowerScope {
                    db: ctx.db,
                    package_items: ctx.binding_pkg_items,
                    ns_context: ctx.binding_namespace_path,
                    generic_params: generic_params,
                    bounds: bounds,
                    self_ty: root.types.TyTypeVar { param: self_param },
                };
                lower_ref_in(scope, ctx.binding_type_refs, binding.ty, diagnostics)
            } else {
                let scope = LowerScope {
                    db: ctx.db,
                    package_items: ctx.binding_pkg_items,
                    ns_context: ctx.binding_namespace_path,
                    generic_params: bindings.keys(),
                    bounds: iface_bounds,
                    self_ty: null,
                };
                lower_ref_in(scope, ctx.binding_type_refs, binding.ty, diagnostics)
            };
            let ty = root.types.substitute_ty(lowered, bindings);
            let collapsed = collapse_self_assoc_projections(ty, [self_var], iface_qtn, ctx.interface_args, resolved_pins);
            resolved_pins.push(root.types.AssociatedType { name: assoc.name, ty: collapsed });
            continue;
        }
        // Fill the omitted default eagerly at this interface realized on the
        // receiver.
        let found = interface_associated_type_default(ctx.db, ctx.iface_loc, assoc.name);
        if (found == null || iface_qtn == null) {
            continue;
        }
        let self_ty = root.types.TyInterface {
            name: iface_qtn,
            args: ctx.interface_args,
            associated_types: resolved_pins.concat([]),
        };
        let realized = realize_associated_default(found.0, iface_params, ctx.interface_args, self_param, self_ty);
        let ty = root.types.substitute_ty(realized, bindings);
        let collapsed = collapse_self_assoc_projections(ty, [self_var, self_ty], iface_qtn, ctx.interface_args, resolved_pins);
        resolved_pins.push(root.types.AssociatedType { name: assoc.name, ty: collapsed });
    }
    resolved_pins
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::match_ty_patterns @ d9be6853b
// Match several `(pattern, concrete)` pairs into one consistent set of
// bindings: a param occurring in more than one pattern must bind the same
// type in all of them.
function match_ty_patterns(
    pairs: (root.types.Ty, root.types.Ty)[],
    generic_params: root.types.ParamTy[],
    aliases: root.types.AliasEquivCtx,
) -> root.types.TypeBindings? throws never {
    let bindings: root.types.TypeBindings = {};
    for (let pair in pairs) {
        if (!match_ty_pattern_into(pair.0, pair.1, generic_params, aliases, bindings)) {
            return null;
        }
    }
    bindings
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::match_ty_pattern_into @ d9be6853b
// Incrementally match `pattern` against `concrete`, recording type-variable
// bindings into `bindings` (params already bound must match consistently).
// Restructured: Rust's `Option<()>` is `bool`.
function match_ty_pattern_into(
    pattern: root.types.Ty,
    concrete: root.types.Ty,
    generic_params: root.types.ParamTy[],
    aliases: root.types.AliasEquivCtx,
    bindings: root.types.TypeBindings,
) -> bool throws never {
    if let v: root.types.TyTypeVar = pattern {
        if (generic_params.includes(v.param)) {
            return bind_type_var(v.param, concrete, bindings, aliases);
        }
    }
    let pattern_has_vars = root.types.contains_bound_typevar(pattern, generic_params);
    if (!pattern_has_vars && aliases.equivalent(pattern, concrete)) {
        return true;
    }
    // A pattern position whose type variables are all already bound is no
    // longer a pattern: substitute and compare. On mismatch fall through:
    // structural matching may still succeed.
    if (pattern_has_vars) {
        let has_unbound = root.types.contains_ty_where(pattern, (t) -> {
            match (t) {
                let v: root.types.TyTypeVar => {
                    generic_params.includes(v.param) && !bindings.has(v.param)
                },
                _ => false,
            }
        });
        if (!has_unbound && aliases.equivalent(root.types.substitute_ty(pattern, bindings), concrete)) {
            return true;
        }
    }
    let go = (p: root.types.Ty, c: root.types.Ty) -> bool {
        match_ty_pattern_into(p, c, generic_params, aliases, bindings)
    };
    let all = (ps: root.types.Ty[], cs: root.types.Ty[]) -> bool {
        for (let i = 0; i < ps.length(); i += 1) {
            if (!go(ps[i], cs[i])) {
                return false;
            }
        }
        true
    };
    // Each arm that applies answers; null falls through to the alias-aware
    // equivalence fallback.
    let structural: bool? = match (pattern) {
        let p: root.types.TyClass => {
            match (concrete) {
                let c: root.types.TyClass
                    if p.name == c.name && p.args.length() == c.args.length() => {
                    all(p.args, c.args)
                },
                _ => null,
            }
        },
        let p: root.types.TyInterface => {
            match (concrete) {
                let c: root.types.TyInterface
                    if p.name == c.name && p.args.length() == c.args.length() => {
                    if (!all(p.args, c.args)) {
                        return false;
                    }
                    for (let c_pin in c.associated_types) {
                        let p_pin = p.associated_types.find((pin) -> {
                            pin.name == c_pin.name
                        });
                        if (p_pin == null || !go(p_pin.ty, c_pin.ty)) {
                            return false;
                        }
                    }
                    true
                },
                _ => null,
            }
        },
        let p: root.types.TyList => {
            match (concrete) {
                let c: root.types.TyList => go(p.elem, c.elem),
                _ => null,
            }
        },
        let p: root.types.TyTuple => {
            match (concrete) {
                let c: root.types.TyTuple if p.items.length() == c.items.length() => {
                    all(p.items, c.items)
                },
                _ => null,
            }
        },
        let p: root.types.TyMap => {
            match (concrete) {
                let c: root.types.TyMap => go(p.key, c.key) && go(p.value, c.value),
                _ => null,
            }
        },
        let p: root.types.TyFuture => {
            match (concrete) {
                let c: root.types.TyFuture => go(p.value, c.value) && go(p.error, c.error),
                _ => null,
            }
        },
        let p: root.types.TyUnion => {
            match (concrete) {
                let c: root.types.TyUnion if p.members.length() == c.members.length() => {
                    match_union_members(p.members, c.members, generic_params, aliases, bindings)
                },
                _ => null,
            }
        },
        root.types.TyInt => {
            match (concrete) {
                let c: root.types.TyLiteral if c.value is root.base.LiteralInt => true,
                _ => null,
            }
        },
        root.types.TyBigint => {
            match (concrete) {
                let c: root.types.TyLiteral if c.value is root.base.LiteralBigint => true,
                _ => null,
            }
        },
        root.types.TyFloat => {
            match (concrete) {
                let c: root.types.TyLiteral if c.value is root.base.LiteralFloat => true,
                _ => null,
            }
        },
        root.types.TyString => {
            match (concrete) {
                let c: root.types.TyLiteral if c.value is root.base.LiteralString => true,
                _ => null,
            }
        },
        root.types.TyBool => {
            match (concrete) {
                let c: root.types.TyLiteral if c.value is root.base.LiteralBool => true,
                _ => null,
            }
        },
        // An enum variant is a member of its enum's set, so a `for Side`
        // impl (or a blanket `for T`) applies to a `Side.Left` receiver.
        let p: root.types.TyEnum => {
            match (concrete) {
                let c: root.types.TyEnumVariant if p.name == c.name => true,
                _ => null,
            }
        },
        let p: root.types.TyFunction => {
            match (concrete) {
                let c: root.types.TyFunction
                    if p.params.length() == c.params.length()
                    && root.types.zip_all(p.params, c.params, (pp, cp) -> {
                        pp.mode == cp.mode
                    }) => {
                    // Function values are realized: match the param, return
                    // and throws components directly.
                    for (let i = 0; i < p.params.length(); i += 1) {
                        if (!go(p.params[i].ty, c.params[i].ty)) {
                            return false;
                        }
                    }
                    go(p.ret, c.ret) && go(p.throws_, c.throws_)
                },
                _ => null,
            }
        },
        _ => null,
    };
    if (structural != null) {
        return structural;
    }
    aliases.equivalent(pattern, concrete)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::match_union_members @ d9be6853b
// Match union members order-insensitively: each pattern member takes some
// remaining concrete member, backtracking over the choice.
function match_union_members(
    pattern_members: root.types.Ty[],
    concrete_members: root.types.Ty[],
    generic_params: root.types.ParamTy[],
    aliases: root.types.AliasEquivCtx,
    bindings: root.types.TypeBindings,
) -> bool throws never {
    if (pattern_members.length() == 0) {
        return concrete_members.length() == 0;
    }
    let pattern_head = pattern_members[0];
    let pattern_tail = pattern_members.slice(1, pattern_members.length());
    for (let idx = 0; idx < concrete_members.length(); idx += 1) {
        let trial_bindings = root.types.copy_bindings(bindings);
        if (
            !match_ty_pattern_into(pattern_head, concrete_members[idx], generic_params, aliases, trial_bindings)
        ) {
            continue;
        }
        let remaining: root.types.Ty[] = [];
        for (let member_idx = 0; member_idx < concrete_members.length(); member_idx += 1) {
            if (member_idx != idx) {
                remaining.push(concrete_members[member_idx]);
            }
        }
        if (match_union_members(pattern_tail, remaining, generic_params, aliases, trial_bindings)) {
            root.types.assign_bindings(bindings, trial_bindings);
            return true;
        }
    }
    false
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::bind_type_var @ d9be6853b
function bind_type_var(
    param: root.types.ParamTy,
    concrete: root.types.Ty,
    bindings: root.types.TypeBindings,
    aliases: root.types.AliasEquivCtx,
) -> bool throws never {
    let existing = bindings.get(param);
    if (existing != null) {
        return aliases.equivalent(existing, concrete);
    }
    bindings[param] = concrete;
    true
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolve_path_to_interface_identity @ d9be6853b
// Resolve a path type expression to an interface declaration and its
// identity; null when the path doesn't resolve to an interface. The paths
// resolved here are `requires` / `implements` targets: constraint heads.
function resolve_path_to_interface_identity(
    db: root.hir.Db,
    target: root.ast.TypeExpr,
    pkg_items: root.hir.PackageItems,
    current_ns: string[],
) -> ResolvedInterface? throws never {
    let diagnostics: root.hir_ty.TirTypeError[] = [];
    let scope = LowerScope {
        db: db,
        package_items: pkg_items,
        ns_context: current_ns,
        generic_params: [],
        bounds: {},
        self_ty: null,
    };
    let ty = lower_expr_in_at(scope, target, root.hir_ty.TypePosition.ConstraintHead, diagnostics);
    resolved_interface_from_ty(db, ty)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolve_ref_to_interface_identity @ d9be6853b
// The `TypeRef`-arena twin of `resolve_path_to_interface_identity`. Also
// `resolve_ref_to_interface` (read `?.loc`).
function resolve_ref_to_interface_identity(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    target: int,
    pkg_items: root.hir.PackageItems,
    current_ns: string[],
) -> ResolvedInterface? throws never {
    let qtn = resolve_ref_to_interface_name(db, store, target, pkg_items, current_ns)
        ?? return null;
    resolved_interface_from_ty(db, root.types.TyInterface { name: qtn, args: [], associated_types: [] })
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolve_ref_to_interface_name @ d9be6853b
// The interface a written reference names, whichever lane declares it;
// null when the reference does not lower to an interface.
function resolve_ref_to_interface_name(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    target: int,
    pkg_items: root.hir.PackageItems,
    current_ns: string[],
) -> root.types.DeclName? throws never {
    let diagnostics: root.hir_ty.TirTypeError[] = [];
    let scope = LowerScope {
        db: db,
        package_items: pkg_items,
        ns_context: current_ns,
        generic_params: [],
        bounds: {},
        self_ty: null,
    };
    match (
        lower_ref_in(scope, store, target, diagnostics, position = root.hir_ty.TypePosition.ConstraintHead)
    ) {
        let i: root.types.TyInterface => i.name,
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolved_interface_from_ty @ d9be6853b
// Shared tail of the two `resolve_*_to_interface_identity` functions.
function resolved_interface_from_ty(
    db: root.hir.Db,
    ty: root.types.Ty,
) -> ResolvedInterface? throws never {
    let qtn = match (ty) {
        let i: root.types.TyInterface => i.name,
        _ => {
            return null;
        },
    };
    match (root.hir.package_items(db, qtn.pkg).lookup_type(qtn.namespace, qtn.name)) {
        let def: root.hir.DefinitionInterface => ResolvedInterface { loc: def.value, qtn: qtn },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_requires_cycle @ d9be6853b
// If `root_`'s transitive `requires` graph cycles back to it, the name chain
// `[root, ..., root]` witnessing it; else null. The user-facing detector
// (E0118) for the cycle `interface_closure_locs` skips silently.
function interface_requires_cycle(db: root.hir.Db, root_: int) -> string[]? throws never {
    let iface_name = (loc: int) -> string {
        root.hir.interface_data(db, loc).name
    };
    let required_locs = (loc: int) -> int[] {
        let iface = root.hir.interface_data(db, loc);
        let pkg = root.hir.file_package(db, db.interface_locs.get(loc).file);
        let pkg_items = root.hir.package_items(db, pkg.root_id);
        iface.requires_.filter_map((p) -> {
            resolve_ref_to_interface_identity(db, iface.type_refs, p, pkg_items, pkg.namespace_path)?.loc
        })
    };
    let root_name = iface_name(root_);
    // Frontier item: (interface to expand, the name chain from `root_` to it).
    let frontier: (int, string[])[] = required_locs(root_).map((p) -> {
        (p, [root_name, iface_name(p)])
    });
    let visited: map<int, bool> = {};
    while let item: (int, string[]) = frontier.pop() {
        let (let loc, let chain) = item;
        if (loc == root_) {
            return chain;
        }
        if (visited.has(loc)) {
            continue;
        }
        visited[loc] = true;
        for (let p in required_locs(loc)) {
            frontier.push((p, chain.concat([iface_name(p)])));
        }
    }
    null
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_closure_locs @ d9be6853b
// Every interface in the transitive `requires` closure of `root_iface`
// (itself included), in BFS order. Cycles are skipped silently (E0118 is
// reported elsewhere).
function interface_closure_locs(db: root.hir.Db, root_iface: int) -> int[] throws never {
    let out: int[] = [];
    let seen: map<int, bool> = {};
    let queue: int[] = [root_iface];
    let head = 0;
    while (head < queue.length()) {
        let loc = queue[head];
        head += 1;
        if (seen.has(loc)) {
            continue;
        }
        seen[loc] = true;
        out.push(loc);
        let iface = root.hir.interface_data(db, loc);
        let pkg_info = root.hir.file_package(db, db.interface_locs.get(loc).file);
        let parent_pkg_items = root.hir.package_items(db, pkg_info.root_id);
        for (let parent in iface.requires_) {
            let parent_loc = resolve_ref_to_interface_identity(db, iface.type_refs, parent, parent_pkg_items, pkg_info.namespace_path)?.loc;
            if (parent_loc != null) {
                queue.push(parent_loc);
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interfaces_declaring_associated_type @ d9be6853b
// Every interface reachable from `roots` (each root plus its `requires`
// closure) that declares an associated type named `member`. `roots` is a
// conjunction, so deduplication is shared across all of them. Order is
// stable: roots in the order given, each closure in BFS order.
function interfaces_declaring_associated_type(
    db: root.hir.Db,
    roots: int[],
    member: string,
) -> int[] throws never {
    let out: int[] = [];
    let seen: map<int, bool> = {};
    for (let root_ in roots) {
        for (let loc in interface_closure_locs(db, root_)) {
            if (seen.has(loc)) {
                continue;
            }
            seen[loc] = true;
            if (
                root.hir.interface_data(db, loc).associated_types.some((assoc) -> {
                    assoc.name == member
                })
            ) {
                out.push(loc);
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_closure_locs_with_args_and_assoc @ d9be6853b
// The transitive `requires` closure of `root_iface`, each interface carried
// with its realized generic arguments and associated-type bindings.
// `fill_associated_defaults` false keeps an overridable associated type a
// symbolic projection (callers resolving through a rigid `Self`).
function interface_closure_locs_with_args_and_assoc(
    db: root.hir.Db,
    root_iface: int,
    root_args: root.types.Ty[],
    root_associated_bindings: root.types.AssociatedType[],
    fill_associated_defaults: bool,
) -> InterfaceClosureEntry[] throws never {
    let out: InterfaceClosureEntry[] = [];
    let seen: InterfaceClosureEntry[] = [];
    let queue: InterfaceClosureQueueEntry[] = [
        InterfaceClosureQueueEntry {
            loc: root_iface,
            args: root_args,
            associated_bindings: root_associated_bindings,
            ancestors: {},
        },
    ];
    let head = 0;
    while (head < queue.length()) {
        let entry = queue[head];
        head += 1;
        let loc = entry.loc;
        let args = entry.args;
        if (entry.ancestors.has(loc)) {
            continue;
        }
        let iface = root.hir.interface_data(db, loc);
        let pkg_info = root.hir.file_package(db, db.interface_locs.get(loc).file);
        let parent_pkg_items = root.hir.package_items(db, pkg_info.root_id);
        let diags: root.hir_ty.TirTypeError[] = [];
        let associated_bindings = complete_interface_associated_bindings_from_tys(db, loc, iface, args, entry.associated_bindings, fill_associated_defaults);
        let closure_entry = InterfaceClosureEntry { loc: loc, args: args, associated_bindings: associated_bindings };
        if (seen.includes(closure_entry)) {
            continue;
        }
        seen.push(closure_entry);
        out.push(closure_entry);
        let child_ancestors: map<int, bool> = {};
        for (let ancestor in entry.ancestors.keys()) {
            child_ancestors[ancestor] = true;
        }
        child_ancestors[loc] = true;

        // Only the declared params bind: associated types are projection-only
        // (`Self.X`), resolved through `self_bound`'s pins below.
        let iface_params = root.hir_ty.interface_declared_params(db, loc);
        let bindings = root.types.bind_type_vars(iface_params, args);

        // This interface as a constraint (its associated types pinned to the
        // realized bindings), so a required interface's `Item = Self.Item`
        // resolves `Self.Item` here.
        let qtn = interface_loc_qtn(db, loc);
        let self_bound = if (qtn != null) {
            root.types.InterfaceConstraint {
                name: qtn,
                generics: args,
                associated_types: associated_bindings.concat([]).sort_by_key((pin) -> {
                    pin.name
                }),
            }
        } else {
            null
        };
        // The requiring interface's declared parameter bounds, so a
        // `T.member` projection in a parent's arguments resolves.
        let iface_bounds = interface_declared_param_bounds(db, loc);

        for (let parent in iface.requires_) {
            let parent_loc = resolve_ref_to_interface_identity(db, iface.type_refs, parent, parent_pkg_items, pkg_info.namespace_path)?.loc;
            if (parent_loc == null) {
                continue;
            }
            let parent_path = match (iface.type_refs.get(parent).kind) {
                let path: root.hir.TypeRefKindPath => path,
                _ => null,
            };
            let arg_diags: root.hir_ty.TirTypeError[] = [];
            let parent_args: root.types.Ty[] = if (parent_path != null) {
                parent_path.generic_args.map((arg) -> {
                    let scope = LowerScope {
                        db: db,
                        package_items: parent_pkg_items,
                        ns_context: pkg_info.namespace_path,
                        generic_params: bindings.keys(),
                        bounds: iface_bounds,
                        self_ty: null,
                    };
                    root.types.substitute_ty(
                        lower_ref_in(scope, iface.type_refs, arg, arg_diags),
                        bindings,
                    )
                })
            } else {
                []
            };
            let parent_explicit_assoc: root.hir.AssociatedTypeBindingRef[] = if (parent_path != null) {
                parent_path.associated_type_bindings
            } else {
                []
            };
            let parent_assoc = lower_interface_type_associated_bindings(
                InterfaceTypeAssocLowering {
                    db: db,
                    iface_loc: parent_loc,
                    iface: root.hir.interface_data(db, parent_loc),
                    interface_args: parent_args,
                    explicit_associated_bindings: parent_explicit_assoc,
                    binding_type_refs: iface.type_refs,
                    binding_pkg_items: parent_pkg_items,
                    binding_namespace_path: pkg_info.namespace_path,
                    outer_bindings: bindings,
                    self_bound: self_bound,
                },
                diags,
            );
            queue.push(
                InterfaceClosureQueueEntry {
                    loc: parent_loc,
                    args: parent_args,
                    associated_bindings: parent_assoc,
                    ancestors: child_ancestors,
                },
            );
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::type_generic_bound_errors @ d9be6853b
// Every generic-argument bound violation inside the written type `ty`
// (rustc's wfcheck for ADT instantiations). `scope_bounds` is the enclosing
// scope's param env. Aliases expand cycle-guarded.
function type_generic_bound_errors(
    db: root.hir.Db,
    scope_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    ty: root.types.LoweringTy,
) -> root.hir_ty.TirTypeError[] throws never {
    let facts = root.hir_ty.Facts.with_bounds(db, copy_bounds(scope_bounds));
    let errors: root.hir_ty.TirTypeError[] = [];
    collect_type_generic_bound_errors(db, facts, ty, {}, errors);
    errors
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::map_key_is_hashable @ d9be6853b
// Whether a map key type implements `baml.Hash`. An error-carrying key
// passes (its own diagnostic covers it).
function map_key_is_hashable(
    db: root.hir.Db,
    facts: root.hir_ty.Facts,
    key: root.types.Ty,
) -> bool throws never {
    if (
        root.types.contains_ty_where(key, (t) -> {
            t is root.types.TyError
        })
    ) {
        return true;
    }
    let baml_root = root.hir.lang_roots(db).get(root.base.LangPackage.Baml)
        ?? return false;
    let bound = root.types.InterfaceConstraint {
        name: root.types.DeclName { pkg: baml_root, namespace: [], name: "Hash" },
        generics: [],
        associated_types: [],
    };
    normalized_arg_implements_bound(facts, facts.normalize(key), bound)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::collect_type_generic_bound_errors @ d9be6853b
function collect_type_generic_bound_errors(
    db: root.hir.Db,
    facts: root.hir_ty.Facts,
    ty: root.types.LoweringTy,
    seen_aliases: map<root.types.DeclName, bool>,
    errors: root.hir_ty.TirTypeError[],
) -> void throws never {
    let go = (t: root.types.LoweringTy) -> void {
        collect_type_generic_bound_errors(db, facts, t, seen_aliases, errors);
    };
    match (ty) {
        let c: root.types.LoweringTyClass => {
            c.args.for_each(go);
            // The head's declared bounds: its source declaration's, or its
            // served package's row's.
            match (root.hir_ty.definition_of(db, c.name)) {
                let def: root.hir.DefinitionClass => {
                    let params = root.hir_ty.class_generic_frame(db, def.value);
                    let declared = root.hir_ty.class_generic_bounds(db, def.value);
                    check_head_args(db, facts, params, declared, c.args, errors);
                },
                _ => {
                    let class_ = root.hir_ty.mounted_class_loc(db, c.name);
                    if (class_ != null) {
                        let row = root.hir_ty.extern_class_row(db, class_);
                        let declared = row_param_bounds(row.generic_params, row.generic_param_bounds);
                        check_head_args(db, facts, row.generic_params, declared, c.args, errors);
                    }
                },
            }
        },
        let i: root.types.LoweringTyInterface => {
            i.args.for_each(go);
            for (let pin in i.associated_types) {
                go(pin.ty);
            }
            match (root.hir_ty.definition_of(db, i.name)) {
                let def: root.hir.DefinitionInterface => {
                    let params = root.hir_ty.interface_declared_params(db, def.value);
                    let declared = interface_declared_param_bounds(db, def.value);
                    check_head_args(db, facts, params, declared, i.args, errors);
                },
                // The served-row branch is not ported (header).
                _ => {},
            }
        },
        let l: root.types.LoweringTyList => go(l.elem),
        let m: root.types.LoweringTyMap => {
            go(m.key);
            go(m.value);
        },
        let u: root.types.LoweringTyUnion => u.members.for_each(go),
        let t: root.types.LoweringTyTuple => t.items.for_each(go),
        let f: root.types.LoweringTyFunction => {
            for (let param in f.params) {
                go(param.ty);
            }
            go(f.ret);
            go(f.throws_);
        },
        let f: root.types.LoweringTyFuture => {
            go(f.value);
            go(f.error);
        },
        let a: root.types.TyTypeAlias => {
            if (seen_aliases.has(a.name)) {
                return;
            }
            seen_aliases[a.name] = true;
            let expanded = facts.alias_def(a.name);
            if (expanded != null) {
                // Alias definitions are finalized facts; the walk's vocabulary
                // is the wider member.
                go(root.types.widen_ty_to_lowering_ty(expanded));
            }
            seen_aliases.delete(a.name);
        },
        _ => {},
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::row_param_bounds @ d9be6853b
// A served row's per-parameter bounds in the walk's keyed form.
function row_param_bounds(
    params: root.types.ParamTy[],
    bounds: root.types.InterfaceConstraint[][],
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    let out: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
    for (let i = 0; i < params.length() && i < bounds.length(); i += 1) {
        out[params[i]] = bounds[i];
    }
    out
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::check_head_args @ d9be6853b
// One head's arguments against its declared bounds, each conjunct a
// separate requirement. Bounds may reference sibling params, so the head's
// own bindings substitute through them first. A hole-carrying argument is
// judged after instantiation, not here.
function check_head_args(
    db: root.hir.Db,
    facts: root.hir_ty.Facts,
    params: root.types.ParamTy[],
    declared: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    args: root.types.LoweringTy[],
    errors: root.hir_ty.TirTypeError[],
) -> void throws never {
    if (params.length() == 0 || args.length() == 0) {
        return;
    }
    let closed: root.types.Ty?[] = args.map((arg) -> {
        root.types.narrow_lowering_ty_to_ty(arg) catch (e) {
            root.types.NarrowError => null,
        }
    });
    let closed_params: root.types.ParamTy[] = [];
    let closed_args: root.types.Ty[] = [];
    for (let i = 0; i < params.length() && i < closed.length(); i += 1) {
        let arg = closed[i];
        if (arg != null) {
            closed_params.push(params[i]);
            closed_args.push(arg);
        }
    }
    let bindings = root.types.bind_type_vars(closed_params, closed_args);
    let pool = db.ty_memo.pool;
    for (let index = 0; index < params.length(); index += 1) {
        let actual = closed.at(index) ?? null;
        if (actual == null) {
            continue;
        }
        for (let declared_bound in declared.get(params[index]) ?? []) {
            let bound_ty = root.types.TyInterface {
                name: declared_bound.name,
                args: declared_bound.generics,
                associated_types: declared_bound.associated_types,
            };
            let bound = root.types.as_interface(root.types.substitute_ty(bound_ty, bindings));
            if (bound == null) {
                continue;
            }
            let arg = facts.normalize(actual);
            let structural = root.hir_ty.structural_interface(db, bound.name);
            let admissible = root.hir_ty.is_structural_interface(
                db,
                root.types.infer_interface_from_constraint(pool, bound),
            )
                || (
                    structural != null
                        && root.types.structural_interface_is_conditional(structural)
                        && normalized_arg_implements_bound(facts, arg, bound)
                )
                || root.types.is_concrete(arg)
                || arg is root.types.TyTypeVar
                || arg is root.types.TyAssociatedTypeProjection
                || arg is root.types.TyError;
            if (!admissible) {
                errors.push(
                    root.hir_ty.TirTypeErrorBoundedTypeArgNotConcrete {
                        arg: actual,
                        bound: [bound],
                    },
                );
            } else if (!normalized_arg_implements_bound(facts, arg, bound)) {
                errors.push(
                    root.hir_ty.TirTypeErrorTypeMismatch {
                        expected: root.types.TyInterface {
                            name: bound.name,
                            args: bound.generics,
                            associated_types: bound.associated_types,
                        },
                        got: actual,
                    },
                );
            }
        }
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::MemberNamespace @ d9be6853b
// Which member namespace a projection reads.
enum MemberNamespace {
    // Associated types, written in type position.
    Type,
    // Fields and methods, written in value position.
    Value,
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::ValueMemberKind @ d9be6853b
// What an interface declares under a name in the value namespace.
enum ValueMemberKind {
    Field,
    Method,
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::InterfaceMemberKind @ d9be6853b
// What an interface declares under a name, across both namespaces.
type InterfaceMemberKind = InterfaceMemberKindAssociatedType | InterfaceMemberKindValue;

class InterfaceMemberKindAssociatedType {
}

class InterfaceMemberKindValue {
    value: ValueMemberKind,
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::ProjectionLowering @ d9be6853b
// A lowered projection (the canonical triple when determined, else
// `Error`) and its determination diagnostics.
class ProjectionLowering {
    ty: root.types.Ty,
    diagnostics: root.hir_ty.TirTypeError[],
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::Determination @ d9be6853b
// The outcome of resolving which interface declares a projection's member.
// Each namespace phrases its own diagnostics from it.
type Determination = DeterminationDetermined
    | DeterminationUndeclared
    | DeterminationAmbiguous
    | DeterminationSubjectDoesNotImplementQualifier
    | DeterminationInvalidBase
    | DeterminationPoisoned;

class DeterminationDetermined {
    value: root.types.InterfaceConstraint,
}

class DeterminationUndeclared {
    container: root.hir_ty.AssocContainer,
}

class DeterminationAmbiguous {
    value: root.types.InterfaceConstraint[],
}

class DeterminationSubjectDoesNotImplementQualifier {
    subject: root.types.Ty,
    qualifier: root.types.InterfaceConstraint,
}

class DeterminationInvalidBase {
}

class DeterminationPoisoned {
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::projection_poisoned @ d9be6853b
// Whether `ty` already carries an upstream error, so a projection over it
// must not emit a fresh diagnostic.
function projection_poisoned(ty: root.types.Ty) -> bool throws never {
    ty is root.types.TyError
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::determine_member_interface @ d9be6853b
// Determine which interface declares `member` for `base`, in `ns`.
// `scope_bounds` is the enclosing scope's plain param env.
function determine_member_interface(
    db: root.hir.Db,
    viewer: int,
    scope_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    base: root.types.Ty,
    explicit_interface: root.types.Ty?,
    member: string,
    ns: MemberNamespace,
) -> (Determination, root.hir_ty.TirTypeError[]) throws never {
    let facts = root.hir_ty.Facts.with_bounds(db, copy_bounds(scope_bounds));
    determine_member_interface_with_facts(db, viewer, facts, base, explicit_interface, member, ns)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::determine_member_interface_with_facts @ d9be6853b
// `determine_member_interface` against an already-built fact oracle. A
// written qualifier that is not an interface is rejected here.
function determine_member_interface_with_facts(
    db: root.hir.Db,
    viewer: int,
    facts: root.hir_ty.Facts,
    base: root.types.Ty,
    explicit_interface: root.types.Ty?,
    member: string,
    ns: MemberNamespace,
) -> (Determination, root.hir_ty.TirTypeError[]) throws never {
    let explicit: root.types.InterfaceConstraint? = null;
    if (explicit_interface != null) {
        let iface_ty = projection_expand_aliases(facts, explicit_interface);
        let interface_ = root.types.as_interface(iface_ty);
        if (interface_ == null) {
            if (projection_poisoned(iface_ty)) {
                return (DeterminationPoisoned {}, []);
            }
            return (DeterminationPoisoned {}, [root.hir_ty.TirTypeErrorNonInterfaceProjectionQualifier {}]);
        }
        explicit = interface_;
    }
    (determine_interface(db, viewer, facts, base, explicit, member, ns), [])
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::lower_projection @ d9be6853b
// Lower `base.member` or `(base as explicit).member` to its canonical
// projection: the type-namespace half of `determine_member_interface`.
function lower_projection(
    db: root.hir.Db,
    viewer: int,
    scope_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    base: root.types.Ty,
    explicit_interface: root.types.Ty?,
    member: string,
) -> ProjectionLowering throws never {
    let (let determination, let diagnostics) = determine_member_interface(db, viewer, scope_bounds, base, explicit_interface, member, MemberNamespace.Type);
    let ty: root.types.Ty = match (determination) {
        let d: DeterminationDetermined => {
            let pinned = d.value.associated_types.find((pin) -> {
                pin.name == member
            });
            if (pinned != null) {
                pinned.ty
            } else {
                root.types.TyAssociatedTypeProjection {
                    base: base,
                    interface_: d.value,
                    member: member,
                }
            }
        },
        let d: DeterminationUndeclared => {
            diagnostics.push(
                root.hir_ty.TirTypeErrorUnknownAssociatedType {
                    member: member,
                    container: d.container,
                },
            );
            root.types.TyError {}
        },
        let d: DeterminationAmbiguous => {
            diagnostics.push(
                root.hir_ty.TirTypeErrorAmbiguousAssociatedTypeProjection {
                    member: member,
                    candidates: d.value.map((iface) -> {
                        iface.name
                    }),
                },
            );
            root.types.TyError {}
        },
        let d: DeterminationSubjectDoesNotImplementQualifier => {
            diagnostics.push(
                root.hir_ty.TirTypeErrorTypeDoesNotImplementInterface {
                    value_type: d.subject,
                    interface_: root.types.TyInterface {
                        name: d.qualifier.name,
                        args: d.qualifier.generics,
                        associated_types: d.qualifier.associated_types,
                    },
                },
            );
            root.types.TyError {}
        },
        // A subject that can declare no associated type at all: the member
        // is unknown for it.
        DeterminationInvalidBase => {
            diagnostics.push(
                root.hir_ty.TirTypeErrorUnknownAssociatedType {
                    member: member,
                    container: root.hir_ty.AssocContainerTy { value: base },
                },
            );
            root.types.TyError {}
        },
        // An already-poisoned subject was reported where it was lowered.
        DeterminationPoisoned => root.types.TyError {},
    };
    ProjectionLowering { ty: ty, diagnostics: diagnostics }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::determine_interface @ d9be6853b
// The mechanism is fixed by the base's kind: a type variable searches its
// bound conjunction's closures, an interface existential its own, a
// concrete type its visible impls, a chained projection the inner member's
// declared bound.
function determine_interface(
    db: root.hir.Db,
    viewer: int,
    facts: root.hir_ty.Facts,
    base: root.types.Ty,
    explicit: root.types.InterfaceConstraint?,
    member: string,
    ns: MemberNamespace,
) -> Determination throws never {
    // An explicit qualifier must declare `member` directly: `requires` is a
    // bound, not inheritance.
    if (explicit != null && !interface_declares_member(db, explicit.name, member, ns)) {
        return DeterminationUndeclared {
            container: root.hir_ty.AssocContainerInterface { value: explicit.name },
        };
    }
    let expanded = projection_expand_aliases(facts, base);
    match (expanded) {
        let i: root.types.TyInterface => {
            let root_ = root.types.InterfaceConstraint {
                name: i.name,
                generics: i.args,
                associated_types: i.associated_types.concat([]).sort_by_key((pin) -> {
                    pin.name
                }),
            };
            let undeclared = root.hir_ty.AssocContainerInterface { value: root_.name };
            let roots = [root_];
            append_structural_roots(db, roots);
            resolve_via_roots(db, viewer, facts, roots, explicit, member, undeclared, expanded, true, ns)
        },
        let v: root.types.TyTypeVar => {
            let bounds = facts.type_var_bound(v.param).concat([]);
            let undeclared: root.hir_ty.AssocContainer = if (bounds.length() != 0) {
                root.hir_ty.AssocContainerInterface { value: bounds[0].name }
            } else {
                root.hir_ty.AssocContainerTypeVar { value: v.param.name }
            };
            append_structural_roots(db, bounds);
            if (bounds.length() == 0) {
                if (explicit != null) {
                    DeterminationSubjectDoesNotImplementQualifier {
                        subject: expanded,
                        qualifier: explicit,
                    }
                } else {
                    DeterminationUndeclared {
                        container: root.hir_ty.AssocContainerTypeVar { value: v.param.name },
                    }
                }
            } else {
                resolve_via_roots(db, viewer, facts, bounds, explicit, member, undeclared, expanded, false, ns)
            }
        },
        root.types.TyClass
            | root.types.TyEnum
            | root.types.TyTypeAlias
            | root.types.TyList
            | root.types.TyMap
            | root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.TyLiteral
            | root.types.TyUnknown
            | root.types.TyUnion
            | root.types.TyFunction
            | root.types.TyFuture
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst
            | root.types.TyEnumVariant =>
        {
            if (explicit == null) {
                determine_concrete(db, viewer, facts, expanded, member, ns)
            } else {
                let realized = concrete_realized_interface(db, expanded, explicit);
                if (realized != null) {
                    DeterminationDetermined { value: realized }
                } else {
                    DeterminationSubjectDoesNotImplementQualifier {
                        subject: expanded,
                        qualifier: explicit,
                    }
                }
            }
        },
        let p: root.types.TyAssociatedTypeProjection => {
            let bound = root.hir_ty.realized_assoc_bound_plain(db, p.interface_, p.base, p.member);
            let root_ = if (bound != null) {
                root.types.as_interface(bound)
            } else {
                null
            };
            let container: root.hir_ty.AssocContainer = if (root_ != null) {
                root.hir_ty.AssocContainerInterface { value: root_.name }
            } else {
                root.hir_ty.AssocContainerTy { value: expanded }
            };
            let roots: root.types.InterfaceConstraint[] = if (root_ != null) {
                [root_]
            } else {
                []
            };
            append_structural_roots(db, roots);
            resolve_via_roots(db, viewer, facts, roots, explicit, member, container, expanded, false, ns)
        },
        root.types.TyError => DeterminationPoisoned {},
        _ => {
            if (explicit != null) {
                DeterminationSubjectDoesNotImplementQualifier {
                    subject: expanded,
                    qualifier: explicit,
                }
            } else {
                DeterminationInvalidBase {}
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::append_structural_roots @ d9be6853b
function append_structural_roots(
    db: root.hir.Db,
    roots: root.types.InterfaceConstraint[],
) -> void throws never {
    let pool = db.ty_memo.pool;
    for (let reference in root.hir_ty.structural_interface_roots(db)) {
        let interface_ = root.types.interface_try_from(pool, reference) catch (e) {
            root.types.OpenTy => baml.sys.panic("structural interface roots are closed"),
        };
        if (!roots.includes(interface_)) {
            roots.push(interface_);
        }
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolve_via_roots @ d9be6853b
// `fill_defaults`: an existential root denotes one complete instantiation,
// so its closure fills defaulted members; a rigid root (a bound, a chained
// projection's declared bound) leaves them unpinned.
function resolve_via_roots(
    db: root.hir.Db,
    viewer: int,
    facts: root.hir_ty.Facts,
    roots: root.types.InterfaceConstraint[],
    explicit: root.types.InterfaceConstraint?,
    member: string,
    undeclared: root.hir_ty.AssocContainer,
    subject: root.types.Ty,
    fill_defaults: bool,
    ns: MemberNamespace,
) -> Determination throws never {
    if (explicit != null) {
        let realized = realize_qualifier_through_roots(db, facts, roots, explicit, fill_defaults);
        return if (realized != null) {
            DeterminationDetermined { value: realized }
        } else {
            DeterminationSubjectDoesNotImplementQualifier { subject: subject, qualifier: explicit }
        };
    }
    let result = resolve_through_roots(db, roots, member, undeclared, fill_defaults, ns);
    match (result) {
        let ambiguous: DeterminationAmbiguous => {
            let candidates = ambiguous.value;
            let pool = db.ty_memo.pool;
            // A bound's `requires` closure can reach `baml.Concrete`; its
            // `type` yields.
            root.hir_ty.demote_concrete_type_member(root.hir.lang_roots(db), member, candidates, (
                iface,
            ) -> {
                iface.name
            });
            root.hir_ty.prefer_explicit_members(db, viewer, facts, pool.from_plain(subject), candidates, (
                iface,
            ) -> {
                root.types.infer_interface_from_constraint(pool, iface)
            });
            if (candidates.length() == 1) {
                DeterminationDetermined { value: candidates[0] }
            } else {
                DeterminationAmbiguous { value: candidates }
            }
        },
        _ => result,
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::realize_qualifier_through_roots @ d9be6853b
// The written qualifier proven through the roots' closures: the written
// generics ride, the candidate supplies what the qualifier left unwritten.
function realize_qualifier_through_roots(
    db: root.hir.Db,
    facts: root.hir_ty.Facts,
    roots: root.types.InterfaceConstraint[],
    qualifier: root.types.InterfaceConstraint,
    fill_defaults: bool,
) -> root.types.InterfaceConstraint? throws never {
    for (let root_ in roots) {
        // A mounted interface has no loc, but its exported row is still a
        // complete root for qualifier proof.
        if (root.hir_ty.mounted_type_row(db, root_.name) is root.hir_ty.ExportedTypeInterface) {
            let subject = root.types.TyInterface {
                name: root_.name,
                args: root_.generics,
                associated_types: root_.associated_types,
            };
            let candidates = [root_].concat(
                root.hir_ty.direct_requires_closure_plain(
                    db,
                    root_,
                    subject,
                    root.hir_ty.REQUIRES_CLOSURE_FUEL,
                ),
            );
            for (let candidate in candidates) {
                if (candidate.name != qualifier.name) {
                    continue;
                }
                let completed = complete_qualifier_candidate_associated_bindings(db, candidate, fill_defaults);
                if (written_qualifier_proven_by(facts, qualifier, completed)) {
                    return root.types.InterfaceConstraint {
                        name: completed.name,
                        generics: qualifier.generics,
                        associated_types: completed.associated_types,
                    };
                }
            }
            continue;
        }
        let root_loc = projection_interface_loc(db, root_.name);
        if (root_loc == null) {
            continue;
        }
        for (
            let entry in interface_closure_locs_with_args_and_assoc(db, root_loc, root_.generics, root_.associated_types, fill_defaults)
        ) {
            let qtn = interface_loc_qtn(db, entry.loc);
            if (qtn != null && qtn == qualifier.name) {
                let candidate = root.types.InterfaceConstraint {
                    name: qtn,
                    generics: entry.args,
                    associated_types: entry.associated_bindings.concat([]).sort_by_key((pin) -> {
                        pin.name
                    }),
                };
                if (written_qualifier_proven_by(facts, qualifier, candidate)) {
                    return root.types.InterfaceConstraint {
                        name: candidate.name,
                        generics: qualifier.generics,
                        associated_types: candidate.associated_types,
                    };
                }
            }
        }
    }
    null
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::complete_qualifier_candidate_associated_bindings @ d9be6853b
// Fill an existential qualifier candidate's omitted associated defaults in
// declaration order. Rigid roots pass `fill_defaults = false`: their
// implementor may override a default.
function complete_qualifier_candidate_associated_bindings(
    db: root.hir.Db,
    candidate: root.types.InterfaceConstraint,
    fill_defaults: bool,
) -> root.types.InterfaceConstraint throws never {
    if (!fill_defaults) {
        return candidate;
    }
    let row = match (root.hir_ty.mounted_type_row(db, candidate.name)) {
        let r: root.hir_ty.ExportedTypeInterface => r,
        _ => {
            let loc = projection_interface_loc(db, candidate.name)
                ?? return candidate;
            let data = root.hir.interface_data(db, loc);
            return root.types.InterfaceConstraint {
                name: candidate.name,
                generics: candidate.generics,
                associated_types: complete_interface_associated_bindings_from_tys(db, loc, data, candidate.generics, candidate.associated_types, true),
            };
        },
    };

    let generic_bindings = root.types.bind_type_vars(row.generic_params, candidate.generics);
    let self_var = root.types.TyTypeVar { param: row.self_param };
    let resolved_pins: root.types.AssociatedType[] = [];
    for (let associated_type in row.associated_types) {
        let self_ty = root.types.TyInterface {
            name: candidate.name,
            args: candidate.generics,
            associated_types: resolved_pins.concat([]),
        };
        let written = candidate.associated_types.find((pin) -> {
            pin.name == associated_type.name
        });
        let default_ = associated_type.default_;
        let ty: root.types.Ty? = if (written != null) {
            root.types.substitute_ty(written.ty, generic_bindings)
        } else if (default_ != null) {
            realize_associated_default(default_, row.generic_params, candidate.generics, row.self_param, self_ty)
        } else {
            null
        };
        if (ty == null) {
            continue;
        }
        let collapsed = collapse_self_assoc_projections(ty, [self_var, self_ty], candidate.name, candidate.generics, resolved_pins);
        resolved_pins.push(root.types.AssociatedType { name: associated_type.name, ty: collapsed });
    }
    root.types.InterfaceConstraint {
        name: candidate.name,
        generics: candidate.generics,
        associated_types: resolved_pins,
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::written_qualifier_proven_by @ d9be6853b
// Whether a bound-closure `candidate` proves the written qualifier: every
// written position equivalent (a rigid variable only to itself) and every
// written associated pin matched. Nothing fails open.
function written_qualifier_proven_by(
    facts: root.hir_ty.Facts,
    written: root.types.InterfaceConstraint,
    candidate: root.types.InterfaceConstraint,
) -> bool throws never {
    if (written.generics.length() != candidate.generics.length()) {
        return false;
    }
    if (
        !root.types.zip_all(written.generics, candidate.generics, (w, real) -> {
            facts.equivalent(w, real)
        })
    ) {
        return false;
    }
    written.associated_types.every((written_pin) -> {
        candidate.associated_types.some((real_pin) -> {
            real_pin.name == written_pin.name && facts.equivalent(written_pin.ty, real_pin.ty)
        })
    })
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::resolve_through_roots @ d9be6853b
// Unqualified: search every root. A root that declares `member` directly
// shadows its own closure; declarers dedupe by realized identity.
function resolve_through_roots(
    db: root.hir.Db,
    roots: root.types.InterfaceConstraint[],
    member: string,
    undeclared: root.hir_ty.AssocContainer,
    fill_defaults: bool,
    ns: MemberNamespace,
) -> Determination throws never {
    let declarers: root.types.InterfaceConstraint[] = [];
    let push = (interface_: root.types.InterfaceConstraint) -> void {
        if (!declarers.includes(interface_)) {
            declarers.push(interface_);
        }
    };
    for (let root_ in roots) {
        if (interface_declares_member(db, root_.name, member, ns)) {
            push(root_);
            continue;
        }
        if (root.hir_ty.mounted_type_row(db, root_.name) != null) {
            let subject = root.types.TyInterface {
                name: root_.name,
                args: root_.generics,
                associated_types: root_.associated_types,
            };
            for (
                let inherited in root.hir_ty.direct_requires_closure_plain(
                    db,
                    root_,
                    subject,
                    root.hir_ty.REQUIRES_CLOSURE_FUEL,
                )
            ) {
                if (interface_declares_member(db, inherited.name, member, ns)) {
                    push(inherited);
                }
            }
            continue;
        }
        let root_loc = projection_interface_loc(db, root_.name);
        if (root_loc == null) {
            continue;
        }
        for (
            let entry in interface_closure_locs_with_args_and_assoc(db, root_loc, root_.generics, root_.associated_types, fill_defaults)
        ) {
            if (!interface_declares_member_at(db, entry.loc, member, ns)) {
                continue;
            }
            let qtn = interface_loc_qtn(db, entry.loc);
            if (qtn == null) {
                continue;
            }
            push(
                root.types.InterfaceConstraint {
                    name: qtn,
                    generics: entry.args,
                    associated_types: entry.associated_bindings.concat([]).sort_by_key((pin) -> {
                        pin.name
                    }),
                },
            );
        }
    }
    match (declarers.length()) {
        0 => DeterminationUndeclared { container: undeclared },
        1 => DeterminationDetermined { value: declarers[0] },
        _ => DeterminationAmbiguous { value: declarers },
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::determine_concrete @ d9be6853b
// A concrete base's projection through its visible impls; the most-derived
// interface shadows one it transitively requires.
function determine_concrete(
    db: root.hir.Db,
    viewer: int,
    facts: root.hir_ty.Facts,
    base: root.types.Ty,
    member: string,
    ns: MemberNamespace,
) -> Determination throws never {
    let pool = db.ty_memo.pool;
    let interned = root.hir_ty.try_interned_ty(pool, base)
        ?? return DeterminationPoisoned {};
    let declarers: root.types.InterfaceConstraint[] = [];
    let views = root.hir_ty.impl_views_for_type(db, viewer, base, (name) -> {
        interface_declares_member(db, name, member, ns)
    });
    for (let interface_ in views) {
        if (
            interface_declares_member(db, interface_.name, member, ns)
                && !declarers.includes(interface_)
        ) {
            declarers.push(interface_);
        }
    }
    if (declarers.length() > 1) {
        let heads = declarers.map((iface) -> {
            root.types.infer_interface_new(
                iface.name,
                iface.generics.map((ty) -> {
                    pool.from_plain(ty)
                }),
                [],
            )
        });
        let kept: root.types.InterfaceConstraint[] = [];
        for (let i = 0; i < heads.length(); i += 1) {
            let head = heads[i];
            let shadowed = heads.some((other) -> {
                other.name != head.name
                    && root.hir_ty.interface_requires(db, other, head, interned, 8)
            });
            if (!shadowed) {
                kept.push(declarers[i]);
            }
        }
        declarers = kept;
    }
    // `baml.Concrete` declares `type` for every concrete type; any other
    // interface declaring the name keeps it.
    root.hir_ty.demote_concrete_type_member(root.hir.lang_roots(db), member, declarers, (iface) -> {
        iface.name
    });
    root.hir_ty.prefer_explicit_members(db, viewer, facts, interned, declarers, (iface) -> {
        root.types.infer_interface_from_constraint(pool, iface)
    });
    match (declarers.length()) {
        0 => {
            DeterminationUndeclared {
                container: match (base) {
                    let c: root.types.TyClass => root.hir_ty.AssocContainerClass { value: c.name },
                    let e: root.types.TyEnum => root.hir_ty.AssocContainerEnum { value: e.name },
                    _ => root.hir_ty.AssocContainerTy { value: base },
                },
            }
        },
        1 => DeterminationDetermined { value: declarers[0] },
        _ => DeterminationAmbiguous { value: declarers },
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::concrete_realized_interface @ d9be6853b
// A concrete base's view of the written qualifier, proven by the impl
// oracle: the written generics ride, the impl realizes the associated types
// the qualifier left unwritten.
function concrete_realized_interface(
    db: root.hir.Db,
    base: root.types.Ty,
    qualifier: root.types.InterfaceConstraint,
) -> root.types.InterfaceConstraint? throws never {
    let pool = db.ty_memo.pool;
    let interned = root.hir_ty.try_interned_ty(pool, base)
        ?? return null;
    let goal = root.types.infer_interface_from_constraint(pool, qualifier);
    let resolved = match (root.hir_ty.resolve_implementation(db, interned, goal)) {
        let explicit: root.hir_ty.ResolvedImplementationExplicit => explicit.value,
        root.hir_ty.ResolvedImplementationStructuralDefault => {
            return qualifier;
        },
        null => {
            return null;
        },
    };
    let view = root.types.interface_try_from(pool, resolved.implemented_view(db, interned)) catch (e) {
        root.types.OpenTy => baml.sys.panic("realized view of a closed base is closed"),
    };
    root.types.InterfaceConstraint {
        name: view.name,
        generics: qualifier.generics,
        associated_types: view.associated_types,
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::projection_expand_aliases @ d9be6853b
// Expand a top-level alias chain, bounded against cycles.
function projection_expand_aliases(
    facts: root.hir_ty.Facts,
    ty: root.types.Ty,
) -> root.types.Ty throws never {
    let current = ty;
    for (let i = 0; i < 64; i += 1) {
        let alias = match (current) {
            let a: root.types.TyTypeAlias => a,
            _ => {
                return current;
            },
        };
        let expanded = facts.alias_def(alias.name)
            ?? return current;
        current = expanded;
    }
    current
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_declares_member @ d9be6853b
// Whether `qtn` declares `member` in `ns`. The mounted-row branch is not
// ported (header).
function interface_declares_member(
    db: root.hir.Db,
    qtn: root.types.DeclName,
    member: string,
    ns: MemberNamespace,
) -> bool throws never {
    let loc = projection_interface_loc(db, qtn);
    loc != null && interface_declares_member_at(db, loc, member, ns)
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_declares_member_at @ d9be6853b
function interface_declares_member_at(
    db: root.hir.Db,
    loc: int,
    member: string,
    ns: MemberNamespace,
) -> bool throws never {
    let data = root.hir.interface_data(db, loc);
    match (ns) {
        MemberNamespace.Type => {
            data.associated_types.some((assoc) -> {
                assoc.name == member
            })
        },
        MemberNamespace.Value => source_declared_value_kind(db, data, member) != null,
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::source_declared_value_kind @ d9be6853b
// The value-namespace kind a source interface declares `name` as. Fields
// win the tie (a field and a method cannot share a name).
function source_declared_value_kind(
    db: root.hir.Db,
    data: root.hir.InterfaceData,
    name: string,
) -> ValueMemberKind? throws never {
    if (
        data.fields.some((field) -> {
            field.name == name
        })
    ) {
        return ValueMemberKind.Field;
    }
    if (
        data.methods.some((method) -> {
            root.hir.function_data(db, method).name == name
        })
    ) {
        ValueMemberKind.Method
    } else {
        null
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_declared_kind @ d9be6853b
// What `qtn` declares under `name` in `ns`. The mounted-row branch is not
// ported (header).
function interface_declared_kind(
    db: root.hir.Db,
    qtn: root.types.DeclName,
    name: string,
    ns: MemberNamespace,
) -> InterfaceMemberKind? throws never {
    let loc = projection_interface_loc(db, qtn)
        ?? return null;
    let data = root.hir.interface_data(db, loc);
    match (ns) {
        MemberNamespace.Type => {
            if (
                data.associated_types.some((assoc) -> {
                    assoc.name == name
                })
            ) {
                InterfaceMemberKindAssociatedType {}
            } else {
                null
            }
        },
        MemberNamespace.Value => {
            let kind = source_declared_value_kind(db, data, name);
            if (kind != null) {
                InterfaceMemberKindValue { value: kind }
            } else {
                null
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::projection_interface_loc @ d9be6853b
function projection_interface_loc(db: root.hir.Db, qtn: root.types.DeclName) -> int? throws never {
    match (root.hir_ty.definition_of(db, qtn)) {
        let def: root.hir.DefinitionInterface => def.value,
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/interfaces.rs::interface_base_without_member_pin @ d9be6853b
// The interface a written projection base names without determining
// `member` (the invalid interface-as-base spelling). An alias of a fully
// pinned existential whose spelling pins `member` passes (null).
function interface_base_without_member_pin(
    db: root.hir.Db,
    base_ty: root.types.Ty,
    member: string,
) -> root.types.DeclName? throws never {
    let facts = root.hir_ty.Facts.new(db);
    let seen: map<root.types.DeclName, bool> = {};
    let current = base_ty;
    while (true) {
        match (current) {
            let i: root.types.TyInterface => {
                let pinned = i.associated_types.some((pin) -> {
                    pin.name == member
                });
                return if (pinned) {
                    null
                } else {
                    i.name
                };
            },
            let a: root.types.TyTypeAlias => {
                if (seen.has(a.name)) {
                    return null;
                }
                seen[a.name] = true;
                current
                    = facts.alias_def(a.name)
                        ?? return null;
            },
            _ => {
                return null;
            },
        }
    }
}
