// port: baml_type/src/interned.rs @ d9be6853b
//
// The hash-consed InferTy pool. Rust's `interned::Ty` is an Arc handle into a
// global sharded set; here a handle is an `int` into an InferPool, and two
// handles are equal exactly when their kinds are structurally equal. The kind
// (`InferTy`) and its satellites are generated in family.baml.
//
// Restructured:
// - `impl Ty` methods are InferPool methods taking the handle (`pool.has_infer(ty)`,
//   `pool.from_plain(t)`, `pool.optional(ty)`); `impl InferInterface` methods are
//   free functions with the `infer_interface_` prefix (BAML's
//   InferInterfaceConstraint is generated, so it takes no methods here).
// - `Ty::intern` is `InferPool.add`: the generated `intern_<member>` functions
//   call it by that name.
// - `TyVocabulary` / `InterfaceVocabulary` (one rewrite generic over the open
//   and closed vocabularies): the open side is InferPool methods and the
//   `infer_interface_` functions, the closed side ClosedTy / ClosedInterface
//   methods. `substitute_bindings` is written once per vocabulary.
//
// Not ported:
// - `InferVar`: a bare `int` (TyInferVar.var).
// - `TyData`, the sharded `pool()`, `Clone`/`Drop` eviction, pointer `Hash`,
//   `Debug`: one compile owns one pool and never frees entries. The primitive
//   singletons in `Ty::intern` exist to skip the pool lock; `add` dedups them
//   like any kind.
// - Accessors and one-liners: `Ty::kind` (`pool.kinds[ty]`), `Ty::flags`
//   (`pool.flags[ty]`), `Ty::is_closed` (`!pool.has_infer(ty)`), the leaf
//   helpers `Ty::int` ... `Ty::tuple` (`pool.add(TyInt {})`), the
//   `TyVocabulary for Ty::map_children` (`pool.add(map_children(pool.kinds[ty], f))`),
//   `InferFunctionParamTy::required` / `optional` (write the class),
//   `ClosedTy::as_ty` / `into_ty` / `closed_by_construction` / `Deref` /
//   `PartialEq<Ty>` (read or write `.ty`), `ClosedTy::from_plain`
//   (`ClosedTy { ty: pool.from_plain(t) }`), `ClosedTy::to_plain`
//   (`pool.to_plain_closed(closed.ty)`), `ClosedInterface::from_constraint`,
//   `as_reference` and `Deref` (`.reference`), and the interface
//   `substitute_bindings` defaults (`map_types` with each type's
//   `substitute_bindings`).
// - `for_each_child`: the generated `children_infer_ty` (same children, same
//   order).

// port: baml_type/src/interned.rs::TypeFlags @ d9be6853b
// Facts about a type computed once at intern time; the union of each node's
// own bit and all its children's flags.
// Contains an `InferVar` node (a live inference-table variable).
const HAS_INFER = 1;
// Contains an `Error` sentinel.
const HAS_ERROR = 2;
// Contains a named `TypeVar`.
const HAS_TYPEVAR = 4;
// Contains an unresolved associated-type projection.
const HAS_PROJECTION = 8;
// Contains a fresh (unwidened) literal.
const HAS_FRESH_LITERAL = 16;
// Contains a union node. Its members may be a spelling inference has not
// canonicalized yet, so consumers that relate or dispatch on structure
// re-canonicalize a ground tree before deciding.
const HAS_UNION = 32;

// port: baml_type/src/interned.rs::Ty @ d9be6853b
// The hash-cons pool. A handle is an index into `kinds` and `flags`; entries
// are one level deep (children are handles), so `index` hashes shallowly and
// structurally equal kinds share one handle.
class InferPool {
    kinds: InferTy[],
    flags: int[],
    // Keyed by `key_infer_ty(kind)`, not by the kind: a class-keyed map
    // lookup is ~3 us on the VM (ns_types/key.baml).
    index: map<string, int>,

    function new() -> Self {
        InferPool { kinds: [], flags: [], index: {} }
    }

    // port: baml_type/src/interned.rs::Ty::intern @ d9be6853b
    // Interns `kind`, returning the unique handle for it. Flags are computed
    // here; there is no other way to make a handle.
    // Restructured: named `add`, the name the generated interning calls.
    function add(self, kind: InferTy) -> int {
        let key = key_infer_ty(kind);
        let existing = self.index.get(key);
        if (existing != null) {
            return existing;
        }
        let ty = self.kinds.length();
        self.flags.push(self.compute_flags(kind));
        self.kinds.push(kind);
        self.index.set(key, ty);
        ty
    }

