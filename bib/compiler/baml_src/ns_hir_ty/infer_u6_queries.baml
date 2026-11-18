// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 6, the queries: the per-owner tracked inference queries, their
// cycle seeds, the in-flight top-level let set, and `infer_body_impl`, which
// sets up an `InferenceContext` for one body owner, walks it and finishes it.
//
// Restructured (BAML forces it):
// - Each `#[salsa::tracked]` query is a `TrackedMemo` on `db.ty_memo`
//   (`infer_function_body`, `infer_let_body`, `infer_parameter_defaults`);
//   a `cycle_initial` seed is `get_fixpoint`'s `initial`.
// - The thread-local `IN_FLIGHT_LET_OWNERS` is `db.ty_memo.in_flight_let_owners`.
//   `InFlightLetOwner`'s `Drop` is an explicit `leave`, called on the
//   query's one exit path.
// - The process-wide `BODY_INFERENCES` counter is `db.ty_memo.body_inferences`:
//   a compile owns one `Db`, so `body_inferences` takes it.

// port: baml_compiler2_hir_ty/src/infer.rs::infer_function_body_cycle_initial @ d9be6853b
// The fixpoint seed for the signature/throws cycle (`infer_body ->
// function_signature -> callable_throws -> infer_body`): an empty result
// whose effect is `never`, consistent with `callable_throws`' own seed.
// Restructured: salsa's `id` parameter is dropped (nothing reads it).
function infer_function_body_cycle_initial(
    db: root.hir.Db,
    function_: int,
) -> InferenceResult<root.types.Ty> throws never {
    InferenceResult.empty(root.types.TyNever {})
}

// port: baml_compiler2_hir_ty/src/infer.rs::LetOwnerKey @ d9be6853b
// A top-level let's identity across queries: its file's path and item id.
type LetOwnerKey = (string, int);

// port: baml_compiler2_hir_ty/src/infer.rs::let_owner_key @ d9be6853b
function let_owner_key(db: root.hir.Db, let_binding: int) -> LetOwnerKey throws never {
    let loc = db.let_locs.get(let_binding);
    (db.file(loc.file).path, loc.id)
}

// port: baml_compiler2_hir_ty/src/infer.rs::let_owner_is_in_flight @ d9be6853b
// Whether `let_binding`'s initializer is being inferred now, further up the
// query stack.
function let_owner_is_in_flight(db: root.hir.Db, let_binding: int) -> bool throws never {
    let (let path, let id) = let_owner_key(db, let_binding);
    db.ty_memo.in_flight_let_owners.get(path)?.has(id) ?? false
}

// port: baml_compiler2_hir_ty/src/infer.rs::InFlightLetOwner @ d9be6853b
// One top-level let's entry in the in-flight set, held while its
// initializer is inferred. `inserted` is false for a re-entry, which must
// not remove the outer entry.
class InFlightLetOwner {
    key: LetOwnerKey,
    inserted: bool,

