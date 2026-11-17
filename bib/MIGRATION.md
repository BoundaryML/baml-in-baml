# Migration plan: the BAML compiler in BAML

Status: draft, 2026-11-17. Nothing below is built yet except the sync infra in `bib/`.
The micro-level method is in `bib/PORTING.md`.

## Scope

BAML owns the whole compiler. Rust keeps the runtime.

| Piece | Language | Notes |
|---|---|---|
| Lex, parse, AST, HIR, TIR, MIR, bytecode emit | BAML | ported front to back from the Rust crates |
| `baml generate` (SDK codegen) | BAML | after the compiler |
| Linker, bex VM, engine, sys_*, bridges, SDK runtimes | Rust | unchanged, mirrored from upstream |
| LSP / IDE | Rust | out of scope for now; keeps using the Rust compiler |
| `baml_fmt`, `baml_builtins2_codegen` | Rust | build tooling, keeps the Rust parser |

## Contracts with the runtime

The compiler talks to the outside world only through artifacts upstream
already defines and serializes. No upstream crate needs editing.

| Output | Upstream type | Consumer |
|---|---|---|
| Code | `EmittedPackage` (borsh, `baml_linker_types`) | `baml_linker` → bex VM |
| Public surface | `PackageInterface` (borsh) | dependent packages, precompiled stdlib |
| Diagnostics | code, severity, file, byte span, message | CLI |
| SDK | generated client files | user projects |

`baml_linker` depends only on `baml_linker_types`, `bex_vm_types` and `baml_type`,
so "`EmittedPackage` in, run it" is a clean seam. The BAML emitter writes
borsh bytes directly (writers generated from the Rust types).

## The Rust compiler is the oracle

It stays in the tree, mirrored from upstream. For every stage, the BAML
compiler's printer output must equal the Rust printer's on the corpus
(`PORTING.md`, rules 2 and 3). End to end, the runtime test suite must pass on
BAML-compiled bytecode, and generated SDK files must be byte-equal.

## Phases

| # | Phase | Gate |
|---|---|---|
| 0 | Spikes, `bib_typegen`, `bib_dump`, `bib diff`, `IDIOMS.md`, ladder, `BASE` | spikes pass; Rust dumps for the corpus exist |
| 1 | Lex + parse | tokens and CST (`debug_tree`) + syntax diagnostics equal |
| 2 | AST + HIR | `render_hir` output + name diagnostics equal |
| 3 | TIR | TIR dumps + all diagnostics equal; `PackageInterface` equal |
| 4 | MIR | `display_function` output equal |
| 5 | Bytecode | `display_program` output and `EmittedPackage` bytes equal; runtime suite passes |
| 6 | `baml generate` | generated SDK files byte-equal |
| 7 | Self-host + stdlib | stage1 bytecode == stage2; stdlib compiled by the BAML compiler |
| 8 | Default flip | `baml check` exit latency within budget |

### Bootstrap

- Stage 0: the Rust compiler compiles the BAML compiler to bytecode.
- Stage 1: that bytecode, on the VM, compiles the BAML compiler again.
- Stage 2: stage 1 compiles it once more; stage1 bytecode must equal stage2.
- The Rust compiler stays in the tree, so stage 0 is always available.

### Speed

The compiler runs on the VM, which upstream keeps making faster. The long-term
fast path is `baml_compiler2_rust`: AOT-compile the BAML compiler to native code.

## How upstream PRs flow through this

Sync tags port tasks with the layers they touch (`parse`, `ast`, `hir`, `tir`,
`mir`, `emit`, `codegen`, `diag`). `ported_layers` in `bib/config.toml` lists the
layers whose BAML version passed its gate.

- **Layer not ported yet:** `absorbed`, as long as the change landed before
  that layer's `BASE`. Changes after `BASE` queue and are replayed once the
  gate passes (`PORTING.md`, rule 5).
- **Layer ported:** the port agent reads the PR's intent, finds the BAML file
  that mirrors the touched Rust file, re-plans the change there, and is done
  when the stage diffs match again on the full corpus.
- **Rust-only change** with no printer diff: `not-applicable`.

## Risks

1. **Speed on the VM.** 170k lines of compiler running on the VM. The lexer
   spike measures this first.
2. **TIR is a third of the job** (57.7k lines) and the most salsa-shaped.
3. **Emit churn.** Upstream VM work changes emit often; those become ports
   once phase 5 lands.
4. **Stack depth.** 10 MiB VM stack; input-controlled recursion needs work-stacks.
5. **Latency.** Agents iterate on `baml check` exit time; phase 8 needs a budget.
