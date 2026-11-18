// port: baml_syntax/src/token.rs::TokenKind @ d9be6853b
// One variant per Rust variant, same order, same names.

enum TokenKind {
    // trivia
    Whitespace,
    Newline,
    LineComment,
    DocComment,
    DirectiveComment,
    HeaderComment,
    BlockComment,
    UnclosedBlockComment,
    // keywords
    Class,
    Enum,
    Interface,
    Implements,
    Implement,
    Extends,
    Requires,
    Function,
    Client,
    Generator,
    Test,
    Testset,
    RetryPolicy,
    TemplateString,
    If,
    Else,
    For,
    While,
    Let,
    In,
    Break,
    Continue,
    Return,
    Throw,
    Match,
    Catch,
    CatchAll,
    Throws,
    Spawn,
    Await,
    Defer,
    Instanceof,
    Is,
    // contextual keywords
    Type,
    Const,
    With,
    As,
    True,
    False,
    Null,
    Endfor,
    Endif,
    Map,
    Env,
    Prompt,
    Tools,
    SelfValue,
    Underscore,
    Spec,
    Stream,
    RenderPrompt,
    BuildRequest,
    Parse,
    CatchAllPanics,
    Unreflect,
    TypeBuilder,
    Dynamic,
    // punctuation
    LBrace,
    RBrace,
    LParen,
    RParen,
    LBracket,
    RBracket,
    DoubleColon,
    Colon,
    Comma,
    Semicolon,
    DotDotDot,
    DotDot,
    Dot,
    Dollar,
    DollarLBrace,
    Arrow,
    FatArrow,
    AtAt,
    At,
    Pipe,
    QuestionDot,
    Question,
    LessLessEquals,
    PlusEquals,
    MinusEquals,
    StarEquals,
    SlashEquals,
    PercentEquals,
    AndEquals,
    PipeEquals,
    CaretEquals,
    Equals,
    EqualsEquals,
    NotEquals,
    LessEquals,
    LessLess,
    Less,
    Greater,
    AndAnd,
    OrOr,
    Not,
    And,
    Caret,
    Tilde,
    PlusPlus,
    MinusMinus,
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Backslash,
    // literals
    Word,
    Integer,
    Float,
    Bigint,
    String,
    RawString,
    ByteString,
    LegacyHashString,
    BacktickStart,
    TemplateChunk,
    BacktickEnd,
    // invalid
    Hash,
    UnclosedString,
    UnclosedRawString,
    UnclosedByteString,
    UnclosedHashString,
    Error,
}

// port: baml_syntax/src/token.rs::Tokens @ d9be6853b
// `starts` has one more entry than `kinds`: the text length, so token i spans
// starts[i]..starts[i + 1]. Offsets are UTF-8 byte offsets.
class Tokens {
    kinds: TokenKind[],
    starts: int[],

    // port: Tokens::prev_significant. The nearest non-trivia token before `idx`.
    function prev_significant(self, idx: int) -> int? throws never {
        let i = idx - 1;
        while (i >= 0) {
            if (!is_trivia(self.kinds[i])) {
                return i;
            }
            i -= 1;
        }
        null
    }

    // port: Tokens::text. `utf8` is the source text's bytes.
    function text(self, utf8: uint8array, idx: int) -> string throws never {
        string.from_utf8(utf8.slice(self.starts[idx], self.starts[idx + 1])) catch (e) {
            baml.errors.InvalidArgument => {
                baml.sys.panic("tokens split the source on character boundaries")
            },
        }
    }
}

// port: TokenKind::is_trivia (generated from `#[group(trivia)]` in Rust).
function is_trivia(kind: TokenKind) -> bool throws never {
    match (kind) {
        TokenKind.Whitespace
            | TokenKind.Newline
            | TokenKind.LineComment
            | TokenKind.HeaderComment
            | TokenKind.BlockComment
            | TokenKind.UnclosedBlockComment =>
        {
            true
        },
        _ => false,
    }
}

// The fixed spellings that win over `Word` at equal length (Logos prefers a
// `#[token]` over a regex). A word is looked up only after it is fully munched.
const KEYWORDS: map<string, TokenKind> = {
    "class": TokenKind.Class,
    "enum": TokenKind.Enum,
    "interface": TokenKind.Interface,
    "implements": TokenKind.Implements,
    "implement": TokenKind.Implement,
    "extends": TokenKind.Extends,
    "requires": TokenKind.Requires,
    "function": TokenKind.Function,
    "client": TokenKind.Client,
    "generator": TokenKind.Generator,
    "test": TokenKind.Test,
    "testset": TokenKind.Testset,
    "retry_policy": TokenKind.RetryPolicy,
    "template_string": TokenKind.TemplateString,
    "if": TokenKind.If,
    "else": TokenKind.Else,
    "for": TokenKind.For,
    "while": TokenKind.While,
    "let": TokenKind.Let,
    "in": TokenKind.In,
    "break": TokenKind.Break,
    "continue": TokenKind.Continue,
    "return": TokenKind.Return,
    "throw": TokenKind.Throw,
    "match": TokenKind.Match,
    "catch": TokenKind.Catch,
    "catch_all": TokenKind.CatchAll,
    "throws": TokenKind.Throws,
    "spawn": TokenKind.Spawn,
    "await": TokenKind.Await,
    "defer": TokenKind.Defer,
    "instanceof": TokenKind.Instanceof,
    "is": TokenKind.Is,
    "type": TokenKind.Type,
    "const": TokenKind.Const,
    "with": TokenKind.With,
    "as": TokenKind.As,
    "true": TokenKind.True,
    "false": TokenKind.False,
    "null": TokenKind.Null,
    "endfor": TokenKind.Endfor,
    "endif": TokenKind.Endif,
    "map": TokenKind.Map,
    "env": TokenKind.Env,
    "prompt": TokenKind.Prompt,
    "tools": TokenKind.Tools,
    "self": TokenKind.SelfValue,
    "_": TokenKind.Underscore,
    "spec": TokenKind.Spec,
    "stream": TokenKind.Stream,
    "render_prompt": TokenKind.RenderPrompt,
    "build_request": TokenKind.BuildRequest,
    "parse": TokenKind.Parse,
    "catch_all_panics": TokenKind.CatchAllPanics,
    "unreflect": TokenKind.Unreflect,
    "type_builder": TokenKind.TypeBuilder,
    "dynamic": TokenKind.Dynamic,
};
