// port: baml_compiler2_ast/src/ast.rs @ d9be6853b
// Generated once by a porting script; edit by hand from here on.

// Raw attribute from CST — not yet validated.
class RawAttribute {
  name: string,
  args: RawAttributeArg[],
  span: root.syntax.TextRange,
}

class RawAttributeArg {
  key: string?,
  value: string,
  span: root.syntax.TextRange,
}

// Full recursive type expression — all structural content in memory.
// 
// Corresponds to `TypeRef` in `baml_compiler_hir/src/type_ref.rs` but lives
// in the AST layer (before any name resolution). CST → `TypeExpr` conversion
// happens once during `lower_file` and is never repeated.
type TypeExprKind = TypeExprKindPath | TypeExprKindAssociatedTypeProjection | TypeExprKindInt | TypeExprKindBigint | TypeExprKindFloat | TypeExprKindString | TypeExprKindBool | TypeExprKindNull | TypeExprKindNever | TypeExprKindUint8Array | TypeExprKindMedia | TypeExprKindOptional | TypeExprKindList | TypeExprKindMap | TypeExprKindUnion | TypeExprKindTuple | TypeExprKindLiteral | TypeExprKindFunction | TypeExprKindUnknown | TypeExprKindType | TypeExprKindRust | TypeExprKindError | TypeExprKindMissing | TypeExprKindInfer

class TypeExprKindPath {
  path: root.base.Path,
  generic_args: TypeExpr[],
  associated_type_bindings: AssociatedTypeBinding[],
}

class TypeExprKindAssociatedTypeProjection {
  base: TypeExpr,
  interface_: TypeExpr?,
  member: string,
}

class TypeExprKindInt {
}

class TypeExprKindBigint {
}

class TypeExprKindFloat {
}

class TypeExprKindString {
}

class TypeExprKindBool {
}

class TypeExprKindNull {
}

class TypeExprKindNever {
}

class TypeExprKindUint8Array {
}

class TypeExprKindMedia {
  kind: root.base.MediaKind,
}

class TypeExprKindOptional {
  inner: TypeExpr,
}

class TypeExprKindList {
  inner: TypeExpr,
}

class TypeExprKindMap {
  key: TypeExpr,
  value: TypeExpr,
}

class TypeExprKindUnion {
  variants: TypeExpr[],
}

class TypeExprKindTuple {
  elements: TypeExpr[],
}

class TypeExprKindLiteral {
  value: root.base.Literal,
}

class TypeExprKindFunction {
  params: FunctionTypeParam[],
  ret: TypeExpr,
  throws_: TypeExpr?,
}

class TypeExprKindUnknown {
}

class TypeExprKindType {
}

class TypeExprKindRust {
}

class TypeExprKindError {
}

class TypeExprKindMissing {
}

class TypeExprKindInfer {
}

// A type expression node paired with its source span. Every node in the tree
// is spanned (recursively, via the `Box<TypeExpr>`/`Vec<TypeExpr>` children of
// [`TypeExprKind`]), so a diagnostic about any sub-type (e.g. an unresolved
// member of a union/map) can point exactly at it.
// 
// Equality and hashing are **structural** — they ignore `span`. Two occurrences
// of the same type compare equal regardless of source position; `span` is
// diagnostic metadata, not part of type identity (this matches the pre-spanning
// behavior and keeps Salsa early-cutoff / dedup position-insensitive).
class TypeExpr {
  kind: TypeExprKind,
  span: root.syntax.TextRange,
}

// A parameter in a function type expression.
class FunctionTypeParam {
  name: string?,
  optional: bool,
  ty: TypeExpr,
}

// Named associated type binding used inside type applications:
// `Iterator<Item = int>`.
class AssociatedTypeBinding {
  name: string,
  ty: TypeExpr,
}

// A generic type parameter declaration, paired with the `&`-separated bounds
// it was declared with (`<T>` → `bounds = []`; `<T extends A & B>` → `bounds =
// [A, B]`).
// 
// The bound set is a **conjunction**: an argument for this parameter must
// satisfy every entry. Holding the name and its bounds together makes a length
// mismatch between the two unrepresentable.
// 
// Bounds are `TypeExpr`s so generic parents like `Container<int>` round-trip;
// that each must denote an *interface* — never an interface-existential type,
// see `TYPE_SYSTEM.md` "Generics on Functions" — is enforced where they are
// lowered to constraints.
class GenericParam {
  name: string,
  bounds: TypeExpr[],
  name_span: root.syntax.TextRange,
}

