// port: baml_compiler2_hir_ty/src/method_resolution.rs @ d9be6853b
//
// Method resolution: receiver type to member candidate. A receiver resolves
// to one owning class (its own, or the language's builtin class for a
// structural type); then interface members, through bounds for symbolic
// receivers and through matched impls for concrete ones; then fields.
//
// Hash eligibility: `lookup_impl_member` and `union_arm_interfaces` take
// upstream's fixed shape (after d9be6853b): a structural root is proven
// (`structural_root_applies`) only once it declares the looked-up member.
// Results are identical (see impls.baml's header).
//
// Restructured:
// - Interned types are `int`s into `db.ty_memo.pool` (see impls.baml).
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so `FunctionRef`, `ImplRef` and `InterfaceRef` are their Source lane, an
//   `int` loc, and the mounted/External arms (`mounted_class_method`,
//   `mounted_interface_loc`, `extern_interface_row`, ...) are dropped.
// - Data enums are unions of classes named `<Enum><Variant>`; Rust's
//   `Result<Ty, Vec<Ty>>` is `int | int[]`.
// - `prefer_explicit_members` returns the kept candidates instead of
//   retaining in place.
// - `member_owner` is baml_type's (compiler_aliases.rs); it lives here
//   because this package may not add to `ns_types`.
//
// Not ported: the IDE enumeration (`member_candidates`,
// `type_member_candidates`, `declared_methods`, `interface_member_rows`,
// their `MemberCandidate`/`MemberDecl`/`MemberSource` and helpers, and
// `impls_of_type`), whose only callers are ide.rs and baml_ide; and
// `interface_frame` (a forward to lower's).

