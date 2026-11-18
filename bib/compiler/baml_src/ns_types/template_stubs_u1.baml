// Stubs added by MIR unit 1 for items of `baml_type` (and its neighbours
// `baml_type_runtime` and `baml_base`) that MIR needs and `root.types` does
// not port yet. Each panics until unit U7 ports it into its home; this file
// is deleted at merge. Rust signatures; methods are free functions
// `<type>_<method>`.

// port: baml_type/src/runtime_ty.rs::ResolvedAliases::convert @ d9be6853b
// Home: `root.types` (runtime_ty.baml, with `lower_to_runtime`). A
// compile-time type as the runtime carries it: non-recursive aliases
// expanded, every head kept; panics on an error-recovery type.
function resolved_aliases_convert(aliases: ResolvedAliases, ty: Ty) -> RuntimeTy throws never {
    baml.sys.panic("ResolvedAliases::convert: not ported (U7)")
}

// port: baml_type_runtime/src/lib.rs::erase_typevars_matching @ d9be6853b
// Home: baml_type_runtime (no namespace yet). Replace the type variables
// `should_erase` selects with `unknown`.
function erase_typevars_matching(
    ty: Ty,
    should_erase: (ParamTy) -> bool throws never,
) -> Ty throws never {
    baml.sys.panic("erase_typevars_matching: not ported (U7)")
}

// port: baml_type/src/template.rs::TyTemplate::substitute_symbolic @ d9be6853b
// Home: `root.types` (template.rs). Resolve each frame reference against
// `type_args`, leaving every unresolved position symbolic.
function ty_template_substitute_symbolic(
    template: TyTemplate,
    type_args: RuntimeTy[],
) -> RuntimeTy throws never {
    baml.sys.panic("TyTemplate::substitute_symbolic: not ported (U7)")
}

// port: baml_base/src/lang.rs::native_key_spelling @ d9be6853b
// Home: `root.base` (lang.baml). A written type spelled for a native key: a
// written `root.` at a path start becomes `package.`.
function native_key_spelling(package: string, written: string) -> string throws never {
    baml.sys.panic("native_key_spelling: not ported (U7)")
}
