// port: baml_type/src/unify.rs @ d9be6853b
//
// Shared equality-unification core over Ty: the tri-state Overlap engine.
// Answers "is there a substitution of the given unification variables under
// which these two types are the same type?", with unions compared as ACI sets
// through a bounded covering search. Interface coherence and pattern
// reachability (pattern_overlap.baml) build on it. Also home to `nf` (the
// union canonical form the engine assumes) and the TypeBindings substitution.
//
// Restructured:
// - AliasMap (a trait whose only implementor is HashMap) is not ported:
//   AliasEquivCtx.aliases is a `map<DeclName, Ty>`.
// - EnumVariants is a function type `(DeclName) -> string[]?`.
// - Overlap is an enum; `Overlap::and` is `overlap_and`. Rust's `.and` takes
//   its argument evaluated, so both sides always run (and spend budget):
//   every call site evaluates both operands before combining.
// - A `_at` worker and its depth-0 entry are one function with a named
//   `depth = 0` default: unify_into (+ unify_into_at), unify_union_members
//   (+ unify_union_members_at), cover (+ cover_at).
// - TypeBindings is `map<ParamTy, Ty>`. Rust's derived `Clone` is
//   copy_bindings; `*bindings = trial` is assign_bindings, which overwrites
//   the caller's map in place.
// - cover_search's `budget: &mut usize` is a SearchBudget class.
// - Obligations `Vec<(Ty, Vec<Ty>)>` are `(Ty, Ty[])[]`; candidate lists are
//   shared between obligations instead of cloned (they are never mutated).
// - fold_finite_bases returns the folded list instead of editing `&mut Vec`.
// - normalize_union_members, bind_type_vars, substitute_ty and rewrite_ty are
//   generic over the head in Rust; every family member here is
//   DeclName-headed, so they take Ty.
// - The `env` parameter is `env_`: a bare `env.x` resolves to the builtin
//   environment-variable namespace, not the parameter.
// - The `i != j` guard in normalize_union's subsumption filter is dropped:
//   is_literal_subtype is irreflexive, so it never matters.
//
// Not ported: the debug_assert in unify_all.

// port: baml_type/src/unify.rs::AliasEquivCtx @ d9be6853b
// A TypeContext for structural type equivalence that expands aliases but
// leaves every nominal fact opaque: no enum-completeness collapse, no
// interface membership or `requires`, no type-variable bounds, no
// associated-type bounds and no projection reduction. Resolving any of those
// here would re-enter impl resolution with no bound, and invariant equality
// needs none of them: an unreduced projection or an unabsorbed `C | dyn I` is
// a faithful opaque leaf for equality.
class AliasEquivCtx {
    aliases: map<DeclName, Ty>,
    // Which roots hold the language packages, so the well-known `reflect`
    // heads resolve by identity.
    lang: root.base.LangRoots,

    implements TypeContext {
        function well_known(self, head: WellKnownHead) -> DeclName? {
            well_known_decl(self.lang, head)
        }

        function alias_def(self, name: DeclName) -> Ty? {
            self.aliases.get(name)
        }

        // Opaque: a `C | dyn I == dyn I` absorption is not performed.
        function implements_interface(self, concrete: Ty, interface_: InterfaceConstraint) -> bool {
            false
        }

        // Opaque: a type variable is only equal to itself here.
        function type_var_bound(self, param: ParamTy) -> InterfaceConstraint[] {
            []
        }

        // Opaque: `A | B == B` via `A requires B` is not performed.
        function interface_requires(
            self,
            sub: InterfaceConstraint,
            sup: InterfaceConstraint,
        ) -> bool {
            false
        }

        // Opaque: `E.A | E.B | .. == E` completeness collapse is not performed.
        function enum_variants(self, name: DeclName) -> string[]? {
            null
        }

        // Opaque: a still-symbolic projection carries no bound-derived
        // membership here.
        function associated_type_bound(
            self,
            interface_: InterfaceConstraint,
            assoc: string,
        ) -> InterfaceConstraint[] {
            []
        }

        // Opaque: reducing here would re-enter impl resolution unboundedly.
        function project(
            self,
            base: Ty,
            interface_: InterfaceConstraint,
            member: string,
            fuel: int,
        ) -> ProjectionStep {
            ProjectionStepOpaque {}
        }
    }
}

// port: baml_type/src/unify.rs::TypeBindings @ d9be6853b
// The unifier's substitution: unification variable to bound type.
type TypeBindings = map<ParamTy, Ty>;

// port: baml_type/src/unify.rs::TypeBindings @ d9be6853b
// Rust's derived `Clone` of the substitution map.
function copy_bindings(bindings: TypeBindings) -> TypeBindings throws never {
    let out: TypeBindings = {};
    for (let key in bindings.keys()) {
        out.set(key, bindings[key]);
    }
    out
}

// port: baml_type/src/unify.rs::cover_search @ d9be6853b
// `*bindings = trial`: the caller's map becomes a copy of `trial`, in place.
function assign_bindings(bindings: TypeBindings, trial: TypeBindings) -> void throws never {
    bindings.clear();
    for (let key in trial.keys()) {
        bindings.set(key, trial[key]);
    }
}

