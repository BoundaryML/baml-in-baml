// port: baml_compiler2_ast/src/lib.rs::tests @ d9be6853b
//
// Expression-body lowering tests; the helpers are in `lib_test.baml`.

// port: lib.rs::tests::only_type_binding. The body's one `let type` binding.
function only_type_binding(body: ExprBody) -> StmtTypeBinding throws never {
    let bindings = body.stmts.filter_map((stmt) -> {
        match (stmt) {
            let s: StmtTypeBinding => s,
            _ => null,
        }
    });
    assert.equal(bindings.length(), 1);
    bindings[0]
}

// The expression a body's root block ends with.
function root_tail(body: ExprBody) -> int throws never {
    root_block(body).tail_expr ?? baml.sys.panic("expected tail expression")
}

// The value of a body's first statement, which must be `return <expr>`.
function first_return_value(body: ExprBody) -> int throws never {
    match (body.stmts[root_block(body).stmts[0]]) {
        StmtReturn { value: let v: int } => v,
        _ => baml.sys.panic("expected return statement"),
    }
}

// port: lib.rs::tests::let_type_lowers_its_operand_bounds_and_else_block @ d9be6853b
test "let type lowers its operand bounds and else block" {
    let f = first_function(
        lower_source(
            "function main(t: reflect.Type) -> int { let type T extends A & B = t else { return 0 }; 1 }",
        ).items,
    );
    let body = expr_body(f).v0;
    let binding = only_type_binding(body);
    assert.equal(binding.name, "T");
    assert.equal(path_segments(body.exprs[binding.operand]), ["t"]);
    let bounds = binding.bounds.map((bound) -> {
        match (bound.kind) {
            let k: TypeExprKindPath => k.path.to_string(),
            _ => baml.sys.panic("unexpected bound"),
        }
    });
    assert.equal(bounds, ["A", "B"]);
    let else_branch = binding.else_branch;
    assert.is_true(else_branch != null && body.exprs[else_branch] is ExprBlock)
}

// port: lib.rs::tests::ast_tagged_template_body_marked_synthetic @ d9be6853b
// The desugared closure body of a tagged template is compiler-generated, so
// every node it allocates is in the source map's synthetic sets, while the
// user-written tag and `${…}` interpolations stay non-synthetic.
test "ast tagged template body marked synthetic" {
    let source = "\nfunction Demo(items: string[]) -> string {\n  sql`a ${1} ${for (let x in items)}${x},${endfor}`\n}\n";
    let lowered_body = expr_body(first_function(lower_source(source).items));
    let body = lowered_body.v0;
    let source_map = lowered_body.v1;
    let template = match (body.exprs[root_tail(body)]) {
        let e: ExprTemplate => e,
        _ => baml.sys.panic("expected Custom Template tail"),
    };
    let tag = match (template.tag) {
        let t: TemplateTagCustom => t,
        _ => baml.sys.panic("expected Custom Template tail"),
    };
    // The elaborated closure body block and all of its statements are synthetic.
    assert.is_true(source_map.is_synthetic_expr(tag.body));
    let stmts = match (body.exprs[tag.body]) {
        let b: ExprBlock => b.stmts,
        _ => baml.sys.panic("tagged body should be a block"),
    };
    assert.is_true(
        stmts.length() > 0
            && stmts.every((s) -> {
                source_map.is_synthetic_stmt(s)
            }),
    );
    // The tag expr and the user's `${…}` interpolation stay non-synthetic.
    assert.is_true(!source_map.is_synthetic_expr(tag.tag));
    let interp = template.segments
        .filter_map((s) -> {
            match (s) {
                let i: TemplateSegmentInterp => i.value,
                _ => null,
            }
        })
        .at(0)
        ?? baml.sys.panic("expected a top-level interp segment");
    assert.is_true(!source_map.is_synthetic_expr(interp))
}