// Full expression body — owned arena of expressions, statements,
// and patterns. Modeled after `ExprBody` in `body.rs`.
class ExprBody {
  exprs: Expr[],
  stmts: Stmt[],
  patterns: Pattern[],
  match_arms: MatchArm[],
  catch_arms: CatchArm[],
  type_annotations: TypeExpr[],
  tag_values: int[],
  root_expr: int?,
}

// Parallel span storage for an `ExprBody` — maps arena IDs to source ranges.
// Separated so semantic queries (type checking) can ignore spans and get
// Salsa early-cutoff on whitespace changes.
class AstSourceMap {
  expr_spans: root.syntax.TextRange[],
  stmt_spans: root.syntax.TextRange[],
  pattern_spans: root.syntax.TextRange[],
  bind_name_spans: map<int, root.syntax.TextRange>,
  type_binding_name_spans: map<int, root.syntax.TextRange>,
  match_arm_spans: root.syntax.TextRange[],
  type_annotation_spans: root.syntax.TextRange[],
  catch_arm_spans: root.syntax.TextRange[],
  member_access_member_spans: map<int, root.syntax.TextRange>,
  path_segment_spans: map<int, root.syntax.TextRange[]>,
  // deviation: Rust keys by (expr, arg index); BAML tuples are not hashable yet.
  call_arg_label_spans: map<int, map<int, root.syntax.TextRange>>,
  // deviation: Rust keys by (expr, field index); BAML tuples are not hashable yet.
  object_field_name_spans: map<int, map<int, root.syntax.TextRange>>,
  lambda_parameter_spans: map<int, root.syntax.TextRange[]>,
  synthetic_exprs: map<int, bool>,
  synthetic_stmts: map<int, bool>,
  synthetic_patterns: map<int, bool>,
}

// How a class property value was written in source.
enum PropertySyntax {
  Explicit
  Shorthand
}

class ObjectExprField {
  name: string,
  value: int,
  syntax: PropertySyntax,
}

class MapExprEntry {
  key: int,
  value: int,
}

// Expressions — modeled after `Expr` in `body.rs`.
type Expr = ExprLiteral | ExprByteStringLiteral | ExprNull | ExprPath | ExprGenericApply | ExprIf | ExprIfLet | ExprMatch | ExprIs | ExprCatch | ExprThrow | ExprReturn | ExprAwait | ExprBinary | ExprUnary | ExprCall | ExprObject | ExprArray | ExprTuple | ExprMap | ExprBlock | ExprMemberAccess | ExprUpcast | ExprQualifiedPath | ExprOptionalMemberAccess | ExprIndex | ExprLambda | ExprOptionalIndex | ExprOptionalCall | ExprOptionalChain | ExprTemplate | ExprMissing

class ExprLiteral {
  value: root.base.Literal,
}

class ExprByteStringLiteral {
  value: int[],
}

class ExprNull {
}

class ExprPath {
  value: root.base.Path,
}

class ExprGenericApply {
  base: int,
  type_args: TypeExpr[],
}

class ExprIf {
  condition: int,
  then_branch: int,
  else_branch: int?,
}

class ExprIfLet {
  pattern: int,
  scrutinee: int,
  then_branch: int,
  else_branch: int?,
}

class ExprMatch {
  scrutinee: int,
  scrutinee_type: int?,
  arms: int[],
}

class ExprIs {
  scrutinee: int,
  pattern: int,
}

class ExprCatch {
  base: int,
  clause: CatchClause,
}

class ExprThrow {
  value: int,
}

class ExprReturn {
  value: int?,
}

class ExprAwait {
  future: int,
}

class ExprBinary {
  op: BinaryOp,
  lhs: int,
  rhs: int,
}

class ExprUnary {
  op: UnaryOp,
  expr: int,
}

class ExprCall {
  callee: int,
  type_args: TypeExpr[],
  args: CallArg[],
}

class ExprObject {
  type_name: root.base.Path,
  type_args: TypeExpr[],
  fields: ObjectExprField[],
  spreads: SpreadField[],
}

class ExprArray {
  elements: int[],
}

class ExprTuple {
  elements: int[],
}

class ExprMap {
  entries: MapExprEntry[],
}

class ExprBlock {
  stmts: int[],
  tail_expr: int?,
}

class ExprMemberAccess {
  base: int,
  member: string,
}

class ExprUpcast {
  base: int,
  target: TypeExpr,
}

class ExprQualifiedPath {
  qself: TypeExpr,
  interface_: TypeExpr,
  member: string,
}

class ExprOptionalMemberAccess {
  base: int,
  member: string,
}

class ExprIndex {
  base: int,
  index: int,
}

class ExprLambda {
  value: LambdaDef,
}

