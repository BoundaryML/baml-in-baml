// port: baml_type/src/normalize/tests.rs @ d9be6853b
//
// Disjointness, always-equal folding, the well-known `reflect` interfaces,
// and head-category refutation. The stub context and constructors are in
// normalize_test.baml.

// ── concrete-type disjointness (`==` always-false fold) ──────────────────

test "disjoint distinct primitives" {
    let ctx = Ctx.new();
    // `5 == 5n`: an int literal and bigint never share a concrete type.
    assert.is_true(ctx.definitely_disjoint(lit_int(5), bigint()));
    assert.is_true(ctx.definitely_disjoint(TyInt {}, bigint()));
    assert.is_true(ctx.definitely_disjoint(TyInt {}, TyString {}));
    assert.is_true(ctx.definitely_disjoint(lit_int(1), TyString {}));
    // Distinct primitive literals are disjoint.
    assert.is_true(ctx.definitely_disjoint(lit_int(1), lit_int(2)));
    assert.is_true(ctx.definitely_disjoint(lit_str("a"), lit_str("b")));
    // Same family (literal inside its base, equal literals): not disjoint.
    assert.is_true(!ctx.definitely_disjoint(TyInt {}, TyInt {}));
    assert.is_true(!ctx.definitely_disjoint(lit_int(1), TyInt {}));
    assert.is_true(!ctx.definitely_disjoint(lit_int(1), lit_int(1)));
    // Floats are excluded from literal disjointness, but still disjoint
    // across categories.
    assert.is_true(!ctx.definitely_disjoint(lit_float("1.5"), lit_float("2.5")));
    assert.is_true(ctx.definitely_disjoint(lit_float("1.5"), TyString {}));
}

test "disjoint invariant generic classes" {
    let ctx = Ctx.new();
    // Distinct instantiations are distinct runtime types.
    assert.is_true(ctx.definitely_disjoint(class1("Box", TyInt {}), class1("Box", TyString {})));
    assert.is_true(!ctx.definitely_disjoint(class1("Box", TyInt {}), class1("Box", TyInt {})));
    // `unknown` is the determined top type: `Box<unknown>` is disjoint from
    // `Box<int>`.
    assert.is_true(ctx.definitely_disjoint(class1("Box", TyUnknown {}), class1("Box", TyInt {})));
    // A not-yet-resolved generic argument could realize to match.
    assert.is_true(
        !ctx.definitely_disjoint(class1("Box", typevar(0, "T")), class1("Box", TyInt {})),
    );
}

test "containers are invariant even when the element is a genuine subtype" {
    // `Dog <: Animal` does not make `list<Dog> <: list<Animal>`.
    let ctx = Ctx.new();
    ctx.impls.push((qtn("Dog"), qtn("Animal")));
    assert.is_true(ctx.is_subtype(class_("Dog"), iface("Animal")));
    assert.is_true(!ctx.is_subtype(list(class_("Dog")), list(iface("Animal"))));
    assert.is_true(
        !ctx.is_subtype(map_ty(TyString {}, class_("Dog")), map_ty(TyString {}, iface("Animal"))),
    );
    // A generic class is invariant in its argument for the same reason.
    assert.is_true(!ctx.is_subtype(class1("Box", class_("Dog")), class1("Box", iface("Animal"))));
    // Reflexive same-instantiation still holds.
    assert.is_true(ctx.is_subtype(list(class_("Dog")), list(class_("Dog"))));
}

test "disjoint containers are invariant" {
    let ctx = Ctx.new();
    // Different constructors / categories.
    assert.is_true(ctx.definitely_disjoint(list(TyInt {}), TyInt {}));
    assert.is_true(ctx.definitely_disjoint(list(TyInt {}), map_ty(TyString {}, TyInt {})));
    assert.is_true(ctx.definitely_disjoint(list(TyInt {}), class_("Dog")));
    // Distinct element / value instantiations.
    assert.is_true(ctx.definitely_disjoint(list(TyInt {}), list(TyString {})));
    assert.is_true(
        ctx.definitely_disjoint(map_ty(TyString {}, TyInt {}), map_ty(TyString {}, TyBool {})),
    );
    // Same instantiation.
    assert.is_true(!ctx.definitely_disjoint(list(TyInt {}), list(TyInt {})));
    // `list<unknown>` is disjoint from `list<int>`.
    assert.is_true(ctx.definitely_disjoint(list(TyUnknown {}), list(TyInt {})));
    // A not-yet-resolved generic element.
    assert.is_true(!ctx.definitely_disjoint(list(typevar(0, "T")), list(TyInt {})));
}

