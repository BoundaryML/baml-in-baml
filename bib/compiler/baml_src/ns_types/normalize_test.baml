// port: baml_type/src/normalize/tests.rs @ d9be6853b
//
// Unit tests for the canonical type algebra, driven by a hand-built
// TypeContext stub that records nominal facts directly. Split across
// normalize_test.baml (the stub, constructors, and the algebra up to the
// equirecursive forms), normalize_disjoint_test.baml, normalize_interned_test.baml
// and normalize_regression_test.baml, in the Rust file's order.
//
// Restructured:
// - `crate::test_roots` is test_root / test_lang: the prelude packages get
//   root ids in Rust's creation order, every other language package after
//   them in LangPackage order.
// - Ctx's `assoc_bounds: HashMap<(DeclName, Name), Vec<Ty>>` is nested maps
//   (tuples are not hashable); its `alias_lookups: Cell<usize>` a plain int
//   field.
// - The interned entries take the test's InferPool.
// - `branded_head` drops the lifetime: a context over DeclName heads whose
//   well_known answers null, which is what the test exercises.

// port: baml_type/src/test_roots.rs::PRELUDE @ d9be6853b
// Spellings every test may use, in creation (root id) order.
const TEST_PRELUDE: string[] = ["ai", "app", "baml", "dep", "me", "other", "reflect", "user"];

// port: baml_type/src/test_roots.rs::root @ d9be6853b
// The test root id of `package`: its prelude slot, or for any other language
// package its place after the prelude in LangPackage order (the order
// test_lang creates them in).
function test_root(package: string) -> int throws never {
    let slot = TEST_PRELUDE.index_of(package);
    if (slot != null) {
        return slot;
    }
    let extra = root.base.LANG_PACKAGES.map(root.base.lang_package_manifest_name).filter((name) -> {
        !TEST_PRELUDE.includes(name)
    });
    let k = extra.index_of(package) ?? baml.sys.panic(`test_root: unknown package ${package}`);
    TEST_PRELUDE.length() + k
}

// port: baml_type/src/test_roots.rs::lang @ d9be6853b
// The language-root table over the test roots.
function test_lang() -> root.base.LangRoots throws never {
    let roots: map<root.base.LangPackage, int> = {};
    for (let package in root.base.LANG_PACKAGES) {
        roots.set(package, test_root(root.base.lang_package_manifest_name(package)));
    }
    root.base.LangRoots { roots: roots, by_root: null }
}

// port: baml_type/src/normalize/tests.rs::Ctx @ d9be6853b
class Ctx {
    aliases: map<DeclName, Ty>,
    // `(concrete nominal head, interface head)` membership facts.
    impls: (DeclName, DeclName)[],
    // `(primitive name, interface head)` membership facts.
    prim_impls: (string, DeclName)[],
    // `(interface head, required interface head)` direct requirements
    // (`requires` is a keyword).
    requires_: (DeclName, DeclName)[],
    // Conjunction (`T: A + B`) bounds per type variable.
    var_bounds: map<ParamTy, Ty[]>,
    enums: map<DeclName, string[]>,
    // Declared `extends` bounds per interface head, then associated type.
    assoc_bounds: map<DeclName, map<string, Ty[]>>,
    // `(base, interface head, member, reduced)` projection facts.
    projections: (Ty, DeclName, string, Ty)[],
    // How many times the algebra asked for an alias definition.
    alias_lookups: int,

    // port: baml_type/src/normalize/tests.rs::Ctx::default @ d9be6853b
    function new() -> Self {
        Ctx {
            aliases: {},
            impls: [],
            prim_impls: [],
            requires_: [],
            var_bounds: {},
            enums: {},
            assoc_bounds: {},
            projections: [],
            alias_lookups: 0,
        }
    }

