// port: baml_parser/src/cursor.rs @ d9be6853b
//
// The read head over a file's tokens. The `Input` is the text, its tokens and
// the significant ones (everything but trivia) in order, built once. A
// `Cursor` is a position in it and nothing else. Rust's cursor is `Copy`;
// here it is a class, so a lookahead takes `cur.copy()` explicitly.

// port: cursor.rs::Mark. The position a node starts at: the first
// significant token it will own.
class Mark {
  idx: int,

  // The tokens from this mark to `end` (a `Cursor.end()`, current or earlier).
  function to(self, end: int) -> TokenRange throws never {
    TokenRange { start: self.idx, end: if (end > self.idx) { end } else { self.idx } }
  }
}

// port: cursor.rs::Input. What is being parsed: the text, lexed.
class Input {
  text: string,
  utf8: uint8array,
  tokens: Tokens,
  // The significant (non-trivia) tokens, in order.
  sig: int[],

  function new(text: string) -> Input throws never {
    let tokens = lex(text);
    let sig: int[] = [];
    for (let i = 0; i < tokens.kinds.length(); i += 1) {
      if (!is_trivia(tokens.kinds[i])) {
        sig.push(i);
      }
    }
    Input { text: text, utf8: text.to_utf8(), tokens: tokens, sig: sig }
  }
}

// port: cursor.rs::Cursor. A position in the input: the only state a parse
// has besides its output. `pos` indexes the significant tokens.
class Cursor {
  input: Input,
  pos: int,

  function new(input: Input) -> Cursor throws never {
    Cursor { input: input, pos: 0 }
  }

  // A lookahead: an independent cursor at the same position.
  function copy(self) -> Cursor throws never {
    Cursor { input: self.input, pos: self.pos }
  }

  function tokens(self) -> Tokens throws never {
    self.input.tokens
  }

  // ----- what is here -------------------------------------------------------

  // The kind of the significant token `n` ahead of the current one.
  function kind(self, n: int) -> TokenKind? throws never {
    self.kind_at_sig(self.pos + n)
  }

  // Significant token `i`.
  function sig(self, i: int) -> int? throws never {
    self.input.sig.at(i)
  }

  // The kind of significant token `i`.
  function kind_at_sig(self, i: int) -> TokenKind? throws never {
    let idx = self.input.sig.at(i) ?? return null;
    self.input.tokens.kinds[idx]
  }

