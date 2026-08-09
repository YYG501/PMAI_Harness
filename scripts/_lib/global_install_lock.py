#!/usr/bin/env python3
"""Run PMAI global-install mutations under one inherited OS lock."""

from __future__ import annotations

import argparse
import errno
import fcntl
import os
import stat
import sys
from pathlib import Path


LOCK_FD_ENV = "PMAI_GLOBAL_INSTALL_LOCK_FD"


class LockError(RuntimeError):
    pass


def _canonical_lock_path(raw_path: str) -> Path:
    path = Path(raw_path).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    try:
        parent = path.parent.resolve(strict=True)
    except OSError as exc:
        raise LockError(f"全局安装锁目录不可访问: {path.parent}") from exc
    return parent / path.name


def _open_lock(path: Path) -> int:
    flags = os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags, 0o600)
    except OSError as exc:
        raise LockError(f"无法安全打开全局安装锁: {path}") from exc
    try:
        opened = os.fstat(fd)
        current = os.lstat(path)
        if not stat.S_ISREG(opened.st_mode) or (
            opened.st_dev,
            opened.st_ino,
        ) != (current.st_dev, current.st_ino):
            raise LockError(f"全局安装锁不是稳定的普通文件: {path}")
    except BaseException:
        os.close(fd)
        raise
    return fd


def _verify_fd(path: Path, fd: int) -> None:
    try:
        opened = os.fstat(fd)
        current = os.lstat(path)
    except OSError as exc:
        raise LockError(f"继承的全局安装锁不可验证: {path}") from exc
    if not stat.S_ISREG(opened.st_mode) or (
        opened.st_dev,
        opened.st_ino,
    ) != (current.st_dev, current.st_ino):
        raise LockError(f"继承的全局安装锁与锁路径不一致: {path}")
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as exc:
        if exc.errno in {errno.EACCES, errno.EAGAIN}:
            raise LockError(f"继承的全局安装锁未持有排他权限: {path}") from exc
        raise LockError(f"无法验证继承的全局安装锁: {path}") from exc


def run_locked(path: Path, command: list[str]) -> int:
    if not command:
        raise LockError("全局安装锁缺少待执行命令")
    lock_fd = _open_lock(path)
    exec_fd = -1
    try:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
        except OSError as exc:
            raise LockError(f"无法获取全局安装锁: {path}") from exc
        _verify_fd(path, lock_fd)
        try:
            exec_fd = fcntl.fcntl(lock_fd, fcntl.F_DUPFD, 64)
            os.set_inheritable(exec_fd, True)
        except OSError as exc:
            raise LockError(f"无法准备继承的全局安装锁: {path}") from exc
        child_env = os.environ.copy()
        child_env[LOCK_FD_ENV] = str(exec_fd)
        try:
            os.execvpe(command[0], command, child_env)
        except OSError as exc:
            raise LockError(
                f"无法启动全局安装锁内命令: {command[0]}"
            ) from exc
    finally:
        if exec_fd >= 0:
            os.close(exec_fd)
        os.close(lock_fd)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--lock-path", required=True)
    run_parser.add_argument("command", nargs=argparse.REMAINDER)

    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--lock-path", required=True)
    verify_parser.add_argument("--lock-fd", required=True, type=int)

    args = parser.parse_args()
    try:
        path = _canonical_lock_path(args.lock_path)
        if args.action == "verify":
            _verify_fd(path, args.lock_fd)
            return 0
        command = list(args.command)
        if command[:1] == ["--"]:
            command = command[1:]
        return run_locked(path, command)
    except LockError as exc:
        print(f"global_install_lock: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