class ExprOptionalIndex {
  base: int,
  index: int,
}

class ExprOptionalCall {
  callee: int,
  args: CallArg[],
}

class ExprOptionalChain {
  expr: int,
}

class ExprTemplate {
  tag: TemplateTag,
  segments: TemplateSegment[],
}

class ExprMissing {
}

// Which BEP-049 backtick form an [`Expr::Template`] is, plus the per-form
// payload needed to realize it.
type TemplateTag = TemplateTagDefault | TemplateTagCustom

class TemplateTagDefault {
  elaborated: int,
}

class TemplateTagCustom {
  tag: int,
  body: int,
}

// One segment of an [`Expr::Template`] body. Parallel to `BacktickSegment`
// in the CST layer, but every sub-expression is already lowered.
type TemplateSegment = TemplateSegmentText | TemplateSegmentInterp | TemplateSegmentEffect | TemplateSegmentFor | TemplateSegmentCStyleFor | TemplateSegmentIf

class TemplateSegmentText {
  value: string,
}

class TemplateSegmentInterp {
  value: int,
}

class TemplateSegmentEffect {
  block: int,
  stmts: int[],
}

class TemplateSegmentFor {
  binding: int,
  collection: int,
  body: TemplateSegment[],
}

class TemplateSegmentCStyleFor {
  init: int,
  cond: int,
  step: int?,
  body: TemplateSegment[],
}

class TemplateSegmentIf {
  branches: TemplateIfBranch[],
  else_body: TemplateSegment[]?,
}

class TemplateIfBranch {
  condition: int,
  body: TemplateSegment[],
}

class CallArg {
  label: string?,
  expr: int,
}

// Statements — modeled after `Stmt` in `body.rs`.
type Stmt = StmtExpr | StmtTypeBinding | StmtLet | StmtWhile | StmtWhileLet | StmtFor | StmtReturn | StmtThrow | StmtBreak | StmtContinue | StmtDefer | StmtAssign | StmtAssignOp | StmtMissing | StmtHeaderComment

class StmtExpr {
  value: int,
}

class StmtTypeBinding {
  name: string,
  operand: int,
  bounds: TypeExpr[],
  else_branch: int?,
}

class StmtLet {
  pattern: int,
  initializer: int?,
  origin: LetOrigin,
  else_branch: int?,
}

class StmtWhile {
  condition: int,
  body: int,
  after: int?,
  origin: LoopOrigin,
}

class StmtWhileLet {
  pattern: int,
  scrutinee: int,
  body: int,
}

class StmtFor {
  binding: int,
  collection: int,
  body: int,
}

class StmtReturn {
  value: int?,
}

class StmtThrow {
  value: int,
}

class StmtBreak {
}

class StmtContinue {
}

class StmtDefer {
  body: int,
}

class StmtAssign {
  target: int,
  value: int,
}

class StmtAssignOp {
  target: int,
  op: AssignOp,
  value: int,
}

class StmtMissing {
}

class StmtHeaderComment {
  name: string,
  level: int,
}

// A pattern in the AST.
// 
// One flat enum. Atoms (`Wildcard`, `Bind`, `Class`, `Type`) describe a
// single shape; the only combinator (`Or`) combines other patterns.
// 
// Lowering invariants:
// - `_` always lowers to [`Pattern::Wildcard`] — never `Bind { name: "_" }`.
// - 1-element `Or` is NOT allocated; it collapses to the inner pattern.
// So if you see `Or(parts)`, `parts.len() >= 2`.
// - The `: T` annotation in `let x: T` is carried as the bind's `subpat`
// slot (see [`Pattern::Bind`]) and likewise as `Pattern::Array`'s
// `ascription` field for `[…]: T`. `:` is only valid after `let x` or
// `[…]` — it is rejected on `_`, `Class { … }`, bare types, and
// Or-patterns.
type Pattern = PatternWildcard | PatternBind | PatternClass | PatternArray | PatternTuple | PatternType | PatternOr

class PatternWildcard {
}

class PatternBind {
  name: string,
  subpat: int?,
}

class PatternClass {
  class_: string[],
  generic_args: TypeExpr[],
  associated_type_bindings: AssociatedTypeBinding[],
  fields: FieldPat[],
}

class PatternArray {
  prefix: int[],
  rest: ArrayRestPat?,
  suffix: int[],
  ascription: TypeExpr?,
}

class PatternTuple {
  value: int[],
}

class PatternType {
  value: TypeExpr,
}

class PatternOr {
  value: int[],
}

