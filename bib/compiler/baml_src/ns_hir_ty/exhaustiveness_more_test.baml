// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests @ d9be6853b
//
// The second half of exhaustiveness.rs's tests; contexts and helpers are in
// exhaustiveness_test.baml.

// `class Octet { f0..f7: bool }`: all 256 combinations are exhaustive;
// dropping one (180) leaves exactly one missing.
test "testing 27 8bit cartesian" {
    let cx = TestingCtx.new();
    let q = qtn("Octet");
    cx.register(q, baml.Array.filled(8, bool_ty()));
    let qty = class_ty(q);

    let combo = (bits: int) -> DPat {
        DPat.class_(
            q,
            baml.Array.generate(8, (i) -> {
                DPat.type_test(bool_lit(((bits >> i) & 1) != 0), bool_ty())
            }),
            qty,
        )
    };

    let all = baml.Array.generate(256, (i) -> {
        i
    });
    let report = compute_match_usefulness(cx, all.map(combo), qty);
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, []);

    let arms = all
        .filter((b) -> {
            b != 180
        })
        .map(combo);
    let report = compute_match_usefulness(cx, arms, qty);
    assert.equal(report.missing.length(), 1)
}

// `class Node { val: bool, next: Node? }`: null plus `Node(_)` is exhaustive;
// dropping the class arm leaves a `Node` witness.
test "testing 28 linked list recursion" {
    let cx = TestingCtx.new();
    let n = qtn("Node");
    let n_ty = class_ty(n);
    let opt_n = root.types.optional(n_ty);
    cx.register(n, [bool_ty(), opt_n]);
    let scrut = opt_n;

    let null_top = DPat.type_test(root.types.TyNull {}, scrut);
    let some_any = DPat.class_(n, [DPat.wildcard(bool_ty()), DPat.wildcard(opt_n)], n_ty);

    let report = compute_match_usefulness(cx, [null_top, some_any], scrut);
    assert.equal(rendered(report), []);

    let report = compute_match_usefulness(cx, [null_top], scrut);
    assert.is_true(
        rendered(report).some((s) -> {
            s.includes("Node")
        }),
    )
}

// `A.b: B.c: C.d: D.e: E.v: bool`: covering only `v: true` leaves one
// witness that keeps the whole chain and `false` at the leaf.
test "testing 29 5level deep nesting" {
    let cx = TestingCtx.new();
    let e = qtn("E");
    cx.register(e, [bool_ty()]);
    let e_ty = class_ty(e);
    let d = qtn("D");
    cx.register(d, [e_ty]);
    let d_ty = class_ty(d);
    let c = qtn("C");
    cx.register(c, [d_ty]);
    let c_ty = class_ty(c);
    let b = qtn("B");
    cx.register(b, [c_ty]);
    let b_ty = class_ty(b);
    let a = qtn("A");
    cx.register(a, [b_ty]);
    let a_ty = class_ty(a);

    let mk = (v: bool) -> DPat {
        let leaf = DPat.class_(e, [DPat.type_test(bool_lit(v), bool_ty())], e_ty);
        DPat.class_(
            a,
            [DPat.class_(b, [DPat.class_(c, [DPat.class_(d, [leaf], d_ty)], c_ty)], b_ty)],
            a_ty,
        )
    };

    let report = compute_match_usefulness(cx, [mk(true), mk(false)], a_ty);
    assert.equal(rendered(report), []);

    let report = compute_match_usefulness(cx, [mk(true)], a_ty);
    assert.equal(report.missing.length(), 1);
    let s = rendered(report)[0];
    assert.is_true(
        s.includes("A") && s.includes("B") && s.includes("C") && s.includes("D") && s.includes("E"),
    );
    assert.is_true(s.includes("false"))
}