// port: lib.rs::tests::ast_tagged_template_lowers_to_template_expr @ d9be6853b
// BEP-049 §10. A tagged template lowers to an `ExprTemplate` with
// `TemplateTagCustom`, keeping the segment structure (text / interp / for /
// if). The tag lowers as an ordinary expression (here the bare path `sql`).
test "ast tagged template lowers to template expr" {
    let source = "\nfunction Demo(items: string[]) -> string {\n  sql`a ${1} ${for (let x in items)}${x},${endfor}${if (true)}w${else}e${endif}`\n}\n";
    let body = expr_body(first_function(lower_source(source).items)).v0;
    let template = match (body.exprs[root_tail(body)]) {
        let e: ExprTemplate => e,
        _ => baml.sys.panic("expected Template tail"),
    };
    let tag = match (template.tag) {
        let t: TemplateTagCustom => t.tag,
        _ => baml.sys.panic("expected Custom tag"),
    };
    assert.equal(path_segments(body.exprs[tag]), ["sql"]);
    let segments = template.segments;
    // A leading Text, an Interp, a For block and an If chain.
    assert.is_type<TemplateSegmentText>(segments.at(0));
    assert.is_true(
        segments.some((s) -> {
            s is TemplateSegmentInterp
        }),
    );
    let for_body = segments
        .filter_map((s) -> {
            match (s) {
                let f: TemplateSegmentFor => f.body,
                _ => null,
            }
        })
        .at(0)
        ?? baml.sys.panic("expected a For segment");
    // The for body contains the `${x}` interpolation.
    assert.is_true(
        for_body.some((s) -> {
            s is TemplateSegmentInterp
        }),
    );
    let if_segment = segments
        .filter_map((s) -> {
            match (s) {
                let i: TemplateSegmentIf => i,
                _ => null,
            }
        })
        .at(0)
        ?? baml.sys.panic("expected an If segment");
    assert.equal(if_segment.branches.length(), 1);
    // The then-branch contains text, and the if carries an else body.
    assert.is_true(
        if_segment.branches[0].body.some((s) -> {
            s is TemplateSegmentText
        }),
    );
    assert.not_null(if_segment.else_body)
}

// port: lib.rs::tests::ast_does_not_treat_upcast_target_as_method_type_args @ d9be6853b
test "ast does not treat upcast target as method type args" {
    let source = `
        function main(m: MultiFormat) -> string {
          return m.as<Converter<int>>.convert()
        }
    `;
    let body = expr_body(first_function(lower_source(source).items)).v0;
    let call = match (body.exprs[first_return_value(body)]) {
        let e: ExprCall => e,
        _ => baml.sys.panic("expected return expression to be a call"),
    };
    // The `.as<Interface>` target is not lowered as method type args.
    assert.equal(call.type_args.length(), 0);
    let access = match (body.exprs[call.callee]) {
        let e: ExprMemberAccess => e,
        _ => baml.sys.panic("expected call callee to be member access"),
    };
    assert.equal(access.member, "convert");
    let upcast = match (body.exprs[access.base]) {
        let e: ExprUpcast => e,
        _ => baml.sys.panic("expected member receiver to be an upcast expression"),
    };
    // The upcast target itself is preserved.
    assert.equal(upcast.target.to_string(), "Converter<int>")
}

// port: lib.rs::tests::throw_statement_and_expression_are_lowered @ d9be6853b
test "throw statement and expression are lowered" {
    let source = `
        function f() -> int {
          throw "boom"
        }

        function g() -> int {
          return throw 1
        }
    `;
    let items = lower_source(source).items;
    let f_body = expr_body(first_function(items, name = "f")).v0;
    let first_stmt = f_body.stmts[root_block(f_body).stmts[0]];
    assert.is_type<StmtThrow>(first_stmt);
    let g_body = expr_body(first_function(items, name = "g")).v0;
    assert.is_type<ExprThrow>(g_body.exprs[first_return_value(g_body)]);
}

// port: lib.rs::tests::throw_call_catch_binds_catch_to_payload_expression @ d9be6853b
test "throw call catch binds catch to payload expression" {
    let source = `
        function make_err() -> int {
          return 1
        }

        function f() -> int {
          return throw make_err() catch (e) {
            _ => 0
          }
        }
    `;
    let lowered_body = expr_body(first_function(lower_source(source).items, name = "f"));
    let body = lowered_body.v0;
    let caught = match (body.exprs[first_return_value(body)]) {
        let e: ExprCatch => e,
        _ => baml.sys.panic("expected return expression to be Expr::Catch"),
    };
    let thrown_value = match (body.exprs[caught.base]) {
        let e: ExprThrow => e.value,
        _ => baml.sys.panic("expected catch base to be Expr::Throw"),
    };
    assert.is_type<ExprCall>(body.exprs[thrown_value]);
    let arm_span = lowered_body.v1.catch_arm_span(caught.clause.arms[0]);
    // The catch arm has a non-empty span in the source map.
    assert.is_true(arm_span.start != arm_span.end)
}

