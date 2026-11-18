// port: baml_compiler2_hir_ty/src/lower.rs @ d9be6853b
//
// Declaration lowering: span-free HIR `TypeRef`s to `LoweringTy` / `Ty`, with
// name resolution (rust-analyzer's `TyLoweringContext` analog). Aliases stay
// nominal at lowering; `T?` is sugar for `T | null`; enum variants read as
// literal types through the path fallback; generic arity is enforced by
// truncate / pad-with-`Error`. Every failure lowers to the `Error` sentinel
// and records its diagnostic in the context's sink.
//
// Restructured (BAML forces it):
// - `LowerCtx`'s `RefCell`/`Cell` fields are plain fields (classes are
//   references); the `with_*` builders mutate and return the context, which
//   Rust moves.
// - `lower_type_ref` / `lower_type_ref_at` are one method with
//   `position = TypePosition.Existential`; likewise
//   `lower_type_ref_with_diagnostics` / `lower_type_ref_at_with_diagnostics`.
// - Interned-type functions (`substitute_params`, `class_ty`, ...) take the
//   pool their handles index (`db.ty_memo.pool` where a Db is at hand).
// - `class_ty` is `class_ty_interned`: `hir_ty` already has a test helper
//   `class_ty` (exhaustiveness_test.baml), and BAML has one namespace where
//   Rust has two modules.
// - A `(Name, LoweringTy)` binding list is a `(string, LoweringTy)[]`; an
//   `FxHashMap<ParamTy, Vec<Interface>>` is a `map<ParamTy, InterfaceConstraint[]>`.
// Not ported (one-line forwards or accessors): `LowerCtx::namespace_context`
// and `generic_params` (read `ns_context` / `generic_params`),
// `qualify_definition` (call `qualify`), and `function_signature` (read
// `function_signature_with_diagnostics(db, f).signature`).

// port: baml_compiler2_hir_ty/src/lower.rs::ResolvedTypeDefinition @ d9be6853b
type ResolvedTypeDefinition = ResolvedTypeDefinitionSource | ResolvedTypeDefinitionExported;

class ResolvedTypeDefinitionSource {
    value: root.hir.Definition,
}

class ResolvedTypeDefinitionExported {
    value: ExportedType,
}

// port: baml_compiler2_hir_ty/src/lower.rs::LoweringDiag @ d9be6853b
// One diagnostic recorded while lowering, anchored at its `TypeRefId`; the
// caller resolves the id through the source map paired with the store.
class LoweringDiag {
    type_ref: int,
    kind: LoweringDiagKind,
}

// port: baml_compiler2_hir_ty/src/lower.rs::LoweringDiagKind @ d9be6853b
type LoweringDiagKind = LoweringDiagKindUnresolved
    | LoweringDiagKindInvalidMapKey
    | LoweringDiagKindProjection
    | LoweringDiagKindWrongArgCount
    | LoweringDiagKindFnTypeMissingThrows
    | LoweringDiagKindHoleNotAllowed;

// The written path resolved nowhere (E0002).
class LoweringDiagKindUnresolved {
    name: string,
    // "Did you mean" candidates, each a fully qualified `root...` path.
    suggestions: string[],
}

// A map key type without a `baml.Hash` implementation.
class LoweringDiagKindInvalidMapKey {
    key: root.types.Ty,
}

// A type error already in the shared vocabulary, carried verbatim.
class LoweringDiagKindProjection {
    value: TirTypeError,
}

// Written type-argument count disagrees with the declaration.
class LoweringDiagKindWrongArgCount {
    name: string,
    expected: int,
    got: int,
}

// A written function type without a `throws` clause where elaboration could
// not legalize it (E0151).
class LoweringDiagKindFnTypeMissingThrows {
}

// An inference hole in a position with nothing to infer it from.
class LoweringDiagKindHoleNotAllowed {
    reason: NoInferReason,
}

// port: baml_compiler2_hir_ty/src/lower.rs::NoInferReason @ d9be6853b
// Why a position forbids an inference hole.
enum NoInferReason {
    // An interface method's signature (a dispatch contract).
    InterfaceSignature,
    // An `extends` bound of a `let type T extends I = ...` binding.
    TypeBinding,
    // The subject of an associated-type projection.
    ProjectionBase,
}

// port: baml_compiler2_hir_ty/src/lower.rs::HolePolicy @ d9be6853b
// Whether the types a `LowerCtx` lowers may contain an inference hole.
type HolePolicy = HolePolicyAllowed | HolePolicyForbidden;

class HolePolicyAllowed {
}

class HolePolicyForbidden {
    reason: NoInferReason,
}

// port: baml_compiler2_hir_ty/src/lower.rs::MAX_SUGGESTIONS @ d9be6853b
// How many "did you mean" candidates an unresolved path reports.
const MAX_SUGGESTIONS: int = 5;

// port: baml_compiler2_hir_ty/src/lower.rs::TypePosition @ d9be6853b
// Where a type reference stands. An existential denotes one complete
// interface instantiation (omitted defaulted associated types fill eagerly,
// a member with neither pin nor default is diagnosed); a constraint head
// pins only what it writes; an extraction contract is an existential whose
// omitted outer `throws` becomes the runtime wildcard.
enum TypePosition {
    Existential,
    ConstraintHead,
    ExtractionContract,
}

