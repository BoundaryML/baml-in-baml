# Migration plan: the BAML frontend in BAML

Status: draft, 2026-11-17. Nothing below is built yet except the sync infra in `bib/`.

## The short version

1. Define a **frontend output** (FO): plain, serializable data holding everything
   downstream crates read from the frontend (declarations, layouts, signatures,
   MIR bodies, diagnostics). Today that seam does not exist.
2. Write a Rust **extractor** that produces FO from the existing Rust frontend.
   This is the oracle, forever.
3. Write the frontend in BAML, layer by layer, until it produces the same FO
   for every program in the test corpus.
4. Put a **facade** in front of the Rust frontend crates, switched by one root
   `Cargo.toml` change, so emit, the VM and every other consumer read FO instead
   of salsa queries, with zero edits to runtime crates.
5. Self-host, then flip the default.

The Rust frontend is never deleted. Upstream keeps changing it, the fork mirrors
those changes for free, and each change becomes a mechanical acceptance test
for the BAML port: the oracle's FO moved, so the BAML frontend's FO must move
the same way.

## What we learned about the codebase

### There is no MIR seam

`baml_compiler2_emit` does not consume a MIR value. `emit_package(db, root, opt)`
takes the salsa db, calls `lower_function(db, loc)` itself, and makes roughly
40 hir_ty queries while emitting (`layout`, `function_signature`,
`resolve_class_fields`, `impl_facts`, `runtime_throw_facts`, `plan_global_init`,
...). MIR (`baml_compiler2_mir/src/ir.rs`, ~30 types, ~120 variants) carries
`'db` lifetimes and salsa-interned ids (`FunctionLoc`, `ClassRef`, ...) and is not
serializable. Its pretty printer needs the db.

So "source to MIR in BAML, runtime unchanged" really means "source to
*everything emit asks the frontend*", and we have to build that contract.

### Who else reads the frontend

| Consumer | Reads | Plan |
|---|---|---|
| `baml_compiler2_emit` | MIR + ~40 HIR/TIR queries | FO via facade (phase 5) |
| `baml_compiler2_rust` (AOT) | MIR via `lower_program` | FO via facade (phase 5) |
| `baml_db` | drives check/compile, collects diagnostics | facade-aware driver (phase 5) |
| `bex_project` | parser, `infer_body`, `package_interface`; `build.rs` compiles stdlib | phase 6 |
| `bex_vm` | `runtime_type`, `hir_ty::interfaces` | stays on Rust frontend crates (types only) |
| `baml_builtins2_codegen` | parser + AST at build time for `$rust_function` stubs | stays on Rust parser |
| `baml_cli generate` | `baml_ide::build_symbol_pool` (HIR/TIR) | FO declarations (phase 5) |
| `baml_fmt` | syntax tree only | stays on Rust parser |
| `baml_ide` / LSP | ~215 HIR uses, incremental | phase 8, last |

Build-time tools (`builtins2_codegen`, `fmt`) keep using the Rust parser. They
are tooling around the runtime, not the compile path, and rewriting them buys
nothing.

### What BAML can express today

Enough for a compiler. The gaps and their workarounds:

| Gap | Workaround |
|---|---|
| No data-carrying enums | Unions of classes, `type Expr = Binary \| Call \| Lit`, narrowed with exhaustive `match` |
| No string builder | Push pieces to `string[]`, `join` once |
| `at(i)` is O(n) after the first non-ASCII char | Lexer indexes `to_code_points()` (`int[]`) once |
| No `Set` | `map<K, bool>` |
| 10 MiB VM stack | Explicit work-stacks for deep expression nesting |
| No visibility | Convention (`_name`) |

Calling BAML from Rust works (`bex_project::new` + `Bex::call_function`,
returning `BexExternalValue`). `reflect.Package.compile` already lets BAML call
the Rust compiler, which is handy for in-BAML differential tests.

## Architecture

```
                 ┌──────────────── oracle (Rust, mirrored from upstream) ──────────┐
 .baml sources ──┤ baml_parser → ast → hir → hir_ty → mir   ──bib_fo_extract──→ FO  ├─┐
                 └──────────────────────────────────────────────────────────────────┘ │ diff
                 ┌──────────────── frontend (BAML, ours) ──────────────────────────┐ │
 .baml sources ──┤ lex → parse → ast → resolve → check → lower        ─────────→ FO  ├─┘
                 └──────────────────────────────────────────┬──────────────────────┘
                                                             │ FO (bytes)
                          facade crates (Cargo rename) ◄─────┘
                                     │  same Rust API as hir/hir_ty/mir
                                     ▼
                emit, compiler2_rust, linker, VM, SDKs (unchanged)
```

