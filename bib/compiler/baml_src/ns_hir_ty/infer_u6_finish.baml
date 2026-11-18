// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 6, finish: the finish-time diagnostic collectors (unsolved holes,
// unresolved origins, the writeback backstop), the taint passes, the
// conflicting-class quiescence tier, and `finish` itself, which turns one
// inference run into its `InferenceResult`.
//
// Restructured (BAML forces it, or Rust's 1.6k-line `finish` does):
// - `finish` runs its phases as functions, in Rust's order: `finish_fixpoint`
//   (the fulfillment loop), `finish_quiescence` (quiescence reports, taints
//   and the "cannot infer" collectors), `finish_throws` (the owner's effect
//   and contract judgments), `finish_tables` (take the result, finalize the
//   type tables and mismatches), `finish_diagnostics` (the user-facing
//   diagnostics) and `finish_writeback`; then `materialize_result`.
// - `finish_diagnostics`' `PendingDiag` loop dispatches each pending to a
//   `pending_diag_to_tir_<family>` function returning the diagnostic it
//   pushes (null for Rust's `continue`), threading the loop-carried
//   `reported_units`. Rust's common tail (severity and primary for an
//   `(error, expr)` arm) is `pending_diag_at_expr`.
// - Rust's `FxHashSet<(ExprId, DeclName)>` is `map<int, DeclName[]>` (tuples
//   are not map keys); `std::mem::take` is a read followed by a reset.
// - `crate::throw_facts::flatten_declared_ty_to_facts` (throw_facts.rs, not
//   ported yet) is ported here, the one item of that file `finish` reaches.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::take_unresolved_infer_diagnostics @ d9be6853b
// Reports every registered variable still unsolved at finalize, once per
// class. A class the `Error` sentinel related to is a cascade of that
// error's own report and is skipped. Origins are judged by rank, a lambda
// parameter first and a type parameter last, so a class with several
// origins gets the report that names what the user can annotate.
function take_unresolved_infer_diagnostics(
    ctx: InferenceContext,
) -> (DiagnosticLocation, TirTypeError)[] throws never {
    let taken = ctx.journals.infer_var_origins;
    ctx.journals.infer_var_origins = {};
    let origins = taken.keys().map((var) -> {
        (var, taken[var])
    });
    let diagnostics: (DiagnosticLocation, TirTypeError)[] = [];
    for (let entry in origins) {
        if let origin: InferVarOriginLambdaParameter = entry.1 {
            let root_var = unsolved_undiagnosed_root(ctx, entry.0);
            if (root_var == null) {
                continue;
            }
            ctx.diagnosed_infer_vars[root_var] = true;
            diagnostics.push(
                (
                    DiagnosticLocationLambdaParameter {
                        expr: origin.lambda,
                        parameter: origin.parameter_index,
                    },
                    TirTypeErrorCannotInferLambdaParamType { param_name: origin.name },
                ),
            );
        }
    }
    for (let entry in origins) {
        if let origin: InferVarOriginTypeMustBeKnown = entry.1 {
            let root_var = unsolved_undiagnosed_root(ctx, entry.0);
            if (root_var == null) {
                continue;
            }
            let full_type = ctx.table.resolve_completely(origin.containing_type);
            if (ctx.table.pool.has_error(full_type)) {
                continue;
            }
            ctx.diagnosed_infer_vars[root_var] = true;
            diagnostics.push(
                (
                    origin.location,
                    TirTypeErrorTypeMustBeKnown { full_type: plain_finalized(ctx, full_type) },
                ),
            );
        }
    }
    // One site may instantiate a parameter more than once, so the slot is
    // determined iff ANY instantiation of that parameter at the site solved,
    // and one report covers the `(site, parameter)` pair. The key is the
    // parameter's identity, never its spelling.
    let by_site: (int, root.types.ParamTy, int[]?)[] = [];
    for (let entry in origins) {
        if let origin: InferVarOriginTypeParameter = entry.1 {
            let root_var = unsolved_undiagnosed_root(ctx, entry.0);
            let seen = by_site.find_index((site) -> {
                site.0 == origin.site && site.1 == origin.param
            });
            if (seen != null) {
                let roots = by_site[seen].2;
                if (root_var == null) {
                    by_site[seen] = (origin.site, origin.param, null);
                } else if (roots != null) {
                    roots.push(root_var);
                }
            } else {
                by_site.push(
                    (
                        origin.site,
                        origin.param,
                        if (root_var != null) {
                            [root_var]
                        } else {
                            null
                        },
                    ),
                );
            }
        }
    }
    for (let entry in by_site) {
        let (let site, let param, let roots) = entry;
        let name = param.name;
        if (roots == null) {
            continue;
        }
        let first = roots.at(0);
        let conflict = if (first != null) {
            conflicting_lower_bounds(ctx, first)
        } else {
            null
        };
        if (
            roots.every((root_var) -> {
                ctx.diagnosed_infer_vars.has(root_var)
            })
        ) {
            continue;
        }
        for (let root_var in roots) {
            ctx.diagnosed_infer_vars[root_var] = true;
        }
        let error: TirTypeError = if (conflict != null) {
            TirTypeErrorConflictingTypeArguments {
                name: name,
                first: plain_finalized(ctx, conflict.0),
                second: plain_finalized(ctx, conflict.1),
            }
        } else {
            TirTypeErrorCannotInferTypeParameter { name: name }
        };
        diagnostics.push((DiagnosticLocationExpr { value: site }, error));
    }
    diagnostics
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::taint_classes_owned_by_mismatches @ d9be6853b
// Every type mismatch that will report owns the open classes of its two
// sides: a slot whose only evidence was the failed relation is that
// report's cascade, not a "cannot infer" of its own. Judged on the same
// predicate the finalize filter applies; a mismatch the filter drops owns
// nothing.
function taint_classes_owned_by_mismatches(ctx: InferenceContext) -> void throws never {
    let pool = ctx.table.pool;
    let direct = ctx.result.type_mismatches.values();
    let provisional = ctx.journals.provisional_checks.map((check) -> {
        (check.1, check.2)
    });
    for (let pair in direct) {
        let (let expected, let actual) = pair;
        let finalized_expected = finalize_ty(ctx, expected).ty;
        let finalized_actual = finalize_ty(ctx, actual).ty;
        if (!direct_mismatch_holds(ctx, finalized_expected, finalized_actual)) {
            continue;
        }
        ctx.table.taint_vars_in(expected);
        ctx.table.taint_vars_in(actual);
    }
    for (let pair in provisional) {
        let (let expected, let actual) = pair;
        let finalized_expected = finalize_ty(ctx, expected).ty;
        let finalized_actual = finalize_ty(ctx, actual).ty;
        if (
            pool.has_error(finalized_expected)
                || pool.has_error(finalized_actual)
                || cached_subtype(ctx, finalized_actual, finalized_expected)
        ) {
            continue;
        }
        ctx.table.taint_vars_in(expected);
        ctx.table.taint_vars_in(actual);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::direct_mismatch_holds @ d9be6853b
// Whether a recorded mismatch, judged on its finalized sides, is a report of
// its own: neither side IS the error sentinel (that is a cascade), and the
// relation fails in the finalized world.
function direct_mismatch_holds(
    ctx: InferenceContext,
    expected: int,
    actual: int,
) -> bool throws never {
    let pool = ctx.table.pool;
    !(pool.kinds[expected] is root.types.TyError)
        && !(pool.kinds[actual] is root.types.TyError)
        && !cached_subtype(ctx, actual, expected)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::taint_classes_owned_by_value_reports @ d9be6853b
// A generic function VALUE whose own arguments stay open is reported as the
// unspecialized value, which reports exactly when its evidence still names
// an open class: it owns those classes.
function taint_classes_owned_by_value_reports(ctx: InferenceContext) -> void throws never {
    let evidence: int[] = [];
    for (let pending in ctx.journals.pending_diags) {
        if let value: PendingDiagGenericFunctionValueNotSpecialized = pending {
            root.base.extend(evidence, value.inference_evidence);
        }
    }
    for (let ty in evidence) {
        ctx.table.taint_vars_in(ty);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::solve_conflicting_classes_from_their_demand @ d9be6853b
// The quiescence fallback for a value class whose evidence CONFLICTS (ground
// lower bounds with no common candidate) but whose demands admit every one
// of them: the minimum upper is the solution the expectation pins (`let r:
// int | string = pick(1, "s")`). Returns whether any class was decided. In
// variable order.
function solve_conflicting_classes_from_their_demand(ctx: InferenceContext) -> bool throws never {
    let classes = ctx.table.unsolved_bounded_vars().sort_by_key((entry) -> {
        entry.0
    });
    let progressed = false;
    for (let entry in classes) {
        if (solve_conflicting_class_from_its_demand(ctx, entry.0, entry.1)) {
            progressed = true;
        }
    }
    progressed
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::effect_default_keep_open @ d9be6853b
// The open classes the effect default must leave open: those holding a slot
// the program must determine (a value-position type parameter). Invariance
// can tie such a slot to an effect class; with no evidence it reports rather
// than defaults.
function effect_default_keep_open(ctx: InferenceContext) -> int[] throws never {
    let value_slots: int[] = [];
    for (let var in ctx.journals.infer_var_origins.keys()) {
        match (ctx.journals.infer_var_origins[var]) {
            let origin: InferVarOriginTypeParameter if !origin.effect => {
                value_slots.push(var);
            },
            InferVarOriginTypeParameter
                | InferVarOriginTypeMustBeKnown
                | InferVarOriginLambdaParameter =>
            {},
        }
    }
    let roots: int[] = [];
    for (let var in value_slots) {
        let root_var = ctx.table.unsolved_root_var(var);
        if (root_var != null && !roots.includes(root_var)) {
            roots.push(root_var);
        }
    }
    roots
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::solve_conflicting_class_from_its_demand @ d9be6853b
// One class of `solve_conflicting_classes_from_their_demand`; whether it was
// solved.
function solve_conflicting_class_from_its_demand(
    ctx: InferenceContext,
    var: int,
    bounds: root.hir_ty.infer.VarBounds,
) -> bool throws never {
    if (
        ctx.table.is_solved(var)
            || ctx.table.unsolved_policy(var) != root.hir_ty.infer.VarPolicy.Value
    ) {
        return false;
    }
    let pool = ctx.table.pool;
    let ground = (bounds: root.hir_ty.infer.Bound[]) -> int[]? {
        let tys: int[] = [];
        for (let bound in bounds) {
            let ty = ctx.table.resolve_completely(bound.ty);
            if (pool.has_infer(ty) || pool.has_error(ty)) {
                return null;
            }
            tys.push(ty);
        }
        tys
    };
    let lowers = ground(bounds.lowers);
    if (lowers == null) {
        return false;
    }
    let ground_uppers = ground(bounds.uppers);
    if (ground_uppers == null) {
        return false;
    }
    let uppers = ground_uppers.filter((upper) -> {
        !(pool.kinds[upper] is root.types.TyUnknown)
    });
    if (lowers.length() < 2 || uppers.length() == 0 || lowers_join(ctx, lowers, []) != null) {
        return false;
    }
    let found = uppers.find((candidate) -> {
        uppers.every((upper) -> {
            cached_subtype(ctx, candidate, upper)
        })
    });
    if (found == null) {
        return false;
    }
    let minimum: int = found;
    if (
        !lowers.every((lower) -> {
            cached_subtype(ctx, lower, minimum)
        })
    ) {
        return false;
    }
    ctx.table.solve(var, minimum);
    true
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::conflicting_lower_bounds @ d9be6853b
// Two ground lower bounds of `root_id`'s class with no common candidate, when
// its evidence conflicts rather than being absent.
function conflicting_lower_bounds(ctx: InferenceContext, root_id: int) -> (int, int)? throws never {
    let pool = ctx.table.pool;
    let bounds = ctx.table.var_bounds(root_id);
    let lowers: int[] = [];
    for (let bound in bounds.lowers) {
        let resolved = ctx.table.resolve_completely(bound.ty);
        if (pool.has_infer(resolved) || pool.has_error(resolved)) {
            continue;
        }
        let ty = widen_fresh(ctx, resolved);
        if (!lowers.includes(ty)) {
            lowers.push(ty);
        }
    }
    if (lowers.length() < 2 || lowers_join(ctx, lowers, []) != null) {
        return null;
    }
    (lowers[0], lowers[1])
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::take_unsolved_hole_diagnostics @ d9be6853b
// A `_` hole that never solved reports E0147 at the hole, judged before
// every other "cannot infer" report so they see its classes as owned. One
// WRITTEN hole may instantiate several times, so instantiations group by
// their source anchor: the hole is solved iff ANY of its instantiations
// solved, and one report covers the anchor. Every class an instantiation
// leaves open is owned by its anchor's verdict.
function take_unsolved_hole_diagnostics(
    ctx: InferenceContext,
) -> (DiagnosticLocation, TirTypeError)[] throws never {
    let pool = ctx.table.pool;
    let by_anchor: (HoleAnchor, bool)[] = [];
    let holes = ctx.hole_vars;
    ctx.hole_vars = [];
    for (let hole in holes) {
        let (let var, let at) = hole;
        let resolved = ctx.table.resolve_completely(pool.add(root.types.TyInferVar { var: var }));
        let open_roots = ctx.table.open_roots_in(resolved);
        let solved = open_roots.length() == 0;
        for (let root_var in open_roots) {
            ctx.diagnosed_infer_vars[root_var] = true;
        }
        let seen = by_anchor.find_index((entry) -> {
            entry.0 == at
        });
        if (seen != null) {
            by_anchor[seen] = (at, by_anchor[seen].1 || solved);
        } else {
            by_anchor.push((at, solved));
        }
    }
    let diagnostics: (DiagnosticLocation, TirTypeError)[] = [];
    for (let entry in by_anchor) {
        let (let at, let any_solved) = entry;
        if (any_solved) {
            continue;
        }
        let location: DiagnosticLocation = match (at) {
            let anchor: HoleAnchorTypeRef => DiagnosticLocationBodyTypeRef { value: anchor.value },
        };
        diagnostics.push((location, TirTypeErrorCannotInferType {}));
    }
    diagnostics
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::take_writeback_backstop_diagnostics @ d9be6853b
// rustc's writeback E0282, the backstop behind the registered origins: a
// class no origin spoke for that is still open where the body's types are
// recorded owes "type annotations needed" at the first expression (or
// pattern) whose type carries it. Nothing may reach `erase_infer`
// undiagnosed.
function take_writeback_backstop_diagnostics(
    ctx: InferenceContext,
) -> (DiagnosticLocation, TirTypeError)[] throws never {
    let pool = ctx.table.pool;
    let sites: (DiagnosticLocation, int)[] = [];
    for (let recorded in ctx.result.recorded_types()) {
        let (let site, let ty) = recorded;
        if (!pool.has_infer(ty)) {
            continue;
        }
        // The owner's thrown type is assembled after this, from the
        // contributions the recorded expressions carry.
        let location = recorded_site_location(site);
        if (location != null) {
            sites.push((location, ty));
        }
    }
    let diagnostics: (DiagnosticLocation, TirTypeError)[] = [];
    for (let entry in sites) {
        let (let location, let ty) = entry;
        let resolved = ctx.table.resolve_completely(ty);
        let owed = false;
        for (let open_root in ctx.table.open_roots_in(resolved)) {
            let root_var = unsolved_undiagnosed_root(ctx, open_root);
            if (root_var != null) {
                ctx.diagnosed_infer_vars[root_var] = true;
                owed = true;
            }
        }
        if (owed) {
            diagnostics.push(
                (
                    location,
                    TirTypeErrorTypeMustBeKnown { full_type: plain_finalized(ctx, resolved) },
                ),
            );
        }
    }
    diagnostics
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::open_classes_owned @ d9be6853b
// Whether `ty` names open classes and another report owns every one of them
// (they are tainted): what it leaves undetermined is that report's cascade.
function open_classes_owned(ctx: InferenceContext, ty: int) -> bool throws never {
    let roots = ctx.table.open_roots_in(ty);
    roots.length() > 0
        && roots.every((root_var) -> {
            ctx.table.is_tainted(root_var)
        })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::unsolved_undiagnosed_root @ d9be6853b
// The class `var` belongs to when it still owes a report: unsolved, not
// tainted by the `Error` sentinel, and not yet reported on.
function unsolved_undiagnosed_root(ctx: InferenceContext, var: int) -> int? throws never {
    let root_var = ctx.table.unsolved_root_var(var);
    if (root_var == null) {
        return null;
    }
    if (ctx.table.is_tainted(root_var) || ctx.diagnosed_infer_vars.has(root_var)) {
        return null;
    }
    root_var
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// Turns this inference run into its result: the fulfillment fixpoint, the
// quiescence reports, the owner's effect, the finalized tables, the
// user-facing diagnostics, the writeback, and the plain materialization.
// Restructured: Rust's one body is the `finish_<phase>` functions, called in
// its order.
function finish(
    ctx: InferenceContext,
    body: root.ast.ExprBody?,
) -> InferenceResult<root.types.Ty> throws never {
    finish_fixpoint(ctx, body);
    let unresolved_infer_diagnostics = finish_quiescence(ctx);
    let throws_ = finish_throws(ctx);
    let result = finish_tables(ctx, throws_);
    finish_diagnostics(ctx, body, result, unresolved_infer_diagnostics);
    finish_writeback(ctx, result);
    materialize_result(ctx, result)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s fulfillment fixpoint: solve what FULL bounds determine, attempt
// obligations, re-drive the deferred residue, repeat while any side
// progresses. Only at QUIESCENCE does the ground-subset tier commit classes
// from partial bounds, and then the quiescence fallbacks run, each a tier
// the loop re-runs fulfillment after.
function finish_fixpoint(ctx: InferenceContext, body: root.ast.ExprBody?) -> void throws never {
    let pool = ctx.table.pool;
    while (true) {
        let solved = resolve_bounded_vars(ctx, SolveTier.Ground);
        let replayed = replay_solved_class_bounds(ctx);
        let obligations = root.hir_ty.infer.discharge_obligations_once(ctx);
        let subs = drain_deferred_subs(ctx);
        if (solved || replayed || obligations || subs) {
            continue;
        }
        if (resolve_bounded_vars(ctx, SolveTier.GroundSubset)) {
            continue;
        }
        // Preserve the historical string default only when an empty map's
        // key has no evidence from any use.
        let defaulted = false;
        if (body != null) {
            for (let expr = 0; expr < body.exprs.length(); expr += 1) {
                let node = body.exprs[expr];
                if (!(node is root.ast.ExprMap) || node.entries.length() != 0) {
                    continue;
                }
                let recorded = ctx.result.type_of_expr.get(expr);
                if (recorded == null) {
                    continue;
                }
                let ty = ctx.table.resolve_completely(recorded);
                if let map_ty: root.types.InferTyMap = pool.kinds[ty] {
                    if let key: root.types.TyInferVar = pool.kinds[map_ty.key] {
                        let bounds = ctx.table.var_bounds(key.var);
                        if (bounds.lowers.length() == 0 && bounds.uppers.length() == 0) {
                            let unified = true;
                            ctx.table.unify(map_ty.key, pool.add(root.types.TyString {})) catch (e) {
                                root.hir_ty.infer.UnifyError => {
                                    unified = false;
                                },
                            };
                            defaulted = defaulted || unified;
                        }
                    }
                }
            }
        }
        if (defaulted) {
            continue;
        }
        // Quiescence fallbacks: first the expected-type decision for a value
        // class with conflicting evidence; then BAML's only defaulting rule,
        // an unconstrained EFFECT is `never` (a value variable erases to
        // Error instead).
        if (solve_conflicting_classes_from_their_demand(ctx)) {
            continue;
        }
        let keep_open = effect_default_keep_open(ctx);
        if (ctx.table.default_unsolved_effects_to_never(keep_open)) {
            continue;
        }
        break;
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish` at quiescence: contradictory bounds, the skolem judgment of the
// residue still open on both sides, the stalled obligations, the escapes
// with no anchor, the taint passes, and the "cannot infer" collectors
// (holes first, then origins, then the writeback backstop), returned for
// the diagnostics phase.
function finish_quiescence(
    ctx: InferenceContext,
) -> (DiagnosticLocation, TirTypeError)[] throws never {
    let pool = ctx.table.pool;
    report_contradictory_bounds(ctx);
    // A residue pair still open on BOTH sides can never be decided by more
    // solving. Skolemize the unsolved vars and judge: a pair no substitution
    // could satisfy is a definite mismatch, reported at the expression that
    // deposited it. Projection pairs and anchorless flushes drop.
    let deferred = ctx.journals.deferred_subs;
    ctx.journals.deferred_subs = [];
    for (let entry in deferred) {
        let (let raw_actual, let raw_expected, let anchor) = entry;
        if (anchor == null) {
            continue;
        }
        let actual = ctx.table.resolve_completely(raw_actual);
        let expected = ctx.table.resolve_completely(raw_expected);
        if (
            pool.has_projection(actual)
                || pool.has_projection(expected)
                || pool.has_error(actual)
                || pool.has_error(expected)
        ) {
            continue;
        }
        let judged_actual = skolemize_infer(pool, actual);
        let judged_expected = skolemize_infer(pool, expected);
        if (!cached_subtype(ctx, judged_actual, judged_expected)) {
            if (!ctx.result.type_mismatches.has(anchor)) {
                ctx.result.type_mismatches[anchor] = (expected, actual);
            }
        }
    }
    root.hir_ty.infer.settle_stalled_obligations(ctx);
    // An escape refused on a road with no anchor after its block had closed
    // has no block tail left to report at; the body is the last enclosing
    // scope.
    let body_root = ctx.body_root;
    if (body_root != null) {
        let escapes = ctx.journals.anchorless_escapes;
        ctx.journals.anchorless_escapes = [];
        for (let escape in escapes) {
            report_scoped_type_escape(ctx, body_root, escape.0, escape.1, ScopedTypeEscapeKindInferred {});
        }
    }
    taint_classes_owned_by_mismatches(ctx);
    taint_classes_owned_by_value_reports(ctx);
    let unresolved_infer_diagnostics = take_unsolved_hole_diagnostics(ctx);
    root.base.extend(unresolved_infer_diagnostics, take_unresolved_infer_diagnostics(ctx));
    root.base.extend(unresolved_infer_diagnostics, take_writeback_backstop_diagnostics(ctx));
    unresolved_infer_diagnostics
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s owner effect: a closed clause IS the surface, verbatim (the
// written member order is render fidelity); an open or omitted one is the
// inferred set, an open clause's named part joining the union. Then every
// closed contract's coverage is judged.
function finish_throws(ctx: InferenceContext) -> int throws never {
    let pool = ctx.table.pool;
    let owner_channel = ctx.throws_channels[0];
    let throws_ = match (owner_channel.clause) {
        let closed: ThrowsClauseClosed => closed.value,
        let clause: ThrowsClauseInferred | ThrowsClauseOpen => {
            let declared: int? = match (clause) {
                let open: ThrowsClauseOpen => open.named,
                ThrowsClauseInferred => null,
            };
            // Every block has closed: a contribution still typed by a scoped
            // binding would be published as the owner's surface.
            let contributions = drop_escaping_effects(ctx, owner_channel.contributions.concat([]), declared);
            // A contribution typed by the sentinel stays in the set: the
            // body's throw set is not determined, and `never` would claim it
            // throws nothing.
            let resolved = contributions.map((contribution) -> {
                finalize_ty(ctx, contribution.1).ty
            });
            if (declared != null) {
                resolved.push(declared);
            }
            if (resolved.length() == 0) {
                pool.add(root.types.TyNever {})
            } else {
                union_of(ctx, resolved)
            }
        },
    };
    let body_root = ctx.body_root;
    if let closed: ThrowsClauseClosed = ctx.throws_channels[0].clause {
        if (body_root != null) {
            let contributions = ctx.throws_channels[0].contributions;
            ctx.throws_channels[0].contributions = [];
            ctx.throws_contracts.push(
                ThrowsContract {
                    declared: closed.value,
                    contributions: contributions,
                    at: body_root,
                },
            );
        }
    }
    let contracts = ctx.throws_contracts;
    ctx.throws_contracts = [];
    for (let contract in contracts) {
        judge_throws_contract_coverage(ctx, contract);
    }
    throws_
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s tables: the working result is taken, takes the owner's effect,
// and has its expression and pattern types finalized; deferred truthiness
// decides on the final types; provisional checks re-judge (first writer per
// expression wins); the mismatch table is finalized.
function finish_tables(ctx: InferenceContext, throws_: int) -> InferenceResult<int> throws never {
    let pool = ctx.table.pool;
    let result = ctx.result;
    ctx.result = InferenceResult.empty(pool.add(root.types.TyNever {}));
    result.throws_ = throws_;
    for (let expr in result.type_of_expr.keys()) {
        result.type_of_expr[expr] = finalize_ty(ctx, result.type_of_expr[expr]).ty;
    }
    for (let pat in result.type_of_pat.keys()) {
        result.type_of_pat[pat] = finalize_ty(ctx, result.type_of_pat[pat]).ty;
    }
    // Truthiness decisions deferred past the fixpoint: a condition still
    // carrying an inference variable at check time decides here, on its
    // FINAL type.
    root.hir_ty.infer.decide_deferred_conditions(ctx, result);
    // Provisional checks re-judge now that their expectations solved: a
    // definite failure joins the mismatch table (a direct mismatch is the
    // better message).
    let provisional = ctx.journals.provisional_checks;
    ctx.journals.provisional_checks = [];
    for (let check in provisional) {
        let (let expr, let raw_expected, let raw_actual) = check;
        let expected = finalize_ty(ctx, raw_expected).ty;
        let actual = finalize_ty(ctx, raw_actual).ty;
        if (
            pool.has_error(expected)
                || pool.has_error(actual)
                || cached_subtype(ctx, actual, expected)
        ) {
            continue;
        }
        if (!result.type_mismatches.has(expr)) {
            result.type_mismatches[expr] = (expected, actual);
        }
    }
    for (let expr in result.type_mismatches.keys()) {
        let (let expected, let actual) = result.type_mismatches[expr];
        result.type_mismatches[expr] = (finalize_ty(ctx, expected).ty, finalize_ty(ctx, actual).ty);
    }
    result
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s user-facing diagnostics: the finalized mismatch table plus the
// pendings, in the shared vocabulary with PLAIN payload types. Sorted by
// anchor (stable; the check layer re-sorts globally by span), and identical
// neighbours collapse to one (the fixpoint may re-attempt a failing
// obligation once per round).
function finish_diagnostics(
    ctx: InferenceContext,
    body: root.ast.ExprBody?,
    result: InferenceResult<int>,
    unresolved_infer_diagnostics: (DiagnosticLocation, TirTypeError)[],
) -> void throws never {
    let pool = ctx.table.pool;
    let diags: TirDiagnostic[] = [];
    if (body != null) {
        for (let expr = 0; expr < body.exprs.length(); expr += 1) {
            if (!(body.exprs[expr] is root.ast.ExprMap)) {
                continue;
            }
            let ty = result.type_of_expr.get(expr);
            if (ty == null) {
                continue;
            }
            if let map_ty: root.types.InferTyMap = pool.kinds[ty] {
                let key = plain_finalized(ctx, map_ty.key);
                if (!root.hir_ty.interfaces.map_key_is_hashable(ctx.db, ctx.facts, key)) {
                    diags.push(
                        TirDiagnostic {
                            error: TirTypeErrorInvalidMapKeyType { key: key },
                            severity: DiagnosticSeverity.Error,
                            primary: DiagnosticLocationExpr { value: expr },
                            related: [],
                        },
                    );
                }
            }
        }
    }
    for (let entry in unresolved_infer_diagnostics) {
        diags.push(
            TirDiagnostic {
                error: entry.1,
                severity: DiagnosticSeverity.Error,
                primary: entry.0,
                related: [],
            },
        );
    }
    // Expressions with a nominal does-not-implement verdict, keyed by the
    // interface that failed: a mismatch there AGAINST THAT INTERFACE is the
    // same fault restated through subtyping, and the verdict is the precise
    // report. A mismatch against a DIFFERENT interface at the same span is a
    // second fault, and still reports.
    let not_implemented_at: map<int, root.types.DeclName[]> = {};
    for (let pending in ctx.journals.pending_diags) {
        if let verdict: PendingDiagDoesNotImplement = pending {
            // Every push site builds this from an interface existential.
            if let iface: root.types.InferTyInterface = pool.kinds[verdict.interface_] {
                not_implemented_at.get_or_insert(verdict.expr, []).push(iface.name);
            }
        }
    }
    for (let expr in result.type_mismatches.keys()) {
        let (let expected, let actual) = result.type_mismatches[expr];
        if (!direct_mismatch_holds(ctx, expected, actual)) {
            continue;
        }
        let expected_kind = pool.kinds[expected];
        if (expected_kind is root.types.InferTyInterface) {
            let failed = not_implemented_at.get(expr);
            if (failed != null && failed.includes(expected_kind.name)) {
                continue;
            }
        }
        // A value where only the unit type is admitted reports at the
        // expression that produces it, with its remedy.
        let unit_position = ctx.unit_positions.get(expr);
        if (unit_position != null && cached_equivalent(ctx, expected, pool.add(root.types.TyNull {}))) {
            diags.push(
                TirDiagnostic {
                    error: TirTypeErrorUnitExpected {
                        context: unit_position.1,
                        found: materialize_ty(ctx, actual),
                    },
                    severity: DiagnosticSeverity.Error,
                    primary: DiagnosticLocationExpr { value: unit_position.0 },
                    related: [],
                },
            );
            continue;
        }
        // The for-desugar's iterability failure reads as its own message, not
        // a raw interface mismatch. A value that ALMOST implements an
        // expected interface through a blanket `implements` rule names the
        // unsatisfied bound.
        let error: TirTypeError = match (expected_kind) {
            let iface: root.types.InferTyInterface
                if infer_ctx_lang(ctx).is_(root.base.LangPackage.Baml, iface.name.pkg)
                && iface.name.namespace.length() == 1
                && iface.name.namespace[0] == "iter"
                && iface.name.name == "Iterable" => {
                TirTypeErrorNotIterable { ty: materialize_ty(ctx, actual) }
            },
            root.types.InferTyInterface => {
                let bound = first_failing_blanket_bound(ctx, actual, expected);
                if (bound != null) {
                    TirTypeErrorBlanketBoundNotSatisfied {
                        value_type: materialize_ty(ctx, actual),
                        bound: bound,
                    }
                } else {
                    TirTypeErrorTypeMismatch {
                        expected: materialize_ty(ctx, expected),
                        got: materialize_ty(ctx, actual),
                    }
                }
            },
            _ => {
                TirTypeErrorTypeMismatch {
                    expected: materialize_ty(ctx, expected),
                    got: materialize_ty(ctx, actual),
                }
            },
        };
        diags.push(
            TirDiagnostic {
                error: error,
                severity: DiagnosticSeverity.Error,
                primary: DiagnosticLocationExpr { value: expr },
                related: [],
            },
        );
    }
    // One implicit unit can fail both its join and its expectation; it
    // reports once.
    let reported_units: DiagnosticLocation[] = [];
    let pendings = ctx.journals.pending_diags;
    ctx.journals.pending_diags = [];
    for (let pending in pendings) {
        let diag = pending_diag_to_tir(ctx, body, result, pending, reported_units);
        if (diag != null) {
            diags.push(diag);
        }
    }
    if (body != null) {
        root.hir_ty.infer.add_diagnostics(body, result, ctx.loop_verdicts, diags);
    }
    // Stable, so diagnostics at one anchor keep their push order.
    let sort_key = (diag: TirDiagnostic) -> (int, int) {
        match (diag.primary) {
            let at: DiagnosticLocationExpr => (0, at.value),
            let at: DiagnosticLocationExprMember => (0, at.value),
            let at: DiagnosticLocationExprSegment => (0, at.expr),
            let at: DiagnosticLocationLambdaParameter => (0, at.expr),
            let at: DiagnosticLocationObjectFieldName => (0, at.value),
            let at: DiagnosticLocationStmt => (1, at.value),
            let at: DiagnosticLocationTypeAnnot => (2, at.value),
            let at: DiagnosticLocationPat => (4, at.value),
            let at: DiagnosticLocationBodyTypeRef => (5, ctx.type_refs.raw_id(at.value)),
            let at: DiagnosticLocationSpan => (3, at.value.start),
        }
    };
    diags.sort_by((a, b) -> {
        let a_key = sort_key(a);
        let b_key = sort_key(b);
        let by_kind = a_key.0.cmp(b_key.0);
        if (by_kind != baml.ops.Ordering.Equal) {
            by_kind
        } else {
            a_key.1.cmp(b_key.1)
        }
    });
    // Adjacent duplicates only (Rust's `Vec::dedup`).
    let deduped: TirDiagnostic[] = [];
    for (let diag in diags) {
        if (deduped.length() == 0 || deduped[deduped.length() - 1] != diag) {
            deduped.push(diag);
        }
    }
    result.diagnostics = deduped;
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s writeback pass over every recorded table (rustc's
// `resolve_type_vars_in_body`): member resolutions, path ladders, call plans
// (emission slots keep their written union order) and adjustments.
function finish_writeback(
    ctx: InferenceContext,
    result: InferenceResult<int>,
) -> void throws never {
    for (let resolution in result.member_resolutions.values()) {
        finalize_member_resolution(ctx, resolution);
    }
    for (let path in result.path_resolutions.values()) {
        for (let segment in path.segments) {
            segment.ty = finalize_ty(ctx, segment.ty).ty;
            let resolution = segment.resolution;
            if (resolution != null) {
                finalize_member_resolution(ctx, resolution);
            }
        }
    }
    for (let plan in result.call_plans.values()) {
        plan.type_args
            = plan.type_args.map((ty) -> {
                finalize_ty(ctx, ty).ty
            });
        for (let slot in plan.slots) {
            slot.ty = finalize_ty(ctx, slot.ty).ty;
            slot.emission_ty = finalize_emission_ty(ctx, slot.emission_ty).ty;
        }
    }
    for (let adjustments in result.expr_adjustments.values()) {
        for (let adjustment in adjustments) {
            adjustment.target = finalize_ty(ctx, adjustment.target).ty;
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// The common tail of `finish`'s pending loop: an `(error, expr)` arm reports
// at the expression (its member name for a tuple index), as an error unless
// it is a warning-flagged unreachable arm.
function pending_diag_at_expr(
    error: TirTypeError,
    expr: int,
    related: RelatedNote[] = [],
    unreachable_is_warning: bool = false,
) -> TirDiagnostic throws never {
    let severity = if (error is TirTypeErrorUnreachableArm && unreachable_is_warning) {
        DiagnosticSeverity.Warning
    } else {
        DiagnosticSeverity.Error
    };
    let primary: DiagnosticLocation = if (error is TirTypeErrorTupleIndexOutOfRange) {
        DiagnosticLocationExprMember { value: expr }
    } else {
        DiagnosticLocationExpr { value: expr }
    };
    TirDiagnostic { error: error, severity: severity, primary: primary, related: related }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// One diagnostic pushed directly by a pending arm: an error with no related
// notes.
function pending_diag_error_at(
    error: TirTypeError,
    primary: DiagnosticLocation,
) -> TirDiagnostic throws never {
    TirDiagnostic {
        error: error,
        severity: DiagnosticSeverity.Error,
        primary: primary,
        related: [],
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// The pendings of a call or construction: arguments, constructors,
// specialization, literals.
type PendingDiagCallFamily = PendingDiagMissingNamedArg
    | PendingDiagPositionalDefaultedArg
    | PendingDiagUnresolvedCtor
    | PendingDiagConstructedTypeParameter
    | PendingDiagAliasNotConstructible
    | PendingDiagAliasTakesNoTypeArgs
    | PendingDiagFunctionFieldNeedsParens
    | PendingDiagPositionalAfterNamed
    | PendingDiagDuplicateNamedArg
    | PendingDiagNotCallable
    | PendingDiagArgCountMismatch
    | PendingDiagUnknownNamedArg
    | PendingDiagTraceUnsupportedCall
    | PendingDiagTraceOpaqueValue
    | PendingDiagWrongTypeArgArity
    | PendingDiagGenericFunctionValueNotSpecialized
    | PendingDiagComputedGenericArgumentRequiresLetType
    | PendingDiagMountedPackageCallUnsupported
    | PendingDiagCannotConstructReflectionKind
    | PendingDiagCannotConstructOpaqueClass
    | PendingDiagCannotConstructBuiltinCompanion
    | PendingDiagCallSiteBuiltinValue
    | PendingDiagUnknownObjectField
    | PendingDiagMissingRequiredObjectFields
    | PendingDiagInterfaceFieldInConstruction
    | PendingDiagTaggedTagInvalid
    | PendingDiagIntLiteralOutOfRange
    | PendingDiagInvalidRegexPattern;

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// The pendings of a name, member or path.
type PendingDiagMemberFamily = PendingDiagUnresolvedName
    | PendingDiagItemShadowsPackage
    | PendingDiagTopLevelLetCycle
    | PendingDiagUnresolvedMember
    | PendingDiagReceiverTypeMustBeKnown
    | PendingDiagAmbiguousMember
    | PendingDiagFieldRequiresProjection
    | PendingDiagSelfRestrictedMember
    | PendingDiagSelflessInstanceMember
    | PendingDiagItemProjectionSelfSlot
    | PendingDiagUnionNoCommonInterface
    | PendingDiagUnionAssociatedTypeConflict
    | PendingDiagQualifierNotInterface
    | PendingDiagUnresolvedShorthand
    | PendingDiagUnnecessaryOptionalChain
    | PendingDiagTupleElementAssign
    | PendingDiagTupleIndexOutOfRange
    | PendingDiagInvalidAssignmentTarget
    | PendingDiagAssignmentToGlobal;

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// The pendings of an interface goal or an operator.
type PendingDiagObligationFamily = PendingDiagBoundedArgNotConcrete
    | PendingDiagDoesNotImplement
    | PendingDiagAmbiguousImplementation
    | PendingDiagOperatorNotApplicable
    | PendingDiagComparisonAlwaysDisjoint
    | PendingDiagOrderingDifferentTypes
    | PendingDiagOrderingRequiresCompare;

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// The pendings of a written annotation or a block-scoped type.
type PendingDiagAnnotationFamily = PendingDiagAnnotWf
    | PendingDiagBodyAnnot
    | PendingDiagExprPositionHole
    | PendingDiagScopedTypeEscapesBlock
    | PendingDiagBoundedLetTypeRequiresElse
    | PendingDiagLetTypePendingOperand;

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// The pendings of control flow, effects, conditions and templates.
type PendingDiagControlFamily = PendingDiagReturnOutsideFunctionBody
    | PendingDiagDeferEscape
    | PendingDiagLoopControlOutsideLoop
    | PendingDiagLoopControlInLoopHeader
    | PendingDiagImplicitUnit
    | PendingDiagExtraneousThrows
    | PendingDiagImpreciseUnknownThrows
    | PendingDiagThrowsViolation
    | PendingDiagConditionAlwaysConst
    | PendingDiagInterpolatedMaybeNull
    | PendingDiagInterpolatedRoleMarker
    | PendingDiagBareOutputFormatReference;

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// The pendings of a pattern, a match or a `let`.
type PendingDiagPatternFamily = PendingDiagNonExhaustiveMatch
    | PendingDiagNonExhaustiveCatchAll
    | PendingDiagUnreachableArm
    | PendingDiagScrutineeTypeMustBeKnown
    | PendingDiagListPatternNeverMatches
    | PendingDiagUninferredPatternTypeParam
    | PendingDiagUninferredPatternAssociatedType
    | PendingDiagPatternScrutMismatch
    | PendingDiagTupleTypeTestNeverMatches
    | PendingDiagUnresolvedPatternName
    | PendingDiagRestNotBinding
    | PendingDiagOrBindingConflict
    | PendingDiagGenericDestructureNoArgs
    | PendingDiagUnknownPatternField
    | PendingDiagRefutableLet
    | PendingDiagLetElseMustDiverge;

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// One iteration of `finish`'s pending loop: the diagnostic `pending` reports,
// or null where Rust's arm `continue`s without one.
function pending_diag_to_tir(
    ctx: InferenceContext,
    body: root.ast.ExprBody?,
    result: InferenceResult<int>,
    pending: PendingDiag,
    reported_units: DiagnosticLocation[],
) -> TirDiagnostic? throws never {
    match (pending) {
        let p: PendingDiagCallFamily => pending_diag_to_tir_call(ctx, p),
        let p: PendingDiagMemberFamily => pending_diag_to_tir_member(ctx, p),
        let p: PendingDiagObligationFamily => pending_diag_to_tir_obligation(ctx, p),
        let p: PendingDiagAnnotationFamily => pending_diag_to_tir_annotation(ctx, p),
        let p: PendingDiagControlFamily => {
            pending_diag_to_tir_control(ctx, body, result, p, reported_units)
        },
        let p: PendingDiagPatternFamily => pending_diag_to_tir_pattern(ctx, p),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s pending arms for calls and construction.
function pending_diag_to_tir_call(
    ctx: InferenceContext,
    pending: PendingDiagCallFamily,
) -> TirDiagnostic? throws never {
    match (pending) {
        let p: PendingDiagMissingNamedArg => {
            pending_diag_at_expr(TirTypeErrorMissingRequiredArgument { name: p.name }, p.expr)
        },
        let p: PendingDiagPositionalDefaultedArg => {
            pending_diag_at_expr(TirTypeErrorDefaultedParamPassedPositionally { name: p.name }, p.expr)
        },
        let p: PendingDiagUnresolvedCtor => {
            pending_diag_at_expr(
                removed_reflect_spelling(p.name)
                    ?? TirTypeErrorUnresolvedType { name: p.name, suggestions: p.suggestions },
                p.expr,
            )
        },
        let p: PendingDiagConstructedTypeParameter => {
            pending_diag_at_expr(TirTypeErrorConstructedTypeParameter { name: p.name }, p.expr)
        },
        let p: PendingDiagAliasNotConstructible => {
            pending_diag_at_expr(TirTypeErrorCannotConstructAlias { name: p.name, denotes: p.denotes }, p.expr)
        },
        let p: PendingDiagAliasTakesNoTypeArgs => {
            pending_diag_at_expr(
                TirTypeErrorWrongNumberOfTypeArgs { type_name: p.name, expected: 0, got: p.got },
                p.expr,
            )
        },
        let p: PendingDiagFunctionFieldNeedsParens => {
            pending_diag_at_expr(TirTypeErrorFunctionFieldNeedsParens {}, p.expr)
        },
        let p: PendingDiagPositionalAfterNamed => {
            pending_diag_at_expr(TirTypeErrorPositionalArgumentAfterNamed {}, p.expr)
        },
        let p: PendingDiagDuplicateNamedArg => {
            pending_diag_at_expr(TirTypeErrorDuplicateNamedArgument { name: p.name }, p.expr)
        },
        let p: PendingDiagNotCallable => {
            pending_diag_at_expr(TirTypeErrorNotCallable { ty: plain_finalized(ctx, p.ty) }, p.expr)
        },
        let p: PendingDiagArgCountMismatch => {
            pending_diag_at_expr(TirTypeErrorArgumentCountMismatch { expected: p.expected, got: p.got }, p.expr)
        },
        let p: PendingDiagUnknownNamedArg => {
            pending_diag_at_expr(TirTypeErrorUnknownNamedArgument { name: p.name }, p.expr)
        },
        let p: PendingDiagTraceUnsupportedCall => {
            pending_diag_at_expr(TirTypeErrorTraceUnsupportedCall {}, p.expr)
        },
        let p: PendingDiagTraceOpaqueValue => {
            pending_diag_at_expr(TirTypeErrorTraceOpaqueValue {}, p.expr)
        },
        let p: PendingDiagWrongTypeArgArity => {
            pending_diag_at_expr(
                TirTypeErrorWrongTypeArgArity {
                    callee_name: p.callee,
                    expected: p.expected,
                    got: p.got,
                },
                p.expr,
            )
        },
        let p: PendingDiagGenericFunctionValueNotSpecialized => {
            pending_diag_to_tir_unspecialized(ctx, p)
        },
        let p: PendingDiagComputedGenericArgumentRequiresLetType => {
            pending_diag_at_expr(TirTypeErrorComputedGenericArgumentRequiresLetType { name: p.name }, p.expr)
        },
        let p: PendingDiagMountedPackageCallUnsupported => {
            pending_diag_at_expr(TirTypeErrorMountedPackageCallUnsupported { path: p.path }, p.expr)
        },
        let p: PendingDiagCannotConstructReflectionKind => {
            pending_diag_at_expr(TirTypeErrorCannotConstructReflectionKind { class_name: p.class_name }, p.expr)
        },
        let p: PendingDiagCannotConstructOpaqueClass => {
            pending_diag_at_expr(
                TirTypeErrorCannotConstructOpaqueClass { class_name: p.class_name, field: p.field },
                p.expr,
            )
        },
        let p: PendingDiagCannotConstructBuiltinCompanion => {
            pending_diag_at_expr(
                TirTypeErrorCannotConstructBuiltinCompanion {
                    class_name: p.class_name,
                    companion: p.companion,
                },
                p.expr,
            )
        },
        let p: PendingDiagCallSiteBuiltinValue => {
            pending_diag_at_expr(TirTypeErrorCallSiteBuiltinValue { reference: p.reference }, p.expr)
        },
        let p: PendingDiagUnknownObjectField => {
            let suggestions = similar_name_suggestions(p.name, p.declared);
            let error: TirTypeError = if (p.shorthand) {
                TirTypeErrorUnknownClassPropertyShorthand {
                    class_name: p.class_name,
                    name: p.name,
                    suggestions: suggestions,
                }
            } else {
                TirTypeErrorUnknownClassField {
                    class_name: p.class_name,
                    field_name: p.name,
                    suggestions: suggestions,
                }
            };
            pending_diag_error_at(error, DiagnosticLocationObjectFieldName { object: p.object, value: p.value })
        },
        let p: PendingDiagMissingRequiredObjectFields => {
            pending_diag_error_at(
                TirTypeErrorMissingRequiredClassFields {
                    class_name: p.class_name,
                    field_names: p.field_names,
                },
                DiagnosticLocationExpr { value: p.object },
            )
        },
        let p: PendingDiagInterfaceFieldInConstruction => {
            pending_diag_at_expr(
                TirTypeErrorInterfaceFieldRequiresQualifiedConstruction {
                    field_name: p.name,
                    qualified_name: p.class_field,
                },
                p.object,
            )
        },
        let p: PendingDiagTaggedTagInvalid => {
            let (let error, let note) = match (p.kind) {
                TaggedTagIssue.NotAFunction => {
                    let e: TirTypeError = TirTypeErrorTaggedTagNotAFunction { name: p.name };
                    let n: string? = null;
                    (e, n)
                },
                TaggedTagIssue.NotMarked => {
                    let e: TirTypeError = TirTypeErrorTaggedTagNotMarked { name: p.name };
                    let n: string? = "add a `//baml:tagged_string` marker comment above this function";
                    (e, n)
                },
                TaggedTagIssue.BadBodyParam => {
                    let e: TirTypeError = TirTypeErrorTaggedTagBadBodyParam { name: p.name };
                    let n: string? = "the first parameter must be `body: (...) -> baml.TaggedString`";
                    (e, n)
                },
            };
            let func = p.func;
            let related: RelatedNote[] = if (func != null && note != null) {
                [
                    RelatedNote {
                        location: RelatedLocationItem { value: root.hir.DefinitionFunction { value: func } },
                        message: note,
                    },
                ]
            } else {
                []
            };
            TirDiagnostic {
                error: error,
                severity: DiagnosticSeverity.Error,
                primary: DiagnosticLocationExpr { value: p.at },
                related: related,
            }
        },
        let p: PendingDiagIntLiteralOutOfRange => {
            pending_diag_at_expr(TirTypeErrorIntegerLiteralOutOfRange { value: p.value }, p.expr)
        },
        let p: PendingDiagInvalidRegexPattern => {
            pending_diag_at_expr(
                TirTypeErrorInvalidRegexPattern {
                    kind: p.kind,
                    message: p.message,
                    offset: p.offset,
                },
                p.expr,
            )
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s `GenericFunctionValueNotSpecialized` arm: reported when
// unconditional or when an inference argument stayed unresolved, with a
// specialization example (solved slots kept, `int` for the rest) and an
// annotation example only when it is insertable source.
function pending_diag_to_tir_unspecialized(
    ctx: InferenceContext,
    p: PendingDiagGenericFunctionValueNotSpecialized,
) -> TirDiagnostic? throws never {
    let pool = ctx.table.pool;
    let has_unresolved_user_arg = p.inference_evidence.some((arg) -> {
        pool.has_error(finalize_ty(ctx, arg).ty)
    });
    if (!p.unconditional && !has_unresolved_user_arg) {
        return null;
    }
    let vp = infer_ctx_viewpoint(ctx);
    let specialization_example: string? = if (p.specialization_example_is_safe && p.specialization_syntax_available) {
        let args: string[] = [];
        let specialization_args = p.specialization_args;
        if (specialization_args != null) {
            for (let arg in specialization_args) {
                let finalized = finalize_ty(ctx, arg);
                args.push(
                    ty_spell(rendered_plain(pool, diagnostic_example_ty(pool, finalized.ty)), vp),
                );
            }
        } else {
            for (let index = 0; index < p.generic_params.length(); index += 1) {
                args.push("int");
            }
        }
        args.join(", ")
    } else {
        null
    };
    // Insertable source: an example naming a package this package cannot
    // spell is no example.
    let annotation_ty = p.annotation_ty;
    let annotation_example: string? = if (annotation_ty != null) {
        let finalized = finalize_ty(ctx, annotation_ty);
        vp.source_text(rendered_plain(pool, diagnostic_example_ty(pool, finalized.ty))) catch (e) {
            Unspellable => null,
        }
    } else {
        null
    };
    pending_diag_at_expr(
        TirTypeErrorGenericFunctionValueNotSpecialized {
            name: p.name,
            reference: p.reference,
            had_expected_type: p.had_expected_type,
            generic_params: p.generic_params,
            binding_name: p.binding_name,
            function_shape: p.function_shape,
            annotation_example: annotation_example,
            specialization_example: specialization_example,
            specialization_syntax_available: p.specialization_syntax_available,
        },
        p.expr,
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s pending arms for names, members and paths.
function pending_diag_to_tir_member(
    ctx: InferenceContext,
    pending: PendingDiagMemberFamily,
) -> TirDiagnostic? throws never {
    match (pending) {
        let p: PendingDiagUnresolvedName => {
            pending_diag_at_expr(
                removed_reflect_spelling(p.name)
                    ?? TirTypeErrorUnresolvedName { name: p.name, suggestions: p.suggestions },
                p.expr,
            )
        },
        let p: PendingDiagItemShadowsPackage => {
            pending_diag_at_expr(TirTypeErrorItemShadowsPackage { name: p.name }, p.expr)
        },
        let p: PendingDiagTopLevelLetCycle => {
            pending_diag_at_expr(TirTypeErrorCannotInferType {}, p.expr)
        },
        let p: PendingDiagUnresolvedMember => {
            pending_diag_at_expr(
                TirTypeErrorUnresolvedMember {
                    base_type: plain_finalized(ctx, p.base),
                    member: p.member,
                },
                p.expr,
            )
        },
        let p: PendingDiagReceiverTypeMustBeKnown => {
            pending_diag_at_expr(TirTypeErrorReceiverTypeMustBeKnown { member: p.member }, p.expr)
        },
        let p: PendingDiagAmbiguousMember => {
            let receiver = ty_spell(plain_finalized(ctx, p.base), infer_ctx_viewpoint(ctx));
            let sources = p.sources.map((iface) -> {
                qualified_interface_display(ctx, iface)
            });
            let error: TirTypeError = if (p.is_field) {
                TirTypeErrorAmbiguousInterfaceField {
                    class_name: receiver,
                    field_name: p.member,
                    sources: sources,
                }
            } else {
                TirTypeErrorAmbiguousInterfaceMethod {
                    class_name: receiver,
                    method_name: p.member,
                    sources: sources,
                }
            };
            pending_diag_at_expr(error, p.expr)
        },
        let p: PendingDiagFieldRequiresProjection => {
            pending_diag_at_expr(
                TirTypeErrorInterfaceFieldRequiresProjection {
                    class_name: ty_spell(plain_finalized(ctx, p.base), infer_ctx_viewpoint(ctx)),
                    field_name: p.member,
                    interface_name: qualified_interface_display(ctx, p.interface_),
                },
                p.expr,
            )
        },
        let p: PendingDiagSelfRestrictedMember => {
            pending_diag_at_expr(
                TirTypeErrorInvalidSelfCallThroughInterface {
                    interface_name: qualified_interface_display(ctx, p.interface_),
                    method_name: p.member,
                    position: p.position,
                },
                p.expr,
            )
        },
        let p: PendingDiagSelflessInstanceMember => {
            pending_diag_at_expr(
                TirTypeErrorSelflessInstanceMember {
                    interface_name: p.interface_name,
                    method_name: p.member,
                },
                p.expr,
            )
        },
        let p: PendingDiagItemProjectionSelfSlot => pending_diag_to_tir_self_slot(ctx, p),
        let p: PendingDiagUnionNoCommonInterface => {
            pending_diag_at_expr(
                TirTypeErrorUnionMemberNoCommonInterface {
                    union: plain_finalized(ctx, p.base),
                    member: p.member,
                },
                p.expr,
            )
        },
        let p: PendingDiagUnionAssociatedTypeConflict => {
            pending_diag_at_expr(
                TirTypeErrorUnionMemberAssociatedTypeConflict {
                    union: plain_finalized(ctx, p.base),
                    member: p.member,
                    is_method: p.is_method,
                    types: p.types.map((ty) -> {
                        plain_finalized(ctx, ty)
                    }),
                },
                p.expr,
            )
        },
        let p: PendingDiagQualifierNotInterface => {
            pending_diag_at_expr(
                TirTypeErrorInvalidInterfaceUpcastTarget { target: plain_finalized(ctx, p.target) },
                p.expr,
            )
        },
        let p: PendingDiagUnresolvedShorthand => {
            pending_diag_error_at(
                TirTypeErrorUnresolvedPropertyShorthand { name: p.name, suggestions: p.suggestions },
                DiagnosticLocationExpr { value: p.expr },
            )
        },
        let p: PendingDiagUnnecessaryOptionalChain => {
            pending_diag_at_expr(
                TirTypeErrorUnnecessaryOptionalChaining { expr: p.expr_text, base: p.base_text },
                p.expr,
            )
        },
        let p: PendingDiagTupleElementAssign => {
            pending_diag_at_expr(TirTypeErrorTupleElementNotAssignable {}, p.expr)
        },
        let p: PendingDiagTupleIndexOutOfRange => {
            let variant = p.variant;
            pending_diag_at_expr(
                TirTypeErrorTupleIndexOutOfRange {
                    index: p.index,
                    tuple: plain_finalized(ctx, p.tuple),
                    variant: if (variant != null) {
                        plain_finalized(ctx, variant)
                    } else {
                        null
                    },
                },
                p.expr,
            )
        },
        let p: PendingDiagInvalidAssignmentTarget => {
            pending_diag_at_expr(TirTypeErrorInvalidAssignmentTarget { path: p.path }, p.expr)
        },
        let p: PendingDiagAssignmentToGlobal => {
            pending_diag_error_at(
                TirTypeErrorAssignmentToGlobal { name: p.name, is_client: p.is_client },
                DiagnosticLocationExpr { value: p.target },
            )
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s `ItemProjectionSelfSlot` arm: a selfless interface item reached
// through `Self`'s slot. `never` names no implementor, and a LITERAL type is
// not an implementor either (impls attach to its base); an existential or a
// union slot reports by how `Self` is dispatched.
function pending_diag_to_tir_self_slot(
    ctx: InferenceContext,
    p: PendingDiagItemProjectionSelfSlot,
) -> TirDiagnostic? throws never {
    let pool = ctx.table.pool;
    let slot = finalize_ty(ctx, p.var);
    let slot_kind = pool.kinds[slot.ty];
    if (slot_kind is root.types.TyNever || slot_kind is root.types.TyLiteral) {
        return pending_diag_error_at(
            TirTypeErrorSelflessMethodNeedsConcreteSelf {
                interface_name: qualified_interface_display(ctx, p.interface_),
                method_name: p.member,
                self_ty: materialize_ty(ctx, slot.ty),
            },
            DiagnosticLocationExpr { value: p.expr },
        );
    }
    if (!(slot_kind is root.types.InferTyInterface || slot_kind is root.types.InferTyUnion)) {
        return null;
    }
    let interface_name = qualified_interface_display(ctx, p.interface_);
    match (p.dispatch) {
        let breaks: SelfDispatchBreaks => {
            pending_diag_at_expr(
                TirTypeErrorInvalidSelfCallThroughInterface {
                    interface_name: interface_name,
                    method_name: p.member,
                    position: breaks.value,
                },
                p.expr,
            )
        },
        SelfDispatchNoSelfParam => {
            pending_diag_at_expr(
                TirTypeErrorSelflessMethodNeedsConcreteSelf {
                    interface_name: interface_name,
                    method_name: p.member,
                    self_ty: materialize_ty(ctx, slot.ty),
                },
                p.expr,
            )
        },
        // A CALL dispatches off the `Self`-typed argument's runtime type; a
        // reified value has no resolution moment.
        SelfDispatchOnParam => {
            if (p.value_position) {
                pending_diag_at_expr(
                    TirTypeErrorErasedSelfMethodValue {
                        interface_name: interface_name,
                        method_name: p.member,
                        self_ty: materialize_ty(ctx, slot.ty),
                    },
                    p.expr,
                )
            } else {
                null
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s pending arms for interface goals and operators.
function pending_diag_to_tir_obligation(
    ctx: InferenceContext,
    pending: PendingDiagObligationFamily,
) -> TirDiagnostic? throws never {
    let pool = ctx.table.pool;
    match (pending) {
        let p: PendingDiagBoundedArgNotConcrete => {
            let related = required_for_notes(ctx, p.expr, p.required_for);
            pending_diag_at_expr(
                TirTypeErrorBoundedTypeArgNotConcrete {
                    arg: plain_finalized(ctx, p.arg),
                    bound: [materialize_interface(ctx, p.bound)],
                },
                p.expr,
                related = related,
            )
        },
        let p: PendingDiagDoesNotImplement => {
            let related = required_for_notes(ctx, p.expr, p.required_for);
            let elided = with_unsolved_pins_elided(ctx, p.interface_);
            // A value that ALMOST implements the interface through a blanket
            // `implements` rule names the unsatisfied bound rather than the
            // bare verdict.
            let value = finalize_ty(ctx, p.value);
            let interface_ = finalize_ty(ctx, elided);
            // The for-desugar's iterability goal reads as its own message,
            // keyed on the interface.
            let iterable = lang_decl(ctx, root.base.LangPackage.Baml, ["iter"], "Iterable");
            let interface_kind = pool.kinds[interface_.ty];
            let error: TirTypeError = if (
                interface_kind is root.types.InferTyInterface
                    && iterable != null
                    && interface_kind.name == iterable
            ) {
                TirTypeErrorNotIterable { ty: pool.to_plain_closed(value.ty) }
            } else {
                let bound = first_failing_blanket_bound(ctx, value.ty, interface_.ty);
                if (bound != null) {
                    TirTypeErrorBlanketBoundNotSatisfied {
                        value_type: pool.to_plain_closed(value.ty),
                        bound: bound,
                    }
                } else {
                    TirTypeErrorTypeDoesNotImplementInterface {
                        value_type: pool.to_plain_closed(value.ty),
                        interface_: pool.to_plain_closed(interface_.ty),
                    }
                }
            };
            pending_diag_at_expr(error, p.expr, related = related)
        },
        let p: PendingDiagAmbiguousImplementation => {
            let related = required_for_notes(ctx, p.expr, p.required_for);
            let elided = with_unsolved_pins_elided(ctx, p.interface_);
            pending_diag_at_expr(
                TirTypeErrorAmbiguousImplementation {
                    value_type: plain_finalized(ctx, p.value),
                    interface_: plain_finalized(ctx, elided),
                },
                p.expr,
                related = related,
            )
        },
        let p: PendingDiagOperatorNotApplicable => {
            let lhs = plain_finalized(ctx, p.lhs);
            let rhs_ty = p.rhs;
            let rhs = if (rhs_ty != null) {
                plain_finalized(ctx, rhs_ty)
            } else {
                null
            };
            let error: TirTypeError = if (p.interface_ == "Index") {
                TirTypeErrorNotIndexable { ty: lhs }
            } else if (p.interface_ == "Negate") {
                TirTypeErrorInvalidUnaryOp { op: root.ast.UnaryOp.Neg, operand: lhs }
            } else if (rhs != null) {
                let op = match (p.interface_) {
                    "Add" => root.ast.BinaryOp.Add,
                    "Subtract" => root.ast.BinaryOp.Sub,
                    "Multiply" => root.ast.BinaryOp.Mul,
                    "Divide" => root.ast.BinaryOp.Div,
                    "Remainder" => root.ast.BinaryOp.Mod,
                    "BitAnd" => root.ast.BinaryOp.BitAnd,
                    "BitOr" => root.ast.BinaryOp.BitOr,
                    "BitXor" => root.ast.BinaryOp.BitXor,
                    "ShiftLeft" => root.ast.BinaryOp.Shl,
                    "ShiftRight" => root.ast.BinaryOp.Shr,
                    _ => root.ast.BinaryOp.Add,
                };
                TirTypeErrorInvalidBinaryOp { op: op, lhs: lhs, rhs: rhs }
            } else {
                TirTypeErrorInvalidUnaryOp { op: root.ast.UnaryOp.Neg, operand: lhs }
            };
            pending_diag_error_at(error, DiagnosticLocationExpr { value: p.expr })
        },
        let p: PendingDiagComparisonAlwaysDisjoint => {
            TirDiagnostic {
                error: TirTypeErrorComparisonAlwaysDisjoint {
                    op: p.op,
                    lhs: plain_finalized(ctx, p.lhs),
                    rhs: plain_finalized(ctx, p.rhs),
                },
                severity: DiagnosticSeverity.Warning,
                primary: DiagnosticLocationExpr { value: p.at },
                related: [],
            }
        },
        let p: PendingDiagOrderingDifferentTypes => {
            pending_diag_error_at(
                TirTypeErrorOrderingDifferentTypes {
                    op: p.op,
                    lhs: plain_finalized(ctx, p.lhs),
                    rhs: plain_finalized(ctx, p.rhs),
                },
                DiagnosticLocationExpr { value: p.at },
            )
        },
        let p: PendingDiagOrderingRequiresCompare => {
            pending_diag_error_at(
                TirTypeErrorOrderingRequiresCompare { op: p.op, ty: plain_finalized(ctx, p.ty) },
                DiagnosticLocationExpr { value: p.at },
            )
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s pending arms for written annotations and block-scoped types.
function pending_diag_to_tir_annotation(
    ctx: InferenceContext,
    pending: PendingDiagAnnotationFamily,
) -> TirDiagnostic? throws never {
    match (pending) {
        let p: PendingDiagAnnotWf => {
            pending_diag_error_at(p.error, DiagnosticLocationBodyTypeRef { value: p.type_ref })
        },
        let p: PendingDiagBodyAnnot => {
            pending_diag_error_at(lowering_diag_error(p.kind), DiagnosticLocationBodyTypeRef { value: p.type_ref })
        },
        let p: PendingDiagExprPositionHole => {
            pending_diag_at_expr(TirTypeErrorCannotInferType {}, p.expr)
        },
        let p: PendingDiagScopedTypeEscapesBlock => {
            let value = plain_finalized(ctx, p.value);
            // The thrown type is final here, so this is where the remedy the
            // label names can be computed rather than described.
            let kind: ScopedTypeEscapeKind = match (p.kind) {
                ScopedTypeEscapeKindThrown => {
                    ScopedTypeEscapeKindThrown {
                        relaxation: nearest_scoped_relaxation(value, RelaxationVariance.Covariant),
                    }
                },
                let other: ScopedTypeEscapeKindValue | ScopedTypeEscapeKindInferred => other,
            };
            pending_diag_at_expr(TirTypeErrorScopedTypeEscapesBlock { name: p.name, value: value, kind: kind }, p.at)
        },
        let p: PendingDiagBoundedLetTypeRequiresElse => {
            pending_diag_error_at(
                TirTypeErrorBoundedLetTypeRequiresElse { name: p.name },
                DiagnosticLocationStmt { value: p.stmt },
            )
        },
        let p: PendingDiagLetTypePendingOperand => {
            pending_diag_at_expr(TirTypeErrorLetTypePendingOperand {}, p.expr)
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s pending arms for control flow, effects, conditions and
// templates. Threads the loop-carried `reported_units`, and records a
// surviving throws violation on `result`'s mismatch channel.
function pending_diag_to_tir_control(
    ctx: InferenceContext,
    body: root.ast.ExprBody?,
    result: InferenceResult<int>,
    pending: PendingDiagControlFamily,
    reported_units: DiagnosticLocation[],
) -> TirDiagnostic? throws never {
    let pool = ctx.table.pool;
    match (pending) {
        let p: PendingDiagReturnOutsideFunctionBody => {
            pending_diag_error_at(TirTypeErrorReturnOutsideFunctionBody { context: p.context }, p.at)
        },
        let p: PendingDiagDeferEscape => {
            pending_diag_error_at(TirTypeErrorDeferControlFlowEscape { keyword: p.keyword }, p.at)
        },
        let p: PendingDiagLoopControlOutsideLoop => {
            pending_diag_error_at(
                TirTypeErrorLoopControlOutsideLoop { keyword: p.keyword, barrier: p.barrier },
                DiagnosticLocationStmt { value: p.stmt },
            )
        },
        let p: PendingDiagLoopControlInLoopHeader => {
            pending_diag_error_at(
                TirTypeErrorLoopControlInLoopHeader { keyword: p.keyword, slot: p.slot },
                DiagnosticLocationStmt { value: p.stmt },
            )
        },
        let p: PendingDiagImplicitUnit => {
            pending_diag_to_tir_implicit_unit(ctx, result, p, reported_units)
        },
        let p: PendingDiagExtraneousThrows => {
            TirDiagnostic {
                error: TirTypeErrorExtraneousThrowsDeclaration { extra_types: p.extra_types },
                severity: DiagnosticSeverity.Warning,
                primary: DiagnosticLocationExpr { value: p.at },
                related: [],
            }
        },
        let p: PendingDiagImpreciseUnknownThrows => {
            pending_diag_error_at(
                TirTypeErrorImpreciseUnknownThrows {
                    inferred: p.inferred,
                    needs_declaration: p.needs_declaration,
                },
                DiagnosticLocationExpr { value: p.at },
            )
        },
        let p: PendingDiagThrowsViolation => pending_diag_to_tir_throws_violation(ctx, result, p),
        let p: PendingDiagConditionAlwaysConst => {
            let ty = plain_finalized(ctx, p.ty);
            if (body != null) {
                if let function_ty: root.types.TyFunction = ty {
                    return root.hir_ty.infer.uncalled_function_diagnostic(
                        body,
                        p.expr,
                        function_ty.params.every((param) -> {
                            param.mode == root.types.FunctionParamMode.Optional
                        }),
                    );
                }
            }
            TirDiagnostic {
                error: TirTypeErrorConditionAlwaysConstant { ty: ty, always_true: p.always_true },
                severity: DiagnosticSeverity.Warning,
                primary: DiagnosticLocationExpr { value: p.expr },
                related: [],
            }
        },
        let p: PendingDiagInterpolatedMaybeNull => {
            pending_diag_at_expr(TirTypeErrorInterpolatedValueMaybeNull { ty: plain_finalized(ctx, p.ty) }, p.expr)
        },
        let p: PendingDiagInterpolatedRoleMarker => {
            pending_diag_at_expr(TirTypeErrorRoleMarkerInUntaggedTemplate { ty: plain_finalized(ctx, p.ty) }, p.expr)
        },
        let p: PendingDiagBareOutputFormatReference => {
            pending_diag_at_expr(TirTypeErrorOutputFormatNotCalled {}, p.expr)
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s `ImplicitUnit` arm: judged on the solved types; one implicit
// unit reports once (`reported_units`). An error sentinel is a context
// already diagnosed.
function pending_diag_to_tir_implicit_unit(
    ctx: InferenceContext,
    result: InferenceResult<int>,
    p: PendingDiagImplicitUnit,
    reported_units: DiagnosticLocation[],
) -> TirDiagnostic? throws never {
    let pool = ctx.table.pool;
    let site = p.site;
    if (
        reported_units.some((at) -> {
            at == site.at
        })
    ) {
        return null;
    }
    let null_ty = pool.add(root.types.TyNull {});
    let (let context, let admitted) = match (p.demand) {
        let demand: UnitDemandExpected => {
            // A variable nothing solved is not one: it finalizes to the
            // sentinel with no report of its own, and it did not solve to
            // unit.
            let unsolved = pool.has_infer(ctx.table.resolve_completely(demand.value));
            let expected = finalize_ty(ctx, demand.value);
            let admitted = !unsolved
                && (
                    pool.kinds[expected.ty] is root.types.TyError
                        || cached_equivalent(ctx, expected.ty, null_ty)
                );
            (expected, admitted)
        },
        let demand: UnitDemandJoined => {
            let others = finalize_ty(ctx, demand.value);
            (others, cached_subtype(ctx, others.ty, null_ty))
        },
    };
    if (admitted) {
        return null;
    }
    reported_units.push(site.at);
    // A context with a hole in it (`!error`) is compatible with anything, so
    // nothing is known of what would fit it.
    let whole = !pool.has_error(context.ty);
    let (let form, let primary) = match (site.form) {
        let block: UnitSiteFormBlockWithoutTail => {
            // A value of the wanted type right before the end of the block is
            // the likelier slip than a missing one, and reports where its `;`
            // is.
            let last_value = block.last_value;
            let discarded = if (whole && last_value != null) {
                let recorded = result.type_of_expr.get(last_value.1);
                if (recorded != null) {
                    let ty = finalize_ty(ctx, recorded).ty;
                    !pool.has_error(ty)
                        && !(pool.kinds[ty] is root.types.TyNever)
                        && !cached_subtype(ctx, ty, null_ty)
                        && cached_subtype(ctx, ty, context.ty)
                } else {
                    false
                }
            } else {
                false
            };
            let at: DiagnosticLocation = if (discarded && last_value != null) {
                DiagnosticLocationStmt { value: last_value.0 }
            } else {
                site.at
            };
            let f: ImplicitUnitForm = ImplicitUnitFormBlockWithoutTail { discards_value: discarded };
            (f, at)
        },
        UnitSiteFormIfWithoutElse => {
            let f: ImplicitUnitForm = ImplicitUnitFormIfWithoutElse {};
            (f, site.at)
        },
        UnitSiteFormBareReturn => {
            let f: ImplicitUnitForm = ImplicitUnitFormBareReturn {};
            (f, site.at)
        },
    };
    let admits_unit = whole && cached_subtype(ctx, null_ty, context.ty);
    pending_diag_error_at(
        TirTypeErrorImplicitUnit {
            form: form,
            expected: pool.to_plain_closed(context.ty),
            admits_unit: admits_unit,
        },
        primary,
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s `ThrowsViolation` arm. A check can fail MID-INFERENCE on open
// variables later resolution satisfies; cascades suppress. A synthetic
// effect param traces to a CALLBACK parameter, named in the message. A
// surviving violation also records on the mismatch channel at the thrown
// value (after the mismatch render loop, so E0096 stays the one diagnostic
// for it).
function pending_diag_to_tir_throws_violation(
    ctx: InferenceContext,
    result: InferenceResult<int>,
    p: PendingDiagThrowsViolation,
) -> TirDiagnostic? throws never {
    let pool = ctx.table.pool;
    let declared = finalize_ty(ctx, p.declared);
    let extra = finalize_ty(ctx, p.extra);
    if (
        pool.has_error(declared.ty)
            || pool.has_error(extra.ty)
            || cached_subtype(ctx, extra.ty, declared.ty)
    ) {
        return null;
    }
    if let param: root.types.TyTypeVar = pool.kinds[extra.ty] {
        if (root.types.is_synthetic_effect_param(param.param.name)) {
            let callback = callback_param_for_effect(ctx, param.param);
            if (callback != null) {
                return pending_diag_error_at(
                    TirTypeErrorCallbackThrowsContractViolation {
                        callback_name: callback,
                        declared: pool.to_plain_closed(declared.ty),
                        concrete_throws: null,
                    },
                    DiagnosticLocationExpr { value: p.at },
                );
            }
        }
    }
    let extra_union = throws_clause_union(flatten_declared_ty_to_facts(pool.to_plain_closed(extra.ty)));
    if (extra_union == null) {
        return null;
    }
    if (!result.type_mismatches.has(p.at)) {
        result.type_mismatches[p.at] = (declared.ty, extra.ty);
    }
    pending_diag_error_at(
        TirTypeErrorThrowsContractViolation {
            declared: pool.to_plain_closed(declared.ty),
            extra: extra_union,
        },
        DiagnosticLocationExpr { value: p.at },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish @ d9be6853b
// `finish`'s pending arms for patterns, matches and `let`s.
function pending_diag_to_tir_pattern(
    ctx: InferenceContext,
    pending: PendingDiagPatternFamily,
) -> TirDiagnostic? throws never {
    match (pending) {
        let p: PendingDiagNonExhaustiveMatch => {
            pending_diag_at_expr(
                TirTypeErrorNonExhaustiveMatch {
                    scrutinee_type: plain_finalized(ctx, p.scrutinee),
                    missing_cases: p.missing,
                },
                p.expr,
            )
        },
        let p: PendingDiagNonExhaustiveCatchAll => {
            pending_diag_at_expr(
                TirTypeErrorNonExhaustiveCatchAll {
                    keyword: p.keyword,
                    caught_type: p.caught,
                    missing_cases: p.missing,
                },
                p.expr,
            )
        },
        let p: PendingDiagUnreachableArm => {
            pending_diag_at_expr(TirTypeErrorUnreachableArm {}, p.expr, unreachable_is_warning = p.warning)
        },
        let p: PendingDiagScrutineeTypeMustBeKnown => {
            pending_diag_error_at(
                TirTypeErrorTypeMustBeKnown { full_type: p.full_type },
                DiagnosticLocationExpr { value: p.expr },
            )
        },
        let p: PendingDiagListPatternNeverMatches => {
            pending_diag_error_at(
                TirTypeErrorListPatternNeverMatches { scrutinee: plain_finalized(ctx, p.scrutinee) },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagUninferredPatternTypeParam => {
            pending_diag_error_at(
                TirTypeErrorCannotInferTypeParameter { name: p.name },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagUninferredPatternAssociatedType => {
            pending_diag_error_at(
                TirTypeErrorCannotInferAssociatedType { name: p.name },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagPatternScrutMismatch => {
            pending_diag_error_at(
                TirTypeErrorTypeMismatch {
                    expected: plain_finalized(ctx, p.expected),
                    got: plain_finalized(ctx, p.found),
                },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagTupleTypeTestNeverMatches => {
            pending_diag_error_at(
                TirTypeErrorTupleTypeTestNeverMatches {
                    scrutinee: plain_finalized(ctx, p.scrutinee),
                    tested: plain_finalized(ctx, p.tested),
                },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagUnresolvedPatternName => {
            pending_diag_error_at(
                removed_reflect_spelling(p.name)
                    ?? TirTypeErrorUnresolvedType { name: p.name, suggestions: p.suggestions },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagRestNotBinding => {
            pending_diag_error_at(TirTypeErrorRestSubPatternNotBinding {}, DiagnosticLocationPat { value: p.pat })
        },
        let p: PendingDiagOrBindingConflict => {
            pending_diag_error_at(
                TirTypeErrorOrPatternBindingTypeMismatch {
                    name: p.name,
                    first_type: plain_finalized(ctx, p.first),
                    other_type: plain_finalized(ctx, p.other),
                },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagGenericDestructureNoArgs => {
            pending_diag_error_at(
                TirTypeErrorGenericClassDestructureRequiresTypeArgs { class_name: p.class_name },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagUnknownPatternField => {
            pending_diag_error_at(
                TirTypeErrorUnknownClassPatternField {
                    class_name: p.class_name,
                    field_name: p.field_name,
                    suggestions: similar_name_suggestions(p.field_name, p.declared),
                },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagRefutableLet => {
            pending_diag_error_at(
                TirTypeErrorRefutablePatternInLet { context: p.context },
                DiagnosticLocationPat { value: p.pat },
            )
        },
        let p: PendingDiagLetElseMustDiverge => {
            pending_diag_at_expr(TirTypeErrorLetElseMustDiverge { got: plain_finalized(ctx, p.got) }, p.expr)
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::required_for_notes @ d9be6853b
// A note for each goal whose confirmed impl required a reported goal, the
// nearest first (rustc's "required for `X` to implement `I`"), all at the
// reported expression. A self-satisfying impl repeats one requirement down
// its chain, which is noted once.
function required_for_notes(
    ctx: InferenceContext,
    at: int,
    required_for: root.hir_ty.infer.RequiredFor[],
) -> RelatedNote[] throws never {
    let vp = infer_ctx_viewpoint(ctx);
    let notes: RelatedNote[] = [];
    for (let index = required_for.length() - 1; index >= 0; index -= 1) {
        let goal = required_for[index];
        let interface_ = with_unsolved_pins_elided(ctx, root.types.infer_interface_existential(ctx.table.pool, goal.interface_));
        let message = ``required for `${ty_spell(plain_finalized(ctx, goal.subject), vp)}` to implement `${ty_spell(plain_finalized(ctx, interface_), vp)}```;
        if (
            notes.every((note) -> {
                note.message != message
            })
        ) {
            notes.push(
                RelatedNote { location: RelatedLocationExpr { value: at }, message: message },
            );
        }
    }
    notes
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::with_unsolved_pins_elided @ d9be6853b
// `interface_` (an existential) without the pins inference never solved: a
// failed goal leaves its pins open, so they say nothing about what the user
// has to fix.
function with_unsolved_pins_elided(ctx: InferenceContext, interface_: int) -> int throws never {
    let pool = ctx.table.pool;
    let resolved = ctx.table.resolve_completely(interface_);
    match (pool.kinds[resolved]) {
        let iface: root.types.InferTyInterface => {
            let pins = iface.associated_types.filter((pin) -> {
                !pool.has_infer(pin.ty) && !pool.has_error(pin.ty)
            });
            pool.add(
                root.types.InferTyInterface {
                    name: iface.name,
                    args: iface.args,
                    associated_types: pins,
                },
            )
        },
        _ => resolved,
    }
}

// port: baml_compiler2_hir_ty/src/throw_facts.rs::flatten_declared_ty_to_facts @ d9be6853b
// A declared throws type as throw facts: union members decomposed, literals
// widened to their primitive, `never` dropped. Rust's `BTreeSet<Ty>` is
// sorted by `cmp_ty` and deduplicated.
function flatten_declared_ty_to_facts(ty: root.types.Ty) -> root.types.Ty[] throws never {
    let out: root.types.Ty[] = [];
    collect_widened_leaf_types(ty, out);
    out.sort_by(root.types.cmp_ty);
    let facts: root.types.Ty[] = [];
    for (let fact in out) {
        if (facts.length() == 0 || facts[facts.length() - 1] != fact) {
            facts.push(fact);
        }
    }
    facts
}

// port: baml_compiler2_hir_ty/src/throw_facts.rs::collect_widened_leaf_types @ d9be6853b
function collect_widened_leaf_types(ty: root.types.Ty, out: root.types.Ty[]) -> void throws never {
    match (ty) {
        // Compound types: decompose.
        let u: root.types.TyUnion => {
            for (let member in u.members) {
                collect_widened_leaf_types(member, out);
            }
        },
        // Literal types: widen to primitive for throw fact purposes.
        let l: root.types.TyLiteral => {
            out.push(
                match (l.value) {
                    root.base.LiteralInt => root.types.TyInt {},
                    root.base.LiteralBigint => root.types.TyBigint {},
                    root.base.LiteralFloat => root.types.TyFloat {},
                    root.base.LiteralString => root.types.TyString {},
                    root.base.LiteralBool => root.types.TyBool {},
                },
            );
        },
        // Bottom: no facts.
        root.types.TyNever => {},
        // Everything else: keep as-is.
        _ => {
            out.push(ty);
        },
    }
}
