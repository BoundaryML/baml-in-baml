// port: baml_syntax/src/tree.rs @ d9be6853b
//
// The Rust tree stores nodes in per-type arenas and links them by `Id<T>`;
// here a node holds its children directly (classes are references). What the
// arenas also carried is kept on the node: its token `span`.
//
// Field types follow the Rust grammar positions:
//   Token<K>                 -> int (an index into the file's tokens)
//   Id<T>                    -> T
//   Result<T, Missing>       -> T | Missing
//   Option<T>                -> T?
//   List<T>                  -> T[]
//   Sep<T, S>                -> SepItem<T>[]

// port: tree.rs::TokenRange. Tokens [start, end).
class TokenRange {
  start: int,
  end: int,
}

// port: tree.rs::Missing. A required position the parser had to leave empty,
// always alongside a diagnostic; `at` is the byte offset where it belongs.
class Missing {
  at: int,
}

// port: tree.rs::Bogus. Tokens that fit no node, kept in place, always
// alongside a diagnostic.
class Bogus {
  span: TokenRange,
}

// port: tree.rs::SepItem. An item of a separated list and the separator token
// after it, if any.
class SepItem<T> {
  item: T,
  sep: int?,
}
