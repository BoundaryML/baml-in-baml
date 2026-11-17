# Migration plan: the BAML compiler in BAML

Status: draft, 2026-11-17. Nothing below is built yet except the sync infra in `bib/`.

## Scope

BAML owns the whole compiler. Rust keeps the runtime.

| Piece | Language | Notes |
|---|---|---|
| Lexer, parser, AST, names, types, MIR lowering | BAML | MIR is ours to design |
| Bytecode emitter (MIR → `EmittedPackage`) | BAML | **built first** |
| `baml generate` (SDK codegen) | BAML | from the compiler's own declarations |
| Linker, bex VM, engine, sys_*, bridges, SDK runtimes | Rust | unchanged, mirrored from upstream |
| LSP / IDE | Rust | out of scope for now; keeps using the Rust frontend |
| `baml_fmt`, `baml_builtins2_codegen` | Rust | build tooling, keeps the Rust parser |

## Contracts

The compiler talks to the outside world only through artifacts upstream already
defines and serializes. These are the stable interface; everything inside the
compiler, MIR included, is ours.

| Output | Upstream type | Consumer |
|---|---|---|
| Code | `EmittedPackage` (borsh, `baml_linker_types`) | `baml_linker` → bex VM |
| Public surface | `PackageInterface` (borsh, `hir_ty::package_interface`) | dependent packages, precompiled stdlib |
| Diagnostics | code, severity, file, byte span, message | CLI |
| SDK | generated client files | user projects |

`baml_linker` depends only on `baml_linker_types`, `bex_vm_types` and `baml_type`,
so "`EmittedPackage` in, run it" is already a clean seam. No upstream crate
needs editing.

## The Rust oracle

The Rust compiler stays in the tree, mirrored from upstream. Upstream keeps
improving it and it keeps answering "what is the right output for this
program". Each phase gate compares against it on the corpus
(`baml_tests/baml_src`, 311 namespaces; `baml_tests/projects`, ~165 projects).

