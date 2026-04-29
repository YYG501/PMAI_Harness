#!/usr/bin/env python3
"""Finalize a review run on a task: update PM view's GSTACK REVIEW REPORT
section and recompute engineering.md `synced_pm_view_hash`.

Why: review-input bundle 跑完后两件机械劳动重复出现：
1. shasum 重算 PM 视图 hash → 写工程合同顶部 `<!-- synced_pm_view_hash: ... -->`
2. 解析 PM 视图末尾 GSTACK REVIEW REPORT 表，increment runs / 替换 status /
   replace findings / update verdict 行

本脚本一次完成。AI 在 chat 协助分流写完源文件后调本脚本收尾。

Usage:
  finalize-review.py <pm-view-file>
      --review {ceo,codex,eng,design,dx}
      --status "CLEAN (PLAN)" | "ISSUES_OPEN" | "CLEAN (FULL)" | etc
      --findings "<single-line summary>"
      [--unresolved N]   set the **UNRESOLVED total** line (default: don't touch)
      [--verdict TEXT]   replace **VERDICT** line wholesale (default: don't touch)
      [--no-hash]        skip hash recompute (use when only PM view末 reporting changed)

Behavior:
- Locate `## GSTACK REVIEW REPORT` section in PM view file.
- Find row matching review type (Eng / Design / CEO / Codex / DX).
- Increment Runs cell by 1.
- Replace Status + Findings cells.
- (optional) Replace UNRESOLVED line.
- (optional) Replace VERDICT line.
- Recompute PM view shasum -a 256 | cut -c1-12 → write into the
  `<pm-view-stem>.engineering.md` `<!-- synced_pm_view_hash: ... -->` comment
  if the file exists.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REVIEW_LABEL = {
    "ceo": "CEO Review",
    "codex": "Codex Review",
    "eng": "Eng Review",
    "design": "Design Review",
    "dx": "DX Review",
}


def find_repo_root() -> Path:
    try:
        return Path(
            subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True
            ).strip()
        )
    except Exception:
        return Path.cwd()


def compute_pm_view_hash(pm_view: Path) -> str:
    """Replicates `shasum -a 256 <file> | cut -c1-12`."""
    out = subprocess.check_output(["shasum", "-a", "256", str(pm_view)], text=True)
    return out.split()[0][:12]


def update_review_table_row(
    pm_text: str,
    review_label: str,
    new_status: str,
    new_findings: str,
) -> tuple[str, bool]:
    """Find row matching review_label in GSTACK REVIEW REPORT table; bump Runs,
    replace Status + Findings cells. Returns (new_text, found)."""
    # Match table row pattern: | <label> | <trigger> | <why> | <runs> | <status> | <findings> |
    # Be forgiving on spacing.
    pattern = re.compile(
        r"^(\|\s*"
        + re.escape(review_label)
        + r"\s*\|[^|]*\|[^|]*\|\s*)"        # group 1: prefix through start of runs cell
        r"([^|\s]+)"                          # group 2: runs (number or "—")
        r"(\s*\|\s*)"                         # group 3: separator
        r"([^|]*)"                            # group 4: status cell
        r"(\s*\|\s*)"                         # group 5: separator
        r"([^|\n]*)"                          # group 6: findings cell
        r"(\s*\|\s*)$",                       # group 7: trailing
        re.MULTILINE,
    )

    def replace(m: re.Match) -> str:
        runs_cell = m.group(2).strip()
        try:
            new_runs = str(int(runs_cell) + 1)
        except ValueError:
            new_runs = "1"  # was "—" or other
        return (
            m.group(1)
            + new_runs
            + m.group(3)
            + " "
            + new_status
            + " "
            + m.group(5)
            + " "
            + new_findings
            + " "
            + m.group(7)
        )

    new_text, n = pattern.subn(replace, pm_text, count=1)
    return new_text, n > 0


def update_unresolved_line(pm_text: str, unresolved: int) -> str:
    """Replace `**UNRESOLVED**: <N>` line. Append if missing."""
    pattern = re.compile(r"^\*\*UNRESOLVED\*\*:\s*\d+\s*$", re.MULTILINE)
    replacement = f"**UNRESOLVED**: {unresolved}"
    new_text, n = pattern.subn(replacement, pm_text, count=1)
    if n == 0:
        # Append before VERDICT line if exists, else end of GSTACK section.
        verdict_pos = pm_text.find("**VERDICT**:")
        if verdict_pos != -1:
            new_text = (
                pm_text[:verdict_pos] + replacement + "\n" + pm_text[verdict_pos:]
            )
        else:
            new_text = pm_text.rstrip() + "\n\n" + replacement + "\n"
    return new_text


def update_verdict_line(pm_text: str, verdict: str) -> str:
    """Replace the **VERDICT**: ... line (potentially multi-line until next blank
    line / next ## heading). Append if missing."""
    pattern = re.compile(
        r"^\*\*VERDICT\*\*:.*?(?=^\s*$|\Z|^##\s)",
        re.MULTILINE | re.DOTALL,
    )
    replacement = f"**VERDICT**: {verdict}\n"
    new_text, n = pattern.subn(replacement, pm_text, count=1)
    if n == 0:
        new_text = pm_text.rstrip() + "\n\n" + replacement
    return new_text


def update_engineering_hash(pm_view: Path, new_hash: str) -> tuple[bool, str]:
    """Update `<!-- synced_pm_view_hash: ... -->` in <stem>.engineering.md.
    Returns (updated, message)."""
    eng_path = pm_view.with_name(pm_view.stem + ".engineering.md")
    if not eng_path.exists():
        return False, f"engineering view not found: {eng_path.name} (skipped hash)"

    eng_text = eng_path.read_text(encoding="utf-8")
    pattern = re.compile(r"<!--\s*synced_pm_view_hash:\s*[a-f0-9]+\s*-->")
    replacement = f"<!-- synced_pm_view_hash: {new_hash} -->"
    new_text, n = pattern.subn(replacement, eng_text, count=1)
    if n == 0:
        return False, (
            f"no `synced_pm_view_hash` comment found in {eng_path.name}; "
            f"first reconcile should add it manually before using this script"
        )
    if new_text == eng_text:
        return True, f"hash unchanged ({new_hash})"
    eng_path.write_text(new_text, encoding="utf-8")
    return True, f"hash updated → {new_hash}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Finalize a review run: update GSTACK REVIEW REPORT row + recompute synced_pm_view_hash"
    )
    parser.add_argument("pm_view", help="Path to PM view file (.md, not .engineering.md)")
    parser.add_argument(
        "--review",
        required=True,
        choices=sorted(REVIEW_LABEL.keys()),
        help="Review type",
    )
    parser.add_argument("--status", required=True, help="Status cell value (e.g. 'CLEAN (FULL)' / 'ISSUES_OPEN')")
    parser.add_argument(
        "--findings",
        required=True,
        help="Findings cell value (single-line summary; can include markdown inline)",
    )
    parser.add_argument(
        "--unresolved",
        type=int,
        default=None,
        help="Update **UNRESOLVED** total line (default: leave existing)",
    )
    parser.add_argument(
        "--verdict",
        default=None,
        help="Replace **VERDICT** line wholesale (default: leave existing)",
    )
    parser.add_argument(
        "--no-hash",
        action="store_true",
        help="Skip hash recompute (use when PM view content unchanged)",
    )
    args = parser.parse_args()

    pm_view = Path(args.pm_view).resolve()
    if not pm_view.exists():
        sys.exit(f"Error: PM view not found: {pm_view}")
    if pm_view.name.endswith(".engineering.md"):
        sys.exit("Error: pass PM view (.md), not .engineering.md")

    label = REVIEW_LABEL[args.review]
    pm_text = pm_view.read_text(encoding="utf-8")

    # Update the row
    pm_text, found = update_review_table_row(pm_text, label, args.status, args.findings)
    if not found:
        sys.exit(
            f"Error: row '{label}' not found in GSTACK REVIEW REPORT table. "
            f"Make sure PM view has a `## GSTACK REVIEW REPORT` table with a "
            f"row labeled '{label}'."
        )

    # Update UNRESOLVED if asked
    if args.unresolved is not None:
        pm_text = update_unresolved_line(pm_text, args.unresolved)

    # Update VERDICT if asked
    if args.verdict is not None:
        pm_text = update_verdict_line(pm_text, args.verdict)

    pm_view.write_text(pm_text, encoding="utf-8")
    print(f"✅ PM view updated: {label} runs +1, status='{args.status}'")
    if args.unresolved is not None:
        print(f"   UNRESOLVED → {args.unresolved}")
    if args.verdict is not None:
        print(f"   VERDICT replaced")

    # Recompute hash
    if args.no_hash:
        print("   hash: skipped (--no-hash)")
        return

    new_hash = compute_pm_view_hash(pm_view)
    updated, msg = update_engineering_hash(pm_view, new_hash)
    prefix = "✅" if updated else "⚠️ "
    print(f"   {prefix} {msg}")


if __name__ == "__main__":
    main()
