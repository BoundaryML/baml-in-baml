// port: baml_type/src/lib.rs @ d9be6853b
//
// `impl Ty` methods are free functions under their Rust names. The
// hand-mirrored `impl LoweringTy` twins of a `Ty` method take the family's
// `_lowering_ty` suffix (`optional_lowering_ty`). The renderer lives on
// LoweringTy, as in Rust; a Ty renders through its upcast,
// `render_with(widen_ty_to_lowering_ty(t), s)`.
//
// Not ported:
// - `Freshness` and `FunctionParamMode`: in family_support.baml.
// - `MAX_BIGINT_BITS`: `root.base.MAX_BIGINT_BITS`. `MAX_BIGINT_DECIMAL_DIGITS`
//   serves SAP, jsonish and `bigint.parse` only.
// - The one-line constructors (`Ty::never`, `error`, `int`, `float`,
//   `string`, `bool`, `null`, `uint8array`, `list`, `tuple`, `union`,
//   `unknown`, `resource`, `prompt_ast`, `type_type`, `type_var` and the
//   LoweringTy set): write the variant (`TyList { elem: t }`).
// - One-line predicates over a walk: `Ty::is_null` and `LoweringTy::is_null`
//   (`t is TyNull`), `contains_error` (`contains_ty_where(t, (n) -> { n is
//   TyError })`), `LoweringTy::contains_hole` / `contains_error`
//   (`any_node(t, (n) -> { n is TyInfer })`), `Ty::render_with` (the upcast
//   above).
// - `HeadDisplay`, both `impl Display`s and `fmt_as_postfix_base` /
//   `fmt_as_function_result`: Rust implements `HeadDisplay` for wire and
//   runtime heads only and keeps it off `DeclName` on purpose, so that a
//   compiler type cannot be rendered without a viewpoint. Every family member
//   here is `DeclName`-headed; compiler code renders through `render_with`
//   and a viewpoint strategy.
// - `CanonicalTyRender`, `render_canonical`, `render_user_facing`,
//   `Ty::class`, `Ty::user_class_with_args`: `TypeName`-headed only, and no
//   family member is `TypeName`-headed.

// port: baml_type/src/lib.rs::TypeName @ d9be6853b
// The wire's qualified name: a declaration by the spelling an artifact gives
// its package. The compiler's counterpart is DeclName.
type TypeName = QualifiedTypeName<Package>;

// port: baml_type/src/lib.rs::dedup_and_collapse @ d9be6853b
// Flatten, deduplicate and collapse widened types into one: after
// widen_fresh several members may have widened to the same primitive, which
// flat_union then spells once.
function dedup_and_collapse(types: Ty[]) -> Ty throws never {
    flat_union(
        types,
        (ty: Ty) -> Ty[]? {
            match (ty) {
                let u: TyUnion => u.members,
                _ => null,
            }
        },
        TyNever {},
        (members: Ty[]) -> Ty {
            TyUnion { members: members }
        },
    )
}

// port: baml_type/src/lib.rs::flat_union @ d9be6853b
// The union of `members`, spelled flat and without repeats, in any member of
// the family: a nested union (`as_union`) is spliced in place, a member
// structurally equal to an earlier one is dropped, a single member stands for
// itself, and no members is `never_`. Only associativity and idempotence are
// applied, never commutativity: each member keeps the position of its first
// occurrence, since SAP reads a union's declared order.
// Restructured: Rust's `as_union` returns `Err(member)` for a non-union; here
// it returns null.
function flat_union<T>(members: T[], as_union: (T) -> T[]?, never_: T, union_: (T[]) -> T) -> T {
    let out: T[] = [];
    splice(members, as_union, out);
    match (out.length()) {
        0 => never_,
        1 => out[0],
        _ => union_(out),
    }
}

// port: baml_type/src/lib.rs::flat_union::splice @ d9be6853b
// flat_union's inner function: appends `members` to `out`, splicing nested
// unions and skipping repeats.
function splice<T>(members: T[], as_union: (T) -> T[]?, out: T[]) -> void {
    for (let member in members) {
        let nested = as_union(member);
        if (nested != null) {
            splice(nested, as_union, out);
        } else if (!out.includes(member)) {
            out.push(member);
        }
    }
}

