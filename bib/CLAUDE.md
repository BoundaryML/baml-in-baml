# Rules for agents in baml-in-baml

This repo is upstream BAML plus its compiler rewritten in BAML. See `bib/README.md`.

- **Compiler** = everything from source text to `EmittedPackage` plus `baml generate`:
  the crates with `class = "frontend"` in `bib/boundary.toml`. This is what gets
  rebuilt in BAML, under `bib/compiler/`. Ported front to back, file by file (`bib/PORTING.md`).
- **Runtime is frozen.** Do not change the linker, the VM (`bex_*`), sys_*,
  bridges or SDK runtimes. The contracts are upstream's `EmittedPackage` and
  `PackageInterface`; fork-owned Rust glue lives in `bib/crates/`.
- **LSP is out of scope** for now and keeps using the Rust frontend.
- **Never edit mirrored upstream files for convenience.** Every edit to an
  upstream path is a future merge conflict. New work goes in new paths.
- **Port by intent.** When porting an upstream PR, plan from the Intent in its
  `bib/ports/*/pr<N>.md`, not by translating the Rust diff.
- **The Rust compiler is the oracle** and stays in the tree. See "The Rust oracle"
  in `bib/MIGRATION.md` for what must match.
- **Upstream is read-only.** Never push, comment or open PRs on `BoundaryML/baml`.
- `bib/ledger.jsonl` is append-only and written only by `bib/scripts/sync.py`.
- Never re-enable GitHub Actions on the fork without a human: the inherited
  workflows publish releases.
