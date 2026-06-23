#!/usr/bin/env python3
"""检测 .worktrees/ 残留与编号冲突。

调用方：/next 或迁移排障时可手动跑。

检测项：
1. req 编号冲突 — 同一编号 req-NNN-* 出现 ≥ 2 个目录
2. 历史 task worktree 残留 — `.worktrees/task-*` 还存在

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

    # 1. req 编号冲突
    by_num: dict[str, list[str]] = defaultdict(list)
    for name in entries:
        m = re.match(r"^(req)-(\d+)-", name)
        if m:
            key = f"{m.group(1)}-{m.group(2)}"
            by_num[key].append(name)
    for key, names in sorted(by_num.items()):
        if len(names) >= 2:
            issues.append(f"编号冲突 {key}: {', '.join(names)}")

    # 2. 历史 task worktree 残留。当前流程不再创建 task-* worktree。
    for name in entries:
        if name.startswith("task-"):
            issues.append(f"历史 task worktree 残留: {name}（当前流程不再创建 task-* worktree）")

    if issues:
        print("⚠️ .worktrees/ 残留检测发现问题:", file=sys.stderr)
        for line in issues:
            print(f"  - {line}", file=sys.stderr)
        print("", file=sys.stderr)
        print("处理路径：", file=sys.stderr)
        print("  - 编号冲突：检查是否为旧 req 残留；需要时跑 /cancel 或手动移除旧 worktree", file=sys.stderr)
        print("  - 历史 task worktree：确认无未合并代码后 git worktree remove .worktrees/<name>", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
