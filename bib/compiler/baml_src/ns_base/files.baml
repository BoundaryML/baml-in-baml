// port: baml_base/src/files.rs @ d9be6853b
//
// Rust's salsa inputs `SourceFile`, `SourceRoot` and `SourceRootTable` are
// plain classes here, owned by the HIR `Db` (`ns_hir/db.baml`) and referred to
// everywhere else by their `id` (an index into the Db's arrays), the way salsa
// ids are. Rust's `FileId` is the file's `id`.

// port: files.rs::SourceRootKind. In table order: every `Stdlib` root first,
// `Dynamic` last.
enum SourceRootKind {
  // Embedded stdlib source. Read-only, never diagnosed.
  Stdlib
  // A read-only source-bearing dependency package.
  Dependency
  // A user project: editable, diagnosed, emitted.
  Workspace
  // A package loaded at run time (a runtime compile, an eval session).
  Dynamic
}

// port: files.rs::Dependency. An edge: the package `root` (a root id),
// reached under `name`.
class Dependency {
  name: string,
  root: int,
}

// port: files.rs::SourceRoot. A package.
class SourceRoot {
  id: int,
  // Root directory: a real path, or `<builtin>/<pkg>` for a stdlib package.
  path: string,
  kind: SourceRootKind,
  // `[package].name`, or the stdlib package's fixed name; display only.
  self_name: string?,
  // File ids, in insertion order.
  files: int[],
  // Omit test registrars from the semantic input (SDK generation).
  exclude_tests: bool,
  // The packages this package may reach, each under the name it uses.
  dependencies: Dependency[],
}

// port: files.rs::SourceFile
class SourceFile {
  id: int,
  text: string,
  // As registered: `<builtin>/<pkg>/<relative>` for stdlib files.
  path: string,
  // The root (package) the file belongs to.
  root: int,
}
