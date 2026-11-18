// port: baml_compiler2_hir_ty/src/infer/obligations.rs @ d9be6853b
//
// The obligation system: rust-analyzer's fulfillment semantics over BAML's
// facts.
//
// - An obligation REGISTERS during the walk when a decision needs
//   information inference has not produced yet (an operator on a
//   still-unsolved generic, a call-site bound on an argument variable).
//   Registration never fails and never guesses.
// - Discharge runs at `finish`, INTERLEAVED with bound resolution to
//   fixpoint: each round resolves what the ground bounds determine, then
//   attempts every pending obligation. An attempt with live variables
//   STALLS (retried next round, never an early failure); a ground attempt
//   succeeds (possibly unifying its output variable, which is what
//   un-stalls other work) or definitively fails (a reported diagnostic, the
//   output erased).
// - After fixpoint, still-stalled obligations fail CLOSED: their outputs
//   erase through the ordinary finalize rules, and a goal that stalled
//   because SEVERAL candidates proved it reports that ambiguity
//   (`settle_stalled_obligations`). Each stall records which of the two it
//   was (`Stall`).
//
// The interleave exists because of a real deadlock: an operator
// obligation's output can be a LOWER BOUND of the very variable its operand
// waits on. Bound resolution therefore decides from the GROUND SUBSET of a
// class's bounds, deferring variable-carrying bounds to post-hoc
// verification.
//
// This file holds the types and the pure helpers; the `InferenceContext`
// methods are stubbed in `infer_stubs_u2.baml` (namespace `hir_ty.infer`)
// until ported. Interned types are `int`s, `InferInterface` is
// `root.types.InferInterfaceConstraint`.

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::GoalPurpose @ d9be6853b
// Why a type must implement an interface, which decides what proves it.
//
// `TYPE_SYSTEM.md` derives subtyping FROM implements (a concrete `C <: I`
// exactly when `C` implements `I`), and the arrow never runs backwards. A
// goal that licenses dispatch on a TYPE is answered by the implements
// relation, which is nominal: an impl row exists or it fails, so `never`
// implements nothing it has no impl for. A goal that asks whether a VALUE
// may be used through the interface is answered by subtyping, where `never`
// holds vacuously and a union holds when every member does.
enum GoalPurpose {
    // A value used through the interface: flowing into an existential,
    // iterated, or the receiver a method call dispatches on. Dispatch is
    // keyed by the value at run time, so this is value inhabitation.
    Coercion,
    // A declared bound on a generic param (a function's or class's own, or
    // an impl header's, replayed when the impl is selected). Code under the
    // bound may dispatch on the TYPE (`(T as I).make()`), so it is nominal,
    // and the argument must be concrete (E0001): an abstract type has no
    // single runtime type to dispatch on, and no impl makes an existential
    // an implementor. The impl header is no exception, and the ground
    // resolver already rejects the candidate there, so selection must too or
    // the two disagree.
    Bound,
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::Obligation @ d9be6853b
// One registered obligation.
type Obligation = ObligationImplements | ObligationOperator;

// `ty` must implement `interface_`. There is no output to bind, but
// selection unifies the goal against the one impl (or bound) that proves
// it, which is how a goal's open args and pins solve. A failure reports the
// nominal does-not-implement diagnostic at `at`.
class ObligationImplements {
    ty: int,
    interface_: root.types.InferInterfaceConstraint,
    at: int,
    purpose: GoalPurpose,
    // The goals whose confirmed impls required this one, the program's own
    // goal first; empty for a goal the program asked directly. A report
    // names the goal that failed and notes each of these, so a bound
    // replayed from an impl header is tied back to what the program wrote
    // (rustc's `ImplDerivedObligation`). Its length is how many impl headers
    // were confirmed to reach this goal, and the budget that stops a
    // self-satisfying impl from registering its own bounds forever (see
    // `attempt`).
    required_for: RequiredFor[],
}

// `lhs <op-interface> rhs` deferred: discharge re-runs the SAME ground
// operator dispatch (union distribution, literal widening, carried bounds
// included) and unifies `out` with its result.
class ObligationOperator {
    interface_: string,
    lhs: int,
    rhs: int?,
    out: int,
    // The registering expression: the no-impl diagnostic's anchor.
    at: int,
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::Obligation::implements @ d9be6853b
// A goal the program asks directly: `ty` must implement `interface_` for
// `purpose`, reported at `at`.
function obligation_implements(
    ty: int,
    interface_: root.types.InferInterfaceConstraint,
    at: int,
    purpose: GoalPurpose,
) -> Obligation throws never {
    ObligationImplements {
        ty: ty,
        interface_: interface_,
        at: at,
        purpose: purpose,
        required_for: [],
    }
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::RequiredFor @ d9be6853b
// A goal that confirming an impl for it made another goal of: the impl's
// bounds had to hold for `subject` to implement `interface_`.
class RequiredFor {
    // As the goal spelled it.
    subject: int,
    interface_: root.types.InferInterfaceConstraint,
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::instantiate_interface @ d9be6853b
// An impl's interface reference (its own, or one of its bounds) at a
// confirmation's `instantiation` of the impl's params.
// Restructured: takes the pool the handles index.
function instantiate_interface(
    pool: root.types.InferPool,
    interface_: root.types.ClosedInterface,
    instantiation: map<root.types.ParamTy, int>,
) -> root.types.InferInterfaceConstraint throws never {
    let reference = interface_.reference;
    root.types.infer_interface_new(
        reference.name,
        reference.generics.map((ty) -> {
            pool.substitute_bindings(ty, instantiation)
        }),
        reference.associated_types.map((binding) -> {
            root.types.InferAssociatedType {
                name: binding.name,
                ty: pool.substitute_bindings(binding.ty, instantiation),
            }
        }),
    )
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::is_abstract_head @ d9be6853b
// Whether a bound must refuse `head` before consulting any implementation:
// the type is not one concrete type, because it spans several runtime types
// (a union, an existential, `unknown`), none (`never`), or is a literal
// type, a subset of a concrete type rather than one: its values use the
// base type's members, but it is never a bound's type argument (the
// runtime's `bound_admits` judges a host's or a `let type`'s argument by
// the same rule).
function is_abstract_head(head: root.types.InferTy) -> bool throws never {
    match (head) {
        root.types.InferTyUnion
            | root.types.InferTyInterface
            | root.types.TyUnknown
            | root.types.TyNever
            | root.types.TyLiteral
            | root.types.TyEnumVariant =>
        {
            true
        },
        root.types.TyInt
            | root.types.TyBigint
            | root.types.TyFloat
            | root.types.TyString
            | root.types.TyBool
            | root.types.TyNull
            | root.types.TyUint8Array
            | root.types.TyMedia
            | root.types.InferTyClass
            | root.types.TyEnum
            | root.types.InferTyList
            | root.types.InferTyTuple
            | root.types.InferTyMap
            | root.types.InferTyFunction
            | root.types.InferTyFuture
            | root.types.TyType
            | root.types.TyResource
            | root.types.TyPromptAst
            | root.types.TyRustType =>
        {
            false
        },
        // Symbolic: concreteness is the variable's own bound, which
        // caller-bound selection proves.
        root.types.TyTypeVar | root.types.InferTyAssociatedTypeProjection => false,
        // Not decided here: an open variable stalls, an alias head is
        // expanded before this is asked, and an error was reported already.
        root.types.TyInferVar | root.types.TyTypeAlias | root.types.TyError => false,
    }
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::Attempt @ d9be6853b
type Attempt = AttemptStalled | AttemptDone;

// Undecided this round: retry next.
class AttemptStalled {
    value: Stall,
}

// Discharged (successfully or with a recorded failure).
class AttemptDone {
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::Stall @ d9be6853b
// Why an attempt could not decide its goal, and so, at quiescence, which
// diagnostic owns it.
enum Stall {
    // Part of the goal is still unsolved: the subject is a variable, a union
    // has not closed, a projection's base has not resolved, or a conditional
    // default needs resolved components. This is not candidate ambiguity;
    // the diagnostics for an undetermined type own it.
    Unresolved,
    // The goal is decidable and MORE THAN ONE candidate decides it. More
    // solving may still prune the set, so it retries; if nothing does, it is
    // rustc's E0283 ("type annotations needed").
    Ambiguous,
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::Pending @ d9be6853b
// A registered obligation and what its last attempt learned about it.
class Pending {
    obligation: Obligation,
    // Why the last attempt left it pending, or null before its first.
    // Settling treats null as undecided rather than ambiguous: a goal
    // registered after the fixpoint's last round was never asked, so
    // nothing observed more than one candidate for it.
    stall: Stall?,
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InterfaceInstantiation @ d9be6853b
// The generic arguments and associated-type pins of one interface
// instantiation.
class InterfaceInstantiation {
    args: int[],
    pins: (string, int)[],
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::ConfirmedImpl @ d9be6853b
// The one impl selection confirmed, with the instantiation of its own
// parameters that confirms it.
type ConfirmedImpl = (root.hir_ty.ImplFacts, map<root.types.ParamTy, int>);

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::Selection @ d9be6853b
// The outcome of candidate selection for a goal whose subject is known.
enum Selection {
    // Exactly one candidate applied, and confirming it committed its
    // unifications.
    Confirmed,
    // Several candidates apply; more solving may prune them.
    Ambiguous,
    // A conditional default needs the subject's remaining variables
    // resolved.
    Unresolved,
    // No candidate can apply, whatever the goal's open variables become.
    NoCandidate,
}
