// port: baml_syntax/src/nodes/exprs.rs @ d9be6853b
// Generated once by a porting script; edit by hand from here on.

type AnyExpr = PathExpr
    | GenericApplyExpr
    | LiteralExpr
    | StringLit
    | BacktickString
    | FieldAccessExpr
    | OptionalFieldAccessExpr
    | UpcastExpr
    | QualifiedPath
    | SpecExpr
    | EnvAccessExpr
    | CallExpr
    | OptionalCallExpr
    | IndexExpr
    | OptionalIndexExpr
    | TaggedTemplateExpr
    | BinaryExpr
    | IsExpr
    | UnaryExpr
    | AwaitExpr
    | SpawnExpr
    | CatchExpr
    | ThrowExpr
    | ReturnExpr
    | BreakExpr
    | ContinueExpr
    | ParenExpr
    | TupleExpr
    | TupleFieldExpr
    | Block
    | IfExpr
    | IfLetExpr
    | MatchExpr
    | LambdaExpr
    | ArrayLiteral
    | MapLiteral
    | ObjectLiteral
    | Bogus;

// A name: an identifier, a contextual keyword, or a reserved word in a
// position that accepts it.
class Name {
    span: TokenRange,
    token: int,
}

// `x`, `user.name`, `baml.HttpMethod.Get` — what the segments refer to is
// decided by name resolution, not the parser.
class PathExpr {
    span: TokenRange,
    head: Name,
    segments: PathSegment[],
}

// `.name` after a path head, in expressions, types and attribute names
// alike. A dot with nothing after it is a segment with a missing name — a
// trailing dot is never valid, so the shape leaves no silent place for one.
class PathSegment {
    dot: int,
    name: Name | Missing,
}

// `foo<T>`, `a.b<T>`, `f().g<T>`.
class GenericApplyExpr {
    span: TokenRange,
    base: AnyExpr,
    args: GenericArgs,
}

// `1`, `1.5`, `10n`, `true`, `false`, `null`.
class LiteralExpr {
    span: TokenRange,
    token: int,
}

// `"…"`, `r"…"`, `b"…"`, or the removed `#"…"#`; one token each.
class StringLit {
    span: TokenRange,
    token: int,
}

// `expr.name` on a computed base (`f().x`, `a[0].x`).
class FieldAccessExpr {
    span: TokenRange,
    base: AnyExpr,
    dot: int,
    name: Name | Missing,
}

// `expr?.name`
class OptionalFieldAccessExpr {
    span: TokenRange,
    base: AnyExpr,
    qdot: int,
    name: Name | Missing,
}

// `expr.as<T>`
class UpcastExpr {
    span: TokenRange,
    base: AnyExpr,
    dot: int,
    as_kw: int,
    args: GenericArgs | Missing,
}

// `F@spec`, `F@stream`, …
class SpecExpr {
    span: TokenRange,
    base: AnyExpr,
    at: int,
    selector: int | Missing,
}

// `env.NAME`
class EnvAccessExpr {
    span: TokenRange,
    env: int,
    dot: int,
    name: Name | Missing,
}

class CallExpr {
    span: TokenRange,
    callee: AnyExpr,
    args: ArgList,
}

class ArgList {
    span: TokenRange,
    l: int,
    args: SepItem<Arg>[],
    r: int | Missing,
}

// `value` or `label = value`.
class Arg {
    span: TokenRange,
    label: ArgLabel?,
    value: AnyExpr | Missing,
}

class ArgLabel {
    name: Name,
    eq: int,
}

// `f?.(args)`
class OptionalCallExpr {
    span: TokenRange,
    callee: AnyExpr,
    qdot: int,
    args: ArgList,
}

class IndexExpr {
    span: TokenRange,
    base: AnyExpr,
    l: int,
    index: AnyExpr | Missing,
    r: int | Missing,
}

// `a?.[i]`
class OptionalIndexExpr {
    span: TokenRange,
    base: AnyExpr,
    qdot: int,
    l: int,
    index: AnyExpr | Missing,
    r: int | Missing,
}

// `` tag`…` ``
class TaggedTemplateExpr {
    span: TokenRange,
    tag: AnyExpr,
    template: BacktickString,
}

// `lhs op rhs`, assignment included.
class BinaryExpr {
    span: TokenRange,
    lhs: AnyExpr,
    op: BinaryOpTok,
    rhs: AnyExpr | Missing,
}

// `expr is pattern`
class IsExpr {
    span: TokenRange,
    expr: AnyExpr,
    is_kw: int,
    pattern: AnyPattern | Missing,
}

// `-x`, `!x`, `~x`, `++x`, `--x`; the operator is
// [`UnaryOp::from_kind`](crate::ops::UnaryOp::from_kind) of the token.
class UnaryExpr {
    span: TokenRange,
    op: int,
    operand: AnyExpr | Missing,
}

class AwaitExpr {
    span: TokenRange,
    kw: int,
    operand: AnyExpr | Missing,
}

// `spawn name with a, b { … }`
class SpawnExpr {
    span: TokenRange,
    kw: int,
    name: AnyExpr?,
    with: WithClause?,
    body: Block | Missing,
}

