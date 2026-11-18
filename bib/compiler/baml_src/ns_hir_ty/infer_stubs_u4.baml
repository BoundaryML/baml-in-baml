// Stubs for K4 unit 4 (paths, objects, annotations): every function of
// infer.rs that the unit owns, in namespace `hir_ty`, with its BAML
// signature. Each panics until the unit ports it; the unit replaces this file
// and deletes it. Signatures follow infer.baml's conventions:
// `InferenceContext` methods take `ctx` first; a free function over interned
// types with no context takes the pool first.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::resolve_value_path @ d9be6853b
function resolve_value_path(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    segments: string[],
    expected: Expectation,
) -> int throws never {
    baml.sys.panic("resolve_value_path: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::own_instantiation_with_bounds @ d9be6853b
function own_instantiation_with_bounds(
    ctx: InferenceContext,
    own: OwnArgs,
    params: root.types.ParamTy[],
    callee: string,
    anchor: int,
    position: TypePosition,
) -> int[] throws never {
    baml.sys.panic("own_instantiation_with_bounds: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::item_projection_value @ d9be6853b
function item_projection_value(
    ctx: InferenceContext,
    interface_: int,
    written: WrittenQualifier?,
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    baml.sys.panic("item_projection_value: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::qualified_path_value @ d9be6853b
function qualified_path_value(
    ctx: InferenceContext,
    expr: int,
    member: string,
    own: OwnArgs,
    record_at: int?,
) -> int throws never {
    baml.sys.panic("qualified_path_value: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_ref_for @ d9be6853b
function interface_ref_for(ctx: InferenceContext, qtn: root.types.DeclName) -> int? throws never {
    baml.sys.panic("interface_ref_for: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_method_loc @ d9be6853b
function interface_method_loc(
    ctx: InferenceContext,
    interface_: int,
    member: string,
) -> int? throws never {
    baml.sys.panic("interface_method_loc: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_static_value @ d9be6853b
function interface_static_value(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    baml.sys.panic("interface_static_value: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_static_value @ d9be6853b
function class_static_value(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    baml.sys.panic("class_static_value: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::extern_class_static_value @ d9be6853b
function extern_class_static_value(
    ctx: InferenceContext,
    class_: int,
    pinned: int[]?,
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    baml.sys.panic("extern_class_static_value: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_impl_static_value @ d9be6853b
function class_impl_static_value(
    ctx: InferenceContext,
    class_: int,
    pinned: int[]?,
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    baml.sys.panic("class_impl_static_value: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::impl_static_value @ d9be6853b
function impl_static_value(
    ctx: InferenceContext,
    qself: int,
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    baml.sys.panic("impl_static_value: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::source_class_static_value @ d9be6853b
function source_class_static_value(
    ctx: InferenceContext,
    class_: int,
    pinned: int[]?,
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    baml.sys.panic("source_class_static_value: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::enum_variant_value @ d9be6853b
function enum_variant_value(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
    record_at: int?,
) -> int? throws never {
    baml.sys.panic("enum_variant_value: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::type_qualified_member_callee @ d9be6853b
function type_qualified_member_callee(
    ctx: InferenceContext,
    call: int,
    base_expr: int,
    head: root.hir.PathHead,
    prefix: string[],
    member: string,
    record_at: int,
) -> int? throws never {
    baml.sys.panic("type_qualified_member_callee: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::static_class_for @ d9be6853b
function static_class_for(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
) -> (int, int[]?)? throws never {
    baml.sys.panic("static_class_for: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_ref_generic_frame @ d9be6853b
function class_ref_generic_frame(
    ctx: InferenceContext,
    class_: int,
) -> root.types.ParamTy[] throws never {
    baml.sys.panic("class_ref_generic_frame: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_ref_name @ d9be6853b
function class_ref_name(ctx: InferenceContext, class_: int) -> root.types.DeclName throws never {
    baml.sys.panic("class_ref_name: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::static_qualifier_ty @ d9be6853b
function static_qualifier_ty(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
) -> int? throws never {
    baml.sys.panic("static_qualifier_ty: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_static_method @ d9be6853b
function interface_static_method(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
    member: string,
) -> (int, int)? throws never {
    baml.sys.panic("interface_static_method: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_object @ d9be6853b
function infer_object(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    object: int,
    expected: Expectation,
    type_name: root.base.Path,
    fields: root.ast.ObjectExprField[],
    spreads: root.ast.SpreadField[],
) -> int throws never {
    baml.sys.panic("infer_object: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::constructor_head @ d9be6853b
// Restructured: Rust's `Result<T, E>` is the union `T | E`.
function constructor_head(
    ctx: InferenceContext,
    object: int,
    type_name: root.base.Path,
) -> (int, int[]?) | ConstructorMiss throws never {
    baml.sys.panic("constructor_head: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_denoted_by @ d9be6853b
function class_denoted_by(
    ctx: InferenceContext,
    ty: root.types.Ty,
) -> (root.types.DeclName, root.types.Ty[])? throws never {
    baml.sys.panic("class_denoted_by: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_source_object @ d9be6853b
function infer_source_object(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    object: int,
    expected: Expectation,
    type_name: root.base.Path,
    class_: int,
    pinned: int[]?,
    fields: root.ast.ObjectExprField[],
    spreads: root.ast.SpreadField[],
) -> int throws never {
    baml.sys.panic("infer_source_object: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::refuse_opaque_construction @ d9be6853b
function refuse_opaque_construction(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    object: int,
    class_name: root.types.DeclName,
    field: string,
    fields: root.ast.ObjectExprField[],
    spreads: root.ast.SpreadField[],
) -> int throws never {
    baml.sys.panic("refuse_opaque_construction: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_exported_object @ d9be6853b
function infer_exported_object(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    object: int,
    expected: Expectation,
    class_: int,
    pinned: int[]?,
    fields: root.ast.ObjectExprField[],
    spreads: root.ast.SpreadField[],
) -> int throws never {
    baml.sys.panic("infer_exported_object: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::field_access @ d9be6853b
function field_access(
    ctx: InferenceContext,
    at: int,
    base_ty: int,
    member: string,
) -> int throws never {
    baml.sys.panic("field_access: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_bare_output_format_reference @ d9be6853b
function report_bare_output_format_reference(
    ctx: InferenceContext,
    expr: int,
    function_: int,
) -> void throws never {
    baml.sys.panic("report_bare_output_format_reference: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::is_opaque_trace_type @ d9be6853b
function is_opaque_trace_type(
    ctx: InferenceContext,
    name: root.types.DeclName,
) -> bool throws never {
    baml.sys.panic("is_opaque_trace_type: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_field_access @ d9be6853b
function class_field_access(
    ctx: InferenceContext,
    at: int,
    receiver: int,
    member: string,
) -> (int, WorkingMemberResolution?)? throws never {
    baml.sys.panic("class_field_access: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::field_access_resolved @ d9be6853b
function field_access_resolved(
    ctx: InferenceContext,
    at: int,
    base_ty: int,
    member: string,
) -> (int, WorkingMemberResolution?) throws never {
    baml.sys.panic("field_access_resolved: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::union_member_access @ d9be6853b
function union_member_access(
    ctx: InferenceContext,
    at: int,
    union_ty: int,
    members: int[],
    member: string,
) -> (int, WorkingMemberResolution?) throws never {
    baml.sys.panic("union_member_access: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::declarer_resolution @ d9be6853b
function declarer_resolution(
    ctx: InferenceContext,
    declarer: MemberDeclarer,
    member: string,
    receiver: Receiver,
) -> WorkingMemberResolution? throws never {
    baml.sys.panic("declarer_resolution: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::constructor_interface_field_link @ d9be6853b
function constructor_interface_field_link(
    ctx: InferenceContext,
    class_: int,
    name: string,
) -> string? throws never {
    baml.sys.panic("constructor_interface_field_link: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::template_param_root @ d9be6853b
function template_param_root(ctx: InferenceContext, name: string) -> bool throws never {
    baml.sys.panic("template_param_root: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::global_root @ d9be6853b
function global_root(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
) -> (int, int)? throws never {
    baml.sys.panic("global_root: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::global_value_ty @ d9be6853b
function global_value_ty(ctx: InferenceContext, expr: int, binding: int) -> int? throws never {
    baml.sys.panic("global_value_ty: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::template_param_heads @ d9be6853b
function template_param_heads(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
) -> bool throws never {
    baml.sys.panic("template_param_heads: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::qualified_path_root_is_top_level_let @ d9be6853b
function qualified_path_root_is_top_level_let(
    ctx: InferenceContext,
    segments: string[],
) -> bool throws never {
    baml.sys.panic("qualified_path_root_is_top_level_let: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::path_resolves_locally @ d9be6853b
function path_resolves_locally(ctx: InferenceContext, expr: int) -> bool throws never {
    baml.sys.panic("path_resolves_locally: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::path_resolution @ d9be6853b
function path_resolution(
    ctx: InferenceContext,
    expr: int,
) -> root.hir.PathResolution? throws never {
    baml.sys.panic("path_resolution: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::item_head @ d9be6853b
function item_head(
    ctx: InferenceContext,
    expr: int,
    segments: string[],
) -> root.hir.PathHead throws never {
    baml.sys.panic("item_head: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::binding_for_pattern @ d9be6853b
function binding_for_pattern(
    ctx: InferenceContext,
    pattern: int,
) -> root.hir.BindingId? throws never {
    baml.sys.panic("binding_for_pattern: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_path @ d9be6853b
function infer_path(ctx: InferenceContext, expr: int) -> int throws never {
    baml.sys.panic("infer_path: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lower_body_annotation @ d9be6853b
function lower_body_annotation(
    ctx: InferenceContext,
    type_ref: root.hir.BodyTypeRefId,
) -> int throws never {
    baml.sys.panic("lower_body_annotation: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::instantiate_holes @ d9be6853b
function instantiate_holes(
    ctx: InferenceContext,
    ty: root.types.LoweringTy,
    at: HoleAnchor,
) -> int throws never {
    baml.sys.panic("instantiate_holes: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::ingest_lowered @ d9be6853b
function ingest_lowered(
    ctx: InferenceContext,
    ty: root.types.LoweringTy,
    policy: IngestHoles,
) -> int throws never {
    baml.sys.panic("ingest_lowered: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::ingest_lowered_slow @ d9be6853b
function ingest_lowered_slow(
    ctx: InferenceContext,
    ty: root.types.LoweringTy,
    policy: IngestHoles,
) -> int throws never {
    baml.sys.panic("ingest_lowered_slow: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::reject_expr_position_holes @ d9be6853b
function reject_expr_position_holes(
    ctx: InferenceContext,
    ty: root.types.LoweringTy,
    at: int,
) -> int throws never {
    baml.sys.panic("reject_expr_position_holes: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::bind_receiver @ d9be6853b
function bind_receiver(pool: root.types.InferPool, fn_ty: int) -> int throws never {
    baml.sys.panic("bind_receiver: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::generic_function_value_ty @ d9be6853b
function generic_function_value_ty(
    db: root.hir.Db,
    callable: int,
    user_params: root.types.ParamTy[],
    receiver_is_bound: bool,
    concrete_example: bool,
) -> int throws never {
    baml.sys.panic("generic_function_value_ty: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::generic_function_value_shape @ d9be6853b
function generic_function_value_shape(
    vp: Viewpoint,
    db: root.hir.Db,
    callable: int,
    user_params: root.types.ParamTy[],
    receiver_is_bound: bool,
    concrete_example: bool,
) -> string? throws never {
    baml.sys.panic("generic_function_value_shape: not ported (U4)")
}

// port: baml_compiler2_hir_ty/src/infer.rs::initializer_binding_name @ d9be6853b
function initializer_binding_name(
    body: root.ast.ExprBody,
    initializer: int,
) -> string? throws never {
    baml.sys.panic("initializer_binding_name: not ported (U4)")
}
