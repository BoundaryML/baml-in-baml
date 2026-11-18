// port: baml_compiler2_ast/src/cleanup_guard.rs @ d9be6853b
//
// BEP-042 `cleanup` magic-method recognition and run-once guard injection.
// A class method `function cleanup(self) -> void { ... }` is its finalizer: it
// runs at most once per instance, called explicitly, via `defer`, or by the
// GC. The guarantee is a compile-time guard around the user body, which
// rewrites `{ <body> }` into
// `{ if (!baml._cleanup_begin(self)) { return; } { <body> } }`.
// `baml._cleanup_begin` test-and-sets the instance's latch and is true only
// the first time. The guard is an early return rather than an `if` around
// the body, so the user's body stays the function's value.

// port: baml_compiler2_ast/src/cleanup_guard.rs::reads_as_finalizer @ d9be6853b
// Whether `func` reads as a class's finalizer: named `cleanup`, taking
// `self` alone. Whether it *is* one is decided on its checked signature; a
// guarded method that turns out malformed is an error (E0144).
function reads_as_finalizer(func: FunctionDef) -> bool throws never {
    func.name == CLEANUP_METHOD && func.params.length() == 1 && func.params[0].name == "self"
}

// port: baml_compiler2_ast/src/cleanup_guard.rs::maybe_inject_cleanup_guard @ d9be6853b
// Wrap the body of a class's magic `cleanup` method in the run-once guard; a
// no-op for classes without one. A pure AST transform during lowering, so
// the guard is type-checked by the normal pipeline.
function maybe_inject_cleanup_guard(class_def: ClassDef) -> void throws never {
    for (let method in class_def.methods) {
        if (!reads_as_finalizer(method)) {
            continue;
        }
        // A `$rust_function` cleanup (builtin body) has nothing to guard, and an
        // empty body has no root; skip rather than fabricate a body.
        let fn_body = method.body;
        if (!(fn_body is FunctionBodyDefExpr)) {
            continue;
        }
        let orig_root = fn_body.v0.root_expr;
        if (orig_root == null) {
            continue;
        }
        fn_body.v0.root_expr
            = inject_cleanup_guard(fn_body.v0, fn_body.v1, method.name_span, orig_root);
    }
}

// The guard's nodes, allocated into the body's arenas with the source map's
// span arenas kept index-aligned. Every synthesized node carries the
// method-name span and is marked compiler-generated. Returns the new root.
// (Inline in the Rust loop.)
function inject_cleanup_guard(
    body: ExprBody,
    source_map: AstSourceMap,
    span: root.syntax.TextRange,
    orig_root: int,
) -> int throws never {
    let expr = (e: Expr) -> int {
        let id = body.exprs.push(e) - 1;
        source_map.expr_spans.push(span);
        source_map.synthetic_exprs.set(id, true);
        id
    };
    let stmt = (s: Stmt) -> int {
        let id = body.stmts.push(s) - 1;
        source_map.stmt_spans.push(span);
        source_map.synthetic_stmts.set(id, true);
        id
    };
    // `baml._cleanup_begin`, named by identity: nothing in the guarded body's
    // scope can shadow it.
    let callee = expr(ExprPath { value: root.base.Path.compiler(["baml", "_cleanup_begin"]) });
    let self_arg = expr(ExprPath { value: root.base.Path.new(["self"]) });
    let first_call = expr(ExprCall { callee: callee, type_args: [], args: [CallArg.positional(self_arg)] });
    let already_ran = expr(ExprUnary { op: UnaryOp.Not, expr: first_call });
    let bail = stmt(StmtReturn { value: null });
    let bail_block = expr(ExprBlock { stmts: [bail], tail_expr: null });
    let guard = expr(ExprIf { condition: already_ran, then_branch: bail_block, else_branch: null });
    let guard_stmt = stmt(StmtExpr { value: guard });
    expr(ExprBlock { stmts: [guard_stmt], tail_expr: orig_root })
}

// needs foundation: baml_base/src/lib.rs::CLEANUP_METHOD. The reserved
// magic-method name for the BEP-042 finalizer.
const CLEANUP_METHOD: string = "cleanup";
