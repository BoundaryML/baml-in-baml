# Rules for agents in baml-in-baml

This repo is upstream BAML plus a frontend rewritten in BAML. See `bib/README.md`.

- **Frontend** = source text to MIR: the crates listed under `class = "frontend"`
  in `bib/boundary.toml`. This is what gets rebuilt in BAML.
- **Runtime is frozen.** Do not change MIR → bytecode (`baml_compiler2_emit`),
  the VM (`bex_*`), SDKs, bridges or anything else upstream owns, except the
  minimum glue needed to feed BAML-produced MIR into the existing emit stage.
  Any such glue change gets called out in its PR.
- **Never edit mirrored upstream files for convenience.** Every edit to an
  upstream path is a future merge conflict. New work goes in new paths.
- **Port by intent.** When porting an upstream PR, plan from the Intent in its
  `bib/ports/*/pr<N>.md`, not by translating the Rust diff.
- **The Rust frontend is the oracle** until it is deleted: same input, same MIR
  and diagnostics.
- **Upstream is read-only.** Never push, comment or open PRs on `BoundaryML/baml`.
- `bib/ledger.jsonl` is append-only and written only by `bib/scripts/sync.py`.
- Never re-enable GitHub Actions on the fork without a human: the inherited
  workflows publish releases.