// port: baml_type/src/unify.rs::Overlap @ d9be6853b
// Three-valued result of an overlap decision. Overlap is undecidable in
// general (ACI-unification), so the checker can report "couldn't tell".
enum Overlap {
    // A common instance provably exists.
    Yes,
    // No common instance can exist.
    No,
    // Could not be decided within the search bounds. Callers treat it as a
    // possible overlap (the sound direction) but report it distinctly.
    Unknown,
}

// port: baml_type/src/unify.rs::Overlap::and @ d9be6853b
// Kleene conjunction: `No` dominates, then `Unknown`, then `Yes`.
function overlap_and(a: Overlap, b: Overlap) -> Overlap throws never {
    if (a == Overlap.No || b == Overlap.No) {
        return Overlap.No;
    }
    if (a == Overlap.Unknown || b == Overlap.Unknown) {
        return Overlap.Unknown;
    }
    Overlap.Yes
}

// port: baml_type/src/unify.rs::MAX_OVERLAP_SEARCH_STEPS @ d9be6853b
// Budget on the number of `cover` trials the covering search may perform
// before it gives up with Overlap.Unknown.
const MAX_OVERLAP_SEARCH_STEPS: int = 4096;

// port: baml_type/src/unify.rs::MAX_UNIFY_DEPTH @ d9be6853b
// Recursion-depth cap for unify_into and the covering search it drives. Two
// distinct recursive aliases can expand head-first forever without repeating
// a goal; past this depth unification fails closed to Overlap.Unknown.
const MAX_UNIFY_DEPTH: int = 256;

// port: baml_type/src/unify.rs::cover_search @ d9be6853b
// The `&mut usize` step budget cover_search threads through its recursion.
class SearchBudget {
    remaining: int,
}

// port: baml_type/src/unify.rs::contains_bound_typevar @ d9be6853b
// Whether `ty` contains a type variable drawn from `generic_params` anywhere
// in its structure. An AssociatedTypeProjection falls through the wildcard
// and counts as variable-free, as in Rust.
function contains_bound_typevar(ty: Ty, generic_params: ParamTy[]) -> bool throws never {
    let any = (tys: Ty[]) -> bool {
        tys.some((t) -> {
            contains_bound_typevar(t, generic_params)
        })
    };
    match (ty) {
        let v: TyTypeVar => generic_params.includes(v.param),
        let c: TyClass => any(c.args),
        let u: TyUnion => any(u.members),
        let t: TyTuple => any(t.items),
        let i: TyInterface => {
            any(i.args)
                || any(
                    i.associated_types.map((b) -> {
                        b.ty
                    }),
                )
        },
        let l: TyList => contains_bound_typevar(l.elem, generic_params),
        let m: TyMap => {
            contains_bound_typevar(m.key, generic_params)
                || contains_bound_typevar(m.value, generic_params)
        },
        let f: TyFuture => {
            contains_bound_typevar(f.value, generic_params)
                || contains_bound_typevar(f.error, generic_params)
        },
        let f: TyFunction => {
            any(
                f.params.map((p) -> {
                    p.ty
                }),
            )
                || contains_bound_typevar(f.ret, generic_params)
                || contains_bound_typevar(f.throws_, generic_params)
        },
        _ => false,
    }
}

// port: baml_type/src/unify.rs::all_typevars_within @ d9be6853b
// Every TypeVar occurring in `ty` (projection bases and interface pins
// included) is one of `vars`. A `No` from the overlap oracle is only
// trustworthy when both inputs satisfy this.
function all_typevars_within(ty: Ty, vars: ParamTy[]) -> bool throws never {
    let all = (tys: Ty[]) -> bool {
        tys.every((t) -> {
            all_typevars_within(t, vars)
        })
    };
    match (ty) {
        let v: TyTypeVar => vars.includes(v.param),
        let c: TyClass => all(c.args),
        let u: TyUnion => all(u.members),
        let t: TyTuple => all(t.items),
        let i: TyInterface => {
            all(i.args)
                && all(
                    i.associated_types.map((b) -> {
                        b.ty
                    }),
                )
        },
        let l: TyList => all_typevars_within(l.elem, vars),
        let m: TyMap => all_typevars_within(m.key, vars) && all_typevars_within(m.value, vars),
        let f: TyFuture => all_typevars_within(f.value, vars) && all_typevars_within(f.error, vars),
        let f: TyFunction => {
            all(
                f.params.map((p) -> {
                    p.ty
                }),
            )
                && all_typevars_within(f.ret, vars)
                && all_typevars_within(f.throws_, vars)
        },
        let p: TyAssociatedTypeProjection => {
            all_typevars_within(p.base, vars)
                && all(p.interface_.generics)
                && all(
                    p.interface_.associated_types.map((b) -> {
                        b.ty
                    }),
                )
        },
        _ => true,
    }
}