// Single field inside a class destructure pattern.
// 
// Shorthand `{ f }` lowers to `FieldPat { field: f, pat: <Bind { name: f }> }`,
// so consumers never see the missing-pattern shape.
class FieldPat {
  field: string,
  field_span: root.syntax.TextRange,
  pat: int,
}

class ArrayRestPat {
  pat: int?,
}

class MatchArm {
  pattern: int,
  guard: int?,
  body: int,
}

// Every catch clause creates its own protected expression and handler. The
// three keywords select the [`CatchClauseKind::requires_error_coverage`]
// and [`CatchClauseKind::wildcard_traps_panics`] policies.
enum CatchClauseKind {
  Catch
  CatchAll
  CatchAllPanics
}

class CatchClause {
  kind: CatchClauseKind,
  binding: int,
  stack_trace_binding: int?,
  arms: int[],
}

class CatchArm {
  pattern: int,
  body: int,
}

class SpreadField {
  expr: int,
  position: int,
}

enum LetOrigin {
  Source
  Client
}

enum FunctionOrigin {
  UserDefined
  Companion
  Internal
  AutoDerive
  TestInitializer
}

class FunctionMetadata {
  trace_passthrough: bool,
  explicit_trace_passthrough: bool,
  origin: FunctionOrigin,
  is_language_internal: bool,
}

// The source form a [`Stmt::While`] was written in.
type LoopOrigin = LoopOriginWhile | LoopOriginFor

class LoopOriginWhile {
}

class LoopOriginFor {
  init: int,
}

// Binary operators — matches those supported in `body.rs`.
enum BinaryOp {
  Add
  Sub
  Mul
  Div
  Mod
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  And
  Or
  BitAnd
  BitOr
  BitXor
  Shl
  Shr
  NullCoalesce
}

enum UnaryOp {
  Not
  Neg
}

// Compound assignment operators.
enum AssignOp {
  Add
  Sub
  Mul
  Div
  Mod
  BitAnd
  BitOr
  BitXor
  Shl
  Shr
}

// Top-level item — the output unit of CST → AST lowering.
type Item = ItemFunction | ItemClass | ItemEnum | ItemInterface | ItemTypeAlias | ItemLet | ItemImplementsFor

class ItemFunction {
  value: FunctionDef,
}

class ItemClass {
  value: ClassDef,
}

class ItemEnum {
  value: EnumDef,
}

class ItemInterface {
  value: InterfaceDef,
}

class ItemTypeAlias {
  value: TypeAliasDef,
}

class ItemLet {
  value: LetDef,
}

class ItemImplementsFor {
  value: ImplementsForDef,
}

type DeclarativeMeta = DeclarativeMetaLlm

class DeclarativeMetaLlm {
  value: LlmBodyDef,
}

// A trace hook attached with `/// baml:$trace=path.to.hook`.
class TraceHookDirective {
  path: string[],
  span: root.syntax.TextRange,
}