    // port: baml_compiler2_hir_ty/src/infer.rs::InFlightLetOwner::enter @ d9be6853b
    function enter(db: root.hir.Db, let_binding: int) -> InFlightLetOwner throws never {
        let key = let_owner_key(db, let_binding);
        let ids = db.ty_memo.in_flight_let_owners.get_or_insert(key.0, {});
        let inserted = !ids.has(key.1);
        ids[key.1] = true;
        InFlightLetOwner { key: key, inserted: inserted }
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::impl Drop for InFlightLetOwner::drop @ d9be6853b
    // Restructured: BAML has no destructors; the owner calls this on every
    // exit path.
    function leave(self, db: root.hir.Db) -> void throws never {
        if (self.inserted) {
            db.ty_memo.in_flight_let_owners.get(self.key.0)?.delete(self.key.1);
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_let_body_cycle_initial @ d9be6853b
// The seed of a mutually recursive top-level let: its root expression types
// as the error sentinel, with E0147 there.
// Restructured: salsa's `id` parameter is dropped (nothing reads it).
function infer_let_body_cycle_initial(
    db: root.hir.Db,
    let_binding: int,
) -> InferenceResult<root.types.Ty> throws never {
    let result: InferenceResult<root.types.Ty> = InferenceResult.empty(root.types.TyNever {});
    match (root.hir.let_body(db, let_binding)) {
        let body: root.hir.LetBodyExpr => {
            let root_expr = body.value.root_expr;
            if (root_expr != null) {
                result.type_of_expr[root_expr] = root.types.TyError {};
                result.diagnostics.push(
                    TirDiagnostic {
                        error: TirTypeErrorCannotInferType {},
                        severity: DiagnosticSeverity.Error,
                        primary: DiagnosticLocationExpr { value: root_expr },
                        related: [],
                    },
                );
            }
        },
        root.hir.LetBodyMissing => {},
    }
    result
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_function_body @ d9be6853b
// TRACKED: the crate's central query, per function.
function infer_function_body(
    db: root.hir.Db,
    function_: int,
) -> InferenceResult<root.types.Ty> throws never {
    db.ty_memo.infer_function_body.get_fixpoint(
        db.cycles,
        function_,
        () -> {
            infer_function_body_cycle_initial(db, function_)
        },
        () -> {
            infer_body_impl(db, root.hir.BodyOwnerIdFunction { value: function_ })
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_let_body @ d9be6853b
// TRACKED: top-level `let` bodies. Mutually recursive lets have an
// error-typed cycle seed, while the explicit in-flight set normally
// diagnoses before the fixpoint must recover.
function infer_let_body(
    db: root.hir.Db,
    let_binding: int,
) -> InferenceResult<root.types.Ty> throws never {
    db.ty_memo.infer_let_body.get_fixpoint(
        db.cycles,
        let_binding,
        () -> {
            infer_let_body_cycle_initial(db, let_binding)
        },
        () -> {
            let in_flight = InFlightLetOwner.enter(db, let_binding);
            let result = infer_body_impl(db, root.hir.BodyOwnerIdLet { value: let_binding });
            in_flight.leave(db);
            result
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_parameter_defaults @ d9be6853b
// TRACKED: a function's parameter-default arena as its own inference root.
// No cycle seed: nothing on the signature road consults default inference.
function infer_parameter_defaults(
    db: root.hir.Db,
    function_: int,
) -> InferenceResult<root.types.Ty> throws never {
    db.ty_memo.infer_parameter_defaults.get(db.cycles, function_, () -> {
        infer_body_impl(db, root.hir.BodyOwnerIdParameterDefaults { value: function_ })
    })
}

// port: baml_compiler2_hir_ty/src/infer.rs::owner_declared_bounds @ d9be6853b
// The bounds the owner declared: the param env a body owner's inference runs
// in (each rigid type variable's declared bound conjunction), in the
// declaration side's plain vocabulary.
function owner_declared_bounds(
    db: root.hir.Db,
    owner: root.hir.BodyOwnerId,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    match (owner) {
        let o: root.hir.BodyOwnerIdFunction => function_generic_bounds(db, o.value),
        let o: root.hir.BodyOwnerIdParameterDefaults => function_generic_bounds(db, o.value),
        root.hir.BodyOwnerIdLet => {
            let none: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
            none
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_body @ d9be6853b
// Infers types for one body owner (function, top-level let, or a function's
// parameter defaults): a dispatcher over the per-loc tracked queries.
function infer_body(
    db: root.hir.Db,
    owner: root.hir.BodyOwnerId,
) -> InferenceResult<root.types.Ty> throws never {
    match (owner) {
        let o: root.hir.BodyOwnerIdFunction => infer_function_body(db, o.value),
        let o: root.hir.BodyOwnerIdLet => infer_let_body(db, o.value),
        let o: root.hir.BodyOwnerIdParameterDefaults => infer_parameter_defaults(db, o.value),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::body_inferences @ d9be6853b
// Number of body inferences executed (not served from a memo) in this
// compile. Restructured: the counter lives on the Db, so it takes the Db.
function body_inferences(db: root.hir.Db) -> int throws never {
    db.ty_memo.body_inferences
}

// port: baml_compiler2_hir_ty/src/infer.rs::infer_body_impl @ d9be6853b
// One inference run: the owner's generic frame, parameter types, return
// expectation and written `throws` clause set up the context; the body is
// walked (each parameter default against its parameter, for a defaults
// owner) and finished.
function infer_body_impl(
    db: root.hir.Db,
    owner: root.hir.BodyOwnerId,
) -> InferenceResult<root.types.Ty> throws never {
    db.ty_memo.body_inferences += 1;
    let body = root.hir.owner_body_expr_body(root.hir.body(db, owner));
    let pool = db.ty_memo.pool;
    // The owner's generic frame makes `T` in body annotations resolve; the
    // signature gives parameter references their types and the body its
    // return expectation.
    let parts: (root.types.ParamTy[], int[], int?, DeclaredThrows?) = match (owner) {
        let o: root.hir.BodyOwnerIdFunction => {
            let signature = function_signature_with_diagnostics(db, o.value).signature;
            // A malformed `cleanup` is reported at its signature (E0144). Its
            // body, run-once guard included, is written for the finalizer's
            // unit return and owes the declared one nothing.
            let return_ty = if (cleanup_method(db, o.value) == CleanupMethod.Malformed) {
                pool.add(root.types.TyError {})
            } else {
                pool.from_plain(signature.ret)
            };
            (
                function_generic_frame(db, o.value),
                signature.params.map((param) -> {
                    pool.from_plain(param.ty)
                }),
                return_ty,
                // The owner checks its throw sites against the WRITTEN clause
                // (a partial clause opens the contract), never the
                // caller-facing surface, which for a partial clause is derived
                // FROM those sites.
                declared_throws(db, o.value),
            )
        },
        // Defaults type in the FUNCTION's environment (its frame makes `T` in
        // a default resolve; its parameter types are each default's
        // expectation) with no return expectation and no declared throws
        // clause of their own.
        let o: root.hir.BodyOwnerIdParameterDefaults => {
            let signature = function_signature_with_diagnostics(db, o.value).signature;
            (
                function_generic_frame(db, o.value),
                signature.params.map((param) -> {
                    pool.from_plain(param.ty)
                }),
                null,
                null,
            )
        },
        // A global's initializer checks against its annotation the way a
        // function body checks against its declared return type.
        let o: root.hir.BodyOwnerIdLet => {
            let declared_ty = let_declared_type(db, o.value);
            (
                [],
                [],
                if (declared_ty != null) {
                    pool.from_plain(declared_ty)
                } else {
                    null
                },
                null,
            )
        },
    };
    let (let frame, let param_tys, let return_ty, let declared) = parts;
    let function_: int? = match (owner) {
        let o: root.hir.BodyOwnerIdFunction => o.value,
        let o: root.hir.BodyOwnerIdParameterDefaults => o.value,
        root.hir.BodyOwnerIdLet => null,
    };
    // BODY-position `Self` is a plain-class-method error (signatures resolve
    // it, bodies do not); implements-block bodies and interface default
    // bodies keep theirs.
    let concrete_self: root.types.Ty? = if (function_ != null) {
        match (root.hir.method_owner(db, function_)) {
            root.hir.MethodOwnerClass => null,
            _ => owner_self_ty(db, function_),
        }
    } else {
        null
    };
    let impl_target = if (function_ != null) {
        owner_impl_target(db, function_, frame)
    } else {
        null
    };
    let lower = lower_ctx_for_file(db, root.hir.body_owner_id_file(db, owner)).with_frame(frame)
        .with_bounds(owner_declared_bounds(db, owner))
        .with_self_ty(concrete_self)
        .with_impl_target(impl_target);
    let clause: ThrowsClause = match (declared) {
        let d: DeclaredThrowsClosed => ThrowsClauseClosed { value: pool.from_plain(d.value) },
        let d: DeclaredThrowsPartial => ThrowsClauseOpen { named: pool.from_plain(d.named) },
        DeclaredThrowsOmitted | null => ThrowsClauseInferred {},
    };
    let ctx = InferenceContext.new(db, owner, lower, param_tys, return_ty, clause);
    if let defaults_owner: root.hir.BodyOwnerIdParameterDefaults = owner {
        // The defaults arena has no single root: each parameter's default
        // checks against that parameter's declared type (its expectation at
        // the call boundary, the rule MIR's callee-entry prologue relies on).
        let defaults = root.hir.function_parameter_defaults(db, defaults_owner.value);
        if (body != null) {
            register_property_shorthands(ctx, body);
            for (let index = 0; index < defaults.params.length(); index += 1) {
                let default = defaults.params[index];
                if (default == null) {
                    continue;
                }
                let param_ty = ctx.param_tys.at(index);
                if (param_ty != null && !pool.has_error(param_ty)) {
                    check_expr(ctx, body, default.expr, param_ty);
                } else {
                    infer_expr(ctx, body, default.expr, ExpectationNone {});
                }
            }
            check_tag_values(ctx, body);
            backfill_untyped_patterns(ctx, body);
        }
    } else if (body != null) {
        infer_expr_body(ctx, body);
    }
    if (body != null) {
        report_call_site_builtin_values(ctx, body);
    }
    finish(ctx, body)
}