// port: baml_type/src/lib.rs::contains_ty_where @ d9be6853b
// Does `pred` hold for `ty` or any type nested inside it?
function contains_ty_where(ty: Ty, pred: (Ty) -> bool) -> bool {
    pred(ty)
        || children_ty(ty).some((child) -> {
            contains_ty_where(child, pred)
        })
}

// port: baml_type/src/lib.rs::Ty::is_valid_impl_subject @ d9be6853b
// Whether this type may be the implementor (`for`-target) of an interface
// implementation. Valid: concrete user-facing types with one runtime
// representation dispatch can key on (primitives, media, classes, enums,
// lists, maps, the builtin handles), a blanket type parameter or its
// projection, and `never` (vacuously). Rejected: `Future` (not implemented
// yet, not a limitation), literal types (they dispatch through their base),
// existentials and unions (no single implementor), function types and
// `RustType`, `unknown`, the error sentinel, and a surviving (unresolved)
// alias. Exhaustive so a new variant must be classified here.
function is_valid_impl_subject(ty: Ty) -> bool throws never {
    match (ty) {
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyClass
            | TyEnum
            | TyList
            | TyMap
            | TyType
            | TyResource
            | TyPromptAst
            | TyNever
            | TyTypeVar
            | TyAssociatedTypeProjection =>
        {
            true
        },
        TyTuple
            | TyLiteral
            | TyEnumVariant
            | TyInterface
            | TyUnion
            | TyFuture
            | TyFunction
            | TyRustType
            | TyTypeAlias
            | TyUnknown
            | TyError =>
        {
            false
        },
    }
}

// port: baml_type/src/lib.rs::Ty::is_concrete @ d9be6853b
// Whether this is a concrete type per the TYPE_SYSTEM.md taxonomy: every
// value has exactly one run-time representation method dispatch can key on.
// Not concrete: unions and existentials, `unknown`, literal types, `never`,
// type variables and projections (their concreteness is an obligation on
// their bound), unresolved aliases and the error sentinel. Distinct from
// is_valid_impl_subject, which asks whether a written impl may target the
// type. Exhaustive so a new variant must be classified here.
function is_concrete(ty: Ty) -> bool throws never {
    match (ty) {
        TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyClass
            | TyEnum
            | TyList
            | TyMap
            | TyTuple
            | TyFunction
            | TyFuture
            | TyType
            | TyResource
            | TyPromptAst
            | TyRustType =>
        {
            true
        },
        TyUnion
            | TyInterface
            | TyUnknown
            | TyLiteral
            | TyEnumVariant
            | TyNever
            | TyTypeVar
            | TyAssociatedTypeProjection
            | TyTypeAlias
            | TyError =>
        {
            false
        },
    }
}

// port: baml_type/src/lib.rs::Ty::from_primitive @ d9be6853b
function from_primitive(primitive: PrimitiveType) -> Ty throws never {
    match (primitive) {
        PrimitiveType.Int => TyInt {},
        PrimitiveType.Bigint => TyBigint {},
        PrimitiveType.Float => TyFloat {},
        PrimitiveType.String => TyString {},
        PrimitiveType.Bool => TyBool {},
        PrimitiveType.Null => TyNull {},
        PrimitiveType.Uint8Array => TyUint8Array {},
        PrimitiveType.Image => TyMedia { kind: root.base.MediaKind.Image },
        PrimitiveType.Audio => TyMedia { kind: root.base.MediaKind.Audio },
        PrimitiveType.Video => TyMedia { kind: root.base.MediaKind.Video },
        PrimitiveType.Pdf => TyMedia { kind: root.base.MediaKind.Pdf },
    }
}

// port: baml_type/src/lib.rs::Ty::optional @ d9be6853b
// `T?`, sugar for `T | null`: flattened and idempotent. `(A | B)?` is a flat
// `A | B | null`, `T??` stays `T?`, and `null?` is `null`.
function optional(inner: Ty) -> Ty throws never {
    match (inner) {
        let u: TyUnion => {
            if (
                u.members.some((m) -> {
                    m is TyNull
                })
            ) {
                u
            } else {
                TyUnion { members: u.members.concat([TyNull {}]) }
            }
        },
        let n: TyNull => n,
        _ => TyUnion { members: [inner, TyNull {}] },
    }
}

