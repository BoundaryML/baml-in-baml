// port: baml_compiler2_hir_ty/src/impls.rs @ d9be6853b
//
// The impl registry: `(interface, concrete type) -> the unique implements
// block`, plus Hash eligibility and the `requires` closure.
//
// Hash eligibility: this ports upstream's fixed shape, not the code at
// d9be6853b. At d9be6853b `applicable_structural_interface_roots` proved
// `Hash` (a walk of the receiver's whole type graph) for every receiver
// whose member was looked up, which was ~80% of check time. Upstream split
// it into `structural_interface_candidates` (every structural root, the same
// order) and `structural_root_applies` (the per-root proof), and the two
// hot callers (method_resolution.baml's `lookup_impl_member` and
// `union_arm_interfaces`) prove a root only once it declares the looked-up
// member; `impl_views_for_type` takes the caller's `structural` filter.
// Results are identical: a root that does not declare the member never
// contributed a provider or a declarer.
//
// Restructured:
// - Rust's interned `Ty` is an `int` into `db.ty_memo.pool`; a function with
//   no `db` takes the pool first. `InferInterface` is
//   `root.types.InferInterfaceConstraint`, `baml_type::Interface` is
//   `root.types.InterfaceConstraint`.
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so the External lane is dropped: `ResolvedImplFacts` is the Source lane
//   only (a block id and its facts), `ImplRef` is an `int` impl loc, and
//   `MountedImplFacts`, `exported_impl_facts` and the mounted half of
//   `package_impl_candidates` are not ported. The `mounted_type_row` branches
//   that read only ported row fields are kept; `direct_requires`' needs the
//   row's `requires` closure, which is not ported, so it is dropped.
// - `ImplTypeKey` (`(viewer root, plain concrete Ty)`, salsa-interned) is
//   interned in `db.ty_memo.impl_type_keys`: the concrete type is interned
//   into the pool (`pool.from_plain`, structurally equal types share a
//   handle), and `(viewer, handle)` maps to a dense `int` key.
// - Nested `fn`s are top-level functions named `<outer>_<inner>`. A
//   wrapper that only seeds its worker's arguments is the worker with
//   named defaults: `hash_eligible` (+ `hash_eligible_within_depth`),
//   `interface_requires` (+ `interface_requires_inner`).
// - `ImplHeaderResolution` and `ResolvedImpl` methods that read a field
//   (`ResolvedImpl::block`, `ResolvedImplFacts` accessors) are not ported:
//   read `.block` / `.facts.<field>`.
//
// Not ported (no Type-diagnostic caller): `impls_naming_interface` (IDE,
// describe), `concrete_callee_target` (MIR), `reduce_ground_projections_plain`
// (package export), and `interned_ty` (`pool.from_plain`).

// port: baml_compiler2_hir_ty/src/impls.rs::BLANKET_IMPL_BOUND_DEPTH @ d9be6853b
// Recursion budget for verifying blanket bounds: a bounded blanket can itself
// be satisfied by another blanket, so bound-checking re-enters the resolver.
const BLANKET_IMPL_BOUND_DEPTH: int = 16;

// port: baml_compiler2_hir_ty/src/impls.rs::try_interned_ty @ d9be6853b
// The plain type interned, declining a type carrying an `Error` sentinel
// anywhere: an oracle asked about it answers "undecidable" (null).
// Restructured: the sentinel is found by the interned HAS_ERROR flag, which
// is the same walk.
function try_interned_ty(pool: root.types.InferPool, ty: root.types.Ty) -> int? throws never {
    let interned = pool.from_plain(ty);
    if (pool.has_error(interned)) {
        return null;
    }
    interned
}

// port: baml_compiler2_hir_ty/src/impls.rs::subject_head_is_implementor @ d9be6853b
// Whether a lowered for-target is a valid implementor, the E0138 rule: alias
// heads expand (reading alias definitions only), nothing else does.
function subject_head_is_implementor(db: root.hir.Db, ty: root.types.Ty) -> bool throws never {
    let head = ty;
    // Bounded: a cyclic alias is rejected at its declaration (E0068).
    for (let i = 0; i < 64; i += 1) {
        let alias = match (head) {
            let a: root.types.TyTypeAlias => a,
            _ => null,
        };
        if (alias == null) {
            break;
        }
        let expanded = uncached_alias_def(db, alias.name);
        if (expanded == null) {
            break;
        }
        head = expanded;
    }
    root.types.is_valid_impl_subject(head)
}

// port: baml_compiler2_hir_ty/src/impls.rs::ImplFacts @ d9be6853b
// One impl's resolution-relevant facts, normalized to the free shape, in the
// closed interned vocabulary.
class ImplFacts {
    interface_: root.types.ClosedInterface,
    for_ty_pattern: root.types.ClosedTy,
    // The impl's own generic params with their conjunctive bounds.
    generic_params: (root.types.ParamTy, root.types.ClosedInterface[])[],
    associated_types: (string, root.types.ClosedTy)[],
    methods: int[],
}

// port: baml_compiler2_hir_ty/src/impls.rs::ImplHeaderResolution @ d9be6853b
// One impl block's header resolution: the single decision point for header
// validity.
type ImplHeaderResolution = ImplHeaderResolutionUnresolved
    | ImplHeaderResolutionPoisoned
    | ImplHeaderResolutionNotImplementor
    | ImplHeaderResolutionResolved;

// The header does not resolve to an interface.
class ImplHeaderResolutionUnresolved {
}

// The header declares generic params neither the for-target nor the
// interface arguments determine, in frame order.
class ImplHeaderResolutionPoisoned {
    unconstrained: string[],
}

// The written for-target is not an implementor (E0138). `facts` has the
// subject replaced by the Error sentinel.
class ImplHeaderResolutionNotImplementor {
    target: root.types.Ty,
    facts: ImplFacts,
}

class ImplHeaderResolutionResolved {
    value: ImplFacts,
}

