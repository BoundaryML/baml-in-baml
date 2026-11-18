// port: baml_type/src/lib.rs::tests @ d9be6853b
//
// Rust asserts these renderings through `Display`, which is not ported (see
// lib.baml); `render_with` agrees with it on every type rendered here.
// Not ported: `test_opaque_constructors_build_concrete_variants` (it tests
// the one-line constructors, which are not ported).

// A strategy that spells a head by its short name, as `Display` does for a
// local wire name.
class ShortNames {
    implements TyRenderStrategy {
        function qtn(self, qtn: DeclName) -> string {
            qtn.name
        }

        function type_var(self, name: string) -> string {
            name
        }
    }
}

function rendered(ty: Ty) -> string throws never {
    render_with(widen_ty_to_lowering_ty(ty), ShortNames {})
}

function local_decl(name: string) -> DeclName throws never {
    DeclName { pkg: 0, namespace: [], name: name }
}

function type_var_t() -> Ty throws never {
    TyTypeVar { param: ParamTy { index: 0, name: "T" } }
}

function item_projection() -> Ty throws never {
    TyAssociatedTypeProjection {
        base: type_var_t(),
        interface_: InterfaceConstraint { name: local_decl("Iterator"), generics: [], associated_types: [] },
        member: "Item",
    }
}

function null_function() -> Ty throws never {
    TyFunction { params: [], ret: TyNull {}, throws_: TyNull {} }
}

function int_to_string() -> Ty throws never {
    TyFunction {
        params: [FunctionParamTy { name: null, ty: TyInt {}, mode: FunctionParamMode.Required }],
        ret: TyString {},
        throws_: TyNever {},
    }
}

test "from primitive preserves primitive kind" {
    for (let primitive in PRIMITIVE_TYPES) {
        assert.equal(rendered(from_primitive(primitive)), primitive_type_alias(primitive));
    }
}

test "is valid impl subject classifies variants" {
    let valid: Ty[] = [
        TyInt {},
        TyClass { name: local_decl("Foo"), args: [] },
        TyEnum { name: local_decl("Color") },
        TyList { elem: TyInt {} },
        TyMap { key: TyString {}, value: TyInt {} },
        TyType {},
        TyResource {},
        TyPromptAst {},
        TyNever {},
        type_var_t(),
        item_projection(),
    ];
    for (let ty in valid) {
        assert.is_true(is_valid_impl_subject(ty));
    }
    let invalid: Ty[] = [
        TyLiteral { value: root.base.LiteralInt { value: 1 }, freshness: Freshness.Regular },
        TyEnumVariant { name: local_decl("Color"), variant: "Red" },
        TyInterface { name: local_decl("I"), args: [], associated_types: [] },
        TyUnion { members: [TyInt {}, TyString {}] },
        // `Future` is dispatchable at runtime; written impls on it are simply
        // not implemented yet.
        TyFuture { value: TyInt {}, error: TyNull {} },
        null_function(),
        TyRustType {},
        TyTypeAlias { name: local_decl("A") },
        TyUnknown {},
        TyError {},
    ];
    for (let ty in invalid) {
        assert.is_true(!is_valid_impl_subject(ty));
    }
}

test "is concrete classifies variants" {
    // Unlike is_valid_impl_subject, `Function`, `Future` and `RustType` are
    // concrete types.
    let concrete: Ty[] = [
        TyInt {},
        TyBigint {},
        TyFloat {},
        TyString {},
        TyBool {},
        TyNull {},
        TyClass { name: local_decl("Foo"), args: [] },
        TyEnum { name: local_decl("Color") },
        TyList { elem: TyInt {} },
        TyMap { key: TyString {}, value: TyInt {} },
        TyTuple { items: [TyInt {}, TyString {}] },
        TyTuple {
            items: [
                TyUnion { members: [TyInt {}, TyString {}] },
                TyLiteral { value: root.base.LiteralInt { value: 1 }, freshness: Freshness.Regular },
            ],
        },
        null_function(),
        TyFuture { value: TyInt {}, error: TyNull {} },
        TyType {},
        TyResource {},
        TyPromptAst {},
        TyRustType {},
    ];
    for (let ty in concrete) {
        assert.is_true(is_concrete(ty));
    }
    let not_concrete: Ty[] = [
        TyUnion { members: [TyInt {}, TyString {}] },
        TyInterface { name: local_decl("I"), args: [], associated_types: [] },
        TyUnknown {},
        TyLiteral { value: root.base.LiteralInt { value: 1 }, freshness: Freshness.Regular },
        TyEnumVariant { name: local_decl("Color"), variant: "Red" },
        TyNever {},
        type_var_t(),
        item_projection(),
        TyTypeAlias { name: local_decl("A") },
        TyError {},
    ];
    for (let ty in not_concrete) {
        assert.is_true(!is_concrete(ty));
    }
}

test "test display opaque types" {
    assert.equal(rendered(TyResource {}), "ai.Resource");
    assert.equal(rendered(TyPromptAst {}), "ai.Prompt");
    assert.equal(rendered(TyType {}), "reflect.Type")
}

test "test display nullable union is plain union" {
    // `?` does not survive lowering; a nullable type renders as a union.
    let ty = optional(TyUnion { members: [TyInt {}, TyString {}] });
    assert.equal(rendered(ty), "int | string | null")
}

test "test display list union parenthesized" {
    let ty = TyList { elem: TyUnion { members: [TyInt {}, TyString {}] } };
    assert.equal(rendered(ty), "(int | string)[]")
}

test "test function display parenthesizes nested function returns" {
    let ty = TyFunction { params: [], ret: int_to_string(), throws_: TyNever {} };
    assert.equal(rendered(ty), "() -> ((int) -> string throws never) throws never")
}

test "test function display parenthesizes function postfix types" {
    assert.equal(rendered(optional(int_to_string())), "((int) -> string throws never) | null");
    assert.equal(rendered(TyList { elem: int_to_string() }), "((int) -> string throws never)[]")
}
