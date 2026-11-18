// port: baml_syntax/src/nodes/stmts.rs @ d9be6853b
// Generated once by a porting script; edit by hand from here on.

type AnyStmt = LetStmt | TypeBindingStmt | ExprStmt | AssignStmt | EmptyStmt | DeferStmt | WhileStmt | WhileLetStmt | ForStmt | TestDef | HeaderStmt | Bogus

// An expression in statement position, with its `;` if it has one. (An
// `if`/`match` statement usually has none.)
class ExprStmt {
  span: TokenRange,
  expr: AnyExpr,
  semi: int?,
}

// `target = value;`, or a compound `target += value;`. Assignment is a
// statement: it has no value, so it is never an expression and never
// chains (`a = b = c` is an error).
class AssignStmt {
  span: TokenRange,
  target: AnyExpr,
  op: AssignOpTok,
  value: AnyExpr | Missing,
  semi: int?,
}

// A `;` with nothing before it.
class EmptyStmt {
  span: TokenRange,
  semi: int,
}

// `let pattern = init else { … };` — also a top-level global, and the
// initialiser of a C-style `for` (which owns the `;` then).
class LetStmt {
  span: TokenRange,
  introducer: int,
  pattern: AnyPattern | Missing,
  eq: int | Missing,
  init: AnyExpr | Missing,
  else_branch: LetElse?,
  semi: int?,
}

class LetElse {
  kw: int,
  block: Block | Missing,
}

// `let type T extends A & B = expr else { … };`
class TypeBindingStmt {
  span: TokenRange,
  let_kw: int,
  type_kw: int,
  name: Name | Missing,
  bounds: GenericParamBounds?,
  eq: int | Missing,
  init: AnyExpr | Missing,
  else_branch: LetElse?,
  semi: int?,
}

class DeferStmt {
  span: TokenRange,
  kw: int,
  body: Block | Missing,
}

class WhileStmt {
  span: TokenRange,
  kw: int,
  cond: AnyExpr | Missing,
  body: Block | Missing,
}

class WhileLetStmt {
  span: TokenRange,
  kw: int,
  introducer: int,
  pattern: AnyPattern | Missing,
  eq: int | Missing,
  scrutinee: AnyExpr | Missing,
  body: Block | Missing,
}

class ForStmt {
  span: TokenRange,
  kw: int,
  header: AnyForHeader | Missing,
  body: Block | Missing,
}

// The header of a `for`: the `in` form may be written bare or in
// parentheses, the C-style form always in parentheses.
type AnyForHeader = ForInHeader | ParenForInHeader | CForHeader | Bogus

// `let x in xs`
class ForInHeader {
  span: TokenRange,
  introducer: int,
  pattern: AnyPattern | Missing,
  in_kw: int | Missing,
  iter: AnyExpr | Missing,
}

// `(let x in xs)` — an opening parenthesis is always matched by a slot for
// the closing one.
class ParenForInHeader {
  span: TokenRange,
  l: int,
  header: ForInHeader,
  r: int | Missing,
}

// `(init; cond; step)` — every part optional, the parentheses required. A
// `let` initialiser's `;` is `semi1`, not the `LetStmt`'s.
class CForHeader {
  span: TokenRange,
  l: int | Missing,
  init: AnyForInit?,
  semi1: int?,
  cond: AnyExpr?,
  semi2: int?,
  step: AnyForStep?,
  r: int | Missing,
}

type AnyForInit = LetStmt | AnyExpr | Bogus

// The step of a C-style `for`: a statement position, so usually an
// assignment (`i += 1`); its `AssignStmt` has no `;`.
type AnyForStep = AssignStmt | AnyExpr | Bogus

// A `//#` header line inside a block (a section heading in the body): a
// trivia token a node owns, because here it is a statement. Directly above
// a function it is the function's title (`HeaderLine`); anywhere else —
// between the arms of a `match` included — it is an error.
class HeaderStmt {
  span: TokenRange,
  token: int,
}
