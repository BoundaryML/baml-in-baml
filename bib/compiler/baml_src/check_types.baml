// port: baml_db/src/check.rs @ d9be6853b
//
// The type checker's message layer: turning TIR errors into diagnostics,
// the interface checks and the associated-type AST checks. `check_file`
// (check.baml) does not call any of it yet; the type-phase steps are wired in
// once inference exists.
//
// Restructured:
// - Rust's `SourceFile` and `FileId` are the same `int` here, so the
//   functions that take both take one `file`.
// - `&mut Vec<Diagnostic>` out-parameters are arrays the callee pushes to.
// - The mounted-dependency paths (`check_interfaces`' source-vs-mounted
//   coherence and its replay of a mounted interface row, and the
//   `has_mounted_bound` early return of the associated-type check) are not
//   ported: they act only on packages served from a package interface, and
//   this port mounts none (the stdlib is compiled from source), so in Rust
//   too they find no mounted interface and do nothing here.
//
// Not ported: `tir_rendered_to_diagnostic` (`#[cfg(test)]` only).

// port: baml_db/src/check.rs::check_interfaces @ d9be6853b
// The interface `implements` diagnostics of `file`, computed by hir_ty and
// mapped onto source ranges here: coherence overlaps (E0132) anchored on
// this file's side of each conflicting pair, then each impl's structural
// diagnostics (`impl_data`) and its signature/type conformance
// (`validate_impl_signatures`).
function check_interfaces(
    db: root.hir.Db,
    file: int,
) -> root.diagnostics.Diagnostic[] throws never {
    let diagnostics: root.diagnostics.Diagnostic[] = [];
    let vp = root.hir_ty.Viewpoint.for_file(db, file);

    // 1. Coherence (E0132): a per-package property, surfaced for the
    // violations whose offending impl lives in this file. A cross-file pair
    // is reported once per file, each anchored on its own impl.
    let pkg_id = root.hir.file_package(db, file).root_id;
    for (let violation in root.hir_ty.interfaces.package_coherence_diagnostics(db, pkg_id)) {
        let primary = violation.primary;
        let secondary = violation.secondary;
        if (violation.primary.file_id != file) {
            if (violation.secondary.file_id != file) {
                continue;
            }
            primary = violation.secondary;
            secondary = violation.primary;
        }
        // A definite overlap and an undecidable one are both rejected; the
        // message says which.
        let message = if (violation.indeterminate) {
            "these interface implementations are too complex to prove disjoint; simplify the types involved so coherence can be decided"
        } else {
            "overlapping interface implementations for the same receiver/interface"
        };
        diagnostics.push(
            root.diagnostics.Diagnostic.error(root.diagnostics.OVERLAPPING_IMPLEMENTS, message)
                .with_primary_span(primary)
                .with_secondary(secondary, "conflicting implementation is here")
                .with_phase(root.hir.DiagnosticPhase.Type),
        );
    }

    // 2 + 3. Per-impl structural and signature/conformance diagnostics, each
    // mapped through the impl's source map; a name-keyed location may mark
    // several sites.
    for (let impl_loc in root.hir.file_impls(db, file)) {
        let sm = root.hir_ty.interfaces.impl_data_source_map(db, impl_loc);
        // `impl_data` owns an impl's structural diagnostics whether or not it
        // fully resolves. A cyclic header carries none:
        // `validate_impl_signatures` re-detects and surfaces it.
        let structural: (root.hir_ty.TirTypeError, root.hir_ty.interfaces.ImplDiagnosticLocation)[] = match (root.hir_ty.interfaces.impl_data(db, impl_loc)) {
            let data: root.hir_ty.interfaces.ImplData => data.diagnostics,
            let error: root.hir_ty.interfaces.ImplDataErrorInterfaceUnresolved => error.diagnostics,
            root.hir_ty.interfaces.ImplDataErrorCyclicHeader
                | root.hir_ty.interfaces.ImplDataErrorMalformed =>
            {
                []
            },
        };
        let signatures = root.hir_ty.interfaces.validate_impl_signatures(db, impl_loc);
        for (let entry in structural.concat(signatures)) {
            for (let span in impl_diagnostic_spans(entry.1, sm)) {
                diagnostics.push(
                    root.diagnostics.Diagnostic
                        .error(
                            tir_type_error_to_diagnostic_id(entry.0),
                            root.hir_ty.tir_type_error_render(entry.0, vp),
                        )
                        .with_primary_span(span)
                        .with_phase(root.hir.DiagnosticPhase.Type),
                );
            }
        }
    }

    diagnostics
}

// port: baml_db/src/check.rs::impl_diagnostic_spans @ d9be6853b
// The source span(s) an impl diagnostic location marks. The name-keyed
// locations can mark several same-named sites; an empty or missing entry
// falls back to the whole-block span.
function impl_diagnostic_spans(
    loc: root.hir_ty.interfaces.ImplDiagnosticLocation,
    sm: root.hir_ty.interfaces.ImplDataSourceMap,
) -> root.base.Span[] throws never {
    let named = (spans: root.base.Span[]?) -> root.base.Span[] {
        if (spans != null && spans.length() > 0) {
            spans
        } else {
            [sm.impl_span]
        }
    };
    match (loc) {
        root.hir_ty.interfaces.ImplDiagnosticLocationInterfaceTarget => [sm.interface_target_span],
        root.hir_ty.interfaces.ImplDiagnosticLocationForTarget => {
            [sm.for_target_span ?? sm.impl_span]
        },
        root.hir_ty.interfaces.ImplDiagnosticLocationBound => [sm.impl_span],
        let l: root.hir_ty.interfaces.ImplDiagnosticLocationMethod => {
            named(sm.method_spans.get(l.value))
        },
        let l: root.hir_ty.interfaces.ImplDiagnosticLocationInterfaceFieldLink => {
            named(sm.interface_field_link_spans.get(l.value))
        },
        let l: root.hir_ty.interfaces.ImplDiagnosticLocationClassFieldLink => {
            named(sm.class_field_link_spans.get(l.value))
        },
        let l: root.hir_ty.interfaces.ImplDiagnosticLocationAssociatedBinding => {
            named(sm.associated_binding_spans.get(l.value))
        },
    }
}

// port: baml_db/src/check.rs::resolve_interface_path @ d9be6853b
// The interface (loc id) an `extends` bound names, or null when it does not
// resolve to one (diagnosed elsewhere).
function resolve_interface_path(
    db: root.hir.Db,
    target: root.ast.TypeExpr,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
) -> int? throws never {
    root.hir_ty.interfaces.resolve_path_to_interface_identity(db, target, pkg_items, namespace_path)
        ?.loc
}

