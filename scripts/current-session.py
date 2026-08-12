#!/usr/bin/env python3
"""Locate the exact raw transcript for the current PMAI host session.

The locator is deliberately fail-closed. It never guesses from modification
time or picks the "most recent" conversation because multiple PMAI sessions
may be active for the same repository.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


SESSION_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{5,127}$")
SUPPORTED_HOSTS = ("auto", "codex", "claude-code", "kimi-code", "opencode")


class LocateError(RuntimeError):
    """Expected fail-closed locator error."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="精确定位当前宿主的原始会话文件；不能唯一确定时拒绝猜测。"
    )
    parser.add_argument("--repo-root", required=True, help="当前 PMAI 消费仓根目录")
    parser.add_argument(
        "--host",
        choices=SUPPORTED_HOSTS,
        default="auto",
        help="当前主控宿主；auto 目前只在 CODEX_THREAD_ID 存在时识别 Codex",
    )
    parser.add_argument(
        "--session-id",
        help="显式会话 ID；主要用于宿主已提供确定 ID 的受控调用和测试",
    )
    parser.add_argument(
        "--codex-home",
        help="Codex 状态目录；默认 CODEX_HOME 或 ~/.codex",
    )
    return parser.parse_args()


def resolve_host(requested: str, env: dict[str, str]) -> str:
    if requested != "auto":
        return requested
    if env.get("CODEX_THREAD_ID", "").strip():
        return "codex"
    raise LocateError(
        "无法从当前环境取得确定的宿主会话 ID。"
        "禁止按最近修改时间猜测；当前仅验证 Codex 的 CODEX_THREAD_ID 精确链路。"
    )


def resolve_session_id(
    host: str, explicit_session_id: str | None, env: dict[str, str]
) -> tuple[str, str]:
    if explicit_session_id:
        session_id = explicit_session_id.strip()
        source = "--session-id"
    elif host == "codex":
        session_id = env.get("CODEX_THREAD_ID", "").strip()
        source = "CODEX_THREAD_ID"
    else:
        raise LocateError(
            f"{host} 尚未验证可精确定位当前原始会话文件。"
            "本次停止，不使用最近会话或 cwd 模糊匹配代替。"
        )

    if not session_id:
        raise LocateError(
            f"当前 {host} 环境没有确定的会话 ID。"
            "本次停止，不使用最近会话代替。"
        )
    if not SESSION_ID_RE.fullmatch(session_id):
        raise LocateError("会话 ID 格式异常，拒绝用于文件搜索。")
    return session_id, source


def read_session_meta(path: Path) -> dict[str, object]:
    try:
        with path.open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, start=1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise LocateError(
                        f"会话文件在第 {line_number} 行不是合法 JSONL：{path}: {exc}"
                    ) from exc
                if record.get("type") == "session_meta":
                    payload = record.get("payload")
                    if isinstance(payload, dict):
                        return payload
                    raise LocateError(f"session_meta.payload 不是对象：{path}")
    except OSError as exc:
        raise LocateError(f"无法读取会话文件：{path}: {exc}") from exc
    raise LocateError(f"会话文件缺少 session_meta：{path}")


def is_within_repo(session_cwd: Path, repo_root: Path) -> bool:
    return session_cwd == repo_root or repo_root in session_cwd.parents


def capture_snapshot(path: Path) -> tuple[int, int, str]:
    """Capture the immutable prefix that feedback may inspect."""
    try:
        with path.open("rb") as handle:
            captured_size = os.fstat(handle.fileno()).st_size
            remaining = captured_size
            scanned_bytes = 0
            seen_lines = 0
            line_count = 0
            byte_count = 0
            while remaining > 0:
                chunk = handle.read(min(1024 * 1024, remaining))
                if not chunk:
                    break
                remaining -= len(chunk)
                last_newline = chunk.rfind(b"\n")
                seen_lines += chunk.count(b"\n")
                if last_newline >= 0:
                    line_count = seen_lines
                    byte_count = scanned_bytes + last_newline + 1
                scanned_bytes += len(chunk)
    except OSError as exc:
        raise LocateError(f"无法固定会话快照边界：{path}: {exc}") from exc
    if line_count < 1:
        raise LocateError(f"会话文件没有完整 JSONL 记录，无法固定快照边界：{path}")
    captured_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    return line_count, byte_count, captured_at