// The tail of a body's root block, or the value of its first statement when
// the block has no tail, as a string literal (Rust's
// `extract_first_string_literal`, below).
// port: lib.rs::tests::extract_first_string_literal
function extract_first_string_literal(items: Item[]) -> string throws never {
    let body = expr_body(first_function(items)).v0;
    let root_id = body.root_expr ?? baml.sys.panic("expected root expr");
    // The body is a block; take its tail or its first statement's value.
    let candidate = match (body.exprs[root_id]) {
        ExprBlock { tail_expr: let tail: int } => tail,
        let block: ExprBlock => match (body.stmts[block.stmts[0]]) {
            let s: StmtExpr => s.value,
            StmtLet { initializer: let init: int } => init,
            _ => baml.sys.panic("unexpected stmt"),
        },
        _ => root_id,
    };
    // An untagged backtick lowers to `ExprTemplate`; its desugared realization
    // (a string literal, for pure-text templates) is `TemplateTagDefault`'s.
    let realized = match (body.exprs[candidate]) {
        ExprTemplate { tag: TemplateTagDefault { elaborated: let elaborated } } => elaborated,
        _ => candidate,
    };
    match (body.exprs[realized]) {
        ExprLiteral { value: let s: root.base.LiteralString } => s.value,
        _ => baml.sys.panic("expected string literal"),
    }
}

// port: lib.rs::tests::raw_string_literals_keep_backslashes @ d9be6853b
test "raw string literals keep backslashes" {
    let source = "\nfunction main() -> string {\n  r\"\\d+\\\"\\u{41}\"\n}\n";
    let body = expr_body(first_function(lower_source(source).items)).v0;
    assert.equal(
        body.exprs[root_tail(body)],
        ExprLiteral { value: root.base.LiteralString { value: "\\d+\\\"\\u{41}" } },
    )
}

// port: lib.rs::tests::byte_string_literals_decode_any_hex_byte @ d9be6853b
test "byte string literals decode any hex byte" {
    let source = "\nfunction main() -> uint8array {\n  b\"\\xFF\\'\\/\"\n}\n";
    let body = expr_body(first_function(lower_source(source).items)).v0;
    assert.equal(body.exprs[root_tail(body)], ExprByteStringLiteral { value: [0xFF, 39, 47] })
}

// port: lib.rs::tests::quoted_string_literals_decode_escape_sequences @ d9be6853b
test "quoted string literals decode escape sequences" {
    let source = "\nfunction main() -> string {\n  \"\\n\"\n}\n";
    let body = expr_body(first_function(lower_source(source).items)).v0;
    assert.equal(
        body.exprs[root_tail(body)],
        ExprLiteral { value: root.base.LiteralString { value: "\n" } },
    )
}

// port: lib.rs::tests::trace_hook_is_attached_but_not_documentation @ d9be6853b
test "trace hook is attached but not documentation" {
    let source = `
        /// Useful documentation.
        /// baml:$trace=trace.hidden
        function helper() -> int { 1 }
    `;
    let f = first_function(lower_source(source).items);
    assert.equal(f.docstring, "Useful documentation.");
    let hook = f.trace_hook ?? baml.sys.panic("expected a trace hook");
    assert.equal(hook.path, ["trace", "hidden"])
}

// port: lib.rs::tests::backtick_one_liner_lowers_to_string_literal @ d9be6853b
test "backtick one liner lowers to string literal" {
    let source = "\nfunction Demo() -> string {\n    `hello world`\n}\n";
    assert.equal(extract_first_string_literal(lower_source(source).items), "hello world")
}

// port: lib.rs::tests::backtick_decodes_standard_escapes @ d9be6853b
test "backtick decodes standard escapes" {
    let source = "\nfunction Demo() -> string {\n    `line\\nbreak`\n}\n";
    assert.equal(extract_first_string_literal(lower_source(source).items), "line\nbreak")
}

// port: lib.rs::tests::backtick_single_line_keeps_escaped_newline @ d9be6853b
test "backtick single line keeps escaped newline" {
    let source = "\nfunction Demo() -> string {\n    `hostname\\n`\n}\n";
    assert.equal(extract_first_string_literal(lower_source(source).items), "hostname\n")
}