// port: baml_db/src/check.rs::validate_associated_type_bindings_in_items @ d9be6853b
// The associated-type checks over a file's AST items: declaration names
// against generic parameters, and every `T.Member` projection in a
// signature against the bounds of `T`.
function validate_associated_type_bindings_in_items(
    db: root.hir.Db,
    file: int,
    items: root.ast.Item[],
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
) -> root.diagnostics.Diagnostic[] throws never {
    let diagnostics: root.diagnostics.Diagnostic[] = [];

    for (let item in items) {
        match (item) {
            let f: root.ast.ItemFunction => {
                validate_associated_type_bindings_in_function(db, file, f.value, {}, pkg_items, namespace_path, diagnostics);
            },
            let c: root.ast.ItemClass => {
                let outer_bounds = generic_bound_expr_map(c.value.generic_params);
                for (let method in c.value.methods) {
                    validate_associated_type_bindings_in_function(db, file, method, outer_bounds, pkg_items, namespace_path, diagnostics);
                }
            },
            let i: root.ast.ItemInterface => {
                let iface = i.value;
                validate_associated_type_declaration_names(file, iface, diagnostics);
                let iface_bounds = generic_bound_expr_map(iface.generic_params);
                for (let method in iface.required_methods) {
                    validate_associated_type_bindings_in_method_sig(db, file, method, iface_bounds, pkg_items, namespace_path, diagnostics);
                }
                for (let method in iface.default_methods) {
                    validate_associated_type_bindings_in_function(db, file, method, iface_bounds, pkg_items, namespace_path, diagnostics);
                }
            },
            let imp: root.ast.ItemImplementsFor => {
                let impl_bounds = generic_bound_expr_map(imp.value.generic_params);
                for (let method in imp.value.methods) {
                    validate_associated_type_bindings_in_function(db, file, method, impl_bounds, pkg_items, namespace_path, diagnostics);
                }
            },
            _ => {},
        }
    }

    diagnostics
}

// port: baml_db/src/check.rs::validate_associated_type_declaration_names @ d9be6853b
// An associated type spelled like one of its interface's generic parameters.
function validate_associated_type_declaration_names(
    file: int,
    iface: root.ast.InterfaceDef,
    diagnostics: root.diagnostics.Diagnostic[],
) -> void throws never {
    for (let assoc in iface.associated_types) {
        if (
            iface.generic_params.some((param) -> {
                param.name == assoc.name
            })
        ) {
            diagnostics.push(
                root.diagnostics.Diagnostic
                    .error(
                        root.diagnostics.DUPLICATE_FIELD,
                        ``associated type `${assoc.name}` collides with generic parameter `${assoc.name}```,
                    )
                    .with_primary_span(root.base.Span { file_id: file, range: assoc.span })
                    .with_phase(root.hir.DiagnosticPhase.Type),
            );
        }
    }
}

// port: baml_db/src/check.rs::GenericBoundExprMap @ d9be6853b
// Each in-scope type variable's declared bound conjunction: `T extends A & B`
// maps `T` to `[A, B]`.
type GenericBoundExprMap = map<string, root.ast.TypeExpr[]>;

// port: baml_db/src/check.rs::generic_bound_expr_map @ d9be6853b
function generic_bound_expr_map(
    params: root.ast.GenericParam[],
) -> GenericBoundExprMap throws never {
    let bounds: GenericBoundExprMap = {};
    for (let param in params) {
        if (param.bounds.length() > 0) {
            bounds[param.name] = param.bounds;
        }
    }
    bounds
}

// port: baml_db/src/check.rs::extend_generic_bound_expr_map @ d9be6853b
// `outer` with `params`' bounds added, an inner declaration's winning.
function extend_generic_bound_expr_map(
    outer: GenericBoundExprMap,
    params: root.ast.GenericParam[],
) -> GenericBoundExprMap throws never {
    let merged: GenericBoundExprMap = {};
    for (let name in outer.keys()) {
        merged[name] = outer[name];
    }
    let inner = generic_bound_expr_map(params);
    for (let name in inner.keys()) {
        merged[name] = inner[name];
    }
    merged
}

// port: baml_db/src/check.rs::validate_associated_type_bindings_in_function @ d9be6853b
// The projection check over a function's parameter, return and throws types.
function validate_associated_type_bindings_in_function(
    db: root.hir.Db,
    file: int,
    function_: root.ast.FunctionDef,
    outer_generic_bounds: GenericBoundExprMap,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    diagnostics: root.diagnostics.Diagnostic[],
) -> void throws never {
    let generic_bounds = extend_generic_bound_expr_map(outer_generic_bounds, function_.generic_params);
    let annotations = function_.params
        .filter_map((param) -> {
            param.type_expr
        })
        .concat(
            [function_.return_type, function_.throws_].filter_map((te) -> {
                te
            }),
        );
    for (let te in annotations) {
        validate_ambiguous_typevar_associated_projection_in_type_expr(db, file, te, te.span, pkg_items, namespace_path, generic_bounds, diagnostics);
    }
}

// port: baml_db/src/check.rs::validate_associated_type_bindings_in_method_sig @ d9be6853b
// The projection check over a required method's parameter, return and
// throws types.
function validate_associated_type_bindings_in_method_sig(
    db: root.hir.Db,
    file: int,
    method: root.ast.MethodSigDef,
    outer_generic_bounds: GenericBoundExprMap,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    diagnostics: root.diagnostics.Diagnostic[],
) -> void throws never {
    let generic_bounds = extend_generic_bound_expr_map(outer_generic_bounds, method.generic_params);
    let annotations = method.params
        .filter_map((param) -> {
            param.type_expr
        })
        .concat(
            [method.return_type, method.throws_].filter_map((te) -> {
                te
            }),
        );
    for (let te in annotations) {
        validate_ambiguous_typevar_associated_projection_in_type_expr(db, file, te, te.span, pkg_items, namespace_path, generic_bounds, diagnostics);
    }
}

// port: baml_db/src/check.rs::validate_ambiguous_typevar_associated_projection_in_type_expr @ d9be6853b
// Every `T.Member` written in `expr`, where `T` is a bounded type variable:
// unknown when no bound's `requires` closure declares `Member` (E0002),
// ambiguous when two or more do (E0001). Reported at `span`, the written
// annotation's span, for nested types too.
function validate_ambiguous_typevar_associated_projection_in_type_expr(
    db: root.hir.Db,
    file: int,
    expr: root.ast.TypeExpr,
    span: root.syntax.TextRange,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    generic_bounds: GenericBoundExprMap,
    diagnostics: root.diagnostics.Diagnostic[],
) -> void throws never {
    let recurse = (child: root.ast.TypeExpr) -> void {
        validate_ambiguous_typevar_associated_projection_in_type_expr(db, file, child, span, pkg_items, namespace_path, generic_bounds, diagnostics);
    };
    match (expr.kind) {
        let p: root.ast.TypeExprKindPath => {
            let path = p.path.segments;
            if (
                path.length() == 2
                    && p.generic_args.length() == 0
                    && p.associated_type_bindings.length() == 0
            ) {
                let base = path[0];
                let member = path[1];
                let bounds = generic_bounds.get(base);
                if (bounds != null) {
                    // `T extends A & B`: the member may come from any
                    // conjunct, so the declarers are collected across the
                    // whole conjunction (hir_ty deduplicates them): none is
                    // unknown, two or more is ambiguous.
                    let roots = bounds.filter_map((bound) -> {
                        resolve_interface_path(db, bound, pkg_items, namespace_path)
                    });
                    let viewpoint = root.hir_ty.Viewpoint.for_namespace(
                        db,
                        pkg_items.root_id,
                        namespace = namespace_path,
                    );
                    let sources = root.hir_ty.interfaces
                        .interfaces_declaring_associated_type(db, roots, member)
                        .filter_map((loc) -> {
                            let qtn = root.hir_ty.interfaces.interface_loc_qtn(db, loc)
                                ?? return null;
                            viewpoint.path(qtn)
                        });
                    if (sources.length() == 0) {
                        let rendered = bounds
                            .map((bound) -> {
                                bound.to_string()
                            })
                            .join(" & ");
                        diagnostics.push(
                            root.diagnostics.Diagnostic
                                .error(
                                    root.diagnostics.UNKNOWN_TYPE,
                                    ``unknown associated type `${member}` for bound `${rendered}```,
                                )
                                .with_primary_span(root.base.Span { file_id: file, range: span })
                                .with_phase(root.hir.DiagnosticPhase.Type),
                        );
                    } else if (sources.length() >= 2) {
                        let alternatives = sources
                            .map((interface_) -> {
                                `(${base} as ${interface_}).${member}`
                            })
                            .join(", ");
                        diagnostics.push(
                            root.diagnostics.Diagnostic
                                .error(
                                    root.diagnostics.TYPE_MISMATCH,
                                    ``ambiguous associated type projection `${base}.${member}`; disambiguate with one of: ${alternatives}``,
                                )
                                .with_primary_span(root.base.Span { file_id: file, range: span })
                                .with_phase(root.hir.DiagnosticPhase.Type),
                        );
                    }
                }
            }
            p.generic_args.map(recurse);
            p.associated_type_bindings.map((binding) -> {
                recurse(binding.ty)
            });
        },
        let p: root.ast.TypeExprKindAssociatedTypeProjection => {
            recurse(p.base);
            let interface_ = p.interface_;
            if (interface_ != null) {
                recurse(interface_);
            }
        },
        let o: root.ast.TypeExprKindOptional => recurse(o.inner),
        let l: root.ast.TypeExprKindList => recurse(l.inner),
        let m: root.ast.TypeExprKindMap => {
            recurse(m.key);
            recurse(m.value);
        },
        let u: root.ast.TypeExprKindUnion => {
            u.variants.map(recurse);
        },
        let f: root.ast.TypeExprKindFunction => {
            f.params.map((param) -> {
                recurse(param.ty)
            });
            recurse(f.ret);
            let throws_ = f.throws_;
            if (throws_ != null) {
                recurse(throws_);
            }
        },
        _ => {},
    }
}