    // port: baml_type/src/interned.rs::compute_flags @ d9be6853b
    // `kind`'s own flag bit or'ed with every direct child's flags.
    function compute_flags(self, kind: InferTy) -> int throws never {
        let own = match (kind) {
            let l: TyLiteral => {
                if (l.freshness == Freshness.Fresh) {
                    HAS_FRESH_LITERAL
                } else {
                    0
                }
            },
            TyTypeVar => HAS_TYPEVAR,
            InferTyAssociatedTypeProjection => HAS_PROJECTION,
            TyError => HAS_ERROR,
            TyInferVar => HAS_INFER,
            InferTyUnion => HAS_UNION,
            _ => 0,
        };
        children_infer_ty(kind).reduce(
            (flags, child) -> {
                flags | self.flags[child]
            },
            own,
        )
    }

    // port: baml_type/src/interned.rs::Ty::has_infer @ d9be6853b
    // Whether this type still contains inference variables.
    function has_infer(self, ty: int) -> bool throws never {
        (self.flags[ty] & HAS_INFER) != 0
    }

    // port: baml_type/src/interned.rs::Ty::has_error @ d9be6853b
    // Whether this type contains an `Error` sentinel.
    function has_error(self, ty: int) -> bool throws never {
        (self.flags[ty] & HAS_ERROR) != 0
    }

    // port: baml_type/src/interned.rs::Ty::has_typevar @ d9be6853b
    // Whether this type contains a rigid type variable.
    function has_typevar(self, ty: int) -> bool throws never {
        (self.flags[ty] & HAS_TYPEVAR) != 0
    }

    // port: baml_type/src/interned.rs::Ty::has_projection @ d9be6853b
    // Whether this type contains an associated-type projection.
    function has_projection(self, ty: int) -> bool throws never {
        (self.flags[ty] & HAS_PROJECTION) != 0
    }

    // port: baml_type/src/interned.rs::Ty::has_union @ d9be6853b
    // Whether this type contains a union node.
    function has_union(self, ty: int) -> bool throws never {
        (self.flags[ty] & HAS_UNION) != 0
    }

    // port: baml_type/src/interned.rs::Ty::cmp @ d9be6853b
    // Structural, deterministic ordering (handle order would follow intern
    // order; canonical union sorting needs stability). Fast path on handle
    // identity, then the derived order of the kinds.
    function cmp(self, a: int, b: int) -> baml.ops.Ordering throws never {
        if (a == b) {
            return baml.ops.Ordering.Equal;
        }
        cmp_infer_ty(self, self.kinds[a], self.kinds[b])
    }

    // port: baml_type/src/interned.rs::Ty::from_plain @ d9be6853b
    // Interns the plain type's structure. Differs from the generated
    // `intern_ty` only at a projection, whose constraint goes through
    // `InferInterface::new` (bindings sorted by name).
    function from_plain(self, ty: Ty) -> int throws never {
        let interned_all = (tys: Ty[]) -> int[] {
            tys.map((t) -> {
                self.from_plain(t)
            })
        };
        let interned_bindings = (bindings: AssociatedType[]) -> InferAssociatedType[] {
            bindings.map((binding) -> {
                InferAssociatedType { name: binding.name, ty: self.from_plain(binding.ty) }
            })
        };
        let kind: InferTy = match (ty) {
            let x: TyInt
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
                | TyTypeVar
                | TyUnknown
                | TyNever
                | TyError =>
            {
                x
            },
            let x: TyClass => InferTyClass { name: x.name, args: interned_all(x.args) },
            let x: TyInterface => {
                InferTyInterface {
                    name: x.name,
                    args: interned_all(x.args),
                    associated_types: interned_bindings(x.associated_types),
                }
            },
            let x: TyList => InferTyList { elem: self.from_plain(x.elem) },
            let x: TyMap => {
                InferTyMap { key: self.from_plain(x.key), value: self.from_plain(x.value) }
            },
            let x: TyUnion => InferTyUnion { members: interned_all(x.members) },
            let x: TyTuple => InferTyTuple { items: interned_all(x.items) },
            let x: TyFunction => {
                InferTyFunction {
                    params: x.params.map((param) -> {
                        InferFunctionParamTy {
                            name: param.name,
                            ty: self.from_plain(param.ty),
                            mode: param.mode,
                        }
                    }),
                    ret: self.from_plain(x.ret),
                    throws_: self.from_plain(x.throws_),
                }
            },
            let x: TyFuture => {
                InferTyFuture { value: self.from_plain(x.value), error: self.from_plain(x.error) }
            },
            let x: TyAssociatedTypeProjection => {
                InferTyAssociatedTypeProjection {
                    base: self.from_plain(x.base),
                    interface_: infer_interface_new(
                        x.interface_.name,
                        interned_all(x.interface_.generics),
                        interned_bindings(x.interface_.associated_types),
                    ),
                    member: x.member,
                }
            },
        };
        self.add(kind)
    }

