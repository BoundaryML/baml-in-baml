// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// MIR unit 4, match lowering: `lower_match`, the switch fast path
// (`try_lower_as_switch`, shared with `catch`) and the sequential
// `lower_match_chain`.
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - `try_lower_as_switch` (433 lines in Rust) is split along its own
//   blocks: `try_lower_as_switch_classify` (the classification loop, with
//   its `classify_atom` closure as `try_lower_as_switch_classify_atom`),
//   `try_lower_as_switch_arm_names` and `try_lower_as_switch_otherwise`,
//   called where the blocks were. The loop's mutable locals (`switch_kind`,
//   `int_arms`, `otherwise_idx`, `seen_values`) live in a
//   `SwitchArmClassification`, which Rust does not have; a null
//   classification is Rust's early `Ok(false)`.
// - `HashSet<SwitchKey>` (`seen_values`) is a `map<string, bool>` keyed by
//   an injective spelling of the key: `i<value>` for a `SwitchKeyInt`,
//   `c<class loc>` for a `SwitchKeyClass` (the prefix tells the variants
//   apart, the decimal value the keys within one). `HashMap<usize,
//   BlockId>` (`arm_blocks`) is `map<int, int>`.
// - `match_scrutinee.replace(..)` saves the old value and assigns the new;
//   the saved one is assigned back. `Place`s are never mutated, so
//   `dest.clone()` shares the place.

// The classification state of `try_lower_as_switch`'s arm loop (Rust's
// locals `switch_kind`, `int_arms`, `otherwise_idx`, `seen_values`).
class SwitchArmClassification {
    switch_kind: SwitchKind?,
    int_arms: (SwitchKey, int)[],
    otherwise_idx: int?,
    // Deduplicate keys so union patterns don't produce duplicate switch
    // arms. Keyed by the key's spelling (see the file header).
    seen_values: map<string, bool>,

