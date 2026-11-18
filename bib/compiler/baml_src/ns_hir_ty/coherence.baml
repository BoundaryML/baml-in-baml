// port: baml_compiler2_hir_ty/src/coherence.rs @ d9be6853b
//
// Ported: `heads_may_overlap`, the bound-free head overlap Hash eligibility
// asks (impls.baml's `has_potential_custom_equals`), and `renamed_var`.
//
// Restructured: coherence.rs carries a private copy of the overlap engine
// (`unify_into` .. `occurs_in`, `TypeBindings`, `Overlap`) that is
// baml_type/src/unify.rs's engine line for line, ported as `root.types`'
// (ns_types/unify.baml). The one difference is the tuple arm, a `.and` loop
// here against `unify_all` there; both return the same `Overlap` (`No`
// dominates the conjunction either way), and the bindings they leave differ
// only on a `No`, which every caller discards. So `heads_may_overlap` calls
// `root.types.unify_into` instead of a second copy, and coherence.rs's tests
// of that engine (the `union_overlap_*`, `cover_*`, `nf_*`, ... tests) are
// the ones ns_types/unify_test.baml already ports under the same names.
//
// Also ported, for baml_tests' type_spec coherence suite: the per-package
// coherence walk (`package_coherence_violations` and its helpers through
// `renamed_subject`), the orphan walk (`package_orphan_violations`,
// `orphan_check`), the private `substitute_plain`, and `orphan_check`'s unit
// tests.
// - The walks are not memoized: Rust's `#[salsa::tracked]` would need a memo
//   field on `ty_memo` (db.baml), and only tests call them.
// - `CoherenceReport` / `OrphanReport` (salsa value wrappers) are the
//   arrays they wrap; an `ImplLoc` is its interned `int`.
// - coherence.rs's private `contains_bound_typevar`, `var_under_union` and
//   `chase_var` are baml_type/src/unify.rs's line for line (the leaf arms
//   differ only in spelling, all `false`), so the `root.types` ports are
//   called. `substitute_plain` is NOT unify.rs's `substitute_ty` (that one
//   re-normalizes a rebuilt union), so it is ported here.
// - `orphan_check`'s tests are in coherence_test.baml; they reuse
//   `root.hir_ty.interfaces.test_root` / `pkg_qtn` (impl_rules_test.baml's
//   port of `test_heads::root`).
//
// Not ported: `source_mounted_impl_conflict` and `mounted_impl_facts`
// (check.rs uses them only for mounted packages, none here).

// port: baml_compiler2_hir_ty/src/coherence.rs::heads_may_overlap @ d9be6853b
// Bound-free head overlap. Symbolic projections may denote any type; proving
// their values here would re-enter trait selection during negative
// reasoning, so each type variable or projection becomes a fresh variable.
function heads_may_overlap(
    db: root.hir.Db,
    package: int,
    left: root.types.ClosedTy,
    right: root.types.ClosedTy,
) -> bool throws never {
    let pool = db.ty_memo.pool;
    let vars: root.types.ParamTy[] = [];
    let left_fresh = heads_may_overlap_freshen(pool, left.ty, {}, vars);
    let right_fresh = heads_may_overlap_freshen(pool, right.ty, {}, vars);
    let aliases = root.types.AliasEquivCtx {
        aliases: root.hir_ty.interfaces.normalized_alias_map(db, package),
        lang: root.hir.lang_roots(db),
    };
    // A freshened head is closed: its inputs were.
    root.types.unify_into(
        pool.to_plain_closed(left_fresh),
        pool.to_plain_closed(right_fresh),
        vars,
        aliases,
        {},
    )
        != root.types.Overlap.No
}

