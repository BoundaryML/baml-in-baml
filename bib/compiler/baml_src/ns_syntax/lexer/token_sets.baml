// port: baml_syntax/src/token.rs::{KindSet, TokenSet, Ident, sets} @ d9be6853b
//
// In Rust a `Token<S>` is typed by its set and `KindSet` is a bitset. Here a
// token is its index (`int`) and a set is a lookup table.

// A bitset over `token_kind_index`, as Rust's `KindSet` is (there a u128-ish
// mask of the kind's discriminant). 62 bits per word: BAML ints are 63-bit.
// Restructured from a `map<TokenKind, bool>`: an enum-keyed map lookup costs
// ~0.8 us on the VM, a `match` plus a shift ~40 ns.
class KindSet {
    words: int[],

    function of(kinds: TokenKind[]) -> KindSet throws never {
        let words = [0, 0, 0];
        for (let kind in kinds) {
            let i = token_kind_index(kind);
            words[i / 62] = words[i / 62] | (1 << (i % 62));
        }
        KindSet { words: words }
    }

    function contains(self, kind: TokenKind) -> bool throws never {
        let i = token_kind_index(kind);
        ((self.words[i / 62] >> (i % 62)) & 1) == 1
    }

    function union(self, other: KindSet) -> KindSet throws never {
        KindSet {
            words: [
                self.words[0] | other.words[0],
                self.words[1] | other.words[1],
                self.words[2] | other.words[2],
            ],
        }
    }
}

