// port: baml_type/src/decl_cycles.rs @ d9be6853b
//
// Type-alias recursion detection and declaration cycle diagnostics:
// `find_invalid_alias_cycles` (aliases with no finite value) and
// `find_invalid_class_cycles` (classes whose required fields form a cycle).
//
// Rust's `HashMap<DeclName, _>` is `map<DeclName, _>` and `HashSet<DeclName>`
// is `map<DeclName, bool>` (a DeclName class is hashable structurally).
//
// Restructured (BAML forces it):
// - Rust's derived `Ord` on `QualifiedTypeName` sorts Tarjan's nodes; BAML
//   has no derived `Compare` for classes; `cmp_decl_name` (ord.baml) spells it out.
// - Graph walks whose depth is the length of a declaration chain (Tarjan's
//   `strong_connect`, the alias chain followed by
//   `extract_required_class_deps`, and `has_cycle`) use an explicit work
//   stack instead of recursion. Walks over one type's nesting stay recursive,
//   as in lib.baml.
//
// The tests also call `ResolvedAliases::from_aliases`, `has_cycle` and
// `ty_has_cycle` (runtime_ty.baml).

// ═══════════════════════════════════════════════════════════════════════════
// INVALID CYCLE DETECTION (Tarjan's SCC + structural edges)
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/decl_cycles.rs::find_invalid_alias_cycles @ d9be6853b
// The aliases that should receive cycle diagnostics: every member of an
// alias SCC that has a member with no finite value.
function find_invalid_alias_cycles(aliases: map<DeclName, Ty>) -> map<DeclName, bool> throws never {
    let graph = build_alias_graph(aliases);
    let sccs = Tarjan.components(graph);
    let productive = productive_aliases(aliases);

    let invalid: map<DeclName, bool> = {};
    for (let scc in sccs) {
        if (
            !scc.every((name) -> {
                productive.has(name)
            })
        ) {
            for (let name in scc) {
                invalid.set(name, true);
            }
        }
    }
    invalid
}

// port: baml_type/src/decl_cycles.rs::build_alias_graph @ d9be6853b
// Each alias to every alias its target names, guarded or not.
function build_alias_graph(
    aliases: map<DeclName, Ty>,
) -> map<DeclName, map<DeclName, bool>> throws never {
    let graph: map<DeclName, map<DeclName, bool>> = {};
    for (let alias_name in aliases.keys()) {
        let (let deps, let guarded) = extract_type_alias_deps(aliases[alias_name], aliases);
        for (let name in guarded.keys()) {
            deps.set(name, true);
        }
        graph.set(alias_name, deps);
    }
    graph
}

// port: baml_type/src/decl_cycles.rs::productive_aliases @ d9be6853b
// The aliases that have a finite value, as a least fixpoint: an alias is
// productive once its target is, given the aliases already known productive.
function productive_aliases(aliases: map<DeclName, Ty>) -> map<DeclName, bool> throws never {
    let known: map<DeclName, bool> = {};
    while (true) {
        let found = aliases.keys().filter((name) -> {
            !known.has(name) && productive(aliases[name], aliases, known)
        });
        if (!found) {
            return known;
        }
        for (let name in found) {
            known.set(name, true);
        }
    }
}

// port: baml_type/src/decl_cycles.rs::productive_aliases::productive @ d9be6853b
// Whether `ty` has a finite value when the aliases in `known` do.
function productive(
    ty: Ty,
    aliases: map<DeclName, Ty>,
    known: map<DeclName, bool>,
) -> bool throws never {
    match (ty) {
        let alias: TyTypeAlias => !aliases.has(alias.name) || known.has(alias.name),
        let u: TyUnion => {
            u.members.some((m) -> {
                productive(m, aliases, known)
            })
        },
        let t: TyTuple => {
            t.items.every((e) -> {
                productive(e, aliases, known)
            })
        },
        TyNever => false,
        _ => true,
    }
}

// port: baml_type/src/decl_cycles.rs::extract_type_alias_deps @ d9be6853b
// The aliases `ty` names, split into (unguarded, guarded): a reference under
// a list, map or tuple is guarded.
function extract_type_alias_deps(
    ty: Ty,
    aliases: map<DeclName, Ty>,
) -> (map<DeclName, bool>, map<DeclName, bool>) throws never {
    let unguarded: map<DeclName, bool> = {};
    let guarded: map<DeclName, bool> = {};
    visit(ty, aliases, unguarded, guarded, false);
    (unguarded, guarded)
}

