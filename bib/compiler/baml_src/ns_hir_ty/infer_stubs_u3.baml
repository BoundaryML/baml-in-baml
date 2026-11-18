// Stubs for K4 unit 3 (calls, lambdas): every function of infer.rs that the
// unit owns, in namespace `hir_ty`, with its BAML signature. Each panics
// until the unit ports it; the unit replaces this file and deletes it.
// Signatures follow infer.baml's conventions: `InferenceContext` methods take
// `ctx` first; a free function over interned types with no context takes the
// pool first.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_call @ d9be6853b
function infer_call(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
    args: root.ast.CallArg[],
) -> int throws never {
    baml.sys.panic("infer_call: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::is_regex_new @ d9be6853b
function is_regex_new(ctx: InferenceContext, callee: int) -> bool throws never {
    baml.sys.panic("is_regex_new: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_constant_regex_pattern @ d9be6853b
function report_constant_regex_pattern(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
) -> void throws never {
    baml.sys.panic("report_constant_regex_pattern: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_call_site_builtin_values @ d9be6853b
function report_call_site_builtin_values(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
) -> void throws never {
    baml.sys.panic("report_call_site_builtin_values: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_mounted_reserved_call @ d9be6853b
function report_mounted_reserved_call(
    ctx: InferenceContext,
    call: int,
    callee: int,
) -> void throws never {
    baml.sys.panic("report_mounted_reserved_call: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::validate_runtime_type_operand @ d9be6853b
function validate_runtime_type_operand(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    operand: int,
) -> void throws never {
    baml.sys.panic("validate_runtime_type_operand: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::seed_implicit_llm_schema @ d9be6853b
function seed_implicit_llm_schema(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
    args: root.ast.CallArg[],
) -> void throws never {
    baml.sys.panic("seed_implicit_llm_schema: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::default_uncontracted_session_eval @ d9be6853b
function default_uncontracted_session_eval(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
) -> void throws never {
    baml.sys.panic("default_uncontracted_session_eval: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_call_args @ d9be6853b
function check_call_args(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
    callee_fn_ty: int,
    bound_receiver: bool,
    args: root.ast.CallArg[],
) -> int throws never {
    baml.sys.panic("check_call_args: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_callee @ d9be6853b
function infer_callee(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    call: int,
    callee: int,
) -> (int, bool) throws never {
    baml.sys.panic("infer_callee: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::member_callee @ d9be6853b
function member_callee(
    ctx: InferenceContext,
    call: int,
    member_expr: int,
    receiver: int,
    member: string,
) -> (int, bool, WorkingMemberResolution?) throws never {
    baml.sys.panic("member_callee: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::default_receiver_target @ d9be6853b
function default_receiver_target(
    ctx: InferenceContext,
) -> (root.types.InferInterfaceConstraint, int)? throws never {
    baml.sys.panic("default_receiver_target: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::default_member @ d9be6853b
function default_member(ctx: InferenceContext, member: string) -> InterfaceMember? throws never {
    baml.sys.panic("default_member: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_member_callee @ d9be6853b
function interface_member_callee(
    ctx: InferenceContext,
    interface_member: InterfaceMember,
    call: int,
    bind_self: bool,
) -> (int, bool) throws never {
    baml.sys.panic("interface_member_callee: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_unspecialized_generic_method_value @ d9be6853b
function report_unspecialized_generic_method_value(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: Expectation,
    inferred: int,
) -> void throws never {
    baml.sys.panic("report_unspecialized_generic_method_value: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_lambda @ d9be6853b
function infer_lambda(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    def: root.ast.LambdaDef,
    expected: Expectation,
) -> int throws never {
    baml.sys.panic("infer_lambda: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::register_callable_instantiation @ d9be6853b
function register_callable_instantiation(
    ctx: InferenceContext,
    callable: int,
    instantiation: int[],
    at: int,
) -> void throws never {
    baml.sys.panic("register_callable_instantiation: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::register_class_bounds @ d9be6853b
function register_class_bounds(
    ctx: InferenceContext,
    class_: int,
    instantiation: int[],
    at: int,
) -> void throws never {
    baml.sys.panic("register_class_bounds: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::instantiation_args @ d9be6853b
function instantiation_args(
    ctx: InferenceContext,
    site: int,
    generic_params: root.types.ParamTy[],
    callee: string?,
) -> int[] throws never {
    baml.sys.panic("instantiation_args: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::instantiation_args_at @ d9be6853b
function instantiation_args_at(
    ctx: InferenceContext,
    site: int,
    generic_params: root.types.ParamTy[],
    callee: string?,
    position: TypePosition,
) -> int[] throws never {
    baml.sys.panic("instantiation_args_at: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::is_reflect_package_function_lookup @ d9be6853b
function is_reflect_package_function_lookup(
    ctx: InferenceContext,
    function_: int,
) -> bool throws never {
    baml.sys.panic("is_reflect_package_function_lookup: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::computed_generic_argument_name @ d9be6853b
function computed_generic_argument_name(
    ctx: InferenceContext,
    type_ref: root.hir.BodyTypeRefId,
    site: int,
) -> string? throws never {
    baml.sys.panic("computed_generic_argument_name: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::specialize_computed_generic_diagnostic @ d9be6853b
function specialize_computed_generic_diagnostic(
    ctx: InferenceContext,
    diagnostics: LoweringDiag[],
    type_ref: root.hir.BodyTypeRefId,
    site: int,
    name: string,
) -> void throws never {
    baml.sys.panic("specialize_computed_generic_diagnostic: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::fresh_generic_arg @ d9be6853b
function fresh_generic_arg(ctx: InferenceContext, param: root.types.ParamTy) -> int throws never {
    baml.sys.panic("fresh_generic_arg: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::fresh_required_arg @ d9be6853b
function fresh_required_arg(
    ctx: InferenceContext,
    param: root.types.ParamTy,
    site: int,
) -> int throws never {
    baml.sys.panic("fresh_required_arg: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_missing_required_object_fields @ d9be6853b
function report_missing_required_object_fields(
    ctx: InferenceContext,
    object: int,
    class_name: root.types.DeclName,
    field_types: (string, root.types.Ty)[],
    instantiation: int[],
    fields: root.ast.ObjectExprField[],
    has_spread: bool,
) -> void throws never {
    baml.sys.panic("report_missing_required_object_fields: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::function_param_pairs @ d9be6853b
function function_param_pairs(
    pool: root.types.InferPool,
    actual: root.types.InferFunctionParamTy[],
    expected: root.types.InferFunctionParamTy[],
) -> (int, int)[]? throws never {
    baml.sys.panic("function_param_pairs: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::effect_only_params @ d9be6853b
function effect_only_params(db: root.hir.Db, callable: int) -> root.types.ParamTy[] throws never {
    baml.sys.panic("effect_only_params: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::substitute_interface_params @ d9be6853b
function substitute_interface_params(
    pool: root.types.InferPool,
    interface_: root.types.InferInterfaceConstraint,
    args: int[],
) -> root.types.InferInterfaceConstraint throws never {
    baml.sys.panic("substitute_interface_params: not ported (U3)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::call_bound_purpose @ d9be6853b
function call_bound_purpose(
    param: root.types.ParamTy,
    own_start: int,
) -> root.hir_ty.infer.GoalPurpose throws never {
    baml.sys.panic("call_bound_purpose: not ported (U3)")
}