def locate_codex_transcript(
    codex_home: Path, session_id: str, repo_root: Path
) -> tuple[Path, dict[str, object], str]:
    roots = (
        (codex_home / "sessions", "active"),
        (codex_home / "archived_sessions", "archived"),
    )
    candidates: list[tuple[Path, str]] = []
    pattern = f"*{session_id}*.jsonl"
    for root, state in roots:
        if not root.is_dir():
            continue
        candidates.extend((path.resolve(), state) for path in root.rglob(pattern) if path.is_file())

    # A copied active + archived transcript is ambiguous even when both carry
    # the same id: the caller asked for the exact current evidence file.
    unique_candidates = sorted(set(candidates), key=lambda item: str(item[0]))
    if not unique_candidates:
        raise LocateError(
            f"没有找到会话 {session_id} 的原始 JSONL。"
            f"已检查 {codex_home / 'sessions'} 和 {codex_home / 'archived_sessions'}。"
        )
    if len(unique_candidates) != 1:
        paths = "\n".join(f"- {path}" for path, _ in unique_candidates)
        raise LocateError(
            f"找到多个会话 {session_id} 候选，无法唯一确定：\n{paths}\n"
            "本次停止，不自动挑选。"
        )

    path, state = unique_candidates[0]
    meta = read_session_meta(path)
    meta_id = str(meta.get("id") or "").strip()
    if meta_id != session_id:
        raise LocateError(
            f"文件名命中但 session_meta.id 不一致：期望 {session_id}，实际 {meta_id or '<empty>'}。"
        )

    raw_cwd = str(meta.get("cwd") or "").strip()
    if not raw_cwd:
        raise LocateError(f"session_meta 缺少 cwd：{path}")
    session_cwd = Path(raw_cwd).expanduser().resolve()
    if not is_within_repo(session_cwd, repo_root):
        raise LocateError(
            "当前会话不属于指定消费仓："
            f"session cwd={session_cwd}，repo root={repo_root}。"
        )
    return path, meta, state


def main() -> int:
    args = parse_args()
    env = dict(os.environ)
    try:
        repo_root = Path(args.repo_root).expanduser().resolve()
        if not repo_root.is_dir():
            raise LocateError(f"消费仓根目录不存在：{repo_root}")

        host = resolve_host(args.host, env)
        session_id, id_source = resolve_session_id(host, args.session_id, env)
        if host != "codex":
            raise LocateError(
                f"{host} 尚未实现经过验证的原始会话定位器。"
                "本次停止，不使用最近会话代替。"
            )

        codex_home = Path(
            args.codex_home
            or env.get("CODEX_HOME", "")
            or (Path.home() / ".codex")
        ).expanduser().resolve()
        path, meta, state = locate_codex_transcript(
            codex_home=codex_home,
            session_id=session_id,
            repo_root=repo_root,
        )
        snapshot_end_line, snapshot_end_bytes, snapshot_captured_at = capture_snapshot(path)
        result = {
            "schema_version": 2,
            "status": "ok",
            "exact": True,
            "host": host,
            "session_id": session_id,
            "session_id_source": id_source,
            "transcript_path": str(path),
            "transcript_format": "codex-jsonl",
            "transcript_state": state,
            "session_cwd": str(meta.get("cwd")),
            "repo_root": str(repo_root),
            "originator": meta.get("originator"),
            "started_at": meta.get("timestamp"),
            "snapshot_end_line": snapshot_end_line,
            "snapshot_end_bytes": snapshot_end_bytes,
            "snapshot_captured_at": snapshot_captured_at,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except LocateError as exc:
        print(f"CURRENT_SESSION_ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
