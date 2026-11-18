// port: baml_compiler2_hir_ty/src/init_io.rs @ d9be6853b
//
// Check-time detection of io and suspension reachable from `$init` (E0163,
// E0182). Every top-level binding with an initializer (a global variable or
// a `client` declaration) is evaluated once by the synthesized `$init`, on a
// path that cannot suspend: an io sysop, a `spawn` or an `await` reached from
// an initializer kills engine construction. A body is tainted when its
// evaluated path performs one of those directly, or calls a function that is
// tainted. The evaluated path excludes lambda bodies, except an immediately
// invoked lambda and a `spawn { ... }` body. The analysis is a deliberate
// under-approximation: an indirect call resolves to no function and is
// skipped.
//
// Restructured:
// - `EvaluatedCall` (`(ExprId, FunctionLoc)`) is an `(int, int)` tuple, and
//   `EvaluatedCalls::EMPTY` is `EvaluatedCalls.empty()`.
// - The two tracked queries are `TrackedMemo`s on `db.ty_memo`
//   (`function_evaluated_calls`, `let_evaluated_calls`).
// - `InitEffect` (a data enum) is a union of classes.
// - No root is served from an interface (stdlib compiled from source), so a
//   resolved function is always a source loc: `resolved_function` has no
//   `DeclRef::External` arm to skip.

// port: baml_compiler2_hir_ty/src/init_io.rs::EvaluatedCall @ d9be6853b
// One resolved call on a body's evaluated path: the callee expression it was
// written at (for span anchoring) and the function it resolved to.
type EvaluatedCall = (int, int);

// port: baml_compiler2_hir_ty/src/init_io.rs::EvaluatedCalls @ d9be6853b
// A body's evaluated path: the calls it makes, and the `await`s it performs
// itself.
class EvaluatedCalls {
    calls: EvaluatedCall[],
    // `await` expressions on the evaluated path, in arena order.
    awaits: int[],

    // port: baml_compiler2_hir_ty/src/init_io.rs::EvaluatedCalls::EMPTY @ d9be6853b
    function empty() -> EvaluatedCalls throws never {
        EvaluatedCalls { calls: [], awaits: [] }
    }
}

// port: baml_compiler2_hir_ty/src/init_io.rs::body_evaluated_calls @ d9be6853b
// The callees a body invokes on its evaluated path, in arena order: a
// dispatcher over the per-loc tracked queries.
function body_evaluated_calls(
    db: root.hir.Db,
    owner: root.hir.BodyOwnerId,
) -> EvaluatedCalls throws never {
    match (owner) {
        let o: root.hir.BodyOwnerIdFunction => function_evaluated_calls(db, o.value),
        let o: root.hir.BodyOwnerIdLet => let_evaluated_calls(db, o.value),
        // Parameter defaults are evaluated per CALL, not at `$init`.
        root.hir.BodyOwnerIdParameterDefaults => EvaluatedCalls.empty(),
    }
}

// port: baml_compiler2_hir_ty/src/init_io.rs::function_evaluated_calls @ d9be6853b
function function_evaluated_calls(db: root.hir.Db, function_: int) -> EvaluatedCalls throws never {
    db.ty_memo.function_evaluated_calls.get(db.cycles, function_, () -> {
        evaluated_calls_impl(db, root.hir.BodyOwnerIdFunction { value: function_ })
    })
}

// port: baml_compiler2_hir_ty/src/init_io.rs::let_evaluated_calls @ d9be6853b
function let_evaluated_calls(db: root.hir.Db, let_binding: int) -> EvaluatedCalls throws never {
    db.ty_memo.let_evaluated_calls.get(db.cycles, let_binding, () -> {
        evaluated_calls_impl(db, root.hir.BodyOwnerIdLet { value: let_binding })
    })
}