// port: lib.rs::tests::backtick_escapes_backtick_and_dollar @ d9be6853b
test "backtick escapes backtick and dollar" {
    let source = "\nfunction Demo() -> string {\n    `a\\`b\\${name}c`\n}\n";
    assert.equal(extract_first_string_literal(lower_source(source).items), "a`b${name}c")
}

// port: lib.rs::tests::backtick_multiline_dedents @ d9be6853b
test "backtick multiline dedents" {
    let source = "\nfunction Demo() -> string {\n    `\n        line one\n        line two\n    `\n}\n";
    assert.equal(extract_first_string_literal(lower_source(source).items), "line one\nline two")
}

// port: lib.rs::tests::backtick_single_line_preserves_boundary_whitespace @ d9be6853b
test "backtick single line preserves boundary whitespace" {
    let source = "\nfunction Demo() -> string {\n    `  padded content  `\n}\n";
    assert.equal(extract_first_string_literal(lower_source(source).items), "  padded content  ")
}

// port: lib.rs::tests::backtick_multiline_trims_boundary_layout @ d9be6853b
test "backtick multiline trims boundary layout" {
    let source = [
        "function Demo() -> string {",
        "    `",
        "",
        "        line one",
        "         ",
        "        line two",
        "",
        "    `",
        "}",
    ]
        .join("\n");
    assert.equal(extract_first_string_literal(lower_source(source).items), "line one\n\nline two")
}

// port: lib.rs::tests::backtick_multi_tick_ladder_preserves_inner_ticks @ d9be6853b
test "backtick multi tick ladder preserves inner ticks" {
    let source = "\nfunction Demo() -> string {\n    ``inline `code` here``\n}\n";
    assert.equal(extract_first_string_literal(lower_source(source).items), "inline `code` here")
}

// port: lib.rs::tests::backtick_interpolation_lowers_to_concat_chain @ d9be6853b
// BEP §11: `Hello, ${name}!` is an untagged `ExprTemplate` whose
// `TemplateTagDefault` realization is the left-folded Add chain
// ("Hello, " + name.to_string()) + "!".
test "backtick interpolation lowers to concat chain" {
    let source = "\nfunction Demo(name: string) -> string {\n    `Hello, ${name}!`\n}\n";
    let body = expr_body(first_function(lower_source(source).items)).v0;
    let elaborated = match (body.exprs[root_tail(body)]) {
        ExprTemplate { tag: TemplateTagDefault { elaborated: let e } } => e,
        _ => baml.sys.panic("expected untagged Template at tail"),
    };
    let outer = match (body.exprs[elaborated]) {
        let e: ExprBinary => e,
        _ => baml.sys.panic("expected Binary at elaborated root"),
    };
    assert.equal(outer.op, BinaryOp.Add);
    assert.equal(
        body.exprs[outer.rhs],
        ExprLiteral { value: root.base.LiteralString { value: "!" } },
    );
    let inner = match (body.exprs[outer.lhs]) {
        let e: ExprBinary => e,
        _ => baml.sys.panic("expected nested Binary on lhs"),
    };
    assert.equal(inner.op, BinaryOp.Add);
    assert.equal(
        body.exprs[inner.lhs],
        ExprLiteral { value: root.base.LiteralString { value: "Hello, " } },
    )
}

// port: lib.rs::tests::class_property_syntax_is_structural_ast_data @ d9be6853b
test "class property syntax is structural ast data" {
    let source = `
        class Config { name string }
        function build(name: string) -> unknown {
          let shorthand_object = Config { name };
          let explicit_object = Config { name: name };
          [shorthand_object, explicit_object]
        }
    `;
    let body = expr_body(first_function(lower_source(source).items)).v0;
    let object_syntax = body.exprs.filter_map((expr) -> {
        match (expr) {
            let e: ExprObject => e.fields.at(0)?.syntax,
            _ => null,
        }
    });
    assert.equal(object_syntax, [PropertySyntax.Shorthand, PropertySyntax.Explicit])
}

