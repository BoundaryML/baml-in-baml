// Stubs for K4 unit 4 (paths, objects, annotations): every function of
// infer/trace_hooks.rs that the unit owns, in namespace `hir_ty.infer`, with
// its BAML signature. Each panics until the unit ports it; the unit replaces
// this file and deletes it. Signatures follow infer.baml's conventions:
// `InferenceContext` methods take `ctx` first; a free function over interned
// types with no context takes the pool first.

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::TraceHookPlan @ d9be6853b
// Checked invocation plan shared by diagnostics and executable lowering.
class TraceHookPlan {
    function_: int,
    type_args: root.types.Ty[],
    arguments: HookArgument[],
    return_ty: root.types.Ty,
}

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::HookArgument @ d9be6853b
// Parameter slots in the ordinary checked hook call, in declaration order.
type HookArgument = HookArgumentTarget | HookArgumentSettings | HookArgumentDefault;

// Resolved target parameter slot, including a method's receiver.
class HookArgumentTarget {
    value: int,
}

// Detached call-local tracing settings.
class HookArgumentSettings {
}

// An omitted optional slot; its default executes in the hook's frame.
class HookArgumentDefault {
}

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::declaration_diagnostics @ d9be6853b
function declaration_diagnostics(
    db: root.hir.Db,
    function_: int,
) -> root.hir_ty.TirDiagnostic[] throws never {
    baml.sys.panic("declaration_diagnostics: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::declaration_plan @ d9be6853b
function declaration_plan(db: root.hir.Db, function_: int) -> TraceHookPlan? throws never {
    baml.sys.panic("declaration_plan: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer/trace_hooks.rs::checked_declaration @ d9be6853b
function checked_declaration(
    db: root.hir.Db,
    function_: int,
) -> (root.hir_ty.TirDiagnostic[], TraceHookPlan?) throws never {
    baml.sys.panic("checked_declaration: not ported (U4)")
}
