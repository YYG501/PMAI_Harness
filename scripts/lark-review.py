#!/usr/bin/env python3
"""收集飞书规格评审增量，并在整批完成后记录本地 checkpoint。"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse
from xml.etree import ElementTree

_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.lark_adapter import (  # noqa: E402
    LarkAdapterError,
    auth_status,
    docs_fetch,
    drive_comment_reply_create,
    drive_comment_set_solved,
    drive_comment_replies_page,
    drive_comments_page,
    markdown_body_hash,
    parse_frontmatter,
    replace_markdown_body,
    version,
    write_frontmatter,
)
from _lib.atomic_file import (  # noqa: E402
    AtomicFileError,
    bind_directory_fd,
    ensure_directory_beneath,
    read_regular_bytes as atomic_read_regular_bytes,
    write_text_atomically,
)
from _lib.decision_status import (  # noqa: E402
    decision_is_question,
    decision_is_superseded,
)
from _lib.lark_review_semantics import (  # noqa: E402
    NATIVE_SNAPSHOT_KIND,
    NATIVE_SNAPSHOT_SCHEMA_VERSION,
    REMOTE_COVERAGE_KIND,
    REMOTE_COVERAGE_SCHEMA_VERSION,
    build_native_snapshot,
    build_remote_coverage,
    markdown_verification_projection,
    render_remote_preview,
)
from _lib.state import StateReadError, list_active_work  # noqa: E402
from _lib.proposal import (  # noqa: E402
    ProposalContractError,
    validate_current_proposal,
)


SCHEMA_VERSION = 3
PLAN_SCHEMA_VERSION = 4
RESOLUTION_SCHEMA_VERSION = 4
COMMENT_ACTIONS_SCHEMA_VERSION = 3
LEGACY_REVIEW_SCHEMA_VERSION = 2
LEGACY_PLAN_SCHEMA_VERSION = 2
PREVIOUS_PLAN_SCHEMA_VERSION = 3
PREVIOUS_RESOLUTION_SCHEMA_VERSION = 3
MIN_LARK_REVIEW_CLI_VERSION = (1, 0, 49)
MAX_PAGES = 100
MAX_COMMENT_STABILITY_SCANS = 4
COMMENT_ACTIONS_KIND = "pmai_lark_review_comment_actions"
REMOTE_VERIFICATION_KIND = "pmai_lark_review_remote_verification"
REMOTE_VERIFICATION_SCHEMA_VERSION = 2
HANDOFF_KIND = "pmai_lark_review_read_only_handoff"
LEGACY_HANDOFF_SCHEMA_VERSION = 1
HANDOFF_SCHEMA_VERSION = 2
HANDOFF_ROUTES = {"proposal", "design"}
HANDOFF_BUNDLE_KIND = "pmai_lark_review_upstream_handoff_bundle"
HANDOFF_BUNDLE_SCHEMA_VERSION = 2
HANDOFF_BUNDLE_STATES = {"pending", "closed"}
HANDOFF_PHASES = {"proposal", "design", "lark_review", "closed"}
HANDOFF_PHASE_SEQUENCES = {
    "proposal": ("proposal", "design", "lark_review", "closed"),
    "design": ("design", "lark_review", "closed"),
}
HANDOFF_BUNDLE_REQUIRED_FILES = (
    "review.json",
    "apply-plan.json",
    "handoff.json",
    "resolutions.json",
    "target.md",
    "local.md",
    "remote.md",
    "remote-native.json",
    "local-vs-remote.diff",
    "remote-coverage.json",
    "remote-preview.md",
)
HANDOFF_BUNDLE_OPTIONAL_FILES = (
    "baseline.md",
    "remote-vs-baseline.diff",
    "local-vs-baseline.diff",
)
REPLAN_CANDIDATE_SCHEMA_VERSION = 1
ACTIVE_BUILD_DELTA_KIND = "scoped-adjustment"
ACTIVE_BUILD_SCOPE_ATTESTATION = "approved-module-task-no-model-change"
ACTIVE_BUILD_STATES = {"building", "iterating", "final_check"}
CHECKPOINT_KIND = "pmai_lark_review_checkpoint"
CHECKPOINT_SCHEMA_VERSION = 1
COMPLETED_COMMENT_DECISIONS = {
    "applied",
    "already_satisfied",
    "no_spec_change",
    "superseded",
}
COMMENT_ACTION_STATUSES = {
    "pending",
    "reply_created",
    "replied_pending_pm",
    "solve_requested",
    "completed",
    "reopen_requested",
    "reopened",
}
COMMENT_COMPLETION_STATUSES = {
    "open",
    "replied_pending_pm",
    "solved_by_pmai",
    "solved_by_pm_verified",
}
SOLVE_EVIDENCE_MODES = {
    "server_time",
    "write_ack_and_stable_readback",
    "legacy_stable_readback",
    "external_stable_readback",
}
REPLY_EVIDENCE_MODES = {
    "write_ack",
    "stable_readback",
    "legacy_stable_readback",
}
COMMENT_EXECUTION_MODES = {"single", "batch", "reply_only"}
_PERF_COUNTERS = {
    "document_fetch_api_calls": 0,
    "comment_full_scans": 0,
    "comment_list_api_calls": 0,
    "comment_reply_api_calls": 0,
}


class ReviewError(Exception):
    pass


class CommentSnapshotRace(ReviewError):
    """A comment moved between solved-state queries during one full scan."""


def _body_hash(body: str) -> str:
    return markdown_body_hash(body)


def _normalise(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n").strip("\n") + "\n"


def _int(value: object) -> int | None:
    try:
        return int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


def _event_time(value: dict[str, Any]) -> int:
    return _int(value.get("update_time")) or _int(value.get("create_time")) or 0


def _checkpoint_ids(value: object) -> set[str]:
    if value in (None, ""):
        return set()
    if isinstance(value, list):
        parsed = value
    else:
        try:
            parsed = json.loads(str(value))
        except json.JSONDecodeError as exc:
            raise ReviewError(f"lark_reviewed_comment_ids 不是合法 JSON 数组: {exc}") from exc
    if not isinstance(parsed, list) or any(not isinstance(item, str) for item in parsed):
        raise ReviewError("lark_reviewed_comment_ids 必须是字符串数组")
    return set(parsed)


def _comment_fence_hash(items: list[dict[str, Any]]) -> str:
    fence = [
        _comment_fence_view(item)
        for item in sorted(items, key=lambda value: str(value.get("comment_id") or ""))
    ]
    encoded = json.dumps(fence, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _reply_checkpoint_view(reply: dict[str, Any]) -> dict[str, Any]:
    return {
        "reply_id": str(reply.get("reply_id") or ""),
        "user_id": reply.get("user_id"),
        "create_time": _int(reply.get("create_time")),
        "update_time": _int(reply.get("update_time")),
        "text": str(reply.get("text") or ""),
    }


def _comment_checkpoint_view(item: dict[str, Any]) -> dict[str, Any]:
    replies = item.get("replies") if isinstance(item.get("replies"), list) else []
    return {
        "comment_id": str(item.get("comment_id") or ""),
        "user_id": item.get("user_id"),
        "create_time": _int(item.get("create_time")),
        "is_whole": bool(item.get("is_whole")),
        "replies": sorted(
            [
                _reply_checkpoint_view(reply)
                for reply in replies
                if isinstance(reply, dict)
            ],
            key=lambda reply: reply["reply_id"],
        ),
    }


def _comment_fence_view(item: dict[str, Any]) -> dict[str, Any]:
    """保留服务端评论围栏字段；排除本地派生的 location。"""
    return {
        **_comment_checkpoint_view(item),
        "update_time": _int(item.get("update_time")),
        "is_solved": bool(item.get("is_solved")),
        "solved_time": _int(item.get("solved_time")),
        "solver_user_id": str(item.get("solver_user_id") or ""),
        "quote": str(item.get("quote") or ""),
    }


def _comment_preserves_collected_input(
    collected: dict[str, Any], current: dict[str, Any]
) -> bool:
    """允许已完成评论追加结果回复，但不允许采集时输入被编辑或删除。"""
    collected_view = _comment_checkpoint_view(collected)
    current_view = _comment_checkpoint_view(current)
    for key in ("comment_id", "user_id", "create_time", "is_whole"):
        if current_view[key] != collected_view[key]:
            return False
    current_replies = {
        str(reply.get("reply_id") or ""): reply for reply in current_view["replies"]
    }
    return all(
        current_replies.get(str(reply.get("reply_id") or "")) == reply
        for reply in collected_view["replies"]
    )


def _docx_token(value: object) -> str | None:
    """从 Docx URL 或裸 token 中提取文档身份；其它链接类型不猜。"""
    text = str(value or "").strip()
    if not text:
        return None
    if "://" not in text:
        return text if "/" not in text else None
    parts = [part for part in urlparse(text).path.split("/") if part]
    for marker in ("docx",):
        if marker in parts:
            index = parts.index(marker)
            if index + 1 < len(parts):
                return parts[index + 1]
    return None


def _data(payload: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ReviewError("飞书 JSON 结果顶层不是对象")
    if "data" in payload:
        value = payload["data"]
        if not isinstance(value, dict):
            raise ReviewError("飞书 JSON 结果的 data 不是对象")
        return value
    if "ok" in payload:
        raise ReviewError("飞书 JSON envelope 缺少 data 对象")
    return payload


def _document(payload: dict[str, Any]) -> dict[str, Any]:
    data = _data(payload)
    value = data.get("document", data)
    if not isinstance(value, dict):
        raise ReviewError("飞书文档读取结果缺少 document")
    if not isinstance(value.get("content"), str):
        raise ReviewError("飞书文档读取结果缺少正文 content")
    return value


def _page(payload: dict[str, Any]) -> tuple[list[dict[str, Any]], bool, str | None]:
    data = _data(payload)
    if "items" not in data:
        raise ReviewError("飞书分页结果缺少 items")
    raw_items = data["items"]
    if not isinstance(raw_items, list):
        raise ReviewError("飞书分页结果的 items 不是数组")
    if any(not isinstance(item, dict) for item in raw_items):
        raise ReviewError("飞书分页结果的 items 包含非对象条目")
    if "has_more" not in data or not isinstance(data["has_more"], bool):
        raise ReviewError("飞书分页结果的 has_more 缺失或不是布尔值")
    has_more = data["has_more"]
    token_value = data.get("page_token")
    if token_value is not None and not isinstance(token_value, str):
        raise ReviewError("飞书分页结果的 page_token 不是字符串或 null")
    token = token_value.strip() if isinstance(token_value, str) else None
    if isinstance(token_value, str) and not token:
        raise ReviewError("飞书分页结果的 page_token 不能为空字符串")
    if has_more and not token:
        raise ReviewError("飞书分页结果 has_more=true，但分页 token 缺失或重复")
    return raw_items, has_more, token


def _paginate(
    fetch_page: Callable[[str | None], dict[str, Any]],
    *,
    label: str,
    metric: str,
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    page_token: str | None = None
    seen_tokens: set[str] = set()
    for _ in range(MAX_PAGES):
        _PERF_COUNTERS[metric] = _PERF_COUNTERS.get(metric, 0) + 1
        page_items, has_more, next_token = _page(fetch_page(page_token))
        items.extend(page_items)
        if not has_more:
            return items
        if not next_token or next_token in seen_tokens:
            raise ReviewError(f"{label} 返回 has_more=true，但分页 token 缺失或重复")
        seen_tokens.add(next_token)
        page_token = next_token
    raise ReviewError(f"{label} 超过 {MAX_PAGES} 页，已停止以避免无限分页")


def _flatten_text(value: object) -> str:
    parts: list[str] = []

    def visit(node: object) -> None:
        if isinstance(node, str):
            if node.strip():
                parts.append(node.strip())
            return
        if isinstance(node, list):
            for child in node:
                visit(child)
            return
        if not isinstance(node, dict):
            return
        text = node.get("text")
        if isinstance(text, str) and text.strip():
            parts.append(text.strip())
        for key, child in node.items():
            if key != "text" and isinstance(child, (dict, list)):
                visit(child)

    visit(value)
    return " ".join(parts)


def _reply_view(reply: dict[str, Any]) -> dict[str, Any]:
    return {
        "reply_id": reply.get("reply_id"),
        "user_id": reply.get("user_id"),
        "create_time": _int(reply.get("create_time")),
        "update_time": _int(reply.get("update_time")),
        "text": _flatten_text(reply.get("content")),
        "extra": reply.get("extra") if isinstance(reply.get("extra"), dict) else {},
    }


def _dedupe_replies(replies: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    result: list[dict[str, Any]] = []
    for reply in replies:
        key = str(reply.get("reply_id") or "")
        if not key:
            raise ReviewError("回复列表存在缺少 reply_id 的条目")
        if key in seen:
            raise ReviewError(f"回复分页返回重复 reply_id: {key}")
        seen.add(key)
        result.append(reply)
    return result


def _find_block_ids(node: object) -> list[str]:
    result: list[str] = []
    if isinstance(node, dict):
        position = node.get("positionInfo")
        if isinstance(position, dict) and position.get("blockID"):
            result.append(str(position["blockID"]))
        for value in node.values():
            result.extend(_find_block_ids(value))
    elif isinstance(node, list):
        for value in node:
            result.extend(_find_block_ids(value))
    return list(dict.fromkeys(result))


def _relation_details(comment: dict[str, Any]) -> tuple[list[str], object | None, str | None]:
    relation = comment.get("relation")
    if not isinstance(relation, dict):
        return [], None, None
    encoded = relation.get("relation")
    if isinstance(encoded, str):
        try:
            decoded = json.loads(encoded)
            return _find_block_ids(decoded), decoded, None
        except json.JSONDecodeError as exc:
            return [], None, f"relation.relation 无法解析: {exc}"
    return _find_block_ids(encoded), encoded, None


def _xml_indexes(content: str) -> tuple[dict[str, dict[str, str]], dict[str, str], str | None]:
    blocks: dict[str, dict[str, str]] = {}
    token_to_block: dict[str, str] = {}
    cleaned = re.sub(r"^\s*<\?xml[^>]*>\s*", "", content)
    try:
        root = ElementTree.fromstring(f"<pmai-root>{cleaned}</pmai-root>")
    except ElementTree.ParseError as exc:
        return blocks, token_to_block, f"with-ids XML 无法解析，评论将退回 quote 弱匹配: {exc}"

    for element in root.iter():
        block_id = element.attrib.get("id") or element.attrib.get("block_id")
        text = " ".join(part.strip() for part in element.itertext() if part.strip())
        if block_id:
            blocks[block_id] = {
                "block_id": block_id,
                "block_type": element.tag,
                "text": text,
            }
        token = element.attrib.get("token")
        if token and block_id:
            token_to_block[token] = block_id
    return blocks, token_to_block, None


def _parent_block(parent_token: str, token_to_block: dict[str, str]) -> str | None:
    if parent_token in token_to_block:
        return token_to_block[parent_token]
    candidates = [
        (token, block_id)
        for token, block_id in token_to_block.items()
        if parent_token.startswith(f"{token}_") or token.startswith(f"{parent_token}_")
    ]
    return candidates[0][1] if len(candidates) == 1 else None


def _locate_comment(
    comment: dict[str, Any],
    blocks: dict[str, dict[str, str]],
    token_to_block: dict[str, str],
) -> dict[str, Any]:
    relation_raw = comment.get("relation") if isinstance(comment.get("relation"), dict) else {}
    relation_ids, relation_decoded, relation_warning = _relation_details(comment)
    relation = relation_raw
    content_deleted = bool(relation.get("content_deleted"))
    base = {
        "content_deleted": content_deleted,
        "relation_raw": relation_raw,
        "relation_decoded": relation_decoded,
    }
    if relation_warning:
        base["warning"] = relation_warning
    if content_deleted:
        return {
            "accuracy": "content_deleted",
            "block_ids": relation_ids,
            **base,
        }
    if comment.get("is_whole"):
        return {"accuracy": "whole_document", **base}
    matched_ids = [block_id for block_id in relation_ids if block_id in blocks]
    if matched_ids:
        relation_id = matched_ids[0]
        return {
            "accuracy": "relation_exact",
            "block_ids": matched_ids,
            "blocks": [blocks[block_id] for block_id in matched_ids],
            **base,
            **blocks[relation_id],
        }

    parent_token = str(comment.get("parent_token") or "")
    if parent_token:
        block_id = _parent_block(parent_token, token_to_block)
        if block_id and block_id in blocks:
            return {
                "accuracy": "parent_resource_exact",
                **base,
                "parent_type": comment.get("parent_type"),
                "parent_token": parent_token,
                **blocks[block_id],
            }

    quote = str(comment.get("quote") or "").strip()
    if quote:
        matches = [block for block in blocks.values() if quote in block.get("text", "")]
        if len(matches) == 1:
            return {
                "accuracy": "quote_inferred",
                **base,
                **matches[0],
            }
        if len(matches) > 1:
            return {
                "accuracy": "quote_ambiguous",
                **base,
                "candidate_block_ids": [item["block_id"] for item in matches],
            }
    return {"accuracy": "unlocated", **base}


def _diff(before: str, after: str, before_name: str, after_name: str) -> str:
    return "".join(
        difflib.unified_diff(
            _normalise(before).splitlines(keepends=True),
            _normalise(after).splitlines(keepends=True),
            fromfile=before_name,
            tofile=after_name,
        )
    )


def _absolute_lexical_path(path: Path) -> Path:
    if not path.is_absolute():
        path = Path.cwd() / path
    return Path(os.path.normpath(str(path)))


def _read_regular_bytes(path: Path, *, label: str) -> bytes:
    path = _absolute_lexical_path(path)
    try:
        return atomic_read_regular_bytes(path, require_canonical_path=True)
    except AtomicFileError as exc:
        raise ReviewError(f"{label} 不是可安全读取的普通文件: {path}；{exc}") from exc


def _canonical_regular_file(path: Path, *, label: str) -> Path:
    path = _absolute_lexical_path(path)
    _read_regular_bytes(path, label=label)
    return path


def _canonical_directory(path: Path, *, label: str) -> Path:
    path = _absolute_lexical_path(path)
    flags = (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_CLOEXEC", 0)
        | os.O_NOFOLLOW
    )
    directory_fd = -1
    try:
        directory_fd = os.open(path, flags)
        bind_directory_fd(path, directory_fd)
        return path
    except (AtomicFileError, OSError) as exc:
        raise ReviewError(f"{label} 不是无 symlink 的安全目录: {path}；{exc}") from exc
    finally:
        if directory_fd >= 0:
            os.close(directory_fd)


def _prepare_empty_directory(path: Path, *, label: str) -> Path:
    path = _absolute_lexical_path(path)
    try:
        ensure_directory_beneath(Path(path.anchor), path)
        flags = (
            os.O_RDONLY
            | getattr(os, "O_DIRECTORY", 0)
            | getattr(os, "O_CLOEXEC", 0)
            | os.O_NOFOLLOW
        )
        directory_fd = os.open(path, flags)
        try:
            bind_directory_fd(path, directory_fd)
            if os.listdir(directory_fd):
                raise ReviewError(f"{label}必须为空，避免混用其它批次")
            os.fchmod(directory_fd, 0o700)
            os.fsync(directory_fd)
            bind_directory_fd(path, directory_fd)
        finally:
            os.close(directory_fd)
    except ReviewError:
        raise
    except (AtomicFileError, OSError) as exc:
        raise ReviewError(f"无法安全准备{label}: {path}；{exc}") from exc
    return path


def _entry_exists(path: Path, *, label: str) -> bool:
    path = _absolute_lexical_path(path)
    flags = (
        os.O_RDONLY
        | getattr(os, "O_DIRECTORY", 0)
        | getattr(os, "O_CLOEXEC", 0)
        | os.O_NOFOLLOW
    )
    directory_fd = -1
    try:
        directory_fd = os.open(path.parent, flags)
        bind_directory_fd(path.parent, directory_fd)
        try:
            os.stat(path.name, dir_fd=directory_fd, follow_symlinks=False)
            exists = True
        except FileNotFoundError:
            exists = False
        bind_directory_fd(path.parent, directory_fd)
        return exists
    except (AtomicFileError, OSError) as exc:
        raise ReviewError(f"无法安全检查{label}: {path}；{exc}") from exc
    finally:
        if directory_fd >= 0:
            os.close(directory_fd)


def _sha256_value(value: object, *, label: str) -> str:
    text = str(value or "")
    if not re.fullmatch(r"[0-9a-f]{64}", text):
        raise ReviewError(f"{label} 不是合法 SHA-256")
    return text


def _handoff_path(manifest_path: Path) -> Path:
    return manifest_path.parent / "handoff.json"


def _load_handoff_marker(
    manifest_path: Path,
    manifest: dict[str, Any],
    *,
    plan_path: Path | None = None,
    plan: dict[str, Any] | None = None,
) -> dict[str, Any] | None:
    marker_path = _handoff_path(manifest_path)
    marker_exists = _entry_exists(marker_path, label="handoff.json")
    if not marker_exists:
        if isinstance(plan, dict) and plan.get("state") == "handed_off":
            raise ReviewError("apply-plan.json 已标记 handed_off，但缺少 handoff.json 证据")
        return None

    if plan is None:
        plan_path = _canonical_regular_file(
            manifest_path.parent / "apply-plan.json",
            label="handoff 批次 apply-plan.json",
        )
        plan = _load_json_object(plan_path, label="apply-plan.json")

    marker_path = _canonical_regular_file(marker_path, label="handoff.json")
    marker = _load_json_object(marker_path, label="handoff.json")
    review_binding = marker.get("review")
    draft_binding = marker.get("draft_plan")
    resolutions_binding = marker.get("resolutions")
    target_binding = marker.get("target")
    candidate_binding = marker.get("candidate_manifest")
    product_baseline_binding = marker.get("product_baseline")
    handoff_mode = str(marker.get("handoff_mode") or "")
    route = str(marker.get("route") or "")
    schema_version = _int(marker.get("schema_version"))
    if (
        marker.get("kind") != HANDOFF_KIND
        or schema_version
        not in {LEGACY_HANDOFF_SCHEMA_VERSION, HANDOFF_SCHEMA_VERSION}
        or marker.get("state") != "read_only"
        or marker.get("batch_id") != manifest.get("batch_id")
        or route not in HANDOFF_ROUTES
        or not isinstance(review_binding, dict)
        or review_binding.get("name") != "review.json"
        or not isinstance(draft_binding, dict)
        or draft_binding.get("name") != "apply-plan.json"
        or not isinstance(resolutions_binding, dict)
        or resolutions_binding.get("name") != "resolutions.json"
        or not isinstance(target_binding, dict)
        or target_binding.get("name") != "target.md"
    ):
        raise ReviewError("handoff.json 不是当前批次的完整只读交接证据")
    if schema_version == LEGACY_HANDOFF_SCHEMA_VERSION:
        if not isinstance(candidate_binding, dict):
            raise ReviewError("旧版 handoff.json 缺少 replan candidate 绑定")
    elif handoff_mode == "active_replan":
        if not isinstance(candidate_binding, dict) or product_baseline_binding is not None:
            raise ReviewError("active replan handoff 缺少唯一 candidate manifest 绑定")
    elif handoff_mode == "direct_product_change":
        if (
            route != "proposal"
            or candidate_binding is not None
            or not isinstance(product_baseline_binding, dict)
            or product_baseline_binding.get("route") != "proposal"
            or product_baseline_binding.get("branch") not in {"main", "master"}
            or product_baseline_binding.get("active_build_count") != 0
            or not re.fullmatch(
                r"[0-9a-f]{40,64}",
                str(product_baseline_binding.get("repo_head") or ""),
            )
        ):
            raise ReviewError("无 active build 的产品级 handoff 基线绑定不完整")
    else:
        raise ReviewError("handoff.json 缺少可识别的交接模式")
    if _sha256_value(review_binding.get("sha256"), label="handoff review.sha256") != _file_digest(
        manifest_path
    ):
        raise ReviewError("handoff.json 绑定的 review.json 已变化")
    draft_sha = _sha256_value(
        draft_binding.get("sha256"), label="handoff draft_plan.sha256"
    )
    for binding, name in (
        (resolutions_binding, "resolutions.json"),
        (target_binding, "target.md"),
    ):
        expected_sha = _sha256_value(
            binding.get("sha256"), label=f"handoff {name}.sha256"
        )
        if expected_sha != _file_digest(manifest_path.parent / name):
            raise ReviewError(f"handoff.json 绑定的 {name} 已变化")
    if isinstance(candidate_binding, dict):
        _sha256_value(
            candidate_binding.get("sha256"),
            label="handoff candidate_manifest.sha256",
        )
        if candidate_binding.get("route") != route:
            raise ReviewError("handoff.json 的 route 与 candidate manifest 绑定不一致")

    if plan is not None:
        if plan_path is None:
            raise ReviewError("内部错误：校验 handoff plan 时缺少路径")
        if plan.get("batch_id") != manifest.get("batch_id"):
            raise ReviewError("handoff 批次与 apply-plan.json 不匹配")
        if plan.get("state") == "draft":
            if _file_digest(plan_path) != draft_sha:
                raise ReviewError("handoff 前的 draft apply-plan.json 已变化")
        elif plan.get("state") == "handed_off":
            handoff_binding = plan.get("handoff")
            if (
                not isinstance(handoff_binding, dict)
                or handoff_binding.get("name") != "handoff.json"
                or handoff_binding.get("route") != route
                or _sha256_value(
                    handoff_binding.get("sha256"),
                    label="apply-plan handoff.sha256",
                )
                != _file_digest(marker_path)
                or handoff_binding.get("draft_plan_sha256") != draft_sha
            ):
                raise ReviewError("apply-plan.json 的 handed_off 绑定不完整或已变化")
        else:
            raise ReviewError("handoff 批次的 apply-plan.json 状态不合法")
    return marker


def _reject_read_only_handoff(
    manifest_path: Path,
    manifest: dict[str, Any],
    *,
    plan_path: Path | None = None,
    plan: dict[str, Any] | None = None,
) -> None:
    marker = _load_handoff_marker(
        manifest_path,
        manifest,
        plan_path=plan_path,
        plan=plan,
    )
    if marker is not None:
        raise ReviewError(
            "当前评审批次已经转为只读 handoff；旧批只作上游交接证据，"
            "禁止 reconcile/seal/apply，请在 main 完成上游归位并同步同篇飞书后 fresh collect"
        )


def _write_text(path: Path, content: str) -> str:
    path = _absolute_lexical_path(path)
    try:
        write_text_atomically(
            path,
            content,
            require_canonical_path=True,
            create_mode=0o600,
        )
    except AtomicFileError as exc:
        raise ReviewError(f"无法安全写入评审产物: {path}；{exc}") from exc
    return str(path)


def _write_json(path: Path, value: dict[str, Any]) -> str:
    return _write_text(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def _read_regular_text(path: Path, *, label: str) -> str:
    raw = _read_regular_bytes(path, label=label)
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ReviewError(f"{label} 不是合法 UTF-8 文本: {path}") from exc


def _file_digest(path: Path) -> str:
    return hashlib.sha256(_read_regular_bytes(path, label="摘要目标")).hexdigest()


def _load_json_object(path: Path, *, label: str) -> dict[str, Any]:
    value = json.loads(_read_regular_text(path, label=label))
    if not isinstance(value, dict):
        raise ReviewError(f"{label} 顶层必须是对象")
    return value


def _manifest_path(args_value: str) -> Path:
    path = _absolute_lexical_path(Path(args_value))
    if path.name != "review.json":
        raise ReviewError("评审清单必须使用 collect 生成的 review.json")
    return _canonical_regular_file(path, label="review.json")


def _load_manifest(path: Path) -> dict[str, Any]:
    manifest = _load_json_object(path, label="review.json")
    if _int(manifest.get("schema_version")) not in {
        LEGACY_REVIEW_SCHEMA_VERSION,
        SCHEMA_VERSION,
    }:
        raise ReviewError("review.json schema_version 不受支持，请重新 collect")
    return manifest


def _artifact_path(
    manifest_path: Path,
    value: object,
    *,
    expected_name: str,
    label: str,
) -> Path:
    raw = _absolute_lexical_path(Path(str(value or "")))
    if raw.name != expected_name or raw.parent != manifest_path.parent:
        raise ReviewError(f"review.json 的 {label} 不在本评审目录或文件名异常")
    return _canonical_regular_file(raw, label=f"review.json 的 {label}")


@dataclass(frozen=True)
class _BodyChange:
    source: str
    start: int
    end: int
    replacement: tuple[str, ...]


def _body_lines(text: str) -> list[str]:
    return _normalise(text).splitlines(keepends=True)


def _body_changes(baseline: list[str], variant: list[str], source: str) -> list[_BodyChange]:
    changes: list[_BodyChange] = []
    matcher = difflib.SequenceMatcher(None, baseline, variant, autojunk=False)
    for tag, start, end, replacement_start, replacement_end in matcher.get_opcodes():
        if tag == "equal":
            continue
        changes.append(
            _BodyChange(
                source=source,
                start=start,
                end=end,
                replacement=tuple(variant[replacement_start:replacement_end]),
            )
        )
    return changes


def _changes_interact(left: _BodyChange, right: _BodyChange) -> bool:
    if left.source == right.source:
        return False
    if left.start == left.end:
        return right.start <= left.start <= right.end
    if right.start == right.end:
        return left.start <= right.start <= left.end
    return max(left.start, right.start) < min(left.end, right.end)


def _change_clusters(changes: list[_BodyChange]) -> list[list[_BodyChange]]:
    remaining = set(range(len(changes)))
    clusters: list[list[_BodyChange]] = []
    while remaining:
        seed = min(remaining)
        remaining.remove(seed)
        component = {seed}
        queue = [seed]
        while queue:
            current = queue.pop()
            neighbours = [
                index
                for index in list(remaining)
                if _changes_interact(changes[current], changes[index])
            ]
            for index in neighbours:
                remaining.remove(index)
                component.add(index)
                queue.append(index)
        clusters.append([changes[index] for index in sorted(component)])
    return sorted(
        clusters,
        key=lambda cluster: (
            min(change.start for change in cluster),
            max(change.end for change in cluster),
        ),
    )


def _cluster_segment(
    baseline: list[str],
    cluster: list[_BodyChange],
    source: str,
) -> tuple[int, int, list[str]]:
    start = min(change.start for change in cluster)
    end = max(change.end for change in cluster)
    selected = sorted(
        (change for change in cluster if change.source == source),
        key=lambda change: (change.start, change.end),
    )
    output: list[str] = []
    cursor = start
    for change in selected:
        if change.start < cursor:
            raise ReviewError("三方差异内部重叠，无法确定性归位")
        output.extend(baseline[cursor:change.start])
        output.extend(change.replacement)
        cursor = change.end
    output.extend(baseline[cursor:end])
    return start, end, output


def _conflict_marker(
    change_id: str,
    baseline: list[str],
    local: list[str],
    remote: list[str],
) -> list[str]:
    return [
        f"<<<<<<< LOCAL {change_id}\n",
        *local,
        f"||||||| BASELINE {change_id}\n",
        *baseline,
        "=======\n",
        *remote,
        f">>>>>>> REMOTE {change_id}\n",
    ]


def _default_target_derivation() -> dict[str, str]:
    return {
        "mode": "reconciled",
        "authority": "rule",
        "reason": "T 与正文归位结果一致",
    }


def _resolution_maps(
    path: Path | None,
    *,
    expected_batch_id: str | None = None,
) -> tuple[
    dict[str, dict[str, Any]],
    dict[str, dict[str, Any]],
    dict[str, Any],
    list[dict[str, Any]],
    dict[str, Any],
    list[dict[str, Any]],
    dict[str, Any],
    dict[str, Any] | None,
]:
    if path is None:
        return (
            {},
            {},
            _default_target_derivation(),
            [],
            _default_preview_resolution(),
            [],
            _default_consistency_receipt(),
            None,
        )
    value = _load_json_object(path, label="resolutions.json")
    schema_version = _int(value.get("schema_version"))
    if schema_version not in {
        RESOLUTION_SCHEMA_VERSION,
        PREVIOUS_RESOLUTION_SCHEMA_VERSION,
    }:
        raise ReviewError("resolutions.json schema_version 不受支持")
    batch_id = str(value.get("batch_id") or "")
    if not batch_id:
        raise ReviewError("resolutions.json 缺少 batch_id")
    if expected_batch_id is not None and batch_id != expected_batch_id:
        raise ReviewError("resolutions.json 与 review.json 批次不匹配")

    def index(items: object, key: str, label: str) -> dict[str, dict[str, Any]]:
        if not isinstance(items, list):
            raise ReviewError(f"resolutions.json 的 {label} 必须是数组")
        output: dict[str, dict[str, Any]] = {}
        for item in items:
            if not isinstance(item, dict) or not str(item.get(key) or ""):
                raise ReviewError(f"resolutions.json 的 {label} 存在缺少 {key} 的条目")
            item_id = str(item[key])
            if item_id in output:
                raise ReviewError(f"resolutions.json 的 {label} 重复: {item_id}")
            output[item_id] = item
        return output

    target = value.get("target")
    if not isinstance(target, dict):
        raise ReviewError("resolutions.json 缺少 target 派生说明")
    remote_coverage = value.get("remote_coverage")
    if not isinstance(remote_coverage, list):
        raise ReviewError("resolutions.json 的 remote_coverage 必须是数组")
    preview = value.get("preview")
    if not isinstance(preview, dict):
        raise ReviewError("resolutions.json 缺少 preview 确认")
    decision_routing = value.get("decision_routing")
    if not isinstance(decision_routing, list):
        raise ReviewError("resolutions.json 的 decision_routing 必须是数组")
    consistency = value.get("consistency", _default_consistency_receipt())
    if not isinstance(consistency, dict):
        raise ReviewError("resolutions.json 的 consistency 必须是对象")
    active_build_delta = value.get("active_build_delta")
    if active_build_delta is not None and not isinstance(active_build_delta, dict):
        raise ReviewError("resolutions.json 的 active_build_delta 必须是对象或 null")
    return (
        index(value.get("body"), "change_id", "body"),
        index(value.get("comments"), "comment_id", "comments"),
        target,
        remote_coverage,
        preview,
        decision_routing,
        consistency,
        active_build_delta,
    )


def _default_preview_resolution() -> dict[str, Any]:
    return {
        "approved": False,
        "authority": "pending",
        "reason": "",
    }


def _default_consistency_receipt() -> dict[str, Any]:
    return {
        "status": "not_required",
        "target_sha256": "",
        "source_hashes": [],
        "candidate_decision_ids": [],
        "reviewed_active_decision_ids": [],
        "checks": [],
    }


def _markdown_sections(text: str) -> list[tuple[str, str]]:
    text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)
    matches = list(re.finditer(r"(?m)^(#{2,4})\s+(.+?)\s*$", text))
    sections: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        sections.append((match.group(2).strip(), text[start:end].strip()))
    return sections


def _decision_inventory(repo_root: Path) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    candidates: list[Path] = []
    product_rules = repo_root / "PRODUCT-RULES.md"
    if product_rules.is_file():
        candidates.append(product_rules)
    decisions_root = repo_root / "docs" / "decisions"
    if decisions_root.is_dir():
        candidates.extend(sorted(decisions_root.glob("*.md")))
    modules_root = repo_root / "docs" / "modules"
    if modules_root.is_dir():
        candidates.extend(sorted(modules_root.glob("*/decisions.md")))

    source_hashes: list[dict[str, str]] = []
    active: list[dict[str, str]] = []
    for path in candidates:
        canonical = _canonical_regular_file(path, label="一致性扫描决定源")
        relative = canonical.relative_to(repo_root).as_posix()
        text = _read_regular_text(canonical, label="一致性扫描决定源")
        source_hashes.append({"path": relative, "sha256": _sha256_text(text)})
        module_decisions = relative.startswith("docs/modules/")
        frozen_project_decision = relative.startswith("docs/decisions/")
        sections = _markdown_sections(text)
        if frozen_project_decision and not sections:
            sections = [(path.stem, re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL).strip())]
        for title, body in sections:
            label = re.sub(r"^\d+[.、：:\s-]*", "", title).strip()
            if label in {
                "已拍板决策",
                "共同理由",
                "否过的方案",
                "待复核决策",
                "规则清单",
                "参考材料",
                "变更日志",
                "变更记录",
                "版本信息",
                "名词解释",
                "讨论记录",
                "未决问题",
                "待确认问题",
            }:
                continue
            decision_match = re.match(r"^D\d+(?:[.、：:\s-]|$)", title, re.IGNORECASE)
            if module_decisions and decision_match is None:
                continue
            if not body or decision_is_question(title, body) or decision_is_superseded(title, body):
                continue
            decision_id = (
                decision_match.group(0).rstrip(".、：: -")
                if decision_match is not None
                else hashlib.sha256(f"{relative}:{title}".encode("utf-8")).hexdigest()[:12]
            )
            active.append(
                {
                    "id": f"{relative}#{decision_id}",
                    "path": relative,
                    "decision_id": decision_id,
                }
            )
    return source_hashes, active


def _validate_consistency_receipt(
    receipt: dict[str, Any],
    *,
    routes: list[dict[str, Any]],
    repo_root: Path,
    target_body: str,
) -> dict[str, Any]:
    decision_routes = [
        item for item in routes if item.get("outcome") in {"create", "supersede"}
    ]
    if not decision_routes:
        if receipt != _default_consistency_receipt():
            raise ReviewError("本批没有产品决定变化，consistency receipt 必须为 not_required")
        return receipt

    source_hashes, active = _decision_inventory(repo_root)
    candidate_ids = sorted(
        f"{item['target_path']}#{item['decision_id']}" for item in decision_routes
    )
    active_ids = sorted(item["id"] for item in active)
    if (
        receipt.get("status") not in {"checked", "needs_pm"}
        or receipt.get("target_sha256") != _sha256_text(target_body)
        or receipt.get("source_hashes") != source_hashes
        or receipt.get("candidate_decision_ids") != candidate_ids
        or receipt.get("reviewed_active_decision_ids") != active_ids
    ):
        raise ReviewError("seal 前缺少绑定当前 target 与有效决定清单的一致性回执")
    checks = receipt.get("checks")
    if not isinstance(checks, list):
        raise ReviewError("consistency receipt 的 checks 必须是数组")
    expected_pairs = {(candidate, active_id) for candidate in candidate_ids for active_id in active_ids}
    actual_pairs: set[tuple[str, str]] = set()
    needs_pm = False
    superseded_by_candidate = {
        (
            f"{route['target_path']}#{route['decision_id']}",
            f"{route['target_path']}#{old_id}",
        )
        for route in decision_routes
        for old_id in route.get("supersedes") or []
    }
    for item in checks:
        if not isinstance(item, dict) or set(item) != {
            "candidate_decision_id",
            "active_decision_id",
            "status",
            "reason",
        }:
            raise ReviewError("consistency receipt check schema 不完整")
        pair = (
            str(item.get("candidate_decision_id") or ""),
            str(item.get("active_decision_id") or ""),
        )
        status = str(item.get("status") or "")
        reason = str(item.get("reason") or "").strip()
        if pair in actual_pairs or pair not in expected_pairs:
            raise ReviewError("consistency receipt 包含重复或批次外决定对")
        if status not in {"compatible", "supersedes", "needs_pm"} or not reason:
            raise ReviewError("consistency receipt check 缺少有效结论或原因")
        if pair in superseded_by_candidate and status != "supersedes":
            raise ReviewError("decision_routing 声明的 supersede 未进入一致性回执")
        actual_pairs.add(pair)
        needs_pm = needs_pm or status == "needs_pm"
    if actual_pairs != expected_pairs:
        raise ReviewError("consistency receipt 未覆盖全部当前有效决定")
    if needs_pm or receipt.get("status") == "needs_pm":
        raise ReviewError("产品决定存在需要 PM 拍板的一致性冲突，不能 seal")
    return receipt


def _decision_routing_template(
    body_records: list[dict[str, Any]],
    comment_records: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for source_type, records, key in (
        ("body", body_records, "change_id"),
        ("comment", comment_records, "comment_id"),
    ):
        for record in records:
            output.append(
                {
                    "source_type": source_type,
                    "source_id": str(record.get(key) or ""),
                    "outcome": "pending",
                    "target_path": "",
                    "decision_id": "",
                    "supersedes": [],
                    "summary": "",
                    "reason": "",
                }
            )
    return output


def _validate_decision_routing(
    routes: list[dict[str, Any]],
    *,
    body_records: list[dict[str, Any]],
    comment_records: list[dict[str, Any]],
    repo_root: Path,
) -> list[dict[str, Any]]:
    expected = {
        *(
            ("body", str(item.get("change_id") or ""))
            for item in body_records
        ),
        *(
            ("comment", str(item.get("comment_id") or ""))
            for item in comment_records
        ),
    }
    required_keys = {
        "source_type",
        "source_id",
        "outcome",
        "target_path",
        "decision_id",
        "supersedes",
        "summary",
        "reason",
    }
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = {}
    normalised: list[dict[str, Any]] = []
    seen_decision_ids: set[str] = set()
    for raw in routes:
        if not isinstance(raw, dict) or set(raw) != required_keys:
            raise ReviewError("decision_routing 条目 schema 不完整或包含未知字段")
        source = (
            str(raw.get("source_type") or ""),
            str(raw.get("source_id") or ""),
        )
        if source not in expected:
            raise ReviewError(f"decision_routing 包含当前批次之外的来源: {source}")
        outcome = str(raw.get("outcome") or "")
        target_path = str(raw.get("target_path") or "").strip()
        decision_id = str(raw.get("decision_id") or "").strip()
        summary = str(raw.get("summary") or "").strip()
        reason = str(raw.get("reason") or "").strip()
        supersedes_raw = raw.get("supersedes")
        if not isinstance(supersedes_raw, list) or any(
            not isinstance(item, str) or not item.strip() for item in supersedes_raw
        ):
            raise ReviewError("decision_routing.supersedes 必须是非空字符串数组或空数组")
        supersedes = [item.strip() for item in supersedes_raw]
        if len(set(supersedes)) != len(supersedes):
            raise ReviewError("decision_routing.supersedes 不能重复")
        if outcome == "pending":
            raise ReviewError(f"{source[0]} {source[1]} 尚未完成 decision 归档路由")
        if outcome == "not_required":
            if target_path or decision_id or supersedes or summary or not reason:
                raise ReviewError(
                    f"{source[0]} {source[1]} 的 not_required 只能填写 reason"
                )
        elif outcome in {"create", "supersede"}:
            if (
                not target_path
                or not decision_id
                or not summary
                or not reason
            ):
                raise ReviewError(
                    f"{source[0]} {source[1]} 的 decision 写入缺少安全目标、ID、摘要或原因"
                )
            target_path = _decision_target_path(repo_root, target_path)
            if outcome == "create" and supersedes:
                raise ReviewError("新建 decision 不能同时填写 supersedes")
            if outcome == "supersede" and not supersedes:
                raise ReviewError("supersede decision 必须列出被替代的决定 ID")
            if decision_id in seen_decision_ids:
                raise ReviewError(f"decision_routing 重复 decision_id: {decision_id}")
            seen_decision_ids.add(decision_id)
        else:
            raise ReviewError(f"decision_routing.outcome 不受支持: {outcome}")
        item = {
            "source_type": source[0],
            "source_id": source[1],
            "outcome": outcome,
            "target_path": target_path,
            "decision_id": decision_id,
            "supersedes": supersedes,
            "summary": summary,
            "reason": reason,
        }
        grouped.setdefault(source, []).append(item)
        normalised.append(item)
    missing = sorted(expected - set(grouped))
    if missing:
        raise ReviewError(f"decision_routing 未覆盖全部正文 / 评论来源: {missing}")
    for source, items in grouped.items():
        if len(items) > 1 and any(item["outcome"] == "not_required" for item in items):
            raise ReviewError(f"{source} 不能同时标记 not_required 和写入 decision")
    return normalised


def _preflight() -> None:
    current = version()
    if current is None or current < MIN_LARK_REVIEW_CLI_VERSION:
        minimum = ".".join(str(value) for value in MIN_LARK_REVIEW_CLI_VERSION)
        actual = "无法解析" if current is None else ".".join(str(value) for value in current)
        raise ReviewError(f"lark-cli 版本 {actual} 不满足最低要求 {minimum}")
    ok, detail = auth_status()
    if not ok:
        raise ReviewError(f"飞书 CLI 未登录；请先完成 lark-cli auth login。详情: {detail}")


def _fetch_current_pair(doc_ref: str) -> tuple[dict[str, Any], dict[str, Any]]:
    """取得同一 revision 的 Markdown 与 full XML 原生快照。"""
    for _ in range(2):
        _PERF_COUNTERS["document_fetch_api_calls"] += 1
        markdown = _document(docs_fetch(doc_ref, doc_format="markdown", detail="simple"))
        markdown_revision = _int(markdown.get("revision_id"))
        if markdown_revision is None:
            continue
        _PERF_COUNTERS["document_fetch_api_calls"] += 1
        xml = _document(
            docs_fetch(
                doc_ref,
                doc_format="xml",
                detail="full",
                revision_id=markdown_revision,
            )
        )
        xml_revision = _int(xml.get("revision_id"))
        markdown_id = str(markdown.get("document_id") or "")
        xml_id = str(xml.get("document_id") or "")
        if (
            markdown_id
            and markdown_id == xml_id
            and markdown_revision is not None
            and markdown_revision == xml_revision
        ):
            return markdown, xml
    raise ReviewError("采集期间飞书正文 revision 持续变化，请停止编辑后重试")


def _collect_comments_once(
    doc_id: str,
    *,
    blocks: dict[str, dict[str, str]],
    token_to_block: dict[str, str],
) -> list[dict[str, Any]]:
    _PERF_COUNTERS["comment_full_scans"] += 1
    comments: list[dict[str, Any]] = []
    seen_comment_ids: set[str] = set()
    for solved_state in (False, True):
        state_comments = _paginate(
            lambda token, solved=solved_state: drive_comments_page(
                doc_id,
                page_token=token,
                is_solved=solved,
                need_relation=True,
            ),
            label="已解决评论列表" if solved_state else "未解决评论列表",
            metric="comment_list_api_calls",
        )
        if any(bool(comment.get("is_solved")) != solved_state for comment in state_comments):
            label = "已解决" if solved_state else "未解决"
            raise ReviewError(f"{label}评论查询返回了状态不匹配的评论")
        state_ids = [str(item.get("comment_id") or "") for item in state_comments]
        if any(not comment_id for comment_id in state_ids):
            raise ReviewError("评论列表存在缺少 comment_id 的条目")
        if len(set(state_ids)) != len(state_ids):
            raise ReviewError("单一解决状态的评论分页返回重复 comment_id")
        if seen_comment_ids.intersection(state_ids):
            raise CommentSnapshotRace("评论在已解决 / 未解决查询间切换状态")
        seen_comment_ids.update(state_ids)
        comments.extend(state_comments)
    output: list[dict[str, Any]] = []
    for comment in comments:
        reply_list = comment.get("reply_list")
        if reply_list is not None and not isinstance(reply_list, dict):
            raise ReviewError("评论 reply_list 不是对象")
        embedded = reply_list.get("replies", []) if isinstance(reply_list, dict) else []
        if not isinstance(embedded, list) or any(
            not isinstance(reply, dict) for reply in embedded
        ):
            raise ReviewError("评论 reply_list.replies 不是对象数组")
        replies = embedded
        if comment.get("has_more") or not replies:
            comment_id = str(comment.get("comment_id") or "")
            if not comment_id:
                raise ReviewError("评论缺少 comment_id，无法补齐回复")
            replies = _paginate(
                lambda token, cid=comment_id: drive_comment_replies_page(
                    doc_id, cid, page_token=token
                ),
                label=f"评论 {comment_id} 回复",
                metric="comment_reply_api_calls",
            )
        replies = _dedupe_replies(replies)
        comment_id = str(comment.get("comment_id") or "")
        if not replies:
            raise ReviewError(f"评论 {comment_id} 未返回承载评论正文的首条 reply")
        reply_views = [_reply_view(reply) for reply in replies]
        comment_time = _event_time(comment)
        reply_times = [_event_time(reply) for reply in replies]
        update_time = max([comment_time, *reply_times], default=0)
        output.append(
            {
                "comment_id": comment.get("comment_id"),
                "user_id": comment.get("user_id"),
                "create_time": _int(comment.get("create_time")),
                "_comment_event_time": comment_time,
                "update_time": update_time,
                "is_solved": bool(comment.get("is_solved")),
                "solved_time": _int(comment.get("solved_time")),
                "solver_user_id": str(comment.get("solver_user_id") or ""),
                "is_whole": bool(comment.get("is_whole")),
                "quote": comment.get("quote") or "",
                "location": _locate_comment(comment, blocks, token_to_block),
                "replies": reply_views,
            }
        )
    return output


def _with_comment_cursor(
    items: list[dict[str, Any]],
    *,
    reviewed_comment_at: int,
    reviewed_comment_ids: set[str],
) -> tuple[list[dict[str, Any]], int, list[str]]:
    output: list[dict[str, Any]] = []
    max_update_time = reviewed_comment_at
    max_update_ids = set(reviewed_comment_ids)
    for item in items:
        comment_id = str(item.get("comment_id") or "")
        update_time = _int(item.get("update_time")) or 0
        event_ids: set[str] = set()
        comment_time = _int(item.get("_comment_event_time")) or 0
        if comment_time == update_time:
            event_ids.add(f"comment:{comment_id}")
        replies = item.get("replies") if isinstance(item.get("replies"), list) else []
        for reply in replies:
            if not isinstance(reply, dict):
                raise ReviewError("评论快照的 replies 包含非对象条目")
            if _event_time(reply) == update_time:
                event_ids.add(f"reply:{reply.get('reply_id')}")
        is_new = update_time > reviewed_comment_at or (
            update_time == reviewed_comment_at
            and bool(event_ids - reviewed_comment_ids)
        )
        if update_time > max_update_time:
            max_update_time = update_time
            max_update_ids = set(event_ids)
        elif update_time == max_update_time:
            max_update_ids.update(event_ids)
        marked = {
            **item,
            "comment_event_time": comment_time,
            "new_since_checkpoint": is_new,
        }
        marked.pop("_comment_event_time", None)
        output.append(marked)
    return output, max_update_time, sorted(max_update_ids)


def _comment_cursor_from_snapshot(
    items: list[dict[str, Any]],
) -> tuple[int, list[str]]:
    """从已稳定的公开评论快照计算 checkpoint 水位，不触发再次远端扫描。"""
    max_update_time = 0
    max_update_ids: set[str] = set()
    for item in items:
        comment_id = str(item.get("comment_id") or "")
        update_time = _int(item.get("update_time")) or 0
        event_ids: set[str] = set()
        comment_time = _int(item.get("comment_event_time")) or 0
        if comment_id and comment_time == update_time:
            event_ids.add(f"comment:{comment_id}")
        replies = item.get("replies") if isinstance(item.get("replies"), list) else []
        for reply in replies:
            if isinstance(reply, dict) and _event_time(reply) == update_time:
                event_ids.add(f"reply:{reply.get('reply_id')}")
        if update_time > max_update_time:
            max_update_time = update_time
            max_update_ids = event_ids
        elif update_time == max_update_time:
            max_update_ids.update(event_ids)
    return max_update_time, sorted(max_update_ids)


def _stable_comments(
    doc_id: str,
    *,
    blocks: dict[str, dict[str, str]],
    token_to_block: dict[str, str],
) -> list[dict[str, Any]]:
    previous_hash: str | None = None
    stable_items: list[dict[str, Any]] | None = None
    for _ in range(MAX_COMMENT_STABILITY_SCANS):
        try:
            current_items = _collect_comments_once(
                doc_id,
                blocks=blocks,
                token_to_block=token_to_block,
            )
        except CommentSnapshotRace:
            previous_hash = None
            continue
        current_hash = _comment_fence_hash(current_items)
        if previous_hash == current_hash:
            stable_items = current_items
            break
        previous_hash = current_hash
    if stable_items is None:
        raise ReviewError(
            "飞书全量评论围栏连续读取不稳定；请停止编辑后重新执行"
        )
    return stable_items


def _collect_comments(
    doc_id: str,
    *,
    include_solved: bool,
    blocks: dict[str, dict[str, str]],
    token_to_block: dict[str, str],
    reviewed_comment_at: int,
    reviewed_comment_ids: set[str],
) -> tuple[list[dict[str, Any]], int, list[str]]:
    stable_items = _stable_comments(
        doc_id,
        blocks=blocks,
        token_to_block=token_to_block,
    )
    selected = (
        stable_items
        if include_solved
        else [item for item in stable_items if not bool(item.get("is_solved"))]
    )
    return _with_comment_cursor(
        selected,
        reviewed_comment_at=reviewed_comment_at,
        reviewed_comment_ids=reviewed_comment_ids,
    )


def collect(args: argparse.Namespace) -> int:
    collect_started = time.monotonic()
    markdown_path = _canonical_regular_file(
        Path(args.markdown),
        label="本地 markdown",
    )
    raw = _read_regular_text(markdown_path, label="本地 markdown")
    frontmatter, local_body = parse_frontmatter(raw)
    frontmatter_doc_id = str(frontmatter.get("lark_doc_id") or "")
    frontmatter_url = frontmatter.get("lark_doc_url")
    frontmatter_url_token = _docx_token(frontmatter_url)
    if frontmatter_url and frontmatter_url_token is None:
        raise ReviewError(
            "lark-review 只支持飞书 Docx 链接；本地 lark_doc_url 不是 Docx"
        )
    doc_ref = args.doc or frontmatter.get("lark_doc_url") or frontmatter.get("lark_doc_id")
    if not doc_ref:
        raise ReviewError("缺少飞书链接/token，且本地 frontmatter 没有 lark_doc_id/lark_doc_url")
    if "://" in str(doc_ref) and _docx_token(doc_ref) is None:
        raise ReviewError("lark-review 只支持飞书 Docx 链接；旧版 /doc/ 或 wiki 链接请先迁移")
    input_token = _docx_token(args.doc) if args.doc else None
    if input_token and frontmatter_doc_id and input_token != frontmatter_doc_id:
        raise ReviewError(
            f"--doc 指向 {input_token}，但本地 lark_doc_id 是 {frontmatter_doc_id}"
        )
    if input_token and frontmatter_url_token and input_token != frontmatter_url_token:
        raise ReviewError(
            f"--doc 指向 {input_token}，但本地 lark_doc_url 指向 {frontmatter_url_token}"
        )
    if not frontmatter_doc_id and not frontmatter_url_token:
        raise ReviewError(
            "本地 markdown 缺少 lark_doc_id 或 Docx lark_doc_url；"
            "拒绝生成无法绑定回本地规格的评审批次"
        )
    repo_root = _repository_root(markdown_path)

    output_dir = _prepare_empty_directory(
        Path(args.output_dir),
        label="评审产物目录",
    )

    _preflight()
    fetch_started = time.monotonic()
    current_markdown, current_xml = _fetch_current_pair(str(doc_ref))
    initial_fetch_seconds = time.monotonic() - fetch_started
    remote_body = str(current_markdown["content"])
    current_revision = _int(current_markdown.get("revision_id"))
    doc_id = str(
        current_markdown.get("document_id")
        or frontmatter.get("lark_doc_id")
        or ""
    )
    if not doc_id:
        raise ReviewError("飞书读取结果和本地 frontmatter 都缺少 document_id")
    if frontmatter_doc_id and frontmatter_doc_id != doc_id:
        raise ReviewError(
            f"输入飞书文档 {doc_id} 与本地 frontmatter 的 {frontmatter_doc_id} 不一致"
        )
    if frontmatter_url_token and frontmatter_url_token != doc_id:
        raise ReviewError(
            f"飞书读取结果 {doc_id} 与本地 lark_doc_url 的 {frontmatter_url_token} 不一致"
        )
    if input_token and input_token != doc_id:
        raise ReviewError(f"--doc 指向 {input_token}，但飞书实际返回文档 {doc_id}")

    warnings: list[str] = []
    blocks, token_to_block, xml_warning = _xml_indexes(str(current_xml["content"]))
    if xml_warning:
        warnings.append(xml_warning)

    published_revision = _int(frontmatter.get("lark_published_revision_id"))
    published_hash = str(frontmatter.get("lark_published_source_hash") or "") or None
    local_hash = _body_hash(local_body)
    baseline_body: str | None = None
    baseline_status = "missing"
    if published_revision is not None:
        if current_revision == published_revision:
            baseline_body = remote_body
            baseline_status = "revision"
        else:
            try:
                _PERF_COUNTERS["document_fetch_api_calls"] += 1
                baseline_document = _document(
                    docs_fetch(
                        str(doc_ref),
                        doc_format="markdown",
                        detail="simple",
                        revision_id=published_revision,
                    )
                )
                baseline_doc_id = str(baseline_document.get("document_id") or "")
                fetched_revision = _int(baseline_document.get("revision_id"))
                if baseline_doc_id != doc_id or fetched_revision != published_revision:
                    raise ReviewError(
                        "历史版本响应与请求不一致："
                        f"期望 {doc_id}@{published_revision}，"
                        f"实际 {baseline_doc_id or 'unknown'}@{fetched_revision}"
                    )
                baseline_body = str(baseline_document["content"])
                baseline_status = "revision"
            except (LarkAdapterError, ReviewError) as exc:
                raise ReviewError(
                    f"已记录的发布 revision {published_revision} 无法读取，不能安全识别正文增量: {exc}"
                ) from exc
    if baseline_body is None and published_hash and local_hash == published_hash:
        baseline_body = local_body
        baseline_status = "local_hash_fallback"
        warnings.append("发布 revision 不可用；因本地正文 hash 未变化，暂用本地正文作为发布基线")

    baseline_hash = _body_hash(baseline_body) if baseline_body is not None else None
    remote_hash = _body_hash(remote_body)
    common_ancestor_compatible = bool(
        baseline_status == "revision"
        and published_hash
        and baseline_hash == published_hash
    )
    if baseline_body is not None and not common_ancestor_compatible:
        warnings.append(
            "飞书历史版与本地发布源不是同格式公共祖先；只能禁止 raw Markdown 三方合并，"
            "目标仍以当前飞书原生快照初始化"
        )

    local_changed = None if not published_hash else local_hash != published_hash
    if baseline_body is not None:
        remote_changed: bool | None = _normalise(remote_body) != _normalise(baseline_body)
    elif published_revision is not None and current_revision is not None:
        remote_changed = current_revision != published_revision
    else:
        remote_changed = None

    if local_changed is None or remote_changed is None:
        body_status = "legacy_baseline"
    elif local_changed and remote_changed:
        body_status = "both_changed"
    elif local_changed:
        body_status = "local_only"
    elif remote_changed:
        body_status = "remote_only"
    else:
        body_status = "unchanged"

    reviewed_comment_at = _int(frontmatter.get("lark_reviewed_comment_at")) or 0
    reviewed_comment_ids = _checkpoint_ids(frontmatter.get("lark_reviewed_comment_ids"))
    comments_started = time.monotonic()
    stable_comment_items = _stable_comments(
        doc_id,
        blocks=blocks,
        token_to_block=token_to_block,
    )
    comments_seconds = time.monotonic() - comments_started
    fence_comments, full_comment_update_time, full_comment_update_ids = _with_comment_cursor(
        stable_comment_items,
        reviewed_comment_at=reviewed_comment_at,
        reviewed_comment_ids=reviewed_comment_ids,
    )
    if args.include_solved:
        comments = fence_comments
        max_comment_update_time = full_comment_update_time
        max_comment_update_ids = full_comment_update_ids
    else:
        comments, max_comment_update_time, max_comment_update_ids = _with_comment_cursor(
            [
                item
                for item in stable_comment_items
                if not bool(item.get("is_solved"))
            ],
            reviewed_comment_at=reviewed_comment_at,
            reviewed_comment_ids=reviewed_comment_ids,
        )

    stable_raw = _read_regular_text(markdown_path, label="本地 markdown")
    if stable_raw != raw:
        raise ReviewError("本地 markdown 在评论采集期间变化，请重新 collect")
    final_fetch_started = time.monotonic()
    _PERF_COUNTERS["document_fetch_api_calls"] += 1
    stable_markdown = _document(
        docs_fetch(str(doc_ref), doc_format="markdown", detail="simple")
    )
    final_fetch_seconds = time.monotonic() - final_fetch_started
    initial_remote_fence = (
        str(current_markdown.get("document_id") or ""),
        _int(current_markdown.get("revision_id")),
        str(current_markdown.get("content") or ""),
    )
    stable_remote_fence = (
        str(stable_markdown.get("document_id") or ""),
        _int(stable_markdown.get("revision_id")),
        str(stable_markdown.get("content") or ""),
    )
    if stable_remote_fence != initial_remote_fence:
        raise ReviewError("飞书正文在评论采集期间变化，请重新 collect")

    local_path = _write_text(output_dir / "local.md", local_body)
    remote_path = _write_text(output_dir / "remote.md", remote_body)
    native_snapshot = build_native_snapshot(current_xml)
    native_path = output_dir / "remote-native.json"
    _write_json(native_path, native_snapshot)
    baseline_path = None
    remote_diff_path = None
    local_diff_path = None
    if baseline_body is not None:
        baseline_path = _write_text(output_dir / "baseline.md", baseline_body)
        remote_diff_path = _write_text(
            output_dir / "remote-vs-baseline.diff",
            _diff(baseline_body, remote_body, "published", "remote-current"),
        )
        local_diff_path = _write_text(
            output_dir / "local-vs-baseline.diff",
            _diff(baseline_body, local_body, "published", "local-current"),
        )
    local_remote_diff_path = _write_text(
        output_dir / "local-vs-remote.diff",
        _diff(local_body, remote_body, "local-current", "remote-current"),
    )

    interaction_count = sum(len(item["replies"]) for item in comments)
    comments_payload = {
        "included_solved": bool(args.include_solved),
        "count": len(comments),
        "interaction_count": interaction_count,
        "reply_count": max(0, interaction_count - len(comments)),
        "new_or_updated_count": sum(1 for item in comments if item["new_since_checkpoint"]),
        "max_update_time": max_comment_update_time,
        "max_update_ids": max_comment_update_ids,
        "items": comments,
    }
    comments_hash = hashlib.sha256(
        json.dumps(
            comments_payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()
    comments_fence_hash = _comment_fence_hash(fence_comments)
    local_exact_hash = hashlib.sha256(local_body.encode("utf-8")).hexdigest()
    remote_exact_hash = hashlib.sha256(remote_body.encode("utf-8")).hexdigest()
    baseline_exact_hash = (
        hashlib.sha256(baseline_body.encode("utf-8")).hexdigest()
        if baseline_body is not None
        else None
    )
    batch_seed = "\0".join(
        [
            doc_id,
            str(current_revision),
            local_exact_hash,
            remote_exact_hash,
            comments_hash,
            comments_fence_hash,
            _file_digest(native_path),
        ]
    )
    batch_id = hashlib.sha256(batch_seed.encode("utf-8")).hexdigest()[:24]
    manifest: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "batch_id": batch_id,
        "markdown_path": str(markdown_path),
        "repo_root": str(repo_root),
        "document": {
            "doc_id": doc_id,
            "doc_url": (
                str(args.doc)
                if args.doc and "://" in str(args.doc)
                else frontmatter.get("lark_doc_url") or str(doc_ref)
            ),
            "published_revision_id": published_revision,
            "current_revision_id": current_revision,
        },
        "body": {
            "status": body_status,
            "baseline_status": baseline_status,
            "local_changed_since_publish": local_changed,
            "remote_changed_since_publish": remote_changed,
            "published_source_hash": published_hash,
            "baseline_source_hash": baseline_hash,
            "local_source_hash": local_hash,
            "remote_source_hash": remote_hash,
            "common_ancestor_compatible": common_ancestor_compatible,
            "target_base": "remote_native_snapshot",
            "baseline_path": baseline_path,
            "local_path": local_path,
            "remote_path": remote_path,
            "remote_vs_baseline_diff": remote_diff_path,
            "local_vs_baseline_diff": local_diff_path,
            "local_vs_remote_diff": local_remote_diff_path,
        },
        "comments": {
            **comments_payload,
            "canonical_sha256": comments_hash,
            "fence_count": len(fence_comments),
            "fence_items": fence_comments,
            "fence_sha256": comments_fence_hash,
        },
        "artifacts": {
            "local.md": {
                "sha256": _file_digest(Path(local_path)),
                "body_sha256": local_hash,
                "exact_body_sha256": local_exact_hash,
            },
            "remote.md": {
                "sha256": _file_digest(Path(remote_path)),
                "body_sha256": remote_hash,
                "exact_body_sha256": remote_exact_hash,
            },
            "remote-native.json": {
                "sha256": _file_digest(native_path),
                "content_sha256": native_snapshot["native"]["content_sha256"],
                "block_count": native_snapshot["native"]["block_count"],
                "resource_count": native_snapshot["native"]["resource_count"],
            },
            **(
                {
                    "baseline.md": {
                        "sha256": _file_digest(Path(baseline_path)),
                        "body_sha256": baseline_hash,
                        "exact_body_sha256": baseline_exact_hash,
                    }
                }
                if baseline_path
                else {}
            ),
        },
        "warnings": warnings,
        "performance": {
            "initial_document_fetch_seconds": round(initial_fetch_seconds, 6),
            "comment_collection_seconds": round(comments_seconds, 6),
            "final_document_fence_seconds": round(final_fetch_seconds, 6),
            "total_seconds": round(time.monotonic() - collect_started, 6),
            "document_full_fetches": 1,
            "document_snapshot_pairs": 1,
            "document_revision_fence_fetches": 1,
            "document_fetch_api_calls": _PERF_COUNTERS[
                "document_fetch_api_calls"
            ],
            **_comment_scan_counters(),
            "target_base_cache": "remote-native.json",
        },
    }
    manifest_path = output_dir / "review.json"
    _write_json(manifest_path, manifest)
    print(json.dumps({
        "manifest": str(manifest_path),
        "batch_id": batch_id,
        "body_status": body_status,
        "comments": len(comments),
        "new_or_updated_comments": manifest["comments"]["new_or_updated_count"],
        "warnings": warnings,
    }, ensure_ascii=False))
    return 0


def _manifest_markdown_path(manifest: dict[str, Any]) -> Path:
    raw_path = Path(str(manifest.get("markdown_path") or ""))
    return _canonical_regular_file(
        raw_path,
        label="review.json 对应的本地 markdown",
    )


def _has_git_marker(candidate: Path) -> bool:
    marker = candidate / ".git"
    try:
        mode = marker.lstat().st_mode
    except OSError:
        return False
    return stat.S_ISDIR(mode) or stat.S_ISREG(mode)


def _is_pmai_repository(candidate: Path) -> bool:
    product_state = candidate / "PRODUCT-STATE.md"
    agent_entries = (candidate / "AGENTS.md", candidate / "CLAUDE.md")
    try:
        _read_regular_bytes(product_state, label="PRODUCT-STATE.md")
    except ReviewError:
        return False
    for entry in agent_entries:
        try:
            if "PMAI" in _read_regular_text(entry, label=entry.name):
                return True
        except ReviewError:
            continue
    return False


def _git_path(markdown_path: Path, argument: str) -> Path | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(markdown_path.parent), "rev-parse", argument],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    value = result.stdout.strip()
    if result.returncode != 0 or not value:
        return None
    raw = Path(value)
    if not raw.is_absolute():
        raw = markdown_path.parent / raw
    try:
        return _canonical_directory(raw, label=f"Git {argument} 目录")
    except ReviewError:
        return None


def _linked_worktree_main_root(markdown_path: Path, git_root: Path) -> Path | None:
    marker = git_root / ".git"
    try:
        if not stat.S_ISREG(marker.lstat().st_mode):
            return None
    except OSError:
        return None
    common_dir = _git_path(markdown_path, "--git-common-dir")
    if common_dir is None or common_dir.name != ".git":
        return None
    try:
        return _canonical_directory(common_dir.parent, label="worktree 主仓根")
    except ReviewError:
        return None


def _repository_root(markdown_path: Path) -> Path:
    markdown_path = _canonical_regular_file(
        markdown_path,
        label="本地 markdown",
    )
    git_candidates = [
        candidate
        for candidate in markdown_path.parents
        if _has_git_marker(candidate)
    ]
    pmai_candidates = [
        candidate for candidate in git_candidates if _is_pmai_repository(candidate)
    ]
    git_root = _git_path(markdown_path, "--show-toplevel")
    if git_root is not None:
        git_root = _canonical_directory(git_root, label="Git 仓根")
        try:
            markdown_path.relative_to(git_root)
        except ValueError as exc:
            raise ReviewError("Git 返回的仓根不包含本地 markdown") from exc
        if git_root in pmai_candidates:
            if len(pmai_candidates) == 1:
                return git_root
            main_root = _linked_worktree_main_root(markdown_path, git_root)
            if (
                len(pmai_candidates) == 2
                and main_root is not None
                and main_root in pmai_candidates
            ):
                return git_root
            raise ReviewError("本地 markdown 位于多个嵌套的 PMAI 仓库中，无法确定写入边界")
        if pmai_candidates:
            raise ReviewError("本地 markdown 位于 PMAI 仓内的独立嵌套 Git 仓库中")
        return git_root

    if len(pmai_candidates) == 1:
        return _canonical_directory(pmai_candidates[0], label="PMAI 仓根")
    if len(pmai_candidates) > 1:
        raise ReviewError("本地 markdown 位于多个嵌套的 PMAI 仓库中，无法确定写入边界")
    if len(git_candidates) > 1:
        raise ReviewError("本地 markdown 位于多个嵌套的 Git 仓库中，无法确定 PMAI 仓根")
    if len(git_candidates) == 1:
        # 兼容旧批次和独立工具调用；一旦出现嵌套 .git 就失败关闭。
        return _canonical_directory(git_candidates[0], label="Git 仓根")
    raise ReviewError("本地 markdown 不在可识别的 Git 仓库中")


def _manifest_repository_root(manifest: dict[str, Any], markdown_path: Path) -> Path:
    current_root = _repository_root(markdown_path)
    recorded = manifest.get("repo_root")
    if recorded is None:
        raise ReviewError("review.json 缺少 collect 时的 PMAI 仓根绑定")
    raw = Path(str(recorded))
    recorded_root = _canonical_directory(raw, label="review.json 记录的仓根")
    if recorded_root != current_root:
        raise ReviewError("本地 markdown 的 PMAI 仓根在 collect 后发生变化")
    try:
        markdown_path.relative_to(recorded_root)
    except ValueError as exc:
        raise ReviewError("本地 markdown 超出 review.json 绑定的 PMAI 仓根") from exc
    return recorded_root


def _git_toplevel(path: Path, *, label: str) -> Path:
    try:
        result = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise ReviewError(f"无法读取{label}的 Git 仓根：{exc}") from exc
    value = result.stdout.strip()
    if result.returncode != 0 or not value:
        raise ReviewError(f"无法读取{label}的 Git 仓根")
    return _canonical_directory(Path(value), label=f"{label} Git 仓根")


def _review_target_scope(relative: Path) -> Path | None:
    """Return the module scope for a supported authoritative specification."""

    parts = relative.parts
    if (
        relative.is_absolute()
        or ".." in parts
        or parts[:2] != ("docs", "modules")
    ):
        return None
    if (
        len(parts) == 3
        and parts[2].endswith(".md")
        and not parts[2].startswith(".")
    ):
        return relative
    if len(parts) >= 4 and parts[2] and not parts[2].startswith("."):
        return Path(*parts[:3])
    return None


def _build_anchor_relative(build: dict[str, Any], *, label: str) -> Path | None:
    raw = build.get("anchor")
    if raw is None or raw == "":
        return None
    if not isinstance(raw, str):
        raise ReviewError(f"{label} build.anchor 不是合法仓内规格路径")
    relative = Path(raw)
    if relative.as_posix() != raw or _review_target_scope(relative) is None:
        raise ReviewError(
            f"{label} build.anchor 必须是 docs/modules/<模块>/... "
            "或 docs/modules/<功能>.md"
        )
    return relative


def resolve_target(args: argparse.Namespace) -> int:
    """Bind a review target to the authoritative active-build worktree, if any."""
    input_path = _canonical_regular_file(
        Path(args.markdown), label="待评审本地 markdown"
    )
    input_root = _repository_root(input_path)
    main_root = _linked_worktree_main_root(input_path, input_root) or input_root
    try:
        relative = input_path.relative_to(input_root)
    except ValueError as exc:
        raise ReviewError("待评审 markdown 不在识别出的仓根内") from exc

    target_scope = _review_target_scope(relative)

    try:
        active_result = list_active_work(
            main_root,
            cwd=input_root,
            strict=True,
        )
    except StateReadError as exc:
        raise ReviewError(f"无法安全读取 active work：{exc}") from exc

    matches: list[dict[str, Any]] = []
    if target_scope is not None:
        for item in active_result["items"]:
            meta = item.get("meta") if isinstance(item, dict) else None
            if not isinstance(meta, dict):
                continue
            build = meta.get("build") if isinstance(meta.get("build"), dict) else {}
            lifecycle = str(
                build.get("lifecycle_state") or meta.get("lifecycle_state") or ""
            )
            if lifecycle not in ACTIVE_BUILD_STATES:
                continue
            work_dir = _canonical_directory(
                Path(item["work_dir"]), label="active work 模块目录"
            )
            active_root = _git_toplevel(work_dir, label="active work")
            try:
                active_module_relative = work_dir.relative_to(active_root)
            except ValueError as exc:
                raise ReviewError("active work 模块目录超出其 Git 仓根") from exc
            anchor_relative = _build_anchor_relative(
                build,
                label=f"active work {meta.get('id') or work_dir.name}",
            )
            if anchor_relative is not None:
                target_matches = anchor_relative == relative
            else:
                # 旧 active work 没有 anchor 时，继续按模块目录绑定模块内规格。
                target_matches = active_module_relative == target_scope
            if not target_matches:
                continue
            candidate = _canonical_regular_file(
                active_root / relative,
                label="active build 中的待评审 markdown",
            )
            matches.append(
                {
                    "markdown_path": candidate,
                    "repo_root": active_root,
                    "work_dir": work_dir,
                    "work_id": str(meta.get("id") or ""),
                    "lifecycle_state": lifecycle,
                }
            )

    if len(matches) > 1:
        identities = "、".join(
            f"{item['work_id'] or '<missing-id>'}@{item['work_dir']}"
            for item in matches
        )
        raise ReviewError(
            "同一评审目标命中多个 active build，拒绝猜测权威副本：" + identities
        )

    selected = matches[0] if matches else None
    markdown_path = selected["markdown_path"] if selected else input_path
    repo_root = selected["repo_root"] if selected else input_root
    print(
        json.dumps(
            {
                "markdown_path": str(markdown_path),
                "repo_root": str(repo_root),
                "main_repo_root": str(main_root),
                "active_work_dir": (
                    str(selected["work_dir"]) if selected is not None else None
                ),
                "active_work_id": (
                    selected["work_id"] if selected is not None else None
                ),
                "lifecycle_state": (
                    selected["lifecycle_state"] if selected is not None else None
                ),
            },
            ensure_ascii=False,
        )
    )
    return 0


def _decision_target_path(repo_root: Path, value: str) -> str:
    raw = Path(value)
    parts = raw.parts
    if (
        not value
        or raw.is_absolute()
        or ".." in parts
        or len(parts) != 4
        or parts[:2] != ("docs", "modules")
        or not parts[2]
        or parts[2].startswith(".")
        or parts[3] != "decisions.md"
    ):
        raise ReviewError(
            "decision_routing.target_path 只允许仓内 "
            "docs/modules/<模块>/decisions.md"
        )

    canonical_root = repo_root.resolve()
    candidate = canonical_root
    for part in parts:
        candidate /= part
        if candidate.is_symlink():
            raise ReviewError("decision_routing.target_path 不能包含 symlink 组件")
    try:
        candidate.resolve(strict=False).relative_to(canonical_root)
    except ValueError as exc:
        raise ReviewError("decision_routing.target_path 超出当前仓库") from exc
    return raw.as_posix()


def _source_artifacts(
    manifest_path: Path,
    manifest: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    artifact_meta = manifest.get("artifacts")
    if not isinstance(artifact_meta, dict):
        raise ReviewError("review.json 缺少快照摘要，请重新 collect")
    body_meta = manifest.get("body")
    if not isinstance(body_meta, dict):
        raise ReviewError("review.json 缺少 body")
    output: dict[str, dict[str, Any]] = {}
    expected_names = ["local.md", "remote.md"]
    if body_meta.get("baseline_path"):
        expected_names.append("baseline.md")
    for name in expected_names:
        meta = artifact_meta.get(name)
        if not isinstance(meta, dict):
            raise ReviewError(f"review.json 缺少 {name} 摘要")
        path = _artifact_path(
            manifest_path,
            manifest_path.parent / name,
            expected_name=name,
            label=name,
        )
        text = _read_regular_text(path, label=name)
        exact_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
        file_hash = _file_digest(path)
        body_hash = _body_hash(text)
        if (
            file_hash != str(meta.get("sha256") or "")
            or exact_hash != str(meta.get("exact_body_sha256") or "")
            or body_hash != str(meta.get("body_sha256") or "")
        ):
            raise ReviewError(f"{name} 已被修改，拒绝混用评审批次")
        output[name] = {
            "path": path,
            "text": text,
            "sha256": file_hash,
            "exact_body_sha256": exact_hash,
            "body_sha256": body_hash,
        }
    return output


def _native_snapshot_artifact(
    manifest_path: Path,
    manifest: dict[str, Any],
) -> dict[str, Any]:
    artifacts = manifest.get("artifacts")
    meta = artifacts.get("remote-native.json") if isinstance(artifacts, dict) else None
    if not isinstance(meta, dict):
        raise ReviewError("review.json 缺少 remote-native.json 摘要，请重新 collect")
    path = _artifact_path(
        manifest_path,
        manifest_path.parent / "remote-native.json",
        expected_name="remote-native.json",
        label="remote-native.json",
    )
    if _file_digest(path) != str(meta.get("sha256") or ""):
        raise ReviewError("remote-native.json 已被修改，拒绝混用评审批次")
    value = _load_json_object(path, label="remote-native.json")
    document = value.get("document")
    manifest_document = manifest.get("document")
    if (
        value.get("kind") != NATIVE_SNAPSHOT_KIND
        or value.get("schema_version") != NATIVE_SNAPSHOT_SCHEMA_VERSION
        or not isinstance(document, dict)
        or not isinstance(manifest_document, dict)
        or str(document.get("document_id") or "") != str(manifest_document.get("doc_id") or "")
        or _int(document.get("revision_id")) != _int(manifest_document.get("current_revision_id"))
    ):
        raise ReviewError("remote-native.json 与 review.json 文档基准不一致")
    return {"path": path, "sha256": _file_digest(path), "value": value}


def _git_provenance_result(
    root: Path,
    *arguments: str,
) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            ["git", "-C", str(root), *arguments],
            capture_output=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise ReviewError(
            f"无法核验 replan candidate 的 Git 来源（{' '.join(arguments)}）：{exc}"
        ) from exc


def _git_worktree_bindings(main_root: Path) -> list[dict[str, str]]:
    result = _git_provenance_result(
        main_root,
        "worktree",
        "list",
        "--porcelain",
        "-z",
    )
    if result.returncode != 0 or (result.stdout and not result.stdout.endswith(b"\0")):
        raise ReviewError("无法读取完整的 Git worktree 清单，拒绝 handoff")

    fields = result.stdout[:-1].split(b"\0") if result.stdout else []
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
            raise ReviewError("Git worktree 清单包含不可识别字段") from exc
        current[key] = os.fsdecode(value_raw) if separator else ""
    return entries


def _verify_replan_candidate_git_provenance(
    *,
    main_root: Path,
    worktree: Path,
    branch: str,
    candidate_head: str,
    baseline: str,
) -> None:
    branch_ref = f"refs/heads/{branch}"
    ref_check = _git_provenance_result(main_root, "check-ref-format", branch_ref)
    if ref_check.returncode != 0:
        raise ReviewError("candidate manifest 的 branch 不是合法 Git branch")

    for oid, label in ((candidate_head, "candidate HEAD"), (baseline, "baseline")):
        exists = _git_provenance_result(main_root, "cat-file", "-e", f"{oid}^{{commit}}")
        if exists.returncode != 0:
            raise ReviewError(f"candidate manifest 的 {label} 不是当前仓可读取的 commit")

    ancestor = _git_provenance_result(
        main_root,
        "merge-base",
        "--is-ancestor",
        baseline,
        candidate_head,
    )
    if ancestor.returncode != 0:
        raise ReviewError("candidate manifest 的 baseline 不是 candidate HEAD 的祖先")

    expected_worktree = str(worktree)
    matches = [
        entry
        for entry in _git_worktree_bindings(main_root)
        if os.path.normpath(entry.get("worktree", "")) == expected_worktree
    ]
    if len(matches) != 1 or matches[0].get("branch") != branch_ref:
        raise ReviewError("candidate manifest 对应的 worktree/branch 已不存在或身份不一致")

    branch_tip_result = _git_provenance_result(
        main_root,
        "rev-parse",
        "--verify",
        f"{branch_ref}^{{commit}}",
    )
    branch_tip = os.fsdecode(branch_tip_result.stdout).strip().lower()
    worktree_head = str(matches[0].get("HEAD") or "").lower()
    oid_pattern = r"[0-9a-f]{40,64}"
    if (
        branch_tip_result.returncode != 0
        or not re.fullmatch(oid_pattern, branch_tip)
        or worktree_head != branch_tip
    ):
        raise ReviewError("candidate manifest 对应的 branch/worktree HEAD 已漂移")

    retained = _git_provenance_result(
        main_root,
        "merge-base",
        "--is-ancestor",
        candidate_head,
        branch_tip,
    )
    if retained.returncode != 0:
        raise ReviewError("candidate manifest 对应分支已不再包含 candidate HEAD")


def _replan_candidate_binding(
    candidate_arg: str,
    *,
    repo_root: Path,
    markdown_path: Path,
    route: str,
) -> dict[str, Any]:
    candidate_path = _canonical_regular_file(
        Path(candidate_arg), label="replan candidate manifest"
    )
    if (
        candidate_path.parent.name != "replan-candidates"
        or candidate_path.parent.parent.name != ".runs"
    ):
        raise ReviewError("candidate manifest 必须位于 main 的 .runs/replan-candidates/")
    main_root = _canonical_directory(
        candidate_path.parent.parent.parent,
        label="candidate manifest 所属 main 仓根",
    )
    candidate = _load_json_object(candidate_path, label="replan candidate manifest")
    mode = str(candidate.get("mode") or "")
    work_id = str(candidate.get("work_id") or "")
    candidate_route = str(candidate.get("route") or "")
    module = str(candidate.get("module") or "")
    main_branch = str(candidate.get("main_branch") or "")
    branch = str(candidate.get("branch") or "")
    if (
        _int(candidate.get("schema_version")) != REPLAN_CANDIDATE_SCHEMA_VERSION
        or mode not in {"main", "worktree"}
        or candidate_route != route
        or route not in HANDOFF_ROUTES
        or not work_id
        or Path(work_id).name != work_id
        or candidate_path.name != f"{work_id}.json"
        or main_branch not in {"main", "master"}
        or not branch
    ):
        raise ReviewError("candidate manifest 的 schema、身份或 route 不合法")
    module_path = Path(module)
    module_parts = module_path.parts
    if len(module_parts) != 3 or module_parts[:2] != ("docs", "modules"):
        raise ReviewError("candidate manifest 的 module 必须是 docs/modules/<模块>")
    try:
        markdown_relative = markdown_path.relative_to(repo_root)
    except ValueError as exc:
        raise ReviewError("评审 markdown 不在旧批次仓根内") from exc
    target_scope = _review_target_scope(markdown_relative)
    if target_scope is None:
        raise ReviewError(
            "评审 markdown 必须是 docs/modules/<模块>/... "
            "或 docs/modules/<功能>.md"
        )
    if target_scope != module_path:
        work_meta_path = _canonical_regular_file(
            repo_root / module_path / ".work-meta.json",
            label="candidate manifest 对应 active work .work-meta.json",
        )
        work_meta = _load_json_object(
            work_meta_path,
            label="candidate manifest 对应 active work .work-meta.json",
        )
        build = work_meta.get("build")
        if (
            work_meta.get("id") != work_id
            or not isinstance(build, dict)
            or _build_anchor_relative(build, label="candidate active work")
            != markdown_relative
        ):
            raise ReviewError(
                "candidate manifest 的 module/build.anchor 与评审 markdown 不匹配"
            )

    worktree = _canonical_directory(
        Path(str(candidate.get("worktree") or "")),
        label="candidate manifest worktree",
    )
    if worktree != repo_root:
        raise ReviewError("candidate manifest 未绑定当前旧批次所在 worktree")
    if mode == "main":
        expected_main_root = repo_root
        if branch != main_branch:
            raise ReviewError("main candidate 的 branch 与 main_branch 不一致")
    else:
        expected_main_root = _linked_worktree_main_root(markdown_path, repo_root)
        if expected_main_root is None:
            raise ReviewError("无法确认 worktree candidate 所属 main 仓根")
    if main_root != expected_main_root:
        raise ReviewError("candidate manifest 不在当前 Git 仓的 main 受控目录")

    oid_pattern = r"[0-9a-f]{40,64}"
    candidate_head = str(candidate.get("candidate_head") or "")
    baseline = str(candidate.get("original_baseline_sha") or "")
    if not re.fullmatch(oid_pattern, candidate_head) or not re.fullmatch(
        oid_pattern, baseline
    ):
        raise ReviewError("candidate manifest 缺少合法 candidate/baseline commit")
    _verify_replan_candidate_git_provenance(
        main_root=main_root,
        worktree=worktree,
        branch=branch,
        candidate_head=candidate_head,
        baseline=baseline,
    )
    binding = {
        "path": candidate_path.relative_to(main_root).as_posix(),
        "sha256": _file_digest(candidate_path),
        "schema_version": REPLAN_CANDIDATE_SCHEMA_VERSION,
        "work_id": work_id,
        "mode": mode,
        "route": route,
        "candidate_head": candidate_head,
        "original_baseline_sha": baseline,
        "branch": branch,
        "worktree": str(worktree),
        "module": module,
        "main_branch": main_branch,
    }
    if target_scope != module_path:
        binding["markdown_relative"] = markdown_relative.as_posix()
    return binding


def _direct_product_handoff_binding(
    *,
    repo_root: Path,
    markdown_path: Path,
    route: str,
) -> dict[str, Any]:
    if route != "proposal":
        raise ReviewError("没有 replan candidate 时只允许产品级 proposal handoff")
    if _linked_worktree_main_root(markdown_path, repo_root) is not None:
        raise ReviewError("worktree 评审批次必须先 replan，并绑定 candidate manifest")

    branch_result = _git_provenance_result(repo_root, "branch", "--show-current")
    branch = os.fsdecode(branch_result.stdout).strip()
    if branch_result.returncode != 0 or branch not in {"main", "master"}:
        raise ReviewError("无 active build 的产品级 handoff 只能从 main/master 建立")

    try:
        active_result = list_active_work(repo_root, cwd=repo_root, strict=True)
    except StateReadError as exc:
        raise ReviewError(f"无法安全核验 active build：{exc}") from exc
    active_builds: list[str] = []
    for item in active_result["items"]:
        meta = item.get("meta") if isinstance(item, dict) else None
        if not isinstance(meta, dict):
            continue
        build = meta.get("build") if isinstance(meta.get("build"), dict) else {}
        lifecycle = str(
            build.get("lifecycle_state") or meta.get("lifecycle_state") or ""
        )
        if lifecycle in ACTIVE_BUILD_STATES:
            active_builds.append(str(meta.get("id") or item.get("work_dir") or ""))
    if active_builds:
        raise ReviewError(
            "检测到 active build，产品级 handoff 必须先 replan 并绑定 candidate manifest："
            + "、".join(active_builds)
        )

    head_result = _git_provenance_result(repo_root, "rev-parse", "HEAD^{commit}")
    head = os.fsdecode(head_result.stdout).strip().lower()
    if head_result.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", head):
        raise ReviewError("无法绑定产品级 handoff 建立时的 main HEAD")
    return {
        "route": "proposal",
        "branch": branch,
        "repo_head": head,
        "active_build_count": 0,
    }


def _verified_main_repository_root(raw_root: Path) -> Path:
    root = _canonical_directory(raw_root, label="handoff main 仓根")
    top_result = _git_provenance_result(root, "rev-parse", "--show-toplevel")
    top_raw = os.fsdecode(top_result.stdout).strip()
    if top_result.returncode != 0 or not top_raw:
        raise ReviewError("无法确认 handoff bundle 所属 main Git 仓根")
    top = _canonical_directory(Path(top_raw), label="Git 返回的 main 仓根")
    if top != root:
        raise ReviewError("handoff bundle 必须位于唯一 main Git 仓根")
    branch_result = _git_provenance_result(root, "branch", "--show-current")
    branch = os.fsdecode(branch_result.stdout).strip()
    if branch_result.returncode != 0 or branch not in {"main", "master"}:
        raise ReviewError("handoff bundle 只能从 main/master 枚举或更新")
    return root


def _handoff_bundle_root(main_root: Path, *, create: bool) -> Path | None:
    main_root = _verified_main_repository_root(main_root)
    root = main_root / ".runs" / "lark-review-handoffs"
    if create:
        try:
            ensure_directory_beneath(main_root, root)
        except AtomicFileError as exc:
            raise ReviewError(f"无法安全创建 handoff bundle 目录：{exc}") from exc
    else:
        try:
            info = root.lstat()
        except FileNotFoundError:
            return None
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise ReviewError("handoff bundle 根目录必须是 main 内的真实目录")
    root = _canonical_directory(root, label="handoff bundle 根目录")
    for entry in root.iterdir():
        info = entry.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise ReviewError(f"handoff bundle 根目录包含非法条目：{entry.name}")
    return root


def _handoff_bundle_dir(main_root: Path, batch_id: str, *, create: bool) -> Path:
    if not re.fullmatch(r"[0-9a-f]{24}", batch_id):
        raise ReviewError("handoff batch_id 不是安全的 24 位十六进制标识")
    root = _handoff_bundle_root(main_root, create=create)
    if root is None:
        raise ReviewError("handoff bundle 根目录不存在")
    bundle_dir = root / batch_id
    if create:
        try:
            ensure_directory_beneath(main_root, bundle_dir)
        except AtomicFileError as exc:
            raise ReviewError(f"无法安全创建 handoff bundle：{exc}") from exc
    bundle_dir = _canonical_directory(bundle_dir, label="handoff bundle 目录")
    allowed = {
        *HANDOFF_BUNDLE_REQUIRED_FILES,
        *HANDOFF_BUNDLE_OPTIONAL_FILES,
        "candidate-manifest.json",
        "bundle.json",
    }
    for entry in bundle_dir.iterdir():
        info = entry.lstat()
        if (
            entry.name not in allowed
            or stat.S_ISLNK(info.st_mode)
            or not stat.S_ISREG(info.st_mode)
        ):
            raise ReviewError(f"handoff bundle 包含非法条目：{entry.name}")
    return bundle_dir


def _validate_handoff_phase_history(
    *,
    route: str,
    phase: str,
    history: object,
    closure: object,
) -> None:
    sequence = HANDOFF_PHASE_SEQUENCES.get(route)
    if sequence is None or phase not in sequence or not isinstance(history, list):
        raise ReviewError("handoff bundle 的 phase 或 phase_history 不合法")
    expected_count = sequence.index(phase)
    if len(history) != expected_count:
        raise ReviewError("handoff bundle 的 phase_history 与当前 phase 不一致")
    for index, item in enumerate(history):
        if not isinstance(item, dict):
            raise ReviewError("handoff bundle 的阶段证据必须是对象")
        expected_from = sequence[index]
        expected_to = sequence[index + 1]
        evidence = item.get("evidence")
        if (
            item.get("from") != expected_from
            or item.get("to") != expected_to
            or not str(item.get("advanced_at") or "")
            or not isinstance(evidence, dict)
        ):
            raise ReviewError("handoff bundle 的阶段顺序或证据不完整")
        if expected_from == "proposal":
            if (
                evidence.get("kind") != "accepted_proposal"
                or not re.fullmatch(r"[0-9a-f]{40,64}", str(evidence.get("commit") or ""))
                or not str(evidence.get("proposal_id") or "")
                or not str(evidence.get("proposal_path") or "")
            ):
                raise ReviewError("handoff bundle 缺少有效的 Proposal 生效证据")
            _sha256_value(
                evidence.get("proposal_sha256"),
                label="handoff Proposal proposal_sha256",
            )
        elif expected_from == "design":
            if (
                evidence.get("kind") != "authority_commit"
                or not re.fullmatch(r"[0-9a-f]{40,64}", str(evidence.get("commit") or ""))
                or not str(evidence.get("markdown_relative") or "")
            ):
                raise ReviewError("handoff bundle 缺少有效的 design 权威提交证据")
            _sha256_value(
                evidence.get("blob_sha256"),
                label="handoff design blob_sha256",
            )
        elif expected_from == "lark_review":
            if (
                evidence.get("kind") != "fresh_checkpoint"
                or not isinstance(closure, dict)
                or evidence.get("batch_id") != closure.get("batch_id")
                or evidence.get("review_sha256") != closure.get("review_sha256")
                or evidence.get("plan_sha256") != closure.get("plan_sha256")
            ):
                raise ReviewError("handoff bundle 缺少与 closure 一致的 fresh checkpoint 证据")


def _load_handoff_bundle(bundle_path: Path) -> tuple[Path, dict[str, Any]]:
    bundle_path = _canonical_regular_file(bundle_path, label="handoff bundle.json")
    if (
        bundle_path.name != "bundle.json"
        or bundle_path.parent.parent.name != "lark-review-handoffs"
        or bundle_path.parent.parent.parent.name != ".runs"
    ):
        raise ReviewError("handoff bundle 必须位于 main 的 .runs/lark-review-handoffs/<batch>/")
    batch_id = bundle_path.parent.name
    if not re.fullmatch(r"[0-9a-f]{24}", batch_id):
        raise ReviewError("handoff bundle 目录名不是安全 batch_id")
    value = _load_json_object(bundle_path, label="handoff bundle.json")
    route = str(value.get("route") or "")
    state = str(value.get("state") or "")
    phase = str(value.get("phase") or "")
    phase_history = value.get("phase_history")
    handoff_mode = str(value.get("handoff_mode") or "")
    module = str(value.get("module") or "")
    module_path = Path(module)
    module_parts = module_path.parts
    markdown_relative = str(value.get("markdown_relative") or "")
    markdown_path = Path(markdown_relative)
    target_scope = _review_target_scope(markdown_path)
    document = value.get("document")
    artifacts = value.get("artifacts")
    source_handoff = value.get("source_handoff")
    candidate = value.get("candidate_manifest")
    product_baseline = value.get("product_baseline")
    if (
        value.get("kind") != HANDOFF_BUNDLE_KIND
        or _int(value.get("schema_version")) != HANDOFF_BUNDLE_SCHEMA_VERSION
        or value.get("batch_id") != batch_id
        or route not in HANDOFF_ROUTES
        or state not in HANDOFF_BUNDLE_STATES
        or phase not in HANDOFF_PHASES
        or not isinstance(phase_history, list)
        or (state == "pending" and phase == "closed")
        or (state == "closed" and phase != "closed")
        or not re.fullmatch(
            r"[0-9a-f]{40,64}", str(value.get("main_repo_head_at_handoff") or "")
        )
        or len(module_parts) != 3
        or module_parts[:2] != ("docs", "modules")
        or target_scope is None
        or markdown_path.as_posix() != markdown_relative
        or not isinstance(document, dict)
        or not str(document.get("doc_id") or "")
        or not isinstance(artifacts, dict)
        or not isinstance(source_handoff, dict)
        or source_handoff.get("name") != "handoff.json"
    ):
        raise ReviewError("handoff bundle.json 的身份、路由或文档绑定不完整")
    required = set(HANDOFF_BUNDLE_REQUIRED_FILES)
    if not required.issubset(artifacts):
        missing = sorted(required - set(artifacts))
        raise ReviewError(f"handoff bundle 缺少必要证据：{missing}")
    allowed = required | set(HANDOFF_BUNDLE_OPTIONAL_FILES) | {"candidate-manifest.json"}
    if not set(artifacts).issubset(allowed):
        raise ReviewError("handoff bundle 声明了未知证据文件")
    for name, binding in artifacts.items():
        if not isinstance(binding, dict) or binding.get("name") != name:
            raise ReviewError(f"handoff bundle 的 {name} 绑定不完整")
        expected = _sha256_value(
            binding.get("sha256"), label=f"handoff bundle {name}.sha256"
        )
        artifact_path = _canonical_regular_file(
            bundle_path.parent / name,
            label=f"handoff bundle {name}",
        )
        if _file_digest(artifact_path) != expected:
            raise ReviewError(f"handoff bundle 的 {name} 已变化")
    if _sha256_value(
        source_handoff.get("sha256"), label="handoff bundle source_handoff.sha256"
    ) != str(artifacts["handoff.json"].get("sha256") or ""):
        raise ReviewError("handoff bundle 的 marker 摘要绑定不一致")
    if handoff_mode == "active_replan":
        if (
            not isinstance(candidate, dict)
            or product_baseline is not None
            or candidate.get("route") != route
            or candidate.get("module") != module
            or (
                target_scope != module_path
                and candidate.get("markdown_relative") != markdown_relative
            )
        ):
            raise ReviewError("active handoff bundle 缺少唯一 candidate 绑定")
        if "candidate-manifest.json" not in artifacts:
            raise ReviewError("active handoff bundle 缺少 candidate manifest 快照")
        if candidate.get("sha256") != artifacts["candidate-manifest.json"].get("sha256"):
            raise ReviewError("active handoff bundle 的 candidate 摘要不一致")
    elif handoff_mode == "direct_product_change":
        if (
            route != "proposal"
            or candidate is not None
            or not isinstance(product_baseline, dict)
            or product_baseline.get("route") != "proposal"
            or product_baseline.get("active_build_count") != 0
            or target_scope != module_path
        ):
            raise ReviewError("直接产品 handoff bundle 的基线绑定不完整")
        if "candidate-manifest.json" in artifacts:
            raise ReviewError("直接产品 handoff bundle 不应包含 candidate manifest")
    else:
        raise ReviewError("handoff bundle 缺少可识别的交接模式")
    closure = value.get("closure")
    if state == "closed":
        if (
            not isinstance(closure, dict)
            or not re.fullmatch(r"[0-9a-f]{24}", str(closure.get("batch_id") or ""))
            or closure.get("batch_id") == batch_id
        ):
            raise ReviewError("已关闭 handoff bundle 缺少 fresh batch 绑定")
        _sha256_value(closure.get("review_sha256"), label="handoff closure review_sha256")
        _sha256_value(closure.get("plan_sha256"), label="handoff closure plan_sha256")
    elif closure is not None:
        raise ReviewError("pending handoff bundle 不得提前写 closure")
    _validate_handoff_phase_history(
        route=route,
        phase=phase,
        history=phase_history,
        closure=closure,
    )
    return bundle_path, value


def _handoff_bundle_summary(bundle_path: Path, value: dict[str, Any]) -> dict[str, Any]:
    evidence_files = {
        name: str(bundle_path.parent / name)
        for name in sorted(value["artifacts"])
    }
    return {
        "state": value["state"],
        "batch_id": value["batch_id"],
        "route": value["route"],
        "phase": value["phase"],
        "handoff_mode": value["handoff_mode"],
        "module": value["module"],
        "markdown_relative": value["markdown_relative"],
        "document": value["document"],
        "candidate_manifest": value.get("candidate_manifest"),
        "product_baseline": value.get("product_baseline"),
        "handoff_bundle": str(bundle_path),
        "evidence_dir": str(bundle_path.parent),
        "evidence_files": evidence_files,
        "created_at": value.get("created_at"),
        "main_repo_head_at_handoff": value.get("main_repo_head_at_handoff"),
        "closure": value.get("closure"),
        "phase_history": value.get("phase_history"),
    }


def _create_or_load_handoff_bundle(
    *,
    main_root: Path,
    repo_root: Path,
    manifest_path: Path,
    manifest: dict[str, Any],
    marker_path: Path,
    marker: dict[str, Any],
    candidate_source: Path | None,
) -> tuple[Path, dict[str, Any], bool]:
    main_root = _verified_main_repository_root(main_root)
    batch_id = str(manifest.get("batch_id") or "")
    bundle_dir = _handoff_bundle_dir(main_root, batch_id, create=True)
    bundle_path = bundle_dir / "bundle.json"
    if _entry_exists(bundle_path, label="handoff bundle.json"):
        loaded_path, loaded = _load_handoff_bundle(bundle_path)
        if (
            loaded.get("route") != marker.get("route")
            or loaded.get("handoff_mode") != marker.get("handoff_mode")
            or loaded.get("candidate_manifest") != marker.get("candidate_manifest")
            or loaded.get("product_baseline") != marker.get("product_baseline")
            or str((loaded.get("source_handoff") or {}).get("sha256") or "")
            != _file_digest(marker_path)
        ):
            raise ReviewError("已有 main handoff bundle 与当前只读批次不一致")
        return loaded_path, loaded, True

    source_dir = manifest_path.parent
    artifacts: dict[str, dict[str, str]] = {}
    for name in HANDOFF_BUNDLE_REQUIRED_FILES:
        source = _canonical_regular_file(source_dir / name, label=f"handoff 源证据 {name}")
        destination = bundle_dir / name
        _write_text(destination, _read_regular_text(source, label=f"handoff 源证据 {name}"))
        artifacts[name] = {"name": name, "sha256": _file_digest(destination)}
    for name in HANDOFF_BUNDLE_OPTIONAL_FILES:
        source = source_dir / name
        if not _entry_exists(source, label=f"可选 handoff 源证据 {name}"):
            continue
        source = _canonical_regular_file(source, label=f"可选 handoff 源证据 {name}")
        destination = bundle_dir / name
        _write_text(destination, _read_regular_text(source, label=f"可选 handoff 源证据 {name}"))
        artifacts[name] = {"name": name, "sha256": _file_digest(destination)}

    candidate_binding = marker.get("candidate_manifest")
    if isinstance(candidate_binding, dict):
        if candidate_source is None:
            raise ReviewError("active handoff 缺少 candidate manifest 源文件")
        candidate_source = _canonical_regular_file(
            candidate_source, label="handoff candidate manifest"
        )
        if _file_digest(candidate_source) != candidate_binding.get("sha256"):
            raise ReviewError("candidate manifest 在 handoff bundle 固化前已变化")
        destination = bundle_dir / "candidate-manifest.json"
        _write_text(
            destination,
            _read_regular_text(candidate_source, label="handoff candidate manifest"),
        )
        artifacts["candidate-manifest.json"] = {
            "name": "candidate-manifest.json",
            "sha256": _file_digest(destination),
        }

    markdown_path = _manifest_markdown_path(manifest)
    try:
        markdown_relative = markdown_path.relative_to(repo_root).as_posix()
    except ValueError as exc:
        raise ReviewError("handoff markdown 不在旧批次仓根内") from exc
    target_scope = _review_target_scope(Path(markdown_relative))
    if target_scope is None:
        raise ReviewError(
            "handoff markdown 必须是 docs/modules/<模块>/... "
            "或 docs/modules/<功能>.md"
        )
    candidate_binding = marker.get("candidate_manifest")
    module = (
        str(candidate_binding.get("module") or "")
        if isinstance(candidate_binding, dict)
        else target_scope.as_posix()
    )
    head_result = _git_provenance_result(main_root, "rev-parse", "HEAD^{commit}")
    main_head = os.fsdecode(head_result.stdout).strip().lower()
    if head_result.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", main_head):
        raise ReviewError("无法绑定 handoff bundle 建立时的 main HEAD")
    value: dict[str, Any] = {
        "kind": HANDOFF_BUNDLE_KIND,
        "schema_version": HANDOFF_BUNDLE_SCHEMA_VERSION,
        "state": "pending",
        "batch_id": batch_id,
        "route": marker["route"],
        "phase": marker["route"],
        "phase_history": [],
        "handoff_mode": marker["handoff_mode"],
        "created_at": marker.get("created_at"),
        "main_repo_head_at_handoff": main_head,
        "module": module,
        "markdown_relative": markdown_relative,
        "document": manifest.get("document"),
        "source_repo_root": str(repo_root),
        "source_markdown_path": str(markdown_path),
        "source_handoff": {
            "name": "handoff.json",
            "sha256": _file_digest(marker_path),
        },
        "candidate_manifest": candidate_binding,
        "product_baseline": marker.get("product_baseline"),
        "artifacts": artifacts,
        "closure": None,
    }
    _write_json(bundle_path, value)
    loaded_path, loaded = _load_handoff_bundle(bundle_path)
    return loaded_path, loaded, False


def list_handoffs(args: argparse.Namespace) -> int:
    main_root = _verified_main_repository_root(Path(args.main_root))
    root = _handoff_bundle_root(main_root, create=False)
    handoffs: list[dict[str, Any]] = []
    if root is not None:
        for bundle_dir in sorted(root.iterdir(), key=lambda value: os.fsencode(value.name)):
            bundle_path, value = _load_handoff_bundle(bundle_dir / "bundle.json")
            if not args.include_closed and value.get("state") != "pending":
                continue
            if args.route and value.get("route") != args.route:
                continue
            if args.phase and value.get("phase") != args.phase:
                continue
            if args.module and value.get("module") != args.module:
                continue
            document = value.get("document")
            if args.doc_id and (
                not isinstance(document, dict) or document.get("doc_id") != args.doc_id
            ):
                continue
            handoffs.append(_handoff_bundle_summary(bundle_path, value))
    print(
        json.dumps(
            {
                "status": "handoff_list",
                "main_repo_root": str(main_root),
                "count": len(handoffs),
                "handoffs": handoffs,
                "read_only": True,
            },
            ensure_ascii=False,
        )
    )
    return 0


def _require_commit_ancestry(
    main_root: Path,
    *,
    ancestor: str,
    descendant: str,
    label: str,
) -> None:
    result = _git_provenance_result(
        main_root,
        "merge-base",
        "--is-ancestor",
        ancestor,
        descendant,
    )
    if result.returncode != 0:
        raise ReviewError(f"{label}未承接 handoff 的已记录基线")


def _proposal_phase_evidence(
    main_root: Path,
    bundle: dict[str, Any],
) -> dict[str, Any]:
    try:
        proposal = validate_current_proposal(main_root)
    except ProposalContractError as exc:
        raise ReviewError(f"当前 Product Proposal 尚未形成有效生效版本：{exc}") from exc
    commit_result = _git_provenance_result(
        main_root,
        "log",
        "-1",
        "--format=%H",
        "--",
        ":(literal).pm-workflow/proposal.json",
    )
    commit = os.fsdecode(commit_result.stdout).strip().lower()
    baseline = str(bundle.get("main_repo_head_at_handoff") or "")
    if commit_result.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        raise ReviewError("无法读取当前 Proposal 的生效提交")
    if commit == baseline:
        raise ReviewError("当前 Proposal 仍是 handoff 建立时的旧产品基线")
    _require_commit_ancestry(
        main_root,
        ancestor=baseline,
        descendant=commit,
        label="Proposal 生效提交",
    )
    head_result = _git_provenance_result(main_root, "rev-parse", "HEAD^{commit}")
    head = os.fsdecode(head_result.stdout).strip().lower()
    if head_result.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", head):
        raise ReviewError("无法读取 main 当前提交")
    _require_commit_ancestry(
        main_root,
        ancestor=commit,
        descendant=head,
        label="Proposal 生效提交",
    )
    return {
        "kind": "accepted_proposal",
        "commit": commit,
        "proposal_id": proposal["id"],
        "proposal_path": proposal["path"],
        "proposal_sha256": proposal["hash"],
    }


def _authority_commit_evidence(
    main_root: Path,
    bundle: dict[str, Any],
    raw_commit: str | None,
) -> dict[str, Any]:
    commit = str(raw_commit or "").lower()
    if not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        raise ReviewError("design → lark_review 必须提供完整的权威规格提交 SHA")
    commit_result = _git_provenance_result(
        main_root,
        "rev-parse",
        "--verify",
        f"{commit}^{{commit}}",
    )
    resolved = os.fsdecode(commit_result.stdout).strip().lower()
    if commit_result.returncode != 0 or resolved != commit:
        raise ReviewError("权威规格提交不是当前仓可读取的 commit")
    history = bundle.get("phase_history") or []
    baseline = str(bundle.get("main_repo_head_at_handoff") or "")
    if history and isinstance(history[-1], dict):
        prior_evidence = history[-1].get("evidence")
        if isinstance(prior_evidence, dict) and prior_evidence.get("kind") == "accepted_proposal":
            baseline = str(prior_evidence.get("commit") or baseline)
    if commit == baseline:
        raise ReviewError("权威规格提交必须晚于 handoff 当前阶段的基线")
    _require_commit_ancestry(
        main_root,
        ancestor=baseline,
        descendant=commit,
        label="权威规格提交",
    )
    head_result = _git_provenance_result(main_root, "rev-parse", "HEAD^{commit}")
    head = os.fsdecode(head_result.stdout).strip().lower()
    if head_result.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", head):
        raise ReviewError("无法读取 main 当前提交")
    _require_commit_ancestry(
        main_root,
        ancestor=commit,
        descendant=head,
        label="权威规格提交",
    )

    relative = str(bundle.get("markdown_relative") or "")
    changed_result = _git_provenance_result(
        main_root,
        "diff-tree",
        "--root",
        "--no-commit-id",
        "--name-only",
        "-r",
        "-z",
        commit,
        "--",
        f":(literal){relative}",
    )
    changed = [os.fsdecode(item) for item in changed_result.stdout.split(b"\0") if item]
    if changed_result.returncode != 0 or changed != [relative]:
        raise ReviewError("权威规格提交没有修改当前 handoff 绑定的规格")
    tree_result = _git_provenance_result(
        main_root,
        "ls-tree",
        "-z",
        commit,
        "--",
        f":(literal){relative}",
    )
    entries = [item for item in tree_result.stdout.split(b"\0") if item]
    if tree_result.returncode != 0 or len(entries) != 1 or b"\t" not in entries[0]:
        raise ReviewError("权威规格提交中缺少 handoff 绑定的规格")
    metadata, encoded_path = entries[0].split(b"\t", 1)
    fields = metadata.split()
    if (
        len(fields) != 3
        or fields[0] not in {b"100644", b"100755"}
        or fields[1] != b"blob"
        or os.fsdecode(encoded_path) != relative
    ):
        raise ReviewError("权威规格提交中的目标不是普通规格文件")
    blob_result = _git_provenance_result(main_root, "cat-file", "blob", os.fsdecode(fields[2]))
    if blob_result.returncode != 0:
        raise ReviewError("无法读取权威规格提交中的规格正文")
    current_path = _canonical_regular_file(
        main_root / relative,
        label="handoff 当前权威规格",
    )
    if current_path.read_bytes() != blob_result.stdout:
        raise ReviewError("当前权威规格与提供的 design 提交不一致")
    return {
        "kind": "authority_commit",
        "commit": commit,
        "markdown_relative": relative,
        "blob_sha256": hashlib.sha256(blob_result.stdout).hexdigest(),
    }


def advance_handoff(args: argparse.Namespace) -> int:
    bundle_path, bundle = _load_handoff_bundle(Path(args.bundle))
    if bundle.get("state") != "pending":
        raise ReviewError("已关闭的 handoff bundle 不能继续推进阶段")
    target = "lark_review" if args.to == "lark-review" else args.to
    current = str(bundle.get("phase") or "")
    if current == target:
        print(json.dumps({
            "status": "handoff_phase",
            "handoff_bundle": str(bundle_path),
            "route": bundle["route"],
            "phase": current,
            "recovered": True,
        }, ensure_ascii=False))
        return 0
    sequence = HANDOFF_PHASE_SEQUENCES[str(bundle.get("route") or "")]
    if current not in sequence or sequence.index(current) + 1 >= len(sequence):
        raise ReviewError("handoff bundle 当前 phase 不能继续推进")
    if sequence[sequence.index(current) + 1] != target or target == "closed":
        raise ReviewError(f"handoff phase 只能按顺序推进，当前是 {current}")
    main_root = _verified_main_repository_root(bundle_path.parents[3])
    if current == "proposal":
        evidence = _proposal_phase_evidence(main_root, bundle)
    elif current == "design":
        evidence = _authority_commit_evidence(main_root, bundle, args.evidence_commit)
    else:
        raise ReviewError("lark_review → closed 只能由 fresh checkpoint 完成")
    updated = dict(bundle)
    updated["phase"] = target
    updated["phase_history"] = [
        *bundle["phase_history"],
        {
            "from": current,
            "to": target,
            "advanced_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "evidence": evidence,
        },
    ]
    _write_json(bundle_path, updated)
    _, verified = _load_handoff_bundle(bundle_path)
    print(json.dumps({
        "status": "handoff_phase",
        "handoff_bundle": str(bundle_path),
        "route": verified["route"],
        "phase": verified["phase"],
        "evidence": evidence,
        "recovered": False,
    }, ensure_ascii=False))
    return 0


def _validate_resumable_plan(
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
) -> None:
    schema_pair = (
        _int(manifest.get("schema_version")),
        _int(plan.get("schema_version")),
    )
    if (
        plan.get("kind") != "pmai_lark_review_apply_plan"
        or schema_pair
        not in {
            (SCHEMA_VERSION, PLAN_SCHEMA_VERSION),
            (SCHEMA_VERSION, PREVIOUS_PLAN_SCHEMA_VERSION),
            (LEGACY_REVIEW_SCHEMA_VERSION, LEGACY_PLAN_SCHEMA_VERSION),
        }
        or plan.get("state") not in {"draft", "ready"}
        or plan.get("batch_id") != manifest.get("batch_id")
    ):
        raise ReviewError("未完成批次的 apply-plan.json 结构或状态不合法")
    if _file_digest(manifest_path) != str(
        (plan.get("manifest") or {}).get("sha256") or ""
    ):
        raise ReviewError("未完成批次的 review.json 已变化")
    resolutions_path = manifest_path.parent / "resolutions.json"
    target_path = manifest_path.parent / "target.md"
    if (
        _file_digest(resolutions_path)
        != str((plan.get("resolutions") or {}).get("sha256") or "")
        or _file_digest(target_path)
        != str((plan.get("target") or {}).get("sha256") or "")
    ):
        raise ReviewError("未完成批次的 target/resolutions 已变化")
    if plan.get("state") == "ready" and plan.get("ready_token") != _ready_token(plan):
        raise ReviewError("未完成批次的 ready plan 绑定不完整")


def handoff(args: argparse.Namespace) -> int:
    manifest_path = _manifest_path(args.manifest)
    manifest = _load_manifest(manifest_path)
    if _int(manifest.get("schema_version")) != SCHEMA_VERSION:
        raise ReviewError("只读 handoff 只接受当前 schema 的新评审批次")
    markdown_path = _manifest_markdown_path(manifest)
    repo_root = _manifest_repository_root(manifest, markdown_path)
    plan_path = _canonical_regular_file(
        manifest_path.parent / "apply-plan.json",
        label="apply-plan.json",
    )
    plan = _load_json_object(plan_path, label="apply-plan.json")
    candidate_source: Path | None = None
    if args.candidate_manifest:
        handoff_mode = "active_replan"
        candidate_source = _canonical_regular_file(
            Path(args.candidate_manifest), label="replan candidate manifest"
        )
        candidate_binding = _replan_candidate_binding(
            str(candidate_source),
            repo_root=repo_root,
            markdown_path=markdown_path,
            route=str(args.route),
        )
        main_root = candidate_source.parent.parent.parent
        product_baseline_binding = None
    else:
        handoff_mode = "direct_product_change"
        candidate_binding = None
        main_root = repo_root
        product_baseline_binding = _direct_product_handoff_binding(
            repo_root=repo_root,
            markdown_path=markdown_path,
            route=str(args.route),
        )

    marker_path = _handoff_path(manifest_path)
    if _entry_exists(marker_path, label="handoff.json"):
        marker = _load_handoff_marker(
            manifest_path,
            manifest,
            plan_path=plan_path,
            plan=plan,
        )
        if (
            marker is None
            or marker.get("route") != args.route
            or marker.get("candidate_manifest") != candidate_binding
            or marker.get("product_baseline") != product_baseline_binding
            or marker.get("handoff_mode") != handoff_mode
        ):
            raise ReviewError("已有 handoff 与本次 route 或上游交接基线不一致")
        recovered = True
    else:
        if (
            plan.get("kind") != "pmai_lark_review_apply_plan"
            or _int(plan.get("schema_version")) != PLAN_SCHEMA_VERSION
            or plan.get("batch_id") != manifest.get("batch_id")
            or plan.get("state") != "draft"
            or plan.get("ready_token")
        ):
            raise ReviewError("只有尚未 seal/apply 的当前 draft 批次可以转为只读 handoff")
        _validate_resumable_plan(manifest_path, manifest, plan_path, plan)
        sources = _source_artifacts(manifest_path, manifest)
        current_raw = _read_regular_text(markdown_path, label="handoff 目标 markdown")
        _, current_body = parse_frontmatter(current_raw)
        if hashlib.sha256(current_body.encode("utf-8")).hexdigest() != sources[
            "local.md"
        ]["exact_body_sha256"]:
            raise ReviewError("正式规格已在 collect 后变化，不能把旧批次标成 unapplied handoff")
        draft_plan_sha = _file_digest(plan_path)
        resolutions_path = manifest_path.parent / "resolutions.json"
        target_path = manifest_path.parent / "target.md"
        marker = {
            "kind": HANDOFF_KIND,
            "schema_version": HANDOFF_SCHEMA_VERSION,
            "state": "read_only",
            "batch_id": manifest.get("batch_id"),
            "route": args.route,
            "handoff_mode": handoff_mode,
            "created_at": datetime.now().astimezone().isoformat(timespec="seconds"),
            "review": {"name": "review.json", "sha256": _file_digest(manifest_path)},
            "draft_plan": {"name": "apply-plan.json", "sha256": draft_plan_sha},
            "resolutions": {
                "name": "resolutions.json",
                "sha256": _file_digest(resolutions_path),
            },
            "target": {"name": "target.md", "sha256": _file_digest(target_path)},
            "candidate_manifest": candidate_binding,
            "product_baseline": product_baseline_binding,
        }
        _write_json(marker_path, marker)
        recovered = False

    if plan.get("state") == "draft":
        transitioned = dict(plan)
        transitioned["state"] = "handed_off"
        transitioned.pop("ready_token", None)
        transitioned["handoff"] = {
            "name": "handoff.json",
            "sha256": _file_digest(marker_path),
            "draft_plan_sha256": marker["draft_plan"]["sha256"],
            "route": args.route,
        }
        _write_json(plan_path, transitioned)
        plan = transitioned
    _load_handoff_marker(
        manifest_path,
        manifest,
        plan_path=plan_path,
        plan=plan,
    )
    bundle_path, bundle, bundle_recovered = _create_or_load_handoff_bundle(
        main_root=main_root,
        repo_root=repo_root,
        manifest_path=manifest_path,
        manifest=manifest,
        marker_path=marker_path,
        marker=marker,
        candidate_source=candidate_source,
    )
    output = {
        "status": "handed_off",
        "state": "read_only",
        "batch_id": manifest.get("batch_id"),
        "route": args.route,
        "handoff_mode": handoff_mode,
        "candidate_manifest": (
            candidate_binding["path"] if candidate_binding is not None else None
        ),
        "candidate_manifest_sha256": (
            candidate_binding["sha256"] if candidate_binding is not None else None
        ),
        "product_baseline": product_baseline_binding,
        "handoff": str(marker_path),
        "handoff_bundle": str(bundle_path),
        "handoff_bundle_state": bundle.get("state"),
        "bundle_recovered": bundle_recovered,
        "recovered": recovered,
    }
    print(json.dumps(output, ensure_ascii=False))
    return 0


def _checkpoint_receipt_path(manifest_path: Path) -> Path:
    return manifest_path.parent / "checkpoint.json"


def _load_checkpoint_receipt(
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path | None,
    plan: dict[str, Any] | None,
) -> dict[str, Any] | None:
    receipt_path = _checkpoint_receipt_path(manifest_path)
    if not _entry_exists(receipt_path, label="checkpoint.json"):
        return None
    if plan_path is None or plan is None:
        raise ReviewError("checkpoint.json 存在但缺少对应 apply-plan.json")
    receipt_path = _canonical_regular_file(receipt_path, label="checkpoint.json")
    receipt = _load_json_object(receipt_path, label="checkpoint.json")
    document = receipt.get("document")
    if (
        receipt.get("kind") != CHECKPOINT_KIND
        or _int(receipt.get("schema_version")) != CHECKPOINT_SCHEMA_VERSION
        or receipt.get("batch_id") != manifest.get("batch_id")
        or receipt.get("review_sha256") != _file_digest(manifest_path)
        or receipt.get("plan_sha256") != _file_digest(plan_path)
        or receipt.get("markdown_path") != str(_manifest_markdown_path(manifest))
        or not str(receipt.get("reviewed_at") or "")
        or not isinstance(document, dict)
        or document.get("doc_id") != (manifest.get("document") or {}).get("doc_id")
        or _int(document.get("published_revision_id")) is None
        or plan.get("state") != "ready"
    ):
        raise ReviewError("checkpoint.json 与评审批次绑定不完整或已漂移")
    return receipt


def _scan_resumable_review_root(
    review_root: Path,
    *,
    markdown_filter: Path | None = None,
    expected_repo_root: Path | None = None,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    resumable: list[dict[str, Any]] = []
    skipped_handoffs: list[dict[str, Any]] = []
    skipped_checkpoints: list[dict[str, Any]] = []
    for entry in sorted(review_root.iterdir(), key=lambda value: os.fsencode(value.name)):
        if not entry.name.startswith("batch."):
            continue
        batch_dir = _canonical_directory(entry, label="lark-review 批次目录")
        manifest_path = batch_dir / "review.json"
        if not _entry_exists(manifest_path, label="review.json"):
            continue
        manifest_path = _canonical_regular_file(manifest_path, label="review.json")
        manifest = _load_manifest(manifest_path)
        markdown_path = _manifest_markdown_path(manifest)
        if markdown_filter is not None and markdown_path != markdown_filter:
            continue
        repo_root = _manifest_repository_root(manifest, markdown_path)
        if expected_repo_root is not None and repo_root != expected_repo_root:
            raise ReviewError("评审批次声明的仓根与所在 worktree 不一致")
        plan_path = batch_dir / "apply-plan.json"
        plan: dict[str, Any] | None = None
        if _entry_exists(plan_path, label="apply-plan.json"):
            plan_path = _canonical_regular_file(plan_path, label="apply-plan.json")
            plan = _load_json_object(plan_path, label="apply-plan.json")
        marker = _load_handoff_marker(
            manifest_path,
            manifest,
            plan_path=plan_path if plan is not None else None,
            plan=plan,
        )
        if marker is not None:
            skipped_handoffs.append(
                {
                    "batch_id": manifest.get("batch_id"),
                    "batch_dir": str(batch_dir),
                    "route": marker.get("route"),
                    "reason": "read_only_handoff",
                }
            )
            continue
        checkpoint = _load_checkpoint_receipt(
            manifest_path,
            manifest,
            plan_path if plan is not None else None,
            plan,
        )
        if checkpoint is not None:
            skipped_checkpoints.append(
                {
                    "batch_id": manifest.get("batch_id"),
                    "batch_dir": str(batch_dir),
                    "reason": "checkpointed",
                }
            )
            continue
        sources = _source_artifacts(manifest_path, manifest)
        _, current_body = parse_frontmatter(
            _read_regular_text(markdown_path, label="恢复扫描目标 markdown")
        )
        current_exact = hashlib.sha256(current_body.encode("utf-8")).hexdigest()
        valid_current_hashes = {sources["local.md"]["exact_body_sha256"]}
        state = "collected"
        if plan is not None:
            _validate_resumable_plan(manifest_path, manifest, plan_path, plan)
            state = str(plan.get("state") or "")
            if state == "ready":
                valid_current_hashes.add(
                    str((plan.get("target") or {}).get("exact_body_sha256") or "")
                )
        if current_exact not in valid_current_hashes:
            raise ReviewError("未完成批次绑定的本地正文已变化，请先归位现场")
        resumable.append(
            {
                "batch_id": manifest.get("batch_id"),
                "batch_dir": str(batch_dir),
                "manifest": str(manifest_path),
                "state": state,
                "repo_root": str(repo_root),
                "markdown_path": str(markdown_path),
                "markdown_relative": str(markdown_path.relative_to(repo_root)),
                "module": (
                    _review_target_scope(markdown_path.relative_to(repo_root)).as_posix()
                    if _review_target_scope(markdown_path.relative_to(repo_root)) is not None
                    else None
                ),
                "document": manifest.get("document"),
            }
        )
    return resumable, skipped_handoffs, skipped_checkpoints


def find_resumable(args: argparse.Namespace) -> int:
    markdown_path = _canonical_regular_file(
        Path(args.markdown), label="恢复扫描目标 markdown"
    )
    review_root = _canonical_directory(
        Path(args.review_root), label="lark-review 批次根目录"
    )
    resumable, skipped_handoffs, skipped_checkpoints = _scan_resumable_review_root(
        review_root,
        markdown_filter=markdown_path,
    )
    if len(resumable) > 1:
        raise ReviewError("同一目标存在多个可恢复批次，不能靠最新目录猜测")
    result: dict[str, Any] = {
        "status": "resumable" if resumable else "none",
        "markdown_path": str(markdown_path),
        "resumable_count": len(resumable),
        "skipped_handoff_count": len(skipped_handoffs),
        "skipped_handoffs": skipped_handoffs,
        "skipped_checkpoint_count": len(skipped_checkpoints),
        "skipped_checkpoints": skipped_checkpoints,
    }
    if resumable:
        result["batch"] = resumable[0]
    print(json.dumps(result, ensure_ascii=False))
    return 0


def list_resumables(args: argparse.Namespace) -> int:
    main_root = _verified_main_repository_root(Path(args.main_root))
    roots: list[Path] = []
    for binding in _git_worktree_bindings(main_root):
        raw = binding.get("worktree")
        if not raw:
            raise ReviewError("Git worktree 清单缺少 worktree 路径")
        root = _canonical_directory(Path(raw), label="评审恢复 worktree")
        if _git_toplevel(root, label="评审恢复 worktree") != root:
            raise ReviewError("评审恢复扫描只接受 Git worktree 根目录")
        if root not in roots:
            roots.append(root)

    resumable: list[dict[str, Any]] = []
    skipped_handoffs: list[dict[str, Any]] = []
    skipped_checkpoints: list[dict[str, Any]] = []
    for root in roots:
        review_root = root / ".pm-workflow" / "context" / "lark-review"
        try:
            info = review_root.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise ReviewError("lark-review 批次根目录必须是 worktree 内真实目录")
        canonical_review_root = _canonical_directory(
            review_root,
            label="lark-review 批次根目录",
        )
        found, handed_off, checkpointed = _scan_resumable_review_root(
            canonical_review_root,
            expected_repo_root=root,
        )
        resumable.extend(found)
        skipped_handoffs.extend(handed_off)
        skipped_checkpoints.extend(checkpointed)

    identities: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for item in resumable:
        document = item.get("document")
        doc_id = str(document.get("doc_id") or "") if isinstance(document, dict) else ""
        key = (doc_id, str(item.get("markdown_relative") or ""))
        identities.setdefault(key, []).append(item)
    duplicates = [items for items in identities.values() if len(items) > 1]
    if duplicates:
        raise ReviewError("同一飞书文档与规格存在多个可恢复批次，不能靠 worktree 或时间猜测")
    resumable.sort(
        key=lambda item: (
            str(item.get("markdown_relative") or ""),
            str(item.get("batch_id") or ""),
        )
    )
    print(json.dumps({
        "status": "resumable_list",
        "main_repo_root": str(main_root),
        "count": len(resumable),
        "batches": resumable,
        "skipped_handoff_count": len(skipped_handoffs),
        "skipped_checkpoint_count": len(skipped_checkpoints),
        "read_only": True,
    }, ensure_ascii=False))
    return 0


def _segment_hash(lines: list[str]) -> str:
    return hashlib.sha256("".join(lines).encode("utf-8")).hexdigest()


def _change_id(
    start: int,
    end: int,
    baseline: list[str],
    local: list[str],
    remote: list[str],
) -> str:
    seed = "\0".join(
        [str(start), str(end), _segment_hash(baseline), _segment_hash(local), _segment_hash(remote)]
    )
    return f"body-{hashlib.sha256(seed.encode('utf-8')).hexdigest()[:12]}"


def _resolution_value(
    resolution: dict[str, Any] | None,
    *,
    default_decision: str,
    default_authority: str,
    default_reason: str,
) -> dict[str, str]:
    if resolution is None:
        return {
            "decision": default_decision,
            "authority": default_authority,
            "reason": default_reason,
        }
    return {
        "decision": str(resolution.get("decision") or "pending"),
        "authority": str(resolution.get("authority") or "pending"),
        "reason": str(resolution.get("reason") or "").strip(),
    }


def _build_body_reconciliation(
    baseline_body: str | None,
    local_body: str,
    remote_body: str,
    *,
    body_status: str,
    common_ancestor_compatible: bool,
    resolutions: dict[str, dict[str, Any]],
    sealing: bool,
) -> tuple[str, list[dict[str, Any]], list[dict[str, str]], int]:
    records: list[dict[str, Any]] = []
    template: list[dict[str, str]] = []
    unresolved = 0

    if not common_ancestor_compatible or baseline_body is None:
        if _normalise(local_body) == _normalise(remote_body):
            if resolutions:
                raise ReviewError("resolutions.json 包含当前批次不存在的正文项")
            return remote_body, records, template, unresolved
        baseline_lines = _body_lines(baseline_body or "")
        local_lines = _body_lines(local_body)
        remote_lines = _body_lines(remote_body)
        change_id = _change_id(0, len(baseline_lines), baseline_lines, local_lines, remote_lines)
        default_decision = "needs_pm" if body_status == "remote_only" else "pending"
        resolution = _resolution_value(
            resolutions.get(change_id),
            default_decision=default_decision,
            default_authority="pending",
            default_reason="",
        )
        if resolution["decision"] not in {"remote", "merged", "pending", "needs_pm"}:
            raise ReviewError(f"{change_id} 使用了不支持的归位决定")
        if resolution["decision"] in {"pending", "needs_pm"}:
            unresolved += 1
        elif resolution["authority"] != "pm_confirmed" or not resolution["reason"]:
            raise ReviewError(
                f"{change_id} 缺少 PM 对 legacy / 不兼容祖先归位的明确确认"
            )
        records.append(
            {
                "change_id": change_id,
                "kind": "ancestor_incompatible" if baseline_body is not None else "legacy_baseline",
                "baseline_start_line": 0,
                "baseline_end_line_exclusive": len(baseline_lines),
                "baseline_segment_sha256": _segment_hash(baseline_lines),
                "local_segment_sha256": _segment_hash(local_lines),
                "remote_segment_sha256": _segment_hash(remote_lines),
                **resolution,
            }
        )
        template.append({"change_id": change_id, **resolution})
        unknown_ids = set(resolutions) - {change_id}
        if unknown_ids:
            raise ReviewError(f"resolutions.json 包含其它批次的正文项: {sorted(unknown_ids)}")
        return remote_body, records, template, unresolved

    baseline_lines = _body_lines(baseline_body)
    local_lines = _body_lines(local_body)
    remote_lines = _body_lines(remote_body)
    changes = [
        *_body_changes(baseline_lines, local_lines, "local"),
        *_body_changes(baseline_lines, remote_lines, "remote"),
    ]
    clusters = _change_clusters(changes)
    draft: list[str] = []
    cursor = 0
    expected_resolution_ids: set[str] = set()
    for cluster in clusters:
        start, end, local_segment = _cluster_segment(baseline_lines, cluster, "local")
        _, _, remote_segment = _cluster_segment(baseline_lines, cluster, "remote")
        baseline_segment = baseline_lines[start:end]
        change_id = _change_id(
            start, end, baseline_segment, local_segment, remote_segment
        )
        expected_resolution_ids.add(change_id)
        sources = {change.source for change in cluster}
        if sources == {"local"}:
            kind = "local_only"
            expected = _resolution_value(
                None,
                default_decision="local",
                default_authority="rule",
                default_reason="仅本地变化，保留采集时本地版本",
            )
            chosen = local_segment
        elif sources == {"remote"}:
            kind = "remote_only"
            expected = _resolution_value(
                resolutions.get(change_id),
                default_decision="needs_pm",
                default_authority="pending",
                default_reason="",
            )
            if expected["decision"] not in {"local", "remote", "pending", "needs_pm"}:
                raise ReviewError(f"{change_id} 使用了不支持的飞书正文归位决定")
            if expected["decision"] in {"pending", "needs_pm"}:
                unresolved += 1
                chosen = remote_segment
            else:
                if expected["authority"] != "pm_confirmed" or not expected["reason"]:
                    raise ReviewError(
                        f"{change_id} 缺少 PM 对飞书正文增量的本轮明确确认"
                    )
                chosen = (
                    remote_segment
                    if expected["decision"] == "remote"
                    else local_segment
                )
        elif local_segment == remote_segment:
            kind = "both_equivalent"
            expected = _resolution_value(
                None,
                default_decision="merged",
                default_authority="rule",
                default_reason="本地与飞书得到相同结果",
            )
            chosen = local_segment
        else:
            kind = "both_conflict"
            expected = _resolution_value(
                resolutions.get(change_id),
                default_decision="pending",
                default_authority="pending",
                default_reason="",
            )
            if expected["decision"] not in {"local", "remote", "merged", "pending", "needs_pm"}:
                raise ReviewError(f"{change_id} 使用了不支持的归位决定")
            if expected["decision"] in {"pending", "needs_pm"}:
                unresolved += 1
                chosen = _conflict_marker(
                    change_id, baseline_segment, local_segment, remote_segment
                )
            else:
                if expected["authority"] != "pm_confirmed" or not expected["reason"]:
                    raise ReviewError(f"{change_id} 的双边冲突必须记录 PM 确认依据和原因")
                if expected["decision"] == "local":
                    chosen = local_segment
                elif expected["decision"] == "remote":
                    chosen = remote_segment
                else:
                    chosen = _conflict_marker(
                        change_id,
                        baseline_segment,
                        local_segment,
                        remote_segment,
                    )
        supplied = resolutions.get(change_id)
        if sealing and kind != "both_conflict":
            if supplied is None or any(
                str(supplied.get(key) or "") != expected[key]
                for key in ("decision", "authority", "reason")
            ):
                raise ReviewError(f"{change_id} 的规则归位项被遗漏或改写")
        draft.extend(baseline_lines[cursor:start])
        draft.extend(chosen)
        cursor = end
        records.append(
            {
                "change_id": change_id,
                "kind": kind,
                "baseline_start_line": start,
                "baseline_end_line_exclusive": end,
                "baseline_segment_sha256": _segment_hash(baseline_segment),
                "local_segment_sha256": _segment_hash(local_segment),
                "remote_segment_sha256": _segment_hash(remote_segment),
                **expected,
            }
        )
        template.append({"change_id": change_id, **expected})
    draft.extend(baseline_lines[cursor:])
    unknown_ids = set(resolutions) - expected_resolution_ids
    if unknown_ids:
        raise ReviewError(f"resolutions.json 包含其它批次的正文项: {sorted(unknown_ids)}")
    return "".join(draft), records, template, unresolved


def _comment_reconciliation(
    manifest: dict[str, Any],
    resolutions: dict[str, dict[str, Any]],
    *,
    sealing: bool,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], int]:
    comments_meta = manifest.get("comments")
    items = comments_meta.get("items") if isinstance(comments_meta, dict) else None
    if not isinstance(items, list):
        raise ReviewError("review.json 缺少评论清单")
    batch_items = [
        item
        for item in items
        if isinstance(item, dict)
        and item.get("new_since_checkpoint")
        and (
            not item.get("is_solved")
            or bool(comments_meta.get("included_solved"))
        )
    ]
    expected_ids = {str(item.get("comment_id") or "") for item in batch_items}
    if "" in expected_ids:
        raise ReviewError("review.json 的批次评论缺少 comment_id")
    unknown_ids = set(resolutions) - expected_ids
    if unknown_ids:
        raise ReviewError(f"resolutions.json 包含其它批次的评论: {sorted(unknown_ids)}")
    records: list[dict[str, Any]] = []
    template: list[dict[str, Any]] = []
    unresolved = 0
    for item in batch_items:
        comment_id = str(item["comment_id"])
        resolution = _resolution_value(
            resolutions.get(comment_id),
            default_decision="pending",
            default_authority="pending",
            default_reason="",
        )
        if resolution["decision"] not in {
            "applied",
            "already_satisfied",
            "no_spec_change",
            "superseded",
            "deferred",
            "pending",
            "needs_pm",
        }:
            raise ReviewError(f"评论 {comment_id} 使用了不支持的处置决定")
        if resolution["decision"] in {"pending", "needs_pm"}:
            unresolved += 1
        elif not resolution["reason"] or resolution["authority"] in {"", "pending"}:
            raise ReviewError(f"评论 {comment_id} 缺少处置依据或原因")
        supplied = resolutions.get(comment_id)
        result_text = str(
            supplied.get("result_text") if isinstance(supplied, dict) else ""
            or ""
        ).strip()
        if resolution["decision"] in COMPLETED_COMMENT_DECISIONS:
            if not bool(item.get("is_whole")) and not result_text:
                if sealing:
                    raise ReviewError(
                        f"局部评论 {comment_id} 必须在 resolutions.json 固化 result_text"
                    )
            elif "\n" in result_text:
                raise ReviewError(f"评论 {comment_id} 的 result_text 只能是单段文本")
        elif result_text:
            raise ReviewError(
                f"评论 {comment_id} 尚不应完成，不能预填 result_text"
            )
        if sealing and resolutions.get(comment_id) is None:
            raise ReviewError(f"评论 {comment_id} 没有处置记录")
        records.append(
            {
                "comment_id": comment_id,
                "update_time": item.get("update_time"),
                "location_accuracy": (item.get("location") or {}).get("accuracy"),
                "result_text": result_text,
                **resolution,
            }
        )
        template.append(
            {"comment_id": comment_id, "result_text": result_text, **resolution}
        )
    return records, template, unresolved


def _ready_token(plan: dict[str, Any]) -> str:
    binding = {key: value for key, value in plan.items() if key != "ready_token"}
    encoded = json.dumps(binding, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _validate_target_derivation(
    value: dict[str, Any],
    *,
    target_body: str,
    reconciled_body: str,
) -> dict[str, str]:
    mode = str(value.get("mode") or "")
    authority = str(value.get("authority") or "")
    reason = str(value.get("reason") or "").strip()
    if mode == "reconciled":
        if authority != "rule" or not reason:
            raise ReviewError("target.mode=reconciled 必须保留规则派生依据")
        if target_body != reconciled_body:
            raise ReviewError(
                "target.md 与正文归位结果不一致；若经评论或生命周期重新编译，"
                "请显式记录 target.mode=lifecycle_compiled"
            )
    elif mode == "lifecycle_compiled":
        if authority in {"", "pending", "rule"} or not reason:
            raise ReviewError("生命周期编译后的 T 必须记录确认依据和原因")
    else:
        raise ReviewError("resolutions.json 的 target.mode 不受支持")
    return {"mode": mode, "authority": authority, "reason": reason}


def _validate_active_build_delta(
    value: dict[str, Any] | None,
    *,
    repo_root: Path,
    markdown_path: Path,
    body_records: list[dict[str, Any]],
    comment_records: list[dict[str, Any]],
    decision_routes: list[dict[str, Any]],
    target_body: str,
) -> dict[str, Any] | None:
    """Bind a scoped review route to the exact active build before seal."""

    if value is None:
        return None
    expected_keys = {
        "kind",
        "scope_attestation",
        "module",
        "work_id",
        "approved_source_hash_before",
        "design_revision_before",
        "summary",
        "affected_surfaces",
        "affects",
        "source_items",
        "authority",
        "reason",
    }
    if set(value) != expected_keys:
        raise ReviewError(
            "active_build_delta 字段不完整；必须在 seal 前固化当前 build、"
            "scoped-adjustment 口径、影响面和来源"
        )
    if (
        value.get("kind") != ACTIVE_BUILD_DELTA_KIND
        or value.get("scope_attestation") != ACTIVE_BUILD_SCOPE_ATTESTATION
        or value.get("authority") != "pm_confirmed"
    ):
        raise ReviewError(
            "active_build_delta 只接受 PM 已确认且不改变产品基线或模块模型的 "
            "scoped-adjustment"
        )

    try:
        module_relative = markdown_path.parent.relative_to(repo_root).as_posix()
    except ValueError as exc:
        raise ReviewError("active_build_delta 对应规格不在当前 PMAI 仓内") from exc
    module_parts = Path(module_relative).parts
    if (
        markdown_path.name != "spec.md"
        or len(module_parts) != 3
        or module_parts[:2] != ("docs", "modules")
        or not module_parts[2]
        or module_parts[2].startswith(".")
        or value.get("module") != module_relative
    ):
        raise ReviewError("active_build_delta 未绑定当前 docs/modules/<模块>/spec.md")

    work_meta_path = _canonical_regular_file(
        markdown_path.parent / ".work-meta.json",
        label="active build .work-meta.json",
    )
    work_meta = _load_json_object(work_meta_path, label="active build .work-meta.json")
    build = work_meta.get("build")
    lifecycle_state = str(
        (build.get("lifecycle_state") if isinstance(build, dict) else None)
        or work_meta.get("lifecycle_state")
        or ""
    )
    if (
        work_meta.get("status") != "active"
        or not isinstance(build, dict)
        or lifecycle_state not in ACTIVE_BUILD_STATES
        or value.get("work_id") != work_meta.get("id")
        or value.get("approved_source_hash_before")
        != build.get("approved_source_hash")
        or isinstance(value.get("design_revision_before"), bool)
        or not isinstance(value.get("design_revision_before"), int)
        or value.get("design_revision_before") != build.get("design_revision")
    ):
        raise ReviewError(
            "active_build_delta 未绑定当前 active build 的 work ID、设计版本和批准依据"
        )

    checkpoint_commit = str(
        build.get("authority_checkpoint_commit")
        or work_meta.get("design_checkpoint_commit")
        or ""
    )
    if not re.fullmatch(r"[0-9a-f]{40,64}", checkpoint_commit):
        raise ReviewError("active_build_delta 缺少上一份权威规格的 Git checkpoint")
    try:
        previous_spec = subprocess.run(
            [
                "git",
                "-C",
                str(repo_root),
                "show",
                f"{checkpoint_commit}:{module_relative}/spec.md",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise ReviewError(f"无法读取上一份权威规格：{exc}") from exc
    if previous_spec.returncode != 0:
        raise ReviewError("上一份 authority checkpoint 不包含当前模块 spec.md")
    _, previous_body = parse_frontmatter(previous_spec.stdout)
    previous_body_sha256 = hashlib.sha256(previous_body.encode("utf-8")).hexdigest()
    target_body_sha256 = hashlib.sha256(target_body.encode("utf-8")).hexdigest()
    if previous_body_sha256 == target_body_sha256:
        raise ReviewError(
            "active_build_delta 没有形成真实规格正文变化；仅发布 frontmatter 变化不能写 delta"
        )

    summary = str(value.get("summary") or "").strip()
    reason = str(value.get("reason") or "").strip()
    surfaces = value.get("affected_surfaces")
    affects = value.get("affects")
    if (
        not summary
        or not reason
        or not isinstance(surfaces, list)
        or not surfaces
        or any(not isinstance(item, str) or not item.strip() for item in surfaces)
        or len(set(surfaces)) != len(surfaces)
        or not isinstance(affects, list)
    ):
        raise ReviewError("active_build_delta 缺少明确的新口径、影响面或确认原因")
    normalised_affects: list[dict[str, str]] = []
    seen_affects: set[tuple[str, str]] = set()
    for item in affects:
        if not isinstance(item, dict) or set(item) != {"kind", "name"}:
            raise ReviewError("active_build_delta.affects 只能记录 term / role 的准确名称")
        key = (str(item.get("kind") or ""), str(item.get("name") or "").strip())
        if key[0] not in {"term", "role"} or not key[1] or key in seen_affects:
            raise ReviewError("active_build_delta.affects 包含非法或重复的 term / role")
        seen_affects.add(key)
        normalised_affects.append({"kind": key[0], "name": key[1]})

    if any(
        isinstance(item, dict) and item.get("outcome") in {"create", "supersede"}
        for item in decision_routes
    ):
        raise ReviewError(
            "active_build_delta 不能与 create / supersede 稳定模块决定同时 seal；"
            "模块模型变化必须回 design"
        )

    expected_sources = [
        f"body:{str(item.get('change_id') or '')}"
        for item in body_records
        if isinstance(item, dict) and str(item.get("change_id") or "")
    ]
    expected_sources.extend(
        f"comment:{str(item.get('comment_id') or '')}"
        for item in comment_records
        if isinstance(item, dict)
        and item.get("decision") == "applied"
        and str(item.get("comment_id") or "")
    )
    source_items = value.get("source_items")
    if not expected_sources or source_items != expected_sources:
        raise ReviewError(
            "active_build_delta.source_items 必须按批次顺序完整绑定全部正文归位项"
            "和 applied 评论"
        )
    return {
        "kind": ACTIVE_BUILD_DELTA_KIND,
        "scope_attestation": ACTIVE_BUILD_SCOPE_ATTESTATION,
        "module": module_relative,
        "work_id": str(value["work_id"]),
        "approved_source_hash_before": str(value["approved_source_hash_before"]),
        "design_revision_before": int(value["design_revision_before"]),
        "summary": summary,
        "affected_surfaces": [str(item) for item in surfaces],
        "affects": normalised_affects,
        "source_items": [str(item) for item in source_items],
        "authority": "pm_confirmed",
        "reason": reason,
        "authority_checkpoint_commit": checkpoint_commit,
        "previous_spec_body_sha256": previous_body_sha256,
        "target_body_sha256": target_body_sha256,
    }


def reconcile(args: argparse.Namespace) -> int:
    reconcile_started = time.monotonic()
    manifest_path = _manifest_path(args.manifest)
    manifest = _load_manifest(manifest_path)
    plan_path = manifest_path.parent / "apply-plan.json"
    existing_plan: dict[str, Any] | None = None
    if _entry_exists(plan_path, label="apply-plan.json"):
        plan_path = _canonical_regular_file(plan_path, label="apply-plan.json")
        existing_plan = _load_json_object(plan_path, label="apply-plan.json")
    _reject_read_only_handoff(
        manifest_path,
        manifest,
        plan_path=plan_path if existing_plan is not None else None,
        plan=existing_plan,
    )
    sources = _source_artifacts(manifest_path, manifest)
    native_snapshot = _native_snapshot_artifact(manifest_path, manifest)
    markdown_path = _manifest_markdown_path(manifest)
    repo_root = _manifest_repository_root(manifest, markdown_path)
    current_raw = _read_regular_text(markdown_path, label="本地 markdown")
    _, current_body = parse_frontmatter(current_raw)
    if hashlib.sha256(current_body.encode("utf-8")).hexdigest() != sources["local.md"]["exact_body_sha256"]:
        raise ReviewError("本地规格正文已在 collect 后变化，请重新 collect")

    resolutions_path = manifest_path.parent / "resolutions.json"
    target_path = manifest_path.parent / "target.md"
    coverage_path = manifest_path.parent / "remote-coverage.json"
    preview_path = manifest_path.parent / "remote-preview.md"
    if args.resolutions:
        provided = _absolute_lexical_path(Path(args.resolutions))
        if provided != resolutions_path:
            raise ReviewError("--resolutions 必须指向本批次目录中的 resolutions.json")
        _canonical_regular_file(provided, label="resolutions.json")
    if args.seal:
        try:
            _canonical_regular_file(resolutions_path, label="resolutions.json")
            _canonical_regular_file(target_path, label="target.md")
        except ReviewError as exc:
            raise ReviewError(
                "seal 前必须完成本批次 resolutions.json 与 target.md"
            ) from exc
        (
            body_resolutions,
            comment_resolutions,
            target_derivation,
            coverage_resolutions,
            preview_resolution,
            decision_routing_resolutions,
            consistency_receipt,
            active_build_delta,
        ) = _resolution_maps(
            resolutions_path,
            expected_batch_id=str(manifest.get("batch_id") or ""),
        )
    else:
        if args.resolutions:
            raise ReviewError("首次 reconcile 不接受 --resolutions；先生成批次模板")
        for path in (resolutions_path, target_path, plan_path, coverage_path, preview_path):
            if _entry_exists(path, label="评审产物"):
                raise ReviewError("本批次已开始归位；编辑现有产物后使用 reconcile --seal")
        body_resolutions, comment_resolutions = {}, {}
        target_derivation = _default_target_derivation()
        coverage_resolutions = []
        preview_resolution = _default_preview_resolution()
        decision_routing_resolutions = []
        consistency_receipt = _default_consistency_receipt()
        active_build_delta = None

    body_meta = manifest.get("body") or {}
    baseline_body = sources.get("baseline.md", {}).get("text")
    draft, body_records, body_template, body_unresolved = _build_body_reconciliation(
        baseline_body if isinstance(baseline_body, str) else None,
        str(sources["local.md"]["text"]),
        str(sources["remote.md"]["text"]),
        body_status=str(body_meta.get("status") or ""),
        common_ancestor_compatible=bool(body_meta.get("common_ancestor_compatible")),
        resolutions=body_resolutions,
        sealing=bool(args.seal),
    )
    comment_records, comment_template, comment_unresolved = _comment_reconciliation(
        manifest,
        comment_resolutions,
        sealing=bool(args.seal),
    )

    if not args.seal:
        decision_routing_resolutions = _decision_routing_template(
            body_records,
            comment_records,
        )
        _write_text(target_path, draft)
        _write_json(
            resolutions_path,
            {
                "schema_version": RESOLUTION_SCHEMA_VERSION,
                "batch_id": manifest.get("batch_id"),
                "target": target_derivation,
                "body": body_template,
                "comments": comment_template,
                "remote_coverage": coverage_resolutions,
                "preview": preview_resolution,
                "decision_routing": decision_routing_resolutions,
                "consistency": consistency_receipt,
                "active_build_delta": active_build_delta,
            },
        )
    target_body = _read_regular_text(target_path, label="target.md")
    target_frontmatter, _ = parse_frontmatter(target_body)
    if target_frontmatter:
        raise ReviewError("target.md 只能包含正文，不能带 frontmatter")
    document = manifest.get("document") or {}
    remote_revision = _int(document.get("current_revision_id"))
    if remote_revision is None:
        raise ReviewError("review.json 缺少远端 revision")
    try:
        coverage = build_remote_coverage(
            str(sources["remote.md"]["text"]),
            target_body,
            native_snapshot=native_snapshot["value"],
            resolutions=coverage_resolutions,
            batch_id=str(manifest.get("batch_id") or ""),
            remote_revision_id=remote_revision,
        )
    except ValueError as exc:
        raise ReviewError(f"远端语义覆盖账本不合法: {exc}") from exc
    _write_json(coverage_path, coverage)
    _write_text(preview_path, render_remote_preview(coverage))
    coverage_summary = coverage["summary"]
    has_markers = any(
        marker in target_body
        for marker in ("<<<<<<< LOCAL ", "||||||| BASELINE ", ">>>>>>> REMOTE ")
    )
    unresolved = body_unresolved + comment_unresolved
    if args.seal and (unresolved != 0 or has_markers):
        raise ReviewError(
            f"归位仍有 {unresolved} 个待决项或冲突标记，不能 seal"
        )
    if args.seal:
        target_derivation = _validate_target_derivation(
            target_derivation,
            target_body=target_body,
            reconciled_body=draft,
        )
        if any(
            item.get("decision") == "applied" for item in comment_records
        ) and (
            target_derivation["mode"] != "lifecycle_compiled"
            or _normalise(target_body) == _normalise(draft)
        ):
            raise ReviewError(
                "评论标记 applied 时，T 必须由生命周期重新编译且包含实际正文变化；"
                "已有口径请使用 already_satisfied，无规格变化请使用 no_spec_change"
            )
        manual_merged = any(
            item.get("decision") == "merged" and item.get("authority") != "rule"
            for item in body_records
        )
        if manual_merged and _normalise(target_body) in {
            _normalise(str(sources["local.md"]["text"])),
            _normalise(str(sources["remote.md"]["text"])),
        }:
            raise ReviewError(
                "手工 merged 的 T 不能退化为完整 L 或完整 R；"
                "若实际保留单边口径，请使用对应的单边决定，不要伪装成 merged"
            )
        if coverage.get("unknown_resolution_ids"):
            raise ReviewError(
                "远端语义覆盖账本包含不属于当前 R 的条目: "
                f"{coverage['unknown_resolution_ids']}"
            )
        if (
            int(coverage_summary.get("unassigned_count") or 0) != 0
            or int(coverage_summary.get("format_unassigned_count") or 0) != 0
            or float(coverage_summary.get("remote_accounted_ratio") or 0) != 1.0
            or float(coverage_summary.get("remote_format_accounted_ratio") or 0) != 1.0
        ):
            raise ReviewError(
                "远端语义或原生格式仍有未归位项，不能 seal；"
                "请查看 remote-coverage.json 和 remote-preview.md"
            )
        if bool(coverage_summary.get("preview_required")):
            preview_authority = str(preview_resolution.get("authority") or "")
            if (
                preview_resolution.get("approved") is not True
                or preview_authority not in {"agent_reviewed", "pm_confirmed", "rule"}
                or not str(preview_resolution.get("reason") or "").strip()
            ):
                raise ReviewError(
                    "R→T 差异达到强制预览阈值；完成 remote-preview.md 验收前不能 seal"
                )
        decision_routing_resolutions = _validate_decision_routing(
            decision_routing_resolutions,
            body_records=body_records,
            comment_records=comment_records,
            repo_root=repo_root,
        )
        consistency_receipt = _validate_consistency_receipt(
            consistency_receipt,
            routes=decision_routing_resolutions,
            repo_root=repo_root,
            target_body=target_body,
        )
        active_build_delta = _validate_active_build_delta(
            active_build_delta,
            repo_root=repo_root,
            markdown_path=markdown_path,
            body_records=body_records,
            comment_records=comment_records,
            decision_routes=decision_routing_resolutions,
            target_body=target_body,
        )
    state = "ready" if args.seal and unresolved == 0 and not has_markers else "draft"

    artifacts_for_plan = {
        name: {
            "sha256": value["sha256"],
            "exact_body_sha256": value["exact_body_sha256"],
            "body_sha256": value["body_sha256"],
        }
        for name, value in sources.items()
    }
    plan: dict[str, Any] = {
        "kind": "pmai_lark_review_apply_plan",
        "schema_version": PLAN_SCHEMA_VERSION,
        "batch_id": manifest.get("batch_id"),
        "state": state,
        "manifest": {"name": "review.json", "sha256": _file_digest(manifest_path)},
        "resolutions": {
            "name": "resolutions.json",
            "sha256": _file_digest(resolutions_path),
        },
        "markdown_path": str(markdown_path),
        "repo_root": str(repo_root),
        "document": {
            "doc_id": document.get("doc_id"),
            "published_revision_id": document.get("published_revision_id"),
            "remote_revision_id": document.get("current_revision_id"),
        },
        "published_fence": {
            "revision_id": document.get("published_revision_id"),
            "source_hash": body_meta.get("published_source_hash"),
        },
        "common_ancestor_compatible": bool(body_meta.get("common_ancestor_compatible")),
        "target_base": "remote_native_snapshot",
        "target_base_revision": remote_revision,
        "remote_native": {
            "name": "remote-native.json",
            "sha256": native_snapshot["sha256"],
        },
        "remote_coverage": {
            "name": "remote-coverage.json",
            "sha256": _file_digest(coverage_path),
            "remote_accounted_ratio": coverage_summary["remote_accounted_ratio"],
            "remote_format_accounted_ratio": coverage_summary[
                "remote_format_accounted_ratio"
            ],
            "unassigned_count": coverage_summary["unassigned_count"],
            "format_unassigned_count": coverage_summary["format_unassigned_count"],
        },
        "preview": {
            "name": "remote-preview.md",
            "sha256": _file_digest(preview_path),
            "required": bool(coverage_summary.get("preview_required")),
            "pm_confirmation_required": bool(
                coverage_summary.get("pm_confirmation_required")
            ),
            **preview_resolution,
        },
        "writeback_contract": {
            "mode": "native_block_patch",
            "preserve_unmodified_native_blocks": True,
            "forbid_markdown_overwrite": True,
        },
        "sources": artifacts_for_plan,
        "comments_canonical_sha256": (manifest.get("comments") or {}).get("canonical_sha256"),
        "required_items": {
            "body": body_records,
            "comments": comment_records,
        },
        "target_derivation": target_derivation,
        "decision_routing": decision_routing_resolutions,
        "consistency": consistency_receipt,
        "active_build_delta": active_build_delta,
        "decision_write_count": sum(
            1
            for item in decision_routing_resolutions
            if item.get("outcome") in {"create", "supersede"}
        ),
        "target": {
            "name": "target.md",
            "sha256": _file_digest(target_path),
            "exact_body_sha256": hashlib.sha256(target_body.encode("utf-8")).hexdigest(),
            "body_sha256": _body_hash(target_body),
        },
        "expected_local_exact_body_sha256": sources["local.md"]["exact_body_sha256"],
        "unresolved_count": unresolved,
        "performance": {
            "reconcile_seconds": round(time.monotonic() - reconcile_started, 6),
            "remote_semantic_units": coverage_summary["remote_unit_count"],
            "remote_native_blocks": coverage_summary["native_block_count"],
        },
    }
    if state == "ready":
        plan["ready_token"] = _ready_token(plan)
    _write_json(plan_path, plan)
    print(
        json.dumps(
            {
                "batch_id": manifest.get("batch_id"),
                "state": state,
                "target": str(target_path),
                "resolutions": str(resolutions_path),
                "plan": str(plan_path),
                "body_items": len(body_records),
                "comment_items": len(comment_records),
                "unresolved": unresolved,
                "target_base": "remote_native_snapshot",
                "target_base_revision": remote_revision,
                "content_coverage": coverage_summary["remote_accounted_ratio"],
                "format_coverage": coverage_summary["remote_format_accounted_ratio"],
                "unassigned": coverage_summary["unassigned_count"],
                "format_unassigned": coverage_summary["format_unassigned_count"],
                "preview_required": coverage_summary["preview_required"],
                "decision_writes": plan["decision_write_count"],
                "elapsed_seconds": round(time.monotonic() - reconcile_started, 6),
            },
            ensure_ascii=False,
        )
    )
    return 0


def _validate_local_document_identity(
    frontmatter: dict[str, str],
    *,
    expected_doc_id: str,
    label: str,
) -> None:
    frontmatter_doc_id = str(frontmatter.get("lark_doc_id") or "")
    frontmatter_url = frontmatter.get("lark_doc_url")
    frontmatter_url_id = _docx_token(frontmatter_url)
    if frontmatter_url and frontmatter_url_id is None:
        raise ReviewError(f"{label} 的 lark_doc_url 不是受支持的 Docx 链接")
    identities = {
        value for value in (frontmatter_doc_id, frontmatter_url_id) if value
    }
    if identities != {expected_doc_id}:
        raise ReviewError(f"{label} 与评审批次的飞书文档身份不匹配")


def _validate_sealed_batch_contract(
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
    *,
    require_current_schema: bool = False,
) -> dict[str, Any]:
    """Replay the complete read-only seal contract shared by apply and build."""

    _reject_read_only_handoff(
        manifest_path,
        manifest,
        plan_path=plan_path,
        plan=plan,
    )
    schema_pair = (
        _int(manifest.get("schema_version")),
        _int(plan.get("schema_version")),
    )
    allowed_pairs = {
        (SCHEMA_VERSION, PLAN_SCHEMA_VERSION),
        (SCHEMA_VERSION, PREVIOUS_PLAN_SCHEMA_VERSION),
        (LEGACY_REVIEW_SCHEMA_VERSION, LEGACY_PLAN_SCHEMA_VERSION),
    }
    if (
        plan.get("kind") != "pmai_lark_review_apply_plan"
        or schema_pair not in allowed_pairs
        or plan.get("state") != "ready"
        or (require_current_schema and schema_pair != (SCHEMA_VERSION, PLAN_SCHEMA_VERSION))
    ):
        raise ReviewError("只接受 schema 匹配且已 seal 的 ready plan")

    manifest_path = _canonical_regular_file(manifest_path, label="review.json")
    plan_path = _canonical_regular_file(plan_path, label="apply-plan.json")
    batch_dir = _canonical_directory(plan_path.parent, label="lark-review 批次目录")
    resolutions_path = _canonical_regular_file(
        batch_dir / "resolutions.json", label="resolutions.json"
    )
    target_path = _canonical_regular_file(batch_dir / "target.md", label="target.md")
    coverage_path = _canonical_regular_file(
        batch_dir / "remote-coverage.json", label="remote-coverage.json"
    )
    preview_path = _canonical_regular_file(
        batch_dir / "remote-preview.md", label="remote-preview.md"
    )
    if manifest.get("batch_id") != plan.get("batch_id"):
        raise ReviewError("apply-plan.json 与 review.json 批次不匹配")
    markdown_path = _manifest_markdown_path(manifest)
    repo_root = _manifest_repository_root(manifest, markdown_path)
    if (
        str(plan.get("repo_root") or "") != str(repo_root)
        or str(plan.get("markdown_path") or "") != str(markdown_path)
    ):
        raise ReviewError("apply-plan.json 未绑定 review.json 的仓根与本地规格")
    if (
        _file_digest(manifest_path)
        != str((plan.get("manifest") or {}).get("sha256") or "")
        or _file_digest(resolutions_path)
        != str((plan.get("resolutions") or {}).get("sha256") or "")
        or _file_digest(target_path)
        != str((plan.get("target") or {}).get("sha256") or "")
        or plan.get("ready_token") != _ready_token(plan)
    ):
        raise ReviewError("sealed ready plan 的 review / resolutions / T 绑定已失效")
    unresolved_count = plan.get("unresolved_count")
    if isinstance(unresolved_count, bool) or not isinstance(unresolved_count, int) or unresolved_count != 0:
        raise ReviewError("sealed ready plan 仍包含待决项")

    sources = _source_artifacts(manifest_path, manifest)
    current_sources = {
        name: {
            "sha256": value["sha256"],
            "exact_body_sha256": value["exact_body_sha256"],
            "body_sha256": value["body_sha256"],
        }
        for name, value in sources.items()
    }
    if current_sources != plan.get("sources"):
        raise ReviewError("B/L/R 快照与 sealed ready plan 不一致")
    native_snapshot = _native_snapshot_artifact(manifest_path, manifest)
    remote_revision = _int((manifest.get("document") or {}).get("current_revision_id"))
    if (
        plan.get("target_base") != "remote_native_snapshot"
        or _int(plan.get("target_base_revision")) != remote_revision
        or (plan.get("remote_native") or {}).get("sha256") != native_snapshot["sha256"]
    ):
        raise ReviewError("sealed ready plan 未绑定采集时飞书原生底稿")

    (
        body_resolutions,
        comment_resolutions,
        target_derivation,
        coverage_resolutions,
        preview_resolution,
        decision_routes,
        consistency_receipt,
        active_build_delta,
    ) = _resolution_maps(
        resolutions_path,
        expected_batch_id=str(manifest.get("batch_id") or ""),
    )
    body_meta = manifest.get("body") or {}
    baseline_body = sources.get("baseline.md", {}).get("text")
    reconciled_body, body_records, _, body_unresolved = _build_body_reconciliation(
        baseline_body if isinstance(baseline_body, str) else None,
        str(sources["local.md"]["text"]),
        str(sources["remote.md"]["text"]),
        body_status=str(body_meta.get("status") or ""),
        common_ancestor_compatible=bool(body_meta.get("common_ancestor_compatible")),
        resolutions=body_resolutions,
        sealing=True,
    )
    comment_records, _, comment_unresolved = _comment_reconciliation(
        manifest,
        comment_resolutions,
        sealing=True,
    )
    target_body = _read_regular_text(target_path, label="target.md")
    target_frontmatter, _ = parse_frontmatter(target_body)
    if target_frontmatter:
        raise ReviewError("target.md 只能包含正文，不能带 frontmatter")
    if body_unresolved or comment_unresolved or any(
        marker in target_body
        for marker in ("<<<<<<< LOCAL ", "||||||| BASELINE ", ">>>>>>> REMOTE ")
    ):
        raise ReviewError("sealed ready plan 的归位结果仍有待决项或冲突标记")

    required = plan.get("required_items")
    if not isinstance(required, dict) or required.get("body") != body_records or required.get(
        "comments"
    ) != comment_records:
        raise ReviewError("resolutions.json 与 sealed ready plan 的 required_items 不一致")
    target_derivation = _validate_target_derivation(
        target_derivation,
        target_body=target_body,
        reconciled_body=reconciled_body,
    )
    if target_derivation != plan.get("target_derivation"):
        raise ReviewError("T 的派生说明与 sealed ready plan 不一致")
    if any(item.get("decision") == "applied" for item in comment_records) and (
        target_derivation["mode"] != "lifecycle_compiled"
        or _normalise(target_body) == _normalise(reconciled_body)
    ):
        raise ReviewError("applied 评论没有被生命周期真实编译进独立 T")

    decision_routes = _validate_decision_routing(
        decision_routes,
        body_records=body_records,
        comment_records=comment_records,
        repo_root=repo_root,
    )
    if decision_routes != plan.get("decision_routing"):
        raise ReviewError("decision 归档路由与 sealed ready plan 不一致")
    if schema_pair == (SCHEMA_VERSION, PLAN_SCHEMA_VERSION):
        consistency_receipt = _validate_consistency_receipt(
            consistency_receipt,
            routes=decision_routes,
            repo_root=repo_root,
            target_body=target_body,
        )
        if consistency_receipt != plan.get("consistency"):
            raise ReviewError("跨决定一致性回执与 sealed ready plan 不一致")
        active_build_delta = _validate_active_build_delta(
            active_build_delta,
            repo_root=repo_root,
            markdown_path=markdown_path,
            body_records=body_records,
            comment_records=comment_records,
            decision_routes=decision_routes,
            target_body=target_body,
        )
        if active_build_delta != plan.get("active_build_delta"):
            raise ReviewError("active build scoped-adjustment 路由与 seal 结果不一致")

    expected_coverage = build_remote_coverage(
        str(sources["remote.md"]["text"]),
        target_body,
        native_snapshot=native_snapshot["value"],
        resolutions=coverage_resolutions,
        batch_id=str(manifest.get("batch_id") or ""),
        remote_revision_id=int(remote_revision or 0),
    )
    coverage = _load_json_object(coverage_path, label="remote-coverage.json")
    if coverage != expected_coverage:
        raise ReviewError(
            "远端覆盖账本不是可执行的完整账本："
            "不能由 sealed resolutions 与 T 重放得到"
        )
    coverage_summary = coverage.get("summary")
    if not isinstance(coverage_summary, dict) or any(
        (
            int(coverage_summary.get("unassigned_count") or 0) != 0,
            int(coverage_summary.get("format_unassigned_count") or 0) != 0,
            coverage_summary.get("remote_accounted_ratio") != 1.0,
            coverage_summary.get("remote_format_accounted_ratio") != 1.0,
        )
    ):
        raise ReviewError("remote-coverage.json 仍有未归位的内容或原生格式")
    plan_coverage = plan.get("remote_coverage")
    if not isinstance(plan_coverage, dict) or any(
        (
            plan_coverage.get("name") != "remote-coverage.json",
            plan_coverage.get("sha256") != _file_digest(coverage_path),
            plan_coverage.get("remote_accounted_ratio")
            != coverage_summary.get("remote_accounted_ratio"),
            plan_coverage.get("remote_format_accounted_ratio")
            != coverage_summary.get("remote_format_accounted_ratio"),
            plan_coverage.get("unassigned_count") != coverage_summary.get("unassigned_count"),
            plan_coverage.get("format_unassigned_count")
            != coverage_summary.get("format_unassigned_count"),
        )
    ):
        raise ReviewError("sealed ready plan 的远端覆盖绑定不完整")

    expected_preview = render_remote_preview(coverage)
    if _read_regular_text(preview_path, label="remote-preview.md") != expected_preview:
        raise ReviewError("remote-preview.md 不能由远端覆盖账本重放得到")
    plan_preview = plan.get("preview")
    sealed_preview = {
        key: value
        for key, value in (plan_preview if isinstance(plan_preview, dict) else {}).items()
        if key in {"approved", "authority", "reason"}
    }
    if (
        not isinstance(plan_preview, dict)
        or plan_preview.get("name") != "remote-preview.md"
        or plan_preview.get("sha256") != _file_digest(preview_path)
        or plan_preview.get("required") != bool(coverage_summary.get("preview_required"))
        or plan_preview.get("pm_confirmation_required")
        != bool(coverage_summary.get("pm_confirmation_required"))
        or preview_resolution != sealed_preview
    ):
        raise ReviewError("PM 预览确认与 sealed ready plan 不一致")
    if bool(coverage_summary.get("preview_required")) and (
        preview_resolution.get("approved") is not True
        or preview_resolution.get("authority")
        not in {"agent_reviewed", "pm_confirmed", "rule"}
        or not str(preview_resolution.get("reason") or "").strip()
    ):
        raise ReviewError("强制远端预览尚未形成有效确认")

    target_binding = plan.get("target")
    target_exact_hash = hashlib.sha256(target_body.encode("utf-8")).hexdigest()
    if (
        not isinstance(target_binding, dict)
        or target_binding.get("name") != "target.md"
        or target_binding.get("sha256") != _file_digest(target_path)
        or target_binding.get("exact_body_sha256") != target_exact_hash
        or target_binding.get("body_sha256") != _body_hash(target_body)
        or plan.get("comments_canonical_sha256")
        != (manifest.get("comments") or {}).get("canonical_sha256")
    ):
        raise ReviewError("sealed ready plan 的 T 或评论快照绑定不完整")
    return {
        "repo_root": repo_root,
        "markdown_path": markdown_path,
        "resolutions_path": resolutions_path,
        "target_path": target_path,
        "target_body": target_body,
        "target_exact_hash": target_exact_hash,
        "sources": sources,
        "native_snapshot": native_snapshot,
        "coverage": coverage,
        "coverage_summary": coverage_summary,
        "active_build_delta": active_build_delta,
    }


def apply_target(args: argparse.Namespace) -> int:
    plan_path = _canonical_regular_file(
        Path(args.plan),
        label="apply-plan.json",
    )
    if plan_path.name != "apply-plan.json":
        raise ReviewError("--plan 必须指向本批次的 apply-plan.json")
    plan = _load_json_object(plan_path, label="apply-plan.json")
    manifest_path = plan_path.parent / "review.json"
    manifest = _load_manifest(
        _canonical_regular_file(manifest_path, label="本批次 review.json")
    )
    if (
        _int(manifest.get("schema_version")) == SCHEMA_VERSION
        and _int(plan.get("schema_version")) == PLAN_SCHEMA_VERSION
    ):
        _validate_sealed_batch_contract(
            manifest_path,
            manifest,
            plan_path,
            plan,
            require_current_schema=True,
        )
    _reject_read_only_handoff(
        manifest_path,
        manifest,
        plan_path=plan_path,
        plan=plan,
    )
    if (
        plan.get("kind") != "pmai_lark_review_apply_plan"
        or _int(plan.get("schema_version"))
        not in {PLAN_SCHEMA_VERSION, PREVIOUS_PLAN_SCHEMA_VERSION}
        or plan.get("state") != "ready"
    ):
        raise ReviewError("apply-plan.json 尚未 seal 为 ready")

    resolutions_path = plan_path.parent / "resolutions.json"
    target_path = plan_path.parent / "target.md"
    for path, label in (
        (manifest_path, "review.json"),
        (resolutions_path, "resolutions.json"),
        (target_path, "target.md"),
    ):
        _canonical_regular_file(path, label=f"本批次 {label}")
    if manifest.get("batch_id") != plan.get("batch_id"):
        raise ReviewError("apply-plan.json 与 review.json 批次不匹配")
    manifest_markdown_path = _manifest_markdown_path(manifest)
    repo_root = _manifest_repository_root(manifest, manifest_markdown_path)
    if str(plan.get("repo_root") or "") != str(repo_root):
        raise ReviewError("apply-plan.json 与 review.json 绑定的 PMAI 仓根不一致")
    if _file_digest(manifest_path) != str((plan.get("manifest") or {}).get("sha256") or ""):
        raise ReviewError("review.json 在 seal 后发生变化")
    if _file_digest(resolutions_path) != str((plan.get("resolutions") or {}).get("sha256") or ""):
        raise ReviewError("resolutions.json 在 seal 后发生变化")
    if _file_digest(target_path) != str((plan.get("target") or {}).get("sha256") or ""):
        raise ReviewError("target.md 在 seal 后发生变化")
    if plan.get("ready_token") != _ready_token(plan):
        raise ReviewError("apply-plan.json 的 ready 绑定不完整或已被修改")
    if int(plan.get("unresolved_count") or 0) != 0:
        raise ReviewError("apply-plan.json 仍包含待决项")

    (
        body_resolutions,
        comment_resolutions,
        target_derivation,
        coverage_resolutions,
        preview_resolution,
        decision_routing_resolutions,
        consistency_receipt,
        active_build_delta,
    ) = _resolution_maps(
        resolutions_path,
        expected_batch_id=str(manifest.get("batch_id") or ""),
    )
    if target_derivation != plan.get("target_derivation"):
        raise ReviewError("T 的派生说明与 seal 结果不一致")
    if preview_resolution != {
        key: value
        for key, value in (plan.get("preview") or {}).items()
        if key in {"approved", "authority", "reason"}
    }:
        raise ReviewError("PM 预览确认与 seal 结果不一致")
    required = plan.get("required_items") or {}
    body_items = required.get("body") if isinstance(required, dict) else None
    comment_items = required.get("comments") if isinstance(required, dict) else None
    if not isinstance(body_items, list) or not isinstance(comment_items, list):
        raise ReviewError("apply-plan.json 缺少 required_items")
    decision_routing_resolutions = _validate_decision_routing(
        decision_routing_resolutions,
        body_records=body_items,
        comment_records=comment_items,
        repo_root=repo_root,
    )
    if decision_routing_resolutions != plan.get("decision_routing"):
        raise ReviewError("decision 归档路由与 seal 结果不一致")
    if _int(plan.get("schema_version")) == PLAN_SCHEMA_VERSION:
        consistency_receipt = _validate_consistency_receipt(
            consistency_receipt,
            routes=decision_routing_resolutions,
            repo_root=repo_root,
            target_body=_read_regular_text(target_path, label="target.md"),
        )
        if consistency_receipt != plan.get("consistency"):
            raise ReviewError("跨决定一致性回执与 seal 结果不一致")
        active_build_delta = _validate_active_build_delta(
            active_build_delta,
            repo_root=repo_root,
            markdown_path=manifest_markdown_path,
            body_records=body_items,
            comment_records=comment_items,
            decision_routes=decision_routing_resolutions,
            target_body=_read_regular_text(target_path, label="target.md"),
        )
        if active_build_delta != plan.get("active_build_delta"):
            raise ReviewError("active build scoped-adjustment 路由与 seal 结果不一致")
    if {str(item.get("change_id") or "") for item in body_items if isinstance(item, dict)} != set(body_resolutions):
        raise ReviewError("正文归位项与 seal 结果不一致")
    if {str(item.get("comment_id") or "") for item in comment_items if isinstance(item, dict)} != set(comment_resolutions):
        raise ReviewError("评论处置项与 seal 结果不一致")
    for item in body_items:
        if not isinstance(item, dict):
            raise ReviewError("apply-plan.json 的正文归位项格式异常")
        resolution = body_resolutions[str(item.get("change_id"))]
        if any(
            str(item.get(key) or "") != str(resolution.get(key) or "")
            for key in ("decision", "authority", "reason")
        ):
            raise ReviewError("正文归位决定与 resolutions.json 不一致")
    for item in comment_items:
        if not isinstance(item, dict):
            raise ReviewError("apply-plan.json 的评论处置项格式异常")
        resolution = comment_resolutions[str(item.get("comment_id"))]
        if any(
            str(item.get(key) or "") != str(resolution.get(key) or "")
            for key in ("decision", "authority", "reason", "result_text")
        ):
            raise ReviewError("评论处置决定与 resolutions.json 不一致")
    if any(
        str(item.get("decision") or "") in {"pending", "needs_pm"}
        for item in [*body_items, *comment_items]
        if isinstance(item, dict)
    ):
        raise ReviewError("apply-plan.json 仍有未决决定")

    sources = _source_artifacts(manifest_path, manifest)
    current_sources = {
        name: {
            "sha256": value["sha256"],
            "exact_body_sha256": value["exact_body_sha256"],
            "body_sha256": value["body_sha256"],
        }
        for name, value in sources.items()
    }
    if current_sources != plan.get("sources"):
        raise ReviewError("B/L/R 快照与 seal 结果不一致")
    native_snapshot = _native_snapshot_artifact(manifest_path, manifest)
    if (
        plan.get("target_base") != "remote_native_snapshot"
        or _int(plan.get("target_base_revision"))
        != _int((manifest.get("document") or {}).get("current_revision_id"))
        or (plan.get("remote_native") or {}).get("sha256")
        != native_snapshot["sha256"]
    ):
        raise ReviewError("apply-plan.json 未绑定采集时飞书原生底稿")
    coverage_path = plan_path.parent / "remote-coverage.json"
    preview_path = plan_path.parent / "remote-preview.md"
    if (
        _file_digest(coverage_path)
        != str((plan.get("remote_coverage") or {}).get("sha256") or "")
        or _file_digest(preview_path)
        != str((plan.get("preview") or {}).get("sha256") or "")
    ):
        raise ReviewError("远端覆盖账本或 PM 预览在 seal 后变化")
    coverage = _load_json_object(coverage_path, label="remote-coverage.json")
    if (
        coverage.get("kind") != REMOTE_COVERAGE_KIND
        or coverage.get("schema_version") != REMOTE_COVERAGE_SCHEMA_VERSION
        or coverage.get("batch_id") != manifest.get("batch_id")
        or coverage.get("unknown_resolution_ids")
        or int((coverage.get("summary") or {}).get("unassigned_count") or 0) != 0
        or int((coverage.get("summary") or {}).get("format_unassigned_count") or 0) != 0
    ):
        raise ReviewError("远端覆盖账本不是可执行的完整账本")

    markdown_path = _canonical_regular_file(
        Path(args.markdown),
        label="apply 目标 markdown",
    )
    if markdown_path != _manifest_markdown_path(manifest) or str(markdown_path) != str(plan.get("markdown_path") or ""):
        raise ReviewError("apply 目标不是本批次绑定的本地规格")
    current_raw = _read_regular_text(markdown_path, label="apply 目标")
    frontmatter, current_body = parse_frontmatter(current_raw)
    document = plan.get("document") or {}
    doc_id = str(document.get("doc_id") or "")
    if not doc_id:
        raise ReviewError("apply-plan.json 缺少 doc_id")
    _validate_local_document_identity(
        frontmatter,
        expected_doc_id=doc_id,
        label="apply 目标",
    )
    published_fence = plan.get("published_fence") or {}
    if (
        _int(frontmatter.get("lark_published_revision_id"))
        != _int(published_fence.get("revision_id"))
        or (str(frontmatter.get("lark_published_source_hash") or "") or None)
        != (str(published_fence.get("source_hash") or "") or None)
    ):
        raise ReviewError("本地发布基线在 collect 后变化，请重新 collect")

    target_body = _read_regular_text(target_path, label="target.md")
    target_exact_hash = hashlib.sha256(target_body.encode("utf-8")).hexdigest()
    current_exact_hash = hashlib.sha256(current_body.encode("utf-8")).hexdigest()
    if target_exact_hash != str((plan.get("target") or {}).get("exact_body_sha256") or ""):
        raise ReviewError("target.md 正文摘要与 apply-plan.json 不一致")
    already_applied = current_exact_hash == target_exact_hash
    if not already_applied and current_exact_hash != str(
        plan.get("expected_local_exact_body_sha256") or ""
    ):
        raise ReviewError("本地规格正文已在 collect 后变化，拒绝覆盖")

    _preflight()
    remote_document = _document(
        docs_fetch(doc_id, doc_format="markdown", detail="simple")
    )
    remote_doc_id = str(remote_document.get("document_id") or "")
    remote_revision = _int(remote_document.get("revision_id"))
    expected_revision = _int(document.get("remote_revision_id"))
    remote_body = str(remote_document.get("content") or "")
    if remote_doc_id != doc_id or remote_revision != expected_revision:
        raise ReviewError("飞书正文 revision 已在 collect 后变化，请重新 collect")
    if hashlib.sha256(remote_body.encode("utf-8")).hexdigest() != sources["remote.md"]["exact_body_sha256"]:
        raise ReviewError("飞书正文与本批次 R 快照不一致，请重新 collect")

    current_comments, _, _ = _collect_comments(
        doc_id,
        include_solved=True,
        blocks={},
        token_to_block={},
        reviewed_comment_at=0,
        reviewed_comment_ids=set(),
    )
    if _comment_fence_hash(current_comments) != str(
        (manifest.get("comments") or {}).get("fence_sha256") or ""
    ):
        raise ReviewError("飞书评论或回复已在 collect 后变化，请重新 collect")

    final_remote_document = _document(
        docs_fetch(doc_id, doc_format="markdown", detail="simple")
    )
    if (
        str(final_remote_document.get("document_id") or "") != doc_id
        or _int(final_remote_document.get("revision_id")) != expected_revision
        or hashlib.sha256(
            str(final_remote_document.get("content") or "").encode("utf-8")
        ).hexdigest()
        != sources["remote.md"]["exact_body_sha256"]
    ):
        raise ReviewError("飞书正文在评论复核期间变化，请重新 collect")

    if _read_regular_text(markdown_path, label="apply 目标") != current_raw:
        raise ReviewError("本地规格在远端复核期间变化，请重新 collect")

    if already_applied:
        print(
            json.dumps(
                {
                    "status": "already_applied",
                    "markdown_path": str(markdown_path),
                    "target_sha256": target_exact_hash,
                },
                ensure_ascii=False,
            )
        )
        return 0

    replace_markdown_body(
        markdown_path,
        target_body,
        expected_text=current_raw,
        require_canonical_path=True,
    )
    written_raw = _read_regular_text(markdown_path, label="已写入 markdown")
    _, written_body = parse_frontmatter(written_raw)
    if hashlib.sha256(written_body.encode("utf-8")).hexdigest() != target_exact_hash:
        raise ReviewError("target.md 写入后回读摘要不一致")
    print(
        json.dumps(
            {
                "status": "applied",
                "markdown_path": str(markdown_path),
                "batch_id": plan.get("batch_id"),
                "target_sha256": target_exact_hash,
                "expected_remote_revision_id": expected_revision,
                "target_base": plan.get("target_base"),
                "content_coverage": (plan.get("remote_coverage") or {}).get(
                    "remote_accounted_ratio"
                ),
                "format_coverage": (plan.get("remote_coverage") or {}).get(
                    "remote_format_accounted_ratio"
                ),
                },
            ensure_ascii=False,
        )
    )
    return 0


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _payload_sha256(value: dict[str, Any]) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return _sha256_text(encoded)


def _require_sha256(value: object, *, label: str) -> str:
    text = str(value or "")
    if not re.fullmatch(r"[0-9a-f]{64}", text):
        raise ReviewError(f"{label} 不是合法 SHA-256")
    return text


def _load_ready_batch(
    manifest_arg: str,
    plan_arg: str,
    *,
    label: str,
) -> tuple[Path, dict[str, Any], Path, dict[str, Any]]:
    manifest_path = _manifest_path(manifest_arg)
    manifest = _load_manifest(manifest_path)
    expected_plan_path = manifest_path.parent / "apply-plan.json"
    plan_path = _absolute_lexical_path(Path(plan_arg))
    if plan_path != expected_plan_path:
        raise ReviewError(f"{label} 必须使用本批次的 apply-plan.json")
    _canonical_regular_file(plan_path, label="apply-plan.json")
    plan = _load_json_object(plan_path, label="apply-plan.json")
    _reject_read_only_handoff(
        manifest_path,
        manifest,
        plan_path=plan_path,
        plan=plan,
    )
    schema_pair = (
        _int(manifest.get("schema_version")),
        _int(plan.get("schema_version")),
    )
    if (
        plan.get("kind") != "pmai_lark_review_apply_plan"
        or schema_pair
        not in {
            (SCHEMA_VERSION, PLAN_SCHEMA_VERSION),
            (SCHEMA_VERSION, PREVIOUS_PLAN_SCHEMA_VERSION),
            (LEGACY_REVIEW_SCHEMA_VERSION, LEGACY_PLAN_SCHEMA_VERSION),
        }
        or plan.get("state") != "ready"
        or plan.get("batch_id") != manifest.get("batch_id")
        or plan.get("ready_token") != _ready_token(plan)
    ):
        raise ReviewError(f"{label} 只接受已 seal 且批次匹配的 ready plan")
    if _file_digest(manifest_path) != str(
        (plan.get("manifest") or {}).get("sha256") or ""
    ):
        raise ReviewError(f"{label} 前 review.json 已变化")
    resolutions_path = manifest_path.parent / "resolutions.json"
    target_path = manifest_path.parent / "target.md"
    if (
        _file_digest(resolutions_path)
        != str((plan.get("resolutions") or {}).get("sha256") or "")
        or _file_digest(target_path)
        != str((plan.get("target") or {}).get("sha256") or "")
    ):
        raise ReviewError(f"{label} 前目标版本或归位账本已变化")
    return manifest_path, manifest, plan_path, plan


def _comment_index(
    items: object,
    *,
    label: str,
) -> dict[str, dict[str, Any]]:
    if not isinstance(items, list):
        raise ReviewError(f"{label} 不是数组")
    result: dict[str, dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict):
            raise ReviewError(f"{label} 包含非对象条目")
        comment_id = str(item.get("comment_id") or "")
        if not comment_id or comment_id in result:
            raise ReviewError(f"{label} 的 comment_id 缺失或重复")
        result[comment_id] = item
    return result


def _batch_comment_contracts(
    manifest: dict[str, Any],
    plan: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, str], dict[str, str]]:
    manifest_comments = manifest.get("comments")
    collected_by_id = _comment_index(
        manifest_comments.get("fence_items")
        if isinstance(manifest_comments, dict)
        else None,
        label="review.json 全量评论围栏",
    )
    required = plan.get("required_items")
    decisions: dict[str, str] = {}
    result_texts: dict[str, str] = {}
    comment_items = required.get("comments") if isinstance(required, dict) else None
    for comment_id, item in _comment_index(
        comment_items,
        label="apply-plan.json 评论处置项",
    ).items():
        if comment_id not in collected_by_id:
            raise ReviewError("apply-plan.json 包含不在本批围栏中的评论")
        decision = str(item.get("decision") or "")
        if decision not in COMPLETED_COMMENT_DECISIONS | {"deferred"}:
            raise ReviewError(f"评论 {comment_id} 尚未形成可执行的处置决定")
        decisions[comment_id] = decision
        result_texts[comment_id] = str(item.get("result_text") or "").strip()
        if (
            _int(plan.get("schema_version")) == PLAN_SCHEMA_VERSION
            and decision in COMPLETED_COMMENT_DECISIONS
            and not bool(collected_by_id[comment_id].get("is_whole"))
            and not result_texts[comment_id]
        ):
            raise ReviewError(f"评论 {comment_id} 的 ready plan 缺少 result_text")
    return collected_by_id, decisions, result_texts


def _published_target_context(
    manifest: dict[str, Any],
    plan: dict[str, Any],
    *,
    label: str,
) -> dict[str, Any]:
    markdown_path = _manifest_markdown_path(manifest)
    if str(markdown_path) != str(plan.get("markdown_path") or ""):
        raise ReviewError(f"{label} 的本地规格绑定与 ready plan 不一致")
    raw = _read_regular_text(markdown_path, label=f"{label} 目标")
    frontmatter, body = parse_frontmatter(raw)
    if _sha256_text(body) != str(
        (plan.get("target") or {}).get("exact_body_sha256") or ""
    ):
        raise ReviewError(f"{label} 前本地规格不是已应用的目标版本 T")
    document = plan.get("document")
    manifest_document = manifest.get("document")
    doc_id = str(document.get("doc_id") or "") if isinstance(document, dict) else ""
    if (
        not doc_id
        or not isinstance(manifest_document, dict)
        or str(manifest_document.get("doc_id") or "") != doc_id
    ):
        raise ReviewError(f"{label} 的 ready plan 缺少一致的 doc_id")
    _validate_local_document_identity(
        frontmatter,
        expected_doc_id=doc_id,
        label=f"{label} 目标",
    )
    target_source_hash = str((plan.get("target") or {}).get("body_sha256") or "")
    published_source_hash = str(frontmatter.get("lark_published_source_hash") or "")
    if not target_source_hash or published_source_hash != target_source_hash:
        raise ReviewError(f"{label} 前发布基线尚未指向本批目标 T")
    collected_revision = _int(document.get("remote_revision_id"))
    published_revision = _int(frontmatter.get("lark_published_revision_id"))
    if (
        collected_revision is None
        or published_revision is None
        or published_revision < collected_revision
    ):
        raise ReviewError(f"{label} 前发布 revision 尚未追平本批采集版本")
    return {
        "markdown_path": markdown_path,
        "raw": raw,
        "frontmatter": frontmatter,
        "body": body,
        "doc_id": doc_id,
        "published_revision_id": published_revision,
    }


def _remote_coverage_artifact(
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
) -> dict[str, Any]:
    coverage_path = manifest_path.parent / "remote-coverage.json"
    binding = plan.get("remote_coverage")
    if (
        not isinstance(binding, dict)
        or binding.get("name") != "remote-coverage.json"
        or _file_digest(coverage_path) != str(binding.get("sha256") or "")
    ):
        raise ReviewError("remote-coverage.json 与 ready plan 绑定不一致")
    coverage = _load_json_object(coverage_path, label="remote-coverage.json")
    summary = coverage.get("summary")
    if (
        coverage.get("kind") != REMOTE_COVERAGE_KIND
        or coverage.get("schema_version") != REMOTE_COVERAGE_SCHEMA_VERSION
        or coverage.get("batch_id") != manifest.get("batch_id")
        or coverage.get("target_base") != "remote_native_snapshot"
        or not isinstance(summary, dict)
        or coverage.get("unknown_resolution_ids")
        or int(summary.get("unassigned_count") or 0) != 0
        or int(summary.get("format_unassigned_count") or 0) != 0
    ):
        raise ReviewError("remote-coverage.json 不是完整的远端覆盖账本")
    return {"path": coverage_path, "value": coverage}


def _markdown_verification_sha256(markdown: str) -> str:
    projection = markdown_verification_projection(markdown)
    encoded = json.dumps(
        projection,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    return _sha256_text(encoded)


def _sync_verification(
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
    context: dict[str, Any],
) -> dict[str, Any]:
    started = time.monotonic()
    document_fetches_before = _PERF_COUNTERS["document_fetch_api_calls"]
    if (
        _int(manifest.get("schema_version")) != SCHEMA_VERSION
        or _int(plan.get("schema_version"))
        not in {PLAN_SCHEMA_VERSION, PREVIOUS_PLAN_SCHEMA_VERSION}
    ):
        raise ReviewError("旧版批次没有原生格式快照，不能生成格式保真验证")
    native_artifact = _native_snapshot_artifact(manifest_path, manifest)
    coverage_artifact = _remote_coverage_artifact(
        manifest_path,
        manifest,
        plan_path,
        plan,
    )
    doc_id = str(context.get("doc_id") or "")
    published_revision = _int(context.get("published_revision_id"))
    remote_markdown, remote_xml = _fetch_current_pair(doc_id)
    if (
        str(remote_markdown.get("document_id") or "") != doc_id
        or _int(remote_markdown.get("revision_id")) != published_revision
    ):
        raise ReviewError("飞书当前 revision 与本地发布基线不一致，不能完成格式验收")

    target_units = markdown_verification_projection(str(context.get("body") or ""))
    remote_units = markdown_verification_projection(str(remote_markdown.get("content") or ""))
    if remote_units != target_units:
        raise ReviewError("飞书当前正文的稳定语义投影与 sealed T 不一致")

    current_native = build_native_snapshot(remote_xml)
    current_blocks = {
        str(item.get("block_id") or ""): item
        for item in (current_native.get("native") or {}).get("blocks") or []
        if isinstance(item, dict) and str(item.get("block_id") or "")
    }
    format_entries = coverage_artifact["value"].get("native_format_entries")
    if not isinstance(format_entries, list):
        raise ReviewError("remote-coverage.json 缺少原生格式清单")
    preserved_count = 0
    for entry in format_entries:
        if not isinstance(entry, dict) or not entry.get("accounted"):
            raise ReviewError("远端原生格式清单包含未归位项")
        if entry.get("format_disposition") != "preserved":
            continue
        block_id = str(entry.get("block_id") or "")
        current = current_blocks.get(block_id)
        if (
            current is None
            or current.get("format_sha256") != entry.get("format_sha256")
            or current.get("resources") != entry.get("resources")
        ):
            raise ReviewError(f"飞书原生 block {block_id} 的格式或资源未被保留")
        preserved_count += 1

    original_document = native_artifact["value"].get("document") or {}
    current_document = current_native.get("document") or {}
    original_references = original_document.get("reference_map") or {}
    current_references = current_document.get("reference_map") or {}
    if not isinstance(original_references, dict) or not isinstance(current_references, dict):
        raise ReviewError("飞书 reference_map 结构异常")
    if any(current_references.get(key) != value for key, value in original_references.items()):
        raise ReviewError("飞书原有引用映射未被完整保留")

    summary = coverage_artifact["value"]["summary"]
    return {
        "kind": REMOTE_VERIFICATION_KIND,
        "schema_version": REMOTE_VERIFICATION_SCHEMA_VERSION,
        "batch_id": manifest.get("batch_id"),
        "plan_ready_token": plan.get("ready_token"),
        "document": {
            "doc_id": doc_id,
            "target_base_revision": plan.get("target_base_revision"),
            "verified_revision_id": published_revision,
        },
        "target_base": "remote_native_snapshot",
        "content_projection_match": True,
        "remote_accounted_ratio": summary.get("remote_accounted_ratio"),
        "remote_format_accounted_ratio": summary.get(
            "remote_format_accounted_ratio"
        ),
        "preserved_native_block_count": preserved_count,
        "original_reference_count": len(original_references),
        "original_references_preserved": True,
        "remote_markdown_exact_sha256": _sha256_text(
            str(remote_markdown.get("content") or "")
        ),
        "remote_markdown_projection_sha256": _markdown_verification_sha256(
            str(remote_markdown.get("content") or "")
        ),
        "current_native_content_sha256": (current_native.get("native") or {}).get(
            "content_sha256"
        ),
        "elapsed_seconds": round(time.monotonic() - started, 6),
        "document_fetch_api_calls": (
            _PERF_COUNTERS["document_fetch_api_calls"] - document_fetches_before
        ),
    }


def verify_sync(args: argparse.Namespace) -> int:
    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        args.manifest,
        args.plan,
        label="verify-sync",
    )
    context = _published_target_context(manifest, plan, label="verify-sync")
    _preflight()
    verification = _sync_verification(
        manifest_path,
        manifest,
        plan_path,
        plan,
        context,
    )
    verification_path = manifest_path.parent / "remote-verification.json"
    _write_json(verification_path, verification)
    print(json.dumps({
        "status": "verified",
        "target_base": verification["target_base"],
        "revision_id": verification["document"]["verified_revision_id"],
        "content_coverage": verification["remote_accounted_ratio"],
        "format_coverage": verification["remote_format_accounted_ratio"],
        "preserved_native_blocks": verification["preserved_native_block_count"],
        "verification": str(verification_path),
        "elapsed_seconds": verification["elapsed_seconds"],
        "document_fetch_api_calls": verification["document_fetch_api_calls"],
    }, ensure_ascii=False))
    return 0


def _remote_verification_artifact(
    manifest_path: Path,
    manifest: dict[str, Any],
    plan: dict[str, Any],
    *,
    doc_id: str,
    published_revision: int,
    expected_projection_sha256: str | None = None,
    expected_coverage: dict[str, Any] | None = None,
) -> dict[str, Any]:
    path = manifest_path.parent / "remote-verification.json"
    try:
        value = _load_json_object(path, label="remote-verification.json")
    except ReviewError as exc:
        raise ReviewError(
            "缺少安全可读的本批 remote-verification.json；请先运行 verify-sync"
        ) from exc
    document = value.get("document")
    markdown_hash = str(value.get("remote_markdown_projection_sha256") or "")
    remote_exact_hash = str(value.get("remote_markdown_exact_sha256") or "")
    native_hash = str(value.get("current_native_content_sha256") or "")
    coverage_matches = True
    if expected_coverage is not None:
        coverage_matches = (
            value.get("remote_accounted_ratio")
            == expected_coverage.get("remote_accounted_ratio")
            and value.get("remote_format_accounted_ratio")
            == expected_coverage.get("remote_format_accounted_ratio")
        )
    if (
        value.get("kind") != REMOTE_VERIFICATION_KIND
        or value.get("schema_version") != REMOTE_VERIFICATION_SCHEMA_VERSION
        or value.get("batch_id") != manifest.get("batch_id")
        or value.get("plan_ready_token") != plan.get("ready_token")
        or value.get("target_base") != "remote_native_snapshot"
        or value.get("content_projection_match") is not True
        or value.get("remote_accounted_ratio") != 1.0
        or value.get("remote_format_accounted_ratio") != 1.0
        or not coverage_matches
        or value.get("original_references_preserved") is not True
        or not isinstance(document, dict)
        or str(document.get("doc_id") or "") != doc_id
        or _int(document.get("verified_revision_id")) != published_revision
        or _int(document.get("target_base_revision"))
        != _int(plan.get("target_base_revision"))
        or not re.fullmatch(r"[0-9a-f]{64}", markdown_hash)
        or (expected_projection_sha256 is not None and markdown_hash != expected_projection_sha256)
        or not re.fullmatch(r"[0-9a-f]{64}", remote_exact_hash)
        or not re.fullmatch(r"[0-9a-f]{64}", native_hash)
        or not isinstance(value.get("preserved_native_block_count"), int)
        or int(value.get("preserved_native_block_count") or 0) < 0
        or not isinstance(value.get("original_reference_count"), int)
        or int(value.get("original_reference_count") or 0) < 0
        or not isinstance(value.get("document_fetch_api_calls"), int)
        or int(value.get("document_fetch_api_calls") or 0) < 2
    ):
        raise ReviewError("remote-verification.json 与当前 ready plan / 发布 revision 不一致")
    return value


def validate_approval(args: argparse.Namespace) -> int:
    """Validate the complete local receipt consumed by build accepted-delta."""

    repo_root = _canonical_directory(Path(args.repo_root), label="审批证据仓根")
    markdown_input = _canonical_regular_file(
        Path(args.markdown), label="审批证据对应模块规格"
    )
    review_root = _canonical_directory(
        repo_root / ".pm-workflow" / "context" / "lark-review",
        label="lark-review 批次根目录",
    )
    artifact_candidate = _absolute_lexical_path(Path(args.artifact))
    if artifact_candidate.name != "remote-verification.json":
        raise ReviewError("审批证据必须指向本批 remote-verification.json")
    artifact_path = _canonical_regular_file(
        artifact_candidate,
        label="remote-verification.json",
    )
    batch_dir = _canonical_directory(artifact_path.parent, label="lark-review 批次目录")
    try:
        batch_relative = batch_dir.relative_to(review_root)
    except ValueError as exc:
        raise ReviewError(
            "审批证据必须位于当前仓 .pm-workflow/context/lark-review/"
        ) from exc
    if len(batch_relative.parts) != 1 or not batch_relative.name.startswith("batch."):
        raise ReviewError("审批证据必须位于单一安全的 batch.* 评审目录")

    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        str(batch_dir / "review.json"),
        str(batch_dir / "apply-plan.json"),
        label="build approval",
    )
    if (
        _int(manifest.get("schema_version")) != SCHEMA_VERSION
        or _int(plan.get("schema_version")) != PLAN_SCHEMA_VERSION
        or str(manifest.get("batch_id") or "") != str(args.batch_id)
    ):
        raise ReviewError(
            "审批证据不是该 batch ID 的当前 sealed Lark 评审批次"
        )
    sealed = _validate_sealed_batch_contract(
        manifest_path,
        manifest,
        plan_path,
        plan,
        require_current_schema=True,
    )
    manifest_markdown = _manifest_markdown_path(manifest)
    manifest_root = _manifest_repository_root(manifest, manifest_markdown)
    if manifest_root != repo_root or manifest_markdown != markdown_input:
        raise ReviewError("审批证据未绑定当前仓库与当前模块 spec.md")

    _source_artifacts(manifest_path, manifest)
    _native_snapshot_artifact(manifest_path, manifest)
    resolutions_path = _canonical_regular_file(
        batch_dir / "resolutions.json",
        label="resolutions.json",
    )
    (
        _,
        _,
        target_derivation,
        _,
        preview_resolution,
        decision_routing,
        consistency,
        active_build_delta,
    ) = _resolution_maps(
        resolutions_path,
        expected_batch_id=str(manifest.get("batch_id") or ""),
    )
    required = plan.get("required_items")
    body_items = required.get("body") if isinstance(required, dict) else None
    comment_items = required.get("comments") if isinstance(required, dict) else None
    if not isinstance(body_items, list) or not isinstance(comment_items, list):
        raise ReviewError("sealed ready plan 缺少完整 required_items")
    active_build_delta = sealed["active_build_delta"]
    if active_build_delta is None or any(
        current != sealed
        for current, sealed in (
            (target_derivation, plan.get("target_derivation")),
            (decision_routing, plan.get("decision_routing")),
            (consistency, plan.get("consistency")),
            (active_build_delta, plan.get("active_build_delta")),
        )
    ):
        raise ReviewError(
            "sealed ready plan 未固化可进入当前 build 的 scoped-adjustment 路由"
        )
    expected_preview = {
        key: value
        for key, value in (plan.get("preview") or {}).items()
        if key in {"approved", "authority", "reason"}
    }
    if preview_resolution != expected_preview:
        raise ReviewError("sealed ready plan 的预览确认与 resolutions.json 不一致")

    coverage_artifact = _remote_coverage_artifact(
        manifest_path,
        manifest,
        plan_path,
        plan,
    )
    coverage_summary = coverage_artifact["value"]["summary"]
    context = _published_target_context(manifest, plan, label="build approval")
    verification = _remote_verification_artifact(
        manifest_path,
        manifest,
        plan,
        doc_id=str(context["doc_id"]),
        published_revision=int(context["published_revision_id"]),
        expected_projection_sha256=_markdown_verification_sha256(str(context["body"])),
        expected_coverage=coverage_summary,
    )
    if artifact_path != batch_dir / "remote-verification.json":
        raise ReviewError("审批证据路径与已验证批次不一致")

    target_path = _canonical_regular_file(batch_dir / "target.md", label="target.md")
    result = {
        "batch_id": str(manifest["batch_id"]),
        "path": artifact_path.relative_to(repo_root).as_posix(),
        "sha256": _file_digest(artifact_path),
        "plan_path": plan_path.relative_to(repo_root).as_posix(),
        "plan_sha256": _file_digest(plan_path),
        "target_sha256": _file_digest(target_path),
        "doc_id": str(verification["document"]["doc_id"]),
        "verified_revision_id": int(
            verification["document"]["verified_revision_id"]
        ),
        "remote_markdown_projection_sha256": str(
            verification["remote_markdown_projection_sha256"]
        ),
        "active_build_delta": active_build_delta,
    }
    print(json.dumps(result, ensure_ascii=False))
    return 0


def _comment_actions_path(manifest_path: Path) -> Path:
    return manifest_path.parent / "comment-actions.json"


def _empty_comment_performance() -> dict[str, int | float]:
    return {
        "attempt_count": 0,
        "elapsed_seconds": 0.0,
        "document_fetch_api_calls": 0,
        "comment_full_scans": 0,
        "comment_list_api_calls": 0,
        "comment_reply_api_calls": 0,
        "reply_write_api_calls": 0,
        "solve_write_api_calls": 0,
    }


def _comment_scan_counters() -> dict[str, int]:
    return {
        key: int(_PERF_COUNTERS.get(key, 0))
        for key in (
            "comment_full_scans",
            "comment_list_api_calls",
            "comment_reply_api_calls",
        )
    }


def _record_comment_performance(
    value: dict[str, Any],
    *,
    before_scan_counters: dict[str, int],
    started: float,
    document_fetches: int = 0,
    reply_writes: int = 0,
    solve_writes: int = 0,
) -> None:
    performance = value.get("performance")
    if not isinstance(performance, dict):
        raise ReviewError("comment-actions.json 缺少 performance 账本")
    performance["attempt_count"] = int(performance.get("attempt_count") or 0) + 1
    performance["elapsed_seconds"] = round(
        float(performance.get("elapsed_seconds") or 0)
        + (time.monotonic() - started),
        6,
    )
    performance["document_fetch_api_calls"] = int(
        performance.get("document_fetch_api_calls") or 0
    ) + document_fetches
    performance["reply_write_api_calls"] = int(
        performance.get("reply_write_api_calls") or 0
    ) + reply_writes
    performance["solve_write_api_calls"] = int(
        performance.get("solve_write_api_calls") or 0
    ) + solve_writes
    current = _comment_scan_counters()
    for key, current_value in current.items():
        performance[key] = int(performance.get(key) or 0) + (
            current_value - int(before_scan_counters.get(key) or 0)
        )


def _new_comment_actions(
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
    *,
    doc_id: str,
    published_revision_id: int,
    execution_mode: str = "single",
) -> dict[str, Any]:
    comments = manifest.get("comments")
    initial_fence = _require_sha256(
        comments.get("fence_sha256") if isinstance(comments, dict) else None,
        label="review.json comments.fence_sha256",
    )
    return {
        "kind": COMMENT_ACTIONS_KIND,
        "schema_version": COMMENT_ACTIONS_SCHEMA_VERSION,
        "batch_id": manifest.get("batch_id"),
        "manifest": {
            "name": "review.json",
            "sha256": _file_digest(manifest_path),
        },
        "plan": {
            "name": "apply-plan.json",
            "sha256": _file_digest(plan_path),
            "ready_token": plan.get("ready_token"),
        },
        "document": {
            "doc_id": doc_id,
            "published_revision_id": published_revision_id,
        },
        "execution_mode": execution_mode,
        "initial_fence_sha256": initial_fence,
        "current_fence_sha256": initial_fence,
        "performance": _empty_comment_performance(),
        "actions": [],
    }


def _upgrade_comment_actions(value: dict[str, Any]) -> dict[str, Any]:
    """Upgrade v1/v2 receipts without inventing missing server evidence."""
    schema_version = _int(value.get("schema_version"))
    if schema_version == COMMENT_ACTIONS_SCHEMA_VERSION:
        return json.loads(json.dumps(value, ensure_ascii=False))
    if schema_version not in {1, 2}:
        raise ReviewError("comment-actions.json schema_version 不受支持")
    upgraded = json.loads(json.dumps(value, ensure_ascii=False))
    upgraded["schema_version"] = COMMENT_ACTIONS_SCHEMA_VERSION
    upgraded.setdefault("execution_mode", "single")
    upgraded.setdefault("performance", _empty_comment_performance())
    actions = upgraded.get("actions")
    if not isinstance(actions, list):
        raise ReviewError("comment-actions.json actions 必须是数组")
    for action in actions:
        if not isinstance(action, dict):
            raise ReviewError("comment-actions.json action 必须是对象")
        status = str(action.get("status") or "")
        solved_time = _int(action.get("solved_time"))
        if schema_version == 1:
            action["solve_evidence_mode"] = (
                "server_time"
                if status in {"completed", "reopen_requested", "reopened"}
                and solved_time is not None
                else None
            )
            action["reply_evidence_mode"] = (
                "legacy_stable_readback" if action.get("reply") is not None else None
            )
            action["reply_write_ack_sha256"] = None
            action["solve_write_ack_sha256"] = None
        else:
            action.setdefault("reply_write_ack_sha256", None)
            action.setdefault(
                "reply_evidence_mode",
                "legacy_stable_readback" if action.get("reply") is not None else None,
            )
        action["completion_status"] = (
            "solved_by_pmai"
            if status in {"completed", "reopen_requested", "reopened"}
            else "open"
        )
    return upgraded


def _validate_comment_actions(
    value: dict[str, Any],
    *,
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
    doc_id: str,
    published_revision_id: int,
) -> None:
    expected_top_keys = {
        "kind",
        "schema_version",
        "batch_id",
        "manifest",
        "plan",
        "document",
        "execution_mode",
        "initial_fence_sha256",
        "current_fence_sha256",
        "performance",
        "actions",
    }
    if set(value) != expected_top_keys:
        raise ReviewError("comment-actions.json 顶层 schema 不完整或包含未知字段")
    manifest_binding = value.get("manifest")
    plan_binding = value.get("plan")
    document_binding = value.get("document")
    execution_mode = str(value.get("execution_mode") or "")
    performance = value.get("performance")
    expected_performance_keys = set(_empty_comment_performance())
    if (
        value.get("kind") != COMMENT_ACTIONS_KIND
        or value.get("schema_version") != COMMENT_ACTIONS_SCHEMA_VERSION
        or value.get("batch_id") != manifest.get("batch_id")
        or not isinstance(manifest_binding, dict)
        or set(manifest_binding) != {"name", "sha256"}
        or manifest_binding.get("name") != "review.json"
        or manifest_binding.get("sha256") != _file_digest(manifest_path)
        or not isinstance(plan_binding, dict)
        or set(plan_binding) != {"name", "sha256", "ready_token"}
        or plan_binding.get("name") != "apply-plan.json"
        or plan_binding.get("sha256") != _file_digest(plan_path)
        or plan_binding.get("ready_token") != plan.get("ready_token")
        or not isinstance(document_binding, dict)
        or set(document_binding) != {"doc_id", "published_revision_id"}
        or document_binding.get("doc_id") != doc_id
        or _int(document_binding.get("published_revision_id"))
        != published_revision_id
        or execution_mode not in COMMENT_EXECUTION_MODES
        or not isinstance(performance, dict)
        or set(performance) != expected_performance_keys
        or any(
            not isinstance(performance.get(key), (int, float))
            or isinstance(performance.get(key), bool)
            or float(performance.get(key) or 0) < 0
            for key in expected_performance_keys
        )
    ):
        raise ReviewError("comment-actions.json 与本批 review/plan/doc 绑定不一致")
    initial_fence = _require_sha256(
        value.get("initial_fence_sha256"),
        label="comment-actions initial_fence_sha256",
    )
    _require_sha256(
        value.get("current_fence_sha256"),
        label="comment-actions current_fence_sha256",
    )
    manifest_comments = manifest.get("comments")
    if initial_fence != str(
        manifest_comments.get("fence_sha256")
        if isinstance(manifest_comments, dict)
        else ""
    ):
        raise ReviewError("comment-actions.json 的初始评论围栏与 review.json 不一致")

    collected_by_id, decisions, _ = _batch_comment_contracts(manifest, plan)
    actions = value.get("actions")
    if not isinstance(actions, list):
        raise ReviewError("comment-actions.json actions 必须是数组")
    expected_action_keys = {
        "batch_id",
        "plan_ready_token",
        "plan_sha256",
        "doc_id",
        "comment_id",
        "decision",
        "is_whole",
        "status",
        "completion_status",
        "result_text_sha256",
        "before_fence_sha256",
        "before_other_fence_sha256",
        "before_comment",
        "reply",
        "reply_evidence_mode",
        "reply_write_ack_sha256",
        "reply_fence_sha256",
        "solver_user_id",
        "solved_time",
        "solve_evidence_mode",
        "solve_write_ack_sha256",
        "after_fence_sha256",
        "reopened_fence_sha256",
    }
    seen: set[str] = set()
    in_progress = 0
    for action in actions:
        if not isinstance(action, dict) or set(action) != expected_action_keys:
            raise ReviewError("comment-actions.json action schema 不完整或包含未知字段")
        comment_id = str(action.get("comment_id") or "")
        status = str(action.get("status") or "")
        completion_status = str(action.get("completion_status") or "")
        decision = decisions.get(comment_id)
        collected = collected_by_id.get(comment_id)
        if (
            not comment_id
            or comment_id in seen
            or collected is None
            or decision not in COMPLETED_COMMENT_DECISIONS
            or action.get("decision") != decision
            or bool(collected.get("is_solved"))
            or action.get("batch_id") != manifest.get("batch_id")
            or action.get("plan_ready_token") != plan.get("ready_token")
            or action.get("plan_sha256") != plan_binding.get("sha256")
            or action.get("doc_id") != doc_id
            or action.get("is_whole") is not bool(collected.get("is_whole"))
            or status not in COMMENT_ACTION_STATUSES
            or completion_status not in COMMENT_COMPLETION_STATUSES
        ):
            raise ReviewError("comment-actions.json action 与本批评论合同不一致")
        valid_completion = (
            (status in {"pending", "reply_created", "solve_requested"} and completion_status == "open")
            or (status == "replied_pending_pm" and completion_status == "replied_pending_pm")
            or (
                status == "completed"
                and completion_status in {"solved_by_pmai", "solved_by_pm_verified"}
            )
            or (
                status in {"reopen_requested", "reopened"}
                and completion_status == "solved_by_pmai"
            )
        )
        if not valid_completion:
            raise ReviewError(f"评论 {comment_id} 的操作状态与远端完成状态不一致")
        seen.add(comment_id)
        if status in {"pending", "reply_created", "solve_requested", "reopen_requested"}:
            in_progress += 1
        _require_sha256(
            action.get("before_fence_sha256"),
            label=f"评论 {comment_id} before_fence_sha256",
        )
        _require_sha256(
            action.get("before_other_fence_sha256"),
            label=f"评论 {comment_id} before_other_fence_sha256",
        )
        before_comment = action.get("before_comment")
        if (
            not isinstance(before_comment, dict)
            or before_comment != _comment_fence_view(collected)
        ):
            raise ReviewError(f"评论 {comment_id} 的操作前评论证据与 review.json 不一致")
        result_hash = action.get("result_text_sha256")
        if result_hash is not None:
            _require_sha256(result_hash, label=f"评论 {comment_id} result_text_sha256")
        reply = action.get("reply")
        if reply is not None:
            if (
                not isinstance(reply, dict)
                or set(reply) != {"reply_id", "user_id", "text_sha256"}
                or not str(reply.get("reply_id") or "")
                or not str(reply.get("user_id") or "")
                or result_hash is None
                or reply.get("text_sha256") != result_hash
            ):
                raise ReviewError(f"评论 {comment_id} 的 reply 回执不完整")
        if result_hash is None and reply is not None:
            raise ReviewError(f"评论 {comment_id} 的 solve-only 回执不能绑定 reply")
        reply_fence = action.get("reply_fence_sha256")
        reply_evidence_mode = str(action.get("reply_evidence_mode") or "")
        reply_write_ack = action.get("reply_write_ack_sha256")
        if reply_write_ack is not None:
            _require_sha256(
                reply_write_ack,
                label=f"评论 {comment_id} reply_write_ack_sha256",
            )
        if reply_fence is not None:
            _require_sha256(reply_fence, label=f"评论 {comment_id} reply_fence_sha256")
        if status in {
            "reply_created",
            "replied_pending_pm",
            "solve_requested",
            "completed",
            "reopen_requested",
            "reopened",
        } and (
            reply_fence is None or (result_hash is not None and reply is None)
        ):
            raise ReviewError(f"评论 {comment_id} 缺少回复/解决前围栏证据")
        if reply is not None:
            if reply_evidence_mode not in REPLY_EVIDENCE_MODES:
                raise ReviewError(f"评论 {comment_id} 缺少 reply 证据模式")
            if reply_evidence_mode == "write_ack":
                _require_sha256(
                    reply_write_ack,
                    label=f"评论 {comment_id} reply_write_ack_sha256",
                )
            elif reply_write_ack is not None:
                raise ReviewError(f"评论 {comment_id} 的稳定回读不能伪造 reply 写回执")
        elif reply_evidence_mode or reply_write_ack is not None:
            raise ReviewError(f"评论 {comment_id} 尚未形成结果回复证据")
        solved_status = completion_status in {"solved_by_pmai", "solved_by_pm_verified"}
        solver_user_id = str(action.get("solver_user_id") or "")
        solved_time = _int(action.get("solved_time"))
        solve_evidence_mode = str(action.get("solve_evidence_mode") or "")
        solve_write_ack = action.get("solve_write_ack_sha256")
        after_fence = action.get("after_fence_sha256")
        if solved_status:
            if (
                not solver_user_id
                or after_fence is None
                or solve_evidence_mode not in SOLVE_EVIDENCE_MODES
            ):
                raise ReviewError(f"评论 {comment_id} 的 completed 证据不完整")
            _require_sha256(after_fence, label=f"评论 {comment_id} after_fence_sha256")
            if solve_evidence_mode == "server_time":
                if solved_time is None:
                    raise ReviewError(f"评论 {comment_id} 的 server_time 证据缺少 solved_time")
                if solve_write_ack is not None:
                    _require_sha256(
                        solve_write_ack,
                        label=f"评论 {comment_id} solve_write_ack_sha256",
                    )
            elif solve_evidence_mode == "write_ack_and_stable_readback":
                if solved_time is not None:
                    raise ReviewError(f"评论 {comment_id} 的无时间回执不能伪造 solved_time")
                _require_sha256(
                    solve_write_ack,
                    label=f"评论 {comment_id} solve_write_ack_sha256",
                )
            elif solved_time is not None or solve_write_ack is not None:
                raise ReviewError(f"评论 {comment_id} 的 legacy 回执包含不存在的写入证据")
            if (
                completion_status == "solved_by_pmai"
                and reply is not None
                and solver_user_id != str(reply.get("user_id") or "")
            ):
                raise ReviewError(f"评论 {comment_id} 的回复作者与 solver 不一致")
            if completion_status == "solved_by_pm_verified":
                if solve_write_ack is not None:
                    raise ReviewError(f"评论 {comment_id} 的 PM 手工解决不能包含系统 solve 写回执")
                if solve_evidence_mode not in {"server_time", "external_stable_readback"}:
                    raise ReviewError(f"评论 {comment_id} 缺少 PM 手工解决回读证据")
        elif (
            solver_user_id
            or solved_time is not None
            or (after_fence is not None and completion_status != "replied_pending_pm")
            or solve_evidence_mode
            or (solve_write_ack is not None and status != "solve_requested")
        ):
            raise ReviewError(f"评论 {comment_id} 尚未完成却包含完成证据")
        elif solve_write_ack is not None:
            _require_sha256(
                solve_write_ack,
                label=f"评论 {comment_id} solve_write_ack_sha256",
            )
        if completion_status == "replied_pending_pm":
            if reply is None or after_fence is None:
                raise ReviewError(f"评论 {comment_id} 缺少 reply-only 最终回读证据")
            _require_sha256(after_fence, label=f"评论 {comment_id} reply-only after_fence_sha256")
        reopened_fence = action.get("reopened_fence_sha256")
        if status == "reopened":
            _require_sha256(
                reopened_fence,
                label=f"评论 {comment_id} reopened_fence_sha256",
            )
        elif reopened_fence is not None:
            raise ReviewError(f"评论 {comment_id} 尚未 reopen 却包含 reopen 围栏")
    if execution_mode == "single" and in_progress > 1:
        raise ReviewError("comment-actions.json 同时存在多条未完成远端操作")


def _load_comment_actions(
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
    *,
    doc_id: str,
    published_revision_id: int,
    required: bool,
) -> tuple[Path, dict[str, Any] | None]:
    path = _comment_actions_path(manifest_path)
    if not _entry_exists(path, label="comment-actions.json"):
        if required:
            raise ReviewError("缺少本批次 comment-actions.json 完成回执")
        return path, None
    value = _upgrade_comment_actions(
        _load_json_object(path, label="comment-actions.json")
    )
    _validate_comment_actions(
        value,
        manifest_path=manifest_path,
        manifest=manifest,
        plan_path=plan_path,
        plan=plan,
        doc_id=doc_id,
        published_revision_id=published_revision_id,
    )
    return path, value


def _save_comment_actions(
    path: Path,
    value: dict[str, Any],
    *,
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
    doc_id: str,
    published_revision_id: int,
) -> None:
    _validate_comment_actions(
        value,
        manifest_path=manifest_path,
        manifest=manifest,
        plan_path=plan_path,
        plan=plan,
        doc_id=doc_id,
        published_revision_id=published_revision_id,
    )
    _write_json(path, value)


def _read_comment_snapshot(doc_id: str) -> list[dict[str, Any]]:
    items, _, _ = _collect_comments(
        doc_id,
        include_solved=True,
        blocks={},
        token_to_block={},
        reviewed_comment_at=0,
        reviewed_comment_ids=set(),
    )
    return items


def _reply_index(item: dict[str, Any]) -> dict[str, dict[str, Any]]:
    replies = item.get("replies")
    if not isinstance(replies, list):
        raise ReviewError("评论回读缺少 replies 数组")
    result: dict[str, dict[str, Any]] = {}
    for reply in replies:
        if not isinstance(reply, dict):
            raise ReviewError("评论回读的 replies 包含非对象条目")
        reply_id = str(reply.get("reply_id") or "")
        if not reply_id or reply_id in result:
            raise ReviewError("评论回读的 reply_id 缺失或重复")
        result[reply_id] = reply
    return result


def _other_comment_fence_hash(
    items: list[dict[str, Any]],
    comment_id: str,
) -> str:
    return _comment_fence_hash(
        [item for item in items if str(item.get("comment_id") or "") != comment_id]
    )


def _new_comment_replies(
    before: dict[str, Any],
    current: dict[str, Any],
) -> dict[str, dict[str, Any]]:
    if not _comment_preserves_collected_input(before, current):
        raise ReviewError("评论采集输入已被编辑或删除")
    if str(current.get("quote") or "") != str(before.get("quote") or ""):
        raise ReviewError("评论 quote 已变化")
    before_ids = set(_reply_index(before))
    current_replies = _reply_index(current)
    return {
        reply_id: reply
        for reply_id, reply in current_replies.items()
        if reply_id not in before_ids
    }


def _reply_receipt(reply: dict[str, Any]) -> dict[str, str]:
    reply_id = str(reply.get("reply_id") or "")
    user_id = str(reply.get("user_id") or "")
    text = str(reply.get("text") or "").replace("<", "&lt;").replace(">", "&gt;")
    if not reply_id or not user_id:
        raise ReviewError("结果回复缺少 reply_id 或作者 open_id")
    return {
        "reply_id": reply_id,
        "user_id": user_id,
        "text_sha256": _sha256_text(text),
    }


def _reply_from_create_response(
    payload: dict[str, Any],
    *,
    expected_text_sha256: str,
) -> dict[str, str]:
    data = _data(payload)
    raw_reply = data.get("reply", data)
    if not isinstance(raw_reply, dict):
        raise ReviewError("回复创建结果缺少 reply 对象")
    reply_view = _reply_view(raw_reply)
    receipt = _reply_receipt(reply_view)
    if not str(reply_view.get("text") or ""):
        receipt["text_sha256"] = expected_text_sha256
    return receipt


def _verify_action_comment(
    action: dict[str, Any],
    current: dict[str, Any],
    *,
    expect_solved: bool,
    allow_external_solver: bool = False,
) -> None:
    before = action.get("before_comment")
    if not isinstance(before, dict):
        raise ReviewError("评论回执缺少操作前评论证据")
    new_replies = _new_comment_replies(before, current)
    expected_reply = action.get("reply")
    if expected_reply is None:
        if new_replies:
            raise ReviewError("solve-only 评论出现未绑定的新回复")
    else:
        if not isinstance(expected_reply, dict):
            raise ReviewError("评论回执的 reply 不是对象")
        reply_id = str(expected_reply.get("reply_id") or "")
        if set(new_replies) != {reply_id}:
            raise ReviewError("评论新增回复与本批结果 reply ID 不一致")
        remote_reply = _reply_receipt(new_replies[reply_id])
        if remote_reply != expected_reply:
            raise ReviewError("评论结果回复的 ID、作者或正文与回执不一致")
    if bool(current.get("is_solved")) is not expect_solved:
        state = "已解决" if expect_solved else "未解决"
        raise ReviewError(f"评论远端状态不是回执要求的{state}状态")
    if expect_solved:
        solver_user_id = str(current.get("solver_user_id") or "")
        solved_time = _int(current.get("solved_time"))
        if not solver_user_id:
            raise ReviewError("评论解决后缺少 solver_user_id")
        recorded_solver = str(action.get("solver_user_id") or "")
        recorded_time = _int(action.get("solved_time"))
        if recorded_solver and solver_user_id != recorded_solver:
            raise ReviewError("评论当前 solver 与 completed 回执不一致")
        if recorded_time is not None and solved_time != recorded_time:
            raise ReviewError("评论当前 solved_time 与 completed 回执不一致")
        if (
            not allow_external_solver
            and isinstance(expected_reply, dict)
            and solver_user_id != str(expected_reply.get("user_id") or "")
        ):
            raise ReviewError("评论结果回复作者与 solver 不一致")


def _verify_reopen_action_comment(
    action: dict[str, Any],
    current: dict[str, Any],
    *,
    expect_solved: bool,
) -> None:
    """验证受控完成证据，同时允许目标评论在完成后继续收到回复。"""
    before = action.get("before_comment")
    if not isinstance(before, dict):
        raise ReviewError("评论回执缺少操作前评论证据")
    new_replies = _new_comment_replies(before, current)
    expected_reply = action.get("reply")
    if expected_reply is not None:
        if not isinstance(expected_reply, dict):
            raise ReviewError("评论回执的 reply 不是对象")
        reply_id = str(expected_reply.get("reply_id") or "")
        remote_reply = new_replies.get(reply_id)
        if remote_reply is None or _reply_receipt(remote_reply) != expected_reply:
            raise ReviewError("评论结果回复的 ID、作者或正文与受控回执不一致")
    if bool(current.get("is_solved")) is not expect_solved:
        state = "已解决" if expect_solved else "未解决"
        raise ReviewError(f"评论远端状态不是回执要求的{state}状态")
    if expect_solved:
        solver_user_id = str(current.get("solver_user_id") or "")
        solved_time = _int(current.get("solved_time"))
        if (
            not solver_user_id
            or solver_user_id != str(action.get("solver_user_id") or "")
            or (
                _int(action.get("solved_time")) is not None
                and solved_time != _int(action.get("solved_time"))
            )
        ):
            raise ReviewError("评论当前 solver/solved_time 与受控完成回执不一致")
        if isinstance(expected_reply, dict) and solver_user_id != str(
            expected_reply.get("user_id") or ""
        ):
            raise ReviewError("评论结果回复作者与 solver 不一致")


def _record_completed_action(
    action: dict[str, Any],
    current: dict[str, Any],
    *,
    after_fence_sha256: str,
    completion_status: str = "solved_by_pmai",
) -> None:
    solver_user_id = str(current.get("solver_user_id") or "")
    if not solver_user_id:
        raise ReviewError("评论解决后缺少 solver_user_id")
    solved_time = _int(current.get("solved_time"))
    solve_write_ack = action.get("solve_write_ack_sha256")
    action["solver_user_id"] = solver_user_id
    action["solved_time"] = solved_time
    if solved_time is not None:
        action["solve_evidence_mode"] = "server_time"
    elif completion_status == "solved_by_pm_verified":
        action["solve_evidence_mode"] = "external_stable_readback"
    elif solve_write_ack is not None:
        action["solve_evidence_mode"] = "write_ack_and_stable_readback"
    else:
        action["solve_evidence_mode"] = "legacy_stable_readback"
    action["after_fence_sha256"] = after_fence_sha256
    action["status"] = "completed"
    action["completion_status"] = completion_status


def _record_replied_action(
    action: dict[str, Any],
    *,
    after_fence_sha256: str,
) -> None:
    if action.get("reply") is None:
        raise ReviewError("reply-only 评论缺少结果回复回执")
    action["after_fence_sha256"] = after_fence_sha256
    action["status"] = "replied_pending_pm"
    action["completion_status"] = "replied_pending_pm"


def _require_solve_write_ack_for_recovery(action: dict[str, Any]) -> None:
    solve_write_ack = action.get("solve_write_ack_sha256")
    if solve_write_ack is None:
        raise ReviewError(
            "solve_requested 回执缺少系统解决写响应，"
            "不能把外部手工解决记录为受控完成"
        )
    _require_sha256(solve_write_ack, label="solve_requested solve_write_ack_sha256")


def _recover_solve_requested_for_reopen(
    action: dict[str, Any],
    current: dict[str, Any],
    *,
    current_fence_sha256: str,
    allow_new_replies: bool,
) -> None:
    """Promote a proven solve write when the batch's final readback was interrupted."""
    if action.get("status") != "solve_requested":
        return
    _require_solve_write_ack_for_recovery(action)
    if not bool(current.get("is_solved")):
        raise ReviewError("solve_requested 评论当前未解决，请先重跑 complete-comments")

    before = action.get("before_comment")
    if not isinstance(before, dict):
        raise ReviewError("solve_requested 回执缺少操作前评论证据")
    new_replies = _new_comment_replies(before, current)
    expected_reply = action.get("reply")
    if expected_reply is None:
        if not allow_new_replies and new_replies:
            raise ReviewError("solve-only 评论在最终回读前出现未绑定的新回复")
    else:
        if not isinstance(expected_reply, dict):
            raise ReviewError("solve_requested 回执的 reply 不是对象")
        reply_id = str(expected_reply.get("reply_id") or "")
        remote_reply = new_replies.get(reply_id)
        if remote_reply is None or _reply_receipt(remote_reply) != expected_reply:
            raise ReviewError("评论结果回复与 solve_requested 写回执不一致")
        if not allow_new_replies and set(new_replies) != {reply_id}:
            raise ReviewError("评论在最终回读前出现未绑定的新回复")

    solver_user_id = str(current.get("solver_user_id") or "")
    if not solver_user_id:
        raise ReviewError("solve_requested 评论解决后缺少 solver_user_id")
    if isinstance(expected_reply, dict) and solver_user_id != str(
        expected_reply.get("user_id") or ""
    ):
        raise ReviewError("评论结果回复作者与 solver 不一致")
    _record_completed_action(
        action,
        current,
        after_fence_sha256=current_fence_sha256,
    )


