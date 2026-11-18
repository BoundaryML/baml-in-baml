// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 2, subtyping and joins: `InferenceContext::sub` and the pieces it
// decays into (`sub_residue`, `eq_piece`), the cached oracle verdicts, and
// the freshness-preserving join. Operators are in infer_u2_ops.baml.
//
// Restructured (BAML forces it):
// - Methods of `InferenceContext` are free functions taking `ctx` first;
//   interned types are `int`s into `ctx.table.pool`.
// - `ClosedTy::try_from(&ty)` succeeding is `!pool.has_infer(ty)`, after
//   which the handle is wrapped as `root.types.ClosedTy { ty: ty }`.
// - `ok &= self.sub(..)` (every piece related, no short circuit) is
//   `ok = sub(..) && ok`.
// - `let _ = self.table.unify(..)` is a `catch` that drops the
//   `UnifyError`.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::sub @ d9be6853b
// `Sub(actual, expected)`, discharged eagerly: invariant same-heads decay to
// `Eq`; function types relate contra/co; var-headed pairs deposit bounds;
// ground pairs ask the canonical oracle; the irreducible residue defers to
// finish. False on a DEFINITE mismatch (callers record it); undecided is
// true.
function sub(ctx: InferenceContext, actual: int, expected: int) -> bool throws never {
    let pool = ctx.table.pool;
    actual = ctx.table.shallow_resolve(actual);
    expected = ctx.table.shallow_resolve(expected);
    // A function-type alias used as contextual type information must expose
    // its parameter/return slots so they can determine a generic function
    // value's instantiation (`let f: StringCallback = identity`). Keep the
    // normalization shape-directed: expanding every alias here would erase
    // nominal alias identity from unrelated diagnostics.
    if (
        pool.kinds[actual] is root.types.InferTyFunction
            && pool.kinds[expected] is root.types.TyTypeAlias
    ) {
        expected = expand_alias_ty(ctx, expected);
    }
    if (
        pool.kinds[actual] is root.types.TyTypeAlias
            && pool.kinds[expected] is root.types.InferTyFunction
    ) {
        actual = expand_alias_ty(ctx, actual);
    }
    // Normalize-then-relate: a GROUND projection the oracle can already
    // determine reduces before the pair is related, so
    // `(Iterator<Item = int> as Iterable).Item[]` meets `int[]`.
    // VAR-CARRYING projections must not enter the reduction (the oracle
    // speaks the plain algebra, whose conversion erases inference vars);
    // they relate as lazy predicates through the deferred residue
    // (`eq_piece`).
    if (pool.has_projection(actual) && !pool.has_infer(actual)) {
        actual
            = reduce_projections(ctx, root.types.ClosedTy { ty: actual }, PROJECTION_FINALIZE_FUEL).ty;
    }
    if (pool.has_projection(expected) && !pool.has_infer(expected)) {
        expected
            = reduce_projections(ctx, root.types.ClosedTy { ty: expected }, PROJECTION_FINALIZE_FUEL).ty;
    }
    // Interned identity first: only a pair that is NOT already identical can
    // need the canonical spelling.
    if (actual == expected) {
        return true;
    }
    // The sentinel relates to everything, and the open classes on the other
    // side are tainted by it: the evidence that would have determined them
    // was the error.
    if (pool.has_error(actual)) {
        ctx.table.taint_vars_in(expected);
        return true;
    }
    if (pool.has_error(expected)) {
        ctx.table.taint_vars_in(actual);
        return true;
    }
    // Relate through the canonical spelling of a union whose members
    // resolution has since ground out.
    if (pool.has_union(actual)) {
        actual = deduped_unions(ctx, actual);
    }
    if (pool.has_union(expected)) {
        expected = deduped_unions(ctx, expected);
    }
    if (actual == expected) {
        return true;
    }
    // An `unknown` demand commits empty-container value slots, but not key
    // slots or ordinary inference variables. A bare inference variable still
    // records its upper bound through the var arm below; only STRUCTURED
    // actuals take the fast path.
    if (pool.kinds[expected] is root.types.TyUnknown && !(pool.kinds[actual] is root.types.TyInferVar)) {
        commit_establishments_to_unknown(ctx, actual);
        return true;
    }
    match (pool.kinds[actual], pool.kinds[expected]) {
        // A variable flowing into a context: upper bound. A value flowing
        // into a variable: lower bound. (Var-var records on both sides.)
        (let a: root.types.TyInferVar, _) => {
            if (reject_scoped_escape_into_var(ctx, a.var, expected)) {
                return false;
            }
            let anchor = ctx.obligation_anchor;
            ctx.table.add_upper_bound(a.var, expected, anchor);
            if let other: root.types.TyInferVar = pool.kinds[expected] {
                if (reject_scoped_escape_into_var(ctx, other.var, actual)) {
                    return false;
                }
                ctx.table.add_lower_bound(other.var, actual, anchor);
            }
            true
        },
        (_, let b: root.types.TyInferVar) => {
            if (reject_scoped_escape_into_var(ctx, b.var, actual)) {
                return false;
            }
            ctx.table.add_lower_bound(b.var, actual, ctx.obligation_anchor);
            true
        },
        // A union flowing into a context decomposes universally: `A | B <:
        // C` iff `A <: C` and `B <: C`. Decomposing lets a VAR-CARRYING
        // member meet the expectation instead of deferring the whole pair to
        // the residue, where the member's variable would never receive a
        // bound. Ground unions skip this arm and keep the single oracle
        // verdict.
        (let u: root.types.InferTyUnion, _) if pool.has_infer(actual) => {
            let ok = true;
            for (let member in u.members) {
                ok = sub(ctx, member, expected) && ok;
            }
            ok
        },
        // A var-carrying value flowing into a GROUND union can use a single
        // structurally compatible arm as context (a function can only
        // inhabit the function arm of `Callback | null`). Multiple
        // compatible arms remain ambiguous and stay deferred.
        (_, let u: root.types.InferTyUnion)
            if pool.has_infer(actual) && !pool.has_infer(expected) => {
            let targets = u.members
                .map((member) -> {
                    expand_alias_ty(ctx, member)
                })
                .filter((member) -> {
                    same_head_constructor(pool, actual, member)
                });
            if (targets.length() == 1) {
                return sub(ctx, actual, targets[0]);
            }
            ctx.journals.deferred_subs.push((actual, expected, ctx.obligation_anchor));
            true
        },
        // A var-carrying union TARGET: TypeScript's `inferToMultipleTypes`
        // (`int | null <: ?R | null` must conclude `?R := int`).
        // Constituents IDENTICAL on both sides match and drop; then exactly
        // ONE naked variable left in the target takes the whole remaining
        // source as a lower bound; no naked variable, a single-member
        // remainder and a UNIQUE structurally-matching target constituent
        // recurse; anything else defers.
        (_, let u: root.types.InferTyUnion) if pool.has_infer(expected) => {
            let actual_members = match (pool.kinds[actual]) {
                let au: root.types.InferTyUnion => au.members,
                _ => [actual],
            };
            let naked = u.members.filter((member) -> {
                pool.kinds[member] is root.types.TyInferVar
            });
            let targets = u.members.filter((member) -> {
                !(pool.kinds[member] is root.types.TyInferVar)
            });
            let remainder = actual_members.filter((member) -> {
                !targets.includes(member)
            });
            if (remainder.length() == 0) {
                // Every source constituent found an identical target member.
                return true;
            }
            if (naked.length() == 1) {
                // `join`, not `union_of`: the remainder flows on as a LOWER
                // BOUND, and the canonical algebra would erase literal
                // freshness.
                let source = join(ctx, remainder);
                return sub(ctx, source, naked[0]);
            }
            if (naked.length() == 0 && remainder.length() == 1) {
                let source = remainder[0];
                let matching = targets.filter((target) -> {
                    pool.has_infer(target) && same_head_constructor(pool, source, target)
                });
                if (matching.length() == 1) {
                    return sub(ctx, source, matching[0]);
                }
            }
            ctx.journals.deferred_subs.push((actual, expected, ctx.obligation_anchor));
            true
        },
        // Invariant constructors: Sub decays to Eq of the pieces.
        (let a: root.types.InferTyClass, let b: root.types.InferTyClass)
            if a.name == b.name && a.args.length() == b.args.length() => {
            let ok = true;
            for (let i = 0; i < a.args.length(); i += 1) {
                ok = eq_piece(ctx, a.args[i], b.args[i]) && ok;
            }
            ok
        },
        (let a: root.types.InferTyList, let b: root.types.InferTyList) => {
            eq_piece(ctx, a.elem, b.elem)
        },
        (let a: root.types.InferTyMap, let b: root.types.InferTyMap) => {
            let key_ok = eq_piece(ctx, a.key, b.key);
            let value_ok = eq_piece(ctx, a.value, b.value);
            key_ok && value_ok
        },
        (let a: root.types.InferTyFuture, let b: root.types.InferTyFuture) => {
            let value_ok = eq_piece(ctx, a.value, b.value);
            let error_ok = eq_piece(ctx, a.error, b.error);
            value_ok && error_ok
        },
        (let a: root.types.InferTyTuple, let b: root.types.InferTyTuple)
            if a.items.length() == b.items.length() => {
            let ok = true;
            for (let i = 0; i < a.items.length(); i += 1) {
                ok = eq_piece(ctx, a.items[i], b.items[i]) && ok;
            }
            ok
        },
        // Function types: contravariant params, covariant ret/throws. The
        // parameter lists pair by the spec's rule; a pair of lists that does
        // not fit it is the oracle's verdict.
        (let a: root.types.InferTyFunction, let b: root.types.InferTyFunction) => {
            let param_pairs = function_param_pairs(pool, a.params, b.params)
                ?? return sub_residue(ctx, actual, expected);
            let ok = true;
            for (let pair in param_pairs) {
                ok = sub(ctx, pair.0, pair.1) && ok;
            }
            ok = sub(ctx, a.ret, b.ret) && ok;
            ok = sub(ctx, a.throws_, b.throws_) && ok;
            ok
        },
        // `reflect.AnyFunction` is compiler-derived for concrete function
        // values: a function value flowing into it carries its output
        // channels into the requested `Returns` / `Throws` pins, so a
        // generic consumer such as `reflect.call_any<R, E>` infers `R`/`E`
        // from the signature.
        (let a: root.types.InferTyFunction, let b: root.types.InferTyInterface)
            if root.types.decl_name_is_lang_root_type(
            b.name,
            infer_ctx_lang(ctx),
            root.base.LangPackage.Reflect,
            "AnyFunction",
        ) => {
            let ok = true;
            for (let pin in b.associated_types) {
                let actual_pin = match (pin.name) {
                    "Returns" => a.ret,
                    "Throws" => a.throws_,
                    _ => null,
                };
                if (actual_pin != null) {
                    ok = sub(ctx, actual_pin, pin.ty) && ok;
                }
            }
            ok
        },
        _ => sub_residue(ctx, actual, expected),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::sub_residue @ d9be6853b
// The pair no structural arm decided: ground on both sides, one oracle
// verdict; otherwise the deferred residue, an Implements goal for an
// interface expectation, or invariant identity for a same-interface pair.
function sub_residue(ctx: InferenceContext, actual: int, expected: int) -> bool throws never {
    let pool = ctx.table.pool;
    actual = ctx.table.resolve_completely(actual);
    expected = ctx.table.resolve_completely(expected);
    if (!pool.has_infer(actual) && !pool.has_infer(expected)) {
        return cached_subtype(ctx, actual, expected);
    }
    // A SAME-INTERFACE pair with variables: identity is INVARIANT (args
    // positional, pins by name). Requires-closure upcasts between DIFFERENT
    // interfaces keep the oracle/obligation road; a requested pin the actual
    // side lacks falls through.
    if let a: root.types.InferTyInterface = pool.kinds[actual] {
        if let b: root.types.InferTyInterface = pool.kinds[expected] {
            if (
                a.name == b.name
                    && a.args.length() == b.args.length()
                    && (
                        root.types.decl_name_is_lang_root_type(
                            a.name,
                            infer_ctx_lang(ctx),
                            root.base.LangPackage.Reflect,
                            "AnyFunction",
                        )
                            || b.associated_types.every((pin) -> {
                                a.associated_types.some((a_pin) -> {
                                    a_pin.name == pin.name
                                })
                            })
                    )
            ) {
                let pairs: (int, int)[] = [];
                for (let i = 0; i < a.args.length(); i += 1) {
                    pairs.push((a.args[i], b.args[i]));
                }
                // An `AnyFunction` pin the actual side leaves unwritten reads
                // as its declared `unknown` default, so a bare value binds
                // the expectation's pin variables to `unknown` instead of
                // stranding them.
                for (let pin in b.associated_types) {
                    let a_pin = a.associated_types.find((a_pin) -> {
                        a_pin.name == pin.name
                    });
                    if (a_pin != null) {
                        pairs.push((a_pin.ty, pin.ty));
                    } else {
                        pairs.push((pool.add(root.types.TyUnknown {}), pin.ty));
                    }
                }
                let ok = true;
                for (let pair in pairs) {
                    ok = eq_piece(ctx, pair.0, pair.1) && ok;
                }
                return ok;
            }
        }
    }
    // An interface EXPECTATION in a var-carrying pair is an Implements GOAL,
    // not an inert pair: confirmation both proves the goal and BINDS the
    // expectation's variables (`int[] <: Iterable<Item = ?R>` confirms
    // through the `T[]` impl, pinning `?R := int`). A union is a subtype of
    // an existential iff ALL members are, and only concrete types implement,
    // so the goal decomposes per member before registration.
    let anchor = ctx.obligation_anchor;
    if (anchor != null && !(pool.kinds[actual] is root.types.TyInferVar)) {
        if let i: root.types.InferTyInterface = pool.kinds[expected] {
            let interface_ = root.types.infer_interface_new(i.name, i.args, i.associated_types);
            let goals = match (pool.kinds[actual]) {
                let u: root.types.InferTyUnion => u.members,
                _ => [actual],
            };
            for (let goal in goals) {
                root.hir_ty.infer.register_obligation(
                    ctx,
                    root.hir_ty.infer.obligation_implements(
                        goal,
                        interface_,
                        anchor,
                        root.hir_ty.infer.GoalPurpose.Coercion,
                    ),
                );
            }
            return true;
        }
    }
    ctx.journals.deferred_subs.push((actual, expected, ctx.obligation_anchor));
    true
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::commit_establishments_to_unknown @ d9be6853b
// Solves every ESTABLISHMENT variable inside `ty` to the top type: the
// commitment a ground `unknown` demand makes on an empty container
// literal's slots. Ordinary inference vars are untouched.
function commit_establishments_to_unknown(ctx: InferenceContext, ty: int) -> void throws never {
    let pool = ctx.table.pool;
    if (!pool.has_infer(ty)) {
        return;
    }
    let resolved = ctx.table.shallow_resolve(ty);
    if let v: root.types.TyInferVar = pool.kinds[resolved] {
        let policy = ctx.table.unsolved_policy(v.var);
        if (policy != null && root.hir_ty.infer.absorbs_unknown(policy)) {
            ctx.table.solve(v.var, pool.add(root.types.TyUnknown {}));
        }
        return;
    }
    for (let child in root.types.children_infer_ty(pool.kinds[resolved])) {
        commit_establishments_to_unknown(ctx, child);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::eq_piece @ d9be6853b
// One invariant piece of a decayed Sub: SEMANTIC equality. A ground pair
// asks the canonical oracle (`equivalent` reduces projections, expands
// aliases, normalizes unions); a variable-carrying pair unifies through the
// table.
function eq_piece(ctx: InferenceContext, a: int, b: int) -> bool throws never {
    let pool = ctx.table.pool;
    a = ctx.table.resolve_completely(a);
    b = ctx.table.resolve_completely(b);
    if (!pool.has_infer(a) && !pool.has_infer(b)) {
        return cached_equivalent(ctx, a, b);
    }
    // A projection whose base still carries variables cannot relate
    // structurally: the deferred `Sub` residue keeps the pair as a lazy
    // predicate, both directions (this is Eq), re-examined at finish.
    if (pool.has_projection(a) || pool.has_projection(b)) {
        ctx.journals.deferred_subs.push((a, b, ctx.obligation_anchor));
        ctx.journals.deferred_subs.push((b, a, ctx.obligation_anchor));
        return true;
    }
    // A union against a NON-union has no unification arm: `A | B ≡ C` does
    // not entail `A ≡ C`. What IS entailed is CONTAINMENT of every member,
    // so relate those (landing the bounds a demand point later needs), and
    // defer the pair itself both directions for the finish drain.
    // Union-against-union keeps unifying positionally, and a union against a
    // BARE variable unifies (equality entails the variable is the union).
    let union_members = (ty: int) -> int[]? {
        match (pool.kinds[ty]) {
            let u: root.types.InferTyUnion => u.members,
            _ => null,
        }
    };
    let bare_var = (ty: int) -> bool {
        pool.kinds[ty] is root.types.TyInferVar
    };
    let a_members = union_members(a);
    let b_members = union_members(b);
    let one_sided: (int[], int)? = if (a_members != null && b_members == null && !bare_var(b)) {
        (a_members, b)
    } else if (a_members == null && b_members != null && !bare_var(a)) {
        (b_members, a)
    } else {
        null
    };
    if (one_sided != null) {
        for (let member in one_sided.0) {
            // Report-only: the deferred pair below is the judge.
            sub(ctx, member, one_sided.1);
        }
        ctx.journals.deferred_subs.push((a, b, ctx.obligation_anchor));
        ctx.journals.deferred_subs.push((b, a, ctx.obligation_anchor));
        return true;
    }
    ctx.table.unify(a, b) catch (e) {
        root.hir_ty.infer.UnifyError => {
            let param = e.escaped;
            if (param != null) {
                // The variable side is `left` (the table's `bind` reports
                // the variable first); it takes the `Error` fill so the
                // failure does not cascade into an unresolved-type report.
                let at = ctx.obligation_anchor;
                if (at != null) {
                    report_scoped_type_escape(ctx, at, param, e.right, ScopedTypeEscapeKindValue {});
                }
                if let v: root.types.TyInferVar = pool.kinds[e.left] {
                    refuse_with_error_fill(ctx, v.var);
                }
            }
            return false;
        },
    };
    true
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::reject_scoped_escape_into_var @ d9be6853b
// rustc's universe check at a bound's deposit point: a variable minted
// outside a block may not be solved to a type mentioning a binding the
// block introduced. Reported at the current anchor (E0172); the variable
// takes the `Error` fill so the failure does not cascade.
function reject_scoped_escape_into_var(
    ctx: InferenceContext,
    var: int,
    ty: int,
) -> bool throws never {
    let param = ctx.table.escaping_scoped_param(var, ty)
        ?? return false;
    let at = ctx.obligation_anchor;
    if (at != null) {
        report_scoped_type_escape(ctx, at, param, ty, ScopedTypeEscapeKindInferred {});
    } else {
        // Reached from a road with no anchor (a pattern walk, a bound
        // replay): the block that binds the parameter reports it when it
        // closes rather than filling `Error` in silence.
        ctx.journals.anchorless_escapes.push((param, ty));
    }
    refuse_with_error_fill(ctx, var);
    true
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::cached_equivalent @ d9be6853b
// The canonical oracle's equivalence on a ground pair. An OPEN operand:
// only shallow identity decides before resolution, failing closed (a
// mismatch recorded mid-flight is re-judged at finish).
function cached_equivalent(ctx: InferenceContext, a: int, b: int) -> bool throws never {
    let pool = ctx.table.pool;
    if (pool.has_infer(a) || pool.has_infer(b)) {
        return a == b;
    }
    ctx.canonical_cache.equivalent(
        pool,
        root.types.ClosedTy { ty: a },
        root.types.ClosedTy { ty: b },
        ctx.facts,
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::cached_subtype @ d9be6853b
// The canonical oracle's subtype verdict on a ground pair; an open operand
// decides by shallow identity.
function cached_subtype(ctx: InferenceContext, sub: int, sup: int) -> bool throws never {
    let pool = ctx.table.pool;
    if (pool.has_infer(sub) || pool.has_infer(sup)) {
        return sub == sup;
    }
    ctx.canonical_cache.is_subtype(
        pool,
        root.types.ClosedTy { ty: sub },
        root.types.ClosedTy { ty: sup },
        ctx.facts,
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::provable_subtype @ d9be6853b
// A PROVABLE subtype verdict: ground on both sides and confirmed by this
// body's facts and canonical cache. Rigid or unresolved pairs are not
// provable, the conservative direction for coverage and claiming. Rigid
// variables go to the oracle too: its typevar arms are already
// conservative.
function provable_subtype(ctx: InferenceContext, sub: int, sup: int) -> bool throws never {
    let pool = ctx.table.pool;
    if (sub == sup) {
        return true;
    }
    if (pool.has_error(sub) || pool.has_error(sup)) {
        return false;
    }
    if (pool.has_infer(sub) || pool.has_infer(sup)) {
        return false;
    }
    ctx.canonical_cache.is_subtype(
        pool,
        root.types.ClosedTy { ty: sub },
        root.types.ClosedTy { ty: sup },
        ctx.facts,
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::union_of @ d9be6853b
// A union of members that may still contain inference variables: canonical
// when closed, syntactic until then (`union_of_tys`). Kept although it only
// forwards: it is the agreed entry point other units call.
function union_of(ctx: InferenceContext, members: int[]) -> int throws never {
    union_of_tys(ctx.facts, members)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::join @ d9be6853b
// The control-flow join: a canonical union that PRESERVES literal freshness
// across the round-trip (the canonical algebra erases freshness, but
// widening at the eventual binding site still needs it: `if c { 1 } else {
// 2 }` is the fresh `1 | 2`). A value with a RIGID witness stays rigid:
// TS's union-widening rule.
function join(ctx: InferenceContext, members: int[]) -> int throws never {
    let pool = ctx.table.pool;
    // Literal witnesses by freshness: top-level members and one union layer
    // (the shapes arm joins produce).
    let fresh: root.base.Literal[] = [];
    let regular: root.base.Literal[] = [];
    let collect = (ty: int) -> void {
        if let l: root.types.TyLiteral = pool.kinds[ty] {
            match (l.freshness) {
                root.types.Freshness.Fresh => {
                    fresh.push(l.value);
                },
                root.types.Freshness.Regular => {
                    regular.push(l.value);
                },
            }
        }
    };
    for (let member in members) {
        match (pool.kinds[member]) {
            let u: root.types.InferTyUnion => {
                for (let inner in u.members) {
                    collect(inner);
                }
            },
            _ => {
                collect(member);
            },
        }
    }
    let joined = union_of(ctx, members);
    if (fresh.length() == 0) {
        return joined;
    }
    let remark = (ty: int) -> int {
        match (pool.kinds[ty]) {
            let l: root.types.TyLiteral
                if l.freshness == root.types.Freshness.Regular
                && fresh.includes(l.value)
                && !regular.includes(l.value) => {
                pool.add(
                    root.types.TyLiteral { value: l.value, freshness: root.types.Freshness.Fresh },
                )
            },
            _ => ty,
        }
    };
    match (pool.kinds[joined]) {
        let u: root.types.InferTyUnion => {
            pool.add(root.types.InferTyUnion { members: u.members.map(remark) })
        },
        _ => remark(joined),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::join_return_candidates @ d9be6853b
// The join of a body's return candidates, `never` ones dropped: a single
// distinct candidate stands as it is.
function join_return_candidates(ctx: InferenceContext, candidates: int[]) -> int throws never {
    let pool = ctx.table.pool;
    let live = candidates.filter((candidate) -> {
        !(pool.kinds[candidate] is root.types.TyNever)
    });
    if (live.length() == 0) {
        return pool.add(root.types.TyNever {});
    }
    let first = live[0];
    if (
        live.every((candidate) -> {
            candidate == first
        })
    ) {
        return first;
    }
    join(ctx, live)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::widen_fresh @ d9be6853b
// Fresh literals widen to their base primitive at binding sites and joins;
// a union of fresh literals widens member-wise and re-canonicalizes (`1 | 2`
// at a binding is `int`).
function widen_fresh(ctx: InferenceContext, ty: int) -> int throws never {
    let pool = ctx.table.pool;
    let is_fresh_literal = (member: int) -> bool {
        match (pool.kinds[member]) {
            let l: root.types.TyLiteral => l.freshness == root.types.Freshness.Fresh,
            _ => false,
        }
    };
    match (pool.kinds[ty]) {
        root.types.TyLiteral if is_fresh_literal(ty) => widen_fresh_literal(pool, ty),
        let u: root.types.InferTyUnion if u.members.some(is_fresh_literal) => {
            union_of(
                ctx,
                u.members.map((member) -> {
                    widen_fresh_literal(pool, member)
                }),
            )
        },
        _ => ty,
    }
}
