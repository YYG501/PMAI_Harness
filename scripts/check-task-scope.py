#!/usr/bin/env python3
"""Check whether a set of changed paths falls within a task's allowlist.

Called by exec-adapters after executor exits:
  git diff --name-only HEAD | check-task-scope.py <task_file>

Exit codes:
  0 = all paths within allowlist (or allowlist undeclared — advisory pass)
  1 = at least one path outside allowlist (violation)
  2 = usage / file error

Allowlist format mirrors build-execution-prompt.py:parse_scope (新建:/修改:
entries). Glob patterns supported via fnmatch.
"""

from __future__ import annotations

import argparse
import fnmatch
import re
import sys
from pathlib import Path


def extract_scope_section(text: str) -> str:
    pattern = re.compile(r"^## 执行范围.*$", re.MULTILINE)
    match = pattern.search(text)
    if not match:
        return ""
    start = match.end()
    nxt = re.search(r"^## ", text[start:], re.MULTILINE)
    return text[start : start + nxt.start()] if nxt else text[start:]


def parse_allowlist(section: str) -> tuple[list[str], list[str]]:
    allow: list[str] = []
    deny: list[str] = []
    for raw in section.splitlines():
        stripped = raw.strip()
        if not stripped.startswith("-"):
            continue
        body = stripped.lstrip("-").strip()
        bucket: str | None = None
        rest: str | None = None
        for prefix, b in (
            ("新建：", "allow"),
            ("新建:", "allow"),
            ("修改：", "allow"),
            ("修改:", "allow"),
            ("不动：", "deny"),
            ("不动:", "deny"),
        ):
            if body.startswith(prefix):
                bucket = b
                rest = body[len(prefix):]
                break
        if bucket is None or rest is None:
            continue
        items = [x.strip() for x in rest.split(",") if x.strip()]
        (allow if bucket == "allow" else deny).extend(items)
    return allow, deny


def matches_any(path: str, patterns: list[str]) -> bool:
    for pat in patterns:
        # Exact
        if path == pat:
            return True
        # Glob
        if fnmatch.fnmatch(path, pat):
            return True
        # Dir prefix: "prototypes/" matches "prototypes/foo/bar.ts"
        if pat.endswith("/") and path.startswith(pat):
            return True
    return False


# 项目级 / 兄弟 task 文件不应由 task commit 修改（PM 在 req worktree 维护，
# task worktree 通过 4.5f drift 检测 + apply-req-doc 单文件 PM 决策拉取，
# 不走 task commit）。implicit_deny 优先级高于 allowlist——即便 allowlist 显式命中也拒。
PROJECT_LEVEL_FILES = {"DESIGN.md", "CLAUDE.md"}
REQ_DIR_PREFIX = "requirements/active/"


def implicit_deny_reason(path: str, task_stem: str) -> str | None:
    """返回 deny 原因（命中保留路径且不是自己的 task 文件）；否则 None。"""
    if path in PROJECT_LEVEL_FILES:
        return f"项目级文档（PM 在 req worktree 维护，task 不得 commit）"
    if path.startswith(REQ_DIR_PREFIX):
        # 自己的 task PM 视图 / 工程合同 允许
        own_pm = f"tasks/{task_stem}.md"
        own_eng = f"tasks/{task_stem}.engineering.md"
        if path.endswith(own_pm) or path.endswith(own_eng):
            return None
        return "req 目录内非本 task 文件（PM 在 req worktree 维护，task 不得 commit）"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Check task allowlist vs changed paths")
    parser.add_argument("task_file", help="Path to task file")
    parser.add_argument(
        "--paths-from",
        default="-",
        help="File with one path per line, or '-' for stdin (default)",
    )
    parser.add_argument(
        "--allow-empty",
        action="store_true",
        help="Treat empty allowlist as advisory pass (default: strict fail)",
    )
    args = parser.parse_args()

    task_file = Path(args.task_file)
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        print(
            "  修复：检查路径拼写；task 文件应位于 "
            "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md。"
            "若 task 还没生成，先在 req worktree 跑 /task-spec <task-id>。",
            file=sys.stderr,
        )
        return 2

    text = task_file.read_text(encoding="utf-8")
    section = extract_scope_section(text)
    allow, deny = parse_allowlist(section)

    if args.paths_from == "-":
        paths = [l.strip() for l in sys.stdin.read().splitlines() if l.strip()]
    else:
        with open(args.paths_from, encoding="utf-8") as fh:
            paths = [l.strip() for l in fh.read().splitlines() if l.strip()]

    if not paths:
        # Nothing changed — trivially passes
        print("✅ 无变更文件，scope 校验通过", file=sys.stderr)
        return 0

    task_stem = task_file.stem

    # Implicit deny（sync 白名单：项目级 + 同 req 其他文档）必须优先于 allowlist
    # empty 检查——否则 task 改了 DESIGN.md/CLAUDE.md 但 allowlist 缺失时会先报
    # "allowlist 未声明"而漏报"sync 白名单 deny"，错误信息不准。
    implicit_violations: list[str] = []
    for p in paths:
        idr = implicit_deny_reason(p, task_stem)
        if idr is not None:
            implicit_violations.append(f"{p}（{idr}）")

    if implicit_violations:
        print("❌ 越界文件（命中 sync 白名单 implicit deny）：", file=sys.stderr)
        for v in implicit_violations:
            print(f"   - {v}", file=sys.stderr)
        return 1

    if not allow:
        if args.allow_empty:
            print(
                "⚠️ task 文件 执行范围 section 未声明 allowlist，按 advisory 放行",
                file=sys.stderr,
            )
            return 0
        print(
            "❌ task 文件 执行范围 section 未声明 allowlist，拒绝（使用 --allow-empty 放行）",
            file=sys.stderr,
        )
        return 1

    violations: list[str] = []
    for p in paths:
        # Explicit deny list short-circuits
        if matches_any(p, deny):
            violations.append(f"{p}（命中 denylist）")
            continue
        if not matches_any(p, allow):
            violations.append(f"{p}（未命中 allowlist）")

    if violations:
        print("❌ 越界文件：", file=sys.stderr)
        for v in violations:
            print(f"   - {v}", file=sys.stderr)
        print("", file=sys.stderr)
        print(f"allowlist: {allow}", file=sys.stderr)
        if deny:
            print(f"denylist: {deny}", file=sys.stderr)
        return 1

    print(f"✅ {len(paths)} 个变更文件全部在 allowlist 内", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
