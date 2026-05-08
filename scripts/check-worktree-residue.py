#!/usr/bin/env python3
"""检测 .worktrees/ 残留与编号冲突。

调用方：req-stage-gate skill 在每次进入时跑一次；PM 也可手动跑。

检测项：
1. task 编号冲突 — 同一编号 task-NNN-* 出现 ≥ 2 个目录
2. req 编号冲突 — 同一编号 req-NNN-* 出现 ≥ 2 个目录
3. 闭合 req 残留 — req 在 requirements/closed/ 但 worktree 还在
4. 孤儿 task — task worktree 对应的 task 文件在任何 active req 里都找不到

退出码：
- 0：无问题
- 1：发现冲突或残留（输出到 stderr，列出每条）

不动文件（read-only），不调 git；只看目录结构。具体清理由 PM 决定。
"""
from __future__ import annotations
import json
import re
import sys
from collections import defaultdict
from pathlib import Path


def find_repo_root() -> Path:
    p = Path.cwd()
    for parent in [p, *p.parents]:
        if (parent / ".git").exists() or (parent / ".req-meta.json").exists():
            return parent
    return p


def main() -> int:
    repo = find_repo_root()
    wt_dir = repo / ".worktrees"
    if not wt_dir.is_dir():
        return 0

    entries = sorted(p.name for p in wt_dir.iterdir() if p.is_dir())
    if not entries:
        return 0

    issues: list[str] = []

    # 1+2. 编号冲突
    by_num: dict[str, list[str]] = defaultdict(list)
    for name in entries:
        m = re.match(r"^(task|req)-(\d+)-", name)
        if m:
            key = f"{m.group(1)}-{m.group(2)}"
            by_num[key].append(name)
    for key, names in sorted(by_num.items()):
        if len(names) >= 2:
            issues.append(f"编号冲突 {key}: {', '.join(names)}")

    # 3. 闭合 req 残留
    closed_dir = repo / "requirements" / "closed"
    closed_reqs: set[str] = set()
    if closed_dir.is_dir():
        for p in closed_dir.iterdir():
            if p.is_dir():
                m = re.match(r"^(req-\d+)-", p.name)
                if m:
                    closed_reqs.add(m.group(1))
    for name in entries:
        m = re.match(r"^(req-\d+)-", name)
        if m and m.group(1) in closed_reqs:
            issues.append(f"闭合 req 残留 worktree: {name}（已在 requirements/closed/）")

    # 4. 孤儿 task — task worktree 但找不到对应的 active req task 文件
    # 扫两处：main 仓的 requirements/active/ + 每个 req-* worktree 的 active/
    # 理由：active req 通常在自己 worktree 的分支上，main 视角下 active 是空的
    active_task_stems: set[str] = set()

    def _scan_active(active_dir: Path) -> None:
        if not active_dir.is_dir():
            return
        for req_dir in active_dir.iterdir():
            tasks_dir = req_dir / "tasks"
            if tasks_dir.is_dir():
                for tf in tasks_dir.iterdir():
                    if tf.is_file() and tf.suffix == ".md" and not tf.name.endswith(".engineering.md"):
                        active_task_stems.add(tf.stem)

    _scan_active(repo / "requirements" / "active")
    for name in entries:
        if name.startswith("req-"):
            _scan_active(wt_dir / name / "requirements" / "active")

    for name in entries:
        if name.startswith("task-") and name not in active_task_stems:
            issues.append(f"孤儿 task worktree: {name}（active req 里找不到对应 task 文件）")

    if issues:
        print("⚠️ .worktrees/ 残留检测发现问题:", file=sys.stderr)
        for line in issues:
            print(f"  - {line}", file=sys.stderr)
        print("", file=sys.stderr)
        print("处理路径：", file=sys.stderr)
        print("  - 编号冲突：检查是否为旧 req 残留；旧的跑 close-task / cancel-req 清理", file=sys.stderr)
        print("  - 闭合 req 残留：跑 git worktree remove .worktrees/<name>", file=sys.stderr)
        print("  - 孤儿 task：确认 task 是否被废弃；废弃的跑 task-transition --discard 归档", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