// port: baml_type/src/decl_cycles.rs::extract_type_alias_deps::visit @ d9be6853b
// Note: like Rust, this does not look inside `Future`.
function visit(
    ty: Ty,
    aliases: map<DeclName, Ty>,
    unguarded: map<DeclName, bool>,
    guarded: map<DeclName, bool>,
    in_guard: bool,
) -> void throws never {
    let same = (child: Ty) -> {
        visit(child, aliases, unguarded, guarded, in_guard)
    };
    let guard = (child: Ty) -> {
        visit(child, aliases, unguarded, guarded, true)
    };
    match (ty) {
        let alias: TyTypeAlias if aliases.has(alias.name) => {
            if (in_guard) {
                guarded.set(alias.name, true);
            } else {
                unguarded.set(alias.name, true);
            }
        },
        let l: TyList => guard(l.elem),
        let m: TyMap => {
            guard(m.key);
            guard(m.value)
        },
        let u: TyUnion => u.members.for_each(same),
        let t: TyTuple => t.items.for_each(guard),
        // Nominal type args are pass-through for cycle classification, so
        // generic arguments inherit the surrounding context.
        let c: TyClass => c.args.for_each(same),
        let i: TyInterface => {
            i.args.for_each(same);
            i.associated_types.for_each((binding) -> {
                same(binding.ty)
            })
        },
        let p: TyAssociatedTypeProjection => {
            same(p.base);
            tys(p.interface_).for_each(same)
        },
        let f: TyFunction => {
            f.params.for_each((param) -> {
                same(param.ty)
            });
            same(f.ret);
            same(f.throws_)
        },
        _ => {},
    }
}

// ── Tarjan's SCC ─────────────────────────────────────────────────────────────
//
// Deterministic ordering via sorted traversal, component reversal, and
// rotation to the minimum element.

// port: baml_type/src/decl_cycles.rs::Tarjan::UNVISITED @ d9be6853b
// Rust uses `usize::MAX`; any index Tarjan never assigns works.
const TARJAN_UNVISITED = -1;

// port: baml_type/src/decl_cycles.rs::NodeState @ d9be6853b
// State of each node for Tarjan's algorithm.
class NodeState {
    index: int,
    low_link: int,
    on_stack: bool,
}

// One `strong_connect` call in progress: the node, its sorted successors and
// how many of them it has looked at. Replaces Rust's recursion.
class TarjanFrame {
    node_id: DeclName,
    node: NodeState,
    successors: DeclName[],
    next: int,
}

// port: baml_type/src/decl_cycles.rs::Tarjan @ d9be6853b
// Tarjan's strongly connected components algorithm. Only returns real cycles
// (multi-node SCCs or single nodes with self-loops), sorted
// deterministically. The `components` field is `components_value` (it would
// clash with the constructor).
class Tarjan {
    graph: map<DeclName, map<DeclName, bool>>,
    index: int,
    stack: DeclName[],
    state: map<DeclName, NodeState>,
    components_value: DeclName[][],

    // port: baml_type/src/decl_cycles.rs::Tarjan::components @ d9be6853b
    function components(graph: map<DeclName, map<DeclName, bool>>) -> DeclName[][] throws never {
        let state: map<DeclName, NodeState> = {};
        for (let node in graph.keys()) {
            state.set(
                node,
                NodeState { index: TARJAN_UNVISITED, low_link: TARJAN_UNVISITED, on_stack: false },
            );
        }
        let tarjan = Tarjan { graph: graph, index: 0, stack: [], state: state, components_value: [] };

        // Sort nodes for deterministic traversal order.
        let nodes = graph.keys().sort_by(cmp_decl_name);
        for (let node in nodes) {
            if (tarjan.state[node].index == TARJAN_UNVISITED) {
                tarjan.strong_connect(node);
            }
        }

        // Sort components by first element for deterministic output.
        tarjan.components_value.sort_by((a, b) -> {
            cmp_decl_name(a[0], b[0])
        })
    }

    // port: baml_type/src/decl_cycles.rs::Tarjan::strong_connect @ d9be6853b
    // Rust recurses into each unvisited successor; here each pending call is
    // a `TarjanFrame` and a finished frame folds its low link into its
    // caller's, as the recursive call's return does.
    function strong_connect(self, node_id: DeclName) -> void throws never {
        let frames = [self.enter(node_id)];
        while (frames.length() > 0) {
            let frame = frames[frames.length() - 1];
            if (frame.next < frame.successors.length()) {
                let successor_id = frame.successors[frame.next];
                frame.next += 1;
                let successor = self.state[successor_id];
                if (successor.index == TARJAN_UNVISITED) {
                    frames.push(self.enter(successor_id));
                } else if (successor.on_stack) {
                    frame.node.low_link
                        = if (successor.index < frame.node.low_link) {
                            successor.index
                        } else {
                            frame.node.low_link
                        };
                }
                continue;
            }
            frames.pop();
            self.finish(frame.node_id, frame.node);
            if (frames.length() > 0) {
                let caller = frames[frames.length() - 1].node;
                let low_link = self.state[frame.node_id].low_link;
                caller.low_link
                    = if (low_link < caller.low_link) {
                        low_link
                    } else {
                        caller.low_link
                    };
            }
        }
    }

