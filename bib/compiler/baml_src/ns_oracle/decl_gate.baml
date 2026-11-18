// The declaration gate (bib/PORTING.md, "TIR plan", after K1): the Type
// diagnostics the declaration lowering reports, ours vs the Rust compiler's.
//
//   baml run oracle.decl_gate_summary
//
// Ours: `signature_lowering_diagnostics`, `let_lowering_diagnostics`,
// `class_lowering_diagnostics`, `interface_lowering_diagnostics` and
// `type_alias_lowering_diagnostics` of every workspace file, rendered through
// the check.rs message layer (`tir_rendered_to_diagnostic_for_file`) as
// `check_file` does.
//
// Rust's share: a Type-phase diagnostic whose code is one these functions
// report under AND whose primary span is a declaration position they report
// at: a span of a type reference in an item's own store (signature, written
// and elaborated; class; interface; alias; global annotation), or an item's
// name. Body diagnostics never land on those spans (a body's type references
// live in the body's store), and the other declaration checks that do
// (`@json`, LLM-output, cleanup, impl conformance) report under other codes.
// The same filter is applied to ours.
//
// A unit runs in its own task: a stub that panics stops that unit only, and
// is counted with its message.

// The codes the declaration lowering reports under: every `TirTypeError` it
// builds, mapped by the message layer.
function decl_lowering_codes() -> string[] throws never {
    let decl = root.types.DeclName { pkg: 0, namespace: [], name: "X" };
    let ty = root.types.TyError {};
    let iface = root.types.InterfaceConstraint { name: decl, generics: [], associated_types: [] };
    let errors: root.hir_ty.TirTypeError[] = [
        root.hir_ty.TirTypeErrorUnresolvedType { name: "X", suggestions: [] },
        root.hir_ty.TirTypeErrorRemovedReflectSpelling {
            written: "type",
            replacement: "reflect.Type",
            mentions_type_keyword: true,
        },
        root.hir_ty.TirTypeErrorWrongNumberOfTypeArgs { type_name: "X", expected: 0, got: 1 },
        root.hir_ty.TirTypeErrorInvalidMapKeyType { key: ty },
        root.hir_ty.TirTypeErrorFunctionTypeMissingThrows {},
        root.hir_ty.TirTypeErrorCannotInferType {},
        root.hir_ty.TirTypeErrorWildcardInProjectionSubject {},
        root.hir_ty.TirTypeErrorBuiltinInterfaceNotABound { interface_: decl },
        root.hir_ty.TirTypeErrorGenericBoundNotInterface { bound: ty },
        root.hir_ty.TirTypeErrorTypeParamShadowed {
            param_name: "T",
            type_name: "X",
            owner: root.hir_ty.ShadowedParamOwner.Class,
        },
        root.hir_ty.TirTypeErrorTypeParamShadowedImplParam { param_name: "T" },
        root.hir_ty.TirTypeErrorAssociatedTypeBindingViolatesBound {
            interface_: decl,
            name: "A",
            binding: ty,
            bound: iface,
        },
        root.hir_ty.TirTypeErrorAssociatedTypeDefaultViolatesBound {
            interface_: decl,
            name: "A",
            default_: ty,
            bound: iface,
        },
        root.hir_ty.TirTypeErrorInterfaceMethodMissingThrows { interface_: decl, method: "m" },
        root.hir_ty.TirTypeErrorInterfaceRequiresCycle { chain: [] },
        root.hir_ty.TirTypeErrorInterfaceRequiresNonInterface { interface_: decl, target: ty },
        root.hir_ty.TirTypeErrorAliasCycle { name: "X" },
        root.hir_ty.TirTypeErrorDuplicateAssociatedTypeBinding { interface_: decl, name: "A" },
        root.hir_ty.TirTypeErrorMissingAssociatedTypeBindings { interface_: decl, missing: [] },
        root.hir_ty.TirTypeErrorInterfaceProjectionBase { interface_: decl, member: "A" },
        root.hir_ty.TirTypeErrorItemShadowsPackage { name: "x" },
    ];
    let codes: string[] = [];
    for (let error in errors) {
        let code = root.tir_type_error_to_diagnostic_id(error);
        if (!codes.includes(code)) {
            codes.push(code);
        }
    }
    codes
}

