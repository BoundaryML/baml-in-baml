// port: baml_type/src/normalize/tests.rs::interned_entry @ d9be6853b
//
// The interned entry: every verdict must agree with the plain entry. Each
// test owns an InferPool (Rust's pool is global). The stub context and
// constructors are in normalize_test.baml.

// port: baml_type/src/normalize/tests.rs::interned_entry::it @ d9be6853b
function it(pool: InferPool, ty: Ty) -> ClosedTy throws never {
    ClosedTy.try_from(pool, pool.from_plain(ty)) catch (e) {
        OpenTy => baml.sys.panic("plain input carries no variables"),
    }
}

test "subtype and equivalence verdicts match the plain entry" {
    let pool = InferPool.new();
    let ctx = Ctx.new();
    ctx.enums.set(qtn("Side"), ["L", "R"]);
    ctx.aliases.set(qtn("Loop"), list(alias("Loop")));
    let pairs: (Ty, Ty)[] = [
        (lit_int(1), TyInt {}),
        (TyInt {}, lit_int(1)),
        (TyInt {}, union([TyInt {}, TyString {}])),
        (union([TyInt {}, TyString {}]), TyInt {}),
        (list(lit_int(1)), list(TyInt {})),
        (TyNever {}, class_("Box")),
        (class_("Box"), TyUnknown {}),
        (variant("Side", "L"), enum_ty("Side")),
        (enum_ty("Side"), variant("Side", "L")),
        (union([variant("Side", "L"), variant("Side", "R")]), enum_ty("Side")),
        (alias("Loop"), list(alias("Loop"))),
        (class1("Box", TyInt {}), class1("Box", union([TyInt {}, TyString {}]))),
    ];
    for (let pair in pairs) {
        let sub = pair.0;
        let sup = pair.1;
        assert.equal(
            is_subtype_interned(pool, it(pool, sub), it(pool, sup), ctx),
            ctx.is_subtype(sub, sup),
        );
        assert.equal(
            equivalent_interned(pool, it(pool, sub), it(pool, sup), ctx),
            ctx.equivalent(sub, sup),
        );
    }
    // ACI equivalence through the interned entry.
    assert.is_true(
        equivalent_interned(
            pool,
            it(pool, union([TyInt {}, TyString {}])),
            it(pool, union([TyString {}, TyInt {}])),
            ctx,
        ),
    );
}

test "interned verdicts agree with the canonical relation for every kind pair" {
    let pool = InferPool.new();
    let (let ctx, let plain) = kind_corpus();
    let corpus = plain.map((t) -> {
        it(pool, t)
    });
    let cache = InternedCanonicalCache.new();
    for (let sub in corpus) {
        for (let sup in corpus) {
            let canonical_sub = canonical_interned(pool, sub, ctx);
            let canonical_sup = canonical_interned(pool, sup, ctx);
            let subtype = is_subtype_of(canonical_sub, canonical_sup, ctx, []);
            let equivalent = canonical_sub == canonical_sup;
            assert.equal(is_subtype_interned(pool, sub, sup, ctx), subtype);
            assert.equal(cache.is_subtype(pool, sub, sup, ctx), subtype);
            assert.equal(equivalent_interned(pool, sub, sup, ctx), equivalent);
            assert.equal(cache.equivalent(pool, sub, sup, ctx), equivalent);
        }
    }
}

test "interned cross category pairs are refuted without canonicalizing" {
    let pool = InferPool.new();
    let ctx = Ctx.new();
    json_alias(ctx, "Json");
    let cache = InternedCanonicalCache.new();
    for (let pair in cross_category_pairs()) {
        let sub = it(pool, pair.0);
        let sup = it(pool, pair.1);
        assert.is_true(!is_subtype_interned(pool, sub, sup, ctx));
        assert.is_true(!equivalent_interned(pool, sub, sup, ctx));
        assert.is_true(!cache.is_subtype(pool, sub, sup, ctx));
        assert.is_true(!cache.equivalent(pool, sub, sup, ctx));
        assert.equal(ctx.alias_lookups, 0);
    }
}

test "canonical cache matches reject free canonical relations" {
    let pool = InferPool.new();
    let ctx = Ctx.new();
    ctx.enums.set(qtn("Side"), ["L", "R"]);
    ctx.requires_.push((qtn("Readable"), qtn("Displayable")));
    int_list_alias(ctx, "JsonA");
    int_list_alias(ctx, "JsonB");
    let plain: (Ty, Ty)[] = [
        (alias("JsonA"), alias("JsonB")),
        (alias("JsonA"), TyInt {}),
        (lit_int(1), TyInt {}),
        (TyInt {}, union([TyInt {}, TyString {}])),
        (union([variant("Side", "L"), variant("Side", "R")]), enum_ty("Side")),
        (class_("Left"), class_("Right")),
        // Distinct interface heads cannot be rejected: `requires` relates them.
        (iface("Readable"), iface("Displayable")),
        (iface("Displayable"), iface("Readable")),
    ];
    let pairs = plain.map((p) -> {
        (it(pool, p.0), it(pool, p.1))
    });
    let cache = InternedCanonicalCache.new();
    // Twice: the first pass populates the cache, the second reads it warm.
    for (let round = 0; round < 2; round += 1) {
        for (let pair in pairs) {
            let canonical_a = canonical_interned(pool, pair.0, ctx);
            let canonical_b = canonical_interned(pool, pair.1, ctx);
            assert.equal(cache.equivalent(pool, pair.0, pair.1, ctx), canonical_a == canonical_b);
            assert.equal(
                cache.is_subtype(pool, pair.0, pair.1, ctx),
                is_subtype_of(canonical_a, canonical_b, ctx, []),
            );
        }
    }
}

