// port: baml_base/src/core_types.rs @ d9be6853b
//
// Rust's `Name` (an interned `SmolStr`) is `string`. `FileId` is an `int`:
// a real file's id, or `SENTINEL_FILE_ID` for fake spans (the Rust packing of
// a tag into the top bits is a size optimization with no BAML counterpart).

// port: FileId::sentinel
const SENTINEL_FILE_ID: int = 4294967295;

// port: core_types.rs::Span. A span in source code: which file, which bytes.
class Span {
  file_id: int,
  range: root.syntax.TextRange,

  // port: Span::fake / Default. Not a real place in any file.
  function fake() -> Span throws never {
    Span { file_id: SENTINEL_FILE_ID, range: root.syntax.TextRange.empty(0) }
  }
}

// port: core_types.rs::PathOrigin. Who wrote a path, which decides how its
// first segment is read: a name of the surrounding scope (`Written`), or a
// language package / the writer's own item by identity (`Compiler`).
enum PathOrigin {
  Written
  Compiler
}

// port: core_types.rs::Path. A dotted path as the AST carries it, with who
// wrote it. A bare name is one segment.
class Path {
  segments: string[],
  origin: PathOrigin,

  // A path source wrote.
  function new(segments: string[]) -> Path throws never {
    Path { segments: segments, origin: PathOrigin.Written }
  }

  // port: Path::compiler and compiler_path!. A path the compiler writes into
  // a language package (or to an item of the writer's own namespace): its
  // first segment is read by identity.
  function compiler(segments: string[]) -> Path throws never {
    Path { segments: segments, origin: PathOrigin.Compiler }
  }

  function is_qualified(self) -> bool throws never {
    self.segments.length() > 1
  }

  // The unqualified leaf (`Response` for `root.http.Response`).
  function leaf(self) -> string throws never {
    self.segments[self.segments.length() - 1]
  }

  implements baml.ToString {
    function to_string(self) -> string throws never {
      self.segments.join(".")
    }
  }
}

// port: core_types.rs::MediaKind
enum MediaKind {
  Image
  Audio
  Video
  Pdf
  // Could be any of the media types.
  Generic
}

// port: MediaKind::tag_str. Tag value in the `{ kind, source, value, mime }`
// JSON shape; `Generic` collapses to "media".
function media_kind_tag(kind: MediaKind) -> string throws never {
  match (kind) {
    MediaKind.Image => "image",
    MediaKind.Audio => "audio",
    MediaKind.Video => "video",
    MediaKind.Pdf => "pdf",
    MediaKind.Generic => "media",
  }
}

// port: MediaKind::wrapper_class_name. The stdlib wrapper class carrying a
// media kind, by wire name; null for `Generic`.
function media_kind_wrapper_class_name(kind: MediaKind) -> string? throws never {
  match (kind) {
    MediaKind.Image => "baml.media.Image",
    MediaKind.Audio => "baml.media.Audio",
    MediaKind.Video => "baml.media.Video",
    MediaKind.Pdf => "baml.media.Pdf",
    MediaKind.Generic => null,
  }
}

// port: MediaKind::from_wrapper_class_name
function media_kind_from_wrapper_class_name(name: string) -> MediaKind? throws never {
  match (name) {
    "baml.media.Image" => MediaKind.Image,
    "baml.media.Audio" => MediaKind.Audio,
    "baml.media.Video" => MediaKind.Video,
    "baml.media.Pdf" => MediaKind.Pdf,
    _ => null,
  }
}

// port: impl Display for MediaKind
function media_kind_display(kind: MediaKind) -> string throws never {
  match (kind) {
    MediaKind.Generic => "image | audio | video | pdf",
    let k: MediaKind => media_kind_tag(k),
  }
}

// port: core_types.rs::Literal
class LiteralInt {
  value: int,
}

class LiteralBigint {
  value: bigint,
}

// The literal's source text.
class LiteralFloat {
  value: string,
}

class LiteralString {
  value: string,
}

class LiteralBool {
  value: bool,
}

type Literal = LiteralInt | LiteralBigint | LiteralFloat | LiteralString | LiteralBool

// port: impl Display for Literal. A string prints as Rust's `{:?}` does.
function literal_display(literal: Literal) -> string throws never {
  match (literal) {
    let l: LiteralString => rust_debug_string(l.value),
    let l: LiteralInt => `${l.value}`,
    let l: LiteralBigint => `${l.value}n`,
    let l: LiteralFloat => l.value,
    let l: LiteralBool => `${l.value}`,
  }
}

// Rust's `{:?}` of a `str`: quoted, with `"`, `\`, newline, CR, tab and NUL
// escaped. deviation: other control characters (Rust prints `\u{..}`) pass
// through; revisit if a diagnostic ever shows one.
function rust_debug_string(s: string) -> string throws never {
  let escaped = s.chars().map((c) -> {
    match (c) {
      "\"" => "\\\"",
      "\\" => "\\\\",
      "\n" => "\\n",
      "\r" => "\\r",
      "\t" => "\\t",
      "\u{0}" => "\\0",
      _ => c,
    }
  });
  `"${escaped.join("")}"`
}

// port: core_types.rs::Severity
enum Severity {
  Error
  Warning
  Info
}
