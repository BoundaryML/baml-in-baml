// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 6, finalize and solve: finalizing a recorded type (resolve, erase
// survivors, reduce projections, canonicalize unions), the bounded-variable
// solver the finish fixpoint and structure demands share, the deferred-sub
// and solved-bound re-drives, the pattern-overlap and blanket-bound oracles,
// the materialization of the working result into the plain one, and the
// free helpers over interned types.
//
// Restructured (BAML forces it):
// - Methods of `InferenceContext` are free functions taking `ctx` first; a
//   free function over interned types takes the pool first.
// - `ClosedTy::try_from(ty)` followed by a disposition is a `has_infer` test
//   and a `ClosedTy { ty: .. }` literal (the conversion is that one flag
//   test); the `unreachable!` arms of a conversion that cannot fail are gone.
// - Nested `fn`s are top-level functions named `<outer>_<inner>`.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::plain_finalized @ d9be6853b
// `finalize_ty` plus the total plain exit: the one-step form for diagnostic
// payloads and other plain-vocabulary consumers inside `finish`.
function plain_finalized(ctx: InferenceContext, ty: int) -> root.types.Ty throws never {
    ctx.table.pool.to_plain_closed(finalize_ty(ctx, ty).ty)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finalize_ty @ d9be6853b
// One recorded type, finalized: solved variables substituted, survivors
// erased to the local Error sentinel, unions re-canonicalized. The
// `ClosedTy` return is the finalize guarantee: nothing leaves still
// carrying a variable.
function finalize_ty(ctx: InferenceContext, ty: int) -> root.types.ClosedTy throws never {
    let pool = ctx.table.pool;
    let resolved = ctx.table.resolve_completely(ty);
    let erased = erase_infer(pool, resolved);
    if (pool.has_error(erased.ty)) {
        // Errors stay LOCAL, but the cleanup pass still runs: the union
        // constructor is identity-safe on error members, so one erased var no
        // longer leaves the whole tree's unions syntactic.
        return canonicalize_unions(ctx, erased);
    }
    let reduced = reduce_projections(ctx, erased, PROJECTION_FINALIZE_FUEL);
    canonicalize_unions(ctx, reduced)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finalize_emission_ty @ d9be6853b
// Finalize a written type for runtime emission: the same substitution,
// inference cleanup, and projection reduction as `finalize_ty`, but every
// union node keeps its written order (no union set algebra).
function finalize_emission_ty(ctx: InferenceContext, ty: int) -> root.types.ClosedTy throws never {
    let resolved = ctx.table.resolve_completely(ty);
    let erased = erase_infer(ctx.table.pool, resolved);
    reduce_projections(ctx, erased, PROJECTION_FINALIZE_FUEL)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::deduped_unions @ d9be6853b
// A type with every union node's SPELLING normalized: members resolved,
// flattened, `never` dropped, duplicates removed. Dedup only, not the
// canonical algebra (absorption and literal-into-base erase literal
// freshness, which flow narrowing reads). The descent is memoized per call
// on the interned handle, so a DAG is visited once per node.
function deduped_unions(ctx: InferenceContext, ty: int) -> int throws never {
    deduped_unions_memo(ctx, ty, {})
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::deduped_unions_memo @ d9be6853b
function deduped_unions_memo(
    ctx: InferenceContext,
    ty: int,
    memo: map<int, int>,
) -> int throws never {
    let cached = memo.get(ty);
    if (cached != null) {
        return cached;
    }
    let pool = ctx.table.pool;
    let resolved = ctx.table.resolve_completely(ty);
    let deduped = if (pool.has_union(resolved)) {
        let rebuilt = pool.add(
            root.types.map_children(pool.kinds[resolved], (child) -> {
                deduped_unions_memo(ctx, child, memo)
            }),
        );
        match (pool.kinds[rebuilt]) {
            let u: root.types.InferTyUnion => syntactic_union(pool, u.members),
            _ => rebuilt,
        }
    } else {
        resolved
    };
    memo[ty] = deduped;
    deduped
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::reduce_projections @ d9be6853b
// Post-substitution projection normalization: every projection the oracle
// can determine reduces, so results and renders show what the type IS
// (`(IntStore as Store).Item` finalizes as `int`). Targeted rather than full
// canonicalization, which would also expand nominal aliases.
function reduce_projections(
    ctx: InferenceContext,
    ty: root.types.ClosedTy,
    fuel: int,
) -> root.types.ClosedTy throws never {
    let pool = ctx.table.pool;
    if (fuel == 0 || !pool.has_projection(ty.ty)) {
        return ty;
    }
    let rebuilt = ty.map_children(pool, (child) -> {
        reduce_projections(ctx, child, fuel)
    });
    // Node-local normalization: a ground projection reduces through the
    // oracle, handed its native (plain) vocabulary.
    if (pool.kinds[rebuilt.ty] is root.types.InferTyAssociatedTypeProjection) {
        if let plain: root.types.TyAssociatedTypeProjection = pool.to_plain_closed(rebuilt.ty) {
            match (ctx.facts.project(plain.base, plain.interface_, plain.member, fuel)) {
                let step: root.types.ProjectionStepReduced => {
                    return reduce_projections(ctx, root.types.ClosedTy { ty: pool.from_plain(step.ty) }, fuel - 1);
                },
                root.types.ProjectionStepOpaque => {},
            }
        }
    }
    rebuilt
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::iteration_item @ d9be6853b
// The element a `for (let x in coll)` loop yields for a non-list collection:
// the projection `(coll as baml.iter.Iterable).Item`, reduced through the
// oracle. A projection the oracle cannot determine stays the error sentinel:
// iteration over a type with no `Iterable` evidence has no element type.
function iteration_item(ctx: InferenceContext, collection: int, at: int) -> int throws never {
    let pool = ctx.table.pool;
    let iterable_decl = lang_decl(ctx, root.base.LangPackage.Baml, ["iter"], "Iterable");
    if (iterable_decl == null) {
        return pool.add(root.types.TyError {});
    }
    let iterable = root.types.infer_interface_new(iterable_decl, [], []);
    // rustc's for-desugar is an `into_iter` CALL: the iterability obligation
    // registers against the collection, and the element is the Item
    // projection, resolved through the same structure demand receivers use.
    root.hir_ty.infer.register_obligation(
        ctx,
        root.hir_ty.infer.obligation_implements(
            collection,
            iterable,
            at,
            root.hir_ty.infer.GoalPurpose.Coercion,
        ),
    );
    let existential = root.types.infer_interface_existential(pool, iterable);
    let projection = pool.add(
        root.types.InferTyAssociatedTypeProjection {
            base: collection,
            interface_: iterable,
            member: "Item",
        },
    );
    let reduced = structurally_resolve(ctx, projection);
    if (pool.has_projection(reduced) && !pool.has_infer(reduced)) {
        // Ground and irreducible: a collection that fails `Iterable` reports
        // E0006, so its element is the diagnosed error sentinel; one that
        // satisfies the bound keeps the projection as the element. Judge
        // only a CLOSED collection, and canonicalize only under that gate.
        let resolved_collection = ctx.table.resolve_completely(collection);
        if (!pool.has_infer(resolved_collection)) {
            let canonical = canonicalize_unions(ctx, root.types.ClosedTy { ty: resolved_collection });
            if (!cached_subtype(ctx, canonical.ty, existential)) {
                return pool.add(root.types.TyError {});
            }
        }
    }
    reduced
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::canonicalize_unions @ d9be6853b
// Rebuilds `ty` with every union node in canonical form, bottom-up.
// Idempotent on canonical types; repairs the syntactic unions `union_of`
// built while a member still carried a variable. Presentation order: `null`
// moves LAST (the optional convention).
function canonicalize_unions(
    ctx: InferenceContext,
    ty: root.types.ClosedTy,
) -> root.types.ClosedTy throws never {
    let cached = ctx.canonical_unions.get(ty.ty);
    if (cached != null) {
        return root.types.ClosedTy { ty: cached };
    }
    let result = canonicalize_unions_uncached(ctx, ty);
    ctx.canonical_unions[ty.ty] = result.ty;
    result
}

// The body of `canonicalize_unions`, before its per-context cache.
function canonicalize_unions_uncached(
    ctx: InferenceContext,
    ty: root.types.ClosedTy,
) -> root.types.ClosedTy throws never {
    let pool = ctx.table.pool;
    match (pool.kinds[ty.ty]) {
        root.types.InferTyUnion => {
            let members: root.types.ClosedTy[] = [];
            ty.for_each_child(pool, (member) -> {
                members.push(canonicalize_unions(ctx, member));
            });
            // Error-carrying unions clean up STRUCTURALLY only: the canonical
            // algebra treats the Error sentinel as bidirectionally
            // compatible, so a member like `!error[]` would merge into
            // `int[]` and vanish. Flatten, dedup and collapse; skip
            // absorption.
            if (
                members.some((member) -> {
                    pool.has_error(member.ty)
                })
            ) {
                let raw = members.map((member) -> {
                    member.ty
                });
                return root.types.ClosedTy { ty: syntactic_union(pool, raw) };
            }
            let joined = root.types.canonical_union_interned(pool, members, ctx.facts);
            match (pool.kinds[joined.ty]) {
                let u: root.types.InferTyUnion => {
                    let ordered = u.members.filter((member) -> {
                        !(pool.kinds[member] is root.types.TyNull)
                    });
                    let nulls = u.members.filter((member) -> {
                        pool.kinds[member] is root.types.TyNull
                    });
                    root.types.ClosedTy {
                        ty: pool.add(root.types.InferTyUnion { members: ordered.concat(nulls) }),
                    }
                },
                _ => joined,
            }
        },
        _ => {
            ty.map_children(pool, (child) -> {
                canonicalize_unions(ctx, child)
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::resolve_bounded_vars @ d9be6853b
// Derives solutions from accumulated bounds, iterating because one
// resolution can make another class's bounds ground. Returns whether
// anything solved.
function resolve_bounded_vars(ctx: InferenceContext, tier: SolveTier) -> bool throws never {
    let any = false;
    while (true) {
        let progressed = false;
        for (let entry in ctx.table.unsolved_bounded_vars()) {
            if (try_solve_bounded_var_tiered(ctx, entry.0, entry.1, tier)) {
                progressed = true;
            }
        }
        if (!progressed) {
            break;
        }
        any = true;
    }
    any
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::try_solve_bounded_var_tiered @ d9be6853b
// The tier gate in front of `try_solve_bounded_var`: the eager tier solves
// only FULLY-ground classes; a class with var-carrying bounds waits, because
// a sibling those bounds mention may still be solvable. The ground-subset
// tier is the quiescence fallback.
function try_solve_bounded_var_tiered(
    ctx: InferenceContext,
    var: int,
    bounds: root.hir_ty.infer.VarBounds,
    tier: SolveTier,
) -> bool throws never {
    if (tier == SolveTier.Ground) {
        let fully_ground = bounds.lowers.concat(bounds.uppers).every((bound) -> {
            !ctx.table.pool.has_infer(ctx.table.resolve_completely(bound.ty))
        });
        if (!fully_ground) {
            return false;
        }
    }
    try_solve_bounded_var(ctx, var, bounds)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::try_solve_bounded_var @ d9be6853b
// One bounded class's resolution step, the shared core of the finish
// fixpoint and `structurally_resolve`. The GROUND SUBSET of the bounds
// decides; bounds still carrying variables move to the deferred residue for
// post-hoc verification. Returns whether the class was solved (or aliased).
function try_solve_bounded_var(
    ctx: InferenceContext,
    var: int,
    bounds: root.hir_ty.infer.VarBounds,
) -> bool throws never {
    // A sibling's generalization step may have ALIASED this var into a
    // solved class since the caller collected its list.
    if (ctx.table.is_solved(var)) {
        return false;
    }
    let pool = ctx.table.pool;
    let resolve = (bound: root.hir_ty.infer.Bound) -> root.hir_ty.infer.Bound {
        root.hir_ty.infer.Bound { ty: ctx.table.resolve_completely(bound.ty), anchor: bound.anchor }
    };
    let resolved_lowers = bounds.lowers.map(resolve);
    let lower_bounds = resolved_lowers.filter((bound) -> {
        !pool.has_infer(bound.ty)
    });
    let deferred_lowers = resolved_lowers.filter((bound) -> {
        pool.has_infer(bound.ty)
    });
    // A TOP-TYPE upper is no constraint and therefore no EVIDENCE: the
    // minimum-upper meet must not commit a class to `unknown` from a vacuous
    // bound while real evidence is still en route.
    let resolved_uppers = bounds.uppers.map(resolve).filter((bound) -> {
        !(pool.kinds[bound.ty] is root.types.TyUnknown)
    });
    let upper_bounds = resolved_uppers.filter((bound) -> {
        !pool.has_infer(bound.ty)
    });
    let deferred_uppers = resolved_uppers.filter((bound) -> {
        pool.has_infer(bound.ty)
    });
    let lowers = lower_bounds.map((bound) -> {
        bound.ty
    });
    let uppers = upper_bounds.map((bound) -> {
        bound.ty
    });
    if (lowers.length() == 0 && uppers.length() == 0) {
        // GENERALIZATION: a var whose only information is one var-carrying
        // lower (or several identical ones) and no uppers is an ALIAS of
        // that lower; solving it is occurs-guarded union-find aliasing, not
        // a premature meet. DISTINCT var-carrying lowers stay deferred (the
        // operator-deadlock rule).
        if (deferred_uppers.length() == 0 && deferred_lowers.length() > 0) {
            let alias = deferred_lowers[0].ty;
            let all_same = deferred_lowers.every((lower) -> {
                lower.ty == alias
            });
            if (all_same) {
                let unified = true;
                ctx.table.unify(pool.add(root.types.TyInferVar { var: var }), alias) catch (e) {
                    root.hir_ty.infer.UnifyError => {
                        unified = false;
                    },
                };
                if (unified) {
                    return true;
                }
            }
        }
        return false;
    }
    let var_ty = pool.add(root.types.TyInferVar { var: var });
    for (let deferred in deferred_lowers) {
        ctx.journals.deferred_subs.push((deferred.ty, var_ty, deferred.anchor));
    }
    for (let deferred in deferred_uppers) {
        ctx.journals.deferred_subs.push((var_ty, deferred.ty, deferred.anchor));
    }
    let solution: int? = if (lowers.length() == 0) {
        // No values flowed in: the MINIMUM upper is the meet when one exists
        // (BAML has no intersections, so incomparable uppers have no
        // representable meet).
        uppers.find((candidate) -> {
            uppers.every((upper) -> {
                cached_subtype(ctx, candidate, upper)
            })
        })
    } else {
        let maximum = lowers_join(ctx, lowers, uppers);
        let fits = if (maximum != null) {
            let candidate: int = maximum;
            uppers.every((upper) -> {
                cached_subtype(ctx, candidate, upper)
            })
        } else {
            false
        };
        if (fits) {
            maximum
        } else {
            // No join under the uppers: genuinely incompatible demands. A
            // monomorphic source follows first-demand order: the first
            // ground demand wins so later incompatible demands report
            // through the provisional re-check at finalize. Other vars stay
            // unsolved, and quiescence reports the contradiction
            // (`report_contradictory_bounds`).
            let policy = ctx.table.unsolved_policy(var);
            if (policy != null && root.hir_ty.infer.first_demand_commits(policy)) {
                widen_fresh(ctx, lowers[0])
            } else {
                null
            }
        }
    };
    if (solution == null) {
        return false;
    }
    // A block-scoped parameter reaches the solution only through a bound
    // whose own variable was decided after the deposit. That bound is the
    // escape, reported where it was deposited; the class takes the `Error`
    // fill so the failure does not cascade.
    let param = ctx.table.escaping_scoped_param(var, solution);
    if (param != null) {
        let offending = lower_bounds.concat(upper_bounds).find((bound) -> {
            ctx.table.escaping_scoped_param(var, bound.ty) != null
        });
        if (offending != null) {
            let at = offending.anchor;
            if (at != null) {
                report_scoped_type_escape(ctx, at, param, offending.ty, ScopedTypeEscapeKindInferred {});
            } else {
                ctx.journals.anchorless_escapes.push((param, offending.ty));
            }
        } else {
            ctx.journals.anchorless_escapes.push((param, solution));
        }
        refuse_with_error_fill(ctx, var);
        return true;
    }
    ctx.table.solve(var, solution);
    true
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_contradictory_bounds @ d9be6853b
// Reports each value variable still unsolved at quiescence whose ground
// bounds contradict each other: its lower bounds have a join, and the join
// violates an upper bound. The mismatch is the violated upper against the
// join, at the expression the upper was recorded with. A bound carrying
// `Error`, and lowers with no common candidate, are left alone.
function report_contradictory_bounds(ctx: InferenceContext) -> void throws never {
    let pool = ctx.table.pool;
    let ground = (bounds: root.hir_ty.infer.Bound[]) -> root.hir_ty.infer.Bound[] {
        bounds
            .map((bound) -> {
                root.hir_ty.infer.Bound {
                    ty: ctx.table.resolve_completely(bound.ty),
                    anchor: bound.anchor,
                }
            })
            .filter((bound) -> {
                !pool.has_infer(bound.ty)
            })
    };
    for (let entry in ctx.table.unsolved_bounded_vars()) {
        let (let var, let bounds) = entry;
        if (ctx.table.unsolved_policy(var) != root.hir_ty.infer.VarPolicy.Value) {
            continue;
        }
        let lower_bounds = ground(bounds.lowers);
        let upper_bounds = ground(bounds.uppers).filter((bound) -> {
            !(pool.kinds[bound.ty] is root.types.TyUnknown)
        });
        if (
            lower_bounds.length() == 0
                || upper_bounds.length() == 0
                || lower_bounds.concat(upper_bounds).some((bound) -> {
                    pool.has_error(bound.ty)
                })
        ) {
            continue;
        }
        let lowers = lower_bounds.map((bound) -> {
            bound.ty
        });
        let uppers = upper_bounds.map((bound) -> {
            bound.ty
        });
        let joined = lowers_join(ctx, lowers, uppers);
        if (joined == null) {
            continue;
        }
        let join: int = joined;
        let violated = upper_bounds.find((upper) -> {
            !cached_subtype(ctx, join, upper.ty)
        });
        if (violated == null) {
            continue;
        }
        let anchor = violated.anchor
            ?? lower_bounds
                .find((bound) -> {
                    bound.anchor != null
                })
                ?.anchor
            ?? ctx.body_root;
        if (anchor == null) {
            continue;
        }
        ctx.diagnosed_infer_vars[var] = true;
        if (!ctx.result.type_mismatches.has(anchor)) {
            ctx.result.type_mismatches[anchor] = (violated.ty, join);
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lowers_join @ d9be6853b
// The JOIN of a class's ground lower bounds under its ground `uppers`, or
// null when the lowers have no common candidate (BAML forms no union join
// here). The MAXIMUM lower is the join when one exists; raw candidates
// first, so an exact literal demand keeps the literal; fresh widening is the
// retry when raw candidates have no maximum. `lowers` must not be empty.
function lowers_join(ctx: InferenceContext, lowers: int[], uppers: int[]) -> int? throws never {
    let widened = lowers.map((ty) -> {
        widen_fresh(ctx, ty)
    });
    let widening: bool[] = [];
    for (let index = 0; index < lowers.length(); index += 1) {
        widening.push(lowers[index] != widened[index]);
    }
    let maximum_of = (candidates: int[]) -> int? {
        let subsumes_all = (candidate: int) -> bool {
            candidates.every((lower) -> {
                cached_subtype(ctx, lower, candidate)
            })
        };
        // Prefer a non-widening witness: the solution's freshness decides
        // binding-site widening later, and a rigid `3` holding a fresh `3`
        // must keep the demand rigid.
        for (let index = 0; index < candidates.length(); index += 1) {
            if (!widening[index] && subsumes_all(candidates[index])) {
                return candidates[index];
            }
        }
        candidates.find(subsumes_all)
    };
    // An ALL-widening candidate set widens by DEFAULT (`push(1)` infers
    // `int[]`); a non-widening candidate anchors the raw literals instead. A
    // default never overrides an actual constraint: when the widened join
    // violates an upper, the raw literals get their turn (`-> 42 { id(42) }`
    // is `42`, not Error).
    if (
        widening.every((flag) -> {
            flag
        })
    ) {
        let widest = maximum_of(widened);
        if (widest != null) {
            let candidate: int = widest;
            if (
                uppers.every((upper) -> {
                    cached_subtype(ctx, candidate, upper)
                })
            ) {
                return widest;
            }
        }
        return maximum_of(lowers);
    }
    maximum_of(lowers) ?? maximum_of(widened)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::structurally_resolve @ d9be6853b
// rustc's `structurally_resolve_type`: where the walk needs a type's
// STRUCTURE now (method receivers, field bases, index subjects), a
// still-unsolved head var is forced from the bounds it has accumulated SO
// FAR. Committing early is rustc's semantics: a later conflicting bound
// becomes a mismatch rather than a wider join. A class with no evidence yet
// stays a var.
function structurally_resolve(ctx: InferenceContext, ty: int) -> int throws never {
    let pool = ctx.table.pool;
    let resolved = root.hir_ty.infer.resolve_structure_operand(ctx, ty, {});
    // A projection blocked behind inference vars cannot PROBE: force the
    // occurring vars from their accumulated bounds.
    if (pool.has_infer(resolved) && pool.has_projection(resolved)) {
        resolved = force_occurring_vars(ctx, resolved);
    }
    // A member access on a union resolves through the ONE interface every
    // arm shares, so the arm count IS the structure here: commit the
    // occurring variables and relate the canonical spelling.
    if (pool.has_union(resolved)) {
        resolved = deduped_unions(ctx, resolved);
        if (pool.has_infer(resolved)) {
            resolved = force_occurring_vars(ctx, resolved);
            resolved = deduped_unions(ctx, resolved);
        }
    }
    // rustc's `structurally_resolve_type` NORMALIZES as well as resolving: a
    // ground reducible projection is not structure. One spelling, one
    // verdict: reduce over the canonical form.
    if (pool.has_projection(resolved) && !pool.has_infer(resolved)) {
        let canonical = canonicalize_unions(ctx, root.types.ClosedTy { ty: resolved });
        resolved = reduce_projections(ctx, canonical, PROJECTION_FINALIZE_FUEL).ty;
    }
    // Normalize the whole union/alias, not just an alias head. Recorded types
    // retain their written names; only structure demands use this spelling.
    // Open/error types stay on the structural path.
    let kind = pool.kinds[resolved];
    if (kind is root.types.TyTypeAlias || kind is root.types.InferTyUnion) {
        if (!pool.has_error(resolved) && !pool.has_infer(resolved)) {
            let normalized = ctx.canonical_cache.normalize(pool, root.types.ClosedTy { ty: resolved }, ctx.facts).ty;
            // Keep a surviving source arm's metadata, including literal
            // freshness and callable parameter names nested in containers.
            let source = resolved;
            let restore_arm = (arm_ty: int) -> int {
                unique_expected_arm(
                    ctx,
                    source,
                    (arm) -> {
                        if (cached_equivalent(ctx, arm, arm_ty)) {
                            arm
                        } else {
                            null
                        }
                    },
                    (a, b) -> {
                        let a_kind = pool.kinds[a];
                        let b_kind = pool.kinds[b];
                        if (a_kind is root.types.TyLiteral && b_kind is root.types.TyLiteral) {
                            return a == b;
                        }
                        if (
                            a_kind is root.types.InferTyFunction
                                && b_kind is root.types.InferTyFunction
                        ) {
                            let a_names = a_kind.params.map((param) -> {
                                param.name
                            });
                            let b_names = b_kind.params.map((param) -> {
                                param.name
                            });
                            return a_names == b_names;
                        }
                        true
                    },
                )
                    ?? arm_ty
            };
            return match (pool.kinds[normalized]) {
                let u: root.types.InferTyUnion => syntactic_union(pool, u.members.map(restore_arm)),
                _ => restore_arm(normalized),
            };
        }
        return root.hir_ty.expand_alias_head(ctx.table.pool, resolved, ctx.facts);
    }
    resolved
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::force_occurring_vars @ d9be6853b
// Forces every inference var OCCURRING in `ty` from its accumulated bounds,
// to fixpoint: the demand-point commitment shared by projection bases and
// match scrutinees, where deferral is impossible.
function force_occurring_vars(ctx: InferenceContext, ty: int) -> int throws never {
    let pool = ctx.table.pool;
    let resolved = ctx.table.resolve_completely(ty);
    while (true) {
        let found: int[] = [];
        collect_infer_vars(pool, resolved, found);
        found.sort_by_key((var) -> {
            var
        });
        let vars: int[] = [];
        for (let var in found) {
            if (vars.length() == 0 || vars[vars.length() - 1] != var) {
                vars.push(var);
            }
        }
        let progressed = false;
        for (let var in vars) {
            let bounds = ctx.table.var_bounds(var);
            if (try_solve_bounded_var(ctx, var, bounds)) {
                progressed = true;
            }
        }
        // A var pinned by an associated type of a not-yet-selected impl has
        // no bounds of its own: only discharging the obligation that names it
        // solves it. Selection is licensed by a known head and stalls
        // otherwise.
        if (!progressed && !root.hir_ty.infer.discharge_obligations_once(ctx)) {
            break;
        }
        resolved = ctx.table.resolve_completely(resolved);
        if (!pool.has_infer(resolved)) {
            break;
        }
    }
    resolved
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::callback_param_for_effect @ d9be6853b
// The name of the parameter whose function type carries `effect` in throws
// position: the callback a synthetic effect param belongs to.
function callback_param_for_effect(
    ctx: InferenceContext,
    effect: root.types.ParamTy,
) -> string? throws never {
    let function_ = owner_function(ctx);
    if (function_ == null) {
        return null;
    }
    let data = root.hir.function_data(ctx.db, function_);
    let param_tys = ctx.param_tys.concat([]);
    for (let index = 0; index < param_tys.length(); index += 1) {
        let resolved = ctx.table.resolve_completely(param_tys[index]);
        let callback = callback_root_fn(ctx, resolved);
        if (callback == null) {
            continue;
        }
        let throws_ = match (ctx.table.pool.kinds[callback]) {
            let f: root.types.InferTyFunction => f.throws_,
            _ => baml.sys.panic("callback_root_fn returns a function type"),
        };
        if let var: root.types.TyTypeVar = ctx.table.pool.kinds[throws_] {
            if (var.param == effect) {
                return data.params.at(index)?.name;
            }
        }
    }
    null
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::local_binding_names_at @ d9be6853b
// Every local value name in the expression's lexical scope and its
// ancestors: the near-match candidate pool for shorthand suggestions.
function local_binding_names_at(ctx: InferenceContext, expr: int) -> string[] throws never {
    let names: string[] = [];
    let key = metadata_key(ctx, expr);
    if (key == null) {
        return names;
    }
    let scope = ctx.index.expression_scope(key);
    if (scope == null) {
        return names;
    }
    for (let ancestor in ctx.index.ancestor_scopes(scope)) {
        let bindings = ctx.index.scope_bindings[ancestor];
        for (let binding in bindings.bindings) {
            names.push(binding.name);
        }
        for (let param in bindings.params) {
            names.push(param.0);
        }
    }
    names
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::first_failing_blanket_bound @ d9be6853b
// The failing bound of an ALMOST-matching blanket impl for an interface
// expectation: null when no impl's implementor shape matches the value, or
// every matching impl's bounds hold. Diagnostic refinement only.
function first_failing_blanket_bound(
    ctx: InferenceContext,
    actual: int,
    expected: int,
) -> root.types.Ty? throws never {
    let pool = ctx.table.pool;
    if (pool.has_infer(actual) || pool.has_infer(expected)) {
        return null;
    }
    let pkg = root.hir.file_package(ctx.db, ctx.owner_file).root_id;
    let aliases = overlap_alias_map(ctx);
    let failing = root.hir_ty.interfaces.first_failing_impl_bound(ctx.db, pkg, rendered_plain(pool, actual), rendered_plain(pool, expected), aliases, (
        a,
        b,
    ) -> {
        ctx.facts.is_subtype(a, b)
    });
    failing?.1
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::pattern_overlap_verdict @ d9be6853b
// The pattern-reachability oracle over this scope: can `pat` and `member`
// share a value under some realization of the in-scope rigid params?
// `Yes`/`Unknown` = possible, `No` = provably dead.
function pattern_overlap_verdict(
    ctx: InferenceContext,
    pat: root.types.Ty,
    member: root.types.Ty,
) -> root.types.Overlap throws never {
    let aliases = overlap_alias_map(ctx);
    root.types.pattern_overlap(
        pat,
        member,
        root.types.PatternOverlapEnv {
            vars: ctx.lower.generic_params,
            bounds: ctx.facts.bounds,
            aliases: aliases,
            lang: root.hir.lang_roots(ctx.db),
            enum_variants: (qtn) -> {
                ctx.facts.enum_variants(qtn)
            },
            implements_: (ty, iface) -> {
                ctx.facts.implements_interface(ty, iface)
            },
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::overlap_alias_map @ d9be6853b
// The oracle's alias input: every alias visible to the body's package (own
// plus dependency closure), bodies pre-folded to `nf`'s canonical union
// form. Built once per inference (Rust's `OnceCell`).
function overlap_alias_map(
    ctx: InferenceContext,
) -> map<root.types.DeclName, root.types.Ty> throws never {
    let cached = ctx.overlap_aliases;
    if (cached != null) {
        return cached;
    }
    let db = ctx.db;
    let pkg = root.hir.file_package(db, ctx.owner_file).root_id;
    let shared = db.ty_memo.overlap_alias_maps.get(pkg);
    if (shared != null) {
        ctx.overlap_aliases = shared;
        return shared;
    }
    let aliases: map<root.types.DeclName, root.types.Ty> = {};
    let packages = [pkg].concat(root.hir.package_dependency_closure(db, pkg));
    for (let pkg_id in packages) {
        let items = root.hir.package_items(db, pkg_id);
        for (let entry in items.namespaces) {
            let types = entry.1.types;
            for (let name in types.keys()) {
                if let alias: root.hir.DefinitionTypeAlias = types[name] {
                    let def_info = root.hir.file_package(db, db.type_alias_locs.get(alias.value).file);
                    let qtn = root.types.DeclName {
                        pkg: def_info.root_id,
                        namespace: def_info.namespace_path,
                        name: name,
                    };
                    if (!aliases.has(qtn)) {
                        aliases[qtn] = type_alias_value(db, alias.value);
                    }
                }
            }
        }
    }
    let enum_variants = (qtn: root.types.DeclName) -> string[]? {
        ctx.facts.enum_variants(qtn)
    };
    for (let qtn in aliases.keys()) {
        aliases[qtn] = root.types.nf(aliases[qtn], enum_variants);
    }
    ctx.overlap_aliases = aliases;
    db.ty_memo.overlap_alias_maps[pkg] = aliases;
    aliases
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::replay_solved_class_bounds @ d9be6853b
// Re-drives bounds accumulated on classes DIRECT unification has since
// solved: binding a variable discharges its pending evidence by replaying
// each bound against the solution, never by dropping it. Replay failures
// follow the anchorless-drop rule.
function replay_solved_class_bounds(ctx: InferenceContext) -> bool throws never {
    let solved = ctx.table.take_solved_class_bounds();
    let progressed = false;
    for (let entry in solved) {
        let (let solution, let bounds) = entry;
        for (let lower in bounds.lowers) {
            let saved_anchor = ctx.obligation_anchor;
            ctx.obligation_anchor = lower.anchor;
            sub(ctx, lower.ty, solution);
            ctx.obligation_anchor = saved_anchor;
            progressed = true;
        }
        for (let upper in bounds.uppers) {
            let saved_anchor = ctx.obligation_anchor;
            ctx.obligation_anchor = upper.anchor;
            sub(ctx, solution, upper.ty);
            ctx.obligation_anchor = saved_anchor;
            progressed = true;
        }
    }
    progressed
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::drain_deferred_subs @ d9be6853b
// Re-drives the deferred `Sub` residue inside the finish fixpoint: a pair
// whose counterpart has since RESOLVED decomposes through `sub` again. Pairs
// open on both sides wait; ground pairs retire (a failure reports at the
// expression that deposited it); a pair `sub` re-defers unchanged is not
// progress.
function drain_deferred_subs(ctx: InferenceContext) -> bool throws never {
    let pool = ctx.table.pool;
    let deferred = ctx.journals.deferred_subs;
    ctx.journals.deferred_subs = [];
    let progressed = false;
    for (let entry in deferred) {
        let (let raw_actual, let raw_expected, let anchor) = entry;
        // A pair deferred over a not-yet-canonical union becomes decidable
        // the moment its members ground out: re-relate the canonical
        // spelling.
        let actual = deduped_unions(ctx, raw_actual);
        let expected = deduped_unions(ctx, raw_expected);
        if (pool.has_infer(actual) && pool.has_infer(expected)) {
            ctx.journals.deferred_subs.push((actual, expected, anchor));
            continue;
        }
        if (!pool.has_infer(actual) && !pool.has_infer(expected)) {
            // A failed post-hoc bound reports at the expression that
            // deposited it; a pair a pattern walk deposited has no anchor and
            // drops.
            if (!cached_subtype(ctx, actual, expected) && anchor != null) {
                if (!ctx.result.type_mismatches.has(anchor)) {
                    ctx.result.type_mismatches[anchor] = (expected, actual);
                }
            }
            continue;
        }
        let saved_anchor = ctx.obligation_anchor;
        ctx.obligation_anchor = anchor;
        let before = ctx.journals.deferred_subs.length();
        sub(ctx, actual, expected);
        ctx.obligation_anchor = saved_anchor;
        let added = ctx.journals.deferred_subs.slice(before, ctx.journals.deferred_subs.length());
        let re_deferred = added.some((pair) -> {
            pair.0 == actual && pair.1 == expected
        });
        if (!re_deferred) {
            progressed = true;
        }
    }
    progressed
}

// port: baml_compiler2_hir_ty/src/infer.rs::skolemize_infer @ d9be6853b
// Replaces every unsolved inference var with a RIGID placeholder (a
// `TypeVar` named after the var, same var -> same placeholder) for the
// quiescence judgment: rigid vars are opaque to the subtype oracle, so the
// substituted pair fails only when NO solution could satisfy it.
function skolemize_infer(pool: root.types.InferPool, ty: int) -> int throws never {
    if (!pool.has_infer(ty)) {
        return ty;
    }
    if let v: root.types.TyInferVar = pool.kinds[ty] {
        return pool.add(
            root.types.TyTypeVar {
                param: root.types.ParamTy {
                    // Counted DOWN from the top of the declared space, below
                    // `SCOPED_PARAM_BIT`: a skolem is neither a declared frame
                    // position nor a block-scoped binding.
                    index: (root.types.SCOPED_PARAM_BIT - 1) - v.var,
                    name: `?${v.var}`,
                },
            },
        );
    }
    pool.add(
        root.types.map_children(pool.kinds[ty], (child) -> {
            skolemize_infer(pool, child)
        }),
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::collect_infer_vars @ d9be6853b
// Every unsolved inference var occurring in `ty`, for structural
// resolution's projection-base forcing.
function collect_infer_vars(pool: root.types.InferPool, ty: int, out: int[]) -> void throws never {
    if (!pool.has_infer(ty)) {
        return;
    }
    if let v: root.types.TyInferVar = pool.kinds[ty] {
        out.push(v.var);
    }
    for (let child in root.types.children_infer_ty(pool.kinds[ty])) {
        collect_infer_vars(pool, child, out);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::same_head_constructor @ d9be6853b
// Whether `source` and `target` share a head CONSTRUCTOR: the gate for
// recursing into a union target's single structured constituent.
function same_head_constructor(
    pool: root.types.InferPool,
    source: int,
    target: int,
) -> bool throws never {
    let s = pool.kinds[source];
    let t = pool.kinds[target];
    if (s is root.types.InferTyList && t is root.types.InferTyList) {
        return true;
    }
    if (s is root.types.InferTyMap && t is root.types.InferTyMap) {
        return true;
    }
    if (s is root.types.InferTyFuture && t is root.types.InferTyFuture) {
        return true;
    }
    if (s is root.types.InferTyClass && t is root.types.InferTyClass) {
        return s.name == t.name && s.args.length() == t.args.length();
    }
    if (s is root.types.InferTyTuple && t is root.types.InferTyTuple) {
        return s.items.length() == t.items.length();
    }
    if (s is root.types.InferTyInterface && t is root.types.InferTyInterface) {
        return s.name == t.name && s.args.length() == t.args.length();
    }
    if (s is root.types.InferTyFunction && t is root.types.InferTyFunction) {
        return s.params.length() == t.params.length();
    }
    false
}

// port: baml_compiler2_hir_ty/src/infer.rs::mentions_param_as_value @ d9be6853b
// Whether `param` occurs in `ty` other than as a member of a function type's
// `throws`: a VALUE occurrence.
function mentions_param_as_value(
    pool: root.types.InferPool,
    ty: int,
    param: root.types.ParamTy,
) -> bool throws never {
    match (pool.kinds[ty]) {
        let v: root.types.TyTypeVar => v.param == param,
        let f: root.types.InferTyFunction => {
            f.params.some((function_param) -> {
                mentions_param_as_value(pool, function_param.ty, param)
            })
                || mentions_param_as_value(pool, f.ret, param)
                || throws_mentions_param_as_value(pool, f.throws_, param)
        },
        let kind: root.types.InferTy => {
            root.types.children_infer_ty(kind).some((child) -> {
                mentions_param_as_value(pool, child, param)
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::throws_mentions_param_as_value @ d9be6853b
// `mentions_param_as_value` for a `throws` type: the parameter as a whole
// member (`throws E`, `throws E | Boom`) is an effect occurrence; anywhere
// deeper (`throws Box<E>`) it is a value.
function throws_mentions_param_as_value(
    pool: root.types.InferPool,
    throws_: int,
    param: root.types.ParamTy,
) -> bool throws never {
    match (pool.kinds[throws_]) {
        let v: root.types.TyTypeVar if v.param == param => false,
        let u: root.types.InferTyUnion => {
            u.members.some((member) -> {
                throws_mentions_param_as_value(pool, member, param)
            })
        },
        _ => mentions_param_as_value(pool, throws_, param),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::function_user_generic_params @ d9be6853b
// The user-written portion of a function's flattened generic frame. Owner
// parameters precede it and compiler-created callback-effect parameters
// follow it.
function function_user_generic_params(
    db: root.hir.Db,
    function_: int,
    signature: FunctionSignature,
) -> root.types.ParamTy[] throws never {
    let data = root.hir.elaborated_function_data(db, function_);
    let end = signature.generic_params.length() - data.synthetic_effect_params.length();
    if (end < 0) {
        baml.sys.panic("synthetic effect parameters are a suffix of the generic frame");
    }
    let start = end - data.user_generic_params.length();
    if (start < 0) {
        baml.sys.panic("user parameters precede synthetic effects in the generic frame");
    }
    signature.generic_params.slice(start, end)
}

// port: baml_compiler2_hir_ty/src/infer.rs::signature_mentions_param @ d9be6853b
// Whether `param` occurs in the signature's parameter types, return type or
// `throws`. Restructured: Rust interns each plain type and asks
// `ty_mentions_param`; interning preserves every `TypeVar` node, so the
// plain walk is the same answer without a pool.
function signature_mentions_param(
    signature: root.hir_ty.FunctionSignatureTy,
    throws_: root.types.Ty,
    param: root.types.ParamTy,
) -> bool throws never {
    let mentions = (ty: root.types.Ty) -> bool {
        root.types.contains_ty_where(ty, (node) -> {
            node is root.types.TyTypeVar && node.param == param
        })
    };
    signature.params.some((function_param) -> {
        mentions(function_param.ty)
    })
        || mentions(signature.return_type)
        || mentions(throws_)
}

// port: baml_compiler2_hir_ty/src/infer.rs::throws_clause_union @ d9be6853b
// The one type a `throws` clause must name to cover `facts`, in the order
// given, or null when nothing is thrown. A message quotes this SINGLE type
// so the renderer can parenthesize what needs it.
function throws_clause_union(facts: root.types.Ty[]) -> root.types.Ty? throws never {
    let members: root.types.Ty[] = [];
    for (let fact in facts) {
        if (!members.includes(fact)) {
            members.push(fact);
        }
    }
    match (members.length()) {
        0 => null,
        1 => members[0],
        _ => root.types.TyUnion { members: members },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::mentions_scoped_param @ d9be6853b
// Whether a finalized (plain) type names a block-scoped parameter.
function mentions_scoped_param(ty: root.types.Ty) -> bool throws never {
    root.types.contains_ty_where(ty, (candidate) -> {
        candidate is root.types.TyTypeVar
            && (candidate.param.index & root.types.SCOPED_PARAM_BIT) != 0
    })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_ty @ d9be6853b
// Inference finalize's exit through the `ClosedTy` boundary, TOTAL: a
// finalized (closed) value materializes directly; a value that arrives
// still open is finalized on the spot (Rust also debug-asserts there).
function materialize_ty(ctx: InferenceContext, ty: int) -> root.types.Ty throws never {
    if (!ctx.table.pool.has_infer(ty)) {
        return ctx.table.pool.to_plain_closed(ty);
    }
    plain_finalized(ctx, ty)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_interface @ d9be6853b
// `materialize_ty`'s satellite twin, for interface constraints (as
// `Interface::new`, bindings sorted by name).
function materialize_interface(
    ctx: InferenceContext,
    iface: root.types.InferInterfaceConstraint,
) -> root.types.InterfaceConstraint throws never {
    root.types.InterfaceConstraint {
        name: iface.name,
        generics: iface.generics.map((ty) -> {
            materialize_ty(ctx, ty)
        }),
        associated_types: iface.associated_types
            .map((binding) -> {
                root.types.AssociatedType {
                    name: binding.name,
                    ty: materialize_ty(ctx, binding.ty),
                }
            })
            .sort_by_key((binding) -> {
                binding.name
            }),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_result @ d9be6853b
// Materialize the finalized working result into the public plain artifact:
// the LAST step of `finish`. Every value conversion routes through
// `materialize_ty` / `materialize_interface`, field by field.
function materialize_result(
    ctx: InferenceContext,
    working: InferenceResult<int>,
) -> InferenceResult<root.types.Ty> throws never {
    let result: InferenceResult<root.types.Ty> = InferenceResult.empty(materialize_ty(ctx, working.throws_));
    for (let expr in working.type_of_expr.keys()) {
        result.type_of_expr[expr] = materialize_ty(ctx, working.type_of_expr[expr]);
    }
    for (let pat in working.type_of_pat.keys()) {
        result.type_of_pat[pat] = materialize_ty(ctx, working.type_of_pat[pat]);
    }
    for (let expr in working.type_mismatches.keys()) {
        let (let expected, let actual) = working.type_mismatches[expr];
        result.type_mismatches[expr] = (materialize_ty(ctx, expected), materialize_ty(ctx, actual));
    }
    result.non_exhaustive_matches = working.non_exhaustive_matches;
    result.diagnostics = working.diagnostics;
    for (let expr in working.member_resolutions.keys()) {
        result.member_resolutions[expr]
            = materialize_member_resolution(ctx, working.member_resolutions[expr]);
    }
    for (let expr in working.path_resolutions.keys()) {
        result.path_resolutions[expr]
            = ResolvedPath {
                segments: working.path_resolutions[expr].segments.map((segment) -> {
                    let resolution = segment.resolution;
                    ResolvedPathSegment {
                        ty: materialize_ty(ctx, segment.ty),
                        resolution: if (resolution != null) {
                            materialize_member_resolution(ctx, resolution)
                        } else {
                            null
                        },
                    }
                }),
            };
    }
    result.global_roots = working.global_roots;
    for (let expr in working.call_plans.keys()) {
        result.call_plans[expr] = materialize_call_plan(ctx, working.call_plans[expr]);
    }
    result.type_bindings = working.type_bindings;
    for (let expr in working.expr_adjustments.keys()) {
        result.expr_adjustments[expr]
            = working.expr_adjustments[expr].map((adjustment) -> {
                Adjustment { kind: adjustment.kind, target: materialize_ty(ctx, adjustment.target) }
            });
    }
    result
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_member_resolution @ d9be6853b
function materialize_member_resolution(
    ctx: InferenceContext,
    resolution: WorkingMemberResolution,
) -> MemberResolution throws never {
    match (resolution) {
        let r: MemberResolutionField => r,
        let r: MemberResolutionVariant => r,
        let r: MemberResolutionFree => r,
        let r: MemberResolutionMethod<int> => {
            let callee: MethodCallee = match (r.callee) {
                let c: MethodCalleeInherent => c,
                let c: MethodCalleeVirtual<int> => {
                    MethodCalleeVirtual {
                        interface_: c.interface_,
                        view: materialize_ty(ctx, c.view),
                        method: c.method,
                    }
                },
                let c: MethodCalleeConcrete<int> => {
                    MethodCalleeConcrete {
                        impl_block: c.impl_block,
                        func: c.func,
                        frame_type_args: c.frame_type_args.map((ty) -> {
                            materialize_ty(ctx, ty)
                        }),
                    }
                },
            };
            MemberResolutionMethod<root.types.Ty> { callee: callee, receiver: r.receiver }
        },
        let r: MemberResolutionInterfaceVirtualField<int> => {
            MemberResolutionInterfaceVirtualField {
                interface_: r.interface_,
                view: materialize_ty(ctx, r.view),
                field_index: r.field_index,
                field: r.field,
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::materialize_call_plan @ d9be6853b
function materialize_call_plan(
    ctx: InferenceContext,
    plan: CallPlan<int>,
) -> CallPlan<root.types.Ty> throws never {
    CallPlan {
        bindings: plan.bindings,
        argument_layout: plan.argument_layout,
        type_args: plan.type_args.map((ty) -> {
            materialize_ty(ctx, ty)
        }),
        own_offset: plan.own_offset,
        explicit: plan.explicit,
        slots: plan.slots.map((slot) -> {
            CallTypeArgPlan {
                ty: materialize_ty(ctx, slot.ty),
                emission_ty: materialize_ty(ctx, slot.emission_ty),
            }
        }),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::diagnostic_example_ty @ d9be6853b
// Turn a finalized, partially inferred type into a concrete diagnostic
// example without discarding the slots inference did solve. `int` is only a
// placeholder for still-unknown, unbounded slots.
function diagnostic_example_ty(pool: root.types.InferPool, ty: int) -> int throws never {
    match (pool.kinds[ty]) {
        root.types.TyError | root.types.TyInferVar => pool.add(root.types.TyInt {}),
        let kind: root.types.InferTy => {
            pool.add(
                root.types.map_children(kind, (child) -> {
                    diagnostic_example_ty(pool, child)
                }),
            )
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::finalize_member_resolution @ d9be6853b
// Finalize every type a recorded member resolution carries, in place. Both
// writeback sites (the expression table and each path-ladder segment) go
// through this.
function finalize_member_resolution(
    ctx: InferenceContext,
    resolution: WorkingMemberResolution,
) -> void throws never {
    match (resolution) {
        let r: MemberResolutionInterfaceVirtualField<int> => {
            r.view = finalize_ty(ctx, r.view).ty;
        },
        let r: MemberResolutionMethod<int> => {
            match (r.callee) {
                let c: MethodCalleeVirtual<int> => {
                    c.view = finalize_ty(ctx, c.view).ty;
                },
                let c: MethodCalleeConcrete<int> => {
                    c.frame_type_args
                        = c.frame_type_args.map((ty) -> {
                            finalize_ty(ctx, ty).ty
                        });
                },
                MethodCalleeInherent => {},
            }
        },
        MemberResolutionField | MemberResolutionVariant | MemberResolutionFree => {},
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::erase_infer @ d9be6853b
// Replaces every `Infer` node (unsolved variable or hole) with the Error
// sentinel. Precondition: every class this replaces has been reported, so
// the `Error` keeps its meaning ("a hard error was reported, do not
// cascade").
function erase_infer(pool: root.types.InferPool, ty: int) -> root.types.ClosedTy throws never {
    root.types.ClosedTy { ty: erase_infer_erase(pool, ty) }
}

// port: baml_compiler2_hir_ty/src/infer.rs::erase_infer::erase @ d9be6853b
function erase_infer_erase(pool: root.types.InferPool, ty: int) -> int throws never {
    if (!pool.has_infer(ty)) {
        return ty;
    }
    if (pool.kinds[ty] is root.types.TyInferVar) {
        return pool.add(root.types.TyError {});
    }
    pool.add(
        root.types.map_children(pool.kinds[ty], (child) -> {
            erase_infer_erase(pool, child)
        }),
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::rendered_plain @ d9be6853b
// The rename edge for helpers that cannot reach the table to finalize: a
// closed value materializes, and a live variable falls back to
// `infer_to_diagnostic_unknown`. NOT the way to put an undetermined type in
// a MESSAGE (use `plain_finalized`): `unknown` claims inference succeeded.
function rendered_plain(pool: root.types.InferPool, ty: int) -> root.types.Ty throws never {
    if (!pool.has_infer(ty)) {
        return pool.to_plain_closed(ty);
    }
    pool.to_plain_closed(infer_to_diagnostic_unknown(pool, ty))
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_to_diagnostic_unknown @ d9be6853b
// Replaces every unresolved inference node with the user-denotable top type
// while preserving the surrounding shape.
function infer_to_diagnostic_unknown(pool: root.types.InferPool, ty: int) -> int throws never {
    if (!pool.has_infer(ty)) {
        return ty;
    }
    if (pool.kinds[ty] is root.types.TyInferVar) {
        return pool.add(root.types.TyUnknown {});
    }
    pool.add(
        root.types.map_children(pool.kinds[ty], (child) -> {
            infer_to_diagnostic_unknown(pool, child)
        }),
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::widen_fresh_literal @ d9be6853b
// A fresh literal widens to its base primitive at binding sites;
// everything else passes through. Top-level only.
function widen_fresh_literal(pool: root.types.InferPool, ty: int) -> int throws never {
    if let l: root.types.TyLiteral = pool.kinds[ty] {
        if (l.freshness == root.types.Freshness.Fresh) {
            return pool.add(literal_base(l.value));
        }
    }
    ty
}
