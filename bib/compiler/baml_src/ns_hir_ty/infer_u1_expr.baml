// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// Unit 1 of the K4 plan, part two: `infer_expr`, the expression walk.
//
// Restructured (BAML forces it): `infer_expr` stays the dispatcher and
// keeps Rust's epilogue last (the unspecialized-generic report, then the
// `type_of_expr` record); its large arms are `infer_expr_<variant>`
// functions (block, if let, upcast, template, array, map, optional chain),
// each called where Rust's arm sits so every child is inferred in Rust's
// order. Small arms stay inline.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr @ d9be6853b
function infer_expr(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: Expectation,
) -> int throws never {
    let pool = ctx.table.pool;
    let ty = match (body.exprs[expr]) {
        // An `int` literal whose value doesn't fit i63 is rejected in Rust
        // here (E0150). BAML's `int` is i63 and the AST lowering already
        // rejects such a literal (the accepted 63-bit difference), so the
        // literal always fits.
        let e: root.ast.ExprLiteral => {
            pool.add(root.types.TyLiteral { value: e.value, freshness: root.types.Freshness.Fresh })
        },
        root.ast.ExprNull => pool.add(root.types.TyNull {}),
        // A byte-string literal (`b"..."`) IS a `uint8array` value: its own
        // expr kind, not a `Literal` (no literal TYPE per byte-string; TIR
        // agrees).
        root.ast.ExprByteStringLiteral => pool.add(root.types.TyUint8Array {}),
        let e: root.ast.ExprPath => resolve_value_path(ctx, body, expr, e.value.segments, expected),
        let e: root.ast.ExprIndex => infer_index(ctx, body, expr, e.base, e.index, false, false),
        let e: root.ast.ExprAwait => infer_await(ctx, body, expr, e.future),
        let e: root.ast.ExprOptionalIndex => {
            infer_index(ctx, body, expr, e.base, e.index, true, false)
        },
        let e: root.ast.ExprBlock => infer_expr_block(ctx, body, expr, e, expected),
        let e: root.ast.ExprIf => {
            let (_, let facts) = root.hir_ty.infer.check_condition(ctx, body, e.condition);
            infer_if_branches(ctx, body, expr, e.then_branch, e.else_branch, expected, (this, side) -> void {
                root.hir_ty.infer.apply_facts(
                    this,
                    match (side) {
                        IfSide.Then => facts.when_true,
                        IfSide.Else => facts.when_false,
                    },
                );
            })
        },
        let e: root.ast.ExprIfLet => infer_expr_if_let(ctx, body, expr, e, expected),
        // A fully-qualified item reference used as a VALUE. Its own generic
        // suffix is fresh: only a call site can spell a turbofish, exactly as
        // for the two path spellings.
        let e: root.ast.ExprQualifiedPath => {
            qualified_path_value(ctx, expr, e.member, OwnArgsFresh {}, expr)
        },
        let e: root.ast.ExprUpcast => infer_expr_upcast(ctx, body, expr, e),
        // Value-position turbofish (rustc's `let f = identity::<i32>`; r-a's
        // `substs_from_path`): the SAME resolution ladder a call's callee
        // takes, reading the written type args keyed at THIS expression (the
        // `instantiation_args` channel), minus the call. A resolved METHOD
        // binds its receiver like any instance-accessed method value.
        let e: root.ast.ExprGenericApply => {
            let (let fn_ty, let bound) = infer_callee(ctx, body, expr, e.base);
            if (bound) {
                bind_receiver(pool, fn_ty)
            } else {
                fn_ty
            }
        },
        let e: root.ast.ExprTemplate => infer_expr_template(ctx, body, e),
        let e: root.ast.ExprArray => infer_expr_array(ctx, body, expr, e, expected),
        let e: root.ast.ExprTuple => {
            let slots = expected_tuple_elements(ctx, expected, e.elements.length());
            if (slots != null) {
                for (let i = 0; i < e.elements.length() && i < slots.length(); i += 1) {
                    check_expr(ctx, body, e.elements[i], slots[i]);
                }
                pool.add(root.types.InferTyTuple { items: slots })
            } else {
                let element_tys = e.elements.map((element) -> int {
                    let element_ty = infer_expr(ctx, body, element, ExpectationNone {});
                    widen_fresh(ctx, element_ty)
                });
                pool.add(root.types.InferTyTuple { items: element_tys })
            }
        },
        let e: root.ast.ExprMap => infer_expr_map(ctx, body, expr, e, expected),
        let e: root.ast.ExprReturn => {
            infer_return(ctx, body, e.value, DiagnosticLocationExpr { value: expr });
            root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
            pool.add(root.types.TyNever {})
        },
        let e: root.ast.ExprThrow => {
            infer_throw(ctx, body, e.value);
            root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
            pool.add(root.types.TyNever {})
        },
        let e: root.ast.ExprBinary => infer_binary(ctx, body, expr, expected, e.op, e.lhs, e.rhs),
        let e: root.ast.ExprUnary => infer_unary(ctx, body, e.op, e.expr),
        let e: root.ast.ExprCall => infer_call(ctx, body, expr, e.callee, e.args),
        let e: root.ast.ExprObject => {
            infer_object(ctx, body, expr, expected, e.type_name, e.fields, e.spreads)
        },
        let e: root.ast.ExprMemberAccess => {
            let base_ty = infer_expr(ctx, body, e.base, ExpectationNone {});
            field_access(ctx, expr, base_ty, e.member)
        },
        let e: root.ast.ExprOptionalChain => infer_expr_optional_chain(ctx, body, e),
        let e: root.ast.ExprOptionalMemberAccess => {
            let base_ty = infer_expr(ctx, body, e.base, ExpectationNone {});
            check_needless_chain(ctx, body, expr, e.base, base_ty);
            let nonnull = peel_chain_null(ctx, base_ty);
            field_access(ctx, expr, nonnull, e.member)
        },
        let e: root.ast.ExprOptionalCall => {
            let callee_ty = with_suppressed(ctx, Suppress.OptionalCallee, (this) -> int {
                infer_expr(this, body, e.callee, ExpectationNone {})
            });
            report_mounted_reserved_call(ctx, expr, e.callee);
            check_needless_chain(ctx, body, expr, e.callee, callee_ty);
            let nonnull = peel_chain_null(ctx, callee_ty);
            check_call_args(ctx, body, expr, e.callee, nonnull, false, e.args)
        },
        let e: root.ast.ExprLambda => infer_lambda(ctx, body, expr, e.value, expected),
        let e: root.ast.ExprMatch => {
            root.hir_ty.infer.infer_match(ctx, body, expr, e.scrutinee, e.arms, expected)
        },
        let e: root.ast.ExprIs => {
            root.hir_ty.infer.infer_is(
                ctx,
                body,
                e.scrutinee,
                e.pattern,
                root.hir_ty.infer.TestPosition.Value,
            ).0
        },
        let e: root.ast.ExprCatch => infer_catch(ctx, body, expr, e.base, e.clause, expected),
        // The parse-recovery hole: no children in practice; the generic
        // visit stays as recovery if that ever changes.
        root.ast.ExprMissing => {
            let children: root.ast.BodyNode[] = [];
            body.expr_children(expr, children);
            for (let node in children) {
                match (node) {
                    let child: root.ast.BodyNodeExpr => {
                        infer_expr(ctx, body, child.value, ExpectationNone {});
                    },
                    let child: root.ast.BodyNodeStmt => infer_stmt(ctx, body, child.value),
                }
            }
            pool.add(root.types.TyError {})
        },
    };
    report_unspecialized_generic_method_value(ctx, body, expr, expected, ty);
    ctx.result.type_of_expr.set(expr, ty);
    ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr (the `Expr::Block` arm) @ d9be6853b
function infer_expr_block(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    block: root.ast.ExprBlock,
    expected: Expectation,
) -> int throws never {
    let pool = ctx.table.pool;
    let type_scope = ctx.scoped_type_bindings.length();
    let entry_diverges = root.hir_ty.infer.diverges(ctx);
    ctx.block_defer_writes.push({});
    let deferred_diverges = false;
    for (let stmt in block.stmts) {
        if let deferred: root.ast.StmtDefer = body.stmts[stmt] {
            let writes = root.hir_ty.infer.assigned_bindings(ctx, body, deferred.body);
            let armed = ctx.block_defer_writes[ctx.block_defer_writes.length() - 1];
            for (let binding in writes.keys()) {
                armed.set(binding, true);
            }
        }
        infer_stmt(ctx, body, stmt);
        if let deferred: root.ast.StmtDefer = body.stmts[stmt] {
            let deferred_ty = ctx.result.type_of_expr.get(deferred.body);
            if (deferred_ty != null && pool.kinds[deferred_ty] is root.types.TyNever) {
                deferred_diverges = true;
            }
        }
    }
    let tail = block.tail_expr;
    let ty = if (tail != null) {
        let tail_ty = infer_expr(ctx, body, tail, expected);
        let units = take_units(ctx, tail);
        if (units.length() > 0) {
            ctx.unjudged_units.set(expr, units);
        }
        tail_ty
    } else if (
        deferred_diverges
            || (
                root.hir_ty.infer.diverges(ctx) == Diverges.Always
                    && entry_diverges == Diverges.Maybe
            )
    ) {
        // A tail-less block that always diverged (in its statements, or in a
        // `defer` it registered, which runs before the block yields) is
        // never; otherwise it is an implicit unit.
        pool.add(root.types.TyNever {})
    } else {
        let last = block.stmts.at(block.stmts.length() - 1);
        let last_value: (int, int)? = if (last != null) {
            match (body.stmts[last]) {
                let s: root.ast.StmtExpr => (last, s.value),
                _ => null,
            }
        } else {
            null
        };
        let verdict = unit_verdict(ctx, expectation_only_has_type(expected));
        implicit_unit(ctx, expr, UnitSiteFormBlockWithoutTail { last_value: last_value }, verdict)
    };
    // Defers run after the tail value is evaluated. Their writes may change
    // outer locals before the enclosing code resumes.
    let deferred_writes = ctx.block_defer_writes.pop() ?? baml.sys.panic("pushed above");
    for (let binding in deferred_writes.keys()) {
        ctx.flow.delete(binding);
    }
    let settled = if (deferred_diverges) {
        root.hir_ty.infer.set_diverges(ctx, Diverges.Always);
        ctx.unjudged_units.delete(expr);
        pool.add(root.types.TyNever {})
    } else {
        ty
    };
    finish_scoped_type_bindings(ctx, body, type_scope, expr, tail, settled, expected)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr (the `Expr::IfLet` arm) @ d9be6853b
// `if let PAT = scrut`: the pattern types its bindings, the then-branch sees
// the scrutinee narrowed to the matched type, the else-branch the RESIDUAL
// (consumes-gated); branch join and the divergence-aware merge follow the
// `if` arm.
function infer_expr_if_let(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    if_let: root.ast.ExprIfLet,
    expected: Expectation,
) -> int throws never {
    let scrut_ty = infer_expr(ctx, body, if_let.scrutinee, ExpectationNone {});
    let scrut = root.hir_ty.infer.scrutinee_demand(ctx, scrut_ty);
    let outcome = root.hir_ty.infer.lower_pattern(ctx, body, if_let.pattern, scrut);
    let binding = root.hir_ty.infer.narrowable_binding(ctx, body, if_let.scrutinee);
    infer_if_branches(ctx, body, expr, if_let.then_branch, if_let.else_branch, expected, (
        this,
        side,
    ) -> void {
        let narrowed = binding
            ?? return;
        match (side) {
            IfSide.Then => {
                this.flow.set(narrowed, outcome.matched_ty);
            },
            IfSide.Else => {
                if (outcome.consumes_matched) {
                    let residual = root.hir_ty.infer.subtract_narrow(this, scrut, outcome.matched_ty);
                    this.flow.set(narrowed, residual);
                }
            },
        }
    })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr (the `Expr::Upcast` arm) @ d9be6853b
// Rust's qualified trait path (`<X as Parent<i32>>`, r-a's trait-object
// coercion): the value viewed through a WRITTEN interface. The base proves
// the view (ground pairs through the implements oracle, var-carrying
// targets as an Implements obligation anchored HERE) and the result IS the
// target, so members flow through the existential road with exactly the
// requested args/pins (what disambiguates same-name members across
// instantiations). Interface views only (TIR's rule).
function infer_expr_upcast(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    upcast: root.ast.ExprUpcast,
) -> int throws never {
    let pool = ctx.table.pool;
    let base_ty = infer_expr(ctx, body, upcast.base, ExpectationNone {});
    let target_ref = ctx.type_refs.upcast_targets.get(expr);
    let written = if (target_ref != null) {
        let (let lowered, let diagnostics) = lower_body_type_ref_at(ctx, target_ref, TypePosition.Existential, HolePolicyAllowed {});
        queue_body_lowering_diagnostics(ctx, diagnostics);
        reject_expr_position_holes(ctx, lowered, expr)
    } else {
        pool.add(root.types.TyError {})
    };
    // The interface-view gate is a STRUCTURE demand: an alias naming an
    // interface answers as the interface.
    let target = expand_alias_ty(ctx, written);
    if (pool.has_error(target)) {
        return pool.add(root.types.TyError {});
    }
    if (!(pool.kinds[target] is root.types.InferTyInterface)) {
        report(ctx, PendingDiagQualifierNotInterface { expr: expr, target: target });
        return pool.add(root.types.TyError {});
    }
    let saved_anchor = ctx.obligation_anchor;
    ctx.obligation_anchor = expr;
    let fits = sub(ctx, base_ty, target);
    ctx.obligation_anchor = saved_anchor;
    if (!fits) {
        // The dedicated form: the value's type does not implement the
        // requested interface, clearer than the generic mismatch.
        report(
            ctx,
            PendingDiagDoesNotImplement {
                expr: expr,
                value: base_ty,
                interface_: target,
                required_for: [],
            },
        );
    }
    target
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr (the `Expr::Template` arm) @ d9be6853b
function infer_expr_template(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    template: root.ast.ExprTemplate,
) -> int throws never {
    let pool = ctx.table.pool;
    let custom = match (template.tag) {
        let tag: root.ast.TemplateTagDefault => {
            // Untagged backtick: the value IS the desugared
            // `string.from`-wrapped `+` concat, which types every `${expr}`
            // in place on its original span.
            let result = infer_expr(ctx, body, tag.elaborated, ExpectationNone {});
            // Strict stringify: a NULLABLE interpolated value errors at check
            // time (the structured segments exist exactly for these
            // per-`${...}` diagnostics on the original spans).
            check_template_interps_strict(ctx, template.segments);
            return result;
        },
        let tag: root.ast.TemplateTagCustom => tag,
    };
    // Tagged template: the result is the TAG fn's return type (`prompt`
    // yields the `(Context) -> PromptAst` render closure). The desugared
    // flatten block types under the template's synthetic Lambda scope with
    // the tag's body-lambda params name-visible; its effects and divergence
    // stay the deferred closure's, not the enclosing function's (the
    // `infer_lambda` discipline).
    let tag_ty = infer_expr(ctx, body, custom.tag, ExpectationNone {});
    let resolved = ctx.table.resolve_completely(tag_ty);
    let written_name = match (body.exprs[custom.tag]) {
        let path: root.ast.ExprPath => path.value.segments.at(path.value.segments.length() - 1),
        _ => null,
    };
    let tag_name = written_name ?? "<tag>";
    let error = pool.add(root.types.TyError {});
    // Tag validation (TIR's rules): the tag must be a
    // `//baml:tagged_string`-marked function whose first parameter is
    // `body: (...) -> baml.TaggedString`. The body-lambda params scope into
    // the interpolations only when the tag validated; an unresolved tag
    // already reported UnresolvedName and stays quiet here.
    let (let result, let template_params) = match (pool.kinds[resolved]) {
        let function_: root.types.InferTyFunction => {
            let func = match (ctx.result.member_resolutions.get(custom.tag)) {
                let free: MemberResolutionFree => free.func,
                _ => null,
            };
            let is_tagged = func != null && root.hir.function_data(ctx.db, func).is_tagged_template_tag;
            let first = function_.params.at(0);
            let body_params = if (first != null && first.name == "body") {
                body_lambda_params(ctx, first.ty)
            } else {
                null
            };
            if (!is_tagged) {
                report(
                    ctx,
                    PendingDiagTaggedTagInvalid {
                        at: custom.tag,
                        name: tag_name,
                        func: func,
                        kind: TaggedTagIssue.NotMarked,
                    },
                );
                (error, {})
            } else if (body_params == null) {
                report(
                    ctx,
                    PendingDiagTaggedTagInvalid {
                        at: custom.tag,
                        name: tag_name,
                        func: func,
                        kind: TaggedTagIssue.BadBodyParam,
                    },
                );
                (error, {})
            } else {
                let params: map<string, int> = {};
                for (let param in body_params) {
                    let name = param.name;
                    if (name != null) {
                        params.set(name, param.ty);
                    }
                }
                (function_.ret, params)
            }
        },
        // Unresolved: `UnresolvedName` already reported for a bare-path tag;
        // no double report.
        _ if pool.has_error(resolved) => (error, {}),
        _ => {
            report(
                ctx,
                PendingDiagTaggedTagInvalid {
                    at: custom.tag,
                    name: tag_name,
                    func: null,
                    kind: TaggedTagIssue.NotAFunction,
                },
            );
            (error, {})
        },
    };
    // NO scope switch: the builder marks the template's Lambda scope
    // `is_template_body` (a capture boundary for MIR), but its expressions
    // register in the ENCLOSING metadata namespace (TIR's
    // `inference_owner_scope` climbs past it the same way). Entering it here
    // would key every lookup into a namespace nothing was registered under.
    root.hir_ty.infer.enter_frame(
        ctx,
        root.hir_ty.infer.FrameKindTemplate { params: template_params },
    );
    ctx.throws_channels.push(ThrowsChannel { clause: ThrowsClauseInferred {}, contributions: [] });
    infer_expr(ctx, body, custom.body, ExpectationNone {});
    // The tag's `body` param declares the flatten block's effect contract
    // (`throws never` for `prompt`); the contract diagnostic is S17's, so the
    // channel drops.
    ctx.throws_channels.pop();
    root.hir_ty.infer.leave_frame(ctx);
    result
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr (the tagged-template `body_param_ok` test) @ d9be6853b
// The tag's first parameter type, when it is a function returning
// `baml.TaggedString`: that function's parameters, which become the
// template's body-lambda params. Restructured: Rust tests the shape and
// then destructures the same type again; this answers both at once.
function body_lambda_params(
    ctx: InferenceContext,
    param_ty: int,
) -> root.types.InferFunctionParamTy[]? throws never {
    let pool = ctx.table.pool;
    let body_fn = match (pool.kinds[param_ty]) {
        let f: root.types.InferTyFunction => f,
        _ => {
            return null;
        },
    };
    match (pool.kinds[body_fn.ret]) {
        let class_: root.types.InferTyClass
            if root.types.decl_name_is_lang_root_type(
            class_.name,
            infer_ctx_lang(ctx),
            root.base.LangPackage.Baml,
            "TaggedString",
        ) => {
            body_fn.params
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr (the `Expr::Array` arm) @ d9be6853b
// With an expected element type, elements are CHECKED against it;
// otherwise they synthesize and JOIN (fresh literals widening at the join,
// per the generation-site rule).
function infer_expr_array(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    array: root.ast.ExprArray,
    expected: Expectation,
) -> int throws never {
    let pool = ctx.table.pool;
    let element_ty = expected_list_element(ctx, expected);
    if (element_ty != null) {
        for (let element in array.elements) {
            check_expr(ctx, body, element, element_ty);
        }
        return pool.add(root.types.InferTyList { elem: element_ty });
    }
    if (array.elements.length() == 0) {
        // `[]`: a list over a fresh element variable, the honest replacement
        // for TIR's evolving-list sentinel.
        return untyped_empty_container_ty(ctx, expr, (element) -> int {
            pool.add(root.types.InferTyList { elem: element })
        });
    }
    let joined = array.elements.map((element) -> int {
        let ty = infer_expr(ctx, body, element, ExpectationNone {});
        widen_fresh(ctx, ty)
    });
    let parts: (int, UnitSite[])[] = [];
    for (let i = 0; i < array.elements.length(); i += 1) {
        parts.push((joined[i], take_units(ctx, array.elements[i])));
    }
    join_units(ctx, parts, ExpectationNone {});
    // TS's best-common-type adoption (rustc likewise unifies vec elements;
    // E0282 needs NO evidence): an element still carrying inference vars
    // takes the join of its GROUND siblings as an upper bound, so
    // `[[1], []]` is `int[][]`: the empty list's element solves from the
    // siblings instead of erasing under the rustc-strict rule, which remains
    // for genuinely unconstrained literals (`[[], []]` has no evidence and
    // stays strict).
    let ground: int[] = [];
    let open: int[] = [];
    for (let ty in joined) {
        if (pool.has_infer(ctx.table.resolve_completely(ty))) {
            open.push(ty);
        } else {
            ground.push(ty);
        }
    }
    if (ground.length() > 0 && open.length() > 0) {
        let evidence = join(ctx, ground);
        for (let ty in open) {
            sub(ctx, ty, evidence);
        }
    }
    pool.add(root.types.InferTyList { elem: union_of(ctx, joined) })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr (the `Expr::Map` arm) @ d9be6853b
// With an expected map type, entries are CHECKED against its key/value (the
// array rule; r-a's expectation-driven literal typing): `{"input": s}` in a
// `map<string, unknown>` position IS that map, not a synthesized
// `map<string, string>` tripping invariance.
function infer_expr_map(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    map_expr: root.ast.ExprMap,
    expected: Expectation,
) -> int throws never {
    let pool = ctx.table.pool;
    let expected_entry = expected_map_entry(ctx, expected);
    if (expected_entry != null) {
        let (let key_ty, let value_ty) = expected_entry;
        for (let entry in map_expr.entries) {
            check_expr(ctx, body, entry.key, key_ty);
            check_expr(ctx, body, entry.value, value_ty);
        }
        return pool.add(root.types.InferTyMap { key: key_ty, value: value_ty });
    }
    if (map_expr.entries.length() == 0) {
        let key = ctx.table.new_var_ty(policy = root.hir_ty.infer.VarPolicy.MapKeySlot);
        return untyped_empty_container_ty(ctx, expr, (value) -> int {
            pool.add(root.types.InferTyMap { key: key, value: value })
        });
    }
    let keys: int[] = [];
    let values: int[] = [];
    for (let entry in map_expr.entries) {
        let key_ty = infer_expr(ctx, body, entry.key, ExpectationNone {});
        let value_ty = infer_expr(ctx, body, entry.value, ExpectationNone {});
        keys.push(widen_fresh(ctx, key_ty));
        values.push(widen_fresh(ctx, value_ty));
    }
    let key_parts: (int, UnitSite[])[] = [];
    for (let i = 0; i < map_expr.entries.length(); i += 1) {
        key_parts.push((keys[i], take_units(ctx, map_expr.entries[i].key)));
    }
    join_units(ctx, key_parts, ExpectationNone {});
    let value_parts: (int, UnitSite[])[] = [];
    for (let i = 0; i < map_expr.entries.length(); i += 1) {
        value_parts.push((values[i], take_units(ctx, map_expr.entries[i].value)));
    }
    join_units(ctx, value_parts, ExpectationNone {});
    pool.add(root.types.InferTyMap { key: union_of(ctx, keys), value: union_of(ctx, values) })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_expr (the `Expr::OptionalChain` arm) @ d9be6853b
// TS short-circuit chains: the boundary owns the `| null`, and is where the
// links skipped by a null base rejoin the flow.
function infer_expr_optional_chain(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    chain: root.ast.ExprOptionalChain,
) -> int throws never {
    ctx.chains.push(ChainFrame { nullable: false, skip: null });
    let ty = infer_expr(ctx, body, chain.expr, ExpectationNone {});
    let frame = ctx.chains.pop() ?? baml.sys.panic("pushed above");
    let skip = frame.skip ?? baml.sys.panic("an `OptionalChain` wraps at least one `?.` link");
    let reassigned = root.hir_ty.infer.assigned_bindings(ctx, body, chain.expr);
    root.hir_ty.infer.rejoin_skipped(ctx, skip, reassigned);
    if (frame.nullable) {
        union_of(ctx, [ty, ctx.table.pool.add(root.types.TyNull {})])
    } else {
        ty
    }
}
