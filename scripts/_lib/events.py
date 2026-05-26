"""Shared helpers for the task event stream (.runs/events/<stem>.jsonl).

Single source of truth for what counts as an "execution event", so the
accept gate (task-transition.py check_preconditions) and I-CT7
(audit-task-events.py audit_ct7) can never drift apart.
"""

from __future__ import annotations

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

# 执行器被真正触发过的证据。accept 闸门与 I-CT7 共用同一定义 —— 改这里两处同步。
EXEC_EVENT_TYPES = {"execution_started", "execution_manual_completed"}

# 这些事件类型不允许通过 task-events.py CLI 直接写入 —— 它们是审计证据，
# 必须经合规通路（task-transition.py 的 --bound-to-execution-event /
# --emit-from-pending / --register-manual-completion / --repair-evidence）
# 通过 append_execution_event_internal() 写入。
#
# 设计依据：accept 闸门挡下 task 时，AI 看错误消息后可能自行拼出
# `task-events.py append --type execution_started` 命令补登伪造审计证据。
# CLI 黑名单让这条绕过路径在物理层面拒绝执行（不靠文案说服 AI）。
CLI_RESTRICTED_EVENT_TYPES = {"execution_started", "execution_manual_completed"}

# task-transition.py 「待执行→执行中」transition 接受的物化绑定事件类型。
# 修复 B：transition 与 dispatch 事件原子写入一次，不允许"状态变了但无执行证据"
# 的悬空态。值映射到要写入的实际事件类型。
BOUND_DISPATCH_EVENT_MAP = {
    "started": "execution_started",          # 普通 executor (claude-code / codex / cursor-agent)
    "manual-waiting": "execution_manual_waiting",  # executor=manual 派发到 PM 手做
}


def has_execution_event(events: list[dict]) -> bool:
    """True if the event stream contains at least one execution event."""
    return any(e.get("event") in EXEC_EVENT_TYPES for e in events)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _find_main_repo_root() -> Path:
    """Resolve main repo root (not a worktree's gitdir)."""
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


def events_file_for(task_file: Path) -> Path:
    """Resolve <main-repo>/.runs/events/<stem>.jsonl for a task file."""
    return _find_main_repo_root() / ".runs" / "events" / f"{Path(task_file).stem}.jsonl"


def append_execution_event_internal(
    task_file: Path,
    event_type: str,
    *,
    payload: dict | None = None,
    note: str | None = None,
) -> None:
    """Internal API: write a (CLI-restricted) execution event, bypassing the blacklist.

    Only合规通路应当调用本函数：task-transition.py 的 --bound-to-execution-event /
    --emit-from-pending / --register-manual-completion / --repair-evidence。
    其他调用方应当走 task-events.py CLI 写非受限事件类型（如 review_completed /
    status_changed / execution_manual_waiting）。

    Args:
        task_file: task md path
        event_type: must be in CLI_RESTRICTED_EVENT_TYPES (sanity check)
        payload: extra dict fields merged into event
        note: optional note string
    """
    # 受限事件类型 = CLI 黑名单 ∪ atomic 绑定通路用的 dispatch 事件类型
    # （后者覆盖 dispatch §3b 重试场景下单独 emit 的情况）
    _internal_writable = CLI_RESTRICTED_EVENT_TYPES | set(BOUND_DISPATCH_EVENT_MAP.values())
    if event_type not in _internal_writable:
        raise ValueError(
            f"append_execution_event_internal: event_type {event_type!r} 不在 "
            f"内部可写集合（{sorted(_internal_writable)}）。"
            f"非受限事件类型请走 task-events.py CLI。"
        )

    events_file = events_file_for(task_file)
    events_file.parent.mkdir(parents=True, exist_ok=True)

    event: dict = {
        "event": event_type,
        "timestamp": _now_iso(),
        "task": Path(task_file).stem,
    }
    if payload:
        for k, v in payload.items():
            if k not in event:
                event[k] = v
    if note:
        event["note"] = note

    with events_file.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(event, ensure_ascii=False) + "\n")


def write_status_change_and_exec_event_atomic(
    task_file: Path,
    from_status: str,
    to_status: str,
    bound_event_alias: str,
    *,
    note: str | None = None,
    exec_payload: dict | None = None,
) -> None:
    """Atomic: status_changed + dispatch exec event written as one append.

    修复 B：「待执行→执行中」transition 必须原子绑定 dispatch 事件。两条事件
    用同一时戳、写在同一次 fh.write 调用里，确保不会出现"状态变了但无执行
    证据"的悬空态。

    Args:
        task_file: task md path
        from_status / to_status: 状态变化方向
        bound_event_alias: 必须是 BOUND_DISPATCH_EVENT_MAP 的 key
            ("started" | "manual-waiting")
        note: status_changed 事件的备注
        exec_payload: dispatch 事件的附加字段（executor / model / baseline_sha 等）
    """
    if bound_event_alias not in BOUND_DISPATCH_EVENT_MAP:
        raise ValueError(
            f"bound_event_alias 必须 ∈ {sorted(BOUND_DISPATCH_EVENT_MAP)}, "
            f"got {bound_event_alias!r}"
        )
    exec_event_type = BOUND_DISPATCH_EVENT_MAP[bound_event_alias]

    events_file = events_file_for(task_file)
    events_file.parent.mkdir(parents=True, exist_ok=True)
    task_stem = Path(task_file).stem
    ts = _now_iso()

    status_event: dict = {
        "event": "status_changed",
        "timestamp": ts,
        "task": task_stem,
        "from": from_status,
        "to": to_status,
    }
    if note:
        status_event["note"] = note

    exec_event: dict = {
        "event": exec_event_type,
        "timestamp": ts,
        "task": task_stem,
    }
    if exec_payload:
        for k, v in exec_payload.items():
            if k not in exec_event:
                exec_event[k] = v

    lines = [
        json.dumps(status_event, ensure_ascii=False),
        json.dumps(exec_event, ensure_ascii=False),
    ]
    with events_file.open("a", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def load_events_strict(events_file: Path) -> tuple[list[dict], list[str]]:
    """Load a .jsonl event stream for gate use.

    Returns (events, problems). `problems` is non-empty when the file is
    missing, unreadable, or contains malformed lines — callers that need a
    trustworthy answer (the accept gate) treat any problem as fail-closed.
    """
    if not events_file.exists():
        return [], [f"事件流文件不存在: {events_file}"]
    try:
        raw = events_file.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        # UnicodeDecodeError（非法 UTF-8 字节）也视为不可读 —— strict 加载器的
        # 职责是任何读取障碍都转成 problem、由调用方 fail-closed，不抛 traceback。
        return [], [f"事件流文件不可读: {exc}"]
    events: list[dict] = []
    problems: list[str] = []
    for lineno, line in enumerate(raw.splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            problems.append(f"第 {lineno} 行不是合法 JSON")
    return events, problems