// port: baml_type/src/unify.rs::var_under_union @ d9be6853b
// Whether `param` occurs anywhere inside a union within `ty`. A bounded param
// that does is bound by cover_search to one of several possible witnesses, so
// its chase_var representative is non-principal.
function var_under_union(param: ParamTy, ty: Ty) -> bool throws never {
    occurs(param, ty, false)
}

// port: baml_type/src/unify.rs::var_under_union::occurs @ d9be6853b
// var_under_union's inner walk; `in_union` is whether a union encloses `ty`.
function occurs(param: ParamTy, ty: Ty, in_union: bool) -> bool throws never {
    let any = (tys: Ty[], inside: bool) -> bool {
        tys.some((t) -> {
            occurs(param, t, inside)
        })
    };
    match (ty) {
        let v: TyTypeVar => in_union && v.param == param,
        let u: TyUnion => any(u.members, true),
        let c: TyClass => any(c.args, in_union),
        let t: TyTuple => any(t.items, in_union),
        let i: TyInterface => {
            any(i.args, in_union)
                || any(
                    i.associated_types.map((b) -> {
                        b.ty
                    }),
                    in_union,
                )
        },
        let l: TyList => occurs(param, l.elem, in_union),
        let m: TyMap => occurs(param, m.key, in_union) || occurs(param, m.value, in_union),
        let f: TyFuture => occurs(param, f.value, in_union) || occurs(param, f.error, in_union),
        let p: TyAssociatedTypeProjection => {
            occurs(param, p.base, in_union) || any(tys(p.interface_), in_union)
        },
        let f: TyFunction => {
            any(
                f.params.map((p) -> {
                    p.ty
                }),
                in_union,
            )
                || occurs(param, f.ret, in_union)
                || occurs(param, f.throws_, in_union)
        },
        // Leaf types hold no nested type. Listed so a new variant must be
        // classified.
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever
            | TyError =>
        {
            false
        },
    }
}

// port: baml_type/src/unify.rs::EnumVariants @ d9be6853b
// Looks up an enum's full set of variant names (null if it can't be resolved).
type EnumVariants = (DeclName) -> string[]? throws never;

// port: baml_type/src/unify.rs::nf @ d9be6853b
// Normalize a type toward the union canonical form the covering solver
// assumes, recursing into every argument. For unions this flattens, drops
// `never`, absorbs `unknown`, deduplicates, drops members subsumed by a
// co-member (`1 | int -> int`), and folds a complete finite base back to its
// base (`true | false -> bool`, all of an enum's variants -> the enum).
function nf(ty: Ty, enum_variants: EnumVariants) -> Ty throws never {
    let go = (t: Ty) -> Ty {
        nf(t, enum_variants)
    };
    match (ty) {
        let u: TyUnion => normalize_union(u.members.map(go), enum_variants),
        let l: TyList => TyList { elem: go(l.elem) },
        let t: TyTuple => TyTuple { items: t.items.map(go) },
        let m: TyMap => TyMap { key: go(m.key), value: go(m.value) },
        let f: TyFuture => TyFuture { value: go(f.value), error: go(f.error) },
        let c: TyClass => TyClass { name: c.name, args: c.args.map(go) },
        let i: TyInterface => {
            TyInterface {
                name: i.name,
                args: i.args.map(go),
                associated_types: i.associated_types.map((b) -> {
                    AssociatedType { name: b.name, ty: go(b.ty) }
                }),
            }
        },
        let p: TyAssociatedTypeProjection => {
            TyAssociatedTypeProjection {
                base: go(p.base),
                interface_: map_tys(p.interface_, go),
                member: p.member,
            }
        },
        let f: TyFunction => {
            TyFunction {
                params: f.params.map((p) -> {
                    FunctionParamTy { name: p.name, ty: go(p.ty), mode: p.mode }
                }),
                ret: go(f.ret),
                throws_: go(f.throws_),
            }
        },
        _ => ty,
    }
}

// port: baml_type/src/unify.rs::normalize_union @ d9be6853b
// The union laws of nf. `members` are already individually normalized.
function normalize_union(members: Ty[], enum_variants: EnumVariants) -> Ty throws never {
    // Flatten, drop `never`, absorb `unknown`, deduplicate.
    let flat: Ty[] = [];
    for (let member in members) {
        let inner: Ty[] = match (member) {
            let u: TyUnion => u.members,
            _ => [member],
        };
        for (let m in inner) {
            match (m) {
                TyNever => {},
                TyUnknown => {
                    return TyUnknown {};
                },
                _ => {
                    if (!flat.includes(m)) {
                        flat.push(m);
                    }
                },
            }
        }
    }

    // Drop members subsumed by a co-member (`literal <: base`, `variant <: enum`).
    let kept = flat.filter((m) -> {
        !flat.some((other) -> {
            is_literal_subtype(m, other)
        })
    });

    // Canonical member order, so nf's output is stable.
    let folded = fold_finite_bases(kept, enum_variants).sort_by(cmp_ty);

    match (folded.length()) {
        0 => TyNever {},
        1 => folded[0],
        _ => TyUnion { members: folded },
    }
}

