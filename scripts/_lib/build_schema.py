"""Build contract schema rules shared by the CLI and recovery runners."""

from __future__ import annotations

import argparse
import json
from typing import Any

from .delivery_policy import delivery_policy_hash, validate_delivery_policy
from .work_contract import (
    CURRENT_BUILD_CONTRACT_VERSION,
    WorkContract,
    WorkContractError,
    normalize_work_contract,
    normalize_work_state,
)


VALID_MODES = {"worktree", "main"}
VALID_EXECUTORS = {
    "claude-code",
    "codex",
    "cursor-agent",
    "kimi-code",
    "opencode",
    "manual",
    "native",
}
VALID_TARGET_KINDS = {"prototype", "product"}
VALID_DOCS_STATUSES = {"pending", "complete", "failed"}
NEW_DELTA_KIND = "scoped-adjustment"
DELTA_SCOPE_ATTESTATION = "approved-module-task-no-model-change"
VALID_DELTA_APPROVAL_KINDS = {"pm-confirmation", "lark-review-batch"}
VALID_DELTA_AFFECT_KINDS = {"term", "role"}
CURRENT_CONTRACT_VERSION = CURRENT_BUILD_CONTRACT_VERSION


def optional(value: Any) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def normalize_string_list(values: list[str] | None) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values or []:
        item = value.strip()
        if item and item not in seen:
            seen.add(item)
            result.append(item)
    return result


def parse_delta_affects(values: list[str] | None) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for raw in values or []:
        kind, separator, name = raw.partition(":")
        kind = kind.strip().lower()
        name = name.strip()
        if separator != ":" or kind not in VALID_DELTA_AFFECT_KINDS or not name:
            raise SystemExit("--affects 必须是 term:<准确名称> 或 role:<准确名称>。")
        key = (kind, name)
        if key not in seen:
            seen.add(key)
            result.append({"kind": kind, "name": name})
    return result


def validate_scoped_delta_shape(delta: dict, index: int) -> None:
    """Validate current scoped-delta fields without rejecting historical entries."""

    new_fields = {
        "scope_attestation",
        "approval_evidence",
        "affects",
        "authority_paths",
        "authority_file_hashes",
        "authority_git_blobs",
        "authority_parent_commit",
        "authority_source_hash_before",
        "authority_source_hash_after",
    }
    kind = delta.get("kind")
    if kind != NEW_DELTA_KIND:
        if not new_fields.intersection(delta):
            return
        raise SystemExit(
            f"accepted delta[{index}] 使用新证据字段时 kind 必须是 {NEW_DELTA_KIND}。"
        )
    if delta.get("scope_attestation") != DELTA_SCOPE_ATTESTATION:
        raise SystemExit(f"accepted delta[{index}] 的 scope_attestation 不合法。")
    evidence = delta.get("approval_evidence")
    if not isinstance(evidence, dict):
        raise SystemExit(f"accepted delta[{index}] 缺少 approval_evidence。")
    evidence_kind = evidence.get("kind")
    evidence_reference = evidence.get("reference")
    if evidence_kind not in VALID_DELTA_APPROVAL_KINDS or not isinstance(
        evidence_reference, str
    ) or not evidence_reference.strip():
        raise SystemExit(f"accepted delta[{index}] 的 approval_evidence 不合法。")
    approval_artifact = evidence.get("artifact")
    if evidence_kind == "lark-review-batch":
        if (
            not isinstance(approval_artifact, dict)
            or approval_artifact.get("batch_id") != evidence_reference
            or any(
                not isinstance(approval_artifact.get(field), str)
                or not approval_artifact[field].strip()
                for field in (
                    "path",
                    "sha256",
                    "plan_path",
                    "plan_sha256",
                    "target_sha256",
                )
            )
        ):
            raise SystemExit(
                f"accepted delta[{index}] 缺少绑定 sealed Lark 批次的 approval artifact。"
            )
    elif approval_artifact is not None:
        raise SystemExit(
            f"accepted delta[{index}] 只有 lark-review-batch 可以携带 approval artifact。"
        )
    affects = delta.get("affects")
    if not isinstance(affects, list):
        raise SystemExit(f"accepted delta[{index}] 的 affects 必须是数组。")
    for affect in affects:
        if (
            not isinstance(affect, dict)
            or affect.get("kind") not in VALID_DELTA_AFFECT_KINDS
            or not isinstance(affect.get("name"), str)
            or not affect["name"].strip()
        ):
            raise SystemExit(f"accepted delta[{index}] 的 affects 条目不合法。")
    for field in ("authority_source_hash_before", "authority_source_hash_after"):
        value = delta.get(field)
        if not isinstance(value, str) or not value.strip():
            raise SystemExit(
                f"accepted delta[{index}] 缺少完整 authority source hash transition。"
            )
    authority_paths = delta.get("authority_paths")
    authority_hashes = delta.get("authority_file_hashes")
    authority_blobs = delta.get("authority_git_blobs")
    authority_parent = delta.get("authority_parent_commit")
    if authority_paths is None:
        if authority_hashes is not None or authority_blobs is not None or authority_parent is not None:
            raise SystemExit(
                f"accepted delta[{index}] 没有 authority_paths，不能单独提供 authority 内容绑定。"
            )
        return
    if not isinstance(authority_paths, list) or any(
        not isinstance(path, str) or not path.strip() for path in authority_paths
    ):
        raise SystemExit(f"accepted delta[{index}] 的 authority_paths 不合法。")
    if not isinstance(authority_hashes, dict) or set(authority_hashes) != set(authority_paths):
        raise SystemExit(
            f"accepted delta[{index}] 的 authority_file_hashes 必须精确覆盖 authority_paths。"
        )
    for path, digest in authority_hashes.items():
        if (
            not isinstance(path, str)
            or not isinstance(digest, str)
            or len(digest) != 64
            or any(char not in "0123456789abcdef" for char in digest)
        ):
            raise SystemExit(f"accepted delta[{index}] 的 authority_file_hashes 不合法。")
    if not isinstance(authority_blobs, dict) or set(authority_blobs) != set(authority_paths):
        raise SystemExit(
            f"accepted delta[{index}] 的 authority_git_blobs 必须精确覆盖 authority_paths。"
        )
    for path, oid in authority_blobs.items():
        if (
            not isinstance(path, str)
            or not isinstance(oid, str)
            or len(oid) not in {40, 64}
            or any(char not in "0123456789abcdef" for char in oid)
        ):
            raise SystemExit(f"accepted delta[{index}] 的 authority_git_blobs 不合法。")
    if (
        not isinstance(authority_parent, str)
        or len(authority_parent) not in {40, 64}
        or any(char not in "0123456789abcdef" for char in authority_parent)
    ):
        raise SystemExit(f"accepted delta[{index}] 的 authority_parent_commit 不合法。")


