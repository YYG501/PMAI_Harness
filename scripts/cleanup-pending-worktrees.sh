#!/usr/bin/env bash
# cleanup-pending-worktrees.sh — 清理由 cancel/pmai-build-close 标记的待清理 build worktree + branch
# 用法: bash scripts/cleanup-pending-worktrees.sh [--dry-run]
#
# 背景：
# cancel/pmai-build-close 不再总是直接删 worktree/branch。原因是 PM 可能在被废弃的
# worktree 内（即 cwd = .worktrees/<branch>）执行 close，删除会让 Claude Code
# 父进程的 cwd 变成 dangling，下一次 Stop hook 的 posix_spawn 报 ENOENT。
# 解决办法是把删除推迟，由本脚本从主仓执行，并确认没有其它进程仍以待删
# worktree 为 cwd 后再清理。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

# --- 主仓根目录 ---
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

if [ -z "$REPO_ROOT" ]; then
  echo "❌ 不在 git 仓库内。" >&2
  exit 1
fi

PENDING_FILE="$REPO_ROOT/.runs/pending-cleanup.json"

if [ ! -f "$PENDING_FILE" ]; then
  echo "✅ 无待清理项。"
  exit 0
fi

CALLER_PWD="$(pwd -P 2>/dev/null || echo "")"

# --- 遍历 entries：成功清理的从列表移除，失败的保留 ---
TMP_RESULT=$(mktemp)
trap 'rm -f "$TMP_RESULT"' EXIT

python3 - "$PENDING_FILE" "$REPO_ROOT" "$DRY_RUN" "$TMP_RESULT" "$SCRIPT_DIR" "$CALLER_PWD" <<'PY'
import atexit
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path, PurePosixPath

pending_file, repo_root, dry_run_str, result_path, script_dir, caller = sys.argv[1:7]
dry_run = dry_run_str == "true"
repo_root_real = os.path.realpath(repo_root)
sys.path.insert(0, script_dir)

from _lib.pending_cleanup import (  # noqa: E402
    PendingCleanupError,
    acquire_queue_lock,
    read_pending_entries,
    replace_pending_entries,
)
from _lib.work_contract import WorkContractError, normalize_work_state

try:
    lock_fd = acquire_queue_lock(Path(pending_file))
    entries = read_pending_entries(Path(pending_file), allow_missing=True)
except PendingCleanupError as exc:
    raise SystemExit(f"待清理队列无法安全读取，拒绝继续: {exc}") from exc
atexit.register(os.close, lock_fd)

if not entries:
    print("✅ 无待清理项。")
else:
    print(f"🧹 待清理项: {len(entries)}")

remaining = []
ok_count = 0
fail_count = 0

def run(cmd, *, input_text=None):
    return subprocess.run(
        cmd, capture_output=True, text=True, input=input_text
    )


SAFE_BRANCH_RE = re.compile(
    r"^build-[A-Za-z0-9][A-Za-z0-9._-]*$"
)
SAFE_OID_RE = re.compile(r"^[0-9a-fA-F]{40,64}$")
SAFE_TRANSACTION_ID_RE = re.compile(r"^[0-9a-f]{32}$")
INTEGRATION_REFS = ("refs/heads/main", "refs/heads/master")


def registered_worktrees():
    """Return branch -> real worktree path from git worktree list --porcelain."""
    r = run(["git", "-C", repo_root, "worktree", "list", "--porcelain"])
    if r.returncode != 0:
        raise SystemExit(
            "git worktree list 查询失败，待清理队列保持不变: "
            f"{r.stderr.strip() or f'exit {r.returncode}'}"
        )
    out = {}
    current_path = None
    for line in r.stdout.splitlines():
        if line.startswith("worktree "):
            current_path = os.path.realpath(line[len("worktree "):])
        elif line.startswith("branch refs/heads/") and current_path:
            branch = line[len("branch refs/heads/"):]
            out[branch] = current_path
    return out


WORKTREES_BY_BRANCH = registered_worktrees()


def integration_ref_exists(integration_ref):
    result = run(
        ["git", "-C", repo_root, "show-ref", "--verify", "--quiet", integration_ref]
    )
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    raise PendingCleanupError(
        f"git show-ref 查询主线 {integration_ref} 失败: "
        f"{result.stderr.strip() or f'exit {result.returncode}'}"
    )