// port: baml_type/src/unify.rs::fold_finite_bases @ d9be6853b
// Fold complete finite bases in a flattened, deduplicated member list:
// `true | false` becomes `bool`, and an enum all of whose variants are present
// becomes the enum.
function fold_finite_bases(members: Ty[], enum_variants: EnumVariants) -> Ty[] throws never {
    let bool_literal = (m: Ty) -> bool? {
        match (m) {
            let l: TyLiteral => match (l.value) {
                let b: root.base.LiteralBool => b.value,
                _ => null,
            },
            _ => null,
        }
    };
    let flat = members;
    if (
        flat.some((m) -> {
            bool_literal(m) == true
        })
            && flat.some((m) -> {
                bool_literal(m) == false
            })
    ) {
        flat
            = flat.filter((m) -> {
                bool_literal(m) == null
            });
        flat.push(TyBool {});
    }

    // Each enum that has a variant member: fold if all its variants are present.
    let enums: DeclName[] = [];
    for (let member in flat) {
        if let v: TyEnumVariant = member {
            if (!enums.includes(v.name)) {
                enums.push(v.name);
            }
        }
    }
    for (let enum_name in enums) {
        let all_variants = enum_variants(enum_name);
        if (!all_variants) {
            continue;
        }
        let present = flat.filter_map((m) -> {
            match (m) {
                let v: TyEnumVariant if v.name == enum_name => v.variant,
                _ => null,
            }
        });
        if (
            all_variants.every((v) -> {
                present.includes(v)
            })
        ) {
            flat
                = flat.filter((m) -> {
                    match (m) {
                        let v: TyEnumVariant => v.name != enum_name,
                        _ => true,
                    }
                });
            flat.push(TyEnum { name: enum_name });
        }
    }
    flat
}

// port: baml_type/src/unify.rs::expand_alias_head @ d9be6853b
// Resolve a chain of top-level type aliases to the underlying type, bounded
// against alias cycles. Only the head is resolved.
function expand_alias_head(ty: Ty, env_: AliasEquivCtx) -> Ty throws never {
    let current = ty;
    let step = 0;
    while (step < 64) {
        let a = match (current) {
            let a: TyTypeAlias => a,
            _ => {
                break;
            },
        };
        let next = env_.aliases.get(a.name);
        if (next == null) {
            break;
        }
        current = next;
        step += 1;
    }
    current
}

// port: baml_type/src/unify.rs::unify_into @ d9be6853b
// port: baml_type/src/unify.rs::unify_into_at @ d9be6853b
// Symmetric first-order equality unification: is there a substitution of the
// unification variables `vars` that makes `x` and `y` the same type? Commits
// the bindings on `Yes`. Equality, not subtyping: `int` and `1` are distinct
// here (the `literal <: base` subtyping lives in `cover`). `depth` accumulates
// across the whole recursive cycle (structural args and the covering
// search); past MAX_UNIFY_DEPTH the answer is Unknown.
function unify_into(
    x: Ty,
    y: Ty,
    vars: ParamTy[],
    env_: AliasEquivCtx,
    bindings: TypeBindings,
    depth: int = 0,
) -> Overlap throws never {
    if (depth >= MAX_UNIFY_DEPTH) {
        return Overlap.Unknown;
    }
    // Resolve a type alias to its definition before matching, so the
    // structural arms and variable binding see through it.
    let x1 = expand_alias_head(chase_var(x, vars, bindings), env_);
    let y1 = expand_alias_head(chase_var(y, vars, bindings), env_);
    let next = depth + 1;

    // The error sentinel never unifies: it carries its own diagnostic. The
    // inhabited top type `unknown` is not bailed here: it binds an opposing
    // variable and is otherwise a distinct atomic type compared by equality.
    if (x1 is TyError || y1 is TyError) {
        return Overlap.No;
    }

    if let v: TyTypeVar = x1 {
        if (vars.includes(v.param)) {
            return bind_unify_var(v.param, y1, vars, env_, bindings, next);
        }
    }
    if let v: TyTypeVar = y1 {
        if (vars.includes(v.param)) {
            return bind_unify_var(v.param, x1, vars, env_, bindings, next);
        }
    }

    // Structurally-equal (or alias-equal) subjects unify with no new bindings.
    if (env_.equivalent(x1, y1)) {
        return Overlap.Yes;
    }

    let rec = (a: Ty, b: Ty) -> Overlap {
        unify_into(a, b, vars, env_, bindings, depth = next)
    };
    match (x1, y1) {
        (let a: TyClass, let b: TyClass)
            if a.name == b.name && a.args.length() == b.args.length() => {
            unify_all(a.args, b.args, vars, env_, bindings, next)
        },
        // Generic args and associated bindings are both part of an
        // interface-existential type's identity.
        (let a: TyInterface, let b: TyInterface)
            if a.name == b.name && a.args.length() == b.args.length() => {
            let args = unify_all(a.args, b.args, vars, env_, bindings, next);
            let assoc = unify_associated_bindings(a.associated_types, b.associated_types, vars, env_, bindings, next);
            overlap_and(args, assoc)
        },
        (let a: TyList, let b: TyList) => rec(a.elem, b.elem),
        (let a: TyTuple, let b: TyTuple) if a.items.length() == b.items.length() => {
            unify_all(a.items, b.items, vars, env_, bindings, next)
        },
        (let a: TyMap, let b: TyMap) => {
            let k = rec(a.key, b.key);
            overlap_and(k, rec(a.value, b.value))
        },
        (let a: TyFuture, let b: TyFuture) => {
            let v = rec(a.value, b.value);
            overlap_and(v, rec(a.error, b.error))
        },
        // Function values are realized (no binders of their own), so unify
        // the param/ret/throws components directly.
        (let a: TyFunction, let b: TyFunction) if same_param_modes(a.params, b.params) => {
            let result: Overlap = Overlap.Yes;
            let i = 0;
            while (i < a.params.length()) {
                result = overlap_and(result, rec(a.params[i].ty, b.params[i].ty));
                i += 1;
            }
            let r = rec(a.ret, b.ret);
            result = overlap_and(result, r);
            overlap_and(result, rec(a.throws_, b.throws_))
        },
        // Unions compare by covering on their member sets (ACI); a non-union
        // operand is the singleton union `{S}`.
        (let a: TyUnion, let b: TyUnion) => {
            unify_union_members(a.members, b.members, vars, env_, bindings, depth = next)
        },
        (let a: TyUnion, _) => {
            unify_union_members(a.members, [y1], vars, env_, bindings, depth = next)
        },
        (_, let b: TyUnion) => {
            unify_union_members([x1], b.members, vars, env_, bindings, depth = next)
        },
        // A projection could stand for any concrete type: conservatively `Yes`
        // (not Unknown, which is reserved for budget exhaustion).
        (TyAssociatedTypeProjection, _) => Overlap.Yes,
        (_, TyAssociatedTypeProjection) => Overlap.Yes,
        // Everything else is disjoint under equality.
        _ => Overlap.No,
    }
}

