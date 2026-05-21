"""Shared helpers for the task event stream (.runs/events/<stem>.jsonl).

Single source of truth for what counts as an "execution event", so the
accept gate (task-transition.py check_preconditions) and I-CT7
(audit-task-events.py audit_ct7) can never drift apart.
"""

from __future__ import annotations

import json
from pathlib import Path

# 执行器被真正触发过的证据。accept 闸门与 I-CT7 共用同一定义 —— 改这里两处同步。
EXEC_EVENT_TYPES = {"execution_started", "execution_manual_completed"}


def has_execution_event(events: list[dict]) -> bool:
    """True if the event stream contains at least one execution event."""
    return any(e.get("event") in EXEC_EVENT_TYPES for e in events)


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
