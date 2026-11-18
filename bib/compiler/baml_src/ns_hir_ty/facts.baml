// port: baml_compiler2_hir_ty/src/facts.rs @ d9be6853b
//
// The engine's fact oracle: a `TypeContext` backed by HIR's item data,
// consulted by every subtype, equivalence and canonicalization query. Facts
// are fail-safe per the trait's contract: an unanswerable question returns
// the conservative answer, never a guess.
//
// Restructured:
// - Rust's interned types live in a global pool; `Facts` reads the compile's
//   pool from `db.ty_memo.pool`.
// - The `RefCell` caches are plain maps (BAML classes are references).
// Not ported: `Facts::definition_of` and `Facts::lang` (one-line forwards to
// `definition_of` and `root.hir.lang_roots`) and `Facts::bounds` (read the
// field).

// port: baml_compiler2_hir_ty/src/facts.rs::Facts @ d9be6853b
class Facts {
    db: root.hir.Db,
    // The current scope's param env: each rigid variable's declared bound
    // conjunction, as plain constraints.
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    // Canonicalization asks for the same alias and enum facts many times
    // inside one body: the owned rows are cached at the oracle boundary.
    alias_defs: map<root.types.DeclName, root.types.Ty?>,
    // Rust's `enum_variants`; renamed, a method has that name.
    enum_variants_cache: map<root.types.DeclName, string[]?>,

    // port: baml_compiler2_hir_ty/src/facts.rs::Facts::new @ d9be6853b
    function new(db: root.hir.Db) -> Facts throws never {
        Facts { db: db, bounds: {}, alias_defs: {}, enum_variants_cache: {} }
    }

    // port: baml_compiler2_hir_ty/src/facts.rs::Facts::with_bounds @ d9be6853b
    function with_bounds(
        db: root.hir.Db,
        bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    ) -> Facts throws never {
        Facts { db: db, bounds: bounds, alias_defs: {}, enum_variants_cache: {} }
    }

    // port: baml_compiler2_hir_ty/src/facts.rs::Facts::add_bounds @ d9be6853b
    // Bound one more rigid parameter: a body's `let type T extends I = ...`
    // binding, which enters the env where its statement runs.
    function add_bounds(
        self,
        param: root.types.ParamTy,
        bounds: root.types.InterfaceConstraint[],
    ) -> void throws never {
        self.bounds[param] = bounds;
    }