// port: baml_type/src/unify.rs::unify_into_at @ d9be6853b
// The Function arm's guard: equal arity and pairwise-equal parameter modes.
function same_param_modes(xp: FunctionParamTy[], yp: FunctionParamTy[]) -> bool throws never {
    xp.length() == yp.length()
        && baml.Array
            .generate(xp.length(), (i) -> {
                i
            })
            .every((i) -> {
                xp[i].mode == yp[i].mode
            })
}

// port: baml_type/src/unify.rs::unify_all @ d9be6853b
// Unify two equal-length type-argument lists position-wise: a disjoint
// position short-circuits to `No`; an undecidable one downgrades to Unknown.
function unify_all(
    xs: Ty[],
    ys: Ty[],
    vars: ParamTy[],
    env_: AliasEquivCtx,
    bindings: TypeBindings,
    depth: int,
) -> Overlap throws never {
    let result: Overlap = Overlap.Yes;
    let i = 0;
    while (i < xs.length()) {
        match (unify_into(xs[i], ys[i], vars, env_, bindings, depth = depth)) {
            Overlap.No => {
                return Overlap.No;
            },
            Overlap.Unknown => {
                result = Overlap.Unknown;
            },
            Overlap.Yes => {},
        }
        i += 1;
    }
    result
}

// port: baml_type/src/unify.rs::unify_associated_bindings @ d9be6853b
// Unify two interface-existentials' associated bindings: a conjunction over
// names common to both. A name on only one side does not constrain.
function unify_associated_bindings(
    xb: AssociatedType[],
    yb: AssociatedType[],
    vars: ParamTy[],
    env_: AliasEquivCtx,
    bindings: TypeBindings,
    depth: int,
) -> Overlap throws never {
    let result: Overlap = Overlap.Yes;
    for (let x in xb) {
        let y = yb.find((b) -> {
            b.name == x.name
        });
        if (y != null) {
            match (unify_into(x.ty, y.ty, vars, env_, bindings, depth = depth)) {
                Overlap.No => {
                    return Overlap.No;
                },
                Overlap.Unknown => {
                    result = Overlap.Unknown;
                },
                Overlap.Yes => {},
            }
        }
    }
    result
}

