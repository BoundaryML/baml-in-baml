// port: baml_type/src/unify.rs::tests @ d9be6853b
//
// Reuses normalize's test helpers where Rust's helper is the same function:
// `param(name)` is `param(0, name)`, `Ty::type_var(name)` is
// `typevar(0, name)`, `int_literal` is lit_int, `bool_literal` is lit_bool,
// `enum_variant` is variant, `crate::test_roots::local` is qtn,
// `crate::test_roots::class` is class_, `Ty::list` is list, `Ty::union` is
// union. The test-only entries `unify_union_members` and `cover` are the
// depth-0 calls of the merged functions.

// port: baml_type/src/test_roots.rs::class_with_args @ d9be6853b
// `Class(name, args)` at the nameless workspace root.
function class_with_args(name: string, args: Ty[]) -> Ty throws never {
    TyClass { name: qtn(name), args: args }
}

// port: baml_type/src/test_roots.rs::alias_ctx @ d9be6853b
// The alias-equivalence context over `aliases` with the test language roots.
function alias_ctx(aliases: map<DeclName, Ty>) -> AliasEquivCtx throws never {
    AliasEquivCtx { aliases: aliases, lang: test_lang() }
}

// port: baml_type/src/unify.rs::tests::interface @ d9be6853b
// An interface existential with generic args and no associated bindings
// (`interface` is a keyword).
function interface_ty(name: string, args: Ty[]) -> Ty throws never {
    TyInterface { name: qtn(name), args: args, associated_types: [] }
}

// port: baml_type/src/unify.rs::tests::interface_with_assoc @ d9be6853b
function interface_with_assoc(name: string, assoc: (string, Ty)[]) -> Ty throws never {
    TyInterface {
        name: qtn(name),
        args: [],
        associated_types: assoc.map((pair) -> {
            AssociatedType { name: pair.0, ty: pair.1 }
        }),
    }
}

// port: baml_type/src/unify.rs::tests::stub_enum_variants @ d9be6853b
// Stub enum schema for `nf` tests: `Cmp` has variants `Less`, `Equal`, `More`.
function stub_enum_variants(qtn: DeclName) -> string[]? throws never {
    if (qtn.name == "Cmp") {
        ["Less", "Equal", "More"]
    } else {
        null
    }
}

test "contains bound typevar checks interface associated bindings" {
    let ty = TyInterface {
        name: qtn("Source"),
        args: [],
        associated_types: [AssociatedType { name: "Item", ty: list(typevar(0, "T")) }],
    };
    assert.is_true(contains_bound_typevar(ty, [param(0, "T")]));
    assert.is_true(!contains_bound_typevar(ty, [param(0, "U")]))
}

test "union overlap both bare vars is yes" {
    // Each bare variable can absorb the other side.
    let vars = [param(0, "T"), param(0, "V")];
    let xs: Ty[] = [TyInt {}, typevar(0, "T")];
    let ys: Ty[] = [TyString {}, typevar(0, "V")];
    assert.equal(unify_union_members(xs, ys, vars, alias_ctx({}), {}), Overlap.Yes)
}

test "union overlap variable absorbs extra members is yes" {
    // `{int, T}` vs `{int, string, Foo}`: `T = string | Foo` makes them equal.
    let vars = [param(0, "T")];
    let xs: Ty[] = [TyInt {}, typevar(0, "T")];
    let ys: Ty[] = [TyInt {}, TyString {}, class_("Foo")];
    assert.equal(unify_union_members(xs, ys, vars, alias_ctx({}), {}), Overlap.Yes)
}

test "union overlap unmatchable rigid member is no" {
    // `{int, T}` vs `{string, Foo}`: `int` matches nothing on the right.
    let vars = [param(0, "T")];
    let xs: Ty[] = [TyInt {}, typevar(0, "T")];
    let ys: Ty[] = [TyString {}, class_("Foo")];
    assert.equal(unify_union_members(xs, ys, vars, alias_ctx({}), {}), Overlap.No)
}