    implements TypeContext {
        // port: baml_type/src/normalize/tests.rs::Ctx::well_known @ d9be6853b
        function well_known(self, head: WellKnownHead) -> DeclName? {
            well_known_decl(test_lang(), head)
        }

        // port: baml_type/src/normalize/tests.rs::Ctx::alias_def @ d9be6853b
        function alias_def(self, name: DeclName) -> Ty? {
            self.alias_lookups += 1;
            self.aliases.get(name)
        }

        // port: baml_type/src/normalize/tests.rs::Ctx::implements_interface @ d9be6853b
        function implements_interface(self, concrete: Ty, interface_: InterfaceConstraint) -> bool {
            let iface = interface_.name;
            let c = nominal_head(concrete);
            if (c != null) {
                return self.impls.some((p) -> {
                    p.0 == c && p.1 == iface
                });
            }
            let prim = primitive_name(concrete);
            if (prim != null) {
                return self.prim_impls.some((p) -> {
                    p.0 == prim && p.1 == iface
                });
            }
            false
        }

        // port: baml_type/src/normalize/tests.rs::Ctx::type_var_bound @ d9be6853b
        function type_var_bound(self, param: ParamTy) -> InterfaceConstraint[] {
            (self.var_bounds.get(param) ?? []).filter_map(as_interface)
        }

        // port: baml_type/src/normalize/tests.rs::Ctx::interface_requires @ d9be6853b
        function interface_requires(
            self,
            sub: InterfaceConstraint,
            sup: InterfaceConstraint,
        ) -> bool {
            let a = sub.name;
            let b = sup.name;
            a == b
                || self.requires_.some((p) -> {
                    p.0 == a && p.1 == b
                })
        }

        // port: baml_type/src/normalize/tests.rs::Ctx::enum_variants @ d9be6853b
        function enum_variants(self, name: DeclName) -> string[]? {
            self.enums.get(name)
        }

        // port: baml_type/src/normalize/tests.rs::Ctx::associated_type_bound @ d9be6853b
        function associated_type_bound(
            self,
            interface_: InterfaceConstraint,
            assoc: string,
        ) -> InterfaceConstraint[] {
            (self.assoc_bounds.get(interface_.name)?.get(assoc) ?? []).filter_map(as_interface)
        }

        // port: baml_type/src/normalize/tests.rs::Ctx::project @ d9be6853b
        function project(
            self,
            base: Ty,
            interface_: InterfaceConstraint,
            member: string,
            fuel: int,
        ) -> ProjectionStep {
            let hit = self.projections.find((p) -> {
                p.0 == base && p.1 == interface_.name && p.2 == member
            });
            match (hit) {
                null => ProjectionStepOpaque {},
                let h: (Ty, DeclName, string, Ty) => ProjectionStepReduced { ty: h.3 },
            }
        }
    }
}

// port: baml_type/src/normalize/tests.rs::nominal_head @ d9be6853b
function nominal_head(ty: Ty) -> DeclName? throws never {
    match (ty) {
        let x: TyClass => x.name,
        let x: TyInterface => x.name,
        let x: TyEnum => x.name,
        let x: TyEnumVariant => x.name,
        _ => null,
    }
}

// port: baml_type/src/normalize/tests.rs::primitive_name @ d9be6853b
function primitive_name(ty: Ty) -> string? throws never {
    match (ty) {
        TyInt => "int",
        TyBigint => "bigint",
        TyFloat => "float",
        TyString => "string",
        TyBool => "bool",
        _ => null,
    }
}

// ── constructors ─────────────────────────────────────────────────────────

// port: baml_type/src/normalize/tests.rs::qtn @ d9be6853b
// A head at the root namespace of the nameless workspace root
// (`test_roots::local`).
function qtn(s: string) -> DeclName throws never {
    DeclName { pkg: test_root("user"), namespace: [], name: s }
}

// port: baml_type/src/normalize/tests.rs::class @ d9be6853b
function class_(s: string) -> Ty throws never {
    TyClass { name: qtn(s), args: [] }
}

// port: baml_type/src/normalize/tests.rs::class1 @ d9be6853b
function class1(s: string, arg: Ty) -> Ty throws never {
    TyClass { name: qtn(s), args: [arg] }
}

// port: baml_type/src/normalize/tests.rs::iface @ d9be6853b
function iface(s: string) -> Ty throws never {
    TyInterface { name: qtn(s), args: [], associated_types: [] }
}

// port: baml_type/src/normalize/tests.rs::enum_ty @ d9be6853b
function enum_ty(s: string) -> Ty throws never {
    TyEnum { name: qtn(s) }
}

// port: baml_type/src/normalize/tests.rs::variant @ d9be6853b
function variant(e: string, v: string) -> Ty throws never {
    TyEnumVariant { name: qtn(e), variant: v }
}

// port: baml_type/src/normalize/tests.rs::lit_int @ d9be6853b
function lit_int(n: int) -> Ty throws never {
    TyLiteral { value: root.base.LiteralInt { value: n }, freshness: Freshness.Regular }
}

// port: baml_type/src/normalize/tests.rs::union @ d9be6853b
function union(v: Ty[]) -> Ty throws never {
    TyUnion { members: v }
}

// port: baml_type/src/normalize/tests.rs::list @ d9be6853b
function list(t: Ty) -> Ty throws never {
    TyList { elem: t }
}

// port: baml_type/src/normalize/tests.rs::alias @ d9be6853b
function alias(s: string) -> Ty throws never {
    TyTypeAlias { name: qtn(s) }
}

