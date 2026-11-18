// port: baml_compiler2_ast/src/lib.rs::tests @ d9be6853b
//
// The AST lowering tests: parse a source, lower it, assert on the items.
// Split by topic: items here, expression bodies in `lib_body_test.baml`,
// type expressions and field attributes in `lib_type_expr_test.baml`.
//
// deviation: Rust's `strip_spans` is not ported: `TypeExpr` equality already
// ignores spans at every depth, so expected types compare as built.

// Which parse errors a test source may have.
enum ParseErrors {
    // None (Rust's `parse`).
    Forbidden,
    // Any (Rust's `parse_lenient`).
    Allowed,
    // At least one, all `RemovedFeature` (Rust's `lower_removed_syntax`).
    RemovedOnly,
}

class Lowered {
    items: Item[],
    diags: LoweringDiagnostic[],
    errors: root.syntax.ParseError[],
}

// port: lib.rs::tests::parse, parse_lenient, parse_and_lower,
// parse_and_lower_with_diagnostics and lower_removed_syntax, as one function.
// Parse `source`, check its parse errors against `parse_errors`, and lower
// it; the lowering must report nothing unless `allow_diagnostics`.
function lower_source(
    source: string,
    parse_errors: ParseErrors = ParseErrors.Forbidden,
    allow_diagnostics: bool = false,
) -> Lowered throws never {
    let parsed = root.syntax.parse(source);
    match (parse_errors) {
        ParseErrors.Forbidden => {
            assert.equal(
                parsed.errors.map((e) -> {
                    root.syntax.parse_error_message(e)
                }),
                [],
            )
        },
        ParseErrors.Allowed => null,
        ParseErrors.RemovedOnly => {
            assert.is_true(
                parsed.errors.length() > 0
                    && parsed.errors.every((e) -> {
                        e is root.syntax.RemovedFeature
                    }),
            )
        },
    };
    let (let items, let diags, _) = lower_file(parsed.tree, null, null);
    if (!allow_diagnostics) {
        assert.equal(diags, []);
    }
    Lowered { items: items, diags: diags, errors: parsed.errors }
}

// port: lib.rs::tests::first_function. The first function item, or the
// first one called `name`.
function first_function(items: Item[], name: string? = null) -> FunctionDef throws never {
    let found = items.filter_map((item) -> {
        match (item) {
            let i: ItemFunction if name == null || i.value.name == name => i.value,
            _ => null,
        }
    });
    found.at(0) ?? baml.sys.panic("expected a FunctionDef")
}

// The first class item, or the first one called `name`.
function first_class(items: Item[], name: string? = null) -> ClassDef throws never {
    let found = items.filter_map((item) -> {
        match (item) {
            let i: ItemClass if name == null || i.value.name == name => i.value,
            _ => null,
        }
    });
    found.at(0) ?? baml.sys.panic("expected a ClassDef")
}

// The first interface item, or the first one called `name`.
function first_interface(items: Item[], name: string? = null) -> InterfaceDef throws never {
    let found = items.filter_map((item) -> {
        match (item) {
            let i: ItemInterface if name == null || i.value.name == name => i.value,
            _ => null,
        }
    });
    found.at(0) ?? baml.sys.panic("expected an InterfaceDef")
}

// The first `implements … for` item.
function first_implements(items: Item[]) -> ImplementsForDef throws never {
    let found = items.filter_map((item) -> {
        match (item) {
            let i: ItemImplementsFor => i.value,
            _ => null,
        }
    });
    found.at(0) ?? baml.sys.panic("expected an ImplementsFor item")
}

// port: lib.rs::tests::first_type_alias
function first_type_alias(items: Item[]) -> TypeAliasDef throws never {
    let found = items.filter_map((item) -> {
        match (item) {
            let i: ItemTypeAlias => i.value,
            _ => null,
        }
    });
    found.at(0) ?? baml.sys.panic("expected a TypeAliasDef")
}

