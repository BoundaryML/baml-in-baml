// The `#[derive(PartialOrd, Ord)]` orders the type family's payloads carry,
// which the generated `cmp_<member>` functions (family.baml) compose. A
// derived `Ord` compares an enum by variant declaration order, then fields in
// order; a struct by fields in order; a slice lexicographically; `None` sorts
// before `Some`.

// port: `Ord for [T]` (lexicographic).
function cmp_list<T>(a: T[], b: T[], cmp: (T, T) -> baml.ops.Ordering throws never) -> baml.ops.Ordering throws never {
    let n = if (a.length() < b.length()) { a.length() } else { b.length() };
    for (let i = 0; i < n; i += 1) {
        let o = cmp(a[i], b[i]);
        if (o != baml.ops.Ordering.Equal) {
            return o;
        }
    }
    a.length().cmp(b.length())
}

// port: `Ord for Option<Name>`.
function cmp_optional_string(a: string?, b: string?) -> baml.ops.Ordering throws never {
    if (a == null) {
        if (b == null) { baml.ops.Ordering.Equal } else { baml.ops.Ordering.Less }
    } else if (b == null) {
        baml.ops.Ordering.Greater
    } else {
        a.cmp(b)
    }
}

// port: names.rs::QualifiedTypeName's derived Ord (pkg, namespace, name).
// The package key is a root id; Rust's `SourceRoot` orders by salsa id,
// which is the order roots were created in, as root ids are here.
function cmp_decl_name(a: DeclName, b: DeclName) -> baml.ops.Ordering throws never {
    let by_pkg = a.pkg.cmp(b.pkg);
    if (by_pkg != baml.ops.Ordering.Equal) {
        return by_pkg;
    }
    let by_namespace = cmp_list(a.namespace, b.namespace, (x: string, y: string) -> baml.ops.Ordering { x.cmp(y) });
    if (by_namespace != baml.ops.Ordering.Equal) {
        return by_namespace;
    }
    a.name.cmp(b.name)
}

// port: baml_base core_types.rs::Literal's derived Ord.
function cmp_literal(a: root.base.Literal, b: root.base.Literal) -> baml.ops.Ordering throws never {
    let rank = (l: root.base.Literal) -> int {
        match (l) {
            root.base.LiteralInt => 0,
            root.base.LiteralBigint => 1,
            root.base.LiteralFloat => 2,
            root.base.LiteralString => 3,
            root.base.LiteralBool => 4,
        }
    };
    match ((a, b)) {
        (let x: root.base.LiteralInt, let y: root.base.LiteralInt) => x.value.cmp(y.value),
        (let x: root.base.LiteralBigint, let y: root.base.LiteralBigint) => x.value.cmp(y.value),
        (let x: root.base.LiteralFloat, let y: root.base.LiteralFloat) => x.value.cmp(y.value),
        (let x: root.base.LiteralString, let y: root.base.LiteralString) => x.value.cmp(y.value),
        (let x: root.base.LiteralBool, let y: root.base.LiteralBool) => x.value.cmp(y.value),
        _ => rank(a).cmp(rank(b)),
    }
}

// port: baml_base core_types.rs::MediaKind's derived Ord.
function cmp_media_kind(a: root.base.MediaKind, b: root.base.MediaKind) -> baml.ops.Ordering throws never {
    let rank = (k: root.base.MediaKind) -> int {
        match (k) {
            root.base.MediaKind.Image => 0,
            root.base.MediaKind.Audio => 1,
            root.base.MediaKind.Video => 2,
            root.base.MediaKind.Pdf => 3,
            root.base.MediaKind.Generic => 4,
        }
    };
    rank(a).cmp(rank(b))
}

// port: lib.rs::Freshness's derived Ord.
function cmp_freshness(a: Freshness, b: Freshness) -> baml.ops.Ordering throws never {
    let rank = (f: Freshness) -> int {
        match (f) {
            Freshness.Fresh => 0,
            Freshness.Regular => 1,
        }
    };
    rank(a).cmp(rank(b))
}

// port: lib.rs::FunctionParamMode's derived Ord.
function cmp_function_param_mode(a: FunctionParamMode, b: FunctionParamMode) -> baml.ops.Ordering throws never {
    let rank = (m: FunctionParamMode) -> int {
        match (m) {
            FunctionParamMode.Required => 0,
            FunctionParamMode.Optional => 1,
        }
    };
    rank(a).cmp(rank(b))
}

// port: param.rs::ParamTy's derived Ord (index, name).
function cmp_param_ty(a: ParamTy, b: ParamTy) -> baml.ops.Ordering throws never {
    let by_index = a.index.cmp(b.index);
    if (by_index != baml.ops.Ordering.Equal) {
        return by_index;
    }
    a.name.cmp(b.name)
}
