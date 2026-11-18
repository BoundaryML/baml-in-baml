// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// MIR unit 4, pattern bindings: `bind_pattern` and its walk, the
// or-pattern declare-then-assign scheme, and tuple slot projection.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - `project_tuple_pattern_element`'s nested `fn slot` is
//   `project_tuple_pattern_element_slot`.
// - `collect_pattern_bindings`' `&mut Vec` out-parameter is an array the
//   caller passes (shared, so pushes are seen by the caller); each caller
//   passes a fresh one, as Rust's `Vec::new()`.
// - `self.body.patterns[..].clone()` reads the pattern; patterns are never
//   mutated, so nothing is copied.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::bind_pattern @ d9be6853b
// Bind the names `pat_id` introduces, registered under `site`: the
// construct HIR registered them for.
function bind_pattern(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    // Pass the root pat_id through recursion: HIR registers bindings keyed
    // by the OUTER pattern id (the let-stmt's pattern, the match-arm's
    // pattern, etc.), never by the inner Bind. To wire up closure capture
    // lookups correctly, we register the local against that root.
    bind_pattern_inner(ctx, scrutinee, pat_id, pat_id, pat_id, site);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::bind_pattern_inner @ d9be6853b
function bind_pattern_inner(
    ctx: LoweringContext,
    scrutinee_in: int,
    pat_id: int,
    root_id: int,
    narrow_root: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    let key = pat_metadata_key(ctx, pat_id);
    let scrutinee = ctx.tested_pattern_values.get(key.0)?.get(key.1) ?? scrutinee_in;
    match (ctx.body.patterns[pat_id]) {
        let p: root.ast.PatternBind => {
            let bound_scrutinee = if let subpat: int = p.subpat {
                let sub_key = pat_metadata_key(ctx, subpat);
                ctx.tested_pattern_values.get(sub_key.0)?.get(sub_key.1) ?? scrutinee
            } else {
                scrutinee
            };
            // For Or-patterns we look up `pat_types` against the inner
            // bind's `pat_id`, not the outer `root`. That's safe because TIR
            // rejects Or-branches whose shared bindings disagree on type
            // (`OrPatternBindingTypeMismatch`), so by the time we reach MIR
            // every alternative's bind for `name` carries the same type. If
            // you ever loosen that TIR invariant, switch this lookup to
            // `root` so we don't over-narrow.
            let narrow = pattern_narrow_type(ctx, narrow_root);
            let ty = if (narrow != null) {
                resolve_type_annotation(ctx, narrow)
            } else {
                let tir_ty = tir_pat_type(ctx, pat_id);
                if (tir_ty != null) {
                    runtime(ctx).convert(tir_ty)
                } else {
                    ctx.builder.local_ty(scrutinee)
                }
            };
            let local = declare_binding(ctx, root_id, site, p.name, ty);
            let value = value_place(ctx, local);
            ctx.builder.assign(value, RvalueUse { value: operand_copy_local(bound_scrutinee) });
            // Recurse into the sub-pattern so inner bindings (e.g. `let x:
            // let y` or `let x: Class { f }`) get emitted too.
            if let sp: int = p.subpat {
                bind_pattern_inner(ctx, bound_scrutinee, sp, root_id, sp, site);
            }
        },
        let p: root.ast.PatternOr => {
            let bindings: (string, int)[] = [];
            collect_pattern_bindings(ctx, pat_id, bindings);
            if (bindings.length() == 0) {
                return;
            }
            declare_or_pattern_bindings(ctx, pat_id, root_id, site);
            lower_or_pattern_assign_existing(ctx, scrutinee, p.value, root_id, narrow_root, site);
        },
        let p: root.ast.PatternClass => {
            for (let f in p.fields) {
                let field_local = project_class_pattern_field(ctx, scrutinee, pat_id, f.pat, f.field);
                bind_pattern_inner(ctx, field_local, f.pat, root_id, f.pat, site);
            }
        },
        let p: root.ast.PatternTuple => {
            let elements = p.value;
            let arity = elements.length();
            for (let idx = 0; idx < arity; idx += 1) {
                let elem_pat = elements[idx];
                if (!pattern_binds_names(ctx, elem_pat)) {
                    continue;
                }
                let elem_local = project_tuple_pattern_element(ctx, scrutinee, elem_pat, idx, arity);
                bind_pattern_inner(ctx, elem_local, elem_pat, root_id, elem_pat, site);
            }
        },
        let p: root.ast.PatternArray => {
            let prefix = p.prefix;
            let suffix = p.suffix;
            for (let idx = 0; idx < prefix.length(); idx += 1) {
                let elem_pat = prefix[idx];
                let elem_local = project_array_pattern_element_from_start(ctx, scrutinee, elem_pat, idx);
                bind_pattern_inner(ctx, elem_local, elem_pat, root_id, elem_pat, site);
            }
            if let rest_pat: int = p.rest?.pat {
                // Wildcard rests bind nothing; skip the slice copy.
                if (!(ctx.body.patterns[rest_pat] is root.ast.PatternWildcard)) {
                    let rest_local = project_array_pattern_rest(ctx, scrutinee, rest_pat, prefix.length(), suffix.length());
                    bind_pattern_inner(ctx, rest_local, rest_pat, root_id, rest_pat, site);
                }
            }
            for (let suffix_idx = 0; suffix_idx < suffix.length(); suffix_idx += 1) {
                let elem_pat = suffix[suffix_idx];
                let absolute_idx_from_end = suffix.length() - suffix_idx;
                let elem_local = project_array_pattern_element_from_end(ctx, scrutinee, elem_pat, absolute_idx_from_end);
                bind_pattern_inner(ctx, elem_local, elem_pat, root_id, elem_pat, site);
            }
        },
        root.ast.PatternWildcard | root.ast.PatternType => {},
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::collect_pattern_bindings @ d9be6853b
function collect_pattern_bindings(
    ctx: LoweringContext,
    pat_id: int,
    out: (string, int)[],
) -> void throws never {
    match (ctx.body.patterns[pat_id]) {
        let p: root.ast.PatternBind => {
            out.push((p.name, pat_id));
            if let sp: int = p.subpat {
                collect_pattern_bindings(ctx, sp, out);
            }
        },
        let p: root.ast.PatternOr => {
            if let first: int = p.value.at(0) {
                collect_pattern_bindings(ctx, first, out);
            }
        },
        let p: root.ast.PatternClass => {
            for (let field in p.fields) {
                collect_pattern_bindings(ctx, field.pat, out);
            }
        },
        let p: root.ast.PatternArray => {
            for (let part in p.prefix) {
                collect_pattern_bindings(ctx, part, out);
            }
            if let rest_pat: int = p.rest?.pat {
                collect_pattern_bindings(ctx, rest_pat, out);
            }
            for (let part in p.suffix) {
                collect_pattern_bindings(ctx, part, out);
            }
        },
        let p: root.ast.PatternTuple => {
            for (let part in p.value) {
                collect_pattern_bindings(ctx, part, out);
            }
        },
        root.ast.PatternWildcard | root.ast.PatternType => {},
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_binds_names @ d9be6853b
function pattern_binds_names(ctx: LoweringContext, pat_id: int) -> bool throws never {
    let bindings: (string, int)[] = [];
    collect_pattern_bindings(ctx, pat_id, bindings);
    bindings.length() > 0
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_tuple_pattern_element @ d9be6853b
function project_tuple_pattern_element(
    ctx: LoweringContext,
    scrutinee: int,
    elem_pat: int,
    index: int,
    arity: int,
) -> int throws MirInternalError {
    let slots: root.types.RuntimeTy[] = [];
    project_tuple_pattern_element_slot(ctx.builder.local_ty(scrutinee), index, arity, slots);
    let elem_ty = match (slots.length()) {
        0 => pat_ty(ctx, elem_pat),
        1 => slots[0],
        _ => root.types.RuntimeTyUnion { members: slots },
    };
    let index_local = ctx.builder.declare_local(root.types.TyInt {});
    ctx.builder.assign(
        PlaceLocal { value: index_local },
        RvalueUse { value: OperandConstant { value: ConstantInt { value: index } } },
    );
    let elem_local = ctx.builder.declare_local(elem_ty);
    ctx.builder.assign(
        PlaceLocal { value: elem_local },
        RvalueUse {
            value: OperandCopy {
                value: PlaceIndex {
                    base: PlaceLocal { value: scrutinee },
                    index: index_local,
                    kind: IndexKind.Tuple,
                },
            },
        },
    );
    elem_local
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_tuple_pattern_element::slot @ d9be6853b
// The type of slot `index` of each `arity`-tuple `ty` may be, pushed onto
// `out`; `unknown` for a type that may hold any tuple.
function project_tuple_pattern_element_slot(
    ty: root.types.RuntimeTy,
    index: int,
    arity: int,
    out: root.types.RuntimeTy[],
) -> void throws never {
    match (ty) {
        let t: root.types.RuntimeTyTuple if t.items.length() == arity => {
            out.push(t.items[index]);
        },
        let u: root.types.RuntimeTyUnion => {
            for (let member in u.members) {
                project_tuple_pattern_element_slot(member, index, arity, out);
            }
        },
        root.types.TyUnknown
            | root.types.RuntimeTyInterface
            | root.types.TyTypeVar
            | root.types.RuntimeTyAssociatedTypeProjection
            | root.types.TyTypeAlias =>
        {
            out.push(root.types.TyUnknown {});
        },
        _ => {},
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::declare_or_pattern_bindings @ d9be6853b
// Declare every name an or-pattern binds, once, ahead of the alternatives
// that each assign it.
function declare_or_pattern_bindings(
    ctx: LoweringContext,
    pat_id: int,
    root_id: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    let bindings: (string, int)[] = [];
    collect_pattern_bindings(ctx, pat_id, bindings);
    for (let binding in bindings) {
        let (let name, let bind_pat) = binding;
        let ty = pat_ty(ctx, bind_pat);
        declare_binding(ctx, root_id, site, name, ty);
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_or_pattern_assign_existing @ d9be6853b
function lower_or_pattern_assign_existing(
    ctx: LoweringContext,
    scrutinee: int,
    parts: int[],
    root_id: int,
    narrow_root: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    if (parts.length() == 0) {
        ctx.builder.unreachable();
        return;
    }

    let join = ctx.builder.create_block();
    let failure = ctx.builder.create_block();

    for (let idx = 0; idx < parts.length(); idx += 1) {
        let part = parts[idx];
        let body = ctx.builder.create_block();
        let next = if (idx + 1 == parts.length()) {
            failure
        } else {
            ctx.builder.create_block()
        };
        lower_pattern_test(ctx, scrutinee, part, body, next);

        ctx.builder.set_current_block(body);
        assign_pattern_to_existing(ctx, scrutinee, part, root_id, narrow_root, site);
        if (!ctx.builder.is_current_terminated()) {
            ctx.builder.goto(join);
        }

        if (idx + 1 < parts.length()) {
            ctx.builder.set_current_block(next);
        }
    }

    ctx.builder.set_current_block(failure);
    ctx.builder.unreachable();
    ctx.builder.set_current_block(join);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::assign_pattern_to_existing @ d9be6853b
function assign_pattern_to_existing(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    root_id: int,
    narrow_root: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    match (ctx.body.patterns[pat_id]) {
        let p: root.ast.PatternBind => {
            let binding_id = binding_id_for_pattern_site_name(ctx, root_id, site, p.name);
            let found = if (binding_id != null) {
                ctx.binding_locals.get(binding_id)
            } else {
                null
            };
            let local = found
                ?? baml.sys.panic(
                    `or-pattern binding \`${p.name}\` was not declared ahead of its alternatives`,
                );
            let value = value_place(ctx, local);
            ctx.builder.assign(value, RvalueUse { value: operand_copy_local(scrutinee) });
        },
        let p: root.ast.PatternOr => {
            lower_or_pattern_assign_existing(ctx, scrutinee, p.value, root_id, narrow_root, site);
        },
        let p: root.ast.PatternClass => {
            for (let field in p.fields) {
                let field_local = project_class_pattern_field(ctx, scrutinee, pat_id, field.pat, field.field);
                assign_pattern_to_existing(ctx, field_local, field.pat, root_id, field.pat, site);
            }
        },
        let p: root.ast.PatternTuple => {
            let elements = p.value;
            let arity = elements.length();
            for (let idx = 0; idx < arity; idx += 1) {
                let elem_pat = elements[idx];
                if (!pattern_binds_names(ctx, elem_pat)) {
                    continue;
                }
                let elem_local = project_tuple_pattern_element(ctx, scrutinee, elem_pat, idx, arity);
                assign_pattern_to_existing(ctx, elem_local, elem_pat, root_id, elem_pat, site);
            }
        },
        let p: root.ast.PatternArray => {
            let prefix = p.prefix;
            let suffix = p.suffix;
            for (let idx = 0; idx < prefix.length(); idx += 1) {
                let elem_pat = prefix[idx];
                let elem_local = project_array_pattern_element_from_start(ctx, scrutinee, elem_pat, idx);
                assign_pattern_to_existing(ctx, elem_local, elem_pat, root_id, elem_pat, site);
            }
            if let rest_pat: int = p.rest?.pat {
                let rest_local = project_array_pattern_rest(ctx, scrutinee, rest_pat, prefix.length(), suffix.length());
                assign_pattern_to_existing(ctx, rest_local, rest_pat, root_id, rest_pat, site);
            }
            for (let suffix_idx = 0; suffix_idx < suffix.length(); suffix_idx += 1) {
                let elem_pat = suffix[suffix_idx];
                let absolute_idx_from_end = suffix.length() - suffix_idx;
                let elem_local = project_array_pattern_element_from_end(ctx, scrutinee, elem_pat, absolute_idx_from_end);
                assign_pattern_to_existing(ctx, elem_local, elem_pat, root_id, elem_pat, site);
            }
        },
        root.ast.PatternWildcard | root.ast.PatternType => {},
    }
}