// port: baml_db/src/check.rs::tir_rendered_to_diagnostic_with_message @ d9be6853b
// A rendered TIR diagnostic as a `Diagnostic` in `file`, with `message` as
// its text. A member read on `unknown` gets a narrowing hint as its label;
// the reachability family labels its related code in the same frame.
function tir_rendered_to_diagnostic_with_message(
    vp: root.hir_ty.Viewpoint,
    rendered: root.hir_ty.RenderedTirDiagnostic,
    file: int,
    message: root.diagnostics.DiagnosticText,
) -> root.diagnostics.Diagnostic throws never {
    let unknown_member_access_member = match (rendered.error) {
        let e: root.hir_ty.TirTypeErrorUnresolvedMember if e.base_type is root.types.TyUnknown => {
            e.member
        },
        _ => null,
    };
    let span = root.base.Span { file_id: file, range: rendered.range };
    let warning = rendered.severity == root.hir_ty.DiagnosticSeverity.Warning;
    let diag = new_tir_diagnostic(vp, rendered.error, message, span, warning);
    if (unknown_member_access_member != null) {
        diag.annotations = [];
        diag.with_primary(
            span,
            ``use `match` to narrow this value before accessing `${unknown_member_access_member}```,
        );
    }
    // The reachability family labels the code it talks about in the same
    // frame: the unreachable branch, body or arm of a constant condition,
    // and the never-ending loop that leaves the code after it dead.
    let reachability = match (rendered.error) {
        root.hir_ty.TirTypeErrorUncalledFunctionInCondition
            | root.hir_ty.TirTypeErrorConditionAlwaysConstant
            | root.hir_ty.TirTypeErrorComparisonAlwaysDisjoint
            | root.hir_ty.TirTypeErrorDeadCode =>
        {
            true
        },
        _ => false,
    };
    for (let related in rendered.related) {
        let related_span = root.base.Span { file_id: related.file_id, range: related.range };
        if (reachability) {
            diag.with_secondary(related_span, related.message);
            continue;
        }
        if (unknown_member_access_member != null) {
            diag.with_secondary(related_span, related.message);
        }
        diag.with_related(related_span, related.message);
    }
    diag
}

// port: baml_db/src/check.rs::tir_rendered_to_diagnostic_for_file @ d9be6853b
// A rendered TIR diagnostic as a `Diagnostic` in `file`, with its message
// rendered as `file` reads it.
function tir_rendered_to_diagnostic_for_file(
    db: root.hir.Db,
    file: int,
    rendered: root.hir_ty.RenderedTirDiagnostic,
) -> root.diagnostics.Diagnostic throws never {
    let message = rich_source_aware_tir_type_error_message(db, file, rendered.error);
    tir_rendered_to_diagnostic_with_message(root.hir_ty.Viewpoint.for_file(db, file), rendered, file, message)
}

// port: baml_db/src/check.rs::malformed_cleanup_diagnostic @ d9be6853b
// E0144 for a class's own `cleanup` method that is not shaped as a
// finalizer, at the method's name.
function malformed_cleanup_diagnostic(
    db: root.hir.Db,
    file: int,
    method: int,
) -> root.diagnostics.Diagnostic throws never {
    let class_ = match (root.hir.method_owner(db, method)) {
        let owner: root.hir.MethodOwnerClass => owner.value,
        _ => baml.sys.panic("only a class's own method is a `cleanup` finalizer"),
    };
    let class_name = root.hir.class_data(db, class_).name;
    root.diagnostics.Diagnostic
        .error(
            root.diagnostics.CLEANUP_MAGIC_METHOD_SIGNATURE,
            ``\`cleanup` on class `${class_name}` must have the signature `cleanup(self) -> void`; it is a reserved magic finalizer name``,
        )
        .with_primary(
            root.base.Span {
                file_id: file,
                range: root.hir.function_source_map(db, method).name_span,
            },
            "expected `cleanup(self) -> void`",
        )
        .with_phase(root.hir.DiagnosticPhase.Type)
}