// port: baml_type/src/normalize/tests.rs::param @ d9be6853b
function param(index: int, name: string) -> ParamTy throws never {
    ParamTy { index: index, name: name }
}

// port: baml_type/src/normalize/tests.rs::typevar @ d9be6853b
function typevar(index: int, name: string) -> Ty throws never {
    TyTypeVar { param: param(index, name) }
}

// port: baml_type/src/normalize/tests.rs::projection @ d9be6853b
function projection(base: Ty, iface_name: string, member: string) -> Ty throws never {
    TyAssociatedTypeProjection {
        base: base,
        interface_: InterfaceConstraint { name: qtn(iface_name), generics: [], associated_types: [] },
        member: member,
    }
}

// port: baml_type/src/normalize/tests.rs::bigint @ d9be6853b
function bigint() -> Ty throws never {
    TyBigint {}
}

// port: baml_type/src/normalize/tests.rs::map_ty @ d9be6853b
function map_ty(key: Ty, value: Ty) -> Ty throws never {
    TyMap { key: key, value: value }
}

// port: baml_type/src/normalize/tests.rs::lit_str @ d9be6853b
function lit_str(s: string) -> Ty throws never {
    TyLiteral { value: root.base.LiteralString { value: s }, freshness: Freshness.Regular }
}

// port: baml_type/src/normalize/tests.rs::lit_bool @ d9be6853b
function lit_bool(b: bool) -> Ty throws never {
    TyLiteral { value: root.base.LiteralBool { value: b }, freshness: Freshness.Regular }
}

// port: baml_type/src/normalize/tests.rs::lit_float @ d9be6853b
function lit_float(s: string) -> Ty throws never {
    TyLiteral { value: root.base.LiteralFloat { value: s }, freshness: Freshness.Regular }
}

// ── projection reduction ─────────────────────────────────────────────────

test "projection reduces to its binding" {
    // `(C as Foo).Assoc` is the type the oracle reduces it to.
    let ctx = Ctx.new();
    ctx.projections.push((class_("C"), qtn("Foo"), "Assoc", TyString {}));
    assert.is_true(ctx.equivalent(projection(class_("C"), "Foo", "Assoc"), TyString {}));
}

// ── shared runtime-type algebra ──────────────────────────────────────────

test "reflection kind classes are ordinary classes disjoint from the carrier" {
    // The kind views are wrapper classes: no subtyping edge relates them to the
    // `type` carrier, and as nominal classes they are head-disjoint from it.
    let ctx = Ctx.new();
    let pool = InferPool.new();
    let carrier = TyType {};
    for (let kind in TYPE_KINDS) {
        let view = TyClass { name: type_kind_class_decl(kind, test_root("reflect")), args: [] };
        assert.is_true(!ctx.is_subtype(view, carrier));
        let view_i = ClosedTy.try_from(pool, pool.from_plain(view));
        let carrier_i = ClosedTy.try_from(pool, pool.from_plain(carrier));
        assert.is_true(!is_subtype_interned(pool, view_i, carrier_i, ctx));
        assert.is_true(!ctx.is_subtype(carrier, view));
        assert.is_true(ctx.definitely_disjoint(view, carrier));
    }
}

test "cyclic projection reduction terminates and stays opaque" {
    // `(C as I).A -> (C as J).B -> (C as I).A -> ..`: fuel-bounded, and the
    // projection stays opaque, never equated to a concrete type.
    let ctx = Ctx.new();
    ctx.projections.push((class_("C"), qtn("I"), "A", projection(class_("C"), "J", "B")));
    ctx.projections.push((class_("C"), qtn("J"), "B", projection(class_("C"), "I", "A")));
    assert.is_true(!ctx.equivalent(projection(class_("C"), "I", "A"), TyInt {}));
}

// ── union algebra ────────────────────────────────────────────────────────

test "union aci" {
    let ctx = Ctx.new();
    // Commutativity.
    assert.is_true(ctx.equivalent(union([TyInt {}, TyString {}]), union([TyString {}, TyInt {}])));
    // Idempotence.
    assert.is_true(ctx.equivalent(union([TyInt {}, TyInt {}]), TyInt {}));
    // Associativity / flattening.
    assert.is_true(
        ctx.equivalent(
            union([TyInt {}, union([TyString {}, TyBool {}])]),
            union([union([TyInt {}, TyString {}]), TyBool {}]),
        ),
    );
}

test "never is removed unknown absorbs" {
    let ctx = Ctx.new();
    assert.is_true(ctx.equivalent(union([TyInt {}, TyNever {}]), TyInt {}));
    assert.is_true(ctx.equivalent(union([TyInt {}, TyUnknown {}]), TyUnknown {}));
}

