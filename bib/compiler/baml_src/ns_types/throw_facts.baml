// port: baml_type/src/throw_facts.rs @ d9be6853b
//
// Per-function throw-analysis facts: the inputs to the package-level
// throw-inference solve (`hir_ty`'s throw_facts), everything extracted from
// one function's signature and body that the call-graph fixpoint needs.
//
// Not ported: `try_map_heads` and the head parameter `N`. Rust converts the
// facts between DeclName and the cache manifest's PathName heads at the seed
// boundary; seeded inputs are absent here, so the facts stay DeclName-headed.

// port: baml_type/src/throw_facts.rs::FunctionThrowFacts @ d9be6853b
// Rust's `BTreeSet`s are `map<T, bool>` (IDIOMS): the sets keep insertion
// order, not Rust's `Ord` order, so a consumer that lists them in order
// sorts first.
class FunctionThrowFacts {
    // Solver key (`throw_set_key` form: namespace-qualified short name).
    key: string,
    // Direct throw facts: the declared `throws` clause (when closed) or the
    // facts collected from the body, as the solver seeds its nodes.
    direct: map<Ty, bool>,
    // Same-package call targets (edges of the propagation graph).
    call_edges: map<string, bool>,
    // A closed declared `throws` clause acts as a propagation firewall.
    has_declared_contract: bool,
}