// port: baml_compiler2_hir_ty/src/method_resolution.rs::MethodCandidate @ d9be6853b
// One resolved class-inherent method plus the receiver-driven instantiation
// of its owning class's generic params.
class MethodCandidate {
    method: int,
    class_args: int[],
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::lookup_method @ d9be6853b
// Finds `name` among the inherent methods of `receiver`'s owning class.
function lookup_method(
    db: root.hir.Db,
    facts: Facts,
    receiver: int,
    name: string,
) -> MethodCandidate? throws never {
    let (let class_, let class_args) = receiver_class(facts, receiver, 8)
        ?? return null;
    let method = root.hir.class_data(db, class_).methods.find((method) -> {
        root.hir.function_data(db, method).name == name
    })
        ?? return null;
    MethodCandidate { method: method, class_args: class_args }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::external_class_for_type @ d9be6853b
// The member owner of `receiver`: its class declaration's name and the
// generic arguments the receiver pins. Aliases are transparent
// (fuel-bounded); builtins map through the compiler alias registry.
function external_class_for_type(
    facts: Facts,
    receiver: int,
    fuel: int,
) -> (root.types.DeclName, int[])? throws never {
    let pool = facts.db.ty_memo.pool;
    match (pool.kinds[receiver]) {
        let class_: root.types.InferTyClass => (class_.name, class_.args),
        let alias: root.types.TyTypeAlias => {
            let expanded = facts.alias_def(alias.name)
                ?? return null;
            if (fuel == 0) {
                return null;
            }
            external_class_for_type(facts, pool.from_plain(expanded), fuel - 1)
        },
        _ => member_owner(root.hir.lang_roots(facts.db), pool, receiver),
    }
}

// port: baml_type/src/compiler_aliases.rs::member_owner @ d9be6853b
// The carrier class that owns a structural receiver's members and the
// arguments the receiver pins; a literal defers to its base primitive.
// Restructured: also `Definition::decl_name` (the carrier's head under
// `lang`, null when its package is not installed); the registry's
// definitions are spelled as in compiler_aliases.baml.
function member_owner(
    lang: root.base.LangRoots,
    pool: root.types.InferPool,
    receiver: int,
) -> (root.types.DeclName, int[])? throws never {
    let (let spelling, let args) = match (pool.kinds[receiver]) {
        root.types.TyInt => ("int", []),
        root.types.TyBigint => ("bigint", []),
        root.types.TyFloat => ("float", []),
        root.types.TyString => ("string", []),
        root.types.TyBool => ("bool", []),
        root.types.TyNull => ("null", []),
        root.types.TyUint8Array => ("uint8array", []),
        let literal: root.types.TyLiteral => {
            (
                root.types.primitive_type_alias(
                    root.types.primitive_type_from_literal(literal.value),
                ),
                [],
            )
        },
        let media: root.types.TyMedia => {
            match (media.kind) {
                root.base.MediaKind.Image => ("image", []),
                root.base.MediaKind.Audio => ("audio", []),
                root.base.MediaKind.Video => ("video", []),
                root.base.MediaKind.Pdf => ("pdf", []),
                root.base.MediaKind.Generic => {
                    return null;
                },
            }
        },
        // `baml.Array`, spelled by the postfix `[]`, has no named spelling.
        let list: root.types.InferTyList => ("", [list.elem]),
        let m: root.types.InferTyMap => ("map", [m.key, m.value]),
        let future: root.types.InferTyFuture => ("baml.future.Future", [future.value, future.error]),
        root.types.TyType => ("reflect.Type", []),
        _ => {
            return null;
        },
    };
    let definition = if (spelling == "") {
        ["baml", "Array"]
    } else {
        root.types.compiler_alias_by_spelling(spelling)?.definition
    }
        ?? return null;
    let package = root.base.lang_package_from_manifest_name(definition[0])
        ?? return null;
    let root_id = lang.get(package)
        ?? return null;
    (
        root.types.DeclName {
            pkg: root_id,
            namespace: definition.slice(1, definition.length() - 1),
            name: definition[definition.length() - 1],
        },
        args,
    )
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::receiver_class @ d9be6853b
// The class whose declaration owns `receiver`'s methods, with the generic
// arguments the receiver pins.
function receiver_class(facts: Facts, receiver: int, fuel: int) -> (int, int[])? throws never {
    let (let name, let args) = external_class_for_type(facts, receiver, fuel)
        ?? return null;
    match (definition_of(facts.db, name)) {
        let class_: root.hir.DefinitionClass => (class_.value, args),
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::InterfaceMember @ d9be6853b
// A resolved interface member: its type, fully instantiated for the
// receiver.
class InterfaceMember {
    ty: int,
    // Methods bind their receiver; fields do not take one.
    is_method: bool,
    // Set for a default method with own generic params: the call site
    // finishes the instantiation.
    pending_own: PendingOwnGenerics?,
    // Where the member was found: the resolution's identity.
    declarer: MemberDeclarer,
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::MemberDeclarer @ d9be6853b
// The declaration a resolved interface member came from, by dispatch mode.
type MemberDeclarer = MemberDeclarerVirtualField
    | MemberDeclarerVirtualMethod
    | MemberDeclarerImplMethod
    | MemberDeclarerImplField;

// A virtual field read: the realized declaring-interface view and the
// field's index in that interface's own declared field list.
class MemberDeclarerVirtualField {
    interface_: int,
    realized: root.types.InferInterfaceConstraint,
    field_index: int,
}

// A virtual method slot, reached through the realized view `realized`.
class MemberDeclarerVirtualMethod {
    interface_: int,
    realized: root.types.InferInterfaceConstraint,
    method: int,
}

// A concrete receiver's method through a matched impl: the method the impl
// provides, else the interface's default body. `frame_type_args` is the
// instantiation of `func`'s owner frame.
class MemberDeclarerImplMethod {
    block: int,
    func: int,
    frame_type_args: int[],
}

// A concrete receiver's interface field through a matched impl.
class MemberDeclarerImplField {
    block: int,
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::PendingOwnGenerics @ d9be6853b
// What the call site needs to finish a method's instantiation: the callable
// and the owner-frame prefix the receiver pinned.
class PendingOwnGenerics {
    callable: int,
    prefix: int[],
    // The arms of a union receiver; null for every other receiver.
    arms: int[]?,
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::InterfaceMemberLookup @ d9be6853b
// The outcome of an interface-member lookup. Ambiguity is distinct from
// not-found.
type InterfaceMemberLookup = InterfaceMemberLookupFound
    | InterfaceMemberLookupAmbiguous
    | InterfaceMemberLookupFieldRequiresProjection
    | InterfaceMemberLookupSelfRestricted
    | InterfaceMemberLookupNotFound;

class InterfaceMemberLookupFound {
    value: InterfaceMember,
}

// Two or more realized-distinct interfaces declare the member.
class InterfaceMemberLookupAmbiguous {
    sources: root.types.InferInterfaceConstraint[],
    is_field: bool,
}

// A concrete receiver reached an interface field: only `obj.as<I>.field`
// reads it.
class InterfaceMemberLookupFieldRequiresProjection {
    interface_: root.types.InferInterfaceConstraint,
}

// The member uses `Self` outside the receiver position, so it is uncallable
// through an existential receiver.
class InterfaceMemberLookupSelfRestricted {
    interface_: root.types.InferInterfaceConstraint,
    position: SelfCallPosition,
}

class InterfaceMemberLookupNotFound {
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::member_roots @ d9be6853b
// The interfaces a symbolic receiver resolves members through, and whether
// it is existential; null for a concrete receiver.
function member_roots(
    db: root.hir.Db,
    facts: Facts,
    receiver: int,
) -> (root.types.InferInterfaceConstraint[], bool)? throws never {
    let (let roots, let existential) = declared_member_roots(db, facts, receiver)
        ?? return null;
    for (let interface_ in applicable_structural_interface_roots(db, facts, receiver)) {
        if (!roots.includes(interface_)) {
            roots.push(interface_);
        }
    }
    (roots, existential)
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::declared_member_roots @ d9be6853b
function declared_member_roots(
    db: root.hir.Db,
    facts: Facts,
    receiver: int,
) -> (root.types.InferInterfaceConstraint[], bool)? throws never {
    let pool = db.ty_memo.pool;
    match (pool.kinds[receiver]) {
        let existential: root.types.InferTyInterface => {
            (
                [
                    root.types.infer_interface_new(
                        existential.name,
                        existential.args,
                        existential.associated_types,
                    ),
                ],
                true,
            )
        },
        let var: root.types.TyTypeVar => {
            (
                facts.type_var_bound(var.param).map((bound) -> {
                    root.types.infer_interface_from_constraint(pool, bound)
                }),
                false,
            )
        },
        // A rigid, irreducible projection: the associated type's declared
        // bound (rustc's alias-bound candidates).
        let projection: root.types.InferTyAssociatedTypeProjection => {
            (
                assoc_bound_roots(db, facts, projection.base, projection.interface_, projection.member),
                false,
            )
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::prefer_explicit_members @ d9be6853b
// A declared bound or applicable explicit impl outranks a structural
// fallback; a shared union view is a fallback only if every arm gets it
// implicitly. Restructured: returns the kept candidates.
function prefer_explicit_members<T>(
    db: root.hir.Db,
    viewer: int,
    facts: Facts,
    receiver: int,
    candidates: T[],
    interface_: (T) -> root.types.InferInterfaceConstraint,
) -> T[] {
    if (candidates.length() < 2) {
        return candidates;
    }
    let priorities = candidates.map((candidate) -> {
        prefer_explicit_members_explicit(db, viewer, facts, receiver, interface_(candidate))
    });
    if (
        !priorities.some((explicit) -> {
            explicit
        })
    ) {
        return candidates;
    }
    let kept: T[] = [];
    for (let i = 0; i < candidates.length(); i += 1) {
        if (priorities[i]) {
            kept.push(candidates[i]);
        }
    }
    kept
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::prefer_explicit_members::explicit @ d9be6853b
function prefer_explicit_members_explicit(
    db: root.hir.Db,
    viewer: int,
    facts: Facts,
    receiver: int,
    interface_: root.types.InferInterfaceConstraint,
) -> bool throws never {
    let pool = db.ty_memo.pool;
    if let union: root.types.InferTyUnion = pool.kinds[receiver] {
        return union.members.some((arm) -> {
            prefer_explicit_members_explicit(db, viewer, facts, arm, interface_)
        });
    }
    let declared = declared_member_roots(db, facts, receiver);
    if (declared != null) {
        return declared.0.some((root_) -> {
            root_ == interface_
                || direct_requires_closure(db, root_, receiver, 8).includes(interface_)
        });
    }
    impls_for_receiver(db, viewer, receiver).some((resolved) -> {
        env_discharges_rigid_bounds(db, facts, resolved) && resolved.implemented(pool) == interface_
    })
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::lookup_interface_member @ d9be6853b
// Resolves `name` as an interface member of `receiver`: an existential, a
// rigid bounded var, or a projection through its bound; a concrete receiver
// resolves through the impls it matches. Within one conjunct the root
// shadows its `requires` closure; across conjuncts declarers dedupe by
// realized identity, and two or more survivors are ambiguous.
function lookup_interface_member(
    db: root.hir.Db,
    viewer: int,
    facts: Facts,
    receiver: int,
    name: string,
) -> InterfaceMemberLookup throws never {
    let (let roots, let existential) = member_roots(db, facts, receiver)
        ?? return lookup_impl_member(db, viewer, facts, receiver, name);
    let lang = root.hir.lang_roots(db);
    let declarers: (root.types.InferInterfaceConstraint, InterfaceMember)[] = [];
    let push = (realized: root.types.InferInterfaceConstraint, member: InterfaceMember) -> void {
        if (
            !declarers.some((seen) -> {
                seen.0 == realized
            })
        ) {
            declarers.push((realized, member));
        }
    };
    // A value receiver's members: `baml.Concrete`'s `type` is a static.
    let concrete_type = (interface_: root.types.InferInterfaceConstraint) -> bool {
        is_concrete_type_member(lang, interface_.name, name)
    };
    for (let root_ in roots) {
        // Root-wins: the directly-named interface shadows its own closure.
        if (!concrete_type(root_)) {
            let member = member_on_interface(db, facts, root_, receiver, name, existential);
            if (member != null) {
                push(root_, member);
                continue;
            }
        }
        for (let required in direct_requires_closure(db, root_, receiver, 8)) {
            if (concrete_type(required)) {
                continue;
            }
            let member = member_on_interface(db, facts, required, receiver, name, existential);
            if (member != null) {
                push(required, member);
            }
        }
    }
    let kept = prefer_explicit_members(db, viewer, facts, receiver, declarers, (declarer) -> {
        declarer.0
    });
    match (kept.length()) {
        0 => {
            // An existential receiver may have skipped a declared method for
            // using `Self` outside the receiver position: say that.
            if (existential) {
                for (let root_ in roots) {
                    let position = declared_method_self_restriction(db, facts, root_, name);
                    if (position != null) {
                        return InterfaceMemberLookupSelfRestricted {
                            interface_: root_,
                            position: position,
                        };
                    }
                }
            }
            InterfaceMemberLookupNotFound {}
        },
        1 => InterfaceMemberLookupFound { value: kept[0].1 },
        _ => {
            InterfaceMemberLookupAmbiguous {
                is_field: !kept[0].1.is_method,
                sources: kept.map((declarer) -> {
                    declarer.0
                }),
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::declared_method_self_restriction @ d9be6853b
// Whether `target` declares method `name` with a `Self` use that makes it
// uncallable through an existential receiver, and where.
function declared_method_self_restriction(
    db: root.hir.Db,
    facts: Facts,
    target: root.types.InferInterfaceConstraint,
    name: string,
) -> SelfCallPosition? throws never {
    let interface_ = match (definition_of(db, target.name)) {
        let def: root.hir.DefinitionInterface => def.value,
        _ => {
            return null;
        },
    };
    let method = root.hir.interface_data(db, interface_).methods.find((method) -> {
        root.hir.function_data(db, method).name == name
    })
        ?? return null;
    match (callable_self_dispatch(db, method)) {
        let breaks: SelfDispatchBreaks => breaks.value,
        SelfDispatchOnParam | SelfDispatchNoSelfParam => null,
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::concrete_member_ambiguity @ d9be6853b
// The concrete-receiver impl tier's ambiguity verdict alone: an own method
// does not arbitrate an interface clash (E0121).
function concrete_member_ambiguity(
    db: root.hir.Db,
    viewer: int,
    facts: Facts,
    receiver: int,
    name: string,
) -> (root.types.InferInterfaceConstraint[], bool)? throws never {
    match (lookup_impl_member(db, viewer, facts, receiver, name)) {
        let ambiguous: InterfaceMemberLookupAmbiguous => (ambiguous.sources, ambiguous.is_field),
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::lookup_impl_member @ d9be6853b
// Concrete receivers: every impl the receiver matches contributes its
// interface's members. Root-wins across providers (the most-derived
// interface shadows the ones it `requires`); distinct survivors are
// ambiguous. Upstream's fixed shape: a structural root is proven only once
// it declares `name`.
function lookup_impl_member(
    db: root.hir.Db,
    viewer: int,
    facts: Facts,
    receiver: int,
    name: string,
) -> InterfaceMemberLookup throws never {
    let pool = db.ty_memo.pool;
    let lang = root.hir.lang_roots(db);
    // An unsolved receiver instantiation: probe at probe-unique rigid class
    // params (`$` is unwritable in user identifiers) and substitute the
    // receiver's actual arguments back.
    if let class_: root.types.InferTyClass = pool.kinds[receiver] {
        let unsolved = class_.args.some((arg) -> {
            pool.has_infer(arg)
        });
        if (unsolved) {
            if let def: root.hir.DefinitionClass = definition_of(db, class_.name) {
                let frame = class_generic_frame(db, def.value).map((param) -> {
                    root.types.ParamTy { index: param.index, name: `$probe$${param.name}` }
                });
                let probe = class_ty_interned(
                    pool,
                    lang,
                    class_qualified_name(db, def.value),
                    frame.map((param) -> {
                        pool.add(root.types.TyTypeVar { param: param })
                    }),
                );
                let lookup = lookup_impl_member(db, viewer, facts, probe, name);
                return substitute_lookup_class_args(pool, lookup, frame, class_.args);
            }
        }
    }
    // A literal receiver resolves against its base primitive's impls, and
    // `Self` widens with it.
    let widened = match (pool.kinds[receiver]) {
        let literal: root.types.TyLiteral => pool.add(literal_base(literal.value)),
        _ => receiver,
    };
    let providers: (root.types.InferInterfaceConstraint, InterfaceMember)[] = [];
    for (let resolved in impls_for_receiver(db, viewer, widened)) {
        if (!env_discharges_rigid_bounds(db, facts, resolved)) {
            continue;
        }
        let implemented = resolved.implemented(pool);
        if (is_concrete_type_member(lang, implemented.name, name)) {
            continue;
        }
        let member = member_on_interface(db, facts, implemented, widened, name, false);
        if (
            member == null
                || providers.some((seen) -> {
                    seen.0 == implemented
                })
        ) {
            continue;
        }
        lookup_impl_member_concrete_declarer(db, member, resolved, implemented, widened, name);
        providers.push((implemented, member));
    }
    if (providers.length() == 0 && !pool.has_error(widened)) {
        // Member first: proving a conditional root (`Hash`) can walk the
        // receiver's whole type graph, and most names are not on it.
        for (let interface_ in structural_interface_candidates(db)) {
            let member = member_on_interface(db, facts, interface_, widened, name, false);
            if (member != null && structural_root_applies(db, facts, widened, interface_)) {
                providers.push((interface_, member));
            }
        }
    }
    // Interface fields on a concrete receiver are projection-only.
    let field_sources = providers
        .filter((provider) -> {
            !provider.1.is_method
        })
        .map((provider) -> {
            provider.0
        });
    if (field_sources.length() >= 2) {
        return InterfaceMemberLookupAmbiguous { sources: field_sources, is_field: true };
    }
    if (field_sources.length() == 1) {
        return InterfaceMemberLookupFieldRequiresProjection { interface_: field_sources[0] };
    }
    // Interface methods: the most-derived provider shadows the ones it
    // `requires`; distinct survivors are ambiguous (E0121).
    let survivors = if (providers.length() > 1) {
        providers.filter((provider) -> {
            !providers.some((other) -> {
                other.0.name != provider.0.name
                    && interface_requires(db, other.0, provider.0, widened, 8)
            })
        })
    } else {
        providers
    };
    match (survivors.length()) {
        0 => InterfaceMemberLookupNotFound {},
        1 => InterfaceMemberLookupFound { value: survivors[0].1 },
        _ => {
            InterfaceMemberLookupAmbiguous {
                sources: survivors.map((provider) -> {
                    provider.0
                }),
                is_field: false,
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::lookup_impl_member @ d9be6853b
// Concrete dispatch for one provider: the interface answered the
// declaration question; the impl answers which function runs. A provided
// method types against its own (possibly refined) signature; an adopted
// default keeps the interface's typing and narrows only the declarer, when
// the default has a body. A field's declarer is the source block.
// Restructured: split out of `lookup_impl_member`'s loop; edits `member`.
function lookup_impl_member_concrete_declarer(
    db: root.hir.Db,
    member: InterfaceMember,
    resolved: ResolvedImpl,
    implemented: root.types.InferInterfaceConstraint,
    receiver: int,
    name: string,
) -> void throws never {
    let declarer = member.declarer;
    if (!member.is_method) {
        if (declarer is MemberDeclarerVirtualField) {
            member.declarer = MemberDeclarerImplField { block: resolved.facts.block };
        }
        return;
    }
    let callable = resolved.provided_method(db, name);
    if (callable != null) {
        // The provided method's frame: the impl's generics realized through
        // the match, in declaration order. The own suffix stays rigid for
        // the call site.
        let frame_type_args = realized_impl_frame(resolved);
        member.ty = instantiate_callable_signature(db, callable, frame_type_args);
        member.pending_own
            = if (function_signature_ty(db, callable).generic_params.length() != 0) {
                PendingOwnGenerics { callable: callable, prefix: frame_type_args, arms: null }
            } else {
                null
            };
        member.declarer
            = MemberDeclarerImplMethod {
                block: resolved.facts.block,
                func: callable,
                frame_type_args: frame_type_args,
            };
        return;
    }
    // Adoption needs a default body this compilation can reference; an
    // incomplete impl keeps the virtual declarer.
    if let virtual: MemberDeclarerVirtualMethod = declarer {
        if (root.hir.function_has_body(db, virtual.method)) {
            // The default's frame: `[Self = receiver, iface args..]`.
            member.declarer
                = MemberDeclarerImplMethod {
                    block: resolved.facts.block,
                    func: virtual.method,
                    frame_type_args: [receiver].concat(implemented.generics),
                };
        }
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::assoc_bound_roots @ d9be6853b
// The alias-bound roots of a projection receiver: the associated type's
// declared bound, realized with `Self` = the projection's base. Empty means
// the projection has no bound roots (or its declaration already failed).
function assoc_bound_roots(
    db: root.hir.Db,
    facts: Facts,
    base: int,
    interface_ref: root.types.InferInterfaceConstraint,
    member: string,
) -> root.types.InferInterfaceConstraint[] throws never {
    let pool = db.ty_memo.pool;
    match (mounted_type_row(db, interface_ref.name)) {
        let row: ExportedTypeInterface => {
            let assoc = row.associated_types.find((assoc) -> {
                assoc.name == member
            })
                ?? return [];
            if (assoc.bound == null) {
                return [];
            }
            let realized = realized_assoc_bound(db, interface_ref, base, member);
            let bound = if (realized != null) {
                root.types.infer_interface_of_ty(pool, realized)
            } else {
                null
            };
            return if (bound != null) {
                [bound]
            } else {
                []
            };
        },
        _ => {},
    }
    let interface_ = match (definition_of(db, interface_ref.name)) {
        let def: root.hir.DefinitionInterface => def.value,
        _ => {
            return [];
        },
    };
    let data = root.hir.interface_data(db, interface_);
    let assoc = data.associated_types.find((assoc) -> {
        assoc.name == member
    })
        ?? return [];
    // An associated type without item bounds contributes no candidates.
    let bound = assoc.bound
        ?? return [];
    let ctx = lower_ctx_for_file(db, db.interface_locs.get(interface_).file)
        .with_frame(interface_frame(db, interface_))
        .with_bounds(interface_scope_bounds(db, interface_));
    let bound_ty = pool.from_plain(
        reject_holes(ctx.lower_type_ref(data.type_refs, bound, position = TypePosition.ConstraintHead)),
    );
    let instantiation = interface_instantiation(base, interface_ref, data.generic_params.length())
        ?? return [];
    match (pool.kinds[substitute_params(pool, bound_ty, instantiation)]) {
        let realized: root.types.InferTyInterface => {
            [
                root.types.infer_interface_new(
                    realized.name,
                    realized.args,
                    realized.associated_types,
                ),
            ]
        },
        // A bound that realizes to a non-interface or the Error sentinel was
        // rejected where it was declared.
        _ => [],
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::impls_for_receiver @ d9be6853b
// `impls_for_type` for an interned receiver: an open receiver enumerates
// nothing.
function impls_for_receiver(
    db: root.hir.Db,
    viewer: int,
    receiver: int,
) -> ResolvedImpl[] throws never {
    let pool = db.ty_memo.pool;
    if (pool.has_infer(receiver)) {
        return [];
    }
    impls_for_type(db, viewer, pool.to_plain_closed(receiver))
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::realized_impl_frame @ d9be6853b
// A matched impl's generic params realized through the match, in
// declaration order.
function realized_impl_frame(resolved: ResolvedImpl) -> int[] throws never {
    resolved.facts.facts.generic_params.map((entry) -> {
        resolved.bindings.get(entry.0)
            ?? baml.sys.panic(`matched impl left generic \`${entry.0.name}\` unbound`)
    })
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::env_discharges_rigid_bounds @ d9be6853b
// Discharges the bounds `bounds_hold` skipped as vacuous (impl params bound to
// rigid vars) against the caller's param env.
function env_discharges_rigid_bounds(
    db: root.hir.Db,
    facts: Facts,
    resolved: ResolvedImpl,
) -> bool throws never {
    let pool = db.ty_memo.pool;
    for (let entry in resolved.facts.facts.generic_params) {
        let actual = resolved.bindings.get(entry.0);
        if (actual == null || !pool.has_typevar(actual)) {
            continue;
        }
        for (let bound in entry.1) {
            // Pins are outputs, not part of the relation.
            let goal = root.types.infer_interface_new(
                bound.reference.name,
                bound.reference.generics.map((arg) -> {
                    pool.substitute_bindings(arg, resolved.bindings)
                }),
                [],
            );
            if (!env_proves(db, facts, actual, goal)) {
                return false;
            }
        }
    }
    true
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::env_proves @ d9be6853b
// Whether the param env proves rigid `actual` implements `goal`; structured
// rigid-carrying actuals fall back to the impl search.
function env_proves(
    db: root.hir.Db,
    facts: Facts,
    actual: int,
    goal: root.types.InferInterfaceConstraint,
) -> bool throws never {
    if (is_structural_interface(db, goal)) {
        return true;
    }
    let eligible = conditional_structural_verdict(db, facts, actual, goal);
    if (eligible != null) {
        return eligible;
    }
    let pool = db.ty_memo.pool;
    let var = match (pool.kinds[actual]) {
        let v: root.types.TyTypeVar => v,
        _ => {
            return implements_interface(db, actual, goal);
        },
    };
    let eq = AliasOnlyFacts.new(db);
    facts.type_var_bound(var.param).some((bound) -> {
        requires_heads(db, root.types.infer_interface_from_constraint(pool, bound), actual, 8).some((
            head,
        ) -> {
            head_matches(head, goal, eq)
        })
    })
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::substitute_class_params @ d9be6853b
// Substitute the class frame's rigid parameters with the receiver's actual
// arguments, keyed by full `ParamTy` identity.
function substitute_class_params(
    pool: root.types.InferPool,
    ty: int,
    frame: root.types.ParamTy[],
    args: int[],
) -> int throws never {
    if (!pool.has_typevar(ty)) {
        return ty;
    }
    if let var: root.types.TyTypeVar = pool.kinds[ty] {
        let position = frame.find_index((candidate) -> {
            candidate == var.param
        });
        if (position != null && position < args.length()) {
            return args[position];
        }
    }
    pool.add(
        root.types.map_children(pool.kinds[ty], (child) -> {
            substitute_class_params(pool, child, frame, args)
        }),
    )
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::substitute_lookup_class_args @ d9be6853b
// `substitute_class_params` over a whole lookup result: every carried type
// trades the probe's rigid class vars for the receiver's actual arguments.
function substitute_lookup_class_args(
    pool: root.types.InferPool,
    lookup: InterfaceMemberLookup,
    frame: root.types.ParamTy[],
    args: int[],
) -> InterfaceMemberLookup throws never {
    let subst = (ty: int) -> int {
        substitute_class_params(pool, ty, frame, args)
    };
    let subst_ref = (realized: root.types.InferInterfaceConstraint) -> root.types.InferInterfaceConstraint {
        root.types.infer_interface_map_types(realized, subst)
    };
    match (lookup) {
        let found: InterfaceMemberLookupFound => {
            let member = found.value;
            member.ty = subst(member.ty);
            let pending = member.pending_own;
            if (pending != null) {
                let arms = pending.arms;
                member.pending_own
                    = PendingOwnGenerics {
                        callable: pending.callable,
                        prefix: pending.prefix.map(subst),
                        arms: if (arms != null) {
                            arms.map(subst)
                        } else {
                            null
                        },
                    };
            }
            member.declarer
                = match (member.declarer) {
                    let d: MemberDeclarerVirtualField => {
                        MemberDeclarerVirtualField {
                            interface_: d.interface_,
                            realized: subst_ref(d.realized),
                            field_index: d.field_index,
                        }
                    },
                    let d: MemberDeclarerImplMethod => {
                        MemberDeclarerImplMethod {
                            block: d.block,
                            func: d.func,
                            frame_type_args: d.frame_type_args.map(subst),
                        }
                    },
                    let d: MemberDeclarerVirtualMethod => {
                        MemberDeclarerVirtualMethod {
                            interface_: d.interface_,
                            realized: subst_ref(d.realized),
                            method: d.method,
                        }
                    },
                    let d: MemberDeclarerImplField => d,
                };
            InterfaceMemberLookupFound { value: member }
        },
        let ambiguous: InterfaceMemberLookupAmbiguous => {
            InterfaceMemberLookupAmbiguous {
                sources: ambiguous.sources.map(subst_ref),
                is_field: ambiguous.is_field,
            }
        },
        let projection: InterfaceMemberLookupFieldRequiresProjection => {
            InterfaceMemberLookupFieldRequiresProjection {
                interface_: subst_ref(projection.interface_),
            }
        },
        let restricted: InterfaceMemberLookupSelfRestricted => {
            InterfaceMemberLookupSelfRestricted {
                interface_: subst_ref(restricted.interface_),
                position: restricted.position,
            }
        },
        InterfaceMemberLookupNotFound => InterfaceMemberLookupNotFound {},
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::member_on_interface @ d9be6853b
// A member declared directly on `target`, instantiated for `receiver`.
// Fields first, then methods (default and required alike, one signature
// road).
function member_on_interface(
    db: root.hir.Db,
    facts: Facts,
    target: root.types.InferInterfaceConstraint,
    receiver: int,
    name: string,
    existential: bool,
) -> InterfaceMember? throws never {
    let pool = db.ty_memo.pool;
    let interface_ = match (definition_of(db, target.name)) {
        let def: root.hir.DefinitionInterface => def.value,
        _ => {
            return null;
        },
    };
    let data = root.hir.interface_data(db, interface_);
    let instantiation = interface_instantiation(receiver, target, data.generic_params.length())
        ?? return null;
    let field_index = data.fields.find_index((field) -> {
        field.name == name
    });
    if (field_index != null) {
        let field_ty = declared_interface_field_ty(db, interface_, field_index);
        return InterfaceMember {
            ty: substitute_params(pool, field_ty, instantiation),
            is_method: false,
            pending_own: null,
            // The index space implementations are baked against is the
            // interface's own declared field list.
            declarer: MemberDeclarerVirtualField {
                interface_: interface_,
                realized: target,
                field_index: field_index,
            },
        };
    }
    let method = data.methods.find((method) -> {
        root.hir.function_data(db, method).name == name
    })
        ?? return null;
    if (existential && callable_breaks_one_self(db, method)) {
        return null;
    }
    // The method's own generics are the call site's to fill.
    let pending_own = if (function_signature_ty(db, method).generic_params.length() != 0) {
        PendingOwnGenerics { callable: method, prefix: instantiation, arms: null }
    } else {
        null
    };
    InterfaceMember {
        ty: instantiate_callable_signature(db, method, instantiation),
        is_method: true,
        pending_own: pending_own,
        declarer: MemberDeclarerVirtualMethod { interface_: interface_, realized: target, method: method },
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::declared_interface_field_ty @ d9be6853b
// The declared type of the field at `index` in an interface's own field
// list, over the interface frame.
function declared_interface_field_ty(
    db: root.hir.Db,
    interface_: int,
    index: int,
) -> int throws never {
    let data = root.hir.interface_data(db, interface_);
    let ctx = lower_ctx_for_file(db, db.interface_locs.get(interface_).file)
        .with_frame(interface_frame(db, interface_))
        .with_bounds(interface_scope_bounds(db, interface_));
    db.ty_memo.pool.from_plain(
        reject_holes(ctx.lower_type_ref(data.type_refs, data.fields[index].type_ref)),
    )
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::interface_instantiation @ d9be6853b
// The positional instantiation `[Self = receiver, args..]` of an interface
// reference; null when the reference's arity is not the declared one (a
// construction bug Rust debug-asserts).
function interface_instantiation(
    receiver: int,
    target: root.types.InferInterfaceConstraint,
    declared_arity: int,
) -> int[]? throws never {
    if (declared_arity != target.generics.length()) {
        return null;
    }
    [receiver].concat(target.generics)
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::self_occurs @ d9be6853b
// Whether frame slot 0 (`Self`) occurs illegally: any occurrence in a
// non-top position, or a top one when `top_ok` is false. Projection bases
// are exempt. Restructured: takes the pool.
function self_occurs(pool: root.types.InferPool, ty: int, top_ok: bool) -> bool throws never {
    match (pool.kinds[ty]) {
        let var: root.types.TyTypeVar if var.param.index == 0 && var.param.name == "Self" => !top_ok,
        root.types.InferTyAssociatedTypeProjection => false,
        // Unions and optionals are covariant-transparent.
        let union: root.types.InferTyUnion => {
            union.members.some((member) -> {
                self_occurs(pool, member, top_ok)
            })
        },
        let kind: root.types.InferTy => {
            root.types.children_infer_ty(kind).some((child) -> {
                self_occurs(pool, child, false)
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::UnionMemberLookup @ d9be6853b
// The outcome of resolving a member on a union receiver: the union behaves
// as the intersection existential over the interfaces every arm provides.
type UnionMemberLookup = UnionMemberLookupFound
    | UnionMemberLookupAmbiguous
    | UnionMemberLookupSelfRestricted
    | UnionMemberLookupNoCommonInterface
    | UnionMemberLookupAssociatedTypeConflict;

class UnionMemberLookupFound {
    value: InterfaceMember,
}

// Two or more shared interfaces declare the member.
class UnionMemberLookupAmbiguous {
    sources: root.types.InferInterfaceConstraint[],
    is_field: bool,
}

// The single shared declarer's method uses `Self` outside the receiver
// position.
class UnionMemberLookupSelfRestricted {
    interface_: root.types.InferInterfaceConstraint,
    position: SelfCallPosition,
}

// No interface shared by every arm declares the member.
class UnionMemberLookupNoCommonInterface {
}

// The member needs one type where the arms bind an associated type
// differently; `types` are the arms' types for that position.
class UnionMemberLookupAssociatedTypeConflict {
    is_method: bool,
    types: int[],
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::lookup_union_member @ d9be6853b
// Resolves `name` through the single interface every arm shares that
// declares it: inference sugar for `union.as<I>.member`.
function lookup_union_member(
    db: root.hir.Db,
    viewer: int,
    facts: Facts,
    union_ty: int,
    members: int[],
    name: string,
) -> UnionMemberLookup throws never {
    let shared: root.types.InferInterfaceConstraint[]? = null;
    for (let arm in members) {
        let arm_ifaces = union_arm_interfaces(db, viewer, facts, arm, name, 4);
        let current = shared;
        let next = if (current == null) {
            arm_ifaces
        } else {
            current.filter((iface) -> {
                arm_ifaces.includes(iface)
            })
        };
        shared = next;
        if (next.length() == 0) {
            break;
        }
    }
    let lang = root.hir.lang_roots(db);
    let declarers: (root.types.InferInterfaceConstraint, bool)[] = [];
    for (let iface in shared ?? []) {
        if (is_concrete_type_member(lang, iface.name, name)) {
            continue;
        }
        let is_field = interface_declares_member(db, iface, name);
        if (
            is_field != null
                && !declarers.some((seen) -> {
                    seen.0 == iface
                })
        ) {
            declarers.push((iface, is_field));
        }
    }
    let kept = prefer_explicit_members(db, viewer, facts, union_ty, declarers, (declarer) -> {
        declarer.0
    });
    match (kept.length()) {
        0 => UnionMemberLookupNoCommonInterface {},
        1 => {
            let iface = kept[0].0;
            // Virtual dispatch goes through the shared interface, but `Self`
            // binds to the union itself; one-`Self` object safety applies as
            // for an existential.
            let member = member_on_interface(db, facts, iface, union_ty, name, true);
            if (member != null) {
                return type_union_member(db, facts, member, iface, union_ty, members);
            }
            let position = declared_method_self_restriction(db, facts, iface, name);
            if (position != null) {
                UnionMemberLookupSelfRestricted { interface_: iface, position: position }
            } else {
                UnionMemberLookupNoCommonInterface {}
            }
        },
        _ => {
            UnionMemberLookupAmbiguous {
                is_field: kept[0].1,
                sources: kept.map((declarer) -> {
                    declarer.0
                }),
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::type_union_member @ d9be6853b
// A union member's type, instantiated once per arm: what flows out (a
// method's return and throws) is the union of the arms' types; what flows in
// (a method's parameters) or both ways (a field) needs one agreed type.
function type_union_member(
    db: root.hir.Db,
    facts: Facts,
    member: InterfaceMember,
    interface_: root.types.InferInterfaceConstraint,
    union_ty: int,
    arms: int[],
) -> UnionMemberLookup throws never {
    // The owner frame only: a method's own generics stay rigid for the call
    // site.
    let instantiation = [union_ty].concat(interface_.generics);
    let typed: int | int[] = match (member.declarer) {
        let method: MemberDeclarerVirtualMethod => {
            union_method_signature(db, facts, method.method, instantiation, arms)
        },
        let field: MemberDeclarerVirtualField => {
            let declared = declared_interface_field_ty(db, field.interface_, field.field_index);
            let per_arm = instantiate_per_arm(facts, declared, instantiation, arms);
            agreed(facts, per_arm) ?? per_arm
        },
        MemberDeclarerImplMethod | MemberDeclarerImplField => {
            return UnionMemberLookupFound { value: member };
        },
    };
    match (typed) {
        let ty: int => {
            member.ty = ty;
            let pending = member.pending_own;
            if (pending != null) {
                pending.arms = arms;
            }
            UnionMemberLookupFound { value: member }
        },
        let types: int[] => {
            UnionMemberLookupAssociatedTypeConflict { is_method: member.is_method, types: types }
        },
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::instantiate_member_signature @ d9be6853b
// A callable's signature at `instantiation`, per arm when the receiver is a
// union (`arms`). A union's parameters were proven to agree at lookup, so
// the first arm's are the answer.
function instantiate_member_signature(
    db: root.hir.Db,
    facts: Facts,
    callable: int,
    instantiation: int[],
    arms: int[]?,
) -> int throws never {
    let arm_list = arms
        ?? return instantiate_callable_signature(db, callable, instantiation);
    let pool = db.ty_memo.pool;
    let signature = function_signature_ty(db, callable);
    let outward = (declared: root.types.Ty) -> int {
        let per_arm = instantiate_per_arm(facts, pool.from_plain(declared), instantiation, arm_list);
        agreed(facts, per_arm) ?? union_of_tys(facts, per_arm)
    };
    let first_arm = arm_list.slice(0, 1);
    pool.add(
        root.types.InferTyFunction {
            params: signature.params.map((param) -> {
                root.types.InferFunctionParamTy {
                    name: param.name,
                    ty: instantiate_per_arm(facts, pool.from_plain(param.ty), instantiation, first_arm)[
                        0
                    ],
                    mode: param.mode,
                }
            }),
            ret: outward(signature.return_type),
            throws_: outward(function_signature_with_diagnostics(db, callable).signature.throws_),
        },
    )
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::union_method_signature @ d9be6853b
// `instantiate_member_signature` for a union, checking every arm agrees on
// each parameter; the arms' types for the first disagreeing parameter
// otherwise.
function union_method_signature(
    db: root.hir.Db,
    facts: Facts,
    callable: int,
    instantiation: int[],
    arms: int[],
) -> int | int[] throws never {
    let pool = db.ty_memo.pool;
    for (let param in function_signature_ty(db, callable).params) {
        let per_arm = instantiate_per_arm(facts, pool.from_plain(param.ty), instantiation, arms);
        if (agreed(facts, per_arm) == null) {
            return per_arm;
        }
    }
    instantiate_member_signature(db, facts, callable, instantiation, arms)
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::instantiate_per_arm @ d9be6853b
// `declared` instantiated once per arm of a union `Self`
// (`instantiation[0]`), each arm's projections reduced.
function instantiate_per_arm(
    facts: Facts,
    declared: int,
    instantiation: int[],
    arms: int[],
) -> int[] throws never {
    let pool = facts.db.ty_memo.pool;
    arms.map((arm) -> {
        let arm_instantiation = [arm].concat(instantiation.slice(1, instantiation.length()));
        let instantiated = substitute_params_through_arm(pool, declared, instantiation, arm_instantiation);
        reduce_closed_projections(facts, instantiated, PROJECTION_FINALIZE_FUEL)
    })
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::agreed @ d9be6853b
// The one type every arm gives, when they all give the same one: identical
// spellings, or closed types the oracle proves equivalent.
function agreed(facts: Facts, per_arm: int[]) -> int? throws never {
    let pool = facts.db.ty_memo.pool;
    let first = per_arm.at(0)
        ?? return null;
    let all = per_arm.slice(1, per_arm.length()).every((other) -> {
        other == first || eq_admitted(pool, other, first, facts)
    });
    if (all) {
        first
    } else {
        null
    }
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::union_arm_interfaces @ d9be6853b
// The realized interfaces one union arm provides: an existential itself plus
// its `requires` closure; a bounded variable each conjunct's; a concrete arm
// its matched impls' realized interfaces. Upstream's fixed shape (after
// d9be6853b, which added `name`): structural roots join only when they
// declare `name`.
function union_arm_interfaces(
    db: root.hir.Db,
    viewer: int,
    facts: Facts,
    arm: int,
    name: string,
    fuel: int,
) -> root.types.InferInterfaceConstraint[] throws never {
    if (fuel == 0) {
        return [];
    }
    let pool = db.ty_memo.pool;
    let interfaces: root.types.InferInterfaceConstraint[] = [];
    let add = (interface_: root.types.InferInterfaceConstraint) -> void {
        if (!interfaces.includes(interface_)) {
            interfaces.push(interface_);
        }
    };
    let add_with_closure = (root_: root.types.InferInterfaceConstraint) -> void {
        add(root_);
        for (let required in direct_requires_closure(db, root_, arm, 8)) {
            add(required);
        }
    };
    match (pool.kinds[arm]) {
        let existential: root.types.InferTyInterface => {
            add_with_closure(
                root.types.infer_interface_new(
                    existential.name,
                    existential.args,
                    existential.associated_types,
                ),
            );
        },
        let var: root.types.TyTypeVar => {
            for (let bound in facts.type_var_bound(var.param)) {
                add_with_closure(root.types.infer_interface_from_constraint(pool, bound));
            }
        },
        _ => {
            for (let resolved in impls_for_receiver(db, viewer, arm)) {
                if (env_discharges_rigid_bounds(db, facts, resolved)) {
                    add(resolved.implemented(pool));
                }
            }
        },
    }
    // Only structural roots declaring `name` can matter to the caller, and
    // proving a conditional one (`Hash`) can walk the arm's whole type graph.
    for (let interface_ in structural_interface_candidates(db)) {
        if (
            !interfaces.includes(interface_)
                && interface_declares_member(db, interface_, name) != null
                && structural_root_applies(db, facts, arm, interface_)
        ) {
            interfaces.push(interface_);
        }
    }
    interfaces
}

// port: baml_compiler2_hir_ty/src/method_resolution.rs::interface_declares_member @ d9be6853b
// Whether the interface declares `name`, and as which kind (true = field).
// Side-effect-free: counts shared declarers before committing.
function interface_declares_member(
    db: root.hir.Db,
    target: root.types.InferInterfaceConstraint,
    name: string,
) -> bool? throws never {
    match (
        root.hir_ty.interfaces.interface_declared_kind(
            db,
            target.name,
            name,
            root.hir_ty.interfaces.MemberNamespace.Value,
        )
    ) {
        let value: root.hir_ty.interfaces.InterfaceMemberKindValue => {
            value.value == root.hir_ty.interfaces.ValueMemberKind.Field
        },
        root.hir_ty.interfaces.InterfaceMemberKindAssociatedType | null => null,
    }
}