def _recover_pending_reply(
    action: dict[str, Any],
    current_items: list[dict[str, Any]],
) -> dict[str, str]:
    comment_id = str(action.get("comment_id") or "")
    current = _comment_index(
        current_items,
        label="结果回复恢复评论围栏",
    ).get(comment_id)
    if current is None:
        raise ReviewError(f"评论 {comment_id} 在结果回复恢复时无法回读")
    if _other_comment_fence_hash(current_items, comment_id) != str(
        action.get("before_other_fence_sha256") or ""
    ):
        raise ReviewError("结果回复恢复时批次外评论发生变化，请重新 collect")
    if bool(current.get("is_solved")):
        raise ReviewError("结果回复尚未绑定回执，但评论已经解决，无法唯一归因")
    before = action.get("before_comment")
    if not isinstance(before, dict):
        raise ReviewError("结果回复恢复缺少操作前评论证据")
    new_replies = _new_comment_replies(before, current)
    if len(new_replies) != 1:
        raise ReviewError("无法唯一识别本批结果回复；请重新 collect")
    recovered = _reply_receipt(next(iter(new_replies.values())))
    if recovered.get("text_sha256") != action.get("result_text_sha256"):
        raise ReviewError("新增回复正文与本批结果文本不一致，请重新 collect")
    recorded = action.get("reply")
    if recorded is not None and recovered != recorded:
        raise ReviewError("远端结果回复与写 API 返回回执不一致")
    return recovered


