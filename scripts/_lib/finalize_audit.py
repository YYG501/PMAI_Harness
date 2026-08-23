"""Shared helpers for binding and reviewing finalize audit evidence."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any, Mapping


def canonical(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_revision(root: Path) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        detail = result.stderr.strip() or "无法读取 Git revision。"
        raise ValueError(detail)
    return result.stdout.strip()


def git_clean(root: Path, ignore_paths: list[str] | None = None) -> bool:
    pathspecs = ["."] + [f":(exclude){path}" for path in (ignore_paths or [])]
    result = subprocess.run(
        [
            "git",
            "-C",
            str(root),
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
            "--",
            *pathspecs,
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "无法读取 Git worktree 状态。"
        raise ValueError(detail)
    return not bool(result.stdout.strip())


def tool_file_hashes(root: Path, paths: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    resolved_root = root.expanduser().resolve()
    for raw in paths:
        path = (resolved_root / raw).resolve()
        try:
            path.relative_to(resolved_root)
        except ValueError as exc:
            raise ValueError(f"工具源码越出框架仓：{raw}") from exc
        if not path.is_file():
            raise ValueError(f"工具源码不存在：{raw}")
        result[raw] = file_digest(path)
    return result


def read_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"{label} 不存在：{path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} 不是合法 JSON：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{label} 顶层必须是对象：{path}")
    return value


def resolve_audit_dir(consumer_root: Path, raw: str) -> Path:
    root = consumer_root.expanduser().resolve()
    candidate = Path(raw).expanduser()
    resolved = (candidate if candidate.is_absolute() else root / candidate).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ValueError("audit 目录必须位于消费仓内。") from exc
    if not resolved.is_dir():
        raise ValueError(f"audit 目录不存在：{resolved}")
    return resolved


def audit_file_hashes(audit_dir: Path, binding_name: str = "audit-binding.json") -> dict[str, str]:
    result: dict[str, str] = {}
    for path in sorted(audit_dir.rglob("*")):
        if not path.is_file() or path.name == binding_name:
            continue
        relative = path.relative_to(audit_dir).as_posix()
        result[relative] = file_digest(path)
    if not result:
        raise ValueError("audit 目录没有可绑定的证据文件。")
    return result


def evidence_digest(file_hashes: Mapping[str, str]) -> str:
    return digest({"files": dict(sorted(file_hashes.items()))})


def validate_finalize_audit(
    audit_dir: Path,
    *,
    binding_name: str = "audit-binding.json",
) -> dict[str, Any]:
    marker = read_object(audit_dir / "finalize-run.json", "finalize marker")
    if marker.get("schema_version") != 1 or marker.get("runner") != "finalize-work":
        raise ValueError("finalize marker 不是受支持的 finalize-work 审计。")
    implementation_commit = marker.get("implementation_commit")
    source_hash = marker.get("source_hash")
    if not isinstance(implementation_commit, str) or not implementation_commit.strip():
        raise ValueError("finalize marker 缺少 implementation_commit。")
    if not isinstance(source_hash, str) or not source_hash.strip():
        raise ValueError("finalize marker 缺少 source_hash。")

    validation = read_object(audit_dir / "final-validation.json", "final-validation")
    for field in ("implementation_commit", "source_hash"):
        marker_value = marker.get(field)
        validation_value = validation.get(field)
        if validation_value is not None and validation_value != marker_value:
            raise ValueError(f"{field} 与 finalize marker 不一致。")
    if validation.get("status") not in {"pass", "limited"}:
        raise ValueError("final-validation 没有通过或 limited 结果。")

    timing = read_object(audit_dir / "timing.json", "timing")
    entries = timing.get("entries")
    if not isinstance(entries, list):
        raise ValueError("timing.entries 必须是数组。")
    required = marker.get("required_timing_phases") or []
    if not isinstance(required, list) or any(not isinstance(item, str) for item in required):
        raise ValueError("finalize marker.required_timing_phases 不合法。")
    allowed_limited = set(marker.get("allowed_limited_timing_phases") or [])
    missing: list[str] = []
    running: list[str] = []
    for phase in dict.fromkeys(required):
        phase_entries = [item for item in entries if isinstance(item, dict) and item.get("phase") == phase]
        accepted = {"pass"} | ({"limited"} if phase in allowed_limited else set())
        if not any(item.get("status") in accepted for item in phase_entries):
            missing.append(phase)
        if any(item.get("status") == "running" for item in phase_entries):
            running.append(phase)
    if missing or running:
        detail = []
        if missing:
            detail.append("缺少通过阶段：" + ",".join(missing))
        if running:
            detail.append("仍在运行阶段：" + ",".join(running))
        raise ValueError("finalize timing 账本不完整；" + "; ".join(detail))

    return {
        "marker": marker,
        "validation": validation,
        "timing": timing,
        "file_hashes": audit_file_hashes(audit_dir, binding_name),
        "implementation_commit": implementation_commit,
        "source_hash": source_hash,
    }


def binding_digest(binding: Mapping[str, Any]) -> str:
    return digest({key: value for key, value in binding.items() if key != "digest"})
