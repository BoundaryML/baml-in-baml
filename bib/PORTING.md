# How the port works, micro level

We build the BAML compiler front to back, the same pipeline as the Rust one:

```
lex → parse (CST) → AST → HIR (names) → TIR (types) → MIR → bytecode
```

Each stage is a port: its data structures and functions are carried over from
the Rust crate one by one. Nothing is fed in from Rust; stage N+1 consumes
what our stage N produced.

## Size of the job (at the fork point)

| Stage | Rust crate | Lines |
|---|---|---|
| tokens, CST nodes | `baml_syntax` (+ `baml_syntax_macros` 1.2k) | 5.6k |
| lex + parse | `baml_parser` | 8.5k |
| AST | `baml_compiler2_ast` | 13.8k |
| HIR | `baml_compiler2_hir` | 11.2k |
| TIR | `baml_compiler2_hir_ty` | 57.7k |
| MIR | `baml_compiler2_mir` | 26.4k |
| bytecode | `baml_compiler2_emit` | 15.9k |
| shared | `baml_base` 3.6k, `baml_type` 23.2k, `baml_type_runtime` 1.4k, `baml_compiler_diagnostics` 4.2k | 32.4k |

About 170k lines, a third of it the type checker.

## 100% BAML

The compiler, its tests, `bless`, and every helper they use are BAML. No
Rust or Python of ours sits in the compile or test path. The only non-BAML
code in `bib/` is repo plumbing (`bib/scripts/sync.py`). Borsh reading and
writing, used for the precompiled stdlib interface and `EmittedPackage`, are
written in BAML on `uint8array`.

## The five rules

### 1. Same shape as the Rust code

One BAML namespace per Rust crate, one BAML file per Rust file, one BAML
function per Rust function, same names:

```
baml_compiler2_hir_ty/src/infer/call.rs :: fn infer_call
  → bib/compiler/baml_src/ns_hir_ty/ns_infer/call.baml :: function infer_call
```

Every ported item starts with `// port: <crate>/<path>::<item> @ <BASE sha>`.
This keeps review side-by-side, makes "what is left" a diff of two item lists,
and gives every future upstream PR an obvious place to land. We restructure
only where BAML forces it (rule 4) and say so in the header.

### 2. A stage is ported in a fixed order

For each stage:

1. **Data structures.** Ported by hand like everything else (token kinds,
   node structs, `Any*` unions, MIR `ir.rs`, bytecode `Instruction`), one Rust
   type per BAML type, same names.
2. **Functions, leaves first.** `bib/scripts/port_graph.py` builds the crate's
   call graph and lists every function with its callees. A function is ready
   to port when its callees are ported. The crate's own `#[cfg(test)]` tests
   are ported next to the functions they test, as BAML tests.
3. **Gate.** Our compiler's diagnostics equal the Rust compiler's on every
   corpus program in the feature slugs the stage covers so far (rule 3).

The next stage may start its data structures while the previous one finishes;
its functions wait for the gate.

### 3. Plain `baml check` and `baml test`, nothing bespoke

The compiler is an ordinary BAML project, `bib/compiler/` (with its own
`baml.toml`). The dev loop is the stock toolchain:

```bash
baml check bib/compiler     # the Rust compiler checks our compiler's source
baml test  bib/compiler     # our tests, including the oracle comparisons
```

The compiler's entry point has the same shape as the one BAML already exposes
to BAML code, `reflect.Package.compile(files, packages)`:

```baml
function check(files: map<string, string>) -> reflect.Diagnostic[]
```

So the oracle runs inside a BAML test, with no Rust tooling of ours: compile
the same files with `reflect.Package._compile` (the Rust compiler) and with our
`check`, and `assert.equal` the two diagnostic lists. The corpus files are read
with `baml.fs`. Every stage is measured this way, because every stage reports
diagnostics: the parser on `projects/broken_syntax`, name resolution and
typing on `projects/diagnostic_errors` and `baml_src`.

