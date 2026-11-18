// port: baml_type/src/pattern_overlap.rs @ d9be6853b
//
// The `match`/`is` pattern reachability oracle. Decides whether a pattern's
// denoted type-set can intersect a scrutinee member's under some realization
// of the in-scope rigid type variables: Yes / Unknown (possibly reachable,
// the arm keeps its runtime test) vs No (provably dead). Built on the
// equality-unification core (unify.baml). Ground rules: a rigid variable is
// potentially unifiable, never necessarily; bounds refute, never confirm;
// uncertainty degrades to possible.
//
// Restructured:
// - PatternOverlapEnv.aliases is a `map<DeclName, Ty>` (AliasMap is not
//   ported, see unify.baml); the `implements` field is `implements_`
//   (keyword).
// - ImplementsOracle is a function type `(Ty, InterfaceConstraint) -> bool`.
// - pattern_overlap and its depth-capped worker pattern_overlap_at are one
//   function with a named `depth = 0` default.
// - `RealizedTy::try_from(t).is_ok()` is a narrow_ty_to_realized_ty call
//   whose NarrowError is caught (`realized`).
//
// Not ported: the debug_assert in pattern_pair_overlap.

// port: baml_type/src/pattern_overlap.rs::TypeVarBoundsMap @ d9be6853b
// In-scope rigid type parameters mapped to their declared interface bounds
// (`T extends I` conjunctions).
type TypeVarBoundsMap = map<ParamTy, InterfaceConstraint[]>;

// port: baml_type/src/pattern_overlap.rs::ImplementsOracle @ d9be6853b
// "Does this realized type implement this interface?", abstracted from the
// impl registry. Consulted only with fully-realized inputs and only to
// refute: `false` must mean "provably does not implement".
type ImplementsOracle = (Ty, InterfaceConstraint) -> bool throws never;

// port: baml_type/src/pattern_overlap.rs::PatternOverlapEnv @ d9be6853b
// Everything pattern_overlap needs to know about the enclosing scope and
// program.
class PatternOverlapEnv {
    // Every in-scope rigid type parameter, shared by name across both sides.
    // A variable absent from this set is an opaque atom: callers acting on
    // `No` must first check every free type variable of both inputs is here.
    vars: ParamTy[],
    // Interface bounds of the rigid params. They only ever refute.
    bounds: TypeVarBoundsMap,
    // Type-alias bodies, pre-folded to nf's canonical union form.
    aliases: map<DeclName, Ty>,
    // Which roots hold the language packages.
    lang: root.base.LangRoots,
    // Enum schemas for nf's complete-variant folding.
    enum_variants: EnumVariants,
    // See ImplementsOracle (`implements` is a keyword).
    implements_: ImplementsOracle,

    // port: baml_type/src/pattern_overlap.rs::PatternOverlapEnv::alias_ctx @ d9be6853b
    // The alias-equivalence context over this scope's aliases.
    function alias_ctx(self) -> AliasEquivCtx throws never {
        AliasEquivCtx { aliases: self.aliases, lang: self.lang }
    }
}

// port: baml_type/src/pattern_overlap.rs::pattern_overlap @ d9be6853b
// port: baml_type/src/pattern_overlap.rs::pattern_overlap_at @ d9be6853b
// Can the type-set denoted by `pat` intersect the set denoted by `member`
// under some realization of the in-scope rigid type variables? Normalizes,
// expands the alias head, and decomposes top-level unions into a disjunction
// of member pairs (intersection distributes over union). The depth cap bounds
// alias-cycle expansion through union members; hitting it is Unknown.
function pattern_overlap(
    pat: Ty,
    member: Ty,
    env_: PatternOverlapEnv,
    depth: int = 0,
) -> Overlap throws never {
    if (depth >= MAX_UNIFY_DEPTH) {
        return Overlap.Unknown;
    }
    let aliases = env_.alias_ctx();
    let pat_nf = nf(expand_alias_head(pat, aliases), env_.enum_variants);
    let member_nf = nf(expand_alias_head(member, aliases), env_.enum_variants);
    let pats = union_members(pat_nf);
    let members = union_members(member_nf);
    if (pats.length() == 1 && members.length() == 1) {
        return pattern_pair_overlap(pats[0], members[0], env_);
    }
    let result: Overlap = Overlap.No;
    for (let p in pats) {
        for (let m in members) {
            match (pattern_overlap(p, m, env_, depth = depth + 1)) {
                Overlap.Yes => {
                    return Overlap.Yes;
                },
                Overlap.Unknown => {
                    result = Overlap.Unknown;
                },
                Overlap.No => {},
            }
        }
    }
    result
}

