#!/usr/bin/env python3
"""Mirror new upstream canary commits into the fork, one --no-ff merge each,
and queue a port task for every commit that touches the frontend.

Usage:
  python3 bib/scripts/sync.py [--dry-run] [--limit N] [--no-push] [--no-fetch]
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
import tomllib
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIB = ROOT / "bib"
LEDGER = BIB / "ledger.jsonl"
PENDING = BIB / "ports" / "pending"
DONE = BIB / "ports" / "done"
LOCK = ROOT / ".git" / "bib-sync.lock"
TRAILER = "Upstream-Commit"


def git(*args: str, check: bool = True) -> str:
    r = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed:\n{r.stderr.strip()}")
    return r.stdout.strip()


def load_toml(name: str) -> dict:
    with open(BIB / name, "rb") as f:
        return tomllib.load(f)


def classify(path: str, rules: list[dict]) -> str:
    for rule in rules:
        if any(fnmatch.fnmatchcase(path, g) for g in rule["globs"]):
            return rule["class"]
    return "mirror"


def last_mirrored(upstream_ref: str) -> str:
    """Newest upstream commit already in main: the last Upstream-Commit trailer,
    falling back to the merge base (the fork point)."""
    sha = git("log", "-1", "--format=%(trailers:key=" + TRAILER + ",valueonly)", "--grep", f"^{TRAILER}:", "main")
    sha = sha.strip()
    return sha if sha else git("merge-base", "main", upstream_ref)


def changed_paths(sha: str) -> list[str]:
    return [p for p in git("diff-tree", "--no-commit-id", "-r", "--name-only", "-m", "--first-parent", sha).splitlines() if p]


def pr_number(subject: str) -> int | None:
    m = re.search(r"\(#(\d+)\)\s*$", subject)
    return int(m.group(1)) if m else None


def write_port_task(entry: dict, by_class: dict[str, list[str]], upstream_repo: str) -> Path:
    PENDING.mkdir(parents=True, exist_ok=True)
    key = f"pr{entry['pr']}" if entry["pr"] else entry["sha"][:12]
    path = PENDING / f"{key}.md"
    url = f"https://github.com/{upstream_repo}/pull/{entry['pr']}" if entry["pr"] else f"https://github.com/{upstream_repo}/commit/{entry['sha']}"

    def section(cls: str) -> str:
        files = by_class.get(cls, [])
        return "\n".join(f"- `{f}`" for f in files) if files else "_none_"

    path.write_text(
        f"""---
upstream_sha: {entry['sha']}
upstream_pr: {entry['pr'] or ''}
title: {json.dumps(entry['title'])}
url: {url}
merged_at: {entry['date']}
status: needs-intent   # needs-intent -> needs-port -> in-progress -> done | not-applicable
---

# {entry['title']}

Upstream: {url}

## Intent

<!-- Filled by the intent agent: what this PR changes about the language or the
     compiler's observable behavior, stated without reference to Rust code.
     Say "not applicable" with a reason for Rust-only refactors or perf work. -->

## Acceptance

<!-- Filled by the intent agent: the upstream tests/snapshots that pin this
     behavior, and how to check the BAML frontend matches (MIR diff, diagnostics). -->

## Upstream files

### frontend
{section('frontend')}

### spec
{section('spec')}

### shared
{section('shared')}
"""
    )
    return path


class Lock:
    def __enter__(self):
        try:
            self.fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(self.fd, str(os.getpid()).encode())
        except FileExistsError:
            raise SystemExit(f"another sync holds {LOCK} (delete it if stale)")
        return self

    def __exit__(self, *exc):
        os.close(self.fd)
        LOCK.unlink(missing_ok=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--no-push", action="store_true")
    ap.add_argument("--no-fetch", action="store_true")
    args = ap.parse_args()

    cfg = load_toml("config.toml")
    rules = load_toml("boundary.toml")["rule"]
    up = cfg["upstream"]
    upstream_ref = f"{up['remote']}/{up['branch']}"
    limit = args.limit or cfg["sync"]["max_commits_per_run"]

    with Lock():
        if git("rev-parse", "--abbrev-ref", "HEAD") != cfg["fork"]["branch"]:
            raise SystemExit(f"checkout {cfg['fork']['branch']} first")
        if git("status", "--porcelain", "--untracked-files=no"):
            raise SystemExit("working tree has uncommitted changes")
        if not args.no_fetch:
            git("fetch", "--quiet", up["remote"], up["branch"])

        base = last_mirrored(upstream_ref)
        todo = git("rev-list", "--reverse", "--first-parent", f"{base}..{upstream_ref}").splitlines()
        print(f"{len(todo)} upstream commit(s) after {base[:10]}; processing up to {limit}")

        mirrored = 0
        for sha in todo[:limit]:
            subject, date = git("log", "-1", "--format=%s%x00%cI", sha).split("\x00")
            paths = changed_paths(sha)
            by_class: dict[str, list[str]] = {}
            for p in paths:
                by_class.setdefault(classify(p, rules), []).append(p)
            entry = {
                "sha": sha,
                "pr": pr_number(subject),
                "title": subject,
                "date": date,
                "classes": {k: len(v) for k, v in sorted(by_class.items())},
                "port": "frontend" in by_class,
                "mirrored_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            }
            tag = "PORT  " if entry["port"] else "mirror"
            print(f"  {tag} {sha[:10]} {subject}  {entry['classes']}")
            if args.dry_run:
                continue

            bare = re.sub(r"\s*\(#\d+\)\s*$", "", subject)
            msg = f"upstream #{entry['pr']}: {bare}" if entry["pr"] else f"upstream: {subject}"
            r = subprocess.run(
                ["git", "-C", str(ROOT), "merge", "--no-ff", "--no-edit", "-m", msg, "-m", f"{TRAILER}: {sha}", sha],
                capture_output=True, text=True,
            )
            if r.returncode != 0:
                conflicts = git("diff", "--name-only", "--diff-filter=U").splitlines()
                # A frontend path the fork deleted: keep the deletion, the change becomes a port.
                deleted_ours = [c for c in conflicts if classify(c, rules) == "frontend"
                                and subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", f"HEAD:{c}"], capture_output=True).returncode != 0]
                if conflicts and set(deleted_ours) == set(conflicts):
                    for c in conflicts:
                        git("rm", "--quiet", "--", c)
                    git("commit", "--no-edit", "--quiet")
                    print(f"    resolved {len(conflicts)} conflict(s) by keeping fork-side deletions")
                else:
                    git("merge", "--abort", check=False)
                    entry["status"] = "blocked"
                    entry["conflicts"] = conflicts
                    print(f"    BLOCKED: merge conflict in {conflicts or r.stderr.strip()}", file=sys.stderr)
                    print("    resolve by hand: git merge --no-ff " + sha, file=sys.stderr)
                    return 2

            entry["status"] = "port-pending" if entry["port"] else "mirrored"
            with LEDGER.open("a") as f:
                f.write(json.dumps(entry) + "\n")
            git("add", str(LEDGER))
            if entry["port"]:
                git("add", str(write_port_task(entry, by_class, up["repo"])))
            git("commit", "--amend", "--no-edit", "--quiet")
            mirrored += 1

        if mirrored and cfg["fork"]["push"] and not args.no_push:
            git("push", "--quiet", "origin", cfg["fork"]["branch"])
            print(f"pushed {mirrored} commit(s) to origin/{cfg['fork']['branch']}")
        left = len(todo) - mirrored
        if left and not args.dry_run:
            print(f"{left} upstream commit(s) still to mirror")
        return 0


if __name__ == "__main__":
    sys.exit(main())