// `bool[][][]`: a `[..]` catch-all at the outer level makes a deep arm's
// match exhaustive; without it many cases are missing.
test "testing 30 3d slice" {
    let lvl1: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let lvl2: root.types.Ty = root.types.TyList { elem: lvl1 };
    let lvl3: root.types.Ty = root.types.TyList { elem: lvl2 };

    // [[[true]]]
    let deep = () -> DPat {
        let inner_true = DPat.slice(fixed(1), [DPat.type_test(bool_lit(true), bool_ty())], lvl1);
        let mid = DPat.slice(fixed(1), [inner_true], lvl2);
        DPat.slice(fixed(1), [mid], lvl3)
    };
    let any = DPat.slice(var_shape(0, 0), [], lvl3);

    let report = compute_match_usefulness(TestingCtx.new(), [deep(), any], lvl3);
    assert.equal(rendered(report), []);
    assert.equal(report.unreachable_arms, []);

    let report = compute_match_usefulness(TestingCtx.new(), [deep()], lvl3);
    assert.is_true(report.missing.length() > 0)
}

// `{a: T, b: _}` and `{a: _, b: F}` leave only `(F, T)` missing: a later
// `(T, F)` is redundant, `(F, T)` completes coverage.
test "testing 31 subsumption redundancy" {
    let cx = TestingCtx.new();
    let p = qtn("Pair");
    cx.register(p, [bool_ty(), bool_ty()]);
    let pty = class_ty(p);

    let field = (v: bool?) -> DPat {
        if (v != null) {
            DPat.type_test(bool_lit(v), bool_ty())
        } else {
            DPat.wildcard(bool_ty())
        }
    };
    let mk = (a: bool?, b: bool?) -> DPat {
        DPat.class_(p, [field(a), field(b)], pty)
    };
    let a_true_any = mk(true, null);
    let any_b_false = mk(null, false);
    let t_f = mk(true, false);
    let f_t = mk(false, true);

    // (a) After two arms, `(F, T)` is missing.
    let report = compute_match_usefulness(cx, [a_true_any, any_b_false], pty);
    assert.equal(report.missing.length(), 1);
    let s = rendered(report)[0];
    assert.is_true(s.includes("false") && s.includes("true"));

    // (b) `(T, F)` is subsumed by both prior arms.
    let report = compute_match_usefulness(cx, [a_true_any, any_b_false, t_f], pty);
    assert.is_true(report.unreachable_arms.includes(2));

    // (c) `(F, T)` plugs the hole.
    let report = compute_match_usefulness(cx, [a_true_any, any_b_false, f_t], pty);
    assert.equal(report.missing.length(), 0)
}

// A union of 15 classes: all covered is exhaustive; dropping `G` reports it.
test "testing 32 alphabet union" {
    let cx = TestingCtx.new();
    let qtns = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O"].map((n) -> {
        qtn(n)
    });
    for (let q in qtns) {
        cx.register(q, []);
    }
    let scrut: root.types.Ty = root.types.TyUnion {
        members: qtns.map((q) -> {
            class_ty(q)
        }),
    };
    let arm = (q: root.types.DeclName) -> DPat {
        DPat.class_(q, [], class_ty(q))
    };

    let report = compute_match_usefulness(cx, qtns.map(arm), scrut);
    assert.equal(report.missing.length(), 0);

    let arms = qtns
        .filter((q) -> {
            q.name != "G"
        })
        .map(arm);
    let report = compute_match_usefulness(cx, arms, scrut);
    assert.equal(report.missing.length(), 1);
    assert.is_true(rendered(report)[0].includes("G"))
}

// `class O { rows: M[] }; class M { items: I[] }; class I { v: bool }`: a
// single deep arm leaves many cases missing.
test "testing 33 alternating structural" {
    let cx = TestingCtx.new();
    let i = qtn("I");
    cx.register(i, [bool_ty()]);
    let i_ty = class_ty(i);
    let i_arr: root.types.Ty = root.types.TyList { elem: i_ty };
    let m = qtn("M");
    cx.register(m, [i_arr]);
    let m_ty = class_ty(m);
    let m_arr: root.types.Ty = root.types.TyList { elem: m_ty };
    let o = qtn("O");
    cx.register(o, [m_arr]);
    let o_ty = class_ty(o);

    // O { rows: [M { items: [I { v: true }] }] }
    let inner = DPat.class_(i, [DPat.type_test(bool_lit(true), bool_ty())], i_ty);
    let mid = DPat.class_(m, [DPat.slice(fixed(1), [inner], i_arr)], m_ty);
    let outer = DPat.class_(o, [DPat.slice(fixed(1), [mid], m_arr)], o_ty);

    let report = compute_match_usefulness(cx, [outer], o_ty);
    assert.is_true(report.missing.length() > 0)
}