def _new_comment_action(
    *,
    manifest: dict[str, Any],
    plan: dict[str, Any],
    plan_sha256: str,
    doc_id: str,
    comment_id: str,
    decision: str,
    collected: dict[str, Any],
    current_items: list[dict[str, Any]],
    result_text_sha256: str | None,
) -> dict[str, Any]:
    return {
        "batch_id": manifest.get("batch_id"),
        "plan_ready_token": plan.get("ready_token"),
        "plan_sha256": plan_sha256,
        "doc_id": doc_id,
        "comment_id": comment_id,
        "decision": decision,
        "is_whole": bool(collected.get("is_whole")),
        "status": "pending",
        "completion_status": "open",
        "result_text_sha256": result_text_sha256,
        "before_fence_sha256": _comment_fence_hash(current_items),
        "before_other_fence_sha256": _other_comment_fence_hash(
            current_items, comment_id
        ),
        "before_comment": _comment_fence_view(collected),
        "reply": None,
        "reply_evidence_mode": None,
        "reply_write_ack_sha256": None,
        "reply_fence_sha256": None,
        "solver_user_id": None,
        "solved_time": None,
        "solve_evidence_mode": None,
        "solve_write_ack_sha256": None,
        "after_fence_sha256": None,
        "reopened_fence_sha256": None,
    }


