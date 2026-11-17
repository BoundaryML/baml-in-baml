# Scheduled run: sync upstream, extract intent, port

You are the maintenance agent for the baml-in-baml fork at
`~/repos/company/baml-in-baml`. Read `bib/README.md` and `bib/CLAUDE.md` first.
Work only inside that checkout. Upstream (`BoundaryML/baml`) is read-only to you:
never push, comment, or open PRs there.

## 1. Preflight

```bash
cd ~/repos/company/baml-in-baml
git checkout main && git pull --ff-only origin main
```

If the tree is dirty or `main` has diverged, stop and report; do not force anything.

## 2. Mirror upstream

```bash
python3 bib/scripts/sync.py
```

Exit code 2 means a merge conflict outside the frontend. Stop the whole run and
report the upstream commit and conflicting paths. Do not resolve it yourself.

## 3. Intent (when `[ports] intent_enabled = true` in `bib/config.toml`)

Tasks whose `layers` are all unported are written straight to `bib/ports/done/`
with `status: absorbed` by sync; leave them alone. See `bib/MIGRATION.md`.

For each file in `bib/ports/pending/` with `status: needs-intent`, oldest
`merged_at` first, at most 10 per run:

1. Read the upstream PR: `gh pr view <pr> --repo BoundaryML/baml --json title,body,files,comments`
   and `gh pr diff <pr> --repo BoundaryML/baml`.
2. Fill **Intent**: what changed in the language or in the compiler's observable
   behavior (accepted programs, diagnostics, types, MIR shape, stdlib surface),
   stated in language terms, not Rust terms. Include the *why* from the PR body.
3. Fill **Acceptance**: the upstream tests/snapshots added or changed that pin
   the behavior (paths under `baml_language/crates/baml_tests/` etc.), and what
   the BAML frontend must reproduce (same MIR, same diagnostics, same types).
4. Set `status`:
   - `needs-port` when the BAML frontend must change.
   - `not-applicable` when the PR is Rust-only (perf, refactor, salsa plumbing,
     crate moves) with no observable effect; give the reason in Intent and
     `git mv` the file to `bib/ports/done/`.
5. One commit per PR: `bib: intent for upstream #<pr>`.

Push `main` when done.

## 4. Port (only when `[ports] port_enabled = true`)

Take the single oldest `needs-port` task. Skip this step if a fork PR from a
`port/*` branch is still open (`gh pr list --repo BoundaryML/baml-in-baml --head 'port/'`).

1. `git worktree add ../baml-in-baml-port-<pr> -b port/pr<pr> main`; set `status: in-progress`.
2. Plan from the Intent, not from the Rust diff. Re-design for the BAML
   frontend's own structure; the Rust code is a reference for behavior only.
3. Implement in the BAML frontend. Do not edit the runtime (see `bib/CLAUDE.md`).
4. Verify: BAML frontend output (FO) must equal the Rust oracle's FO on the
   whole corpus, not just the acceptance inputs (`bib/MIGRATION.md`, "The oracle").
5. Set `status: done`, `git mv` the task to `bib/ports/done/`, open a PR into
   `main` of `BoundaryML/baml-in-baml` titled `port #<pr>: <title>` with the
   intent and verification results in the body.

## 5. Report

End with a short summary: commits mirrored, ports queued, intents written,
ports opened, anything blocked.