test "disjoint distinct classes and enums" {
    let ctx = Ctx.new();
    assert.is_true(ctx.definitely_disjoint(class_("Dog"), class_("Cat")));
    assert.is_true(!ctx.definitely_disjoint(class_("Dog"), class_("Dog")));
    assert.is_true(ctx.definitely_disjoint(class_("Dog"), TyInt {}));
    assert.is_true(ctx.definitely_disjoint(enum_ty("Foo"), enum_ty("Bar")));
    assert.is_true(!ctx.definitely_disjoint(enum_ty("Foo"), enum_ty("Foo")));
}

test "same enum variants are not disjoint" {
    // `E.A` vs `E.B` depends on `E`'s equality: never folded.
    let ctx = Ctx.new();
    assert.is_true(!ctx.definitely_disjoint(variant("Foo", "A"), variant("Foo", "B")));
    assert.is_true(!ctx.definitely_disjoint(variant("Foo", "A"), enum_ty("Foo")));
    // Variants of different enums are disjoint.
    assert.is_true(ctx.definitely_disjoint(variant("Foo", "A"), variant("Bar", "X")));
}

test "non ground types are never disjoint" {
    let ctx = Ctx.new();
    assert.is_true(!ctx.definitely_disjoint(TyInt {}, TyUnknown {}));
    assert.is_true(!ctx.definitely_disjoint(TyInt {}, typevar(0, "T")));
    assert.is_true(!ctx.definitely_disjoint(TyInt {}, iface("Animal")));
    // A concrete type vs an interface it might implement.
    assert.is_true(!ctx.definitely_disjoint(class_("Dog"), iface("Animal")));
}

test "disjoint unions require all cross pairs" {
    let ctx = Ctx.new();
    let int_or_string = union([TyInt {}, TyString {}]);
    assert.is_true(ctx.definitely_disjoint(int_or_string, TyBool {}));
    assert.is_true(!ctx.definitely_disjoint(int_or_string, TyInt {}));
    assert.is_true(ctx.definitely_disjoint(int_or_string, union([TyBool {}, bigint()])));
    assert.is_true(!ctx.definitely_disjoint(int_or_string, union([TyString {}, TyBool {}])));
}

test "disjoint null" {
    let ctx = Ctx.new();
    assert.is_true(ctx.definitely_disjoint(TyNull {}, TyInt {}));
    assert.is_true(!ctx.definitely_disjoint(TyNull {}, TyNull {}));
}

// ── always-equal fold (`==` provably true) ───────────────────────────────

test "equal same primitive literals and null" {
    let ctx = Ctx.new();
    assert.is_true(ctx.definitely_equal(lit_int(1), lit_int(1)));
    assert.is_true(ctx.definitely_equal(lit_str("a"), lit_str("a")));
    assert.is_true(ctx.definitely_equal(lit_bool(true), lit_bool(true)));
    assert.is_true(ctx.definitely_equal(TyNull {}, TyNull {}));
    // Different values of the same primitive are not always-equal.
    assert.is_true(!ctx.definitely_equal(lit_int(1), lit_int(2)));
    assert.is_true(!ctx.definitely_equal(lit_bool(true), lit_bool(false)));
}

test "equal requires singleton with unoverridable eq" {
    let ctx = Ctx.new();
    // Base primitives are not singletons.
    assert.is_true(!ctx.definitely_equal(TyInt {}, TyInt {}));
    // A literal vs its base.
    assert.is_true(!ctx.definitely_equal(lit_int(1), TyInt {}));
    // Float literals are excluded, even when identical.
    assert.is_true(!ctx.definitely_equal(lit_float("1.5"), lit_float("1.5")));
    // Enum-variant singletons are excluded (a later `Equals`).
    assert.is_true(!ctx.definitely_equal(variant("Foo", "A"), variant("Foo", "A")));
    // Class singletons are not folded.
    assert.is_true(!ctx.definitely_equal(class_("Dog"), class_("Dog")));
}

// ── reflect.AnyClass ─────────────────────────────────────────────────────

// port: baml_type/src/normalize/tests.rs::any_class @ d9be6853b
function any_class() -> Ty throws never {
    TyInterface {
        name: DeclName { pkg: test_root("reflect"), namespace: [], name: "AnyClass" },
        args: [],
        associated_types: [],
    }
}

test "any class membership is derived for classes only" {
    let ctx = Ctx.new();
    let target = any_class();
    assert.is_true(ctx.is_subtype(class_("Record"), target));
    assert.is_true(!ctx.is_subtype(TyInt {}, target));
    assert.is_true(!ctx.is_subtype(TyString {}, target));
    assert.is_true(!ctx.is_subtype(list(TyInt {}), target));
    assert.is_true(!ctx.is_subtype(map_ty(TyString {}, TyInt {}), target));
}

