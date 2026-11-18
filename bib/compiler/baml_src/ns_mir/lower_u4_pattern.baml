// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// MIR unit 4, pattern tests: the type, tag, tuple-shape and value-equality
// branches, class / tuple / array projections, and `lower_pattern_test`.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - `lower_pattern_test_with_catch_policy` (387 lines in Rust) is
//   `lower_pattern_test` with a named default `wildcard_skips_panics =
//   false` (Rust's `lower_pattern_test` forwards to it). It keeps its
//   prologue (the atomic snapshot, the bind recursion, the array ascription
//   test) and dispatches its large arms to `lower_pattern_test_<arm>`
//   (`type`, `class`, `tuple`, `array`), side effects in Rust's order.
// - `baml_type::typetag::X` is `root.types.TYPETAG_X`;
//   `baml_type_runtime::contains_typevar` is `contains_ty_where` with a
//   `TyTypeVar` test. `usize` / `u32` conversions that Rust `expect`s
//   cannot fail on an `int` and are dropped; so `const_usize_int_local`
//   (`const_int_local` behind that conversion) is not ported: its callers
//   call `const_int_local`.
// - `tested_pattern_values` (keyed by the `(scope, pattern)` tuple) is a
//   nested map; an insert creates the inner map on first use.
// - The `unreachable!` in `emit_is_type_branch` names no type: `RuntimeTy`'s
//   `Display` is not ported.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_is_type_branch @ d9be6853b
// Emit an `IsType` check that handles union types by expanding them into a
// chain: try each member, branch to `success` if any matches.
//
// Testing a value against an *interface* type means "is its concrete
// runtime type an implementor": a single `IsType` on the interface
// existential itself, which the VM resolves through the canonical
// membership check against the impl registry. The bytecode never
// enumerates implementors. Interfaces reach here already tagged
// `RuntimeTy::Interface`, so no name-based re-tag is needed.
function emit_is_type_branch(
    ctx: LoweringContext,
    scrutinee: int,
    ty: root.types.RuntimeTy,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    if let union: root.types.RuntimeTyUnion = ty {
        // For union A | B | C: check A -> success, else check B -> success,
        // else check C -> success, else failure.
        let members = union.members;
        for (let i = 0; i < members.length(); i += 1) {
            if (i + 1 == members.length()) {
                // Last member: branch directly to success/failure.
                emit_is_type_branch(ctx, scrutinee, members[i], success, failure);
            } else {
                // Not last: if this member matches, jump to success;
                // otherwise try the next member.
                let next_check = ctx.builder.create_block();
                emit_is_type_branch(ctx, scrutinee, members[i], success, next_check);
                ctx.builder.set_current_block(next_check);
            }
        }
        return;
    }
    // If this is a parametric arm whose type arguments the emitter would
    // otherwise check structurally, but the enclosing match's scrutinee
    // statically proves a coarse `LIST`/`MAP`/`FUTURE` tag suffices, emit the
    // tag test directly. Guarded on the tested local holding the scrutinee
    // (itself, or a narrowing arm's snapshot of it) so an `is` / nested test
    // against a different value stays arg-precise.
    let scrutinee_ty = ctx.match_scrutinee?.ty_held_by(scrutinee);
    if (scrutinee_ty != null && parametric_arm_tag_sufficient(ty, scrutinee_ty)) {
        let tag = match (ty) {
            root.types.RuntimeTyList => root.types.TYPETAG_LIST,
            root.types.RuntimeTyMap => root.types.TYPETAG_MAP,
            root.types.RuntimeTyFuture => root.types.TYPETAG_FUTURE,
            // `parametric_arm_tag_sufficient` returns false for every
            // non-parametric arm.
            _ => baml.sys.panic("tag-sufficient non-parametric arm"),
        };
        emit_is_type_tag_branch(ctx, scrutinee, tag, success, failure);
        return;
    }
    // Convert RuntimeTy -> template so generic class checks (a
    // `RuntimeTy::Class` with concrete args) become an arg-precise `Class`
    // test. For non-generic types the template is a realized leaf: the
    // emitter's tag / class-identity fast path. A residual symbolic position
    // becomes a guard hole the pattern test refuses.
    let guard = ty_to_pattern_template_from_resolved_ty(ty);
    emit_pattern_template_test(ctx, scrutinee, guard, success, failure);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_is_type_tag_branch @ d9be6853b
// Emit an `IsTypeTag` coarse-tag test + branch (the container arm of a
// match whose scrutinee proves the tag sufficient).
function emit_is_type_tag_branch(
    ctx: LoweringContext,
    scrutinee: int,
    tag: int,
    success: int,
    failure: int,
) -> void throws never {
    let test_ = RvalueIsTypeTag { operand: operand_copy_local(scrutinee), tag: tag };
    let test_local = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(PlaceLocal { value: test_local }, test_);
    ctx.builder.branch(operand_copy_local(test_local), success, failure);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_tuple_shape_branch @ d9be6853b
function emit_tuple_shape_branch(
    ctx: LoweringContext,
    scrutinee: int,
    arity: int,
    success: int,
    failure: int,
) -> void throws never {
    let is_tuple = ctx.builder.create_block();
    emit_is_type_tag_branch(ctx, scrutinee, root.types.TYPETAG_TUPLE, is_tuple, failure);
    ctx.builder.set_current_block(is_tuple);
    lower_array_pattern_length_test(ctx, scrutinee, false, arity, success, failure);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_pattern_template_test @ d9be6853b
// Emit a `match`/`is` pattern test from a pattern-template build.
//
// A pattern denotes exactly one type per frame; the builders report an
// unresolvable position (an associated projection, a type variable without
// a frame slot) as null at construction, and such a pattern has no complete
// test: it is fail-closed, branching straight to `failure`.
//
// FIXME(typevar-templates): the sound fix for the fail-closed cases is to
// resolve them (projection templates over frame refs, the way `Self` gained
// its frame slot) or reject them at TIR, never to match-any.
function emit_pattern_template_test(
    ctx: LoweringContext,
    scrutinee: int,
    template: root.types.TyTemplate?,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    if (template != null) {
        emit_is_type_template_branch(ctx, scrutinee, template, success, failure);
    } else {
        ctx.builder.goto(failure);
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_is_type_template_branch @ d9be6853b
// Emit an `IsType` test + branch for an already-built `TyTemplate`.
//
// Used directly (instead of `emit_is_type_branch`) when the pattern type
// still contains the enclosing function's `TypeVar`s: the caller builds the
// template via `ty_to_template` so those lower to `TypeArgRef` leaves
// resolved against `frame.type_args` at runtime.
function emit_is_type_template_branch(
    ctx: LoweringContext,
    scrutinee: int,
    ty_template: root.types.TyTemplate,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    let test_ = type_test(ctx, ty_template);
    if (ctx.atomic_pattern_test) {
        ctx.builder.narrow_bind(operand_copy_local(scrutinee), test_, scrutinee, success, failure);
    } else {
        let is_type = RvalueIsType { operand: operand_copy_local(scrutinee), test_: test_ };
        let test_local = ctx.builder.declare_local(root.types.TyBool {});
        ctx.builder.assign(PlaceLocal { value: test_local }, is_type);
        ctx.builder.branch(operand_copy_local(test_local), success, failure);
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_ty_needs_interface_shape_test @ d9be6853b
// Whether `ty` is (or contains, inside a union/optional) an interface view
// whose runtime test must respect type arguments or associated bindings.
// Used to opt only these patterns into the TIR-typed test path, leaving
// non-interface patterns on the unchanged erased fast path.
function tir_ty_needs_interface_shape_test(ty: root.types.Ty) -> bool throws never {
    match (ty) {
        let i: root.types.TyInterface => i.args.length() > 0 || i.associated_types.length() > 0,
        let u: root.types.TyUnion => u.members.some(tir_ty_needs_interface_shape_test),
        _ => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_is_tir_type_branch @ d9be6853b
function emit_is_tir_type_branch(
    ctx: LoweringContext,
    scrutinee: int,
    ty: root.types.Ty,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    match (ty) {
        let u: root.types.TyUnion => {
            let members = u.members;
            for (let i = 0; i < members.length(); i += 1) {
                if (i + 1 == members.length()) {
                    emit_is_tir_type_branch(ctx, scrutinee, members[i], success, failure);
                } else {
                    let next_check = ctx.builder.create_block();
                    emit_is_tir_type_branch(ctx, scrutinee, members[i], success, next_check);
                    ctx.builder.set_current_block(next_check);
                }
            }
        },
        // One arg-precise instantiation test. Building it TIR-side lets the
        // enclosing function's type variables (including an interface-owned
        // body's `Self`) lower to `TypeArgRef` frame slots, so the VM
        // compares the value's stored class type args against this frame's
        // realizations invariantly. Residual symbolic args make the build
        // null, failing the test closed. This test is complete on its own:
        // do not add a walk over the class's declared field types.
        let c: root.types.TyClass if c.args.length() > 0 => {
            let generic_params = enclosing_generic_params(ctx);
            let header = tir2_to_pattern_template(ty, runtime(ctx), generic_params);
            emit_pattern_template_test(ctx, scrutinee, header, success, failure);
        },
        // An interface pattern (`Slot<int>`, `Source<Item = int>`, or a bare
        // `Named`) is a single membership test against the interface
        // existential itself, resolved by the VM against the impl registry
        // at the requested instantiation. The enclosing function's type
        // variables lower to `TypeArgRef` frame slots, resolved at runtime.
        root.types.TyInterface => {
            let generic_params = enclosing_generic_params(ctx);
            let guard = tir2_to_pattern_template(ty, runtime(ctx), generic_params);
            emit_pattern_template_test(ctx, scrutinee, guard, success, failure);
        },
        // Singleton-valued types pin a specific runtime value, so emit
        // equality checks rather than type-tag tests: `is_type` on a literal
        // type checks the value's *type* (string) rather than its content.
        let l: root.types.TyLiteral => {
            let constant = lower_literal(l.value);
            emit_value_eq_branch(ctx, scrutinee, OperandConstant { value: constant }, success, failure);
        },
        root.types.TyNull => {
            emit_value_eq_branch(ctx, scrutinee, OperandConstant { value: ConstantNull {} }, success, failure);
        },
        _ => {
            let resolved = runtime(ctx).convert(ty);
            emit_is_type_branch(ctx, scrutinee, resolved, success, failure);
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_value_eq_branch @ d9be6853b
// Branch on `scrutinee == rhs` (value equality). Used for singleton-typed
// patterns where the type pins a specific value.
function emit_value_eq_branch(
    ctx: LoweringContext,
    scrutinee: int,
    rhs: Operand,
    success: int,
    failure: int,
) -> void throws never {
    let test_ = RvalueBinaryOp { op: BinOp.Eq, left: operand_copy_local(scrutinee), right: rhs };
    let test_local = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(PlaceLocal { value: test_local }, test_);
    ctx.builder.branch(operand_copy_local(test_local), success, failure);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_tag_for_ty @ d9be6853b
// The switch key for a type: a primitive kind's fixed tag (INT=0,
// STRING=1, etc.), a class by its declaration, or null for types that
// have no tag of their own (unions, generics, etc.).
function type_tag_for_ty(
    ctx: LoweringContext,
    ty: root.types.RuntimeTy,
) -> SwitchKey? throws never {
    let tag: int? = match (ty) {
        root.types.TyInt => root.types.TYPETAG_INT,
        root.types.TyBigint => root.types.TYPETAG_BIGINT,
        root.types.TyString => root.types.TYPETAG_STRING,
        root.types.TyBool => root.types.TYPETAG_BOOL,
        root.types.TyNull => root.types.TYPETAG_NULL,
        root.types.TyFloat => root.types.TYPETAG_FLOAT,
        root.types.TyUint8Array => root.types.TYPETAG_UINT8ARRAY,
        // The single shared ENUM tag conflates *all* enum types (and all
        // variants of one enum). That's safe on the switch path only because
        // `switch_member_tag_sufficient` bails an enum-type arm to the precise
        // chain whenever a second enum type shares this tag. A
        // single-enum-type switch keeps the fast tag.
        root.types.TyEnum | root.types.TyEnumVariant => root.types.TYPETAG_ENUM,
        root.types.RuntimeTyList => root.types.TYPETAG_LIST,
        root.types.RuntimeTyMap => root.types.TYPETAG_MAP,
        root.types.RuntimeTyFunction => root.types.TYPETAG_FUNCTION,
        root.types.RuntimeTyFuture => root.types.TYPETAG_FUTURE,
        root.types.TyType => root.types.TYPETAG_TYPE,
        // The class arm names its declaration; the tag is whoever lays that
        // declaration into an image assigns.
        let c: root.types.RuntimeTyClass => {
            return match (root.hir_ty.class_ref_of(ctx.db, c.name)) {
                let source: root.hir.DeclRefSource<int> => SwitchKeyClass { value: source.value },
                root.hir.DeclRefExternal<int> => {
                    baml.sys.panic(
                        "type_tag_for_ty: a root served from its interface is not ported",
                    )
                },
                null => null,
            };
        },
        _ => null,
    };
    if (tag != null) {
        SwitchKeyInt { value: tag }
    } else {
        null
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_contains_structural @ d9be6853b
function pattern_contains_structural(ctx: LoweringContext, pat_id: int) -> bool throws never {
    match (ctx.body.patterns[pat_id]) {
        root.ast.PatternClass | root.ast.PatternArray | root.ast.PatternTuple => true,
        let p: root.ast.PatternOr => {
            p.value.some((part) -> {
                pattern_contains_structural(ctx, part)
            })
        },
        let p: root.ast.PatternBind => {
            if let sub: int = p.subpat {
                pattern_contains_structural(ctx, sub)
            } else {
                false
            }
        },
        root.ast.PatternWildcard | root.ast.PatternType => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_pattern_fields @ d9be6853b
function class_pattern_fields(
    ctx: LoweringContext,
    pat_id: int,
) -> root.ast.FieldPat[] throws never {
    match (ctx.body.patterns[pat_id]) {
        let p: root.ast.PatternClass => p.fields.concat([]),
        _ => [],
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_pattern_type_name @ d9be6853b
function class_pattern_type_name(
    ctx: LoweringContext,
    pat_id: int,
) -> root.types.DeclName? throws never {
    let tir_ty = tir_pat_type(ctx, pat_id)
        ?? return null;
    match (runtime(ctx).convert(tir_ty)) {
        let c: root.types.RuntimeTyClass => c.name,
        _ => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_pattern_field_ty @ d9be6853b
// The type of `field` in the class a pattern matches, with the pattern's
// class arguments substituted: wherever the class is declared.
function class_pattern_field_ty(
    ctx: LoweringContext,
    pat_id: int,
    field: string,
) -> root.types.RuntimeTy? throws never {
    let tir_ty = tir_pat_type(ctx, pat_id)
        ?? return null;
    let class_ty = match (tir_ty) {
        let c: root.types.TyClass => c,
        _ => {
            return null;
        },
    };
    let class_ = root.hir_ty.class_ref_of(ctx.db, class_ty.name)
        ?? return null;
    let declared = root.hir_ty.class_field_ty(ctx.db, class_, field)
        ?? return null;
    let bindings = root.types.bind_type_vars(root.hir_ty.class_generic_params(ctx.db, class_), class_ty.args);
    runtime(ctx).convert(root.types.substitute_ty(declared, bindings))
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_class_pattern_field @ d9be6853b
// The local holding `field` of the value a class pattern matched. TIR
// admitted every field of the pattern against its class or interface, so a
// field that cannot be projected is a compiler bug: never a pattern that
// silently fails, or a binding silently left unset.
function project_class_pattern_field(
    ctx: LoweringContext,
    scrutinee: int,
    class_pat_id: int,
    field_pat_id: int,
    field: string,
) -> int throws MirInternalError {
    // An interface head (`Animal { name } => ...`) has no positional field
    // layout. Branch on the raw TIR type so interface patterns project
    // through field-view dispatch instead of class slots.
    if (tir_pat_type(ctx, class_pat_id) is root.types.TyInterface) {
        return project_interface_pattern_field(ctx, scrutinee, class_pat_id, field_pat_id, field);
    }
    let class_tn = class_pattern_type_name(ctx, class_pat_id)
        ?? throw internal_error_here(ctx, "a class pattern's type is neither a class nor an interface");
    let class_ = class_ref_of(ctx, class_tn);
    let field_idx = root.hir_ty.class_field_index(ctx.db, root.hir.DeclRefSource { value: class_ }, field)
        ?? throw internal_error_here(
            ctx,
            `TIR admitted the pattern field \`${field}\`, which the class \`${class_tn.name}\` does not declare`,
        );
    let field_ty = class_pattern_field_ty(ctx, class_pat_id, field) ?? pat_ty(ctx, field_pat_id);
    let field_local = ctx.builder.declare_local(field_ty);
    ctx.builder.assign(
        PlaceLocal { value: field_local },
        RvalueUse {
            value: OperandCopy {
                value: PlaceField { base: PlaceLocal { value: scrutinee }, field: field_idx },
            },
        },
    );
    field_local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_interface_pattern_field @ d9be6853b
// Project a field bound by an *interface* destructure pattern (`Animal {
// name } => …`). The scrutinee's concrete runtime class is not known
// statically, so we can't index a fixed field slot. Instead we reuse the
// interface field-view dispatch (`try_lower_interface_field_access`), the
// same code that lowers `iface_value.name`, to read the linked field off
// whichever implementor the value actually is.
function project_interface_pattern_field(
    ctx: LoweringContext,
    scrutinee: int,
    class_pat_id: int,
    field_pat_id: int,
    field: string,
) -> int throws MirInternalError {
    let unresolved = `TIR admitted the interface pattern field \`${field}\`, which no field view serves`;
    let tir_ty = tir_pat_type(ctx, class_pat_id) ?? throw internal_error_here(ctx, unresolved);
    let view = interface_dispatch_target_for_member(ctx, tir_ty, field)
        ?? throw internal_error_here(ctx, unresolved);
    let (let iface_tn, let iface_args, let iface_assoc) = view;
    let field_local = ctx.builder.declare_local(pat_ty(ctx, field_pat_id));
    if (
        try_lower_interface_field_access(
            ctx,
            scrutinee,
            iface_tn,
            iface_args,
            iface_assoc,
            field,
            PlaceLocal { value: field_local },
        )
    ) {
        field_local
    } else {
        throw internal_error_here(ctx, unresolved)
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::const_int_local @ d9be6853b
function const_int_local(ctx: LoweringContext, value: int) -> int throws never {
    let local = ctx.builder.declare_local(root.types.TyInt {});
    ctx.builder.assign(
        PlaceLocal { value: local },
        RvalueUse { value: OperandConstant { value: ConstantInt { value: value } } },
    );
    local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::array_len_local @ d9be6853b
function array_len_local(ctx: LoweringContext, scrutinee: int) -> int throws never {
    let len_local = ctx.builder.declare_local(root.types.TyInt {});
    ctx.builder.assign(
        PlaceLocal { value: len_local },
        RvalueLen { value: PlaceLocal { value: scrutinee } },
    );
    len_local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_array_pattern_length_test @ d9be6853b
function lower_array_pattern_length_test(
    ctx: LoweringContext,
    scrutinee: int,
    has_rest: bool,
    fixed_len: int,
    success: int,
    failure: int,
) -> void throws never {
    let len_local = array_len_local(ctx, scrutinee);
    let expected = const_int_local(ctx, fixed_len);
    let test_local = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(
        PlaceLocal { value: test_local },
        RvalueBinaryOp {
            op: if (has_rest) {
                BinOp.Ge
            } else {
                BinOp.Eq
            },
            left: operand_copy_local(len_local),
            right: operand_copy_local(expected),
        },
    );
    ctx.builder.branch(operand_copy_local(test_local), success, failure);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_array_pattern_element_from_start @ d9be6853b
function project_array_pattern_element_from_start(
    ctx: LoweringContext,
    scrutinee: int,
    elem_pat: int,
    index: int,
) -> int throws MirInternalError {
    let index_local = const_int_local(ctx, index);
    project_array_pattern_element(ctx, scrutinee, elem_pat, index_local)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_array_pattern_element_from_end @ d9be6853b
function project_array_pattern_element_from_end(
    ctx: LoweringContext,
    scrutinee: int,
    elem_pat: int,
    index_from_end: int,
) -> int throws MirInternalError {
    let len_local = array_len_local(ctx, scrutinee);
    let offset = const_int_local(ctx, index_from_end);
    let index_local = ctx.builder.declare_local(root.types.TyInt {});
    ctx.builder.assign(
        PlaceLocal { value: index_local },
        RvalueBinaryOp {
            op: BinOp.Sub,
            left: operand_copy_local(len_local),
            right: operand_copy_local(offset),
        },
    );
    project_array_pattern_element(ctx, scrutinee, elem_pat, index_local)
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_array_pattern_element @ d9be6853b
function project_array_pattern_element(
    ctx: LoweringContext,
    scrutinee: int,
    elem_pat: int,
    index_local: int,
) -> int throws MirInternalError {
    let elem_ty = pat_ty(ctx, elem_pat);
    let elem_local = ctx.builder.declare_local(elem_ty);
    ctx.builder.assign(
        PlaceLocal { value: elem_local },
        RvalueUse {
            value: OperandCopy {
                value: PlaceIndex {
                    base: PlaceLocal { value: scrutinee },
                    index: index_local,
                    kind: IndexKind.Array,
                },
            },
        },
    );
    elem_local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_array_pattern_rest @ d9be6853b
function project_array_pattern_rest(
    ctx: LoweringContext,
    scrutinee: int,
    rest_pat: int,
    prefix_len: int,
    suffix_len: int,
) -> int throws MirInternalError {
    let rest_ty = pat_ty(ctx, rest_pat);
    let rest_local = ctx.builder.declare_local(rest_ty);
    let start = const_int_local(ctx, prefix_len);
    let end = if (suffix_len == 0) {
        array_len_local(ctx, scrutinee)
    } else {
        let len_local = array_len_local(ctx, scrutinee);
        let suffix = const_int_local(ctx, suffix_len);
        let end = ctx.builder.declare_local(root.types.TyInt {});
        ctx.builder.assign(
            PlaceLocal { value: end },
            RvalueBinaryOp {
                op: BinOp.Sub,
                left: operand_copy_local(len_local),
                right: operand_copy_local(suffix),
            },
        );
        end
    };
    let target = ctx.builder.create_block();
    let slice = lang_class_method(ctx, root.base.LangPackage.Baml, "Array", "slice");
    ctx.builder.call_with_type_args(
        OperandConstant { value: ConstantFunction { value: slice } },
        [operand_copy_local(scrutinee), operand_copy_local(start), operand_copy_local(end)],
        0,
        PlaceLocal { value: rest_local },
        target,
    );
    ctx.builder.set_current_block(target);
    rest_local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_pattern_test_with_catch_policy @ d9be6853b
// Also Rust's `lower_pattern_test`, which is this with
// `wildcard_skips_panics = false` (a one-line forwarder in Rust): one
// function under the name its callers use, with a named default.
//
// Catch wildcard filtering follows alternatives and binding wrappers of the
// caught value, but not patterns on its projected fields/elements. In
// particular, `PanicType | _` must still test its named alternative when
// the wildcard rejects a panic.
function lower_pattern_test(
    ctx: LoweringContext,
    scrutinee_in: int,
    pat_id: int,
    success: int,
    failure: int,
    wildcard_skips_panics: bool = false,
) -> void throws MirInternalError {
    let scrutinee = scrutinee_in;
    if (ctx.atomic_pattern_test) {
        let snapshot = ctx.builder.declare_local(ctx.builder.local_ty(scrutinee_in));
        ctx.builder.assign(
            PlaceLocal { value: snapshot },
            RvalueUse { value: operand_copy_local(scrutinee_in) },
        );
        if let match_scrutinee: MatchScrutinee = ctx.match_scrutinee {
            match_scrutinee.record_copy(scrutinee_in, snapshot);
        }
        let key = pat_metadata_key(ctx, pat_id);
        let tested = ctx.tested_pattern_values.get(key.0);
        if (tested == null) {
            tested = {};
            ctx.tested_pattern_values[key.0] = tested;
        }
        tested[key.1] = snapshot;
        scrutinee = snapshot;
    }
    let pat = ctx.body.patterns[pat_id];

    // Bind sub-pattern: `let x: <pattern>` defers to the sub-pattern's
    // runtime test (recursively). The bind itself doesn't emit a runtime
    // check; the sub-pattern does.
    if let bind: root.ast.PatternBind = pat {
        if let sp: int = bind.subpat {
            let saved = ctx.atomic_pattern_test;
            ctx.atomic_pattern_test = true;
            lower_pattern_test(ctx, scrutinee, sp, success, failure, wildcard_skips_panics = wildcard_skips_panics);
            ctx.atomic_pattern_test = saved;
            return;
        }
    }
    // Array `: T` ascription emits an `is_type` test before the structural
    // shape test below.
    if let array: root.ast.PatternArray = pat {
        if let ty_expr: root.ast.TypeExpr = array.ascription {
            let after_ascription = ctx.builder.create_block();
            let tir_ty = tir_pat_type(ctx, pat_id);
            if (tir_ty != null && !(tir_ty is root.types.TyNever)) {
                emit_is_tir_type_branch(ctx, scrutinee, tir_ty, after_ascription, failure);
            } else {
                let annotation_ty = resolve_type_annotation(ctx, ty_expr);
                emit_is_type_branch(ctx, scrutinee, annotation_ty, after_ascription, failure);
            }
            ctx.builder.set_current_block(after_ascription);
            // Fall through to the array shape test below.
        }
    }

    match (pat) {
        root.ast.PatternWildcard => {
            emit_catch_wildcard_entry(ctx, scrutinee, wildcard_skips_panics, failure);
            ctx.builder.goto(success);
        },
        // A bare `let e` (no annotation: annotated binds carry the
        // annotation as a subpattern and recursed above) is IRREFUTABLE: arm
        // dispatch is sequential, so the bind takes whatever reaches it; its
        // `pat_types` entry is exhaustiveness bookkeeping, not a runtime
        // dispatch condition. Emitting a type test here is at best a
        // tautology and at worst a miscompile (a rigid generic is carried by
        // name, which a test cannot resolve against the frame). Panic
        // fall-through for catch arms is handled separately by
        // `emit_catch_wildcard_entry`.
        root.ast.PatternBind => {
            emit_catch_wildcard_entry(ctx, scrutinee, wildcard_skips_panics, failure);
            ctx.builder.goto(success);
        },
        let p: root.ast.PatternType => {
            lower_pattern_test_type(ctx, scrutinee, pat_id, p.value, success, failure)
        },
        let p: root.ast.PatternOr => {
            let sub_pats = p.value;
            if (sub_pats.length() == 0) {
                ctx.builder.goto(failure);
                return;
            }
            let n = sub_pats.length();
            for (let i = 0; i < n; i += 1) {
                let next = if (i + 1 < n) {
                    ctx.builder.create_block()
                } else {
                    failure
                };
                lower_pattern_test(
                    ctx,
                    scrutinee,
                    sub_pats[i],
                    success,
                    next,
                    wildcard_skips_panics = wildcard_skips_panics,
                );
                if (i + 1 < n) {
                    ctx.builder.set_current_block(next);
                }
            }
        },
        root.ast.PatternClass => {
            lower_pattern_test_class(ctx, scrutinee, pat_id, success, failure)
        },
        let p: root.ast.PatternTuple => {
            lower_pattern_test_tuple(ctx, scrutinee, p.value, success, failure)
        },
        let p: root.ast.PatternArray => {
            lower_pattern_test_array(ctx, scrutinee, pat_id, p, success, failure)
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_pattern_test_with_catch_policy @ d9be6853b
// The `Pattern::Type` arm. The flat pattern enum collapses literal, null,
// enum-variant and type patterns into `Pattern::Type(TypeExpr)`, so this
// dispatches on the inner `TypeExpr`.
function lower_pattern_test_type(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    ty_expr: root.ast.TypeExpr,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    match (ty_expr.kind) {
        // A literal pattern is a membership test against a singleton type,
        // not an arithmetic equality: it asks whether the value inhabits
        // `{1}`, and `1`, `1.0` and `1n` are disjoint types. Routing through
        // the same `IsType` relation every other pattern kind uses keeps one
        // definition of "matches".
        let k: root.ast.TypeExprKindLiteral => {
            emit_is_type_branch(
                ctx,
                scrutinee,
                root.types.TyLiteral { value: k.value, freshness: root.types.Freshness.Regular },
                success,
                failure,
            );
            return;
        },
        root.ast.TypeExprKindNull => {
            let test_ = RvalueBinaryOp {
                op: BinOp.Eq,
                left: operand_copy_local(scrutinee),
                right: OperandConstant { value: ConstantNull {} },
            };
            let test_local = ctx.builder.declare_local(root.types.TyBool {});
            ctx.builder.assign(PlaceLocal { value: test_local }, test_);
            ctx.builder.branch(operand_copy_local(test_local), success, failure);
            return;
        },
        root.ast.TypeExprKindPath => {
            if let variant_ty: root.types.TyEnumVariant = tir_pat_type(ctx, pat_id) {
                let enum_ref = enum_ref_of(ctx, variant_ty.name);
                let index = enum_variant_index(ctx, enum_ref, variant_ty.variant);
                let test_ = RvalueBinaryOp {
                    op: BinOp.Eq,
                    left: operand_copy_local(scrutinee),
                    right: OperandConstant {
                        value: ConstantEnumVariant { enum_ref: enum_ref, index: index },
                    },
                };
                let test_local = ctx.builder.declare_local(root.types.TyBool {});
                ctx.builder.assign(PlaceLocal { value: test_local }, test_);
                ctx.builder.branch(operand_copy_local(test_local), success, failure);
                return;
            }
        },
        _ => {},
    }
    // The annotated-bind recursion (`let e: T => …` recurses into its Type
    // subpattern) has no `pat_types` entry for the subpattern, so fall back
    // to lowering the annotation itself with the enclosing generic params in
    // scope.
    let pat_tir_ty = tir_pat_type(ctx, pat_id) ?? lower_type_annotation_tir(ctx, ty_expr);
    // A generic-interface pattern (`Slot<int>`) needs the TIR-typed test,
    // which preserves the type argument and tests only the implementors of
    // *that* instantiation.
    if (tir_ty_needs_interface_shape_test(pat_tir_ty)) {
        emit_is_tir_type_branch(ctx, scrutinee, pat_tir_ty, success, failure);
        return;
    }
    // A pattern type still carrying the enclosing function's TypeVars must
    // NOT go through `convert_tir_ty_for_runtime`: that carries each TypeVar
    // by name, with no frame slot for the test to resolve it against. Build
    // a template instead so each typevar resolves against `frame.type_args`
    // at runtime and the value is compared invariantly against the
    // *realized* binding. `tir2_to_pattern_template` reports an unresolvable
    // position as null, which `emit_pattern_template_test` fails closed.
    // `Self` is an ordinary frame type variable here (frame slot 0 of an
    // interface-owned body); a residual slotless `Self` fails closed.
    if (
        root.types.contains_ty_where(pat_tir_ty, (t) -> {
            t is root.types.TyTypeVar
        })
    ) {
        let generic_params = enclosing_generic_params(ctx);
        let guard = tir2_to_pattern_template(pat_tir_ty, runtime(ctx), generic_params);
        emit_pattern_template_test(ctx, scrutinee, guard, success, failure);
        return;
    }
    // Other patterns keep the erased fast path (unchanged codegen).
    let annotation_ty = runtime(ctx).convert(pat_tir_ty);
    emit_is_type_branch(ctx, scrutinee, annotation_ty, success, failure);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_pattern_test_with_catch_policy @ d9be6853b
// The `Pattern::Class` arm: the type test, then each field's test.
function lower_pattern_test_class(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    let class_success = if (class_pattern_fields(ctx, pat_id).length() == 0) {
        success
    } else {
        ctx.builder.create_block()
    };

    let tir_ty = tir_pat_type(ctx, pat_id);
    if (tir_ty != null) {
        emit_is_tir_type_branch(ctx, scrutinee, tir_ty, class_success, failure);
    } else if (class_success == success) {
        ctx.builder.goto(success);
    } else {
        ctx.builder.goto(class_success);
    }

    if (class_success != success) {
        ctx.builder.set_current_block(class_success);
        let fields = class_pattern_fields(ctx, pat_id);
        for (let idx = 0; idx < fields.length(); idx += 1) {
            let field = fields[idx];
            let next = if (idx + 1 == fields.length()) {
                success
            } else {
                ctx.builder.create_block()
            };
            let field_local = project_class_pattern_field(ctx, scrutinee, pat_id, field.pat, field.field);
            lower_pattern_test(ctx, field_local, field.pat, next, failure);
            if (idx + 1 < fields.length()) {
                ctx.builder.set_current_block(next);
            }
        }
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_pattern_test_with_catch_policy @ d9be6853b
// The `Pattern::Tuple` arm: the shape test, then each refutable element's
// test.
function lower_pattern_test_tuple(
    ctx: LoweringContext,
    scrutinee: int,
    elements: int[],
    success: int,
    failure: int,
) -> void throws MirInternalError {
    let arity = elements.length();
    let statically_tuple = match (ctx.builder.local_ty(scrutinee)) {
        let t: root.types.RuntimeTyTuple => t.items.length() == arity,
        _ => false,
    };
    let refutable: (int, int)[] = [];
    for (let idx = 0; idx < arity; idx += 1) {
        if (!is_irrefutable_catch_all(ctx, elements[idx])) {
            refutable.push((idx, elements[idx]));
        }
    }
    let shape_success = if (refutable.length() == 0) {
        success
    } else {
        ctx.builder.create_block()
    };
    if (statically_tuple) {
        ctx.builder.goto(shape_success);
    } else {
        emit_tuple_shape_branch(ctx, scrutinee, arity, shape_success, failure);
    }
    if (refutable.length() > 0) {
        ctx.builder.set_current_block(shape_success);
        let last = refutable.length() - 1;
        for (let n = 0; n < refutable.length(); n += 1) {
            let (let idx, let sub) = refutable[n];
            let next = if (n == last) {
                success
            } else {
                ctx.builder.create_block()
            };
            let elem_local = project_tuple_pattern_element(ctx, scrutinee, sub, idx, arity);
            lower_pattern_test(ctx, elem_local, sub, next, failure);
            if (n < last) {
                ctx.builder.set_current_block(next);
            }
        }
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_pattern_test_with_catch_policy @ d9be6853b
// The `Pattern::Array` arm: the list test, the length test, then each
// element's and the rest's test.
function lower_pattern_test_array(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    p: root.ast.PatternArray,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    let prefix = p.prefix;
    let suffix = p.suffix;
    let array_success = ctx.builder.create_block();

    // The checker records the list members the pattern claims. Where each
    // is a list type, the elements are typed by them, so the test is
    // membership; where one may hold lists of any element (`unknown`, a type
    // parameter, an interface existential), the pattern accepts any list and
    // the test is the list head alone - never membership in `unknown[]`,
    // which no `int[]` has.
    let claimed = tir_pat_type(ctx, pat_id)
        ?? throw internal_error_here(ctx, "the checker recorded no type for a list pattern");
    if (is_union_of_list_types(claimed)) {
        emit_is_tir_type_branch(ctx, scrutinee, claimed, array_success, failure);
    } else {
        emit_is_type_tag_branch(ctx, scrutinee, root.types.TYPETAG_LIST, array_success, failure);
    }

    ctx.builder.set_current_block(array_success);
    // A rest sub-pattern needs a test-phase slice projection only when it is
    // refutable (e.g. a `: T` ascription link). Plain bindings and `.._`
    // match unconditionally; bindings get their slice in the arm-binding
    // phase instead, so testing here would just copy the middle twice.
    let rest_pat_id = p.rest?.pat;
    let rest_test_pat = if (rest_pat_id != null && !is_irrefutable_catch_all(ctx, rest_pat_id)) {
        rest_pat_id
    } else {
        null
    };
    let has_rest_test = rest_test_pat != null;
    let element_count = prefix.length() + suffix.length();
    let has_nested_tests = element_count > 0 || has_rest_test;
    let after_len = if (has_nested_tests) {
        ctx.builder.create_block()
    } else {
        success
    };
    lower_array_pattern_length_test(ctx, scrutinee, p.rest != null, prefix.length() + suffix.length(), after_len, failure);
    if (!has_nested_tests) {
        return;
    }

    ctx.builder.set_current_block(after_len);
    let rest_entry = if (has_rest_test) {
        ctx.builder.create_block()
    } else {
        null
    };
    let element_success = rest_entry ?? success;
    if (element_count == 0) {
        ctx.builder.goto(element_success);
    }

    for (let idx = 0; idx < prefix.length(); idx += 1) {
        let elem_pat = prefix[idx];
        let next = if (idx + 1 == element_count) {
            element_success
        } else {
            ctx.builder.create_block()
        };
        let elem_local = project_array_pattern_element_from_start(ctx, scrutinee, elem_pat, idx);
        lower_pattern_test(ctx, elem_local, elem_pat, next, failure);
        if (idx + 1 < element_count) {
            ctx.builder.set_current_block(next);
        }
    }

    for (let suffix_idx = 0; suffix_idx < suffix.length(); suffix_idx += 1) {
        let elem_pat = suffix[suffix_idx];
        let absolute_idx_from_end = suffix.length() - suffix_idx;
        let elem_idx = prefix.length() + suffix_idx;
        let next = if (elem_idx + 1 == element_count) {
            element_success
        } else {
            ctx.builder.create_block()
        };
        let elem_local = project_array_pattern_element_from_end(ctx, scrutinee, elem_pat, absolute_idx_from_end);
        lower_pattern_test(ctx, elem_local, elem_pat, next, failure);
        if (elem_idx + 1 < element_count) {
            ctx.builder.set_current_block(next);
        }
    }

    if (rest_test_pat != null) {
        if (rest_entry != null) {
            ctx.builder.set_current_block(rest_entry);
        }
        let rest_local = project_array_pattern_rest(ctx, scrutinee, rest_test_pat, prefix.length(), suffix.length());
        lower_pattern_test(ctx, rest_local, rest_test_pat, success, failure);
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_irrefutable_catch_all @ d9be6853b
function is_irrefutable_catch_all(ctx: LoweringContext, pat_id: int) -> bool throws never {
    match (ctx.body.patterns[pat_id]) {
        root.ast.PatternWildcard => true,
        // `let x` is irrefutable; `let x: <pat>` is refutable iff the inner
        // sub-pattern is.
        let p: root.ast.PatternBind => {
            if let sp: int = p.subpat {
                is_irrefutable_catch_all(ctx, sp)
            } else {
                true
            }
        },
        let p: root.ast.PatternOr => {
            p.value.some((part) -> {
                is_irrefutable_catch_all(ctx, part)
            })
        },
        root.ast.PatternType | root.ast.PatternClass | root.ast.PatternArray | root.ast.PatternTuple => {
            false
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_narrow_type @ d9be6853b
// Type ascription on the pattern, if any. For `let x: T` (where the
// sub-pattern is a `Type`), returns `T`. For `[…]: T` (Array with
// ascription), returns `T`. Returns null for everything else (including
// `let x: <non-type-pattern>`).
function pattern_narrow_type(ctx: LoweringContext, pat_id: int) -> root.ast.TypeExpr? throws never {
    match (ctx.body.patterns[pat_id]) {
        let p: root.ast.PatternBind => {
            let sp = p.subpat
                ?? return null;
            match (ctx.body.patterns[sp]) {
                let t: root.ast.PatternType => t.value,
                _ => null,
            }
        },
        let p: root.ast.PatternArray => p.ascription,
        _ => null,
    }
}
