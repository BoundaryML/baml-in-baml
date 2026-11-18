// port: baml_type/src/interned.rs::tests @ d9be6853b
//
// Not ported (Rust-only mechanics): `concurrent_primitive_interning_preserves_identity`,
// `concurrent_compound_interning_preserves_identity` (threads),
// `dropping_parent_evicts_its_unreferenced_children`,
// `dropping_last_handle_evicts_pool_entry` and its `pool_contains` helper
// (eviction: the pool never frees). `primitive_singletons_preserve_identity_without_live_callers`
// keeps its identity and flag asserts; the Arc-liveness part is dropped.

// port: baml_type/src/interned.rs::tests::plain_samples @ d9be6853b
// One plain type per variant, in Rust discriminant order.
function plain_samples() -> Ty[] throws never {
    let name = DeclName { pkg: 0, namespace: [], name: "Foo" };
    [
        TyInt {},
        TyBigint {},
        TyFloat {},
        TyString {},
        TyBool {},
        TyNull {},
        TyUint8Array {},
        TyLiteral { value: root.base.LiteralInt { value: 1 }, freshness: Freshness.Fresh },
        TyClass { name: name, args: [TyInt {}] },
        TyInterface {
            name: name,
            args: [TyInt {}],
            associated_types: [AssociatedType { name: "Item", ty: TyInt {} }],
        },
        TyEnum { name: name },
        TyEnumVariant { name: name, variant: "A" },
        TyList { elem: TyInt {} },
        TyMap { key: TyString {}, value: TyInt {} },
        TyUnion { members: [TyInt {}, TyNull {}] },
        TyFunction {
            params: [FunctionParamTy { name: "x", ty: TyInt {}, mode: FunctionParamMode.Required }],
            ret: TyInt {},
            throws_: TyNever {},
        },
        TyFuture { value: TyInt {}, error: TyNever {} },
        TyRustType {},
        TyType {},
        TyResource {},
        TyPromptAst {},
        TyTypeAlias { name: name },
        TyTypeVar { param: ParamTy { index: 0, name: "T" } },
        TyAssociatedTypeProjection {
            base: TyInt {},
            interface_: InterfaceConstraint { name: name, generics: [], associated_types: [] },
            member: "Item",
        },
        TyUnknown {},
        TyNever {},
        TyError {},
        TyTuple { items: [TyInt {}, TyString {}] },
    ]
}

test "roundtrip every variant" {
    let pool = InferPool.new();
    for (let plain in plain_samples()) {
        let closed = ClosedTy.try_from(pool, pool.from_plain(plain));
        assert.equal(pool.to_plain_closed(closed.ty), plain);
    }
}

test "open type cannot close" {
    // The boundary is the type system: an open tree never reaches the
    // conversion; the caller must defer, suppress, rename, or dispose.
    let pool = InferPool.new();
    let open = pool.add(InferTyList { elem: pool.add(TyInferVar { var: 3 }) });
    assert.is_true(pool.has_infer(open));
    let refused = ClosedTy.try_from(pool, open) catch (e) {
        OpenTy => null,
    };
    assert.equal(refused, null);
    let ok = ClosedTy.try_from(pool, pool.add(InferTyList { elem: pool.add(TyInt {}) }));
    assert.is_true(!pool.has_infer(ok.ty));
}

test "optional flattens union and is idempotent" {
    let pool = InferPool.new();
    let int = pool.add(TyInt {});
    let string = pool.add(TyString {});
    let optional = pool.optional(pool.add(InferTyUnion { members: [int, string] }));
    let members = match (pool.kinds[optional]) {
        let u: InferTyUnion => u.members,
        _ => baml.sys.panic("expected union"),
    };
    assert.equal(members.length(), 3);
    assert.is_true(members.includes(int));
    assert.is_true(members.includes(string));
    assert.is_true(
        members.some((member) -> {
            pool.kinds[member] is TyNull
        }),
    );
    assert.is_true(
        !members.some((member) -> {
            pool.kinds[member] is InferTyUnion
        }),
    );
    assert.equal(pool.optional(optional), optional);
}

