// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// MIR unit 4, type-tag classification (shared by match and catch switch
// dispatch) and `catch` lowering.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - `lower_catch`'s nested `struct ClauseBindings` and `fn install_binding`
//   / `fn install_clause_bindings` are top-level items of the same names.
//   Its sequential fallback (the arm chain and arm bodies) is
//   `lower_catch_chain`, called where the block was.
// - `catch_rethrow_locals.truncate(mark)` pops in place down to `mark`, so
//   whoever holds the array (a lambda's saved copy) sees what Rust's
//   `Vec` would.
// - `baml_type::typetag::X` is `root.types.TYPETAG_X`.
// - Rust's `dest.clone()` is `place_clone(dest)`: the optimizer rewrites
//   places in place, so a place in two MIR positions must be two objects.
// - `classify_pattern_type_tag`'s inline `ascription_ty` match is the same
//   match as `pattern_narrow_type`, which it calls.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::classify_pattern_type_tag @ d9be6853b
// Classify a pattern as type-tag-eligible and return its tag(s), for
// switch dispatch.
//
// Shared by match and catch lowering. `scrutinee_static_ty` is the
// enclosing match scrutinee's resolved static type when known (null on the
// catch path, whose error value has no useful static type); the
// tag-sufficiency gate uses it to disqualify arms whose coarse tag would
// conflate values the scrutinee admits (see `ty_to_type_tags_for_switch`).
//
// Returns the tags for `TypedBinding` and Binding-with-TIR-type patterns
// that resolve to primitive or class types; null for literals, wildcards,
// enum variants, and types without tag mappings.
function classify_pattern_type_tag(
    ctx: LoweringContext,
    pat_id: int,
    scrutinee_static_ty: root.types.RuntimeTy?,
) -> SwitchKey[]? throws never {
    let pat = ctx.body.patterns[pat_id];
    if (pattern_contains_structural(ctx, pat_id)) {
        return null;
    }
    // A generic-interface pattern (`Slot<int>`, or one nested in a union /
    // optional) cannot be discriminated by a flat type-tag switch: every
    // instantiation shares the bare interface's implementor tags, so arms
    // would collide and the first would wrongly capture all of them.
    // Disqualify the switch so the match-chain runtime test, which filters
    // implementors by the specific instantiation, is used instead.
    let pat_tir_ty = tir_pat_type(ctx, pat_id);
    if (pat_tir_ty != null && tir_ty_needs_interface_shape_test(pat_tir_ty)) {
        return null;
    }
    // Bind/Array patterns may carry a `:T` type ascription; resolve via the
    // ascription's TypeExpr if present. For Bind, the ascription is the
    // sub-pattern when it's a `Type(...)` shape.
    let ascription_ty = pattern_narrow_type(ctx, pat_id);
    if (ascription_ty != null) {
        if (pat_tir_ty != null) {
            let resolved = runtime(ctx).convert(pat_tir_ty);
            return ty_to_type_tags_for_switch(ctx, resolved, scrutinee_static_ty);
        }
        let resolved = resolve_type_annotation(ctx, ascription_ty);
        return ty_to_type_tags_for_switch(ctx, resolved, scrutinee_static_ty);
    }
    match (pat) {
        root.ast.PatternWildcard => null,
        root.ast.PatternBind => {
            let tir_ty = pat_tir_ty
                ?? return null;
            let resolved = runtime(ctx).convert(tir_ty);
            ty_to_type_tags_for_switch(ctx, resolved, scrutinee_static_ty)
        },
        let p: root.ast.PatternType => {
            if (pat_tir_ty != null) {
                let resolved = runtime(ctx).convert(pat_tir_ty);
                return ty_to_type_tags_for_switch(ctx, resolved, scrutinee_static_ty);
            }
            let resolved = resolve_type_annotation(ctx, p.value);
            ty_to_type_tags_for_switch(ctx, resolved, scrutinee_static_ty)
        },
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ty_to_type_tags_for_switch @ d9be6853b
// `ty_to_type_tags`, additionally requiring every flattened member of `ty`
// to be *tag-sufficient* for a switch keyed on those tags (see
// `switch_member_tag_sufficient`): a coarse tag may only key a jump-table
// arm when it cannot conflate values the scrutinee admits onto the wrong
// arm (`int[]` and `string[]` share the LIST tag, `Foo<int>` and
// `Foo<string>` share `Foo`'s tag, and the tag dedup would silently drop
// the second arm). An insufficient member disqualifies the pattern (null),
// which makes `try_lower_as_switch` fall back to the precise sequential
// chain.
function ty_to_type_tags_for_switch(
    ctx: LoweringContext,
    ty: root.types.RuntimeTy,
    scrutinee_static_ty: root.types.RuntimeTy?,
) -> SwitchKey[]? throws never {
    let tags = ty_to_type_tags(ctx, ty)
        ?? return null;
    let members: root.types.RuntimeTy[] = [];
    flatten_runtime_union(ty, members);
    if (
        members.every((m) -> {
            switch_member_tag_sufficient(m, scrutinee_static_ty)
        })
    ) {
        tags
    } else {
        null
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ty_to_type_tags @ d9be6853b
// Convert a `RuntimeTy` to the list of switch keys it corresponds to.
// Returns null if the type has no simple tag representation.
//
// Supports primitives (globally-stable tags) and class types (keyed by
// their declaration). Union types are flattened: all members must be
// tag-eligible.
function ty_to_type_tags(
    ctx: LoweringContext,
    ty: root.types.RuntimeTy,
) -> SwitchKey[]? throws never {
    match (ty) {
        let u: root.types.RuntimeTyUnion => {
            let keys: SwitchKey[] = [];
            for (let m in u.members) {
                let member_keys = ty_to_type_tags(ctx, m)
                    ?? return null;
                for (let key in member_keys) {
                    keys.push(key);
                }
            }
            keys
        },
        _ => {
            let key = type_tag_for_ty(ctx, ty)
                ?? return null;
            [key]
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::format_type_tag_name @ d9be6853b
// Format a type tag integer as a human-readable name for switch arm debug
// metadata.
function format_type_tag_name(tag: int) -> string throws never {
    match (tag) {
        let t if t == root.types.TYPETAG_INT => "int",
        let t if t == root.types.TYPETAG_BIGINT => "bigint",
        let t if t == root.types.TYPETAG_STRING => "string",
        let t if t == root.types.TYPETAG_BOOL => "bool",
        let t if t == root.types.TYPETAG_NULL => "null",
        let t if t == root.types.TYPETAG_FLOAT => "float",
        let t if t == root.types.TYPETAG_LIST => "list",
        let t if t == root.types.TYPETAG_TUPLE => "tuple",
        let t if t == root.types.TYPETAG_MAP => "map",
        let t if t == root.types.TYPETAG_ENUM => "enum",
        let t if t == root.types.TYPETAG_FUNCTION => "function",
        let t if t == root.types.TYPETAG_FUTURE => "future",
        let t if t == root.types.TYPETAG_TYPE => "reflect.Type",
        let t if t == root.types.TYPETAG_UINT8ARRAY => "uint8array",
        _ if tag >= root.types.TYPETAG_CLASS_BASE => `class#${tag - root.types.TYPETAG_CLASS_BASE}`,
        _ => `tag#${tag}`,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_catch::ClauseBindings @ d9be6853b
// A clause's own bindings (`catch (e)` / `catch (e, trace)`) by name and the
// pattern HIR registered each under.
class ClauseBindings {
    error: (string, int)?,
    stack_trace: (string, int)?,
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_catch::install_binding @ d9be6853b
// Create one clause binding on entry to a handler arm. The runtime wrote its
// value into `source`; an uncaptured binding is that slot itself, a captured
// one gets a celled local of its own, copied from it. Returns that own
// local.
function install_binding(
    ctx: LoweringContext,
    binding: (string, int)?,
    source: int?,
) -> int? throws MirInternalError {
    if (binding == null || source == null) {
        return null;
    }
    let (let name, let pattern) = binding;
    let site = root.hir.DefinitionSiteCatchBinding { value: pattern };
    if (!pattern_binding_is_captured(ctx, pattern, site, name)) {
        bind_existing_local(ctx, pattern, site, name, source);
        return null;
    }
    let local = declare_binding(ctx, pattern, site, name, root.types.TyUnknown {});
    let value = value_place(ctx, local);
    ctx.builder.assign(value, RvalueUse { value: operand_copy_local(source) });
    local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_catch::install_clause_bindings @ d9be6853b
// Create a clause's bindings on entry to one of its arms, returning the
// error binding's own local when it has one, so a `rethrow` in the arm
// treats it as the caught error too.
function install_clause_bindings(
    ctx: LoweringContext,
    error_local: int,
    context_local: int,
    clause: ClauseBindings,
) -> int? throws MirInternalError {
    let error_copy = install_binding(ctx, clause.error, error_local);
    install_binding(ctx, clause.stack_trace, context_local);
    error_copy
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_catch @ d9be6853b
function lower_catch(
    ctx: LoweringContext,
    _expr_id: int,
    base: int,
    clause: root.ast.CatchClause,
    dest: Place,
) -> void throws MirInternalError {
    let bb_join = ctx.builder.create_block();

    let first_name = root.ast.pattern_binding_name(ctx.body.patterns[clause.binding], ctx.body.patterns);
    let binding_name = if (
        first_name != null
            && !pattern_binding_is_captured(
                ctx,
                clause.binding,
                root.hir.DefinitionSiteCatchBinding { value: clause.binding },
                first_name,
            )
    ) {
        first_name
    } else {
        null
    };
    let error_local = ctx.builder.declare_local(root.types.TyUnknown {}, name = binding_name);

    // Every landing receives the caught error's context, bound or not: a
    // rethrow from an arm carries it, and a throw during an arm takes it as
    // its cause.
    let context_local = ctx.builder.declare_local(root.types.TyUnknown {});

    // The handler block: the VM lands in it with the error and context
    // locals. Created under the outer handler, like `bb_join`, so neither is
    // protected by this catch.
    let bb_handler = ctx.builder.create_handler_block(
        Landing { error_local: error_local, context_local: context_local },
    );

    let name_of = (pattern: int) -> (string, int)? {
        let name = root.ast.pattern_binding_name(ctx.body.patterns[pattern], ctx.body.patterns)
            ?? return null;
        (name, pattern)
    };
    let clause_bindings = ClauseBindings {
        error: name_of(clause.binding),
        stack_trace: if let trace: int = clause.stack_trace_binding {
            name_of(trace)
        } else {
            null
        },
    };
    let wildcard_traps = root.ast.catch_clause_kind_wildcard_traps_panics(clause.kind);
    let arms = clause.arms.map((id) -> (root.ast.CatchArm, bool) {
        let arm = ctx.body.catch_arms[id];
        let skips_panics = is_irrefutable_catch_all(ctx, arm.pattern) && !wildcard_traps;
        (arm, skips_panics)
    });

    // A chained catch is a nested base. Its own landing and arm blocks are
    // protected by this handler; its base uses its own handler. The try
    // body unwinds to `bb_handler`; what follows the catch expression
    // unwinds to the outer handler again.
    let outer_unwind = ctx.builder.current_unwind;
    ctx.builder.transition_unwind(bb_handler);
    lower_expr(ctx, base, place_clone(dest));
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_join);
    }
    ctx.builder.transition_unwind(outer_unwind);

    // Attempt switch-style dispatch on type tags. If all non-wildcard arms
    // have pure type-test patterns, emit a single Switch on
    // `Rvalue::TypeTag` instead of a sequential is_type chain.
    let switch_arms = arms.map((arm) -> (int, int, int?) {
        (arm.0.pattern, arm.0.body, null)
    });
    // The arms are lowered out of line in `bb_handler`, unwinding to the
    // outer handler, as this catch's handler body: a throw in an arm is
    // "during handling of" the caught error (the cause chain).
    let arms_out_of_line = ctx.builder.begin_out_of_line(bb_handler, outer_unwind, bb_handler);
    let switch_rethrow_mark = ctx.catch_rethrow_locals.length();
    let error_copy = install_clause_bindings(ctx, error_local, context_local, clause_bindings);
    ctx.catch_rethrow_locals.push((error_local, context_local));
    if (error_copy != null) {
        ctx.catch_rethrow_locals.push((error_copy, context_local));
    }
    let lowered_as_switch = try_lower_as_switch(
        ctx,
        error_local,
        switch_arms,
        place_clone(dest),
        bb_join,
        SwitchOtherwiseCatch {
            error_local: error_local,
            context_local: context_local,
            wildcard_skips_panics: arms.some((arm) -> {
                arm.1
            }),
        },
        null,
    );
    while (ctx.catch_rethrow_locals.length() > switch_rethrow_mark) {
        ctx.catch_rethrow_locals.pop();
    }
    if (lowered_as_switch) {
        ctx.builder.end_out_of_line(arms_out_of_line);
        ctx.builder.set_current_block(bb_join);
        return;
    }

    lower_catch_chain(ctx, error_local, context_local, clause_bindings, arms, dest, bb_join);

    ctx.builder.end_out_of_line(arms_out_of_line);
    ctx.builder.set_current_block(bb_join);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_catch @ d9be6853b
// `lower_catch`'s fallback: the sequential pattern-test chain, then each
// arm body.
function lower_catch_chain(
    ctx: LoweringContext,
    error_local: int,
    context_local: int,
    clause_bindings: ClauseBindings,
    arms: (root.ast.CatchArm, bool)[],
    dest: Place,
    bb_join: int,
) -> void throws MirInternalError {
    // Create body blocks now (not created earlier so the switch path doesn't
    // leave orphaned unterminated blocks).
    let arms_with_blocks = arms.map((arm) -> (root.ast.CatchArm, int, bool) {
        (arm.0, ctx.builder.create_block(), arm.1)
    });

    for (let entry in arms_with_blocks) {
        let (let arm, let body_block, let skips_panics) = entry;
        // Try remaining arms in this handler. An unmatched value rethrows
        // through this clause's own exception region to an outer catch.
        let bb_arm_next = ctx.builder.create_block();
        lower_pattern_test(
            ctx,
            error_local,
            arm.pattern,
            body_block,
            bb_arm_next,
            wildcard_skips_panics = skips_panics,
        );
        ctx.builder.set_current_block(bb_arm_next);
    }

    // Rethrow if nothing matched.
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.rethrow(operand_copy_local(error_local), context_local);
    }

    // Lower each arm body.
    for (let entry in arms_with_blocks) {
        let (let arm, let body_block, _) = entry;
        ctx.builder.set_current_block(body_block);
        let error_copy = install_clause_bindings(ctx, error_local, context_local, clause_bindings);
        bind_pattern(
            ctx,
            error_local,
            arm.pattern,
            root.hir.DefinitionSitePatternBinding { value: arm.pattern },
        );
        let rethrow_mark = ctx.catch_rethrow_locals.length();
        ctx.catch_rethrow_locals.push((error_local, context_local));
        if (error_copy != null) {
            ctx.catch_rethrow_locals.push((error_copy, context_local));
        }
        lower_expr(ctx, arm.body, place_clone(dest));
        while (ctx.catch_rethrow_locals.length() > rethrow_mark) {
            ctx.catch_rethrow_locals.pop();
        }
        if (!ctx.builder.is_current_terminated()) {
            ctx.builder.goto(bb_join);
        }
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_catch_wildcard_entry @ d9be6853b
// Enter a catch arm that may not receive panics: when `skips_panics`, a
// caught panic branches to `panic_target` and the current block becomes the
// arm's (non-panic) entry. A wildcard arm of a clause that does not trap
// panics is the only arm needing this test (every other arm's pattern test
// already decides panics by type), so one coarse tag test is all an error
// pays for, and the same dispatch serves `catch`, `catch_all`, and
// `catch_all_panics`.
function emit_catch_wildcard_entry(
    ctx: LoweringContext,
    error_local: int,
    skips_panics: bool,
    panic_target: int,
) -> void throws never {
    if (!skips_panics) {
        return;
    }
    let bb_not_panic = ctx.builder.create_block();
    emit_is_type_tag_branch(ctx, error_local, root.types.TYPETAG_PANIC, panic_target, bb_not_panic);
    ctx.builder.set_current_block(bb_not_panic);
}

// port: baml_compiler2_mir/src/lower.rs::is_union_of_list_types @ d9be6853b
// Whether `ty` is a list type or a union of list types: a list pattern's
// claim that one membership test decides.
function is_union_of_list_types(ty: root.types.Ty) -> bool throws never {
    match (ty) {
        root.types.TyList => true,
        let u: root.types.TyUnion => {
            u.members.every((member) -> {
                member is root.types.TyList
            })
        },
        _ => false,
    }
}