// port: baml_compiler2_hir_ty/src/coherence.rs::heads_may_overlap::freshen @ d9be6853b
function heads_may_overlap_freshen(
    pool: root.types.InferPool,
    ty: int,
    symbols: map<int, int>,
    vars: root.types.ParamTy[],
) -> int throws never {
    match (pool.kinds[ty]) {
        root.types.TyTypeVar | root.types.InferTyAssociatedTypeProjection => {
            let existing = symbols.get(ty);
            if (existing != null) {
                return existing;
            }
            let param = renamed_var("h", vars.length());
            vars.push(param);
            let fresh = pool.add(root.types.TyTypeVar { param: param });
            symbols[ty] = fresh;
            fresh
        },
        _ => {
            pool.add(
                root.types.map_children(pool.kinds[ty], (child) -> {
                    heads_may_overlap_freshen(pool, child, symbols, vars)
                }),
            )
        },
    }
}

// port: baml_compiler2_hir_ty/src/coherence.rs::renamed_var @ d9be6853b
// Fresh unification param for side `prefix`'s `idx`-th generic param.
function renamed_var(prefix: string, idx: int) -> root.types.ParamTy throws never {
    root.types.ParamTy { index: idx, name: `__coherence_${prefix}_${idx}` }
}

// port: baml_compiler2_hir_ty/src/coherence.rs::substitute_plain @ d9be6853b
// Substitute `bindings` into a plain type by param identity. Unlike
// `root.types.substitute_ty`, a rebuilt union is not re-normalized.
function substitute_plain(
    ty: root.types.Ty,
    bindings: root.types.TypeBindings,
) -> root.types.Ty throws never {
    let all = (tys: root.types.Ty[]) -> root.types.Ty[] {
        tys.map((t) -> {
            substitute_plain(t, bindings)
        })
    };
    match (ty) {
        let v: root.types.TyTypeVar => bindings.get(v.param) ?? ty,
        let u: root.types.TyUnion => root.types.TyUnion { members: all(u.members) },
        let t: root.types.TyTuple => root.types.TyTuple { items: all(t.items) },
        let c: root.types.TyClass => root.types.TyClass { name: c.name, args: all(c.args) },
        let i: root.types.TyInterface => {
            root.types.TyInterface {
                name: i.name,
                args: all(i.args),
                associated_types: i.associated_types.map((b) -> {
                    root.types.AssociatedType { name: b.name, ty: substitute_plain(b.ty, bindings) }
                }),
            }
        },
        let l: root.types.TyList => root.types.TyList { elem: substitute_plain(l.elem, bindings) },
        let m: root.types.TyMap => {
            root.types.TyMap {
                key: substitute_plain(m.key, bindings),
                value: substitute_plain(m.value, bindings),
            }
        },
        let f: root.types.TyFuture => {
            root.types.TyFuture {
                value: substitute_plain(f.value, bindings),
                error: substitute_plain(f.error, bindings),
            }
        },
        let p: root.types.TyAssociatedTypeProjection => {
            root.types.TyAssociatedTypeProjection {
                base: substitute_plain(p.base, bindings),
                interface_: root.types.map_tys(p.interface_, (t) -> {
                    substitute_plain(t, bindings)
                }),
                member: p.member,
            }
        },
        let f: root.types.TyFunction => {
            root.types.TyFunction {
                params: f.params.map((param) -> {
                    root.types.FunctionParamTy {
                        name: param.name,
                        ty: substitute_plain(param.ty, bindings),
                        mode: param.mode,
                    }
                }),
                ret: substitute_plain(f.ret, bindings),
                throws_: substitute_plain(f.throws_, bindings),
            }
        },
        _ => ty,
    }
}

// port: baml_compiler2_hir_ty/src/coherence.rs::CoherenceViolation @ d9be6853b
// Two implementations of the same interface that overlap, or could not be
// proven disjoint. Location-keyed (impl locs, no spans).
class CoherenceViolation {
    // The offending impl, always owned by the package being checked.
    primary: int,
    // The impl it overlaps with; may live in a dependency package.
    secondary: int,
    // Overlap could be neither proven nor disproven (conservatively
    // rejected) rather than definite.
    indeterminate: bool,
}