_legacy_integration_ref = None


def legacy_integration_ref():
    """Resolve old queue entries, preferring the main worktree's current branch."""
    global _legacy_integration_ref
    if _legacy_integration_ref is not None:
        return _legacy_integration_ref

    current = run(["git", "-C", repo_root, "symbolic-ref", "--quiet", "HEAD"])
    if current.returncode not in (0, 1):
        raise PendingCleanupError(
            "git symbolic-ref 查询主仓当前分支失败: "
            f"{current.stderr.strip() or f'exit {current.returncode}'}"
        )
    current_ref = current.stdout.strip() if current.returncode == 0 else ""
    candidates = (
        (current_ref, *INTEGRATION_REFS)
        if current_ref in INTEGRATION_REFS
        else INTEGRATION_REFS
    )
    for integration_ref in candidates:
        if integration_ref and integration_ref_exists(integration_ref):
            _legacy_integration_ref = integration_ref
            return integration_ref
    raise PendingCleanupError("主仓缺少 main/master，无法恢复旧待清理记录")


def integration_ref_for_entry(entry):
    value = entry.get("integration_ref", "")
    if value:
        if not isinstance(value, str) or value not in INTEGRATION_REFS:
            raise PendingCleanupError(f"待清理项主线引用不安全: {value!r}")
        return value

    value = legacy_integration_ref()
    entry["integration_ref"] = value
    return value


def capture_integration_point(entry):
    """Resolve the integration ref once; every check uses this exact commit."""
    integration_ref = integration_ref_for_entry(entry)
    result = run(
        [
            "git",
            "-C",
            repo_root,
            "show-ref",
            "--hash",
            "--verify",
            integration_ref,
        ]
    )
    oid = result.stdout.strip().lower()
    if result.returncode == 0 and SAFE_OID_RE.fullmatch(oid):
        return integration_ref, oid
    if result.returncode == 1:
        raise PendingCleanupError(f"待清理项主线引用不存在: {integration_ref}")
    raise PendingCleanupError(
        f"git show-ref 查询主线身份 {integration_ref} 失败: "
        f"{result.stderr.strip() or f'exit {result.returncode}'}"
    )