// port: baml_type/src/lib.rs::Ty::is_nullable_union @ d9be6853b
// True for a union that includes `null`: an optional after `?` lowering.
// The canonical "is this nullable" predicate.
function is_nullable_union(ty: Ty) -> bool throws never {
    match (ty) {
        let u: TyUnion => {
            u.members.some((m) -> {
                m is TyNull
            })
        },
        _ => false,
    }
}

// port: baml_type/src/lib.rs::Ty::strip_null @ d9be6853b
// Remove `null` from a nullable union, collapsing the result: `T | null` is
// `T`, `A | B | null` is `A | B`, a non-nullable type (and an all-null union)
// is unchanged. The inverse of `optional`.
function strip_null(ty: Ty) -> Ty throws never {
    match (ty) {
        let u: TyUnion => {
            let non_null = u.members.filter((m) -> {
                !(m is TyNull)
            });
            match (non_null.length()) {
                0 => ty,
                1 => non_null[0],
                _ => TyUnion { members: non_null },
            }
        },
        _ => ty,
    }
}

// port: baml_type/src/lib.rs::Ty::remove_null @ d9be6853b
// Remove `null` from this type: `T?` gives `T`, a union drops its null member
// (a single survivor collapses), bare `null` gives `never`, everything else
// passes through unchanged.
function remove_null(ty: Ty) -> Ty throws never {
    match (ty) {
        let u: TyUnion => {
            let filtered = u.members.filter((m) -> {
                !(m is TyNull)
            });
            match (filtered.length()) {
                0 => TyNever {},
                1 => filtered[0],
                _ => TyUnion { members: filtered },
            }
        },
        TyNull => TyNever {},
        _ => ty,
    }
}

// port: baml_type/src/lib.rs::Ty::widen_fresh @ d9be6853b
// Widen fresh literal types to their base primitive, at mutable binding sites
// (`let` without annotation). Regular literals pass through. Recurses into
// unions, lists, maps, class arguments and tuples, so `(1 | 2 | 3)[]` widens
// to `int[]`.
function widen_fresh(ty: Ty) -> Ty throws never {
    match (ty) {
        let l: TyLiteral if l.freshness == Freshness.Fresh => {
            from_primitive(primitive_type_from_literal(l.value))
        },
        let u: TyUnion => dedup_and_collapse(u.members.map(widen_fresh)),
        let l: TyList => TyList { elem: widen_fresh(l.elem) },
        let m: TyMap => TyMap { key: widen_fresh(m.key), value: widen_fresh(m.value) },
        let c: TyClass => TyClass { name: c.name, args: c.args.map(widen_fresh) },
        let t: TyTuple => TyTuple { items: t.items.map(widen_fresh) },
        _ => ty,
    }
}

// port: baml_type/src/lib.rs::Ty::as_interface @ d9be6853b
// This type as an interface constraint when it is an interface existential;
// null for any other type. Rust builds it with `Interface::new`, which sorts
// the associated-type bindings by name; the sort is inlined here.
function as_interface(ty: Ty) -> InterfaceConstraint? throws never {
    match (ty) {
        let i: TyInterface => {
            InterfaceConstraint {
                name: i.name,
                generics: i.args,
                associated_types: i.associated_types.slice(0, i.associated_types.length()).sort_by_key((binding) -> {
                    binding.name
                }),
            }
        },
        _ => null,
    }
}

// port: baml_type/src/lib.rs::LoweringTy::optional @ d9be6853b
// `T?` on a written type; mirrors `optional`.
function optional_lowering_ty(inner: LoweringTy) -> LoweringTy throws never {
    match (inner) {
        let u: LoweringTyUnion => {
            if (
                u.members.some((m) -> {
                    m is TyNull
                })
            ) {
                u
            } else {
                LoweringTyUnion { members: u.members.concat([TyNull {}]) }
            }
        },
        let n: TyNull => n,
        _ => LoweringTyUnion { members: [inner, TyNull {}] },
    }
}