// port: baml_compiler2_hir_ty/src/coherence.rs::package_coherence_violations @ d9be6853b
// Overlapping implementations across `pkg` and its dependency closure. Only
// pairs with at least one impl owned by `pkg` are reported;
// dependency-internal conflicts belong to the dependency's own check.
function package_coherence_violations(
    db: root.hir.Db,
    pkg: int,
) -> CoherenceViolation[] throws never {
    // Stable textual order for attribution (the later impl carries the
    // error): key on (file path, span start).
    let own = package_impls(db, pkg).sort_by((a, b) -> {
        let (let a_path, let a_start) = impl_sort_key(db, a.0);
        let (let b_path, let b_start) = impl_sort_key(db, b.0);
        let by_path = a_path.cmp(b_path);
        if (by_path != baml.ops.Ordering.Equal) {
            by_path
        } else {
            a_start.cmp(b_start)
        }
    });

    let alias_ctx = root.types.AliasEquivCtx {
        aliases: root.hir_ty.interfaces.normalized_alias_map(db, pkg),
        lang: root.hir.lang_roots(db),
    };
    let dep_impls = root.hir.package_dependency_closure(db, pkg).flat_map((dep) -> {
        package_impls(db, dep)
    });

    let violations: CoherenceViolation[] = [];
    for (let i = 0; i < own.length(); i += 1) {
        let (let own_loc, let own_facts) = own[i];
        // own x own: each unordered pair once; the later impl is primary.
        for (let other in own.slice(i + 1, own.length())) {
            let indeterminate = overlap_violation(impls_conflict(db, own_facts, other.1, alias_ctx));
            if (indeterminate != null) {
                violations.push(
                    CoherenceViolation {
                        primary: other.0,
                        secondary: own_loc,
                        indeterminate: indeterminate,
                    },
                );
            }
        }
        // own x dependency: the owning package's impl is primary.
        for (let dep in dep_impls) {
            let indeterminate = overlap_violation(impls_conflict(db, own_facts, dep.1, alias_ctx));
            if (indeterminate != null) {
                violations.push(
                    CoherenceViolation {
                        primary: own_loc,
                        secondary: dep.0,
                        indeterminate: indeterminate,
                    },
                );
            }
        }
    }
    violations
}

// port: baml_compiler2_hir_ty/src/coherence.rs::overlap_violation @ d9be6853b
// null = disjoint; otherwise report, `true` when indeterminate.
function overlap_violation(overlap: root.types.Overlap) -> bool? throws never {
    match (overlap) {
        root.types.Overlap.No => null,
        root.types.Overlap.Yes => false,
        root.types.Overlap.Unknown => true,
    }
}

// port: baml_compiler2_hir_ty/src/coherence.rs::package_impls @ d9be6853b
// The impls of `pkg` whose headers resolved, with their facts.
function package_impls(db: root.hir.Db, pkg: int) -> (int, ImplFacts)[] throws never {
    package_impl_locs(db, pkg).filter_map((loc) -> {
        let facts = impl_header_resolution_resolved(impl_facts(db, loc))
            ?? return null;
        (loc, facts)
    })
}

// port: baml_compiler2_hir_ty/src/coherence.rs::impl_sort_key @ d9be6853b
function impl_sort_key(db: root.hir.Db, loc: int) -> (string, int) throws never {
    let span = root.hir.impl_block_source_map(db, loc).span;
    (db.file(db.impl_locs.get(loc).file).path, span.start)
}

// port: baml_compiler2_hir_ty/src/coherence.rs::impls_conflict @ d9be6853b
// Whether two impls of the SAME interface conflict. Distinct interfaces
// never conflict; a duplicate in-body block is a degenerate overlap. No
// concreteness gate: an impl whose for-target is not an implementor never
// has resolved facts, so it cannot reach here.
function impls_conflict(
    db: root.hir.Db,
    a: ImplFacts,
    b: ImplFacts,
    aliases: root.types.AliasEquivCtx,
) -> root.types.Overlap throws never {
    if (a.interface_.reference.name != b.interface_.reference.name) {
        return root.types.Overlap.No;
    }
    impls_overlap(db, a, b, aliases)
}

