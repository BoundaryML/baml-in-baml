// port: baml_type/src/pattern_overlap.rs::tests @ d9be6853b
//
// Reuses the existing helpers where Rust's helper is the same function:
// normalize's (`param(name)` is `param(0, name)`, `Ty::type_var(name)` is
// `typevar(0, name)`, `int_literal` is lit_int, `bool_literal` is lit_bool,
// `enum_variant` is variant, `type_alias` is alias, class1, enum_ty,
// projection, `crate::test_roots::class` is class_, `crate::test_roots::local`
// is qtn) and unify's (`interface` is interface_ty, stub_enum_variants).

// port: baml_type/src/pattern_overlap.rs::tests::params @ d9be6853b
function params(vars: string[]) -> ParamTy[] throws never {
    vars.map((name) -> {
        param(0, name)
    })
}

// port: baml_type/src/pattern_overlap.rs::tests::class2 @ d9be6853b
function class2(name: string, a: Ty, b: Ty) -> Ty throws never {
    TyClass { name: qtn(name), args: [a, b] }
}

// port: baml_type/src/pattern_overlap.rs::tests::constraint @ d9be6853b
// A nullary interface constraint (the bound / registry-request form).
function constraint(name: string) -> InterfaceConstraint throws never {
    InterfaceConstraint { name: qtn(name), generics: [], associated_types: [] }
}

// port: baml_type/src/pattern_overlap.rs::tests::fn_returning @ d9be6853b
// `() -> ret`, never throwing.
function fn_returning(ret: Ty) -> Ty throws never {
    TyFunction { params: [], ret: ret, throws_: TyNever {} }
}

// port: baml_type/src/pattern_overlap.rs::tests::pattern_overlap_with @ d9be6853b
// The oracle with everything configurable.
function pattern_overlap_with(
    pat: Ty,
    member: Ty,
    vars: ParamTy[],
    bounds: TypeVarBoundsMap,
    aliases: map<DeclName, Ty>,
    implements_: ImplementsOracle,
) -> Overlap throws never {
    pattern_overlap(
        pat,
        member,
        PatternOverlapEnv {
            lang: test_lang(),
            vars: vars,
            bounds: bounds,
            aliases: aliases,
            enum_variants: stub_enum_variants,
            implements_: implements_,
        },
    )
}

// port: baml_type/src/pattern_overlap.rs::tests::pattern_overlap_plain @ d9be6853b
// The oracle over an empty program: no aliases, no bounds, and a registry
// that refutes every membership question.
function pattern_overlap_plain(pat: Ty, member: Ty, vars: ParamTy[]) -> Overlap throws never {
    pattern_overlap_with(pat, member, vars, {}, {}, (t, i) -> {
        false
    })
}

test "pattern overlap same var is reflexively yes" {
    let t = typevar(0, "T");
    assert.equal(pattern_overlap_plain(t, t, params(["T"])), Overlap.Yes)
}

test "pattern overlap var vs concrete is possible both directions" {
    let vars = params(["T"]);
    let t = typevar(0, "T");
    assert.equal(pattern_overlap_plain(t, TyInt {}, vars), Overlap.Yes);
    assert.equal(pattern_overlap_plain(TyInt {}, t, vars), Overlap.Yes)
}

test "pattern overlap var vs ctor carrying var is possible" {
    // `T` vs `Box<U>` overlaps at `T := Box<U>`.
    let vars = params(["T", "U"]);
    assert.equal(
        pattern_overlap_plain(typevar(0, "T"), class1("Box", typevar(0, "U")), vars),
        Overlap.Yes,
    )
}

test "pattern overlap binding consistency across positions" {
    // `Pair<T, T>` needs one consistent realization.
    let vars = params(["T"]);
    let pat = class2("Pair", typevar(0, "T"), typevar(0, "T"));
    assert.equal(
        pattern_overlap_plain(pat, class2("Pair", TyInt {}, TyString {}), vars),
        Overlap.No,
    );
    assert.equal(pattern_overlap_plain(pat, class2("Pair", TyInt {}, TyInt {}), vars), Overlap.Yes)
}

test "pattern overlap vars are shared by name across sides" {
    // The pattern and the scrutinee live in one scope: their `T`s are the
    // same variable.
    let vars = params(["T"]);
    let t = typevar(0, "T");
    assert.equal(
        pattern_overlap_plain(class2("Pair", t, TyString {}), class2("Pair", t, t), vars),
        Overlap.Yes,
    );
    assert.equal(
        pattern_overlap_plain(class2("Pair", TyInt {}, t), class2("Pair", t, TyString {}), vars),
        Overlap.No,
    )
}

test "pattern overlap ground mismatch is no" {
    let vars = params(["T"]);
    assert.equal(pattern_overlap_plain(TyInt {}, TyString {}, vars), Overlap.No);
    assert.equal(
        pattern_overlap_plain(class1("Box", TyInt {}), class1("Box", TyString {}), vars),
        Overlap.No,
    )
}