**The headline test:** our compiler checks its own source. `check` on
`bib/compiler/baml_src` must return exactly what `baml check bib/compiler`
reports: nothing on a clean tree, and the same errors on deliberately broken
copies. A compiler that agrees with BAML about a 170k-line BAML program is
most of the way there.

Code generation (MIR, bytecode) is tested by behavior once it exists: compile a
corpus program with our compiler, run it, and compare with the same program
compiled by `reflect.Package.compile`.

The upstream printers (`debug_tree`, `render_hir`, `display_function`,
`display_program`) can be ported later as debugging aids. They are not the gate.

**Our own test cases.** Besides the upstream corpus, `bib/cases/` holds cases
we write: good and bad BAML plus what should happen. The `.baml` file is plain
code; everything expected lives in a sidecar next to it:

```
bib/cases/match/non_exhaustive_union.baml
bib/cases/match/non_exhaustive_union.expect.toml
```

```toml
about = "Missing arm in a match over a union is an error."
# rust_differs = "reason the Rust compiler is expected to disagree"

[[diagnostics]]
severity = "error"
code = "E0150"
line = 5
col = 3
message = "non-exhaustive match: `Square` not covered"

[tests]                 # expected outcome of each test block, when run
area_of_circle = "pass"
```

- The folder is the case's feature slug (`match`, `generics`, `closures`, ...).
  There is no number or level field.
- No `[[diagnostics]]`: the file must check clean.
- `[tests]`: the case's `test` blocks are compiled by our compiler and run;
  each must end as listed.
- A multi-file case is a folder with one `expect.toml` at its root, and each
  diagnostic also names its `file`.
- `rust_differs`: the Rust compiler disagrees with the sidecar on purpose (an
  upstream bug, or behavior we chose differently). The case still runs against
  Rust, and fails if Rust starts agreeing, so the note never goes stale.

Every case runs against both compilers. Adding a case: write the `.baml`, run
`bless` (a function in `bib/compiler`, run with `baml run`) to write the
sidecar from the Rust compiler's output, review it, commit. Fixing a case:
edit the sidecar, plus `rust_differs` if Rust now disagrees. `bless` never
overwrites a sidecar that has `rust_differs` set.

**Feature slugs.** Upstream corpus programs and our cases are grouped by
feature slug, the order we expect a stage to start passing them:

`basics` (literals, lets, arithmetic, calls) → `control` (if, loops) →
`classes` (fields, arrays, maps) → `match` (enums, unions, type tests) →
`closures` → `errors` (throws, catch, defer) → `generics` (interfaces, impls) →
`modules` (globals, files, namespaces, packages) → `llm` (functions, clients,
templates, tests) → `stdlib` → `self` (our own compiler).

Upstream programs get their slug from the syntax they use; our cases from
their folder. Each slug is one `testset` per stage, so `baml test` output
reads as "the type checker passes `basics` through `match`".

### 4. One BAML idiom per Rust idiom

`bib/IDIOMS.md` is the translation table, backed by helpers in
`bib/compiler/baml_src/ns_prelude/`. It is settled before the first function
is ported, and a new idiom is added before it is used twice.

| Rust | BAML |
|---|---|
| data enum + `match` | union of classes + exhaustive `match` |
| `Option<T>`, `?` | `T?`, early `return null` |
| `Result<T, E>`, `?` | `throws E`, propagation |
| `HashMap` iterated where order matters | prelude `IndexMap` |
| `u32`/`usize` math that may overflow | `int` + prelude checked helpers |
| `&mut` out-params | return the value, or mutate a class field |
| `String` building | `string[]` + `join` |
| `panic!` / `expect` | `panic` with the same message |
| deep recursion | explicit work-stack where depth is input-controlled |
| trait + impls | `interface` + `implements` |
| `TextRange`, byte offsets | `int` byte offsets; source text indexed via `to_utf8()` once |