// `path:start-end` of every declaration position of `file`.
function decl_positions(db: root.hir.Db, file: int, out: map<string, bool>) -> void throws never {
    let path = db.file(file).path;
    let add = (range: root.syntax.TextRange) -> void {
        out[`${path}:${range.start}-${range.end}`] = true;
    };
    let add_all = (map: root.hir.TypeRefSourceMap) -> void {
        map.spans.for_each(add);
    };
    for (let f in root.hir.file_functions(db, file)) {
        let source_map = root.hir.function_source_map(db, f);
        add(source_map.name_span);
        add_all(source_map.type_refs);
        add_all(root.hir.elaborated_function_source_map(db, f).type_refs);
    }
    for (let c in root.hir.file_classes(db, file)) {
        let source_map = root.hir.class_source_map(db, c);
        add(source_map.name_span);
        add_all(source_map.type_refs);
    }
    for (let i in root.hir.file_interfaces(db, file)) {
        let source_map = root.hir.interface_source_map(db, i);
        add(source_map.name_span);
        add_all(source_map.type_refs);
        source_map.required_method_spans.for_each((sig) -> {
            add(sig.name_span)
        });
    }
    for (let a in root.hir.file_type_aliases(db, file)) {
        let source_map = root.hir.type_alias_source_map(db, a);
        add(source_map.name_span);
        add_all(source_map.type_refs);
    }
    for (let l in root.hir.file_lets(db, file)) {
        add_all(root.hir.let_source_map(db, l).type_refs);
    }
}

// Our declaration lowering diagnostics of `file`, in `check_file`'s order.
function our_decl_diagnostics(db: root.hir.Db, file: int) -> reflect.Diagnostic[] throws never {
    let vp = root.hir_ty.Viewpoint.for_file(db, file);
    let found: (root.syntax.TextRange, root.hir_ty.TirTypeError)[] = [];
    for (let f in root.hir.file_functions(db, file)) {
        root.base.extend(found, root.hir_ty.signature_lowering_diagnostics(db, f));
    }
    for (let l in root.hir.file_lets(db, file)) {
        root.base.extend(found, root.hir_ty.let_lowering_diagnostics(db, l));
    }
    for (let c in root.hir.file_classes(db, file)) {
        root.base.extend(found, root.hir_ty.class_lowering_diagnostics(db, c));
    }
    for (let i in root.hir.file_interfaces(db, file)) {
        root.base.extend(found, root.hir_ty.interface_lowering_diagnostics(db, i));
    }
    for (let a in root.hir.file_type_aliases(db, file)) {
        root.base.extend(found, root.hir_ty.type_alias_lowering_diagnostics(db, a));
    }
    found.map((entry) -> {
        let rendered = root.hir_ty.RenderedTirDiagnostic {
            error: entry.1,
            message: root.hir_ty.tir_type_error_render(entry.1, vp),
            range: entry.0,
            severity: root.hir_ty.DiagnosticSeverity.Error,
            related: [],
        };
        root.owned_diagnostic(db, root.tir_rendered_to_diagnostic_for_file(db, file, rendered))
    })
}

class DeclComparison {
    rust: string[],
    ours: string[],
}

// One unit: `files` as a new workspace of `db`.
function compare_decl(
    db: root.hir.Db,
    files: map<string, string>,
    codes: string[],
) -> DeclComparison throws never {
    let workspace = root.db.add_root(db, "", root.base.SourceRootKind.Workspace, null, []);
    for (let path in files.keys()) {
        root.db.add_file(db, workspace, path, files[path]);
    }
    let file_ids = db.source_root(workspace).files;
    let positions: map<string, bool> = {};
    for (let file in file_ids) {
        decl_positions(db, file, positions);
    }
    let in_scope = (d: reflect.Diagnostic) -> bool {
        let span = d.span;
        span != null
            && codes.includes(d.code)
            && positions.has(`${span.file ?? ""}:${span.start}-${span.end}`)
    };
    let ours = file_ids
        .flat_map((file) -> {
            our_decl_diagnostics(db, file)
        })
        .filter(in_scope)
        .map(diagnostic_key);
    let rust = rust_diagnostics(files)
        .filter((d) -> {
            d.phase == "type" && in_scope(d)
        })
        .map(diagnostic_key);
    ours.sort_by((a, b) -> {
        a.cmp(b)
    });
    rust.sort_by((a, b) -> {
        a.cmp(b)
    });
    DeclComparison { rust: rust, ours: ours }
}