def complete_comment(args: argparse.Namespace) -> int:
    complete_started = time.monotonic()
    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        args.manifest,
        args.plan,
        label="complete-comment",
    )
    context = _published_target_context(
        manifest,
        plan,
        label="complete-comment",
    )
    doc_id = str(context["doc_id"])
    published_revision = int(context["published_revision_id"])
    collected_by_id, decisions, result_texts = _batch_comment_contracts(manifest, plan)
    comment_id = str(args.comment_id or "").strip()
    if not comment_id:
        raise ReviewError("--comment-id 不能为空")
    collected = collected_by_id.get(comment_id)
    decision = decisions.get(comment_id)
    if collected is None or decision not in COMPLETED_COMMENT_DECISIONS:
        raise ReviewError("complete-comment 只能处理本批非 deferred 的已处置评论")
    if bool(collected.get("is_solved")):
        raise ReviewError("complete-comment 不能接管 collect 时已经解决的评论")
    planned_result_text = result_texts.get(comment_id, "")
    supplied_result_text = str(args.result_text or "").strip()
    if planned_result_text and supplied_result_text and planned_result_text != supplied_result_text:
        raise ReviewError("--result-text 与 ready plan 固化的评论结果不一致")
    result_text = supplied_result_text or planned_result_text
    if not bool(collected.get("is_whole")) and not result_text:
        raise ReviewError("局部评论必须提供非空 --result-text")
    result_text = result_text.replace("<", "&lt;").replace(">", "&gt;")
    result_text_sha256 = _sha256_text(result_text) if result_text else None

    _preflight()
    remote_document = _document(
        docs_fetch(doc_id, doc_format="markdown", detail="simple")
    )
    if (
        str(remote_document.get("document_id") or "") != doc_id
        or _int(remote_document.get("revision_id")) != published_revision
    ):
        raise ReviewError("complete-comment 前飞书 revision 与本地发布基线不一致")
    current_items = _read_comment_snapshot(doc_id)
    current_hash = _comment_fence_hash(current_items)
    current_by_id = _comment_index(current_items, label="complete-comment 评论围栏")

    actions_path, actions_value = _load_comment_actions(
        manifest_path,
        manifest,
        plan_path,
        plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
        required=False,
    )
    if actions_value is None:
        actions_value = _new_comment_actions(
            manifest_path,
            manifest,
            plan_path,
            plan,
            doc_id=doc_id,
            published_revision_id=published_revision,
        )
    actions = actions_value["actions"]
    action = next(
        (
            item
            for item in actions
            if isinstance(item, dict) and item.get("comment_id") == comment_id
        ),
        None,
    )
    if action is None:
        if any(
            isinstance(item, dict)
            and item.get("status")
            in {"pending", "reply_created", "solve_requested", "reopen_requested"}
            for item in actions
        ):
            raise ReviewError("另一个评论远端操作尚未收口，请先恢复该操作")
        if current_hash != str(actions_value.get("current_fence_sha256") or ""):
            raise ReviewError("评论围栏与本批回执水位不一致，请重新 collect")
        current = current_by_id.get(comment_id)
        if current is None or _comment_fence_view(current) != _comment_fence_view(collected):
            raise ReviewError("目标评论已在 collect 后变化，请重新 collect")
        action = _new_comment_action(
            manifest=manifest,
            plan=plan,
            plan_sha256=str((actions_value.get("plan") or {}).get("sha256") or ""),
            doc_id=doc_id,
            comment_id=comment_id,
            decision=decision,
            collected=collected,
            current_items=current_items,
            result_text_sha256=result_text_sha256,
        )
        actions.append(action)
        _save_comment_actions(
            actions_path,
            actions_value,
            manifest_path=manifest_path,
            manifest=manifest,
            plan_path=plan_path,
            plan=plan,
            doc_id=doc_id,
            published_revision_id=published_revision,
        )
    elif action.get("result_text_sha256") != result_text_sha256:
        raise ReviewError("complete-comment 重跑必须使用与回执一致的 --result-text")

    status = str(action.get("status") or "")
    if status == "reopened" or status == "reopen_requested":
        raise ReviewError("该评论已进入 reopen 恢复，旧批次回执不能复用")
    if status == "completed":
        if current_hash != str(actions_value.get("current_fence_sha256") or ""):
            raise ReviewError("completed 回执后的评论围栏又发生变化，请重新 collect")
        current = current_by_id.get(comment_id)
        if current is None:
            raise ReviewError("completed 评论当前无法回读")
        _verify_action_comment(action, current, expect_solved=True)
        print(json.dumps({
            "status": "already_completed",
            "batch_id": manifest.get("batch_id"),
            "doc_id": doc_id,
            "comment_id": comment_id,
            "receipt": str(actions_path),
            "elapsed_seconds": round(time.monotonic() - complete_started, 6),
        }, ensure_ascii=False))
        return 0

    if status == "pending" and result_text_sha256 is not None:
        if current_hash != str(action.get("before_fence_sha256") or "") or action.get("reply") is not None:
            recovered = _recover_pending_reply(action, current_items)
            action["reply"] = recovered
            if not action.get("reply_evidence_mode"):
                action["reply_evidence_mode"] = "stable_readback"
            action["reply_fence_sha256"] = current_hash
            action["status"] = "reply_created"
            actions_value["current_fence_sha256"] = current_hash
            _save_comment_actions(
                actions_path,
                actions_value,
                manifest_path=manifest_path,
                manifest=manifest,
                plan_path=plan_path,
                plan=plan,
                doc_id=doc_id,
                published_revision_id=published_revision,
            )
            status = "reply_created"
        else:
            try:
                response = drive_comment_reply_create(doc_id, comment_id, result_text)
                action["reply"] = _reply_from_create_response(
                    response,
                    expected_text_sha256=result_text_sha256,
                )
                action["reply_evidence_mode"] = "write_ack"
                action["reply_write_ack_sha256"] = _payload_sha256(response)
                _save_comment_actions(
                    actions_path,
                    actions_value,
                    manifest_path=manifest_path,
                    manifest=manifest,
                    plan_path=plan_path,
                    plan=plan,
                    doc_id=doc_id,
                    published_revision_id=published_revision,
                )
            except (LarkAdapterError, ReviewError) as exc:
                raise ReviewError(
                    "结果回复创建未能形成完整回执；已保留 pending，"
                    f"重跑 complete-comment 恢复。详情: {exc}"
                ) from exc
            current_items = _read_comment_snapshot(doc_id)
            current_hash = _comment_fence_hash(current_items)
            recovered = _recover_pending_reply(action, current_items)
            if recovered != action.get("reply"):
                raise ReviewError("结果回复回读与写 API 回执不一致，请重新 collect")
            action["reply_fence_sha256"] = current_hash
            action["status"] = "reply_created"
            actions_value["current_fence_sha256"] = current_hash
            _save_comment_actions(
                actions_path,
                actions_value,
                manifest_path=manifest_path,
                manifest=manifest,
                plan_path=plan_path,
                plan=plan,
                doc_id=doc_id,
                published_revision_id=published_revision,
            )
            status = "reply_created"

    current_by_id = _comment_index(current_items, label="complete-comment 当前评论围栏")
    current = current_by_id.get(comment_id)
    if current is None:
        raise ReviewError("complete-comment 无法回读目标评论")
    if status == "pending":
        if result_text_sha256 is not None:
            raise ReviewError("结果回复仍未形成可验证回执")
        if current_hash != str(action.get("before_fence_sha256") or ""):
            raise ReviewError("solve-only 写入前评论围栏发生变化，请重新 collect")
        _verify_action_comment(action, current, expect_solved=False)
        action["reply_fence_sha256"] = current_hash
    elif status == "reply_created":
        if (
            current_hash != str(action.get("reply_fence_sha256") or "")
            or current_hash != str(actions_value.get("current_fence_sha256") or "")
            or _other_comment_fence_hash(current_items, comment_id)
            != str(action.get("before_other_fence_sha256") or "")
        ):
            raise ReviewError("结果回复后的评论围栏发生变化，请重新 collect")
        _verify_action_comment(action, current, expect_solved=False)
    elif status == "solve_requested":
        if _other_comment_fence_hash(current_items, comment_id) != str(
            action.get("before_other_fence_sha256") or ""
        ):
            raise ReviewError("解决操作恢复时批次外评论发生变化，请重新 collect")
        if bool(current.get("is_solved")):
            _require_solve_write_ack_for_recovery(action)
            _verify_action_comment(action, current, expect_solved=True)
            _record_completed_action(
                action,
                current,
                after_fence_sha256=current_hash,
            )
            actions_value["current_fence_sha256"] = current_hash
            _save_comment_actions(
                actions_path,
                actions_value,
                manifest_path=manifest_path,
                manifest=manifest,
                plan_path=plan_path,
                plan=plan,
                doc_id=doc_id,
                published_revision_id=published_revision,
            )
            print(json.dumps({
                "status": "completed",
                "recovered": True,
                "batch_id": manifest.get("batch_id"),
                "doc_id": doc_id,
                "comment_id": comment_id,
                "reply_id": (action.get("reply") or {}).get("reply_id"),
                "solver_user_id": action.get("solver_user_id"),
                "solved_time": action.get("solved_time"),
                "solve_evidence_mode": action.get("solve_evidence_mode"),
                "receipt": str(actions_path),
                "elapsed_seconds": round(time.monotonic() - complete_started, 6),
            }, ensure_ascii=False))
            return 0
        if current_hash != str(actions_value.get("current_fence_sha256") or ""):
            raise ReviewError("解决操作恢复前评论围栏无法与回执匹配")
        _verify_action_comment(action, current, expect_solved=False)
    else:
        raise ReviewError(f"不支持的 comment action 状态: {status}")

    action["status"] = "solve_requested"
    actions_value["current_fence_sha256"] = current_hash
    _save_comment_actions(
        actions_path,
        actions_value,
        manifest_path=manifest_path,
        manifest=manifest,
        plan_path=plan_path,
        plan=plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
    )
    try:
        solve_response = drive_comment_set_solved(doc_id, comment_id, is_solved=True)
        action["solve_write_ack_sha256"] = _payload_sha256(solve_response)
        _save_comment_actions(
            actions_path,
            actions_value,
            manifest_path=manifest_path,
            manifest=manifest,
            plan_path=plan_path,
            plan=plan,
            doc_id=doc_id,
            published_revision_id=published_revision,
        )
    except LarkAdapterError as exc:
        raise ReviewError(
            "评论解决写入未完成；已保留 solve_requested，"
            f"重跑 complete-comment 恢复。详情: {exc}"
        ) from exc
    try:
        final_items = _read_comment_snapshot(doc_id)
    except (LarkAdapterError, ReviewError) as exc:
        raise ReviewError(
            "评论解决后回读失败；已保留 solve_requested，"
            f"重跑 complete-comment 恢复。详情: {exc}"
        ) from exc
    final_hash = _comment_fence_hash(final_items)
    final_by_id = _comment_index(final_items, label="complete-comment 最终评论围栏")
    final_comment = final_by_id.get(comment_id)
    if final_comment is None:
        raise ReviewError("评论解决后无法回读目标评论；回执保持 solve_requested")
    if _other_comment_fence_hash(final_items, comment_id) != str(
        action.get("before_other_fence_sha256") or ""
    ):
        raise ReviewError("评论解决期间批次外评论发生变化；回执保持 solve_requested")
    _verify_action_comment(action, final_comment, expect_solved=True)
    _record_completed_action(
        action,
        final_comment,
        after_fence_sha256=final_hash,
    )
    actions_value["current_fence_sha256"] = final_hash
    _save_comment_actions(
        actions_path,
        actions_value,
        manifest_path=manifest_path,
        manifest=manifest,
        plan_path=plan_path,
        plan=plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
    )
    print(json.dumps({
        "status": "completed",
        "batch_id": manifest.get("batch_id"),
        "doc_id": doc_id,
        "comment_id": comment_id,
        "reply_id": (action.get("reply") or {}).get("reply_id"),
        "reply_user_id": (action.get("reply") or {}).get("user_id"),
        "solver_user_id": action.get("solver_user_id"),
        "solved_time": action.get("solved_time"),
        "solve_evidence_mode": action.get("solve_evidence_mode"),
        "solve_write_ack_sha256": action.get("solve_write_ack_sha256"),
        "before_fence_sha256": action.get("before_fence_sha256"),
        "after_fence_sha256": action.get("after_fence_sha256"),
        "receipt": str(actions_path),
        "elapsed_seconds": round(time.monotonic() - complete_started, 6),
    }, ensure_ascii=False))
    return 0