    // port: baml_type/src/interned.rs::Ty::to_plain_closed @ d9be6853b
    // The walk behind `ClosedTy::to_plain`: the plain structure of a handle
    // with no live inference variable. Differs from the generated
    // `resolve_ty` at a projection, whose constraint goes through
    // `Interface::new` (bindings sorted by name), and at an `InferVar`, which
    // panics instead of throwing.
    function to_plain_closed(self, ty: int) -> Ty throws never {
        let plain_all = (tys: int[]) -> Ty[] {
            tys.map((t) -> {
                self.to_plain_closed(t)
            })
        };
        let plain_bindings = (bindings: InferAssociatedType[]) -> AssociatedType[] {
            bindings.map((binding) -> {
                AssociatedType { name: binding.name, ty: self.to_plain_closed(binding.ty) }
            })
        };
        match (self.kinds[ty]) {
            let x: TyInt
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
                | TyTypeVar
                | TyUnknown
                | TyNever
                | TyError =>
            {
                x
            },
            let x: InferTyClass => TyClass { name: x.name, args: plain_all(x.args) },
            let x: InferTyInterface => {
                TyInterface {
                    name: x.name,
                    args: plain_all(x.args),
                    associated_types: plain_bindings(x.associated_types),
                }
            },
            let x: InferTyList => TyList { elem: self.to_plain_closed(x.elem) },
            let x: InferTyMap => {
                TyMap { key: self.to_plain_closed(x.key), value: self.to_plain_closed(x.value) }
            },
            let x: InferTyUnion => TyUnion { members: plain_all(x.members) },
            let x: InferTyTuple => TyTuple { items: plain_all(x.items) },
            let x: InferTyFunction => {
                TyFunction {
                    params: x.params.map((param) -> {
                        FunctionParamTy {
                            name: param.name,
                            ty: self.to_plain_closed(param.ty),
                            mode: param.mode,
                        }
                    }),
                    ret: self.to_plain_closed(x.ret),
                    throws_: self.to_plain_closed(x.throws_),
                }
            },
            let x: InferTyFuture => {
                TyFuture {
                    value: self.to_plain_closed(x.value),
                    error: self.to_plain_closed(x.error),
                }
            },
            let x: InferTyAssociatedTypeProjection => {
                TyAssociatedTypeProjection {
                    base: self.to_plain_closed(x.base),
                    interface_: InterfaceConstraint {
                        name: x.interface_.name,
                        generics: plain_all(x.interface_.generics),
                        associated_types: plain_bindings(x.interface_.associated_types).sort_by_key((binding) -> {
                            binding.name
                        }),
                    },
                    member: x.member,
                }
            },
            // Unreachable by invariant: `ClosedTy` construction checked the
            // cached HAS_INFER flag over the whole tree.
            TyInferVar => baml.sys.panic("ClosedTy invariant: no live inference variables"),
        }
    }

    // port: baml_type/src/interned.rs::TyVocabulary::substitute_bindings @ d9be6853b
    // The type with every type variable `bindings` binds replaced, by param
    // identity (a frame is not positional at use sites, unlike signature
    // instantiation). The open vocabulary's copy; ClosedTy has the closed one.
    function substitute_bindings(self, ty: int, bindings: map<ParamTy, int>) -> int {
        if (!self.has_typevar(ty)) {
            return ty;
        }
        if let v: TyTypeVar = self.kinds[ty] {
            let bound = bindings.get(v.param);
            if (bound != null) {
                return bound;
            }
        }
        self.add(
            map_children(self.kinds[ty], (child) -> {
                self.substitute_bindings(child, bindings)
            }),
        )
    }

