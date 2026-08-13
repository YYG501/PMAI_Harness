"""Shared validation-artifact and PM exception binding helpers."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Mapping


CHECK_TO_COMMAND = {"tests": "test", "typecheck": "typecheck", "build": "build"}
LIMITABLE_CHECKS = {"tests", "typecheck"}


def results_digest(artifact: Mapping[str, Any]) -> str:
    commands = artifact.get("commands")
    if not isinstance(commands, list):
        raise ValueError("final-validation artifact.commands 必须是数组。")
    normalized = []
    for item in commands:
        if not isinstance(item, Mapping):
            raise ValueError("final-validation command 必须是对象。")
        normalized.append(
            {
                "name": item.get("name"),
                "command": item.get("command"),
                "status": item.get("status"),
                "exit_code": item.get("exit_code"),
                "satisfies": item.get("satisfies"),
            }
        )
    payload = {
        "implementation_commit": artifact.get("implementation_commit"),
        "source_hash": artifact.get("source_hash"),
        "requested_checks": artifact.get("requested_checks"),
        "commands": normalized,
    }
    return hashlib.sha256(
        json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()


def command_statuses(artifact: Mapping[str, Any]) -> dict[str, str]:
    result: dict[str, str] = {}
    commands = artifact.get("commands")
    if not isinstance(commands, list):
        return result
    for item in commands:
        if not isinstance(item, Mapping):
            continue
        status = str(item.get("status") or "")
        satisfies = item.get("satisfies")
        if not isinstance(satisfies, list):
            continue
        for check in satisfies:
            if isinstance(check, str):
                result[check] = status
    return result


def validate_artifact_binding(
    build: Mapping[str, Any], artifact: Mapping[str, Any]
) -> str:
    if artifact.get("check") != "final-validation":
        raise ValueError("audit exception artifact 不是 final-validation。")
    if artifact.get("implementation_commit") != build.get("implementation_commit"):
        raise ValueError("audit exception artifact 与当前 implementation_commit 不一致。")
    if artifact.get("source_hash") != build.get("approved_source_hash"):
        raise ValueError("audit exception artifact 与当前 approved_source_hash 不一致。")
    digest = results_digest(artifact)
    if artifact.get("results_digest") != digest:
        raise ValueError("final-validation artifact.results_digest 不一致。")
    return digest


def exception_allows(
    build: Mapping[str, Any], check: str, artifact: Mapping[str, Any]
) -> bool:
    exception = build.get("audit_exception")
    if not isinstance(exception, Mapping):
        return False
    bindings = exception.get("bindings")
    if not isinstance(bindings, Mapping):
        return False
    binding = bindings.get(check)
    if not isinstance(binding, Mapping):
        return False
    try:
        digest = validate_artifact_binding(build, artifact)
    except ValueError:
        return False
    return (
        binding.get("implementation_commit") == build.get("implementation_commit")
        and binding.get("source_hash") == build.get("approved_source_hash")
        and binding.get("results_digest") == digest
    )


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"{label} 不存在：{path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} 不是合法 JSON：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{label} 顶层必须是对象。")
    return value
