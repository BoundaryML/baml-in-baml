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
| field named after a BAML keyword (`throws`, `requires`) | `throws_clause`, `requires_clause` |

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
| `usize`/`u32` | `int` |
| `HashSet<T>` | `map<T, bool>` |
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
| `p.attempt(\|p\| -> Result<T, E>)` | `p.attempt((p) -> { ... })` returning `T?` (null = Err) |
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
| several values from one `match` | `let (a, b) = match ..` once the nightly has tuples (upstream #5030, after nightly 20261115); until then a small named class |
| `format!("..{x}..")` | `` `..${x}..` `` |
