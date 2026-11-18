// port: baml_compiler2_hir/src/signature.rs @ d9be6853b
//
// Per-function signature queries. They read the `ItemTree` (full AST data),
// and split the semantic signature from its source map (spans only).

// port: baml_compiler2_hir/src/signature.rs::FunctionSignature @ d9be6853b
// Param names plus unresolved `root.ast.TypeExpr`s. Its span-free successor
// is `function_data` over the `TypeRef` arena.
class FunctionSignature {
    name: string,
    // Parameter names paired with their unresolved type expressions.
    params: SignatureParam[],
    // Return type (null if omitted).
    return_type: SignatureTypeExpr?,
    // Declared throws contract type (null if omitted).
    throws_: SignatureTypeExpr?,
}

// port: baml_compiler2_hir/src/signature.rs::SignatureTypeExpr @ d9be6853b
// A signature's written type, compared including its spans: consumers anchor
// diagnostics on the spans inside it, nested ones included, and
// `root.ast.TypeExpr`'s own equality ignores spans.
// deviation: `new`, `into_type_expr` and `Deref` are not ported (one-line
// wrappers): write `SignatureTypeExpr { value: ty }` and read `.value`.
class SignatureTypeExpr {
    value: root.ast.TypeExpr,

    // port: baml_compiler2_hir/src/signature.rs::impl PartialEq for SignatureTypeExpr @ d9be6853b
    implements baml.ops.Equals {
        function eq(self, other: Self) -> bool throws never {
            self.value == other.value && self.value.spans() == other.value.spans()
        }
    }
}

// port: baml_compiler2_hir/src/signature.rs::SignatureParam @ d9be6853b
class SignatureParam {
    name: string,
    ty: SignatureTypeExpr,
    has_default: bool,
}

// port: baml_compiler2_hir/src/signature.rs::FunctionParameterDefaults @ d9be6853b
class FunctionParameterDefaults {
    // One default-expression reference per parameter, parallel to
    // `FunctionSignature.params`.
    params: DefaultExprRef?[],
    // The definition-local default expression arena and source map.
    defaults: root.ast.FunctionDefaults,

    // port: baml_compiler2_hir/src/signature.rs::FunctionParameterDefaults::param_default @ d9be6853b
    function param_default(self, index: int) -> DefaultExprRef? throws never {
        self.params.at(index)
    }
}

// port: baml_compiler2_hir/src/signature.rs::ElaboratedFunctionSignature @ d9be6853b
// Canonical callable-signature view used by TIR. The top-level throws stays
// optional (inferred from the body). Callback parameter roots (the parameter
// type, or the function type reached through optionality) with an omitted
// throws are opened to a fresh synthetic effect parameter. Every other
// function type keeps `null` here and is rejected in TIR (E0151).
class ElaboratedFunctionSignature {
    name: string,
    user_generic_params: string[],
    synthetic_effect_params: string[],
    params: SignatureParam[],
    return_type: SignatureTypeExpr?,
    throws_: SignatureTypeExpr?,
}

// port: baml_compiler2_hir/src/signature.rs::SignatureSourceMap @ d9be6853b
// Parallel span storage for a signature.
class SignatureSourceMap {
    // One span per parameter, parallel to `FunctionSignature.params`: the
    // whole `name: Type`, which is what a diagnostic underlines.
    param_spans: root.syntax.TextRange[],
    // One span per parameter's NAME token (rename, go-to-definition).
    param_name_spans: root.syntax.TextRange[],
    // One span per parameter's type expression; null when not annotated.
    param_type_spans: root.syntax.TextRange?[],
    // Span of the return type annotation, if present.
    return_type_span: root.syntax.TextRange?,
    // Span of the throws type annotation, if present.
    throws_type_span: root.syntax.TextRange?,
}

// port: baml_compiler2_hir/src/signature.rs::signature_param @ d9be6853b
// One signature parameter; an unannotated one gets a `Missing` type.
function signature_param(p: FunctionParam) -> SignatureParam throws never {
    let type_expr = p.type_expr
        ?? root.ast.TypeExpr {
            kind: root.ast.TypeExprKindMissing {},
            span: root.syntax.TextRange.empty(0),
        };
    SignatureParam {
        name: p.name,
        ty: SignatureTypeExpr { value: type_expr },
        has_default: p.default != null,
    }
}

