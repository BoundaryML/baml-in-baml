// Items of `baml_type` MIR unit 3 needs that are not ported yet, with their
// Rust signatures. Deleted at the MIR merge, when U7 ports their homes.

// port: baml_type/src/runtime_ty.rs::RuntimeTy::strip_null @ d9be6853b
// Remove `null` from a nullable union, collapsing the result. Ported for
// real (not a panicking stub): index and member lowering need it on every
// access.
function runtime_ty_strip_null(ty: RuntimeTy) -> RuntimeTy throws never {
    match (ty) {
        let union_: RuntimeTyUnion => {
            let non_null = union_.members.filter((m) -> {
                match (m) {
                    TyNull => false,
                    _ => true,
                }
            });
            match (non_null.length()) {
                0 => ty,
                1 => non_null[0],
                _ => RuntimeTyUnion { members: non_null },
            }
        },
        _ => ty,
    }
}

// port: baml_type/src/lib.rs::impl Display for RuntimeTy @ d9be6853b
// The rendering a `{}` format of a `RuntimeTy` gives.
function runtime_ty_to_string(ty: RuntimeTy) -> string throws never {
    baml.sys.panic("runtime_ty_to_string: not ported")
}

// port: baml_type/src/family.rs::impl Debug for RuntimeTy @ d9be6853b
// The rendering a `{:?}` format of a `RuntimeTy` gives.
function runtime_ty_debug(ty: RuntimeTy) -> string throws never {
    baml.sys.panic("runtime_ty_debug: not ported")
}
