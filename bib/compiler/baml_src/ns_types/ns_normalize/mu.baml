// port: baml_type/src/normalize/mu.rs @ d9be6853b
//
// μ-canonicalization: the automaton stage that makes canonical forms unique
// representatives of the equirecursive equivalence class. A typestate
// pipeline, Builder -> Built -> Closed -> Minimal -> read-back / render:
// 1. build: intern the term as a term graph (a μ-binder is the knot, a
//    recursion variable a back-edge);
// 2. ε-closure: union members that are unions are ε-edges; per ε-SCC the
//    members become the constructor successors (`type A = A | A[]` is
//    `μX.X[]`, `μX.X` is `never`);
// 3. minimization interleaved with the per-state union algebra, members
//    materialized as closed read-backs for the real subtype checker;
// 4. read-back / render: a deterministic DFS emits the canonical μ-term and
//    each binder's named-cut display.
// A cycle neither an alias name nor a subset cover can cut has no alias-based
// Ty spelling; the renderer then bails and the caller keeps the
// pre-automaton term (sound, less canonical).
//
// Namespace `types.normalize` (Rust's `normalize::mu`): the items keep their
// Rust names, and two of them (collapse_complete_enums,
// collapse_complete_bools) share a name with normalize.rs items.
//
// Restructured:
// - NameId / StrId / LeafId / StateId are ints. Interner keys by value
//   (Rust borrows the input and orders by reference).
// - `Specials` (owned specials the interner borrows for the automaton's
//   lifetime) is gone: the automaton interns the special leaves itself.
// - The two function-local `Tarjan` structs are EpsilonTarjan
//   (epsilon_sccs) and CyclicTarjan (cyclic_states).
// - BTreeSet<StateId> is a sorted, deduplicated `int[]` (id_set) where the
//   order is read, and a `map<int, bool>` where only membership is.
// - minimize groups states by a LocalKey value and by a `[block, ..sig]`
//   key: map iteration follows insertion, so block numbers differ from
//   Rust's BTreeMap order, but the partition (and the smallest-id
//   representative each block merges into) is the same.
// - Tuple-shaped node payloads (`(StrId, StateId)`, the function param
//   triple) are tuples; the hashed LocalKey params use LocalKeyParam.

// port: baml_type/src/normalize/mu.rs::canonicalize_mu @ d9be6853b
// Canonicalize a term containing at least one μ-binder. Falls back to the
// (sound, bottom-up-canonicalized) input when the renderer bails.
function canonicalize_mu(
    term: root.types.NormalTy,
    ctx: root.types.TypeContext,
) -> root.types.NormalTy throws never {
    let out = Builder { binders: [] }.build(term).epsilon_close().minimize_and_absorb(ctx).read_back();
    out ?? term
}

// port: baml_type/src/normalize/mu.rs::canonicalize_mu_with_render @ d9be6853b
// canonicalize_mu plus the root rendering for `normalize`
// (root-unfold-once). The bail fallback renders the input via its interim
// displays.
function canonicalize_mu_with_render(
    term: root.types.NormalTy,
    ctx: root.types.TypeContext,
) -> (root.types.NormalTy, root.types.Ty) throws never {
    let minimal = Builder { binders: [] }.build(term).epsilon_close().minimize_and_absorb(ctx);
    let t = minimal.read_back();
    if (t != null) {
        let r = minimal.render_root();
        if (r != null) {
            return (t, r);
        }
    }
    (term, root.types.into_ty(term))
}

// port: baml_type/src/normalize/mu.rs::BTreeSet<StateId> @ d9be6853b
// A state-id set in ascending order: sorted and deduplicated.
function id_set(xs: int[]) -> int[] throws never {
    let sorted = xs.slice(0, xs.length()).sort_by((a, b) -> {
        a.cmp(b)
    });
    let out: int[] = [];
    for (let x in sorted) {
        if (out.length() == 0 || out[out.length() - 1] != x) {
            out.push(x);
        }
    }
    out
}

// ═══════════════════════════════════════════════════════════════════════════
// INTERNING
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize/mu.rs::Interner @ d9be6853b
// First-encounter interning: one probe per occurrence at build time buys
// integer comparison everywhere after.
class Interner<T extends baml.Hash> {
    ids: map<T, int>,
    values: T[],

    // port: baml_type/src/normalize/mu.rs::Interner::intern @ d9be6853b
    function intern(self, value: T) -> int throws never {
        let existing = self.ids.get(value);
        if (existing != null) {
            return existing;
        }
        let id = self.values.length();
        self.ids.set(value, id);
        self.values.push(value);
        id
    }