test "pattern overlap literal meets base at top level only" {
    // Top level compares value sets (`1` within `int`); inside an invariant
    // argument the relation is equality.
    let vars = params(["T"]);
    assert.equal(pattern_overlap_plain(lit_int(1), TyInt {}, vars), Overlap.Yes);
    assert.equal(pattern_overlap_plain(TyInt {}, lit_int(1), vars), Overlap.Yes);
    assert.equal(
        pattern_overlap_plain(class1("Box", lit_int(1)), class1("Box", TyInt {}), vars),
        Overlap.No,
    )
}

test "pattern overlap enum variant meets its enum only" {
    let vars = params([]);
    assert.equal(
        pattern_overlap_plain(variant("Color", "Red"), enum_ty("Color"), vars),
        Overlap.Yes,
    );
    assert.equal(pattern_overlap_plain(variant("Color", "Red"), enum_ty("Other"), vars), Overlap.No)
}

test "pattern overlap union decomposes by intersection" {
    // One overlapping member pair suffices.
    let vars = params(["T"]);
    assert.equal(
        pattern_overlap_plain(union([typevar(0, "T"), TyInt {}]), TyString {}, vars),
        Overlap.Yes,
    );
    assert.equal(pattern_overlap_plain(union([TyInt {}, TyBool {}]), TyString {}, vars), Overlap.No);
    assert.equal(
        pattern_overlap_plain(TyString {}, union([typevar(0, "T"), TyInt {}]), vars),
        Overlap.Yes,
    )
}

test "pattern overlap never overlaps nothing" {
    // The empty set has no common value with anything, not even itself.
    let vars = params(["T"]);
    assert.equal(pattern_overlap_plain(TyNever {}, typevar(0, "T"), vars), Overlap.No);
    assert.equal(pattern_overlap_plain(typevar(0, "T"), TyNever {}, vars), Overlap.No);
    assert.equal(pattern_overlap_plain(TyNever {}, TyNever {}, vars), Overlap.No)
}

test "pattern overlap unknown top type meets everything" {
    assert.equal(pattern_overlap_plain(TyUnknown {}, TyInt {}, params([])), Overlap.Yes)
}

test "pattern overlap bounded var meets unknown member" {
    let bounds: TypeVarBoundsMap = {};
    bounds.set(param(0, "T"), [constraint("I")]);
    // A rigid var over an `unknown` member is possible regardless of bounds;
    // in an invariant argument the bounded var cannot realize to `unknown`.
    let vars = params(["T"]);
    assert.equal(
        pattern_overlap_with(typevar(0, "T"), TyUnknown {}, vars, bounds, {}, (t, i) -> {
            false
        }),
        Overlap.Yes,
    );
    assert.equal(
        pattern_overlap_with(class1("Box", typevar(0, "T")), class1("Box", TyUnknown {}), vars, bounds, {}, (
            t,
            i,
        ) -> {
            false
        }),
        Overlap.No,
    )
}

test "pattern overlap bounded var meets existential member" {
    let bounds: TypeVarBoundsMap = {};
    bounds.set(param(0, "T"), [constraint("I")]);
    // A rigid var meeting an existential at the top level is always possible,
    // in either orientation.
    let vars = params(["T"]);
    assert.equal(
        pattern_overlap_with(typevar(0, "T"), interface_ty("J", []), vars, bounds, {}, (t, i) -> {
            false
        }),
        Overlap.Yes,
    );
    assert.equal(
        pattern_overlap_with(interface_ty("J", []), typevar(0, "T"), vars, bounds, {}, (t, i) -> {
            false
        }),
        Overlap.Yes,
    )
}

test "pattern overlap error sentinel overlaps nothing" {
    assert.equal(pattern_overlap_plain(TyError {}, typevar(0, "T"), params(["T"])), Overlap.No)
}

test "pattern overlap projection is conservatively possible" {
    let vars = params(["T"]);
    let proj = projection(typevar(0, "T"), "Iter", "Item");
    assert.equal(pattern_overlap_plain(proj, TyInt {}, vars), Overlap.Yes);
    assert.equal(pattern_overlap_plain(proj, proj, vars), Overlap.Yes)
}

test "pattern overlap bound refutes pinned witness" {
    let bounds: TypeVarBoundsMap = {};
    bounds.set(param(0, "T"), [constraint("I")]);
    // `T extends I` pinned to `int`: the registry decides; bounds refute but
    // never confirm.
    let vars = params(["T"]);
    assert.equal(
        pattern_overlap_with(typevar(0, "T"), TyInt {}, vars, bounds, {}, (t, i) -> {
            false
        }),
        Overlap.No,
    );
    assert.equal(
        pattern_overlap_with(typevar(0, "T"), TyInt {}, vars, bounds, {}, (t, i) -> {
            true
        }),
        Overlap.Yes,
    )
}

