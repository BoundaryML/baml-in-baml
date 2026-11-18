// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests @ d9be6853b
//
// Rust's `Ty::int()`, `Ty::list(..)`, ... are `pool.add(..)` of the member
// class. `.unwrap()` on a unification is a plain call (a `UnifyError` fails
// the test); `.unwrap_err()` / `.is_err()` go through `unify_err`. The
// `Result<_, ()>` probes throw `ProbeFailed`. `class` heads are local
// declarations (`DeclName` of package 0) where Rust mints them through
// `test_heads::local`.

// The failure of `table.unify(left, right)`, or `null` when it succeeds.
function unify_err(table: InferenceTable, left: int, right: int) -> UnifyError? {
    table.unify(left, right) catch (e) {
        UnifyError => {
            return e;
        },
    };
    null
}

// The `Err(())` of a failed probe.
class ProbeFailed {
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::class @ d9be6853b
function class_(pool: root.types.InferPool, name: string, args: int[]) -> int {
    pool.add(
        root.types.InferTyClass {
            name: root.types.DeclName { pkg: 0, namespace: [], name: name },
            args: args,
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::map @ d9be6853b
function map_(pool: root.types.InferPool, key: int, value: int) -> int {
    pool.add(root.types.InferTyMap { key: key, value: value })
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::func @ d9be6853b
function func(pool: root.types.InferPool, params: int[], ret: int, throws_: int) -> int {
    pool.add(
        root.types.InferTyFunction {
            params: params.map((ty) -> {
                root.types.InferFunctionParamTy {
                    name: null,
                    ty: ty,
                    mode: root.types.FunctionParamMode.Required,
                }
            }),
            ret: ret,
            throws_: throws_,
        },
    )
}

// The variable a fresh variable type names.
function var_of(pool: root.types.InferPool, ty: int) -> int {
    match (pool.kinds[ty]) {
        let v: root.types.TyInferVar => v.var,
        _ => baml.sys.panic("fresh var"),
    }
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::fresh_vars_are_distinct_and_unsolved @ d9be6853b
test "fresh vars are distinct and unsolved" {
    let table = InferenceTable.new(root.types.InferPool.new());
    let a = table.new_var_ty();
    let b = table.new_var_ty();
    assert.is_true(a != b);
    assert.equal(table.shallow_resolve(a), a);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::unsolved_root_var_tracks_equivalence_classes @ d9be6853b
test "unsolved root var tracks equivalence classes" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let a = table.new_var();
    let b = table.new_var();
    assert.is_true(table.unsolved_root_var(a) != table.unsolved_root_var(b));

    table.unify(
        pool.add(root.types.TyInferVar { var: a }),
        pool.add(root.types.TyInferVar { var: b }),
    );
    assert.equal(table.unsolved_root_var(a), table.unsolved_root_var(b));

    table.unify(pool.add(root.types.TyInferVar { var: a }), pool.add(root.types.TyInt {}));
    assert.equal(table.unsolved_root_var(a), null);
    assert.equal(table.unsolved_root_var(b), null);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::binding_a_var_solves_it @ d9be6853b
test "binding a var solves it" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let a = table.new_var_ty();
    let int = pool.add(root.types.TyInt {});
    table.unify(a, int);
    assert.equal(table.shallow_resolve(a), int);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::var_var_union_shares_the_solution @ d9be6853b
test "var var union shares the solution" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let a = table.new_var_ty();
    let b = table.new_var_ty();
    let string = pool.add(root.types.TyString {});
    table.unify(a, b);
    table.unify(b, string);
    assert.equal(table.shallow_resolve(a), string);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::structural_unification_decomposes_and_solves @ d9be6853b
test "structural unification decomposes and solves" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let string = pool.add(root.types.TyString {});
    let elem = table.new_var_ty();
    table.unify(
        pool.add(root.types.InferTyList { elem: elem }),
        pool.add(root.types.InferTyList { elem: int }),
    );
    assert.equal(table.shallow_resolve(elem), int);

    let err = unify_err(
        table,
        pool.add(root.types.InferTyList { elem: int }),
        pool.add(root.types.InferTyList { elem: string }),
    );
    assert.equal(err, UnifyError { left: int, right: string, escaped: null });
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::known_var_unifies_through_its_solution @ d9be6853b
test "known var unifies through its solution" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let a = table.new_var_ty();
    let b = table.new_var_ty();
    table.unify(a, int);
    table.unify(b, int);
    // Both known: relate the solutions, never merge known roots.
    table.unify(a, b);
    assert.not_null(unify_err(table, a, pool.add(root.types.TyString {})));
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::occurs_check_rejects_infinite_types @ d9be6853b
test "occurs check rejects infinite types" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let a = table.new_var_ty();
    assert.not_null(unify_err(table, a, pool.add(root.types.InferTyList { elem: a })));
    // Also through a chain: ?b := ?a, ?a = List(?b).
    let b = table.new_var_ty();
    table.unify(a, b);
    assert.not_null(unify_err(table, a, pool.add(root.types.InferTyList { elem: b })));
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::error_unifies_with_anything @ d9be6853b
test "error unifies with anything" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let error = pool.add(root.types.TyError {});
    let a = table.new_var_ty();
    table.unify(error, pool.add(root.types.TyInt {}));
    table.unify(a, error);
    // The var stays unsolved rather than being poisoned with Error.
    assert.equal(table.shallow_resolve(a), a);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::error_taints_the_open_classes_it_relates_to @ d9be6853b
test "error taints the open classes it relates to" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let error = pool.add(root.types.TyError {});
    let a = table.new_var();
    let elem = table.new_var();
    let untouched = table.new_var();
    assert.is_true(!table.is_tainted(a));
    table.unify(pool.add(root.types.TyInferVar { var: a }), error);
    assert.is_true(table.is_tainted(a));
    // Nested: the error relates to a type that names the class.
    table.unify(
        error,
        pool.add(root.types.InferTyList { elem: pool.add(root.types.TyInferVar { var: elem }) }),
    );
    assert.is_true(table.is_tainted(elem));
    assert.is_true(!table.is_tainted(untouched));
    // The taint is a property of the open class: an alias sees it, and a
    // solution retires it.
    let alias = table.new_var();
    table.unify(
        pool.add(root.types.TyInferVar { var: alias }),
        pool.add(root.types.TyInferVar { var: a }),
    );
    assert.is_true(table.is_tainted(alias));
    table.unify(pool.add(root.types.TyInferVar { var: a }), pool.add(root.types.TyInt {}));
    assert.is_true(!table.is_tainted(a));
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::var_var_union_keeps_either_taint @ d9be6853b
test "var var union keeps either taint" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let clean = table.new_var();
    let dirty = table.new_var();
    table.unify(pool.add(root.types.TyInferVar { var: dirty }), pool.add(root.types.TyError {}));
    table.unify(
        pool.add(root.types.TyInferVar { var: clean }),
        pool.add(root.types.TyInferVar { var: dirty }),
    );
    assert.is_true(table.is_tainted(clean));
    assert.is_true(table.is_tainted(dirty));
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::rollback_reverts_taint @ d9be6853b
test "rollback reverts taint" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let a = table.new_var();
    let snapshot = table.snapshot();
    table.unify(pool.add(root.types.TyInferVar { var: a }), pool.add(root.types.TyError {}));
    assert.is_true(table.is_tainted(a));
    table.rollback_to(snapshot);
    assert.is_true(!table.is_tainted(a));
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::resolve_completely_folds_nested_solutions @ d9be6853b
test "resolve completely folds nested solutions" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let string = pool.add(root.types.TyString {});
    let elem = table.new_var_ty();
    let ty = pool.add(
        root.types.InferTyList { elem: pool.add(root.types.InferTyUnion { members: [int, elem] }) },
    );
    table.unify(elem, string);
    let resolved = table.resolve_completely(ty);
    assert.equal(
        resolved,
        pool.add(
            root.types.InferTyList {
                elem: pool.add(root.types.InferTyUnion { members: [int, string] }),
            },
        ),
    );
    assert.is_true(!pool.has_infer(resolved));
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::vars_solve_through_deep_nesting @ d9be6853b
test "vars solve through deep nesting" {
    // Map<?k, List<Box<?e>>> = Map<string, List<Box<int | null>>>
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let string = pool.add(root.types.TyString {});
    let int_or_null = pool.add(
        root.types.InferTyUnion {
            members: [pool.add(root.types.TyInt {}), pool.add(root.types.TyNull {})],
        },
    );
    let k = table.new_var_ty();
    let e = table.new_var_ty();
    let left = map_(pool, k, pool.add(root.types.InferTyList { elem: class_(pool, "Box", [e]) }));
    let right = map_(pool, string, pool.add(root.types.InferTyList { elem: class_(pool, "Box", [int_or_null]) }));
    table.unify(left, right);
    assert.equal(table.shallow_resolve(k), string);
    assert.equal(table.shallow_resolve(e), int_or_null);
    assert.equal(table.resolve_completely(left), right);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::union_members_solve_positionally @ d9be6853b
test "union members solve positionally" {
    // (int | ?a | ?b) = (int | string | bool), including a nested union
    // member: List(int | (string | ?x)) = List(int | (string | bool)).
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let string = pool.add(root.types.TyString {});
    let bool = pool.add(root.types.TyBool {});
    let a = table.new_var_ty();
    let b = table.new_var_ty();
    table.unify(
        pool.add(root.types.InferTyUnion { members: [int, a, b] }),
        pool.add(root.types.InferTyUnion { members: [int, string, bool] }),
    );
    assert.equal(table.shallow_resolve(a), string);
    assert.equal(table.shallow_resolve(b), bool);

    let x = table.new_var_ty();
    let nested_left = pool.add(
        root.types.InferTyList {
            elem: pool.add(
                root.types.InferTyUnion {
                    members: [int, pool.add(root.types.InferTyUnion { members: [string, x] })],
                },
            ),
        },
    );
    let nested_right = pool.add(
        root.types.InferTyList {
            elem: pool.add(
                root.types.InferTyUnion {
                    members: [int, pool.add(root.types.InferTyUnion { members: [string, bool] })],
                },
            ),
        },
    );
    table.unify(nested_left, nested_right);
    assert.equal(table.shallow_resolve(x), bool);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::reordered_unions_do_not_unify_yet @ d9be6853b
test "reordered unions do not unify yet" {
    // Pins the limitation: ground unions unify positionally, so a reordered
    // but ACI-equal union is a mismatch today.
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let string = pool.add(root.types.TyString {});
    assert.not_null(
        unify_err(
            table,
            pool.add(root.types.InferTyUnion { members: [int, string] }),
            pool.add(root.types.InferTyUnion { members: [string, int] }),
        ),
    );
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::repeated_var_constrains_both_positions @ d9be6853b
test "repeated var constrains both positions" {
    // Pair<?a, ?a> = Pair<int, ?b>: the second position relates the
    // now-solved ?a against ?b, so ?b := int.
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let a = table.new_var_ty();
    let b = table.new_var_ty();
    table.unify(class_(pool, "Pair", [a, a]), class_(pool, "Pair", [int, b]));
    assert.equal(table.shallow_resolve(b), int);
    // And a later contradiction on either alias is caught.
    assert.not_null(unify_err(table, b, pool.add(root.types.TyString {})));
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::diamond_of_var_unions_resolves_from_one_binding @ d9be6853b
test "diamond of var unions resolves from one binding" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let vars: int[] = [];
    for (let i = 0; i < 6; i += 1) {
        vars.push(table.new_var_ty());
    }
    // Chain pairs, then cross-link into a diamond, then bind one end.
    table.unify(vars[0], vars[1]);
    table.unify(vars[2], vars[3]);
    table.unify(vars[4], vars[5]);
    table.unify(vars[1], vars[2]);
    table.unify(vars[3], vars[4]);
    let never = pool.add(root.types.TyNever {});
    table.unify(vars[5], never);
    for (let var in vars) {
        assert.equal(table.shallow_resolve(var), never);
    }
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::var_bound_to_composite_containing_other_vars @ d9be6853b
test "var bound to composite containing other vars" {
    // ?b = List(?a); ?b = List(int) => ?a := int, and a type mentioning ?b
    // resolves through both hops.
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let string = pool.add(root.types.TyString {});
    let null_ty = pool.add(root.types.TyNull {});
    let list_int = pool.add(root.types.InferTyList { elem: int });
    let a = table.new_var_ty();
    let b = table.new_var_ty();
    table.unify(b, pool.add(root.types.InferTyList { elem: a }));
    table.unify(b, list_int);
    assert.equal(table.shallow_resolve(a), int);
    let wrapper = map_(pool, string, pool.add(root.types.InferTyUnion { members: [b, null_ty] }));
    assert.equal(
        table.resolve_completely(wrapper),
        map_(pool, string, pool.add(root.types.InferTyUnion { members: [list_int, null_ty] })),
    );
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::function_types_solve_params_ret_and_throws @ d9be6853b
test "function types solve params ret and throws" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let string = pool.add(root.types.TyString {});
    let bool = pool.add(root.types.TyBool {});
    let never = pool.add(root.types.TyNever {});
    let p = table.new_var_ty();
    let r = table.new_var_ty();
    let e = table.new_var_ty();
    table.unify(func(pool, [p, string], r, e), func(pool, [int, string], bool, never));
    assert.equal(table.shallow_resolve(p), int);
    assert.equal(table.shallow_resolve(r), bool);
    assert.equal(table.shallow_resolve(e), never);
    // Arity mismatch is a head mismatch, not a partial solve.
    assert.not_null(
        unify_err(table, func(pool, [int], int, never), func(pool, [int, int], int, never)),
    );
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::occurs_check_rejects_deeply_buried_cycles @ d9be6853b
test "occurs check rejects deeply buried cycles" {
    // ?a = Map<string, List<(int | Box<?a>)>> must be rejected, however deep
    // the occurrence and even through an aliased var.
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let a = table.new_var_ty();
    let alias = table.new_var_ty();
    table.unify(a, alias);
    let cyclic = map_(
        pool,
        pool.add(root.types.TyString {}),
        pool.add(
            root.types.InferTyList {
                elem: pool.add(
                    root.types.InferTyUnion {
                        members: [pool.add(root.types.TyInt {}), class_(pool, "Box", [alias])],
                    },
                ),
            },
        ),
    );
    assert.not_null(unify_err(table, a, cyclic));
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::hundred_levels_of_nesting_unify_and_resolve @ d9be6853b
test "hundred levels of nesting unify and resolve" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let core = table.new_var_ty();
    let left = core;
    let right = pool.add(
        root.types.InferTyUnion {
            members: [pool.add(root.types.TyInt {}), pool.add(root.types.TyString {})],
        },
    );
    let expected_core = right;
    for (let i = 0; i < 100; i += 1) {
        left = pool.add(root.types.InferTyList { elem: left });
        right = pool.add(root.types.InferTyList { elem: right });
    }
    table.unify(left, right);
    assert.equal(table.shallow_resolve(core), expected_core);
    assert.equal(table.resolve_completely(left), right);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::nested_probes_roll_back_independently @ d9be6853b
test "nested probes roll back independently" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let string = pool.add(root.types.TyString {});
    let a = table.new_var_ty();
    let b = table.new_var_ty();
    table.commit_if_ok((outer) -> {
        outer.unify(a, int);
        // Inner probe fails and must roll back only its own work.
        let inner_failed = outer.commit_if_ok((inner) -> {
            inner.unify(b, string);
            throw ProbeFailed {}
        }) catch (e) {
            ProbeFailed => true,
        };
        assert.equal(inner_failed, true);
        // inner rollback
        assert.equal(outer.shallow_resolve(b), b);
        // outer intact
        assert.equal(outer.shallow_resolve(a), int);
    });
    assert.equal(table.shallow_resolve(a), int);
    assert.equal(table.shallow_resolve(b), b);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::resolution_is_idempotent_and_identity_on_var_free_types @ d9be6853b
test "resolution is idempotent and identity on var free types" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let string = pool.add(root.types.TyString {});
    let e = table.new_var_ty();
    let ty = pool.add(
        root.types.InferTyList { elem: pool.add(root.types.InferTyUnion { members: [int, e] }) },
    );
    table.unify(e, string);
    let once = table.resolve_completely(ty);
    let twice = table.resolve_completely(once);
    assert.equal(once, twice);
    // Var-free input returns the same interned handle, no rebuild.
    let ground = map_(pool, string, pool.add(root.types.InferTyList { elem: pool.add(root.types.TyBool {}) }));
    assert.equal(table.resolve_completely(ground), ground);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::rollback_reverts_var_kinds_with_their_indices @ d9be6853b
test "rollback reverts var kinds with their indices" {
    // A rolled-back probe frees its variable indices for reuse. The kind
    // must be freed WITH the index, or the fresh value variable below would
    // inherit the dead effect var's kind and default to `never`.
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let snapshot = table.snapshot();
    let _effect = table.new_var_ty(policy = VarPolicy.Effect);
    table.rollback_to(snapshot);

    let value = table.new_var_ty();
    table.default_unsolved_effects_to_never([]);
    // A value variable reusing a rolled-back effect var's index must not
    // default.
    assert.equal(table.shallow_resolve(value), value);

    let snapshot = table.snapshot();
    let _slot = table.new_var_ty(policy = VarPolicy.ContainerSlot);
    table.rollback_to(snapshot);
    let plain = table.new_var();
    assert.equal(table.unsolved_policy(plain), VarPolicy.Value);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::policy_joins_over_unions_and_retires_at_solution @ d9be6853b
test "policy joins over unions and retires at solution" {
    let pool = root.types.InferPool.new();
    let int = pool.add(root.types.TyInt {});
    let table = InferenceTable.new(pool);
    let slot = table.new_var_ty(policy = VarPolicy.ContainerSlot);
    let plain = table.new_var_ty();
    // Unioning a plain var into a container-slot class adopts the class's
    // policy (`Value` is the join identity).
    table.unify(slot, plain);
    let plain_var = var_of(pool, plain);
    assert.equal(table.unsolved_policy(plain_var), VarPolicy.ContainerSlot);
    // Solving retires the policy: a solved class IS its solution.
    table.unify(plain, int);
    assert.equal(table.unsolved_policy(plain_var), null);
    // A rollback of the solving step restores it, policy included.
    let table = InferenceTable.new(pool);
    let slot = table.new_var_ty(policy = VarPolicy.ContainerSlot);
    let var = var_of(pool, slot);
    let snapshot = table.snapshot();
    table.unify(slot, int);
    assert.equal(table.unsolved_policy(var), null);
    table.rollback_to(snapshot);
    assert.equal(table.unsolved_policy(var), VarPolicy.ContainerSlot);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::lambda_param_joining_container_slot_takes_the_stronger_policy @ d9be6853b
test "lambda param joining container slot takes the stronger policy" {
    // `let xs = []; xs.push(x)` inside a lambda: the element slot and the
    // parameter var union, and the class must keep BOTH behaviors
    // (first-demand order AND unknown absorption).
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let param = table.new_var_ty(policy = VarPolicy.LambdaParam);
    let slot = table.new_var_ty(policy = VarPolicy.ContainerSlot);
    table.unify(param, slot);
    let policy = table.unsolved_policy(var_of(pool, param)) ?? baml.sys.panic("still open");
    assert.equal(policy, VarPolicy.ContainerSlot);
    assert.is_true(first_demand_commits(policy));
    assert.is_true(absorbs_unknown(policy));
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::a_scoped_parameter_solves_only_variables_minted_in_its_scope @ d9be6853b
test "a scoped parameter solves only variables minted in its scope" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let outer = table.new_var();
    let param = root.types.ParamTy { index: root.types.SCOPED_PARAM_BIT | 7, name: "T" };
    let scoped = pool.add(root.types.TyTypeVar { param: param });
    let list_scoped = pool.add(root.types.InferTyList { elem: scoped });

    table.bind_scoped_param(param);
    let inner = table.new_var();
    // Minted inside the binding's scope: may take the parameter.
    table.unify(pool.add(root.types.TyInferVar { var: inner }), scoped);
    assert.equal(table.shallow_resolve(pool.add(root.types.TyInferVar { var: inner })), scoped);
    // Minted outside: may not, even under a constructor, and stays open.
    let err = unify_err(table, pool.add(root.types.TyInferVar { var: outer }), list_scoped);
    assert.equal(err?.escaped, param);
    assert.not_null(table.unsolved_root_var(outer));
    assert.equal(table.escaping_scoped_param(outer, list_scoped), param);
    assert.equal(table.escaping_scoped_param(inner, scoped), null);

    // A var-var union is observable from the shallower scope, so the merged
    // class takes the shallower universe.
    let inner_alias = table.new_var();
    table.unify(
        pool.add(root.types.TyInferVar { var: inner_alias }),
        pool.add(root.types.TyInferVar { var: outer }),
    );
    assert.equal(table.escaping_scoped_param(inner_alias, scoped), param);

    // After the block closes, a fresh variable is outer again, and the
    // closed parameter still counts as escaping.
    table.close_scopes_to(0);
    let later = table.new_var();
    assert.equal(table.escaping_scoped_param(later, scoped), param);
    // A rollback restores the universe with the rest of the var state.
    let snapshot = table.snapshot();
    table.unify(pool.add(root.types.TyInferVar { var: later }), pool.add(root.types.TyInt {}));
    table.rollback_to(snapshot);
    assert.equal(table.escaping_scoped_param(later, scoped), param);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::a_closing_block_leaves_its_open_variables_to_the_enclosing_universe @ d9be6853b
test "a closing block leaves its open variables to the enclosing universe" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let param = root.types.ParamTy { index: root.types.SCOPED_PARAM_BIT | 9, name: "T" };
    let scoped = pool.add(root.types.TyTypeVar { param: param });
    let before = table.new_var();
    table.bind_scoped_param(param);
    let inner = table.new_var();
    let solved = table.new_var();
    assert.equal(table.escaping_scoped_param(inner, scoped), null);
    assert.equal(table.escaping_scoped_param(before, scoped), param);
    assert.equal(table.unsolved_vars_deeper_than(0), [inner, solved]);

    // Closing: a class the block leaves open moves out, and from there the
    // closed parameter is an escape for it too.
    table.close_scopes_to(0);
    table.demote_to(inner, 0);
    assert.equal(table.unsolved_vars_deeper_than(0), [solved]);
    assert.equal(table.escaping_scoped_param(inner, scoped), param);
    // Demotion never lifts a class deeper or touches a solved one.
    table.demote_to(before, 0);
    assert.equal(table.escaping_scoped_param(before, scoped), param);
    table.unify(pool.add(root.types.TyInferVar { var: solved }), pool.add(root.types.TyInt {}));
    table.demote_to(solved, 0);
    assert.is_true(table.is_solved(solved));
    assert.equal(table.unsolved_vars_deeper_than(0), []);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::a_deposit_generalizes_the_variables_it_carries_to_the_receiving_class @ d9be6853b
test "a deposit generalizes the variables it carries to the receiving class" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let outer = table.new_var();
    let outer_union = table.new_var();
    let param = root.types.ParamTy { index: root.types.SCOPED_PARAM_BIT | 3, name: "T" };
    let scoped = pool.add(root.types.TyTypeVar { param: param });

    table.bind_scoped_param(param);
    let inner = table.new_var();
    let carried = table.new_var();
    table.add_lower_bound(inner, pool.add(root.types.TyInferVar { var: carried }), null);
    // Minted inside the binding's scope: both may take the parameter.
    assert.equal(table.escaping_scoped_param(inner, scoped), null);
    assert.equal(table.escaping_scoped_param(carried, scoped), null);

    // Depositing `inner[]` into the outer class makes `inner` observable from
    // outside, and through its own bound so is `carried`: neither may take
    // the parameter any more (rustc's generalizer).
    table.add_lower_bound(
        outer,
        pool.add(root.types.InferTyList { elem: pool.add(root.types.TyInferVar { var: inner }) }),
        null,
    );
    assert.equal(table.escaping_scoped_param(inner, scoped), param);
    assert.equal(table.escaping_scoped_param(carried, scoped), param);

    // A SOLUTION carries its variables out the same way a bound does.
    let via_solution = table.new_var();
    assert.equal(table.escaping_scoped_param(via_solution, scoped), null);
    table.solve(
        outer,
        pool.add(
            root.types.InferTyList { elem: pool.add(root.types.TyInferVar { var: via_solution }) },
        ),
    );
    assert.equal(table.escaping_scoped_param(via_solution, scoped), param);

    // So does a var-var union, which takes the shallower depth: the merged
    // class's own bounds are generalized with it.
    let holder = table.new_var();
    let deep = table.new_var();
    table.add_upper_bound(holder, pool.add(root.types.TyInferVar { var: deep }), null);
    assert.equal(table.escaping_scoped_param(deep, scoped), null);
    table.unify(
        pool.add(root.types.TyInferVar { var: outer_union }),
        pool.add(root.types.TyInferVar { var: holder }),
    );
    assert.equal(table.escaping_scoped_param(deep, scoped), param);

    // Closing the scope RETIRES the parameter: a variable minted after it, at
    // the very depth a sibling block reuses, still cannot take it.
    table.close_scopes_to(0);
    let sibling_depth = table.new_var();
    table.bind_scoped_param(
        root.types.ParamTy { index: root.types.SCOPED_PARAM_BIT | 4, name: "U" },
    );
    let in_sibling_block = table.new_var();
    assert.equal(table.escaping_scoped_param(sibling_depth, scoped), param);
    assert.equal(table.escaping_scoped_param(in_sibling_block, scoped), param);
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::tests::rollback_undoes_and_commit_keeps @ d9be6853b
test "rollback undoes and commit keeps" {
    let pool = root.types.InferPool.new();
    let table = InferenceTable.new(pool);
    let int = pool.add(root.types.TyInt {});
    let string = pool.add(root.types.TyString {});
    let a = table.new_var_ty();

    let snapshot = table.snapshot();
    table.unify(a, int);
    table.rollback_to(snapshot);
    // rollback must unsolve
    assert.equal(table.shallow_resolve(a), a);

    table.commit_if_ok((t) -> {
        t.unify(a, string)
    });
    // commit must keep
    assert.equal(table.shallow_resolve(a), string);

    let failed = table.commit_if_ok((t) -> {
        let b = t.new_var_ty();
        t.unify(b, int);
        throw ProbeFailed {}
    }) catch (e) {
        ProbeFailed => true,
    };
    assert.equal(failed, true);
    assert.equal(table.shallow_resolve(a), string);
}
