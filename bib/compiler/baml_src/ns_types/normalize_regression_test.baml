// port: baml_type/src/normalize/tests.rs @ d9be6853b
//
// Regressions (self-referential bounds, renderer totality, unguarded members,
// projection qualifiers), heads carrying a lifetime, and tuples. The stub
// context and constructors are in normalize_test.baml.

test "self referential bound subtyping terminates" {
    // `T extends Foo<T | int>`: the bound mentions its own variable, so the
    // TypeVar arm re-canonicalizes it while proving through it. Terminating is
    // the test; the verdicts pin the co-inductive semantics.
    let ctx = Ctx.new();
    let t = TyTypeVar { param: param(0, "T") };
    let bound = TyInterface { name: qtn("Foo"), args: [union([t, TyInt {}])], associated_types: [] };
    ctx.var_bounds.set(param(0, "T"), [bound]);
    // Proves through the carried bound (reflexive at the bound itself).
    assert.is_true(ctx.is_subtype(t, bound));
    // The bound does not place `T` inside `int`.
    assert.is_true(!ctx.is_subtype(t, TyInt {}));
    // Canonicalizing the bound itself terminates.
    ctx.normalize(bound);
}

// ── review regressions: renderer totality, unguarded members, qualifiers ──

test "nested union member recursion renders totally" {
    // type A = string | (A | int)[]
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("A"), union([TyString {}, list(union([alias("A"), TyInt {}]))]));
    let n = ctx.normalize(alias("A"));
    assert.is_true(ctx.equivalent(alias("A"), n));
    // Idempotent.
    assert.equal(ctx.normalize(n), n);
    assert.is_true(!ctx.equivalent(alias("A"), TyInt {}));
}

test "unguarded mu member is not vacuously absorbing" {
    // type A = A | A[]  (== μX.X[])
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("A"), union([alias("A"), list(alias("A"))]));
    // string | A must not be equivalent to A.
    assert.is_true(!ctx.equivalent(union([TyString {}, alias("A")]), alias("A")));
}

test "projection qualifier on cycle terminates" {
    // type A = I<A> | (int as I<A>).M | J
    // The standalone `I<A>` member state and the projection's qualifier state
    // are bisimilar, so minimization merges them.
    let ctx = Ctx.new();
    let i_of_a = TyInterface { name: qtn("I"), args: [alias("A")], associated_types: [] };
    ctx.aliases.set(
        qtn("A"),
        union(
            [
                i_of_a,
                TyAssociatedTypeProjection {
                    base: TyInt {},
                    interface_: InterfaceConstraint {
                        name: qtn("I"),
                        generics: [alias("A")],
                        associated_types: [],
                    },
                    member: "M",
                },
                iface("J"),
            ],
        ),
    );
    let n = ctx.normalize(alias("A"));
    assert.is_true(ctx.equivalent(alias("A"), n));
}

test "map value union recursion renders totally" {
    // type J = int | map<string, J | null>
    let ctx = Ctx.new();
    ctx.aliases.set(
        qtn("J"),
        union([TyInt {}, map_ty(TyString {}, union([alias("J"), TyNull {}]))]),
    );
    let n = ctx.normalize(alias("J"));
    assert.is_true(ctx.equivalent(alias("J"), n));
    // Idempotent.
    assert.equal(ctx.normalize(n), n);
    assert.is_true(!ctx.equivalent(alias("J"), TyInt {}));
}

// ── review regressions: unguarded members, disjointness, rendering ───────

test "unguarded mu member does not absorb siblings" {
    // `type A = A | A[]` is non-contractive until ε-closure; the bottom-up
    // absorption must not prove `string <: A` vacuously.
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("A"), union([alias("A"), list(alias("A"))]));
    let u = union([TyString {}, alias("A")]);
    assert.is_true(ctx.is_subtype(TyString {}, u));
    assert.is_true(!ctx.equivalent(u, alias("A")));
    assert.is_true(ctx.equivalent(u, union([TyString {}, list(alias("A"))])));
}

test "overlapping recursive types are not disjoint" {
    // `A[]` is inside `A` for `type A = int | A[]`.
    let ctx = Ctx.new();
    int_list_alias(ctx, "A");
    assert.is_true(ctx.is_subtype(list(alias("A")), alias("A")));
    assert.is_true(!ctx.definitely_disjoint(alias("A"), list(alias("A"))));
    let d = union([TyBool {}, list(alias("A"))]);
    assert.is_true(!ctx.definitely_disjoint(alias("A"), d));
    assert.equal(ctx.constant_equality(alias("A"), d), null);
}

