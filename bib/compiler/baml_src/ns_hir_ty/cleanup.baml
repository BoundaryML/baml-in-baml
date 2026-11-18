// port: baml_compiler2_hir_ty/src/cleanup.rs @ d9be6853b
//
// BEP-042 `cleanup` finalizer recognition. `cleanup` is a reserved method
// name: a class's own method called `cleanup` is its finalizer, and must have
// the finalizer's shape, judged on the checked signature rather than on its
// spelling.

// port: baml_compiler2_hir_ty/src/cleanup.rs::CleanupMethod @ d9be6853b
// What a class's own method named `cleanup` is.
enum CleanupMethod {
    // The class's finalizer: it runs at most once per instance, whether
    // called, deferred, or run by the collector.
    Finalizer,
    // Not shaped as a finalizer, which the reserved name requires (E0144).
    Malformed,
}

// port: baml_compiler2_hir_ty/src/cleanup.rs::cleanup_method @ d9be6853b
// Whether `function_` is a class's finalizer. Null for anything but a
// class's own method named `cleanup`. The finalizer takes `self` alone, with
// no default and no generic parameters of its own, returns the unit type,
// and throws nothing; a `throws` clause may be left out, or written as one
// that admits no error.
function cleanup_method(db: root.hir.Db, function_: int) -> CleanupMethod? throws never {
    let data = root.hir.function_data(db, function_);
    if (data.name != root.base.CLEANUP_METHOD) {
        return null;
    }
    if (!(root.hir.method_owner(db, function_) is root.hir.MethodOwnerClass)) {
        return null;
    }
    let takes_only_self = data.params.length() == 1 && data.params[0].name == "self" && !data.params[0].has_default;
    let signature = function_signature_with_diagnostics(db, function_).signature;
    let facts = Facts.new(db);
    let returns_unit = facts.equivalent(signature.ret, root.types.TyNull {});
    let throws_nothing = data.throws_ == null || facts.equivalent(signature.throws_, root.types.TyNever {});
    if (data.generic_params.length() == 0 && takes_only_self && returns_unit && throws_nothing) {
        CleanupMethod.Finalizer
    } else {
        CleanupMethod.Malformed
    }
}