test "cached normalization expands nested aliases and reuses the result" {
    let pool = InferPool.new();
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("MaybeInt"), union([TyInt {}, TyNull {}]));
    ctx.aliases.set(qtn("Nested"), union([alias("MaybeInt"), TyNull {}]));
    json_alias(ctx, "Json");
    let cache = InternedCanonicalCache.new();
    for (let plain in [alias("Nested"), union([alias("Nested"), TyNull {}]), alias("Json")]) {
        let input = it(pool, plain);
        let expected = normalize_interned(pool, input, ctx);
        let actual = cache.normalize(pool, input, ctx);
        assert.equal(actual, expected);
        if (input == it(pool, alias("Json"))) {
            // A recursive root must unfold.
            assert.is_true(pool.kinds[actual.ty] is InferTyUnion);
        } else {
            assert.equal(actual, it(pool, union([TyInt {}, TyNull {}])));
        }
        let lookups = ctx.alias_lookups;
        assert.equal(cache.normalize(pool, input, ctx), actual);
        // Warm normalization does not re-expand aliases.
        assert.equal(ctx.alias_lookups, lookups);
    }
}

test "resolved cache keeps both forms lazy in either access order" {
    let pool = InferPool.new();
    let ctx = Ctx.new();
    ctx.aliases.set(qtn("MaybeInt"), optional(TyInt {}));
    json_alias(ctx, "Json");
    for (let input in [it(pool, alias("MaybeInt")), it(pool, alias("Json"))]) {
        let expected_canonical = canonical_interned(pool, input, ctx);
        let expected_normalized = normalize_interned(pool, input, ctx);
        for (let normalized_first in [false, true]) {
            let cache = InternedCanonicalCache.new();
            if (normalized_first) {
                assert.equal(cache.normalize(pool, input, ctx), expected_normalized);
                assert.equal(cache.get_canonical(input), null);
            } else {
                assert.equal(cache.canonical(pool, input, ctx), expected_canonical);
                assert.equal(cache.get_normalized(input), null);
            }
            assert.equal(cache.canonical(pool, input, ctx), expected_canonical);
            assert.equal(cache.normalize(pool, input, ctx), expected_normalized);
            let lookups = ctx.alias_lookups;
            assert.equal(cache.canonical(pool, input, ctx), expected_canonical);
            assert.equal(cache.normalize(pool, input, ctx), expected_normalized);
            // Warm reads recompute nothing.
            assert.equal(ctx.alias_lookups, lookups);
        }
    }
}

test "complete bool literal set is bool in the plain entry too" {
    // The collapse lives in the shared algebra, not in an engine.
    let ctx = Ctx.new();
    assert.is_true(ctx.equivalent(union([lit_bool(true), lit_bool(false)]), TyBool {}));
    assert.is_true(!ctx.equivalent(lit_bool(true), TyBool {}));
}

test "canonical union joins and collapses" {
    let pool = InferPool.new();
    let ctx = Ctx.new();
    // true | false collapses to bool.
    let joined = canonical_union_interned(pool, [it(pool, lit_bool(true)), it(pool, lit_bool(false))], ctx);
    assert.equal(joined, it(pool, TyBool {}));
    // Absorption: 1 | int collapses to int.
    let absorbed = canonical_union_interned(pool, [it(pool, lit_int(1)), it(pool, TyInt {})], ctx);
    assert.equal(absorbed, it(pool, TyInt {}));
    // Join identity: the empty union is never.
    assert.equal(canonical_union_interned(pool, [], ctx), it(pool, TyNever {}));
    // Reordered spellings canonicalize identically.
    let ab = canonical_union_interned(pool, [it(pool, TyInt {}), it(pool, TyString {})], ctx);
    let ba = canonical_union_interned(pool, [it(pool, TyString {}), it(pool, TyInt {})], ctx);
    assert.equal(ab, ba);
}

test "normalize interned produces canonical interned types" {
    let pool = InferPool.new();
    let ctx = Ctx.new();
    let messy = it(pool, union([lit_int(1), TyInt {}, TyInt {}]));
    assert.equal(normalize_interned(pool, messy, ctx), it(pool, TyInt {}));
}
