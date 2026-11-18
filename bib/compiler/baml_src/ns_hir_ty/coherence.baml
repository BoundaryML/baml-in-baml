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
// Not ported: the per-package coherence and orphan walks
// (`package_coherence_violations`, `package_orphan_violations`, and their
// helpers and tests); they serve only tests, and check.rs's
// `source_mounted_impl_conflict` acts only on mounted packages (none here).

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
