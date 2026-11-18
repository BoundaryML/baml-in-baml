// port: baml_compiler2_hir_ty/src/infer/pat.rs @ d9be6853b
//
// Pattern typing and match exhaustiveness: every pattern site (`match`
// arms, `is` tests, destructuring `let`, `catch` arms) lowers its pattern
// against the scrutinee here, recording binding types and producing the
// `DPat` row the usefulness matrix (exhaustiveness.baml) consumes over
// plain `root.types.Ty`. Class patterns adopt generic args from the
// scrutinee when none are written; claiming a union member requires
// PROVABLE overlap, so a rigid `T` pattern does not claim a `null` member.
//
// Restructured (BAML forces it):
// - `InferenceContext` methods are free functions taking `ctx` first, as in
//   infer.baml; interned types are `int`s into `ctx.table.pool`, and a
//   helper with no context takes the pool first.
// - `lower_pattern` and `lower_pattern_reaching` are one function: the
//   reaching type is the named default `reaching` (Rust's `lower_pattern`
//   passes the scrutinee for both).
// - `HirPatCtx` is a class implementing `root.hir_ty.PatCtx`. The
//   served-package lanes of its interface lookups (`mounted_interface_loc`,
//   `extern_interface_row`) are dropped: no root is served from an
//   interface (`root.hir.is_served_from_interface`), so Rust takes the
//   source lane or returns nothing, as here.
// Not ported: `lower_pattern_inner`'s `written_refs` list, which Rust
// builds and never reads.