    // port: baml_compiler2_hir_ty/src/facts.rs::impl TypeContext for Facts @ d9be6853b
    implements root.types.TypeContext {
        function well_known(self, head: root.types.WellKnownHead) -> root.types.DeclName? {
            root.types.well_known_decl(root.hir.lang_roots(self.db), head)
        }

        function alias_def(self, name: root.types.DeclName) -> root.types.Ty? {
            if (self.alias_defs.has(name)) {
                return self.alias_defs[name];
            }
            let resolved = uncached_alias_def(self.db, name);
            self.alias_defs[name] = resolved;
            resolved
        }

        function enum_variants(self, name: root.types.DeclName) -> string[]? {
            if (self.enum_variants_cache.has(name)) {
                return self.enum_variants_cache[name];
            }
            let resolved = uncached_enum_variants(self.db, name);
            self.enum_variants_cache[name] = resolved;
            resolved
        }

        // Interface facts: the impl registry answers.
        function implements_interface(
            self,
            concrete: root.types.Ty,
            interface_: root.types.InterfaceConstraint,
        ) -> bool {
            let pool = self.db.ty_memo.pool;
            let concrete_ty = pool.from_plain(concrete);
            let target = root.types.infer_interface_from_constraint(pool, interface_);
            let eligible = conditional_structural_verdict(self.db, self, concrete_ty, target);
            if (eligible != null) {
                return eligible;
            }
            root.hir_ty.implements_interface(self.db, concrete_ty, target)
        }

        function type_var_bound(
            self,
            param: root.types.ParamTy,
        ) -> root.types.InterfaceConstraint[] {
            self.bounds.get(param) ?? []
        }

        function interface_requires(
            self,
            sub: root.types.InterfaceConstraint,
            sup: root.types.InterfaceConstraint,
        ) -> bool {
            let pool = self.db.ty_memo.pool;
            let sub_reference = root.types.infer_interface_from_constraint(pool, sub);
            // No better subject at this fact boundary: `Self` in `sub`'s
            // requires targets realizes as the existential itself (rustc's
            // `dyn A: B` elaboration).
            let subject = root.types.infer_interface_existential(pool, sub_reference);
            root.hir_ty.interface_requires(
                self.db,
                sub_reference,
                root.types.infer_interface_from_constraint(pool, sup),
                subject,
                8,
            )
        }

        // The declared `type assoc extends J`, realized at the qualifier's
        // args with `Self` left symbolic, then with sibling-pin projections
        // the substitution left behind collapsed (the qualifier's own pins
        // first, then normalized).
        function associated_type_bound(
            self,
            interface_: root.types.InterfaceConstraint,
            assoc: string,
        ) -> root.types.InterfaceConstraint[] {
            let symbolic_self = root.types.TyTypeVar { param: root.types.ParamTy { index: 0, name: "Self" } };
            let realized = realized_assoc_bound_plain(self.db, interface_, symbolic_self, assoc)
                ?? return [];
            let bound = root.types.as_interface(realized)
                ?? return [];
            let collapse = (ty: root.types.Ty) -> root.types.Ty {
                let collapsed = root.hir_ty.interfaces.collapse_self_assoc_projections(
                    ty,
                    [symbolic_self],
                    interface_.name,
                    interface_.generics,
                    interface_.associated_types,
                );
                self.normalize(collapsed)
            };
            [
                root.types.InterfaceConstraint {
                    name: bound.name,
                    generics: bound.generics.map(collapse),
                    associated_types: bound.associated_types.map((pin) -> {
                        root.types.AssociatedType { name: pin.name, ty: collapse(pin.ty) }
                    }),
                },
            ]
        }

        // Single-step projection reduction, in rustc's `project.rs` candidate
        // order: param-env candidates first (the qualifier's own pin, then a
        // rigid var's carried bounds elaborated through the `requires`
        // closure; disagreeing candidates stay opaque), then the base's own
        // reference (an existential's pin or its interface's default), then
        // impl candidates.
        function project(
            self,
            base: root.types.Ty,
            interface_: root.types.InterfaceConstraint,
            member: string,
            fuel: int,
        ) -> root.types.ProjectionStep {
            let own_pin = interface_.associated_types.find((pin) -> {
                pin.name == member
            });
            if (own_pin != null) {
                return root.types.ProjectionStepReduced { ty: own_pin.ty };
            }
            let pool = self.db.ty_memo.pool;
            let target = root.types.infer_interface_from_constraint(pool, interface_);
            let eq = AliasOnlyFacts.new(self.db);
            match (base) {
                let var: root.types.TyTypeVar => {
                    let base_interned = pool.from_plain(base);
                    let candidates: int[] = [];
                    for (let bound in self.type_var_bound(var.param)) {
                        let have = root.types.infer_interface_from_constraint(pool, bound);
                        for (let head in requires_heads(self.db, have, base_interned, 8)) {
                            if (!head_matches(head, target, eq)) {
                                continue;
                            }
                            // Param-env pins only: the declared default
                            // belongs to impl selection.
                            let value = head.associated_types
                                .find((pin) -> {
                                    pin.name == member
                                })
                                ?.ty;
                            if (value != null && !candidates.includes(value)) {
                                candidates.push(value);
                            }
                        }
                    }
                    // A rigid var reaches no impl, so the param env decides
                    // alone.
                    if (candidates.length() != 1) {
                        return root.types.ProjectionStepOpaque {};
                    }
                    let only = root.types.ClosedTy.try_from(pool, candidates[0]) catch (e) {
                        root.types.OpenTy => {
                            return root.types.ProjectionStepOpaque {};
                        },
                    };
                    return root.types.ProjectionStepReduced { ty: pool.to_plain_closed(only.ty) };
                },
                let existential: root.types.TyInterface => {
                    let pin = existential.associated_types.find((pin) -> {
                        pin.name == member
                    });
                    if (pin != null) {
                        return root.types.ProjectionStepReduced { ty: pin.ty };
                    }
                    // An existential fixes an omitted defaulted member to the
                    // default, with `Self` the base itself.
                    let base_target = root.types.infer_interface_new(
                        existential.name,
                        existential.args.map((arg) -> {
                            pool.from_plain(arg)
                        }),
                        existential.associated_types.map((binding) -> {
                            root.types.InferAssociatedType {
                                name: binding.name,
                                ty: pool.from_plain(binding.ty),
                            }
                        }),
                    );
                    let base_interned = try_interned_ty(pool, base)
                        ?? return root.types.ProjectionStepOpaque {};
                    // A pin inherited through the requires closure: all
                    // matching heads vote; one agreed value reduces, a
                    // disagreement stays opaque.
                    let inherited: int[] = [];
                    for (let head in requires_heads(self.db, base_target, base_interned, 8)) {
                        if (!head_matches(head, target, eq)) {
                            continue;
                        }
                        if let ty: int = head.associated_types
                            .find((binding) -> {
                                binding.name == member
                            })
                            ?.ty {
                            if (
                                !inherited.some((have) -> {
                                    eq_admitted(pool, have, ty, eq)
                                })
                            ) {
                                inherited.push(ty);
                            }
                        }
                    }
                    if (inherited.length() > 1) {
                        return root.types.ProjectionStepOpaque {};
                    }
                    if (inherited.length() == 1) {
                        let only = root.types.ClosedTy.try_from(pool, inherited[0]) catch (e) {
                            root.types.OpenTy => {
                                return root.types.ProjectionStepOpaque {};
                            },
                        };
                        return root.types.ProjectionStepReduced { ty: pool.to_plain_closed(only.ty) };
                    }
                    let default_ = realized_assoc_default(self.db, base_target, base_interned, member)
                        ?? return root.types.ProjectionStepOpaque {};
                    let closed = root.types.ClosedTy.try_from(pool, default_) catch (e) {
                        root.types.OpenTy => {
                            return root.types.ProjectionStepOpaque {};
                        },
                    };
                    return root.types.ProjectionStepReduced { ty: pool.to_plain_closed(closed.ty) };
                },
                _ => {},
            }
            let base_interned = try_interned_ty(pool, base)
                ?? return root.types.ProjectionStepOpaque {};
            let resolved = resolve_impl(self.db, base_interned, target);
            if (resolved != null) {
                let pin = resolved_pin(self.db, resolved, base_interned, member);
                if (pin != null) {
                    let closed = root.types.ClosedTy.try_from(pool, pin) catch (e) {
                        root.types.OpenTy => {
                            return root.types.ProjectionStepOpaque {};
                        },
                    };
                    return root.types.ProjectionStepReduced { ty: pool.to_plain_closed(closed.ty) };
                }
            }
            root.types.ProjectionStepOpaque {}
        }
    }
}

