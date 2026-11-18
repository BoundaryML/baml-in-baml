// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// Unit 1 of the K4 plan, part one: the core of the expression walk (the
// body drive, checking mode, `return`/`throw`, implicit units, `if`
// branches, probes, suppressions and the report queue), plus the free
// helpers `may_become_unit` and `value_tail`. `infer_expr` is in
// `infer_u1_expr.baml`, `infer_stmt` in `infer_u1_stmt.baml`, the scoped
// type bindings in `infer_u1_scoped.baml`, and `let` / assignment in
// `infer_u1_let.baml`.
//
// Restructured (BAML forces it), as in infer.baml: methods of
// `InferenceContext` are free functions taking `ctx` first; interned types
// are `int`s into `ctx.table.pool`; `Option<&Ty>` is `int?`; a flow overlay
// is copied with `copy_flow` where Rust clones it.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::metadata_key @ d9be6853b
// The semantic-index key for an expression under the CURRENT scope:
// `ParameterDefault` when this run infers a default arena and the walk sits
// at the owner scope (the builder's `walk_parameter_defaults` keys those
// expressions so), `Body` everywhere else (lambda bodies included: their
// frame names their scope).
function metadata_key(ctx: InferenceContext, expr: int) -> root.hir.ExprMetadataKey? throws never {
    let scope = root.hir_ty.infer.current_scope(ctx)
        ?? return null;
    let defaults_owner = ctx.owner is root.hir.BodyOwnerIdParameterDefaults;
    let metadata_scope: root.hir.ExprMetadataScope = if (defaults_owner && scope == ctx.owner_scope) {
        root.hir.ExprMetadataScopeParameterDefault { value: scope }
    } else {
        root.hir.ExprMetadataScopeBody { value: scope }
    };
    root.hir.ExprMetadataKey.new(metadata_scope, expr)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr_body @ d9be6853b
function infer_expr_body(ctx: InferenceContext, body: root.ast.ExprBody) -> void throws never {
    register_property_shorthands(ctx, body);
    ctx.body_root = body.root_expr;
    let body_root = body.root_expr;
    if (body_root != null) {
        let return_ty = root.hir_ty.infer.return_frame(ctx).expected;
        if (return_ty == null) {
            infer_expr(ctx, body, body_root, ExpectationNone {});
        } else if (!ctx.table.pool.has_error(return_ty)) {
            check_expr(ctx, body, body_root, return_ty);
        } else {
            infer_expr(ctx, body, body_root, ExpectationErroneous {});
        }
    }
    check_tag_values(ctx, body);
    backfill_untyped_patterns(ctx, body);
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::backfill_untyped_patterns @ d9be6853b
// Backfills patterns the walk did not type. A TYPE-EXPRESSION node (an
// annotation or ascription, or an OR of them) records the type it DENOTES
// (typed coverage, TIR's convention); everything else records the sentinel
// so gaps stay visible. Shared by the body drive and the parameter-defaults
// drive.
function backfill_untyped_patterns(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
) -> void throws never {
    let unfilled: int[] = [];
    for (let pat_id = 0; pat_id < body.patterns.length(); pat_id += 1) {
        if (!ctx.result.type_of_pat.has(pat_id)) {
            unfilled.push(pat_id);
        }
    }
    for (let pat_id in unfilled) {
        let ty = pattern_ascription_ty(ctx, body, pat_id) ?? ctx.table.pool.add(root.types.TyError {});
        ctx.result.type_of_pat.set(pat_id, ty);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::register_property_shorthands @ d9be6853b
function register_property_shorthands(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
) -> void throws never {
    for (let expr in body.exprs) {
        if let object: root.ast.ExprObject = expr {
            for (let field in object.fields) {
                if (field.syntax == root.ast.PropertySyntax.Shorthand) {
                    ctx.property_shorthand_values.set(field.value, field.name);
                }
            }
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_expr @ d9be6853b
// Checking mode: infer with the expectation, then constrain
// (`Sub(actual, expected)`, discharged eagerly). Definite failures are
// recorded against the checked expression, never dropped.
//
// A block that ends in a value where the unit type is expected is marked as
// a `unit_positions` entry: the value would be dropped silently, so its
// mismatch reports at the expression that produces it and names the remedy.
function check_expr(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: int,
) -> int throws never {
    check_expr_fits(ctx, body, expr, expected).0
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_expr_fits @ d9be6853b
// `check_expr`, also answering whether the expression fits as far as is
// known now.
function check_expr_fits(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: int,
) -> (int, bool) throws never {
    let ty = infer_expr_with_hint(ctx, body, expr, expected);
    // Whether the unit type is what was expected is asked when the mismatch
    // reports: the expectation may not be solved yet.
    let tail = value_tail(body, expr);
    if (tail != expr) {
        ctx.unit_positions.set(expr, (tail, UnitContext.Block));
    }
    let fits = check_fits(ctx, expr, ty, expected);
    (ty, fits)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_branch @ d9be6853b
// Types one branch of an `if`, `match` or `catch`. A hard expectation
// CHECKS each branch (rustc coerces every arm to the expectation): a failing
// one reports at ITSELF and recovers as the expectation, so the join does
// not report the same mismatch again on the whole expression, nor one
// branch's mistake hide another's. A passing one keeps its ACTUAL type
// (literal grain survives the join).
function infer_branch(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    branch: int,
    expected: Expectation,
) -> int throws never {
    let expected_ty = expectation_only_has_type(expected);
    if (expected_ty == null) {
        return infer_expr(ctx, body, branch, expected);
    }
    let (let actual, let fits) = check_expr_fits(ctx, body, branch, expected_ty);
    if (fits) {
        actual
    } else {
        expected_ty
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_inferred @ d9be6853b
// The checking half of `check_expr`: relate an already inferred `ty` to
// `expected` at `expr`, recording the mismatch or the adapter.
function check_inferred(
    ctx: InferenceContext,
    expr: int,
    ty: int,
    expected: int,
) -> int throws never {
    check_fits(ctx, expr, ty, expected);
    ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_fits @ d9be6853b
// `check_inferred`, answering whether `ty` fits as far as is known now.
function check_fits(ctx: InferenceContext, expr: int, ty: int, expected: int) -> bool throws never {
    let pool = ctx.table.pool;
    let saved_anchor = ctx.obligation_anchor;
    ctx.obligation_anchor = expr;
    let fits = sub(ctx, ty, expected);
    ctx.obligation_anchor = saved_anchor;
    if (!fits) {
        ctx.result.type_mismatches.set(expr, (expected, ty));
    } else if ((pool.has_infer(expected) || pool.has_infer(ty)) && !pool.has_error(ty)) {
        // A GROUND value checked against a still-open expectation passed by
        // DEPOSITING a bound; whether it actually fits is only known once
        // the var solves. Stash for the finalize re-check (the
        // establishment-order road: a later push's incompatible element
        // reports here).
        ctx.journals.provisional_checks.push((expr, expected, ty));
    }
    fits
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr_with_hint @ d9be6853b
// Supply value context without checking the outer relation. Return values
// use `check_expr`; thrown values need effect diagnostics and panic
// filtering instead, but share the same contextual inference.
function infer_expr_with_hint(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: int?,
) -> int throws never {
    let expectation: Expectation = if (expected != null) {
        expectation_has_type(ctx.table.pool, expected)
    } else {
        ExpectationNone {}
    };
    infer_expr(ctx, body, expr, expectation)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_throw @ d9be6853b
function infer_throw(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    value: int,
) -> void throws never {
    let channel = ctx.throws_channels.at(ctx.throws_channels.length() - 1);
    let expected = if (channel != null) {
        throws_clause_closed(channel.clause)
    } else {
        null
    };
    let thrown = infer_expr_with_hint(ctx, body, value, expected);
    record_throw(ctx, value, thrown);
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_return @ d9be6853b
// `at` is the `return` itself, for a bare `return;` to report at. A
// `return` that leaves a `defer` body or an expression context
// (`return_escape`) is rejected and still typed against the innermost
// callable, so its value gets no second report.
function infer_return(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    value: int?,
    at: DiagnosticLocation,
) -> void throws never {
    match (root.hir_ty.infer.return_escape(ctx)) {
        root.hir_ty.infer.ReturnEscapeDefer => {
            report(ctx, PendingDiagDeferEscape { at: at, keyword: "return" });
        },
        let outside: root.hir_ty.infer.ReturnEscapeOutside => {
            report(ctx, PendingDiagReturnOutsideFunctionBody { at: at, context: outside.value });
        },
        null => {},
    }
    let pool = ctx.table.pool;
    let frame = root.hir_ty.infer.return_frame(ctx);
    let expected = frame.expected;
    let floor = frame.scoped_bindings_floor;
    let returned = if (value != null) {
        let context = if (expected != null && !pool.has_error(expected)) {
            expected
        } else {
            null
        };
        let expectation: Expectation = if (context != null) {
            expectation_has_type(pool, context)
        } else if (expected != null) {
            ExpectationErroneous {}
        } else {
            ExpectationNone {}
        };
        let ty = infer_expr(ctx, body, value, expectation);
        let units = take_units(ctx, value);
        let escaped = frame_scoped_param(ctx, ty, floor);
        let settled = if (escaped != null && expected != null && pool.has_error(expected)) {
            // A context already diagnosed suppresses the escape too.
            ty
        } else if (escaped != null) {
            // A `return` leaves every block of its frame at once, so a value
            // typed by a binding the frame opened is judged here, at the
            // return, the way a declared `throws` judges a throw: the binding
            // is still in scope, so the closing brace would never see it, and
            // a frame candidate carries no anchor to report at.
            let resolved = if (context != null) {
                ctx.table.resolve_completely(context)
            } else {
                null
            };
            let vetted = if (resolved != null && frame_scoped_param(ctx, resolved, floor) == null) {
                resolved
            } else {
                null
            };
            publish_scoped_value(ctx, value, escaped, ty, vetted)
        } else if (context != null) {
            check_inferred(ctx, value, ty, context)
        } else {
            ty
        };
        root.hir_ty.infer.Returned { ty: settled, units: units }
    } else {
        // `return;` is shorthand for `return null;`.
        let site = UnitSite { at: at, form: UnitSiteFormBareReturn {} };
        let verdict = unit_verdict(ctx, expected);
        let (let ty, let unjudged) = settle_unit(ctx, site, verdict);
        if (expected != null && !pool.has_error(ty)) {
            sub(ctx, ty, expected);
        }
        root.hir_ty.infer.Returned {
            ty: ty,
            units: if (unjudged != null) {
                [unjudged]
            } else {
                []
            },
        }
    };
    root.hir_ty.infer.return_frame(ctx).candidates.push(returned);
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::unit_verdict @ d9be6853b
// What its context makes of an *implicit unit*: a block with no final
// expression, an `if` with no `else`, or a bare `return;`. Each evaluates
// to the unit value without the author writing it, so it is admitted only
// where the unit type itself is expected. Subtyping alone would be too
// permissive: `null <: int?`, so a forgotten value would become a silent
// `null`. Where nothing is expected the form is unit as long as nothing
// else joins it, which its join decides.
function unit_verdict(ctx: InferenceContext, expected: int?) -> UnitVerdict throws never {
    if (expected == null) {
        return UnitVerdictUnjudged {};
    }
    let pool = ctx.table.pool;
    let resolved = ctx.table.resolve_completely(expected);
    if (pool.kinds[resolved] is root.types.TyError) {
        return UnitVerdictAdmitted {};
    }
    if (may_become_unit(pool, resolved)) {
        UnitVerdictPending { value: resolved }
    } else if (cached_equivalent(ctx, resolved, pool.add(root.types.TyNull {}))) {
        UnitVerdictAdmitted {}
    } else {
        UnitVerdictRefused { value: resolved }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::settle_unit @ d9be6853b
// Records `verdict` for the implicit unit at `site`. Returns its type, the
// error sentinel when refused so the one mistake does not report again as a
// mismatch against the same context, and the site itself when it is left
// to its join.
function settle_unit(
    ctx: InferenceContext,
    site: UnitSite,
    verdict: UnitVerdict,
) -> (int, UnitSite?) throws never {
    let pool = ctx.table.pool;
    match (verdict) {
        UnitVerdictAdmitted => (pool.add(root.types.TyNull {}), null),
        UnitVerdictUnjudged => (pool.add(root.types.TyNull {}), site),
        let pending: UnitVerdictPending => {
            report(
                ctx,
                PendingDiagImplicitUnit {
                    site: site,
                    demand: UnitDemandExpected { value: pending.value },
                },
            );
            (pool.add(root.types.TyNull {}), null)
        },
        let refused: UnitVerdictRefused => {
            report(
                ctx,
                PendingDiagImplicitUnit {
                    site: site,
                    demand: UnitDemandExpected { value: refused.value },
                },
            );
            (pool.add(root.types.TyError {}), null)
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::implicit_unit @ d9be6853b
// `settle_unit` for an implicit unit that is an expression: a tail-less
// block or a lone `if`. One left to its join is carried as that
// expression's value.
function implicit_unit(
    ctx: InferenceContext,
    expr: int,
    form: UnitSiteForm,
    verdict: UnitVerdict,
) -> int throws never {
    let site = UnitSite { at: DiagnosticLocationExpr { value: expr }, form: form };
    let (let ty, let unjudged) = settle_unit(ctx, site, verdict);
    if (unjudged != null) {
        ctx.unjudged_units.set(expr, [unjudged]);
    }
    ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::take_units @ d9be6853b
// The implicit units `expr`'s value carries, unjudged.
function take_units(ctx: InferenceContext, expr: int) -> UnitSite[] throws never {
    ctx.unjudged_units.delete(expr) ?? []
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::join_units @ d9be6853b
// Judges the implicit units among the values a join combines (the branches
// of an `if`, the arms of a `match` or `catch`, a literal's elements, a
// lambda's returns) that met no expectation on their way to it. A join of
// nothing but unit values is itself unit, so its units are returned to be
// carried on; beside any other value, each is a silent `null` and is
// reported. The join's own expectation judges them too: the branches did
// not see it when it was an inference variable, held back so the first
// branch cannot fix it for the rest.
function join_units(
    ctx: InferenceContext,
    parts: (int, UnitSite[])[],
    expected: Expectation,
) -> UnitSite[] throws never {
    let others: int[] = [];
    let sites: UnitSite[] = [];
    for (let part in parts) {
        if (part.1.length() == 0) {
            others.push(part.0);
        } else {
            root.base.extend(sites, part.1);
        }
    }
    if (sites.length() == 0) {
        return sites;
    }
    let expected_ty = match (expected) {
        ExpectationNone => null,
        let e: ExpectationHasType => e.value,
        // Nothing reads the join, or its context is already diagnosed.
        ExpectationDiscarded | ExpectationErroneous => {
            return [];
        },
    };
    let pool = ctx.table.pool;
    let joined = join(ctx, others);
    let widened = widen_fresh(ctx, joined);
    let resolved = ctx.table.resolve_completely(widened);
    let all_unit = !pool.has_infer(resolved) && cached_subtype(ctx, resolved, pool.add(root.types.TyNull {}));
    if (!all_unit) {
        for (let site in sites) {
            report(
                ctx,
                PendingDiagImplicitUnit { site: site, demand: UnitDemandJoined { value: widened } },
            );
        }
    }
    if (expected_ty != null) {
        for (let site in sites) {
            report(
                ctx,
                PendingDiagImplicitUnit {
                    site: site,
                    demand: UnitDemandExpected { value: expected_ty },
                },
            );
        }
        []
    } else if (all_unit) {
        sites
    } else {
        []
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::is_unit_ty @ d9be6853b
// Whether `ty` is the unit type itself, as opposed to a type that merely
// admits the unit value (`int?`) or one not yet solved.
function is_unit_ty(ctx: InferenceContext, ty: int) -> bool throws never {
    let pool = ctx.table.pool;
    let resolved = ctx.table.resolve_completely(ty);
    !pool.has_infer(resolved)
        && !pool.has_error(resolved)
        && cached_equivalent(ctx, resolved, pool.add(root.types.TyNull {}))
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_if_branches @ d9be6853b
// The branches of an `if` / `if let`, after its condition. `enter` applies
// what the condition proves on the side it is given.
function infer_if_branches(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    then_branch: int,
    else_branch: int?,
    expected: Expectation,
    enter: (InferenceContext, IfSide) -> void throws never,
) -> int throws never {
    let condition_diverges = root.hir_ty.infer.diverges(ctx);
    let branch_expectation = expectation_adjust_for_branches(expected, ctx.table);
    let base_flow = root.hir_ty.infer.copy_flow(ctx.flow);

    enter(ctx, IfSide.Then);
    root.hir_ty.infer.set_diverges(ctx, Diverges.Maybe);
    // With no `else`, this is the type of the whole `if`.
    let then_ty = if (else_branch != null) {
        infer_branch(ctx, body, then_branch, branch_expectation)
    } else {
        infer_lone_if(ctx, body, expr, then_branch, expected)
    };
    let then_diverges = root.hir_ty.infer.diverges(ctx);
    let then_taken = ctx.flow;
    ctx.flow = root.hir_ty.infer.copy_flow(base_flow);
    let then_flow = if (then_diverges == Diverges.Maybe) {
        then_taken
    } else {
        null
    };

    // The else path (written or implicit fall-through) carries the
    // condition's false facts; the divergence-aware merge makes
    // guard-with-early-return narrowing the ordinary rule, no special case.
    enter(ctx, IfSide.Else);
    if (else_branch == null) {
        let else_flow = ctx.flow;
        ctx.flow = base_flow;
        root.hir_ty.infer.set_diverges(ctx, condition_diverges);
        ctx.flow
            = root.hir_ty.infer.merge_flows(
                ctx,
                else_flow,
                if (then_flow != null) {
                    [then_flow]
                } else {
                    []
                },
            );
        return then_ty;
    }
    root.hir_ty.infer.set_diverges(ctx, Diverges.Maybe);
    let else_ty = infer_branch(ctx, body, else_branch, branch_expectation);
    let else_diverges = root.hir_ty.infer.diverges(ctx);
    let else_taken = ctx.flow;
    ctx.flow = root.hir_ty.infer.copy_flow(base_flow);
    let reaching: root.hir_ty.infer.Flow[] = [];
    if (then_flow != null) {
        reaching.push(then_flow);
    }
    if (else_diverges == Diverges.Maybe) {
        reaching.push(else_taken);
    }
    root.hir_ty.infer.set_diverges(
        ctx,
        diverges_or(condition_diverges, diverges_and(then_diverges, else_diverges)),
    );
    // Both branches diverged: everything after is unreachable; keep entry.
    ctx.flow = root.hir_ty.infer.merge_reaching(ctx, reaching) ?? base_flow;
    let parts = [(then_ty, take_units(ctx, then_branch)), (else_ty, take_units(ctx, else_branch))];
    let units = join_units(ctx, parts, expected);
    if (units.length() > 0) {
        ctx.unjudged_units.set(expr, units);
    }
    // The merge point: a canonical union, never a forced equality (joins
    // happen at generation sites).
    join(ctx, [then_ty, else_ty])
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_lone_if @ d9be6853b
// The type of an `if` / `if let` with no `else`, given its branch. Where
// the `if` is observed it is an implicit unit, so its branch must be unit
// too. A branch that produces a value anyway is the author reading the `if`
// as one: that is the mistake reported, and the `if` takes the error
// sentinel rather than report again wherever its `null` then fails to fit.
function infer_lone_if(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    branch: int,
    expected: Expectation,
) -> int throws never {
    let pool = ctx.table.pool;
    let verdict = match (expected) {
        ExpectationNone | ExpectationHasType => {
            unit_verdict(ctx, expectation_only_has_type(expected))
        },
        // Nothing reads it (a statement), or its context is already
        // diagnosed: the slot is typed by what it can hold, the branch's
        // value or `null` when the branch did not run.
        ExpectationDiscarded | ExpectationErroneous => {
            let branch_ty = infer_expr(ctx, body, branch, expected);
            return join(ctx, [branch_ty, pool.add(root.types.TyNull {})]);
        },
    };
    if (verdict is UnitVerdictRefused) {
        // The context refused the `if`; its branch owes nothing.
        infer_expr(ctx, body, branch, ExpectationErroneous {});
        return implicit_unit(ctx, expr, UnitSiteFormIfWithoutElse {}, verdict);
    }
    let unit = pool.add(root.types.TyNull {});
    let ty = infer_expr(ctx, body, branch, ExpectationHasType { value: unit });
    // Discarding the branch's value is a remedy only where the `if` itself
    // is meant to be unit, not where its value is used.
    let context = match (verdict) {
        UnitVerdictAdmitted => UnitContext.IfWithoutElse,
        UnitVerdictUnjudged | UnitVerdictPending | UnitVerdictRefused => {
            UnitContext.UsedIfWithoutElse
        },
    };
    ctx.unit_positions.set(branch, (value_tail(body, branch), context));
    if (!check_fits(ctx, branch, ty, unit)) {
        return pool.add(root.types.TyError {});
    }
    implicit_unit(ctx, expr, UnitSiteFormIfWithoutElse {}, verdict)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::probe @ d9be6853b
// Opens a speculative probe: relate freely, then discard the whole attempt
// with `rollback_probe`. See `ProbeCheckpoint`.
function probe(ctx: InferenceContext) -> ProbeCheckpoint throws never {
    ProbeCheckpoint {
        table: ctx.table.snapshot(),
        journals: ctx.journals.mark(),
        type_mismatches: ctx.result.type_mismatches.length(),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::rollback_probe @ d9be6853b
// Discards everything a probe did, in the order the state depends on: the
// accumulators first (they name variables), then the table, whose rollback
// frees those variables' keys for reuse. Rust's debug assertion that the
// probe recorded no type mismatch is dropped.
function rollback_probe(ctx: InferenceContext, probe: ProbeCheckpoint) -> void throws never {
    ctx.journals.truncate_to(probe.journals);
    ctx.table.rollback_to(probe.table);
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::owner_function @ d9be6853b
// The function whose body this run infers, when the owner is one (a
// defaults arena types in its function's environment too): the resolver
// for owner-scoped receivers (`default` inside an `implements` block, like
// `self`).
function owner_function(ctx: InferenceContext) -> int? throws never {
    match (ctx.owner) {
        let owner: root.hir.BodyOwnerIdFunction => owner.value,
        let owner: root.hir.BodyOwnerIdParameterDefaults => owner.value,
        root.hir.BodyOwnerIdLet => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::global_initializer @ d9be6853b
// The global's name when this run checks a source global variable's
// initializer (not a client's, not a Session binding's): the owner whose
// top-level `return` is refused.
function global_initializer(ctx: InferenceContext) -> string? throws never {
    let binding = match (ctx.owner) {
        let owner: root.hir.BodyOwnerIdLet => owner.value,
        _ => {
            return null;
        },
    };
    if (is_source_global(ctx.db, binding)) {
        root.hir.let_data(ctx.db, binding).name
    } else {
        null
    }
}

// port: baml_compiler2_hir_ty/src/globals.rs::is_source_global @ d9be6853b
// Whether `binding` is a source global variable: a `let` written at the top
// level of a file (not a client, not a Session submission's binding). Only
// these can be annotated, and only their initializers are held to the
// initializer-is-an-expression rules (no top-level `return`).
// Placed here until globals.rs is ported (package L), which should move it.
function is_source_global(db: root.hir.Db, binding: int) -> bool throws never {
    root.hir.let_data(db, binding).origin == root.ast.LetOrigin.Source
        && !root.hir.is_session_submission(db, db.let_locs.get(binding).file)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::suppressed @ d9be6853b
// Whether reports of `what`'s kind stay quiet at the current point.
function suppressed(ctx: InferenceContext, what: Suppress) -> bool throws never {
    ctx.suppressions.depth(what) > 0
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::with_suppressed @ d9be6853b
// Runs `f` with reports of `what`'s kind held quiet; nesting counts.
function with_suppressed<R>(
    ctx: InferenceContext,
    what: Suppress,
    f: (InferenceContext) -> R throws never,
) -> R throws never {
    ctx.suppressions.depth_mut(what, 1);
    let out = f(ctx);
    ctx.suppressions.depth_mut(what, -1);
    out
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report @ d9be6853b
// Queues a diagnostic; it is finalized at finish.
function report(ctx: InferenceContext, diag: PendingDiag) -> void throws never {
    ctx.journals.pending_diags.push(diag);
}

// port: baml_compiler2_hir_ty/src/infer.rs::may_become_unit @ d9be6853b
// Whether an implicit unit's expected type may still solve to the unit
// type. Only a variable or what can reduce through one can: any other
// constructor has already ruled it out, whatever variables it holds.
function may_become_unit(pool: root.types.InferPool, ty: int) -> bool throws never {
    if (!pool.has_infer(ty)) {
        return false;
    }
    match (pool.kinds[ty]) {
        root.types.TyInferVar | root.types.InferTyUnion | root.types.InferTyAssociatedTypeProjection => {
            true
        },
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
            | root.types.InferTyInterface
            | root.types.TyEnum
            | root.types.TyEnumVariant
            | root.types.InferTyList
            | root.types.InferTyTuple
            | root.types.InferTyMap
            | root.types.InferTyFunction
            | root.types.InferTyFuture
            | root.types.TyRustType
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst
            | root.types.TyTypeAlias
            | root.types.TyTypeVar
            | root.types.TyUnknown
            | root.types.TyNever
            | root.types.TyError =>
        {
            false
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::value_tail @ d9be6853b
// The expression that produces `expr`'s value: a block's final expression,
// through nested blocks. A diagnostic about that value points here rather
// than at the whole block.
function value_tail(body: root.ast.ExprBody, expr: int) -> int throws never {
    let current = expr;
    while let block: root.ast.ExprBlock = body.exprs[current] {
        let tail = block.tail_expr;
        if (tail == null) {
            break;
        }
        current = tail;
    }
    current
}