| Output | Comparison |
|---|---|
| `EmittedPackage` from the BAML emitter fed upstream MIR | byte-equal |
| Diagnostics | exact |
| `PackageInterface` | exact (the type checker's whole public verdict) |
| Generated SDK files | byte-equal |
| `EmittedPackage` from the full BAML compiler | behavioral: runtime test suite passes |

Byte-equal bytecode is required only while the emitter consumes upstream MIR.
Once the BAML frontend produces its own MIR, bytecode is checked by behavior,
so we are free to lower differently.

## The internal interface: `LoweredPackage`

The emitter's input is the one boundary *inside* the compiler worth designing
carefully: it separates "understand the program" from "encode it for the VM",
and it is what the Rust exporter writes in phase 1.

Today Rust emit has no such input. It takes a salsa db and makes ~70 distinct
frontend calls, including frontend work that leaked downstream (it lowers type
expressions itself via `lower_ctx_for_file` / `reject_holes`, recomputes function
metadata from TIR, runs escape analysis). `LoweredPackage` draws the line where
it should be:

**Frontend's job (in `LoweredPackage`):** anything that needs BAML semantics.
Resolved names, runtime types with no holes or aliases left, generic frames,
impl facts, throw sets, parameter defaults, global init order, MIR bodies.

**Emitter's job (not in it):** anything that is an encoding choice. Slot and
bucket numbering, import tables, operand layout, stack carrying, escape
analysis on MIR, verification.

Shape (BAML; written in `bib/compiler/baml_src/lowered/`):

```baml
class LoweredPackage {
  package PackageId
  deps PackageRef[]          // every package a ref may point into
  classes ClassDecl[]        // declaration order = file order
  enums EnumDecl[]
  interfaces InterfaceDecl[]
  aliases AliasDecl[]
  impls ImplDecl[]
  functions FunctionDecl[]   // signature, generic frame, defaults, origin, throws, body
  globals GlobalDecl[]       // top-level lets
  init_order string[]        // global paths, dependency order
  interface PackageInterface // the public surface, as upstream defines it
}

class FunctionDecl {
  path DeclPath
  signature RuntimeSignature
  generics GenericFrame
  defaults map<string, MirBody>
  origin FunctionOrigin
  throws RuntimeTy[]
  body MirBody?              // null for $rust_function
}
```

Rules:

- **Closed.** Every reference is a `DeclPath` (`package`, namespace, name). No
  salsa ids, no indices into tables the reader doesn't have.
- **Fully lowered types.** The emitter never sees a type expression.
- **Ordered.** Declaration lists are in the order emit numbers them (file order
  within a package), so numbering is a pure function of the input.
- **MIR starts as upstream's MIR**, with ids replaced by paths. That gives the
  byte-equal oracle in phase 1. We diverge deliberately in phase 4, when our
  frontend lowers its own way.
- **JSON** on disk at first (BAML's `json.decode<T>` reads it into these
  classes; diffs are readable). Binary later if size or speed matters.

## Phases

| # | Phase | Gate |
|---|---|---|
| 1 | **Emitter.** Rust exporter (Rust frontend → `LoweredPackage`), BAML emitter (`LoweredPackage` → `EmittedPackage`), `bib` runner | byte-equal `EmittedPackage` on the corpus; runtime suite passes on BAML-emitted bytecode |
| 2 | **Lex + parse** | tokens, CST and syntax diagnostics match `test_02_cst` / `broken_syntax` |
| 3 | **AST + names** | HIR dumps (`hir.snap`) and name diagnostics match |
| 4 | **Types** | all diagnostics + `PackageInterface` match |
| 5 | **MIR lowering** (our MIR) → our emitter | runtime suite passes end to end on the BAML compiler |
| 6 | **`baml generate`** | generated SDK files byte-equal |
| 7 | **Self-host + stdlib** | stage1 bytecode == stage2; stdlib interfaces built by the BAML compiler |
| 8 | **Default flip** | `baml check` exit latency within budget |

### Phase 1 in detail

The micro-level method (pinned baseline, generated types, per-function
diffs, the work graph, spikes) is in `bib/EMITTER_PORT.md`.

1. **`bib_lower_export`** (fork-owned Rust crate, in `bib/crates/`): runs the
   Rust frontend through `baml_db` and writes `LoweredPackage` JSON. It answers
   every question Rust emit asks; the list of emit's frontend imports is its
   checklist.
2. **BAML emitter** (`bib/compiler/baml_src/emit/`): port of
   `baml_compiler2_emit` (~16k lines: `emit.rs`, `analysis.rs`, `stack_carry.rs`,
   `items.rs`, `refs.rs`, `pull_semantics.rs`, `package/*`, `verifier.rs`).
   Output is `EmittedPackage` as JSON.
3. **Glue** (`bib/crates/bib_glue`): JSON → borsh `EmittedPackage`. Pure
   schema conversion, no semantics.
4. **`bib` runner** (`bib/crates/bib_cli`): `bib emit <project>` runs the BAML
   emitter on the VM (compiled by the Rust compiler: stage 0), links, and runs.
   `bib diff <project>` compares against Rust emit.

Phase 1 proves the whole loop (BAML compiler code running on the VM, producing
bytecode the Rust runtime executes) before any parser work, and its byte-equal
oracle is the strongest check we will ever have.

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

- **Layer not ported yet:** `absorbed`. It will be written against the oracle
  as it stands when we get there.
- **Layer ported:** the port agent reads the PR's intent, re-plans it for the
  BAML compiler, and is done when the oracle comparisons pass again on the full
  corpus. Upstream's new tests arrive with the mirror.
- **Emit after phase 1:** upstream VM work that changes the instruction set
  touches emit (in one 40-commit window: #5678, #5681, #5699). Those become
  emitter ports. This is the main ongoing cost of owning the emitter.
- **Rust-only change** with no oracle diff: `not-applicable`.

## Risks and open questions

1. **Emit churn.** Upstream VM perf work changes emit often. Watch the
   emit-port rate after phase 1; it sets the ongoing cost.
2. **Exporter completeness.** The exporter must answer everything emit asks.
   Byte-equality catches gaps, but only on inputs the corpus covers.
3. **Latency.** Agents iterate on `baml check` exit time. Phase 8 needs a
   budget (proposed: within 2x of the Rust compiler) and the AOT path.
4. **Stack depth.** 10 MiB VM stack; recursive passes over deep MIR or deep
   expressions need explicit work-stacks.
5. **Spans in desugared code** must follow ARCHITECTURE.md section 11, or
   diagnostic diffs never converge.