// port: baml_type/src/pattern_overlap.rs::union_members @ d9be6853b
// The members a type contributes to a top-level union meet: a union's member
// list, any other type as the singleton `{ty}`.
function union_members(ty: Ty) -> Ty[] throws never {
    match (ty) {
        let u: TyUnion => u.members,
        _ => [ty],
    }
}

// port: baml_type/src/pattern_overlap.rs::pattern_pair_overlap @ d9be6853b
// One decomposed (non-union) pattern/member pair. Equality-unification
// decides the bulk; the pairs equality wrongly calls disjoint are rescued by
// the top-level meet. A surviving overlap is then checked against the rigid
// params' interface bounds, which can refute it.
function pattern_pair_overlap(
    pat: Ty,
    member: Ty,
    env_: PatternOverlapEnv,
) -> Overlap throws never {
    // `never` is the empty set: it overlaps nothing, not even itself.
    if (pat is TyNever || member is TyNever) {
        return Overlap.No;
    }
    // `unknown` is the top type: every inhabited type shares values with it,
    // so nothing is pinned and bounds cannot refute.
    if (pat is TyUnknown || member is TyUnknown) {
        return Overlap.Yes;
    }
    // A bare in-scope rigid var meeting an interface existential is
    // membership at the pair's top level: always possible in the open world
    // and never refutable through the var's own bounds.
    let bare_rigid = (t: Ty) -> bool {
        match (t) {
            let v: TyTypeVar => env_.vars.includes(v.param),
            _ => false,
        }
    };
    if ((bare_rigid(pat) && member is TyInterface) || (pat is TyInterface && bare_rigid(member))) {
        return Overlap.Yes;
    }
    let bindings: TypeBindings = {};
    let result = unify_into(pat, member, env_.vars, env_.alias_ctx(), bindings);
    if (result == Overlap.No) {
        result = pattern_atom_meet(pat, member, env_);
        // A meet rescue proves possibility without a witness substitution;
        // bindings left by the failed equality attempt must not feed bound
        // refutation.
        bindings.clear();
    }
    if (result != Overlap.No && pattern_bounds_refute(pat, member, bindings, env_)) {
        return Overlap.No;
    }
    result
}

// port: baml_type/src/pattern_overlap.rs::pattern_atom_meet @ d9be6853b
// The top-level meets that value-set intersection has and
// equality-unification lacks. Only consulted after unify_into answered `No`.
function pattern_atom_meet(pat: Ty, member: Ty, env_: PatternOverlapEnv) -> Overlap throws never {
    // A literal shares its values with its base, an enum variant with its
    // enum; symmetric, since intersection is.
    if (is_literal_subtype(pat, member) || is_literal_subtype(member, pat)) {
        return Overlap.Yes;
    }
    match (pat, member) {
        // Error sentinels overlap nothing (mirrors unify_into).
        (TyError, _) => Overlap.No,
        (_, TyError) => Overlap.No,
        // `unknown` is the top type.
        (TyUnknown, _) => Overlap.Yes,
        (_, TyUnknown) => Overlap.Yes,
        // An opaque `$rust_type` could coincide with anything.
        (TyRustType, _) => Overlap.Yes,
        (_, TyRustType) => Overlap.Yes,
        // A residual projection could stand for any type.
        (TyAssociatedTypeProjection, _) => Overlap.Yes,
        (_, TyAssociatedTypeProjection) => Overlap.Yes,
        // Two interface-existentials always possibly meet (a common
        // implementor may be loaded later), same-name ones with different
        // args included.
        (let _a: TyInterface, let _b: TyInterface) => Overlap.Yes,
        // Concrete-vs-existential is membership.
        (TyInterface, _) => interface_membership_overlap(pat, member, env_),
        (_, TyInterface) => interface_membership_overlap(member, pat, env_),
        // Two non-equal function types can still share values (a common
        // structural subtype): conservatively possible.
        (let _a: TyFunction, let _b: TyFunction) => Overlap.Yes,
        // Unreachable by construction (the caller decomposes unions); fail
        // toward possible.
        (TyUnion, _) => Overlap.Unknown,
        (_, TyUnion) => Overlap.Unknown,
        // Every remaining pair is genuinely disjoint.
        _ => Overlap.No,
    }
}