// A function's expression body and its source map (Rust's
// `let Some(FunctionBodyDef::Expr(body, sm)) = &f.body else { panic!() }`).
function expr_body(f: FunctionDef) -> FunctionBodyDefExpr throws never {
    match (f.body) {
        let b: FunctionBodyDefExpr => b,
        _ => baml.sys.panic("expected expression body"),
    }
}

// The block at a body's root (Rust's `let Expr::Block { .. } = &body.exprs[root]`).
function root_block(body: ExprBody) -> ExprBlock throws never {
    let root_id = body.root_expr ?? baml.sys.panic("expected body root expression");
    match (body.exprs[root_id]) {
        let b: ExprBlock => b,
        _ => baml.sys.panic("expected block root expression"),
    }
}

// The segments of a path expression; null for any other expression.
function path_segments(expr: Expr) -> string[]? throws never {
    match (expr) {
        let p: ExprPath => p.value.segments,
        _ => null,
    }
}

// port: lib.rs::tests::rendered_generic_params. Generic parameters rendered
// back to source form (`T extends A & B`).
function rendered_generic_params(params: GenericParam[]) -> string[] throws never {
    params.map((param) -> {
        if (param.bounds.length() == 0) {
            return param.name;
        }
        let bounds = param.bounds.map((bound) -> {
            bound.to_string()
        });
        `${param.name} extends ${bounds.join(" & ")}`
    })
}

// A `baml.errors.Io` path type, as `throws baml.errors.Io` lowers.
function io_error_kind() -> TypeExprKind throws never {
    TypeExprKindPath {
        path: root.base.Path.new(["baml", "errors", "Io"]),
        generic_args: [],
        associated_type_bindings: [],
    }
}

// port: lib.rs::tests::unescape_string_literal_decodes_supported_escapes @ d9be6853b
test "unescape string literal decodes supported escapes" {
    assert.equal(root.base.unescape_string_literal("line\\nbreak"), "line\nbreak");
    assert.equal(root.base.unescape_string_literal("tab\\there"), "tab\there");
    assert.equal(root.base.unescape_string_literal("cr\\rhere"), "cr\rhere");
    assert.equal(root.base.unescape_string_literal("nul\\0here"), "nul\0here");
    assert.equal(root.base.unescape_string_literal("back\\\\slash"), "back\\slash");
    assert.equal(root.base.unescape_string_literal("a\\\"b"), "a\"b")
}

// port: lib.rs::tests::unescape_string_literal_decodes_code_point_escapes @ d9be6853b
test "unescape string literal decodes code point escapes" {
    assert.equal(root.base.unescape_string_literal("\\x41"), "A");
    assert.equal(root.base.unescape_string_literal("\\u0041\\u{42}"), "AB")
}

// port: lib.rs::tests::unescape_string_literal_preserves_unknown_sequences @ d9be6853b
test "unescape string literal preserves unknown sequences" {
    assert.equal(root.base.unescape_string_literal("\\d+"), "\\d+")
}

// port: lib.rs::tests::unescape_string_literal_preserves_trailing_backslash @ d9be6853b
test "unescape string literal preserves trailing backslash" {
    assert.equal(root.base.unescape_string_literal("trailing\\"), "trailing\\")
}

// port: lib.rs::tests::unescape_string_literal_handles_empty_and_plain_text @ d9be6853b
test "unescape string literal handles empty and plain text" {
    assert.equal(root.base.unescape_string_literal(""), "");
    assert.equal(root.base.unescape_string_literal("plain text"), "plain text")
}

// port: lib.rs::tests::removed_type_statement_binds_nothing @ d9be6853b
// The parser reports the removed statement (E0098) and lowering leaves it a
// `StmtMissing`: `T` is not bound.
test "removed type statement binds nothing" {
    let sources = [
        "function main(t: reflect.Type) -> reflect.Type { type T = unreflect(t); return reflect.Type.of<T>() }",
        "function main() -> int { type T = int[]; 0 }",
    ];
    for (let source in sources) {
        let lowered = lower_source(source, parse_errors = ParseErrors.RemovedOnly);
        let body = expr_body(first_function(lowered.items)).v0;
        assert.is_true(
            !body.stmts.some((stmt) -> {
                stmt is StmtTypeBinding
            }),
        );
        assert.is_true(
            body.stmts.some((stmt) -> {
                stmt is StmtMissing
            }),
        );
    }
}

