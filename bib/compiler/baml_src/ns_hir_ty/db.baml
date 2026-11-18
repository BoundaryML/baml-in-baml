// port: baml_compiler2_hir_ty's `#[salsa::tracked]` queries @ d9be6853b
//
// One `TrackedMemo` per hir_ty query (ns_hir/tracked.baml), named after the
// query, keyed like HIR's memos: an interned loc id (`db.function_locs`, ...)
// or a root id. A query keyed by something else interns its key here first
// (`assoc_members`). Reached as `db.ty_memo.<query>`.
//
// Restructured: Rust's interned types live in one global pool
// (`baml_type::interned::pool()`); here the compile's pool is `pool`, so a
// query that interns reaches it through the Db.

// The `(InterfaceLoc, Name)` keys of `interface_assoc_default` and
// `interface_assoc_bound`, interned to `int`s.
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
    assoc_members: AssocMemberKeys,
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
            assoc_members: AssocMemberKeys.new(),
            pool: root.types.InferPool.new(),
        }
    }
}
