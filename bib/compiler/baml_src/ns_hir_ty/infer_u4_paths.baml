// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 4, paths: value paths (`resolve_value_path`) and the
// type-qualified value tiers (item projections, class and impl statics,
// enum variants).
//
// Restructured (BAML forces it):
// - `InferenceContext` methods are free functions taking `ctx` first.
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so `ClassRef`, `InterfaceRef` and `FunctionRef` are their Source lane, an
//   `int` loc, and the External arms are dropped: the `ResolvedValue::External`
//   arm of `resolve_value_path`, the `Exported` arms of `static_class_for`
//   and `interface_static_method`, the `mounted_*` fallbacks of
//   `static_class_for`, `interface_ref_for` and `enum_variant_value`.
// - `resolve_value_path` (371 lines) is split: the source-function arm is
//   `resolve_value_path_function`, the unresolved-name report
//   `resolve_value_path_unresolved`. `resolve_value` is pure, so the path's
//   value resolution is read once.
//
// Not ported: `extern_class_static_value` (External lane only), and
// `class_ref_generic_frame` / `class_ref_name`, which without the External
// lane forward to `class_generic_frame` / `class_qualified_name`.

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::resolve_value_path @ d9be6853b
function resolve_value_path(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    segments: string[],
    expected: Expectation,
) -> int throws never {
    let pool = ctx.table.pool;
    let item_head = item_head(ctx, expr, segments);
    // A type parameter or scoped `type` binding at the head shadows every
    // item, as in Rust: the path names members of that type variable, never
    // a package's or namespace's items. So below, the head is read as a
    // plain name and no package lane answers.
    let lexical_head = scoped_type_param_heads(ctx, item_head, segments);
    let head: root.hir.PathHead = if (lexical_head) {
        root.hir.PathHeadPlain {}
    } else {
        item_head
    };
    let resolved = ctx.lower.resolve_value(head, segments);
    let top_level_let_qualified_item = qualified_path_root_is_top_level_let(ctx, segments)
        && match (resolved) {
            let source: ResolvedValueSource => source.value is root.hir.DefinitionFunction,
            ResolvedValueExternal => true,
            _ => false,
        };
    if (path_resolves_locally(ctx, expr) && !top_level_let_qualified_item) {
        // The root resolves through the semantic index; the remaining
        // segments are member accesses (the AST cannot split `b.v` into
        // base+member before name resolution).
        let root_ty = infer_path(ctx, expr);
        let (let ty, let steps) = walk_path_members(ctx, expr, root_ty, segments.slice(1, segments.length()));
        write_resolved_path(ctx, expr, steps);
        return ty;
    }
    // Tagged-template body params (`prompt`'s `role`/`ctx`): the semantic
    // index cannot register them (the tag is a cross-file item), so they
    // resolve here, shadowing package items exactly as locals do, with the
    // same root + member-access fold.
    if (template_param_heads(ctx, head, segments)) {
        let root_ty = root.hir_ty.infer.template_param_ty(ctx, segments[0]);
        if (root_ty != null) {
            let (let ty, let steps) = walk_path_members(ctx, expr, root_ty, segments.slice(1, segments.length()));
            write_resolved_path(ctx, expr, steps);
            return ty;
        }
    }
    if let source: ResolvedValueSource = resolved {
        if let function_: root.hir.DefinitionFunction = source.value {
            return resolve_value_path_function(ctx, body, expr, segments, expected, function_.value);
        }
    }
    // A type-qualified static as a VALUE (`let f = float.nan;`,
    // `Array.filled`): the same tier the call spellings use, with the own
    // suffix fresh (only a call site can spell turbofish).
    if (segments.length() >= 2) {
        let prefix = segments.slice(0, segments.length() - 1);
        let member = segments[segments.length() - 1];
        let fn_ty = interface_static_value(ctx, head, prefix, member, OwnArgsFresh {}, expr, expr);
        if (fn_ty != null) {
            return fn_ty;
        }
        let static_ty = class_static_value(ctx, head, prefix, member, OwnArgsFresh {}, expr, expr);
        if (static_ty != null) {
            return static_ty;
        }
    }
    // `default.m` as a VALUE: the delegation target as a bound method value
    // (same scoped-receiver rule as the callee road).
    if (segments.length() == 2 && segments[0] == "default") {
        let interface_member = default_member(ctx, segments[1]);
        if (interface_member != null) {
            return interface_member_value(ctx, interface_member, expr);
        }
    }
    // Enum VARIANT values (`Shape.Rectangle`): the variant's singleton
    // literal type, the same product the type-position path gives
    // (`lower_path` fallback 2; r-a resolves the value namespace to the
    // variant the same way).
    let variant = enum_variant_value(ctx, head, segments, expr);
    if (variant != null) {
        return variant;
    }
    // Every reading of a type variable's members has declined above (a
    // static through its bound, `T.from_json`): the path names a member the
    // variable does not have, never the package item its spelling would
    // otherwise reach.
    if (lexical_head && segments.length() >= 2) {
        let param = scoped_type_param(ctx, segments[0]) ?? ctx.lower.lexical_generic(segments[0]);
        if (param != null) {
            report(
                ctx,
                PendingDiagUnresolvedMember {
                    expr: expr,
                    base: pool.from_plain(root.types.TyTypeVar { param: param }),
                    member: segments[1],
                },
            );
            return pool.add(root.types.TyError {});
        }
    }
    // A top-level `let` (a global variable, a client, or a Session's
    // persisted binding) named by the path's leading segments: bare (`x`)
    // in its own namespace, qualified from a package head (`root.ns.x`,
    // `dep.x`) anywhere else; the remaining segments are member accesses on
    // its value. Every other value tier runs first (functions, exported
    // values, statics, `default.m`, enum variants), so a global named like a
    // type never captures its statics: `float.nan` stays the static. A
    // global named like a package is an item of its namespace, and `head`
    // already reads `reflect.x` as that item there, as for any item (#4543).
    let global = global_root(ctx, head, segments);
    if (global != null) {
        let (let binding, let root_len) = global;
        // Recorded before typing: a reference whose type is cyclic is still
        // an edge the initialization-order analysis must see.
        ctx.result.global_roots[expr] = GlobalRoot { binding: binding, segments: root_len };
        let root_ty = global_value_ty(ctx, expr, binding)
            ?? return pool.add(root.types.TyError {});
        let (let ty, let steps) = walk_path_members(ctx, expr, root_ty, segments.slice(root_len, segments.length()));
        write_resolved_path(ctx, expr, steps);
        return ty;
    }
    // A name that RESOLVES to a definition kind this road doesn't type (a
    // global whose initializer is missing or untyped) is not unresolved: it
    // stays the silent sentinel it always was.
    if (resolved == null) {
        resolve_value_path_unresolved(ctx, expr, head, segments);
    }
    pool.add(root.types.TyError {})
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::resolve_value_path @ d9be6853b
// The arm of `resolve_value_path` for a path naming a source function: its
// value at a fresh instantiation, reported when generic and unspecialized.
// Restructured: split out of `resolve_value_path`.
function resolve_value_path_function(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    segments: string[],
    expected: Expectation,
    function_: int,
) -> int throws never {
    let db = ctx.db;
    let had_context = expectation_only_has_type(expected) != null || suppressed(ctx, Suppress.OptionalCallee);
    let signature = function_signature_with_diagnostics(db, function_).signature;
    let instantiation = signature.generic_params.map((param) -> {
        fresh_generic_arg(ctx, param)
    });
    let data = root.hir.function_data(db, function_);
    // An empty `data.generic_params`: synthetic callback-effect parameters
    // are inference-only; they do not make an otherwise non-generic function
    // value require explicit specialization.
    if (data.generic_params.length() > 0) {
        let user_params = function_user_generic_params(db, function_, signature);
        let specialization_example_is_safe = data.generic_params.every((param) -> {
            param.bounds.length() == 0
        });
        let has_phantom_param = user_params.some((param) -> {
            !signature_mentions_param(function_signature_ty(db, function_), signature.throws_, param)
        });
        let user_args = user_params.filter_map((param) -> {
            instantiation.at(param.index)
        });
        report(
            ctx,
            PendingDiagGenericFunctionValueNotSpecialized {
                expr: expr,
                name: data.name,
                reference: segments.join("."),
                inference_evidence: user_args,
                specialization_args: user_params.filter_map((param) -> {
                    instantiation.at(param.index)
                }),
                unconditional: !had_context,
                had_expected_type: had_context,
                generic_params: user_params.map((param) -> {
                    param.name
                }),
                binding_name: initializer_binding_name(body, expr),
                function_shape: if (has_phantom_param) {
                    null
                } else {
                    generic_function_value_shape(infer_ctx_viewpoint(ctx), db, function_, user_params, false, false)
                },
                annotation_ty: if (specialization_example_is_safe && !has_phantom_param) {
                    instantiate_callable_signature(db, function_, instantiation)
                } else {
                    null
                },
                specialization_example_is_safe: specialization_example_is_safe,
                specialization_syntax_available: true,
            },
        );
        // A function VALUE has no call site to seed its frame: the
        // instantiation inference settles rides with the value, and its
        // bounds are judged where the value is taken, as a call's are at the
        // call.
        write_call_type_args(ctx, expr, instantiation, 0);
        register_callable_instantiation(ctx, function_, instantiation, expr);
    }
    write_member_resolution(ctx, expr, MemberResolutionFree { func: function_ });
    instantiate_callable_signature(db, function_, instantiation)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::resolve_value_path @ d9be6853b
// The tail of `resolve_value_path` for a path that resolves to nothing.
// When a proper prefix resolves (`baml.media.Image.missing` has the valid
// type `baml.media.Image`), the segment AFTER the longest valid prefix is
// what failed: it is reported alone, not the whole dotted path (TIR's
// first-invalid-segment rule). A path with no valid prefix reports in full.
// Restructured: split out of `resolve_value_path`.
function resolve_value_path_unresolved(
    ctx: InferenceContext,
    expr: int,
    head: root.hir.PathHead,
    segments: string[],
) -> void throws never {
    let failed: string? = null;
    for (let cut = segments.length() - 1; cut >= 1; cut -= 1) {
        let prefix = segments.slice(0, cut);
        if (
            ctx.lower.resolve_type_definition(head, prefix) != null
                || ctx.lower.resolve_exported_type_definition(head, prefix) != null
                || ctx.lower.resolve_value(head, prefix) != null
        ) {
            failed = segments[cut];
            break;
        }
    }
    // A served dependency answers from its interface alone, and that
    // interface cannot tell a declaration it does not carry from a
    // misspelling, so a path into a served package that names nothing
    // reports exactly as the source lane reports it. The whole path names
    // nothing: when it is a path this package would spell `root.…`, say so.
    let suggestions = if (failed != null) {
        []
    } else {
        ctx.lower.value_suggestions(segments)
    };
    let name = failed ?? segments.join(".");
    let package = ctx.lower.package_shadowed_by_item(head, segments);
    if (package != null) {
        report(ctx, PendingDiagItemShadowsPackage { expr: expr, name: package });
    }
    let shorthand_name = ctx.property_shorthand_values.get(expr);
    if (shorthand_name != null) {
        let locals = local_binding_names_at(ctx, expr);
        report(
            ctx,
            PendingDiagUnresolvedShorthand {
                expr: expr,
                name: shorthand_name,
                suggestions: similar_name_suggestions(shorthand_name, locals),
            },
        );
    } else {
        report(ctx, PendingDiagUnresolvedName { expr: expr, name: name, suggestions: suggestions });
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::own_instantiation_with_bounds @ d9be6853b
// The own-generic slots of a member spelled at `anchor`: written at a call
// site, or fresh for a value reference. A fresh slot nothing solves is E0002
// at the anchor. This lane is reachable from a CALL too, since a consumed
// type-arg channel (`Bin<int>.pick()`, and equally the turbofish
// `Bin.pick<int>()`, which the channel cannot distinguish from it) hands the
// written args to the CLASS frame and leaves the member's own generics with
// no written source at all.
function own_instantiation_with_bounds(
    ctx: InferenceContext,
    own: OwnArgs,
    params: root.types.ParamTy[],
    callee: string,
    anchor: int,
    position: TypePosition,
) -> int[] throws never {
    match (own) {
        let call: OwnArgsCall => instantiation_args_at(ctx, call.value, params, callee, position),
        OwnArgsFresh => {
            params.map((param) -> {
                fresh_required_arg(ctx, param, anchor)
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::item_projection_value @ d9be6853b
// TIER: an ITEM PROJECTION, the `(Self type, interface, item)` triple, with
// either half optionally left to inference. The spellings differ only in
// which halves are written: `Interface.item` infers `qself` and writes the
// qualifier; `(Base as I).item` writes both.
//
// `Self` is slot 0 of an interface method's generic frame
// (`interface_frame`). A written `qself` PINS it; an inferred one leaves a
// fresh variable whose implements-bound rides along through
// `function_generic_bounds` and is discharged by the call's arguments. That
// one slot is the entire difference between the spellings.
//
// A turbofish binds the slots AFTER `Self`: the method's own generics and
// the interface's, never `Self` itself. The receiver is never bound: `self`
// stays the written first argument, the UFCS shape `Type.method(recv, ..)`
// already uses.
function item_projection_value(
    ctx: InferenceContext,
    interface_: int,
    written: WrittenQualifier?,
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    let db = ctx.db;
    let pool = ctx.table.pool;
    // The interface's own declaration of `member` (required and default
    // alike), its frame, the interface's declared generic count, and its
    // head. The frame is `[Self] ++ interface generics ++ the method's own
    // generics` (`interface_frame`).
    let method = interface_method_loc(ctx, interface_, member)
        ?? return null;
    let frame = function_signature_with_diagnostics(db, method).signature.generic_params;
    let pinned = root.hir.interface_data(db, interface_).generic_params.length();
    let iface_qtn = root.hir_ty.interfaces.interface_loc_qtn(db, interface_)
        ?? baml.sys.panic("a resolved interface item has a source QTN");
    if (frame.length() == 0) {
        baml.sys.panic("an interface method's generic frame always opens with `Self`");
    }
    let self_param = frame[0];
    let after_self = frame.slice(1, frame.length());
    // A written qualifier realizes the interface generics group and it is
    // PINNED from it: `Conv<int>` and `Conv<string>` are different interfaces
    // a type may implement both of. Associated types are not slots. The
    // clamp is Rust's release-mode net for a frame shorter than the
    // interface it was built from.
    let split = if (pinned < after_self.length()) {
        pinned
    } else {
        after_self.length()
    };
    let frame_params = after_self.slice(0, split);
    let own_params = after_self.slice(split, after_self.length());

    let instantiation: int[] = [];
    let self_slot = if (written != null) {
        written.qself
    } else {
        fresh_required_arg(ctx, self_param, anchor)
    };
    // Guards on the `Self` slot, deferred until inference resolves it: an
    // ERASED `Self` (an interface existential or a union) is admitted only
    // where the one-`Self` rule lets the call dispatch on it
    // (`callable_self_dispatch`). An UNRESOLVED `Self` is a hard error:
    // rustc's E0790, whose fix is the fully-qualified spelling.
    let dispatch = callable_self_dispatch(db, method);
    // The WRITTEN arguments name the interface in the message (`Conv<int>`
    // and `Conv<string>` differ); empty for the inferred spelling.
    // Associated types stay empty: they are determined, not written.
    let iface_ref = root.types.infer_interface_new(
        iface_qtn,
        if (written != null) {
            written.realized.generics.map((ty) -> {
                pool.from_plain(ty)
            })
        } else {
            []
        },
        [],
    );
    report(
        ctx,
        PendingDiagItemProjectionSelfSlot {
            expr: anchor,
            var: self_slot,
            interface_: iface_ref,
            member: member,
            dispatch: dispatch,
            value_position: own is OwnArgsFresh,
        },
    );
    instantiation.push(self_slot);
    let index = 0;
    for (let param in frame_params) {
        // Realized generics first; an unrealized slot (the `Interface.item`
        // spelling, which has no subject to realize against) stays a fresh
        // variable the call's arguments solve. A realization that comes up
        // short leaves the slot fresh.
        let realized_arg = if (written != null) {
            written.realized.generics.at(index)
        } else {
            null
        };
        instantiation.push(
            if (realized_arg != null) {
                pool.from_plain(realized_arg)
            } else {
                fresh_required_arg(ctx, param, anchor)
            },
        );
        index += 1;
    }
    // The slot's interface at the frame's generics group (`Self` is slot 0).
    let view = root.types.infer_interface_existential(
        pool,
        root.types.infer_interface_new(
            iface_qtn,
            instantiation.slice(1, instantiation.length()),
            [],
        ),
    );
    let own_args = own_instantiation_with_bounds(ctx, own, own_params, member, anchor, TypePosition.Existential);
    for (let arg in own_args) {
        instantiation.push(arg);
    }
    match (own) {
        let call: OwnArgsCall => {
            instantiation = write_call_type_args(ctx, call.value, instantiation, 0);
        },
        OwnArgsFresh => {
            // A VALUE reference has no call site, but MIR still needs the
            // (eventually solved) frame to resolve the callable: record it as
            // a plan keyed by the reference expression itself, the same
            // channel a call's instantiation rides. Writeback grounds it once
            // inference finishes.
            let plan = ctx.result.call_plans.get(anchor);
            if (plan == null) {
                plan = CallPlan.default();
                ctx.result.call_plans[anchor] = plan;
            }
            plan.type_args = instantiation.slice(0, instantiation.length());
            plan.own_offset = 0;
        },
    }
    register_callable_instantiation(ctx, method, instantiation, anchor);
    if (record_at != null) {
        // The slot is what is statically known (interface plus member),
        // recorded for default and required methods alike, and UNBOUND:
        // every spelling of this tier is type-rooted. Resolving the slot to a
        // concrete impl is downstream's job.
        write_member_resolution(
            ctx,
            record_at,
            MemberResolutionMethod<int> {
                callee: MethodCalleeVirtual<int> { interface_: interface_, view: view, method: member },
                receiver: Receiver.Unbound,
            },
        );
    }
    instantiate_callable_signature(db, method, instantiation)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::qualified_path_value @ d9be6853b
// The `(Base as I).item` spelling: both halves written. Validates them and
// hands the same tier its pinned `Self`.
//
// This is the only spelling that reaches two otherwise-unreachable members:
// one declared by several implemented interfaces (the bare `base.item` is
// E0121-ambiguous), and one whose `Self` appears in a parameter (the
// existential `base.as<I>.item` is object-safety rejected).
function qualified_path_value(
    ctx: InferenceContext,
    expr: int,
    member: string,
    own: OwnArgs,
    record_at: int?,
) -> int throws never {
    let pool = ctx.table.pool;
    // The parser builds this node only with both halves present, so a
    // missing anchor is a malformed body, already reported upstream.
    let anchors = ctx.type_refs.qualified_path_anchors.get(expr)
        ?? return pool.add(root.types.TyError {});
    let lower = (type_ref: root.hir.BodyTypeRefId, position: TypePosition) -> int {
        let (let ty, let diagnostics) = lower_body_type_ref_at(ctx, type_ref, position, HolePolicyAllowed {});
        queue_body_lowering_diagnostics(ctx, diagnostics);
        reject_expr_position_holes(ctx, ty, expr)
    };
    let qself = lower(anchors.qself, TypePosition.Existential);
    // The qualifier is a CONSTRAINT HEAD, not an existential: its associated
    // types are determined by `Self` and need not be written, exactly as in
    // a bound (`T extends I`).
    let lowered_interface = lower(anchors.interface_, TypePosition.ConstraintHead);
    if (pool.has_error(qself) || pool.has_error(lowered_interface)) {
        return pool.add(root.types.TyError {});
    }
    // The interface-view gate is a STRUCTURE demand, as it is for `.as<I>`:
    // an alias naming an interface answers as the interface.
    let interface_ = expand_alias_ty(ctx, lowered_interface);
    let qualifier = root.types.infer_interface_of_ty(pool, interface_);
    if (qualifier == null) {
        report(ctx, PendingDiagQualifierNotInterface { expr: expr, target: interface_ });
        return pool.add(root.types.TyError {});
    }
    let resolved_qself = structurally_resolve(ctx, qself);
    // Determination admits no unresolved inference variable. Both halves
    // are WRITTEN types, ground at lowering: a variable here comes only from
    // a written hole `reject_expr_position_holes` already reported.
    if (pool.has_infer(resolved_qself) || pool.has_infer(interface_)) {
        return pool.add(root.types.TyError {});
    }

    // Which half is at fault, from the SHARED determination road: the
    // qualifier must be an interface `qself` implements, and it must declare
    // `member` DIRECTLY (`requires` is a bound, not inheritance).
    let qself_plain = materialize_ty(ctx, resolved_qself);
    let interface_plain = materialize_ty(ctx, interface_);
    let (let determination, let diagnostics) = root.hir_ty.interfaces.determine_member_interface_with_facts(
        ctx.db,
        viewer(ctx),
        ctx.facts,
        qself_plain,
        interface_plain,
        member,
        root.hir_ty.interfaces.MemberNamespace.Value,
    );
    for (let error in diagnostics) {
        report(ctx, PendingDiagAnnotWf { type_ref: anchors.interface_, error: error });
    }
    let unresolved_member = () -> int {
        if (!suppressed(ctx, Suppress.MemberProbe)) {
            report(ctx, PendingDiagUnresolvedMember { expr: expr, base: interface_, member: member });
        }
        pool.add(root.types.TyError {})
    };
    let realized = match (determination) {
        let determined: root.hir_ty.interfaces.DeterminationDetermined => determined.value,
        root.hir_ty.interfaces.DeterminationSubjectDoesNotImplementQualifier => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagDoesNotImplement {
                        expr: expr,
                        value: resolved_qself,
                        interface_: interface_,
                        required_for: [],
                    },
                );
            }
            return pool.add(root.types.TyError {});
        },
        root.hir_ty.interfaces.DeterminationUndeclared
            | root.hir_ty.interfaces.DeterminationAmbiguous
            | root.hir_ty.interfaces.DeterminationInvalidBase =>
        {
            return unresolved_member();
        },
        // An already-poisoned input was reported where it was lowered.
        root.hir_ty.interfaces.DeterminationPoisoned => {
            return pool.add(root.types.TyError {});
        },
    };

    // Determination proved the member exists in the VALUE namespace, so a
    // miss below it is a FIELD, which has no static spelling.
    let interface_loc = interface_ref_for(ctx, qualifier.name)
        ?? return unresolved_member();
    item_projection_value(
        ctx,
        interface_loc,
        WrittenQualifier { qself: resolved_qself, realized: realized },
        member,
        own,
        expr,
        record_at,
    )
        ?? unresolved_member()
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_ref_for @ d9be6853b
// The interface a qualified type name denotes.
function interface_ref_for(ctx: InferenceContext, qtn: root.types.DeclName) -> int? throws never {
    match (definition_of(ctx.db, qtn)) {
        let interface_: root.hir.DefinitionInterface => interface_.value,
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_method_loc @ d9be6853b
// The interface's method item named `member`. Required and default methods
// alike: they are one item kind.
function interface_method_loc(
    ctx: InferenceContext,
    interface_: int,
    member: string,
) -> int? throws never {
    root.hir.interface_data(ctx.db, interface_).methods.find((method) -> {
        root.hir.function_data(ctx.db, method).name == member
    })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_static_value @ d9be6853b
// The `Interface.item` spelling: the interface is written, `Self` is
// inferred from the call's arguments. Bounds register at the instantiation,
// whatever the spelling.
function interface_static_value(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    let (let interface_, _) = interface_static_method(ctx, head, prefix, member)
        ?? return null;
    item_projection_value(ctx, interface_, null, member, own, anchor, record_at)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_static_value @ d9be6853b
// TIER: a class-qualified static (`Array.filled`, `float.nan`, alias and
// keyword qualifiers included). The class prefix takes the qualifier's
// pinned args when it carries them (an alias expansion), else fresh vars;
// the own suffix follows `own`. `record_at` keys the recorded resolution
// (the callee expression for calls).
function class_static_value(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    // The qualifier is resolved ONCE, to the class it denotes; each tier
    // below then reads that class.
    let static_class = static_class_for(ctx, head, prefix);
    if (static_class == null) {
        let written = lower_scoped_type_path(ctx, head, prefix);
        if (
            lowering_ty_any_node(written, (node) -> {
                node is root.types.TyError
            })
        ) {
            return null;
        }
        let target = ctx.table.pool.from_plain(reject_holes(written));
        return impl_static_value(ctx, target, member, own, anchor, record_at);
    }
    let (let class_, let pinned) = static_class;
    let inherent = source_class_static_value(ctx, class_, pinned, member, own, anchor, record_at);
    if (inherent != null) {
        return inherent;
    }
    // TIER: a type-qualified implements-block member on a class: the bare
    // spelling of the `(C as I).item` projection with the interface INFERRED.
    class_impl_static_value(ctx, class_, pinned, member, own, anchor, record_at)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_impl_static_value @ d9be6853b
// The impl tier of `class_static_value`: `C.item` / `C<args>.item` where
// `item` lives in an implements block. Mirrors `qualified_path_value` with
// the qualifier inferred: the determination must be UNIQUE.
//
// The receiver must be GROUND before determination runs, so the class
// arguments come only from the spelling: an alias expansion's pinned args,
// the hoisted receiver args (`Bin<int>.build(2)`), or an empty frame. A
// generic class with no written arguments does not reach this tier.
function class_impl_static_value(
    ctx: InferenceContext,
    class_: int,
    pinned: int[]?,
    member: string,
    own: OwnArgs,
    anchor: int,
    record_at: int?,
) -> int? throws never {
    let frame = class_generic_frame(ctx.db, class_);
    // The class arguments and whether the call's written type-arg channel
    // was consumed for them (the hoisted-receiver-args spelling).
    let args: int[] = [];
    let channel_consumed = false;
    if (pinned != null) {
        args = pinned;
    } else if (frame.length() > 0) {
        let call = match (own) {
            let c: OwnArgsCall => c.value,
            OwnArgsFresh => {
                return null;
            },
        };
        let written = ctx.type_refs.expr_type_args.get(call)
            ?? return null;
        // The whole prefix must be written and static: a partial or runtime
        // instantiation cannot ground the receiver here.
        if (written.length() != frame.length()) {
            return null;
        }
        // Lowered WITHOUT call-plan slot recording: these args live inside
        // the `Self` template, and the interface-item road reads recorded
        // slots as the method's OWN suffix.
        args
            = written.map((type_ref) -> {
                let (let lowered, let diagnostics) = lower_body_type_ref_at(ctx, type_ref, TypePosition.Existential, HolePolicyAllowed {});
                queue_body_lowering_diagnostics(ctx, diagnostics);
                reject_expr_position_holes(ctx, lowered, anchor)
            });
        channel_consumed = true;
    }
    let qself = class_ty_interned(ctx.table.pool, infer_ctx_lang(ctx), class_qualified_name(ctx.db, class_), args);
    let effective_own: OwnArgs = if (channel_consumed) {
        OwnArgsFresh {}
    } else {
        own
    };
    impl_static_value(ctx, qself, member, effective_own, anchor, record_at)
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
    let pool = ctx.table.pool;
    if (pool.has_infer(qself) || pool.has_error(qself)) {
        return null;
    }
    let (let determination, _) = root.hir_ty.interfaces.determine_member_interface_with_facts(
        ctx.db,
        viewer(ctx),
        ctx.facts,
        rendered_plain(pool, qself),
        null,
        member,
        root.hir_ty.interfaces.MemberNamespace.Value,
    );
    let realized = match (determination) {
        let determined: root.hir_ty.interfaces.DeterminationDetermined => determined.value,
        let ambiguous: root.hir_ty.interfaces.DeterminationAmbiguous => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagAmbiguousMember {
                        expr: anchor,
                        base: qself,
                        member: member,
                        sources: ambiguous.value.map((iface) -> {
                            root.types.infer_interface_from_constraint(pool, iface)
                        }),
                        is_field: false,
                    },
                );
            }
            return pool.add(root.types.TyError {});
        },
        root.hir_ty.interfaces.DeterminationUndeclared
            | root.hir_ty.interfaces.DeterminationSubjectDoesNotImplementQualifier
            | root.hir_ty.interfaces.DeterminationInvalidBase
            | root.hir_ty.interfaces.DeterminationPoisoned =>
        {
            return null;
        },
    };
    let interface_ = interface_ref_for(ctx, realized.name)
        ?? return null;
    item_projection_value(
        ctx,
        interface_,
        WrittenQualifier { qself: qself, realized: realized },
        member,
        own,
        anchor,
        record_at,
    )
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
    let db = ctx.db;
    let method = root.hir.class_data(db, class_).methods.find((method) -> {
        root.hir.function_data(db, method).name == member
    })
        ?? return null;
    let signature = function_signature_with_diagnostics(db, method).signature;
    let frame = class_generic_frame(db, class_);
    let position = if (is_reflect_package_function_lookup(ctx, method)) {
        TypePosition.ExtractionContract
    } else {
        TypePosition.Existential
    };
    // An unbound/static class method supplies the whole declared frame at
    // the call site: owner params first, then function params (TIR's
    // `UnboundMethod` rule). An alias-qualified class already pins the owner
    // prefix, so only the method suffix remains writable.
    let instantiation: int[] = [];
    let own_offset = 0;
    if (pinned != null) {
        let own_params = signature.generic_params.slice(frame.length(), signature.generic_params.length());
        instantiation
            = pinned.concat(
                own_instantiation_with_bounds(ctx, own, own_params, member, anchor, position),
            );
        own_offset = frame.length();
    } else {
        instantiation
            = own_instantiation_with_bounds(ctx, own, signature.generic_params, member, anchor, position);
    }
    let resolution = MemberResolutionMethod<int> {
        callee: MethodCalleeInherent { value: method },
        receiver: Receiver.Unbound,
    };
    if let call: OwnArgsCall = own {
        let written = write_call_type_args(ctx, call.value, instantiation, own_offset);
        register_callable_instantiation(ctx, method, written, anchor);
        if (record_at != null) {
            write_member_resolution(ctx, record_at, resolution);
        }
        return instantiate_callable_signature(db, method, written);
    }
    register_callable_instantiation(ctx, method, instantiation, anchor);
    if (instantiation.length() > 0) {
        // A static method VALUE has no receiver and no call site: its whole
        // frame (owner prefix included) rides with the value.
        write_call_type_args(ctx, anchor, instantiation, 0);
    }
    if (record_at != null) {
        write_member_resolution(ctx, record_at, resolution);
    }
    instantiate_callable_signature(db, method, instantiation)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::enum_variant_value @ d9be6853b
// TIER: an enum variant value (`Shape.Rectangle`): the singleton literal
// type, the same product the type position gives. `record_at` keys the
// recorded resolution.
function enum_variant_value(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    segments: string[],
    record_at: int?,
) -> int? throws never {
    if (segments.length() < 2) {
        return null;
    }
    let lowered = lower_scoped_type_path(ctx, head, segments);
    let variant = match (lowered) {
        let v: root.types.TyEnumVariant => v,
        _ => {
            return null;
        },
    };
    let ty = ctx.table.pool.from_plain(reject_holes(lowered));
    if (record_at != null) {
        if let enum_loc: root.hir.DefinitionEnum = definition_of(ctx.db, variant.name) {
            write_member_resolution(
                ctx,
                record_at,
                MemberResolutionVariant { enum_loc: enum_loc.value, variant: variant.variant },
            );
        }
    }
    ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::type_qualified_member_callee @ d9be6853b
// The `MemberAccess` spelling of a type-qualified callee uses the same
// interface, inherent, and impl lookup as a path spelling.
function type_qualified_member_callee(
    ctx: InferenceContext,
    call: int,
    base_expr: int,
    head: root.hir.PathHead,
    prefix: string[],
    member: string,
    record_at: int,
) -> int? throws never {
    let own = OwnArgsCall { value: call };
    let interface_ty = interface_static_value(ctx, head, prefix, member, own, call, record_at);
    if (interface_ty != null) {
        return interface_ty;
    }
    let class_ty = class_static_value(ctx, head, prefix, member, own, call, record_at);
    if (class_ty != null) {
        return class_ty;
    }
    enum_variant_value(ctx, head, prefix.concat([member]), record_at)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::static_class_for @ d9be6853b
// The class owning a TYPE-QUALIFIED static path's members: a resolved class
// path (`Array.filled`, `baml.Array.generate`), or a primitive KEYWORD head
// (`float.nan()`, `int.max_value()`) mapped through the language's
// builtin-class correspondence. A null args component means the qualifier
// wrote no instantiation (the call site fills fresh vars); an array pins it
// (an alias expansion carries its target's args).
function static_class_for(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
) -> (int, int[]?)? throws never {
    if (scoped_type_param_heads(ctx, head, prefix)) {
        return null;
    }
    if let source: ResolvedTypeDefinitionSource = ctx.lower.resolve_type(head, prefix) {
        if let class_: root.hir.DefinitionClass = source.value {
            return (class_.value, null);
        }
    }
    let ty = static_qualifier_ty(ctx, head, prefix)
        ?? return null;
    let (let class_, let args) = receiver_class(ctx.facts, ty, 8)
        ?? return null;
    (class_, args)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::static_qualifier_ty @ d9be6853b
// Anything else a static qualifier can denote: a primitive or media KEYWORD
// (annotation-grammar tokens, not paths), or an ALIAS (chains included). It
// becomes the TYPE it names, and the receiver-class correspondence maps type
// to class, the same table instance receivers use.
function static_qualifier_ty(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
) -> int? throws never {
    let pool = ctx.table.pool;
    let alias = if (prefix.length() == 1) {
        root.types.compiler_alias_by_spelling(prefix[0])
    } else {
        null
    };
    let builtin = if (alias != null) {
        root.types.compiler_alias_lower_class(pool, alias, [])
    } else {
        null
    };
    let ty = if (builtin != null) {
        builtin
    } else {
        pool.from_plain(reject_holes(lower_scoped_type_path(ctx, head, prefix)))
    };
    if (pool.has_error(ty)) {
        return null;
    }
    ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_static_method @ d9be6853b
// The method a TYPE-QUALIFIED interface path names (`IqDescribable.describe`,
// Rust's `Trait::method`). Interface methods are ordinary items, so the
// ordinary signature road serves: `Self` instantiates fresh and its
// implements-bound rides along through the callable's frame.
function interface_static_method(
    ctx: InferenceContext,
    head: root.hir.PathHead,
    prefix: string[],
    member: string,
) -> (int, int)? throws never {
    if (scoped_type_param_heads(ctx, head, prefix)) {
        return null;
    }
    let resolved = ctx.lower.resolve_type(head, prefix)
        ?? return null;
    match (resolved) {
        let source: ResolvedTypeDefinitionSource => {
            match (source.value) {
                let interface_: root.hir.DefinitionInterface => {
                    let method = interface_method_loc(ctx, interface_.value, member)
                        ?? return null;
                    (interface_.value, method)
                },
                _ => null,
            }
        },
        ResolvedTypeDefinitionExported => null,
    }
}
