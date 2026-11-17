// port: baml_syntax/src/nodes/templates.rs @ d9be6853b
// Generated once by a porting script; edit by hand from here on.

class BacktickString {
  span: TokenRange,
  open: int,
  parts: AnyTemplatePart[],
  close: int | Missing,
}

type AnyTemplatePart = AnyTemplatePartChunk | TemplateInterp | TemplateFor | TemplateIf | Bogus

// `${ stmts; tail }` — an interpolation is a block body.
class TemplateInterp {
  span: TokenRange,
  open: int,
  stmts: AnyStmt[],
  tail: AnyExpr?,
  close: int | Missing,
}

// `${for …}` body `${endfor}`
class TemplateFor {
  span: TokenRange,
  open: TemplateForOpen,
  body: AnyTemplatePart[],
  close: TemplateEndTag | Missing,
}

class TemplateForOpen {
  span: TokenRange,
  open: int,
  kw: int,
  header: AnyForHeader | Missing,
  close: int | Missing,
}

// `${if c}` … `${else if d}` … `${else}` … `${endif}`
class TemplateIf {
  span: TokenRange,
  open: TemplateIfOpen,
  then_parts: AnyTemplatePart[],
  elifs: TemplateElif[],
  else_part: TemplateElse?,
  close: TemplateEndTag | Missing,
}

class TemplateIfOpen {
  span: TokenRange,
  open: int,
  kw: int,
  cond: AnyExpr | Missing,
  close: int | Missing,
}

// `${else if d}` and the parts it guards.
class TemplateElif {
  span: TokenRange,
  open: int,
  else_kw: int,
  if_kw: int,
  cond: AnyExpr | Missing,
  close: int | Missing,
  parts: AnyTemplatePart[],
}

// `${else}` and the parts it guards.
class TemplateElse {
  span: TokenRange,
  open: int,
  kw: int,
  close: int | Missing,
  parts: AnyTemplatePart[],
}

// `${endfor}` / `${endif}`
class TemplateEndTag {
  span: TokenRange,
  open: int,
  kw: int,
  close: int | Missing,
}

// A `Token![TemplateChunk]` alternative, as its own node.
class AnyTemplatePartChunk {
  token: int,
}