// `Variable { prefix: 5, suffix: 3 }` plus a `[..]` catch-all is exhaustive.
test "testing 34 wide variable slice" {
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let var53 = DPat.slice(
        var_shape(5, 3),
        baml.Array.generate(8, (i) -> {
            DPat.wildcard(bool_ty())
        }),
        arr,
    );
    let any = DPat.slice(var_shape(0, 0), [], arr);
    let report = compute_match_usefulness(TestingCtx.new(), [var53, any], arr);
    assert.equal(rendered(report), [])
}

// `class Triple { a, b, c: bool }` covered by four partial-wildcard arms.
test "testing 35 partial wildcard cartesian" {
    let cx = TestingCtx.new();
    let t = qtn("Triple");
    cx.register(t, [bool_ty(), bool_ty(), bool_ty()]);
    let tty = class_ty(t);

    let mk = (a: bool, b: bool) -> DPat {
        DPat.class_(
            t,
            [
                DPat.type_test(bool_lit(a), bool_ty()),
                DPat.type_test(bool_lit(b), bool_ty()),
                DPat.wildcard(bool_ty()),
            ],
            tty,
        )
    };
    let arms = [mk(true, true), mk(true, false), mk(false, true), mk(false, false)];
    let report = compute_match_usefulness(cx, arms, tty);
    assert.equal(rendered(report), [])
}

// 64 arms over a 6-bool class: exhaustive, no blow-up.
test "testing 36 64 arm scale" {
    let cx = TestingCtx.new();
    let q = qtn("Sextet");
    cx.register(q, baml.Array.filled(6, bool_ty()));
    let qty = class_ty(q);

    let combo = (bits: int) -> DPat {
        DPat.class_(
            q,
            baml.Array.generate(6, (i) -> {
                DPat.type_test(bool_lit(((bits >> i) & 1) != 0), bool_ty())
            }),
            qty,
        )
    };
    let arms = baml.Array.generate(64, (i) -> {
        combo(i)
    });
    let report = compute_match_usefulness(cx, arms, qty);
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, [])
}

// `class P { a, b: bool }` with 3 of 4 combos: exactly one witness.
test "testing 37 witness uniqueness" {
    let cx = TestingCtx.new();
    let p = qtn("P");
    cx.register(p, [bool_ty(), bool_ty()]);
    let pty = class_ty(p);
    let mk = (a: bool, b: bool) -> DPat {
        DPat.class_(
            p,
            [DPat.type_test(bool_lit(a), bool_ty()), DPat.type_test(bool_lit(b), bool_ty())],
            pty,
        )
    };
    let report = compute_match_usefulness(cx, [mk(true, true), mk(true, false), mk(false, true)], pty);
    assert.equal(report.missing.length(), 1)
}

// `class A { x, y, z: B }; class B { p, q: bool }`: all 64 combinations
// through 64 structural arms.
test "testing 38 mixed deep wide" {
    let cx = TestingCtx.new();
    let b = qtn("B");
    cx.register(b, [bool_ty(), bool_ty()]);
    let b_ty = class_ty(b);
    let a = qtn("A");
    cx.register(a, [b_ty, b_ty, b_ty]);
    let a_ty = class_ty(a);

    let mk_b_n = (bits: int) -> DPat {
        DPat.class_(
            b,
            [
                DPat.type_test(bool_lit((bits & 1) != 0), bool_ty()),
                DPat.type_test(bool_lit((bits & 2) != 0), bool_ty()),
            ],
            b_ty,
        )
    };
    let arms: DPat[] = [];
    for (let px in [0, 1, 2, 3]) {
        for (let py in [0, 1, 2, 3]) {
            for (let pz in [0, 1, 2, 3]) {
                arms.push(DPat.class_(a, [mk_b_n(px), mk_b_n(py), mk_b_n(pz)], a_ty));
            }
        }
    }
    assert.equal(arms.length(), 64);
    let report = compute_match_usefulness(cx, arms, a_ty);
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, [])
}

