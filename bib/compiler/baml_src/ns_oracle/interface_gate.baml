// The interface gate (bib/PORTING.md, "TIR plan"): the Type diagnostics the
// `implements` checks report, ours vs the Rust compiler's.
//
//   baml run oracle.interface_gate_summary
//
// Ours: `check_interfaces` (check_types.baml) of every workspace file:
// coherence overlaps (E0132) and each impl's `impl_data` and
// `validate_impl_signatures` diagnostics, mapped onto source spans.
//
// Rust's share: a Type-phase diagnostic whose code is one those checks
// report under AND whose primary span is an impl position: an `implements`
// block's span, a type reference in its own store, a field-link side, an
// associated-binding name, or an override method's span. The positions come
// from HIR's source maps, not from `impl_data_source_map`, so a wrong span on
// our side shows as a mismatch instead of hiding Rust's diagnostic. The same
// filter is applied to ours.
//
// A unit runs in its own task: a stub that panics stops that unit only, and
// is counted with its message.

// The codes the interface checks report under: every `TirTypeError`
// `impl_data` and `validate_impl_signatures` build (the interface-target and
// for-target lowering errors included), mapped by the message layer, plus
// E0132.
function interface_codes() -> string[] throws never {
    let decl = root.types.DeclName { pkg: 0, namespace: [], name: "X" };
    let ty = root.types.TyError {};
    let iface = root.types.InterfaceConstraint { name: decl, generics: [], associated_types: [] };
    let errors: root.hir_ty.TirTypeError[] = [
        root.hir_ty.TirTypeErrorImplTargetNotInterface { name: "X" },
        root.hir_ty.TirTypeErrorBuiltinInterfaceNotImplementable { interface_: decl },
        root.hir_ty.TirTypeErrorOutOfBodyImplementsFieldInterface { interface_: decl },
        root.hir_ty.TirTypeErrorMissingInterfaceMethod { interface_: decl, method: "m" },
        root.hir_ty.TirTypeErrorUnknownInterfaceMember { interface_: decl, member: "m" },
        root.hir_ty.TirTypeErrorDuplicateInterfaceFieldLink { interface_: decl, field: "f" },
        root.hir_ty.TirTypeErrorUnknownInterfaceFieldLink { interface_: decl, field: "f" },
        root.hir_ty.TirTypeErrorUnknownClassFieldInInterfaceLink {
            class_: "C",
            interface_: decl,
            field: "f",
        },
        root.hir_ty.TirTypeErrorMissingInterfaceField { interface_: decl, field: "f" },
        root.hir_ty.TirTypeErrorDuplicateAssociatedTypeBinding { interface_: decl, name: "A" },
        root.hir_ty.TirTypeErrorUnknownAssociatedTypeBinding { interface_: decl, name: "A" },
        root.hir_ty.TirTypeErrorMissingImplAssociatedTypeBinding { interface_: decl, name: "A" },
        root.hir_ty.TirTypeErrorAssociatedTypeBindingsOnImplementsTarget { interface_: decl },
        root.hir_ty.TirTypeErrorCyclicImplHeader {},
        root.hir_ty.TirTypeErrorUnconstrainedImplTypeParam { name: "T" },
        root.hir_ty.TirTypeErrorImplTargetNotConcrete { target: ty },
        root.hir_ty.TirTypeErrorImplViolatesOrphanRule { interface_: decl, uncovered_param: null },
        root.hir_ty.TirTypeErrorMissingRequiredInterface { interface_: decl, required: iface },
        root.hir_ty.TirTypeErrorAssociatedTypeBindingViolatesBound {
            interface_: decl,
            name: "A",
            binding: ty,
            bound: iface,
        },
        root.hir_ty.TirTypeErrorInterfaceFieldTypeMismatch {
            interface_: decl,
            field: "f",
            expected: ty,
            got: ty,
        },
        root.hir_ty.TirTypeErrorGenericSysOpMethodInInterfaceImpl { interface_: decl, method: "m" },
        root.hir_ty.TirTypeErrorInterfaceMethodSignatureMismatch {
            interface_: decl,
            method: "m",
            expected: ty,
            got: ty,
        },
        root.hir_ty.TirTypeErrorInterfaceMethodAddsGenericBound {
            interface_: decl,
            method: "m",
            param: "T",
            bound: iface,
        },
        root.hir_ty.TirTypeErrorDuplicateGenericParam { name: "T" },
        root.hir_ty.TirTypeErrorTypeDoesNotImplementInterface { value_type: ty, interface_: ty },
        root.hir_ty.TirTypeErrorUnknownAssociatedType {
            member: "A",
            container: root.hir_ty.AssocContainerTy { value: ty },
        },
        root.hir_ty.TirTypeErrorAmbiguousAssociatedTypeProjection { member: "A", candidates: [] },
        root.hir_ty.TirTypeErrorNonInterfaceProjectionQualifier {},
    ];
    let codes: string[] = [root.diagnostics.OVERLAPPING_IMPLEMENTS];
    for (let code in decl_lowering_codes()) {
        if (!codes.includes(code)) {
            codes.push(code);
        }
    }
    for (let error in errors) {
        let code = root.tir_type_error_to_diagnostic_id(error);
        if (!codes.includes(code)) {
            codes.push(code);
        }
    }
    codes
}

// `path:start-end` of every impl position of `file`.
function impl_positions(db: root.hir.Db, file: int, out: map<string, bool>) -> void throws never {
    let path = db.file(file).path;
    let add = (range: root.syntax.TextRange) -> void {
        out[`${path}:${range.start}-${range.end}`] = true;
    };
    for (let block in root.hir.file_impls(db, file)) {
        let source_map = root.hir.impl_block_source_map(db, block);
        add(source_map.span);
        source_map.type_refs.spans.for_each(add);
        for (let link in source_map.field_links) {
            add(link.interface_field_span);
            add(link.class_field_span);
        }
        for (let binding in source_map.associated_type_bindings) {
            add(binding.name_span);
        }
        for (let method in root.hir.impl_block_data(db, block).methods) {
            add(root.hir.function_source_map(db, method).span);
        }
    }
}

// One unit: `files` as a new workspace of `db`.
function compare_interfaces(
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
        impl_positions(db, file, positions);
    }
    let in_scope = (d: reflect.Diagnostic) -> bool {
        let span = d.span;
        span != null
            && codes.includes(d.code)
            && positions.has(`${span.file ?? ""}:${span.start}-${span.end}`)
    };
    // Nothing to compare in a unit with no impl.
    if (positions.length() == 0) {
        return DeclComparison { rust: [], ours: [] };
    }
    let ours = file_ids
        .flat_map((file) -> {
            root.check_interfaces(db, file).map((d) -> {
                root.owned_diagnostic(db, d)
            })
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

function interface_gate(
    dir: string,
    unit: CorpusUnit,
) -> DeclGateReport throws baml.errors.Io | baml.errors.ParseError {
    let paths = baml.glob.new("**/*.baml").scan(dir);
    let codes = interface_codes();
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
        let task: baml.future.Future<DeclComparison, never> = spawn { compare_interfaces(unit_db, files, codes) };
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

// One line per corpus, then the first `limit` mismatches and every panic.
function interface_gate_summary(
    limit: int = 10,
) -> string throws baml.errors.Io | baml.errors.ParseError {
    DECL_GATE_CORPORA
        .map((corpus) -> {
            let r = interface_gate(corpus.0, corpus.1);
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
