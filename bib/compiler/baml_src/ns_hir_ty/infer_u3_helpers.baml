// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 3, context helpers: the language-package lookups (`lang_decl`,
// `lang_value`, `lang_interface_ty`), the interface-member helpers (the
// `self`-less rejections and the declaring interface they name), the
// expectation shapes aggregate literals and lambdas build at, and the
// writeback recorders.
//
// Restructured (BAML forces it):
// - `InferenceContext` methods are free functions taking `ctx` first.
// - The nested `collect` of `callback_root_fn` and `search` of
//   `unique_expected_arm` are `callback_root_fn_collect` and
//   `unique_expected_arm_search`; their `&mut Option<T>` accumulators are
//   arrays holding at most one entry.
// - No root is served from an interface, so the `DeclRef::External` arms of
//   `member_declaring_interface` are dropped.
// Not ported (one-line forwards or accessors): `lang`, `viewpoint`,
// `viewer`, `interface_short_name`, `expand_alias_ty`,
// `write_member_resolution` (see infer_u3.baml's header).

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lang_decl @ d9be6853b
// A declaration of an installed language package, or null when that package
// is not installed: then nothing it declares exists and the rule asking for
// it does not apply.
function lang_decl(
    ctx: InferenceContext,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> root.types.DeclName? throws never {
    let root_id = root.hir.lang_roots(ctx.db).get(package)
        ?? return null;
    root.types.DeclName { pkg: root_id, namespace: namespace, name: name }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lang_value @ d9be6853b
// A function of an installed language package, by that package's IDENTITY:
// the road for every path the compiler itself writes (`baml.json.to`,
// `baml.regex.new`), which no name in the body's scope can capture. Null
// when the package is not installed or declares no such function.
function lang_value(
    ctx: InferenceContext,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> ResolvedValue? throws never {
    let root_id = root.hir.lang_roots(ctx.db).get(package)
        ?? return null;
    let segments = [root.base.lang_package_manifest_name(package)].concat(namespace).concat([name]);
    ctx.lower.resolve_value(root.hir.PathHeadLang { value: root_id }, segments)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::lang_interface_ty @ d9be6853b
// The interface existential `package.namespace.name`, or the error sentinel
// when the package is not installed.
function lang_interface_ty(
    ctx: InferenceContext,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> int throws never {
    let decl = lang_decl(ctx, package, namespace, name);
    if (decl != null) {
        ctx.table.pool.add(
            root.types.InferTyInterface { name: decl, args: [], associated_types: [] },
        )
    } else {
        ctx.table.pool.add(root.types.TyError {})
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::qualified_interface_display @ d9be6853b
// A realized interface rendered for a diagnostic's `as<I>` hint: spelled as
// source in this file writes it (one the file cannot write is shown as the
// viewpoint displays it), with generic args so same-interface
// different-args sources stay distinct.
function qualified_interface_display(
    ctx: InferenceContext,
    iface: root.types.InferInterfaceConstraint,
) -> string throws never {
    let vp = Viewpoint.for_file(ctx.db, ctx.owner_file);
    let base = vp.source_path(iface.name) catch (e) {
        Unspellable => vp.path(iface.name),
    };
    if (iface.generics.length() == 0) {
        return base;
    }
    let args = iface.generics
        .map((arg) -> {
            ty_spell(rendered_plain(ctx.table.pool, arg), vp)
        })
        .join(", ");
    `${base}<${args}>`
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_member_takes_self @ d9be6853b
// Whether a resolved interface METHOD takes a `self` receiver. A `self`-less
// method is an associated function, not an instance member: it is reachable
// through the type-qualified spellings only. Fields have no
// receiver-vs-associated split.
function interface_member_takes_self(
    ctx: InferenceContext,
    member: InterfaceMember,
) -> bool throws never {
    match (member.declarer) {
        let virtual: MemberDeclarerVirtualMethod => callable_takes_self(ctx.db, virtual.method),
        let concrete: MemberDeclarerImplMethod => callable_takes_self(ctx.db, concrete.func),
        MemberDeclarerVirtualField | MemberDeclarerImplField => true,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::reject_selfless_inherent_method @ d9be6853b
// A class-INHERENT static reached through a value receiver: reports and
// returns true. `Widget.make(..)` is the spelling.
function reject_selfless_inherent_method(
    ctx: InferenceContext,
    method: int,
    member_name: string,
    at: int,
) -> bool throws never {
    if (callable_takes_self(ctx.db, method)) {
        return false;
    }
    if (!suppressed(ctx, Suppress.MemberProbe)) {
        // An in-class `implements` method resolves as an ordinary class
        // candidate, so this road is where a CONCRETE receiver's interface
        // static lands. Name its interface when it has one.
        report(
            ctx,
            PendingDiagSelflessInstanceMember {
                expr: at,
                interface_name: declaring_interface_of_method(ctx, method),
                member: member_name,
            },
        );
    }
    true
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::member_declaring_interface @ d9be6853b
// The interface a resolved member was declared by, for the diagnostic that
// names it. The FIELD declarers cannot occur here: the only caller has
// already required `member.is_method`.
function member_declaring_interface(
    ctx: InferenceContext,
    declarer: MemberDeclarer,
) -> string? throws never {
    match (declarer) {
        let virtual: MemberDeclarerVirtualMethod => {
            root.hir.interface_data(ctx.db, virtual.interface_).name
        },
        let concrete: MemberDeclarerImplMethod => declaring_interface_of_method(ctx, concrete.func),
        MemberDeclarerVirtualField | MemberDeclarerImplField => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::declaring_interface_of_method @ d9be6853b
// The interface a METHOD belongs to, from the method alone: an inherited
// default body is owned by the interface, and a method written inside an
// `implements` block records that block's interface target. Null for a
// genuinely inherent method.
function declaring_interface_of_method(ctx: InferenceContext, func: int) -> string? throws never {
    match (root.hir.method_owner(ctx.db, func)) {
        let owner: root.hir.MethodOwnerInterface => {
            return root.hir.interface_data(ctx.db, owner.value).name;
        },
        _ => {},
    }
    let target = root.hir.method_interface_target(ctx.db, func)
        ?? return null;
    match (
        ctx.lower.lower_type_ref(
            target.type_refs,
            target.target,
            position = TypePosition.ConstraintHead,
        )
    ) {
        let interface_: root.types.LoweringTyInterface => interface_.name.name,
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::reject_selfless_instance_member @ d9be6853b
// A `self`-less member reached through a VALUE receiver, whatever the
// receiver's kind: reports and returns true. The type-qualified spellings
// are the only roads.
function reject_selfless_instance_member(
    ctx: InferenceContext,
    member: InterfaceMember,
    member_name: string,
    at: int,
) -> bool throws never {
    if (!member.is_method || interface_member_takes_self(ctx, member)) {
        return false;
    }
    if (!suppressed(ctx, Suppress.MemberProbe)) {
        report(
            ctx,
            PendingDiagSelflessInstanceMember {
                expr: at,
                interface_name: member_declaring_interface(ctx, member.declarer),
                member: member_name,
            },
        );
    }
    true
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::interface_member_value @ d9be6853b
// An interface member in VALUE position: no turbofish, so a default
// method's own generics instantiate fresh; methods bind their receiver.
// Shared by field access and the `default.` value road.
function interface_member_value(
    ctx: InferenceContext,
    interface_member: InterfaceMember,
    at: int,
) -> int throws never {
    let pool = ctx.table.pool;
    let pending = interface_member.pending_own;
    if (pending != null) {
        // A VALUE reference, reported as the unspecialized value, not as an
        // uninferred slot; its bounds are judged here, as a call's are at the
        // call.
        let own = function_signature_ty(ctx.db, pending.callable).generic_params.map((param) -> {
            fresh_generic_arg(ctx, param)
        });
        let owner_count = pending.prefix.length();
        let instantiation = pending.prefix.concat(own);
        register_callable_instantiation(ctx, pending.callable, instantiation, at);
        if (own.length() > 0 && !suppressed(ctx, Suppress.MemberProbe)) {
            // The bound value carries its own instantiation: the receiver (or
            // `default`'s adopted frame) supplies the owner prefix.
            write_call_type_args(ctx, at, instantiation, owner_count);
        }
        return bind_receiver(
            pool,
            instantiate_member_signature(ctx.db, ctx.facts, pending.callable, instantiation, pending.arms),
        );
    }
    // Same rule as the call road: a `self`-less method binds nothing.
    if (interface_member.is_method && interface_member_takes_self(ctx, interface_member)) {
        return bind_receiver(pool, interface_member.ty);
    }
    interface_member.ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::expectation_shape @ d9be6853b
// The expectation's SHAPE for aggregate-literal adoption: nominal aliases
// expanded through the oracle, so the recursive `baml.json.json` union
// answers structurally.
function expectation_shape(ctx: InferenceContext, expected: Expectation) -> int? throws never {
    let ty = expectation_only_has_type(expected)
        ?? return null;
    structurally_resolve(ctx, ty)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::callback_root_fn @ d9be6853b
// The sole concrete function type at a callback root: `ty` itself, or the
// unique function member nested through unions and type aliases. Multiple
// function arms remain ambiguous and provide no context; the traversal is
// fuel-bounded because recursive aliases offer no finite unique shape.
function callback_root_fn(ctx: InferenceContext, ty: int) -> int? throws never {
    let callback: int[] = [];
    if (callback_root_fn_collect(ctx, ty, callback, 16)) {
        callback.at(0)
    } else {
        null
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::callback_root_fn::collect @ d9be6853b
function callback_root_fn_collect(
    ctx: InferenceContext,
    ty: int,
    callback: int[],
    fuel: int,
) -> bool throws never {
    if (fuel == 0) {
        return false;
    }
    let pool = ctx.table.pool;
    let expanded = expand_alias_head(pool, ty, ctx.facts);
    match (pool.kinds[expanded]) {
        root.types.InferTyFunction => {
            if (callback.length() > 0) {
                return false;
            }
            callback.push(expanded);
            true
        },
        let union_: root.types.InferTyUnion => {
            union_.members.every((member) -> {
                callback_root_fn_collect(ctx, member, callback, fuel - 1)
            })
        },
        root.types.TyTypeAlias => false,
        _ => true,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::expected_list_element @ d9be6853b
// The element an ARRAY literal adopts from its expectation: the expected
// list itself, or the UNIQUE list member of an expected union. Arrays are
// invariant, so this adoption is what makes `[1, 2, 3]` a `json[]` against
// the recursive `json` union.
function expected_list_element(ctx: InferenceContext, expected: Expectation) -> int? throws never {
    let pool = ctx.table.pool;
    let shape = expectation_shape(ctx, expected)
        ?? return null;
    unique_expected_arm(
        ctx,
        shape,
        (arm) -> int? {
            match (pool.kinds[arm]) {
                let list: root.types.InferTyList => list.elem,
                _ => null,
            }
        },
        (a, b) -> {
            a == b
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::expected_tuple_elements @ d9be6853b
// The TUPLE literal's counterpart of `expected_list_element`, at `arity`.
function expected_tuple_elements(
    ctx: InferenceContext,
    expected: Expectation,
    arity: int,
) -> int[]? throws never {
    let pool = ctx.table.pool;
    let shape = expectation_shape(ctx, expected)
        ?? return null;
    unique_expected_arm(
        ctx,
        shape,
        (arm) -> int[]? {
            match (pool.kinds[arm]) {
                let tuple: root.types.InferTyTuple if tuple.items.length() == arity => tuple.items,
                _ => null,
            }
        },
        (a, b) -> {
            a == b
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::expected_map_entry @ d9be6853b
// The MAP literal's counterpart of `expected_list_element`.
function expected_map_entry(
    ctx: InferenceContext,
    expected: Expectation,
) -> (int, int)? throws never {
    let pool = ctx.table.pool;
    let shape = expectation_shape(ctx, expected)
        ?? return null;
    unique_expected_arm(
        ctx,
        shape,
        (arm) -> (int, int)? {
            match (pool.kinds[arm]) {
                let entry: root.types.InferTyMap => (entry.key, entry.value),
                _ => null,
            }
        },
        (a, b) -> {
            a.0 == b.0 && a.1 == b.1
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::expectation_shapes @ d9be6853b
// Whether `expected` gives `expr` a shape to build at: an aggregate literal
// needs a unique list/map/tuple arm, a lambda a callback arm. Any other
// expression takes the expectation as-is.
function expectation_shapes(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    expr: int,
    expected: Expectation,
) -> bool throws never {
    match (body.exprs[expr]) {
        root.ast.ExprArray => expected_list_element(ctx, expected) != null,
        root.ast.ExprMap => expected_map_entry(ctx, expected) != null,
        let tuple: root.ast.ExprTuple => {
            expected_tuple_elements(ctx, expected, tuple.elements.length()) != null
        },
        root.ast.ExprLambda => {
            let ty = expectation_only_has_type(expected);
            ty != null && callback_root_fn(ctx, structurally_resolve(ctx, ty)) != null
        },
        _ => true,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::expected_class_args @ d9be6853b
// The arguments a generic constructor's EXPECTED type gives its class: the
// unique arm naming the same class. Class arguments are invariant, so that
// arm is the only instantiation the object can take there.
function expected_class_args(
    ctx: InferenceContext,
    expected: Expectation,
    head: root.types.DeclName,
) -> int[]? throws never {
    let pool = ctx.table.pool;
    let shape = expectation_shape(ctx, expected)
        ?? return null;
    unique_expected_arm(
        ctx,
        shape,
        (arm) -> int[]? {
            match (pool.kinds[arm]) {
                let class_: root.types.InferTyClass if class_.name == head => class_.args,
                _ => null,
            }
        },
        (a, b) -> {
            a == b
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::constructor_arg_hints @ d9be6853b
// The instantiation that INFORMS a generic constructor's field values: each
// still-open slot takes the argument the expected type gives the same
// class. Null when every slot is already determined or the expectation
// names no unique arm.
function constructor_arg_hints(
    ctx: InferenceContext,
    expected: Expectation,
    head: root.types.DeclName,
    instantiation: int[],
) -> int[]? throws never {
    let open = instantiation.map((arg) -> {
        ctx.table.pool.has_infer(ctx.table.resolve_completely(arg))
    });
    if (!open.includes(true)) {
        return null;
    }
    let expected_args = expected_class_args(ctx, expected, head)
        ?? return null;
    if (expected_args.length() != instantiation.length()) {
        return null;
    }
    baml.Array.generate(instantiation.length(), (index) -> {
        if (open[index]) {
            expected_args[index]
        } else {
            instantiation[index]
        }
    })
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::check_object_field @ d9be6853b
// Checks a constructor field value against its declared type at the
// object's `instantiation`. With `hints`, the value is first inferred
// against the declared type at the hinted arguments; this only INFORMS the
// value, while the check that constrains the open slots remains against the
// object's own instantiation.
function check_object_field(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    value: int,
    field_ty: int,
    instantiation: int[],
    hints: int[]?,
) -> void throws never {
    let pool = ctx.table.pool;
    let declared = substitute_params(pool, field_ty, instantiation);
    if (hints != null) {
        let hint = substitute_params(pool, field_ty, hints);
        let ty = infer_expr_with_hint(ctx, body, value, hint);
        check_inferred(ctx, value, ty, declared);
    } else {
        check_expr(ctx, body, value, declared);
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::unique_expected_arm @ d9be6853b
// The single arm of `ty` that `pick` accepts, looking through nested unions
// and type aliases. Two distinct accepted arms are ambiguous and give no
// context. Each alias expands at most once per search, so recursive aliases
// terminate without a depth limit.
function unique_expected_arm<T>(
    ctx: InferenceContext,
    ty: int,
    pick: (int) -> T? throws never,
    same: (T, T) -> bool throws never,
) -> T? throws never {
    let found: T[] = [];
    if (unique_expected_arm_search(ctx, ty, pick, same, [], found)) {
        found.at(0)
    } else {
        null
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::unique_expected_arm::search @ d9be6853b
function unique_expected_arm_search<T>(
    ctx: InferenceContext,
    ty: int,
    pick: (int) -> T? throws never,
    same: (T, T) -> bool throws never,
    expanded: root.types.DeclName[],
    found: T[],
) -> bool throws never {
    let pool = ctx.table.pool;
    match (pool.kinds[ty]) {
        let alias: root.types.TyTypeAlias => {
            if (expanded.includes(alias.name)) {
                return true;
            }
            expanded.push(alias.name);
            let expansion = ctx.facts.alias_def(alias.name);
            if (expansion != null) {
                unique_expected_arm_search(ctx, pool.from_plain(expansion), pick, same, expanded, found)
            } else {
                true
            }
        },
        let union_: root.types.InferTyUnion => {
            union_.members.every((member) -> {
                unique_expected_arm_search(ctx, member, pick, same, expanded, found)
            })
        },
        _ => {
            let arm = pick(ty);
            if (arm == null) {
                return true;
            }
            let prior = found.at(0);
            if (prior != null && !same(prior, arm)) {
                return false;
            }
            if (found.length() > 0) {
                found[0] = arm;
            } else {
                found.push(arm);
            }
            true
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::write_call_type_args @ d9be6853b
// Records a call's solved instantiation vector (raw; ground after
// writeback) with the owner-prefix split. The plan's two halves have two
// writers keyed by the same call id: type args at the instantiation site,
// bindings in `check_call_args`.
function write_call_type_args(
    ctx: InferenceContext,
    call: int,
    type_args: int[],
    own_offset: int,
) -> int[] throws never {
    let explicit = ctx.type_refs.expr_type_args.has(call);
    let plan = ctx.result.call_plans.get_or_insert(call, CallPlan.default());
    plan.type_args = type_args.slice(0, type_args.length());
    plan.own_offset = own_offset;
    plan.explicit = explicit;
    type_args
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::walk_path_members @ d9be6853b
// Walks the MEMBER segments of a value-rooted path (everything after the
// root name), returning the final type and the recorded ladder. Callers
// append their final segment when they resolve it differently and then
// write the tables.
function walk_path_members(
    ctx: InferenceContext,
    expr: int,
    root_ty: int,
    members: string[],
) -> (int, ResolvedPathSegment<int>[]) throws never {
    let steps: ResolvedPathSegment<int>[] = [ResolvedPathSegment { ty: root_ty, resolution: null }];
    let ty = root_ty;
    for (let member in members) {
        let (let next, let resolution) = field_access_resolved(ctx, expr, ty, member);
        steps.push(ResolvedPathSegment { ty: next, resolution: resolution });
        ty = next;
    }
    (ty, steps)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::write_resolved_path @ d9be6853b
// Records a value-rooted path's ladder, and its final member's resolution
// as the expression's member resolution.
function write_resolved_path(
    ctx: InferenceContext,
    expr: int,
    steps: ResolvedPathSegment<int>[],
) -> void throws never {
    if (steps.length() < 2) {
        return;
    }
    let last = steps[steps.length() - 1].resolution;
    if (last != null) {
        ctx.result.member_resolutions[expr] = last;
    }
    ctx.result.path_resolutions[expr] = ResolvedPath { segments: steps };
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::untyped_empty_container_ty @ d9be6853b
// An empty container literal with nothing to type it: a container-slot
// variable inside `make_container`'s shape, registered so an unsolved slot
// reports at `expr`.
function untyped_empty_container_ty(
    ctx: InferenceContext,
    expr: int,
    make_container: (int) -> int throws never,
) -> int throws never {
    let slot = ctx.table.new_var_ty(policy = root.hir_ty.infer.VarPolicy.ContainerSlot);
    let var = match (ctx.table.pool.kinds[slot]) {
        let v: root.types.TyInferVar => v.var,
        _ => baml.sys.panic("a fresh establishment variable must be an inference type"),
    };
    let containing_type = make_container(slot);
    ctx.journals.infer_var_origins[var]
        = InferVarOriginTypeMustBeKnown {
            location: DiagnosticLocationExpr { value: expr },
            containing_type: containing_type,
        };
    containing_type
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::untyped_lambda_parameter_ty @ d9be6853b
// An unannotated lambda parameter with no expected type: a lambda-param
// variable, registered so an unsolved one reports naming the parameter.
function untyped_lambda_parameter_ty(
    ctx: InferenceContext,
    lambda: int,
    parameter_index: int,
    name: string,
) -> int throws never {
    let ty = ctx.table.new_var_ty(policy = root.hir_ty.infer.VarPolicy.LambdaParam);
    let var = match (ctx.table.pool.kinds[ty]) {
        let v: root.types.TyInferVar => v.var,
        _ => baml.sys.panic("a fresh lambda parameter variable must be an inference type"),
    };
    ctx.journals.infer_var_origins[var]
        = InferVarOriginLambdaParameter {
            lambda: lambda,
            parameter_index: parameter_index,
            name: name,
        };
    ty
}
