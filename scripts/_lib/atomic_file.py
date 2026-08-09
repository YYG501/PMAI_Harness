#!/usr/bin/env python3
"""Cross-platform path-namespace CAS helpers for repository files.

The implementation never falls back to check-then-rename. Linux uses
renameat2(RENAME_NOREPLACE); macOS uses renameatx_np(RENAME_EXCL). The CAS
linearization covers pathname create, unlink, rename, and writes completed
before claim. POSIX writes through an already-open fd after claim target the
retired inode and require a shared writer lock or version retention if callers
also need to preserve them.
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import fcntl
import os
import secrets
import signal
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


class AtomicFileError(RuntimeError):
    def __init__(
        self,
        kind: str,
        message: str,
        *,
        recovery_paths: tuple[Path, ...] = (),
    ) -> None:
        super().__init__(message)
        self.kind = kind
        self.recovery_paths = recovery_paths

    def __str__(self) -> str:
        message = super().__str__()
        if not self.recovery_paths:
            return message
        paths = tuple(dict.fromkeys(str(path) for path in self.recovery_paths))
        return f"{message}；需核对路径: {'、'.join(paths)}"


@dataclass(frozen=True)
class _Snapshot:
    data: bytes
    mode: int
    device: int
    inode: int


@dataclass(frozen=True)
class EntryIdentity:
    device: int
    inode: int


@dataclass(frozen=True)
class PreparedUpdate:
    original_identity: EntryIdentity | None
    backup_name: str | None
    backup_identity: EntryIdentity | None
    stage_name: str
    stage_identity: EntryIdentity


PROJECT_HOOKS_LOCK_FD_ENV = "PMAI_PROJECT_HOOKS_LOCK_FD"


def _open_directory_without_symlinks(path: Path) -> int:
    if not path.is_absolute() or not hasattr(os, "O_NOFOLLOW"):
        raise AtomicFileError(
            "validation",
            f"安全写入需要绝对路径和 O_NOFOLLOW 支持: {path}",
        )
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    current_fd = -1
    try:
        current_fd = os.open(path.anchor, flags)
        for part in path.parts[1:]:
            next_fd = os.open(part, flags | os.O_NOFOLLOW, dir_fd=current_fd)
            os.close(current_fd)
            current_fd = next_fd
        return current_fd
    except OSError as exc:
        if current_fd >= 0:
            os.close(current_fd)
        raise AtomicFileError(
            "validation",
            f"安全写入拒绝 symlink 或不可访问的目录组件: {path}",
        ) from exc


def _normalise_absolute_lexical_path(path: Path) -> Path:
    if not path.is_absolute():
        path = Path.cwd() / path
    return Path(os.path.normpath(str(path)))


def ensure_directory_beneath(root: Path, directory: Path) -> None:
    """Create a directory beneath root without following any path symlink."""
    root = _normalise_absolute_lexical_path(root)
    directory = _normalise_absolute_lexical_path(directory)
    try:
        relative = directory.relative_to(root)
    except ValueError as exc:
        raise AtomicFileError(
            "validation",
            f"安全目录必须位于仓库内: {directory}",
        ) from exc

    current_fd = _open_directory_without_symlinks(root)
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | os.O_NOFOLLOW
    try:
        for part in relative.parts:
            try:
                next_fd = os.open(part, flags, dir_fd=current_fd)
            except FileNotFoundError:
                try:
                    os.mkdir(part, 0o755, dir_fd=current_fd)
                except FileExistsError:
                    pass
                except OSError as exc:
                    raise AtomicFileError(
                        "validation",
                        f"无法安全创建 Host 配置目录: {directory}",
                    ) from exc
                _fsync_directory(
                    current_fd,
                    message=f"Host 配置目录已创建但父目录持久化失败: {directory}",
                    recovery_paths=(directory,),
                )
                try:
                    next_fd = os.open(part, flags, dir_fd=current_fd)
                except OSError as exc:
                    raise AtomicFileError(
                        "validation",
                        f"新建 Host 配置目录无法安全打开: {directory}",
                    ) from exc
            except OSError as exc:
                raise AtomicFileError(
                    "validation",
                    f"Host 配置目录包含 symlink 或不可访问组件: {directory}",
                ) from exc
            os.close(current_fd)
            current_fd = next_fd
    finally:
        os.close(current_fd)


def bind_directory_fd(directory: Path, inherited_fd: int) -> tuple[int, int]:
    """Bind an inherited fd to the no-symlink pathname visible at this instant."""
    expected_fd = _open_directory_without_symlinks(
        _normalise_absolute_lexical_path(directory)
    )
    try:
        expected = os.fstat(expected_fd)
        inherited = os.fstat(inherited_fd)
    except OSError as exc:
        raise AtomicFileError(
            "validation",
            f"无法校验 Host 配置目录 fd: {directory}",
        ) from exc
    finally:
        os.close(expected_fd)
    if not stat.S_ISDIR(inherited.st_mode) or (
        inherited.st_dev,
        inherited.st_ino,
    ) != (expected.st_dev, expected.st_ino):
        raise AtomicFileError(
            "concurrent_update",
            f"Host 配置目录在绑定期间被改向，拒绝读取或写入: {directory}",
        )
    return inherited.st_dev, inherited.st_ino


def _bound_directory_fd(
    inherited_fd: int,
    *,
    expected_device: int,
    expected_inode: int,
    parent: Path,
) -> int:
    try:
        current = os.fstat(inherited_fd)
    except OSError as exc:
        raise AtomicFileError(
            "validation",
            f"Host 配置目录 fd 已失效: {parent}",
        ) from exc
    if not stat.S_ISDIR(current.st_mode) or (
        current.st_dev,
        current.st_ino,
    ) != (expected_device, expected_inode):
        raise AtomicFileError(
            "concurrent_update",
            f"Host 配置目录 fd 身份不一致，拒绝读取或写入: {parent}",
        )
    return inherited_fd


def _open_current_bound_directory(
    parent: Path,
    *,
    expected_device: int,
    expected_inode: int,
    label: str = "Host 配置目录",
) -> int:
    current_fd = _open_directory_without_symlinks(
        _normalise_absolute_lexical_path(parent)
    )
    try:
        current = os.fstat(current_fd)
    except OSError as exc:
        os.close(current_fd)
        raise AtomicFileError(
            "validation",
            f"无法校验当前{label}: {parent}",
        ) from exc
    if not stat.S_ISDIR(current.st_mode) or (
        current.st_dev,
        current.st_ino,
    ) != (expected_device, expected_inode):
        os.close(current_fd)
        raise AtomicFileError(
            "concurrent_update",
            f"{label}在绑定期间被改向，拒绝读取或写入: {parent}",
        )
    return current_fd


def _entry_identity(device: int, inode: int) -> EntryIdentity:
    if device < 0 or inode < 0:
        raise AtomicFileError("validation", "文件身份 device/inode 不能为负数")
    return EntryIdentity(device=device, inode=inode)


def _optional_entry_identity(
    device: int | None,
    inode: int | None,
    *,
    label: str,
) -> EntryIdentity | None:
    if (device is None) != (inode is None):
        raise AtomicFileError(
            "validation",
            f"{label} device 与 inode 必须同时提供或同时省略",
        )
    if device is None or inode is None:
        return None
    return _entry_identity(device, inode)


def _identity_from_stat(entry_stat: os.stat_result) -> EntryIdentity:
    return EntryIdentity(device=entry_stat.st_dev, inode=entry_stat.st_ino)


def _identity_from_snapshot(snapshot: _Snapshot) -> EntryIdentity:
    return EntryIdentity(device=snapshot.device, inode=snapshot.inode)


def _assert_directory_is_current(
    directory_fd: int,
    parent: Path,
    *,
    label: str = "Host 配置目录",
) -> None:
    try:
        bound = os.fstat(directory_fd)
    except OSError as exc:
        raise AtomicFileError(
            "validation",
            f"{label} fd 已失效: {parent}",
        ) from exc
    verification_fd = _open_current_bound_directory(
        parent,
        expected_device=bound.st_dev,
        expected_inode=bound.st_ino,
        label=label,
    )
    os.close(verification_fd)


def _assert_identity(
    snapshot: _Snapshot,
    expected: EntryIdentity,
    *,
    path: Path,
    label: str,
) -> None:
    if _identity_from_snapshot(snapshot) != expected:
        raise AtomicFileError(
            "concurrent_update",
            f"{label}身份已变化，拒绝继续: {path}",
            recovery_paths=(path,),
        )


def _assert_lock_path_identity(
    directory_fd: int,
    name: str,
    expected: EntryIdentity,
    *,
    path: Path,
) -> None:
    try:
        current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    except OSError as exc:
        raise AtomicFileError(
            "concurrent_update",
            f"协作锁路径在持锁期间不可访问: {path}",
        ) from exc
    if not stat.S_ISREG(current.st_mode) or _identity_from_stat(current) != expected:
        raise AtomicFileError(
            "concurrent_update",
            f"协作锁路径在持锁期间被替换: {path}",
        )


def run_locked(lock_path: Path, command: list[str]) -> int:
    """Run one cooperative writer while holding a stable Git-directory lock."""
    if not command:
        raise AtomicFileError("validation", "run-locked 缺少待执行命令")

    lock_path = _normalise_absolute_lexical_path(lock_path)
    lock_name = _validate_entry_name(lock_path.name, label="协作锁文件名")
    directory_fd = _open_directory_without_symlinks(lock_path.parent)
    lock_fd = -1
    child_lock_fd = -1
    process: subprocess.Popen[bytes] | None = None
    previous_handlers: dict[int, object] = {}
    forward_signals = tuple(
        signal_number
        for signal_number in (
            getattr(signal, "SIGHUP", None),
            getattr(signal, "SIGINT", None),
            getattr(signal, "SIGQUIT", None),
            getattr(signal, "SIGTERM", None),
        )
        if signal_number is not None
    )
    try:
        _assert_directory_is_current(
            directory_fd,
            lock_path.parent,
            label="Git 协作锁目录",
        )
        try:
            lock_fd = os.open(
                lock_name,
                os.O_RDWR
                | os.O_CREAT
                | os.O_NOFOLLOW
                | os.O_NONBLOCK
                | getattr(os, "O_CLOEXEC", 0),
                0o600,
                dir_fd=directory_fd,
            )
            lock_stat = os.fstat(lock_fd)
        except OSError as exc:
            raise AtomicFileError(
                "validation",
                f"无法安全打开协作锁文件: {lock_path}",
            ) from exc
        if not stat.S_ISREG(lock_stat.st_mode):
            raise AtomicFileError(
                "validation",
                f"协作锁路径不是普通文件: {lock_path}",
            )
        lock_identity = _identity_from_stat(lock_stat)
        _assert_lock_path_identity(
            directory_fd,
            lock_name,
            lock_identity,
            path=lock_path,
        )
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
        except OSError as exc:
            raise AtomicFileError(
                "validation",
                f"无法获取 Host 配置协作锁: {lock_path}",
            ) from exc
        _assert_directory_is_current(
            directory_fd,
            lock_path.parent,
            label="Git 协作锁目录",
        )
        _assert_lock_path_identity(
            directory_fd,
            lock_name,
            lock_identity,
            path=lock_path,
        )

        try:
            duplicate_operation = getattr(
                fcntl,
                "F_DUPFD_CLOEXEC",
                fcntl.F_DUPFD,
            )
            child_lock_fd = fcntl.fcntl(lock_fd, duplicate_operation, 64)
            os.set_inheritable(child_lock_fd, False)
            child_env = os.environ.copy()
            child_env[PROJECT_HOOKS_LOCK_FD_ENV] = str(child_lock_fd)
            child_env.pop("PMAI_PROJECT_HOOKS_LOCK_HELD", None)
            process = subprocess.Popen(
                command,
                close_fds=True,
                pass_fds=(child_lock_fd,),
                env=child_env,
            )
        except OSError as exc:
            raise AtomicFileError(
                "validation",
                f"无法启动协作锁内命令: {command[0]}",
            ) from exc
        finally:
            if child_lock_fd >= 0:
                os.close(child_lock_fd)
                child_lock_fd = -1

        def forward_signal(signal_number: int, _frame: object) -> None:
            assert process is not None
            if process.poll() is None:
                try:
                    process.send_signal(signal_number)
                except ProcessLookupError:
                    pass

        try:
            for signal_number in forward_signals:
                previous_handlers[signal_number] = signal.getsignal(signal_number)
                signal.signal(signal_number, forward_signal)
            return_code = process.wait()
        finally:
            for signal_number, previous_handler in previous_handlers.items():
                signal.signal(signal_number, previous_handler)

        _assert_directory_is_current(
            directory_fd,
            lock_path.parent,
            label="Git 协作锁目录",
        )
        _assert_lock_path_identity(
            directory_fd,
            lock_name,
            lock_identity,
            path=lock_path,
        )
        return return_code
    finally:
        if process is not None and process.poll() is None:
            process.wait()
        if child_lock_fd >= 0:
            os.close(child_lock_fd)
        if lock_fd >= 0:
            os.close(lock_fd)
        os.close(directory_fd)


def verify_inherited_lock(lock_path: Path, inherited_fd: int) -> None:
    """Bind an inherited fd to the lock path and ensure it owns exclusivity."""
    if inherited_fd < 0:
        raise AtomicFileError("validation", "继承的协作锁 fd 不能为负数")

    lock_path = _normalise_absolute_lexical_path(lock_path)
    lock_name = _validate_entry_name(lock_path.name, label="协作锁文件名")
    directory_fd = _open_directory_without_symlinks(lock_path.parent)
    try:
        _assert_directory_is_current(
            directory_fd,
            lock_path.parent,
            label="Git 协作锁目录",
        )
        try:
            inherited_stat = os.fstat(inherited_fd)
        except OSError as exc:
            raise AtomicFileError("validation", "继承的 Host 配置协作锁 fd 已失效") from exc
        if not stat.S_ISREG(inherited_stat.st_mode):
            raise AtomicFileError("validation", "继承的 Host 配置协作锁 fd 不是普通文件")
        inherited_identity = _identity_from_stat(inherited_stat)
        try:
            lock_path_stat = os.stat(
                lock_name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
        except OSError as exc:
            raise AtomicFileError(
                "validation",
                f"无法校验继承的 Host 配置协作锁路径: {lock_path}",
            ) from exc
        if not stat.S_ISREG(lock_path_stat.st_mode) or (
            _identity_from_stat(lock_path_stat) != inherited_identity
        ):
            raise AtomicFileError(
                "validation",
                f"继承的 Host 配置协作锁 fd 与协作锁路径不一致: {lock_path}",
            )
        try:
            # On a duplicate of run_locked's open-file description this is
            # idempotent. On a caller-supplied but unlocked fd it acquires the
            # same exclusive lock before any mutation; if another writer owns
            # it, verification fails closed instead of bypassing serialization.
            fcntl.flock(inherited_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            if exc.errno in {errno.EACCES, errno.EAGAIN}:
                raise AtomicFileError(
                    "concurrent_update",
                    f"继承的 Host 配置协作锁未持有排他权限: {lock_path}",
                ) from exc
            raise AtomicFileError(
                "validation",
                f"无法验证继承的 Host 配置协作锁: {lock_path}",
            ) from exc
        _assert_directory_is_current(
            directory_fd,
            lock_path.parent,
            label="Git 协作锁目录",
        )
        _assert_lock_path_identity(
            directory_fd,
            lock_name,
            inherited_identity,
            path=lock_path,
        )
    finally:
        os.close(directory_fd)


def cooperative_lock_status(lock_path: Path) -> str:
    """Inspect an existing cooperative lock without creating or writing it."""
    lock_path = _normalise_absolute_lexical_path(lock_path)
    lock_name = _validate_entry_name(lock_path.name, label="协作锁文件名")
    directory_fd = _open_directory_without_symlinks(lock_path.parent)
    lock_fd = -1
    try:
        _assert_directory_is_current(
            directory_fd,
            lock_path.parent,
            label="Git 协作锁目录",
        )
        try:
            lock_fd = os.open(
                lock_name,
                os.O_RDONLY
                | os.O_NOFOLLOW
                | os.O_NONBLOCK
                | getattr(os, "O_CLOEXEC", 0),
                dir_fd=directory_fd,
            )
        except FileNotFoundError:
            _assert_directory_is_current(
                directory_fd,
                lock_path.parent,
                label="Git 协作锁目录",
            )
            return "idle"
        except OSError as exc:
            raise AtomicFileError(
                "validation",
                f"无法只读检查 Host 配置协作锁: {lock_path}",
            ) from exc
        lock_stat = os.fstat(lock_fd)
        if not stat.S_ISREG(lock_stat.st_mode):
            raise AtomicFileError(
                "validation",
                f"协作锁路径不是普通文件: {lock_path}",
            )
        lock_identity = _identity_from_stat(lock_stat)
        _assert_lock_path_identity(
            directory_fd,
            lock_name,
            lock_identity,
            path=lock_path,
        )
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except OSError as exc:
            if exc.errno in {errno.EACCES, errno.EAGAIN}:
                return "busy"
            raise AtomicFileError(
                "validation",
                f"无法只读检查 Host 配置协作锁: {lock_path}",
            ) from exc
        _assert_directory_is_current(
            directory_fd,
            lock_path.parent,
            label="Git 协作锁目录",
        )
        _assert_lock_path_identity(
            directory_fd,
            lock_name,
            lock_identity,
            path=lock_path,
        )
        return "idle"
    finally:
        if lock_fd >= 0:
            os.close(lock_fd)
        os.close(directory_fd)


def _return_or_reraise_child_signal(return_code: int) -> int:
    if return_code >= 0:
        return return_code
    signal_number = -return_code
    signal.signal(signal_number, signal.SIG_DFL)
    os.kill(os.getpid(), signal_number)
    return 128 + signal_number


def _validate_entry_name(name: str, *, label: str) -> str:
    if not name or name in {".", ".."} or Path(name).name != name:
        raise AtomicFileError("validation", f"{label} 必须是单个文件名: {name!r}")
    return name


def _snapshot_at(
    directory_fd: int,
    name: str,
    *,
    display_path: Path,
    missing_kind: str = "validation",
    fsync_file: bool = False,
) -> _Snapshot:
    file_fd = -1
    try:
        file_fd = os.open(
            name,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=directory_fd,
        )
        file_stat = os.fstat(file_fd)
        if not stat.S_ISREG(file_stat.st_mode):
            raise AtomicFileError(
                "validation",
                f"原子写入目标不是普通文件: {display_path}",
            )
        chunks: list[bytes] = []
        while True:
            chunk = os.read(file_fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        if fsync_file:
            try:
                os.fsync(file_fd)
            except OSError as exc:
                raise AtomicFileError(
                    "validation",
                    f"暂存文件持久化失败，正式文件未修改: {display_path}",
                ) from exc
        return _Snapshot(
            data=b"".join(chunks),
            mode=stat.S_IMODE(file_stat.st_mode),
            device=file_stat.st_dev,
            inode=file_stat.st_ino,
        )
    except AtomicFileError:
        raise
    except FileNotFoundError as exc:
        raise AtomicFileError(
            missing_kind,
            f"原子写入目标不存在: {display_path}",
        ) from exc
    except OSError as exc:
        raise AtomicFileError(
            "validation",
            f"原子写入拒绝 symlink 或不可访问的普通文件: {display_path}",
        ) from exc
    finally:
        if file_fd >= 0:
            os.close(file_fd)


def _snapshot_bound_at(
    directory_fd: int,
    *,
    parent: Path,
    name: str,
    display_path: Path,
    missing_kind: str = "validation",
    fsync_file: bool = False,
    label: str = "Host 配置目录",
) -> _Snapshot:
    _assert_directory_is_current(directory_fd, parent, label=label)
    snapshot = _snapshot_at(
        directory_fd,
        name,
        display_path=display_path,
        missing_kind=missing_kind,
        fsync_file=fsync_file,
    )
    _assert_directory_is_current(directory_fd, parent, label=label)
    return snapshot


def _snapshot_path(path: Path, *, label: str) -> _Snapshot:
    path = _normalise_destination(path, allow_missing=True)
    directory_fd = _open_directory_without_symlinks(path.parent)
    try:
        return _snapshot_at(
            directory_fd,
            path.name,
            display_path=path,
        )
    except AtomicFileError as exc:
        raise AtomicFileError(
            "validation",
            f"{label} 不可访问或不是普通文件: {path}",
        ) from exc
    finally:
        os.close(directory_fd)


def _same_file(left: _Snapshot, right: _Snapshot) -> bool:
    return (
        left.device == right.device
        and left.inode == right.inode
        and left.mode == right.mode
        and left.data == right.data
    )


def _write_existing_regular_file(path: Path, data: bytes) -> None:
    path = _normalise_destination(path, allow_missing=True)
    file_fd = -1
    directory_fd = -1
    try:
        directory_fd = _open_directory_without_symlinks(path.parent)
        file_fd = os.open(
            path.name,
            os.O_WRONLY | os.O_TRUNC | os.O_NOFOLLOW | os.O_NONBLOCK,
            dir_fd=directory_fd,
        )
        file_stat = os.fstat(file_fd)
        if not stat.S_ISREG(file_stat.st_mode):
            raise AtomicFileError(
                "validation",
                f"快照输出路径不是普通文件: {path}",
            )
        view = memoryview(data)
        while view:
            written = os.write(file_fd, view)
            if written <= 0:
                raise OSError(errno.EIO, "快照输出写入未取得进展")
            view = view[written:]
    except AtomicFileError:
        raise
    except OSError as exc:
        raise AtomicFileError(
            "validation",
            f"无法安全写入快照输出文件: {path}",
        ) from exc
    finally:
        if file_fd >= 0:
            os.close(file_fd)
        if directory_fd >= 0:
            os.close(directory_fd)


def snapshot_entry_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    output: Path,
) -> tuple[bool, int]:
    destination_name = _validate_entry_name(destination_name, label="Host 配置名")
    _assert_directory_is_current(directory_fd, parent)
    _ensure_no_recovery_state(directory_fd, parent, destination_name)
    try:
        snapshot = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=destination_name,
            display_path=parent / destination_name,
            missing_kind="missing",
        )
    except AtomicFileError as exc:
        if exc.kind != "missing":
            raise
        _assert_directory_is_current(directory_fd, parent)
        _write_existing_regular_file(output, b"")
        _assert_directory_is_current(directory_fd, parent)
        return False, 0o644
    _write_existing_regular_file(output, snapshot.data)
    _assert_directory_is_current(directory_fd, parent)
    return True, snapshot.mode


def _unique_entry_name(directory_fd: int, prefix: str) -> str:
    for _ in range(100):
        candidate = f"{prefix}{secrets.token_hex(8)}"
        try:
            os.stat(candidate, dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            return candidate
    raise AtomicFileError("validation", f"无法分配唯一文件名: {prefix}")


def _create_regular_at(
    directory_fd: int,
    *,
    parent: Path,
    name: str,
    data: bytes,
    mode: int,
    owned_entries: dict[str, tuple[int, int]] | None = None,
) -> EntryIdentity:
    name = _validate_entry_name(name, label="安全文件名")
    display_path = parent / name
    file_fd = -1
    created = False
    created_identity: EntryIdentity | None = None
    _assert_directory_is_current(directory_fd, parent, label="安全文件目标目录")
    try:
        file_fd = os.open(
            name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            mode,
            dir_fd=directory_fd,
        )
        created = True
        created_stat = os.fstat(file_fd)
        created_identity = _identity_from_stat(created_stat)
        if owned_entries is not None:
            owned_entries[name] = (created_stat.st_dev, created_stat.st_ino)
        os.fchmod(file_fd, mode)
        view = memoryview(data)
        while view:
            written = os.write(file_fd, view)
            if written <= 0:
                raise OSError(errno.EIO, "安全文件写入未取得进展")
            view = view[written:]
        os.fsync(file_fd)
    except OSError as exc:
        if file_fd >= 0:
            os.close(file_fd)
            file_fd = -1
        raise AtomicFileError(
            "validation",
            f"安全文件写入、权限设置或持久化失败: {display_path}",
            recovery_paths=(display_path,) if created else (),
        ) from exc
    finally:
        if file_fd >= 0:
            os.close(file_fd)
    try:
        _assert_directory_is_current(directory_fd, parent, label="安全文件目标目录")
    except AtomicFileError as exc:
        assert created_identity is not None
        try:
            _unlink_entry_identity_at(
                directory_fd,
                parent=parent,
                name=name,
                expected_device=created_identity.device,
                expected_inode=created_identity.inode,
                require_current_parent=False,
            )
        except AtomicFileError as cleanup_error:
            cleanup_error.args = (
                f"安全文件创建期间目标目录被改向，且自有文件补偿清理失败: "
                f"{display_path}；{cleanup_error.args[0]}",
            )
            raise cleanup_error from exc
        raise AtomicFileError(
            "concurrent_update",
            f"安全文件创建期间目标目录被改向，自有文件已清理: {display_path}",
        ) from exc
    _fsync_directory(
        directory_fd,
        message=f"安全文件已创建但目录持久化失败: {display_path}",
        recovery_paths=(display_path,),
    )
    assert created_identity is not None
    try:
        _assert_directory_is_current(directory_fd, parent, label="安全文件目标目录")
    except AtomicFileError as exc:
        _unlink_entry_identity_at(
            directory_fd,
            parent=parent,
            name=name,
            expected_device=created_identity.device,
            expected_inode=created_identity.inode,
            require_current_parent=False,
        )
        raise AtomicFileError(
            "concurrent_update",
            f"安全文件持久化后目标目录被改向，自有文件已清理: {display_path}",
        ) from exc
    return created_identity


def _owned_paths_at(
    directory_fd: int,
    parent: Path,
    owned_entries: dict[str, tuple[int, int]],
) -> tuple[Path, ...]:
    paths: list[Path] = []
    for name, expected_identity in owned_entries.items():
        try:
            current = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        except OSError:
            paths.append(parent / name)
            continue
        if (current.st_dev, current.st_ino) == expected_identity:
            paths.append(parent / name)
    return tuple(paths)


def _cleanup_owned_entries_at(
    directory_fd: int,
    parent: Path,
    owned_entries: dict[str, tuple[int, int]],
) -> tuple[bool, list[tuple[str, BaseException]]]:
    removed_any = False
    cleanup_errors: list[tuple[str, BaseException]] = []
    for name, expected_identity in tuple(owned_entries.items()):
        try:
            removed = _unlink_entry_identity_at(
                directory_fd,
                parent=parent,
                name=name,
                expected_device=expected_identity[0],
                expected_inode=expected_identity[1],
                ignore_missing=True,
                require_current_parent=False,
            )
        except AtomicFileError as exc:
            cleanup_errors.append((name, exc))
            if exc.kind == "concurrent_update":
                owned_entries.pop(name, None)
        else:
            owned_entries.pop(name, None)
            removed_any = removed_any or removed
    return removed_any, cleanup_errors


def _cleanup_error_paths(
    cleanup_errors: list[tuple[str, BaseException]],
) -> tuple[Path, ...]:
    paths: list[Path] = []
    for _, error in cleanup_errors:
        if isinstance(error, AtomicFileError):
            paths.extend(error.recovery_paths)
    return tuple(dict.fromkeys(paths))


def _reconcile_generated_recovery_paths(
    error: AtomicFileError,
    *,
    generated_paths: set[Path],
    remaining_paths: tuple[Path, ...],
    cleanup_errors: list[tuple[str, BaseException]],
) -> None:
    error.recovery_paths = tuple(
        dict.fromkeys(
            (
                *(path for path in error.recovery_paths if path not in generated_paths),
                *remaining_paths,
                *_cleanup_error_paths(cleanup_errors),
            )
        )
    )


def prepare_update_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    rendered_path: Path,
    expected_path: Path | None,
    expected_mode: int,
) -> PreparedUpdate:
    destination_name = _validate_entry_name(destination_name, label="Host 配置名")
    _assert_directory_is_current(directory_fd, parent)
    _ensure_no_recovery_state(directory_fd, parent, destination_name)
    rendered = _snapshot_path(rendered_path, label="渲染配置")
    current: _Snapshot | None = None

    if expected_path is not None:
        expected = _snapshot_path(expected_path, label="Host 配置快照")
        current = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=destination_name,
            display_path=parent / destination_name,
            missing_kind="concurrent_update",
        )
        if current.data != expected.data or current.mode != expected_mode:
            raise AtomicFileError(
                "concurrent_update",
                f"Host 配置在准备事务期间已变化: {parent / destination_name}",
            )
    else:
        _assert_directory_is_current(directory_fd, parent)
        try:
            os.stat(destination_name, dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            pass
        except OSError as exc:
            raise AtomicFileError(
                "validation",
                f"无法检查待创建 Host 配置: {parent / destination_name}",
            ) from exc
        else:
            raise AtomicFileError(
                "concurrent_update",
                f"Host 配置在准备事务期间被创建: {parent / destination_name}",
            )
        _assert_directory_is_current(directory_fd, parent)

    backup_name: str | None = None
    backup_identity: EntryIdentity | None = None
    stage_name: str | None = None
    stage_identity: EntryIdentity | None = None
    owned_entries: dict[str, tuple[int, int]] = {}
    try:
        if current is not None:
            timestamp = time.strftime("%Y%m%d-%H%M%S")
            backup_name = _unique_entry_name(
                directory_fd,
                f"{destination_name}.bak.{timestamp}.",
            )
            backup_identity = _create_regular_at(
                directory_fd,
                parent=parent,
                name=backup_name,
                data=current.data,
                mode=expected_mode,
                owned_entries=owned_entries,
            )
        stage_name = _unique_entry_name(
            directory_fd,
            f"{destination_name}.pmai-new.",
        )
        stage_identity = _create_regular_at(
            directory_fd,
            parent=parent,
            name=stage_name,
            data=rendered.data,
            mode=expected_mode,
            owned_entries=owned_entries,
        )
        _assert_directory_is_current(directory_fd, parent)
    except BaseException as primary_error:
        generated_names = tuple(owned_entries)
        removed_any, cleanup_errors = _cleanup_owned_entries_at(
            directory_fd,
            parent,
            owned_entries,
        )

        remaining = _owned_paths_at(
            directory_fd,
            parent,
            owned_entries,
        )
        generated_paths = {parent / name for name in generated_names}
        if isinstance(primary_error, AtomicFileError):
            _reconcile_generated_recovery_paths(
                primary_error,
                generated_paths=generated_paths,
                remaining_paths=remaining,
                cleanup_errors=cleanup_errors,
            )
            if cleanup_errors:
                primary_error.kind = "recovery_required"
                primary_error.args = (
                    f"{primary_error.args[0]}；事务文件清理未完全成功，"
                    "请按恢复路径核对",
                )
            raise
        if cleanup_errors:
            primary = f"{type(primary_error).__name__}: {primary_error}"
            raise AtomicFileError(
                "recovery_required",
                f"Host 配置准备先因 {primary} 失败；事务文件清理未完全成功",
                recovery_paths=tuple(
                    dict.fromkeys((*remaining, *_cleanup_error_paths(cleanup_errors)))
                ),
            ) from primary_error
        raise
    assert stage_name is not None
    assert stage_identity is not None
    return PreparedUpdate(
        original_identity=(
            _identity_from_snapshot(current) if current is not None else None
        ),
        backup_name=backup_name,
        backup_identity=backup_identity,
        stage_name=stage_name,
        stage_identity=stage_identity,
    )


def _rename_noreplace(directory_fd: int, source: str, destination: str) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    encoded_source = os.fsencode(source)
    encoded_destination = os.fsencode(destination)

    if sys.platform == "darwin":
        function = getattr(libc, "renameatx_np", None)
        flag = 0x00000004  # RENAME_EXCL
    elif sys.platform.startswith("linux"):
        function = getattr(libc, "renameat2", None)
        flag = 0x00000001  # RENAME_NOREPLACE
    else:
        function = None
        flag = 0

    if function is None:
        raise AtomicFileError(
            "unsupported",
            "当前系统不支持原子 RENAME_NOREPLACE，拒绝降级为覆盖式 rename",
        )

    function.argtypes = [
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_int,
        ctypes.c_char_p,
        ctypes.c_uint,
    ]
    function.restype = ctypes.c_int
    if function(
        directory_fd,
        encoded_source,
        directory_fd,
        encoded_destination,
        flag,
    ) != 0:
        error_number = ctypes.get_errno()
        raise OSError(
            error_number,
            os.strerror(error_number),
            f"{source} -> {destination}",
        )


def _rename_noreplace_bound(
    directory_fd: int,
    source: str,
    destination: str,
    *,
    parent: Path,
    recovery_paths: tuple[Path, ...],
    label: str,
) -> None:
    # A dirfd pins an inode, not its membership at ``parent``. A rebind can land
    # between this precheck and rename. The postcheck therefore reports a
    # recovery state; callers that know the moved entries must compensate via
    # the same pinned dirfd before returning.
    _assert_directory_is_current(directory_fd, parent, label=label)
    _rename_noreplace(directory_fd, source, destination)
    try:
        _assert_directory_is_current(directory_fd, parent, label=label)
    except AtomicFileError as exc:
        raise AtomicFileError(
            "recovery_required",
            f"{label}期间目录被改向，命名空间变更状态需人工核对: {parent}",
            recovery_paths=recovery_paths,
        ) from exc


def _fsync_directory(
    directory_fd: int,
    *,
    message: str,
    recovery_paths: tuple[Path, ...] = (),
) -> None:
    try:
        os.fsync(directory_fd)
    except OSError as exc:
        raise AtomicFileError(
            "recovery_required",
            message,
            recovery_paths=recovery_paths,
        ) from exc


def _normalise_destination(path: Path, *, allow_missing: bool) -> Path:
    if not path.is_absolute():
        path = Path.cwd() / path
    try:
        parent = path.parent.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise AtomicFileError(
            "validation",
            f"原子写入目标目录不可访问: {path.parent}",
        ) from exc
    normalised = parent / path.name
    if not allow_missing:
        try:
            resolved = normalised.resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise AtomicFileError(
                "validation",
                f"原子写入目标不可访问: {normalised}",
            ) from exc
        if resolved != normalised:
            raise AtomicFileError(
                "validation",
                f"原子写入目标路径组件不能是 symlink: {normalised}",
            )
    return normalised


def _destination_for_directory_access(
    path: Path,
    *,
    require_canonical_path: bool,
) -> Path:
    if require_canonical_path:
        if not path.is_absolute():
            raise AtomicFileError("validation", f"安全写入目标必须是绝对路径: {path}")
        try:
            canonical_parent = path.parent.resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise AtomicFileError(
                "validation",
                f"原子写入目标目录不可访问: {path.parent}",
            ) from exc
        if canonical_parent != path.parent:
            raise AtomicFileError(
                "validation",
                f"安全写入目标路径组件不能是 symlink 或非规范路径: {path}",
            )
        return path
    return _normalise_destination(path, allow_missing=True)


def _unique_quarantine_name(directory_fd: int, destination_name: str) -> str:
    prefix = f".{destination_name}.pmai-cas-original-"
    for _ in range(100):
        candidate = f"{prefix}{os.getpid()}-{secrets.token_hex(8)}"
        try:
            os.stat(candidate, dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            return candidate
    raise AtomicFileError("validation", "无法分配唯一的原子写入隔离文件名")


def _recovery_paths(
    directory_fd: int,
    parent: Path,
    destination_name: str,
    *,
    allowed_names: tuple[str, ...] = (),
) -> tuple[Path, ...]:
    prefixes = (
        f".{destination_name}.pmai-cas-original-",
        f"{destination_name}.pmai-new.",
        f".{destination_name}.pmai-cas-stage-",
        f".{destination_name}.pmai-write-stage-",
        f".{destination_name}.pmai-stage-claim-",
    )
    cleanup_prefixes = (*prefixes, f"{destination_name}.bak.")
    _assert_directory_is_current(directory_fd, parent)
    try:
        names = os.listdir(directory_fd)
    except OSError as exc:
        raise AtomicFileError("validation", f"无法扫描原子写入恢复文件: {parent}") from exc
    _assert_directory_is_current(directory_fd, parent)
    allowed = set(allowed_names)
    recovery_names = (
        name
        for name in names
        if name not in allowed
        and (
            name.startswith(prefixes)
            or (
                ".pmai-cleanup-claim-" in name
                and name.startswith(cleanup_prefixes)
            )
        )
    )
    return tuple(sorted(parent / name for name in recovery_names))


def _existing_paths_at(
    directory_fd: int,
    parent: Path,
    *names: str,
) -> tuple[Path, ...]:
    paths: list[Path] = []
    for name in names:
        try:
            os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
        except FileNotFoundError:
            continue
        except OSError:
            paths.append(parent / name)
            continue
        paths.append(parent / name)
    return tuple(paths)


def _ensure_no_recovery_state(
    directory_fd: int,
    parent: Path,
    destination_name: str,
    *,
    allowed_names: tuple[str, ...] = (),
) -> None:
    paths = _recovery_paths(
        directory_fd,
        parent,
        destination_name,
        allowed_names=allowed_names,
    )
    if paths:
        rendered = "、".join(str(path) for path in paths)
        raise AtomicFileError(
            "recovery_required",
            f"发现未收口的原子写入原件，请先恢复或确认: {rendered}",
            recovery_paths=paths,
        )


def ensure_no_recovery_state_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
) -> None:
    destination_name = _validate_entry_name(destination_name, label="原子写入目标名")
    _assert_directory_is_current(directory_fd, parent, label="原子写入目标目录")
    _ensure_no_recovery_state(directory_fd, parent, destination_name)
    _assert_directory_is_current(directory_fd, parent, label="原子写入目标目录")


def ensure_no_recovery_state(
    path: Path,
    *,
    require_canonical_path: bool = False,
) -> None:
    """Fail closed when a prior CAS left quarantine, stage, or cleanup state."""
    normalised = _destination_for_directory_access(
        path,
        require_canonical_path=require_canonical_path,
    )
    directory_fd = _open_directory_without_symlinks(normalised.parent)
    try:
        _ensure_no_recovery_state(directory_fd, normalised.parent, normalised.name)
    finally:
        os.close(directory_fd)


def read_regular_bytes(
    path: Path,
    *,
    require_canonical_path: bool = False,
) -> bytes:
    """Read one stable regular-file snapshot through a rebound-safe directory fd."""
    normalised = _destination_for_directory_access(
        path,
        require_canonical_path=require_canonical_path,
    )
    directory_fd = _open_directory_without_symlinks(normalised.parent)
    verification_fd = -1
    try:
        directory_stat = os.fstat(directory_fd)
        _ensure_no_recovery_state(directory_fd, normalised.parent, normalised.name)
        snapshot = _snapshot_at(
            directory_fd,
            normalised.name,
            display_path=normalised,
        )
        verification_fd = _open_current_bound_directory(
            normalised.parent,
            expected_device=directory_stat.st_dev,
            expected_inode=directory_stat.st_ino,
            label="安全读取目标目录",
        )
        verified = _snapshot_at(
            verification_fd,
            normalised.name,
            display_path=normalised,
        )
        if not _same_file(snapshot, verified):
            raise AtomicFileError(
                "concurrent_update",
                f"安全读取期间文件发生变化，拒绝返回混合快照: {normalised}",
            )
        return snapshot.data
    finally:
        if verification_fd >= 0:
            os.close(verification_fd)
        os.close(directory_fd)


def read_text_for_update(
    path: Path,
    *,
    require_canonical_path: bool = False,
) -> str:
    """Read a regular UTF-8 target through the same fixed directory boundary."""
    normalised = _destination_for_directory_access(
        path,
        require_canonical_path=require_canonical_path,
    )
    directory_fd = _open_directory_without_symlinks(normalised.parent)
    verification_fd = -1
    try:
        directory_stat = os.fstat(directory_fd)
        _ensure_no_recovery_state(directory_fd, normalised.parent, normalised.name)
        snapshot = _snapshot_at(
            directory_fd,
            normalised.name,
            display_path=normalised,
            missing_kind="concurrent_update",
        )
        verification_fd = _open_current_bound_directory(
            normalised.parent,
            expected_device=directory_stat.st_dev,
            expected_inode=directory_stat.st_ino,
            label="原子读取目标目录",
        )
        verified = _snapshot_at(
            verification_fd,
            normalised.name,
            display_path=normalised,
            missing_kind="concurrent_update",
        )
        if not _same_file(snapshot, verified):
            raise AtomicFileError(
                "concurrent_update",
                f"原子读取期间文件发生变化，拒绝返回混合快照: {normalised}",
            )
    finally:
        if verification_fd >= 0:
            os.close(verification_fd)
        os.close(directory_fd)
    try:
        return snapshot.data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AtomicFileError(
            "validation",
            f"原子写入目标不是合法 UTF-8 文本: {normalised}",
        ) from exc


def _restore_claim(
    directory_fd: int,
    quarantine_name: str,
    destination_name: str,
    *,
    parent: Path,
    require_current_parent: bool = True,
) -> None:
    try:
        if require_current_parent:
            _rename_noreplace_bound(
                directory_fd,
                quarantine_name,
                destination_name,
                parent=parent,
                recovery_paths=(
                    parent / destination_name,
                    parent / quarantine_name,
                ),
                label="恢复原件",
            )
        else:
            _rename_noreplace(directory_fd, quarantine_name, destination_name)
    except (AtomicFileError, OSError) as exc:
        paths = _existing_paths_at(
            directory_fd,
            parent,
            destination_name,
            quarantine_name,
        )
        if isinstance(exc, OSError) and exc.errno == errno.EEXIST:
            message = (
                "恢复原件时目标名已被并发创建；"
                "未覆盖任何现存路径，请核对正式路径与隔离原件"
            )
        else:
            message = (
                "原子 claim 后恢复原件失败；正式路径可能缺失，"
                "未覆盖任何仍存在的路径"
            )
        raise AtomicFileError(
            "recovery_required",
            message,
            recovery_paths=paths,
        ) from exc
    _fsync_directory(
        directory_fd,
        message=(
            "原件已恢复到正式路径，但目录持久化失败；"
            f"请核对后再继续: {parent / destination_name}"
        ),
        recovery_paths=(parent / destination_name,),
    )
    if require_current_parent:
        _assert_directory_is_current(directory_fd, parent, label="恢复原件目录")


def _restore_claim_if_identity(
    directory_fd: int,
    source_name: str,
    destination_name: str,
    *,
    parent: Path,
    expected_identity: EntryIdentity,
    require_current_parent: bool = True,
) -> None:
    source_path = parent / source_name
    try:
        current = os.stat(
            source_name,
            dir_fd=directory_fd,
            follow_symlinks=False,
        )
    except OSError as exc:
        raise AtomicFileError(
            "recovery_required",
            f"无法确认待恢复文件身份: {source_path}",
            recovery_paths=(source_path,),
        ) from exc
    if _identity_from_stat(current) != expected_identity:
        raise AtomicFileError(
            "recovery_required",
            f"待恢复文件身份已变化，未移动 foreign 文件: {source_path}",
            recovery_paths=(source_path, parent / destination_name),
        )
    _restore_claim(
        directory_fd,
        source_name,
        destination_name,
        parent=parent,
        require_current_parent=require_current_parent,
    )


def _unique_cleanup_claim_name(directory_fd: int, name: str) -> str:
    return _unique_entry_name(
        directory_fd,
        f"{name}.pmai-cleanup-claim-{os.getpid()}-",
    )


def _unlink_entry_identity_at(
    directory_fd: int,
    *,
    parent: Path,
    name: str,
    expected_device: int,
    expected_inode: int,
    ignore_missing: bool = False,
    require_current_parent: bool = True,
) -> bool:
    """Delete exactly one same-directory entry identity without name-based unlink."""
    name = _validate_entry_name(name, label="待清理文件名")
    expected_identity = _entry_identity(expected_device, expected_inode)
    display_path = parent / name
    try:
        claim_name = _unique_cleanup_claim_name(directory_fd, name)
    except OSError as exc:
        raise AtomicFileError(
            "recovery_required",
            f"无法分配事务文件清理 claim: {display_path}",
            recovery_paths=(display_path,),
        ) from exc
    claim_path = parent / claim_name

    try:
        if require_current_parent:
            _rename_noreplace_bound(
                directory_fd,
                name,
                claim_name,
                parent=parent,
                recovery_paths=(display_path, claim_path),
                label="事务文件清理 claim",
            )
        else:
            _rename_noreplace(directory_fd, name, claim_name)
    except FileNotFoundError as exc:
        if ignore_missing:
            return False
        raise AtomicFileError("validation", f"待清理文件不存在: {display_path}") from exc
    except OSError as exc:
        raise AtomicFileError(
            "recovery_required",
            f"无法安全 claim 待清理事务文件: {display_path}",
            recovery_paths=_existing_paths_at(
                directory_fd,
                parent,
                name,
                claim_name,
            ),
        ) from exc
    except AtomicFileError as exc:
        if exc.kind != "recovery_required":
            raise
        _restore_claim_if_identity(
            directory_fd,
            claim_name,
            name,
            parent=parent,
            expected_identity=expected_identity,
            require_current_parent=False,
        )
        raise AtomicFileError(
            "concurrent_update",
            "事务文件清理 claim 期间目录被改向，自有命名空间变更已补偿",
        ) from exc

    _fsync_directory(
        directory_fd,
        message=f"事务文件已 claim 但目录持久化失败: {claim_path}",
        recovery_paths=(claim_path,),
    )
    try:
        claimed_stat = os.stat(
            claim_name,
            dir_fd=directory_fd,
            follow_symlinks=False,
        )
    except OSError as exc:
        _restore_claim(
            directory_fd,
            claim_name,
            name,
            parent=parent,
            require_current_parent=require_current_parent,
        )
        raise AtomicFileError(
            "recovery_required",
            f"无法校验已 claim 的事务文件，原名已恢复: {display_path}",
            recovery_paths=(display_path,),
        ) from exc

    if _identity_from_stat(claimed_stat) != expected_identity:
        _restore_claim(
            directory_fd,
            claim_name,
            name,
            parent=parent,
            require_current_parent=require_current_parent,
        )
        raise AtomicFileError(
            "concurrent_update",
            f"待清理文件身份已变化，foreign 文件已恢复且未删除: {display_path}",
            recovery_paths=(display_path,),
        )

    if require_current_parent:
        _assert_directory_is_current(directory_fd, parent, label="事务文件清理目录")
    try:
        os.unlink(claim_name, dir_fd=directory_fd)
    except OSError as exc:
        raise AtomicFileError(
            "recovery_required",
            f"事务文件已 claim，但清理失败: {claim_path}",
            recovery_paths=(claim_path,),
        ) from exc
    _fsync_directory(
        directory_fd,
        message=f"事务文件已清理但目录持久化失败: {display_path}",
        recovery_paths=(claim_path,),
    )
    if require_current_parent:
        try:
            _assert_directory_is_current(directory_fd, parent, label="事务文件清理目录")
        except AtomicFileError as exc:
            raise AtomicFileError(
                "concurrent_update",
                f"事务文件清理完成后目录被改向，未继续操作: {display_path}",
            ) from exc
    return True


def unlink_entry_at(
    directory_fd: int,
    *,
    parent: Path,
    name: str,
    expected_device: int,
    expected_inode: int,
    ignore_missing: bool = False,
) -> bool:
    return _unlink_entry_identity_at(
        directory_fd,
        parent=parent,
        name=name,
        expected_device=expected_device,
        expected_inode=expected_inode,
        ignore_missing=ignore_missing,
        require_current_parent=True,
    )


def _claim_staged_entry_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    staged_name: str,
    staged_identity: EntryIdentity,
) -> tuple[str, _Snapshot]:
    claim_name = _unique_entry_name(
        directory_fd,
        f".{destination_name}.pmai-stage-claim-{os.getpid()}-",
    )
    staged_path = parent / staged_name
    claim_path = parent / claim_name
    initial = _snapshot_bound_at(
        directory_fd,
        parent=parent,
        name=staged_name,
        display_path=staged_path,
        fsync_file=True,
    )
    _assert_identity(
        initial,
        staged_identity,
        path=staged_path,
        label="Host 暂存文件",
    )
    try:
        _rename_noreplace_bound(
            directory_fd,
            staged_name,
            claim_name,
            parent=parent,
            recovery_paths=(staged_path, claim_path),
            label="Host 暂存文件 claim",
        )
    except AtomicFileError as exc:
        if exc.kind != "recovery_required":
            raise
        try:
            claimed_stat = os.stat(
                claim_name,
                dir_fd=directory_fd,
                follow_symlinks=False,
            )
        except OSError as inspect_error:
            exc.recovery_paths = tuple(
                dict.fromkeys((*exc.recovery_paths, staged_path, claim_path))
            )
            raise exc from inspect_error
        if _identity_from_stat(claimed_stat) != staged_identity:
            raise
        _restore_claim(
            directory_fd,
            claim_name,
            staged_name,
            parent=parent,
            require_current_parent=False,
        )
        raise AtomicFileError(
            "concurrent_update",
            "Host 暂存文件 claim 期间目录被改向，自有命名空间变更已补偿",
        ) from exc
    _fsync_directory(
        directory_fd,
        message=f"Host 暂存文件已 claim 但目录持久化失败: {claim_path}",
        recovery_paths=(claim_path,),
    )
    try:
        claimed = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=claim_name,
            display_path=claim_path,
        )
    except AtomicFileError as exc:
        try:
            _restore_claim(
                directory_fd,
                claim_name,
                staged_name,
                parent=parent,
            )
        except AtomicFileError:
            raise
        raise AtomicFileError(
            "concurrent_update",
            f"Host 暂存文件 claim 后无法校验，已恢复原名: {staged_path}",
        ) from exc
    try:
        _assert_identity(
            claimed,
            staged_identity,
            path=claim_path,
            label="Host 暂存文件",
        )
    except AtomicFileError as exc:
        _restore_claim(
            directory_fd,
            claim_name,
            staged_name,
            parent=parent,
        )
        raise AtomicFileError(
            "concurrent_update",
            f"Host 暂存文件身份已变化，foreign 文件已恢复且未安装: {staged_path}",
            recovery_paths=(staged_path,),
        ) from exc
    return claim_name, claimed


def _replace_staged_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    staged_name: str,
    staged_identity: EntryIdentity,
    expected: _Snapshot,
) -> None:
    _assert_directory_is_current(directory_fd, parent)
    _ensure_no_recovery_state(
        directory_fd,
        parent,
        destination_name,
        allowed_names=(staged_name,),
    )
    destination_path = parent / destination_name
    staged_path = parent / staged_name
    quarantine_name = _unique_quarantine_name(directory_fd, destination_name)
    quarantine_path = parent / quarantine_name
    staged_claim_name, staged = _claim_staged_entry_at(
        directory_fd,
        parent=parent,
        destination_name=destination_name,
        staged_name=staged_name,
        staged_identity=staged_identity,
    )
    staged_claim_path = parent / staged_claim_name

    try:
        _rename_noreplace_bound(
            directory_fd,
            destination_name,
            quarantine_name,
            parent=parent,
            recovery_paths=(destination_path, quarantine_path, staged_claim_path),
            label="原子写入 claim",
        )
    except FileNotFoundError as exc:
        _restore_claim(
            directory_fd,
            staged_claim_name,
            staged_name,
            parent=parent,
        )
        raise AtomicFileError(
            "concurrent_update",
            f"原子写入前目标已被删除: {destination_path}",
        ) from exc
    except OSError as exc:
        _restore_claim(
            directory_fd,
            staged_claim_name,
            staged_name,
            parent=parent,
        )
        raise AtomicFileError(
            "validation",
            f"无法原子 claim 写入目标: {destination_path}",
        ) from exc
    except AtomicFileError as exc:
        if exc.kind == "recovery_required":
            _restore_claim(
                directory_fd,
                quarantine_name,
                destination_name,
                parent=parent,
                require_current_parent=False,
            )
            _restore_claim(
                directory_fd,
                staged_claim_name,
                staged_name,
                parent=parent,
                require_current_parent=False,
            )
            raise AtomicFileError(
                "concurrent_update",
                "原子写入 claim 期间目录被改向，自有命名空间变更已补偿",
            ) from exc
        _restore_claim(
            directory_fd,
            staged_claim_name,
            staged_name,
            parent=parent,
        )
        raise
    _fsync_directory(
        directory_fd,
        message=(
            "原子 claim 已发生但目录持久化失败；正式路径当前可能缺失，"
            f"原件位于: {quarantine_path}"
        ),
        recovery_paths=(quarantine_path, staged_claim_path),
    )

    try:
        claimed = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=quarantine_name,
            display_path=quarantine_path,
        )
    except AtomicFileError as exc:
        _restore_claim(
            directory_fd,
            quarantine_name,
            destination_name,
            parent=parent,
        )
        _restore_claim(
            directory_fd,
            staged_claim_name,
            staged_name,
            parent=parent,
        )
        raise AtomicFileError(
            "concurrent_update",
            f"原子 claim 后发现目标已变为不可接受的文件类型，已恢复并发版本: {destination_path}",
        ) from exc
    if not _same_file(claimed, expected):
        _restore_claim(
            directory_fd,
            quarantine_name,
            destination_name,
            parent=parent,
        )
        _restore_claim(
            directory_fd,
            staged_claim_name,
            staged_name,
            parent=parent,
        )
        raise AtomicFileError(
            "concurrent_update",
            f"原子写入前目标 inode、内容或权限已变化: {destination_path}",
        )

    try:
        _rename_noreplace_bound(
            directory_fd,
            staged_claim_name,
            destination_name,
            parent=parent,
            recovery_paths=(destination_path, quarantine_path, staged_claim_path),
            label="原子安装新文件",
        )
    except OSError as exc:
        recovery = quarantine_path
        if exc.errno != errno.EEXIST:
            try:
                _restore_claim(
                    directory_fd,
                    quarantine_name,
                    destination_name,
                    parent=parent,
                )
            except AtomicFileError:
                raise
            _restore_claim(
                directory_fd,
                staged_claim_name,
                staged_name,
                parent=parent,
            )
            raise AtomicFileError(
                "validation",
                f"无法原子安装新文件: {destination_path}",
            ) from exc
        _restore_claim(
            directory_fd,
            staged_claim_name,
            staged_name,
            parent=parent,
        )
        raise AtomicFileError(
            "recovery_required",
            "原子写入期间目标名被并发创建；当前目标、原件和暂存文件均未覆盖，"
            f"原件位于: {recovery}，暂存文件位于: {staged_path}",
            recovery_paths=(destination_path, recovery, staged_path),
        ) from exc
    except AtomicFileError as exc:
        if exc.kind == "recovery_required":
            _restore_claim_if_identity(
                directory_fd,
                destination_name,
                staged_name,
                parent=parent,
                expected_identity=staged_identity,
                require_current_parent=False,
            )
            _restore_claim(
                directory_fd,
                quarantine_name,
                destination_name,
                parent=parent,
                require_current_parent=False,
            )
            raise AtomicFileError(
                "concurrent_update",
                "原子安装期间目录被改向，自有命名空间变更已补偿",
            ) from exc
        _restore_claim(
            directory_fd,
            quarantine_name,
            destination_name,
            parent=parent,
        )
        _restore_claim(
            directory_fd,
            staged_claim_name,
            staged_name,
            parent=parent,
        )
        raise
    _fsync_directory(
        directory_fd,
        message=(
            "新文件已安装但目录持久化失败；正式文件和原件均已保留，"
            f"原件位于: {quarantine_path}"
        ),
        recovery_paths=(destination_path, quarantine_path),
    )

    try:
        installed = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=destination_name,
            display_path=destination_path,
        )
    except AtomicFileError as exc:
        paths = _existing_paths_at(
            directory_fd,
            parent,
            destination_name,
            quarantine_name,
        )
        if destination_path in paths:
            message = (
                "原子安装后无法校验正式路径；当前正式路径仍存在，"
                f"可能已被并发替换或变为不可接受的文件类型: {destination_path}"
            )
        else:
            message = (
                "原子安装后无法校验正式路径；正式路径可能已被删除、"
                f"替换或变为不可访问: {destination_path}"
            )
        if quarantine_path in paths:
            message += f"；隔离原件已保留: {quarantine_path}"
        else:
            message += "；隔离原件当前也无法确认"
        raise AtomicFileError(
            "recovery_required",
            message,
            recovery_paths=paths,
        ) from exc
    if not _same_file(installed, staged):
        paths = _existing_paths_at(
            directory_fd,
            parent,
            destination_name,
            quarantine_name,
        )
        if destination_path in paths:
            message = f"原子安装后目标又被并发修改，当前正式路径已保留: {destination_path}"
        else:
            message = (
                "原子安装后目标又被并发修改，随后正式路径消失: "
                f"{destination_path}"
            )
        if quarantine_path in paths:
            message += f"；隔离原件已保留: {quarantine_path}"
        else:
            message += "；隔离原件当前也无法确认"
        raise AtomicFileError(
            "recovery_required",
            message,
            recovery_paths=paths,
        )

    if staged_path in _existing_paths_at(
        directory_fd,
        parent,
        staged_name,
    ):
        raise AtomicFileError(
            "recovery_required",
            "Host 暂存文件公开名称在 claim 后被并发复用；foreign 文件未安装或删除，"
            "新文件与旧原件均已保留",
            recovery_paths=(destination_path, quarantine_path, staged_path),
        )

    unlink_entry_at(
        directory_fd,
        parent=parent,
        name=quarantine_name,
        expected_device=claimed.device,
        expected_inode=claimed.inode,
    )
    _assert_directory_is_current(directory_fd, parent)


def replace_text_if_unchanged_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    text: str,
    expected_text: str,
    expected_device: int | None = None,
    expected_inode: int | None = None,
) -> None:
    """Replace text through one bound directory fd and optional file identity."""
    destination_name = _validate_entry_name(destination_name, label="原子写入目标名")
    if (expected_device is None) != (expected_inode is None):
        raise AtomicFileError(
            "validation",
            "expected_device 与 expected_inode 必须同时提供或同时省略",
        )
    expected_identity = (
        _entry_identity(expected_device, expected_inode)
        if expected_device is not None and expected_inode is not None
        else None
    )
    destination = parent / destination_name
    staged_name: str | None = None
    owned_entries: dict[str, tuple[int, int]] = {}
    active_error: BaseException | None = None
    cleanup_error: AtomicFileError | None = None
    cleanup_cause: BaseException | None = None
    try:
        _assert_directory_is_current(directory_fd, parent, label="原子写入目标目录")
        _ensure_no_recovery_state(directory_fd, parent, destination_name)
        original = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=destination_name,
            display_path=destination,
            missing_kind="concurrent_update",
            label="原子写入目标目录",
        )
        if original.data != expected_text.encode("utf-8"):
            raise AtomicFileError(
                "concurrent_update",
                f"原子写入前文件已变化，拒绝覆盖: {destination}",
            )
        if expected_identity is not None:
            _assert_identity(
                original,
                expected_identity,
                path=destination,
                label="原子写入目标",
            )

        for _ in range(100):
            candidate = (
                f".{destination_name}.pmai-cas-stage-"
                f"{os.getpid()}-{secrets.token_hex(8)}"
            )
            _assert_directory_is_current(
                directory_fd,
                parent,
                label="原子写入目标目录",
            )
            try:
                staged_fd = os.open(
                    candidate,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                    original.mode,
                    dir_fd=directory_fd,
                )
            except FileExistsError:
                continue
            try:
                staged_stat = os.fstat(staged_fd)
            except OSError as exc:
                try:
                    os.close(staged_fd)
                except OSError:
                    pass
                raise AtomicFileError(
                    "recovery_required",
                    f"暂存文件已创建但无法登记所有权: {parent / candidate}",
                    recovery_paths=(parent / candidate,),
                ) from exc
            staged_name = candidate
            owned_entries[candidate] = (staged_stat.st_dev, staged_stat.st_ino)
            break
        else:
            raise AtomicFileError("validation", f"无法创建安全暂存文件: {parent}")

        try:
            with os.fdopen(staged_fd, mode="wb") as handle:
                handle.write(text.encode("utf-8"))
                handle.flush()
                os.fchmod(handle.fileno(), original.mode)
                os.fsync(handle.fileno())
        except OSError as exc:
            raise AtomicFileError(
                "validation",
                f"暂存文件写入或持久化失败，正式文件未修改: {destination}",
            ) from exc
        _assert_directory_is_current(directory_fd, parent, label="原子写入目标目录")
        stage_identity = _entry_identity(*owned_entries[staged_name])
        try:
            _replace_staged_at(
                directory_fd,
                parent=parent,
                destination_name=destination_name,
                staged_name=staged_name,
                staged_identity=stage_identity,
                expected=original,
            )
        except AtomicFileError as exc:
            if parent / staged_name in exc.recovery_paths:
                owned_entries.pop(staged_name, None)
                staged_name = None
            raise
        owned_entries.pop(staged_name, None)
        staged_name = None
        _assert_directory_is_current(directory_fd, parent, label="原子写入目标目录")
    except BaseException as exc:
        active_error = exc
        raise
    finally:
        if owned_entries:
            generated_paths = {parent / name for name in owned_entries}
            removed_any, cleanup_errors = _cleanup_owned_entries_at(
                directory_fd,
                parent,
                owned_entries,
            )
            remaining = _owned_paths_at(directory_fd, parent, owned_entries)
            if isinstance(active_error, AtomicFileError):
                _reconcile_generated_recovery_paths(
                    active_error,
                    generated_paths=generated_paths,
                    remaining_paths=remaining,
                    cleanup_errors=cleanup_errors,
                )
            if cleanup_errors:
                message = "暂存文件清理失败，请按恢复路径人工核对"
                if isinstance(active_error, AtomicFileError):
                    active_error.kind = "recovery_required"
                    active_error.args = (f"{active_error.args[0]}；{message}",)
                else:
                    primary = (
                        f"{type(active_error).__name__}: {active_error}"
                        if active_error is not None
                        else "未知原子写入错误"
                    )
                    cleanup_error = AtomicFileError(
                        "recovery_required",
                        f"原子写入先因 {primary} 失败；{message}",
                        recovery_paths=tuple(
                            dict.fromkeys(
                                (*remaining, *_cleanup_error_paths(cleanup_errors))
                            )
                        ),
                    )
                    cleanup_cause = cleanup_errors[0][1]
        if cleanup_error is not None:
            if active_error is not None:
                raise cleanup_error from active_error
            raise cleanup_error from cleanup_cause


def replace_text_if_unchanged(
    path: Path,
    text: str,
    *,
    expected_text: str,
    require_canonical_path: bool = False,
) -> None:
    normalised = _destination_for_directory_access(
        path,
        require_canonical_path=require_canonical_path,
    )
    directory_fd = _open_directory_without_symlinks(normalised.parent)
    try:
        replace_text_if_unchanged_at(
            directory_fd,
            parent=normalised.parent,
            destination_name=normalised.name,
            text=text,
            expected_text=expected_text,
        )
    finally:
        os.close(directory_fd)


def write_text_atomically(
    path: Path,
    text: str,
    *,
    require_canonical_path: bool = False,
    create_mode: int = 0o600,
) -> None:
    """CAS-replace or no-replace-create a UTF-8 file through a fixed directory."""
    if create_mode < 0 or create_mode > 0o7777:
        raise AtomicFileError("validation", "原子写入 create_mode 超出合法权限范围")
    normalised = _destination_for_directory_access(
        path,
        require_canonical_path=require_canonical_path,
    )
    encoded = text.encode("utf-8")
    directory_fd = _open_directory_without_symlinks(normalised.parent)
    commit_fd = -1
    postcheck_fd = -1
    owned_entries: dict[str, tuple[int, int]] = {}
    stage_name: str | None = None
    active_error: BaseException | None = None
    cleanup_error: AtomicFileError | None = None
    try:
        directory_stat = os.fstat(directory_fd)
        _ensure_no_recovery_state(directory_fd, normalised.parent, normalised.name)
        try:
            original = _snapshot_at(
                directory_fd,
                normalised.name,
                display_path=normalised,
                missing_kind="missing",
            )
        except AtomicFileError as exc:
            if exc.kind != "missing":
                raise
            original = None

        verification_fd = _open_current_bound_directory(
            normalised.parent,
            expected_device=directory_stat.st_dev,
            expected_inode=directory_stat.st_ino,
            label="原子写入目标目录",
        )
        try:
            if original is None:
                try:
                    os.stat(
                        normalised.name,
                        dir_fd=verification_fd,
                        follow_symlinks=False,
                    )
                except FileNotFoundError:
                    pass
                else:
                    raise AtomicFileError(
                        "concurrent_update",
                        f"原子写入目标在准备期间被创建: {normalised}",
                    )
            else:
                verified = _snapshot_at(
                    verification_fd,
                    normalised.name,
                    display_path=normalised,
                    missing_kind="concurrent_update",
                )
                if not _same_file(original, verified):
                    raise AtomicFileError(
                        "concurrent_update",
                        f"原子写入目标在准备期间发生变化: {normalised}",
                    )
        finally:
            os.close(verification_fd)

        mode = original.mode if original is not None else create_mode
        for _ in range(100):
            candidate = (
                f".{normalised.name}.pmai-write-stage-"
                f"{os.getpid()}-{secrets.token_hex(8)}"
            )
            try:
                _create_regular_at(
                    directory_fd,
                    parent=normalised.parent,
                    name=candidate,
                    data=encoded,
                    mode=mode,
                    owned_entries=owned_entries,
                )
            except AtomicFileError as exc:
                if isinstance(exc.__cause__, FileExistsError):
                    continue
                raise
            stage_name = candidate
            break
        else:
            raise AtomicFileError(
                "validation",
                f"无法创建安全暂存文件: {normalised.parent}",
            )

        commit_fd = _open_current_bound_directory(
            normalised.parent,
            expected_device=directory_stat.st_dev,
            expected_inode=directory_stat.st_ino,
            label="原子写入目标目录",
        )
        assert stage_name is not None
        stage_identity = _entry_identity(*owned_entries[stage_name])
        try:
            if original is None:
                _create_from_staged_at(
                    commit_fd,
                    parent=normalised.parent,
                    destination_name=normalised.name,
                    staged_name=stage_name,
                    staged_identity=stage_identity,
                )
            else:
                _replace_staged_at(
                    commit_fd,
                    parent=normalised.parent,
                    destination_name=normalised.name,
                    staged_name=stage_name,
                    staged_identity=stage_identity,
                    expected=original,
                )
        except AtomicFileError as exc:
            if normalised.parent / stage_name in exc.recovery_paths:
                owned_entries.pop(stage_name, None)
            raise
        owned_entries.pop(stage_name, None)
        stage_name = None

        postcheck_fd = _open_current_bound_directory(
            normalised.parent,
            expected_device=directory_stat.st_dev,
            expected_inode=directory_stat.st_ino,
            label="原子写入目标目录",
        )
        installed = _snapshot_bound_at(
            postcheck_fd,
            parent=normalised.parent,
            name=normalised.name,
            display_path=normalised,
        )
        if installed.data != encoded or installed.mode != mode:
            raise AtomicFileError(
                "recovery_required",
                f"原子写入完成后目标又发生变化，请核对: {normalised}",
                recovery_paths=_existing_paths_at(
                    postcheck_fd,
                    normalised.parent,
                    normalised.name,
                ),
            )
    except BaseException as exc:
        active_error = exc
        raise
    finally:
        if owned_entries:
            generated_paths = {normalised.parent / name for name in owned_entries}
            removed_any, cleanup_errors = _cleanup_owned_entries_at(
                directory_fd,
                normalised.parent,
                owned_entries,
            )
            remaining = _owned_paths_at(
                directory_fd,
                normalised.parent,
                owned_entries,
            )
            if isinstance(active_error, AtomicFileError):
                _reconcile_generated_recovery_paths(
                    active_error,
                    generated_paths=generated_paths,
                    remaining_paths=remaining,
                    cleanup_errors=cleanup_errors,
                )
            if cleanup_errors:
                message = "原子写入暂存文件清理未完全成功，请按恢复路径核对"
                if isinstance(active_error, AtomicFileError):
                    active_error.kind = "recovery_required"
                    active_error.args = (f"{active_error.args[0]}；{message}",)
                else:
                    primary = (
                        f"{type(active_error).__name__}: {active_error}"
                        if active_error is not None
                        else "未知原子写入错误"
                    )
                    cleanup_error = AtomicFileError(
                        "recovery_required",
                        f"原子写入先因 {primary} 失败；{message}",
                        recovery_paths=tuple(
                            dict.fromkeys(
                                (*remaining, *_cleanup_error_paths(cleanup_errors))
                            )
                        ),
                    )
        if postcheck_fd >= 0:
            os.close(postcheck_fd)
        if commit_fd >= 0:
            os.close(commit_fd)
        os.close(directory_fd)
        if cleanup_error is not None:
            if active_error is not None:
                raise cleanup_error from active_error
            raise cleanup_error


def replace_from_staged(
    destination: Path,
    staged: Path,
    *,
    expected_path: Path,
    expected_mode: int | None = None,
) -> None:
    destination = _normalise_destination(destination, allow_missing=True)
    if not staged.is_absolute():
        staged = Path.cwd() / staged
    if staged.parent != destination.parent:
        raise AtomicFileError("validation", "暂存文件必须与目标位于同一目录")
    expected = _snapshot_path(expected_path, label="预期版本")
    mode = expected.mode if expected_mode is None else expected_mode

    directory_fd = _open_directory_without_symlinks(destination.parent)
    try:
        _ensure_no_recovery_state(directory_fd, destination.parent, destination.name)
        staged_snapshot = _snapshot_bound_at(
            directory_fd,
            parent=destination.parent,
            name=staged.name,
            display_path=staged,
        )
        current = _snapshot_bound_at(
            directory_fd,
            parent=destination.parent,
            name=destination.name,
            display_path=destination,
            missing_kind="concurrent_update",
        )
        if current.data != expected.data or current.mode != mode:
            raise AtomicFileError(
                "concurrent_update",
                f"目标内容或权限与预期版本不一致: {destination}",
            )
        _replace_staged_at(
            directory_fd,
            parent=destination.parent,
            destination_name=destination.name,
            staged_name=staged.name,
            staged_identity=_identity_from_snapshot(staged_snapshot),
            expected=current,
        )
    finally:
        os.close(directory_fd)


def _create_from_staged_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    staged_name: str,
    staged_identity: EntryIdentity,
) -> None:
    destination_name = _validate_entry_name(destination_name, label="Host 配置名")
    staged_name = _validate_entry_name(staged_name, label="Host 暂存文件名")
    destination = parent / destination_name
    staged = parent / staged_name
    _assert_directory_is_current(directory_fd, parent)
    _ensure_no_recovery_state(
        directory_fd,
        parent,
        destination_name,
        allowed_names=(staged_name,),
    )
    staged_claim_name, staged_snapshot = _claim_staged_entry_at(
        directory_fd,
        parent=parent,
        destination_name=destination_name,
        staged_name=staged_name,
        staged_identity=staged_identity,
    )
    staged_claim_path = parent / staged_claim_name
    try:
        _rename_noreplace_bound(
            directory_fd,
            staged_claim_name,
            destination_name,
            parent=parent,
            recovery_paths=(destination, staged_claim_path),
            label="原子创建目标",
        )
    except OSError as exc:
        _restore_claim(
            directory_fd,
            staged_claim_name,
            staged_name,
            parent=parent,
        )
        if exc.errno == errno.EEXIST:
            raise AtomicFileError(
                "concurrent_update",
                f"目标在创建期间被并发创建，未覆盖: {destination}",
            ) from exc
        raise AtomicFileError("validation", f"无法原子创建目标: {destination}") from exc
    except AtomicFileError as exc:
        if exc.kind == "recovery_required":
            _restore_claim_if_identity(
                directory_fd,
                destination_name,
                staged_name,
                parent=parent,
                expected_identity=staged_identity,
                require_current_parent=False,
            )
            raise AtomicFileError(
                "concurrent_update",
                "原子创建期间目录被改向，自有命名空间变更已补偿",
            ) from exc
        _restore_claim(
            directory_fd,
            staged_claim_name,
            staged_name,
            parent=parent,
        )
        raise
    _fsync_directory(
        directory_fd,
        message=f"目标已创建但目录持久化失败，请核对后再继续: {destination}",
        recovery_paths=(destination,),
    )
    try:
        installed = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=destination_name,
            display_path=destination,
            missing_kind="concurrent_update",
        )
    except AtomicFileError as exc:
        paths = _existing_paths_at(
            directory_fd,
            parent,
            destination_name,
        )
        if paths:
            message = (
                "原子创建后无法校验正式路径；当前路径仍存在，"
                f"可能已被并发替换或变为不可接受的文件类型: {destination}"
            )
        else:
            message = (
                "原子创建后无法校验正式路径；正式路径可能已被并发删除"
                f"或变为不可访问，当前无可确认的恢复文件: {destination}"
            )
        raise AtomicFileError(
            "recovery_required",
            message,
            recovery_paths=paths,
        ) from exc
    if not _same_file(installed, staged_snapshot):
        paths = _existing_paths_at(
            directory_fd,
            parent,
            destination_name,
        )
        if paths:
            message = f"原子创建后目标又被并发修改，当前正式路径已保留: {destination}"
        else:
            message = (
                "原子创建后目标又被并发修改，随后正式路径消失；"
                f"当前无可确认的恢复文件: {destination}"
            )
        raise AtomicFileError(
            "recovery_required",
            message,
            recovery_paths=paths,
        )

    if staged in _existing_paths_at(directory_fd, parent, staged_name):
        raise AtomicFileError(
            "recovery_required",
            "Host 暂存文件公开名称在 claim 后被并发复用；foreign 文件未安装或删除",
            recovery_paths=(destination, staged),
        )


def create_from_staged(destination: Path, staged: Path) -> None:
    destination = _normalise_destination(destination, allow_missing=True)
    if not staged.is_absolute():
        staged = Path.cwd() / staged
    if staged.parent != destination.parent:
        raise AtomicFileError("validation", "暂存文件必须与目标位于同一目录")

    directory_fd = _open_directory_without_symlinks(destination.parent)
    try:
        staged_snapshot = _snapshot_bound_at(
            directory_fd,
            parent=destination.parent,
            name=staged.name,
            display_path=staged,
        )
        _create_from_staged_at(
            directory_fd,
            parent=destination.parent,
            destination_name=destination.name,
            staged_name=staged.name,
            staged_identity=_identity_from_snapshot(staged_snapshot),
        )
    finally:
        os.close(directory_fd)


def _delete_if_unchanged_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    expected: _Snapshot,
    expected_mode: int,
    destination_identity: EntryIdentity | None = None,
) -> None:
    destination_name = _validate_entry_name(destination_name, label="Host 配置名")
    destination = parent / destination_name
    quarantine_name: str | None = None
    try:
        _ensure_no_recovery_state(directory_fd, parent, destination_name)
        current = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=destination_name,
            display_path=destination,
            missing_kind="concurrent_update",
        )
        if destination_identity is not None:
            _assert_identity(
                current,
                destination_identity,
                path=destination,
                label="待删除目标",
            )
        if current.data != expected.data or current.mode != expected_mode:
            raise AtomicFileError(
                "concurrent_update",
                f"待删除目标内容或权限已变化，未删除: {destination}",
            )
        quarantine_name = _unique_quarantine_name(directory_fd, destination_name)
        try:
            _rename_noreplace_bound(
                directory_fd,
                destination_name,
                quarantine_name,
                parent=parent,
                recovery_paths=(destination, parent / quarantine_name),
                label="原子删除 claim",
            )
        except FileNotFoundError as exc:
            raise AtomicFileError(
                "concurrent_update",
                f"待删除目标在 claim 前已被删除: {destination}",
            ) from exc
        except AtomicFileError as exc:
            if exc.kind != "recovery_required":
                raise
            _restore_claim_if_identity(
                directory_fd,
                quarantine_name,
                destination_name,
                parent=parent,
                expected_identity=_identity_from_snapshot(current),
                require_current_parent=False,
            )
            quarantine_name = None
            raise AtomicFileError(
                "concurrent_update",
                "原子删除 claim 期间目录被改向，自有命名空间变更已补偿",
            ) from exc
        quarantine_path = parent / quarantine_name
        _fsync_directory(
            directory_fd,
            message=(
                "删除 claim 已发生但目录持久化失败；正式路径当前可能缺失，"
                f"原件位于: {quarantine_path}"
            ),
            recovery_paths=(quarantine_path,),
        )
        try:
            claimed = _snapshot_bound_at(
                directory_fd,
                parent=parent,
                name=quarantine_name,
                display_path=quarantine_path,
            )
        except AtomicFileError as exc:
            _restore_claim(
                directory_fd,
                quarantine_name,
                destination_name,
                parent=parent,
            )
            quarantine_name = None
            raise AtomicFileError(
                "concurrent_update",
                f"删除 claim 后发现目标已变为不可接受的文件类型，已恢复并发版本: {destination}",
            ) from exc
        if not _same_file(claimed, current):
            _restore_claim(
                directory_fd,
                quarantine_name,
                destination_name,
                parent=parent,
            )
            quarantine_name = None
            raise AtomicFileError(
                "concurrent_update",
                f"待删除目标在 claim 前已变化，未删除: {destination}",
            )
        unlink_entry_at(
            directory_fd,
            parent=parent,
            name=quarantine_name,
            expected_device=claimed.device,
            expected_inode=claimed.inode,
        )
        quarantine_name = None
        _assert_directory_is_current(directory_fd, parent)
    except OSError as exc:
        raise AtomicFileError("validation", f"无法原子删除目标: {destination}") from exc


def delete_if_unchanged(
    destination: Path,
    *,
    expected_path: Path,
    expected_mode: int | None = None,
) -> None:
    destination = _normalise_destination(destination, allow_missing=True)
    expected = _snapshot_path(expected_path, label="预期删除版本")
    mode = expected.mode if expected_mode is None else expected_mode

    directory_fd = _open_directory_without_symlinks(destination.parent)
    try:
        _delete_if_unchanged_at(
            directory_fd,
            parent=destination.parent,
            destination_name=destination.name,
            expected=expected,
            expected_mode=mode,
        )
    finally:
        os.close(directory_fd)


def _expected_snapshot_at_or_path(
    directory_fd: int,
    *,
    parent: Path,
    expected_name: str | None,
    expected_path: Path | None,
    expected_entry_device: int | None = None,
    expected_entry_inode: int | None = None,
) -> _Snapshot:
    if (expected_name is None) == (expected_path is None):
        raise AtomicFileError(
            "validation",
            "必须且只能提供 expected-name 或 expected-path 之一",
        )
    if expected_name is not None:
        if expected_entry_device is None or expected_entry_inode is None:
            raise AtomicFileError(
                "validation",
                "expected-name 必须同时提供 expected-entry-device 与 expected-entry-inode",
            )
        expected_name = _validate_entry_name(expected_name, label="预期文件名")
        snapshot = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=expected_name,
            display_path=parent / expected_name,
        )
        _assert_identity(
            snapshot,
            _entry_identity(expected_entry_device, expected_entry_inode),
            path=parent / expected_name,
            label="预期文件",
        )
        return snapshot
    if expected_entry_device is not None or expected_entry_inode is not None:
        raise AtomicFileError(
            "validation",
            "expected-path 不接受 expected-entry-device/expected-entry-inode",
        )
    assert expected_path is not None
    return _snapshot_path(expected_path, label="预期版本")


def inspect_entry_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    expected_name: str | None,
    expected_path: Path | None,
    expected_mode: int,
    expected_entry_device: int | None = None,
    expected_entry_inode: int | None = None,
    destination_device: int | None = None,
    destination_inode: int | None = None,
) -> str:
    destination_name = _validate_entry_name(destination_name, label="Host 配置名")
    destination_identity = _optional_entry_identity(
        destination_device,
        destination_inode,
        label="正式 Host 配置身份",
    )
    expected = _expected_snapshot_at_or_path(
        directory_fd,
        parent=parent,
        expected_name=expected_name,
        expected_path=expected_path,
        expected_entry_device=expected_entry_device,
        expected_entry_inode=expected_entry_inode,
    )
    try:
        current = _snapshot_bound_at(
            directory_fd,
            parent=parent,
            name=destination_name,
            display_path=parent / destination_name,
            missing_kind="missing",
        )
    except AtomicFileError as exc:
        if exc.kind == "missing":
            _assert_directory_is_current(directory_fd, parent)
            return "missing"
        raise
    if (
        destination_identity is not None
        and _identity_from_snapshot(current) != destination_identity
    ):
        _assert_directory_is_current(directory_fd, parent)
        return "different"
    if current.data == expected.data and current.mode == expected_mode:
        _assert_directory_is_current(directory_fd, parent)
        return "same"
    _assert_directory_is_current(directory_fd, parent)
    return "different"


def replace_entry_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    staged_name: str,
    staged_device: int,
    staged_inode: int,
    expected_name: str | None,
    expected_path: Path | None,
    expected_mode: int,
    expected_entry_device: int | None = None,
    expected_entry_inode: int | None = None,
    destination_device: int | None = None,
    destination_inode: int | None = None,
) -> None:
    destination_name = _validate_entry_name(destination_name, label="Host 配置名")
    staged_name = _validate_entry_name(staged_name, label="Host 暂存文件名")
    destination_identity = _optional_entry_identity(
        destination_device,
        destination_inode,
        label="正式 Host 配置身份",
    )
    expected = _expected_snapshot_at_or_path(
        directory_fd,
        parent=parent,
        expected_name=expected_name,
        expected_path=expected_path,
        expected_entry_device=expected_entry_device,
        expected_entry_inode=expected_entry_inode,
    )
    current = _snapshot_bound_at(
        directory_fd,
        parent=parent,
        name=destination_name,
        display_path=parent / destination_name,
        missing_kind="concurrent_update",
    )
    if destination_identity is not None:
        _assert_identity(
            current,
            destination_identity,
            path=parent / destination_name,
            label="正式 Host 配置",
        )
    if current.data != expected.data or current.mode != expected_mode:
        raise AtomicFileError(
            "concurrent_update",
            f"目标内容或权限与预期版本不一致: {parent / destination_name}",
        )
    _replace_staged_at(
        directory_fd,
        parent=parent,
        destination_name=destination_name,
        staged_name=staged_name,
        staged_identity=_entry_identity(staged_device, staged_inode),
        expected=current,
    )


def create_entry_at(
    directory_fd: int,
    *,
    parent: Path,
    destination_name: str,
    staged_name: str,
    staged_device: int,
    staged_inode: int,
) -> None:
    _create_from_staged_at(
        directory_fd,
        parent=parent,
        destination_name=destination_name,
        staged_name=staged_name,
        staged_identity=_entry_identity(staged_device, staged_inode),
    )


def _parse_mode(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        mode = int(value, 8)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("mode 必须是八进制权限") from exc
    if mode < 0 or mode > 0o7777:
        raise argparse.ArgumentTypeError("mode 超出合法权限范围")
    return mode


def _add_bound_directory_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--directory-fd", type=int, required=True)
    parser.add_argument("--expected-device", type=int, required=True)
    parser.add_argument("--expected-inode", type=int, required=True)
    parser.add_argument("--parent-display", required=True)


def _directory_fd_from_args(args: argparse.Namespace) -> tuple[int, Path]:
    parent = _normalise_absolute_lexical_path(Path(args.parent_display))
    directory_fd = _bound_directory_fd(
        args.directory_fd,
        expected_device=args.expected_device,
        expected_inode=args.expected_inode,
        parent=parent,
    )
    current_fd = _open_current_bound_directory(
        parent,
        expected_device=args.expected_device,
        expected_inode=args.expected_inode,
    )
    try:
        os.dup2(current_fd, directory_fd)
    finally:
        os.close(current_fd)
    return directory_fd, parent


def _add_expected_source_arguments(parser: argparse.ArgumentParser) -> None:
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--expected-name")
    group.add_argument("--expected-path")


def _add_expected_entry_identity_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--expected-entry-device", type=int)
    parser.add_argument("--expected-entry-inode", type=int)


def _add_destination_identity_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--destination-device", type=int)
    parser.add_argument("--destination-inode", type=int)


def _add_staged_identity_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--staged-device", type=int, required=True)
    parser.add_argument("--staged-inode", type=int, required=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PMAI 原子文件 CAS")
    subparsers = parser.add_subparsers(dest="command", required=True)

    replace_parser = subparsers.add_parser("replace")
    replace_parser.add_argument("--destination", required=True)
    replace_parser.add_argument("--staged", required=True)
    replace_parser.add_argument("--expected", required=True)
    replace_parser.add_argument("--expected-mode", type=_parse_mode)

    create_parser = subparsers.add_parser("create")
    create_parser.add_argument("--destination", required=True)
    create_parser.add_argument("--staged", required=True)

    delete_parser = subparsers.add_parser("delete")
    delete_parser.add_argument("--destination", required=True)
    delete_parser.add_argument("--expected", required=True)
    delete_parser.add_argument("--expected-mode", type=_parse_mode)

    recovery_parser = subparsers.add_parser("check-recovery")
    recovery_parser.add_argument("--destination", required=True)

    ensure_directory_parser = subparsers.add_parser("ensure-directory")
    ensure_directory_parser.add_argument("--root", required=True)
    ensure_directory_parser.add_argument("--directory", required=True)

    bind_directory_parser = subparsers.add_parser("bind-directory")
    bind_directory_parser.add_argument("--directory", required=True)
    bind_directory_parser.add_argument("--directory-fd", type=int, required=True)

    snapshot_at_parser = subparsers.add_parser("snapshot-at")
    _add_bound_directory_arguments(snapshot_at_parser)
    snapshot_at_parser.add_argument("--destination-name", required=True)
    snapshot_at_parser.add_argument("--output", required=True)

    prepare_at_parser = subparsers.add_parser("prepare-at")
    _add_bound_directory_arguments(prepare_at_parser)
    prepare_at_parser.add_argument("--destination-name", required=True)
    prepare_at_parser.add_argument("--rendered", required=True)
    prepare_at_parser.add_argument("--expected")
    prepare_at_parser.add_argument("--expected-mode", type=_parse_mode, required=True)

    inspect_at_parser = subparsers.add_parser("inspect-at")
    _add_bound_directory_arguments(inspect_at_parser)
    inspect_at_parser.add_argument("--destination-name", required=True)
    _add_expected_source_arguments(inspect_at_parser)
    _add_expected_entry_identity_arguments(inspect_at_parser)
    _add_destination_identity_arguments(inspect_at_parser)
    inspect_at_parser.add_argument("--expected-mode", type=_parse_mode, required=True)

    replace_at_parser = subparsers.add_parser("replace-at")
    _add_bound_directory_arguments(replace_at_parser)
    replace_at_parser.add_argument("--destination-name", required=True)
    replace_at_parser.add_argument("--staged-name", required=True)
    _add_staged_identity_arguments(replace_at_parser)
    _add_expected_source_arguments(replace_at_parser)
    _add_expected_entry_identity_arguments(replace_at_parser)
    _add_destination_identity_arguments(replace_at_parser)
    replace_at_parser.add_argument("--expected-mode", type=_parse_mode, required=True)

    create_at_parser = subparsers.add_parser("create-at")
    _add_bound_directory_arguments(create_at_parser)
    create_at_parser.add_argument("--destination-name", required=True)
    create_at_parser.add_argument("--staged-name", required=True)
    _add_staged_identity_arguments(create_at_parser)

    delete_at_parser = subparsers.add_parser("delete-at")
    _add_bound_directory_arguments(delete_at_parser)
    delete_at_parser.add_argument("--destination-name", required=True)
    _add_expected_source_arguments(delete_at_parser)
    _add_expected_entry_identity_arguments(delete_at_parser)
    _add_destination_identity_arguments(delete_at_parser)
    delete_at_parser.add_argument("--expected-mode", type=_parse_mode, required=True)

    recovery_at_parser = subparsers.add_parser("check-recovery-at")
    _add_bound_directory_arguments(recovery_at_parser)
    recovery_at_parser.add_argument("--destination-name", required=True)

    unlink_at_parser = subparsers.add_parser("unlink-at")
    _add_bound_directory_arguments(unlink_at_parser)
    unlink_at_parser.add_argument("--name", required=True)
    unlink_at_parser.add_argument("--entry-device", type=int, required=True)
    unlink_at_parser.add_argument("--entry-inode", type=int, required=True)
    unlink_at_parser.add_argument("--ignore-missing", action="store_true")

    run_locked_parser = subparsers.add_parser("run-locked")
    run_locked_parser.add_argument("--lock-path", required=True)
    run_locked_parser.add_argument("locked_command", nargs=argparse.REMAINDER)

    lock_status_parser = subparsers.add_parser("lock-status")
    lock_status_parser.add_argument("--lock-path", required=True)

    verify_lock_parser = subparsers.add_parser("verify-lock-fd")
    verify_lock_parser.add_argument("--lock-path", required=True)
    verify_lock_parser.add_argument("--lock-fd", type=int, required=True)

    args = parser.parse_args(argv)
    try:
        if args.command == "replace":
            replace_from_staged(
                Path(args.destination),
                Path(args.staged),
                expected_path=Path(args.expected),
                expected_mode=args.expected_mode,
            )
        elif args.command == "create":
            create_from_staged(Path(args.destination), Path(args.staged))
        elif args.command == "delete":
            delete_if_unchanged(
                Path(args.destination),
                expected_path=Path(args.expected),
                expected_mode=args.expected_mode,
            )
        elif args.command == "check-recovery":
            ensure_no_recovery_state(Path(args.destination))
        elif args.command == "ensure-directory":
            ensure_directory_beneath(Path(args.root), Path(args.directory))
        elif args.command == "bind-directory":
            device, inode = bind_directory_fd(
                Path(args.directory),
                args.directory_fd,
            )
            print(f"{device}\t{inode}")
        elif args.command == "snapshot-at":
            directory_fd, parent = _directory_fd_from_args(args)
            exists, mode = snapshot_entry_at(
                directory_fd,
                parent=parent,
                destination_name=args.destination_name,
                output=Path(args.output),
            )
            print(f"{1 if exists else 0}\t{mode:o}")
        elif args.command == "prepare-at":
            directory_fd, parent = _directory_fd_from_args(args)
            prepared = prepare_update_at(
                directory_fd,
                parent=parent,
                destination_name=args.destination_name,
                rendered_path=Path(args.rendered),
                expected_path=Path(args.expected) if args.expected else None,
                expected_mode=args.expected_mode,
            )
            if prepared.original_identity is None:
                original_fields = ("-", "-")
            else:
                original_fields = (
                    str(prepared.original_identity.device),
                    str(prepared.original_identity.inode),
                )
            if prepared.backup_identity is None:
                backup_fields = ("-", "-", "-")
            else:
                backup_fields = (
                    prepared.backup_name or "-",
                    str(prepared.backup_identity.device),
                    str(prepared.backup_identity.inode),
                )
            print(
                "\t".join(
                    (
                        *original_fields,
                        *backup_fields,
                        prepared.stage_name,
                        str(prepared.stage_identity.device),
                        str(prepared.stage_identity.inode),
                    )
                )
            )
        elif args.command == "inspect-at":
            directory_fd, parent = _directory_fd_from_args(args)
            print(
                inspect_entry_at(
                    directory_fd,
                    parent=parent,
                    destination_name=args.destination_name,
                    expected_name=args.expected_name,
                    expected_path=(
                        Path(args.expected_path) if args.expected_path else None
                    ),
                    expected_mode=args.expected_mode,
                    expected_entry_device=args.expected_entry_device,
                    expected_entry_inode=args.expected_entry_inode,
                    destination_device=args.destination_device,
                    destination_inode=args.destination_inode,
                )
            )
        elif args.command == "replace-at":
            directory_fd, parent = _directory_fd_from_args(args)
            replace_entry_at(
                directory_fd,
                parent=parent,
                destination_name=args.destination_name,
                staged_name=args.staged_name,
                staged_device=args.staged_device,
                staged_inode=args.staged_inode,
                expected_name=args.expected_name,
                expected_path=Path(args.expected_path) if args.expected_path else None,
                expected_mode=args.expected_mode,
                expected_entry_device=args.expected_entry_device,
                expected_entry_inode=args.expected_entry_inode,
                destination_device=args.destination_device,
                destination_inode=args.destination_inode,
            )
        elif args.command == "create-at":
            directory_fd, parent = _directory_fd_from_args(args)
            create_entry_at(
                directory_fd,
                parent=parent,
                destination_name=args.destination_name,
                staged_name=args.staged_name,
                staged_device=args.staged_device,
                staged_inode=args.staged_inode,
            )
        elif args.command == "delete-at":
            directory_fd, parent = _directory_fd_from_args(args)
            expected = _expected_snapshot_at_or_path(
                directory_fd,
                parent=parent,
                expected_name=args.expected_name,
                expected_path=Path(args.expected_path) if args.expected_path else None,
                expected_entry_device=args.expected_entry_device,
                expected_entry_inode=args.expected_entry_inode,
            )
            _delete_if_unchanged_at(
                directory_fd,
                parent=parent,
                destination_name=args.destination_name,
                expected=expected,
                expected_mode=args.expected_mode,
                destination_identity=_optional_entry_identity(
                    args.destination_device,
                    args.destination_inode,
                    label="正式 Host 配置身份",
                ),
            )
        elif args.command == "check-recovery-at":
            directory_fd, parent = _directory_fd_from_args(args)
            destination_name = _validate_entry_name(
                args.destination_name,
                label="Host 配置名",
            )
            ensure_no_recovery_state_at(
                directory_fd,
                parent=parent,
                destination_name=destination_name,
            )
        elif args.command == "unlink-at":
            directory_fd, parent = _directory_fd_from_args(args)
            unlink_entry_at(
                directory_fd,
                parent=parent,
                name=args.name,
                expected_device=args.entry_device,
                expected_inode=args.entry_inode,
                ignore_missing=args.ignore_missing,
            )
        elif args.command == "lock-status":
            print(cooperative_lock_status(Path(args.lock_path)))
        elif args.command == "verify-lock-fd":
            verify_inherited_lock(Path(args.lock_path), args.lock_fd)
        else:
            locked_command = list(args.locked_command)
            if locked_command[:1] == ["--"]:
                locked_command = locked_command[1:]
            return _return_or_reraise_child_signal(
                run_locked(Path(args.lock_path), locked_command)
            )
    except AtomicFileError as exc:
        print(f"{exc.kind}: {exc}", file=sys.stderr)
        return 3 if exc.kind in {"concurrent_update", "recovery_required"} else 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
