// port: baml_compiler2_hir_ty/src/callable.rs @ d9be6853b
//
// Cross-function throws propagation (`callable_throws`, the on-demand
// fixpoint query) and the one callable surface every consumer asks.
//
// Restructured:
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so a `FunctionRef` is its Source lane, a function loc `int`, and the
//   External arms (`extern_*` rows, `ExternRowAddr`) are dropped. Without
//   them these are one-line reads, not ported: `callable_signature`
//   (`function_signature_ty`), `callable_throws_of`
//   (`function_signature_with_diagnostics(db, f).signature.throws_`),
//   `callable_builtin_kind` (`function_signature_ty(db, f).builtin_kind`),
//   `callable_display_name` (`root.hir.function_data(db, f).name`), and
//   `concat_frame` and `From<ExternFunctionLoc>`.
// - `CallableFrame`'s borrowed `Cow`s are owned arrays;
//   `package_interface::plain_bounds` is inlined.
// - `seeded_callable_throws` (bytecode-cache seeds) is absent, as every
//   `seeded_*` input is.
//
// Not ported: `ExternalCallTarget` and `ExternalLinkability` (the export and
// MIR's link surface).

// port: baml_compiler2_hir_ty/src/callable.rs::CallableThrows @ d9be6853b
// A function's effect, wrapped for the memoized query result.
class CallableThrows {
    value: root.types.Ty,
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_throws_cycle_initial @ d9be6853b
// The fixpoint seed: a recursive call contributes nothing until an iteration
// proves otherwise.
function callable_throws_cycle_initial(
    db: root.hir.Db,
    function_: int,
) -> CallableThrows throws never {
    CallableThrows { value: root.types.TyNever {} }
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_throws @ d9be6853b
// What `function_` throws: the declared clause when written, else the union
// its body's effect channel infers.
function callable_throws(db: root.hir.Db, function_: int) -> CallableThrows throws never {
    db.ty_memo.callable_throws.get_fixpoint(
        db.cycles,
        function_,
        () -> {
            callable_throws_cycle_initial(db, function_)
        },
        () -> {
            // An interface method's contract is what its signature declares,
            // never what a default body does.
            if (signature_is_interface_contract(db, function_)) {
                return CallableThrows {
                    value: function_signature_with_diagnostics(db, function_).signature.throws_,
                };
            }
            // A closed clause is the function's effect as written.
            match (declared_throws(db, function_)) {
                let closed: DeclaredThrowsClosed => {
                    return CallableThrows { value: closed.value };
                },
                DeclaredThrowsPartial | DeclaredThrowsOmitted => {},
            }
            // A partial or omitted clause keeps inferring: the body run's
            // finalize unions any named members with the inferred set.
            CallableThrows {
                value: infer_body(db, root.hir.BodyOwnerIdFunction { value: function_ }).throws_,
            }
        },
    )
}

// port: baml_compiler2_hir_ty/src/callable.rs::FunctionSignatureTy @ d9be6853b
// A function's declaration-site resolved signature: plain types, own generic
// parameters only.
class FunctionSignatureTy {
    // Every parameter, `self` included; a defaulted one is `Optional`.
    params: root.types.FunctionParamTy[],
    // The declared return type; the Error sentinel when unwritten.
    return_type: root.types.Ty,
    // The function's own generic parameters: its frame minus the enclosing
    // type's prefix.
    generic_params: root.types.ParamTy[],
    // Set for builtin-bodied functions.
    builtin_kind: root.ast.BuiltinKind?,
}

// port: baml_compiler2_hir_ty/src/callable.rs::enclosing_param_count @ d9be6853b
// The enclosing type's generic-frame prefix length for a method's frame; 0
// for a free function.
function enclosing_param_count(db: root.hir.Db, function_: int) -> int throws never {
    match (root.hir.method_owner(db, function_)) {
        let owner: root.hir.MethodOwnerClass => class_generic_frame(db, owner.value).length(),
        let owner: root.hir.MethodOwnerInterface => interface_frame(db, owner.value).length(),
        let owner: root.hir.MethodOwnerImpl => impl_frame(db, owner.value).length(),
        null => 0,
    }
}

// port: baml_compiler2_hir_ty/src/callable.rs::function_signature_ty_cycle_initial @ d9be6853b
// A projection of `function_signature`, inside the same fixpoint: the same
// degenerate seed.
function function_signature_ty_cycle_initial(
    db: root.hir.Db,
    function_: int,
) -> FunctionSignatureTy throws never {
    FunctionSignatureTy {
        params: [],
        return_type: root.types.TyError {},
        generic_params: [],
        builtin_kind: null,
    }
}

// port: baml_compiler2_hir_ty/src/callable.rs::function_signature_ty @ d9be6853b
// A view over `function_signature` (the one signature road), with own
// generics only.
function function_signature_ty(
    db: root.hir.Db,
    function_: int,
) -> FunctionSignatureTy throws never {
    db.ty_memo.function_signature_ty.get_fixpoint(
        db.cycles,
        function_,
        () -> {
            function_signature_ty_cycle_initial(db, function_)
        },
        () -> {
            let sig = function_signature_with_diagnostics(db, function_).signature;
            let enclosing = enclosing_param_count(db, function_);
            let builtin_kind = match (root.hir.function_body(db, function_)) {
                let builtin: root.hir.FunctionBodyBuiltin => builtin.value,
                root.hir.FunctionBodyExpr | root.hir.FunctionBodyMissing => null,
            };
            let start = if (enclosing < sig.generic_params.length()) {
                enclosing
            } else {
                sig.generic_params.length()
            };
            FunctionSignatureTy {
                params: sig.params.map((param) -> {
                    root.types.FunctionParamTy {
                        name: param.name,
                        ty: param.ty,
                        mode: if (param.has_default) {
                            root.types.FunctionParamMode.Optional
                        } else {
                            root.types.FunctionParamMode.Required
                        },
                    }
                }),
                return_type: sig.ret,
                generic_params: sig.generic_params.slice(start, sig.generic_params.length()),
                builtin_kind: builtin_kind,
            }
        },
    )
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_takes_self @ d9be6853b
// Whether the callable declares a `self` receiver: an instance method rather
// than a static one (the sugar question only).
function callable_takes_self(db: root.hir.Db, callable: int) -> bool throws never {
    function_signature_ty(db, callable).params.at(0)?.name == "self"
}

// port: baml_compiler2_hir_ty/src/callable.rs::lang_function @ d9be6853b
// The function a language package declares at `namespace.name`; null when
// the package is not installed or declares no such function.
function lang_function(
    db: root.hir.Db,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> int? throws never {
    let root_id = root.hir.lang_roots(db).get(package)
        ?? return null;
    match (root.hir.package_items(db, root_id).lookup_value(namespace, name)) {
        let function_: root.hir.DefinitionFunction => function_.value,
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/callable.rs::lang_class_method @ d9be6853b
// The class-inherent method `class.method` a language package declares at
// its root.
function lang_class_method(
    db: root.hir.Db,
    package: root.base.LangPackage,
    class_: string,
    method: string,
) -> int? throws never {
    let root_id = root.hir.lang_roots(db).get(package)
        ?? return null;
    let class_loc = match (root.hir.package_items(db, root_id).lookup_type([], class_)) {
        let def: root.hir.DefinitionClass => def.value,
        _ => {
            return null;
        },
    };
    root.hir.class_data(db, class_loc).methods.find((candidate) -> {
        root.hir.function_data(db, candidate).name == method
    })
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_user_generic_params @ d9be6853b
// Call-site-suppliable generics with their bounds: the callable's own
// parameters minus the synthetic callback-effect parameters.
function callable_user_generic_params(
    db: root.hir.Db,
    callable: int,
) -> (root.types.ParamTy, root.types.InterfaceConstraint[])[] throws never {
    let bounds = function_generic_bounds(db, callable);
    function_signature_ty(db, callable).generic_params
        .filter((param) -> {
            !root.types.is_synthetic_effect_param(param.name)
        })
        .map((param) -> {
            (param, bounds.get(param) ?? [])
        })
}

// port: baml_compiler2_hir_ty/src/callable.rs::CallableFrame @ d9be6853b
// A callable's full generic frame: the owner's prefix, then its own
// parameters, with the declared bound conjunction of every slot.
class CallableFrame {
    params: root.types.ParamTy[],
    // Per frame slot, that parameter's declared bounds (empty when none).
    bounds: root.types.InterfaceConstraint[][],
    // The first slot the call site supplies (turbofish or inferred).
    own_start: int,
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_generic_frame @ d9be6853b
// The frame a call instantiates. `own_start` is the owner frame's length.
function callable_generic_frame(db: root.hir.Db, callable: int) -> CallableFrame throws never {
    let params = function_generic_frame(db, callable);
    let declared = function_generic_bounds(db, callable);
    // The frame is `owner ++ declared ++ synthetic effect`.
    let own = root.hir.elaborated_function_data(db, callable);
    let own_count = own.user_generic_params.length() + own.synthetic_effect_params.length();
    CallableFrame {
        own_start: params.length() - own_count,
        bounds: params.map((param) -> {
            declared.get(param) ?? []
        }),
        params: params,
    }
}

// port: baml_compiler2_hir_ty/src/callable.rs::instantiate_callable_signature @ d9be6853b
// The callable as a value of function type, instantiated at `instantiation`
// (one type per frame slot).
function instantiate_callable_signature(
    db: root.hir.Db,
    callable: int,
    instantiation: int[],
) -> int throws never {
    let pool = db.ty_memo.pool;
    let signature = function_signature_ty(db, callable);
    let substitute = (ty: root.types.Ty) -> int {
        substitute_params(pool, pool.from_plain(ty), instantiation)
    };
    pool.add(
        root.types.InferTyFunction {
            params: signature.params.map((param) -> {
                root.types.InferFunctionParamTy {
                    name: param.name,
                    ty: substitute(param.ty),
                    mode: param.mode,
                }
            }),
            ret: substitute(signature.return_type),
            throws_: substitute(function_signature_with_diagnostics(db, callable).signature.throws_),
        },
    )
}

// port: baml_compiler2_hir_ty/src/callable.rs::SelfDispatch @ d9be6853b
// Where an erased `Self` is dispatched from: the one-`Self` rule.
type SelfDispatch = SelfDispatchOnParam | SelfDispatchNoSelfParam | SelfDispatchBreaks;

// Object-safe: the one required bare-`Self` parameter is at this declared
// index.
class SelfDispatchOnParam {
    value: int,
}

// No parameter is typed `Self`: a caller must name a concrete `Self`.
class SelfDispatchNoSelfParam {
}

// `Self` occurs where the rule forbids it.
class SelfDispatchBreaks {
    value: SelfCallPosition,
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_self_dispatch @ d9be6853b
// `SelfDispatch` for a callable. `Self` is frame slot 0.
function callable_self_dispatch(db: root.hir.Db, callable: int) -> SelfDispatch throws never {
    let pool = db.ty_memo.pool;
    let signature = function_signature_ty(db, callable);
    // `top_ok` permits a bare top-level `Self` and flags only nested ones.
    let occurs = (ty: root.types.Ty, top_ok: bool) -> bool {
        self_occurs(pool, pool.from_plain(ty), top_ok)
    };
    let bare_self = (ty: root.types.Ty) -> bool {
        match (pool.kinds[pool.from_plain(ty)]) {
            let var: root.types.TyTypeVar => var.param.index == 0 && var.param.name == "Self",
            _ => false,
        }
    };
    let dispatch_params: int[] = [];
    for (let index = 0; index < signature.params.length(); index += 1) {
        if (bare_self(signature.params[index].ty)) {
            dispatch_params.push(index);
        }
    }
    let first = dispatch_params.at(0);
    // Every parameter but the one dispatch source must be free of `Self`
    // entirely, unions included.
    let other_param_mentions_self = false;
    for (let index = 0; index < signature.params.length(); index += 1) {
        if (index != first && occurs(signature.params[index].ty, false)) {
            other_param_mentions_self = true;
        }
    }
    if (dispatch_params.length() > 1 || other_param_mentions_self) {
        return SelfDispatchBreaks { value: SelfCallPosition.Parameter };
    }
    // An omitted argument is no value to read `Self` off.
    if (first != null && signature.params[first].mode == root.types.FunctionParamMode.Optional) {
        return SelfDispatchBreaks { value: SelfCallPosition.OptionalParameter };
    }
    if (
        occurs(signature.return_type, true)
            || occurs(function_signature_with_diagnostics(db, callable).signature.throws_, true)
    ) {
        return SelfDispatchBreaks { value: SelfCallPosition.NestedInReturn };
    }
    if (first != null) {
        SelfDispatchOnParam { value: first }
    } else {
        SelfDispatchNoSelfParam {}
    }
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_breaks_one_self @ d9be6853b
// Whether the one-`Self` rule forbids dispatching this callable on an erased
// `Self`.
function callable_breaks_one_self(db: root.hir.Db, callable: int) -> bool throws never {
    callable_self_dispatch(db, callable) is SelfDispatchBreaks
}

// port: baml_compiler2_hir_ty/src/callable.rs::CallableOwnerKind @ d9be6853b
// What declares a callable.
enum CallableOwnerKind {
    // A top-level function.
    Free,
    // A class-inherent method.
    Class,
    // A method an interface declares (required or default).
    Interface,
    // A method an `implements` block provides.
    Impl,
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_owner_kind @ d9be6853b
function callable_owner_kind(db: root.hir.Db, callable: int) -> CallableOwnerKind throws never {
    match (root.hir.method_owner(db, callable)) {
        null => CallableOwnerKind.Free,
        root.hir.MethodOwnerClass => CallableOwnerKind.Class,
        root.hir.MethodOwnerInterface => CallableOwnerKind.Interface,
        root.hir.MethodOwnerImpl => CallableOwnerKind.Impl,
    }
}

// port: baml_compiler2_hir_ty/src/callable.rs::callable_owner_type @ d9be6853b
// The head of the declaration that owns a callable: the class, the
// interface, or the implemented interface; null for a free function (and an
// impl whose header did not resolve).
function callable_owner_type(db: root.hir.Db, callable: int) -> root.types.DeclName? throws never {
    match (root.hir.method_owner(db, callable)) {
        let owner: root.hir.MethodOwnerClass => class_qualified_name(db, owner.value),
        let owner: root.hir.MethodOwnerInterface => interface_qualified_name(db, owner.value),
        let owner: root.hir.MethodOwnerImpl => {
            impl_header_resolution_resolved(impl_facts(db, owner.value))?.interface_.reference.name
        },
        null => null,
    }
}
