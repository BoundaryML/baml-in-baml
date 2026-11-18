// The generated family: conversions through satellites and shallow members,
// and the InferTy pool.

function class_name(name: string) -> DeclName throws never {
    DeclName { pkg: 0, namespace: [], name: name }
}

// `map<string, (int, Foo) -> Bar throws Never>`: a nested satellite and a
// head, with an `Error` sentinel where `with_error` asks for one.
function sample(with_error: bool) -> Ty throws never {
    let ret: Ty = if (with_error) {
        TyError {}
    } else {
        TyClass { name: class_name("Bar"), args: [] }
    };
    TyMap {
        key: TyString {},
        value: TyFunction {
            params: [
                FunctionParamTy { name: null, ty: TyInt {}, mode: FunctionParamMode.Required },
                FunctionParamTy {
                    name: "foo",
                    ty: TyClass { name: class_name("Foo"), args: [] },
                    mode: FunctionParamMode.Optional,
                },
            ],
            ret: ret,
            throws_: TyNever {},
        },
    }
}

// The variant a narrowing failed on, or "ok".
function narrow_outcome(t: Ty) -> string throws never {
    let _ = narrow_ty_to_concrete_ty(t) catch_all (e) {
        _ => {
            return `${e.variant} -> ${e.into}`;
        },
    };
    "ok"
}

test "narrowing round-trips through a shallow member" {
    let t = sample(false);
    let concrete = narrow_ty_to_concrete_ty(t);
    assert.equal(widen_concrete_ty_to_ty(concrete), t);
}

test "narrowing fails on a nested variant the target lacks" {
    assert.equal(narrow_outcome(sample(true)), "Error -> RuntimeTy");
}

test "interning shares equal subtrees and propagates flags" {
    let pool = InferPool.new();
    let a = intern_ty(pool, sample(true));
    let b = intern_ty(pool, sample(true));
    assert.equal(a, b);
    assert.is_true(pool.has(a, HAS_ERROR));
    assert.is_true(!pool.has(a, HAS_INFER));
    assert.equal(resolve_ty(pool, a), sample(true));
}

test "types order as Rust's derived Ord: variant order, then fields" {
    let foo = TyClass { name: class_name("Foo"), args: [] };
    let foo_int = TyClass { name: class_name("Foo"), args: [TyInt {}] };
    let bar = TyClass { name: class_name("Bar"), args: [TyString {}] };
    let tys: Ty[] = [TyList { elem: TyInt {} }, foo_int, TyString {}, bar, TyInt {}, foo, TyNever {}];
    tys.sort_by(cmp_ty);
    assert.equal(tys, [TyInt {}, TyString {}, bar, foo, foo_int, TyList { elem: TyInt {} }, TyNever {}]);
}
