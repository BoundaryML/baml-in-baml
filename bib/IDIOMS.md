# Rust → BAML idioms for the port

Every porter follows this table. Add a row before using a new idiom twice.
Style rules come from the BAML skill (`bib/compiler/.agents/skills/baml-core/SKILL.md`,
"Style guidelines"); run `baml codequality --functions` after each function.

## Layout

| Rust | BAML |
|---|---|
| crate `baml_syntax` + `baml_parser` | namespace `syntax`: `ns_syntax/{lexer,nodes,parser}/` (plain subfolders share the namespace) |
| crate `baml_base` | namespace `base`: `ns_base/` |
| file `src/foo.rs` | `foo.baml` in the matching folder |
| item header | `// port: <crate>/src/<file>.rs::<item> @ d9be6853b` (a function's own header comment, not one per line) |
| `#[cfg(test)]` tests | `<file>_test.baml` next to the file, `test "<rust name with spaces>" { ... }` |

## Names and functions

| Rust | BAML |
|---|---|
| `fn foo_bar(p: &mut Parser, ..)` | `function foo_bar(p: Parser, ..) -> .. throws never` (same name) |
| `impl Parse for FooBar { type Head = H; fn parse(p, head) }` | `function parse_foo_bar(p: Parser, head..) -> FooBar` |
| tuple head `(a, b)` | separate parameters, in order |
| method on a type we own | method in the class (`Cursor`, `Parser`, `Sink`, ...) |
| one-line forwarding helper | don't: one function with a named default parameter, or call the target directly |
| `const FOO: KindSet = KindSet::new(&[..])` | `const FOO: KindSet = KindSet.of([..]);` |
| field, method or parameter named after a BAML keyword (`throws`, `requires`, `client`, `class`, `function`, `interface`) | the Rust name plus `_`: `throws_`, `client_`, `self.class_(..)`. Function names built from a keyword (`parse_throws_clause`, `class_def`) keep their Rust spelling |
| a field that would clash with a method of the same class | the field gets a suffix (`tools_value`, `is_testset`); say so in a comment |
| a binding, field or parameter named `root` | not allowed (`root` is the package path): a `SourceRoot` becomes `root_id` (it is an id); a tree root becomes `file`/`root_node` |

## Types

| Rust | BAML |
|---|---|
| `Token<K>`, `Token![..]`, `TokenIdx` | `int` (token index) |
| `Id<T>` | `T` (the node itself; classes are references) |
| `Result<T, Missing>` | `T \| Missing` |
| `Option<T>` | `T?` |
| `List<T>`, `List1<T>`, `Vec<T>` | `T[]` |
| `Sep<T, S>`, `Sep1<T, S>` | `SepItem<T>[]` |
| `TextRange` / `TextSize` | `TextRange` / `int` (byte offsets) |
| `Any*` enum of node ids | `type AnyX = A \| B \| Bogus` (already in `nodes/`) |
| data enum (`ParseError`) | union of classes, narrowed with `match (e) { let x: Foo => .. }` |
| fieldless enum | `enum` |
| data enum variant `Expr::If { .. }` (AST and later, generated) | `class ExprIf { .. }`, union `type Expr = ExprIf \| ..`; a single unnamed payload `Literal(l)` is field `value`; a unit variant is an empty class |
| `View` lookups in the AST lowering (`view.range_of(id)`, `view.range_any(&any)`) | `view.range(node.span)`, `view.range(root.syntax.node_span(any))` |
| `usize`/`u32` | `int` |
| `HashSet<T>` | `map<T, bool>` |
| map keyed by a tuple `(A, B)` | `map<A, map<B, V>>` (tuples are not `baml.Hash` yet) |
| arena + `Idx<T>` (AST and later) | `T[]` + `int` id: later stages key results by id |
| `&str` / `String` | `string` |
| `&[T]` / `&mut Vec<T>` out-param | `T[]` (arrays are shared, so pushes are seen by the caller) |

## Parser specifics

| Rust | BAML |
|---|---|
| `p.alloc(mark, X { .. })` | `X { span: p.span_from(mark), .. }` |
| `p.alloc_to(mark, end, X { .. })` | `X { span: mark.to(end), .. }` |
| `p.out.get(id).field`, `p.out.list(list)` | `node.field`, the array itself |
| `p.out.span(id)` / `node_span(id)` | `node.span` |
| `p.mark_of(id)` / `mark_of_any(&any)` | `p.mark_of(node.span)` for a concrete node; `p.mark_of(node_span(any))` for an `Any*` union (`nodes/mod.baml`) |
| `p.cur.eat::<K>()` | `p.cur.eat(TokenKind.K)` → `int?` |
| `p.cur.eat_in::<S>()`, `eat_set::<S>(set)` | `p.cur.eat_in(SET)` → `int?` |
| `p.expect::<K>()` | `p.expect(TokenKind.K)` → `int \| Missing` |
| `p.cur.eat_op::<BinaryOp>()` | `p.cur.eat_binary_op()` (also `eat_assign_op`, `at_binary_op`, `at_assign_op`) |
| `let mut c = p.cur;` (a lookahead copy) | `let c = p.cur.copy();` **always copy**: `p.cur` is a reference |
| `p.cur = c;` | `p.cur = c;` |
| `p.attempt(\|p\| -> Result<T, ParseError>)` | `p.attempt((p) -> { .. })` with the closure returning `T \| ParseError`; `match` the result |
| bitflags (`Restrictions::STATEMENT \| NO_CATCH`) | a class of bools: `Restrictions.statement()`, `r.no_catch`, `Restrictions { ...r, no_catch: true }` |
| `.ok()` on a `T \| Missing` position | `ok(x)` (`ns_syntax/tree.baml`) |
| Rust std methods the BAML stdlib lacks (`strip_prefix`, `trim_start_matches`, `Vec::extend`) | `ns_base/std.baml` |
| `p.discard(f)`, `p.probe(f)` | same names |
| `p.sep_list::<T, S>(close, item)` | `p.sep_list(close, TokenKind.S, item)` |
| `p.sep1_list::<T, S>(first, item)` | `p.sep1_list(first, TokenKind.S, item)` |
| `p.members(.., \|p\| Some((item, sep_msg)))` | `p.members(.., (p) -> { Member { item: .., missing_sep: .. } })` |
| `p.enter_nesting(what)?` (Result<(), Missing>) | `let deep = p.enter_nesting(what); if (deep) { return deep; }` then `p.leave_nesting()` |
| `p.out.owned_tokens::<HeaderStmt/HeaderLine>()` | `p.out.owned_header_tokens()`; create those nodes through `p.out.header_stmt(..)` / `p.out.header_line(..)` |
| `TokenKind::X` / `K::X` | `TokenKind.X` |
| `matches!(p.cur.kind(0), Some(A \| B))` | `match` on `p.cur.kind(0)`, or `p.cur.at_in(SET)` |

## Control flow

| Rust | BAML |
|---|---|
| `x?` on Option | `let v = x ?? return null;` |
| `if let Some(v) = x { .. }` | `if (x != null) { .. }` (x a local) or `if let v: T = x { .. }` |
| `while let Some(v) = f() { .. }` | `while let v: T = f() { .. }` |
| `loop { .. }` | `while (true) { .. }` |
| `match` with guards | `match (v) { pat if cond => .., _ => .. }` |
| `debug_assert!`, `unreachable!` | `baml.sys.panic("..")` only where Rust would really panic; drop debug asserts |
| several values from one `match`, Rust tuples `(a, b)` | tuples: `let (let a, let b) = match ..`; `t.0`; patterns `(let a, _)` (needs a toolchain with upstream #5030) |
| `format!("..{x}..")` | `` `..${x}..` `` |

## Salsa (HIR and later)

The `Db` is `root.hir.Db` (`ns_hir/db.baml`); compile setup is `root.db.project_db`.

| Rust | BAML |
|---|---|
| `db: &dyn Db` parameter | `db: root.hir.Db` (bare `Db` inside `ns_hir`) |
| `#[salsa::input] SourceFile` / `SourceRoot` | `int` id; data via `db.file(id)` / `db.source_root(id)` (`root.base.SourceFile`, `root.base.SourceRoot`) |
| `file.text(db)`, `file.path(db)`, `file.source_root(db)` | `db.file(f).text`, `.path`, `.root` |
| `root.files(db)`, `root.kind(db)`, `root.dependencies(db)` | `db.source_root(r).files`, `.kind`, `.dependencies` |
| `db.source_roots().roots(db)` (table order) | `db.root_order` |
| `FunctionLoc::new(db, file, id)` (and Class/Enum/Interface/TypeAlias/Let/Impl) | `db.function_locs.intern(file, id)` → `int` (`db.class_locs`, ...) |
| `loc.file(db)`, `loc.id(db)` | `db.function_locs.get(loc).file`, `.id` |
| `ScopeId::new(db, file, file_scope_id)` | `db.scopes.intern(file, file_scope_id)` → `int` |
| `NamespaceId::new(db, package, path)` | `db.namespaces.intern(package, path)` → `int`; `db.namespaces.get(ns).package`, `.path` |
| `#[salsa::tracked] fn q(db, key) -> T { body }` | `function q(db: Db, key: int) -> T { db.memo.q.get(key, () -> { body }) }` (the `Memo<T>` field already exists on `Memos`) |
| a tracked query with no key (`workspace_roots`) | memo key `0` |
| `LocalItemId<Marker>` | `int` (packed `hash << 16 \| index`); `hash_name` is our own 16-bit hash (deviation: Rust's SipHash is not reproducible cheaply) |
| `seeded_*` inputs (cache seeding) | absent: always `None` |
| `Arc<T>` | `T` |


## Type family (`ty_family!`)

`baml_type`'s family is generated, as in Rust: `ns_types/ns_family_gen/spec.baml`
is the `ty_family!` invocation, `gen.baml` the macro, and `ns_types/family.baml`
the checked-in output. Change the spec, then from `bib/compiler`:

    baml run types.family_gen.main -- --out baml_src/ns_types/family.baml

- Variant classes are `<Member><Variant>` (`RuntimeTyList`); a variant with no
  nested type and one head across members is a single shared `Ty<Variant>`.
- Satellites keep Rust's names (`RuntimeFunctionParamTy`), except
  `InterfaceConstraint` (Rust's `Interface` satellite) and `AssociatedType`
  (Rust's `(Name, Ty)` pair; tuples are not hashable).
- Each member names its head type in the spec; conversions exist only between
  members at the same head.
- Rust's derived `Ord` is generated as `cmp_<member>` / `cmp_<satellite>`
  (variant declaration order, then fields); payload orders are in
  `ns_types/ord.baml`. Sort with `xs.sort_by(cmp_ty)` where Rust uses a
  `BTreeSet<Ty>` or `.sort()`.
- The generator runs only while the project checks. If a spec change breaks
  `family.baml` or `family_support.baml`, move both aside, regenerate, and put
  `family_support.baml` back.

## Generic unions and Result

- BAML type aliases take no generic parameters. A Rust generic enum becomes
  generic variant classes, and each instantiation in use gets its own alias:
  `type MemberResolution = MemberResolutionField<Ty> | ...;` and
  `type WorkingMemberResolution = MemberResolutionField<int> | ...;`.
- A Rust `Result<T, E>` returned from a function that may be a stub (or whose
  error is a plain enum) is `T | E`: a stub that declares `throws E` but
  never throws gets an "extraneous throws" warning (E0097). Elsewhere, use
  `throws`.
