// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 4, annotations: path heads and local paths (`infer_path`,
// `global_root`, `global_value_ty`), body annotations and the
// lowering-to-inference ingestion of `_` holes, and the free helpers
// `bind_receiver`, `generic_function_value_*` and `initializer_binding_name`.
//
// Restructured (BAML forces it):
// - `InferenceContext` methods are free functions taking `ctx` first; a free
//   function over interned types takes the pool first.
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so a `GlobalRef` is its Source lane, a let loc `int`: the
//   `ResolvedValue::ExternalLet` arm of `global_root` and the External arm of
//   `global_value_ty` are dropped.
// - `LoweringTy::contains_hole` / `contains_error` are not ported in
//   `ns_types`; both are `lowering_ty_any_node` with the matching predicate.
// - Rust's `debug_assert!(false, ..)` arms of `infer_path` (an index/walk
//   inconsistency) answer the error sentinel, as Rust's release build does.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::template_param_root @ d9be6853b
function template_param_root(ctx: InferenceContext, name: string) -> bool throws never {
    root.hir_ty.infer.template_param_ty(ctx, name) != null
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::global_root @ d9be6853b
// The top-level `let` a path's leading segments name, read from `head`, with
// how many segments name it: a plain path's first segment, an item of the
// current namespace (`x`), or the SHORTEST `<namespace*>.<item>` after a
// package head (`root.ns.x`, `dep.ns.x`).
function global_root(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
) -> (int, int)? throws never {
    // A plain head names an item of this namespace in one segment; a package
    // head is followed by `<namespace*>.<item>`.
    let (let first, let last) = match (head) {
        root.hir.PathHeadPlain => (1, 1),
        root.hir.PathHeadPackage | root.hir.PathHeadLang => (2, segments.length()),
    };
    for (let len = first; len <= last; len += 1) {
        if let source: ResolvedValueSource = ctx.lower.resolve_value(head, segments.slice(0, len)) {
            if let binding: root.hir.DefinitionLet = source.value {
                return (binding.value, len);
            }
        }
    }
    null
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::global_value_ty @ d9be6853b
// The type a read of global `binding` has: its annotation when it has one
// (read without inferring the initializer, which is what lets an annotated
// global appear in its own initializer's call graph), else the initializer's
// type, widened like any binding site.
//
// Null (after diagnosing) when an unannotated global's type depends on
// itself.
function global_value_ty(ctx: InferenceContext, expr: int, binding: int) -> int? throws never {
    let pool = ctx.table.pool;
    let declared = let_declared_type(ctx.db, binding);
    if (declared != null) {
        return pool.from_plain(declared);
    }
    let own = match (ctx.owner) {
        let owner: root.hir.BodyOwnerIdLet => owner.value == binding,
        _ => false,
    };
    if (own || let_owner_is_in_flight(ctx.db, binding)) {
        // A source global's type can only depend on itself through
        // references its initializer (or a function it reaches) makes, and
        // each of those is an initialization edge: the cycle is reported
        // once, deterministically, as E0181 by the globals pass. Reporting it
        // here too would be order-dependent and would advise an annotation
        // that cannot help.
        if (!suppressed(ctx, Suppress.MemberProbe) && !is_source_global(ctx.db, binding)) {
            report(ctx, PendingDiagTopLevelLetCycle { expr: expr });
        }
        return null;
    }
    // The initializer's own type is the EXPRESSION type, so a fresh literal
    // arrives unwidened. A top-level let is a binding site like any other,
    // so `global_value_type` widens it (an annotation is how a global opts
    // out), and the package interface exports the same type.
    let ty = global_value_type(ctx.db, binding)
        ?? return null;
    pool.from_plain(ty)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::template_param_heads @ d9be6853b
// Whether a path starts at a tagged-template body parameter: its first
// segment names one, and the path is read in scope at all; a path the
// compiler wrote into a language package (`PathHeadLang`) is not.
function template_param_heads(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
) -> bool throws never {
    match (head) {
        root.hir.PathHeadLang => false,
        root.hir.PathHeadPackage | root.hir.PathHeadPlain => {
            segments.length() > 0 && template_param_root(ctx, segments[0])
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::qualified_path_root_is_top_level_let @ d9be6853b
function qualified_path_root_is_top_level_let(
    ctx: InferenceContext,
    segments: string[],
) -> bool throws never {
    if (segments.length() <= 1) {
        return false;
    }
    match (ctx.lower.resolve_value(root.hir.PathHeadPlain {}, [segments[0]])) {
        let source: ResolvedValueSource => source.value is root.hir.DefinitionLet,
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::path_resolves_locally @ d9be6853b
// Whether a path expression names a local binding or parameter (which
// shadows any package-level name at a call site). Keyed under the current
// scope: a lambda body's expressions live in the semantic index under the
// LAMBDA's scope, not the owner's.
function path_resolves_locally(ctx: InferenceContext, expr: int) -> bool throws never {
    path_resolution(ctx, expr) is root.hir.PathResolutionLocal
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::path_resolution @ d9be6853b
// HIR's recorded reading of a value path's first segment.
function path_resolution(
    ctx: InferenceContext,
    expr: int,
) -> root.hir.PathResolution? throws never {
    let key = metadata_key(ctx, expr)
        ?? return null;
    ctx.index.path_resolution(key)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::item_head @ d9be6853b
// The head an ITEM reading of a value path is read from: HIR's recorded
// reading when no binding claims the path. A binding-headed path is read as
// an item in exactly one case (a session root `let` spelled like a package
// path, `qualified_path_root_is_top_level_let`), and then the head is the one
// its name has.
function item_head(
    ctx: InferenceContext,
    expr: int,
    segments: string[],
) -> root.hir.PathHead throws never {
    match (path_resolution(ctx, expr)) {
        let item: root.hir.PathResolutionItem => item.value,
        _ => ctx.lower.path_head(segments),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::binding_for_pattern @ d9be6853b
// The `BindingId` a pattern introduces, searched within the current owner's
// scope subtree (`PatId`s are per-body arenas; the subtree restriction keeps
// other bodies' ids apart). The reverse of `LocalBinding.bind_pattern`, for
// bindings introduced by non-let constructs (catch clauses).
function binding_for_pattern(
    ctx: InferenceContext,
    pattern: int,
) -> root.hir.BindingId? throws never {
    let owner = ctx.owner_scope
        ?? return null;
    let descendants = ctx.index.scopes.at(owner)?.descendants
        ?? return null;
    let subtree = [owner];
    for (let scope_id = descendants.start; scope_id < descendants.end; scope_id += 1) {
        subtree.push(scope_id);
    }
    for (let scope_id in subtree) {
        let bindings = ctx.index.scope_bindings.at(scope_id)
            ?? return null;
        let index = 0;
        for (let binding in bindings.bindings) {
            if (binding.bind_pattern == pattern) {
                return root.hir.BindingId.local(scope_id, index);
            }
            index += 1;
        }
    }
    null
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_path @ d9be6853b
// Resolves a path expression to a local binding or a parameter through the
// semantic index. Owner parameters come from the lowered signature; lambda
// parameters from the signatures `infer_lambda` deduced. Non-local names go
// through `resolve_value_path`.
function infer_path(ctx: InferenceContext, expr: int) -> int throws never {
    let pool = ctx.table.pool;
    let key = metadata_key(ctx, expr)
        ?? return pool.add(root.types.TyError {});
    let local = match (ctx.index.path_resolution(key)) {
        let l: root.hir.PathResolutionLocal => l.value,
        // The index said the path resolves locally; anything else here is an
        // inconsistency between the index and this walk.
        _ => {
            return pool.add(root.types.TyError {});
        },
    };
    // The flow overlay wins over the declared/widened binding type
    // (narrowed within a match arm).
    let narrowed = ctx.flow.get(local);
    if (narrowed != null) {
        return narrowed;
    }
    match (local.kind) {
        root.hir.BindingKindLocal => {
            let binding = ctx.index.local_binding(local);
            let ty = if (binding != null) {
                ctx.result.type_of_pat.get(binding.bind_pattern)
            } else {
                null
            };
            ty ?? pool.add(root.types.TyError {})
        },
        let param: root.hir.BindingKindParameter => {
            let params = if (local.scope == ctx.owner_scope) {
                ctx.param_tys
            } else {
                ctx.lambda_params.get(local.scope)
            };
            params?.at(param.value) ?? pool.add(root.types.TyError {})
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lower_body_annotation @ d9be6853b
// One body-position annotation, lowered and hole-instantiated: the single
// entry for every type written inside a body (let ascriptions, lambda
// signature slots; turbofish go through `instantiation_args`).
function lower_body_annotation(
    ctx: InferenceContext,
    type_ref: root.hir.BodyTypeRefId,
) -> int throws never {
    let cached = ctx.annotation_cache.get(type_ref);
    if (cached != null) {
        return cached;
    }
    let (let lowered, let diagnostics) = lower_body_type_ref_at(ctx, type_ref, TypePosition.Existential, HolePolicyAllowed {});
    queue_body_lowering_diagnostics(ctx, diagnostics);
    // Written-type well-formedness (rustc's wfcheck at body annotations):
    // generic arguments must satisfy their heads' declared bounds.
    // Hole-carrying annotations skip: their holes solve first and the
    // instantiation sites judge them.
    if (
        !lowering_ty_any_node(lowered, (node) -> {
            node is root.types.TyInfer
        })
    ) {
        let owner_env = ctx.wf_scope_env;
        if (owner_env == null) {
            let function_ = owner_function(ctx);
            owner_env
                = if (function_ != null) {
                    function_generic_bounds(ctx.db, function_)
                } else {
                    {}
                };
            ctx.wf_scope_env = owner_env;
        }
        // A bounded `let type` binding in scope carries its own bounds.
        let scoped_bounds = ctx.scoped_type_bindings.filter((binding) -> {
            binding.bounds.length() > 0
        });
        let env = owner_env;
        if (scoped_bounds.length() > 0) {
            env = {};
            for (let param in owner_env.keys()) {
                env[param] = owner_env[param];
            }
            for (let binding in scoped_bounds) {
                env[binding.parameter] = binding.bounds;
            }
        }
        for (let error in root.hir_ty.interfaces.type_generic_bound_errors(ctx.db, env, lowered)) {
            report(ctx, PendingDiagAnnotWf { type_ref: type_ref, error: error });
        }
    }
    let instantiated = instantiate_holes(ctx, lowered, HoleAnchorTypeRef { value: type_ref });
    ctx.annotation_cache[type_ref] = instantiated;
    instantiated
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::instantiate_holes @ d9be6853b
// The `process_user_written_ty` funnel (rust-analyzer's discipline):
// lowering is pure and emits var-less hole nodes for `_`; the inference side
// instantiates each hole as a fresh table variable, filled from context.
function instantiate_holes(
    ctx: InferenceContext,
    ty: root.types.LoweringTy,
    at: HoleAnchor,
) -> int throws never {
    ingest_lowered(ctx, ty, IngestHolesAnchored { value: at })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::ingest_lowered @ d9be6853b
// The lowering-to-inference ingestion: intern the closed structure, and let
// the policy decide what each `_` hole becomes. Both policies mint a fresh
// table variable; they differ in whether the hole is legal (annotation
// positions record it in `hole_vars` for unsolved-hole reporting) or
// immediately diagnosed (expression positions, an unconditional E0147).
function ingest_lowered(
    ctx: InferenceContext,
    ty: root.types.LoweringTy,
    policy: IngestHoles,
) -> int throws never {
    if (ty is root.types.TyInfer) {
        return match (policy) {
            let anchored: IngestHolesAnchored => {
                let var_ty = ctx.table.new_var_ty();
                if let var: root.types.TyInferVar = ctx.table.pool.kinds[var_ty] {
                    ctx.hole_vars.push((var.var, anchored.value));
                }
                var_ty
            },
            let position: IngestHolesExprPosition => {
                report(ctx, PendingDiagExprPositionHole { expr: position.value });
                // The report above owns the class, whatever it merges into:
                // nothing it leaves undetermined reports again.
                let var_ty = ctx.table.new_var_ty();
                ctx.table.taint_vars_in(var_ty);
                var_ty
            },
        };
    }
    // No holes below: the interned ingestion is total.
    let closed = root.types.narrow_lowering_ty_to_ty(ty) catch (e) {
        root.types.NarrowError => {
            return ingest_lowered_slow(ctx, ty, policy);
        },
    };
    ctx.table.pool.from_plain(closed)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::ingest_lowered_slow @ d9be6853b
// The hole-carrying slow path of `ingest_lowered`: rebuild the recursive
// shapes interned with each child re-ingested. Leaves never reach here (a
// leaf is closed, so the fast path takes it).
function ingest_lowered_slow(
    ctx: InferenceContext,
    ty: root.types.LoweringTy,
    policy: IngestHoles,
) -> int throws never {
    let ingest = (child: root.types.LoweringTy) -> int {
        ingest_lowered(ctx, child, policy)
    };
    let ingest_interface = (interface_: root.types.LoweringInterfaceConstraint) -> root.types.InferInterfaceConstraint {
        root.types.infer_interface_new(
            interface_.name,
            interface_.generics.map(ingest),
            interface_.associated_types.map((pin) -> {
                root.types.InferAssociatedType { name: pin.name, ty: ingest(pin.ty) }
            }),
        )
    };
    let kind: root.types.InferTy = match (ty) {
        let list: root.types.LoweringTyList => root.types.InferTyList { elem: ingest(list.elem) },
        let map: root.types.LoweringTyMap => {
            root.types.InferTyMap { key: ingest(map.key), value: ingest(map.value) }
        },
        let union: root.types.LoweringTyUnion => {
            root.types.InferTyUnion { members: union.members.map(ingest) }
        },
        let tuple: root.types.LoweringTyTuple => {
            root.types.InferTyTuple { items: tuple.items.map(ingest) }
        },
        let class_: root.types.LoweringTyClass => {
            root.types.InferTyClass { name: class_.name, args: class_.args.map(ingest) }
        },
        let interface_: root.types.LoweringTyInterface => {
            root.types.InferTyInterface {
                name: interface_.name,
                args: interface_.args.map(ingest),
                associated_types: interface_.associated_types.map((pin) -> {
                    root.types.InferAssociatedType { name: pin.name, ty: ingest(pin.ty) }
                }),
            }
        },
        let function_: root.types.LoweringTyFunction => {
            root.types.InferTyFunction {
                params: function_.params.map((param) -> {
                    root.types.InferFunctionParamTy {
                        name: param.name,
                        ty: ingest(param.ty),
                        mode: param.mode,
                    }
                }),
                ret: ingest(function_.ret),
                throws_: ingest(function_.throws_),
            }
        },
        let future: root.types.LoweringTyFuture => {
            root.types.InferTyFuture { value: ingest(future.value), error: ingest(future.error) }
        },
        let projection: root.types.LoweringTyAssociatedTypeProjection => {
            root.types.InferTyAssociatedTypeProjection {
                base: ingest(projection.base),
                interface_: ingest_interface(projection.interface_),
                member: projection.member,
            }
        },
        _ => baml.sys.panic("closed leaves take the ingest fast path"),
    };
    ctx.table.pool.add(kind)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::reject_expr_position_holes @ d9be6853b
// `instantiate_holes` for EXPRESSION-position type arguments (turbofish,
// generic-apply values, upcast targets): a written `_` there is a hard E0147
// outright, TIR's rule; expression positions have no annotation slot for
// inference to fill. The hole still instantiates as a fresh var so
// inference proceeds for RECOVERY, but the diagnostic is unconditional and
// immediate.
function reject_expr_position_holes(
    ctx: InferenceContext,
    ty: root.types.LoweringTy,
    at: int,
) -> int throws never {
    ingest_lowered(ctx, ty, IngestHolesExprPosition { value: at })
}

// port: baml_type/src/lib.rs::LoweringTy::any_node @ d9be6853b
// Whether `pred` holds for `ty` or any type nested in it: Rust's
// `contains_hole` (`TyInfer`) and `contains_error` (`TyError`), which
// `ns_types` does not port.
function lowering_ty_any_node(
    ty: root.types.LoweringTy,
    pred: (root.types.LoweringTy) -> bool throws never,
) -> bool throws never {
    pred(ty)
        || root.types.children_lowering_ty(ty).some((child) -> {
            lowering_ty_any_node(child, pred)
        })
}

// port: baml_compiler2_hir_ty/src/infer.rs::bind_receiver @ d9be6853b
// An instance-accessed METHOD as a value is receiver-BOUND: the access
// consumes the `self` slot (`greeter.handle` is `(req) -> Response`, the
// runtime hands out a bound closure). Static/UFCS spellings (`Type.method`)
// keep the full signature; there the receiver arrives as the written first
// argument. Non-methods pass through untouched.
function bind_receiver(pool: root.types.InferPool, fn_ty: int) -> int throws never {
    let function_ = match (pool.kinds[fn_ty]) {
        let f: root.types.InferTyFunction => f,
        _ => {
            return fn_ty;
        },
    };
    let binds = function_.params.length() > 0 && function_.params[0].name == "self";
    if (!binds) {
        return fn_ty;
    }
    pool.add(
        root.types.InferTyFunction {
            params: function_.params.slice(1, function_.params.length()),
            ret: function_.ret,
            throws_: function_.throws_,
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::generic_function_value_ty @ d9be6853b
// The callable's value type at its own symbolic frame (each slot its rigid
// parameter), optionally with the user-facing params set to `int` as a
// concrete example: the shape the "not specialized" diagnostic shows.
function generic_function_value_ty(
    db: root.hir.Db,
    callable: int,
    user_params: root.types.ParamTy[],
    receiver_is_bound: bool,
    concrete_example: bool,
) -> int throws never {
    let pool = db.ty_memo.pool;
    let instantiation = callable_generic_frame(db, callable).params.map((param) -> {
        pool.add(root.types.TyTypeVar { param: param })
    });
    if (concrete_example) {
        for (let param in user_params) {
            if (param.index < instantiation.length()) {
                instantiation[param.index] = pool.add(root.types.TyInt {});
            }
        }
    }
    let ty = instantiate_callable_signature(db, callable, instantiation);
    if (receiver_is_bound) {
        bind_receiver(pool, ty)
    } else {
        ty
    }
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
    let ty = generic_function_value_ty(db, callable, user_params, receiver_is_bound, concrete_example);
    vp.source_text(rendered_plain(db.ty_memo.pool, ty)) catch (e) {
        Unspellable => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::initializer_binding_name @ d9be6853b
function initializer_binding_name(
    body: root.ast.ExprBody,
    initializer: int,
) -> string? throws never {
    for (let stmt in body.stmts) {
        if let let_: root.ast.StmtLet = stmt {
            if (let_.initializer == initializer) {
                if let bind: root.ast.PatternBind = body.patterns[let_.pattern] {
                    return bind.name;
                }
            }
        }
    }
    null
}
