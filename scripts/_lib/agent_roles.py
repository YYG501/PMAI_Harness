"""Shared role and execution backend validation for delegated build work."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from uuid import uuid4


VALID_AGENT_ROLES = {"builder", "verifier", "judge"}
VALID_AGENT_BACKENDS = {"child", "external", "main-fallback"}


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def new_run_id(role: str) -> str:
    if role not in VALID_AGENT_ROLES:
        raise ValueError(f"不支持的 Agent role: {role}")
    return f"{role}-{uuid4().hex[:16]}"


def validate_role(role: Any, *, expected: str | None = None) -> str:
    if not isinstance(role, str) or role not in VALID_AGENT_ROLES:
        raise ValueError(f"Agent role 不合法：{role!r}")
    if expected and role != expected:
        raise ValueError(f"Agent role 必须是 {expected}：{role}")
    return role


def validate_backend(backend: Any) -> str:
    if not isinstance(backend, str) or backend not in VALID_AGENT_BACKENDS:
        raise ValueError(f"Agent backend 不合法：{backend!r}")
    return backend


def independent_for_backend(backend: str) -> bool:
    return backend != "main-fallback"


def build_receipt(
    *,
    role: str,
    backend: str,
    run_id: str,
    implementation_commit: str,
    source_hash: str,
    host: str = "unknown",
    model: str = "unknown",
    status: str = "pass",
    reason: str | None = None,
) -> dict[str, Any]:
    validate_role(role)
    validate_backend(backend)
    if not run_id.strip():
        raise ValueError("Agent run_id 不能为空")
    if not implementation_commit.strip() or not source_hash.strip():
        raise ValueError("Agent receipt 必须绑定 implementation_commit 和 source_hash")
    if status not in {"running", "pass", "fail", "degraded"}:
        raise ValueError(f"Agent receipt status 不合法：{status}")
    receipt: dict[str, Any] = {
        "schema_version": 1,
        "role": role,
        "backend": backend,
        "independent": independent_for_backend(backend),
        "run_id": run_id,
        "host": host.strip() or "unknown",
        "model": model.strip() or "unknown",
        "implementation_commit": implementation_commit,
        "source_hash": source_hash,
        "status": status,
        "updated_at": now_iso(),
    }
    if reason:
        receipt["reason"] = reason
    return receipt


def validate_receipt(
    receipt: Any,
    *,
    expected_role: str | None = None,
    implementation_commit: str | None = None,
    source_hash: str | None = None,
    require_pass: bool = False,
) -> dict[str, Any]:
    if not isinstance(receipt, dict):
        raise ValueError("Agent receipt 必须是对象")
    if receipt.get("schema_version") != 1:
        raise ValueError("Agent receipt schema_version 不受支持")
    role = validate_role(receipt.get("role"), expected=expected_role)
    backend = validate_backend(receipt.get("backend"))
    if receipt.get("independent") is not independent_for_backend(backend):
        raise ValueError("Agent receipt independent 与 backend 不一致")
    for field in ("run_id", "host", "model", "implementation_commit", "source_hash"):
        if not isinstance(receipt.get(field), str) or not receipt[field].strip():
            raise ValueError(f"Agent receipt {field} 不能为空")
    if receipt.get("status") not in {"running", "pass", "fail", "degraded"}:
        raise ValueError("Agent receipt status 不合法")
    if require_pass and receipt.get("status") not in {"pass", "degraded"}:
        raise ValueError("Agent receipt 尚未通过")
    if implementation_commit and receipt.get("implementation_commit") != implementation_commit:
        raise ValueError(f"Agent receipt {role} 的 implementation_commit 已漂移")
    if source_hash and receipt.get("source_hash") != source_hash:
        raise ValueError(f"Agent receipt {role} 的 source_hash 已漂移")
    return receipt