// port: lib.rs::tests::map_keys_lower_as_ordinary_expressions @ d9be6853b
test "map keys lower as ordinary expressions" {
    let source = `
        function build(name: string) -> unknown {
          { name: 0, "name": 1, KeyKind.Foo: 2, name + "!": 3, f(): 4, keys[0]: 5 }
        }
    `;
    let body = expr_body(first_function(lower_source(source).items)).v0;
    let entries = body.exprs
        .filter_map((expr) -> {
            match (expr) {
                let e: ExprMap => e.entries,
                _ => null,
            }
        })
        .at(0)
        ?? baml.sys.panic("map");
    assert.equal(entries.length(), 6);
    assert.equal(path_segments(body.exprs[entries[0].key]), ["name"]);
    assert.equal(
        body.exprs[entries[1].key],
        ExprLiteral { value: root.base.LiteralString { value: "name" } },
    );
    assert.equal(path_segments(body.exprs[entries[2].key]), ["KeyKind", "Foo"]);
    assert.is_type<ExprBinary>(body.exprs[entries[3].key]);
    assert.is_type<ExprCall>(body.exprs[entries[4].key]);
    assert.is_type<ExprIndex>(body.exprs[entries[5].key]);
}

// port: lib.rs::traverse_coverage_tests::every_allocated_node_is_reachable_from_the_root @ d9be6853b
// Every expression and statement a lambda-free body allocates is reachable
// from its root, exactly once. A child the walker forgets would be dropped
// by every analysis built on it.
test "every allocated node is reachable from the root" {
    let sources = [
        `
            function f(a: int, b: int) -> int throws string {
              let m = { "k": a + b }
              let arr = [a, b, m["k"]]
              for (let x in arr) { if (x > 0) { throw "pos" } }
              let i = 0
              while (i < 3) { i = i + 1 }
              match (a) { 1 => { throw "one" }, _ if b > 0 => { b }, _ => { 0 } }
            }
        `,
        `
            function g(o: int?, cb: () -> int) -> int throws never {
              defer { let z = 1 }
              let v = o?.to_string()
              let c = cb() catch (e) { _ => 0 }
              return c
            }
        `,
        `
            function h(xs: int[]) -> int throws never {
              if let [first, ..rest] = xs { return first }
              return 0
            }
        `,
        // Backtick templates carry their expressions twice, once in
        // `segments` and once in the desugared tag payload, by the same ids.
        // Both must be walked, and neither twice.
        "function t(a: string, n: int) -> string throws never {\n  let plain = `hi ${a} there`\n  let looped = `${for (let i in [1, 2])}x${a}${endfor}`\n  let branched = `${if (n > 0)}pos${else}neg${endif}`\n  return plain + looped + branched\n}",
        // A `let type` binding hides ordinary expression nodes (its operand
        // and `else` block) inside a statement.
        `
            function runtime_edges(t: reflect.Type, value: int) -> int throws never {
              let type T extends I = t else { return 0 }
              let called = identity<T>(value)
              let tested = value is T
              match (value) {
                T => called,
                _ => if (tested) { value } else { 0 }
              }
            }
        `,
    ];
    for (let source in sources) {
        for (let item in lower_source(source).items) {
            if (!(item is ItemFunction)) {
                continue;
            }
            let f = item.value;
            if (!(f.body is FunctionBodyDefExpr)) {
                continue;
            }
            let body = expr_body(f).v0;
            // Bodies with lambdas are skipped: a lambda's nodes are not
            // reachable from the function's root.
            if (
                body.exprs.some((e) -> {
                    e is ExprLambda
                })
            ) {
                continue;
            }
            let root_id = body.root_expr;
            if (root_id == null) {
                continue;
            }
            let walked = body.reachable_excluding_lambdas(root_id);
            let reached_exprs: map<int, bool> = {};
            let reached_stmts: map<int, bool> = {};
            for (let node in walked) {
                match (node) {
                    let n: BodyNodeExpr => reached_exprs.set(n.value, true),
                    let n: BodyNodeStmt => reached_stmts.set(n.value, true),
                };
            }
            // The arena is a DAG (templates share ids between their two
            // representations), so the walk must not repeat itself.
            assert.equal(walked.length(), reached_exprs.length() + reached_stmts.length());
            let missed_exprs: int[] = [];
            for (let id = 0; id < body.exprs.length(); id += 1) {
                if (!reached_exprs.has(id)) {
                    missed_exprs.push(id);
                }
            }
            let missed_stmts: int[] = [];
            for (let id = 0; id < body.stmts.length(); id += 1) {
                if (!reached_stmts.has(id)) {
                    missed_stmts.push(id);
                }
            }
            assert.equal(
                { "function": f.name, "missed_exprs": missed_exprs, "missed_stmts": missed_stmts },
                { "function": f.name, "missed_exprs": [], "missed_stmts": [] },
            );
        }
    }
}