test "union overlap shared rigid members extracted is yes" {
    // `{A1, A2, T}` vs `{A1, .., A9}`: unit propagation peels A1 and A2, `T`
    // absorbs the rest.
    let vars = [param(0, "T")];
    let xs: Ty[] = [class_("A1"), class_("A2"), typevar(0, "T")];
    let ys = baml.Array.generate(9, (i) -> {
        class_(`A${i + 1}`)
    });
    assert.equal(unify_union_members(xs, ys, vars, alias_ctx({}), {}), Overlap.Yes)
}

test "union overlap linear large residual is yes" {
    // `{List<T>, List<U>, V}` vs `{List<A1>, .., List<A9>}`: a witness exists
    // and the search finds it in a few steps.
    let vars = [param(0, "T"), param(0, "U"), param(0, "V")];
    let xs: Ty[] = [list(typevar(0, "T")), list(typevar(0, "U")), typevar(0, "V")];
    let ys = baml.Array.generate(9, (i) -> {
        list(class_(`A${i + 1}`))
    });
    assert.equal(unify_union_members(xs, ys, vars, alias_ctx({}), {}), Overlap.Yes)
}

test "union overlap collapsing members is yes" {
    // `{List<T>, List<U>, List<W>}` vs `{List<A1>, List<A2>}`: idempotency
    // lets two members collapse (`T=A1, U=A2, W=A1`).
    let vars = [param(0, "T"), param(0, "U"), param(0, "W")];
    let xs: Ty[] = [list(typevar(0, "T")), list(typevar(0, "U")), list(typevar(0, "W"))];
    let ys: Ty[] = [list(class_("A1")), list(class_("A2"))];
    assert.equal(unify_union_members(xs, ys, vars, alias_ctx({}), {}), Overlap.Yes)
}

test "union overlap oversized search is unknown" {
    // Unknown via the breadth of the candidate set: scanning it exhausts the
    // step budget before the search can prove disjointness.
    let vars = [param(0, "T")];
    let pair = (a: Ty, b: Ty) -> Ty {
        class_with_args("Pair", [a, b])
    };
    let xs: Ty[] = [pair(typevar(0, "T"), class_("A1")), pair(typevar(0, "T"), class_("A2"))];
    let ys: Ty[] = [];
    let i = 0;
    while (i < 2050) {
        ys.push(pair(class_(`L${i}`), class_("A1")));
        ys.push(pair(class_(`R${i}`), class_("A2")));
        i += 1;
    }
    assert.equal(unify_union_members(xs, ys, vars, alias_ctx({}), {}), Overlap.Unknown)
}

test "union overlap literal covered by base is yes" {
    // `{1, T}` vs `{int, string}`: `1` is a subtype of `int`.
    let vars = [param(0, "T")];
    let xs: Ty[] = [lit_int(1), typevar(0, "T")];
    let ys: Ty[] = [TyInt {}, TyString {}];
    assert.equal(unify_union_members(xs, ys, vars, alias_ctx({}), {}), Overlap.Yes)
}

test "union overlap base not covered by literal is no" {
    // `{int, T}` vs `{1, string}`: subtyping is directional.
    let vars = [param(0, "T")];
    let xs: Ty[] = [TyInt {}, typevar(0, "T")];
    let ys: Ty[] = [lit_int(1), TyString {}];
    assert.equal(unify_union_members(xs, ys, vars, alias_ctx({}), {}), Overlap.No)
}

test "interface distinct associated binding is disjoint" {
    // `I<Item=int>` and `I<Item=string>` are distinct existential types.
    let a = interface_with_assoc("I", [("Item", TyInt {})]);
    let b = interface_with_assoc("I", [("Item", TyString {})]);
    assert.equal(unify_into(a, b, [], alias_ctx({}), {}), Overlap.No)
}