// port: lib.rs::tests::removed_unreflect_lowers_to_the_error_type_without_a_second_diagnostic @ d9be6853b
// The parser reports every `unreflect` (E0098); lowering only turns each
// position into the error sentinel.
test "removed unreflect lowers to the error type without a second diagnostic" {
    let source = "function main(t: reflect.Type, v: int) -> int {\n  let a = identity<unreflect(t)>(v)\n  let b: unreflect(t)? = null\n  let c = v is unreflect(t)\n  0\n}";
    lower_source(source, parse_errors = ParseErrors.RemovedOnly);
}

// port: lib.rs::tests::llm_function_user_client_param_is_reserved @ d9be6853b
test "llm function user client param is reserved" {
    let source = "\nfunction Extract(client: string, text: string) -> string {\n  client: \"openai/gpt-4o\"\n  prompt: `${text} ${ctx.output_format()}`\n}\n";
    let lowered = lower_source(source, allow_diagnostics = true);
    assert.is_true(
        lowered.diags.some((diag) -> {
            match (diag) {
                let d: LoweringDiagnosticReservedLlmParam => {
                    d.function_name == "Extract" && d.param_name == "client"
                },
                _ => false,
            }
        }),
    );
    let f = first_function(lowered.items, name = "Extract");
    assert.equal(
        f.params.map((p) -> {
            p.name
        }),
        ["text", "client", "on_event"],
    );
    for (let injected in [f.params[1], f.params[2]]) {
        let default_id = injected.default ?? baml.sys.panic(`expected ${injected.name} default`);
        // The injected override defaults to null.
        assert.is_type<ExprNull>(f.defaults.expr(default_id));
    }
}

// port: lib.rs::tests::client_block_is_a_migration_error @ d9be6853b
test "client block is a migration error" {
    let source = `
        client<llm> C {
          provider openai
          options { model "gpt-4o" }
        }
    `;
    let lowered = lower_source(source, allow_diagnostics = true);
    assert.equal(lowered.items.length(), 0);
    assert.is_true(
        lowered.diags.some((diag) -> {
            match (diag) {
                let d: LoweringDiagnosticClientBlockRemoved => d.name == "C",
                _ => false,
            }
        }),
    )
}

// port: lib.rs::tests::client_value_decl_lowers_to_client_let @ d9be6853b
test "client value decl lowers to client let" {
    let items = lower_source("\nclient Fast = openai.ResponsesClient.new(model = \"gpt-4o-mini\");\n").items;
    assert.equal(items.length(), 1);
    let let_def = match (items[0]) {
        let i: ItemLet => i.value,
        _ => baml.sys.panic("expected Item::Let"),
    };
    assert.equal(let_def.name, "Fast");
    assert.equal(let_def.origin, LetOrigin.Client);
    let initializer = let_def.initializer ?? baml.sys.panic("expected initializer");
    let body = initializer.0;
    let root_id = body.root_expr ?? baml.sys.panic("expected root expr");
    // The initializer is the user's constructor call.
    assert.is_type<ExprCall>(body.exprs[root_id]);
}

// port: lib.rs::tests::ast_function_def_has_generic_params @ d9be6853b
test "ast function def has generic params" {
    let source = `
        function deep_copy<T>(value: T) -> T {
          $rust_function
        }
    `;
    let f = first_function(lower_source(source).items);
    assert.equal(f.generic_params.length(), 1);
    assert.equal(f.generic_params[0].name, "T")
}