// port: baml_db/src/check.rs::new_tir_diagnostic @ d9be6853b
// The `Diagnostic` for a TIR error at `span`: the errors with their own
// headline (the shared runtime-type constructors, `mismatched types`,
// `missing value`) put `message` in the primary label; the rest make it the
// headline.
function new_tir_diagnostic(
    vp: root.hir_ty.Viewpoint,
    error: root.hir_ty.TirTypeError,
    message: root.diagnostics.DiagnosticText,
    span: root.base.Span,
    warning: bool,
) -> root.diagnostics.Diagnostic throws never {
    let type_phase = root.hir.DiagnosticPhase.Type;
    match (error) {
        let e: root.hir_ty.TirTypeErrorUncalledFunctionInCondition => {
            let suggestion = e.suggestion;
            let label = if (suggestion != null) {
                ``did you mean to call this function? Replace with `${suggestion}```
            } else {
                "did you mean to call this function?"
            };
            return root.diagnostics.Diagnostic
                .warning(root.diagnostics.CONDITION_ALWAYS_CONSTANT, message)
                .with_primary(span, label)
                .with_phase(type_phase);
        },
        let e: root.hir_ty.TirTypeErrorComputedGenericArgumentRequiresLetType => {
            return root.diagnostics.computed_generic_argument_requires_let_type(e.name)
                .with_primary_span(span)
                .with_phase(type_phase);
        },
        let e: root.hir_ty.TirTypeErrorBoundedLetTypeRequiresElse => {
            return root.diagnostics.bounded_let_type_requires_else(e.name)
                .with_primary_span(span)
                .with_phase(type_phase);
        },
        root.hir_ty.TirTypeErrorLetTypePendingOperand => {
            return root.diagnostics.let_type_pending_operand().with_primary_span(span).with_phase(
                type_phase,
            );
        },
        let e: root.hir_ty.TirTypeErrorCannotConstructReflectionKind => {
            return root.diagnostics.cannot_construct_reflection_kind(vp.path(e.class_name))
                .with_primary_span(span)
                .with_phase(type_phase);
        },
        let e: root.hir_ty.TirTypeErrorScopedTypeEscapesBlock => {
            let name = e.name;
            let value = root.hir_ty.ty_spell(e.value, vp);
            let label = match (e.kind) {
                root.hir_ty.ScopedTypeEscapeKindValue => {
                    ``this has type `${value}`; a value leaves the block only through a type that does not mention `${name}`, such as `unknown```
                },
                // The remedy names the clause to write, not the rule that
                // derives it: the author is being asked to type something.
                let thrown: root.hir_ty.ScopedTypeEscapeKindThrown => {
                    let relaxation = thrown.relaxation;
                    if (relaxation != null) {
                        ``this throws `${value}`, which would be published past the block; catch it inside the block, or declare `throws ${root.hir_ty.ty_spell(relaxation, vp)}```
                    } else {
                        ``this throws `${value}`, which would be published past the block; catch it inside the block, or declare a `throws` clause that does not mention `${name}```
                    }
                },
                root.hir_ty.ScopedTypeEscapeKindInferred => {
                    ``the type inferred here would be `${value}`; give the binding it flows into a type that does not mention `${name}`, such as `unknown```
                },
            };
            return root.diagnostics.scoped_type_escapes_block(name).with_primary(span, label).with_phase(
                type_phase,
            );
        },
        let e: root.hir_ty.TirTypeErrorCannotConstructBuiltinCompanion => {
            return root.diagnostics
                .cannot_construct_builtin_companion(
                    vp.path(e.class_name),
                    e.companion.builtin,
                    e.companion.origin,
                    e.companion.carries_methods,
                )
                .with_primary_span(span)
                .with_phase(type_phase);
        },
        root.hir_ty.TirTypeErrorTypeMismatch
            | root.hir_ty.TirTypeErrorUnitExpected
            | root.hir_ty.TirTypeErrorListPatternNeverMatches =>
        {
            let base = root.diagnostics.mismatched_types();
            let diagnostic = if (warning) {
                root.diagnostics.Diagnostic.warning(base.id, base.message)
            } else {
                base
            };
            return diagnostic.with_primary(span, message).with_phase(type_phase);
        },
        _ => {},
    }
    let id = tir_type_error_to_diagnostic_id(error);
    let headline = match (error) {
        root.hir_ty.TirTypeErrorImplicitUnit => "missing value",
        _ => null,
    };
    let diagnostic = if (headline != null) {
        let headed = if (warning) {
            root.diagnostics.Diagnostic.warning(id, headline)
        } else {
            root.diagnostics.Diagnostic.error(id, headline)
        };
        headed.with_primary(span, message)
    } else {
        let headed = if (warning) {
            root.diagnostics.Diagnostic.warning(id, message)
        } else {
            root.diagnostics.Diagnostic.error(id, message)
        };
        headed.with_primary_span(span)
    };
    diagnostic.with_phase(type_phase)
}

// port: baml_db/src/check.rs::rich_source_aware_tir_type_error_message @ d9be6853b
// The message for `error` as `file` reads it, with its type expressions,
// identifiers and code highlighted; errors without a rich form take
// `source_aware_tir_type_error_message`.
function rich_source_aware_tir_type_error_message(
    db: root.hir.Db,
    file: int,
    error: root.hir_ty.TirTypeError,
) -> root.diagnostics.DiagnosticText throws never {
    let ty = (t: root.types.Ty) -> string {
        display_ty_for_file(db, file, t)
    };
    let new_text = () -> root.diagnostics.DiagnosticText {
        root.diagnostics.DiagnosticText.new()
    };
    match (error) {
        let e: root.hir_ty.TirTypeErrorTypeMismatch => {
            new_text().text("expected ").type_expr(ty(e.expected)).text(", found ").type_expr(
                ty(e.got),
            )
        },
        let e: root.hir_ty.TirTypeErrorUnresolvedName => {
            let text = new_text().text("unresolved name: ").identifier(
                e.name,
                root.diagnostics.DiagnosticIdentifierKind.Variable,
            );
            match (e.suggestions.length()) {
                0 => text,
                1 => text.text(". Did you mean ").code(e.suggestions[0]).text("?"),
                _ => {
                    text.text(". Did you mean one of these: ").code(e.suggestions[0]);
                    for (let suggestion in e.suggestions.slice(1, e.suggestions.length())) {
                        text.text(", ").code(suggestion);
                    }
                    text.text("?")
                },
            }
        },
        let e: root.hir_ty.TirTypeErrorUnresolvedMember => {
            let message = new_text().text("type ").type_expr(ty(e.base_type)).text(" has no member ").identifier(
                e.member,
                root.diagnostics.DiagnosticIdentifierKind.Field,
            );
            if (e.base_type is root.types.TyTuple) {
                message.text("; tuple slots are numbered, such as `.0`")
            } else {
                message
            }
        },
        let e: root.hir_ty.TirTypeErrorNotCallable => {
            new_text().type_expr(ty(e.ty)).text(" is not a function and cannot be called")
        },
        let e: root.hir_ty.TirTypeErrorNotIterable => {
            new_text().text("cannot iterate over type ").type_expr(ty(e.ty))
        },
        let e: root.hir_ty.TirTypeErrorNotIndexable => {
            let message = new_text().text("cannot index into type ").type_expr(ty(e.ty));
            if (e.ty is root.types.TyTuple) {
                message.text(
                    "; tuples use fixed dot slots such as `.0`; use `reflect.Tuple.get_element` for a runtime-selected slot",
                )
            } else {
                message
            }
        },
        let e: root.hir_ty.TirTypeErrorImplicitUnit => {
            let (let before, let after) = root.hir_ty.implicit_unit_form_around_expected(e.form, e.admits_unit);
            new_text().text(before).type_expr(ty(e.expected)).text(after)
        },
        let e: root.hir_ty.TirTypeErrorListPatternNeverMatches => {
            new_text().text("a list pattern never matches a value of type ").type_expr(
                ty(e.scrutinee),
            )
        },
        let e: root.hir_ty.TirTypeErrorUnitExpected => {
            let (let before, let after) = root.hir_ty.unit_context_around_found(e.context);
            new_text().text(before).type_expr(ty(e.found)).text(after)
        },
        _ => {
            root.diagnostics.diagnostic_text_from(
                source_aware_tir_type_error_message(db, file, error),
            )
        },
    }
}

