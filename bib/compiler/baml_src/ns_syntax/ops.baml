// port: baml_syntax/src/ops.rs @ d9be6853b
//
// Operators and their precedence. An operator spelled by more than one token
// (`? ?`, `> =`, `> > =`) is read from *adjacent* tokens: `?` and `>` are
// always lexed one character each, so `int??` and a nested generic's `>>`
// close correctly.

// port: ops.rs::IS_BINDING_POWER. `is`: same precedence as the comparisons.
const IS_BINDING_POWER: BindingPower = BindingPower { left: 18, right: 19 };

// port: ops.rs::PREFIX_BINDING_POWER. Below `*`/`/`/`%`, so `-a * b` parses as
// `-(a * b)`: an upstream bug kept for parity until upstream fixes it.
const PREFIX_BINDING_POWER: int = 23;

class BindingPower {
    left: int,
    right: int,
}

enum BinaryOp {
    // `a ?? b`: `a` unless it is null, else `b`.
    NullCoalesce,
    Or,
    And,
    BitOr,
    BitXor,
    BitAnd,
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,
    Instanceof,
    Shl,
    Shr,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
}

// `=` and the compound assignments: statements, never values.
enum AssignOp {
    Assign,
    AddAssign,
    SubAssign,
    MulAssign,
    DivAssign,
    ModAssign,
    BitAndAssign,
    BitOrAssign,
    BitXorAssign,
    ShlAssign,
    ShrAssign,
}

enum UnaryOp {
    Neg,
    Not,
    BitNot,
    PreInc,
    PreDec,
}

// port: ops.rs::OpTok. Which operator, and its first token; the others are
// the adjacent tokens after it.
class OpTok<O> {
    op: O,
    first: int,
}

type BinaryOpTok = OpTok<BinaryOp>;

type AssignOpTok = OpTok<AssignOp>;

// port: BinaryOp::binding_power
function binary_binding_power(op: BinaryOp) -> BindingPower throws never {
    match (op) {
        BinaryOp.NullCoalesce => BindingPower { left: 4, right: 5 },
        BinaryOp.Or => BindingPower { left: 6, right: 7 },
        BinaryOp.And => BindingPower { left: 8, right: 9 },
        BinaryOp.BitOr => BindingPower { left: 10, right: 11 },
        BinaryOp.BitXor => BindingPower { left: 12, right: 13 },
        BinaryOp.BitAnd => BindingPower { left: 14, right: 15 },
        BinaryOp.Eq | BinaryOp.Ne => BindingPower { left: 16, right: 17 },
        BinaryOp.Lt | BinaryOp.Gt | BinaryOp.Le | BinaryOp.Ge | BinaryOp.Instanceof => {
            IS_BINDING_POWER
        },
        BinaryOp.Shl | BinaryOp.Shr => BindingPower { left: 20, right: 21 },
        BinaryOp.Add | BinaryOp.Sub => BindingPower { left: 22, right: 23 },
        BinaryOp.Mul | BinaryOp.Div | BinaryOp.Mod => BindingPower { left: 24, right: 25 },
    }
}

// port: BinaryOp::tokens
function binary_op_tokens(op: BinaryOp) -> TokenKind[] throws never {
    match (op) {
        BinaryOp.NullCoalesce => [TokenKind.Question, TokenKind.Question],
        BinaryOp.Or => [TokenKind.OrOr],
        BinaryOp.And => [TokenKind.AndAnd],
        BinaryOp.BitOr => [TokenKind.Pipe],
        BinaryOp.BitXor => [TokenKind.Caret],
        BinaryOp.BitAnd => [TokenKind.And],
        BinaryOp.Eq => [TokenKind.EqualsEquals],
        BinaryOp.Ne => [TokenKind.NotEquals],
        BinaryOp.Lt => [TokenKind.Less],
        BinaryOp.Gt => [TokenKind.Greater],
        BinaryOp.Le => [TokenKind.LessEquals],
        BinaryOp.Ge => [TokenKind.Greater, TokenKind.Equals],
        BinaryOp.Instanceof => [TokenKind.Instanceof],
        BinaryOp.Shl => [TokenKind.LessLess],
        BinaryOp.Shr => [TokenKind.Greater, TokenKind.Greater],
        BinaryOp.Add => [TokenKind.Plus],
        BinaryOp.Sub => [TokenKind.Minus],
        BinaryOp.Mul => [TokenKind.Star],
        BinaryOp.Div => [TokenKind.Slash],
        BinaryOp.Mod => [TokenKind.Percent],
    }
}

