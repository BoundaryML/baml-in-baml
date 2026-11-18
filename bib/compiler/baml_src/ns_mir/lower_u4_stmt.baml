// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// MIR unit 4, statements: `for` loops (iterable and dead), `lower_stmt` and
// its arms, and assignment targets (`lower_store_place`, `lower_lvalue`).
//
// Restructured (BAML forces it):
// - `LoweringContext` methods are free functions taking `ctx` first.
// - `lower_stmt` (445 lines in Rust) stays the dispatcher; its large arms
//   are `lower_stmt_<arm>` helpers, called where the arm was, side effects
//   in Rust's order. Its `For` arm returns from `lower_stmt` without
//   restoring the source span when the collection is `never`, as Rust does.
// - `lower_lvalue`'s large arms are `lower_lvalue_<arm>` helpers.
// - `loop_context.take()` saves the old context object and assigns a new
//   one; the saved object is assigned back (never mutated in place).
// - No `Place` is cloned here (each `value_place` call builds a fresh
//   one); `binding.bounds.clone()` is copied (`concat([])`), as it is
//   stored in `generic_param_bounds`.
// - `{ty:?}` (a derived `Debug` of a type) in an internal error is
//   `root.hir_ty.ty_debug` of the widened type.

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_iterable_for_loop @ d9be6853b
function lower_iterable_for_loop(
    ctx: LoweringContext,
    stmt_id: int,
    binding: int,
    collection: int,
    body: int,
    iterable_view: InterfaceTypeView,
) -> void throws MirInternalError {
    let coll_ty = expr_ty(ctx, collection);
    let coll_local = ctx.builder.declare_local(coll_ty);
    lower_expr(ctx, collection, PlaceLocal { value: coll_local });

    let (let iterable_tn, let iterable_args, let iterable_assoc) = iterable_view;
    // A bare `Iterable` view pins nothing: iterating a `T extends Iterable`
    // or an unpinned existential reaches here with an empty binding list.
    // The top type is a sound supertype for the element.
    //
    // BUG: the faithful element type is the symbolic projection
    // `(collection as Iterable).Item`, which `RuntimeTy` carries and the
    // runtime can resolve from the receiver. Erasing to `unknown` throws
    // that away.
    let item_tir_ty = associated_binding_ty(iterable_assoc, "Item") ?? root.types.TyUnknown {};
    let elem_ty = convert_tir_ty_for_runtime(ctx, item_tir_ty);

    let iterator_tn = baml_decl(ctx, "iter", "Iterator");
    let iter_method = "iter";
    let iterator = baml_iter_decl(ctx, "Iterator");
    let iter_ty = if (iterator != null) {
        convert_tir_ty_for_runtime(
            ctx,
            root.types.TyInterface {
                name: iterator,
                args: [],
                associated_types: iterable_assoc.map((b) -> root.types.AssociatedType {
                    root.types.AssociatedType { name: b.0, ty: b.1 }
                }),
            },
        )
    } else {
        root.types.TyUnknown {}
    };
    let iter_local = ctx.builder.declare_local(iter_ty);
    // `collection.iter()`: open-world virtual dispatch on the collection's
    // `Iterable` view; the VM resolves the impl from the runtime concrete
    // type (containers included; array/map values carry their element types).
    emit_virtual_call(
        ctx,
        coll_local,
        iterable_tn,
        iterable_args,
        iterable_assoc,
        iter_method,
        body,
        [],
        PlaceLocal { value: iter_local },
    );

    let bb_header = ctx.builder.create_block();
    let bb_body = ctx.builder.create_block();
    let bb_exit = ctx.builder.create_block();

    let prev_loop = ctx.loop_context;
    ctx.loop_context
        = LoopContext {
            break_target: bb_exit,
            continue_target: bb_header,
            defer_depth: ctx.defer_stack.length(),
        };

    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_header);
    }

    ctx.builder.set_current_block(bb_header);
    let next_method = "next";
    let next_local = ctx.builder.declare_local(root.types.TyUnknown {});
    // `iterator.next()`: the iterator value's concrete adapter class resolves
    // its own `Iterator` impl at runtime.
    emit_virtual_call(
        ctx,
        iter_local,
        iterator_tn,
        [],
        iterable_assoc,
        next_method,
        body,
        [],
        PlaceLocal { value: next_local },
    );
    emit_is_type_branch(ctx, next_local, baml_iter_done_ty(ctx), bb_exit, bb_body);

    ctx.builder.set_current_block(bb_body);
    let elem_local = ctx.builder.declare_local(elem_ty);
    ctx.builder.assign(
        PlaceLocal { value: elem_local },
        RvalueUse { value: OperandCopy { value: PlaceLocal { value: next_local } } },
    );
    bind_pattern(ctx, elem_local, binding, root.hir.DefinitionSiteStatement { value: stmt_id });

    let body_temp = ctx.builder.declare_local(expr_ty(ctx, body));
    lower_expr(ctx, body, PlaceLocal { value: body_temp });

    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_header);
    }

    ctx.loop_context = prev_loop;
    ctx.builder.set_current_block(bb_exit);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_dead_for_loop @ d9be6853b