// port: lib.rs::tests::ast_preserves_parameter_defaults_and_call_labels @ d9be6853b
test "ast preserves parameter defaults and call labels" {
    let source = `
        function Search(query: string, max_results: int = 10) -> int {
          Search(query = "cats", max_results = 5)
        }
    `;
    let f = first_function(lower_source(source).items);
    assert.equal(f.params[0].default, null);
    let default_id = f.params[1].default ?? baml.sys.panic("expected default expression id");
    assert.is_type<ExprLiteral>(f.defaults.expr(default_id));
    let body = expr_body(f).v0;
    let tail = root_block(body).tail_expr ?? baml.sys.panic("expected block root");
    let call = match (body.exprs[tail]) {
        let e: ExprCall => e,
        _ => baml.sys.panic("expected call tail expression"),
    };
    assert.equal(call.args[0].label, "query");
    assert.equal(call.args[1].label, "max_results")
}

// port: lib.rs::tests::ast_preserves_out_of_body_implements_for_external_class_target @ d9be6853b
test "ast preserves out of body implements for external class target" {
    let source = `
        interface ToJson {
          function to_json(self) -> string
        }

        implements ToJson for Dog {
          function to_json(self) -> string {
            return "dog"
          }
        }
    `;
    let imp = first_implements(lower_source(source).items);
    assert.equal(imp.interface_target.to_string(), "ToJson");
    assert.equal(imp.for_target.to_string(), "Dog")
}

// port: lib.rs::tests::ast_does_not_merge_qualified_out_of_body_implements_into_local_class @ d9be6853b
test "ast does not merge qualified out of body implements into local class" {
    let source = `
        interface ToJson {
          function to_json(self) -> string
        }

        class Dog {
          name string
        }

        implements ToJson for other.Dog {
          function to_json(self) -> string {
            return "dog"
          }
        }
    `;
    let items = lower_source(source).items;
    let class_def = first_class(items, name = "Dog");
    let imp = first_implements(items);
    assert.equal(imp.for_target.to_string(), "other.Dog");
    // A qualified target is not an implementation for the local class.
    assert.is_true(!imp.is_for_class(class_def))
}

// port: lib.rs::tests::ast_does_not_merge_generic_out_of_body_implements_into_local_class @ d9be6853b
test "ast does not merge generic out of body implements into local class" {
    let source = `
        interface ToJson {
          function to_json(self) -> string
        }

        class Dog<T> {
          value T
        }

        implements ToJson for Dog<int> {
          function to_json(self) -> string {
            return "dog"
          }
        }
    `;
    let items = lower_source(source).items;
    let class_def = first_class(items, name = "Dog");
    let imp = first_implements(items);
    assert.equal(imp.for_target.to_string(), "Dog<int>");
    // `Dog<int>` is not an implementation for the generic class `Dog<T>`.
    assert.is_true(!imp.is_for_class(class_def))
}

// port: lib.rs::tests::ast_preserves_interface_generic_param_bounds @ d9be6853b
test "ast preserves interface generic param bounds" {
    let source = `
        interface Named {
          name string
        }

        interface Box<T extends Named, E> {
          value T
        }
    `;
    let interface_def = first_interface(lower_source(source).items, name = "Box");
    assert.equal(rendered_generic_params(interface_def.generic_params), ["T extends Named", "E"])
}

// port: lib.rs::tests::ast_preserves_every_bound_in_a_generic_param_intersection @ d9be6853b
// `T extends A & B` is a conjunction: every bound must survive lowering.
test "ast preserves every bound in a generic param intersection" {
    let source = `
        interface Named {
          name string
        }

        interface Sized {
          size int
        }

        interface Box<T extends Named & Sized, E> {
          value T
        }

        function pack<U extends Named & Sized>(value: U) -> U {
          value
        }
    `;
    let items = lower_source(source).items;
    let interface_def = first_interface(items, name = "Box");
    assert.equal(
        rendered_generic_params(interface_def.generic_params),
        ["T extends Named & Sized", "E"],
    );
    let f = first_function(items, name = "pack");
    assert.equal(rendered_generic_params(f.generic_params), ["U extends Named & Sized"])
}