// port: baml_type/src/lib.rs::LoweringTy::any_node @ d9be6853b
// Deep node predicate: does any node in this tree satisfy `pred`?
// Restructured: Rust hand-writes the traversal "until the macro generates
// per-member child visitors"; the generated `children_lowering_ty` visits the
// same children.
function any_node(ty: LoweringTy, pred: (LoweringTy) -> bool) -> bool {
    pred(ty)
        || children_lowering_ty(ty).some((child) -> {
            any_node(child, pred)
        })
}

// port: baml_type/src/lib.rs::LoweringTy::needs_postfix_parens @ d9be6853b
function needs_postfix_parens(ty: LoweringTy) -> bool throws never {
    ty is LoweringTyUnion || ty is LoweringTyFunction
}

// port: baml_type/src/lib.rs::LoweringTy::needs_function_result_parens @ d9be6853b
function needs_function_result_parens(ty: LoweringTy) -> bool throws never {
    ty is LoweringTyFunction
}

// port: baml_type/src/lib.rs::render_tuple @ d9be6853b
// A one-element tuple keeps its trailing comma: `(int,)`.
function render_tuple(elements: string[]) -> string throws never {
    if (elements.length() == 1) {
        `(${elements[0]},)`
    } else {
        `(${elements.join(", ")})`
    }
}

// port: baml_type/src/lib.rs::TyRenderStrategy @ d9be6853b
// How a type renders its leaf names. render_with walks the structure;
// everything package-, type-var- or context-specific lives behind this
// interface. The canonical dump renderer, user-facing diagnostics and hover
// all implement it instead of re-walking the type. Rust's head parameter `N`
// is DeclName, the only head here.
interface TyRenderStrategy {
    // A head's dotted path (package/namespace/name) without any `<...>`
    // suffix; the renderer appends type arguments.
    function qtn(self, qtn: DeclName) -> string throws never;

    // A type-variable name (`T`, or a synthetic effect param).
    function type_var(self, name: string) -> string throws never;
}

// port: baml_type/src/lib.rs::LoweringTy::render_as_postfix_base @ d9be6853b
// Render with parentheses if needed in postfix (`[]`/`?`) context.
function render_as_postfix_base(ty: LoweringTy, s: TyRenderStrategy) -> string throws never {
    let inner = render_with(ty, s);
    if (needs_postfix_parens(ty)) {
        `(${inner})`
    } else {
        inner
    }
}

// port: baml_type/src/lib.rs::LoweringTy::render_as_function_result @ d9be6853b
// Render with parentheses if needed in a function-return position.
function render_as_function_result(ty: LoweringTy, s: TyRenderStrategy) -> string throws never {
    let inner = render_with(ty, s);
    if (needs_function_result_parens(ty)) {
        `(${inner})`
    } else {
        inner
    }
}

