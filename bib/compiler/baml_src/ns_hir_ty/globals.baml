// port: baml_compiler2_hir_ty/src/globals.rs @ d9be6853b
//
// Global variables: what a top-level binding needs before its initializer
// can run, and the order `$init` runs the initializers in. A global `a`
// depends on a global `b` of the same package when `a`'s initializer refers
// to `b`, or refers to a function whose body (or parameter defaults) refers
// to `b`, transitively (Go's package-initialization rule). References come
// from inference's resolution tables, never from spellings, and the walk
// stays inside the package. Globals run in dependency order, independent
// ones in source order (file path, then position); a cycle is E0181,
// reported once, at the first global of the cycle in source order.
//
// Restructured:
// - The tracked queries (`let_init_refs`, `function_init_refs`,
//   `global_init_deps`, `package_global_init_plan`) are `TrackedMemo`s on
//   `db.ty_memo`; `package_global_init_plan` is keyed by the root id.
// - `ExprId`, `LetLoc`, `FunctionLoc` and `SourceRoot` are `int`s; the
//   `(ExprId, Loc)` pairs of `InitRefs` are tuples. `GlobalDeps` (a newtype
//   over `Vec<GlobalDep>`) is an alias of `GlobalDep[]`.
// - No root is served from an interface, so every `GlobalRoot` binding is a
//   source let: `body_init_refs` has no `DeclRef::External` case to skip.
// - `source_key`'s `PathBuf` is the path's `/`-separated components, compared
//   as `Path`'s `Ord` compares them (`cmp_source_key`).
// - `plan_global_init`'s `BTreeSet` of ready components is an array whose
//   smallest `(first member, component)` is taken each round; Tarjan's
//   `usize::MAX` "unvisited" is `-1`.

// port: baml_compiler2_hir_ty/src/globals.rs::is_source_global @ d9be6853b
// Whether `binding` is a global variable written in source, as opposed to a
// `client` declaration or a Session's persisted binding. Only source globals
// can be annotated, and only their initializers are held to the
// initializer-is-an-expression rules (no top-level `return`).
function is_source_global(db: root.hir.Db, binding: int) -> bool throws never {
    root.hir.let_data(db, binding).origin == root.ast.LetOrigin.Source
        && !root.hir.is_session_submission(db, db.let_locs.get(binding).file)
}

// port: baml_compiler2_hir_ty/src/globals.rs::global_value_type @ d9be6853b
// The type every reader of global `binding` sees: its annotation when it has
// one, else its initializer's type widened as at any binding site (`let n =
// 5` is an `int`, not the literal `5`). Null when the initializer is missing
// or was not typed.
function global_value_type(db: root.hir.Db, binding: int) -> root.types.Ty? throws never {
    let declared = let_declared_type(db, binding);
    if (declared != null) {
        return declared;
    }
    let body = match (root.hir.let_body(db, binding)) {
        let b: root.hir.LetBodyExpr => b.value,
        root.hir.LetBodyMissing => {
            return null;
        },
    };
    let root_expr = body.root_expr
        ?? return null;
    let inference = infer_body(db, root.hir.BodyOwnerIdLet { value: binding });
    let root_ty = inference.type_of_expr.get(root_expr)
        ?? return null;
    root.types.widen_fresh(root_ty)
}

