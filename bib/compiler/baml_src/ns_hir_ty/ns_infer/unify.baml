// port: baml_compiler2_hir_ty/src/infer/unify.rs @ d9be6853b
//
// The inference table: a union-find over inference variables with
// snapshot/rollback and eager, occurs-checked `Eq` unification (the
// rust-analyzer `InferenceTable` shape).
//
// Unification discipline (rustc's `TypeVariableValue` model): both sides are
// shallow-resolved before relating, so two solved roots never merge inside
// the union-find's value merge; a solved root is unified structurally against
// the other side instead. `Error` unifies with everything (a diagnostic was
// already emitted; never cascade). Unions unify positionally for now.
//
// Restructured (BAML forces it):
// - Rust's `Ty` handles live in a global pool; here the table owns the
//   `root.types.InferPool` its handles index (`InferenceTable.new(pool)`).
// - `InferVar` is a bare `int`; `VarKey` (ena's key newtype) is not ported.
// - ena's `InPlaceUnificationTable` is an external crate: `UnificationTable`
//   below is the subset this file uses, with ena's root choice (union by
//   rank, ties redirect the first root to the second) and its undo log.
//   Path compression is left out: it never changes which key is a root.
// - `VarPolicy` is a BAML enum, which takes no methods: its predicates and
//   `join` are free functions taking the policy first.
// - `new_var` / `new_var_of` and `new_var_ty` / `new_var_ty_of` are one
//   method each, with `policy` a named parameter defaulting to `Value`.
// - `Result<(), UnifyError>` is `throws UnifyError`; `commit_if_ok` takes a
//   closure that throws instead of returning `Err`.
// - `FxHashMap` iteration (`take_solved_class_bounds`) has no reproducible
//   order; we walk the bounds ledger in ascending root index.
//
// Not ported: `VarKey` and its `UnifyKey` impl (ena plumbing), debug
// assertions (`join`'s effect-class check, `bind_scoped_param`'s overwrite
// check, `close_scopes_to`'s and `rollback_to`'s depth checks).

// A closed scoped parameter's depth: deeper than any variable is minted at.
// Rust's `u32::MAX`.
const RETIRED_DEPTH = 4294967295;