// port: baml_compiler2_hir_ty/src/impls.rs::ImplHeaderResolution::resolved @ d9be6853b
// The facts, when the header resolved cleanly: the selection surface.
function impl_header_resolution_resolved(
    resolution: ImplHeaderResolution,
) -> ImplFacts? throws never {
    match (resolution) {
        let r: ImplHeaderResolutionResolved => r.value,
        ImplHeaderResolutionUnresolved
            | ImplHeaderResolutionPoisoned
            | ImplHeaderResolutionNotImplementor =>
        {
            null
        },
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::ImplHeaderResolution::for_display @ d9be6853b
// The facts for describing the block, resolved or not an implementor.
function impl_header_resolution_for_display(
    resolution: ImplHeaderResolution,
) -> ImplFacts? throws never {
    match (resolution) {
        let r: ImplHeaderResolutionResolved => r.value,
        let r: ImplHeaderResolutionNotImplementor => r.facts,
        ImplHeaderResolutionUnresolved | ImplHeaderResolutionPoisoned => null,
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::impl_facts @ d9be6853b
// The resolution-relevant facts of one impl block, behind the header's
// validity decision.
function impl_facts(db: root.hir.Db, block: int) -> ImplHeaderResolution throws never {
    db.ty_memo.impl_facts.get(db.cycles, block, () -> {
        let pool = db.ty_memo.pool;
        let data = root.hir.impl_block_data(db, block);
        let file = db.impl_locs.get(block).file;
        // The generic frame and for-target, one path for both spellings.
        let frame: root.types.ParamTy[] = [];
        root.types.ParamTy.extend_frame(
            frame,
            data.generics.map((param) -> {
                param.name
            }),
        );
        let ctx = lower_ctx_for_file(db, file).with_frame(frame);
        let param_bounds: root.types.InterfaceConstraint[][] = data.generics.map((param) -> {
            param.bounds.filter_map((type_ref) -> {
                root.types.as_interface(
                    reject_holes(
                        ctx.lower_type_ref(
                            data.type_refs,
                            type_ref,
                            position = TypePosition.ConstraintHead,
                        ),
                    ),
                )
            })
        });
        let for_ty_plain = reject_holes(ctx.lower_type_ref(data.type_refs, data.for_target));
        // E0138, decided on the lowered form; a rejected subject is replaced
        // by the Error sentinel so the IDE keeps a fact set.
        let not_implementor: root.types.Ty? = null;
        let for_ty_pattern = if (subject_head_is_implementor(db, for_ty_plain)) {
            root.types.ClosedTy { ty: pool.from_plain(for_ty_plain) }
        } else {
            not_implementor = for_ty_plain;
            root.types.ClosedTy { ty: pool.add(root.types.TyError {}) }
        };
        let params = frame;
        // The impl's own bounds ride along: `type Output = T.Item` finds
        // `Item`'s declaring interface through `T`'s declared bound.
        let bounds_map: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
        for (let i = 0; i < params.length(); i += 1) {
            bounds_map[params[i]] = param_bounds[i];
        }
        let ctx = lower_ctx_for_file(db, file).with_frame(params).with_bounds(bounds_map);
        // A path headed by an item of this namespace is a projection off
        // that item, which names no interface (and resolving it would ask
        // this impl's own facts): the header resolves to nothing.
        let target_kind = data.type_refs.get(data.interface_target).kind;
        if let path: root.hir.TypeRefKindPath = target_kind {
            let segments = path.path.segments;
            if (
                segments.length() >= 2
                    && ctx.type_path_head(path.path.origin, segments) is root.hir.PathHeadPlain
                    && ctx.lexical_generic(segments[0]) == null
                    && root.hir.namespace_declares(
                        db,
                        db.file(file).root,
                        ctx.ns_context,
                        segments[0],
                    )
            ) {
                return ImplHeaderResolutionUnresolved {};
            }
        }
        let interface_plain = root.types.as_interface(
            reject_holes(
                ctx.lower_type_ref(
                    data.type_refs,
                    data.interface_target,
                    position = TypePosition.ConstraintHead,
                ),
            ),
        )
            ?? return ImplHeaderResolutionUnresolved {};
        let interface_ = root.types.ClosedInterface {
            reference: root.types.infer_interface_from_constraint(pool, interface_plain),
        };
        // A declared param neither the for-target nor the interface
        // arguments determine poisons the header (E0135 renders this list).
        // A rejected subject is the Error sentinel and mentions no param, so
        // nothing is reported for it.
        let unconstrained: string[] = if (not_implementor != null) {
            []
        } else {
            params
                .filter((param) -> {
                    !ty_mentions_param(pool, for_ty_pattern.ty, param)
                        && !interface_.reference.generics.some((arg) -> {
                            ty_mentions_param(pool, arg, param)
                        })
                })
                .map((param) -> {
                    param.name
                })
        };
        if (unconstrained.length() != 0) {
            return ImplHeaderResolutionPoisoned { unconstrained: unconstrained };
        }
        let associated_types = impl_facts_associated_types(db, block, interface_, for_ty_pattern, params, bounds_map, ctx);
        let facts = ImplFacts {
            interface_: interface_,
            for_ty_pattern: for_ty_pattern,
            generic_params: params.map((param) -> {
                (
                    param,
                    param_bounds[param.index].map((bound) -> {
                        root.types.ClosedInterface {
                            reference: root.types.infer_interface_from_constraint(pool, bound),
                        }
                    }),
                )
            }),
            associated_types: associated_types,
            methods: data.methods,
        };
        if (not_implementor != null) {
            ImplHeaderResolutionNotImplementor { target: not_implementor, facts: facts }
        } else {
            ImplHeaderResolutionResolved { value: facts }
        }
    })
}

// port: baml_compiler2_hir_ty/src/impls.rs::impl_facts @ d9be6853b
// `impl_facts`' associated-type pins. Restructured: split out of
// `impl_facts`. A mounted interface has no `InterfaceLoc`, so its members are
// lowered here in its declared order with symbolic `Self`, each resolved pin
// exposed on `Self`'s bound before the next; a source interface's bindings
// lower directly.
function impl_facts_associated_types(
    db: root.hir.Db,
    block: int,
    interface_: root.types.ClosedInterface,
    for_ty_pattern: root.types.ClosedTy,
    params: root.types.ParamTy[],
    bounds_map: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    ctx: LowerCtx,
) -> (string, root.types.ClosedTy)[] throws never {
    let pool = db.ty_memo.pool;
    let data = root.hir.impl_block_data(db, block);
    let file = db.impl_locs.get(block).file;
    let row = match (mounted_type_row(db, interface_.reference.name)) {
        let r: ExportedTypeInterface => r,
        _ => null,
    };
    if (row == null) {
        return data.associated_type_bindings.filter_map((binding) -> {
            let type_ref = binding.type_ref;
            if (type_ref == null) {
                null
            } else {
                (
                    binding.name,
                    root.types.ClosedTy {
                        ty: pool.from_plain(reject_holes(ctx.lower_type_ref(data.type_refs, type_ref))),
                    },
                )
            }
        });
    }
    let interface_plain = interface_.to_plain(pool);
    let for_ty = pool.to_plain_closed(for_ty_pattern.ty);
    let self_var = root.types.TyTypeVar { param: row.self_param };
    let value_scope = params.concat([row.self_param]);
    let value_bindings: map<root.types.ParamTy, root.types.Ty> = {};
    for (let param in params) {
        value_bindings[param] = root.types.TyTypeVar { param: param };
    }
    value_bindings[row.self_param] = for_ty;
    let resolved_pins: root.types.AssociatedType[] = [];
    for (let associated_type in row.associated_types) {
        let binding = data.associated_type_bindings.find((b) -> {
            b.name == associated_type.name
        });
        let binding_ref = binding?.type_ref;
        let default_ = associated_type.default_;
        let realized: root.types.Ty? = if (binding_ref != null) {
            let bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
            for (let key in bounds_map.keys()) {
                bounds[key] = bounds_map[key];
            }
            bounds[row.self_param]
                = [
                    root.types.InterfaceConstraint {
                        name: interface_plain.name,
                        generics: interface_plain.generics,
                        associated_types: resolved_pins.concat([]).sort_by_key((pin) -> {
                            pin.name
                        }),
                    },
                ];
            let lowered = reject_holes(
                lower_ctx_for_file(db, file).with_frame(value_scope)
                    .with_bounds(bounds)
                    .with_self_ty(self_var)
                    .lower_type_ref(data.type_refs, binding_ref),
            );
            root.types.substitute_ty(lowered, value_bindings)
        } else if (default_ != null) {
            root.hir_ty.interfaces.realize_associated_default(
                default_,
                row.generic_params,
                interface_plain.generics,
                row.self_param,
                for_ty,
            )
        } else {
            null
        };
        if (realized == null) {
            continue;
        }
        let collapsed = root.hir_ty.interfaces.collapse_self_assoc_projections(
            realized,
            [self_var, for_ty],
            interface_plain.name,
            interface_plain.generics,
            resolved_pins,
        );
        resolved_pins.push(root.types.AssociatedType { name: associated_type.name, ty: collapsed });
    }
    resolved_pins.map((pin) -> {
        (pin.name, root.types.ClosedTy { ty: pool.from_plain(pin.ty) })
    })
}

// port: baml_compiler2_hir_ty/src/impls.rs::package_impl_locs @ d9be6853b
// Every impl block a package declares, in source order. Scans only the
// package's own files.
function package_impl_locs(db: root.hir.Db, package: int) -> int[] throws never {
    db.ty_memo.package_impl_locs.get(db.cycles, package, () -> {
        db.source_root(package).files.flat_map((file) -> {
            root.hir.file_impls(db, file)
        })
    })
}

// port: baml_compiler2_hir_ty/src/impls.rs::AliasOnlyFacts @ d9be6853b
// The fact-poor equality context (TIR's `AliasEquivCtx`): aliases and enum
// variants only. Everything else answers the conservative default, which is
// the termination argument (a fact-rich context would let the matcher
// re-enter the resolver that called it).
class AliasOnlyFacts {
    db: root.hir.Db,
    // Rust's `memoized`; renamed, a static method has that name.
    memoized_facts: Facts?,

    // port: baml_compiler2_hir_ty/src/impls.rs::AliasOnlyFacts::new @ d9be6853b
    // A one-shot alias/enum context.
    function new(db: root.hir.Db) -> AliasOnlyFacts throws never {
        AliasOnlyFacts { db: db, memoized_facts: null }
    }

    // port: baml_compiler2_hir_ty/src/impls.rs::AliasOnlyFacts::memoized @ d9be6853b
    // A scan-local alias/enum context that caches repeated type heads.
    function memoized(db: root.hir.Db) -> AliasOnlyFacts throws never {
        AliasOnlyFacts { db: db, memoized_facts: Facts.new(db) }
    }

    // port: baml_compiler2_hir_ty/src/impls.rs::impl TypeContext for AliasOnlyFacts @ d9be6853b
    implements root.types.TypeContext {
        function well_known(self, head: root.types.WellKnownHead) -> root.types.DeclName? {
            root.types.well_known_decl(root.hir.lang_roots(self.db), head)
        }

        function alias_def(self, name: root.types.DeclName) -> root.types.Ty? {
            let facts = self.memoized_facts;
            if (facts != null) {
                facts.alias_def(name)
            } else {
                uncached_alias_def(self.db, name)
            }
        }

        function enum_variants(self, name: root.types.DeclName) -> string[]? {
            let facts = self.memoized_facts;
            if (facts != null) {
                facts.enum_variants(name)
            } else {
                uncached_enum_variants(self.db, name)
            }
        }

        function implements_interface(
            self,
            concrete: root.types.Ty,
            interface_: root.types.InterfaceConstraint,
        ) -> bool {
            false
        }

        function type_var_bound(
            self,
            param: root.types.ParamTy,
        ) -> root.types.InterfaceConstraint[] {
            []
        }

        function interface_requires(
            self,
            sub: root.types.InterfaceConstraint,
            sup: root.types.InterfaceConstraint,
        ) -> bool {
            false
        }

        function associated_type_bound(
            self,
            interface_: root.types.InterfaceConstraint,
            assoc: string,
        ) -> root.types.InterfaceConstraint[] {
            []
        }

        function project(
            self,
            base: root.types.Ty,
            interface_: root.types.InterfaceConstraint,
            member: string,
            fuel: int,
        ) -> root.types.ProjectionStep {
            root.types.ProjectionStepOpaque {}
        }
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::is_concrete_receiver @ d9be6853b
// A value whose runtime type pins a single static impl. A bare blanket
// `implement<T> I for T` applies only to these.
function is_concrete_receiver(pool: root.types.InferPool, ty: int) -> bool throws never {
    match (pool.kinds[ty]) {
        root.types.InferTyClass
            | root.types.TyEnum
            | root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.InferTyList
            | root.types.InferTyMap
            | root.types.InferTyFuture
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst =>
        {
            true
        },
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::ResolvedImplFacts @ d9be6853b
// A resolved impl's identity with its facts. Restructured: the Source lane
// only (see the file header).
class ResolvedImplFacts {
    block: int,
    facts: ImplFacts,
}

// port: baml_compiler2_hir_ty/src/impls.rs::ResolvedImpl @ d9be6853b
// One resolved impl plus the generic instantiation the match pinned.
class ResolvedImpl {
    facts: ResolvedImplFacts,
    bindings: map<root.types.ParamTy, int>,

    // port: baml_compiler2_hir_ty/src/impls.rs::ResolvedImpl::implemented @ d9be6853b
    // The interface this impl provides, realized through the match's
    // bindings. Associated members carry only what the header wrote.
    function implemented(
        self,
        pool: root.types.InferPool,
    ) -> root.types.InferInterfaceConstraint throws never {
        root.types.infer_interface_map_types(self.facts.facts.interface_.reference, (ty) -> {
            pool.substitute_bindings(ty, self.bindings)
        })
    }

    // port: baml_compiler2_hir_ty/src/impls.rs::ResolvedImpl::implemented_view @ d9be6853b
    // The complete realized view of the implemented interface for subject
    // `self_ty`: every associated member the interface declares, resolved
    // through the projection ladder.
    function implemented_view(
        self,
        db: root.hir.Db,
        self_ty: int,
    ) -> root.types.InferInterfaceConstraint throws never {
        let header = self.implemented(db.ty_memo.pool);
        let declared: string[] = match (definition_of(db, header.name)) {
            let def: root.hir.DefinitionInterface => {
                root.hir.interface_data(db, def.value).associated_types.map((assoc) -> {
                    assoc.name
                })
            },
            _ => {
                match (mounted_type_row(db, header.name)) {
                    let row: ExportedTypeInterface => {
                        row.associated_types.map((assoc) -> {
                            assoc.name
                        })
                    },
                    _ => {
                        return header;
                    },
                }
            },
        };
        let associated_types = declared.filter_map((member) -> {
            let pin = resolved_pin(db, self, self_ty, member);
            if (pin != null) {
                root.types.InferAssociatedType { name: member, ty: pin }
            } else {
                null
            }
        });
        root.types.infer_interface_new(header.name, header.generics, associated_types)
    }

    // port: baml_compiler2_hir_ty/src/impls.rs::ResolvedImpl::provided_method @ d9be6853b
    // What this impl provides for method `name`; null leaves the method to
    // the interface's default body.
    function provided_method(self, db: root.hir.Db, name: string) -> int? throws never {
        self.facts.facts.methods.find((method) -> {
            root.hir.function_data(db, method).name == name
        })
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::CachedResolvedImpl @ d9be6853b
// A memoized candidate: the impl's identity and the match's bindings,
// fact-free.
class CachedResolvedImpl {
    block: int,
    bindings: map<root.types.ParamTy, int>,
}

// port: baml_compiler2_hir_ty/src/impls.rs::resolved_pin @ d9be6853b
// The realized value of associated `member` under a resolved impl: the
// impl's own binding through the match, else the interface's default
// realized at the receiver (rustc's `leaf_def`).
function resolved_pin(
    db: root.hir.Db,
    resolved: ResolvedImpl,
    self_ty: int,
    member: string,
) -> int? throws never {
    let pool = db.ty_memo.pool;
    let declared = resolved.facts.facts.associated_types.find((pin) -> {
        pin.0 == member
    });
    if (declared != null) {
        return pool.substitute_bindings(declared.1.ty, resolved.bindings);
    }
    realized_assoc_default(db, resolved.implemented(pool), self_ty, member)
}

// port: baml_compiler2_hir_ty/src/impls.rs::realized_assoc_default @ d9be6853b
// The interface's declared default for `member`, realized at a use site:
// `Self` = `self_ty` and the interface's generics via `[Self, args..]`.
function realized_assoc_default(
    db: root.hir.Db,
    target: root.types.InferInterfaceConstraint,
    self_ty: int,
    member: string,
) -> int? throws never {
    let pool = db.ty_memo.pool;
    match (mounted_type_row(db, target.name)) {
        let row: ExportedTypeInterface => {
            let default_ = row.associated_types
                .find((assoc) -> {
                    assoc.name == member
                })
                ?.default_
                ?? return null;
            let instantiation = interface_instantiation(self_ty, target, row.generic_params.length())
                ?? return null;
            return substitute_params(pool, pool.from_plain(default_), instantiation);
        },
        _ => {},
    }
    let (let interface_, let data) = assoc_realization_env(db, target)
        ?? return null;
    let lowered = interface_assoc_default(db, interface_, member).value
        ?? return null;
    let instantiation = interface_instantiation(self_ty, target, data.generic_params.length())
        ?? return null;
    substitute_params(pool, pool.from_plain(lowered), instantiation)
}

// port: baml_compiler2_hir_ty/src/impls.rs::eq_admitted @ d9be6853b
// Equivalence over matcher values: both sides must close, else nothing
// matches (fail closed). Restructured: takes the pool.
function eq_admitted(
    pool: root.types.InferPool,
    a: int,
    b: int,
    eq: root.types.TypeContext,
) -> bool throws never {
    if (pool.has_infer(a) || pool.has_infer(b)) {
        return false;
    }
    root.types.equivalent_interned(
        pool,
        root.types.ClosedTy { ty: a },
        root.types.ClosedTy { ty: b },
        eq,
    )
}

// port: baml_compiler2_hir_ty/src/impls.rs::realized_assoc_bound_plain @ d9be6853b
// `realized_assoc_bound`'s plain entry: plain inputs intern on the way in,
// and the realized bound exits closed.
function realized_assoc_bound_plain(
    db: root.hir.Db,
    target: root.types.InterfaceConstraint,
    self_ty: root.types.Ty,
    member: string,
) -> root.types.Ty? throws never {
    let pool = db.ty_memo.pool;
    let bound = realized_assoc_bound(db, root.types.infer_interface_from_constraint(pool, target), pool.from_plain(self_ty), member)
        ?? return null;
    if (pool.has_infer(bound)) {
        baml.sys.panic("closed inputs realize to a closed bound");
    }
    pool.to_plain_closed(bound)
}

// port: baml_compiler2_hir_ty/src/impls.rs::realized_assoc_bound @ d9be6853b
// The declared bound of `member` (`type member extends J`), realized at the
// reference: what a still-symbolic projection is provable against.
function realized_assoc_bound(
    db: root.hir.Db,
    target: root.types.InferInterfaceConstraint,
    self_ty: int,
    member: string,
) -> int? throws never {
    let pool = db.ty_memo.pool;
    match (mounted_type_row(db, target.name)) {
        let row: ExportedTypeInterface => {
            let bound = row.associated_types
                .find((assoc) -> {
                    assoc.name == member
                })
                ?.bound
                ?? return null;
            let instantiation = interface_instantiation(self_ty, target, row.generic_params.length())
                ?? return null;
            let bound_ty = pool.add(
                root.types.InferTyInterface {
                    name: bound.name,
                    args: bound.generics.map((arg) -> {
                        pool.from_plain(arg)
                    }),
                    associated_types: bound.associated_types.map((pin) -> {
                        root.types.InferAssociatedType {
                            name: pin.name,
                            ty: pool.from_plain(pin.ty),
                        }
                    }),
                },
            );
            return substitute_params(pool, bound_ty, instantiation);
        },
        _ => {},
    }
    let (let interface_, let data) = assoc_realization_env(db, target)
        ?? return null;
    let lowered = interface_assoc_bound(db, interface_, member).value
        ?? return null;
    let instantiation = interface_instantiation(self_ty, target, data.generic_params.length())
        ?? return null;
    substitute_params(pool, pool.from_plain(lowered), instantiation)
}

// port: baml_compiler2_hir_ty/src/impls.rs::assoc_realization_env @ d9be6853b
// The interface definition and its data for a realization. Arity is judged
// by `interface_instantiation`, which every caller proceeds into.
function assoc_realization_env(
    db: root.hir.Db,
    target: root.types.InferInterfaceConstraint,
) -> (int, root.hir.InterfaceData)? throws never {
    match (definition_of(db, target.name)) {
        let def: root.hir.DefinitionInterface => (def.value, root.hir.interface_data(db, def.value)),
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::impl_views_for_type @ d9be6853b
// The dispatch views every impl block contributes for a plain receiver, plus
// the structural roots it implements. Upstream's fixed shape: `structural`
// selects the structural roots worth proving (deciding `Hash` walks the
// receiver's whole type graph), so a caller after one member rejects roots
// that cannot lead to it.
function impl_views_for_type(
    db: root.hir.Db,
    viewer: int,
    concrete: root.types.Ty,
    structural: (root.types.DeclName) -> bool,
) -> root.types.InterfaceConstraint[] {
    let pool = db.ty_memo.pool;
    let interned = try_interned_ty(pool, concrete)
        ?? return [];
    let to_plain = (view: root.types.InferInterfaceConstraint) -> root.types.InterfaceConstraint {
        root.types.interface_try_from(pool, view) catch (e) {
            root.types.OpenTy => baml.sys.panic("realized view of a closed receiver is closed"),
        }
    };
    let views = impls_for_type(db, viewer, concrete).map((resolved) -> {
        to_plain(resolved.implemented_view(db, interned))
    });
    let facts = Facts.new(db);
    for (let interface_ in structural_interface_candidates(db)) {
        if (!structural(interface_.name) || !structural_root_applies(db, facts, interned, interface_)) {
            continue;
        }
        let view = to_plain(interface_);
        if (!views.includes(view)) {
            views.push(view);
        }
    }
    views
}

// port: baml_compiler2_hir_ty/src/impls.rs::REQUIRES_CLOSURE_FUEL @ d9be6853b
// The `requires`-closure traversal budget every consumer shares: one unit per
// queued interface, so it bounds ancestor depth, not fan-out.
const REQUIRES_CLOSURE_FUEL: int = 64;

// port: baml_compiler2_hir_ty/src/impls.rs::direct_requires_closure_plain @ d9be6853b
// `direct_requires_closure`'s plain entry.
function direct_requires_closure_plain(
    db: root.hir.Db,
    root_: root.types.InterfaceConstraint,
    self_ty: root.types.Ty,
    fuel: int,
) -> root.types.InterfaceConstraint[] throws never {
    let pool = db.ty_memo.pool;
    direct_requires_closure(db, root.types.infer_interface_from_constraint(pool, root_), pool.from_plain(self_ty), fuel)
        .map((reference) -> {
            root.types.interface_try_from(pool, reference) catch (e) {
                root.types.OpenTy => baml.sys.panic("requires closure of closed inputs is closed"),
            }
        })
}

// port: baml_compiler2_hir_ty/src/impls.rs::impls_for_type @ d9be6853b
// Every impl an admissible plain `concrete` type matches, across every
// package `viewer` sees. A literal widens to its base primitive first, so
// both spellings share one cache entry.
function impls_for_type(
    db: root.hir.Db,
    viewer: int,
    concrete: root.types.Ty,
) -> ResolvedImpl[] throws never {
    if let literal: root.types.TyLiteral = concrete {
        let widened = root.types.from_primitive(root.types.primitive_type_from_literal(literal.value));
        return impls_for_type(db, viewer, widened);
    }
    let key = db.ty_memo.impl_type_keys.intern(viewer, db.ty_memo.pool.from_plain(concrete));
    let lang = root.hir.lang_roots(db);
    impls_for_type_cached(db, key)
        .map((cached) -> {
            ResolvedImpl { facts: matched_impl_facts(db, cached.block), bindings: cached.bindings }
        })
        .filter((resolved) -> {
            // `AnyClass` is an explicit narrowing surface, kept out of the
            // concrete receiver tier.
            provides_concrete_members(lang, resolved.facts.facts.interface_.reference.name)
        })
}

// port: baml_compiler2_hir_ty/src/impls.rs::provides_concrete_members @ d9be6853b
// Whether an implemented interface contributes members to an unqualified
// concrete-receiver lookup (`AnyClass` does not).
function provides_concrete_members(
    lang: root.base.LangRoots,
    interface_: root.types.DeclName,
) -> bool throws never {
    !root.types.decl_name_is_lang_root_type(
        interface_,
        lang,
        root.base.LangPackage.Reflect,
        "AnyClass",
    )
}

// port: baml_compiler2_hir_ty/src/impls.rs::is_concrete_type_member @ d9be6853b
// Whether `member` of `interface_` is `baml.Concrete`'s static `type()`.
function is_concrete_type_member(
    lang: root.base.LangRoots,
    interface_: root.types.DeclName,
    member: string,
) -> bool throws never {
    member == "type"
        && root.types.decl_name_is_lang_root_type(
            interface_,
            lang,
            root.base.LangPackage.Baml,
            "Concrete",
        )
}

// port: baml_compiler2_hir_ty/src/impls.rs::demote_concrete_type_member @ d9be6853b
// Drops `baml.Concrete` from the interfaces declaring `member` when the
// member is its `type` and another interface declares it too. Restructured:
// returns the kept declarers instead of editing the `&mut Vec`.
function demote_concrete_type_member<T>(
    lang: root.base.LangRoots,
    member: string,
    declarers: T[],
    interface_: (T) -> root.types.DeclName,
) -> T[] {
    let concrete = (declarer: T) -> bool {
        is_concrete_type_member(lang, interface_(declarer), member)
    };
    if (
        declarers.some((declarer) -> {
            !concrete(declarer)
        })
    ) {
        declarers.filter((declarer) -> {
            !concrete(declarer)
        })
    } else {
        declarers
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::derived_impl_allows @ d9be6853b
// Compiler-derived interfaces may narrow a blanket stdlib impl: `AnyClass`
// admits only what normalizes to a class.
function derived_impl_allows(
    db: root.hir.Db,
    concrete: int,
    interface_: root.types.DeclName,
) -> bool throws never {
    if (
        !root.types.decl_name_is_lang_root_type(
            interface_,
            root.hir.lang_roots(db),
            root.base.LangPackage.Reflect,
            "AnyClass",
        )
    ) {
        return true;
    }
    let pool = db.ty_memo.pool;
    // Fail closed: an open value proves no membership.
    if (pool.has_infer(concrete)) {
        return false;
    }
    let normalized = root.types.normalize_interned(
        pool,
        root.types.ClosedTy { ty: concrete },
        AliasOnlyFacts.new(db),
    );
    pool.kinds[normalized.ty] is root.types.InferTyClass
}

// port: baml_compiler2_hir_ty/src/impls.rs::ImplTypeKey @ d9be6853b
// The `(viewer root, concrete type)` key of `impls_for_type_cached`,
// interned to a dense `int`. The concrete type is its pool handle.
class ImplTypeKeys {
    index: map<int, map<int, int>>,
    viewers: int[],
    concretes: int[],

    function new() -> ImplTypeKeys throws never {
        ImplTypeKeys { index: {}, viewers: [], concretes: [] }
    }

    function intern(self, viewer: int, concrete: int) -> int throws never {
        let by_concrete = self.index.get_or_insert(viewer, {});
        let existing = by_concrete.get(concrete);
        if (existing != null) {
            return existing;
        }
        let key = self.viewers.length();
        self.viewers.push(viewer);
        self.concretes.push(concrete);
        by_concrete[concrete] = key;
        key
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::impls_for_type_cached @ d9be6853b
// Memoized ground candidate assembly for one `(viewer, concrete)` key. A
// recursive obligation can re-enter it through `bounds_hold`; inductive impl
// cycles contribute no candidates (`impls_for_type_cycle_result`).
function impls_for_type_cached(
    db: root.hir.Db,
    type_key: int,
) -> CachedResolvedImpl[] throws never {
    db.ty_memo.impls_for_type_cached.get_fallback(
        db.cycles,
        type_key,
        () -> {
            impls_for_type_cycle_result(db, type_key)
        },
        () -> {
            let pool = db.ty_memo.pool;
            let concrete = db.ty_memo.impl_type_keys.concretes[type_key];
            // An error-carrying goal proves nothing.
            if (pool.has_error(concrete)) {
                return [];
            }
            let eq = AliasOnlyFacts.memoized(db);
            let out: CachedResolvedImpl[] = [];
            for (
                let package in root.hir.visible_packages(
                    db,
                    db.ty_memo.impl_type_keys.viewers[type_key],
                )
            ) {
                for (let facts in package_impl_candidates(db, package)) {
                    let accepted = impls_for_type_candidate(db, facts, concrete, eq);
                    if (accepted != null) {
                        out.push(accepted);
                    }
                }
            }
            out
        },
    )
}

// port: baml_compiler2_hir_ty/src/impls.rs::impls_for_type_cycle_result @ d9be6853b
// Inductive impl cycles contribute no candidates.
function impls_for_type_cycle_result(
    db: root.hir.Db,
    type_key: int,
) -> CachedResolvedImpl[] throws never {
    []
}

// port: baml_compiler2_hir_ty/src/impls.rs::impls_for_type_cached @ d9be6853b
// One candidate of the scan, accepted or not. Restructured: the loop body of
// `impls_for_type_cached`, split out.
function impls_for_type_candidate(
    db: root.hir.Db,
    facts: ResolvedImplFacts,
    concrete: int,
    eq: AliasOnlyFacts,
) -> CachedResolvedImpl? throws never {
    let pool = db.ty_memo.pool;
    let pattern = facts.facts.for_ty_pattern.ty;
    let pattern_has_typevar = pool.has_typevar(pattern);
    if (!pattern_has_typevar && !eq_admitted(pool, pattern, concrete, eq)) {
        return null;
    }
    let params = facts.facts.generic_params.map((param) -> {
        param.0
    });
    // Bare-blanket guard, as in `match_impl_head`.
    if let var: root.types.TyTypeVar = pool.kinds[pattern] {
        if (params.includes(var.param) && !is_concrete_receiver(pool, concrete)) {
            return null;
        }
    }
    let bindings: map<root.types.ParamTy, int> = {};
    if (pattern_has_typevar && !match_pattern(pool, pattern, concrete, params, bindings, eq)) {
        return null;
    }
    if (!bounds_hold(db, facts, bindings, BLANKET_IMPL_BOUND_DEPTH, [])) {
        return null;
    }
    // An implemented interface still mentioning unbound impl params is
    // undetermined by the receiver: skipped (checked on the pattern side).
    let undetermined = (ty: int) -> bool {
        !pattern_fully_bound(pool, ty, params, bindings)
    };
    let reference = facts.facts.interface_.reference;
    if (
        reference.generics.some(undetermined)
            || reference.associated_types.some((pin) -> {
                undetermined(pin.ty)
            })
    ) {
        return null;
    }
    CachedResolvedImpl { block: facts.block, bindings: bindings }
}

// port: baml_compiler2_hir_ty/src/impls.rs::package_impl_candidates @ d9be6853b
// Every impl block of `package` whose header resolved. Restructured: the
// source lane only (see the file header). Lazy, as Rust's iterator is: a
// search that stops at its first match must not resolve the facts of the
// blocks after it (a block's facts can depend on the search itself).
function package_impl_candidates(
    db: root.hir.Db,
    package: int,
) -> baml.iter.Iterator<Item = ResolvedImplFacts, Error = never> throws never {
    baml.iter.ArrayIterator.new(package_impl_locs(db, package)).iter().filter_map((block) -> {
        let facts = impl_header_resolution_resolved(impl_facts(db, block));
        if (facts != null) {
            ResolvedImplFacts { block: block, facts: facts }
        } else {
            null
        }
    })
}

// port: baml_compiler2_hir_ty/src/impls.rs::impl_candidates @ d9be6853b
// Every impl block implementing `interface_name`, drawn from the packages the
// goal's qualified names point into plus the interface's own package.
function impl_candidates(
    db: root.hir.Db,
    goal: int,
    interface_name: root.types.DeclName,
) -> ImplFacts[] throws never {
    let roots: int[] = [interface_name.pkg];
    collect_packages(root.hir.lang_roots(db), db.ty_memo.pool, goal, roots);
    let out: ImplFacts[] = [];
    for (let package in sorted_roots(roots)) {
        for (let block in package_impl_locs(db, package)) {
            let facts = impl_header_resolution_resolved(impl_facts(db, block));
            if (facts != null && facts.interface_.reference.name == interface_name) {
                out.push(facts);
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/impls.rs::all_impl_facts @ d9be6853b
// Every impl block `viewer` can see, for the method probe's candidates.
function all_impl_facts(db: root.hir.Db, viewer: int) -> ImplFacts[] throws never {
    root.hir.visible_packages(db, viewer).flat_map((package) -> {
        package_impl_locs(db, package).filter_map((block) -> {
            impl_header_resolution_resolved(impl_facts(db, block))
        })
    })
}

// port: baml_compiler2_hir_ty/src/impls.rs::STRUCTURAL_INTERFACES @ d9be6853b
// The language interfaces with a structural default: namespace, item, kind.
const STRUCTURAL_INTERFACES: (string[], string, root.types.StructuralInterface)[] = [
    ([], "ToString", root.types.StructuralInterface.ToString),
    ([], "ToJson", root.types.StructuralInterface.ToJson),
    ([], "FromJson", root.types.StructuralInterface.FromJson),
    (["ops"], "Equals", root.types.StructuralInterface.Equals),
    ([], "Hash", root.types.StructuralInterface.Hash),
    (["ops"], "Compare", root.types.StructuralInterface.Compare),
];

// port: baml_compiler2_hir_ty/src/impls.rs::is_json_alias @ d9be6853b
// Whether `name` is the stdlib's `baml.json.json`, never a user alias with
// the same spelling.
function is_json_alias(db: root.hir.Db, name: root.types.DeclName) -> bool throws never {
    root.hir.lang_roots(db).is_(root.base.LangPackage.Baml, name.pkg)
        && name.namespace == ["json"]
        && name.name == "json"
}

// port: baml_compiler2_hir_ty/src/impls.rs::structural_interface @ d9be6853b
// Recognizes the trusted language declarations, never user interfaces with
// the same spelling.
function structural_interface(
    db: root.hir.Db,
    name: root.types.DeclName,
) -> root.types.StructuralInterface? throws never {
    if (!root.hir.lang_roots(db).is_(root.base.LangPackage.Baml, name.pkg)) {
        return null;
    }
    STRUCTURAL_INTERFACES.find((entry) -> {
        name.namespace == entry.0 && name.name == entry.1
    })?.2
}

// port: baml_compiler2_hir_ty/src/impls.rs::structural_interface_roots @ d9be6853b
// The unconditional structural defaults. Conditional ones must prove the
// receiver's eligibility.
function structural_interface_roots(
    db: root.hir.Db,
) -> root.types.InferInterfaceConstraint[] throws never {
    let root_id = root.hir.lang_roots(db).get(root.base.LangPackage.Baml)
        ?? return [];
    STRUCTURAL_INTERFACES
        .filter((entry) -> {
            !root.types.structural_interface_is_conditional(entry.2)
        })
        .map((entry) -> {
            root.types.infer_interface_new(
                root.types.DeclName { pkg: root_id, namespace: entry.0, name: entry.1 },
                [],
                [],
            )
        })
}

// port: baml_compiler2_hir_ty/src/impls.rs::is_structural_interface @ d9be6853b
// Whether every admissible type implements this interface without a bound.
function is_structural_interface(
    db: root.hir.Db,
    interface_: root.types.InferInterfaceConstraint,
) -> bool throws never {
    if (interface_.generics.length() != 0 || interface_.associated_types.length() != 0) {
        return false;
    }
    let kind = structural_interface(db, interface_.name);
    kind != null && !root.types.structural_interface_is_conditional(kind)
}

// port: baml_compiler2_hir_ty/src/impls.rs::applicable_structural_interface_roots @ d9be6853b
// The structural roots `receiver` implements, in candidate order.
function applicable_structural_interface_roots(
    db: root.hir.Db,
    facts: Facts,
    receiver: int,
) -> root.types.InferInterfaceConstraint[] throws never {
    structural_interface_candidates(db).filter((interface_) -> {
        structural_root_applies(db, facts, receiver, interface_)
    })
}

// port: baml_compiler2_hir_ty/src/impls.rs::structural_interface_candidates @ d9be6853b
// Every structural root a receiver may implement, in the order
// `applicable_structural_interface_roots` reports them: unconditional roots
// first, then the conditional `Hash` and `Compare`. (Upstream's fix, after
// d9be6853b.)
function structural_interface_candidates(
    db: root.hir.Db,
) -> root.types.InferInterfaceConstraint[] throws never {
    let roots = structural_interface_roots(db);
    let hash = hash_interface_root(db);
    if (hash != null) {
        roots.push(hash);
    }
    let compare = compare_interface_root(db);
    if (compare != null) {
        roots.push(compare);
    }
    roots
}

// port: baml_compiler2_hir_ty/src/impls.rs::structural_root_applies @ d9be6853b
// Whether `receiver` implements a root from `structural_interface_candidates`.
// Deciding `Hash` walks the receiver's whole type graph, so a caller that only
// needs roots declaring some member filters on the member first. (Upstream's
// fix, after d9be6853b.)
function structural_root_applies(
    db: root.hir.Db,
    facts: Facts,
    receiver: int,
    interface_: root.types.InferInterfaceConstraint,
) -> bool throws never {
    match (structural_interface(db, interface_.name)) {
        root.types.StructuralInterface.Hash => hash_eligible(db, facts, receiver, interface_),
        root.types.StructuralInterface.Compare => {
            derived_tuple_compare(db, facts, receiver, interface_) == true
        },
        _ => true,
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::compare_interface_root @ d9be6853b
function compare_interface_root(
    db: root.hir.Db,
) -> root.types.InferInterfaceConstraint? throws never {
    let root_id = root.hir.lang_roots(db).get(root.base.LangPackage.Baml)
        ?? return null;
    root.types.infer_interface_new(
        root.types.DeclName { pkg: root_id, namespace: ["ops"], name: "Compare" },
        [],
        [],
    )
}

// port: baml_compiler2_hir_ty/src/impls.rs::conditional_structural_verdict @ d9be6853b
// The verdict of a conditional structural interface (`Hash`, `Compare`) for
// `ty`; null when the interface is not one, or carries arguments.
function conditional_structural_verdict(
    db: root.hir.Db,
    facts: Facts,
    ty: int,
    interface_: root.types.InferInterfaceConstraint,
) -> bool? throws never {
    if (interface_.generics.length() != 0 || interface_.associated_types.length() != 0) {
        return null;
    }
    match (structural_interface(db, interface_.name)) {
        root.types.StructuralInterface.Hash => hash_eligible(db, facts, ty, interface_),
        root.types.StructuralInterface.Compare => derived_tuple_compare(db, facts, ty, interface_),
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::derived_tuple_compare @ d9be6853b
// Whether a tuple derives `Compare` (every slot compares); null for a type
// that is not a tuple or an interface that is not `Compare`.
function derived_tuple_compare(
    db: root.hir.Db,
    facts: Facts,
    ty: int,
    compare: root.types.InferInterfaceConstraint,
) -> bool? throws never {
    let pool = db.ty_memo.pool;
    if (pool.has_infer(ty) || pool.has_error(ty)) {
        return null;
    }
    if (structural_interface(db, compare.name) != root.types.StructuralInterface.Compare) {
        return null;
    }
    let head = expand_alias_head(pool, ty, AliasOnlyFacts.new(db));
    if (!(pool.kinds[head] is root.types.InferTyTuple)) {
        return null;
    }
    derived_tuple_compare_slot(db, facts, head, compare, BLANKET_IMPL_BOUND_DEPTH)
}

// port: baml_compiler2_hir_ty/src/impls.rs::derived_tuple_compare::slot @ d9be6853b
function derived_tuple_compare_slot(
    db: root.hir.Db,
    facts: Facts,
    ty: int,
    compare: root.types.InferInterfaceConstraint,
    depth: int,
) -> bool throws never {
    let pool = db.ty_memo.pool;
    if (pool.has_infer(ty) || pool.has_error(ty)) {
        return false;
    }
    let eq = AliasOnlyFacts.new(db);
    let head = expand_alias_head(pool, ty, eq);
    let proves = (bound: root.types.InterfaceConstraint) -> bool {
        let reference = root.types.infer_interface_from_constraint(pool, bound);
        head_matches(reference, compare, eq)
            || interface_requires(db, reference, compare, head, REQUIRES_CLOSURE_FUEL)
    };
    match (pool.kinds[head]) {
        let tuple: root.types.InferTyTuple => {
            depth > 0
                && tuple.items.every((inner) -> {
                    derived_tuple_compare_slot(db, facts, inner, compare, depth - 1)
                })
        },
        let var: root.types.TyTypeVar => facts.type_var_bound(var.param).some(proves),
        let projection: root.types.InferTyAssociatedTypeProjection => {
            let interface_ = root.types.interface_try_from(pool, projection.interface_) catch (e) {
                root.types.OpenTy => {
                    return false;
                },
            };
            facts.associated_type_bound(interface_, projection.member).some(proves)
        },
        _ => resolve_impl(db, head, compare) != null,
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::hash_interface_root @ d9be6853b
function hash_interface_root(db: root.hir.Db) -> root.types.InferInterfaceConstraint? throws never {
    let root_id = root.hir.lang_roots(db).get(root.base.LangPackage.Baml)
        ?? return null;
    root.types.infer_interface_new(
        root.types.DeclName { pkg: root_id, namespace: [], name: "Hash" },
        [],
        [],
    )
}

// port: baml_compiler2_hir_ty/src/impls.rs::hash_eligible @ d9be6853b
// Proves data eligibility for `Hash` coinductively, while preserving explicit
// implementations. Also `hash_eligible_within_depth` (the worker; `depth`
// and `in_progress` default to the entry's values).
function hash_eligible(
    db: root.hir.Db,
    facts: Facts,
    concrete: int,
    hash: root.types.InferInterfaceConstraint,
    depth: int = BLANKET_IMPL_BOUND_DEPTH,
    in_progress: (int, root.types.InferInterfaceConstraint)[] = [],
) -> bool throws never {
    hash_eligible_within_depth_visit(db, facts, concrete, hash, [], depth, in_progress)
}

// port: baml_compiler2_hir_ty/src/impls.rs::hash_eligible_within_depth::visit @ d9be6853b
function hash_eligible_within_depth_visit(
    db: root.hir.Db,
    facts: Facts,
    ty: int,
    hash: root.types.InferInterfaceConstraint,
    active: int[],
    depth: int,
    in_progress: (int, root.types.InferInterfaceConstraint)[],
) -> bool throws never {
    let pool = db.ty_memo.pool;
    if (pool.has_infer(ty) || pool.has_error(ty)) {
        return false;
    }
    if let variant: root.types.TyEnumVariant = pool.kinds[ty] {
        return hash_eligible_within_depth_visit(
            db,
            facts,
            pool.add(root.types.TyEnum { name: variant.name }),
            hash,
            active,
            depth,
            in_progress,
        );
    }
    if let resolved: ResolvedImpl = resolve_within_depth(db, ty, hash, depth, in_progress) {
        in_progress.push((ty, hash));
        let proven = resolved.facts.facts.generic_params.every((entry) -> {
            let actual = resolved.bindings.get(entry.0)
                ?? return true;
            if (!pool.has_typevar(actual) && !pool.has_projection(actual)) {
                return true;
            }
            entry.1.every((bound) -> {
                let realized = root.types.infer_interface_map_types(bound.reference, (arg) -> {
                    pool.substitute_bindings(arg, resolved.bindings)
                });
                if (structural_interface(db, realized.name) == root.types.StructuralInterface.Hash) {
                    depth > 0
                        && hash_eligible_within_depth_visit(db, facts, actual, realized, [], depth - 1, in_progress)
                } else {
                    let closed_actual = root.types.ClosedTy.try_from(pool, actual) catch (e) {
                        root.types.OpenTy => baml.sys.panic("rigid subject is closed"),
                    };
                    let plain_actual = pool.to_plain_closed(closed_actual.ty);
                    let plain_bound = root.types.interface_try_from(pool, realized) catch (e) {
                        root.types.OpenTy => baml.sys.panic("rigid bound is closed"),
                    };
                    root.hir_ty.interfaces.normalized_arg_implements_bound(
                        facts,
                        plain_actual,
                        plain_bound,
                    )
                }
            })
        });
        in_progress.pop();
        if (proven) {
            return true;
        }
    }
    let equals = root.types.infer_interface_new(
        root.types.DeclName { pkg: hash.name.pkg, namespace: ["ops"], name: "Equals" },
        [],
        [],
    );
    let nominal = match (pool.kinds[ty]) {
        root.types.InferTyClass | root.types.TyEnum | root.types.TyEnumVariant => true,
        _ => false,
    };
    if (nominal && has_potential_custom_equals(db, ty, equals)) {
        return false;
    }
    if (active.includes(ty)) {
        return true;
    }
    // Expanding generic recursion need not repeat an identical realization.
    if (active.length() >= REQUIRES_CLOSURE_FUEL) {
        return false;
    }
    active.push(ty);
    let visit = (inner: int) -> bool {
        hash_eligible_within_depth_visit(db, facts, inner, hash, active, depth, in_progress)
    };
    let bound_proves = (bound: root.types.InferInterfaceConstraint) -> bool {
        head_matches(bound, hash, AliasOnlyFacts.new(db))
            || interface_requires(db, bound, hash, ty, REQUIRES_CLOSURE_FUEL)
    };
    let result = match (pool.kinds[ty]) {
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyBool
            | root.types.TyString
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyLiteral
            | root.types.TyEnum
            | root.types.TyEnumVariant
            | root.types.TyNever =>
        {
            true
        },
        let list: root.types.InferTyList => visit(list.elem),
        let m: root.types.InferTyMap => visit(m.key) && visit(m.value),
        let u: root.types.InferTyUnion => u.members.every(visit),
        let class_: root.types.InferTyClass => {
            let class_ref = class_ref_of(db, class_.name);
            if (class_ref == null) {
                false
            } else {
                let params = class_generic_params(db, class_ref);
                if (params.length() != class_.args.length()) {
                    false
                } else {
                    let bindings: map<root.types.ParamTy, int> = {};
                    for (let i = 0; i < params.length(); i += 1) {
                        bindings[params[i]] = class_.args[i];
                    }
                    class_fields(db, class_ref).every((field) -> {
                        visit(pool.substitute_bindings(pool.from_plain(field.1), bindings))
                    })
                }
            }
        },
        let alias: root.types.TyTypeAlias => {
            let body = facts.alias_def(alias.name);
            body != null && visit(pool.from_plain(body))
        },
        let var: root.types.TyTypeVar => {
            facts.type_var_bound(var.param).some((bound) -> {
                bound_proves(root.types.infer_interface_from_constraint(pool, bound))
            })
        },
        let existential: root.types.InferTyInterface => {
            bound_proves(
                root.types.infer_interface_new(
                    existential.name,
                    existential.args,
                    existential.associated_types,
                ),
            )
        },
        let projection: root.types.InferTyAssociatedTypeProjection => {
            let interface_ = root.types.interface_try_from(pool, projection.interface_) catch (e) {
                root.types.OpenTy => baml.sys.panic("admissible projection is closed"),
            };
            facts.associated_type_bound(interface_, projection.member).some((bound) -> {
                bound_proves(root.types.infer_interface_from_constraint(pool, bound))
            })
        },
        _ => false,
    };
    active.pop();
    result
}

// port: baml_compiler2_hir_ty/src/impls.rs::has_potential_custom_equals @ d9be6853b
// Whether an `Equals` impl providing `eq` may overlap `concrete`. Bounds
// cannot establish the absence of an override (negative reasoning could
// recurse from `Equals` back into `Hash`).
function has_potential_custom_equals(
    db: root.hir.Db,
    concrete: int,
    equals: root.types.InferInterfaceConstraint,
) -> bool throws never {
    let closed = root.types.ClosedTy.try_from(db.ty_memo.pool, concrete) catch (e) {
        root.types.OpenTy => baml.sys.panic("eligibility receiver is closed"),
    };
    for (let package in search_roots(db, concrete, equals)) {
        for (let facts in package_impl_candidates(db, package)) {
            if (
                facts.facts.interface_.reference.name == equals.name
                    && ResolvedImpl { facts: facts, bindings: {} }.provided_method(db, "eq") != null
                    && heads_may_overlap(db, package, facts.facts.for_ty_pattern, closed)
            ) {
                return true;
            }
        }
    }
    false
}

// port: baml_compiler2_hir_ty/src/impls.rs::implements_interface @ d9be6853b
// Whether `concrete` implements `interface_`, explicitly or by a structural
// default.
function implements_interface(
    db: root.hir.Db,
    concrete: int,
    interface_: root.types.InferInterfaceConstraint,
) -> bool throws never {
    resolve_implementation(db, concrete, interface_) != null
}

// port: baml_compiler2_hir_ty/src/impls.rs::ResolvedImplementation @ d9be6853b
// An implementation witness, without inventing a source block for builtin
// behavior.
type ResolvedImplementation = ResolvedImplementationExplicit
    | ResolvedImplementationStructuralDefault;

class ResolvedImplementationExplicit {
    value: ResolvedImpl,
}

class ResolvedImplementationStructuralDefault {
    value: root.types.StructuralInterface,
}

// port: baml_compiler2_hir_ty/src/impls.rs::resolve_implementation @ d9be6853b
// Explicit implementations first, then the language-provided structural
// default.
function resolve_implementation(
    db: root.hir.Db,
    concrete: int,
    interface_: root.types.InferInterfaceConstraint,
) -> ResolvedImplementation? throws never {
    let implementation = resolve_impl(db, concrete, interface_);
    if (implementation != null) {
        return ResolvedImplementationExplicit { value: implementation };
    }
    let pool = db.ty_memo.pool;
    if (
        pool.has_infer(concrete)
            || pool.has_error(concrete)
            || interface_.generics.length() != 0
            || interface_.associated_types.length() != 0
    ) {
        return null;
    }
    let kind = structural_interface(db, interface_.name)
        ?? return null;
    if (
        root.types.structural_interface_is_conditional(kind)
            && conditional_structural_verdict(db, Facts.new(db), concrete, interface_) != true
    ) {
        return null;
    }
    ResolvedImplementationStructuralDefault { value: kind }
}

// port: baml_compiler2_hir_ty/src/impls.rs::resolve_impl @ d9be6853b
// The unique explicit impl by which realized `concrete` implements realized
// `interface_`, with bindings. Rigid vars are legal in goals; inference
// variables and error sentinels are not.
function resolve_impl(
    db: root.hir.Db,
    concrete: int,
    interface_: root.types.InferInterfaceConstraint,
) -> ResolvedImpl? throws never {
    let pool = db.ty_memo.pool;
    let admissible = (ty: int) -> bool {
        !pool.has_infer(ty) && !pool.has_error(ty)
    };
    if (
        !admissible(concrete)
            || !interface_.generics.every(admissible)
            || !interface_.associated_types.every((pin) -> {
                admissible(pin.ty)
            })
    ) {
        return null;
    }
    let head = expand_alias_head(pool, concrete, AliasOnlyFacts.new(db));
    // A literal-typed value implements what its base primitive does.
    if let literal: root.types.TyLiteral = pool.kinds[head] {
        return resolve_impl(db, pool.add(literal_base(literal.value)), interface_);
    }
    resolve_within_depth(db, head, interface_, BLANKET_IMPL_BOUND_DEPTH, [])
}

// port: baml_compiler2_hir_ty/src/impls.rs::expand_alias_head @ d9be6853b
// `ty` with its alias head unfolded to the type it denotes. Restructured:
// takes the pool.
function expand_alias_head(
    pool: root.types.InferPool,
    ty: int,
    aliases: root.types.TypeContext,
) -> int throws never {
    let head = ty;
    // Bounded: an alias chain leading back to itself is rejected at its
    // declaration (E0068).
    for (let i = 0; i < 64; i += 1) {
        let alias = match (pool.kinds[head]) {
            let a: root.types.TyTypeAlias => a,
            _ => null,
        };
        if (alias == null) {
            break;
        }
        let expanded = aliases.alias_def(alias.name);
        if (expanded == null) {
            break;
        }
        head = pool.from_plain(expanded);
    }
    head
}

// port: baml_compiler2_hir_ty/src/impls.rs::unfold_aliases_against @ d9be6853b
// `target` with an alias unfolded wherever `pattern` has structure at the
// same position, so selection's alias-blind unifier meets the type the alias
// denotes. A position under a pattern variable keeps its spelling.
// Restructured: takes the pool.
function unfold_aliases_against(
    pool: root.types.InferPool,
    pattern: int,
    target: int,
    aliases: root.types.TypeContext,
) -> int throws never {
    match (pool.kinds[pattern]) {
        root.types.TyTypeVar | root.types.TyInferVar => {
            return target;
        },
        _ => {},
    }
    let target_head = expand_alias_head(pool, target, aliases);
    let pattern_children = root.types.children_infer_ty(pool.kinds[pattern]);
    let target_kind = pool.kinds[target_head];
    if (
        pattern_children.length() == 0
            || root.types.children_infer_ty(target_kind).length() != pattern_children.length()
            || root.types.infer_ty_discriminant(pool.kinds[pattern])
                != root.types.infer_ty_discriminant(target_kind)
    ) {
        return target_head;
    }
    let next = 0;
    pool.add(
        root.types.map_children(target_kind, (child) -> {
            let child_pattern = pattern_children[next];
            next += 1;
            unfold_aliases_against(pool, child_pattern, child, aliases)
        }),
    )
}

// port: baml_compiler2_hir_ty/src/impls.rs::is_realized @ d9be6853b
function is_realized(pool: root.types.InferPool, ty: int) -> bool throws never {
    !pool.has_infer(ty) && !pool.has_typevar(ty) && !pool.has_error(ty)
}

// port: baml_compiler2_hir_ty/src/impls.rs::resolve_within_depth @ d9be6853b
// Impl selection with rustc's obligation-stack cycle detection: a goal
// already being resolved on this path fails inductively; the depth budget is
// the backstop for growing chains.
function resolve_within_depth(
    db: root.hir.Db,
    concrete: int,
    interface_: root.types.InferInterfaceConstraint,
    depth: int,
    in_progress: (int, root.types.InferInterfaceConstraint)[],
) -> ResolvedImpl? throws never {
    let pool = db.ty_memo.pool;
    let eq = AliasOnlyFacts.memoized(db);
    // A bound discharged below binds an impl variable to whatever the subject
    // spelled there, an alias included.
    let head = expand_alias_head(pool, concrete, eq);
    if (
        in_progress.some((entry) -> {
            entry.0 == head && entry.1 == interface_
        })
    ) {
        return null;
    }
    // Compiler-derived membership applies before the blanket rule.
    if (!derived_impl_allows(db, head, interface_.name)) {
        return null;
    }
    in_progress.push((head, interface_));
    let resolved: ResolvedImpl? = null;
    for (let package in search_roots(db, head, interface_)) {
        for (let facts in package_impl_candidates(db, package)) {
            let bindings = match_impl_head(db, facts, head, interface_, eq);
            if (bindings == null || !bounds_hold(db, facts, bindings, depth, in_progress)) {
                continue;
            }
            resolved = ResolvedImpl { facts: facts, bindings: bindings };
            break;
        }
        if (resolved != null) {
            break;
        }
    }
    in_progress.pop();
    resolved
}

// port: baml_compiler2_hir_ty/src/impls.rs::search_roots @ d9be6853b
// Every package a qualified name on either side points into: the orphan rule
// guarantees the impl lives in one of them.
function search_roots(
    db: root.hir.Db,
    concrete: int,
    interface_: root.types.InferInterfaceConstraint,
) -> int[] throws never {
    let lang = root.hir.lang_roots(db);
    let pool = db.ty_memo.pool;
    let roots: int[] = [interface_.name.pkg];
    collect_packages(lang, pool, concrete, roots);
    for (let arg in interface_.generics) {
        collect_packages(lang, pool, arg, roots);
    }
    sorted_roots(roots)
}

// port: baml_compiler2_hir_ty/src/impls.rs::search_roots @ d9be6853b
// `roots.sort(); roots.dedup();` over root ids.
function sorted_roots(roots: int[]) -> int[] throws never {
    let out: int[] = [];
    for (
        let root_id in roots.sort_by_key((r) -> {
            r
        })
    ) {
        if (out.length() == 0 || out[out.length() - 1] != root_id) {
            out.push(root_id);
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/impls.rs::collect_packages @ d9be6853b
// The packages qualified names in `ty` point into; primitives and structural
// types live in the stdlib package. Restructured: takes the pool.
function collect_packages(
    lang: root.base.LangRoots,
    pool: root.types.InferPool,
    ty: int,
    out: int[],
) -> void throws never {
    let kind = pool.kinds[ty];
    match (kind) {
        let x: root.types.InferTyClass => {
            out.push(x.name.pkg);
        },
        let x: root.types.InferTyInterface => {
            out.push(x.name.pkg);
        },
        let x: root.types.TyEnum => {
            out.push(x.name.pkg);
        },
        let x: root.types.TyEnumVariant => {
            out.push(x.name.pkg);
        },
        let x: root.types.TyTypeAlias => {
            out.push(x.name.pkg);
        },
        _ => {},
    }
    let structural = match (kind) {
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.InferTyList
            | root.types.InferTyMap
            | root.types.InferTyFuture
            | root.types.TyLiteral =>
        {
            true
        },
        _ => false,
    };
    if (structural) {
        let baml = lang.get(root.base.LangPackage.Baml);
        if (baml != null) {
            out.push(baml);
        }
    }
    for (let child in root.types.children_infer_ty(kind)) {
        collect_packages(lang, pool, child, out);
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::match_impl_head @ d9be6853b
// Structural head match: exact interface, joint unification of the
// for-target and every interface arg against one shared binding set, then
// the associated-pin gate. Declared bounds are not checked here.
function match_impl_head(
    db: root.hir.Db,
    facts: ResolvedImplFacts,
    concrete: int,
    interface_: root.types.InferInterfaceConstraint,
    eq: AliasOnlyFacts,
) -> map<root.types.ParamTy, int>? throws never {
    let pool = db.ty_memo.pool;
    let header = facts.facts.interface_.reference;
    if (header.name != interface_.name || header.generics.length() != interface_.generics.length()) {
        return null;
    }
    let pattern = facts.facts.for_ty_pattern.ty;
    let params = facts.facts.generic_params.map((param) -> {
        param.0
    });
    // Bare-blanket guard: `implement<T> I for T` applies only to concrete
    // receivers.
    if let var: root.types.TyTypeVar = pool.kinds[pattern] {
        if (params.includes(var.param) && !is_concrete_receiver(pool, concrete)) {
            return null;
        }
    }
    let bindings: map<root.types.ParamTy, int> = {};
    if (!match_pattern(pool, pattern, concrete, params, bindings, eq)) {
        return null;
    }
    for (let i = 0; i < header.generics.length(); i += 1) {
        if (!match_pattern(pool, header.generics[i], interface_.generics[i], params, bindings, eq)) {
            return null;
        }
    }
    // Every pin the request carries must equal what this impl realizes for
    // that member (its binding, else the interface default), compared after
    // reducing ground projections.
    for (let pin in interface_.associated_types) {
        let declared = facts.facts.associated_types.find((entry) -> {
            entry.0 == pin.name
        });
        let supplied = if (declared != null) {
            pool.substitute_bindings(declared.1.ty, bindings)
        } else {
            let implemented = root.types.infer_interface_map_types(header, (ty) -> {
                pool.substitute_bindings(ty, bindings)
            });
            realized_assoc_default(db, implemented, concrete, pin.name)
        };
        if (supplied == null) {
            return null;
        }
        let supplied_reduced = reduce_ground_projections(db, supplied, 8);
        let requested = reduce_ground_projections(db, pin.ty, 8);
        if (!eq_admitted(pool, supplied_reduced, requested, eq)) {
            return null;
        }
    }
    bindings
}

// port: baml_compiler2_hir_ty/src/impls.rs::reduce_ground_projections @ d9be6853b
// Fuel-bounded projection reduction over ground types for the registry
// matcher. Var-carrying input returns unchanged.
function reduce_ground_projections(db: root.hir.Db, ty: int, fuel: int) -> int throws never {
    if (db.ty_memo.pool.has_infer(ty)) {
        return ty;
    }
    reduce_closed_projections(Facts.new(db), ty, fuel)
}

// port: baml_compiler2_hir_ty/src/impls.rs::reduce_closed_projections @ d9be6853b
// `reduce_ground_projections` against the caller's facts, node by node: each
// projection with no inference variable of its own reduces.
function reduce_closed_projections(facts: Facts, ty: int, fuel: int) -> int throws never {
    let pool = facts.db.ty_memo.pool;
    if (fuel == 0 || !pool.has_projection(ty)) {
        return ty;
    }
    let rebuilt = pool.add(
        root.types.map_children(pool.kinds[ty], (child) -> {
            reduce_closed_projections(facts, child, fuel)
        }),
    );
    if (pool.has_infer(rebuilt)) {
        return rebuilt;
    }
    if let projection: root.types.InferTyAssociatedTypeProjection = pool.kinds[rebuilt] {
        let plain_interface = root.types.InterfaceConstraint {
            name: projection.interface_.name,
            generics: projection.interface_.generics.map((arg) -> {
                pool.to_plain_closed(arg)
            }),
            associated_types: projection.interface_.associated_types
                .map((pin) -> {
                    root.types.AssociatedType { name: pin.name, ty: pool.to_plain_closed(pin.ty) }
                })
                .sort_by_key((pin) -> {
                    pin.name
                }),
        };
        match (
            facts.project(
                pool.to_plain_closed(projection.base),
                plain_interface,
                projection.member,
                fuel,
            )
        ) {
            let step: root.types.ProjectionStepReduced => {
                return reduce_closed_projections(facts, pool.from_plain(step.ty), fuel - 1);
            },
            root.types.ProjectionStepOpaque => {},
        }
    }
    rebuilt
}

// port: baml_compiler2_hir_ty/src/impls.rs::match_pattern @ d9be6853b
// The one-directional pattern matcher: impl params bind, ground positions
// compare via the fact-poor equality, structural heads decompose. A literal
// target matches its base-primitive pattern, an enum-variant target its
// enum's. Restructured: takes the pool.
function match_pattern(
    pool: root.types.InferPool,
    pattern: int,
    target: int,
    params: root.types.ParamTy[],
    bindings: map<root.types.ParamTy, int>,
    eq: AliasOnlyFacts,
) -> bool throws never {
    if let var: root.types.TyTypeVar = pool.kinds[pattern] {
        if (params.includes(var.param)) {
            let bound = bindings.get(var.param);
            if (bound != null) {
                return eq_admitted(pool, bound, target, eq);
            }
            bindings[var.param] = target;
            return true;
        }
    }
    if (!pool.has_typevar(pattern)) {
        return eq_admitted(pool, pattern, target, eq);
    }
    // Substitute-and-compare escape: a pattern whose vars are all bound
    // compares semantically.
    if (pattern_fully_bound(pool, pattern, params, bindings)) {
        if (eq_admitted(pool, pool.substitute_bindings(pattern, bindings), target, eq)) {
            return true;
        }
    }
    // The pattern has structure here, so the target is matched for what an
    // alias spelling it denotes.
    let head = expand_alias_head(pool, target, eq);
    let each = (ps: int[], ts: int[]) -> bool {
        ps.length() == ts.length()
            && baml.Array
                .generate(ps.length(), (i) -> {
                    i
                })
                .every((i) -> {
                    match_pattern(pool, ps[i], ts[i], params, bindings, eq)
                })
    };
    match (pool.kinds[pattern], pool.kinds[head]) {
        (let p: root.types.InferTyClass, let t: root.types.InferTyClass) => {
            p.name == t.name && each(p.args, t.args)
        },
        (let p: root.types.InferTyInterface, let t: root.types.InferTyInterface) => {
            p.name == t.name
                && each(p.args, t.args)
                && t.associated_types.every((target_pin) -> {
                    p.associated_types.some((pattern_pin) -> {
                        pattern_pin.name == target_pin.name
                            && match_pattern(pool, pattern_pin.ty, target_pin.ty, params, bindings, eq)
                    })
                })
        },
        (let p: root.types.InferTyList, let t: root.types.InferTyList) => {
            match_pattern(pool, p.elem, t.elem, params, bindings, eq)
        },
        (let p: root.types.InferTyTuple, let t: root.types.InferTyTuple) => each(p.items, t.items),
        (let p: root.types.InferTyMap, let t: root.types.InferTyMap) => {
            match_pattern(pool, p.key, t.key, params, bindings, eq)
                && match_pattern(pool, p.value, t.value, params, bindings, eq)
        },
        (let p: root.types.InferTyFuture, let t: root.types.InferTyFuture) => {
            match_pattern(pool, p.value, t.value, params, bindings, eq)
                && match_pattern(pool, p.error, t.error, params, bindings, eq)
        },
        (let p: root.types.InferTyUnion, let t: root.types.InferTyUnion) => {
            match_union_members(pool, p.members, t.members, params, bindings, eq)
        },
        (let p: root.types.InferTyFunction, let t: root.types.InferTyFunction) => {
            p.params.length() == t.params.length()
                && baml.Array
                    .generate(p.params.length(), (i) -> {
                        i
                    })
                    .every((i) -> {
                        p.params[i].mode == t.params[i].mode
                            && match_pattern(pool, p.params[i].ty, t.params[i].ty, params, bindings, eq)
                    })
                && match_pattern(pool, p.ret, t.ret, params, bindings, eq)
                && match_pattern(pool, p.throws_, t.throws_, params, bindings, eq)
        },
        // Widenings: a literal target matches its base primitive; an
        // enum-variant target matches its enum.
        (root.types.TyInt, let t: root.types.TyLiteral) => t.value is root.base.LiteralInt,
        (root.types.TyBigint, let t: root.types.TyLiteral) => t.value is root.base.LiteralBigint,
        (root.types.TyFloat, let t: root.types.TyLiteral) => t.value is root.base.LiteralFloat,
        (root.types.TyString, let t: root.types.TyLiteral) => t.value is root.base.LiteralString,
        (root.types.TyBool, let t: root.types.TyLiteral) => t.value is root.base.LiteralBool,
        (let p: root.types.TyEnum, let t: root.types.TyEnumVariant) => p.name == t.name,
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/impls.rs::match_union_members @ d9be6853b
// Order-insensitive union cover: every pattern member claims a distinct
// target member (backtracking search; unions are small).
function match_union_members(
    pool: root.types.InferPool,
    pattern_members: int[],
    target_members: int[],
    params: root.types.ParamTy[],
    bindings: map<root.types.ParamTy, int>,
    eq: AliasOnlyFacts,
) -> bool throws never {
    if (pattern_members.length() != target_members.length()) {
        return false;
    }
    let used = baml.Array.generate(target_members.length(), (i) -> {
        false
    });
    match_union_members_search(pool, pattern_members, target_members, used, params, bindings, eq)
}

// port: baml_compiler2_hir_ty/src/impls.rs::match_union_members::search @ d9be6853b
function match_union_members_search(
    pool: root.types.InferPool,
    patterns: int[],
    targets: int[],
    used: bool[],
    params: root.types.ParamTy[],
    bindings: map<root.types.ParamTy, int>,
    eq: AliasOnlyFacts,
) -> bool throws never {
    if (patterns.length() == 0) {
        return true;
    }
    let pattern = patterns[0];
    let rest = patterns.slice(1, patterns.length());
    for (let index = 0; index < targets.length(); index += 1) {
        if (used[index]) {
            continue;
        }
        let saved = copy_impl_bindings(bindings);
        if (match_pattern(pool, pattern, targets[index], params, bindings, eq)) {
            used[index] = true;
            if (match_union_members_search(pool, rest, targets, used, params, bindings, eq)) {
                return true;
            }
            used[index] = false;
        }
        // `*bindings = saved`, in place.
        bindings.clear();
        for (let key in saved.keys()) {
            bindings[key] = saved[key];
        }
    }
    false
}

// port: baml_compiler2_hir_ty/src/impls.rs::match_union_members @ d9be6853b
// Rust's derived `Clone` of an impl binding map.
function copy_impl_bindings(
    bindings: map<root.types.ParamTy, int>,
) -> map<root.types.ParamTy, int> throws never {
    let out: map<root.types.ParamTy, int> = {};
    for (let key in bindings.keys()) {
        out[key] = bindings[key];
    }
    out
}

// port: baml_compiler2_hir_ty/src/impls.rs::pattern_fully_bound @ d9be6853b
// Whether every impl param `pattern` mentions is bound. Restructured: the
// `walk` with its `&mut bool` is a recursive `every`.
function pattern_fully_bound(
    pool: root.types.InferPool,
    pattern: int,
    params: root.types.ParamTy[],
    bindings: map<root.types.ParamTy, int>,
) -> bool throws never {
    let kind = pool.kinds[pattern];
    if let var: root.types.TyTypeVar = kind {
        if (params.includes(var.param) && !bindings.has(var.param)) {
            return false;
        }
    }
    root.types.children_infer_ty(kind).every((child) -> {
        pattern_fully_bound(pool, child, params, bindings)
    })
}

// port: baml_compiler2_hir_ty/src/impls.rs::matched_impl_facts @ d9be6853b
// The facts of a matched block: total, a block reaches a resolution only
// through a header that resolved.
function matched_impl_facts(db: root.hir.Db, block: int) -> ResolvedImplFacts throws never {
    let facts = impl_header_resolution_resolved(impl_facts(db, block))
        ?? baml.sys.panic("a matched impl's header resolved");
    ResolvedImplFacts { block: block, facts: facts }
}

// port: baml_compiler2_hir_ty/src/impls.rs::bounds_hold @ d9be6853b
// Verifies a matched impl's declared bounds at the realized bindings.
// Unbound or still-symbolic bounds are vacuous (the caller's obligation);
// realized ones recurse with the budget.
function bounds_hold(
    db: root.hir.Db,
    facts: ResolvedImplFacts,
    bindings: map<root.types.ParamTy, int>,
    depth: int,
    in_progress: (int, root.types.InferInterfaceConstraint)[],
) -> bool throws never {
    let pool = db.ty_memo.pool;
    for (let entry in facts.facts.generic_params) {
        let actual = bindings.get(entry.0);
        if (actual == null) {
            continue;
        }
        for (let declared in entry.1) {
            let bound = root.types.infer_interface_map_types(declared.reference, (ty) -> {
                pool.substitute_bindings(ty, bindings)
            });
            if (
                !is_realized(pool, actual)
                    || !bound.generics.every((arg) -> {
                        is_realized(pool, arg)
                    })
            ) {
                continue;
            }
            if (structural_interface(db, bound.name) == root.types.StructuralInterface.Hash) {
                if (
                    depth == 0
                        || !hash_eligible(
                            db,
                            Facts.new(db),
                            actual,
                            bound,
                            depth = depth - 1,
                            in_progress = in_progress,
                        )
                ) {
                    return false;
                }
                continue;
            }
            let eligible = derived_tuple_compare(db, Facts.new(db), actual, bound);
            if (eligible != null) {
                if (!eligible) {
                    return false;
                }
                continue;
            }
            if (
                !is_structural_interface(db, bound)
                    && (
                        depth == 0
                            || resolve_within_depth(db, actual, bound, depth - 1, in_progress)
                                == null
                    )
            ) {
                return false;
            }
        }
    }
    true
}

// port: baml_compiler2_hir_ty/src/impls.rs::requires_heads @ d9be6853b
// The root plus its transitive `requires` closure: the candidate head set
// every consumer walks.
function requires_heads(
    db: root.hir.Db,
    root_: root.types.InferInterfaceConstraint,
    self_ty: int,
    fuel: int,
) -> root.types.InferInterfaceConstraint[] throws never {
    [root_].concat(direct_requires_closure(db, root_, self_ty, fuel))
}

// port: baml_compiler2_hir_ty/src/impls.rs::head_matches @ d9be6853b
// Whether a carried or closure head answers for `want`: same interface, same
// arity, args equivalent under the fact-poor oracle. Pins are not part of
// the relation.
function head_matches(
    have: root.types.InferInterfaceConstraint,
    want: root.types.InferInterfaceConstraint,
    eq: AliasOnlyFacts,
) -> bool throws never {
    let pool = eq.db.ty_memo.pool;
    have.name == want.name
        && have.generics.length() == want.generics.length()
        && baml.Array
            .generate(have.generics.length(), (i) -> {
                i
            })
            .every((i) -> {
                eq_admitted(pool, have.generics[i], want.generics[i], eq)
            })
}

// port: baml_compiler2_hir_ty/src/impls.rs::head_satisfies @ d9be6853b
// Whether `have` satisfies `want`: the shared head relation, plus every pin
// `want` demands present on `have` and equal (normalize-then-compare).
function head_satisfies(
    db: root.hir.Db,
    have: root.types.InferInterfaceConstraint,
    want: root.types.InferInterfaceConstraint,
    eq: AliasOnlyFacts,
) -> bool throws never {
    let pool = db.ty_memo.pool;
    head_matches(have, want, eq)
        && want.associated_types.every((want_pin) -> {
            have.associated_types.some((have_pin) -> {
                if (have_pin.name != want_pin.name) {
                    return false;
                }
                eq_admitted(
                    pool,
                    reduce_ground_projections(db, have_pin.ty, 8),
                    reduce_ground_projections(db, want_pin.ty, 8),
                    eq,
                )
            })
        })
}

// port: baml_compiler2_hir_ty/src/impls.rs::direct_requires_closure @ d9be6853b
// The realized direct-plus-transitive `requires` closure of an interface
// reference (excluding itself), fuel-bounded, elaborated for subject
// `self_ty`.
function direct_requires_closure(
    db: root.hir.Db,
    root_: root.types.InferInterfaceConstraint,
    self_ty: int,
    fuel: int,
) -> root.types.InferInterfaceConstraint[] throws never {
    let out: root.types.InferInterfaceConstraint[] = [];
    let queue = [root_];
    let budget = fuel;
    while let current: root.types.InferInterfaceConstraint = queue.pop() {
        if (budget == 0) {
            break;
        }
        budget -= 1;
        for (let required in direct_requires(db, current, self_ty)) {
            if (required.name != root_.name && !out.includes(required)) {
                out.push(required);
                queue.push(required);
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/impls.rs::direct_requires @ d9be6853b
// The realized direct `requires` targets of `of` for subject `self_ty`,
// lowered in the full interface frame. Not ported: the mounted-row branch
// (the row's `requires` is not ported; see the file header).
function direct_requires(
    db: root.hir.Db,
    of: root.types.InferInterfaceConstraint,
    self_ty: int,
) -> root.types.InferInterfaceConstraint[] throws never {
    let pool = db.ty_memo.pool;
    let (let interface_, let data) = assoc_realization_env(db, of)
        ?? return [];
    let ctx = lower_ctx_for_file(db, db.interface_locs.get(interface_).file)
        .with_frame(interface_frame(db, interface_))
        .with_bounds(interface_scope_bounds(db, interface_));
    let instantiation = interface_instantiation(self_ty, of, data.generic_params.length())
        ?? return [];
    data.requires_.filter_map((required) -> {
        let lowered = reject_holes(ctx.lower_type_ref(data.type_refs, required, position = TypePosition.ConstraintHead));
        let target = root.types.infer_interface_of_ty(pool, pool.from_plain(lowered));
        if (target == null) {
            null
        } else {
            root.types.infer_interface_new(
                target.name,
                target.generics.map((arg) -> {
                    substitute_params(pool, arg, instantiation)
                }),
                target.associated_types.map((pin) -> {
                    root.types.InferAssociatedType {
                        name: pin.name,
                        ty: substitute_params(pool, pin.ty, instantiation),
                    }
                }),
            )
        }
    })
}

// port: baml_compiler2_hir_ty/src/impls.rs::interface_requires @ d9be6853b
// The transitive `requires` closure: whether interface `sub` (with its
// realized args) requires `sup`, for subject `self_ty`. Also
// `interface_requires_inner` (the worker; `visited` defaults empty).
function interface_requires(
    db: root.hir.Db,
    sub: root.types.InferInterfaceConstraint,
    sup: root.types.InferInterfaceConstraint,
    self_ty: int,
    fuel: int,
    visited: root.types.InferInterfaceConstraint[] = [],
) -> bool throws never {
    if (fuel == 0) {
        return false;
    }
    // A `requires` loop revisits a realized head: no new facts lie that way.
    if (visited.includes(sub)) {
        return false;
    }
    visited.push(sub);
    let eq = AliasOnlyFacts.new(db);
    let holds = false;
    for (let required in direct_requires(db, sub, self_ty)) {
        // Satisfies, not merely matches: the required reference must carry
        // every pin `sup` demands.
        if (
            head_satisfies(db, required, sup, eq)
                || interface_requires(db, required, sup, self_ty, fuel - 1, visited = visited)
        ) {
            holds = true;
            break;
        }
    }
    visited.pop();
    holds
}