// port: baml_type/src/unify.rs::unify_union_members @ d9be6853b
// port: baml_type/src/unify.rs::unify_union_members_at @ d9be6853b
// Unify two unions, as sets: does some substitution make them one type?
// Members are matched by covering (many-to-one, idempotency), not a one-to-one
// pairing. Cheap special cases run first (all-ground is set equality; a bare
// variable on each side is `Yes`); otherwise the covering obligations are
// solved jointly by cover_search, within MAX_OVERLAP_SEARCH_STEPS.
function unify_union_members(
    xs: Ty[],
    ys: Ty[],
    vars: ParamTy[],
    env_: AliasEquivCtx,
    bindings: TypeBindings,
    depth: int = 0,
) -> Overlap throws never {
    let ground = try_union_set_equality(xs, ys, vars, env_);
    if (ground != null) {
        return ground;
    }
    let absorbed = try_union_mutual_absorption(xs, ys, vars);
    if (absorbed != null) {
        return absorbed;
    }

    let rigids = (members: Ty[]) -> Ty[] {
        members.filter((m) -> {
            !is_bare_var(m, vars)
        })
    };
    let xn = rigids(xs);
    let yn = rigids(ys);
    let x_has_bare = xs.some((m) -> {
        is_bare_var(m, vars)
    });
    let y_has_bare = ys.some((m) -> {
        is_bare_var(m, vars)
    });

    // A side with a bare variable absorbs the other side's leftovers, so only
    // its own rigids must be covered. With no bare variable anywhere,
    // equality requires mutual covering, solved jointly.
    let covering = (members: Ty[], candidates: Ty[]) -> (Ty, Ty[])[] {
        members.map((m) -> {
            (m, candidates)
        })
    };
    let obligations = if (x_has_bare) {
        covering(xn, yn)
    } else if (y_has_bare) {
        covering(yn, xn)
    } else {
        covering(xn, yn).concat(covering(yn, xn))
    };

    let budget = SearchBudget { remaining: MAX_OVERLAP_SEARCH_STEPS };
    cover_search(obligations, vars, env_, bindings, budget, depth)
}

// port: baml_type/src/unify.rs::normalize_union_members @ d9be6853b
// Flatten nested unions, drop `never`, deduplicate; collapse a single
// survivor to a bare type and an empty result to `never`.
function normalize_union_members(members: Ty[]) -> Ty throws never {
    let normalized: Ty[] = [];
    for (let member in members) {
        let inner: Ty[] = match (member) {
            let u: TyUnion => u.members,
            _ => [member],
        };
        for (let m in inner) {
            if (!(m is TyNever) && !normalized.includes(m)) {
                normalized.push(m);
            }
        }
    }
    match (normalized.length()) {
        0 => TyNever {},
        1 => normalized[0],
        _ => TyUnion { members: normalized },
    }
}

// port: baml_type/src/unify.rs::bind_type_vars @ d9be6853b
// Bind generic params to concrete type arguments, position-wise. Extra
// entries on either side are ignored.
function bind_type_vars(
    generic_params: ParamTy[],
    concrete_args: Ty[],
) -> TypeBindings throws never {
    let bindings: TypeBindings = {};
    let i = 0;
    while (i < generic_params.length() && i < concrete_args.length()) {
        bindings.set(generic_params[i], concrete_args[i]);
        i += 1;
    }
    bindings
}

// port: baml_type/src/unify.rs::substitute_ty @ d9be6853b
// Replace every type variable present in `bindings`, preserving the full
// shape (unions renormalized through normalize_union_members).
function substitute_ty(ty: Ty, bindings: TypeBindings) -> Ty throws never {
    if (bindings.length() == 0) {
        return ty;
    }
    rewrite_ty(ty, (node) -> {
        match (node) {
            let v: TyTypeVar => bindings.get(v.param),
            _ => null,
        }
    })
}

// port: baml_type/src/unify.rs::rewrite_ty @ d9be6853b
// Pre-order rewrite: `rewrite` is consulted at every node; a non-null answer
// replaces the node wholesale (its children are not visited), null recurses
// into the children and rebuilds.
function rewrite_ty(ty: Ty, rewrite: (Ty) -> Ty?) -> Ty {
    let replacement = rewrite(ty);
    if (replacement != null) {
        return replacement;
    }
    let go = (t: Ty) -> Ty {
        rewrite_ty(t, rewrite)
    };
    match (ty) {
        let l: TyList => TyList { elem: go(l.elem) },
        let m: TyMap => TyMap { key: go(m.key), value: go(m.value) },
        let f: TyFuture => TyFuture { value: go(f.value), error: go(f.error) },
        let p: TyAssociatedTypeProjection => {
            TyAssociatedTypeProjection {
                base: go(p.base),
                interface_: map_tys(p.interface_, go),
                member: p.member,
            }
        },
        let u: TyUnion => normalize_union_members(u.members.map(go)),
        let t: TyTuple => TyTuple { items: t.items.map(go) },
        // Function values are realized: nothing to shadow.
        let f: TyFunction => {
            TyFunction {
                params: f.params.map((p) -> {
                    FunctionParamTy { name: p.name, ty: go(p.ty), mode: p.mode }
                }),
                ret: go(f.ret),
                throws_: go(f.throws_),
            }
        },
        let c: TyClass => TyClass { name: c.name, args: c.args.map(go) },
        let i: TyInterface => {
            TyInterface {
                name: i.name,
                args: i.args.map(go),
                associated_types: i.associated_types.map((b) -> {
                    AssociatedType { name: b.name, ty: go(b.ty) }
                }),
            }
        },
        // Leaves pass through.
        _ => ty,
    }
}

// port: baml_type/src/unify.rs::try_union_set_equality @ d9be6853b
// With no variable on either side, overlap is exact set equality. Null if a
// variable is present.
function try_union_set_equality(
    xs: Ty[],
    ys: Ty[],
    vars: ParamTy[],
    env_: AliasEquivCtx,
) -> Overlap? throws never {
    let has_var = (members: Ty[]) -> bool {
        members.some((m) -> {
            contains_bound_typevar(m, vars)
        })
    };
    if (has_var(xs) || has_var(ys)) {
        return null;
    }
    if (unions_set_equal(xs, ys, env_)) {
        Overlap.Yes
    } else {
        Overlap.No
    }
}

