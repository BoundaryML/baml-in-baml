// port: baml_type/src/template.rs @ d9be6853b
//
// The hand-written behaviour of TyTemplate, the `Ty`-shaped template member
// of the family: every leaf is realized or a positional frame reference
// (`TyTypeArgRef`, De Bruijn index into the enclosing call frame's type
// args). The variants, satellites and the `RealizedTy` conversions are
// generated (family.baml).
//
// A method of `TyTemplate` is a free function `ty_template_<method>`; one of
// Rust's `TyTemplateInterface` satellite (here `TyTemplateInterfaceConstraint`,
// the variant class `TyTemplateInterface` being the existential) is
// `ty_template_interface_<method>`. Rust's head parameter `N` is DeclName,
// the only head here.
//
// Restructured:
// - `walk_template` mutates the template in place in Rust; here it rebuilds:
//   the visitor returns null to descend, or the node that takes this one's
//   place (its children unwalked), and every composite on the path is a
//   fresh node. So `compose_template` and `transform_has_expanding_cycle`
//   need no defensive clone.
// - `transform_has_expanding_cycle`'s nested `fn reaches` is the top-level
//   `reaches`.
// - `substitute` and `substitute_with_fuel` are one function with a named
//   default `fuel`.
// - `Result<_, SubstituteError>` is `throws SubstituteError`.
//
// Not ported:
// - The constructors `list`, `map`, `union`, `class`, `interface` (one-line):
//   write the variant (`TyTemplateList { elem: t }`).
// - `impl Default for TyTemplateOrigins`: `TyTemplateOrigins.root()`.
// - `impl Display for TyTemplate` and `for TyTemplateInterface`: they render
//   through `Ty`'s `Display`, which needs `HeadDisplay`, which DeclName does
//   not implement (lib.baml). Render
//   `render_with(widen_ty_to_lowering_ty(ty_template_to_display_ty(t)), s)`,
//   and a constraint through `ty_template_interface_to_template` first.
// - `impl std::error::Error for SubstituteError` (a marker).

// port: baml_type/src/template.rs::TyTemplateOrigins @ d9be6853b
// Symbolic realizations of the current type relative to each generic class
// on a render traversal's ancestry stack. Renderers use this to tell a finite
// sequence of specializations from a recursive type transform whose
// arguments grow forever.
class TyTemplateOrigins {
    origins: (TyTemplate | null)[],

