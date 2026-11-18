// Stubs for MIR unit 1 (context, names, pretty, entries): every function the unit owns
// (lower.rs 105-1681, 1918-2279, 2539-3275, 4317-4529 and 15053-15318 (the MIR plan's line numbers), and pretty.rs), in namespace `mir`, with its BAML
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
// - `resolved_aliases_for_package` and `lower_function` are memoized in
//   `db.mir_memo` (db.baml); `lower_function` reads
//   `db.mir_memo.lower_function_memo(opt)`, whose value is
//   `MirFunction | MirInternalError`, and rethrows the error.
// - pretty.rs writes into `string[]` (Rust's `&mut impl Write`); its
//   `fmt::Result` returns are `void`.
// - pretty.rs's `Names::ty` / `template` / `interface` return Rust's
//   display-headed instantiation (`baml_type::RuntimeTy<TypeName>`), which
//   the monomorphic `root.types` family cannot spell; the stubs say
//   `DeclName`-headed types, and the unit chooses (rendering straight to a
//   string keeps the output).
// - lower.rs's tests (`indirect_call_layout_tests`) belong to this unit.

// port: baml_compiler2_mir/src/lower.rs::PackageAliases @ d9be6853b
// A package's memoized alias environment (`resolved_aliases_for_package`).
// Rust's `Deref` to the `ResolvedAliases` is the field `value`.
class PackageAliases {
    value: root.types.ResolvedAliases,
}

// port: baml_compiler2_mir/src/lower.rs::PrimitiveRendering @ d9be6853b
enum PrimitiveRendering {
    Itself,
    Formatted,
}

// port: baml_compiler2_mir/src/lower.rs::TemplateMode @ d9be6853b
enum TemplateMode {
    Value,
    Pattern,
}

// port: baml_compiler2_mir/src/lower.rs::RuntimeLowering @ d9be6853b
// The crossing from this program's compile-time types to the wire.
class RuntimeLowering {
    aliases: root.types.ResolvedAliases,
    db: root.hir.Db,

    // port: baml_compiler2_mir/src/lower.rs::RuntimeLowering::of @ d9be6853b
    // The crossing for `root`'s declarations: its memoized alias
    // environment.
    function of(db: root.hir.Db, root_id: int) -> RuntimeLowering throws never {
        baml.sys.panic("RuntimeLowering::of: not ported (U1)")
    }

    // port: baml_compiler2_mir/src/lower.rs::RuntimeLowering::convert @ d9be6853b
    // A compile-time type as MIR carries it: aliases expanded, every head
    // still the declaration's identity.
    function convert(self, ty: root.types.Ty) -> root.types.RuntimeTy throws never {
        baml.sys.panic("RuntimeLowering::convert: not ported (U1)")
    }

    // port: baml_compiler2_mir/src/lower.rs::RuntimeLowering::wire @ d9be6853b
    // A compile-time head rendered canonically, packed into a wire name for
    // printers that take one (`Viewpoint::wire_head`): what operand
    // metadata and a dump say. Never an identity: nothing resolves a
    // declaration from it.
    function wire(self, decl: root.types.DeclName) -> root.types.TypeName throws never {
        baml.sys.panic("RuntimeLowering::wire: not ported (U1)")
    }
}

// port: baml_compiler2_mir/src/lower.rs::MatchScrutinee @ d9be6853b
// The value an enclosing `match` scrutinizes, for the coarse-tag proofs.
class MatchScrutinee {
    // The local the match evaluated its scrutinee into, then each snapshot a
    // narrowing arm copies it into and tests in its place.
    locals: int[],
    // The scrutinee's resolved static type.
    ty: root.types.RuntimeTy,

    // port: baml_compiler2_mir/src/lower.rs::MatchScrutinee::new @ d9be6853b
    function new(local: int, ty: root.types.RuntimeTy) -> MatchScrutinee throws never {
        baml.sys.panic("MatchScrutinee::new: not ported (U1)")
    }

    // port: baml_compiler2_mir/src/lower.rs::MatchScrutinee::ty_held_by @ d9be6853b
    // The scrutinee's static type when `local` holds the scrutinee.
    function ty_held_by(self, local: int) -> root.types.RuntimeTy? throws never {
        baml.sys.panic("MatchScrutinee::ty_held_by: not ported (U1)")
    }

    // port: baml_compiler2_mir/src/lower.rs::MatchScrutinee::record_copy @ d9be6853b
    // Records that `copy` was assigned a copy of `source`: if `source` holds
    // the scrutinee, so does `copy`.
    function record_copy(self, source: int, copy: int) -> void throws never {
        baml.sys.panic("MatchScrutinee::record_copy: not ported (U1)")
    }
}

// port: baml_compiler2_mir/src/lower.rs::TagConflatedShape @ d9be6853b
enum TagConflatedShape {
    List,
    Map,
    Future,
}

// port: baml_compiler2_mir/src/lower.rs::BodyPackageSpelling @ d9be6853b
class BodyPackageSpelling {
    db: root.hir.Db,
    body_root: int,

    // port: baml_compiler2_mir/src/lower.rs::impl TyRenderStrategy for BodyPackageSpelling @ d9be6853b
    implements root.types.TyRenderStrategy {
        // port: baml_compiler2_mir/src/lower.rs::BodyPackageSpelling::qtn @ d9be6853b
        function qtn(self, qtn: root.types.DeclName) -> string throws never {
            baml.sys.panic("BodyPackageSpelling::qtn: not ported (U1)")
        }

        // port: baml_compiler2_mir/src/lower.rs::BodyPackageSpelling::type_var @ d9be6853b
        function type_var(self, name: string) -> string throws never {
            baml.sys.panic("BodyPackageSpelling::type_var: not ported (U1)")
        }
    }
}

// port: baml_compiler2_mir/src/lower.rs::InterfaceTypeView @ d9be6853b
// An interface view: head, generic arguments, associated-type bindings.
type InterfaceTypeView = (root.types.DeclName, root.types.Ty[], (string, root.types.Ty)[]);

// port: baml_compiler2_mir/src/lower.rs::InterfaceMember @ d9be6853b
// What a member name means in an interface view, resolved by one walk of the
// view and its `requires` closure.
type InterfaceMember = InterfaceMemberMethod | InterfaceMemberField | InterfaceMemberUndeclared;

class InterfaceMemberMethod {
    declaring: InterfaceTypeView,
}

class InterfaceMemberField {
    declaring: InterfaceTypeView,
    index: int,
}

class InterfaceMemberUndeclared {
}

// port: baml_compiler2_mir/src/lower.rs::InterfaceMethodShape @ d9be6853b
// How an interface method's frame divides.
class InterfaceMethodShape {
    takes_self: bool,
    dispatch_param: int?,
    interface_generics: int,
    own_start: int,
    frame_len: int,
}

// port: baml_compiler2_mir/src/lower.rs::VirtualFieldTarget @ d9be6853b
// A virtual field access resolved down to what the instruction carries.
class VirtualFieldTarget {
    receiver: int,
    field: string,
    iface: root.types.TyTemplateInterfaceConstraint,
    field_index: int,
}

// port: baml_compiler2_mir/src/lower.rs::LoweredLetBody @ d9be6853b
// A `let` initializer's body with the lambdas lowered inside it.
type LoweredLetBody = (MirFunctionBody, MirFunction[]);

// port: baml_compiler2_mir/src/pretty.rs::Names @ d9be6853b
// Rust's tuple struct `Names(Viewpoint)`: the payload is `value`.
class Names {
    value: root.hir_ty.Viewpoint,