// port: baml_compiler2_hir/src/signature.rs::function_signature_with_source_map @ d9be6853b
// Reads the `ItemTree` and splits it into the semantic signature and the
// source map.
function function_signature_with_source_map(
    db: Db,
    function_: int,
) -> (FunctionSignature, SignatureSourceMap) throws never {
    let loc = db.function_locs.get(function_);
    let item_tree = file_item_tree(db, loc.file);
    let func_data = item_tree.functions[loc.id];

    let sig = FunctionSignature {
        name: func_data.name,
        params: func_data.params.map((p) -> {
            signature_param(p)
        }),
        return_type: signature_type_expr_opt(func_data.return_type),
        throws_: signature_type_expr_opt(func_data.throws_),
    };

    // Build source map: spans only (separate for early cutoff).
    let source_map = SignatureSourceMap {
        param_spans: func_data.params.map((p) -> {
            p.span
        }),
        param_name_spans: func_data.params.map((p) -> {
            p.name_span
        }),
        param_type_spans: func_data.params.map((p) -> {
            p.type_expr?.span
        }),
        return_type_span: func_data.return_type?.span,
        throws_type_span: func_data.throws_?.span,
    };

    (sig, source_map)
}

// port: baml_compiler2_hir/src/signature.rs::type_expr_for_effect_param @ d9be6853b
function type_expr_for_effect_param(name: string) -> root.ast.TypeExpr throws never {
    root.ast.TypeExpr {
        kind: root.ast.TypeExprKindPath {
            path: root.base.Path.new([name]),
            generic_args: [],
            associated_type_bindings: [],
        },
        span: root.syntax.TextRange.empty(0),
    }
}

// port: baml_compiler2_hir/src/signature.rs::fresh_effect_param_name @ d9be6853b
// The first `__effect_param_<n>` not in `used_names`, which it joins.
function fresh_effect_param_name(used_names: map<string, bool>) -> string throws never {
    let index = 0;
    while (true) {
        let candidate = `__effect_param_${index}`;
        if (!used_names.has(candidate)) {
            used_names[candidate] = true;
            return candidate;
        }
        index += 1;
    }
}

// port: baml_compiler2_hir/src/signature.rs::elaborate_immediate_callback_param @ d9be6853b
function elaborate_immediate_callback_param(
    params: root.ast.FunctionTypeParam[],
    ret: root.ast.TypeExpr,
    effect_param: string,
) -> root.ast.TypeExpr throws never {
    root.ast.TypeExpr {
        kind: root.ast.TypeExprKindFunction {
            params: params,
            ret: ret,
            throws_: type_expr_for_effect_param(effect_param),
        },
        span: root.syntax.TextRange.empty(0),
    }
}

// port: baml_compiler2_hir/src/signature.rs::elaborate_callback_param_root @ d9be6853b
// Open one parameter's callback root to a synthetic effect param. The root is
// the parameter type itself, or the function type reached from it through
// optionality only (`((v: int) -> int)?` and `((v: int) -> int) | null`).
// Every other nesting (list element, map value, a returned function type, a
// callback's own parameter, a union with a non-null arm) is left alone: an
// omitted `throws` there stays an E0151.
function elaborate_callback_param_root(
    ty: root.ast.TypeExpr,
    used_names: map<string, bool>,
    synthetic_effect_params: string[],
) -> root.ast.TypeExpr throws never {
    match (ty.kind) {
        let k: root.ast.TypeExprKindFunction if k.throws_ == null => {
            let effect_param = fresh_effect_param_name(used_names);
            synthetic_effect_params.push(effect_param);
            elaborate_immediate_callback_param(k.params, k.ret, effect_param)
        },
        let k: root.ast.TypeExprKindOptional => {
            let inner = elaborate_callback_param_root(k.inner, used_names, synthetic_effect_params);
            root.ast.TypeExpr {
                kind: root.ast.TypeExprKindOptional { inner: inner },
                span: ty.span,
            }
        },
        // `T | null` is the same type as `T?`, so it opens the same way. A
        // union carrying any other arm is not an optional callback.
        let k: root.ast.TypeExprKindUnion if non_null_variant_count(k.variants) == 1 => {
            let variants = k.variants.map((variant) -> {
                match (variant.kind) {
                    root.ast.TypeExprKindNull => variant,
                    _ => elaborate_callback_param_root(variant, used_names, synthetic_effect_params),
                }
            });
            root.ast.TypeExpr {
                kind: root.ast.TypeExprKindUnion { variants: variants },
                span: ty.span,
            }
        },
        _ => ty,
    }
}

// port: baml_compiler2_hir/src/signature.rs::elaborate_function_signature_parts @ d9be6853b
function elaborate_function_signature_parts(
    name: string,
    user_generic_params: string[],
    reserved_effect_param_names: string[],
    params: SignatureParam[],
    return_type: SignatureTypeExpr?,
    throws_: SignatureTypeExpr?,
) -> ElaboratedFunctionSignature throws never {
    let used_names: map<string, bool> = {};
    for (let used in user_generic_params.concat(reserved_effect_param_names)) {
        used_names[used] = true;
    }

    let synthetic_effect_params: string[] = [];
    let elaborated_params = params.map((param) -> {
        let elaborated = elaborate_callback_param_root(param.ty.value, used_names, synthetic_effect_params);
        SignatureParam {
            name: param.name,
            ty: SignatureTypeExpr { value: elaborated },
            has_default: param.has_default,
        }
    });

    ElaboratedFunctionSignature {
        name: name,
        user_generic_params: user_generic_params,
        synthetic_effect_params: synthetic_effect_params,
        params: elaborated_params,
        return_type: return_type,
        throws_: throws_,
    }
}