// Each token kind's position in `TokenKind`'s declaration order, the bit
// `KindSet` uses. Exhaustive, so a new kind fails to compile until it is
// given an index here.
function token_kind_index(kind: TokenKind) -> int throws never {
    match (kind) {
        TokenKind.Whitespace => 0,
        TokenKind.Newline => 1,
        TokenKind.LineComment => 2,
        TokenKind.DocComment => 3,
        TokenKind.DirectiveComment => 4,
        TokenKind.HeaderComment => 5,
        TokenKind.BlockComment => 6,
        TokenKind.UnclosedBlockComment => 7,
        TokenKind.Class => 8,
        TokenKind.Enum => 9,
        TokenKind.Interface => 10,
        TokenKind.Implements => 11,
        TokenKind.Implement => 12,
        TokenKind.Extends => 13,
        TokenKind.Requires => 14,
        TokenKind.Function => 15,
        TokenKind.Client => 16,
        TokenKind.Generator => 17,
        TokenKind.Test => 18,
        TokenKind.Testset => 19,
        TokenKind.RetryPolicy => 20,
        TokenKind.TemplateString => 21,
        TokenKind.If => 22,
        TokenKind.Else => 23,
        TokenKind.For => 24,
        TokenKind.While => 25,
        TokenKind.Let => 26,
        TokenKind.In => 27,
        TokenKind.Break => 28,
        TokenKind.Continue => 29,
        TokenKind.Return => 30,
        TokenKind.Throw => 31,
        TokenKind.Match => 32,
        TokenKind.Catch => 33,
        TokenKind.CatchAll => 34,
        TokenKind.Throws => 35,
        TokenKind.Spawn => 36,
        TokenKind.Await => 37,
        TokenKind.Defer => 38,
        TokenKind.Instanceof => 39,
        TokenKind.Is => 40,
        TokenKind.Type => 41,
        TokenKind.Const => 42,
        TokenKind.With => 43,
        TokenKind.As => 44,
        TokenKind.True => 45,
        TokenKind.False => 46,
        TokenKind.Null => 47,
        TokenKind.Endfor => 48,
        TokenKind.Endif => 49,
        TokenKind.Map => 50,
        TokenKind.Env => 51,
        TokenKind.Prompt => 52,
        TokenKind.Tools => 53,
        TokenKind.SelfValue => 54,
        TokenKind.Underscore => 55,
        TokenKind.Spec => 56,
        TokenKind.Stream => 57,
        TokenKind.RenderPrompt => 58,
        TokenKind.BuildRequest => 59,
        TokenKind.Parse => 60,
        TokenKind.CatchAllPanics => 61,
        TokenKind.Unreflect => 62,
        TokenKind.TypeBuilder => 63,
        TokenKind.Dynamic => 64,
        TokenKind.LBrace => 65,
        TokenKind.RBrace => 66,
        TokenKind.LParen => 67,
        TokenKind.RParen => 68,
        TokenKind.LBracket => 69,
        TokenKind.RBracket => 70,
        TokenKind.DoubleColon => 71,
        TokenKind.Colon => 72,
        TokenKind.Comma => 73,
        TokenKind.Semicolon => 74,
        TokenKind.DotDotDot => 75,
        TokenKind.DotDot => 76,
        TokenKind.Dot => 77,
        TokenKind.Dollar => 78,
        TokenKind.DollarLBrace => 79,
        TokenKind.Arrow => 80,
        TokenKind.FatArrow => 81,
        TokenKind.AtAt => 82,
        TokenKind.At => 83,
        TokenKind.Pipe => 84,
        TokenKind.QuestionDot => 85,
        TokenKind.Question => 86,
        TokenKind.LessLessEquals => 87,
        TokenKind.PlusEquals => 88,
        TokenKind.MinusEquals => 89,
        TokenKind.StarEquals => 90,
        TokenKind.SlashEquals => 91,
        TokenKind.PercentEquals => 92,
        TokenKind.AndEquals => 93,
        TokenKind.PipeEquals => 94,
        TokenKind.CaretEquals => 95,
        TokenKind.Equals => 96,
        TokenKind.EqualsEquals => 97,
        TokenKind.NotEquals => 98,
        TokenKind.LessEquals => 99,
        TokenKind.LessLess => 100,
        TokenKind.Less => 101,
        TokenKind.Greater => 102,
        TokenKind.AndAnd => 103,
        TokenKind.OrOr => 104,
        TokenKind.Not => 105,
        TokenKind.And => 106,
        TokenKind.Caret => 107,
        TokenKind.Tilde => 108,
        TokenKind.PlusPlus => 109,
        TokenKind.MinusMinus => 110,
        TokenKind.Plus => 111,
        TokenKind.Minus => 112,
        TokenKind.Star => 113,
        TokenKind.Slash => 114,
        TokenKind.Percent => 115,
        TokenKind.Backslash => 116,
        TokenKind.Word => 117,
        TokenKind.Integer => 118,
        TokenKind.Float => 119,
        TokenKind.Bigint => 120,
        TokenKind.String => 121,
        TokenKind.RawString => 122,
        TokenKind.ByteString => 123,
        TokenKind.LegacyHashString => 124,
        TokenKind.BacktickStart => 125,
        TokenKind.TemplateChunk => 126,
        TokenKind.BacktickEnd => 127,
        TokenKind.Hash => 128,
        TokenKind.UnclosedString => 129,
        TokenKind.UnclosedRawString => 130,
        TokenKind.UnclosedByteString => 131,
        TokenKind.UnclosedHashString => 132,
        TokenKind.Error => 133,
    }
}

// port: KindSet::CONTEXTUAL_KEYWORDS
const CONTEXTUAL_KEYWORDS: KindSet = KindSet.of(
    [
        TokenKind.Type,
        TokenKind.Const,
        TokenKind.With,
        TokenKind.As,
        TokenKind.True,
        TokenKind.False,
        TokenKind.Null,
        TokenKind.Endfor,
        TokenKind.Endif,
        TokenKind.Map,
        TokenKind.Env,
        TokenKind.Prompt,
        TokenKind.Tools,
        TokenKind.SelfValue,
        TokenKind.Underscore,
        TokenKind.Spec,
        TokenKind.Stream,
        TokenKind.RenderPrompt,
        TokenKind.BuildRequest,
        TokenKind.Parse,
        TokenKind.CatchAllPanics,
        TokenKind.Unreflect,
        TokenKind.TypeBuilder,
        TokenKind.Dynamic,
    ],
);

// port: Ident. Anything that names a thing: a word or a contextual keyword.
const IDENT: KindSet = CONTEXTUAL_KEYWORDS.union(KindSet.of([TokenKind.Word]));

// port: sets::*. Token alternatives used by node fields.

