// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// Tagged-template lowering (lower.rs "3.1b"): the served-callee helpers
// `external_callee` / `trusted_external_callee`, `lower_tagged_template`,
// `collect_static_tagged_segments`, and `build_tagged_body_closure`.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - `build_tagged_body_closure` saves and restores the context as
//   `lower_lambda` does: every `mem::take` / `mem::replace` / `Option::take`
//   saves the old object and puts a FRESH value in the field. Its HIR
//   capture read and capture-operand tail are `lambda_hir_captures` and
//   `lower_lambda_capture_operands` (lower_u3_body.baml), which Rust writes
//   out twice, word for word.
// - `ExternFunctionLoc` is an `int`; its `package` and `extern_function_row`
//   are stubs (`ns_hir_ty/layout_stubs_u3.baml`): no root is served from an
//   interface, so `external_callee` never finds one.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::external_callee @ d9be6853b
// The exported row a callee expression names, following the same
// flat-vs-path-member precedence as the source-location helpers.
function external_callee(ctx: LoweringContext, callee: int) -> int? throws never {
    match (ctx.body.exprs[callee]) {
        let path: root.ast.ExprPath if path.value.segments.length() >= 2 => {
            let final_resolution = tir_path_final_resolution(ctx, callee);
            let from_final = if (final_resolution != null) {
                resolution_external_function(ctx.db, final_resolution)
            } else {
                null
            };
            if (from_final != null) {
                return from_final;
            }
            let resolution = tir_resolution(ctx, callee);
            if (resolution != null) {
                resolution_external_function(ctx.db, resolution)
            } else {
                null
            }
        },
        root.ast.ExprMemberAccess => {
            let resolution = tir_resolution(ctx, callee);
            if (resolution != null) {
                resolution_external_function(ctx.db, resolution)
            } else {
                null
            }
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::trusted_external_callee @ d9be6853b
// The exported row a callee names, ONLY when its package is
// compiler-built (the precompiled stdlib): the one gate on trusting a
// row's `builtin_kind` for compiler-owned lowering. Trust follows the
// package the row's ADDRESS lives in: a blob cannot borrow another
// package's trust by spelling its `target`.
function trusted_external_callee(
    ctx: LoweringContext,
    callee: int,
) -> (int, root.hir_ty.ExportedFunction)? throws never {
    let function_ = external_callee(ctx, callee)
        ?? return null;
    if (
        !root.hir.is_precompiled_stdlib(
            ctx.db,
            root.hir_ty.extern_function_package(ctx.db, function_),
        )
    ) {
        return null;
    }
    (function_, root.hir_ty.extern_function_row(ctx.db, function_))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_tagged_template @ d9be6853b
// Lower a tagged template (a `TAGGED_TEMPLATE_EXPR`) to a
// `tag(body = <closure>)` call, where the closure builds a
// `baml.TaggedString { parts, values }` from the template segments.
//
// The closure is hand-rolled (there is no AST `ExprLambda`): HIR registered
// a `ScopeKind.Lambda` spanning the tagged-template expr so captures are
// computed; `build_tagged_body_closure` replicates `lower_lambda`'s skeleton
// with the body params from the tag's `body: (...) -> baml.TaggedString`
// parameter. The interpolation expressions live in the CURRENT `ExprBody`,
// so `ctx.body` / `ctx.source_map` are not swapped.
function lower_tagged_template(
    ctx: LoweringContext,
    expr_id: int,
    tag: int,
    body: int,
    segments: root.ast.TemplateSegment[],
    dest: Place,
) -> void throws MirInternalError {
    let db = ctx.db;
    // Resolve the tag function. TIR already validated it is a
    // `//baml:tagged_string` fn whose first param is
    // `body: (...) -> baml.TaggedString`; resolve again for its callee and
    // signature (the body-lambda param names and types).
    let sm = ctx.source_map;
    let tag_span_start = if (sm != null) {
        sm.expr_span(tag).start
    } else {
        0
    };
    // Prefer the resolution TIR recorded for the tag expression. A qualified
    // tag like `ai.prompt` is a multi-segment path whose function lives in
    // `resolutions`; resolving only the bare last segment in the user's
    // scope would miss it. Fall back to bare-name resolution for
    // unqualified, in-file tags.
    let tag_resolution = tir_resolution(ctx, tag);
    let tag_func_loc = if (tag_resolution != null) {
        resolution_func_loc(tag_resolution)
    } else {
        null
    };
    if (tag_func_loc == null) {
        let tag_name: string? = match (ctx.body.exprs[tag]) {
            let path: root.ast.ExprPath if path.value.segments.length() > 0 => {
                path.value.segments[path.value.segments.length() - 1]
            },
            _ => null,
        };
        if (tag_name != null) {
            let resolved = root.hir.resolve_name_at(
                db,
                ctx.file,
                tag_span_start,
                tag_name,
                scope_name = ctx.scope_func_name,
            );
            tag_func_loc
                = match (resolved) {
                    let item: root.hir.ResolvedNameItem => match (item.value) {
                        let f: root.hir.DefinitionFunction => f.value,
                        _ => null,
                    },
                    let builtin: root.hir.ResolvedNameBuiltin => match (builtin.value) {
                        let f: root.hir.DefinitionFunction => f.value,
                        _ => null,
                    },
                    _ => null,
                };
        }
    }
    if (tag_func_loc == null) {
        // Unreachable in well-typed programs (TIR rejects non-function
        // tags); guard so codegen never proceeds on a malformed tag.
        throw internal_error(ctx, "tagged-template tag did not resolve to a function", expr_id);
    }
    let tag_callee = tag_func_loc;

    // Body-lambda params and closure type from the tag's `body` param.
    let tag_sig = root.hir.function_signature(db, tag_func_loc);
    let tag_pkg_info = root.hir.file_package(db, db.function_locs.get(tag_func_loc).file);
    let tag_pkg_items = root.hir.package_items(db, tag_pkg_info.root_id);
    let body_params: (string, root.types.RuntimeTy)[] = [];
    let closure_ty: root.types.RuntimeTy = root.types.TyNull {};
    let first_param = tag_sig.params.at(0);
    if (first_param != null) {
        let body_te = first_param.ty.value;
        match (body_te.kind) {
            let function_ty: root.ast.TypeExprKindFunction => {
                let i = 0;
                for (let p in function_ty.params) {
                    let name = p.name ?? `__arg${i}`;
                    let tir_ty = lower_expr_in_scope(db, p.ty, tag_pkg_items, tag_pkg_info.namespace_path, [], {}, null);
                    body_params.push((name, runtime(ctx).convert(tir_ty)));
                    i += 1;
                }
                let tir_ty = lower_expr_in_scope(db, body_te, tag_pkg_items, tag_pkg_info.namespace_path, [], {}, null);
                closure_ty = runtime(ctx).convert(tir_ty);
            },
            _ => {},
        }
    }

    // Static segment layout (text and interpolations only): the fixed-array
    // fast path. `null` means a `${for}` / `${if}` block is present, so the
    // closure body lowers the desugared `body` flatten block instead.
    let static_layout = collect_static_tagged_segments(segments);

    // Hand-roll the body closure into an operand.
    let closure_op = build_tagged_body_closure(ctx, expr_id, body, body_params, closure_ty, static_layout);

    // Emit `tag(closure)` into dest. The result is the template's value.
    let callee = OperandConstant { value: ConstantFunction { value: tag_callee } };
    let target = ctx.builder.create_block();
    match (dest) {
        PlaceLocal => {
            ctx.builder.call_with_type_args(callee, [closure_op], 0, dest, target);
            ctx.builder.set_current_block(target);
        },
        _ => {
            let ty = expr_ty(ctx, expr_id);
            let tmp = ctx.builder.declare_local(ty);
            ctx.builder.call_with_type_args(
                callee,
                [closure_op],
                0,
                PlaceLocal { value: tmp },
                target,
            );
            ctx.builder.set_current_block(target);
            ctx.builder.assign(dest, RvalueUse { value: operand_copy_local(tmp) });
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::collect_static_tagged_segments @ d9be6853b
// Flatten text/interpolation segments into `(parts, value_exprs)` honoring
// `parts.length() == value_exprs.length() + 1`. Returns `null` if any
// `${for}` / `${if}` block or value-less `${...}` is present (the flatten
// body runs those).
function collect_static_tagged_segments(
    segments: root.ast.TemplateSegment[],
) -> (string[], int[])? throws never {
    let parts: string[] = [];
    let values: int[] = [];
    let cur = "";
    for (let seg in segments) {
        match (seg) {
            let text: root.ast.TemplateSegmentText => {
                cur = cur + text.value;
            },
            let interp: root.ast.TemplateSegmentInterp => {
                // Close the current literal part, then record the value.
                parts.push(cur);
                cur = "";
                values.push(interp.value);
            },
            // Statements, loops and branches run in the flatten body.
            root.ast.TemplateSegmentEffect
                | root.ast.TemplateSegmentFor
                | root.ast.TemplateSegmentCStyleFor
                | root.ast.TemplateSegmentIf =>
            {
                return null;
            },
        }
    }
    // The trailing part (possibly empty): parts.length() == values.length() + 1.
    parts.push(cur);
    (parts, values)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::build_tagged_body_closure @ d9be6853b
// Hand-roll the tagged-template body closure, returning the closure value.
// Replicates `lower_lambda`'s state-save / param-decl / build / capture /
// `MakeClosure` skeleton, replacing the AST-body lowering with the
// array-builder (`static_layout`). `ctx.body` / `ctx.source_map` are NOT
// swapped: the interpolation exprs live in the current `ExprBody`.
function build_tagged_body_closure(
    ctx: LoweringContext,
    expr_id: int,
    body: int,
    body_params: (string, root.types.RuntimeTy)[],
    closure_ty: root.types.RuntimeTy,
    static_layout: (string[], int[])?,
) -> Operand throws MirInternalError {
    let lambda_identity = MirFunctionIdSynthetic {
        parent: ctx.builder.owner,
        kind: SyntheticKind.Tagged,
        ordinal: ctx.synthetic_ordinals.next(SyntheticKind.Tagged),
    };

    // Find the HIR Lambda scope registered for this tagged template (its
    // span is the tagged-template expr span). Two functions can carry a
    // tagged template at the same source span (a new-mode LLM function and
    // its `@spec` companion): prefer the lambda scope nested within the
    // function being lowered, and fall back to the first range match.
    let lambda_scope_id = ctx.current_scope;
    let sm = ctx.source_map;
    if (sm != null) {
        let span = sm.expr_span(expr_id);
        let index = root.hir.file_semantic_index(ctx.db, ctx.file);
        let found = index.lambda_scope_for_within(ctx.current_scope, span) ?? index.lambda_scope_for(span);
        if (found == null) {
            throw internal_error(
                ctx,
                `no HIR lambda scope for the tagged template at ${span.start}..${span.end}`,
                expr_id,
            );
        }
        lambda_scope_id = found;
    }

    let hir_captures = lambda_hir_captures(ctx, lambda_scope_id);
    let lambda_capture_indices: map<root.hir.BindingId, int> = {};
    let capture_idx = 0;
    for (let capture in hir_captures) {
        lambda_capture_indices[capture.1] = capture_idx;
        capture_idx += 1;
    }

    // Save parent state. `body` / `source_map` are intentionally NOT saved:
    // the interpolation exprs live in the current (enclosing) `ExprBody`.
    let saved_builder = ctx.builder;
    ctx.builder = MirBuilder.new(FunctionOwnerSynthetic { value: lambda_identity }, 0);
    let saved_binding_locals = ctx.binding_locals;
    ctx.binding_locals = {};
    let saved_catch_rethrow_locals = ctx.catch_rethrow_locals;
    ctx.catch_rethrow_locals = [];
    let saved_exit_block = ctx.exit_block;
    let saved_loop_context = ctx.loop_context;
    ctx.loop_context = null;
    let saved_current_scope = ctx.current_scope;
    let saved_metadata_scope = ctx.current_metadata_scope;
    let saved_pending_lambdas = ctx.pending_lambdas;
    ctx.pending_lambdas = [];
    let saved_capture_indices = ctx.capture_indices;
    ctx.capture_indices = null;
    let saved_transitive_captures = ctx.transitive_captures_needed;
    ctx.transitive_captures_needed = [];
    let saved_tagged_body_params = ctx.tagged_body_param_bindings;
    ctx.tagged_body_param_bindings = {};

    ctx.current_scope = lambda_scope_id;
    ctx.current_metadata_scope = root.hir.ExprMetadataScopeBody { value: lambda_scope_id };
    ctx.capture_indices = lambda_capture_indices;
    // Body params have no HIR binding: record each name with the synthetic
    // `BindingId.parameter` it is given below (same scope and index order as
    // the declare loop), so `lower_path_expr` resolves `${param}` interps to
    // the locals and a nested lambda referencing one can capture it
    // transitively by that binding.
    let tagged_body_param_bindings: map<string, root.hir.BindingId> = {};
    let param_idx = 0;
    for (let param in body_params) {
        tagged_body_param_bindings[param.0]
            = root.hir.BindingId.parameter(ctx.current_scope, param_idx);
        param_idx += 1;
    }
    ctx.tagged_body_param_bindings = tagged_body_param_bindings;

    let arity = body_params.length();
    ctx.builder = MirBuilder.new(FunctionOwnerSynthetic { value: lambda_identity }, arity);

    // Return place _0.
    let ret = ctx.builder.declare_local(root.types.TyNull {}, name = "_0");

    // Body params _1..=_n (the tag supplies their values when it calls
    // body). Declared captured unconditionally: HIR has no binding for them
    // to consult, and a nested lambda in an interpolation may capture one.
    param_idx = 0;
    for (let param in body_params) {
        let local = ctx.builder.declare_captured_local(param.0, param.1, null);
        ctx.binding_locals[root.hir.BindingId.parameter(ctx.current_scope, param_idx)] = local;
        param_idx += 1;
    }

    let entry = ctx.builder.create_block();
    let exit_blk = ctx.builder.create_block();
    ctx.exit_block = exit_blk;
    ctx.builder.set_current_block(entry);

    // Body: construct `baml.TaggedString { parts, values }`. The static
    // layout stands in for the desugared `body` block, whose own statements
    // are then never lowered.
    let skipped_desugar: int? = if (static_layout != null) {
        body
    } else {
        null
    };
    if (static_layout != null) {
        let parts = static_layout.0;
        let value_exprs = static_layout.1;
        let parts_ops: Operand[] = parts.map((s) -> Operand {
            OperandConstant { value: ConstantString { value: s } }
        });
        let parts_local = ctx.builder.declare_local(
            root.types.RuntimeTyList { elem: root.types.TyString {} },
            name = "__tt_parts",
        );
        // Tagged-template literal parts are always strings.
        ctx.builder.assign(
            PlaceLocal { value: parts_local },
            RvalueArray { element_ty: root.types.TyString {}, elements: parts_ops },
        );
        // Interps lower in the closure scope (body-param refs are locals,
        // enclosing-local refs captures), but their TIR types and
        // resolutions were inferred INLINE in the enclosing body, keyed
        // under the enclosing metadata scope: restore it so member/method
        // resolution lookups hit the recorded entries. Mirrors the dynamic
        // layout below.
        let prev_metadata_scope = ctx.current_metadata_scope;
        ctx.current_metadata_scope = saved_metadata_scope;
        let value_ops: Operand[] = [];
        for (let e in value_exprs) {
            value_ops.push(lower_to_operand(ctx, e));
        }
        ctx.current_metadata_scope = prev_metadata_scope;
        let values_local = ctx.builder.declare_local(
            root.types.RuntimeTyList { elem: root.types.TyUnknown {} },
            name = "__tt_values",
        );
        // Tagged-template interpolated values are heterogeneous.
        ctx.builder.assign(
            PlaceLocal { value: values_local },
            RvalueArray { element_ty: root.types.TyUnknown {}, elements: value_ops },
        );

        ctx.builder.assign(
            PlaceLocal { value: ret },
            RvalueAggregate {
                kind: AggregateKindClass {
                    class_: lang_class(ctx, root.base.LangPackage.Baml, [], "TaggedString"),
                    type_arg_templates: [],
                },
                fields: [operand_copy_local(parts_local), operand_copy_local(values_local)],
            },
        );
    } else {
        // A `${for}` / `${if}` block is present, so lengths are
        // data-dependent: lower the desugared `body` flatten block (built at
        // AST lowering, type-checked by TIR), which builds the TaggedString
        // with empty lists and `push` in real loops and branches. Its exprs
        // were inferred inline in the enclosing function, so restore the
        // enclosing metadata scope for the `expr_ty` / resolution lookups.
        let prev_metadata_scope = ctx.current_metadata_scope;
        ctx.current_metadata_scope = saved_metadata_scope;
        lower_expr(ctx, body, PlaceLocal { value: ret });
        ctx.current_metadata_scope = prev_metadata_scope;
    }

    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(ctx.exit_block);
    }
    ctx.builder.set_current_block(ctx.exit_block);
    ctx.builder.return_();

    verify_bindings_recorded(ctx, lambda_scope_id, skipped_desugar);

    let nested_lambdas = ctx.pending_lambdas;
    ctx.pending_lambdas = [];
    let lambda_builder = ctx.builder;
    ctx.builder = MirBuilder.new(lambda_builder.owner, 0);
    let lambda_mir = lambda_builder.build();
    optimize_function(ctx.db, lambda_mir, ctx.opt);
    lambda_mir.lambdas = nested_lambdas;

    let newly_needed_transitive = ctx.transitive_captures_needed;
    ctx.transitive_captures_needed = [];

    // Restore parent state.
    ctx.builder = saved_builder;
    ctx.binding_locals = saved_binding_locals;
    ctx.catch_rethrow_locals = saved_catch_rethrow_locals;
    ctx.exit_block = saved_exit_block;
    ctx.loop_context = saved_loop_context;
    ctx.current_scope = saved_current_scope;
    ctx.current_metadata_scope = saved_metadata_scope;
    ctx.capture_indices = saved_capture_indices;
    ctx.pending_lambdas = saved_pending_lambdas;
    ctx.transitive_captures_needed = saved_transitive_captures;
    ctx.tagged_body_param_bindings = saved_tagged_body_params;

    let capture_operands = lower_lambda_capture_operands(ctx, hir_captures, newly_needed_transitive, expr_id);

    let lambda_pending_idx = ctx.pending_lambdas.length();
    ctx.pending_lambdas.push(lambda_mir);

    let type_arg_templates = enclosing_runtime_type_arg_templates(ctx);

    let closure_local = ctx.builder.declare_local(closure_ty);
    ctx.builder.assign(
        PlaceLocal { value: closure_local },
        RvalueMakeClosure {
            lambda_idx: lambda_pending_idx,
            captures: capture_operands,
            type_arg_templates: type_arg_templates,
        },
    );
    operand_copy_local(closure_local)
}
