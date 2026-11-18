// port: baml_compiler2_hir/src/type_ref.rs::tests @ d9be6853b

// port: baml_compiler2_hir/src/type_ref.rs::tests::span @ d9be6853b
function type_ref_test_span(start: int, end: int) -> root.syntax.TextRange throws never {
    root.syntax.TextRange { start: start, end: end }
}

// port: baml_compiler2_hir/src/type_ref.rs::tests::map_of_string_to_int_list @ d9be6853b
// `map<string, int[]>`, with every node's span offset by `shift`.
function map_of_string_to_int_list(shift: int) -> root.ast.TypeExpr throws never {
    let s = (a: int, b: int) -> root.syntax.TextRange {
        type_ref_test_span(a + shift, b + shift)
    };
    root.ast.TypeExpr {
        kind: root.ast.TypeExprKindMap {
            key: root.ast.TypeExpr { kind: root.ast.TypeExprKindString {}, span: s(4, 10) },
            value: root.ast.TypeExpr {
                kind: root.ast.TypeExprKindList {
                    inner: root.ast.TypeExpr { kind: root.ast.TypeExprKindInt {}, span: s(12, 15) },
                },
                span: s(12, 17),
            },
        },
        span: s(0, 18),
    }
}

// port: baml_compiler2_hir/src/type_ref.rs::tests::lower @ d9be6853b
function type_ref_test_lower(
    te: root.ast.TypeExpr,
) -> (TypeRefStore, TypeRefSourceMap, int) throws never {
    let builder = TypeRefBuilder.new();
    let root_id = builder.lower(te);
    let (let store, let source_map) = builder.finish();
    (store, source_map, root_id)
}

// port: baml_compiler2_hir/src/type_ref.rs::tests::children_are_allocated_before_parents @ d9be6853b
test "children are allocated before parents" {
    let (let store, _, let root_id) = type_ref_test_lower(map_of_string_to_int_list(0));

    // Post-order: the root is allocated last.
    let entries = store.iter();
    assert.equal(root_id, entries[entries.length() - 1].0);

    // string, int, int[], map: post-order.
    assert.equal(store.len(), 4);
    let kinds = entries.map((entry) -> {
        entry.1.kind
    });
    assert.is_type<TypeRefKindString>(kinds[0]);
    assert.is_type<TypeRefKindInt>(kinds[1]);
    assert.is_type<TypeRefKindList>(kinds[2]);
    assert.is_type<TypeRefKindMap>(kinds[3]);
}

// port: baml_compiler2_hir/src/type_ref.rs::tests::shifting_spans_does_not_change_the_store @ d9be6853b
// Shifting every span (a whitespace-only edit) leaves the store equal, while
// the source map reports the new spans.
test "shifting spans does not change the store" {
    let (let unshifted, let map_a, let root_a) = type_ref_test_lower(map_of_string_to_int_list(0));
    let (let shifted, let map_b, let root_b) = type_ref_test_lower(map_of_string_to_int_list(100));

    assert.equal(unshifted, shifted);
    assert.equal(map_a.span(root_a), type_ref_test_span(0, 18));
    assert.equal(map_b.span(root_b), type_ref_test_span(100, 118));
}

// port: baml_compiler2_hir/src/type_ref.rs::tests::structural_changes_do_change_the_store @ d9be6853b
test "structural changes do change the store" {
    let (let int_keyed, _, _) = type_ref_test_lower(map_of_string_to_int_list(0));
    let (let bool_keyed, _, _) = type_ref_test_lower(
        root.ast.TypeExpr {
            kind: root.ast.TypeExprKindMap {
                key: root.ast.TypeExpr {
                    kind: root.ast.TypeExprKindBool {},
                    span: type_ref_test_span(4, 10),
                },
                value: root.ast.TypeExpr {
                    kind: root.ast.TypeExprKindList {
                        inner: root.ast.TypeExpr {
                            kind: root.ast.TypeExprKindInt {},
                            span: type_ref_test_span(12, 15),
                        },
                    },
                    span: type_ref_test_span(12, 17),
                },
            },
            span: type_ref_test_span(0, 18),
        },
    );

    assert.is_true(int_keyed != bool_keyed);
}