test "interface associated binding unifies variable" {
    // `I<Item=int>` unifies with `I<Item=T>` by binding `T = int`.
    let vars = [param(0, "T")];
    let bindings: TypeBindings = {};
    let a = interface_with_assoc("I", [("Item", TyInt {})]);
    let b = interface_with_assoc("I", [("Item", typevar(0, "T"))]);
    assert.equal(unify_into(a, b, vars, alias_ctx({}), bindings), Overlap.Yes);
    assert.equal(bindings.get(param(0, "T")), TyInt {})
}

test "distinct recursive alias subjects overlap" {
    // `type R = Box<R>` and `type S = Box<S>` denote the same type: the
    // alias-equality check answers before the structural arm descends.
    let aliases: map<DeclName, Ty> = {};
    aliases.set(qtn("R"), class_with_args("Box", [alias("R")]));
    aliases.set(qtn("S"), class_with_args("Box", [alias("S")]));
    assert.equal(unify_into(alias("R"), alias("S"), [], alias_ctx(aliases), {}), Overlap.Yes)
}

test "complete bool literal union subject overlaps bool" {
    // `true | false` and `bool` name the same subject.
    let u = TyUnion { members: [lit_bool(true), lit_bool(false)] };
    assert.equal(unify_into(TyBool {}, u, [], alias_ctx({}), {}), Overlap.Yes)
}

test "distinct recursive alias subjects are disjoint" {
    // `type R = Box<R>` vs `type S = Box<Pair<S, int>>` differ at a finite
    // depth.
    let aliases: map<DeclName, Ty> = {};
    aliases.set(qtn("R"), class_with_args("Box", [alias("R")]));
    aliases.set(qtn("S"), class_with_args("Box", [class_with_args("Pair", [alias("S"), TyInt {}])]));
    assert.equal(unify_into(alias("R"), alias("S"), [], alias_ctx(aliases), {}), Overlap.No)
}

test "cover distinct interface binding is not conservative" {
    // Same-name interfaces are decided precisely by unify_into.
    let a = interface_with_assoc("I", [("Item", TyInt {})]);
    let b = interface_with_assoc("I", [("Item", TyString {})]);
    assert.equal(cover(a, b, [], alias_ctx({}), {}), Overlap.No)
}

test "cover class vs interface is conservative yes" {
    // Class-implements-interface needs the impl registry: conservatively Yes.
    assert.equal(cover(class_("A"), interface_ty("I", []), [], alias_ctx({}), {}), Overlap.Yes)
}

test "nf drops never and collapses" {
    assert.equal(nf(union([TyInt {}, TyNever {}]), stub_enum_variants), TyInt {})
}

test "nf subsumes literal by base" {
    assert.equal(nf(union([lit_int(1), TyInt {}]), stub_enum_variants), TyInt {})
}

test "alias body normalization makes alias equal to its folded form" {
    // An alias whose body is normalized at map-build (`type TF = true | false`
    // folds to `bool`) must unify with `bool`.
    let aliases: map<DeclName, Ty> = {};
    aliases.set(qtn("TF"), union([lit_bool(true), lit_bool(false)]));
    // Mirror `normalized_alias_map`'s alias-body normalization.
    for (let key in aliases.keys()) {
        aliases.set(key, nf(aliases[key], stub_enum_variants));
    }
    assert.equal(unify_into(alias("TF"), TyBool {}, [], alias_ctx(aliases), {}), Overlap.Yes)
}

test "var bearing function arg unifies not disjoint" {
    // `(T) -> int` vs `(int) -> int` unifies at `T = int`.
    let func = (p: Ty) -> Ty {
        TyFunction {
            params: [FunctionParamTy { name: null, ty: p, mode: FunctionParamMode.Required }],
            ret: TyInt {},
            throws_: TyNever {},
        }
    };
    let vars = [param(0, "T")];
    assert.equal(
        unify_into(func(typevar(0, "T")), func(TyInt {}), vars, alias_ctx({}), {}),
        Overlap.Yes,
    )
}