// port: lib.rs::testset_nesting_tests::count_registrations. The
// `<collector>.register_test` / `register_test_set` (or `register_test_at` /
// `register_test_set_at`) calls in a body. Lambda bodies share the arena, so
// a flat scan covers the registration lambdas too.
function count_registrations(body: ExprBody) -> int throws never {
    body.exprs
        .filter((expr) -> {
            match (expr) {
                let call: ExprCall => match (body.exprs[call.callee]) {
                    let callee: ExprMemberAccess => {
                        ["register_test", "register_test_set"].includes(callee.member)
                    },
                    let callee: ExprPath => {
                        let last = callee.value.segments.at(callee.value.segments.length() - 1);
                        last == "register_test_at" || last == "register_test_set_at"
                    },
                    _ => false,
                },
                _ => false,
            }
        })
        .length()
}

// port: lib.rs::testset_nesting_tests::a_test_inside_a_test_does_not_register @ d9be6853b
// A `test` nested in a `testset` registers; a `test` nested in a `test` does
// not. A testset body sets the collector, a test body clears it.
test "a test inside a test does not register" {
    let source = `
        testset "Outer" {
          test "Middle" {
            test "Inner" {
              assert.is_true(true)
            }
          }
        }
    `;
    let lowered = lower_source(source, allow_diagnostics = true);
    // `Inner` sits in a test body, which is no testset's: reported.
    assert.is_true(
        lowered.diags.some((diag) -> {
            match (diag) {
                let d: LoweringDiagnosticTestOutsideTestset => d.kind == TestBlockKind.Test,
                _ => false,
            }
        }),
    );
    let init = lowered.items
        .filter_map((item) -> {
            match (item) {
                let i: ItemFunction if is_init_test_function(i.value.name) => i.value,
                _ => null,
            }
        })
        .at(0)
        ?? baml.sys.panic("expected a synthesized $init_test function");
    let body = expr_body(init).v0;
    // Outer testset + Middle test = 2; `Inner` lowers to `StmtMissing`.
    assert.equal(count_registrations(body), 2);
    let missing_stmts = body.stmts.filter((s) -> {
        s is StmtMissing
    });
    assert.is_true(missing_stmts.length() >= 1)
}

// port: lib.rs::lambda_arena_tests::a_lambdas_throw_is_in_the_enclosing_arena_but_not_reachable_from_its_root @ d9be6853b
// A lambda's body is allocated in the enclosing function's arena, and is not
// reachable from that function's root: effect analyses cannot scan the arena
// flatly.
test "a lambdas throw is in the enclosing arena but not reachable from its root" {
    let source = `
        function defines(value: int) -> int throws never {
          let risky = (n: int) -> int {
            throw "boom"
          }
          return value
        }
    `;
    let f = match (lower_source(source).items.at(0)) {
        let i: ItemFunction => i.value,
        _ => baml.sys.panic("expected a function item"),
    };
    let body = expr_body(f).v0;
    let throw_stmts: int[] = [];
    for (let id = 0; id < body.stmts.length(); id += 1) {
        if (body.stmts[id] is StmtThrow) {
            throw_stmts.push(id);
        }
    }
    // The lambda's `throw` lives in the enclosing function's arena.
    assert.equal(throw_stmts.length(), 1);
    let the_throw = BodyNodeStmt { value: throw_stmts[0] };
    let root_id = body.root_expr ?? baml.sys.panic("root");
    // A walk that stops at lambdas does not reach the lambda's `throw`.
    assert.is_true(!body.reachable_excluding_lambdas(root_id).includes(the_throw));
    // Walking from the lambda's own root does.
    let lambda_root = body.exprs
        .filter_map((e) -> {
            match (e) {
                let l: ExprLambda => l.value.body,
                _ => null,
            }
        })
        .at(0)
        ?? baml.sys.panic("lambda body");
    assert.is_true(body.reachable_excluding_lambdas(lambda_root).includes(the_throw))
}
