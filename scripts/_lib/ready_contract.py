"""Shared validation for the design-to-build ready contract.

The ready contract is deliberately smaller than the build contract.  It binds
the approved design inputs to the exact implementation paths that the next
build may touch.  Both status and build use this module so they cannot disagree
about whether a ready design is still current.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from .work_contract import WorkContractError, normalize_work_state


class ReadyContractError(ValueError):
    """Raised when a ready-to-build handoff is missing, stale, or ambiguous."""


def lifecycle_state(meta: dict[str, Any]) -> str:
    try:
        return normalize_work_state(meta).lifecycle_state
    except WorkContractError as exc:
        raise ReadyContractError(str(exc)) from exc


def normalize_paths(values: object, label: str = "approved_target.paths") -> list[str]:
    if not isinstance(values, list):
        raise ReadyContractError(f"{label} 必须是非空路径数组。")
    result: list[str] = []
    seen: set[str] = set()
    for index, value in enumerate(values):
        if not isinstance(value, str) or not value.strip():
            raise ReadyContractError(f"{label}[{index}] 必须是仓内相对路径。")
        path = Path(value.strip())
        if path.is_absolute() or ".." in path.parts:
            raise ReadyContractError(f"{label}[{index}] 必须是仓内相对路径：{value}")
        normalized = path.as_posix().rstrip("/") or "."
        if normalized not in seen:
            seen.add(normalized)
            result.append(normalized)
    if not result:
        raise ReadyContractError(f"{label} 不能为空；请回到 /pmai-design 固定本轮目标页面或代码路径。")
    return result


def approved_target_paths(meta: dict[str, Any]) -> list[str]:
    target = meta.get("approved_target")
    if not isinstance(target, dict):
        raise ReadyContractError("ready 状态缺少 approved_target；请回到 /pmai-design 重新固定建造范围。")
    return normalize_paths(target.get("paths"))


def load_context_pack(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ReadyContractError(f"缺少最新 context pack：{path}") from exc
    except json.JSONDecodeError as exc:
        raise ReadyContractError(f"context pack 不是合法 JSON：{path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise ReadyContractError("context pack 顶层必须是对象。")
    return payload


def _module_relative(repo_root: Path, module_dir: Path) -> str:
    try:
        return module_dir.expanduser().resolve().relative_to(repo_root.expanduser().resolve()).as_posix()
    except ValueError as exc:
        raise ReadyContractError(f"模块目录不在仓库内：{module_dir}") from exc


def validate_ready_pack(
    repo_root: Path,
    module_dir: Path,
    meta: dict[str, Any],
    pack: dict[str, Any],
    *,
    allowed_states: set[str] | None = None,
    expected_pack_approved_hash: str | None = None,
    expected_current_source_hash: str | None = None,
) -> dict[str, Any]:
    accepted_states = allowed_states or {"ready_to_build"}
    current_lifecycle = lifecycle_state(meta)
    if current_lifecycle not in accepted_states:
        raise ReadyContractError(
            f"当前模块 lifecycle={current_lifecycle or '<empty>'}；"
            f"此校验只接受 {', '.join(sorted(accepted_states))}。"
        )

    approved_hash = str(meta.get("approved_source_hash") or "").strip()
    if not approved_hash:
        raise ReadyContractError("ready 状态缺少 approved_source_hash；请回到 /pmai-design 重新固定建造依据。")
    current_hash = str(pack.get("source_hash") or "").strip()
    if not current_hash:
        raise ReadyContractError("最新 context pack 缺少 source_hash，不能确认设计是否仍有效。")
    build = meta.get("build") if isinstance(meta.get("build"), dict) else {}
    try:
        expected_hash_version = int(
            build.get("source_hash_version") or meta.get("source_hash_version") or 1
        )
        pack_hash_version = int(pack.get("source_hash_version") or 1)
    except (TypeError, ValueError) as exc:
        raise ReadyContractError("当前工作或 context pack 的 source_hash_version 不合法。") from exc
    if pack_hash_version != expected_hash_version:
        raise ReadyContractError("context pack 与当前工作使用的 source hash 版本不一致。")

    expected_module = _module_relative(repo_root, module_dir)
    if pack.get("module") != expected_module:
        raise ReadyContractError(
            f"context pack 绑定模块不一致：期望 {expected_module}，实际 {pack.get('module') or '<empty>'}。"
        )
    expected_current_hash = (
        str(expected_current_source_hash).strip()
        if expected_current_source_hash is not None
        else approved_hash
    )
    if current_hash != expected_current_hash:
        raise ReadyContractError("设计依据在批准后发生变化；请回到 /pmai-design 重新核对并固定建造起点。")

    pack_approved = str(pack.get("approved_source_hash") or "").strip()
    expected_pack_hash = (
        str(expected_pack_approved_hash).strip()
        if expected_pack_approved_hash is not None
        else approved_hash
    )
    if pack_approved and pack_approved != expected_pack_hash:
        raise ReadyContractError("context pack 与模块状态记录的 approved_source_hash 不一致。")

    target_paths = approved_target_paths(meta)
    pack_target = pack.get("target")
    if isinstance(pack_target, dict) and pack_target.get("paths") not in (None, []):
        pack_paths = normalize_paths(pack_target.get("paths"), "context_pack.target.paths")
        if pack_paths != target_paths:
            raise ReadyContractError("context pack 的目标路径与 design 批准范围不一致。")

    return {
        "state": "current",
        "approved_source_hash": approved_hash,
        "current_source_hash": current_hash,
        "source_hash_version": expected_hash_version,
        "design_revision": int(meta.get("design_revision") or 1),
        "target_paths": target_paths,
    }


def compile_current_context_pack(repo_root: Path, module_dir: Path) -> dict[str, Any]:
    script = Path(__file__).resolve().parents[1] / "context-pack.py"
    result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--repo-root",
            str(repo_root),
            "--module",
            str(module_dir),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "context pack 编译失败"
        raise ReadyContractError(detail)
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ReadyContractError("context pack 编译结果不是合法 JSON。") from exc
    if not isinstance(payload, dict):
        raise ReadyContractError("context pack 编译结果顶层必须是对象。")
    return payload


def ready_currentness(repo_root: Path, module_dir: Path, meta: dict[str, Any]) -> dict[str, Any]:
    try:
        pack = compile_current_context_pack(repo_root, module_dir)
        return validate_ready_pack(repo_root, module_dir, meta, pack)
    except ReadyContractError as exc:
        return {"state": "stale", "reason": str(exc)}


def _git_names(repo_root: Path, *args: str) -> set[str]:
    result = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise ReadyContractError(detail or "无法读取 Git 工作区状态。")
    return {
        item.decode("utf-8", errors="surrogateescape")
        for item in result.stdout.split(b"\0")
        if item
    }


def changed_paths(repo_root: Path) -> list[str]:
    paths = set()
    paths.update(_git_names(repo_root, "diff", "--name-only", "-z"))
    paths.update(_git_names(repo_root, "diff", "--cached", "--name-only", "-z"))
    paths.update(_git_names(repo_root, "ls-files", "--others", "--exclude-standard", "-z"))
    return sorted(Path(path).as_posix() for path in paths)


def _overlaps(left: str, right: str) -> bool:
    left = left.rstrip("/")
    right = right.rstrip("/")
    return left == right or left.startswith(right + "/") or right.startswith(left + "/")


def classify_dirty_paths(repo_root: Path, target_paths: list[str]) -> dict[str, list[str]]:
    changed = changed_paths(repo_root)
    overlapping = [path for path in changed if any(_overlaps(path, target) for target in target_paths)]
    unrelated = [path for path in changed if path not in overlapping]
    return {"overlapping": overlapping, "unrelated": unrelated}