    // port: baml_type/src/interned.rs::Ty::optional @ d9be6853b
    // `T?` is a flat `T | null` union.
    function optional(self, inner: int) -> int throws never {
        match (self.kinds[inner]) {
            let u: InferTyUnion => {
                if (
                    u.members.some((member) -> {
                        self.kinds[member] is TyNull
                    })
                ) {
                    inner
                } else {
                    self.add(InferTyUnion { members: u.members.concat([self.add(TyNull {})]) })
                }
            },
            TyNull => inner,
            _ => self.add(InferTyUnion { members: [inner, self.add(TyNull {})] }),
        }
    }
}

// port: baml_type/src/interned.rs::InferInterface::new @ d9be6853b
// Sorts `associated_types` by name, mirroring the plain satellite's
// order-insensitivity invariant (and `Interface::new`'s signature).
function infer_interface_new(
    name: DeclName,
    generics: int[],
    associated_types: InferAssociatedType[],
) -> InferInterfaceConstraint throws never {
    InferInterfaceConstraint {
        name: name,
        generics: generics,
        associated_types: associated_types.sort_by_key((binding) -> {
            binding.name
        }),
    }
}

// port: baml_type/src/interned.rs::InferInterface::of_ty @ d9be6853b
// The interface reference an existential type carries, when `ty` is one: the
// single extraction every consumer shares.
function infer_interface_of_ty(pool: InferPool, ty: int) -> InferInterfaceConstraint? throws never {
    match (pool.kinds[ty]) {
        let i: InferTyInterface => infer_interface_new(i.name, i.args, i.associated_types),
        _ => null,
    }
}

// port: baml_type/src/interned.rs::InferInterface::from_constraint @ d9be6853b
// From the plain algebra's constraint satellite (the `TypeContext` boundary).
function infer_interface_from_constraint(
    pool: InferPool,
    interface_: InterfaceConstraint,
) -> InferInterfaceConstraint throws never {
    infer_interface_new(
        interface_.name,
        interface_.generics.map((ty) -> {
            pool.from_plain(ty)
        }),
        interface_.associated_types.map((binding) -> {
            InferAssociatedType { name: binding.name, ty: pool.from_plain(binding.ty) }
        }),
    )
}

// port: baml_type/src/interned.rs::InferInterface::existential @ d9be6853b
// The existential type this reference denotes (`dyn`-style view).
function infer_interface_existential(pool: InferPool, reference: InferInterfaceConstraint) -> int {
    pool.add(
        InferTyInterface {
            name: reference.name,
            args: reference.generics,
            associated_types: reference.associated_types,
        },
    )
}

// port: baml_type/src/interned.rs::InterfaceVocabulary for InferInterface::map_types @ d9be6853b
// The reference rebuilt with every carried type (generic argument and
// associated-type pin) mapped through `f`; the head is untouched.
function infer_interface_map_types(
    reference: InferInterfaceConstraint,
    f: (int) -> int,
) -> InferInterfaceConstraint {
    infer_interface_new(
        reference.name,
        reference.generics.map(f),
        reference.associated_types.map((binding) -> {
            InferAssociatedType { name: binding.name, ty: f(binding.ty) }
        }),
    )
}

// port: baml_type/src/interned.rs::InferTy::map_children @ d9be6853b
// Rebuilds `kind` with every direct child replaced by `f(child)`
// (satellite-nested children included): the rebuild dual of
// `children_infer_ty`. Leaf kinds come back unchanged. Callers intern the
// result; short-circuit on the flags first when the fold cannot apply.
function map_children(kind: InferTy, f: (int) -> int) -> InferTy {
    let map_bindings = (bindings: InferAssociatedType[]) -> InferAssociatedType[] {
        bindings.map((binding) -> {
            InferAssociatedType { name: binding.name, ty: f(binding.ty) }
        })
    };
    match (kind) {
        let x: TyInt
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
            | TyTypeVar
            | TyUnknown
            | TyNever
            | TyError
            | TyInferVar =>
        {
            x
        },
        let x: InferTyClass => InferTyClass { name: x.name, args: x.args.map(f) },
        let x: InferTyInterface => {
            InferTyInterface {
                name: x.name,
                args: x.args.map(f),
                associated_types: map_bindings(x.associated_types),
            }
        },
        let x: InferTyList => InferTyList { elem: f(x.elem) },
        let x: InferTyMap => InferTyMap { key: f(x.key), value: f(x.value) },
        let x: InferTyUnion => InferTyUnion { members: x.members.map(f) },
        let x: InferTyTuple => InferTyTuple { items: x.items.map(f) },
        let x: InferTyFunction => {
            InferTyFunction {
                params: x.params.map((param) -> {
                    InferFunctionParamTy { name: param.name, ty: f(param.ty), mode: param.mode }
                }),
                ret: f(x.ret),
                throws_: f(x.throws_),
            }
        },
        let x: InferTyFuture => InferTyFuture { value: f(x.value), error: f(x.error) },
        let x: InferTyAssociatedTypeProjection => {
            InferTyAssociatedTypeProjection {
                base: f(x.base),
                interface_: InferInterfaceConstraint {
                    name: x.interface_.name,
                    generics: x.interface_.generics.map(f),
                    associated_types: map_bindings(x.interface_.associated_types),
                },
                member: x.member,
            }
        },
    }
}

