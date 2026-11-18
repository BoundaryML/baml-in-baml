// port: baml_compiler2_mir/src/inference_provider.rs @ d9be6853b
//
// MIR borrows the body's and parameter defaults' `hir_ty` inference results
// directly, one per arena. Rust's `pub(crate) use` re-exports (`CallPlan`,
// `GlobalRoot`, `InferenceResult`, `MemberResolution`, `MethodCallee`,
// `ParamBinding`, `Receiver`, `ResolvedPath`, `ScopedTypeBinding`) are the
// `root.hir_ty` types themselves, at `T = root.types.Ty`.
//
// Not ported: the `#[cfg(debug_assertions)]` probes `assert_checked` and
// `assert_signature_checked` (a release build has none; they need
// `baml_type::contains_error`, which is not ported).

// port: baml_compiler2_mir/src/inference_provider.rs::InferenceTables @ d9be6853b
// The inference results behind the `tir_*` accessors, one per metadata
// scope.
class InferenceTables {
    body: root.hir_ty.InferenceResult<root.types.Ty>,
    // A function's parameter defaults; a `let` has no parameters.
    defaults: root.hir_ty.InferenceResult<root.types.Ty>?,

    // port: baml_compiler2_mir/src/inference_provider.rs::InferenceTables::for_function @ d9be6853b
    function for_function(db: root.hir.Db, function_: int) -> InferenceTables throws never {
        InferenceTables {
            body: root.hir_ty.infer_body(db, root.hir.BodyOwnerIdFunction { value: function_ }),
            defaults: root.hir_ty.infer_body(db, root.hir.BodyOwnerIdParameterDefaults { value: function_ }),
        }
    }

    // port: baml_compiler2_mir/src/inference_provider.rs::InferenceTables::for_let @ d9be6853b
    function for_let(db: root.hir.Db, let_binding: int) -> InferenceTables throws never {
        InferenceTables {
            body: root.hir_ty.infer_body(db, root.hir.BodyOwnerIdLet { value: let_binding }),
            defaults: null,
        }
    }

    // port: baml_compiler2_mir/src/inference_provider.rs::InferenceTables::of @ d9be6853b
    // The results `inference_root` was typed in. Renamed parameter: `root`
    // is the package path.
    function of(
        self,
        inference_root: InferenceRoot,
    ) -> root.hir_ty.InferenceResult<root.types.Ty>? throws never {
        match (inference_root) {
            InferenceRoot.Body => self.body,
            InferenceRoot.ParameterDefaults => self.defaults,
        }
    }
}

// port: baml_compiler2_mir/src/inference_provider.rs::InferenceRoot @ d9be6853b
// Which of an owner's two arenas is being lowered, and so which inference
// result types its expressions. The metadata scope cannot say: a lambda keeps
// a scope of its own wherever it is written, so one inside a parameter
// default is keyed like any other lambda and typed with the defaults.
enum InferenceRoot {
    Body,
    ParameterDefaults,
}