// `[..rest, true]` does not cover `[true, false]`: specialize aligns suffix
// fields to the rightmost positions.
test "testing 39 suffix slice does not cover wrong fixed tail" {
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let ends_true = DPat.slice(var_shape(0, 1), [DPat.type_test(bool_lit(true), bool_ty())], arr);
    let true_false = DPat.slice(
        fixed(2),
        [DPat.type_test(bool_lit(true), bool_ty()), DPat.type_test(bool_lit(false), bool_ty())],
        arr,
    );
    let report = compute_match_usefulness(TestingCtx.new(), [ends_true, true_false], arr);
    assert.is_true(!report.unreachable_arms.includes(1))
}

// `1 | 2 => a; 2 => b`: the reported unreachable arm is the source arm 1.
test "testing 40 or pattern source arm ids" {
    let scrut: root.types.Ty = root.types.TyUnion { members: [int_lit(1), int_lit(2)] };
    let arm0 = DPat.or([DPat.type_test(int_lit(1), scrut), DPat.type_test(int_lit(2), scrut)], scrut);
    let arm1 = DPat.type_test(int_lit(2), scrut);
    let report = compute_match_usefulness(TestingCtx.new(), [arm0, arm1], scrut);
    assert.equal(report.unreachable_arms, [1])
}

// A chain of 258 nested classes ending in `bool`, one arm matching the
// deepest `true`: the missing `false` leaf must surface.
test "testing 41 deep chain missing leaf" {
    let cx = TestingCtx.new();
    let qs = baml.Array.generate(258, (i) -> {
        qtn(`C${i}`)
    });
    let i = 0;
    for (let q in qs) {
        let field = if (i + 1 == qs.length()) {
            bool_ty()
        } else {
            class_ty(qs[i + 1])
        };
        cx.register(q, [field]);
        i += 1;
    }

    let pat = DPat.type_test(bool_lit(true), bool_ty());
    for (let q in qs.reverse()) {
        pat = DPat.class_(q, [pat], class_ty(q));
    }

    let report = compute_match_usefulness(cx, [pat], class_ty(qs[0]));
    assert.is_true(report.missing.length() > 0)
}

// `never[]` only inhabits `[]`, so a lone `[]` arm is exhaustive.
test "testing 42 list of never empty arm is exhaustive" {
    let arr: root.types.Ty = root.types.TyList { elem: root.types.TyNever {} };
    let report = compute_match_usefulness(TestingCtx.new(), [DPat.slice(fixed(0), [], arr)], arr);
    assert.equal(rendered(report), [])
}

// `bool??` enumerates `null` once per optional layer; the missing witness is
// one `null`.
test "testing 43 duplicate ctors deduped in missing" {
    let outer = root.types.optional(root.types.optional(bool_ty()));
    let arms = [DPat.type_test(bool_lit(true), outer), DPat.type_test(bool_lit(false), outer)];
    let report = compute_match_usefulness(TestingCtx.new(), arms, outer);
    assert.equal(rendered(report), ["null"])
}

// `class Inner { f: never }; class Outer { f: Inner }`: a zero-arm match on
// `Outer` is vacuously exhaustive.
test "testing 46 nested uninhabited class empty match exhaustive" {
    let cx = TestingCtx.new();
    let inner = qtn("Inner");
    let outer = qtn("Outer");
    cx.register(inner, [root.types.TyNever {}]);
    cx.register(outer, [class_ty(inner)]);
    let report = compute_match_usefulness(cx, [], class_ty(outer));
    assert.equal(rendered(report), [])
}

