// port: baml_compiler2_hir_ty/src/infer/truthy.rs @ d9be6853b
//
// Truthiness: condition positions coerce any value to `bool` instead of
// requiring one.
//
// The falsy set is uniform and type-agnostic (Python's rule): `false`,
// `null`, `0`, `0n`, `0.0`/`-0.0`, `""`, `[]`, `{}`, and an empty byte
// array. Everything else (including `NaN`, class instances, enum variants,
// functions, and media) is truthy. A condition whose static type decides
// the branch is a warning (a unit condition is one: its only value,
// `null`, is falsy). The reachability pass diagnoses the dead code a
// written constant leaves.
//
// Layering: the checker DECIDES here and records an `Adjust.Truthy`
// adjustment on the condition expression; MIR synthesizes the coercion
// structurally from `expr_adjustments`; the VM's branch opcodes stay
// strict-bool.
//
// Restructured: `truthiness` and `needs_truthy_coercion` take the pool their
// handles index; the `InferenceContext` methods are free functions taking
// `ctx` first.

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::Truthiness @ d9be6853b
// What a value's static type says about its runtime truthiness.
enum Truthiness {
    // Every runtime inhabitant is truthy (an instance, a function, a
    // non-falsy literal).
    AlwaysTruthy,
    // Every runtime inhabitant is falsy (`null`, `false`, `0`, `""`).
    AlwaysFalsy,
    // Decided per value at runtime.
    Runtime,
}

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::truthiness @ d9be6853b
// Truthiness of a RESOLVED type. Conservative: anything open (vars,
// projections, `unknown`) answers `Runtime`.
function truthiness(pool: root.types.InferPool, ty: int) -> Truthiness throws never {
    match (pool.kinds[ty]) {
        root.types.TyNull => Truthiness.AlwaysFalsy,
        let l: root.types.TyLiteral => literal_truthiness(l.value),
        // Runtime-decided scalars and containers: any of them can hold a
        // falsy value.
        root.types.TyBool
            | root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyUint8Array
            | root.types.InferTyList
            | root.types.InferTyMap =>
        {
            Truthiness.Runtime
        },
        // An interface can be implemented by falsy primitives. Its
        // existential value is not necessarily a truthy class instance.
        root.types.InferTyInterface => Truthiness.Runtime,
        // Heap values with no falsy inhabitant.
        root.types.InferTyClass
            | root.types.TyEnum
            | root.types.TyEnumVariant
            | root.types.TyMedia
            | root.types.InferTyFunction
            | root.types.InferTyFuture
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst
            | root.types.TyRustType
            | root.types.InferTyTuple =>
        {
            Truthiness.AlwaysTruthy
        },
        let u: root.types.InferTyUnion => {
            let all_truthy = true;
            let all_falsy = true;
            for (let member in u.members) {
                match (truthiness(pool, member)) {
                    Truthiness.AlwaysTruthy => {
                        all_falsy = false;
                    },
                    Truthiness.AlwaysFalsy => {
                        all_truthy = false;
                    },
                    Truthiness.Runtime => {
                        return Truthiness.Runtime;
                    },
                }
            }
            if (all_truthy && !all_falsy) {
                Truthiness.AlwaysTruthy
            } else if (all_falsy && !all_truthy) {
                Truthiness.AlwaysFalsy
            } else {
                // A union is non-empty; both flags survive only if the union
                // mixes polarities, which the arms above cleared.
                Truthiness.Runtime
            }
        },
        // Open or sentinel types: no static claim.
        root.types.TyUnknown
            | root.types.TyTypeVar
            | root.types.InferTyAssociatedTypeProjection
            | root.types.TyTypeAlias
            | root.types.TyNever
            | root.types.TyError
            | root.types.TyInferVar =>
        {
            Truthiness.Runtime
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::literal_truthiness @ d9be6853b
// Literal truthiness: the zero of each base and the empty string are falsy;
// every other literal is truthy. Float literals carry their SOURCE text, so
// `-0.0` and `0e5` classify by parsed value; a literal that fails to parse
// (unreachable for checked source) stays truthy.
function literal_truthiness(literal: root.base.Literal) -> Truthiness throws never {
    let falsy = match (literal) {
        let l: root.base.LiteralBool => !l.value,
        let l: root.base.LiteralInt => l.value == 0,
        let l: root.base.LiteralBigint => l.value == 0n,
        let l: root.base.LiteralFloat => {
            let parsed = baml.Float.parse(l.value) catch (e) {
                baml.errors.ParseError => null,
            };
            parsed == 0.0
        },
        let l: root.base.LiteralString => l.value == "",
    };
    if (falsy) {
        Truthiness.AlwaysFalsy
    } else {
        Truthiness.AlwaysTruthy
    }
}

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::PendingCondition @ d9be6853b
// A condition or `!` operand whose truthiness decision waits for the
// inference fixpoint.
class PendingCondition {
    expr: int,
    // Written-literal conditions are exempt from the always-constant
    // warning.
    is_literal: bool,
    // Branch conditions record `Adjust.Truthy`; `!` operands do not
    // (`OpCode::Not` coerces itself).
    coerce: bool,
}

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::InferenceContext::uncalled_function_diagnostic @ d9be6853b
// The warning for a function value used as a condition. An exact `name()`
// replacement is proposed only for an expression renderable as a callee,
// and a function that needs no arguments. A static method: no `ctx`.
function uncalled_function_diagnostic(
    body: root.ast.ExprBody,
    expr: int,
    accepts_no_args: bool,
) -> root.hir_ty.TirDiagnostic throws never {
    let name = body.display_expr(expr);
    let callee_shaped = match (body.exprs[expr]) {
        root.ast.ExprPath
            | root.ast.ExprMemberAccess
            | root.ast.ExprGenericApply
            | root.ast.ExprQualifiedPath
            | root.ast.ExprIndex
            | root.ast.ExprCall =>
        {
            true
        },
        _ => false,
    };
    let suggestion = if (accepts_no_args && callee_shaped) {
        `${name}()`
    } else {
        null
    };
    root.hir_ty.TirDiagnostic {
        error: root.hir_ty.TirTypeErrorUncalledFunctionInCondition { name: name, suggestion: suggestion },
        severity: root.hir_ty.DiagnosticSeverity.Warning,
        primary: root.hir_ty.DiagnosticLocationExpr { value: expr },
        related: [],
    }
}

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::InferenceContext::check_condition @ d9be6853b
// Type a branch condition (`if`/`while`/guard) and return what each outcome
// proves: any type is accepted, a non-`bool` records the Truthy adjustment
// for MIR, and a statically-decided branch warns. Inference runs with NO
// expectation: a `bool` expectation would wrongly pin type variables the
// condition is free to leave open under truthiness. Kept although it only
// forwards: it is the agreed entry point other units call.
function check_condition(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    condition: int,
) -> (int, CondFacts) throws never {
    check_truthy_operand(ctx, body, condition, true, TestPosition.Condition)
}

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::InferenceContext::check_truthy_operand @ d9be6853b
// The operand walk behind every tested position: a branch condition, an
// operand of `&&`/`||`, and the operand of `!`. Infer with no expectation,
// bail on error, defer open types to `finish`, decide closed ones. `coerce`
// distinguishes a condition or an `&&`/`||` operand (records
// `Adjust.Truthy`) from a `!` operand (records nothing: `OpCode::Not`
// performs the coercion itself); acceptance and the always-constant warning
// are shared.
function check_truthy_operand(
    ctx: root.hir_ty.InferenceContext,
    body: root.ast.ExprBody,
    operand: int,
    coerce: bool,
    position: TestPosition,
) -> (int, CondFacts) throws never {
    let pool = ctx.table.pool;
    let (let ty, let facts) = infer_test(ctx, body, operand, position);
    let resolved = ctx.table.resolve_completely(ty);
    if (pool.has_error(resolved)) {
        return (ty, facts);
    }
    let is_literal = match (body.exprs[operand]) {
        root.ast.ExprLiteral | root.ast.ExprNull => true,
        _ => false,
    };
    if (pool.has_infer(resolved)) {
        // The type is still open (a generic call's var solves at the
        // fixpoint): defer the decision to `finish`, where the FINAL type is
        // known.
        ctx.pending_truthy_conditions.push(
            PendingCondition { expr: operand, is_literal: is_literal, coerce: coerce },
        );
        return (ty, facts);
    }
    if (needs_truthy_coercion(pool, resolved)) {
        if (coerce) {
            ctx.result.expr_adjustments[operand]
                = [
                    root.hir_ty.Adjustment {
                        kind: root.hir_ty.Adjust.Truthy,
                        target: pool.add(root.types.TyBool {}),
                    },
                ];
        }
        push_always_const_warning(ctx, operand, resolved, is_literal);
    }
    (ty, facts)
}

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::InferenceContext::decide_deferred_conditions @ d9be6853b
// The deferred half of `check_truthy_operand`: conditions whose type was
// still open at check time decide here on the finalized `type_of_expr`
// entry. Runs in `finish` after type finalization, writing into the SAME
// tables the eager path writes (`result` is already taken from
// `ctx.result` at that point).
function decide_deferred_conditions(
    ctx: root.hir_ty.InferenceContext,
    result: root.hir_ty.InferenceResult<int>,
) -> void throws never {
    let pool = ctx.table.pool;
    let pending = ctx.pending_truthy_conditions;
    ctx.pending_truthy_conditions = [];
    for (let condition in pending) {
        let resolved = result.type_of_expr.get(condition.expr);
        if (resolved == null || pool.has_error(resolved) || pool.has_infer(resolved)) {
            continue;
        }
        if (needs_truthy_coercion(pool, resolved)) {
            // A `!` operand (`coerce: false`) records nothing: `OpCode::Not`
            // coerces itself. It still owes the warning.
            if (condition.coerce) {
                result.expr_adjustments[condition.expr]
                    = [
                        root.hir_ty.Adjustment {
                            kind: root.hir_ty.Adjust.Truthy,
                            target: pool.add(root.types.TyBool {}),
                        },
                    ];
            }
            push_always_const_warning(ctx, condition.expr, resolved, condition.is_literal);
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::InferenceContext::needs_truthy_coercion @ d9be6853b
// The shared judgment: an already-boolean condition (including `never`,
// which produces no value to coerce) branches as it is; every other value
// is coerced. A static method: no `ctx`.
function needs_truthy_coercion(pool: root.types.InferPool, resolved: int) -> bool throws never {
    match (pool.kinds[resolved]) {
        root.types.TyBool | root.types.TyNever => false,
        let l: root.types.TyLiteral => !(l.value is root.base.LiteralBool),
        _ => true,
    }
}

// port: baml_compiler2_hir_ty/src/infer/truthy.rs::InferenceContext::push_always_const_warning @ d9be6853b
// A statically-decided NON-literal condition is a likely bug (`if
// (some_fn)`, `if (instance)`); a written literal is the author's
// deliberate constant.
function push_always_const_warning(
    ctx: root.hir_ty.InferenceContext,
    condition: int,
    resolved: int,
    is_literal: bool,
) -> void throws never {
    if (is_literal) {
        return;
    }
    let always_true = match (truthiness(ctx.table.pool, resolved)) {
        Truthiness.AlwaysTruthy => true,
        Truthiness.AlwaysFalsy => false,
        Truthiness.Runtime => {
            return;
        },
    };
    root.hir_ty.report(
        ctx,
        root.hir_ty.PendingDiagConditionAlwaysConst {
            expr: condition,
            ty: resolved,
            always_true: always_true,
        },
    );
}