// port: lib.rs::tests::ast_preserves_required_interface_method_generic_param_bounds @ d9be6853b
test "ast preserves required interface method generic param bounds" {
    let source = `
        interface Named {
          name string
        }

        interface Mapper {
          function map<T extends Named, E>(self, value: T, extra: E) -> T
        }
    `;
    let interface_def = first_interface(lower_source(source).items, name = "Mapper");
    let method = interface_def.required_methods.at(0) ?? baml.sys.panic("expected required method");
    assert.equal(rendered_generic_params(method.generic_params), ["T extends Named", "E"])
}

// port: lib.rs::tests::ast_default_indices_survive_recovered_parameter @ d9be6853b
test "ast default indices survive recovered parameter" {
    let source = `
        function Broken(: int = 1, value: int = 2) -> int {
          value
        }
    `;
    let lowered = lower_source(source, parse_errors = ParseErrors.Allowed, allow_diagnostics = true);
    let f = first_function(lowered.items);
    assert.equal(f.params.length(), 1);
    assert.equal(f.params[0].name, "value");
    let default_id = f.params[0].default ?? baml.sys.panic("expected valid param default to survive recovery");
    assert.is_type<ExprLiteral>(f.defaults.expr(default_id));
}

// port: lib.rs::tests::constructorless_recovered_object_lowers_to_missing @ d9be6853b
test "constructorless recovered object lowers to missing" {
    let source = `
        function Broken() -> int {
          (1)<int> { x: 2 }
        }
    `;
    let lowered = lower_source(source, parse_errors = ParseErrors.Allowed, allow_diagnostics = true);
    let body = expr_body(first_function(lowered.items)).v0;
    // Constructor-less recovery lowers to `ExprMissing`...
    assert.is_true(
        body.exprs.some((expr) -> {
            expr is ExprMissing
        }),
    );
    // ...and stays visible as a lowering diagnostic.
    assert.is_true(
        lowered.diags.some((diag) -> {
            diag is LoweringDiagnosticMissingObjectConstructor
        }),
    )
}

// port: lib.rs::tests::removed_hash_string_does_not_lower_to_a_string_literal @ d9be6853b
test "removed hash string does not lower to a string literal" {
    let source = "\nfunction legacy() -> string {\n  #\"value\"#\n}\n";
    let lowered = lower_source(source, parse_errors = ParseErrors.Allowed, allow_diagnostics = true);
    // Removed hash strings must fail parsing.
    assert.is_true(lowered.errors.length() > 0);
    let body = expr_body(first_function(lowered.items)).v0;
    assert.is_true(
        body.exprs.some((expr) -> {
            expr is ExprMissing
        }),
    );
    // They never become semantic string literals.
    assert.is_true(
        !body.exprs.some((expr) -> {
            expr == ExprLiteral { value: root.base.LiteralString { value: "value" } }
        }),
    )
}

// port: lib.rs::tests::ast_default_indices_skip_missing_name_slots @ d9be6853b
test "ast default indices skip missing name slots" {
    let source = `
        function Broken(: int, b: string = "x") -> string {
          b
        }
    `;
    let lowered = lower_source(source, parse_errors = ParseErrors.Allowed, allow_diagnostics = true);
    // The parser reports the recovered missing name.
    assert.is_true(lowered.errors.length() > 0);
    let f = first_function(lowered.items);
    // The missing-name slot is filtered out, and only b's default is lowered.
    assert.equal(f.params.length(), 1);
    assert.equal(f.params[0].name, "b");
    assert.equal(f.defaults.exprs.exprs.length(), 1);
    let default_id = f.params[0].default ?? baml.sys.panic("expected b's default to use the lowered params index");
    assert.equal(
        f.defaults.expr(default_id),
        ExprLiteral { value: root.base.LiteralString { value: "x" } },
    )
}