// A wildcard arm over an uninhabited scrutinee is unreachable.
test "testing 46c wildcard over uninhabited class unreachable" {
    let cx = TestingCtx.new();
    let empty = qtn("Empty");
    cx.register(empty, [root.types.TyNever {}]);
    let ty = class_ty(empty);
    let report = compute_match_usefulness(cx, [DPat.wildcard(ty)], ty);
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, [0])
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::UnionCtx @ d9be6853b
// Enumerates union members as `CtorUnionMember`s, as the real builder does.
class UnionCtx {
    classes: map<string, root.types.Ty[]>,

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::UnionCtx::new @ d9be6853b
    function new() -> UnionCtx throws never {
        UnionCtx { classes: {} }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::UnionCtx::register @ d9be6853b
    function register(
        self,
        qtn: root.types.DeclName,
        fields: root.types.Ty[],
    ) -> void throws never {
        self.classes.set(decl_name_ctor_identity(qtn), fields);
    }

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
                // Each union member becomes a `CtorUnionMember`.
                let u: root.types.TyUnion => {
                    u.members.map((m) -> {
                        let member: Ctor = CtorUnionMember { value: m };
                        member
                    })
                },
                root.types.TyLiteral | root.types.TyEnumVariant => [CtorType { value: ty }],
                let c: root.types.TyClass => [CtorClass { name: c.name, args: c.args }],
                root.types.TyList => [],
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
            match (ty) {
                let l: root.types.TyList => l.elem,
                _ => ty,
            }
        }
    }
}

// The union `Cls | int[]` of the UnionMember tests, with `Cls` registered.
class ClsOrInts {
    cx: UnionCtx,
    cls: root.types.DeclName,
    cls_ty: root.types.Ty,
    arr: root.types.Ty,
    scrut: root.types.Ty,

    function new() -> ClsOrInts throws never {
        let cx = UnionCtx.new();
        let cls = qtn("Cls");
        cx.register(cls, []);
        let cls_ty = class_ty(cls);
        let arr: root.types.Ty = root.types.TyList { elem: int_ty() };
        ClsOrInts {
            cx: cx,
            cls: cls,
            cls_ty: cls_ty,
            arr: arr,
            scrut: root.types.TyUnion { members: [cls_ty, arr] },
        }
    }

    // `Cls {}` through its union member.
    function class_arm(self) -> DPat throws never {
        DPat.union_member(self.cls_ty, DPat.class_(self.cls, [], self.cls_ty), self.scrut)
    }

    // A slice pattern through the `int[]` member.
    function slice_arm(self, shape: SliceShape, fields: DPat[]) -> DPat throws never {
        DPat.union_member(self.arr, DPat.slice(shape, fields, self.arr), self.scrut)
    }
}

// `Cls {} | [..]`: specializing on the `int[]` member recurses into a list
// column where `[..]` is exhaustive.
test "testing 47 union member slice wildcard exhaustive" {
    let u = ClsOrInts.new();
    let report = compute_match_usefulness(u.cx, [u.class_arm(), u.slice_arm(var_shape(0, 0), [])], u.scrut);
    assert.equal(rendered(report), [])
}

// `Cls {} | [_]`: lengths 0 and 2+ stay missing on the list branch.
test "testing 48 union member partial slice non exhaustive" {
    let u = ClsOrInts.new();
    let report = compute_match_usefulness(u.cx, [u.class_arm(), u.slice_arm(fixed(1), [DPat.wildcard(int_ty())])], u.scrut);
    assert.is_true(report.missing.length() > 0)
}

// `Cls {} | [] | [_, ..]`: the combined slice arms cover every length.
test "testing 49 union member combined slices exhaustive" {
    let u = ClsOrInts.new();
    let arms = [
        u.class_arm(),
        u.slice_arm(fixed(0), []),
        u.slice_arm(var_shape(1, 0), [DPat.wildcard(int_ty())]),
    ];
    let report = compute_match_usefulness(u.cx, arms, u.scrut);
    assert.equal(rendered(report), [])
}

// `Cls {}` alone: the list branch is missing.
test "testing 50 union member missing branch" {
    let u = ClsOrInts.new();
    let report = compute_match_usefulness(u.cx, [u.class_arm()], u.scrut);
    assert.is_true(report.missing.length() > 0)
}

