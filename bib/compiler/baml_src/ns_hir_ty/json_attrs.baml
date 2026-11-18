// port: baml_compiler2_hir_ty/src/json_attrs.rs @ d9be6853b
//
// The mistakes `@json` attributes make possible, as compile errors. The
// attributes describe how a class reads and writes JSON, so each of these is
// a class whose JSON would quietly not be what its declaration says: an
// override the attributes never reach, a key held by the wrong field, or a
// union whose members can't be told apart by their tags.
//
// Restructured:
// - `json_overrides` is a `TrackedMemo` on `db.ty_memo`, keyed by root id.
//   Its `&'static str` interface names are `string`s, sorted with
//   `cmp_decl_name`.
// - `override_of` finds the first entry named `head`; Rust's
//   `partition_point` lands on the same entry of the sorted list.
// - `tag_tree`'s `Result` is its throw (json_tags.baml).

// port: baml_compiler2_hir_ty/src/json_attrs.rs::json_overrides @ d9be6853b
// The interface each class or enum in `package` overrides, by its name and
// sorted by it: `baml.ToJson` or `baml.FromJson`, when an impl provides the
// method, for any instantiation. An impl's own package holds it, since the
// type's package or the interface's has to.
function json_overrides(
    db: root.hir.Db,
    package: int,
) -> (root.types.DeclName, string)[] throws never {
    db.ty_memo.json_overrides.get(db.cycles, package, () -> {
        let overrides: (root.types.DeclName, string)[] = [];
        for (let block in package_impl_locs(db, package)) {
            let facts = impl_header_resolution_resolved(impl_facts(db, block));
            if (facts == null) {
                continue;
            }
            let (let interface_, let method) = match (structural_interface(db, facts.interface_.reference.name)) {
                root.types.StructuralInterface.ToJson => ("baml.ToJson", "to_json"),
                root.types.StructuralInterface.FromJson => ("baml.FromJson", "from_json"),
                _ => {
                    continue;
                },
            };
            let provides = facts.methods.some((function_) -> {
                root.hir.function_data(db, function_).name == method
            });
            if (!provides) {
                continue;
            }
            match (db.ty_memo.pool.to_plain_closed(facts.for_ty_pattern.ty)) {
                let c: root.types.TyClass => {
                    overrides.push((c.name, interface_));
                },
                let e: root.types.TyEnum => {
                    overrides.push((e.name, interface_));
                },
                _ => {},
            }
        }
        overrides.sort_by((a, b) -> {
            let by_name = root.types.cmp_decl_name(a.0, b.0);
            if (by_name != baml.ops.Ordering.Equal) {
                by_name
            } else {
                a.1.cmp(b.1)
            }
        })
    })
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::override_of @ d9be6853b
// The interface `head` overrides, in `json_overrides`' list.
function override_of(
    overrides: (root.types.DeclName, string)[],
    head: root.types.DeclName,
) -> string? throws never {
    overrides.find((entry) -> {
        entry.0 == head
    })?.1
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::class_errors @ d9be6853b
// The compile errors of `class_`'s own `@json` attributes, at the field or
// class name they are about.
function class_errors(
    db: root.hir.Db,
    class_: int,
    head: root.types.DeclName,
    overrides: (root.types.DeclName, string)[],
) -> (root.syntax.TextRange, TirTypeError)[] throws never {
    let data = root.hir.class_data(db, class_);
    let source_map = root.hir.class_source_map(db, class_);
    let fields = resolve_class_fields(db, class_);
    let errors: (root.syntax.TextRange, TirTypeError)[] = [];

    let held_rest = false;
    for (let index = 0; index < fields.length(); index += 1) {
        let (let name, let ty, let attrs) = fields[index];
        let span = source_map.field_name_spans[index];
        if (attrs.json_flatten || attrs.json_fallback) {
            if (!is_json_object(db, ty)) {
                errors.push(
                    (
                        span,
                        TirTypeErrorJsonRestFieldType {
                            attribute: rest_attribute(attrs),
                            field: name,
                        },
                    ),
                );
            }
            if (attrs.json_rename != null) {
                errors.push(
                    (
                        span,
                        TirTypeErrorJsonRestRenamed {
                            attribute: rest_attribute(attrs),
                            field: name,
                        },
                    ),
                );
            }
            if (attrs.skip) {
                errors.push((span, TirTypeErrorJsonAttributeSkipped { field: name }));
            }
            if (held_rest || (attrs.json_flatten && attrs.json_fallback)) {
                errors.push((span, TirTypeErrorJsonRestRepeated { class_: data.name }));
            }
            held_rest = true;
        }
    }

    let has_fallback = fields.some((field) -> {
        field.2.json_fallback
    });
    if (has_fallback) {
        let has_tag = false;
        for (let index = 0; index < fields.length(); index += 1) {
            let (let name, let ty, let attrs) = fields[index];
            if (attrs.json_fallback || attrs.json_flatten) {
                continue;
            }
            let span = source_map.field_name_spans[index];
            if (literal_of(db, ty) == null) {
                errors.push(
                    (
                        span,
                        TirTypeErrorJsonFallbackFieldNotLiteral { class_: data.name, field: name },
                    ),
                );
            } else if (attrs.skip) {
                errors.push((span, TirTypeErrorJsonAttributeSkipped { field: name }));
            } else {
                has_tag = true;
            }
        }
        if (!has_tag) {
            errors.push((source_map.name_span, TirTypeErrorJsonFallbackNoTag { class_: data.name }));
        }
    }

    let uses_attributes = data.attrs.json_omit_nulls
        || fields.some((field) -> {
            field.2.json_rename != null || field.2.json_flatten || field.2.json_fallback
        });
    if (uses_attributes) {
        let interface_ = override_of(overrides, head);
        if (interface_ != null) {
            errors.push(
                (
                    source_map.name_span,
                    TirTypeErrorJsonAttributesWithOverride {
                        name: data.name,
                        interface_: interface_,
                    },
                ),
            );
        }
    }
    errors
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::rest_attribute @ d9be6853b
function rest_attribute(attrs: root.hir.ClassFieldAttrs) -> string throws never {
    if (attrs.json_fallback) {
        "@json.fallback"
    } else {
        "@json.flatten"
    }
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::resolved @ d9be6853b
// `ty`, or the type an alias of it resolves to.
function resolved(db: root.hir.Db, ty: root.types.Ty) -> root.types.Ty throws never {
    let seen: root.types.DeclName[] = [];
    let current = ty;
    while let alias_ty: root.types.TyTypeAlias = current {
        let head = alias_ty.name;
        if (is_json_alias(db, head) || seen.includes(head)) {
            break;
        }
        let alias = alias_ref_of(db, head)
            ?? return current;
        seen.push(head);
        current = alias_value(db, alias);
    }
    current
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::is_json_object @ d9be6853b
// Whether `ty` is `map<string, json>`, through any aliases.
function is_json_object(db: root.hir.Db, ty: root.types.Ty) -> bool throws never {
    match (resolved(db, ty)) {
        let m: root.types.TyMap => {
            resolved(db, m.key) is root.types.TyString && is_json(db, resolved(db, m.value))
        },
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::is_json @ d9be6853b
function is_json(db: root.hir.Db, ty: root.types.Ty) -> bool throws never {
    match (ty) {
        let a: root.types.TyTypeAlias => is_json_alias(db, a.name),
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::literal_of @ d9be6853b
// The literal `ty` is, through any aliases.
function literal_of(db: root.hir.Db, ty: root.types.Ty) -> root.base.Literal? throws never {
    match (resolved(db, ty)) {
        let l: root.types.TyLiteral => l.value,
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::is_optional @ d9be6853b
// Whether a field of type `ty` is optional: its type has a `null` arm, or it
// names an alias that resolves to one. `json` holds `null` as a value.
function is_optional(db: root.hir.Db, ty: root.types.Ty) -> bool throws never {
    match (resolved(db, ty)) {
        let u: root.types.TyUnion => {
            u.members.some((member) -> {
                member is root.types.TyNull
            })
        },
        _ => false,
    }
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::union_error @ d9be6853b
// The first union in `ty` that can't pick a member by tag: it has a
// `@json.fallback` member, and a member the tags can't tell apart.
function union_error(db: root.hir.Db, ty: root.types.Ty) -> TirTypeError? throws never {
    let first_of = (tys: root.types.Ty[]) -> TirTypeError? {
        for (let inner in tys) {
            let error = union_error(db, inner);
            if (error != null) {
                return error;
            }
        }
        null
    };
    match (ty) {
        let u: root.types.TyUnion => {
            let flat: root.types.Ty[] = [];
            members_of(db, ty, [], flat);
            fallback_union_error(db, flat) ?? first_of(u.members)
        },
        let l: root.types.TyList => union_error(db, l.elem),
        let m: root.types.TyMap => union_error(db, m.value),
        let c: root.types.TyClass => first_of(c.args),
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::members_of @ d9be6853b
// The non-alias members of `ty`, unions flattened. `json` stays one member.
function members_of(
    db: root.hir.Db,
    ty: root.types.Ty,
    unfolding: root.types.DeclName[],
    out: root.types.Ty[],
) -> void throws never {
    match (ty) {
        let u: root.types.TyUnion => {
            for (let member in u.members) {
                members_of(db, member, unfolding, out);
            }
        },
        let a: root.types.TyTypeAlias if !is_json(db, ty) => {
            if (unfolding.includes(a.name)) {
                return;
            }
            let alias = alias_ref_of(db, a.name);
            if (alias != null) {
                unfolding.push(a.name);
                members_of(db, alias_value(db, alias), unfolding, out);
                unfolding.pop();
            }
        },
        _ => {
            out.push(ty);
        },
    }
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::source_fields @ d9be6853b
// The class `head` names, with what the union check needs to know about it:
// a class from another package is taken at its word.
function source_fields(
    db: root.hir.Db,
    head: root.types.DeclName,
) -> (string, root.types.Ty, root.hir.ClassFieldAttrs)[]? throws never {
    match (class_ref_of(db, head)) {
        let r: root.hir.DeclRefSource<int> => resolve_class_fields(db, r.value),
        _ => null,
    }
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::literals @ d9be6853b
// Each literal field among `fields`, by its JSON key under declared or
// aliased names.
function literals(
    db: root.hir.Db,
    fields: (string, root.types.Ty, root.hir.ClassFieldAttrs)[],
    aliased: bool,
) -> (string, root.base.Literal)[] throws never {
    fields.filter_map((field) -> (string, root.base.Literal)? {
        let (let name, let ty, let attrs) = field;
        if (attrs.skip) {
            return null;
        }
        let alias = if (aliased) {
            attrs.schema.alias
        } else {
            null
        };
        let key = attrs.json_rename ?? alias ?? name;
        let literal = literal_of(db, ty)
            ?? return null;
        (key, literal)
    })
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::fallback_union_error @ d9be6853b
// Why the union of `members` can't pick by tag, under either naming:
// `baml.json` reads aliased names when a call asks it to.
function fallback_union_error(
    db: root.hir.Db,
    members: root.types.Ty[],
) -> TirTypeError? throws never {
    tag_error(db, members, false) ?? tag_error(db, members, true)
}

// port: baml_compiler2_hir_ty/src/json_attrs.rs::tag_error @ d9be6853b
function tag_error(
    db: root.hir.Db,
    members: root.types.Ty[],
    aliased: bool,
) -> TirTypeError? throws never {
    let fallback: (root.types.DeclName, (string, root.base.Literal)[])? = null;
    let tagged: (root.types.Ty, (string, root.base.Literal)[])[] = [];
    let untagged: root.types.Ty[] = [];
    for (let member in members) {
        match (member) {
            let c: root.types.TyClass => {
                // A class this check can't see is taken at its word.
                let fields = source_fields(db, c.name);
                if (fields == null) {
                    continue;
                }
                let is_fallback = fields.some((field) -> {
                    field.2.json_fallback
                });
                if (is_fallback && fallback == null) {
                    fallback = (c.name, literals(db, fields, aliased));
                } else if (is_fallback) {
                    untagged.push(member);
                } else {
                    tagged.push((member, literals(db, fields, aliased)));
                }
            },
            // Each reads any object, with nothing to match on.
            root.types.TyMap
                | root.types.TyUnknown
                | root.types.TyInterface
                | root.types.TyMedia
                | root.types.TyTypeVar =>
            {
                untagged.push(member);
            },
            _ if is_json(db, member) => {
                untagged.push(member);
            },
            _ => {},
        }
    }
    let (let head, let tags) = fallback
        ?? return null;
    let name = head.name;
    let first_untagged = untagged.at(0);
    if (first_untagged != null) {
        return TirTypeErrorJsonFallbackUntaggedMember { fallback: name, member: first_untagged };
    }
    let literal_sets = tagged.map((entry) -> {
        entry.1
    });
    {
        root.types.tag_tree(literal_sets, tags);
        null
    } catch (e) {
        root.types.UntaggedNoTag => null,
        let m: root.types.UntaggedMember => {
            TirTypeErrorJsonFallbackUntaggedMember { fallback: name, member: tagged[m.value].0 }
        },
        let o: root.types.UntaggedOverlap => {
            TirTypeErrorJsonFallbackOverlap { first: tagged[o.first].0, second: tagged[o.second].0 }
        },
    }
}
