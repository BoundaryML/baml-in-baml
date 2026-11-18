// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// Unit 1 of the K4 plan, part five: `let` statements and assignments
// (`infer_let`, `infer_assign`, the assignment-target check, pattern
// ascriptions and the `let ... else` tail).

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_let @ d9be6853b
// The `let` rule: with an annotation, the initializer is CHECKED against it
// (`_` holes as fresh vars, filled by the resulting bounds); without one,
// the initializer synthesizes and fresh literals widen at the binding site.
function infer_let(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    pattern: int,
    initializer: int?,
    else_branch: int?,
) -> void throws never {
    if (else_branch != null) {
        // let-else is REFUTABLE (Rust's let-else): every pattern, the
        // ascribed-bind form (`let o: Ok = r else ..`) included, is a pattern
        // TEST against the synthesized initializer, narrowing to the matched
        // type; the else arm covers the residual, so the initializer is never
        // CHECKED against the written type.
        root.hir_ty.infer.infer_let_destructure(ctx, body, pattern, initializer, true);
        return finish_let_else(ctx, body, else_branch);
    }
    match (body.patterns[pattern]) {
        let bind: root.ast.PatternBind => {
            // The `let` rule decides check-vs-synthesize from the leading
            // ascription alone; the pattern itself then lowers through the
            // ONE recursive walk match arms use (r-a's `infer_top_pat`
            // shape), so chains (`let x: let y`) and structural subpatterns
            // (`let xs: [..]: int[]`) record every binding.
            let subpat = bind.subpat;
            let annotation = if (subpat != null) {
                pattern_ascription_ty(ctx, body, subpat)
            } else {
                null
            };
            let settled = if (annotation != null) {
                if (initializer != null) {
                    check_expr(ctx, body, initializer, annotation);
                }
                annotation
            } else if (initializer != null) {
                let init_ty = infer_expr(ctx, body, initializer, ExpectationNone {});
                widen_fresh(ctx, init_ty)
            } else {
                ctx.table.pool.add(root.types.TyError {})
            };
            root.hir_ty.infer.lower_pattern(ctx, body, pattern, settled);
            finish_let_else(ctx, body, else_branch);
        },
        // Destructures: the pattern walk records each binding's type itself;
        // the let-level entry keeps the initializer type for the pattern
        // node (refutability is S17's diagnostic).
        _ => {
            root.hir_ty.infer.infer_let_destructure(
                ctx,
                body,
                pattern,
                initializer,
                else_branch != null,
            );
            finish_let_else(ctx, body, else_branch);
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_assign @ d9be6853b
// Assignment typing. The value checks against the DECLARED binding type,
// never the narrowed overlay (a narrowed local may be re-assigned anything
// its declaration admits), then the overlay re-narrows to the assigned
// value when it provably fits (the narrow-on-assign rule), else clears to
// declared.
function infer_assign(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    target: int,
    value: int,
    op: root.ast.AssignOp?,
) -> void throws never {
    let pool = ctx.table.pool;
    let place = match (body.exprs[target]) {
        let chain: root.ast.ExprOptionalChain => chain.expr,
        _ => target,
    };
    let member = match (body.exprs[place]) {
        let access: root.ast.ExprMemberAccess => access.member,
        let access: root.ast.ExprOptionalMemberAccess => access.member,
        _ => null,
    };
    // Rust's `member.parse::<u32>().is_ok()`: decimal digits whose value
    // (leading zeros dropped) is at most `u32::MAX`.
    if (member != null && member.is_ascii_numeric()) {
        let significant = root.base.trim_start_matches(member, "0");
        if (significant.length() < 10 || (significant.length() == 10 && significant <= "4294967295")) {
            infer_expr(ctx, body, target, ExpectationNone {});
            infer_expr(ctx, body, value, ExpectationNone {});
            report(ctx, PendingDiagTupleElementAssign { expr: target });
            return;
        }
    }
    // An INDEX target (`xs[0] = v`, `xs[0] += v`): the element type comes
    // from the same `baml.ops.Index` dispatch as a read, the value checks
    // against it (expectation propagation: an empty literal on the right
    // adopts the element type), and a compound op dispatches on (element,
    // value) with the result checked against the element. No binding
    // narrows: the container's declared element type is the contract.
    if let index: root.ast.ExprIndex = body.exprs[target] {
        let element = infer_index(ctx, body, target, index.base, index.index, false, true);
        ctx.result.type_of_expr.set(target, element);
        if (op == null) {
            if (!pool.has_error(element)) {
                check_expr(ctx, body, value, element);
            } else {
                infer_expr(ctx, body, value, ExpectationNone {});
            }
        } else {
            let rhs = infer_expr(ctx, body, value, ExpectationNone {});
            let result = compound_op_result(ctx, value, op, element, rhs);
            if (!pool.has_error(element) && !sub(ctx, result, element)) {
                ctx.result.type_mismatches.set(value, (element, result));
            }
        }
        return;
    }
    let binding = root.hir_ty.infer.narrowable_binding(ctx, body, target);
    let declared = if (binding != null) {
        root.hir_ty.infer.binding_declared_ty(ctx, binding)
    } else {
        null
    };
    // A MEMBER/PLACE target (`a.b[i].f = v`) types as an ordinary place
    // expression (r-a's `infer_assignee_expr` mirrors expression inference
    // for assignee position): the chain's types and resolutions RECORD (MIR's
    // field-slot road resolves the store through them instead of falling to
    // the dynamic string-keyed store) and the place's type is the value's
    // expectation (TIR checks the assigned value against the field type the
    // same way).
    let place_ty = if (binding == null && op == null) {
        infer_expr(ctx, body, target, ExpectationNone {})
    } else {
        null
    };
    let assigned = if (op == null) {
        if (declared != null && !pool.has_error(declared)) {
            check_expr(ctx, body, value, declared)
        } else if (place_ty != null && !pool.has_error(place_ty)) {
            check_expr(ctx, body, value, place_ty)
        } else if (declared != null || place_ty != null) {
            infer_expr(ctx, body, value, ExpectationErroneous {})
        } else {
            infer_expr(ctx, body, value, ExpectationNone {})
        }
    } else {
        // Compound assignment: `target op value` through the same operator
        // machinery, the result checked against declared.
        let written_lhs = if (binding != null) {
            root.hir_ty.infer.binding_flow_ty(ctx, binding)
        } else {
            infer_expr(ctx, body, target, ExpectationNone {})
        };
        // An optional-chain place (`user?.id += 1`) SKIPS on null: the op
        // only runs when the chain produces a value, so it dispatches on the
        // peeled type (the corpus pins the skip semantics).
        let lhs = if (body.exprs[target] is root.ast.ExprOptionalChain) {
            let resolved = structurally_resolve(ctx, written_lhs);
            remove_null(ctx, resolved)
        } else {
            written_lhs
        };
        let rhs = infer_expr(ctx, body, value, ExpectationNone {});
        let result = compound_op_result(ctx, value, op, lhs, rhs);
        if (declared != null && !pool.has_error(declared) && !sub(ctx, result, declared)) {
            ctx.result.type_mismatches.set(value, (declared, result));
        }
        result
    };
    // A top-level binding is written once, by `$init`, and then shared by
    // every call: the binding itself never changes. Only a target that IS
    // the global (`x = v`, `root.ns.x += v`) is refused: `x.f = v` and
    // `x[i] = v` change what the global holds, not the binding.
    if (binding == null) {
        if let path: root.ast.ExprPath = body.exprs[target] {
            let global = ctx.result.global_roots.get(target);
            if (global != null && global.segments == path.value.segments.length()) {
                let data = root.hir.let_data(ctx.db, global.binding);
                report(
                    ctx,
                    PendingDiagAssignmentToGlobal {
                        target: target,
                        name: data.name,
                        is_client: data.origin == root.ast.LetOrigin.Client,
                    },
                );
            }
        }
    }
    if (declared != null) {
        ctx.result.type_of_expr.set(target, declared);
    }
    check_path_assignment_target(ctx, body, target);
    if (binding != null) {
        // The overlay narrows to the assigned value's OWN type (TS narrows
        // assignments to the literal the same way): an assignment is a flow
        // fact, not a binding site, so the binding-site widening does not
        // apply; the fresh literal survives into the overlay and still
        // widens wherever it later reaches a real binding or join.
        let narrowed = ctx.table.resolve_completely(assigned);
        let fits = declared != null && !pool.has_error(declared) && provable_subtype(ctx, narrowed, declared);
        if (fits) {
            ctx.flow.set(binding, narrowed);
        } else {
            ctx.flow.delete(binding);
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_path_assignment_target @ d9be6853b
function check_path_assignment_target(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    target: int,
) -> void throws never {
    let segments = match (body.exprs[target]) {
        let path: root.ast.ExprPath => path.value.segments,
        _ => {
            return;
        },
    };
    if (ctx.result.global_roots.has(target)) {
        return;
    }
    let key = metadata_key(ctx, target);
    let resolution = if (key != null) {
        ctx.index.path_resolution(key)
    } else {
        null
    };
    let resolves_to_local = resolution is root.hir.PathResolutionLocal;
    let target_ty = ctx.result.type_of_expr.get(target);
    if (resolves_to_local || target_ty == null || ctx.table.pool.has_error(target_ty)) {
        return;
    }
    report(ctx, PendingDiagInvalidAssignmentTarget { expr: target, path: segments.join(".") });
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::pattern_ascription_ty @ d9be6853b
// The TYPE a binding's `:`-ascribed sub-pattern denotes, when it is a pure
// type ascription: a `Pattern::Type`, or an OR of type ascriptions
// (`let v: int | string` parses its annotation as an or-pattern, and the
// binding's recorded type is the WRITTEN union: bindings record what the
// user wrote; narrowing is for uses). Structural sub-patterns return null
// (the destructure walk owns those).
function pattern_ascription_ty(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    sub: int,
) -> int? throws never {
    match (body.patterns[sub]) {
        root.ast.PatternType => {
            let type_ref = ctx.type_refs.pattern_types.get(sub)
                ?? return null;
            lower_body_annotation(ctx, type_ref)
        },
        let alternatives: root.ast.PatternOr => {
            let members: int[] = [];
            for (let alt in alternatives.value) {
                if (!(body.patterns[alt] is root.ast.PatternType)) {
                    return null;
                }
                let type_ref = ctx.type_refs.pattern_types.get(alt)
                    ?? return null;
                members.push(lower_body_annotation(ctx, type_ref));
            }
            ctx.table.pool.add(root.types.InferTyUnion { members: members })
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::finish_let_else @ d9be6853b
// The `let ... else` tail, shared by the bind and destructure paths. The
// else branch must diverge; the check itself is an S17 diagnostic. Its
// divergence does not leak past the let.
function finish_let_else(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    else_branch: int?,
) -> void throws never {
    if (else_branch == null) {
        return;
    }
    let pool = ctx.table.pool;
    let saved_flow = root.hir_ty.infer.copy_flow(ctx.flow);
    let saved = root.hir_ty.infer.diverges(ctx);
    root.hir_ty.infer.set_diverges(ctx, Diverges.Maybe);
    let got = infer_expr(ctx, body, else_branch, ExpectationNone {});
    let branch_diverges = root.hir_ty.infer.diverges(ctx);
    root.hir_ty.infer.set_diverges(ctx, saved);
    ctx.flow = saved_flow;
    let resolved = ctx.table.resolve_completely(got);
    if (
        branch_diverges != Diverges.Always
            && !pool.has_error(resolved)
            && !(pool.kinds[resolved] is root.types.TyNever)
    ) {
        report(ctx, PendingDiagLetElseMustDiverge { expr: else_branch, got: got });
    }
}