// port: lib.rs::tests::a_block_attribute_in_a_class_body_is_the_class_s @ d9be6853b
// A `@@` attribute is written inside the body of the declaration it
// describes, wherever among the members it sits; a method takes none.
test "a block attribute in a class body is the class s" {
    let source = `
        class Response {
          @@internal.uses(engine_ctx)
          function text(self) -> string throws baml.errors.Io {
            $rust_io_function
          }
        }
    `;
    let class_def = first_class(lower_source(source).items);
    assert.equal(class_def.attributes.length(), 1);
    assert.equal(class_def.attributes[0].name, "internal.uses");
    assert.equal(class_def.attributes[0].args.length(), 1);
    assert.equal(class_def.attributes[0].args[0].value, "engine_ctx");
    let method = class_def.methods.at(0) ?? baml.sys.panic("expected method");
    assert.equal(method.attributes.length(), 0);
    let throws_ = method.throws_ ?? baml.sys.panic("expected throws contract");
    assert.equal(throws_.kind, io_error_kind())
}

// port: lib.rs::tests::ast_lowers_keyword_named_class_field @ d9be6853b
test "ast lowers keyword named class field" {
    let source = `
        class InterfaceTwo {
          interface string
        }
    `;
    let class_def = first_class(lower_source(source).items);
    let field = class_def.fields.at(0) ?? baml.sys.panic("expected field");
    assert.equal(field.name, "interface");
    assert.equal(field.type_expr.to_string(), "string")
}

// port: lib.rs::tests::ast_lowers_keyword_named_class_method_and_member_call @ d9be6853b
test "ast lowers keyword named class method and member call" {
    let source = `
        class TypeValue {
          function implements(self) -> string {
            "ok"
          }
        }

        function Foo(t: TypeValue) -> string {
          t.implements()
        }
    `;
    let items = lower_source(source).items;
    let class_def = first_class(items);
    assert.is_true(class_def.methods.length() > 0);
    assert.equal(class_def.methods[0].name, "implements");
    let body = expr_body(first_function(items)).v0;
    let tail = root_block(body).tail_expr ?? baml.sys.panic("expected tail expression");
    let call = match (body.exprs[tail]) {
        let e: ExprCall => e,
        _ => baml.sys.panic("expected call expression"),
    };
    let member = match (body.exprs[call.callee]) {
        let e: ExprMemberAccess => e.member,
        _ => baml.sys.panic("expected member access callee"),
    };
    assert.equal(member, "implements")
}

// port: lib.rs::tests::ast_lowers_required_interface_method_throws @ d9be6853b
test "ast lowers required interface method throws" {
    let source = `
        interface Response {
          function text(self) -> string throws baml.errors.Io
        }
    `;
    let interface_def = first_interface(lower_source(source).items);
    let method = interface_def.required_methods.at(0) ?? baml.sys.panic("expected required method");
    let throws_ = method.throws_ ?? baml.sys.panic("expected throws contract");
    assert.equal(throws_.kind, io_error_kind())
}

// port: lib.rs::tests::ast_class_def_has_one_generic_param @ d9be6853b
test "ast class def has one generic param" {
    let source = `
        class Array<T> {
          function at(self, index: int) -> T {
            $rust_function
          }
        }
    `;
    let class_def = first_class(lower_source(source).items);
    assert.equal(class_def.generic_params.length(), 1);
    assert.equal(class_def.generic_params[0].name, "T")
}

// port: lib.rs::tests::ast_class_def_has_two_generic_params @ d9be6853b
test "ast class def has two generic params" {
    let source = `
        class Map<K, V> {
          function has(self, key: K) -> bool {
            $rust_function
          }
        }
    `;
    let class_def = first_class(lower_source(source).items);
    assert.equal(class_def.generic_params.length(), 2);
    assert.equal(class_def.generic_params[0].name, "K");
    assert.equal(class_def.generic_params[1].name, "V")
}