// A `for let` over a collection typed `never`: only the collection
// runs, and the checker types the loop and the code after it as dead.
// The collection need not end its block with a terminator (a call typed
// `never` returns to a successor), so the block ends with an
// unreachable, as `let … else` does. The body is still lowered, in a
// dead block, so every binding it declares gets its local (the tripwire
// in `verify_bindings_recorded`), as the code after a `return`
// is; the statements after the loop follow in another dead block.
function lower_dead_for_loop(
    ctx: LoweringContext,
    stmt_id: int,
    binding: int,
    collection: int,
    body: int,
) -> void throws MirInternalError {
    let coll_ty = expr_ty(ctx, collection);
    let coll_local = ctx.builder.declare_local(coll_ty);
    lower_expr(ctx, collection, PlaceLocal { value: coll_local });
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.unreachable();
    }

    let bb_body = ctx.builder.create_block();
    let bb_exit = ctx.builder.create_block();
    let prev_loop = ctx.loop_context;
    ctx.loop_context
        = LoopContext {
            break_target: bb_exit,
            continue_target: bb_body,
            defer_depth: ctx.defer_stack.length(),
        };

    ctx.builder.set_current_block(bb_body);
    declare_dead_pattern_bindings(ctx, binding, binding, root.hir.DefinitionSiteStatement { value: stmt_id });
    let body_temp = ctx.builder.declare_local(expr_ty(ctx, body));
    lower_expr(ctx, body, PlaceLocal { value: body_temp });
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.unreachable();
    }

    ctx.loop_context = prev_loop;
    ctx.builder.set_current_block(bb_exit);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::declare_dead_pattern_bindings @ d9be6853b