// A wildcard arm covers every union member.
test "testing 51 union member wildcard covers all" {
    let u = ClsOrInts.new();
    let report = compute_match_usefulness(u.cx, [DPat.wildcard(u.scrut)], u.scrut);
    assert.equal(report.missing.length(), 0)
}

// `class A { x: A }` is treated as inhabited (the cycle guard is
// conservative), so a zero-arm match reports a missing case.
test "testing 46b self recursive class treated as inhabited" {
    let cx = TestingCtx.new();
    let a = qtn("A");
    let a_ty = class_ty(a);
    cx.register(a, [a_ty]);
    let report = compute_match_usefulness(cx, [], a_ty);
    assert.is_true(report.missing.length() > 0)
}

// `type Foo = bool`: the context expands the alias for enumeration, so
// `true` + `false` is exhaustive and `true` alone misses `false`.
test "testing 45 type alias expansion" {
    let cx = TestingCtx.new();
    let foo = qtn("Foo");
    cx.register_alias(foo, bool_ty());
    let alias_ty: root.types.Ty = root.types.TyTypeAlias { name: foo };

    let arms = [DPat.type_test(bool_lit(true), alias_ty), DPat.type_test(bool_lit(false), alias_ty)];
    let report = compute_match_usefulness(cx, arms, alias_ty);
    assert.equal(rendered(report), []);

    let report = compute_match_usefulness(cx, [DPat.type_test(bool_lit(true), alias_ty)], alias_ty);
    assert.equal(report.missing.length(), 1);
    assert.is_true(rendered(report)[0].includes("false"))
}

// `type Tri = 1 | 2 | 3` covered through the alias.
test "testing 45b alias to literal union" {
    let cx = TestingCtx.new();
    let tri = qtn("Tri");
    cx.register_alias(tri, root.types.TyUnion { members: [int_lit(1), int_lit(2), int_lit(3)] });
    let tri_ty: root.types.Ty = root.types.TyTypeAlias { name: tri };
    let arms = [
        DPat.type_test(int_lit(1), tri_ty),
        DPat.type_test(int_lit(2), tri_ty),
        DPat.type_test(int_lit(3), tri_ty),
    ];
    let report = compute_match_usefulness(cx, arms, tri_ty);
    assert.equal(rendered(report), [])
}

// `type Tree = Node?` with a recursive `Node` terminates.
test "testing 45c alias with recursion terminates" {
    let cx = TestingCtx.new();
    let n = qtn("Node");
    let n_ty = class_ty(n);
    let opt_n = root.types.optional(n_ty);
    cx.register(n, [bool_ty(), opt_n]);
    let alias = qtn("Tree");
    cx.register_alias(alias, opt_n);
    let alias_ty: root.types.Ty = root.types.TyTypeAlias { name: alias };

    let null_top = DPat.type_test(root.types.TyNull {}, alias_ty);
    let some_any = DPat.class_(n, [DPat.wildcard(bool_ty()), DPat.wildcard(opt_n)], n_ty);
    let report = compute_match_usefulness(cx, [null_top, some_any], alias_ty);
    assert.equal(rendered(report), [])
}

