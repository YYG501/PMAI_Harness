#!/usr/bin/env python3
"""Freeze an active build candidate before returning upstream to replan."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any

from _lib.pending_cleanup import (
    PendingCleanupError,
    activate_pending_cleanup,
    prepare_pending_cleanup,
    read_pending_entries,
)


ALLOWED_LIFECYCLES = {"building", "iterating", "final_check"}
ALLOWED_ROUTES = {"proposal", "design"}
MAIN_REFS = {"refs/heads/main", "refs/heads/master"}
SCHEMA_VERSION = 1
OID_PATTERN = re.compile(r"[0-9a-f]{40,64}")


class ReplanError(RuntimeError):
    pass


def git_result(root: Path, *args: str) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise ReplanError(f"无法运行 Git（{' '.join(args)}）：{exc}") from exc


def run_git_bytes(root: Path, *args: str) -> bytes:
    result = git_result(root, *args)
    if result.returncode != 0:
        detail = os.fsdecode(result.stderr).strip() or os.fsdecode(result.stdout).strip()
        raise ReplanError(f"Git 命令失败（{' '.join(args)}）：{detail or f'exit {result.returncode}'}")
    return result.stdout


def run_git(root: Path, *args: str) -> str:
    return os.fsdecode(run_git_bytes(root, *args))


def nul_fields(output: bytes, label: str) -> list[bytes]:
    if not output:
        return []
    if not output.endswith(b"\0"):
        raise ReplanError(f"{label}没有使用 NUL 终止，拒绝解析路径。")
    return output[:-1].split(b"\0")


def git_paths(root: Path, *args: str) -> list[str]:
    return [os.fsdecode(value) for value in nul_fields(run_git_bytes(root, *args), "Git 路径输出")]


def status_paths(root: Path) -> list[str]:
    fields = nul_fields(
        run_git_bytes(root, "status", "--porcelain=v1", "-z", "--untracked-files=all"),
        "Git 状态输出",
    )
    paths: list[str] = []
    index = 0
    while index < len(fields):
        record = fields[index]
        index += 1
        if len(record) < 4 or record[2:3] != b" ":
            raise ReplanError(f"无法解析 Git 状态记录：{record!r}")
        try:
            status_code = record[:2].decode("ascii")
        except UnicodeDecodeError as exc:
            raise ReplanError(f"无法解析 Git 状态码：{record[:2]!r}") from exc
        paths.append(os.fsdecode(record[3:]))
        if "R" in status_code or "C" in status_code:
            if index >= len(fields):
                raise ReplanError("Git rename/copy 状态缺少原路径。")
            paths.append(os.fsdecode(fields[index]))
            index += 1
    return paths


def ensure_clean(root: Path, *, allowed_paths: set[str], label: str) -> None:
    dirty = [path for path in status_paths(root) if path not in allowed_paths]
    if dirty:
        raise ReplanError(f"{label}存在未提交改动，不能安全重规划：" + "、".join(dirty))


def parse_worktrees(root: Path) -> list[dict[str, str]]:
    fields = nul_fields(
        run_git_bytes(root, "worktree", "list", "--porcelain", "-z"),
        "Git worktree 输出",
    )
    entries: list[dict[str, str]] = []
    current: dict[str, str] = {}
    for field in [*fields, b""]:
        if not field:
            if current:
                entries.append(current)
                current = {}
            continue
        key_raw, separator, value_raw = field.partition(b" ")
        try:
            key = key_raw.decode("ascii")
        except UnicodeDecodeError as exc:
            raise ReplanError(f"无法解析 Git worktree 字段：{field!r}") from exc
        current[key] = os.fsdecode(value_raw) if separator else ""
    return entries


def find_worktree_for_path(entries: list[dict[str, str]], path: Path) -> Path:
    resolved = path.resolve()
    matches: list[Path] = []
    for entry in entries:
        raw = entry.get("worktree")
        if not raw:
            continue
        candidate = Path(raw).resolve()
        try:
            resolved.relative_to(candidate)
        except ValueError:
            continue
        matches.append(candidate)
    if not matches:
        raise ReplanError("无法唯一定位当前 build 所属 worktree。")
    # Worktrees commonly live below <main>/.worktrees/, so main is also a
    # lexical ancestor. The deepest registered worktree owns the module path.
    deepest = max(matches, key=lambda value: len(value.parts))
    if sum(1 for value in matches if len(value.parts) == len(deepest.parts)) != 1:
        raise ReplanError("无法唯一定位当前 build 所属 worktree。")
    return deepest


def find_main_worktree(entries: list[dict[str, str]]) -> tuple[Path, str]:
    matches = [
        (Path(entry["worktree"]).resolve(), entry.get("branch", "").removeprefix("refs/heads/"))
        for entry in entries
        if entry.get("branch", "") in MAIN_REFS and entry.get("worktree")
    ]
    if not matches:
        raise ReplanError("没有找到已挂载的 main/master worktree，无法安全归位。")
    if len(matches) != 1:
        detail = "、".join(f"{branch}@{path}" for path, branch in matches)
        raise ReplanError(f"main/master 同时挂载，无法唯一确认落地主线：{detail}")
    return matches[0]


def read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise ReplanError(f"缺少{label}：{path}") from None
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ReplanError(f"无法读取{label}：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ReplanError(f"{label}必须是 JSON 对象：{path}")
    return value


def atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    if path.is_symlink():
        raise ReplanError(f"拒绝写入符号链接：{path}")
    fd, temp_name = tempfile.mkstemp(prefix=".replan.", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_path, path)
        fsync_directory(path.parent)
    finally:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass


def fsync_directory(path: Path) -> None:
    directory_fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def ensure_real_directory(root: Path, path: Path, *, create: bool) -> None:
    root = root.resolve()
    try:
        relative = path.relative_to(root)
    except ValueError as exc:
        raise ReplanError(f"候选目录落在仓外：{path}") from exc
    current = root
    for part in relative.parts:
        current = current / part
        try:
            info = current.lstat()
        except FileNotFoundError:
            if not create:
                raise ReplanError(f"候选目录不存在：{current}") from None
            current.mkdir(mode=0o700)
            info = current.lstat()
        if stat.S_ISLNK(info.st_mode):
            raise ReplanError(f"候选目录链包含符号链接，拒绝继续：{current}")
        if not stat.S_ISDIR(info.st_mode):
            raise ReplanError(f"候选目录链不是目录：{current}")
        try:
            current.resolve(strict=True).relative_to(root)
        except ValueError as exc:
            raise ReplanError(f"候选目录解析到仓外：{current}") from exc


def secure_manifest_dir(main_root: Path, *, create: bool) -> Path:
    main_root = main_root.resolve()
    manifest_dir = main_root / ".runs" / "replan-candidates"
    ensure_real_directory(main_root, manifest_dir, create=create)
    for entry in manifest_dir.iterdir():
        info = entry.lstat()
        if stat.S_ISLNK(info.st_mode):
            raise ReplanError(f"候选目录包含符号链接，拒绝继续：{entry}")
        if not stat.S_ISREG(info.st_mode):
            raise ReplanError(f"候选目录包含非普通文件，拒绝继续：{entry}")
    return manifest_dir


def existing_manifest_dir(main_root: Path) -> Path | None:
    main_root = main_root.resolve()
    runs_dir = main_root / ".runs"
    manifest_dir = runs_dir / "replan-candidates"
    for path in (runs_dir, manifest_dir):
        try:
            info = path.lstat()
        except FileNotFoundError:
            return None
        if stat.S_ISLNK(info.st_mode):
            raise ReplanError(f"候选目录链包含符号链接，拒绝继续：{path}")
        if not stat.S_ISDIR(info.st_mode):
            raise ReplanError(f"候选目录链不是目录：{path}")
        try:
            path.resolve(strict=True).relative_to(main_root)
        except ValueError as exc:
            raise ReplanError(f"候选目录解析到仓外：{path}") from exc
    return secure_manifest_dir(main_root, create=False)


def ensure_manifest_file(manifest_dir: Path, path: Path, *, must_exist: bool) -> None:
    if path.parent != manifest_dir:
        raise ReplanError(f"候选 manifest 不在受控目录：{path}")
    try:
        info = path.lstat()
    except FileNotFoundError:
        if must_exist:
            raise ReplanError(f"候选 manifest 不存在：{path}") from None
        return
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ReplanError(f"候选 manifest 必须是仓内普通文件：{path}")


def module_relative(worktree: Path, module_dir: Path) -> str:
    try:
        relative = module_dir.resolve().relative_to(worktree.resolve()).as_posix()
    except ValueError as exc:
        raise ReplanError("模块目录不在当前 build worktree 内。") from exc
    parts = PurePosixPath(relative).parts
    if len(parts) != 3 or parts[:2] != ("docs", "modules"):
        raise ReplanError("模块目录必须是 docs/modules/<模块>/。")
    return relative


def validate_oid(value: object, label: str) -> str:
    if not isinstance(value, str) or not OID_PATTERN.fullmatch(value):
        raise ReplanError(f"{label}不是安全的 Git commit OID。")
    return value


def ensure_commit(root: Path, oid: str, label: str) -> None:
    result = git_result(root, "cat-file", "-e", f"{oid}^{{commit}}")
    if result.returncode != 0:
        raise ReplanError(f"{label}不是当前仓可读取的 commit：{oid}")


def ensure_ancestor(root: Path, ancestor: str, descendant: str) -> None:
    result = git_result(root, "merge-base", "--is-ancestor", ancestor, descendant)
    if result.returncode != 0:
        raise ReplanError("原 baseline 不是候选 HEAD 的祖先，拒绝把两者作为候选差异。")


def build_fields(meta: dict[str, Any]) -> tuple[str, str, str, str]:
    build = meta.get("build")
    if not isinstance(build, dict):
        raise ReplanError("活动工作缺少 build 合同。")
    mode = str(build.get("mode") or "")
    lifecycle = str(build.get("lifecycle_state") or meta.get("lifecycle_state") or "")
    branch = str(build.get("branch") or meta.get("branch") or "")
    baseline = str(build.get("baseline_sha") or "")
    if mode not in {"worktree", "main"}:
        raise ReplanError("build.mode 必须是 worktree 或 main。")
    if lifecycle not in ALLOWED_LIFECYCLES:
        raise ReplanError(
            "上游重规划只支持 building / iterating / final_check；"
            f"当前为 {lifecycle or '<empty>'}。"
        )
    if not branch:
        raise ReplanError(f"{mode} build 缺少 branch。")
    validate_oid(baseline, f"{mode} build baseline_sha")
    return mode, lifecycle, branch, baseline


def pending_entries(main_root: Path) -> list[dict[str, Any]]:
    try:
        return read_pending_entries(main_root / ".runs" / "pending-cleanup.json", allow_missing=True)
    except PendingCleanupError as exc:
        raise ReplanError(f"无法确认待清理队列，拒绝继续：{exc}") from exc


def ensure_not_pending(main_root: Path, branch: str) -> None:
    if any(item.get("branch") == branch for item in pending_entries(main_root)):
        raise ReplanError("该候选分支已进入待清理队列，不能安全重规划。")


def expected_manifest(
    *,
    work_id: str,
    mode: str,
    route: str,
    candidate_head: str,
    baseline_sha: str,
    branch: str,
    worktree: Path,
    module: str,
    main_branch: str,
) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "work_id": work_id,
        "mode": mode,
        "route": route,
        "candidate_head": candidate_head,
        "original_baseline_sha": baseline_sha,
        "branch": branch,
        "worktree": str(worktree),
        "module": module,
        "main_branch": main_branch,
        "created_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
    }


def validate_manifest(manifest: dict[str, Any], expected: dict[str, Any]) -> None:
    if manifest_mode(manifest) != expected.get("mode"):
        raise ReplanError("已有候选 manifest 与本次重规划不一致：mode。")
    for key in (
        "schema_version",
        "work_id",
        "route",
        "original_baseline_sha",
        "branch",
        "worktree",
        "module",
        "main_branch",
    ):
        if manifest.get(key) != expected.get(key):
            raise ReplanError(f"已有候选 manifest 与本次重规划不一致：{key}。")
    validate_oid(manifest.get("candidate_head"), "候选 manifest candidate_head")


def manifest_mode(manifest: dict[str, Any]) -> str:
    # Schema v1 manifests created before main-mode support were all worktree candidates.
    value = manifest.get("mode", "worktree")
    if value not in {"worktree", "main"}:
        raise ReplanError("候选 manifest mode 必须是 worktree 或 main。")
    return str(value)


def validate_manifest_shape(
    manifest: dict[str, Any], manifest_file: Path, main_branch: str, main_root: Path
) -> None:
    if manifest.get("schema_version") != SCHEMA_VERSION:
        raise ReplanError("候选 manifest schema_version 不受支持。")
    work_id = manifest.get("work_id")
    if not isinstance(work_id, str) or Path(work_id).name != work_id:
        raise ReplanError("候选 manifest work_id 不安全。")
    if manifest_file.name != f"{work_id}.json":
        raise ReplanError("候选 manifest 文件名与 work_id 不一致。")
    if manifest.get("route") not in ALLOWED_ROUTES:
        raise ReplanError("候选 manifest route 不合法。")
    if manifest.get("main_branch") != main_branch:
        raise ReplanError("候选 manifest 记录的 main branch 已不匹配。")
    module = manifest.get("module")
    module_parts = PurePosixPath(module).parts if isinstance(module, str) else ()
    if len(module_parts) != 3 or module_parts[:2] != ("docs", "modules"):
        raise ReplanError("候选 manifest module 必须是 docs/modules/<模块>。")
    worktree = manifest.get("worktree")
    if not isinstance(worktree, str) or not Path(worktree).is_absolute():
        raise ReplanError("候选 manifest worktree 必须是绝对路径。")
    branch = manifest.get("branch")
    if not isinstance(branch, str) or not branch:
        raise ReplanError("候选 manifest branch 缺失。")
    mode = manifest_mode(manifest)
    if mode == "main" and (
        branch != main_branch or Path(worktree).resolve() != main_root.resolve()
    ):
        raise ReplanError("main 候选 manifest 的 branch/worktree 与当前主线不一致。")
    validate_oid(manifest.get("candidate_head"), "候选 manifest candidate_head")
    validate_oid(manifest.get("original_baseline_sha"), "候选 manifest original_baseline_sha")


def ensure_candidate_head_retained(root: Path, candidate_head: str) -> None:
    result = git_result(root, "merge-base", "--is-ancestor", candidate_head, "HEAD")
    if result.returncode != 0:
        raise ReplanError("候选分支已不再包含 manifest 记录的 candidate HEAD，拒绝继续。")


def find_recovery_manifest(
    manifest_dir: Path, worktree: Path, module: str, route: str
) -> tuple[Path, dict[str, Any]]:
    matches: list[tuple[Path, dict[str, Any]]] = []
    for path in sorted(manifest_dir.iterdir(), key=lambda value: os.fsencode(value.name)):
        if path.suffix != ".json":
            continue
        ensure_manifest_file(manifest_dir, path, must_exist=True)
        manifest = read_json(path, "候选 manifest")
        if (
            manifest.get("worktree") == str(worktree)
            and manifest.get("module") == module
            and manifest.get("route") == route
        ):
            matches.append((path, manifest))
    if len(matches) != 1:
        raise ReplanError("无法唯一定位旧 build 的可恢复重规划 manifest。")
    return matches[0]


def meta_id(path: Path, label: str) -> str:
    if path.is_symlink() or not path.is_file():
        raise ReplanError(f"{label}必须是普通文件：{path}")
    value = read_json(path, label)
    work_id = value.get("id")
    if not isinstance(work_id, str) or not work_id:
        raise ReplanError(f"{label}缺少 work id。")
    return work_id


def head_meta_id(root: Path, relative_meta: str) -> str | None:
    result = git_result(root, "show", f"HEAD:{relative_meta}")
    if result.returncode != 0:
        return None
    try:
        value = json.loads(result.stdout.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ReplanError(f"HEAD 中的 .work-meta.json 无法读取：{relative_meta}: {exc}") from exc
    work_id = value.get("id") if isinstance(value, dict) else None
    if not isinstance(work_id, str) or not work_id:
        raise ReplanError(f"HEAD 中的 .work-meta.json 缺少 work id：{relative_meta}")
    return work_id


def staged_paths(root: Path) -> list[str]:
    return git_paths(root, "diff", "--cached", "--name-only", "-z")


def staged_deletions(root: Path) -> list[str]:
    return git_paths(root, "diff", "--cached", "--diff-filter=D", "--name-only", "-z")


def remove_meta_and_commit(
    root: Path,
    relative_meta: str,
    message: str,
    *,
    expected_work_id: str,
    preserve_other_work: bool,
) -> str:
    path = root / relative_meta
    staged = staged_paths(root)
    if staged and staged != [relative_meta]:
        raise ReplanError("重规划提交只能包含 .work-meta.json；暂存区存在其它路径。")

    if os.path.lexists(path):
        current_id = meta_id(path, ".work-meta.json")
        if staged or relative_meta in status_paths(root):
            raise ReplanError(".work-meta.json 存在非事务内改动，拒绝删除。")
        if current_id != expected_work_id:
            if preserve_other_work:
                return "new_work_preserved"
            raise ReplanError("旧 worktree 的 .work-meta.json 已指向另一项工作，拒绝删除。")
        run_git_bytes(root, "rm", "-q", "--", relative_meta)
    elif staged:
        if staged_deletions(root) != [relative_meta]:
            raise ReplanError(".work-meta.json 已不在工作区，但 index 不是预期的 staged deletion。")
        current_id = head_meta_id(root, relative_meta)
        if current_id != expected_work_id:
            raise ReplanError("index 中待提交的删除属于另一项工作，拒绝提交。")
    else:
        current_id = head_meta_id(root, relative_meta)
        if current_id is None:
            return "already_absent"
        raise ReplanError(".work-meta.json 已从工作区消失但删除未进入 index，拒绝假定事务完成。")

    if staged_paths(root) != [relative_meta] or staged_deletions(root) != [relative_meta]:
        raise ReplanError("git rm 后 index 未形成唯一的 .work-meta.json 删除，拒绝提交。")
    run_git_bytes(root, "commit", "-m", message, "--", relative_meta)
    if staged_paths(root):
        raise ReplanError("重规划 commit 后 index 仍有暂存内容，事务未完成。")
    if os.path.lexists(path) or head_meta_id(root, relative_meta) is not None:
        raise ReplanError("重规划 commit 后 .work-meta.json 仍存在，事务未完成。")
    return "removed"


def perform(args: argparse.Namespace) -> dict[str, Any]:
    module_dir = Path(args.module_dir).expanduser().resolve()
    entries = parse_worktrees(module_dir)
    old_worktree = find_worktree_for_path(entries, module_dir)
    main_root, main_branch = find_main_worktree(entries)
    module = module_relative(old_worktree, module_dir)
    relative_meta = f"{module}/.work-meta.json"
    old_meta_path = old_worktree / relative_meta
    main_meta_path = main_root / relative_meta
    actual_branch = run_git(old_worktree, "symbolic-ref", "--quiet", "--short", "HEAD").strip()
    if not actual_branch:
        raise ReplanError("旧 build worktree 处于 detached HEAD，拒绝重规划。")

    recovered = not os.path.lexists(old_meta_path)
    if recovered:
        manifest_dir = secure_manifest_dir(main_root, create=False)
        manifest_file, existing_manifest = find_recovery_manifest(
            manifest_dir, old_worktree, module, args.route
        )
        mode = manifest_mode(existing_manifest)
        work_id = str(existing_manifest.get("work_id") or "")
        branch = str(existing_manifest.get("branch") or "")
        baseline_sha = validate_oid(
            existing_manifest.get("original_baseline_sha"), "候选 manifest original_baseline_sha"
        )
        if not work_id or Path(work_id).name != work_id or not branch:
            raise ReplanError("候选 manifest 缺少可恢复的 work id 或 branch。")
        expected = expected_manifest(
            work_id=work_id,
            mode=mode,
            route=args.route,
            candidate_head=str(existing_manifest.get("candidate_head") or ""),
            baseline_sha=baseline_sha,
            branch=branch,
            worktree=old_worktree,
            module=module,
            main_branch=main_branch,
        )
        validate_manifest(existing_manifest, expected)
    else:
        old_meta = read_json(old_meta_path, "旧 worktree .work-meta.json")
        mode, _, branch, baseline_sha = build_fields(old_meta)
        if mode == "main" and old_worktree != main_root:
            raise ReplanError("build 合同声明 main mode，但活动模块不在 main worktree。")
        if mode == "worktree" and old_worktree == main_root:
            raise ReplanError("build 合同声明 worktree mode，但活动模块位于 main。")
        if branch != actual_branch:
            raise ReplanError("build 合同 branch 与旧 worktree 当前分支不一致。")
        if mode == "main" and branch != main_branch:
            raise ReplanError("main mode build 的 branch 与唯一落地主线不一致。")
        work_id = str(old_meta.get("id") or "")
        if not work_id or Path(work_id).name != work_id:
            raise ReplanError("活动工作缺少安全的唯一 work id。")
        candidate_head = validate_oid(
            run_git(old_worktree, "rev-parse", "HEAD").strip(), "候选 HEAD"
        )
        expected = expected_manifest(
            work_id=work_id,
            mode=mode,
            route=args.route,
            candidate_head=candidate_head,
            baseline_sha=baseline_sha,
            branch=branch,
            worktree=old_worktree,
            module=module,
            main_branch=main_branch,
        )
        ensure_clean(main_root, allowed_paths=set(), label="main")
        if mode == "worktree":
            ensure_clean(old_worktree, allowed_paths=set(), label="旧 worktree")
            if not os.path.lexists(main_meta_path):
                raise ReplanError("main 缺少对应 .work-meta.json，不能建立可恢复的重规划交接。")
            if meta_id(main_meta_path, "main .work-meta.json") != work_id:
                raise ReplanError("main .work-meta.json 与旧 build 的 work id 不一致。")
        manifest_dir = secure_manifest_dir(main_root, create=True)
        manifest_file = manifest_dir / f"{work_id}.json"
        ensure_manifest_file(manifest_dir, manifest_file, must_exist=False)
        existing_manifest = None

    if branch != actual_branch:
        raise ReplanError("候选 manifest branch 与旧 worktree 当前分支不一致。")
    if mode == "main" and (old_worktree != main_root or branch != main_branch):
        raise ReplanError("main 候选与唯一挂载的主线不一致。")
    if mode == "worktree" and old_worktree == main_root:
        raise ReplanError("worktree 候选不能位于 main。")
    ensure_commit(old_worktree, baseline_sha, "原 baseline")

    if not recovered and manifest_file.exists():
        ensure_manifest_file(manifest_dir, manifest_file, must_exist=True)
        existing_manifest = read_json(manifest_file, "候选 manifest")
        expected["candidate_head"] = existing_manifest.get("candidate_head")
        validate_manifest(existing_manifest, expected)
        recovered = True
    elif not recovered:
        ensure_not_pending(main_root, branch)
        atomic_write_json(manifest_file, expected)
        existing_manifest = expected

    candidate_head = validate_oid(existing_manifest.get("candidate_head"), "候选 HEAD")
    ensure_commit(old_worktree, candidate_head, "候选 HEAD")
    ensure_ancestor(old_worktree, baseline_sha, candidate_head)
    ensure_candidate_head_retained(old_worktree, candidate_head)
    ensure_clean(main_root, allowed_paths={relative_meta}, label="main")
    if mode == "worktree":
        ensure_clean(old_worktree, allowed_paths={relative_meta}, label="旧 worktree")
    ensure_not_pending(main_root, branch)

    old_disposition = remove_meta_and_commit(
        old_worktree,
        relative_meta,
        f"replan: preserve {mode} candidate {work_id} for {args.route}",
        expected_work_id=work_id,
        preserve_other_work=recovered and mode == "main",
    )
    if mode == "worktree":
        main_disposition = remove_meta_and_commit(
            main_root,
            relative_meta,
            f"replan: retire active work {work_id} for {args.route}",
            expected_work_id=work_id,
            preserve_other_work=recovered,
        )
    else:
        main_disposition = old_disposition
    ensure_not_pending(main_root, branch)

    return {
        "schema_version": SCHEMA_VERSION,
        "status": "replanned",
        "mode": mode,
        "route": args.route,
        "work_id": work_id,
        "candidate_manifest": str(manifest_file),
        "candidate_manifest_relative": manifest_file.relative_to(main_root).as_posix(),
        "candidate_head": candidate_head,
        "original_baseline_sha": baseline_sha,
        "branch": branch,
        "worktree": str(old_worktree),
        "module": module,
        "main_branch": main_branch,
        "old_worktree_meta_removed": old_disposition in {"removed", "already_absent"},
        "main_meta_removed": main_disposition in {"removed", "already_absent"},
        "main_meta_preserved": main_disposition == "new_work_preserved",
        "candidate_preserved": True,
        "pending_cleanup_enqueued": False,
        "recovered": recovered,
    }


def manifest_location(raw: str) -> tuple[Path, Path, str, dict[str, Any]]:
    expanded = Path(raw).expanduser()
    requested_file = Path(os.path.abspath(expanded))
    if requested_file.suffix != ".json" or requested_file.parent.name != "replan-candidates":
        raise ReplanError("候选 manifest 必须是 .runs/replan-candidates/<work-id>.json。")
    if requested_file.parent.parent.name != ".runs":
        raise ReplanError("候选 manifest 必须位于 main 的 .runs/replan-candidates/。")
    main_root = requested_file.parent.parent.parent
    entries = parse_worktrees(main_root)
    detected_main, main_branch = find_main_worktree(entries)
    if detected_main != main_root.resolve():
        raise ReplanError("候选 manifest 不在唯一挂载的 main/master worktree 内。")
    for component in (requested_file.parent.parent, requested_file.parent):
        try:
            info = component.lstat()
        except FileNotFoundError:
            raise ReplanError(f"候选 manifest 目录不存在：{component}") from None
        if stat.S_ISLNK(info.st_mode):
            raise ReplanError(f"候选 manifest 路径包含符号链接：{component}")
    manifest_dir = secure_manifest_dir(detected_main, create=False)
    if requested_file.parent.resolve(strict=True) != manifest_dir:
        raise ReplanError("候选 manifest 路径解析结果不在受控目录。")
    manifest_file = manifest_dir / requested_file.name
    ensure_manifest_file(manifest_dir, manifest_file, must_exist=True)
    manifest = read_json(manifest_file, "候选 manifest")
    validate_manifest_shape(manifest, manifest_file, main_branch, detected_main)
    return detected_main, manifest_file, main_branch, manifest


def list_candidates(args: argparse.Namespace) -> dict[str, Any]:
    requested = Path(args.main_root).expanduser().resolve()
    entries = parse_worktrees(requested)
    main_root, main_branch = find_main_worktree(entries)
    manifest_dir = existing_manifest_dir(main_root)
    candidates: list[dict[str, Any]] = []
    if manifest_dir is not None:
        for manifest_file in sorted(
            manifest_dir.iterdir(), key=lambda value: os.fsencode(value.name)
        ):
            if manifest_file.suffix != ".json":
                continue
            ensure_manifest_file(manifest_dir, manifest_file, must_exist=True)
            manifest = read_json(manifest_file, "候选 manifest")
            validate_manifest_shape(manifest, manifest_file, main_branch, main_root)
            retirement = manifest.get("retirement")
            candidates.append(
                {
                    "work_id": manifest["work_id"],
                    "mode": manifest_mode(manifest),
                    "route": manifest["route"],
                    "module": manifest["module"],
                    "candidate_manifest": str(manifest_file),
                    "candidate_manifest_relative": manifest_file.relative_to(main_root).as_posix(),
                    "original_baseline_sha": manifest["original_baseline_sha"],
                    "candidate_head": manifest["candidate_head"],
                    "branch": manifest["branch"],
                    "worktree": manifest["worktree"],
                    "created_at": manifest.get("created_at"),
                    "retirement_status": (
                        retirement.get("status") if isinstance(retirement, dict) else None
                    ),
                }
            )
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "candidate_list",
        "main_root": str(main_root),
        "main_branch": main_branch,
        "count": len(candidates),
        "candidates": candidates,
        "read_only": True,
    }


def live_candidate(main_root: Path, manifest: dict[str, Any]) -> Path:
    if manifest_mode(manifest) == "main":
        candidate_head = validate_oid(manifest.get("candidate_head"), "候选 HEAD")
        baseline = validate_oid(manifest.get("original_baseline_sha"), "原 baseline")
        ensure_commit(main_root, candidate_head, "候选 HEAD")
        ensure_commit(main_root, baseline, "原 baseline")
        ensure_ancestor(main_root, baseline, candidate_head)
        ensure_candidate_head_retained(main_root, candidate_head)
        return main_root
    worktree_raw = manifest.get("worktree")
    branch = manifest.get("branch")
    if not isinstance(worktree_raw, str) or not Path(worktree_raw).is_absolute():
        raise ReplanError("候选 manifest worktree 必须是绝对路径。")
    if not isinstance(branch, str) or not branch:
        raise ReplanError("候选 manifest branch 缺失。")
    worktree = Path(worktree_raw).resolve()
    matches = [
        entry
        for entry in parse_worktrees(main_root)
        if entry.get("worktree") and Path(entry["worktree"]).resolve() == worktree
    ]
    if len(matches) != 1 or matches[0].get("branch") != f"refs/heads/{branch}":
        raise ReplanError("候选 worktree/branch 已不存在或与 manifest 不一致。")
    candidate_head = validate_oid(manifest.get("candidate_head"), "候选 HEAD")
    baseline = validate_oid(manifest.get("original_baseline_sha"), "原 baseline")
    ensure_commit(worktree, candidate_head, "候选 HEAD")
    ensure_commit(worktree, baseline, "原 baseline")
    ensure_ancestor(worktree, baseline, candidate_head)
    ensure_candidate_head_retained(worktree, candidate_head)
    return worktree


def inspect_candidate(args: argparse.Namespace) -> dict[str, Any]:
    main_root, manifest_file, _, manifest = manifest_location(args.manifest)
    worktree = live_candidate(main_root, manifest)
    baseline = str(manifest["original_baseline_sha"])
    candidate_head = str(manifest["candidate_head"])
    changed_paths = git_paths(
        worktree, "diff", "--name-only", "-z", baseline, candidate_head, "--"
    )
    patch = run_git(
        worktree,
        "-c",
        "core.quotePath=false",
        "diff",
        "--no-ext-diff",
        "--binary",
        baseline,
        candidate_head,
        "--",
    )
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "candidate_inspected",
        "work_id": manifest["work_id"],
        "mode": manifest_mode(manifest),
        "route": manifest["route"],
        "candidate_manifest": str(manifest_file),
        "candidate_manifest_relative": manifest_file.relative_to(main_root).as_posix(),
        "diff_range": f"{baseline}..{candidate_head}",
        "original_baseline_sha": baseline,
        "candidate_head": candidate_head,
        "branch": manifest["branch"],
        "worktree": str(worktree),
        "module": manifest["module"],
        "changed_paths": changed_paths,
        "diff": patch,
        "read_only": True,
    }


def ensure_candidate_frozen(worktree: Path, manifest: dict[str, Any]) -> None:
    ensure_clean(worktree, allowed_paths=set(), label="候选 worktree")
    module_meta = f"{manifest['module']}/.work-meta.json"
    if os.path.lexists(worktree / module_meta):
        raise ReplanError("候选 worktree 仍有 active .work-meta.json，不能退役。")
    candidate_head = str(manifest["candidate_head"])
    branch_head = validate_oid(run_git(worktree, "rev-parse", "HEAD").strip(), "候选分支 HEAD")
    post_candidate = git_paths(
        worktree, "diff", "--name-only", "-z", candidate_head, branch_head, "--"
    )
    if any(path != module_meta for path in post_candidate):
        raise ReplanError("冻结候选之后又出现实现改动，必须先重新核对，不能直接退役。")


def matching_queue_entry(
    entries: list[dict[str, Any]], manifest: dict[str, Any], main_branch: str
) -> dict[str, Any] | None:
    branch = str(manifest["branch"])
    matches = [entry for entry in entries if entry.get("branch") == branch]
    if not matches:
        return None
    if len(matches) != 1:
        raise ReplanError("候选分支存在多条待清理记录，拒绝猜测。")
    entry = matches[0]
    expected = {
        "kind": "work",
        "branch": branch,
        "worktree": str(manifest["worktree"]),
        "work_dir": str(Path(str(manifest["worktree"])) / str(manifest["module"])),
        "integration_ref": f"refs/heads/{main_branch}",
    }
    for key, value in expected.items():
        if entry.get(key) != value:
            raise ReplanError(f"候选分支已有不一致的待清理记录：{key}。")
    if entry.get("phase", "active") not in {"prepared", "active"}:
        raise ReplanError("候选分支待清理记录阶段不合法。")
    return entry


def remove_manifest(manifest_file: Path, main_root: Path) -> None:
    manifest_dir = secure_manifest_dir(main_root, create=False)
    ensure_manifest_file(manifest_dir, manifest_file, must_exist=True)
    manifest_file.unlink()
    fsync_directory(manifest_dir)


def retire_candidate(args: argparse.Namespace) -> dict[str, Any]:
    if not args.reconciled:
        raise ReplanError("只有明确确认旧候选已逐项 reconcile 后，才可退役；请传 --reconciled。")
    main_root, manifest_file, main_branch, manifest = manifest_location(args.manifest)
    mode = manifest_mode(manifest)
    if mode == "main":
        live_candidate(main_root, manifest)
        remove_manifest(manifest_file, main_root)
        return {
            "schema_version": SCHEMA_VERSION,
            "status": "candidate_retired",
            "work_id": manifest["work_id"],
            "mode": mode,
            "candidate_head": manifest["candidate_head"],
            "branch": manifest["branch"],
            "worktree": manifest["worktree"],
            "module": manifest["module"],
            "candidate_manifest": str(manifest_file),
            "candidate_manifest_relative": manifest_file.relative_to(main_root).as_posix(),
            "reconciled": True,
            "manifest_removed": True,
            "pending_cleanup_enqueued": False,
            "cleanup_already_complete": False,
        }
    queue_file = main_root / ".runs" / "pending-cleanup.json"
    queue_entry = matching_queue_entry(pending_entries(main_root), manifest, main_branch)
    cleanup_already_complete = False

    if queue_entry is None:
        try:
            worktree = live_candidate(main_root, manifest)
        except ReplanError:
            retirement = manifest.get("retirement")
            branch_exists = git_result(
                main_root, "show-ref", "--verify", "--quiet", f"refs/heads/{manifest['branch']}"
            ).returncode == 0
            worktree_exists = Path(str(manifest["worktree"])).exists()
            if isinstance(retirement, dict) and retirement.get("reconciled") is True and not branch_exists and not worktree_exists:
                cleanup_already_complete = True
                worktree = None
            else:
                raise
        if not cleanup_already_complete:
            ensure_candidate_frozen(worktree, manifest)
            retirement = manifest.get("retirement")
            if not isinstance(retirement, dict) or retirement.get("reconciled") is not True:
                manifest["retirement"] = {
                    "reconciled": True,
                    "confirmed_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
                    "status": "preparing_cleanup",
                }
                atomic_write_json(manifest_file, manifest)
            try:
                transaction_id = prepare_pending_cleanup(
                    queue_file,
                    kind="work",
                    branch=str(manifest["branch"]),
                    worktree=str(manifest["worktree"]),
                    work_dir=str(Path(str(manifest["worktree"])) / str(manifest["module"])),
                    integration_ref=f"refs/heads/{main_branch}",
                    activation="main_meta_absent",
                    module_meta=f"{manifest['module']}/.work-meta.json",
                )
            except PendingCleanupError as exc:
                raise ReplanError(f"无法把候选送入待清理队列：{exc}") from exc
            manifest["retirement"]["cleanup_transaction_id"] = transaction_id
            atomic_write_json(manifest_file, manifest)
            queue_entry = matching_queue_entry(pending_entries(main_root), manifest, main_branch)

    if queue_entry is not None and queue_entry.get("phase", "active") == "prepared":
        transaction_id = queue_entry.get("transaction_id")
        if not isinstance(transaction_id, str) or not transaction_id:
            raise ReplanError("prepared 待清理记录缺少 transaction_id。")
        try:
            activate_pending_cleanup(
                queue_file, branch=str(manifest["branch"]), transaction_id=transaction_id
            )
        except PendingCleanupError as exc:
            raise ReplanError(f"无法激活候选待清理记录：{exc}") from exc

    remove_manifest(manifest_file, main_root)
    return {
        "schema_version": SCHEMA_VERSION,
        "status": "candidate_retired",
        "work_id": manifest["work_id"],
        "mode": mode,
        "candidate_head": manifest["candidate_head"],
        "branch": manifest["branch"],
        "worktree": manifest["worktree"],
        "module": manifest["module"],
        "candidate_manifest": str(manifest_file),
        "candidate_manifest_relative": manifest_file.relative_to(main_root).as_posix(),
        "reconciled": True,
        "manifest_removed": True,
        "pending_cleanup_enqueued": not cleanup_already_complete,
        "cleanup_already_complete": cleanup_already_complete,
    }


def parser(argv: list[str] | None = None) -> argparse.Namespace:
    arguments = list(sys.argv[1:] if argv is None else argv)
    commands = {"start", "list", "inspect", "retire"}
    if arguments and arguments[0] not in commands and arguments[0] not in {"-h", "--help"}:
        arguments.insert(0, "start")

    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)
    start = subparsers.add_parser("start", help="冻结 active build 候选并返回上游")
    start.add_argument("module_dir", help="旧 build worktree 内 docs/modules/<模块> 目录")
    start.add_argument("--route", choices=sorted(ALLOWED_ROUTES), required=True)
    start.set_defaults(handler=perform)
    list_command = subparsers.add_parser("list", help="只读列出 main 中全部冻结候选")
    list_command.add_argument("main_root", nargs="?", default=".")
    list_command.set_defaults(handler=list_candidates)
    inspect = subparsers.add_parser("inspect", help="只读输出 baseline..candidate diff")
    inspect.add_argument("manifest", help="replan 返回的 candidate_manifest")
    inspect.set_defaults(handler=inspect_candidate)
    retire = subparsers.add_parser("retire", help="已 reconcile 后退役候选")
    retire.add_argument("manifest", help="replan 返回的 candidate_manifest")
    retire.add_argument("--reconciled", action="store_true", help="确认候选差异已逐项采用或明确放弃")
    retire.set_defaults(handler=retire_candidate)
    return result.parse_args(arguments)


def main() -> int:
    args = parser()
    try:
        print(json.dumps(args.handler(args), ensure_ascii=False))
    except ReplanError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