def _batch_comment_targets(
    manifest: dict[str, Any],
    plan: dict[str, Any],
) -> tuple[
    dict[str, dict[str, Any]],
    dict[str, str],
    list[str],
]:
    collected_by_id, decisions, result_texts = _batch_comment_contracts(
        manifest,
        plan,
    )
    required = plan.get("required_items")
    raw_comments = required.get("comments") if isinstance(required, dict) else []
    ordered_ids = [
        str(item.get("comment_id") or "")
        for item in raw_comments
        if isinstance(item, dict)
        and str(item.get("decision") or "") in COMPLETED_COMMENT_DECISIONS
    ]
    for comment_id in ordered_ids:
        collected = collected_by_id[comment_id]
        if bool(collected.get("is_solved")):
            raise ReviewError(
                f"评论 {comment_id} 在 collect 时已经解决，不能由当前批次再次完成"
            )
        if not bool(collected.get("is_whole")) and not result_texts.get(comment_id):
            raise ReviewError(f"局部评论 {comment_id} 缺少固化的 result_text")
    return collected_by_id, result_texts, ordered_ids


def _recover_batch_action(
    action: dict[str, Any],
    current: dict[str, Any],
    *,
    current_fence_sha256: str,
    reply_only: bool,
) -> None:
    status = str(action.get("status") or "")
    if status == "pending":
        before = action.get("before_comment")
        if not isinstance(before, dict):
            raise ReviewError("批量评论回执缺少操作前证据")
        new_replies = _new_comment_replies(before, current)
        if not new_replies:
            if bool(current.get("is_solved")):
                raise ReviewError("尚未执行的批量评论已被外部解决")
            return
        if action.get("result_text_sha256") is None or len(new_replies) != 1:
            raise ReviewError("批量评论出现无法归因的新回复")
        recovered = _reply_receipt(next(iter(new_replies.values())))
        if recovered.get("text_sha256") != action.get("result_text_sha256"):
            raise ReviewError("批量评论新增回复与固化结果文本不一致")
        recorded = action.get("reply")
        if recorded is not None and recovered != recorded:
            raise ReviewError("批量评论远端回复与写回执不一致")
        action["reply"] = recovered
        action["reply_evidence_mode"] = "stable_readback"
        action["reply_fence_sha256"] = current_fence_sha256
        action["status"] = "reply_created"
        status = "reply_created"
    if status == "reply_created":
        _verify_action_comment(action, current, expect_solved=False)
        return
    if status == "replied_pending_pm":
        if bool(current.get("is_solved")):
            raise ReviewError("reply-only 评论已由 PM 解决；请运行 verify-comments 回读")
        _verify_action_comment(action, current, expect_solved=False)
        return
    if status == "solve_requested":
        if bool(current.get("is_solved")):
            _require_solve_write_ack_for_recovery(action)
            _verify_action_comment(action, current, expect_solved=True)
            _record_completed_action(
                action,
                current,
                after_fence_sha256=current_fence_sha256,
            )
        else:
            _verify_action_comment(action, current, expect_solved=False)
        return
    if status == "completed":
        completion_status = str(action.get("completion_status") or "")
        _verify_action_comment(
            action,
            current,
            expect_solved=True,
            allow_external_solver=completion_status == "solved_by_pm_verified",
        )
        return
    raise ReviewError(f"批量评论不接受状态 {status or 'missing'}")


