// port: baml_type/src/runtime_ty.rs @ d9be6853b
//
// The hand-written behaviour of RuntimeTy, the runtime-facing member of the
// family. Only what the type checker reaches is ported: llm_output.rs (through
// json_inhabit) uses `RuntimeTy::try_from(&Ty)`, `Ty::from(&RuntimeTy)`,
// `is_null` and `flatten_union`. Like lib.baml's LoweringTy twins, a RuntimeTy
// method takes the family's `_runtime_ty` suffix, so it does not clash with
// the `Ty` or json_inhabit function of the same name.
//
// Not ported:
// - `try_from` / `Ty::from`: the generated `narrow_ty_to_runtime_ty` (and
//   `narrow_lowering_ty_to_runtime_ty`) and `widen_runtime_ty_to_ty`.
// - The one-line constructors (`int`, `bigint`, `float`, `string`, `bool`,
//   `null`, `uint8array`, `list`, `map`, `union`, `unknown`, `resource`,
//   `prompt_ast`, `type_type`): write the variant. `is_null` is `t is TyNull`.
// - `class`, `class_with_args`, `user_class`: `TypeName`-headed only.
// - `impl Display`: needs `HeadDisplay`, which DeclName does not implement;
//   render through `render_with(widen_runtime_ty_to_lowering_ty(t), s)`.
// - `optional`, `is_unit`, `is_uninhabited`, `is_nullable_union`,
//   `strip_null`: nothing on the type checker's path calls them.
// - `lower_vec`: a `map` inside `lower_to_runtime`.
// - `impl Default for ResolvedAliases`: write
//   `ResolvedAliases { aliases: {}, recursive: {} }`.
// - The tests: they cover the items above (`is_unit`, the constructors at
//   another head, and the generated conversions, which family_test.baml
//   covers).

// port: baml_type/src/runtime_ty.rs::RuntimeTy::flatten_union @ d9be6853b
// This type with its union, if it is one, spelled flat and without repeated
// members, first occurrences in place (flat_union): `(int | null) | null` is
// `int | null`.
function flatten_union_runtime_ty(ty: RuntimeTy) -> RuntimeTy throws never {
    match (ty) {
        let u: RuntimeTyUnion => {
            flat_union(
                u.members,
                (member: RuntimeTy) -> RuntimeTy[]? {
                    match (member) {
                        let nested: RuntimeTyUnion => nested.members,
                        _ => null,
                    }
                },
                TyNever {},
                (members: RuntimeTy[]) -> RuntimeTy {
                    RuntimeTyUnion { members: members }
                },
            )
        },
        _ => ty,
    }
}

// port: baml_type/src/runtime_ty.rs::ResolvedAliases @ d9be6853b
// The resolved type-alias environment needed to erase a Ty into a RuntimeTy:
// the alias targets to expand and the set of recursive aliases to keep
// opaque.
class ResolvedAliases {
    aliases: map<DeclName, Ty>,
    recursive: map<DeclName, bool>,

    // port: baml_type/src/runtime_ty.rs::ResolvedAliases::from_aliases @ d9be6853b
    // Build the environment from the collected alias targets, computing the
    // recursive set here: the one constructor, so a caller cannot pair
    // aliases with a stale recursive set.
    function from_aliases(aliases: map<DeclName, Ty>) -> ResolvedAliases throws never {
        let recursive: map<DeclName, bool> = {};
        for (let name in aliases.keys()) {
            if (has_cycle(name, aliases)) {
                recursive.set(name, true);
            }
        }
        ResolvedAliases { aliases: aliases, recursive: recursive }
    }

    // port: baml_type/src/runtime_ty.rs::ResolvedAliases::convert @ d9be6853b
    // A compile-time type as the runtime carries it (lower_to_runtime).
    // Panics on an error-recovery type: a type-checked program has none.
    function convert(self, ty: Ty) -> RuntimeTy throws never {
        lower_to_runtime(ty, self) catch (e) {
            let err: NotRuntimeTy => baml.sys.panic(
                `ty is not a runtime type: ${err.variant}: an error-recovery type reached runtime lowering`,
            ),
        }
    }
}

// port: baml_type/src/runtime_ty.rs::NotRuntimeTy @ d9be6853b
// A type with no runtime form: the error-recovery sentinel, or an alias the
// environment cannot see.
class NotRuntimeTy {
    variant: string,
}