// `,` or `;` after a member.
const MEMBER_SEP: KindSet = KindSet.of([TokenKind.Comma, TokenKind.Semicolon]);
// `let` or `const`.
const LET_INTRODUCER: KindSet = KindSet.of([TokenKind.Let, TokenKind.Const]);
// `->`, or `=>` accepted in its place.
const ANY_ARROW: KindSet = KindSet.of([TokenKind.Arrow, TokenKind.FatArrow]);
const IMPLEMENTS_KW: KindSet = KindSet.of([TokenKind.Implements, TokenKind.Implement]);
const TEST_KW: KindSet = KindSet.of([TokenKind.Test, TokenKind.Testset]);
const CATCH_KW: KindSet = KindSet.of([TokenKind.Catch, TokenKind.CatchAll, TokenKind.CatchAllPanics]);
// The keyword of a removed item form, kept only for its diagnostic.
const REMOVED_KW: KindSet = KindSet.of(
    [
        TokenKind.Client,
        TokenKind.RetryPolicy,
        TokenKind.TemplateString,
        TokenKind.Generator,
        TokenKind.TypeBuilder,
        TokenKind.Dynamic,
        TokenKind.Test,
    ],
);
const LITERAL_EXPR_TOKEN: KindSet = KindSet.of(
    [
        TokenKind.Integer,
        TokenKind.Float,
        TokenKind.Bigint,
        TokenKind.True,
        TokenKind.False,
        TokenKind.Null,
    ],
);
// A string literal, closed or not: the parser accepts an unclosed one as the
// literal it was meant to be and reports the missing closer.
const STRING_TOKEN: KindSet = KindSet.of(
    [
        TokenKind.String,
        TokenKind.RawString,
        TokenKind.ByteString,
        TokenKind.LegacyHashString,
        TokenKind.UnclosedString,
        TokenKind.UnclosedRawString,
        TokenKind.UnclosedByteString,
        TokenKind.UnclosedHashString,
    ],
);
// A literal in type position: `"a"`, `1`, `2n`, `true` (floats are accepted
// and reported).
const LITERAL_TYPE_TOKEN: KindSet = STRING_TOKEN.union(
    KindSet.of(
        [TokenKind.Integer, TokenKind.Float, TokenKind.Bigint, TokenKind.True, TokenKind.False],
    ),
);
// `.` or the `$` member separator.
const MEMBER_DOT: KindSet = KindSet.of([TokenKind.Dot, TokenKind.Dollar]);
const TUPLE_DOT: KindSet = KindSet.of([TokenKind.Dot, TokenKind.QuestionDot]);
// The selector of `F@spec`, `F@stream`, ...
const SPEC_SELECTOR: KindSet = KindSet.of(
    [
        TokenKind.Spec,
        TokenKind.Stream,
        TokenKind.RenderPrompt,
        TokenKind.BuildRequest,
        TokenKind.Parse,
    ],
);
const END_TAG_KW: KindSet = KindSet.of([TokenKind.Endfor, TokenKind.Endif]);
// A `///` line or a `//baml:` directive: what a declaration may own before
// its attributes and keyword.
const DOC_TOKEN: KindSet = KindSet.of([TokenKind.DocComment, TokenKind.DirectiveComment]);
// A comment of any spelling.
const COMMENT_TOKEN: KindSet = KindSet.of(
    [
        TokenKind.LineComment,
        TokenKind.BlockComment,
        TokenKind.UnclosedBlockComment,
        TokenKind.DocComment,
        TokenKind.DirectiveComment,
        TokenKind.HeaderComment,
    ],
);
// port: sets::NameToken. Any token that may name something: a word, a
// contextual keyword, or a reserved word the grammar accepts as a name in
// some position.
const NAME_TOKEN: KindSet = IDENT.union(
    KindSet.of(
        [
            TokenKind.Client,
            TokenKind.Class,
            TokenKind.Enum,
            TokenKind.Function,
            TokenKind.Interface,
            TokenKind.Implements,
            TokenKind.Implement,
            TokenKind.Extends,
            TokenKind.Requires,
            TokenKind.Spawn,
            TokenKind.Await,
            TokenKind.Throws,
        ],
    ),
);
// port: ops.rs::UnaryOpToken
const UNARY_OP_TOKEN: KindSet = KindSet.of(
    [TokenKind.Minus, TokenKind.Not, TokenKind.Tilde, TokenKind.PlusPlus, TokenKind.MinusMinus],
);
