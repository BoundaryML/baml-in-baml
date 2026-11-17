// port: baml_syntax/src/nodes/items.rs @ d9be6853b
// Generated once by a porting script; edit by hand from here on.

class SourceFile {
  span: TokenRange,
  items: AnyItem[],
}

type AnyItem = FunctionDef | ClassDef | EnumDef | InterfaceDef | ImplementsFor | TypeAliasDef | LetItem | TypeBindingStmt | ClientValueDef | TestDef | RemovedItem | Bogus

// A file-scope `let`/`const` binding: the statement, documented. (In a body
// the statement stands alone; a `///` line there is an error.)
class LetItem {
  span: TokenRange,
  docs: AnyDoc[],
  stmt: LetStmt,
}

// `function name<G>(params) -> R throws E { body }`. Also a class method,
// an interface default method, and an implements-block method.
class FunctionDef {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: Name | Missing,
  generics: GenericParamList?,
  params: ParamList | Missing,
  ret: ReturnType | Missing,
  throws_clause: ThrowsClause?,
  body: AnyFunctionBody | Missing,
}

// `-> T` (or `=> T`, accepted in its place).
class ReturnType {
  span: TokenRange,
  arrow: int,
  ty: AnyType | Missing,
}

class ThrowsClause {
  span: TokenRange,
  kw: int,
  ty: AnyType | Missing,
}

type AnyFunctionBody = Block | LlmBody | Bogus

// `{ client: …  prompt: …  tools: … }`, in any order (duplicates are a
// lowering diagnostic).
class LlmBody {
  span: TokenRange,
  l: int,
  fields: AnyLlmField[],
  r: int | Missing,
}

type AnyLlmField = ClientField | PromptField | ToolsField | Bogus

class ClientField {
  span: TokenRange,
  kw: int,
  colon: int | Missing,
  value: AnyExpr | Missing,
}

class PromptField {
  span: TokenRange,
  kw: int,
  colon: int | Missing,
  value: AnyStringLike | Missing,
}

class ToolsField {
  span: TokenRange,
  kw: int,
  colon: int | Missing,
  value: AnyExpr | Missing,
}

type AnyStringLike = StringLit | BacktickString | Bogus

class ClassDef {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: Name | Missing,
  generics: GenericParamList?,
  l: int | Missing,
  members: AnyClassMember[],
  r: int | Missing,
}

type AnyClassMember = Field | FunctionDef | ImplementsBlock | BlockAttr | Bogus

// `name: T @attr…,` — the colon may be omitted (`name T`), and the member
// owns its separator.
class Field {
  span: TokenRange,
  docs: AnyDoc[],
  name: Name,
  colon: int?,
  ty: AnyType | Missing,
  attrs: Attribute[],
  sep: int?,
}

class EnumDef {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: Name | Missing,
  l: int | Missing,
  members: AnyEnumMember[],
  r: int | Missing,
}

type AnyEnumMember = EnumVariant | BlockAttr | Bogus

class EnumVariant {
  span: TokenRange,
  docs: AnyDoc[],
  name: Name,
  attrs: Attribute[],
  sep: int?,
}

class InterfaceDef {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: Name | Missing,
  generics: GenericParamList?,
  requires_clause: RequiresClause?,
  l: int | Missing,
  members: AnyInterfaceMember[],
  r: int | Missing,
}

class RequiresClause {
  span: TokenRange,
  kw: int,
  types: SepItem<AnyType>[] | Missing,
}

type AnyInterfaceMember = MethodSig | FunctionDef | Field | AssocTypeDecl | BlockAttr | Bogus

// A required method: a signature without a body.
class MethodSig {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: Name | Missing,
  generics: GenericParamList?,
  params: ParamList | Missing,
  ret: ReturnType | Missing,
  throws_clause: ThrowsClause?,
  semi: int?,
}

// `type Item extends Bound = Default,` declared in an interface: bound and
// default both optional.
class AssocTypeDecl {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: Name | Missing,
  bound: AssocBound?,
  default: AssocDefault?,
  sep: int?,
}

class AssocBound {
  kw: int,
  ty: AnyType | Missing,
}

class AssocDefault {
  eq: int,
  ty: AnyType | Missing,
}

// `type Item = T,` defined in an implementation: the binding is required.
class AssocTypeDef {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: Name | Missing,
  eq: int | Missing,
  ty: AnyType | Missing,
  sep: int?,
}

// `implements I { … }` inside a class.
class ImplementsBlock {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  target: AnyType | Missing,
  l: int | Missing,
  members: AnyImplMember[],
  r: int | Missing,
}

// `implements<G> I for T { … }` at the top level.
class ImplementsFor {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  generics: GenericParamList?,
  target: AnyType | Missing,
  for_kw: int | Missing,
  self_ty: AnyType | Missing,
  l: int | Missing,
  members: AnyImplMember[],
  r: int | Missing,
}

type AnyImplMember = FunctionDef | AssocTypeDef | InterfaceFieldLink | Field | Bogus

// `interface_field as class_field,`
class InterfaceFieldLink {
  span: TokenRange,
  docs: AnyDoc[],
  iface_field: Name,
  as_kw: int | Missing,
  class_field: Name | Missing,
  sep: int?,
}