  // The position of the first significant token at or after `idx`.
  function sig_index(self, idx: int) -> int throws never {
    let lo = 0;
    let hi = self.input.sig.length();
    while (lo < hi) {
      let mid = (lo + hi) / 2;
      if (self.input.sig[mid] < idx) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    lo
  }

  // The significant-token positions a node's span covers: [start, end).
  function sig_range(self, span: TokenRange) -> int[] throws never {
    [self.sig_index(span.start), self.sig_index(span.end)]
  }

  function nth(self, n: int) -> int? throws never {
    self.input.sig.at(self.pos + n)
  }

  function text_at(self, n: int) -> string? throws never {
    let idx = self.nth(n) ?? return null;
    self.text_of(idx)
  }

  function text_of(self, idx: int) -> string throws never {
    self.input.tokens.text(self.input.utf8, idx)
  }

  function at(self, kind: TokenKind) -> bool throws never {
    self.kind(0) == kind
  }

  function nth_is(self, n: int, kind: TokenKind) -> bool throws never {
    self.kind(n) == kind
  }

  function nth_in(self, n: int, set: KindSet) -> bool throws never {
    let kind = self.kind(n) ?? return false;
    set.contains(kind)
  }

  function at_in(self, set: KindSet) -> bool throws never {
    self.nth_in(0, set)
  }

  // A word or contextual keyword: anything that may simply be a name.
  function at_ident(self) -> bool throws never {
    self.nth_in(0, IDENT)
  }

  function nth_is_ident(self, n: int) -> bool throws never {
    self.nth_in(n, IDENT)
  }

  // Whether significant token `i` is a word or contextual keyword.
  function nth_is_ident_at(self, i: int) -> bool throws never {
    let kind = self.kind_at_sig(i) ?? return false;
    IDENT.contains(kind)
  }

  function at_end(self) -> bool throws never {
    self.pos >= self.input.sig.length()
  }

  // ----- consuming ------------------------------------------------------------
  //
  // A token is consumed only when it is what the caller asks for: `eat`
  // returns its index or null. `skip` is the one untyped consume, for tokens
  // a `Bogus` or a raw range will own.

  // port: eat::<K>. Consume the current significant token if it is a `kind`.
  function eat(self, kind: TokenKind) -> int? throws never {
    let idx = self.nth(0) ?? return null;
    if (self.input.tokens.kinds[idx] != kind) {
      return null;
    }
    self.pos += 1;
    idx
  }

  // port: eat_in::<S> / eat_set. Consume the current significant token if
  // its kind is in `set`.
  function eat_in(self, set: KindSet) -> int? throws never {
    let idx = self.nth(0) ?? return null;
    if (!set.contains(self.input.tokens.kinds[idx])) {
      return null;
    }
    self.pos += 1;
    idx
  }

  // port: eat_op::<BinaryOp>. Consume the binary operator starting at the
  // current token, if one does: all of its adjacent tokens.
  function eat_binary_op(self) -> BinaryOpTok? throws never {
    let idx = self.nth(0) ?? return null;
    let op = binary_op_at(self.input.tokens, idx) ?? return null;
    self.pos += binary_op_tokens(op).length();
    OpTok { op: op, first: idx }
  }

  // port: eat_op::<AssignOp>
  function eat_assign_op(self) -> AssignOpTok? throws never {
    let idx = self.nth(0) ?? return null;
    let op = assign_op_at(self.input.tokens, idx) ?? return null;
    self.pos += assign_op_tokens(op).length();
    OpTok { op: op, first: idx }
  }

  // port: at_op::<BinaryOp>
  function at_binary_op(self) -> bool throws never {
    let idx = self.nth(0) ?? return false;
    binary_op_at(self.input.tokens, idx) != null
  }

  // port: at_op::<AssignOp>
  function at_assign_op(self) -> bool throws never {
    let idx = self.nth(0) ?? return false;
    assign_op_at(self.input.tokens, idx) != null
  }

  // Consume the current significant token without typing it: recovery.
  function skip(self) -> void throws never {
    self.pos += 1;
  }

  // Consume a balanced `{ ... }` (a `${` opens a brace too); nothing when not
  // at `{`. Returns whether the closing brace was found. A token starting a
  // line while a brace is still open at which `resync` holds (an item head)
  // means the brace was never closed: the skip stops before it so the item is
  // parsed, and the caller reports the missing `}`.
  function skip_balanced_braces(self, resync: (Cursor) -> bool throws never) -> bool throws never {
    if (!self.at(TokenKind.LBrace)) {
      return true;
    }
    let depth = 0;
    while (!self.at_end()) {
      let kind = self.kind(0);
      if (kind == TokenKind.LBrace || kind == TokenKind.DollarLBrace) {
        depth += 1;
      } else if (kind == TokenKind.RBrace) {
        depth -= 1;
        self.skip();
        if (depth == 0) {
          return true;
        }
        continue;
      } else if (self.starts_line(0) && resync(self.copy())) {
        return false;
      }
      self.skip();
    }
    false
  }

  // Whether significant token `pos + n` is the first token on its line: only
  // blanks between it and the previous newline (or the start).
  function starts_line(self, n: int) -> bool throws never {
    let i = self.pos + n;
    let idx = self.input.sig.at(i) ?? return false;
    if (i == 0) {
      return true;
    }
    let gap_start = self.input.sig[i - 1] + 1;
    // Walk back from the token: whitespace up to a newline.
    let raw = idx - 1;
    while (raw >= gap_start) {
      let kind = self.input.tokens.kinds[raw];
      if (kind == TokenKind.Newline) {
        return true;
      }
      if (kind != TokenKind.Whitespace) {
        return false;
      }
      raw -= 1;
    }
    false
  }

  // Skip to the next token in `until` at this bracket depth (or an unbalanced
  // closer, or the end); `<`/`>` count as brackets only when `angles_nest`
  // (a type list). In an expression list they are comparisons and must not
  // swallow the rest of the file.
  function skip_until(self, until: KindSet, angles_nest: bool = true) -> void throws never {
    let depth = 0;
    while (!self.at_end()) {
      let kind = self.kind(0) ?? return;
      if (depth == 0 && until.contains(kind)) {
        return;
      }
      match (kind) {
        TokenKind.LParen | TokenKind.LBracket | TokenKind.LBrace => {
          depth += 1;
        },
        TokenKind.Less if angles_nest => {
          depth += 1;
        },
        TokenKind.RParen | TokenKind.RBracket | TokenKind.RBrace => {
          if (depth == 0) {
            return;
          }
          depth -= 1;
        },
        TokenKind.Greater if angles_nest => {
          if (depth == 0) {
            return;
          }
          depth -= 1;
        },
        _ => {},
      }
      self.skip();
    }
  }

  // Skip the bracket group at the cursor (an opener, its balanced interior
  // and its closer), or one token when none opens here. For recovery that
  // gives up on a construct.
  function skip_group(self) -> void throws never {
    if (!self.at_in(OPENERS)) {
      if (!self.at_end()) {
        self.skip();
      }
      return;
    }
    self.skip();
    self.skip_group_interior();
    if (self.at_in(CLOSERS)) {
      self.skip();
    }
  }

  // Inside a bracket group whose opener is consumed: skip to its closer (not
  // consumed), or the end of the input.
  function skip_group_interior(self) -> void throws never {
    let depth = 1;
    while (!self.at_end()) {
      if (self.at_in(OPENERS)) {
        depth += 1;
      } else if (self.at_in(CLOSERS)) {
        depth -= 1;
        if (depth == 0) {
          return;
        }
      }
      self.skip();
    }
  }

  // ----- marks and ranges -------------------------------------------------------

  // The start of the node about to be parsed: the current significant token,
  // or the end of the text.
  function mark(self) -> Mark throws never {
    Mark { idx: self.nth(0) ?? self.eof_idx() }
  }

  function eof_idx(self) -> int throws never {
    self.input.tokens.kinds.length()
  }

  // Just past the last consumed significant token.
  function end(self) -> int throws never {
    if (self.pos == 0) {
      return 0;
    }
    self.input.sig[self.pos - 1] + 1
  }

  // The tokens from `mark` to the last one consumed (empty if none).
  function range_from(self, mark: Mark) -> TokenRange throws never {
    mark.to(self.end())
  }

  function text_range(self, range: TokenRange) -> TextRange throws never {
    let starts = self.input.tokens.starts;
    if (range.start == range.end) {
      return TextRange.empty(if (range.start > 0) { starts[range.start] } else { 0 });
    }
    TextRange { start: starts[range.start], end: starts[range.end] }
  }

  function token_range(self, idx: int) -> TextRange throws never {
    let starts = self.input.tokens.starts;
    TextRange { start: starts[idx], end: starts[idx + 1] }
  }

  // The source text `range` covers.
  function text_of_range(self, range: TokenRange) -> string throws never {
    let text = self.text_range(range);
    string.from_utf8(self.input.utf8.slice(text.start, text.end)) catch (e) {
      baml.errors.InvalidArgument => baml.sys.panic("token ranges split the source on character boundaries"),
    }
  }

  // Where a "found ..." diagnostic points: the current token, or a zero-width
  // caret just past the last significant token at the end of input (never at
  // trailing trivia).
  function error_range(self) -> TextRange throws never {
    let idx = self.nth(0);
    if (idx != null) {
      return self.token_range(idx);
    }
    let count = self.input.sig.length();
    if (count == 0) {
      return TextRange.empty(0);
    }
    TextRange.empty(self.token_range(self.input.sig[count - 1]).end)
  }

  // ----- lines ---------------------------------------------------------------------

  // A line break between the last consumed token and the current one (or the
  // end of the text): a newline token, or a block comment spanning lines.
  function has_newline_ahead(self) -> bool throws never {
    let to = self.nth(0) ?? self.eof_idx();
    for (let i = self.end(); i < to; i += 1) {
      let kind = self.input.tokens.kinds[i];
      if (kind == TokenKind.Newline) {
        return true;
      }
      if (kind == TokenKind.BlockComment && self.text_of(i).includes("\n")) {
        return true;
      }
    }
    false
  }

  // The `//#` header tokens between the last consumed token and the current
  // one (or the end of the text), in order.
  function headers_ahead(self) -> int[] throws never {
    let to = self.nth(0) ?? self.eof_idx();
    let headers: int[] = [];
    for (let i = self.end(); i < to; i += 1) {
      if (self.input.tokens.kinds[i] == TokenKind.HeaderComment) {
        headers.push(i);
      }
    }
    headers
  }

  function header_ahead(self) -> bool throws never {
    self.headers_ahead().length() > 0
  }

  // Whether horizontal whitespace directly follows token `idx`.
  function blank_after(self, idx: int) -> bool throws never {
    self.input.tokens.kinds.at(idx + 1) == TokenKind.Whitespace
  }

  // A line break between significant tokens `i` and `j` (`i < j`).
  function newline_between_sig(self, i: int, j: int) -> bool throws never {
    let from = self.sig(i) ?? return false;
    let to = self.sig(j) ?? return false;
    for (let raw = from + 1; raw < to; raw += 1) {
      if (self.input.tokens.kinds[raw] == TokenKind.Newline) {
        return true;
      }
    }
    false
  }

  // ----- lookahead -----------------------------------------------------------------

  // Whether the body opening at `open` is an LLM body: its first member is
  // `client:`, `prompt:` or `tools:` (scalar LLM fields require the colon, so
  // these starts are never expression statements).
  function looks_like_llm_function_body_from(self, open: int) -> bool throws never {
    let first = self.kind_at_sig(open + 1);
    (first == TokenKind.Client || first == TokenKind.Prompt || first == TokenKind.Tools)
      && self.kind_at_sig(open + 2) == TokenKind.Colon
  }
}

const OPENERS: KindSet = KindSet.of([TokenKind.LParen, TokenKind.LBracket, TokenKind.LBrace]);

const CLOSERS: KindSet = KindSet.of([TokenKind.RParen, TokenKind.RBracket, TokenKind.RBrace]);
