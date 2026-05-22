#!/usr/bin/env python3
"""Append-only JSONL event stream for req-level content events (delta-7).

req 级「内容性事件流」—— 与 task-events.py 平行，但抬到 req 级。
- 文件落 `<req-dir>/req-events.jsonl`，**被 git 跟踪**（随 req 分支 commit / merge，
  close 后仍可查），不落 gitignored 的 `.runs/`。
- 两类事件（§0 re-scope 后只此两类，不加 §0 未点名的类型）：
    decision   —— prd-writing @ stage 3 做决策时，结果留 PRD §四、备选+理由进事件。
    adjustment —— 执行期 task 对 PRD 的偏离（close-task Phase 2 promote）。
- 与 task-events.py 一致的公共信封字段名（`event` / `timestamp`），零新格式。

req 生命周期（stage 转换）仍由 `.req-meta.json` 的 stage_history 装；本事件流只装
**内容**（决策理由 / PRD 调整）。三套时间线零重叠，见 delta-7 §2.6。
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

EVENTS_FILENAME = "req-events.jsonl"
VALID_TYPES = ("decision", "adjustment")


def now_iso() -> str:
    """ISO-8601 UTC timestamp —— 与 task-events.py now_iso() 同实现。"""
    return datetime.now(timezone.utc).isoformat()


def find_repo_root() -> Path:
    """Find the real repo root (not a worktree) —— 同 task-events.py。"""
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


def resolve_req_dir(arg: str) -> Path:
    """接受 req 目录路径，或裸 reqid（无斜杠）→ 解析到 requirements/active/<reqid>。

    传目录路径时直接用 —— 文件落 caller 所在的 worktree（req worktree），
    随 req 分支 commit；不经 find_repo_root（那会指向主仓）。
    """
    p = Path(arg)
    if p.is_dir():
        return p
    if "/" in arg or p.exists():
        return p
    # 裸 reqid —— 解析到 requirements/active/<reqid>
    return find_repo_root() / "requirements" / "active" / arg


def events_path(req_dir: Path) -> Path:
    return req_dir / EVENTS_FILENAME


def cmd_append(args: argparse.Namespace) -> None:
    req_dir = resolve_req_dir(args.req_dir)
    if not req_dir.is_dir():
        print(f"Error: req directory not found: {req_dir}", file=sys.stderr)
        sys.exit(1)

    event: dict = {
        "event": args.type,
        "timestamp": now_iso(),
        "req": req_dir.name,
    }
    if args.source:
        event["source"] = args.source

    if args.type == "decision":
        if not args.decision:
            print("Error: decision event requires --decision", file=sys.stderr)
            sys.exit(1)
        event["decision"] = args.decision
        if args.prd_anchor:
            event["prd_anchor"] = args.prd_anchor
        if args.chosen:
            event["chosen"] = args.chosen
        if args.alternatives:
            event["alternatives"] = list(args.alternatives)
        if args.rationale:
            event["rationale"] = args.rationale
    elif args.type == "adjustment":
        if not args.from_task:
            print("Error: adjustment event requires --from-task", file=sys.stderr)
            sys.exit(1)
        event["from_task"] = args.from_task
        if args.prd_anchor:
            event["prd_anchor"] = args.prd_anchor
        if args.before:
            event["before"] = args.before
        if args.after:
            event["after"] = args.after
        if args.reason:
            event["reason"] = args.reason

    # Free-form payload —— 与 task-events.py 一致，不覆盖已有字段
    if args.payload:
        try:
            payload = json.loads(args.payload)
            if isinstance(payload, dict):
                for k, v in payload.items():
                    if k not in event:
                        event[k] = v
        except json.JSONDecodeError as exc:
            print(f"Error: --payload must be valid JSON ({exc})", file=sys.stderr)
            sys.exit(1)

    ep = events_path(req_dir)
    with ep.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(event, ensure_ascii=False) + "\n")

    print(f"req event appended: {args.type}", file=sys.stderr)


def _load_events(req_dir: Path) -> list[dict]:
    ep = events_path(req_dir)
    if not ep.exists():
        return []
    events: list[dict] = []
    for line in ep.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return events


def cmd_list(args: argparse.Namespace) -> None:
    """把 jsonl 折叠成可读时间线 —— decision / adjustment 分组、各按 timestamp 排。"""
    req_dir = resolve_req_dir(args.req_dir)
    events = _load_events(req_dir)
    if not events:
        print("No req events found.")
        return

    decisions = sorted(
        (e for e in events if e.get("event") == "decision"),
        key=lambda e: e.get("timestamp", ""),
    )
    adjustments = sorted(
        (e for e in events if e.get("event") == "adjustment"),
        key=lambda e: e.get("timestamp", ""),
    )

    print(f"# req-events: {req_dir.name}")
    print(f"  decision: {len(decisions)} 条  ·  adjustment: {len(adjustments)} 条")

    if decisions:
        print("\n## 决策（decision —— 备选 / 理由）")
        for e in decisions:
            print(f"\n- [{e.get('timestamp', '?')}] {e.get('decision', '(无标题)')}")
            if e.get("prd_anchor"):
                print(f"    PRD 锚点：{e['prd_anchor']}")
            if e.get("chosen"):
                print(f"    选定：{e['chosen']}")
            if e.get("alternatives"):
                print(f"    备选：{'; '.join(e['alternatives'])}")
            if e.get("rationale"):
                print(f"    理由：{e['rationale']}")

    if adjustments:
        print("\n## 调整（adjustment —— 执行期对 PRD 的偏离）")
        for e in adjustments:
            print(
                f"\n- [{e.get('timestamp', '?')}] "
                f"{e.get('from_task', '?')} → {e.get('prd_anchor', '(未标锚点)')}"
            )
            if e.get("before"):
                print(f"    PRD 原定：{e['before']}")
            if e.get("after"):
                print(f"    实际做成：{e['after']}")
            if e.get("reason"):
                print(f"    原因：{e['reason']}")


def main() -> None:
    parser = argparse.ArgumentParser(description="req-level content event stream manager")
    sub = parser.add_subparsers(dest="command", required=True)

    p_append = sub.add_parser("append", help="Append a req event")
    p_append.add_argument("req_dir", help="req directory path (or bare reqid)")
    p_append.add_argument(
        "--type", required=True, choices=VALID_TYPES, help="Event type"
    )
    p_append.add_argument("--source", help="Producer (skill@stage, e.g. prd-writing@3)")
    # decision fields
    p_append.add_argument("--decision", help="[decision] one-line title")
    p_append.add_argument("--chosen", help="[decision] chosen option")
    p_append.add_argument(
        "--alternatives",
        action="append",
        help="[decision] an alternative (repeat for multiple)",
    )
    p_append.add_argument("--rationale", help="[decision] why this choice")
    # adjustment fields
    p_append.add_argument("--from-task", dest="from_task", help="[adjustment] task id")
    p_append.add_argument("--before", help="[adjustment] what PRD originally specified")
    p_append.add_argument("--after", help="[adjustment] what was actually built")
    p_append.add_argument("--reason", help="[adjustment] why it deviated")
    # shared
    p_append.add_argument(
        "--prd-anchor", dest="prd_anchor", help="PRD anchor (which §四 entry)"
    )
    p_append.add_argument(
        "--payload", help="Free-form JSON object merged into event"
    )

    p_list = sub.add_parser("list", help="List req events as a readable timeline")
    p_list.add_argument("req_dir", help="req directory path (or bare reqid)")

    args = parser.parse_args()
    if args.command == "append":
        cmd_append(args)
    elif args.command == "list":
        cmd_list(args)


if __name__ == "__main__":
    main()