    // port: baml_compiler2_mir/src/pretty.rs::Names::of @ d9be6853b
    function of(db: root.hir.Db) -> Names throws never {
        baml.sys.panic("Names::of: not ported (U1)")
    }

    // port: baml_compiler2_mir/src/pretty.rs::Names::ty @ d9be6853b
    function ty(self, ty: root.types.RuntimeTy) -> root.types.RuntimeTy throws never {
        baml.sys.panic("Names::ty: not ported (U1)")
    }

    // port: baml_compiler2_mir/src/pretty.rs::Names::template @ d9be6853b
    function template(self, template: root.types.TyTemplate) -> root.types.TyTemplate throws never {
        baml.sys.panic("Names::template: not ported (U1)")
    }

    // port: baml_compiler2_mir/src/pretty.rs::Names::templates @ d9be6853b
    function templates(self, templates: root.types.TyTemplate[]) -> string throws never {
        baml.sys.panic("Names::templates: not ported (U1)")
    }

    // port: baml_compiler2_mir/src/pretty.rs::Names::interface @ d9be6853b
    function interface(
        self,
        interface_: root.types.TyTemplateInterfaceConstraint,
    ) -> root.types.TyTemplateInterfaceConstraint throws never {
        baml.sys.panic("Names::interface: not ported (U1)")
    }
}