// port: AssignOp::tokens
function assign_op_tokens(op: AssignOp) -> TokenKind[] throws never {
    match (op) {
        AssignOp.Assign => [TokenKind.Equals],
        AssignOp.AddAssign => [TokenKind.PlusEquals],
        AssignOp.SubAssign => [TokenKind.MinusEquals],
        AssignOp.MulAssign => [TokenKind.StarEquals],
        AssignOp.DivAssign => [TokenKind.SlashEquals],
        AssignOp.ModAssign => [TokenKind.PercentEquals],
        AssignOp.BitAndAssign => [TokenKind.AndEquals],
        AssignOp.BitOrAssign => [TokenKind.PipeEquals],
        AssignOp.BitXorAssign => [TokenKind.CaretEquals],
        AssignOp.ShlAssign => [TokenKind.LessLessEquals],
        AssignOp.ShrAssign => [TokenKind.Greater, TokenKind.Greater, TokenKind.Equals],
    }
}

// Whether the tokens from `idx` spell `kinds`, adjacent.
function spells(tokens: Tokens, idx: int, kinds: TokenKind[]) -> bool throws never {
    if (idx + kinds.length() > tokens.kinds.length()) {
        return false;
    }
    for (let offset = 0; offset < kinds.length(); offset += 1) {
        if (tokens.kinds[idx + offset] != kinds[offset]) {
            return false;
        }
    }
    true
}

// port: BinaryOp::at. The operator spelled from `idx`; the longest spelling wins.
function binary_op_at(tokens: Tokens, idx: int) -> BinaryOp? throws never {
    longest_spelled(
        tokens,
        idx,
        BINARY_OPS.map((op) -> {
            binary_op_tokens(op)
        }),
        BINARY_OPS,
    )
}

// port: AssignOp::at
function assign_op_at(tokens: Tokens, idx: int) -> AssignOp? throws never {
    longest_spelled(
        tokens,
        idx,
        ASSIGN_OPS.map((op) -> {
            assign_op_tokens(op)
        }),
        ASSIGN_OPS,
    )
}

// The operator in `ops` whose spelling (same position in `spellings`) is the
// longest one found at `idx`.
function longest_spelled<O>(
    tokens: Tokens,
    idx: int,
    spellings: TokenKind[][],
    ops: O[],
) -> O? throws never {
    let best: O? = null;
    let best_len = 0;
    for (let i = 0; i < ops.length(); i += 1) {
        let spelling = spellings[i];
        if (spelling.length() > best_len && spells(tokens, idx, spelling)) {
            best = ops[i];
            best_len = spelling.length();
        }
    }
    best
}

// port: UnaryOp::token
function unary_op_token(op: UnaryOp) -> TokenKind throws never {
    match (op) {
        UnaryOp.Neg => TokenKind.Minus,
        UnaryOp.Not => TokenKind.Not,
        UnaryOp.BitNot => TokenKind.Tilde,
        UnaryOp.PreInc => TokenKind.PlusPlus,
        UnaryOp.PreDec => TokenKind.MinusMinus,
    }
}

// port: UnaryOp::from_kind
function unary_op_from_kind(kind: TokenKind) -> UnaryOp? throws never {
    match (kind) {
        TokenKind.Minus => UnaryOp.Neg,
        TokenKind.Not => UnaryOp.Not,
        TokenKind.Tilde => UnaryOp.BitNot,
        TokenKind.PlusPlus => UnaryOp.PreInc,
        TokenKind.MinusMinus => UnaryOp.PreDec,
        _ => null,
    }
}

const BINARY_OPS: BinaryOp[] = [
    BinaryOp.NullCoalesce,
    BinaryOp.Or,
    BinaryOp.And,
    BinaryOp.BitOr,
    BinaryOp.BitXor,
    BinaryOp.BitAnd,
    BinaryOp.Eq,
    BinaryOp.Ne,
    BinaryOp.Lt,
    BinaryOp.Gt,
    BinaryOp.Le,
    BinaryOp.Ge,
    BinaryOp.Instanceof,
    BinaryOp.Shl,
    BinaryOp.Shr,
    BinaryOp.Add,
    BinaryOp.Sub,
    BinaryOp.Mul,
    BinaryOp.Div,
    BinaryOp.Mod,
];

const ASSIGN_OPS: AssignOp[] = [
    AssignOp.Assign,
    AssignOp.AddAssign,
    AssignOp.SubAssign,
    AssignOp.MulAssign,
    AssignOp.DivAssign,
    AssignOp.ModAssign,
    AssignOp.BitAndAssign,
    AssignOp.BitOrAssign,
    AssignOp.BitXorAssign,
    AssignOp.ShlAssign,
    AssignOp.ShrAssign,
];
