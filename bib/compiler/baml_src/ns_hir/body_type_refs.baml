// port: baml_compiler2_hir/src/body_type_refs.rs @ d9be6853b
//
// Per-body type references: every type expression written inside a body,
// lowered once into a span-free `TypeRefStore` (the body-side analog of the
// per-item stores in `item_data`; bodies own their type refs, consumers see
// ids, never syntax). The collection walks the body's arenas in allocation
// order, so ids are a pure function of body shape. Spans stay in the lockstep
// `BodyTypeRefSourceMap`.
//
// Collected: pattern type ascriptions, array-pattern ascriptions,
// class-destructure generic args and associated bindings, explicit
// expression-position type args, `.as<T>` upcast targets, match scrutinee
// annotations, lambda signature slots, qualified-path halves, and the bounds
// of a `let type T extends ... = ...` binding.
//
// `PatId`, `ExprId` and `StmtId` are `int` indexes into the body's arenas.

// port: baml_compiler2_hir/src/body_type_refs.rs::BodyTypeRefId @ d9be6853b
// Identity of a type reference in a body-owned arena, distinct from a
// declaration `TypeRefId`: converting back to the raw arena index goes
// through the owning `BodyTypeRefs`.
class BodyTypeRefId {
    value: int,
}

// port: baml_compiler2_hir/src/body_type_refs.rs::BodyTypeRefSourceMap @ d9be6853b
// Spans for one body's type-reference arena.
class BodyTypeRefSourceMap {
    value: TypeRefSourceMap,

    // port: baml_compiler2_hir/src/body_type_refs.rs::BodyTypeRefSourceMap::span @ d9be6853b
    function span(self, id: BodyTypeRefId) -> root.syntax.TextRange throws never {
        self.value.span(id.value)
    }
}

// port: baml_compiler2_hir/src/body_type_refs.rs::BodyTypeRefs @ d9be6853b
// All type references written in one body, keyed by the nodes that carry
// them. A missing key means the position had no written annotation.
class BodyTypeRefs {
    store: TypeRefStore,
    // `Pattern::Type` nodes: `let x: T` ascriptions (as the bind's
    // sub-pattern) and bare type patterns in match arms.
    pattern_types: map<int, BodyTypeRefId>,
    // Array-pattern `[...]: T` ascriptions.
    array_ascriptions: map<int, BodyTypeRefId>,
    // Class-destructure generic args (`Box<int> { v }` patterns), in written
    // order. Never empty when present.
    pattern_class_args: map<int, BodyTypeRefId[]>,
    // Destructure-head associated bindings (`Source<Item = int> { v }`
    // patterns), in written order. Never empty when present.
    pattern_assoc_bindings: map<int, (string, BodyTypeRefId)[]>,
    // Explicit expression-position type arguments (`Call`, `GenericApply`,
    // and `Object` constructors), in written order. Never empty when present.
    expr_type_args: map<int, BodyTypeRefId[]>,
    // The written bounds of `let type T extends A & B = ...` bindings, in
    // written order. Never empty when present: an unbounded binding has no
    // entry (its operand is an expression in the body arena).
    stmt_type_binding_bounds: map<int, BodyTypeRefId[]>,
    // Written annotations on match scrutinees (`match (value: T)`).
    match_scrutinee_types: map<int, BodyTypeRefId>,
    // `.as<T>` upcast targets.
    upcast_targets: map<int, BodyTypeRefId>,
    // The two written halves of a `(Base as Interface).item` reference.
    qualified_path_anchors: map<int, QualifiedPathTypeRefs>,
    // Lambda signature slots, keyed by the lambda expression.
    lambda_signatures: map<int, LambdaTypeRefs>,

    // port: baml_compiler2_hir/src/body_type_refs.rs::impl Default for BodyTypeRefs @ d9be6853b
    function default_() -> BodyTypeRefs throws never {
        BodyTypeRefs {
            store: TypeRefStore.default_(),
            pattern_types: {},
            array_ascriptions: {},
            pattern_class_args: {},
            pattern_assoc_bindings: {},
            expr_type_args: {},
            stmt_type_binding_bounds: {},
            match_scrutinee_types: {},
            upcast_targets: {},
            qualified_path_anchors: {},
            lambda_signatures: {},
        }
    }

    // port: baml_compiler2_hir/src/body_type_refs.rs::BodyTypeRefs::raw_id @ d9be6853b
    function raw_id(self, id: BodyTypeRefId) -> int throws never {
        id.value
    }