// port: baml_compiler2_mir/src/lower.rs::resolved_aliases_for_package @ d9be6853b
// Build the `ResolvedAliases` type-alias environment for a package: every
// alias visible to it (its own plus its dependency closure's), whichever lane
// each package is served from: `hir_ty`'s one alias environment
// (`interfaces::package_resolved_aliases`). The pure erasure that consumes it
// lives in `baml_type` (`ResolvedAliases::convert`), wrapped compiler-side
// by `convert_tir_ty_for_runtime`; only this db-querying constructor stays ...
function resolved_aliases_for_package(db: root.hir.Db, pkg_id: int) -> PackageAliases throws never {
    baml.sys.panic("resolved_aliases_for_package: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::lower_ty_with_bindings @ d9be6853b
// Lower a type expression, treating the `bindings` map's keys as the in-scope type variables,
// then substitute those bindings. Threads the in-scope typevar `bounds` so a `T.member`
// projection resolves through `T`'s bound rather than erasing to `unknown`. Replaces the
// removed `lower_type_expr_with_generics` (a bare lower-then-substitute that dropped bounds);
// `bounds` is required, so bound-erasure is unrepresentable at the call sites.
function lower_ty_with_bindings(
    db: root.hir.Db,
    expr: root.ast.TypeExpr,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    bindings: map<root.types.ParamTy, root.types.Ty>,
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
) -> root.types.Ty throws never {
    baml.sys.panic("lower_ty_with_bindings: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::lower_ref_with_bindings @ d9be6853b
// The `TypeRef`-arena twin of `lower_ty_with_bindings`, for callers holding
// firewall data (`*_data(…).type_refs` + a `TypeRefId`) rather than an AST node.
// Identical behavior: lowers through `lower_type_ref` instead of `lower_type_expr`.
function lower_ref_with_bindings(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    id: int,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    bindings: map<root.types.ParamTy, root.types.Ty>,
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
) -> root.types.Ty throws never {
    baml.sys.panic("lower_ref_with_bindings: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::lower_ref_in_scope @ d9be6853b
// The IN-SCOPE twins of the binding wrappers above: explicit frame, no
// substitution - the same `hir_ty` road for sites that keep their type
// variables rigid (turbofish args, annotations, dispatch targets).
function lower_ref_in_scope(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    id: int,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    generic_params: root.types.ParamTy[],
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    self_ty: root.types.Ty?,
) -> root.types.Ty throws never {
    baml.sys.panic("lower_ref_in_scope: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::lower_ref_in_scope_at @ d9be6853b
// `lower_ref_in_scope` at an explicit position - for `implements` /
// dispatch targets, which are constraint heads (written pins only, no
// existential completeness demands).
function lower_ref_in_scope_at(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    id: int,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    generic_params: root.types.ParamTy[],
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    self_ty: root.types.Ty?,
    position: root.hir_ty.TypePosition,
) -> root.types.Ty throws never {
    baml.sys.panic("lower_ref_in_scope_at: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::lower_expr_in_scope @ d9be6853b
// The AST twin of `lower_ref_in_scope` (scratch firewall store).
function lower_expr_in_scope(
    db: root.hir.Db,
    expr: root.ast.TypeExpr,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    generic_params: root.types.ParamTy[],
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
    self_ty: root.types.Ty?,
) -> root.types.Ty throws never {
    baml.sys.panic("lower_expr_in_scope: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::widen_literal_bases @ d9be6853b
// Literals widened to their bases REGARDLESS of freshness - impl
// dispatch is by base type (`hir_ty`'s operand-dispatch discipline; a
// `"x"`-typed receiver IS a string at runtime).
function widen_literal_bases(ty: root.types.Ty) -> root.types.Ty throws never {
    baml.sys.panic("widen_literal_bases: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::primitive_rendering @ d9be6853b
// The `PrimitiveRendering` of every value of checked type `ty`, or `None`
// when `ty` admits a value that is not a primitive, or a union mixes the two
// renderings.
function primitive_rendering(ty: root.types.Ty) -> PrimitiveRendering? throws never {
    baml.sys.panic("primitive_rendering: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::resolve_ref_to_interface_loc @ d9be6853b
// Resolve a written interface reference to its declaration: the `hir_ty`
// lowering road (written pins only) plus the facts definition lookup.
function resolve_ref_to_interface_loc(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    target: int,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
) -> int? throws never {
    baml.sys.panic("resolve_ref_to_interface_loc: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::qualify_def @ d9be6853b
// A definition's head: its declaring file's package and namespace plus
// the short name.
function qualify_def(
    db: root.hir.Db,
    def: root.hir.Definition,
    name: string,
) -> root.types.DeclName throws never {
    baml.sys.panic("qualify_def: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::plain_interface_ty @ d9be6853b
// An interned interface bound as the plain interface TYPE - the
// dispatch view MIR's per-param bound map holds.
function plain_interface_ty(bound: root.types.InterfaceConstraint) -> root.types.Ty throws never {
    baml.sys.panic("plain_interface_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::tir_contains_projection @ d9be6853b
// Whether `ty` contains an associated-type projection node at any depth.
function tir_contains_projection(ty: root.types.Ty) -> bool throws never {
    baml.sys.panic("tir_contains_projection: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::tir_contains_symbolic @ d9be6853b
// Whether `ty` contains any symbolic node: a type variable or an
// associated-type projection: that has no realized runtime form and must be
// lowered through the structured template arms.
function tir_contains_symbolic(ty: root.types.Ty) -> bool throws never {
    baml.sys.panic("tir_contains_symbolic: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::lower_tir_template @ d9be6853b
function lower_tir_template(
    ty: root.types.Ty,
    resolved: RuntimeLowering,
    generic_layout: root.types.RuntimeGenericLayout,
    mode: TemplateMode,
) -> root.types.TyTemplate? throws never {
    baml.sys.panic("lower_tir_template: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::is_slotless_effect_param @ d9be6853b
// Whether `param` is a synthetic effect parameter, which has no frame slot
// by ABI and is erased wherever a template needs a slot. Synthetic effect
// parameters are still told apart by their name, so a block-scoped
// `type __effect_param_0 = …`: a user binding that always has a slot: is
// excluded by its identity, not its spelling.
function is_slotless_effect_param(param: root.types.ParamTy) -> bool throws never {
    baml.sys.panic("is_slotless_effect_param: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::tir2_to_template @ d9be6853b
// Convert a `Tir2Ty` to `TyTemplate`, mapping each type variable to its
// canonical runtime frame index.
function tir2_to_template(
    ty: root.types.Ty,
    resolved: RuntimeLowering,
    generic_params: root.types.ParamTy[],
) -> root.types.TyTemplate throws never {
    baml.sys.panic("tir2_to_template: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::tir2_interface_to_template @ d9be6853b
// Lower a realized interface **constraint** to its template form: each generic
// argument and associated binding lowered individually, so an argument that is an
// enclosing generic becomes a `TypeArgRef` and reaches the runtime resolver
// realized against the caller's frame.
function tir2_interface_to_template(
    name: root.types.DeclName,
    args: root.types.Ty[],
    assoc: (string, root.types.Ty)[],
    resolved: RuntimeLowering,
    generic_params: root.types.ParamTy[],
) -> root.types.TyTemplateInterfaceConstraint throws never {
    baml.sys.panic("tir2_interface_to_template: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::realized_leaf_template @ d9be6853b
// A resolved `RuntimeTy` with no residual type variables, as a leaf template:
// it narrows to a `RealizedTy` (proving realizedness) and widens into a
// `Concrete`-equivalent `TyTemplate`. Panics if the type still contains a type
// variable: callers guarantee realizedness (see the `tir_contains_symbolic`
// gate), so a failure is a compiler invariant violation, not silent erasure.
function realized_leaf_template(ty: root.types.RuntimeTy) -> root.types.TyTemplate throws never {
    baml.sys.panic("realized_leaf_template: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::runtime_ty_is_int_only @ d9be6853b
// Whether every value of `ty` is a raw `int`: the precondition an integer
// `Switch` reads its discriminant under.
function runtime_ty_is_int_only(ty: root.types.RuntimeTy) -> bool throws never {
    baml.sys.panic("runtime_ty_is_int_only: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::runtime_ty_is_enum_only @ d9be6853b
// Whether every value admitted by `ty` has an enum discriminant belonging to
// `enum_name`. Nullable and mixed-enum scrutinees must use the comparison
// chain so non-matching values can reach a wildcard arm.
function runtime_ty_is_enum_only(
    ty: root.types.RuntimeTy,
    enum_name: root.types.DeclName,
) -> bool throws never {
    baml.sys.panic("runtime_ty_is_enum_only: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::tir2_to_pattern_template @ d9be6853b
// Convert a TIR pattern type into a complete `TyTemplate`, failing closed
// when a type variable has no runtime frame slot.
function tir2_to_pattern_template(
    ty: root.types.Ty,
    resolved: RuntimeLowering,
    generic_params: root.types.ParamTy[],
) -> root.types.TyTemplate? throws never {
    baml.sys.panic("tir2_to_pattern_template: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::ty_to_pattern_template_from_resolved_ty @ d9be6853b
// Convert an already-resolved `baml_type::RuntimeTy` into a complete
// `TyTemplate`, or `None` when any position is unresolvable.
function ty_to_pattern_template_from_resolved_ty(
    ty: root.types.RuntimeTy,
) -> root.types.TyTemplate? throws never {
    baml.sys.panic("ty_to_pattern_template_from_resolved_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::flatten_runtime_union @ d9be6853b
// Flatten a `RuntimeTy` union into its leaf members (recursively), pushing each
// non-union leaf into `out`. A recursive alias is kept as a single `TypeAlias`
// leaf: it is not expanded: matching `ResolvedAliases::convert`.
function flatten_runtime_union(
    ty: root.types.RuntimeTy,
    out: root.types.RuntimeTy[],
) -> void throws never {
    baml.sys.panic("flatten_runtime_union: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::member_is_opaque_for_tag_proof @ d9be6853b
// A scrutinee member is *opaque* for a coarse-tag soundness proof when it could
// dynamically resolve to a container or class instantiation its static type
// does not reveal: a type alias (`json` keeps its `json[]`/`map` arms hidden
// behind an opaque leaf), a type variable, `unknown`, an interface (a container
// or class may implement it), or an associated projection. A coarse
// type-tag test can never be *proven* equivalent to the structural test against ...
function member_is_opaque_for_tag_proof(m: root.types.RuntimeTy) -> bool throws never {
    baml.sys.panic("member_is_opaque_for_tag_proof: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::tag_conflated_shape @ d9be6853b
// The `TagConflatedShape` of `ty`, or `None` when its tag already pins its
// values (a primitive, a monomorphic class, …).
function tag_conflated_shape(ty: root.types.RuntimeTy) -> TagConflatedShape? throws never {
    baml.sys.panic("tag_conflated_shape: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::parametric_arm_tag_sufficient @ d9be6853b
// Whether a coarse `LIST`/`MAP`/`FUTURE` type-tag test for the parametric arm
// `arm` is a *provably sound* substitute for the argument-discriminating
// structural test, for values of the scrutinee's resolved static type
// `scrutinee`.
function parametric_arm_tag_sufficient(
    arm: root.types.RuntimeTy,
    scrutinee: root.types.RuntimeTy,
) -> bool throws never {
    baml.sys.panic("parametric_arm_tag_sufficient: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::switch_member_tag_sufficient @ d9be6853b
// Whether the coarse type tag fully discriminates values reaching a switch arm
// whose (already union-flattened) member type is `member`, given the enclosing
// match scrutinee's resolved static type when known.
function switch_member_tag_sufficient(
    member: root.types.RuntimeTy,
    scrutinee: root.types.RuntimeTy?,
) -> bool throws never {
    baml.sys.panic("switch_member_tag_sufficient: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::enum_type_name @ d9be6853b
// The enum type name of an enum-shaped type. A bare enum (`Color`) and any of
// its variants (`Color.Red`) collapse onto the same shared `ENUM` type tag, so
// both count as "an enum of this type" for the tag-collision check in
// `switch_member_tag_sufficient`.
function enum_type_name(ty: root.types.RuntimeTy) -> root.types.DeclName? throws never {
    baml.sys.panic("enum_type_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::definition_display_name @ d9be6853b
// The name a definition links and displays as: `pkg.ns.name` for a free
// item, `pkg.ns.Class.name` for a class-inherent method, and: for an
// interface-machinery body: `pkg.ns.<display owner>.name`, where the
// display owner is the interface's bare name for a default body and the
// synthesized `<(target as iface)>` segment for an impl-provided one.
function definition_display_name(db: root.hir.Db, def: root.hir.Definition) -> string throws never {
    baml.sys.panic("definition_display_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::global_display_name @ d9be6853b
// The display name of a top-level binding, wherever it is declared: a source
// `let` by its declaration, an exported row of a served package by its head
// (the same `package.namespace….name` spelling).
function global_display_name(db: root.hir.Db, global: int) -> string throws never {
    baml.sys.panic("global_display_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::definition_short_name @ d9be6853b
// The owner-qualified tail of a declaration's display name: everything after
// the package and namespace segments: `f` for a free function, `Class.m`
// for a class-inherent method, `Interface.m` for an interface's default
// body, `<(target as iface)>.m` for an impl-provided one, and the bare name
// for every other item. This is the ONE spelling of a declaration's tail:
// `definition_display_name` prefixes it, and a nested synthetic function ...
function definition_short_name(db: root.hir.Db, def: root.hir.Definition) -> string throws never {
    baml.sys.panic("definition_short_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::dotted_name @ d9be6853b
// `package.ns….tail…`: the one dotted spelling every display name uses.
function dotted_name(package: string, namespace: string[], tail: string[]) -> string throws never {
    baml.sys.panic("dotted_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::impl_display_segment @ d9be6853b
// The synthesized `<(target as iface)>` display segment for an anonymous
// impl block: see the `MethodOwner::Impl` arm of `definition_display_name`.
function impl_display_segment(db: root.hir.Db, impl_loc: int) -> string throws never {
    baml.sys.panic("impl_display_segment: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::interface_body_link_bounds_suffix @ d9be6853b
// The `where` suffix of an impl-provided interface body's DISPLAY: the
// impl's constraint set, rendered with frame indices. Display only: the
// body's identity is its structural `ImplBodyKey`, whose coherence part
// carries the same constraints.
function interface_body_link_bounds_suffix(db: root.hir.Db, func_loc: int) -> string? throws never {
    baml.sys.panic("interface_body_link_bounds_suffix: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::render_with_frame_indices @ d9be6853b
// Render `ty` canonically with the impl frame's type variables spelled as
// their frame indices (`#0`) instead of their declared names: the declared
// names are the block's private spelling, not part of its identity.
function render_with_frame_indices(
    ty: root.types.Ty,
    frame: root.types.ParamTy[],
    spelling: root.types.TyRenderStrategy,
) -> string throws never {
    baml.sys.panic("render_with_frame_indices: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::native_key_for @ d9be6853b
// The codegen-lockstep NATIVE KEY for a builtin body: the dot-free
// `{iface as written}$for${target as written}` scheme that
// `baml_builtins2_codegen::extract` produces byte-for-byte for its dispatch
// tables and sys-op paths, with a written `root.` spelled as the package
// (`baml_base::native_key_spelling`, shared with the extractor). This is a
// KEY, not a name: `Function.name` renders the canonical ...
function native_key_for(db: root.hir.Db, func_loc: int) -> string throws never {
    baml.sys.panic("native_key_for: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::function_is_interface_body @ d9be6853b
// True if `func_loc` is an interface-machinery *body*: an impl-block method
// (in-class or free: the compiler sees no distinction) or an interface
// default-method body.
function function_is_interface_body(db: root.hir.Db, func_loc: int) -> bool throws never {
    baml.sys.panic("function_is_interface_body: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::function_display_name @ d9be6853b
// The name a callable links as, wherever it is declared: a source
// declaration by `definition_display_name`; a served package's row by its
// ADDRESS: its dispatch slot: never the heads the row's own `target`
// spells (a blob cannot point a consumer's call at another package's
// symbol).
function function_display_name(db: root.hir.Db, func: int) -> string throws never {
    baml.sys.panic("function_display_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::class_display_name @ d9be6853b
// The display name of a class, wherever it is declared: what emit renders
// into operand metadata.
function class_display_name(db: root.hir.Db, class_: int) -> string throws never {
    baml.sys.panic("class_display_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::enum_display_name @ d9be6853b
// The display name of an enum, wherever it is declared.
function enum_display_name(db: root.hir.Db, enum_ref: int) -> string throws never {
    baml.sys.panic("enum_display_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::resolution_func_loc @ d9be6853b
// The body a resolution calls directly in THIS compilation: its callable,
// when declared in source. A served package's row has no body here, and a
// virtual interface method dispatches at runtime even when the interface
// declares a default. Fields, variants, and virtual fields are not
// callable.
function resolution_func_loc(res: root.hir_ty.MemberResolution) -> int? throws never {
    baml.sys.panic("resolution_func_loc: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::resolution_external_function @ d9be6853b
// The exported row a resolution names, when its callee is a served
// package's: the row itself for a free function, a class method, or an
// impl-provided method; the interface's own declaration of the method for
// a virtual slot on a served interface.
function resolution_external_function(
    db: root.hir.Db,
    res: root.hir_ty.MemberResolution,
) -> int? throws never {
    baml.sys.panic("resolution_external_function: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::lower_ref_interface_target_args @ d9be6853b
// Lower the generic arguments of an interface target held as a `TypeRefId` in
// `store` (e.g. the `<int>` in `implements Slot<int>`). Non-`Path` targets
// contribute no arguments.
function lower_ref_interface_target_args(
    db: root.hir.Db,
    store: root.hir.TypeRefStore,
    target: int,
    pkg_items: root.hir.PackageItems,
    namespace_path: string[],
    generic_params: root.types.ParamTy[],
    bounds: map<root.types.ParamTy, root.types.InterfaceConstraint[]>,
) -> root.types.Ty[] throws never {
    baml.sys.panic("lower_ref_interface_target_args: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::runtime @ d9be6853b
// The crossing from this program's compile-time types to the wire.
function runtime(ctx: LoweringContext) -> RuntimeLowering throws never {
    baml.sys.panic("runtime: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lang @ d9be6853b
// Where the language packages are installed.
function lang(ctx: LoweringContext) -> root.base.LangRoots throws never {
    baml.sys.panic("lang: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lang_function @ d9be6853b
// A function the language ships and lowering targets by identity
// (`baml.sys.panic`, the `baml.ops` drivers, ...), whichever lane serves
// the package. Its absence is a compiler/stdlib mismatch.
function lang_function(
    ctx: LoweringContext,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> int throws never {
    baml.sys.panic("lang_function: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lang_class_method @ d9be6853b
// `Self::lang_function` for a class-inherent method of a language
// package's root class (`baml.String.from`, `baml.Array.slice`).
function lang_class_method(
    ctx: LoweringContext,
    package: root.base.LangPackage,
    class_: string,
    method: string,
) -> int throws never {
    baml.sys.panic("lang_class_method: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::is_lang_method @ d9be6853b
// Whether `func` is the method `owner.name` of a language package's
// root class or interface: the identity twin of a rendered-name test.
function is_lang_method(
    ctx: LoweringContext,
    func: int,
    package: root.base.LangPackage,
    owner: string,
    name: string,
) -> bool throws never {
    baml.sys.panic("is_lang_method: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::callee_owner_is_lang @ d9be6853b
// Whether `func` is owned by `owner`, a language package's root type.
function callee_owner_is_lang(
    ctx: LoweringContext,
    func: int,
    package: root.base.LangPackage,
    owner: string,
) -> bool throws never {
    baml.sys.panic("callee_owner_is_lang: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enum_ref_of @ d9be6853b
// The declaration an enum head names, wherever it lives. TIR admits an
// enum type only by resolving its declaration, so a head that names
// none here is an internal inconsistency, never a state to fall open on.
function enum_ref_of(
    ctx: LoweringContext,
    qtn: root.types.DeclName,
) -> int throws MirInternalError {
    throw MirInternalError { message: "enum_ref_of: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::enum_variant_index @ d9be6853b
// The discriminant of `variant` in `enum_ref`'s declared order. TIR
// admitted the variant against this very declaration, so a miss is a
// compiler bug.
function enum_variant_index(
    ctx: LoweringContext,
    enum_ref: int,
    variant: string,
) -> int throws MirInternalError {
    throw MirInternalError { message: "enum_variant_index: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lang_class @ d9be6853b
// A class the language ships and lowering constructs by identity
// (`baml.TaggedString`, `baml.spawn.Params`), whichever lane serves the
// package. Its absence is a compiler/stdlib mismatch.
function lang_class(
    ctx: LoweringContext,
    package: root.base.LangPackage,
    namespace: string[],
    name: string,
) -> int throws never {
    baml.sys.panic("lang_class: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_ref_of @ d9be6853b
// The declaration a class head names, wherever it lives. TIR admits a
// class type only by resolving its declaration, so a head that names
// none here is an internal inconsistency, never a state to fall open on.
function class_ref_of(
    ctx: LoweringContext,
    head: root.types.DeclName,
) -> int throws MirInternalError {
    throw MirInternalError { message: "class_ref_of: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::type_test @ d9be6853b
// A type test of `template`, stated by declaration where it is nominal:
// a class or an enum is tested by the declaration its head names.
function type_test(
    ctx: LoweringContext,
    template: root.types.TyTemplate,
) -> TypeTest throws MirInternalError {
    throw MirInternalError { message: "type_test: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_field_slot @ d9be6853b
// Where `field` sits in `class`'s layout and the type it holds there, with
// the receiver's class arguments substituted into the declared field type
// so a generic position (`item: T` in `Box<T>`) reads as the concrete
// receiver-side binding rather than erased runtime metadata. `None` when
// the class declares no such field.
function class_field_slot(
    ctx: LoweringContext,
    class_: int,
    field: string,
    class_type_args: root.types.RuntimeTy[],
) -> (int, root.types.RuntimeTy)? throws never {
    baml.sys.panic("class_field_slot: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::display_viewpoint @ d9be6853b
// The viewpoint a function's DISPLAY fields (`display_param_types`,
// `display_return_type`) spell types from: the package's root namespace,
// facing a host that reads the package as a whole: the same one emit
// uses for a declared function's, so a lambda's agree with its owner's.
function display_viewpoint(ctx: LoweringContext) -> root.hir_ty.Viewpoint throws never {
    baml.sys.panic("display_viewpoint: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::baml_iter_decl @ d9be6853b
// `baml.iter.<name>` as a compile-time head, or `None` without the stdlib.
function baml_iter_decl(ctx: LoweringContext, name: string) -> root.types.DeclName? throws never {
    baml.sys.panic("baml_iter_decl: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::baml_decl @ d9be6853b
// `baml.<namespace>.<name>` as a head. Lowering names one only for a
// construct the language package itself defines the meaning of (a `for`
// loop's iterator protocol, an ordering operator), so the package's
// absence there is a compiler/stdlib mismatch.
function baml_decl(
    ctx: LoweringContext,
    namespace: string,
    name: string,
) -> root.types.DeclName throws never {
    baml.sys.panic("baml_decl: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::baml_iter_done_ty @ d9be6853b
function baml_iter_done_ty(ctx: LoweringContext) -> root.types.RuntimeTy throws never {
    baml.sys.panic("baml_iter_done_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::spelled @ d9be6853b
// A MIR type rendered canonically, for a message.
function spelled(
    ctx: LoweringContext,
    ty: root.types.RuntimeTy,
) -> root.types.RuntimeTy throws never {
    baml.sys.panic("spelled: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::associated_binding_ty @ d9be6853b
function associated_binding_ty(
    bindings: (string, root.types.Ty)[],
    name: string,
) -> root.types.Ty? throws never {
    baml.sys.panic("associated_binding_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::substitute_class_params_in_interface_view @ d9be6853b
function substitute_class_params_in_interface_view(
    view: InterfaceTypeView,
    class_params: root.types.ParamTy[],
    class_args: root.types.Ty[],
) -> InterfaceTypeView throws never {
    baml.sys.panic("substitute_class_params_in_interface_view: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_view_for_class_tir_ty @ d9be6853b
function interface_view_for_class_tir_ty(
    ctx: LoweringContext,
    class_qtn: root.types.DeclName,
    class_args: root.types.Ty[],
    target_tn: root.types.DeclName,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("interface_view_for_class_tir_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::realized_interface_view_for @ d9be6853b
// The realized view of the `target_tn` interface a receiver of type `actual_ty`
// provides: through its own `requires` closure for an interface-existential
// receiver, or through one of its impls (own or `requires`-elaborated views) for
// a concrete-headed receiver, enumerated via the canonical L1 substrate.
function realized_interface_view_for(
    ctx: LoweringContext,
    actual_ty: root.types.Ty,
    target_tn: root.types.DeclName,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("realized_interface_view_for: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::interface_view_for_tir_ty @ d9be6853b
function interface_view_for_tir_ty(
    ctx: LoweringContext,
    ty: root.types.Ty,
    target_tn: root.types.DeclName,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("interface_view_for_tir_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::iterable_view_for_tir_ty @ d9be6853b
function iterable_view_for_tir_ty(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("iterable_view_for_tir_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::scope_is_descendant_or_self @ d9be6853b
function scope_is_descendant_or_self(
    index: root.hir.FileSemanticIndex,
    scope_id: int,
    ancestor_id: int,
) -> bool throws never {
    baml.sys.panic("scope_is_descendant_or_self: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::binding_id_for_pattern_site_name @ d9be6853b
function binding_id_for_pattern_site_name(
    ctx: LoweringContext,
    pattern: int,
    site: root.hir.DefinitionSite,
    name: string,
) -> root.hir.BindingId? throws never {
    baml.sys.panic("binding_id_for_pattern_site_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::binding_is_captured @ d9be6853b
// Whether a nested closure captures `binding`, per HIR's capture analysis.
// That analysis is complete before MIR runs: a capture through any depth
// of nesting marks the binding in its declaring scope.
function binding_is_captured(
    ctx: LoweringContext,
    binding: root.hir.BindingId,
) -> bool throws never {
    baml.sys.panic("binding_is_captured: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::value_place @ d9be6853b
// The place holding a binding's value: the local itself, or the cell
// behind it when a closure captures the binding.
function value_place(ctx: LoweringContext, local: int) -> Place throws never {
    baml.sys.panic("value_place: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::self_local @ d9be6853b
function self_local(ctx: LoweringContext) -> int? throws never {
    baml.sys.panic("self_local: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pattern_binding_is_captured @ d9be6853b
// `Self::binding_is_captured` for the binding `name` introduces in
// `pattern` at `site`.
function pattern_binding_is_captured(
    ctx: LoweringContext,
    pattern: int,
    site: root.hir.DefinitionSite,
    name: string,
) -> bool throws never {
    baml.sys.panic("pattern_binding_is_captured: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::binding_id_for_statement_name @ d9be6853b
function binding_id_for_statement_name(
    ctx: LoweringContext,
    stmt_id: int,
    pattern: int,
    name: string,
) -> root.hir.BindingId? throws never {
    baml.sys.panic("binding_id_for_statement_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::captured_locals_of_statement @ d9be6853b
// The captured locals among the bindings `stmt` declared (a `let`; any
// other statement declares none). The statement must already be lowered.
function captured_locals_of_statement(ctx: LoweringContext, stmt: int) -> int[] throws never {
    baml.sys.panic("captured_locals_of_statement: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::recell_per_iteration @ d9be6853b
function recell_per_iteration(ctx: LoweringContext, locals: int[]) -> void throws never {
    baml.sys.panic("recell_per_iteration: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::declare_binding @ d9be6853b
// Declare the local that holds the binding `name` introduces in `pattern`
// at `site`, creating its cell if a closure captures it.
function declare_binding(
    ctx: LoweringContext,
    pattern: int,
    site: root.hir.DefinitionSite,
    name: string,
    ty: root.types.RuntimeTy,
) -> int throws MirInternalError {
    throw MirInternalError { message: "declare_binding: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::declare_parameter @ d9be6853b
// Declare the local for parameter `param_idx` of the function or lambda
// being lowered. A captured parameter is celled by the frame preamble
// rather than here: the caller has already written its value into the
// slot.
function declare_parameter(
    ctx: LoweringContext,
    param_idx: int,
    name: string,
    ty: root.types.RuntimeTy,
) -> int throws never {
    baml.sys.panic("declare_parameter: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::bind_existing_local @ d9be6853b
// Record that the binding `name` introduces in `pattern` at `site` is
// held by `local`, a slot the runtime writes directly (a caught error or
// its stack trace). Only for a binding no closure captures: a captured
// binding owns a celled slot of its own, from `declare_binding`.
function bind_existing_local(
    ctx: LoweringContext,
    pattern: int,
    site: root.hir.DefinitionSite,
    name: string,
    local: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "bind_existing_local: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_resolution @ d9be6853b
function path_resolution(
    ctx: LoweringContext,
    expr_id: int,
) -> root.hir.PathResolution? throws never {
    baml.sys.panic("path_resolution: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::hir_binding_id_for_path @ d9be6853b
function hir_binding_id_for_path(
    ctx: LoweringContext,
    expr_id: int,
) -> root.hir.BindingId? throws never {
    baml.sys.panic("hir_binding_id_for_path: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::binding_id_for_path @ d9be6853b
function binding_id_for_path(
    ctx: LoweringContext,
    expr_id: int,
    name: string,
) -> root.hir.BindingId? throws never {
    baml.sys.panic("binding_id_for_path: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::local_for_path @ d9be6853b
function local_for_path(ctx: LoweringContext, expr_id: int, name: string) -> int? throws never {
    baml.sys.panic("local_for_path: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::refined_root_local_ty @ d9be6853b
// The type of a path root held by `local`, preferring what TIR inferred
// for the root expression. When TIR knows a more specific type than the
// local's `Unknown` declaration, the declaration is refined too, so the
// emitter can resolve field names for display (`load_field .index`).
function refined_root_local_ty(
    ctx: LoweringContext,
    expr_id: int,
    local: int,
) -> root.types.RuntimeTy throws never {
    baml.sys.panic("refined_root_local_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::place_for_path @ d9be6853b
// The place holding the value of the binding `name` resolves to at
// `expr_id`: a local, or the value behind a cell for a captured binding
// or a capture.
function place_for_path(ctx: LoweringContext, expr_id: int, name: string) -> Place? throws never {
    baml.sys.panic("place_for_path: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::ensure_transitive_capture @ d9be6853b
// Return the current lambda's capture index for `binding_id`, allocating a
// fresh one (and signalling the parent to forward it via
// `transitive_captures_needed`) when it isn't captured yet. Mirrors the
// transitive-capture branch of `lower_lambda`'s capture-operand loop, for
// callers that discover a needed capture while lowering an expression
// (e.g. a tagged-body param referenced from a nested lambda).
function ensure_transitive_capture(
    ctx: LoweringContext,
    binding_id: root.hir.BindingId,
) -> int throws never {
    baml.sys.panic("ensure_transitive_capture: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::replay_defers_to_depth @ d9be6853b
// Re-lower the `defer` bodies armed at `[defer_depth..]` of
// `defer_stack`, in reverse declaration order (LIFO): BEP-042.
function replay_defers_to_depth(
    ctx: LoweringContext,
    defer_depth: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "replay_defers_to_depth: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_shielded_defer_body @ d9be6853b
// Lower one copy of a `defer` body shielded from cancellation: its
// blocks are stamped `shielded`, and the engine does not deliver
// `Cancelled` to a thread executing inside them (or in a callee called
// from them), so cleanup may suspend (BEP-034's shield, implicit for
// `defer`). A throw out of the body simply leaves the shielded blocks.
function lower_shielded_defer_body(
    ctx: LoweringContext,
    body: int,
) -> void throws MirInternalError {
    throw MirInternalError { message: "lower_shielded_defer_body: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::shielded @ d9be6853b
// Lower with `f` shielded from cancellation: the blocks it creates are
// stamped `shielded`, and the shield closes when it returns, so a shield
// is never opened without being closed, and nested ones close innermost
// first.
// Restructured: `R` may carry a `MirInternalError` (Rust's `Lowered`), so `f` declares it.
function shielded<R>(
    ctx: LoweringContext,
    f: (LoweringContext) -> R throws MirInternalError,
) -> R throws MirInternalError {
    throw MirInternalError { message: "shielded: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::verify_bindings_recorded @ d9be6853b
// Every binding HIR registered in the scopes this body lowers has a
// local: the tripwire for a declaration site that bypassed
// `declare_binding`. Nested lambda subtrees are skipped: they are
// lowered in their own context, which runs this check when it builds ,
// and so are the statements of `unlowered_block`, a desugared block the
// lowering replaced wholesale (a tagged template's static layout).
function verify_bindings_recorded(
    ctx: LoweringContext,
    root_scope: int,
    unlowered_block: int?,
) -> void throws never {
    baml.sys.panic("verify_bindings_recorded: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::expr_metadata_key @ d9be6853b
// Get the `baml_type::RuntimeTy` for an expression by looking up in the aggregated map
// and converting from TIR `Ty`. Uses `current_metadata_scope` as the arena namespace.
function expr_metadata_key(
    ctx: LoweringContext,
    expr_id: int,
) -> root.hir.ExprMetadataKey throws never {
    baml.sys.panic("expr_metadata_key: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pat_metadata_key @ d9be6853b
function pat_metadata_key(ctx: LoweringContext, pat_id: int) -> PatMetadataKey throws never {
    baml.sys.panic("pat_metadata_key: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_tables @ d9be6853b
function tir_tables(
    ctx: LoweringContext,
) -> root.hir_ty.InferenceResult<root.types.Ty>? throws never {
    baml.sys.panic("tir_tables: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_expr_type @ d9be6853b
function tir_expr_type(ctx: LoweringContext, expr: int) -> root.types.Ty? throws never {
    baml.sys.panic("tir_expr_type: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_pat_type @ d9be6853b
function tir_pat_type(ctx: LoweringContext, pat: int) -> root.types.Ty? throws never {
    baml.sys.panic("tir_pat_type: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_resolution @ d9be6853b
function tir_resolution(
    ctx: LoweringContext,
    expr: int,
) -> root.hir_ty.MemberResolution? throws never {
    baml.sys.panic("tir_resolution: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_field_view_of @ d9be6853b
// The interface view and field index a recorded member resolution carries
// when it is a virtual-field read: source or mounted interface alike; every
// other resolution kind is `None`. Authoritative, and preferred over
// re-deriving a view from the receiver's type: it is what the type checker
// actually resolved through, which is the only thing that answers a *union*
// receiver, where the serving interface is the one every arm shares and is ...
function virtual_field_view_of(
    resolution: root.hir_ty.MemberResolution,
) -> (InterfaceTypeView, int)? throws never {
    baml.sys.panic("virtual_field_view_of: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::virtual_method_view_of @ d9be6853b
// The interface view a recorded member resolution dispatches a method
// through, when it is a virtual slot bound to its receiver; every other
// resolution kind is `None`. The method twin of
// `Self::virtual_field_view_of`: the view the type checker resolved
// the access through, read rather than derived again from the
// receiver's type.
function virtual_method_view_of(
    resolution: root.hir_ty.MemberResolution,
) -> InterfaceTypeView? throws never {
    baml.sys.panic("virtual_method_view_of: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_virtual_field_view @ d9be6853b
function tir_virtual_field_view(
    ctx: LoweringContext,
    expr: int,
) -> (InterfaceTypeView, int)? throws never {
    baml.sys.panic("tir_virtual_field_view: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_segment_virtual_field_view @ d9be6853b
// The recorded virtual-field view of member segment `seg_idx` of a path
// ladder (1-based within the path: segment 0 is the root). The checker
// records one resolution per member segment and the writeback finalizes
// each, so a ladder's interface field reads resolve exactly like an
// expression's: through the interface the access was CHECKED against,
// never re-derived from the segment's type.
function tir_path_segment_virtual_field_view(
    ctx: LoweringContext,
    expr: int,
    seg_idx: int,
) -> (InterfaceTypeView, int)? throws never {
    baml.sys.panic("tir_path_segment_virtual_field_view: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_is_exhaustive_match @ d9be6853b
function tir_is_exhaustive_match(ctx: LoweringContext, expr: int) -> bool throws never {
    baml.sys.panic("tir_is_exhaustive_match: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path @ d9be6853b
// The value-rooted ladder recorded for a path expression.
function tir_path(
    ctx: LoweringContext,
    expr: int,
) -> root.hir_ty.ResolvedPath<root.types.Ty>? throws never {
    baml.sys.panic("tir_path: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_root_type @ d9be6853b
function tir_path_root_type(ctx: LoweringContext, expr: int) -> root.types.Ty? throws never {
    baml.sys.panic("tir_path_root_type: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_global_root @ d9be6853b
// The top-level `let` TIR resolved this path expression's leading
// segments to, with how many segments name it.
function tir_global_root(ctx: LoweringContext, expr: int) -> root.hir_ty.GlobalRoot? throws never {
    baml.sys.panic("tir_global_root: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_segment_type @ d9be6853b
function tir_path_segment_type(
    ctx: LoweringContext,
    expr: int,
    seg_idx: int,
) -> root.types.Ty? throws never {
    baml.sys.panic("tir_path_segment_type: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_member_resolution @ d9be6853b
// The resolution of member segment `member_index` (0 = the first member
// after the root) of a fully resolved ladder.
function tir_path_member_resolution(
    ctx: LoweringContext,
    expr: int,
    member_index: int,
) -> root.hir_ty.MemberResolution? throws never {
    baml.sys.panic("tir_path_member_resolution: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_path_final_resolution @ d9be6853b
// The final segment's resolution of a fully resolved ladder: what a
// value-rooted path names.
function tir_path_final_resolution(
    ctx: LoweringContext,
    expr: int,
) -> root.hir_ty.MemberResolution? throws never {
    baml.sys.panic("tir_path_final_resolution: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_call_plan @ d9be6853b
function tir_call_plan(
    ctx: LoweringContext,
    expr: int,
) -> root.hir_ty.CallPlan<root.types.Ty>? throws never {
    baml.sys.panic("tir_call_plan: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_type_binding @ d9be6853b
function tir_type_binding(
    ctx: LoweringContext,
    stmt: int,
) -> root.hir_ty.ScopedTypeBinding? throws never {
    baml.sys.panic("tir_type_binding: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tir_truthy_condition @ d9be6853b
function tir_truthy_condition(ctx: LoweringContext, expr: int) -> bool throws never {
    baml.sys.panic("tir_truthy_condition: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::convert_tir_ty_for_runtime @ d9be6853b
function convert_tir_ty_for_runtime(
    ctx: LoweringContext,
    ty: root.types.Ty,
) -> root.types.RuntimeTy throws never {
    baml.sys.panic("convert_tir_ty_for_runtime: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::runtime_ready_ty @ d9be6853b
// A checked type's runtime representation: literal freshness is a
// compile-time property and drops, and a slotless effect parameter has
// no frame slot to name. The error sentinel is NOT handled here - a
// checked world carries none (`baml_db::CheckedWorld`'s walker), and
// one that slipped through is refused loudly by the conversion.
function runtime_ready_ty(ty: root.types.Ty) -> root.types.Ty throws never {
    baml.sys.panic("runtime_ready_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_signature_runtime_ty @ d9be6853b
// Lower a method-signature type expression (a parameter or return type) to
// a runtime type, in the owner's declaration environment.
function lower_signature_runtime_ty(
    ctx: LoweringContext,
    te: root.ast.TypeExpr,
    pkg_items: root.hir.PackageItems,
    ns_context: string[],
) -> root.types.RuntimeTy throws never {
    baml.sys.panic("lower_signature_runtime_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::expr_ty @ d9be6853b
// The checker's type for an expression, as a runtime type. The checker
// types every expression of a body it accepts, so a missing entry is an
// internal inconsistency: an expression the checker was never given, or
// one read against the other arena's results. Never a type to stand in
// for.
function expr_ty(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.RuntimeTy throws MirInternalError {
    throw MirInternalError { message: "expr_ty: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::class_type_arg_templates @ d9be6853b
// Compute the `TyTemplate` slice for the class-level type args of a class
// construction expression.
function class_type_arg_templates(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.TyTemplate[] throws never {
    baml.sys.panic("class_type_arg_templates: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::array_element_template @ d9be6853b
// The element-type template for an array-literal expression: the `T` of
// its `T[]` static type: for `Rvalue::Array`. A generic element maps to
// a `TypeArgRef` so it resolves against the frame's type args at runtime.
// The checker types every array literal as a list.
function array_element_template(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.TyTemplate throws MirInternalError {
    throw MirInternalError { message: "array_element_template: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::tuple_element_templates @ d9be6853b
function tuple_element_templates(
    ctx: LoweringContext,
    expr_id: int,
    arity: int,
) -> root.types.TyTemplate[] throws MirInternalError {
    throw MirInternalError { message: "tuple_element_templates: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::map_kv_templates @ d9be6853b
// The key/value type templates for a map-literal expression: the `K`/`V`
// of its `map<K, V>` static type: for `Rvalue::Map`. The checker
// types every map literal as a map.
function map_kv_templates(
    ctx: LoweringContext,
    expr_id: int,
) -> (root.types.TyTemplate, root.types.TyTemplate) throws MirInternalError {
    throw MirInternalError { message: "map_kv_templates: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::object_class_type_arg_templates @ d9be6853b
// The type-argument templates of an object literal: its written type
// args as TIR resolved them (the call plan keyed at the expression), or,
// for `Box { … }`, the class type TIR inferred for it. Never re-lowered
// from syntax: see `check_type_of_intrinsic`.
function object_class_type_arg_templates(
    ctx: LoweringContext,
    expr_id: int,
) -> root.types.TyTemplate[] throws never {
    baml.sys.panic("object_class_type_arg_templates: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::pat_ty @ d9be6853b
// The checker's type for a pattern binding, as a runtime type. Like
// `Self::expr_ty`, a missing entry is an internal inconsistency.
function pat_ty(ctx: LoweringContext, pat_id: int) -> root.types.RuntimeTy throws MirInternalError {
    throw MirInternalError { message: "pat_ty: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_root_ty @ d9be6853b
// Get the TIR-inferred root segment type for a multi-segment Path expression.
// Returns `None` if no root type was recorded (e.g. single-segment paths).
function path_root_ty(ctx: LoweringContext, expr_id: int) -> root.types.RuntimeTy? throws never {
    baml.sys.panic("path_root_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::top_level_let_at @ d9be6853b
// The **top-level `let`** this path expression's root names, if any: a
// global variable, a `client` declaration, or a Session submission's
// persisted root binding: all the same item. The checker records every
// such root (`InferenceResult::global_roots`), qualified (`root.ns.x`,
// lowered here as the bare `x` it names: see `with_bare_global_paths`)
// or bare.
function top_level_let_at(ctx: LoweringContext, expr_id: int) -> int? throws never {
    baml.sys.panic("top_level_let_at: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_root_is_top_level_let @ d9be6853b
// Whether a path expression's root names a top-level `let`: i.e. whether
// it denotes a runtime **value** even though it is not a lexical binding.
function path_root_is_top_level_let(ctx: LoweringContext, expr_id: int) -> bool throws never {
    baml.sys.panic("path_root_is_top_level_let: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::load_top_level_let_root @ d9be6853b
// Materialize a **top-level `let`**'s current value into a temp, when
// `name` resolves to one at this expression's position.
function load_top_level_let_root(ctx: LoweringContext, expr_id: int) -> int? throws never {
    baml.sys.panic("load_top_level_let_root: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::path_segment_ty @ d9be6853b
// Get the TIR-inferred type of `segments[..=seg_idx]` for a multi-segment
// local-rooted Path expression. Returns `None` if not recorded.
function path_segment_ty(
    ctx: LoweringContext,
    expr_id: int,
    seg_idx: int,
) -> root.types.RuntimeTy? throws never {
    baml.sys.panic("path_segment_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::resolve_type_annotation @ d9be6853b
// Resolve a `TypeExpr` annotation directly to a `baml_type::RuntimeTy`.
// Used for `TypedBinding` patterns where TIR may not have populated the
// bindings map (e.g. catch arm and match arm patterns).
function resolve_type_annotation(
    ctx: LoweringContext,
    ty_expr: root.ast.TypeExpr,
) -> root.types.RuntimeTy throws never {
    baml.sys.panic("resolve_type_annotation: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::lower_type_annotation_tir @ d9be6853b
// Lower a pattern's type annotation to TIR with the enclosing function's
// generic params in scope, so `TypeVar`s survive and a typed pattern test
// lowers to a `TypeArgRef` template (dynamic dispatch on the realized type
// argument).
function lower_type_annotation_tir(
    ctx: LoweringContext,
    ty_expr: root.ast.TypeExpr,
) -> root.types.Ty throws never {
    baml.sys.panic("lower_type_annotation_tir: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::span_for_expr @ d9be6853b
// Build a `Span` from an expression's source range.
// Returns `None` if no source map is available (e.g. synthesized bodies).
function span_for_expr(ctx: LoweringContext, expr_id: int) -> root.base.Span? throws never {
    baml.sys.panic("span_for_expr: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::span_for_pat @ d9be6853b
// Build a `Span` from a pattern's source range.
function span_for_pat(ctx: LoweringContext, pat_id: int) -> root.base.Span? throws never {
    baml.sys.panic("span_for_pat: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::LoweringContext::span_for_stmt @ d9be6853b
// Build a `Span` from a statement's source range.
function span_for_stmt(ctx: LoweringContext, stmt_id: int) -> root.base.Span? throws never {
    baml.sys.panic("span_for_stmt: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::lower_let_body @ d9be6853b
// Lower a top-level let binding's initializer into a `MirFunctionBody`.
function lower_let_body(
    db: root.hir.Db,
    let_loc: int,
    opt: OptLevel,
) -> LoweredLetBody? throws MirInternalError {
    throw MirInternalError { message: "lower_let_body: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::with_bare_global_paths @ d9be6853b
// `body` with every qualified global path (`root.ns.x.rest`) rewritten to
// the bare form `[x, rest…]`.
function with_bare_global_paths(
    body: root.ast.ExprBody,
    tables: root.hir_ty.InferenceResult<root.types.Ty>?,
) -> root.ast.ExprBody throws never {
    baml.sys.panic("with_bare_global_paths: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::lower_let_body_impl @ d9be6853b
function lower_let_body_impl(
    db: root.hir.Db,
    let_loc: int,
    opt: OptLevel,
) -> LoweredLetBody? throws MirInternalError {
    throw MirInternalError { message: "lower_let_body_impl: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::check_indirect_call_layouts @ d9be6853b
// An indirect call pushes slots the runtime callee cannot describe, so its
// layout must come from the checked call plan. Only compiler-synthesized
// DIRECT calls go without one; an indirect call without a layout means TIR
// recorded no plan for the call it checked (), and emit could only
// guess what the call pushed.
function check_indirect_call_layouts(body: MirFunctionBody) -> void throws MirInternalError {
    throw MirInternalError { message: "check_indirect_call_layouts: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::check_function_call_layouts @ d9be6853b
function check_function_call_layouts(function_: MirFunction) -> void throws MirInternalError {
    throw MirInternalError { message: "check_function_call_layouts: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::lower_function @ d9be6853b
// Lower one function to MIR.
function lower_function(
    db: root.hir.Db,
    func_loc: int,
    opt: OptLevel,
) -> MirFunction throws MirInternalError {
    throw MirInternalError { message: "lower_function: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::lower_function_impl @ d9be6853b
function lower_function_impl(
    db: root.hir.Db,
    func_loc: int,
    opt: OptLevel,
) -> MirFunction throws MirInternalError {
    throw MirInternalError { message: "lower_function_impl: not ported (U1)", span: null }
}

// port: baml_compiler2_mir/src/lower.rs::index_kind_for @ d9be6853b
function index_kind_for(ty: root.types.RuntimeTy) -> IndexKind throws never {
    baml.sys.panic("index_kind_for: not ported (U1)")
}

// port: baml_compiler2_mir/src/lower.rs::is_tuple_runtime_ty @ d9be6853b
function is_tuple_runtime_ty(ty: root.types.RuntimeTy) -> bool throws never {
    baml.sys.panic("is_tuple_runtime_ty: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::display_function @ d9be6853b
// Pretty print a MIR function.
function display_function(db: root.hir.Db, func: MirFunction) -> string throws never {
    baml.sys.panic("display_function: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_function @ d9be6853b
// Write a MIR function to a formatter.
function write_function(f: string[], db: root.hir.Db, func: MirFunction) -> void throws never {
    baml.sys.panic("write_function: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_bytecode_function @ d9be6853b
// Write the bytecode body of a MIR function.
function write_bytecode_function(
    f: string[],
    db: root.hir.Db,
    func: MirFunction,
    body: MirFunctionBody,
) -> void throws never {
    baml.sys.panic("write_bytecode_function: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::display_body @ d9be6853b
// Pretty print a function body on its own: its locals and blocks, without
// the signature header.
function display_body(db: root.hir.Db, body: MirFunctionBody, arity: int) -> string throws never {
    baml.sys.panic("display_body: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_body @ d9be6853b
// Write a body's locals and blocks.
function write_body(
    f: string[],
    db: root.hir.Db,
    body: MirFunctionBody,
    arity: int,
) -> void throws never {
    baml.sys.panic("write_body: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_local_decl_inline @ d9be6853b
function write_local_decl_inline(
    f: string[],
    db: root.hir.Db,
    id: int,
    decl: LocalDecl,
) -> void throws never {
    baml.sys.panic("write_local_decl_inline: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_block @ d9be6853b
function write_block(f: string[], db: root.hir.Db, block: BasicBlock) -> void throws never {
    baml.sys.panic("write_block: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_statement @ d9be6853b
function write_statement(f: string[], db: root.hir.Db, stmt: Statement) -> void throws never {
    baml.sys.panic("write_statement: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_terminator @ d9be6853b
function write_terminator(f: string[], db: root.hir.Db, term: Terminator) -> void throws never {
    baml.sys.panic("write_terminator: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_rvalue @ d9be6853b
function write_rvalue(f: string[], db: root.hir.Db, rvalue: Rvalue) -> void throws never {
    baml.sys.panic("write_rvalue: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::type_tag_name @ d9be6853b
// Symbolic name for a `baml_type::typetag` constant in `is_type_tag` renders.
// Class tags (`CLASS_BASE + n`) and anything unrecognized print numerically.
// The full tag set is named for robustness, though the only MIR producer
// today (`emit_is_type_tag_branch`) emits `LIST`/`MAP`.
function type_tag_name(tag: int) -> string throws never {
    baml.sys.panic("type_tag_name: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_operand @ d9be6853b
function write_operand(f: string[], db: root.hir.Db, operand: Operand) -> void throws never {
    baml.sys.panic("write_operand: not ported (U1)")
}

// port: baml_compiler2_mir/src/pretty.rs::write_constant @ d9be6853b
function write_constant(f: string[], db: root.hir.Db, constant: Constant) -> void throws never {
    baml.sys.panic("write_constant: not ported (U1)")
}
