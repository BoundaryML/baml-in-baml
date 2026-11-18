// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs @ d9be6853b
//
// Ported so far: the data types and stubs the type checker's message layer
// (`check_types.baml`) reads.

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

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::interface_loc_qtn @ d9be6853b
// The qualified name of a resolved interface loc.
function interface_loc_qtn(db: root.hir.Db, iface_loc: int) -> root.types.DeclName? throws never {
    baml.sys.panic("interface_loc_qtn: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::impl_data @ d9be6853b
// Resolve one `implements` block.
// Restructured: Rust's `Result<ImplData, ImplDataError>` is the union
// `ImplData | ImplDataError`, a memoizable value like Rust's cached result.
function impl_data(db: root.hir.Db, impl_loc: int) -> ImplData | ImplDataError throws never {
    baml.sys.panic("impl_data: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::impl_data_source_map @ d9be6853b
// Span sidecar for `impl_data`.
function impl_data_source_map(db: root.hir.Db, impl_loc: int) -> ImplDataSourceMap throws never {
    baml.sys.panic("impl_data_source_map: not ported")
}

// port: baml_compiler2_hir_ty/src/interfaces/impl_rules.rs::validate_impl_signatures @ d9be6853b
// An impl's field and method type conformance diagnostics.
function validate_impl_signatures(
    db: root.hir.Db,
    impl_loc: int,
) -> (root.hir_ty.TirTypeError, ImplDiagnosticLocation)[] throws never {
    baml.sys.panic("validate_impl_signatures: not ported")
}
