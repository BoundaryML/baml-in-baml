// port: baml_compiler2_hir_ty/src/callable.rs @ d9be6853b
//
// Not ported (package K3). Only what the signature lowering reads.

// port: baml_compiler2_hir_ty/src/callable.rs::CallableThrows @ d9be6853b
// What a callable throws, wrapped for the memoized query result.
class CallableThrows {
    value: root.types.Ty,
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_throws @ d9be6853b
// What `function_` throws: the declared clause when written, else the union
// its body's effect channel infers.
// Stub: body inference is not ported, so this answers the fixpoint's seed
// (`callable_throws_cycle_initial`, `never`) instead of panicking. That pins
// every open (omitted or partial) throws clause to `never` until K3/K4 land.
function callable_throws(db: root.hir.Db, function_: int) -> CallableThrows throws never {
    CallableThrows { value: root.types.TyNever {} }
}