    // port: baml_type/src/template.rs::TyTemplateOrigins::root @ d9be6853b
    // No enclosing generic classes contribute symbolic origins at the root.
    function root() -> TyTemplateOrigins throws never {
        TyTemplateOrigins { origins: [] }
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::opaque @ d9be6853b
    // An origin-free value at the given ancestry depth.
    function opaque(depth: int) -> TyTemplateOrigins throws never {
        TyTemplateOrigins {
            origins: baml.Array.generate(depth, (_i) -> TyTemplate | null {
                null
            }),
        }
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::through_field @ d9be6853b
    // Compose a class field template through every enclosing class transform,
    // then add the field's template relative to its immediate class.
    function through_field(
        self,
        class_name: DeclName,
        class_arity: int,
        field: TyTemplate,
    ) -> TyTemplateOrigins throws never {
        let origins = self.origins.map((origin) -> TyTemplate | null {
            let type_args = class_origin_args(origin, class_name, class_arity)
                ?? return null;
            compose_template(field, type_args)
        });
        origins.push(field);
        TyTemplateOrigins { origins: origins }
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::class_transform_expands @ d9be6853b
    // Whether the class realization at `ancestry_index` contains a growing
    // dependency cycle among that class's generic parameter slots.
    function class_transform_expands(
        self,
        ancestry_index: int,
        class_name: DeclName,
        class_arity: int,
    ) -> bool throws never {
        let origin = self.origins.at(ancestry_index)
            ?? return false;
        let type_args = class_origin_args(origin, class_name, class_arity)
            ?? return false;
        transform_has_expanding_cycle(type_args, class_arity)
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::list_element @ d9be6853b
    // Project these origins through a list element.
    function list_element(self) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let l: TyTemplateList => l.elem,
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::map_key @ d9be6853b
    // Project these origins through a map key.
    function map_key(self) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let m: TyTemplateMap => m.key,
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::map_value @ d9be6853b
    // Project these origins through a map value.
    function map_value(self) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let m: TyTemplateMap => m.value,
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::union_member @ d9be6853b
    // Project these origins through one union member.
    function union_member(self, index: int) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let u: TyTemplateUnion => u.members.at(index),
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::tuple_element @ d9be6853b
    function tuple_element(self, index: int) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let t: TyTemplateTuple => t.items.at(index),
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::future_value @ d9be6853b
    // Project these origins through a future's value type.
    function future_value(self) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let f: TyTemplateFuture => f.value,
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::future_error @ d9be6853b
    // Project these origins through a future's error type.
    function future_error(self) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let f: TyTemplateFuture => f.error,
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::function_param @ d9be6853b
    // Project these origins through a function parameter.
    function function_param(self, index: int) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let f: TyTemplateFunction => f.params.at(index)?.ty,
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::function_return @ d9be6853b
    // Project these origins through a function return type.
    function function_return(self) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let f: TyTemplateFunction => f.ret,
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::function_throws @ d9be6853b
    // Project these origins through a function throws type.
    function function_throws(self) -> TyTemplateOrigins throws never {
        self.project((origin) -> TyTemplate | null {
            match (origin) {
                let f: TyTemplateFunction => f.throws_,
                _ => null,
            }
        })
    }

    // port: baml_type/src/template.rs::TyTemplateOrigins::project @ d9be6853b
    function project(
        self,
        project: (TyTemplate) -> TyTemplate | null throws never,
    ) -> TyTemplateOrigins throws never {
        TyTemplateOrigins {
            origins: self.origins.map((origin) -> TyTemplate | null {
                match (origin) {
                    null => null,
                    let o: TyTemplate => project(o),
                }
            }),
        }
    }
}

// port: baml_type/src/template.rs::compose_template @ d9be6853b
// `template` with each in-range frame reference replaced by its type
// argument. Rust clones `template` and walks the copy; `walk_template`
// rebuilds, so the input is untouched without one.
function compose_template(
    template: TyTemplate,
    type_args: TyTemplate[],
) -> TyTemplate throws never {
    walk_template(template, false, (node, _nested) -> TyTemplate | null {
        match (node) {
            let r: TyTypeArgRef => type_args.at(r.index) ?? node,
            _ => null,
        }
    })
}

// port: baml_type/src/template.rs::walk_template @ d9be6853b
// Pre-order traversal of `template`. `visitor` sees each node with whether
// it sits below a type constructor (list, map, class, function, ...).
// Restructured (see the file header): Rust's visitor mutates the node and
// returns whether to descend; here it returns null to descend, or the node
// that replaces this one (whose children are then not walked). The walk
// returns the rebuilt template.
//
// A union member is not below a constructor on the union's account: a union
// builds no new value shape, and `T | T` is `T`. So a type argument that only
// ever lands in unions (`Opt<T?>`) reaches finitely many types, while one
// below a list (`Nest<T[]>`) grows without end.
function walk_template(
    template: TyTemplate,
    nested: bool,
    visitor: (TyTemplate, bool) -> TyTemplate | null throws never,
) -> TyTemplate throws never {
    let replaced = visitor(template, nested);
    if (replaced != null) {
        return replaced;
    }
    let child = (t: TyTemplate) -> TyTemplate {
        walk_template(t, true, visitor)
    };
    let binding = (b: TyTemplateAssociatedType) -> TyTemplateAssociatedType {
        TyTemplateAssociatedType { name: b.name, ty: child(b.ty) }
    };
    match (template) {
        let t: TyTemplateList => TyTemplateList { elem: child(t.elem) },
        let t: TyTemplateMap => {
            let key = child(t.key);
            TyTemplateMap { key: key, value: child(t.value) }
        },
        let t: TyTemplateUnion => {
            TyTemplateUnion {
                members: t.members.map((member) -> TyTemplate {
                    walk_template(member, nested, visitor)
                }),
            }
        },
        let t: TyTemplateTuple => TyTemplateTuple { items: t.items.map(child) },
        let t: TyTemplateClass => TyTemplateClass { name: t.name, args: t.args.map(child) },
        let t: TyTemplateInterface => {
            let args = t.args.map(child);
            TyTemplateInterface {
                name: t.name,
                args: args,
                associated_types: t.associated_types.map(binding),
            }
        },
        let t: TyTemplateFunction => {
            let params = t.params.map((param) -> TyTemplateFunctionParamTy {
                TyTemplateFunctionParamTy {
                    name: param.name,
                    ty: child(param.ty),
                    mode: param.mode,
                }
            });
            let ret = child(t.ret);
            TyTemplateFunction { params: params, ret: ret, throws_: child(t.throws_) }
        },
        let t: TyTemplateFuture => {
            let value = child(t.value);
            TyTemplateFuture { value: value, error: child(t.error) }
        },
        let t: TyTemplateAssociatedTypeProjection => {
            let base = child(t.base);
            let generics = t.interface_.generics.map(child);
            TyTemplateAssociatedTypeProjection {
                base: base,
                interface_: TyTemplateInterfaceConstraint {
                    name: t.interface_.name,
                    generics: generics,
                    associated_types: t.interface_.associated_types.map(binding),
                },
                member: t.member,
            }
        },
        _ => template,
    }
}

// port: baml_type/src/template.rs::visit_template @ d9be6853b
// Read-only pre-order traversal: the immutable sibling of `walk_template`,
// arm for arm, so the two cannot disagree about where children live.
// `visitor` sees every node, parents before children.
function visit_template(
    template: TyTemplate,
    visitor: (TyTemplate) -> void throws never,
) -> void throws never {
    visitor(template);
    match (template) {
        let t: TyTemplateList => visit_template(t.elem, visitor),
        let t: TyTemplateMap => {
            visit_template(t.key, visitor);
            visit_template(t.value, visitor);
        },
        let t: TyTemplateUnion => {
            for (let member in t.members) {
                visit_template(member, visitor);
            }
        },
        let t: TyTemplateTuple => {
            for (let item in t.items) {
                visit_template(item, visitor);
            }
        },
        let t: TyTemplateClass => {
            for (let arg in t.args) {
                visit_template(arg, visitor);
            }
        },
        let t: TyTemplateInterface => {
            for (let arg in t.args) {
                visit_template(arg, visitor);
            }
            for (let binding in t.associated_types) {
                visit_template(binding.ty, visitor);
            }
        },
        let t: TyTemplateFunction => {
            for (let param in t.params) {
                visit_template(param.ty, visitor);
            }
            visit_template(t.ret, visitor);
            visit_template(t.throws_, visitor);
        },
        let t: TyTemplateFuture => {
            visit_template(t.value, visitor);
            visit_template(t.error, visitor);
        },
        let t: TyTemplateAssociatedTypeProjection => {
            visit_template(t.base, visitor);
            for (let generic in t.interface_.generics) {
                visit_template(generic, visitor);
            }
            for (let binding in t.interface_.associated_types) {
                visit_template(binding.ty, visitor);
            }
        },
        _ => {},
    }
}

// port: baml_type/src/template.rs::class_origin_args @ d9be6853b
// The type arguments of `origin` when it instantiates `class_name` at its
// full arity.
function class_origin_args(
    origin: TyTemplate | null,
    class_name: DeclName,
    class_arity: int,
) -> TyTemplate[]? throws never {
    match (origin) {
        let c: TyTemplateClass => {
            if (c.name == class_name && c.args.length() == class_arity) {
                c.args
            } else {
                null
            }
        },
        _ => null,
    }
}

// port: baml_type/src/template.rs::transform_has_expanding_cycle @ d9be6853b
// Whether the class transform `type_args` (output slot i is type_args[i],
// over input slots 0..arity) has a dependency cycle through an edge that
// sits below a type constructor: such a cycle grows the type forever.
function transform_has_expanding_cycle(type_args: TyTemplate[], arity: int) -> bool throws never {
    let edges: (int, bool)[][] = baml.Array.generate(arity, (_i) -> (int, bool)[] {
        []
    });
    for (let output = 0; output < type_args.length() && output < arity; output += 1) {
        let dependencies: (int, bool)[] = [];
        walk_template(type_args[output], false, (template, nested) -> TyTemplate | null {
            match (template) {
                let r: TyTypeArgRef => {
                    dependencies.push((r.index, nested));
                    template
                },
                _ => null,
            }
        });
        for (let dependency in dependencies) {
            let (let input, let expanding) = dependency;
            if (input < arity) {
                edges[input].push((output, expanding));
            }
        }
    }
    for (let input = 0; input < arity; input += 1) {
        for (let edge in edges[input]) {
            let (let output, let expanding) = edge;
            let visited: bool[] = baml.Array.generate(arity, (_i) -> bool {
                false
            });
            if (expanding && reaches(edges, output, input, visited)) {
                return true;
            }
        }
    }
    false
}

// port: baml_type/src/template.rs::transform_has_expanding_cycle::reaches @ d9be6853b
// Whether `target` is reachable from `current` along `edges`. Rust nests it
// in `transform_has_expanding_cycle`.
function reaches(
    edges: (int, bool)[][],
    current: int,
    target: int,
    visited: bool[],
) -> bool throws never {
    if (current == target) {
        return true;
    }
    if (visited[current]) {
        return false;
    }
    visited[current] = true;
    for (let edge in edges[current]) {
        if (reaches(edges, edge.0, target, visited)) {
            return true;
        }
    }
    false
}

// port: baml_type/src/template.rs::SubstituteError @ d9be6853b
// Why a `ty_template_substitute` failed to fully realize a template against
// a frame's realized type arguments. Substitution at runtime realizes fully
// or fails loudly; it never erases an unresolved position to `unknown`. Each
// variant is a broken invariant the VM surfaces as an internal error.
type SubstituteError = SubstituteErrorUnreducibleProjection
    | SubstituteErrorProjectionNotRealized
    | SubstituteErrorProjectionFuelExhausted
    | SubstituteErrorTypeArgRefOutOfRange;

// port: baml_type/src/template.rs::SubstituteError::UnreducibleProjection @ d9be6853b
// A projection over a realized base found no impl binding.
class SubstituteErrorUnreducibleProjection {
    member: string,

    // port: baml_type/src/template.rs::impl Display for SubstituteError @ d9be6853b
    implements baml.ToString {
        function to_string(self) -> string throws never {
            `associated-type projection \`.${self.member}\` could not be reduced`
        }
    }
}

// port: baml_type/src/template.rs::SubstituteError::ProjectionNotRealized @ d9be6853b
// A projection reduced to a type that still holds a non-realized position
// (named by `variant`).
class SubstituteErrorProjectionNotRealized {
    member: string,
    variant: string,

    // port: baml_type/src/template.rs::impl Display for SubstituteError @ d9be6853b
    implements baml.ToString {
        function to_string(self) -> string throws never {
            `associated-type projection \`.${self.member}\` reduced to a non-realized \`${self.variant}\``
        }
    }
}

// port: baml_type/src/template.rs::SubstituteError::ProjectionFuelExhausted @ d9be6853b
// A projection-reduction chain exceeded the fuel budget (a cyclic binding).
class SubstituteErrorProjectionFuelExhausted {
    member: string,

    // port: baml_type/src/template.rs::impl Display for SubstituteError @ d9be6853b
    implements baml.ToString {
        function to_string(self) -> string throws never {
            `associated-type projection \`.${self.member}\` did not terminate within the reduction budget`
        }
    }
}

// port: baml_type/src/template.rs::SubstituteError::TypeArgRefOutOfRange @ d9be6853b
// A `TyTypeArgRef` read a slot the frame does not supply: a frame-layout bug.
class SubstituteErrorTypeArgRefOutOfRange {
    index: int,
    frame_len: int,

    // port: baml_type/src/template.rs::impl Display for SubstituteError @ d9be6853b
    implements baml.ToString {
        function to_string(self) -> string throws never {
            `template references frame type-arg slot ${self.index} but the frame has ${self.frame_len} type args`
        }
    }
}

// port: baml_type/src/template.rs::TyTemplate::substitute @ d9be6853b
// Also `substitute_with_fuel` (`fuel` defaults to the full budget). Realize
// `template` against a frame's realized type arguments: every frame
// reference filled, every projection reduced through `ctx.project`, or a
// SubstituteError. Each projection reduced spends one unit of `fuel`, so a
// cyclic binding fails with `SubstituteErrorProjectionFuelExhausted` instead
// of recursing forever.
function ty_template_substitute(
    template: TyTemplate,
    type_args: RealizedTy[],
    ctx: TypeContext,
    fuel: int = PROJECTION_REDUCTION_FUEL,
) -> RealizedTy throws SubstituteError {
    let sub = (t: TyTemplate) -> RealizedTy throws SubstituteError {
        ty_template_substitute(t, type_args, ctx, fuel = fuel)
    };
    let subs = (ts: TyTemplate[]) -> RealizedTy[] throws SubstituteError {
        let out: RealizedTy[] = [];
        for (let t in ts) {
            out.push(sub(t));
        }
        out
    };
    match (template) {
        // A frame reference materializes to its bound type argument; an
        // out-of-range index is a frame-layout bug, reported.
        let r: TyTypeArgRef => {
            type_args.at(r.index)
                ?? throw SubstituteErrorTypeArgRefOutOfRange {
                    index: r.index,
                    frame_len: type_args.length(),
                }
        },
        let t: TyTemplateList => RealizedTyList { elem: sub(t.elem) },
        let t: TyTemplateMap => {
            let key = sub(t.key);
            RealizedTyMap { key: key, value: sub(t.value) }
        },
        let t: TyTemplateUnion => RealizedTyUnion { members: subs(t.members) },
        let t: TyTemplateTuple => RealizedTyTuple { items: subs(t.items) },
        let t: TyTemplateClass => RealizedTyClass { name: t.name, args: subs(t.args) },
        let t: TyTemplateInterface => {
            let args = subs(t.args);
            let bindings: RealizedAssociatedType[] = [];
            for (let binding in t.associated_types) {
                bindings.push(RealizedAssociatedType { name: binding.name, ty: sub(binding.ty) });
            }
            RealizedTyInterface { name: t.name, args: args, associated_types: bindings }
        },
        let t: TyTemplateFunction => {
            let params: RealizedFunctionParamTy[] = [];
            for (let param in t.params) {
                params.push(
                    RealizedFunctionParamTy {
                        name: param.name,
                        ty: sub(param.ty),
                        mode: param.mode,
                    },
                );
            }
            let ret = sub(t.ret);
            RealizedTyFunction { params: params, ret: ret, throws_: sub(t.throws_) }
        },
        let t: TyTemplateFuture => {
            let value = sub(t.value);
            RealizedTyFuture { value: value, error: sub(t.error) }
        },
        // Realize the base, then reduce the projection to the impl's
        // binding; anything but one realized witness is a broken invariant.
        let t: TyTemplateAssociatedTypeProjection => {
            let base = sub(t.base);
            let interface_ = ty_template_interface_substitute(t.interface_, type_args, ctx, fuel);
            // Spend one unit on this reduction before consulting
            // `ctx.project`, which can re-enter substitution.
            if (fuel == 0) {
                throw SubstituteErrorProjectionFuelExhausted { member: t.member };
            }
            match (ctx.project(widen_realized_ty_to_ty(base), interface_, t.member, fuel - 1)) {
                let reduced: ProjectionStepReduced => {
                    narrow_ty_to_realized_ty(reduced.ty) catch (e) {
                        NarrowError => {
                            throw SubstituteErrorProjectionNotRealized {
                                member: t.member,
                                variant: e.variant,
                            }
                        },
                    }
                },
                ProjectionStepOpaque => {
                    throw SubstituteErrorUnreducibleProjection { member: t.member }
                },
            }
        },
        // A realized leaf narrows to a RealizedTy directly; a composite is
        // handled above, so a failure here is a missing arm.
        _ => {
            narrow_ty_template_to_realized_ty(template) catch (e) {
                NarrowError => {
                    baml.sys.panic(`realized-leaf template narrowing failed: ${e.variant}`)
                },
            }
        },
    }
}

// port: baml_type/src/template.rs::TyTemplateInterface::to_template @ d9be6853b
// The interface existential template (`TyTemplateInterface`) this constraint
// denotes. Needed only where a type, not a constraint, is carried (the
// bytecode constant pool a `LoadType` reads).
function ty_template_interface_to_template(
    constraint: TyTemplateInterfaceConstraint,
) -> TyTemplate throws never {
    TyTemplateInterface {
        name: constraint.name,
        args: constraint.generics,
        associated_types: constraint.associated_types,
    }
}

// port: baml_type/src/template.rs::TyTemplateInterface::for_each_type_arg_ref @ d9be6853b
// `ty_template_for_each_type_arg_ref` over every template position of the
// constraint: the generic arguments, then the associated-type bindings.
function ty_template_interface_for_each_type_arg_ref(
    constraint: TyTemplateInterfaceConstraint,
    f: (int) -> void throws never,
) -> void throws never {
    for (let generic in constraint.generics) {
        ty_template_for_each_type_arg_ref(generic, f);
    }
    for (let binding in constraint.associated_types) {
        ty_template_for_each_type_arg_ref(binding.ty, f);
    }
}

// port: baml_type/src/template.rs::TyTemplateInterface::substitute_symbolic @ d9be6853b
// Compile-time counterpart of `ty_template_interface_substitute`: frame refs
// resolved, unresolved positions left symbolic. Rust builds the result with
// `RuntimeInterface::new`, which sorts the bindings by name; the sort is
// inlined.
function ty_template_interface_substitute_symbolic(
    constraint: TyTemplateInterfaceConstraint,
    type_args: RuntimeTy[],
) -> RuntimeInterfaceConstraint throws never {
    let generics = constraint.generics.map((generic) -> RuntimeTy {
        ty_template_substitute_symbolic(generic, type_args)
    });
    RuntimeInterfaceConstraint {
        name: constraint.name,
        generics: generics,
        associated_types: constraint.associated_types
            .map((binding) -> RuntimeAssociatedType {
                RuntimeAssociatedType {
                    name: binding.name,
                    ty: ty_template_substitute_symbolic(binding.ty, type_args),
                }
            })
            .sort_by_key((binding) -> {
                binding.name
            }),
    }
}

// port: baml_type/src/template.rs::TyTemplateInterface::substitute @ d9be6853b
// Substitute frame type args through the constraint's generic and binding
// positions, producing the realized constraint (widened to Ty) that reduces
// the enclosing projection. Rust builds it with `Interface::new`, which sorts
// the bindings by name; the sort is inlined.
function ty_template_interface_substitute(
    constraint: TyTemplateInterfaceConstraint,
    type_args: RealizedTy[],
    ctx: TypeContext,
    fuel: int,
) -> InterfaceConstraint throws SubstituteError {
    let generics: Ty[] = [];
    for (let generic in constraint.generics) {
        generics.push(
            widen_realized_ty_to_ty(ty_template_substitute(generic, type_args, ctx, fuel = fuel)),
        );
    }
    let bindings: AssociatedType[] = [];
    for (let binding in constraint.associated_types) {
        bindings.push(
            AssociatedType {
                name: binding.name,
                ty: widen_realized_ty_to_ty(ty_template_substitute(binding.ty, type_args, ctx, fuel = fuel)),
            },
        );
    }
    InterfaceConstraint {
        name: constraint.name,
        generics: generics,
        associated_types: bindings.sort_by_key((binding) -> {
            binding.name
        }),
    }
}

// port: baml_type/src/template.rs::TyTemplate::substitute_symbolic @ d9be6853b
// Compile-time counterpart of `ty_template_substitute`: resolve each frame
// reference against `type_args` but leave every unresolved position
// symbolic. A projection stays a projection; an out-of-range reference falls
// back to `unknown`. Used where the args may themselves be symbolic (a class
// field's type given the receiver's class args).
function ty_template_substitute_symbolic(
    template: TyTemplate,
    type_args: RuntimeTy[],
) -> RuntimeTy throws never {
    let sub = (t: TyTemplate) -> RuntimeTy {
        ty_template_substitute_symbolic(t, type_args)
    };
    match (template) {
        let r: TyTypeArgRef => type_args.at(r.index) ?? TyUnknown {},
        let t: TyTemplateList => RuntimeTyList { elem: sub(t.elem) },
        let t: TyTemplateMap => {
            let key = sub(t.key);
            RuntimeTyMap { key: key, value: sub(t.value) }
        },
        let t: TyTemplateUnion => RuntimeTyUnion { members: t.members.map(sub) },
        let t: TyTemplateTuple => RuntimeTyTuple { items: t.items.map(sub) },
        let t: TyTemplateClass => RuntimeTyClass { name: t.name, args: t.args.map(sub) },
        let t: TyTemplateInterface => {
            let args = t.args.map(sub);
            RuntimeTyInterface {
                name: t.name,
                args: args,
                associated_types: t.associated_types.map((binding) -> RuntimeAssociatedType {
                    RuntimeAssociatedType { name: binding.name, ty: sub(binding.ty) }
                }),
            }
        },
        let t: TyTemplateFunction => {
            let params = t.params.map((param) -> RuntimeFunctionParamTy {
                RuntimeFunctionParamTy { name: param.name, ty: sub(param.ty), mode: param.mode }
            });
            let ret = sub(t.ret);
            RuntimeTyFunction { params: params, ret: ret, throws_: sub(t.throws_) }
        },
        let t: TyTemplateFuture => {
            let value = sub(t.value);
            RuntimeTyFuture { value: value, error: sub(t.error) }
        },
        let t: TyTemplateAssociatedTypeProjection => {
            let base = sub(t.base);
            RuntimeTyAssociatedTypeProjection {
                base: base,
                interface_: ty_template_interface_substitute_symbolic(t.interface_, type_args),
                member: t.member,
            }
        },
        // A realized leaf narrows to RealizedTy, then widens to RuntimeTy.
        _ => {
            let realized = narrow_ty_template_to_realized_ty(template) catch (e) {
                NarrowError => {
                    baml.sys.panic(`realized-leaf template narrowing failed: ${e.variant}`)
                },
            };
            widen_realized_ty_to_runtime_ty(realized)
        },
    }
}

// port: baml_type/src/template.rs::TyTemplate::is_fully_concrete @ d9be6853b
// Whether the template holds no template-only leaf (`TyTypeArgRef` or an
// unresolved projection) at any depth: it narrows to a RealizedTy.
function ty_template_is_fully_concrete(template: TyTemplate) -> bool throws never {
    narrow_ty_template_to_realized_ty(template) catch (e) {
        NarrowError => {
            return false;
        },
    };
    true
}

// port: baml_type/src/template.rs::TyTemplate::has_projection @ d9be6853b
// Whether the template holds an associated-type projection at any depth: the
// one node whose substitution consults the type context.
function ty_template_has_projection(template: TyTemplate) -> bool throws never {
    let found = false;
    visit_template(template, (node) -> {
        found = found || node is TyTemplateAssociatedTypeProjection;
    });
    found
}

// port: baml_type/src/template.rs::TyTemplate::for_each_type_arg_ref @ d9be6853b
// Calls `f` with the frame slot of every `TyTypeArgRef` leaf, in traversal
// order, once per reference: exactly the slots evaluating the template reads.
function ty_template_for_each_type_arg_ref(
    template: TyTemplate,
    f: (int) -> void throws never,
) -> void throws never {
    visit_template(template, (node) -> {
        match (node) {
            let r: TyTypeArgRef => f(r.index),
            _ => {},
        }
    });
}

// port: baml_type/src/template.rs::TyTemplate::to_display_ty @ d9be6853b
// A lossy Ty view for rendering only: frame refs become `TyTypeVar` named
// `#n`; every other node maps structurally (a projection's constraint as a
// struct literal, unsorted, as in Rust).
function ty_template_to_display_ty(template: TyTemplate) -> Ty throws never {
    let display = (t: TyTemplate) -> Ty {
        ty_template_to_display_ty(t)
    };
    let binding = (b: TyTemplateAssociatedType) -> AssociatedType {
        AssociatedType { name: b.name, ty: display(b.ty) }
    };
    match (template) {
        let r: TyTypeArgRef => TyTypeVar { param: ParamTy { index: r.index, name: `#${r.index}` } },
        let t: TyTemplateList => TyList { elem: display(t.elem) },
        let t: TyTemplateMap => {
            let key = display(t.key);
            TyMap { key: key, value: display(t.value) }
        },
        let t: TyTemplateUnion => TyUnion { members: t.members.map(display) },
        let t: TyTemplateTuple => TyTuple { items: t.items.map(display) },
        let t: TyTemplateClass => TyClass { name: t.name, args: t.args.map(display) },
        let t: TyTemplateInterface => {
            let args = t.args.map(display);
            TyInterface {
                name: t.name,
                args: args,
                associated_types: t.associated_types.map(binding),
            }
        },
        let t: TyTemplateFunction => {
            let params = t.params.map((param) -> FunctionParamTy {
                FunctionParamTy { name: param.name, ty: display(param.ty), mode: param.mode }
            });
            let ret = display(t.ret);
            TyFunction { params: params, ret: ret, throws_: display(t.throws_) }
        },
        let t: TyTemplateFuture => {
            let value = display(t.value);
            TyFuture { value: value, error: display(t.error) }
        },
        let t: TyTemplateAssociatedTypeProjection => {
            let base = display(t.base);
            let generics = t.interface_.generics.map(display);
            TyAssociatedTypeProjection {
                base: base,
                interface_: InterfaceConstraint {
                    name: t.interface_.name,
                    generics: generics,
                    associated_types: t.interface_.associated_types.map(binding),
                },
                member: t.member,
            }
        },
        // A realized leaf widens into Ty by the generated conversions.
        _ => {
            let realized = narrow_ty_template_to_realized_ty(template) catch (e) {
                NarrowError => {
                    baml.sys.panic(
                        `realized-leaf template widening for display failed: ${e.variant}`,
                    )
                },
            };
            widen_realized_ty_to_ty(realized)
        },
    }
}