// port: baml_db/src/check.rs::source_aware_tir_type_error_message @ d9be6853b
// The plain message for `error` as `file` reads it: check.rs's own wording
// for some errors, `TirTypeError::render` from the file's viewpoint for the
// rest.
function source_aware_tir_type_error_message(
    db: root.hir.Db,
    file: int,
    error: root.hir_ty.TirTypeError,
) -> string throws never {
    let ty = (t: root.types.Ty) -> string {
        display_ty_for_file(db, file, t)
    };
    match (error) {
        let e: root.hir_ty.TirTypeErrorTypeMismatch => {
            `type mismatch: expected ${ty(e.expected)}, got ${ty(e.got)}`
        },
        let e: root.hir_ty.TirTypeErrorUnresolvedMember if e.base_type is root.types.TyUnknown => {
            ``cannot access field `${e.member}` on `unknown```
        },
        let e: root.hir_ty.TirTypeErrorUnresolvedMember => {
            ``type `${ty(e.base_type)}` has no member `${e.member}```
        },
        let e: root.hir_ty.TirTypeErrorNotCallable => {
            ``\`${ty(e.ty)}` is not a function — it cannot be called``
        },
        let e: root.hir_ty.TirTypeErrorNotIterable => ``cannot iterate over type `${ty(e.ty)}```,
        let e: root.hir_ty.TirTypeErrorNotIndexable => ``type `${ty(e.ty)}` is not indexable``,
        let e: root.hir_ty.TirTypeErrorInvalidBinaryOp => {
            ``operator `${root.ast.binary_op_display(e.op)}` cannot be applied to `${ty(e.lhs)}` and `${ty(e.rhs)}```
        },
        let e: root.hir_ty.TirTypeErrorInvalidUnaryOp => {
            ``operator `${root.ast.unary_op_display(e.op)}` cannot be applied to `${ty(e.operand)}```
        },
        let e: root.hir_ty.TirTypeErrorOrderingDifferentTypes => {
            ``cannot order `${ty(e.lhs)}` and `${ty(e.rhs)}` with `${root.ast.binary_op_display(e.op)}`: ordering requires both operands to have the same type``
        },
        let e: root.hir_ty.TirTypeErrorOrderingRequiresCompare => {
            ``\`${ty(e.ty)}` does not implement `Compare`, so it cannot be ordered with `${root.ast.binary_op_display(e.op)}```
        },
        let e: root.hir_ty.TirTypeErrorComparisonAlwaysDisjoint => {
            let always = if (e.op == root.ast.BinaryOp.Ne) {
                "true"
            } else {
                "false"
            };
            ``\`${ty(e.lhs)}` and `${ty(e.rhs)}` share no value, so this comparison is always ${always}``
        },
        let e: root.hir_ty.TirTypeErrorNonExhaustiveMatch => {
            if (e.missing_cases.length() == 0) {
                `non-exhaustive match on type ${ty(e.scrutinee_type)}`
            } else {
                `non-exhaustive match on type ${ty(e.scrutinee_type)}; missing: ${e.missing_cases.join(", ")}`
            }
        },
        let e: root.hir_ty.TirTypeErrorNonExhaustiveCatchAll => {
            if (e.missing_cases.length() == 0) {
                `non-exhaustive ${e.keyword} on type ${ty(e.caught_type)}`
            } else {
                `non-exhaustive ${e.keyword} on type ${ty(e.caught_type)}; missing: ${e.missing_cases.join(", ")}`
            }
        },
        let e: root.hir_ty.TirTypeErrorOrPatternBindingTypeMismatch => {
            ``or-pattern binding `${e.name}` has conflicting types: ${ty(e.first_type)} and ${ty(e.other_type)}``
        },
        let e: root.hir_ty.TirTypeErrorThrowsContractViolation => {
            ``declared throws is `${ty(e.declared)}`, but this function may also throw `${ty(e.extra)}```
        },
        let e: root.hir_ty.TirTypeErrorCallbackThrowsContractViolation => {
            let callback_name = e.callback_name;
            let concrete_throws = e.concrete_throws;
            if (concrete_throws != null) {
                ``this body may throw through callback `${callback_name}`, but declared throws is `${ty(e.declared)}`. Add `throws ${ty(concrete_throws)}` to the callback, catch the call, or make the callback non-throwing.``
            } else {
                ``this body may throw through callback `${callback_name}`, but declared throws is `${ty(e.declared)}`. The callback type does not say what it can throw. If `${callback_name}` is an infallible host callback, annotate it with `throws never`; otherwise catch the call or let the enclosing function declare/propagate the callback's throws.``
            }
        },
        // Both spellings that write an interface qualifier report here:
        // `x.as<T>` and `(Base as T).item`.
        let e: root.hir_ty.TirTypeErrorInvalidInterfaceUpcastTarget => {
            `expected an interface qualifier, got ${ty(e.target)}`
        },
        _ => root.hir_ty.tir_type_error_render(error, root.hir_ty.Viewpoint.for_file(db, file)),
    }
}

