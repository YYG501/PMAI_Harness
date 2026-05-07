#!/usr/bin/env python3
"""Pre-commit gate: 拦截绕过 task-transition.py 的 task 状态字段直改。

逻辑：
  对每个 staged 的 `requirements/**/tasks/task-*.md`（不含 .engineering.md）：
    1. 读 HEAD 版本的「状态」字段值（首次 commit 该文件 → HEAD 不存在 → 跳过）
    2. 读 index 版本的「状态」字段值
    3. HEAD 值 == index 值 → 跳过（状态没变，可能只是改了执行日志/PM 反馈）
    4. 不一样 → 查 `.runs/events/<task-stem>.jsonl` 最后一条 status_changed
       事件的 `to` 是否等于 index 状态值。匹配则 OK；否则拒绝（说明这次状态
       字段变更没经过 task-transition.py，是非法直改）。

退出码：
  0 = 全部 OK 或无 task 文件 staged
  1 = 至少一个 task 状态字段变更未经 task-transition.py 留痕

Escape hatch: `git commit --no-verify` 自然绕过（git 内置；hook 不会被调到）。

被调用方：`.git/hooks/pre-commit`（由 init-project / install-hooks 安装）。
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

# 复用 task-transition 的解析逻辑（兼容段落 + 任务卡表格两种格式）
_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

# 直接 inline 解析，避免 import 顶层带 hyphen 的模块名问题
FIELD_RE_OLD = re.compile(r"^\*\*(.+?)：\*\*\s*(.*)$")
FIELD_RE_NEW = re.compile(r"^\|\s*\*\*(.+?)\*\*\s*\|\s*(.*?)\s*\|.*$")


def parse_status(text: str) -> str | None:
    """Return the value of the「状态」field, or None if not found in first 40 lines."""
    for idx, line in enumerate(text.splitlines()):
        if idx >= 40:
            break
        stripped = line.strip()
        m = FIELD_RE_OLD.match(stripped)
        if m and m.group(1).strip() == "状态":
            return m.group(2).strip()
        m = FIELD_RE_NEW.match(stripped)
        if m and m.group(1).strip() == "状态":
            return m.group(2).strip()
    return None


def staged_task_files() -> list[str]:
    """Return staged task PM-view files (excluding .engineering.md)."""
    try:
        out = subprocess.check_output(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
            text=True,
        )
    except subprocess.CalledProcessError:
        return []
    paths = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        # requirements/**/tasks/task-*.md 但不要 .engineering.md / discarded/
        if not re.match(r"^requirements/.+/tasks/task-[^/]+\.md$", line):
            continue
        if line.endswith(".engineering.md"):
            continue
        if "/discarded/" in line:
            continue
        paths.append(line)
    return paths


def git_show_blob(ref: str, path: str) -> str | None:
    """Return file content at <ref>:<path>, or None if missing.

    ref="" → index (uses `git show :<path>` with single colon).
    ref="HEAD" / branch / commit-sha → that ref."""
    spec = f"{ref}:{path}" if ref else f":{path}"
    try:
        return subprocess.check_output(
            ["git", "show", spec],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return None


def task_stem(path: str) -> str:
    """Strip the trailing .md to match task-events.py task_stem()."""
    return Path(path).stem


def find_repo_root() -> Path:
    """Find real repo root (handles worktrees)."""
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


def last_status_changed_event(stem: str) -> dict | None:
    """Read .runs/events/<stem>.jsonl, return the last status_changed event."""
    events_file = find_repo_root() / ".runs" / "events" / f"{stem}.jsonl"
    if not events_file.exists():
        return None
    last: dict | None = None
    try:
        with events_file.open(encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if event.get("event") == "status_changed":
                    last = event
    except OSError:
        return None
    return last


def head_exists() -> bool:
    """Check if HEAD points to a valid commit (false on first commit before any history)."""
    try:
        subprocess.check_output(
            ["git", "rev-parse", "--verify", "HEAD"],
            stderr=subprocess.DEVNULL,
        )
        return True
    except subprocess.CalledProcessError:
        return False


def main() -> int:
    paths = staged_task_files()
    if not paths:
        return 0

    has_head = head_exists()
    violations: list[tuple[str, str, str, str]] = []  # (path, head_status, index_status, evidence)

    for path in paths:
        index_text = git_show_blob("", path)
        if index_text is None:
            continue  # weird; skip
        index_status = parse_status(index_text)
        if index_status is None:
            # task-spec step 10.6 should have caught this; let it through here
            # because pre-commit isn't the right place to enforce field-format.
            continue

        head_text = git_show_blob("HEAD", path) if has_head else None
        if head_text is None:
            # newly added task file — legitimate creation, no transition needed
            continue
        head_status = parse_status(head_text)
        if head_status is None or head_status == index_status:
            # status field unchanged — only other sections edited, fine
            continue

        # status changed; need a matching event
        event = last_status_changed_event(task_stem(path))
        if event is None:
            violations.append(
                (path, head_status, index_status, "无 events 流文件 / 无 status_changed 事件")
            )
            continue
        if event.get("to") != index_status:
            violations.append(
                (
                    path,
                    head_status,
                    index_status,
                    f"events 流最后 status_changed 事件 to={event.get('to')!r} ≠ index 状态={index_status!r}",
                )
            )
            continue

    if not violations:
        return 0

    # Compose readable error and reject
    print("", file=sys.stderr)
    print("❌ 拦截非法 task 状态字段直改", file=sys.stderr)
    print("=" * 60, file=sys.stderr)
    print(
        "CLAUDE.md 规则：禁止直接编辑 task 文件的状态字段。\n"
        "状态字段必须经 task-transition.py 推进，留下 events 流痕迹。",
        file=sys.stderr,
    )
    print("", file=sys.stderr)
    print("被拦截的文件：", file=sys.stderr)
    for path, head_s, index_s, evidence in violations:
        print(f"  • {path}", file=sys.stderr)
        print(f"    状态字段：{head_s!r} → {index_s!r}", file=sys.stderr)
        print(f"    问题：{evidence}", file=sys.stderr)
    print("", file=sys.stderr)
    print("如何修复：", file=sys.stderr)
    print("  1. 撤销文件改动：", file=sys.stderr)
    print("       git restore --staged <task-file>", file=sys.stderr)
    print("       git restore <task-file>", file=sys.stderr)
    print("  2. 用 task-transition.py 走合规流程：", file=sys.stderr)
    print(
        "       python3 .claude/scripts/task-transition.py <task-file> --to <目标状态>",
        file=sys.stderr,
    )
    print("  3. 重新 commit。", file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "Escape hatch（仅救火，绕过审计）：git commit --no-verify",
        file=sys.stderr,
    )
    print("=" * 60, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
