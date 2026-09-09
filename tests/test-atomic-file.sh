#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ATOMIC_FILE="$REPO_ROOT/scripts/_lib/atomic_file.py"
SUITE_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pmai-atomic-file.XXXXXX")"
SUITE_TMP_ROOT="$(cd "$SUITE_TMP_ROOT" && pwd -P)"
export TMPDIR="$SUITE_TMP_ROOT"
trap 'rm -rf "$SUITE_TMP_ROOT"' EXIT

test_unsupported_syscalls_fail_closed() {
  start_test "atomic-file: unsupported no-replace syscalls fail closed"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import ctypes
import errno
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class MissingSymbolLib:
    pass


class FailingRename:
    def __init__(self, error_number):
        self.error_number = error_number
        self.argtypes = None
        self.restype = None

    def __call__(self, *_args):
        ctypes.set_errno(self.error_number)
        return -1


class FailingLib:
    def __init__(self, error_number):
        function = FailingRename(error_number)
        self.renameatx_np = function
        self.renameat2 = function


root = Path(tempfile.mkdtemp()).resolve()
source = root / "source"
destination = root / "destination"
source.write_text("source", encoding="utf-8")
destination.write_text("destination", encoding="utf-8")
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_cdll = module.ctypes.CDLL
try:
    module.ctypes.CDLL = lambda *_args, **_kwargs: MissingSymbolLib()
    try:
        module._rename_noreplace(directory_fd, source.name, destination.name)
    except module.AtomicFileError as exc:
        assert exc.kind == "unsupported", (exc.kind, str(exc))
    else:
        raise AssertionError("missing syscall symbol unexpectedly fell back")

    for error_number in (errno.ENOSYS, errno.EOPNOTSUPP, errno.EINVAL):
        module.ctypes.CDLL = lambda *_args, _errno=error_number, **_kwargs: FailingLib(_errno)
        try:
            module._rename_noreplace(directory_fd, source.name, destination.name)
        except OSError as exc:
            assert exc.errno == error_number, (exc.errno, error_number)
        else:
            raise AssertionError(f"syscall errno {error_number} unexpectedly fell back")
        assert source.read_text(encoding="utf-8") == "source"
        assert destination.read_text(encoding="utf-8") == "destination"
finally:
    module.ctypes.CDLL = original_cdll
    os.close(directory_fd)
PY
  then
    pass_test
  else
    _fail "unsupported syscall path did not fail closed"
  fi
}

test_claim_fsync_failure_preserves_recovery_paths() {
  start_test "atomic-file: claim fsync failure preserves original and staged paths"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
destination = root / "body.md"
destination.write_text("old", encoding="utf-8")
original_fsync = module.os.fsync
calls = 0


def failing_fsync(fd):
    global calls
    calls += 1
    if calls == 4:
        raise OSError(5, "injected directory fsync failure")
    return original_fsync(fd)


module.os.fsync = failing_fsync
try:
    module.replace_text_if_unchanged(
        destination,
        "new",
        expected_text="old",
        require_canonical_path=True,
    )
except module.AtomicFileError as exc:
    assert exc.kind == "recovery_required", (exc.kind, str(exc))
    assert "持久化失败" in str(exc)
    existing = [item for item in exc.recovery_paths if item.exists()]
    assert len(existing) == 2, (exc.recovery_paths, existing)
    assert sorted(item.read_text(encoding="utf-8") for item in existing) == ["new", "old"]
else:
    raise AssertionError("claim fsync failure unexpectedly succeeded")
finally:
    module.os.fsync = original_fsync

assert not destination.exists()
assert len(list(root.glob(".body.md.pmai-cas-original-*"))) == 1
assert len(list(root.glob(".body.md.pmai-stage-claim-*"))) == 1
PY
  then
    pass_test
  else
    _fail "claim fsync failure hid or deleted recovery data"
  fi
}

