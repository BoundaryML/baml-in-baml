// port: baml_compiler2_hir_ty/src/exhaustiveness.rs @ d9be6853b
//
// Pattern exhaustiveness, irrefutability, and witness construction: a reduced
// port of rustc's `rustc_pattern_analysis`. `Ctor` is the head of a
// deconstructed pattern, `DPat` a pattern in deconstructed form, `Matrix` a
// grid of `DPat`s (rows are arms, columns positions). The usefulness
// recursion specializes the matrix on each ctor of the leading column;
// missing cases come back as `WitnessPat`s. The type system is reached only
// through the `PatCtx` interface.
//
// Restructured:
// - `Ctor` and `SliceShape` are unions of classes; their methods are free
//   functions (`ctor_arity`, `ctor_covers`, `slice_shape_arity`).
// - `Ctor`'s custom `PartialEq` + `Hash` are one function, `ctor_hash`: the
//   identity key a ctor is hashed and compared by (two ctors are equal iff
//   their keys are). `FxHashSet<Ctor>` is `map<string, bool>` over it, and
//   `class_args_identity_eq` (only the `PartialEq` impl used it) is folded in.
// - `FxHashSet<DeclName>` (`is_inhabited_default`'s cycle guard) is keyed by
//   `decl_name_ctor_identity`; `FxHashSet<ArmId>` by the arm index.
// - `ty_ctor_identity` is ported for compile-time `Ty` only (heads are
//   `DeclName`); the `CtorHead` trait is `decl_name_ctor_identity`, and its
//   `TypeName` impl (wire heads) is not ported. Identity strings are never
//   shown, only compared: a root is keyed by its id, a float literal by its
//   parsed value's canonical spelling instead of its bit pattern.
// - `write!` into a `String` / `fmt::Result` helpers return the text, or
//   push pieces onto a `string[]` joined at the end.
// - Borrowed rows (`Vec<&DPat>`) are arrays of `DPat` references; no row or
//   pattern is mutated after it is built, so sharing is safe.
// - Not ported (trivial accessors or constructors, written inline):
//   `Matrix::col_count` / `first_col_ty` (read `col_tys`),
//   `WitnessStack::push`, `WitnessMatrix::empty` / `unit` / `extend`.

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::Ctor @ d9be6853b
// The head of a pattern. Determines arity (number of sub-pattern slots) and
// the coverage relation against other ctors at the same column type.
type Ctor = CtorType
    | CtorSlice
    | CtorClass
    | CtorInterface
    | CtorTuple
    | CtorUnionMember
    | CtorOr
    | CtorWildcard
    | CtorNonExhaustive
    | CtorMissing;

// Every value of the carried type. Identity is `ty_ctor_identity`, which
// strips `Freshness` and canonicalizes float literals. Singleton types are
// the one-value case; a wider type (`int`, a rigid type variable) appears
// where the column's alphabet cannot be listed.
class CtorType {
    value: root.types.Ty,
}

// Array shape. Sub-patterns' types come from the array's element type.
class CtorSlice {
    value: SliceShape,
}

// Class destructure. Sub-patterns' types come from the class's fields, with
// generic substitution applied.
class CtorClass {
    name: root.types.DeclName,
    args: root.types.Ty[],
}

// Interface destructure. Sub-patterns' types come from the interface's field
// view, with generic substitution applied.
class CtorInterface {
    value: root.types.Ty,
}

class CtorTuple {
    value: int,
}

// "Which member of a union" tag, with arity 1. Specializing on it projects
// the column from the union down to the member type.
class CtorUnionMember {
    value: root.types.Ty,
}

// Or-pattern: alternatives stored in `DPat.fields`. Never in witnesses.
class CtorOr {
}

// Matches anything of the column type.
class CtorWildcard {
}

// The column type has an effectively infinite alphabet. Produced only by
// `PatCtx.enumerate_ctors`, never by pattern lowering.
class CtorNonExhaustive {
}

