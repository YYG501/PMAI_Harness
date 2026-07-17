#!/usr/bin/env python3
"""Record build phases and time-to-preview without blocking delivery."""

from __future__ import annotations

import argparse
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path


VALID_PHASES = {
    "prepare",
    "implement",
    "fast-check",
    "preview",
    "final-typecheck",
    "production-build",
    "browser-acceptance",
    "documentation",
}
VALID_KINDS = {"minor", "interaction", "initial", "final"}
PREVIEW_TARGETS = {"minor": 300, "interaction": 600}


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def parse_time(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SystemExit(f"时间不是合法 ISO-8601：{value}") from exc
    if parsed.tzinfo is None:
        raise SystemExit(f"时间必须包含时区：{value}")
    return parsed


def duration_seconds(started_at: str, ended_at: str) -> float:
    duration = (parse_time(ended_at) - parse_time(started_at)).total_seconds()
    if duration < 0:
        raise SystemExit("结束时间不能早于开始时间。")
    return round(duration, 3)


def read_audit(path: Path) -> dict:
    if not path.exists():
        return {"schema_version": 1, "entries": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"timing audit 不是合法 JSON：{path}: {exc}") from exc
    if data.get("schema_version") != 1 or not isinstance(data.get("entries"), list):
        raise SystemExit("timing audit schema 不兼容。")
    return data


def write_audit(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def cmd_start(args: argparse.Namespace) -> int:
    path = Path(args.audit_file).expanduser()
    data = read_audit(path)
    entry = {
        "id": args.id or uuid.uuid4().hex,
        "phase": args.phase,
        "kind": args.kind,
        "status": "running",
        "started_at": args.started_at or now_iso(),
        "ended_at": None,
        "duration_seconds": None,
        "feedback_received_at": args.feedback_at,
        "preview_ready_at": None,
        "time_to_preview_seconds": None,
        "warning": None,
    }
    if any(item.get("id") == entry["id"] for item in data["entries"]):
        raise SystemExit(f"timing entry id 已存在：{entry['id']}")
    parse_time(entry["started_at"])
    if entry["feedback_received_at"]:
        parse_time(entry["feedback_received_at"])
    data["entries"].append(entry)
    write_audit(path, data)
    print(json.dumps(entry, ensure_ascii=False))
    return 0


def cmd_finish(args: argparse.Namespace) -> int:
    path = Path(args.audit_file).expanduser()
    data = read_audit(path)
    matches = [item for item in data["entries"] if item.get("id") == args.id]
    if len(matches) != 1:
        raise SystemExit(f"找不到唯一 timing entry：{args.id}")
    entry = matches[0]
    if entry.get("status") != "running":
        raise SystemExit(f"timing entry 已结束：{args.id}")
    ended_at = args.ended_at or now_iso()
    entry["status"] = args.status
    entry["ended_at"] = ended_at
    entry["duration_seconds"] = duration_seconds(str(entry["started_at"]), ended_at)
    if args.preview_ready:
        feedback_at = entry.get("feedback_received_at")
        if not feedback_at:
            raise SystemExit("记录 time-to-preview 必须在 start 时提供 --feedback-at。")
        entry["preview_ready_at"] = ended_at
        entry["time_to_preview_seconds"] = duration_seconds(str(feedback_at), ended_at)
        target = PREVIEW_TARGETS.get(str(entry.get("kind")))
        if target is not None and entry["time_to_preview_seconds"] > target:
            entry["warning"] = (
                f"time-to-preview {entry['time_to_preview_seconds']:.0f}s "
                f"超过 {target // 60} 分钟目标；仅预警，不阻断 PM 刷新查看。"
            )
    write_audit(path, data)
    print(json.dumps(entry, ensure_ascii=False))
    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    path = Path(args.audit_file).expanduser()
    data = read_audit(path)
    completed = [item for item in data["entries"] if item.get("status") != "running"]
    summary = {
        "schema_version": 1,
        "entries": len(data["entries"]),
        "running": len(data["entries"]) - len(completed),
        "phase_seconds": {},
        "previews": [],
    }
    for item in completed:
        phase = str(item.get("phase"))
        seconds = float(item.get("duration_seconds") or 0)
        summary["phase_seconds"][phase] = round(
            float(summary["phase_seconds"].get(phase, 0)) + seconds, 3
        )
        if item.get("time_to_preview_seconds") is not None:
            summary["previews"].append(
                {
                    "id": item.get("id"),
                    "kind": item.get("kind"),
                    "seconds": item.get("time_to_preview_seconds"),
                    "warning": item.get("warning"),
                }
            )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)

    start = sub.add_parser("start")
    start.add_argument("--audit-file", required=True)
    start.add_argument("--phase", required=True, choices=sorted(VALID_PHASES))
    start.add_argument("--kind", required=True, choices=sorted(VALID_KINDS))
    start.add_argument("--id")
    start.add_argument("--started-at")
    start.add_argument("--feedback-at")
    start.set_defaults(func=cmd_start)

    finish = sub.add_parser("finish")
    finish.add_argument("--audit-file", required=True)
    finish.add_argument("--id", required=True)
    finish.add_argument("--status", choices=("pass", "fail", "limited"), default="pass")
    finish.add_argument("--ended-at")
    finish.add_argument("--preview-ready", action="store_true")
    finish.set_defaults(func=cmd_finish)

    summary = sub.add_parser("summary")
    summary.add_argument("--audit-file", required=True)
    summary.set_defaults(func=cmd_summary)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