// port: baml_db/src/check.rs::tir_type_error_to_diagnostic_id @ d9be6853b
// The diagnostic id (its code) a TIR error reports under.
function tir_type_error_to_diagnostic_id(error: root.hir_ty.TirTypeError) -> string throws never {
    match (error) {
        root.hir_ty.TirTypeErrorInvalidTraceHook => root.diagnostics.MALFORMED_ATTRIBUTE,
        root.hir_ty.TirTypeErrorTypeMismatch | root.hir_ty.TirTypeErrorListPatternNeverMatches => {
            root.diagnostics.TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorUnresolvedMember => root.diagnostics.NO_SUCH_FIELD,
        root.hir_ty.TirTypeErrorUnionMemberNoCommonInterface => root.diagnostics.NO_SUCH_FIELD,
        root.hir_ty.TirTypeErrorUnionMemberAssociatedTypeConflict => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorUnknownClassField | root.hir_ty.TirTypeErrorUnknownClassPatternField => {
            root.diagnostics.NO_SUCH_FIELD
        },
        root.hir_ty.TirTypeErrorUnknownClassPropertyShorthand => root.diagnostics.NO_SUCH_FIELD,
        root.hir_ty.TirTypeErrorMissingRequiredClassFields => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorUnresolvedName | root.hir_ty.TirTypeErrorUnresolvedPropertyShorthand => {
            root.diagnostics.UNKNOWN_VARIABLE
        },
        let e: root.hir_ty.TirTypeErrorComputedGenericArgumentRequiresLetType => {
            root.diagnostics.computed_generic_argument_requires_let_type(e.name).id
        },
        let e: root.hir_ty.TirTypeErrorBoundedLetTypeRequiresElse => {
            root.diagnostics.bounded_let_type_requires_else(e.name).id
        },
        root.hir_ty.TirTypeErrorLetTypePendingOperand => {
            root.diagnostics.let_type_pending_operand().id
        },
        let e: root.hir_ty.TirTypeErrorMountedPackageCallUnsupported => {
            root.diagnostics.mounted_package_call_unsupported(e.path).id
        },
        root.hir_ty.TirTypeErrorInvalidAssignmentTarget => root.diagnostics.INVALID_SYNTAX,
        root.hir_ty.TirTypeErrorInvalidRegexPattern => root.diagnostics.INVALID_REGEX_PATTERN,
        root.hir_ty.TirTypeErrorCannotConstructReflectionKind => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorCannotConstructAlias
            | root.hir_ty.TirTypeErrorConstructedTypeParameter =>
        {
            root.diagnostics.TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorCannotConstructBuiltinCompanion => {
            root.diagnostics.CANNOT_CONSTRUCT_BUILTIN_COMPANION
        },
        root.hir_ty.TirTypeErrorDeadCode => root.diagnostics.UNREACHABLE_CODE,
        root.hir_ty.TirTypeErrorConditionAlwaysConstant
            | root.hir_ty.TirTypeErrorUncalledFunctionInCondition =>
        {
            root.diagnostics.CONDITION_ALWAYS_CONSTANT
        },
        root.hir_ty.TirTypeErrorUnitExpected => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorTraceOpaqueValue => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorNotCallable => root.diagnostics.NOT_CALLABLE,
        root.hir_ty.TirTypeErrorNotIterable => root.diagnostics.NOT_CALLABLE,
        root.hir_ty.TirTypeErrorNotIndexable => root.diagnostics.NOT_INDEXABLE,
        root.hir_ty.TirTypeErrorInvalidMapKeyType => root.diagnostics.INVALID_MAP_KEY_TYPE,
        root.hir_ty.TirTypeErrorInvalidBinaryOp => root.diagnostics.INVALID_OPERATOR,
        root.hir_ty.TirTypeErrorOrderingDifferentTypes
            | root.hir_ty.TirTypeErrorOrderingRequiresCompare
            | root.hir_ty.TirTypeErrorComparisonAlwaysDisjoint =>
        {
            root.diagnostics.INVALID_OPERATOR
        },
        root.hir_ty.TirTypeErrorInvalidUnaryOp => root.diagnostics.INVALID_OPERATOR,
        root.hir_ty.TirTypeErrorUnresolvedType => root.diagnostics.UNKNOWN_TYPE,
        root.hir_ty.TirTypeErrorItemShadowsPackage => root.diagnostics.UNKNOWN_VARIABLE,
        root.hir_ty.TirTypeErrorRemovedReflectSpelling => root.diagnostics.REMOVED_FEATURE,
        root.hir_ty.TirTypeErrorNonInterfaceProjectionQualifier => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorTupleElementNotAssignable
            | root.hir_ty.TirTypeErrorFunctionFieldNeedsParens =>
        {
            root.diagnostics.TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorTupleIndexOutOfRange => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorTupleTypeTestNeverMatches => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorUnknownAssociatedType => root.diagnostics.UNKNOWN_TYPE,
        root.hir_ty.TirTypeErrorAmbiguousAssociatedTypeProjection => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorArgumentCountMismatch
            | root.hir_ty.TirTypeErrorPositionalArgumentAfterNamed
            | root.hir_ty.TirTypeErrorDuplicateNamedArgument
            | root.hir_ty.TirTypeErrorUnknownNamedArgument
            | root.hir_ty.TirTypeErrorTraceUnsupportedCall
            | root.hir_ty.TirTypeErrorDefaultedParamPassedPositionally
            | root.hir_ty.TirTypeErrorMissingRequiredArgument =>
        {
            root.diagnostics.ARGUMENT_COUNT_MISMATCH
        },
        root.hir_ty.TirTypeErrorRequiredParamAfterDefault
            | root.hir_ty.TirTypeErrorSelfParamDefault
            | root.hir_ty.TirTypeErrorDefaultParamForwardReference =>
        {
            root.diagnostics.TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorImplicitUnit => root.diagnostics.MISSING_RETURN_EXPRESSION,
        root.hir_ty.TirTypeErrorAliasCycle => root.diagnostics.ALIAS_CYCLE,
        root.hir_ty.TirTypeErrorClassCycle => root.diagnostics.CLASS_CYCLE,
        root.hir_ty.TirTypeErrorNonExhaustiveMatch | root.hir_ty.TirTypeErrorNonExhaustiveCatchAll => {
            root.diagnostics.NON_EXHAUSTIVE_MATCH
        },
        root.hir_ty.TirTypeErrorUnreachableArm => root.diagnostics.UNREACHABLE_ARM,
        root.hir_ty.TirTypeErrorOrPatternBindingTypeMismatch => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorGenericClassDestructureRequiresTypeArgs => {
            root.diagnostics.TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorRestSubPatternNotBinding => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorRefutablePatternInLet => root.diagnostics.REFUTABLE_PATTERN_IN_LET,
        root.hir_ty.TirTypeErrorIrrefutablePatternInIfLet => {
            root.diagnostics.IRREFUTABLE_PATTERN_IN_IF_LET
        },
        root.hir_ty.TirTypeErrorLetElseMustDiverge => root.diagnostics.LET_ELSE_MUST_DIVERGE,
        root.hir_ty.TirTypeErrorIrrefutablePatternInLetElse => {
            root.diagnostics.IRREFUTABLE_PATTERN_IN_LET_ELSE
        },
        root.hir_ty.TirTypeErrorIrrefutablePatternInWhileLet => {
            root.diagnostics.IRREFUTABLE_PATTERN_IN_WHILE_LET
        },
        root.hir_ty.TirTypeErrorInvalidCatchBindingType => {
            root.diagnostics.INVALID_CATCH_BINDING_TYPE
        },
        root.hir_ty.TirTypeErrorDeferControlFlowEscape => root.diagnostics.DEFER_CONTROL_FLOW_ESCAPE,
        root.hir_ty.TirTypeErrorLoopControlOutsideLoop => root.diagnostics.LOOP_CONTROL_OUTSIDE_LOOP,
        root.hir_ty.TirTypeErrorLoopControlInLoopHeader => {
            root.diagnostics.LOOP_CONTROL_IN_LOOP_HEADER
        },
        root.hir_ty.TirTypeErrorThrowsContractViolation
            | root.hir_ty.TirTypeErrorCallbackThrowsContractViolation =>
        {
            root.diagnostics.THROWS_CONTRACT_VIOLATION
        },
        root.hir_ty.TirTypeErrorExtraneousThrowsDeclaration
            | root.hir_ty.TirTypeErrorImpreciseUnknownThrows =>
        {
            root.diagnostics.THROWS_CONTRACT_EXTRANEOUS
        },
        root.hir_ty.TirTypeErrorCannotInferTypeParameter
            | root.hir_ty.TirTypeErrorCannotInferAssociatedType
            | root.hir_ty.TirTypeErrorConflictingTypeArguments =>
        {
            root.diagnostics.UNKNOWN_TYPE
        },
        root.hir_ty.TirTypeErrorCannotInferLambdaParamType => root.diagnostics.UNKNOWN_TYPE,
        root.hir_ty.TirTypeErrorWrongNumberOfTypeArgs => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorTypeIsNotGeneric => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorGenericFunctionValueNotSpecialized => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorWrongTypeArgArity => root.diagnostics.ARGUMENT_COUNT_MISMATCH,
        root.hir_ty.TirTypeErrorScopedTypeEscapesBlock => root.diagnostics.SCOPED_TYPE_ESCAPES_BLOCK,
        root.hir_ty.TirTypeErrorCannotConstructOpaqueClass => {
            root.diagnostics.CANNOT_CONSTRUCT_OPAQUE_CLASS
        },
        root.hir_ty.TirTypeErrorCallSiteBuiltinValue => root.diagnostics.CALL_SITE_BUILTIN_VALUE,
        // Optional chaining diagnostics.
        root.hir_ty.TirTypeErrorUnnecessaryOptionalChaining => root.diagnostics.INVALID_OPERATOR,
        root.hir_ty.TirTypeErrorUnnecessaryNullCoalesce => root.diagnostics.INVALID_OPERATOR,
        root.hir_ty.TirTypeErrorSuggestNullCoalesce => root.diagnostics.INVALID_OPERATOR,
        root.hir_ty.TirTypeErrorNullCoalesceWithNull => root.diagnostics.INVALID_OPERATOR,
        root.hir_ty.TirTypeErrorNullableMemberAccess => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorTaggedTagNotAFunction => root.diagnostics.NOT_CALLABLE,
        root.hir_ty.TirTypeErrorTaggedTagNotMarked | root.hir_ty.TirTypeErrorTaggedTagBadBodyParam => {
            root.diagnostics.TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorInterpolatedValueMaybeNull
            | root.hir_ty.TirTypeErrorRoleMarkerInUntaggedTemplate
            | root.hir_ty.TirTypeErrorOutputFormatNotCalled =>
        {
            root.diagnostics.TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorAmbiguousInterfaceMethod => {
            root.diagnostics.AMBIGUOUS_INTERFACE_METHOD
        },
        root.hir_ty.TirTypeErrorAmbiguousInterfaceField => {
            root.diagnostics.AMBIGUOUS_INTERFACE_FIELD
        },
        root.hir_ty.TirTypeErrorInterfaceFieldRequiresProjection => root.diagnostics.NO_SUCH_FIELD,
        root.hir_ty.TirTypeErrorInterfaceFieldRequiresQualifiedConstruction => {
            root.diagnostics.NO_SUCH_FIELD
        },
        root.hir_ty.TirTypeErrorInvalidInterfaceUpcastTarget => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorInterfaceMemberRequiresReceiver => root.diagnostics.NO_SUCH_FIELD,
        root.hir_ty.TirTypeErrorInvalidSelfCallThroughInterface => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorSelflessMethodNeedsConcreteSelf => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorSelflessInstanceMember => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorErasedSelfMethodValue => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorDefaultOnRequiredMethod => {
            root.diagnostics.DEFAULT_ON_REQUIRED_METHOD
        },
        root.hir_ty.TirTypeErrorBareDefaultKeyword => root.diagnostics.BARE_DEFAULT_KEYWORD,
        root.hir_ty.TirTypeErrorTypeDoesNotImplementInterface => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorBlanketBoundNotSatisfied => root.diagnostics.TYPE_MISMATCH,
        root.hir_ty.TirTypeErrorIntegerLiteralOutOfRange => {
            root.diagnostics.INTEGER_LITERAL_OUT_OF_RANGE
        },
        root.hir_ty.TirTypeErrorGenericBoundNotInterface => {
            root.diagnostics.GENERIC_BOUND_NOT_INTERFACE
        },
        // Builtin interfaces (E0153/E0154).
        root.hir_ty.TirTypeErrorBuiltinInterfaceNotImplementable => {
            root.diagnostics.BUILTIN_INTERFACE_NOT_IMPLEMENTABLE
        },
        root.hir_ty.TirTypeErrorBuiltinInterfaceNotABound => {
            root.diagnostics.BUILTIN_INTERFACE_NOT_A_BOUND
        },
        // A `_` placeholder in a non-inferable position.
        root.hir_ty.TirTypeErrorCannotInferType
            | root.hir_ty.TirTypeErrorWildcardInProjectionSubject =>
        {
            root.diagnostics.WILDCARD_TYPE_NOT_ALLOWED
        },
        root.hir_ty.TirTypeErrorTypeMustBeKnown => root.diagnostics.TYPE_MUST_BE_KNOWN,
        root.hir_ty.TirTypeErrorReceiverTypeMustBeKnown => root.diagnostics.TYPE_MUST_BE_KNOWN,
        root.hir_ty.TirTypeErrorAmbiguousImplementation => root.diagnostics.TYPE_MUST_BE_KNOWN,
        // Generic-parameter / associated-type declaration hygiene.
        root.hir_ty.TirTypeErrorTypeParamShadowed
            | root.hir_ty.TirTypeErrorTypeParamShadowedImplParam
            | root.hir_ty.TirTypeErrorDuplicateGenericParam
            | root.hir_ty.TirTypeErrorDuplicateAssociatedType
            | root.hir_ty.TirTypeErrorAssociatedTypeConflictsWithGenericParam =>
        {
            root.diagnostics.DUPLICATE_FIELD
        },
        // Generic type-argument constraints.
        root.hir_ty.TirTypeErrorBoundedTypeArgNotConcrete
            | root.hir_ty.TirTypeErrorMissingAssociatedTypeBindings
            | root.hir_ty.TirTypeErrorAmbiguousInterfacePatternBindings =>
        {
            root.diagnostics.TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorInterfaceProjectionBase => {
            root.diagnostics.INTERFACE_PROJECTION_BASE
        },
        // `$init` effect rules.
        root.hir_ty.TirTypeErrorInitIoNotAllowed => root.diagnostics.INIT_IO_NOT_ALLOWED,
        root.hir_ty.TirTypeErrorInitSuspendNotAllowed => root.diagnostics.INIT_SUSPEND_NOT_ALLOWED,
        root.hir_ty.TirTypeErrorInitThrowNotHandled => root.diagnostics.INIT_THROW_NOT_HANDLED,
        root.hir_ty.TirTypeErrorLlmOutputMemberDropped => root.diagnostics.LLM_OUTPUT_MEMBER_DROPPED,
        root.hir_ty.TirTypeErrorLlmOutputFieldAlwaysNull => {
            root.diagnostics.LLM_OUTPUT_FIELD_ALWAYS_NULL
        },
        root.hir_ty.TirTypeErrorJsonAttributesWithOverride
            | root.hir_ty.TirTypeErrorJsonRestFieldType
            | root.hir_ty.TirTypeErrorJsonRestRenamed
            | root.hir_ty.TirTypeErrorJsonRestRepeated
            | root.hir_ty.TirTypeErrorJsonAttributeSkipped
            | root.hir_ty.TirTypeErrorJsonFallbackFieldNotLiteral
            | root.hir_ty.TirTypeErrorJsonFallbackNoTag
            | root.hir_ty.TirTypeErrorJsonFallbackUntaggedMember
            | root.hir_ty.TirTypeErrorJsonFallbackOverlap =>
        {
            root.diagnostics.INVALID_JSON_ATTRIBUTE
        },
        // Global variables.
        root.hir_ty.TirTypeErrorAssignmentToGlobal => root.diagnostics.ASSIGNMENT_TO_GLOBAL,
        root.hir_ty.TirTypeErrorReturnOutsideFunctionBody => {
            root.diagnostics.RETURN_OUTSIDE_FUNCTION_BODY
        },
        root.hir_ty.TirTypeErrorGlobalInitializationCycle => {
            root.diagnostics.GLOBAL_INITIALIZATION_CYCLE
        },
        // Interface impl conformance (E0113 to E0139), surfaced by
        // `check_interfaces`.
        root.hir_ty.TirTypeErrorMissingInterfaceMethod => root.diagnostics.MISSING_INTERFACE_METHOD,
        root.hir_ty.TirTypeErrorGenericSysOpMethodInInterfaceImpl => {
            root.diagnostics.GENERIC_SYS_OP_METHOD_IN_INTERFACE_IMPL
        },
        root.hir_ty.TirTypeErrorOutOfBodyImplementsFieldInterface => {
            root.diagnostics.OUT_OF_BODY_IMPLEMENTS_FIELD_INTERFACE
        },
        root.hir_ty.TirTypeErrorUnknownInterfaceMember => root.diagnostics.UNKNOWN_INTERFACE_MEMBER,
        root.hir_ty.TirTypeErrorMissingInterfaceField => root.diagnostics.MISSING_INTERFACE_FIELD,
        root.hir_ty.TirTypeErrorInterfaceFieldTypeMismatch => {
            root.diagnostics.INTERFACE_FIELD_TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorInterfaceMethodSignatureMismatch
            | root.hir_ty.TirTypeErrorInterfaceMethodAddsGenericBound =>
        {
            root.diagnostics.INTERFACE_METHOD_SIGNATURE_MISMATCH
        },
        root.hir_ty.TirTypeErrorMissingRequiredInterface => {
            root.diagnostics.MISSING_REQUIRED_INTERFACE
        },
        root.hir_ty.TirTypeErrorImplTargetNotInterface => root.diagnostics.NOT_AN_INTERFACE,
        root.hir_ty.TirTypeErrorImplTargetNotConcrete => root.diagnostics.IMPL_TARGET_NOT_CONCRETE,
        root.hir_ty.TirTypeErrorUnconstrainedImplTypeParam => {
            root.diagnostics.UNCONSTRAINED_IMPL_TYPE_PARAM
        },
        root.hir_ty.TirTypeErrorImplViolatesOrphanRule => root.diagnostics.IMPL_VIOLATES_ORPHAN_RULE,
        root.hir_ty.TirTypeErrorUnknownInterfaceFieldLink => {
            root.diagnostics.UNKNOWN_INTERFACE_FIELD_LINK
        },
        root.hir_ty.TirTypeErrorUnknownClassFieldInInterfaceLink => {
            root.diagnostics.UNKNOWN_CLASS_FIELD_IN_INTERFACE_LINK
        },
        root.hir_ty.TirTypeErrorDuplicateInterfaceFieldLink => {
            root.diagnostics.DUPLICATE_INTERFACE_FIELD_LINK
        },
        root.hir_ty.TirTypeErrorSelfInInterfaceField => root.diagnostics.SELF_IN_INTERFACE_FIELD,
        root.hir_ty.TirTypeErrorSelfInAssociatedTypeDefault => {
            root.diagnostics.SELF_IN_ASSOCIATED_TYPE_DEFAULT
        },
        root.hir_ty.TirTypeErrorInterfaceRequiresNonInterface => {
            root.diagnostics.INTERFACE_REQUIRES_NON_INTERFACE
        },
        // The `requires` graph is the successor to `extends`; it shares E0118.
        root.hir_ty.TirTypeErrorInterfaceRequiresCycle => root.diagnostics.INTERFACE_EXTENDS_CYCLE,
        // Associated-binding hygiene and cyclic impl headers have no
        // dedicated codes yet: generic type errors.
        root.hir_ty.TirTypeErrorUnknownAssociatedTypeBinding
            | root.hir_ty.TirTypeErrorDuplicateAssociatedTypeBinding
            | root.hir_ty.TirTypeErrorMissingImplAssociatedTypeBinding
            | root.hir_ty.TirTypeErrorAssociatedTypeBindingsOnImplementsTarget
            | root.hir_ty.TirTypeErrorAssociatedTypeBindingViolatesBound
            | root.hir_ty.TirTypeErrorAssociatedTypeDefaultViolatesBound
            | root.hir_ty.TirTypeErrorCyclicImplHeader =>
        {
            root.diagnostics.TYPE_MISMATCH
        },
        root.hir_ty.TirTypeErrorInterfaceMethodMissingThrows => {
            root.diagnostics.INTERFACE_METHOD_MISSING_THROWS
        },
        root.hir_ty.TirTypeErrorFunctionTypeMissingThrows => {
            root.diagnostics.FUNCTION_TYPE_MISSING_THROWS
        },
    }
}

// port: baml_db/src/check.rs::display_ty_for_file @ d9be6853b
// `ty` as seen from `file` (`Viewpoint.for_file`): the type printer every
// diagnostic message produced by `check_file` uses.
function display_ty_for_file(db: root.hir.Db, file: int, ty: root.types.Ty) -> string throws never {
    root.hir_ty.ty_spell(ty, root.hir_ty.Viewpoint.for_file(db, file))
}

// port: bex_project/src/runtime_compile.rs::owned_diagnostic @ d9be6853b
// A `Diagnostic` as reflection reports it (`reflect.Diagnostic`): the
// headline plus a distinct primary label as `message`, every annotation (the
// primary included) and related location in its own file.
// Restructured: the non-session path only (no name demangling), and a file
// is named by `db.file(id).path`, as the other diagnostics here are; Rust's
// `runtime_relative_virtual_path` strips a virtual root this port does not
// use.
function owned_diagnostic(
    db: root.hir.Db,
    diagnostic: root.diagnostics.Diagnostic,
) -> reflect.Diagnostic throws never {
    let owned_span = (span: root.base.Span) -> reflect.Span {
        reflect.Span {
            file: db.file(span.file_id).path,
            start: span.range.start,
            end: span.range.end,
        }
    };
    let primary = diagnostic.annotations.find((a) -> {
        a.is_primary
    });
    reflect.Diagnostic {
        code: diagnostic.id,
        span: if (primary != null) {
            owned_span(primary.span)
        } else {
            null
        },
        message: diagnostic.message_with_primary_label(),
        severity: match (diagnostic.severity) {
            root.base.Severity.Error => "error",
            root.base.Severity.Warning => "warning",
            root.base.Severity.Info => "info",
        },
        phase: match (diagnostic.phase) {
            root.hir.DiagnosticPhase.Parse => "parse",
            root.hir.DiagnosticPhase.Hir => "hir",
            root.hir.DiagnosticPhase.Validation => "validation",
            root.hir.DiagnosticPhase.Type => "type",
        },
        headline: diagnostic.message,
        primary_label: primary?.message,
        message_highlights: diagnostic.message_highlights.map(owned_highlight),
        annotations: diagnostic.annotations.map((a) -> {
            reflect.DiagnosticAnnotation {
                span: owned_span(a.span),
                message: a.message,
                message_highlights: a.message_highlights.map(owned_highlight),
                is_primary: a.is_primary,
            }
        }),
        related_info: diagnostic.related_info.map((related) -> {
            reflect.DiagnosticRelatedInfo {
                span: owned_span(related.span),
                message: related.message,
                message_highlights: related.message_highlights.map(owned_highlight),
                file_path: related.file_path,
            }
        }),
    }
}

// port: bex_project/src/runtime_compile.rs::owned_diagnostic::highlight_kind @ d9be6853b
// A highlight as reflection reports it, its kind by name.
function owned_highlight(
    highlight: root.diagnostics.DiagnosticMessageHighlight,
) -> reflect.DiagnosticHighlight throws never {
    let kind: "identifier.type"
        | "identifier.function"
        | "identifier.field"
        | "identifier.variable"
        | "identifier.enum_variant"
        | "identifier.attribute"
        | "type_expression"
        | "code" = match (highlight.kind) {
        let k: root.diagnostics.DiagnosticMessageKindIdentifier => {
            match (k.value) {
                root.diagnostics.DiagnosticIdentifierKind.Type => "identifier.type",
                root.diagnostics.DiagnosticIdentifierKind.Function => "identifier.function",
                root.diagnostics.DiagnosticIdentifierKind.Field => "identifier.field",
                root.diagnostics.DiagnosticIdentifierKind.Variable => "identifier.variable",
                root.diagnostics.DiagnosticIdentifierKind.EnumVariant => "identifier.enum_variant",
                root.diagnostics.DiagnosticIdentifierKind.Attribute => "identifier.attribute",
            }
        },
        root.diagnostics.DiagnosticMessageKindTypeExpression => "type_expression",
        root.diagnostics.DiagnosticMessageKindCode => "code",
    };
    reflect.DiagnosticHighlight { start: highlight.start, end: highlight.end, kind: kind }
}