// Sentinel used during witness construction when no concrete ctor is known.
class CtorMissing {
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::impl Hash for Ctor @ d9be6853b
// The identity key of a ctor; also `impl PartialEq for Ctor` (two ctors are
// equal iff their keys are). The discriminant, then the payload: a type by
// `ty_ctor_identity` (never raw `Ty` equality, whose `Freshness` would split
// identical ctors), class args per arg the same way.
function ctor_hash(ctor: Ctor) -> string throws never {
    match (ctor) {
        let c: CtorType => `Type:${ty_ctor_identity(c.value).value}`,
        let c: CtorSlice => match (c.value) {
            let s: SliceShapeFixed => `Slice:F${s.value}`,
            let s: SliceShapeVariable => `Slice:V${s.prefix},${s.suffix}`,
        },
        let c: CtorTuple => `Tuple:${c.value}`,
        let c: CtorClass => {
            `Class:${ty_ctor_identity(root.types.TyClass { name: c.name, args: c.args }).value}`
        },
        let c: CtorInterface => `Interface:${ty_ctor_identity(c.value).value}`,
        let c: CtorUnionMember => `UnionMember:${ty_ctor_identity(c.value).value}`,
        CtorOr => "Or",
        CtorWildcard => "Wildcard",
        CtorNonExhaustive => "NonExhaustive",
        CtorMissing => "Missing",
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::SliceShape @ d9be6853b
// The shape of an array pattern.
type SliceShape = SliceShapeFixed | SliceShapeVariable;

// `[a, b, c]`: exactly N elements. Arity = N.
class SliceShapeFixed {
    value: int,
}

// `[a, b, ..rest, y, z]`: at least prefix+suffix elements. Arity = prefix +
// suffix; `rest` is a pattern-side binding, not an algorithm slot.
class SliceShapeVariable {
    prefix: int,
    suffix: int,
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::SliceShape::arity @ d9be6853b
function slice_shape_arity(shape: SliceShape) -> int throws never {
    match (shape) {
        let s: SliceShapeFixed => s.value,
        let s: SliceShapeVariable => s.prefix + s.suffix,
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::Ctor::arity @ d9be6853b
// Arity for ctors whose arity is determined by the ctor and `ty` alone. `Or`'s
// arity comes from its `DPat`'s fields; callers special-case it.
function ctor_arity(ctor: Ctor, ty: root.types.Ty, cx: PatCtx) -> int throws never {
    match (ctor) {
        CtorType | CtorWildcard | CtorNonExhaustive | CtorMissing | CtorOr => 0,
        CtorUnionMember => 1,
        let c: CtorSlice => slice_shape_arity(c.value),
        let c: CtorTuple => c.value,
        let c: CtorClass => {
            cx.class_field_types(c.name, class_ty_for_ctor(c.name, c.args, ty)).length()
        },
        let c: CtorInterface => cx.interface_field_types(c.value).length(),
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::Ctor::covers @ d9be6853b
// Does `this` cover `other`, i.e. is every value matched by `other` also
// matched by `this`? Equality for most ctors; a type test covers the tests of
// its provable subtypes (`int` covers `1`); a variable-length slice covers
// fixed slices of compatible length; wildcard covers anything. `Or` rows are
// expanded at the matrix level before any cover check runs.
//
// A class pair is non-covering only when the args provably differ: an arity
// mismatch or an error-recovery arg means the pattern already failed
// resolution at its own site, so it covers like a name-only identity would.
function ctor_covers(this: Ctor, other: Ctor, cx: PatCtx) -> bool throws never {
    match (this, other) {
        (CtorWildcard, _) => true,
        (_, CtorWildcard) => false,
        (let a: CtorType, let b: CtorType) => {
            ty_ctor_identity(a.value) == ty_ctor_identity(b.value)
                || cx.is_subtype(b.value, a.value)
        },
        (let a: CtorTuple, let b: CtorTuple) => a.value == b.value,
        (let a: CtorClass, let b: CtorClass) => {
            a.name == b.name && !class_args_definitely_distinct(a.args, b.args)
        },
        (let a: CtorInterface, let b: CtorInterface) => {
            ty_ctor_identity(a.value) == ty_ctor_identity(b.value)
        },
        (let a: CtorSlice, let b: CtorSlice) => slice_covers(a.value, b.value),
        (let a: CtorUnionMember, let b: CtorUnionMember) => {
            ty_ctor_identity(a.value) == ty_ctor_identity(b.value)
        },
        (CtorNonExhaustive {}, CtorNonExhaustive {}) => true,
        (CtorMissing {}, CtorMissing {}) => true,
        (CtorOr {}, CtorOr {}) => true,
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::class_args_definitely_distinct @ d9be6853b
// Whether two `CtorClass` arg lists are provably distinct instantiations: same
// arity, no error-recovery arg on either side, and some position's identities
// differ. Anything undecidable is treated as not distinct.
function class_args_definitely_distinct(
    a: root.types.Ty[],
    b: root.types.Ty[],
) -> bool throws never {
    if (a.length() != b.length() || class_args_have_recovery(a) || class_args_have_recovery(b)) {
        return false;
    }
    baml.Array
        .generate(a.length(), (i) -> {
            i
        })
        .some((i) -> {
            ty_ctor_identity(a[i]) != ty_ctor_identity(b[i])
        })
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::class_args_have_recovery @ d9be6853b
// Whether any of a `CtorClass`'s type args carries the error sentinel
// anywhere in its structure (`baml_type::contains_error`). A written
// `unknown` argument is an ordinary argument.
function class_args_have_recovery(args: root.types.Ty[]) -> bool throws never {
    args.some((arg) -> {
        root.types.contains_ty_where(arg, (t) -> {
            t is root.types.TyError
        })
    })
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::class_ty_for_ctor @ d9be6853b
function class_ty_for_ctor(
    qtn: root.types.DeclName,
    args: root.types.Ty[],
    fallback: root.types.Ty,
) -> root.types.Ty throws never {
    match (fallback) {
        let c: root.types.TyClass if c.name == qtn => c,
        _ => root.types.TyClass { name: qtn, args: args },
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::slice_covers @ d9be6853b
function slice_covers(a: SliceShape, b: SliceShape) -> bool throws never {
    match (a, b) {
        (let x: SliceShapeFixed, let y: SliceShapeFixed) => x.value == y.value,
        (let x: SliceShapeVariable, let y: SliceShapeFixed) => x.prefix + x.suffix <= y.value,
        (let x: SliceShapeVariable, let y: SliceShapeVariable) => {
            x.prefix + x.suffix <= y.prefix + y.suffix
                && x.prefix <= y.prefix
                && x.suffix <= y.suffix
        },
        (SliceShapeFixed { value: _ }, SliceShapeVariable { prefix: _, suffix: _ }) => false,
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::CtorIdentity @ d9be6853b
// A canonicalized form of `Ty` used as the identity key for `CtorType`:
// `Freshness` dropped, float spellings canonicalized (`1.0` = `1.00` = `1e0`).
class CtorIdentity {
    value: string,
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::ty_ctor_identity @ d9be6853b
// Two types with the same identity are the same ctor.
function ty_ctor_identity(ty: root.types.Ty) -> CtorIdentity throws never {
    let out: string[] = [];
    write_ty_identity(out, ty);
    CtorIdentity { value: out.join("") }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::impl CtorHead for DeclName @ d9be6853b
// A head's identity for a ctor key, injective within one compile: the root's
// id (Rust: its `Debug`), then the namespace and name, dot-separated.
function decl_name_ctor_identity(decl: root.types.DeclName) -> string throws never {
    [`${decl.pkg}`].concat(decl.namespace).concat([decl.name]).join(".")
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::write_ty_identity @ d9be6853b
function write_ty_identity(out: string[], ty: root.types.Ty) -> void throws never {
    match (ty) {
        let t: root.types.TyLiteral => {
            out.push("L:");
            write_literal_identity(out, t.value);
        },
        let t: root.types.TyEnumVariant => {
            out.push(`EV:${decl_name_ctor_identity(t.name)}::${t.variant}`);
        },
        let t: root.types.TyEnum => {
            out.push(`E:${decl_name_ctor_identity(t.name)}`);
        },
        let t: root.types.TyClass => {
            out.push(`C:${decl_name_ctor_identity(t.name)}<`);
            out.push(
                t.args
                    .map((a) -> {
                        ty_ctor_identity(a).value
                    })
                    .join(","),
            );
            out.push(">");
        },
        let t: root.types.TyInterface => {
            out.push(`I:${decl_name_ctor_identity(t.name)}<`);
            out.push(
                t.args
                    .map((a) -> {
                        ty_ctor_identity(a).value
                    })
                    .join(","),
            );
            let wrote_any = t.args.length() > 0;
            for (let binding in t.associated_types) {
                if (wrote_any) {
                    out.push(",");
                }
                out.push(`${binding.name}=`);
                write_ty_identity(out, binding.ty);
                wrote_any = true;
            }
            out.push(">");
        },
        let t: root.types.TyAssociatedTypeProjection => {
            out.push("Assoc<");
            write_ty_identity(out, t.base);
            out.push(" as ");
            write_ty_identity(
                out,
                root.types.TyInterface {
                    name: t.interface_.name,
                    args: t.interface_.generics,
                    associated_types: t.interface_.associated_types,
                },
            );
            out.push(`.${t.member}>`);
        },
        root.types.TyInt => {
            out.push("P:Int");
        },
        root.types.TyBigint => {
            out.push("P:Bigint");
        },
        root.types.TyFloat => {
            out.push("P:Float");
        },
        root.types.TyString => {
            out.push("P:String");
        },
        root.types.TyBool => {
            out.push("P:Bool");
        },
        root.types.TyNull => {
            out.push("P:Null");
        },
        root.types.TyUint8Array => {
            out.push("P:Uint8Array");
        },
        let t: root.types.TyMedia => {
            out.push(`P:${t.kind}`);
        },
        let t: root.types.TyTuple => {
            out.push("T:(");
            out.push(
                t.items
                    .map((a) -> {
                        ty_ctor_identity(a).value
                    })
                    .join(","),
            );
            out.push(")");
        },
        let t: root.types.TyUnion => {
            out.push("U:[");
            out.push(
                t.members
                    .map((a) -> {
                        ty_ctor_identity(a).value
                    })
                    .join("|"),
            );
            out.push("]");
        },
        let t: root.types.TyList => {
            out.push("Lst:");
            write_ty_identity(out, t.elem);
        },
        let t: root.types.TyMap => {
            out.push("M:");
            write_ty_identity(out, t.key);
            out.push(",");
            write_ty_identity(out, t.value);
        },
        let t: root.types.TyTypeAlias => {
            out.push(`A:${decl_name_ctor_identity(t.name)}`);
        },
        let t: root.types.TyTypeVar => {
            out.push(`V:${t.param.name}`);
        },
        root.types.TyNever => {
            out.push("Never");
        },
        root.types.TyUnknown => {
            out.push("BUnk");
        },
        root.types.TyError => {
            out.push("Err");
        },
        root.types.TyRustType => {
            out.push("Rust");
        },
        root.types.TyType => {
            out.push("Type");
        },
        let t: root.types.TyFunction => {
            out.push("Fn(");
            out.push(
                t.params
                    .map((param) -> {
                        ty_ctor_identity(param.ty).value
                    })
                    .join(","),
            );
            out.push(")->");
            write_ty_identity(out, t.ret);
            out.push("!");
            write_ty_identity(out, t.throws_);
        },
        let t: root.types.TyFuture => {
            out.push("Fut<");
            write_ty_identity(out, t.value);
            out.push(",");
            write_ty_identity(out, t.error);
            out.push(">");
        },
        // `Resource`/`PromptAst` are never produced by TIR; the arms keep the
        // match exhaustive over the shared `Ty`.
        root.types.TyResource => {
            out.push("Res");
        },
        root.types.TyPromptAst => {
            out.push("PAst");
        },
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::write_literal_identity @ d9be6853b
// A float is canonicalized through its parsed value, with every zero one key
// and every NaN one key (Rust keys the bit pattern; any injective spelling of
// the value serves).
function write_literal_identity(out: string[], lit: root.base.Literal) -> void throws never {
    match (lit) {
        let l: root.base.LiteralInt => {
            out.push(`i${l.value}`);
        },
        let l: root.base.LiteralBigint => {
            out.push(`i${l.value}n`);
        },
        let l: root.base.LiteralBool => {
            out.push(
                if (l.value) {
                    "bT"
                } else {
                    "bF"
                },
            );
        },
        let l: root.base.LiteralString => {
            out.push(`s${root.base.rust_debug_string(l.value)}`);
        },
        let l: root.base.LiteralFloat => {
            let parsed = baml.Float.parse(l.value) catch (e) {
                baml.errors.ParseError => null,
            };
            let canon = if (parsed == null) {
                `raw:${l.value}`
            } else if (parsed.is_nan()) {
                "nan"
            } else if (parsed == 0.0) {
                "0"
            } else {
                `${parsed}`
            };
            out.push(`f${canon}`);
        },
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat @ d9be6853b
// A pattern in the form the usefulness algorithm consumes. `fields.length()
// == arity`; wildcards fill elided positions during lowering.
class DPat {
    ctor: Ctor,
    fields: DPat[],
    arity: int,
    ty: root.types.Ty,

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat::wildcard @ d9be6853b
    function wildcard(ty: root.types.Ty) -> DPat throws never {
        DPat { ctor: CtorWildcard {}, fields: [], arity: 0, ty: ty }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat::type_test @ d9be6853b
    function type_test(ty: root.types.Ty, scrutinee_ty: root.types.Ty) -> DPat throws never {
        DPat { ctor: CtorType { value: ty }, fields: [], arity: 0, ty: scrutinee_ty }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat::class @ d9be6853b
    function class_(
        qtn: root.types.DeclName,
        fields: DPat[],
        ty: root.types.Ty,
    ) -> DPat throws never {
        DPat {
            ctor: CtorClass { name: qtn, args: [] },
            arity: fields.length(),
            fields: fields,
            ty: ty,
        }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat::class_inst @ d9be6853b
    function class_inst(
        qtn: root.types.DeclName,
        args: root.types.Ty[],
        fields: DPat[],
        ty: root.types.Ty,
    ) -> DPat throws never {
        DPat {
            ctor: CtorClass { name: qtn, args: args },
            arity: fields.length(),
            fields: fields,
            ty: ty,
        }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat::interface @ d9be6853b
    function interface_(
        iface_ty: root.types.Ty,
        fields: DPat[],
        ty: root.types.Ty,
    ) -> DPat throws never {
        DPat {
            ctor: CtorInterface { value: iface_ty },
            arity: fields.length(),
            fields: fields,
            ty: ty,
        }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat::tuple @ d9be6853b
    function tuple(fields: DPat[], ty: root.types.Ty) -> DPat throws never {
        DPat {
            ctor: CtorTuple { value: fields.length() },
            arity: fields.length(),
            fields: fields,
            ty: ty,
        }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat::slice @ d9be6853b
    function slice(shape: SliceShape, fields: DPat[], ty: root.types.Ty) -> DPat throws never {
        DPat { ctor: CtorSlice { value: shape }, arity: fields.length(), fields: fields, ty: ty }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat::or @ d9be6853b
    // Or-pattern `pat1 | pat2 | ...`: the alternatives are the fields, each of
    // type `ty`; at least two by convention.
    function or(alts: DPat[], ty: root.types.Ty) -> DPat throws never {
        DPat { ctor: CtorOr {}, arity: alts.length(), fields: alts, ty: ty }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::DPat::union_member @ d9be6853b
    // Union-member tag: the single sub-pattern is the pattern as it would
    // have been against the member type directly.
    function union_member(
        member_ty: root.types.Ty,
        inner: DPat,
        scrut_ty: root.types.Ty,
    ) -> DPat throws never {
        DPat { ctor: CtorUnionMember { value: member_ty }, arity: 1, fields: [inner], ty: scrut_ty }
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessPat @ d9be6853b
// A missing-case witness: a concrete pattern shape that proves a match is
// non-exhaustive (or an irrefutable context refutable).
class WitnessPat {
    ctor: Ctor,
    fields: WitnessPat[],
    ty: root.types.Ty,

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessPat::wildcard @ d9be6853b
    function wildcard(ty: root.types.Ty) -> WitnessPat throws never {
        WitnessPat { ctor: CtorWildcard {}, fields: [], ty: ty }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessPat::new @ d9be6853b
    function new(ctor: Ctor, fields: WitnessPat[], ty: root.types.Ty) -> WitnessPat throws never {
        WitnessPat { ctor: ctor, fields: fields, ty: ty }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessPat::render @ d9be6853b
    // The witness as source-like text, with every type spelled from `vp`.
    function render(self, vp: Viewpoint) -> string throws never {
        match (self.ctor) {
            CtorWildcard | CtorNonExhaustive | CtorMissing => "_",
            // Or never appears in witnesses; rendered defensively as `_`.
            CtorOr => "_",
            // A "which branch" tag: the inner witness when it is concrete,
            // else the member type's name (`int` rather than `_`).
            let c: CtorUnionMember => {
                let inner = self.fields.at(0);
                if (
                    inner != null
                        && !(
                            inner.ctor is CtorWildcard
                                || inner.ctor is CtorNonExhaustive
                                || inner.ctor is CtorMissing
                        )
                ) {
                    inner.render(vp)
                } else {
                    write_member_ty_witness(vp, c.value)
                }
            },
            let c: CtorType => write_type_witness(vp, c.value),
            let c: CtorClass => {
                let head = class_witness_head(vp, c.name, c.args);
                if (self.fields.length() == 0) {
                    return `${head} {}`;
                }
                let fields = self.fields.map((fld) -> {
                    fld.render(vp)
                });
                `${head} { ${fields.join(", ")} }`
            },
            let c: CtorInterface => {
                let head = ty_spell(c.value, vp);
                if (self.fields.length() == 0) {
                    return `${head} {}`;
                }
                let fields = self.fields.map((fld) -> {
                    fld.render(vp)
                });
                `${head} { ${fields.join(", ")} }`
            },
            CtorTuple => {
                root.types.render_tuple(
                    self.fields.map((fld) -> {
                        fld.render(vp)
                    }),
                )
            },
            let c: CtorSlice => {
                let out: string[] = ["["];
                match (c.value) {
                    SliceShapeFixed => {
                        out.push(
                            self.fields
                                .map((fld) -> {
                                    fld.render(vp)
                                })
                                .join(", "),
                        );
                    },
                    let s: SliceShapeVariable => {
                        let i = 0;
                        for (let fld in self.fields) {
                            if (i > 0) {
                                out.push(", ");
                            }
                            if (i == s.prefix) {
                                // `self.fields[i..]` is never empty here.
                                out.push("..");
                                out.push(", ");
                            }
                            out.push(fld.render(vp));
                            i += 1;
                        }
                        if (self.fields.length() == s.prefix) {
                            // Trailing `..` (suffix is 0), comma-separated
                            // from any rendered prefix fields.
                            if (self.fields.length() > 0) {
                                out.push(", ");
                            }
                            out.push("..");
                        }
                    },
                }
                out.push("]");
                out.join("")
            },
        }
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::render_witness_pat @ d9be6853b
// Render a missing-case witness for the E0062 message: class witnesses carry
// their field NAMES (declaration order via HIR), union members cascade so
// nested classes keep labels, everything else renders as `WitnessPat.render`.
// `ClassRow` (a served package's class row) is not ported: a served class
// panics there, after the `mounted_class_loc` stub.
function render_witness_pat(db: root.hir.Db, vp: Viewpoint, w: WitnessPat) -> string throws never {
    match (w.ctor) {
        let c: CtorClass => {
            let names: string[] = match (definition_of(db, c.name)) {
                let d: root.hir.DefinitionClass => {
                    root.hir.class_data(db, d.value).fields.map((f) -> {
                        f.name
                    })
                },
                // A served package's class: its row's field names.
                _ => {
                    if (mounted_class_loc(db, c.name) != null) {
                        baml.sys.panic("extern_class_row: not ported")
                    }
                    []
                },
            };
            let head = class_witness_head(vp, c.name, c.args);
            if (w.fields.length() == 0) {
                return `${head} {}`;
            }
            let i = 0;
            let fields: string[] = [];
            for (let fld in w.fields) {
                let rendered = render_witness_pat(db, vp, fld);
                let name = names.at(i);
                fields.push(
                    if (name != null) {
                        `${name}: ${rendered}`
                    } else {
                        rendered
                    },
                );
                i += 1;
            }
            `${head} { ${fields.join(", ")} }`
        },
        CtorUnionMember => {
            let inner = w.fields.at(0);
            if (inner == null) {
                return w.render(vp);
            }
            let s = render_witness_pat(db, vp, inner);
            if (s == "_") {
                w.render(vp)
            } else {
                s
            }
        },
        CtorTuple => {
            root.types.render_tuple(
                w.fields.map((fld) -> {
                    render_witness_pat(db, vp, fld)
                }),
            )
        },
        _ => w.render(vp),
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::class_witness_head @ d9be6853b
// The head of a class witness: the class name, plus its type arguments when
// it has any. The arguments are part of the ctor's identity, so two
// instantiations missing render as two distinct witnesses.
function class_witness_head(
    vp: Viewpoint,
    qtn: root.types.DeclName,
    args: root.types.Ty[],
) -> string throws never {
    let name = vp.path(qtn);
    if (args.length() == 0) {
        return name;
    }
    let spelled = args.map((ty) -> {
        ty_spell(ty, vp)
    });
    `${name}<${spelled.join(", ")}>`
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::write_type_witness @ d9be6853b
// Anything but a literal, an enum variant or `null` renders as Rust's derived
// `Debug` of `Ty` (`ty_debug`, a stub).
function write_type_witness(vp: Viewpoint, ty: root.types.Ty) -> string throws never {
    match (ty) {
        let t: root.types.TyLiteral => match (t.value) {
            let l: root.base.LiteralInt => `${l.value}`,
            let l: root.base.LiteralBigint => `${l.value}n`,
            let l: root.base.LiteralBool => `${l.value}`,
            let l: root.base.LiteralString => root.base.rust_debug_string(l.value),
            let l: root.base.LiteralFloat => l.value,
        },
        let t: root.types.TyEnumVariant => `${vp.path(t.name)}.${t.variant}`,
        root.types.TyNull => "null",
        _ => ty_debug(ty),
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::write_member_ty_witness @ d9be6853b
// A `CtorUnionMember` witness's member type when the inner pat is a
// placeholder: the member's runtime shape (`int`, `string`, `Foo`) rather
// than `_`. Interfaces are open-world, so the uncovered interface is named.
function write_member_ty_witness(vp: Viewpoint, ty: root.types.Ty) -> string throws never {
    match (ty) {
        root.types.TyInt => root.types.primitive_type_alias(root.types.PrimitiveType.Int),
        root.types.TyBigint => root.types.primitive_type_alias(root.types.PrimitiveType.Bigint),
        root.types.TyFloat => root.types.primitive_type_alias(root.types.PrimitiveType.Float),
        root.types.TyString => root.types.primitive_type_alias(root.types.PrimitiveType.String),
        root.types.TyBool => root.types.primitive_type_alias(root.types.PrimitiveType.Bool),
        root.types.TyNull => root.types.primitive_type_alias(root.types.PrimitiveType.Null),
        root.types.TyUint8Array => {
            root.types.primitive_type_alias(root.types.PrimitiveType.Uint8Array)
        },
        let t: root.types.TyMedia => root.base.media_kind_display(t.kind),
        root.types.TyInterface => ty_spell(ty, vp),
        let t: root.types.TyClass => vp.path(t.name),
        let t: root.types.TyEnum => vp.path(t.name),
        let t: root.types.TyEnumVariant => `${vp.path(t.name)}.${t.variant}`,
        root.types.TyLiteral => write_type_witness(vp, ty),
        _ => "_",
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::PatCtx @ d9be6853b
// Operations the algorithm needs from the type system. The TIR builder
// implements this; the algorithm depends on nothing else.
interface PatCtx {
    // Enumerate the ctors that inhabit `ty`: every singleton for a finite
    // alphabet (`CtorType` per enum variant, both bool literals, ...),
    // `[CtorNonExhaustive]` for an infinite or opaque one, nothing for
    // `never`. Type aliases are expanded.
    function enumerate_ctors(self, ty: root.types.Ty) -> Ctor[] throws never;

    // For a class ctor applied at column type `ty` (which may carry generic
    // type arguments), the ordered field types after substitution.
    function class_field_types(
        self,
        qtn: root.types.DeclName,
        ty: root.types.Ty,
    ) -> root.types.Ty[] throws never;

    // For an interface ctor, the ordered field-view types after
    // substitution. Contexts that do not model interfaces keep the empty
    // default.
    function interface_field_types(self, ty: root.types.Ty) -> root.types.Ty[] throws never {
        []
    }

    // When an interface pattern row is specialized through an implementing
    // class ctor, map each interface field slot to the class field slot that
    // supplies it. Contexts that do not model interfaces decline.
    function interface_field_projection_for_class(
        self,
        iface_ty: root.types.Ty,
        class_qtn: root.types.DeclName,
        class_type_args: root.types.Ty[],
    ) -> int[]? throws never {
        null
    }

    // Whether an interface-pattern ctor covers every value in an interface
    // column. A narrower associated-type binding must not make an open
    // interface column exhaustive.
    function interface_ctor_covers_column(
        self,
        iface_ty: root.types.Ty,
        col_ty: root.types.Ty,
    ) -> bool throws never {
        ty_ctor_identity(iface_ty) == ty_ctor_identity(col_ty)
    }

    // For a slice ctor at column type `ty` (an array type), the sub-pattern
    // types: the element type repeated `arity` times.
    function slice_field_types(
        self,
        shape: SliceShape,
        ty: root.types.Ty,
    ) -> root.types.Ty[] throws never {
        let elem = self.list_element_type(ty);
        baml.Array.filled(slice_shape_arity(shape), elem)
    }

    // Whether every value of `sub` is provably a value of `sup`. Must answer
    // false for anything undecidable. Contexts that do not model subtyping
    // decline, which leaves type tests related by identity alone.
    function is_subtype(self, sub: root.types.Ty, sup: root.types.Ty) -> bool throws never {
        false
    }

    // The element type of an array type.
    function list_element_type(self, ty: root.types.Ty) -> root.types.Ty throws never;

    // Is this type inhabited? The default walks the type structurally with
    // cycle protection (a direct cycle counts as inhabited, since
    // uninhabitedness is anti-monotone). Real implementations override with a
    // cached query.
    function is_inhabited(self, ty: root.types.Ty) -> bool throws never {
        is_inhabited_default(ty, self, {})
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::is_inhabited_default @ d9be6853b
function is_inhabited_default(
    ty: root.types.Ty,
    cx: PatCtx,
    seen: map<string, bool>,
) -> bool throws never {
    match (ty) {
        root.types.TyNever => false,
        let c: root.types.TyClass => {
            let key = decl_name_ctor_identity(c.name);
            if (seen.has(key)) {
                // Cycle: assume inhabited. Uninhabitedness is only proven by
                // reaching a Never; it is never assumed.
                return true;
            }
            seen.set(key, true);
            let r = cx.class_field_types(c.name, ty).every((f) -> {
                is_inhabited_default(f, cx, seen)
            });
            seen.delete(key);
            r
        },
        let u: root.types.TyUnion => {
            u.members.some((m) -> {
                is_inhabited_default(m, cx, seen)
            })
        },
        let t: root.types.TyTuple => {
            t.items.every((e) -> {
                is_inhabited_default(e, cx, seen)
            })
        },
        // `T[]` always inhabits `[]`, so it is inhabited regardless of T.
        root.types.TyList => true,
        _ => true,
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::Row @ d9be6853b
class Row {
    pats: DPat[],
    // Source-arm index (for unreachable-arm reporting). Several rows share an
    // arm when an or-pattern was expanded.
    arm: ArmId,
    // Has any later ctor-witness exposed this row as useful?
    useful: bool,
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::ArmId @ d9be6853b
// A source-arm index.
type ArmId = int;

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::Matrix @ d9be6853b
class Matrix {
    rows: Row[],
    // Column types. Specializing on a column-0 ctor puts its sub-pattern
    // types in its place.
    col_tys: root.types.Ty[],

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::Matrix::new @ d9be6853b
    function new(arms: DPat[], scrut_ty: root.types.Ty) -> Matrix throws never {
        let rows = baml.Array.generate(arms.length(), (i) -> {
            Row { pats: [arms[i]], arm: i, useful: false }
        });
        Matrix { rows: rows, col_tys: [scrut_ty] }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::Matrix::specialize @ d9be6853b
    // Keep only rows whose column-0 ctor covers `ctor`, projecting their
    // sub-patterns into the leading columns. Wildcards in column 0 expand to
    // wildcards in each new sub-column.
    //
    // When `ctor` is `Or`, each row whose head is `Or` expands into one row
    // per alternative (sharing the source arm) and other rows pass through
    // unchanged; the column count stays the same.
    function specialize(
        self,
        cx: PatCtx,
        ctor: Ctor,
        sub_tys: root.types.Ty[],
        wild_pad: DPat[],
    ) -> Matrix throws never {
        if (ctor is CtorOr) {
            let new_rows: Row[] = [];
            for (let row in self.rows) {
                let head = row.pats[0];
                let tail = row.pats.slice(1, row.pats.length());
                if (head.ctor is CtorOr) {
                    for (let alt in head.fields) {
                        new_rows.push(
                            Row { pats: [alt].concat(tail), arm: row.arm, useful: row.useful },
                        );
                    }
                } else {
                    new_rows.push(Row { pats: row.pats, arm: row.arm, useful: row.useful });
                }
            }
            return Matrix { rows: new_rows, col_tys: self.col_tys };
        }

        let arity = sub_tys.length();
        let new_rows: Row[] = [];
        for (let row in self.rows) {
            let head = row.pats[0];
            let tail = row.pats.slice(1, row.pats.length());
            if (head.ctor is CtorWildcard) {
                new_rows.push(
                    Row {
                        pats: wild_pad.slice(0, arity).concat(tail),
                        arm: row.arm,
                        useful: row.useful,
                    },
                );
                continue;
            }
            let interface_projection = match (head.ctor, ctor) {
                (let iface: CtorInterface, let class_: CtorClass) => {
                    cx.interface_field_projection_for_class(iface.value, class_.name, class_.args)
                },
                _ => null,
            };
            if (!ctor_covers(head.ctor, ctor, cx) && interface_projection == null) {
                // The row's pattern accepts no value of shape `ctor`.
                continue;
            }

            // Project the row's fields into the `arity` slots, wildcards by
            // default. A `Variable{prefix, suffix}` slice projecting onto a
            // wider arity keeps prefix fields at 0..prefix and shifts suffix
            // fields to the rightmost positions; without the shift
            // `[..rest, true]` would cover `[true, false]`.
            let pats = wild_pad.slice(0, arity);
            let head_arity = head.fields.length();
            if (interface_projection != null) {
                let interface_idx = 0;
                for (let class_idx in interface_projection) {
                    let fld = head.fields.at(interface_idx);
                    if (fld != null && class_idx < arity) {
                        pats[class_idx] = fld;
                    }
                    interface_idx += 1;
                }
            } else {
                let variable = match (head.ctor) {
                    let s: CtorSlice if head_arity != arity => match (s.value) {
                        let v: SliceShapeVariable => v,
                        _ => null,
                    },
                    _ => null,
                };
                let i = 0;
                for (let fld in head.fields) {
                    if (variable != null) {
                        let new_idx = if (i < variable.prefix) {
                            i
                        } else {
                            i + arity - head_arity
                        };
                        pats[new_idx] = fld;
                    } else if (i < arity) {
                        pats[i] = fld;
                    }
                    i += 1;
                }
            }
            new_rows.push(Row { pats: pats.concat(tail), arm: row.arm, useful: row.useful });
        }
        Matrix {
            rows: new_rows,
            col_tys: sub_tys.concat(self.col_tys.slice(1, self.col_tys.length())),
        }
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::UsefulnessReport @ d9be6853b
// Top-level result of running usefulness on a match.
class UsefulnessReport {
    // One witness per missing case at the top level. Empty = exhaustive.
    missing: WitnessPat[],
    // Arms no value reaches that an earlier arm did not already match.
    unreachable_arms: ArmId[],
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::compute_match_usefulness @ d9be6853b
// Exhaustiveness and per-arm reachability. `arms` is one `DPat` per source
// arm; or-patterns are `CtorOr` nodes expanded during specialization, and
// usefulness aggregates back to the source arm.
function compute_match_usefulness(
    cx: PatCtx,
    arms: DPat[],
    scrut_ty: root.types.Ty,
) -> UsefulnessReport throws never {
    let all_arms = baml.Array.generate(arms.length(), (i) -> {
        i
    });
    // Uninhabited scrutinee: vacuously exhaustive, every arm unreachable.
    if (!cx.is_inhabited(scrut_ty)) {
        return UsefulnessReport { missing: [], unreachable_arms: all_arms };
    }

    let matrix = Matrix.new(arms, scrut_ty);
    let witness_matrix = WitnessMatrix { stacks: [] };
    compute_exhaustiveness(cx, matrix, witness_matrix);

    let used: map<int, bool> = {};
    for (let row in matrix.rows) {
        if (row.useful) {
            used.set(row.arm, true);
        }
    }
    // Already sorted and unique.
    let unreachable_arms = all_arms.filter((a) -> {
        !used.has(a)
    });

    // Witnesses come only from alphabet branches, whose ctors are disjoint
    // and deduplicated by ctor identity, so no rendered-form de-duplication
    // is needed (`class_witness_head` keeps class args so distinct
    // instantiations never render alike).
    UsefulnessReport {
        missing: witness_matrix.into_single_column(),
        unreachable_arms: unreachable_arms,
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessStack @ d9be6853b
// A column-stack of witness patterns, one entry per remaining matrix column.
class WitnessStack {
    pats: WitnessPat[],

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessStack::apply_ctor @ d9be6853b
    // Wrap the top `arity` patterns under `ctor`, reversing one specialize
    // step. The last pushed is the first sub-position, so the drained
    // patterns are reversed back to declaration order.
    function apply_ctor(
        self,
        ctor: Ctor,
        arity: int,
        ty: root.types.Ty,
    ) -> WitnessStack throws never {
        let len = self.pats.length();
        let fields = self.pats.slice(len - arity, len).reverse();
        WitnessStack {
            pats: self.pats.slice(0, len - arity).concat([WitnessPat.new(ctor, fields, ty)]),
        }
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessMatrix @ d9be6853b
// One witness stack per missing-case witness.
class WitnessMatrix {
    stacks: WitnessStack[],

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessMatrix::apply_ctor @ d9be6853b
    function apply_ctor(self, ctor: Ctor, arity: int, ty: root.types.Ty) -> void throws never {
        self.stacks
            = self.stacks.map((s) -> {
                s.apply_ctor(ctor, arity, ty)
            });
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessMatrix::apply_missing @ d9be6853b
    // For each missing ctor, copy every witness and push a wildcard-filled
    // pat for that ctor on top. A ctor with an uninhabited sub-field type
    // matches no value and is not a real missing case (`[Never, ..]`).
    function apply_missing(
        self,
        missing: Ctor[],
        ty: root.types.Ty,
        cx: PatCtx,
    ) -> void throws never {
        let original = self.stacks;
        self.stacks = [];
        for (let ctor in missing) {
            // Sub-pattern types come from the ctor's own slots, not the
            // parent column type.
            let field_tys = ctor_sub_tys(cx, ctor, ty);
            if (
                field_tys.some((t) -> {
                    !cx.is_inhabited(t)
                })
            ) {
                continue;
            }
            let pat = WitnessPat.new(
                ctor,
                field_tys.map((t) -> {
                    WitnessPat.wildcard(t)
                }),
                ty,
            );
            for (let stack in original) {
                self.stacks.push(WitnessStack { pats: stack.pats.concat([pat]) });
            }
        }
    }

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::WitnessMatrix::into_single_column @ d9be6853b
    function into_single_column(self) -> WitnessPat[] throws never {
        self.stacks.map((s) -> {
            s.pats[s.pats.length() - 1]
        })
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::compute_exhaustiveness @ d9be6853b
// The core recursion: marks rows of `matrix` useful and collects
// missing-case witnesses into `witnesses`. The empty-matrix and all-wildcard
// shortcuts in `split_ctors` make it terminate on recursive types.
function compute_exhaustiveness(
    cx: PatCtx,
    matrix: Matrix,
    witnesses: WitnessMatrix,
) -> void throws never {
    if (matrix.col_tys.length() == 0) {
        if (matrix.rows.length() == 0) {
            // A reachable leaf no row covers: a unit witness, wrapped by the
            // unspecialize chain on the way out.
            witnesses.stacks.push(WitnessStack { pats: [] });
        } else {
            // The first row covers this leaf; later rows are unreachable.
            matrix.rows[0].useful = true;
        }
        return;
    }

    let col_ty = matrix.col_tys[0];
    let split = split_ctors(cx, col_ty, matrix);
    let branches = split.split
        .map((c) -> {
            (c, true)
        })
        .concat(
            split.reachability_only.map((c) -> {
                (c, false)
            }),
        );

    for (let branch in branches) {
        let (let ctor, let in_alphabet) = branch;
        let sub_tys = ctor_sub_tys(cx, ctor, col_ty);
        let wild_pad = sub_tys.map((t) -> {
            DPat.wildcard(t)
        });

        let sub_matrix = matrix.specialize(cx, ctor, sub_tys, wild_pad);
        let sub_witnesses = WitnessMatrix { stacks: [] };
        compute_exhaustiveness(cx, sub_matrix, sub_witnesses);

        // Propagate "useful" back from sub-matrix rows to parent rows.
        for (let sub_row in sub_matrix.rows) {
            if (sub_row.useful) {
                for (let parent_row in matrix.rows) {
                    if (parent_row.arm == sub_row.arm) {
                        parent_row.useful = true;
                    }
                }
            }
        }

        if (!in_alphabet) {
            // Reachability-only branch: its rows are marked useful above, its
            // witnesses dropped (see `CtorSplit.reachability_only`).
            continue;
        }

        // Unspecialize: wrap sub-witnesses under this ctor. An or-pattern
        // contributes no ctor of its own: the expanded sub-matrix's
        // witnesses are already shaped for this level.
        match (ctor) {
            CtorMissing => {
                sub_witnesses.apply_missing(split.missing, col_ty, cx);
            },
            CtorOr => {},
            _ => {
                sub_witnesses.apply_ctor(ctor, ctor_arity(ctor, col_ty, cx), col_ty);
            },
        }
        for (let stack in sub_witnesses.stacks) {
            witnesses.stacks.push(stack);
        }
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::CtorSplit @ d9be6853b
// The outcome of `split_ctors`: which ctors to specialize on, partitioned by
// how each branch takes part in the verdict.
class CtorSplit {
    // Alphabet branches: together they cover the column's whole value set,
    // and witnesses propagate only from them. A synthetic `CtorMissing`
    // stands in for ctors absent from the matrix.
    split: Ctor[],
    // The absent alphabet ctors, expanding `CtorMissing` in a witness.
    missing: Ctor[],
    // Present-but-outside-the-alphabet branches (a rigid `Type`, an
    // arg-mismatched class, a non-slice head in a list column), specialized
    // only so their rows are marked reachable. A witness from one is at best
    // a duplicate and at worst a false non-exhaustive.
    reachability_only: Ctor[],

    // port: baml_compiler2_hir_ty/src/exhaustiveness.rs::CtorSplit::alphabet @ d9be6853b
    // A split whose branches are all alphabet branches.
    function alphabet(split: Ctor[], missing: Ctor[]) -> CtorSplit throws never {
        CtorSplit { split: split, missing: missing, reachability_only: [] }
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::split_ctors @ d9be6853b
// Decide which ctors to specialize on.
function split_ctors(cx: PatCtx, col_ty: root.types.Ty, matrix: Matrix) -> CtorSplit throws never {
    // Or-rows can't take part in a cover check; they explode first.
    if (
        matrix.rows.some((row) -> {
            row.pats[0].ctor is CtorOr
        })
    ) {
        return CtorSplit.alphabet([CtorOr {}], []);
    }

    // Empty matrix: nothing matched here. Enumerating `col_ty` would recurse
    // forever on recursive types, so a synthetic `Missing` drops the column;
    // `apply_missing` wraps one wildcard-filled pat per missing ctor.
    if (matrix.rows.length() == 0) {
        // An uninhabited column (also transitively, `class A { x: never }`)
        // is vacuously exhaustive.
        if (!cx.is_inhabited(col_ty)) {
            return CtorSplit.alphabet([], []);
        }
        // Lists: one open-ended `[..]` witness covers any list. Checked
        // before `enumerate_ctors`, whose empty answer for a list would read
        // as vacuously exhaustive.
        if (col_ty is root.types.TyList) {
            return CtorSplit.alphabet(
                [CtorMissing {}],
                [CtorSlice { value: SliceShapeVariable { prefix: 0, suffix: 0 } }],
            );
        }
        let all = cx.enumerate_ctors(col_ty);
        if (all.length() == 0) {
            // Vacuously exhaustive (`never` directly).
            return CtorSplit.alphabet([], []);
        }
        let missing: Ctor[] = if (
            all.some((c) -> {
                c is CtorNonExhaustive
            })
        ) {
            [CtorNonExhaustive {}]
        } else {
            dedup_ctors(all)
        };
        return CtorSplit.alphabet([CtorMissing {}], missing);
    }

    let present = collect_column_ctors(matrix);
    let has_wildcard = present.some((c) -> {
        c is CtorWildcard
    });
    let present_no_wild = present.filter((c) -> {
        !(c is CtorWildcard)
    });

    // Slice columns split into length classes, not by set membership.
    if (col_ty is root.types.TyList) {
        return split_slice_ctors(present_no_wild, has_wildcard);
    }

    let all = cx.enumerate_ctors(col_ty);

    if (
        all.some((c) -> {
            c is CtorNonExhaustive
        })
    ) {
        if (
            col_ty is root.types.TyInterface
                && present_no_wild.some((c) -> {
                    match (c) {
                        let i: CtorInterface => cx.interface_ctor_covers_column(i.value, col_ty),
                        _ => false,
                    }
                })
        ) {
            // The present ctors are the branches; class branches keep their
            // covering interface rows through the interface projection in
            // `specialize`.
            return CtorSplit.alphabet(present_no_wild, []);
        }
        // Infinite alphabet (raw int/string/float, generics, opaque types).
        let split = dedup_equivalent_type_tests(cx, present_no_wild);
        // With a wildcard, `NonExhaustive` is a pass-through ctor: concrete
        // heads don't cover it, wildcard rows pad and take it.
        split.push(
            if (has_wildcard) {
                CtorNonExhaustive {}
            } else {
                CtorMissing {}
            },
        );
        CtorSplit.alphabet(split, [CtorNonExhaustive {}])
    } else if (all.length() == 0) {
        // Vacuously exhaustive (`never`).
        CtorSplit.alphabet([], [])
    } else {
        // Finite alphabet of pairwise-disjoint ctors.
        if (present_no_wild.length() == 0 && has_wildcard) {
            // All rows are wildcards here; iterating the ctors would recurse
            // forever on recursive types. Pass through with a synthetic ctor
            // that drops the column.
            return CtorSplit.alphabet([CtorNonExhaustive {}], []);
        }
        // Every ctor of the type: wildcard rows extend to each, missing ones
        // recurse into an empty sub-matrix. `enumerate_ctors` can repeat a
        // ctor (`null` per optional layer).
        let all = dedup_ctors(all);
        // Membership by `covers`, not equality: a present ctor with
        // error-recovery args covers its column ctor without being equal.
        let missing = all.filter((c) -> {
            !present_no_wild.some((p) -> {
                ctor_covers(p, c, cx)
            })
        });
        // Possible-but-not-covering rows get their own reachability-only
        // branch: never specialized they would read as unreachable, and
        // their witnesses would be false.
        let all_set: map<string, bool> = {};
        for (let c in all) {
            all_set.set(ctor_hash(c), true);
        }
        let reachability_only = present_no_wild.filter((c) -> {
            !all_set.has(ctor_hash(c))
        });
        CtorSplit { split: all, missing: missing, reachability_only: reachability_only }
    }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::split_slice_ctors @ d9be6853b
// Mirrors rustc's `Slice::split`: partition array lengths into the finite
// set of `Fixed` lengths the column distinguishes plus one open-ended
// `Variable` for every longer length, each seen or unseen.
function split_slice_ctors(present: Ctor[], _has_wildcard: bool) -> CtorSplit throws never {
    let min_var_arity: int? = null;
    let max_var_prefix = 0;
    let max_var_suffix = 0;
    let max_fixed_plus_one = 1;
    let seen_fixed: map<int, bool> = {};
    for (let c in present) {
        match (c) {
            let slice: CtorSlice => match (slice.value) {
                let s: SliceShapeFixed => {
                    if (s.value + 1 > max_fixed_plus_one) {
                        max_fixed_plus_one = s.value + 1;
                    }
                    seen_fixed.set(s.value, true);
                },
                let s: SliceShapeVariable => {
                    if (s.prefix > max_var_prefix) {
                        max_var_prefix = s.prefix;
                    }
                    if (s.suffix > max_var_suffix) {
                        max_var_suffix = s.suffix;
                    }
                    let arity = s.prefix + s.suffix;
                    if (min_var_arity == null || arity < min_var_arity) {
                        min_var_arity = arity;
                    }
                },
            },
            _ => {},
        }
    }

    // The "max slice": the open-ended Variable covering the tail. Its arity
    // must exceed every fixed length seen, so the prefix grows to fit.
    let max_prefix = max_var_prefix;
    let max_suffix = max_var_suffix;
    if (max_prefix + max_suffix < max_fixed_plus_one) {
        max_prefix = max_fixed_plus_one - max_suffix;
    }
    let max_arity = max_prefix + max_suffix;

    // Only seen lengths go into `split`; unseen ones into `missing`, surfaced
    // through the synthetic `CtorMissing`. Both would duplicate witnesses.
    let split: Ctor[] = [];
    let missing: Ctor[] = [];
    let n = 0;
    while (n < max_arity) {
        let seen = seen_fixed.has(n) || (min_var_arity != null && min_var_arity <= n);
        let c: Ctor = CtorSlice { value: SliceShapeFixed { value: n } };
        if (seen) {
            split.push(c);
        } else {
            missing.push(c);
        }
        n += 1;
    }

    let tail: Ctor = CtorSlice { value: SliceShapeVariable { prefix: max_prefix, suffix: max_suffix } };
    if (min_var_arity != null && min_var_arity <= max_arity) {
        split.push(tail);
    } else {
        missing.push(tail);
    }

    // Non-slice heads in a list column (`let t: T[]` in a `string[]` column)
    // cover no length class but need a reachability-only branch of their own.
    let reachability_only = present.filter((c) -> {
        !(c is CtorSlice)
    });

    if (missing.length() > 0) {
        split.push(CtorMissing {});
    }
    CtorSplit { split: split, missing: missing, reachability_only: reachability_only }
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::collect_column_ctors @ d9be6853b
// The distinct column-0 ctors in first-seen order, with one trailing
// `CtorWildcard` if any row has one.
function collect_column_ctors(matrix: Matrix) -> Ctor[] throws never {
    let seen: map<string, bool> = {};
    let out: Ctor[] = [];
    let has_wildcard = false;
    for (let row in matrix.rows) {
        let head = row.pats[0];
        if (head.ctor is CtorWildcard) {
            has_wildcard = true;
            continue;
        }
        let key = ctor_hash(head.ctor);
        if (!seen.has(key)) {
            seen.set(key, true);
            out.push(head.ctor);
        }
    }
    if (has_wildcard) {
        out.push(CtorWildcard {});
    }
    out
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::dedup_ctors @ d9be6853b
// Order-preserving de-duplication: keeps the first occurrence of each ctor.
function dedup_ctors(ctors: Ctor[]) -> Ctor[] throws never {
    let seen: map<string, bool> = {};
    ctors.filter((c) -> {
        let key = ctor_hash(c);
        if (seen.has(key)) {
            false
        } else {
            seen.set(key, true);
            true
        }
    })
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::dedup_equivalent_type_tests @ d9be6853b
// Keep one type test per set of mutually covering ones (`int` beside an alias
// of `int`); each would otherwise be its own branch over the same values,
// reporting every witness once per spelling.
function dedup_equivalent_type_tests(cx: PatCtx, ctors: Ctor[]) -> Ctor[] throws never {
    let kept: Ctor[] = [];
    for (let ctor in ctors) {
        let duplicate = ctor is CtorType
            && kept.some((earlier) -> {
                earlier is CtorType
                    && ctor_covers(earlier, ctor, cx)
                    && ctor_covers(ctor, earlier, cx)
            });
        if (!duplicate) {
            kept.push(ctor);
        }
    }
    kept
}

// port: baml_compiler2_hir_ty/src/exhaustiveness.rs::ctor_sub_tys @ d9be6853b
function ctor_sub_tys(
    cx: PatCtx,
    ctor: Ctor,
    col_ty: root.types.Ty,
) -> root.types.Ty[] throws never {
    match (ctor) {
        let c: CtorClass => cx.class_field_types(c.name, class_ty_for_ctor(c.name, c.args, col_ty)),
        let c: CtorInterface => cx.interface_field_types(c.value),
        let c: CtorSlice => cx.slice_field_types(c.value, col_ty),
        let c: CtorTuple => match (col_ty) {
            let t: root.types.TyTuple if t.items.length() == c.value => t.items,
            // In an open column this ctor establishes only tuple kind and
            // arity, never membership in a tuple of `unknown` slots.
            _ => baml.Array.filled(c.value, root.types.TyUnknown {}),
        },
        // Projects a column from the union type down to the member type.
        let c: CtorUnionMember => [c.value],
        _ => [],
    }
}
