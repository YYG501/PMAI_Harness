#!/usr/bin/env python3
"""Locked read-modify-write helpers for the pending worktree cleanup queue."""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
import stat
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path, PurePosixPath
from typing import Any


class PendingCleanupError(RuntimeError):
    pass


ACTIVATION_CONDITIONS = ("main_meta_absent", "main_meta_landed")
INTEGRATION_REFS = ("refs/heads/main", "refs/heads/master")
TRANSACTION_ID_LENGTH = 32


def _lock_path(pending_file: Path) -> Path:
    return pending_file.with_name(f"{pending_file.name}.lock")


def acquire_queue_lock(pending_file: Path) -> int:
    """Acquire the queue's process-shared exclusive lock and return its fd."""
    lock_path = _lock_path(pending_file)
    flags = os.O_RDWR | os.O_CREAT | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        lock_fd = os.open(lock_path, flags, 0o600)
    except OSError as exc:
        raise PendingCleanupError(f"待清理队列锁无法打开: {lock_path}: {exc}") from exc
    try:
        if not stat.S_ISREG(os.fstat(lock_fd).st_mode):
            raise PendingCleanupError(f"待清理队列锁不是普通文件: {lock_path}")
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        return lock_fd
    except Exception:
        os.close(lock_fd)
        raise


def read_pending_entries(
    pending_file: Path,
    *,
    allow_missing: bool = False,
) -> list[dict[str, Any]]:
    flags = os.O_RDONLY | os.O_NONBLOCK
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        file_fd = os.open(pending_file, flags)
    except FileNotFoundError:
        if allow_missing:
            return []
        raise PendingCleanupError(f"待清理队列不存在: {pending_file}") from None
    except OSError as exc:
        raise PendingCleanupError(f"待清理队列无法打开: {pending_file}: {exc}") from exc

    try:
        if not stat.S_ISREG(os.fstat(file_fd).st_mode):
            raise PendingCleanupError(f"待清理队列不是普通文件: {pending_file}")
        with os.fdopen(file_fd, encoding="utf-8") as handle:
            file_fd = -1
            entries = json.load(handle)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PendingCleanupError(f"待清理队列无法读取: {pending_file}: {exc}") from exc
    finally:
        if file_fd >= 0:
            os.close(file_fd)

    if not isinstance(entries, list) or any(not isinstance(entry, dict) for entry in entries):
        raise PendingCleanupError(f"待清理队列顶层必须是对象数组: {pending_file}")
    return entries