// A prefix-only variable witness renders its trailing `..` after a comma.
test "testing 44 prefix only var witness comma before rest" {
    let arr: root.types.Ty = root.types.TyList { elem: bool_ty() };
    let witness = WitnessPat.new(
        CtorSlice { value: var_shape(2, 0) },
        [WitnessPat.wildcard(bool_ty()), WitnessPat.wildcard(bool_ty())],
        arr,
    );
    assert.equal(witness.render(viewpoint()), "[_, _, ..]")
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::class_pair_missing_one_combo::PairCtx @ d9be6853b
class PairCtx {
    value: root.types.DeclName,

    implements PatCtx {
        function enumerate_ctors(self, ty: root.types.Ty) -> Ctor[] {
            match (ty) {
                root.types.TyBool => {
                    [CtorType { value: bool_lit(true) }, CtorType { value: bool_lit(false) }]
                },
                let c: root.types.TyClass => [CtorClass { name: self.value, args: c.args }],
                root.types.TyLiteral => [CtorType { value: ty }],
                _ => [CtorNonExhaustive {}],
            }
        }

        function class_field_types(
            self,
            q: root.types.DeclName,
            t: root.types.Ty,
        ) -> root.types.Ty[] {
            [bool_ty(), bool_ty()]
        }

        function list_element_type(self, ty: root.types.Ty) -> root.types.Ty {
            ty
        }
    }
}

// `class Pair { a, b: bool }` with `{ a: true, b: _ }` and
// `{ a: false, b: true }` misses `{ a: false, b: false }`.
test "class pair missing one combo" {
    let pair = qtn("Pair");
    let pair_ty = class_ty(pair);
    let arm1 = DPat.class_(
        pair,
        [DPat.type_test(bool_lit(true), bool_ty()), DPat.wildcard(bool_ty())],
        pair_ty,
    );
    let arm2 = DPat.class_(
        pair,
        [DPat.type_test(bool_lit(false), bool_ty()), DPat.type_test(bool_lit(true), bool_ty())],
        pair_ty,
    );
    let missing = rendered(compute_match_usefulness(PairCtx { value: pair }, [arm1, arm2], pair_ty));
    assert.equal(missing.length(), 1);
    assert.is_true(missing[0].includes("false, false"))
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::type_var_ty @ d9be6853b
// `Ty::type_var(name)`: the parameter at index 0.
function type_var_ty(name: string) -> root.types.Ty throws never {
    root.types.TyTypeVar { param: root.types.ParamTy { index: 0, name: name } }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::tests::projection_ty @ d9be6853b
function projection_ty(
    base: root.types.Ty,
    iface: string,
    member: string,
) -> root.types.Ty throws never {
    root.types.TyAssociatedTypeProjection {
        base: base,
        interface_: root.types.InterfaceConstraint { name: qtn(iface), generics: [], associated_types: [] },
        member: member,
    }
}

// Two constructions of the same projection agree; a different member or
// variable is a distinct identity.
test "ty ctor identity is stable for projections and typevars" {
    let a = projection_ty(type_var_ty("Self"), "Iterator", "Item");
    let b = projection_ty(type_var_ty("Self"), "Iterator", "Item");
    let other = projection_ty(type_var_ty("Self"), "Iterator", "Error");
    assert.equal(ty_ctor_identity(a), ty_ctor_identity(b));
    assert.is_true(ty_ctor_identity(a) != ty_ctor_identity(other));
    assert.equal(ty_ctor_identity(type_var_ty("T")), ty_ctor_identity(type_var_ty("T")));
    assert.is_true(ty_ctor_identity(type_var_ty("T")) != ty_ctor_identity(type_var_ty("U")))
}

// `let t: T` in a `bool` column covers nothing (the wildcard is required) but
// gets its own branch, so it is not flagged unreachable.
test "rigid single row in finite column is possible not covering" {
    let cx = TestingCtx.new();
    let rigid = DPat.type_test(type_var_ty("T"), bool_ty());
    let report = compute_match_usefulness(cx, [rigid, DPat.wildcard(bool_ty())], bool_ty());
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, []);

    // Without the wildcard the rigid row proves no coverage.
    let report = compute_match_usefulness(cx, [rigid], bool_ty());
    assert.is_true(report.missing.length() > 0);
    assert.equal(report.unreachable_arms, [])
}

// `let t: T` beside a complete concrete cover stays a live row.
test "rigid single row among full concrete cover is not unreachable" {
    let arms = [
        DPat.type_test(type_var_ty("T"), bool_ty()),
        DPat.type_test(bool_lit(true), bool_ty()),
        DPat.type_test(bool_lit(false), bool_ty()),
    ];
    let report = compute_match_usefulness(TestingCtx.new(), arms, bool_ty());
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, [])
}

// `let t: T[]` in a `string[]` column covers no length class but stays
// reachable.
test "rigid single row in list column is possible not covering" {
    let cx = TestingCtx.new();
    let col: root.types.Ty = root.types.TyList { elem: root.types.TyString {} };
    let rigid = DPat.type_test(root.types.TyList { elem: type_var_ty("T") }, col);
    let report = compute_match_usefulness(cx, [rigid, DPat.wildcard(col)], col);
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, []);

    let report = compute_match_usefulness(cx, [rigid], col);
    assert.is_true(report.missing.length() > 0);
    assert.equal(report.unreachable_arms, [])
}