test "projection conservatively overlaps not disjoint" {
    // A projection could stand for any type: Yes, never No, not Unknown.
    let proj = TyAssociatedTypeProjection {
        base: typevar(0, "T"),
        interface_: as_interface(interface_ty("Iter", []))
            ?? baml.sys.panic("interface() builds an existential"),
        member: "Item",
    };
    assert.equal(unify_into(proj, TyInt {}, [], alias_ctx({}), {}), Overlap.Yes)
}

test "nf folds complete bool" {
    assert.equal(nf(union([lit_bool(true), lit_bool(false)]), stub_enum_variants), TyBool {})
}

test "nf folds complete enum" {
    let all = union([variant("Cmp", "Less"), variant("Cmp", "Equal"), variant("Cmp", "More")]);
    assert.equal(nf(all, stub_enum_variants), enum_ty("Cmp"))
}

test "nf keeps partial enum" {
    // Two of Cmp's three variants: not folded, and listed in canonical order.
    let partial = union([variant("Cmp", "Less"), variant("Cmp", "Equal")]);
    let canonical = union([variant("Cmp", "Equal"), variant("Cmp", "Less")]);
    assert.equal(nf(partial, stub_enum_variants), canonical)
}

test "nf absorbs unknown" {
    assert.equal(nf(union([TyInt {}, TyUnknown {}]), stub_enum_variants), TyUnknown {})
}

test "nf recurses into arguments" {
    let wrapped = class_with_args("Wrap", [union([TyInt {}, TyNever {}])]);
    assert.equal(nf(wrapped, stub_enum_variants), class_with_args("Wrap", [TyInt {}]))
}

test "union with var conservatively overlaps enum" {
    // `Cmp.Less | T` opposite `Cmp`: the var could complete the enum.
    let vars = [param(0, "T")];
    let u = union([variant("Cmp", "Less"), typevar(0, "T")]);
    assert.equal(unify_into(u, enum_ty("Cmp"), vars, alias_ctx({}), {}), Overlap.Yes)
}

test "ground partial enum union is disjoint from enum" {
    let u = union([variant("Cmp", "Less"), variant("Cmp", "Equal")]);
    assert.equal(unify_into(u, enum_ty("Cmp"), [], alias_ctx({}), {}), Overlap.No)
}

test "union with var vs single class overlaps via collapse" {
    // `C | T` opposite `C`: at `T = C` idempotency collapses the union.
    let vars = [param(0, "T")];
    let u = union([class_("C"), typevar(0, "T")]);
    assert.equal(unify_into(u, class_("C"), vars, alias_ctx({}), {}), Overlap.Yes)
}

test "union with literal and var vs base overlaps via collapse" {
    // `1 | T` opposite `int`: at `T = int` the literal collapses.
    let vars = [param(0, "T")];
    let u = union([lit_int(1), typevar(0, "T")]);
    assert.equal(unify_into(u, TyInt {}, vars, alias_ctx({}), {}), Overlap.Yes)
}

test "union with var vs unrelated single is disjoint" {
    // `D | T` opposite `C`: the union always contains `D`.
    let vars = [param(0, "T")];
    let u = union([class_("D"), typevar(0, "T")]);
    assert.equal(unify_into(u, class_("C"), vars, alias_ctx({}), {}), Overlap.No)
}

test "variable binds to unknown" {
    // `unknown` is the inhabited top type, so a variable binds to it.
    let vars = [param(0, "T")];
    assert.equal(unify_into(typevar(0, "T"), TyUnknown {}, vars, alias_ctx({}), {}), Overlap.Yes)
}

test "unknown is disjoint from distinct concrete" {
    assert.equal(unify_into(TyUnknown {}, TyInt {}, [], alias_ctx({}), {}), Overlap.No)
}

