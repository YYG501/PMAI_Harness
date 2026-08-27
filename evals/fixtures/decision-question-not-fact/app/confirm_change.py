"""Persistent single-change confirmation service.

The module deliberately keeps the product boundary small: one product manager
can inspect a change, confirm it, or leave it pending. JSON storage makes the
state survive a process restart without introducing a service dependency.
"""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Mapping


PENDING = "待处理"
CONFIRMED = "已确认"
_VALID_STATUSES = {PENDING, CONFIRMED}


class ChangeNotFoundError(LookupError):
    """Raised when a requested change is not present in the store."""


@dataclass(frozen=True)
class Change:
    """A change record returned by the service."""

    change_id: str
    title: str
    summary: str
    status: str = PENDING
    confirmed_at: str | None = None

    def __post_init__(self) -> None:
        if not self.change_id.strip():
            raise ValueError("change_id 不能为空")
        if not self.title.strip():
            raise ValueError("title 不能为空")
        if not self.summary.strip():
            raise ValueError("summary 不能为空")
        if self.status not in _VALID_STATUSES:
            raise ValueError(f"status 必须是 {PENDING} 或 {CONFIRMED}")
        if self.status == PENDING and self.confirmed_at is not None:
            raise ValueError("待处理变更不能带确认时间")
        if self.status == CONFIRMED and not self.confirmed_at:
            raise ValueError("已确认变更必须带确认时间")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class ChangeStore:
    """Read and update changes in a small atomic JSON file."""

    def __init__(self, path: str | os.PathLike[str], clock: Callable[[], str] = _utc_now):
        self.path = Path(path)
        self._clock = clock

    def _read(self) -> dict[str, dict[str, object]]:
        if not self.path.exists():
            return {}
        try:
            payload = json.loads(self.path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"变更存储文件不是合法 JSON: {self.path}") from exc
        if not isinstance(payload, dict):
            raise ValueError("变更存储文件必须是对象")
        return payload

    def _write(self, records: Mapping[str, Mapping[str, object]]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=f".{self.path.name}.", dir=self.path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(records, handle, ensure_ascii=False, indent=2, sort_keys=True)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.path)
        except BaseException:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass
            raise

    @staticmethod
    def _parse(change_id: str, raw: Mapping[str, object]) -> Change:
        try:
            return Change(
                change_id=change_id,
                title=str(raw["title"]),
                summary=str(raw["summary"]),
                status=str(raw.get("status", PENDING)),
                confirmed_at=raw.get("confirmed_at") if raw.get("confirmed_at") else None,
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(f"变更记录无效: {change_id}") from exc

    def create(self, change_id: str, title: str, summary: str) -> Change:
        """Create a new pending change, rejecting accidental replacement."""
        records = self._read()
        if change_id in records:
            raise ValueError(f"变更已存在: {change_id}")
        change = Change(change_id=change_id, title=title, summary=summary)
        records[change_id] = asdict(change)
        self._write(records)
        return change

    def get(self, change_id: str) -> Change:
        """Return one change or a clear domain error."""
        records = self._read()
        raw = records.get(change_id)
        if raw is None:
            raise ChangeNotFoundError(f"找不到变更: {change_id}")
        if not isinstance(raw, Mapping):
            raise ValueError(f"变更记录无效: {change_id}")
        return self._parse(change_id, raw)

    def confirm(self, change_id: str) -> Change:
        """Confirm a pending change exactly once."""
        records = self._read()
        current = self.get(change_id)
        if current.status == CONFIRMED:
            return current
        updated = Change(
            change_id=current.change_id,
            title=current.title,
            summary=current.summary,
            status=CONFIRMED,
            confirmed_at=self._clock(),
        )
        records[change_id] = asdict(updated)
        self._write(records)
        return updated

    def keep_pending(self, change_id: str) -> Change:
        """Keep a pending change unchanged; confirmed changes stay confirmed."""
        current = self.get(change_id)
        return current


def _command_line() -> int:
    parser = argparse.ArgumentParser(description="查看和确认单条发布前变更")
    parser.add_argument("--store", required=True, help="JSON 变更存储文件")
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create", help="创建待处理变更")
    create.add_argument("change_id")
    create.add_argument("title")
    create.add_argument("summary")

    for command in ("view", "confirm", "keep-pending"):
        action = subparsers.add_parser(command)
        action.add_argument("change_id")

    args = parser.parse_args()
    store = ChangeStore(args.store)
    try:
        if args.command == "create":
            result = store.create(args.change_id, args.title, args.summary)
        elif args.command == "view":
            result = store.get(args.change_id)
        elif args.command == "confirm":
            result = store.confirm(args.change_id)
        else:
            result = store.keep_pending(args.change_id)
    except (ChangeNotFoundError, ValueError) as exc:
        parser.error(str(exc))
    print(json.dumps(asdict(result), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(_command_line())