    // port: baml_type/src/normalize/mu.rs::Interner::get @ d9be6853b
    function get(self, id: int) -> T throws never {
        self.values[id]
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATON CORE
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize/mu.rs::Node @ d9be6853b
// One term-graph node. Children are state ids (resolve before use); payloads
// are interned ids. Enums get their own id-based kinds so the completeness
// collapse can synthesize an enum state.
class NodeLeaf {
    leaf: int,
}

class NodeEnum {
    name: int,
}

class NodeEnumVariant {
    name: int,
    variant: int,
}

class NodeClass {
    name: int,
    args: int[],
}

class NodeInterface {
    name: int,
    args: int[],
    bindings: (int, int)[],
}

class NodeList {
    inner: int,
}

class NodeMap {
    key: int,
    value: int,
}

class NodeFuture {
    value: int,
    error: int,
}

class NodeUnion {
    members: int[],
}

class NodeTuple {
    items: int[],
}

class NodeFunction {
    params: (int?, root.types.FunctionParamMode, int)[],
    ret: int,
    throws_: int,
}

class NodeProjection {
    base: int,
    interface_: int,
    member: int,
}

type Node = NodeLeaf
    | NodeEnum
    | NodeEnumVariant
    | NodeClass
    | NodeInterface
    | NodeList
    | NodeMap
    | NodeFuture
    | NodeUnion
    | NodeTuple
    | NodeFunction
    | NodeProjection;

// port: baml_type/src/normalize/mu.rs::State @ d9be6853b
class State {
    node: Node,
    // Alias names denoting this state (μ-binder origins; unioned on merge,
    // transferred on redirect).
    names: map<int, bool>,
}

// port: baml_type/src/normalize/mu.rs::Automaton @ d9be6853b
class Automaton {
    states: State[],
    // Redirect chains from ε singleton collapses, minimization merges and
    // binder knot-tying; resolve follows them to the live state.
    redirect: int[],
    names: Interner<root.types.DeclName>,
    strs: Interner<string>,
    leaves: Interner<root.types.NormalTy>,
    // Pre-interned special leaves, so the hot probes are id compares.
    never: int,
    unknown_top: int,
    bool_leaf: int,
    lit_true: int,
    lit_false: int,

    // port: baml_type/src/normalize/mu.rs::Automaton::new @ d9be6853b
    function new() -> Self {
        let leaves = Interner<root.types.NormalTy> { ids: {}, values: [] };
        let never = leaves.intern(root.types.NormalTyNever {});
        let unknown_top = leaves.intern(root.types.NormalTyUnknown {});
        let bool_leaf = leaves.intern(root.types.NormalTyBool {});
        let lit_true = leaves.intern(root.types.NormalTyLiteral { value: root.base.LiteralBool { value: true } });
        let lit_false = leaves.intern(root.types.NormalTyLiteral { value: root.base.LiteralBool { value: false } });
        Automaton {
            states: [],
            redirect: [],
            names: Interner<root.types.DeclName> { ids: {}, values: [] },
            strs: Interner<string> { ids: {}, values: [] },
            leaves: leaves,
            never: never,
            unknown_top: unknown_top,
            bool_leaf: bool_leaf,
            lit_true: lit_true,
            lit_false: lit_false,
        }
    }

    // port: baml_type/src/normalize/mu.rs::Automaton::alloc @ d9be6853b
    function alloc(self, node: Node) -> int throws never {
        let id = self.states.length();
        self.states.push(State { node: node, names: {} });
        self.redirect.push(id);
        id
    }

    // port: baml_type/src/normalize/mu.rs::Automaton::resolve @ d9be6853b
    function resolve(self, s: int) -> int throws never {
        let r = s;
        while (self.redirect[r] != r) {
            r = self.redirect[r];
        }
        r
    }

    // port: baml_type/src/normalize/mu.rs::Automaton::redirect_to @ d9be6853b
    // Redirect `from` to `to`, transferring names.
    function redirect_to(self, from: int, to: int) -> void throws never {
        let names = self.states[from].names;
        self.states[from].names = {};
        let target = self.resolve(to);
        for (let n in names.keys()) {
            self.states[target].names.set(n, true);
        }
        self.redirect[from] = target;
    }

    // port: baml_type/src/normalize/mu.rs::Automaton::node @ d9be6853b
    function node(self, s: int) -> Node throws never {
        self.states[self.resolve(s)].node
    }

    // port: baml_type/src/normalize/mu.rs::Automaton::is_never @ d9be6853b
    function is_never(self, s: int) -> bool throws never {
        match (self.node(s)) {
            let l: NodeLeaf => l.leaf == self.never,
            _ => false,
        }
    }

    // port: baml_type/src/normalize/mu.rs::Automaton::is_unknown_top @ d9be6853b
    function is_unknown_top(self, s: int) -> bool throws never {
        match (self.node(s)) {
            let l: NodeLeaf => l.leaf == self.unknown_top,
            _ => false,
        }
    }

    // port: baml_type/src/normalize/mu.rs::Automaton::representative_name @ d9be6853b
    // The least alias name of `s` (ordered by name, not id), if any.
    function representative_name(self, s: int) -> root.types.DeclName? throws never {
        let best: root.types.DeclName? = null;
        for (let id in self.states[self.resolve(s)].names.keys()) {
            let name = self.names.get(id);
            if (best == null || root.types.cmp_decl_name(name, best) == baml.ops.Ordering.Less) {
                best = name;
            }
        }
        best
    }

    // port: baml_type/src/normalize/mu.rs::Automaton::reachable @ d9be6853b
    // Every state reachable from `root_state`, resolved, ascending.
    function reachable(self, root_state: int) -> int[] throws never {
        let seen: map<int, bool> = {};
        let stack = [self.resolve(root_state)];
        while let s: int = stack.pop() {
            if (seen.has(s)) {
                continue;
            }
            seen.set(s, true);
            for (let c in children(self.node(s))) {
                stack.push(self.resolve(c));
            }
        }
        id_set(seen.keys())
    }
}

// port: baml_type/src/normalize/mu.rs::children @ d9be6853b
// The child state ids of a node, in canonical child order.
function children(node: Node) -> int[] throws never {
    match (node) {
        NodeLeaf | NodeEnum | NodeEnumVariant => [],
        let x: NodeClass => x.args,
        let x: NodeInterface => {
            x.args.concat(
                x.bindings.map((b) -> {
                    b.1
                }),
            )
        },
        let x: NodeList => [x.inner],
        let x: NodeMap => [x.key, x.value],
        let x: NodeFuture => [x.value, x.error],
        let x: NodeUnion => x.members,
        let x: NodeTuple => x.items,
        let x: NodeFunction => {
            x.params
                .map((p) -> {
                    p.2
                })
                .concat([x.ret, x.throws_])
        },
        let x: NodeProjection => [x.base, x.interface_],
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE 1: BUILD
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize/mu.rs::Builder @ d9be6853b
// Interns a canonical term into a fresh automaton; owns the binder stack.
class Builder {
    binders: int[],

    // port: baml_type/src/normalize/mu.rs::Builder::build @ d9be6853b
    function build(self, term: root.types.NormalTy) -> Built throws never {
        let auto = Automaton.new();
        let root_state = self.intern_term(auto, term);
        Built { auto: auto, root_state: root_state }
    }

    // port: baml_type/src/normalize/mu.rs::Builder::intern_term @ d9be6853b
    // A μ-binder ties the knot: its reserved state either becomes the
    // ε-self-loop (a body that is the back-reference itself) or redirects to
    // the body's state, carrying the alias name either way. A recursion
    // variable is an edge to the binder state `index` levels up.
    function intern_term(self, auto: Automaton, term: root.types.NormalTy) -> int throws never {
        let go = (t: root.types.NormalTy) -> int {
            self.intern_term(auto, t)
        };
        match (term) {
            let m: root.types.NormalTyMu => {
                let s = auto.alloc(NodeUnion { members: [] });
                let name = root.types.mu_display(m).name;
                if (name != null) {
                    auto.states[s].names.set(auto.names.intern(name), true);
                }
                self.binders.push(s);
                let b = go(m.body);
                self.binders.pop();
                if (auto.resolve(b) == s) {
                    // `μX.X`: an ε-self-loop, `never` after closure.
                    auto.states[s].node = NodeUnion { members: [s] };
                    s
                } else {
                    auto.redirect_to(s, b);
                    auto.resolve(b)
                }
            },
            let r: root.types.NormalTyRecVar => {
                let i = match (r.var) {
                    let i: int => i,
                    _ => baml.sys.panic("a named-phase RecVar reached the automaton"),
                };
                self.binders[self.binders.length() - 1 - i]
            },
            let e: root.types.NormalTyEnum => {
                auto.alloc(NodeEnum { name: auto.names.intern(e.name) })
            },
            let v: root.types.NormalTyEnumVariant => {
                let qn = auto.names.intern(v.name);
                let variant = auto.strs.intern(v.variant);
                auto.alloc(NodeEnumVariant { name: qn, variant: variant })
            },
            let c: root.types.NormalTyClass => {
                let qn = auto.names.intern(c.name);
                let args = c.args.map(go);
                auto.alloc(NodeClass { name: qn, args: args })
            },
            let i: root.types.NormalTyInterface => {
                let qn = auto.names.intern(i.name);
                let args = i.args.map(go);
                let bindings = i.bindings.map((b) -> {
                    let n = auto.strs.intern(b.name);
                    (n, go(b.ty))
                });
                auto.alloc(NodeInterface { name: qn, args: args, bindings: bindings })
            },
            let l: root.types.NormalTyList => {
                let inner = go(l.elem);
                auto.alloc(NodeList { inner: inner })
            },
            let x: root.types.NormalTyMap => {
                let key = go(x.key);
                let value = go(x.value);
                auto.alloc(NodeMap { key: key, value: value })
            },
            let f: root.types.NormalTyFuture => {
                let value = go(f.value);
                let error = go(f.error);
                auto.alloc(NodeFuture { value: value, error: error })
            },
            let u: root.types.NormalTyUnion => {
                let members = u.members.map(go);
                auto.alloc(NodeUnion { members: members })
            },
            let t: root.types.NormalTyTuple => {
                let items = t.items.map(go);
                auto.alloc(NodeTuple { items: items })
            },
            let f: root.types.NormalTyFunction => {
                let params = f.params.map((p) -> {
                    let pname = p.name;
                    let n = if (pname != null) {
                        auto.strs.intern(pname)
                    } else {
                        null
                    };
                    (n, p.mode, go(p.ty))
                });
                let ret = go(f.ret);
                let throws_ = go(f.throws_);
                auto.alloc(NodeFunction { params: params, ret: ret, throws_: throws_ })
            },
            let p: root.types.NormalTyAssociatedTypeProjection => {
                let base = go(p.base);
                let interface_ = go(p.interface_);
                let member = auto.strs.intern(p.member);
                auto.alloc(NodeProjection { base: base, interface_: interface_, member: member })
            },
            let leaf: root.types.NormalTyInt
                | root.types.NormalTyBigint
                | root.types.NormalTyFloat
                | root.types.NormalTyString
                | root.types.NormalTyBool
                | root.types.NormalTyNull
                | root.types.NormalTyUint8Array
                | root.types.NormalTyMedia
                | root.types.NormalTyRustType
                | root.types.NormalTyType
                | root.types.NormalTyResource
                | root.types.NormalTyPromptAst
                | root.types.NormalTyLiteral
                | root.types.NormalTyTypeVar
                | root.types.NormalTyOpaqueAlias
                | root.types.NormalTyNever
                | root.types.NormalTyUnknown
                | root.types.NormalTyError =>
            {
                auto.alloc(NodeLeaf { leaf: auto.leaves.intern(leaf) })
            },
        }
    }
}

// port: baml_type/src/normalize/mu.rs::Built @ d9be6853b
// A faithful term graph of the input: knots tied, nothing transformed yet.
class Built {
    auto: Automaton,
    root_state: int,

    // port: baml_type/src/normalize/mu.rs::Built::epsilon_close @ d9be6853b
    function epsilon_close(self) -> Closed throws never {
        epsilon_close(self.auto, self.root_state);
        Closed { auto: self.auto, root_state: self.root_state }
    }
}

// port: baml_type/src/normalize/mu.rs::Closed @ d9be6853b
// ε-closed: no union has a union member, a `never` member, or an unguarded
// spine; every μ body is constructor-headed (contractive).
class Closed {
    auto: Automaton,
    root_state: int,

    // port: baml_type/src/normalize/mu.rs::Closed::minimize_and_absorb @ d9be6853b
    // Interleave partition refinement with the per-state union algebra to a
    // fixpoint (an absorption redirect can resurface ε-edges, hence the
    // re-closure inside the loop).
    function minimize_and_absorb(self, ctx: root.types.TypeContext) -> Minimal throws never {
        while (true) {
            minimize(self.auto, self.root_state);
            if (!algebra_pass(self.auto, self.root_state, ctx)) {
                break;
            }
            epsilon_close(self.auto, self.root_state);
        }
        Minimal { auto: self.auto, root_state: self.root_state }
    }
}

// port: baml_type/src/normalize/mu.rs::Minimal @ d9be6853b
// The canonical automaton: coarsest bisimulation, union algebra at fixpoint.
class Minimal {
    auto: Automaton,
    root_state: int,

    // port: baml_type/src/normalize/mu.rs::Minimal::read_back @ d9be6853b
    function read_back(self) -> root.types.NormalTy? throws never {
        read_back(self.auto, self.root_state)
    }

    // port: baml_type/src/normalize/mu.rs::Minimal::render_root @ d9be6853b
    // The `normalize` rendering: a named recursive root is unfolded once
    // (exposing its head constructor), nested recursion folded to alias
    // names; every other root renders by named-cut. Null when the renderer
    // bails.
    function render_root(self) -> root.types.Ty? throws never {
        let auto = self.auto;
        let cyclic = cyclic_states(auto, self.root_state);
        let orders = union_orders(auto, self.root_state);
        let renderer = Renderer.new(auto, cyclic, orders);
        let r = auto.resolve(self.root_state);
        let path: int[] = [];
        if (cyclic.has(r) && auto.representative_name(r) != null) {
            path.push(r);
            let rendered = renderer.structural(r, path);
            path.pop();
            return rendered;
        }
        renderer.render(r, path)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE 2: ε-CLOSURE
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize/mu.rs::epsilon_close @ d9be6853b
// Close every union state over its ε-edges. Tarjan yields ε-SCCs
// successors-first, so each component sees only closed unions through ε; its
// final members are the constructor successors gathered across it.
function epsilon_close(auto: Automaton, root_state: int) -> void throws never {
    for (let scc in epsilon_sccs(auto, root_state)) {
        let in_scc: map<int, bool> = {};
        for (let u in scc) {
            in_scc.set(u, true);
        }
        let gathered: int[] = [];
        for (let u in scc) {
            let node = auto.node(u);
            // A prior component may have redirected this state.
            if (!(node is NodeUnion)) {
                continue;
            }
            for (let m in node.members) {
                let r = auto.resolve(m);
                if (in_scc.has(r)) {
                    continue;
                }
                match (auto.node(r)) {
                    // An already-closed union: splice its constructor members.
                    let inner: NodeUnion => {
                        for (let x in inner.members) {
                            gathered.push(auto.resolve(x));
                        }
                    },
                    _ => {
                        gathered.push(r);
                    },
                }
            }
        }
        // `never` contributes nothing; `unknown` absorbs everything.
        let members = id_set(gathered).filter((m) -> {
            !auto.is_never(m)
        });
        let has_top = members.some((m) -> {
            auto.is_unknown_top(m)
        });
        for (let u in scc) {
            if (auto.resolve(u) != u) {
                continue;
            }
            if (has_top) {
                auto.states[u].node = NodeLeaf { leaf: auto.unknown_top };
            } else if (members.length() == 0) {
                // A constructor-free ε-component is uninhabited.
                auto.states[u].node = NodeLeaf { leaf: auto.never };
            } else if (members.length() == 1) {
                let m = members[0];
                if (auto.resolve(m) != u) {
                    auto.redirect_to(u, m);
                }
            } else {
                auto.states[u].node = NodeUnion { members: members };
            }
        }
    }
}

// port: baml_type/src/normalize/mu.rs::epsilon_sccs::Tarjan @ d9be6853b
// Tarjan over the ε-edges of union states.
class EpsilonTarjan {
    auto: Automaton,
    index: map<int, int>,
    low: map<int, int>,
    on_stack: map<int, bool>,
    stack: int[],
    next: int,
    sccs: int[][],

    // port: baml_type/src/normalize/mu.rs::epsilon_sccs::Tarjan::visit @ d9be6853b
    function visit(self, s: int) -> void throws never {
        self.index.set(s, self.next);
        self.low.set(s, self.next);
        self.next += 1;
        self.stack.push(s);
        self.on_stack.set(s, true);
        let node = self.auto.node(s);
        let members = match (node) {
            let u: NodeUnion => u.members,
            _ => baml.sys.panic("ε-SCCs are computed over union states only"),
        };
        let eps = members
            .map((m) -> {
                self.auto.resolve(m)
            })
            .filter((r) -> {
                r != s && self.auto.node(r) is NodeUnion
            });
        for (let t in eps) {
            if (!self.index.has(t)) {
                self.visit(t);
                let l = if (self.low[t] < self.low[s]) {
                    self.low[t]
                } else {
                    self.low[s]
                };
                self.low.set(s, l);
            } else if (self.on_stack.has(t)) {
                let l = if (self.index[t] < self.low[s]) {
                    self.index[t]
                } else {
                    self.low[s]
                };
                self.low.set(s, l);
            }
        }
        if (self.low[s] == self.index[s]) {
            let scc: int[] = [];
            while (true) {
                let t = self.stack.pop() ?? baml.sys.panic("Tarjan stack underflow");
                self.on_stack.delete(t);
                scc.push(t);
                if (t == s) {
                    break;
                }
            }
            self.sccs.push(id_set(scc));
        }
    }
}

// port: baml_type/src/normalize/mu.rs::epsilon_sccs @ d9be6853b
// ε-SCCs over union states, in Tarjan completion order (successors first).
function epsilon_sccs(auto: Automaton, root_state: int) -> int[][] throws never {
    let t = EpsilonTarjan { auto: auto, index: {}, low: {}, on_stack: {}, stack: [], next: 0, sccs: [] };
    for (let s in auto.reachable(root_state)) {
        if (auto.node(s) is NodeUnion && !t.index.has(s)) {
            t.visit(s);
        }
    }
    t.sccs
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE 3: MINIMIZATION + PER-STATE ALGEBRA
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize/mu.rs::minimize @ d9be6853b
// Moore-style partition refinement to the coarsest bisimulation, then merge
// each block into its smallest member. Union members refine as a set of
// blocks.
function minimize(auto: Automaton, root_state: int) -> void throws never {
    let reach = auto.reachable(root_state);

    // Initial partition by local shape.
    let block: map<int, int> = {};
    let initial: map<LocalKey, int[]> = {};
    for (let s in reach) {
        let key = local_key(auto, s);
        let group = initial.get_or_insert(key, []);
        group.push(s);
    }
    let i = 0;
    for (let states in initial.values()) {
        for (let s in states) {
            block.set(s, i);
        }
        i += 1;
    }

    // Refine by child blocks until stable.
    while (true) {
        let groups: map<int[], int[]> = {};
        for (let s in reach) {
            let node = auto.node(s);
            let sig = match (node) {
                let u: NodeUnion => {
                    id_set(
                        u.members.map((m) -> {
                            block[auto.resolve(m)]
                        }),
                    )
                },
                _ => {
                    children(node).map((c) -> {
                        block[auto.resolve(c)]
                    })
                },
            };
            let group = groups.get_or_insert([block[s]].concat(sig), []);
            group.push(s);
        }
        let distinct: map<int, bool> = {};
        for (let b in block.values()) {
            distinct.set(b, true);
        }
        let stable = groups.length() == distinct.length();
        let next: map<int, int> = {};
        let k = 0;
        for (let states in groups.values()) {
            for (let s in states) {
                next.set(s, k);
            }
            k += 1;
        }
        block = next;
        if (stable) {
            break;
        }
    }

    // Merge each block into its smallest state id (reach is ascending).
    let rep: map<int, int> = {};
    for (let s in reach) {
        if (!rep.has(block[s])) {
            rep.set(block[s], s);
        }
    }
    for (let s in reach) {
        let r = rep[block[s]];
        if (s != r) {
            auto.redirect_to(s, r);
        }
    }
}

// port: baml_type/src/normalize/mu.rs::LocalKey @ d9be6853b
// The local (childless) shape of a state, as interned ids: two states can
// only merge if their local keys are equal.
class LocalKeyLeaf {
    leaf: int,
}

class LocalKeyEnum {
    name: int,
}

class LocalKeyEnumVariant {
    name: int,
    variant: int,
}

class LocalKeyClass {
    name: int,
    arity: int,
}

class LocalKeyInterface {
    name: int,
    arity: int,
    bindings: int[],
}

class LocalKeyList {
}

class LocalKeyMap {
}

class LocalKeyFuture {
}

class LocalKeyUnion {
}

class LocalKeyTuple {
    arity: int,
}

class LocalKeyFunction {
    params: LocalKeyParam[],
}

// port: baml_type/src/normalize/mu.rs::LocalKey::Function @ d9be6853b
// One `(Option<StrId>, FunctionParamMode)` of LocalKeyFunction (a class:
// tuples are not hashable).
class LocalKeyParam {
    name: int?,
    mode: root.types.FunctionParamMode,
}

class LocalKeyProjection {
    member: int,
}

type LocalKey = LocalKeyLeaf
    | LocalKeyEnum
    | LocalKeyEnumVariant
    | LocalKeyClass
    | LocalKeyInterface
    | LocalKeyList
    | LocalKeyMap
    | LocalKeyFuture
    | LocalKeyUnion
    | LocalKeyTuple
    | LocalKeyFunction
    | LocalKeyProjection;

// port: baml_type/src/normalize/mu.rs::local_key @ d9be6853b
function local_key(auto: Automaton, s: int) -> LocalKey throws never {
    match (auto.node(s)) {
        let x: NodeLeaf => LocalKeyLeaf { leaf: x.leaf },
        let x: NodeEnum => LocalKeyEnum { name: x.name },
        let x: NodeEnumVariant => LocalKeyEnumVariant { name: x.name, variant: x.variant },
        let x: NodeClass => LocalKeyClass { name: x.name, arity: x.args.length() },
        let x: NodeInterface => {
            LocalKeyInterface {
                name: x.name,
                arity: x.args.length(),
                bindings: x.bindings.map((b) -> {
                    b.0
                }),
            }
        },
        NodeList => LocalKeyList {},
        NodeMap => LocalKeyMap {},
        NodeFuture => LocalKeyFuture {},
        NodeUnion => LocalKeyUnion {},
        let x: NodeTuple => LocalKeyTuple { arity: x.items.length() },
        let x: NodeFunction => {
            LocalKeyFunction {
                params: x.params.map((p) -> {
                    LocalKeyParam { name: p.0, mode: p.1 }
                }),
            }
        },
        let x: NodeProjection => LocalKeyProjection { member: x.member },
    }
}

// port: baml_type/src/normalize/mu.rs::algebra_pass @ d9be6853b
// Re-run the union algebra per state over the merged automaton: dedup, drop
// `never`, collapse complete enums and bools, and absorb subtype members with
// each member materialized as its closed read-back, so the real subtype
// checker decides. Returns whether anything changed. Pairwise absorption is
// skipped for a cyclic unnamed union (its rendering needs a named subset
// cover) and when a member's materialization bails.
function algebra_pass(
    auto: Automaton,
    root_state: int,
    ctx: root.types.TypeContext,
) -> bool throws never {
    let cyclic = cyclic_states(auto, root_state);
    let changed = false;
    // Member read-backs, memoized while the automaton is unmutated: any node
    // rewrite or redirect below clears the memo. A null entry is a bail.
    let read_backs: map<int, root.types.NormalTy?> = {};
    for (let s in auto.reachable(root_state)) {
        let raw = auto.node(s);
        if (!(raw is NodeUnion)) {
            continue;
        }
        let before = id_set(
            raw.members.map((m) -> {
                auto.resolve(m)
            }),
        );
        let members = before.filter((m) -> {
            !auto.is_never(m)
        });
        members = collapse_complete_enums(auto, members, ctx);
        members = collapse_complete_bools(auto, members);

        let absorb = !(cyclic.has(s) && auto.representative_name(s) == null);
        // Materialize members as closed terms; canonical order is term order.
        let items: (root.types.NormalTy, int)[]? = null;
        if (absorb) {
            let collected: (root.types.NormalTy, int)[] = [];
            let bailed = false;
            for (let m in members) {
                if (!read_backs.has(m)) {
                    read_backs.set(m, read_back(auto, m));
                }
                let t = read_backs[m];
                if (t == null) {
                    bailed = true;
                    break;
                }
                collected.push((t, m));
            }
            if (!bailed) {
                items = collected;
            }
        }
        if (items != null) {
            items.sort_by((a, b) -> {
                let o = root.types.cmp_normal_ty(a.0, b.0);
                if (o != baml.ops.Ordering.Equal) {
                    o
                } else {
                    a.1.cmp(b.1)
                }
            });
            // The pairwise absorption rule of absorb_subtypes, over closed terms.
            let n = items.length();
            let keep = baml.Array.filled(n, true);
            for (let i = 0; i < n; i += 1) {
                if (items[i].0 is root.types.NormalTyError) {
                    continue;
                }
                for (let j = 0; j < n; j += 1) {
                    if (i == j || !keep[j] || items[j].0 is root.types.NormalTyError) {
                        continue;
                    }
                    if (!root.types.is_subtype_of(items[i].0, items[j].0, ctx, [])) {
                        continue;
                    }
                    let mutual = root.types.is_subtype_of(items[j].0, items[i].0, ctx, []);
                    if (!mutual || j < i) {
                        keep[i] = false;
                        break;
                    }
                }
            }
            let kept: int[] = [];
            for (let i = 0; i < n; i += 1) {
                if (keep[i]) {
                    kept.push(items[i].1);
                }
            }
            members = id_set(kept);
        }

        let state_changed = members != before;
        if (state_changed) {
            changed = true;
        }
        if (members.length() == 0) {
            auto.states[s].node = NodeLeaf { leaf: auto.never };
            read_backs.clear();
        } else if (members.length() == 1) {
            let m = members[0];
            if (auto.resolve(m) != s) {
                auto.redirect_to(s, m);
                // The redirect may point other unions' members at a union:
                // force another closure/refinement round.
                changed = true;
                read_backs.clear();
            }
        } else {
            // Rewriting the stored members (resolved, sorted, deduplicated)
            // with the set unchanged keeps cached read-backs valid.
            auto.states[s].node = NodeUnion { members: members };
            if (state_changed) {
                read_backs.clear();
            }
        }
    }
    changed
}

// port: baml_type/src/normalize/mu.rs::collapse_complete_enums @ d9be6853b
// Replace a complete set of an enum's variant states with the enum state
// (`E.A | E.B | .. == E`), finding or allocating it. Returns the members
// instead of editing them in place.
function collapse_complete_enums(
    auto: Automaton,
    members: int[],
    ctx: root.types.TypeContext,
) -> int[] throws never {
    let enums: int[] = [];
    for (let m in members) {
        if let v: NodeEnumVariant = auto.node(m) {
            enums.push(v.name);
        }
    }
    let out = members;
    for (let e in id_set(enums)) {
        // An unknown enum does not collapse (fail-safe).
        let all = ctx.enum_variants(auto.names.get(e));
        if (all == null) {
            continue;
        }
        let present: map<string, bool> = {};
        for (let m in out) {
            if let v: NodeEnumVariant = auto.node(m) {
                if (v.name == e) {
                    present.set(auto.strs.get(v.variant), true);
                }
            }
        }
        // At least two variants, as in the bottom-up pass.
        if (
            all.length() >= 2
                && all.every((v) -> {
                    present.has(v)
                })
        ) {
            let kept = out.filter((m) -> {
                match (auto.node(m)) {
                    let v: NodeEnumVariant => v.name != e,
                    _ => true,
                }
            });
            let enum_state = find_live_state(auto, (node) -> {
                match (node) {
                    let x: NodeEnum => x.name == e,
                    _ => false,
                }
            })
                ?? auto.alloc(NodeEnum { name: e });
            out = id_set(kept.concat([enum_state]));
        }
    }
    out
}

// port: baml_type/src/normalize/mu.rs::collapse_complete_enums @ d9be6853b
// The `(0..auto.states.len()).find(|&s| auto.redirect[s] == s && ..)` scan
// both collapses share: the first live (unredirected) state whose node
// satisfies `pred`.
function find_live_state(auto: Automaton, pred: (Node) -> bool throws never) -> int? throws never {
    for (let s = 0; s < auto.states.length(); s += 1) {
        if (auto.redirect[s] == s && pred(auto.node(s))) {
            return s;
        }
    }
    null
}

// port: baml_type/src/normalize/mu.rs::collapse_complete_bools @ d9be6853b
// Replace the complete pair of bool literal states with the `bool` state
// (`true | false == bool`). Returns the members instead of editing them in
// place.
function collapse_complete_bools(auto: Automaton, members: int[]) -> int[] throws never {
    let is_leaf = (m: int, leaf: int) -> bool {
        match (auto.node(m)) {
            let l: NodeLeaf => l.leaf == leaf,
            _ => false,
        }
    };
    let has_true = members.some((m) -> {
        is_leaf(m, auto.lit_true)
    });
    let has_false = members.some((m) -> {
        is_leaf(m, auto.lit_false)
    });
    if (!(has_true && has_false)) {
        return members;
    }
    let kept = members.filter((m) -> {
        !is_leaf(m, auto.lit_true) && !is_leaf(m, auto.lit_false)
    });
    let bool_state = find_live_state(auto, (node) -> {
        match (node) {
            let l: NodeLeaf => l.leaf == auto.bool_leaf,
            _ => false,
        }
    })
        ?? auto.alloc(NodeLeaf { leaf: auto.bool_leaf });
    id_set(kept.concat([bool_state]))
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE 4: READ-BACK & RENDERING
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize/mu.rs::Rb @ d9be6853b
// The automaton expanded into a tree with explicit back-references.
// `needs_binder` marks occurrences whose subtree references them.
class RbRef {
    state: int,
}

class RbNode {
    state: int,
    needs_binder: bool,
    shape: RbShape,
}

type Rb = RbRef | RbNode;

// port: baml_type/src/normalize/mu.rs::RbShape @ d9be6853b
class RbShapeLeaf {
    leaf: int,
}

class RbShapeEnum {
    name: int,
}

class RbShapeEnumVariant {
    name: int,
    variant: int,
}

class RbShapeClass {
    name: int,
    args: Rb[],
}

class RbShapeInterface {
    name: int,
    args: Rb[],
    bindings: (int, Rb)[],
}

class RbShapeList {
    inner: Rb,
}

class RbShapeMap {
    key: Rb,
    value: Rb,
}

class RbShapeFuture {
    value: Rb,
    error: Rb,
}

class RbShapeUnion {
    members: Rb[],
}

class RbShapeTuple {
    items: Rb[],
}

class RbShapeFunction {
    params: (int?, root.types.FunctionParamMode, Rb)[],
    ret: Rb,
    throws_: Rb,
}

class RbShapeProjection {
    base: Rb,
    interface_: Rb,
    member: int,
}

type RbShape = RbShapeLeaf
    | RbShapeEnum
    | RbShapeEnumVariant
    | RbShapeClass
    | RbShapeInterface
    | RbShapeList
    | RbShapeMap
    | RbShapeFuture
    | RbShapeUnion
    | RbShapeTuple
    | RbShapeFunction
    | RbShapeProjection;

// port: baml_type/src/normalize/mu.rs::read_back @ d9be6853b
// The canonical μ-term rooted at `root_state`, or null when the display
// renderer bails. Expand to a tree; convert once with placeholder displays to
// fix the union member orders; render every binder state's display; convert
// again with the real displays. The result is always closed.
function read_back(auto: Automaton, root_state: int) -> root.types.NormalTy? throws never {
    let cyclic = cyclic_states(auto, root_state);
    let (let rb, _) = expand(auto, root_state, []);

    // Pass A: canonical member orders and the binder set.
    let rec = Recorder { union_orders: {}, binder_states: {} };
    convert(auto, rb, [], null, rec);

    let renderer = Renderer.new(auto, cyclic, rec.union_orders);
    let displays: map<int, root.types.Ty> = {};
    for (let s in id_set(rec.binder_states.keys())) {
        let rendered = renderer.render(s, [])
            ?? return null;
        displays.set(s, rendered);
    }

    // Pass B: the real term.
    let rec_b = Recorder { union_orders: {}, binder_states: {} };
    convert(auto, rb, [], displays, rec_b)
}

// port: baml_type/src/normalize/mu.rs::union_orders @ d9be6853b
// The canonical member orders of every union state in the expansion, from a
// placeholder-display read-back. Rust returns an Option that is always Some.
function union_orders(auto: Automaton, root_state: int) -> map<int, int[]> throws never {
    let (let rb, _) = expand(auto, root_state, []);
    let rec = Recorder { union_orders: {}, binder_states: {} };
    convert(auto, rb, [], null, rec);
    rec.union_orders
}

// port: baml_type/src/normalize/mu.rs::expand @ d9be6853b
// Expand state `s` into a tree, cutting at on-path revisits. Also returns the
// states the tree references freely.
function expand(auto: Automaton, s: int, path: int[]) -> (Rb, map<int, bool>) throws never {
    let r = auto.resolve(s);
    if (path.includes(r)) {
        let refs: map<int, bool> = {};
        refs.set(r, true);
        return (RbRef { state: r }, refs);
    }
    path.push(r);
    let refs: map<int, bool> = {};
    let child = (c: int) -> Rb {
        let (let rb, let child_refs) = expand(auto, c, path);
        for (let k in child_refs.keys()) {
            refs.set(k, true);
        }
        rb
    };
    let shape: RbShape = match (auto.node(r)) {
        let x: NodeLeaf => RbShapeLeaf { leaf: x.leaf },
        let x: NodeEnum => RbShapeEnum { name: x.name },
        let x: NodeEnumVariant => RbShapeEnumVariant { name: x.name, variant: x.variant },
        let x: NodeClass => RbShapeClass { name: x.name, args: x.args.map(child) },
        let x: NodeInterface => {
            let args = x.args.map(child);
            let bindings = x.bindings.map((b) -> {
                (b.0, child(b.1))
            });
            RbShapeInterface { name: x.name, args: args, bindings: bindings }
        },
        let x: NodeList => RbShapeList { inner: child(x.inner) },
        let x: NodeMap => {
            let key = child(x.key);
            RbShapeMap { key: key, value: child(x.value) }
        },
        let x: NodeFuture => {
            let value = child(x.value);
            RbShapeFuture { value: value, error: child(x.error) }
        },
        let x: NodeUnion => RbShapeUnion { members: x.members.map(child) },
        let x: NodeTuple => RbShapeTuple { items: x.items.map(child) },
        let x: NodeFunction => {
            let params = x.params.map((p) -> {
                (p.0, p.1, child(p.2))
            });
            let ret = child(x.ret);
            RbShapeFunction { params: params, ret: ret, throws_: child(x.throws_) }
        },
        let x: NodeProjection => {
            let base = child(x.base);
            RbShapeProjection { base: base, interface_: child(x.interface_), member: x.member }
        },
    };
    path.pop();
    let needs_binder = refs.has(r);
    refs.delete(r);
    (RbNode { state: r, needs_binder: needs_binder, shape: shape }, refs)
}

// port: baml_type/src/normalize/mu.rs::Recorder @ d9be6853b
// What a convert pass records for the passes after it: each union state's
// canonical member order, and the states that emit binders.
class Recorder {
    union_orders: map<int, int[]>,
    binder_states: map<int, bool>,
}

// port: baml_type/src/normalize/mu.rs::convert @ d9be6853b
// Convert the expansion to the canonical μ-term: binder-emitting ancestors
// form the de Bruijn context, union members sort by the canonical order, and
// each emitted binder gets its display. With `displays` null (pass A) the
// display is a placeholder, which equality-transparency keeps out of the
// sort.
function convert(
    auto: Automaton,
    rb: Rb,
    binders: int[],
    displays: map<int, root.types.Ty>?,
    rec: Recorder,
) -> root.types.NormalTy throws never {
    let go = (x: Rb) -> root.types.NormalTy {
        convert(auto, x, binders, displays, rec)
    };
    match (rb) {
        let r: RbRef => {
            let i = binders.find_last_index((b) -> {
                b == r.state
            })
                ?? baml.sys.panic(
                    "a back-reference targets an ancestor, and every referenced ancestor emits a binder",
                );
            root.types.NormalTyRecVar { var: binders.length() - 1 - i }
        },
        let node: RbNode => {
            if (node.needs_binder) {
                binders.push(node.state);
                rec.binder_states.set(node.state, true);
            }
            let body: root.types.NormalTy = match (node.shape) {
                let x: RbShapeLeaf => auto.leaves.get(x.leaf),
                let x: RbShapeEnum => root.types.NormalTyEnum { name: auto.names.get(x.name) },
                let x: RbShapeEnumVariant => {
                    root.types.NormalTyEnumVariant {
                        name: auto.names.get(x.name),
                        variant: auto.strs.get(x.variant),
                    }
                },
                let x: RbShapeClass => {
                    root.types.NormalTyClass { name: auto.names.get(x.name), args: x.args.map(go) }
                },
                let x: RbShapeInterface => {
                    let args = x.args.map(go);
                    let bindings = x.bindings.map((b) -> {
                        root.types.NormalBinding { name: auto.strs.get(b.0), ty: go(b.1) }
                    });
                    root.types.NormalTyInterface {
                        name: auto.names.get(x.name),
                        args: args,
                        bindings: bindings,
                    }
                },
                let x: RbShapeList => root.types.NormalTyList { elem: go(x.inner) },
                let x: RbShapeMap => {
                    let key = go(x.key);
                    root.types.NormalTyMap { key: key, value: go(x.value) }
                },
                let x: RbShapeFuture => {
                    let value = go(x.value);
                    root.types.NormalTyFuture { value: value, error: go(x.error) }
                },
                let x: RbShapeTuple => root.types.NormalTyTuple { items: x.items.map(go) },
                let x: RbShapeUnion => {
                    let converted: (root.types.NormalTy, int)[] = x.members.map((m) -> {
                        let state = match (m) {
                            let r: RbRef => r.state,
                            let n: RbNode => n.state,
                        };
                        (go(m), state)
                    });
                    converted.sort_by((a, b) -> {
                        let o = root.types.cmp_normal_ty(a.0, b.0);
                        if (o != baml.ops.Ordering.Equal) {
                            o
                        } else {
                            a.1.cmp(b.1)
                        }
                    });
                    // `dedup_by` on the term: keep the first of each run.
                    let deduped: (root.types.NormalTy, int)[] = [];
                    for (let c in converted) {
                        if (deduped.length() == 0 || deduped[deduped.length() - 1].0 != c.0) {
                            deduped.push(c);
                        }
                    }
                    if (!rec.union_orders.has(node.state)) {
                        rec.union_orders.set(
                            node.state,
                            deduped.map((c) -> {
                                c.1
                            }),
                        );
                    }
                    match (deduped.length()) {
                        0 => root.types.NormalTyNever {},
                        1 => deduped[0].0,
                        _ => {
                            root.types.NormalTyUnion {
                                members: deduped.map((c) -> {
                                    c.0
                                }),
                            }
                        },
                    }
                },
                let x: RbShapeFunction => {
                    let params = x.params.map((p) -> {
                        let pname = p.0;
                        let name = if (pname != null) {
                            auto.strs.get(pname)
                        } else {
                            null
                        };
                        root.types.NormalParam { name: name, ty: go(p.2), mode: p.1 }
                    });
                    let ret = go(x.ret);
                    root.types.NormalTyFunction { params: params, ret: ret, throws_: go(x.throws_) }
                },
                let x: RbShapeProjection => {
                    let base = go(x.base);
                    root.types.NormalTyAssociatedTypeProjection {
                        base: base,
                        interface_: go(x.interface_),
                        member: auto.strs.get(x.member),
                    }
                },
            };
            if (!node.needs_binder) {
                return body;
            }
            binders.pop();
            // Pass A placeholder: never escapes (the pass-A term is dropped);
            // Error is the honest sentinel for "not a real rendering".
            let rendered: root.types.Ty = match (displays) {
                let d: map<int, root.types.Ty> => {
                    d.get(node.state) ?? baml.sys.panic("pass A recorded every binder state")
                },
                null => root.types.TyError {},
            };
            root.types.NormalTyMu {
                binder: root.types.MuDisplay {
                    name: auto.representative_name(node.state),
                    rendered: rendered,
                },
                body: body,
            }
        },
    }
}

// port: baml_type/src/normalize/mu.rs::cyclic_states::Tarjan @ d9be6853b
// Tarjan over every edge, recording states in a nontrivial SCC or with a
// self-edge.
class CyclicTarjan {
    auto: Automaton,
    index: map<int, int>,
    low: map<int, int>,
    on_stack: map<int, bool>,
    stack: int[],
    next: int,
    cyclic: map<int, bool>,

    // port: baml_type/src/normalize/mu.rs::cyclic_states::Tarjan::visit @ d9be6853b
    function visit(self, s: int) -> void throws never {
        self.index.set(s, self.next);
        self.low.set(s, self.next);
        self.next += 1;
        self.stack.push(s);
        self.on_stack.set(s, true);
        let succs = children(self.auto.node(s)).map((c) -> {
            self.auto.resolve(c)
        });
        let self_edge = false;
        for (let t in succs) {
            if (t == s) {
                self_edge = true;
                continue;
            }
            if (!self.index.has(t)) {
                self.visit(t);
                let l = if (self.low[t] < self.low[s]) {
                    self.low[t]
                } else {
                    self.low[s]
                };
                self.low.set(s, l);
            } else if (self.on_stack.has(t)) {
                let l = if (self.index[t] < self.low[s]) {
                    self.index[t]
                } else {
                    self.low[s]
                };
                self.low.set(s, l);
            }
        }
        if (self.low[s] == self.index[s]) {
            let scc: int[] = [];
            while (true) {
                let t = self.stack.pop() ?? baml.sys.panic("Tarjan stack underflow");
                self.on_stack.delete(t);
                scc.push(t);
                if (t == s) {
                    break;
                }
            }
            if (scc.length() > 1) {
                for (let t in scc) {
                    self.cyclic.set(t, true);
                }
            } else if (self_edge) {
                self.cyclic.set(s, true);
            }
        }
    }
}

// port: baml_type/src/normalize/mu.rs::cyclic_states @ d9be6853b
// States on a cycle (a nontrivial SCC of the full edge graph, or a
// self-edge): the states whose alias names cut recursion in the rendering.
function cyclic_states(auto: Automaton, root_state: int) -> map<int, bool> throws never {
    let t = CyclicTarjan { auto: auto, index: {}, low: {}, on_stack: {}, stack: [], next: 0, cyclic: {} };
    for (let s in auto.reachable(root_state)) {
        if (!t.index.has(s)) {
            t.visit(s);
        }
    }
    t.cyclic
}

// port: baml_type/src/normalize/mu.rs::Renderer @ d9be6853b
// The named-cut display renderer: recursion folds to an alias name at every
// named cyclic state, and (when ε-closure spliced the named union through,
// leaving its cycle nameless) to a subset cover: an unnamed cyclic union
// holding everything a named union holds renders as `name | extras`. Renders
// are memoized per state. Null (a bail) when an on-path state re-enters with
// no exact cut.
class Renderer {
    auto: Automaton,
    cyclic: map<int, bool>,
    orders: map<int, int[]>,
    // Named union states (the cover candidates) with their resolved member
    // sets, in representative-name order.
    candidates: (int, int[])[],
    memo: map<int, root.types.Ty>,

    // port: baml_type/src/normalize/mu.rs::Renderer::new @ d9be6853b
    // Candidates come from the whole automaton: an ε-splice leaves the named
    // binder union unreachable, and that orphan is the cover a cycle needs.
    function new(auto: Automaton, cyclic: map<int, bool>, orders: map<int, int[]>) -> Self {
        let candidates: (int, int[])[] = [];
        for (let s = 0; s < auto.states.length(); s += 1) {
            if (auto.redirect[s] != s || auto.representative_name(s) == null) {
                continue;
            }
            if let u: NodeUnion = auto.node(s) {
                candidates.push(
                    (
                        s,
                        id_set(
                            u.members.map((m) -> {
                                auto.resolve(m)
                            }),
                        ),
                    ),
                );
            }
        }
        candidates.sort_by((a, b) -> {
            let x = auto.representative_name(a.0) ?? baml.sys.panic("candidates are named");
            let y = auto.representative_name(b.0) ?? baml.sys.panic("candidates are named");
            root.types.cmp_decl_name(x, y)
        });
        Renderer { auto: auto, cyclic: cyclic, orders: orders, candidates: candidates, memo: {} }
    }

    // port: baml_type/src/normalize/mu.rs::Renderer::render @ d9be6853b
    function render(self, s: int, path: int[]) -> root.types.Ty? throws never {
        let r = self.auto.resolve(s);
        let memoized = self.memo.get(r);
        if (memoized != null) {
            return memoized;
        }
        if (self.cyclic.has(r)) {
            let name = self.auto.representative_name(r);
            if (name != null) {
                let t = root.types.TyTypeAlias { name: name };
                self.memo.set(r, t);
                return t;
            }
        }
        if (path.includes(r)) {
            // On-path re-entry with no name: only a union fully covered by
            // named states can still cut the cycle exactly.
            return self.cover_only(r);
        }
        path.push(r);
        let out = self.structural(r, path);
        path.pop();
        if (out != null) {
            self.memo.set(r, out);
        }
        out
    }

    // port: baml_type/src/normalize/mu.rs::Renderer::covers_of @ d9be6853b
    // The named covers of union state `r` (candidates whose member sets are
    // subsets of `r`'s), plus the members they leave uncovered.
    function covers_of(self, r: int) -> (int[], int[]) throws never {
        let node = self.auto.node(r);
        if (!(node is NodeUnion)) {
            return ([], []);
        }
        let members = id_set(
            node.members.map((m) -> {
                self.auto.resolve(m)
            }),
        );
        let covers: int[] = [];
        let covered: map<int, bool> = {};
        for (let candidate in self.candidates) {
            let u = candidate.0;
            let u_members = candidate.1;
            let subset = u_members.every((m) -> {
                members.includes(m)
            });
            if (u != r && subset) {
                covers.push(u);
                for (let m in u_members) {
                    covered.set(m, true);
                }
            }
        }
        let uncovered = members.filter((m) -> {
            !covered.has(m)
        });
        (covers, uncovered)
    }

    // port: baml_type/src/normalize/mu.rs::Renderer::cover_only @ d9be6853b
    // Render an on-path unnamed state through covers alone: exact only when
    // they leave nothing uncovered.
    function cover_only(self, r: int) -> root.types.Ty? throws never {
        if (!(self.auto.node(r) is NodeUnion)) {
            return null;
        }
        let (let covers, let uncovered) = self.covers_of(r);
        if (covers.length() == 0 || uncovered.length() != 0) {
            return null;
        }
        self.cover_union(covers, [], [])
    }

    // port: baml_type/src/normalize/mu.rs::Renderer::cover_union @ d9be6853b
    // A union Ty from cover names plus rendered extras.
    function cover_union(
        self,
        covers: int[],
        extras: int[],
        path: int[],
    ) -> root.types.Ty? throws never {
        let parts: root.types.Ty[] = [];
        for (let u in covers) {
            let name = self.auto.representative_name(u) ?? baml.sys.panic("candidates are named");
            parts.push(root.types.TyTypeAlias { name: name });
        }
        for (let m in extras) {
            parts.push(
                self.render(m, path)
                    ?? return null,
            );
        }
        match (parts.length()) {
            0 => root.types.TyNever {},
            1 => parts[0],
            _ => root.types.TyUnion { members: parts },
        }
    }

    // port: baml_type/src/normalize/mu.rs::Renderer::render_all @ d9be6853b
    // Render each state in order; null as soon as one bails. (Rust's
    // `for .. { out.push(self.render(x, path)?) }` loops.)
    function render_all(self, states: int[], path: int[]) -> root.types.Ty[]? throws never {
        let out: root.types.Ty[] = [];
        for (let s in states) {
            out.push(
                self.render(s, path)
                    ?? return null,
            );
        }
        out
    }

    // port: baml_type/src/normalize/mu.rs::Renderer::structural @ d9be6853b
    // Render `r`'s node one level, children through render. The root render
    // calls it directly to unfold a named root once.
    function structural(self, r: int, path: int[]) -> root.types.Ty? throws never {
        let auto = self.auto;
        let union_of = (parts: root.types.Ty[]) -> root.types.Ty {
            match (parts.length()) {
                0 => root.types.TyNever {},
                1 => parts[0],
                _ => root.types.TyUnion { members: parts },
            }
        };
        match (auto.node(r)) {
            let x: NodeLeaf => root.types.into_ty(auto.leaves.get(x.leaf)),
            let x: NodeEnum => root.types.TyEnum { name: auto.names.get(x.name) },
            let x: NodeEnumVariant => {
                root.types.TyEnumVariant {
                    name: auto.names.get(x.name),
                    variant: auto.strs.get(x.variant),
                }
            },
            let x: NodeClass => {
                let args = self.render_all(x.args, path)
                    ?? return null;
                root.types.TyClass { name: auto.names.get(x.name), args: args }
            },
            let x: NodeInterface => {
                let args = self.render_all(x.args, path)
                    ?? return null;
                let bindings: root.types.AssociatedType[] = [];
                for (let b in x.bindings) {
                    let ty = self.render(b.1, path)
                        ?? return null;
                    bindings.push(root.types.AssociatedType { name: auto.strs.get(b.0), ty: ty });
                }
                root.types.TyInterface {
                    name: auto.names.get(x.name),
                    args: args,
                    associated_types: bindings,
                }
            },
            let x: NodeList => {
                let inner = self.render(x.inner, path)
                    ?? return null;
                root.types.TyList { elem: inner }
            },
            let x: NodeMap => {
                let key = self.render(x.key, path)
                    ?? return null;
                let value = self.render(x.value, path)
                    ?? return null;
                root.types.TyMap { key: key, value: value }
            },
            let x: NodeFuture => {
                let value = self.render(x.value, path)
                    ?? return null;
                let error = self.render(x.error, path)
                    ?? return null;
                root.types.TyFuture { value: value, error: error }
            },
            let x: NodeTuple => {
                let items = self.render_all(x.items, path)
                    ?? return null;
                root.types.TyTuple { items: items }
            },
            let x: NodeUnion => {
                // Cyclic unnamed unions fold their covered members to alias
                // names (the splice-bypass case); everything else renders
                // member-wise in the order pass A fixed.
                let recorded = self.orders.get(r);
                // Defensive: a union outside the recorded expansion renders
                // resolved, deduplicated, id-ordered.
                let ordered = recorded
                    ?? id_set(
                        x.members.map((m) -> {
                            auto.resolve(m)
                        }),
                    );
                if (self.cyclic.has(r) && auto.representative_name(r) == null) {
                    let (let covers, _) = self.covers_of(r);
                    let covered: map<int, bool> = {};
                    for (let candidate in self.candidates) {
                        if (covers.includes(candidate.0)) {
                            for (let m in candidate.1) {
                                covered.set(m, true);
                            }
                        }
                    }
                    let extras = ordered.filter((m) -> {
                        !covered.has(m)
                    });
                    if (covers.length() == 0) {
                        // No name and no cover: renders structurally only if no
                        // cycle re-enters this state (render bails on re-entry).
                        let parts = self.render_all(ordered, path)
                            ?? return null;
                        return union_of(parts);
                    }
                    return self.cover_union(covers, extras, path);
                }
                let parts = self.render_all(ordered, path)
                    ?? return null;
                union_of(parts)
            },
            let x: NodeFunction => {
                let params: root.types.FunctionParamTy[] = [];
                for (let p in x.params) {
                    let ty = self.render(p.2, path)
                        ?? return null;
                    let pname = p.0;
                    let name = if (pname != null) {
                        auto.strs.get(pname)
                    } else {
                        null
                    };
                    params.push(root.types.FunctionParamTy { name: name, ty: ty, mode: p.1 });
                }
                let ret = self.render(x.ret, path)
                    ?? return null;
                let throws_ = self.render(x.throws_, path)
                    ?? return null;
                root.types.TyFunction { params: params, ret: ret, throws_: throws_ }
            },
            let x: NodeProjection => {
                let qualifier = match (auto.node(x.interface_)) {
                    let i: NodeInterface => i,
                    _ => baml.sys.panic("projection qualifier is an interface"),
                };
                let generics = self.render_all(qualifier.args, path)
                    ?? return null;
                let bindings: root.types.AssociatedType[] = [];
                for (let b in qualifier.bindings) {
                    let ty = self.render(b.1, path)
                        ?? return null;
                    bindings.push(root.types.AssociatedType { name: auto.strs.get(b.0), ty: ty });
                }
                let iface = root.types.InterfaceConstraint {
                    name: auto.names.get(qualifier.name),
                    generics: generics,
                    associated_types: bindings,
                };
                let base = self.render(x.base, path)
                    ?? return null;
                root.types.TyAssociatedTypeProjection {
                    base: base,
                    interface_: iface,
                    member: auto.strs.get(x.member),
                }
            },
        }
    }
}