test "literal types are subtypes of their base only" {
    // A literal is a member of its base primitive and of any union containing
    // it; it does not cross representations.
    let ctx = Ctx.new();
    assert.is_true(ctx.is_subtype(lit_int(42), TyInt {}));
    assert.is_true(ctx.is_subtype(lit_float("3.14"), TyFloat {}));
    assert.is_true(ctx.is_subtype(lit_str("hello"), TyString {}));
    assert.is_true(ctx.is_subtype(lit_bool(true), TyBool {}));
    assert.is_true(!ctx.is_subtype(lit_int(42), TyFloat {}));
    // Union / optional membership.
    assert.is_true(ctx.is_subtype(lit_int(42), union([TyString {}, TyInt {}])));
    assert.is_true(ctx.is_subtype(lit_int(42), optional(TyInt {})));
    assert.is_true(ctx.is_subtype(TyNull {}, optional(TyString {})));
}

test "numeric types do not widen across representations" {
    let ctx = Ctx.new();
    assert.is_true(!ctx.is_subtype(TyInt {}, TyFloat {}));
    assert.is_true(!ctx.is_subtype(TyInt {}, bigint()));
    assert.is_true(!ctx.is_subtype(list(TyInt {}), list(bigint())));
}

test "literal into base absorption" {
    let ctx = Ctx.new();
    // `int | 99 == int`.
    assert.is_true(ctx.equivalent(union([lit_int(99), TyInt {}]), TyInt {}));
    assert.equal(ctx.normalize(union([lit_int(99), TyInt {}])), TyInt {});
    // A bare literal does not absorb into a different base.
    assert.is_true(!ctx.equivalent(union([lit_int(99), TyString {}]), TyInt {}));
}

test "optional is union with null" {
    let ctx = Ctx.new();
    assert.is_true(ctx.equivalent(optional(TyInt {}), union([TyInt {}, TyNull {}])));
}

// ── enums ────────────────────────────────────────────────────────────────

test "enum completeness collapse" {
    let ctx = Ctx.new();
    ctx.enums.set(qtn("Side"), ["Left", "Right"]);
    // All variants present: the enum.
    assert.is_true(
        ctx.equivalent(union([variant("Side", "Left"), variant("Side", "Right")]), enum_ty("Side")),
    );
    // An incomplete set does not collapse.
    assert.is_true(!ctx.equivalent(variant("Side", "Left"), enum_ty("Side")));
    // A bare enum absorbs its own variants.
    assert.is_true(
        ctx.equivalent(union([variant("Side", "Left"), enum_ty("Side")]), enum_ty("Side")),
    );
}

test "unknown enum does not collapse" {
    // No enum_variants fact: fail-safe, keep the variants.
    let ctx = Ctx.new();
    assert.is_true(
        !ctx.equivalent(union([variant("Side", "Left"), variant("Side", "Right")]), enum_ty("Side")),
    );
}

// ── interface absorption ─────────────────────────────────────────────────

test "concrete implements interface" {
    let ctx = Ctx.new();
    ctx.impls.push((qtn("Dog"), qtn("Animal")));
    assert.is_true(ctx.is_subtype(class_("Dog"), iface("Animal")));
    // `Dog | Animal == Animal`.
    assert.is_true(ctx.equivalent(union([class_("Dog"), iface("Animal")]), iface("Animal")));
    // A non-implementor is not absorbed.
    assert.is_true(!ctx.is_subtype(class_("Rock"), iface("Animal")));
    assert.is_true(!ctx.equivalent(union([class_("Rock"), iface("Animal")]), iface("Animal")));
}

test "interface requires absorption" {
    let ctx = Ctx.new();
    ctx.requires_.push((qtn("Compare"), qtn("Equals")));
    assert.is_true(ctx.is_subtype(iface("Compare"), iface("Equals")));
    // `Compare | Equals == Equals`.
    assert.is_true(ctx.equivalent(union([iface("Compare"), iface("Equals")]), iface("Equals")));
    assert.is_true(!ctx.is_subtype(iface("Equals"), iface("Compare")));
}

test "type var bound absorption" {
    let ctx = Ctx.new();
    ctx.var_bounds.set(param(0, "T"), [iface("Animal")]);
    assert.is_true(ctx.is_subtype(typevar(0, "T"), iface("Animal")));
    // `T | Animal == Animal` when `T: Animal`.
    assert.is_true(ctx.equivalent(union([typevar(0, "T"), iface("Animal")]), iface("Animal")));
    // A different type variable is not absorbed and not equivalent.
    assert.is_true(!ctx.equivalent(typevar(0, "T"), typevar(1, "U")));
}