class DeclGateReport {
    corpus: string,
    units: int,
    matched: int,
    // Units with at least one in-scope diagnostic on either side.
    nonempty: int,
    rust_total: int,
    ours_total: int,
    mismatches: CorpusMismatch[],
    // Units a panicking stub stopped, with the panic.
    panicked: (string, string)[],
}

function decl_gate(
    dir: string,
    unit: CorpusUnit,
) -> DeclGateReport throws baml.errors.Io | baml.errors.ParseError {
    let paths = baml.glob.new("**/*.baml").scan(dir);
    let codes = decl_lowering_codes();
    let db = root.stdlib_db();
    let report = DeclGateReport {
        corpus: dir,
        units: 0,
        matched: 0,
        nonempty: 0,
        rust_total: 0,
        ours_total: 0,
        mismatches: [],
        panicked: [],
    };
    for (let group in corpus_units(paths, unit)) {
        let files: map<string, string> = {};
        for (let path in group.paths) {
            files[path.slice(group.prefix.length(), path.length())] = baml.fs.read(`${dir}/${path}`);
        }
        report.units += 1;
        let unit_db = db;
        let task: baml.future.Future<DeclComparison, never> = spawn { compare_decl(unit_db, files, codes) };
        let settled = await baml.future.all_settled([task]);
        match (settled[0]) {
            let ok: baml.future.Success<DeclComparison> => {
                let comparison = ok.value;
                report.rust_total += comparison.rust.length();
                report.ours_total += comparison.ours.length();
                if (comparison.rust.length() + comparison.ours.length() > 0) {
                    report.nonempty += 1;
                }
                if (comparison.rust == comparison.ours) {
                    report.matched += 1;
                } else {
                    report.mismatches.push(
                        CorpusMismatch {
                            path: group.name,
                            rust: comparison.rust,
                            ours: comparison.ours,
                        },
                    );
                }
            },
            let panicked: baml.future.Panicked => {
                report.panicked.push((group.name, `${panicked.panic}`));
                // The Db's tracked-query stack is left mid-query: start over.
                db = root.stdlib_db();
            },
            _ => {
                report.panicked.push((group.name, "failed"));
                db = root.stdlib_db();
            },
        }
    }
    report
}

const DECL_GATE_CORPORA: (string, CorpusUnit)[] = [
    ("../../baml_language/crates/baml_tests/projects/broken_syntax", "project"),
    ("../../baml_language/crates/baml_tests/projects/diagnostic_errors", "project"),
    ("../../baml_language/crates/baml_tests/projects/parser_stress", "project"),
    ("../../baml_language/crates/baml_tests/baml_src", "whole"),
];

// One line per corpus, then the first `limit` mismatches and every panic.
function decl_gate_summary(
    limit: int = 10,
) -> string throws baml.errors.Io | baml.errors.ParseError {
    DECL_GATE_CORPORA
        .map((corpus) -> {
            let r = decl_gate(corpus.0, corpus.1);
            let head = `${r.corpus}: ${r.matched}/${r.units} units match (${r.nonempty} with in-scope diagnostics; rust ${r.rust_total}, ours ${r.ours_total}), ${r.mismatches.length()} mismatches, ${r.panicked.length()} panicked`;
            let shown = r.mismatches.slice(0, limit).map((m) -> {
                `  ${m.path}\n    rust: ${m.rust.join("\n          ")}\n    ours: ${m.ours.join("\n          ")}`
            });
            let panics = r.panicked.map((p) -> {
                `  PANIC ${p.0}: ${p.1.slice(0, 200)}`
            });
            [head].concat(shown).concat(panics).join("\n")
        })
        .join("\n")
}
