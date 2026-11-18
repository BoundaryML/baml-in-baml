// port: baml_compiler2_hir_ty/src/infer.rs @ d9be6853b
//
// K4 unit 4, objects: object literals (`infer_object` and the constructor
// head) and value-position member access (`field_access_resolved`,
// `union_member_access`).
//
// Restructured (BAML forces it):
// - `InferenceContext` methods are free functions taking `ctx` first.
// - No root is served from an interface (`root.hir.is_served_from_interface`),
//   so a `ClassRef` is its Source lane, a class loc `int`, and the External
//   arms are dropped: the `Exported` class rows and `mounted_class_loc`
//   fallbacks of `constructor_head`, the mounted-class field lookup of
//   `class_field_access`, and `infer_object`'s External dispatch.
// - Rust's `Result<T, ConstructorMiss>` is the union `T | ConstructorMiss`.
// - `builtin_companion_of_decl` (baml_type/src/type_kind.rs) is not ported
//   in `ns_types`, which this unit may not edit; it is ported here.
//
// Not ported: `infer_exported_object` (External lane only).

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_object @ d9be6853b
function infer_object(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    object: int,
    expected: Expectation,
    type_name: root.base.Path,
    fields: root.ast.ObjectExprField[],
    spreads: root.ast.SpreadField[],
) -> int throws never {
    match (constructor_head(ctx, object, type_name)) {
        let miss: ConstructorMiss => {
            // A WRITTEN constructor head that denotes no class reports as an
            // unresolved type with near-match suggestions
            // (`ValidationIssu { .. }` suggests the class), unless the head
            // itself was already reported.
            let segments = type_name.segments;
            match (miss) {
                ConstructorMiss.Unresolved if segments.length() > 0 => {
                    report(
                        ctx,
                        PendingDiagUnresolvedCtor {
                            expr: object,
                            name: segments.join("."),
                            suggestions: ctx.lower.type_suggestions(segments),
                        },
                    );
                },
                ConstructorMiss.TypeParameter => {
                    report(
                        ctx,
                        PendingDiagConstructedTypeParameter {
                            expr: object,
                            name: segments.join("."),
                        },
                    );
                },
                // `Unresolved` with no segments is parse recovery's shape, and
                // the parse error is its report.
                ConstructorMiss.Unresolved | ConstructorMiss.Reported => {},
            }
            for (let field in fields) {
                infer_expr(ctx, body, field.value, ExpectationNone {});
            }
            for (let spread in spreads) {
                infer_expr(ctx, body, spread.expr, ExpectationNone {});
            }
            ctx.table.pool.add(root.types.TyError {})
        },
        let found: (int, int[]?) => {
            infer_source_object(ctx, body, object, expected, type_name, found.0, found.1, fields, spreads)
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::constructor_head @ d9be6853b
// The class a written constructor head denotes, with the instantiation an
// alias pins (null when the head names the class itself and the arguments
// are the object's own). A scoped type parameter or a lexical generic
// parameter shadows every item and denotes no class; an alias of anything
// but a class denotes none either.
// Restructured: Rust's `Result<T, E>` is the union `T | E`.
function constructor_head(
    ctx: InferenceContext,
    object: int,
    type_name: root.base.Path,
) -> (int, int[]?) | ConstructorMiss throws never {
    let db = ctx.db;
    let segments = type_name.segments;
    let head = ctx.lower.type_path_head(type_name.origin, segments);
    if (scoped_type_param_heads(ctx, head, segments)) {
        return ConstructorMiss.TypeParameter;
    }
    let resolved = ctx.lower.resolve_type(head, segments)
        ?? return ConstructorMiss.Unresolved;
    let alias_value = match (resolved) {
        let source: ResolvedTypeDefinitionSource => {
            match (source.value) {
                let class_: root.hir.DefinitionClass => {
                    return (class_.value, null);
                },
                let alias: root.hir.DefinitionTypeAlias => type_alias_value(db, alias.value),
                _ => {
                    return ConstructorMiss.Unresolved;
                },
            }
        },
        let exported: ResolvedTypeDefinitionExported => {
            match (exported.value) {
                let alias: ExportedTypeTypeAlias => alias.resolved,
                ExportedTypeClass | ExportedTypeEnum | ExportedTypeInterface => {
                    return ConstructorMiss.Unresolved;
                },
            }
        },
    };
    let short = type_name.leaf();
    // An alias takes no arguments of its own: written ones are an arity
    // error, and the class's come from the alias's definition.
    let written = ctx.type_refs.expr_type_args.get(object)?.length() ?? 0;
    if (written > 0) {
        report(ctx, PendingDiagAliasTakesNoTypeArgs { expr: object, name: short, got: written });
    }
    let denoted = class_denoted_by(ctx, alias_value);
    if (denoted == null) {
        report(ctx, PendingDiagAliasNotConstructible { expr: object, name: short, denotes: alias_value });
        return ConstructorMiss.Reported;
    }
    let (let class_head, let args) = denoted;
    let pinned = args.map((arg) -> {
        ctx.table.pool.from_plain(arg)
    });
    match (definition_of(db, class_head)) {
        let class_: root.hir.DefinitionClass => (class_.value, pinned),
        _ => ConstructorMiss.Unresolved,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_denoted_by @ d9be6853b
// The class `ty` denotes once aliases are expanded: a class itself, or an
// alias chain ending in one. A chain that revisits an alias is a declaration
// cycle (rejected at its declaration) and denotes no class.
function class_denoted_by(
    ctx: InferenceContext,
    ty: root.types.Ty,
) -> (root.types.DeclName, root.types.Ty[])? throws never {
    let visited: root.types.DeclName[] = [];
    let current = ty;
    while (true) {
        match (current) {
            let class_: root.types.TyClass => {
                return (class_.name, class_.args);
            },
            let alias: root.types.TyTypeAlias => {
                if (visited.includes(alias.name)) {
                    return null;
                }
                current
                    = uncached_alias_def(ctx.db, alias.name)
                        ?? return null;
                visited.push(alias.name);
            },
            _ => {
                return null;
            },
        }
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::infer_source_object @ d9be6853b
// A source class under construction: at `pinned` arguments when the head
// was an alias (the object is then the class the alias denotes), else at the
// object's own written or inferred ones.
function infer_source_object(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    object: int,
    expected: Expectation,
    type_name: root.base.Path,
    class_: int,
    pinned: int[]?,
    fields: root.ast.ObjectExprField[],
    spreads: root.ast.SpreadField[],
) -> int throws never {
    let db = ctx.db;
    let pool = ctx.table.pool;
    let class_name = class_qualified_name(db, class_);
    if (is_opaque_trace_type(ctx, class_name)) {
        report(ctx, PendingDiagTraceOpaqueValue { expr: object });
        return pool.add(root.types.TyError {});
    }
    if (root.types.is_type_kind_class_decl(infer_ctx_lang(ctx), class_name)) {
        for (let field in fields) {
            infer_expr(ctx, body, field.value, ExpectationNone {});
        }
        for (let spread in spreads) {
            infer_expr(ctx, body, spread.expr, ExpectationNone {});
        }
        report(ctx, PendingDiagCannotConstructReflectionKind { expr: object, class_name: class_name });
        return pool.add(root.types.TyError {});
    }
    let companion = builtin_companion_of_decl(infer_ctx_lang(ctx), class_name);
    if (companion != null) {
        for (let field in fields) {
            infer_expr(ctx, body, field.value, ExpectationNone {});
        }
        for (let spread in spreads) {
            infer_expr(ctx, body, spread.expr, ExpectationNone {});
        }
        report(
            ctx,
            PendingDiagCannotConstructBuiltinCompanion {
                expr: object,
                class_name: class_name,
                companion: companion,
            },
        );
        return pool.add(root.types.TyError {});
    }
    let field_types = class_field_types(db, class_);
    let opaque = field_types.find((entry) -> {
        entry.1 is root.types.TyRustType
    });
    if (opaque != null) {
        return refuse_opaque_construction(ctx, body, object, class_name, opaque.0, fields, spreads);
    }
    let generic_count = root.hir.class_data(db, class_).generic_params.length();
    let generic_names = class_generic_frame(db, class_);
    let through_alias = pinned != null;
    let instantiation = if (pinned != null) {
        pinned
    } else {
        instantiation_args(ctx, object, generic_names, null)
    };
    root.syntax.truncate(instantiation, generic_count);
    while (instantiation.length() < generic_count) {
        instantiation.push(ctx.table.new_var_ty());
    }
    register_class_bounds(ctx, class_, instantiation, object);
    // The object's head: the written spelling (a `$stream` companion
    // re-qualifies under its own name), or through an alias the class the
    // alias denotes.
    let object_head = if (through_alias) {
        class_name
    } else {
        ctx.lower.qualify(root.hir.DefinitionClass { value: class_ }, type_name.leaf())
    };
    let hints = constructor_arg_hints(ctx, expected, object_head, instantiation);
    let declared = field_types.map((entry) -> {
        entry.0
    });
    for (let field in fields) {
        let name = field.name;
        let value = field.value;
        let field_ty = field_types.find((entry) -> {
            entry.0 == name
        });
        if (field_ty != null) {
            check_object_field(ctx, body, value, pool.from_plain(field_ty.1), instantiation, hints);
            continue;
        }
        // An INTERFACE field of an implemented interface is not a
        // constructor key: interface fields are satisfied by class-owned
        // fields (or explicit `field as class_field` links). Name the backing
        // class field, and still type the value against it so a wrong value
        // ALSO reports (both diagnostics carry signal).
        if let class_field: string = constructor_interface_field_link(ctx, class_, name) {
            report(
                ctx,
                PendingDiagInterfaceFieldInConstruction {
                    object: object,
                    name: name,
                    class_field: class_field,
                },
            );
            let backing = field_types.find((entry) -> {
                entry.0 == class_field
            });
            if (backing != null) {
                check_object_field(ctx, body, value, pool.from_plain(backing.1), instantiation, hints);
            } else {
                infer_expr(ctx, body, value, ExpectationNone {});
            }
            continue;
        }
        infer_expr(ctx, body, value, ExpectationNone {});
        report(
            ctx,
            PendingDiagUnknownObjectField {
                object: object,
                value: value,
                class_name: qualify_def(
                    db,
                    root.hir.DefinitionClass { value: class_ },
                    root.hir.class_data(db, class_).name,
                ),
                declared: declared,
                name: name,
                shorthand: field.syntax == root.ast.PropertySyntax.Shorthand,
            },
        );
    }
    report_missing_required_object_fields(ctx, object, class_name, field_types, instantiation, fields, spreads.length() > 0);
    let object_ty = pool.add(root.types.InferTyClass { name: object_head, args: instantiation });
    // A spread source must BE the constructed class at the same arguments
    // (fields are invariant slots): checking against the object's own type
    // both enforces that and lets `Left { ...source }` solve open
    // instantiation slots from the source.
    for (let spread in spreads) {
        check_expr(ctx, body, spread.expr, object_ty);
    }
    object_ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::refuse_opaque_construction @ d9be6853b
// A class literal for a class that holds `$rust_type` state in `field`. Only
// the class's own native functions create that state, so a literal could
// only copy a handle out of another value, relabelling what it means. The
// members are still walked, so their own errors report.
function refuse_opaque_construction(
    ctx: InferenceContext,
    body: root.ast.ExprBody,
    object: int,
    class_name: root.types.DeclName,
    field: string,
    fields: root.ast.ObjectExprField[],
    spreads: root.ast.SpreadField[],
) -> int throws never {
    for (let member in fields) {
        infer_expr(ctx, body, member.value, ExpectationNone {});
    }
    for (let spread in spreads) {
        infer_expr(ctx, body, spread.expr, ExpectationNone {});
    }
    report(
        ctx,
        PendingDiagCannotConstructOpaqueClass { expr: object, class_name: class_name, field: field },
    );
    ctx.table.pool.add(root.types.TyError {})
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::field_access @ d9be6853b
// Member access in value position. Inspection site: the receiver must
// resolve enough to look inside (rustc's `structurally_resolve` discipline).
// Class fields first; then methods on any receiver kind, as full signatures
// (self included) with the receiver pinning the class generics and fresh
// variables for the method's own (value position has no turbofish).
function field_access(
    ctx: InferenceContext,
    at: int,
    base_ty: int,
    member: string,
) -> int throws never {
    let (let ty, let resolution) = field_access_resolved(ctx, at, base_ty, member);
    if (resolution != null) {
        write_member_resolution(ctx, at, resolution);
    }
    ty
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::report_bare_output_format_reference @ d9be6853b
function report_bare_output_format_reference(
    ctx: InferenceContext,
    expr: int,
    function_: int,
) -> void throws never {
    let class_ = callable_owner_type(ctx.db, function_)
        ?? return;
    let is_output_format = root.hir.function_data(ctx.db, function_).name == "output_format"
        && infer_ctx_lang(ctx).is_(root.base.LangPackage.Ai, class_.pkg)
        && match (class_.name) {
            "Context" => class_.namespace.length() == 0,
            "SpecCtx" => class_.namespace.length() == 1 && class_.namespace[0] == "internal",
            _ => false,
        };
    if (is_output_format) {
        report(ctx, PendingDiagBareOutputFormatReference { expr: expr });
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::is_opaque_trace_type @ d9be6853b
function is_opaque_trace_type(
    ctx: InferenceContext,
    name: root.types.DeclName,
) -> bool throws never {
    infer_ctx_lang(ctx).is_(root.base.LangPackage.Trace, name.pkg)
        && name.namespace.length() == 0
        && ["Options", "ReservedSpan", "SpanId"].includes(name.name)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::class_field_access @ d9be6853b
// Class-owned fields have the same precedence in value and callee position.
function class_field_access(
    ctx: InferenceContext,
    at: int,
    receiver: int,
    member: string,
) -> (int, WorkingMemberResolution?)? throws never {
    let pool = ctx.table.pool;
    let class_ty = match (pool.kinds[receiver]) {
        let c: root.types.InferTyClass => c,
        _ => {
            return null;
        },
    };
    if (member == "_handle" && is_opaque_trace_type(ctx, class_ty.name)) {
        report(ctx, PendingDiagTraceOpaqueValue { expr: at });
        return (pool.add(root.types.TyError {}), null);
    }
    let class_ = match (definition_of(ctx.db, class_ty.name)) {
        let c: root.hir.DefinitionClass => c.value,
        _ => {
            return null;
        },
    };
    let field = class_field_types(ctx.db, class_).find((entry) -> {
        entry.0 == member
    })
        ?? return null;
    (
        substitute_params(pool, pool.from_plain(field.1), class_ty.args),
        MemberResolutionField { class_: class_, field: member },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::field_access_resolved @ d9be6853b
// The resolution core behind `field_access`: hands the resolution BACK
// instead of recording, so the union arm can drop its per-member
// recursion's resolutions (one expression, one recorded entry) and
// `member_callee` can key a call's entry on the CALLEE expression rather than
// the anchor.
// Restructured: Rust's `str::parse::<usize>` is a digit check plus
// `bigint.parse`; an index past BAML's `int` range is not a tuple slot (Rust
// reads up to `usize::MAX`), which no tuple has anyway.
function field_access_resolved(
    ctx: InferenceContext,
    at: int,
    base_ty: int,
    member: string,
) -> (int, WorkingMemberResolution?) throws never {
    let pool = ctx.table.pool;
    let error = () -> int {
        pool.add(root.types.TyError {})
    };
    // `structurally_resolve` expands weak aliases, so `json` answers as its
    // union and an alias-of-class answers as the class: every arm below sees
    // the target.
    let resolved = structurally_resolve(ctx, base_ty);
    let slot = if (member.length() > 0 && member.is_ascii_numeric()) {
        root.types.int63_new(bigint.parse(member)) catch (e) {
            _ => null,
        }
    } else {
        null
    };
    if (slot != null) {
        if let tuple: root.types.InferTyTuple = pool.kinds[resolved] {
            let element = tuple.items.at(slot);
            if (element != null) {
                return (element, null);
            }
            report(
                ctx,
                PendingDiagTupleIndexOutOfRange {
                    expr: at,
                    index: slot,
                    tuple: resolved,
                    variant: null,
                },
            );
            return (error(), null);
        }
    }
    let field = class_field_access(ctx, at, resolved, member);
    if (field != null) {
        return field;
    }
    // A union behaves as the intersection existential over the interfaces
    // every arm provides (TIR's rule): `member` resolves through the SINGLE
    // shared interface that declares it, inference sugar for
    // `union.as<I>.member` with `Self` bound to the union itself.
    if let union: root.types.InferTyUnion = pool.kinds[resolved] {
        return union_member_access(ctx, at, resolved, union.members, member);
    }
    let candidate = lookup_method(ctx.db, ctx.facts, resolved, member);
    if (candidate != null) {
        return field_access_method(ctx, at, resolved, member, candidate);
    }
    match (lookup_interface_member(ctx.db, viewer(ctx), ctx.facts, resolved, member)) {
        let found: InterfaceMemberLookupFound => {
            let interface_member = found.value;
            if (reject_selfless_instance_member(ctx, interface_member, member, at)) {
                return (error(), null);
            }
            let resolution = declarer_resolution(ctx, interface_member.declarer, member, Receiver.Bound);
            return (interface_member_value(ctx, interface_member, at), resolution);
        },
        let ambiguous: InterfaceMemberLookupAmbiguous => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagAmbiguousMember {
                        expr: at,
                        base: resolved,
                        member: member,
                        sources: ambiguous.sources,
                        is_field: ambiguous.is_field,
                    },
                );
            }
            return (error(), null);
        },
        let projection: InterfaceMemberLookupFieldRequiresProjection => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagFieldRequiresProjection {
                        expr: at,
                        base: resolved,
                        member: member,
                        interface_: projection.interface_,
                    },
                );
            }
            // Reported above: `Error` taints the expression so the missing
            // view is not restated as a type mismatch.
            return (error(), null);
        },
        let restricted: InterfaceMemberLookupSelfRestricted => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagSelfRestrictedMember {
                        expr: at,
                        interface_: restricted.interface_,
                        member: member,
                        position: restricted.position,
                    },
                );
            }
            return (error(), null);
        },
        InterfaceMemberLookupNotFound => {},
    }
    // A definitely-missing member on a KNOWN base reports; an error base is
    // a cascade of an earlier failure (rustc's tainted_by_errors
    // discipline), and a PROBE leaves the report to its committed frame. A
    // var-carrying base is no cascade: it is not inferred yet, and the
    // `Error` returned here is permanent, so it must report (rustc's E0282).
    // `unknown` reports too: it must be narrowed before member access.
    if (!suppressed(ctx, Suppress.MemberProbe) && !pool.has_error(resolved)) {
        // The report owns the receiver's open classes.
        ctx.table.taint_vars_in(resolved);
        if (pool.has_infer(resolved)) {
            report(ctx, PendingDiagReceiverTypeMustBeKnown { expr: at, member: member });
        } else {
            report(ctx, PendingDiagUnresolvedMember { expr: at, base: resolved, member: member });
        }
    }
    (error(), null)
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::field_access_resolved @ d9be6853b
// The class-inherent method arm of `field_access_resolved`: the method as a
// receiver-BOUND value. Restructured: split out of `field_access_resolved`.
function field_access_method(
    ctx: InferenceContext,
    at: int,
    resolved: int,
    member: string,
    candidate: MethodCandidate,
) -> (int, WorkingMemberResolution?) throws never {
    let pool = ctx.table.pool;
    // An own method does not arbitrate an interface clash (E0121): see the
    // callee road's twin check.
    let ambiguity = concrete_member_ambiguity(ctx.db, viewer(ctx), ctx.facts, resolved, member);
    if (ambiguity != null) {
        if (!suppressed(ctx, Suppress.MemberProbe)) {
            report(
                ctx,
                PendingDiagAmbiguousMember {
                    expr: at,
                    base: resolved,
                    member: member,
                    sources: ambiguity.0,
                    is_field: ambiguity.1,
                },
            );
        }
        return (pool.add(root.types.TyError {}), null);
    }
    let method = candidate.method;
    if (reject_selfless_inherent_method(ctx, method, member, at)) {
        return (pool.add(root.types.TyError {}), null);
    }
    if (!suppressed(ctx, Suppress.MemberProbe)) {
        report_bare_output_format_reference(ctx, at, method);
    }
    let class_count = candidate.class_args.length();
    // A VALUE reference: an own generic nothing solves is reported as the
    // unspecialized value (`GenericFunctionValueNotSpecialized`, which names
    // the fix), not as an uninferred slot.
    let own = function_signature_ty(ctx.db, method).generic_params.map((param) -> {
        fresh_generic_arg(ctx, param)
    });
    let has_own = own.length() > 0;
    let instantiation = candidate.class_args.concat(own);
    // r-a registers required obligations at EVERY value instantiation,
    // whatever the spelling: a method read as a VALUE obligates its own
    // generics' bounds exactly as a call would.
    register_callable_instantiation(ctx, method, instantiation, at);
    if (has_own && !suppressed(ctx, Suppress.MemberProbe)) {
        // The bound value carries its own instantiation: the receiver
        // supplies the owner prefix at run time.
        write_call_type_args(ctx, at, instantiation, class_count);
    }
    (
        bind_receiver(pool, instantiate_callable_signature(ctx.db, method, instantiation)),
        MemberResolutionMethod<int> {
            callee: MethodCalleeInherent { value: method },
            receiver: Receiver.Bound,
        },
    )
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::union_member_access @ d9be6853b
// Member access on a UNION receiver in value position: resolve through the
// single interface every arm shares, or report which of the failure shapes
// applies (no common declarer, ambiguous declarers, `Self`-restricted
// method, conflicting associated types).
function union_member_access(
    ctx: InferenceContext,
    at: int,
    union_ty: int,
    members: int[],
    member: string,
) -> (int, WorkingMemberResolution?) throws never {
    let pool = ctx.table.pool;
    let error = pool.add(root.types.TyError {});
    match (lookup_union_member(ctx.db, viewer(ctx), ctx.facts, union_ty, members, member)) {
        let found: UnionMemberLookupFound => {
            let interface_member = found.value;
            if (reject_selfless_instance_member(ctx, interface_member, member, at)) {
                return (error, null);
            }
            let resolution = declarer_resolution(ctx, interface_member.declarer, member, Receiver.Bound);
            (interface_member_value(ctx, interface_member, at), resolution)
        },
        let conflict: UnionMemberLookupAssociatedTypeConflict => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagUnionAssociatedTypeConflict {
                        expr: at,
                        base: union_ty,
                        member: member,
                        is_method: conflict.is_method,
                        types: conflict.types,
                    },
                );
            }
            (error, null)
        },
        let ambiguous: UnionMemberLookupAmbiguous => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagAmbiguousMember {
                        expr: at,
                        base: union_ty,
                        member: member,
                        sources: ambiguous.sources,
                        is_field: ambiguous.is_field,
                    },
                );
            }
            (error, null)
        },
        let restricted: UnionMemberLookupSelfRestricted => {
            if (!suppressed(ctx, Suppress.MemberProbe)) {
                report(
                    ctx,
                    PendingDiagSelfRestrictedMember {
                        expr: at,
                        interface_: restricted.interface_,
                        member: member,
                        position: restricted.position,
                    },
                );
            }
            (error, null)
        },
        UnionMemberLookupNoCommonInterface => {
            // An unsolved arm contributes no interfaces, so the miss may only
            // mean "not inferred yet": still a permanent `Error`.
            if (!suppressed(ctx, Suppress.MemberProbe) && !pool.has_error(union_ty)) {
                // The report owns the receiver's open classes.
                ctx.table.taint_vars_in(union_ty);
                if (pool.has_infer(union_ty)) {
                    report(ctx, PendingDiagReceiverTypeMustBeKnown { expr: at, member: member });
                } else {
                    report(
                        ctx,
                        PendingDiagUnionNoCommonInterface {
                            expr: at,
                            base: union_ty,
                            member: member,
                        },
                    );
                }
            }
            (error, null)
        },
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::declarer_resolution @ d9be6853b
// The recorded resolution for an interface member's declarer, when one
// applies (the concrete-field backing link is not resolved yet: no entry
// rather than a wrong one).
function declarer_resolution(
    ctx: InferenceContext,
    declarer: MemberDeclarer,
    member: string,
    receiver: Receiver,
) -> WorkingMemberResolution? throws never {
    let pool = ctx.table.pool;
    match (declarer) {
        let field: MemberDeclarerVirtualField => {
            MemberResolutionInterfaceVirtualField<int> {
                interface_: field.interface_,
                view: root.types.infer_interface_existential(pool, field.realized),
                field_index: field.field_index,
                field: member,
            }
        },
        let method: MemberDeclarerVirtualMethod => {
            MemberResolutionMethod<int> {
                callee: MethodCalleeVirtual<int> {
                    interface_: method.interface_,
                    view: root.types.infer_interface_existential(pool, method.realized),
                    method: member,
                },
                receiver: receiver,
            }
        },
        let impl_method: MemberDeclarerImplMethod => {
            MemberResolutionMethod<int> {
                callee: MethodCalleeConcrete<int> {
                    impl_block: impl_method.block,
                    func: impl_method.func,
                    frame_type_args: impl_method.frame_type_args,
                },
                receiver: receiver,
            }
        },
        MemberDeclarerImplField => null,
    }
}

// port: baml_compiler2_hir_ty/src/infer.rs::InferenceContext::constructor_interface_field_link @ d9be6853b
// If `name` is a FIELD declared by an interface this class implements, the
// class field backing it (`field as class_field` link, else the same name).
// Null when no implemented interface declares it. The class's impls are
// enumerated like every other receiver's, through the impl registry.
function constructor_interface_field_link(
    ctx: InferenceContext,
    class_: int,
    name: string,
) -> string? throws never {
    let db = ctx.db;
    let pkg = root.hir.file_package(db, db.class_locs.get(class_).file);
    let pkg_items = root.hir.package_items(db, pkg.root_id);
    let self_ty = class_self_ty(db, class_);
    for (let resolved in impls_for_type(db, pkg.root_id, self_ty)) {
        // Field links are source data (an interface with fields is
        // implemented in-body, so the block is in this compilation).
        let block = root.hir.impl_block_data(db, resolved.facts.block);
        let interface_ = root.hir_ty.interfaces.resolve_ref_to_interface_identity(
            db,
            block.type_refs,
            block.interface_target,
            pkg_items,
            pkg.namespace_path,
        );
        if (interface_ == null) {
            continue;
        }
        let declares = root.hir.interface_data(db, interface_.loc).fields.some((field) -> {
            field.name == name
        });
        if (!declares) {
            continue;
        }
        let link = block.field_links.find((link) -> {
            link.interface_field == name
        });
        return if (link != null) {
            link.class_field
        } else {
            name
        };
    }
    null
}

// port: baml_type/src/type_kind.rs::builtin_companion_of_decl @ d9be6853b
// The builtin companion carrier `name` is (`baml.Int`, `baml.Map`, ...), when
// it is one. Restructured: `ns_types` ports the registry without its
// `Construction`; a `Construction::Builtin` entry is exactly one whose
// target is not `Json`, `Void`, `Never` or `Unknown`, and its `origin` and
// `carries_methods` are listed here by target. `display_name` is the table
// spelling (`array` for the postfix entry), and
// `members_reachable_without_carrier` holds for an arity-0 named spelling
// that is not the carrier's own path (every arity-0 carrier but
// `reflect.Type`).
function builtin_companion_of_decl(
    lang: root.base.LangRoots,
    name: root.types.DeclName,
) -> root.types.BuiltinCompanion? throws never {
    let alias = root.types.compiler_alias_by_definition(lang, name)
        ?? return null;
    let (let builtin, let origin, let carries_methods) = match (alias.target) {
        root.types.AliasTarget.Int => ("int", "literals", true),
        root.types.AliasTarget.Bigint => ("bigint", "literals", true),
        root.types.AliasTarget.Float => ("float", "literals", true),
        root.types.AliasTarget.String => ("string", "literals", true),
        root.types.AliasTarget.Bool => ("bool", "literals", false),
        root.types.AliasTarget.Null => ("null", "the `null` literal", false),
        root.types.AliasTarget.Uint8Array => ("uint8array", "byte-string literals", true),
        root.types.AliasTarget.Image => ("image", "image factory methods", true),
        root.types.AliasTarget.Audio => ("audio", "audio factory methods", true),
        root.types.AliasTarget.Video => ("video", "video factory methods", true),
        root.types.AliasTarget.Pdf => ("pdf", "pdf factory methods", true),
        root.types.AliasTarget.List => ("array", "array literals", true),
        root.types.AliasTarget.Map => ("map", "map literals", true),
        root.types.AliasTarget.Future => ("baml.future.Future", "spawn expressions", true),
        root.types.AliasTarget.Type => {
            ("reflect.Type", "`reflect.Type.of<T>()` and reflection", true)
        },
        root.types.AliasTarget.Json
            | root.types.AliasTarget.Void
            | root.types.AliasTarget.Never
            | root.types.AliasTarget.Unknown =>
        {
            return null;
        },
    };
    let named = alias.target != root.types.AliasTarget.List;
    let definition = alias.definition ?? [];
    root.types.BuiltinCompanion {
        builtin: builtin,
        origin: origin,
        carries_methods: carries_methods,
        members_reachable_without_carrier: named && alias.arity == 0 && definition.join(".") != builtin,
    }
}