// port: baml_type/src/unify.rs::try_union_mutual_absorption @ d9be6853b
// A bare variable can be instantiated to a union, so it absorbs any set of
// the other side's members; with one on each side a common instance always
// exists. Null if either side lacks a bare variable.
function try_union_mutual_absorption(xs: Ty[], ys: Ty[], vars: ParamTy[]) -> Overlap? throws never {
    let has_bare = (members: Ty[]) -> bool {
        members.some((m) -> {
            is_bare_var(m, vars)
        })
    };
    if (has_bare(xs) && has_bare(ys)) {
        Overlap.Yes
    } else {
        null
    }
}

// port: baml_type/src/unify.rs::is_bare_var @ d9be6853b
// Whether `m` is a top-level type variable in `vars`.
function is_bare_var(m: Ty, vars: ParamTy[]) -> bool throws never {
    match (m) {
        let v: TyTypeVar => vars.includes(v.param),
        _ => false,
    }
}

// port: baml_type/src/unify.rs::unions_set_equal @ d9be6853b
// Whether two ground unions denote the same set of types (order-insensitive).
// Members are de-duplicated, so equal cardinality plus "every member of `xs`
// has an equal member in `ys`" implies a bijection.
function unions_set_equal(xs: Ty[], ys: Ty[], env_: AliasEquivCtx) -> bool throws never {
    xs.length() == ys.length()
        && xs.every((x) -> {
            ys.some((y) -> {
                env_.equivalent(x, y)
            })
        })
}

// port: baml_type/src/unify.rs::cover @ d9be6853b
// port: baml_type/src/unify.rs::cover_at @ d9be6853b
// Whether `member` can be a subtype of `candidate` under some substitution
// (committing the bindings on success). unify_into supplies the bulk; on top
// sit `literal <: base` / `variant <: enum`, and the pairs that need the impl
// registry (concrete vs interface, two different interfaces, `$rust_type`),
// which are conservatively `Yes`. Those arms only fire after unify_into
// returned `No` without binding anything.
function cover(
    member: Ty,
    candidate: Ty,
    vars: ParamTy[],
    env_: AliasEquivCtx,
    bindings: TypeBindings,
    depth: int = 0,
) -> Overlap throws never {
    let decided = unify_into(member, candidate, vars, env_, bindings, depth = depth);
    if (
        decided == Overlap.No
            && (
                is_literal_subtype(member, candidate)
                    || needs_conservative_membership(member, candidate)
            )
    ) {
        return Overlap.Yes;
    }
    decided
}

// port: baml_type/src/unify.rs::is_literal_subtype @ d9be6853b
// Whether `member` is a top-level subtype of `candidate` by the only
// subtypings invariance leaves above the constructor level: a literal of its
// base primitive (`1 <: int`) and an enum variant of its enum. Directional.
function is_literal_subtype(member: Ty, candidate: Ty) -> bool throws never {
    match (member, candidate) {
        (let l: TyLiteral, _) => match (l.value) {
            root.base.LiteralInt => candidate is TyInt,
            root.base.LiteralBigint => candidate is TyBigint,
            root.base.LiteralFloat => candidate is TyFloat,
            root.base.LiteralString => candidate is TyString,
            root.base.LiteralBool => candidate is TyBool,
        },
        (let v: TyEnumVariant, let e: TyEnum) => v.name == e.name,
        _ => false,
    }
}

// port: baml_type/src/unify.rs::needs_conservative_membership @ d9be6853b
// Whether this pair's subtyping cannot be decided without the impl registry:
// a concrete type vs an interface, two different interfaces, or an opaque
// `$rust_type`. Same-name interfaces are decided precisely by unify_into.
function needs_conservative_membership(a: Ty, b: Ty) -> bool throws never {
    if (a is TyRustType || b is TyRustType) {
        return true;
    }
    match (a, b) {
        (let x: TyInterface, let y: TyInterface) => x.name != y.name,
        (TyInterface, _) => true,
        (_, TyInterface) => true,
        _ => false,
    }
}

