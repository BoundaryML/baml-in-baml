// Injective string keys for the type family's payloads, which the generated
// `key_<member>` functions (family.baml) compose. Not a Rust item: on the
// BAML VM a class-keyed map lookup costs ~3 us and a string-keyed one well
// under 0.5 us, so hot maps keyed by a type are keyed by its string instead.
// Strings are length-prefixed and lists count-prefixed, so distinct values
// never share a key.

function key_str(s: string) -> string throws never {
    `${s.length()}:${s}`
}

function key_opt_str(s: string?) -> string throws never {
    if (s == null) { "-" } else { key_str(s) }
}

function key_ints(xs: int[]) -> string throws never {
    `${xs.length()}[${xs.join(",")}]`
}

function key_decl_name(d: DeclName) -> string throws never {
    `${d.pkg}/${d.namespace.length()}/${d.namespace.map(key_str).join("")}${key_str(d.name)}`
}

function key_literal(l: root.base.Literal) -> string throws never {
    match (l) {
        let x: root.base.LiteralInt => `i${x.value}`,
        let x: root.base.LiteralBigint => `b${x.value}`,
        let x: root.base.LiteralFloat => `f${key_str(x.value)}`,
        let x: root.base.LiteralString => `s${key_str(x.value)}`,
        let x: root.base.LiteralBool => if (x.value) { "t" } else { "F" },
    }
}

function key_media_kind(k: root.base.MediaKind) -> string throws never {
    match (k) {
        root.base.MediaKind.Image => "I",
        root.base.MediaKind.Audio => "A",
        root.base.MediaKind.Video => "V",
        root.base.MediaKind.Pdf => "P",
        root.base.MediaKind.Generic => "G",
    }
}

function key_freshness(f: Freshness) -> string throws never {
    match (f) {
        Freshness.Fresh => "f",
        Freshness.Regular => "r",
    }
}

function key_function_param_mode(m: FunctionParamMode) -> string throws never {
    match (m) {
        FunctionParamMode.Required => "q",
        FunctionParamMode.Optional => "o",
    }
}

function key_param_ty(p: ParamTy) -> string throws never {
    `${p.index}${key_str(p.name)}`
}
