// Stubs for MIR unit 4 (statements, patterns, catch): every function the unit owns
// (lower.rs 2280-2380 and 11904-15052 (the MIR plan's line numbers)), in namespace `mir`, with its BAML
// signature, and the types those signatures need that the unit's range
// declares. Each function
// panics until the unit ports it; the unit moves the types and functions
// into their files (`lower.baml`, `pretty.baml`, ...) and deletes this file.
//
// Conventions (bib/IDIOMS.md; ir.baml and lower.baml's headers):
// - `LoweringContext` methods are free functions taking `ctx:
//   LoweringContext` first. Methods of a type the unit declares stay
//   methods of its class; a method of a data enum (a union) is a free
//   function `<enum>_<method>`.
// - `Lowered<T>` / `Result<T, MirInternalError>` is `T throws
//   MirInternalError`; such a stub throws `MirInternalError` with its
//   "not ported" message instead of panicking (a stub that only panics
//   would warn that its `throws` is extraneous).
// - Ids (`Local`, `BlockId`, arena ids, locs, `*Ref`s, `SourceRoot`) are
//   `int`s; `Name` is `string`; parameters named after a BAML keyword (or
//   `root`) get `_` (`root_id`).

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_iterable_for_loop @ d9be6853b
function lower_iterable_for_loop(
    ctx: LoweringContext,
    stmt_id: int,
    binding: int,
    collection: int,
    body: int,
    iterable_view: InterfaceTypeView,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_iterable_for_loop: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_dead_for_loop @ d9be6853b
// A `for let` over a collection typed `never`: only the collection
// runs, and the checker types the loop and the code after it as dead.
// The collection need not end its block with a terminator (a call typed
// `never` returns to a successor), so the block ends with an
// unreachable, as `let … else` does. The body is still lowered, in a
// dead block, so every binding it declares gets its local (the tripwire ...
function lower_dead_for_loop(
    ctx: LoweringContext,
    stmt_id: int,
    binding: int,
    collection: int,
    body: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_dead_for_loop: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::declare_dead_pattern_bindings @ d9be6853b
// Declares a local for every binding `pat_id` introduces without
// matching the pattern: for a pattern in dead code whose scrutinee
// never exists (a `for let` over `never`). HIR registered each binding
// against the root pattern and `Self::verify_bindings_recorded`
// expects a local for each, while a projection (a class field, a tuple
// slot) would need a value's type that `never` does not have.
function declare_dead_pattern_bindings(
    ctx: LoweringContext,
    pat_id: int,
    root_id: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    throw MirInternalError { message: "declare_dead_pattern_bindings: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_stmt @ d9be6853b
function lower_stmt(ctx: LoweringContext, stmt_id: int) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_stmt: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::convert_assign_op @ d9be6853b
function convert_assign_op(op: root.ast.AssignOp) -> BinOp throws never {
    baml.sys.panic("convert_assign_op: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_store_place @ d9be6853b
function lower_store_place(ctx: LoweringContext, expr_id: int) -> Place throws MirInternalError {
    throw MirInternalError { message: "lower_store_place: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_lvalue @ d9be6853b
function lower_lvalue(ctx: LoweringContext, expr_id: int) -> Place throws MirInternalError {
    throw MirInternalError { message: "lower_lvalue: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_match @ d9be6853b
function lower_match(
    ctx: LoweringContext,
    expr_id: int,
    scrutinee: int,
    arm_ids: int[],
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_match: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::try_lower_as_switch @ d9be6853b
// Attempt to lower a match or catch as a Switch terminator.
// Returns true if successful, false if the arms aren't switch-eligible.
function try_lower_as_switch(
    ctx: LoweringContext,
    scrutinee: int,
    arms: (int, int, int?)[],
    dest: Place,
    join: int,
    otherwise: SwitchOtherwise,
    pre_created_blocks: int?[]?,
) -> bool throws MirInternalError {
    throw MirInternalError { message: "try_lower_as_switch: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_match_chain @ d9be6853b
function lower_match_chain(
    ctx: LoweringContext,
    scrutinee: int,
    arms: root.ast.MatchArm[],
    dest: Place,
    join: int,
    exhaustive: bool,
    backstop_last_arm: bool,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_match_chain: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_test_can_reject_covered_values @ d9be6853b
// Whether lowering `pat`'s runtime test can *reject a value the static
// coverage proof counted as matched*. TIR's coverage relation is the
// same canonical invariant subtype the emitted tests evaluate, so for
// values with a concrete runtime type the two always agree: with one
// exception: a value whose concrete type the VM cannot reconstruct
// (`value_concrete_ty` is `None`: a compile-time definition object) fails every ...
function pattern_test_can_reject_covered_values(
    ctx: LoweringContext,
    pat_id: int,
) -> bool throws never {
    baml.sys.panic("pattern_test_can_reject_covered_values: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_is_type_branch @ d9be6853b
// Emit an `IsType` check that handles union types by expanding them
// into a chain: try each member, branch to `success` if any matches.
function emit_is_type_branch(
    ctx: LoweringContext,
    scrutinee: int,
    ty: root.types.RuntimeTy,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "emit_is_type_branch: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_is_type_tag_branch @ d9be6853b
// Emit an `IsTypeTag` coarse-tag test + branch (the container arm of a
// match whose scrutinee proves the tag sufficient).
function emit_is_type_tag_branch(
    ctx: LoweringContext,
    scrutinee: int,
    tag: int,
    success: int,
    failure: int,
) -> void throws never {
    baml.sys.panic("emit_is_type_tag_branch: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_tuple_shape_branch @ d9be6853b
function emit_tuple_shape_branch(
    ctx: LoweringContext,
    scrutinee: int,
    arity: int,
    success: int,
    failure: int,
) -> void throws never {
    baml.sys.panic("emit_tuple_shape_branch: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_pattern_template_test @ d9be6853b
// Emit a `match`/`is` pattern test from a pattern-template build.
function emit_pattern_template_test(
    ctx: LoweringContext,
    scrutinee: int,
    template: root.types.TyTemplate?,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "emit_pattern_template_test: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_is_type_template_branch @ d9be6853b
// Emit an `IsType` test + branch for an already-built `TyTemplate`.
function emit_is_type_template_branch(
    ctx: LoweringContext,
    scrutinee: int,
    ty_template: root.types.TyTemplate,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "emit_is_type_template_branch: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_ty_needs_interface_shape_test @ d9be6853b
// Whether `ty` is (or contains, inside a union/optional) an interface view
// whose runtime test must respect type arguments or associated bindings.
// Used to opt only these patterns into the TIR-typed test path, leaving
// non-interface patterns on the unchanged erased fast path.
function tir_ty_needs_interface_shape_test(ty: root.types.Ty) -> bool throws never {
    baml.sys.panic("tir_ty_needs_interface_shape_test: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_is_tir_type_branch @ d9be6853b
function emit_is_tir_type_branch(
    ctx: LoweringContext,
    scrutinee: int,
    ty: root.types.Ty,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "emit_is_tir_type_branch: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_value_eq_branch @ d9be6853b
// Branch on `scrutinee == rhs` (value equality). Used for singleton-typed
// patterns where the type pins a specific value.
function emit_value_eq_branch(
    ctx: LoweringContext,
    scrutinee: int,
    rhs: Operand,
    success: int,
    failure: int,
) -> void throws never {
    baml.sys.panic("emit_value_eq_branch: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_tag_for_ty @ d9be6853b
// The switch key for a type: a primitive kind's fixed tag (INT=0,
// STRING=1, etc.), a class by its declaration, or `None` for types that
// have no tag of their own (unions, generics, etc.).
function type_tag_for_ty(
    ctx: LoweringContext,
    ty: root.types.RuntimeTy,
) -> SwitchKey? throws never {
    baml.sys.panic("type_tag_for_ty: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_contains_structural @ d9be6853b
function pattern_contains_structural(ctx: LoweringContext, pat_id: int) -> bool throws never {
    baml.sys.panic("pattern_contains_structural: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_pattern_fields @ d9be6853b
function class_pattern_fields(
    ctx: LoweringContext,
    pat_id: int,
) -> root.ast.FieldPat[] throws never {
    baml.sys.panic("class_pattern_fields: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_pattern_type_name @ d9be6853b
function class_pattern_type_name(
    ctx: LoweringContext,
    pat_id: int,
) -> root.types.DeclName? throws never {
    baml.sys.panic("class_pattern_type_name: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_pattern_field_ty @ d9be6853b
// The type of `field` in the class a pattern matches, with the pattern's
// class arguments substituted: wherever the class is declared.
function class_pattern_field_ty(
    ctx: LoweringContext,
    pat_id: int,
    field: string,
) -> root.types.RuntimeTy? throws never {
    baml.sys.panic("class_pattern_field_ty: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_class_pattern_field @ d9be6853b
// The local holding `field` of the value a class pattern matched. TIR
// admitted every field of the pattern against its class or interface, so
// a field that cannot be projected is a compiler bug: never a pattern
// that silently fails, or a binding silently left unset.
function project_class_pattern_field(
    ctx: LoweringContext,
    scrutinee: int,
    class_pat_id: int,
    field_pat_id: int,
    field: string,
) -> int throws MirInternalError {
    throw MirInternalError { message: "project_class_pattern_field: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_interface_pattern_field @ d9be6853b
// BEP-044: project a field bound by an *interface* destructure pattern
// (`Animal { name } => …`). The scrutinee's concrete runtime class is not
// known statically, so we can't index a fixed field slot. Instead we reuse
// the interface field-view dispatch (`try_lower_interface_field_access`) ,
// the same code that lowers `iface_value.name`: to read the linked field
// off whichever implementor the value actually is.
function project_interface_pattern_field(
    ctx: LoweringContext,
    scrutinee: int,
    class_pat_id: int,
    field_pat_id: int,
    field: string,
) -> int throws MirInternalError {
    throw MirInternalError { message: "project_interface_pattern_field: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::const_int_local @ d9be6853b
function const_int_local(ctx: LoweringContext, value: int) -> int throws never {
    baml.sys.panic("const_int_local: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::const_usize_int_local @ d9be6853b
function const_usize_int_local(ctx: LoweringContext, value: int) -> int throws never {
    baml.sys.panic("const_usize_int_local: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::array_len_local @ d9be6853b
function array_len_local(ctx: LoweringContext, scrutinee: int) -> int throws never {
    baml.sys.panic("array_len_local: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_array_pattern_length_test @ d9be6853b
function lower_array_pattern_length_test(
    ctx: LoweringContext,
    scrutinee: int,
    has_rest: bool,
    fixed_len: int,
    success: int,
    failure: int,
) -> void throws never {
    baml.sys.panic("lower_array_pattern_length_test: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_array_pattern_element_from_start @ d9be6853b
function project_array_pattern_element_from_start(
    ctx: LoweringContext,
    scrutinee: int,
    elem_pat: int,
    index: int,
) -> int throws MirInternalError {
    throw MirInternalError { message: "project_array_pattern_element_from_start: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_array_pattern_element_from_end @ d9be6853b
function project_array_pattern_element_from_end(
    ctx: LoweringContext,
    scrutinee: int,
    elem_pat: int,
    index_from_end: int,
) -> int throws MirInternalError {
    throw MirInternalError { message: "project_array_pattern_element_from_end: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_array_pattern_element @ d9be6853b
function project_array_pattern_element(
    ctx: LoweringContext,
    scrutinee: int,
    elem_pat: int,
    index_local: int,
) -> int throws MirInternalError {
    throw MirInternalError { message: "project_array_pattern_element: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_array_pattern_rest @ d9be6853b
function project_array_pattern_rest(
    ctx: LoweringContext,
    scrutinee: int,
    rest_pat: int,
    prefix_len: int,
    suffix_len: int,
) -> int throws MirInternalError {
    throw MirInternalError { message: "project_array_pattern_rest: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_pattern_test @ d9be6853b
function lower_pattern_test(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    success: int,
    failure: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_pattern_test: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_pattern_test_with_catch_policy @ d9be6853b
// Catch wildcard filtering follows alternatives and binding wrappers of
// the caught value, but not patterns on its projected fields/elements.
// In particular, `PanicType | _` must still test its named alternative
// when the wildcard rejects a panic.
function lower_pattern_test_with_catch_policy(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    success: int,
    failure: int,
    wildcard_skips_panics: bool,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_pattern_test_with_catch_policy: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_irrefutable_catch_all @ d9be6853b
function is_irrefutable_catch_all(ctx: LoweringContext, pat_id: int) -> bool throws never {
    baml.sys.panic("is_irrefutable_catch_all: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_narrow_type @ d9be6853b
// Type ascription on the pattern, if any. For `let x: T` (where the
// sub-pattern is a `Type`), returns `T`. For `[…]: T` (Array with
// ascription), returns `T`. Returns `None` for everything else
// (including `let x: <non-type-pattern>`).
function pattern_narrow_type(ctx: LoweringContext, pat_id: int) -> root.ast.TypeExpr? throws never {
    baml.sys.panic("pattern_narrow_type: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::bind_pattern @ d9be6853b
// Bind the names `pat_id` introduces, registered under `site`: the
// construct HIR registered them for.
function bind_pattern(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    throw MirInternalError { message: "bind_pattern: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::bind_pattern_inner @ d9be6853b
function bind_pattern_inner(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    root_id: int,
    narrow_root: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    throw MirInternalError { message: "bind_pattern_inner: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::collect_pattern_bindings @ d9be6853b
function collect_pattern_bindings(
    ctx: LoweringContext,
    pat_id: int,
    out: (string, int)[],
) -> void throws never {
    baml.sys.panic("collect_pattern_bindings: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_binds_names @ d9be6853b
function pattern_binds_names(ctx: LoweringContext, pat_id: int) -> bool throws never {
    baml.sys.panic("pattern_binds_names: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::project_tuple_pattern_element @ d9be6853b
function project_tuple_pattern_element(
    ctx: LoweringContext,
    scrutinee: int,
    elem_pat: int,
    index: int,
    arity: int,
) -> int throws MirInternalError {
    throw MirInternalError { message: "project_tuple_pattern_element: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::declare_or_pattern_bindings @ d9be6853b
// Declare every name an or-pattern binds, once, ahead of the
// alternatives that each assign it.
function declare_or_pattern_bindings(
    ctx: LoweringContext,
    pat_id: int,
    root_id: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    throw MirInternalError { message: "declare_or_pattern_bindings: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_or_pattern_assign_existing @ d9be6853b
function lower_or_pattern_assign_existing(
    ctx: LoweringContext,
    scrutinee: int,
    parts: int[],
    root_id: int,
    narrow_root: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_or_pattern_assign_existing: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::assign_pattern_to_existing @ d9be6853b
function assign_pattern_to_existing(
    ctx: LoweringContext,
    scrutinee: int,
    pat_id: int,
    root_id: int,
    narrow_root: int,
    site: root.hir.DefinitionSite,
) -> void throws MirInternalError {
    throw MirInternalError { message: "assign_pattern_to_existing: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::classify_pattern_type_tag @ d9be6853b
// Classify a pattern into type tag value(s) for switch dispatch.
// Classify a pattern as type-tag-eligible and return its tag(s).
function classify_pattern_type_tag(
    ctx: LoweringContext,
    pat_id: int,
    scrutinee_static_ty: root.types.RuntimeTy?,
) -> SwitchKey[]? throws never {
    baml.sys.panic("classify_pattern_type_tag: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ty_to_type_tags_for_switch @ d9be6853b
// `Self::ty_to_type_tags`, additionally requiring every flattened member
// of `ty` to be *tag-sufficient* for a switch keyed on those tags (see
// `switch_member_tag_sufficient`): a coarse tag may only key a jump-table
// arm when it cannot conflate values the scrutinee admits onto the wrong
// arm: `int[]` and `string[]` share the LIST tag, `Foo<int>` and
// `Foo<string>` share `Foo`'s tag, and the tag dedup would silently drop ...
function ty_to_type_tags_for_switch(
    ctx: LoweringContext,
    ty: root.types.RuntimeTy,
    scrutinee_static_ty: root.types.RuntimeTy?,
) -> SwitchKey[]? throws never {
    baml.sys.panic("ty_to_type_tags_for_switch: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ty_to_type_tags @ d9be6853b
// Convert a `RuntimeTy` to the list of switch keys it corresponds to.
// Returns `None` if the type has no simple tag representation.
function ty_to_type_tags(
    ctx: LoweringContext,
    ty: root.types.RuntimeTy,
) -> SwitchKey[]? throws never {
    baml.sys.panic("ty_to_type_tags: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::format_type_tag_name @ d9be6853b
// Format a type tag integer as a human-readable name for switch arm debug metadata.
function format_type_tag_name(tag: int) -> string throws never {
    baml.sys.panic("format_type_tag_name: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_catch @ d9be6853b
function lower_catch(
    ctx: LoweringContext,
    _expr_id: int,
    base: int,
    clause: root.ast.CatchClause,
    dest: Place,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_catch: not ported (U4)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::emit_catch_wildcard_entry @ d9be6853b
// Enter a catch arm that may not receive panics: when `skips_panics`, a
// caught panic branches to `panic_target` and the current block becomes
// the arm's (non-panic) entry. A wildcard arm of a clause that does not
// trap panics is the only arm needing this test: every other arm's
// pattern test already decides panics by type: so one coarse tag
// test is all an error pays for, and the same dispatch serves `catch`, ...
function emit_catch_wildcard_entry(
    ctx: LoweringContext,
    error_local: int,
    skips_panics: bool,
    panic_target: int,
) -> void throws never {
    baml.sys.panic("emit_catch_wildcard_entry: not ported (U4)")
}

// port: baml_compiler2_mir/src/lower.rs::is_union_of_list_types @ d9be6853b
// Whether `ty` is a list type or a union of list types: a list pattern's
// claim that one membership test decides.
function is_union_of_list_types(ty: root.types.Ty) -> bool throws never {
    baml.sys.panic("is_union_of_list_types: not ported (U4)")
}