// port: baml_compiler2_hir_ty/src/coherence.rs::impls_overlap @ d9be6853b
// Conservative symmetric overlap over two impls of the same interface: do
// the subjects (for-type + interface args) share a common instance? Both
// impls' params become fresh disjoint unification variables. A bound on a
// param the unifier pinned to a ground witness is checked against the
// registry; a provable violation makes the pair disjoint.
function impls_overlap(
    db: root.hir.Db,
    a: ImplFacts,
    b: ImplFacts,
    aliases: root.types.AliasEquivCtx,
) -> root.types.Overlap throws never {
    let facts = Facts.new(db);
    let enum_variants = (qtn: root.types.DeclName) -> string[]? {
        facts.enum_variants(qtn)
    };
    let pool = db.ty_memo.pool;
    let (let a_for, let a_args) = renamed_subject(pool, a, "a", enum_variants);
    let (let b_for, let b_args) = renamed_subject(pool, b, "b", enum_variants);
    if (a_args.length() != b_args.length()) {
        return root.types.Overlap.No;
    }
    let vars: root.types.ParamTy[] = [];
    for (let i = 0; i < a.generic_params.length(); i += 1) {
        vars.push(renamed_var("a", i));
    }
    for (let i = 0; i < b.generic_params.length(); i += 1) {
        vars.push(renamed_var("b", i));
    }

    let bindings: root.types.TypeBindings = {};
    let result = root.types.unify_into(a_for, b_for, vars, aliases, bindings);
    if (result == root.types.Overlap.No) {
        return root.types.Overlap.No;
    }
    for (let i = 0; i < a_args.length(); i += 1) {
        match (root.types.unify_into(a_args[i], b_args[i], vars, aliases, bindings)) {
            root.types.Overlap.No => {
                return root.types.Overlap.No;
            },
            root.types.Overlap.Unknown => {
                result = root.types.Overlap.Unknown;
            },
            root.types.Overlap.Yes => {},
        }
    }

    let a_subject = [a_for].concat(a_args);
    let b_subject = [b_for].concat(b_args);
    if (
        !bounds_hold_at_common_instance(db, a, "a", vars, bindings, a_subject)
            || !bounds_hold_at_common_instance(db, b, "b", vars, bindings, b_subject)
    ) {
        return root.types.Overlap.No;
    }
    result
}

// port: baml_compiler2_hir_ty/src/coherence.rs::bounds_hold_at_common_instance @ d9be6853b
// Whether every bound of this impl could hold at the common instance.
// False only on a PROVABLE violation: the binding is principal (not a
// union-cover witness), the witness fully realized, and the instantiated
// bound fully realized; then no impl from the registry means the witness
// does not implement it.
function bounds_hold_at_common_instance(
    db: root.hir.Db,
    rule: ImplFacts,
    prefix: string,
    vars: root.types.ParamTy[],
    bindings: root.types.TypeBindings,
    subject: root.types.Ty[],
) -> bool throws never {
    let pool = db.ty_memo.pool;
    let param_witnesses: root.types.TypeBindings = {};
    for (let j = 0; j < rule.generic_params.length(); j += 1) {
        param_witnesses[rule.generic_params[j].0]
            = root.types.chase_var(
                root.types.TyTypeVar { param: renamed_var(prefix, j) },
                vars,
                bindings,
            );
    }

    for (let i = 0; i < rule.generic_params.length(); i += 1) {
        let (let param, let bounds) = rule.generic_params[i];
        if (bounds.length() == 0) {
            continue;
        }
        let var_i = renamed_var(prefix, i);
        if (
            subject.some((t) -> {
                root.types.var_under_union(var_i, t)
            })
        ) {
            continue;
        }
        let witness = param_witnesses[param];
        if (root.types.contains_bound_typevar(witness, vars) || !root.types.realized(witness)) {
            continue;
        }
        for (let declared in bounds) {
            let bound = root.types.map_tys(declared.to_plain(pool), (t) -> {
                substitute_plain(t, param_witnesses)
            });
            if (
                root.types.tys(bound).every((t) -> {
                    root.types.realized(t)
                })
                    && resolve_impl(
                        db,
                        pool.from_plain(witness),
                        root.types.infer_interface_from_constraint(pool, bound),
                    )
                        == null
            ) {
                return false;
            }
        }
    }
    true
}