test "type var bounds use full param identity" {
    let ctx = Ctx.new();
    ctx.var_bounds.set(param(1, "T"), [iface("Animal")]);
    assert.is_true(!ctx.is_subtype(typevar(0, "T"), iface("Animal")));
    assert.is_true(ctx.is_subtype(typevar(1, "T"), iface("Animal")));
}

test "type var conjunction bound" {
    // `T: Animal + Compare`, and `Compare` transitively requires `Equals`.
    let ctx = Ctx.new();
    ctx.var_bounds.set(param(0, "T"), [iface("Animal"), iface("Compare")]);
    ctx.requires_.push((qtn("Compare"), qtn("Equals")));
    // Each conjunct is provable on its own, including transitively.
    assert.is_true(ctx.is_subtype(typevar(0, "T"), iface("Animal")));
    assert.is_true(ctx.is_subtype(typevar(0, "T"), iface("Compare")));
    assert.is_true(ctx.is_subtype(typevar(0, "T"), iface("Equals")));
    // An interface no conjunct provides is not a supertype.
    assert.is_true(!ctx.is_subtype(typevar(0, "T"), iface("Serialize")));
    // Union absorption follows the same per-conjunct rule.
    assert.is_true(ctx.equivalent(union([typevar(0, "T"), iface("Equals")]), iface("Equals")));
    assert.is_true(
        !ctx.equivalent(union([typevar(0, "T"), iface("Serialize")]), iface("Serialize")),
    );
}

// ── invariant generics ───────────────────────────────────────────────────

test "generics are invariant up to equivalence" {
    let ctx = Ctx.new();
    assert.is_true(!ctx.equivalent(class1("Box", TyInt {}), class1("Box", TyString {})));
    // Equivalent argument spellings make the containers equivalent.
    assert.is_true(
        ctx.equivalent(class1("Box", union([lit_int(1), TyInt {}])), class1("Box", TyInt {})),
    );
    assert.is_true(!ctx.is_subtype(class1("Box", TyInt {}), class1("Box", TyString {})));
}

// ── subtype basics ───────────────────────────────────────────────────────

test "subtype basics" {
    let ctx = Ctx.new();
    assert.is_true(ctx.is_subtype(lit_int(1), TyInt {}));
    assert.is_true(ctx.is_subtype(variant("Side", "Left"), enum_ty("Side")));
    assert.is_true(ctx.is_subtype(TyNever {}, TyInt {}));
    assert.is_true(ctx.is_subtype(TyInt {}, TyUnknown {}));
    assert.is_true(!ctx.is_subtype(TyUnknown {}, TyInt {}));
    // No numeric coercion across representations.
    assert.is_true(!ctx.is_subtype(TyInt {}, TyBigint {}));
    // Union decomposition.
    assert.is_true(ctx.is_subtype(TyInt {}, union([TyInt {}, TyString {}])));
    assert.is_true(
        ctx.is_subtype(union([TyInt {}, TyString {}]), union([TyString {}, TyInt {}, TyBool {}])),
    );
    assert.is_true(!ctx.is_subtype(union([TyInt {}, TyString {}]), TyInt {}));
}

// ── subtyping: variance, holes, unions ───────────────────────────────────

test "invariant arg distinguishes top from recovery sentinel" {
    // `unknown` is invariant-distinct (`Box<unknown>` is not `Box<int>`); the
    // Error sentinel stays bidirectionally compatible.
    let ctx = Ctx.new();
    assert.is_true(!ctx.is_subtype(class1("Box", TyUnknown {}), class1("Box", TyInt {})));
    assert.is_true(!ctx.is_subtype(class1("Box", TyInt {}), class1("Box", TyUnknown {})));
    assert.is_true(ctx.is_subtype(class1("Box", TyError {}), class1("Box", TyInt {})));
    assert.is_true(ctx.is_subtype(class1("Box", TyInt {}), class1("Box", TyError {})));
}

test "function subtyping is contravariant in params covariant in return" {
    // `(int | string) -> bool` is a subtype of `(int) -> bool | float`.
    let ctx = Ctx.new();
    let foo = TyFunction {
        params: [
            FunctionParamTy {
                name: null,
                ty: union([TyInt {}, TyString {}]),
                mode: FunctionParamMode.Required,
            },
        ],
        ret: TyBool {},
        throws_: TyNever {},
    };
    let expected = TyFunction {
        params: [FunctionParamTy { name: null, ty: TyInt {}, mode: FunctionParamMode.Required }],
        ret: union([TyBool {}, TyFloat {}]),
        throws_: TyNever {},
    };
    assert.is_true(ctx.is_subtype(foo, expected));
    // The reverse fails on the contravariant parameter.
    assert.is_true(!ctx.is_subtype(expected, foo));
}