    // port: baml_compiler2_hir/src/body_type_refs.rs::BodyTypeRefs::diagnostic_id @ d9be6853b
    // Panics when `id` is not in this body's store.
    function diagnostic_id(self, id: int) -> BodyTypeRefId throws never {
        self.store.get(id);
        BodyTypeRefId { value: id }
    }
}

// port: baml_compiler2_hir/src/body_type_refs.rs::QualifiedPathTypeRefs @ d9be6853b
// The written halves of a fully-qualified item reference. Both are always
// present: the parser builds the node only when it saw both.
class QualifiedPathTypeRefs {
    // The `Self` type: `Base` in `(Base as Interface).item`.
    qself: BodyTypeRefId,
    // The interface the item is projected through.
    interface_: BodyTypeRefId,
}

// port: baml_compiler2_hir/src/body_type_refs.rs::LambdaTypeRefs @ d9be6853b
// A lambda's written signature slots, each optional (lambdas may omit any of
// them and rely on expectation-driven inference).
class LambdaTypeRefs {
    // Per declared parameter, in order.
    params: BodyTypeRefId?[],
    return_type: BodyTypeRefId?,
    throws_: BodyTypeRefId?,
}

// port: baml_compiler2_hir/src/body_type_refs.rs::collect_body_type_refs @ d9be6853b
// Lowers every type expression in `body` into one store. Pure; the queries
// below wrap it per body owner. Patterns, then expressions, then statements,
// each in allocation order.
function collect_body_type_refs(
    body: root.ast.ExprBody,
) -> (BodyTypeRefs, BodyTypeRefSourceMap) throws never {
    let builder = TypeRefBuilder.new();
    let refs = BodyTypeRefs.default_();
    collect_pattern_type_refs(body, builder, refs);
    collect_expr_type_refs(body, builder, refs);
    collect_stmt_type_refs(body, builder, refs);
    let (let store, let source_map) = builder.finish();
    refs.store = store;
    (refs, BodyTypeRefSourceMap { value: source_map })
}

// port: baml_compiler2_hir/src/body_type_refs.rs::collect_body_type_refs @ d9be6853b
// (the `body.patterns` walk).
function collect_pattern_type_refs(
    body: root.ast.ExprBody,
    builder: TypeRefBuilder,
    refs: BodyTypeRefs,
) -> void throws never {
    let lower = (ty: root.ast.TypeExpr) -> BodyTypeRefId {
        BodyTypeRefId { value: builder.lower(ty) }
    };
    for (let pat_id = 0; pat_id < body.patterns.length(); pat_id += 1) {
        match (body.patterns[pat_id]) {
            let p: root.ast.PatternType => {
                refs.pattern_types[pat_id] = lower(p.value);
            },
            let p: root.ast.PatternArray => {
                if let ascription: root.ast.TypeExpr = p.ascription {
                    refs.array_ascriptions[pat_id] = lower(ascription);
                }
            },
            let p: root.ast.PatternClass
                if p.generic_args.length() > 0 || p.associated_type_bindings.length() > 0 => {
                if (p.generic_args.length() > 0) {
                    refs.pattern_class_args[pat_id] = p.generic_args.map(lower);
                }
                if (p.associated_type_bindings.length() > 0) {
                    refs.pattern_assoc_bindings[pat_id]
                        = p.associated_type_bindings.map((binding) -> {
                            (binding.name, lower(binding.ty))
                        });
                }
            },
            _ => {},
        }
    }
}

// port: baml_compiler2_hir/src/body_type_refs.rs::collect_body_type_refs @ d9be6853b
// (the `body.exprs` walk).
function collect_expr_type_refs(
    body: root.ast.ExprBody,
    builder: TypeRefBuilder,
    refs: BodyTypeRefs,
) -> void throws never {
    let lower = (ty: root.ast.TypeExpr) -> BodyTypeRefId {
        BodyTypeRefId { value: builder.lower(ty) }
    };
    let lower_opt = (ty: root.ast.TypeExpr?) -> BodyTypeRefId? {
        if (ty) {
            lower(ty)
        } else {
            null
        }
    };
    for (let expr_id = 0; expr_id < body.exprs.length(); expr_id += 1) {
        match (body.exprs[expr_id]) {
            let e: root.ast.ExprCall if e.type_args.length() > 0 => {
                refs.expr_type_args[expr_id] = e.type_args.map(lower);
            },
            let e: root.ast.ExprGenericApply if e.type_args.length() > 0 => {
                refs.expr_type_args[expr_id] = e.type_args.map(lower);
            },
            let e: root.ast.ExprObject if e.type_args.length() > 0 => {
                refs.expr_type_args[expr_id] = e.type_args.map(lower);
            },
            let e: root.ast.ExprUpcast => {
                refs.upcast_targets[expr_id] = lower(e.target);
            },
            let e: root.ast.ExprQualifiedPath => {
                refs.qualified_path_anchors[expr_id]
                    = QualifiedPathTypeRefs {
                        qself: lower(e.qself),
                        interface_: lower(e.interface_),
                    };
            },
            let e: root.ast.ExprLambda => {
                let def = e.value;
                refs.lambda_signatures[expr_id]
                    = LambdaTypeRefs {
                        params: def.params.map((param) -> {
                            lower_opt(param.type_expr)
                        }),
                        return_type: lower_opt(def.return_type),
                        throws_: lower_opt(def.throws_),
                    };
            },
            let e: root.ast.ExprMatch => {
                if let type_id: int = e.scrutinee_type {
                    refs.match_scrutinee_types[expr_id] = lower(body.type_annotations[type_id]);
                }
            },
            _ => {},
        }
    }
}