class TypeAliasDef {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: Name | Missing,
  eq: int | Missing,
  ty: AnyType | Missing,
  semi: int?,
}

// `client Name = <expr>;`
class ClientValueDef {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: Name,
  eq: int,
  value: AnyExpr | Missing,
  semi: int?,
}

// `test "name" with … { … }` / `testset …` — also a statement inside a
// testset's block.
class TestDef {
  span: TokenRange,
  docs: AnyDoc[],
  kw: int,
  name: AnyExpr | Missing,
  with: WithClause?,
  body: Block | Missing,
}

// `with a, b` — on tests, testsets and `spawn`.
class WithClause {
  span: TokenRange,
  kw: int,
  items: SepItem<AnyExpr>[],
}

// A removed item form (`client<llm> X { … }`, `retry_policy`,
// `template_string`, `generator`, `type_builder`, `dynamic class`, a legacy
// `test X { functions … }`). Kept as token ranges so its diagnostic can point
// at it and name it; it lowers to nothing. `head` is what sits between the
// keyword and the name (`<llm>`, the `class` of `dynamic class`), usually
// empty; `body` is everything after the name.
class RemovedItem {
  span: TokenRange,
  kw: int,
  head: TokenRange,
  name: Name?,
  body: TokenRange,
}

// Declaration-site `<T, U extends I>`.
class GenericParamList {
  span: TokenRange,
  l: int,
}

class GenericParam {
  span: TokenRange,
  name: Name,
  bounds: GenericParamBounds?,
}

// `extends A & B` — on a generic parameter or a `let type` binding.
class GenericParamBounds {
  span: TokenRange,
  kw: int,
  first: AnyType | Missing,
  rest: BoundArm[],
}

class BoundArm {
  and: int,
  ty: AnyType | Missing,
}

// Expression-side `foo<T, U>`.
class GenericArgs {
  span: TokenRange,
  l: int,
}

// Type-side `Foo<T, Item = U>`.
class TypeArgs {
  span: TokenRange,
  l: int,
}

type AnyTypeArg = AnyType | AssocTypeBinding | Bogus

// `Item = int` inside type arguments.
class AssocTypeBinding {
  span: TokenRange,
  name: Name,
  eq: int,
  ty: AnyType | Missing,
}

class ParamList {
  span: TokenRange,
  l: int,
}

// `name: T = default`. `self` has no type. A parameter written as a bare
// type keeps the type and misses the name.
class Param {
  span: TokenRange,
  name: Name | Missing,
  ascription: TypeAscription?,
  default: DefaultValue?,
}

// `: T` — the colon may be omitted where the grammar allows `name T`.
class TypeAscription {
  span: TokenRange,
  colon: int?,
  ty: AnyType | Missing,
}

class DefaultValue {
  span: TokenRange,
  eq: int,
  value: AnyExpr | Missing,
}

// `@name(args)` on a field or variant.
class Attribute {
  span: TokenRange,
  at: int,
  path: DottedName | Missing,
  args: AttrArgs?,
}

// `@@name(args)` on a declaration — before it, or inside its body as a
// member (the two spellings are the same attribute).
// `@@name(args)`: an attribute of the declaration whose body it is written
// in — a class, enum or interface. There is no other position for one.
class BlockAttr {
  span: TokenRange,
  at: int,
  path: DottedName | Missing,
  args: AttrArgs?,
}

// What precedes a declaration that takes `@@attrs`, in source order: its
// attributes, its `///` doc lines and its `//baml:` directives. A `///` or
// `//baml:` line is syntax the declaration owns, as in Rust, where `///` is
// an attribute; one that precedes no declaration is an error.
type AnyDoc = DocLine | Directive | HeaderLine | Bogus

// A `//#` header line directly above a function: the function's title,
// which the control-flow visualizer labels its node with. A function takes
// one; above any other declaration, or twice, it is an error (in a block it
// is a statement instead, see `HeaderStmt`).
class HeaderLine {
  span: TokenRange,
  token: int,
}

// One `///` line of a declaration's documentation. Its text is the token's
// text after the `///`, with one optional leading space; the lines of a
// declaration join with `\n`.
class DocLine {
  span: TokenRange,
  token: int,
}

// A `//baml:<name>` directive on a declaration, or a `/// baml:$trace=path`
// trace hook: an internal attribute spelled as a comment. The parser
// classifies it; a line it cannot classify is a `Bogus` with an error.
class Directive {
  span: TokenRange,
  token: int,
  kind: DirectiveKind,
}

// Which directive a [`Directive`] is.
enum DirectiveKind {
  MutSelf
  Vm
  MutVm
  MayYield
  Fallible
  TaggedString
  TracePassthrough
  LocalTwin
  Trace
}

// `a.b.c` where only names are allowed (attribute paths, object keys).
class DottedName {
  span: TokenRange,
  head: Name,
  segments: PathSegment[],
}

class AttrArgs {
  span: TokenRange,
  l: int,
}

type AnyAttrArg = StringLit | BacktickString | JinjaArg | Name | Bogus

// `{{ … }}` — a Jinja expression argument, kept as unparsed tokens.
class JinjaArg {
  span: TokenRange,
  l1: int,
  l2: int,
  tokens: TokenRange,
  r1: int | Missing,
  r2: int | Missing,
}
