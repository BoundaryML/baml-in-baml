// port: baml_compiler2_hir_ty's `#[salsa::tracked]` queries @ d9be6853b
//
// One `TrackedMemo` per hir_ty query (ns_hir/tracked.baml), named after the
// query, keyed like HIR's memos: an interned loc id (`db.function_locs`, ...)
// or a root id. A query keyed by something else interns its key here first
// (`assoc_members`, `impl_type_keys`). Reached as `db.ty_memo.<query>`.
//
// Restructured: Rust's interned types live in one global pool
// (`baml_type::interned::pool()`); here the compile's pool is `pool`, so a
// query that interns reaches it through the Db.

// The `(InterfaceLoc, Name)` keys of `interface_assoc_default`,
// `interface_assoc_bound` and `interface_associated_type_default`, interned
// to `int`s.
class AssocMemberKeys {
    index: map<int, map<string, int>>,
    count: int,

    function new() -> AssocMemberKeys throws never {
        AssocMemberKeys { index: {}, count: 0 }
    }

    function intern(self, interface_: int, member: string) -> int throws never {
        let by_member = self.index.get_or_insert(interface_, {});
        let existing = by_member.get(member);
        if (existing != null) {
            return existing;
        }
        let key = self.count;
        self.count += 1;
        by_member[member] = key;
        key
    }
}

class TyMemos {
    // lower.rs::package_decl_cycles (key: root id)
    package_decl_cycles: root.hir.TrackedMemo<DeclCycles>,
    // lower.rs::resolve_class_fields (key: class loc)
    resolve_class_fields: root.hir.TrackedMemo<(string, root.types.Ty, root.hir.ClassFieldAttrs)[]>,
    // lower.rs::let_declared_type (key: let loc)
    let_declared_type: root.hir.TrackedMemo<root.types.Ty?>,
    // lower.rs::function_signature_with_diagnostics (key: function loc)
    function_signature_with_diagnostics: root.hir.TrackedMemo<FunctionSignatureResult>,
    // lower.rs::declared_throws (key: function loc)
    declared_throws: root.hir.TrackedMemo<DeclaredThrows>,
    // lower.rs::interface_assoc_default (key: `assoc_members`)
    interface_assoc_default: root.hir.TrackedMemo<AssocTypeLowering>,
    // lower.rs::interface_assoc_bound (key: `assoc_members`)
    interface_assoc_bound: root.hir.TrackedMemo<AssocTypeLowering>,
    // interfaces.rs::package_resolved_aliases (key: root id)
    package_resolved_aliases: root.hir.TrackedMemo<map<root.types.DeclName, root.types.Ty>>,
    // interfaces.rs::normalized_alias_map (key: root id)
    normalized_alias_map: root.hir.TrackedMemo<map<root.types.DeclName, root.types.Ty>>,
    // interfaces.rs::interface_associated_type_default (key: `assoc_members`)
    interface_associated_type_default: root.hir.TrackedMemo<(root.types.Ty, TirTypeError[])?>,
    // interfaces.rs::resolve_interface_fields (key: interface loc)
    resolve_interface_fields: root.hir.TrackedMemo<root.hir_ty.interfaces.ResolvedInterfaceFields>,
    // interfaces.rs::resolve_interface_required_methods (key: interface loc)
    resolve_interface_required_methods: root.hir.TrackedMemo<root.hir_ty.interfaces.ResolvedInterfaceMethod[]>,
    // impl_rules.rs::impl_data (key: impl loc; `cycle_result`)
    impl_data: root.hir.TrackedMemo<root.hir_ty.interfaces.ImplData | root.hir_ty.interfaces.ImplDataError>,
    // impl_rules.rs::impl_data_source_map (key: impl loc)
    impl_data_source_map: root.hir.TrackedMemo<root.hir_ty.interfaces.ImplDataSourceMap>,
    // impl_rules.rs::validate_impl_signatures (key: impl loc)
    validate_impl_signatures: root.hir.TrackedMemo<(TirTypeError, root.hir_ty.interfaces.ImplDiagnosticLocation)[]>,
    // impl_rules.rs::package_impl_locs (key: root id). Renamed: impls.rs
    // has a query of the same name (`package_impl_locs` below).
    impl_rules_package_impl_locs: root.hir.TrackedMemo<int[]>,
    // coherence.rs::package_coherence_diagnostics (key: root id)
    package_coherence_diagnostics: root.hir.TrackedMemo<root.hir_ty.interfaces.CoherenceViolation[]>,
    assoc_members: AssocMemberKeys,
    // impls.rs::impl_facts (key: impl loc)
    impl_facts: root.hir.TrackedMemo<ImplHeaderResolution>,
    // impls.rs::package_impl_locs (key: root id)
    package_impl_locs: root.hir.TrackedMemo<int[]>,
    // impls.rs::impls_for_type_cached (key: `impl_type_keys`)
    impls_for_type_cached: root.hir.TrackedMemo<CachedResolvedImpl[]>,
    impl_type_keys: ImplTypeKeys,
    // callable.rs::callable_throws (key: function loc)
    callable_throws: root.hir.TrackedMemo<CallableThrows>,
    // callable.rs::function_signature_ty (key: function loc)
    function_signature_ty: root.hir.TrackedMemo<FunctionSignatureTy>,
    // infer.rs::infer_function_body (key: function loc; `cycle_initial`)
    infer_function_body: root.hir.TrackedMemo<InferenceResult<root.types.Ty>>,
    // infer.rs::infer_let_body (key: let loc; `cycle_initial`)
    infer_let_body: root.hir.TrackedMemo<InferenceResult<root.types.Ty>>,
    // infer.rs::infer_parameter_defaults (key: function loc)
    infer_parameter_defaults: root.hir.TrackedMemo<InferenceResult<root.types.Ty>>,
    // infer.rs::IN_FLIGHT_LET_OWNERS (Rust's thread-local): the top-level
    // lets whose initializer is being inferred now, by `LetOwnerKey`
    // (file path, then item id; tuples are not map keys).
    in_flight_let_owners: map<string, map<int, bool>>,
    // infer.rs::BODY_INFERENCES (Rust's process-wide counter): body
    // inferences executed in this compile.
    body_inferences: int,
    // The compile's interned-type pool (Rust's global `pool()`).
    pool: root.types.InferPool,