**Salsa** gets its own section of the table, because HIR and TIR are written
as salsa queries:

| Salsa | BAML |
|---|---|
| `#[salsa::input]` | fields of one `Db` class built at the start of a compile |
| `#[salsa::interned]` (`FunctionLoc`, `Name`, ...) | `int` index into an arena on `Db` (+ `map` for dedup) |
| `#[salsa::tracked] fn q(db, k)` | `function q(db, k)` memoized in a `map` on `Db` |
| accumulators (diagnostics) | `db.diagnostics.push(...)` |
| cycle recovery (`cycle_fn`) | explicit fixpoint loop, written where Rust declares the cycle |

No incrementality: a compile builds one `Db` and throws it away.

### 5. Pin the baseline

The initial port targets one upstream commit, `BASE` (in `bib/BASE`). Sync
keeps mirroring canary; compiler PRs after `BASE` queue as port tasks. A
stage's queued tasks are replayed in order once its gate passes at `BASE`, and
`BASE` advances with them. We never port against a moving tree.

## Decisions to make before stage 1

1. **Stdlib in name resolution and typing.** Every program sees the stdlib.
   Option A: compile the stdlib sources with our own pipeline every time
   (simple, slow, and the stdlib becomes the first slug for HIR/TIR instead of
   one of the last). Option B: read the precompiled stdlib `PackageInterface` blob the Rust
   build already produces (borsh decoder written in BAML), and
   compile the stdlib sources only at the `stdlib` slug. Upstream's own HIR tests do B
   (`set_seeded_stdlib_interface`). Proposed: B.
2. **Where the parser's macros go.** `baml_syntax_macros` derives node
   accessors and tree walking. Proposed: port what the macros expand to (the
   accessors and walkers) as plain BAML, never the macros themselves. `cargo
   expand` on `baml_syntax` shows the expansion.
3. **Source text access.** BAML `string` indexing is by character and O(n) after
   non-ASCII; Rust uses byte offsets everywhere. Proposed: the lexer works on
   `to_utf8()` bytes, all spans are byte offsets, text is sliced from bytes.

## Spikes first

Each answers one question with a number, before any tooling is built:

| Spike | Question | Pass |
|---|---|---|
| lexer speed | Port the lexer (no parser), lex the whole stdlib on the VM. | within 50x of Rust |
| check time | `baml check` on the compiler project: 75s at 34 files, ~3 min at 37. Profiled (2026-11-17, fork build with symbols): ~80% of active compiler time is `hir_ty::impls::hash_eligible_within_depth::visit`, reached from `method_resolution::lookup_impl_member` → `concrete_member_ambiguity` → `applicable_structural_interface_roots` → `hash_eligible(receiver)`. Every method call re-walks the receiver's whole type graph (fields, unions, list/map elements) with no memoization, so cost ≈ method calls × type-graph size. Upstream bug; fix is to memoize Hash eligibility per type or compute it only when the looked-up member belongs to `Hash`. |
| salsa idiom | Port one small memoized, cyclic TIR query (throws inference) with the table above. | same result on its upstream tests |
| oracle in BAML | A BAML test compiles one corpus file with `reflect.Package._compile` and gets the same diagnostics as `baml check` on it. | equal |

If the lexer is far too slow on the VM, the plan changes before 170k lines
depend on it: compile the BAML compiler to native code early through
`baml_compiler2_rust`.

## Spike results

| Spike | Result (2026-11-17, toolchain nightly 20261115) |
|---|---|
| oracle in BAML | Pass. A BAML test gets the Rust compiler's diagnostics through `reflect.Package._compile` (`ns_oracle/oracle.baml`). |
| lexer | Ported (`ns_syntax/lexer.baml`, `token.baml`); 88 table asserts from `lexer/tests.rs` pass. Whole stdlib (128 files, 1.47 MB, 257,053 tokens) lexes in 256 ms on the VM: ~5.7 MB/s, ~1M tokens/s. Rust baseline: pending. |
| big unions | `baml check` on the compiler project takes ~75s at 34 files / ~10k lines. Adding `types.baml` or `patterns.baml` alone to the foundation costs ~30s each; files without heavy `match` over node unions cost ~1s. Being bisected. |
| salsa idiom | not run |

