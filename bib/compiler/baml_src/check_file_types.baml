// port: baml_db/src/check.rs::check_file, steps 3-7 @ d9be6853b
//
// The Type-phase part of `check_file`: each body's inference, the per-item
// declaration checks, type-alias bodies, associated-type bindings and the
// interface checks, in Rust's order: per function the LLM-output warnings
// (E0184); per let the init effect, cycle and throw diagnostics (E0163,
// E0181, E0182, E0183); the `@json` attribute errors; the always-null
// LLM-output fields (E0185).

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
    let scope = root.hir.body_scope(db, owner)
        ?? return null;
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
    let warning = root.hir_ty.DiagnosticSeverity.Warning;

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
        let found = root.hir_ty.parameter_default_diagnostics(db, function_).concat(
            root.hir_ty.signature_lowering_diagnostics(db, function_),
        );
        for (let (let range, let error) in found) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
        for (let diagnostic in root.hir_ty.infer.declaration_diagnostics(db, function_)) {
            out.push(
                tir_rendered_to_diagnostic_for_file(db, file, diagnostic.render(db, file, null)),
            );
        }
        // LLM OUTPUT warnings: a return-type member a model can never
        // return (E0184), at the written return type.
        let findings = root.hir_ty.llm_output_findings(db, function_);
        if (findings.dropped.length() > 0) {
            let return_type = root.hir.elaborated_function_data(db, function_).return_type;
            let range = if (return_type != null) {
                root.hir.elaborated_function_source_map(db, function_).type_refs.span(return_type)
            } else {
                root.hir.function_source_map(db, function_).name_span
            };
            let name = root.hir.function_data(db, function_).name;
            for (let (let member, let no_values) in findings.dropped) {
                let error = root.hir_ty.TirTypeErrorLlmOutputMemberDropped {
                    function_: name,
                    member: member,
                    no_values: no_values,
                    kept: findings.kept,
                };
                out.push(declaration_diagnostic(db, file, vp, range, error, warning));
            }
        }
    }
    for (let function_ in root.hir.file_functions(db, file)) {
        if (root.hir_ty.cleanup_method(db, function_) == root.hir_ty.CleanupMethod.Malformed) {
            out.push(malformed_cleanup_diagnostic(db, file, function_));
        }
    }
    // TOP-LEVEL DECLARATION effect diagnostics. A parse-tainted let keeps
    // only its annotation's diagnostics: recovery rebuilds a broken
    // initializer into some other expression.
    for (let let_ in root.hir.file_lets(db, file)) {
        let tainted_decl = owner_scope_tainted(db, index, tainted, root.hir.BodyOwnerIdLet { value: let_ }) == true;
        let annotation = root.hir_ty.let_lowering_diagnostics(db, let_);
        if (tainted_decl) {
            for (let (let range, let error) in annotation) {
                out.push(declaration_diagnostic(db, file, vp, range, error, error_));
            }
            continue;
        }
        // An effect error already explains a throw its io would raise, so
        // the throw (a warning) is reported only on its own.
        let effects = root.hir_ty.let_init_io_diagnostics(db, let_);
        let throws_: (root.syntax.TextRange, root.hir_ty.TirTypeError)[] = if (effects.length() == 0) {
            root.hir_ty.let_init_throw_diagnostics(db, let_)
        } else {
            []
        };
        let errors = annotation.concat(effects).concat(root.hir_ty.let_init_cycle_diagnostics(db, let_));
        for (let (let range, let error) in errors) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
        for (let (let range, let error) in throws_) {
            out.push(declaration_diagnostic(db, file, vp, range, error, warning));
        }
    }
    for (let class_ in root.hir.file_classes(db, file)) {
        for (let (let range, let error) in root.hir_ty.class_lowering_diagnostics(db, class_)) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
    }
    // `@json` ATTRIBUTE errors: a declaration's own, and each union its types
    // spell that can't pick a member by tag.
    let package_root = root.hir.file_package(db, file).root_id;
    let overrides = root.hir_ty.json_overrides(db, package_root);
    let json_errors: (root.syntax.TextRange, root.hir_ty.TirTypeError)[] = [];
    for (let class_ in root.hir.file_classes(db, file)) {
        let data = root.hir.class_data(db, class_);
        let head = root.hir_ty.qualify_def(db, root.hir.DefinitionClass { value: class_ }, data.name);
        json_errors = json_errors.concat(root.hir_ty.class_errors(db, class_, head, overrides));
        let source_map = root.hir.class_source_map(db, class_);
        let fields = root.hir_ty.resolve_class_fields(db, class_);
        for (let i = 0; i < data.fields.length() && i < fields.length(); i += 1) {
            let error = root.hir_ty.union_error(db, fields[i].1);
            if (error != null) {
                json_errors.push((source_map.type_refs.span(data.fields[i].type_ref), error));
            }
        }
    }
    for (let enum_loc in root.hir.file_enums(db, file)) {
        let data = root.hir.enum_data(db, enum_loc);
        let head = root.hir_ty.qualify_def(db, root.hir.DefinitionEnum { value: enum_loc }, data.name);
        let renames = data.variants.some((variant) -> {
            variant.attrs.json_rename != null
        });
        let interface_ = if (renames) {
            root.hir_ty.override_of(overrides, head)
        } else {
            null
        };
        if (interface_ != null) {
            json_errors.push(
                (
                    root.hir.enum_source_map(db, enum_loc).name_span,
                    root.hir_ty.TirTypeErrorJsonAttributesWithOverride {
                        name: data.name,
                        interface_: interface_,
                    },
                ),
            );
        }
    }
    for (let function_ in root.hir.file_functions(db, file)) {
        let signature = root.hir_ty.function_signature_with_diagnostics(db, function_).signature;
        let tys = signature.params
            .map((param) -> {
                param.ty
            })
            .concat([signature.ret]);
        for (let ty in tys) {
            let error = root.hir_ty.union_error(db, ty);
            if (error != null) {
                json_errors.push((root.hir.function_source_map(db, function_).name_span, error));
                break;
            }
        }
    }
    for (let (let range, let error) in json_errors) {
        out.push(declaration_diagnostic(db, file, vp, range, error, error_));
    }
    // LLM OUTPUT field warnings: an optional field an LLM function's output
    // reaches, which a model can never fill (E0185), at the field's written
    // type.
    let always_null = root.hir_ty.package_always_null_fields(db, package_root);
    if (always_null.length() > 0) {
        for (let class_ in root.hir.file_classes(db, file)) {
            let data = root.hir.class_data(db, class_);
            let head = root.hir_ty.qualify_def(db, root.hir.DefinitionClass { value: class_ }, data.name);
            let source_map = root.hir.class_source_map(db, class_);
            for (let field in data.fields) {
                if (!always_null.includes((head, field.name))) {
                    continue;
                }
                let error = root.hir_ty.TirTypeErrorLlmOutputFieldAlwaysNull { field: field.name };
                out.push(
                    declaration_diagnostic(db, file, vp, source_map.type_refs.span(field.type_ref), error, warning),
                );
            }
        }
    }
    for (let interface_ in root.hir.file_interfaces(db, file)) {
        for (let (let range, let error) in root.hir_ty.interface_lowering_diagnostics(db, interface_)) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
    }

    // ── 4. Type-alias bodies ──
    for (let alias in root.hir.file_type_aliases(db, file)) {
        let found = root.hir_ty.type_alias_lowering_diagnostics(db, alias);
        let untagged = root.hir_ty.union_error(db, root.hir_ty.type_alias_value(db, alias));
        if (untagged != null) {
            found = found.concat([(root.hir.type_alias_source_map(db, alias).name_span, untagged)]);
        }
        for (let (let range, let error) in found) {
            out.push(declaration_diagnostic(db, file, vp, range, error, error_));
        }
    }

    let package = root.hir.file_package(db, file);
    out
        = out.concat(
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