test_claimed_special_files_restore_without_blocking() {
  start_test "atomic-file: claimed symlink and FIFO races restore without blocking"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import stat
import sys
import tempfile
import time
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
destination = root / "body.md"
symlink_target = root / "target.md"
symlink_target.write_text("target", encoding="utf-8")
original_rename = module._rename_noreplace


def run(kind):
    destination.unlink(missing_ok=True)
    destination.write_text("old", encoding="utf-8")
    calls = 0

    def racing_rename(directory_fd, source, target):
        nonlocal calls
        calls += 1
        if calls == 1:
            destination.unlink()
            if kind == "symlink":
                destination.symlink_to(symlink_target)
            else:
                os.mkfifo(destination)
        original_rename(directory_fd, source, target)

    module._rename_noreplace = racing_rename
    started = time.monotonic()
    try:
        module.replace_text_if_unchanged(
            destination,
            "new",
            expected_text="old",
            require_canonical_path=True,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (kind, exc.kind, str(exc))
    else:
        raise AssertionError(f"{kind} race unexpectedly succeeded")
    finally:
        module._rename_noreplace = original_rename
    assert time.monotonic() - started < 1.0, kind
    mode = destination.lstat().st_mode
    assert stat.S_ISLNK(mode) if kind == "symlink" else stat.S_ISFIFO(mode)
    assert not list(root.glob(".body.md.pmai-cas-original-*")), kind
    assert not list(root.glob(".body.md.pmai-cas-stage-*")), kind
    assert not list(root.glob(".body.md.pmai-stage-claim-*")), kind


run("symlink")
destination.unlink()
run("fifo")
destination.unlink()
assert symlink_target.read_text(encoding="utf-8") == "target"
PY
  then
    pass_test
  else
    _fail "special-file race blocked or left the formal path missing"
  fi
}

test_external_stages_are_fsynced_before_rename() {
  start_test "atomic-file: external replace/create stages fsync before namespace commit"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
original_fsync = module.os.fsync


def failing_fsync(_fd):
    raise OSError(5, "injected staged-file fsync failure")


def expect_validation(call, destination, staged):
    module.os.fsync = failing_fsync
    try:
        call()
    except module.AtomicFileError as exc:
        assert exc.kind == "validation", (exc.kind, str(exc))
        assert "暂存文件持久化失败" in str(exc), str(exc)
    else:
        raise AssertionError("unsynced external stage unexpectedly committed")
    finally:
        module.os.fsync = original_fsync
    assert staged.exists()
    assert not list(root.glob(f".{destination.name}.pmai-cas-original-*"))


destination = root / "replace.json"
expected = root / "expected.json"
staged = root / "replace.stage"
destination.write_text("old", encoding="utf-8")
expected.write_text("old", encoding="utf-8")
staged.write_text("new", encoding="utf-8")
expect_validation(
    lambda: module.replace_from_staged(destination, staged, expected_path=expected),
    destination,
    staged,
)
assert destination.read_text(encoding="utf-8") == "old"

created = root / "created.json"
create_stage = root / "create.stage"
create_stage.write_text("new", encoding="utf-8")
expect_validation(
    lambda: module.create_from_staged(created, create_stage),
    created,
    create_stage,
)
assert not created.exists()
PY
  then
    pass_test
  else
    _fail "external stage was renamed without a successful file fsync"
  fi
}

test_post_install_missing_destination_reports_exact_recovery() {
  start_test "atomic-file: post-install deletion reports only retained recovery files"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
destination = root / "body.md"
destination.write_text("old", encoding="utf-8")
original_snapshot = module._snapshot_at
destination_snapshots = 0


def racing_snapshot(directory_fd, name, **kwargs):
    global destination_snapshots
    if name == destination.name:
        destination_snapshots += 1
        if destination_snapshots == 2:
            destination.unlink()
    return original_snapshot(directory_fd, name, **kwargs)


module._snapshot_at = racing_snapshot
try:
    module.replace_text_if_unchanged(
        destination,
        "new",
        expected_text="old",
        require_canonical_path=True,
    )
except module.AtomicFileError as exc:
    assert exc.kind == "recovery_required", (exc.kind, str(exc))
    assert "正式路径可能已被删除" in str(exc), str(exc)
    assert "当前目标与原件均已保留" not in str(exc), str(exc)
    assert destination not in exc.recovery_paths, exc.recovery_paths
    assert len(exc.recovery_paths) == 1, exc.recovery_paths
    recovery = exc.recovery_paths[0]
    assert recovery.exists(), recovery
    assert recovery.read_text(encoding="utf-8") == "old"
else:
    raise AssertionError("post-install destination deletion unexpectedly succeeded")
finally:
    module._snapshot_at = original_snapshot

assert not destination.exists()
assert not list(root.glob(".body.md.pmai-cas-stage-*"))
assert not list(root.glob(".body.md.pmai-stage-claim-*"))
PY
  then
    pass_test
  else
    _fail "post-install deletion claimed a missing destination was recoverable"
  fi
}

test_replace_postcheck_reports_existing_paths_only() {
  start_test "atomic-file: replace post-check reports only paths that still exist"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
original_snapshot = module._snapshot_at
original_same = module._same_file

special = root / "special.md"
target = root / "target.md"
special.write_text("old", encoding="utf-8")
target.write_text("target", encoding="utf-8")
special_reads = 0


def replace_with_symlink(directory_fd, name, **kwargs):
    global special_reads
    if name == special.name:
        special_reads += 1
        if special_reads == 2:
            special.unlink()
            special.symlink_to(target)
    return original_snapshot(directory_fd, name, **kwargs)


module._snapshot_at = replace_with_symlink
try:
    module.replace_text_if_unchanged(special, "new", expected_text="old")
except module.AtomicFileError as exc:
    assert exc.kind == "recovery_required", (exc.kind, str(exc))
    assert "当前正式路径仍存在" in str(exc), str(exc)
    assert special in exc.recovery_paths, exc.recovery_paths
    assert len(exc.recovery_paths) == 2, exc.recovery_paths
    quarantine = next(item for item in exc.recovery_paths if item != special)
    assert special.is_symlink()
    assert quarantine.exists(), quarantine
    assert quarantine.read_text(encoding="utf-8") == "old"
else:
    raise AssertionError("post-install symlink unexpectedly passed validation")
finally:
    module._snapshot_at = original_snapshot

missing = root / "missing.md"
missing.write_text("old", encoding="utf-8")
same_calls = 0


def remove_after_mismatch(left, right):
    global same_calls
    same_calls += 1
    if same_calls == 2:
        missing.unlink()
        return False
    return original_same(left, right)


module._same_file = remove_after_mismatch
try:
    module.replace_text_if_unchanged(missing, "new", expected_text="old")
except module.AtomicFileError as exc:
    assert exc.kind == "recovery_required", (exc.kind, str(exc))
    assert "随后正式路径消失" in str(exc), str(exc)
    assert missing not in exc.recovery_paths, exc.recovery_paths
    assert len(exc.recovery_paths) == 1, exc.recovery_paths
    quarantine = exc.recovery_paths[0]
    assert quarantine.exists(), quarantine
    assert quarantine.read_text(encoding="utf-8") == "old"
else:
    raise AssertionError("post-install mismatch deletion unexpectedly succeeded")
finally:
    module._same_file = original_same

assert not missing.exists()
assert target.read_text(encoding="utf-8") == "target"
PY
  then
    pass_test
  else
    _fail "replace post-check recovery paths did not match the live namespace"
  fi
}

test_cleanup_failure_preserves_primary_error_and_stage() {
  start_test "atomic-file: cleanup failure preserves primary error and staged recovery"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import errno
import importlib.util
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
destination = root / "body.md"
destination.write_text("old", encoding="utf-8")
original_replace = module._replace_staged_at
original_unlink = module.os.unlink


def fail_replace(*_args, **_kwargs):
    raise module.AtomicFileError("concurrent_update", "PRIMARY")


def fail_stage_cleanup(name, *args, **kwargs):
    if str(name).startswith(f".{destination.name}.pmai-cas-stage-"):
        raise OSError(errno.EIO, "injected cleanup failure")
    return original_unlink(name, *args, **kwargs)


module._replace_staged_at = fail_replace
module.os.unlink = fail_stage_cleanup
try:
    module.replace_text_if_unchanged(
        destination,
        "new",
        expected_text="old",
        require_canonical_path=True,
    )
except module.AtomicFileError as exc:
    assert exc.kind == "recovery_required", (exc.kind, str(exc))
    assert "PRIMARY" in str(exc), str(exc)
    assert "暂存文件清理失败" in str(exc), str(exc)
    assert len(exc.recovery_paths) == 1, exc.recovery_paths
    stage = exc.recovery_paths[0]
    assert stage.exists(), stage
    assert stage.read_text(encoding="utf-8") == "new"
else:
    raise AssertionError("cleanup failure masked or lost the primary error")
finally:
    module._replace_staged_at = original_replace
    module.os.unlink = original_unlink

assert destination.read_text(encoding="utf-8") == "old"
PY
  then
    pass_test
  else
    _fail "cleanup failure did not preserve the primary error and staged recovery"
  fi
}

test_prepare_cleanup_reports_only_live_recovery_paths() {
  start_test "atomic-file: prepare cleanup preserves primary error and reports live paths only"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import errno
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def run_case(*, fail_cleanup: bool) -> None:
    root = Path(tempfile.mkdtemp()).resolve()
    destination = root / "hooks.json"
    expected = root / "expected.json"
    rendered = root / "rendered.json"
    destination.write_text("old", encoding="utf-8")
    expected.write_text("old", encoding="utf-8")
    rendered.write_text("new", encoding="utf-8")
    directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    original_create = module._create_regular_at
    original_unlink = module.os.unlink

    def fail_after_creating_stage(
        directory_fd,
        *,
        parent,
        name,
        data,
        mode,
        owned_entries=None,
    ):
        if ".pmai-new." not in name:
            return original_create(
                directory_fd,
                parent=parent,
                name=name,
                data=data,
                mode=mode,
                owned_entries=owned_entries,
            )
        stage_fd = os.open(
            name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            mode,
            dir_fd=directory_fd,
        )
        try:
            os.write(stage_fd, data)
            os.fsync(stage_fd)
            stage_stat = os.fstat(stage_fd)
            if owned_entries is not None:
                owned_entries[name] = module._identity_from_stat(stage_stat)
        finally:
            os.close(stage_fd)
        raise module.AtomicFileError(
            "validation",
            "PRIMARY PREPARE ERROR",
            recovery_paths=(parent / name,),
        )

    def maybe_fail_stage_cleanup(name, *args, **kwargs):
        if fail_cleanup and ".pmai-new." in str(name):
            raise OSError(errno.EIO, "injected prepare cleanup failure")
        return original_unlink(name, *args, **kwargs)

    module._create_regular_at = fail_after_creating_stage
    module.os.unlink = maybe_fail_stage_cleanup
    try:
        module.prepare_update_at(
            directory_fd,
            parent=root,
            destination_name=destination.name,
            rendered_path=rendered,
            expected_path=expected,
            expected_mode=0o644,
        )
    except module.AtomicFileError as exc:
        assert "PRIMARY PREPARE ERROR" in str(exc), str(exc)
        backups = tuple(root.glob("hooks.json.bak.*"))
        stages = tuple(root.glob("hooks.json.pmai-new.*"))
        assert backups == (), backups
        if fail_cleanup:
            assert exc.kind == "recovery_required", (exc.kind, str(exc))
            assert "事务文件清理未完全成功" in str(exc), str(exc)
            assert len(stages) == 1, stages
            assert exc.recovery_paths == stages, (exc.recovery_paths, stages)
            assert all(item.exists() for item in exc.recovery_paths)
        else:
            assert stages == (), stages
            assert exc.kind == "validation", (exc.kind, str(exc))
            assert exc.recovery_paths == (), exc.recovery_paths
    else:
        raise AssertionError("prepare failure unexpectedly succeeded")
    finally:
        module._create_regular_at = original_create
        module.os.unlink = original_unlink
        os.close(directory_fd)

    assert destination.read_text(encoding="utf-8") == "old"


run_case(fail_cleanup=False)
run_case(fail_cleanup=True)
PY
  then
    pass_test
  else
    _fail "prepare cleanup masked its primary error or reported stale recovery paths"
  fi
}

test_prepare_does_not_unlink_unowned_collision() {
  start_test "atomic-file: prepare cleanup never unlinks a concurrently claimed name"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
rendered = root / "rendered.json"
rendered.write_text("new", encoding="utf-8")
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_open = module.os.open
collisions = []


def claim_candidate_before_create(name, flags, mode=0o777, *, dir_fd=None):
    if (
        isinstance(name, str)
        and ".pmai-new." in name
        and flags & os.O_EXCL
        and not collisions
    ):
        competing_fd = original_open(
            name,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            mode,
            dir_fd=dir_fd,
        )
        try:
            os.write(competing_fd, b"owned-by-racer")
            os.fsync(competing_fd)
        finally:
            os.close(competing_fd)
        collisions.append(root / name)
    return original_open(name, flags, mode, dir_fd=dir_fd)


module.os.open = claim_candidate_before_create
try:
    module.prepare_update_at(
        directory_fd,
        parent=root,
        destination_name="hooks.json",
        rendered_path=rendered,
        expected_path=None,
        expected_mode=0o644,
    )
except module.AtomicFileError as exc:
    assert exc.kind == "validation", (exc.kind, str(exc))
    assert exc.recovery_paths == (), exc.recovery_paths
else:
    raise AssertionError("concurrent stage-name claim unexpectedly succeeded")
finally:
    module.os.open = original_open
    os.close(directory_fd)

assert len(collisions) == 1, collisions
assert collisions[0].read_text(encoding="utf-8") == "owned-by-racer"
assert not (root / "hooks.json").exists()
assert tuple(root.glob("hooks.json.bak.*")) == ()
PY
  then
    pass_test
  else
    _fail "prepare cleanup removed a name owned by another process"
  fi
}

test_safe_read_write_reject_parent_rebind() {
  start_test "atomic-file: stable read and atomic write reject parent-directory rebinds"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
batch = root / "batch"
batch.mkdir()
artifact = batch / "review.json"
module.write_text_atomically(
    artifact,
    "one",
    require_canonical_path=True,
)
assert artifact.read_text(encoding="utf-8") == "one"
assert (artifact.stat().st_mode & 0o777) == 0o600
module.write_text_atomically(
    artifact,
    "two",
    require_canonical_path=True,
)
assert module.read_regular_bytes(
    artifact,
    require_canonical_path=True,
) == b"two"

captured_read = root / "captured-read"
original_snapshot = module._snapshot_at
snapshot_calls = 0


def move_parent_after_read(directory_fd, name, **kwargs):
    global snapshot_calls
    result = original_snapshot(directory_fd, name, **kwargs)
    if name == artifact.name:
        snapshot_calls += 1
        if snapshot_calls == 1:
            batch.rename(captured_read)
            batch.mkdir()
            (batch / artifact.name).write_text("decoy", encoding="utf-8")
    return result


module._snapshot_at = move_parent_after_read
try:
    module.read_regular_bytes(artifact, require_canonical_path=True)
except module.AtomicFileError as exc:
    assert exc.kind == "concurrent_update", (exc.kind, str(exc))
else:
    raise AssertionError("rebound read returned data")
finally:
    module._snapshot_at = original_snapshot

assert (captured_read / artifact.name).read_text(encoding="utf-8") == "two"
assert artifact.read_text(encoding="utf-8") == "decoy"

write_dir = root / "write-batch"
write_dir.mkdir()
write_target = write_dir / "comment-actions.json"
write_target.write_text("old", encoding="utf-8")
captured_write = root / "captured-write"
original_create = module._create_regular_at
moved = False


def move_parent_after_stage(*args, **kwargs):
    global moved
    result = original_create(*args, **kwargs)
    name = kwargs.get("name", "")
    if ".pmai-write-stage-" in name and not moved:
        moved = True
        write_dir.rename(captured_write)
        write_dir.mkdir()
        write_target.write_text("replacement", encoding="utf-8")
    return result


module._create_regular_at = move_parent_after_stage
try:
    module.write_text_atomically(
        write_target,
        "new",
        require_canonical_path=True,
    )
except module.AtomicFileError as exc:
    assert exc.kind == "concurrent_update", (exc.kind, str(exc))
else:
    raise AssertionError("rebound write unexpectedly succeeded")
finally:
    module._create_regular_at = original_create

assert moved
assert (captured_write / write_target.name).read_text(encoding="utf-8") == "old"
assert write_target.read_text(encoding="utf-8") == "replacement"
assert tuple(captured_write.glob("*.pmai-write-stage-*")) == ()
assert tuple(write_dir.glob("*.pmai-write-stage-*")) == ()
PY
  then
    pass_test
  else
    _fail "safe read/write crossed a rebound parent-directory boundary"
  fi
}

test_expected_snapshot_rejects_final_symlinks() {
  start_test "atomic-file: expected snapshots reject relative and absolute final symlinks"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
target = root / "expected.json"
link = root / "expected-link.json"
target.write_text("expected", encoding="utf-8")
link.symlink_to(target)

old_cwd = Path.cwd()
os.chdir(root)
try:
    assert module._snapshot_path(Path("expected.json"), label="预期版本").data == b"expected"
    candidates = (Path("expected-link.json"), link)
    for candidate in candidates:
        try:
            module._snapshot_path(candidate, label="预期版本")
        except module.AtomicFileError as exc:
            assert exc.kind == "validation", (candidate, exc.kind, str(exc))
        else:
            raise AssertionError(f"final symlink was followed: {candidate}")
finally:
    os.chdir(old_cwd)

assert target.read_text(encoding="utf-8") == "expected"
PY
  then
    pass_test
  else
    _fail "relative and absolute expected symlinks did not share O_NOFOLLOW semantics"
  fi
}

test_create_postcheck_reports_existing_paths_only() {
  start_test "atomic-file: create post-check reports only paths that still exist"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
original_snapshot = module._snapshot_at
original_same = module._same_file


def run_snapshot_race(label, mutate, expected_paths, message):
    destination = root / f"{label}.json"
    stage = root / f"{label}.stage"
    stage.write_text("new", encoding="utf-8")

    def racing_snapshot(directory_fd, name, **kwargs):
        if name == destination.name:
            mutate(destination)
        return original_snapshot(directory_fd, name, **kwargs)

    module._snapshot_at = racing_snapshot
    try:
        module.create_from_staged(destination, stage)
    except module.AtomicFileError as exc:
        assert exc.kind == "recovery_required", (label, exc.kind, str(exc))
        assert message in str(exc), (label, str(exc))
        assert exc.recovery_paths == expected_paths(destination), (
            label,
            exc.recovery_paths,
        )
    else:
        raise AssertionError(f"{label} create race unexpectedly succeeded")
    finally:
        module._snapshot_at = original_snapshot
    return destination


missing = run_snapshot_race(
    "missing",
    lambda destination: destination.unlink(),
    lambda _destination: (),
    "当前无可确认的恢复文件",
)
assert not missing.exists()

target = root / "special-target.json"
target.write_text("target", encoding="utf-8")


def replace_with_symlink(destination):
    destination.unlink()
    destination.symlink_to(target)


special = run_snapshot_race(
    "special",
    replace_with_symlink,
    lambda destination: (destination,),
    "当前路径仍存在",
)
assert special.is_symlink()
assert target.read_text(encoding="utf-8") == "target"

modified = run_snapshot_race(
    "modified",
    lambda destination: destination.write_text("racer", encoding="utf-8"),
    lambda destination: (destination,),
    "当前正式路径已保留",
)
assert modified.read_text(encoding="utf-8") == "racer"

disappearing = root / "disappearing.json"
disappearing_stage = root / "disappearing.stage"
disappearing_stage.write_text("new", encoding="utf-8")


def remove_before_recovery_check(_left, _right):
    disappearing.unlink()
    return False


module._same_file = remove_before_recovery_check
try:
    module.create_from_staged(disappearing, disappearing_stage)
except module.AtomicFileError as exc:
    assert exc.kind == "recovery_required", (exc.kind, str(exc))
    assert "随后正式路径消失" in str(exc), str(exc)
    assert exc.recovery_paths == (), exc.recovery_paths
else:
    raise AssertionError("disappearing mismatch unexpectedly succeeded")
finally:
    module._same_file = original_same

assert not disappearing.exists()
PY
  then
    pass_test
  else
    _fail "create post-check recovery paths did not match the live namespace"
  fi
}

test_restore_claim_classifies_failures_and_existing_paths() {
  start_test "atomic-file: restore claim distinguishes EEXIST from other failures"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import errno
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
destination = root / "body.md"
quarantine = root / ".body.md.pmai-cas-original-test"
destination.write_text("racer", encoding="utf-8")
quarantine.write_text("original", encoding="utf-8")
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_rename = module._rename_noreplace
try:
    try:
        module._restore_claim(
            directory_fd,
            quarantine.name,
            destination.name,
            parent=root,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "recovery_required", (exc.kind, str(exc))
        assert "目标名已被并发创建" in str(exc), str(exc)
        assert exc.recovery_paths == (destination, quarantine), exc.recovery_paths
        assert all(item.exists() for item in exc.recovery_paths)
    else:
        raise AssertionError("restore EEXIST unexpectedly succeeded")

    destination.unlink()

    def fail_restore(*_args):
        raise OSError(errno.EIO, "injected restore failure")

    module._rename_noreplace = fail_restore
    try:
        module._restore_claim(
            directory_fd,
            quarantine.name,
            destination.name,
            parent=root,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "recovery_required", (exc.kind, str(exc))
        assert "恢复原件失败" in str(exc), str(exc)
        assert "目标名已被并发创建" not in str(exc), str(exc)
        assert exc.recovery_paths == (quarantine,), exc.recovery_paths
        assert quarantine.exists()
        assert not destination.exists()
    else:
        raise AssertionError("restore EIO unexpectedly succeeded")
finally:
    module._rename_noreplace = original_rename
    os.close(directory_fd)
PY
  then
    pass_test
  else
    _fail "restore claim error classification or recovery paths were inaccurate"
  fi
}

test_prepared_entry_identities_block_name_reuse() {
  start_test "atomic-file: prepared stage and backup identities survive name reuse"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
destination = root / "hooks.json"
expected = root / "expected.json"
rendered = root / "rendered.json"
destination.write_text("old", encoding="utf-8")
expected.write_text("old", encoding="utf-8")
rendered.write_text("new", encoding="utf-8")
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
try:
    prepared = module.prepare_update_at(
        directory_fd,
        parent=root,
        destination_name=destination.name,
        rendered_path=rendered,
        expected_path=expected,
        expected_mode=0o644,
    )
    assert prepared.original_identity is not None
    assert prepared.backup_name is not None
    assert prepared.backup_identity is not None
    assert (
        prepared.original_identity.device,
        prepared.original_identity.inode,
    ) == (destination.stat().st_dev, destination.stat().st_ino)
    stage = root / prepared.stage_name
    backup = root / prepared.backup_name

    original_snapshot_bound = module._snapshot_bound_at
    swapped = False

    def swap_after_identity_read(*args, **kwargs):
        global swapped
        result = original_snapshot_bound(*args, **kwargs)
        if (
            kwargs.get("name") == stage.name
            and kwargs.get("fsync_file")
            and not swapped
        ):
            swapped = True
            stage.unlink()
            stage.write_text("foreign-stage", encoding="utf-8")
        return result

    module._snapshot_bound_at = swap_after_identity_read
    try:
        try:
            module.replace_entry_at(
                directory_fd,
                parent=root,
                destination_name=destination.name,
                staged_name=stage.name,
                staged_device=prepared.stage_identity.device,
                staged_inode=prepared.stage_identity.inode,
                staged_size=prepared.stage_identity.size,
                staged_mtime_ns=prepared.stage_identity.mtime_ns,
                expected_name=backup.name,
                expected_path=None,
                expected_mode=0o644,
                expected_entry_device=prepared.backup_identity.device,
                expected_entry_inode=prepared.backup_identity.inode,
                expected_entry_size=prepared.backup_identity.size,
                expected_entry_mtime_ns=prepared.backup_identity.mtime_ns,
                destination_device=prepared.original_identity.device,
                destination_inode=prepared.original_identity.inode,
                destination_size=prepared.original_identity.size,
                destination_mtime_ns=prepared.original_identity.mtime_ns,
            )
        except module.AtomicFileError as exc:
            assert exc.kind == "concurrent_update", (exc.kind, str(exc))
        else:
            raise AssertionError("reused stage name unexpectedly committed")
    finally:
        module._snapshot_bound_at = original_snapshot_bound
    assert swapped
    assert destination.read_text(encoding="utf-8") == "old"
    assert stage.read_text(encoding="utf-8") == "foreign-stage"

    try:
        module.unlink_entry_at(
            directory_fd,
            parent=root,
            name=stage.name,
            expected_device=prepared.stage_identity.device,
            expected_inode=prepared.stage_identity.inode,
            expected_size=prepared.stage_identity.size,
            expected_mtime_ns=prepared.stage_identity.mtime_ns,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("cleanup deleted a foreign stage")
    assert stage.read_text(encoding="utf-8") == "foreign-stage"
    stage.unlink()

    destination.write_text("new", encoding="utf-8")
    backup.unlink()
    backup.write_text("foreign-backup", encoding="utf-8")
    try:
        module.replace_entry_at(
            directory_fd,
            parent=root,
            destination_name=destination.name,
            staged_name=backup.name,
            staged_device=prepared.backup_identity.device,
            staged_inode=prepared.backup_identity.inode,
            staged_size=prepared.backup_identity.size,
            staged_mtime_ns=prepared.backup_identity.mtime_ns,
            expected_name=None,
            expected_path=rendered,
            expected_mode=0o644,
            destination_device=prepared.original_identity.device,
            destination_inode=prepared.original_identity.inode,
            destination_size=prepared.original_identity.size,
            destination_mtime_ns=prepared.original_identity.mtime_ns,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("reused backup name unexpectedly rolled back")
    assert destination.read_text(encoding="utf-8") == "new"
    assert backup.read_text(encoding="utf-8") == "foreign-backup"
finally:
    os.close(directory_fd)
PY
  then
    pass_test
  else
    _fail "prepared inode identities did not protect commit, rollback, or cleanup"
  fi
}

test_identity_cleanup_claim_restores_foreign_and_reports_stat_errors() {
  start_test "atomic-file: identity cleanup claims before unlink and restores mismatches"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import errno
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
entry = root / "hooks.json.pmai-new.test"
entry.write_text("owned", encoding="utf-8")
identity = entry.stat()
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_rename_bound = module._rename_noreplace_bound
swapped = False


def swap_before_claim(*args, **kwargs):
    global swapped
    if kwargs.get("label") == "事务文件清理 claim" and not swapped:
        swapped = True
        entry.unlink()
        entry.write_text("foreign", encoding="utf-8")
    return original_rename_bound(*args, **kwargs)


module._rename_noreplace_bound = swap_before_claim
try:
    try:
        module.unlink_entry_at(
            directory_fd,
            parent=root,
            name=entry.name,
            expected_device=identity.st_dev,
            expected_inode=identity.st_ino,
            expected_size=identity.st_size,
            expected_mtime_ns=identity.st_mtime_ns,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("identity-mismatched cleanup unexpectedly succeeded")
finally:
    module._rename_noreplace_bound = original_rename_bound

assert swapped
assert entry.read_text(encoding="utf-8") == "foreign"
assert not list(root.glob("*.pmai-cleanup-claim-*"))

entry.unlink()
entry.write_text("owned-again", encoding="utf-8")
identity = entry.stat()
original_stat = module.os.stat
claimed = False


def mark_claim(*args, **kwargs):
    global claimed
    result = original_rename_bound(*args, **kwargs)
    if kwargs.get("label") == "事务文件清理 claim":
        claimed = True
    return result


def fail_claim_stat(name, *args, **kwargs):
    if claimed and ".pmai-cleanup-claim-" in str(name):
        raise OSError(errno.EIO, "injected claim stat failure")
    return original_stat(name, *args, **kwargs)


module._rename_noreplace_bound = mark_claim
module.os.stat = fail_claim_stat
try:
    try:
        module.unlink_entry_at(
            directory_fd,
            parent=root,
            name=entry.name,
            expected_device=identity.st_dev,
            expected_inode=identity.st_ino,
            expected_size=identity.st_size,
            expected_mtime_ns=identity.st_mtime_ns,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "recovery_required", (exc.kind, str(exc))
        assert entry in exc.recovery_paths, exc.recovery_paths
    else:
        raise AssertionError("claim stat failure was treated as missing")
finally:
    module.os.stat = original_stat
    module._rename_noreplace_bound = original_rename_bound
    os.close(directory_fd)

assert entry.read_text(encoding="utf-8") == "owned-again"
assert not list(root.glob("*.pmai-cleanup-claim-*"))
PY
  then
    pass_test
  else
    _fail "identity cleanup deleted foreign data or hid an indeterminate path"
  fi
}

test_generation_identity_rejects_simulated_inode_reuse() {
  start_test "atomic-file: size and mtime reject simulated inode reuse"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
entry = root / "hooks.json.pmai-new.test"
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
try:
    entry.write_text("owned", encoding="utf-8")
    old = entry.stat()
    entry.unlink()
    entry.write_text("other", encoding="utf-8")
    os.utime(
        entry,
        ns=(entry.stat().st_atime_ns, old.st_mtime_ns + 1),
    )
    current = entry.stat()
    assert current.st_size == old.st_size
    try:
        module.unlink_entry_at(
            directory_fd,
            parent=root,
            name=entry.name,
            expected_device=current.st_dev,
            expected_inode=current.st_ino,
            expected_size=old.st_size,
            expected_mtime_ns=old.st_mtime_ns,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("same-size inode reuse bypassed mtime identity")
    assert entry.read_text(encoding="utf-8") == "other"

    old = entry.stat()
    entry.unlink()
    entry.write_text("foreign-longer", encoding="utf-8")
    os.utime(
        entry,
        ns=(entry.stat().st_atime_ns, old.st_mtime_ns),
    )
    current = entry.stat()
    assert current.st_size != old.st_size
    try:
        module.unlink_entry_at(
            directory_fd,
            parent=root,
            name=entry.name,
            expected_device=current.st_dev,
            expected_inode=current.st_ino,
            expected_size=old.st_size,
            expected_mtime_ns=current.st_mtime_ns,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("different-size inode reuse bypassed size identity")
    assert entry.read_text(encoding="utf-8") == "foreign-longer"
finally:
    os.close(directory_fd)
PY
  then
    pass_test
  else
    _fail "file generation identity accepted simulated inode reuse"
  fi
}

test_cleanup_unlink_fsyncs_before_parent_rebind_check() {
  start_test "atomic-file: cleanup unlink 后先持久化绑定目录再报告父目录重绑"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
parent = root / "bound"
captured = root / "captured"
parent.mkdir()
entry = parent / "hooks.json.pmai-new.test"
entry.write_text("owned", encoding="utf-8")
identity = entry.stat()
directory_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_unlink = module.os.unlink
original_fsync = module.os.fsync
state = {"unlinked": False, "rebound": False, "fsynced_after_unlink": False}


def rebind_after_cleanup_unlink(name, *args, **kwargs):
    result = original_unlink(name, *args, **kwargs)
    if ".pmai-cleanup-claim-" in str(name) and not state["rebound"]:
        state["unlinked"] = True
        parent.rename(captured)
        parent.mkdir()
        state["rebound"] = True
    return result


def observe_fsync(fd):
    if fd == directory_fd and state["unlinked"]:
        state["fsynced_after_unlink"] = True
    return original_fsync(fd)


module.os.unlink = rebind_after_cleanup_unlink
module.os.fsync = observe_fsync
try:
    try:
        module.unlink_entry_at(
            directory_fd,
            parent=parent,
            name=entry.name,
            expected_device=identity.st_dev,
            expected_inode=identity.st_ino,
            expected_size=identity.st_size,
            expected_mtime_ns=identity.st_mtime_ns,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("cleanup ignored a rebound display parent")
finally:
    module.os.fsync = original_fsync
    module.os.unlink = original_unlink
    os.close(directory_fd)

assert state["rebound"] is True, state
assert state["fsynced_after_unlink"] is True, state
assert not list(captured.iterdir()), tuple(captured.iterdir())
assert not list(parent.iterdir()), tuple(parent.iterdir())
PY
  then
    pass_test
  else
    _fail "cleanup checked the display parent before persisting the bound unlink"
  fi
}

test_cleanup_final_fsync_failure_reports_claim_recovery_path() {
  start_test "atomic-file: cleanup 最终 fsync 失败返回可能重现的 claim 路径"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import errno
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
entry = root / "hooks.json.pmai-new.test"
entry.write_text("owned", encoding="utf-8")
identity = entry.stat()
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_unlink = module.os.unlink
original_fsync = module.os.fsync
state = {"claim_path": None, "unlinked": False}


def record_cleanup_unlink(name, *args, **kwargs):
    if ".pmai-cleanup-claim-" in str(name):
        state["claim_path"] = root / str(name)
    result = original_unlink(name, *args, **kwargs)
    if state["claim_path"] is not None:
        state["unlinked"] = True
    return result


def fail_fsync_after_unlink(fd):
    if fd == directory_fd and state["unlinked"]:
        raise OSError(errno.EIO, "injected final directory fsync failure")
    return original_fsync(fd)


module.os.unlink = record_cleanup_unlink
module.os.fsync = fail_fsync_after_unlink
try:
    try:
        module.unlink_entry_at(
            directory_fd,
            parent=root,
            name=entry.name,
            expected_device=identity.st_dev,
            expected_inode=identity.st_ino,
            expected_size=identity.st_size,
            expected_mtime_ns=identity.st_mtime_ns,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "recovery_required", (exc.kind, str(exc))
        assert state["claim_path"] is not None, state
        assert exc.recovery_paths == (state["claim_path"],), exc.recovery_paths
        assert not state["claim_path"].exists()
    else:
        raise AssertionError("final cleanup fsync failure unexpectedly succeeded")
finally:
    module.os.fsync = original_fsync
    module.os.unlink = original_unlink
    os.close(directory_fd)

assert state["unlinked"] is True, state
assert not list(root.iterdir()), tuple(root.iterdir())
PY
  then
    pass_test
  else
    _fail "cleanup final fsync failure omitted the potentially reappearing claim path"
  fi
}

test_cleanup_removes_stale_generated_recovery_paths() {
  start_test "atomic-file: successful cleanup removes stale generated recovery paths"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
destination = root / "new.json"
original_create = module._create_regular_at


def fail_after_create(*args, **kwargs):
    original_create(*args, **kwargs)
    generated = kwargs["parent"] / kwargs["name"]
    raise module.AtomicFileError(
        "validation",
        "PRIMARY CREATE ERROR",
        recovery_paths=(generated,),
    )


module._create_regular_at = fail_after_create
try:
    module.write_text_atomically(destination, "new", require_canonical_path=True)
except module.AtomicFileError as exc:
    assert "PRIMARY CREATE ERROR" in str(exc), str(exc)
    assert exc.kind == "validation", (exc.kind, str(exc))
    assert exc.recovery_paths == (), exc.recovery_paths
else:
    raise AssertionError("injected create failure unexpectedly succeeded")
finally:
    module._create_regular_at = original_create

assert not destination.exists()
assert not list(root.glob(".new.json.pmai-write-stage-*"))
PY
  then
    pass_test
  else
    _fail "successful cleanup still reported a deleted generated path"
  fi
}

test_zero_progress_writes_fail_closed() {
  start_test "atomic-file: zero-progress os.write fails instead of looping"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_write = module.os.write
module.os.write = lambda *_args, **_kwargs: 0
try:
    try:
        module._create_regular_at(
            directory_fd,
            parent=root,
            name="stage",
            data=b"payload",
            mode=0o600,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "validation", (exc.kind, str(exc))
        assert "未取得进展" in str(exc.__cause__), repr(exc.__cause__)
    else:
        raise AssertionError("zero-progress write unexpectedly returned")
finally:
    module.os.write = original_write
    os.close(directory_fd)
PY
  then
    pass_test
  else
    _fail "zero-progress os.write did not fail closed"
  fi
}

test_bound_helpers_recheck_parent_after_entry_validation() {
  start_test "atomic-file: bound helpers reject parent rebinds after entry validation"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
parent = root / "bound"
captured = root / "captured"
parent.mkdir()
(parent / "hooks.json").write_text("old", encoding="utf-8")
output = root / "snapshot"
directory_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_recovery_check = module._ensure_no_recovery_state
moved = False


def move_after_entry_check(*args, **kwargs):
    global moved
    result = original_recovery_check(*args, **kwargs)
    if not moved:
        moved = True
        parent.rename(captured)
        parent.mkdir()
        (parent / "hooks.json").write_text("decoy", encoding="utf-8")
    return result


module._ensure_no_recovery_state = move_after_entry_check
try:
    try:
        module.snapshot_entry_at(
            directory_fd,
            parent=parent,
            destination_name="hooks.json",
            output=output,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("snapshot returned after its parent was rebound")
finally:
    module._ensure_no_recovery_state = original_recovery_check
    os.close(directory_fd)

assert moved
assert not output.exists()
assert (captured / "hooks.json").read_text(encoding="utf-8") == "old"
assert (parent / "hooks.json").read_text(encoding="utf-8") == "decoy"

prepare_parent = root / "prepare"
prepare_captured = root / "prepare-captured"
prepare_parent.mkdir()
rendered = root / "rendered.json"
rendered.write_text("new", encoding="utf-8")
directory_fd = os.open(prepare_parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_snapshot_path = module._snapshot_path
moved = False


def move_after_rendered_read(*args, **kwargs):
    global moved
    result = original_snapshot_path(*args, **kwargs)
    if not moved:
        moved = True
        prepare_parent.rename(prepare_captured)
        prepare_parent.mkdir()
    return result


module._snapshot_path = move_after_rendered_read
try:
    try:
        module.prepare_update_at(
            directory_fd,
            parent=prepare_parent,
            destination_name="hooks.json",
            rendered_path=rendered,
            expected_path=None,
            expected_mode=0o644,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("prepare continued after its parent was rebound")
finally:
    module._snapshot_path = original_snapshot_path
    os.close(directory_fd)

assert moved
assert not list(prepare_captured.iterdir())
assert not list(prepare_parent.iterdir())
PY
  then
    pass_test
  else
    _fail "bound helper continued reading or writing after a parent rebind"
  fi
}

test_namespace_mutations_compensate_parent_rebinds() {
  start_test "atomic-file: namespace mutations compensate rebinds after precheck"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def run(target_label):
    root = Path(tempfile.mkdtemp()).resolve()
    parent = root / "bound"
    captured = root / "captured"
    parent.mkdir()
    destination = parent / "hooks.json"
    stage = parent / "hooks.json.pmai-new.test"
    destination.write_text("old", encoding="utf-8")
    stage.write_text("new", encoding="utf-8")
    stage_stat = stage.stat()
    directory_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    expected = module._snapshot_at(
        directory_fd,
        destination.name,
        display_path=destination,
    )
    original_assert = module._assert_directory_is_current
    moved = False

    def move_after_precheck(fd, checked_parent, *, label="Host 配置目录"):
        nonlocal moved
        result = original_assert(fd, checked_parent, label=label)
        if label == target_label and not moved:
            moved = True
            parent.rename(captured)
            parent.mkdir()
        return result

    module._assert_directory_is_current = move_after_precheck
    try:
        try:
            module._replace_staged_at(
                directory_fd,
                parent=parent,
                destination_name=destination.name,
                staged_name=stage.name,
                staged_identity=module.EntryIdentity(
                    stage_stat.st_dev,
                    stage_stat.st_ino,
                    stage_stat.st_size,
                    stage_stat.st_mtime_ns,
                ),
                expected=expected,
            )
        except module.AtomicFileError as exc:
            assert exc.kind in {"concurrent_update", "recovery_required"}, (
                target_label,
                exc.kind,
                str(exc),
            )
        else:
            raise AssertionError(f"{target_label}: rebound mutation unexpectedly succeeded")
    finally:
        module._assert_directory_is_current = original_assert
        os.close(directory_fd)

    assert moved, target_label
    assert (captured / destination.name).read_text(encoding="utf-8") == "old"
    assert (captured / stage.name).read_text(encoding="utf-8") == "new"
    assert sorted(item.name for item in captured.iterdir()) == [
        destination.name,
        stage.name,
    ], (target_label, tuple(captured.iterdir()))
    assert not list(parent.iterdir()), target_label


for label in (
    "Host 暂存文件 claim",
    "原子写入 claim",
    "原子安装新文件",
):
    run(label)

root = Path(tempfile.mkdtemp()).resolve()
parent = root / "bound"
captured = root / "captured"
parent.mkdir()
directory_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_assert = module._assert_directory_is_current
moved = False


def move_after_create_precheck(fd, checked_parent, *, label="Host 配置目录"):
    global moved
    result = original_assert(fd, checked_parent, label=label)
    if label == "安全文件目标目录" and not moved:
        moved = True
        parent.rename(captured)
        parent.mkdir()
    return result


module._assert_directory_is_current = move_after_create_precheck
try:
    try:
        module._create_regular_at(
            directory_fd,
            parent=parent,
            name="hooks.json.pmai-new.test",
            data=b"new",
            mode=0o600,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("rebound create unexpectedly succeeded")
finally:
    module._assert_directory_is_current = original_assert
    os.close(directory_fd)

assert moved
assert not list(captured.iterdir())
assert not list(parent.iterdir())
PY
  then
    pass_test
  else
    _fail "namespace mutation left self-owned changes in a rebound directory"
  fi
}

test_delete_claim_compensates_parent_rebind() {
  start_test "atomic-file: delete claim 后父目录改向会恢复原名并保留新绑定目录"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
parent = root / "bound"
captured = root / "captured"
parent.mkdir()
destination = parent / "hooks.json"
destination.write_text("old", encoding="utf-8")
directory_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
expected = module._snapshot_at(
    directory_fd,
    destination.name,
    display_path=destination,
)
original_assert = module._assert_directory_is_current
claim_checks = 0


def rebind_after_delete_claim(fd, checked_parent, *, label="Host 配置目录"):
    global claim_checks
    if label == "原子删除 claim":
        claim_checks += 1
        if claim_checks == 2:
            parent.rename(captured)
            parent.mkdir()
            (parent / destination.name).write_text("decoy", encoding="utf-8")
    return original_assert(fd, checked_parent, label=label)


module._assert_directory_is_current = rebind_after_delete_claim
try:
    try:
        module._delete_if_unchanged_at(
            directory_fd,
            parent=parent,
            destination_name=destination.name,
            expected=expected,
            expected_mode=expected.mode,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
        assert "已补偿" in str(exc), str(exc)
    else:
        raise AssertionError("delete returned after its parent was rebound")
finally:
    module._assert_directory_is_current = original_assert
    os.close(directory_fd)

assert claim_checks == 2, claim_checks
assert (captured / destination.name).read_text(encoding="utf-8") == "old"
assert [item.name for item in captured.iterdir()] == [destination.name]
assert (parent / destination.name).read_text(encoding="utf-8") == "decoy"
PY
  then
    pass_test
  else
    _fail "delete claim left the original quarantined after a parent rebind"
  fi
}

test_prepare_cli_uses_fixed_fourteen_field_identity_protocol() {
  start_test "atomic-file: prepare-at returns a fixed 14-field identity protocol"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import contextlib
import importlib.util
import io
import os
import stat
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


def prepare_case(existed: bool) -> None:
    root = Path(tempfile.mkdtemp()).resolve()
    destination = root / "hooks.json"
    expected = root / "expected.json"
    rendered = root / "rendered.json"
    rendered.write_text("new", encoding="utf-8")
    original_stat = None
    expected_mode = 0o640 if existed else 0o644
    if existed:
        destination.write_text("old", encoding="utf-8")
        destination.chmod(expected_mode)
        expected.write_text("old", encoding="utf-8")
        original_stat = destination.stat()

    directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    directory_stat = os.fstat(directory_fd)
    arguments = [
        "prepare-at",
        "--directory-fd",
        str(directory_fd),
        "--expected-device",
        str(directory_stat.st_dev),
        "--expected-inode",
        str(directory_stat.st_ino),
        "--parent-display",
        str(root),
        "--destination-name",
        destination.name,
        "--rendered",
        str(rendered),
        "--expected-mode",
        format(expected_mode, "o"),
    ]
    if existed:
        arguments.extend(("--expected", str(expected)))

    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            assert module.main(arguments) == 0
    finally:
        os.close(directory_fd)

    line = output.getvalue().rstrip("\n")
    assert "\n" not in line, line
    fields = line.split("\t")
    assert len(fields) == 14, fields
    assert all(fields), fields
    original_device, original_inode, original_size, original_mtime_ns = fields[:4]
    backup_name, backup_device, backup_inode, backup_size, backup_mtime_ns = fields[4:9]
    stage_name, stage_device, stage_inode, stage_size, stage_mtime_ns = fields[9:]
    assert stage_name != "-"
    assert all(
        value.isdecimal()
        for value in (stage_device, stage_inode, stage_size, stage_mtime_ns)
    ), fields
    stage_stat = os.stat(root / stage_name, follow_symlinks=False)
    assert tuple(map(int, fields[10:14])) == (
        stage_stat.st_dev,
        stage_stat.st_ino,
        stage_stat.st_size,
        stage_stat.st_mtime_ns,
    )
    assert stat.S_ISREG(stage_stat.st_mode)

    if existed:
        assert original_stat is not None
        assert all(
            value.isdecimal()
            for value in (
                original_device,
                original_inode,
                original_size,
                original_mtime_ns,
            )
        ), fields
        assert tuple(map(int, fields[:4])) == (
            original_stat.st_dev,
            original_stat.st_ino,
            original_stat.st_size,
            original_stat.st_mtime_ns,
        )
        assert backup_name != "-"
        assert all(
            value.isdecimal()
            for value in (
                backup_device,
                backup_inode,
                backup_size,
                backup_mtime_ns,
            )
        ), fields
        backup_stat = os.stat(root / backup_name, follow_symlinks=False)
        assert tuple(map(int, fields[5:9])) == (
            backup_stat.st_dev,
            backup_stat.st_ino,
            backup_stat.st_size,
            backup_stat.st_mtime_ns,
        )
    else:
        assert fields[:9] == ["-"] * 9, fields


prepare_case(True)
prepare_case(False)
PY
  then
    pass_test
  else
    _fail "prepare-at did not preserve its fixed 14-field identity contract"
  fi
}

test_destination_identities_reject_same_content_name_reuse() {
  start_test "atomic-file: destination identity rejects same-content create/replace races"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

# The installer lock serializes cooperative PMAI writers. These inode checks
# additionally fail closed when a pathname replacement is observed; they do not
# claim to constrain an arbitrary non-cooperative process with the same uid.
root = Path(tempfile.mkdtemp()).resolve()
destination = root / "hooks.json"
expected = root / "expected.json"
rendered = root / "rendered.json"
destination.write_text("old", encoding="utf-8")
expected.write_text("old", encoding="utf-8")
rendered.write_text("new", encoding="utf-8")
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
try:
    prepared = module.prepare_update_at(
        directory_fd,
        parent=root,
        destination_name=destination.name,
        rendered_path=rendered,
        expected_path=expected,
        expected_mode=0o644,
    )
    assert prepared.original_identity is not None
    assert prepared.backup_name is not None
    assert prepared.backup_identity is not None
    held_original = root / "held-original.json"
    destination.rename(held_original)
    destination.write_text("old", encoding="utf-8")
    assert destination.stat().st_ino != prepared.original_identity.inode

    state = module.inspect_entry_at(
        directory_fd,
        parent=root,
        destination_name=destination.name,
        expected_name=prepared.backup_name,
        expected_path=None,
        expected_mode=0o644,
        expected_entry_device=prepared.backup_identity.device,
        expected_entry_inode=prepared.backup_identity.inode,
        expected_entry_size=prepared.backup_identity.size,
        expected_entry_mtime_ns=prepared.backup_identity.mtime_ns,
        destination_device=prepared.original_identity.device,
        destination_inode=prepared.original_identity.inode,
        destination_size=prepared.original_identity.size,
        destination_mtime_ns=prepared.original_identity.mtime_ns,
    )
    assert state == "different", state
    try:
        module.replace_entry_at(
            directory_fd,
            parent=root,
            destination_name=destination.name,
            staged_name=prepared.stage_name,
            staged_device=prepared.stage_identity.device,
            staged_inode=prepared.stage_identity.inode,
            staged_size=prepared.stage_identity.size,
            staged_mtime_ns=prepared.stage_identity.mtime_ns,
            expected_name=prepared.backup_name,
            expected_path=None,
            expected_mode=0o644,
            expected_entry_device=prepared.backup_identity.device,
            expected_entry_inode=prepared.backup_identity.inode,
            expected_entry_size=prepared.backup_identity.size,
            expected_entry_mtime_ns=prepared.backup_identity.mtime_ns,
            destination_device=prepared.original_identity.device,
            destination_inode=prepared.original_identity.inode,
            destination_size=prepared.original_identity.size,
            destination_mtime_ns=prepared.original_identity.mtime_ns,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("same-content replacement unexpectedly committed")
    assert destination.read_text(encoding="utf-8") == "old"
    assert (root / prepared.stage_name).exists()
finally:
    os.close(directory_fd)

create_root = Path(tempfile.mkdtemp()).resolve()
create_destination = create_root / "hooks.json"
create_rendered = create_root / "rendered.json"
create_rendered.write_text("new", encoding="utf-8")
create_fd = os.open(
    create_root,
    os.O_RDONLY | getattr(os, "O_DIRECTORY", 0),
)
try:
    prepared = module.prepare_update_at(
        create_fd,
        parent=create_root,
        destination_name=create_destination.name,
        rendered_path=create_rendered,
        expected_path=None,
        expected_mode=0o644,
    )
    assert prepared.original_identity is None
    module.create_entry_at(
        create_fd,
        parent=create_root,
        destination_name=create_destination.name,
        staged_name=prepared.stage_name,
        staged_device=prepared.stage_identity.device,
        staged_inode=prepared.stage_identity.inode,
        staged_size=prepared.stage_identity.size,
        staged_mtime_ns=prepared.stage_identity.mtime_ns,
    )
    held_stage = create_root / "held-stage.json"
    create_destination.rename(held_stage)
    create_destination.write_bytes(held_stage.read_bytes())
    assert create_destination.stat().st_ino != prepared.stage_identity.inode

    state = module.inspect_entry_at(
        create_fd,
        parent=create_root,
        destination_name=create_destination.name,
        expected_name=None,
        expected_path=create_rendered,
        expected_mode=0o644,
        destination_device=prepared.stage_identity.device,
        destination_inode=prepared.stage_identity.inode,
        destination_size=prepared.stage_identity.size,
        destination_mtime_ns=prepared.stage_identity.mtime_ns,
    )
    assert state == "different", state
    expected_snapshot = module._snapshot_path(
        create_rendered,
        label="expected rendered output",
    )
    try:
        module._delete_if_unchanged_at(
            create_fd,
            parent=create_root,
            destination_name=create_destination.name,
            expected=expected_snapshot,
            expected_mode=0o644,
            destination_identity=prepared.stage_identity,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("same-content recreated destination was deleted")
    assert create_destination.read_text(encoding="utf-8") == "new"
finally:
    os.close(create_fd)
PY
  then
    pass_test
  else
    _fail "destination inode checks accepted a same-content pathname replacement"
  fi
}

test_prepare_final_parent_rebind_cleans_owned_entries() {
  start_test "atomic-file: prepare final parent rebind cleans owned backup and stage"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import importlib.util
import os
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("atomic_file_test", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

root = Path(tempfile.mkdtemp()).resolve()
parent = root / "bound"
captured = root / "captured"
parent.mkdir()
destination = parent / "hooks.json"
expected = root / "expected.json"
rendered = root / "rendered.json"
destination.write_text("old", encoding="utf-8")
expected.write_text("old", encoding="utf-8")
rendered.write_text("new", encoding="utf-8")
directory_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_create = module._create_regular_at
create_count = 0


def move_after_all_owned_entries(*args, **kwargs):
    global create_count
    identity = original_create(*args, **kwargs)
    create_count += 1
    if create_count == 2:
        parent.rename(captured)
        parent.mkdir()
    return identity


module._create_regular_at = move_after_all_owned_entries
try:
    try:
        module.prepare_update_at(
            directory_fd,
            parent=parent,
            destination_name=destination.name,
            rendered_path=rendered,
            expected_path=expected,
            expected_mode=0o644,
        )
    except module.AtomicFileError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
        assert not exc.recovery_paths, exc.recovery_paths
    else:
        raise AssertionError("prepare returned after its final parent rebind")
finally:
    module._create_regular_at = original_create
    os.close(directory_fd)

assert create_count == 2, create_count
assert sorted(item.name for item in captured.iterdir()) == [destination.name]
assert (captured / destination.name).read_text(encoding="utf-8") == "old"
assert not list(parent.iterdir())
PY
  then
    pass_test
  else
    _fail "prepare leaked owned transaction entries after its final parent rebind"
  fi
}

test_run_locked_serializes_cooperative_writers() {
  start_test "atomic-file: stable Git-dir lock serializes cooperative PMAI writers"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$ATOMIC_FILE" <<'PY'
import os
import signal
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

atomic_file = Path(sys.argv[1])
root = Path(tempfile.mkdtemp()).resolve()
lock_path = root / ".pmai-install-project-hooks.lock"
worker = root / "worker.py"
worker.write_text(
    """import errno
import os
import subprocess
import sys
import time
from pathlib import Path

atomic_file = Path(sys.argv[3])
lock_path = Path(sys.argv[4])
lock_fd_text = os.environ.get("PMAI_PROJECT_HOOKS_LOCK_FD", "")
assert lock_fd_text.isdigit(), lock_fd_text
lock_fd = int(lock_fd_text)
lock_stat = os.fstat(lock_fd)
path_stat = os.stat(lock_path, follow_symlinks=False)
assert (lock_stat.st_dev, lock_stat.st_ino) == (path_stat.st_dev, path_stat.st_ino)
verified = subprocess.run(
    [
        sys.executable,
        str(atomic_file),
        "verify-lock-fd",
        "--lock-path",
        str(lock_path),
        "--lock-fd",
        str(lock_fd),
    ],
    pass_fds=(lock_fd,),
    capture_output=True,
    text=True,
)
assert verified.returncode == 0, verified

for descriptor in (7, 8):
    try:
        os.fstat(descriptor)
    except OSError as exc:
        assert exc.errno == errno.EBADF, (descriptor, exc)
    else:
        raise AssertionError(f\"lock descriptor leaked as fd {descriptor}\")

marker = Path(sys.argv[1])
release = Path(sys.argv[2]) if sys.argv[2] != \"-\" else None
marker.write_text(\"entered\", encoding=\"utf-8\")
while release is not None and not release.exists():
    time.sleep(0.01)
""",
    encoding="utf-8",
)
first_marker = root / "first"
second_marker = root / "second"
release = root / "release"


def locked_command(marker: Path, release_path: str) -> list[str]:
    return [
        sys.executable,
        str(atomic_file),
        "run-locked",
        "--lock-path",
        str(lock_path),
        "--",
        sys.executable,
        str(worker),
        str(marker),
        release_path,
        str(atomic_file),
        str(lock_path),
    ]


first = subprocess.Popen(locked_command(first_marker, str(release)))
second = None
try:
    deadline = time.monotonic() + 5
    while not first_marker.exists():
        if first.poll() is not None:
            raise AssertionError(f"first locked writer exited early: {first.returncode}")
        if time.monotonic() >= deadline:
            raise AssertionError("first locked writer did not enter")
        time.sleep(0.01)

    first.kill()
    assert first.wait(timeout=5) == -signal.SIGKILL

    # The orphaned worker still owns the inherited high-numbered lock fd. A
    # second cooperative writer must remain blocked until that worker exits.
    lock_status = subprocess.run(
        [
            sys.executable,
            str(atomic_file),
            "lock-status",
            "--lock-path",
            str(lock_path),
        ],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert lock_status.returncode == 0, lock_status
    assert lock_status.stdout == "busy\n", lock_status.stdout
    second = subprocess.Popen(locked_command(second_marker, "-"))
    time.sleep(0.2)
    assert second.poll() is None, second.returncode
    assert not second_marker.exists(), "second cooperative writer bypassed the lock"

    release.write_text("continue", encoding="utf-8")
    assert second.wait(timeout=5) == 0
    assert second_marker.read_text(encoding="utf-8") == "entered"
    lock_stat = os.stat(lock_path, follow_symlinks=False)
    assert stat.S_ISREG(lock_stat.st_mode)

    completed = subprocess.run(
        [
            sys.executable,
            str(atomic_file),
            "run-locked",
            "--lock-path",
            str(lock_path),
            "--",
            sys.executable,
            "-c",
            "import sys; print('locked-output'); sys.exit(37)",
        ],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert completed.returncode == 37, completed
    assert completed.stdout == "locked-output\n", completed.stdout
    assert completed.stderr == "", completed.stderr
    assert lock_path.exists(), "cooperative lock must be retained permanently"

    unrelated_path = root / "unrelated.lock"
    unrelated_fd = os.open(unrelated_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        mismatched = subprocess.run(
            [
                sys.executable,
                str(atomic_file),
                "verify-lock-fd",
                "--lock-path",
                str(lock_path),
                "--lock-fd",
                str(unrelated_fd),
            ],
            pass_fds=(unrelated_fd,),
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert mismatched.returncode == 2, mismatched
        assert "继承的 Host 配置协作锁 fd 与协作锁路径不一致" in mismatched.stderr, mismatched
    finally:
        os.close(unrelated_fd)
finally:
    release.touch(exist_ok=True)
    for process in (first, second):
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
PY
  then
    pass_test
  else
    _fail "run-locked did not serialize cooperative writers or preserve child status"
  fi
}

test_recovery_check_finds_all_unfinished_stages() {
  start_test "atomic-file: check-recovery finds unfinished stages but ignores backups"
  local tmp name out rc
  tmp=$(mktemp -d)
  for name in \
    'hooks.json.pmai-new.crash' \
    '.hooks.json.pmai-cas-stage-crash' \
    '.hooks.json.pmai-write-stage-crash' \
    '.hooks.json.pmai-stage-claim-crash' \
    'hooks.json.bak.20260101.pmai-cleanup-claim-crash'; do
    printf '%s\n' staged > "$tmp/$name"
    out=$(python3 "$ATOMIC_FILE" check-recovery --destination "$tmp/hooks.json" 2>&1)
    rc=$?
    if [ "$rc" -ne 3 ] || ! echo "$out" | grep -Fq "$tmp/$name"; then
      _fail "check-recovery missed unfinished stage $name: rc=$rc out=$out"
      rm -rf "$tmp"
      return
    fi
    rm -f "$tmp/$name"
  done

  printf '%s\n' backup > "$tmp/hooks.json.bak.20260101.retained"
  out=$(python3 "$ATOMIC_FILE" check-recovery --destination "$tmp/hooks.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "check-recovery treated a retained backup as unfinished: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_recovery_check_finds_missing_destination() {
  start_test "atomic-file: check-recovery reports quarantine when destination is missing"
  local tmp out rc recovery
  tmp=$(mktemp -d)
  recovery="$tmp/.hooks.json.pmai-cas-original-crash"
  printf '%s\n' old > "$recovery"
  out=$(python3 "$ATOMIC_FILE" check-recovery --destination "$tmp/hooks.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 3 ] || ! echo "$out" | grep -Fq "$recovery" || [ ! -f "$recovery" ]; then
    _fail "check-recovery missed the exact quarantine path: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_unsupported_syscalls_fail_closed
test_claim_fsync_failure_preserves_recovery_paths
test_claimed_special_files_restore_without_blocking
test_external_stages_are_fsynced_before_rename
test_post_install_missing_destination_reports_exact_recovery
test_replace_postcheck_reports_existing_paths_only
test_cleanup_failure_preserves_primary_error_and_stage
test_prepare_cleanup_reports_only_live_recovery_paths
test_prepare_does_not_unlink_unowned_collision
test_safe_read_write_reject_parent_rebind
test_expected_snapshot_rejects_final_symlinks
test_create_postcheck_reports_existing_paths_only
test_restore_claim_classifies_failures_and_existing_paths
test_prepared_entry_identities_block_name_reuse
test_identity_cleanup_claim_restores_foreign_and_reports_stat_errors
test_generation_identity_rejects_simulated_inode_reuse
test_cleanup_unlink_fsyncs_before_parent_rebind_check
test_cleanup_final_fsync_failure_reports_claim_recovery_path
test_cleanup_removes_stale_generated_recovery_paths
test_zero_progress_writes_fail_closed
test_bound_helpers_recheck_parent_after_entry_validation
test_namespace_mutations_compensate_parent_rebinds
test_delete_claim_compensates_parent_rebind
test_prepare_cli_uses_fixed_fourteen_field_identity_protocol
test_destination_identities_reject_same_content_name_reuse
test_prepare_final_parent_rebind_cleans_owned_entries
test_run_locked_serializes_cooperative_writers
test_recovery_check_finds_all_unfinished_stages
test_recovery_check_finds_missing_destination

report_results "atomic-file"
