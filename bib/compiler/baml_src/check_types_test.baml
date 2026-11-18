// The message layer against the Rust compiler: a TIR error built by hand,
// at the span the Rust compiler reports, must become the same diagnostic
// (code, span, headline, primary label, severity) as Rust's for the program
// that provokes it. check.rs's own tests run inference; these stand in until
// inference is ported.

// The diagnostic our message layer makes of `error` at `start..end` of
// `files["a.baml"]`, as reflection reports it.
function our_type_diagnostic(
    files: map<string, string>,
    error: root.hir_ty.TirTypeError,
    start: int,
    end: int,
    severity: root.hir_ty.DiagnosticSeverity,
) -> reflect.Diagnostic throws never {
    let db = root.hir.Db.new();
    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    let file_ids = files.keys().map((path) -> {
        root.db.add_file(db, workspace, path, files[path])
    });
    let file = file_ids[
        files.keys().find_index((path) -> {
            path == "a.baml"
        })
            ?? 0
    ];
    let rendered = root.hir_ty.RenderedTirDiagnostic {
        error: error,
        message: root.hir_ty.tir_type_error_render(error, root.hir_ty.Viewpoint.for_file(db, file)),
        range: root.syntax.TextRange { start: start, end: end },
        severity: severity,
        related: [],
    };
    owned_diagnostic(db, tir_rendered_to_diagnostic_for_file(db, file, rendered))
}

// What the comparison reads: the oracle's key plus the severity.
function type_diagnostic_key(d: reflect.Diagnostic) -> string throws never {
    `${d.severity} ${root.oracle.diagnostic_key(d)}`
}

// Asserts that Rust reports exactly one diagnostic for `files`, and that our
// message layer makes the same one of `error` at Rust's span.
function assert_matches_rust(
    files: map<string, string>,
    error: root.hir_ty.TirTypeError,
    severity: root.hir_ty.DiagnosticSeverity = root.hir_ty.DiagnosticSeverity.Error,
) -> void throws never {
    let rust = root.oracle.rust_diagnostics(files);
    assert.equal(rust.length(), 1);
    let span = rust[0].span ?? baml.sys.panic("the Rust diagnostic has no span");
    let ours = our_type_diagnostic(files, error, span.start, span.end, severity);
    assert.equal(type_diagnostic_key(ours), type_diagnostic_key(rust[0]));
}

// A declaration of the workspace (root 0 of a fresh Db) at `namespace.name`.
function workspace_decl(namespace: string[], name: string) -> root.types.DeclName throws never {
    root.types.QualifiedTypeName { pkg: 0, namespace: namespace, name: name }
}

test "a type mismatch is mismatched types with the types in the label" {
    let error: root.hir_ty.TirTypeError = root.hir_ty.TirTypeErrorTypeMismatch {
        expected: root.types.TyInt {},
        got: root.types.TyClass { name: workspace_decl(["shop"], "Cart"), args: [] },
    };
    assert_matches_rust(
        { "ns_shop/b.baml": "class Cart {}", "a.baml": "function f() -> int { root.shop.Cart {} }" },
        error,
    )
}

test "an unresolved name highlights the name in the headline" {
    let error: root.hir_ty.TirTypeError = root.hir_ty.TirTypeErrorUnresolvedName { name: "x", suggestions: [] };
    assert_matches_rust({ "a.baml": "function f() -> int { x }" }, error)
}

test "an unknown member names the receiver type" {
    let error: root.hir_ty.TirTypeError = root.hir_ty.TirTypeErrorUnresolvedMember { base_type: root.types.TyInt {}, member: "foo" };
    assert_matches_rust({ "a.baml": "function f(a: int) -> int { a.foo }" }, error)
}

test "an implicit unit is missing value" {
    let form: root.hir_ty.ImplicitUnitForm = root.hir_ty.ImplicitUnitFormBlockWithoutTail { discards_value: false };
    let error: root.hir_ty.TirTypeError = root.hir_ty.TirTypeErrorImplicitUnit {
        form: form,
        expected: root.types.TyInt {},
        admits_unit: false,
    };
    assert_matches_rust({ "a.baml": "function f() -> int { }" }, error)
}

test "an invalid binary operation spells both operand types" {
    let one: root.base.Literal = root.base.LiteralInt { value: 1 };
    let yes: root.base.Literal = root.base.LiteralBool { value: true };
    let error: root.hir_ty.TirTypeError = root.hir_ty.TirTypeErrorInvalidBinaryOp {
        op: root.ast.BinaryOp.Add,
        lhs: root.types.TyLiteral { value: one, freshness: root.types.Freshness.Fresh },
        rhs: root.types.TyLiteral { value: yes, freshness: root.types.Freshness.Fresh },
    };
    assert_matches_rust({ "a.baml": "function f() -> int { 1 + true }" }, error)
}

test "a constant condition is a warning" {
    let yes: root.base.Literal = root.base.LiteralBool { value: true };
    let error: root.hir_ty.TirTypeError = root.hir_ty.TirTypeErrorConditionAlwaysConstant {
        ty: root.types.TyLiteral { value: yes, freshness: root.types.Freshness.Fresh },
        always_true: true,
    };
    assert_matches_rust(
        { "a.baml": "function f() -> int { if (true) { 1 } else { 2 } }" },
        error,
        severity = root.hir_ty.DiagnosticSeverity.Warning,
    )
}

test "similar names rank by fuzzy score" {
    assert.equal(
        root.hir_ty.similar_name_suggestions("nmae", ["name", "names", "other"]),
        ["name", "names"],
    );
    assert.equal(root.hir_ty.similar_name_suggestions("", ["name"]), []);
    assert.equal(root.hir_ty.jaro_winkler("martha", "marhta") > 0.961, true);
    assert.equal(root.hir_ty.jaro_winkler("martha", "marhta") < 0.962, true)
}