    function new() -> TyMemos throws never {
        TyMemos {
            package_decl_cycles: root.hir.TrackedMemo.new("package_decl_cycles"),
            resolve_class_fields: root.hir.TrackedMemo.new("resolve_class_fields"),
            let_declared_type: root.hir.TrackedMemo.new("let_declared_type"),
            function_signature_with_diagnostics: root.hir.TrackedMemo.new("function_signature_with_diagnostics"),
            declared_throws: root.hir.TrackedMemo.new("declared_throws"),
            interface_assoc_default: root.hir.TrackedMemo.new("interface_assoc_default"),
            interface_assoc_bound: root.hir.TrackedMemo.new("interface_assoc_bound"),
            package_resolved_aliases: root.hir.TrackedMemo.new("package_resolved_aliases"),
            normalized_alias_map: root.hir.TrackedMemo.new("normalized_alias_map"),
            interface_associated_type_default: root.hir.TrackedMemo.new("interface_associated_type_default"),
            resolve_interface_fields: root.hir.TrackedMemo.new("resolve_interface_fields"),
            resolve_interface_required_methods: root.hir.TrackedMemo.new("resolve_interface_required_methods"),
            impl_data: root.hir.TrackedMemo.new("impl_data"),
            impl_data_source_map: root.hir.TrackedMemo.new("impl_data_source_map"),
            validate_impl_signatures: root.hir.TrackedMemo.new("validate_impl_signatures"),
            impl_rules_package_impl_locs: root.hir.TrackedMemo.new("impl_rules::package_impl_locs"),
            package_coherence_diagnostics: root.hir.TrackedMemo.new("package_coherence_diagnostics"),
            assoc_members: AssocMemberKeys.new(),
            impl_facts: root.hir.TrackedMemo.new("impl_facts"),
            package_impl_locs: root.hir.TrackedMemo.new("package_impl_locs"),
            impls_for_type_cached: root.hir.TrackedMemo.new("impls_for_type_cached"),
            impl_type_keys: ImplTypeKeys.new(),
            callable_throws: root.hir.TrackedMemo.new("callable_throws"),
            function_signature_ty: root.hir.TrackedMemo.new("function_signature_ty"),
            infer_function_body: root.hir.TrackedMemo.new("infer_function_body"),
            infer_let_body: root.hir.TrackedMemo.new("infer_let_body"),
            infer_parameter_defaults: root.hir.TrackedMemo.new("infer_parameter_defaults"),
            in_flight_let_owners: {},
            body_inferences: 0,
            pool: root.types.InferPool.new(),
        }
    }
}