// port: lib.rs::tests::ast_class_def_has_empty_generic_params_for_non_generic_class @ d9be6853b
test "ast class def has empty generic params for non generic class" {
    let source = `
        class User {
          name string
        }
    `;
    let class_def = first_class(lower_source(source).items);
    assert.equal(class_def.generic_params.length(), 0)
}

// port: lib.rs::tests::function_body_rust_function_produces_builtin_vm @ d9be6853b
test "function body rust function produces builtin vm" {
    let source = `
        class Array<T> {
          function at(self, index: int) -> T {
            $rust_function
          }
        }
    `;
    let class_def = first_class(lower_source(source).items);
    let method = class_def.methods.at(0) ?? baml.sys.panic("expected a method");
    assert.equal(method.body, FunctionBodyDefBuiltin { value: BuiltinKind.Vm })
}

// port: lib.rs::tests::function_body_rust_io_function_produces_builtin_io @ d9be6853b
test "function body rust io function produces builtin io" {
    let source = `
        function get(key: string) -> string? {
          $rust_io_function
        }
    `;
    let f = first_function(lower_source(source).items);
    assert.equal(f.body, FunctionBodyDefBuiltin { value: BuiltinKind.Io })
}

// port: lib.rs::tests::regular_expr_body_is_not_builtin @ d9be6853b
test "regular expr body is not builtin" {
    let source = `
        function add(a: int, b: int) -> int {
          a + b
        }
    `;
    let f = first_function(lower_source(source).items);
    assert.is_type<FunctionBodyDefExpr>(f.body);
}

// port: lib.rs::tests::field_with_rust_type_produces_type_expr_rust @ d9be6853b
test "field with rust type produces type expr rust" {
    let source = `
        class Media {
          _data $rust_type
        }
    `;
    let class_def = first_class(lower_source(source).items);
    let field = class_def.fields.find((f) -> {
        f.name == "_data"
    })
        ?? baml.sys.panic("expected _data field");
    assert.is_type<TypeExprKindRust>(field.type_expr.kind);
}

// port: lib.rs::tests::roundtrip_no_panic_on_array_stub @ d9be6853b
test "roundtrip no panic on array stub" {
    let source = `
        class Array<T> {
          function length(self) -> int {
            $rust_function
          }

          function at(self, index: int) -> T {
            $rust_function
          }

          function push(self, item: T) -> int {
            $rust_function
          }

          function concat(self, other: T[]) -> T[] {
            $rust_function
          }
        }
    `;
    let items = lower_source(source).items;
    assert.equal(items.length(), 1);
    let c = match (items[0]) {
        let i: ItemClass => i.value,
        _ => baml.sys.panic("expected Item::Class"),
    };
    assert.equal(c.name, "Array");
    assert.equal(c.generic_params.length(), 1);
    assert.equal(c.generic_params[0].name, "T");
    // 4 user-defined stubs + 2 auto-derived (`to_json`, `from_json`).
    let stub_methods = c.methods.filter((m) -> {
        m.metadata.origin != FunctionOrigin.AutoDerive
    });
    assert.equal(stub_methods.length(), 4);
    for (let method in stub_methods) {
        assert.equal(method.body, FunctionBodyDefBuiltin { value: BuiltinKind.Vm });
    }
}

// port: lib.rs::tests::roundtrip_no_panic_on_map_stub @ d9be6853b
test "roundtrip no panic on map stub" {
    let source = `
        class Map<K, V> {
          function length(self) -> int {
            $rust_function
          }

          function has(self, key: K) -> bool {
            $rust_function
          }

          function keys(self) -> K[] {
            $rust_function
          }

          function values(self) -> V[] {
            $rust_function
          }
        }
    `;
    let items = lower_source(source).items;
    assert.equal(items.length(), 1);
    let c = match (items[0]) {
        let i: ItemClass => i.value,
        _ => baml.sys.panic("expected Item::Class"),
    };
    assert.equal(c.name, "Map");
    assert.equal(c.generic_params.length(), 2)
}