    // Rust's `if seen_values.insert(key) { int_arms.push((key, i)) }`.
    function insert_arm(self, key: SwitchKey, arm_idx: int) -> void throws never {
        let spelled = match (key) {
            let k: SwitchKeyInt => `i${k.value}`,
            let k: SwitchKeyClass => `c${k.value}`,
        };
        if (!self.seen_values.has(spelled)) {
            self.seen_values[spelled] = true;
            self.int_arms.push((key, arm_idx));
        }
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_match @ d9be6853b
function lower_match(
    ctx: LoweringContext,
    expr_id: int,
    scrutinee: int,
    arm_ids: int[],
    dest: Place,
) -> void throws MirInternalError {
    let is_exhaustive = tir_is_exhaustive_match(ctx, expr_id);

    let resolved = try_resolve_to_local(ctx, scrutinee);
    let scrutinee_local = if (resolved != null) {
        resolved
    } else {
        let op = lower_to_operand(ctx, scrutinee);
        let ty = expr_ty(ctx, scrutinee);
        operand_to_local(ctx, op, ty)
    };

    let bb_join = ctx.builder.create_block();

    // Collect arms from arena.
    let arms = arm_ids.map((id) -> root.ast.MatchArm {
        ctx.body.match_arms[id]
    });

    // Try switch optimization: if all non-wildcard arms have compatible
    // patterns (int literal, enum variant, or type tag) with no guards, emit
    // a Switch.
    let switch_arms = arms.map((arm) -> (int, int, int?) {
        (arm.pattern, arm.body, arm.guard)
    });

    // Expose the scrutinee's static type to each arm's container type test
    // so it can decide whether a coarse `LIST`/`MAP` tag suffices; restore
    // the enclosing match's scrutinee (if any) once the arms are lowered.
    let scrutinee_ty = expr_ty(ctx, scrutinee);
    let saved_scrutinee = ctx.match_scrutinee;
    ctx.match_scrutinee = MatchScrutinee.new(scrutinee_local, scrutinee_ty);

    let switched = try_lower_as_switch(
        ctx,
        scrutinee_local,
        switch_arms,
        dest,
        bb_join,
        SwitchOtherwiseMatch { is_exhaustive: is_exhaustive },
        null,
    );
    if (!switched) {
        // Whether any non-final arm's emitted test can reject a value the
        // static exhaustiveness proof counted as matched (a typevar template
        // test meeting a callable with no reconstructible type; see
        // `pattern_test_can_reject_covered_values`). If so, the final arm's
        // test must be emitted (with a trap on fall-through) instead of
        // skipped: a wrongly-rejected value falling into an untested final
        // arm would silently bind at the wrong type, while the trap fails
        // loud.
        let backstop_last_arm = arms.length() > 0
            && arms.slice(0, arms.length() - 1).some((arm) -> {
                pattern_test_can_reject_covered_values(ctx, arm.pattern)
            });
        lower_match_chain(ctx, scrutinee_local, arms, dest, bb_join, is_exhaustive, backstop_last_arm);
    }

    ctx.match_scrutinee = saved_scrutinee;
    ctx.builder.set_current_block(bb_join);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_as_switch @ d9be6853b
// Attempt to lower a match or catch as a Switch terminator.
// Returns true if successful, false if the arms aren't switch-eligible.
//
// Unified entry point for both match and catch switch dispatch.
// - `arms`: `(pattern, body_expr, optional_guard)` tuples
// - `otherwise`: controls what happens for unmatched values
// - `pre_created_blocks`: if non-null, use these pre-created body blocks
//   instead of creating new ones (used by catch, which pre-creates blocks)
function try_lower_as_switch(
    ctx: LoweringContext,
    scrutinee: int,
    arms: (int, int, int?)[],
    dest: Place,
    join: int,
    otherwise: SwitchOtherwise,
    pre_created_blocks: int?[]?,
) -> bool throws MirInternalError {
    if (arms.length() == 0) {
        return false;
    }

    let is_exhaustive = match (otherwise) {
        let m: SwitchOtherwiseMatch => m.is_exhaustive,
        SwitchOtherwiseCatch => false,
    };

    // The enclosing match scrutinee's static type, for the tag-sufficiency
    // gate in `classify_pattern_type_tag`. Guarded on the local so the catch
    // path (whose error local is never the registered match scrutinee)
    // stays conservative (null).
    let scrutinee_static_ty = ctx.match_scrutinee?.ty_held_by(scrutinee);

    let classified = try_lower_as_switch_classify(ctx, arms, scrutinee_static_ty)
        ?? return false;
    let switch_kind = classified.switch_kind;
    let int_arms = classified.int_arms;
    let otherwise_idx = classified.otherwise_idx;

    // Need at least one int arm to justify a switch.
    if (int_arms.length() == 0) {
        return false;
    }

    // Reading a discriminant is only valid when every possible scrutinee
    // value belongs to this enum. Fall back for optionals and mixed unions.
    if let enum_kind: SwitchKindEnumDiscriminant = switch_kind {
        if (!runtime_ty_is_enum_only(ctx.builder.local_ty(scrutinee), enum_kind.value)) {
            return false;
        }
    }

    // TypeTag switches only pay off at 4+ arms (JumpTable). For fewer arms
    // the sequential `is_type` chain is more compact because the if-else
    // chain adds copy/pop stack management overhead per arm.
    let is_type_tag = switch_kind is SwitchKindTypeTag;
    if (is_type_tag && int_arms.length() < 4) {
        return false;
    }

    // Exhaustiveness: for **match** TypeTag switches without a wildcard arm,
    // all typed arms together cover the union: the otherwise block is dead.
    // TIR's `required_match_cases` returns None for class types, so class
    // unions are never marked exhaustive by TIR even when all arms are
    // covered. For match + TypeTag, if there's no wildcard, treat as
    // exhaustive so the last arm skips its comparison and the otherwise
    // block becomes Unreachable.
    //
    // For **catch** expressions, we never mark the switch as exhaustive even
    // when all declared thrown types are covered, because panics can always
    // occur at runtime and must be rethrown via the otherwise block.
    let is_match = otherwise is SwitchOtherwiseMatch;
    let is_switch_exhaustive = otherwise_idx == null && (is_exhaustive || (is_match && is_type_tag));

    // Save the entry block: this is where the switch terminator goes.
    let bb_entry = ctx.builder.current_block();

    // Emit discriminant/type-tag extraction before building arm blocks. We
    // must do this before create_block() calls so the assignment goes into
    // bb_entry.
    let switch_operand: Operand = match (switch_kind) {
        SwitchKindEnumDiscriminant => {
            let disc = ctx.builder.declare_local(root.types.TyInt {});
            ctx.builder.assign(
                PlaceLocal { value: disc },
                RvalueDiscriminant { value: PlaceLocal { value: scrutinee } },
            );
            operand_copy_local(disc)
        },
        SwitchKindTypeTag => {
            let tag_local = ctx.builder.declare_local(root.types.TyInt {});
            ctx.builder.assign(
                PlaceLocal { value: tag_local },
                RvalueTypeTag { value: PlaceLocal { value: scrutinee } },
            );
            operand_copy_local(tag_local)
        },
        _ => operand_copy_local(scrutinee),
    };

    // Build body blocks for each arm. Union sub-patterns sharing the same
    // arm_idx reuse a single block (e.g. Active | Pending -> same bb).
    let bb_otherwise = ctx.builder.create_block();
    let switch_arms: (SwitchKey, int)[] = [];
    let arm_blocks: map<int, int> = {};

    for (let int_arm in int_arms) {
        let (let val, let arm_idx) = int_arm;
        let existing_bb = arm_blocks.get(arm_idx);
        if (existing_bb != null) {
            // Union sub-pattern: reuse the same body block.
            switch_arms.push((val, existing_bb));
        } else {
            // Use pre-created block if available, otherwise create a new one.
            let bb_body = if (pre_created_blocks != null) {
                pre_created_blocks[arm_idx] ?? baml.sys.panic("pre-created block missing for arm")
            } else {
                ctx.builder.create_block()
            };
            switch_arms.push((val, bb_body));
            arm_blocks[arm_idx] = bb_body;

            ctx.builder.set_current_block(bb_body);
            let (let pattern, let body, _) = arms[arm_idx];
            bind_pattern(ctx, scrutinee, pattern, root.hir.DefinitionSitePatternBinding { value: pattern });
            lower_expr(ctx, body, dest);
            if (!ctx.builder.is_current_terminated()) {
                ctx.builder.goto(join);
            }
        }
    }

    // Build arm_names: symbolic labels for the switch arms (debug metadata).
    let arm_names = try_lower_as_switch_arm_names(ctx, switch_kind, int_arms);

    // Lower the otherwise block.
    ctx.builder.set_current_block(bb_otherwise);
    try_lower_as_switch_otherwise(ctx, scrutinee, arms, dest, join, otherwise, otherwise_idx, is_switch_exhaustive);

    // For catch with pre-created blocks: redirect wildcard arm's pre-created
    // block to bb_otherwise, since the wildcard body was lowered there.
    if (pre_created_blocks != null) {
        for (let i = 0; i < pre_created_blocks.length(); i += 1) {
            if let block: int = pre_created_blocks[i] {
                if (otherwise_idx == i) {
                    // Wildcard arm's pre-created block: redirect to otherwise.
                    ctx.builder.set_current_block(block);
                    ctx.builder.goto(bb_otherwise);
                } else if (!arm_blocks.has(i)) {
                    // Unreachable pre-created block (e.g. duplicate tag):
                    // terminate it.
                    ctx.builder.set_current_block(block);
                    ctx.builder.goto(bb_otherwise);
                }
            }
        }
    }

    // Emit the switch terminator in the entry block.
    ctx.builder.set_current_block(bb_entry);
    // An integer switch reads the scrutinee as a raw `int`. When the static
    // type admits anything else (`int | float`, a union with a class), a
    // non-int value reaching the switch is a *match failure*, not a broken
    // invariant: it belongs to no arm, so it belongs to `otherwise`. Without
    // the guard the VM raises a type error and the match aborts instead of
    // falling through. Provably int-only scrutinees, the overwhelmingly
    // common case, keep the bare switch.
    if (switch_kind is SwitchKindInteger && !runtime_ty_is_int_only(ctx.builder.local_ty(scrutinee))) {
        let bb_switch = ctx.builder.create_block();
        emit_is_type_tag_branch(ctx, scrutinee, root.types.TYPETAG_INT, bb_switch, bb_otherwise);
        ctx.builder.set_current_block(bb_switch);
    }
    ctx.builder.switch(switch_operand, switch_arms, bb_otherwise, is_switch_exhaustive, arm_names);

    true
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_as_switch @ d9be6853b
// `try_lower_as_switch`'s classification loop: collect (key, arm_index)
// for int literal, enum variant, or type patterns, and check for a
// trailing wildcard/binding. Null where Rust returns `Ok(false)`.
function try_lower_as_switch_classify(
    ctx: LoweringContext,
    arms: (int, int, int?)[],
    scrutinee_static_ty: root.types.RuntimeTy?,
) -> SwitchArmClassification? throws never {
    let state = SwitchArmClassification {
        switch_kind: null,
        int_arms: [],
        otherwise_idx: null,
        seen_values: {},
    };

    for (let i = 0; i < arms.length(); i += 1) {
        let (let pattern, _, let guard) = arms[i];
        // Guards disqualify switch optimization.
        if (guard != null) {
            return null;
        }
        // Narrowed bindings require NarrowBind's atomic test-and-bind
        // semantics, which Switch cannot preserve.
        if (pattern_narrow_type(ctx, pattern) != null) {
            return null;
        }

        match (ctx.body.patterns[pattern]) {
            let p: root.ast.PatternOr => {
                for (let sub_pat_id in p.value) {
                    if (
                        !try_lower_as_switch_classify_atom(ctx, i, sub_pat_id, state, scrutinee_static_ty)
                    ) {
                        return null;
                    }
                }
            },
            root.ast.PatternWildcard => {
                if (i != arms.length() - 1) {
                    return null;
                }
                state.otherwise_idx = i;
            },
            // Plain `let x` without a narrow always acts as the catch-all
            // arm, enabling jump-table dispatch. (Narrowed bindings, e.g.
            // `let n: int`, were handled by the `pattern_narrow_type` branch
            // above.)
            root.ast.PatternBind => {
                if (i != arms.length() - 1) {
                    return null;
                }
                state.otherwise_idx = i;
            },
            _ => {
                if (!try_lower_as_switch_classify_atom(ctx, i, pattern, state, scrutinee_static_ty)) {
                    return null;
                }
            },
        }
    }
    state
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_as_switch @ d9be6853b
// `try_lower_as_switch`'s `classify_atom` closure: classify a pattern (the
// arm pattern itself, or a sub-pattern of an `Or`) of arm `i` into a switch
// kind, updating `state`. False if the pattern disqualifies.
function try_lower_as_switch_classify_atom(
    ctx: LoweringContext,
    i: int,
    atom_id: int,
    state: SwitchArmClassification,
    scrutinee_static_ty: root.types.RuntimeTy?,
) -> bool throws never {
    let atom = ctx.body.patterns[atom_id];
    let type_kind = match (atom) {
        let p: root.ast.PatternType => p.value.kind,
        _ => null,
    };
    // OLD `Literal(Int(val))`: integer switch.
    let int_literal = match (type_kind) {
        let k: root.ast.TypeExprKindLiteral => {
            match (k.value) {
                let l: root.base.LiteralInt => l.value,
                _ => null,
            }
        },
        _ => null,
    };
    if (int_literal != null) {
        match (state.switch_kind) {
            null => {
                state.switch_kind = SwitchKindInteger {};
            },
            SwitchKindInteger => {},
            _ => {
                return false;
            },
        }
        state.insert_arm(SwitchKeyInt { value: int_literal }, i);
        return true;
    }
    // OLD `EnumVariant { ... }`: integer switch with discriminant. The new
    // repr puts enum variants inside `Pattern::Type`; detect via TIR.
    if (type_kind is root.ast.TypeExprKindPath) {
        if let variant_ty: root.types.TyEnumVariant = tir_pat_type(ctx, atom_id) {
            let enum_name = variant_ty.name;
            let variant = variant_ty.variant;
            match (state.switch_kind) {
                null => {
                    state.switch_kind = SwitchKindEnumDiscriminant { value: enum_name };
                },
                let n: SwitchKindEnumDiscriminant if n.value == enum_name => {},
                _ => {
                    return false;
                },
            }
            let enum_ref = root.hir_ty.enum_ref_of(ctx.db, variant_ty.name)
                ?? return false;
            let idx = root.hir_ty.enum_variant_index(ctx.db, enum_ref, variant)
                ?? return false;
            state.insert_arm(SwitchKeyInt { value: idx }, i);
            return true;
        }
    }
    // OLD `Type(_)` / `Bind { .. }` (with TIR type): TypeTag.
    match (atom) {
        root.ast.PatternType | root.ast.PatternBind => {
            match (state.switch_kind) {
                null => {
                    state.switch_kind = SwitchKindTypeTag {};
                },
                SwitchKindTypeTag => {},
                _ => {
                    return false;
                },
            }
            let keys = classify_pattern_type_tag(ctx, atom_id, scrutinee_static_ty)
                ?? return false;
            for (let key in keys) {
                state.insert_arm(key, i);
            }
            true
        },
        _ => false,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_as_switch @ d9be6853b
// `try_lower_as_switch`'s `arm_names`: symbolic labels for the switch arms
// (debug metadata).
function try_lower_as_switch_arm_names(
    ctx: LoweringContext,
    switch_kind: SwitchKind?,
    int_arms: (SwitchKey, int)[],
) -> (SwitchKey, string)[] throws never {
    match (switch_kind) {
        let enum_kind: SwitchKindEnumDiscriminant => {
            let enum_name = enum_kind.value;
            let enum_ref = root.hir_ty.enum_ref_of(ctx.db, enum_name);
            let variants: string[] = if (enum_ref != null) {
                root.hir_ty.enum_variants(ctx.db, enum_ref)
            } else {
                []
            };
            int_arms.filter_map((arm) -> (SwitchKey, string)? {
                let key = arm.0;
                let val = match (key) {
                    let k: SwitchKeyInt => k.value,
                    SwitchKeyClass => {
                        return null;
                    },
                };
                if (val < 0) {
                    return null;
                }
                let vname = variants.at(val)
                    ?? return null;
                (key, `${enum_name.name}.${vname}`)
            })
        },
        SwitchKindTypeTag => {
            int_arms.map((arm) -> (SwitchKey, string) {
                let name = match (arm.0) {
                    let k: SwitchKeyInt => format_type_tag_name(k.value),
                    let k: SwitchKeyClass => {
                        root.hir_ty.class_head(ctx.db, root.hir.DeclRefSource { value: k.value })
                            .name
                    },
                };
                (arm.0, name)
            })
        },
        _ => {
            int_arms.map((arm) -> (SwitchKey, string) {
                let name = match (arm.0) {
                    let k: SwitchKeyInt => `${k.value}`,
                    let k: SwitchKeyClass => {
                        root.hir_ty.class_head(ctx.db, root.hir.DeclRefSource { value: k.value })
                            .name
                    },
                };
                (arm.0, name)
            })
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_as_switch @ d9be6853b
// `try_lower_as_switch`'s otherwise block, lowered into the current block.
function try_lower_as_switch_otherwise(
    ctx: LoweringContext,
    scrutinee: int,
    arms: (int, int, int?)[],
    dest: Place,
    join: int,
    otherwise: SwitchOtherwise,
    otherwise_idx: int?,
    is_switch_exhaustive: bool,
) -> void throws MirInternalError {
    if (otherwise_idx != null) {
        // Wildcard arm present.
        match (otherwise) {
            let c: SwitchOtherwiseCatch if c.wildcard_skips_panics => {
                // The wildcard is the switch's last resort, so a panic that
                // passes over it has no arm left: it rethrows.
                let bb_panic = ctx.builder.create_block();
                emit_catch_wildcard_entry(ctx, c.error_local, true, bb_panic);
                let bb_wildcard_body = ctx.builder.current_block();
                ctx.builder.set_current_block(bb_panic);
                ctx.builder.rethrow(operand_copy_local(c.error_local), c.context_local);
                ctx.builder.set_current_block(bb_wildcard_body);
            },
            _ => {},
        }
        let (let pattern, let body, _) = arms[otherwise_idx];
        bind_pattern(ctx, scrutinee, pattern, root.hir.DefinitionSitePatternBinding { value: pattern });
        lower_expr(ctx, body, dest);
        if (!ctx.builder.is_current_terminated()) {
            ctx.builder.goto(join);
        }
        return;
    }
    // No wildcard: decide what the otherwise block does. Use
    // `is_switch_exhaustive` (which may be inferred for TypeTag) rather than
    // the caller's original `is_exhaustive`, so the otherwise block stays
    // consistent with the switch terminator flag. A catch rethrows either
    // way (even if exhaustive, the error might not match any arm at
    // runtime).
    match (otherwise) {
        SwitchOtherwiseMatch => {
            if (is_switch_exhaustive) {
                ctx.builder.unreachable();
            } else {
                ctx.builder.goto(join);
            }
        },
        let c: SwitchOtherwiseCatch => {
            ctx.builder.rethrow(operand_copy_local(c.error_local), c.context_local);
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_match_chain @ d9be6853b
function lower_match_chain(
    ctx: LoweringContext,
    scrutinee: int,
    arms: root.ast.MatchArm[],
    dest: Place,
    join: int,
    exhaustive: bool,
    backstop_last_arm: bool,
) -> void throws MirInternalError {
    if (arms.length() == 0) {
        // No more arms to test. An exhaustive match cannot get here (some
        // arm matched) and says so, as the switch lowering's otherwise block
        // does; the impossible edge must not reach the join, where `dest` is
        // read without having been written. A non-exhaustive match can, and
        // execution continues at the join.
        if (exhaustive) {
            ctx.builder.unreachable();
        } else {
            ctx.builder.goto(join);
        }
        return;
    }

    let arm = arms[0];
    let rest = arms.slice(1, arms.length());
    let arm_pattern = ctx.body.patterns[arm.pattern];

    // Exhaustive last arm: skip the pattern test (it must match). Do not
    // take this shortcut for Or-patterns because bindings must come from the
    // specific alternative that matched.
    if (exhaustive && rest.length() == 0 && arm.guard == null && !(arm_pattern is root.ast.PatternOr)) {
        // When a preceding arm's test can reject a value the static coverage
        // proof counted as matched (`backstop_last_arm`), "it must match" no
        // longer follows from exhaustiveness: the wrongly-rejected value
        // falls through to this arm. Emit the final refutable arm's test
        // anyway and trap on fall-through. Irrefutable last arms (wildcard,
        // bare bind) match everything, so they keep the plain skip.
        let last_is_refutable = match (arm_pattern) {
            root.ast.PatternWildcard => false,
            let b: root.ast.PatternBind => b.subpat != null,
            _ => true,
        };
        if (backstop_last_arm && last_is_refutable) {
            let bb_body = ctx.builder.create_block();
            let bb_trap = ctx.builder.create_block();
            lower_pattern_test(ctx, scrutinee, arm.pattern, bb_body, bb_trap);
            ctx.builder.set_current_block(bb_trap);
            ctx.builder.unreachable();
            ctx.builder.set_current_block(bb_body);
        }
        bind_pattern(ctx, scrutinee, arm.pattern, root.hir.DefinitionSitePatternBinding { value: arm.pattern });
        lower_expr(ctx, arm.body, dest);
        if (!ctx.builder.is_current_terminated()) {
            ctx.builder.goto(join);
        }
        return;
    }

    if let or_pat: root.ast.PatternOr = arm_pattern {
        let parts = or_pat.value;
        let bb_next = ctx.builder.create_block();
        for (let idx = 0; idx < parts.length(); idx += 1) {
            let part = parts[idx];
            let bb_body = ctx.builder.create_block();
            let bb_alt_next = if (idx + 1 == parts.length()) {
                bb_next
            } else {
                ctx.builder.create_block()
            };

            lower_pattern_test(ctx, scrutinee, part, bb_body, bb_alt_next);

            ctx.builder.set_current_block(bb_body);
            bind_pattern_inner(
                ctx,
                scrutinee,
                part,
                arm.pattern,
                part,
                root.hir.DefinitionSitePatternBinding { value: arm.pattern },
            );
            if let guard: int = arm.guard {
                let bb_guarded = ctx.builder.create_block();
                lower_condition(ctx, guard, bb_guarded, bb_next);
                ctx.builder.set_current_block(bb_guarded);
            }
            lower_expr(ctx, arm.body, dest);
            if (!ctx.builder.is_current_terminated()) {
                ctx.builder.goto(join);
            }

            if (idx + 1 < parts.length()) {
                ctx.builder.set_current_block(bb_alt_next);
            }
        }

        ctx.builder.set_current_block(bb_next);
        lower_match_chain(ctx, scrutinee, rest, dest, join, exhaustive, backstop_last_arm);
        return;
    }

    let bb_body = ctx.builder.create_block();
    let bb_next = ctx.builder.create_block();

    lower_pattern_test(ctx, scrutinee, arm.pattern, bb_body, bb_next);

    ctx.builder.set_current_block(bb_body);
    bind_pattern(ctx, scrutinee, arm.pattern, root.hir.DefinitionSitePatternBinding { value: arm.pattern });
    if let guard: int = arm.guard {
        let bb_guarded = ctx.builder.create_block();
        lower_condition(ctx, guard, bb_guarded, bb_next);
        ctx.builder.set_current_block(bb_guarded);
    }
    lower_expr(ctx, arm.body, dest);
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(join);
    }

    ctx.builder.set_current_block(bb_next);
    lower_match_chain(ctx, scrutinee, rest, dest, join, exhaustive, backstop_last_arm);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_test_can_reject_covered_values @ d9be6853b
// Whether lowering `pat`'s runtime test can *reject a value the static
// coverage proof counted as matched*. TIR's coverage relation is the same
// canonical invariant subtype the emitted tests evaluate, so for values with
// a concrete runtime type the two always agree, with one exception: a value
// whose concrete type the VM cannot reconstruct (`value_concrete_ty` is
// `None`: a compile-time definition object) fails every structural test,
// including one whose realized binding IS that value's static type. A
// non-final `let v: T` arm can therefore wrongly reject such a value, so an
// exhaustive match containing one cannot safely skip its final arm's test
// (see `lower_match_chain`'s backstop).
//
// Over-approximation is safe (one extra final test plus a dead trap block);
// under-approximation would silently bind a value to a pattern it does not
// match.
function pattern_test_can_reject_covered_values(
    ctx: LoweringContext,
    pat_id: int,
) -> bool throws never {
    match (ctx.body.patterns[pat_id]) {
        let p: root.ast.PatternOr => {
            p.value.some((part) -> {
                pattern_test_can_reject_covered_values(ctx, part)
            })
        },
        let p: root.ast.PatternTuple => {
            p.value.some((part) -> {
                pattern_test_can_reject_covered_values(ctx, part)
            })
        },
        let p: root.ast.PatternBind => {
            if let sp: int = p.subpat {
                pattern_test_can_reject_covered_values(ctx, sp)
            } else {
                // Irrefutable patterns emit no test.
                false
            }
        },
        root.ast.PatternWildcard => false,
        root.ast.PatternType | root.ast.PatternClass | root.ast.PatternArray => {
            let tir_ty = tir_pat_type(ctx, pat_id)
                ?? return false;
            // Typevar-carrying patterns route through the dispatch-guard
            // template (see `lower_pattern_test`); only their realized
            // bindings can name a function type a closure would need to
            // match.
            root.types.contains_ty_where(tir_ty, (t) -> {
                t is root.types.TyTypeVar
            })
        },
    }
}