// port: baml_compiler2_hir_ty/src/infer/unify.rs::VarPolicy @ d9be6853b
// What a variable IS: one total axis, from which every behavior derives (the
// predicates below). Carried inside the union-find value, never in a side
// table keyed by creation index, so the undo log governs it: a rollback that
// frees an index for reuse also reverts its policy.
enum VarPolicy {
    // An ordinary value variable (call instantiations, holes): demands must
    // agree, and an unconstrained class is an error.
    Value,
    // A throws-channel variable: unconstrained defaults to `never` at
    // finalize, BAML's only defaulting rule.
    Effect,
    // An unannotated lambda parameter: its first ground demand commits, and
    // later incompatible demands diagnose at their own use sites.
    LambdaParam,
    // Element/value of an EMPTY container literal: first-demand order on
    // disagreeing demands, and a ground `unknown` demand commits the slot to
    // top.
    ContainerSlot,
    // An empty map's key slot takes its first demand, but cannot absorb
    // `unknown`: an erased container still needs a hashable key type.
    MapKeySlot,
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::VarPolicy::first_demand_commits @ d9be6853b
// Whether the first ground demand commits the class, with later incompatible
// demands reporting at their own sites, where an ordinary var (a call
// instantiation) fails resolution instead.
function first_demand_commits(policy: VarPolicy) -> bool throws never {
    match (policy) {
        VarPolicy.LambdaParam | VarPolicy.ContainerSlot | VarPolicy.MapKeySlot => true,
        VarPolicy.Value | VarPolicy.Effect => false,
    }
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::VarPolicy::absorbs_unknown @ d9be6853b
// Whether a ground `unknown` demand commits the class to the top type. ONLY
// container-shaped slots absorb: committing an ordinary or lambda-parameter
// variable to `unknown` would poison its real solution.
function absorbs_unknown(policy: VarPolicy) -> bool throws never {
    match (policy) {
        VarPolicy.ContainerSlot => true,
        VarPolicy.Value | VarPolicy.Effect | VarPolicy.LambdaParam | VarPolicy.MapKeySlot => false,
    }
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::VarPolicy::defaults_to_never @ d9be6853b
// Whether an unconstrained class defaults to `never` at finalize instead of
// erroring.
function defaults_to_never(policy: VarPolicy) -> bool throws never {
    match (policy) {
        VarPolicy.Effect => true,
        VarPolicy.Value | VarPolicy.LambdaParam | VarPolicy.ContainerSlot | VarPolicy.MapKeySlot => {
            false
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::VarPolicy::join @ d9be6853b
// The class policy after a var-var union. `Value` is the identity; a lambda
// parameter absorbed into a container class takes that class's policy (its
// behavior set is a strict superset). An effect class keeps its policy: a
// throws channel cannot afford to lose its `never` default.
function join(policy: VarPolicy, other: VarPolicy) -> VarPolicy throws never {
    match (policy, other) {
        (VarPolicy.Effect, _) | (_, VarPolicy.Effect) => VarPolicy.Effect,
        (VarPolicy.Value, let o) => o,
        (let o, VarPolicy.Value) => o,
        (VarPolicy.LambdaParam, let o) => o,
        (let o, VarPolicy.LambdaParam) => o,
        (VarPolicy.MapKeySlot, _) | (_, VarPolicy.MapKeySlot) => VarPolicy.MapKeySlot,
        // Only (ContainerSlot, ContainerSlot) is left.
        _ => VarPolicy.ContainerSlot,
    }
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::VarValue @ d9be6853b
// Solver state of a variable's equivalence class. Policy is unsolved-only
// state, so it lives inside that variant: solving retires it, and a rollback
// of the solving step restores the `Unsolved` value, policy included.
type VarValue = VarValueUnsolved | VarValueSolved;

class VarValueUnsolved {
    policy: VarPolicy,
    // The block-scope depth the class was minted in (see
    // `InferenceTable.bind_scoped_param`): a solution may mention a scoped
    // `let type T = ...` parameter only from a depth at most this. A var-var
    // union keeps the shallower depth.
    universe: int,
    // Whether the class has been related to the `Error` sentinel: it then
    // owes no "cannot infer" of its own. A var-var union keeps the taint of
    // either side; a rollback reverts it.
    tainted: bool,
}

class VarValueSolved {
    value: int,
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::VarValue::unify_values @ d9be6853b
// ena's value merge. Two solved roots never merge (`unify` shallow-resolves
// first); solving retires the policy; two open classes join.
function unify_values(a: VarValue, b: VarValue) -> VarValue throws never {
    match (a, b) {
        (let _solved: VarValueSolved, VarValueSolved) => {
            baml.sys.panic(
                "unify shallow-resolves before relating, so two solved roots never merge",
            )
        },
        (let solved: VarValueSolved, VarValueUnsolved) => solved,
        (VarValueUnsolved, let solved: VarValueSolved) => solved,
        (let ua: VarValueUnsolved, let ub: VarValueUnsolved) => {
            VarValueUnsolved {
                policy: join(ua.policy, ub.policy),
                universe: if (ua.universe < ub.universe) {
                    ua.universe
                } else {
                    ub.universe
                },
                tainted: ua.tainted || ub.tainted,
            }
        },
    }
}

// port: ena 0.14.4 unify::UnificationTable (external crate) @ d9be6853b
// The subset of ena's `InPlaceUnificationTable` the inference table uses.
// Union by rank: the higher rank becomes the root; on a tie the first root
// redirects to the second, whose rank grows. Every write while a snapshot is
// open is logged, and a rollback replays the log backwards (a key minted
// inside the snapshot is popped, freeing its index for reuse).
class UnificationTable {
    parents: int[],
    ranks: int[],
    values: VarValue[],
    undo_log: UndoEntry[],
    num_open_snapshots: int,

    function new() -> Self {
        UnificationTable { parents: [], ranks: [], values: [], undo_log: [], num_open_snapshots: 0 }
    }

    function len(self) -> int throws never {
        self.values.length()
    }

    function new_key(self, value: VarValue) -> int throws never {
        let index = self.values.length();
        self.parents.push(index);
        self.ranks.push(0);
        self.values.push(value);
        if (self.num_open_snapshots > 0) {
            self.undo_log.push(UndoNewElem { index: index });
        }
        index
    }

    // ena's `update_value`: one logged write of a key's whole entry.
    function update(
        self,
        index: int,
        parent: int,
        rank: int,
        value: VarValue,
    ) -> void throws never {
        if (self.num_open_snapshots > 0) {
            self.undo_log.push(
                UndoSetElem {
                    index: index,
                    parent: self.parents[index],
                    rank: self.ranks[index],
                    value: self.values[index],
                },
            );
        }
        self.parents[index] = parent;
        self.ranks[index] = rank;
        self.values[index] = value;
    }

    function find(self, key: int) -> int throws never {
        let current = key;
        while (self.parents[current] != current) {
            current = self.parents[current];
        }
        current
    }

    function probe_value(self, key: int) -> VarValue throws never {
        self.values[self.find(key)]
    }

    function unioned(self, a: int, b: int) -> bool throws never {
        self.find(a) == self.find(b)
    }

    function union(self, a: int, b: int) -> void throws never {
        let root_a = self.find(a);
        let root_b = self.find(b);
        if (root_a == root_b) {
            return;
        }
        let combined = unify_values(self.values[root_a], self.values[root_b]);
        let rank_a = self.ranks[root_a];
        let rank_b = self.ranks[root_b];
        if (rank_a > rank_b) {
            self.redirect_root(rank_a, root_b, root_a, combined);
        } else if (rank_a < rank_b) {
            self.redirect_root(rank_b, root_a, root_b, combined);
        } else {
            self.redirect_root(rank_a + 1, root_a, root_b, combined);
        }
    }

    function redirect_root(
        self,
        new_rank: int,
        old_root: int,
        new_root: int,
        new_value: VarValue,
    ) -> void throws never {
        self.update(old_root, new_root, self.ranks[old_root], self.values[old_root]);
        self.update(new_root, new_root, new_rank, new_value);
    }

    function union_value(self, key: int, value: VarValue) -> void throws never {
        let root_key = self.find(key);
        self.update(
            root_key,
            root_key,
            self.ranks[root_key],
            unify_values(self.values[root_key], value),
        );
    }

    // The undo-log position to roll back to.
    function snapshot(self) -> int throws never {
        self.num_open_snapshots += 1;
        self.undo_log.length()
    }

    function rollback_to(self, snapshot: int) -> void throws never {
        while (self.undo_log.length() > snapshot) {
            match (self.undo_log.pop()) {
                UndoNewElem => {
                    self.parents.pop();
                    self.ranks.pop();
                    self.values.pop();
                },
                let set: UndoSetElem => {
                    self.parents[set.index] = set.parent;
                    self.ranks[set.index] = set.rank;
                    self.values[set.index] = set.value;
                },
                null => {},
            }
        }
        self.num_open_snapshots -= 1;
    }

    function commit(self, snapshot: int) -> void throws never {
        self.num_open_snapshots -= 1;
        if (self.num_open_snapshots == 0) {
            self.undo_log.clear();
        }
    }
}

// ena's undo-log entries: a key minted, or a key's previous entry.
type UndoEntry = UndoNewElem | UndoSetElem;

class UndoNewElem {
    index: int,
}

class UndoSetElem {
    index: int,
    parent: int,
    rank: int,
    value: VarValue,
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::collect_infer_vars @ d9be6853b
// Every inference variable `ty` names, in walk order (`ty` is expected to be
// resolved, so each is an open class or an alias of one).
// Restructured: takes the pool the handle indexes.
function collect_infer_vars(pool: root.types.InferPool, ty: int, out: int[]) -> void throws never {
    if (!pool.has_infer(ty)) {
        return;
    }
    let kind = pool.kinds[ty];
    if let v: root.types.TyInferVar = kind {
        out.push(v.var);
        return;
    }
    for (let child in root.types.children_infer_ty(kind)) {
        collect_infer_vars(pool, child, out);
    }
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::UnifyError @ d9be6853b
// A structural mismatch: the innermost pair of types that failed to unify.
// `escaped` names the block-scoped parameter when the failure is a solution
// that would leave its block (`right` mentions it; `left` is the variable),
// rather than a shape mismatch.
class UnifyError {
    left: int,
    right: int,
    escaped: root.types.ParamTy?,
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::Bound @ d9be6853b
// One deposited bound and where it was deposited: the expression the
// relation was checked at, when the road had one (a pattern walk has none).
class Bound {
    ty: int,
    anchor: int?,
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::VarBounds @ d9be6853b
// Sub-constraint evidence accumulated on an unsolved variable's class: lower
// bounds are values flowing INTO the variable, upper bounds are contexts it
// flows into.
class VarBounds {
    lowers: Bound[],
    uppers: Bound[],

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::VarBounds (derived Default) @ d9be6853b
    function default() -> Self {
        VarBounds { lowers: [], uppers: [] }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::VarBounds (derived Clone) @ d9be6853b
    // New arrays: the table pushes into a class's bounds in place.
    function clone(self) -> VarBounds throws never {
        VarBounds { lowers: self.lowers.concat([]), uppers: self.uppers.concat([]) }
    }
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::Snapshot @ d9be6853b
// A revertible point in the table's history. The bounds map is snapshotted by
// copy; the union-find's undo log covers every class's value.
class Snapshot {
    // The union-find's undo-log position.
    vars: int,
    bounds: map<int, VarBounds>,
    // The scope depth the snapshot was taken at. Not restored.
    universe: int,
}

// port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable @ d9be6853b
class InferenceTable {
    // Restructured: the pool every handle the table sees indexes.
    pool: root.types.InferPool,
    vars: UnificationTable,
    // Bounds per CLASS, keyed by the root's index; var-var unions merge the
    // two roots' entries.
    bounds: map<int, VarBounds>,
    // The current block-scope depth: how many `let type T = ...` bindings are
    // open. Fresh variables record it. Not part of a snapshot.
    universe: int,
    // The depth each scoped parameter was bound at, by parameter index.
    // Append-only, so it needs no rollback either.
    scoped_params: map<int, int>,

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::new @ d9be6853b
    // Restructured: takes the pool.
    function new(pool: root.types.InferPool) -> Self {
        InferenceTable {
            pool: pool,
            vars: UnificationTable.new(),
            bounds: {},
            universe: 0,
            scoped_params: {},
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::new_var @ d9be6853b
    // Allocates a fresh, unconstrained variable of `policy`.
    // Restructured: also `new_var_of`, as the `policy` parameter.
    function new_var(self, policy: VarPolicy = VarPolicy.Value) -> int throws never {
        self.vars.new_key(
            VarValueUnsolved { policy: policy, universe: self.universe, tainted: false },
        )
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::bind_scoped_param @ d9be6853b
    // Opens the scope of a block-level `let type T = ...` binding: variables
    // minted from here until the matching `close_scopes_to` live one universe
    // deeper and may be solved to `param`; variables minted outside may not.
    // The scope opens at the STATEMENT, not the block. Depths are reused by
    // sibling blocks, which is sound because closing a scope retires its
    // parameters (see `close_scopes_to`).
    function bind_scoped_param(self, param: root.types.ParamTy) -> void throws never {
        self.universe += 1;
        self.scoped_params.set(param.index, self.universe);
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::close_scopes_to @ d9be6853b
    // Closes every scope deeper than `depth`, the enclosing block's count of
    // open bindings. A closed parameter is RETIRED: it keeps a registration,
    // so a later mention still counts as escaping, at a depth no variable can
    // be minted at.
    function close_scopes_to(self, depth: int) -> void throws never {
        for (let index in self.scoped_params.keys()) {
            if (self.scoped_params[index] > depth) {
                self.scoped_params.set(index, RETIRED_DEPTH);
            }
        }
        self.universe = depth;
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::unsolved_vars_deeper_than @ d9be6853b
    // The root of every still-open class minted deeper than `depth`: the
    // variables a closing block leaves behind, in index order.
    function unsolved_vars_deeper_than(self, depth: int) -> int[] throws never {
        let out: int[] = [];
        for (let index = 0; index < self.vars.len(); index += 1) {
            if (self.vars.find(index) != index) {
                continue;
            }
            if let open: VarValueUnsolved = self.vars.probe_value(index) {
                if (open.universe > depth) {
                    out.push(index);
                }
            }
        }
        out
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::demote_to @ d9be6853b
    // Moves `var`'s open class out to `depth`: the block that minted it has
    // closed. A class already at or above `depth`, or solved, is left alone.
    function demote_to(self, var: int, depth: int) -> void throws never {
        let open = self.vars.probe_value(var);
        if (!(open is VarValueUnsolved) || open.universe <= depth) {
            return;
        }
        self.vars.union_value(
            var,
            VarValueUnsolved { policy: open.policy, universe: depth, tainted: open.tainted },
        );
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::escaping_scoped_param @ d9be6853b
    // The first block-scoped parameter in `ty` (through solved variables)
    // that `var`'s class may not take as a solution: one bound deeper than the
    // class was minted, or one this table never saw bound. `null` for a
    // solved class: its solution was judged when it was made.
    function escaping_scoped_param(self, var: int, ty: int) -> root.types.ParamTy? throws never {
        // No body binds a scoped parameter in the common case, and this sits
        // on every solve and bound deposit: skip the resolution walk.
        if (!self.scoped_params) {
            return null;
        }
        let open = self.vars.probe_value(var);
        if (!(open is VarValueUnsolved)) {
            return null;
        }
        self.walk(open.universe, self.resolve_completely(ty))
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::escaping_scoped_param::walk @ d9be6853b
    // Restructured: a method (it reads `scoped_params`) returning the first
    // escape instead of filling an out-parameter.
    function walk(self, universe: int, ty: int) -> root.types.ParamTy? throws never {
        if (!self.pool.has_typevar(ty)) {
            return null;
        }
        let kind = self.pool.kinds[ty];
        if let v: root.types.TyTypeVar = kind {
            if (v.param.is_scoped()) {
                let depth = self.scoped_params.get(v.param.index);
                if (depth == null || depth > universe) {
                    return v.param;
                }
            }
        }
        for (let child in root.types.children_infer_ty(kind)) {
            let escaped = self.walk(universe, child);
            if (escaped != null) {
                return escaped;
            }
        }
        null
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::new_var_ty @ d9be6853b
    // A fresh variable of `policy`, as a type.
    // Restructured: also `new_var_ty_of`, as the `policy` parameter.
    function new_var_ty(self, policy: VarPolicy = VarPolicy.Value) -> int throws never {
        self.pool.add(root.types.TyInferVar { var: self.new_var(policy = policy) })
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::unsolved_policy @ d9be6853b
    // What `var`'s still-open equivalence class IS. `null` once solved:
    // policy retires at solution.
    function unsolved_policy(self, var: int) -> VarPolicy? throws never {
        match (self.vars.probe_value(var)) {
            let open: VarValueUnsolved => open.policy,
            VarValueSolved => null,
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::unsolved_root_var @ d9be6853b
    // The canonical representative when `var`'s equivalence class still
    // lacks a solution.
    function unsolved_root_var(self, var: int) -> int? throws never {
        let root_var = self.vars.find(var);
        if (self.vars.probe_value(root_var) is VarValueUnsolved) {
            root_var
        } else {
            null
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::taint_vars_in @ d9be6853b
    // Marks every open class `ty` names (through solved variables) as related
    // to the `Error` sentinel. A solved class is left alone.
    function taint_vars_in(self, ty: int) -> void throws never {
        for (let root_var in self.open_roots_in(ty)) {
            self.taint_root(root_var);
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::open_roots_in @ d9be6853b
    // The roots of the open classes `ty` names (through solved variables),
    // each once, in walk order.
    function open_roots_in(self, ty: int) -> int[] throws never {
        if (!self.pool.has_infer(ty)) {
            return [];
        }
        let vars: int[] = [];
        collect_infer_vars(self.pool, self.resolve_completely(ty), vars);
        let roots: int[] = [];
        for (let var in vars) {
            let root_var = self.unsolved_root_var(var);
            if (root_var != null && !roots.includes(root_var)) {
                roots.push(root_var);
            }
        }
        roots
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::promote_to_effect @ d9be6853b
    // Makes `var`'s open VALUE class an EFFECT class. Only a still-plain value
    // class is promoted.
    function promote_to_effect(self, var: int) -> void throws never {
        let key = self.vars.find(var);
        let open = self.vars.probe_value(key);
        if (!(open is VarValueUnsolved) || open.policy != VarPolicy.Value) {
            return;
        }
        self.vars.union_value(
            key,
            VarValueUnsolved {
                policy: VarPolicy.Effect,
                universe: open.universe,
                tainted: open.tainted,
            },
        );
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::taint_root @ d9be6853b
    // Marks the open class rooted at `root_var` as related to the `Error`
    // sentinel.
    function taint_root(self, root_var: int) -> void throws never {
        let key = self.vars.find(root_var);
        let open = self.vars.probe_value(key);
        if (!(open is VarValueUnsolved) || open.tainted) {
            return;
        }
        // The merge's policy join and universe min are idempotent, so only
        // the taint changes.
        self.vars.union_value(
            key,
            VarValueUnsolved { policy: open.policy, universe: open.universe, tainted: true },
        );
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::is_tainted @ d9be6853b
    // Whether `var`'s open class was related to the `Error` sentinel. A
    // solved class is never tainted.
    function is_tainted(self, var: int) -> bool throws never {
        match (self.vars.probe_value(var)) {
            let open: VarValueUnsolved => open.tainted,
            VarValueSolved => false,
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::default_unsolved_effects_to_never @ d9be6853b
    // Defaults every still-unsolved effect class to `never`, except the
    // classes rooted in `keep_open`. Returns whether any class was defaulted.
    function default_unsolved_effects_to_never(self, keep_open: int[]) -> bool throws never {
        let keep_roots = keep_open.map((var) -> {
            self.vars.find(var)
        });
        let defaulted = false;
        for (let index = 0; index < self.vars.len(); index += 1) {
            let open = self.vars.probe_value(index);
            if (
                open is VarValueUnsolved
                    && defaults_to_never(open.policy)
                    && !keep_roots.includes(self.vars.find(index))
            ) {
                self.vars.union_value(
                    index,
                    VarValueSolved { value: self.pool.add(root.types.TyNever {}) },
                );
                defaulted = true;
            }
        }
        defaulted
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::shallow_resolve @ d9be6853b
    // Replaces a solved variable at the ROOT of `ty` with its solution,
    // repeatedly; never descends into children.
    function shallow_resolve(self, ty: int) -> int throws never {
        let current = ty;
        while let v: root.types.TyInferVar = self.pool.kinds[current] {
            match (self.vars.probe_value(v.var)) {
                let solved: VarValueSolved => {
                    current = solved.value;
                },
                VarValueUnsolved => {
                    return current;
                },
            }
        }
        current
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::resolve_completely @ d9be6853b
    // Substitutes every solved variable in `ty`, at any depth. Unresolved
    // variables remain.
    function resolve_completely(self, ty: int) -> int throws never {
        if (!self.pool.has_infer(ty)) {
            return ty;
        }
        let resolved = self.shallow_resolve(ty);
        if (!self.pool.has_infer(resolved)) {
            return resolved;
        }
        self.pool.add(
            root.types.map_children(self.pool.kinds[resolved], (child) -> {
                self.resolve_completely(child)
            }),
        )
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::unify @ d9be6853b
    // Eagerly unifies `left` and `right` structurally, solving variables.
    // Symmetric; errors carry the innermost mismatching pair.
    function unify(self, left: int, right: int) -> void throws UnifyError {
        let l = self.shallow_resolve(left);
        let r = self.shallow_resolve(right);
        // Interning makes structural equality handle equality.
        if (l == r) {
            return;
        }
        // Error unifies with everything: a diagnostic was already emitted. The
        // other side's open classes are tainted by it.
        let left_error = self.pool.kinds[l] is root.types.TyError;
        let right_error = self.pool.kinds[r] is root.types.TyError;
        if (left_error || right_error) {
            if (left_error && !right_error) {
                self.taint_vars_in(r);
            } else if (right_error && !left_error) {
                self.taint_vars_in(l);
            }
            return;
        }
        match (self.pool.kinds[l], self.pool.kinds[r]) {
            (let a: root.types.TyInferVar, let b: root.types.TyInferVar) => {
                let root_a = self.vars.find(a.var);
                let root_b = self.vars.find(b.var);
                self.vars.union(a.var, b.var);
                if (root_a != root_b) {
                    let merged_root = self.vars.find(a.var);
                    let merged = self.bounds.delete(root_a) ?? VarBounds.default();
                    let other = self.bounds.delete(root_b) ?? VarBounds.default();
                    merged.lowers = merged.lowers.concat(other.lowers);
                    merged.uppers = merged.uppers.concat(other.uppers);
                    if (merged.lowers || merged.uppers) {
                        self.bounds.set(merged_root, merged);
                    }
                    // The merged class took the shallower universe; every
                    // variable its bounds carry is observable through it now.
                    self.generalize_bounds_into(merged_root);
                }
            },
            (let a: root.types.TyInferVar, _) => self.bind(a.var, r, l),
            (_, let b: root.types.TyInferVar) => self.bind(b.var, l, r),
            _ => self.unify_kinds(l, r),
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::commit_if_ok @ d9be6853b
    // Runs `f` inside a snapshot: rolled back when it throws, committed when
    // it returns.
    function commit_if_ok<T, E>(self, f: (InferenceTable) -> T throws E) -> T throws E {
        let snapshot = self.snapshot();
        let value = f(self) catch_all (err) {
            _ => {
                self.rollback_to(snapshot);
                throw err
            },
        };
        self.commit(snapshot);
        value
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::snapshot @ d9be6853b
    function snapshot(self) -> Snapshot throws never {
        let bounds: map<int, VarBounds> = {};
        for (let key in self.bounds.keys()) {
            bounds.set(key, self.bounds[key].clone());
        }
        Snapshot { vars: self.vars.snapshot(), bounds: bounds, universe: self.universe }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::rollback_to @ d9be6853b
    function rollback_to(self, snapshot: Snapshot) -> void throws never {
        self.vars.rollback_to(snapshot.vars);
        self.bounds = snapshot.bounds;
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::commit @ d9be6853b
    function commit(self, snapshot: Snapshot) -> void throws never {
        self.vars.commit(snapshot.vars);
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::add_lower_bound @ d9be6853b
    // Records a lower bound (a value flowing into the variable), deposited at
    // `anchor`.
    function add_lower_bound(self, var: int, ty: int, anchor: int?) -> void throws never {
        self.generalize_into(var, ty);
        let root_var = self.vars.find(var);
        self.bounds.get_or_insert(root_var, VarBounds.default()).lowers.push(
            Bound { ty: ty, anchor: anchor },
        );
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::add_upper_bound @ d9be6853b
    // Records an upper bound (a context the variable flows into), deposited
    // at `anchor`.
    function add_upper_bound(self, var: int, ty: int, anchor: int?) -> void throws never {
        self.generalize_into(var, ty);
        let root_var = self.vars.find(var);
        self.bounds.get_or_insert(root_var, VarBounds.default()).uppers.push(
            Bound { ty: ty, anchor: anchor },
        );
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::generalize_into @ d9be6853b
    // rustc's generalizer at a relation: once `ty` is a bound or the solution
    // of `var`'s class, every open variable inside it is observable through
    // that class, so it may take no block-scoped parameter the class may not.
    // Each is lowered to the class's universe, and so is everything that can
    // flow into it (the open variables in its own bounds, transitively).
    // Universes only differ while some binding is open, so the walk is
    // skipped otherwise.
    function generalize_into(self, var: int, ty: int) -> void throws never {
        if (!self.scoped_params) {
            return;
        }
        let open = self.vars.probe_value(var);
        if (!(open is VarValueUnsolved)) {
            return;
        }
        let universe = open.universe;
        let worklist: int[] = [];
        collect_infer_vars(self.pool, self.resolve_completely(ty), worklist);
        let visited: map<int, bool> = {};
        while let inner: int = worklist.pop() {
            let root_var = self.vars.find(inner);
            if (visited.has(root_var)) {
                continue;
            }
            visited.set(root_var, true);
            let inner_open = self.vars.probe_value(root_var);
            if (!(inner_open is VarValueUnsolved) || inner_open.universe <= universe) {
                continue;
            }
            self.demote_to(root_var, universe);
            let bounds = self.bounds.get(root_var);
            if (bounds != null) {
                for (let bound in bounds.lowers.concat(bounds.uppers)) {
                    collect_infer_vars(self.pool, self.resolve_completely(bound.ty), worklist);
                }
            }
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::generalize_bounds_into @ d9be6853b
    // `generalize_into` over every bound `var`'s class already carries: for a
    // class whose universe just dropped.
    function generalize_bounds_into(self, var: int) -> void throws never {
        if (!self.scoped_params) {
            return;
        }
        let bounds = self.bounds.get(self.vars.find(var));
        if (bounds == null) {
            return;
        }
        for (let bound in bounds.lowers.concat(bounds.uppers)) {
            self.generalize_into(var, bound.ty);
        }
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::var_bounds @ d9be6853b
    // The accumulated bounds of `var`'s equivalence class (empty when none),
    // as a copy.
    function var_bounds(self, var: int) -> VarBounds throws never {
        self.bounds.get(self.vars.find(var))?.clone() ?? VarBounds.default()
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::take_solved_class_bounds @ d9be6853b
    // Bounds accumulated on classes that DIRECT unification has since solved,
    // as `(solution, bounds)` pairs; the ledger entries are removed. Binding a
    // variable must discharge its pending evidence by replay, never by
    // dropping it.
    // Restructured: roots in ascending index, where Rust follows FxHashMap
    // order.
    function take_solved_class_bounds(self) -> (int, VarBounds)[] throws never {
        let roots = self.bounds.keys().sort_by_key((key) -> {
            key
        });
        let out: (int, VarBounds)[] = [];
        for (let root_var in roots) {
            if let solved: VarValueSolved = self.vars.probe_value(root_var) {
                let bounds = self.bounds.delete(root_var) ?? VarBounds.default();
                out.push((solved.value, bounds));
            }
        }
        out
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::unsolved_bounded_vars @ d9be6853b
    // Every still-unsolved class that has accumulated bounds, as
    // `(representative var, bounds)`, in index order. Resolution input.
    function unsolved_bounded_vars(self) -> (int, VarBounds)[] throws never {
        let out: (int, VarBounds)[] = [];
        for (let root_var in self.bounds.keys()) {
            if (self.vars.probe_value(root_var) is VarValueUnsolved) {
                out.push((root_var, self.bounds[root_var].clone()));
            }
        }
        out.sort_by_key((entry) -> {
            entry.0
        })
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::is_solved @ d9be6853b
    // Whether `var`'s class already carries a solution. A generalization step
    // can ALIAS two listed vars mid-pass, so the later var must be re-checked
    // before acting on it.
    function is_solved(self, var: int) -> bool throws never {
        self.vars.probe_value(var) is VarValueSolved
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::solve @ d9be6853b
    // Solves `var := ty` directly (resolution-time binding; no occurs check
    // because the solution was derived from resolved bounds).
    function solve(self, var: int, ty: int) -> void throws never {
        self.generalize_into(var, ty);
        self.vars.union_value(var, VarValueSolved { value: ty });
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::bind @ d9be6853b
    // Solves `var := ty` after the occurs check. `var_ty` is the variable as a
    // type, for the error value.
    function bind(self, var: int, ty: int, var_ty: int) -> void throws UnifyError {
        if (self.occurs(var, ty)) {
            throw UnifyError { left: var_ty, right: ty, escaped: null };
        }
        let escaped = self.escaping_scoped_param(var, ty);
        if (escaped != null) {
            throw UnifyError { left: var_ty, right: ty, escaped: escaped };
        }
        self.generalize_into(var, ty);
        self.vars.union_value(var, VarValueSolved { value: ty });
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::occurs @ d9be6853b
    // Whether `var`'s equivalence class occurs anywhere inside `ty`
    // (resolving through solved variables). Binding on occurrence would build
    // an infinite type.
    function occurs(self, var: int, ty: int) -> bool throws never {
        if (!self.pool.has_infer(ty)) {
            return false;
        }
        let kind = self.pool.kinds[ty];
        if let v: root.types.TyInferVar = kind {
            if (self.vars.unioned(v.var, var)) {
                return true;
            }
            let resolved = self.shallow_resolve(ty);
            if (resolved == ty) {
                return false;
            }
            return self.occurs(var, resolved);
        }
        root.types.children_infer_ty(kind).some((child) -> {
            self.occurs(var, child)
        })
    }

    // port: baml_compiler2_hir_ty/src/infer/unify.rs::InferenceTable::unify_kinds @ d9be6853b
    // Structural unification of two non-var, non-equal heads: same head with
    // identical non-child payload recurses on children; anything else is a
    // mismatch. Leaf pairs never match here: equal leaves were caught by
    // handle equality in `unify`.
    function unify_kinds(self, left: int, right: int) -> void throws UnifyError {
        let mismatch = UnifyError { left: left, right: right, escaped: null };
        let zip = (ls: int[], rs: int[]) -> (int, int)[] {
            let out: (int, int)[] = [];
            for (let i = 0; i < ls.length(); i += 1) {
                out.push((ls[i], rs[i]));
            }
            out
        };
        let pairs: (int, int)[] = match (self.pool.kinds[left], self.pool.kinds[right]) {
            (let l: root.types.InferTyClass, let r: root.types.InferTyClass)
                if l.name == r.name && l.args.length() == r.args.length() => zip(l.args, r.args),
            (let l: root.types.InferTyList, let r: root.types.InferTyList) => [(l.elem, r.elem)],
            (let l: root.types.InferTyTuple, let r: root.types.InferTyTuple)
                if l.items.length() == r.items.length() => zip(l.items, r.items),
            (let l: root.types.InferTyMap, let r: root.types.InferTyMap) => {
                [(l.key, r.key), (l.value, r.value)]
            },
            (let l: root.types.InferTyFuture, let r: root.types.InferTyFuture) => {
                [(l.value, r.value), (l.error, r.error)]
            },
            // Positional; the ACI (reorder/absorb) equality class defers to
            // the budgeted machinery that lands with Sub constraints.
            (let l: root.types.InferTyUnion, let r: root.types.InferTyUnion)
                if l.members.length() == r.members.length() => zip(l.members, r.members),
            (let l: root.types.InferTyInterface, let r: root.types.InferTyInterface)
                if l.name == r.name
                && l.args.length() == r.args.length()
                && l.associated_types.map((binding) -> {
                    binding.name
                })
                    == r.associated_types.map((binding) -> {
                        binding.name
                    }) => {
                zip(l.args, r.args).concat(
                    zip(
                        l.associated_types.map((binding) -> {
                            binding.ty
                        }),
                        r.associated_types.map((binding) -> {
                            binding.ty
                        }),
                    ),
                )
            },
            (let l: root.types.InferTyFunction, let r: root.types.InferTyFunction)
                if l.params.map((p) -> {
                (p.name, p.mode)
            })
                == r.params.map((p) -> {
                    (p.name, p.mode)
                }) => {
                zip(
                    l.params.map((p) -> {
                        p.ty
                    }),
                    r.params.map((p) -> {
                        p.ty
                    }),
                )
                    .concat([(l.ret, r.ret), (l.throws_, r.throws_)])
            },
            _ => {
                throw mismatch
            },
        };
        for (let pair in pairs) {
            self.unify(pair.0, pair.1);
        }
    }
}