// port: baml_type/src/lib.rs::LoweringTy::render_with @ d9be6853b
// The single structural renderer: walks the type, delegating every package-,
// type-var- and presentation-policy decision to `s`.
// Restructured: a projection renders its constraint as the existential Rust's
// `Interface::to_ty` builds (`LoweringTyInterface` with the constraint's
// generics and bindings), written inline.
function render_with(ty: LoweringTy, s: TyRenderStrategy) -> string throws never {
    let render = (t: LoweringTy) -> string {
        render_with(t, s)
    };
    match (ty) {
        let c: LoweringTyClass => {
            if (c.args.length() == 0) {
                s.qtn(c.name)
            } else {
                `${s.qtn(c.name)}<${c.args.map(render).join(", ")}>`
            }
        },
        let i: LoweringTyInterface => {
            let args = i.args.map(render).concat(
                i.associated_types.map((binding) -> {
                    `${binding.name} = ${render(binding.ty)}`
                }),
            );
            if (args.length() == 0) {
                s.qtn(i.name)
            } else {
                `${s.qtn(i.name)}<${args.join(", ")}>`
            }
        },
        let e: TyEnum => s.qtn(e.name),
        let a: TyTypeAlias => s.qtn(a.name),
        let v: TyEnumVariant => `${s.qtn(v.name)}.${v.variant}`,
        TyInt => primitive_type_alias(PrimitiveType.Int),
        TyBigint => primitive_type_alias(PrimitiveType.Bigint),
        TyFloat => primitive_type_alias(PrimitiveType.Float),
        TyString => primitive_type_alias(PrimitiveType.String),
        TyBool => primitive_type_alias(PrimitiveType.Bool),
        TyNull => primitive_type_alias(PrimitiveType.Null),
        TyUint8Array => primitive_type_alias(PrimitiveType.Uint8Array),
        let m: TyMedia => root.base.media_kind_display(m.kind),
        let l: LoweringTyList => `${render_as_postfix_base(l.elem, s)}[]`,
        let m: LoweringTyMap => `map<${render(m.key)}, ${render(m.value)}>`,
        // `?` is sugar that exists only in source/lowering; after that a
        // nullable type is a plain union and renders as `T | null`. Function
        // members are parenthesized so a nullable callback reads as
        // `((..) -> ..) | null`, not a function with `throws .. | null`.
        let u: LoweringTyUnion => {
            u.members
                .map((member) -> {
                    let rendered = render(member);
                    if (member is LoweringTyFunction) {
                        `(${rendered})`
                    } else {
                        rendered
                    }
                })
                .join(" | ")
        },
        let t: LoweringTyTuple => render_tuple(t.items.map(render)),
        let l: TyLiteral => root.base.literal_display(l.value),
        let f: LoweringTyFunction => {
            let params = f.params.map((param) -> {
                let rendered = render(param.ty);
                let name = param.name;
                if (name == null) {
                    rendered
                } else if (param.mode == FunctionParamMode.Optional) {
                    `${name}?: ${rendered}`
                } else {
                    `${name}: ${rendered}`
                }
            });
            `(${params.join(", ")}) -> ${render_as_function_result(f.ret, s)} throws ${render(f.throws_)}`
        },
        let v: TyTypeVar => s.type_var(v.param.name),
        let p: LoweringTyAssociatedTypeProjection => {
            let constraint = LoweringTyInterface {
                name: p.interface_.name,
                args: p.interface_.generics,
                associated_types: p.interface_.associated_types,
            };
            `(${render(p.base)} as ${render(constraint)}).${p.member}`
        },
        TyNever => "never",
        TyUnknown => "unknown",
        TyRustType => "$rust_type",
        TyType => "reflect.Type",
        // Opaque leaf types render as their fixed qualified names; these
        // strings feed canonical dumps and must stay byte-identical.
        TyResource => "ai.Resource",
        TyPromptAst => "ai.Prompt",
        TyError => "!error",
        // The written inference hole renders as written.
        TyInfer => "_",
        // The writable spelling: bare `Future` resolves nowhere, the class
        // lives in `baml.future`.
        let f: LoweringTyFuture => `baml.future.Future<${render(f.value)}, ${render(f.error)}>`,
    }
}

// port: baml_type/src/lib.rs::Interface::tys @ d9be6853b
// Every type the constraint carries: its generic arguments, then the type of
// each associated-type binding (not the names).
function tys(constraint: InterfaceConstraint) -> Ty[] throws never {
    constraint.generics.concat(
        constraint.associated_types.map((binding) -> {
            binding.ty
        }),
    )
}

// port: baml_type/src/lib.rs::Interface::map_tys @ d9be6853b
// The constraint with every carried type (generics and binding types) mapped
// through `f`; the name and binding names are kept. Rust routes through
// `Interface::new` so the bindings come out sorted by name; the sort is
// inlined here.
function map_tys(constraint: InterfaceConstraint, f: (Ty) -> Ty) -> InterfaceConstraint {
    InterfaceConstraint {
        name: constraint.name,
        generics: constraint.generics.map(f),
        associated_types: constraint.associated_types
            .map((binding) -> {
                AssociatedType { name: binding.name, ty: f(binding.ty) }
            })
            .sort_by_key((binding) -> {
                binding.name
            }),
    }
}