def complete_comments(args: argparse.Namespace) -> int:
    """整批回复评论，并按所选模式由系统解决或等待 PM 解决。"""
    batch_started = time.monotonic()
    scan_counters_before = _comment_scan_counters()
    document_fetches = 0
    reply_writes = 0
    solve_writes = 0
    reply_only = bool(getattr(args, "reply_only", False))
    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        args.manifest,
        args.plan,
        label="complete-comments",
    )
    if reply_only and _int(plan.get("schema_version")) != PLAN_SCHEMA_VERSION:
        raise ReviewError("reply-only 只接受按当前合同重新 seal 的 v4 批次")
    context = _published_target_context(
        manifest,
        plan,
        label="complete-comments",
    )
    doc_id = str(context["doc_id"])
    published_revision = int(context["published_revision_id"])
    collected_by_id, result_texts, ordered_ids = _batch_comment_targets(
        manifest,
        plan,
    )
    if not ordered_ids:
        print(json.dumps({
            "status": "nothing_to_complete",
            "batch_id": manifest.get("batch_id"),
            "comment_count": 0,
        }, ensure_ascii=False))
        return 0
    if reply_only and any(not result_texts.get(comment_id) for comment_id in ordered_ids):
        raise ReviewError("reply-only 模式不接受无法回复的 whole_document 评论")

    _preflight()
    document_fetches += 1
    remote_document = _document(
        docs_fetch(doc_id, doc_format="markdown", detail="simple")
    )
    if (
        str(remote_document.get("document_id") or "") != doc_id
        or _int(remote_document.get("revision_id")) != published_revision
    ):
        raise ReviewError("complete-comments 前飞书 revision 与本地发布基线不一致")
    current_items = _read_comment_snapshot(doc_id)
    current_hash = _comment_fence_hash(current_items)
    current_by_id = _comment_index(current_items, label="批量评论初始围栏")
    if set(current_by_id) != set(collected_by_id):
        raise ReviewError("批量评论初始围栏出现新增或删除，请重新 collect")

    actions_path, actions_value = _load_comment_actions(
        manifest_path,
        manifest,
        plan_path,
        plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
        required=False,
    )
    if actions_value is None:
        actions_value = _new_comment_actions(
            manifest_path,
            manifest,
            plan_path,
            plan,
            doc_id=doc_id,
            published_revision_id=published_revision,
            execution_mode="reply_only" if reply_only else "batch",
        )
    elif actions_value.get("execution_mode") != ("reply_only" if reply_only else "batch"):
        raise ReviewError(
            "当前 comment-actions.json 的执行模式与本次命令不一致"
        )
    actions = actions_value["actions"]
    action_by_id = {
        str(action.get("comment_id") or ""): action
        for action in actions
        if isinstance(action, dict)
    }
    if set(action_by_id) - set(ordered_ids):
        raise ReviewError("批量评论回执包含当前 ready plan 之外的评论")
    if actions and set(action_by_id) != set(ordered_ids):
        raise ReviewError("批量评论 journal 未原子建立全部 action，拒绝继续写入")

    # 首笔远端写入前一次性建立全部 action，保证中断后知道尚未开始的范围。
    for comment_id in ordered_ids:
        current = current_by_id[comment_id]
        action = action_by_id.get(comment_id)
        result_text = result_texts.get(comment_id, "").replace("<", "&lt;").replace(
            ">", "&gt;"
        )
        result_hash = _sha256_text(result_text) if result_text else None
        if action is None:
            if _comment_fence_view(current) != _comment_fence_view(
                collected_by_id[comment_id]
            ):
                raise ReviewError(f"评论 {comment_id} 已在批量操作前变化")
            action = _new_comment_action(
                manifest=manifest,
                plan=plan,
                plan_sha256=str((actions_value.get("plan") or {}).get("sha256") or ""),
                doc_id=doc_id,
                comment_id=comment_id,
                decision=str(
                    next(
                        item.get("decision")
                        for item in (plan.get("required_items") or {}).get("comments") or []
                        if isinstance(item, dict) and item.get("comment_id") == comment_id
                    )
                ),
                collected=collected_by_id[comment_id],
                current_items=current_items,
                result_text_sha256=result_hash,
            )
            actions.append(action)
            action_by_id[comment_id] = action
        elif action.get("result_text_sha256") != result_hash:
            raise ReviewError(f"评论 {comment_id} 的批量结果文本与现有回执不一致")
        _recover_batch_action(
            action,
            current,
            current_fence_sha256=current_hash,
            reply_only=reply_only,
        )
    for comment_id, collected in collected_by_id.items():
        if comment_id not in ordered_ids and _comment_fence_view(
            current_by_id[comment_id]
        ) != _comment_fence_view(collected):
            raise ReviewError(f"批次外或 deferred 评论 {comment_id} 已变化")
    _save_comment_actions(
        actions_path,
        actions_value,
        manifest_path=manifest_path,
        manifest=manifest,
        plan_path=plan_path,
        plan=plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
    )

    def save_failed_attempt(message: str, exc: Exception) -> ReviewError:
        _record_comment_performance(
            actions_value,
            before_scan_counters=scan_counters_before,
            started=batch_started,
            document_fetches=document_fetches,
            reply_writes=reply_writes,
            solve_writes=solve_writes,
        )
        _save_comment_actions(
            actions_path,
            actions_value,
            manifest_path=manifest_path,
            manifest=manifest,
            plan_path=plan_path,
            plan=plan,
            doc_id=doc_id,
            published_revision_id=published_revision,
        )
        return ReviewError(f"{message}；批量 journal 已保留，重跑恢复。详情: {exc}")

    for comment_id in ordered_ids:
        action = action_by_id[comment_id]
        if action.get("status") == "completed":
            continue
        if action.get("status") == "pending" and action.get("result_text_sha256") is not None:
            result_text = result_texts[comment_id].replace("<", "&lt;").replace(
                ">", "&gt;"
            )
            reply_writes += 1
            try:
                response = drive_comment_reply_create(doc_id, comment_id, result_text)
                action["reply"] = _reply_from_create_response(
                    response,
                    expected_text_sha256=str(action["result_text_sha256"]),
                )
                action["reply_evidence_mode"] = "write_ack"
                action["reply_write_ack_sha256"] = _payload_sha256(response)
                action["reply_fence_sha256"] = str(
                    action.get("before_fence_sha256") or ""
                )
                action["status"] = "reply_created"
                _save_comment_actions(
                    actions_path,
                    actions_value,
                    manifest_path=manifest_path,
                    manifest=manifest,
                    plan_path=plan_path,
                    plan=plan,
                    doc_id=doc_id,
                    published_revision_id=published_revision,
                )
            except (LarkAdapterError, ReviewError) as exc:
                raise save_failed_attempt(
                    f"评论 {comment_id} 的结果回复创建失败",
                    exc,
                ) from exc
        if action.get("status") == "pending":
            action["reply_fence_sha256"] = str(action.get("before_fence_sha256") or "")
        if reply_only:
            continue
        if action.get("status") in {"pending", "reply_created"}:
            action["status"] = "solve_requested"
            _save_comment_actions(
                actions_path,
                actions_value,
                manifest_path=manifest_path,
                manifest=manifest,
                plan_path=plan_path,
                plan=plan,
                doc_id=doc_id,
                published_revision_id=published_revision,
            )
        if action.get("status") == "solve_requested":
            solve_writes += 1
            try:
                solve_response = drive_comment_set_solved(
                    doc_id,
                    comment_id,
                    is_solved=True,
                )
                action["solve_write_ack_sha256"] = _payload_sha256(solve_response)
                _save_comment_actions(
                    actions_path,
                    actions_value,
                    manifest_path=manifest_path,
                    manifest=manifest,
                    plan_path=plan_path,
                    plan=plan,
                    doc_id=doc_id,
                    published_revision_id=published_revision,
                )
            except LarkAdapterError as exc:
                raise save_failed_attempt(
                    f"评论 {comment_id} 的解决写入失败",
                    exc,
                ) from exc

    try:
        final_items = _read_comment_snapshot(doc_id)
    except (LarkAdapterError, ReviewError) as exc:
        raise save_failed_attempt("批量评论写入后的稳定回读失败", exc) from exc
    final_hash = _comment_fence_hash(final_items)
    final_by_id = _comment_index(final_items, label="批量评论最终围栏")
    for comment_id in ordered_ids:
        action = action_by_id[comment_id]
        current = final_by_id.get(comment_id)
        if current is None:
            raise save_failed_attempt(
                f"评论 {comment_id} 在最终围栏中缺失",
                ReviewError("评论可能被删除"),
            )
        if reply_only:
            _verify_action_comment(action, current, expect_solved=False)
            _record_replied_action(action, after_fence_sha256=final_hash)
        else:
            _verify_action_comment(action, current, expect_solved=True)
            _record_completed_action(
                action,
                current,
                after_fence_sha256=final_hash,
            )
    actions_value["current_fence_sha256"] = final_hash
    _verify_batch_comment_snapshot(
        manifest,
        plan,
        actions_value,
        final_items,
        require_all_completed=True,
        allow_reopen_states=False,
        allow_replied_pending_pm=reply_only,
    )
    _record_comment_performance(
        actions_value,
        before_scan_counters=scan_counters_before,
        started=batch_started,
        document_fetches=document_fetches,
        reply_writes=reply_writes,
        solve_writes=solve_writes,
    )
    _save_comment_actions(
        actions_path,
        actions_value,
        manifest_path=manifest_path,
        manifest=manifest,
        plan_path=plan_path,
        plan=plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
    )
    print(json.dumps({
        "status": "replied_pending_pm" if reply_only else "completed",
        "execution_mode": "reply_only" if reply_only else "batch",
        "batch_id": manifest.get("batch_id"),
        "doc_id": doc_id,
        "comment_ids": ordered_ids,
        "comment_count": len(ordered_ids),
        "receipt": str(actions_path),
        "performance": actions_value["performance"],
    }, ensure_ascii=False))
    return 0


