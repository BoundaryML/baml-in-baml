# baml-in-baml

A fork of [BoundaryML/baml](https://github.com/BoundaryML/baml) whose goal is a
BAML compiler frontend written in BAML.

## Goals

1. **Frontend in BAML.** Everything from source text to MIR (lexer, parser,
   AST, HIR, TIR, MIR lowering, diagnostics) is rewritten in pure BAML.
2. **Runtime unchanged.** MIR → bytecode (`baml_compiler2_emit`), the VM, the
   engine, SDKs and everything else stay exactly as upstream ships them.
3. **Track upstream by intent.** Every PR merged into upstream `canary` is
   mirrored here. If it touches the frontend, its *intent* is re-planned and
   re-built in the BAML frontend, not copied line by line.

## Layout

| Path | What |
|---|---|
| `bib/boundary.toml` | Which upstream paths are frontend (port), shared (flag) or mirror. |
| `bib/config.toml` | Sync and port settings (`port_enabled` gates the port agent). |
| `bib/ledger.jsonl` | One line per mirrored upstream commit, append-only. |
| `bib/ports/pending/` | Upstream PRs that touched the frontend and still need a BAML port. |
| `bib/ports/done/` | Ported, or judged not applicable (with the reason). |
| `bib/scripts/sync.py` | Mirrors new upstream commits, one merge per upstream PR, and queues ports. |
| `bib/agent/` | Prompts for the scheduled agent (sync, intent extraction, porting). |
| `bib/CLAUDE.md` | Rules for agents working in this fork. |
| `bib/MIGRATION.md` | The plan: FO seam, Rust oracle, facade, phases. |

## Branches and remotes

- `main` is the fork's trunk. It is upstream `canary` plus one `--no-ff` merge
  per upstream commit, plus port commits.
- Remote `upstream` = `BoundaryML/baml` (only `canary` is fetched).
- Remote `origin` = `BoundaryML/baml-in-baml`.
- GitHub Actions are disabled on the fork: the inherited release/publish
  workflows must never run here. Sync runs locally.
- LFS objects are read from upstream's LFS store (`.lfsconfig`).

## Sync loop

```bash
python3 bib/scripts/sync.py --dry-run     # show what would be mirrored
python3 bib/scripts/sync.py --limit 20    # mirror up to 20 upstream commits
```

For each new upstream commit, in order:

1. Classify its changed paths with `bib/boundary.toml`.
2. `git merge --no-ff` it into `main` (message `upstream #<pr>: <title>`,
   trailer `Upstream-Commit: <sha>`).
3. Append a ledger line.
4. If any `frontend` path changed, write `bib/ports/pending/<pr>.md`.
5. Amend the ledger and port file into that merge commit, so each upstream PR
   is exactly one fork commit.

A merge conflict outside `frontend` paths stops the loop and records the
commit as `blocked`; nothing after it is mirrored until a human resolves it.
Once a Rust frontend crate is deleted in the fork, conflicts on its paths are
resolved by keeping the deletion (the change lives on as a port task).

While the Rust frontend still exists here it keeps tracking upstream. It is the
oracle: the BAML frontend must produce the same MIR for the same input.
