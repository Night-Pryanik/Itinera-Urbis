#!/usr/bin/env python3
"""Reject changes that only re-indent files.

The project is written with 4-space indentation, but a few files legitimately
contain tab-indented regions (pasted code, the example mod's JSON). A rule that
forbids tabs would therefore raise false alarms. What actually breaks the build
is a wholesale re-indentation: every line of a file rewritten with another
indent while the code stays the same. GDScript then refuses to parse a file that
mixes both styles, and the whole game stops.

This check compares each changed file's diff with and without whitespace. A file
whose diff is large but whose whitespace-insensitive diff is nearly empty was
re-indented, not edited, and the commit is refused.

Usage:
    python tools/check_indentation.py            # working tree vs HEAD
    python tools/check_indentation.py --staged   # staged changes only (pre-commit)
    SKIP_INDENT_CHECK=1 git commit ...           # deliberate reformat: bypass

Exit code 0 — no suspicious re-indentation, 1 — at least one file was refused.
"""

from __future__ import annotations

import os
import subprocess
import sys

# A file passes when its whitespace-sensitive diff is close to its
# whitespace-insensitive one. Re-indentation makes the first huge and the second
# almost empty, so both a ratio and a floor are needed: small files must not trip
# the check over a handful of lines.
RATIO = 3.0
FLOOR = 30


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    return result.stdout if result.returncode == 0 else ""


def numstat(staged: bool, ignore_whitespace: bool) -> dict[str, int]:
    """Changed lines per file: additions plus deletions."""
    args = ["diff", "--numstat", "--no-color"]
    if staged:
        args.append("--cached")
    else:
        args.append("HEAD")
    if ignore_whitespace:
        args.append("-w")
    counts: dict[str, int] = {}
    for line in git(*args).splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        added, deleted, path = parts
        if added == "-" or deleted == "-":  # binary
            continue
        if "=>" in path:  # rename: not comparable across paths
            continue
        counts[path] = int(added) + int(deleted)
    return counts


def main() -> int:
    if os.environ.get("SKIP_INDENT_CHECK") == "1":
        print("check_indentation: skipped by SKIP_INDENT_CHECK")
        return 0

    staged = "--staged" in sys.argv[1:]
    plain = numstat(staged, ignore_whitespace=False)
    ignoring = numstat(staged, ignore_whitespace=True)

    failures: list[tuple[str, int, int]] = []
    for path, changed in sorted(plain.items()):
        if changed <= FLOOR:
            continue
        content_change = ignoring.get(path, 0)
        if changed > max(FLOOR, RATIO * content_change):
            failures.append((path, changed, content_change))

    if not failures:
        return 0

    print("check_indentation: these files look re-indented rather than edited:")
    for path, changed, content_change in failures:
        print(f"  {path}: {changed} changed lines, only {content_change} with whitespace ignored")
    print()
    print("The code of these files did not change — only its indentation did.")
    print("Restore them (git restore <file>) or, for a deliberate reformat,")
    print("commit with SKIP_INDENT_CHECK=1.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
