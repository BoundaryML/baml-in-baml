// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests @ d9be6853b
//
// The algorithm driven through test `PatCtx`s, no database. Split across
// exhaustiveness_test.baml (contexts, helpers, tests through `testing_26`)
// and exhaustiveness_more_test.baml (the rest).
//
// Restructured:
// - Contexts declared inside a test fn are top-level classes; the two
//   `ArrayCtx`s are `ArrayCtx` and `ArrayRestCtx`.
// - `HashMap<DeclName, _>` registries are keyed by `decl_name_ctor_identity`.
// - `assert!` messages are dropped; asserts on rendered witnesses compare the
//   same strings.
// - Not ported (forwarding helpers, called directly): `opt_of`
//   (`root.types.optional`), `union_of`, `list_of`, `null_ty`, `never_ty`
//   (class literals).

// port: baml_compiler2_hir_ty/src/test_heads.rs @ d9be6853b
// Reduced to what these tests spell: the nameless workspace root `user`, the
// first and only root of the test database, so its id is 0.
const USER_ROOT: int = 0;

// port: baml_compiler2_hir_ty/src/test_heads.rs::viewpoint @ d9be6853b
// The viewpoint diagnostics render from: user-facing for the nameless
// workspace root (its own items bare).
function viewpoint() -> Viewpoint throws never {
    let db = root.hir.Db.new();
    let user = root.db.add_root(db, "<test>/user", root.base.SourceRootKind.Workspace, null, []);
    Viewpoint.for_namespace(db, user)
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::StubCtx @ d9be6853b
// A trivial `PatCtx`: no class or list lookup.
class StubCtx {
    implements PatCtx {
        function enumerate_ctors(self, ty: root.types.Ty) -> Ctor[] {
            match (ty) {
                root.types.TyBool => {
                    [CtorType { value: bool_lit(true) }, CtorType { value: bool_lit(false) }]
                },
                root.types.TyInt | root.types.TyFloat | root.types.TyString => {
                    [CtorNonExhaustive {}]
                },
                root.types.TyNull => [CtorType { value: ty }],
                let u: root.types.TyUnion => {
                    u.members.flat_map((m) -> {
                        self.enumerate_ctors(m)
                    })
                },
                root.types.TyLiteral | root.types.TyEnumVariant => [CtorType { value: ty }],
                root.types.TyNever => [],
                root.types.TyTypeVar => [CtorNonExhaustive {}],
                _ => [CtorNonExhaustive {}],
            }
        }

        function class_field_types(
            self,
            qtn: root.types.DeclName,
            ty: root.types.Ty,
        ) -> root.types.Ty[] {
            []
        }

        function list_element_type(self, ty: root.types.Ty) -> root.types.Ty {
            match (ty) {
                let l: root.types.TyList => l.elem,
                _ => ty,
            }
        }
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::bool_lit @ d9be6853b
function bool_lit(v: bool) -> root.types.Ty throws never {
    root.types.TyLiteral {
        value: root.base.LiteralBool { value: v },
        freshness: root.types.Freshness.Regular,
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::int_lit @ d9be6853b
function int_lit(v: int) -> root.types.Ty throws never {
    root.types.TyLiteral {
        value: root.base.LiteralInt { value: v },
        freshness: root.types.Freshness.Regular,
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::float_lit @ d9be6853b
function float_lit(s: string) -> root.types.Ty throws never {
    root.types.TyLiteral {
        value: root.base.LiteralFloat { value: s },
        freshness: root.types.Freshness.Regular,
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::bool_ty @ d9be6853b
function bool_ty() -> root.types.Ty throws never {
    root.types.TyBool {}
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::int_ty @ d9be6853b
function int_ty() -> root.types.Ty throws never {
    root.types.TyInt {}
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::TestingCtx @ d9be6853b
// A reusable context with a class registry (fields in declaration order) and
// an alias map. `List` enumerates as `NonExhaustive`: slice splitting handles
// it before enumeration is consulted.
class TestingCtx {
    classes: map<string, root.types.Ty[]>,
    // `TyTypeAlias` targets, as the real builder's `expand_alias_chains`.
    aliases: map<string, root.types.Ty>,

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::TestingCtx::new @ d9be6853b
    function new() -> TestingCtx throws never {
        TestingCtx { classes: {}, aliases: {} }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::TestingCtx::register @ d9be6853b
    function register(
        self,
        qtn: root.types.DeclName,
        fields: root.types.Ty[],
    ) -> void throws never {
        self.classes.set(decl_name_ctor_identity(qtn), fields);
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::TestingCtx::register_alias @ d9be6853b
    function register_alias(
        self,
        qtn: root.types.DeclName,
        target: root.types.Ty,
    ) -> void throws never {
        self.aliases.set(decl_name_ctor_identity(qtn), target);
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::TestingCtx::expand_alias @ d9be6853b
    // Walk `TyTypeAlias` chains to a non-alias type. A cycle falls through to
    // the alias (treated as opaque).
    function expand_alias(self, ty: root.types.Ty) -> root.types.Ty throws never {
        let current = ty;
        let seen: map<string, bool> = {};
        while let alias: root.types.TyTypeAlias = current {
            let key = decl_name_ctor_identity(alias.name);
            if (seen.has(key)) {
                return current;
            }
            seen.set(key, true);
            let target = self.aliases.get(key);
            if (target == null) {
                return current;
            }
            current = target;
        }
        current
    }

    implements PatCtx {
        function enumerate_ctors(self, ty: root.types.Ty) -> Ctor[] {
            // Peel aliases first, the same way the real builder will.
            let expanded = self.expand_alias(ty);
            match (expanded) {
                root.types.TyBool => {
                    [CtorType { value: bool_lit(true) }, CtorType { value: bool_lit(false) }]
                },
                root.types.TyInt | root.types.TyFloat | root.types.TyString => {
                    [CtorNonExhaustive {}]
                },
                root.types.TyNull => [CtorType { value: expanded }],
                let u: root.types.TyUnion => {
                    u.members.flat_map((m) -> {
                        self.enumerate_ctors(m)
                    })
                },
                root.types.TyLiteral | root.types.TyEnumVariant => [CtorType { value: expanded }],
                let c: root.types.TyClass => [CtorClass { name: c.name, args: c.args }],
                root.types.TyList => [CtorNonExhaustive {}],
                root.types.TyNever => [],
                root.types.TyTypeVar => [CtorNonExhaustive {}],
                _ => [CtorNonExhaustive {}],
            }
        }

        function class_field_types(
            self,
            qtn: root.types.DeclName,
            ty: root.types.Ty,
        ) -> root.types.Ty[] {
            self.classes.get(decl_name_ctor_identity(qtn)) ?? []
        }

        function list_element_type(self, ty: root.types.Ty) -> root.types.Ty {
            match (self.expand_alias(ty)) {
                let l: root.types.TyList => l.elem,
                let t: root.types.Ty => t,
            }
        }
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::qtn @ d9be6853b
// A head at the root namespace of the nameless workspace root. Also
// `test_heads::new` (package `user`, no namespace) and `test_heads::local`,
// the only forms these tests use.
function qtn(name: string) -> root.types.DeclName throws never {
    root.types.DeclName { pkg: USER_ROOT, namespace: [], name: name }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::class_ty @ d9be6853b
function class_ty(q: root.types.DeclName) -> root.types.Ty throws never {
    root.types.TyClass { name: q, args: [] }
}

// `report.missing`, each rendered from the test viewpoint.
function rendered(report: UsefulnessReport) -> string[] throws never {
    let vp = viewpoint();
    report.missing.map((w) -> {
        w.render(vp)
    })
}

// `SliceShape::Variable { prefix, suffix }`.
function var_shape(prefix: int, suffix: int) -> SliceShape throws never {
    SliceShapeVariable { prefix: prefix, suffix: suffix }
}

// `SliceShape::Fixed(n)`.
function fixed(n: int) -> SliceShape throws never {
    SliceShapeFixed { value: n }
}

test "open tuple shapes compare slot patterns without consuming other values" {
    let unknown: root.types.Ty = root.types.TyUnknown {};
    let shape = (first: root.types.Ty) -> DPat {
        DPat.tuple([DPat.type_test(first, unknown), DPat.wildcard(unknown)], unknown)
    };
    let arms = [shape(bool_lit(true)), shape(bool_lit(true)), shape(bool_lit(false))];
    let report = compute_match_usefulness(StubCtx {}, arms, unknown);
    assert.equal(report.unreachable_arms, [1]);
    // Non-tuples still need coverage.
    assert.is_true(report.missing.length() > 0);

    let report = compute_match_usefulness(StubCtx {}, arms.concat([DPat.wildcard(unknown)]), unknown);
    assert.equal(report.unreachable_arms, [1]);
    assert.equal(report.missing.length(), 0)
}

test "bool exhaustive with both arms" {
    let arms = [DPat.type_test(bool_lit(true), bool_ty()), DPat.type_test(bool_lit(false), bool_ty())];
    let report = compute_match_usefulness(StubCtx {}, arms, bool_ty());
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, [])
}

test "bool non exhaustive missing false" {
    let arms = [DPat.type_test(bool_lit(true), bool_ty())];
    let report = compute_match_usefulness(StubCtx {}, arms, bool_ty());
    assert.equal(report.missing.length(), 1);
    assert.is_true(report.missing[0].ctor is CtorType)
}

test "bool wildcard makes exhaustive" {
    let arms = [DPat.type_test(bool_lit(true), bool_ty()), DPat.wildcard(bool_ty())];
    let report = compute_match_usefulness(StubCtx {}, arms, bool_ty());
    assert.equal(report.missing.length(), 0)
}

test "int requires wildcard" {
    let arms = [DPat.type_test(int_lit(1), int_ty())];
    let report = compute_match_usefulness(StubCtx {}, arms, int_ty());
    assert.equal(report.missing.length(), 1)
}

test "int with wildcard is exhaustive" {
    let arms = [DPat.type_test(int_lit(1), int_ty()), DPat.wildcard(int_ty())];
    let report = compute_match_usefulness(StubCtx {}, arms, int_ty());
    assert.equal(report.missing.length(), 0)
}

test "unreachable after wildcard" {
    let arms = [DPat.wildcard(bool_ty()), DPat.type_test(bool_lit(true), bool_ty())];
    let report = compute_match_usefulness(StubCtx {}, arms, bool_ty());
    assert.equal(report.missing.length(), 0);
    assert.is_true(report.unreachable_arms.includes(1))
}

test "typevar requires wildcard" {
    let tv = type_var_ty("T");
    let report = compute_match_usefulness(StubCtx {}, [DPat.wildcard(tv)], tv);
    assert.equal(report.missing.length(), 0)
}

test "never is vacuously exhaustive" {
    let report = compute_match_usefulness(StubCtx {}, [], root.types.TyNever {});
    assert.equal(report.missing.length(), 0)
}

test "float canonicalization" {
    let a = ty_ctor_identity(float_lit("1.0"));
    let b = ty_ctor_identity(float_lit("1.00"));
    let c = ty_ctor_identity(float_lit("1e0"));
    assert.equal(a, b);
    assert.equal(a, c)
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::array_pair_missing_diagonal::ArrayCtx @ d9be6853b
// Enumerates `List` as lengths 0..=3 plus a variable catch-all.
class ArrayCtx {
    implements PatCtx {
        function enumerate_ctors(self, ty: root.types.Ty) -> Ctor[] {
            match (ty) {
                root.types.TyBool => {
                    [CtorType { value: bool_lit(true) }, CtorType { value: bool_lit(false) }]
                },
                root.types.TyList => {
                    [
                        CtorSlice { value: fixed(0) },
                        CtorSlice { value: fixed(1) },
                        CtorSlice { value: fixed(2) },
                        CtorSlice { value: fixed(3) },
                        CtorSlice { value: var_shape(0, 0) },
                    ]
                },
                root.types.TyLiteral => [CtorType { value: ty }],
                _ => [CtorNonExhaustive {}],
            }
        }

        function class_field_types(
            self,
            q: root.types.DeclName,
            t: root.types.Ty,
        ) -> root.types.Ty[] {
            []
        }

        function list_element_type(self, ty: root.types.Ty) -> root.types.Ty {
            match (ty) {
                let l: root.types.TyList => l.elem,
                _ => ty,
            }
        }
    }
}

// `Array<bool>` with `[true, _]` and `[false, true]` reports `[false, false]`
// among the missing cases.
test "array pair missing diagonal" {
    let array_bool: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let arm1 = DPat.slice(
        fixed(2),
        [DPat.type_test(bool_lit(true), bool_ty()), DPat.wildcard(bool_ty())],
        array_bool,
    );
    let arm2 = DPat.slice(
        fixed(2),
        [DPat.type_test(bool_lit(false), bool_ty()), DPat.type_test(bool_lit(true), bool_ty())],
        array_bool,
    );
    let report = compute_match_usefulness(ArrayCtx {}, [arm1, arm2], array_bool);
    assert.is_true(
        rendered(report).some((s) -> {
            s.includes("false, false")
        }),
    )
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::array_rest_covers_all_lengths::ArrayCtx @ d9be6853b
// Enumerates `List` as the length classes in the matrix plus a variable
// catch-all.
class ArrayRestCtx {
    implements PatCtx {
        function enumerate_ctors(self, ty: root.types.Ty) -> Ctor[] {
            match (ty) {
                root.types.TyBool => {
                    [CtorType { value: bool_lit(true) }, CtorType { value: bool_lit(false) }]
                },
                root.types.TyList => {
                    [
                        CtorSlice { value: fixed(0) },
                        CtorSlice { value: fixed(1) },
                        CtorSlice { value: var_shape(2, 0) },
                    ]
                },
                root.types.TyLiteral => [CtorType { value: ty }],
                _ => [CtorNonExhaustive {}],
            }
        }

        function class_field_types(
            self,
            q: root.types.DeclName,
            t: root.types.Ty,
        ) -> root.types.Ty[] {
            []
        }

        function list_element_type(self, ty: root.types.Ty) -> root.types.Ty {
            match (ty) {
                let l: root.types.TyList => l.elem,
                _ => ty,
            }
        }
    }
}

// `Array<bool>` with `[]`, `[_]`, `[_, _, ..]` is exhaustive over all lengths.
test "array rest covers all lengths" {
    let array_bool: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let arms = [
        DPat.slice(fixed(0), [], array_bool),
        DPat.slice(fixed(1), [DPat.wildcard(bool_ty())], array_bool),
        DPat.slice(
            var_shape(2, 0),
            [DPat.wildcard(bool_ty()), DPat.wildcard(bool_ty())],
            array_bool,
        ),
    ];
    let report = compute_match_usefulness(ArrayRestCtx {}, arms, array_bool);
    assert.equal(rendered(report), [])
}

// Port of rustc_pattern_analysis `test_nested`: `type E = A | B` and
// `class Pair { left: E, right: E }`.
test "rustc port nested type union pair" {
    let cx = TestingCtx.new();
    let a = qtn("A");
    let b = qtn("B");
    let pair = qtn("NestedPair");
    let a_ty = class_ty(a);
    let b_ty = class_ty(b);
    let e_ty: root.types.Ty = root.types.TyUnion { members: [a_ty, b_ty] };
    let pair_ty = class_ty(pair);

    cx.register(a, [bool_ty()]);
    cx.register(b, [bool_ty()]);
    cx.register(pair, [e_ty, e_ty]);

    let variant = (q: root.types.DeclName) -> DPat {
        DPat.class_(q, [DPat.wildcard(bool_ty())], class_ty(q))
    };
    let mk_pair = (left: DPat, right: DPat) -> DPat {
        DPat.class_(pair, [left, right], pair_ty)
    };

    // A(_) in the left slot must not cover B(_).
    let report = compute_match_usefulness(cx, [mk_pair(variant(a), DPat.wildcard(e_ty))], pair_ty);
    assert.is_true(report.missing.length() > 0);

    // A(_) | B(_) in the left slot covers the whole pair.
    let report = compute_match_usefulness(
        cx,
        [mk_pair(variant(a), DPat.wildcard(e_ty)), mk_pair(variant(b), DPat.wildcard(e_ty))],
        pair_ty,
    );
    assert.equal(report.missing.length(), 0);

    // A(_) in either slot still misses B(_), B(_).
    let report = compute_match_usefulness(
        cx,
        [mk_pair(variant(a), DPat.wildcard(e_ty)), mk_pair(DPat.wildcard(e_ty), variant(a))],
        pair_ty,
    );
    assert.is_true(report.missing.length() > 0);

    // The explicit B(_), B(_) arm completes coverage.
    let report = compute_match_usefulness(
        cx,
        [
            mk_pair(variant(a), DPat.wildcard(e_ty)),
            mk_pair(DPat.wildcard(e_ty), variant(a)),
            mk_pair(variant(b), variant(b)),
        ],
        pair_ty,
    );
    assert.equal(report.missing.length(), 0)
}

// Port of rustc_pattern_analysis `test_witnesses`: `(Option<bool>,
// Option<bool>)` as a two-field class over `bool?`.
test "rustc port optional pair witnesses" {
    let cx = TestingCtx.new();
    let pair = qtn("OptionalPair");
    let opt_bool = root.types.optional(bool_ty());
    let pair_ty = class_ty(pair);
    cx.register(pair, [opt_bool, opt_bool]);

    let mk_pair = (left: DPat, right: DPat) -> DPat {
        DPat.class_(pair, [left, right], pair_ty)
    };

    // An empty match produces one wildcard-shaped witness.
    let witnesses = rendered(compute_match_usefulness(cx, [], pair_ty));
    assert.equal(witnesses.length(), 1);
    assert.is_true(
        witnesses[0].includes("OptionalPair") && witnesses[0].split("_").length() - 1 >= 2,
    );

    let false_false = mk_pair(DPat.type_test(bool_lit(false), opt_bool), DPat.type_test(bool_lit(false), opt_bool));
    let witnesses = rendered(compute_match_usefulness(cx, [false_false], pair_ty));
    // All `bool?` pairs except false/false are missing.
    assert.equal(witnesses.length(), 8);
    for (
        let expected in [
            "OptionalPair { true, true }",
            "OptionalPair { true, false }",
            "OptionalPair { true, null }",
            "OptionalPair { false, true }",
            "OptionalPair { false, null }",
            "OptionalPair { null, true }",
            "OptionalPair { null, false }",
            "OptionalPair { null, null }",
        ]
    ) {
        assert.is_true(witnesses.includes(expected));
    }

    let any_false = mk_pair(DPat.wildcard(opt_bool), DPat.type_test(bool_lit(false), opt_bool));
    let witnesses = rendered(compute_match_usefulness(cx, [any_false], pair_ty));
    // All pairs with a non-false right side are missing.
    assert.equal(witnesses.length(), 2);
    assert.is_true(witnesses.includes("OptionalPair { _, true }"));
    assert.is_true(witnesses.includes("OptionalPair { _, null }"))
}

// Port of rustc_pattern_analysis `test_empty`: `type Result = Ok | Err` where
// `Err` has a `never` payload and is uninhabited.
test "rustc port empty variant payloads are ignored" {
    let cx = TestingCtx.new();
    let ok = qtn("NeverOk");
    let err = qtn("NeverErr");
    let pair = qtn("NeverPair");
    let ok_ty = class_ty(ok);
    let err_ty = class_ty(err);
    let result_ty: root.types.Ty = root.types.TyUnion { members: [ok_ty, err_ty] };
    let pair_ty = class_ty(pair);

    cx.register(ok, [bool_ty()]);
    cx.register(err, [root.types.TyNever {}]);
    cx.register(pair, [bool_ty(), result_ty]);

    let ok_any = () -> DPat {
        DPat.class_(ok, [DPat.wildcard(bool_ty())], ok_ty)
    };

    // Ok(_) exhausts Result<bool, Never>.
    let report = compute_match_usefulness(cx, [ok_any()], result_ty);
    assert.equal(rendered(report), []);

    let mk_pair = (b: bool) -> DPat {
        DPat.class_(pair, [DPat.type_test(bool_lit(b), bool_ty()), ok_any()], pair_ty)
    };
    // Covering bool with Ok(_) exhausts (bool, Result<bool, Never>).
    let report = compute_match_usefulness(cx, [mk_pair(true), mk_pair(false)], pair_ty);
    assert.equal(report.missing.length(), 0)
}

// Port of the finite bool witness check in rustc_pattern_analysis
// `test_witnesses`.
test "rustc port bool empty match witnesses" {
    let report = compute_match_usefulness(TestingCtx.new(), [], bool_ty());
    assert.equal(rendered(report), ["true", "false"])
}

// The "large enum" shape: a tagged enum with bool payloads is a union of
// classes, and a wildcard after every variant is unreachable.
test "rustc port large enum type union with trailing wildcard" {
    let cx = TestingCtx.new();
    let variants = baml.Array.generate(20, (i) -> {
        qtn(
            if (i < 10) {
                `V0${i}`
            } else {
                `V${i}`
            },
        )
    });
    for (let variant in variants) {
        cx.register(variant, [bool_ty()]);
    }
    let scrut: root.types.Ty = root.types.TyUnion {
        members: variants.map((v) -> {
            class_ty(v)
        }),
    };
    let arms = variants.map((variant) -> {
        DPat.class_(variant, [DPat.wildcard(bool_ty())], class_ty(variant))
    });
    arms.push(DPat.wildcard(scrut));

    let report = compute_match_usefulness(cx, arms, scrut);
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, [20])
}

// `[_, ..]` misses `[]`, so a following `_` arm is still useful.
test "rustc port slice prefix then wildcard keeps short length reachable" {
    let scrut: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let non_empty = DPat.slice(var_shape(1, 0), [DPat.wildcard(bool_ty())], scrut);
    let report = compute_match_usefulness(TestingCtx.new(), [non_empty, DPat.wildcard(scrut)], scrut);
    assert.equal(report.missing.length(), 0);
    // The wildcard arm covers the empty-list case.
    assert.equal(report.unreachable_arms, [])
}

// `class Quad { a, b, c, d: bool }`: all 16 combinations are exhaustive;
// dropping one reports exactly that one.
test "testing 1 cartesian quad all combos" {
    let cx = TestingCtx.new();
    let q = qtn("Quad");
    cx.register(q, [bool_ty(), bool_ty(), bool_ty(), bool_ty()]);
    let qty = class_ty(q);

    let combo = (i: int) -> DPat {
        DPat.class_(
            q,
            [1, 2, 4, 8].map((bit) -> {
                DPat.type_test(bool_lit((i & bit) != 0), bool_ty())
            }),
            qty,
        )
    };

    let all = baml.Array.generate(16, (i) -> {
        i
    });
    let report = compute_match_usefulness(cx, all.map(combo), qty);
    assert.equal(rendered(report), []);

    // Drop (true, false, true, false): exactly that one is missing.
    let arms = all
        .filter((i) -> {
            i != (1 | 4)
        })
        .map(combo);
    let report = compute_match_usefulness(cx, arms, qty);
    assert.equal(report.missing.length(), 1);
    let w = rendered(report)[0];
    assert.is_true(w.includes("true") && w.includes("false"))
}

// A wildcard mid-pattern expands coverage: `{ a: true, b: _ }` covers both
// values of `b`.
test "testing 1b wildcard in class field" {
    let cx = TestingCtx.new();
    let q = qtn("Pair");
    cx.register(q, [bool_ty(), bool_ty()]);
    let qty = class_ty(q);

    let arm1 = DPat.class_(q, [DPat.type_test(bool_lit(true), bool_ty()), DPat.wildcard(bool_ty())], qty);
    let arm2 = DPat.class_(q, [DPat.type_test(bool_lit(false), bool_ty()), DPat.wildcard(bool_ty())], qty);
    let report = compute_match_usefulness(cx, [arm1, arm2], qty);
    assert.equal(rendered(report), [])
}

// `[true, ..rest, false]` + `[..rest]` covers everything.
test "testing 2 variable prefix suffix" {
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let arm1 = DPat.slice(
        var_shape(1, 1),
        [DPat.type_test(bool_lit(true), bool_ty()), DPat.type_test(bool_lit(false), bool_ty())],
        arr,
    );
    let arm2 = DPat.slice(var_shape(0, 0), [], arr);
    let report = compute_match_usefulness(TestingCtx.new(), [arm1, arm2], arr);
    assert.equal(rendered(report), []);
    assert.equal(report.unreachable_arms, [])
}

// `[]`, `[_]`, `[_, _]`, `[_, _, _, ..]` covers all lengths; dropping one
// leaves a witness; a literal pair after `[_, _]` is unreachable.
test "testing 3 mixed lengths" {
    let cx = TestingCtx.new();
    let arr: root.types.Ty = root.types.TyList { elem: int_ty() };
    let arm0 = DPat.slice(fixed(0), [], arr);
    let arm1 = DPat.slice(fixed(1), [DPat.wildcard(int_ty())], arr);
    let arm2 = DPat.slice(fixed(2), [DPat.wildcard(int_ty()), DPat.wildcard(int_ty())], arr);
    let arm3plus = DPat.slice(
        var_shape(3, 0),
        [DPat.wildcard(int_ty()), DPat.wildcard(int_ty()), DPat.wildcard(int_ty())],
        arr,
    );

    // (a) All four: exhaustive.
    let report = compute_match_usefulness(cx, [arm0, arm1, arm2, arm3plus], arr);
    assert.equal(rendered(report), []);

    // (b) Drop arm2: non-exhaustive.
    let report = compute_match_usefulness(cx, [arm0, arm1, arm3plus], arr);
    assert.is_true(report.missing.length() > 0);

    // (c) `[1, 2]` after arm2 is unreachable.
    let arm_lit = DPat.slice(
        fixed(2),
        [DPat.type_test(int_lit(1), int_ty()), DPat.type_test(int_lit(2), int_ty())],
        arr,
    );
    let report = compute_match_usefulness(cx, [arm0, arm1, arm2, arm_lit, arm3plus], arr);
    assert.is_true(report.unreachable_arms.includes(3))
}

// `Array<Result>` where `Result = { ok: bool, val: bool }`. Dropping the
// false-ok branch leaves a nested witness mentioning `false`.
test "testing 4 array of classes" {
    let cx = TestingCtx.new();
    let r = qtn("Result");
    cx.register(r, [bool_ty(), bool_ty()]);
    let result_ty = class_ty(r);
    let arr: root.types.Ty = root.types.TyList { elem: result_ty };

    let make_class = (ok: bool, val: bool?) -> DPat {
        let val_pat = if (val != null) {
            DPat.type_test(bool_lit(val), bool_ty())
        } else {
            DPat.wildcard(bool_ty())
        };
        DPat.class_(r, [DPat.type_test(bool_lit(ok), bool_ty()), val_pat], result_ty)
    };

    let len0 = DPat.slice(fixed(0), [], arr);
    let len1_ok = DPat.slice(fixed(1), [make_class(true, null)], arr);
    let len1_err = DPat.slice(fixed(1), [make_class(false, null)], arr);
    let len2plus = DPat.slice(var_shape(2, 0), [DPat.wildcard(result_ty), DPat.wildcard(result_ty)], arr);

    let report = compute_match_usefulness(cx, [len0, len1_ok, len1_err, len2plus], arr);
    assert.equal(rendered(report), []);

    let report = compute_match_usefulness(cx, [len0, len1_ok, len2plus], arr);
    assert.is_true(report.missing.length() > 0);
    assert.is_true(
        rendered(report).some((s) -> {
            s.includes("false")
        }),
    )
}

// `class Container { tag: bool, items: bool[] }`: dropping a nested
// fixed-length slice surfaces a witness.
test "testing 5 class with array field" {
    let cx = TestingCtx.new();
    let c = qtn("Container");
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    cx.register(c, [bool_ty(), arr]);
    let cty = class_ty(c);

    let cont = (tag: bool, items: DPat) -> DPat {
        DPat.class_(c, [DPat.type_test(bool_lit(tag), bool_ty()), items], cty)
    };
    let true_empty = cont(true, DPat.slice(fixed(0), [], arr));
    let true_nonempty = cont(true, DPat.slice(var_shape(1, 0), [DPat.wildcard(bool_ty())], arr));
    let false_any = cont(false, DPat.wildcard(arr));

    let report = compute_match_usefulness(cx, [true_empty, true_nonempty, false_any], cty);
    assert.equal(rendered(report), []);

    let report = compute_match_usefulness(cx, [true_nonempty, false_any], cty);
    assert.is_true(report.missing.length() > 0)
}

// `bool??`: the two `null`s are one ctor, so `{true, false, null}` is
// exhaustive and a second `null` arm unreachable.
test "testing 6 double optional" {
    let cx = TestingCtx.new();
    let outer = root.types.optional(root.types.optional(bool_ty()));
    let null_ty: root.types.Ty = root.types.TyNull {};

    let null_ = DPat.type_test(null_ty, outer);
    let inner_null = DPat.type_test(null_ty, outer);
    let bool_true = DPat.type_test(bool_lit(true), outer);
    let bool_false = DPat.type_test(bool_lit(false), outer);

    let report = compute_match_usefulness(cx, [null_, bool_true, bool_false], outer);
    assert.equal(rendered(report), []);
    let report = compute_match_usefulness(cx, [null_, inner_null, bool_true, bool_false], outer);
    assert.is_true(report.unreachable_arms.includes(1))
}

// Or-pattern `1 | 2` pre-expanded to two rows: a later `2` is unreachable,
// `3` completes coverage.
test "testing 7 or pattern unreachable" {
    let scrut: root.types.Ty = root.types.TyUnion { members: [int_lit(1), int_lit(2), int_lit(3)] };
    let arms = [
        DPat.type_test(int_lit(1), scrut),
        DPat.type_test(int_lit(2), scrut),
        DPat.type_test(int_lit(2), scrut),
        DPat.type_test(int_lit(3), scrut),
    ];
    let report = compute_match_usefulness(TestingCtx.new(), arms, scrut);
    assert.equal(rendered(report), []);
    assert.is_true(report.unreachable_arms.includes(2))
}

// `Ok | Err` with destructuring: dropping `Ok { val: false }` reports it.
test "testing 8 discriminated union" {
    let cx = TestingCtx.new();
    let ok = qtn("Ok");
    let err = qtn("Err");
    cx.register(ok, [bool_ty()]);
    cx.register(err, [int_ty()]);
    let ok_ty = class_ty(ok);
    let err_ty = class_ty(err);
    let scrut: root.types.Ty = root.types.TyUnion { members: [ok_ty, err_ty] };

    let mk_ok = (v: bool) -> DPat {
        DPat.class_(ok, [DPat.type_test(bool_lit(v), bool_ty())], ok_ty)
    };
    let any_err = DPat.class_(err, [DPat.wildcard(int_ty())], err_ty);

    let report = compute_match_usefulness(cx, [mk_ok(true), mk_ok(false), any_err], scrut);
    assert.equal(rendered(report), []);

    let report = compute_match_usefulness(cx, [mk_ok(true), any_err], scrut);
    assert.is_true(
        rendered(report).some((s) -> {
            s.includes("Ok") && s.includes("false")
        }),
    )
}

// `class Wrapper<T> { inner: T }` simulated as two classes: with `int` the
// inner wildcard is required, with `bool` both literals exhaust.
test "testing 9 generic substitution" {
    let cx = TestingCtx.new();
    let w_int = qtn("WrapperInt");
    let w_bool = qtn("WrapperBool");
    cx.register(w_int, [int_ty()]);
    cx.register(w_bool, [bool_ty()]);

    let scrut = class_ty(w_int);
    let report = compute_match_usefulness(cx, [DPat.class_(w_int, [DPat.wildcard(int_ty())], scrut)], scrut);
    assert.equal(rendered(report), []);

    let scrut = class_ty(w_bool);
    let arms = [
        DPat.class_(w_bool, [DPat.type_test(bool_lit(true), bool_ty())], scrut),
        DPat.class_(w_bool, [DPat.type_test(bool_lit(false), bool_ty())], scrut),
    ];
    let report = compute_match_usefulness(cx, arms, scrut);
    assert.equal(rendered(report), [])
}

// A missing witness renders with the class name.
test "testing 10 witness exact rendering" {
    let cx = TestingCtx.new();
    let p = qtn("Pair");
    cx.register(p, [bool_ty(), bool_ty()]);
    let pty = class_ty(p);

    let arm = DPat.class_(
        p,
        [DPat.type_test(bool_lit(true), bool_ty()), DPat.type_test(bool_lit(true), bool_ty())],
        pty,
    );
    let strs = rendered(compute_match_usefulness(cx, [arm], pty));
    // Three missing combos: (T,F), (F,T), (F,F).
    assert.equal(strs.length(), 3);
    assert.is_true(
        strs.every((s) -> {
            s.includes("Pair") || s.includes("user.Pair")
        }),
    )
}

// `class A { b: B }; class B { c: C[] }; class C { v: bool }`: a deeply
// nested missing case unwinds.
test "testing 11 deep nesting" {
    let cx = TestingCtx.new();
    let a = qtn("A");
    let b = qtn("B");
    let c = qtn("C");
    cx.register(c, [bool_ty()]);
    let c_ty = class_ty(c);
    let c_list: root.types.Ty = root.types.TyList { elem: c_ty };
    cx.register(b, [c_list]);
    let b_ty = class_ty(b);
    cx.register(a, [b_ty]);
    let a_ty = class_ty(a);

    // A { b: B { c: [] } }
    let arm = DPat.class_(a, [DPat.class_(b, [DPat.slice(fixed(0), [], c_list)], b_ty)], a_ty);
    let report = compute_match_usefulness(cx, [arm], a_ty);
    assert.is_true(report.missing.length() > 0)
}

// An empty-array-only arm against `int[]` leaves non-empty arrays missing.
test "testing 12a empty only arm for list" {
    let arr: root.types.Ty = root.types.TyList { elem: int_ty() };
    let report = compute_match_usefulness(TestingCtx.new(), [DPat.slice(fixed(0), [], arr)], arr);
    assert.is_true(report.missing.length() > 0)
}

// A match on `never` with zero arms is vacuously exhaustive.
test "testing 12b never zero arms exhaustive" {
    let report = compute_match_usefulness(TestingCtx.new(), [], root.types.TyNever {});
    assert.equal(report.missing.length(), 0)
}

// `[..rest]` first makes a later `[true]` unreachable.
test "testing 13 var covers fixed unreachable" {
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let any = DPat.slice(var_shape(0, 0), [], arr);
    let one_true = DPat.slice(fixed(1), [DPat.type_test(bool_lit(true), bool_ty())], arr);
    let report = compute_match_usefulness(TestingCtx.new(), [any, one_true], arr);
    assert.equal(report.missing.length(), 0);
    assert.is_true(report.unreachable_arms.includes(1))
}

// `[a, ..r]` and `[..r, b]` both match exactly `length >= 1`: the second is
// redundant and `[]` is missing.
test "testing 14 two vars redundant coverage" {
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let pre = DPat.slice(var_shape(1, 0), [DPat.wildcard(bool_ty())], arr);
    let suf = DPat.slice(var_shape(0, 1), [DPat.wildcard(bool_ty())], arr);
    let report = compute_match_usefulness(TestingCtx.new(), [pre, suf], arr);
    assert.is_true(rendered(report).includes("[]"));
    assert.is_true(report.unreachable_arms.includes(1))
}

// `[_, ..rest]` alone misses `[]`.
test "testing 15 prefix only var misses zero" {
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let arm = DPat.slice(var_shape(1, 0), [DPat.wildcard(bool_ty())], arr);
    let report = compute_match_usefulness(TestingCtx.new(), [arm], arr);
    assert.is_true(rendered(report).includes("[]"))
}

// `[a, b, ..rest]` misses lengths 0 and 1.
test "testing 16 arity2 var misses short lengths" {
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let arm = DPat.slice(var_shape(2, 0), [DPat.wildcard(bool_ty()), DPat.wildcard(bool_ty())], arr);
    let strs = rendered(compute_match_usefulness(TestingCtx.new(), [arm], arr));
    assert.is_true(strs.includes("[]"));
    // A single-element witness: `[_]`, `[true]` or `[false]`.
    let has_length_one = strs.some((s) -> {
        s.starts_with("[")
            && s.ends_with("]")
            && !s.includes(",")
            && !s.includes("..")
            && s.length() > 2
    });
    assert.is_true(has_length_one)
}

// `[..r]` covers a later `[a, b]`.
test "testing 17 var covers long fixed" {
    let arr: root.types.Ty = root.types.TyList { elem: int_ty() };
    let any = DPat.slice(var_shape(0, 0), [], arr);
    let pair = DPat.slice(fixed(2), [DPat.wildcard(int_ty()), DPat.wildcard(int_ty())], arr);
    let report = compute_match_usefulness(TestingCtx.new(), [any, pair], arr);
    assert.equal(report.missing.length(), 0);
    assert.is_true(report.unreachable_arms.includes(1))
}

// `[a, b, c, ..r, d]` alone leaves lengths 0..=3 missing; `[..r]` completes
// it.
test "testing 18 asymmetric var" {
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let var31 = DPat.slice(
        var_shape(3, 1),
        [
            DPat.wildcard(bool_ty()),
            DPat.wildcard(bool_ty()),
            DPat.wildcard(bool_ty()),
            DPat.wildcard(bool_ty()),
        ],
        arr,
    );
    let report = compute_match_usefulness(TestingCtx.new(), [var31], arr);
    assert.is_true(report.missing.length() > 0);

    let any = DPat.slice(var_shape(0, 0), [], arr);
    let report = compute_match_usefulness(TestingCtx.new(), [var31, any], arr);
    assert.equal(rendered(report), [])
}

// `bool[][]` with `[[true, _]]`, `[[false, true]]`, `[..rest]`: exhaustive,
// and the first two arms stay useful.
test "testing 19 slice of slices" {
    let inner_ty: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let outer_ty: root.types.Ty = root.types.TyList { elem: inner_ty };

    let outer_one_inner = (inner_pat: DPat) -> DPat {
        DPat.slice(fixed(1), [inner_pat], outer_ty)
    };
    let inner_pat = (a: bool, b: bool?) -> DPat {
        let second = if (b != null) {
            DPat.type_test(bool_lit(b), bool_ty())
        } else {
            DPat.wildcard(bool_ty())
        };
        DPat.slice(fixed(2), [DPat.type_test(bool_lit(a), bool_ty()), second], inner_ty)
    };
    let arm1 = outer_one_inner(inner_pat(true, null));
    let arm2 = outer_one_inner(inner_pat(false, true));
    let arm3 = DPat.slice(var_shape(0, 0), [], outer_ty);

    let report = compute_match_usefulness(TestingCtx.new(), [arm1, arm2, arm3], outer_ty);
    assert.equal(rendered(report), []);
    assert.is_true(!report.unreachable_arms.includes(0));
    assert.is_true(!report.unreachable_arms.includes(1))
}

// `Pair[]` where `Pair = { a, b: bool }`: dropping length-1 with `a: false`
// leaves a witness mentioning `false`.
test "testing 20 array of class destructure" {
    let cx = TestingCtx.new();
    let p = qtn("Pair");
    cx.register(p, [bool_ty(), bool_ty()]);
    let pty = class_ty(p);
    let arr: root.types.Ty = root.types.TyList { elem: pty };

    let pair = (a: bool) -> DPat {
        DPat.class_(p, [DPat.type_test(bool_lit(a), bool_ty()), DPat.wildcard(bool_ty())], pty)
    };
    let len0 = DPat.slice(fixed(0), [], arr);
    let len1_true = DPat.slice(fixed(1), [pair(true)], arr);
    let len1_false = DPat.slice(fixed(1), [pair(false)], arr);
    let len2plus = DPat.slice(var_shape(2, 0), [DPat.wildcard(pty), DPat.wildcard(pty)], arr);

    let report = compute_match_usefulness(cx, [len0, len1_true, len1_false, len2plus], arr);
    assert.equal(rendered(report), []);

    let report = compute_match_usefulness(cx, [len0, len1_true, len2plus], arr);
    assert.is_true(
        rendered(report).some((s) -> {
            s.includes("false")
        }),
    )
}

// `class Holder { items: bool[] }` matched as `{ items: [..rest] }` alone is
// exhaustive.
test "testing 21 class with var slice field" {
    let cx = TestingCtx.new();
    let h = qtn("Holder");
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    cx.register(h, [arr]);
    let hty = class_ty(h);

    let arm = DPat.class_(h, [DPat.slice(var_shape(0, 0), [], arr)], hty);
    let report = compute_match_usefulness(cx, [arm], hty);
    assert.equal(rendered(report), [])
}

// `class Empty {}` matched as `{}` is exhaustive.
test "testing 22 empty class" {
    let cx = TestingCtx.new();
    let e = qtn("Empty");
    cx.register(e, []);
    let ety = class_ty(e);
    let report = compute_match_usefulness(cx, [DPat.class_(e, [], ety)], ety);
    assert.equal(report.missing.length(), 0)
}

// `class Outer { rows: Inner[] }; class Inner { val: bool }`: one deep path
// covered leaves cases missing.
test "testing 23 class slice class nesting" {
    let cx = TestingCtx.new();
    let outer = qtn("Outer");
    let inner = qtn("Inner");
    cx.register(inner, [bool_ty()]);
    let inner_ty = class_ty(inner);
    let inner_arr: root.types.Ty = root.types.TyList { elem: inner_ty };
    cx.register(outer, [inner_arr]);
    let outer_ty = class_ty(outer);

    let mk_inner = (v: bool) -> DPat {
        DPat.class_(inner, [DPat.type_test(bool_lit(v), bool_ty())], inner_ty)
    };
    let arm = DPat.class_(outer, [DPat.slice(fixed(1), [mk_inner(true)], inner_arr)], outer_ty);
    let report = compute_match_usefulness(cx, [arm], outer_ty);
    assert.is_true(report.missing.length() > 0)
}

// `_` first makes a later `{a: true, b: false}` unreachable.
test "testing 24 wildcard makes structural unreachable" {
    let cx = TestingCtx.new();
    let p = qtn("Pair");
    cx.register(p, [bool_ty(), bool_ty()]);
    let pty = class_ty(p);

    let specific = DPat.class_(
        p,
        [DPat.type_test(bool_lit(true), bool_ty()), DPat.type_test(bool_lit(false), bool_ty())],
        pty,
    );
    let report = compute_match_usefulness(cx, [DPat.wildcard(pty), specific], pty);
    assert.equal(report.missing.length(), 0);
    assert.is_true(report.unreachable_arms.includes(1))
}

// `{a: true, b: _}` and `{a: false, b: _}` are exhaustive with no top-level
// wildcard.
test "testing 25 no top wildcard exhaustive" {
    let cx = TestingCtx.new();
    let p = qtn("Pair");
    cx.register(p, [bool_ty(), bool_ty()]);
    let pty = class_ty(p);

    let mk = (a: bool) -> DPat {
        DPat.class_(p, [DPat.type_test(bool_lit(a), bool_ty()), DPat.wildcard(bool_ty())], pty)
    };
    let report = compute_match_usefulness(cx, [mk(true), mk(false)], pty);
    assert.equal(rendered(report), [])
}

// `[1 | 2, _]` pre-expanded to `[1, _]` and `[2, _]`, then `[3, _]` and a
// wildcard: every row is reachable.
test "testing 26 or pattern simulated rows" {
    let arr: root.types.Ty = root.types.TyList { elem: int_ty() };
    let arm = (v: int) -> DPat {
        DPat.slice(fixed(2), [DPat.type_test(int_lit(v), int_ty()), DPat.wildcard(int_ty())], arr)
    };
    let report = compute_match_usefulness(TestingCtx.new(), [arm(1), arm(2), arm(3), DPat.wildcard(arr)], arr);
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, [])
}