## Parser gate (2026-11-17)

Parse diagnostics compared file by file with the Rust compiler (`root.oracle.corpus_summary`):

| Corpus | Match |
|---|---|
| `baml_tests/projects/broken_syntax` | 41/43 |
| `baml_tests/projects/diagnostic_errors` | 167/174 |
| `baml_tests/projects/parser_stress` | 5/5 |
| `baml_tests/baml_src` | 604/617 |
| stdlib (`baml_builtins2/baml_std`) | 128/128 |

With the oracle built from the fork at `BASE` (`baml toolchain use
<fork>/baml_language/target/release/baml-cli`): **967/967 files match**.

With nightly 20261115 as the oracle it was 945/967: all 22 mismatches were
files whose expected output changed in upstream #5030
(tuples, merged 2026-11-16). The oracle was nightly 20261115, which predates
it; the port follows `BASE`, which includes it. **The oracle must be the Rust
compiler at `BASE`**, not the installed nightly: build `baml-cli` from the fork
at `BASE` and select it with `baml toolchain use <path>` for oracle runs.

## AST lowering gate (2026-11-18)

`check()` runs parse + CST to AST lowering; compared with the Rust compiler's
parse diagnostics plus its lowering diagnostics (phase `hir`, lowering codes
E0001 E0010 E0017 E0098 E0108 E0127 E0147 E0152 E0171), warnings included:

| Corpus | Match |
|---|---|
| `projects/broken_syntax` | 43/43 |
| `projects/diagnostic_errors` | 173/174 |
| `projects/parser_stress` | 5/5 |
| `baml_tests/baml_src` | 613/617 |
| stdlib | 128/128 |

The 5 differences are all the 63-bit `int` limit (accepted): our lowering
rejects an i64-only literal that Rust rejects during type checking. They are
listed in `ns_oracle/corpus.baml::KNOWN_DIFFERENCES`.

Toolchain: upstream canary plus the lazy Hash-eligibility fix (separate PR);
`baml check` on this project went from 11 minutes to under a second. No
parser/AST/diagnostics changes between `BASE` and that canary, so it is a
valid oracle for these two stages.

## HIR gate (2026-11-18)

`check()` builds a `Db` (stdlib from source plus a workspace root) and reports
parse, lowering, HIR and package-level validation diagnostics (cross-file
name conflicts, namespace shadows), sorted by file then position as
`collect_compiler2_diagnostics` does. Compared with the Rust compiler's
phase `parse` + `hir` + `validation` diagnostics, on the compilation units
upstream's own tests use:

| Corpus | Unit | Units | Mismatches |
|---|---|---|---|
| `projects/broken_syntax` | each project | 28 (43 files) | 0 |
| `projects/diagnostic_errors` | each project | 135 (178 files) | 0 (1 known) |
| `projects/parser_stress` | each project | 5 | 0 |
| `baml_tests/baml_src` | the whole directory as one project | 1 (619 files) | 0 (1 known) |

Known differences are the accepted 63-bit `int` limit (`KNOWN_DIFFERENCES`;
diagnostics in those files are set aside, the rest of the unit still
compared). A crafted cross-file duplicate (E0011) matches too. Full run:
about 4 minutes.

`ported_layers` is now `parse`, `ast`, `hir`, `diag`: upstream changes to
these queue as port tasks. #5634 and #5715 (mirrored after `BASE`, while no
layer was marked ported) were reviewed by hand: neither needs a port.

## Agents