// port: baml_compiler2_hir_ty/src/infer/pat.rs::PatternOutcome @ d9be6853b
// One lowered pattern: the matrix row piece, the refined scrutinee type the
// arm body sees, and two type-only verdicts. `covers_type`: the pattern
// matches EVERY scrutinee value (irrefutability). `consumes_matched`: the
// pattern matches every value of its OWN `matched_ty` (no literal, field,
// or length constraint), the gate for else-side subtraction and match
// residual accumulation.
class PatternOutcome {
    dpat: root.hir_ty.DPat,
    matched_ty: int,
    // The WRITTEN form to record when it differs from `matched_ty`: a type
    // ascription records the declared spelling, while `matched_ty` stays the
    // refined form that drives narrowing and destructuring.
    recorded_ty: int?,
    covers_type: bool,
    consumes_matched: bool,
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::ListHolding @ d9be6853b
// The lists a list pattern can match among one type's values.
type ListHolding = ListHoldingElements | ListHoldingAnyElements;

// Lists of exactly this element type.
class ListHoldingElements {
    value: int,
}

// Lists of any element type, among other values: no one list type describes
// them, and their elements are only known to be `unknown`.
class ListHoldingAnyElements {
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::infer_match @ d9be6853b
// Match typing: lower every arm's pattern against the scrutinee, narrow the
// scrutinee binding per arm, type the bodies against the branch
// expectation, then run the usefulness matrix over the unguarded arms
// (guarded arms contribute nothing to exhaustiveness). Non-exhaustive ->
// Error sentinel.
function infer_match(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    match_expr: int,
    scrutinee: int,
    arms: int[],
    expected: root.hir_ty.Expectation,
) -> int throws never {
    let pool = ctx.table.pool;
    let written_scrutinee = ctx.type_refs.match_scrutinee_types.get(match_expr);
    let scrut_ty = if (written_scrutinee != null) {
        let annotation = root.hir_ty.lower_body_annotation(ctx, written_scrutinee);
        root.hir_ty.check_expr(ctx, body, scrutinee, annotation);
        // A match annotation declares the matrix's full input type. Keep it
        // instead of narrowing back to the scrutinee's current concrete
        // value so later arms remain reachable.
        annotation
    } else {
        root.hir_ty.infer_expr(ctx, body, scrutinee, root.hir_ty.ExpectationNone {})
    };
    let scrut_resolved = scrutinee_demand(ctx, scrut_ty);
    // An arm that writes a type or a shape is typed against the scrutinee's
    // structure here, so the type must be known at that point: a structural
    // demand, refused here whatever a variable later solves to. Arms that
    // only bind ask for nothing. The report owns the open classes, and a
    // class an earlier error already owns is that error's cascade.
    let needs_structure = arms.some((arm) -> {
        !binds_without_a_type(body, body.match_arms[arm].pattern)
    });
    let refused_open = needs_structure && !pool.has_error(scrut_resolved) && pool.has_infer(scrut_resolved);
    if (refused_open) {
        let open_roots = ctx.table.open_roots_in(scrut_resolved);
        let owed = open_roots.some((root_var) -> {
            !ctx.table.is_tainted(root_var)
        });
        for (let root_var in open_roots) {
            ctx.table.taint_root(root_var);
        }
        if (owed) {
            let full_type = root.hir_ty.plain_finalized(ctx, scrut_resolved);
            root.hir_ty.report(
                ctx,
                root.hir_ty.PendingDiagScrutineeTypeMustBeKnown {
                    expr: scrutinee,
                    full_type: full_type,
                },
            );
        }
    }
    let scrut_binding = narrowable_binding(ctx, body, scrutinee);
    let branch_expectation = root.hir_ty.expectation_adjust_for_branches(expected, ctx.table);

    // Arm execution can change outer locals. Do not restore an entry fact
    // after an arm (or its deferred cleanup) invalidates it.
    for (let arm_id in arms) {
        let arm = body.match_arms[arm_id];
        let guard = arm.guard;
        let roots_of_arm = if (guard != null) {
            [guard, arm.body]
        } else {
            [arm.body]
        };
        for (let root_expr in roots_of_arm) {
            for (let binding in assigned_bindings(ctx, body, root_expr).keys()) {
                ctx.flow.delete(binding);
            }
        }
    }

    let entry_diverges = diverges(ctx);
    let arm_tys: int[] = [];
    let matrix_arms: root.hir_ty.DPat[] = [];
    let matrix_arm_bodies: int[] = [];
    let any_pattern_error = false;
    let all_diverge: root.hir_ty.Diverges = root.hir_ty.Diverges.Always;
    // The residual accumulator: each unguarded arm that is refutable by type
    // alone subtracts what it matched, so a later catch-all arm sees the
    // complement.
    let residual = scrut_resolved;
    let pending_before = ctx.journals.pending_diags.length();
    for (let arm_id in arms) {
        let arm = body.match_arms[arm_id];
        // The arm's own catch-all bindings read the same way as the
        // scrutinee does in the arm: `null => .., let rest => ..` binds
        // `rest` to the non-null remainder.
        let outcome = lower_pattern(ctx, body, arm.pattern, scrut_resolved, reaching = residual);
        any_pattern_error = any_pattern_error || pool.has_error(outcome.matched_ty);
        // A pattern irrefutable against the full scrutinee is really
        // matching the residual; typed arms take their own refinement.
        let narrow_ty = if (outcome.covers_type) {
            residual
        } else {
            outcome.matched_ty
        };

        let saved_flow = root.hir_ty.copy_flow(ctx.flow);
        if (scrut_binding != null) {
            ctx.flow.set(scrut_binding, narrow_ty);
        }
        set_diverges(ctx, root.hir_ty.Diverges.Maybe);
        let guard = arm.guard;
        if (guard != null) {
            let (_, let guard_facts) = check_condition(ctx, body, guard);
            apply_facts(ctx, guard_facts.when_true);
        }
        let arm_ty = root.hir_ty.infer_branch(ctx, body, arm.body, branch_expectation);
        all_diverge = root.hir_ty.diverges_and(all_diverge, diverges(ctx));
        ctx.flow = saved_flow;
        arm_tys.push(arm_ty);
        if (arm.guard == null) {
            if (outcome.consumes_matched) {
                residual = subtract_narrow(ctx, residual, outcome.matched_ty);
            }
            matrix_arms.push(outcome.dpat);
            matrix_arm_bodies.push(arm.body);
        }
    }
    set_diverges(ctx, root.hir_ty.diverges_or(entry_diverges, all_diverge));
    let parts = baml.Array.generate(arms.length(), (i) -> {
        (arm_tys[i], root.hir_ty.take_units(ctx, body.match_arms[arms[i]].body))
    });
    let units = root.hir_ty.join_units(ctx, parts, expected);
    // An unknown FIELD in some arm's class pattern makes that arm's matrix
    // row a lie, so usefulness verdicts are noise.
    any_pattern_error
        = any_pattern_error
            || ctx.journals.pending_diags.slice(pending_before, ctx.journals.pending_diags.length())
                .some((pending) -> {
                    pending is root.hir_ty.PendingDiagUnknownPatternField
                });

    if (pool.has_error(scrut_resolved)) {
        return pool.add(root.types.TyError {});
    }
    if (pool.has_infer(scrut_resolved)) {
        if (refused_open) {
            return pool.add(root.types.TyError {});
        }
        // Catch-all arms over a scrutinee still being inferred: the first
        // unguarded one takes every value, so the match is exhaustive and
        // every unguarded arm after it is unreachable. With every arm
        // guarded, nothing names a narrower witness than `_`.
        if (matrix_arm_bodies.length() == 0) {
            root.hir_ty.report(
                ctx,
                root.hir_ty.PendingDiagNonExhaustiveMatch {
                    expr: match_expr,
                    scrutinee: scrut_resolved,
                    missing: ["_"],
                },
            );
            ctx.result.non_exhaustive_matches.set(match_expr, true);
            return pool.add(root.types.TyError {});
        }
        for (let arm_body in matrix_arm_bodies.slice(1, matrix_arm_bodies.length())) {
            root.hir_ty.report(
                ctx,
                root.hir_ty.PendingDiagUnreachableArm { expr: arm_body, warning: false },
            );
        }
        if (units.length() > 0) {
            ctx.unjudged_units.set(match_expr, units);
        }
        return root.hir_ty.join(ctx, arm_tys);
    }
    let col_ty = pool.to_plain_closed(scrut_resolved);
    let usefulness = root.hir_ty.compute_match_usefulness(HirPatCtx { infer: ctx }, matrix_arms, col_ty);
    // An errored arm pattern makes the reachability verdicts noise.
    for (let arm in usefulness.unreachable_arms) {
        if (any_pattern_error) {
            break;
        }
        let arm_body = matrix_arm_bodies.at(arm);
        if (arm_body != null) {
            root.hir_ty.report(
                ctx,
                root.hir_ty.PendingDiagUnreachableArm { expr: arm_body, warning: false },
            );
        }
    }
    if (usefulness.missing.length() > 0) {
        // Non-exhaustive: the match can fall through, which the type system
        // rejects; E0062 carries the witnesses.
        let missing = usefulness.missing.map((w) -> {
            root.hir_ty.render_witness_pat(ctx.db, root.hir_ty.infer_ctx_viewpoint(ctx), w)
        });
        root.hir_ty.report(
            ctx,
            root.hir_ty.PendingDiagNonExhaustiveMatch {
                expr: match_expr,
                scrutinee: scrut_resolved,
                missing: missing,
            },
        );
        ctx.result.non_exhaustive_matches.set(match_expr, true);
        return pool.add(root.types.TyError {});
    }
    if (units.length() > 0) {
        ctx.unjudged_units.set(match_expr, units);
    }
    root.hir_ty.join(ctx, arm_tys)
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::scrutinee_demand @ d9be6853b
// The scrutinee demand every pattern site shares: resolve, force occurring
// vars (exhaustiveness and narrowing cannot defer), then matrix-normalize.
function scrutinee_demand(ctx: root.hir_ty.InferenceContext, ty: int) -> int throws never {
    let resolved = ctx.table.resolve_completely(ty);
    let forced = if (ctx.table.pool.has_infer(resolved)) {
        root.hir_ty.force_occurring_vars(ctx, resolved)
    } else {
        resolved
    };
    matrix_scrut(ctx, forced)
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::infer_is @ d9be6853b
// `expr is pattern`: the pattern lowers against the operand (no subtype
// gate: a never-matching test is legal and just false); the result is
// always bool. A narrowable operand also yields the facts of the test: the
// matched type when it holds and, for a pattern refutable by type alone,
// the rest when it does not.
function infer_is(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    scrutinee: int,
    pattern: int,
    position: TestPosition,
) -> (int, CondFacts) throws never {
    let pool = ctx.table.pool;
    let scrut_ty = root.hir_ty.infer_expr(ctx, body, scrutinee, root.hir_ty.ExpectationNone {});
    let binding = narrowable_binding(ctx, body, scrutinee);
    let operand = if (binding != null) {
        binding_flow_ty(ctx, binding)
    } else {
        scrut_ty
    };
    let scrut = scrutinee_demand(ctx, operand);
    // `is` is a runtime TYPE TEST: a pattern provably disjoint from the
    // scrutinee is a legal test that answers `false`, so it probes
    // silently. A branch condition on a narrowable local is the exception:
    // there the test is dead code, and it reports.
    let silent = binding == null || position == TestPosition.Value;
    let outcome = if (silent) {
        root.hir_ty.with_suppressed(ctx, root.hir_ty.Suppress.SilentTest, (this) -> {
            lower_pattern(this, body, pattern, scrut)
        })
    } else {
        lower_pattern(ctx, body, pattern, scrut)
    };
    let facts = CondFacts.default();
    if (binding != null) {
        // Subtraction only when the pattern is refutable by type alone: a
        // field- or length-constrained pattern failing tells us nothing
        // type-shaped about the scrutinee.
        if (outcome.consumes_matched) {
            let complement = subtract_narrow(ctx, scrut, outcome.matched_ty);
            facts.when_false.set(binding, complement);
        }
        facts.when_true.set(binding, outcome.matched_ty);
    }
    (pool.add(root.types.TyBool {}), facts)
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::infer_let_destructure @ d9be6853b
// Destructuring `let`: the initializer synthesizes (widened at the binding
// site), then the pattern lowers against it. A refutable pattern with no
// `else` reports E0111; the types are recorded either way.
function infer_let_destructure(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pattern: int,
    initializer: int?,
    has_else: bool,
) -> void throws never {
    let pool = ctx.table.pool;
    let init_ty = if (initializer != null) {
        // The pattern's informative type INFORMS the initializer: a class
        // destructure over a generic call solves the callee's return var
        // from the pattern's class. Inform-only: the pattern walk below is
        // the check.
        let informed = pattern_informative_ty(ctx, body, pattern);
        let expectation: root.hir_ty.Expectation = if (informed != null) {
            root.hir_ty.expectation_has_type(pool, informed)
        } else if (body.patterns[pattern] is root.ast.PatternWildcard) {
            // `let _ = ...` binds nothing: nobody reads the value.
            root.hir_ty.ExpectationDiscarded {}
        } else {
            root.hir_ty.ExpectationNone {}
        };
        let ty = root.hir_ty.infer_expr(ctx, body, initializer, expectation);
        if (informed != null && pool.has_infer(ty)) {
            // Deposit the demand as a bound so a generic callee's return
            // var solves from the pattern; a failure is the pattern walk's
            // to report.
            root.hir_ty.sub(ctx, ty, informed);
        }
        root.hir_ty.widen_fresh(ctx, ty)
    } else {
        pool.add(root.types.TyError {})
    };
    let resolved = scrutinee_demand(ctx, init_ty);
    let outcome = lower_pattern(ctx, body, pattern, resolved);
    // A refutable pattern in an irrefutable position has nowhere to go when
    // it fails (E0111), unless the `else` branch is that somewhere.
    // Error-typed scrutinees are cascades.
    if (
        !has_else
            && !outcome.covers_type
            && !pool.has_error(outcome.matched_ty)
            && !pool.has_error(resolved)
            && !pool.has_infer(resolved)
    ) {
        root.hir_ty.report(
            ctx,
            root.hir_ty.PendingDiagRefutableLet {
                pat: pattern,
                context: root.hir_ty.IrrefutableContextKind.Let,
            },
        );
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_informative_ty @ d9be6853b
// The informative type a pattern DEMANDS of its scrutinee, when one exists:
// a class pattern's head (written args honored, unwritten as fresh vars),
// through binds; an or-pattern's UNIQUE informative branch.
function pattern_informative_ty(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
) -> int? throws never {
    match (body.patterns[pat]) {
        let b: root.ast.PatternBind => {
            let sub = b.subpat;
            if (sub != null) {
                pattern_informative_ty(ctx, body, sub)
            } else {
                null
            }
        },
        let c: root.ast.PatternClass => {
            let segments = c.class_;
            let head = ctx.lower.path_head(segments);
            if (root.hir_ty.scoped_type_param_heads(ctx, head, segments)) {
                return null;
            }
            let def = ctx.lower.resolve_type_definition(head, segments)
                ?? return null;
            let class_loc = match (def) {
                let d: root.hir.DefinitionClass => d.value,
                _ => {
                    return null;
                },
            };
            let short = segments.at(segments.length() - 1)
                ?? return null;
            let qtn = ctx.lower.qualify(def, short);
            let generic_count = root.hir.class_data(ctx.db, class_loc).generic_params.length();
            let written = ctx.type_refs.pattern_class_args.get(pat);
            let args = if (written != null) {
                written.map((type_ref) -> {
                    root.hir_ty.lower_body_annotation(ctx, type_ref)
                })
            } else {
                baml.Array.generate(generic_count, (i) -> {
                    ctx.table.new_var_ty()
                })
            };
            ctx.table.pool.add(root.types.InferTyClass { name: qtn, args: args })
        },
        let o: root.ast.PatternOr => {
            let informative: int? = null;
            for (let alt in o.value) {
                let ty = pattern_informative_ty(ctx, body, alt);
                if (ty != null) {
                    if (informative != null) {
                        return null;
                    }
                    informative = ty;
                }
            }
            informative
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::matrix_scrut @ d9be6853b
// The canonical scrutinee for pattern analysis: aliases expanded, unions
// canonical, so a `Role = "user" | "assistant"` alias scrutinee projects
// onto its members. Var and error scrutinees pass through (the oracle
// takes closed input; those matches sentinel out anyway).
function matrix_scrut(ctx: root.hir_ty.InferenceContext, ty: int) -> int throws never {
    let pool = ctx.table.pool;
    if (pool.has_error(ty) || pool.has_infer(ty)) {
        return ty;
    }
    root.types.normalize_interned(pool, root.types.ClosedTy { ty: ty }, ctx.facts).ty
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::narrowable_binding @ d9be6853b
// The scrutinee's binding, when it is a bare local that no closure captures
// (a captured binding is never narrowed: the lambda could observe a
// different value).
function narrowable_binding(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
) -> root.hir.BindingId? throws never {
    let segments = match (body.exprs[expr]) {
        let p: root.ast.ExprPath => p.value.segments,
        _ => {
            return null;
        },
    };
    if (segments.length() != 1) {
        return null;
    }
    let key = root.hir_ty.metadata_key(ctx, expr)
        ?? return null;
    match (ctx.index.path_resolution(key)) {
        let local: root.hir.PathResolutionLocal => {
            let binding = local.value;
            let bindings = ctx.index.scope_bindings.at(binding.scope);
            let captured = bindings != null && bindings.captured_bindings.has(binding);
            if (captured) {
                null
            } else {
                binding
            }
        },
        _ => null,
    }
}

// -- The per-shape lowering walk ----------------------------------------------

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_pattern @ d9be6853b
// (with `lower_pattern_reaching` folded in as the `reaching` default)
// Lowers one pattern against a resolved scrutinee type, recording binding
// types along the way. `reaching` is the part of the scrutinee that reaches
// the pattern (the scrutinee minus what earlier `match` arms consumed;
// the scrutinee itself when null): a pattern that writes no type of its own
// takes whatever reaches it, every other pattern is typed by what it
// writes, against `scrut`. Every pattern node records its type; ascriptions
// record the WRITTEN form while narrowing keeps the refined one.
function lower_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    scrut: int,
    reaching: int? = null,
) -> PatternOutcome throws never {
    let outcome = lower_pattern_inner(ctx, body, pat, scrut, reaching ?? scrut);
    ctx.result.type_of_pat.set(pat, outcome.recorded_ty ?? outcome.matched_ty);
    outcome
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_pattern_inner @ d9be6853b
function lower_pattern_inner(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    scrut: int,
    reaching: int,
) -> PatternOutcome throws never {
    let pool = ctx.table.pool;
    match (body.patterns[pat]) {
        // A pattern that writes no type matches what reaches it. Its matrix
        // row is still a wildcard over the whole column.
        root.ast.PatternWildcard => {
            PatternOutcome {
                dpat: root.hir_ty.DPat.wildcard(dpat_ty(pool, scrut)),
                matched_ty: reaching,
                recorded_ty: null,
                covers_type: true,
                consumes_matched: true,
            }
        },
        let b: root.ast.PatternBind => {
            let sub = b.subpat;
            let inner = if (sub != null) {
                lower_pattern(ctx, body, sub, scrut, reaching = reaching)
            } else {
                PatternOutcome {
                    dpat: root.hir_ty.DPat.wildcard(dpat_ty(pool, scrut)),
                    matched_ty: reaching,
                    recorded_ty: null,
                    covers_type: true,
                    consumes_matched: true,
                }
            };
            // Chain semantics: every bind in a chain takes the rightmost
            // type, the WRITTEN form when an ascription supplied one.
            ctx.result.type_of_pat.set(pat, inner.recorded_ty ?? inner.matched_ty);
            inner
        },
        root.ast.PatternType => {
            let type_ref = ctx.type_refs.pattern_types.get(pat);
            let pat_ty = if (type_ref != null) {
                root.hir_ty.lower_body_annotation(ctx, type_ref)
            } else {
                pool.add(root.types.TyError {})
            };
            type_pattern_outcome(ctx, pat, scrut, pat_ty)
        },
        let c: root.ast.PatternClass => {
            let fields = c.fields.map((field) -> {
                (field.field, field.pat)
            });
            lower_class_pattern(ctx, body, pat, c.class_, fields, scrut)
        },
        let a: root.ast.PatternArray => {
            lower_array_pattern(ctx, body, pat, a.prefix, a.rest, a.suffix, scrut)
        },
        let t: root.ast.PatternTuple => lower_tuple_pattern(ctx, body, pat, t.value, scrut),
        let o: root.ast.PatternOr => {
            let alts = o.value;
            // Every alternative is tried on the value that reached the
            // whole pattern.
            let outcomes = root.hir_ty.with_suppressed(ctx, root.hir_ty.Suppress.OrPattern, (this) -> {
                alts.map((alt) -> {
                    lower_pattern(this, body, alt, scrut, reaching = reaching)
                })
            });
            // The dead-pattern rule at the CHAIN level: one alternative that
            // can't match is just never taken, but a chain where no
            // alternative overlaps the scrutinee is dead outright.
            let whole = root.hir_ty.union_of(
                ctx,
                outcomes.map((outcome) -> {
                    outcome.recorded_ty ?? outcome.matched_ty
                }),
            );
            check_pattern_type_overlap(ctx, pat, scrut, whole);
            // Alternatives bind the SAME names (HIR enforces); their NARROW
            // types must agree.
            let first: map<string, int> = {};
            for (let alt in alts) {
                let binds: (string, int)[] = [];
                collect_bind_types(ctx, body, alt, binds);
                for (let bind in binds) {
                    let name = bind.0;
                    let ty = bind.1;
                    if (pool.has_error(ty) || pool.has_infer(ty)) {
                        continue;
                    }
                    let existing = first.get(name);
                    if (existing == null) {
                        first.set(name, ty);
                    } else if (existing != ty) {
                        root.hir_ty.report(
                            ctx,
                            root.hir_ty.PendingDiagOrBindingConflict {
                                pat: pat,
                                name: name,
                                first: existing,
                                other: ty,
                            },
                        );
                    }
                }
            }
            let matched = root.hir_ty.join(
                ctx,
                outcomes.map((outcome) -> {
                    outcome.matched_ty
                }),
            );
            PatternOutcome {
                covers_type: outcomes.some((outcome) -> {
                    outcome.covers_type
                }),
                consumes_matched: outcomes.every((outcome) -> {
                    outcome.consumes_matched
                }),
                dpat: root.hir_ty.DPat.or(
                    outcomes.map((outcome) -> {
                        outcome.dpat
                    }),
                    dpat_ty(pool, scrut),
                ),
                matched_ty: matched,
                recorded_ty: null,
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_interface_pattern @ d9be6853b
// A destructure pattern spelled with an INTERFACE name: the interface's
// declared FIELDS destructure like a class's, each typed through the same
// member instantiation field access uses (`member_on_interface`), the head
// being the existential view at the written args, else the args a
// same-interface scrutinee member carries.
function lower_interface_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    interface_: int,
    path: string[],
    field_pats: (string, int)[],
    scrut: int,
) -> PatternOutcome throws never {
    let pool = ctx.table.pool;
    let data = root.hir.interface_data(ctx.db, interface_);
    let short = path.at(path.length() - 1) ?? baml.sys.panic("type paths are never empty");
    let qtn = ctx.lower.qualify(root.hir.DefinitionInterface { value: interface_ }, short);

    let written_args = (ctx.type_refs.pattern_class_args.get(pat) ?? []).map((type_ref) -> {
        root.hir_ty.lower_body_annotation(ctx, type_ref)
    });
    let written_pins = (ctx.type_refs.pattern_assoc_bindings.get(pat) ?? []).map((binding) -> {
        (binding.0, root.hir_ty.lower_body_annotation(ctx, binding.1))
    });
    // Written positions win; anything unwritten ADOPTS from an
    // arg-compatible same-interface scrutinee member, while a written pin
    // constrains the head and types its fields. A written arg still carrying
    // a variable adopts nothing rather than materializing mid-inference.
    let existential_member = scrut_members(pool, scrut).find((member) -> {
        match (pool.kinds[member]) {
            let i: root.types.InferTyInterface => {
                i.name == qtn
                    && (
                        written_args.length() == 0
                            || written_args.length() == i.args.length()
                            && root.types.zip_all(written_args, i.args, (a, b) -> {
                                root.hir_ty.cached_equivalent(ctx, a, b)
                            })
                    )
            },
            _ => false,
        }
    });
    let existential: InterfaceInstantiation? = null;
    if (existential_member != null) {
        if let i: root.types.InferTyInterface = pool.kinds[existential_member] {
            existential
                = InterfaceInstantiation {
                    args: i.args,
                    pins: i.associated_types.map((pin) -> {
                        (pin.name, pin.ty)
                    }),
                };
        }
    }
    // Else the instantiation the scrutinee's implementors provide: the one
    // at which every member that implements the interface does so. Members
    // that implement it at different arguments leave them undetermined.
    let adopted = existential;
    if (adopted == null && written_args.length() == 0 && !pool.has_error(scrut)) {
        let associated = data.associated_types.map((assoc) -> {
            assoc.name
        });
        let provided: InterfaceInstantiation? = null;
        let disagree = false;
        for (let member in scrut_members(pool, scrut)) {
            let instantiation = implemented_instantiation(ctx, member, qtn, data.generic_params.length(), associated);
            if (instantiation == null) {
                continue;
            }
            if (provided == null) {
                provided = instantiation;
            } else if (provided != instantiation) {
                disagree = true;
                break;
            }
        }
        adopted
            = if (disagree) {
                null
            } else {
                provided
            };
    }
    // Nothing written and nothing to adopt: the interface's generics are
    // undetermined, and the pattern says so (E0002 at the pattern) unless
    // the scrutinee's own report already covers it.
    if (
        adopted == null
            && written_args.length() == 0
            && !pool.has_error(scrut)
            && !root.hir_ty.open_classes_owned(ctx, scrut)
    ) {
        for (let param in data.generic_params) {
            root.hir_ty.report(
                ctx,
                root.hir_ty.PendingDiagUninferredPatternTypeParam { pat: pat, name: param.name },
            );
        }
    }
    let base = adopted
        ?? InterfaceInstantiation {
            args: baml.Array.generate(data.generic_params.length(), (i) -> {
                pool.add(root.types.TyError {})
            }),
            pins: [],
        };
    let args = if (written_args.length() == 0) {
        base.args
    } else {
        written_args
    };
    let chosen_pins = if (written_pins.length() == 0) {
        base.pins
    } else {
        written_pins
    };
    // A copy: the declared associated types are pushed below.
    let pins = chosen_pins.concat([]);
    // The fields are read through this head, so every declared associated
    // type is pinned on it: one the written or adopted instantiation leaves
    // out is undetermined (reported, unless the scrutinee's own report
    // covers it) and takes the sentinel.
    for (let assoc in data.associated_types) {
        if (
            pins.some((pin) -> {
                pin.0 == assoc.name
            })
        ) {
            continue;
        }
        if (!pool.has_error(scrut) && !root.hir_ty.open_classes_owned(ctx, scrut)) {
            root.hir_ty.report(
                ctx,
                root.hir_ty.PendingDiagUninferredPatternAssociatedType {
                    pat: pat,
                    name: assoc.name,
                },
            );
        }
        pins.push((assoc.name, pool.add(root.types.TyError {})));
    }
    let to_pins = () -> root.types.InferAssociatedType[] {
        pins.map((pin) -> {
            root.types.InferAssociatedType { name: pin.0, ty: pin.1 }
        })
    };
    let head = pool.add(root.types.InferTyInterface { name: qtn, args: args, associated_types: to_pins() });
    // `infer_interface_new` sorts its pins in place: a fresh list, not the
    // head's.
    let target = root.types.infer_interface_new(qtn, args, to_pins());

    let declared = data.fields.map((field) -> {
        field.name
    });
    let field_covers = true;
    let sub_dpats: (root.hir_ty.DPat | null)[] = baml.Array.filled(declared.length(), null);
    for (let field_pat in field_pats) {
        let name = field_pat.0;
        let member = root.hir_ty.member_on_interface(ctx.db, ctx.facts, target, head, name, true);
        let field_ty = if (member != null && !member.is_method) {
            reduced_for_pattern(ctx, member.ty)
        } else {
            null
        };
        if (field_ty != null) {
            let index = declared.index_of(name);
            let outcome = lower_pattern(ctx, body, field_pat.1, field_ty);
            field_covers = field_covers && outcome.covers_type;
            if (index != null) {
                sub_dpats[index] = outcome.dpat;
            }
        } else {
            // Unknown field: sub-bindings still record (as Error).
            lower_pattern(ctx, body, field_pat.1, pool.add(root.types.TyError {}));
            field_covers = false;
        }
    }
    let fields = baml.Array.generate(declared.length(), (index) -> {
        let sub = sub_dpats[index];
        if (sub != null) {
            sub
        } else {
            let member = root.hir_ty.member_on_interface(ctx.db, ctx.facts, target, head, declared[index], true);
            let field_ty = if (member != null) {
                reduced_for_pattern(ctx, member.ty)
            } else {
                pool.add(root.types.TyError {})
            };
            root.hir_ty.DPat.wildcard(dpat_ty(pool, field_ty))
        }
    });
    let head_covers = root.hir_ty.provable_subtype(ctx, scrut, head);

    // The matrix's single-ctor STRUCT VIEW of an existential: field
    // sub-patterns decompose, so refutable field arms COMPOSE to coverage.
    let iface_dpat = root.hir_ty.DPat.interface_(dpat_ty(pool, head), fields, dpat_ty(pool, scrut));
    let dpat = match (pool.kinds[scrut]) {
        let u: root.types.InferTyUnion => {
            let claimed = u.members.filter((member) -> {
                match (pool.kinds[member]) {
                    let i: root.types.InferTyInterface => i.name == qtn,
                    _ => false,
                }
            });
            if (claimed.length() == 1) {
                root.hir_ty.DPat.union_member(
                    dpat_ty(pool, claimed[0]),
                    iface_dpat,
                    dpat_ty(pool, scrut),
                )
            } else {
                iface_dpat
            }
        },
        _ => iface_dpat,
    };
    PatternOutcome {
        dpat: dpat,
        // A head the scrutinee provably inhabits narrows nothing; the pattern
        // still records the interface it names.
        matched_ty: if (head_covers) {
            scrut
        } else {
            head
        },
        recorded_ty: head,
        covers_type: head_covers && field_covers,
        consumes_matched: field_covers,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::type_pattern_outcome @ d9be6853b
// A type pattern (`let x: T`, literals, enum variants, `null`) against the
// scrutinee. Union scrutinees project onto claimed members; claiming
// requires PROVABLE overlap in either direction.
function type_pattern_outcome(
    ctx: root.hir_ty.InferenceContext,
    pat: int,
    scrut: int,
    pat_ty: int,
) -> PatternOutcome throws never {
    let outcome = type_pattern_outcome_inner(ctx, scrut, pat_ty);
    // The recorded form is the WRITTEN annotation whenever it is not
    // error-carrying.
    if (!ctx.table.pool.has_error(pat_ty)) {
        outcome.recorded_ty = pat_ty;
    }
    if (!outcome.covers_type) {
        if (tuple_type_test_never_matches(ctx, scrut, pat_ty)) {
            // Quiet inside an or-pattern alternative and a rejected rest,
            // reported for a plain test, silent or not.
            if (
                !root.hir_ty.suppressed(ctx, root.hir_ty.Suppress.OrPattern)
                    && !root.hir_ty.suppressed(ctx, root.hir_ty.Suppress.RestReject)
            ) {
                root.hir_ty.report(
                    ctx,
                    root.hir_ty.PendingDiagTupleTypeTestNeverMatches {
                        pat: pat,
                        scrutinee: scrut,
                        tested: pat_ty,
                    },
                );
            }
        } else {
            check_pattern_type_overlap(ctx, pat, scrut, pat_ty);
        }
    }
    outcome
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::tuple_type_test_never_matches @ d9be6853b
function tuple_type_test_never_matches(
    ctx: root.hir_ty.InferenceContext,
    scrut: int,
    pat_ty: int,
) -> bool throws never {
    let pool = ctx.table.pool;
    if (!(pool.kinds[root.hir_ty.expand_alias_ty(ctx, pat_ty)] is root.types.InferTyTuple)) {
        return false;
    }
    let expanded = root.hir_ty.expand_alias_ty(ctx, scrut);
    let members = match (pool.kinds[expanded]) {
        let u: root.types.InferTyUnion => u.members,
        _ => [expanded],
    };
    members.some((member) -> {
        pool.kinds[root.hir_ty.expand_alias_ty(ctx, member)] is root.types.InferTyTuple
    })
        && provably_disjoint(ctx, scrut, pat_ty)
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::dead_pattern_is_quiet @ d9be6853b
// Whether the dead-pattern rule is quiet here: inside an or-pattern
// alternative, under a silent `is` test or in a rejected rest's subtree.
function dead_pattern_is_quiet(ctx: root.hir_ty.InferenceContext) -> bool throws never {
    root.hir_ty.suppressed(ctx, root.hir_ty.Suppress.OrPattern)
        || root.hir_ty.suppressed(ctx, root.hir_ty.Suppress.SilentTest)
        || root.hir_ty.suppressed(ctx, root.hir_ty.Suppress.RestReject)
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::check_pattern_type_overlap @ d9be6853b
// The dead-pattern rule: a pattern TYPE provably sharing no value with its
// scrutinee reports like any concrete mismatch.
function check_pattern_type_overlap(
    ctx: root.hir_ty.InferenceContext,
    pat: int,
    scrut: int,
    pat_ty: int,
) -> void throws never {
    if (dead_pattern_is_quiet(ctx)) {
        return;
    }
    if (provably_disjoint(ctx, scrut, pat_ty)) {
        root.hir_ty.report(
            ctx,
            root.hir_ty.PendingDiagPatternScrutMismatch { pat: pat, expected: scrut, found: pat_ty },
        );
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::provably_disjoint @ d9be6853b
// Whether a pattern of type `pat_ty` provably shares no value with a
// scrutinee of type `scrut`. An erroneous or still-open pair is undecidable
// here, so never provably disjoint.
function provably_disjoint(
    ctx: root.hir_ty.InferenceContext,
    scrut: int,
    pat_ty: int,
) -> bool throws never {
    let pool = ctx.table.pool;
    if (pool.has_error(pat_ty) || pool.has_error(scrut)) {
        return false;
    }
    if (pool.has_infer(pat_ty) || pool.has_infer(scrut)) {
        return false;
    }
    let pat_plain = pool.to_plain_closed(pat_ty);
    let scrut_plain = pool.to_plain_closed(scrut);
    // The overlap oracle's `No` rejects on every shape, trusted only when it
    // can see every variable.
    let vars = ctx.lower.generic_params;
    let oracle_no = root.types.all_typevars_within(pat_plain, vars)
        && root.types.all_typevars_within(scrut_plain, vars)
        && root.hir_ty.pattern_overlap_verdict(ctx, pat_plain, scrut_plain) == root.types.Overlap.No;
    // Ground pairs ADDITIONALLY take bidirectional-subtyping strictness,
    // against the whole scrutinee or any union member: two same-interface
    // existentials with differing pins share no value.
    let ground = !pool.has_typevar(pat_ty)
        && !pool.has_typevar(scrut)
        && !pool.has_projection(pat_ty)
        && !pool.has_projection(scrut);
    oracle_no
        || ground
        && !pattern_matchable(ctx, pat_plain, scrut_plain)
        && !pattern_overlaps_scrut_member(ctx, pat_plain, scrut_plain)
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_matchable @ d9be6853b
// Whether an arm with natural type `pat` is *plausible* against a
// scrutinee of type `scrut`. Container element positions recurse laxly; a
// bare interface head places no pin constraint; non-container pairs use
// bidirectional subtyping.
function pattern_matchable(
    ctx: root.hir_ty.InferenceContext,
    pat: root.types.Ty,
    scrut: root.types.Ty,
) -> bool throws never {
    let p = expand_alias_chain(ctx, pat);
    let s = expand_alias_chain(ctx, scrut);
    match (p, s) {
        (root.types.TyNever, _) => true,
        (let a: root.types.TyList, let b: root.types.TyList) => {
            pattern_matchable(ctx, a.elem, b.elem)
        },
        (let a: root.types.TyTuple, let b: root.types.TyTuple) => ctx.facts.equivalent(a, b),
        (let a: root.types.TyMap, let b: root.types.TyMap) => {
            pattern_matchable(ctx, a.key, b.key) && pattern_matchable(ctx, a.value, b.value)
        },
        (let a: root.types.TyInterface, let b: root.types.TyInterface)
            if a.name == b.name
            && a.associated_types.length() == 0
            && (
                a.args.length() == 0
                    || a.args.length() == b.args.length()
                    && root.types.zip_all(a.args, b.args, (x, y) -> {
                        ctx.facts.equivalent(x, y)
                    })
            ) => true,
        _ => ctx.facts.is_subtype(p, s) || ctx.facts.is_subtype(s, p),
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_overlaps_scrut_member @ d9be6853b
// A match arm is valid if its pattern overlaps ANY member of a union or
// optional scrutinee.
function pattern_overlaps_scrut_member(
    ctx: root.hir_ty.InferenceContext,
    pat: root.types.Ty,
    scrut: root.types.Ty,
) -> bool throws never {
    let members = flatten_union_members(ctx, scrut);
    members.length() > 1
        && members.some((member) -> {
            pattern_matchable(ctx, pat, member)
        })
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::flatten_union_members @ d9be6853b
function flatten_union_members(
    ctx: root.hir_ty.InferenceContext,
    ty: root.types.Ty,
) -> root.types.Ty[] throws never {
    match (expand_alias_chain(ctx, ty)) {
        let u: root.types.TyUnion => {
            u.members.flat_map((member) -> {
                flatten_union_members(ctx, member)
            })
        },
        let other: root.types.Ty => [other],
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::expand_alias_chain @ d9be6853b
// Follow a top-level alias chain to its target (bounded; a cyclic or
// unknown alias stays as written).
function expand_alias_chain(
    ctx: root.hir_ty.InferenceContext,
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
        current
            = ctx.facts.alias_def(alias.name)
                ?? return current;
    }
    current
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::type_pattern_outcome_inner @ d9be6853b
function type_pattern_outcome_inner(
    ctx: root.hir_ty.InferenceContext,
    scrut: int,
    pat_ty: int,
) -> PatternOutcome throws never {
    let pool = ctx.table.pool;
    if (pool.has_error(pat_ty)) {
        // Fail-safe for coverage, but the error stays LOCAL: the written
        // type is the matched type (`map<!error, int>` keeps its shape).
        return PatternOutcome {
            dpat: root.hir_ty.DPat.wildcard(dpat_ty(pool, scrut)),
            matched_ty: pat_ty,
            recorded_ty: null,
            covers_type: false,
            consumes_matched: false,
        };
    }
    let covers = root.hir_ty.provable_subtype(ctx, scrut, pat_ty);
    let union_members = match (pool.kinds[scrut]) {
        let u: root.types.InferTyUnion => u.members,
        _ => null,
    };
    if (union_members != null && !covers) {
        let claimed = union_members.filter((member) -> {
            root.hir_ty.provable_subtype(ctx, member, pat_ty)
                || root.hir_ty.provable_subtype(ctx, pat_ty, member)
        });
        if (claimed.length() > 0) {
            let scrut_plain = dpat_ty(pool, scrut);
            let alts = claimed.map((member) -> {
                let inner = if (root.hir_ty.provable_subtype(ctx, member, pat_ty)) {
                    root.hir_ty.DPat.wildcard(dpat_ty(pool, member))
                } else {
                    dpat_for_type(ctx, pat_ty, member)
                };
                root.hir_ty.DPat.union_member(dpat_ty(pool, member), inner, scrut_plain)
            });
            let dpat = if (alts.length() == 1) {
                alts[0]
            } else {
                root.hir_ty.DPat.or(alts, scrut_plain)
            };
            let matched = root.hir_ty.union_of(ctx, claimed);
            return PatternOutcome {
                dpat: dpat,
                matched_ty: narrow_to(ctx, matched, pat_ty),
                recorded_ty: null,
                covers_type: false,
                consumes_matched: true,
            };
        }
        // Nothing provably claimed: possible-but-not-covering.
        return PatternOutcome {
            dpat: root.hir_ty.DPat.type_test(dpat_ty(pool, pat_ty), dpat_ty(pool, scrut)),
            matched_ty: pat_ty,
            recorded_ty: null,
            covers_type: false,
            consumes_matched: true,
        };
    }
    PatternOutcome {
        dpat: dpat_for_type(ctx, pat_ty, scrut),
        matched_ty: if (covers) {
            scrut
        } else {
            narrow_to(ctx, scrut, pat_ty)
        },
        recorded_ty: null,
        covers_type: covers,
        consumes_matched: true,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::narrow_to @ d9be6853b
// The refined scrutinee type after a successful type test, the meet
// approximated: a scrutinee already inside the pattern stays; otherwise the
// pattern type stands.
function narrow_to(ctx: root.hir_ty.InferenceContext, scrut: int, pat_ty: int) -> int throws never {
    if (root.hir_ty.provable_subtype(ctx, scrut, pat_ty)) {
        scrut
    } else {
        pat_ty
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::dpat_for_type @ d9be6853b
// The coverage-side lowering of a type pattern: singletons, finite
// alphabets, classes, rigid vars, and the subtype fallback. Deliberately
// stricter than arm validity.
function dpat_for_type(
    ctx: root.hir_ty.InferenceContext,
    pat_ty: int,
    col: int,
) -> root.hir_ty.DPat throws never {
    let pool = ctx.table.pool;
    let col_plain = dpat_ty(pool, col);
    let pat_plain = dpat_ty(pool, pat_ty);
    // The universal coverage rule first: a pattern the whole column provably
    // fits is a wildcard at this column, whatever its shape.
    if (root.hir_ty.provable_subtype(ctx, col, pat_ty)) {
        return root.hir_ty.DPat.wildcard(col_plain);
    }
    match (pool.kinds[pat_ty]) {
        root.types.TyLiteral | root.types.TyEnumVariant | root.types.TyNull => {
            root.hir_ty.DPat.type_test(pat_plain, col_plain)
        },
        root.types.TyBool => {
            root.hir_ty.DPat.or(
                [true, false].map((value) -> {
                    root.hir_ty.DPat.type_test(
                        root.types.TyLiteral {
                            value: root.base.LiteralBool { value: value },
                            freshness: root.types.Freshness.Regular,
                        },
                        col_plain,
                    )
                }),
                col_plain,
            )
        },
        let e: root.types.TyEnum => {
            root.hir_ty.DPat.or(
                (ctx.facts.enum_variants(e.name) ?? []).map((variant) -> {
                    root.hir_ty.DPat.type_test(
                        root.types.TyEnumVariant { name: e.name, variant: variant },
                        col_plain,
                    )
                }),
                col_plain,
            )
        },
        let u: root.types.InferTyUnion => {
            root.hir_ty.DPat.or(
                u.members.map((member) -> {
                    dpat_for_type(ctx, member, col)
                }),
                col_plain,
            )
        },
        let c: root.types.InferTyClass => {
            let fields = class_pattern_field_types(ctx, c.name, c.args);
            root.hir_ty.DPat.class_inst(
                c.name,
                c.args.map((arg) -> {
                    dpat_ty(pool, arg)
                }),
                fields.map((field_ty) -> {
                    root.hir_ty.DPat.wildcard(dpat_ty(pool, field_ty))
                }),
                pat_plain,
            )
        },
        root.types.InferTyTuple => root.hir_ty.DPat.type_test(pat_plain, col_plain),
        // Rigid: covers only a column of the SAME variable; otherwise
        // possible-but-not-covering (never a blanket claim).
        root.types.TyTypeVar => {
            if (pat_ty == col) {
                root.hir_ty.DPat.wildcard(col_plain)
            } else {
                root.hir_ty.DPat.type_test(pat_plain, col_plain)
            }
        },
        _ => {
            if (root.hir_ty.provable_subtype(ctx, col, pat_ty)) {
                root.hir_ty.DPat.wildcard(col_plain)
            } else {
                root.hir_ty.DPat.type_test(pat_plain, col_plain)
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_class_pattern @ d9be6853b
// Class destructure. Generic args: written args win; otherwise ADOPTED
// from the scrutinee when exactly one same-class member determines them; a
// generic class with neither is Error.
function lower_class_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    class_path: string[],
    field_pats: (string, int)[],
    scrut: int,
) -> PatternOutcome throws never {
    let pool = ctx.table.pool;
    let error = pool.add(root.types.TyError {});
    // Under an ERRORED scrutinee the whole destructure is tainted: fields
    // lower against the sentinel and nothing reports.
    if (pool.has_error(scrut)) {
        for (let field_pat in field_pats) {
            lower_pattern(ctx, body, field_pat.1, error);
        }
        return PatternOutcome {
            dpat: root.hir_ty.DPat.wildcard(dpat_ty(pool, scrut)),
            matched_ty: error,
            recorded_ty: null,
            covers_type: false,
            consumes_matched: false,
        };
    }
    // A type parameter or scoped `type` binding at the head shadows every
    // item: no class is named.
    let head = ctx.lower.path_head(class_path);
    let definition = if (root.hir_ty.scoped_type_param_heads(ctx, head, class_path)) {
        null
    } else {
        ctx.lower.resolve_type_definition(head, class_path)
    };
    // Destructure spelled with an INTERFACE name: the existential's declared
    // FIELDS destructure like a class's.
    let class_ = match (definition) {
        let d: root.hir.DefinitionInterface => {
            return lower_interface_pattern(ctx, body, pat, d.value, class_path, field_pats, scrut);
        },
        let d: root.hir.DefinitionClass => d.value,
        _ => {
            // The destructured name resolves nowhere (or to a non-class):
            // E0002 at the pattern; fields lower against the sentinel.
            if (definition == null) {
                root.hir_ty.report(
                    ctx,
                    root.hir_ty.PendingDiagUnresolvedPatternName {
                        pat: pat,
                        name: class_path.join("."),
                        suggestions: ctx.lower.type_suggestions(class_path),
                    },
                );
            }
            for (let field_pat in field_pats) {
                lower_pattern(ctx, body, field_pat.1, error);
            }
            return PatternOutcome {
                dpat: root.hir_ty.DPat.wildcard(dpat_ty(pool, scrut)),
                matched_ty: error,
                recorded_ty: null,
                covers_type: false,
                consumes_matched: false,
            };
        },
    };
    let qtn = root.hir_ty.class_qualified_name(ctx.db, class_);
    let generic_count = root.hir_ty.class_generic_frame(ctx.db, class_).length();
    // A generic class destructure must WRITE its type arguments.
    if (generic_count > 0 && !ctx.type_refs.pattern_class_args.has(pat)) {
        root.hir_ty.report(
            ctx,
            root.hir_ty.PendingDiagGenericDestructureNoArgs { pat: pat, class_name: qtn.name },
        );
    }

    let written = (ctx.type_refs.pattern_class_args.get(pat) ?? []).map((type_ref) -> {
        root.hir_ty.lower_body_annotation(ctx, type_ref)
    });
    let args = if (written.length() > 0 || generic_count == 0) {
        written
    } else {
        // Adoption: same-class scrutinee members that pin the args.
        let candidates = scrut_members(pool, scrut).filter((member) -> {
            match (pool.kinds[member]) {
                let c: root.types.InferTyClass => c.name == qtn,
                _ => false,
            }
        });
        let only = if (candidates.length() == 1) {
            pool.kinds[candidates[0]]
        } else {
            null
        };
        match (only) {
            let c: root.types.InferTyClass => c.args,
            // None or ambiguous: Error args.
            _ => {
                baml.Array.generate(generic_count, (i) -> {
                    error
                })
            },
        }
    };

    let head_ty = root.hir_ty.class_ty_interned(pool, root.hir_ty.infer_ctx_lang(ctx), qtn, args);
    let declared: (string, root.types.Ty)[] = if (root.hir_ty.is_opaque_trace_type(ctx, qtn)) {
        []
    } else {
        root.hir_ty.class_field_types(ctx.db, class_)
    };
    let field_covers = true;
    let sub_dpats: (root.hir_ty.DPat | null)[] = baml.Array.filled(declared.length(), null);
    for (let field_pat in field_pats) {
        let name = field_pat.0;
        let index = declared.find_index((field) -> {
            field.0 == name
        });
        if (index != null) {
            let field_ty = pattern_field_ty(ctx, pool.from_plain(declared[index].1), args);
            let outcome = lower_pattern(ctx, body, field_pat.1, field_ty);
            field_covers = field_covers && outcome.covers_type;
            sub_dpats[index] = outcome.dpat;
        } else {
            // Unknown field (E0007); sub-bindings still record (as Error).
            root.hir_ty.report(
                ctx,
                root.hir_ty.PendingDiagUnknownPatternField {
                    pat: pat,
                    class_name: qtn,
                    field_name: name,
                    declared: declared.map((field) -> {
                        field.0
                    }),
                },
            );
            lower_pattern(ctx, body, field_pat.1, error);
        }
    }
    let fields = baml.Array.generate(declared.length(), (index) -> {
        let sub = sub_dpats[index];
        if (sub != null) {
            sub
        } else {
            root.hir_ty.DPat.wildcard(
                dpat_ty(pool, pattern_field_ty(ctx, pool.from_plain(declared[index].1), args)),
            )
        }
    });
    let head_covers = root.hir_ty.provable_subtype(ctx, scrut, head_ty);

    // Union scrutinee: claim the same-class member with an agreeing
    // instantiation, so per-instantiation arms compose to full coverage.
    // Without written or adopted args the name alone decides.
    let class_dpat = root.hir_ty.DPat.class_inst(
        qtn,
        args.map((arg) -> {
            dpat_ty(pool, arg)
        }),
        fields,
        dpat_ty(pool, head_ty),
    );
    let dpat = match (pool.kinds[scrut]) {
        let u: root.types.InferTyUnion => {
            let claimed = u.members.filter((member) -> {
                match (pool.kinds[member]) {
                    let c: root.types.InferTyClass => {
                        c.name == qtn
                            && (
                                args.length() == 0
                                    || c.args.length() == args.length()
                                    && root.types.zip_all(c.args, args, (member_arg, arg) -> {
                                        root.hir_ty.eq_admitted(pool, member_arg, arg, ctx.facts)
                                    })
                            )
                    },
                    _ => false,
                }
            });
            if (claimed.length() == 1) {
                root.hir_ty.DPat.union_member(
                    dpat_ty(pool, claimed[0]),
                    class_dpat,
                    dpat_ty(pool, scrut),
                )
            } else {
                class_dpat
            }
        },
        _ => class_dpat,
    };
    PatternOutcome {
        dpat: dpat,
        matched_ty: if (head_covers) {
            scrut
        } else {
            head_ty
        },
        recorded_ty: null,
        covers_type: head_covers && field_covers,
        // The head is fully consumed only when every field sub-pattern is
        // irrefutable for its field type.
        consumes_matched: field_covers,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_tuple_pattern @ d9be6853b
// Tuple destructuring tests shape and slot values, preserving every
// possible carried instantiation. Open holders may contain tuples of any
// slot types; their bindings start at `unknown`.
function lower_tuple_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    elements: int[],
    scrut: int,
) -> PatternOutcome throws never {
    let pool = ctx.table.pool;
    let arity = elements.length();
    let structure = root.hir_ty.structurally_resolve(ctx, scrut);
    let tuple_slots = (ty: int) -> int[]? {
        match (pool.kinds[ty]) {
            let t: root.types.InferTyTuple if t.items.length() == arity => t.items,
            // The bottom type is every tuple: the pattern covers it and
            // binds nothing that exists.
            root.types.TyNever => baml.Array.filled(arity, pool.add(root.types.TyNever {})),
            _ => {
                if (tuple_pattern_is_open(pool, ty)) {
                    baml.Array.filled(arity, pool.add(root.types.TyUnknown {}))
                } else {
                    null
                }
            },
        }
    };
    let slots = tuple_slots(structure);
    if (slots != null) {
        let outcome = lower_tuple_elements(ctx, body, elements, slots, structure);
        if (tuple_pattern_is_open(pool, structure)) {
            // Even irrefutable slot patterns do not consume an open holder:
            // it can also contain non-tuples or other arities.
            outcome.covers_type = false;
            outcome.consumes_matched = false;
        }
        return outcome;
    }
    let union_members: int[] = match (pool.kinds[structure]) {
        let u: root.types.InferTyUnion => u.members,
        _ => [],
    };
    let members = union_members.map((member) -> {
        root.hir_ty.structurally_resolve(ctx, member)
    });
    let claimed: (int, int[])[] = [];
    for (let member in members) {
        let member_slots = tuple_slots(member);
        if (member_slots != null && pattern_fits(ctx, body, pat, member)) {
            claimed.push((member, member_slots));
        }
    }
    if (claimed.length() > 0) {
        let scrut_plain = dpat_ty(pool, scrut);
        let alts: root.hir_ty.DPat[] = [];
        let matched: int[] = [];
        let consumes = true;
        let single = claimed.length() == 1;
        for (let claim in claimed) {
            let outcome = if (single) {
                lower_tuple_elements(ctx, body, elements, claim.1, claim.0)
            } else {
                root.hir_ty.with_suppressed(ctx, root.hir_ty.Suppress.OrPattern, (this) -> {
                    lower_tuple_elements(this, body, elements, claim.1, claim.0)
                })
            };
            consumes = consumes && outcome.consumes_matched && !tuple_pattern_is_open(pool, claim.0);
            matched.push(outcome.matched_ty);
            alts.push(
                root.hir_ty.DPat.union_member(dpat_ty(pool, claim.0), outcome.dpat, scrut_plain),
            );
        }
        if (!single) {
            let joined = baml.Array.generate(arity, (i) -> {
                root.hir_ty.union_of(
                    ctx,
                    claimed.map((claim) -> {
                        claim.1[i]
                    }),
                )
            });
            let joined_ty = pool.add(root.types.InferTyTuple { items: joined });
            lower_tuple_elements(ctx, body, elements, joined, joined_ty);
        }
        let dpat = if (single) {
            alts[0]
        } else {
            root.hir_ty.DPat.or(alts, scrut_plain)
        };
        return PatternOutcome {
            dpat: dpat,
            matched_ty: root.hir_ty.union_of(ctx, matched),
            recorded_ty: null,
            covers_type: false,
            consumes_matched: consumes,
        };
    }
    let error = pool.add(root.types.TyError {});
    let error_slots = baml.Array.filled(arity, error);
    root.hir_ty.with_suppressed(ctx, root.hir_ty.Suppress.OrPattern, (this) -> {
        lower_tuple_elements(this, body, elements, error_slots, error);
    });
    if (!dead_pattern_is_quiet(ctx) && !pool.has_error(structure) && !pool.has_infer(structure)) {
        root.hir_ty.report(
            ctx,
            root.hir_ty.PendingDiagPatternScrutMismatch {
                pat: pat,
                expected: scrut,
                found: pool.add(
                    root.types.InferTyTuple {
                        items: baml.Array.filled(arity, pool.add(root.types.TyUnknown {})),
                    },
                ),
            },
        );
    }
    PatternOutcome {
        dpat: root.hir_ty.DPat.wildcard(dpat_ty(pool, scrut)),
        matched_ty: error,
        recorded_ty: null,
        covers_type: false,
        consumes_matched: false,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_tuple_elements @ d9be6853b
function lower_tuple_elements(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    elements: int[],
    slots: int[],
    tuple_ty: int,
) -> PatternOutcome throws never {
    let count = if (elements.length() < slots.length()) {
        elements.length()
    } else {
        slots.length()
    };
    let outcomes = baml.Array.generate(count, (i) -> {
        lower_pattern(ctx, body, elements[i], slots[i])
    });
    let covers = outcomes.every((outcome) -> {
        outcome.covers_type
    });
    PatternOutcome {
        dpat: root.hir_ty.DPat.tuple(
            outcomes.map((outcome) -> {
                outcome.dpat
            }),
            dpat_ty(ctx.table.pool, tuple_ty),
        ),
        matched_ty: tuple_ty,
        recorded_ty: null,
        covers_type: covers,
        consumes_matched: covers,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::lower_array_pattern @ d9be6853b
function lower_array_pattern(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    prefix: int[],
    rest: root.ast.ArrayRestPat?,
    suffix: int[],
    scrut: int,
) -> PatternOutcome throws never {
    let pool = ctx.table.pool;
    let ascription_ref = ctx.type_refs.array_ascriptions.get(pat);
    let ascribed = if (ascription_ref != null) {
        root.hir_ty.lower_body_annotation(ctx, ascription_ref)
    } else {
        null
    };
    let narrowed = if (ascribed != null && !pool.has_error(ascribed)) {
        // A written ascription that provably shares no value with the
        // scrutinee is the same dead-pattern mismatch a type pattern gets.
        check_pattern_type_overlap(ctx, pat, scrut, ascribed);
        narrow_to(ctx, scrut, ascribed)
    } else {
        scrut
    };
    // The element extraction below is a STRUCTURE demand, so an ascription
    // naming a weak alias (or a reducible projection, or a bounded var)
    // answers as its structure.
    let effective = root.hir_ty.structurally_resolve(ctx, narrowed);
    // The lists the pattern can match are the list-holding members of the
    // scrutinee: a list type holds lists of its own element, and a member
    // whose values may be lists of ANY element holds lists no one list type
    // describes. Among several holders the pattern claims the ones its own
    // demands fit ("cannot tell" keeps the member). A pattern no holder
    // fits is dead.
    let scrut_structure = root.hir_ty.structurally_resolve(ctx, scrut);
    let erroneous = pool.has_error(effective);
    let holders: (int, ListHolding)[] = [];
    let scrutinee_is_lists = !erroneous;
    for (let member in scrut_members(pool, effective)) {
        // Every member is visited (Rust's non-short-circuit `&=`).
        let only_lists = collect_list_holders(ctx, member, [], holders);
        scrutinee_is_lists = scrutinee_is_lists && only_lists;
    }
    let holder_count = holders.length();
    let claimed = if (holders.length() > 1) {
        let fitting: (int, ListHolding)[] = [];
        for (let holder in holders) {
            let fits = match (holder.1) {
                ListHoldingElements => pattern_fits(ctx, body, pat, holder.0),
                ListHoldingAnyElements => true,
            };
            if (fits) {
                fitting.push(holder);
            }
        }
        if (fitting.length() == 0) {
            holders
        } else {
            fitting
        }
    } else {
        holders
    };
    let element = if (erroneous) {
        // The scrutinee's own error was reported; its elements are that
        // error too, never a type of their own.
        pool.add(root.types.TyError {})
    } else if (claimed.length() == 0) {
        // A scrutinee that holds no list: the pattern is dead. Reported
        // where a type pattern's dead arm is (not from a silent probe, not
        // against `never`, not after a written ascription's report); then
        // the elements are the sentinel, else what a dead binding holds,
        // nothing.
        let reported = ascribed == null
            && !dead_pattern_is_quiet(ctx)
            && !(pool.kinds[effective] is root.types.TyNever);
        if (reported) {
            root.hir_ty.report(
                ctx,
                root.hir_ty.PendingDiagListPatternNeverMatches { pat: pat, scrutinee: scrut },
            );
            pool.add(root.types.TyError {})
        } else {
            pool.add(root.types.TyNever {})
        }
    } else if (
        claimed.some((holder) -> {
            holder.1 is ListHoldingAnyElements
        })
    ) {
        pool.add(root.types.TyUnknown {})
    } else {
        root.hir_ty.union_of(
            ctx,
            claimed.filter_map((holder) -> {
                match (holder.1) {
                    let e: ListHoldingElements => e.value,
                    ListHoldingAnyElements => null,
                }
            }),
        )
    };
    // What the pattern matches, the claimed holders, is what its test
    // decides at run time.
    let matched_ty = if (claimed.length() == 0) {
        effective
    } else {
        root.hir_ty.union_of(
            ctx,
            claimed.map((holder) -> {
                holder.0
            }),
        )
    };
    let claims_only_lists = claimed.length() > 0
        && claimed.every((holder) -> {
            holder.1 is ListHoldingElements
        });
    let sub_dpats: root.hir_ty.DPat[] = [];
    for (let sub in prefix) {
        sub_dpats.push(lower_pattern(ctx, body, sub, element).dpat);
    }
    if let rest_pat: int = rest?.pat {
        // The rest slot carries a BINDING (optionally ascribed) or the
        // wildcard. Structural sub-patterns have no sliced-middle semantics.
        let shape_ok = rest_pattern_shape_ok(body, rest_pat);
        if (!shape_ok && !root.hir_ty.suppressed(ctx, root.hir_ty.Suppress.RestReject)) {
            root.hir_ty.report(ctx, root.hir_ty.PendingDiagRestNotBinding { pat: rest_pat });
        }
        // The rest binds the sliced middle: a list of the element. A
        // rejected subtree still lowers so its bindings record, but reports
        // inside it are suppressed.
        let rest_ty = pool.add(root.types.InferTyList { elem: element });
        if (shape_ok) {
            lower_pattern(ctx, body, rest_pat, rest_ty);
        } else {
            root.hir_ty.with_suppressed(ctx, root.hir_ty.Suppress.RestReject, (this) -> {
                lower_pattern(this, body, rest_pat, rest_ty)
            });
        }
    }
    for (let sub in suffix) {
        sub_dpats.push(lower_pattern(ctx, body, sub, element).dpat);
    }
    let shape: root.hir_ty.SliceShape = if (rest != null) {
        root.hir_ty.SliceShapeVariable { prefix: prefix.length(), suffix: suffix.length() }
    } else {
        root.hir_ty.SliceShapeFixed { value: prefix.length() + suffix.length() }
    };
    let covers = rest != null && prefix.length() == 0 && suffix.length() == 0;
    // A union column takes the claimed members as its branches, one
    // `UnionMember` each; any other column (or a claim not made of the
    // column's own members) takes the slice directly.
    let slice_dpat = (ty: int) -> root.hir_ty.DPat {
        root.hir_ty.DPat.slice(shape, sub_dpats, dpat_ty(pool, ty))
    };
    let dpat = match (pool.kinds[scrut_structure]) {
        let u: root.types.InferTyUnion
            if claimed.length() > 0
            && claimed.every((holder) -> {
                u.members.includes(holder.0)
            }) => {
            let branches = claimed.map((holder) -> {
                root.hir_ty.DPat.union_member(
                    dpat_ty(pool, holder.0),
                    slice_dpat(holder.0),
                    dpat_ty(pool, scrut),
                )
            });
            if (branches.length() == 1) {
                branches[0]
            } else {
                root.hir_ty.DPat.or(branches, dpat_ty(pool, scrut))
            }
        },
        _ => slice_dpat(matched_ty),
    };
    PatternOutcome {
        dpat: dpat,
        matched_ty: matched_ty,
        recorded_ty: null,
        // `[..]` accepts every value of a type made of lists only, and every
        // value of the claimed list types; a member that may hold something
        // other than a list is never wholly accepted.
        covers_type: covers && ascribed == null && scrutinee_is_lists && claimed.length() == holder_count,
        consumes_matched: covers && claims_only_lists,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::collect_list_holders @ d9be6853b
// Appends the list-holding members `ty` unfolds to, through unions and
// recursive aliases; returns whether every member is a list type. An alias
// met again on its own unfolding is an unguarded recursive member, which
// contributes nothing to its type.
function collect_list_holders(
    ctx: root.hir_ty.InferenceContext,
    ty: int,
    unfolding: int[],
    holders: (int, ListHolding)[],
) -> bool throws never {
    let pool = ctx.table.pool;
    if (pool.kinds[ty] is root.types.TyTypeAlias) {
        if (unfolding.includes(ty)) {
            return true;
        }
        let expanded = root.hir_ty.expand_alias_ty(ctx, ty);
        if (expanded != ty) {
            unfolding.push(ty);
            let only_lists = collect_list_holders(ctx, expanded, unfolding, holders);
            unfolding.pop();
            return only_lists;
        }
    }
    if let u: root.types.InferTyUnion = pool.kinds[ty] {
        // Every member is visited: a non-list member must not hide the
        // lists after it.
        let only_lists = true;
        for (let member in u.members) {
            let member_lists = collect_list_holders(ctx, member, unfolding, holders);
            only_lists = only_lists && member_lists;
        }
        return only_lists;
    }
    let holding = list_holding(pool, ty)
        ?? return false;
    if (
        !holders.some((holder) -> {
            holder.0 == ty
        })
    ) {
        holders.push((ty, holding));
    }
    holding is ListHoldingElements
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_fits @ d9be6853b
// Whether `pat` can fit a value of `ty`: false only on a PROVABLE misfit
// (an ascription with no overlap either way, a structural demand the
// type's kind cannot meet). Conservative: "cannot tell" answers true, and
// the caller claims only on a unique fit.
function pattern_fits(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    ty: int,
) -> bool throws never {
    let pool = ctx.table.pool;
    let expanded = root.hir_ty.expand_alias_ty(ctx, ty);
    // A type whose values may be of any shape, or of any of several, is
    // never a provable misfit as a whole.
    match (pool.kinds[expanded]) {
        root.types.TyUnknown
            | root.types.TyTypeVar
            | root.types.InferTyAssociatedTypeProjection
            | root.types.TyInferVar
            | root.types.TyError =>
        {
            return true;
        },
        let u: root.types.InferTyUnion => {
            return u.members.some((member) -> {
                pattern_fits(ctx, body, pat, member)
            });
        },
        _ => {},
    }
    match (body.patterns[pat]) {
        root.ast.PatternWildcard => true,
        let b: root.ast.PatternBind => {
            let sub = b.subpat
                ?? return true;
            let ascribed = root.hir_ty.pattern_ascription_ty(ctx, body, sub);
            if (ascribed != null) {
                return !provably_disjoint(ctx, expanded, ascribed);
            }
            pattern_fits(ctx, body, sub, expanded)
        },
        let a: root.ast.PatternArray => {
            let element = match (list_holding(pool, expanded)) {
                let e: ListHoldingElements => e.value,
                // Lists of any element may be among its values: cannot tell.
                ListHoldingAnyElements => {
                    return true;
                },
                null => {
                    return false;
                },
            };
            let type_ref = ctx.type_refs.array_ascriptions.get(pat);
            if (type_ref != null) {
                let ascribed = root.hir_ty.lower_body_annotation(ctx, type_ref);
                if (provably_disjoint(ctx, expanded, ascribed)) {
                    return false;
                }
            }
            let rest_pat = a.rest?.pat;
            a.prefix.concat(a.suffix).every((sub) -> {
                pattern_fits(ctx, body, sub, element)
            })
                && (
                    rest_pat == null
                        || pattern_fits(ctx, body, rest_pat, pool.add(root.types.InferTyList { elem: element }))
                )
        },
        let c: root.ast.PatternClass => class_head_fits(ctx, c.class_, expanded),
        let t: root.ast.PatternTuple => {
            match (pool.kinds[expanded]) {
                let tuple: root.types.InferTyTuple if tuple.items.length() == t.value.length() => {
                    root.types.zip_all(t.value, tuple.items, (sub, element_ty) -> {
                        tuple_element_fits(ctx, body, sub, element_ty)
                    })
                },
                root.types.TyUnknown | root.types.TyTypeVar => true,
                _ => false,
            }
        },
        // Type patterns carry their own runtime test; the lowering settles
        // their claim.
        root.ast.PatternType => true,
        let o: root.ast.PatternOr => {
            o.value.some((alternative) -> {
                pattern_fits(ctx, body, alternative, expanded)
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::tuple_element_fits @ d9be6853b
function tuple_element_fits(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    sub: int,
    slot: int,
) -> bool throws never {
    match (body.patterns[sub]) {
        root.ast.PatternType => {
            let tested = root.hir_ty.pattern_ascription_ty(ctx, body, sub);
            if (tested != null) {
                !provably_disjoint(ctx, slot, tested)
            } else {
                true
            }
        },
        let o: root.ast.PatternOr => {
            o.value.some((alternative) -> {
                tuple_element_fits(ctx, body, alternative, slot)
            })
        },
        _ => pattern_fits(ctx, body, sub, slot),
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::class_head_fits @ d9be6853b
// Whether a destructure spelled with `class_path` can fit a value of `ty`
// (neither a union nor a type that may hold any shape): a class head
// demands that class by identity; an interface head demands an implementor,
// which an existential may be and any other type is unless no
// implementation of the interface is visible from it. A head that resolves
// to nothing fits: the lowering reports it.
function class_head_fits(
    ctx: root.hir_ty.InferenceContext,
    class_path: string[],
    ty: int,
) -> bool throws never {
    let pool = ctx.table.pool;
    let head = ctx.lower.path_head(class_path);
    let definition = if (root.hir_ty.scoped_type_param_heads(ctx, head, class_path)) {
        null
    } else {
        ctx.lower.resolve_type_definition(head, class_path)
    };
    match (definition) {
        let d: root.hir.DefinitionClass => {
            match (pool.kinds[ty]) {
                let c: root.types.InferTyClass => {
                    c.name == root.hir_ty.class_qualified_name(ctx.db, d.value)
                },
                _ => false,
            }
        },
        let d: root.hir.DefinitionInterface => {
            if (pool.kinds[ty] is root.types.InferTyInterface) {
                return true;
            }
            let short = class_path.at(class_path.length() - 1) ?? baml.sys.panic("type paths are never empty");
            let qtn = ctx.lower.qualify(d, short);
            root.hir_ty.structural_interface(ctx.db, qtn) != null
                || root.hir_ty.impl_candidates(ctx.db, ty, qtn).length() > 0
        },
        _ => true,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::class_pattern_field_types @ d9be6853b
// A class's field types at a pattern's class arguments, in declaration
// order: a source class's, else a served package's row's.
function class_pattern_field_types(
    ctx: root.hir_ty.InferenceContext,
    qtn: root.types.DeclName,
    args: int[],
) -> int[] throws never {
    let pool = ctx.table.pool;
    match (root.hir_ty.definition_of(ctx.db, qtn)) {
        let d: root.hir.DefinitionClass => {
            root.hir_ty.class_field_types(ctx.db, d.value).map((field) -> {
                pattern_field_ty(ctx, pool.from_plain(field.1), args)
            })
        },
        _ => {
            let class_ = root.hir_ty.mounted_class_loc(ctx.db, qtn)
                ?? return [];
            root.hir_ty.extern_class_row(ctx.db, class_).fields.map((field) -> {
                pattern_field_ty(ctx, pool.from_plain(field.1), args)
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::pattern_field_ty @ d9be6853b
// A declared field's type at a pattern's class arguments, as the
// sub-pattern judges it: a projection the arguments make ground is reduced
// (`T.Out` at `T = IntOut` IS `int`).
function pattern_field_ty(
    ctx: root.hir_ty.InferenceContext,
    declared: int,
    args: int[],
) -> int throws never {
    reduced_for_pattern(ctx, root.hir_ty.substitute_params(ctx.table.pool, declared, args))
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::InferenceContext::reduced_for_pattern @ d9be6853b
// `ty` with its ground projections reduced; one still waiting on an
// inference variable stays, as it does in every relation.
function reduced_for_pattern(ctx: root.hir_ty.InferenceContext, ty: int) -> int throws never {
    let pool = ctx.table.pool;
    if (pool.has_infer(ty) || !pool.has_projection(ty)) {
        return ty;
    }
    root.hir_ty
        .reduce_projections(
            ctx,
            root.types.ClosedTy { ty: ty },
            root.hir_ty.PROJECTION_FINALIZE_FUEL,
        )
        .ty
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::dpat_ty @ d9be6853b
// Materialize a (possibly in-flight) type as a `DPat` column type. Pattern
// lowering runs mid-inference, so a column can still carry unsolved
// variables, which the plain `Ty` cannot represent: an open column takes
// the Error sentinel, on which exhaustiveness only withholds verdicts.
// Recorded pattern facts are unaffected.
function dpat_ty(pool: root.types.InferPool, ty: int) -> root.types.Ty throws never {
    if (pool.has_infer(ty)) {
        root.types.TyError {}
    } else {
        pool.to_plain_closed(ty)
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::binds_without_a_type @ d9be6853b
// Whether `pat` binds without writing a type or a shape: the wildcard, a
// bare binding, a chain of bare bindings, or an or-pattern of these. Such a
// pattern asks nothing of its scrutinee's structure and takes every value
// that reaches it.
function binds_without_a_type(body: root.ast.ExprBody, pat: int) -> bool throws never {
    match (body.patterns[pat]) {
        root.ast.PatternWildcard => true,
        let b: root.ast.PatternBind => {
            let sub = b.subpat;
            sub == null || binds_without_a_type(body, sub)
        },
        let o: root.ast.PatternOr => {
            o.value.every((alternative) -> {
                binds_without_a_type(body, alternative)
            })
        },
        root.ast.PatternType | root.ast.PatternClass | root.ast.PatternArray | root.ast.PatternTuple => {
            false
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::takes_every_value @ d9be6853b
// Whether `pat` takes every value that reaches it: a pattern that binds
// without a type, or an or-pattern one of whose alternatives does
// (`Panic | _`).
function takes_every_value(body: root.ast.ExprBody, pat: int) -> bool throws never {
    match (body.patterns[pat]) {
        root.ast.PatternWildcard => true,
        let b: root.ast.PatternBind => {
            let sub = b.subpat;
            sub == null || takes_every_value(body, sub)
        },
        let o: root.ast.PatternOr => {
            o.value.some((alternative) -> {
                takes_every_value(body, alternative)
            })
        },
        root.ast.PatternType | root.ast.PatternClass | root.ast.PatternArray | root.ast.PatternTuple => {
            false
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::rest_pattern_shape_ok @ d9be6853b
// The legal shapes of a rest sub-pattern: the wildcard, a bare binding, or
// a bind chain whose tail is at most a type ascription (`..let name: T[]`).
// A chain ending in a STRUCTURAL link has no sliced-middle semantics.
function rest_pattern_shape_ok(body: root.ast.ExprBody, pat: int) -> bool throws never {
    match (body.patterns[pat]) {
        root.ast.PatternWildcard => true,
        let b: root.ast.PatternBind => {
            let sub = b.subpat;
            sub == null
                || body.patterns[sub] is root.ast.PatternType
                || rest_pattern_shape_ok(body, sub)
        },
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::scrut_members @ d9be6853b
// A scrutinee's members: union members, or the type itself.
function scrut_members(pool: root.types.InferPool, scrut: int) -> int[] throws never {
    match (pool.kinds[scrut]) {
        let u: root.types.InferTyUnion => u.members,
        _ => [scrut],
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::tuple_pattern_is_open @ d9be6853b
// These types may hold tuples of any carried instantiation, as well as
// non-tuples. A shape test cannot give their slots concrete types or
// consume the entire holder during negative narrowing.
function tuple_pattern_is_open(pool: root.types.InferPool, ty: int) -> bool throws never {
    match (pool.kinds[ty]) {
        root.types.TyUnknown
            | root.types.InferTyInterface
            | root.types.TyTypeVar
            | root.types.InferTyAssociatedTypeProjection
            | root.types.TyInferVar
            | root.types.TyTypeAlias
            | root.types.TyError =>
        {
            true
        },
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::list_holding @ d9be6853b
// What a list pattern can match among the values of `ty`, a type that is
// neither a union nor an alias; null when no value of it is a list.
function list_holding(pool: root.types.InferPool, ty: int) -> ListHolding? throws never {
    match (pool.kinds[ty]) {
        let l: root.types.InferTyList => ListHoldingElements { value: l.elem },
        // Any value at all, an implementor of an interface, whatever a type
        // parameter or projection is instantiated with, or a type still
        // being inferred: each may be a list of any element.
        root.types.TyUnknown
            | root.types.InferTyInterface
            | root.types.TyTypeVar
            | root.types.InferTyAssociatedTypeProjection
            | root.types.TyInferVar
            | root.types.TyError =>
        {
            ListHoldingAnyElements {}
        },
        // An alias that did not unfold: its shape is not known here.
        root.types.TyTypeAlias => ListHoldingAnyElements {},
        // A union an alias unfolded to: a caller that needs its members
        // unfolds it first; one that does not cannot tell.
        root.types.InferTyUnion => ListHoldingAnyElements {},
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.TyLiteral
            | root.types.InferTyClass
            | root.types.TyEnum
            | root.types.TyEnumVariant
            | root.types.InferTyTuple
            | root.types.InferTyMap
            | root.types.InferTyFunction
            | root.types.InferTyFuture
            | root.types.TyRustType
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst
            | root.types.TyNever =>
        {
            null
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::HirPatCtx @ d9be6853b
// The `PatCtx` backing the usefulness matrix, over plain resolved types.
class HirPatCtx {
    infer: root.hir_ty.InferenceContext,

    // port: baml_compiler2_hir_ty/src/infer/pat.rs::HirPatCtx::peel_aliases @ d9be6853b
    function peel_aliases(self, ty: root.types.Ty, fuel: int) -> root.types.Ty throws never {
        if (fuel == 0) {
            return ty;
        }
        match (ty) {
            let a: root.types.TyTypeAlias => {
                let target = self.infer.facts.alias_def(a.name);
                if (target != null) {
                    self.peel_aliases(target, fuel - 1)
                } else {
                    ty
                }
            },
            _ => ty,
        }
    }

    implements root.hir_ty.PatCtx {
        // port: baml_compiler2_hir_ty/src/infer/pat.rs::HirPatCtx::interface_field_projection_for_class @ d9be6853b
        // Each interface field slot's class field slot, through the impl by
        // which THIS realized class type implements THIS realized interface
        // (selected like every other impl goal, so a class implementing one
        // interface at several argument lists gets the matching block's
        // links). The served-package interface lane is dropped (see the
        // file header).
        function interface_field_projection_for_class(
            self,
            iface_ty: root.types.Ty,
            class_qtn: root.types.DeclName,
            class_type_args: root.types.Ty[],
        ) -> int[]? {
            let iface = match (iface_ty) {
                let i: root.types.TyInterface => i,
                _ => {
                    return null;
                },
            };
            let db = self.infer.db;
            let class_ = match (root.hir_ty.definition_of(db, class_qtn)) {
                let d: root.hir.DefinitionClass => d.value,
                _ => {
                    return null;
                },
            };
            // The interface's declared field list.
            let iface_fields = match (root.hir_ty.definition_of(db, iface.name)) {
                let d: root.hir.DefinitionInterface => {
                    root.hir.interface_data(db, d.value).fields.map((field) -> {
                        field.name
                    })
                },
                _ => {
                    return null;
                },
            };
            let pool = db.ty_memo.pool;
            let concrete = root.hir_ty.try_interned_ty(
                pool,
                root.types.TyClass { name: class_qtn, args: class_type_args },
            )
                ?? return null;
            let goal = root.types.infer_interface_from_constraint(
                pool,
                root.types.InterfaceConstraint {
                    name: iface.name,
                    generics: iface.args,
                    associated_types: iface.associated_types.concat([]),
                },
            );
            let resolved = root.hir_ty.resolve_impl(db, concrete, goal)
                ?? return null;
            // Field links are source data (an interface with fields is
            // implemented in-body, so the block is in this compilation).
            let block = root.hir.impl_block_data(db, resolved.facts.block);
            let class_data = root.hir.class_data(db, class_);
            let projection: int[] = [];
            for (let field in iface_fields) {
                let link = block.field_links.find((link) -> {
                    link.interface_field == field
                });
                let class_field = if (link != null) {
                    link.class_field
                } else {
                    field
                };
                let position = class_data.fields.find_index((candidate) -> {
                    candidate.name == class_field
                })
                    ?? return null;
                projection.push(position);
            }
            projection
        }

        // port: baml_compiler2_hir_ty/src/infer/pat.rs::HirPatCtx::enumerate_ctors @ d9be6853b
        function enumerate_ctors(self, ty: root.types.Ty) -> root.hir_ty.Ctor[] {
            let peeled = self.peel_aliases(ty, 8);
            match (peeled) {
                root.types.TyBool => {
                    [
                        root.hir_ty.CtorType {
                            value: root.types.TyLiteral {
                                value: root.base.LiteralBool { value: true },
                                freshness: root.types.Freshness.Regular,
                            },
                        },
                        root.hir_ty.CtorType {
                            value: root.types.TyLiteral {
                                value: root.base.LiteralBool { value: false },
                                freshness: root.types.Freshness.Regular,
                            },
                        },
                    ]
                },
                root.types.TyNull | root.types.TyLiteral | root.types.TyEnumVariant => {
                    [root.hir_ty.CtorType { value: peeled }]
                },
                root.types.TyNever => [],
                let u: root.types.TyUnion => {
                    u.members.map((member) -> {
                        root.hir_ty.CtorUnionMember { value: self.peel_aliases(member, 8) }
                    })
                },
                let e: root.types.TyEnum => {
                    (self.infer.facts.enum_variants(e.name) ?? []).map((variant) -> {
                        root.hir_ty.CtorType {
                            value: root.types.TyEnumVariant { name: e.name, variant: variant },
                        }
                    })
                },
                let c: root.types.TyClass => [root.hir_ty.CtorClass { name: c.name, args: c.args }],
                // An existential column is a single-constructor STRUCT VIEW
                // over its declared fields.
                root.types.TyInterface => [root.hir_ty.CtorInterface { value: peeled }],
                // Slice splitting owns list columns; empty defers to it.
                root.types.TyList => [],
                let t: root.types.TyTuple => [root.hir_ty.CtorTuple { value: t.items.length() }],
                // Everything else is an infinite or open alphabet.
                _ => [root.hir_ty.CtorNonExhaustive {}],
            }
        }

        // port: baml_compiler2_hir_ty/src/infer/pat.rs::HirPatCtx::interface_field_types @ d9be6853b
        // The struct-view field types of an existential column, in declared
        // order: the same member instantiation field access uses. The
        // served-package interface lane is dropped (see the file header).
        function interface_field_types(self, iface_ty: root.types.Ty) -> root.types.Ty[] {
            let iface = match (iface_ty) {
                let i: root.types.TyInterface => i,
                _ => {
                    return [];
                },
            };
            let db = self.infer.db;
            let field_names = match (root.hir_ty.definition_of(db, iface.name)) {
                let d: root.hir.DefinitionInterface => {
                    root.hir.interface_data(db, d.value).fields.map((field) -> {
                        field.name
                    })
                },
                _ => {
                    return [];
                },
            };
            let pool = self.infer.table.pool;
            let head = pool.from_plain(iface_ty);
            let target = root.types.infer_interface_new(
                iface.name,
                iface.args.map((arg) -> {
                    pool.from_plain(arg)
                }),
                iface.associated_types.map((pin) -> {
                    root.types.InferAssociatedType { name: pin.name, ty: pool.from_plain(pin.ty) }
                }),
            );
            field_names.map((field) -> {
                let member = root.hir_ty.member_on_interface(db, self.infer.facts, target, head, field, true);
                // Instantiation of a closed scrutinee head is closed; an open
                // escape poisons the column (`dpat_ty`).
                if (member != null) {
                    dpat_ty(pool, member.ty)
                } else {
                    root.types.TyError {}
                }
            })
        }

        // port: baml_compiler2_hir_ty/src/infer/pat.rs::HirPatCtx::class_field_types @ d9be6853b
        function class_field_types(
            self,
            qtn: root.types.DeclName,
            ty: root.types.Ty,
        ) -> root.types.Ty[] {
            let pool = self.infer.table.pool;
            let args = match (ty) {
                let c: root.types.TyClass => {
                    c.args.map((arg) -> {
                        pool.from_plain(arg)
                    })
                },
                _ => [],
            };
            // Substitution of closed args into declaration types is closed;
            // an open escape poisons the column (`dpat_ty`).
            class_pattern_field_types(self.infer, qtn, args).map((field_ty) -> {
                dpat_ty(pool, field_ty)
            })
        }

        // port: baml_compiler2_hir_ty/src/infer/pat.rs::HirPatCtx::is_subtype @ d9be6853b
        // Error is compatible with everything in the subtype relation; here
        // it must prove nothing.
        function is_subtype(self, sub: root.types.Ty, sup: root.types.Ty) -> bool {
            let is_error = (node: root.types.Ty) -> bool {
                node is root.types.TyError
            };
            !root.types.contains_ty_where(sub, is_error)
                && !root.types.contains_ty_where(sup, is_error)
                && self.infer.facts.is_subtype(sub, sup)
        }

        // port: baml_compiler2_hir_ty/src/infer/pat.rs::HirPatCtx::list_element_type @ d9be6853b
        function list_element_type(self, ty: root.types.Ty) -> root.types.Ty {
            match (self.peel_aliases(ty, 8)) {
                let l: root.types.TyList => l.elem,
                let other: root.types.Ty => other,
            }
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer/pat.rs::collect_bind_types @ d9be6853b
// Every `(name, recorded type)` bind under `pat` (or-alternative conflict
// detection walks each alternative's binds).
function collect_bind_types(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    pat: int,
    out: (string, int)[],
) -> void throws never {
    match (body.patterns[pat]) {
        let b: root.ast.PatternBind => {
            let ty = ctx.result.type_of_pat.get(pat);
            if (ty != null) {
                out.push((b.name, ty));
            }
            let sub = b.subpat;
            if (sub != null) {
                collect_bind_types(ctx, body, sub, out);
            }
        },
        let c: root.ast.PatternClass => {
            for (let field in c.fields) {
                collect_bind_types(ctx, body, field.pat, out);
            }
        },
        let a: root.ast.PatternArray => {
            for (let sub in a.prefix.concat(a.suffix)) {
                collect_bind_types(ctx, body, sub, out);
            }
            let rest_pat = a.rest?.pat;
            if (rest_pat != null) {
                collect_bind_types(ctx, body, rest_pat, out);
            }
        },
        let o: root.ast.PatternOr => {
            for (let alt in o.value) {
                collect_bind_types(ctx, body, alt, out);
            }
        },
        let t: root.ast.PatternTuple => {
            for (let element in t.value) {
                collect_bind_types(ctx, body, element, out);
            }
        },
        root.ast.PatternWildcard | root.ast.PatternType => {},
    }
}