### FO: the frontend output

- One file per compiled world: packages, then per package a declarations
  table (classes, fields, enums, interfaces, impls, type aliases, globals and
  their init plan, function signatures and metadata, throw facts, layouts),
  MIR bodies, and diagnostics (code, severity, file, span, message).
- Ids are stable qualified paths (`root.ns.Foo.bar`) and dense indices, never
  salsa ids. Spans are `(file, start, end)` byte offsets.
- Encoding: JSON first (BAML has `json` in the stdlib, diffs are readable).
  Switch to a binary encoding once the schema settles, if size or speed matters.
- **Schema source of truth is BAML.** The FO classes are declared in the BAML
  frontend package. Rust gets its types from BAML's own Rust SDK codegen
  (`baml_sdk`), so the contract cannot drift. If the Rust SDK cannot express
  something, fall back to hand-written serde types plus a schema-equality test.
- The FO's normal form is defined by the extractor: field order, sorting of
  declarations, how MIR temporaries are numbered. Both sides must canonicalize
  the same way or the diff is noise.

### The oracle: `bib_fo_extract`

A fork-owned crate that runs the Rust frontend through `baml_db` and walks the
same queries emit uses, writing FO. It is a pure reader: it does not change the
Rust frontend. Exposed as `baml bib dump-fo <project>` and as a test harness
over the corpus (`baml_tests/baml_src` 311 namespaces, `projects/` ~165).

The extractor only reads what emit and the other consumers read. A script
(`bib/scripts/facade_surface.py`) lists every frontend item imported by
non-frontend crates. Sync reruns it per upstream commit; if the surface grows,
the port task says so, because the FO schema and extractor must grow too.

### The facade

Every consumer depends on frontend crates through `[workspace.dependencies]` in
`baml_language/Cargo.toml`. The fork redirects those entries:

```toml
# baml_language/Cargo.toml (fork-only lines)
baml_compiler2_mir    = { path = "../bib/facade/mir",    package = "bib_facade_mir" }
baml_compiler2_hir_ty = { path = "../bib/facade/hir_ty", package = "bib_facade_hir_ty" }
```

Each facade crate does `pub use baml_compiler2_mir_real::*;` and shadows only the
query functions consumers call, choosing per world: FO-backed when the world
was compiled by the BAML frontend, delegate to Rust otherwise. Types (`FunctionLoc`,
`MirFunction`, ...) are the real crate's types, so emit compiles unchanged.

This is the only edit to an upstream file the plan needs, a handful of lines in
one `Cargo.toml`. Emit, the VM and the SDKs stay byte-identical to upstream.

## Phases

Each phase ends with a measurable gate on the whole corpus. A phase is
"ported" in `bib/config.toml` (`ported_layers`) once its gate is green on `main`.

| # | Phase | Output compared | Gate |
|---|---|---|---|
| 0 | **Seam.** FO schema, `bib_fo_extract`, `dump-fo`, facade surface script, corpus FO goldens | n/a | extractor runs on every corpus project; goldens checked in |
| 1 | **Lex + parse** in BAML; error-tolerant CST | token stream + CST + syntax diagnostics vs `test_02_cst` / `broken_syntax` | 100% corpus match |
| 2 | **AST + HIR**: desugaring, packages, scopes, name resolution | HIR dump vs `hir.snap`, name diagnostics | 100% |
| 3 | **TIR**: bidirectional checking, unions, generics, freshness, exhaustiveness | FO declarations + all diagnostics vs oracle | 100% of `diagnostics.snap` |
| 4 | **MIR lowering** + MIR optimize passes | FO MIR bodies vs oracle | 100% FO equality |
| 5 | **Flip behind a flag.** Facade crates, `BAML_FRONTEND=baml` for check/run/pack/generate | bytecode + runtime tests | full `baml_tests` suite green with the flag |
| 6 | **Self-host + stdlib.** BAML frontend compiles itself; stdlib interfaces built by it; seed artifact | stage1 bytecode == stage2 | fixpoint; `bex_project/build.rs` works from seed |
| 7 | **Default flip.** CLI uses BAML frontend by default; Rust frontend is oracle-only | latency budget | `baml check` exit latency within budget (see Risks) |
| 8 | **IDE.** LSP queries (hover, goto, completion) served from FO or BAML queries | LSP tests | LSP suite green |