// port: baml_type/src/interned.rs::OpenTy @ d9be6853b
// The type still contains a live inference variable; the boundary must
// defer, suppress, rename, or dispose instead of converting.
class OpenTy {
}

// port: baml_type/src/interned.rs::ClosedTy @ d9be6853b
// An interned type proven free of live inference variables: the only
// vocabulary that can leave the interned world. Every boundary that can meet
// an open type picks an explicit disposition on `OpenTy`: defer (relation
// oracles), suppress (exhaustiveness columns), rename for rendering
// (diagnostic payloads), or dispose (inference finalize, which diagnoses and
// substitutes the Error sentinel). The proof is by convention here: BAML has
// no private constructor.
class ClosedTy {
    ty: int,

    // port: baml_type/src/interned.rs::TryFrom<&Ty> for ClosedTy::try_from @ d9be6853b
    // One cached-flag test.
    function try_from(pool: InferPool, ty: int) -> ClosedTy throws OpenTy {
        if (pool.has_infer(ty)) {
            throw OpenTy {};
        }
        ClosedTy { ty: ty }
    }

    // port: baml_type/src/interned.rs::ClosedTy::for_each_child @ d9be6853b
    // Visits each direct child, closed: HAS_INFER is a subtree union, so every
    // child of a closed node is closed.
    function for_each_child(self, pool: InferPool, f: (ClosedTy) -> void) -> void {
        children_infer_ty(pool.kinds[self.ty]).for_each((child) -> {
            f(ClosedTy { ty: child })
        });
    }

    // port: baml_type/src/interned.rs::ClosedTy::map_children @ d9be6853b
    // Rebuilds the node with each child mapped through `f`, closed on both
    // sides: children are closed (subtree union), and the rebuilt node's head
    // is this node's head, which the closed invariant says is not a variable.
    function map_children(self, pool: InferPool, f: (ClosedTy) -> ClosedTy) -> ClosedTy {
        let kind = map_children(pool.kinds[self.ty], (child) -> {
            f(ClosedTy { ty: child }).ty
        });
        ClosedTy { ty: pool.add(kind) }
    }

    // port: baml_type/src/interned.rs::TyVocabulary::substitute_bindings @ d9be6853b
    // The closed vocabulary's copy of InferPool.substitute_bindings: a closed
    // template under closed bindings stays closed.
    function substitute_bindings(
        self,
        pool: InferPool,
        bindings: map<ParamTy, ClosedTy>,
    ) -> ClosedTy {
        if (!pool.has_typevar(self.ty)) {
            return self;
        }
        if let v: TyTypeVar = pool.kinds[self.ty] {
            let bound = bindings.get(v.param);
            if (bound != null) {
                return bound;
            }
        }
        self.map_children(pool, (child) -> {
            child.substitute_bindings(pool, bindings)
        })
    }
}

// port: baml_type/src/interned.rs::TryFrom<&InferInterface> for Interface::try_from @ d9be6853b
// The interface-constraint twin of the ClosedTy gate: a plain constraint
// exists for a reference iff every carried type is closed.
function interface_try_from(
    pool: InferPool,
    reference: InferInterfaceConstraint,
) -> InterfaceConstraint throws OpenTy {
    let closed = (ty: int) -> Ty throws OpenTy {
        pool.to_plain_closed(ClosedTy.try_from(pool, ty).ty)
    };
    InterfaceConstraint {
        name: reference.name,
        generics: reference.generics.map(closed),
        associated_types: reference.associated_types
            .map((binding) -> AssociatedType throws OpenTy {
                AssociatedType { name: binding.name, ty: closed(binding.ty) }
            })
            .sort_by_key((binding) -> {
                binding.name
            }),
    }
}