// Declares a local for every binding `pat_id` introduces without
// matching the pattern: for a pattern in dead code whose scrutinee
// never exists (a `for let` over `never`). HIR registered each binding
// against the root pattern and `verify_bindings_recorded` expects a
// local for each, while a projection (a class field, a tuple slot) would
// need a value's type that `never` does not have.
function declare_dead_pattern_bindings(
    ctx: LoweringContext,
    pat_id: int,
    root_id: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    match (ctx.body.patterns[pat_id]) {
        let p: root.ast.PatternBind => {
            let tir_ty = tir_pat_type(ctx, pat_id);
            let ty = if (tir_ty != null) {
                runtime(ctx).convert(tir_ty)
            } else {
                root.types.TyNever {}
            };
            declare_binding(ctx, root_id, site, p.name, ty);
            if let subpat: int = p.subpat {
                declare_dead_pattern_bindings(ctx, subpat, root_id, site);
            }
        },
        let p: root.ast.PatternClass => {
            for (let field in p.fields) {
                declare_dead_pattern_bindings(ctx, field.pat, root_id, site);
            }
        },
        let p: root.ast.PatternArray => {
            let rest: int[] = [];
            if let rest_pat: int = p.rest?.pat {
                rest.push(rest_pat);
            }
            for (let element in p.prefix.concat(rest).concat(p.suffix)) {
                declare_dead_pattern_bindings(ctx, element, root_id, site);
            }
        },
        let p: root.ast.PatternTuple => {
            for (let element in p.value) {
                declare_dead_pattern_bindings(ctx, element, root_id, site);
            }
        },
        let p: root.ast.PatternOr => {
            for (let element in p.value) {
                declare_dead_pattern_bindings(ctx, element, root_id, site);
            }
        },
        root.ast.PatternWildcard | root.ast.PatternType => {},
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_stmt @ d9be6853b
function lower_stmt(ctx: LoweringContext, stmt_id: int) -> void throws MirInternalError {
    let prev_span = ctx.builder.current_source_span;
    if let span: root.base.Span = span_for_stmt(ctx, stmt_id) {
        ctx.builder.current_source_span = span;
    }

    match (ctx.body.stmts[stmt_id]) {
        let s: root.ast.StmtExpr => {
            let ty = expr_ty(ctx, s.value);
            let temp = ctx.builder.declare_local(ty);
            lower_expr(ctx, s.value, PlaceLocal { value: temp });
        },
        let s: root.ast.StmtTypeBinding => lower_stmt_type_binding(ctx, stmt_id, s),
        // `let PATTERN = init else { … };`: refutable binding lowered as a
        // two-way pattern test. Handled before the structural arms below
        // because a refutable destructure ends up here too.
        let s: root.ast.StmtLet if s.else_branch != null => lower_stmt_let_else(ctx, stmt_id, s),
        let s: root.ast.StmtLet if pattern_contains_structural(ctx, s.pattern) => {
            let local_ty = pat_ty(ctx, s.pattern);
            let scrutinee = ctx.builder.declare_local(local_ty);

            if let init: int = s.initializer {
                lower_expr(ctx, init, PlaceLocal { value: scrutinee });
            } else {
                ctx.builder.assign(
                    PlaceLocal { value: scrutinee },
                    RvalueUse { value: OperandConstant { value: ConstantNull {} } },
                );
            }

            bind_pattern(ctx, scrutinee, s.pattern, root.hir.DefinitionSiteStatement { value: stmt_id });
        },
        let s: root.ast.StmtLet => lower_stmt_let(ctx, stmt_id, s),
        let s: root.ast.StmtWhile => lower_stmt_while(ctx, s),
        let s: root.ast.StmtWhileLet => lower_stmt_while_let(ctx, stmt_id, s),
        // For loops use the Iterable interface: evaluate the collection,
        // call iter(), then repeatedly call next() until Done.
        let s: root.ast.StmtFor => {
            let coll_tir_ty = tir_expr_type(ctx, s.collection);
            if (coll_tir_ty is root.types.TyNever) {
                lower_dead_for_loop(ctx, stmt_id, s.binding, s.collection, s.body);
                return;
            }
            let iterable_view = if (coll_tir_ty != null) {
                iterable_view_for_tir_ty(ctx, coll_tir_ty)
            } else {
                null
            };

            if (iterable_view != null) {
                lower_iterable_for_loop(ctx, stmt_id, s.binding, s.collection, s.body, iterable_view);
            } else {
                throw internal_error(ctx, "for loop collection is not iterable", s.collection);
            }
        },
        let s: root.ast.StmtReturn => lower_stmt_return(ctx, s),
        let s: root.ast.StmtThrow => {
            let val_op = lower_throw_operand(ctx, s.value);
            // Defers run via the block's unwind landing pads: the throw's PC
            // is inside the enclosing defer region(s), so the exception table
            // routes it to the innermost defer pad. We do NOT inline-replay
            // here: that would double-run the defers.
            emit_throw(ctx, val_op);
            let dead = ctx.builder.create_block();
            ctx.builder.set_current_block(dead);
        },
        root.ast.StmtBreak => {
            if let loop_ctx: LoopContext = ctx.loop_context {
                let target = loop_ctx.break_target;
                let defer_depth = loop_ctx.defer_depth;
                // Run defers declared in the loop body.
                replay_defers_to_depth(ctx, defer_depth);
                ctx.builder.goto(target);
            }
            let dead = ctx.builder.create_block();
            ctx.builder.set_current_block(dead);
        },
        root.ast.StmtContinue => {
            if let loop_ctx: LoopContext = ctx.loop_context {
                let target = loop_ctx.continue_target;
                let defer_depth = loop_ctx.defer_depth;
                // Run defers declared in the loop body.
                replay_defers_to_depth(ctx, defer_depth);
                ctx.builder.goto(target);
            }
            let dead = ctx.builder.create_block();
            ctx.builder.set_current_block(dead);
        },
        // A defer is armed by `lower_scoped_block`, which intercepts it
        // before this dispatch to open its landing-pad region; the only other
        // statement lowered here is a C-style `for` step, which the parser
        // never produces as a `defer`.
        root.ast.StmtDefer => {
            baml.sys.panic("a `defer` statement is armed by `lower_scoped_block`, not lowered here")
        },
        let s: root.ast.StmtAssign => {
            match (ctx.body.exprs[s.target]) {
                let chain: root.ast.ExprOptionalChain => {
                    lower_assign_optional_chain(ctx, chain.expr, s.value)
                },
                // Handled when true: the destination slot is only known once
                // the receiver's impl is resolved, so there is no `Place` to
                // assign through.
                _ => {
                    if (!try_lower_virtual_field_assign(ctx, s.target, s.value)) {
                        let place = lower_store_place(ctx, s.target);
                        lower_expr(ctx, s.value, place);
                    }
                },
            }
        },
        let s: root.ast.StmtAssignOp => {
            match (ctx.body.exprs[s.target]) {
                let chain: root.ast.ExprOptionalChain => {
                    lower_assign_op_optional_chain(ctx, chain.expr, s.op, s.value)
                },
                // Handled when true: see `StmtAssign`.
                _ => {
                    if (!try_lower_virtual_field_assign_op(ctx, s.target, s.op, s.value)) {
                        let place = lower_store_place(ctx, s.target);
                        emit_assign_op(ctx, place, s.target, s.op, s.value);
                    }
                },
            }
        },
        root.ast.StmtMissing => lower_stmt_missing(ctx),
        root.ast.StmtHeaderComment => {},
    }

    ctx.builder.current_source_span = prev_span;
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_stmt @ d9be6853b
// `lower_stmt`'s `AstStmt::TypeBinding` arm.
function lower_stmt_type_binding(
    ctx: LoweringContext,
    stmt_id: int,
    s: root.ast.StmtTypeBinding,
) -> void throws MirInternalError {
    let binding = tir_type_binding(ctx, stmt_id)
        ?? throw internal_error_here(
            ctx,
            `TIR recorded no binding plan for the scoped type \`${s.name}\``,
        );
    if (binding.name != s.name) {
        throw internal_error_here(
            ctx,
            `TIR's binding plan names \`${binding.name}\` where the statement binds \`${s.name}\``,
        );
    }
    // The slot is reserved before the operand is lowered: the layout must
    // already contain this binding for `T` to be addressable by the bound
    // checks and right after the statement.
    ctx.scoped_type_binding_params.push(binding.parameter);
    // A bounded binding's members dispatch through its bounds as a declared
    // generic parameter's do. The parameter is unique to this statement, so
    // its entry outlives the block harmlessly (a lambda written in the block
    // is lowered after it closes).
    if (binding.bounds.length() > 0) {
        ctx.generic_param_bounds[binding.parameter] = binding.bounds.concat([]);
    }
    emit_scoped_type_binding(ctx, binding, s.else_branch);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_stmt @ d9be6853b
// `lower_stmt`'s `AstStmt::Let` arm with an `else` branch: on match, bind
// into the current scope (locals survive past the statement); on miss,
// lower the else expression (guaranteed `never` by TIR, so no successor
// edge is needed).
function lower_stmt_let_else(
    ctx: LoweringContext,
    stmt_id: int,
    s: root.ast.StmtLet,
) -> void throws MirInternalError {
    let else_expr = s.else_branch ?? baml.sys.panic("guarded by the caller");
    // Materialize the scrutinee into a local once. The scrutinee carries the
    // BROAD initializer type (e.g. `int | string`), not the pattern's
    // narrowed match type: narrowing only kicks in on the match arm, after
    // the refutable test.
    let scrutinee_ty = if let init: int = s.initializer {
        expr_ty(ctx, init)
    } else {
        pat_ty(ctx, s.pattern)
    };
    let scrutinee = ctx.builder.declare_local(scrutinee_ty);
    if let init: int = s.initializer {
        lower_expr(ctx, init, PlaceLocal { value: scrutinee });
    } else {
        ctx.builder.assign(
            PlaceLocal { value: scrutinee },
            RvalueUse { value: OperandConstant { value: ConstantNull {} } },
        );
    }

    let bb_match = ctx.builder.create_block();
    let bb_fail = ctx.builder.create_block();
    lower_pattern_test(ctx, scrutinee, s.pattern, bb_match, bb_fail);

    // Fail path: lower the else expression. TIR enforced that the else has
    // type `!`, so this block has no successor and we don't emit a join
    // edge. Use a throwaway temp as dest because diverging expressions don't
    // write through it.
    ctx.builder.set_current_block(bb_fail);
    let else_ty = expr_ty(ctx, else_expr);
    let else_dest = ctx.builder.declare_local(else_ty);
    lower_expr(ctx, else_expr, PlaceLocal { value: else_dest });
    // The checker requires the `else` to diverge, but a diverging expression
    // need not end its block with a terminator (a call typed `never`
    // returns to a successor), so terminate it with an unreachable to keep
    // the CFG valid.
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.unreachable();
    }

    // Match path: bind pattern names into the enclosing scope. No
    // saved/restored locals: these flow forward like a plain `let`.
    ctx.builder.set_current_block(bb_match);
    bind_pattern(ctx, scrutinee, s.pattern, root.hir.DefinitionSiteStatement { value: stmt_id });
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_stmt @ d9be6853b
// `lower_stmt`'s plain `AstStmt::Let` arm. A simple `let x` has one name; a
// chain `let x: let y: let z` has three. The first name owns the declared
// slot (the init writes into it directly); remaining names alias via
// copy-assignment.
function lower_stmt_let(
    ctx: LoweringContext,
    stmt_id: int,
    s: root.ast.StmtLet,
) -> void throws MirInternalError {
    let names = root.ast.pattern_bound_names(ctx.body.patterns[s.pattern], ctx.body.patterns);
    let first_name = names.at(0);

    let local_ty = pat_ty(ctx, s.pattern);
    let site = root.hir.DefinitionSiteStatement { value: stmt_id };
    let local = if (first_name != null) {
        declare_binding(ctx, s.pattern, site, first_name, local_ty)
    } else {
        // A nameless pattern still evaluates its initializer.
        ctx.builder.declare_local(local_ty)
    };

    let value = value_place(ctx, local);
    if let init: int = s.initializer {
        lower_expr(ctx, init, value);
    } else {
        ctx.builder.assign(value, RvalueUse { value: OperandConstant { value: ConstantNull {} } });
    }

    // Additional chain-link bindings get their own locals that copy from the
    // first. `let x: let y` means y = x at runtime.
    for (let extra in names.slice(1, names.length())) {
        let alias = declare_binding(ctx, s.pattern, site, extra, local_ty);
        let alias_value = value_place(ctx, alias);
        let source = value_place(ctx, local);
        ctx.builder.assign(alias_value, RvalueUse { value: OperandCopy { value: source } });
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_stmt @ d9be6853b
// `lower_stmt`'s `AstStmt::While` arm (`while` and C-style `for`).
function lower_stmt_while(
    ctx: LoweringContext,
    s: root.ast.StmtWhile,
) -> void throws MirInternalError {
    let bb_cond = ctx.builder.create_block();
    let bb_body = ctx.builder.create_block();
    let bb_after = if (s.after != null) {
        ctx.builder.create_block()
    } else {
        bb_cond
    };
    let bb_exit = ctx.builder.create_block();

    // A C-style header binding is per-iteration: the closures one iteration
    // makes keep that iteration's value while the step advances the next
    // one's (JS/Go). The header `let` ran once, before the loop; each
    // captured binding it declared is re-celled, carrying its value, at the
    // top of the step: the `continue` target too, so a skipped tail still
    // gets its own cell.
    let per_iteration_cells = match (s.origin) {
        let f: root.ast.LoopOriginFor => captured_locals_of_statement(ctx, f.init),
        root.ast.LoopOriginWhile => [],
    };

    let prev_loop = ctx.loop_context;
    ctx.loop_context
        = LoopContext {
            break_target: bb_exit,
            continue_target: bb_after,
            defer_depth: ctx.defer_stack.length(),
        };

    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_cond);
    }

    ctx.builder.set_current_block(bb_cond);
    if (s.after == null) {
        // No step block: re-cell ahead of the test instead, at the cost of
        // one unused cell before the first test.
        recell_per_iteration(ctx, per_iteration_cells);
    }
    lower_condition(ctx, s.condition, bb_body, bb_exit);

    ctx.builder.set_current_block(bb_body);
    let body_ty = expr_ty(ctx, s.body);
    let body_temp = ctx.builder.declare_local(body_ty);
    lower_expr(ctx, s.body, PlaceLocal { value: body_temp });

    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_after);
    }

    if let after_stmt: int = s.after {
        ctx.builder.set_current_block(bb_after);
        recell_per_iteration(ctx, per_iteration_cells);
        lower_stmt(ctx, after_stmt);
    }

    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_cond);
    }

    ctx.loop_context = prev_loop;
    ctx.builder.set_current_block(bb_exit);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_stmt @ d9be6853b
// `lower_stmt`'s `AstStmt::WhileLet` arm: `while let PATTERN = SCRUTINEE {
// BODY }`, a loop header that re-evaluates the scrutinee and re-tests the
// refutable pattern each iteration. On match: bind + run body + jump back to
// the header. On miss: exit the loop.
function lower_stmt_while_let(
    ctx: LoweringContext,
    stmt_id: int,
    s: root.ast.StmtWhileLet,
) -> void throws MirInternalError {
    let bb_header = ctx.builder.create_block();
    let bb_body = ctx.builder.create_block();
    let bb_exit = ctx.builder.create_block();

    // `continue` re-enters the header (re-evaluates scrutinee + re-tests the
    // pattern); `break` jumps to the exit.
    let prev_loop = ctx.loop_context;
    ctx.loop_context
        = LoopContext {
            break_target: bb_exit,
            continue_target: bb_header,
            defer_depth: ctx.defer_stack.length(),
        };

    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_header);
    }

    // Header: resolve the scrutinee to a local, then run the refutable test
    // (match -> body, miss -> exit). For a bare-path scrutinee this resolves
    // to its OWN local, so a body that mutates that local is observed when
    // the header re-tests it on the next pass; other expressions are
    // re-lowered into a fresh local each pass. Mirrors `lower_if_let`.
    ctx.builder.set_current_block(bb_header);
    let resolved = try_resolve_to_local(ctx, s.scrutinee);
    let scrutinee_local = if (resolved != null) {
        resolved
    } else {
        let op = lower_to_operand(ctx, s.scrutinee);
        let ty = expr_ty(ctx, s.scrutinee);
        operand_to_local(ctx, op, ty)
    };
    lower_pattern_test(ctx, scrutinee_local, s.pattern, bb_body, bb_exit);

    // Body: bind pattern locals (declared per pass, so a captured binding
    // gives each pass's closures their own cell), lower the body (result
    // discarded), then jump back to the header.
    ctx.builder.set_current_block(bb_body);
    bind_pattern(ctx, scrutinee_local, s.pattern, root.hir.DefinitionSiteStatement { value: stmt_id });
    let body_temp = ctx.builder.declare_local(expr_ty(ctx, s.body));
    lower_expr(ctx, s.body, PlaceLocal { value: body_temp });
    if (!ctx.builder.is_current_terminated()) {
        ctx.builder.goto(bb_header);
    }

    // Exit.
    ctx.loop_context = prev_loop;
    ctx.builder.set_current_block(bb_exit);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_stmt @ d9be6853b