// port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx @ d9be6853b
// Everything needed to lower type syntax written in one file, for one
// generic frame.
class LowerCtx {
    // A short-lived sink, used only by the one-shot diagnostic lowerings.
    diags: LoweringDiag[]?,
    // The innermost `TypeRefId` lowering now: where an unresolved path reports.
    current_ref: int?,
    db: root.hir.Db,
    package_items: root.hir.PackageItems,
    ns_context: string[],
    // The flattened generic frame, innermost params last.
    generic_params: root.types.ParamTy[],
    // The concrete `Self` an enclosing impl provides.
    self_ty: root.types.LoweringTy?,
    // The impl's written interface target, the qualifier `Self.Member`
    // projects through in an implements-block method.
    self_impl_target: root.types.InterfaceConstraint?,
    // The frame's declared interface bounds, each param's conjunction.
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    holes: HolePolicy,

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::record_arity @ d9be6853b
    function record_arity(self, name: string, got: int, expected: int) -> void throws never {
        if (got == expected) {
            return;
        }
        let diags = self.diags;
        let type_ref = self.current_ref;
        if (diags != null && type_ref != null) {
            diags.push(
                LoweringDiag {
                    type_ref: type_ref,
                    kind: LoweringDiagKindWrongArgCount { name: name, expected: expected, got: got },
                },
            );
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::record_no_infer @ d9be6853b
    // Record a hole this context's policy forbids, at the hole's own ref.
    function record_no_infer(self, reason: NoInferReason) -> void throws never {
        let diags = self.diags;
        let type_ref = self.current_ref;
        if (diags != null && type_ref != null) {
            diags.push(
                LoweringDiag {
                    type_ref: type_ref,
                    kind: LoweringDiagKindHoleNotAllowed { reason: reason },
                },
            );
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::take_diagnostics @ d9be6853b
    function take_diagnostics(self) -> LoweringDiag[] throws never {
        let diags = self.diags
            ?? return [];
        self.diags = [];
        diags
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::with_frame @ d9be6853b
    function with_frame(self, frame: root.types.ParamTy[]) -> LowerCtx throws never {
        self.generic_params = frame;
        self
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::with_impl_target @ d9be6853b
    function with_impl_target(
        self,
        target: root.types.InterfaceConstraint?,
    ) -> LowerCtx throws never {
        self.self_impl_target = target;
        self
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::with_self_ty @ d9be6853b
    // Owner `Self` types are declaration-side plain types, widened into the
    // lowering vocabulary.
    function with_self_ty(self, self_ty: root.types.Ty?) -> LowerCtx throws never {
        self.self_ty
            = if (self_ty != null) {
                root.types.widen_ty_to_lowering_ty(self_ty)
            } else {
                null
            };
        self
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::with_bounds @ d9be6853b
    function with_bounds(
        self,
        bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    ) -> LowerCtx throws never {
        self.bounds = bounds;
        self
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::add_bounds @ d9be6853b
    // Bound one more rigid parameter (a body's `let type T extends I = ...`).
    function add_bounds(
        self,
        param: root.types.ParamTy,
        bounds: root.types.InterfaceConstraint[],
    ) -> void throws never {
        self.bounds[param] = bounds;
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::with_holes_forbidden @ d9be6853b
    function with_holes_forbidden(self, reason: NoInferReason) -> LowerCtx throws never {
        self.holes = HolePolicyForbidden { reason: reason };
        self
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_type_ref_at @ d9be6853b
    // Also `lower_type_ref` (the existential default). The position applies
    // to the reference's head only; nested references are existential.
    function lower_type_ref(
        self,
        store: root.hir.TypeRefStore,
        id: int,
        position: TypePosition = TypePosition.Existential,
    ) -> root.types.LoweringTy throws never {
        let saved = self.current_ref;
        self.current_ref = id;
        let ty = self.lower_type_ref_inner(store, id, position);
        self.current_ref = saved;
        ty
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_type_ref_at_with_diagnostics @ d9be6853b
    // Also `lower_type_ref_with_diagnostics` (the existential default). Lower
    // one tree and return only the diagnostics it produced.
    function lower_type_ref_with_diagnostics(
        self,
        store: root.hir.TypeRefStore,
        id: int,
        position: TypePosition = TypePosition.Existential,
    ) -> (root.types.LoweringTy, LoweringDiag[]) throws never {
        self.lower_type_ref_with_overlay_and_diagnostics(store, id, position, [], self.holes)
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_type_ref_with_overlay @ d9be6853b
    // Lower one body-owned type through a lexical rigid-parameter overlay;
    // the fork's diagnostics merge back into this context's sink.
    function lower_type_ref_with_overlay(
        self,
        store: root.hir.TypeRefStore,
        id: int,
        position: TypePosition,
        overlay: root.types.ParamTy[],
    ) -> root.types.LoweringTy throws never {
        if (overlay.length() == 0) {
            return self.lower_type_ref(store, id, position = position);
        }
        let fork = self.fork_with_overlay(overlay);
        let ty = fork.lower_type_ref(store, id, position = position);
        self.merge_fork_diagnostics(fork);
        ty
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_type_ref_with_overlay_and_diagnostics @ d9be6853b
    function lower_type_ref_with_overlay_and_diagnostics(
        self,
        store: root.hir.TypeRefStore,
        id: int,
        position: TypePosition,
        overlay: root.types.ParamTy[],
        holes: HolePolicy,
    ) -> (root.types.LoweringTy, LoweringDiag[]) throws never {
        let fork = self.fork_with_overlay_and_diagnostics(overlay);
        fork.holes = holes;
        let ty = fork.lower_type_ref(store, id, position = position);
        (ty, fork.take_diagnostics())
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_type_path_with_overlay @ d9be6853b
    function lower_type_path_with_overlay(
        self,
        head: root.hir.PathHead,
        segments: string[],
        overlay: root.types.ParamTy[],
    ) -> root.types.LoweringTy throws never {
        if (overlay.length() == 0) {
            return self.lower_type_path(head, segments);
        }
        let fork = self.fork_with_overlay(overlay);
        let ty = fork.lower_type_path(head, segments);
        self.merge_fork_diagnostics(fork);
        ty
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::fork_with_overlay @ d9be6853b
    function fork_with_overlay(self, overlay: root.types.ParamTy[]) -> LowerCtx throws never {
        LowerCtx {
            diags: if (self.diags != null) {
                []
            } else {
                null
            },
            current_ref: null,
            db: self.db,
            package_items: self.package_items,
            ns_context: self.ns_context,
            generic_params: self.generic_params.concat(overlay),
            self_ty: self.self_ty,
            self_impl_target: self.self_impl_target,
            bounds: self.plain_bounds_env(),
            holes: self.holes,
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::fork_with_overlay_and_diagnostics @ d9be6853b
    function fork_with_overlay_and_diagnostics(
        self,
        overlay: root.types.ParamTy[],
    ) -> LowerCtx throws never {
        let fork = self.fork_with_overlay(overlay);
        fork.diags = [];
        fork
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::merge_fork_diagnostics @ d9be6853b
    function merge_fork_diagnostics(self, fork: LowerCtx) -> void throws never {
        let diags = self.diags;
        if (diags != null) {
            root.base.extend(diags, fork.take_diagnostics());
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_type_ref_inner @ d9be6853b
    function lower_type_ref_inner(
        self,
        store: root.hir.TypeRefStore,
        id: int,
        position: TypePosition,
    ) -> root.types.LoweringTy throws never {
        let extraction_contract = position == TypePosition.ExtractionContract;
        let head_position = if (extraction_contract) {
            TypePosition.Existential
        } else {
            position
        };
        match (store.get(id).kind) {
            root.hir.TypeRefKindInt => root.types.TyInt {},
            root.hir.TypeRefKindBigint => root.types.TyBigint {},
            root.hir.TypeRefKindFloat => root.types.TyFloat {},
            root.hir.TypeRefKindString => root.types.TyString {},
            root.hir.TypeRefKindBool => root.types.TyBool {},
            root.hir.TypeRefKindNull => root.types.TyNull {},
            root.hir.TypeRefKindNever => root.types.TyNever {},
            root.hir.TypeRefKindUint8Array => root.types.TyUint8Array {},
            let k: root.hir.TypeRefKindMedia => root.types.TyMedia { kind: k.kind },
            root.hir.TypeRefKindUnknown => root.types.TyUnknown {},
            root.hir.TypeRefKindType => root.types.TyType {},
            root.hir.TypeRefKindRust => root.types.TyRustType {},
            let k: root.hir.TypeRefKindOptional => {
                root.types.optional_lowering_ty(self.lower_type_ref(store, k.inner))
            },
            let k: root.hir.TypeRefKindList => {
                root.types.LoweringTyList { elem: self.lower_type_ref(store, k.inner) }
            },
            let k: root.hir.TypeRefKindMap => {
                let key = self.checked_map_key(self.lower_type_ref(store, k.key));
                root.types.LoweringTyMap { key: key, value: self.lower_type_ref(store, k.value) }
            },
            let k: root.hir.TypeRefKindUnion => {
                root.types.LoweringTyUnion {
                    members: k.variants.map((variant) -> {
                        self.lower_type_ref(store, variant)
                    }),
                }
            },
            let k: root.hir.TypeRefKindTuple => {
                root.types.LoweringTyTuple {
                    items: k.elements.map((element) -> {
                        self.lower_type_ref(store, element)
                    }),
                }
            },
            let k: root.hir.TypeRefKindLiteral => {
                root.types.TyLiteral { value: k.value, freshness: root.types.Freshness.Regular }
            },
            let k: root.hir.TypeRefKindFunction => {
                let params = k.params.map((param) -> {
                    root.types.LoweringFunctionParamTy {
                        name: param.name,
                        ty: self.lower_type_ref(store, param.ty),
                        mode: if (param.optional) {
                            root.types.FunctionParamMode.Optional
                        } else {
                            root.types.FunctionParamMode.Required
                        },
                    }
                });
                let ret = self.lower_type_ref(store, k.ret);
                // Elaboration rewrites every legal omitted throws into a
                // synthetic effect param; a survivor here is the illegal
                // position: it recovers as `never` and the sink names it.
                let written = k.throws_;
                let throws_: root.types.LoweringTy = if (written != null) {
                    self.lower_type_ref(store, written)
                } else if (extraction_contract) {
                    root.types.TyUnknown {}
                } else {
                    let diags = self.diags;
                    let type_ref = self.current_ref;
                    if (diags != null && type_ref != null) {
                        diags.push(
                            LoweringDiag {
                                type_ref: type_ref,
                                kind: LoweringDiagKindFnTypeMissingThrows {},
                            },
                        );
                    }
                    root.types.TyNever {}
                };
                root.types.LoweringTyFunction { params: params, ret: ret, throws_: throws_ }
            },
            let k: root.hir.TypeRefKindPath => {
                let args = k.generic_args.map((arg) -> {
                    self.lower_type_ref(store, arg)
                });
                let bindings = k.associated_type_bindings.map((binding) -> {
                    (binding.name, self.lower_type_ref(store, binding.ty))
                });
                let head = self.type_path_head(k.path.origin, k.path.segments);
                self.lower_path(head, k.path.segments, args, bindings, head_position)
            },
            // A projection node: `T.Output` / `(T as I).Output`.
            let k: root.hir.TypeRefKindAssociatedTypeProjection => {
                let base_ty = self.lower_type_ref(store, k.base);
                let written_interface = k.interface_;
                // The `Self`-rooted fast path keeps the impl-target
                // qualifier road.
                if (written_interface == null) {
                    let head = self.projection_interface_for(base_ty, k.member);
                    if (head != null) {
                        return root.types.LoweringTyAssociatedTypeProjection {
                            base: base_ty,
                            interface_: head,
                            member: k.member,
                        };
                    }
                }
                // The qualifier names the interface to project through: a
                // constraint shape, not an existential value.
                let explicit = if (written_interface != null) {
                    self.lower_type_ref(
                        store,
                        written_interface,
                        position = TypePosition.ConstraintHead,
                    )
                } else {
                    null
                };
                // Determination needs closed shapes: a hole in the base or the
                // qualifier cannot name an interface.
                let base_plain = root.types.narrow_lowering_ty_to_ty(base_ty) catch (e) {
                    root.types.NarrowError => null,
                };
                let explicit_closed = true;
                let explicit_plain: root.types.Ty? = null;
                if (explicit != null) {
                    explicit_plain
                        = root.types.narrow_lowering_ty_to_ty(explicit) catch (e) {
                            root.types.NarrowError => {
                                explicit_closed = false;
                                null
                            },
                        };
                }
                if (base_plain != null && explicit_closed) {
                    let lowered = root.hir_ty.interfaces.lower_projection(
                        self.db,
                        self.package_items.root_id,
                        self.plain_bounds_env(),
                        base_plain,
                        explicit_plain,
                        k.member,
                    );
                    self.record_type_errors(lowered.diagnostics);
                    return root.types.widen_ty_to_lowering_ty(lowered.ty);
                }
                self.record_no_infer(NoInferReason.ProjectionBase);
                root.types.TyError {}
            },
            // `_` lowers to the hole node where the position can fill it;
            // where it cannot, the context says so and the hole becomes the
            // error sentinel here, with its own span.
            root.hir.TypeRefKindInfer => {
                match (self.holes) {
                    HolePolicyAllowed => root.types.TyInfer {},
                    let forbidden: HolePolicyForbidden => {
                        self.record_no_infer(forbidden.reason);
                        root.types.TyError {}
                    },
                }
            },
            // `Missing` is an omitted annotation and `Error` an unparsable
            // one: the parse reported both.
            root.hir.TypeRefKindError | root.hir.TypeRefKindMissing => root.types.TyError {},
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::probe_projection_prefix @ d9be6853b
    // A projection's prefix resolved as a written type path, with the sink
    // muted; null for prefixes that name no type, and for enum heads.
    function probe_projection_prefix(
        self,
        head: root.hir.PathHead,
        prefix: string[],
    ) -> root.types.LoweringTy? throws never {
        let is_enum = match (self.resolve_type(head, prefix)) {
            let source: ResolvedTypeDefinitionSource => source.value is root.hir.DefinitionEnum,
            let exported: ResolvedTypeDefinitionExported => exported.value is ExportedTypeEnum,
            null => false,
        };
        if (is_enum) {
            return null;
        }
        let diags = self.diags;
        let saved = diags?.length();
        let ty = self.lower_path(head, prefix, [], [], TypePosition.ConstraintHead);
        let clean = if (diags != null && saved != null) {
            let clean = diags.length() == saved;
            while (diags.length() > saved) {
                diags.pop();
            }
            clean
        } else {
            true
        };
        if (
            clean
                && !root.types.any_node(ty, (node) -> {
                    node is root.types.TyError
                })
        ) {
            ty
        } else {
            null
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::plain_bounds_env @ d9be6853b
    // The frame's bound env (a copy), the constraint map projection
    // determination judges through.
    function plain_bounds_env(
        self,
    ) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
        let env: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
        for (let param in self.bounds.keys()) {
            env[param] = self.bounds[param];
        }
        env
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::record_type_errors @ d9be6853b
    function record_type_errors(self, errors: TirTypeError[]) -> void throws never {
        let diags = self.diags;
        let type_ref = self.current_ref;
        if (diags != null && type_ref != null) {
            for (let error in errors) {
                diags.push(
                    LoweringDiag {
                        type_ref: type_ref,
                        kind: LoweringDiagKindProjection { value: error },
                    },
                );
            }
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::projection_interface_for @ d9be6853b
    // The interface a bare projection (`T.Output`) resolves through: for a
    // type-var base, the unique bound declaring `member`; for an interface
    // existential, itself; for a chained step, the previous member's declared
    // bound; for the impl subject, the impl's written target.
    function projection_interface_for(
        self,
        base: root.types.LoweringTy,
        member: string,
    ) -> root.types.LoweringInterfaceConstraint? throws never {
        let declares = (name: root.types.DeclName) -> bool {
            root.hir_ty.interfaces.interface_declares_member(
                self.db,
                name,
                member,
                root.hir_ty.interfaces.MemberNamespace.Type,
            )
        };
        let materialize = (target: root.types.InterfaceConstraint) -> root.types.LoweringInterfaceConstraint {
            root.types.LoweringInterfaceConstraint {
                name: target.name,
                generics: target.generics.map(root.types.widen_ty_to_lowering_ty),
                associated_types: target.associated_types
                    .map((pin) -> {
                        root.types.LoweringAssociatedType {
                            name: pin.name,
                            ty: root.types.widen_ty_to_lowering_ty(pin.ty),
                        }
                    })
                    .sort_by_key((pin) -> {
                        pin.name
                    }),
            }
        };
        match (base) {
            let var: root.types.TyTypeVar => {
                let candidates = (self.bounds.get(var.param) ?? []).filter((bound) -> {
                    declares(bound.name)
                });
                if (candidates.length() == 1) {
                    materialize(candidates[0])
                } else {
                    null
                }
            },
            let existential: root.types.LoweringTyInterface => {
                if (declares(existential.name)) {
                    root.types.LoweringInterfaceConstraint {
                        name: existential.name,
                        generics: existential.args,
                        associated_types: existential.associated_types.concat([]).sort_by_key((pin) -> {
                            pin.name
                        }),
                    }
                } else {
                    null
                }
            },
            let step: root.types.LoweringTyAssociatedTypeProjection => {
                let qualifier = root.types.LoweringTyInterface {
                    name: step.interface_.name,
                    args: step.interface_.generics,
                    associated_types: step.interface_.associated_types,
                };
                let target_ty = root.types.narrow_lowering_ty_to_ty(qualifier) catch (e) {
                    root.types.NarrowError => {
                        return null;
                    },
                };
                let target = root.types.as_interface(target_ty)
                    ?? return null;
                let prev_base = root.types.narrow_lowering_ty_to_ty(step.base) catch (e) {
                    root.types.NarrowError => {
                        return null;
                    },
                };
                let bound = realized_assoc_bound_plain(self.db, target, prev_base, step.member)
                    ?? return null;
                match (bound) {
                    let i: root.types.TyInterface if declares(i.name) => {
                        materialize(
                            root.types.InterfaceConstraint {
                                name: i.name,
                                generics: i.args,
                                associated_types: i.associated_types,
                            },
                        )
                    },
                    _ => null,
                }
            },
            _ => {
                let target = self.self_impl_target;
                if (base == self.self_ty && target != null && declares(target.name)) {
                    materialize(target)
                } else {
                    null
                }
            },
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::checked_map_key @ d9be6853b
    // Written keys must prove `Hash` through their structural implementation
    // or the enclosing bounds; holes are checked after solving.
    function checked_map_key(
        self,
        key: root.types.LoweringTy,
    ) -> root.types.LoweringTy throws never {
        if (
            self.diags == null
                || root.types.any_node(key, (node) -> {
                    node is root.types.TyInfer
                })
                || root.types.any_node(key, (node) -> {
                    node is root.types.TyError
                })
        ) {
            return key;
        }
        let facts = Facts.with_bounds(self.db, self.plain_bounds_env());
        if (!root.hir_ty.interfaces.map_key_is_hashable(self.db, facts, reject_holes(key))) {
            let diags = self.diags;
            let type_ref = self.current_ref;
            if (diags != null && type_ref != null) {
                diags.push(
                    LoweringDiag {
                        type_ref: type_ref,
                        kind: LoweringDiagKindInvalidMapKey { key: reject_holes(key) },
                    },
                );
            }
        }
        key
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_path @ d9be6853b
    // Lowers a resolved (or fallback-resolved) type path: in-scope type var,
    // then the definition, then bare `Self`, then `Enum.Variant`, then a
    // dotted projection, then `Error`. A lexical generic name shadows every
    // nominal definition.
    function lower_path(
        self,
        head: root.hir.PathHead,
        segments: string[],
        args: root.types.LoweringTy[],
        bindings: (string, root.types.LoweringTy)[],
        position: TypePosition,
    ) -> root.types.LoweringTy throws never {
        let short = segments[segments.length() - 1];
        let generic_head = match (head) {
            root.hir.PathHeadLang => null,
            root.hir.PathHeadPackage | root.hir.PathHeadPlain => self.lexical_generic(segments[0]),
        };
        if (generic_head != null) {
            if (segments.length() == 1) {
                return root.types.TyTypeVar { param: generic_head };
            }
            if (args.length() != 0 || bindings.length() != 0) {
                self.record_arity(short, args.length() + bindings.length(), 0);
            }
            return self.lower_projection_chain(root.types.TyTypeVar { param: generic_head }, segments);
        }

        let def = self.resolve_type(head, segments);
        if (def != null) {
            return match (def) {
                let source: ResolvedTypeDefinitionSource => {
                    self.lower_definition(source.value, short, args, bindings, position)
                },
                let exported: ResolvedTypeDefinitionExported => {
                    self.lower_exported_type(exported.value, short, args, bindings, position)
                },
            };
        }

        // Fallback 1: bare `Self` under a concrete impl owner.
        let concrete_self = self.self_ty;
        if (segments.length() == 1 && segments[0] == "Self" && concrete_self != null) {
            return concrete_self;
        }

        // Fallback 2: `Enum.Variant` read as a literal type.
        let enum_prefix = segments.slice(0, segments.length() - 1);
        if (segments.length() >= 2 && args.length() == 0 && bindings.length() == 0) {
            let enum_def = self.resolve_type(head, enum_prefix);
            let enum_qtn = match (enum_def) {
                let source: ResolvedTypeDefinitionSource => {
                    match (source.value) {
                        let e: root.hir.DefinitionEnum => {
                            let declares_variant = root.hir.enum_data(self.db, e.value).variants.some((variant) -> {
                                variant.name == short
                            });
                            if (declares_variant) {
                                self.qualify(e, segments[segments.length() - 2])
                            } else {
                                null
                            }
                        },
                        _ => null,
                    }
                },
                let exported: ResolvedTypeDefinitionExported => {
                    match (exported.value) {
                        let row: ExportedTypeEnum if row.variants.includes(short) => row.qtn,
                        _ => null,
                    }
                },
                null => null,
            };
            if (enum_qtn != null) {
                return root.types.TyEnumVariant { name: enum_qtn, variant: short };
            }
        }

        // Fallback 3: an associated projection written as a dotted path
        // (`T.Item`, `Self.Item`, chained `T.Item.Sub`).
        if (segments.length() > 1 && args.length() == 0 && bindings.length() == 0) {
            let param = self.lexical_generic(segments[0]);
            let projection_head: root.types.LoweringTy? = if (param != null) {
                root.types.TyTypeVar { param: param }
            } else if (segments[0] == "Self") {
                // `Self.Member` under a concrete impl owner: the head is the
                // subject itself.
                self.self_ty
            } else {
                null
            };
            if (projection_head != null) {
                return self.lower_projection_chain(projection_head, segments);
            }
            // Type-headed prefix (`ArrayIterator.Element`, and the rejected
            // interface-as-base `Iterator.Element`), probed with the sink
            // muted so an unresolvable prefix falls through below.
            let prefix_ty = self.probe_projection_prefix(head, enum_prefix);
            if (prefix_ty != null) {
                let head_plain = reject_holes(prefix_ty);
                let iface_qtn = root.hir_ty.interfaces.interface_base_without_member_pin(self.db, head_plain, short);
                if (iface_qtn != null) {
                    self.record_type_errors(
                        [
                            TirTypeErrorInterfaceProjectionBase {
                                interface_: iface_qtn,
                                member: short,
                            },
                        ],
                    );
                    return root.types.TyError {};
                }
                let lowered = root.hir_ty.interfaces.lower_projection(
                    self.db,
                    self.package_items.root_id,
                    self.plain_bounds_env(),
                    head_plain,
                    null,
                    short,
                );
                self.record_type_errors(lowered.diagnostics);
                return root.types.widen_ty_to_lowering_ty(lowered.ty);
            }
        }

        let diags = self.diags;
        let type_ref = self.current_ref;
        if (diags != null && type_ref != null) {
            diags.push(
                LoweringDiag {
                    type_ref: type_ref,
                    kind: LoweringDiagKindUnresolved {
                        name: segments.join("."),
                        suggestions: self.type_suggestions(segments),
                    },
                },
            );
        }
        let package = self.package_shadowed_by_item(head, segments);
        if (package != null) {
            self.record_type_errors([TirTypeErrorItemShadowsPackage { name: package }]);
        }
        root.types.TyError {}
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_path @ d9be6853b
    // (its projection loop). Restructured: Rust writes this loop twice, for
    // a lexical generic head and for fallback 3; it is one method here. Each
    // further segment projects through the interface its base determines;
    // a hole-carrying prefix cannot determine.
    function lower_projection_chain(
        self,
        head: root.types.LoweringTy,
        segments: string[],
    ) -> root.types.LoweringTy throws never {
        let ty = head;
        for (let member in segments.slice(1, segments.length())) {
            let interface_ = self.projection_interface_for(ty, member);
            if (interface_ != null) {
                ty
                    = root.types.LoweringTyAssociatedTypeProjection {
                        base: ty,
                        interface_: interface_,
                        member: member,
                    };
                continue;
            }
            let ty_plain = root.types.narrow_lowering_ty_to_ty(ty) catch (e) {
                root.types.NarrowError => {
                    self.record_no_infer(NoInferReason.ProjectionBase);
                    return root.types.TyError {};
                },
            };
            let lowered = root.hir_ty.interfaces.lower_projection(
                self.db,
                self.package_items.root_id,
                self.plain_bounds_env(),
                ty_plain,
                null,
                member,
            );
            self.record_type_errors(lowered.diagnostics);
            ty = root.types.widen_ty_to_lowering_ty(lowered.ty);
            if (ty is root.types.TyError) {
                return ty;
            }
        }
        ty
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::type_suggestions @ d9be6853b
    // "Did you mean" candidates for an unresolved type path.
    function type_suggestions(self, segments: string[]) -> string[] throws never {
        self.qualified_suggestions(segments, (items, item) -> {
            items.types.has(item)
        })
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::value_suggestions @ d9be6853b
    // `type_suggestions` for an unresolved qualified value path; failing
    // that, the longest prefix that is a type path, with its members.
    function value_suggestions(self, segments: string[]) -> string[] throws never {
        if (segments.length() < 2) {
            return [];
        }
        let direct = self.qualified_suggestions(segments, (items, item) -> {
            items.values.has(item)
        });
        if (direct.length() != 0) {
            return direct;
        }
        for (let split = segments.length() - 1; split >= 2; split -= 1) {
            let members = segments.slice(split, segments.length());
            let types = self.type_suggestions(segments.slice(0, split));
            if (types.length() != 0) {
                return types.map((ty) -> {
                    [ty].concat(members).join(".")
                });
            }
        }
        []
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::qualified_suggestions @ d9be6853b
    // The fully qualified `root...` path of every namespace of this package
    // that `declares` the item and whose path ends with the namespaces
    // written, the first MAX_SUGGESTIONS of them: the relative reading
    // first, the rest sorted.
    function qualified_suggestions(
        self,
        segments: string[],
        declares: (root.hir.NamespaceItems, string) -> bool throws never,
    ) -> string[] throws never {
        if (segments.length() == 0) {
            return [];
        }
        let item = segments[segments.length() - 1];
        let written_ns = segments.slice(0, segments.length() - 1);
        let relative = self.ns_context.concat(written_ns);
        let candidates = self.package_items.namespaces
            .filter((entry) -> {
                let ns_path = entry.0;
                ns_path.length() >= written_ns.length()
                    && ns_path.slice(ns_path.length() - written_ns.length(), ns_path.length())
                        == written_ns
                    && declares(entry.1, item)
            })
            .map((entry) -> {
                (entry.0 != relative, entry.0)
            });
        candidates.sort_by((a, b) -> {
            let by_relative = cmp_bool(a.0, b.0);
            if (by_relative != baml.ops.Ordering.Equal) {
                by_relative
            } else {
                cmp_names(a.1, b.1)
            }
        });
        candidates.slice(0, MAX_SUGGESTIONS).map((candidate) -> {
            ["root"].concat(candidate.1).concat([item]).join(".")
        })
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_definition @ d9be6853b
    function lower_definition(
        self,
        def: root.hir.Definition,
        short: string,
        args: root.types.LoweringTy[],
        bindings: (string, root.types.LoweringTy)[],
        position: TypePosition,
    ) -> root.types.LoweringTy throws never {
        match (def) {
            let class_: root.hir.DefinitionClass => {
                let data = root.hir.class_data(self.db, class_.value);
                self.record_arity(short, args.length(), data.generic_params.length());
                enforce_arity(args, data.generic_params.length());
                let qtn = self.qualify(def, short);
                let ty = class_lowering_ty(root.hir.lang_roots(self.db), qtn, args);
                // The `baml.Map<K, V>` spelling bridges to the structural map,
                // so it gets the same key validation as `map<k, v>`.
                match (ty) {
                    let m: root.types.LoweringTyMap => {
                        root.types.LoweringTyMap {
                            key: self.checked_map_key(m.key),
                            value: m.value,
                        }
                    },
                    _ => ty,
                }
            },
            let interface_: root.hir.DefinitionInterface => {
                let data = root.hir.interface_data(self.db, interface_.value);
                self.record_arity(short, args.length(), data.generic_params.length());
                enforce_arity(args, data.generic_params.length());
                let qtn = self.qualify(def, short);
                // A binding naming an undeclared member, or re-binding one,
                // is diagnosed and dropped.
                let declared = data.associated_types.map((assoc) -> {
                    assoc.name
                });
                let checked: (string, root.types.LoweringTy)[] = [];
                for (let binding in bindings) {
                    if (!declared.includes(binding.0)) {
                        self.record_type_errors(
                            [TirTypeErrorUnresolvedType { name: binding.0, suggestions: declared }],
                        );
                        continue;
                    }
                    if (
                        checked.some((seen) -> {
                            seen.0 == binding.0
                        })
                    ) {
                        self.record_type_errors(
                            [
                                TirTypeErrorDuplicateAssociatedTypeBinding {
                                    interface_: qtn,
                                    name: binding.0,
                                },
                            ],
                        );
                        continue;
                    }
                    checked.push(binding);
                }
                // An existential denotes one complete instantiation: each
                // omitted defaulted member fills eagerly, and a member with
                // neither pin nor default is an error. A constraint head pins
                // only what it writes.
                if (position == TypePosition.Existential && data.associated_types.length() != 0) {
                    let iface_params = interface_declared_params(self.db, interface_.value);
                    let self_param = interface_frame(self.db, interface_.value)[0];
                    let plain_args = args.map(reject_holes);
                    for (let assoc in data.associated_types) {
                        if (
                            checked.some((bound) -> {
                                bound.0 == assoc.name
                            })
                        ) {
                            continue;
                        }
                        let found = root.hir_ty.interfaces.interface_associated_type_default(
                            self.db,
                            interface_.value,
                            assoc.name,
                        );
                        if (found == null) {
                            continue;
                        }
                        let self_ty = root.types.TyInterface {
                            name: qtn,
                            args: plain_args,
                            associated_types: checked.map((bound) -> {
                                root.types.AssociatedType {
                                    name: bound.0,
                                    ty: reject_holes(bound.1),
                                }
                            }),
                        };
                        let realized = root.hir_ty.interfaces.realize_associated_default(
                            found.0,
                            iface_params,
                            plain_args,
                            self_param,
                            self_ty,
                        );
                        checked.push((assoc.name, root.types.widen_ty_to_lowering_ty(realized)));
                    }
                    let missing = declared.filter((name) -> {
                        !checked.some((bound) -> {
                            bound.0 == name
                        })
                    });
                    if (missing.length() != 0) {
                        for (let name in missing) {
                            checked.push((name, root.types.TyError {}));
                        }
                        self.record_type_errors(
                            [
                                TirTypeErrorMissingAssociatedTypeBindings {
                                    interface_: qtn,
                                    missing: missing,
                                },
                            ],
                        );
                    }
                }
                // Sorted for order-insensitive identity.
                checked.sort_by_key((bound) -> {
                    bound.0
                });
                root.types.LoweringTyInterface {
                    name: qtn,
                    args: args,
                    associated_types: checked.map((bound) -> {
                        root.types.LoweringAssociatedType { name: bound.0, ty: bound.1 }
                    }),
                }
            },
            root.hir.DefinitionEnum => root.types.TyEnum { name: self.qualify(def, short) },
            // Aliases stay nominal at lowering.
            root.hir.DefinitionTypeAlias => {
                root.types.TyTypeAlias { name: self.qualify(def, short) }
            },
            // Value-namespace definitions are not types.
            root.hir.DefinitionFunction | root.hir.DefinitionLet => root.types.TyError {},
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_exported_type @ d9be6853b
    function lower_exported_type(
        self,
        exported: ExportedType,
        short: string,
        args: root.types.LoweringTy[],
        bindings: (string, root.types.LoweringTy)[],
        position: TypePosition,
    ) -> root.types.LoweringTy throws never {
        match (exported) {
            let row: ExportedTypeClass => {
                self.record_arity(short, args.length(), row.generic_params.length());
                enforce_arity(args, row.generic_params.length());
                let ty = class_lowering_ty(root.hir.lang_roots(self.db), row.qtn, args);
                match (ty) {
                    let m: root.types.LoweringTyMap => {
                        root.types.LoweringTyMap {
                            key: self.checked_map_key(m.key),
                            value: m.value,
                        }
                    },
                    _ => ty,
                }
            },
            let row: ExportedTypeEnum => {
                self.record_arity(short, args.length(), 0);
                self.reject_non_interface_bindings(bindings);
                root.types.TyEnum { name: row.qtn }
            },
            let row: ExportedTypeTypeAlias => {
                self.record_arity(short, args.length(), 0);
                self.reject_non_interface_bindings(bindings);
                root.types.TyTypeAlias { name: row.qtn }
            },
            let row: ExportedTypeInterface => {
                self.record_arity(short, args.length(), row.generic_params.length());
                enforce_arity(args, row.generic_params.length());
                let declared = row.associated_types.map((assoc) -> {
                    assoc.name
                });
                let checked: (string, root.types.LoweringTy)[] = [];
                for (let binding in bindings) {
                    if (!declared.includes(binding.0)) {
                        self.record_type_errors(
                            [TirTypeErrorUnresolvedType { name: binding.0, suggestions: declared }],
                        );
                        continue;
                    }
                    if (
                        checked.some((seen) -> {
                            seen.0 == binding.0
                        })
                    ) {
                        self.record_type_errors(
                            [
                                TirTypeErrorDuplicateAssociatedTypeBinding {
                                    interface_: row.qtn,
                                    name: binding.0,
                                },
                            ],
                        );
                        continue;
                    }
                    checked.push(binding);
                }
                if (position == TypePosition.Existential) {
                    let plain_args = args.map(reject_holes);
                    for (let assoc in row.associated_types) {
                        if (
                            checked.some((bound) -> {
                                bound.0 == assoc.name
                            })
                        ) {
                            continue;
                        }
                        let default_ = assoc.default_;
                        if (default_ == null) {
                            continue;
                        }
                        let self_ty = root.types.TyInterface {
                            name: row.qtn,
                            args: plain_args,
                            associated_types: checked.map((bound) -> {
                                root.types.AssociatedType {
                                    name: bound.0,
                                    ty: reject_holes(bound.1),
                                }
                            }),
                        };
                        let realized = root.hir_ty.interfaces.realize_associated_default(
                            default_,
                            row.generic_params,
                            plain_args,
                            row.self_param,
                            self_ty,
                        );
                        checked.push((assoc.name, root.types.widen_ty_to_lowering_ty(realized)));
                    }
                    let missing = declared.filter((name) -> {
                        !checked.some((bound) -> {
                            bound.0 == name
                        })
                    });
                    if (missing.length() != 0) {
                        for (let name in missing) {
                            checked.push((name, root.types.TyError {}));
                        }
                        self.record_type_errors(
                            [
                                TirTypeErrorMissingAssociatedTypeBindings {
                                    interface_: row.qtn,
                                    missing: missing,
                                },
                            ],
                        );
                    }
                }
                checked.sort_by_key((bound) -> {
                    bound.0
                });
                root.types.LoweringTyInterface {
                    name: row.qtn,
                    args: args,
                    associated_types: checked.map((bound) -> {
                        root.types.LoweringAssociatedType { name: bound.0, ty: bound.1 }
                    }),
                }
            },
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::reject_non_interface_bindings @ d9be6853b
    function reject_non_interface_bindings(
        self,
        bindings: (string, root.types.LoweringTy)[],
    ) -> void throws never {
        for (let binding in bindings) {
            self.record_type_errors(
                [TirTypeErrorUnresolvedType { name: binding.0, suggestions: [] }],
            );
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::path_head @ d9be6853b
    // HIR's reading of a type path's first segment, for paths with no
    // recorded head.
    function path_head(self, segments: string[]) -> root.hir.PathHead throws never {
        root.hir.path_head(self.db, self.package_items.root_id, self.ns_context, segments)
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lexical_generic @ d9be6853b
    // The lexical generic parameter named `name`, innermost frame first.
    function lexical_generic(self, name: string) -> root.types.ParamTy? throws never {
        self.generic_params.find_last((param) -> {
            param.name == name
        })
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::package_shadowed_by_item @ d9be6853b
    // The package `segments` would have started at, had an item of this
    // namespace not claimed its head.
    function package_shadowed_by_item(
        self,
        head: root.hir.PathHead,
        segments: string[],
    ) -> string? throws never {
        if (!(head is root.hir.PathHeadPlain) || segments.length() < 2) {
            return null;
        }
        let first = segments[0];
        if (
            root.hir.namespace_declares(self.db, self.package_items.root_id, self.ns_context, first)
                && root.hir.path_package(self.db, self.package_items.root_id, first) != null
        ) {
            first
        } else {
            null
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::type_path_head @ d9be6853b
    // HIR's reading of a type path's first segment as `origin` says it was
    // written.
    function type_path_head(
        self,
        origin: root.base.PathOrigin,
        segments: string[],
    ) -> root.hir.PathHead throws never {
        root.hir.path_head_for(
            self.db,
            self.package_items.root_id,
            self.ns_context,
            origin,
            segments,
        )
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::source_items @ d9be6853b
    // The items of a source-served package this context can read.
    function source_items(self, package: int) -> root.hir.PackageItems throws never {
        if (package == self.package_items.root_id) {
            self.package_items
        } else {
            root.hir.package_items(self.db, package)
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::resolve_type @ d9be6853b
    // The type `segments` names, read from `head`, when the whole path is
    // the item's own path: its bare name from its namespace, or its fully
    // qualified path (what a package head reads).
    function resolve_type(
        self,
        head: root.hir.PathHead,
        segments: string[],
    ) -> ResolvedTypeDefinition? throws never {
        let package = match (head) {
            let h: root.hir.PathHeadPackage => h.value,
            let h: root.hir.PathHeadLang => h.value,
            root.hir.PathHeadPlain => null,
        };
        if (package != null && segments.length() >= 2) {
            let item = segments[segments.length() - 1];
            let namespace = segments.slice(1, segments.length() - 1);
            // A served dependency answers from its interface only.
            if (root.hir.is_served_from_interface(self.db, package)) {
                let exported = exported_type_row(self.db, package, namespace, item);
                if (exported != null) {
                    return ResolvedTypeDefinitionExported { value: exported };
                }
            } else {
                let def = self.source_items(package).lookup_type(namespace, item);
                if (def != null) {
                    return ResolvedTypeDefinitionSource { value: def };
                }
            }
        }
        if (!(head is root.hir.PathHeadLang) && segments.length() == 1) {
            let def = self.package_items.lookup_type(self.ns_context, segments[0]);
            if (def != null) {
                return ResolvedTypeDefinitionSource { value: def };
            }
        }
        null
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::resolve_value @ d9be6853b
    // Value-namespace resolution, `resolve_type`'s algorithm over
    // `lookup_value`.
    function resolve_value(
        self,
        head: root.hir.PathHead,
        segments: string[],
    ) -> ResolvedValue? throws never {
        let package = match (head) {
            let h: root.hir.PathHeadPackage => h.value,
            let h: root.hir.PathHeadLang => h.value,
            root.hir.PathHeadPlain => null,
        };
        if (package != null && segments.length() >= 2) {
            let item = segments[segments.length() - 1];
            let namespace = segments.slice(1, segments.length() - 1);
            if (root.hir.is_served_from_interface(self.db, package)) {
                let function_ = mounted_function_named(self.db, package, namespace, item);
                if (function_ != null) {
                    return ResolvedValueExternal { value: function_ };
                }
                let binding = mounted_let_named(self.db, package, namespace, item);
                if (binding != null) {
                    return ResolvedValueExternalLet { value: binding };
                }
            } else {
                let def = self.source_items(package).lookup_value(namespace, item);
                if (def != null) {
                    return ResolvedValueSource { value: def };
                }
            }
        }
        if (!(head is root.hir.PathHeadLang) && segments.length() == 1) {
            let def = self.package_items.lookup_value(self.ns_context, segments[0]);
            if (def != null) {
                return ResolvedValueSource { value: def };
            }
        }
        null
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::resolve_type_definition @ d9be6853b
    // Type-namespace resolution, for constructor and member typing.
    function resolve_type_definition(
        self,
        head: root.hir.PathHead,
        segments: string[],
    ) -> root.hir.Definition? throws never {
        match (self.resolve_type(head, segments)) {
            let source: ResolvedTypeDefinitionSource => source.value,
            _ => null,
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::resolve_exported_type_definition @ d9be6853b
    function resolve_exported_type_definition(
        self,
        head: root.hir.PathHead,
        segments: string[],
    ) -> ExportedType? throws never {
        match (self.resolve_type(head, segments)) {
            let exported: ResolvedTypeDefinitionExported => exported.value,
            _ => null,
        }
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::lower_type_path @ d9be6853b
    // A dotted type path in value position, resolved as a written annotation
    // with no written args or bindings.
    function lower_type_path(
        self,
        head: root.hir.PathHead,
        segments: string[],
    ) -> root.types.LoweringTy throws never {
        self.lower_path(head, segments, [], [], TypePosition.Existential)
    }

    // port: baml_compiler2_hir_ty/src/lower.rs::LowerCtx::qualify @ d9be6853b
    // The qualified name from the definition's file; the short name is what
    // the user wrote.
    function qualify(
        self,
        def: root.hir.Definition,
        short: string,
    ) -> root.types.DeclName throws never {
        let info = root.hir.file_package(self.db, root.hir.definition_file(def, self.db));
        root.types.DeclName { pkg: info.root_id, namespace: info.namespace_path, name: short }
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::lower_ctx_for_file @ d9be6853b
// A lowering context for type syntax written in `file`, with an empty frame.
function lower_ctx_for_file(db: root.hir.Db, file: int) -> LowerCtx throws never {
    let info = root.hir.file_package(db, file);
    lower_ctx_for_package(db, root.hir.package_items(db, info.root_id), info.namespace_path)
}

// port: baml_compiler2_hir_ty/src/lower.rs::lower_ctx_for_package @ d9be6853b
// A lowering context over an explicit package view.
function lower_ctx_for_package(
    db: root.hir.Db,
    package_items: root.hir.PackageItems,
    ns_context: string[],
) -> LowerCtx throws never {
    LowerCtx {
        diags: null,
        current_ref: null,
        db: db,
        package_items: package_items,
        ns_context: ns_context,
        generic_params: [],
        self_ty: null,
        self_impl_target: null,
        bounds: {},
        holes: HolePolicyAllowed {},
    }
}

// Rust's derived `Ord` on `bool` (false < true), for the suggestion sort.
function cmp_bool(a: bool, b: bool) -> baml.ops.Ordering throws never {
    if (a == b) {
        baml.ops.Ordering.Equal
    } else if (b) {
        baml.ops.Ordering.Less
    } else {
        baml.ops.Ordering.Greater
    }
}

// Rust's derived `Ord` on `[Name]`: lexicographic, a prefix first.
function cmp_names(a: string[], b: string[]) -> baml.ops.Ordering throws never {
    let shared = if (a.length() < b.length()) {
        a.length()
    } else {
        b.length()
    };
    for (let i = 0; i < shared; i += 1) {
        let by_segment = a[i].cmp(b[i]);
        if (by_segment != baml.ops.Ordering.Equal) {
            return by_segment;
        }
    }
    a.length().cmp(b.length())
}

// port: baml_compiler2_hir_ty/src/lower.rs::substitute_params @ d9be6853b
// Substitutes generic parameters by frame index: `TypeVar(p)` becomes
// `args[p.index]` (absent slots stay symbolic). Restructured: takes the pool.
function substitute_params(pool: root.types.InferPool, ty: int, args: int[]) -> int throws never {
    if (!pool.has_typevar(ty)) {
        return ty;
    }
    let kind = pool.kinds[ty];
    match (kind) {
        let var: root.types.TyTypeVar if var.param.index < args.length() => {
            return args[var.param.index];
        },
        _ => {},
    }
    pool.add(
        root.types.map_children(kind, (child) -> {
            substitute_params(pool, child, args)
        }),
    )
}

// port: baml_compiler2_hir_ty/src/lower.rs::substitute_params_through_arm @ d9be6853b
// `substitute_params` for one arm of a union `Self`: a bare `Self` is the
// union (`args`), an associated-type projection is taken over the arm
// (`arm_args`). Restructured: takes the pool.
function substitute_params_through_arm(
    pool: root.types.InferPool,
    ty: int,
    args: int[],
    arm_args: int[],
) -> int throws never {
    if (!pool.has_typevar(ty)) {
        return ty;
    }
    let kind = pool.kinds[ty];
    match (kind) {
        root.types.InferTyAssociatedTypeProjection => substitute_params(pool, ty, arm_args),
        let var: root.types.TyTypeVar if var.param.index < args.length() => args[var.param.index],
        _ => {
            pool.add(
                root.types.map_children(kind, (child) -> {
                    substitute_params_through_arm(pool, child, args, arm_args)
                }),
            )
        },
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::enforce_arity @ d9be6853b
// Generic-arity recovery: extras truncated, missing padded with `Error`.
function enforce_arity(args: root.types.LoweringTy[], expected: int) -> void throws never {
    while (args.length() > expected) {
        args.pop();
    }
    while (args.length() < expected) {
        args.push(root.types.TyError {});
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::function_generic_frame @ d9be6853b
// The flattened generic frame for a function: owner generics first (an
// interface prepends `Self`), then the function's own generics, then its
// synthetic effect params.
function function_generic_frame(
    db: root.hir.Db,
    function_: int,
) -> root.types.ParamTy[] throws never {
    let frame: root.types.ParamTy[] = match (root.hir.method_owner(db, function_)) {
        let owner: root.hir.MethodOwnerClass => {
            let frame: root.types.ParamTy[] = [];
            extend_frame(
                frame,
                root.hir.class_data(db, owner.value).generic_params.map((g) -> {
                    g.name
                }),
            );
            frame
        },
        let owner: root.hir.MethodOwnerInterface => {
            // Associated types are not frame slots.
            let frame: root.types.ParamTy[] = [];
            extend_frame(frame, ["Self"]);
            extend_frame(
                frame,
                root.hir.interface_data(db, owner.value).generic_params.map((g) -> {
                    g.name
                }),
            );
            frame
        },
        // Impl blocks: the block's root frame is the owner prefix.
        let owner: root.hir.MethodOwnerImpl => impl_frame(db, owner.value),
        null => [],
    };
    let data = root.hir.elaborated_function_data(db, function_);
    extend_frame(frame, data.user_generic_params);
    extend_frame(frame, data.synthetic_effect_params);
    frame
}

// port: baml_compiler2_hir_ty/src/lower.rs::builtin_structural @ d9be6853b
// The builtin class spellings denote their structural types (`baml.Array<T>`
// is `T[]`, `class baml.Int` is `int`), keyed on the installed language
// root and the full definition path.
function builtin_structural(
    lang: root.base.LangRoots,
    qtn: root.types.DeclName,
    arity: int,
) -> root.types.AliasTarget? throws never {
    let alias = root.types.compiler_alias_by_definition(lang, qtn)
        ?? return null;
    root.types.compiler_alias_class_carrier(alias, arity)
}

// port: baml_compiler2_hir_ty/src/lower.rs::class_lowering_ty @ d9be6853b
// The type a class reference denotes in the lowering vocabulary, builtin
// bridges applied.
function class_lowering_ty(
    lang: root.base.LangRoots,
    qtn: root.types.DeclName,
    args: root.types.LoweringTy[],
) -> root.types.LoweringTy throws never {
    let target = builtin_structural(lang, qtn, args.length());
    if (target == null) {
        return root.types.LoweringTyClass { name: qtn, args: args };
    }
    let primitive = root.types.primitive_of_target(target);
    if (primitive != null) {
        return root.types.widen_ty_to_lowering_ty(root.types.from_primitive(primitive));
    }
    match (target) {
        root.types.AliasTarget.Future => {
            root.types.LoweringTyFuture { value: args[0], error: args[1] }
        },
        root.types.AliasTarget.List => root.types.LoweringTyList { elem: args[0] },
        root.types.AliasTarget.Map => root.types.LoweringTyMap { key: args[0], value: args[1] },
        root.types.AliasTarget.Type => root.types.TyType {},
        // Json expands through the alias resolver; intrinsics have no class.
        _ => root.types.LoweringTyClass { name: qtn, args: args },
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::class_ty @ d9be6853b
// `class_lowering_ty`'s interned twin, for types minted inside inference.
// Restructured: named `class_ty_interned` (see the file header) and takes
// the pool.
function class_ty_interned(
    pool: root.types.InferPool,
    lang: root.base.LangRoots,
    qtn: root.types.DeclName,
    args: int[],
) -> int throws never {
    let alias = root.types.compiler_alias_by_definition(lang, qtn);
    if (alias != null) {
        let lowered = root.types.compiler_alias_lower_class(pool, alias, args);
        if (lowered != null) {
            return lowered;
        }
    }
    pool.add(root.types.InferTyClass { name: qtn, args: args })
}

// port: baml_compiler2_hir_ty/src/lower.rs::class_qualified_name @ d9be6853b
// The qualified name a class definition contributes, from its file's package.
function class_qualified_name(db: root.hir.Db, class_: int) -> root.types.DeclName throws never {
    let package = root.hir.file_package(db, db.class_locs.get(class_).file);
    root.types.DeclName {
        pkg: package.root_id,
        namespace: package.namespace_path,
        name: root.hir.class_data(db, class_).name,
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::class_self_ty @ d9be6853b
// The type of `self` inside `class_`: the class at its own params, through
// the builtin bridging.
function class_self_ty(db: root.hir.Db, class_: int) -> root.types.Ty throws never {
    let args: root.types.LoweringTy[] = class_generic_frame(db, class_).map((param) -> {
        root.types.TyTypeVar { param: param }
    });
    reject_holes(class_lowering_ty(root.hir.lang_roots(db), class_qualified_name(db, class_), args))
}

// port: baml_compiler2_hir_ty/src/lower.rs::enum_self_ty @ d9be6853b
function enum_self_ty(db: root.hir.Db, enum_loc: int) -> root.types.Ty throws never {
    let data = root.hir.enum_data(db, enum_loc);
    root.types.TyEnum {
        name: qualify_def(db, root.hir.DefinitionEnum { value: enum_loc }, data.name),
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::declaration_self_ty @ d9be6853b
// The concrete type a declaration denotes at its own generic params; null
// for a declaration that is no concrete type.
function declaration_self_ty(
    db: root.hir.Db,
    definition: root.hir.Definition,
) -> root.types.Ty? throws never {
    match (definition) {
        let class_: root.hir.DefinitionClass => class_self_ty(db, class_.value),
        let enum_def: root.hir.DefinitionEnum => enum_self_ty(db, enum_def.value),
        root.hir.DefinitionInterface
            | root.hir.DefinitionTypeAlias
            | root.hir.DefinitionFunction
            | root.hir.DefinitionLet =>
        {
            null
        },
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::interface_generic_frame_params @ d9be6853b
// A generic frame from bare interface param names (no `Self` slot).
function interface_generic_frame_params(names: string[]) -> root.types.ParamTy[] throws never {
    let frame: root.types.ParamTy[] = [];
    extend_frame(frame, names);
    frame
}

// port: baml_compiler2_hir_ty/src/lower.rs::interface_frame @ d9be6853b
// The full interface frame: `[Self, params..]`.
function interface_frame(db: root.hir.Db, interface_: int) -> root.types.ParamTy[] throws never {
    let data = root.hir.interface_data(db, interface_);
    interface_generic_frame_params(
        ["Self"].concat(
            data.generic_params.map((g) -> {
                g.name
            }),
        ),
    )
}

// port: baml_compiler2_hir_ty/src/lower.rs::interface_declared_params @ d9be6853b
// The interface's own declared params: `interface_frame` without `Self`.
function interface_declared_params(
    db: root.hir.Db,
    interface_: int,
) -> root.types.ParamTy[] throws never {
    let data = root.hir.interface_data(db, interface_);
    interface_frame(db, interface_).slice(1, data.generic_params.length() + 1)
}

// port: baml_compiler2_hir_ty/src/lower.rs::impl_frame @ d9be6853b
// The root generic frame for an impl block: its declared generics.
function impl_frame(db: root.hir.Db, block: int) -> root.types.ParamTy[] throws never {
    let frame: root.types.ParamTy[] = [];
    root.types.ParamTy.extend_frame(
        frame,
        root.hir.impl_block_data(db, block).generics.map((param) -> {
            param.name
        }),
    );
    frame
}

// port: baml_compiler2_hir_ty/src/lower.rs::impl_self_ty @ d9be6853b
// The type an impl block is for: what `Self` denotes inside it.
function impl_self_ty(db: root.hir.Db, block: int) -> root.types.Ty throws never {
    let data = root.hir.impl_block_data(db, block);
    reject_holes(
        lower_ctx_for_file(db, db.impl_locs.get(block).file).with_frame(impl_frame(db, block))
            .with_bounds(impl_generic_bounds(db, block))
            .lower_type_ref(data.type_refs, data.for_target),
    )
}

// port: baml_compiler2_hir_ty/src/lower.rs::impl_generic_bounds @ d9be6853b
// An impl block's declared generic bounds, conjunctive per param.
function impl_generic_bounds(
    db: root.hir.Db,
    block: int,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    let data = root.hir.impl_block_data(db, block);
    let frame = impl_frame(db, block);
    let ctx = lower_ctx_for_file(db, db.impl_locs.get(block).file).with_frame(frame);
    let out: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
    for (let i = 0; i < frame.length() && i < data.generics.length(); i += 1) {
        let bounds = data.generics[i].bounds.filter_map((type_ref) -> {
            root.types.as_interface(
                reject_holes(
                    ctx.lower_type_ref(
                        data.type_refs,
                        type_ref,
                        position = TypePosition.ConstraintHead,
                    ),
                ),
            )
        });
        if (bounds.length() != 0) {
            out[frame[i]] = bounds;
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::qualify_def @ d9be6853b
// The qualified name of a definition as its own file's package and namespace
// spell it.
function qualify_def(
    db: root.hir.Db,
    def: root.hir.Definition,
    name: string,
) -> root.types.DeclName throws never {
    let info = root.hir.file_package(db, root.hir.definition_file(def, db));
    root.types.DeclName { pkg: info.root_id, namespace: info.namespace_path, name: name }
}

// port: baml_compiler2_hir_ty/src/lower.rs::class_generic_frame @ d9be6853b
// The root generic frame for a class.
function class_generic_frame(db: root.hir.Db, class_: int) -> root.types.ParamTy[] throws never {
    let frame: root.types.ParamTy[] = [];
    extend_frame(
        frame,
        root.hir.class_data(db, class_).generic_params.map((g) -> {
            g.name
        }),
    );
    frame
}

// port: baml_compiler2_hir_ty/src/lower.rs::extend_frame @ d9be6853b
function extend_frame(frame: root.types.ParamTy[], names: string[]) -> void throws never {
    for (let name in names) {
        frame.push(root.types.ParamTy { index: frame.length(), name: name });
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::FunctionSignature @ d9be6853b
// A function's elaborated signature, lowered.
class FunctionSignature {
    generic_params: root.types.ParamTy[],
    params: SignatureParam[],
    ret: root.types.Ty,
    // The effective error type: the written clause when closed, the
    // body-inferred effect when open, the error sentinel for an interface
    // contract that poisons holes.
    throws_: root.types.Ty,
}

// port: baml_compiler2_hir_ty/src/lower.rs::FunctionSignatureResult @ d9be6853b
// `function_signature_with_diagnostics`' full result.
class FunctionSignatureResult {
    signature: FunctionSignature,
    diagnostics: SignatureDiag[],
}

// port: baml_compiler2_hir_ty/src/lower.rs::SignatureDiag @ d9be6853b
// A diagnostic recorded while lowering a signature, anchored in the
// elaborated store (or nowhere, when nothing was written).
type SignatureDiag = SignatureDiagMissingThrows | SignatureDiagThrowsHole;

// An interface method wrote no `throws` clause; renders at its name.
class SignatureDiagMissingThrows {
}

// An inference hole in an interface method's `throws` clause, at the `_`.
class SignatureDiagThrowsHole {
    type_ref: int,
}

// port: baml_compiler2_hir_ty/src/lower.rs::SignatureParam @ d9be6853b
class SignatureParam {
    name: string,
    ty: root.types.Ty,
    has_default: bool,
}

// port: baml_compiler2_hir_ty/src/lower.rs::reject_holes @ d9be6853b
// The finalized type: every hole becomes the `Error` sentinel (its rejection
// diagnostic is the position's own), the closed spine kept.
function reject_holes(ty: root.types.LoweringTy) -> root.types.Ty throws never {
    root.types.narrow_lowering_ty_to_ty(ty) catch (e) {
        root.types.NarrowError => fill_holes_as_errors(ty),
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::fill_holes_as_errors @ d9be6853b
// The slow path of `reject_holes`: rebuild with every `Infer` replaced by
// `Error`.
function fill_holes_as_errors(ty: root.types.LoweringTy) -> root.types.Ty throws never {
    let fill_interface = (interface_: root.types.LoweringInterfaceConstraint) -> root.types.InterfaceConstraint {
        root.types.InterfaceConstraint {
            name: interface_.name,
            generics: interface_.generics.map(fill_holes_as_errors),
            associated_types: interface_.associated_types
                .map((pin) -> {
                    root.types.AssociatedType { name: pin.name, ty: fill_holes_as_errors(pin.ty) }
                })
                .sort_by_key((pin) -> {
                    pin.name
                }),
        }
    };
    match (ty) {
        root.types.TyInfer => root.types.TyError {},
        let t: root.types.LoweringTyList => root.types.TyList { elem: fill_holes_as_errors(t.elem) },
        let t: root.types.LoweringTyMap => {
            root.types.TyMap {
                key: fill_holes_as_errors(t.key),
                value: fill_holes_as_errors(t.value),
            }
        },
        let t: root.types.LoweringTyUnion => {
            root.types.TyUnion { members: t.members.map(fill_holes_as_errors) }
        },
        let t: root.types.LoweringTyTuple => {
            root.types.TyTuple { items: t.items.map(fill_holes_as_errors) }
        },
        let t: root.types.LoweringTyClass => {
            root.types.TyClass { name: t.name, args: t.args.map(fill_holes_as_errors) }
        },
        let t: root.types.LoweringTyInterface => {
            root.types.TyInterface {
                name: t.name,
                args: t.args.map(fill_holes_as_errors),
                associated_types: t.associated_types.map((pin) -> {
                    root.types.AssociatedType { name: pin.name, ty: fill_holes_as_errors(pin.ty) }
                }),
            }
        },
        let t: root.types.LoweringTyFunction => {
            root.types.TyFunction {
                params: t.params.map((param) -> {
                    root.types.FunctionParamTy {
                        name: param.name,
                        ty: fill_holes_as_errors(param.ty),
                        mode: param.mode,
                    }
                }),
                ret: fill_holes_as_errors(t.ret),
                throws_: fill_holes_as_errors(t.throws_),
            }
        },
        let t: root.types.LoweringTyFuture => {
            root.types.TyFuture {
                value: fill_holes_as_errors(t.value),
                error: fill_holes_as_errors(t.error),
            }
        },
        let t: root.types.LoweringTyAssociatedTypeProjection => {
            root.types.TyAssociatedTypeProjection {
                base: fill_holes_as_errors(t.base),
                interface_: fill_interface(t.interface_),
                member: t.member,
            }
        },
        // Hole-free leaves: the generated narrowing is total on them.
        _ => {
            root.types.narrow_lowering_ty_to_ty(ty) catch (e) {
                root.types.NarrowError => {
                    baml.sys.panic("every hole-carrying shape is matched above")
                },
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::class_generic_bounds @ d9be6853b
// The declared interface bounds for a class's own generic frame.
function class_generic_bounds(
    db: root.hir.Db,
    class_: int,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    let frame = class_generic_frame(db, class_);
    let ctx = lower_ctx_for_file(db, db.class_locs.get(class_).file).with_frame(frame);
    let data = root.hir.class_data(db, class_);
    let out: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
    for (let i = 0; i < frame.length() && i < data.generic_params.length(); i += 1) {
        let refs = data.generic_params[i].bounds.filter_map((type_ref) -> {
            root.types.as_interface(
                reject_holes(
                    ctx.lower_type_ref(
                        data.type_refs,
                        type_ref,
                        position = TypePosition.ConstraintHead,
                    ),
                ),
            )
        });
        if (refs.length() != 0) {
            out[frame[i]] = refs;
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::function_generic_bounds @ d9be6853b
// The declared interface bounds for a function's full generic frame (owner
// prefix + own params; effect params unbounded).
function function_generic_bounds(
    db: root.hir.Db,
    function_: int,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    let frame = function_generic_frame(db, function_);
    let ctx = lower_ctx_for_file(db, db.function_locs.get(function_).file).with_frame(frame);
    let out: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
    // A lowered constraint head enters the bounds vocabulary through the
    // reject fold: a hole inside a written bound degrades to `Error`.
    let as_ref = (ty: root.types.LoweringTy) -> root.types.InterfaceConstraint? {
        root.types.as_interface(reject_holes(ty))
    };
    let next = 0;
    match (root.hir.method_owner(db, function_)) {
        let owner: root.hir.MethodOwnerClass => {
            let bounds = class_generic_bounds(db, owner.value);
            for (let param in bounds.keys()) {
                out[param] = bounds[param];
            }
            next = root.hir.class_data(db, owner.value).generic_params.length();
        },
        let owner: root.hir.MethodOwnerInterface => {
            let bounds = interface_scope_bounds(db, owner.value);
            for (let param in bounds.keys()) {
                out[param] = bounds[param];
            }
            next = root.hir.interface_data(db, owner.value).generic_params.length() + 1;
        },
        let owner: root.hir.MethodOwnerImpl => {
            let impl_data = root.hir.impl_block_data(db, owner.value);
            for (let param_data in impl_data.generics) {
                if (next >= frame.length()) {
                    break;
                }
                let bounds = param_data.bounds.filter_map((type_ref) -> {
                    as_ref(
                        ctx.lower_type_ref(
                            impl_data.type_refs,
                            type_ref,
                            position = TypePosition.ConstraintHead,
                        ),
                    )
                });
                if (bounds.length() != 0) {
                    out[frame[next]] = bounds;
                }
                next += 1;
            }
        },
        null => {},
    }
    let data = root.hir.function_data(db, function_);
    for (let declared in data.generic_params) {
        if (next >= frame.length()) {
            break;
        }
        let refs = declared.bounds.filter_map((type_ref) -> {
            as_ref(ctx.lower_type_ref(data.type_refs, type_ref, position = TypePosition.ConstraintHead))
        });
        if (refs.length() != 0) {
            out[frame[next]] = refs;
        }
        next += 1;
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::interface_scope_bounds @ d9be6853b
// The interface scope's param env: `Self` bounded by the interface itself at
// its own params (no pins), plus each generic param's declared bound.
function interface_scope_bounds(
    db: root.hir.Db,
    interface_: int,
) -> map<root.types.ParamTy, root.types.InterfaceConstraint[]> throws never {
    let data = root.hir.interface_data(db, interface_);
    let frame = interface_frame(db, interface_);
    let ctx = lower_ctx_for_file(db, db.interface_locs.get(interface_).file).with_frame(frame);
    let out: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
    if (frame.length() == 0) {
        return out;
    }
    let args: root.types.Ty[] = frame.slice(1, data.generic_params.length() + 1).map((param) -> {
        root.types.TyTypeVar { param: param }
    });
    out[frame[0]]
        = [
            root.types.InterfaceConstraint {
                name: interface_qualified_name(db, interface_),
                generics: args,
                associated_types: [],
            },
        ];
    for (let i = 0; i < data.generic_params.length() && i + 1 < frame.length(); i += 1) {
        let refs = data.generic_params[i].bounds.filter_map((type_ref) -> {
            root.types.as_interface(
                reject_holes(
                    ctx.lower_type_ref(
                        data.type_refs,
                        type_ref,
                        position = TypePosition.ConstraintHead,
                    ),
                ),
            )
        });
        if (refs.length() != 0) {
            out[frame[i + 1]] = refs;
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::interface_qualified_name @ d9be6853b
function interface_qualified_name(
    db: root.hir.Db,
    interface_: int,
) -> root.types.DeclName throws never {
    let package = root.hir.file_package(db, db.interface_locs.get(interface_).file);
    root.types.DeclName {
        pkg: package.root_id,
        namespace: package.namespace_path,
        name: root.hir.interface_data(db, interface_).name,
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::signature_is_interface_contract @ d9be6853b
// Whether `function_`'s signature is an interface's dispatch contract;
// generated language-internal declarations are exempt.
function signature_is_interface_contract(db: root.hir.Db, function_: int) -> bool throws never {
    root.hir.method_owner(db, function_) is root.hir.MethodOwnerInterface
        && !root.hir.function_data(db, function_).metadata.is_language_internal
}

// port: baml_compiler2_hir_ty/src/lower.rs::function_signature_cycle_initial @ d9be6853b
// The fixpoint seed for the signature / throws / inference cycle: only the
// throws type depends on the body, so only it is seeded, at `never`.
function function_signature_cycle_initial(
    db: root.hir.Db,
    function_: int,
) -> FunctionSignatureResult throws never {
    lower_function_signature(db, function_, ThrowsSource.Seed)
}

// port: baml_compiler2_hir_ty/src/lower.rs::ThrowsSource @ d9be6853b
// Where a signature's throws type comes from: the written clause and, for an
// open one, the body fixpoint, or the fixpoint's seed.
enum ThrowsSource {
    Lowered,
    Seed,
}

// port: baml_compiler2_hir_ty/src/lower.rs::owner_self_ty @ d9be6853b
// The concrete `Self` a method's owner provides; null for interface owners
// and free functions.
function owner_self_ty(db: root.hir.Db, function_: int) -> root.types.Ty? throws never {
    match (root.hir.method_owner(db, function_)) {
        let owner: root.hir.MethodOwnerClass => class_self_ty(db, owner.value),
        let owner: root.hir.MethodOwnerImpl => impl_self_ty(db, owner.value),
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::owner_impl_target @ d9be6853b
// The realized interface target of an implements-block method: the written
// reference plus its written `type Member = ...` bindings as pins.
// Restructured: Rust first reads `impls::impl_facts` for a target served from
// an interface (`mounted_type_row`). While no root is served from an
// interface every `mounted_type_row` answers null, so that branch is taken
// only when some root is; `impl_facts` is not ported.
function owner_impl_target(
    db: root.hir.Db,
    function_: int,
    frame: root.types.ParamTy[],
) -> root.types.InterfaceConstraint? throws never {
    let owner = root.hir.method_owner(db, function_);
    let any_served = db.root_order.some((root_id) -> {
        root.hir.is_served_from_interface(db, root_id)
    });
    if (any_served && owner is root.hir.MethodOwnerImpl) {
        let facts = impl_header_resolution_for_display(impl_facts(db, owner.value));
        if (facts != null) {
            let pool = db.ty_memo.pool;
            let interface_ = facts.interface_.to_plain(pool);
            if (mounted_type_row(db, interface_.name) != null) {
                let pins = interface_.associated_types.concat([]);
                for (let fact in facts.associated_types) {
                    let ty = pool.to_plain_closed(fact.1.ty);
                    if let existing: int = pins.find_index((pin) -> {
                        pin.name == fact.0
                    }) {
                        pins[existing] = root.types.AssociatedType { name: fact.0, ty: ty };
                    } else {
                        pins.push(root.types.AssociatedType { name: fact.0, ty: ty });
                    }
                }
                return root.types.InterfaceConstraint {
                    name: interface_.name,
                    generics: interface_.generics,
                    associated_types: pins.sort_by_key((pin) -> {
                        pin.name
                    }),
                };
            }
        }
    }

    let target = root.hir.method_interface_target(db, function_)
        ?? return null;
    // The impl's bounds ride along: a written `type Member = T.Item` must find
    // `Item`'s declaring interface through `T`'s bound.
    let ctx = lower_ctx_for_file(db, db.function_locs.get(function_).file).with_frame(frame).with_bounds(
        function_generic_bounds(db, function_),
    );
    let interface_ = root.types.as_interface(
        reject_holes(
            ctx.lower_type_ref(
                target.type_refs,
                target.target,
                position = TypePosition.ConstraintHead,
            ),
        ),
    )
        ?? return null;
    let pins = target.associated_type_bindings.filter_map((binding) -> {
        let type_ref = binding.type_ref;
        if (type_ref == null) {
            null
        } else {
            root.types.AssociatedType {
                name: binding.name,
                ty: reject_holes(ctx.lower_type_ref(target.type_refs, type_ref)),
            }
        }
    });
    for (let pin in interface_.associated_types) {
        if (
            !pins.some((have) -> {
                have.name == pin.name
            })
        ) {
            pins.push(pin);
        }
    }
    root.types.InterfaceConstraint {
        name: interface_.name,
        generics: interface_.generics,
        associated_types: pins.sort_by_key((pin) -> {
            pin.name
        }),
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::lowering_diag_error @ d9be6853b
// A recorded lowering diagnostic as the shared error vocabulary.
function lowering_diag_error(kind: LoweringDiagKind) -> TirTypeError throws never {
    match (kind) {
        let k: LoweringDiagKindUnresolved => {
            removed_reflect_spelling(k.name)
                ?? TirTypeErrorUnresolvedType { name: k.name, suggestions: k.suggestions }
        },
        let k: LoweringDiagKindWrongArgCount => {
            TirTypeErrorWrongNumberOfTypeArgs {
                type_name: k.name,
                expected: k.expected,
                got: k.got,
            }
        },
        let k: LoweringDiagKindInvalidMapKey => TirTypeErrorInvalidMapKeyType { key: k.key },
        let k: LoweringDiagKindProjection => k.value,
        LoweringDiagKindFnTypeMissingThrows => TirTypeErrorFunctionTypeMissingThrows {},
        // The position's own report is the specific one (an interface
        // signature's is E0170); this is the generic spelling.
        let k: LoweringDiagKindHoleNotAllowed => {
            match (k.reason) {
                NoInferReason.InterfaceSignature | NoInferReason.TypeBinding => {
                    TirTypeErrorCannotInferType {}
                },
                NoInferReason.ProjectionBase => TirTypeErrorWildcardInProjectionSubject {},
            }
        },
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::extend_lowering_diagnostics @ d9be6853b
function extend_lowering_diagnostics(
    out: (root.syntax.TextRange, TirTypeError)[],
    source_map: root.hir.TypeRefSourceMap,
    diagnostics: LoweringDiag[],
) -> void throws never {
    for (let diag in diagnostics) {
        out.push((source_map.span(diag.type_ref), lowering_diag_error(diag.kind)));
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::is_open_throws_contract @ d9be6853b
// Whether a declared throws clause is an open contract: it names `unknown`
// directly, through a union member, or through a type alias. Restructured:
// `ty` is a handle into `db.ty_memo.pool`; Rust's nested `visit` is
// `is_open_throws_contract_visit`.
function is_open_throws_contract(db: root.hir.Db, ty: int) -> bool throws never {
    is_open_throws_contract_visit(db.ty_memo.pool, Facts.new(db), ty, {})
}

// port: baml_compiler2_hir_ty/src/lower.rs::is_open_throws_contract::visit @ d9be6853b
function is_open_throws_contract_visit(
    pool: root.types.InferPool,
    facts: Facts,
    ty: int,
    seen_aliases: map<root.types.DeclName, bool>,
) -> bool throws never {
    match (pool.kinds[ty]) {
        root.types.TyUnknown => true,
        let u: root.types.InferTyUnion => {
            u.members.some((member) -> {
                is_open_throws_contract_visit(pool, facts, member, seen_aliases)
            })
        },
        let alias: root.types.TyTypeAlias if !seen_aliases.has(alias.name) => {
            seen_aliases[alias.name] = true;
            let target = facts.alias_def(alias.name);
            if (target == null) {
                false
            } else {
                is_open_throws_contract_visit(pool, facts, pool.from_plain(target), seen_aliases)
            }
        },
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::signature_lowering_diagnostics @ d9be6853b
// The check layer's signature diagnostic walk: every written signature type
// re-lowered with the sink and judged for generic-argument well-formedness,
// then the bounds (E0145, E0154, binding bounds) and method generic
// shadowing.
function signature_lowering_diagnostics(
    db: root.hir.Db,
    function_: int,
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    let data = root.hir.elaborated_function_data(db, function_);
    let frame = function_generic_frame(db, function_);
    let bounds = function_generic_bounds(db, function_);
    let concrete_self = owner_self_ty(db, function_);
    let impl_target = owner_impl_target(db, function_, frame);
    let file = db.function_locs.get(function_).file;
    let ctx = lower_ctx_for_file(db, file).with_frame(frame)
        .with_bounds(bounds)
        .with_self_ty(concrete_self)
        .with_impl_target(impl_target);
    // Params/ret/throws lower from the elaborated store and resolve spans
    // through the elaborated source map.
    let elaborated_map = root.hir.elaborated_function_source_map(db, function_);
    let scope_env = function_generic_bounds(db, function_);
    let out: (root.syntax.TextRange, TirTypeError)[] = [];
    let lower_and_judge = (type_ref: int) -> void {
        let (let lowered, let diagnostics) = ctx.lower_type_ref_with_diagnostics(data.type_refs, type_ref);
        extend_lowering_diagnostics(out, elaborated_map.type_refs, diagnostics);
        for (let error in root.hir_ty.interfaces.type_generic_bound_errors(db, scope_env, lowered)) {
            out.push((elaborated_map.type_refs.span(type_ref), error));
        }
    };
    for (let param in data.params) {
        // The unannotated-`self` slot lowers as `Missing` by elaboration; it
        // is not a written reference.
        if (
            param.name == "self"
                && data.type_refs.get(param.type_ref).kind is root.hir.TypeRefKindMissing
        ) {
            continue;
        }
        lower_and_judge(param.type_ref);
    }
    let ret = data.return_type;
    if (ret != null) {
        lower_and_judge(ret);
    }
    let throws_ = data.throws_;
    if (throws_ != null) {
        lower_and_judge(throws_);
    }
    // A bound must name an interface directly (E0145). Bounds lower from the
    // written store, so their spans use the written source map.
    let source_map = root.hir.function_source_map(db, function_);
    let func_data = root.hir.function_data(db, function_);
    for (let generic in func_data.generic_params) {
        for (let bound in generic.bounds) {
            let (let lowered, let diagnostics) = ctx.lower_type_ref_with_diagnostics(
                func_data.type_refs,
                bound,
                position = TypePosition.ConstraintHead,
            );
            extend_lowering_diagnostics(out, source_map.type_refs, diagnostics);
            judge_bound_shape(db, func_data.type_refs, source_map.type_refs, bound, lowered, out);
        }
    }
    for (let error in method_generic_shadowing(db, function_, func_data.generic_params)) {
        out.push((source_map.name_span, error));
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::judge_constraint_head @ d9be6853b
// (its shape rules, after lowering). Restructured: Rust writes this match
// twice, in `signature_lowering_diagnostics` and `judge_constraint_head`; it
// is one function here. The compiler-derived `reflect.AnyFunction` is a
// value type, never a bound (E0154); an interface bound's written bindings
// must meet their declared bounds; anything else that is not an error is
// E0145.
function judge_bound_shape(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    source_map: root.hir.TypeRefSourceMap,
    bound: int,
    lowered: root.types.LoweringTy,
    out: (root.syntax.TextRange, TirTypeError)[],
) -> void throws never {
    match (lowered) {
        let i: root.types.LoweringTyInterface
            if root.types.decl_name_is_lang_root_type(
            i.name,
            root.hir.lang_roots(db),
            root.base.LangPackage.Reflect,
            "AnyFunction",
        ) => {
            out.push(
                (
                    source_map.span(bound),
                    TirTypeErrorBuiltinInterfaceNotABound { interface_: i.name },
                ),
            );
        },
        root.types.LoweringTyInterface => {
            for (let error in bound_binding_violations(db, store, bound, reject_holes(lowered))) {
                out.push((source_map.span(bound), error));
            }
        },
        // The lowering already reported why the head is an error.
        _
            if root.types.any_node(lowered, (node) -> {
            node is root.types.TyError
        }) => {},
        _ => {
            out.push(
                (
                    source_map.span(bound),
                    TirTypeErrorGenericBoundNotInterface { bound: reject_holes(lowered) },
                ),
            );
        },
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::method_generic_shadowing @ d9be6853b
// A method's own generic parameter may not reuse the name of a generic
// parameter of its owner (rustc's E0403).
function method_generic_shadowing(
    db: root.hir.Db,
    function_: int,
    own: root.hir.GenericParamData[],
) -> TirTypeError[] throws never {
    match (root.hir.method_owner(db, function_)) {
        null => [],
        let owner: root.hir.MethodOwnerClass => {
            let data = root.hir.class_data(db, owner.value);
            let names = data.generic_params.map((g) -> {
                g.name
            });
            own
                .filter((param) -> {
                    names.includes(param.name)
                })
                .map((param) -> {
                    TirTypeErrorTypeParamShadowed {
                        param_name: param.name,
                        type_name: data.name,
                        owner: ShadowedParamOwner.Class,
                    }
                })
        },
        let owner: root.hir.MethodOwnerInterface => {
            let data = root.hir.interface_data(db, owner.value);
            let names = data.generic_params.map((g) -> {
                g.name
            });
            own
                .filter((param) -> {
                    names.includes(param.name)
                })
                .map((param) -> {
                    TirTypeErrorTypeParamShadowed {
                        param_name: param.name,
                        type_name: data.name,
                        owner: ShadowedParamOwner.Interface,
                    }
                })
        },
        let owner: root.hir.MethodOwnerImpl => {
            // An in-class block's frame is the class's, so the shadowed
            // parameter is named as the class's own.
            let in_class = root.hir.impl_class(db, owner.value);
            let names = impl_frame(db, owner.value).map((param) -> {
                param.name
            });
            own
                .filter((param) -> {
                    names.includes(param.name)
                })
                .map((param) -> {
                    let error: TirTypeError = if let class_: int = in_class {
                        TirTypeErrorTypeParamShadowed {
                            param_name: param.name,
                            type_name: root.hir.class_data(db, class_).name,
                            owner: ShadowedParamOwner.Class,
                        }
                    } else {
                        TirTypeErrorTypeParamShadowedImplParam { param_name: param.name }
                    };
                    error
                })
        },
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::bound_binding_violations @ d9be6853b
// An explicit associated binding written on a generic bound (`P extends
// Parser<Output = V>`) must implement that member's own declared bound. Only
// written bindings; a value still carrying a type variable fails open.
function bound_binding_violations(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    bound: int,
    lowered: root.types.Ty,
) -> TirTypeError[] throws never {
    let path = match (store.get(bound).kind) {
        let k: root.hir.TypeRefKindPath => k,
        _ => {
            return [];
        },
    };
    if (path.associated_type_bindings.length() == 0) {
        return [];
    }
    let existential = match (lowered) {
        let i: root.types.TyInterface => i,
        _ => {
            return [];
        },
    };
    let head = root.types.InterfaceConstraint {
        name: existential.name,
        generics: existential.args,
        associated_types: existential.associated_types.concat([]).sort_by_key((pin) -> {
            pin.name
        }),
    };
    let facts = Facts.new(db);
    let out: TirTypeError[] = [];
    for (let written in path.associated_type_bindings) {
        // An unknown binding name was diagnosed and dropped by lowering.
        let pin = existential.associated_types.find((pin) -> {
            pin.name == written.name
        });
        if (pin == null) {
            continue;
        }
        let value = pin.ty;
        if (
            root.types.contains_ty_where(value, (t) -> {
                t is root.types.TyTypeVar
            })
        ) {
            continue;
        }
        let normalized = facts.normalize(value);
        for (let declared in facts.associated_type_bound(head, written.name)) {
            if (!root.hir_ty.interfaces.normalized_arg_implements_bound(facts, normalized, declared)) {
                out.push(
                    TirTypeErrorAssociatedTypeBindingViolatesBound {
                        interface_: existential.name,
                        name: written.name,
                        binding: value,
                        bound: declared,
                    },
                );
            }
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::judge_constraint_head @ d9be6853b
// Judge one constraint head (`T extends B`, `type A extends B`): lower it
// with the sink, then apply the shape rules a bound must satisfy. Every bound
// position routes here.
function judge_constraint_head(
    db: root.hir.Db,
    ctx: LowerCtx,
    store: root.hir.TypeRefStore,
    source_map: root.hir.TypeRefSourceMap,
    bound: int,
    out: (root.syntax.TextRange, TirTypeError)[],
) -> void throws never {
    let (let lowered, let diagnostics) = ctx.lower_type_ref_with_diagnostics(store, bound, position = TypePosition.ConstraintHead);
    extend_lowering_diagnostics(out, source_map, diagnostics);
    judge_bound_shape(db, store, source_map, bound, lowered, out);
}

// port: baml_compiler2_hir_ty/src/lower.rs::class_lowering_diagnostics @ d9be6853b
// The check layer's class walk: field annotations re-lowered with the sink
// and judged for well-formedness, then the generic-param bounds.
function class_lowering_diagnostics(
    db: root.hir.Db,
    class_: int,
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    let data = root.hir.class_data(db, class_);
    let source_map = root.hir.class_source_map(db, class_);
    let frame = class_generic_frame(db, class_);
    let ctx = lower_ctx_for_file(db, db.class_locs.get(class_).file).with_frame(frame).with_bounds(
        class_generic_bounds(db, class_),
    );
    let out: (root.syntax.TextRange, TirTypeError)[] = [];
    let scope_env = class_generic_bounds(db, class_);
    for (let field in data.fields) {
        let (let lowered, let diagnostics) = ctx.lower_type_ref_with_diagnostics(data.type_refs, field.type_ref);
        extend_lowering_diagnostics(out, source_map.type_refs, diagnostics);
        for (let error in root.hir_ty.interfaces.type_generic_bound_errors(db, scope_env, lowered)) {
            out.push((source_map.type_refs.span(field.type_ref), error));
        }
    }
    for (let generic in data.generic_params) {
        for (let bound in generic.bounds) {
            judge_constraint_head(db, ctx, data.type_refs, source_map.type_refs, bound, out);
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::file_root @ d9be6853b
function file_root(db: root.hir.Db, file: int) -> int throws never {
    root.hir.file_package(db, file).root_id
}

// port: baml_compiler2_hir_ty/src/lower.rs::DeclCycles @ d9be6853b
class DeclCycles {
    invalid_aliases: root.types.DeclName[],
    class_cycles: root.types.DeclName[][],
}

// port: baml_compiler2_hir_ty/src/lower.rs::package_decl_cycles @ d9be6853b
// The package's aliases with no finite value (sorted) and its unconstructable
// class cycles.
function package_decl_cycles(db: root.hir.Db, root_id: int) -> DeclCycles throws never {
    db.ty_memo.package_decl_cycles.get(db.cycles, root_id, () -> {
        let aliases: map<root.types.DeclName, root.types.Ty> = {};
        let class_fields: map<root.types.DeclName, (string, root.types.Ty)[]> = {};
        for (let namespace in root.hir.package_items(db, root_id).namespaces) {
            let types = namespace.1.types;
            for (let name in types.keys()) {
                let def = types[name];
                match (def) {
                    let alias: root.hir.DefinitionTypeAlias => {
                        aliases[qualify_def(db, def, name)] = type_alias_value(db, alias.value);
                    },
                    let class_: root.hir.DefinitionClass => {
                        class_fields[qualify_def(db, def, name)]
                            = resolve_class_fields(db, class_.value).map((field) -> {
                                (field.0, field.1)
                            });
                    },
                    _ => {},
                }
            }
        }
        let invalid_aliases = root.types.find_invalid_alias_cycles(aliases).keys();
        invalid_aliases.sort_by(root.types.cmp_decl_name);
        DeclCycles {
            invalid_aliases: invalid_aliases,
            class_cycles: root.types.find_invalid_class_cycles(class_fields, aliases).map((cycle) -> {
                cycle.members
            }),
        }
    })
}

// port: baml_compiler2_hir_ty/src/lower.rs::interface_lowering_diagnostics @ d9be6853b
// The check layer's interface walk: fields, required methods, generic and
// associated-type bounds and defaults, missing `throws` contracts (E0170),
// `requires` cycles (E0118) and non-interface `requires` targets.
function interface_lowering_diagnostics(
    db: root.hir.Db,
    interface_: int,
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    let data = root.hir.interface_data(db, interface_);
    let frame = interface_frame(db, interface_);
    let ctx = lower_ctx_for_file(db, db.interface_locs.get(interface_).file).with_frame(frame).with_bounds(
        interface_scope_bounds(db, interface_),
    );
    let source_map = root.hir.interface_source_map(db, interface_);
    let out: (root.syntax.TextRange, TirTypeError)[] = [];
    let scope_env = interface_scope_bounds(db, interface_);
    for (let field in data.fields) {
        let (let lowered, let diagnostics) = ctx.lower_type_ref_with_diagnostics(data.type_refs, field.type_ref);
        extend_lowering_diagnostics(out, source_map.type_refs, diagnostics);
        for (let error in root.hir_ty.interfaces.type_generic_bound_errors(db, scope_env, lowered)) {
            out.push((source_map.type_refs.span(field.type_ref), error));
        }
    }
    // Required-method signatures judge through their resolved forms.
    let resolved = root.hir_ty.interfaces.resolve_interface_required_methods(db, interface_);
    let method_scope_env = interface_scope_bounds(db, interface_);
    for (let index = 0; index < resolved.length(); index += 1) {
        let method = resolved[index];
        let env = method_scope_env;
        let own: map<root.types.ParamTy, root.types.InterfaceConstraint[]> = {};
        for (let param in env.keys()) {
            own[param] = env[param];
        }
        for (let generic in method.generic_params) {
            own[generic.0] = generic.1;
        }
        let span = source_map.required_method_spans.at(index)?.name_span ?? source_map.name_span;
        for (
            let error in root.hir_ty.interfaces.type_generic_bound_errors(
                db,
                own,
                root.types.widen_ty_to_lowering_ty(method.function_ty),
            )
        ) {
            out.push((span, error));
        }
    }
    // The interface's own generic parameters carry a class's bound rules.
    for (let generic in data.generic_params) {
        for (let bound in generic.bounds) {
            judge_constraint_head(db, ctx, data.type_refs, source_map.type_refs, bound, out);
        }
    }
    // Associated-type bounds (`type X extends B`).
    for (let assoc in data.associated_types) {
        let bound = assoc.bound;
        if (bound != null) {
            judge_constraint_head(db, ctx, data.type_refs, source_map.type_refs, bound, out);
        }
    }
    // An associated type's default is a written type reference like any
    // other: its lowering diagnostics surface here, once.
    for (let assoc in data.associated_types) {
        let default_ref = assoc.default;
        if (default_ref == null) {
            continue;
        }
        let found = root.hir_ty.interfaces.interface_associated_type_default(db, interface_, assoc.name);
        if (found == null) {
            continue;
        }
        for (let error in found.1) {
            out.push((source_map.type_refs.span(default_ref), error));
        }
    }
    // An associated type's default must implement its declared bound.
    let facts = Facts.with_bounds(db, interface_scope_bounds(db, interface_));
    let own_params: root.types.Ty[] = interface_declared_params(db, interface_).map((param) -> {
        root.types.TyTypeVar { param: param }
    });
    let head = root.types.InterfaceConstraint {
        name: interface_qualified_name(db, interface_),
        generics: own_params,
        associated_types: [],
    };
    for (let assoc in data.associated_types) {
        let default_ref = assoc.default;
        if (default_ref == null || assoc.bound == null) {
            continue;
        }
        let found = root.hir_ty.interfaces.interface_associated_type_default(db, interface_, assoc.name);
        if (found == null) {
            continue;
        }
        let normalized = facts.normalize(found.0);
        for (let declared in facts.associated_type_bound(head, assoc.name)) {
            if (!root.hir_ty.interfaces.normalized_arg_implements_bound(facts, normalized, declared)) {
                out.push(
                    (
                        source_map.type_refs.span(default_ref),
                        TirTypeErrorAssociatedTypeDefaultViolatesBound {
                            interface_: interface_qualified_name(db, interface_),
                            name: assoc.name,
                            default_: found.0,
                            bound: declared,
                        },
                    ),
                );
            }
        }
    }
    // Every interface method must declare its `throws` clause explicitly
    // and completely (E0170): render what the signature run recorded.
    for (let method in data.methods) {
        for (let diag in function_signature_with_diagnostics(db, method).diagnostics) {
            let span = match (diag) {
                SignatureDiagMissingThrows => root.hir.function_source_map(db, method).name_span,
                // At the `_` itself, in the elaborated store.
                let hole: SignatureDiagThrowsHole => {
                    root.hir.elaborated_function_source_map(db, method).type_refs.span(
                        hole.type_ref,
                    )
                },
            };
            out.push(
                (
                    span,
                    TirTypeErrorInterfaceMethodMissingThrows {
                        interface_: interface_qualified_name(db, interface_),
                        method: root.hir.function_data(db, method).name,
                    },
                ),
            );
        }
    }
    // Associated-type bounds re-lower with the sink (Rust discards the
    // result).
    for (let assoc in data.associated_types) {
        let bound = assoc.bound;
        if (bound != null) {
            ctx.lower_type_ref(data.type_refs, bound, position = TypePosition.ConstraintHead);
        }
    }
    // A transitive `requires` graph cycling back to this interface (E0118).
    let chain = root.hir_ty.interfaces.interface_requires_cycle(db, interface_);
    if (chain != null) {
        out.push((source_map.name_span, TirTypeErrorInterfaceRequiresCycle { chain: chain }));
    }
    for (let target in data.requires_) {
        let (let lowered, let diagnostics) = ctx.lower_type_ref_with_diagnostics(
            data.type_refs,
            target,
            position = TypePosition.ConstraintHead,
        );
        extend_lowering_diagnostics(out, source_map.type_refs, diagnostics);
        if (
            !root.types.any_node(lowered, (node) -> {
                node is root.types.TyError
            })
                && !(lowered is root.types.LoweringTyInterface)
        ) {
            out.push(
                (
                    source_map.type_refs.span(target),
                    TirTypeErrorInterfaceRequiresNonInterface {
                        interface_: interface_qualified_name(db, interface_),
                        target: reject_holes(lowered),
                    },
                ),
            );
        }
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::resolve_class_fields @ d9be6853b
// A class's fields resolved to plain types, with their attributes.
function resolve_class_fields(
    db: root.hir.Db,
    class_: int,
) -> (string, root.types.Ty, root.hir.ClassFieldAttrs)[] throws never {
    db.ty_memo.resolve_class_fields.get(db.cycles, class_, () -> {
        let data = root.hir.class_data(db, class_);
        let ctx = lower_ctx_for_file(db, db.class_locs.get(class_).file)
            .with_frame(class_generic_frame(db, class_))
            .with_bounds(class_generic_bounds(db, class_));
        data.fields.map((field) -> {
            (
                field.name,
                reject_holes(ctx.lower_type_ref(data.type_refs, field.type_ref)),
                field.attrs,
            )
        })
    })
}

// port: baml_compiler2_hir_ty/src/lower.rs::let_declared_type @ d9be6853b
// The declared type of a top-level `let`: its written `: T`, or null for an
// unannotated binding. Lowered in the file's namespace with an empty frame.
function let_declared_type(db: root.hir.Db, binding: int) -> root.types.Ty? throws never {
    db.ty_memo.let_declared_type.get(db.cycles, binding, () -> {
        let data = root.hir.let_data(db, binding);
        let annotation = data.annotation
            ?? return null;
        let ctx = lower_ctx_for_file(db, db.let_locs.get(binding).file);
        reject_holes(ctx.lower_type_ref(data.type_refs, annotation))
    })
}

// port: baml_compiler2_hir_ty/src/lower.rs::let_lowering_diagnostics @ d9be6853b
// The check layer's walk over a global's annotation, as a type alias body.
function let_lowering_diagnostics(
    db: root.hir.Db,
    binding: int,
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    let data = root.hir.let_data(db, binding);
    let annotation = data.annotation
        ?? return [];
    let ctx = lower_ctx_for_file(db, db.let_locs.get(binding).file);
    let (let lowered, let diagnostics) = ctx.lower_type_ref_with_diagnostics(data.type_refs, annotation);
    let source_map = root.hir.let_source_map(db, binding);
    let out: (root.syntax.TextRange, TirTypeError)[] = [];
    extend_lowering_diagnostics(out, source_map.type_refs, diagnostics);
    for (let error in root.hir_ty.interfaces.type_generic_bound_errors(db, {}, lowered)) {
        out.push((source_map.type_refs.span(annotation), error));
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::type_alias_lowering_diagnostics @ d9be6853b
// The check layer's type-alias walk: the body re-lowered with the sink and
// judged, then the alias's own cycle (E0xxx `AliasCycle`).
function type_alias_lowering_diagnostics(
    db: root.hir.Db,
    alias: int,
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    let data = root.hir.type_alias_data(db, alias);
    let value = data.value
        ?? return [];
    let file = db.type_alias_locs.get(alias).file;
    let ctx = lower_ctx_for_file(db, file);
    let (let lowered, let diagnostics) = ctx.lower_type_ref_with_diagnostics(data.type_refs, value);
    let source_map = root.hir.type_alias_source_map(db, alias);
    let out: (root.syntax.TextRange, TirTypeError)[] = [];
    extend_lowering_diagnostics(out, source_map.type_refs, diagnostics);
    for (let error in root.hir_ty.interfaces.type_generic_bound_errors(db, {}, lowered)) {
        out.push((source_map.type_refs.span(value), error));
    }
    let head = qualify_def(db, root.hir.DefinitionTypeAlias { value: alias }, data.name);
    if (package_decl_cycles(db, file_root(db, file)).invalid_aliases.includes(head)) {
        out.push((source_map.name_span, TirTypeErrorAliasCycle { name: data.name }));
    }
    out
}

// port: baml_compiler2_hir_ty/src/lower.rs::function_signature_with_diagnostics @ d9be6853b
// The signature and the diagnostics its lowering recorded. A cycle head
// (signature -> callable_throws -> body inference -> signature) iterates
// from `function_signature_cycle_initial`.
function function_signature_with_diagnostics(
    db: root.hir.Db,
    function_: int,
) -> FunctionSignatureResult throws never {
    db.ty_memo.function_signature_with_diagnostics.get_fixpoint(
        db.cycles,
        function_,
        () -> {
            function_signature_cycle_initial(db, function_)
        },
        () -> {
            lower_function_signature(db, function_, ThrowsSource.Lowered)
        },
    )
}

// port: baml_compiler2_hir_ty/src/lower.rs::DeclaredThrows @ d9be6853b
// A function's written `throws` clause, read in its signature's environment.
type DeclaredThrows = DeclaredThrowsOmitted | DeclaredThrowsPartial | DeclaredThrowsClosed;

// No clause: `throws _`, the body's inferred effect alone.
class DeclaredThrowsOmitted {
}

// A clause with a `_` member: the members it names, beside the body's
// inferred remainder.
class DeclaredThrowsPartial {
    named: root.types.Ty,
}

// A clause with no `_` member: exactly what it names.
class DeclaredThrowsClosed {
    value: root.types.Ty,
}

// port: baml_compiler2_hir_ty/src/lower.rs::declared_throws @ d9be6853b
// The written `throws` clause, lowered once in the signature's environment.
function declared_throws(db: root.hir.Db, function_: int) -> DeclaredThrows throws never {
    db.ty_memo.declared_throws.get(db.cycles, function_, () -> {
        let data = root.hir.elaborated_function_data(db, function_);
        let throws_ = data.throws_
            ?? return DeclaredThrowsOmitted {};
        let lowered = signature_lower_ctx(db, function_).lower_type_ref(data.type_refs, throws_);
        let (let named, let open) = throws_clause_parts(lowered);
        let declared: DeclaredThrows = if (open) {
            DeclaredThrowsPartial { named: named }
        } else {
            DeclaredThrowsClosed { value: reject_holes(lowered) }
        };
        declared
    })
}

// port: baml_compiler2_hir_ty/src/lower.rs::signature_lower_ctx @ d9be6853b
// The context a function's signature lowers in: frame, bounds, the owner's
// concrete `Self` and impl target.
function signature_lower_ctx(db: root.hir.Db, function_: int) -> LowerCtx throws never {
    let frame = function_generic_frame(db, function_);
    let impl_target = owner_impl_target(db, function_, frame);
    lower_ctx_for_file(db, db.function_locs.get(function_).file).with_frame(frame)
        .with_bounds(function_generic_bounds(db, function_))
        .with_self_ty(owner_self_ty(db, function_))
        .with_impl_target(impl_target)
}

// port: baml_compiler2_hir_ty/src/lower.rs::lower_function_signature @ d9be6853b
function lower_function_signature(
    db: root.hir.Db,
    function_: int,
    throws_source: ThrowsSource,
) -> FunctionSignatureResult throws never {
    let data = root.hir.elaborated_function_data(db, function_);
    let frame = function_generic_frame(db, function_);
    // The owner's concrete `Self`: written `Self` resolves through the ctx,
    // and an unannotated `self` receiver takes it directly.
    let concrete_self = owner_self_ty(db, function_);
    let owner = root.hir.method_owner(db, function_);
    // An interface method's signature is a dispatch contract: no part of it
    // may be inferred.
    let interface_owner = signature_is_interface_contract(db, function_);
    let ctx = signature_lower_ctx(db, function_);
    if (interface_owner) {
        ctx.with_holes_forbidden(NoInferReason.InterfaceSignature);
    }
    let params = data.params.map((param) -> {
        let receiver: root.types.Ty? = if (
            param.name == "self"
                && data.type_refs.get(param.type_ref).kind is root.hir.TypeRefKindMissing
        ) {
            match (owner) {
                root.hir.MethodOwnerInterface => root.types.TyTypeVar { param: frame[0] },
                _ => concrete_self,
            }
        } else {
            null
        };
        SignatureParam {
            name: param.name,
            ty: receiver ?? reject_holes(ctx.lower_type_ref(data.type_refs, param.type_ref)),
            has_default: param.has_default,
        }
    });
    let ret_ref = data.return_type;
    let ret: root.types.Ty = if (ret_ref != null) {
        reject_holes(ctx.lower_type_ref(data.type_refs, ret_ref))
    } else {
        root.types.TyError {}
    };
    // Omitted `throws` means `throws _`. In an interface contract holes
    // poison and an unwritten clause is a missing contract; elsewhere an
    // open clause fills from the body's inferred effect and a closed one is
    // taken verbatim.
    let diagnostics: SignatureDiag[] = [];
    let written = data.throws_;
    let throws_: root.types.Ty = if (interface_owner) {
        if (written != null) {
            let (let lowered, let diags) = ctx.lower_type_ref_with_diagnostics(data.type_refs, written);
            for (let diag in diags) {
                if (diag.kind is LoweringDiagKindHoleNotAllowed) {
                    diagnostics.push(SignatureDiagThrowsHole { type_ref: diag.type_ref });
                }
            }
            reject_holes(lowered)
        } else {
            diagnostics.push(SignatureDiagMissingThrows {});
            root.types.TyError {}
        }
    } else {
        match (declared_throws(db, function_)) {
            let closed: DeclaredThrowsClosed => closed.value,
            DeclaredThrowsPartial | DeclaredThrowsOmitted => {
                match (throws_source) {
                    ThrowsSource.Lowered => callable_throws(db, function_).value,
                    ThrowsSource.Seed => root.types.TyNever {},
                }
            },
        }
    };
    FunctionSignatureResult {
        signature: FunctionSignature { generic_params: frame, params: params, ret: ret, throws_: throws_ },
        diagnostics: diagnostics,
    }
}

// port: baml_compiler2_hir_ty/src/lower.rs::class_field_types @ d9be6853b
// A class's field types: `resolve_class_fields` without the attributes.
function class_field_types(db: root.hir.Db, class_: int) -> (string, root.types.Ty)[] throws never {
    resolve_class_fields(db, class_).map((field) -> {
        (field.0, field.1)
    })
}

// port: baml_compiler2_hir_ty/src/lower.rs::type_alias_value @ d9be6853b
// A type alias's right-hand side, lowered (aliases are non-generic).
function type_alias_value(db: root.hir.Db, alias: int) -> root.types.Ty throws never {
    let data = root.hir.type_alias_data(db, alias);
    let value = data.value
        ?? return root.types.TyError {};
    reject_holes(
        lower_ctx_for_file(db, db.type_alias_locs.get(alias).file).lower_type_ref(
            data.type_refs,
            value,
        ),
    )
}

// port: baml_compiler2_hir_ty/src/lower.rs::AssocTypeLowering @ d9be6853b
// One associated type's bound or default, lowered once in the interface frame.
class AssocTypeLowering {
    value: root.types.Ty?,
}

// port: baml_compiler2_hir_ty/src/lower.rs::interface_assoc_default @ d9be6853b
// The default of associated type `member`, lowered once in the interface
// frame with `Self` symbolic; null when undeclared or without a default.
// The `(interface, member)` key is interned in `db.ty_memo.assoc_members`.
function interface_assoc_default(
    db: root.hir.Db,
    interface_: int,
    member: string,
) -> AssocTypeLowering throws never {
    let key = db.ty_memo.assoc_members.intern(interface_, member);
    db.ty_memo.interface_assoc_default.get(db.cycles, key, () -> {
        AssocTypeLowering {
            value: lower_assoc_type_ref(db, interface_, member, TypePosition.Existential, (assoc) -> {
                assoc.default
            }),
        }
    })
}

// port: baml_compiler2_hir_ty/src/lower.rs::interface_assoc_bound @ d9be6853b
// The declared bound of associated type `member` (rustc's
// `explicit_item_bounds`); null when undeclared or unbounded. Keyed like
// `interface_assoc_default`.
function interface_assoc_bound(
    db: root.hir.Db,
    interface_: int,
    member: string,
) -> AssocTypeLowering throws never {
    let key = db.ty_memo.assoc_members.intern(interface_, member);
    db.ty_memo.interface_assoc_bound.get(db.cycles, key, () -> {
        AssocTypeLowering {
            value: lower_assoc_type_ref(db, interface_, member, TypePosition.ConstraintHead, (assoc) -> {
                assoc.bound
            }),
        }
    })
}

// port: baml_compiler2_hir_ty/src/lower.rs::lower_assoc_type_ref @ d9be6853b
function lower_assoc_type_ref(
    db: root.hir.Db,
    interface_: int,
    member: string,
    position: TypePosition,
    select: (root.hir.AssociatedTypeData) -> int? throws never,
) -> root.types.Ty? throws never {
    let data = root.hir.interface_data(db, interface_);
    let assoc = data.associated_types.find((assoc) -> {
        assoc.name == member
    })
        ?? return null;
    let type_ref = select(assoc)
        ?? return null;
    let ctx = lower_ctx_for_file(db, db.interface_locs.get(interface_).file)
        .with_frame(interface_frame(db, interface_))
        .with_bounds(interface_scope_bounds(db, interface_));
    reject_holes(ctx.lower_type_ref(data.type_refs, type_ref, position = position))
}

// port: baml_compiler2_hir_ty/src/lower.rs::throws_clause_parts @ d9be6853b
// Splits a lowered `throws` clause into its named members and whether it
// carries a top-level open slot (`_`).
function throws_clause_parts(ty: root.types.LoweringTy) -> (root.types.Ty, bool) throws never {
    let members: root.types.LoweringTy[] = match (ty) {
        let u: root.types.LoweringTyUnion => u.members,
        _ => [ty],
    };
    let named: root.types.Ty[] = [];
    let open = false;
    for (let member in members) {
        if (member is root.types.TyInfer) {
            open = true;
        } else {
            named.push(reject_holes(member));
        }
    }
    let named_ty: root.types.Ty = match (named.length()) {
        0 => root.types.TyNever {},
        1 => named[0],
        _ => root.types.TyUnion { members: named },
    };
    (named_ty, open)
}