test "unguarded mu disjointness terminates conservatively" {
    // The read-back bail keeps the pre-automaton spelling, whose μ spine can
    // be unguarded; the guard must answer before any unfold.
    let unguarded = NormalTyMu {
        binder: MuDisplay { name: null, rendered: TyNever {} },
        body: NormalTyUnion {
            members: [NormalTyRecVar { var: 0 }, NormalTyList { elem: NormalTyRecVar { var: 0 } }],
        },
    };
    assert.is_true(!is_disjoint_from(unguarded, NormalTyString {}));
    assert.is_true(!is_disjoint_from(NormalTyString {}, unguarded));
}

test "union nested recursion renders via subset cover" {
    // `type A = int | (A | null)[]`: ε-closure splices the named union
    // through, and the renderer cuts the nameless cycle with the cover
    // `A | null`.
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("A"), union([TyInt {}, list(union([alias("A"), TyNull {}]))]));
    let a = alias("A");
    assert.is_true(ctx.equivalent(a, a));
    let rendered = ctx.normalize(a);
    assert.is_true(ctx.equivalent(a, rendered));
    // Idempotent.
    assert.equal(ctx.normalize(rendered), rendered);
}

test "single variant enum union is idempotent" {
    // A one-variant enum does not collapse.
    let ctx = Ctx.new();
    ctx.enums.set(qtn("E"), ["A"]);
    let v = variant("E", "A");
    let vv = union([v, v]);
    assert.is_true(ctx.equivalent(vv, v));
    assert.is_true(ctx.is_subtype(vv, v));
    assert.is_true(ctx.is_subtype(v, vv));
    // The two-variant collapse is unaffected.
    ctx.enums.set(qtn("F"), ["X", "Y"]);
    assert.is_true(ctx.equivalent(union([variant("F", "X"), variant("F", "Y")]), enum_ty("F")));
}

// ── heads carrying a lifetime ────────────────────────────────────────────

// port: baml_type/src/normalize/tests.rs::branded_head::TreeCtx @ d9be6853b
// One recursive alias, `Tree = int | Box<Tree>`, under a context that
// resolves no well-known declaration. Rust's heads here borrow a heap epoch;
// a DeclName carries no lifetime, so only the context's shape is ported.
class TreeCtx {
    tree: DeclName,
    boxed: DeclName,

    implements TypeContext {
        function well_known(self, head: WellKnownHead) -> DeclName? {
            null
        }

        function alias_def(self, name: DeclName) -> Ty? {
            if (name == self.tree) {
                TyUnion {
                    members: [
                        TyInt {},
                        TyClass { name: self.boxed, args: [TyTypeAlias { name: self.tree }] },
                    ],
                }
            } else {
                null
            }
        }

        function implements_interface(self, concrete: Ty, interface_: InterfaceConstraint) -> bool {
            false
        }

        function type_var_bound(self, param: ParamTy) -> InterfaceConstraint[] {
            []
        }

        function interface_requires(
            self,
            sub: InterfaceConstraint,
            sup: InterfaceConstraint,
        ) -> bool {
            false
        }

        function enum_variants(self, name: DeclName) -> string[]? {
            null
        }

        function associated_type_bound(
            self,
            interface_: InterfaceConstraint,
            assoc: string,
        ) -> InterfaceConstraint[] {
            []
        }

        function project(
            self,
            base: Ty,
            interface_: InterfaceConstraint,
            member: string,
            fuel: int,
        ) -> ProjectionStep {
            ProjectionStepOpaque {}
        }
    }
}

test "recursive alias canonicalizes over a head carrying a lifetime" {
    let ctx = TreeCtx {
        tree: DeclName { pkg: test_root("me"), namespace: [], name: "Tree" },
        boxed: DeclName { pkg: test_root("me"), namespace: [], name: "Box" },
    };
    let a = TyTypeAlias { name: ctx.tree };
    assert.is_true(ctx.equivalent(a, a));
    assert.is_true(ctx.is_subtype(TyInt {}, a));
    assert.is_true(!ctx.equivalent(a, TyInt {}));
    // The alias and its one-step unfolding denote the same type.
    let unfolded = TyUnion { members: [TyInt {}, TyClass { name: ctx.boxed, args: [a] }] };
    assert.is_true(ctx.equivalent(a, unfolded));
}

