// port: baml_type/src/template.rs::tests @ d9be6853b
//
// Rust's heads are `TypeName::local(..)`; here a local DeclName
// (`local_decl`, lib_test.baml).

// port: baml_type/src/template.rs::tests::NoCtx @ d9be6853b
// A context-free TypeContext: these substitution tests exercise frame-ref
// resolution and realization, not projection reduction, so every query
// fails safe. `well_known` answers null: Rust's name-based context spells the
// well-known head itself, which substitution never asks for.
class NoCtx {
    implements TypeContext {
        function well_known(self, head: WellKnownHead) -> DeclName? {
            null
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

// port: baml_type/src/template.rs::tests::r @ d9be6853b
// A RealizedTy frame argument from a RuntimeTy.
function r(ty: RuntimeTy) -> RealizedTy throws never {
    narrow_runtime_ty_to_realized_ty(ty) catch (e) {
        NarrowError => baml.sys.panic("test arg is realized"),
    }
}

// port: baml_type/src/template.rs::tests::sub @ d9be6853b
// Materialize against a frame, widening the realized result to RuntimeTy.
function sub(tmpl: TyTemplate, args: RealizedTy[]) -> RuntimeTy throws never {
    let realized = ty_template_substitute(tmpl, args, NoCtx {}) catch (e) {
        _ => baml.sys.panic(`substitution realizes: ${e.to_string()}`),
    };
    widen_realized_ty_to_runtime_ty(realized)
}

test "generic render origins reject only growing dependency cycles" {
    let step = local_decl("Step");
    let step_field = TyTemplateClass {
        name: step,
        args: [TyTemplateList { elem: TyTypeArgRef { index: 1 } }, TyInt {}],
    };
    let step_origins = TyTemplateOrigins.root().through_field(step, 2, step_field);
    assert.is_true(!step_origins.class_transform_expands(0, step, 2));

    let chain = local_decl("Chain");
    let chain_field = TyTemplateClass {
        name: chain,
        args: [TyTemplateClass { name: chain, args: [TyTypeArgRef { index: 0 }] }],
    };
    let chain_origins = TyTemplateOrigins.root().through_field(chain, 1, chain_field);
    assert.is_true(chain_origins.class_transform_expands(0, chain, 1));

    let interface_field = TyTemplateClass {
        name: chain,
        args: [
            TyTemplateInterface {
                name: local_decl("Wrapped"),
                args: [TyTypeArgRef { index: 0 }],
                associated_types: [],
            },
        ],
    };
    let interface_origins = TyTemplateOrigins.root().through_field(chain, 1, interface_field);
    assert.is_true(interface_origins.class_transform_expands(0, chain, 1));
}

// A union builds no new value shape: a type argument that lands only in
// unions (`Opt<T?>`, `U<(T | int) | string>`) reaches finitely many
// instantiations once each union is spelled flat, so it does not expand; one
// below a constructor inside the union (`X<T | T[]>`) still grows.
test "generic render origins let union only recursion close" {
    let class_ = local_decl("Opt");
    let expands = (arg: TyTemplate) -> bool {
        let field = TyTemplateClass { name: class_, args: [arg] };
        TyTemplateOrigins.root().through_field(class_, 1, field).class_transform_expands(
            0,
            class_,
            1,
        )
    };
    let t0 = TyTypeArgRef { index: 0 };

    assert.is_true(!expands(TyTemplateUnion { members: [t0, TyNull {}] }));
    assert.is_true(
        !expands(TyTemplateUnion { members: [TyTemplateUnion { members: [t0, TyInt {}] }, TyString {}] }),
    );
    assert.is_true(expands(TyTemplateUnion { members: [t0, TyTemplateList { elem: t0 }] }));
    assert.is_true(expands(TyTemplateList { elem: TyTemplateUnion { members: [t0, TyNull {}] } }));
}

// `visit_template` and `walk_template` are separate traversals, one
// read-only and total, one rebuilding and prunable: both must reach the same
// nodes of a template carrying every child-bearing variant.
test "both template traversals reach the same children" {
    let arg = (index: int) -> TyTemplate {
        TyTypeArgRef { index: index }
    };
    let iface = TyTemplateInterfaceConstraint {
        name: local_decl("Shown"),
        generics: [arg(0)],
        associated_types: [TyTemplateAssociatedType { name: "Item", ty: arg(1) }],
    };
    let every_shape = TyTemplateClass {
        name: local_decl("Holder"),
        args: [
            TyTemplateList { elem: arg(2) },
            TyTemplateMap { key: arg(3), value: arg(4) },
            TyTemplateUnion { members: [arg(5), arg(6)] },
            TyTemplateInterface {
                name: local_decl("Shown"),
                args: [arg(7)],
                associated_types: [TyTemplateAssociatedType { name: "Item", ty: arg(8) }],
            },
            TyTemplateFunction {
                params: [
                    TyTemplateFunctionParamTy {
                        name: "a",
                        ty: arg(9),
                        mode: FunctionParamMode.Required,
                    },
                ],
                ret: arg(10),
                throws_: arg(11),
            },
            TyTemplateFuture { value: arg(12), error: arg(13) },
            TyTemplateAssociatedTypeProjection { base: arg(14), interface_: iface, member: "Item" },
        ],
    };

    let visited = 0;
    visit_template(every_shape, (_node) -> {
        visited = visited + 1;
    });
    let walked = 0;
    walk_template(every_shape, false, (_node, _nested) -> TyTemplate | null {
        walked = walked + 1;
        null
    });
    assert.equal(visited, walked);

    // And the slot walk built on the read-only one sees every leaf.
    let slots: int[] = [];
    ty_template_for_each_type_arg_ref(every_shape, (slot) -> {
        slots.push(slot);
    });
    assert.equal(
        slots.sort_by_key((slot) -> {
            slot
        }),
        baml.Array.generate(15, (i) -> int {
            i
        }),
    );
}

test "concrete template substitutes to itself" {
    let tmpl = TyInt {};
    assert.equal(sub(tmpl, []), TyInt {});
    assert.is_true(ty_template_is_fully_concrete(tmpl));
}

test "type arg ref substitutes correctly" {
    let tmpl = TyTypeArgRef { index: 0 };
    assert.equal(sub(tmpl, [r(TyString {})]), TyString {});
    assert.is_true(!ty_template_is_fully_concrete(tmpl));
}

test "array of type arg ref" {
    // list<#0> with type_args=[int] -> int[]
    let tmpl = TyTemplateList { elem: TyTypeArgRef { index: 0 } };
    assert.equal(sub(tmpl, [r(TyInt {})]), RuntimeTyList { elem: TyInt {} });
    assert.is_true(!ty_template_is_fully_concrete(tmpl));
}

test "optional of type arg ref" {
    // (#0 | null) with type_args=[string] -> string?
    let tmpl = TyTemplateUnion { members: [TyTypeArgRef { index: 0 }, TyNull {}] };
    assert.equal(sub(tmpl, [r(TyString {})]), RuntimeTyUnion { members: [TyString {}, TyNull {}] });
    assert.is_true(!ty_template_is_fully_concrete(tmpl));
}

// A template's indices only reference the surrounding frame, so an
// out-of-range ref is a frame-layout bug, reported rather than realized as
// `unknown`.
test "out of range type arg ref is an error" {
    let outcome = ty_template_substitute(TyTypeArgRef { index: 0 }, [], NoCtx {}) catch (e) {
        _ => e,
    };
    assert.equal(outcome, SubstituteErrorTypeArgRefOutOfRange { index: 0, frame_len: 0 });
}

// port: baml_type/src/template.rs::tests::cyclic_projection @ d9be6853b
// `(#0 as Cyclic).member`: a projection whose base is a realized frame ref.
function cyclic_projection(member: string) -> TyTemplate throws never {
    TyTemplateAssociatedTypeProjection {
        base: TyTypeArgRef { index: 0 },
        interface_: TyTemplateInterfaceConstraint {
            name: local_decl("Cyclic"),
            generics: [],
            associated_types: [],
        },
        member: member,
    }
}

// port: baml_type/src/template.rs::tests::CyclicCtx @ d9be6853b
// A context whose every projection reduces by realizing the same projection
// again: a cyclic associated-type binding. The threaded fuel bounds it.
class CyclicCtx {
    implements TypeContext {
        function well_known(self, head: WellKnownHead) -> DeclName? {
            null
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

        // The binding for `member` is the same projection, so realizing it
        // re-enters `project`; an exhausted budget surfaces as a
        // substitution error, answered `Opaque`.
        function project(
            self,
            base: Ty,
            interface_: InterfaceConstraint,
            member: string,
            fuel: int,
        ) -> ProjectionStep {
            let reduced = ty_template_substitute(cyclic_projection(member), [TyUnknown {}], self, fuel = fuel) catch (e) {
                _ => {
                    return ProjectionStepOpaque {};
                },
            };
            ProjectionStepReduced { ty: widen_realized_ty_to_ty(reduced) }
        }
    }
}

test "projection fuel guard fires at zero" {
    // With no remaining budget a projection cannot even attempt its reduction.
    let outcome = ty_template_substitute(cyclic_projection("Item"), [TyUnknown {}], CyclicCtx {}, fuel = 0) catch (e) {
        _ => e,
    };
    assert.equal(outcome, SubstituteErrorProjectionFuelExhausted { member: "Item" });
}

test "cyclic projection terminates instead of overflowing" {
    let outcome = ty_template_substitute(cyclic_projection("Item"), [TyUnknown {}], CyclicCtx {}, fuel = 16) catch (e) {
        _ => e,
    };
    assert.is_true(
        outcome is SubstituteErrorUnreducibleProjection
            || outcome is SubstituteErrorProjectionNotRealized
            || outcome is SubstituteErrorProjectionFuelExhausted
            || outcome is SubstituteErrorTypeArgRefOutOfRange,
    );
}

test "concrete array is fully concrete" {
    assert.is_true(ty_template_is_fully_concrete(TyTemplateList { elem: TyInt {} }));
}

test "union of concrete is fully concrete" {
    let tmpl = TyTemplateUnion { members: [TyInt {}, TyString {}] };
    assert.is_true(ty_template_is_fully_concrete(tmpl));
    assert.equal(sub(tmpl, []), RuntimeTyUnion { members: [TyInt {}, TyString {}] });
}

test "union containing type arg ref not concrete" {
    let tmpl = TyTemplateUnion { members: [TyInt {}, TyTypeArgRef { index: 0 }] };
    assert.is_true(!ty_template_is_fully_concrete(tmpl));
}

test "class with type arg ref substitution" {
    let container = local_decl("Container");
    let tmpl = TyTemplateClass { name: container, args: [TyTypeArgRef { index: 0 }] };
    let user = RuntimeTyClass { name: local_decl("User"), args: [] };
    assert.equal(sub(tmpl, [r(user)]), RuntimeTyClass { name: container, args: [user] });
    assert.is_true(!ty_template_is_fully_concrete(tmpl));
}

test "class no args is fully concrete" {
    let tmpl = TyTemplateClass { name: local_decl("User"), args: [] };
    assert.is_true(ty_template_is_fully_concrete(tmpl));
    assert.equal(sub(tmpl, []), RuntimeTyClass { name: local_decl("User"), args: [] });
}
