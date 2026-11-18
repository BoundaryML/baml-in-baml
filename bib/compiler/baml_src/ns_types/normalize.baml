// port: baml_type/src/normalize.rs @ d9be6853b
//
// Canonical type normalization, equivalence, and subtyping for Ty: the
// current-context type algebra. Type variables and interface existentials
// compare by identity; every nominal fact comes from a TypeContext and every
// lookup fails safe (a missing fact can only yield "not necessarily
// equivalent / subtype").
//
// Restructured:
// - NormalTy is a union of `NormalTy<Variant>` classes. Rust's phase
//   parameter (`MuPhase`: `Named` / `Canonical`) has no BAML counterpart, so
//   there is one NormalTy whose recursion payloads hold either phase:
//   `NormalTyMu.binder: DeclName | MuDisplay` and
//   `NormalTyRecVar.var: DeclName | int`. The named phase (from_ty,
//   mentions_rec_var, legacy_render, resolve_binders) carries DeclNames, the
//   canonical phase MuDisplay and de Bruijn ints. A cross-phase term, which
//   Rust's types rule out, panics where it is read.
// - MuDisplay implements Equals (always equal) and Hash (feeds nothing), so
//   `==` on NormalTy is Rust's derived equality, display-transparent. Rust's
//   derived Ord is cmp_normal_ty.
// - `impl NormalTy` items are free functions under their Rust names
//   (`canonicalize(t, ..)`); `impl NormalParam` and `impl Category` items take
//   the `normal_param_` / `category_` prefix. The receiver is the first
//   parameter (`t`, or `sub` for the subtype relation).
// - The co-inductive assumption set `HashSet<(NormalTy, NormalTy)>` is a
//   stack `(NormalTy, NormalTy)[]`. Rust only ever probes it by linear scan,
//   and every insert is undone by the matching remove on the way back out,
//   so the set is always exactly the pairs on the current path: push before
//   recursing, pop after. Nothing is hashed, so no key is needed.
// - `saw_mu: &mut bool` is the SawMu class; the `&mut Vec` the
//   collapse_complete_* functions edit is returned instead.
// - TypeContext's `where Self: Sized` defaulted methods are interface
//   default methods.
// - The interned entry takes the InferPool explicitly (Rust's pool is
//   global); InternedCanonicalCache is keyed by handle.
// - `Interface::to_ty` (family.rs, not generated here) is inlined as a
//   TyInterface literal; `Interface::new` as the binding sort.
// - Recursion is plain (from_ty, canonicalize, is_subtype_of): the VM's stack
//   takes tens of thousands of frames, and the deep-nesting test runs 500
//   levels through every walk.
//
// Not ported:
// - SpelledHead and NoFacts: they need a head that spells a well-known
//   declaration (TypeName); every family member here is DeclName-headed.
// - WellKnownHead::item: LangItem is not in ns_base. well_known_head_name
//   and well_known_decl spell the `reflect` root item directly.
// - The free-function forms `normalize`, `equivalent`, `is_subtype`,
//   `definitely_disjoint`, `definitely_equal`: one-line forwarders to the
//   TypeContext methods.
// - One-liners: NormalTy::is_closed (feeds a debug assert only),
//   NormalTy::is_sentinel (`t is NormalTyError`), NormalParam::is_required
//   (`p.mode == FunctionParamMode.Required`), and the list maps into_tys,
//   from_tys, from_interned_all, into_interned_all.
// - The debug_assert!s.

// port: baml_type/src/normalize.rs::WellKnownHead @ d9be6853b
// The declarations the algebra special-cases by identity: items at the root
// namespace of the `reflect` package, resolved through
// TypeContext.well_known so the algebra never spells one.
enum WellKnownHead {
    // `reflect.AnyFunction`, whose associated-type pins are covariant.
    AnyFunction,
    // `reflect.AnyClass`, the compiler-derived interface of class values.
    AnyClass,
}

// port: baml_type/src/normalize.rs::WellKnownHead::ALL @ d9be6853b
const WELL_KNOWN_HEADS: WellKnownHead[] = [WellKnownHead.AnyFunction, WellKnownHead.AnyClass];

// port: baml_type/src/normalize.rs::WellKnownHead::name @ d9be6853b
// The declaration's short name at the root namespace of `reflect`.
function well_known_head_name(head: WellKnownHead) -> string throws never {
    match (head) {
        WellKnownHead.AnyFunction => "AnyFunction",
        WellKnownHead.AnyClass => "AnyClass",
    }
}

// port: baml_type/src/normalize.rs::LangFacts @ d9be6853b
// Every nominal fact opaque, except which heads are the well-known `reflect`
// declarations (a language fact the root table holds). Deprecated in Rust:
// each use marks a boundary awaiting a real fact context.
class LangFacts {
    lang: root.base.LangRoots,

