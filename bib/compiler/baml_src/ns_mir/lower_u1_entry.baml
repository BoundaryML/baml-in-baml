// port: baml_compiler2_mir/src/lower.rs @ d9be6853b
//
// Unit 1 of the MIR plan, part three: the entry points (the plan's lower.rs
// 15053-15318): `lower_let_body`, `with_bare_global_paths`,
// `lower_function` (memoized per opt level), the call-layout checks, and the
// index-kind helpers. The tests (`indirect_call_layout_tests`) are in
// `lower_u1_test.baml`.
//
// Restructured (BAML forces it):
// - `Result<_, MirInternalError>` is `throws MirInternalError`;
//   `lower_function`'s memo value is `MirFunction | MirInternalError`
//   (db.baml), caught on the way in and rethrown on the way out.
// - `lower_let_body` is Rust's `lower_let_body_impl` (Rust's
//   `lower_let_body` only forwards to it).
// - `mem::take(&mut ctx.pending_lambdas)` keeps the old array and puts a
//   fresh one in its place.

// port: baml_compiler2_mir/src/lower.rs::LoweredLetBody @ d9be6853b
// A `let` initializer's body with the lambdas lowered inside it.
type LoweredLetBody = (MirFunctionBody, MirFunction[]);

// port: baml_compiler2_mir/src/lower.rs::lower_let_body_impl @ d9be6853b
// Also `lower_let_body`. Lower a top-level let binding's initializer into a
// `MirFunctionBody` (arity 0, the initializer expression only), for emit's
// `$init` function. Null is a `let` with no initializer; a throw is an
// internal inconsistency (see `lower_function`).
function lower_let_body(
    db: root.hir.Db,
    let_loc: int,
    opt: OptLevel,
) -> LoweredLetBody? throws MirInternalError {
    let body = root.hir.let_body(db, let_loc);
    let source_map = root.hir.let_body_source_map(db, let_loc);
    match (body) {
        let expr_body: root.hir.LetBodyExpr => {
            let ctx = LoweringContext.new_for_let(db, let_loc, expr_body.value, source_map, opt);
            let mir_body = lower_let_body_inner(ctx);
            let lambdas = ctx.pending_lambdas;
            ctx.pending_lambdas = [];
            check_indirect_call_layouts(mir_body);
            for (let lambda in lambdas) {
                check_function_call_layouts(lambda);
            }
            (mir_body, lambdas)
        },
        root.hir.LetBodyMissing => null,
    }
}

// port: baml_compiler2_mir/src/lower.rs::with_bare_global_paths @ d9be6853b
// `body` with every qualified global path (`root.ns.x.rest`) rewritten to
// the bare form `[x, rest..]`. The checker resolved those paths and recorded
// their ladders root-first, exactly as for a bare global; with the
// qualifiers dropped, every lowering road handles the path as the bare
// global it names. Expression ids, spans and every other node are
// unchanged. Rust rewrites its own clone of the body; the body here is the
// memoized one, so the rewrite goes into a copy of `exprs` (made only when a
// path is rewritten) and a new `ExprBody` around it.
function with_bare_global_paths(
    body: root.ast.ExprBody,
    tables: root.hir_ty.InferenceResult<root.types.Ty>?,
) -> root.ast.ExprBody throws never {
    if (tables == null) {
        return body;
    }
    let exprs: root.ast.Expr[]? = null;
    for (let expr in tables.global_roots.keys()) {
        let segments = tables.global_roots[expr].segments;
        if (segments <= 1) {
            continue;
        }
        let path = match (body.exprs[expr]) {
            let p: root.ast.ExprPath => p.value,
            _ => {
                continue;
            },
        };
        if (path.segments.length() < segments) {
            continue;
        }
        let bare = path.segments.slice(segments - 1, path.segments.length());
        let rewritten = root.base.Path { segments: bare, origin: path.origin };
        let copied = exprs ?? body.exprs.concat([]);
        copied[expr] = root.ast.ExprPath { value: rewritten };
        exprs = copied;
    }
    if (exprs == null) {
        return body;
    }
    root.ast.ExprBody { ...body, exprs: exprs }
}

// port: baml_compiler2_mir/src/lower.rs::check_indirect_call_layouts @ d9be6853b
// An indirect call pushes slots the runtime callee cannot describe, so its
// layout must come from the checked call plan. Only compiler-synthesized
// DIRECT calls go without one; an indirect call without a layout means TIR
// recorded no plan for the call it checked, and emit could only guess what
// the call pushed.
function check_indirect_call_layouts(body: MirFunctionBody) -> void throws MirInternalError {
    for (let block in body.blocks) {
        let call = match (block.terminator) {
            let c: TerminatorCall => c,
            _ => {
                continue;
            },
        };
        let direct = match (call.callee) {
            let c: OperandConstant => c.value is ConstantFunction,
            _ => false,
        };
        if (call.argument_layout == null && !direct) {
            throw MirInternalError {
                message: "MIR lowered an indirect call TIR recorded no call plan for",
                span: block.terminator_span ?? block.span,
            };
        }
    }
}