// port: baml_compiler2_hir_ty/src/init_io.rs::evaluated_calls_impl @ d9be6853b
// Walks the body from its root with lambdas excluded (what actually runs),
// re-seeding immediately invoked lambdas and `spawn { ... }` bodies, and
// resolves each callee through inference's tables.
function evaluated_calls_impl(
    db: root.hir.Db,
    owner: root.hir.BodyOwnerId,
) -> EvaluatedCalls throws never {
    let body = match (root.hir.body(db, owner)) {
        let o: root.hir.OwnerBodyFunction => match (o.value) {
            let b: root.hir.FunctionBodyExpr => b.value,
            // A builtin has no BAML body: its io-ness is a property of the
            // declaration, read by `io_sysop_of`, not an edge.
            root.hir.FunctionBodyBuiltin | root.hir.FunctionBodyMissing => {
                return EvaluatedCalls.empty();
            },
        },
        let o: root.hir.OwnerBodyLet => match (o.value) {
            let b: root.hir.LetBodyExpr => b.value,
            root.hir.LetBodyMissing => {
                return EvaluatedCalls.empty();
            },
        },
        // Parameter defaults are evaluated per CALL, not at `$init`.
        root.hir.OwnerBodyParameterDefaults => {
            return EvaluatedCalls.empty();
        },
    };
    let root_expr = body.root_expr
        ?? return EvaluatedCalls.empty();

    let inference = infer_body(db, owner);

    let callee_exprs: int[] = [];
    let awaits: int[] = [];
    let seen_lambda_bodies: map<int, bool> = {};
    let roots: int[] = [root_expr];
    while let start: int = roots.pop() {
        for (let node in body.reachable_excluding_lambdas(start)) {
            let id = match (node) {
                let n: root.ast.BodyNodeExpr => n.value,
                root.ast.BodyNodeStmt => {
                    continue;
                },
            };
            // A `spawn { ... }` body is a launch, not a stored thunk, so it
            // runs during `$init` too: re-seed it, as an IIFE is below.
            match (body.exprs[id]) {
                let l: root.ast.ExprLambda if l.value.kind == root.ast.LambdaKind.Spawn => {
                    let lambda_body = l.value.body;
                    if (lambda_body != null && !seen_lambda_bodies.has(lambda_body)) {
                        seen_lambda_bodies[lambda_body] = true;
                        roots.push(lambda_body);
                    }
                },
                _ => {},
            }
            let callee = match (body.exprs[id]) {
                let c: root.ast.ExprCall => c.callee,
                let c: root.ast.ExprOptionalCall => c.callee,
                root.ast.ExprAwait => {
                    awaits.push(id);
                    continue;
                },
                _ => {
                    continue;
                },
            };
            callee_exprs.push(callee);
            // An IIFE runs now, so its body joins the evaluated path.
            match (body.exprs[callee]) {
                let l: root.ast.ExprLambda => {
                    let lambda_body = l.value.body;
                    if (lambda_body != null && !seen_lambda_bodies.has(lambda_body)) {
                        seen_lambda_bodies[lambda_body] = true;
                        roots.push(lambda_body);
                    }
                },
                _ => {},
            }
        }
    }

    let out: EvaluatedCall[] = [];
    for (let callee in callee_exprs) {
        let resolution = inference.callee_resolution(callee);
        if (resolution != null) {
            let func = resolved_function(resolution);
            if (func != null) {
                out.push((callee, func));
            }
        }
    }
    // Arena order is deterministic and (for a single body) close enough to
    // source order that the reported hop is the first one written.
    let sorted = out.sort_by_key((call) -> {
        call.0
    });
    let calls: EvaluatedCall[] = [];
    for (let call in sorted) {
        let last = calls.at(calls.length() - 1);
        if (last == null || last != call) {
            calls.push(call);
        }
    }
    let sorted_awaits = awaits.sort_by_key((expr) -> {
        expr
    });
    let unique_awaits: int[] = [];
    for (let expr in sorted_awaits) {
        if (unique_awaits.at(unique_awaits.length() - 1) != expr) {
            unique_awaits.push(expr);
        }
    }
    EvaluatedCalls { calls: calls, awaits: unique_awaits }
}