// `lower_stmt`'s `AstStmt::Return` arm.
function lower_stmt_return(
    ctx: LoweringContext,
    s: root.ast.StmtReturn,
) -> void throws MirInternalError {
    // _0 is always the return place.
    let ret = 0;
    if let e: int = s.value {
        lower_expr(ctx, e, PlaceLocal { value: ret });
    } else {
        // A bare `return` in a void function returns null; see
        // `AstExpr::Return`.
        ctx.builder.assign(
            PlaceLocal { value: ret },
            RvalueUse { value: OperandConstant { value: ConstantNull {} } },
        );
    }
    // Run all pending defers (LIFO).
    replay_defers_to_depth(ctx, 0);
    ctx.builder.goto(ctx.exit_block);
    // Create a dead successor block for the builder cursor (subsequent
    // statements in the same block-list are dead code). It is unterminated;
    // phase 1 eliminates unreachable blocks.
    let dead = ctx.builder.create_block();
    ctx.builder.set_current_block(dead);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_stmt @ d9be6853b
// `lower_stmt`'s `AstStmt::Missing` arm: a call to `baml.sys.panic`.
function lower_stmt_missing(ctx: LoweringContext) -> void throws never {
    let callee = OperandConstant {
        value: ConstantFunction { value: lang_function(ctx, root.base.LangPackage.Baml, ["sys"], "panic") },
    };
    let msg = OperandConstant { value: ConstantString { value: "missing statement" } };
    let temp = ctx.builder.declare_local(root.types.TyNull {});
    let unreachable_block = ctx.builder.create_block();
    ctx.builder.call_with_type_args(callee, [msg], 0, PlaceLocal { value: temp }, unreachable_block);
    ctx.builder.set_current_block(unreachable_block);
    ctx.builder.unreachable();
    let dead = ctx.builder.create_block();
    ctx.builder.set_current_block(dead);
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::convert_assign_op @ d9be6853b
function convert_assign_op(op: root.ast.AssignOp) -> BinOp throws never {
    match (op) {
        root.ast.AssignOp.Add => BinOp.Add,
        root.ast.AssignOp.Sub => BinOp.Sub,
        root.ast.AssignOp.Mul => BinOp.Mul,
        root.ast.AssignOp.Div => BinOp.Div,
        root.ast.AssignOp.Mod => BinOp.Mod,
        root.ast.AssignOp.BitAnd => BinOp.BitAnd,
        root.ast.AssignOp.BitOr => BinOp.BitOr,
        root.ast.AssignOp.BitXor => BinOp.BitXor,
        root.ast.AssignOp.Shl => BinOp.Shl,
        root.ast.AssignOp.Shr => BinOp.Shr,
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_store_place @ d9be6853b
function lower_store_place(ctx: LoweringContext, expr_id: int) -> Place throws MirInternalError {
    let place = lower_lvalue(ctx, expr_id);
    match (place) {
        let index: PlaceIndex if index.kind == IndexKind.Tuple => {
            throw internal_error(
                ctx,
                "a store to a tuple slot (TIR should have rejected this program)",
                expr_id,
            );
        },
        _ => {},
    }
    place
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_lvalue @ d9be6853b
function lower_lvalue(ctx: LoweringContext, expr_id: int) -> Place throws MirInternalError {
    match (ctx.body.exprs[expr_id]) {
        let e: root.ast.ExprPath if e.value.segments.length() == 1 => {
            let segment = e.value.segments[0];
            place_for_path(ctx, expr_id, segment)
                ?? throw internal_error(
                    ctx,
                    `MIR failed to resolve assignment target \`${segment}\` (TIR should have rejected this program)`,
                    expr_id,
                )
        },
        let e: root.ast.ExprPath if e.value.segments.length() >= 2 => {
            lower_lvalue_path(ctx, expr_id, e.value.segments)
        },
        let e: root.ast.ExprMemberAccess => lower_lvalue_member_access(ctx, e),
        let e: root.ast.ExprIndex => {
            let base_id = e.base;
            let index_id = e.index;
            let base_ty = expr_ty(ctx, base_id);
            let base_op = lower_to_operand(ctx, base_id);
            let base_place = PlaceLocal { value: operand_to_local(ctx, base_op, base_ty) };
            let index_op = lower_to_operand(ctx, index_id);
            let index_ty = expr_ty(ctx, index_id);
            let index_local = operand_to_local(ctx, index_op, index_ty);
            PlaceIndex { base: base_place, index: index_local, kind: index_kind_of(ctx, base_ty) }
        },
        let e: root.ast.ExprOptionalMemberAccess => {
            lower_lvalue_optional_member_access(ctx, expr_id, e)
        },
        let e: root.ast.ExprOptionalIndex => lower_lvalue_optional_index(ctx, expr_id, e),
        _ => {
            let ty = expr_ty(ctx, expr_id);
            let temp = ctx.builder.declare_local(ty);
            // A projection assignment may use an arbitrary expression as its
            // base (`store.require().info.title = ...`). Materialize that
            // base exactly once before projecting through it.
            lower_expr(ctx, expr_id, PlaceLocal { value: temp });
            PlaceLocal { value: temp }
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_lvalue @ d9be6853b
// `lower_lvalue`'s multi-segment path arm: `a.b` or `a.b.c`. Chain field
// projections from the root local or capture.
function lower_lvalue_path(
    ctx: LoweringContext,
    expr_id: int,
    segments: string[],
) -> Place throws MirInternalError {
    let current_place: Place = PlaceLocal { value: 0 };
    let current_ty: root.types.RuntimeTy = root.types.TyUnknown {};
    let root_place = place_for_path(ctx, expr_id, segments[0]);
    if (root_place != null) {
        current_ty
            = match (root_place) {
                let l: PlaceLocal => path_root_ty(ctx, expr_id) ?? ctx.builder.local_ty(l.value),
                let d: PlaceDeref => {
                    match (d.value) {
                        let l: PlaceLocal => {
                            path_root_ty(ctx, expr_id) ?? ctx.builder.local_ty(l.value)
                        },
                        PlaceCapture => {
                            path_root_ty(ctx, expr_id)
                                ?? throw internal_error(
                                ctx,
                                "the checker recorded no type for a captured path root",
                                expr_id,
                            )
                        },
                    }
                },
                _ => baml.sys.panic("path roots are locals or the values in cells"),
            };
        current_place = root_place;
    } else if let root_local: int = load_top_level_let_root(ctx, expr_id) {
        // `g.f = v` on a global: the binding is immutable (the checker
        // refuses `g = v`), but what it holds is an ordinary heap object.
        // Load the global's value and store through it, so the write lands
        // in the shared object every reader sees.
        current_ty = ctx.builder.local_ty(root_local);
        current_place = PlaceLocal { value: root_local };
    } else {
        throw internal_error(
            ctx,
            `MIR failed to resolve the root \`${segments[0]}\` of an assignment target (TIR should have rejected this program)`,
            expr_id,
        );
    }

    for (let seg_idx = 1; seg_idx < segments.length(); seg_idx += 1) {
        let seg = segments[seg_idx];
        let receiver = class_receiver_for_path_prefix(ctx, expr_id, seg_idx - 1, current_ty);
        if (receiver != null) {
            let (let tn, let class_type_args) = receiver;
            let class_ = class_ref_of(ctx, tn);
            let slot = class_field_slot(ctx, class_, seg, class_type_args);
            if (slot != null) {
                current_place = PlaceField { base: current_place, field: slot.0 };
                current_ty = slot.1;
                continue;
            }
            throw internal_error(
                ctx,
                `MIR failed to resolve assignment target .${seg} against class definition '${tn.name}': the class declares no such field`,
                expr_id,
            );
        }
        // TIR rejects `.seg` assignment on every non-class base; see
        // `lower_member_access`.
        throw internal_error(
            ctx,
            `MIR failed to resolve assignment target .${seg} on \`${root.hir_ty.ty_debug(root.types.widen_runtime_ty_to_ty(current_ty))}\`: TIR recorded no resolution for it`,
            expr_id,
        );
    }
    current_place
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_lvalue @ d9be6853b
// `lower_lvalue`'s `AstExpr::MemberAccess` arm.
function lower_lvalue_member_access(
    ctx: LoweringContext,
    e: root.ast.ExprMemberAccess,
) -> Place throws MirInternalError {
    let base_id = e.base;
    let member_name = e.member;
    let base_ty = expr_ty(ctx, base_id);
    let base_op = lower_to_operand(ctx, base_id);
    let base_place = PlaceLocal { value: operand_to_local(ctx, base_op, base_ty) };
    if let class_ty: root.types.RuntimeTyClass = base_ty {
        let class_ = class_ref_of(ctx, class_ty.name);
        if let idx: int = root.hir_ty.class_field_index(ctx.db, root.hir.DeclRefSource { value: class_ }, member_name) {
            return PlaceField { base: base_place, field: idx };
        }
        throw internal_error(
            ctx,
            `MIR failed to resolve member access .${member_name} against class definition '${class_ty.name.name}': the class declares no such field`,
            base_id,
        );
    }
    // TIR rejects `.member` assignment on every other base; see
    // `lower_member_access`.
    throw internal_error(
        ctx,
        `MIR failed to resolve member assignment target .${member_name} on \`${root.hir_ty.ty_debug(root.types.widen_runtime_ty_to_ty(base_ty))}\`: TIR recorded no resolution for it`,
        base_id,
    )
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_lvalue @ d9be6853b
// `lower_lvalue`'s `AstExpr::OptionalMemberAccess` arm.
function lower_lvalue_optional_member_access(
    ctx: LoweringContext,
    expr_id: int,
    e: root.ast.ExprOptionalMemberAccess,
) -> Place throws MirInternalError {
    let base_id = e.base;
    let member_name = e.member;

    // Evaluate base once into a temp local.
    let base_op = lower_to_operand(ctx, base_id);
    let base_ty = expr_ty(ctx, base_id);
    let base_local = operand_to_local(ctx, base_op, base_ty);

    // Null check using the operand.
    let is_null = RvalueBinaryOp {
        op: BinOp.Eq,
        left: OperandCopy { value: PlaceLocal { value: base_local } },
        right: OperandConstant { value: ConstantNull {} },
    };
    let test_local = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(PlaceLocal { value: test_local }, is_null);

    let bb_continue = ctx.builder.create_block();
    let bb_null = ctx.chain_null_exits.at(ctx.chain_null_exits.length() - 1)
        ?? throw internal_error(
            ctx,
            "an optional member access in assignment position outside an optional chain",
            expr_id,
        );
    ctx.builder.branch(
        OperandCopy { value: PlaceLocal { value: test_local } },
        bb_null,
        bb_continue,
    );

    ctx.builder.set_current_block(bb_continue);

    // Project member from the same temp local: no second evaluation.
    let base_place = PlaceLocal { value: base_local };
    // Unwrap Optional: we've already null-checked, so use the inner type.
    let unwrapped_ty = root.types.strip_null_runtime_ty(base_ty);
    if let class_ty: root.types.RuntimeTyClass = unwrapped_ty {
        let class_ = class_ref_of(ctx, class_ty.name);
        if let idx: int = root.hir_ty.class_field_index(ctx.db, root.hir.DeclRefSource { value: class_ }, member_name) {
            return PlaceField { base: base_place, field: idx };
        }
        throw internal_error(
            ctx,
            `MIR failed to resolve optional member access .${member_name} against class definition '${class_ty.name.name}': the class declares no such field`,
            base_id,
        );
    }
    // Dynamic map access.
    let key_local = ctx.builder.declare_local(root.types.TyString {});
    ctx.builder.assign(
        PlaceLocal { value: key_local },
        RvalueUse { value: OperandConstant { value: ConstantString { value: member_name } } },
    );
    PlaceIndex { base: base_place, index: key_local, kind: IndexKind.Map }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_lvalue @ d9be6853b
// `lower_lvalue`'s `AstExpr::OptionalIndex` arm.
function lower_lvalue_optional_index(
    ctx: LoweringContext,
    expr_id: int,
    e: root.ast.ExprOptionalIndex,
) -> Place throws MirInternalError {
    let base_id = e.base;
    let index_id = e.index;

    // Evaluate base once into a temp local.
    let base_op = lower_to_operand(ctx, base_id);
    let base_ty = expr_ty(ctx, base_id);
    let base_local = operand_to_local(ctx, base_op, base_ty);

    // Null check.
    let is_null = RvalueBinaryOp {
        op: BinOp.Eq,
        left: OperandCopy { value: PlaceLocal { value: base_local } },
        right: OperandConstant { value: ConstantNull {} },
    };
    let test_local = ctx.builder.declare_local(root.types.TyBool {});
    ctx.builder.assign(PlaceLocal { value: test_local }, is_null);

    let bb_continue = ctx.builder.create_block();
    let bb_null = ctx.chain_null_exits.at(ctx.chain_null_exits.length() - 1)
        ?? throw internal_error(
            ctx,
            "an optional index in assignment position outside an optional chain",
            expr_id,
        );
    ctx.builder.branch(
        OperandCopy { value: PlaceLocal { value: test_local } },
        bb_null,
        bb_continue,
    );

    ctx.builder.set_current_block(bb_continue);

    // Project index from the same temp local.
    let index_op = lower_to_operand(ctx, index_id);
    let index_ty = expr_ty(ctx, index_id);
    let index_local = operand_to_local(ctx, index_op, index_ty);
    PlaceIndex {
        base: PlaceLocal { value: base_local },
        index: index_local,
        kind: index_kind_of(ctx, base_ty),
    }
}