test "function throws is covariant" {
    let ctx = Ctx.new();
    let mk = (throws_: Ty) -> Ty {
        TyFunction { params: [], ret: TyString {}, throws_: throws_ }
    };
    assert.is_true(ctx.is_subtype(mk(TyNever {}), mk(TyInt {})));
    assert.is_true(!ctx.is_subtype(mk(TyInt {}), mk(TyNever {})));
}

test "function required param names are insignificant" {
    let ctx = Ctx.new();
    let mk = (name: string?) -> Ty {
        TyFunction {
            params: [FunctionParamTy { name: name, ty: TyInt {}, mode: FunctionParamMode.Required }],
            ret: TyString {},
            throws_: TyNever {},
        }
    };
    assert.is_true(ctx.equivalent(mk("a"), mk("b")));
    assert.is_true(ctx.equivalent(mk("a"), mk(null)));
}

test "function optional params follow the superset rule" {
    // Optional params match by name, and the subtype declares a superset of
    // them; their order is insignificant.
    let ctx = Ctx.new();
    let func = (params: FunctionParamTy[]) -> Ty {
        TyFunction { params: params, ret: TyString {}, throws_: TyNever {} }
    };
    let req = FunctionParamTy { name: null, ty: TyString {}, mode: FunctionParamMode.Required };
    let opt_max = FunctionParamTy { name: "max", ty: TyInt {}, mode: FunctionParamMode.Optional };
    let opt_filter = FunctionParamTy { name: "filter", ty: TyString {}, mode: FunctionParamMode.Optional };
    let two = func([req, opt_max, opt_filter]);
    let one = func([req, opt_filter]);
    // More optionals <: fewer optionals; the reverse fails (missing `max`).
    assert.is_true(ctx.is_subtype(two, one));
    assert.is_true(!ctx.is_subtype(one, two));
    // Reordered forms are mutual subtypes.
    let two_reordered = func([req, opt_filter, opt_max]);
    assert.is_true(ctx.is_subtype(two, two_reordered));
    assert.is_true(ctx.is_subtype(two_reordered, two));
}

test "function optional and required params are incomparable" {
    let ctx = Ctx.new();
    let mk = (optional_param: bool) -> Ty {
        let mode = if (optional_param) {
            FunctionParamMode.Optional
        } else {
            FunctionParamMode.Required
        };
        TyFunction {
            params: [FunctionParamTy { name: "value", ty: TyInt {}, mode: mode }],
            ret: TyString {},
            throws_: TyNever {},
        }
    };
    assert.is_true(!ctx.is_subtype(mk(true), mk(false)));
    assert.is_true(!ctx.is_subtype(mk(false), mk(true)));
}

test "interface membership through unions" {
    let ctx = Ctx.new();
    ctx.impls.push((qtn("Dog"), qtn("Animal")));
    ctx.impls.push((qtn("Cat"), qtn("Animal")));
    // A concrete implementor is a subtype of an interface wrapped in a union.
    assert.is_true(ctx.is_subtype(class_("Dog"), union([iface("Animal"), TyNull {}])));
    // A union of implementors is a subtype of the interface.
    assert.is_true(ctx.is_subtype(union([class_("Dog"), class_("Cat")]), iface("Animal")));
    // `null` is not a member of the bare interface.
    assert.is_true(!ctx.is_subtype(optional(class_("Dog")), iface("Animal")));
}

test "type var is reflexive independent of its bound" {
    let ctx = Ctx.new();
    assert.is_true(ctx.is_subtype(typevar(0, "T"), typevar(0, "T")));
    assert.is_true(ctx.is_subtype(typevar(0, "T"), union([typevar(0, "T"), typevar(1, "U")])));
    assert.is_true(ctx.is_subtype(typevar(0, "T"), optional(typevar(0, "T"))));
    // An unbounded `T` is not a subtype of an unrelated concrete type.
    assert.is_true(!ctx.is_subtype(typevar(0, "T"), TyInt {}));
}