// port: baml_compiler2_hir_ty/src/coherence.rs::renamed_subject @ d9be6853b
// The impl's subject (for-type and interface args) normalized with its
// generic params renamed to side-`prefix` unification variables.
// Associated bindings are dropped (interface outputs, not overlap inputs).
// Restructured: takes the pool the closed facts are interned in.
function renamed_subject(
    pool: root.types.InferPool,
    rule: ImplFacts,
    prefix: string,
    enum_variants: root.types.EnumVariants,
) -> (root.types.Ty, root.types.Ty[]) throws never {
    let rename: root.types.TypeBindings = {};
    for (let i = 0; i < rule.generic_params.length(); i += 1) {
        rename[rule.generic_params[i].0] = root.types.TyTypeVar { param: renamed_var(prefix, i) };
    }
    let for_ty = root.types.nf(
        substitute_plain(pool.to_plain_closed(rule.for_ty_pattern.ty), rename),
        enum_variants,
    );
    let args = rule.interface_.to_plain(pool).generics.map((arg) -> {
        root.types.nf(substitute_plain(arg, rename), enum_variants)
    });
    (for_ty, args)
}

// port: baml_compiler2_hir_ty/src/coherence.rs::OrphanViolation @ d9be6853b
// An orphan-rule violation on one impl: a foreign interface implemented
// with no local type covering the impl, or an uncovered generic param
// before the first local type.
class OrphanViolation {
    block: int,
    interface_: root.types.DeclName,
    // Set: the RFC-2451 uncovered-param flavor; null: no local type anywhere
    // in the impl's inputs.
    uncovered_param: string?,
}

// port: baml_compiler2_hir_ty/src/coherence.rs::package_orphan_violations @ d9be6853b
// Every impl must implement a local interface or cover a local type
// (RFC-2451: the first local class/enum in the impl's inputs, the for-type
// then the interface args, with any generic param before it uncovered).
function package_orphan_violations(db: root.hir.Db, pkg: int) -> OrphanViolation[] throws never {
    let pool = db.ty_memo.pool;
    package_impls(db, pkg).filter_map((entry) -> {
        let (let loc, let facts) = entry;
        let interface_ = facts.interface_.reference.name;
        let for_ty = pool.to_plain_closed(facts.for_ty_pattern.ty);
        let args = facts.interface_.to_plain(pool).generics;
        match (orphan_check(pkg, interface_, for_ty, args)) {
            OrphanOutcomeOk => null,
            let u: OrphanOutcomeUncoveredParam => {
                OrphanViolation { block: loc, interface_: interface_, uncovered_param: u.value }
            },
            OrphanOutcomeNoLocalType => {
                OrphanViolation { block: loc, interface_: interface_, uncovered_param: null }
            },
        }
    })
}

// port: baml_compiler2_hir_ty/src/coherence.rs::OrphanOutcome @ d9be6853b
type OrphanOutcome = OrphanOutcomeOk | OrphanOutcomeUncoveredParam | OrphanOutcomeNoLocalType;

class OrphanOutcomeOk {
}

// The uncovered param's name.
class OrphanOutcomeUncoveredParam {
    value: string,
}

class OrphanOutcomeNoLocalType {
}

// port: baml_compiler2_hir_ty/src/coherence.rs::orphan_check @ d9be6853b
function orphan_check(
    current_package: int,
    interface_: root.types.DeclName,
    for_ty: root.types.Ty,
    interface_args: root.types.Ty[],
) -> OrphanOutcome throws never {
    if (interface_.pkg == current_package) {
        return OrphanOutcomeOk {};
    }
    for (let input in [for_ty].concat(interface_args)) {
        match (input) {
            let c: root.types.TyClass if c.name.pkg == current_package => {
                return OrphanOutcomeOk {};
            },
            let e: root.types.TyEnum if e.name.pkg == current_package => {
                return OrphanOutcomeOk {};
            },
            let v: root.types.TyTypeVar => {
                return OrphanOutcomeUncoveredParam { value: v.param.name };
            },
            _ => {},
        }
    }
    OrphanOutcomeNoLocalType {}
}