// port: lib.rs::tests::roundtrip_no_panic_on_media_stub_with_rust_type @ d9be6853b
test "roundtrip no panic on media stub with rust type" {
    let source = `
        class Media {
          _data $rust_type

          function url(self) -> string {
            $rust_function
          }

          function base64(self) -> string {
            $rust_function
          }
        }
    `;
    let items = lower_source(source).items;
    assert.equal(items.length(), 1);
    let c = match (items[0]) {
        let i: ItemClass => i.value,
        _ => baml.sys.panic("expected Item::Class"),
    };
    assert.equal(c.name, "Media");
    assert.equal(c.generic_params.length(), 0);
    let data_field = c.fields.find((f) -> {
        f.name == "_data"
    })
        ?? baml.sys.panic("expected _data field");
    assert.is_type<TypeExprKindRust>(data_field.type_expr.kind);
}

// port: lib.rs::tests::function_throws_clause_lowers_to_never_type @ d9be6853b
test "function throws clause lowers to never type" {
    let source = `
        function f() -> int throws never {
          return 1
        }
    `;
    let f = first_function(lower_source(source).items);
    let throws_ = f.throws_ ?? baml.sys.panic("expected throws clause to be lowered into FunctionDef.throws");
    assert.is_type<TypeExprKindNever>(throws_.kind);
}

// port: lib.rs::tests::retry_policy_block_lowers_to_a_removal_diagnostic @ d9be6853b
// `retry_policy` blocks are removed; retry composes at the client boundary
// (ai.Retry).
test "retry policy block lowers to a removal diagnostic" {
    let source = `
        retry_policy MyRetry {
          max_retries 3
        }
    `;
    let lowered = lower_source(source, allow_diagnostics = true);
    assert.equal(lowered.items.length(), 0);
    assert.is_true(
        lowered.diags.some((diag) -> {
            match (diag) {
                let d: LoweringDiagnosticRetryPolicyRemoved => d.name == "MyRetry",
                _ => false,
            }
        }),
    )
}

// port: lib.rs::tests::escape_diagnostic_spans. The source text each
// `InvalidStringEscape` parse error points at.
function escape_diagnostic_spans(source: string) -> string[] throws never {
    let parsed = root.syntax.parse(source);
    parsed.errors.map((error) -> {
        match (error) {
            let e: root.syntax.InvalidStringEscape => parsed.tree.slice(e.range),
            _ => baml.sys.panic(`unexpected parse error: ${root.syntax.parse_error_message(error)}`),
        }
    })
}

// port: lib.rs::tests::invalid_escapes_are_reported_once_per_sequence_in_every_literal_kind @ d9be6853b
test "invalid escapes are reported once per sequence in every literal kind" {
    let source = "\ntype Choice = \"\\q\" | \"ok\"\n\nfunction main() -> string {\n  let a = \"\\d+\\x41\\xE9\";\n  let b = b\"\\xFF\\u{E9}é\";\n  let c = `\\v ${\"\\e\"} \\uD83D\\uDE00 \\U0001F600`;\n  let d = r\"\\d \\v\";\n  a\n}\n";
    assert.equal(
        escape_diagnostic_spans(source),
        ["\\q", "\\d", "\\xE9", "\\u{E9}", "é", "\\v", "\\e", "\\U0001F600"],
    )
}

// port: lib.rs::tests::raw_string_hint_only_where_raw_strings_parse @ d9be6853b
test "raw string hint only where raw strings parse" {
    let source = "\nclass C {\n  a string @description(\"\\d\")\n}\n\ntype T = \"\\d\" | \"ok\"\n\nfunction main() -> string {\n  \"\\d\"\n}\n";
    let hints = root.syntax.parse(source).errors.map((error) -> {
        match (error) {
            let e: root.syntax.InvalidStringEscape => {
                root.base.escape_issue_message(e.issue).includes("raw string")
            },
            _ => baml.sys.panic(`unexpected parse error: ${root.syntax.parse_error_message(error)}`),
        }
    });
    assert.equal(hints, [false, false, true])
}