    // The head of `strong_connect`: number the node, push it, and list its
    // successors in sorted order.
    function enter(self, node_id: DeclName) -> TarjanFrame throws never {
        let node = NodeState { index: self.index, low_link: self.index, on_stack: true };
        self.index += 1;
        self.state.set(node_id, NodeState { ...node });
        self.stack.push(node_id);

        // Sort successors for deterministic DFS order.
        let successors = self.graph[node_id].keys().sort_by(cmp_decl_name);
        TarjanFrame { node_id: node_id, node: node, successors: successors, next: 0 }
    }

    // The tail of `strong_connect`: record the node's final state and, at an
    // SCC root, pop the component and keep it if it is a real cycle.
    function finish(self, node_id: DeclName, node: NodeState) -> void throws never {
        self.state.set(node_id, NodeState { ...node });

        if (node.low_link != node.index) {
            return;
        }
        let component: DeclName[] = [];
        while let top: DeclName = self.stack.pop() {
            self.state[top].on_stack = false;
            component.push(top);
            if (top == node_id) {
                break;
            }
        }

        // Reverse: stack pop order to DFS visitation order.
        component = component.reverse();

        // Only keep real cycles: multi-node or single node with self-loop.
        let is_cycle = component.length() > 1 || (component.length() == 1 && self.graph[node_id].has(node_id));
        if (!is_cycle) {
            return;
        }
        // Rotate to start at the lexicographically smallest element for
        // deterministic cycle paths.
        let min_idx = 0;
        for (let i = 1; i < component.length(); i += 1) {
            if (cmp_decl_name(component[i], component[min_idx]) == baml.ops.Ordering.Less) {
                min_idx = i;
            }
        }
        self.components_value.push(
            component.slice(min_idx, component.length()).concat(component.slice(0, min_idx)),
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLASS REQUIRED-FIELD CYCLE DETECTION
// ═══════════════════════════════════════════════════════════════════════════
//
// Classes with required (non-optional, non-list, non-map) fields that form a
// cycle are impossible to construct at runtime. Unlike type alias cycles,
// there is no structural guard exemption: every SCC found is an error.

// port: baml_type/src/decl_cycles.rs::ClassCycleInfo @ d9be6853b
// A class cycle: the classes participating, in cycle order.
class ClassCycleInfo {
    members: DeclName[],

    // port: baml_type/src/decl_cycles.rs::ClassCycleInfo::cycle_path @ d9be6853b
    // The cycle as a path, `A -> B -> A`, with each head spelled by `render`
    // (a compile-time head has no spelling of its own; the caller supplies
    // the viewpoint).
    function cycle_path(self, render: (DeclName) -> string) -> string {
        if (self.members.length() == 1) {
            return render(self.members[0]);
        }
        self.members.concat(self.members.slice(0, 1)).map(render).join(" -> ")
    }
}

// port: baml_type/src/decl_cycles.rs::find_invalid_class_cycles @ d9be6853b
// The classes in unconstructable required-field cycles, one `ClassCycleInfo`
// per SCC. A required field is one that is NOT optional, NOT a list and NOT a
// map: those can be null or empty, breaking the construction chain.
function find_invalid_class_cycles(
    class_fields: map<DeclName, (string, Ty)[]>,
    type_aliases: map<DeclName, Ty>,
) -> ClassCycleInfo[] throws never {
    let graph = build_class_graph(class_fields, type_aliases);
    Tarjan.components(graph).map((scc) -> {
        ClassCycleInfo { members: scc }
    })
}

// port: baml_type/src/decl_cycles.rs::build_class_graph @ d9be6853b
// A dependency graph of classes based on required field types. Every class
// is in the graph, even with no required deps.
function build_class_graph(
    class_fields: map<DeclName, (string, Ty)[]>,
    type_aliases: map<DeclName, Ty>,
) -> map<DeclName, map<DeclName, bool>> throws never {
    let graph: map<DeclName, map<DeclName, bool>> = {};
    for (let class_name in class_fields.keys()) {
        let deps: map<DeclName, bool> = {};
        for (let field in class_fields[class_name]) {
            let field_deps = extract_required_class_deps(field.1, class_fields, type_aliases, false, false);
            for (let dep in field_deps.keys()) {
                deps.set(dep, true);
            }
        }
        graph.set(class_name, deps);
    }
    graph
}

// One `extract_required_class_deps` call in progress: the child types still
// to walk (in the context `in_list_or_map`), the deps each walked child
// produced, the deps found directly, and the alias to drop from `visiting`
// when the call returns.
class RequiredDepsFrame {
    children: Ty[],
    in_list_or_map: bool,
    is_union: bool,
    alias: DeclName?,
    own: map<DeclName, bool>,
    results: map<DeclName, bool>[],
}

// port: baml_type/src/decl_cycles.rs::extract_required_class_deps @ d9be6853b
// The required class dependencies of a field type. A class reference is
// required only if it is NOT behind Optional, List, or Map. Type aliases are
// resolved transparently.
//
// Rust recurses, following alias chains, and fills a `deps` out-param with a
// `visiting` set threaded through. Here the deps are returned, `visiting` is
// local, and each pending call is a `RequiredDepsFrame` on an explicit stack.
function extract_required_class_deps(
    ty: Ty,
    class_fields: map<DeclName, (string, Ty)[]>,
    type_aliases: map<DeclName, Ty>,
    optional: bool,
    in_list_or_map: bool,
) -> map<DeclName, bool> throws never {
    let visiting: map<DeclName, bool> = {};
    let frames = [required_deps_frame(ty, class_fields, type_aliases, optional, in_list_or_map, visiting)];
    while (true) {
        let frame = frames[frames.length() - 1];
        if (frame.results.length() < frame.children.length()) {
            frames.push(
                required_deps_frame(
                    frame.children[frame.results.length()],
                    class_fields,
                    type_aliases,
                    optional,
                    frame.in_list_or_map,
                    visiting,
                ),
            );
            continue;
        }
        frames.pop();
        if let alias: DeclName = frame.alias {
            visiting.delete(alias);
        }
        let deps = required_deps_result(frame);
        if (!frames) {
            return deps;
        }
        frames[frames.length() - 1].results.push(deps);
    }
}

// The match head of `extract_required_class_deps`: what one call finds
// directly and which children it walks, in which context.
function required_deps_frame(
    ty: Ty,
    class_fields: map<DeclName, (string, Ty)[]>,
    type_aliases: map<DeclName, Ty>,
    optional: bool,
    in_list_or_map: bool,
    visiting: map<DeclName, bool>,
) -> RequiredDepsFrame throws never {
    let frame = RequiredDepsFrame {
        children: [],
        in_list_or_map: in_list_or_map,
        is_union: false,
        alias: null,
        own: {},
        results: [],
    };
    let required = !optional && !in_list_or_map;
    match (ty) {
        // Only add if the field is truly required.
        let c: TyClass => {
            if (required && class_fields.has(c.name)) {
                frame.own.set(c.name, true);
            }
        },
        // Resolve through type aliases (only if still required context).
        let a: TyTypeAlias => {
            if (required && !visiting.has(a.name)) {
                if let alias_ty: Ty = type_aliases.get(a.name) {
                    visiting.set(a.name, true);
                    frame.alias = a.name;
                    frame.children = [alias_ty];
                }
            }
        },
        // `T?` lowers to `Union([T, Null])`, so optionals are handled by the
        // union arm, which yields no hard dependency (Null breaks it).
        // A list or map breaks the hard dependency (it can be empty).
        let l: TyList => {
            frame.children = [l.elem];
            frame.in_list_or_map = true;
        },
        let m: TyMap => {
            frame.children = [m.key, m.value];
            frame.in_list_or_map = true;
        },
        // Union: only a hard dependency if ALL variants lead to the same
        // class. If any variant provides an alternative (e.g. string), the
        // cycle is broken.
        let u: TyUnion => {
            frame.children = u.members;
            frame.is_union = true;
        },
        let t: TyTuple => {
            frame.children = t.items;
        },
        _ => {},
    }
    frame
}

// The match tail of `extract_required_class_deps`: a union adds its
// variants' deps only if every variant produced the same single dep; every
// other type adds all its children's.
function required_deps_result(frame: RequiredDepsFrame) -> map<DeclName, bool> throws never {
    if (frame.is_union) {
        let first = frame.results.at(0)
            ?? return {};
        if (
            first.length() == 1
                && frame.results.every((d) -> {
                    d == first
                })
        ) {
            return first;
        }
        return {};
    }
    let deps = frame.own;
    for (let result in frame.results) {
        for (let dep in result.keys()) {
            deps.set(dep, true);
        }
    }
    deps
}
