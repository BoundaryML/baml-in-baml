// Rust has no test for `from_aliases`; this one guards the work-stack
// rewrite of `ty_has_cycle`.

test "from aliases marks the aliases that reach a cycle" {
    let alias = (name: string) -> Ty {
        TyTypeAlias { name: local_decl(name) }
    };
    let aliases: map<DeclName, Ty> = {};
    // A = B[] and B = A | null: a cycle through a list.
    aliases.set(local_decl("A"), TyList { elem: alias("B") });
    aliases.set(local_decl("B"), TyUnion { members: [alias("A"), TyNull {}] });
    // Plain = map<string, int>: no alias at all.
    aliases.set(local_decl("Plain"), TyMap { key: TyString {}, value: TyInt {} });
    // Uses = Plain | Plain: reaches an alias twice, no cycle.
    aliases.set(local_decl("Uses"), TyUnion { members: [alias("Plain"), alias("Plain")] });
    // Into = A: reaches the cycle without being on it, which Rust counts too.
    aliases.set(local_decl("Into"), alias("A"));
    let recursive = ResolvedAliases.from_aliases(aliases).recursive;
    let names = recursive.keys()
        .map((n) -> {
            n.name
        })
        .sort_by_key((n) -> {
            n
        });
    assert.equal(names, ["A", "B", "Into"])
}