test "any class admits every reflection kind view" {
    // The kind views are ordinary classes, so they inhabit AnyClass.
    let ctx = Ctx.new();
    let target = any_class();
    for (let kind in TYPE_KINDS) {
        let view = TyClass { name: type_kind_class_decl(kind, test_root("reflect")), args: [] };
        assert.is_true(ctx.is_subtype(view, target));
    }
}

// ── reflect.AnyFunction ──────────────────────────────────────────────────

// port: baml_type/src/normalize/tests.rs::any_function @ d9be6853b
// `reflect.AnyFunction<..pins>`; an empty list models a pre-default-fill
// existential.
function any_function(pins: (string, Ty)[]) -> Ty throws never {
    TyInterface {
        name: DeclName { pkg: test_root("reflect"), namespace: [], name: "AnyFunction" },
        args: [],
        associated_types: pins.map((p) -> {
            AssociatedType { name: p.0, ty: p.1 }
        }),
    }
}

// port: baml_type/src/normalize/tests.rs::simple_fn @ d9be6853b
function simple_fn(ret: Ty, throws_: Ty) -> Ty throws never {
    TyFunction {
        params: [FunctionParamTy { name: null, ty: TyInt {}, mode: FunctionParamMode.Required }],
        ret: ret,
        throws_: throws_,
    }
}

test "every function implements bare any function" {
    // Conformance is compiler-derived with no impl in the context.
    let ctx = Ctx.new();
    let filled = any_function([("Returns", TyUnknown {}), ("Throws", TyUnknown {})]);
    assert.is_true(ctx.is_subtype(simple_fn(TyString {}, TyNever {}), filled));
    assert.is_true(ctx.is_subtype(simple_fn(class_("Doc"), class_("HttpError")), filled));
    assert.is_true(ctx.is_subtype(simple_fn(TyString {}, TyNever {}), any_function([])));
    // Non-function values fall to the ordinary nominal fact, not claimed here.
    assert.is_true(!ctx.is_subtype(TyInt {}, filled));
    assert.is_true(!ctx.is_subtype(class_("Doc"), filled));
}

test "any function pins check the functions channels covariantly" {
    let ctx = Ctx.new();
    let ret_pin = any_function([("Returns", union([TyInt {}, TyString {}])), ("Throws", TyUnknown {})]);
    // `int <: int | string` fits the Returns pin; `bool` does not.
    assert.is_true(ctx.is_subtype(simple_fn(TyInt {}, TyNever {}), ret_pin));
    assert.is_true(!ctx.is_subtype(simple_fn(TyBool {}, TyNever {}), ret_pin));
    // `throws never` fits every Throws pin; a mismatched error class does not.
    let throws_pin = any_function([("Returns", TyUnknown {}), ("Throws", class_("ToolError"))]);
    assert.is_true(ctx.is_subtype(simple_fn(TyInt {}, TyNever {}), throws_pin));
    assert.is_true(ctx.is_subtype(simple_fn(TyInt {}, class_("ToolError")), throws_pin));
    assert.is_true(!ctx.is_subtype(simple_fn(TyInt {}, class_("IoError")), throws_pin));
}

test "any function existentials are covariant in their pins" {
    let ctx = Ctx.new();
    let narrow = any_function([("Returns", TyInt {}), ("Throws", TyNever {})]);
    let wide = any_function([("Returns", union([TyInt {}, TyString {}])), ("Throws", class_("ToolError"))]);
    let bare = any_function([("Returns", TyUnknown {}), ("Throws", TyUnknown {})]);
    assert.is_true(ctx.is_subtype(narrow, wide));
    assert.is_true(ctx.is_subtype(narrow, bare));
    assert.is_true(ctx.is_subtype(wide, bare));
    assert.is_true(!ctx.is_subtype(wide, narrow));
    assert.is_true(!ctx.is_subtype(bare, narrow));
    // The carve-out is AnyFunction-specific.
    let other = TyInterface {
        name: qtn("Callable"),
        args: [],
        associated_types: [AssociatedType { name: "Returns", ty: TyInt {} }],
    };
    assert.is_true(!ctx.is_subtype(other, any_function([])));
}

// ── head-category refutation ─────────────────────────────────────────────

// port: baml_type/src/normalize/tests.rs::json_alias @ d9be6853b
// `type <name> = null | bool | int | float | string | <name>[] | map<string, <name>>`.
function json_alias(ctx: Ctx, name: string) -> void throws never {
    ctx.aliases.set(
        qtn(name),
        union(
            [
                TyNull {},
                TyBool {},
                TyInt {},
                TyFloat {},
                TyString {},
                list(alias(name)),
                map_ty(TyString {}, alias(name)),
            ],
        ),
    );
}