test "pattern overlap bound on unpinned witness is assumed satisfiable" {
    let bounds: TypeVarBoundsMap = {};
    bounds.set(param(0, "T"), [constraint("I")]);
    // `T := Box<U>` is still variable-bearing.
    let vars = params(["T", "U"]);
    assert.equal(
        pattern_overlap_with(typevar(0, "T"), class1("Box", typevar(0, "U")), vars, bounds, {}, (
            t,
            i,
        ) -> {
            false
        }),
        Overlap.Yes,
    )
}

test "pattern overlap bounded var cannot realize to union or existential" {
    let bounds: TypeVarBoundsMap = {};
    bounds.set(param(0, "T"), [constraint("I")]);
    // A witness pinned to a union or an existential refutes structurally,
    // even with the registry answering yes to everything.
    let vars = params(["T"]);
    assert.equal(
        pattern_overlap_with(class1("Box", typevar(0, "T")), class1("Box", union([TyInt {}, TyString {}])), vars, bounds, {}, (
            t,
            i,
        ) -> {
            true
        }),
        Overlap.No,
    );
    assert.equal(
        pattern_overlap_with(class1("Box", typevar(0, "T")), class1("Box", interface_ty("J", [])), vars, bounds, {}, (
            t,
            i,
        ) -> {
            true
        }),
        Overlap.No,
    )
}

test "pattern overlap union cover binding is not refuted" {
    let bounds: TypeVarBoundsMap = {};
    bounds.set(param(0, "T"), [constraint("I")]);
    // The covering search binds `T` to one of several witnesses, so bound
    // refutation is skipped for params under a union.
    let vars = params(["T"]);
    assert.equal(
        pattern_overlap_with(class1("Box", union([list(typevar(0, "T")), TyInt {}])), class1("Box", union([list(TyString {}), TyInt {}])), vars, bounds, {}, (
            t,
            i,
        ) -> {
            false
        }),
        Overlap.Yes,
    )
}

test "pattern overlap membership refutes only fully realized pairs" {
    // The registry may refute a ground class; a var-bearing side stays
    // possible.
    let vars = params(["T"]);
    let iface = interface_ty("I", []);
    assert.equal(
        pattern_overlap_with(iface, class_("Foo"), vars, {}, {}, (t, i) -> {
            false
        }),
        Overlap.No,
    );
    assert.equal(
        pattern_overlap_with(iface, class_("Foo"), vars, {}, {}, (t, i) -> {
            true
        }),
        Overlap.Yes,
    );
    assert.equal(
        pattern_overlap_with(iface, class1("Box", typevar(0, "T")), vars, {}, {}, (t, i) -> {
            false
        }),
        Overlap.Yes,
    )
}

test "pattern overlap existential pairs are always possible" {
    let vars = params([]);
    assert.equal(
        pattern_overlap_plain(interface_ty("I", [TyInt {}]), interface_ty("I", [TyString {}]), vars),
        Overlap.Yes,
    );
    assert.equal(
        pattern_overlap_plain(interface_ty("I", []), interface_ty("J", []), vars),
        Overlap.Yes,
    )
}

test "pattern overlap function types meet conservatively at top level" {
    // At an invariant argument the relation is equality.
    let vars = params([]);
    assert.equal(
        pattern_overlap_plain(fn_returning(TyInt {}), fn_returning(TyString {}), vars),
        Overlap.Yes,
    );
    assert.equal(
        pattern_overlap_plain(class1("Box", fn_returning(TyInt {})), class1("Box", fn_returning(TyString {})), vars),
        Overlap.No,
    )
}

test "pattern overlap alias under union decomposes" {
    // `string` vs `A | Foo` with `A = int | string` decomposes through A.
    let aliases: map<DeclName, Ty> = {};
    aliases.set(qtn("A"), union([TyInt {}, TyString {}]));
    assert.equal(
        pattern_overlap_with(TyString {}, union([alias("A"), class_("Foo")]), params([]), {}, aliases, (
            t,
            i,
        ) -> {
            false
        }),
        Overlap.Yes,
    )
}

test "pattern overlap cyclic alias degrades to unknown" {
    // Mutually-recursive union aliases: the depth cap answers Unknown.
    let aliases: map<DeclName, Ty> = {};
    aliases.set(qtn("A"), union([TyInt {}, alias("B")]));
    aliases.set(qtn("B"), union([TyBool {}, alias("A")]));
    assert.equal(
        pattern_overlap_with(TyString {}, alias("A"), params([]), {}, aliases, (t, i) -> {
            false
        }),
        Overlap.Unknown,
    )
}

test "pattern overlap normalizes inputs before comparing" {
    // `true | false` folds to `bool` inside invariant args.
    assert.equal(
        pattern_overlap_plain(
            class1("Bar", union([lit_bool(true), lit_bool(false)])),
            class1("Bar", TyBool {}),
            params([]),
        ),
        Overlap.Yes,
    )
}
