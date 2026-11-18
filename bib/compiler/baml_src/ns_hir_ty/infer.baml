// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// Body type inference: `infer_body` walks one body owner's expression tree
// with an `InferenceContext` over an `InferenceTable`
// (`root.hir_ty.infer.InferenceTable`). This file holds Unit 0 of the K4
// plan: the pure helpers, the result and resolution types, `PendingDiag`,
// `InferenceResult`, `InferenceContext` and `InferenceContext::new`. The
// rest of infer.rs is stubbed by unit in `infer_stubs_u<N>.baml`.
//
// Restructured (BAML forces it):
// - Rust's interned `Ty` is an `int` into the inference table's
//   `root.types.InferPool`; a helper with no context takes the pool first.
//   `baml_type::Ty` is `root.types.Ty`, `InferInterface` is
//   `root.types.InferInterfaceConstraint`, `baml_type::Interface` is
//   `root.types.InterfaceConstraint`, `Name` is `string`, `InferVar` and the
//   arena ids (`ExprId`, `PatId`, `StmtId`, `FileScopeId`) are `int`.
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so the `*Ref` declaration handles (`ClassRef`, `EnumRef`, `FunctionRef`,
//   `InterfaceRef`, `ImplRef`, `GlobalRef`) are their Source lane, an `int`
//   loc, as in method_resolution.baml.
// - Generic types (`InferenceResult<T>`, `MemberResolution<T>`, ...) are
//   generic classes. BAML type aliases take no generic parameters, so a
//   generic data enum is a union of generic variant classes spelled at each
//   use site, with one alias per instantiation: `MemberResolution` /
//   `MethodCallee` (`T = root.types.Ty`, Rust's default) and
//   `WorkingMemberResolution` / `WorkingMethodCallee` (`T = int`, the
//   engine's interned vocabulary). `WorkingResult` is
//   `InferenceResult<int>`.
// - Data enums are unions of classes `<Enum><Variant>`; methods on them are
//   free functions `<enum>_<method>`. Methods of `InferenceContext` are free
//   functions taking `ctx: InferenceContext` first.
// - `FxHashMap` keyed by an id is `map<int, ...>`; `FxHashSet<T>` is
//   `map<T, bool>`; `Journals::infer_var_origins` (an `IndexMap`) is a
//   `map`, which is insertion-ordered.
// - `nunny::Vec` (non-empty) is a plain array; `OnceCell` fields are
//   nullable, built on first use.
//
// Not ported here: the salsa `SalsaValue` impl; `impl Default for
// InferenceResult` / `WorkingResult` are `InferenceResult.empty(never)` at
// the call site (`empty` is the shared body).

// port: baml_compiler2_hir_ty/src/infer.rs::OwnArgs @ d9be6853b
// Where a type-qualified reference's OWN generic args come from (r-a's
// `substs_from_path` split): the call site's turbofish channel, or fresh
// variables for a value-position reference.
type OwnArgs = OwnArgsCall | OwnArgsFresh;

class OwnArgsCall {
    value: int,
}

class OwnArgsFresh {
}

// port: baml_compiler2_hir_ty/src/infer.rs::WrittenQualifier @ d9be6853b
// The written halves of a fully-qualified item reference's qualifier: the
// lowered `Self` type and the realized interface the determination road
// proved for it. Always both present or both absent.
class WrittenQualifier {
    qself: int,
    realized: root.types.InterfaceConstraint,
}

// port: baml_compiler2_hir_ty/src/infer.rs::negate_literal @ d9be6853b
// Negate a numeric literal into the negative literal TYPE (`-1` is a type,
// TS parity). Freshness carries through. Null skips the fold: non-numeric
// literals, and an int result outside BAML's i63 value range (the unfolded
// dispatch result stands and the VM raises the catchable overflow).
// Restructured: takes the pool; Rust's `i64::checked_neg` is a bigint
// negation range-checked by `int63_new`.
function negate_literal(
    pool: root.types.InferPool,
    literal: root.base.Literal,
    freshness: root.types.Freshness,
) -> int? throws never {
    let negated: root.base.Literal = match (literal) {
        let l: root.base.LiteralInt => {
            let value = root.types.int63_new(0n - l.value)
                ?? return null;
            root.base.LiteralInt { value: value }
        },
        let l: root.base.LiteralBigint => root.base.LiteralBigint { value: 0n - l.value },
        // The float's WRITTEN digits are preserved exactly: negation is a
        // sign-prefix toggle, never a parse/format round trip.
        let l: root.base.LiteralFloat => {
            root.base.LiteralFloat { value: root.base.strip_prefix(l.value, "-") ?? `-${l.value}` }
        },
        root.base.LiteralString | root.base.LiteralBool => {
            return null;
        },
    };
    pool.add(root.types.TyLiteral { value: negated, freshness: freshness })
}

// Rust's `usize::MAX` on a 64-bit target: the largest shift count
// `const_fold_binary` folds for a bigint.
const USIZE_MAX: bigint = 18446744073709551615n;

// port: baml_compiler2_hir_ty/src/infer.rs::const_fold_binary @ d9be6853b
// Fold a binary operator over two literal TYPES into the literal result:
// literal types are closed under the builtin operators (a deliberate
// divergence from TS, which never folds). Freshness merges: fresh operands
// make a fresh result, so bindings still widen. Null skips the fold:
// non-literal operands, mixed bases, and any result the VM could not
// materialize (i63 overflow, the bigint allocation cap, division by zero,
// non-finite floats); the runtime then raises the same catchable error the
// through-a-variable path gets.
// Restructured: takes the pool. Rust's `i64` checked arithmetic runs in
// `bigint` and is range-checked by `int63_new`; `usize::try_from` on a
// bigint shift count is a comparison with `USIZE_MAX`.
function const_fold_binary(
    pool: root.types.InferPool,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
) -> int? throws never {
    let (let a_lit, let b_lit) = match (pool.kinds[lhs], pool.kinds[rhs]) {
        (let a: root.types.TyLiteral, let b: root.types.TyLiteral) => (a, b),
        _ => {
            return null;
        },
    };
    let freshness = if (
        a_lit.freshness == root.types.Freshness.Regular
            && b_lit.freshness == root.types.Freshness.Regular
    ) {
        root.types.Freshness.Regular
    } else {
        root.types.Freshness.Fresh
    };
    let lit = (value: root.base.Literal) -> int {
        pool.add(root.types.TyLiteral { value: value, freshness: freshness })
    };
    let boolean = (value: bool) -> int? {
        lit(root.base.LiteralBool { value: value })
    };
    let int63 = (value: bigint) -> int? {
        let narrowed = root.types.int63_new(value);
        if (narrowed != null) {
            lit(root.base.LiteralInt { value: narrowed })
        } else {
            null
        }
    };
    match (a_lit.value, b_lit.value) {
        (let x: root.base.LiteralInt, let y: root.base.LiteralInt) => {
            let a = x.value;
            let b = y.value;
            match (op) {
                root.ast.BinaryOp.Add => int63(0n + a + b),
                root.ast.BinaryOp.Sub => int63(0n + a - b),
                root.ast.BinaryOp.Mul => int63((0n + a) * b),
                root.ast.BinaryOp.Div => {
                    if (b == 0) {
                        null
                    } else {
                        int63((0n + a) / b)
                    }
                },
                root.ast.BinaryOp.Mod => {
                    if (b == 0) {
                        null
                    } else {
                        int63((0n + a) % b)
                    }
                },
                root.ast.BinaryOp.BitAnd => lit(root.base.LiteralInt { value: a & b }),
                root.ast.BinaryOp.BitOr => lit(root.base.LiteralInt { value: a | b }),
                root.ast.BinaryOp.BitXor => lit(root.base.LiteralInt { value: a ^ b }),
                // The same semantic value used by the VM defines folding.
                // Negative counts remain unfolded so runtime dispatch raises
                // the typed `NegativeBitShift` panic.
                root.ast.BinaryOp.Shl => {
                    let shifted = root.types.int63_shift_left(a, b) catch (e) {
                        root.types.IntShiftErrorNegativeCount => null,
                    };
                    if (shifted != null) {
                        lit(root.base.LiteralInt { value: shifted })
                    } else {
                        null
                    }
                },
                root.ast.BinaryOp.Shr => {
                    let shifted = root.types.int63_shift_right(a, b) catch (e) {
                        root.types.IntShiftErrorNegativeCount => null,
                    };
                    if (shifted != null) {
                        lit(root.base.LiteralInt { value: shifted })
                    } else {
                        null
                    }
                },
                root.ast.BinaryOp.Eq => boolean(a == b),
                root.ast.BinaryOp.Ne => boolean(a != b),
                root.ast.BinaryOp.Lt => boolean(a < b),
                root.ast.BinaryOp.Le => boolean(a <= b),
                root.ast.BinaryOp.Gt => boolean(a > b),
                root.ast.BinaryOp.Ge => boolean(a >= b),
                _ => null,
            }
        },
        (let x: root.base.LiteralBigint, let y: root.base.LiteralBigint) => {
            let a = x.value;
            let b = y.value;
            let capped = (value: bigint) -> int? {
                if (root.base.bigint_bits(value) <= root.base.MAX_BIGINT_BITS) {
                    lit(root.base.LiteralBigint { value: value })
                } else {
                    null
                }
            };
            match (op) {
                root.ast.BinaryOp.Add => capped(a + b),
                root.ast.BinaryOp.Sub => capped(a - b),
                root.ast.BinaryOp.Mul => {
                    // Pre-flight matching `Instruction::MulBigint`.
                    if (
                        root.base.bigint_bits(a) + root.base.bigint_bits(b)
                            > root.base.MAX_BIGINT_BITS
                    ) {
                        return null;
                    }
                    capped(a * b)
                },
                root.ast.BinaryOp.Div if b != 0n => capped(a / b),
                root.ast.BinaryOp.Mod if b != 0n => capped(a % b),
                root.ast.BinaryOp.BitAnd => capped(a & b),
                root.ast.BinaryOp.BitOr => capped(a | b),
                root.ast.BinaryOp.BitXor => capped(a ^ b),
                // Shl growth is bounded by the allocation cap; a count past
                // `usize` (or past the cap) defers to the runtime
                // AllocFailure. Shr cannot grow: huge counts saturate to
                // `0n` / `-1n`, mirroring `Instruction::ShrBigint`.
                root.ast.BinaryOp.Shl if b >= 0n => {
                    if (b > USIZE_MAX) {
                        return null;
                    }
                    if (0n + root.base.bigint_bits(a) + b > 0n + root.base.MAX_BIGINT_BITS) {
                        return null;
                    }
                    capped(a << b)
                },
                root.ast.BinaryOp.Shr if b >= 0n => {
                    if (b <= USIZE_MAX) {
                        capped(a >> b)
                    } else if (a < 0n) {
                        capped(-1n)
                    } else {
                        capped(0n)
                    }
                },
                root.ast.BinaryOp.Eq => boolean(a == b),
                root.ast.BinaryOp.Ne => boolean(a != b),
                root.ast.BinaryOp.Lt => boolean(a < b),
                root.ast.BinaryOp.Le => boolean(a <= b),
                root.ast.BinaryOp.Gt => boolean(a > b),
                root.ast.BinaryOp.Ge => boolean(a >= b),
                _ => null,
            }
        },
        (let x: root.base.LiteralFloat, let y: root.base.LiteralFloat) => {
            let a = baml.Float.parse(x.value) catch (e) {
                baml.errors.ParseError => {
                    return null;
                },
            };
            let b = baml.Float.parse(y.value) catch (e) {
                baml.errors.ParseError => {
                    return null;
                },
            };
            let float = (value: float) -> int? {
                let text = format_float(value);
                if (text != null) {
                    lit(root.base.LiteralFloat { value: text })
                } else {
                    null
                }
            };
            // The comparisons below are plain IEEE, not BAML's total float
            // order. The two agree on every finite value (they differ only
            // on NaN), and a float LITERAL is always finite: source has no
            // NaN spelling and `format_float` refuses to fold a non-finite
            // result.
            match (op) {
                root.ast.BinaryOp.Add => float(a + b),
                root.ast.BinaryOp.Sub => float(a - b),
                root.ast.BinaryOp.Mul => float(a * b),
                root.ast.BinaryOp.Div if b != 0.0 => float(a / b),
                root.ast.BinaryOp.Mod if b != 0.0 => float(a % b),
                root.ast.BinaryOp.Eq => boolean(a == b),
                root.ast.BinaryOp.Ne => boolean(a != b),
                root.ast.BinaryOp.Lt => boolean(a < b),
                root.ast.BinaryOp.Le => boolean(a <= b),
                root.ast.BinaryOp.Gt => boolean(a > b),
                root.ast.BinaryOp.Ge => boolean(a >= b),
                _ => null,
            }
        },
        (let x: root.base.LiteralBool, let y: root.base.LiteralBool) => {
            let a = x.value;
            let b = y.value;
            match (op) {
                root.ast.BinaryOp.And => boolean(a && b),
                root.ast.BinaryOp.Or => boolean(a || b),
                root.ast.BinaryOp.Eq => boolean(a == b),
                root.ast.BinaryOp.Ne => boolean(a != b),
                _ => null,
            }
        },
        (let x: root.base.LiteralString, let y: root.base.LiteralString) => {
            let a = x.value;
            let b = y.value;
            match (op) {
                root.ast.BinaryOp.Add => lit(root.base.LiteralString { value: `${a}${b}` }),
                root.ast.BinaryOp.Eq => boolean(a == b),
                root.ast.BinaryOp.Ne => boolean(a != b),
                root.ast.BinaryOp.Lt => boolean(a < b),
                root.ast.BinaryOp.Le => boolean(a <= b),
                root.ast.BinaryOp.Gt => boolean(a > b),
                root.ast.BinaryOp.Ge => boolean(a >= b),
                _ => null,
            }
        },
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::format_float @ d9be6853b
// A folded float formatted so it always reads back as a float (a trailing
// `.0` when the value prints integral); non-finite results refuse the fold.
// BAML's float `to_string` prints Rust's `{}` spelling.
function format_float(value: float) -> string? throws never {
    if (!value.is_finite()) {
        return null;
    }
    let text = value.to_string();
    if (text.includes(".")) {
        text
    } else {
        `${text}.0`
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::union_of_tys @ d9be6853b
// A union of members that may still contain inference variables: canonical
// when every member is closed, structural until then (`syntactic_union`).
function union_of_tys(facts: Facts, members: int[]) -> int throws never {
    let pool = facts.db.ty_memo.pool;
    if (
        members.some((member) -> {
            pool.has_infer(member)
        })
    ) {
        return syntactic_union(pool, members);
    }
    root.types
        .canonical_union_interned(
            pool,
            members.map((member) -> {
                root.types.ClosedTy { ty: member }
            }),
            facts,
        )
        .ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::syntactic_union @ d9be6853b
// The STRUCTURAL third of union canonicalization, safe on var-carrying
// members: flatten nested unions, drop `never`, dedup identical members,
// collapse the empty union to `never` and the singleton to its member. The
// SEMANTIC pieces (absorption, literal-into-base) stay with the canonical
// path, which requires var-free input. Without the collapse, `Union([?0])`
// leaks into unification, whose union arm is positional.
// Restructured: takes the pool; the nested `push` is `syntactic_union_push`.
function syntactic_union(pool: root.types.InferPool, members: int[]) -> int throws never {
    let flat: int[] = [];
    for (let member in members) {
        syntactic_union_push(pool, flat, member);
    }
    match (flat.length()) {
        0 => pool.add(root.types.TyNever {}),
        1 => flat[0],
        _ => pool.add(root.types.InferTyUnion { members: flat }),
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::syntactic_union::push @ d9be6853b
function syntactic_union_push(
    pool: root.types.InferPool,
    flat: int[],
    ty: int,
) -> void throws never {
    match (pool.kinds[ty]) {
        let u: root.types.InferTyUnion => {
            for (let member in u.members) {
                syntactic_union_push(pool, flat, member);
            }
        },
        root.types.TyNever => {},
        _ => {
            if (!flat.includes(ty)) {
                flat.push(ty);
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::PROJECTION_FINALIZE_FUEL @ d9be6853b
// Reduction budget for the finalize-time projection pass: bounds a reduction
// CHAIN (`(A as I).X` -> `(B as J).Y` -> ...), the same discipline as the
// canonical walk's fuel.
const PROJECTION_FINALIZE_FUEL: int = 32;

// port: baml_compiler2_hir_ty/src/infer.rs::ROLE_MARKER_FUEL @ d9be6853b
// Depth budget for the role-marker walk over an interpolated type; a
// recursive alias (`baml.json.json`) would otherwise never bottom out.
const ROLE_MARKER_FUEL: int = 16;

// port: baml_compiler2_hir_ty/src/infer.rs::MemberResolution @ d9be6853b
// One member access's resolution: which declaration the member refers to,
// through which dispatch mode. rust-analyzer splits this into a table
// family; BAML keeps one enum because virtual interface dispatch adds modes.
// This alias is Rust's default instantiation (`T = baml_type::Ty`);
// `WorkingMemberResolution` is the engine's (`T` = interned `Ty`). A
// generic consumer spells the union with its own `T`.
type MemberResolution = MemberResolutionField
    | MemberResolutionVariant
    | MemberResolutionFree
    | MemberResolutionMethod<root.types.Ty>
    | MemberResolutionInterfaceVirtualField<root.types.Ty>;

// port: baml_compiler2_hir_ty/src/infer.rs::MemberResolution @ d9be6853b
// `MemberResolution<'db, Ty>`, the working instantiation.
type WorkingMemberResolution = MemberResolutionField
    | MemberResolutionVariant
    | MemberResolutionFree
    | MemberResolutionMethod<int>
    | MemberResolutionInterfaceVirtualField<int>;

// A class field access (`p.name`).
class MemberResolutionField {
    class_: int,
    field: string,
}

// An enum variant access (`Status.Active`).
class MemberResolutionVariant {
    enum_loc: int,
    variant: string,
}

// A free function named by a package/namespace path.
class MemberResolutionFree {
    func: int,
}

// A method access, by WHAT is called and whether the access binds its
// `self`: two independent axes. `recv.m(..)` binds the receiver;
// `Type.m(..)`, `I.m(recv, ..)` and `(C as I).m(recv, ..)` do not: there
// `self`, when the callee takes one, is the written first argument.
class MemberResolutionMethod<T> {
    callee: MethodCalleeInherent | MethodCalleeVirtual<T> | MethodCalleeConcrete<T>,
    receiver: Receiver,
}

// A VIRTUAL interface-field access: read through the realized
// declaring-interface view (`view`, the runtime resolver's key) at
// `field_index` in that interface's own declared field list.
class MemberResolutionInterfaceVirtualField<T> {
    interface_: int,
    view: T,
    field_index: int,
    field: string,
}

// port: baml_compiler2_hir_ty/src/infer.rs::MethodCallee @ d9be6853b
// What a method access calls, by dispatch: the class-inherent method
// itself, an interface's VIRTUAL slot (the receiver's runtime impl
// answers), or a CONCRETE interface method through a statically-matched
// impl. Instantiations as for `MemberResolution`.
type MethodCallee = MethodCalleeInherent
    | MethodCalleeVirtual<root.types.Ty>
    | MethodCalleeConcrete<root.types.Ty>;

// port: baml_compiler2_hir_ty/src/infer.rs::MethodCallee @ d9be6853b
// `MethodCallee<'db, Ty>`, the working instantiation.
type WorkingMethodCallee = MethodCalleeInherent
    | MethodCalleeVirtual<int>
    | MethodCalleeConcrete<int>;

// A class-inherent method. The owning class is the method's own
// (`callable_owner_type`), never carried alongside it.
class MethodCalleeInherent {
    value: int,
}

// A virtual interface slot: dispatch resolves to the receiver's runtime
// impl, keyed on the realized declaring-interface view (`view`) the access
// was checked through.
class MethodCalleeVirtual<T> {
    interface_: int,
    view: T,
    method: string,
}

// A statically-matched impl's method: the method the impl provides, or the
// interface's default body when adopted.
class MethodCalleeConcrete<T> {
    impl_block: int,
    func: int,
    // The instantiation of `func`'s OWNER frame, carried from resolution:
    // the impl's generic bindings for a method the impl provides,
    // `[Self, interface generics..]` for an adopted default. Which shape it
    // is IS `func`'s owner kind, never a separate fact.
    frame_type_args: T[],
}

// port: baml_compiler2_hir_ty/src/infer.rs::Receiver @ d9be6853b
// Whether a method access supplies `self` from its root value. Taking
// `self` at all is the CALLEE's property (`callable_takes_self`), never the
// access's.
enum Receiver {
    // The root value is bound as `self` (`recv.m(..)`): the access's type
    // has `self` stripped.
    Bound,
    // No receiver is bound (`Type.m(..)`, `I.m(..)`, `(C as I).m(..)`): the
    // access's type keeps `self` when the callee takes one.
    Unbound,
}

// port: baml_compiler2_hir_ty/src/infer.rs::MethodCallee::callable @ d9be6853b
// The callable statically named, wherever it is declared: the inherent or
// impl-provided (or adopted) method itself, or (for a virtual slot) the
// interface's own declaration of the method.
function method_callee_callable<T>(
    callee: MethodCalleeInherent | MethodCalleeVirtual<T> | MethodCalleeConcrete<T>,
    db: root.hir.Db,
) -> int? throws never {
    match (callee) {
        let c: MethodCalleeInherent => c.value,
        let c: MethodCalleeConcrete<T> => c.func,
        let c: MethodCalleeVirtual<T> => {
            root.hir.interface_data(db, c.interface_).methods.find((func) -> {
                root.hir.function_data(db, func).name == c.method
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::MemberResolution::callable @ d9be6853b
// The callable a resolution statically names, wherever it is declared: a
// free function, or a method's `method_callee_callable`. Fields and
// variants name none.
function member_resolution_callable<T>(
    resolution: MemberResolutionField
        | MemberResolutionVariant
        | MemberResolutionFree
        | MemberResolutionMethod<T>
        | MemberResolutionInterfaceVirtualField<T>,
    db: root.hir.Db,
) -> int? throws never {
    match (resolution) {
        let r: MemberResolutionFree => r.func,
        let r: MemberResolutionMethod<T> => method_callee_callable<T>(r.callee, db),
        MemberResolutionField | MemberResolutionVariant | MemberResolutionInterfaceVirtualField<T> => {
            null
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::ResolvedPath @ d9be6853b
// A value-rooted path expression's resolved ladder (`a.b.c`: one
// `Expr::Path` node, unnumbered segments): one entry per path expression.
// Package-rooted paths resolve as a whole and record only a
// `MemberResolution`; this table is for paths whose ROOT is a value.
class ResolvedPath<T> {
    // The ladder: entry 0 is the root value (no member resolution), entry
    // `i > 0` the `i`-th member access after it. For a qualified global the
    // written qualifiers have no entry (`path_segment_at_written`).
    segments: ResolvedPathSegment<T>[],

    // port: baml_compiler2_hir_ty/src/infer.rs::ResolvedPath::resolved_members @ d9be6853b
    // The member segments (everything after the root, which performs no
    // member access), when every one of them resolved: a partial ladder
    // still types each segment, but its members cannot be consumed
    // positionally.
    function resolved_members(self) -> ResolvedPathSegment<T>[]? throws never {
        if (self.segments.length() < 1) {
            return null;
        }
        let members = self.segments.slice(1, self.segments.length());
        if (
            members.every((segment) -> {
                segment.resolution != null
            })
        ) {
            members
        } else {
            null
        }
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::ResolvedPath::member_resolution @ d9be6853b
    // The resolution of member `member_index` (0 = the first segment after
    // the root), or null when any member is unresolved.
    function member_resolution(
        self,
        member_index: int,
    ) -> (
        MemberResolutionField
            | MemberResolutionVariant
            | MemberResolutionFree
            | MemberResolutionMethod<T>
            | MemberResolutionInterfaceVirtualField<T>
    )? throws never {
        self.resolved_members()?.at(member_index)?.resolution
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::ResolvedPath::final_member_resolution @ d9be6853b
    // The final member's resolution, or null when any member is unresolved.
    function final_member_resolution(
        self,
    ) -> (
        MemberResolutionField
            | MemberResolutionVariant
            | MemberResolutionFree
            | MemberResolutionMethod<T>
            | MemberResolutionInterfaceVirtualField<T>
    )? throws never {
        let members = self.resolved_members()
            ?? return null;
        members.at(members.length() - 1)?.resolution
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::GlobalRoot @ d9be6853b
// A path expression whose leading written segments name a top-level `let`
// (a global variable, a client, or a Session's persisted binding): bare `x`
// in the binding's own namespace, `root.ns.x` / `dep.ns.x` elsewhere.
// Recorded so MIR loads the global without re-resolving the spelling, and
// so the initialization-order analysis reads its edges from resolved
// references rather than names.
class GlobalRoot {
    // The binding: a source `let` (its loc).
    binding: int,
    // How many written segments name the binding (`1` for a bare name).
    segments: int,
}

// port: baml_compiler2_hir_ty/src/infer.rs::ResolvedPathSegment @ d9be6853b
class ResolvedPathSegment<T> {
    // The value's type AFTER this segment.
    ty: T,
    resolution: (
        MemberResolutionField
            | MemberResolutionVariant
            | MemberResolutionFree
            | MemberResolutionMethod<T>
            | MemberResolutionInterfaceVirtualField<T>
    )?,
}

// port: baml_compiler2_hir_ty/src/infer.rs::Adjustment @ d9be6853b
// A recorded coercion step at an expression, consumed structurally by MIR
// lowering (rust-analyzer's `Adjustment { kind, target }`). The source
// shape is `type_of_expr`; the target shape is here.
class Adjustment<T> {
    kind: Adjust,
    // The post-adjustment type (the expectation the value was adapted to).
    target: T,
}

// port: baml_compiler2_hir_ty/src/infer.rs::Adjust @ d9be6853b
enum Adjust {
    // A condition position holding a non-`bool` value: lowering synthesizes
    // the truthiness test (`null`/`false`/zero/empty are falsy) so the
    // branch itself stays strict-bool.
    Truthy,
}

// port: baml_compiler2_hir_ty/src/infer.rs::CallPlan @ d9be6853b
// One call's argument-to-parameter matching and solved instantiation (the
// prior art is Swift's Sema-recorded argument matching consumed by
// `SILGen`). Keyed by the CALL expression.
class CallPlan<T> {
    // Parameter-ordered bindings over the callee's parameter list MINUS any
    // bound receiver slot (the list written arguments match). Required
    // parameters with no argument get no entry.
    bindings: ParamBinding[],
    // The value slots the arguments were matched against (a bound receiver
    // excluded): the shape the call site pushes, which dispatch maps onto
    // the executing callee's own parameter list.
    argument_layout: root.types.CallLayout,
    // The callee's solved generic instantiation in declared De Bruijn order
    // (owner frame prefix + own suffix). Recorded raw at the instantiation
    // site; ground after writeback.
    type_args: T[],
    // How many leading `type_args` are the OWNER frame's (receiver class
    // args for bound methods, the interface frame for virtual calls). The
    // runtime call convention threads only the suffix as call operands, so
    // consumers slice here.
    own_offset: int,
    // Whether written turbofish filled the args. The runtime plan then
    // carries none: MIR lowers the WRITTEN types itself.
    explicit: bool,
    // Every WRITTEN type-argument slot, in source order, with the written
    // shape MIR emits alongside the solved type.
    slots: CallTypeArgPlan<T>[],

    // port: baml_compiler2_hir_ty/src/infer.rs::impl Default for CallPlan @ d9be6853b
    function default() -> Self {
        CallPlan {
            bindings: [],
            argument_layout: root.types.CallLayout { value: [] },
            type_args: [],
            own_offset: 0,
            explicit: false,
            slots: [],
        }
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::CallPlan::provided_args @ d9be6853b
    // The written arguments the plan bound, in parameter order.
    // Restructured: the lazy iterator is an array.
    function provided_args(self) -> int[] throws never {
        self.bindings.filter_map((binding) -> {
            match (binding) {
                let provided: ParamBindingProvided => provided.arg,
                ParamBindingOmittedDefault => null,
            }
        })
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::CallTypeArgPlan @ d9be6853b
// One written generic slot after its sole lowering pass.
class CallTypeArgPlan<T> {
    // Solved canonical type used by inference, equality, and digests.
    ty: T,
    // Written type shape used only when MIR emits `LoadType`. It is resolved
    // without union set-algebra so coercion try-order survives.
    emission_ty: T,
}

// port: baml_compiler2_hir_ty/src/infer.rs::ScopedTypeBinding @ d9be6853b
// One lexical `let type T = ...` binding: a rigid parameter whose identity
// is the binding statement, bound in the enclosing frame from `operand`
// when the statement runs.
class ScopedTypeBinding {
    name: string,
    parameter: root.types.ParamTy,
    // The `reflect.Type` or `reflect.TypeView` the slot is bound from,
    // evaluated once when the statement runs.
    operand: int,
    // The declared `extends` bounds, in written order. The statement checks
    // each one at run time, and `T` satisfies them statically afterwards. A
    // bound that is not an interface (already diagnosed) is left out.
    bounds: root.types.InterfaceConstraint[],
}

// port: baml_compiler2_hir_ty/src/infer.rs::ParamBinding @ d9be6853b
type ParamBinding = ParamBindingProvided | ParamBindingOmittedDefault;

class ParamBindingProvided {
    param_index: int,
    arg: int,
}

class ParamBindingOmittedDefault {
    param_index: int,
    param_name: string,
}

// port: baml_compiler2_hir_ty/src/infer.rs::TaggedTagIssue @ d9be6853b
// Which BEP-049 SS10 rule a tagged-template tag broke.
enum TaggedTagIssue {
    NotAFunction,
    NotMarked,
    BadBodyParam,
}

// port: baml_compiler2_hir_ty/src/infer.rs::IngestHoles @ d9be6853b
// What the lowering-to-inference ingestion does with a written `_` hole.
type IngestHoles = IngestHolesAnchored | IngestHolesExprPosition;

// An annotation-position hole: legal, anchored for unsolved reporting.
class IngestHolesAnchored {
    value: HoleAnchor,
}

// An expression-position hole: unconditionally diagnosed (E0147),
// instantiated only for recovery.
class IngestHolesExprPosition {
    value: int,
}

// port: baml_compiler2_hir_ty/src/infer.rs::HoleAnchor @ d9be6853b
// Where a written `_` hole sits: a body-position type annotation's ref.
type HoleAnchor = HoleAnchorTypeRef;

class HoleAnchorTypeRef {
    value: root.hir.BodyTypeRefId,
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferVarOrigin @ d9be6853b
// Where an inference variable came from and the user-facing type that
// contains it. Writeback uses this to report unsolved variables before
// replacing them with the error sentinel.
type InferVarOrigin = InferVarOriginTypeMustBeKnown
    | InferVarOriginLambdaParameter
    | InferVarOriginTypeParameter;

class InferVarOriginTypeMustBeKnown {
    location: DiagnosticLocation,
    containing_type: int,
}

class InferVarOriginLambdaParameter {
    lambda: int,
    parameter_index: int,
    name: string,
}

// A generic parameter's instantiation slot at a use site that wrote no
// argument for it (a call, a construction, a member value). Left unsolved,
// it is E0002 (cannot infer type parameter) at the site. The parameter is
// its frame identity: two parameters spelled alike are two slots. An
// `effect` slot is a generic that occurs only in `throws` positions, which
// defaults to `never` instead of reporting.
class InferVarOriginTypeParameter {
    site: int,
    param: root.types.ParamTy,
    effect: bool,
}

// port: baml_compiler2_hir_ty/src/infer.rs::Journals @ d9be6853b
// The accumulators the walk writes through, which a probe marks and
// truncates as one value: each grows at its end, so a mark is a length and
// the rollback a truncation (an entry may be amended in place before
// finish; none is removed from the middle).
//
// A probe relates types to learn whether they COULD relate and must leave
// no trace of the attempt. The table's snapshot covers the union-find and
// the bound ledger; these cover what the relation writes through on the
// way. `mark` and `truncate_to` name every field, so a new journal cannot
// be added without deciding its rollback.
class Journals {
    // The irreducible `Sub` residue: pairs that were neither ground nor
    // var-headed nor decomposable when emitted; re-examined at finish once
    // resolution has run.
    deferred_subs: (int, int, int?)[],
    // The obligation worklist: registered during the walk, discharged at
    // finish interleaved with bound resolution.
    obligations: root.hir_ty.infer.Pending[],
    // Pending diagnostics: anchored on arena ids, interned payloads;
    // finalized into `InferenceResult.diagnostics` (plain types) at finish.
    pending_diags: PendingDiag[],
    // Escapes refused with no anchor to report at (a relation reached from a
    // pattern walk or a bound replay): each waits for the block that binds
    // its parameter to close and is reported at that block's tail.
    anchorless_escapes: (root.types.ParamTy, int)[],
    // Ground values that checked against then-open expectations by
    // depositing bounds; re-judged once the vars solve.
    provisional_checks: (int, int, int)[],
    // User-source origins for ordinary inference variables that require a
    // concrete solution, in registration order: the order makes diagnostic
    // selection stable when several source variables unify into one
    // unresolved class.
    infer_var_origins: map<int, InferVarOrigin>,

    // port: baml_compiler2_hir_ty/src/infer.rs::Journals (derived Default) @ d9be6853b
    function default() -> Self {
        Journals {
            deferred_subs: [],
            obligations: [],
            pending_diags: [],
            anchorless_escapes: [],
            provisional_checks: [],
            infer_var_origins: {},
        }
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::Journals::mark @ d9be6853b
    function mark(self) -> JournalMark throws never {
        JournalMark {
            deferred_subs: self.deferred_subs.length(),
            obligations: self.obligations.length(),
            pending_diags: self.pending_diags.length(),
            anchorless_escapes: self.anchorless_escapes.length(),
            provisional_checks: self.provisional_checks.length(),
            infer_var_origins: self.infer_var_origins.length(),
        }
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::Journals::truncate_to @ d9be6853b
    // Discards everything appended since `mark`.
    function truncate_to(self, mark: JournalMark) -> void throws never {
        root.syntax.truncate(self.deferred_subs, mark.deferred_subs);
        root.syntax.truncate(self.obligations, mark.obligations);
        root.syntax.truncate(self.pending_diags, mark.pending_diags);
        root.syntax.truncate(self.anchorless_escapes, mark.anchorless_escapes);
        root.syntax.truncate(self.provisional_checks, mark.provisional_checks);
        let origins = self.infer_var_origins.keys();
        for (let key in origins.slice(mark.infer_var_origins, origins.length())) {
            self.infer_var_origins.delete(key);
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::JournalMark @ d9be6853b
// The length of every journal when a probe opened.
class JournalMark {
    deferred_subs: int,
    obligations: int,
    pending_diags: int,
    anchorless_escapes: int,
    provisional_checks: int,
    infer_var_origins: int,
}

// port: baml_compiler2_hir_ty/src/infer.rs::ProbeCheckpoint @ d9be6853b
// Where a speculative probe started; see `Journals`.
//
// `type_mismatches` is a keyed, first-writer-wins map rather than a
// journal, so it cannot be truncated; nothing on a probe road writes it
// (its only writer is the checking road, which a probe does not take) and
// the rollback asserts as much.
class ProbeCheckpoint {
    table: root.hir_ty.infer.Snapshot,
    journals: JournalMark,
    type_mismatches: int,
}

// port: baml_compiler2_hir_ty/src/infer.rs::ThrowsClause @ d9be6853b
// What a channel's contributions are judged against: the `throws` clause of
// the callable that owns the channel (written on the owner or a lambda,
// taken from the expected function type for a lambda without one), or
// nothing, for a channel that only collects (a `catch` base, a tagged
// template's flatten block). Rust's derived `Default` is `Inferred`.
type ThrowsClause = ThrowsClauseInferred | ThrowsClauseOpen | ThrowsClauseClosed;

// No closed clause: the effect is inferred from the contributions.
class ThrowsClauseInferred {
}

// `throws T | _`: `named` joins the inferred remainder on the surface, and
// the contract check is suspended.
class ThrowsClauseOpen {
    named: int,
}

// `throws T`: the contract every contribution is checked against, and the
// surface verbatim.
class ThrowsClauseClosed {
    value: int,
}

// port: baml_compiler2_hir_ty/src/infer.rs::ThrowsClause::closed @ d9be6853b
// The clause as a contract, when it is one.
function throws_clause_closed(clause: ThrowsClause) -> int? throws never {
    match (clause) {
        let c: ThrowsClauseClosed => c.value,
        ThrowsClauseInferred | ThrowsClauseOpen => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::ThrowsChannel @ d9be6853b
// The effects one callable (or one `catch` base) accumulates: `throw` sites
// and callee throws contribute into the innermost open channel.
class ThrowsChannel {
    clause: ThrowsClause,
    contributions: (int, int)[],
}

// port: baml_compiler2_hir_ty/src/infer.rs::ThrowsContract @ d9be6853b
class ThrowsContract {
    declared: int,
    contributions: (int, int)[],
    at: int,
}

// port: baml_compiler2_hir_ty/src/infer.rs::Suppress @ d9be6853b
// A kind of report the walk holds quiet while inside a construct that will
// judge it later, or that makes it noise.
enum Suppress {
    // A member lookup that is a PROBE: a failed lookup reports only when no
    // fallback tier remains; probes stay silent, the committed frame
    // reports.
    MemberProbe,
    // An optional-call callee inferred as an ordinary expression. Its
    // arguments still provide specialization evidence after the callee has
    // been typed, so a generic value diagnostic must remain conditional
    // until the whole call has been checked.
    OptionalCallee,
    // An or-pattern alternative, where the dead-pattern overlap check probes
    // SILENTLY: only the whole `|` chain failing to overlap reports, from
    // the chain's own frame.
    OrPattern,
    // A silent `is` test: a disjoint runtime type test is legal and answers
    // `false`, so the dead-pattern checks are quiet under it too, except the
    // tuple type test, which reports for a plain test, silent or not, and is
    // quiet only inside an alternative or a rejected rest.
    SilentTest,
    // The subtree of an already-REJECTED rest sub-pattern. The subtree still
    // lowers, but further rest-shape reports and dead-pattern mismatches
    // inside it are noise after the one rejection.
    RestReject,
}

// port: baml_compiler2_hir_ty/src/infer.rs::ChainFrame @ d9be6853b
// An `OptionalChain` while its links are typed. Rust's derived `Default` is
// `ChainFrame { nullable: false, skip: null }`.
class ChainFrame {
    // Whether some `?.` link's base was nullable: the boundary unions `null`
    // back into the chain's result.
    nullable: bool,
    // The state after the first `?.` link's base ran, which is where the
    // rest of the chain is skipped from when that base is null; set by the
    // link, rejoined at the boundary (`rejoin_skipped`).
    skip: root.hir_ty.infer.SkipPoint?,
}

// port: baml_compiler2_hir_ty/src/infer.rs::Suppressions @ d9be6853b
// How many constructs of each `Suppress` kind enclose the current point.
class Suppressions {
    member_probe: int,
    optional_callee: int,
    or_pattern: int,
    silent_test: int,
    rest_reject: int,

    // port: baml_compiler2_hir_ty/src/infer.rs::Suppressions (derived Default) @ d9be6853b
    function default() -> Self {
        Suppressions {
            member_probe: 0,
            optional_callee: 0,
            or_pattern: 0,
            silent_test: 0,
            rest_reject: 0,
        }
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::Suppressions::depth @ d9be6853b
    function depth(self, what: Suppress) -> int throws never {
        match (what) {
            Suppress.MemberProbe => self.member_probe,
            Suppress.OptionalCallee => self.optional_callee,
            Suppress.OrPattern => self.or_pattern,
            Suppress.SilentTest => self.silent_test,
            Suppress.RestReject => self.rest_reject,
        }
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::Suppressions::depth_mut @ d9be6853b
    // Restructured: BAML has no `&mut u32`, so this adds `delta` to the
    // counter Rust's `depth_mut` returns (`*depth_mut(what) += 1` is
    // `depth_mut(what, 1)`).
    function depth_mut(self, what: Suppress, delta: int) -> void throws never {
        match (what) {
            Suppress.MemberProbe => {
                self.member_probe += delta;
            },
            Suppress.OptionalCallee => {
                self.optional_callee += delta;
            },
            Suppress.OrPattern => {
                self.or_pattern += delta;
            },
            Suppress.SilentTest => {
                self.silent_test += delta;
            },
            Suppress.RestReject => {
                self.rest_reject += delta;
            },
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::ConstructorMiss @ d9be6853b
// Why a written constructor head yields no class to construct.
enum ConstructorMiss {
    // The head resolves to nothing, or to an item that is neither a class
    // nor an alias: reported as an unresolved constructor type.
    Unresolved,
    // The head is a type parameter or a scoped `type` binding: it shadows
    // every item and denotes no class to construct.
    TypeParameter,
    // The head is an alias of a type no object literal can construct:
    // already reported precisely.
    Reported,
}

// port: baml_compiler2_hir_ty/src/infer.rs::PendingDiag @ d9be6853b
// A pending diagnostic (engine-internal): arena-anchored, payload types
// interned (still var-carrying until finish); finalized into the shared
// vocabulary with PLAIN types at writeback.
type PendingDiag = PendingDiagNonExhaustiveMatch
    | PendingDiagNonExhaustiveCatchAll
    | PendingDiagUnreachableArm
    | PendingDiagUnresolvedName
    | PendingDiagReturnOutsideFunctionBody
    | PendingDiagAssignmentToGlobal
    | PendingDiagTopLevelLetCycle
    | PendingDiagUnresolvedMember
    | PendingDiagReceiverTypeMustBeKnown
    | PendingDiagAnnotWf
    | PendingDiagTaggedTagInvalid
    | PendingDiagExprPositionHole
    | PendingDiagIntLiteralOutOfRange
    | PendingDiagAmbiguousMember
    | PendingDiagFieldRequiresProjection
    | PendingDiagSelfRestrictedMember
    | PendingDiagSelflessInstanceMember
    | PendingDiagItemProjectionSelfSlot
    | PendingDiagUnionNoCommonInterface
    | PendingDiagUnionAssociatedTypeConflict
    | PendingDiagBoundedArgNotConcrete
    | PendingDiagInterfaceFieldInConstruction
    | PendingDiagQualifierNotInterface
    | PendingDiagDoesNotImplement
    | PendingDiagAmbiguousImplementation
    | PendingDiagWrongTypeArgArity
    | PendingDiagGenericFunctionValueNotSpecialized
    | PendingDiagComputedGenericArgumentRequiresLetType
    | PendingDiagBoundedLetTypeRequiresElse
    | PendingDiagLetTypePendingOperand
    | PendingDiagInvalidRegexPattern
    | PendingDiagMountedPackageCallUnsupported
    | PendingDiagInvalidAssignmentTarget
    | PendingDiagScopedTypeEscapesBlock
    | PendingDiagCannotConstructReflectionKind
    | PendingDiagCannotConstructBuiltinCompanion
    | PendingDiagCannotConstructOpaqueClass
    | PendingDiagCallSiteBuiltinValue
    | PendingDiagNotCallable
    | PendingDiagArgCountMismatch
    | PendingDiagUnknownNamedArg
    | PendingDiagTraceUnsupportedCall
    | PendingDiagTraceOpaqueValue
    | PendingDiagRefutableLet
    | PendingDiagLetElseMustDiverge
    | PendingDiagMissingNamedArg
    | PendingDiagPositionalDefaultedArg
    | PendingDiagUnresolvedCtor
    | PendingDiagItemShadowsPackage
    | PendingDiagConstructedTypeParameter
    | PendingDiagAliasNotConstructible
    | PendingDiagAliasTakesNoTypeArgs
    | PendingDiagPositionalAfterNamed
    | PendingDiagTupleElementAssign
    | PendingDiagFunctionFieldNeedsParens
    | PendingDiagTupleIndexOutOfRange
    | PendingDiagDuplicateNamedArg
    | PendingDiagScrutineeTypeMustBeKnown
    | PendingDiagListPatternNeverMatches
    | PendingDiagUninferredPatternAssociatedType
    | PendingDiagUninferredPatternTypeParam
    | PendingDiagExtraneousThrows
    | PendingDiagImpreciseUnknownThrows
    | PendingDiagDeferEscape
    | PendingDiagLoopControlOutsideLoop
    | PendingDiagLoopControlInLoopHeader
    | PendingDiagImplicitUnit
    | PendingDiagUnresolvedShorthand
    | PendingDiagComparisonAlwaysDisjoint
    | PendingDiagOrderingDifferentTypes
    | PendingDiagOrderingRequiresCompare
    | PendingDiagUnknownObjectField
    | PendingDiagMissingRequiredObjectFields
    | PendingDiagThrowsViolation
    | PendingDiagPatternScrutMismatch
    | PendingDiagTupleTypeTestNeverMatches
    | PendingDiagOperatorNotApplicable
    | PendingDiagBodyAnnot
    | PendingDiagInterpolatedMaybeNull
    | PendingDiagInterpolatedRoleMarker
    | PendingDiagBareOutputFormatReference
    | PendingDiagConditionAlwaysConst
    | PendingDiagGenericDestructureNoArgs
    | PendingDiagRestNotBinding
    | PendingDiagUnresolvedPatternName
    | PendingDiagUnknownPatternField
    | PendingDiagUnnecessaryOptionalChain
    | PendingDiagOrBindingConflict;

class PendingDiagNonExhaustiveMatch {
    expr: int,
    scrutinee: int,
    missing: string[],
}

// A `catch_all` / `catch_all_panics` clause leaving `missing` unhandled
// out of the (widened) errors it `caught`.
class PendingDiagNonExhaustiveCatchAll {
    expr: int,
    keyword: string,
    caught: root.types.Ty,
    missing: string[],
}

class PendingDiagUnreachableArm {
    expr: int,
    // Catch-road unreachability is advisory (a warning); a match
    // matrix's unreachable arm is an error (canary's split).
    warning: bool,
}

class PendingDiagUnresolvedName {
    expr: int,
    name: string,
    suggestions: string[],
}

// A `return` in an expression that is not a function body
// (`frames::ReturnEscape::Outside`).
class PendingDiagReturnOutsideFunctionBody {
    at: DiagnosticLocation,
    context: ReturnContext,
}

// An assignment whose target is a top-level binding.
class PendingDiagAssignmentToGlobal {
    target: int,
    name: string,
    is_client: bool,
}

class PendingDiagTopLevelLetCycle {
    expr: int,
}

class PendingDiagUnresolvedMember {
    expr: int,
    base: int,
    member: string,
}

// Member lookup ran while the base was still an inference variable.
class PendingDiagReceiverTypeMustBeKnown {
    expr: int,
    member: string,
}

// A body annotation failing the written-type well-formedness
// judgment (generic-argument bounds).
class PendingDiagAnnotWf {
    type_ref: root.hir.BodyTypeRefId,
    error: TirTypeError,
}

// A tagged-template tag failing BEP-049 SS10's contract.
class PendingDiagTaggedTagInvalid {
    at: int,
    name: string,
    func: int?,
    kind: TaggedTagIssue,
}

// E0147: a written `_` in an expression-position type argument.
class PendingDiagExprPositionHole {
    expr: int,
}

// E0150: an `int` literal outside the VM's i63 value range.
class PendingDiagIntLiteralOutOfRange {
    expr: int,
    value: int,
}

// BEP-044 method disambiguation: `member` on `base` is declared by
// two or more realized-distinct interfaces (rustc's E0034 shape) -
// resolving would silently pick one, so the access must qualify
// with `as<I>`.
class PendingDiagAmbiguousMember {
    expr: int,
    base: int,
    member: string,
    sources: root.types.InferInterfaceConstraint[],
    is_field: bool,
}

// An interface FIELD reached on a concrete receiver: reachable only
// through an explicit `obj.as<I>.field` projection.
class PendingDiagFieldRequiresProjection {
    expr: int,
    base: int,
    member: string,
    interface_: root.types.InferInterfaceConstraint,
}

// A method declared with `Self` outside the receiver position,
// called through an existential/union receiver (Rust's `dyn`
// object-safety split).
class PendingDiagSelfRestrictedMember {
    expr: int,
    interface_: root.types.InferInterfaceConstraint,
    member: string,
    position: SelfCallPosition,
}

// A `self`-less interface method reached through a VALUE receiver.
class PendingDiagSelflessInstanceMember {
    expr: int,
    interface_name: string?,
    member: string,
}

// An item projection's `Self` slot, judged once inference resolves it:
// erased (existential/union) `Self` is admitted only where the method
// can dispatch on it: its one required `Self`-typed parameter, whose
// argument the VM reads `Self` from. Pushed for EVERY item projection;
// a concrete or typevar slot passes silently.
class PendingDiagItemProjectionSelfSlot {
    expr: int,
    var: int,
    interface_: root.types.InferInterfaceConstraint,
    member: string,
    dispatch: SelfDispatch,
    // Whether the reference is a VALUE (uncalled). A receiver method
    // with an erased `Self` dispatches fine when CALLED (the receiver
    // value carries the concrete type), but a reified value has no
    // resolution moment: there is no thunk carrier yet, so it is
    // rejected.
    value_position: bool,
}

// A member on a union receiver with no interface shared by every
// arm declaring it.
class PendingDiagUnionNoCommonInterface {
    expr: int,
    base: int,
    member: string,
}

// A member on a union receiver whose type needs one answer where the
// arms bind an associated type differently.
class PendingDiagUnionAssociatedTypeConflict {
    expr: int,
    base: int,
    member: string,
    is_method: bool,
    types: int[],
}

// An abstract type (union or interface existential) instantiating an
// interface-bounded generic parameter - no single runtime type to
// dispatch on (E0001).
class PendingDiagBoundedArgNotConcrete {
    expr: int,
    arg: int,
    bound: root.types.InferInterfaceConstraint,
    required_for: root.hir_ty.infer.RequiredFor[],
}

// A constructor entry naming an implemented interface's FIELD; the
// backing class field is the constructor's key.
class PendingDiagInterfaceFieldInConstruction {
    object: int,
    name: string,
    class_field: string,
}

// A written interface qualifier that is not an interface at all:
// `.as<T>`, or `(Base as T).item`.
class PendingDiagQualifierNotInterface {
    expr: int,
    target: int,
}

// `value` does not implement `interface` (an existential): a written
// qualifier the subject does not implement (`x.as<I>`, `(Base as
// I).item`), or a failed `Implements` goal - the nominal verdict,
// never re-judged by subtyping.
class PendingDiagDoesNotImplement {
    expr: int,
    value: int,
    interface_: int,
    required_for: root.hir_ty.infer.RequiredFor[],
}

// An `Implements` goal on a known subject still pending at
// quiescence: more than one impl or bound could prove it, and nothing
// left to solve picks one.
class PendingDiagAmbiguousImplementation {
    expr: int,
    value: int,
    interface_: int,
    required_for: root.hir_ty.infer.RequiredFor[],
}

// Explicit turbofish count disagrees with the callee's declared
// (writable) generic params.
class PendingDiagWrongTypeArgArity {
    expr: int,
    callee: string,
    expected: int,
    got: int,
}

class PendingDiagGenericFunctionValueNotSpecialized {
    expr: int,
    name: string,
    reference: string,
    inference_evidence: int[],
    specialization_args: int[]?,
    unconditional: bool,
    had_expected_type: bool,
    generic_params: string[],
    binding_name: string?,
    function_shape: string?,
    annotation_ty: int?,
    specialization_example_is_safe: bool,
    specialization_syntax_available: bool,
}

class PendingDiagComputedGenericArgumentRequiresLetType {
    expr: int,
    name: string,
}

// A `let type T extends … = …` statement without an `else` block: its
// bounds are checked when it runs, so a miss needs somewhere to go.
class PendingDiagBoundedLetTypeRequiresElse {
    stmt: int,
    name: string,
}

// A `let type` operand that is a class builder's pending type.
class PendingDiagLetTypePendingOperand {
    expr: int,
}

// A constant pattern argument that does not compile.
class PendingDiagInvalidRegexPattern {
    expr: int,
    kind: baml.regex.ErrorKind,
    message: string,
    offset: int?,
}

class PendingDiagMountedPackageCallUnsupported {
    expr: int,
    path: string,
}

class PendingDiagInvalidAssignmentTarget {
    expr: int,
    path: string,
}

// A value typed by a block-scoped `let type T = …` binding would be
// observable outside its block: the block's value (anchored at the
// tail), or a thrown type an inferred clause would publish (anchored
// at the throw). `value` is the escaping type, `name` the binding's.
class PendingDiagScopedTypeEscapesBlock {
    at: int,
    name: string,
    value: int,
    kind: ScopedTypeEscapeKind,
}

class PendingDiagCannotConstructReflectionKind {
    expr: int,
    class_name: root.types.DeclName,
}

class PendingDiagCannotConstructBuiltinCompanion {
    expr: int,
    class_name: root.types.DeclName,
    companion: root.types.BuiltinCompanion,
}

// A class literal for a class holding `$rust_type` state in `field`.
class PendingDiagCannotConstructOpaqueClass {
    expr: int,
    class_name: root.types.DeclName,
    field: string,
}

// A builtin lowered at its call site, referenced other than as a
// direct call's callee.
class PendingDiagCallSiteBuiltinValue {
    expr: int,
    reference: string,
}

class PendingDiagNotCallable {
    expr: int,
    ty: int,
}

class PendingDiagArgCountMismatch {
    expr: int,
    expected: int,
    got: int,
}

class PendingDiagUnknownNamedArg {
    expr: int,
    name: string,
}

class PendingDiagTraceUnsupportedCall {
    expr: int,
}

class PendingDiagTraceOpaqueValue {
    expr: int,
}

class PendingDiagRefutableLet {
    pat: int,
    context: IrrefutableContextKind,
}

class PendingDiagLetElseMustDiverge {
    expr: int,
    got: int,
}

// A NAMED call leaving a required parameter unfilled - reported by
// name, not count.
class PendingDiagMissingNamedArg {
    expr: int,
    name: string,
}

// A positional argument landing on a DEFAULTED (by-name-only)
// parameter.
class PendingDiagPositionalDefaultedArg {
    expr: int,
    name: string,
}

// A constructor head naming no class (with near-matches).
class PendingDiagUnresolvedCtor {
    expr: int,
    name: string,
    suggestions: string[],
}

// A path that failed to resolve started at an item of this namespace
// spelled like a package: the hint that the package is out of reach.
class PendingDiagItemShadowsPackage {
    expr: int,
    name: string,
}

// A constructor head that is a type parameter or a scoped `type`
// binding.
class PendingDiagConstructedTypeParameter {
    expr: int,
    name: string,
}

// A constructor head that is an alias of a type no object literal can
// construct.
class PendingDiagAliasNotConstructible {
    expr: int,
    name: string,
    denotes: root.types.Ty,
}

// Type arguments written on an alias, which takes none: the class's
// come from the alias's definition.
class PendingDiagAliasTakesNoTypeArgs {
    expr: int,
    name: string,
    got: int,
}

// A positional argument after a named one.
class PendingDiagPositionalAfterNamed {
    expr: int,
}

class PendingDiagTupleElementAssign {
    expr: int,
}

class PendingDiagFunctionFieldNeedsParens {
    expr: int,
}

class PendingDiagTupleIndexOutOfRange {
    expr: int,
    index: int,
    tuple: int,
    variant: int?,
}

// The same argument name supplied twice.
class PendingDiagDuplicateNamedArg {
    expr: int,
    name: string,
}

// A `match` whose scrutinee type was still open when the arms were
// judged: usefulness needs the type at that point, so the match is
// refused there whatever the variable later solves to (rustc's
// structural resolution at the scrutinee).
class PendingDiagScrutineeTypeMustBeKnown {
    expr: int,
    // The scrutinee's type as it was at the match.
    full_type: root.types.Ty,
}

// A list pattern against a scrutinee none of whose values is a list.
class PendingDiagListPatternNeverMatches {
    pat: int,
    scrutinee: int,
}

// An interface pattern whose instantiation leaves the associated type
// `name` unpinned: nothing determines it.
class PendingDiagUninferredPatternAssociatedType {
    pat: int,
    name: string,
}

// An interface pattern that wrote no type arguments and could adopt
// none from the scrutinee: nothing determines the interface's `name`.
class PendingDiagUninferredPatternTypeParam {
    pat: int,
    name: string,
}

// E0097: declared throws members the body can never throw.
class PendingDiagExtraneousThrows {
    at: int,
    extra_types: string[],
}

// E0097: an `unknown`-containing contract without an escaping `unknown`.
class PendingDiagImpreciseUnknownThrows {
    at: int,
    // What the function actually throws, as ONE type; `None` when it
    // throws nothing.
    inferred: root.types.Ty?,
    // Some inferred member is a scoped thrown type's relaxation: the
    // clause is required (removing it is E0172), only its spelling is
    // wrong.
    needs_declaration: bool,
}

// Control flow that would escape a `defer` body (BEP-042): `return`
// always; `break`/`continue` unless a loop opened INSIDE the defer.
class PendingDiagDeferEscape {
    at: DiagnosticLocation,
    keyword: string,
}

// A `break`/`continue` with no loop open in its frame; `barrier` is
// why (`crate::diagnostics::LoopControlBarrier`).
class PendingDiagLoopControlOutsideLoop {
    stmt: int,
    keyword: string,
    barrier: LoopControlBarrier,
}

// A `break`/`continue` written in a header slot of the loop it binds
// to; a loop is left from its body.
class PendingDiagLoopControlInLoopHeader {
    stmt: int,
    keyword: string,
    slot: LoopHeaderSlot,
}

// An implicit unit met a context that is not (or not yet known to be)
// the unit type; judged at finish on the finalized context. See
// `InferenceContext::unit_verdict`.
class PendingDiagImplicitUnit {
    site: UnitSite,
    demand: UnitDemand,
}

// An untyped-object property shorthand naming no in-scope value -
// the specialized spelling of unresolved-name, with near-matches.
class PendingDiagUnresolvedShorthand {
    expr: int,
    name: string,
    suggestions: string[],
}

// The comparison rules (TIR's family): a provably-disjoint `==`/`!=`
// pair warns (the comparison is a constant), and the ordering
// operators demand SAME-typed, `baml.ops.Compare`-implementing
// operands.
class PendingDiagComparisonAlwaysDisjoint {
    at: int,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
}

class PendingDiagOrderingDifferentTypes {
    at: int,
    op: root.ast.BinaryOp,
    lhs: int,
    rhs: int,
}

class PendingDiagOrderingRequiresCompare {
    at: int,
    op: root.ast.BinaryOp,
    ty: int,
}

// An object-literal entry naming no declared field of the constructed
// class - the plain spelling and the property-shorthand spelling get
// their own messages (TIR's pair). Shorthand is detected structurally
// (the value is a bare path spelling the field name), keeping
// inference span-free.
class PendingDiagUnknownObjectField {
    object: int,
    value: int,
    class_name: root.types.DeclName,
    declared: string[],
    name: string,
    shorthand: bool,
}

// A constructor without a spread omitted fields whose resolved types do
// not admit `null`.
class PendingDiagMissingRequiredObjectFields {
    object: int,
    class_name: root.types.DeclName,
    field_names: string[],
}

// A throw site (or a callee's propagated effect) whose contribution
// escapes the CLOSED declared clause: TIR's throws-contract family,
// rendered as the dedicated E-code rather than a generic mismatch.
class PendingDiagThrowsViolation {
    at: int,
    declared: int,
    extra: int,
}

// A `match`/`is` type pattern PROVABLY dead against its scrutinee - no
// realization of the in-scope rigid type variables gives them a common
// value (the overlap oracle's `No`). Reported like any concrete
// pattern/scrutinee mismatch (TIR's policy and message).
class PendingDiagPatternScrutMismatch {
    pat: int,
    expected: int,
    found: int,
}

class PendingDiagTupleTypeTestNeverMatches {
    pat: int,
    scrutinee: int,
    tested: int,
}

class PendingDiagOperatorNotApplicable {
    expr: int,
    interface_: string,
    lhs: int,
    rhs: int?,
}

class PendingDiagBodyAnnot {
    type_ref: root.hir.BodyTypeRefId,
    kind: LoweringDiagKind,
}

class PendingDiagInterpolatedMaybeNull {
    expr: int,
    ty: int,
}

class PendingDiagInterpolatedRoleMarker {
    expr: int,
    ty: int,
}

class PendingDiagBareOutputFormatReference {
    expr: int,
}

// B-1563 truthiness: a NON-literal condition whose static type
// decides the branch (`if (some_fn)`, `if (instance)`) - a likely
// bug, warned like TS 5.6's 2872/2873.
class PendingDiagConditionAlwaysConst {
    expr: int,
    ty: int,
    always_true: bool,
}

class PendingDiagGenericDestructureNoArgs {
    pat: int,
    class_name: string,
}

class PendingDiagRestNotBinding {
    pat: int,
}

class PendingDiagUnresolvedPatternName {
    pat: int,
    name: string,
    suggestions: string[],
}

class PendingDiagUnknownPatternField {
    pat: int,
    class_name: root.types.DeclName,
    field_name: string,
    declared: string[],
}

class PendingDiagUnnecessaryOptionalChain {
    expr: int,
    expr_text: string,
    base_text: string,
}

class PendingDiagOrBindingConflict {
    pat: int,
    name: string,
    first: int,
    other: int,
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult @ d9be6853b
// Inference side tables for one body owner, keyed by arena ids, mirroring
// rust-analyzer's `InferenceResult`; consumers must treat a missing entry
// as "not inferred", never as an error. Generic over the type vocabulary:
// the public artifact (`T = root.types.Ty`) is plain, since `finish`
// disposes of every inference variable and materializes through
// `materialize_ty`; the engine records in the working instantiation
// (`WorkingResult`, `T = int`).
class InferenceResult<T> {
    type_of_expr: map<int, T>,
    type_of_pat: map<int, T>,
    // The owner's effect: the declared clause when written, else the
    // canonical union of the body's throw sites and callee throws (`never`
    // when nothing throws).
    throws_: T,
    // Definite check failures, keyed by the checked expression:
    // `(expected, actual)`. Recorded always (rust-analyzer's discipline).
    type_mismatches: map<int, (T, T)>,
    // Match expressions whose unguarded arms do not cover the scrutinee. The
    // expression types as Error; E0062 renders with witnesses.
    non_exhaustive_matches: map<int, bool>,
    // USER-FACING diagnostics: the shared vocabulary, payloads finalized to
    // plain types at finish. The check layer resolves the arena-id anchors
    // to spans.
    diagnostics: TirDiagnostic[],
    // Member accesses and callees resolved to their declarations, keyed by
    // the accessing expression (a call's entry sits on the CALLEE expr).
    // MIR consumes this instead of re-running resolution.
    member_resolutions: map<
        int,
        MemberResolutionField
            | MemberResolutionVariant
            | MemberResolutionFree
            | MemberResolutionMethod<T>
            | MemberResolutionInterfaceVirtualField<T>
    >,
    // Value-rooted multi-segment paths' per-segment ladders.
    path_resolutions: map<int, ResolvedPath<T>>,
    // Path expressions rooted at a top-level `let`, keyed by the path
    // expression. MIR loads the global from here; the init-order analysis
    // reads its dependency edges from here.
    global_roots: map<int, GlobalRoot>,
    // Per-call argument matching and solved instantiations, keyed by the
    // CALL expression.
    call_plans: map<int, CallPlan<T>>,
    // Durable lexical `let type T = ...` bindings, keyed by the statement
    // that evaluates and installs them.
    type_bindings: map<int, ScopedTypeBinding>,
    // Coercion steps per expression (r-a's `expr_adjustments` shape).
    expr_adjustments: map<int, Adjustment<T>[]>,

    // port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::empty @ d9be6853b
    // The empty result at the given effect seed. Also Rust's two `Default`
    // impls, whose only difference is which `never` they spell:
    // `InferenceResult.empty(root.types.TyNever {})` and
    // `InferenceResult.empty(pool.add(root.types.TyNever {}))`.
    function empty(throws_: T) -> Self {
        InferenceResult {
            type_of_expr: {},
            type_of_pat: {},
            throws_: throws_,
            type_mismatches: {},
            non_exhaustive_matches: {},
            diagnostics: [],
            member_resolutions: {},
            path_resolutions: {},
            global_roots: {},
            call_plans: {},
            type_bindings: {},
            expr_adjustments: {},
        }
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::callee_resolution @ d9be6853b
    // What the callee expression of a call resolves to. A value-rooted
    // `a.b.c()` records its ladder in `path_resolutions`, and the call
    // targets the last rung.
    function callee_resolution(
        self,
        callee: int,
    ) -> (
        MemberResolutionField
            | MemberResolutionVariant
            | MemberResolutionFree
            | MemberResolutionMethod<T>
            | MemberResolutionInterfaceVirtualField<T>
    )? throws never {
        let direct = self.member_resolutions.get(callee);
        if (direct != null) {
            return direct;
        }
        let segments = self.path_resolutions.get(callee)?.segments
            ?? return null;
        segments.at(segments.length() - 1)?.resolution
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::path_root_qualifiers @ d9be6853b
    // How many written segments of path `expr` qualify its root value: the
    // package and namespace segments of a qualified global
    // (`GlobalRoot.segments`), else `0`.
    function path_root_qualifiers(self, expr: int) -> int throws never {
        let global = self.global_roots.get(expr)
            ?? return 0;
        if (global.segments > 0) {
            global.segments - 1
        } else {
            0
        }
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::path_segment_at_written @ d9be6853b
    // The ladder entry of path `expr` for WRITTEN segment `written`: null for
    // the qualifiers of a qualified global, which name no value.
    function path_segment_at_written(
        self,
        expr: int,
        written: int,
    ) -> ResolvedPathSegment<T>? throws never {
        let path = self.path_resolutions.get(expr)
            ?? return null;
        let qualifiers = self.path_root_qualifiers(expr);
        if (written < qualifiers) {
            return null;
        }
        path.segments.at(written - qualifiers)
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::is_truthy_condition @ d9be6853b
    // Whether `expr` holds a condition the checker marked for truthiness
    // coercion (`Adjust.Truthy`).
    function is_truthy_condition(self, expr: int) -> bool throws never {
        let adjustments = self.expr_adjustments.get(expr)
            ?? return false;
        adjustments.some((adjustment) -> {
            adjustment.kind == Adjust.Truthy
        })
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::is_exhaustive_match @ d9be6853b
    // Whether the `match` at `expr` was proved exhaustive: absence from
    // `non_exhaustive_matches` is the proof.
    function is_exhaustive_match(self, expr: int) -> bool throws never {
        !self.non_exhaustive_matches.has(expr)
    }

    // port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::recorded_types @ d9be6853b
    // Every type this result records, with where it sits: table by table in
    // a fixed order, each table in id order. The one enumeration of the
    // recorded types: writeback's backstop asks it which types still carry
    // an open class, and nothing reads a recorded type it misses.
    // Restructured: the nested `sorted` and `resolution_types` are
    // `recorded_types_sorted` and `recorded_types_resolution_types`.
    function recorded_types(self) -> (RecordedSite, T)[] throws never {
        let recorded: (RecordedSite, T)[] = [];
        for (let entry in recorded_types_sorted(self.type_of_expr)) {
            recorded.push((RecordedSiteExpr { value: entry.0 }, entry.1));
        }
        for (let entry in recorded_types_sorted(self.type_of_pat)) {
            recorded.push((RecordedSitePat { value: entry.0 }, entry.1));
        }
        for (let entry in recorded_types_sorted(self.member_resolutions)) {
            let tys: T[] = [];
            recorded_types_resolution_types(entry.1, tys);
            for (let ty in tys) {
                recorded.push((RecordedSiteMemberResolution { value: entry.0 }, ty));
            }
        }
        for (let entry in recorded_types_sorted(self.path_resolutions)) {
            for (let segment in entry.1.segments) {
                recorded.push((RecordedSitePathSegment { value: entry.0 }, segment.ty));
                let resolution = segment.resolution;
                if (resolution != null) {
                    let tys: T[] = [];
                    recorded_types_resolution_types(resolution, tys);
                    for (let ty in tys) {
                        recorded.push((RecordedSitePathSegment { value: entry.0 }, ty));
                    }
                }
            }
        }
        for (let entry in recorded_types_sorted(self.call_plans)) {
            for (let ty in entry.1.type_args) {
                recorded.push((RecordedSiteCallPlan { value: entry.0 }, ty));
            }
            for (let slot in entry.1.slots) {
                recorded.push((RecordedSiteCallPlan { value: entry.0 }, slot.ty));
                recorded.push((RecordedSiteCallPlan { value: entry.0 }, slot.emission_ty));
            }
        }
        for (let entry in recorded_types_sorted(self.expr_adjustments)) {
            for (let adjustment in entry.1) {
                recorded.push((RecordedSiteAdjustment { value: entry.0 }, adjustment.target));
            }
        }
        recorded.push((RecordedSiteThrows {}, self.throws_));
        recorded
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::recorded_types::sorted @ d9be6853b
// A table's entries in key order.
function recorded_types_sorted<V>(table: map<int, V>) -> (int, V)[] throws never {
    table.keys()
        .sort_by_key((key) -> {
            key
        })
        .map((key) -> {
            (key, table[key])
        })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::recorded_types::resolution_types @ d9be6853b
// The types a member resolution carries: a virtual view, or a concrete
// method's frame arguments.
function recorded_types_resolution_types<T>(
    resolution: MemberResolutionField
        | MemberResolutionVariant
        | MemberResolutionFree
        | MemberResolutionMethod<T>
        | MemberResolutionInterfaceVirtualField<T>,
    out: T[],
) -> void throws never {
    match (resolution) {
        let r: MemberResolutionInterfaceVirtualField<T> => {
            out.push(r.view);
        },
        let r: MemberResolutionMethod<T> => {
            match (r.callee) {
                let c: MethodCalleeVirtual<T> => {
                    out.push(c.view);
                },
                let c: MethodCalleeConcrete<T> => {
                    root.base.extend(out, c.frame_type_args);
                },
                MethodCalleeInherent => {},
            }
        },
        MemberResolutionField | MemberResolutionVariant | MemberResolutionFree => {},
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceResult::first_error_site @ d9be6853b
// The first recorded type that carries the error sentinel, with where it
// sits; null when none does. A body whose program has no error diagnostic
// records none (`erase_infer`'s precondition), and code generation probes
// that before it reads the tables.
// Restructured: a free function, since only the plain instantiation has it.
function inference_result_first_error_site(
    result: InferenceResult<root.types.Ty>,
) -> (RecordedSite, root.types.Ty)? throws never {
    result.recorded_types().find((entry) -> {
        root.types.contains_ty_where(entry.1, (node) -> {
            node is root.types.TyError
        })
    })
}

// port: baml_compiler2_hir_ty/src/infer.rs::WorkingResult @ d9be6853b
// The working instantiation: the engine records in its native interned
// vocabulary; `finish` finalizes in place and then materializes into the
// public plain `InferenceResult` through the `materialize_ty` seam.
type WorkingResult = InferenceResult<int>;

// port: baml_compiler2_hir_ty/src/infer.rs::RecordedSite @ d9be6853b
// Where a type an `InferenceResult` records sits (`recorded_types`).
type RecordedSite = RecordedSiteExpr
    | RecordedSitePat
    | RecordedSiteMemberResolution
    | RecordedSitePathSegment
    | RecordedSiteCallPlan
    | RecordedSiteAdjustment
    | RecordedSiteThrows;

// An expression's type.
class RecordedSiteExpr {
    value: int,
}

// A pattern's type.
class RecordedSitePat {
    value: int,
}

// A member resolution on the accessing expression: a method's frame
// arguments, a virtual field's interface view.
class RecordedSiteMemberResolution {
    value: int,
}

// A segment of the value-rooted path at the expression: its type, or its
// member resolution's.
class RecordedSitePathSegment {
    value: int,
}

// The instantiation of the call at the expression: its type arguments and
// written slots.
class RecordedSiteCallPlan {
    value: int,
}

// A coercion step's target at the expression.
class RecordedSiteAdjustment {
    value: int,
}

// The owner's thrown type.
class RecordedSiteThrows {
}

// port: baml_compiler2_hir_ty/src/infer.rs::RecordedSite::location @ d9be6853b
// The expression or pattern a report about the type anchors at; the
// owner's thrown type has none of its own.
function recorded_site_location(site: RecordedSite) -> DiagnosticLocation? throws never {
    match (site) {
        let s: RecordedSiteExpr => DiagnosticLocationExpr { value: s.value },
        let s: RecordedSiteMemberResolution => DiagnosticLocationExpr { value: s.value },
        let s: RecordedSitePathSegment => DiagnosticLocationExpr { value: s.value },
        let s: RecordedSiteCallPlan => DiagnosticLocationExpr { value: s.value },
        let s: RecordedSiteAdjustment => DiagnosticLocationExpr { value: s.value },
        let s: RecordedSitePat => DiagnosticLocationPat { value: s.value },
        RecordedSiteThrows => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::SolveTier @ d9be6853b
// Which bounded-var classes a finish-fixpoint round may commit: the eager
// tier solves fully-ground classes only; the ground-subset tier is the
// quiescence-only fallback (see `finish`). Demand points
// (`structurally_resolve`) bypass the tiers.
enum SolveTier {
    Ground,
    GroundSubset,
}

// port: baml_compiler2_hir_ty/src/infer.rs::UnitSite @ d9be6853b
// An implicit unit (a block with no final expression, an `if` with no
// `else`, a bare `return;`) and where it reports.
class UnitSite {
    at: DiagnosticLocation,
    form: UnitSiteForm,
}

// port: baml_compiler2_hir_ty/src/infer.rs::UnitSiteForm @ d9be6853b
// An `ImplicitUnitForm` as inference meets it, before the type expected of
// it is known.
type UnitSiteForm = UnitSiteFormBlockWithoutTail
    | UnitSiteFormIfWithoutElse
    | UnitSiteFormBareReturn;

class UnitSiteFormBlockWithoutTail {
    // The block's last statement, when it is an expression: the value its
    // `;` discards may be the one the author meant the block to have.
    last_value: (int, int)?,
}

class UnitSiteFormIfWithoutElse {
}

class UnitSiteFormBareReturn {
}

// port: baml_compiler2_hir_ty/src/infer.rs::IfSide @ d9be6853b
// A side of an `if` / `if let`: its branch, or its `else` (written, or the
// fall-through when there is none).
enum IfSide {
    Then,
    Else,
}

// port: baml_compiler2_hir_ty/src/infer.rs::UnitVerdict @ d9be6853b
// What its context makes of an implicit unit (`unit_verdict`).
type UnitVerdict = UnitVerdictAdmitted
    | UnitVerdictUnjudged
    | UnitVerdictPending
    | UnitVerdictRefused;

// The context is the unit type itself, or is already diagnosed.
class UnitVerdictAdmitted {
}

// Nothing is expected of it: what its value joins decides (`join_units`).
class UnitVerdictUnjudged {
}

// The context may still solve to the unit type: judged at finish.
class UnitVerdictPending {
    value: int,
}

// The context rules the unit type out.
class UnitVerdictRefused {
    value: int,
}

// port: baml_compiler2_hir_ty/src/infer.rs::UnitDemand @ d9be6853b
// What an implicit unit must agree with, judged at finish on the solved
// types.
type UnitDemand = UnitDemandExpected | UnitDemandJoined;

// Its value flows into this type, which must be the unit type itself.
class UnitDemandExpected {
    value: int,
}

// Its value joins these others, which must hold nothing but `null`.
class UnitDemandJoined {
    value: int,
}

// port: baml_compiler2_hir_ty/src/infer.rs::Diverges @ d9be6853b
// Whether execution can proceed past the current point. `Maybe & Maybe`
// branch-combines to `Maybe`; a `return`/`throw` sets `Always`, and a block
// whose statements always diverge types as `never`.
enum Diverges {
    Maybe,
    Always,
}

// port: baml_compiler2_hir_ty/src/infer.rs::Diverges::or @ d9be6853b
// Sequential combination: diverged stays diverged.
function diverges_or(diverges: Diverges, other: Diverges) -> Diverges throws never {
    if (diverges == Diverges.Always || other == Diverges.Always) {
        Diverges.Always
    } else {
        Diverges.Maybe
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::Diverges::and @ d9be6853b
// Branch combination: all branches must diverge.
function diverges_and(diverges: Diverges, other: Diverges) -> Diverges throws never {
    if (diverges == Diverges.Always && other == Diverges.Always) {
        Diverges.Always
    } else {
        Diverges.Maybe
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::Expectation @ d9be6853b
// Contextual type information flowing DOWN the walk: the "check" half of
// bidirectional inference. Not a bare `int?`: the functions below encode
// when context may CONSTRAIN (emit `Sub`) versus merely INFORM (shape
// container literals, branch pass-through).
type Expectation = ExpectationNone
    | ExpectationHasType
    | ExpectationDiscarded
    | ExpectationErroneous;

class ExpectationNone {
}

class ExpectationHasType {
    value: int,
}

// The value is not observed: a statement expression, a loop or `defer`
// body. It constrains nothing, and nothing typed by a block-scoped
// `let type T = ...` binding can leave a block through it.
class ExpectationDiscarded {
}

// The context is an error-recovery sentinel, already diagnosed: the value
// is checked against nothing and reports nothing of its own, so a single
// mistake in a signature does not cascade into the body.
class ExpectationErroneous {
}

// port: baml_compiler2_hir_ty/src/infer.rs::Expectation::has_type @ d9be6853b
// The `Error` sentinel is never propagated as context. Top-level only
// (rust-analyzer's discipline): a nested sentinel must not discard the
// useful structure around it.
// Restructured: takes the pool `ty` indexes.
function expectation_has_type(pool: root.types.InferPool, ty: int) -> Expectation throws never {
    if (pool.kinds[ty] is root.types.TyError) {
        ExpectationErroneous {}
    } else {
        ExpectationHasType { value: ty }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::Expectation::only_has_type @ d9be6853b
function expectation_only_has_type(expectation: Expectation) -> int? throws never {
    match (expectation) {
        let e: ExpectationHasType => e.value,
        ExpectationNone | ExpectationDiscarded | ExpectationErroneous => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::Expectation::adjust_for_branches @ d9be6853b
// For if/match arms: drop the expectation when it resolves to a bare
// unsolved variable, so the first arm cannot over-constrain the rest: the
// arms JOIN at the merge point instead.
function expectation_adjust_for_branches(
    expectation: Expectation,
    table: root.hir_ty.infer.InferenceTable,
) -> Expectation throws never {
    match (expectation) {
        let e: ExpectationHasType => {
            let resolved = table.shallow_resolve(e.value);
            if (table.pool.kinds[resolved] is root.types.TyInferVar) {
                ExpectationNone {}
            } else {
                ExpectationHasType { value: resolved }
            }
        },
        ExpectationNone => ExpectationNone {},
        ExpectationDiscarded => ExpectationDiscarded {},
        ExpectationErroneous => ExpectationErroneous {},
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext @ d9be6853b
// One inference run over one body owner: the table, the accumulating
// result, and the bidirectional expression walk. Its methods are free
// functions taking `ctx: InferenceContext` first (infer.baml, the
// `infer_stubs_u<N>.baml` files, and `ns_infer/`).
class InferenceContext {
    db: root.hir.Db,
    facts: Facts,
    index: root.hir.FileSemanticIndex,
    // The owner body's scope: the key half mapping this body's expression
    // ids into the semantic index's per-file tables, and the guard that
    // keeps parameter lookups from crossing into lambda scopes.
    owner_scope: int?,
    // Parameter types for each lambda scope this run has walked, deduced by
    // `infer_lambda`; the lambda-scope analog of `param_tys`.
    lambda_params: map<int, int[]>,
    // The flow-narrowing overlay: a binding's refined type where a fact
    // about it is in force, consulted before `type_of_pat`. Grown eagerly
    // along the structured walk; see ns_infer/flow.baml.
    flow: root.hir_ty.infer.Flow,
    // Lowering for body-position type annotations, carrying the owner's
    // generic frame.
    lower: LowerCtx,
    // Active lexical runtime type names, innermost last. The declaration
    // lowering context remains immutable; body-owned type lowering forks it
    // with these rigid parameters.
    scoped_type_bindings: ScopedTypeBinding[],
    // The body this run infers. The full identity, not just its function,
    // lets a Session top-level let's malformed self-reference fail closed
    // instead of recursively asking for the inference result being built,
    // and tells a defaults arena from its function's body.
    owner: root.hir.BodyOwnerId,
    // The owner's parameter types, from its lowered signature, indexed by
    // declaration position.
    param_tys: int[],
    // Every type annotation written in this body, pre-lowered to span-free
    // `TypeRef`s.
    type_refs: root.hir.BodyTypeRefs,
    // The control frames the walk is inside, innermost last; the bottom
    // frame is the body owner's. Never empty (Rust's `nunny::Vec`).
    frames: root.hir_ty.infer.ControlFrame[],
    // The effect-channel stack: contributions from `throw` sites and callee
    // throws accumulate into the top. The bottom entry is the owner's
    // channel, carrying its declared clause; lambdas and `catch` bases push
    // their own.
    throws_channels: ThrowsChannel[],
    // Explicit, closed contracts whose coverage is checked after inference.
    throws_contracts: ThrowsContract[],
    // Every `_` hole instantiated as a fresh table variable, with the site
    // it was written at. A hole whose class is still unsolved at finalize
    // reports E0147 `CannotInferType` there instead of leaking a bare
    // `Infer` into lowering.
    hole_vars: (int, HoleAnchor)[],
    diagnosed_infer_vars: map<int, bool>,
    // One lowering per written body annotation: the let rule, the pattern
    // walk, and the backfill all read the SAME lowered type (and so the
    // same instantiated hole vars) for one `BodyTypeRefId`.
    annotation_cache: map<root.hir.BodyTypeRefId, int>,
    // Per-body memoization of ground canonical forms. Inference-bearing
    // types bypass it because their meaning changes as the table solves
    // variables.
    canonical_cache: root.types.InternedCanonicalCache,
    // The reports held quiet at the current point; see `Suppress`.
    suppressions: Suppressions,
    table: root.hir_ty.infer.InferenceTable,
    // The accumulators a probe rolls back; see `Journals`.
    journals: Journals,
    // The expression whose CHECK is currently relating types (r-a's
    // `ObligationCause`): obligations born inside a structural `sub`
    // recursion anchor their eventual diagnostic here.
    obligation_anchor: int?,
    // One frame per enclosing `OptionalChain` (chains nest through
    // arguments), owned by the chain BOUNDARY (TS short-circuit semantics,
    // where intermediate links see the non-null type).
    chains: ChainFrame[],
    // Shorthand value expressions and the exact property name they require.
    // Populated from the structural AST before inference so the ordinary
    // path resolver can select the specialized unresolved-name diagnostic.
    property_shorthand_values: map<int, string>,
    // Per open block, the bindings its `defer`s armed so far assign. The
    // block's normal exit and every `break`/`continue` edge through it run
    // those defers, so the facts about those bindings end there.
    block_defer_writes: map<root.hir.BindingId, bool>[],
    // What the walk decided about loops without an exit and jumps without a
    // loop, for the reachability pass.
    loop_verdicts: root.hir_ty.infer.LoopVerdicts,
    // The body's root expression, kept for finish-time anchors (the
    // extraneous-throws warning has no arena node of its own).
    body_root: int?,
    // Conditions and `!` operands whose type still carried an inference
    // variable at check time; decided at finish on the final type.
    pending_truthy_conditions: root.hir_ty.infer.PendingCondition[],
    // Expressions checked where only the unit type is admitted, with the
    // expression that produces their value and why the position is unit. A
    // mismatch recorded at one of them is a value that would be dropped
    // silently: it reports at the producer, naming the remedy.
    unit_positions: map<int, (int, UnitContext)>,
    // Implicit units that met no expectation, keyed by the expression whose
    // value they are: a block carries its tail's, and a join of nothing but
    // unit values carries its branches'. `join_units` reports one that
    // joins any other value.
    unjudged_units: map<int, UnitSite[]>,
    // The file whose body this context infers: the viewer every visibility
    // question is asked from, and the home of package-scoped lookups.
    owner_file: int,
    // The enclosing scope's PLAIN bound env for the written-type
    // well-formedness judgment on body annotations, built lazily (Rust's
    // `OnceCell`; null until built).
    wf_scope_env: map<root.types.ParamTy, root.types.InterfaceConstraint[]>?,
    // The pattern-reachability oracle's pre-folded alias map, built once per
    // inference on first use (Rust's `OnceCell`; null until built).
    overlap_aliases: map<root.types.DeclName, root.types.Ty>?,
    // A binding's runtime operand can be reached by more than one inference
    // road (for example the claim and body passes over a catch arm). Its
    // expression effects and diagnostics must still be inferred once.
    validated_runtime_operands: map<int, bool>,
    result: WorkingResult,

    // port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::new @ d9be6853b
    // A context for `owner`'s body, typed in `lower`'s environment with its
    // signature's parameter types, return expectation and `throws` clause.
    // The table indexes the compile's pool (`db.ty_memo.pool`), as `Facts`
    // does.
    function new(
        db: root.hir.Db,
        owner: root.hir.BodyOwnerId,
        lower: LowerCtx,
        param_tys: int[],
        return_ty: int?,
        clause: ThrowsClause,
    ) -> Self {
        let owner_file = root.hir.body_owner_id_file(db, owner);
        let scope = root.hir.body_scope(db, owner);
        let owner_scope = if (scope != null) {
            db.scopes.get(scope).id
        } else {
            null
        };
        let pool = db.ty_memo.pool;
        InferenceContext {
            db: db,
            facts: Facts.with_bounds(db, owner_declared_bounds(db, owner)),
            index: root.hir.file_semantic_index(db, owner_file),
            owner_scope: owner_scope,
            lambda_params: {},
            flow: {},
            lower: lower,
            scoped_type_bindings: [],
            owner: owner,
            param_tys: param_tys,
            type_refs: root.hir.body_type_refs(db, owner),
            frames: [root.hir_ty.infer.ControlFrame.owner(return_ty, owner_scope)],
            throws_channels: [ThrowsChannel { clause: clause, contributions: [] }],
            throws_contracts: [],
            hole_vars: [],
            diagnosed_infer_vars: {},
            annotation_cache: {},
            canonical_cache: root.types.InternedCanonicalCache.new(),
            suppressions: Suppressions.default(),
            table: root.hir_ty.infer.InferenceTable.new(pool),
            journals: Journals.default(),
            obligation_anchor: null,
            chains: [],
            property_shorthand_values: {},
            block_defer_writes: [],
            loop_verdicts: root.hir_ty.infer.LoopVerdicts.default(),
            body_root: null,
            pending_truthy_conditions: [],
            unit_positions: {},
            unjudged_units: {},
            owner_file: owner_file,
            wf_scope_env: null,
            overlap_aliases: null,
            validated_runtime_operands: {},
            result: InferenceResult.empty(pool.add(root.types.TyNever {})),
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::ty_mentions_param @ d9be6853b
// Whether `param` occurs anywhere in `ty`. Restructured: takes the pool; the
// `walk` with its `&mut bool` is a recursive `some`.
function ty_mentions_param(
    pool: root.types.InferPool,
    ty: int,
    param: root.types.ParamTy,
) -> bool throws never {
    match (pool.kinds[ty]) {
        let var: root.types.TyTypeVar if var.param == param => true,
        let kind: root.types.InferTy => {
            root.types.children_infer_ty(kind).some((child) -> {
                ty_mentions_param(pool, child, param)
            })
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::literal_base @ d9be6853b
// A literal's base primitive.
function literal_base(literal: root.base.Literal) -> root.types.InferTy throws never {
    match (literal) {
        root.base.LiteralInt => root.types.TyInt {},
        root.base.LiteralBigint => root.types.TyBigint {},
        root.base.LiteralFloat => root.types.TyFloat {},
        root.base.LiteralString => root.types.TyString {},
        root.base.LiteralBool => root.types.TyBool {},
    }
}

// added by U5: the catch-coverage and throws-contract judgements read throw
// facts as Rust's `BTreeSet<Ty>`; these two flatteners (from throw_facts.rs
// and package_interface.rs, which are not ported) and the set builder they
// share stand in for them.
// port: Rust's `BTreeSet<Ty>` built from an iterator: sorted by the derived
// `Ord` (`cmp_ty`), equal elements kept once.
function ty_btree_set(tys: root.types.Ty[]) -> root.types.Ty[] throws never {
    let out: root.types.Ty[] = [];
    for (let ty in tys.concat([]).sort_by(root.types.cmp_ty)) {
        let last = out.at(out.length() - 1);
        if (last == null || root.types.cmp_ty(last, ty) != baml.ops.Ordering.Equal) {
            out.push(ty);
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/throw_facts.rs::flatten_declared_ty_to_facts @ d9be6853b
// Flatten a DECLARED `throws` clause into its leaf facts: union members
// flattened, literal members widened to their primitives, `never` dropped.
// Restructured: the `BTreeSet` is a sorted, duplicate-free array, and the
// nested `collect_widened_leaf_types` pushes onto `out`.
function flatten_declared_ty_to_facts(ty: root.types.Ty) -> root.types.Ty[] throws never {
    let out: root.types.Ty[] = [];
    collect_widened_leaf_types(ty, out);
    ty_btree_set(out)
}

// port: baml_compiler2_hir_ty/src/throw_facts.rs::collect_widened_leaf_types @ d9be6853b
function collect_widened_leaf_types(ty: root.types.Ty, out: root.types.Ty[]) -> void throws never {
    match (ty) {
        let u: root.types.TyUnion => {
            for (let member in u.members) {
                collect_widened_leaf_types(member, out);
            }
        },
        let l: root.types.TyLiteral => {
            let widened: root.types.Ty = match (l.value) {
                root.base.LiteralInt => root.types.TyInt {},
                root.base.LiteralBigint => root.types.TyBigint {},
                root.base.LiteralFloat => root.types.TyFloat {},
                root.base.LiteralString => root.types.TyString {},
                root.base.LiteralBool => root.types.TyBool {},
            };
            out.push(widened);
        },
        root.types.TyNever => {},
        _ => {
            out.push(ty);
        },
    }
}

// port: baml_compiler2_hir_ty/src/package_interface.rs::flatten_ty_to_facts @ d9be6853b
// Decompose a throws surface into its leaf facts (union members flattened,
// `never` dropped: the empty set IS `never`). Restructured as
// `flatten_declared_ty_to_facts`.
function flatten_ty_to_facts(ty: root.types.Ty) -> root.types.Ty[] throws never {
    let out: root.types.Ty[] = [];
    collect_leaf_types(ty, out);
    ty_btree_set(out)
}

// port: baml_compiler2_hir_ty/src/package_interface.rs::collect_leaf_types @ d9be6853b
function collect_leaf_types(ty: root.types.Ty, out: root.types.Ty[]) -> void throws never {
    match (ty) {
        let u: root.types.TyUnion => {
            for (let member in u.members) {
                collect_leaf_types(member, out);
            }
        },
        root.types.TyNever => {},
        _ => {
            out.push(ty);
        },
    }
}