// port: baml_type/src/runtime_ty.rs::lower_to_runtime @ d9be6853b
// Lower `ty` to its runtime form: non-recursive aliases expanded inline,
// recursive ones kept opaque, literal freshness reset to Regular (a
// compiler-only flag), every other variant mapped to its runtime twin.
function lower_to_runtime(ty: Ty, resolved: ResolvedAliases) -> RuntimeTy throws NotRuntimeTy {
    let lower = (t: Ty) -> RuntimeTy throws NotRuntimeTy {
        lower_to_runtime(t, resolved)
    };
    match (ty) {
        let x: TyInt
            | TyBigint
            | TyFloat
            | TyString
            | TyBool
            | TyNull
            | TyUint8Array
            | TyMedia
            | TyEnum
            | TyEnumVariant
            | TyRustType
            | TyType
            | TyResource
            | TyPromptAst
            | TyTypeVar
            | TyUnknown
            | TyNever =>
        {
            x
        },
        let x: TyClass => RuntimeTyClass { name: x.name, args: x.args.map(lower) },
        let x: TyInterface => {
            RuntimeTyInterface {
                name: x.name,
                args: x.args.map(lower),
                associated_types: x.associated_types.map((b) -> RuntimeAssociatedType throws NotRuntimeTy {
                    RuntimeAssociatedType { name: b.name, ty: lower(b.ty) }
                }),
            }
        },
        let x: TyTypeAlias => {
            if (resolved.recursive.has(x.name)) {
                // Recursive aliases stay opaque: the runtime resolves them.
                return x;
            }
            let target = resolved.aliases.get(x.name);
            if (target == null) {
                // A name nothing will declare: carrying it opaque would bake a
                // dangling reference into the program image.
                throw NotRuntimeTy { variant: "TypeAlias (not in the resolved-alias environment)" };
            }
            lower(target)
        },
        let x: TyList => RuntimeTyList { elem: lower(x.elem) },
        let x: TyMap => RuntimeTyMap { key: lower(x.key), value: lower(x.value) },
        let x: TyUnion => RuntimeTyUnion { members: x.members.map(lower) },
        let x: TyTuple => RuntimeTyTuple { items: x.items.map(lower) },
        let x: TyLiteral => TyLiteral { value: x.value, freshness: Freshness.Regular },
        let x: TyFunction => {
            RuntimeTyFunction {
                params: x.params.map((p) -> RuntimeFunctionParamTy throws NotRuntimeTy {
                    RuntimeFunctionParamTy { name: p.name, ty: lower(p.ty), mode: p.mode }
                }),
                ret: lower(x.ret),
                throws_: lower(x.throws_),
            }
        },
        let x: TyAssociatedTypeProjection => {
            RuntimeTyAssociatedTypeProjection {
                base: lower(x.base),
                interface_: lower_interface_to_runtime(x.interface_, resolved),
                member: x.member,
            }
        },
        let x: TyFuture => RuntimeTyFuture { value: lower(x.value), error: lower(x.error) },
        TyError => throw NotRuntimeTy { variant: "Error" },
    }
}

// port: baml_type/src/runtime_ty.rs::lower_interface_to_runtime @ d9be6853b
// An interface constraint (the `as I` of a projection) in runtime form,
// every generic argument and binding lowered.
function lower_interface_to_runtime(
    interface_: InterfaceConstraint,
    resolved: ResolvedAliases,
) -> RuntimeInterfaceConstraint throws NotRuntimeTy {
    RuntimeInterfaceConstraint {
        name: interface_.name,
        generics: interface_.generics.map((t) -> RuntimeTy throws NotRuntimeTy {
            lower_to_runtime(t, resolved)
        }),
        associated_types: interface_.associated_types.map((b) -> RuntimeAssociatedType throws NotRuntimeTy {
            RuntimeAssociatedType { name: b.name, ty: lower_to_runtime(b.ty, resolved) }
        }),
    }
}

// port: baml_type/src/runtime_ty.rs::has_cycle @ d9be6853b
// Whether the alias `name` reaches a cycle of aliases (DFS with an on-path
// `stack`). Restructured: Rust's `visited` and `stack` out-params always
// start empty (from_aliases), so they are made here, with `name` already
// entered; ty_has_cycle enters every alias after it.
function has_cycle(name: DeclName, aliases: map<DeclName, Ty>) -> bool throws never {
    let target = aliases.get(name)
        ?? return false;
    let visited: map<DeclName, bool> = {};
    let stack: map<DeclName, bool> = {};
    visited.set(name, true);
    stack.set(name, true);
    ty_has_cycle(target, aliases, visited, stack)
}

// port: baml_type/src/runtime_ty.rs::ty_has_cycle @ d9be6853b
// Leaves the DFS path at `name`: an AliasExit queued under the alias's
// target. Not a Rust item; it stands for the `stack.remove` after Rust's
// recursive call returns.
class AliasExit {
    name: DeclName,
}

// port: baml_type/src/runtime_ty.rs::ty_has_cycle @ d9be6853b
// Whether `ty` reaches an alias already on the DFS path `stack`. An alias
// in `aliases` is entered (Rust's `has_cycle` body, inlined); every other
// type is walked through its children.
// Restructured: alias chains are as deep as the input, so the walk is a work
// stack; an AliasExit takes the alias off `stack` once its target is done,
// where Rust's recursion returns.
function ty_has_cycle(
    ty: Ty,
    aliases: map<DeclName, Ty>,
    visited: map<DeclName, bool>,
    stack: map<DeclName, bool>,
) -> bool throws never {
    let work: (Ty | AliasExit)[] = [ty];
    while let item: Ty | AliasExit = work.pop() {
        match (item) {
            let exit: AliasExit => {
                stack.delete(exit.name);
            },
            let alias: TyTypeAlias => {
                let target = aliases.get(alias.name);
                if (target != null) {
                    if (stack.has(alias.name)) {
                        return true;
                    }
                    if (!visited.has(alias.name)) {
                        visited.set(alias.name, true);
                        stack.set(alias.name, true);
                        work.push(AliasExit { name: alias.name });
                        work.push(target);
                    }
                }
            },
            let t: Ty => {
                let children = children_ty(t);
                for (let i = children.length() - 1; i >= 0; i -= 1) {
                    work.push(children[i]);
                }
            },
        }
    }
    false
}