- A task is one Rust function (or a small cycle of them) whose callees are ported.
- One agent owns one Rust file at a time; files in the same stage run in parallel.
- Every task ends with `baml check` clean and `baml test` no worse than before.
- Reviews read the BAML next to the Rust it names in its header.

## TIR plan (2026-11-18)

Gate: our `check` equals the Rust compiler on phase `Type` too. The corpus
holds 1,444 Type diagnostics of ~60 codes in 170 units
(`baml run oracle.census -- --phase type`).

Entry: `baml_db/src/check.rs::check_file` (infer each body owner, then the
per-item lowering, defaults, trace-hook, `@json`, LLM-output, global-init and
interface checks) plus the ~1.5k lines of message building in check.rs
(959-2434), which land in `check.baml`.

Namespaces: `baml_type` is `types` (`ns_types`), `baml_compiler2_hir_ty` is
`hir_ty` (`ns_hir_ty`, with `infer/` and `interfaces/` as nested
namespaces).

Work packages (★ = depends only on what is ported):

| # | Package | Rust lines | After |
|---|---|---|---|
| ★A | `baml_type` helpers: lib.rs (Ty methods, rendering), names, head, param, primitive, int, defs, structural_interface, accepts_null, type_kind, json_tags, throw_facts, call_layout | 3.7k | family |
| B | interned.rs | 1.4k | A |
| C | decl_cycles.rs | 0.7k | A |
| D | json_inhabit.rs + the runtime_ty part llm_output reaches | 1.5k | A |
| E | normalize.rs + normalize/mu.rs (one cycle) | 5.3k | A, B |
| F | unify.rs, then pattern_overlap.rs | 3.3k | E |
| G | render.rs, diagnostics.rs, check.rs message layer | 5.5k | A |
| H | infer/unify.rs (InferenceTable) | 1.7k | B, G |
| I | exhaustiveness.rs core | 1.8k | G |
| J | defaults.rs | 0.6k | G |
| K1 | lower.rs, facts.rs, layout subset, extern_loc/package_interface stubs | 4.3k | E, F, G |
| K2 | interfaces.rs + interfaces/* | 5.5k | K1 |
| K3 | impls.rs, coherence subset, method_resolution (no IDE), callable, ops | 6.5k | K1, K2 |
| K4 | infer.rs + infer/* | 22k | K, H, I |
| L | trace_hooks, globals, init_io, llm_output, json_attrs, cleanup, rest of check.rs | 3.5k | K4 |

K1-K4 are one cycle in Rust (signature -> callable_throws -> infer_body ->
signature); they land function by function behind stubs. Salsa cycles
(`cycle_initial`/`cycle_result`) need the memo's in-progress state and
fixpoint iteration (`Memo.get_cyclic`), converging to Rust's values.

Deferred (not on the Type diagnostic path): ide.rs, template.rs,
simplify_sap, typetag, wire_head, codegen_ty, crossing, user_facing, most of
layout/throw_facts/coherence/method_resolution, and package_interface /
extern_loc beyond stubs (the stdlib is compiled from source, so no root is
served from an interface).

Checkpoints: each file's `#[cfg(test)]` tests ported beside it (normalize 82,
exhaustiveness 83, unify 38, infer/unify 30, pattern_overlap 25, ...); a
declaration gate after K1 (Type diagnostics outside bodies); an interface
gate after K3; upstream's 173 `type_spec` fixtures (`//^ ty` expression
types) after K4; then the full Type gate.

Port the memoized Hash-eligibility walk (impls.rs `hash_eligible`), not the
code at `BASE`: it is 80% of check time there.

Open items:
- (resolved) `hir_ty.reexport_paths`: a package compiled from source folds
  an interface with no re-exports (`fold_package_interface`), so it is
  always empty here.
- `json_inhabit` `solve` and `decl_cycles` `productive_aliases` are
  quadratic in chain length, as in Rust (a 3,000-class chain: 114 s on the VM).
- `ty_debug` (Rust's derived `Debug` of `Ty`, `family_stubs.baml`) panics.
  exhaustiveness's `write_type_witness` falls back to it for a type-test
  witness on a non-literal type; no corpus case reaches it so far. If one
  does, decide between matching Rust's `Int`-style output and spelling it
  (`int`).
- `register_class_bounds` (infer, U3) walks a class's generic bounds in
  frame order; Rust walks an FxHashMap. Obligation registration order, and
  so diagnostic push order, could differ. Same kind as the next item.
- `InferenceTable::take_solved_class_bounds` walks roots in index order;
  Rust walks its FxHashMap's order. Its one consumer (infer.rs ~15528)
  replays bounds; check the order does not leak into diagnostics.
- exhaustiveness's test helpers (`viewpoint`, `qtn`, `class_ty`,
  `USER_ROOT`, ...) are free functions in `hir_ty`; a later port of
  `test_heads.rs` must reuse them, not redefine them.
- normalize's mu-automaton is superlinear on the VM: a 500-level nesting
  under a recursive alias took 278 s (plain nesting: 0.1 s). Profile before
  the full gate. `baml check` on the compiler went from ~1 s to ~6 s with
  normalize in.
- normalize's test helpers (`Ctx`, `param`, `enum_ty`, `class1`, ...) are in
  `types` under their Rust names; pattern_overlap's tests reuse them.
- The Rust oracle serves the stdlib as a precompiled package interface; we
  compile it from source (decision 1, option A). Through HIR that made no
  difference; in TIR it can: `diagnostic_errors/anyfunction` gets E0153 from
  us for `implements reflect.AnyFunction for MyTool` (the source path checks
  the interface target; the interface path has no source location and skips
  it). Confirm against Rust, then either list such units in
  KNOWN_DIFFERENCES or serve the stdlib as an interface (decision 1, B).

## Declaration gate (2026-11-18, after K1)

`baml run oracle.decl_gate_summary`: Rust's Type-phase diagnostics from the
lowering functions (signature, class, let, alias, interface lowering) at
declaration positions, compared unit by unit. `callable_throws` pinned to its
seed; interface queries stubbed.

| Corpus | Match | Rust / ours | Stopped on a stub |
|---|---|---|---|
| `broken_syntax` | 28/28 | 5 / 5 | 0 |
| `diagnostic_errors` | 128/136 | 49 / 46 | 7 |
| `parser_stress` | 5/5 | 2 / 2 | 0 |
| `baml_src` (one unit) | - | - | 1 |

Every unit that ran matches except `tuples_map_keys` (3 E0067, from the
stubbed `map_key_is_hashable`). The stops are interface stubs (K2).

## K4 plan: body inference (infer.rs 16.6k + infer/*)

`InferenceContext`'s ~400 methods are spread over 7 Rust files, so in BAML
they are free functions taking `ctx: InferenceContext` (as `LowerCtx`'s
are). Names that collide with existing `hir_ty` free functions (`lang`,
`viewpoint`) get an `infer_ctx_` prefix. Files: `ns_hir_ty/infer.baml`
(split into `infer_<unit>.baml` parts, all `// port: .../infer.rs::...`) and
`ns_hir_ty/ns_infer/<file>.baml` for infer/*.

Unit 0 (first, alone, ~2.3k, mostly declarations): infer.rs 1-1807 minus
the queries (helpers, result and resolution types, `PendingDiag`,
`InferenceResult`), 2117-2389 (`SolveTier`, `Expectation`,
`InferenceContext` and its fields) and `new`; the type headers of
frames.rs, flow.rs, obligations.rs (incl. `Obligation`,
`instantiate_interface`) and truthy.rs; plus one stub file per unit
(`ns_hir_ty/infer_stubs_u1.baml` ... `u6`) with the exact signatures of
that unit's functions, panicking. Each unit replaces and deletes only its
own stub file.

| Unit | Owns (infer.rs lines unless named) | ~lines |
|---|---|---|
| U1 expressions, statements | 2390-4803 (core, `infer_expr`, `infer_stmt`, let, assign); frames.rs, flow.rs, reachability.rs rest; 15895-16020 | 3.4k |
| U2 subtyping, operators, obligations | 4804-6230; truthy.rs, obligations.rs rest; `operand_members` | 2.9k |
| U3 calls, lambdas | 6231-7743, 9070-9713, 10717-11282, 12467-12582; `function_param_pairs`, `effect_only_params`, `call_bound_purpose` | 3.1k |
| U4 paths, objects, annotations | 7744-9069, 9714-10716, 11283-11693; `generic_function_value_*`; trace_hooks.rs | 3.2k |
| U5 patterns, effects | pat.rs; 11694-12466 | 3.3k |
| U6 queries, finish | 1808-2116, 12583-15600 (`finish`), 15601-15894, 16067-16278, 16407-16530, tests; wires `callable_throws` to `infer_body` | 3.9k |

Big functions: `infer_expr` stays the dispatcher and keeps Rust's epilogue
last (3576-3578); large arms become `infer_expr_<variant>`. `finish` becomes
`finish_fixpoint`, `finish_quiescence`, `finish_throws`, `finish_tables`,
`finish_diagnostics` (its `PendingDiag` loop as `pending_diag_to_tir_<family>`
threading `reported_units`), `finish_writeback`, called in order. Child
inference order is significant everywhere (variable numbering, diagnostic
push order, flow state); the final diagnostic sort must be stable and the
dedup adjacent-only (14543-14557).

Cycles: `infer_function_body` / `infer_let_body` use `get_fixpoint` with
Rust's seeds (1808-1818, 1868-1890); the thread-local in-flight let set
(1822-1866) is a set on `Db` with explicit enter/leave.

After K4: port upstream's `type_spec` harness (173 fixtures with `//^ ty`
annotations; baml_tests/src/type_spec/harness.rs) as BAML tests.

## Declaration and interface gates (2026-11-18, after K2 + K3)

| Corpus | Declaration gate | Interface gate |
|---|---|---|
| `broken_syntax` | 28/28 (5 = 5) | 28/28 |
| `diagnostic_errors` | 136/136 (54 = 54) | 135/136 (4 / 5) |
| `parser_stress` | 5/5 (2 = 2) | 5/5 |
| `baml_src` (one unit) | 1/1 | 1/1 |

The one difference is `anyfunction` (E0153 `reflect.AnyFunction` is a
compiler builtin and cannot be implemented by hand): see the stdlib open
item. Each gate takes ~80 s.
- TIR ports read the Rust in the fork's tree, which mirrors upstream past
  `BASE` (e.g. #5715 changed infer.rs and infer/*). The oracle toolchain is
  built from that tree, so the code and the oracle agree; the `// port: ...
  @ d9be6853b` headers are nominal for TIR. Advance `BASE` when the TIR gate
  passes.

## Type gate, first run (2026-11-18, after K4)

`baml run oracle.types_gate_summary`: every diagnostic, all phases.

| Corpus | Match | Mismatches | Panicked |
|---|---|---|---|
| `broken_syntax` | 28/28 | 0 | 0 |
| `diagnostic_errors` | 123/136 (+1 known) | 6 | 6 |
| `parser_stress` | 5/5 | 0 | 0 |
| `baml_src` (one unit) | 0/1 | 0 | 1 |

Every panic is package L's `global_value_type` stub. Mismatches:
`trace_call_arguments` (E0002 `trace.Options` unresolved vs our E0007),
`catch_all_coverage` (missing E0002 `baml.panics.IndexOutOfBounds`),
`role_marker_interpolation` (`prompt` tag / `role`), `spawn_modifier_operands`
(interface rendering lists defaulted associated types; a missing
`baml.spawn.Root` error), `init_io_reachable` (package L), `anyfunction`
(E0154 and others). Several look like the stdlib-from-source open item.
Full run: ~2.5 min.

## TIR gate (2026-11-18)

The type checker is ported (packages A-L, K4 units 0-6) and `check_file`
runs it. `baml run oracle.types_gate_summary`, every diagnostic compared:
parse, HIR and validation against `reflect.Package._compile`, the rest
against `baml check` (cli_oracle.baml):

| Corpus | Unit | Units | Mismatches |
|---|---|---|---|
| `projects/broken_syntax` | each project | 28 | 0 |
| `projects/diagnostic_errors` | each project | 136 | 0 (1 known) |
| `projects/parser_stress` | each project | 5 | 0 |
| `baml_tests/baml_src` | the whole directory | 1 (619 files) | 0 (known only) |

Known differences are the 63-bit `int` limit. Full run: ~8 min.

Why `baml check` and not `reflect` for the Type phase: `reflect`'s compile
loads the stdlib as precompiled interfaces, whose lane skips stdlib bodies
for init io, hides private fields and drops some markers and impls; on
`baml_src` it reported ~280 diagnostics `baml check` does not. Our compiler
sees the stdlib's source, as `baml check` does.

`ported_layers` now includes `tir`: upstream changes to the type checker
queue as port tasks.

## type_spec (2026-11-18)

Upstream's inferred-type fixtures, read in place from
`baml_tests/src/type_spec/fixtures/` (`ns_oracle/ns_type_spec/`, a port of
`harness.rs` and `fixtures.rs`):

    baml run oracle.type_spec.type_spec_summary

| Check | Result |
|---|---|
| fixtures | 173/173 |
| caret annotations (inferred types, `throws`, error channel) | 355/355 |
| `render_infer` snapshots, compared as insta compares them | 5/5 |

Runs in ~6 s. A changed expectation is reported as
`line:col expected=<...> ours=<...>`; `baml test` includes the
all-fixtures test.

Verified (2026-11-18): every rule of `harness.rs` / `fixtures.rs` checked
against the port; an independent parser of Rust's annotation rules extracts
the same 355 annotations (343 type, 33 of them `throws`; 4 `mismatch:`;
7 `implements:`; 1 `non-exhaustive`) on the fixtures and on 18 edge-case
files. Mutating each annotation's expected text and caret range (710),
deleting each error-channel annotation (12) and adding bogus ones (23): every
mutation detected, at exactly its fixture and line:col. Snapshot comparison
follows insta 1.47 (trailing whitespace, CRLF, legacy leading `---`), checked
on 2,449 single-byte and structural mutations.

## Quality backlog (after the compiler works end to end)

Behavior is pinned by the Type gate, type_spec and its suites, so these are
safe mechanical passes, each re-checked against all three:
1. One-line forwarders left by the ports (`union_of`, `check_condition`, and
   a scan for others; `baml codequality` does not flag them).
2. `infer.rs` is split into `infer_u1*.baml` ... `infer_u6*.baml`, named
   after the porting units: rename to topic names that follow infer.rs.
3. Helpers outside their Rust home: the throw-fact flatteners
   (throw_facts.rs, package_interface.rs) in `infer.baml`; `member_owner`
   (baml_type) in `method_resolution.baml`.
4. TIR `// port:` headers say `@ d9be6853b` but were ported from the
   mirrored tree (#5715, #5718): advance `BASE` and fix the headers.
5. Dead code: `baml codequality --functions --metrics fan-in --all` lists
   342 functions nothing calls (65 are unused generated family functions,
   kept on purpose; others are entry points and test helpers). Review the
   rest by hand: unused here can mean used by MIR later.
6. The two map-order notes (`register_class_bounds`,
   `take_solved_class_bounds`).
