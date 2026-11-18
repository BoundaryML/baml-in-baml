// port: baml_type/src/decl_cycles.rs::tests @ d9be6853b
//
// Rust's one-line constructors `type_alias(name)` and `tuple(elements)` are
// written as class literals; its `optional(ty)` (`Union([ty, Null])`) is
// lib.baml's `optional`, which builds the same union for every type used
// here.

// port: baml_type/src/decl_cycles.rs::tests::qn @ d9be6853b
function qn(name: string) -> DeclName throws never {
    DeclName { pkg: 0, namespace: [], name: name }
}

// port: baml_type/src/decl_cycles.rs::tests::invalid @ d9be6853b
// The short names of the aliases `find_invalid_alias_cycles` reports, sorted.
function invalid(decls: (string, Ty)[]) -> string[] throws never {
    let aliases: map<DeclName, Ty> = {};
    for (let decl in decls) {
        aliases.set(qn(decl.0), decl.1);
    }
    find_invalid_alias_cycles(aliases).keys()
        .map((name) -> {
            name.name
        })
        .sort_by((a, b) -> {
            a.cmp(b)
        })
}

// port: baml_type/src/decl_cycles.rs::tests::direct_self_reference_is_recursive @ d9be6853b
test "direct self reference is recursive" {
    // `type List = null | List`
    let aliases: map<DeclName, Ty> = {};
    aliases.set(qn("List"), TyUnion { members: [TyNull {}, TyTypeAlias { name: qn("List") }] });
    assert.is_true(ResolvedAliases.from_aliases(aliases).recursive.has(qn("List")))
}

// port: baml_type/src/decl_cycles.rs::tests::non_recursive_alias_is_not_marked @ d9be6853b
test "non recursive alias is not marked" {
    // `type MyInt = int`
    let aliases: map<DeclName, Ty> = {};
    aliases.set(qn("MyInt"), TyInt {});
    assert.is_true(!ResolvedAliases.from_aliases(aliases).recursive.has(qn("MyInt")))
}

// port: baml_type/src/decl_cycles.rs::tests::recursion_through_class_type_arg_is_detected @ d9be6853b
test "recursion through class type arg is detected" {
    // `type A = Box<A>`: recursion goes through a class generic argument.
    // Cycle detection must descend into class type args or it would miss
    // this and expansion would recurse forever.
    let aliases: map<DeclName, Ty> = {};
    aliases.set(qn("A"), TyClass { name: qn("Box"), args: [TyTypeAlias { name: qn("A") }] });
    assert.is_true(ResolvedAliases.from_aliases(aliases).recursive.has(qn("A")))
}

// port: baml_type/src/decl_cycles.rs::tests::recursion_through_interface_type_arg_is_detected @ d9be6853b
test "recursion through interface type arg is detected" {
    // `type A = BoxLike<A>`: recursion through an interface generic argument,
    // detected just like class generic arguments.
    let aliases: map<DeclName, Ty> = {};
    aliases.set(
        qn("A"),
        TyInterface {
            name: qn("BoxLike"),
            args: [TyTypeAlias { name: qn("A") }],
            associated_types: [],
        },
    );
    assert.is_true(ResolvedAliases.from_aliases(aliases).recursive.has(qn("A")))
}

// port: baml_type/src/decl_cycles.rs::tests::tuple_recursion_terminated_by_null_is_valid @ d9be6853b
test "tuple recursion terminated by null is valid" {
    let chain = TyTypeAlias { name: qn("Chain") };
    let t = TyTypeAlias { name: qn("T") };
    assert.equal(invalid([("Chain", TyTuple { items: [TyInt {}, optional(chain)] })]), []);
    assert.equal(invalid([("Chain", optional(TyTuple { items: [TyInt {}, chain] }))]), []);
    assert.equal(invalid([("T", TyTuple { items: [TyInt {}, TyList { elem: t }] })]), [])
}

// port: baml_type/src/decl_cycles.rs::tests::tuple_recursion_without_a_finite_value_is_invalid @ d9be6853b
test "tuple recursion without a finite value is invalid" {
    let t = TyTypeAlias { name: qn("T") };
    let bad = TyTypeAlias { name: qn("Bad") };
    assert.equal(invalid([("T", TyTuple { items: [TyInt {}, t] })]), ["T"]);
    assert.equal(invalid([("Bad", TyTuple { items: [bad, optional(TyInt {})] })]), ["Bad"]);
    assert.equal(invalid([("T", TyTuple { items: [t, TyList { elem: t }] })]), ["T"])
}

// port: baml_type/src/decl_cycles.rs::tests::mutual_tuple_recursion_through_null_is_valid @ d9be6853b
test "mutual tuple recursion through null is valid" {
    let a = TyTypeAlias { name: qn("A") };
    let b = TyTypeAlias { name: qn("B") };
    assert.equal(invalid([("A", TyTuple { items: [TyInt {}, b] }), ("B", optional(a))]), []);
    assert.equal(
        invalid([("A", TyTuple { items: [TyInt {}, b] }), ("B", TyTuple { items: [a, TyString {}] })]),
        ["A", "B"],
    )
}

// port: baml_type/src/decl_cycles.rs::tests::vacuous_self_member_beside_a_finite_one_is_valid @ d9be6853b
test "vacuous self member beside a finite one is valid" {
    let a = TyTypeAlias { name: qn("A") };
    assert.equal(invalid([("A", optional(a))]), []);
    assert.equal(invalid([("A", a)]), ["A"])
}

// port: baml_type/src/decl_cycles.rs::tests::class_cycle_follows_tuple_elements @ d9be6853b
test "class cycle follows tuple elements" {
    let class_a = TyClass { name: qn("A"), args: [] };
    let no_aliases: map<DeclName, Ty> = {};
    let required: map<DeclName, (string, Ty)[]> = {};
    required.set(qn("A"), [("x", TyTuple { items: [TyInt {}, class_a] })]);
    assert.equal(find_invalid_class_cycles(required, no_aliases).length(), 1);
    let optional_field: map<DeclName, (string, Ty)[]> = {};
    optional_field.set(qn("A"), [("x", TyTuple { items: [TyInt {}, optional(class_a)] })]);
    assert.equal(find_invalid_class_cycles(optional_field, no_aliases).length(), 0)
}