// port: baml_type/src/interned.rs::ClosedInterface @ d9be6853b
// The interface-constraint twin of ClosedTy: a reference whose carried types
// are all free of live inference variables, so a boundary that hands out
// declaration-side references converts to the plain vocabulary totally.
class ClosedInterface {
    reference: InferInterfaceConstraint,

    // port: baml_type/src/interned.rs::TryFrom<&InferInterface> for ClosedInterface::try_from @ d9be6853b
    function try_from(
        pool: InferPool,
        reference: InferInterfaceConstraint,
    ) -> ClosedInterface throws OpenTy {
        let closed = reference.generics.every((ty) -> {
            !pool.has_infer(ty)
        })
            && reference.associated_types.every((binding) -> {
                !pool.has_infer(binding.ty)
            });
        if (!closed) {
            throw OpenTy {};
        }
        ClosedInterface { reference: reference }
    }

    // port: baml_type/src/interned.rs::ClosedInterface::new @ d9be6853b
    // A reference assembled from closed parts, total into the closed world.
    function new(
        name: DeclName,
        generics: ClosedTy[],
        associated_types: (string, ClosedTy)[],
    ) -> ClosedInterface throws never {
        ClosedInterface {
            reference: infer_interface_new(
                name,
                generics.map((ty) -> {
                    ty.ty
                }),
                associated_types.map((binding) -> {
                    InferAssociatedType { name: binding.0, ty: binding.1.ty }
                }),
            ),
        }
    }

    // port: baml_type/src/interned.rs::ClosedInterface::to_plain @ d9be6853b
    // Materializes the plain constraint, total by the closed invariant.
    function to_plain(self, pool: InferPool) -> InterfaceConstraint throws never {
        interface_try_from(pool, self.reference) catch (e) {
            OpenTy => baml.sys.panic("ClosedInterface invariant: no live inference variables"),
        }
    }

    // port: baml_type/src/interned.rs::InterfaceVocabulary for ClosedInterface::map_types @ d9be6853b
    // Every carried type of a closed reference is closed, and a closed image
    // keeps the reference closed.
    function map_types(self, f: (ClosedTy) -> ClosedTy) -> ClosedInterface {
        ClosedInterface {
            reference: infer_interface_map_types(self.reference, (ty) -> {
                f(ClosedTy { ty: ty }).ty
            }),
        }
    }
}

