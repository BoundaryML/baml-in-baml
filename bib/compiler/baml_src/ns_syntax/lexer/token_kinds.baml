// port: TokenKind::{is_*, describe}, generated in Rust by baml_syntax_macros' TokenTable.
// Generated once by a porting script from the token.rs attributes.

function is_doc(kind: TokenKind) -> bool throws never {
  match (kind) {
    TokenKind.DocComment | TokenKind.DirectiveComment => true,
    _ => false,
  }
}

function is_keyword(kind: TokenKind) -> bool throws never {
  match (kind) {
    TokenKind.Class | TokenKind.Enum | TokenKind.Interface | TokenKind.Implements | TokenKind.Implement | TokenKind.Extends | TokenKind.Requires | TokenKind.Function | TokenKind.Client | TokenKind.Generator | TokenKind.Test | TokenKind.Testset | TokenKind.RetryPolicy | TokenKind.TemplateString | TokenKind.If | TokenKind.Else | TokenKind.For | TokenKind.While | TokenKind.Let | TokenKind.In | TokenKind.Break | TokenKind.Continue | TokenKind.Return | TokenKind.Throw | TokenKind.Match | TokenKind.Catch | TokenKind.CatchAll | TokenKind.Throws | TokenKind.Spawn | TokenKind.Await | TokenKind.Defer | TokenKind.Instanceof | TokenKind.Is => true,
    _ => false,
  }
}

function is_contextual_keyword(kind: TokenKind) -> bool throws never {
  match (kind) {
    TokenKind.Type | TokenKind.Const | TokenKind.With | TokenKind.As | TokenKind.True | TokenKind.False | TokenKind.Null | TokenKind.Endfor | TokenKind.Endif | TokenKind.Map | TokenKind.Env | TokenKind.Prompt | TokenKind.Tools | TokenKind.SelfValue | TokenKind.Underscore | TokenKind.Spec | TokenKind.Stream | TokenKind.RenderPrompt | TokenKind.BuildRequest | TokenKind.Parse | TokenKind.CatchAllPanics | TokenKind.Unreflect | TokenKind.TypeBuilder | TokenKind.Dynamic => true,
    _ => false,
  }
}

function is_punct(kind: TokenKind) -> bool throws never {
  match (kind) {
    TokenKind.LBrace | TokenKind.RBrace | TokenKind.LParen | TokenKind.RParen | TokenKind.LBracket | TokenKind.RBracket | TokenKind.DoubleColon | TokenKind.Colon | TokenKind.Comma | TokenKind.Semicolon | TokenKind.DotDotDot | TokenKind.DotDot | TokenKind.Dot | TokenKind.Dollar | TokenKind.DollarLBrace | TokenKind.Arrow | TokenKind.FatArrow | TokenKind.AtAt | TokenKind.At | TokenKind.Pipe | TokenKind.QuestionDot | TokenKind.Question | TokenKind.LessLessEquals | TokenKind.PlusEquals | TokenKind.MinusEquals | TokenKind.StarEquals | TokenKind.SlashEquals | TokenKind.PercentEquals | TokenKind.AndEquals | TokenKind.PipeEquals | TokenKind.CaretEquals | TokenKind.Equals | TokenKind.EqualsEquals | TokenKind.NotEquals | TokenKind.LessEquals | TokenKind.LessLess | TokenKind.Less | TokenKind.Greater | TokenKind.AndAnd | TokenKind.OrOr | TokenKind.Not | TokenKind.And | TokenKind.Caret | TokenKind.Tilde | TokenKind.PlusPlus | TokenKind.MinusMinus | TokenKind.Plus | TokenKind.Minus | TokenKind.Star | TokenKind.Slash | TokenKind.Percent | TokenKind.Backslash => true,
    _ => false,
  }
}

function is_literal(kind: TokenKind) -> bool throws never {
  match (kind) {
    TokenKind.Word | TokenKind.Integer | TokenKind.Float | TokenKind.Bigint | TokenKind.String | TokenKind.RawString | TokenKind.ByteString | TokenKind.LegacyHashString | TokenKind.BacktickStart | TokenKind.TemplateChunk | TokenKind.BacktickEnd => true,
    _ => false,
  }
}

function is_invalid(kind: TokenKind) -> bool throws never {
  match (kind) {
    TokenKind.Hash | TokenKind.UnclosedString | TokenKind.UnclosedRawString | TokenKind.UnclosedByteString | TokenKind.UnclosedHashString | TokenKind.Error => true,
    _ => false,
  }
}