def verify_comments(args: argparse.Namespace) -> int:
    """Verify PM-owned solve transitions after a controlled reply-only batch."""
    started = time.monotonic()
    scan_counters_before = _comment_scan_counters()
    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        args.manifest,
        args.plan,
        label="verify-comments",
    )
    if _int(plan.get("schema_version")) != PLAN_SCHEMA_VERSION:
        raise ReviewError("verify-comments 只接受 reply-only 生成的 v4 批次")
    context = _published_target_context(manifest, plan, label="verify-comments")
    doc_id = str(context["doc_id"])
    published_revision = int(context["published_revision_id"])
    actions_path, actions_value = _load_comment_actions(
        manifest_path,
        manifest,
        plan_path,
        plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
        required=True,
    )
    assert actions_value is not None
    if actions_value.get("execution_mode") != "reply_only":
        raise ReviewError("verify-comments 只接受受控 reply-only journal")

    _preflight()
    remote_document = _document(
        docs_fetch(doc_id, doc_format="markdown", detail="simple")
    )
    if (
        str(remote_document.get("document_id") or "") != doc_id
        or _int(remote_document.get("revision_id")) != published_revision
    ):
        raise ReviewError("verify-comments 前飞书 revision 与本地发布基线不一致")
    current_items = _read_comment_snapshot(doc_id)
    current_hash = _comment_fence_hash(current_items)
    current_by_id = _comment_index(current_items, label="PM 手工解决回读围栏")
    collected_by_id, decisions, _ = _batch_comment_contracts(manifest, plan)
    if set(current_by_id) != set(collected_by_id):
        raise ReviewError("PM 手工解决期间出现新增或删除评论，请重新 collect")

    solved_count = 0
    pending_count = 0
    for action in actions_value["actions"]:
        comment_id = str(action.get("comment_id") or "")
        if decisions.get(comment_id) not in COMPLETED_COMMENT_DECISIONS:
            raise ReviewError(f"评论 {comment_id} 不属于本批可完成范围")
        current = current_by_id.get(comment_id)
        if current is None:
            raise ReviewError(f"评论 {comment_id} 在 PM 手工解决回读中缺失")
        completion_status = str(action.get("completion_status") or "")
        if bool(current.get("is_solved")):
            if completion_status == "replied_pending_pm":
                _verify_action_comment(
                    action,
                    current,
                    expect_solved=True,
                    allow_external_solver=True,
                )
                _record_completed_action(
                    action,
                    current,
                    after_fence_sha256=current_hash,
                    completion_status="solved_by_pm_verified",
                )
            elif completion_status == "solved_by_pm_verified":
                _verify_action_comment(
                    action,
                    current,
                    expect_solved=True,
                    allow_external_solver=True,
                )
            else:
                raise ReviewError(f"评论 {comment_id} 缺少先前受控 reply-only 证据")
            solved_count += 1
        else:
            if completion_status != "replied_pending_pm":
                raise ReviewError(f"评论 {comment_id} 的 PM 解决状态发生回退")
            _verify_action_comment(action, current, expect_solved=False)
            pending_count += 1
        action["after_fence_sha256"] = current_hash

    actions_value["current_fence_sha256"] = current_hash
    _verify_batch_comment_snapshot(
        manifest,
        plan,
        actions_value,
        current_items,
        require_all_completed=True,
        allow_reopen_states=False,
        allow_replied_pending_pm=True,
    )
    _record_comment_performance(
        actions_value,
        before_scan_counters=scan_counters_before,
        started=started,
        document_fetches=1,
    )
    _save_comment_actions(
        actions_path,
        actions_value,
        manifest_path=manifest_path,
        manifest=manifest,
        plan_path=plan_path,
        plan=plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
    )
    print(json.dumps({
        "status": "verified" if pending_count == 0 else "waiting_for_pm",
        "batch_id": manifest.get("batch_id"),
        "solved_by_pm_verified": solved_count,
        "replied_pending_pm": pending_count,
        "receipt": str(actions_path),
    }, ensure_ascii=False))
    return 0


def _verify_batch_comment_snapshot(
    manifest: dict[str, Any],
    plan: dict[str, Any],
    actions_value: dict[str, Any] | None,
    current_items: list[dict[str, Any]],
    *,
    require_all_completed: bool,
    allow_reopen_states: bool,
    reopen_comment_ids: set[str] | None = None,
    allow_replied_pending_pm: bool = False,
) -> None:
    collected_by_id, decisions, _ = _batch_comment_contracts(manifest, plan)
    current_by_id = _comment_index(current_items, label="飞书当前全量评论围栏")
    if set(current_by_id) != set(collected_by_id):
        added = sorted(set(current_by_id) - set(collected_by_id))
        removed = sorted(set(collected_by_id) - set(current_by_id))
        raise ReviewError(
            "飞书全量评论围栏出现新增或删除："
            f"新增={added or '无'}，删除={removed or '无'}"
        )
    raw_actions = actions_value.get("actions") if isinstance(actions_value, dict) else []
    action_by_id = {
        str(action.get("comment_id") or ""): action
        for action in raw_actions
        if isinstance(action, dict)
    }
    for comment_id, collected in collected_by_id.items():
        current = current_by_id[comment_id]
        decision = decisions.get(comment_id)
        action = action_by_id.get(comment_id)
        if decision in COMPLETED_COMMENT_DECISIONS:
            if action is None:
                if require_all_completed:
                    raise ReviewError(f"评论 {comment_id} 缺少 completed 回执")
                if _comment_fence_view(current) != _comment_fence_view(collected):
                    raise ReviewError(f"未处理评论 {comment_id} 已在 collect 后变化")
                continue
            status = str(action.get("status") or "")
            if status == "completed":
                completion_status = str(action.get("completion_status") or "")
                if allow_reopen_states and comment_id in (reopen_comment_ids or set()):
                    _verify_reopen_action_comment(
                        action,
                        current,
                        expect_solved=True,
                    )
                else:
                    _verify_action_comment(
                        action,
                        current,
                        expect_solved=True,
                        allow_external_solver=completion_status == "solved_by_pm_verified",
                    )
            elif allow_replied_pending_pm and status == "replied_pending_pm":
                _verify_action_comment(action, current, expect_solved=False)
            elif allow_reopen_states and status == "reopen_requested":
                _verify_reopen_action_comment(
                    action,
                    current,
                    expect_solved=bool(current.get("is_solved")),
                )
            elif allow_reopen_states and status == "reopened":
                _verify_reopen_action_comment(action, current, expect_solved=False)
            else:
                raise ReviewError(
                    f"评论 {comment_id} 的回执状态 {status or 'missing'} 不能用于当前操作"
                )
        else:
            if action is not None:
                raise ReviewError(f"评论 {comment_id} 不应存在远端完成回执")
            if _comment_fence_view(current) != _comment_fence_view(collected):
                kind = "deferred" if decision == "deferred" else "批次外"
                raise ReviewError(f"{kind} 评论 {comment_id} 已在 collect 后变化")


