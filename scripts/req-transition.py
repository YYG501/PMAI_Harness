#!/usr/bin/env python3
"""Single entrypoint for req stage transitions."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

STAGE_NAMES = {
    1: "感受问题",
    2: "需求分析",
    3: "方案设计",
    4: "设计系统建立",
    5: "模块规格 + task 拆分",
    6: "task 执行",
    7: "req close",
}

# Stage N requires this output file to exist (for forward transitions)
STAGE_OUTPUT_FILES = {
    1: "brief.md",
    2: "analysis.md",
    3: "solution.md",
    # stage 4 output is docs/DESIGN.md (checked separately)
    5: "task-plan.md",
}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_meta(req_dir: Path) -> dict:
    meta_file = req_dir / ".req-meta.json"
    if not meta_file.exists():
        print(f"Error: .req-meta.json not found in {req_dir}", file=sys.stderr)
        sys.exit(1)
    return json.loads(meta_file.read_text(encoding="utf-8"))


def save_meta(req_dir: Path, meta: dict) -> None:
    meta_file = req_dir / ".req-meta.json"
    meta_file.write_text(
        json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def find_repo_root() -> Path:
    import subprocess
    try:
        common = subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], text=True
        ).strip()
        if common and common != ".git":
            return Path(common).resolve().parent
    except Exception:
        pass
    try:
        return Path(
            subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True
            ).strip()
        )
    except Exception:
        return Path.cwd()


def check_design_md_has_content(req_dir: Path) -> bool:
    """Check if docs/DESIGN.md has substantial content (not just skeleton).

    Looks at the current worktree's docs/DESIGN.md (not the main repo root's),
    because during req-transition the DESIGN.md that matters is the one on
    the req branch currently being advanced.
    """
    # req_dir is .../.worktrees/<branch>/requirements/active/<req> OR
    # <repo_root>/requirements/active/<req>. The worktree root is two levels up.
    worktree_root = req_dir.parent.parent.parent
    design_file = worktree_root / "docs" / "DESIGN.md"
    if not design_file.exists():
        # Fallback to main repo root for legacy callers
        repo_root = find_repo_root()
        design_file = repo_root / "docs" / "DESIGN.md"
        if not design_file.exists():
            return False
    content = design_file.read_text(encoding="utf-8")
    # Remove comments and empty lines
    lines = [
        l.strip()
        for l in content.split("\n")
        if l.strip() and not l.strip().startswith("<!--") and not l.strip().startswith(">")
    ]
    # More than just headings = has content
    non_heading = [l for l in lines if not l.startswith("#")]
    return len(non_heading) > 3


def check_all_tasks_closed(req_dir: Path) -> tuple[bool, list[str]]:
    """Check if all tasks in req are closed or cancelled.
    Tolerates both old paragraph format (**状态：** 值) and new task-card
    table format (| **状态** | 值 |). Skips engineering files (.engineering.md)
    so each task is only counted once via its PM-view main file.
    """
    tasks_dir = req_dir / "tasks"
    if not tasks_dir.exists():
        return True, []

    import re
    field_re_old = re.compile(r"^\*\*状态：\*\*\s*(.*)$")
    field_re_new = re.compile(r"^\|\s*\*\*状态\*\*\s*\|\s*(.*?)\s*\|.*$")
    open_tasks = []

    for tf in sorted(tasks_dir.glob("task-*.md")):
        # Skip the engineering companion file (PR 2 拆两文件约定)
        if tf.name.endswith(".engineering.md"):
            continue
        status = None
        with tf.open(encoding="utf-8") as fh:
            for idx, line in enumerate(fh):
                if idx >= 40:
                    break
                stripped = line.strip()
                m = field_re_old.match(stripped) or field_re_new.match(stripped)
                if m:
                    status = m.group(1).strip()
                    break
        if status and status in ("待执行", "执行中"):
            open_tasks.append(f"{tf.name} ({status})")

    return len(open_tasks) == 0, open_tasks


def seal_req_docs_before_transition(req_dir: Path, current: int, target: int) -> None:
    """I-DC1 pre-transition gate：把 req worktree 里 active req 范围内的未 commit
    文档改动自动 commit。覆盖 brief / analysis / solution / DESIGN / task-plan / tasks/。
    range 严格限定避免卷入主仓其他改动。

    rationale: stage 5→6 之后会触发 task-confirm 通过 git worktree add fork
    task 分支；working tree 飘的文档不会被 fork 带走。这道 gate 保证每次 stage
    切换都把当前 stage 的产出落盘，下游消费拿到的就是 PM 看过的版本。
    """
    import subprocess

    worktree_root = req_dir.parent.parent.parent
    if not (worktree_root / ".git").exists() and not (worktree_root / ".git").is_file():
        # req_dir 不在 git worktree 内（测试 fixture 等场景）→ 跳过
        return

    rel_req = req_dir.relative_to(worktree_root)
    pathspecs = [str(rel_req)]
    design_md = worktree_root / "docs" / "DESIGN.md"
    if design_md.exists():
        pathspecs.append("docs/DESIGN.md")

    try:
        status_out = subprocess.run(
            ["git", "-C", str(worktree_root), "status", "--porcelain", "--", *pathspecs],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except subprocess.CalledProcessError:
        return

    if not status_out:
        return

    dirty_files = [line[3:] if len(line) > 3 else line for line in status_out.splitlines()]
    print(
        f"⚠️ I-DC1 pre-transition gate: stage {current}→{target} 检测到 active req 范围内未 commit 文档改动，自动落盘：",
        file=sys.stderr,
    )
    for f in dirty_files:
        print(f"   - {f}", file=sys.stderr)

    try:
        subprocess.run(
            ["git", "-C", str(worktree_root), "add", "--", *pathspecs],
            check=True, capture_output=True,
        )
        diff_check = subprocess.run(
            ["git", "-C", str(worktree_root), "diff", "--cached", "--quiet"],
        )
        if diff_check.returncode == 0:
            return
        commit_msg = f"req: stage {current}→{target} seal docs"
        subprocess.run(
            ["git", "-C", str(worktree_root), "commit", "-q", "-m", commit_msg],
            check=True, capture_output=True,
        )
    except subprocess.CalledProcessError as e:
        stderr = e.stderr.decode("utf-8", errors="replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
        print(
            f"❌ I-DC1: pre-transition auto-commit 失败，拒绝推进 stage。请人工处理后重跑。\n   {stderr}",
            file=sys.stderr,
        )
        sys.exit(1)


def validate_forward(meta: dict, target: int, req_dir: Path) -> None:
    """Validate a forward stage transition."""
    current = meta["stage"]

    if target <= current:
        print(f"Error: target stage {target} is not forward from current stage {current}. Use --rollback for backward transitions.", file=sys.stderr)
        sys.exit(1)

    if target > 7:
        print(f"Error: invalid stage {target}. Max is 7.", file=sys.stderr)
        sys.exit(1)

    expected_next = current + 1

    # Stage 4 auto-skip: 只有 DESIGN.md 有实质内容时才能跳过 stage 4
    if expected_next == 4 and target == 5:
        if check_design_md_has_content(req_dir):
            expected_next = 5  # Allow 3 -> 5 (skip 4)
        else:
            print(
                "Error: DESIGN.md 还没有实质内容，不能跳过 stage 4（设计系统建立）。"
                "请先在 stage 4 填充 docs/DESIGN.md。",
                file=sys.stderr,
            )
            sys.exit(1)

    if target != expected_next:
        print(f"Error: must advance to stage {expected_next} from {current} (got {target}).", file=sys.stderr)
        sys.exit(1)

    # Check prerequisite output files
    if current in STAGE_OUTPUT_FILES:
        output_file = req_dir / STAGE_OUTPUT_FILES[current]
        if not output_file.exists():
            print(f"Error: stage {current} output file not found: {output_file.name}", file=sys.stderr)
            sys.exit(1)


def validate_rollback(meta: dict, target: int, req_dir: Path) -> None:
    """Validate a backward stage transition."""
    current = meta["stage"]

    if target >= current:
        print(f"Error: target stage {target} is not backward from current stage {current}.", file=sys.stderr)
        sys.exit(1)

    if target < 1:
        print(f"Error: invalid stage {target}. Min is 1.", file=sys.stderr)
        sys.exit(1)

    if current == 7:
        print("Error: cannot rollback from stage 7 (close). Merge to main is irreversible.", file=sys.stderr)
        sys.exit(1)

    # Stage 6 rollback requires all tasks closed/cancelled
    if current == 6:
        all_closed, open_tasks = check_all_tasks_closed(req_dir)
        if not all_closed:
            print("Error: cannot rollback from stage 6 with open tasks:", file=sys.stderr)
            for t in open_tasks:
                print(f"  - {t}", file=sys.stderr)
            sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Req stage transition")
    parser.add_argument("req_dir", help="Path to req directory")
    parser.add_argument("--to", type=int, required=True, dest="target", help="Target stage number")
    parser.add_argument("--rollback", action="store_true", help="Allow backward transition")
    args = parser.parse_args()

    req_dir = Path(args.req_dir).resolve()
    meta = load_meta(req_dir)
    current = meta["stage"]

    if args.rollback:
        validate_rollback(meta, args.target, req_dir)
        direction = "rollback"
    else:
        validate_forward(meta, args.target, req_dir)
        direction = "forward"
        seal_req_docs_before_transition(req_dir, current, args.target)

    # Execute transition
    meta["stage"] = args.target
    meta.setdefault("stage_history", []).append(
        {
            "stage": args.target,
            "entered_at": now_iso(),
            "direction": direction,
            "from_stage": current,
        }
    )
    save_meta(req_dir, meta)

    target_name = STAGE_NAMES.get(args.target, "?")
    current_name = STAGE_NAMES.get(current, "?")

    if direction == "rollback":
        print(f"⏪ Req stage 回退: {current} ({current_name}) → {args.target} ({target_name})")
    else:
        print(f"✅ Req stage 推进: {current} ({current_name}) → {args.target} ({target_name})")


if __name__ == "__main__":
    main()