// port: baml_compiler2_hir_ty/src/init_io.rs::resolved_function @ d9be6853b
// The statically-known callee behind a member resolution, when there is one.
// A virtual interface call resolves to a slot, not a body: no edge. Fields
// and enum variants are not calls at all.
function resolved_function(resolution: MemberResolution) -> int? throws never {
    match (resolution) {
        let r: MemberResolutionFree => r.func,
        let r: MemberResolutionMethod<root.types.Ty> => match (r.callee) {
            let c: MethodCalleeInherent => c.value,
            let c: MethodCalleeConcrete<root.types.Ty> => c.func,
            MethodCalleeVirtual<root.types.Ty> => null,
        },
        MemberResolutionField
            | MemberResolutionVariant
            | MemberResolutionInterfaceVirtualField<root.types.Ty> =>
        {
            null
        },
    }
}

// port: baml_base/src/qualified_name.rs::BAML_SYNC_WAIT @ d9be6853b
// `baml.sync._wait` never runs in `$init`, so it is not an io sysop here.
const BAML_SYNC_WAIT = "baml.sync._wait";

// port: baml_compiler2_hir_ty/src/init_io.rs::io_sysop_of @ d9be6853b
// The fully-qualified name of `func` when it is an io sysop
// (`$rust_io_function`), else null.
function io_sysop_of(db: root.hir.Db, viewer: int, func: int) -> string? throws never {
    match (root.hir.function_body(db, func)) {
        let b: root.hir.FunctionBodyBuiltin if b.value == root.ast.BuiltinKind.Io => {
            let name = qualified_name(db, viewer, func);
            if (name != BAML_SYNC_WAIT) {
                name
            } else {
                null
            }
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/init_io.rs::qualified_name @ d9be6853b
// `func`'s dotted name as source at `viewer`'s root namespace writes it
// (`baml.env.get`, `root.util.read`), or the display name of a package the
// viewer has no edge to.
function qualified_name(db: root.hir.Db, viewer: int, func: int) -> string throws never {
    let data = root.hir.function_data(db, func);
    let pkg = root.hir.file_package(db, db.function_locs.get(func).file);
    let decl = root.types.DeclName { pkg: pkg.root_id, namespace: pkg.namespace_path, name: data.name };
    Viewpoint.for_namespace(db, viewer).path(decl)
}

// port: baml_compiler2_hir_ty/src/init_io.rs::InitEffect @ d9be6853b
// An effect `$init` cannot perform.
type InitEffect = InitEffectIo | InitEffectSpawn | InitEffectAwait;

// An io sysop, by its fully-qualified name (`baml.env.get`).
class InitEffectIo {
    value: string,
}

// Launching a task (`spawn { ... }`, `baml.spawn.__spawn`).
class InitEffectSpawn {
}

// Suspending on a future (`await`, `baml.future.__await_any`).
class InitEffectAwait {
}

// port: baml_compiler2_hir_ty/src/init_io.rs::builtin_effect_of @ d9be6853b
// The effect `func` performs by being called, when it is an effectful
// builtin; null for an ordinary function (whose body the walk descends into
// instead).
function builtin_effect_of(db: root.hir.Db, viewer: int, func: int) -> InitEffect? throws never {
    let sysop = io_sysop_of(db, viewer, func);
    if (sysop != null) {
        return InitEffectIo { value: sysop };
    }
    match (root.hir.function_body(db, func)) {
        let b: root.hir.FunctionBodyBuiltin => match (b.value) {
            root.ast.BuiltinKind.Spawn => InitEffectSpawn {},
            root.ast.BuiltinKind.AwaitAny => InitEffectAwait {},
            _ => null,
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/init_io.rs::effect_reached_from @ d9be6853b
// Whether calling `func` transitively performs an init-unsafe effect, and
// which one. Io wins over suspension when one call reaches both, and
// otherwise the first effect in source order. Depth-first over the memoized
// evaluated-call graph on an explicit stack; `visited` carries across the
// whole walk (sibling hops included).
function effect_reached_from(
    db: root.hir.Db,
    viewer: int,
    func: int,
    visited: map<int, bool>,
) -> InitEffect? throws never {
    let suspension: InitEffect? = null;
    let stack: int[] = [func];
    while let current: int = stack.pop() {
        if (visited.has(current)) {
            continue;
        }
        visited[current] = true;
        match (builtin_effect_of(db, viewer, current)) {
            let io: InitEffectIo => {
                return io;
            },
            let effect: InitEffectSpawn | InitEffectAwait => {
                suspension = suspension ?? effect;
                continue;
            },
            null => {},
        }
        let evaluated = body_evaluated_calls(db, root.hir.BodyOwnerIdFunction { value: current });
        if (evaluated.awaits.length() > 0) {
            suspension = suspension ?? InitEffectAwait {};
        }
        // Reversed so the first-written callee is explored first: the search
        // order, and so the reported effect, follows source order.
        for (let i = evaluated.calls.length() - 1; i >= 0; i -= 1) {
            stack.push(evaluated.calls[i].1);
        }
    }
    suspension
}

// port: baml_compiler2_hir_ty/src/init_io.rs::let_init_io_diagnostics @ d9be6853b
// E0163 / E0182 for one top-level declaration: its initializer reaches io,
// `spawn`, or `await`, none of which `$init` can run. At most one
// diagnostic: the first offending hop in the initializer.
function let_init_io_diagnostics(
    db: root.hir.Db,
    let_loc: int,
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    let owner = root.hir.BodyOwnerIdLet { value: let_loc };
    let evaluated = body_evaluated_calls(db, owner);
    let viewer = root.hir.file_package(db, db.let_locs.get(let_loc).file).root_id;
    if (evaluated.calls.length() == 0 && evaluated.awaits.length() == 0) {
        return [];
    }
    let source_map = root.hir.body_source_map(db, owner)
        ?? return [];
    let data = root.hir.let_data(db, let_loc);
    let is_client = data.origin == root.ast.LetOrigin.Client;

    // Every offending site in the initializer, as (anchor, effect, via):
    // direct `await`s, then each call hop. The first in source order wins.
    // One visited set for the whole declaration.
    let visited: map<int, bool> = {};
    let sites: (int, InitEffect, string?)[] = evaluated.awaits.map((expr) -> (int, InitEffect, string?) {
        (expr, InitEffectAwait {}, null)
    });
    for (let (let callee_expr, let func) in evaluated.calls) {
        let direct = builtin_effect_of(db, viewer, func);
        let effect = direct ?? effect_reached_from(db, viewer, func, visited);
        if (effect != null) {
            // A direct call needs no "via": the hop IS the effect.
            let via = if (direct == null) {
                qualified_name(db, viewer, func)
            } else {
                null
            };
            sites.push((callee_expr, effect, via));
        }
    }
    // Rust's `min_by_key`: the first site at the smallest anchor.
    let first = sites.at(0)
        ?? return [];
    for (let site in sites) {
        if (site.0 < first.0) {
            first = site;
        }
    }
    let (let anchor, let effect, let via) = first;
    let declaration = data.name;
    let error: TirTypeError = match (effect) {
        let e: InitEffectIo => {
            TirTypeErrorInitIoNotAllowed {
                declaration: declaration,
                is_client: is_client,
                sysop: e.value,
                via: via,
            }
        },
        InitEffectSpawn => {
            TirTypeErrorInitSuspendNotAllowed {
                declaration: declaration,
                is_client: is_client,
                operation: "spawn",
                via: via,
            }
        },
        InitEffectAwait => {
            TirTypeErrorInitSuspendNotAllowed {
                declaration: declaration,
                is_client: is_client,
                operation: "await",
                via: via,
            }
        },
    };
    [(source_map.expr_span(anchor), error)]
}