// port: baml_compiler2_mir/src/lower.rs::check_function_call_layouts @ d9be6853b
function check_function_call_layouts(function_: MirFunction) -> void throws MirInternalError {
    match (function_.kind) {
        let bytecode: MirFunctionKindBytecode => check_indirect_call_layouts(bytecode.value),
        MirFunctionKindBuiltin => {},
    }
    for (let lambda in function_.lambdas) {
        check_function_call_layouts(lambda);
    }
}

// port: baml_compiler2_mir/src/lower.rs::lower_function @ d9be6853b
// Lower one function to MIR, memoized per `(func_loc, opt)`: one memo per
// opt level (`db.mir_memo.lower_function_memo(opt)`). Lowering runs on
// CHECKED programs only, so it cannot fail on a user's account: a throw is
// an internal inconsistency between what the checker recorded and what
// lowering finds. Such a function has no MIR, and the compile fails.
function lower_function(
    db: root.hir.Db,
    func_loc: int,
    opt: OptLevel,
) -> MirFunction throws MirInternalError {
    let lowered = db.mir_memo.lower_function_memo(opt).get(db.cycles, func_loc, () -> {
        lower_function_impl(db, func_loc, opt) catch (e) {
            MirInternalError => e,
        }
    });
    match (lowered) {
        let error: MirInternalError => {
            throw error;
        },
        let function_: MirFunction => function_,
    }
}

// port: baml_compiler2_mir/src/lower.rs::lower_function_impl @ d9be6853b
function lower_function_impl(
    db: root.hir.Db,
    func_loc: int,
    opt: OptLevel,
) -> MirFunction throws MirInternalError {
    let body = root.hir.function_body(db, func_loc);
    let source_map = root.hir.function_body_source_map(db, func_loc);
    let sig = root.hir.function_signature(db, func_loc);
    let arity = sig.params.length();
    match (body) {
        let expr_body: root.hir.FunctionBodyExpr => {
            let ctx = LoweringContext.new(db, func_loc, expr_body.value, source_map, opt);
            let mir = lower_function_body(ctx);
            check_function_call_layouts(mir);
            mir
        },
        let builtin: root.hir.FunctionBodyBuiltin => {
            // For IO builtins (`$rust_io_function`), the compiler injects one
            // synthetic trailing value-arg slot per generic type parameter the
            // call site threads: the function's own generics plus, for a
            // method on a generic class, the enclosing class's (the call path
            // prepends the receiver's class type args). They occupy real
            // operand slots, so `ScheduleFuture` must count them. In lockstep
            // with the builtins codegen's `fn_only_generic_count`.
            let extra_arity = if (builtin.value == root.ast.BuiltinKind.Io) {
                root.hir.function_data(db, func_loc).generic_params.length()
                    + root.hir.enclosing_type_generic_param_count(db, func_loc)
            } else {
                0
            };
            MirFunction {
                arity: arity + extra_arity,
                span: null,
                identity: MirFunctionIdDeclared { value: func_loc },
                kind: MirFunctionKindBuiltin { value: builtin.value },
                lambdas: [],
                signature: null,
            }
        },
        root.hir.FunctionBodyMissing => {
            // The body is a lone `Unreachable`: control never enters it, so
            // no slot of its frame ever holds a value. `never` says exactly
            // that of each of them.
            let block = BasicBlock.new(0);
            block.terminator = TerminatorUnreachable {};
            MirFunction {
                arity: arity,
                span: null,
                identity: MirFunctionIdDeclared { value: func_loc },
                kind: MirFunctionKindBytecode {
                    value: MirFunctionBody {
                        blocks: [block],
                        entry: 0,
                        locals: baml.Array.generate(arity + 1, (_) -> {
                            LocalDecl {
                                name: null,
                                ty: root.types.TyNever {},
                                span: null,
                                scope_span: null,
                                is_captured: false,
                            }
                        }),
                    },
                },
                lambdas: [],
                signature: null,
            }
        },
    }
}

// port: baml_compiler2_mir/src/lower.rs::index_kind_for @ d9be6853b
function index_kind_for(ty: root.types.RuntimeTy) -> IndexKind throws never {
    if (is_tuple_runtime_ty(ty)) {
        IndexKind.Tuple
    } else if (ty is root.types.RuntimeTyList || ty is root.types.TyUint8Array) {
        IndexKind.Array
    } else {
        IndexKind.Map
    }
}

// port: baml_compiler2_mir/src/lower.rs::is_tuple_runtime_ty @ d9be6853b
function is_tuple_runtime_ty(ty: root.types.RuntimeTy) -> bool throws never {
    match (ty) {
        root.types.RuntimeTyTuple => true,
        let u: root.types.RuntimeTyUnion => {
            u.members.length() > 0
                && u.members.every((member) -> {
                    member is root.types.RuntimeTyTuple
                })
        },
        _ => false,
    }
}