// port: baml_type/src/pattern_overlap.rs::interface_membership_overlap @ d9be6853b
// Concrete-type-vs-interface-existential membership: possible unless every
// input is fully realized and the registry proves `other` cannot implement
// the existential's interface. Literals and enum variants stay possible.
function interface_membership_overlap(
    iface: Ty,
    other: Ty,
    env_: PatternOverlapEnv,
) -> Overlap throws never {
    let constraint = as_interface(iface) ?? baml.sys.panic("caller matched `Ty::Interface`");
    if (
        other is TyLiteral
            || other is TyEnumVariant
            || !realized(other)
            || !tys(constraint).every(realized)
    ) {
        return Overlap.Yes;
    }
    let oracle = env_.implements_;
    if (oracle(other, constraint)) {
        Overlap.Yes
    } else {
        Overlap.No
    }
}

// port: baml_type/src/pattern_overlap.rs::interface_membership_overlap @ d9be6853b
// `RealizedTy::try_from(t).is_ok()`.
function realized(t: Ty) -> bool throws never {
    let r: RealizedTy? = narrow_ty_to_realized_ty(t) catch (e) {
        NarrowError => null,
    };
    r != null
}

// port: baml_type/src/pattern_overlap.rs::pattern_bounds_refute @ d9be6853b
// Refute a surviving pair overlap through the rigid params' interface
// bounds: true iff some rigid param was pinned to a ground witness that
// provably cannot realize it. A bounded param must realize to a concrete
// type, so a union or interface-existential witness fails structurally. A
// param under a union on either side may have a non-principal witness from
// the covering search, so it is skipped.
function pattern_bounds_refute(
    pat: Ty,
    member: Ty,
    bindings: TypeBindings,
    env_: PatternOverlapEnv,
) -> bool throws never {
    if (bindings.length() == 0) {
        return false;
    }
    // Every rigid param resolved through the binding chains.
    let witnesses: TypeBindings = {};
    for (let name in env_.vars) {
        witnesses.set(name, chase_var(TyTypeVar { param: name }, env_.vars, bindings));
    }
    let oracle = env_.implements_;
    for (let name in env_.vars) {
        let bounds = env_.bounds.get(name);
        if (!bounds) {
            continue;
        }
        // Non-principal (union-cover) binding: the witness is arbitrary.
        if (var_under_union(name, pat) || var_under_union(name, member)) {
            continue;
        }
        let witness = witnesses[name];
        // Unpinned, or pinned to something still variable-bearing: assumed
        // satisfiable in an open world.
        if (contains_bound_typevar(witness, env_.vars)) {
            continue;
        }
        // Bounded params must realize to concrete types.
        if (witness is TyUnion || witness is TyInterface) {
            return true;
        }
        if (!realized(witness)) {
            continue;
        }
        // A single provably-unsatisfied bound kills the overlap; only a
        // fully-realized instantiated bound may refute.
        for (let bound in bounds) {
            let instantiated = map_tys(bound, (t) -> {
                substitute_ty(t, witnesses)
            });
            if (tys(instantiated).every(realized) && !oracle(witness, instantiated)) {
                return true;
            }
        }
    }
    false
}