test "symbolic associated type projection subtypes via its bound" {
    // `interface Iter { type Item extends Summarizable }`, Summarizable
    // requiring Displayable: `(T as Iter).Item` is a subtype of its bound's
    // supertypes.
    let ctx = Ctx.new();
    let iter_bounds: map<string, Ty[]> = {};
    iter_bounds.set("Item", [iface("Summarizable")]);
    ctx.assoc_bounds.set(qtn("Iter"), iter_bounds);
    ctx.requires_.push((qtn("Summarizable"), qtn("Displayable")));
    let iter_proj = TyAssociatedTypeProjection {
        base: typevar(0, "T"),
        interface_: as_interface(iface("Iter")) ?? baml.sys.panic("iface() builds an interface existential"),
        member: "Item",
    };
    assert.is_true(ctx.is_subtype(iter_proj, iface("Summarizable")));
    // Including transitively through the bound's `requires`.
    assert.is_true(ctx.is_subtype(iter_proj, iface("Displayable")));
    // Not a subtype of an interface the bound does not provide.
    assert.is_true(!ctx.is_subtype(iter_proj, iface("Unrelated")));
    // Reflexivity still holds.
    assert.is_true(ctx.is_subtype(iter_proj, iter_proj));
}

// ── aliases & recursion ──────────────────────────────────────────────────

test "non recursive alias expands" {
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("MyInt"), TyInt {});
    assert.is_true(ctx.equivalent(alias("MyInt"), TyInt {}));
}

test "unresolved alias is opaque" {
    let ctx = Ctx.new();
    let a = alias("Missing");
    // Equal only to itself; never equated to a concrete type.
    assert.is_true(ctx.equivalent(a, a));
    assert.is_true(!ctx.equivalent(a, TyInt {}));
}

test "recursive alias terminates" {
    // `Tree = int | Box<Tree>`: normalization and subtyping terminate.
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("Tree"), union([TyInt {}, class1("Box", alias("Tree"))]));
    let a = alias("Tree");
    assert.is_true(ctx.equivalent(a, a));
    assert.is_true(ctx.is_subtype(a, a));
    // Not equivalent to a flat unrelated type.
    assert.is_true(!ctx.equivalent(a, TyInt {}));
}

// ── bool completeness ────────────────────────────────────────────────────

test "complete bool literals collapse to bool" {
    let ctx = Ctx.new();
    let both = union([lit_bool(true), lit_bool(false)]);
    assert.is_true(ctx.equivalent(both, TyBool {}));
    assert.is_true(ctx.is_subtype(TyBool {}, both));
    assert.is_true(ctx.is_subtype(both, TyBool {}));
    assert.is_true(
        ctx.equivalent(
            union([lit_bool(true), lit_bool(false), TyInt {}]),
            union([TyBool {}, TyInt {}]),
        ),
    );
    // A single literal does not collapse (absorption into a present base
    // still applies).
    assert.is_true(!ctx.equivalent(lit_bool(true), TyBool {}));
    assert.is_true(ctx.equivalent(union([TyBool {}, lit_bool(true)]), TyBool {}));
    // Through recursion: the collapse applies inside μ-bodies too.
    let rec = Ctx.new();
    rec.aliases.set(qtn("A"), union([lit_bool(true), lit_bool(false), list(alias("A"))]));
    rec.aliases.set(qtn("B"), union([TyBool {}, list(alias("B"))]));
    assert.is_true(rec.equivalent(alias("A"), alias("B")));
}

// ── equirecursive canonical forms ────────────────────────────────────────

// port: baml_type/src/normalize/tests.rs::int_list_alias @ d9be6853b
// `type <name> = int | <name>[]`.
function int_list_alias(ctx: Ctx, name: string) -> void throws never {
    ctx.aliases.set(qtn(name), union([TyInt {}, list(alias(name))]));
}

test "alpha equivalent recursive aliases" {
    // The alias name carries no identity.
    let ctx = Ctx.new();
    int_list_alias(ctx, "A");
    int_list_alias(ctx, "B");
    assert.is_true(ctx.equivalent(alias("A"), alias("B")));
    assert.is_true(ctx.is_subtype(alias("A"), alias("B")));
    assert.is_true(ctx.is_subtype(alias("B"), alias("A")));
    ctx.aliases.set(qtn("R"), class1("Box", alias("R")));
    ctx.aliases.set(qtn("S"), class1("Box", alias("S")));
    assert.is_true(ctx.equivalent(alias("R"), alias("S")));
}

test "recursive alias spelling invariance" {
    // Every finite unfolding spells the same regular tree.
    let ctx = Ctx.new();
    int_list_alias(ctx, "A");
    let body = union([TyInt {}, list(alias("A"))]);
    let twice = union([TyInt {}, list(body)]);
    assert.is_true(ctx.equivalent(alias("A"), body));
    assert.is_true(ctx.equivalent(alias("A"), twice));
    assert.is_true(ctx.equivalent(list(alias("A")), list(body)));
    assert.is_true(ctx.equivalent(class1("Box", alias("A")), class1("Box", body)));
}