class FunctionDef {
  name: string,
  generic_params: GenericParam[],
  params: Param[],
  defaults: FunctionDefaults,
  return_type: TypeExpr?,
  throws_: TypeExpr?,
  body: FunctionBodyDef?,
  declarative_meta: DeclarativeMeta?,
  metadata: FunctionMetadata,
  attributes: RawAttribute[],
  docstring: string?,
  header_title: string?,
  is_tagged_template_tag: bool,
  directives: NativeDirectives,
  trace_hook: TraceHookDirective?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

// A `//baml:` directive a native function is declared with, read by the
// builtin codegen: how its `$rust_function` glue is bound.
enum NativeDirective {
  MutSelf
  Vm
  MutVm
  MayYield
  Fallible
  LocalTwin
}

// The set of [`NativeDirective`]s written on a function. Each is a fact of
// the declaration; the codegen combines them.
class NativeDirectives {
  value: int,
}

// What produced a [`LambdaDef`], where that changes how TIR types it.
// 
// Replaces matching on a synthetic `name` string, which could not distinguish
// the cases without agreeing on a magic constant at a distance.
enum LambdaKind {
  Anonymous
  Spawn
}

// An anonymous function *value*, written inside an expression body.
// 
// Distinct from [`FunctionDef`], which describes a declared item. A lambda has
// no name, no generic parameters (the parser rejects them), no attributes, no
// docstring and no declarative metadata, and its body is always an expression
// body — never a `$rust_function` builtin. Carrying only those fields keeps
// those states unrepresentable rather than filling them with synthetic values
// that every reader then has to know to ignore.
class LambdaDef {
  kind: LambdaKind,
  params: Param[],
  defaults: FunctionDefaults,
  return_type: TypeExpr?,
  throws_: TypeExpr?,
  body: int?,
  span: root.syntax.TextRange,
}

class FunctionDefaults {
  exprs: ExprBody,
  source_map: AstSourceMap,
}

type FunctionBodyDef = FunctionBodyDefExpr | FunctionBodyDefBuiltin

class FunctionBodyDefExpr {
  v0: ExprBody,
  v1: AstSourceMap,
}

class FunctionBodyDefBuiltin {
  value: BuiltinKind,
}

// What kind of builtin a function is.
enum BuiltinKind {
  Vm
  Io
  Intrinsic
  AwaitAny
  Spawn
}

// Source geometry of an LLM function's prompt literal.
class LlmPromptSpans {
  literal: root.syntax.TextRange,
  code: root.syntax.TextRange[],
}

class LlmBodyDef {
  client_: string?,
  companion_bodies: (string, (ExprBody, AstSourceMap))[],
  prompt_spans: LlmPromptSpans?,
  prompt_segments: TemplateSegment[],
  has_tools: bool,
  span: root.syntax.TextRange,
}

class Param {
  name: string,
  type_expr: TypeExpr?,
  default: int?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

class DefaultExprId {
  value: int,
}

class ClassDef {
  name: string,
  generic_params: GenericParam[],
  fields: FieldDef[],
  methods: FunctionDef[],
  attributes: RawAttribute[],
  docstring: string?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

// Definition of an `interface` declaration (BEP-044).
// 
// Interfaces declare a contract over fields and methods. Types opt in to
// the contract with an `implements` block ([`ImplementsForDef`]).
class InterfaceDef {
  name: string,
  generic_params: GenericParam[],
  requires_: TypeExpr[],
  fields: FieldDef[],
  associated_types: AssociatedTypeDef[],
  required_methods: MethodSigDef[],
  default_methods: FunctionDef[],
  attributes: RawAttribute[],
  docstring: string?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

// Method signature declared in an interface body without a body — i.e., a
// required method. Mirrors [`FunctionDef`] minus the body.
class MethodSigDef {
  name: string,
  generic_params: GenericParam[],
  params: Param[],
  defaults: FunctionDefaults,
  return_type: TypeExpr?,
  throws_: TypeExpr?,
  attributes: RawAttribute[],
  docstring: string?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

class InterfaceFieldLinkDef {
  interface_field: string,
  class_field: string,
  span: root.syntax.TextRange,
  interface_field_span: root.syntax.TextRange,
  class_field_span: root.syntax.TextRange,
}

// Where an `implements` block was written. The in-body spelling is
// shorthand for the out-of-body one (`TYPE_SYSTEM.md`, "Interface
// Implementations"); the origin is kept for the rules that read it — an
// interface with fields can only be implemented in-body — and must not
// influence resolution, dispatch or coherence.
enum ImplOrigin {
  InBody
  OutOfBody
}

// An `implements` block (BEP-044), in either spelling: `implements I for T
// { ... }` at the top level, or `implements I { ... }` inside the body of
// the class it is for.
class ImplementsForDef {
  generic_params: GenericParam[],
  interface_target: TypeExpr,
  for_target: TypeExpr,
  field_links: InterfaceFieldLinkDef[],
  associated_type_bindings: AssociatedTypeBindingDef[],
  methods: FunctionDef[],
  origin: ImplOrigin,
  span: root.syntax.TextRange,
  docstring: string?,
}

class AssociatedTypeDef {
  name: string,
  bound: TypeExpr?,
  default: TypeExpr?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

class AssociatedTypeBindingDef {
  name: string,
  type_expr: TypeExpr?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

class FieldDef {
  name: string,
  type_expr: TypeExpr,
  attributes: RawAttribute[],
  docstring: string?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

class EnumDef {
  name: string,
  variants: VariantDef[],
  attributes: RawAttribute[],
  docstring: string?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

class VariantDef {
  name: string,
  attributes: RawAttribute[],
  docstring: string?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

class TypeAliasDef {
  name: string,
  type_expr: TypeExpr?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
  docstring: string?,
}

// A top-level let binding: a global variable (`const NAME: T = expr;` at file
// scope), a compiler-generated client binding (`client Name = expr;`), or a
// Session submission's persisted root binding. All three share the `$init`
// pipeline: the initializer runs once, before any request, and the binding is
// immutable afterwards.
// Carries an optional `ExprBody` initializer that flows through TIR type-checking.
class LetDef {
  name: string,
  type_annotation: TypeExpr?,
  initializer: (ExprBody, AstSourceMap)?,
  origin: LetOrigin,
  docstring: string?,
  span: root.syntax.TextRange,
  name_span: root.syntax.TextRange,
}