// port: baml_compiler2_hir_ty/src/facts.rs::definition_of @ d9be6853b
// The source definition a qualified type name points at, if its package is
// served from source and declares the item. A root served from its interface
// answers null outright: it has no files.
function definition_of(
    db: root.hir.Db,
    name: root.types.DeclName,
) -> root.hir.Definition? throws never {
    if (root.hir.is_served_from_interface(db, name.pkg)) {
        return null;
    }
    root.hir.package_items(db, name.pkg).lookup_type(name.namespace, name.name)
}

// port: baml_compiler2_hir_ty/src/facts.rs::uncached_alias_def @ d9be6853b
// Resolves an alias without retaining the result in a memo.
function uncached_alias_def(
    db: root.hir.Db,
    name: root.types.DeclName,
) -> root.types.Ty? throws never {
    match (definition_of(db, name)) {
        let alias: root.hir.DefinitionTypeAlias => {
            return type_alias_value(db, alias.value);
        },
        _ => {},
    }
    match (mounted_type_row(db, name)) {
        let row: ExportedTypeTypeAlias => row.resolved,
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/facts.rs::uncached_enum_variants @ d9be6853b
// Resolves enum variants without retaining the result in a memo.
function uncached_enum_variants(
    db: root.hir.Db,
    name: root.types.DeclName,
) -> string[]? throws never {
    match (definition_of(db, name)) {
        let enum_def: root.hir.DefinitionEnum => {
            return root.hir.enum_data(db, enum_def.value).variants.map((variant) -> {
                variant.name
            });
        },
        _ => {},
    }
    match (mounted_type_row(db, name)) {
        let row: ExportedTypeEnum => row.variants,
        _ => null,
    }
}