// port: baml_type/src/normalize/tests.rs::kind_corpus @ d9be6853b
// One type of every Ty variant, plus the facts that make the context-driven
// rules fire.
function kind_corpus() -> (Ctx, Ty[]) throws never {
    let ctx = Ctx.new();
    json_alias(ctx, "Json");
    ctx.enums.set(qtn("Side"), ["L", "R"]);
    ctx.impls.push((qtn("Box"), qtn("Displayable")));
    ctx.prim_impls.push(("int", qtn("Displayable")));
    ctx.var_bounds.set(param(0, "T"), [iface("Displayable")]);
    ctx.projections.push((class_("Box"), qtn("Displayable"), "Item", TyInt {}));
    let corpus: Ty[] = [
        TyInt {},
        bigint(),
        TyFloat {},
        TyString {},
        TyBool {},
        TyNull {},
        TyUint8Array {},
        TyMedia { kind: root.base.MediaKind.Image },
        TyMedia { kind: root.base.MediaKind.Generic },
        TyRustType {},
        TyType {},
        TyResource {},
        TyPromptAst {},
        lit_int(1),
        lit_float("1.5"),
        lit_str("user"),
        lit_bool(true),
        class_("Box"),
        class1("Gen", TyInt {}),
        enum_ty("Side"),
        variant("Side", "L"),
        list(TyInt {}),
        list(alias("Json")),
        map_ty(TyString {}, alias("Json")),
        map_ty(TyString {}, TyInt {}),
        TyFunction {
            params: [FunctionParamTy { name: null, ty: TyInt {}, mode: FunctionParamMode.Required }],
            ret: TyBool {},
            throws_: TyNever {},
        },
        TyFuture { value: TyInt {}, error: TyNever {} },
        union([TyInt {}, TyString {}]),
        optional(TyString {}),
        alias("Json"),
        iface("Displayable"),
        typevar(0, "T"),
        projection(class_("Box"), "Displayable", "Item"),
        TyUnknown {},
        TyNever {},
        TyError {},
    ];
    (ctx, corpus)
}

test "subtype and equivalence agree with the canonical relation for every kind pair" {
    // The head-category refutation is only a shortcut.
    let (let ctx, let corpus) = kind_corpus();
    for (let sub in corpus) {
        for (let sup in corpus) {
            let canonical_sub = canonical(sub, ctx);
            let canonical_sup = canonical(sup, ctx);
            assert.equal(
                ctx.is_subtype(sub, sup),
                is_subtype_of(canonical_sub, canonical_sup, ctx, []),
            );
            assert.equal(ctx.equivalent(sub, sup), canonical_sub == canonical_sup);
        }
    }
}

// port: baml_type/src/normalize/tests.rs::cross_category_pairs @ d9be6853b
// Pairs whose top-level kinds no rule relates: none may canonicalize (and
// so expand) the recursive alias.
function cross_category_pairs() -> (Ty, Ty)[] throws never {
    let json_map = map_ty(TyString {}, alias("Json"));
    let json_list = list(alias("Json"));
    [
        (lit_str("user"), json_map),
        (lit_str("user"), json_list),
        (json_list, json_map),
        (json_map, json_list),
        (TyInt {}, json_map),
        (lit_int(1), TyFloat {}),
        (TyNull {}, json_list),
        (class_("Box"), json_map),
        (enum_ty("Side"), json_map),
    ]
}

test "cross category pairs are refuted without canonicalizing" {
    let ctx = Ctx.new();
    json_alias(ctx, "Json");
    for (let pair in cross_category_pairs()) {
        assert.is_true(!ctx.is_subtype(pair.0, pair.1));
        assert.is_true(!ctx.equivalent(pair.0, pair.1));
        assert.equal(ctx.alias_lookups, 0);
    }
}

test "rewritable and context driven kinds are not refuted" {
    // Kinds a canonical form can rewrite, or that a context-driven rule
    // relates across kinds, are never refuted by their head alone.
    let (let ctx, _) = kind_corpus();
    let json_map = map_ty(TyString {}, alias("Json"));
    assert.is_true(ctx.is_subtype(lit_str("user"), alias("Json")));
    assert.is_true(ctx.is_subtype(json_map, alias("Json")));
    assert.is_true(ctx.is_subtype(TyInt {}, iface("Displayable")));
    assert.is_true(ctx.is_subtype(class_("Box"), iface("Displayable")));
    assert.is_true(ctx.is_subtype(typevar(0, "T"), iface("Displayable")));
    assert.is_true(ctx.is_subtype(projection(class_("Box"), "Displayable", "Item"), TyInt {}));
    assert.is_true(ctx.is_subtype(TyNever {}, json_map));
    assert.is_true(ctx.is_subtype(json_map, TyUnknown {}));
    assert.is_true(ctx.is_subtype(TyError {}, json_map));
    assert.is_true(ctx.is_subtype(lit_str("user"), optional(TyString {})));
}