test "structurally equal types share one allocation" {
    let pool = InferPool.new();
    for (let plain in plain_samples()) {
        assert.equal(pool.from_plain(plain), pool.from_plain(plain));
    }
    // Substructure is shared too: the element of `int[]` is the `int`.
    let int = pool.add(TyInt {});
    let list = pool.add(InferTyList { elem: int });
    let elem = match (pool.kinds[list]) {
        let l: InferTyList => l.elem,
        _ => baml.sys.panic("expected list"),
    };
    assert.equal(elem, int);
}

test "flags propagate from children" {
    let pool = InferPool.new();
    let int = pool.add(TyInt {});
    let infer = pool.add(TyInferVar { var: 0 });
    assert.is_true(pool.has_infer(infer));
    let deep = pool.add(InferTyList { elem: pool.add(InferTyUnion { members: [int, infer] }) });
    assert.is_true(pool.has_infer(deep));
    assert.is_true(!pool.has_error(deep));
    assert.is_true(!pool.has_infer(pool.add(InferTyList { elem: int })));
    assert.is_true(pool.has_error(pool.add(InferTyList { elem: pool.add(TyError {}) })));
}

// port: baml_type/src/interned.rs::tests::map_children_rebuilds_nested_structure::substitute @ d9be6853b
function substitute(pool: InferPool, ty: int, from: int, to: int) -> int {
    if (ty == from) {
        return to;
    }
    if (!pool.has_infer(ty)) {
        return ty;
    }
    pool.add(
        map_children(pool.kinds[ty], (child) -> {
            substitute(pool, child, from, to)
        }),
    )
}

test "map children rebuilds nested structure" {
    let pool = InferPool.new();
    let int = pool.add(TyInt {});
    let string = pool.add(TyString {});
    let v = pool.add(TyInferVar { var: 7 });
    let nested = pool.add(InferTyList { elem: pool.add(InferTyUnion { members: [int, v] }) });
    let resolved = substitute(pool, nested, v, string);
    assert.equal(
        resolved,
        pool.add(InferTyList { elem: pool.add(InferTyUnion { members: [int, string] }) }),
    );
    assert.is_true(!pool.has_infer(resolved));
    // Untouched subtrees keep their identity.
    let unchanged = substitute(pool, nested, pool.add(TyInferVar { var: 8 }), string);
    assert.equal(unchanged, nested);
}

test "ordering matches plain ordering" {
    // Rust sorts the plain samples with the plain derived `Ord` (not ported);
    // the samples are one per variant in discriminant order, so that sort
    // leaves them as they are. Interning in reverse makes the handle order
    // the opposite of the structural one.
    let pool = InferPool.new();
    let plain = plain_samples();
    let interned = plain.reverse().map((ty) -> {
        pool.from_plain(ty)
    });
    let materialized = interned
        .sort_by((a, b) -> {
            pool.cmp(a, b)
        })
        .map((ty) -> {
            pool.to_plain_closed(ClosedTy.try_from(pool, ty).ty)
        });
    assert.equal(materialized, plain_samples());
}

test "primitive singletons preserve identity without live callers" {
    let pool = InferPool.new();
    let kinds: InferTy[] = [
        TyInt {},
        TyBigint {},
        TyFloat {},
        TyString {},
        TyBool {},
        TyNull {},
        TyUint8Array {},
        TyRustType {},
        TyType {},
        TyResource {},
        TyPromptAst {},
        TyUnknown {},
        TyNever {},
        TyError {},
    ];
    for (let kind in kinds) {
        let first = pool.add(kind);
        let second = pool.add(kind);
        assert.equal(first, second);
        assert.equal(pool.flags[second], pool.compute_flags(kind));
    }
    assert.equal(pool.from_plain(TyString {}), pool.add(TyString {}));
}
