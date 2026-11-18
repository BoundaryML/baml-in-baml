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
// Restructured (BAML forces it): the `InferenceContext` methods are free
// functions taking `ctx` first; interned types are `int`s, `InferInterface`
// is `root.types.InferInterfaceConstraint`; an `FxHashSet<InferVar>` is a
// `map<int, bool>`; Rust's `Result<Option<ConfirmedImpl>, Selection>` is
// `ConfirmedImpl? | Selection`; a debug-assert that a unique candidate
// re-confirms keeps the confirming call and drops the assert.

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

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::has_structure_operator @ d9be6853b
// Search bounds without solving them: whether a pending operator
// obligation's output is `ty`'s class, or one its bounds reach. A structure
// demand must not commit sibling variables merely because they share a
// bound with it.
function has_structure_operator(
    ctx: root.hir_ty.InferenceContext,
    ty: int,
    visiting: map<int, bool>,
) -> bool throws never {
    let table = ctx.table;
    let pool = table.pool;
    let resolved = table.resolve_completely(ty);
    let var = match (pool.kinds[resolved]) {
        let v: root.types.TyInferVar => v.var,
        _ => {
            return false;
        },
    };
    let root_var = table.unsolved_root_var(var)
        ?? baml.sys.panic("resolve_completely leaves only unsolved variables");
    if (visiting.has(root_var)) {
        return false;
    }
    visiting[root_var] = true;
    let produced = ctx.journals.obligations.some((pending) -> {
        match (pending.obligation) {
            let operator: ObligationOperator => {
                let out = table.resolve_completely(operator.out);
                match (pool.kinds[out]) {
                    let v: root.types.TyInferVar => table.unsolved_root_var(v.var) == root_var,
                    _ => false,
                }
            },
            ObligationImplements => false,
        }
    });
    if (produced) {
        return true;
    }
    let bounds = table.var_bounds(root_var);
    bounds.lowers.concat(bounds.uppers).some((bound) -> {
        has_structure_operator(ctx, bound.ty, visiting)
    })
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::resolve_structure_operand @ d9be6853b
// A structure demand can depend on pending arithmetic
// (`(values.reduce((a, b) -> { a + b }, 0) * 1.0).round()`). Resolve only
// that operator's dependencies from their current bounds; unrelated
// obligations keep waiting for the finish fixpoint. The obligation stays
// registered so finish still reports failures.
function resolve_structure_operand(
    ctx: root.hir_ty.InferenceContext,
    ty: int,
    visiting: map<int, bool>,
) -> int throws never {
    let table = ctx.table;
    let pool = table.pool;
    let resolved = table.resolve_completely(ty);
    let first = match (pool.kinds[resolved]) {
        let v: root.types.TyInferVar => v.var,
        _ => {
            return resolved;
        },
    };
    let var = table.unsolved_root_var(first)
        ?? baml.sys.panic("resolve_completely leaves only unsolved variables");
    if (visiting.has(var)) {
        return resolved;
    }
    visiting[var] = true;
    let bounds = table.var_bounds(var);
    // Generic passthrough calls may put bounded variables between the
    // receiver and its producer. Demand those dependencies before committing
    // their aliases; the root guard breaks cycles such as a reduce
    // accumulator bounded by its own callback output.
    for (let bound in bounds.lowers.concat(bounds.uppers)) {
        if (has_structure_operator(ctx, bound.ty, {})) {
            resolve_structure_operand(ctx, bound.ty, visiting);
        }
    }
    root.hir_ty.try_solve_bounded_var(ctx, var, table.var_bounds(var));
    resolved = table.resolve_completely(resolved);
    let solved = match (pool.kinds[resolved]) {
        let v: root.types.TyInferVar => v.var,
        _ => {
            return resolved;
        },
    };
    // Solving can alias the demanded variable to an operator output without
    // grounding either. Compare union-find roots, not the original spellings,
    // and keep following the producer.
    let root_var = table.unsolved_root_var(solved)
        ?? baml.sys.panic("resolve_completely leaves only unsolved variables");
    let operator: ObligationOperator? = null;
    for (let pending in ctx.journals.obligations) {
        if let candidate: ObligationOperator = pending.obligation {
            let out = table.resolve_completely(candidate.out);
            if let v: root.types.TyInferVar = pool.kinds[out] {
                if (table.unsolved_root_var(v.var) == root_var) {
                    operator = candidate;
                    break;
                }
            }
        }
    }
    if (operator != null) {
        let lhs = resolve_structure_operand(ctx, operator.lhs, visiting);
        let operator_rhs = operator.rhs;
        let rhs = if (operator_rhs != null) {
            resolve_structure_operand(ctx, operator_rhs, visiting)
        } else {
            null
        };
        if (!pool.has_infer(lhs) && !(rhs != null && pool.has_infer(rhs))) {
            let result = root.hir_ty.dispatch_operator(ctx, operator.interface_, lhs, rhs);
            table.unify(resolved, result) catch (e) {
                UnifyError => {},
            };
        }
    }
    table.resolve_completely(resolved)
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::register_obligation @ d9be6853b
function register_obligation(
    ctx: root.hir_ty.InferenceContext,
    obligation: Obligation,
) -> void throws never {
    ctx.journals.obligations.push(Pending { obligation: obligation, stall: null });
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::discharge_obligations_once @ d9be6853b
// One discharge round over every pending obligation. Returns whether
// anything discharged (progress for the fixpoint driver).
function discharge_obligations_once(ctx: root.hir_ty.InferenceContext) -> bool throws never {
    let pending = ctx.journals.obligations;
    ctx.journals.obligations = [];
    let progressed = false;
    for (let entry in pending) {
        match (attempt(ctx, entry.obligation)) {
            AttemptDone => {
                progressed = true;
            },
            let stalled: AttemptStalled => {
                ctx.journals.obligations.push(
                    Pending { obligation: entry.obligation, stall: stalled.value },
                );
            },
        }
    }
    progressed
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::attempt @ d9be6853b
// One attempt at an obligation: an Implements goal is judged (ground) or
// selected (variable-bearing); an operator re-runs the ground dispatch once
// its operands resolve and unifies its output with the result.
function attempt(
    ctx: root.hir_ty.InferenceContext,
    obligation: Obligation,
) -> Attempt throws never {
    let pool = ctx.table.pool;
    match (obligation) {
        let goal: ObligationImplements => {
            let at = goal.at;
            let purpose = goal.purpose;
            let required_for = goal.required_for;
            let subject = ctx.table.resolve_completely(goal.ty);
            let interface_ = resolve_interface_ref(ctx, goal.interface_);
            if (pool.has_error(subject)) {
                return AttemptDone {};
            }
            // An alias is a spelling device and a literal implements what
            // its base primitive does, so the goal is JUDGED for the type the
            // alias denotes, widened; a report names the type as written.
            let written = root.hir_ty.expand_alias_head(ctx.table.pool, subject, ctx.facts);
            // A bound judges its argument as written: a fresh literal widens
            // to its base and is one concrete type, while a literal type
            // written as the argument stays a literal, which
            // `is_abstract_head` refuses. The implements verdict below judges
            // every literal by its base.
            let bound_subject = root.hir_ty.widen_fresh_literal(pool, written);
            let ty = widen_literal(pool, written);
            // One spelling, one verdict: resolution can ground a syntactic
            // union after this obligation registered, and the canonical form
            // may be a single member. An OPEN union may still collapse, so
            // only a coercion (which needs every member either way) acts on
            // it before it closes.
            if (pool.kinds[ty] is root.types.InferTyUnion) {
                if (!pool.has_infer(ty)) {
                    // The canonical form of a recursive alias's unfolding is
                    // the alias again.
                    ty = root.hir_ty.canonicalize_unions(ctx, root.types.ClosedTy { ty: ty }).ty;
                    ty = root.hir_ty.expand_alias_head(ctx.table.pool, ty, ctx.facts);
                } else if (purpose != GoalPurpose.Coercion) {
                    return AttemptStalled { value: Stall.Unresolved };
                }
            }
            // The bound's subject is judged canonically too: a type is its
            // value set, so `true | false` written as a type argument is
            // `bool`. Only a union still a union once canonical, or a literal
            // written alone, is abstract.
            if (pool.kinds[bound_subject] is root.types.InferTyUnion && !pool.has_infer(bound_subject)) {
                bound_subject
                    = root.hir_ty
                        .canonicalize_unions(ctx, root.types.ClosedTy { ty: bound_subject })
                        .ty;
                bound_subject = root.hir_ty.expand_alias_head(ctx.table.pool, bound_subject, ctx.facts);
            }
            if (purpose == GoalPurpose.Coercion) {
                match (pool.kinds[ty]) {
                    // `never` inhabits every type.
                    root.types.TyNever => {
                        return AttemptDone {};
                    },
                    // A union value is used through the interface by
                    // whichever member it holds, so every member must
                    // implement it.
                    let u: root.types.InferTyUnion => {
                        for (let member in u.members) {
                            register_obligation(
                                ctx,
                                ObligationImplements {
                                    ty: member,
                                    interface_: interface_,
                                    at: at,
                                    purpose: purpose,
                                    required_for: required_for,
                                },
                            );
                        }
                        return AttemptDone {};
                    },
                    _ => {},
                }
            }
            // An abstract argument has no single runtime type to dispatch on
            // (E0001), whatever its args become. Checked before the shared
            // verdict, whose existential arm answers by the existential's own
            // reference: right for a coercion, never for a bound.
            if (
                purpose == GoalPurpose.Bound
                    && is_abstract_head(pool.kinds[bound_subject])
                    && !root.hir_ty.is_structural_interface(ctx.db, interface_)
                    && root.hir_ty.conditional_structural_verdict(ctx.db, ctx.facts, ty, interface_)
                        != true
            ) {
                // Named as the user wrote it: the judgment widened.
                root.hir_ty.report(
                    ctx,
                    root.hir_ty.PendingDiagBoundedArgNotConcrete {
                        expr: at,
                        arg: subject,
                        bound: interface_,
                        required_for: required_for,
                    },
                );
                return AttemptDone {};
            }
            if (!pool.has_infer(ty) && !interface_has_infer(pool, interface_)) {
                // Every purpose shares the verdict: past `never` and unions,
                // a value inhabits an existential exactly when its type
                // implements it.
                let judged = root.hir_ty.canonicalize_unions(ctx, root.types.ClosedTy { ty: ty }).ty;
                if (!implements_holds(ctx, judged, interface_)) {
                    report_not_implemented(ctx, at, subject, interface_, required_for);
                }
                return AttemptDone {};
            }
            // The ground resolver bounds the same recursion with
            // `BLANKET_IMPL_BOUND_DEPTH`. Each round instantiates the impl
            // header with FRESH variables, so a self-satisfying impl never
            // re-registers an EQUAL goal: it grows one, and only the budget
            // stops it.
            if (required_for.length() > root.hir_ty.BLANKET_IMPL_BOUND_DEPTH) {
                report_not_implemented(ctx, at, subject, interface_, required_for);
                return AttemptDone {};
            }
            let selection = match (pool.kinds[ty]) {
                // Nothing filters the candidate set yet: a head still
                // unknown, or a projection whose base has not resolved.
                root.types.TyInferVar | root.types.InferTyAssociatedTypeProjection => {
                    return AttemptStalled { value: Stall.Unresolved };
                },
                // Object candidates: an existential subject proves the goal
                // from its OWN reference plus its `requires` closure.
                root.types.InferTyInterface => select_object(ctx, ty, interface_),
                // Caller-bound candidates: a rigid var proves the goal from
                // the bounds it carries.
                root.types.TyTypeVar => select_param_env(ctx, ty, interface_),
                // Every other head is known, and filters the impls. A
                // (closed) union finds none: no impl subject is a union.
                _ => select_impl(ctx, ty, subject, interface_, at, required_for),
            };
            match (selection) {
                Selection.Confirmed => AttemptDone {},
                Selection.Ambiguous => AttemptStalled { value: Stall.Ambiguous },
                Selection.Unresolved => AttemptStalled { value: Stall.Unresolved },
                Selection.NoCandidate => {
                    report_not_implemented(ctx, at, subject, interface_, required_for);
                    AttemptDone {}
                },
            }
        },
        let operator: ObligationOperator => {
            let lhs = ctx.table.resolve_completely(operator.lhs);
            let operator_rhs = operator.rhs;
            let rhs = if (operator_rhs != null) {
                ctx.table.resolve_completely(operator_rhs)
            } else {
                null
            };
            if (pool.has_infer(lhs) || (rhs != null && pool.has_infer(rhs))) {
                return AttemptStalled { value: Stall.Unresolved };
            }
            let result = root.hir_ty.dispatch_operator(ctx, operator.interface_, lhs, rhs);
            if (pool.has_error(result)) {
                root.hir_ty.report_operator_failure(ctx, operator.at, operator.interface_, lhs, rhs);
            }
            ctx.table.unify(operator.out, result) catch (e) {
                UnifyError => {},
            };
            AttemptDone {}
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::select_impl @ d9be6853b
// rustc's impl SELECTION for a variable-bearing goal: every candidate is
// tried under a snapshot and rolled back; EXACTLY ONE applying confirms it
// (the header unification commits, constraining the goal's variables), and
// its bounds become nested obligations. Several is genuine ambiguity,
// retried and reported at quiescence if it never resolves. Committing on
// uniqueness is sound because coherence guarantees at most one impl per
// realized instance.
function select_impl(
    ctx: root.hir_ty.InferenceContext,
    goal: int,
    subject: int,
    interface_: root.types.InferInterfaceConstraint,
    at: int,
    required_for: RequiredFor[],
) -> Selection throws never {
    let (let facts, let instantiation) = match (confirm_unique_impl(ctx, goal, subject, interface_)) {
        let selection: Selection => {
            return selection;
        },
        null => {
            return Selection.Confirmed;
        },
        let confirmed: ConfirmedImpl => confirmed,
    };
    let nested = required_for.concat([RequiredFor { subject: subject, interface_: interface_ }]);
    register_impl_bound_obligations(ctx, facts, instantiation, at, nested);
    Selection.Confirmed
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_unique_impl @ d9be6853b
// The candidate half of `select_impl`: the unique impl whose header applies
// to `goal`, confirmed (its header unifications committed) with the
// instantiation that confirms it; null when a structural default proves
// the goal with no impl; otherwise the selection no single impl decides.
// The confirmed impl's own bounds are the caller's to register.
// Restructured: Rust's `Result<T, E>` is the union `T | E` (an enum `E`
// cannot be thrown from a stub without an extraneous-throws warning).
function confirm_unique_impl(
    ctx: root.hir_ty.InferenceContext,
    goal: int,
    subject: int,
    interface_: root.types.InferInterfaceConstraint,
) -> ConfirmedImpl? | Selection throws never {
    let pool = ctx.table.pool;
    let candidates = root.hir_ty.impl_candidates(ctx.db, goal, interface_.name);
    let applicable: root.hir_ty.ImplFacts? = null;
    for (let facts in candidates) {
        let probe = root.hir_ty.probe(ctx);
        let applies = confirm_impl(ctx, goal, interface_, facts) != null;
        root.hir_ty.rollback_probe(ctx, probe);
        if (applies) {
            if (applicable != null) {
                return Selection.Ambiguous;
            }
            applicable = facts;
        }
    }
    if (applicable == null) {
        if (root.hir_ty.is_structural_interface(ctx.db, interface_)) {
            return null;
        }
        match (root.hir_ty.structural_interface(ctx.db, interface_.name)) {
            root.types.StructuralInterface.Hash => {
                if (pool.has_infer(goal) || interface_has_infer(pool, interface_)) {
                    return Selection.Unresolved;
                }
                if (root.hir_ty.hash_eligible(ctx.db, ctx.facts, subject, interface_)) {
                    return null;
                }
            },
            root.types.StructuralInterface.Compare
                if pool.kinds[subject] is root.types.InferTyTuple => {
                if (pool.has_infer(goal) || interface_has_infer(pool, interface_)) {
                    return Selection.Unresolved;
                }
                if (root.hir_ty.derived_tuple_compare(ctx.db, ctx.facts, subject, interface_) == true) {
                    return null;
                }
            },
            _ => {},
        }
        return Selection.NoCandidate;
    }
    let instantiation = confirm_impl(ctx, goal, interface_, applicable)
        ?? baml.sys.panic("the unique applicable candidate re-confirms");
    (applicable, instantiation)
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::implemented_instantiation @ d9be6853b
// The one instantiation (every generic argument and associated-type pin) at
// which `subject` implements the interface `name`, read off what selecting a
// goal with fresh arguments commits: an impl's header, a rigid variable's
// bound, or an existential's own reference. Null when no candidate proves
// it, several do, or what one proves is not fully determined. Nothing the
// selection does survives the call.
function implemented_instantiation(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    name: root.types.DeclName,
    arity: int,
    associated: string[],
) -> InterfaceInstantiation? throws never {
    let table = ctx.table;
    let pool = table.pool;
    let resolved = table.resolve_completely(subject);
    if (pool.has_infer(resolved) || pool.has_error(resolved)) {
        return null;
    }
    let widened = widen_literal(pool, root.hir_ty.expand_alias_head(ctx.table.pool, resolved, ctx.facts));
    let probe = root.hir_ty.probe(ctx);
    let generics: int[] = [];
    for (let i = 0; i < arity; i += 1) {
        generics.push(table.new_var_ty());
    }
    let goal = root.types.infer_interface_new(
        name,
        generics,
        associated.map((member) -> {
            root.types.InferAssociatedType { name: member, ty: table.new_var_ty() }
        }),
    );
    let confirmed = match (pool.kinds[widened]) {
        root.types.InferTyInterface => select_object(ctx, widened, goal) == Selection.Confirmed,
        root.types.TyTypeVar => select_param_env(ctx, widened, goal) == Selection.Confirmed,
        // No impl subject is a union, and the top type is no implementor.
        root.types.InferTyUnion | root.types.TyUnknown | root.types.TyNever => false,
        // An impl's header pins the arguments only where one impl applies.
        _ => {
            match (confirm_unique_impl(ctx, widened, widened, goal)) {
                Selection => false,
                null => false,
                _ => true,
            }
        },
    };
    let instantiation: InterfaceInstantiation? = null;
    if (confirmed) {
        let args = goal.generics.map((arg) -> {
            table.resolve_completely(arg)
        });
        let pins = goal.associated_types.map((pin) -> {
            (pin.name, table.resolve_completely(pin.ty))
        });
        let determined = args
            .concat(
                pins.map((pin) -> {
                    pin.1
                }),
            )
            .every((ty) -> {
                !pool.has_infer(ty) && !pool.has_error(ty)
            });
        if (determined) {
            instantiation = InterfaceInstantiation { args: args, pins: pins };
        }
    }
    root.hir_ty.rollback_probe(ctx, probe);
    instantiation
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::select_object @ d9be6853b
// Object selection: the existential subject's own reference and its
// `requires` closure are the candidate heads; a matching head confirms by
// unifying args and the goal's pins. Exactly one applicable head commits,
// several stall, none reports.
function select_object(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    goal: root.types.InferInterfaceConstraint,
) -> Selection throws never {
    let pool = ctx.table.pool;
    let existential = match (pool.kinds[subject]) {
        let i: root.types.InferTyInterface => i,
        _ => baml.sys.panic("object selection is for an existential subject"),
    };
    let subject_target = root.types.infer_interface_new(existential.name, existential.args, existential.associated_types);
    let heads = root.hir_ty.requires_heads(ctx.db, subject_target, subject, 8);
    let applicable: root.types.InferInterfaceConstraint? = null;
    for (let head in heads) {
        let probe = root.hir_ty.probe(ctx);
        let applies = confirm_object(ctx, head, goal);
        root.hir_ty.rollback_probe(ctx, probe);
        if (applies) {
            if (applicable != null) {
                return Selection.Ambiguous;
            }
            applicable = head;
        }
    }
    if (applicable == null) {
        return Selection.NoCandidate;
    }
    confirm_object(ctx, applicable, goal);
    Selection.Confirmed
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::select_param_env @ d9be6853b
// Caller-bound selection: a rigid var implements what its carried bounds and
// their `requires` closure say. A matching head confirms by unifying args,
// and each goal pin with the head's pin or, where the bound leaves the
// member unpinned, with the rigid projection `(subject as Head).Member`.
// Exactly one applicable head commits, several stall, none reports.
function select_param_env(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    goal: root.types.InferInterfaceConstraint,
) -> Selection throws never {
    let pool = ctx.table.pool;
    let param = match (pool.kinds[subject]) {
        let v: root.types.TyTypeVar => v.param,
        _ => baml.sys.panic("caller-bound selection is for a rigid var subject"),
    };
    // One head, one candidate: two bounds whose `requires` closures meet
    // reach the same head twice, and a head is not ambiguous with itself.
    let heads: root.types.InferInterfaceConstraint[] = [];
    for (let bound in ctx.facts.type_var_bound(param)) {
        let reference = root.types.infer_interface_from_constraint(pool, bound);
        for (let head in root.hir_ty.requires_heads(ctx.db, reference, subject, 8)) {
            if (!heads.includes(head)) {
                heads.push(head);
            }
        }
    }
    let applicable: root.types.InferInterfaceConstraint? = null;
    for (let head in heads) {
        let probe = root.hir_ty.probe(ctx);
        let applies = confirm_param_head(ctx, subject, head, goal);
        root.hir_ty.rollback_probe(ctx, probe);
        if (applies) {
            if (applicable != null) {
                return Selection.Ambiguous;
            }
            applicable = head;
        }
    }
    if (applicable == null) {
        return Selection.NoCandidate;
    }
    confirm_param_head(ctx, subject, applicable, goal);
    Selection.Confirmed
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_param_head @ d9be6853b
// One carried head against the goal: `confirm_object`'s args and pins,
// except that a member the bound does not pin is the rigid var's own
// projection rather than a failure.
function confirm_param_head(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    head: root.types.InferInterfaceConstraint,
    goal: root.types.InferInterfaceConstraint,
) -> bool throws never {
    if (head.name != goal.name || head.generics.length() != goal.generics.length()) {
        return false;
    }
    for (let i = 0; i < head.generics.length(); i += 1) {
        ctx.table.unify(head.generics[i], goal.generics[i]) catch (e) {
            UnifyError => {
                return false;
            },
        };
    }
    for (let want in goal.associated_types) {
        let have = head.associated_types.find((binding) -> {
            binding.name == want.name
        });
        let have_pin = if (have != null) {
            have.ty
        } else {
            ctx.table.pool.add(
                root.types.InferTyAssociatedTypeProjection {
                    base: subject,
                    interface_: head,
                    member: want.name,
                },
            )
        };
        ctx.table.unify(have_pin, want.ty) catch (e) {
            UnifyError => {
                return false;
            },
        };
    }
    true
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::taint_goal_vars @ d9be6853b
// Marks every open class a goal names (its subject, the interface's
// arguments and pins) as owned by the goal's report.
function taint_goal_vars(
    ctx: root.hir_ty.InferenceContext,
    subject: int,
    interface_: root.types.InferInterfaceConstraint,
) -> void throws never {
    ctx.table.taint_vars_in(subject);
    for (let ty in interface_.generics) {
        ctx.table.taint_vars_in(ty);
    }
    for (let binding in interface_.associated_types) {
        ctx.table.taint_vars_in(binding.ty);
    }
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::report_not_implemented @ d9be6853b
// Records that `subject` does not implement `interface_`: the nominal
// verdict, reported as such rather than as a subtyping mismatch (which the
// finalize filter would re-judge, and `never <: I` holds vacuously). One
// report per anchor, subject and interface: a goal can register more than
// once for the same expression.
function report_not_implemented(
    ctx: root.hir_ty.InferenceContext,
    at: int,
    subject: int,
    interface_: root.types.InferInterfaceConstraint,
    required_for: RequiredFor[],
) -> void throws never {
    // The verdict owns the goal's open classes: a slot the goal would have
    // determined had it held is a cascade of this report.
    taint_goal_vars(ctx, subject, interface_);
    let existential = root.types.infer_interface_existential(ctx.table.pool, interface_);
    let already = ctx.journals.pending_diags.some((pending) -> {
        match (pending) {
            let reported: root.hir_ty.PendingDiagDoesNotImplement => {
                reported.expr == at
                    && reported.value == subject
                    && reported.interface_ == existential
            },
            _ => false,
        }
    });
    if (!already) {
        root.hir_ty.report(
            ctx,
            root.hir_ty.PendingDiagDoesNotImplement {
                expr: at,
                value: subject,
                interface_: existential,
                required_for: required_for,
            },
        );
    }
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::settle_stalled_obligations @ d9be6853b
// Settles the goals still pending at quiescence. The recorded stall REASON
// decides: "more than one implementation could make this work" is rustc's
// E0283 and only true of a goal that found more than one. Everything else
// stalled because part of it never resolved, and the diagnostics for an
// undetermined type own it.
function settle_stalled_obligations(ctx: root.hir_ty.InferenceContext) -> void throws never {
    let pending = ctx.journals.obligations;
    ctx.journals.obligations = [];
    for (let entry in pending) {
        match (entry.obligation) {
            // An operator stalls only on an unsolved operand, whose own
            // undetermined-type report owns it. The output is tainted so it
            // does not report a second time, except where solving merged the
            // output INTO an operand's class (`xs.push(xs[0] + 1)`): that
            // class is the operand, and its own report must stand.
            let operator: ObligationOperator => {
                let operand_roots = ctx.table.open_roots_in(operator.lhs);
                let rhs = operator.rhs;
                if (rhs != null) {
                    operand_roots = operand_roots.concat(ctx.table.open_roots_in(rhs));
                }
                for (let root_var in ctx.table.open_roots_in(operator.out)) {
                    if (!operand_roots.includes(root_var)) {
                        ctx.table.taint_root(root_var);
                    }
                }
            },
            let goal: ObligationImplements => {
                if (entry.stall == Stall.Ambiguous) {
                    let ty = ctx.table.resolve_completely(goal.ty);
                    let interface_ = resolve_interface_ref(ctx, goal.interface_);
                    // As for a failed goal: the ambiguity report owns the
                    // slots the selection would have decided.
                    taint_goal_vars(ctx, ty, interface_);
                    root.hir_ty.report(
                        ctx,
                        root.hir_ty.PendingDiagAmbiguousImplementation {
                            expr: goal.at,
                            value: ty,
                            interface_: root.types.infer_interface_existential(ctx.table.pool, interface_),
                            required_for: goal.required_for,
                        },
                    );
                }
            },
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_object @ d9be6853b
// One object head against the goal: names equal, args unify pairwise, and
// every goal pin unifies with the head's realization of that member (the
// head may pin MORE; a member the head does not realize cannot prove a
// pinned requirement).
function confirm_object(
    ctx: root.hir_ty.InferenceContext,
    head: root.types.InferInterfaceConstraint,
    goal: root.types.InferInterfaceConstraint,
) -> bool throws never {
    if (head.name != goal.name || head.generics.length() != goal.generics.length()) {
        return false;
    }
    for (let i = 0; i < head.generics.length(); i += 1) {
        ctx.table.unify(head.generics[i], goal.generics[i]) catch (e) {
            UnifyError => {
                return false;
            },
        };
    }
    for (let want in goal.associated_types) {
        let have = head.associated_types.find((binding) -> {
            binding.name == want.name
        })
            ?? return false;
        ctx.table.unify(have.ty, want.ty) catch (e) {
            UnifyError => {
                return false;
            },
        };
    }
    true
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::register_impl_bound_obligations @ d9be6853b
// The impl's declared bounds at `instantiation` become NESTED obligations
// (rustc's confirmation side conditions), discharged next round. Shared by
// selection and the method probe; `required_for` ends with the goal the
// impl was confirmed for.
function register_impl_bound_obligations(
    ctx: root.hir_ty.InferenceContext,
    facts: root.hir_ty.ImplFacts,
    instantiation: map<root.types.ParamTy, int>,
    at: int,
    required_for: RequiredFor[],
) -> void throws never {
    for (let entry in facts.generic_params) {
        let arg = instantiation.get(entry.0);
        if (arg != null) {
            for (let bound in entry.1) {
                register_obligation(
                    ctx,
                    ObligationImplements {
                        ty: arg,
                        interface_: instantiate_interface(ctx.table.pool, bound, instantiation),
                        at: at,
                        purpose: GoalPurpose.Bound,
                        required_for: required_for,
                    },
                );
            }
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_impl @ d9be6853b
// CONFIRMATION (rustc's shape): instantiate the impl header with FRESH
// inference variables for its params and unify the goal against it: the
// for-target, each interface arg, then every requested pin against the
// impl's binding-else-default. The param instantiation on success; any
// failed unification (or a pin the impl can neither bind nor default)
// rejects the candidate, and the caller's snapshot discards the partial
// bindings.
function confirm_impl(
    ctx: root.hir_ty.InferenceContext,
    goal: int,
    interface_: root.types.InferInterfaceConstraint,
    facts: root.hir_ty.ImplFacts,
) -> map<root.types.ParamTy, int>? throws never {
    let pool = ctx.table.pool;
    let implemented_ref = facts.interface_.reference;
    if (implemented_ref.generics.length() != interface_.generics.length()) {
        return null;
    }
    let instantiation = confirm_impl_subject(ctx, goal, facts)
        ?? return null;
    for (let i = 0; i < implemented_ref.generics.length(); i += 1) {
        let pattern = pool.substitute_bindings(implemented_ref.generics[i], instantiation);
        let requested = root.hir_ty.unfold_aliases_against(pool, pattern, interface_.generics[i], ctx.facts);
        ctx.table.unify(requested, pattern) catch (e) {
            UnifyError => {
                return null;
            },
        };
    }
    for (let binding in interface_.associated_types) {
        let own = facts.associated_types.find((declared) -> {
            declared.0 == binding.name
        });
        let supplied = if (own != null) {
            pool.substitute_bindings(own.1.ty, instantiation)
        } else {
            let implemented = root.types.infer_interface_new(
                implemented_ref.name,
                implemented_ref.generics.map((ty) -> {
                    pool.substitute_bindings(ty, instantiation)
                }),
                implemented_ref.associated_types.map((pin) -> {
                    root.types.InferAssociatedType {
                        name: pin.name,
                        ty: pool.substitute_bindings(pin.ty, instantiation),
                    }
                }),
            );
            root.hir_ty.realized_assoc_default(ctx.db, implemented, goal, binding.name)
                ?? return null
        };
        // Normalize-then-unify: a GROUND requested pin may be a reducible
        // projection and structural unification would reject the candidate
        // on spelling. Var-carrying pins skip reduction and unify as
        // variables.
        let requested = binding.ty;
        if (pool.has_projection(requested) && !pool.has_infer(requested)) {
            requested
                = root.hir_ty
                    .reduce_projections(
                        ctx,
                        root.types.ClosedTy { ty: requested },
                        root.hir_ty.PROJECTION_FINALIZE_FUEL,
                    )
                    .ty;
        }
        if (pool.has_projection(supplied) && !pool.has_infer(supplied)) {
            supplied
                = root.hir_ty
                    .reduce_projections(
                        ctx,
                        root.types.ClosedTy { ty: supplied },
                        root.hir_ty.PROJECTION_FINALIZE_FUEL,
                    )
                    .ty;
        }
        ctx.table.unify(requested, supplied) catch (e) {
            UnifyError => {
                return null;
            },
        };
    }
    instantiation
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::confirm_impl_subject @ d9be6853b
// The SUBJECT half of confirmation, shared with the method probe: the
// impl's params instantiate as FRESH inference variables and the goal
// unifies against the for-target, which merely LINKS the goal's variables
// to the impl's. Bare-blanket guard as in the ground matcher:
// `implements<T> I for T` applies only to concrete receivers.
function confirm_impl_subject(
    ctx: root.hir_ty.InferenceContext,
    goal: int,
    facts: root.hir_ty.ImplFacts,
) -> map<root.types.ParamTy, int>? throws never {
    let pool = ctx.table.pool;
    let pattern = facts.for_ty_pattern.ty;
    if let v: root.types.TyTypeVar = pool.kinds[pattern] {
        let own_param = facts.generic_params.some((entry) -> {
            entry.0 == v.param
        });
        if (own_param && !root.hir_ty.is_concrete_receiver(pool, goal)) {
            return null;
        }
    }
    let instantiation: map<root.types.ParamTy, int> = {};
    for (let entry in facts.generic_params) {
        instantiation[entry.0] = root.hir_ty.fresh_generic_arg(ctx, entry.0);
    }
    let for_ty = pool.substitute_bindings(pattern, instantiation);
    // Unification is structural: an alias nested where the header has
    // structure meets it unfolded.
    let unfolded = root.hir_ty.unfold_aliases_against(pool, for_ty, goal, ctx.facts);
    ctx.table.unify(unfolded, for_ty) catch (e) {
        UnifyError => {
            return null;
        },
    };
    instantiation
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::probe_impl_member @ d9be6853b
// rust-analyzer's METHOD PROBE for a receiver still carrying inference
// variables (`ArrayIterator<?T>.filter`): candidates are tried
// NON-COMMITTALLY under a snapshot (subject confirmation plus "does its
// interface declare the member"), and exactly ONE applying re-confirms for
// real, its header unification LINKING the receiver's variables to the
// impl's fresh ones. Zero or several candidates resolve nothing. Licensed
// by a concrete head.
function probe_impl_member(
    ctx: root.hir_ty.InferenceContext,
    receiver: int,
    name: string,
    at: int,
) -> root.hir_ty.InterfaceMember? throws never {
    let pool = ctx.table.pool;
    if (!root.hir_ty.is_concrete_receiver(pool, receiver)) {
        return null;
    }
    let lang = root.hir.lang_roots(ctx.db);
    let applicable: root.hir_ty.ImplFacts? = null;
    for (let facts in root.hir_ty.all_impl_facts(ctx.db, root.hir.file_package(ctx.db, ctx.owner_file).root_id)) {
        let interface_name = facts.interface_.reference.name;
        if (
            root.hir_ty.provides_concrete_members(lang, interface_name)
                && !root.hir_ty.is_concrete_type_member(lang, interface_name, name)
        ) {
            let probe = root.hir_ty.probe(ctx);
            let applies = probe_candidate(ctx, receiver, name, facts) != null;
            root.hir_ty.rollback_probe(ctx, probe);
            if (applies) {
                if (applicable != null) {
                    return null;
                }
                applicable = facts;
            }
        }
    }
    if (applicable == null) {
        let roots: root.types.InferInterfaceConstraint[] = if (pool.has_infer(receiver)) {
            let open_roots = root.hir_ty.structural_interface_roots(ctx.db);
            root.base.push_some(open_roots, root.hir_ty.hash_interface_root(ctx.db));
            if (pool.kinds[receiver] is root.types.InferTyTuple) {
                root.base.push_some(open_roots, root.hir_ty.compare_interface_root(ctx.db));
            }
            open_roots
        } else {
            root.hir_ty.applicable_structural_interface_roots(ctx.db, ctx.facts, receiver)
        };
        // The unique root declaring the member; a second one resolves
        // nothing (Rust stops its lazy search at the second).
        let found: (root.types.InferInterfaceConstraint, root.hir_ty.InterfaceMember)[] = [];
        for (let interface_ in roots) {
            let member = root.hir_ty.member_on_interface(ctx.db, ctx.facts, interface_, receiver, name, false);
            if (member != null) {
                found.push((interface_, member));
                if (found.length() > 1) {
                    return null;
                }
            }
        }
        let (let interface_, let member) = found.at(0)
            ?? return null;
        // Discovering a conditional default's signature does not prove
        // conformance. Fulfillment checks it once the receiver resolves.
        let kind = root.hir_ty.structural_interface(ctx.db, interface_.name);
        if (kind != null && root.types.structural_interface_is_conditional(kind)) {
            register_obligation(ctx, obligation_implements(receiver, interface_, at, GoalPurpose.Bound));
        }
        return member;
    }
    let (let member, let instantiation) = probe_candidate(ctx, receiver, name, applicable)
        ?? baml.sys.panic("the unique applicable candidate re-confirms");
    let required_for = [
        RequiredFor {
            subject: receiver,
            interface_: instantiate_interface(pool, applicable.interface_, instantiation),
        },
    ];
    register_impl_bound_obligations(ctx, applicable, instantiation, at, required_for);
    member
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::probe_candidate @ d9be6853b
// One probe candidate: subject confirmation, then the member resolved on
// the interface this impl provides, realized through the confirmation's
// bindings (`filter`'s signature comes back MENTIONING the receiver's `?T`).
// The target's pins carry the impl's OWN associated bindings alongside any
// header pins, so the member's `Self.Item` slots realize through the
// confirmation's variables.
function probe_candidate(
    ctx: root.hir_ty.InferenceContext,
    receiver: int,
    name: string,
    facts: root.hir_ty.ImplFacts,
) -> (root.hir_ty.InterfaceMember, map<root.types.ParamTy, int>)? throws never {
    let pool = ctx.table.pool;
    let instantiation = confirm_impl_subject(ctx, receiver, facts)
        ?? return null;
    let implemented_ref = facts.interface_.reference;
    let pins = implemented_ref.associated_types
        .map((pin) -> {
            root.types.InferAssociatedType {
                name: pin.name,
                ty: pool.substitute_bindings(pin.ty, instantiation),
            }
        })
        .concat(
            facts.associated_types.map((pin) -> {
                root.types.InferAssociatedType {
                    name: pin.0,
                    ty: pool.substitute_bindings(pin.1.ty, instantiation),
                }
            }),
        );
    // Rust's `dedup_by` on names: consecutive repeats drop, the first stays.
    let deduped: root.types.InferAssociatedType[] = [];
    for (let pin in pins) {
        let last = deduped.at(deduped.length() - 1);
        if (last == null || last.name != pin.name) {
            deduped.push(pin);
        }
    }
    let implemented = root.types.infer_interface_new(
        implemented_ref.name,
        implemented_ref.generics.map((arg) -> {
            pool.substitute_bindings(arg, instantiation)
        }),
        deduped,
    );
    let member = root.hir_ty.member_on_interface(ctx.db, ctx.facts, implemented, receiver, name, false)
        ?? return null;
    (member, instantiation)
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::implements_holds @ d9be6853b
// Whether ground `ty` implements `interface_`: carried bounds for a rigid
// var (directly or through the requires closure), interface
// identity/requires for an existential, the impl registry for concrete
// types. A union reaches the registry and no impl subject is a union, so it
// fails, never "passes as a subtype".
function implements_holds(
    ctx: root.hir_ty.InferenceContext,
    ty: int,
    interface_: root.types.InferInterfaceConstraint,
) -> bool throws never {
    let pool = ctx.table.pool;
    if (root.hir_ty.is_structural_interface(ctx.db, interface_)) {
        return true;
    }
    let eligible = root.hir_ty.conditional_structural_verdict(ctx.db, ctx.facts, ty, interface_);
    if (eligible != null) {
        return eligible;
    }
    let eq = root.hir_ty.AliasOnlyFacts.new(ctx.db);
    match (pool.kinds[ty]) {
        let v: root.types.TyTypeVar => {
            ctx.facts.type_var_bound(v.param).some((carried) -> {
                let have = root.types.infer_interface_from_constraint(pool, carried);
                root.hir_ty.head_satisfies(ctx.db, have, interface_, eq)
                    || root.hir_ty.interface_requires(ctx.db, have, interface_, ty, 8)
            })
        },
        let i: root.types.InferTyInterface => {
            let have = root.types.infer_interface_new(i.name, i.args, i.associated_types);
            root.hir_ty.head_satisfies(ctx.db, have, interface_, eq)
                || root.hir_ty.interface_requires(ctx.db, have, interface_, ty, 8)
        },
        // A projection: a reducible one reduces inside the canonical
        // algebra; a still-symbolic one proves against its declared bound
        // through the algebra's projection-subtype rule. Fail-closed.
        root.types.InferTyAssociatedTypeProjection => {
            root.hir_ty.sub(ctx, ty, root.types.infer_interface_existential(pool, interface_))
        },
        _ => root.hir_ty.implements_interface(ctx.db, ty, interface_),
    }
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::InferenceContext::resolve_interface_ref @ d9be6853b
// The reference with every generic argument and pin resolved through the
// table.
function resolve_interface_ref(
    ctx: root.hir_ty.InferenceContext,
    interface_: root.types.InferInterfaceConstraint,
) -> root.types.InferInterfaceConstraint throws never {
    root.types.infer_interface_new(
        interface_.name,
        interface_.generics.map((arg) -> {
            ctx.table.resolve_completely(arg)
        }),
        interface_.associated_types.map((binding) -> {
            root.types.InferAssociatedType {
                name: binding.name,
                ty: ctx.table.resolve_completely(binding.ty),
            }
        }),
    )
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::widen_literal @ d9be6853b
// A literal type is judged as its base primitive: `1` implements what `int`
// does. Only the JUDGMENT widens: a report names the subject as written,
// which is why `attempt` keeps both.
function widen_literal(pool: root.types.InferPool, ty: int) -> int throws never {
    match (pool.kinds[ty]) {
        let l: root.types.TyLiteral => pool.add(root.hir_ty.literal_base(l.value)),
        _ => ty,
    }
}

// port: baml_compiler2_hir_ty/src/infer/obligations.rs::interface_has_infer @ d9be6853b
// Whether any generic argument or pin of the reference carries an inference
// variable. Restructured: takes the pool its handles index.
function interface_has_infer(
    pool: root.types.InferPool,
    interface_: root.types.InferInterfaceConstraint,
) -> bool throws never {
    interface_.generics.some((ty) -> {
        pool.has_infer(ty)
    })
        || interface_.associated_types.some((binding) -> {
            pool.has_infer(binding.ty)
        })
}