// ── tuples ───────────────────────────────────────────────────────────────

test "tuples are invariant elementwise" {
    let ctx = Ctx.new();
    let narrow = TyTuple { items: [TyInt {}, TyString {}] };
    let wide = TyTuple { items: [optional(TyInt {}), TyString {}] };
    assert.is_true(!ctx.is_subtype(narrow, wide));
    assert.is_true(!ctx.is_subtype(wide, narrow));
    let literal = TyTuple { items: [lit_int(1), TyString {}] };
    assert.is_true(!ctx.is_subtype(literal, narrow));
    let spelled = TyTuple { items: [union([lit_int(5), TyInt {}]), TyString {}] };
    assert.is_true(ctx.equivalent(spelled, narrow));
    assert.is_true(ctx.is_subtype(spelled, narrow));
    assert.is_true(ctx.is_subtype(narrow, union([narrow, TyInt {}])));
    assert.is_true(!ctx.is_subtype(narrow, union([wide, TyInt {}])));
}

test "distinct tuple arms do not absorb" {
    let ctx = Ctx.new();
    let narrow = TyTuple { items: [TyInt {}] };
    let wide = TyTuple { items: [optional(TyInt {})] };
    let both = union([narrow, wide]);
    match (ctx.normalize(both)) {
        let u: TyUnion => assert.equal(u.members.length(), 2),
        _ => baml.sys.panic("`(int,) | (int?,)` collapsed"),
    }
    assert.is_true(!ctx.equivalent(both, wide));
    assert.is_true(!ctx.equivalent(both, narrow));
    let spelled = TyTuple { items: [union([lit_int(5), TyInt {}])] };
    assert.is_true(ctx.equivalent(union([narrow, spelled]), narrow));
}

test "products of unions and unions of products are unrelated" {
    let ctx = Ctx.new();
    let tuple = (items: Ty[]) -> Ty {
        TyTuple { items: items }
    };
    let product = tuple([union([TyInt {}, TyString {}]), TyBool {}]);
    let distributed = union([tuple([TyInt {}, TyBool {}]), tuple([TyString {}, TyBool {}])]);
    assert.is_true(!ctx.is_subtype(product, distributed));
    assert.is_true(!ctx.is_subtype(distributed, product));
    assert.is_true(!ctx.equivalent(product, distributed));
    assert.is_true(!ctx.is_subtype(class1("Box", product), class1("Box", distributed)));
    let correlated = union([tuple([TyInt {}, TyString {}]), tuple([TyString {}, TyInt {}])]);
    let joined = tuple([union([TyInt {}, TyString {}]), union([TyInt {}, TyString {}])]);
    assert.is_true(!ctx.is_subtype(correlated, joined));
    assert.is_true(!ctx.is_subtype(joined, correlated));
    let nested = tuple([tuple([union([TyInt {}, TyString {}])]), TyBool {}]);
    let nested_distributed = union([tuple([tuple([TyInt {}]), TyBool {}]), tuple([tuple([TyString {}]), TyBool {}])]);
    assert.is_true(!ctx.is_subtype(nested, nested_distributed));
    assert.is_true(!ctx.is_subtype(nested_distributed, nested));
    assert.is_true(!ctx.is_subtype(TyInt {}, tuple([TyInt {}])));
}

// ── not in Rust: recursion depth ─────────────────────────────────────────

// Not a Rust test. The walks recurse on the VM stack (no explicit work
// stacks); this pins that a type nested DEEP_NESTING levels stays within it
// through from_ty, canonicalize, is_subtype_of and the renderers. No alias:
// the μ automaton is superlinear in the term size (the same shape under a
// recursive alias takes minutes on the VM), so it is not part of this check.
const DEEP_NESTING: int = 500;

test "deep nesting stays within the stack" {
    let ctx = Ctx.new();
    let deep: Ty = TyInt {};
    let spelled: Ty = union([lit_int(1), TyInt {}]);
    for (let i = 0; i < DEEP_NESTING; i += 1) {
        deep = class1("Box", union([deep, TyNull {}]));
        spelled = class1("Box", union([TyNull {}, spelled]));
    }
    assert.is_true(ctx.equivalent(deep, spelled));
    assert.is_true(ctx.is_subtype(deep, spelled));
    assert.equal(ctx.normalize(spelled), ctx.normalize(deep))
}