// A type expression of `kind` at an empty span.
function type_ref_test_prim(kind: root.ast.TypeExprKind) -> root.ast.TypeExpr throws never {
    root.ast.TypeExpr { kind: kind, span: type_ref_test_span(0, 0) }
}

// The path type `name` (dotted).
function type_ref_test_path(name: string) -> root.ast.TypeExpr throws never {
    type_ref_test_prim(
        root.ast.TypeExprKindPath {
            path: root.base.Path.new(name.split(".")),
            generic_args: [],
            associated_type_bindings: [],
        },
    )
}

// A function type expression.
function type_ref_test_func(
    params: root.ast.FunctionTypeParam[],
    ret: root.ast.TypeExpr,
    throws_: root.ast.TypeExpr?,
) -> root.ast.TypeExpr throws never {
    type_ref_test_prim(root.ast.TypeExprKindFunction { params: params, ret: ret, throws_: throws_ })
}

// port: baml_compiler2_hir/src/type_ref.rs::tests::display_is_byte_identical_to_ast @ d9be6853b
// `TypeRefStore.display` renders byte for byte the same text as
// `root.ast.TypeExpr`'s `to_string`, over the paren- and recursion-sensitive
// shapes.
test "display is byte identical to ast" {
    let prim = type_ref_test_prim;
    let path = type_ref_test_path;
    let func = type_ref_test_func;
    let cases: root.ast.TypeExpr[] = [
        prim(root.ast.TypeExprKindInt {}),
        prim(root.ast.TypeExprKindString {}),
        path("User"),
        path("baml.http.Request"),
        // `Stream<int, Item = string>`: generic args plus an assoc binding.
        prim(
            root.ast.TypeExprKindPath {
                path: root.base.Path.new(["Stream"]),
                generic_args: [prim(root.ast.TypeExprKindInt {})],
                associated_type_bindings: [
                    root.ast.AssociatedTypeBinding {
                        name: "Item",
                        ty: prim(root.ast.TypeExprKindString {}),
                    },
                ],
            },
        ),
        // `int?`, `int[]`, `map<string, int[]>`.
        prim(root.ast.TypeExprKindOptional { inner: prim(root.ast.TypeExprKindInt {}) }),
        prim(root.ast.TypeExprKindList { inner: prim(root.ast.TypeExprKindInt {}) }),
        map_of_string_to_int_list(0),
        // `int | string`, and `int | (() -> null)` (union parenthesizes fns).
        prim(
            root.ast.TypeExprKindUnion {
                variants: [prim(root.ast.TypeExprKindInt {}), prim(root.ast.TypeExprKindString {})],
            },
        ),
        prim(
            root.ast.TypeExprKindUnion {
                variants: [
                    prim(root.ast.TypeExprKindInt {}),
                    func([], prim(root.ast.TypeExprKindNull {}), null),
                ],
            },
        ),
        // `(a: int, b?: string) -> bool throws MyError`.
        func(
            [
                root.ast.FunctionTypeParam {
                    name: "a",
                    optional: false,
                    ty: prim(root.ast.TypeExprKindInt {}),
                },
                root.ast.FunctionTypeParam {
                    name: "b",
                    optional: true,
                    ty: prim(root.ast.TypeExprKindString {}),
                },
            ],
            prim(root.ast.TypeExprKindBool {}),
            path("MyError"),
        ),
        // `() -> (() -> null)`: a function return parenthesizes a function.
        func([], func([], prim(root.ast.TypeExprKindNull {}), null), null),
        // `T.Item` and `(T as Iterator).Item`.
        prim(
            root.ast.TypeExprKindAssociatedTypeProjection {
                base: path("T"),
                interface_: null,
                member: "Item",
            },
        ),
        prim(
            root.ast.TypeExprKindAssociatedTypeProjection {
                base: path("T"),
                interface_: path("Iterator"),
                member: "Item",
            },
        ),
    ];

    for (let te in cases) {
        let (let store, _, let root_id) = type_ref_test_lower(te);
        assert.equal(te.to_string(), store.display(root_id).to_string());
    }
}