// port: baml_type/src/unify.rs::cover_search @ d9be6853b
// Solve the covering obligations jointly: one substitution under which every
// `(member, candidates)` obligation has `member` a subtype of some candidate.
// Picks the most-constrained obligation first (a single viable candidate is
// forced, none fails fast with `No`), otherwise backtracks over the
// candidates. `budget` caps the number of `cover` trials; exhausting it
// yields Unknown.
function cover_search(
    obligations: (Ty, Ty[])[],
    vars: ParamTy[],
    env_: AliasEquivCtx,
    bindings: TypeBindings,
    budget: SearchBudget,
    depth: int,
) -> Overlap throws never {
    if (obligations.length() == 0) {
        return Overlap.Yes;
    }

    // Choose the obligation with the fewest viable candidates; fail fast on a
    // member that nothing can cover.
    let chosen: int? = null;
    let chosen_viable: int[] = [];
    let oi = 0;
    for (let obligation in obligations) {
        let viable: int[] = [];
        let ci = 0;
        for (let candidate in obligation.1) {
            if (budget.remaining == 0) {
                return Overlap.Unknown;
            }
            budget.remaining -= 1;
            let trial = copy_bindings(bindings);
            if (cover(obligation.0, candidate, vars, env_, trial, depth = depth) != Overlap.No) {
                viable.push(ci);
            }
            ci += 1;
        }
        if (viable.length() == 0) {
            return Overlap.No;
        }
        if (chosen == null || viable.length() < chosen_viable.length()) {
            chosen = oi;
            chosen_viable = viable;
            // Can't be more constrained than a single candidate.
            if (viable.length() == 1) {
                break;
            }
        }
        oi += 1;
    }

    let pick = chosen ?? baml.sys.panic("non-empty obligations always yield a choice");
    let member = obligations[pick].0;
    let candidates = obligations[pick].1;
    let rest = baml.Array
        .generate(obligations.length(), (i) -> {
            i
        })
        .filter((i) -> {
            i != pick
        })
        .map((i) -> {
            obligations[i]
        });

    let result: Overlap = Overlap.No;
    for (let ci in chosen_viable) {
        let trial = copy_bindings(bindings);
        // `ci` was viable, so this is Yes or Unknown, never No.
        let here = cover(member, candidates[ci], vars, env_, trial, depth = depth);
        let tail = cover_search(rest, vars, env_, trial, budget, depth);
        match (overlap_and(here, tail)) {
            Overlap.Yes => {
                assign_bindings(bindings, trial);
                return Overlap.Yes;
            },
            Overlap.Unknown => {
                result = Overlap.Unknown;
            },
            Overlap.No => {},
        }
    }
    result
}

// port: baml_type/src/unify.rs::chase_var @ d9be6853b
// Resolve a type through the current bindings: while it is a bound
// unification variable, replace it with its binding.
function chase_var(ty: Ty, vars: ParamTy[], bindings: TypeBindings) -> Ty throws never {
    let current = ty;
    while let v: TyTypeVar = current {
        if (!vars.includes(v.param)) {
            break;
        }
        let bound = bindings.get(v.param);
        if (bound == null) {
            break;
        }
        current = bound;
    }
    current
}

// port: baml_type/src/unify.rs::bind_unify_var @ d9be6853b
// Bind unification variable `n` to (already-chased) `t`, unifying with any
// existing binding and rejecting cyclic bindings (the occurs check).
function bind_unify_var(
    n: ParamTy,
    t: Ty,
    vars: ParamTy[],
    env_: AliasEquivCtx,
    bindings: TypeBindings,
    depth: int,
) -> Overlap throws never {
    if let tv: TyTypeVar = t {
        if (tv.param == n) {
            return Overlap.Yes;
        }
    }
    let existing = bindings.get(n);
    if (existing != null) {
        return unify_into(existing, t, vars, env_, bindings, depth = depth);
    }
    if (occurs_in(n, t, vars, bindings)) {
        return Overlap.No;
    }
    bindings.set(n, t);
    Overlap.Yes
}

// port: baml_type/src/unify.rs::occurs_in @ d9be6853b
// Occurs check: does unification variable `n` appear anywhere in `t`
// (chasing bound vars)? Binding `n := t` would then build an infinite type.
function occurs_in(
    n: ParamTy,
    t: Ty,
    vars: ParamTy[],
    bindings: TypeBindings,
) -> bool throws never {
    let any = (tys: Ty[]) -> bool {
        tys.some((a) -> {
            occurs_in(n, a, vars, bindings)
        })
    };
    match (chase_var(t, vars, bindings)) {
        let v: TyTypeVar => v.param == n,
        let c: TyClass => any(c.args),
        let u: TyUnion => any(u.members),
        let tu: TyTuple => any(tu.items),
        let i: TyInterface => {
            any(i.args)
                || any(
                    i.associated_types.map((b) -> {
                        b.ty
                    }),
                )
        },
        let l: TyList => occurs_in(n, l.elem, vars, bindings),
        let m: TyMap => occurs_in(n, m.key, vars, bindings) || occurs_in(n, m.value, vars, bindings),
        let f: TyFuture => {
            occurs_in(n, f.value, vars, bindings) || occurs_in(n, f.error, vars, bindings)
        },
        let p: TyAssociatedTypeProjection => {
            occurs_in(n, p.base, vars, bindings) || any(tys(p.interface_))
        },
        let f: TyFunction => {
            any(
                f.params.map((p) -> {
                    p.ty
                }),
            )
                || occurs_in(n, f.ret, vars, bindings)
                || occurs_in(n, f.throws_, vars, bindings)
        },
        // Leaf types hold no nested type. Listed so a new variant must be
        // classified.
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyLiteral
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeAlias
            | TyUnknown
            | TyNever
            | TyError =>
        {
            false
        },
    }
}
