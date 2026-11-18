// port: baml_parser/src/tests.rs @ d9be6853b
// The inputs of the Rust parser tests, as oracle cases: our parse
// diagnostics must equal the Rust compiler's. (The Rust tests snapshot the
// tree; we compare diagnostics, the observable output.)

test "smoke" {
    let c0 = root.oracle.compare_parse({ "a.baml": "class Foo { x: int }" });
    assert.equal(c0.ours, c0.rust)
}

test "function with llm body and attributes" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "@@trace(\"x\")\nfunction Classify(text: string, n: int = 3) -> Category throws Err {\n  client: \"openai/gpt-4o\"\n  prompt: \"Hello\"\n}\n",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "function with expression body" {
    let c0 = root.oracle.compare_parse({ "a.baml": "function f<T>(x: T) -> T { x }" });
    assert.equal(c0.ours, c0.rust)
}

test "interface with signatures and implements for" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "interface Named<T> requires Show {\n  type Item extends Bound = int,\n  function name(self) -> string;\n  label: string\n}\nimplements Named<int> for Foo {\n  type Item = int\n  name as label,\n  function name(self) -> string { \"\" }\n}\n",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "enum with attributes" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "enum E {\n  @@alias(\"e\")\n  A @alias(\"a\") @description({{ this }}),\n  B;\n}",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "structural types" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "type T = (a: int, b?: string) -> map<string, int[]?> | \"lit\" | -1 | (Base as Iface).Item;\nclass C {\n  f: (A | B)[]\n}",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "removed items and recovery" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "client<llm> GPT { provider openai }\nretry_policy R { max_retries 3 }\ngenerator g { output_type python }\ntemplate_string Tpl(x: string) #\"hi\"#\ntype_builder { class X { a int } }\ndynamic class D { a int }\ntest Legacy { functions [F] args { a 1 } }\nclasss Oops { a int }\ntyppe Two = int\n",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "missing pieces are reported once" {
    let c0 = root.oracle.compare_parse(
        { "a.baml": "function (x) -> {\nclass {\nenum E { A int | string }\n" },
    );
    assert.equal(c0.ours, c0.rust)
}

test "header comments outside blocks are reported" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "//# ok before an expression function\nfunction f() -> int { 1 }\n//# not ok before a class\nclass C { //# nor in a body\n a: int }\n//# not ok before an LLM function\nfunction g() -> int {\n  client: \"x\"\n  prompt: \"y\"\n}\n",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "function titles are owned" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "//# Title\n/// doc\nfunction f() -> int { 1 }\n/// doc first\n//## Second-level title\nfunction g() -> int {\n  client: \"x\"\n  prompt: \"y\"\n}\n//# one\n//# two\nfunction h() -> int { 1 }\nclass C {\n  //# method title\n  function m(self) -> int { 1 }\n}\n",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "zero progress shapes terminate" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "function f() -> int {\n  let m = map { < };\n  let o = Foo { catch_all_panics a: 1 };\n  x catch (e) { - => 1 }\n}\nclass A { x: int, implements I { @@dynamic } }\nimplements I for A { @@ }\n",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "lookahead disagreements are reported" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "interface I requires <T> { x: int }\nfunction f() -> int {\n  let y = (f(x) as Foo).bar;\n  let z = ([1] as I).y;\n  1\n}\nclass C {\n  a: int\n  /// trailing doc at the end of the file",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "header shapes are reported in place" {
    let c0 = root.oracle.compare_parse(
        {
            "a.baml": "type M = `a${1}b`;\nfunction f() -> string {\n  for x in xs { x }\n  let t = ``;\n  t\n}\nfunction g() -> int { 1 }\n",
        },
    );
    assert.equal(c0.ours, c0.rust)
}

test "nesting is bounded" {
    let n = 400;
    let deep = (o: string, c: string) -> {
        `${o.repeat(n)}1${c.repeat(n)}`
    };
    let parens = parse(`function f() -> int {\n  ${deep("(", ")")}\n}\n`).errors;
    assert.equal(
        parens.some((e) -> {
            parse_error_message(e).includes("nested more than")
        }),
        true,
    );
    assert.equal(
        parse(`function f() -> int {\n  let x = ${"[".repeat(n)}${"]".repeat(n)};\n  1\n}\n`).errors
            .length()
            > 0,
        true,
    );
    assert.equal(parse(`function f() -> int {\n  ${deep("{", "}")}\n}\n`).errors.length() > 0, true);
    assert.equal(parse(`type T = ${"(".repeat(n)}int${")".repeat(n)};\n`).errors.length() > 0, true)
}