def _render_pm_receipt(
    *,
    document_url: str,
    body_change_count: int,
    content_verified: bool,
    completed_comment_count: int,
    waiting_pm_comment_count: int,
    retained_comment_count: int,
    decision_write_count: int,
    implementation_result: str,
    implementation_label: str | None,
    incomplete_reason: str | None,
) -> str:
    implementation_names = {
        "prototype": "原型",
        "product": "产品",
        "prototype_and_product": "原型和产品",
    }
    label = implementation_names.get(str(implementation_label or ""))
    reason = str(incomplete_reason or "").strip()
    if implementation_result == "updated_verified":
        if label is None:
            raise ReviewError("实现已更新并验证时必须选择 --implementation-label")
        product_result = f"{label}已更新并验证"
    elif implementation_result == "no_change":
        if implementation_label or reason:
            raise ReviewError("无需改实现时不要填写实现对象或未完成原因")
        product_result = "本轮无需改实现"
    elif implementation_result == "incomplete":
        if not reason:
            raise ReviewError("实现尚未完成时必须填写 --incomplete-reason")
        product_result = f"尚未完成（{reason}）"
    else:
        raise ReviewError("--implementation-result 不受支持")

    local_updates: list[str] = []
    if body_change_count:
        local_updates.append("规格")
    if decision_write_count:
        local_updates.append("产品决定")
    if implementation_result == "updated_verified" and label is not None:
        local_updates.append(label)

    action_items: list[str] = []
    if waiting_pm_comment_count:
        action_items.append(
            f"请在飞书手工解决 {waiting_pm_comment_count} 条已回复评论，完成后回读核验"
        )
    if not content_verified:
        action_items.append("等待正文与格式回读验收")
    if retained_comment_count:
        action_items.append(f"有 {retained_comment_count} 条评论保留待后续处理")
    if implementation_result == "incomplete":
        action_items.append(reason)

    body_result = (
        f"已归入 {body_change_count} 处" if body_change_count else "无正文变化"
    )
    verification_result = "已核对通过" if content_verified else "未完成"
    local_result = "、".join(dict.fromkeys(local_updates)) if local_updates else "无"
    action_result = "；".join(dict.fromkeys(action_items)) if action_items else "无需处理"
    return "\n".join(
        [
            f"飞书评审已收回：{document_url}",
            f"正文：{body_result}",
            f"内容与格式：{verification_result}",
            (
                "评论："
                f"已完成 {completed_comment_count} 条，"
                f"等待你手工解决 {waiting_pm_comment_count} 条，"
                f"另保留 {retained_comment_count} 条未解决"
            ),
            f"本地更新：{local_result}",
            f"产品结果：{product_result}",
            f"需要你处理：{action_result}",
        ]
    )


def receipt(args: argparse.Namespace) -> int:
    """Render a PM-facing result from bound batch artifacts."""
    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        args.manifest,
        args.plan,
        label="receipt",
    )
    context = _published_target_context(manifest, plan, label="receipt")
    doc_id = str(context["doc_id"])
    published_revision = int(context["published_revision_id"])
    _, decisions, _ = _batch_comment_contracts(manifest, plan)
    completed_targets = {
        comment_id
        for comment_id, decision in decisions.items()
        if decision in COMPLETED_COMMENT_DECISIONS
    }
    deferred_targets = {
        comment_id for comment_id, decision in decisions.items() if decision == "deferred"
    }
    _, actions_value = _load_comment_actions(
        manifest_path,
        manifest,
        plan_path,
        plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
        required=False,
    )
    actions = actions_value.get("actions") if isinstance(actions_value, dict) else []
    if not isinstance(actions, list):
        raise ReviewError("comment-actions.json actions 必须是数组")
    completed_ids = {
        str(item.get("comment_id") or "")
        for item in actions
        if isinstance(item, dict)
        and item.get("status") == "completed"
        and item.get("completion_status")
        in {"solved_by_pmai", "solved_by_pm_verified"}
    }
    waiting_pm_ids = {
        str(item.get("comment_id") or "")
        for item in actions
        if isinstance(item, dict)
        and item.get("completion_status") == "replied_pending_pm"
    }
    retained_ids = deferred_targets | (
        completed_targets - completed_ids - waiting_pm_ids
    )
    try:
        _remote_verification_artifact(
            manifest_path,
            manifest,
            plan,
            doc_id=doc_id,
            published_revision=published_revision,
            expected_projection_sha256=_markdown_verification_sha256(
                str(context["body"])
            ),
        )
        content_verified = True
    except ReviewError:
        content_verified = False

    required = plan.get("required_items")
    body_items = required.get("body") if isinstance(required, dict) else None
    if not isinstance(body_items, list):
        raise ReviewError("apply-plan.json 缺少正文处置项")
    document = manifest.get("document")
    document_url = (
        str(document.get("doc_url") or "") if isinstance(document, dict) else ""
    )
    if not document_url:
        raise ReviewError("review.json 缺少飞书文档地址")
    print(
        _render_pm_receipt(
            document_url=document_url,
            body_change_count=len(body_items),
            content_verified=content_verified,
            completed_comment_count=len(completed_ids),
            waiting_pm_comment_count=len(waiting_pm_ids),
            retained_comment_count=len(retained_ids),
            decision_write_count=int(plan.get("decision_write_count") or 0),
            implementation_result=str(args.implementation_result or ""),
            implementation_label=args.implementation_label,
            incomplete_reason=args.incomplete_reason,
        )
    )
    return 0


def reopen(args: argparse.Namespace) -> int:
    """在 checkpoint 失败后，受批次约束地重开本次系统已解决的评论。"""
    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        args.manifest,
        args.plan,
        label="reopen",
    )
    context = _published_target_context(manifest, plan, label="reopen")
    markdown_path = Path(context["markdown_path"])
    requested_markdown = _canonical_regular_file(
        Path(args.markdown),
        label="reopen 目标 markdown",
    )
    if requested_markdown != markdown_path:
        raise ReviewError("review.json 与 reopen 目标 markdown 不匹配")
    requested_ids = [str(value or "").strip() for value in args.comment_id]
    if any(not value for value in requested_ids):
        raise ReviewError("--comment-id 不能为空")
    if len(set(requested_ids)) != len(requested_ids):
        raise ReviewError("--comment-id 不能重复")
    doc_id = str(context["doc_id"])
    published_revision = int(context["published_revision_id"])
    _preflight()
    remote_document = _document(
        docs_fetch(doc_id, doc_format="markdown", detail="simple")
    )
    remote_fence = (
        str(remote_document.get("document_id") or ""),
        _int(remote_document.get("revision_id")),
        str(remote_document.get("content") or ""),
    )
    if remote_fence[0] != doc_id or remote_fence[1] != published_revision:
        raise ReviewError("reopen 前飞书当前 revision 与本地发布基线不一致")
    actions_path, actions_value = _load_comment_actions(
        manifest_path,
        manifest,
        plan_path,
        plan,
        doc_id=doc_id,
        published_revision_id=published_revision,
        required=True,
    )
    assert actions_value is not None
    action_by_id = {
        str(action.get("comment_id") or ""): action
        for action in actions_value["actions"]
        if isinstance(action, dict)
    }
    current_comments = _read_comment_snapshot(doc_id)
    current_hash = _comment_fence_hash(current_comments)
    current_by_id = _comment_index(current_comments, label="reopen 当前评论围栏")
    unknown = [
        comment_id
        for comment_id in requested_ids
        if comment_id not in action_by_id
        or action_by_id[comment_id].get("status")
        not in {"solve_requested", "completed", "reopen_requested"}
        or (
            action_by_id[comment_id].get("status") in {"completed", "reopen_requested"}
            and action_by_id[comment_id].get("completion_status") != "solved_by_pmai"
        )
    ]
    if unknown:
        raise ReviewError(
            "reopen 只接受本批可证明的 solve_requested 或 completed 回执: "
            + ", ".join(sorted(unknown))
        )

    recovered_solve_ids: list[str] = []
    for comment_id, action in action_by_id.items():
        if action.get("status") != "solve_requested":
            continue
        current = current_by_id.get(comment_id)
        if current is None:
            raise ReviewError(f"评论 {comment_id} 在 solve_requested 恢复时无法回读")
        _recover_solve_requested_for_reopen(
            action,
            current,
            current_fence_sha256=current_hash,
            allow_new_replies=comment_id in requested_ids,
        )
        recovered_solve_ids.append(comment_id)
    if recovered_solve_ids:
        actions_value["current_fence_sha256"] = current_hash
        _save_comment_actions(
            actions_path,
            actions_value,
            manifest_path=manifest_path,
            manifest=manifest,
            plan_path=plan_path,
            plan=plan,
            doc_id=doc_id,
            published_revision_id=published_revision,
        )
    _verify_batch_comment_snapshot(
        manifest,
        plan,
        actions_value,
        current_comments,
        require_all_completed=False,
        allow_reopen_states=True,
        reopen_comment_ids=set(requested_ids),
    )
    raw = str(context["raw"])
    if _read_regular_text(markdown_path, label="reopen 目标") != raw:
        raise ReviewError("本地规格在 reopen 写入前变化")

    reopened: list[str] = []
    for comment_id in requested_ids:
        action = action_by_id[comment_id]
        current_hash = _comment_fence_hash(current_comments)
        current_by_id = _comment_index(current_comments, label="reopen 当前评论围栏")
        current = current_by_id[comment_id]
        if action.get("status") == "completed":
            _verify_reopen_action_comment(action, current, expect_solved=True)
            action["status"] = "reopen_requested"
            actions_value["current_fence_sha256"] = current_hash
            _save_comment_actions(
                actions_path,
                actions_value,
                manifest_path=manifest_path,
                manifest=manifest,
                plan_path=plan_path,
                plan=plan,
                doc_id=doc_id,
                published_revision_id=published_revision,
            )
        elif bool(current.get("is_solved")):
            _verify_reopen_action_comment(action, current, expect_solved=True)
        else:
            _verify_reopen_action_comment(action, current, expect_solved=False)
            action["status"] = "reopened"
            action["reopened_fence_sha256"] = current_hash
            actions_value["current_fence_sha256"] = current_hash
            _save_comment_actions(
                actions_path,
                actions_value,
                manifest_path=manifest_path,
                manifest=manifest,
                plan_path=plan_path,
                plan=plan,
                doc_id=doc_id,
                published_revision_id=published_revision,
            )
            reopened.append(comment_id)
            continue
        try:
            drive_comment_set_solved(doc_id, comment_id, is_solved=False)
        except LarkAdapterError as exc:
            raise ReviewError(
                f"评论 {comment_id} reopen 写入未完成；已保留 reopen_requested，"
                f"重跑 reopen 恢复。详情: {exc}"
            ) from exc
        try:
            current_comments = _read_comment_snapshot(doc_id)
        except (LarkAdapterError, ReviewError) as exc:
            raise ReviewError(
                f"评论 {comment_id} reopen 后回读失败；已保留 reopen_requested，"
                f"重跑 reopen 恢复。详情: {exc}"
            ) from exc
        _verify_batch_comment_snapshot(
            manifest,
            plan,
            actions_value,
            current_comments,
            require_all_completed=False,
            allow_reopen_states=True,
            reopen_comment_ids=set(requested_ids),
        )
        current_hash = _comment_fence_hash(current_comments)
        current = _comment_index(
            current_comments,
            label="reopen 最终评论围栏",
        )[comment_id]
        if bool(current.get("is_solved")):
            raise ReviewError(
                f"评论 {comment_id} reopen 后仍是已解决状态；回执保持 reopen_requested"
            )
        action["status"] = "reopened"
        action["reopened_fence_sha256"] = current_hash
        actions_value["current_fence_sha256"] = current_hash
        _save_comment_actions(
            actions_path,
            actions_value,
            manifest_path=manifest_path,
            manifest=manifest,
            plan_path=plan_path,
            plan=plan,
            doc_id=doc_id,
            published_revision_id=published_revision,
        )
        reopened.append(comment_id)

    final_remote_document = _document(
        docs_fetch(doc_id, doc_format="markdown", detail="simple")
    )
    final_remote_fence = (
        str(final_remote_document.get("document_id") or ""),
        _int(final_remote_document.get("revision_id")),
        str(final_remote_document.get("content") or ""),
    )
    if final_remote_fence != remote_fence:
        raise ReviewError("飞书正文在 reopen 期间变化；已执行的 reopen 保留，请重新 collect")
    if _read_regular_text(markdown_path, label="reopen 目标") != raw:
        raise ReviewError("本地规格在 reopen 期间变化；已执行的 reopen 保留，请重新 collect")

    print(json.dumps({
        "status": "reopened",
        "batch_id": plan.get("batch_id"),
        "doc_id": doc_id,
        "comment_ids": reopened,
        "receipt": str(actions_path),
    }, ensure_ascii=False))
    return 0


def _checkpoint_handoff_closures(
    raw_bundle_paths: list[str] | None,
    *,
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
    markdown_path: Path,
    doc_id: str,
    published_revision: int,
) -> list[tuple[Path, dict[str, Any], dict[str, Any]]]:
    if not raw_bundle_paths:
        return []
    main_root = _verified_main_repository_root(_repository_root(markdown_path))
    try:
        markdown_relative = markdown_path.relative_to(main_root).as_posix()
    except ValueError as exc:
        raise ReviewError("fresh checkpoint markdown 不在 main 仓根内") from exc
    current_batch_id = str(manifest.get("batch_id") or "")
    expected_closure = {
        "batch_id": current_batch_id,
        "review_sha256": _file_digest(manifest_path),
        "plan_sha256": _file_digest(plan_path),
        "doc_id": doc_id,
        "published_revision_id": published_revision,
        "markdown_relative": markdown_relative,
    }
    closures: list[tuple[Path, dict[str, Any], dict[str, Any]]] = []
    seen: set[Path] = set()
    for raw in raw_bundle_paths:
        bundle_path, bundle = _load_handoff_bundle(Path(raw))
        if bundle_path in seen:
            raise ReviewError("--closes-handoff 不能重复指定同一 bundle")
        seen.add(bundle_path)
        bundle_main_root = _verified_main_repository_root(bundle_path.parents[3])
        source_document = bundle.get("document")
        source_revision = _int(
            source_document.get("current_revision_id")
            if isinstance(source_document, dict)
            else None
        )
        if (
            bundle_main_root != main_root
            or bundle.get("batch_id") == current_batch_id
            or bundle.get("markdown_relative") != markdown_relative
            or not isinstance(source_document, dict)
            or source_document.get("doc_id") != doc_id
            or (source_revision is not None and published_revision < source_revision)
        ):
            raise ReviewError("fresh checkpoint 与待关闭 handoff bundle 的仓、模块或飞书文档不匹配")
        if bundle.get("state") == "pending" and bundle.get("phase") != "lark_review":
            raise ReviewError(
                "handoff bundle 尚未推进到 lark_review；必须先完成 Proposal/design 阶段证据"
            )
        if bundle.get("state") == "closed" and bundle.get("closure") != expected_closure:
            raise ReviewError("handoff bundle 已由另一 fresh batch 收口")
        closures.append((bundle_path, bundle, expected_closure))
    return closures


def _close_handoff_bundles(
    closures: list[tuple[Path, dict[str, Any], dict[str, Any]]],
    *,
    reviewed_at: str,
) -> None:
    for bundle_path, bundle, expected_closure in closures:
        if bundle.get("state") == "closed":
            continue
        updated = dict(bundle)
        updated["state"] = "closed"
        updated["phase"] = "closed"
        updated["closed_at"] = reviewed_at
        updated["closure"] = expected_closure
        updated["phase_history"] = [
            *bundle["phase_history"],
            {
                "from": "lark_review",
                "to": "closed",
                "advanced_at": reviewed_at,
                "evidence": {"kind": "fresh_checkpoint", **expected_closure},
            },
        ]
        _write_json(bundle_path, updated)
        _, verified = _load_handoff_bundle(bundle_path)
        if verified.get("state") != "closed" or verified.get("closure") != expected_closure:
            raise ReviewError("handoff bundle 收口回读不一致")


def _write_checkpoint_receipt(
    *,
    manifest_path: Path,
    manifest: dict[str, Any],
    plan_path: Path,
    plan: dict[str, Any],
    markdown_path: Path,
    doc_id: str,
    published_revision: int,
    reviewed_at: str,
) -> Path:
    receipt_path = _checkpoint_receipt_path(manifest_path)
    value = {
        "kind": CHECKPOINT_KIND,
        "schema_version": CHECKPOINT_SCHEMA_VERSION,
        "batch_id": manifest.get("batch_id"),
        "review_sha256": _file_digest(manifest_path),
        "plan_sha256": _file_digest(plan_path),
        "markdown_path": str(markdown_path),
        "document": {
            "doc_id": doc_id,
            "published_revision_id": published_revision,
        },
        "reviewed_at": reviewed_at,
    }
    if _entry_exists(receipt_path, label="checkpoint.json"):
        existing = _load_checkpoint_receipt(manifest_path, manifest, plan_path, plan)
        if existing != value:
            raise ReviewError("当前批次已有另一份 checkpoint 收据")
        return _canonical_regular_file(receipt_path, label="checkpoint.json")
    _write_json(receipt_path, value)
    verified = _load_checkpoint_receipt(manifest_path, manifest, plan_path, plan)
    if verified != value:
        raise ReviewError("checkpoint.json 写入后回读不一致")
    return _canonical_regular_file(receipt_path, label="checkpoint.json")


def checkpoint(args: argparse.Namespace) -> int:
    checkpoint_started = time.monotonic()
    checkpoint_scan_counters = _comment_scan_counters()
    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        args.manifest,
        args.plan,
        label="checkpoint",
    )
    context = _published_target_context(manifest, plan, label="checkpoint")
    markdown_path = Path(context["markdown_path"])
    markdown_input = _canonical_regular_file(
        Path(args.markdown),
        label="checkpoint 目标 markdown",
    )
    if markdown_input != markdown_path:
        raise ReviewError("review.json 与 checkpoint 目标 markdown 不匹配")
    raw = str(context["raw"])
    frontmatter = context["frontmatter"]
    body = str(context["body"])
    manifest_doc_id = str(context["doc_id"])
    published_revision = int(context["published_revision_id"])
    handoff_closures = _checkpoint_handoff_closures(
        args.closes_handoff,
        manifest_path=manifest_path,
        manifest=manifest,
        plan_path=plan_path,
        plan=plan,
        markdown_path=markdown_path,
        doc_id=manifest_doc_id,
        published_revision=published_revision,
    )
    _, decisions, _ = _batch_comment_contracts(manifest, plan)
    completed_comment_ids = {
        comment_id
        for comment_id, decision in decisions.items()
        if decision in COMPLETED_COMMENT_DECISIONS
    }
    actions_path, actions_value = _load_comment_actions(
        manifest_path,
        manifest,
        plan_path,
        plan,
        doc_id=manifest_doc_id,
        published_revision_id=published_revision,
        required=bool(completed_comment_ids),
    )
    if actions_value is not None:
        action_by_id = {
            str(action.get("comment_id") or ""): action
            for action in actions_value["actions"]
            if isinstance(action, dict)
        }
        if set(action_by_id) != completed_comment_ids:
            missing = sorted(completed_comment_ids - set(action_by_id))
            extra = sorted(set(action_by_id) - completed_comment_ids)
            raise ReviewError(
                "comment-actions.json 未完整覆盖本批非 deferred 评论："
                f"缺少={missing or '无'}，多余={extra or '无'}"
            )
        initial_fence = str(actions_value.get("initial_fence_sha256") or "")
        current_receipt_fence = str(actions_value.get("current_fence_sha256") or "")
        execution_mode = str(actions_value.get("execution_mode") or "")
        if execution_mode in {"batch", "reply_only"}:
            for action in actions_value["actions"]:
                if action.get("status") != "completed":
                    raise ReviewError(
                        f"评论 {action.get('comment_id')} 缺少 completed 回执"
                    )
                if action.get("before_fence_sha256") != initial_fence:
                    raise ReviewError("批量评论回执没有绑定统一初始围栏")
                if action.get("after_fence_sha256") != current_receipt_fence:
                    raise ReviewError("批量评论回执没有绑定统一最终围栏")
                expected_completion = (
                    "solved_by_pm_verified" if execution_mode == "reply_only" else "solved_by_pmai"
                )
                if action.get("completion_status") != expected_completion:
                    raise ReviewError("评论尚未形成当前完成模式要求的远端证据")
        else:
            expected_fence = initial_fence
            for action in actions_value["actions"]:
                if action.get("status") != "completed":
                    raise ReviewError(
                        f"评论 {action.get('comment_id')} 缺少 completed 回执"
                    )
                if action.get("before_fence_sha256") != expected_fence:
                    raise ReviewError("comment-actions.json 的操作前后围栏链不连续")
                expected_fence = str(action.get("after_fence_sha256") or "")
            if expected_fence != current_receipt_fence:
                raise ReviewError("comment-actions.json 的最终围栏水位不一致")
    elif completed_comment_ids:
        raise ReviewError("本批非 deferred 评论缺少 comment-actions.json 完成回执")

    _preflight()
    if _int(manifest.get("schema_version")) == SCHEMA_VERSION:
        verification = _remote_verification_artifact(
            manifest_path,
            manifest,
            plan,
            doc_id=manifest_doc_id,
            published_revision=published_revision,
            expected_projection_sha256=_markdown_verification_sha256(body),
        )
        expected_remote_hash = str(verification["remote_markdown_projection_sha256"])
        checkpoint_document_fetches = 1
    else:
        initial_remote_document = _document(
            docs_fetch(manifest_doc_id, doc_format="markdown", detail="simple")
        )
        if (
            str(initial_remote_document.get("document_id") or "") != manifest_doc_id
            or _int(initial_remote_document.get("revision_id")) != published_revision
        ):
            raise ReviewError("checkpoint 前飞书当前 revision 与本地发布基线不一致")
        expected_remote_hash = _markdown_verification_sha256(
            str(initial_remote_document.get("content") or "")
        )
        checkpoint_document_fetches = 2

    current_comments = _read_comment_snapshot(manifest_doc_id)
    current_fence_hash = _comment_fence_hash(current_comments)
    if actions_value is not None:
        if current_fence_hash != str(actions_value.get("current_fence_sha256") or ""):
            raise ReviewError("checkpoint 前远端评论围栏与完成回执不一致")
    else:
        manifest_comments = manifest.get("comments")
        if current_fence_hash != str(
            manifest_comments.get("fence_sha256")
            if isinstance(manifest_comments, dict)
            else ""
        ):
            raise ReviewError("checkpoint 前远端评论围栏已变化")
    _verify_batch_comment_snapshot(
        manifest,
        plan,
        actions_value,
        current_comments,
        require_all_completed=True,
        allow_reopen_states=False,
    )
    comment_time, final_comment_ids = _comment_cursor_from_snapshot(current_comments)
    final_remote_document = _document(
        docs_fetch(manifest_doc_id, doc_format="markdown", detail="simple")
    )
    final_remote_fence = (
        str(final_remote_document.get("document_id") or ""),
        _int(final_remote_document.get("revision_id")),
        _markdown_verification_sha256(str(final_remote_document.get("content") or "")),
    )
    if final_remote_fence[:2] != (manifest_doc_id, published_revision):
        raise ReviewError("checkpoint 前飞书当前 revision 与本地发布基线不一致")
    if final_remote_fence[2] != expected_remote_hash:
        raise ReviewError("飞书正文在 checkpoint 复核期间变化")
    revision = published_revision
    comment_ids = set(final_comment_ids)
    if _read_regular_text(markdown_path, label="checkpoint 目标") != raw:
        raise ReviewError("本地规格在 checkpoint 复核期间变化")
    previous_revision = _int(frontmatter.get("lark_reviewed_revision_id"))
    previous_comment_time = _int(frontmatter.get("lark_reviewed_comment_at"))
    previous_comment_ids = _checkpoint_ids(frontmatter.get("lark_reviewed_comment_ids"))
    if previous_revision is not None and revision < previous_revision:
        raise ReviewError("最终发布 revision 早于现有 checkpoint，拒绝回退")
    if previous_comment_time is not None and comment_time < previous_comment_time:
        raise ReviewError("最终评论时间早于现有 checkpoint，拒绝回退")
    if previous_comment_time == comment_time:
        comment_ids.update(previous_comment_ids)
    reviewed_at = args.reviewed_at or datetime.now().astimezone().isoformat(timespec="seconds")
    updated: dict[str, object] = dict(frontmatter)
    updated["lark_reviewed_revision_id"] = revision
    updated["lark_reviewed_comment_at"] = comment_time
    updated["lark_reviewed_comment_ids"] = json.dumps(
        sorted(comment_ids), ensure_ascii=False, separators=(",", ":")
    )
    updated["lark_reviewed_at"] = reviewed_at
    write_frontmatter(
        markdown_path,
        updated,
        body,
        expected_text=raw,
        require_canonical_path=True,
    )
    _close_handoff_bundles(handoff_closures, reviewed_at=reviewed_at)
    checkpoint_receipt = _write_checkpoint_receipt(
        manifest_path=manifest_path,
        manifest=manifest,
        plan_path=plan_path,
        plan=plan,
        markdown_path=markdown_path,
        doc_id=manifest_doc_id,
        published_revision=revision,
        reviewed_at=reviewed_at,
    )
    print(json.dumps({
        "markdown_path": str(markdown_path),
        "lark_reviewed_revision_id": revision,
        "lark_reviewed_comment_at": comment_time,
        "lark_reviewed_comment_ids": sorted(comment_ids),
        "lark_reviewed_at": reviewed_at,
        "checkpoint": str(checkpoint_receipt),
        "comment_actions": str(actions_path) if actions_value is not None else None,
        "closed_handoffs": [str(item[0]) for item in handoff_closures],
        "performance": {
            "elapsed_seconds": round(time.monotonic() - checkpoint_started, 6),
            "document_fetch_api_calls": checkpoint_document_fetches,
            **{
                key: value - checkpoint_scan_counters[key]
                for key, value in _comment_scan_counters().items()
            },
        },
    }, ensure_ascii=False))
    return 0


def baseline(args: argparse.Namespace) -> int:
    markdown_path = _canonical_regular_file(
        Path(args.markdown),
        label="baseline 目标 markdown",
    )
    revision = _int(args.revision_id)
    if revision is None or revision < 0:
        raise ReviewError("baseline 需要非负 revision-id")
    raw = _read_regular_text(markdown_path, label="baseline 目标 markdown")
    frontmatter, body = parse_frontmatter(raw)
    source_hash = _body_hash(body)
    if source_hash != str(args.expected_source_hash or ""):
        raise ReviewError("baseline 目标正文与同步时 source hash 不一致，拒绝建立错配基线")
    frontmatter_doc_id = str(frontmatter.get("lark_doc_id") or "")
    frontmatter_url_id = _docx_token(frontmatter.get("lark_doc_url"))
    if frontmatter.get("lark_doc_url") and frontmatter_url_id is None:
        raise ReviewError("baseline 目标的 lark_doc_url 不是受支持的 Docx 链接")
    document_ids = {value for value in (frontmatter_doc_id, frontmatter_url_id) if value}
    if len(document_ids) != 1:
        raise ReviewError("baseline 目标缺少唯一的 Docx 身份，或 id 与 URL 互相冲突")
    previous_revision = _int(frontmatter.get("lark_published_revision_id"))
    if previous_revision is not None and revision < previous_revision:
        raise ReviewError("baseline revision 早于现有发布基线，拒绝回退")
    doc_id = next(iter(document_ids))
    _preflight()
    current_document = _document(
        docs_fetch(doc_id, doc_format="markdown", detail="simple")
    )
    current_doc_id = str(current_document.get("document_id") or "")
    current_revision = _int(current_document.get("revision_id"))
    if current_doc_id != doc_id or current_revision != revision:
        raise ReviewError(
            "baseline 回读与预期飞书版本不一致："
            f"期望 {doc_id}@{revision}，实际 {current_doc_id or 'unknown'}@{current_revision}"
        )
    updated: dict[str, object] = dict(frontmatter)
    updated["lark_doc_id"] = doc_id
    updated["lark_published_revision_id"] = revision
    updated["lark_published_source_hash"] = source_hash
    write_frontmatter(
        markdown_path,
        updated,
        body,
        expected_text=raw,
        require_canonical_path=True,
    )
    print(json.dumps({
        "markdown_path": str(markdown_path),
        "lark_published_revision_id": revision,
        "lark_published_source_hash": source_hash,
    }, ensure_ascii=False))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="lark-review",
        description="收集、归位并受控应用飞书评审，或在验证完成后记录 checkpoint",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    target_parser = subparsers.add_parser(
        "resolve-target",
        help="把本地 markdown 绑定到同模块 active build 的权威 worktree 副本",
    )
    target_parser.add_argument("markdown", help="已唯一定位的本地 markdown")
    target_parser.set_defaults(handler=resolve_target)

    resumable_parser = subparsers.add_parser(
        "find-resumable",
        help="只读查找同一 markdown 的唯一可恢复批次，并跳过只读 handoff",
    )
    resumable_parser.add_argument("markdown", help="待恢复评审对应的本地 markdown")
    resumable_parser.add_argument(
        "--review-root",
        required=True,
        help="当前仓 .pm-workflow/context/lark-review 目录",
    )
    resumable_parser.set_defaults(handler=find_resumable)

    resumable_list_parser = subparsers.add_parser(
        "list-resumables",
        help="只读列出 main 与 attached worktrees 中全部未完成评审批次",
    )
    resumable_list_parser.add_argument("main_root", help="唯一 main/master worktree 根目录")
    resumable_list_parser.set_defaults(handler=list_resumables)

    handoff_list_parser = subparsers.add_parser(
        "list-handoffs",
        help="只读列出 main 中待 Proposal/design 消费的持久评审 handoff bundle",
    )
    handoff_list_parser.add_argument("main_root", help="唯一 main/master worktree 根目录")
    handoff_list_parser.add_argument(
        "--route", choices=tuple(sorted(HANDOFF_ROUTES)), help="只返回指定上游路由"
    )
    handoff_list_parser.add_argument(
        "--phase", choices=tuple(sorted(HANDOFF_PHASES)), help="只返回指定当前阶段"
    )
    handoff_list_parser.add_argument("--module", help="只返回 docs/modules/<模块> 的交接")
    handoff_list_parser.add_argument("--doc-id", help="只返回同一飞书 Docx 文档的交接")
    handoff_list_parser.add_argument(
        "--include-closed", action="store_true", help="同时返回已由 fresh batch checkpoint 收口的交接"
    )
    handoff_list_parser.set_defaults(handler=list_handoffs)

    handoff_advance_parser = subparsers.add_parser(
        "advance-handoff",
        help="凭 Proposal 或权威规格提交证据顺序推进 handoff 阶段",
    )
    handoff_advance_parser.add_argument("bundle", help="main 中的 handoff bundle.json")
    handoff_advance_parser.add_argument(
        "--to",
        required=True,
        choices=("design", "lark-review"),
        help="下一个阶段；closed 只能由 fresh checkpoint 完成",
    )
    handoff_advance_parser.add_argument(
        "--evidence-commit",
        help="推进到 lark-review 时绑定的完整权威规格 commit SHA",
    )
    handoff_advance_parser.set_defaults(handler=advance_handoff)

    collect_parser = subparsers.add_parser("collect", help="只读收集评审增量")
    collect_parser.add_argument("markdown", help="已发布的本地 markdown")
    collect_parser.add_argument("--doc", help="飞书 URL 或 token；默认读 frontmatter")
    collect_parser.add_argument("--output-dir", required=True, help="临时评审产物目录")
    collect_parser.add_argument(
        "--include-solved",
        action="store_true",
        help="同时包含已解决评论；默认只取未解决评论",
    )
    collect_parser.set_defaults(handler=collect)

    reconcile_parser = subparsers.add_parser(
        "reconcile",
        help="生成目标正文与归位账本，或校验后 seal apply plan",
    )
    reconcile_parser.add_argument("--manifest", required=True, help="collect 生成的 review.json")
    reconcile_parser.add_argument(
        "--resolutions",
        help="本批次 resolutions.json；只在 --seal 时使用",
    )
    reconcile_parser.add_argument(
        "--seal",
        action="store_true",
        help="校验 target/resolutions 无待决项并生成 ready plan",
    )
    reconcile_parser.set_defaults(handler=reconcile)

    handoff_parser = subparsers.add_parser(
        "handoff",
        help="把上游重规划的 draft 批次固化为不可 seal/apply 的只读证据",
    )
    handoff_parser.add_argument("--manifest", required=True, help="旧批次 review.json")
    handoff_parser.add_argument(
        "--route",
        required=True,
        choices=tuple(sorted(HANDOFF_ROUTES)),
        help="replan 的上游路由",
    )
    handoff_parser.add_argument(
        "--candidate-manifest",
        help=(
            "active build 经 replan-work.py 返回的精确 candidate manifest；"
            "无 active build 的 proposal handoff 省略"
        ),
    )
    handoff_parser.set_defaults(handler=handoff)

    apply_parser = subparsers.add_parser("apply", help="按 ready plan 原子写入目标正文")
    apply_parser.add_argument("markdown", help="必须与批次绑定一致的本地 markdown")
    apply_parser.add_argument("--plan", required=True, help="seal 生成的 apply-plan.json")
    apply_parser.set_defaults(handler=apply_target)

    verify_parser = subparsers.add_parser(
        "verify-sync",
        help="精细同步后验证飞书正文投影、原生格式和资源保真",
    )
    verify_parser.add_argument("--manifest", required=True, help="collect 生成的 review.json")
    verify_parser.add_argument("--plan", required=True, help="已应用的 ready apply-plan.json")
    verify_parser.set_defaults(handler=verify_sync)

    approval_parser = subparsers.add_parser(
        "validate-approval",
        help="只读验证 build accepted-delta 消费的完整评审批次证据",
    )
    approval_parser.add_argument(
        "--artifact", required=True, help="verify-sync 生成的 remote-verification.json"
    )
    approval_parser.add_argument("--repo-root", required=True, help="当前 PMAI 仓根")
    approval_parser.add_argument("--markdown", required=True, help="当前模块 spec.md")
    approval_parser.add_argument("--batch-id", required=True, help="sealed review batch ID")
    approval_parser.set_defaults(handler=validate_approval)

    complete_parser = subparsers.add_parser(
        "complete-comment",
        help="为本批已验证评论创建结果回复并解决，或对全文评论直接解决",
    )
    complete_parser.add_argument("--manifest", required=True, help="collect 生成的 review.json")
    complete_parser.add_argument("--plan", required=True, help="已应用的 ready apply-plan.json")
    complete_parser.add_argument("--comment-id", required=True, help="本批非 deferred comment ID")
    complete_parser.add_argument(
        "--result-text",
        help="结果回复正文；局部评论必填，全文评论可省略并直接解决",
    )
    complete_parser.set_defaults(handler=complete_comment)

    complete_batch_parser = subparsers.add_parser(
        "complete-comments",
        help="按 ready plan 整批回复并解决评论，只在批次首尾读取稳定围栏",
    )
    complete_batch_parser.add_argument(
        "--manifest", required=True, help="collect 生成的 review.json"
    )
    complete_batch_parser.add_argument(
        "--plan", required=True, help="已应用的 ready apply-plan.json"
    )
    complete_batch_parser.add_argument(
        "--reply-only",
        action="store_true",
        help="只创建受控结果回复，等待 PM 核验后手工解决",
    )
    complete_batch_parser.set_defaults(handler=complete_comments)

    verify_comments_parser = subparsers.add_parser(
        "verify-comments",
        help="回读并核验 PM 在受控 reply-only 之后手工解决的评论",
    )
    verify_comments_parser.add_argument(
        "--manifest", required=True, help="collect 生成的 review.json"
    )
    verify_comments_parser.add_argument(
        "--plan", required=True, help="已应用的 ready apply-plan.json"
    )
    verify_comments_parser.set_defaults(handler=verify_comments)

    receipt_parser = subparsers.add_parser(
        "receipt",
        help="从受控批次产物生成只含业务结果的 PM 回执",
    )
    receipt_parser.add_argument(
        "--manifest", required=True, help="collect 生成的 review.json"
    )
    receipt_parser.add_argument(
        "--plan", required=True, help="已应用的 ready apply-plan.json"
    )
    receipt_parser.add_argument(
        "--implementation-result",
        required=True,
        choices=("updated_verified", "no_change", "incomplete"),
        help="受影响原型或产品的业务验收结果",
    )
    receipt_parser.add_argument(
        "--implementation-label",
        choices=("prototype", "product", "prototype_and_product"),
        help="实现已更新时对应的业务产物",
    )
    receipt_parser.add_argument(
        "--incomplete-reason",
        help="实现尚未完成时面向 PM 的业务原因",
    )
    receipt_parser.set_defaults(handler=receipt)

    reopen_parser = subparsers.add_parser(
        "reopen",
        help="checkpoint 失败后，受批次约束地重开本次系统已解决的评论",
    )
    reopen_parser.add_argument("markdown", help="必须仍是本批目标 T 的本地 markdown")
    reopen_parser.add_argument("--manifest", required=True, help="collect 生成的 review.json")
    reopen_parser.add_argument("--plan", required=True, help="已应用的 ready apply-plan.json")
    reopen_parser.add_argument(
        "--comment-id",
        action="append",
        required=True,
        help="本次系统已解决、需要恢复为未解决的本批 comment ID；可重复",
    )
    reopen_parser.set_defaults(handler=reopen)

    checkpoint_parser = subparsers.add_parser("checkpoint", help="记录已验证完成的评审批次")
    checkpoint_parser.add_argument("markdown", help="本地 markdown")
    checkpoint_parser.add_argument("--manifest", required=True, help="collect 生成的 review.json")
    checkpoint_parser.add_argument("--plan", required=True, help="已应用的 ready apply-plan.json")
    checkpoint_parser.add_argument("--reviewed-at", help="覆盖 checkpoint 时间，供测试或恢复使用")
    checkpoint_parser.add_argument(
        "--closes-handoff",
        action="append",
        default=[],
        help="本次 fresh batch 成功 checkpoint 后关闭的 main handoff bundle.json；可重复",
    )
    checkpoint_parser.set_defaults(handler=checkpoint)

    baseline_parser = subparsers.add_parser("baseline", help="同步成功后刷新正文/revision 基线")
    baseline_parser.add_argument("markdown", help="本地 markdown")
    baseline_parser.add_argument("--revision-id", required=True, help="回读确认后的飞书 revision")
    baseline_parser.add_argument(
        "--expected-source-hash",
        required=True,
        help="本次同步正文的规范化 SHA-256；用于拒绝本地并发变化",
    )
    baseline_parser.set_defaults(handler=baseline)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.handler(args))
    except (LarkAdapterError, ReviewError, OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
