// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 5, the effect half: `catch` typing over the error channel, the
// panic helpers, the throws-contract judgements, and the template and
// optional-chain checks that sit beside them in infer.rs. The pattern half
// is ns_infer/pat.baml.
//
// Restructured (BAML forces it):
// - `InferenceContext` methods are free functions taking `ctx` first, as in
//   infer.baml; interned types are `int`s into `ctx.table.pool`.
// - Rust's `BTreeSet<baml_type::Ty>` of throw facts is a sorted,
//   duplicate-free array (`ty_btree_set`, infer.baml).
// - Snapshots of the flow overlay copy the map (`copy_flow`, infer.baml).

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_catch @ d9be6853b
// `base catch (e) { arms }` / `catch_all` / `catch_all_panics`: narrowing on
// the ERROR channel, one road for every clause kind. The protected
// expression's effects collect into their own channel; the clause binding
// takes their union, and arms subtract what they provably handle. A clause
// that requires error coverage reports what its arms left (E0062) and
// clears the received facts; a partial catch propagates the residual. Own
// arm errors enter the outer channel. The result joins the base value with
// the arm values.
function infer_catch(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    catch_expr: int,
    base: int,
    clause: root.ast.CatchClause,
    expected: Expectation,
) -> int throws never {
    let pool = ctx.table.pool;
    // An exception can leave the base at any point, and a handler may
    // assign outer locals (including through a defer at its block exit).
    let entry_flow = copy_flow(ctx.flow);
    let writes = root.hir_ty.infer.assigned_bindings(ctx, body, base);
    for (let arm in clause.arms) {
        let arm_writes = root.hir_ty.infer.assigned_bindings(ctx, body, body.catch_arms[arm].body);
        for (let binding in arm_writes.keys()) {
            writes.set(binding, true);
        }
    }
    for (let binding in writes.keys()) {
        entry_flow.delete(binding);
    }
    let branch_expectation = expectation_adjust_for_branches(expected, ctx.table);
    // Each chained catch is a nested base expression. Its residual and
    // handler-arm throws enter this channel, so this handler can catch
    // both. Throws from this handler's own arms stay in the outer channel.
    ctx.throws_channels.push(ThrowsChannel { clause: ThrowsClauseInferred {}, contributions: [] });
    // The catch diverges only when the base and every arm do: divergence
    // cannot tell a base that returns from one that throws.
    let entry_diverges = root.hir_ty.infer.diverges(ctx);
    let base_ty = infer_branch(ctx, body, base, branch_expectation);
    let base_diverges = root.hir_ty.infer.diverges(ctx);
    let popped = ctx.throws_channels.pop() ?? baml.sys.panic("pushed above");
    // An arm's binding would carry the fact's type past the block that
    // scoped it.
    let channel = drop_escaping_effects(ctx, popped.contributions, null);
    ctx.flow = entry_flow;
    // catch discharges a SET of throw facts: each contribution finalizes and
    // top-level unions split into their member facts, so per-arm matching
    // and subtraction work at fact grain.
    let facts: int[] = [];
    for (let entry in channel) {
        let finalized = finalize_incoming_effect(ctx, entry.1);
        if (pool.kinds[finalized] is root.types.TyNever) {
            continue;
        }
        let resolved = ctx.table.resolve_completely(finalized);
        let canonical = root.hir_ty.infer.matrix_scrut(ctx, resolved);
        let members = match (pool.kinds[canonical]) {
            let u: root.types.InferTyUnion => u.members,
            _ => [canonical],
        };
        for (let member in members) {
            if (!facts.includes(member)) {
                facts.push(member);
            }
        }
    }

    let had_facts = facts.length() > 0;
    let arm_tys = [base_ty];
    let all_arms_diverge: Diverges = Diverges.Always;
    let clause_facts = facts.concat([]);
    // The panics this clause's arms trap, for a clause that must cover them
    // all. Without inferred panic effects, each boundary covers the full
    // panic family itself.
    let trapped_panics: int[] = [];
    let traps_every_panic = false;
    let clause_binding_ty = if (facts.length() == 0) {
        pool.add(root.types.TyNever {})
    } else {
        union_of(ctx, facts)
    };
    ctx.result.type_of_pat.set(clause.binding, clause_binding_ty);
    let context = clause.stack_trace_binding;
    if (context != null) {
        // The second binding (`catch (e, ctx)`) is the full error context,
        // `baml.errors.Context`. Lookup-gated, fail-safe to Error.
        let context_ty = match (lang_decl(ctx, root.base.LangPackage.Baml, ["errors"], "Context")) {
            let decl: root.types.DeclName
                if definition_of(ctx.db, decl) is root.hir.DefinitionClass
                || mounted_class_loc(ctx.db, decl) != null => {
                pool.add(root.types.InferTyClass { name: decl, args: [] })
            },
            _ => pool.add(root.types.TyError {}),
        };
        ctx.result.type_of_pat.set(context, context_ty);
    }
    for (let arm_id in clause.arms) {
        let arm = body.catch_arms[arm_id];
        // The arm's CLAIM: its pattern's own denotation, probed against
        // `unknown`. The probe is silent: bindings recorded here are
        // overwritten by the walk against the arm's scrutinee, which is the
        // one that reports.
        let pending_before = ctx.journals.pending_diags.length();
        let probe = root.hir_ty.infer.lower_pattern(ctx, body, arm.pattern, pool.add(root.types.TyUnknown {}));
        root.syntax.truncate(ctx.journals.pending_diags, pending_before);
        // A claim the probe could not decide is taken from the walk against
        // everything still reaching the arm instead.
        let walked = if (pool.has_error(probe.matched_ty)) {
            let world = if (facts.length() == 0) {
                pool.add(root.types.TyNever {})
            } else {
                union_of(ctx, facts)
            };
            root.hir_ty.infer.lower_pattern(ctx, body, arm.pattern, world)
        } else {
            null
        };
        let decided = walked ?? probe;
        let claim = decided.matched_ty;
        // A refutable pattern handles only SOME values of its claimed type,
        // so it discharges nothing.
        let claim_is_total = decided.consumes_matched;
        // A pattern that takes every value is decided from its syntax.
        let takes_everything = root.hir_ty.infer.takes_every_value(body, arm.pattern);
        // Fact by fact: a fact INSIDE a total claim is definitely handled
        // (and subtracts); a claim overlapping a fact MAY receive it.
        let may: int[] = [];
        let definite: int[] = [];
        for (let fact in facts) {
            if (provable_subtype(ctx, fact, claim)) {
                may.push(fact);
                if (claim_is_total) {
                    definite.push(fact);
                }
            } else if (provable_subtype(ctx, claim, fact)) {
                may.push(fact);
            }
        }
        // The panic side-rule: a claim naming `baml.panics.*` types is
        // always live. A wildcard or bare bind in a clause whose wildcards
        // trap panics traps every one.
        let wildcard_traps_panics = takes_everything && root.ast.catch_clause_kind_wildcard_traps_panics(clause.kind);
        if (wildcard_traps_panics) {
            if (!traps_every_panic) {
                let untrapped = panics_not_trapped(ctx, trapped_panics);
                if (untrapped.length() == 0 && may.length() == 0 && had_facts) {
                    report(ctx, PendingDiagUnreachableArm { expr: arm.body, warning: true });
                }
                root.base.extend(may, untrapped);
            }
            traps_every_panic = true;
        } else {
            let panic = panic_subset(ctx, claim);
            if (panic != null) {
                if (claim_is_total) {
                    trapped_panics.push(panic);
                }
                may.push(panic);
            } else if (had_facts && may.length() == 0 && !pool.has_error(claim)) {
                // Earlier arms drained every fact this arm could receive:
                // unreachable. An errored claim judges nothing.
                report(ctx, PendingDiagUnreachableArm { expr: arm.body, warning: true });
            }
        }
        // The arm's scrutinee: its may-set, else the WRITTEN claim; a
        // wildcard or bare bind wrote nothing, so with no facts left its
        // world is `never`.
        let outcome = if (walked != null) {
            walked
        } else {
            let arm_scrut = if (may.length() > 0) {
                union_of(ctx, may)
            } else if (takes_everything) {
                pool.add(root.types.TyNever {})
            } else {
                claim
            };
            root.hir_ty.infer.lower_pattern(ctx, body, arm.pattern, arm_scrut)
        };
        // The clause binding NARROWS to the arm's matched type inside the
        // arm body.
        let arm_entry_flow = copy_flow(ctx.flow);
        let binding = binding_for_pattern(ctx, clause.binding);
        if (binding != null) {
            ctx.flow.set(binding, outcome.matched_ty);
        }
        root.hir_ty.infer.set_diverges(ctx, Diverges.Maybe);
        let arm_ty = infer_branch(ctx, body, arm.body, branch_expectation);
        all_arms_diverge = diverges_and(all_arms_diverge, root.hir_ty.infer.diverges(ctx));
        ctx.flow = arm_entry_flow;
        arm_tys.push(arm_ty);
        // Definitely-handled facts leave the set; the survivors are the
        // next arm's world and, at the end, the rethrow.
        facts
            = facts.filter((fact) -> {
                !definite.includes(fact)
            });
    }
    root.hir_ty.infer.set_diverges(
        ctx,
        diverges_or(entry_diverges, diverges_and(base_diverges, all_arms_diverge)),
    );
    if (root.ast.catch_clause_kind_requires_error_coverage(clause.kind)) {
        judge_catch_coverage(ctx, catch_expr, clause.kind, clause_facts, facts, trapped_panics, traps_every_panic);
        // The clause promised to handle everything that reached it: nothing
        // it received propagates, reported or not.
        facts = [];
    }
    for (let fact in facts) {
        record_throw(ctx, base, fact);
    }
    let values = [base].concat(
        clause.arms.map((arm) -> {
            body.catch_arms[arm].body
        }),
    );
    let parts = baml.Array.generate(arm_tys.length(), (i) -> {
        (arm_tys[i], take_units(ctx, values[i]))
    });
    let units = join_units(ctx, parts, expected);
    if (units.length() > 0) {
        ctx.unjudged_units.set(catch_expr, units);
    }
    join(ctx, arm_tys)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::judge_catch_coverage @ d9be6853b
// E0062 for a clause that must cover what reaches it: `unhandled` are the
// error facts its arms left, out of `received`; a clause that must also
// cover panics reports the `baml.panics.*` classes its arms do not trap.
// Errors are spelled widened (a thrown `"oops"` is a missing `string`).
function judge_catch_coverage(
    ctx: InferenceContext,
    at: int,
    kind: root.ast.CatchClauseKind,
    received: int[],
    unhandled: int[],
    trapped_panics: int[],
    traps_every_panic: bool,
) -> void throws never {
    let pool = ctx.table.pool;
    if (
        unhandled.some((fact) -> {
            pool.has_error(fact)
        })
    ) {
        return;
    }
    let widened = (facts: int[]) -> root.types.Ty[] {
        facts.flat_map((fact) -> {
            flatten_declared_ty_to_facts(plain_finalized(ctx, fact))
        })
    };
    let caught = throws_clause_union(widened(received)) ?? root.types.TyNever {};
    let missing = widened(unhandled).map((leaf) -> {
        ty_spell(leaf, infer_ctx_viewpoint(ctx))
    });
    if (root.ast.catch_clause_kind_requires_panic_coverage(kind) && !traps_every_panic) {
        for (let panic in panics_not_trapped(ctx, trapped_panics)) {
            missing.push(ty_spell(plain_finalized(ctx, panic), infer_ctx_viewpoint(ctx)));
        }
    }
    if (missing.length() == 0) {
        return;
    }
    // Rust's `sort` then `dedup`.
    let deduped: string[] = [];
    for (
        let text in missing.sort_by_key((text) -> {
            text
        })
    ) {
        if (deduped.at(deduped.length() - 1) != text) {
            deduped.push(text);
        }
    }
    report(
        ctx,
        PendingDiagNonExhaustiveCatchAll {
            expr: at,
            keyword: root.ast.catch_clause_kind_keyword(kind),
            caught: caught,
            missing: deduped,
        },
    );
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::every_panic @ d9be6853b
// `baml.panics.Panic`, the alias naming every panic class.
function every_panic(ctx: InferenceContext) -> int? throws never {
    let alias = lang_decl(ctx, root.base.LangPackage.Baml, ["panics"], "Panic")
        ?? return null;
    ctx.table.pool.add(root.types.TyTypeAlias { name: alias })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::panics_not_trapped @ d9be6853b
// The `baml.panics.*` classes no type in `trapped` covers. When none is
// covered, the single `baml.panics.Panic` alias stands for them all.
function panics_not_trapped(ctx: InferenceContext, trapped: int[]) -> int[] throws never {
    let pool = ctx.table.pool;
    let alias = every_panic(ctx)
        ?? return [];
    let every = expand_alias_ty(ctx, alias);
    let members = match (pool.kinds[every]) {
        let u: root.types.InferTyUnion => u.members,
        root.types.InferTyClass => [every],
        _ => {
            return [];
        },
    };
    if (trapped.length() == 0) {
        return [alias];
    }
    let trapped_ty = union_of(ctx, trapped);
    members.filter((panic) -> {
        !provable_subtype(ctx, panic, trapped_ty)
    })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::panic_subset @ d9be6853b
// The `baml.panics.*` component of a catch claim (alias-aware, union
// members collected): the types an arm may always trap.
function panic_subset(ctx: InferenceContext, claim: int) -> int? throws never {
    let expanded = expand_alias_ty(ctx, claim);
    match (ctx.table.pool.kinds[expanded]) {
        let c: root.types.InferTyClass
            if root.types.decl_name_is_panic_type(c.name, infer_ctx_lang(ctx)) => {
            expanded
        },
        let u: root.types.InferTyUnion => {
            let panics = u.members.filter_map((member) -> {
                panic_subset(ctx, member)
            });
            if (panics.length() == 0) {
                null
            } else {
                union_of(ctx, panics)
            }
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::non_panic_subset @ d9be6853b
// The non-`baml.panics.*` component of a thrown type: what a `throw`
// actually contributes to the channel, the complement of `panic_subset`.
// Null means the type was panics all the way down.
function non_panic_subset(ctx: InferenceContext, ty: int) -> int? throws never {
    let expanded = expand_alias_ty(ctx, ty);
    match (ctx.table.pool.kinds[expanded]) {
        let c: root.types.InferTyClass
            if root.types.decl_name_is_panic_type(c.name, infer_ctx_lang(ctx)) => {
            null
        },
        let u: root.types.InferTyUnion => {
            let rest = u.members.filter_map((member) -> {
                non_panic_subset(ctx, member)
            });
            if (rest.length() == 0) {
                null
            } else {
                union_of(ctx, rest)
            }
        },
        _ => expanded,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finalize_incoming_effect @ d9be6853b
// A caught effect contribution, resolved for the error channel. A `catch`
// needs the facts of the effect now, so a still-open effect class commits
// from the evidence it has, including evidence in the bounds of another
// open class (`force_classes_naming`). A class still open afterwards reads
// as `never` and drops out of a union, so the facts beside it stay. (Rust
// notes a known gap here: an explicit type parameter in throws position
// with two unrelated lower bounds stays open and reads as `never`.)
function finalize_incoming_effect(ctx: InferenceContext, ty: int) -> int throws never {
    let pool = ctx.table.pool;
    let resolved = force_occurring_vars(ctx, ty);
    while (pool.has_infer(resolved) && force_classes_naming(ctx, resolved)) {
        resolved = force_occurring_vars(ctx, resolved);
    }
    if (!pool.has_infer(resolved)) {
        return resolved;
    }
    match (pool.kinds[resolved]) {
        let u: root.types.InferTyUnion => {
            let known = u.members.filter((member) -> {
                !pool.has_infer(member)
            });
            if (known.length() == 0) {
                pool.add(root.types.TyNever {})
            } else {
                union_of(ctx, known)
            }
        },
        _ => pool.add(root.types.TyNever {}),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::force_classes_naming @ d9be6853b
// One round of the finish fixpoint for the classes that hold evidence about
// `ty`: commits every open class whose bounds name an inference var of
// `ty`, and no other class, then relates the bounds of solved classes
// against their solutions and re-drives the deferred residue. Returns
// whether anything progressed.
function force_classes_naming(ctx: InferenceContext, ty: int) -> bool throws never {
    let pool = ctx.table.pool;
    let named: int[] = [];
    collect_infer_vars(pool, ty, named);
    let progressed = false;
    for (let entry in ctx.table.unsolved_bounded_vars()) {
        let var = entry.0;
        let bounds = entry.1;
        if (named.includes(var)) {
            continue;
        }
        let names_one = bounds.lowers.concat(bounds.uppers).some((bound) -> {
            let in_bound: int[] = [];
            collect_infer_vars(pool, ctx.table.resolve_completely(bound.ty), in_bound);
            in_bound.some((v) -> {
                named.includes(v)
            })
        });
        if (names_one && try_solve_bounded_var(ctx, var, bounds)) {
            progressed = true;
        }
    }
    // Not short-circuited: both steps must run in a round.
    let replayed = replay_solved_class_bounds(ctx);
    let drained = drain_deferred_subs(ctx);
    progressed || replayed || drained
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_needless_chain @ d9be6853b
// A `?.` link whose base PROVABLY cannot be null is noise the user probably
// didn't intend. Error/var bases stay silent as cascades; an optional link
// inside a chain sees its base already peeled, so only the outermost
// truly-non-null base fires.
function check_needless_chain(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    base: int,
    base_ty: int,
) -> void throws never {
    let pool = ctx.table.pool;
    let resolved = ctx.table.resolve_completely(base_ty);
    if (pool.has_error(resolved) || pool.has_infer(resolved)) {
        return;
    }
    let structure = structurally_resolve(ctx, resolved);
    let nullable = match (pool.kinds[structure]) {
        root.types.TyNull | root.types.TyUnknown => true,
        let u: root.types.InferTyUnion => {
            u.members.some((member) -> {
                pool.kinds[member] is root.types.TyNull
            })
        },
        _ => false,
    };
    let base_is_chain = match (body.exprs[base]) {
        root.ast.ExprOptionalMemberAccess | root.ast.ExprOptionalCall => true,
        _ => false,
    };
    if (!nullable && !base_is_chain) {
        report(
            ctx,
            PendingDiagUnnecessaryOptionalChain {
                expr: expr,
                expr_text: body.display_expr(expr),
                base_text: body.display_expr(base),
            },
        );
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_tag_values @ d9be6853b
// A tag takes its values as they are, `null` among them. One that can only
// ever be `null` is an expression written for its effect: as a value it is
// refused, as it is in an untagged template.
function check_tag_values(ctx: InferenceContext, body: root.ast.ExprBody) -> void throws never {
    let pool = ctx.table.pool;
    for (let value in body.tag_values) {
        let ty = ctx.result.type_of_expr.get(value);
        if (ty == null) {
            continue;
        }
        let resolved = ctx.table.resolve_completely(ty);
        if (pool.has_error(resolved) || pool.has_infer(resolved)) {
            continue;
        }
        if (cached_equivalent(ctx, resolved, pool.add(root.types.TyNull {}))) {
            report(ctx, PendingDiagInterpolatedMaybeNull { expr: value, ty: resolved });
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_template_interps_strict @ d9be6853b
// Every `${expr}` in an UNTAGGED template must be non-nullable (implicit
// `.to_string()` on null has no sound rendering), and must not render an
// `ai.Role`. Nested `${for}`/`${if}` segments walk recursively.
function check_template_interps_strict(
    ctx: InferenceContext,
    segments: root.ast.TemplateSegment[],
) -> void throws never {
    let pool = ctx.table.pool;
    for (let segment in segments) {
        match (segment) {
            let interp: root.ast.TemplateSegmentInterp => {
                let expr = interp.value;
                let ty = ctx.result.type_of_expr.get(expr);
                if (ty == null) {
                    continue;
                }
                let resolved = ctx.table.resolve_completely(ty);
                if (pool.has_error(resolved) || pool.has_infer(resolved)) {
                    continue;
                }
                let nullable = match (pool.kinds[resolved]) {
                    root.types.TyNull => true,
                    let u: root.types.InferTyUnion => {
                        u.members.some((member) -> {
                            pool.kinds[member] is root.types.TyNull
                        })
                    },
                    _ => false,
                };
                if (nullable) {
                    report(ctx, PendingDiagInterpolatedMaybeNull { expr: expr, ty: resolved });
                } else if (holds_role_marker(ctx, resolved, ROLE_MARKER_FUEL)) {
                    report(ctx, PendingDiagInterpolatedRoleMarker { expr: expr, ty: resolved });
                }
            },
            let f: root.ast.TemplateSegmentFor => {
                check_template_interps_strict(ctx, f.body);
            },
            let f: root.ast.TemplateSegmentCStyleFor => {
                check_template_interps_strict(ctx, f.body);
            },
            let i: root.ast.TemplateSegmentIf => {
                for (let branch in i.branches) {
                    check_template_interps_strict(ctx, branch.body);
                }
                let else_body = i.else_body;
                if (else_body != null) {
                    check_template_interps_strict(ctx, else_body);
                }
            },
            // Text, and an interpolation with no value to refuse.
            root.ast.TemplateSegmentText | root.ast.TemplateSegmentEffect => {},
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::holds_role_marker @ d9be6853b
// Whether stringifying `ty` would render an `ai.Role` as text: the type is
// `ai.Role` or holds it through a union, list, map value, or type alias.
// Fuel bounds recursive aliases such as `baml.json.json`.
function holds_role_marker(ctx: InferenceContext, ty: int, fuel: int) -> bool throws never {
    if (fuel == 0) {
        return false;
    }
    let expanded = expand_alias_ty(ctx, ty);
    match (ctx.table.pool.kinds[expanded]) {
        let c: root.types.InferTyClass => {
            root.types.decl_name_is_lang_root_type(
                c.name,
                infer_ctx_lang(ctx),
                root.base.LangPackage.Ai,
                "Role",
            )
        },
        let u: root.types.InferTyUnion => {
            u.members.some((member) -> {
                holds_role_marker(ctx, member, fuel - 1)
            })
        },
        let l: root.types.InferTyList => holds_role_marker(ctx, l.elem, fuel - 1),
        let m: root.types.InferTyMap => holds_role_marker(ctx, m.value, fuel - 1),
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::judge_throws_contract_coverage @ d9be6853b
// E0097 judges only explicit, closed clauses, at their body roots.
// Contextual expectations constrain effects but do not claim coverage.
function judge_throws_contract_coverage(
    ctx: InferenceContext,
    contract: ThrowsContract,
) -> void throws never {
    let pool = ctx.table.pool;
    let declared = contract.declared;
    let at = contract.at;
    if (pool.has_error(declared)) {
        return;
    }
    let is_open_contract = is_open_throws_contract(ctx.db, declared);
    // Coverage compares WIDENED facts (a thrown `"boom"` covers a declared
    // `string`) while the report keeps the declared spelling. An open union
    // needs its preserved written surface: finalizing `unknown | SomeError`
    // canonicalizes it to `unknown` and erases `SomeError`.
    let declared_for_coverage = if (is_open_contract) {
        rendered_plain(pool, declared)
    } else {
        plain_finalized(ctx, declared)
    };
    let declared_facts = flatten_ty_to_facts(declared_for_coverage);
    let effective = ty_btree_set(
        contract.contributions.flat_map((contribution) -> {
            flatten_declared_ty_to_facts(plain_finalized(ctx, contribution.1))
        }),
    );
    // A contribution typed by a block-scoped binding was judged at its
    // throw; the clause outside cannot name it, so what the clause may say
    // about it is its NEAREST RELAXATION. Coverage judges declared facts
    // against those relaxations too.
    let relaxed = ty_btree_set(
        effective
            .filter((fact) -> {
                mentions_scoped_param(fact)
            })
            .flat_map((fact) -> {
                flatten_declared_ty_to_facts(nearest_scoped_relaxation(fact, RelaxationVariance.Covariant))
            }),
    );
    if (is_open_contract) {
        // A declared `unknown` is precise exactly when something thrown
        // relaxes to nothing closer than `unknown` itself.
        let throws_unknown = effective.some((ty) -> {
            is_open_throws_contract(ctx.db, pool.from_plain(ty))
        })
            || relaxed.some((ty) -> {
                ty is root.types.TyUnknown
            });
        if (!throws_unknown) {
            // Report what the clause SHOULD say: a scoped contribution by
            // its relaxation, everything else as is.
            let inferred = throws_clause_union(
                effective
                    .filter((fact) -> {
                        !mentions_scoped_param(fact)
                    })
                    .concat(relaxed),
            );
            report(
                ctx,
                PendingDiagImpreciseUnknownThrows {
                    at: at,
                    inferred: inferred,
                    needs_declaration: relaxed.length() > 0,
                },
            );
            return;
        }
    }
    // A meaningful `unknown` (including aliases) is not extraneous, but
    // uncovered named members of its union still are.
    let extra_types = declared_facts
        .filter((decl) -> {
            let covered = flatten_declared_ty_to_facts(decl).every((leaf) -> {
                effective.includes(leaf) || relaxed.includes(leaf)
            });
            !(
                covered
                    || decl is root.types.TyInterface
                    && effective.some((eff) -> {
                        ctx.facts.is_subtype(eff, decl)
                    })
            )
        })
        .filter((ty) -> {
            !is_open_contract || !is_open_throws_contract(ctx.db, pool.from_plain(ty))
        })
        .map((ty) -> {
            ty_spell(ty, infer_ctx_viewpoint(ctx))
        })
        .sort_by_key((text) -> {
            text
        });
    if (extra_types.length() > 0) {
        report(ctx, PendingDiagExtraneousThrows { at: at, extra_types: extra_types });
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_throws_contribution @ d9be6853b
// Ground contributions constrain written holes immediately. Open
// contributions must wait for writeback rather than acquiring an upper
// bound from the contract that could block callback effect inference.
function check_throws_contribution(
    ctx: InferenceContext,
    at: int,
    contribution: int,
    declared: int,
) -> void throws never {
    let pool = ctx.table.pool;
    // Written names can publish scoped effects without depositing them into
    // an open remainder minted outside the binding's scope.
    if (
        escaping_scoped_param(ctx, contribution) != null
            && declared_name_publishes(ctx, contribution, declared)
    ) {
        return;
    }
    if (
        !pool.has_error(declared)
            && (pool.has_infer(contribution) || !sub(ctx, contribution, declared))
    ) {
        report(ctx, PendingDiagThrowsViolation { at: at, declared: declared, extra: contribution });
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::record_throw @ d9be6853b
// One effect contribution: a thrown value or a callee's throws, accumulated
// into the current channel and, when the owner DECLARED a closed clause,
// checked against that contract (including when the clause mentions rigid
// type vars: the check defers through bounds rather than being skipped).
function record_throw(ctx: InferenceContext, at: int, ty: int) -> void throws never {
    let pool = ctx.table.pool;
    if (pool.kinds[ty] is root.types.TyNever || pool.has_error(ty)) {
        return;
    }
    // Panics are RAISED, not thrown: never part of a `throws` contract. A
    // throw whose type mixes panics with ordinary errors contributes only
    // the ordinary half; a throw with no panic records exactly its type.
    // Thrown literals KEEP their literal types (no widening): catch arms
    // match on literal error codes.
    let contribution = ty;
    if (panic_subset(ctx, ty) != null) {
        let rest = non_panic_subset(ctx, ty);
        if (rest == null) {
            return;
        }
        contribution = rest;
    }
    // The owner's closed clause judges each contribution as it comes; an
    // OPEN clause admits every contribution. A lambda's clause judges its
    // channel when it closes.
    let owner_contract = if (ctx.throws_channels.length() == 1) {
        throws_clause_closed(ctx.throws_channels[0].clause)
    } else {
        null
    };
    if (owner_contract != null) {
        check_throws_contribution(ctx, at, contribution, owner_contract);
    }
    ctx.throws_channels[ctx.throws_channels.length() - 1].contributions.push((at, contribution));
}