def branch_exists(branch):
    result = run(
        ["git", "-C", repo_root, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"]
    )
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    raise SystemExit(
        f"git show-ref 查询分支 {branch} 失败，待清理队列保持不变: "
        f"{result.stderr.strip() or f'exit {result.returncode}'}"
    )


def branch_oid(branch):
    result = run(
        [
            "git",
            "-C",
            repo_root,
            "show-ref",
            "--hash",
            "--verify",
            f"refs/heads/{branch}",
        ]
    )
    if result.returncode == 0:
        oid = result.stdout.strip()
        if SAFE_OID_RE.fullmatch(oid):
            return oid.lower()
    raise SystemExit(
        f"git show-ref 查询分支身份 {branch} 失败，待清理队列保持不变: "
        f"{result.stderr.strip() or f'exit {result.returncode}'}"
    )


def branch_is_merged(commit_oid, integration_oid):
    result = run(
        [
            "git",
            "-C",
            repo_root,
            "merge-base",
            "--is-ancestor",
            commit_oid,
            integration_oid,
        ]
    )
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    raise SystemExit(
        f"git merge-base 查询提交 {commit_oid} 与主线提交 {integration_oid} 失败，"
        "待清理队列保持不变: "
        f"{result.stderr.strip() or f'exit {result.returncode}'}"
    )


def safe_module_meta(value):
    if not isinstance(value, str) or "\n" in value or "\r" in value:
        return ""
    path = PurePosixPath(value)
    if (
        not value
        or path.is_absolute()
        or ".." in path.parts
        or len(path.parts) < 4
        or path.parts[:2] != ("docs", "modules")
        or path.name != ".work-meta.json"
    ):
        return ""
    return path.as_posix()


def primary_meta(module_meta, integration_ref, integration_oid):
    listed = run(
        [
            "git",
            "-C",
            repo_root,
            "ls-tree",
            "--name-only",
            "--full-tree",
            integration_oid,
            "--",
            module_meta,
        ]
    )
    if listed.returncode != 0:
        raise PendingCleanupError(
            f"无法从 {integration_ref} 验证状态路径 {module_meta}: "
            f"{listed.stderr.strip() or f'exit {listed.returncode}'}"
        )
    if module_meta not in listed.stdout.splitlines():
        return None
    shown = run(
        ["git", "-C", repo_root, "show", f"{integration_oid}:{module_meta}"]
    )
    if shown.returncode != 0:
        raise PendingCleanupError(
            f"无法从 {integration_ref} 读取状态路径 {module_meta}: "
            f"{shown.stderr.strip() or f'exit {shown.returncode}'}"
        )
    try:
        value = json.loads(shown.stdout)
    except json.JSONDecodeError as exc:
        raise PendingCleanupError(
            f"{integration_ref}:{module_meta} 不是合法 JSON: {exc}"
        ) from exc
    if not isinstance(value, dict):
        raise PendingCleanupError(
            f"{integration_ref}:{module_meta} 顶层必须是对象"
        )
    return value


def prepared_activation_ready(entry, integration_ref, integration_oid):
    branch = entry.get("branch", "")
    if not isinstance(branch, str) or not SAFE_BRANCH_RE.fullmatch(branch):
        raise PendingCleanupError(f"prepared 待清理项分支不安全: {branch!r}")
    activation = entry.get("activation", "")
    module_meta = safe_module_meta(entry.get("module_meta", ""))
    if not module_meta:
        raise PendingCleanupError(
            f"prepared 待清理项状态路径不安全: {entry.get('module_meta', '')!r}"
        )
    transaction_id = entry.get("transaction_id", "")
    if (
        not isinstance(transaction_id, str)
        or not SAFE_TRANSACTION_ID_RE.fullmatch(transaction_id)
    ):
        raise PendingCleanupError(
            "prepared 待清理项缺少安全的事务身份: "
            f"{transaction_id!r}"
        )
    meta = primary_meta(module_meta, integration_ref, integration_oid)
    if activation == "main_meta_absent":
        return meta is None, f"等待 {integration_ref} 删除 {module_meta}"
    if activation != "main_meta_landed":
        raise PendingCleanupError(f"prepared 待清理项激活条件不支持: {activation!r}")
    recorded_oid = entry.get("branch_oid", "")
    if not isinstance(recorded_oid, str) or not SAFE_OID_RE.fullmatch(recorded_oid):
        raise PendingCleanupError(
            f"landed 待清理项缺少安全的原始分支身份: {recorded_oid!r}"
        )
    if not branch_is_merged(recorded_oid, integration_oid):
        return False, f"等待原始分支提交 {recorded_oid} 合入 {integration_ref}"
    if meta is None:
        return True, ""
    try:
        state = normalize_work_state(meta).lifecycle_state
    except WorkContractError as exc:
        raise PendingCleanupError(f"主线工作合同不合法: {exc}") from exc
    if state in {"landed", "documenting"}:
        return True, ""
    return False, f"等待 {integration_ref}:{module_meta} 进入 landed"


# Capture one immutable integration commit per entry. Promotion, validation,
# state reads, and the final ref transaction all share this exact snapshot.
branch_counts = Counter(
    entry.get("branch")
    for entry in entries
    if isinstance(entry.get("branch"), str)
)
integration_ref_upgraded = False
integration_points = {}
integration_point_errors = {}
for entry in entries:
    key = id(entry)
    missing_integration_ref = not entry.get("integration_ref")
    try:
        integration_points[key] = capture_integration_point(entry)
    except PendingCleanupError as exc:
        integration_point_errors[key] = str(exc)
        continue
    if missing_integration_ref:
        integration_ref_upgraded = True

promotion_errors = {}
promotion_waiting = {}
promoted = False
for entry in entries:
    key = id(entry)
    phase = entry.get("phase", "active")
    branch = entry.get("branch", "")
    if phase == "active":
        continue
    if phase != "prepared":
        promotion_errors[key] = f"unsupported phase={phase!r}"
        continue
    if not isinstance(branch, str):
        promotion_errors[key] = f"unsafe branch={branch!r}"
        continue
    if branch_counts[branch] != 1:
        promotion_errors[key] = (
            f"branch has {branch_counts[branch]} queue entries; transaction is ambiguous"
        )
        continue
    if key in integration_point_errors:
        promotion_errors[key] = integration_point_errors[key]
        continue
    integration_ref, integration_oid = integration_points[key]
    try:
        ready, reason = prepared_activation_ready(
            entry, integration_ref, integration_oid
        )
    except PendingCleanupError as exc:
        promotion_errors[key] = str(exc)
        continue
    if not ready:
        promotion_waiting[key] = reason
        continue
    entry["phase"] = "active"
    entry["activated_at"] = dt.datetime.now().astimezone().isoformat(
        timespec="seconds"
    )
    promoted = True

if (integration_ref_upgraded or promoted) and not dry_run:
    try:
        replace_pending_entries(Path(pending_file), entries)
    except (PendingCleanupError, OSError) as exc:
        raise SystemExit(
            f"待清理队列主线绑定或自动激活写回失败，未执行任何删除: {exc}"
        ) from exc

# The caller cwd check must use the same locked queue snapshot as deletion and
# only considers entries that are active after the durable promotion pass.
caller = os.path.realpath(caller) if caller else ""
conflicts = []
for entry in entries:
    if entry.get("phase", "active") != "active":
        continue
    worktree = entry.get("worktree", "")
    if not worktree or not os.path.exists(worktree):
        continue
    real = os.path.realpath(worktree)
    if caller == real or caller.startswith(real + os.sep):
        conflicts.append(worktree)
if conflicts:
    print("❌ 当前 cwd 在以下待清理 worktree 内：", file=sys.stderr)
    for worktree in conflicts:
        print(f"   {worktree}", file=sys.stderr)
    print("", file=sys.stderr)
    print("   清理这些 worktree 会让当前 Claude Code 进程 cwd 变成 dangling。", file=sys.stderr)
    print(f"   请退出当前会话，在主仓 ({repo_root}) 重新打开 Claude Code 后再跑 cleanup。", file=sys.stderr)
    raise SystemExit(1)


def proc_cwd_users(worktree):
    """Return PIDs whose cwd is inside worktree, or None when /proc is unavailable."""
    proc_root = "/proc"
    if not os.path.isdir(proc_root):
        return None
    users = []
    observed = False
    for name in os.listdir(proc_root):
        if not name.isdigit():
            continue
        try:
            cwd = os.path.realpath(os.readlink(os.path.join(proc_root, name, "cwd")))
        except (FileNotFoundError, PermissionError, OSError):
            continue
        observed = True
        if cwd == worktree or cwd.startswith(worktree + os.sep):
            users.append(name)
    return users if observed else None


def lsof_cwd_users(worktree):
    """macOS/BSD fallback: inspect process cwd entries without traversing the worktree."""
    lsof = shutil.which("lsof")
    if not lsof:
        return None
    result = run([lsof, "-nP", "-d", "cwd", "-Fn"])
    if result.returncode not in (0, 1):
        return None
    users = []
    pid = "unknown"
    for line in result.stdout.splitlines():
        if line.startswith("p"):
            pid = line[1:] or "unknown"
        elif line.startswith("n"):
            cwd = os.path.realpath(line[1:])
            if cwd == worktree or cwd.startswith(worktree + os.sep):
                users.append(pid)
    return users


def cwd_users(worktree):
    users = proc_cwd_users(worktree)
    return users if users is not None else lsof_cwd_users(worktree)


def validate_pending_entry(
    entry,
    *,
    branch_present,
    integration_ref,
    integration_oid,
):
    """Fail closed before deleting anything from a pending-cleanup entry."""
    kind = entry.get("kind", "")
    branch = entry.get("branch", "")
    recorded_oid = entry.get("branch_oid", "")
    worktree = entry.get("worktree", "")
    if kind not in {"work", "branch"}:
        return False, f"unsupported kind={kind!r}"
    if not branch or not SAFE_BRANCH_RE.fullmatch(branch):
        return False, f"unsafe branch={branch!r}"
    if branch_counts[branch] != 1:
        return False, (
            f"branch has {branch_counts[branch]} queue entries; transaction is ambiguous"
        )
    if not isinstance(recorded_oid, str) or (
        recorded_oid and not SAFE_OID_RE.fullmatch(recorded_oid)
    ):
        return False, f"invalid branch_oid={recorded_oid!r}"
    if branch_present and not recorded_oid:
        return False, f"live branch has no recorded identity: {branch}"
    if branch_present and recorded_oid and branch_oid(branch) != recorded_oid.lower():
        return False, f"queued branch identity changed: {branch}"
    if "transaction_id" in entry and "activation" not in entry:
        return False, "transaction-bound cleanup is missing its activation evidence"
    if "activation" in entry:
        try:
            ready, reason = prepared_activation_ready(
                entry, integration_ref, integration_oid
            )
        except PendingCleanupError as exc:
            return False, str(exc)
        if not ready:
            return False, f"cleanup activation no longer holds: {reason}"
    registered = WORKTREES_BY_BRANCH.get(branch)
    if kind == "branch":
        if worktree:
            return False, "branch-only cleanup must not include a worktree path"
        if registered is not None:
            return False, f"branch is still registered to worktree {registered}"
        if branch_present and not branch_is_merged(recorded_oid, integration_oid):
            return False, (
                "branch-only cleanup target is not merged into "
                f"{integration_ref}: {branch}"
            )
        return True, ""

    if not worktree:
        if branch_present:
            return False, "live branch has no worktree binding"
        return True, ""

    real = os.path.realpath(worktree)
    protected = {
        os.path.realpath(os.sep),
        repo_root_real,
        os.path.realpath(os.path.expanduser("~")),
    }
    if real in protected:
        return False, f"protected worktree path={real}"

    if not os.path.exists(worktree):
        if registered == real or not branch_present:
            return True, ""
        if registered is None and recorded_oid:
            return True, ""
        return False, (
            "missing worktree path has no stable identity for live branch "
            f"{branch}: path={real}, registered={registered or '<none>'}"
        )
    if registered != real:
        return False, (
            "worktree path is not registered for branch "
            f"{branch}: path={real}, registered={registered or '<none>'}"
        )
    status = run(
        ["git", "-C", real, "status", "--porcelain=v1", "--untracked-files=all"]
    )
    if status.returncode != 0:
        return False, f"cannot verify worktree cleanliness: {status.stderr.strip()}"
    if status.stdout.strip():
        return False, "worktree has uncommitted changes"
    ignored = run(
        [
            "git",
            "-C",
            real,
            "ls-files",
            "--others",
            "--ignored",
            "--exclude-standard",
        ]
    )
    if ignored.returncode != 0:
        return False, f"cannot verify ignored files: {ignored.stderr.strip()}"
    if ignored.stdout.strip():
        return False, "worktree has ignored untracked files"
    users = cwd_users(real)
    if users is None:
        return False, "cannot verify whether another process is using the worktree as cwd"
    if users:
        return False, f"worktree is still used as cwd by pid(s): {', '.join(users)}"
    return True, ""


def delete_branch_with_integration_cas(
    branch,
    recorded_oid,
    integration_ref,
    integration_oid,
):
    commands = "\n".join(
        [
            "start",
            f"verify {integration_ref} {integration_oid}",
            f"delete refs/heads/{branch} {recorded_oid}",
            "prepare",
            "commit",
            "",
        ]
    )
    return run(
        ["git", "-C", repo_root, "update-ref", "--stdin"],
        input_text=commands,
    )


# Persist identity upgrades before the first destructive Git operation. Merely
# mutating ``e`` inside the deletion loop is insufficient: a process crash after
# worktree removal but before the final queue rewrite would strand the on-disk
# legacy entry without enough identity to authorize its branch-only retry.
legacy_identity_upgraded = False
if not dry_run:
    for entry in entries:
        if (
            entry.get("phase", "active") != "active"
            or entry.get("kind") != "work"
            or entry.get("branch_oid")
        ):
            continue
        branch = entry.get("branch", "")
        worktree = entry.get("worktree", "")
        if not isinstance(branch, str) or not SAFE_BRANCH_RE.fullmatch(branch):
            continue
        if not isinstance(worktree, str) or not worktree:
            continue
        real = os.path.realpath(worktree)
        if WORKTREES_BY_BRANCH.get(branch) != real or not branch_exists(branch):
            continue
        entry["branch_oid"] = branch_oid(branch)
        legacy_identity_upgraded = True
    if legacy_identity_upgraded:
        try:
            replace_pending_entries(Path(pending_file), entries)
        except PendingCleanupError as exc:
            raise SystemExit(
                f"待清理队列身份升级写回失败，未执行任何删除: {exc}"
            ) from exc


for e in entries:
    entry_key = id(e)
    branch = e.get("branch", "")
    worktree = e.get("worktree", "")
    kind = e.get("kind", "?")
    label = f"{kind} {branch}"

    phase = e.get("phase", "active")
    if phase != "active":
        remaining.append(e)
        if entry_key in promotion_errors:
            fail_count += 1
            print(
                f"  ❌ {label}: prepared entry invalid: "
                f"{promotion_errors[entry_key]}"
            )
        else:
            print(
                f"  🕓 {label}: "
                f"{promotion_waiting.get(entry_key, '等待状态提交')}"
            )
        continue

    if dry_run:
        print(f"  [dry-run] would clean {label}: worktree={worktree}")
        remaining.append(e)
        continue

    failed = False
    msg_parts = []

    branch_is_safe = isinstance(branch, str) and bool(SAFE_BRANCH_RE.fullmatch(branch))
    branch_present = branch_exists(branch) if branch_is_safe else False
    if entry_key in integration_point_errors:
        failed = True
        msg_parts.append(
            f"unsafe pending entry: {integration_point_errors[entry_key]}"
        )
    else:
        integration_ref, integration_oid = integration_points[entry_key]
        valid, reason = validate_pending_entry(
            e,
            branch_present=branch_present,
            integration_ref=integration_ref,
            integration_oid=integration_oid,
        )
        if not valid:
            failed = True
            msg_parts.append(f"unsafe pending entry: {reason}")

    # 1. 删 worktree（如果还在）
    if not failed and worktree and os.path.isdir(worktree):
        # v2 状态物化：删前先 unlock（创建时 lock 了；幂等）
        run(["git", "-C", repo_root, "worktree", "unlock", worktree])
        r = run(["git", "-C", repo_root, "worktree", "remove", worktree])
        if r.returncode != 0:
            # Git 拒绝删除时保留现场；不能用 rmtree 绕过 dirty/submodule 等保护。
            failed = True
            msg_parts.append(f"worktree remove failed: {r.stderr.strip() or 'unknown error'}")
        else:
            msg_parts.append("worktree removed")
    elif not failed and worktree:
        # worktree 已不在磁盘，prune 残留 metadata
        pruned = run(["git", "-C", repo_root, "worktree", "prune"])
        if pruned.returncode != 0:
            failed = True
            msg_parts.append(f"worktree prune failed: {pruned.stderr.strip() or 'unknown error'}")
        else:
            msg_parts.append("worktree already gone")

    # 2. 删 branch（如果还在）
    if not failed and branch:
        if branch_present:
            recorded_oid = e.get("branch_oid", "")
            r = delete_branch_with_integration_cas(
                branch,
                recorded_oid,
                integration_ref,
                integration_oid,
            )
            if r.returncode != 0:
                failed = True
                msg_parts.append(
                    "integration ref or branch identity changed before atomic delete: "
                    f"{r.stderr.strip() or f'exit {r.returncode}'}"
                )
            else:
                msg_parts.append("branch deleted")
        else:
            msg_parts.append("branch already gone")

    if failed:
        fail_count += 1
        print(f"  ❌ {label}: {'; '.join(msg_parts)}")
        remaining.append(e)
    else:
        ok_count += 1
        print(f"  ✅ {label}: {'; '.join(msg_parts)}")

if not dry_run:
    try:
        replace_pending_entries(Path(pending_file), remaining)
    except PendingCleanupError as exc:
        raise SystemExit(f"待清理队列写回失败，需人工核对: {exc}") from exc

with open(result_path, "w") as f:
    json.dump({"ok": ok_count, "fail": fail_count, "remaining": len(remaining)}, f)
PY

RESULT_FIELDS=$(python3 - "$TMP_RESULT" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    result = json.load(handle)
print(result["ok"])
print(result["fail"])
PY
)
OK=$(printf '%s\n' "$RESULT_FIELDS" | sed -n '1p')
FAIL=$(printf '%s\n' "$RESULT_FIELDS" | sed -n '2p')

if [ "$DRY_RUN" = "true" ]; then
  echo "（dry-run；未做任何改动）"
  exit 0
fi

echo ""
echo "完成：成功 $OK / 失败 $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "⚠️ 有未清理项保留在 ${PENDING_FILE}。请人工检查。" >&2
  exit 1
fi
