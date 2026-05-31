#!/usr/bin/env python3
"""Single entrypoint for req stage transitions."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

# 让 _lib 可以 import（req-transition.py 自身在 scripts/，_lib 是同级子目录）
_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.state import (  # noqa: E402
    read_req_meta,
    StateReadError,
    get_stage_source,
    write_json_atomic,
)
from _lib.stages import (  # noqa: E402
    STAGE_NAMES,
    STAGE_OUTPUT_FILES,
    MAX_STAGE,
)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_meta(req_dir: Path) -> dict:
    try:
        return read_req_meta(req_dir, strict=True)
    except StateReadError as e:
        print(f"Error: {e.reason}: {e.path}", file=sys.stderr)
        sys.exit(1)


def save_meta(req_dir: Path, meta: dict) -> None:
    meta_file = req_dir / ".req-meta.json"
    write_json_atomic(meta_file, meta)


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
    文档改动自动 commit。覆盖 req-plan / DESIGN / task-plan / tasks/（在飞旧 req 仍含 brief/analysis/solution）。
    range 严格限定避免卷入主仓其他改动。

    rationale: build 阶段会触发 task-confirm 通过 git worktree add fork
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

    if target > MAX_STAGE:
        print(f"Error: invalid stage {target}. Max is {MAX_STAGE}.", file=sys.stderr)
        sys.exit(1)

    expected_next = current + 1

    if target != expected_next:
        print(f"Error: must advance to stage {expected_next} from {current} (got {target}).", file=sys.stderr)
        sys.exit(1)

    # Check prerequisite output file（六步：只有 stage 1「范围确认」有法定文档前置 =
    # req-plan.md；build / 复审 的闸门由 PM 验收 + task demo 确认把守，不靠文件存在性。
    # stage 真相源仍走 get_stage_source helper，尊重 .req-meta.json:stage{N}_source override）。
    if current in STAGE_OUTPUT_FILES:
        output_file = get_stage_source(req_dir, current)
        if not output_file.exists():
            print(
                f"Error: stage {current}（{STAGE_NAMES.get(current, '?')}）output file not found: {output_file.name}",
                file=sys.stderr,
            )
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

    if current == MAX_STAGE:
        print(f"Error: cannot rollback from stage {MAX_STAGE}（沉淀）. Merge to main is irreversible.", file=sys.stderr)
        sys.exit(1)

    # 复审（3）回退要求 task（demo 单元）都已确认/取消，避免回退丢在途 demo
    if current == 3:
        all_closed, open_tasks = check_all_tasks_closed(req_dir)
        if not all_closed:
            print("Error: cannot rollback from stage 3（复审）with open tasks:", file=sys.stderr)
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