Phases 1 to 4 run in production nowhere. They are validated against the oracle
only, which keeps the fork shippable at every commit.

### Bootstrap

- Stage 0: the Rust frontend compiles the BAML frontend package to bytecode.
- Stage 1: that bytecode, running on the VM, compiles the BAML frontend again.
- Stage 2: stage 1 compiles it once more; stage1 bytecode must equal stage2.
- Because the Rust frontend stays in the tree, stage 0 is always available and
  no checked-in seed binary is needed until we choose to drop the Rust path
  from release builds.

### Speed

The frontend will run on the VM, which upstream is making faster every week
(fast paths, superinstructions). The second lever is `baml_compiler2_rust`:
AOT-compile the BAML frontend to native Rust. A compiler in BAML that is
compiled to Rust by BAML is the long-term fast path, and it dogfoods the AOT
backend on a large, real program.

## How upstream PRs flow through this

Sync tags each port task with the frontend **layers** it touched (`parse`, `ast`,
`hir`, `tir`, `mir`, `diag`).

- **Layer not yet ported:** the task is `absorbed`. The BAML layer will be
  written against the oracle as it stands when we get there, so the change is
  picked up for free. No work.
- **Layer ported:** the oracle's FO for the corpus changes with the upstream
  commit. The port agent reads the PR's intent, re-plans the change in the BAML
  frontend, and is done when BAML FO equals oracle FO again on the full corpus.
  Upstream's new tests arrive with the mirror, so they are in the corpus too.
- **Facade surface grew** (emit started reading something new): the FO schema,
  extractor and facade grow first, then the port.
- **Rust-only change** (perf, salsa plumbing) with no FO diff: `not-applicable`,
  verified mechanically by "oracle FO unchanged".

The FO diff turns "did we capture the intent" from a judgment call into a test.
The intent doc is still written first, because the port should be designed for
the BAML frontend's own structure, not translated from Rust.

## Risks and open questions

1. **MIR churn.** Upstream changes MIR shape (e.g. #5678 changed `==` on null
   and enums). Every such PR needs a port once phase 4 lands. Expected and fine,
   but it sets the ongoing cost.
2. **Exact-match strictness.** Requiring byte-equal FO forces the BAML frontend
   to reproduce incidental choices (temp numbering, block order, diagnostic
   wording). Proposal: exact match on declarations and diagnostics; MIR compared
   after canonicalization (renumber locals and blocks in traversal order). Loosen
   further only with a written reason.
3. **Latency.** Agents iterate on `baml check` exit time. The VM-run frontend
   will start slower than Rust. Phase 7 needs a budget (proposed: within 2x of
   the Rust frontend on the corpus and a large real project) and the AOT path
   above.
4. **No incrementality.** The BAML frontend recompiles whole worlds. Fine for
   the CLI; a real problem for the LSP, which is why the IDE is last.
5. **FO schema via BAML Rust SDK** depends on that SDK expressing recursive
   unions well. Check in phase 0 before committing to it.
6. **Diagnostics with spans into desugared code** need the same span rules as
   ARCHITECTURE.md section 11, or diagnostic diffs will never converge.

## Phase 0 task list

- [ ] FO schema as BAML classes in `bib/frontend/baml_src/fo/`.
- [ ] Rust types from that schema (BAML Rust SDK, or serde fallback).
- [ ] `bib_fo_extract` crate + `baml bib dump-fo` (fork-only CLI hook, outside upstream crates if possible).
- [ ] FO goldens for the corpus under `bib/goldens/`, regenerated by sync after each mirrored commit; the golden diff goes into the port task.
- [ ] `bib/scripts/facade_surface.py` and its output `bib/facade_surface.txt`.
- [ ] Layer tagging in `sync.py` and `ported_layers` in `config.toml` (done with this plan).
- [ ] CI for the fork: a fork-owned workflow that runs only `bib/` checks, after re-enabling Actions with every inherited workflow disabled by name.