test "mutually recursive aliases are equivalent" {
    // `type A = int | B[]` and `type B = int | A[]` unfold to one tree.
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("A"), union([TyInt {}, list(alias("B"))]));
    ctx.aliases.set(qtn("B"), union([TyInt {}, list(alias("A"))]));
    assert.is_true(ctx.equivalent(alias("A"), alias("B")));
    assert.is_true(ctx.equivalent(alias("A"), union([TyInt {}, list(alias("A"))])));
}

test "unguarded members are vacuous" {
    // `type A = A | A[]` is `type B = B[]`; a fully unguarded `type C = C` is
    // uninhabited.
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("A"), union([alias("A"), list(alias("A"))]));
    ctx.aliases.set(qtn("B"), list(alias("B")));
    ctx.aliases.set(qtn("C"), alias("C"));
    assert.is_true(ctx.equivalent(alias("A"), alias("B")));
    assert.is_true(ctx.equivalent(alias("C"), TyNever {}));
    // The assumption probe must not prove `string <: A` through the
    // unguarded member.
    assert.is_true(!ctx.is_subtype(TyString {}, alias("A")));
    assert.is_true(!ctx.is_subtype(class_("Dog"), alias("A")));
    // The guarded content is still there.
    assert.is_true(ctx.is_subtype(list(alias("A")), alias("A")));
}

test "normalize is idempotent on recursive aliases" {
    let ctx = Ctx.new();
    int_list_alias(ctx, "A");
    ctx.aliases.set(qtn("M"), union([TyInt {}, list(alias("B"))]));
    ctx.aliases.set(qtn("B"), union([TyInt {}, list(alias("M"))]));
    ctx.aliases.set(qtn("R"), class1("Box", alias("R")));
    let corpus = [
        alias("A"),
        list(alias("A")),
        class1("Box", alias("A")),
        alias("M"),
        alias("R"),
        union([TyString {}, alias("A")]),
    ];
    for (let t in corpus) {
        let once = ctx.normalize(t);
        let twice = ctx.normalize(once);
        assert.equal(once, twice);
        assert.is_true(ctx.equivalent(t, once));
    }
}

test "normalize folds nested recursion and unfolds the root" {
    let ctx = Ctx.new();
    int_list_alias(ctx, "A");
    // Root-unfold-once: the recursive occurrence folds back to the name.
    assert.equal(ctx.normalize(alias("A")), union([TyInt {}, list(alias("A"))]));
    // Nested recursion stays folded.
    assert.equal(ctx.normalize(list(alias("A"))), list(alias("A")));
    assert.equal(ctx.normalize(class1("Box", alias("A"))), class1("Box", alias("A")));
    // The inline spelling converges to the same rendering.
    assert.equal(
        ctx.normalize(union([TyInt {}, list(alias("A"))])),
        union([TyInt {}, list(alias("A"))]),
    );
    // An unguarded member vanishes from the rendering too.
    ctx.aliases.set(qtn("U"), union([alias("U"), list(alias("U"))]));
    assert.equal(ctx.normalize(alias("U")), list(alias("U")));
}

test "absorption completes across recursion" {
    // `type A = I | Box<A>` with `Box implements I`: the recursive member is
    // absorbed, and the μ-binder disappears with it.
    let ctx = Ctx.new();
    ctx.impls.push((qtn("Box"), qtn("I")));
    ctx.aliases.set(qtn("A"), union([iface("I"), class1("Box", alias("A"))]));
    assert.is_true(ctx.equivalent(alias("A"), iface("I")));
    assert.equal(ctx.normalize(alias("A")), iface("I"));
}

test "recursive disjointness is sound" {
    let ctx = Ctx.new();
    int_list_alias(ctx, "A");
    ctx.aliases.set(qtn("R"), class1("Box", alias("R")));
    // Two spellings of one recursive type are not disjoint invariant arguments.
    let spelled = class1("Box", alias("A"));
    let unfolded = class1("Box", union([TyInt {}, list(alias("A"))]));
    assert.is_true(!ctx.definitely_disjoint(spelled, unfolded));
    assert.equal(ctx.constant_equality(spelled, unfolded), null);
    // Genuinely different types keep their provable disjointness through μ.
    assert.is_true(ctx.definitely_disjoint(alias("R"), class_("Dog")));
    assert.is_true(ctx.definitely_disjoint(class1("Box", alias("R")), class_("Dog")));
}

// ── compare-style exact-type use ─────────────────────────────────────────

test "catch result union equals base" {
    // `int | 99` vs `int` must be equivalent for exact-type ordering.
    let ctx = Ctx.new();
    assert.is_true(ctx.equivalent(union([TyInt {}, lit_int(99)]), TyInt {}));
}
