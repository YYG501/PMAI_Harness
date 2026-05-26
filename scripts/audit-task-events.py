#!/usr/bin/env python3
"""Audit task event stream and commit timeline before close-task merge.

Enforces INVARIANTS.md I-CT7 and I-CT8:

- I-CT7: Event stream must prove the full state-machine progression:
    待执行→执行中, 执行中→已完成 status_changed events,
    plus at least one execution_started or execution_manual_completed.
    （「待验收」已合并到「执行中」 — commit 不切状态，PM 通过呈交块时直接转「已完成」）
- I-CT8: Each code commit on the task branch must have a committer timestamp
    strictly later than the earliest `status_changed(*, 执行中)` event.

Exit codes:
  0 = audit passed
  1 = audit failed (violation printed to stderr)
  2 = usage / file errors

Usage:
  audit-task-events.py --task-file <path> --task-branch <name> --req-branch <name>

The caller (close-task.sh) is expected to hard-abort merge on non-zero exit.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# 让 _lib 可 import（audit-task-events.py 在 scripts/，_lib 是同级子目录）
_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)
from _lib.events import has_execution_event
from _lib.state import detect_format


def find_main_repo_root() -> Path:
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


def parse_iso(ts: str) -> datetime | None:
    if not ts:
        return None
    try:
        # Handle trailing Z
        cleaned = ts.replace("Z", "+00:00")
        return datetime.fromisoformat(cleaned)
    except Exception:
        return None


def load_events(events_file: Path) -> list[dict]:
    if not events_file.exists():
        return []
    out: list[dict] = []
    with events_file.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def _has_transition(events: list[dict], frm: str, to: str) -> bool:
    return any(
        e.get("event") == "status_changed"
        and e.get("from") == frm
        and e.get("to") == to
        for e in events
    )


def audit_ct7(events: list[dict]) -> list[str]:
    """Return a list of violations (empty = pass)."""
    violations: list[str] = []

    # 入口转换强制：待执行→执行中
    if not _has_transition(events, "待执行", "执行中"):
        violations.append("I-CT7: 事件流缺少 status_changed(待执行→执行中)")

    # 收口转换：接受两种合法路径
    #   1) 直接式（当前规范）：执行中→已完成
    #   2) 三步式（旧规范）：执行中→待验收 + 待验收→已完成
    direct = _has_transition(events, "执行中", "已完成")
    legacy = _has_transition(events, "执行中", "待验收") and _has_transition(
        events, "待验收", "已完成"
    )
    if not (direct or legacy):
        violations.append(
            "I-CT7: 事件流缺少收口转换 status_changed(执行中→已完成) "
            "或旧规范三步式 status_changed(执行中→待验收) + status_changed(待验收→已完成)"
        )

    # At least one execution event（与 task-transition.py accept 闸门共用 _lib.events 定义）
    if not has_execution_event(events):
        violations.append(
            "I-CT7: 事件流缺少任何 execution_started / execution_manual_completed 事件"
            "（说明执行器从未被触发，task 可能被跳过状态机直接写了代码）"
        )

    return violations


def first_transition_to_executing_time(events: list[dict]) -> datetime | None:
    """Return the earliest timestamp of status_changed(*, 执行中)."""
    best: datetime | None = None
    for e in events:
        if e.get("event") != "status_changed":
            continue
        if e.get("to") != "执行中":
            continue
        ts = parse_iso(e.get("timestamp", ""))
        if ts is None:
            continue
        if best is None or ts < best:
            best = ts
    return best


def task_branch_commits(task_branch: str, req_branch: str) -> list[tuple[str, datetime, str]]:
    """Return list of (sha, committer_time_aware, subject) for commits on task branch not on req branch."""
    try:
        out = subprocess.check_output(
            [
                "git",
                "log",
                "--format=%H|%cI|%s",
                f"{req_branch}..{task_branch}",
            ],
            text=True,
        )
    except subprocess.CalledProcessError:
        return []

    commits: list[tuple[str, datetime, str]] = []
    for line in out.strip().split("\n"):
        if not line:
            continue
        parts = line.split("|", 2)
        if len(parts) < 3:
            continue
        sha, ts_raw, subject = parts
        ts = parse_iso(ts_raw)
        if ts is None:
            continue
        commits.append((sha, ts, subject))
    return commits


def commit_only_touches_task_docs(
    sha: str, task_stem: str, repo_root: Path, is_v2: bool = False
) -> bool:
    """A1 hotfix: True if commit only modifies the task's own doc file(s).

    Allows task-confirm 阶段元信息 commit (切 executor / sync from task-confirm /
    create-task-worktree 的 task md 移动等) to bypass I-CT8 timestamp check.

    ：v3 单文件 task 的 own 文件只有 task-NNN.md。
    v2 旧双文件 task 兼容保留 —— is_v2=True 时额外放行 task-NNN.engineering.md。

    Returns False on git error or empty file list (fail-closed).
    """
    try:
        out = subprocess.check_output(
            ["git", "-C", str(repo_root), "show", "--name-only", "--format=", sha],
            text=True,
        )
    except subprocess.CalledProcessError:
        return False
    files = [f.strip() for f in out.split("\n") if f.strip()]
    if not files:
        return False
    allowed_basenames = {f"{task_stem}.md"}
    if is_v2:
        allowed_basenames.add(f"{task_stem}.engineering.md")
    return all(Path(f).name in allowed_basenames for f in files)


def audit_ct8(
    events: list[dict],
    task_branch: str,
    req_branch: str,
    task_stem: str,
    repo_root: Path,
    is_v2: bool = False,
) -> list[str]:
    """Verify every task-branch commit is timestamped after the first transition to 执行中.

    A1 hotfix: commits whose only file changes are the task's own doc file(s)
    are exempted (task-confirm metadata commits are legitimate before *→执行中).
    ：is_v2 透传给 commit_only_touches_task_docs 决定是否放行 .engineering.md。
    """
    violations: list[str] = []

    earliest = first_transition_to_executing_time(events)
    commits = task_branch_commits(task_branch, req_branch)
    if not commits:
        # No commits unique to task branch — nothing to check
        return violations

    if earliest is None:
        # I-CT7 already flags this. Don't double-report; keep I-CT8 silent when baseline missing.
        return violations

    for sha, ts, subject in commits:
        if ts < earliest:
            if commit_only_touches_task_docs(sha, task_stem, repo_root, is_v2=is_v2):
                # A1 hotfix: 纯 task 文档元信息 commit 豁免（v2 含 .engineering.md）
                continue
            # A2 hotfix: chore(...) / chore: ... commit 豁免——task-confirm 时
            # PM 同步框架带进来的 commit 不是 task 代码，时间戳早于 *→执行中合理。
            if re.match(r"^chore[(:]", subject):
                continue
            violations.append(
                f"I-CT8: commit {sha[:8]} ({ts.isoformat()}) 早于首次 status_changed(*→执行中) "
                f"({earliest.isoformat()})。说明代码在状态机推进前就已写入。subject: {subject}"
            )
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit task event stream + commit timeline")
    parser.add_argument("--task-file", required=True, help="Path to task file (for events lookup)")
    parser.add_argument("--task-branch", required=True, help="Task branch name")
    parser.add_argument("--req-branch", required=True, help="Req branch name")
    args = parser.parse_args()

    task_file = Path(args.task_file).resolve()
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        return 2

    repo = find_main_repo_root()
    task_stem = task_file.stem
    events_file = repo / ".runs" / "events" / f"{task_stem}.jsonl"
    # v2 旧双文件 task 兼容：只有 v2 才豁免 .engineering.md 元信息 commit
    is_v2 = detect_format(task_file) == "v2"

    events = load_events(events_file)

    violations: list[str] = []

    # I-CT7: event file must exist (fail-closed)
    if not events_file.exists():
        violations.append(
            f"I-CT7: 事件流文件不存在: {events_file}。无法证明状态机被走过——"
            "这是 fail-closed 设计（没有事件 = 违规，不是 = 无违规）。"
        )
    else:
        violations.extend(audit_ct7(events))

    # I-CT8
    violations.extend(
        audit_ct8(
            events, args.task_branch, args.req_branch, task_stem, repo, is_v2=is_v2
        )
    )

    if violations:
        print("❌ close-task 事件流审计失败：", file=sys.stderr)
        for v in violations:
            print(f"   - {v}", file=sys.stderr)
        print("", file=sys.stderr)
        print(
            "数据已保留。处理路径（按场景选）：\n"
            "\n"
            "  1) 历史 task（accept 闸门加上之前已完成）/ 工作真实手动完成但漏跑 /task-execute：\n"
            "     合规救援路径——\n"
            "       python3 $HOME/.pmai/scripts/task-transition.py <task-file> \\\n"
            "         --repair-evidence --reason \"<原因，例：accept 闸门加上之前完成的历史 task>\"\n"
            "     （强制 reason + 加 repaired:true 永久标记 + 只补 execution_manual_completed）\n"
            "     ⚠️ 不要用 task-events.py append 裸补——没有 repaired 标记 = 事后看像伪造。\n"
            "     ⚠️ 命令报 unknown argument → 消费仓框架太老，先按 框架同步-SOP.md §4.11\n"
            "        同步到 generator bd1f1a3 之后。\n"
            "\n"
            "  2) 真实跳过状态机（PM 手写代码改 status 绕过 /task-execute）：\n"
            "     回新窗口跑 /task-execute <task-id>，让 dispatch 真实发射 execution_started。\n"
            "\n"
            "  3) 整个 req 放弃：/cancel-req（代码不 merge 进 main）。",
            file=sys.stderr,
        )
        return 1

    print("✅ 事件流审计通过（I-CT7 + I-CT8）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