def replace_pending_entries(pending_file: Path, entries: list[dict[str, Any]]) -> None:
    """Persist entries atomically. Caller must hold acquire_queue_lock()."""
    directory = pending_file.parent
    if entries:
        # skill-preamble.sh reserves .pending-* for interrupted Skill markers.
        # Queue transaction stages must live in a disjoint namespace so a
        # concurrent preamble cannot consume them as recovery markers.
        fd, temp_path_raw = tempfile.mkstemp(prefix=".cleanup-queue.", dir=directory)
        temp_path = Path(temp_path_raw)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(entries, handle, indent=2, ensure_ascii=False)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp_path, pending_file)
        finally:
            try:
                temp_path.unlink()
            except FileNotFoundError:
                pass
    else:
        try:
            pending_file.unlink()
        except FileNotFoundError:
            pass

    directory_fd = os.open(directory, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def _module_meta_path(value: str) -> str:
    path = PurePosixPath(value)
    if (
        not value
        or path.is_absolute()
        or ".." in path.parts
        or len(path.parts) < 4
        or path.parts[:2] != ("docs", "modules")
        or path.name != ".work-meta.json"
    ):
        raise PendingCleanupError(f"待清理状态路径不安全: {value!r}")
    return path.as_posix()


def _replace_branch_entry(
    pending_file: Path,
    *,
    kind: str,
    branch: str,
    worktree: str,
    work_dir: str,
    phase: str,
    integration_ref: str = "",
    activation: str = "",
    module_meta: str = "",
) -> str:
    pending_file.parent.mkdir(parents=True, exist_ok=True)
    lock_fd = acquire_queue_lock(pending_file)
    try:
        entries = read_pending_entries(pending_file, allow_missing=True)
        branch_entries = [entry for entry in entries if entry.get("branch") == branch]
        if phase == "prepared" and branch_entries:
            raise PendingCleanupError(
                f"分支已有待清理事务，拒绝覆盖: {branch}"
            )
        if phase == "active" and any(
            entry.get("phase", "active") != "active"
            or "transaction_id" in entry
            for entry in branch_entries
        ):
            raise PendingCleanupError(
                f"分支已有带事务身份的待清理记录，拒绝覆盖: {branch}"
            )
        entries = [entry for entry in entries if entry.get("branch") != branch]
        now = dt.datetime.now().astimezone().isoformat(timespec="seconds")
        entry = {
            "kind": kind,
            "branch": branch,
            "branch_oid": _branch_oid_for_queue(pending_file, branch),
            "integration_ref": _integration_ref_for_queue(
                pending_file, integration_ref
            ),
            "worktree": worktree,
            "work_dir": work_dir,
            "phase": phase,
            "queued_at": now,
        }
        if phase == "prepared":
            transaction_ids = {
                entry.get("transaction_id")
                for entry in entries
                if isinstance(entry.get("transaction_id"), str)
            }
            transaction_id = uuid.uuid4().hex
            while transaction_id in transaction_ids:
                transaction_id = uuid.uuid4().hex
            entry.update(
                {
                    "activation": activation,
                    "module_meta": _module_meta_path(module_meta),
                    "prepared_at": now,
                    "transaction_id": transaction_id,
                }
            )
        else:
            transaction_id = ""
        entries.append(entry)
        replace_pending_entries(pending_file, entries)
        return transaction_id
    finally:
        os.close(lock_fd)


def _branch_oid_for_queue(pending_file: Path, branch: str) -> str:
    """Capture the queued branch identity without making branch absence fatal."""
    repo_root = pending_file.parent.parent
    ref = f"refs/heads/{branch}"
    try:
        exists = subprocess.run(
            [
                "git",
                "-C",
                str(repo_root),
                "show-ref",
                "--verify",
                "--quiet",
                ref,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if exists.returncode == 1:
            return ""
        if exists.returncode != 0:
            raise PendingCleanupError(
                f"无法读取待清理分支身份: {branch}: "
                f"{exists.stderr.strip() or f'exit {exists.returncode}'}"
            )
        result = subprocess.run(
            [
                "git",
                "-C",
                str(repo_root),
                "show-ref",
                "--hash",
                "--verify",
                ref,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        raise PendingCleanupError(f"无法读取待清理分支身份: {branch}: {exc}") from exc
    if result.returncode != 0:
        raise PendingCleanupError(
            f"无法读取待清理分支身份: {branch}: "
            f"{result.stderr.strip() or f'exit {result.returncode}'}"
        )
    return result.stdout.strip()


def _integration_ref_for_queue(pending_file: Path, requested_ref: str) -> str:
    """Capture the integration branch used by this cleanup transaction."""
    repo_root = pending_file.parent.parent

    def run_git(*args: str) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                ["git", "-C", str(repo_root), *args],
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as exc:
            raise PendingCleanupError(
                f"无法读取待清理主线引用: {requested_ref or '<auto>'}: {exc}"
            ) from exc

    candidate = requested_ref
    if candidate and candidate not in INTEGRATION_REFS:
        raise PendingCleanupError(f"待清理主线引用不安全: {candidate!r}")

    if not candidate:
        head = run_git("symbolic-ref", "--quiet", "HEAD")
        if head.returncode == 0 and head.stdout.strip() in INTEGRATION_REFS:
            candidate = head.stdout.strip()
        elif head.returncode not in (0, 1):
            raise PendingCleanupError(
                "无法读取主仓当前分支: "
                f"{head.stderr.strip() or f'exit {head.returncode}'}"
            )

    candidates = (candidate,) if candidate else INTEGRATION_REFS
    for ref in candidates:
        exists = run_git("show-ref", "--verify", "--quiet", ref)
        if exists.returncode == 0:
            return ref
        if exists.returncode != 1:
            raise PendingCleanupError(
                f"无法读取待清理主线引用: {ref}: "
                f"{exists.stderr.strip() or f'exit {exists.returncode}'}"
            )

    if candidate:
        raise PendingCleanupError(f"待清理主线引用不存在: {candidate}")
    raise PendingCleanupError("主仓缺少 main/master，无法记录待清理主线引用")


def enqueue_pending_cleanup(
    pending_file: Path,
    *,
    kind: str,
    branch: str,
    worktree: str,
    work_dir: str,
    integration_ref: str = "",
) -> None:
    _replace_branch_entry(
        pending_file,
        kind=kind,
        branch=branch,
        worktree=worktree,
        work_dir=work_dir,
        phase="active",
        integration_ref=integration_ref,
    )


def prepare_pending_cleanup(
    pending_file: Path,
    *,
    kind: str,
    branch: str,
    worktree: str,
    work_dir: str,
    activation: str,
    module_meta: str,
    integration_ref: str = "",
) -> str:
    if activation not in ACTIVATION_CONDITIONS:
        raise PendingCleanupError(f"不支持的待清理激活条件: {activation!r}")
    return _replace_branch_entry(
        pending_file,
        kind=kind,
        branch=branch,
        worktree=worktree,
        work_dir=work_dir,
        phase="prepared",
        integration_ref=integration_ref,
        activation=activation,
        module_meta=module_meta,
    )


def _validate_transaction_id(transaction_id: str) -> str:
    if (
        not isinstance(transaction_id, str)
        or len(transaction_id) != TRANSACTION_ID_LENGTH
        or any(char not in "0123456789abcdef" for char in transaction_id)
    ):
        raise PendingCleanupError(f"待清理事务身份不合法: {transaction_id!r}")
    return transaction_id


def _branch_transaction_entry(
    entries: list[dict[str, Any]],
    *,
    branch: str,
    transaction_id: str,
) -> dict[str, Any]:
    matches = [entry for entry in entries if entry.get("branch") == branch]
    if not matches:
        raise PendingCleanupError(f"找不到待清理事务: {branch}")
    if len(matches) != 1:
        raise PendingCleanupError(f"分支存在多条待清理记录，拒绝猜测事务: {branch}")
    entry = matches[0]
    recorded_id = entry.get("transaction_id", "")
    if recorded_id != transaction_id:
        raise PendingCleanupError(
            "待清理事务身份不匹配，拒绝修改: "
            f"branch={branch!r}, transaction_id={transaction_id!r}"
        )
    return entry


def activate_pending_cleanup(
    pending_file: Path,
    *,
    branch: str,
    transaction_id: str,
) -> None:
    transaction_id = _validate_transaction_id(transaction_id)
    lock_fd = acquire_queue_lock(pending_file)
    try:
        entries = read_pending_entries(pending_file, allow_missing=True)
        entry = _branch_transaction_entry(
            entries, branch=branch, transaction_id=transaction_id
        )
        phase = entry.get("phase", "active")
        if phase == "active":
            return
        if phase != "prepared":
            raise PendingCleanupError(
                f"待清理项阶段不合法: branch={branch!r}, phase={phase!r}"
            )
        entry["phase"] = "active"
        entry["activated_at"] = dt.datetime.now().astimezone().isoformat(
            timespec="seconds"
        )
        replace_pending_entries(pending_file, entries)
    finally:
        os.close(lock_fd)


def remove_pending_cleanup(
    pending_file: Path,
    *,
    branch: str,
    transaction_id: str,
) -> None:
    transaction_id = _validate_transaction_id(transaction_id)
    lock_fd = acquire_queue_lock(pending_file)
    try:
        entries = read_pending_entries(pending_file, allow_missing=True)
        entry = _branch_transaction_entry(
            entries, branch=branch, transaction_id=transaction_id
        )
        phase = entry.get("phase", "active")
        if phase != "prepared":
            raise PendingCleanupError(
                "只允许撤销尚未激活的清理事务: "
                f"branch={branch!r}, phase={phase!r}"
            )
        replace_pending_entries(
            pending_file, [candidate for candidate in entries if candidate is not entry]
        )
    finally:
        os.close(lock_fd)


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    enqueue = subparsers.add_parser("enqueue")
    enqueue.add_argument("--file", required=True, type=Path)
    enqueue.add_argument("--kind", required=True, choices=("work", "branch"))
    enqueue.add_argument("--branch", required=True)
    enqueue.add_argument("--worktree", required=True)
    enqueue.add_argument("--work-dir", required=True)
    enqueue.add_argument("--integration-ref", choices=INTEGRATION_REFS, default="")
    prepare = subparsers.add_parser("prepare")
    prepare.add_argument("--file", required=True, type=Path)
    prepare.add_argument("--kind", required=True, choices=("work", "branch"))
    prepare.add_argument("--branch", required=True)
    prepare.add_argument("--worktree", required=True)
    prepare.add_argument("--work-dir", required=True)
    prepare.add_argument("--activation", required=True, choices=ACTIVATION_CONDITIONS)
    prepare.add_argument("--module-meta", required=True)
    prepare.add_argument("--integration-ref", choices=INTEGRATION_REFS, default="")
    activate = subparsers.add_parser("activate")
    activate.add_argument("--file", required=True, type=Path)
    activate.add_argument("--branch", required=True)
    activate.add_argument("--transaction-id", required=True)
    remove = subparsers.add_parser("remove")
    remove.add_argument("--file", required=True, type=Path)
    remove.add_argument("--branch", required=True)
    remove.add_argument("--transaction-id", required=True)
    args = parser.parse_args()

    try:
        if args.command == "enqueue":
            enqueue_pending_cleanup(
                args.file,
                kind=args.kind,
                branch=args.branch,
                worktree=args.worktree,
                work_dir=args.work_dir,
                integration_ref=args.integration_ref,
            )
        elif args.command == "prepare":
            transaction_id = prepare_pending_cleanup(
                args.file,
                kind=args.kind,
                branch=args.branch,
                worktree=args.worktree,
                work_dir=args.work_dir,
                activation=args.activation,
                module_meta=args.module_meta,
                integration_ref=args.integration_ref,
            )
            print(transaction_id)
        elif args.command == "activate":
            activate_pending_cleanup(
                args.file,
                branch=args.branch,
                transaction_id=args.transaction_id,
            )
        else:
            remove_pending_cleanup(
                args.file,
                branch=args.branch,
                transaction_id=args.transaction_id,
            )
    except PendingCleanupError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
