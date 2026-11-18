// port: baml_syntax/src/token.rs::{KindSet, TokenSet, Ident, sets} @ d9be6853b
//
// In Rust a `Token<S>` is typed by its set and `KindSet` is a bitset. Here a
// token is its index (`int`) and a set is a lookup table.

class KindSet {
    kinds: map<TokenKind, bool>,

    function of(kinds: TokenKind[]) -> KindSet throws never {
        let table: map<TokenKind, bool> = {};
        for (let kind in kinds) {
            table[kind] = true;
        }
        KindSet { kinds: table }
    }

    function contains(self, kind: TokenKind) -> bool throws never {
        self.kinds.has(kind)
    }

    function union(self, other: KindSet) -> KindSet throws never {
        KindSet.of(self.kinds.keys().concat(other.kinds.keys()))
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