def contract_version(build: dict) -> int:
    value = build.get("contract_version", 1)
    if isinstance(value, bool):
        raise SystemExit(f"build.contract_version 必须是整数: {value}")
    try:
        return int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"build.contract_version 必须是整数: {value}")


def canonical_contract(meta: dict) -> WorkContract:
    try:
        return normalize_work_contract(meta)
    except WorkContractError as exc:
        raise SystemExit(str(exc)) from exc


def canonical_state(meta: dict) -> WorkContract:
    try:
        return normalize_work_state(meta)
    except WorkContractError as exc:
        raise SystemExit(str(exc)) from exc


def canonical_final_checks(meta: dict) -> list[str]:
    return list(canonical_contract(meta).final_checks)


def ensure_build_shape(build: dict) -> None:
    if contract_version(build) < 2:
        return
    try:
        normalized = normalize_work_contract({"build": build})
    except WorkContractError as exc:
        raise SystemExit(str(exc)) from exc
    target = build.get("target")
    if not isinstance(target, dict) or target.get("kind") not in VALID_TARGET_KINDS:
        raise SystemExit("build.target.kind 必须是 prototype 或 product。")
    if not isinstance(target.get("paths", []), list) or not isinstance(
        target.get("entrypoints", []), list
    ):
        raise SystemExit("build.target.paths / entrypoints 必须是数组。")
    if not isinstance(build.get("design_revision"), int) or build["design_revision"] < 1:
        raise SystemExit("build.design_revision 必须是正整数。")
    if not optional(build.get("approved_source_hash")):
        raise SystemExit("build 合同缺少 approved_source_hash。")
    acceptance = build.get("acceptance")
    if not isinstance(acceptance, dict):
        raise SystemExit("build.acceptance 必须是对象。")
    final_checks = list(normalized.final_checks)
    if not isinstance(acceptance.get("evidence", []), list):
        raise SystemExit("build.acceptance.evidence 必须是数组。")
    if contract_version(build) >= 3:
        try:
            policy = validate_delivery_policy(build.get("delivery_policy"), target["kind"])
        except ValueError as exc:
            raise SystemExit(str(exc)) from exc
        if build.get("delivery_policy_hash") != delivery_policy_hash(policy):
            raise SystemExit("build.delivery_policy_hash 与实现深度合同不一致。")
        if target["kind"] == "prototype" and "prototype-boundary" not in final_checks:
            raise SystemExit("prototype build 必须把 prototype-boundary 作为不可跳过的检查。")
    if contract_version(build) >= 4:
        if not isinstance(acceptance.get("iteration_evidence", []), list):
            raise SystemExit("build.acceptance.iteration_evidence 必须是数组。")
        if not isinstance(build.get("finalization"), dict):
            raise SystemExit("build.finalization 必须是对象。")
    docs_status = build.get("docs_status")
    if docs_status not in VALID_DOCS_STATUSES:
        raise SystemExit(
            f"build.docs_status 不合法：{docs_status}（允许 {', '.join(sorted(VALID_DOCS_STATUSES))}）。"
        )


def validate_mode_executor(mode: str, executor: str | None) -> None:
    if mode not in VALID_MODES:
        raise SystemExit(f"build.mode 必须是 {' / '.join(sorted(VALID_MODES))}: {mode}")
    if executor and executor not in VALID_EXECUTORS:
        raise SystemExit(
            f"build.executor 必须是 {' / '.join(sorted(VALID_EXECUTORS))}: {executor}"
        )


def validate_builder(builder: dict) -> None:
    for key in ("model", "thinking"):
        value = builder.get(key)
        if value is not None and not isinstance(value, str):
            raise SystemExit(f"builder.{key} 必须是字符串")
    overrides = builder.get("overrides")
    if overrides is not None and not isinstance(overrides, dict):
        raise SystemExit("builder.overrides 必须是对象")


def build_snapshot(args: argparse.Namespace) -> dict:
    raw = optional(args.builder_json)
    if raw:
        try:
            builder = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"builder 必须是合法 JSON 对象: {exc}") from exc
        if not isinstance(builder, dict):
            raise SystemExit("builder 必须是 JSON 对象")
    else:
        builder = {}
    model = optional(args.builder_model)
    thinking = optional(args.builder_thinking)
    if model:
        builder["model"] = model
    if thinking:
        builder["thinking"] = thinking
    validate_builder(builder)
    return builder