// port: baml_type/src/unify.rs::tests::pigeonhole_overlap @ d9be6853b
// `holes` distinct variables `Pair<Ti, Ti>` against `pigeons` distinct ground
// members `Pair<Ai, Ai>`.
function pigeonhole_overlap(holes: int, pigeons: int) -> Overlap throws never {
    let vars = baml.Array.generate(holes, (i) -> {
        param(0, `T${i}`)
    });
    let xs = baml.Array.generate(holes, (i) -> {
        let t = typevar(0, `T${i}`);
        class_with_args("Pair", [t, t])
    });
    let ys = baml.Array.generate(pigeons, (i) -> {
        let a = class_(`A${i}`);
        class_with_args("Pair", [a, a])
    });
    unify_union_members(xs, ys, vars, alias_ctx({}), {})
}

test "union overlap small pigeonhole is decided" {
    // 4 holes cannot realize 5 pigeons, proved within budget.
    assert.equal(pigeonhole_overlap(4, 5), Overlap.No)
}

test "union overlap pigeonhole is unknown" {
    // 5 holes and 6 pigeons: ruling out every arrangement overruns the budget.
    assert.equal(pigeonhole_overlap(5, 6), Overlap.Unknown)
}

// port: baml_type/src/unify.rs::tests::three_sat_overlap @ d9be6853b
// 3-SAT reduced to union ACI-matching: SAT variable `i` is `Vi` pinned to
// `Pos`/`Neg`; clause `j` is `Cl<Cj, Vp, Vq, Vr>`, whose candidates are the
// ground combinations that satisfy it; a bare var absorbs the pool. The
// unions overlap iff the formula is satisfiable. `clauses[j]` holds three
// `(var, positive?)` literals.
function three_sat_overlap(num_vars: int, clauses: (int, bool)[][]) -> Overlap throws never {
    let v = (i: int) -> Ty {
        typevar(0, `V${i}`)
    };
    let val = (b: bool) -> Ty {
        class_(
            if (b) {
                "Pos"
            } else {
                "Neg"
            },
        )
    };
    let xs: Ty[] = [];
    let ys: Ty[] = [];
    let j = 0;
    for (let clause in clauses) {
        let tag = class_(`C${j}`);
        xs.push(class_with_args("Cl", [tag, v(clause[0].0), v(clause[1].0), v(clause[2].0)]));
        for (let sp in [true, false]) {
            for (let sq in [true, false]) {
                for (let sr in [true, false]) {
                    if (sp == clause[0].1 || sq == clause[1].1 || sr == clause[2].1) {
                        ys.push(class_with_args("Cl", [tag, val(sp), val(sq), val(sr)]));
                    }
                }
            }
        }
        j += 1;
    }
    xs.push(typevar(0, "ABSORB"));
    let vars = baml.Array.generate(num_vars, (i) -> {
        param(0, `V${i}`)
    });
    vars.push(param(0, "ABSORB"));
    unify_union_members(xs, ys, vars, alias_ctx({}), {})
}

// port: baml_type/src/unify.rs::tests::unsat_exclusion_clauses @ d9be6853b
// All 2^n exclusion clauses over the first `n` vars: unsatisfiable.
function unsat_exclusion_clauses(n: int) -> (int, bool)[][] throws never {
    let clauses: (int, bool)[][] = [];
    let mask = 0;
    while (mask < (1 << n)) {
        // Exclude assignment `mask`; the first 3 vars' bits are the literals.
        let lit = (i: int) -> (int, bool) {
            (i, ((mask >> i) & 1) == 0)
        };
        clauses.push([lit(0), lit(1), lit(2)]);
        mask += 1;
    }
    clauses
}

test "union overlap three sat satisfiable is yes" {
    // `(x | y | z)` is satisfiable, so the blocks overlap.
    assert.equal(three_sat_overlap(3, [[(0, true), (1, true), (2, true)]]), Overlap.Yes)
}

test "union overlap three sat unsatisfiable is no" {
    // All 8 assignments of x, y, z excluded: disjoint.
    assert.equal(three_sat_overlap(3, unsat_exclusion_clauses(3)), Overlap.No)
}
