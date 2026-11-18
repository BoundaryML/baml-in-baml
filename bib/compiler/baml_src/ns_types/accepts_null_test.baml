// port: baml_type/src/accepts_null.rs::tests @ d9be6853b

function null_test_alias(name: string) -> Ty throws never {
    TyTypeAlias { name: DeclName { pkg: 0, namespace: [], name: name } }
}

// `Json = null | int | Json[]`, `Tree = Tree[] | int`, and `Loop = Loop`.
function null_test_definition(head: DeclName) -> Ty? throws never {
    match (head.name) {
        "Json" => {
            TyUnion { members: [TyNull {}, TyInt {}, TyList { elem: null_test_alias("Json") }] }
        },
        "Tree" => TyUnion { members: [TyList { elem: null_test_alias("Tree") }, TyInt {}] },
        "Loop" => null_test_alias("Loop"),
        _ => null,
    }
}

test "null is a value by meaning" {
    let cases: (Ty, bool)[] = [
        (TyNull {}, true),
        (TyUnknown {}, true),
        (optional(TyInt {}), true),
        (TyUnion { members: [TyInt {}, TyUnknown {}] }, true),
        (null_test_alias("Json"), true),
        (TyUnion { members: [TyString {}, null_test_alias("Json")] }, true),
        (TyInt {}, false),
        (null_test_alias("Tree"), false),
        (null_test_alias("Loop"), false),
        (null_test_alias("Missing"), false),
        (TyList { elem: TyNull {} }, false),
    ];
    for (let case in cases) {
        assert.equal(accepts_null(case.0, null_form, null_test_definition), case.1);
    }
}