// port: baml_type/src/interned.rs::Ty::cmp @ d9be6853b
// The derived `Ord` of InferTy that `Ty::cmp` falls back to: the Rust
// discriminant first, then the fields in order, child handles through
// `InferPool.cmp`. The derived orders of the field types (DeclName, Literal,
// ParamTy, the satellites) are spelled out below, as Rust derives them.
function cmp_infer_ty(pool: InferPool, a: InferTy, b: InferTy) -> baml.ops.Ordering throws never {
    let by_variant = infer_ty_discriminant(a).cmp(infer_ty_discriminant(b));
    if (by_variant != baml.ops.Ordering.Equal) {
        return by_variant;
    }
    let tys = (x: int[], y: int[]) -> baml.ops.Ordering {
        cmp_list(x, y, (p, q) -> {
            pool.cmp(p, q)
        })
    };
    let bindings = (x: InferAssociatedType[], y: InferAssociatedType[]) -> baml.ops.Ordering {
        cmp_list(x, y, (p, q) -> {
            cmp_then(p.name.cmp(q.name), () -> {
                pool.cmp(p.ty, q.ty)
            })
        })
    };
    match (a, b) {
        (let x: TyMedia, let y: TyMedia) => {
            cmp_media_kind(x.kind, y.kind)
        },
        (let x: TyLiteral, let y: TyLiteral) => {
            cmp_then(cmp_literal(x.value, y.value), () -> {
                cmp_freshness(x.freshness, y.freshness)
            })
        },
        (let x: InferTyClass, let y: InferTyClass) => {
            cmp_then(cmp_decl_name(x.name, y.name), () -> {
                tys(x.args, y.args)
            })
        },
        (let x: InferTyInterface, let y: InferTyInterface) => {
            cmp_then(cmp_decl_name(x.name, y.name), () -> {
                cmp_then(tys(x.args, y.args), () -> {
                    bindings(x.associated_types, y.associated_types)
                })
            })
        },
        (let x: TyEnum, let y: TyEnum) => cmp_decl_name(x.name, y.name),
        (let x: TyEnumVariant, let y: TyEnumVariant) => {
            cmp_then(cmp_decl_name(x.name, y.name), () -> {
                x.variant.cmp(y.variant)
            })
        },
        (let x: InferTyList, let y: InferTyList) => pool.cmp(x.elem, y.elem),
        (let x: InferTyMap, let y: InferTyMap) => {
            cmp_then(pool.cmp(x.key, y.key), () -> {
                pool.cmp(x.value, y.value)
            })
        },
        (let x: InferTyUnion, let y: InferTyUnion) => tys(x.members, y.members),
        (let x: InferTyTuple, let y: InferTyTuple) => tys(x.items, y.items),
        (let x: InferTyFunction, let y: InferTyFunction) => {
            let params = cmp_list(x.params, y.params, (p, q) -> {
                cmp_then(cmp_optional_string(p.name, q.name), () -> {
                    cmp_then(pool.cmp(p.ty, q.ty), () -> {
                        cmp_function_param_mode(p.mode, q.mode)
                    })
                })
            });
            cmp_then(params, () -> {
                cmp_then(pool.cmp(x.ret, y.ret), () -> {
                    pool.cmp(x.throws_, y.throws_)
                })
            })
        },
        (let x: InferTyFuture, let y: InferTyFuture) => {
            cmp_then(pool.cmp(x.value, y.value), () -> {
                pool.cmp(x.error, y.error)
            })
        },
        (let x: TyTypeAlias, let y: TyTypeAlias) => cmp_decl_name(x.name, y.name),
        (let x: TyTypeVar, let y: TyTypeVar) => {
            cmp_then(x.param.index.cmp(y.param.index), () -> {
                x.param.name.cmp(y.param.name)
            })
        },
        (let x: InferTyAssociatedTypeProjection, let y: InferTyAssociatedTypeProjection) => {
            let ix = x.interface_;
            let iy = y.interface_;
            cmp_then(pool.cmp(x.base, y.base), () -> {
                cmp_then(cmp_decl_name(ix.name, iy.name), () -> {
                    cmp_then(tys(ix.generics, iy.generics), () -> {
                        cmp_then(bindings(ix.associated_types, iy.associated_types), () -> {
                            x.member.cmp(y.member)
                        })
                    })
                })
            })
        },
        (let x: TyInferVar, let y: TyInferVar) => x.var.cmp(y.var),
        // Same fieldless variant.
        _ => baml.ops.Ordering.Equal,
    }
}

// port: baml_type/src/interned.rs::Ty::cmp @ d9be6853b
// `first`, or `rest()` when `first` is Equal: one step of a derived
// lexicographic order.
function cmp_then(first: baml.ops.Ordering, rest: () -> baml.ops.Ordering) -> baml.ops.Ordering {
    match (first) {
        baml.ops.Ordering.Equal => rest(),
        _ => first,
    }
}

// port: baml_type/src/interned.rs::Ty::cmp @ d9be6853b
// InferTy's Rust discriminants (family.rs), which order its variants.
function infer_ty_discriminant(kind: InferTy) -> int throws never {
    match (kind) {
        TyInt => 0,
        TyBigint => 1,
        TyFloat => 2,
        TyString => 3,
        TyBool => 4,
        TyNull => 5,
        TyUint8Array => 6,
        TyMedia => 7,
        TyLiteral => 8,
        InferTyClass => 9,
        InferTyInterface => 10,
        TyEnum => 11,
        TyEnumVariant => 12,
        InferTyList => 13,
        InferTyMap => 14,
        InferTyUnion => 15,
        InferTyFunction => 16,
        InferTyFuture => 17,
        TyRustType => 18,
        TyType => 19,
        TyResource => 20,
        TyPromptAst => 21,
        TyTypeAlias => 24,
        TyTypeVar => 25,
        InferTyAssociatedTypeProjection => 26,
        TyUnknown => 27,
        TyNever => 28,
        TyError => 30,
        TyInferVar => 37,
        InferTyTuple => 38,
    }
}