// port: baml_compiler2_hir/src/signature.rs::elaborated_function_signature_with_source_map @ d9be6853b
function elaborated_function_signature_with_source_map(
    db: Db,
    function_: int,
) -> (ElaboratedFunctionSignature, SignatureSourceMap) throws never {
    let loc = db.function_locs.get(function_);
    let item_tree = file_item_tree(db, loc.file);
    let func_data = item_tree.functions[loc.id];

    let params = func_data.params.map((p) -> {
        signature_param(p)
    });

    let return_type = signature_type_expr_opt(func_data.return_type);
    let throws_ = signature_type_expr_opt(func_data.throws_);
    let reserved_effect_param_names = item_tree.enclosing_type_generic_params(loc.id).map((param) -> {
        param.name
    });
    let signature = elaborate_function_signature_parts(
        func_data.name,
        func_data.generic_params.map((param) -> {
            param.name
        }),
        reserved_effect_param_names,
        params,
        return_type,
        throws_,
    );

    let source_map = SignatureSourceMap {
        param_spans: func_data.params.map((p) -> {
            p.span
        }),
        param_name_spans: func_data.params.map((p) -> {
            p.name_span
        }),
        param_type_spans: func_data.params.map((p) -> {
            p.type_expr?.span
        }),
        return_type_span: func_data.return_type?.span,
        throws_type_span: func_data.throws_?.span,
    };

    (signature, source_map)
}

// port: baml_compiler2_hir/src/signature.rs::function_signature @ d9be6853b
// Salsa query: semantic function signature. Its written types keep their
// spans (see `SignatureTypeExpr`); span-free consumers use `function_data`.
function function_signature(db: Db, function_: int) -> FunctionSignature throws never {
    db.memo.function_signature.get(function_, () -> {
        function_signature_with_source_map(db, function_).0
    })
}

// port: baml_compiler2_hir/src/signature.rs::function_signature_source_map @ d9be6853b
// Salsa query: function signature source map (spans only).
function function_signature_source_map(db: Db, function_: int) -> SignatureSourceMap throws never {
    db.memo.function_signature_source_map.get(function_, () -> {
        function_signature_with_source_map(db, function_).1
    })
}

// port: baml_compiler2_hir/src/signature.rs::function_parameter_defaults @ d9be6853b
// Salsa query: function parameter default-expression data, separate from
// `FunctionSignature` so a changed default does not invalidate consumers that
// only need the callable shape.
function function_parameter_defaults(
    db: Db,
    function_: int,
) -> FunctionParameterDefaults throws never {
    db.memo.function_parameter_defaults.get(function_, () -> {
        let loc = db.function_locs.get(function_);
        let item_tree = file_item_tree(db, loc.file);
        let func_data = item_tree.functions[loc.id];

        FunctionParameterDefaults {
            params: func_data.params.map((param) -> {
                param.default
            }),
            defaults: func_data.defaults,
        }
    })
}

// port: baml_compiler2_hir/src/signature.rs::elaborated_function_signature @ d9be6853b
// Salsa query: elaborated callable signature used by TIR consumers.
function elaborated_function_signature(
    db: Db,
    function_: int,
) -> ElaboratedFunctionSignature throws never {
    db.memo.elaborated_function_signature.get(function_, () -> {
        elaborated_function_signature_with_source_map(db, function_).0
    })
}

// port: baml_compiler2_hir/src/signature.rs::elaborated_function_signature_source_map @ d9be6853b
// Salsa query: source map for the elaborated callable signature. The
// elaboration rewrites types but not spans, so this parallels
// `function_signature_source_map`.
function elaborated_function_signature_source_map(
    db: Db,
    function_: int,
) -> SignatureSourceMap throws never {
    db.memo.elaborated_function_signature_source_map.get(function_, () -> {
        elaborated_function_signature_with_source_map(db, function_).1
    })
}

// needs foundation: `Option::map(SignatureTypeExpr::new)`.
function signature_type_expr_opt(ty: root.ast.TypeExpr?) -> SignatureTypeExpr? throws never {
    if (ty) {
        SignatureTypeExpr { value: ty }
    } else {
        null
    }
}

// needs foundation: the `.filter(|v| !matches!(v.kind, Null)).count()` guard
// of `elaborate_callback_param_root`'s union arm.
function non_null_variant_count(variants: root.ast.TypeExpr[]) -> int throws never {
    variants
        .filter((variant) -> {
            !(variant.kind is root.ast.TypeExprKindNull)
        })
        .length()
}
