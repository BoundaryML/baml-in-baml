// The Rust compiler, reached through reflection. Used only by tests to say
// what our compiler should report.

function rust_diagnostics(files: map<string, string>) -> reflect.Diagnostic[] throws never {
    let package = reflect.Package._compile(files, {}) catch (error) {
        reflect.errors.CompilationError => {
            return error.diagnostics;
        },
    };
    []
}

test "oracle reports a type error" {
    let diags = rust_diagnostics({ "a.baml": "function f() -> int { \"no\" }" });
    assert.equal(diags.length() > 0, true);
    assert.equal(diags[0].severity, "error");
}

test "oracle accepts clean code" {
    let diags = rust_diagnostics({ "a.baml": "function f() -> int { 1 }" });
    assert.equal(diags.length(), 0);
}
