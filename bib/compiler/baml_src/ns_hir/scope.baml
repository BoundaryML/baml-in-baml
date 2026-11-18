// port: baml_compiler2_hir/src/scope.rs @ d9be6853b
//
// Scope tree data structures. Scopes are allocated in DFS pre-order during
// `SemanticIndexBuilder.build`; each `Scope` carries a `TextRange` for
// `scope_at_offset()`.
//
// deviation: `FileScopeId` (a `u32` newtype) is a plain `int`, the dense
// index into the per-file scope arena. Its `new` and `index` are the
// identity and `next` is `+ 1`, so none is ported as a function.
// `ScopeId<'db>` (file + file scope id) is interned on the Db:
// `db.scopes.intern(file, file_scope_id)`, read back with
// `db.scopes.get(scope).file` / `.id` (`ns_hir/db.baml`).

// port: scope.rs::FileScopeId::ROOT. `0` is always the Project scope
// (outermost).
const FILE_SCOPE_ID_ROOT: int = 0;

// port: scope.rs::ScopeKind. What kind of scope this is in the hierarchy.
enum ScopeKind {
    // The compilation unit: collects all packages.
    Project,
    // A unit of code with its own root (user, baml, env, ...).
    Package,
    // A named subdivision within a package; can nest.
    Namespace,
    // A .baml file: child of Package or innermost Namespace.
    File,
    // Class body (fields + methods).
    Class,
    // Enum body (variants).
    Enum,
    // Function body.
    Function,
    // Type alias RHS.
    TypeAlias,
    // Block expression with let bindings.
    Block,
    // Lambda expression body: own scope for per-scope incremental inference.
    Lambda,
    // Match arm body: holds pattern bindings visible to the arm body and guard.
    MatchArm,
    // Catch clause: wraps all arms of a catch clause, holds the clause-level
    // binding.
    CatchClause,
    // Catch arm body: holds arm-level pattern bindings.
    CatchArm,
    // Top-level let binding: owns an initializer expression.
    Let,
}

// port: scope.rs::ItemScopeOwner. The item a scope was opened for: the
// builder creates an item's scope in the same step that allocates the item,
// so this link is recorded directly rather than reconstructed from spans.
// Each variant carries the item's `LocalItemId` (an `int`).
type ItemScopeOwner = ItemScopeOwnerFunction
    | ItemScopeOwnerClass
    | ItemScopeOwnerEnum
    | ItemScopeOwnerInterface
    | ItemScopeOwnerTypeAlias
    | ItemScopeOwnerLet
    | ItemScopeOwnerImpl;

class ItemScopeOwnerFunction {
    value: int,
}

class ItemScopeOwnerClass {
    value: int,
}

class ItemScopeOwnerEnum {
    value: int,
}

class ItemScopeOwnerInterface {
    value: int,
}

class ItemScopeOwnerTypeAlias {
    value: int,
}

class ItemScopeOwnerLet {
    value: int,
}

// An out-of-body `implement I for T { ... }` block, which opens a scope for
// its own generic parameters.
class ItemScopeOwnerImpl {
    value: int,
}

// port: std::ops::Range<FileScopeId>, as `Scope.descendants` uses it: the
// scope ids `start <= id < end`.
class FileScopeIdRange {
    start: int,
    end: int,
}

// port: scope.rs::Scope. A single scope node in the per-file scope tree.
class Scope {
    // Parent scope. Null only for the Project root scope.
    parent: int?,
    // What kind of scope this is.
    kind: ScopeKind,
    // Optional name (packages, namespaces, items have names; blocks don't).
    name: string?,
    // The item this scope was opened for, if any. Null for structural scopes
    // (Project/Package/Namespace/File) and for expression scopes (`Block`,
    // `Lambda`, `MatchArm`, ...).
    owner: ItemScopeOwner?,
    // Source range of this scope, for `scope_at_offset()`. Structural scopes
    // (Project, Package, Namespace) use the file's full range.
    range: root.syntax.TextRange,
    // Contiguous range of descendant scope ids (DFS pre-order). All scopes in
    // `descendants` are proper descendants of this scope.
    descendants: FileScopeIdRange,
    // True for the synthetic `ScopeKind.Lambda` scope a tagged template's body
    // is walked in (BEP-049 `walk_template_lambda_body`). It has no backing
    // lambda node and is type-checked inline in its enclosing function or
    // lambda, so it must not be treated as an inference owner. Always false
    // for every other scope.
    is_template_body: bool,
}
