// port: baml_compiler2_ast/src/lib.rs::tests @ d9be6853b
//
// Type-expression and field-attribute lowering tests; the helpers are in
// `lib_test.baml`.

// port: lib.rs::tests::type_expr!. An expected type: `kind` at an empty span
// (equality ignores spans). The macro's container arms are written out as
// `TypeExprKindOptional { inner: .. }` and so on.
function ty(kind: TypeExprKind) -> TypeExpr throws never {
    TypeExpr { kind: kind, span: root.syntax.TextRange.empty(0) }
}

// The type alias `type T = <text>` lowers to.
function alias_type(text: string) -> TypeExpr throws never {
    first_type_alias(lower_source(`type T = ${text}\n`).items).type_expr
        ?? baml.sys.panic("expected type alias body")
}

// port: lib.rs::tests::type_expr_simple_optional @ d9be6853b
test "type expr simple optional" {
    assert.equal(alias_type("int?"), ty(TypeExprKindOptional { inner: ty(TypeExprKindInt {}) }))
}

// port: lib.rs::tests::type_expr_simple_array @ d9be6853b
test "type expr simple array" {
    assert.equal(alias_type("int[]"), ty(TypeExprKindList { inner: ty(TypeExprKindInt {}) }))
}

// port: lib.rs::tests::type_expr_array_optional @ d9be6853b
// int[]? = Optional(List(Int))
test "type expr array optional" {
    assert.equal(
        alias_type("int[]?"),
        ty(TypeExprKindOptional { inner: ty(TypeExprKindList { inner: ty(TypeExprKindInt {}) }) }),
    )
}

// port: lib.rs::tests::type_expr_optional_in_array @ d9be6853b
// string?[] = List(Optional(String))
test "type expr optional in array" {
    assert.equal(
        alias_type("string?[]"),
        ty(TypeExprKindList { inner: ty(TypeExprKindOptional { inner: ty(TypeExprKindString {}) }) }),
    )
}

// port: lib.rs::tests::type_expr_optional_array_optional @ d9be6853b
// string?[]? = Optional(List(Optional(String)))
test "type expr optional array optional" {
    assert.equal(
        alias_type("string?[]?"),
        ty(
            TypeExprKindOptional {
                inner: ty(
                    TypeExprKindList {
                        inner: ty(TypeExprKindOptional { inner: ty(TypeExprKindString {}) }),
                    },
                ),
            },
        ),
    )
}

// port: lib.rs::tests::type_expr_nested_int_array @ d9be6853b
// int[][] = List(List(Int))
test "type expr nested int array" {
    assert.equal(
        alias_type("int[][]"),
        ty(TypeExprKindList { inner: ty(TypeExprKindList { inner: ty(TypeExprKindInt {}) }) }),
    )
}

// port: lib.rs::tests::type_expr_triple_nested_array @ d9be6853b
// int[][][] = List(List(List(Int)))
test "type expr triple nested array" {
    assert.equal(
        alias_type("int[][][]"),
        ty(
            TypeExprKindList {
                inner: ty(TypeExprKindList { inner: ty(TypeExprKindList { inner: ty(TypeExprKindInt {}) }) }),
            },
        ),
    )
}

// The `throws` of the function type that is the first parameter of the
// function type `outer`.
function inner_function_throws(outer: TypeExpr) -> TypeExpr? throws never {
    let params = match (outer.kind) {
        let k: TypeExprKindFunction => k.params,
        _ => baml.sys.panic("expected outer function type"),
    };
    match (params[0].ty.kind) {
        let k: TypeExprKindFunction => k.throws_,
        _ => baml.sys.panic("expected inner function type"),
    }
}

// port: lib.rs::tests::function_type_throws_preserves_omission_vs_explicit_never @ d9be6853b
test "function type throws preserves omission vs explicit never" {
    let omitted = first_type_alias(lower_source("type Omitted = (cb: (value: int) -> string) -> void\n").items);
    let explicit = first_type_alias(lower_source("type Explicit = (cb: (value: int) -> string throws never) -> void\n").items);
    // An omitted nested throws stays null in the raw AST.
    assert.equal(
        inner_function_throws(omitted.type_expr ?? baml.sys.panic("expected type alias body")),
        null,
    );
    // An explicit nested `throws never` is preserved.
    let explicit_throws = inner_function_throws(explicit.type_expr ?? baml.sys.panic("expected type alias body"));
    assert.is_type<TypeExprKindNever>(explicit_throws?.kind);
}