// port: baml_compiler2_hir_ty/src/globals.rs::global_int_literal @ d9be6853b
// The int literal an unannotated global's initializer types as, if it does.
function global_int_literal(db: root.hir.Db, binding: int) -> int? throws never {
    if (let_declared_type(db, binding) != null) {
        return null;
    }
    let body = match (root.hir.let_body(db, binding)) {
        let b: root.hir.LetBodyExpr => b.value,
        root.hir.LetBodyMissing => {
            return null;
        },
    };
    let root_expr = body.root_expr
        ?? return null;
    let inference = infer_body(db, root.hir.BodyOwnerIdLet { value: binding });
    match (inference.type_of_expr.get(root_expr)) {
        let l: root.types.TyLiteral => match (l.value) {
            let i: root.base.LiteralInt => i.value,
            _ => null,
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/globals.rs::InitRefs @ d9be6853b
// What one body refers to that can matter to initialization order.
class InitRefs {
    // Globals read, each at the first expression (arena order) that reads
    // it: `(expr, let loc)`.
    globals: (int, int)[],
    // Same-package functions referred to (called, or taken as a value),
    // each at the first expression that does: `(expr, function loc)`.
    functions: (int, int)[],
}

// port: baml_compiler2_hir_ty/src/globals.rs::body_init_refs @ d9be6853b
function body_init_refs(
    db: root.hir.Db,
    owner: root.hir.BodyOwnerId,
    package: int,
    out: InitRefs,
) -> void throws never {
    let inference = infer_body(db, owner);
    let same_package = (file: int) -> bool {
        root.hir.file_package(db, file).root_id == package
    };
    for (let expr in inference.global_roots.keys()) {
        let binding = inference.global_roots[expr].binding;
        if (same_package(db.let_locs.get(binding).file)) {
            out.globals.push((expr, binding));
        }
    }
    let push_function = (expr: int, resolution: MemberResolution) -> void {
        let function_ = resolved_function(resolution);
        if (function_ != null && same_package(db.function_locs.get(function_).file)) {
            out.functions.push((expr, function_));
        }
    };
    for (let expr in inference.member_resolutions.keys()) {
        push_function(expr, inference.member_resolutions[expr]);
    }
    // A value-rooted ladder (`x.method().field`) resolves its intermediate
    // segments here rather than in `member_resolutions`.
    for (let expr in inference.path_resolutions.keys()) {
        for (let segment in inference.path_resolutions[expr].segments) {
            let resolution = segment.resolution;
            if (resolution != null) {
                push_function(expr, resolution);
            }
        }
    }
}

// port: baml_compiler2_hir_ty/src/globals.rs::finish_refs @ d9be6853b
// Arena order is deterministic (and close to source order), so the anchor
// kept for each target is the first place the body names it.
function finish_refs(refs: InitRefs) -> InitRefs throws never {
    let first_per_target = (pairs: (int, int)[]) -> (int, int)[] {
        let seen: map<int, bool> = {};
        pairs
            .sort_by_key((pair) -> {
                pair.0
            })
            .filter((pair) -> {
                if (seen.has(pair.1)) {
                    false
                } else {
                    seen[pair.1] = true;
                    true
                }
            })
    };
    InitRefs {
        globals: first_per_target(refs.globals),
        functions: first_per_target(refs.functions),
    }
}

// port: baml_compiler2_hir_ty/src/globals.rs::let_init_refs @ d9be6853b
// What a global's initializer refers to.
function let_init_refs(db: root.hir.Db, binding: int) -> InitRefs throws never {
    db.ty_memo.let_init_refs.get(db.cycles, binding, () -> {
        let package = root.hir.file_package(db, db.let_locs.get(binding).file).root_id;
        let refs = InitRefs { globals: [], functions: [] };
        body_init_refs(db, root.hir.BodyOwnerIdLet { value: binding }, package, refs);
        finish_refs(refs)
    })
}

// port: baml_compiler2_hir_ty/src/globals.rs::function_init_refs @ d9be6853b
// What a function refers to when it runs: its body and, because a call
// evaluates them, its parameter defaults.
function function_init_refs(db: root.hir.Db, function_: int) -> InitRefs throws never {
    db.ty_memo.function_init_refs.get(db.cycles, function_, () -> {
        let package = root.hir.file_package(db, db.function_locs.get(function_).file).root_id;
        let refs = InitRefs { globals: [], functions: [] };
        body_init_refs(db, root.hir.BodyOwnerIdFunction { value: function_ }, package, refs);
        let has_defaults = root.hir.function_parameter_defaults(db, function_).params.some((default_) -> {
            default_ != null
        });
        if (has_defaults) {
            body_init_refs(db, root.hir.BodyOwnerIdParameterDefaults { value: function_ }, package, refs);
        }
        finish_refs(refs)
    })
}

// port: baml_compiler2_hir_ty/src/globals.rs::GlobalDep @ d9be6853b
// One global another global's initializer needs, and how it is reached.
class GlobalDep {
    global: int,
    // The expression in the DEPENDENT initializer the path starts at: the
    // global's own read, or the call/reference of the first function.
    anchor: int,
    // The functions the path passes through, in call order (empty when the
    // initializer reads the global directly).
    via: int[],
}

// port: baml_compiler2_hir_ty/src/globals.rs::GlobalDeps @ d9be6853b
type GlobalDeps = GlobalDep[];

// port: baml_compiler2_hir_ty/src/globals.rs::global_init_deps @ d9be6853b
// The same-package globals `binding`'s initializer needs initialized first,
// each with the shortest path that needs it. May include `binding` itself.
// A breadth-first walk over the memoized per-body reference tables, on an
// explicit queue: recursion in user code is a revisit, not a query cycle.
function global_init_deps(db: root.hir.Db, binding: int) -> GlobalDeps throws never {
    db.ty_memo.global_init_deps.get(db.cycles, binding, () -> {
        let refs = let_init_refs(db, binding);
        let deps: GlobalDep[] = [];
        let seen_globals: map<int, bool> = {};
        for (let (let anchor, let global) in refs.globals) {
            if (!seen_globals.has(global)) {
                seen_globals[global] = true;
                deps.push(GlobalDep { global: global, anchor: anchor, via: [] });
            }
        }
        let visited: map<int, bool> = {};
        let queue: (int, int, int[])[] = [];
        for (let (let anchor, let function_) in refs.functions) {
            if (!visited.has(function_)) {
                visited[function_] = true;
                queue.push((function_, anchor, [function_]));
            }
        }
        let head = 0;
        while (head < queue.length()) {
            let (let function_, let anchor, let via) = queue[head];
            head += 1;
            let function_refs = function_init_refs(db, function_);
            for (let (_, let global) in function_refs.globals) {
                if (!seen_globals.has(global)) {
                    seen_globals[global] = true;
                    deps.push(
                        GlobalDep {
                            global: global,
                            anchor: anchor,
                            via: via.slice(0, via.length()),
                        },
                    );
                }
            }
            for (let (_, let callee) in function_refs.functions) {
                if (!visited.has(callee)) {
                    visited[callee] = true;
                    queue.push((callee, anchor, via.concat([callee])));
                }
            }
        }
        deps
    })
}

// port: baml_compiler2_hir_ty/src/globals.rs::GlobalCycle @ d9be6853b
// One initialization cycle, reported at its first global in source order.
class GlobalCycle {
    // The global the cycle is reported at.
    global: int,
    // Where in that global's initializer the cycle starts.
    anchor: int,
    // The cycle as names, starting and ending at `global`, with every
    // function it passes through.
    chain: string[],
}

// port: baml_compiler2_hir_ty/src/globals.rs::GlobalInitPlan @ d9be6853b
// How a set of globals is initialized: the order, and any cycles.
class GlobalInitPlan {
    // The order `$init` evaluates the initializers in. Every global of the
    // set appears once; members of a cycle (a compile error) are placed in
    // source order after everything they need outside the cycle.
    order: int[],
    cycles: GlobalCycle[],
}

// port: baml_compiler2_hir_ty/src/globals.rs::package_global_init_plan @ d9be6853b
// The initialization plan for every global of the package `root_id` (the
// package `$init`).
function package_global_init_plan(db: root.hir.Db, root_id: int) -> GlobalInitPlan throws never {
    db.ty_memo.package_global_init_plan.get(db.cycles, root_id, () -> {
        let lets = db.source_root(root_id).files.flat_map((file) -> {
            root.hir.file_lets(db, file)
        });
        plan_global_init(db, lets)
    })
}

// port: baml_compiler2_hir_ty/src/globals.rs::source_key @ d9be6853b
// Source order: file path, then position. Independent of the order files
// were added to the database. The path is its components (`PathBuf`'s
// order).
function source_key(db: root.hir.Db, binding: int) -> (string[], int) throws never {
    let span = root.hir.let_source_map(db, binding).span;
    let path = db.file(db.let_locs.get(binding).file).path;
    (
        path.split("/").filter((component) -> {
            component != "" && component != "."
        }),
        span.start,
    )
}

// port: baml_compiler2_hir_ty/src/globals.rs::source_key @ d9be6853b
// `source_key`'s order: Rust's derived tuple `Ord` over `(PathBuf, u32)`,
// where a path compares component by component.
function cmp_source_key(a: (string[], int), b: (string[], int)) -> baml.ops.Ordering throws never {
    let (let a_path, let a_start) = a;
    let (let b_path, let b_start) = b;
    for (let i = 0; i < a_path.length() && i < b_path.length(); i += 1) {
        let by_component = a_path[i].cmp(b_path[i]);
        if (by_component != baml.ops.Ordering.Equal) {
            return by_component;
        }
    }
    let by_length = a_path.length().cmp(b_path.length());
    if (by_length != baml.ops.Ordering.Equal) {
        return by_length;
    }
    a_start.cmp(b_start)
}

// port: baml_compiler2_hir_ty/src/globals.rs::plan_global_init @ d9be6853b
// The initialization plan for `lets`: dependencies on globals outside the
// set are already satisfied (an earlier package's `$init`, an earlier
// Session submission) and impose no order.
function plan_global_init(db: root.hir.Db, lets: int[]) -> GlobalInitPlan throws never {
    let keyed = lets.map((binding) -> {
        (source_key(db, binding), binding)
    });
    let by_key = keyed.sort_by((a, b) -> {
        cmp_source_key(a.0, b.0)
    });
    let sorted: int[] = [];
    for (let (_, let binding) in by_key) {
        if (sorted.at(sorted.length() - 1) != binding) {
            sorted.push(binding);
        }
    }
    let index: map<int, int> = {};
    for (let position = 0; position < sorted.length(); position += 1) {
        index[sorted[position]] = position;
    }
    // Edges in source-position space, restricted to the set.
    let edges: int[][] = sorted.map((binding) -> {
        global_init_deps(db, binding).filter_map((dep) -> {
            index.get(dep.global)
        })
    });

    let components = strongly_connected_components(edges);
    let component_of: int[] = sorted.map((_) -> {
        0
    });
    for (let component = 0; component < components.length(); component += 1) {
        for (let member in components[component]) {
            component_of[member] = component;
        }
    }

    // Kahn's algorithm over the condensation, always taking the ready
    // component whose first member comes first in source order.
    let needs: map<int, bool>[] = components.map((_) -> {
        let set: map<int, bool> = {};
        set
    });
    let needed_by: int[][] = components.map((_) -> {
        let list: int[] = [];
        list
    });
    for (let from = 0; from < edges.length(); from += 1) {
        for (let to in edges[from]) {
            let from_c = component_of[from];
            let to_c = component_of[to];
            if (from_c != to_c && !needs[from_c].has(to_c)) {
                needs[from_c][to_c] = true;
                needed_by[to_c].push(from_c);
            }
        }
    }
    // Members are sorted, so a component's first member is its earliest in
    // source order, and distinct components have distinct first members: the
    // ready set orders by first member alone.
    let ready: int[] = [];
    for (let component = 0; component < components.length(); component += 1) {
        if (needs[component].length() == 0) {
            ready.push(component);
        }
    }
    let order: int[] = [];
    let cycles: GlobalCycle[] = [];
    while (ready.length() > 0) {
        let pick = 0;
        for (let i = 1; i < ready.length(); i += 1) {
            if (components[ready[i]][0] < components[ready[pick]][0]) {
                pick = i;
            }
        }
        let component = ready[pick];
        ready.remove_at(pick);
        let members = components[component];
        let cyclic = members.length() > 1 || edges[members[0]].includes(members[0]);
        if (cyclic) {
            cycles.push(describe_cycle(db, sorted, index, members));
        }
        for (let member in members) {
            order.push(sorted[member]);
        }
        for (let dependent in needed_by[component]) {
            needs[dependent].delete(component);
            if (needs[dependent].length() == 0) {
                ready.push(dependent);
            }
        }
    }
    GlobalInitPlan { order: order, cycles: cycles }
}

// port: baml_compiler2_hir_ty/src/globals.rs::strongly_connected_components @ d9be6853b
// Tarjan's algorithm, iterative. Each component's members are sorted, so for
// globals a component's first member is its earliest in source order.
function strongly_connected_components(edges: int[][]) -> int[][] throws never {
    let n = edges.length();
    let index_of: int[] = edges.map((_) -> {
        -1
    });
    let lowlink: int[] = edges.map((_) -> {
        0
    });
    let on_stack: bool[] = edges.map((_) -> {
        false
    });
    let stack: int[] = [];
    let components: int[][] = [];
    let next_index = 0;
    for (let start = 0; start < n; start += 1) {
        if (index_of[start] != -1) {
            continue;
        }
        // (node, next edge to visit)
        let work: (int, int)[] = [(start, 0)];
        index_of[start] = next_index;
        lowlink[start] = next_index;
        next_index += 1;
        stack.push(start);
        on_stack[start] = true;
        while (work.length() > 0) {
            let top = work.length() - 1;
            let (let node, let edge) = work[top];
            let target = edges[node].at(edge);
            if (target != null) {
                work[top] = (node, edge + 1);
                if (index_of[target] == -1) {
                    index_of[target] = next_index;
                    lowlink[target] = next_index;
                    next_index += 1;
                    stack.push(target);
                    on_stack[target] = true;
                    work.push((target, 0));
                } else if (on_stack[target]) {
                    if (index_of[target] < lowlink[node]) {
                        lowlink[node] = index_of[target];
                    }
                }
                continue;
            }
            work.pop();
            let parent = work.at(work.length() - 1);
            if (parent != null) {
                if (lowlink[node] < lowlink[parent.0]) {
                    lowlink[parent.0] = lowlink[node];
                }
            }
            if (lowlink[node] == index_of[node]) {
                let members: int[] = [];
                while let member: int = stack.pop() {
                    on_stack[member] = false;
                    members.push(member);
                    if (member == node) {
                        break;
                    }
                }
                components.push(
                    members.sort_by_key((member) -> {
                        member
                    }),
                );
            }
        }
    }
    components
}

// port: baml_compiler2_hir_ty/src/globals.rs::describe_cycle @ d9be6853b
// The cycle through `members` (one strongly connected component) as the path
// a reader can follow: from its first global, through every function and
// global on the way, back to it.
function describe_cycle(
    db: root.hir.Db,
    sorted: int[],
    index: map<int, int>,
    members: int[],
) -> GlobalCycle throws never {
    let in_component: map<int, bool> = {};
    for (let member in members) {
        in_component[member] = true;
    }
    let start = members[0];
    // Shortest global-to-global path from `start` back to itself, within the
    // component: BFS over dependency hops, remembering the hop taken.
    let parent: map<int, (int, GlobalDep)> = {};
    let queue: int[] = [start];
    let head = 0;
    let closing: (int, GlobalDep)? = null;
    while (closing == null && head < queue.length()) {
        let node = queue[head];
        head += 1;
        for (let dep in global_init_deps(db, sorted[node])) {
            let target = index.get(dep.global);
            if (target == null || !in_component.has(target)) {
                continue;
            }
            if (target == start) {
                closing = (node, dep);
                break;
            }
            if (!parent.has(target)) {
                parent[target] = (node, dep);
                queue.push(target);
            }
        }
    }
    let (let last, let closing_dep) = closing ?? baml.sys.panic("a cyclic component reaches its first member");
    // Rebuild the hops start -> ... -> last, then last -> start.
    let hops: (int, GlobalDep)[] = [(last, closing_dep)];
    let node = last;
    while (node != start) {
        let hop = parent[node];
        hops.push(hop);
        node = hop.0;
    }
    let ordered = hops.reverse();
    let anchor = ordered[0].1.anchor;
    let chain: string[] = [root.hir.let_data(db, sorted[start]).name];
    for (let (_, let dep) in ordered) {
        for (let function_ in dep.via) {
            chain.push(function_display_name(db, function_));
        }
        chain.push(root.hir.let_data(db, dep.global).name);
    }
    GlobalCycle { global: sorted[start], anchor: anchor, chain: chain }
}

// port: baml_compiler2_hir_ty/src/globals.rs::function_display_name @ d9be6853b
// A function as a reader finds it in source: `name`, or `Owner.name` for a
// method.
function function_display_name(db: root.hir.Db, function_: int) -> string throws never {
    let name = root.hir.function_data(db, function_).name;
    match (root.hir.method_owner(db, function_)) {
        let o: root.hir.MethodOwnerClass => `${root.hir.class_data(db, o.value).name}.${name}`,
        let o: root.hir.MethodOwnerInterface => {
            `${root.hir.interface_data(db, o.value).name}.${name}`
        },
        _ => name,
    }
}

// port: baml_compiler2_hir_ty/src/globals.rs::let_init_cycle_diagnostics @ d9be6853b
// E0181 for one global: the initialization cycle it is the reported member
// of, if any.
function let_init_cycle_diagnostics(
    db: root.hir.Db,
    binding: int,
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    let package = root.hir.file_package(db, db.let_locs.get(binding).file).root_id;
    let plan = package_global_init_plan(db, package);
    let cycle = plan.cycles.find((c) -> {
        c.global == binding
    })
        ?? return [];
    let source_map = root.hir.body_source_map(db, root.hir.BodyOwnerIdLet { value: binding });
    let span = if (source_map != null) {
        source_map.expr_span(cycle.anchor)
    } else {
        root.hir.let_source_map(db, binding).name_span
    };
    [(span, TirTypeErrorGlobalInitializationCycle { chain: cycle.chain })]
}

// port: baml_compiler2_hir_ty/src/globals.rs::let_init_throw_diagnostics @ d9be6853b
// E0183 (a warning) for one global variable: its initializer can throw, and
// nothing in it catches the throw. An uncaught throw in `$init` stops the
// engine from being created. Only source globals are judged: a `client`
// constructor may validate its arguments, and a Session binding's throw
// reaches `eval`'s caller.
function let_init_throw_diagnostics(
    db: root.hir.Db,
    binding: int,
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    if (!is_source_global(db, binding)) {
        return [];
    }
    let inference = infer_body(db, root.hir.BodyOwnerIdLet { value: binding });
    if (
        inference.throws_ is root.types.TyNever
            || root.types.contains_ty_where(inference.throws_, (ty) -> {
                ty is root.types.TyError
            })
    ) {
        return [];
    }
    let data = root.hir.let_data(db, binding);
    [
        (
            root.hir.let_source_map(db, binding).name_span,
            TirTypeErrorInitThrowNotHandled {
                declaration: data.name,
                is_client: data.origin == root.ast.LetOrigin.Client,
                thrown: inference.throws_,
            },
        ),
    ]
}