// Generics are invariant: `Box<T>` in a `Box<int>` column is possible but not
// covering; `Box<T>` in a `Box<T>` column covers reflexively.
test "class ctor args are identity relevant" {
    let cx = TestingCtx.new();
    let box_q = qtn("Box");
    cx.register(box_q, [int_ty()]);
    let box_int: root.types.Ty = root.types.TyClass { name: box_q, args: [int_ty()] };
    let box_t: root.types.Ty = root.types.TyClass { name: box_q, args: [type_var_ty("T")] };

    let rigid_row = DPat.class_inst(box_q, [type_var_ty("T")], [DPat.wildcard(int_ty())], box_int);
    let report = compute_match_usefulness(cx, [rigid_row, DPat.wildcard(box_int)], box_int);
    assert.equal(report.missing.length(), 0);
    assert.equal(report.unreachable_arms, []);

    // An arg-mismatched class row never covers a concrete column.
    let report = compute_match_usefulness(cx, [rigid_row], box_int);
    assert.is_true(report.missing.length() > 0);
    assert.equal(report.unreachable_arms, []);

    // Same rigid args on both sides: a definite cover.
    let reflexive_row = DPat.class_inst(box_q, [type_var_ty("T")], [DPat.wildcard(int_ty())], box_t);
    let report = compute_match_usefulness(cx, [reflexive_row], box_t);
    assert.equal(rendered(report), []);
    assert.equal(report.unreachable_arms, [])
}

// `Box<T> { v: 1 }, Box<int> { v: _ }` on `Box<int>`: the concrete arm covers
// everything, and the rigid branch, being reachability-only, adds no false
// witness.
test "rigid class branch does not manufacture witnesses" {
    let cx = TestingCtx.new();
    let box_q = qtn("Box");
    cx.register(box_q, [int_ty()]);
    let box_int: root.types.Ty = root.types.TyClass { name: box_q, args: [int_ty()] };

    let rigid_refutable = DPat.class_inst(box_q, [type_var_ty("T")], [DPat.type_test(int_lit(1), int_ty())], box_int);
    let concrete_cover = DPat.class_inst(box_q, [int_ty()], [DPat.wildcard(int_ty())], box_int);
    let report = compute_match_usefulness(cx, [rigid_refutable, concrete_cover], box_int);
    assert.equal(rendered(report), []);
    assert.equal(report.unreachable_arms, []);

    // The sole rigid arm: one witness, reported once.
    let report = compute_match_usefulness(cx, [rigid_refutable], box_int);
    assert.equal(rendered(report).length(), 1);
    assert.equal(report.unreachable_arms, [])
}

// `Holder { xs: let t: T[], n: 1 }, Holder { xs: [..], n: _ }`: the slice arm
// covers everything; the rigid `Type` head's branch drops its witness.
test "rigid single head in list column does not manufacture witnesses" {
    let cx = TestingCtx.new();
    let holder_q = qtn("Holder");
    let strings: root.types.Ty = root.types.TyList { elem: root.types.TyString {} };
    cx.register(holder_q, [strings, int_ty()]);
    let holder: root.types.Ty = root.types.TyClass { name: holder_q, args: [] };

    let rigid_row = DPat.class_(
        holder_q,
        [
            DPat.type_test(root.types.TyList { elem: type_var_ty("T") }, strings),
            DPat.type_test(int_lit(1), int_ty()),
        ],
        holder,
    );
    let cover_row = DPat.class_(
        holder_q,
        [DPat.slice(var_shape(0, 0), [], strings), DPat.wildcard(int_ty())],
        holder,
    );
    let report = compute_match_usefulness(cx, [rigid_row, cover_row], holder);
    assert.equal(rendered(report), []);
    assert.equal(report.unreachable_arms, [])
}
