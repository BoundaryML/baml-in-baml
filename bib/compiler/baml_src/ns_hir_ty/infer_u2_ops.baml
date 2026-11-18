// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 2, operators: binary and unary operator typing, `await`, indexing,
// ground operator dispatch through the `baml.ops` interfaces (or an operator
// obligation while an operand is open), null peeling and `??`.
//
// Restructured (BAML forces it):
// - Methods of `InferenceContext` are free functions taking `ctx` first;
//   interned types are `int`s into `ctx.table.pool`.
// - `infer_binary`'s arithmetic and bitwise arms, identical in Rust, are one
//   arm.
// - `operand_members`'s nested `fn widen` is a closure.
// - `baml_type_runtime::contains_typevar` is `contains_ty_where` with a
//   `TyTypeVar` test.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_binary @ d9be6853b
// Binary operator typing. Dispatching operators (arithmetic, bitwise,
// ordered comparison) go through the interfaces; the structural ones
// (`&&`/`||` short-circuit control flow, `==`/`!=` structural equality, `??`
// null-algebra) are type algebra, not dispatch.
function infer_binary(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: Expectation,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
) -> int throws never {
    let pool = ctx.table.pool;
    match (op) {
        root.ast.BinaryOp.And => {
            root.hir_ty.infer.infer_short_circuit(
                ctx,
                body,
                root.hir_ty.infer.ShortCircuit.And,
                lhs,
                rhs,
                root.hir_ty.infer.TestPosition.Value,
            ).0
        },
        root.ast.BinaryOp.Or => {
            root.hir_ty.infer.infer_short_circuit(
                ctx,
                body,
                root.hir_ty.infer.ShortCircuit.Or,
                lhs,
                rhs,
                root.hir_ty.infer.TestPosition.Value,
            ).0
        },
        root.ast.BinaryOp.Eq | root.ast.BinaryOp.Ne => {
            let lhs_ty = infer_expr(ctx, body, lhs, ExpectationNone {});
            let rhs_ty = infer_expr(ctx, body, rhs, ExpectationNone {});
            lhs_ty = ctx.table.resolve_completely(lhs_ty);
            rhs_ty = ctx.table.resolve_completely(rhs_ty);
            // Equality folds whenever compile time can DECIDE it: the
            // literal VALUE table first, then the shared algebra's
            // `constant_equality` (false for provably-DISJOINT operands,
            // true for equal unoverridable singletons). Everything else is
            // `bool`.
            let folded = const_fold_binary(pool, op, lhs_ty, rhs_ty);
            if (folded != null) {
                return folded;
            }
            if (
                !pool.has_error(lhs_ty)
                    && !pool.has_error(rhs_ty)
                    && !pool.has_infer(lhs_ty)
                    && !pool.has_infer(rhs_ty)
            ) {
                let equal = ctx.facts.constant_equality(
                    pool.to_plain_closed(lhs_ty),
                    pool.to_plain_closed(rhs_ty),
                );
                if (equal != null) {
                    if (!equal) {
                        // Disjoint operands: the comparison is pointless.
                        report(
                            ctx,
                            PendingDiagComparisonAlwaysDisjoint {
                                at: expr,
                                op: op,
                                lhs: lhs_ty,
                                rhs: rhs_ty,
                            },
                        );
                    }
                    let value = if (op == root.ast.BinaryOp.Eq) {
                        equal
                    } else {
                        !equal
                    };
                    return pool.add(
                        root.types.TyLiteral {
                            value: root.base.LiteralBool { value: value },
                            freshness: root.types.Freshness.Fresh,
                        },
                    );
                }
            }
            pool.add(root.types.TyBool {})
        },
        root.ast.BinaryOp.Lt | root.ast.BinaryOp.Le | root.ast.BinaryOp.Gt | root.ast.BinaryOp.Ge => {
            let lhs_ty = infer_expr(ctx, body, lhs, ExpectationNone {});
            let rhs_ty = infer_expr(ctx, body, rhs, ExpectationNone {});
            lhs_ty = ctx.table.resolve_completely(lhs_ty);
            rhs_ty = ctx.table.resolve_completely(rhs_ty);
            // Exact-type ordering: both operands widen (literal to base,
            // variant to enum) and must be the SAME type, and that type must
            // implement `baml.ops.Compare`. Open/error operands skip
            // (cascades); the `unknown` top type does NOT skip: it orders
            // against nothing, so it reports here.
            if (
                !pool.has_infer(lhs_ty)
                    && !pool.has_infer(rhs_ty)
                    && !pool.has_error(lhs_ty)
                    && !pool.has_error(rhs_ty)
            ) {
                let widen = (ty: int) -> root.types.Ty {
                    let expanded = root.hir_ty.expand_alias_head(ctx.table.pool, ty, ctx.facts);
                    let plain = materialize_ty(ctx, expanded);
                    match (plain) {
                        let l: root.types.TyLiteral => {
                            match (l.value) {
                                root.base.LiteralInt => root.types.TyInt {},
                                root.base.LiteralBigint => root.types.TyBigint {},
                                root.base.LiteralFloat => root.types.TyFloat {},
                                root.base.LiteralString => root.types.TyString {},
                                root.base.LiteralBool => root.types.TyBool {},
                            }
                        },
                        let v: root.types.TyEnumVariant => root.types.TyEnum { name: v.name },
                        _ => plain,
                    }
                };
                let lhs_base = widen(lhs_ty);
                let rhs_base = widen(rhs_ty);
                if (!ctx.facts.equivalent(lhs_base, rhs_base)) {
                    report(
                        ctx,
                        PendingDiagOrderingDifferentTypes {
                            at: expr,
                            op: op,
                            lhs: lhs_ty,
                            rhs: rhs_ty,
                        },
                    );
                } else {
                    // Ordering needs a SINGLE concrete type (or a bounded
                    // rigid realizing to one) implementing
                    // `baml.ops.Compare`; unions and existentials are not
                    // orderable even member-wise.
                    let compare = lang_decl(ctx, root.base.LangPackage.Baml, ["ops"], "Compare");
                    let comparable = !(lhs_base is root.types.TyUnion || lhs_base is root.types.TyInterface)
                        && compare != null
                        && ctx.facts.is_subtype(
                            lhs_base,
                            root.types.TyInterface { name: compare, args: [], associated_types: [] },
                        );
                    if (!comparable) {
                        report(
                            ctx,
                            PendingDiagOrderingRequiresCompare {
                                at: expr,
                                op: op,
                                ty: pool.from_plain(lhs_base),
                            },
                        );
                    }
                }
            }
            const_fold_binary(pool, op, lhs_ty, rhs_ty) ?? pool.add(root.types.TyBool {})
        },
        root.ast.BinaryOp.NullCoalesce => {
            let lhs_ty = infer_expr(ctx, body, lhs, ExpectationNone {});
            // The unwrapped lhs INFORMS the rhs, so `xs ?? []` adopts the
            // element type; it does not CONSTRAIN it (`v ?? "fallback"` is a
            // join, not a mismatch). The ENCLOSING expectation informs it
            // first: the fallback flows to the same place as the whole
            // expression. The unwrapped lhs is the context when the
            // enclosing one is absent or gives the fallback no shape.
            let inner = remove_null(ctx, lhs_ty);
            let rhs_expectation: Expectation = match (expectation_adjust_for_branches(expected, ctx.table)) {
                let enclosing: ExpectationHasType
                    if expectation_shapes(ctx, body, rhs, enclosing) => enclosing,
                _ => expectation_has_type(pool, inner),
            };
            // The fallback runs only when the lhs is null: it may be
            // skipped, so neither its divergence nor its writes are the
            // expression's outright.
            let skip = root.hir_ty.infer.skip_point(ctx);
            let rhs_ty = infer_expr(ctx, body, rhs, rhs_expectation);
            let reassigned = root.hir_ty.infer.assigned_bindings(ctx, body, rhs);
            root.hir_ty.infer.rejoin_skipped(ctx, skip, reassigned);
            null_coalesce(ctx, inner, rhs_ty)
        },
        // Bitwise dispatches through the `baml.ops` interfaces like every
        // other operator.
        root.ast.BinaryOp.Add
            | root.ast.BinaryOp.Sub
            | root.ast.BinaryOp.Mul
            | root.ast.BinaryOp.Div
            | root.ast.BinaryOp.Mod
            | root.ast.BinaryOp.BitAnd
            | root.ast.BinaryOp.BitOr
            | root.ast.BinaryOp.BitXor
            | root.ast.BinaryOp.Shl
            | root.ast.BinaryOp.Shr =>
        {
            let lhs_ty = infer_expr(ctx, body, lhs, ExpectationNone {});
            let rhs_ty = infer_expr(ctx, body, rhs, ExpectationNone {});
            lhs_ty = ctx.table.resolve_completely(lhs_ty);
            rhs_ty = ctx.table.resolve_completely(rhs_ty);
            let folded = const_fold_binary(pool, op, lhs_ty, rhs_ty);
            if (folded != null) {
                return folded;
            }
            let dispatch = binary_operator(op) ?? baml.sys.panic("outer match arm covers dispatching ops");
            operator_or_obligation(ctx, expr, dispatch.interface_, lhs_ty, rhs_ty)
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_await @ d9be6853b
// `await e : T` for `e : Future<T, E>`; `E` joins the effect channel like
// any throw site. DISTRIBUTES over a union of futures (values union, each
// error side contributes). `never` passes through; a still-unsolved operand
// is DEMANDED structurally (unified with `Future<?V, ?E>`); a non-future
// records the mismatch against `Future<unknown, unknown>`.
function infer_await(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    future: int,
) -> int throws never {
    let pool = ctx.table.pool;
    let fut = infer_expr(ctx, body, future, ExpectationNone {});
    let resolved = structurally_resolve(ctx, fut);
    // An await demands the future's ARGUMENTS, not only its head: `E` joins
    // the effect channel right here, and an enclosing `catch` closes that
    // channel during the walk, long before the finish fixpoint.
    if (pool.has_infer(resolved)) {
        resolved = force_occurring_vars(ctx, resolved);
    }
    match (pool.kinds[resolved]) {
        let f: root.types.InferTyFuture => {
            record_throw(ctx, expr, f.error);
            f.value
        },
        let u: root.types.InferTyUnion
            if u.members.length() > 0
            && u.members.every((member) -> {
                pool.kinds[member] is root.types.InferTyFuture
            }) => {
            let values: int[] = [];
            for (let member in u.members) {
                if let f: root.types.InferTyFuture = pool.kinds[member] {
                    values.push(f.value);
                    record_throw(ctx, expr, f.error);
                }
            }
            union_of(ctx, values)
        },
        root.types.TyNever => resolved,
        root.types.TyInferVar => {
            let value = ctx.table.new_var_ty();
            let error = ctx.table.new_var_ty(policy = root.hir_ty.infer.VarPolicy.Effect);
            let demanded = pool.add(root.types.InferTyFuture { value: value, error: error });
            ctx.table.unify(resolved, demanded) catch (e) {
                root.hir_ty.infer.UnifyError => {},
            };
            record_throw(ctx, expr, error);
            value
        },
        _ if pool.has_error(resolved) => resolved,
        _ => {
            let unknown = pool.add(root.types.TyUnknown {});
            let expected = pool.add(root.types.InferTyFuture { value: unknown, error: unknown });
            ctx.result.type_mismatches[expr] = (expected, resolved);
            pool.add(root.types.TyError {})
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::compound_op_result @ d9be6853b
// One compound-assignment step: `lhs op rhs` through the operator
// machinery (the reporting road: an inapplicable compound operator is the
// same E0004 the binary spelling gets), anchored at the value.
function compound_op_result(
    ctx: InferenceContext,
    at: int,
    op: root.ast.AssignOp,
    lhs: int,
    rhs: int,
) -> int throws never {
    let dispatch = assign_operator(op);
    operator_or_obligation(ctx, at, dispatch.interface_, lhs, rhs)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_index @ d9be6853b
// `base[idx]`: builtin indexing first (lists, maps and `uint8array` index
// directly), `baml.ops.Index` otherwise. The OPTIONAL form (`base?[idx]`)
// peels a nullable base and dispatches on the payload; the enclosing chain
// boundary rewraps `| null`. A nullable base in the PLAIN form reaches
// dispatch as the union, whose `null` member has no impl.
function infer_index(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    base: int,
    index: int,
    optional: bool,
    write: bool,
) -> int throws never {
    let pool = ctx.table.pool;
    let base_ty = infer_expr(ctx, body, base, ExpectationNone {});
    let subject = if (optional) {
        // Chain semantics: the base's null peels here and the enclosing
        // OptionalChain boundary re-unions it.
        peel_chain_null(ctx, base_ty)
    } else {
        base_ty
    };
    let resolved_subject = structurally_resolve(ctx, subject);
    // `?.[]` short-circuits on a null INDEX too, so the optional form's key
    // check admits null; the plain form stays strict.
    let key_expectation = (key: int) -> int {
        if (optional) {
            union_of(ctx, [key, pool.add(root.types.TyNull {})])
        } else {
            key
        }
    };
    let element = match (pool.kinds[resolved_subject]) {
        let list: root.types.InferTyList => {
            let expectation = key_expectation(pool.add(root.types.TyInt {}));
            check_expr(ctx, body, index, expectation);
            list.elem
        },
        let map: root.types.InferTyMap => {
            let expectation = key_expectation(map.key);
            check_expr(ctx, body, index, expectation);
            map.value
        },
        root.types.TyUint8Array => {
            let expectation = key_expectation(pool.add(root.types.TyInt {}));
            check_expr(ctx, body, index, expectation);
            pool.add(root.types.TyInt {})
        },
        _ => {
            let index_ty = infer_expr(ctx, body, index, ExpectationNone {});
            operator_or_obligation(ctx, expr, "Index", resolved_subject, index_ty)
        },
    };
    if (optional) {
        // A nullable INDEX short-circuits too: mark the chain frame; the
        // boundary owns the `| null`.
        let index_ty = ctx.result.type_of_expr.get(index);
        let index_nullable = if (index_ty != null) {
            let resolved = structurally_resolve(ctx, index_ty);
            remove_null(ctx, resolved) != resolved
        } else {
            false
        };
        if (index_nullable) {
            let chain = ctx.chains.at(ctx.chains.length() - 1)
                ?? baml.sys.panic("a `?.[]` link is inside an `OptionalChain`");
            chain.nullable = true;
        }
    }
    element
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_not @ d9be6853b
// `!operand`: its type, and the operand's facts with the outcomes swapped.
// `!` on a LITERAL constant-folds through its truthiness, freshness
// preserved.
function infer_not(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    operand: int,
    position: root.hir_ty.infer.TestPosition,
) -> (int, root.hir_ty.infer.CondFacts) throws never {
    let pool = ctx.table.pool;
    let (let ty, let operand_facts) = root.hir_ty.infer.check_truthy_operand(ctx, body, operand, false, position);
    let facts = operand_facts.swapped();
    let resolved = ctx.table.resolve_completely(ty);
    if let l: root.types.TyLiteral = pool.kinds[resolved] {
        let negated = match (root.hir_ty.infer.truthiness(pool, resolved)) {
            root.hir_ty.infer.Truthiness.AlwaysTruthy => false,
            root.hir_ty.infer.Truthiness.AlwaysFalsy => true,
            root.hir_ty.infer.Truthiness.Runtime => {
                return (pool.add(root.types.TyBool {}), facts);
            },
        };
        let folded = pool.add(
            root.types.TyLiteral {
                value: root.base.LiteralBool { value: negated },
                freshness: l.freshness,
            },
        );
        return (folded, facts);
    }
    (pool.add(root.types.TyBool {}), facts)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_unary @ d9be6853b
// `!e` and `-e`. Negation dispatches through `Negate` (the semantic gate);
// a literal operand then constant-folds to the negated literal TYPE,
// freshness preserved, so `-1` has type `-1`. An i63-range overflow skips
// the fold and keeps the dispatch result.
function infer_unary(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    op: root.ast.UnaryOp,
    operand: int,
) -> int throws never {
    let pool = ctx.table.pool;
    match (op) {
        root.ast.UnaryOp.Not => {
            infer_not(ctx, body, operand, root.hir_ty.infer.TestPosition.Value).0
        },
        root.ast.UnaryOp.Neg => {
            let ty = infer_expr(ctx, body, operand, ExpectationNone {});
            let dispatched = operator_or_obligation(ctx, operand, "Negate", ty, null);
            let resolved = ctx.table.resolve_completely(ty);
            if let l: root.types.TyLiteral = pool.kinds[resolved] {
                if (!pool.has_error(dispatched)) {
                    let folded = negate_literal(pool, l.value, l.freshness);
                    if (folded != null) {
                        return folded;
                    }
                }
            }
            dispatched
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::operator_or_obligation @ d9be6853b
// Operator typing at a use site: ground operands dispatch now; operands
// still carrying inference variables REGISTER an operator obligation
// (register-and-fulfill, never guess-or-fail early) whose fresh output
// variable stands for the result until discharge.
function operator_or_obligation(
    ctx: InferenceContext,
    at: int,
    interface_: string,
    lhs: int,
    rhs: int?,
) -> int throws never {
    let pool = ctx.table.pool;
    let lhs_resolved = ctx.table.resolve_completely(lhs);
    let rhs_resolved = if (rhs != null) {
        ctx.table.resolve_completely(rhs)
    } else {
        null
    };
    if (pool.has_infer(lhs_resolved) || (rhs_resolved != null && pool.has_infer(rhs_resolved))) {
        let out = ctx.table.new_var_ty();
        root.hir_ty.infer.register_obligation(
            ctx,
            root.hir_ty.infer.ObligationOperator {
                interface_: interface_,
                lhs: lhs_resolved,
                rhs: rhs_resolved,
                out: out,
                at: at,
            },
        );
        return out;
    }
    let result = dispatch_operator(ctx, interface_, lhs_resolved, rhs_resolved);
    if (pool.has_error(result)) {
        report_operator_failure(ctx, at, interface_, lhs_resolved, rhs_resolved);
    }
    result
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_operator_failure @ d9be6853b
// A ground operator dispatch found NO impl for clean operands: the
// committed E0004. SHALLOW error screening: a nested error slot does not
// silence the report. The `unknown` top type is NOT screened (it is a type
// the reader wrote, and implements no operator); only the error sentinel
// and an unresolved inference var are cascades.
function report_operator_failure(
    ctx: InferenceContext,
    at: int,
    interface_: string,
    lhs: int,
    rhs: int?,
) -> void throws never {
    let pool = ctx.table.pool;
    let dirty = (ty: int) -> bool {
        pool.kinds[ty] is root.types.TyError || pool.has_infer(ty)
    };
    if (dirty(lhs) || (rhs != null && dirty(rhs))) {
        return;
    }
    report(ctx, PendingDiagOperatorNotApplicable { expr: at, interface_: interface_, lhs: lhs, rhs: rhs });
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::dispatch_operator @ d9be6853b
// The GROUND dispatch: every (lhs alternative, rhs alternative) pair of the
// operands' union members must have an impl of `baml.ops.<interface>`; the
// result is the join of the Outputs. `never` propagates; Error/unknown
// operands suppress to the sentinel. Also the discharge rule for operator
// obligations. Operands resolve through the structure demand first:
// ground projections reduce and weak aliases expand.
function dispatch_operator(
    ctx: InferenceContext,
    interface_: string,
    lhs: int,
    rhs: int?,
) -> int throws never {
    let pool = ctx.table.pool;
    let lhs_structural = structurally_resolve(ctx, lhs);
    let rhs_structural = if (rhs != null) {
        structurally_resolve(ctx, rhs)
    } else {
        null
    };
    let lhs_resolved = ctx.table.resolve_completely(lhs_structural);
    let rhs_resolved = if (rhs_structural != null) {
        ctx.table.resolve_completely(rhs_structural)
    } else {
        null
    };
    if (
        pool.kinds[lhs_resolved] is root.types.TyNever
            || (rhs_resolved != null && pool.kinds[rhs_resolved] is root.types.TyNever)
    ) {
        return pool.add(root.types.TyNever {});
    }
    let undispatchable = (ty: int) -> bool {
        pool.has_error(ty) || pool.has_infer(ty) || pool.kinds[ty] is root.types.TyUnknown
    };
    if (undispatchable(lhs_resolved) || (rhs_resolved != null && undispatchable(rhs_resolved))) {
        return pool.add(root.types.TyError {});
    }
    let outputs: int[] = [];
    for (let lhs_member in operand_members(pool, root.hir.lang_roots(ctx.db), lhs_resolved)) {
        if (rhs_resolved != null) {
            for (let rhs_member in operand_members(pool, root.hir.lang_roots(ctx.db), rhs_resolved)) {
                let output = member_operator_output(ctx, interface_, lhs_member, rhs_member)
                    ?? return pool.add(root.types.TyError {});
                outputs.push(output);
            }
        } else {
            let output = member_operator_output(ctx, interface_, lhs_member, null)
                ?? return pool.add(root.types.TyError {});
            outputs.push(output);
        }
    }
    union_of(ctx, outputs)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::member_operator_output @ d9be6853b
// One operand pair's operator result: a rigid operand dispatches through
// its CARRIED bound, yielding the bound's `Output` pin or the symbolic
// projection; an interface-existential operand dispatches through its own
// interface (or one it `requires`); everything else asks the impl
// registry.
function member_operator_output(
    ctx: InferenceContext,
    interface_: string,
    lhs: int,
    rhs: int?,
) -> int? throws never {
    let pool = ctx.table.pool;
    let lang = root.hir.lang_roots(ctx.db);
    if let v: root.types.TyTypeVar = pool.kinds[lhs] {
        let bounds = ctx.facts.type_var_bound(v.param);
        let bound = bounds.find((bound) -> {
            lang.is_(root.base.LangPackage.Baml, bound.name.pkg)
                && bound.name.namespace.length() == 1
                && bound.name.namespace[0] == "ops"
                && bound.name.name == interface_
                && (
                    if (rhs != null) {
                        bound.generics.length() == 1 && pool.from_plain(bound.generics[0]) == rhs
                    } else {
                        bound.generics.length() == 0
                    }
                )
        })
            ?? return null;
        let pinned = bound.associated_types.find((binding) -> {
            binding.name == "Output"
        });
        if (pinned != null) {
            return pool.from_plain(pinned.ty);
        }
        // No `Output` pin: a bound whose args are still SYMBOLIC keeps the
        // canonical projection (`T extends Add<O>`: `T.Output` is the
        // signature's own name for it). A fully GROUND bound (`T extends
        // Add<int>`) leaves the result underdetermined, so the operand must
        // pin it.
        if (
            !bound.generics.some((generic) -> {
                root.types.contains_ty_where(generic, (t) -> {
                    t is root.types.TyTypeVar
                })
            })
        ) {
            return null;
        }
        return pool.add(
            root.types.InferTyAssociatedTypeProjection {
                base: lhs,
                interface_: root.types.infer_interface_new(
                    bound.name,
                    bound.generics.map((generic) -> {
                        pool.from_plain(generic)
                    }),
                    bound.associated_types.map((binding) -> {
                        root.types.InferAssociatedType {
                            name: binding.name,
                            ty: pool.from_plain(binding.ty),
                        }
                    }),
                ),
                member: "Output",
            },
        );
    }
    // An interface-EXISTENTIAL operand adds like the virtual `x.add(rhs)`
    // call it desugars to. The pin is the result; a recovered error pin
    // surfaces as the operator failure.
    if let i: root.types.InferTyInterface = pool.kinds[lhs] {
        let root_ = root.types.infer_interface_new(i.name, i.args, i.associated_types);
        let heads = [root_].concat(direct_requires_closure(ctx.db, root_, lhs, 8));
        let head = heads.find((head) -> {
            lang.is_(root.base.LangPackage.Baml, head.name.pkg)
                && head.name.namespace.length() == 1
                && head.name.namespace[0] == "ops"
                && head.name.name == interface_
                && (
                    if (rhs != null) {
                        head.generics.length() == 1 && head.generics[0] == rhs
                    } else {
                        head.generics.length() == 0
                    }
                )
        })
            ?? return null;
        let pinned = head.associated_types.find((binding) -> {
            binding.name == "Output"
        })
            ?? return null;
        return pinned.ty;
    }
    operator_output(ctx.db, interface_, lhs, rhs)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::peel_chain_null @ d9be6853b
// A `?.` link's base, just typed: null peels off (marking the enclosing
// chain frame so the BOUNDARY re-unions it) and the link proceeds on the
// non-null part. The chain's first `?.` link sets the point the boundary
// rejoins from when the base is null.
function peel_chain_null(ctx: InferenceContext, ty: int) -> int throws never {
    let resolved = structurally_resolve(ctx, ty);
    let nonnull = remove_null(ctx, resolved);
    let chain = ctx.chains.at(ctx.chains.length() - 1)
        ?? baml.sys.panic("a `?.` link is inside an `OptionalChain`");
    if (nonnull != resolved) {
        chain.nullable = true;
    }
    if (chain.skip == null) {
        chain.skip = root.hir_ty.infer.skip_point(ctx);
    }
    nonnull
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::remove_null @ d9be6853b
// The non-null part of a type: `null` drops from unions (an all-null type
// leaves `never`). Null-peeling is a STRUCTURE demand: an aliased nullable
// answers as its union.
function remove_null(ctx: InferenceContext, ty: int) -> int throws never {
    let pool = ctx.table.pool;
    let resolved = structurally_resolve(ctx, ty);
    match (pool.kinds[resolved]) {
        root.types.TyNull => pool.add(root.types.TyNever {}),
        // Filtering never REWRITES the survivors: the structural constructor
        // keeps each member's identity, freshness included.
        let u: root.types.InferTyUnion => {
            syntactic_union(
                pool,
                u.members.filter((member) -> {
                    !(pool.kinds[member] is root.types.TyNull)
                }),
            )
        },
        _ => resolved,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::null_coalesce @ d9be6853b
// `a ?? b` given the already-unwrapped lhs: `rhs <: inner` keeps the
// unwrapped lhs, `inner <: rhs` keeps rhs, else the freshness-preserving
// join.
function null_coalesce(ctx: InferenceContext, inner: int, rhs: int) -> int throws never {
    let pool = ctx.table.pool;
    let rhs_resolved = ctx.table.resolve_completely(rhs);
    let ground = (ty: int) -> bool {
        !pool.has_infer(ty) && !pool.has_error(ty) && !(pool.kinds[ty] is root.types.TyNever)
    };
    if (ground(inner) && ground(rhs_resolved)) {
        if (cached_subtype(ctx, rhs_resolved, inner)) {
            return inner;
        }
        if (cached_subtype(ctx, inner, rhs_resolved)) {
            return rhs_resolved;
        }
    }
    join(ctx, [inner, rhs_resolved])
}

// port: baml_compiler2_hir_ty/src/infer.rs::operand_members @ d9be6853b
// An operand's union alternatives for operator dispatch, literals widened
// to their bases regardless of freshness (dispatch is by base type; every
// alternative must support the operator). A builtin primitive-companion
// class receiver (`self` inside `class Float`) IS its primitive.
function operand_members(
    pool: root.types.InferPool,
    lang: root.base.LangRoots,
    ty: int,
) -> int[] throws never {
    let widen = (member: int) -> int {
        match (pool.kinds[member]) {
            let l: root.types.TyLiteral => pool.add(literal_base(l.value)),
            let c: root.types.InferTyClass if c.args.length() == 0 => {
                match (root.types.decl_name_builtin_primitive(c.name, lang)) {
                    root.types.PrimitiveType.Int => pool.add(root.types.TyInt {}),
                    root.types.PrimitiveType.Bigint => pool.add(root.types.TyBigint {}),
                    root.types.PrimitiveType.Float => pool.add(root.types.TyFloat {}),
                    root.types.PrimitiveType.String => pool.add(root.types.TyString {}),
                    root.types.PrimitiveType.Bool => pool.add(root.types.TyBool {}),
                    _ => member,
                }
            },
            _ => member,
        }
    };
    match (pool.kinds[ty]) {
        let u: root.types.InferTyUnion => u.members.map(widen),
        _ => [widen(ty)],
    }
}
