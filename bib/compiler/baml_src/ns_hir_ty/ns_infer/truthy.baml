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
// This file holds the types and the pure classifiers; the `InferenceContext`
// methods are stubbed in `infer_stubs_u2.baml` (namespace `hir_ty.infer`)
// until ported.
// Restructured: `truthiness` takes the pool its handle indexes.

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
