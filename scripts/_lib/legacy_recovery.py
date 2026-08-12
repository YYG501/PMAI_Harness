"""Validation helpers for explicitly recovered legacy active work.

Legacy recovery is a narrow compatibility bridge for v1-v4 active work.  It is
not a second lifecycle and cannot be used to bypass current v5 work or create
new work without a Product Proposal.
"""

from __future__ import annotations

import re
from typing import Any, Mapping


RECOVERY_SCHEMA_VERSION = 1
ACTIVE_BUILD_STATES = {"building", "iterating", "final_check"}
ACTIVE_DESIGN_STATES = {"designing", "ready_to_build"}


def _sha256(value: object, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ValueError(f"legacy_recovery.{label} 必须是 64 位小写 SHA-256。")
    return value


def validate_legacy_recovery(
    meta: Mapping[str, Any], *, require_active: bool = True
) -> dict[str, Any] | None:
    """Return a validated recovery record, or ``None`` when no record exists."""

    raw = meta.get("legacy_recovery")
    if raw is None:
        return None
    if not isinstance(raw, Mapping):
        raise ValueError("legacy_recovery 必须是对象。")
    try:
        schema_version = int(raw.get("schema_version"))
    except (TypeError, ValueError) as exc:
        raise ValueError("legacy_recovery.schema_version 必须是整数。") from exc
    if schema_version != RECOVERY_SCHEMA_VERSION:
        raise ValueError(
            f"legacy_recovery.schema_version={schema_version} 不受支持；"
            f"当前版本为 {RECOVERY_SCHEMA_VERSION}。"
        )
    if raw.get("status") != "accepted":
        raise ValueError("legacy_recovery.status 必须是 accepted。")
    kind = raw.get("kind")
    if kind not in {"active-build", "active-design"}:
        raise ValueError("legacy_recovery.kind 必须是 active-build 或 active-design。")
    if not isinstance(raw.get("confirmed_by"), str) or not raw["confirmed_by"].strip():
        raise ValueError("legacy_recovery.confirmed_by 必须记录确认人。")
    if not isinstance(raw.get("confirmed_at"), str) or not raw["confirmed_at"].strip():
        raise ValueError("legacy_recovery.confirmed_at 必须记录确认时间。")
    if not isinstance(raw.get("reason"), str) or not raw["reason"].strip():
        raise ValueError("legacy_recovery.reason 必须记录恢复理由。")
    checkpoint = raw.get("checkpoint_commit")
    if not isinstance(checkpoint, str) or not checkpoint.strip():
        raise ValueError("legacy_recovery.checkpoint_commit 必须绑定 Git checkpoint。")
    authority_hash = _sha256(raw.get("authority_source_hash"), "authority_source_hash")
    original_hash = None
    reconciled_hash = None
    if kind == "active-build":
        original_hash = _sha256(
            raw.get("original_build_approved_source_hash"),
            "original_build_approved_source_hash",
        )
        reconciled_hash = _sha256(
            raw.get("reconciled_build_approved_source_hash"),
            "reconciled_build_approved_source_hash",
        )
        if reconciled_hash != authority_hash:
            raise ValueError("legacy_recovery 的恢复后 build hash 与 authority hash 不一致。")
        try:
            original_version = int(raw.get("original_contract_version"))
        except (TypeError, ValueError) as exc:
            raise ValueError("legacy_recovery.original_contract_version 必须是整数。") from exc
        if original_version not in {1, 2, 3, 4}:
            raise ValueError("legacy_recovery.original_contract_version 只接受 1-4。")
        original_deltas = raw.get("original_accepted_deltas")
        if not isinstance(original_deltas, list) or any(
            not isinstance(delta, Mapping) for delta in original_deltas
        ):
            raise ValueError("legacy_recovery.original_accepted_deltas 必须是对象数组。")
        original_count = raw.get("original_accepted_delta_count")
        if isinstance(original_count, bool) or not isinstance(original_count, int):
            raise ValueError("legacy_recovery.original_accepted_delta_count 必须是整数。")
        if original_count != len(original_deltas):
            raise ValueError("legacy_recovery 的原 accepted delta 数量不一致。")
    else:
        if raw.get("original_lifecycle_state") not in ACTIVE_DESIGN_STATES:
            raise ValueError("legacy_recovery.original_lifecycle_state 不是可恢复的 design 状态。")
        if raw.get("resumed_lifecycle_state") != "designing":
            raise ValueError("active-design recovery 必须恢复到 designing。")
        if not isinstance(raw.get("original_ready_contract"), Mapping):
            raise ValueError("legacy_recovery.original_ready_contract 必须是对象。")
    source_scope = raw.get("authority_source_scope")
    if not isinstance(source_scope, list) or any(
        not isinstance(item, str) or not item.strip() for item in source_scope
    ):
        raise ValueError("legacy_recovery.authority_source_scope 必须是字符串数组。")
    source_file_hashes = raw.get("authority_source_file_hashes")
    if not isinstance(source_file_hashes, Mapping):
        raise ValueError("legacy_recovery.authority_source_file_hashes 必须是对象。")
    normalized_file_hashes = {
        str(path): _sha256(digest, f"authority_source_file_hashes[{path}]")
        for path, digest in source_file_hashes.items()
    }
    if sorted(normalized_file_hashes) != sorted(str(item).strip() for item in source_scope):
        raise ValueError("legacy_recovery 的 authority 文件范围与摘要不一致。")
    result = dict(raw)
    result.update(
        {
            "schema_version": schema_version,
            "checkpoint_commit": checkpoint.strip(),
            "authority_source_hash": authority_hash,
            "authority_source_scope": [str(item).strip() for item in source_scope],
            "authority_source_file_hashes": normalized_file_hashes,
        }
    )
    if kind == "active-build":
        result["original_build_approved_source_hash"] = original_hash
        result["reconciled_build_approved_source_hash"] = reconciled_hash
    if require_active:
        status = meta.get("status")
        if status != "active":
            raise ValueError("legacy recovery 只适用于 active work。")
        build = meta.get("build")
        build_lifecycle = build.get("lifecycle_state") if isinstance(build, Mapping) else None
        lifecycle = build_lifecycle or meta.get("lifecycle_state")
        if kind == "active-build":
            if not isinstance(build, Mapping):
                raise ValueError("legacy active build 缺少 build contract。")
            try:
                version = int(build.get("contract_version"))
            except (TypeError, ValueError) as exc:
                raise ValueError("legacy active build 的 contract_version 不合法。") from exc
            if version >= 5:
                raise ValueError("active-build recovery 只适用于 v1-v4 build contract。")
            if version != original_version:
                raise ValueError("active-build recovery 的原合同版本与当前 build 不一致。")
            if lifecycle not in ACTIVE_BUILD_STATES:
                raise ValueError(f"active-build recovery 不能用于 {lifecycle or '<empty>'} 状态。")
        else:
            if isinstance(build, Mapping):
                raise ValueError("active-design recovery 不能包含 build contract。")
            if lifecycle not in ACTIVE_DESIGN_STATES:
                raise ValueError(
                    f"active-design recovery 不能用于 {lifecycle or '<empty>'} 状态。"
                )
    return result


def recovery_allows_proposal_bypass(meta: Mapping[str, Any]) -> dict[str, Any] | None:
    try:
        return validate_legacy_recovery(meta)
    except ValueError:
        return None