// port: lib.rs::tests::type_expr_paren_union_array @ d9be6853b
// (int | string)[] = List(Union(Int, String))
test "type expr paren union array" {
    assert.equal(
        alias_type("(int | string)[]"),
        ty(
            TypeExprKindList {
                inner: ty(
                    TypeExprKindUnion {
                        variants: [ty(TypeExprKindInt {}), ty(TypeExprKindString {})],
                    },
                ),
            },
        ),
    )
}

// port: lib.rs::tests::type_expr_nested_union_array @ d9be6853b
// (int | bool)[][] = List(List(Union(Int, Bool)))
test "type expr nested union array" {
    let int_or_bool = ty(TypeExprKindUnion { variants: [ty(TypeExprKindInt {}), ty(TypeExprKindBool {})] });
    assert.equal(
        alias_type("(int | bool)[][]"),
        ty(TypeExprKindList { inner: ty(TypeExprKindList { inner: int_or_bool }) }),
    )
}

// port: lib.rs::tests::type_expr_nested_union_array_opt @ d9be6853b
// (int | bool)[][]? = Optional(List(List(Union(Int, Bool))))
test "type expr nested union array opt" {
    let int_or_bool = ty(TypeExprKindUnion { variants: [ty(TypeExprKindInt {}), ty(TypeExprKindBool {})] });
    assert.equal(
        alias_type("(int | bool)[][]?"),
        ty(
            TypeExprKindOptional {
                inner: ty(TypeExprKindList { inner: ty(TypeExprKindList { inner: int_or_bool }) }),
            },
        ),
    )
}

// port: lib.rs::tests::type_expr_opt_union_in_array @ d9be6853b
// (int | bool)?[] = List(Optional(Union(Int, Bool)))
test "type expr opt union in array" {
    let int_or_bool = ty(TypeExprKindUnion { variants: [ty(TypeExprKindInt {}), ty(TypeExprKindBool {})] });
    assert.equal(
        alias_type("(int | bool)?[]"),
        ty(TypeExprKindList { inner: ty(TypeExprKindOptional { inner: int_or_bool }) }),
    )
}

// port: lib.rs::tests::field_attribute_names. The names of the attributes
// on each field, in field order.
function field_attribute_names(fields: FieldDef[]) -> string[][] throws never {
    fields.map((field) -> {
        field.attributes.map((attr) -> {
            attr.name
        })
    })
}

// A bare path type (`type_expr!(Path(name))`).
function path_type(name: string) -> TypeExpr throws never {
    ty(
        TypeExprKindPath {
            path: root.base.Path.new([name]),
            generic_args: [],
            associated_type_bindings: [],
        },
    )
}

// port: lib.rs::tests::class_field_attributes_lower_onto_the_field @ d9be6853b
test "class field attributes lower onto the field" {
    let source = `
        class Foo {
          a Fizz @alias("bar") @stream.done
          b A | B @custom("read-back")
          c string?
            @description("next line")
          d string
        }
    `;
    let class_def = first_class(lower_source(source).items);
    let no_attributes: string[] = [];
    assert.equal(
        field_attribute_names(class_def.fields),
        [["alias", "stream.done"], ["custom"], ["description"], no_attributes],
    );
    assert.equal(
        class_def.fields.map((field) -> {
            field.type_expr
        }),
        [
            path_type("Fizz"),
            ty(TypeExprKindUnion { variants: [path_type("A"), path_type("B")] }),
            ty(TypeExprKindOptional { inner: ty(TypeExprKindString {}) }),
            ty(TypeExprKindString {}),
        ],
    )
}

// port: lib.rs::tests::interface_field_attributes_lower_onto_the_field @ d9be6853b
test "interface field attributes lower onto the field" {
    let source = `
        interface Named {
          name string @alias("label")
        }
    `;
    let interface_def = first_interface(lower_source(source).items);
    assert.equal(field_attribute_names(interface_def.fields), [["alias"]]);
    assert.equal(interface_def.fields[0].type_expr, ty(TypeExprKindString {}))
}