// The spelling of a fixed token, or a description of a variable one.
function describe(kind: TokenKind) -> string throws never {
  match (kind) {
    TokenKind.Whitespace => "whitespace",
    TokenKind.Newline => "newline",
    TokenKind.LineComment => "`//` comment",
    TokenKind.DocComment => "`///` doc comment",
    TokenKind.DirectiveComment => "`//baml:` directive",
    TokenKind.HeaderComment => "`//#` header comment",
    TokenKind.BlockComment => "`/* */` comment",
    TokenKind.UnclosedBlockComment => "unclosed `/*` comment",
    TokenKind.Class => "class",
    TokenKind.Enum => "enum",
    TokenKind.Interface => "interface",
    TokenKind.Implements => "implements",
    TokenKind.Implement => "implement",
    TokenKind.Extends => "extends",
    TokenKind.Requires => "requires",
    TokenKind.Function => "function",
    TokenKind.Client => "client",
    TokenKind.Generator => "generator",
    TokenKind.Test => "test",
    TokenKind.Testset => "testset",
    TokenKind.RetryPolicy => "retry_policy",
    TokenKind.TemplateString => "template_string",
    TokenKind.If => "if",
    TokenKind.Else => "else",
    TokenKind.For => "for",
    TokenKind.While => "while",
    TokenKind.Let => "let",
    TokenKind.In => "in",
    TokenKind.Break => "break",
    TokenKind.Continue => "continue",
    TokenKind.Return => "return",
    TokenKind.Throw => "throw",
    TokenKind.Match => "match",
    TokenKind.Catch => "catch",
    TokenKind.CatchAll => "catch_all",
    TokenKind.Throws => "throws",
    TokenKind.Spawn => "spawn",
    TokenKind.Await => "await",
    TokenKind.Defer => "defer",
    TokenKind.Instanceof => "instanceof",
    TokenKind.Is => "is",
    TokenKind.Type => "type",
    TokenKind.Const => "const",
    TokenKind.With => "with",
    TokenKind.As => "as",
    TokenKind.True => "true",
    TokenKind.False => "false",
    TokenKind.Null => "null",
    TokenKind.Endfor => "endfor",
    TokenKind.Endif => "endif",
    TokenKind.Map => "map",
    TokenKind.Env => "env",
    TokenKind.Prompt => "prompt",
    TokenKind.Tools => "tools",
    TokenKind.SelfValue => "self",
    TokenKind.Underscore => "_",
    TokenKind.Spec => "spec",
    TokenKind.Stream => "stream",
    TokenKind.RenderPrompt => "render_prompt",
    TokenKind.BuildRequest => "build_request",
    TokenKind.Parse => "parse",
    TokenKind.CatchAllPanics => "catch_all_panics",
    TokenKind.Unreflect => "unreflect",
    TokenKind.TypeBuilder => "type_builder",
    TokenKind.Dynamic => "dynamic",
    TokenKind.LBrace => "{",
    TokenKind.RBrace => "}",
    TokenKind.LParen => "(",
    TokenKind.RParen => ")",
    TokenKind.LBracket => "[",
    TokenKind.RBracket => "]",
    TokenKind.DoubleColon => "::",
    TokenKind.Colon => ":",
    TokenKind.Comma => ",",
    TokenKind.Semicolon => ";",
    TokenKind.DotDotDot => "...",
    TokenKind.DotDot => "..",
    TokenKind.Dot => ".",
    TokenKind.Dollar => "$",
    TokenKind.DollarLBrace => "${",
    TokenKind.Arrow => "->",
    TokenKind.FatArrow => "=>",
    TokenKind.AtAt => "@@",
    TokenKind.At => "@",
    TokenKind.Pipe => "|",
    TokenKind.QuestionDot => "?.",
    TokenKind.Question => "?",
    TokenKind.LessLessEquals => "<<=",
    TokenKind.PlusEquals => "+=",
    TokenKind.MinusEquals => "-=",
    TokenKind.StarEquals => "*=",
    TokenKind.SlashEquals => "/=",
    TokenKind.PercentEquals => "%=",
    TokenKind.AndEquals => "&=",
    TokenKind.PipeEquals => "|=",
    TokenKind.CaretEquals => "^=",
    TokenKind.Equals => "=",
    TokenKind.EqualsEquals => "==",
    TokenKind.NotEquals => "!=",
    TokenKind.LessEquals => "<=",
    TokenKind.LessLess => "<<",
    TokenKind.Less => "<",
    TokenKind.Greater => ">",
    TokenKind.AndAnd => "&&",
    TokenKind.OrOr => "||",
    TokenKind.Not => "!",
    TokenKind.And => "&",
    TokenKind.Caret => "^",
    TokenKind.Tilde => "~",
    TokenKind.PlusPlus => "++",
    TokenKind.MinusMinus => "--",
    TokenKind.Plus => "+",
    TokenKind.Minus => "-",
    TokenKind.Star => "*",
    TokenKind.Slash => "/",
    TokenKind.Percent => "%",
    TokenKind.Backslash => "\\",
    TokenKind.Word => "identifier",
    TokenKind.Integer => "integer literal",
    TokenKind.Float => "float literal",
    TokenKind.Bigint => "bigint literal",
    TokenKind.String => "string literal",
    TokenKind.RawString => "raw string literal",
    TokenKind.ByteString => "byte string literal",
    TokenKind.LegacyHashString => "`#\"…\"#` string literal",
    TokenKind.BacktickStart => "opening backtick",
    TokenKind.TemplateChunk => "template text",
    TokenKind.BacktickEnd => "closing backtick",
    TokenKind.Hash => "`#`",
    TokenKind.UnclosedString => "unclosed string literal",
    TokenKind.UnclosedRawString => "unclosed raw string literal",
    TokenKind.UnclosedByteString => "unclosed byte string literal",
    TokenKind.UnclosedHashString => "unclosed `#\"…\"#` string literal",
    TokenKind.Error => "unrecognised character",
  }
}