// port: baml_compiler2_hir/src/body_type_refs.rs::collect_body_type_refs @ d9be6853b
// (the `body.stmts` walk).
function collect_stmt_type_refs(
    body: root.ast.ExprBody,
    builder: TypeRefBuilder,
    refs: BodyTypeRefs,
) -> void throws never {
    for (let stmt_id = 0; stmt_id < body.stmts.length(); stmt_id += 1) {
        if let stmt: root.ast.StmtTypeBinding = body.stmts[stmt_id] {
            if (stmt.bounds.length() > 0) {
                refs.stmt_type_binding_bounds[stmt_id]
                    = stmt.bounds.map((bound) -> {
                        BodyTypeRefId { value: builder.lower(bound) }
                    });
            }
        }
    }
}

// port: baml_compiler2_hir/src/body_type_refs.rs::function_body_type_refs @ d9be6853b
// Per-body type references for a function: every type expression written
// inside the body, lowered once into a span-free store.
function function_body_type_refs(db: Db, function_: int) -> BodyTypeRefs throws never {
    db.memo.function_body_type_refs.get(function_, () -> {
        match (function_body(db, function_)) {
            let b: FunctionBodyExpr => collect_body_type_refs(b.value).0,
            _ => BodyTypeRefs.default_(),
        }
    })
}

// port: baml_compiler2_hir/src/body_type_refs.rs::body_type_ref_spans @ d9be6853b
// The span map for a body's collected type references (the `.1` the tracked
// ref query drops; recomputed on demand).
function body_type_ref_spans(db: Db, owner: BodyOwnerId) -> BodyTypeRefSourceMap? throws never {
    match (owner) {
        let o: BodyOwnerIdFunction => match (function_body(db, o.value)) {
            let b: FunctionBodyExpr => collect_body_type_refs(b.value).1,
            _ => null,
        },
        let o: BodyOwnerIdLet => match (let_body(db, o.value)) {
            let b: LetBodyExpr => collect_body_type_refs(b.value).1,
            LetBodyMissing => null,
        },
        let o: BodyOwnerIdParameterDefaults => {
            collect_body_type_refs(function_parameter_defaults(db, o.value).defaults.exprs).1
        },
    }
}

// port: baml_compiler2_hir/src/body_type_refs.rs::let_body_type_refs @ d9be6853b
// Per-body type references for a top-level let's initializer.
function let_body_type_refs(db: Db, let_binding: int) -> BodyTypeRefs throws never {
    db.memo.let_body_type_refs.get(let_binding, () -> {
        match (let_body(db, let_binding)) {
            let b: LetBodyExpr => collect_body_type_refs(b.value).0,
            LetBodyMissing => BodyTypeRefs.default_(),
        }
    })
}

// port: baml_compiler2_hir/src/body_type_refs.rs::body_type_refs @ d9be6853b
// Per-body type references for any body owner.
function body_type_refs(db: Db, owner: BodyOwnerId) -> BodyTypeRefs throws never {
    match (owner) {
        let o: BodyOwnerIdFunction => function_body_type_refs(db, o.value),
        let o: BodyOwnerIdLet => let_body_type_refs(db, o.value),
        let o: BodyOwnerIdParameterDefaults => parameter_defaults_type_refs(db, o.value),
    }
}

// port: baml_compiler2_hir/src/body_type_refs.rs::parameter_defaults_type_refs @ d9be6853b
// Per-body type references for a function's parameter-default arena.
function parameter_defaults_type_refs(db: Db, function_: int) -> BodyTypeRefs throws never {
    db.memo.parameter_defaults_type_refs.get(function_, () -> {
        let defaults = function_parameter_defaults(db, function_);
        collect_body_type_refs(defaults.defaults.exprs).0
    })
}