// `expr catch (e) { … } catch_all (e) { … }`
class CatchExpr {
    span: TokenRange,
    body: AnyExpr,
    clauses: CatchClause[],
}

class CatchClause {
    span: TokenRange,
    kw: int,
    l: int | Missing,
    binding: Name | Missing,
    trace: TraceBinding?,
    r: int | Missing,
    lbrace: int | Missing,
    arms: CatchArm[],
    rbrace: int | Missing,
}

// `, trace` — the stack-trace binding of a catch clause.
class TraceBinding {
    comma: int,
    name: Name | Missing,
}

class CatchArm {
    span: TokenRange,
    pattern: AnyPattern | Missing,
    arrow: int | Missing,
    body: AnyExpr | Missing,
    comma: int?,
}

// `throw payload` — a diverging expression; in statement position it is an
// `ExprStmt`. The payload is required.
class ThrowExpr {
    span: TokenRange,
    kw: int,
    payload: AnyExpr | Missing,
}

// `return` or `return value` — diverging; a statement is an `ExprStmt`.
class ReturnExpr {
    span: TokenRange,
    kw: int,
    value: AnyExpr?,
}

class BreakExpr {
    span: TokenRange,
    kw: int,
}

class ContinueExpr {
    span: TokenRange,
    kw: int,
}

class ParenExpr {
    span: TokenRange,
    l: int,
    inner: AnyExpr | Missing,
    r: int | Missing,
}

// `{ stmt; stmt; tail }` — the tail is the final expression with no `;`,
// the block's value.
class Block {
    span: TokenRange,
    l: int,
    stmts: AnyStmt[],
    tail: AnyExpr?,
    r: int | Missing,
}

// `if cond { … } else …` — `if (c)` keeps its parentheses as a
// [`ParenExpr`] condition.
class IfExpr {
    span: TokenRange,
    kw: int,
    cond: AnyExpr | Missing,
    then_branch: Block | Missing,
    else_branch: ElseBranch?,
}

class ElseBranch {
    kw: int,
    body: AnyElse | Missing,
}

type AnyElse = Block | IfExpr | IfLetExpr | Bogus;

// `if let pattern = scrutinee { … } else …`
class IfLetExpr {
    span: TokenRange,
    kw: int,
    introducer: int,
    pattern: AnyPattern | Missing,
    eq: int | Missing,
    scrutinee: AnyExpr | Missing,
    then_branch: Block | Missing,
    else_branch: ElseBranch?,
}

class MatchExpr {
    span: TokenRange,
    kw: int,
    scrutinee: AnyMatchScrutinee | Missing,
    l: int | Missing,
    arms: MatchArm[],
    r: int | Missing,
}

type AnyMatchScrutinee = MatchParen | AnyExpr | Bogus;

class MatchParen {
    span: TokenRange,
    l: int,
    expr: AnyExpr | Missing,
    ascription: TypeAscription?,
    r: int | Missing,
}

class MatchArm {
    span: TokenRange,
    pattern: AnyPattern | Missing,
    guard: MatchGuard?,
    arrow: int | Missing,
    body: AnyExpr | Missing,
    comma: int?,
}

class MatchGuard {
    kw: int,
    cond: AnyExpr | Missing,
}

// `(params) -> R throws E { … }`. Generic parameters on a lambda are an
// error, kept as [`Bogus`] so they stay in the tree.
class LambdaExpr {
    span: TokenRange,
    rejected_generics: Bogus?,
    params: ParamList,
    arrow: int | Missing,
    ret: AnyType?,
    throws_: ThrowsClause?,
    body: Block | Missing,
}

// `[a, b]` — commas between elements are optional.
class ArrayLiteral {
    span: TokenRange,
    l: int,
    elements: ArrayElement[],
    r: int | Missing,
}

class ArrayElement {
    value: AnyExpr,
    comma: int?,
}

// `map { k: v }` or `{ "k": v }`.
class MapLiteral {
    span: TokenRange,
    map_kw: int?,
    l: int,
    entries: MapEntry[],
    r: int | Missing,
}

class MapEntry {
    span: TokenRange,
    key: AnyExpr,
    colon: int | Missing,
    value: AnyExpr | Missing,
    comma: int?,
}

// `Point { x: 1, ...rest }`
class ObjectLiteral {
    span: TokenRange,
    ctor: AnyObjectCtor,
    l: int,
    members: AnyObjectMember[],
    r: int | Missing,
}

type AnyObjectCtor = PathExpr | GenericApplyExpr | Bogus;

type AnyObjectMember = ObjectField | SpreadElement | Bogus;

// `key: value`, or the shorthand `key`.
class ObjectField {
    span: TokenRange,
    key: AnyObjectKey,
    value: FieldValue?,
    comma: int?,
}

type AnyObjectKey = DottedName | StringLit | BacktickString | Bogus;

class FieldValue {
    colon: int,
    value: AnyExpr | Missing,
}

// `...expr`
class SpreadElement {
    span: TokenRange,
    dots: int,
    value: AnyExpr | Missing,
    comma: int?,
}

class TupleExpr {
    span: TokenRange,
    l: int,
    elements: SepItem<AnyExpr>[],
    r: int | Missing,
}

class TupleFieldExpr {
    span: TokenRange,
    base: AnyExpr,
    dot: int,
    slot: int,
}
