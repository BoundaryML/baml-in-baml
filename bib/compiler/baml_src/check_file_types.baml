// port: baml_db/src/check.rs::check_file, steps 3-7 @ d9be6853b
//
// The Type-phase part of `check_file`: each body's inference, the per-item
// declaration checks, type-alias bodies, associated-type bindings and the
// interface checks, in Rust's order.
//
// Not ported yet (package L of the TIR plan; their diagnostics are missing):
// `llm_output_findings` (E0184), `let_init_io_diagnostics` /
// `let_init_throw_diagnostics` / `let_init_cycle_diagnostics` (E0158, E0163,
// E0181, E0182, E0183), `json_attrs` (`@json` errors), and
// `package_always_null_fields` (E0185).

// port: baml_db/src/check.rs::parse_error_tainted_scopes @ d9be6853b
// The file scope ids whose inference diagnostics are suppressed: the
// innermost executable scope holding a parse error, and its descendants.
function parse_error_tainted_scopes(
    index: root.hir.FileSemanticIndex,
    parse_errors: root.syntax.ParseError[],
) -> map<int, bool> throws never {
    let tainted: map<int, bool> = {};
    for (let error in parse_errors) {
        let fsid = index.scope_at_offset(root.syntax.parse_error_range(error).start, null);
        let scope = index.scopes[fsid];
        let executable = match (scope.kind) {
            root.hir.ScopeKind.Function => true,
            root.hir.ScopeKind.Lambda => true,
            root.hir.ScopeKind.Block => true,
            root.hir.ScopeKind.Let => true,
            root.hir.ScopeKind.MatchArm => true,
            root.hir.ScopeKind.CatchClause => true,
            root.hir.ScopeKind.CatchArm => true,
            _ => false,
        };
        if (!executable) {
            continue;
        }
        tainted[fsid] = true;
        for (let d = scope.descendants.start; d < scope.descendants.end; d += 1) {
            tainted[d] = true;
        }
    }
    tainted
}

// Whether the scope of `owner` or one of its descendants is parse-tainted;
// null for an owner with no scope (Rust's `None` arm).
function owner_scope_tainted(
    db: root.hir.Db,
    index: root.hir.FileSemanticIndex,
    tainted: map<int, bool>,
    owner: root.hir.BodyOwnerId,
) -> bool? throws never {
    let scope = root.hir.body_scope(db, owner) ?? return null;
    let idx = db.scopes.get(scope).id;
    if (idx >= index.scopes.length()) {
        return false;
    }
    if (tainted.has(idx)) {
        return true;
    }
    let descendants = index.scopes[idx].descendants;
    for (let i = descendants.start; i < descendants.end; i += 1) {
        if (tainted.has(i)) {
            return true;
        }
    }
    false
}

// A declaration-level TIR error at `range`, rendered as `file` reads it.
function declaration_diagnostic(
    db: root.hir.Db,
    file: int,
    vp: root.hir_ty.Viewpoint,
    range: root.syntax.TextRange,
    error: root.hir_ty.TirTypeError,
    severity: root.hir_ty.DiagnosticSeverity,
) -> root.diagnostics.Diagnostic throws never {
    tir_rendered_to_diagnostic_for_file(
        db,
        file,
        root.hir_ty.RenderedTirDiagnostic {
            message: root.hir_ty.tir_type_error_render(error, vp),
            error: error,
            range: range,
            severity: severity,
            related: [],
        },
    )
}

function check_file_types(
    db: root.hir.Db,
    file: int,
    parse_errors: root.syntax.ParseError[],
) -> root.diagnostics.Diagnostic[] throws never {
    let out: root.diagnostics.Diagnostic[] = [];
    let vp = root.hir_ty.Viewpoint.for_file(db, file);
    let index = root.hir.file_semantic_index(db, file);
    let error_ = root.hir_ty.DiagnosticSeverity.Error;

    // ── 3. Body inference, then the per-item declaration checks ──
    let tainted = parse_error_tainted_scopes(index, parse_errors);
    let owners: root.hir.BodyOwnerId[] = [];
    for (let owner in root.hir.file_body_owners(db, file)) {
        owners.push(owner);
        match (owner) {
            let f: root.hir.BodyOwnerIdFunction => {
                owners.push(root.hir.BodyOwnerIdParameterDefaults { value: f.value });
            },
            _ => {},
        }
    }
    for (let owner in owners) {
        let scoped = owner_scope_tainted(db, index, tainted, owner);
        let owner_tainted = if (scoped == null) {
            match (owner) {
                root.hir.BodyOwnerIdParameterDefaults => false,
                _ => {
                    continue;
                },
            }
        } else {
            scoped
        };
        let result = root.hir_ty.infer_body(db, owner);
        if (result.diagnostics.length() == 0) {
            continue;
        }
        let source_map = root.hir.body_source_map(db, owner);
        let type_ref_spans = root.hir.body_type_ref_spans(db, owner);
        for (let diagnostic in result.diagnostics) {
            let rendered = diagnostic.render(db, file, source_map, type_ref_spans = type_ref_spans);
            if (owner_tainted && !(rendered.error is root.hir_ty.TirTypeErrorUnresolvedType)) {
                continue;
            }
            out.push(tir_rendered_to_diagnostic_for_file(db, file, rendered));
        }
    }
    for (let function_ in root.hir.file_functions(db, file)) {
        let found = root.hir_ty.parameter_default_diagnostics(db, function_)
            .concat(root.hir_ty.signature_lowering_diagnostics(db, function_));
        for (let (let range, let error) in found) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
        for (let diagnostic in root.hir_ty.infer.declaration_diagnostics(db, function_)) {
            out.push(tir_rendered_to_diagnostic_for_file(db, file, diagnostic.render(db, file, null)));
        }
        // Not ported: llm_output_findings (E0184).
    }
    for (let function_ in root.hir.file_functions(db, file)) {
        if (root.hir_ty.cleanup_method(db, function_) == root.hir_ty.CleanupMethod.Malformed) {
            out.push(malformed_cleanup_diagnostic(db, file, function_));
        }
    }
    for (let let_ in root.hir.file_lets(db, file)) {
        // Rust skips the init effect checks for a parse-tainted let; with
        // those not ported, the annotation diagnostics are all that remain
        // either way.
        for (let (let range, let error) in root.hir_ty.let_lowering_diagnostics(db, let_)) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
        // Not ported: let_init_io / let_init_cycle / let_init_throw diagnostics.
    }
    for (let class_ in root.hir.file_classes(db, file)) {
        for (let (let range, let error) in root.hir_ty.class_lowering_diagnostics(db, class_)) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
    }
    // Not ported: `@json` attribute errors, package_always_null_fields (E0185).
    for (let interface_ in root.hir.file_interfaces(db, file)) {
        for (let (let range, let error) in root.hir_ty.interface_lowering_diagnostics(db, interface_)) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
    }

    // ── 4. Type-alias bodies ──
    for (let alias in root.hir.file_type_aliases(db, file)) {
        // Not ported: the alias body's `@json` union error.
        for (let (let range, let error) in root.hir_ty.type_alias_lowering_diagnostics(db, alias)) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
    }

    let package = root.hir.file_package(db, file);
    out = out.concat(
        validate_associated_type_bindings_in_items(
            db,
            file,
            root.hir.file_ast(db, file).items,
            root.hir.package_items(db, package.root_id),
            package.namespace_path,
        ),
    );

    // ── 7. Interface impl and coherence diagnostics ──
    out.concat(check_interfaces(db, file))
}