    implements TypeContext {
        function well_known(self, head: WellKnownHead) -> DeclName? {
            well_known_decl(self.lang, head)
        }

        function alias_def(self, name: DeclName) -> Ty? {
            null
        }

        function implements_interface(self, concrete: Ty, interface_: InterfaceConstraint) -> bool {
            false
        }

        function type_var_bound(self, param: ParamTy) -> InterfaceConstraint[] {
            []
        }

        function interface_requires(
            self,
            sub: InterfaceConstraint,
            sup: InterfaceConstraint,
        ) -> bool {
            false
        }

        function enum_variants(self, name: DeclName) -> string[]? {
            null
        }

        function associated_type_bound(
            self,
            interface_: InterfaceConstraint,
            assoc: string,
        ) -> InterfaceConstraint[] {
            []
        }

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

// port: baml_type/src/normalize.rs::well_known_decl @ d9be6853b
// The compiler's head for a well-known declaration: the item at the root
// namespace of the installed `reflect` package, or null when it is not
// installed. Rust goes through `DeclName::of_lang_item(lang, head.item())`.
function well_known_decl(lang: root.base.LangRoots, head: WellKnownHead) -> DeclName? throws never {
    let reflect = lang.get(root.base.LangPackage.Reflect)
        ?? return null;
    DeclName { pkg: reflect, namespace: [], name: well_known_head_name(head) }
}

// port: baml_type/src/normalize.rs::is_any_function @ d9be6853b
// Whether `head` is `reflect.AnyFunction`, by identity against the head the
// context uses for it. An unresolved declaration is not AnyFunction here.
function is_any_function(head: DeclName, ctx: TypeContext) -> bool throws never {
    let any_function = ctx.well_known(WellKnownHead.AnyFunction);
    any_function != null && head == any_function
}

// port: baml_type/src/normalize.rs::is_any_class @ d9be6853b
// is_any_function for `reflect.AnyClass`.
function is_any_class(head: DeclName, ctx: TypeContext) -> bool throws never {
    let any_class = ctx.well_known(WellKnownHead.AnyClass);
    any_class != null && head == any_class
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize.rs::PROJECTION_REDUCTION_FUEL @ d9be6853b
// Starting fuel for projection reduction: the longest reduction chain before
// a projection is left opaque. Bounds a cyclic `type A = (C as I).B` /
// `type B = (C as J).A`.
const PROJECTION_REDUCTION_FUEL: int = 256;

// port: baml_type/src/normalize.rs::ProjectionStep::Reduced @ d9be6853b
// The projection is this type: the impl's binding or the qualifier's pin.
class ProjectionStepReduced {
    ty: Ty,
}

// port: baml_type/src/normalize.rs::ProjectionStep::Opaque @ d9be6853b
// The projection cannot be reduced here; it stays an opaque leaf.
class ProjectionStepOpaque {
}

// port: baml_type/src/normalize.rs::ProjectionStep @ d9be6853b
// The result of reducing `(base as I).member` through TypeContext.project.
type ProjectionStep = ProjectionStepReduced | ProjectionStepOpaque;

// port: baml_type/src/normalize.rs::TypeContext @ d9be6853b
// The semantic lookups the algebra needs, supplied by the caller over its own
// registries. Every lookup fails safe: null / false / empty makes the algebra
// conservative. The defaulted methods are the algebra itself; a context
// supplies only the facts.
interface TypeContext {
    // The head this context represents the well-known declaration with; null
    // when it cannot be resolved at all (the special case then does not fire).
    function well_known(self, head: WellKnownHead) -> DeclName? throws never;

    // The type an alias expands to (the direct right-hand side), or null if
    // the alias is unknown (it then stays an opaque leaf).
    function alias_def(self, name: DeclName) -> Ty? throws never;

    // Whether the non-interface, non-type-variable `concrete` implements
    // `interface_`, generic arguments and associated-type bindings included.
    function implements_interface(
        self,
        concrete: Ty,
        interface_: InterfaceConstraint,
    ) -> bool throws never;

    // The declared bound of a type variable (a conjunction of interfaces);
    // empty if unbounded or unknown.
    function type_var_bound(self, param: ParamTy) -> InterfaceConstraint[] throws never;

    // Whether `sub` properly (transitively, not reflexively) requires `sup`.
    function interface_requires(
        self,
        sub: InterfaceConstraint,
        sup: InterfaceConstraint,
    ) -> bool throws never;

    // An enum's complete variant names, or null if the enum is unknown.
    function enum_variants(self, name: DeclName) -> string[]? throws never;

    // The declared interface bounds of associated type `assoc` on
    // `interface_` (a conjunction); empty if unbounded or unknown.
    function associated_type_bound(
        self,
        interface_: InterfaceConstraint,
        assoc: string,
    ) -> InterfaceConstraint[] throws never;

    // Reduce `(base as interface_).member` to the type it denotes when
    // determinable; ProjectionStepOpaque otherwise. `fuel` is the remaining
    // reduction budget, for contexts that drive the recursion themselves.
    function project(
        self,
        base: Ty,
        interface_: InterfaceConstraint,
        member: string,
        fuel: int,
    ) -> ProjectionStep throws never;

    // port: baml_type/src/normalize.rs::TypeContext::normalize @ d9be6853b
    // `ty` in canonical form, rendered back as a Ty. A recursive alias at the
    // root is unfolded once; nested recursion stays folded as alias names.
    // Idempotent and equivalent to the input, canonical up to the naming of
    // recursion back-references.
    function normalize(self, ty: Ty) -> Ty throws never {
        canonical_render(ty, self)
    }

    // port: baml_type/src/normalize.rs::TypeContext::equivalent @ d9be6853b
    // Whether `a` and `b` denote the same type: structural equality of
    // canonical forms (equirecursive across alias renaming, unfolding depth
    // and mutual recursion).
    function equivalent(self, a: Ty, b: Ty) -> bool throws never {
        // Reflexivity fast path.
        if (a == b) {
            return true;
        }
        // Cheap definite-mismatch filter: two nominal heads with different
        // names, decided from the outermost constructor alone.
        if (heads_definitely_differ(a, b)) {
            return false;
        }
        canonical(a, self) == canonical(b, self)
    }

    // port: baml_type/src/normalize.rs::TypeContext::is_subtype @ d9be6853b
    // Whether every value of `sub` is also a value of `sup`.
    function is_subtype(self, sub: Ty, sup: Ty) -> bool throws never {
        if (sub == sup) {
            return true;
        }
        // Definite-mismatch filter. Of the same-variant nominal pairs
        // heads_definitely_differ claims, only interface-to-interface can still
        // be a subtype under different names (through `requires`).
        if (!(sub is TyInterface && sup is TyInterface) && heads_definitely_differ(sub, sup)) {
            return false;
        }
        let sub_n = canonical(sub, self);
        let sup_n = canonical(sup, self);
        is_subtype_of(sub_n, sup_n, self, [])
    }

    // port: baml_type/src/normalize.rs::TypeContext::definitely_disjoint @ d9be6853b
    // Whether no value of `a` can ever be `==`-equal to a value of `b`. Sound
    // and conservative: different concrete categories, distinct
    // instantiations of an invariant generic, distinct non-float literals.
    function definitely_disjoint(self, a: Ty, b: Ty) -> bool throws never {
        is_disjoint_from(canonical(a, self), canonical(b, self))
    }

    // port: baml_type/src/normalize.rs::TypeContext::definitely_equal @ d9be6853b
    // Whether a broad `==` between `a` and `b` is always true: both pinned to
    // the same non-float primitive literal, or null.
    function definitely_equal(self, a: Ty, b: Ty) -> bool throws never {
        let a_n = canonical(a, self);
        is_unoverridable_singleton(a_n) && a_n == canonical(b, self)
    }

    // port: baml_type/src/normalize.rs::TypeContext::constant_equality @ d9be6853b
    // The statically known result of `==` between `a` and `b`, or null:
    // definitely_disjoint and definitely_equal in one pass.
    function constant_equality(self, a: Ty, b: Ty) -> bool? throws never {
        let a_n = canonical(a, self);
        let b_n = canonical(b, self);
        if (is_disjoint_from(a_n, b_n)) {
            false
        } else if (is_unoverridable_singleton(a_n) && a_n == b_n) {
            true
        } else {
            null
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC API
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize.rs::is_string_key @ d9be6853b
// Whether a map's declared key type can cross a string-keyed boundary.
function is_string_key(key: Ty, ctx: TypeContext) -> bool throws never {
    ctx.is_subtype(key, TyString {})
}

// port: baml_type/src/normalize.rs::heads_definitely_differ @ d9be6853b
// True only when `a` and `b` provably canonicalize to different forms, judged
// from their outermost constructor alone. Sound because canonicalization
// keeps Class/Interface/Enum/EnumVariant heads verbatim and keeps every head
// that has a Category.
function heads_definitely_differ(a: Ty, b: Ty) -> bool throws never {
    match (a, b) {
        (let x: TyClass, let y: TyClass) => x.name != y.name,
        (let x: TyInterface, let y: TyInterface) => x.name != y.name,
        (let x: TyEnum, let y: TyEnum) => x.name != y.name,
        (let x: TyEnumVariant, let y: TyEnumVariant) => x.name != y.name || x.variant != y.variant,
        _ => categories_differ(category_of_head(a), category_of_head(b)),
    }
}

// port: baml_type/src/normalize.rs::categories_differ @ d9be6853b
// Whether two heads are of different, known categories.
function categories_differ(a: Category?, b: Category?) -> bool throws never {
    a != null && b != null && a != b
}

// port: baml_type/src/normalize.rs::NormalTy::canonical @ d9be6853b
// Normalize and canonicalize a Ty in one step: the named intermediate, strict
// binder resolution, the bottom-up algebra, and (only when recursion is
// present) the μ-canonicalization automaton.
function canonical(ty: Ty, ctx: TypeContext) -> NormalTy throws never {
    canonical_with(ty, ctx, [])
}

// port: baml_type/src/normalize.rs::NormalTy::canonical_with @ d9be6853b
// canonical with the caller's co-inductive assumptions threaded through the
// union algebra. The expanding arms of is_subtype_of must use this: a bound
// canonicalized under a fresh set re-enters the subtype question that
// triggered it, and a self-referential bound (`T extends Foo<T | int>`) then
// recurses without end.
function canonical_with(
    ty: Ty,
    ctx: TypeContext,
    assumptions: (NormalTy, NormalTy)[],
) -> NormalTy throws never {
    let (let t, let saw_mu) = canonical_bottom_up(ty, ctx, assumptions);
    if (saw_mu && contains_mu(t)) {
        root.types.normalize.canonicalize_mu(t, ctx)
    } else {
        t
    }
}

// port: baml_type/src/normalize.rs::NormalTy::canonical_render @ d9be6853b
// canonical rendered back as a Ty: the body of TypeContext.normalize. On the
// μ path the automaton renders the root directly (root-unfold-once).
function canonical_render(ty: Ty, ctx: TypeContext) -> Ty throws never {
    let (let t, let saw_mu) = canonical_bottom_up(ty, ctx, []);
    if (saw_mu && contains_mu(t)) {
        root.types.normalize.canonicalize_mu_with_render(t, ctx).1
    } else {
        into_ty(t)
    }
}

// port: baml_type/src/normalize.rs::NormalTy::canonical_bottom_up @ d9be6853b
// The shared pre-automaton pipeline: named intermediate, strict binder
// resolution, bottom-up algebra. Also returns whether a binder was seen.
function canonical_bottom_up(
    ty: Ty,
    ctx: TypeContext,
    assumptions: (NormalTy, NormalTy)[],
) -> (NormalTy, bool) throws never {
    let named = from_ty(ty, ctx, {}, PROJECTION_REDUCTION_FUEL);
    let saw_mu = SawMu { value: false };
    let resolved = resolve_binders(named, [], saw_mu);
    (canonicalize(resolved, ctx, saw_mu.value, assumptions), saw_mu.value)
}

// port: baml_type/src/normalize.rs::NormalTy::contains_mu @ d9be6853b
// Whether a μ-binder survives in this term: the automaton trigger.
function contains_mu(t: NormalTy) -> bool throws never {
    match (t) {
        NormalTyMu => true,
        // A free RecVar cannot occur without its binder in a closed term.
        NormalTyRecVar => false,
        let x: NormalTyList => contains_mu(x.elem),
        let x: NormalTyMap => contains_mu(x.key) || contains_mu(x.value),
        let x: NormalTyFuture => contains_mu(x.value) || contains_mu(x.error),
        let x: NormalTyUnion => x.members.some(contains_mu),
        let x: NormalTyTuple => x.items.some(contains_mu),
        let x: NormalTyClass => x.args.some(contains_mu),
        let x: NormalTyInterface => {
            x.args.some(contains_mu)
                || x.bindings.some((b) -> {
                    contains_mu(b.ty)
                })
        },
        let x: NormalTyFunction => {
            x.params.some((p) -> {
                contains_mu(p.ty)
            })
                || contains_mu(x.ret)
                || contains_mu(x.throws_)
        },
        let x: NormalTyAssociatedTypeProjection => contains_mu(x.base) || contains_mu(x.interface_),
        NormalTyLeaf => false,
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CONCRETE-TYPE DISJOINTNESS
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize.rs::Category @ d9be6853b
// Top-level concrete category of a ground-headed type: a value of one
// category is never a value of another. A union of classes (Rust's
// `Media(MediaKind)` carries data).
class CategoryInt {
}

class CategoryBigint {
}

class CategoryFloat {
}

class CategoryString {
}

class CategoryBool {
}

class CategoryNull {
}

class CategoryUint8Array {
}

class CategoryMedia {
    kind: root.base.MediaKind,
}

class CategoryRustType {
}

class CategoryType {
}

class CategoryResource {
}

class CategoryPromptAst {
}

class CategoryClass {
}

class CategoryList {
}

class CategoryMap {
}

class CategoryTuple {
}

class CategoryEnum {
}

class CategoryFunction {
}

class CategoryFuture {
}

type Category = CategoryInt
    | CategoryBigint
    | CategoryFloat
    | CategoryString
    | CategoryBool
    | CategoryNull
    | CategoryUint8Array
    | CategoryMedia
    | CategoryRustType
    | CategoryType
    | CategoryResource
    | CategoryPromptAst
    | CategoryClass
    | CategoryList
    | CategoryMap
    | CategoryTuple
    | CategoryEnum
    | CategoryFunction
    | CategoryFuture;

// port: baml_type/src/normalize.rs::NormalTy::head_category @ d9be6853b
// Top-level concrete category, or null for a non-ground head (union,
// interface, type variable, ...) for which no disjointness is provable.
function head_category(t: NormalTy) -> Category? throws never {
    match (t) {
        NormalTyInt => CategoryInt {},
        NormalTyBigint => CategoryBigint {},
        NormalTyFloat => CategoryFloat {},
        NormalTyString => CategoryString {},
        NormalTyBool => CategoryBool {},
        let l: NormalTyLiteral => category_of_literal(l.value),
        NormalTyNull => CategoryNull {},
        NormalTyUint8Array => CategoryUint8Array {},
        let m: NormalTyMedia => CategoryMedia { kind: m.kind },
        NormalTyRustType => CategoryRustType {},
        NormalTyType => CategoryType {},
        NormalTyResource => CategoryResource {},
        NormalTyPromptAst => CategoryPromptAst {},
        NormalTyClass => CategoryClass {},
        NormalTyList => CategoryList {},
        NormalTyMap => CategoryMap {},
        NormalTyTuple => CategoryTuple {},
        NormalTyEnum | NormalTyEnumVariant => CategoryEnum {},
        NormalTyFunction => CategoryFunction {},
        NormalTyFuture => CategoryFuture {},
        // A μ is transparent to its head (the walk into the body terminates:
        // no unfold happens here).
        let m: NormalTyMu => head_category(m.body),
        NormalTyInterface
            | NormalTyUnion
            | NormalTyAssociatedTypeProjection
            | NormalTyRecVar
            | NormalTyTypeVar
            | NormalTyOpaqueAlias
            | NormalTyNever
            | NormalTyUnknown
            | NormalTyError =>
        {
            null
        },
    }
}

// port: baml_type/src/normalize.rs::NormalTy::is_ground @ d9be6853b
// Whether every position is a fixed type rather than a placeholder that could
// still resolve to something else (Error, a TypeVar, an unresolved
// projection, an OpaqueAlias). `unknown` and `never` are determined.
function is_ground(t: NormalTy) -> bool throws never {
    match (t) {
        NormalTyError | NormalTyTypeVar | NormalTyAssociatedTypeProjection | NormalTyOpaqueAlias => {
            false
        },
        NormalTyInt
            | NormalTyBigint
            | NormalTyFloat
            | NormalTyString
            | NormalTyBool
            | NormalTyNull
            | NormalTyUint8Array
            | NormalTyMedia
            | NormalTyRustType
            | NormalTyType
            | NormalTyResource
            | NormalTyPromptAst
            | NormalTyLiteral
            | NormalTyEnum
            | NormalTyEnumVariant
            | NormalTyUnknown
            | NormalTyNever
            | NormalTyRecVar =>
        {
            true
        },
        let x: NormalTyList => is_ground(x.elem),
        let x: NormalTyMu => is_ground(x.body),
        let x: NormalTyMap => is_ground(x.key) && is_ground(x.value),
        let x: NormalTyFuture => is_ground(x.value) && is_ground(x.error),
        let x: NormalTyUnion => x.members.every(is_ground),
        let x: NormalTyTuple => x.items.every(is_ground),
        let x: NormalTyClass => x.args.every(is_ground),
        let x: NormalTyInterface => x.args.every(is_ground),
        let x: NormalTyFunction => {
            x.params.every((p) -> {
                is_ground(p.ty)
            })
                && is_ground(x.ret)
                && is_ground(x.throws_)
        },
    }
}

// port: baml_type/src/normalize.rs::NormalTy::arg_forces_disjoint @ d9be6853b
// Whether `t` and `other`, as invariant generic arguments, make their
// instantiations disjoint: both ground and not the same realized type. A μ in
// either leaves it unprovable (the unfolding arms of is_disjoint_from hand
// over non-canonical spellings).
function arg_forces_disjoint(t: NormalTy, other: NormalTy) -> bool throws never {
    is_ground(t) && is_ground(other) && t != other && !contains_mu(t) && !contains_mu(other)
}

// port: baml_type/src/normalize.rs::NormalTy::is_disjoint_from @ d9be6853b
// Whether no value of `t` can ever be `==`-equal to a value of `other`.
function is_disjoint_from(t: NormalTy, other: NormalTy) -> bool throws never {
    // A μ is its unfolding, except one with an unguarded spine (the read-back
    // bail's spelling), about which nothing is provable.
    if ((t is NormalTyMu || other is NormalTyMu) && (has_unguarded_mu(t) || has_unguarded_mu(other))) {
        return false;
    }
    match (t, other) {
        (NormalTyMu, _) => is_disjoint_from(unfold(t), other),
        (_, NormalTyMu) => is_disjoint_from(t, unfold(other)),

        // A union is disjoint from the other side iff every member is.
        (let u: NormalTyUnion, _) => {
            u.members.every((m) -> {
                is_disjoint_from(m, other)
            })
        },
        (_, let u: NormalTyUnion) => {
            u.members.every((m) -> {
                is_disjoint_from(t, m)
            })
        },

        // Invariant generic constructors: one provably different argument
        // pair is enough. A different class name is disjoint outright.
        (let c: NormalTyClass, let d: NormalTyClass) => {
            c.name != d.name
                || c.args.length() != d.args.length()
                || zip_any(c.args, d.args, arg_forces_disjoint)
        },
        (let a: NormalTyList, let b: NormalTyList) => arg_forces_disjoint(a.elem, b.elem),
        (let a: NormalTyMap, let b: NormalTyMap) => {
            arg_forces_disjoint(a.key, b.key) || arg_forces_disjoint(a.value, b.value)
        },
        (let a: NormalTyFuture, let b: NormalTyFuture) => {
            arg_forces_disjoint(a.value, b.value) || arg_forces_disjoint(a.error, b.error)
        },

        (let a: NormalTyTuple, let b: NormalTyTuple) => {
            a.items.length() != b.items.length() || zip_any(a.items, b.items, is_disjoint_from)
        },

        // Functions are not invariant, so not provably disjoint here.
        (let _f: NormalTyFunction, let _g: NormalTyFunction) => false,

        // Only different enums are disjoint: a custom `Equals` on one enum
        // could equate distinct variants of it.
        (let e: NormalTyEnum, let f: NormalTyEnum) => e.name != f.name,
        (let e: NormalTyEnumVariant, let f: NormalTyEnumVariant) => e.name != f.name,
        (let e: NormalTyEnumVariant, let f: NormalTyEnum) => e.name != f.name,
        (let f: NormalTyEnum, let e: NormalTyEnumVariant) => e.name != f.name,

        // Primitive literals: distinct values are never equal under their
        // unoverridable equality (floats excluded: NaN, decimal aliasing).
        (let x: NormalTyLiteral, let y: NormalTyLiteral) => {
            !(x.value is root.base.LiteralFloat)
                && !(y.value is root.base.LiteralFloat)
                && x.value != y.value
        },
        (let l: NormalTyLiteral, _) => literal_category_differs(l.value, other),
        (_, let l: NormalTyLiteral) => literal_category_differs(l.value, t),

        // Otherwise: disjoint iff both are ground concrete heads of different
        // categories.
        _ => {
            let x = head_category(t);
            let y = head_category(other);
            x != null && y != null && x != y
        },
    }
}

// port: baml_type/src/normalize.rs::NormalTy::is_disjoint_from @ d9be6853b
// The `(Literal(lit), rhs) | (rhs, Literal(lit))` arm, shared by both
// orientations (Rust binds both in one or-pattern).
function literal_category_differs(lit: root.base.Literal, rhs: NormalTy) -> bool throws never {
    let cat = head_category(rhs)
        ?? return false;
    cat != category_of_literal(lit)
}

// port: baml_type/src/normalize.rs::NormalTy::is_unoverridable_singleton @ d9be6853b
// Whether this pins its operand to one value whose equality the orphan rule
// forbids overriding: null, or a non-float primitive literal.
function is_unoverridable_singleton(t: NormalTy) -> bool throws never {
    match (t) {
        NormalTyNull => true,
        let l: NormalTyLiteral => !(l.value is root.base.LiteralFloat),
        _ => false,
    }
}

// port: baml_type/src/normalize.rs::Category::of_literal @ d9be6853b
function category_of_literal(lit: root.base.Literal) -> Category throws never {
    match (lit) {
        root.base.LiteralInt => CategoryInt {},
        root.base.LiteralBigint => CategoryBigint {},
        root.base.LiteralFloat => CategoryFloat {},
        root.base.LiteralString => CategoryString {},
        root.base.LiteralBool => CategoryBool {},
    }
}

// port: baml_type/src/normalize.rs::Category::of_head @ d9be6853b
// The category of a head canonicalization keeps, read before canonicalizing.
// Null for a head canonicalization can rewrite (alias, union, projection),
// one a context-driven rule relates across kinds (interface, type variable),
// a tuple, and the sentinels. Rust's `family_head_category!` table, spelled
// out for Ty.
function category_of_head(ty: Ty) -> Category? throws never {
    match (ty) {
        TyInt => CategoryInt {},
        TyBigint => CategoryBigint {},
        TyFloat => CategoryFloat {},
        TyString => CategoryString {},
        TyBool => CategoryBool {},
        let l: TyLiteral => category_of_literal(l.value),
        TyNull => CategoryNull {},
        TyUint8Array => CategoryUint8Array {},
        let m: TyMedia => CategoryMedia { kind: m.kind },
        TyRustType => CategoryRustType {},
        TyType => CategoryType {},
        TyResource => CategoryResource {},
        TyPromptAst => CategoryPromptAst {},
        TyClass => CategoryClass {},
        TyList => CategoryList {},
        TyMap => CategoryMap {},
        TyEnum | TyEnumVariant => CategoryEnum {},
        TyFunction => CategoryFunction {},
        TyFuture => CategoryFuture {},
        TyInterface
            | TyTuple
            | TyUnion
            | TyTypeAlias
            | TyTypeVar
            | TyAssociatedTypeProjection
            | TyUnknown
            | TyNever
            | TyError =>
        {
            null
        },
    }
}

// port: baml_type/src/normalize.rs::Category::of_interned_head @ d9be6853b
// category_of_head for the interned kind. A live inference variable can
// still become any type, so it has no category.
function category_of_interned_head(ty: InferTy) -> Category? throws never {
    match (ty) {
        TyInt => CategoryInt {},
        TyBigint => CategoryBigint {},
        TyFloat => CategoryFloat {},
        TyString => CategoryString {},
        TyBool => CategoryBool {},
        let l: TyLiteral => category_of_literal(l.value),
        TyNull => CategoryNull {},
        TyUint8Array => CategoryUint8Array {},
        let m: TyMedia => CategoryMedia { kind: m.kind },
        TyRustType => CategoryRustType {},
        TyType => CategoryType {},
        TyResource => CategoryResource {},
        TyPromptAst => CategoryPromptAst {},
        InferTyClass => CategoryClass {},
        InferTyList => CategoryList {},
        InferTyMap => CategoryMap {},
        TyEnum | TyEnumVariant => CategoryEnum {},
        InferTyFunction => CategoryFunction {},
        InferTyFuture => CategoryFuture {},
        InferTyInterface
            | InferTyTuple
            | InferTyUnion
            | TyTypeAlias
            | TyTypeVar
            | InferTyAssociatedTypeProjection
            | TyUnknown
            | TyNever
            | TyError
            | TyInferVar =>
        {
            null
        },
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// NORMALIZED TYPE
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize.rs::NormalTy @ d9be6853b
// Normalized structural type: aliases resolved, attributes and literal
// freshness erased, recursion made explicit with μ-binders. Ordering
// (cmp_normal_ty) is the canonical sort key for union members.
class NormalTyInt {
}

class NormalTyBigint {
}

class NormalTyFloat {
}

class NormalTyString {
}

class NormalTyBool {
}

class NormalTyNull {
}

class NormalTyUint8Array {
}

class NormalTyMedia {
    kind: root.base.MediaKind,
}

// Nominal opaque leaves, each compatible only with itself.
class NormalTyRustType {
}

class NormalTyType {
}

class NormalTyResource {
}

class NormalTyPromptAst {
}

// A single value as a type; freshness is erased.
class NormalTyLiteral {
    value: root.base.Literal,
}

class NormalTyClass {
    name: DeclName,
    args: NormalTy[],
}

class NormalTyInterface {
    name: DeclName,
    args: NormalTy[],
    bindings: NormalBinding[],
}

class NormalTyEnum {
    name: DeclName,
}

class NormalTyEnumVariant {
    name: DeclName,
    variant: string,
}

class NormalTyList {
    elem: NormalTy,
}

class NormalTyMap {
    key: NormalTy,
    value: NormalTy,
}

class NormalTyUnion {
    members: NormalTy[],
}

class NormalTyTuple {
    items: NormalTy[],
}

class NormalTyFunction {
    params: NormalParam[],
    ret: NormalTy,
    throws_: NormalTy,
}

class NormalTyFuture {
    value: NormalTy,
    error: NormalTy,
}

class NormalTyAssociatedTypeProjection {
    base: NormalTy,
    // The declaring interface (a normalized NormalTyInterface), always present.
    interface_: NormalTy,
    member: string,
}

// Recursion. Named phase: the alias name whose expansion introduced the
// binder. Canonical phase: its equality-transparent display.
class NormalTyMu {
    binder: DeclName | MuDisplay,
    body: NormalTy,
}

// A back-reference to an enclosing NormalTyMu. Named phase: the alias name.
// Canonical phase: the de Bruijn index (0 = innermost enclosing binder).
class NormalTyRecVar {
    var: DeclName | int,
}

// A generic type parameter: opaque, compatible only with itself, its bound's
// supertypes and the top type.
class NormalTyTypeVar {
    param: ParamTy,
}

// An alias the context could not resolve: equal only to the same alias.
class NormalTyOpaqueAlias {
    name: DeclName,
}

// Bottom: a subtype of every type.
class NormalTyNever {
}

// The `unknown` keyword: top, a supertype of every type.
class NormalTyUnknown {
}

// Error-recovery sentinel: bidirectionally compatible to suppress cascades.
class NormalTyError {
}

type NormalTy = NormalTyInt
    | NormalTyBigint
    | NormalTyFloat
    | NormalTyString
    | NormalTyBool
    | NormalTyNull
    | NormalTyUint8Array
    | NormalTyMedia
    | NormalTyRustType
    | NormalTyType
    | NormalTyResource
    | NormalTyPromptAst
    | NormalTyLiteral
    | NormalTyClass
    | NormalTyInterface
    | NormalTyEnum
    | NormalTyEnumVariant
    | NormalTyList
    | NormalTyMap
    | NormalTyUnion
    | NormalTyTuple
    | NormalTyFunction
    | NormalTyFuture
    | NormalTyAssociatedTypeProjection
    | NormalTyMu
    | NormalTyRecVar
    | NormalTyTypeVar
    | NormalTyOpaqueAlias
    | NormalTyNever
    | NormalTyUnknown
    | NormalTyError;

// The childless variants every structural walk treats alike (Rust lists them
// by hand in each match).
type NormalTyLeaf = NormalTyInt
    | NormalTyBigint
    | NormalTyFloat
    | NormalTyString
    | NormalTyBool
    | NormalTyNull
    | NormalTyUint8Array
    | NormalTyMedia
    | NormalTyRustType
    | NormalTyType
    | NormalTyResource
    | NormalTyPromptAst
    | NormalTyLiteral
    | NormalTyEnum
    | NormalTyEnumVariant
    | NormalTyTypeVar
    | NormalTyOpaqueAlias
    | NormalTyNever
    | NormalTyUnknown
    | NormalTyError;

// port: baml_type/src/normalize.rs::NormalParam @ d9be6853b
class NormalParam {
    name: string?,
    ty: NormalTy,
    mode: FunctionParamMode,
}

// port: baml_type/src/normalize.rs::NormalTy::Interface @ d9be6853b
// One `(Name, NormalTy)` associated-type binding of NormalTyInterface (Rust's
// tuple; tuples are not hashable).
class NormalBinding {
    name: string,
    ty: NormalTy,
}

// port: baml_type/src/normalize.rs::MuDisplay @ d9be6853b
// Display payload of a canonical μ-binder. `rendered` is the whole μ-subterm
// as a Ty (recursion spelled via alias names), what into_ty emits for the
// binder. `name` is the alias that introduced the binder; null only for
// automaton read-back binders on a cycle state no alias denotes.
// Equality-transparent by design: every value is equal and hashes alike, so
// equality on NormalTy sees only the de Bruijn structure (canonical equality
// is α-equivalence).
class MuDisplay {
    name: DeclName?,
    rendered: Ty,

    // port: baml_type/src/normalize.rs::MuDisplay::eq @ d9be6853b
    implements baml.ops.Equals {
        function eq(self, other: Self) -> bool {
            true
        }
    }

    // port: baml_type/src/normalize.rs::MuDisplay::hash @ d9be6853b
    implements baml.Hash {
        function hash(self, state: baml.hash.Hasher) -> null {
            null
        }
    }
}

// port: baml_type/src/normalize.rs::NormalTy::resolve_binders @ d9be6853b
// Rust's `saw_mu: &mut bool` out-parameter.
class SawMu {
    value: bool,
}

// port: baml_type/src/normalize.rs::NormalTy (derived Ord) @ d9be6853b
// The variant declaration order of NormalTy.
function variant_index_normal_ty(t: NormalTy) -> int throws never {
    match (t) {
        NormalTyInt => 0,
        NormalTyBigint => 1,
        NormalTyFloat => 2,
        NormalTyString => 3,
        NormalTyBool => 4,
        NormalTyNull => 5,
        NormalTyUint8Array => 6,
        NormalTyMedia => 7,
        NormalTyRustType => 8,
        NormalTyType => 9,
        NormalTyResource => 10,
        NormalTyPromptAst => 11,
        NormalTyLiteral => 12,
        NormalTyClass => 13,
        NormalTyInterface => 14,
        NormalTyEnum => 15,
        NormalTyEnumVariant => 16,
        NormalTyList => 17,
        NormalTyMap => 18,
        NormalTyUnion => 19,
        NormalTyTuple => 20,
        NormalTyFunction => 21,
        NormalTyFuture => 22,
        NormalTyAssociatedTypeProjection => 23,
        NormalTyMu => 24,
        NormalTyRecVar => 25,
        NormalTyTypeVar => 26,
        NormalTyOpaqueAlias => 27,
        NormalTyNever => 28,
        NormalTyUnknown => 29,
        NormalTyError => 30,
    }
}

// port: baml_type/src/normalize.rs::NormalTy (derived Ord) @ d9be6853b
// Variant order, then fields in order. MuDisplay compares equal; a named
// RecVar or binder compares by DeclName, a canonical one by index.
function cmp_normal_ty(a: NormalTy, b: NormalTy) -> baml.ops.Ordering throws never {
    let by_variant = variant_index_normal_ty(a).cmp(variant_index_normal_ty(b));
    if (by_variant != baml.ops.Ordering.Equal) {
        return by_variant;
    }
    let eq = baml.ops.Ordering.Equal;
    match (a, b) {
        (let x: NormalTyMedia, let y: NormalTyMedia) => cmp_media_kind(x.kind, y.kind),
        (let x: NormalTyLiteral, let y: NormalTyLiteral) => cmp_literal(x.value, y.value),
        (let x: NormalTyClass, let y: NormalTyClass) => {
            let o = cmp_decl_name(x.name, y.name);
            if (o != eq) {
                return o;
            }
            cmp_list(x.args, y.args, cmp_normal_ty)
        },
        (let x: NormalTyInterface, let y: NormalTyInterface) => {
            let o0 = cmp_decl_name(x.name, y.name);
            if (o0 != eq) {
                return o0;
            }
            let o1 = cmp_list(x.args, y.args, cmp_normal_ty);
            if (o1 != eq) {
                return o1;
            }
            cmp_list(x.bindings, y.bindings, cmp_normal_binding)
        },
        (let x: NormalTyEnum, let y: NormalTyEnum) => cmp_decl_name(x.name, y.name),
        (let x: NormalTyEnumVariant, let y: NormalTyEnumVariant) => {
            let o = cmp_decl_name(x.name, y.name);
            if (o != eq) {
                return o;
            }
            x.variant.cmp(y.variant)
        },
        (let x: NormalTyList, let y: NormalTyList) => cmp_normal_ty(x.elem, y.elem),
        (let x: NormalTyMap, let y: NormalTyMap) => {
            let o = cmp_normal_ty(x.key, y.key);
            if (o != eq) {
                return o;
            }
            cmp_normal_ty(x.value, y.value)
        },
        (let x: NormalTyUnion, let y: NormalTyUnion) => {
            cmp_list(x.members, y.members, cmp_normal_ty)
        },
        (let x: NormalTyTuple, let y: NormalTyTuple) => cmp_list(x.items, y.items, cmp_normal_ty),
        (let x: NormalTyFunction, let y: NormalTyFunction) => {
            let o0 = cmp_list(x.params, y.params, cmp_normal_param);
            if (o0 != eq) {
                return o0;
            }
            let o1 = cmp_normal_ty(x.ret, y.ret);
            if (o1 != eq) {
                return o1;
            }
            cmp_normal_ty(x.throws_, y.throws_)
        },
        (let x: NormalTyFuture, let y: NormalTyFuture) => {
            let o = cmp_normal_ty(x.value, y.value);
            if (o != eq) {
                return o;
            }
            cmp_normal_ty(x.error, y.error)
        },
        (let x: NormalTyAssociatedTypeProjection, let y: NormalTyAssociatedTypeProjection) => {
            let o0 = cmp_normal_ty(x.base, y.base);
            if (o0 != eq) {
                return o0;
            }
            let o1 = cmp_normal_ty(x.interface_, y.interface_);
            if (o1 != eq) {
                return o1;
            }
            x.member.cmp(y.member)
        },
        (let x: NormalTyMu, let y: NormalTyMu) => {
            let o = match (x.binder, y.binder) {
                (let p: DeclName, let q: DeclName) => cmp_decl_name(p, q),
                _ => eq,
            };
            if (o != eq) {
                return o;
            }
            cmp_normal_ty(x.body, y.body)
        },
        (let x: NormalTyRecVar, let y: NormalTyRecVar) => {
            match (x.var, y.var) {
                (let p: int, let q: int) => p.cmp(q),
                (let p: DeclName, let q: DeclName) => cmp_decl_name(p, q),
                _ => baml.sys.panic("cmp_normal_ty: RecVars of different phases"),
            }
        },
        (let x: NormalTyTypeVar, let y: NormalTyTypeVar) => cmp_param_ty(x.param, y.param),
        (let x: NormalTyOpaqueAlias, let y: NormalTyOpaqueAlias) => cmp_decl_name(x.name, y.name),
        _ => eq,
    }
}

// port: baml_type/src/normalize.rs::NormalParam (derived Ord) @ d9be6853b
function cmp_normal_param(a: NormalParam, b: NormalParam) -> baml.ops.Ordering throws never {
    let o0 = cmp_optional_string(a.name, b.name);
    if (o0 != baml.ops.Ordering.Equal) {
        return o0;
    }
    let o1 = cmp_normal_ty(a.ty, b.ty);
    if (o1 != baml.ops.Ordering.Equal) {
        return o1;
    }
    cmp_function_param_mode(a.mode, b.mode)
}

// port: baml_type/src/normalize.rs::NormalTy::Interface (derived Ord of `(Name, NormalTy)`) @ d9be6853b
function cmp_normal_binding(a: NormalBinding, b: NormalBinding) -> baml.ops.Ordering throws never {
    let o = a.name.cmp(b.name);
    if (o != baml.ops.Ordering.Equal) {
        return o;
    }
    cmp_normal_ty(a.ty, b.ty)
}

// port: baml_type/src/normalize.rs::NormalTy::canonicalize_union @ d9be6853b
// Rust's `Vec::dedup` on sorted members: drops each member equal to the one
// kept before it.
function dedup_normal_tys(xs: NormalTy[]) -> NormalTy[] throws never {
    let out: NormalTy[] = [];
    for (let x in xs) {
        let last = out.at(out.length() - 1);
        if (last == null || last != x) {
            out.push(x);
        }
    }
    out
}

// port: Rust's `a.iter().zip(b).all(f)` (std), over the shorter length.
function zip_all<A, B>(a: A[], b: B[], f: (A, B) -> bool) -> bool {
    let n = if (a.length() < b.length()) {
        a.length()
    } else {
        b.length()
    };
    for (let i = 0; i < n; i += 1) {
        if (!f(a[i], b[i])) {
            return false;
        }
    }
    true
}

// port: Rust's `a.iter().zip(b).any(f)` (std), over the shorter length.
function zip_any<A, B>(a: A[], b: B[], f: (A, B) -> bool) -> bool {
    let n = if (a.length() < b.length()) {
        a.length()
    } else {
        b.length()
    };
    for (let i = 0; i < n; i += 1) {
        if (f(a[i], b[i])) {
            return true;
        }
    }
    false
}

// ── conversion in: Ty to the named phase ─────────────────────────────────

// port: baml_type/src/normalize.rs::NormalTy::from_ty @ d9be6853b
// Ty to the named intermediate. A re-encountered alias is a RecVar and its
// expansion is wrapped in a Mu when the body mentions it; an unresolvable
// alias is opaque. A projection reduces through the context while `fuel`
// lasts (each reduction spends one), else stays an opaque leaf.
function from_ty(
    ty: Ty,
    ctx: TypeContext,
    expanding: map<DeclName, bool>,
    fuel: int,
) -> NormalTy throws never {
    let all = (tys: Ty[]) -> NormalTy[] {
        tys.map((t) -> {
            from_ty(t, ctx, expanding, fuel)
        })
    };
    let bindings = (associated_types: AssociatedType[]) -> NormalBinding[] {
        associated_types
            .map((b) -> {
                NormalBinding { name: b.name, ty: from_ty(b.ty, ctx, expanding, fuel) }
            })
            .sort_by((a, b) -> {
                a.name.cmp(b.name)
            })
    };
    match (ty) {
        TyInt => NormalTyInt {},
        TyBigint => NormalTyBigint {},
        TyFloat => NormalTyFloat {},
        TyString => NormalTyString {},
        TyBool => NormalTyBool {},
        TyNull => NormalTyNull {},
        TyUint8Array => NormalTyUint8Array {},
        let m: TyMedia => NormalTyMedia { kind: m.kind },
        TyRustType => NormalTyRustType {},
        TyType => NormalTyType {},
        TyResource => NormalTyResource {},
        TyPromptAst => NormalTyPromptAst {},
        TyUnknown => NormalTyUnknown {},
        TyNever => NormalTyNever {},
        TyError => NormalTyError {},
        // Freshness is a compiler-only widening flag, irrelevant to identity.
        let l: TyLiteral => NormalTyLiteral { value: l.value },
        let c: TyClass => NormalTyClass { name: c.name, args: all(c.args) },
        let i: TyInterface => {
            let bs = bindings(i.associated_types);
            NormalTyInterface { name: i.name, args: all(i.args), bindings: bs }
        },
        let e: TyEnum => NormalTyEnum { name: e.name },
        let v: TyEnumVariant => NormalTyEnumVariant { name: v.name, variant: v.variant },
        let l: TyList => NormalTyList { elem: from_ty(l.elem, ctx, expanding, fuel) },
        let m: TyMap => {
            NormalTyMap {
                key: from_ty(m.key, ctx, expanding, fuel),
                value: from_ty(m.value, ctx, expanding, fuel),
            }
        },
        let u: TyUnion => NormalTyUnion { members: all(u.members) },
        let t: TyTuple => NormalTyTuple { items: all(t.items) },
        let f: TyFunction => {
            NormalTyFunction {
                params: f.params.map((p) -> {
                    NormalParam {
                        name: p.name,
                        ty: from_ty(p.ty, ctx, expanding, fuel),
                        mode: p.mode,
                    }
                }),
                ret: from_ty(f.ret, ctx, expanding, fuel),
                throws_: from_ty(f.throws_, ctx, expanding, fuel),
            }
        },
        let f: TyFuture => {
            NormalTyFuture {
                value: from_ty(f.value, ctx, expanding, fuel),
                error: from_ty(f.error, ctx, expanding, fuel),
            }
        },
        let v: TyTypeVar => NormalTyTypeVar { param: v.param },
        let p: TyAssociatedTypeProjection => {
            // A projection is a pure type-level operator: `(int as Foo).Assoc`
            // is the type the impl binds, whenever the context can tell.
            if (fuel > 0) {
                if let r: ProjectionStepReduced = ctx.project(p.base, p.interface_, p.member, fuel) {
                    return from_ty(r.ty, ctx, expanding, fuel - 1);
                }
            }
            // Not reducible (symbolic base or exhausted fuel): an opaque leaf.
            NormalTyAssociatedTypeProjection {
                base: from_ty(p.base, ctx, expanding, fuel),
                interface_: from_ty(
                    TyInterface {
                        name: p.interface_.name,
                        args: p.interface_.generics,
                        associated_types: p.interface_.associated_types,
                    },
                    ctx,
                    expanding,
                    fuel,
                ),
                member: p.member,
            }
        },
        let a: TyTypeAlias => {
            if (expanding.has(a.name)) {
                // Back-edge: the enclosing expansion wraps the result in a μ.
                return NormalTyRecVar { var: a.name };
            }
            // Fail-safe: an unresolvable alias is opaque.
            let def = ctx.alias_def(a.name)
                ?? return NormalTyOpaqueAlias { name: a.name };
            expanding.set(a.name, true);
            let body = from_ty(def, ctx, expanding, fuel);
            expanding.delete(a.name);
            if (mentions_rec_var(body, a.name)) {
                NormalTyMu { binder: a.name, body: body }
            } else {
                body
            }
        },
    }
}

// port: baml_type/src/normalize.rs::NormalTy::mentions_rec_var @ d9be6853b
// Whether this named-phase term contains a back-reference to `var`. A nested
// μ over the same name rebinds it.
function mentions_rec_var(t: NormalTy, var: DeclName) -> bool throws never {
    match (t) {
        let r: NormalTyRecVar => r.var == var,
        let m: NormalTyMu => m.binder != var && mentions_rec_var(m.body, var),
        let x: NormalTyClass => {
            x.args.some((a) -> {
                mentions_rec_var(a, var)
            })
        },
        let x: NormalTyInterface => {
            x.args.some((a) -> {
                mentions_rec_var(a, var)
            })
                || x.bindings.some((b) -> {
                    mentions_rec_var(b.ty, var)
                })
        },
        let x: NormalTyList => mentions_rec_var(x.elem, var),
        let x: NormalTyMap => mentions_rec_var(x.key, var) || mentions_rec_var(x.value, var),
        let x: NormalTyUnion => {
            x.members.some((m) -> {
                mentions_rec_var(m, var)
            })
        },
        let x: NormalTyTuple => {
            x.items.some((m) -> {
                mentions_rec_var(m, var)
            })
        },
        let x: NormalTyFunction => {
            x.params.some((p) -> {
                mentions_rec_var(p.ty, var)
            })
                || mentions_rec_var(x.ret, var)
                || mentions_rec_var(x.throws_, var)
        },
        let x: NormalTyFuture => mentions_rec_var(x.value, var) || mentions_rec_var(x.error, var),
        let x: NormalTyAssociatedTypeProjection => {
            mentions_rec_var(x.base, var) || mentions_rec_var(x.interface_, var)
        },
        NormalTyLeaf => false,
    }
}

// port: baml_type/src/normalize.rs::NormalTy::legacy_render @ d9be6853b
// A named-phase term as a Ty, every binder dropped and every back-reference
// spelled as its alias name: the interim MuDisplay.rendered that fact-oracle
// calls see during bottom-up absorption of closed μ members.
function legacy_render(t: NormalTy) -> Ty throws never {
    match (t) {
        NormalTyInt => TyInt {},
        NormalTyBigint => TyBigint {},
        NormalTyFloat => TyFloat {},
        NormalTyString => TyString {},
        NormalTyBool => TyBool {},
        NormalTyNull => TyNull {},
        NormalTyUint8Array => TyUint8Array {},
        let m: NormalTyMedia => TyMedia { kind: m.kind },
        NormalTyRustType => TyRustType {},
        NormalTyType => TyType {},
        NormalTyResource => TyResource {},
        NormalTyPromptAst => TyPromptAst {},
        NormalTyUnknown => TyUnknown {},
        NormalTyNever => TyNever {},
        NormalTyError => TyError {},
        let l: NormalTyLiteral => TyLiteral { value: l.value, freshness: Freshness.Regular },
        let c: NormalTyClass => TyClass { name: c.name, args: c.args.map(legacy_render) },
        let i: NormalTyInterface => {
            TyInterface {
                name: i.name,
                args: i.args.map(legacy_render),
                associated_types: i.bindings.map((b) -> {
                    AssociatedType { name: b.name, ty: legacy_render(b.ty) }
                }),
            }
        },
        let e: NormalTyEnum => TyEnum { name: e.name },
        let v: NormalTyEnumVariant => TyEnumVariant { name: v.name, variant: v.variant },
        let l: NormalTyList => TyList { elem: legacy_render(l.elem) },
        let m: NormalTyMap => TyMap { key: legacy_render(m.key), value: legacy_render(m.value) },
        let u: NormalTyUnion => TyUnion { members: u.members.map(legacy_render) },
        let x: NormalTyTuple => TyTuple { items: x.items.map(legacy_render) },
        let f: NormalTyFunction => {
            TyFunction {
                params: f.params.map((p) -> {
                    FunctionParamTy { name: p.name, ty: legacy_render(p.ty), mode: p.mode }
                }),
                ret: legacy_render(f.ret),
                throws_: legacy_render(f.throws_),
            }
        },
        let f: NormalTyFuture => {
            TyFuture { value: legacy_render(f.value), error: legacy_render(f.error) }
        },
        let p: NormalTyAssociatedTypeProjection => {
            let iface = match (p.interface_) {
                let i: NormalTyInterface => {
                    InterfaceConstraint {
                        name: i.name,
                        generics: i.args.map(legacy_render),
                        associated_types: i.bindings.map((b) -> {
                            AssociatedType { name: b.name, ty: legacy_render(b.ty) }
                        }),
                    }
                },
                _ => baml.sys.panic("projection qualifier is an interface"),
            };
            TyAssociatedTypeProjection {
                base: legacy_render(p.base),
                interface_: iface,
                member: p.member,
            }
        },
        let v: NormalTyTypeVar => TyTypeVar { param: v.param },
        // The binder has no surface syntax (its body renders in place); a
        // back-reference is spelled as its alias name.
        let m: NormalTyMu => legacy_render(m.body),
        let r: NormalTyRecVar => {
            match (r.var) {
                let qn: DeclName => TyTypeAlias { name: qn },
                _ => baml.sys.panic("legacy_render on a canonical-phase RecVar"),
            }
        },
        let o: NormalTyOpaqueAlias => TyTypeAlias { name: o.name },
    }
}

// ── phase conversion: named to canonical ─────────────────────────────────

// port: baml_type/src/normalize.rs::NormalTy::resolve_binders @ d9be6853b
// Strictly convert the named intermediate to the canonical de Bruijn phase:
// each back-reference becomes the distance to its binder, each binder keeps
// its alias name in its display, and `saw_mu` records whether any binder was
// emitted. Runs on the completed named term, where binder-hood is decided.
function resolve_binders(t: NormalTy, stack: DeclName[], saw_mu: SawMu) -> NormalTy throws never {
    let go = (x: NormalTy) -> NormalTy {
        resolve_binders(x, stack, saw_mu)
    };
    match (t) {
        let m: NormalTyMu => {
            let binder = match (m.binder) {
                let qn: DeclName => qn,
                _ => baml.sys.panic("resolve_binders on a canonical-phase binder"),
            };
            saw_mu.value = true;
            let display = MuDisplay { name: binder, rendered: legacy_render(m.body) };
            stack.push(binder);
            let body = go(m.body);
            stack.pop();
            NormalTyMu { binder: display, body: body }
        },
        let r: NormalTyRecVar => {
            // from_ty emits a RecVar only while its alias is on the expanding
            // path, so its binder is on the stack.
            let i = stack.find_last_index((v) -> {
                r.var == v
            })
                ?? baml.sys.panic(
                    "from_ty emits a RecVar only while its alias is on the expanding path",
                );
            NormalTyRecVar { var: stack.length() - 1 - i }
        },
        let x: NormalTyClass => NormalTyClass { name: x.name, args: x.args.map(go) },
        let x: NormalTyInterface => {
            NormalTyInterface {
                name: x.name,
                args: x.args.map(go),
                bindings: x.bindings.map((b) -> {
                    NormalBinding { name: b.name, ty: go(b.ty) }
                }),
            }
        },
        let x: NormalTyList => NormalTyList { elem: go(x.elem) },
        let x: NormalTyMap => NormalTyMap { key: go(x.key), value: go(x.value) },
        let x: NormalTyUnion => NormalTyUnion { members: x.members.map(go) },
        let x: NormalTyTuple => NormalTyTuple { items: x.items.map(go) },
        let x: NormalTyFunction => {
            NormalTyFunction {
                params: x.params.map((p) -> {
                    NormalParam { name: p.name, ty: go(p.ty), mode: p.mode }
                }),
                ret: go(x.ret),
                throws_: go(x.throws_),
            }
        },
        let x: NormalTyFuture => NormalTyFuture { value: go(x.value), error: go(x.error) },
        let x: NormalTyAssociatedTypeProjection => {
            NormalTyAssociatedTypeProjection {
                base: go(x.base),
                interface_: go(x.interface_),
                member: x.member,
            }
        },
        let x: NormalTyLeaf => x,
    }
}

// ── canonicalization ─────────────────────────────────────────────────────

// port: baml_type/src/normalize.rs::NormalTy::canonicalize @ d9be6853b
// Rewrite to a unique canonical form: children canonicalized bottom-up,
// unions reduced by the full set algebra. `saw_mu` (from resolve_binders)
// switches the μ-related guards on.
function canonicalize(
    t: NormalTy,
    ctx: TypeContext,
    saw_mu: bool,
    assumptions: (NormalTy, NormalTy)[],
) -> NormalTy throws never {
    let go = (x: NormalTy) -> NormalTy {
        canonicalize(x, ctx, saw_mu, assumptions)
    };
    match (t) {
        let x: NormalTyClass => NormalTyClass { name: x.name, args: x.args.map(go) },
        let x: NormalTyInterface => {
            let bindings = x.bindings
                .map((b) -> {
                    NormalBinding { name: b.name, ty: go(b.ty) }
                })
                .sort_by((a, b) -> {
                    a.name.cmp(b.name)
                });
            NormalTyInterface { name: x.name, args: x.args.map(go), bindings: bindings }
        },
        let x: NormalTyList => NormalTyList { elem: go(x.elem) },
        let x: NormalTyMap => NormalTyMap { key: go(x.key), value: go(x.value) },
        let x: NormalTyFuture => NormalTyFuture { value: go(x.value), error: go(x.error) },
        let x: NormalTyAssociatedTypeProjection => {
            NormalTyAssociatedTypeProjection {
                base: go(x.base),
                interface_: go(x.interface_),
                member: x.member,
            }
        },
        let x: NormalTyFunction => {
            // Required params are positional (names erased, order kept);
            // optional params are keyed by name (sorted).
            let required: NormalParam[] = [];
            let optional: NormalParam[] = [];
            for (let p in x.params) {
                let ty = go(p.ty);
                match (p.mode) {
                    FunctionParamMode.Required => {
                        required.push(
                            NormalParam { name: null, ty: ty, mode: FunctionParamMode.Required },
                        );
                    },
                    FunctionParamMode.Optional => {
                        optional.push(
                            NormalParam { name: p.name, ty: ty, mode: FunctionParamMode.Optional },
                        );
                    },
                }
            }
            optional.sort_by(cmp_normal_param);
            NormalTyFunction {
                params: required.concat(optional),
                ret: go(x.ret),
                throws_: go(x.throws_),
            }
        },
        // A binder stays put even if an algebra step strands it; the
        // automaton's read-back emits binders only for referenced states.
        let x: NormalTyMu => NormalTyMu { binder: x.binder, body: go(x.body) },
        let x: NormalTyUnion => canonicalize_union(x.members.map(go), ctx, saw_mu, assumptions),
        let x: NormalTyTuple => {
            let items = x.items.map(go);
            if (
                items.some((e) -> {
                    e is NormalTyNever
                })
            ) {
                NormalTyNever {}
            } else {
                NormalTyTuple { items: items }
            }
        },
        let x: NormalTyLeaf | NormalTyRecVar => x,
    }
}

// ── subtyping ────────────────────────────────────────────────────────────

// port: baml_type/src/normalize.rs::NormalTy::invariant_compatible @ d9be6853b
// Invariant-position compatibility for a generic argument: mutual subtypes.
// Error satisfies it either way; `unknown` does not.
function invariant_compatible(
    t: NormalTy,
    other: NormalTy,
    ctx: TypeContext,
    assumptions: (NormalTy, NormalTy)[],
) -> bool throws never {
    is_subtype_of(t, other, ctx, assumptions) && is_subtype_of(other, t, ctx, assumptions)
}

// port: baml_type/src/normalize.rs::NormalTy::pin_is_tautological @ d9be6853b
// Whether pin `(member, value)` required of `var <: name<args, ..>` is the
// variable's own projection of that member through that same interface,
// `(var as name<args>).member`: any `var` implementing the interface
// satisfies it definitionally. Extra pins on the qualifier do not matter.
function pin_is_tautological(
    var: ParamTy,
    name: DeclName,
    args: NormalTy[],
    pin: NormalBinding,
    ctx: TypeContext,
    assumptions: (NormalTy, NormalTy)[],
) -> bool throws never {
    let p = match (pin.ty) {
        let p: NormalTyAssociatedTypeProjection => p,
        _ => {
            return false;
        },
    };
    if (p.member != pin.name) {
        return false;
    }
    let base_is_var = match (p.base) {
        let v: NormalTyTypeVar => v.param == var,
        _ => false,
    };
    if (!base_is_var) {
        return false;
    }
    match (p.interface_) {
        let i: NormalTyInterface => {
            i.name == name
                && i.args.length() == args.length()
                && zip_all(i.args, args, (a, b) -> {
                    invariant_compatible(a, b, ctx, assumptions)
                })
        },
        _ => false,
    }
}

// port: baml_type/src/normalize.rs::NormalTy::is_subtype_of @ d9be6853b
// Equirecursive subtyping with co-inductive assumptions; operands must be
// canonical. No representation-changing coercions: the only widenings are
// literal-into-base and variant-into-enum.
//
// Termination: a cycle can only arise through an arm that expands a type
// instead of descending into a smaller subterm (μ-unfolding on either side, a
// TypeVar or projection bound on the left), so pairs are recorded only there.
function is_subtype_of(
    sub: NormalTy,
    sup: NormalTy,
    ctx: TypeContext,
    assumptions: (NormalTy, NormalTy)[],
) -> bool throws never {
    if (sub == sup) {
        return true;
    }
    // Bottom is a subtype of everything; top is a supertype of everything.
    if (sub is NormalTyNever) {
        return true;
    }
    if (sup is NormalTyUnknown) {
        return true;
    }
    // `unknown` is a subtype of nothing else.
    if (sub is NormalTyUnknown) {
        return false;
    }
    // Error-recovery sentinels are bidirectionally compatible.
    if (sub is NormalTyError || sup is NormalTyError) {
        return true;
    }
    let expanding = sub is NormalTyMu
        || sub is NormalTyTypeVar
        || sub is NormalTyAssociatedTypeProjection
        || sup is NormalTyMu;
    if (!expanding) {
        return is_subtype_of_inner(sub, sup, ctx, assumptions);
    }
    if (
        assumptions.some((pair) -> {
            pair.0 == sub && pair.1 == sup
        })
    ) {
        return true;
    }
    assumptions.push((sub, sup));
    let result = is_subtype_of_inner(sub, sup, ctx, assumptions);
    assumptions.pop();
    result
}

// port: baml_type/src/normalize.rs::NormalTy::is_subtype_of_inner @ d9be6853b
// The structural rules of is_subtype_of, which owns the fast paths and the
// assumption bookkeeping; callers go through it.
function is_subtype_of_inner(
    sub: NormalTy,
    sup: NormalTy,
    ctx: TypeContext,
    assumptions: (NormalTy, NormalTy)[],
) -> bool throws never {
    let le = (a: NormalTy, b: NormalTy) -> bool {
        is_subtype_of(a, b, ctx, assumptions)
    };
    let inv = (a: NormalTy, b: NormalTy) -> bool {
        invariant_compatible(a, b, ctx, assumptions)
    };
    // A bound proves `sup` when its canonical form (under the threaded
    // assumptions) is a subtype of it.
    let bound_proves = (bound: InterfaceConstraint, target: NormalTy) -> bool {
        let bound_ty = TyInterface {
            name: bound.name,
            args: bound.generics,
            associated_types: bound.associated_types,
        };
        le(canonical_with(bound_ty, ctx, assumptions), target)
    };
    match (sub, sup) {
        // μ-unfolding (equirecursive).
        (NormalTyMu, _) => le(unfold(sub), sup),
        (_, NormalTyMu) => le(sub, unfold(sup)),

        // Union decomposition; a union on the left goes first.
        (let u: NormalTyUnion, _) => {
            u.members.every((m) -> {
                le(m, sup)
            })
        },
        (_, let u: NormalTyUnion) => {
            u.members.some((m) -> {
                le(sub, m)
            })
        },

        // A type variable is a subtype of `sup` if any of its bounds is (the
        // bounds are a conjunction). Tautological pins on an interface `sup`
        // are stripped first.
        (let v: NormalTyTypeVar, let i: NormalTyInterface)
            if i.bindings.some((pin) -> {
            pin_is_tautological(v.param, i.name, i.args, pin, ctx, assumptions)
        }) => {
            let stripped = NormalTyInterface {
                name: i.name,
                args: i.args,
                bindings: i.bindings.filter((pin) -> {
                    !pin_is_tautological(v.param, i.name, i.args, pin, ctx, assumptions)
                }),
            };
            ctx.type_var_bound(v.param).some((bound) -> {
                bound_proves(bound, stripped)
            })
        },
        (let v: NormalTyTypeVar, _) => {
            ctx.type_var_bound(v.param).some((bound) -> {
                bound_proves(bound, sup)
            })
        },

        // A still-symbolic projection is a subtype of `sup` if any of its
        // associated type's declared bounds is. Precedes the interface arms,
        // which would ask implements_interface about a non-concrete type.
        (let p: NormalTyAssociatedTypeProjection, _) => {
            let iface = into_interface(p.interface_)
                ?? return false;
            ctx.associated_type_bound(iface, p.member).some((bound) -> {
                bound_proves(bound, sup)
            })
        },

        // `reflect.AnyClass` is compiler-derived for class values; before the
        // general impl-registry arm.
        (_, let i: NormalTyInterface) if is_any_class(i.name, ctx) && !(sub is NormalTyInterface) => {
            sub is NormalTyClass
        },

        // `reflect.AnyFunction` is implemented by every function type: the
        // return type must fit the `Returns` pin and the throws type the
        // `Throws` pin. A missing pin accepts everything.
        (let f: NormalTyFunction, let i: NormalTyInterface) if is_any_function(i.name, ctx) => {
            let pin = (name: string) -> NormalTy? {
                i.bindings
                    .find((b) -> {
                        b.name == name
                    })
                    ?.ty
            };
            let returns = pin("Returns");
            let throws_pin = pin("Throws");
            (returns == null || le(f.ret, returns))
                && (throws_pin == null || le(f.throws_, throws_pin))
        },

        // `AnyFunction`'s pins are covariant, unlike every other interface
        // binding. A pin missing on the sub side reads as its `unknown`
        // default.
        (let a: NormalTyInterface, let b: NormalTyInterface)
            if is_any_function(a.name, ctx) && is_any_function(b.name, ctx) => {
            b.bindings.every((sup_pin) -> {
                let sub_pin = a.bindings.find((x) -> {
                    x.name == sup_pin.name
                });
                match (sub_pin) {
                    let s: NormalBinding => le(s.ty, sup_pin.ty),
                    null => le(NormalTyUnknown {}, sup_pin.ty),
                }
            })
        },

        // A concrete (or any non-interface) type implementing an interface.
        (_, let i: NormalTyInterface) if !(sub is NormalTyInterface) => {
            ctx.implements_interface(into_ty(sub), interface_constraint(i.name, i.args, i.bindings))
        },
        // Interface-to-interface: `A <: B` iff `A` requires `B`.
        (let a: NormalTyInterface, let b: NormalTyInterface) => {
            ctx.interface_requires(
                interface_constraint(a.name, a.args, a.bindings),
                interface_constraint(b.name, b.args, b.bindings),
            )
        },

        // Generic arguments are invariant: classes, lists, maps, tuples and
        // futures relate only when every argument pair is mutual subtypes.
        (let a: NormalTyClass, let b: NormalTyClass)
            if a.name == b.name && a.args.length() == b.args.length() => {
            zip_all(a.args, b.args, inv)
        },
        (let a: NormalTyList, let b: NormalTyList) => inv(a.elem, b.elem),
        (let a: NormalTyMap, let b: NormalTyMap) => inv(a.key, b.key) && inv(a.value, b.value),
        (let a: NormalTyTuple, let b: NormalTyTuple) => {
            a.items.length() == b.items.length() && zip_all(a.items, b.items, inv)
        },
        (let a: NormalTyFuture, let b: NormalTyFuture) => {
            inv(a.value, b.value) && inv(a.error, b.error)
        },

        // Literal types are subtypes of their (same-representation) base only.
        (let l: NormalTyLiteral, NormalTyInt) => l.value is root.base.LiteralInt,
        (let l: NormalTyLiteral, NormalTyBigint) => l.value is root.base.LiteralBigint,
        (let l: NormalTyLiteral, NormalTyFloat) => l.value is root.base.LiteralFloat,
        (let l: NormalTyLiteral, NormalTyString) => l.value is root.base.LiteralString,
        (let l: NormalTyLiteral, NormalTyBool) => l.value is root.base.LiteralBool,

        // A variant is a subtype of its enum.
        (let v: NormalTyEnumVariant, let e: NormalTyEnum) => v.name == e.name,

        // Contravariant params, covariant return and throws.
        (let a: NormalTyFunction, let b: NormalTyFunction) => {
            le(a.ret, b.ret)
                && le(a.throws_, b.throws_)
                && normal_param_list_subtype(a.params, b.params, ctx, assumptions)
        },

        _ => false,
    }
}

// ── conversion out: canonical to Ty ──────────────────────────────────────

// port: baml_type/src/normalize.rs::NormalTy::into_ty @ d9be6853b
// Render a closed canonical form back as a Ty. A μ-subterm renders as its
// precomputed display and is never descended into, so a RecVar is
// unreachable here.
function into_ty(t: NormalTy) -> Ty throws never {
    match (t) {
        NormalTyInt => TyInt {},
        NormalTyBigint => TyBigint {},
        NormalTyFloat => TyFloat {},
        NormalTyString => TyString {},
        NormalTyBool => TyBool {},
        NormalTyNull => TyNull {},
        NormalTyUint8Array => TyUint8Array {},
        let m: NormalTyMedia => TyMedia { kind: m.kind },
        NormalTyRustType => TyRustType {},
        NormalTyType => TyType {},
        NormalTyResource => TyResource {},
        NormalTyPromptAst => TyPromptAst {},
        NormalTyUnknown => TyUnknown {},
        NormalTyNever => TyNever {},
        NormalTyError => TyError {},
        let l: NormalTyLiteral => TyLiteral { value: l.value, freshness: Freshness.Regular },
        let c: NormalTyClass => TyClass { name: c.name, args: c.args.map(into_ty) },
        let i: NormalTyInterface => {
            TyInterface {
                name: i.name,
                args: i.args.map(into_ty),
                associated_types: i.bindings.map((b) -> {
                    AssociatedType { name: b.name, ty: into_ty(b.ty) }
                }),
            }
        },
        let e: NormalTyEnum => TyEnum { name: e.name },
        let v: NormalTyEnumVariant => TyEnumVariant { name: v.name, variant: v.variant },
        let l: NormalTyList => TyList { elem: into_ty(l.elem) },
        let m: NormalTyMap => TyMap { key: into_ty(m.key), value: into_ty(m.value) },
        let u: NormalTyUnion => TyUnion { members: u.members.map(into_ty) },
        let x: NormalTyTuple => TyTuple { items: x.items.map(into_ty) },
        let f: NormalTyFunction => {
            TyFunction {
                params: f.params.map((p) -> {
                    FunctionParamTy { name: p.name, ty: into_ty(p.ty), mode: p.mode }
                }),
                ret: into_ty(f.ret),
                throws_: into_ty(f.throws_),
            }
        },
        let f: NormalTyFuture => TyFuture { value: into_ty(f.value), error: into_ty(f.error) },
        let p: NormalTyAssociatedTypeProjection => {
            TyAssociatedTypeProjection {
                base: into_ty(p.base),
                // A normalized projection's qualifier round-trips to an
                // interface.
                interface_: into_interface(p.interface_)
                    ?? baml.sys.panic("projection qualifier is an interface"),
                member: p.member,
            }
        },
        let v: NormalTyTypeVar => TyTypeVar { param: v.param },
        // A μ-subterm renders as its precomputed display.
        let m: NormalTyMu => mu_display(m).rendered,
        NormalTyRecVar => {
            baml.sys.panic(
                "into_ty on a free RecVar; canonical forms at public boundaries are closed and render recursion via their binder's display",
            )
        },
        let o: NormalTyOpaqueAlias => TyTypeAlias { name: o.name },
    }
}

// port: baml_type/src/normalize.rs::NormalTy::Mu @ d9be6853b
// The canonical-phase display of a binder (`binder.rendered` in Rust, where
// the phase types guarantee it is one).
function mu_display(m: NormalTyMu) -> MuDisplay throws never {
    match (m.binder) {
        let d: MuDisplay => d,
        _ => baml.sys.panic("a named-phase binder reached the canonical phase"),
    }
}

// port: baml_type/src/normalize.rs::NormalTy::interface_constraint @ d9be6853b
// The interface constraint a NormalTyInterface's parts denote, converted back
// to Ty: the shape handed to the membership and requires oracles.
function interface_constraint(
    name: DeclName,
    generics: NormalTy[],
    bindings: NormalBinding[],
) -> InterfaceConstraint throws never {
    InterfaceConstraint {
        name: name,
        generics: generics.map(into_ty),
        associated_types: bindings.map((b) -> {
            AssociatedType { name: b.name, ty: into_ty(b.ty) }
        }),
    }
}

// port: baml_type/src/normalize.rs::NormalTy::into_interface @ d9be6853b
// A normalized interface as its constraint; null for any other variant. A
// μ-wrapped interface (a projection qualifier merged with a standalone
// member) reads the constraint off its display instead of unfolding, which
// would loop.
function into_interface(t: NormalTy) -> InterfaceConstraint? throws never {
    match (t) {
        let i: NormalTyInterface => interface_constraint(i.name, i.args, i.bindings),
        let m: NormalTyMu => {
            match (mu_display(m).rendered) {
                let i: TyInterface => {
                    InterfaceConstraint {
                        name: i.name,
                        generics: i.args,
                        associated_types: i.associated_types,
                    }
                },
                _ => null,
            }
        },
        _ => null,
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// UNION CANONICALIZATION
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize.rs::NormalTy::canonicalize_union @ d9be6853b
// Reduce a union of canonical members: flatten, drop `never`, absorb under
// `unknown`, collapse complete enums and bools, absorb subtype members, sort,
// dedup, unwrap singletons.
function canonicalize_union(
    members: NormalTy[],
    ctx: TypeContext,
    saw_mu: bool,
    assumptions: (NormalTy, NormalTy)[],
) -> NormalTy throws never {
    // Flatten one level (a μ-unfold or alias can surface a nested union).
    let flat: NormalTy[] = [];
    for (let m in members) {
        match (m) {
            let u: NormalTyUnion => {
                for (let inner in u.members) {
                    flat.push(inner);
                }
            },
            NormalTyNever => {},
            _ => {
                flat.push(m);
            },
        }
    }
    // `unknown` (top) absorbs everything.
    if (
        flat.some((m) -> {
            m is NormalTyUnknown
        })
    ) {
        return NormalTyUnknown {};
    }
    let sorted = dedup_normal_tys(flat.sort_by(cmp_normal_ty));
    let collapsed = collapse_complete_bools(collapse_complete_enums(sorted, ctx));
    let kept = absorb_subtypes(collapsed, ctx, saw_mu, assumptions);
    let out = dedup_normal_tys(kept.sort_by(cmp_normal_ty));
    match (out.length()) {
        0 => NormalTyNever {},
        1 => out[0],
        _ => NormalTyUnion { members: out },
    }
}

// port: baml_type/src/normalize.rs::NormalTy::collapse_complete_enums @ d9be6853b
// Replace a complete set of an enum's variants with the enum (`E.A | E.B |
// .. == E`), for enums with at least two variants. Returns the members
// instead of editing them in place.
function collapse_complete_enums(members: NormalTy[], ctx: TypeContext) -> NormalTy[] throws never {
    // Distinct enums with at least one variant present, sorted.
    let enums: DeclName[] = [];
    for (let m in members) {
        if let v: NormalTyEnumVariant = m {
            enums.push(v.name);
        }
    }
    enums.sort_by(cmp_decl_name);
    let out = members;
    let prev: DeclName? = null;
    for (let e in enums) {
        if (prev != null && prev == e) {
            continue;
        }
        prev = e;
        // An unknown enum does not collapse (fail-safe).
        let all = ctx.enum_variants(e);
        if (all == null) {
            continue;
        }
        let present: map<string, bool> = {};
        for (let m in out) {
            if let v: NormalTyEnumVariant = m {
                if (v.name == e) {
                    present.set(v.variant, true);
                }
            }
        }
        // At least two variants: collapsing a one-variant enum would split one
        // value set into two canonical spellings.
        if (
            all.length() >= 2
                && all.every((v) -> {
                    present.has(v)
                })
        ) {
            out
                = out
                    .filter((m) -> {
                        match (m) {
                            let v: NormalTyEnumVariant => v.name != e,
                            _ => true,
                        }
                    })
                    .concat([NormalTyEnum { name: e }]);
        }
    }
    out
}

// port: baml_type/src/normalize.rs::NormalTy::has_unguarded_mu @ d9be6853b
// Whether any μ-binder here is non-contractive: its body reaches a
// back-reference to that binder through union spines alone (the μ of `type A
// = A | A[]`). Such members must not reach the subtype checker before
// ε-closure.
function has_unguarded_mu(t: NormalTy) -> bool throws never {
    match (t) {
        let m: NormalTyMu => spine_has_rec(m.body, 0) || has_unguarded_mu(m.body),
        NormalTyRecVar => false,
        let x: NormalTyList => has_unguarded_mu(x.elem),
        let x: NormalTyMap => has_unguarded_mu(x.key) || has_unguarded_mu(x.value),
        let x: NormalTyFuture => has_unguarded_mu(x.value) || has_unguarded_mu(x.error),
        let x: NormalTyUnion => x.members.some(has_unguarded_mu),
        let x: NormalTyTuple => x.items.some(has_unguarded_mu),
        let x: NormalTyClass => x.args.some(has_unguarded_mu),
        let x: NormalTyInterface => {
            x.args.some(has_unguarded_mu)
                || x.bindings.some((b) -> {
                    has_unguarded_mu(b.ty)
                })
        },
        let x: NormalTyFunction => {
            x.params.some((p) -> {
                has_unguarded_mu(p.ty)
            })
                || has_unguarded_mu(x.ret)
                || has_unguarded_mu(x.throws_)
        },
        let x: NormalTyAssociatedTypeProjection => {
            has_unguarded_mu(x.base) || has_unguarded_mu(x.interface_)
        },
        NormalTyLeaf => false,
    }
}

// port: baml_type/src/normalize.rs::NormalTy::has_unguarded_mu::spine_has_rec @ d9be6853b
// Whether `t`'s union spine reaches the RecVar bound `depth` binders out.
function spine_has_rec(t: NormalTy, depth: int) -> bool throws never {
    match (t) {
        let r: NormalTyRecVar => r.var == depth,
        let u: NormalTyUnion => {
            u.members.some((m) -> {
                spine_has_rec(m, depth)
            })
        },
        let m: NormalTyMu => spine_has_rec(m.body, depth + 1),
        _ => false,
    }
}

// port: baml_type/src/normalize.rs::NormalTy::collapse_complete_bools @ d9be6853b
// Replace the complete pair of bool literals with `bool` (`true | false ==
// bool`). Returns the members instead of editing them in place.
function collapse_complete_bools(members: NormalTy[]) -> NormalTy[] throws never {
    let has = (b: bool) -> bool {
        members.some((m) -> {
            match (m) {
                let l: NormalTyLiteral => {
                    match (l.value) {
                        let x: root.base.LiteralBool => x.value == b,
                        _ => false,
                    }
                },
                _ => false,
            }
        })
    };
    if (!(has(true) && has(false))) {
        return members;
    }
    members
        .filter((m) -> {
            match (m) {
                let l: NormalTyLiteral => !(l.value is root.base.LiteralBool),
                _ => true,
            }
        })
        .concat([NormalTyBool {}])
}

// port: baml_type/src/normalize.rs::NormalTy::absorb_subtypes @ d9be6853b
// Remove any member subsumed by another (`X | Y == Y` when `X <: Y`).
// Sentinels never absorb or are absorbed. Deferred members (an open one, with
// a free RecVar, or one holding a non-contractive μ) are skipped; the μ
// automaton completes their absorption over closed read-backs.
function absorb_subtypes(
    members: NormalTy[],
    ctx: TypeContext,
    saw_mu: bool,
    assumptions: (NormalTy, NormalTy)[],
) -> NormalTy[] throws never {
    let n = members.length();
    // Only computed when a μ exists somewhere in the term.
    let open = if (saw_mu) {
        members.map((m) -> {
            has_free_rec_var(m, 0) || has_unguarded_mu(m)
        })
    } else {
        baml.Array.filled(n, false)
    };
    let keep = baml.Array.filled(n, true);
    for (let i = 0; i < n; i += 1) {
        if (members[i] is NormalTyError || open[i]) {
            continue;
        }
        for (let j = 0; j < n; j += 1) {
            if (i == j || !keep[j] || members[j] is NormalTyError || open[j]) {
                continue;
            }
            if (!is_subtype_of(members[i], members[j], ctx, assumptions)) {
                continue;
            }
            // Drop `i`, unless the two are mutual subtypes; then keep the
            // lower index.
            let mutual = is_subtype_of(members[j], members[i], ctx, assumptions);
            if (!mutual || j < i) {
                keep[i] = false;
                break;
            }
        }
    }
    let out: NormalTy[] = [];
    for (let i = 0; i < n; i += 1) {
        if (keep[i]) {
            out.push(members[i]);
        }
    }
    out
}

// ═══════════════════════════════════════════════════════════════════════════
// μ-UNFOLDING & FUNCTION PARAMETERS
// ═══════════════════════════════════════════════════════════════════════════

// port: baml_type/src/normalize.rs::NormalTy::unfold @ d9be6853b
// One unfold of a closed canonical μ: `μX.body` to `body[μX.body/X]`. The
// replacement is closed, so no de Bruijn shifting is needed.
function unfold(t: NormalTy) -> NormalTy throws never {
    match (t) {
        let m: NormalTyMu => replace_rec_var(m.body, 0, t),
        _ => baml.sys.panic("unfold on a non-μ canonical form"),
    }
}

// port: baml_type/src/normalize.rs::NormalTy::has_free_rec_var @ d9be6853b
// Whether a RecVar with index >= `depth` (free relative to `depth` enclosing
// binders) occurs here.
function has_free_rec_var(t: NormalTy, depth: int) -> bool throws never {
    let go = (x: NormalTy) -> bool {
        has_free_rec_var(x, depth)
    };
    match (t) {
        let r: NormalTyRecVar => {
            match (r.var) {
                let i: int => i >= depth,
                _ => baml.sys.panic("has_free_rec_var on a named-phase RecVar"),
            }
        },
        let m: NormalTyMu => has_free_rec_var(m.body, depth + 1),
        let x: NormalTyList => go(x.elem),
        let x: NormalTyMap => go(x.key) || go(x.value),
        let x: NormalTyFuture => go(x.value) || go(x.error),
        let x: NormalTyUnion => x.members.some(go),
        let x: NormalTyTuple => x.items.some(go),
        let x: NormalTyClass => x.args.some(go),
        let x: NormalTyInterface => {
            x.args.some(go)
                || x.bindings.some((b) -> {
                    go(b.ty)
                })
        },
        let x: NormalTyFunction => {
            x.params.some((p) -> {
                go(p.ty)
            })
                || go(x.ret)
                || go(x.throws_)
        },
        let x: NormalTyAssociatedTypeProjection => go(x.base) || go(x.interface_),
        NormalTyLeaf => false,
    }
}

// port: baml_type/src/normalize.rs::NormalTy::replace_rec_var @ d9be6853b
// Replace every RecVar bound by the binder `depth` levels out with the
// (closed) `replacement`.
function replace_rec_var(t: NormalTy, depth: int, replacement: NormalTy) -> NormalTy throws never {
    let go = (x: NormalTy) -> NormalTy {
        replace_rec_var(x, depth, replacement)
    };
    match (t) {
        let r: NormalTyRecVar if r.var == depth => replacement,
        let m: NormalTyMu => {
            NormalTyMu { binder: m.binder, body: replace_rec_var(m.body, depth + 1, replacement) }
        },
        let x: NormalTyClass => NormalTyClass { name: x.name, args: x.args.map(go) },
        let x: NormalTyInterface => {
            NormalTyInterface {
                name: x.name,
                args: x.args.map(go),
                bindings: x.bindings.map((b) -> {
                    NormalBinding { name: b.name, ty: go(b.ty) }
                }),
            }
        },
        let x: NormalTyList => NormalTyList { elem: go(x.elem) },
        let x: NormalTyMap => NormalTyMap { key: go(x.key), value: go(x.value) },
        let x: NormalTyUnion => NormalTyUnion { members: x.members.map(go) },
        let x: NormalTyTuple => NormalTyTuple { items: x.items.map(go) },
        let x: NormalTyFunction => {
            NormalTyFunction {
                params: x.params.map((p) -> {
                    NormalParam { name: p.name, ty: go(p.ty), mode: p.mode }
                }),
                ret: go(x.ret),
                throws_: go(x.throws_),
            }
        },
        let x: NormalTyFuture => NormalTyFuture { value: go(x.value), error: go(x.error) },
        let x: NormalTyAssociatedTypeProjection => {
            NormalTyAssociatedTypeProjection {
                base: go(x.base),
                interface_: go(x.interface_),
                member: x.member,
            }
        },
        // Leaves and non-matching indices are untouched.
        let x: NormalTyRecVar | NormalTyLeaf => x,
    }
}

// port: baml_type/src/normalize.rs::NormalParam::list_subtype @ d9be6853b
// Parameter-list subtyping (contravariant): required params positional and
// matched in order, optional params matched by name.
function normal_param_list_subtype(
    sub: NormalParam[],
    sup: NormalParam[],
    ctx: TypeContext,
    assumptions: (NormalTy, NormalTy)[],
) -> bool throws never {
    let required = (ps: NormalParam[]) -> NormalParam[] {
        ps.filter((p) -> {
            p.mode == FunctionParamMode.Required
        })
    };
    let sub_required = required(sub);
    let sup_required = required(sup);
    if (sub_required.length() != sup_required.length()) {
        return false;
    }
    for (let k = 0; k < sub_required.length(); k += 1) {
        if (!is_subtype_of(sup_required[k].ty, sub_required[k].ty, ctx, assumptions)) {
            return false;
        }
    }
    for (let s in sup) {
        if (s.mode == FunctionParamMode.Required) {
            continue;
        }
        let name = s.name
            ?? return false;
        let p = sub.find((p) -> {
            p.mode != FunctionParamMode.Required && p.name == name
        })
            ?? return false;
        if (!is_subtype_of(s.ty, p.ty, ctx, assumptions)) {
            return false;
        }
    }
    true
}

// ═══════════════════════════════════════════════════════════════════════════
// INTERNED ENTRY
// ═══════════════════════════════════════════════════════════════════════════
//
// The inference engine's ingestion path: interned types enter the normalizer
// directly. Facts still exchange plain types at the TypeContext boundary;
// only a μ-rendering crosses through the plain form on the way out.

// port: baml_type/src/normalize.rs::ResolvedTy @ d9be6853b
class ResolvedTy {
    canonical: NormalTy?,
    normalized: ClosedTy?,
}

// port: baml_type/src/normalize.rs::InternedCanonicalCache @ d9be6853b
// Memoizes canonical forms and normalized spellings of interned types under
// one immutable TypeContext (the caller scopes one cache to one fact set).
// Keyed by handle.
class InternedCanonicalCache {
    resolved: map<int, ResolvedTy>,

    // port: baml_type/src/normalize.rs::InternedCanonicalCache::default @ d9be6853b
    function new() -> Self {
        InternedCanonicalCache { resolved: {} }
    }

    // port: baml_type/src/normalize.rs::InternedCanonicalCache::get_canonical @ d9be6853b
    function get_canonical(self, ty: ClosedTy) -> NormalTy? throws never {
        self.resolved.get(ty.ty)?.canonical
    }

    // port: baml_type/src/normalize.rs::InternedCanonicalCache::set_canonical @ d9be6853b
    function set_canonical(self, ty: ClosedTy, canonical: NormalTy) -> void throws never {
        let entry = self.resolved.get_or_insert(ty.ty, ResolvedTy { canonical: null, normalized: null });
        entry.canonical = canonical;
    }

    // port: baml_type/src/normalize.rs::InternedCanonicalCache::get_normalized @ d9be6853b
    function get_normalized(self, ty: ClosedTy) -> ClosedTy? throws never {
        self.resolved.get(ty.ty)?.normalized
    }

    // port: baml_type/src/normalize.rs::InternedCanonicalCache::set_normalized @ d9be6853b
    function set_normalized(self, ty: ClosedTy, normalized: ClosedTy) -> void throws never {
        let entry = self.resolved.get_or_insert(ty.ty, ResolvedTy { canonical: null, normalized: null });
        entry.normalized = normalized;
    }

    // port: baml_type/src/normalize.rs::InternedCanonicalCache::normalize @ d9be6853b
    // The cached normalize_interned spelling.
    function normalize(
        self,
        pool: InferPool,
        ty: ClosedTy,
        ctx: TypeContext,
    ) -> ClosedTy throws never {
        let cached = self.get_normalized(ty);
        if (cached != null) {
            return cached;
        }
        let normalized = normalize_interned(pool, ty, ctx);
        self.set_normalized(ty, normalized);
        normalized
    }

    // port: baml_type/src/normalize.rs::InternedCanonicalCache::canonical @ d9be6853b
    function canonical(
        self,
        pool: InferPool,
        ty: ClosedTy,
        ctx: TypeContext,
    ) -> NormalTy throws never {
        let cached = self.get_canonical(ty);
        if (cached != null) {
            return cached;
        }
        let canonical = canonical_interned(pool, ty, ctx);
        self.set_canonical(ty, canonical);
        canonical
    }

    // port: baml_type/src/normalize.rs::InternedCanonicalCache::equivalent @ d9be6853b
    function equivalent(
        self,
        pool: InferPool,
        a: ClosedTy,
        b: ClosedTy,
        ctx: TypeContext,
    ) -> bool throws never {
        if (a.ty == b.ty) {
            return true;
        }
        if (interned_heads_definitely_differ(pool, a.ty, b.ty)) {
            return false;
        }
        self.canonical(pool, a, ctx) == self.canonical(pool, b, ctx)
    }

    // port: baml_type/src/normalize.rs::InternedCanonicalCache::is_subtype @ d9be6853b
    function is_subtype(
        self,
        pool: InferPool,
        sub: ClosedTy,
        sup: ClosedTy,
        ctx: TypeContext,
    ) -> bool throws never {
        if (sub.ty == sup.ty) {
            return true;
        }
        let both_interfaces = pool.kinds[sub.ty] is InferTyInterface && pool.kinds[sup.ty] is InferTyInterface;
        if (!both_interfaces && interned_heads_definitely_differ(pool, sub.ty, sup.ty)) {
            return false;
        }
        is_subtype_of(self.canonical(pool, sub, ctx), self.canonical(pool, sup, ctx), ctx, [])
    }
}

// port: baml_type/src/normalize.rs::NormalTy::canonical_bottom_up_interned @ d9be6853b
// canonical_bottom_up entered from an interned type.
function canonical_bottom_up_interned(
    pool: InferPool,
    ty: ClosedTy,
    ctx: TypeContext,
) -> (NormalTy, bool) throws never {
    let named = from_interned(pool, ty.ty, ctx, {}, PROJECTION_REDUCTION_FUEL);
    let saw_mu = SawMu { value: false };
    let resolved = resolve_binders(named, [], saw_mu);
    (canonicalize(resolved, ctx, saw_mu.value, []), saw_mu.value)
}

// port: baml_type/src/normalize.rs::NormalTy::canonical_interned @ d9be6853b
// canonical for the interned representation.
function canonical_interned(
    pool: InferPool,
    ty: ClosedTy,
    ctx: TypeContext,
) -> NormalTy throws never {
    let (let t, let saw_mu) = canonical_bottom_up_interned(pool, ty, ctx);
    if (saw_mu && contains_mu(t)) {
        root.types.normalize.canonicalize_mu(t, ctx)
    } else {
        t
    }
}

// port: baml_type/src/normalize.rs::NormalTy::into_interned @ d9be6853b
// into_ty for the interned representation: interns each node directly. A μ
// interns from its display, the one plain crossing left.
function into_interned(pool: InferPool, t: NormalTy) -> int throws never {
    let go = (x: NormalTy) -> int {
        into_interned(pool, x)
    };
    let kind: InferTy = match (t) {
        NormalTyInt => TyInt {},
        NormalTyBigint => TyBigint {},
        NormalTyFloat => TyFloat {},
        NormalTyString => TyString {},
        NormalTyBool => TyBool {},
        NormalTyNull => TyNull {},
        NormalTyUint8Array => TyUint8Array {},
        let m: NormalTyMedia => TyMedia { kind: m.kind },
        NormalTyRustType => TyRustType {},
        NormalTyType => TyType {},
        NormalTyResource => TyResource {},
        NormalTyPromptAst => TyPromptAst {},
        NormalTyUnknown => TyUnknown {},
        NormalTyNever => TyNever {},
        NormalTyError => TyError {},
        let l: NormalTyLiteral => TyLiteral { value: l.value, freshness: Freshness.Regular },
        let c: NormalTyClass => InferTyClass { name: c.name, args: c.args.map(go) },
        let i: NormalTyInterface => {
            InferTyInterface {
                name: i.name,
                args: i.args.map(go),
                associated_types: i.bindings.map((b) -> {
                    InferAssociatedType { name: b.name, ty: go(b.ty) }
                }),
            }
        },
        let e: NormalTyEnum => TyEnum { name: e.name },
        let v: NormalTyEnumVariant => TyEnumVariant { name: v.name, variant: v.variant },
        let l: NormalTyList => InferTyList { elem: go(l.elem) },
        let m: NormalTyMap => InferTyMap { key: go(m.key), value: go(m.value) },
        let u: NormalTyUnion => InferTyUnion { members: u.members.map(go) },
        let x: NormalTyTuple => InferTyTuple { items: x.items.map(go) },
        let f: NormalTyFunction => {
            InferTyFunction {
                params: f.params.map((p) -> {
                    InferFunctionParamTy { name: p.name, ty: go(p.ty), mode: p.mode }
                }),
                ret: go(f.ret),
                throws_: go(f.throws_),
            }
        },
        let f: NormalTyFuture => InferTyFuture { value: go(f.value), error: go(f.error) },
        let p: NormalTyAssociatedTypeProjection => {
            InferTyAssociatedTypeProjection {
                base: go(p.base),
                // Same contract as into_ty's projection arm.
                interface_: into_infer_interface(pool, p.interface_)
                    ?? baml.sys.panic("projection qualifier is an interface"),
                member: p.member,
            }
        },
        let v: NormalTyTypeVar => TyTypeVar { param: v.param },
        let m: NormalTyMu => {
            return pool.from_plain(mu_display(m).rendered);
        },
        NormalTyRecVar => {
            baml.sys.panic(
                "into_interned on a free RecVar; canonical forms at public boundaries are closed and render recursion via their binder's display",
            )
        },
        let o: NormalTyOpaqueAlias => TyTypeAlias { name: o.name },
    };
    pool.add(kind)
}

// port: baml_type/src/normalize.rs::NormalTy::into_infer_interface @ d9be6853b
// into_interface for the interned representation, with the same μ-display
// recovery and null degradation.
function into_infer_interface(
    pool: InferPool,
    t: NormalTy,
) -> InferInterfaceConstraint? throws never {
    match (t) {
        let i: NormalTyInterface => {
            infer_interface_new(
                i.name,
                i.args.map((a) -> {
                    into_interned(pool, a)
                }),
                i.bindings.map((b) -> {
                    InferAssociatedType { name: b.name, ty: into_interned(pool, b.ty) }
                }),
            )
        },
        let m: NormalTyMu => {
            match (mu_display(m).rendered) {
                let i: TyInterface => {
                    infer_interface_new(
                        i.name,
                        i.args.map((a) -> {
                            pool.from_plain(a)
                        }),
                        i.associated_types.map((b) -> {
                            InferAssociatedType { name: b.name, ty: pool.from_plain(b.ty) }
                        }),
                    )
                },
                _ => null,
            }
        },
        _ => null,
    }
}

// port: baml_type/src/normalize.rs::NormalTy::from_interned @ d9be6853b
// from_ty mirrored over the interned kind. An alias definition and a
// projection reduction are plain facts, so their expansions continue through
// from_ty.
function from_interned(
    pool: InferPool,
    ty: int,
    ctx: TypeContext,
    expanding: map<DeclName, bool>,
    fuel: int,
) -> NormalTy throws never {
    let go = (t: int) -> NormalTy {
        from_interned(pool, t, ctx, expanding, fuel)
    };
    let bindings = (associated_types: InferAssociatedType[]) -> NormalBinding[] {
        associated_types
            .map((b) -> {
                NormalBinding { name: b.name, ty: go(b.ty) }
            })
            .sort_by((a, b) -> {
                a.name.cmp(b.name)
            })
    };
    match (pool.kinds[ty]) {
        TyInt => NormalTyInt {},
        TyBigint => NormalTyBigint {},
        TyFloat => NormalTyFloat {},
        TyString => NormalTyString {},
        TyBool => NormalTyBool {},
        TyNull => NormalTyNull {},
        TyUint8Array => NormalTyUint8Array {},
        let m: TyMedia => NormalTyMedia { kind: m.kind },
        TyRustType => NormalTyRustType {},
        TyType => NormalTyType {},
        TyResource => NormalTyResource {},
        TyPromptAst => NormalTyPromptAst {},
        TyUnknown => NormalTyUnknown {},
        TyNever => NormalTyNever {},
        TyError => NormalTyError {},
        // Unreachable by the ClosedTy invariant of every interned entry.
        TyInferVar => baml.sys.panic("ClosedTy invariant: no live inference variables"),
        let l: TyLiteral => NormalTyLiteral { value: l.value },
        let c: InferTyClass => NormalTyClass { name: c.name, args: c.args.map(go) },
        let i: InferTyInterface => {
            let bs = bindings(i.associated_types);
            NormalTyInterface { name: i.name, args: i.args.map(go), bindings: bs }
        },
        let e: TyEnum => NormalTyEnum { name: e.name },
        let v: TyEnumVariant => NormalTyEnumVariant { name: v.name, variant: v.variant },
        let l: InferTyList => NormalTyList { elem: go(l.elem) },
        let m: InferTyMap => NormalTyMap { key: go(m.key), value: go(m.value) },
        let u: InferTyUnion => NormalTyUnion { members: u.members.map(go) },
        let x: InferTyTuple => NormalTyTuple { items: x.items.map(go) },
        let f: InferTyFunction => {
            NormalTyFunction {
                params: f.params.map((p) -> {
                    NormalParam { name: p.name, ty: go(p.ty), mode: p.mode }
                }),
                ret: go(f.ret),
                throws_: go(f.throws_),
            }
        },
        let f: InferTyFuture => NormalTyFuture { value: go(f.value), error: go(f.error) },
        let v: TyTypeVar => NormalTyTypeVar { param: v.param },
        let p: InferTyAssociatedTypeProjection => {
            // The fact boundary exchanges plain types; a projection's pieces
            // are small. An open piece here is a compiler bug.
            let closed = (t: int) -> Ty {
                let c = ClosedTy.try_from(pool, t) catch (e) {
                    OpenTy => {
                        baml.sys.panic(
                            "inference variable reached type normalization inside a projection",
                        )
                    },
                };
                pool.to_plain_closed(c.ty)
            };
            let plain_base = closed(p.base);
            let plain_interface = InterfaceConstraint {
                name: p.interface_.name,
                generics: p.interface_.generics.map(closed),
                associated_types: p.interface_.associated_types
                    .map((b) -> {
                        AssociatedType { name: b.name, ty: closed(b.ty) }
                    })
                    .sort_by((a, b) -> {
                        a.name.cmp(b.name)
                    }),
            };
            if (fuel > 0) {
                if let r: ProjectionStepReduced = ctx.project(plain_base, plain_interface, p.member, fuel) {
                    return from_ty(r.ty, ctx, expanding, fuel - 1);
                }
            }
            let bs = bindings(p.interface_.associated_types);
            NormalTyAssociatedTypeProjection {
                base: go(p.base),
                interface_: NormalTyInterface {
                    name: p.interface_.name,
                    args: p.interface_.generics.map(go),
                    bindings: bs,
                },
                member: p.member,
            }
        },
        let a: TyTypeAlias => {
            if (expanding.has(a.name)) {
                return NormalTyRecVar { var: a.name };
            }
            let def = ctx.alias_def(a.name)
                ?? return NormalTyOpaqueAlias { name: a.name };
            expanding.set(a.name, true);
            // The alias definition is a plain fact; its expansion continues
            // through the plain path.
            let body = from_ty(def, ctx, expanding, fuel);
            expanding.delete(a.name);
            if (mentions_rec_var(body, a.name)) {
                NormalTyMu { binder: a.name, body: body }
            } else {
                body
            }
        },
    }
}

// port: baml_type/src/normalize.rs::is_subtype_interned @ d9be6853b
// TypeContext.is_subtype for interned types. Handle identity is the
// reflexivity fast path.
function is_subtype_interned(
    pool: InferPool,
    sub: ClosedTy,
    sup: ClosedTy,
    ctx: TypeContext,
) -> bool throws never {
    if (sub.ty == sup.ty) {
        return true;
    }
    let both_interfaces = pool.kinds[sub.ty] is InferTyInterface && pool.kinds[sup.ty] is InferTyInterface;
    if (!both_interfaces && interned_heads_definitely_differ(pool, sub.ty, sup.ty)) {
        return false;
    }
    let sub_n = canonical_interned(pool, sub, ctx);
    let sup_n = canonical_interned(pool, sup, ctx);
    is_subtype_of(sub_n, sup_n, ctx, [])
}

// port: baml_type/src/normalize.rs::equivalent_interned @ d9be6853b
// TypeContext.equivalent for interned types.
function equivalent_interned(
    pool: InferPool,
    a: ClosedTy,
    b: ClosedTy,
    ctx: TypeContext,
) -> bool throws never {
    if (a.ty == b.ty) {
        return true;
    }
    if (interned_heads_definitely_differ(pool, a.ty, b.ty)) {
        return false;
    }
    canonical_interned(pool, a, ctx) == canonical_interned(pool, b, ctx)
}

// port: baml_type/src/normalize.rs::interned_heads_definitely_differ @ d9be6853b
// heads_definitely_differ for interned types.
function interned_heads_definitely_differ(pool: InferPool, a: int, b: int) -> bool throws never {
    let ka = pool.kinds[a];
    let kb = pool.kinds[b];
    match (ka, kb) {
        (let x: InferTyClass, let y: InferTyClass) => x.name != y.name,
        (let x: InferTyInterface, let y: InferTyInterface) => x.name != y.name,
        (let x: TyEnum, let y: TyEnum) => x.name != y.name,
        (let x: TyEnumVariant, let y: TyEnumVariant) => x.name != y.name || x.variant != y.variant,
        _ => categories_differ(category_of_interned_head(ka), category_of_interned_head(kb)),
    }
}

// port: baml_type/src/normalize.rs::normalize_interned @ d9be6853b
// TypeContext.normalize for interned types, interning the canonical form
// directly; a μ root renders as canonical_render does (root-unfold-once).
function normalize_interned(
    pool: InferPool,
    ty: ClosedTy,
    ctx: TypeContext,
) -> ClosedTy throws never {
    let (let t, let saw_mu) = canonical_bottom_up_interned(pool, ty, ctx);
    if (saw_mu && contains_mu(t)) {
        ClosedTy { ty: pool.from_plain(root.types.normalize.canonicalize_mu_with_render(t, ctx).1) }
    } else {
        ClosedTy { ty: into_interned(pool, t) }
    }
}

// port: baml_type/src/normalize.rs::canonical_union_interned @ d9be6853b
// The canonical union of `members`: the join for control-flow merges and
// throws accumulation. An empty list is `never` (the join identity).
function canonical_union_interned(
    pool: InferPool,
    members: ClosedTy[],
    ctx: TypeContext,
) -> ClosedTy throws never {
    let named = NormalTyUnion {
        members: members.map((m) -> {
            from_interned(pool, m.ty, ctx, {}, PROJECTION_REDUCTION_FUEL)
        }),
    };
    let saw_mu = SawMu { value: false };
    let resolved = resolve_binders(named, [], saw_mu);
    let t = canonicalize(resolved, ctx, saw_mu.value, []);
    let out = if (saw_mu.value && contains_mu(t)) {
        root.types.normalize.canonicalize_mu(t, ctx)
    } else {
        t
    };
    ClosedTy { ty: into_interned(pool, out) }
}
