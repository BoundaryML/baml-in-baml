// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs @ d9be6853b
//
// The `implements` substrate: one block resolved to its `ImplData` (every
// spelling normalized to the free shape), its span sidecar, the phase-5
// signature/type conformance checks, and the realized `(interface, type)`
// to impl lookups built on them.
//
// Restructured (BAML forces it):
// - Rust's `Result<ImplData, ImplDataError>` is the union
//   `ImplData | ImplDataError`, a memoizable value like Rust's cached result.
// - `get_implements_block` and `get_implements_block_within_depth` are one
//   function with `depth = BLANKET_IMPL_BOUND_DEPTH`.
// - `impl FnMut(&Ty, &Ty) -> bool` parameters are function values; the
//   `realize_with_symbolic_self` `lower` callback takes the scope.
// - `SigTypeRef` and `OrphanOutcome` are unions of classes.
// - `impl_data_cycle_result` drops salsa's `Id` parameter.
// - `baml_compiler2_hir::item_data::impl_enclosing_class` is not ported in
//   HIR; its callers read `root.hir.impl_class` directly.
//
// Not ported: the `InterfaceMethodSpec::generic_bounds` and `bound_store`
// accessors (read `generics` / `bound_refs`).

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::ImplData @ d9be6853b
// Fully-resolved data for one `implements` block. Every impl normalizes to
// the same free shape; the in-body/out-of-body distinction survives only as
// `origin`, which must not drive resolution.
class ImplData {
    // The implemented interface (an interface loc id).
    interface_: int,
    // The interface's generic input args.
    interface_args: root.types.Ty[],
    // The resolved implementor pattern (may carry type variables).
    for_ty_pattern: root.types.Ty,
    // Generic params with their interface bounds.
    generic_params: (root.types.ParamTy, root.types.InterfaceConstraint[])[],
    // Diagnostics produced while resolving this impl, each with the span-free
    // location it originated from. Never dropped.
    diagnostics: (root.hir_ty.TirTypeError, ImplDiagnosticLocation)[],
    // The impl body's own method overrides (function loc ids).
    methods: int[],
    // Associated-type bindings supplied by the body, resolved.
    associated_types: (string, root.types.Ty)[],
    // Interface-field to class-field links declared in the block.
    field_links: (string, string)[],
    // In-body vs out-of-body provenance. Diagnostic metadata only.
    origin: InterfaceImplOrigin,
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::ImplDiagnosticLocation @ d9be6853b
// Where in an `implements` block a diagnostic originated; mapped to source
// spans through `impl_data_source_map`.
type ImplDiagnosticLocation = ImplDiagnosticLocationInterfaceTarget
    | ImplDiagnosticLocationForTarget
    | ImplDiagnosticLocationBound
    | ImplDiagnosticLocationMethod
    | ImplDiagnosticLocationInterfaceFieldLink
    | ImplDiagnosticLocationClassFieldLink
    | ImplDiagnosticLocationAssociatedBinding;

// The interface-target type expression (also covers associated-type
// bindings, part of the interface reference).
class ImplDiagnosticLocationInterfaceTarget {
}

// The for-target type expression; absent for in-body impls.
class ImplDiagnosticLocationForTarget {
}

// A generic bound: bounds carry no span, so the whole block.
class ImplDiagnosticLocationBound {
}

// An override method in the block, by name.
class ImplDiagnosticLocationMethod {
    value: string,
}

// The interface-field side of a `field as class_field` link.
class ImplDiagnosticLocationInterfaceFieldLink {
    value: string,
}

// The class-field side of a `field as class_field` link.
class ImplDiagnosticLocationClassFieldLink {
    value: string,
}

// A `type Name = ...` associated-type binding in the block, by name.
class ImplDiagnosticLocationAssociatedBinding {
    value: string,
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::ImplDataSourceMap @ d9be6853b
// Spans for an `implements` block.
class ImplDataSourceMap {
    // The span coherence attributes a conflict to.
    impl_span: root.base.Span,
    // The interface-target type expression.
    interface_target_span: root.base.Span,
    // The for-target type expression; null for in-body impls.
    for_target_span: root.base.Span?,
    // Override-method name to the span of every override with that name.
    method_spans: map<string, root.base.Span[]>,
    // Interface-field name to every link's interface-field side.
    interface_field_link_spans: map<string, root.base.Span[]>,
    // Class-field name to every link's class-field side.
    class_field_link_spans: map<string, root.base.Span[]>,
    // Associated-binding name to every `type Name = ...` binding's name span.
    associated_binding_spans: map<string, root.base.Span[]>,
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::interface_loc_qtn @ d9be6853b
// The qualified name of a resolved interface loc. Always present for a
// genuine loc; the optional shape is kept for its callers.
function interface_loc_qtn(db: root.hir.Db, iface_loc: int) -> root.types.DeclName? throws never {
    let data = root.hir.interface_data(db, iface_loc);
    root.hir_ty.qualify_def(db, root.hir.DefinitionInterface { value: iface_loc }, data.name)
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::ImplDataError @ d9be6853b
// Why `impl_data` could not produce an `ImplData`.
type ImplDataError = ImplDataErrorInterfaceUnresolved
    | ImplDataErrorMalformed
    | ImplDataErrorCyclicHeader;

// The implements target does not name an interface; the diagnostics lowered
// before the failure ride along.
class ImplDataErrorInterfaceUnresolved {
    diagnostics: (root.hir_ty.TirTypeError, ImplDiagnosticLocation)[],
}

// The impl block, its class, or the interface declaration was missing from
// the item tree (internal invariant).
class ImplDataErrorMalformed {
}

// The impl header references its own resolution.
class ImplDataErrorCyclicHeader {
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::lower_generic_param_interface_bounds @ d9be6853b
// Lower one generic param's bounds to its interface constraints, pushing
// the lowering diagnostics and the non-interface-bound (E0142) diagnostics
// into `diags`. `store` is the arena the bound ids index;
// `generic_param_names` are the in-scope params.
function lower_generic_param_interface_bounds(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    bounds: int[],
    pkg_items: root.hir.PackageItems,
    ns: string[],
    generic_param_names: root.types.ParamTy[],
    diags: root.hir_ty.TirTypeError[],
) -> root.types.InterfaceConstraint[] throws never {
    let ifaces: root.types.InterfaceConstraint[] = [];
    let lang = root.hir.lang_roots(db);
    for (let bound in bounds) {
        let scope = LowerScope {
            db: db,
            package_items: pkg_items,
            ns_context: ns,
            generic_params: generic_param_names,
            bounds: {},
            self_ty: null,
        };
        let ty = lower_ref_in(scope, store, bound, diags, position = root.hir_ty.TypePosition.ConstraintHead);
        match (ty) {
            // `reflect.AnyFunction` is legal only as a value type; as a bound
            // it is rejected and contributes no constraint.
            let i: root.types.TyInterface
                if root.types.decl_name_is_lang_root_type(
                i.name,
                lang,
                root.base.LangPackage.Reflect,
                "AnyFunction",
            ) => {
                diags.push(root.hir_ty.TirTypeErrorBuiltinInterfaceNotABound { interface_: i.name });
            },
            let i: root.types.TyInterface => {
                ifaces.push(
                    root.types.InterfaceConstraint {
                        name: i.name,
                        generics: i.args,
                        associated_types: i.associated_types,
                    },
                );
            },
            // Already diagnosed by lowering the bound expression itself.
            root.types.TyError | root.types.TyUnknown => {},
            // Bounds must be interfaces (E0142).
            _ => {
                diags.push(root.hir_ty.TirTypeErrorGenericBoundNotInterface { bound: ty });
            },
        }
    }
    ifaces
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::impl_data_cycle_result @ d9be6853b
// The fallback for a self-referential `impl_data` computation.
function impl_data_cycle_result(
    db: root.hir.Db,
    impl_loc: int,
) -> ImplData | ImplDataError throws never {
    ImplDataErrorCyclicHeader {}
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::impl_data @ d9be6853b
// Resolve one `implements` block. All of this impl's diagnostics are owned
// here (in `ImplData.diagnostics`, or the `InterfaceUnresolved` payload)
// and surfaced at the impl's span by check_types.baml. `cycle_result` is
// `get_fallback`.
function impl_data(db: root.hir.Db, impl_loc: int) -> ImplData | ImplDataError throws never {
    db.ty_memo.impl_data.get_fallback(
        db.cycles,
        impl_loc,
        () -> {
            impl_data_cycle_result(db, impl_loc)
        },
        () -> {
            let file = db.impl_locs.get(impl_loc).file;
            let block = root.hir.impl_block_data(db, impl_loc);
            let pkg_info = root.hir.file_package(db, file);
            let pkg_items = root.hir.package_items(db, pkg_info.root_id);
            let ns = pkg_info.namespace_path;

            // Both spellings arrive in one shape: an in-body block carries its
            // class's generics and the class as its for-target. Provenance decides
            // only the origin.
            let names = block.generics.map((g) -> {
                g.name
            });
            let generic_param_names = root.hir_ty.impl_frame(db, impl_loc);
            let bound_diags: root.hir_ty.TirTypeError[] = [];
            // `implements<T, T> ...`: a duplicate impl generic is a declaration error.
            for (let idx = 0; idx < names.length(); idx += 1) {
                if (names.slice(0, idx).includes(names[idx])) {
                    bound_diags.push(
                        root.hir_ty.TirTypeErrorDuplicateGenericParam { name: names[idx] },
                    );
                }
            }
            let generic_params: (root.types.ParamTy, root.types.InterfaceConstraint[])[] = [];
            for (let i = 0; i < block.generics.length() && i < generic_param_names.length(); i += 1) {
                let ifaces = lower_generic_param_interface_bounds(
                    db,
                    block.type_refs,
                    block.generics[i].bounds,
                    pkg_items,
                    ns,
                    generic_param_names,
                    bound_diags,
                );
                generic_params.push((generic_param_names[i], ifaces));
            }
            let bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
            for (let entry in generic_params) {
                bounds[entry.0] = entry.1;
            }
            let for_target_diags: root.hir_ty.TirTypeError[] = [];
            let header_scope = LowerScope {
                db: db,
                package_items: pkg_items,
                ns_context: ns,
                generic_params: generic_param_names,
                bounds: bounds,
                self_ty: null,
            };
            let for_ty = lower_ref_in(header_scope, block.type_refs, block.for_target, for_target_diags);
            let origin: InterfaceImplOrigin = match (block.origin) {
                root.ast.ImplOrigin.OutOfBody => InterfaceImplOriginOutOfBody {},
                root.ast.ImplOrigin.InBody => {
                    match (for_ty) {
                        let c: root.types.TyClass => {
                            InterfaceImplOriginInBodyClass { class_qtn: c.name }
                        },
                        // The class the block is written in did not resolve to a
                        // class type; nothing in-body applies.
                        _ => InterfaceImplOriginOutOfBody {},
                    }
                },
            };
            let for_ty_pattern = for_ty;

            let interface_target_diags: root.hir_ty.TirTypeError[] = [];
            // The target is a constraint head: it pins only its written bindings.
            let lowered_interface = lower_ref_in(
                header_scope,
                block.type_refs,
                block.interface_target,
                interface_target_diags,
                position = root.hir_ty.TypePosition.ConstraintHead,
            );
            let interface_args: root.types.Ty[] = match (lowered_interface) {
                let i: root.types.TyInterface => i.args,
                _ => [],
            };

            // Resolve the interface head to its loc after lowering, so a bad
            // interface target still surfaces its diagnostics.
            let iface_loc = resolve_ref_to_interface_identity(db, block.type_refs, block.interface_target, pkg_items, ns)?.loc;
            if (iface_loc == null) {
                let diagnostics: (root.hir_ty.TirTypeError, ImplDiagnosticLocation)[] = [];
                match (lowered_interface) {
                    let c: root.types.TyClass => {
                        diagnostics.push(
                            (
                                root.hir_ty.TirTypeErrorImplTargetNotInterface { name: c.name.name },
                                ImplDiagnosticLocationInterfaceTarget {},
                            ),
                        );
                    },
                    let e: root.types.TyEnum => {
                        diagnostics.push(
                            (
                                root.hir_ty.TirTypeErrorImplTargetNotInterface { name: e.name.name },
                                ImplDiagnosticLocationInterfaceTarget {},
                            ),
                        );
                    },
                    _ => {
                        for (let e in interface_target_diags) {
                            diagnostics.push((e, ImplDiagnosticLocationInterfaceTarget {}));
                        }
                    },
                }
                for (let e in for_target_diags) {
                    diagnostics.push((e, ImplDiagnosticLocationForTarget {}));
                }
                for (let e in bound_diags) {
                    diagnostics.push((e, ImplDiagnosticLocationBound {}));
                }
                return ImplDataErrorInterfaceUnresolved { diagnostics: diagnostics };
            }
            let iface_data = root.hir.interface_data(db, iface_loc);

            let assoc_diags: root.hir_ty.TirTypeError[] = [];
            // The impl's own generic bounds, so a `T.member` projection in a binding
            // value resolves through the impl generic's declared bound.
            let impl_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
            for (let entry in generic_params) {
                impl_bounds[entry.0] = entry.1;
            }
            let associated_types = lower_interface_associated_bindings(
                db,
                iface_loc,
                iface_data,
                interface_args,
                for_ty_pattern,
                block.type_refs,
                block.associated_type_bindings,
                pkg_items,
                ns,
                generic_param_names,
                impl_bounds,
                assoc_diags,
            );

            // Conformance, computed alongside lowering: E0126/E0113/E0115 plus
            // field-link and associated-binding hygiene.
            let conformance_diags: (root.hir_ty.TirTypeError, ImplDiagnosticLocation)[] = [];
            let iface_qtn = interface_loc_qtn(db, iface_loc);
            if (iface_qtn != null) {
                // `reflect.AnyFunction`'s conformance is compiler-derived; a written impl
                // is rejected outright (E0153).
                if (
                    root.types.decl_name_is_lang_root_type(
                        iface_qtn,
                        root.hir.lang_roots(db),
                        root.base.LangPackage.Reflect,
                        "AnyFunction",
                    )
                ) {
                    conformance_diags.push(
                        (
                            root.hir_ty.TirTypeErrorBuiltinInterfaceNotImplementable {
                                interface_: iface_qtn,
                            },
                            ImplDiagnosticLocationInterfaceTarget {},
                        ),
                    );
                }
                if (origin is InterfaceImplOriginOutOfBody && iface_data.fields.length() != 0) {
                    conformance_diags.push(
                        (
                            root.hir_ty.TirTypeErrorOutOfBodyImplementsFieldInterface {
                                interface_: iface_qtn,
                            },
                            ImplDiagnosticLocationInterfaceTarget {},
                        ),
                    );
                }
                let override_names = block.methods.map((loc) -> {
                    root.hir.function_data(db, loc).name
                });
                let default_names = iface_data.default_methods.map((loc) -> {
                    root.hir.function_data(db, loc).name
                });
                // E0113: a required method the impl neither provides nor the interface
                // defaults.
                for (let required in iface_data.required_methods) {
                    let provided = override_names.includes(required.name) || default_names.includes(required.name);
                    if (!provided) {
                        conformance_diags.push(
                            (
                                root.hir_ty.TirTypeErrorMissingInterfaceMethod {
                                    interface_: iface_qtn,
                                    method: required.name,
                                },
                                ImplDiagnosticLocationInterfaceTarget {},
                            ),
                        );
                    }
                }
                // E0115: an override matching no required or default method, once per
                // name.
                for (let idx = 0; idx < override_names.length(); idx += 1) {
                    let name = override_names[idx];
                    if (override_names.slice(0, idx).includes(name)) {
                        continue;
                    }
                    let is_member = iface_data.required_methods.some((m) -> {
                        m.name == name
                    })
                        || default_names.includes(name);
                    if (!is_member) {
                        conformance_diags.push(
                            (
                                root.hir_ty.TirTypeErrorUnknownInterfaceMember {
                                    interface_: iface_qtn,
                                    member: name,
                                },
                                ImplDiagnosticLocationMethod { value: name },
                            ),
                        );
                    }
                }
                // Field-side conformance, in-body class impls only.
                if let in_body: InterfaceImplOriginInBodyClass = origin {
                    let class_ = root.hir.impl_class(db, impl_loc);
                    if (
                        class_ != null
                            && (block.field_links.length() != 0 || iface_data.fields.length() != 0)
                    ) {
                        let class_fields = root.hir_ty.resolve_class_fields(db, class_);
                        let is_iface_field = (name: string) -> bool {
                            iface_data.fields.some((fld) -> {
                                fld.name == name
                            })
                        };
                        let is_class_field = (name: string) -> bool {
                            class_fields.some((field) -> {
                                field.0 == name
                            })
                        };
                        let links = block.field_links;

                        // Interface-field side of each link, deduped by interface-field name.
                        for (let idx = 0; idx < links.length(); idx += 1) {
                            let iface_field = links[idx].interface_field;
                            let same_field = (l: root.hir.InterfaceFieldLinkData) -> bool {
                                l.interface_field == iface_field
                            };
                            if (links.slice(0, idx).some(same_field)) {
                                continue;
                            }
                            if (links.slice(idx + 1, links.length()).some(same_field)) {
                                conformance_diags.push(
                                    (
                                        root.hir_ty.TirTypeErrorDuplicateInterfaceFieldLink {
                                            interface_: iface_qtn,
                                            field: iface_field,
                                        },
                                        ImplDiagnosticLocationInterfaceFieldLink {
                                            value: iface_field,
                                        },
                                    ),
                                );
                            }
                            if (!is_iface_field(iface_field)) {
                                conformance_diags.push(
                                    (
                                        root.hir_ty.TirTypeErrorUnknownInterfaceFieldLink {
                                            interface_: iface_qtn,
                                            field: iface_field,
                                        },
                                        ImplDiagnosticLocationInterfaceFieldLink {
                                            value: iface_field,
                                        },
                                    ),
                                );
                            }
                        }
                        // Class-field side, only for links whose interface field is valid;
                        // deduped by class-field name among eligible links.
                        for (let idx = 0; idx < links.length(); idx += 1) {
                            let link = links[idx];
                            if (!is_iface_field(link.interface_field)) {
                                continue;
                            }
                            let class_field = link.class_field;
                            let earlier = links.slice(0, idx).some((l) -> {
                                l.class_field == class_field && is_iface_field(l.interface_field)
                            });
                            if (earlier) {
                                continue;
                            }
                            if (!is_class_field(class_field)) {
                                conformance_diags.push(
                                    (
                                        root.hir_ty.TirTypeErrorUnknownClassFieldInInterfaceLink {
                                            class_: in_body.class_qtn.name,
                                            interface_: iface_qtn,
                                            field: class_field,
                                        },
                                        ImplDiagnosticLocationClassFieldLink { value: class_field },
                                    ),
                                );
                            }
                        }
                        // E0124: every interface field covered by a same-named class field or an
                        // explicit link.
                        for (let iface_field in iface_data.fields) {
                            let linked = links.some((fl) -> {
                                fl.interface_field == iface_field.name
                            });
                            if (!linked && !is_class_field(iface_field.name)) {
                                conformance_diags.push(
                                    (
                                        root.hir_ty.TirTypeErrorMissingInterfaceField {
                                            interface_: iface_qtn,
                                            field: iface_field.name,
                                        },
                                        ImplDiagnosticLocationInterfaceTarget {},
                                    ),
                                );
                            }
                        }
                    }
                }

                // Associated-type binding hygiene, name-based.
                let is_assoc = (name: string) -> bool {
                    iface_data.associated_types.some((a) -> {
                        a.name == name
                    })
                };
                let bindings = block.associated_type_bindings;
                for (let idx = 0; idx < bindings.length(); idx += 1) {
                    let binding = bindings[idx];
                    let same_name = (b: root.hir.AssociatedTypeBindingData) -> bool {
                        b.name == binding.name
                    };
                    if (bindings.slice(0, idx).some(same_name)) {
                        continue;
                    }
                    // Duplicate: the same associated type is bound by a later sibling too.
                    if (bindings.slice(idx + 1, bindings.length()).some(same_name)) {
                        conformance_diags.push(
                            (
                                root.hir_ty.TirTypeErrorDuplicateAssociatedTypeBinding {
                                    interface_: iface_qtn,
                                    name: binding.name,
                                },
                                ImplDiagnosticLocationAssociatedBinding { value: binding.name },
                            ),
                        );
                    }
                    // Unknown: names no associated type of the interface.
                    if (!is_assoc(binding.name)) {
                        conformance_diags.push(
                            (
                                root.hir_ty.TirTypeErrorUnknownAssociatedTypeBinding {
                                    interface_: iface_qtn,
                                    name: binding.name,
                                },
                                ImplDiagnosticLocationAssociatedBinding { value: binding.name },
                            ),
                        );
                    }
                }
                // Missing: an associated type with no default and no binding.
                for (let assoc in iface_data.associated_types) {
                    let bound = bindings.some((b) -> {
                        b.name == assoc.name
                    });
                    if (assoc.default == null && !bound) {
                        conformance_diags.push(
                            (
                                root.hir_ty.TirTypeErrorMissingImplAssociatedTypeBinding {
                                    interface_: iface_qtn,
                                    name: assoc.name,
                                },
                                ImplDiagnosticLocationInterfaceTarget {},
                            ),
                        );
                    }
                }
                // Bindings written on the `implements` target are rejected: the block's
                // `type Name = ...` is the only binding site.
                match (block.type_refs.get(block.interface_target).kind) {
                    let path: root.hir.TypeRefKindPath
                        if path.associated_type_bindings.length() != 0 => {
                        conformance_diags.push(
                            (
                                root.hir_ty.TirTypeErrorAssociatedTypeBindingsOnImplementsTarget {
                                    interface_: iface_qtn,
                                },
                                ImplDiagnosticLocationInterfaceTarget {},
                            ),
                        );
                    },
                    _ => {},
                }
            }

            // Tag each diagnostic with its origin, in a deterministic order.
            let diagnostics: (root.hir_ty.TirTypeError, ImplDiagnosticLocation)[] = [];
            for (let e in interface_target_diags) {
                diagnostics.push((e, ImplDiagnosticLocationInterfaceTarget {}));
            }
            for (let e in assoc_diags) {
                diagnostics.push((e, ImplDiagnosticLocationInterfaceTarget {}));
            }
            root.base.extend(diagnostics, conformance_diags);
            for (let e in for_target_diags) {
                diagnostics.push((e, ImplDiagnosticLocationForTarget {}));
            }
            for (let e in bound_diags) {
                diagnostics.push((e, ImplDiagnosticLocationBound {}));
            }

            ImplData {
                interface_: iface_loc,
                interface_args: interface_args,
                for_ty_pattern: for_ty_pattern,
                generic_params: generic_params,
                diagnostics: diagnostics,
                methods: block.methods,
                associated_types: associated_types.map((pin) -> {
                    (pin.name, pin.ty)
                }),
                field_links: block.field_links.map((link) -> {
                    (link.interface_field, link.class_field)
                }),
                origin: origin,
            }
        },
    )
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::impl_data_source_map @ d9be6853b
// Span sidecar for `impl_data`.
function impl_data_source_map(db: root.hir.Db, impl_loc: int) -> ImplDataSourceMap throws never {
    db.ty_memo.impl_data_source_map.get(db.cycles, impl_loc, () -> {
        let file_id = db.impl_locs.get(impl_loc).file;
        let block = root.hir.impl_block_data(db, impl_loc);
        let spans = root.hir.impl_block_source_map(db, impl_loc);
        let span_of = (range: root.syntax.TextRange) -> root.base.Span {
            root.base.Span { file_id: file_id, range: range }
        };
        let interface_target_range = spans.type_refs.span(block.interface_target);
        // In-body impls attribute to the interface-target span; out-of-body
        // to the whole block span.
        let attribution: (root.syntax.TextRange, root.base.Span?) = match (block.origin) {
            root.ast.ImplOrigin.InBody => (interface_target_range, null),
            root.ast.ImplOrigin.OutOfBody => {
                (spans.span, span_of(spans.type_refs.span(block.for_target)))
            },
        };
        let (let impl_range, let for_target_span) = attribution;
        // Group all override spans by name so a same-named duplicate marks
        // every occurrence.
        let method_spans: map<string, root.base.Span[]> = {};
        for (let func_loc in block.methods) {
            method_spans.get_or_insert(root.hir.function_data(db, func_loc).name, []).push(
                span_of(root.hir.function_source_map(db, func_loc).span),
            );
        }
        // Group each field link's endpoint spans by name.
        let interface_field_link_spans: map<string, root.base.Span[]> = {};
        let class_field_link_spans: map<string, root.base.Span[]> = {};
        for (let i = 0; i < block.field_links.length() && i < spans.field_links.length(); i += 1) {
            let link = block.field_links[i];
            let link_spans = spans.field_links[i];
            interface_field_link_spans.get_or_insert(link.interface_field, []).push(
                span_of(link_spans.interface_field_span),
            );
            class_field_link_spans.get_or_insert(link.class_field, []).push(
                span_of(link_spans.class_field_span),
            );
        }
        // Group each `type Name = ...` binding's name span by name.
        let associated_binding_spans: map<string, root.base.Span[]> = {};
        for (
            let i = 0;
            i < block.associated_type_bindings.length()
                && i < spans.associated_type_bindings.length();
            i += 1
        ) {
            associated_binding_spans.get_or_insert(block.associated_type_bindings[i].name, []).push(
                span_of(spans.associated_type_bindings[i].name_span),
            );
        }
        ImplDataSourceMap {
            impl_span: span_of(impl_range),
            interface_target_span: span_of(interface_target_range),
            for_target_span: for_target_span,
            method_spans: method_spans,
            interface_field_link_spans: interface_field_link_spans,
            class_field_link_spans: class_field_link_spans,
            associated_binding_spans: associated_binding_spans,
        }
    })
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::SigTypeRef @ d9be6853b
// One type slot in a method signature: a written type, or one of the two
// slots the declaration leaves implicit.
type SigTypeRef = SigTypeRefId | SigTypeRefSelfReceiver | SigTypeRefMissing;

class SigTypeRefId {
    value: int,
}

// The `self` receiver, desugared to `self: Self`.
class SigTypeRefSelfReceiver {
}

// No written type: lowers to `unknown`.
class SigTypeRefMissing {
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::InterfaceMethodParam @ d9be6853b
class InterfaceMethodParam {
    name: string,
    ty: SigTypeRef,
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::InterfaceMethodSpec @ d9be6853b
// A normalized interface-method signature: default and required methods
// both reduce to this, so one builder produces the function type.
class InterfaceMethodSpec {
    // The arena every signature slot indexes: the elaborated store for a
    // default method, the interface's own store for a required one.
    sig_refs: root.hir.TypeRefStore,
    // The arena the `generics` bound ids index (the declaration store).
    bound_refs: root.hir.TypeRefStore,
    args: InterfaceMethodParam[],
    kwargs: InterfaceMethodParam[],
    return_type: SigTypeRef,
    throws_: SigTypeRef,
    // Method generic params with their interface-bound conjunction.
    generics: root.hir.GenericParamData[],

    // port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::InterfaceMethodSpec::from_default @ d9be6853b
    function from_default(db: root.hir.Db, func_loc: int) -> InterfaceMethodSpec throws never {
        let sig = root.hir.elaborated_function_data(db, func_loc);
        let func_data = root.hir.function_data(db, func_loc);
        let (let args, let kwargs) = split_params(
            sig.params.map((p) -> (bool, bool, string, SigTypeRef) {
                // The implicit `self` receiver: name "self" with no declared
                // type (elaboration synthesizes a `Missing` node for it).
                let is_self = p.name == "self"
                    && sig.type_refs.get(p.type_ref).kind is root.hir.TypeRefKindMissing;
                (is_self, p.has_default, p.name, SigTypeRefId { value: p.type_ref })
            }),
        );
        InterfaceMethodSpec {
            sig_refs: sig.type_refs,
            bound_refs: func_data.type_refs,
            args: args,
            kwargs: kwargs,
            return_type: match (sig.return_type) {
                let id: int => SigTypeRefId { value: id },
                null => SigTypeRefMissing {},
            },
            throws_: match (sig.throws_) {
                let id: int => SigTypeRefId { value: id },
                null => SigTypeRefMissing {},
            },
            // `user_generic_params` is the elaborated view of the same
            // declaration order `generic_params` lowers.
            generics: func_data.generic_params,
        }
    }

    // port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::InterfaceMethodSpec::from_required @ d9be6853b
    function from_required(
        iface_data: root.hir.InterfaceData,
        sig: root.hir.InterfaceMethodSigData,
    ) -> InterfaceMethodSpec throws never {
        let (let args, let kwargs) = split_params(
            sig.params.map((p) -> (bool, bool, string, SigTypeRef) {
                let is_self = p.name == "self" && p.type_ref == null;
                (
                    is_self,
                    p.has_default,
                    p.name,
                    match (p.type_ref) {
                        let id: int => SigTypeRefId { value: id },
                        null => SigTypeRefMissing {},
                    },
                )
            }),
        );
        InterfaceMethodSpec {
            sig_refs: iface_data.type_refs,
            bound_refs: iface_data.type_refs,
            args: args,
            kwargs: kwargs,
            return_type: match (sig.return_type) {
                let id: int => SigTypeRefId { value: id },
                null => SigTypeRefMissing {},
            },
            throws_: match (sig.throws_) {
                let id: int => SigTypeRefId { value: id },
                null => SigTypeRefMissing {},
            },
            generics: sig.generic_params,
        }
    }

    // port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::InterfaceMethodSpec::generic_param_names @ d9be6853b
    function generic_param_names(self) -> string[] throws never {
        self.generics.map((g) -> {
            g.name
        })
    }

    // port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::InterfaceMethodSpec::to_function_ty @ d9be6853b
    // Lower this normalized signature to a function type through `scope`
    // (which resolves `Self`, `Self.Assoc` and the in-scope generics). Still a
    // template over its free type variables.
    function to_function_ty(
        self,
        scope: LowerScope,
        diags: root.hir_ty.TirTypeError[],
    ) -> root.types.Ty throws never {
        // The two implicit slots, synthesized into a scratch arena so they
        // lower through the same road as written types.
        let scratch = root.hir.TypeRefBuilder.new();
        let self_id = scratch.alloc_synthetic(
            root.hir.TypeRefKindPath {
                path: root.base.Path.new(["Self"]),
                generic_args: [],
                associated_type_bindings: [],
            },
        );
        let unknown_id = scratch.alloc_synthetic(root.hir.TypeRefKindMissing {});
        let (let scratch_store, _) = scratch.finish();
        let lower = (slot: SigTypeRef) -> root.types.Ty {
            match (slot) {
                let id: SigTypeRefId => lower_ref_in(scope, self.sig_refs, id.value, diags),
                SigTypeRefSelfReceiver => lower_ref_in(scope, scratch_store, self_id, diags),
                SigTypeRefMissing => lower_ref_in(scope, scratch_store, unknown_id, diags),
            }
        };
        let params = self.args
            .map((p) -> {
                root.types.FunctionParamTy {
                    name: p.name,
                    ty: lower(p.ty),
                    mode: root.types.FunctionParamMode.Required,
                }
            })
            .concat(
                self.kwargs.map((p) -> {
                    root.types.FunctionParamTy {
                        name: p.name,
                        ty: lower(p.ty),
                        mode: root.types.FunctionParamMode.Optional,
                    }
                }),
            );
        let ret = lower(self.return_type);
        let throws_ = lower(self.throws_);
        root.types.TyFunction { params: params, ret: ret, throws_: throws_ }
    }
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::split_params @ d9be6853b
// Split `(is_self, has_default, name, ty)` into positional args and
// keyword/optional kwargs. The `self` receiver desugars to `self: Self`.
function split_params(
    params: (bool, bool, string, SigTypeRef)[],
) -> (InterfaceMethodParam[], InterfaceMethodParam[]) throws never {
    let args: InterfaceMethodParam[] = [];
    let kwargs: InterfaceMethodParam[] = [];
    for (let entry in params) {
        let (let is_self, let has_default, let name, let ty) = entry;
        let param = InterfaceMethodParam {
            name: name,
            ty: if (is_self) {
                SigTypeRefSelfReceiver {}
            } else {
                ty
            },
        };
        if (has_default) {
            kwargs.push(param);
        } else {
            args.push(param);
        }
    }
    (args, kwargs)
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::method_generic_bound_interfaces @ d9be6853b
// A method spec's generic params paired with their lowered interface-bound
// conjunction (declaration order). A non-interface or unresolved conjunct is
// dropped (diagnosed at its own declaration).
function method_generic_bound_interfaces(
    db: root.hir.Db,
    pkg_items: root.hir.PackageItems,
    ns: string[],
    scope_generics: root.types.ParamTy[],
    spec: InterfaceMethodSpec,
) -> (string, root.types.InterfaceConstraint[])[] throws never {
    spec.generics.map((declared) -> {
        let conjunction = declared.bounds.filter_map((id) -> {
            let d: root.hir_ty.TirTypeError[] = [];
            let scope = LowerScope {
                db: db,
                package_items: pkg_items,
                ns_context: ns,
                generic_params: scope_generics,
                bounds: {},
                self_ty: null,
            };
            root.types.as_interface(
                lower_ref_in(scope, spec.bound_refs, id, d, position = root.hir_ty.TypePosition.ConstraintHead),
            )
        });
        (declared.name, conjunction)
    })
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::OrphanOutcome @ d9be6853b
// The covered-rule outcome for an out-of-body impl.
type OrphanOutcome = OrphanOutcomeOk | OrphanOutcomeUncoveredParam | OrphanOutcomeNoLocalType;

class OrphanOutcomeOk {
}

class OrphanOutcomeUncoveredParam {
    value: string,
}

class OrphanOutcomeNoLocalType {
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::orphan_check @ d9be6853b
// The "covered" rule: an out-of-body impl of a foreign interface is allowed
// only if, scanning `[T, args..]` left to right, a type local to
// `current_package` appears before any uncovered type parameter.
function orphan_check(
    current_package: int,
    iface_qtn: root.types.DeclName,
    for_ty: root.types.Ty,
    iface_args: root.types.Ty[],
) -> OrphanOutcome throws never {
    if (iface_qtn.pkg == current_package) {
        return OrphanOutcomeOk {};
    }
    for (let input in [for_ty].concat(iface_args)) {
        match (input) {
            let c: root.types.TyClass if c.name.pkg == current_package => {
                return OrphanOutcomeOk {};
            },
            let e: root.types.TyEnum if e.name.pkg == current_package => {
                return OrphanOutcomeOk {};
            },
            let v: root.types.TyTypeVar => {
                return OrphanOutcomeUncoveredParam { value: v.param.name };
            },
            _ => {},
        }
    }
    OrphanOutcomeNoLocalType {}
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::realize_with_symbolic_self @ d9be6853b
// Realize an interface-scoped type through `lower`, treating `Self` as a
// rigid type variable bound to `self_bound` and substituting
// `Self -> receiver` (plus `bindings`) last, so `Self.member` lowers to a
// symbolic projection and only collapses after substitution.
function realize_with_symbolic_self(
    db: root.hir.Db,
    package_items: root.hir.PackageItems,
    ns_context: string[],
    base_generics: root.types.ParamTy[],
    self_param: root.types.ParamTy,
    base_bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    self_bound: root.types.InterfaceConstraint,
    receiver: root.types.Ty,
    bindings: root.types.TypeBindings,
    lower: (LowerScope) -> root.types.Ty,
) -> root.types.Ty {
    // `Self` joins the in-scope generics with the implemented interface as
    // its bound.
    let generics = base_generics.concat([]);
    if (!generics.includes(self_param)) {
        generics.push(self_param);
    }
    let bounds = copy_bounds(base_bounds);
    bounds[self_param] = [self_bound];
    let lowered = lower(
        LowerScope {
            db: db,
            package_items: package_items,
            ns_context: ns_context,
            generic_params: generics,
            bounds: bounds,
            self_ty: root.types.TyTypeVar { param: self_param },
        },
    );
    // Substitute the receiver for `Self` last: `(Self as I).member` becomes
    // `(receiver as I).member`, which normalization reduces.
    let substitution = root.types.copy_bindings(bindings);
    substitution[self_param] = receiver;
    root.types.substitute_ty(lowered, substitution)
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::validate_impl_signatures @ d9be6853b
// Phase-5 signature/type conformance for one `implements` block, downstream
// of `impl_data`: field and method types against the interface's (E0116 /
// E0120), the out-of-body header gates (E0138 / E0135 / E0139), added
// method bounds, `requires` obligations (E0125) and associated-binding
// bounds.
function validate_impl_signatures(
    db: root.hir.Db,
    impl_loc: int,
) -> (root.hir_ty.TirTypeError, ImplDiagnosticLocation)[] throws never {
    db.ty_memo.validate_impl_signatures.get(db.cycles, impl_loc, () -> {
        let diags: (root.hir_ty.TirTypeError, ImplDiagnosticLocation)[] = [];
        let block = root.hir.impl_block_data(db, impl_loc);
        let pkg_info = root.hir.file_package(db, db.impl_locs.get(impl_loc).file);
        let current_package = pkg_info.root_id;
        let pkg_id = pkg_info.root_id;
        let data = match (impl_data(db, impl_loc)) {
            let d: ImplData => d,
            // A cyclic header can't carry its own diagnostic: re-detect and
            // surface it here so the impl doesn't silently vanish.
            ImplDataErrorCyclicHeader => {
                return [(root.hir_ty.TirTypeErrorCyclicImplHeader {}, ImplDiagnosticLocationForTarget {})];
            },
            // A source impl whose target is a mounted interface: its loc-free
            // `impl_facts` replays the validations that depend only on those
            // facts (E0138/E0135/E0139, the `requires` obligations and the
            // binding bounds), then returns so nothing is reported twice.
            ImplDataErrorInterfaceUnresolved => {
                let out_of_body = block.origin == root.ast.ImplOrigin.OutOfBody;
                let pool = db.ty_memo.pool;

                let (let facts, let for_ty, let validate_requires) = match (root.hir_ty.impl_facts(db, impl_loc)) {
                    root.hir_ty.ImplHeaderResolutionUnresolved => {
                        return diags;
                    },
                    let poisoned: root.hir_ty.ImplHeaderResolutionPoisoned => {
                        if (out_of_body) {
                            for (let name in poisoned.unconstrained) {
                                diags.push(
                                    (
                                        root.hir_ty.TirTypeErrorUnconstrainedImplTypeParam {
                                            name: name,
                                        },
                                        ImplDiagnosticLocationBound {},
                                    ),
                                );
                            }
                        }
                        return diags;
                    },
                    let not_implementor: root.hir_ty.ImplHeaderResolutionNotImplementor => {
                        if (out_of_body) {
                            diags.push(
                                (
                                    root.hir_ty.TirTypeErrorImplTargetNotConcrete {
                                        target: not_implementor.target,
                                    },
                                    ImplDiagnosticLocationForTarget {},
                                ),
                            );
                        }
                        (not_implementor.facts, not_implementor.target, false)
                    },
                    let resolved: root.hir_ty.ImplHeaderResolutionResolved => {
                        (
                            resolved.value,
                            pool.to_plain_closed(resolved.value.for_ty_pattern.ty),
                            true,
                        )
                    },
                };
                let interface_ = facts.interface_.to_plain(pool);
                // A loc-free resolution with no source interface loc should mean exactly
                // a mounted interface; anything else fails closed.
                if (
                    !(
                        root.hir_ty.mounted_type_row(db, interface_.name) is root.hir_ty.ExportedTypeInterface
                    )
                ) {
                    return diags;
                }
                if (out_of_body) {
                    match (orphan_check(current_package, interface_.name, for_ty, interface_.generics)) {
                        OrphanOutcomeOk => {},
                        let o: OrphanOutcomeUncoveredParam => {
                            diags.push(
                                (
                                    root.hir_ty.TirTypeErrorImplViolatesOrphanRule {
                                        interface_: interface_.name,
                                        uncovered_param: o.value,
                                    },
                                    ImplDiagnosticLocationInterfaceTarget {},
                                ),
                            );
                        },
                        OrphanOutcomeNoLocalType => {
                            diags.push(
                                (
                                    root.hir_ty.TirTypeErrorImplViolatesOrphanRule {
                                        interface_: interface_.name,
                                        uncovered_param: null,
                                    },
                                    ImplDiagnosticLocationInterfaceTarget {},
                                ),
                            );
                        },
                    }
                }

                let bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
                for (let entry in facts.generic_params) {
                    bounds[entry.0]
                        = entry.1.map((closed) -> {
                            closed.to_plain(pool)
                        });
                }
                let ctx = root.hir_ty.Facts.with_bounds(db, bounds);
                // E0125: realize the mounted interface's `requires` closure at this
                // impl's receiver and arguments, then ask the membership oracle.
                if (validate_requires) {
                    for (
                        let required in root.hir_ty.direct_requires_closure_plain(
                            db,
                            interface_,
                            for_ty,
                            root.hir_ty.REQUIRES_CLOSURE_FUEL,
                        )
                    ) {
                        let required_ty = ctx.normalize(
                            root.types.TyInterface {
                                name: required.name,
                                args: required.generics,
                                associated_types: required.associated_types,
                            },
                        );
                        if (
                            root.types.contains_ty_where(required_ty, (t) -> {
                                t is root.types.TyError
                            })
                        ) {
                            continue;
                        }
                        let required_iface = root.types.as_interface(required_ty);
                        if (required_iface == null) {
                            continue;
                        }
                        let concrete = pool.from_plain(for_ty);
                        let required_interned = root.types.infer_interface_from_constraint(pool, required_iface);
                        if (!root.hir_ty.implements_interface(db, concrete, required_interned)) {
                            diags.push(
                                (
                                    root.hir_ty.TirTypeErrorMissingRequiredInterface {
                                        interface_: interface_.name,
                                        required: required_iface,
                                    },
                                    ImplDiagnosticLocationInterfaceTarget {},
                                ),
                            );
                        }
                    }
                }
                // An explicit `type Name = V` binding must implement the interface's
                // declared bound for `Name`, over the header's realized bindings.
                let realized_pins = facts.associated_types.map((pin) -> {
                    root.types.AssociatedType { name: pin.0, ty: pool.to_plain_closed(pin.1.ty) }
                });
                let target_iface = root.types.InterfaceConstraint {
                    name: interface_.name,
                    generics: interface_.generics,
                    associated_types: realized_pins,
                };
                for (let binding in block.associated_type_bindings) {
                    let pin = realized_pins.find((p) -> {
                        p.name == binding.name
                    });
                    if (pin == null) {
                        continue;
                    }
                    let normalized = ctx.normalize(pin.ty);
                    for (let bound in ctx.associated_type_bound(target_iface, binding.name)) {
                        if (!normalized_arg_implements_bound(ctx, normalized, bound)) {
                            diags.push(
                                (
                                    root.hir_ty.TirTypeErrorAssociatedTypeBindingViolatesBound {
                                        interface_: interface_.name,
                                        name: binding.name,
                                        binding: pin.ty,
                                        bound: bound,
                                    },
                                    ImplDiagnosticLocationAssociatedBinding { value: binding.name },
                                ),
                            );
                        }
                    }
                }
                return diags;
            },
            ImplDataErrorMalformed => {
                return diags;
            },
        };
        let iface_qtn = interface_loc_qtn(db, data.interface_)
            ?? return diags;

        // The canonical algebra context: the fact oracle carrying the impl's own
        // param env.
        let pkg_items = root.hir.package_items(db, pkg_id);
        let aliases = package_resolved_aliases(db, pkg_id);
        let bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
        for (let entry in data.generic_params) {
            bounds[entry.0] = entry.1;
        }
        let ctx = root.hir_ty.Facts.with_bounds(db, copy_bounds(bounds));

        let iface_data = root.hir.interface_data(db, data.interface_);
        let iface_self_param = interface_self_param(db, data.interface_);
        let iface_generic_params = root.hir_ty.interface_declared_params(db, data.interface_);
        let iface_pkg_info = root.hir.file_package(db, db.interface_locs.get(data.interface_).file);
        let iface_pkg_items = root.hir.package_items(db, iface_pkg_info.root_id);
        let self_bound = root.types.InterfaceConstraint {
            name: iface_qtn,
            generics: data.interface_args,
            associated_types: [],
        };

        // E0116: field-type conformance (in-body impls).
        let class_ = if (data.origin is InterfaceImplOriginInBodyClass) {
            root.hir.impl_class(db, impl_loc)
        } else {
            null
        };
        if (iface_data.fields.length() != 0 && class_ != null) {
            let class_fields = root.hir_ty.resolve_class_fields(db, class_);
            let iface_field_bounds = interface_declared_param_bounds(db, data.interface_);
            // Realize the interface's declared field types at the impl's args.
            let iface_bindings = root.types.bind_type_vars(iface_generic_params, data.interface_args);
            for (let iface_field in iface_data.fields) {
                // The satisfying class field: explicit link, else same name.
                // Absent is E0124 (impl_data).
                let class_field_name = block.field_links
                    .find((fl) -> {
                        fl.interface_field == iface_field.name
                    })
                    ?.class_field
                    ?? iface_field.name;
                let class_field = class_fields.find((field) -> {
                    field.0 == class_field_name
                });
                if (class_field == null) {
                    continue;
                }
                let lower_diags: root.hir_ty.TirTypeError[] = [];
                let declared = realize_with_symbolic_self(db, iface_pkg_items, iface_pkg_info.namespace_path, iface_generic_params, iface_self_param, iface_field_bounds, self_bound, data.for_ty_pattern, iface_bindings, (
                    scope,
                ) -> {
                    lower_ref_in(scope, iface_data.type_refs, iface_field.type_ref, lower_diags)
                });
                // Field types are invariant: the class field must be the same type.
                if (!ctx.equivalent(declared, class_field.1)) {
                    diags.push(
                        (
                            root.hir_ty.TirTypeErrorInterfaceFieldTypeMismatch {
                                interface_: iface_qtn,
                                field: iface_field.name,
                                expected: declared,
                                got: class_field.1,
                            },
                            ImplDiagnosticLocationInterfaceTarget {},
                        ),
                    );
                }
            }
        }

        // Impl-header gates (out-of-body only).
        if (data.origin is InterfaceImplOriginOutOfBody) {
            // E0138: the for-target must be a single concrete impl subject, as
            // the header's one validity decision (`impl_facts`) says.
            match (root.hir_ty.impl_facts(db, impl_loc)) {
                let not_implementor: root.hir_ty.ImplHeaderResolutionNotImplementor => {
                    diags.push(
                        (
                            root.hir_ty.TirTypeErrorImplTargetNotConcrete {
                                target: not_implementor.target,
                            },
                            ImplDiagnosticLocationForTarget {},
                        ),
                    );
                },
                _ => {},
            }
            // E0135: every declared generic param must be determined by the
            // for-type or interface args; the list comes from `impl_facts`, which
            // also poisons the impl.
            match (root.hir_ty.impl_facts(db, impl_loc)) {
                let poisoned: root.hir_ty.ImplHeaderResolutionPoisoned => {
                    for (let name in poisoned.unconstrained) {
                        diags.push(
                            (
                                root.hir_ty.TirTypeErrorUnconstrainedImplTypeParam { name: name },
                                ImplDiagnosticLocationBound {},
                            ),
                        );
                    }
                },
                _ => {},
            }
            // E0139: the orphan rule.
            match (orphan_check(current_package, iface_qtn, data.for_ty_pattern, data.interface_args)) {
                OrphanOutcomeOk => {},
                let o: OrphanOutcomeUncoveredParam => {
                    diags.push(
                        (
                            root.hir_ty.TirTypeErrorImplViolatesOrphanRule {
                                interface_: iface_qtn,
                                uncovered_param: o.value,
                            },
                            ImplDiagnosticLocationInterfaceTarget {},
                        ),
                    );
                },
                OrphanOutcomeNoLocalType => {
                    diags.push(
                        (
                            root.hir_ty.TirTypeErrorImplViolatesOrphanRule {
                                interface_: iface_qtn,
                                uncovered_param: null,
                            },
                            ImplDiagnosticLocationInterfaceTarget {},
                        ),
                    );
                },
            }
        }

        // E0120: method-signature conformance. An override conforms iff its
        // function type is a subtype of the interface method's realized one.
        // `Self` = for-type on both sides; the interface's generics bind to
        // `interface_args`.
        let for_ty = data.for_ty_pattern;
        let impl_generic_names = data.generic_params.map((entry) -> {
            entry.0
        });
        let iface_bindings = root.types.bind_type_vars(iface_generic_params, data.interface_args);
        let iface_bounds = interface_declared_param_bounds(db, data.interface_);
        let no_bindings: root.types.TypeBindings = {};

        for (let method_loc in data.methods) {
            let method_data = root.hir.function_data(db, method_loc);
            let method_name = method_data.name;

            // A `$rust_io_function` override with method-level generics can't be
            // dispatched through interface (virtual) dispatch.
            let is_io = match (root.hir.function_body(db, method_loc)) {
                let b: root.hir.FunctionBodyBuiltin => b.value == root.ast.BuiltinKind.Io,
                _ => false,
            };
            if (method_data.generic_params.length() != 0 && is_io) {
                diags.push(
                    (
                        root.hir_ty.TirTypeErrorGenericSysOpMethodInInterfaceImpl {
                            interface_: iface_qtn,
                            method: method_name,
                        },
                        ImplDiagnosticLocationMethod { value: method_name },
                    ),
                );
                continue;
            }

            // The interface method this override targets.
            let required = iface_data.required_methods.find((sig) -> {
                sig.name == method_name
            });
            let default_loc = iface_data.default_methods.find((loc) -> {
                root.hir.function_data(db, loc).name == method_name
            });
            let iface_spec = if (required != null) {
                InterfaceMethodSpec.from_required(iface_data, required)
            } else if (default_loc != null) {
                InterfaceMethodSpec.from_default(db, default_loc)
            } else {
                // An unknown member is E0115 (impl_data).
                continue;
            };

            let d: root.hir_ty.TirTypeError[] = [];
            // The override's function type: Self = for-type; impl + method generics
            // in scope. Its declared throws is replaced by the effective throws.
            let impl_spec = InterfaceMethodSpec.from_default(db, method_loc);
            let impl_scope_generics = append_params(impl_generic_names, impl_spec.generic_param_names());
            let impl_method_params = impl_scope_generics.slice(impl_generic_names.length(), impl_scope_generics.length());
            let impl_fn = realize_with_symbolic_self(db, pkg_items, pkg_info.namespace_path, impl_scope_generics, iface_self_param, bounds, self_bound, for_ty, no_bindings, (
                scope,
            ) -> {
                impl_spec.to_function_ty(scope, d)
            });
            match (impl_fn) {
                let f: root.types.TyFunction => {
                    impl_fn
                        = root.types.TyFunction {
                            params: f.params,
                            ret: f.ret,
                            throws_: root.hir_ty.callable_throws(db, method_loc).value,
                        };
                },
                _ => {},
            }

            // The interface method's function type, realized at `interface_args`.
            let iface_scope_generics = append_params(iface_generic_params, iface_spec.generic_param_names());
            let iface_method_params = iface_scope_generics.slice(iface_generic_params.length(), iface_scope_generics.length());
            let method_generic_arity_matches = impl_method_params.length() == iface_method_params.length();
            let iface_method_bindings = root.types.copy_bindings(iface_bindings);
            if (method_generic_arity_matches) {
                for (let i = 0; i < iface_method_params.length(); i += 1) {
                    iface_method_bindings[iface_method_params[i]]
                        = root.types.TyTypeVar { param: impl_method_params[i] };
                }
            }
            let iface_fn = realize_with_symbolic_self(db, iface_pkg_items, iface_pkg_info.namespace_path, iface_scope_generics, iface_self_param, iface_bounds, self_bound, for_ty, iface_method_bindings, (
                scope,
            ) -> {
                iface_spec.to_function_ty(scope, d)
            });

            if (!method_generic_arity_matches || !ctx.is_subtype(impl_fn, iface_fn)) {
                diags.push(
                    (
                        root.hir_ty.TirTypeErrorInterfaceMethodSignatureMismatch {
                            interface_: iface_qtn,
                            method: method_name,
                            expected: iface_fn,
                            got: impl_fn,
                        },
                        ImplDiagnosticLocationMethod { value: method_name },
                    ),
                );
            }

            // An override may not add a generic bound the interface method does not
            // declare (Rust's E0276). Checked positionally: each override bound must
            // be entailed by the interface method's bound at the same position.
            let impl_bounds = method_generic_bound_interfaces(db, pkg_items, pkg_info.namespace_path, impl_scope_generics, impl_spec);
            let iface_method_bounds = method_generic_bound_interfaces(db, iface_pkg_items, iface_pkg_info.namespace_path, iface_scope_generics, iface_spec)
                .map((entry) -> {
                    (
                        entry.0,
                        entry.1.map((bound) -> {
                            root.types.map_tys(bound, (ty) -> {
                                root.types.substitute_ty(ty, iface_method_bindings)
                            })
                        }),
                    )
                });
            for (let i = 0; i < impl_bounds.length(); i += 1) {
                let (let param, let impl_conjunction) = impl_bounds[i];
                let iface_conjunction: root.types.InterfaceConstraint[] = iface_method_bounds.at(i)?.1 ?? [];
                for (let impl_bound in impl_conjunction) {
                    let entailed = iface_conjunction.some((iface_bound) -> {
                        carried_bound_satisfies(ctx, iface_bound, impl_bound)
                            || ctx.interface_requires(iface_bound, impl_bound)
                    });
                    if (!entailed) {
                        diags.push(
                            (
                                root.hir_ty.TirTypeErrorInterfaceMethodAddsGenericBound {
                                    interface_: iface_qtn,
                                    method: method_name,
                                    param: param,
                                    bound: impl_bound,
                                },
                                ImplDiagnosticLocationMethod { value: method_name },
                            ),
                        );
                    }
                }
            }
        }

        // E0125: the for-type must implement each interface the implemented one
        // `requires`. Diagnostics from re-lowering the clause are dropped: the
        // interface's own declaration owns them.
        let requires_diags: root.hir_ty.TirTypeError[] = [];
        for (let required_ref in iface_data.requires_) {
            // A `requires` clause may project `Self.member`; realize it with
            // `Self` bound to the implemented interface and `Self -> for_ty` last.
            let realized = realize_with_symbolic_self(db, iface_pkg_items, iface_pkg_info.namespace_path, iface_generic_params, iface_self_param, iface_bounds, self_bound, for_ty, iface_bindings, (
                scope,
            ) -> {
                lower_ref_in(
                    scope,
                    iface_data.type_refs,
                    required_ref,
                    requires_diags,
                    position = root.hir_ty.TypePosition.ConstraintHead,
                )
            });
            // Reduce any `Self.member` projection so the pins are concrete.
            let required = ctx.normalize(realized);
            let required_iface = match (required) {
                let i: root.types.TyInterface => {
                    root.types.InterfaceConstraint {
                        name: i.name,
                        generics: i.args,
                        associated_types: i.associated_types,
                    }
                },
                _ => {
                    continue;
                },
            };
            // An ill-formed clause realizes to an obligation carrying the error
            // sentinel: a cascade off an error reported at the interface.
            if (
                root.types.contains_ty_where(required, (t) -> {
                    t is root.types.TyError
                })
            ) {
                continue;
            }
            if (
                !implements_interface(db, for_ty, required_iface, aliases, (a, b) -> {
                    ctx.is_subtype(a, b)
                })
            ) {
                diags.push(
                    (
                        root.hir_ty.TirTypeErrorMissingRequiredInterface {
                            interface_: iface_qtn,
                            required: required_iface,
                        },
                        ImplDiagnosticLocationInterfaceTarget {},
                    ),
                );
            }
        }

        // Associated-type binding bound satisfaction: an explicit
        // `type Name = V` binding must implement the interface's declared bound.
        let target_iface = root.types.InterfaceConstraint {
            name: iface_qtn,
            generics: data.interface_args,
            associated_types: data.associated_types.map((pin) -> {
                root.types.AssociatedType { name: pin.0, ty: pin.1 }
            }),
        };
        for (let binding in block.associated_type_bindings) {
            let pin = data.associated_types.find((p) -> {
                p.0 == binding.name
            });
            if (pin == null) {
                continue;
            }
            let normalized = ctx.normalize(pin.1);
            for (let bound in ctx.associated_type_bound(target_iface, binding.name)) {
                if (!normalized_arg_implements_bound(ctx, normalized, bound)) {
                    diags.push(
                        (
                            root.hir_ty.TirTypeErrorAssociatedTypeBindingViolatesBound {
                                interface_: iface_qtn,
                                name: binding.name,
                                binding: pin.1,
                                bound: bound,
                            },
                            ImplDiagnosticLocationAssociatedBinding { value: binding.name },
                        ),
                    );
                }
            }
        }

        diags
    })
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::ResolvedImpl @ d9be6853b
// One `implements` block resolved for a specific realized
// `(interface, type)` pair.
class ResolvedImpl {
    // The unique impl block: coherence guarantees at most one per realized
    // `(interface, type)`.
    impl_loc: int,
    // The impl's own generic params bound to the realized type arguments.
    bindings: root.types.TypeBindings,

    // port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::ResolvedImpl::implemented_interface @ d9be6853b
    // The interface this impl provides at its resolved instantiation.
    function implemented_interface(
        self,
        db: root.hir.Db,
    ) -> root.types.InterfaceConstraint throws never {
        let data = match (impl_data(db, self.impl_loc)) {
            let d: ImplData => d,
            _ => baml.sys.panic("a ResolvedImpl carries an impl_data-Ok impl"),
        };
        let name = interface_loc_qtn(db, data.interface_)
            ?? baml.sys.panic("an impl_data-Ok impl has a named interface target");
        root.types.InterfaceConstraint {
            name: name,
            generics: data.interface_args.map((arg) -> {
                root.types.substitute_ty(arg, self.bindings)
            }),
            associated_types: data.associated_types
                .map((pin) -> {
                    root.types.AssociatedType {
                        name: pin.0,
                        ty: root.types.substitute_ty(pin.1, self.bindings),
                    }
                })
                .sort_by_key((pin) -> {
                    pin.name
                }),
        }
    }
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::package_impl_locs @ d9be6853b
// Every `implements` block declared in a package, in file then source order.
function package_impl_locs(db: root.hir.Db, pkg_id: int) -> int[] throws never {
    db.ty_memo.impl_rules_package_impl_locs.get(db.cycles, pkg_id, () -> {
        let out: int[] = [];
        // Only the package's own files.
        for (let file in db.source_root(pkg_id).files) {
            root.base.extend(out, root.hir.file_impls(db, file));
        }
        out
    })
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::BLANKET_IMPL_BOUND_DEPTH @ d9be6853b
// Recursion budget for verifying generic bounds: a bounded blanket can
// itself be satisfied by another blanket.
const BLANKET_IMPL_BOUND_DEPTH: int = 16;

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::is_concrete_receiver @ d9be6853b
// Whether `ty` is a concrete receiver: a value whose runtime type pins a
// single static impl. A bare blanket `implement<T> I for T` applies only to
// these.
function is_concrete_receiver(ty: root.types.Ty) -> bool throws never {
    match (ty) {
        root.types.TyClass
            | root.types.TyEnum
            | root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.TyList
            | root.types.TyMap
            | root.types.TyFuture
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst =>
        {
            true
        },
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::substitute_interface @ d9be6853b
// Substitute an interface bound's generics and associated types through
// `bindings` (a bound may reference sibling impl params).
function substitute_interface(
    iface: root.types.InterfaceConstraint,
    bindings: root.types.TypeBindings,
) -> root.types.InterfaceConstraint throws never {
    root.types.InterfaceConstraint {
        name: iface.name,
        generics: iface.generics.map((g) -> {
            root.types.substitute_ty(g, bindings)
        }),
        associated_types: iface.associated_types.map((pin) -> {
            root.types.AssociatedType {
                name: pin.name,
                ty: root.types.substitute_ty(pin.ty, bindings),
            }
        }),
    }
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::get_implements_block_within_depth @ d9be6853b
// Also `get_implements_block` (the default budget). The unique
// `implements` block by which a fully realized concrete type implements a
// fully realized interface.
function get_implements_block(
    db: root.hir.Db,
    pkg_id: int,
    concrete_ty: root.types.Ty,
    requested_iface: root.types.InterfaceConstraint,
    aliases: map<root.types.DeclName, root.types.Ty>,
    depth: int = BLANKET_IMPL_BOUND_DEPTH,
) -> ResolvedImpl? throws never {
    let packages = [pkg_id].concat(root.hir.package_dependency_closure(db, pkg_id));
    for (let pkg in packages) {
        for (let impl_loc in package_impl_locs(db, pkg)) {
            let data = match (impl_data(db, impl_loc)) {
                let d: ImplData => d,
                _ => {
                    continue;
                },
            };
            // Structural match: exact interface head, the bare-blanket guard,
            // joint for-type + interface-arg unification, and associated pins.
            let bindings = match (match_impl_head(db, data, concrete_ty, requested_iface, aliases)) {
                let b: root.types.TypeBindings => b,
                null => {
                    continue;
                },
            };
            // Generic bounds must hold: a bound `T extends I` is satisfied iff
            // the bound type itself implements `I`, possibly via another
            // blanket impl, hence the bounded re-entry.
            let bounds_satisfied = data.generic_params.every((entry) -> {
                let actual = match (bindings.get(entry.0)) {
                    let a: root.types.Ty => a,
                    null => {
                        return true;
                    },
                };
                entry.1.every((declared) -> {
                    let bound = substitute_interface(declared, bindings);
                    // A bound still mentioning an unbound param can't be
                    // checked statically here; vacuously satisfied.
                    if (
                        root.types.tys(bound).some((ty) -> {
                            root.types.contains_ty_where(ty, (t) -> {
                                t is root.types.TyTypeVar
                            })
                        })
                    ) {
                        return true;
                    }
                    depth > 0
                        && get_implements_block(db, pkg_id, actual, bound, aliases, depth = depth - 1)
                            != null
                })
            });
            if (!bounds_satisfied) {
                continue;
            }
            // Unique by coherence: the first full match is the only match.
            return ResolvedImpl { impl_loc: impl_loc, bindings: bindings };
        }
    }
    null
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::collect_ty_packages @ d9be6853b
// Collect the package of every qualified type name occurring in `ty`.
function collect_ty_packages(ty: root.types.Ty, out: int[]) -> void throws never {
    let push = (qtn: root.types.DeclName) -> void {
        if (!out.includes(qtn.pkg)) {
            out.push(qtn.pkg);
        }
    };
    let go = (t: root.types.Ty) -> void {
        collect_ty_packages(t, out);
    };
    match (ty) {
        let c: root.types.TyClass => {
            push(c.name);
            c.args.for_each(go);
        },
        let i: root.types.TyInterface => {
            push(i.name);
            i.args.for_each(go);
            for (let pin in i.associated_types) {
                go(pin.ty);
            }
        },
        let e: root.types.TyEnum => push(e.name),
        let v: root.types.TyEnumVariant => push(v.name),
        let a: root.types.TyTypeAlias => push(a.name),
        let l: root.types.TyList => go(l.elem),
        let m: root.types.TyMap => {
            go(m.key);
            go(m.value);
        },
        let f: root.types.TyFuture => {
            go(f.value);
            go(f.error);
        },
        let u: root.types.TyUnion => u.members.for_each(go),
        let t: root.types.TyTuple => t.items.for_each(go),
        let f: root.types.TyFunction => {
            for (let p in f.params) {
                go(p.ty);
            }
            go(f.ret);
            go(f.throws_);
        },
        let p: root.types.TyAssociatedTypeProjection => {
            go(p.base);
            collect_interface_packages(p.interface_, out);
        },
        // No qualified name: primitives, literals, type variables, sentinels.
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.TyLiteral
            | root.types.TyTypeVar
            | root.types.TyRustType
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst
            | root.types.TyUnknown
            | root.types.TyNever
            | root.types.TyError =>
        {},
    }
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::collect_interface_packages @ d9be6853b
// `collect_ty_packages` for an interface constraint.
function collect_interface_packages(
    iface: root.types.InterfaceConstraint,
    out: int[],
) -> void throws never {
    if (!out.includes(iface.name.pkg)) {
        out.push(iface.name.pkg);
    }
    for (let g in iface.generics) {
        collect_ty_packages(g, out);
    }
    for (let pin in iface.associated_types) {
        collect_ty_packages(pin.ty, out);
    }
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::implements_interface @ d9be6853b
// Universal interface membership: true iff every realized instantiation of
// `concrete` implements `interface_`.
function implements_interface(
    db: root.hir.Db,
    concrete: root.types.Ty,
    interface_: root.types.InterfaceConstraint,
    aliases: map<root.types.DeclName, root.types.Ty>,
    is_subtype: (root.types.Ty, root.types.Ty) -> bool,
) -> bool {
    let interface_ty = root.types.TyInterface {
        name: interface_.name,
        args: interface_.generics,
        associated_types: interface_.associated_types,
    };
    // Derived capabilities have no source impl block to find: the
    // normalizer proves their membership under the caller's param env.
    if (
        root.types.decl_name_is_lang_root_type(
            interface_.name,
            root.hir.lang_roots(db),
            root.base.LangPackage.Reflect,
            "AnyClass",
        )
            || root.hir_ty.structural_interface(db, interface_.name) != null
    ) {
        return is_subtype(concrete, interface_ty);
    }

    // The orphan rule keeps a legal impl of `(concrete, interface)` in the
    // package of some type that appears in the query.
    let roots: int[] = [];
    collect_ty_packages(concrete, roots);
    collect_interface_packages(interface_, roots);

    let realized = root.types.realized(concrete) && root.types.realized(interface_ty);
    for (let pkg_id in roots) {
        let found = if (realized) {
            get_implements_block(db, pkg_id, concrete, interface_, aliases) != null
        } else {
            type_implements_interface(db, pkg_id, concrete, interface_, aliases, is_subtype)
        };
        if (found) {
            return true;
        }
    }
    false
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::type_implements_interface @ d9be6853b
// Symbolic universal membership: the type-var-bearing backend of
// `implements_interface`.
function type_implements_interface(
    db: root.hir.Db,
    pkg_id: int,
    concrete: root.types.Ty,
    interface_: root.types.InterfaceConstraint,
    aliases: map<root.types.DeclName, root.types.Ty>,
    is_subtype: (root.types.Ty, root.types.Ty) -> bool,
) -> bool {
    let packages = [pkg_id].concat(root.hir.package_dependency_closure(db, pkg_id));
    for (let pkg in packages) {
        for (let impl_loc in package_impl_locs(db, pkg)) {
            let data = match (impl_data(db, impl_loc)) {
                let d: ImplData => d,
                _ => {
                    continue;
                },
            };
            let bindings = match_impl_head(db, data, concrete, interface_, aliases);
            if (bindings == null) {
                continue;
            }
            if (impl_bounds_hold_symbolic(data, bindings, is_subtype)) {
                return true;
            }
        }
    }
    false
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::get_implements_block_symbolic @ d9be6853b
// Symbolic counterpart of `get_implements_block`: the caller reads the
// match's realized pins, so a unique matching block is required; several
// distinct matches answer null.
function get_implements_block_symbolic(
    db: root.hir.Db,
    pkg_id: int,
    concrete: root.types.Ty,
    interface_: root.types.InterfaceConstraint,
    aliases: map<root.types.DeclName, root.types.Ty>,
    is_subtype: (root.types.Ty, root.types.Ty) -> bool,
) -> ResolvedImpl? {
    let packages = [pkg_id].concat(root.hir.package_dependency_closure(db, pkg_id));
    let found: ResolvedImpl? = null;
    for (let pkg in packages) {
        for (let impl_loc in package_impl_locs(db, pkg)) {
            let data = match (impl_data(db, impl_loc)) {
                let d: ImplData => d,
                _ => {
                    continue;
                },
            };
            let bindings = match_impl_head(db, data, concrete, interface_, aliases);
            if (bindings == null) {
                continue;
            }
            if (!impl_bounds_hold_symbolic(data, bindings, is_subtype)) {
                continue;
            }
            if (found != null) {
                // Coherence guarantees uniqueness only for realized inputs.
                return null;
            }
            found = ResolvedImpl { impl_loc: impl_loc, bindings: bindings };
        }
    }
    found
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::match_impl_head @ d9be6853b
// Structurally match one impl against a requested `(concrete, interface)`.
// Declared generic bounds are not checked here.
function match_impl_head(
    db: root.hir.Db,
    data: ImplData,
    concrete: root.types.Ty,
    requested_iface: root.types.InterfaceConstraint,
    aliases: map<root.types.DeclName, root.types.Ty>,
) -> root.types.TypeBindings? throws never {
    if (
        interface_loc_qtn(db, data.interface_) != requested_iface.name
            || data.interface_args.length() != requested_iface.generics.length()
    ) {
        return null;
    }
    let param_names = data.generic_params.map((entry) -> {
        entry.0
    });
    if let v: root.types.TyTypeVar = data.for_ty_pattern {
        if (param_names.includes(v.param) && !is_concrete_receiver(concrete)) {
            return null;
        }
    }
    let pairs: (root.types.Ty, root.types.Ty)[] = [(data.for_ty_pattern, concrete)];
    for (let i = 0; i < data.interface_args.length(); i += 1) {
        pairs.push((data.interface_args[i], requested_iface.generics[i]));
    }
    let equiv = root.types.AliasEquivCtx { aliases: aliases, lang: root.hir.lang_roots(db) };
    let bindings = match_ty_patterns(pairs, param_names, equiv)
        ?? return null;

    let associated_types_agree = requested_iface.associated_types.every((requested) -> {
        let impl_pin = data.associated_types.find((pin) -> {
            pin.0 == requested.name
        });
        impl_pin == null
            || equiv.equivalent(root.types.substitute_ty(impl_pin.1, bindings), requested.ty)
    });
    if (associated_types_agree) {
        bindings
    } else {
        null
    }
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::impl_bounds_hold_symbolic @ d9be6853b
// Whether every declared bound the match pinned holds, discharged through
// `is_subtype`. A param the match left free, or a bound still mentioning a
// free param, is deferred.
function impl_bounds_hold_symbolic(
    data: ImplData,
    bindings: root.types.TypeBindings,
    is_subtype: (root.types.Ty, root.types.Ty) -> bool,
) -> bool {
    data.generic_params.every((entry) -> {
        let actual = match (bindings.get(entry.0)) {
            let a: root.types.Ty => a,
            null => {
                return true;
            },
        };
        entry.1.every((declared) -> {
            let bound = substitute_interface(declared, bindings);
            if (
                root.types.tys(bound).some((ty) -> {
                    root.types.contains_ty_where(ty, (t) -> {
                        t is root.types.TyTypeVar
                    })
                })
            ) {
                return true;
            }
            is_subtype(
                actual,
                root.types.TyInterface {
                    name: bound.name,
                    args: bound.generics,
                    associated_types: bound.associated_types,
                },
            )
        })
    })
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::impls_for_type @ d9be6853b
// Every impl block in `pkg_id` and its dependency closure that applies to
// `concrete` (which may carry free variables).
function impls_for_type(
    db: root.hir.Db,
    pkg_id: int,
    concrete: root.types.Ty,
    aliases: map<root.types.DeclName, root.types.Ty>,
    is_subtype: (root.types.Ty, root.types.Ty) -> bool,
) -> ResolvedImpl[] {
    let packages = [pkg_id].concat(root.hir.package_dependency_closure(db, pkg_id));
    let out: ResolvedImpl[] = [];
    let equiv = root.types.AliasEquivCtx { aliases: aliases, lang: root.hir.lang_roots(db) };
    for (let pkg in packages) {
        for (let impl_loc in package_impl_locs(db, pkg)) {
            let data = match (impl_data(db, impl_loc)) {
                let d: ImplData => d,
                _ => {
                    continue;
                },
            };
            let param_names = data.generic_params.map((entry) -> {
                entry.0
            });
            if let v: root.types.TyTypeVar = data.for_ty_pattern {
                if (param_names.includes(v.param) && !is_concrete_receiver(concrete)) {
                    continue;
                }
            }
            let bindings = match_ty_patterns([(data.for_ty_pattern, concrete)], param_names, equiv);
            if (bindings == null) {
                continue;
            }
            if (impl_bounds_hold_symbolic(data, bindings, is_subtype)) {
                out.push(ResolvedImpl { impl_loc: impl_loc, bindings: bindings });
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::first_failing_impl_bound @ d9be6853b
// When `concrete` almost implements `requested` via some impl block (the
// implementor shape matches but a concrete generic bound fails), the first
// failing `(param, required bound, actual arg)`. Diagnostic-only.
function first_failing_impl_bound(
    db: root.hir.Db,
    pkg_id: int,
    concrete: root.types.Ty,
    requested: root.types.Ty,
    aliases: map<root.types.DeclName, root.types.Ty>,
    is_subtype: (root.types.Ty, root.types.Ty) -> bool,
) -> (string, root.types.Ty, root.types.Ty)? {
    let requested_iface = match (requested) {
        let i: root.types.TyInterface => i,
        _ => {
            return null;
        },
    };
    let packages = [pkg_id].concat(root.hir.package_dependency_closure(db, pkg_id));
    let equiv = root.types.AliasEquivCtx { aliases: aliases, lang: root.hir.lang_roots(db) };
    for (let pkg in packages) {
        for (let impl_loc in package_impl_locs(db, pkg)) {
            let data = match (impl_data(db, impl_loc)) {
                let d: ImplData => d,
                _ => {
                    continue;
                },
            };
            // Only an impl of the requested interface can "almost" satisfy it.
            if (interface_loc_qtn(db, data.interface_) != requested_iface.name) {
                continue;
            }
            let param_names = data.generic_params.map((entry) -> {
                entry.0
            });
            let pairs: (root.types.Ty, root.types.Ty)[] = [(data.for_ty_pattern, concrete)];
            if (data.interface_args.length() == requested_iface.args.length()) {
                for (let i = 0; i < data.interface_args.length(); i += 1) {
                    pairs.push((data.interface_args[i], requested_iface.args[i]));
                }
            }
            let bindings = match_ty_patterns(pairs, param_names, equiv);
            if (bindings == null) {
                continue;
            }
            for (let entry in data.generic_params) {
                let actual = bindings.get(entry.0);
                if (actual == null) {
                    continue;
                }
                for (let declared in entry.1) {
                    let bound = substitute_interface(declared, bindings);
                    if (
                        root.types.tys(bound).some((ty) -> {
                            root.types.contains_ty_where(ty, (t) -> {
                                t is root.types.TyTypeVar
                            })
                        })
                    ) {
                        continue;
                    }
                    let bound_ty = root.types.TyInterface {
                        name: bound.name,
                        args: bound.generics,
                        associated_types: bound.associated_types,
                    };
                    if (!is_subtype(actual, bound_ty)) {
                        return (entry.0.name, bound_ty, actual);
                    }
                }
            }
        }
    }
    null
}
