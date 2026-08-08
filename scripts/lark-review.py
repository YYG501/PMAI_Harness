#!/usr/bin/env python3
"""收集飞书规格评审增量，并在整批完成后记录本地 checkpoint。"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
import re
import sys
import tempfile
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
from _lib.lark_review_semantics import (  # noqa: E402
    NATIVE_SNAPSHOT_KIND,
    NATIVE_SNAPSHOT_SCHEMA_VERSION,
    REMOTE_COVERAGE_KIND,
    REMOTE_COVERAGE_SCHEMA_VERSION,
    build_native_snapshot,
    build_remote_coverage,
    markdown_semantic_units,
    render_remote_preview,
)


SCHEMA_VERSION = 3
PLAN_SCHEMA_VERSION = 3
RESOLUTION_SCHEMA_VERSION = 3
COMMENT_ACTIONS_SCHEMA_VERSION = 2
LEGACY_REVIEW_SCHEMA_VERSION = 2
LEGACY_PLAN_SCHEMA_VERSION = 2
MIN_LARK_REVIEW_CLI_VERSION = (1, 0, 49)
MAX_PAGES = 100
MAX_COMMENT_STABILITY_SCANS = 4
COMMENT_ACTIONS_KIND = "pmai_lark_review_comment_actions"
REMOTE_VERIFICATION_KIND = "pmai_lark_review_remote_verification"
REMOTE_VERIFICATION_SCHEMA_VERSION = 1
COMPLETED_COMMENT_DECISIONS = {
    "applied",
    "already_satisfied",
    "no_spec_change",
}
COMMENT_ACTION_STATUSES = {
    "pending",
    "reply_created",
    "solve_requested",
    "completed",
    "reopen_requested",
    "reopened",
}
SOLVE_EVIDENCE_MODES = {
    "server_time",
    "write_ack_and_stable_readback",
    "legacy_stable_readback",
}
REPLY_EVIDENCE_MODES = {
    "write_ack",
    "stable_readback",
    "legacy_stable_readback",
}
COMMENT_EXECUTION_MODES = {"single", "batch"}
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


def _write_text(path: Path, content: str) -> str:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ReviewError(f"拒绝覆盖非普通评审产物: {path}")
    tmp = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=f".{path.name}.",
        dir=path.parent,
        delete=False,
    )
    tmp_path = Path(tmp.name)
    try:
        tmp.write(content)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp.close()
        os.replace(tmp_path, path)
    finally:
        if not tmp.closed:
            tmp.close()
        tmp_path.unlink(missing_ok=True)
    return str(path.resolve())


def _write_json(path: Path, value: dict[str, Any]) -> str:
    return _write_text(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def _read_regular_text(path: Path, *, label: str) -> str:
    if path.is_symlink() or not path.is_file():
        raise ReviewError(f"{label} 不是普通文件: {path}")
    return path.read_text(encoding="utf-8")


def _file_digest(path: Path) -> str:
    if path.is_symlink() or not path.is_file():
        raise ReviewError(f"无法计算非普通文件摘要: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _load_json_object(path: Path, *, label: str) -> dict[str, Any]:
    value = json.loads(_read_regular_text(path, label=label))
    if not isinstance(value, dict):
        raise ReviewError(f"{label} 顶层必须是对象")
    return value


def _manifest_path(args_value: str) -> Path:
    raw_path = Path(args_value)
    if raw_path.is_symlink() or not raw_path.is_file():
        raise ReviewError(f"review.json 不是普通文件: {raw_path}")
    path = raw_path.resolve()
    if path.name != "review.json":
        raise ReviewError("评审清单必须使用 collect 生成的 review.json")
    return path


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
    raw = Path(str(value or ""))
    if raw.name != expected_name or raw.parent.resolve() != manifest_path.parent:
        raise ReviewError(f"review.json 的 {label} 不在本评审目录或文件名异常")
    if raw.is_symlink() or not raw.is_file():
        raise ReviewError(f"review.json 的 {label} 不是普通文件")
    return raw.resolve()


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
]:
    if path is None:
        return {}, {}, _default_target_derivation(), [], _default_preview_resolution(), []
    value = _load_json_object(path, label="resolutions.json")
    if value.get("schema_version") != RESOLUTION_SCHEMA_VERSION:
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
    return (
        index(value.get("body"), "change_id", "body"),
        index(value.get("comments"), "comment_id", "comments"),
        target,
        remote_coverage,
        preview,
        decision_routing,
    )


def _default_preview_resolution() -> dict[str, Any]:
    return {
        "approved": False,
        "authority": "pending",
        "reason": "",
    }


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
            path = Path(target_path)
            if (
                not target_path
                or path.is_absolute()
                or ".." in path.parts
                or path.name != "decisions.md"
                or not decision_id
                or not summary
                or not reason
            ):
                raise ReviewError(
                    f"{source[0]} {source[1]} 的 decision 写入缺少安全目标、ID、摘要或原因"
                )
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
        marked = {**item, "new_since_checkpoint": is_new}
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
        event_ids = {f"comment:{comment_id}"} if comment_id else set()
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
    markdown_input = Path(args.markdown)
    if markdown_input.is_symlink() or not markdown_input.is_file():
        raise ReviewError(f"本地 markdown 不是普通文件: {markdown_input}")
    markdown_path = markdown_input.resolve()
    output_input = Path(args.output_dir)
    if output_input.is_symlink():
        raise ReviewError("评审产物目录不能是符号链接")
    if output_input.exists():
        if not output_input.is_dir():
            raise ReviewError("评审产物路径不是目录")
        if any(output_input.iterdir()):
            raise ReviewError("评审产物目录必须为空，避免混用其它批次")
    else:
        output_input.mkdir(parents=True)
    os.chmod(output_input, 0o700)
    output_dir = output_input.resolve()

    raw = markdown_path.read_text(encoding="utf-8")
    frontmatter, local_body = parse_frontmatter(raw)
    doc_ref = args.doc or frontmatter.get("lark_doc_url") or frontmatter.get("lark_doc_id")
    if not doc_ref:
        raise ReviewError("缺少飞书链接/token，且本地 frontmatter 没有 lark_doc_id/lark_doc_url")
    if "://" in str(doc_ref) and _docx_token(doc_ref) is None:
        raise ReviewError("lark-review 只支持飞书 Docx 链接；旧版 /doc/ 或 wiki 链接请先迁移")

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
    frontmatter_doc_id = str(frontmatter.get("lark_doc_id") or "")
    if frontmatter_doc_id and frontmatter_doc_id != doc_id:
        raise ReviewError(
            f"输入飞书文档 {doc_id} 与本地 frontmatter 的 {frontmatter_doc_id} 不一致"
        )
    frontmatter_url_token = _docx_token(frontmatter.get("lark_doc_url"))
    if frontmatter_url_token and frontmatter_url_token != doc_id:
        raise ReviewError(
            f"飞书读取结果 {doc_id} 与本地 lark_doc_url 的 {frontmatter_url_token} 不一致"
        )
    if not frontmatter_doc_id and not frontmatter_url_token:
        raise ReviewError(
            "本地 markdown 缺少 lark_doc_id 或 Docx lark_doc_url；"
            "拒绝生成无法绑定回本地规格的评审批次"
        )
    input_token = _docx_token(args.doc) if args.doc else None
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
    if raw_path.is_symlink() or not raw_path.is_file():
        raise ReviewError("review.json 对应的本地 markdown 不是普通文件")
    return raw_path.resolve()


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
                None,
                default_decision="remote",
                default_authority="rule",
                default_reason="仅飞书变化，纳入发布后正文增量",
            )
            chosen = remote_segment
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


def reconcile(args: argparse.Namespace) -> int:
    reconcile_started = time.monotonic()
    manifest_path = _manifest_path(args.manifest)
    manifest = _load_manifest(manifest_path)
    sources = _source_artifacts(manifest_path, manifest)
    native_snapshot = _native_snapshot_artifact(manifest_path, manifest)
    markdown_path = _manifest_markdown_path(manifest)
    current_raw = _read_regular_text(markdown_path, label="本地 markdown")
    _, current_body = parse_frontmatter(current_raw)
    if hashlib.sha256(current_body.encode("utf-8")).hexdigest() != sources["local.md"]["exact_body_sha256"]:
        raise ReviewError("本地规格正文已在 collect 后变化，请重新 collect")

    resolutions_path = manifest_path.parent / "resolutions.json"
    target_path = manifest_path.parent / "target.md"
    plan_path = manifest_path.parent / "apply-plan.json"
    coverage_path = manifest_path.parent / "remote-coverage.json"
    preview_path = manifest_path.parent / "remote-preview.md"
    if args.resolutions:
        provided = Path(args.resolutions)
        if provided.is_symlink() or provided.resolve() != resolutions_path:
            raise ReviewError("--resolutions 必须指向本批次目录中的 resolutions.json")
    if args.seal:
        if resolutions_path.is_symlink() or not resolutions_path.is_file():
            raise ReviewError("seal 前必须完成本批次 resolutions.json")
        if target_path.is_symlink() or not target_path.is_file():
            raise ReviewError("seal 前必须完成本批次 target.md")
        (
            body_resolutions,
            comment_resolutions,
            target_derivation,
            coverage_resolutions,
            preview_resolution,
            decision_routing_resolutions,
        ) = _resolution_maps(
            resolutions_path,
            expected_batch_id=str(manifest.get("batch_id") or ""),
        )
    else:
        if args.resolutions:
            raise ReviewError("首次 reconcile 不接受 --resolutions；先生成批次模板")
        for path in (resolutions_path, target_path, plan_path, coverage_path, preview_path):
            if path.exists() or path.is_symlink():
                raise ReviewError("本批次已开始归位；编辑现有产物后使用 reconcile --seal")
        body_resolutions, comment_resolutions = {}, {}
        target_derivation = _default_target_derivation()
        coverage_resolutions = []
        preview_resolution = _default_preview_resolution()
        decision_routing_resolutions = []

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
            if (
                preview_resolution.get("approved") is not True
                or str(preview_resolution.get("authority") or "") != "pm_confirmed"
                or not str(preview_resolution.get("reason") or "").strip()
            ):
                raise ReviewError(
                    "R→T 差异达到强制预览阈值；PM 确认 remote-preview.md 前不能 seal"
                )
        decision_routing_resolutions = _validate_decision_routing(
            decision_routing_resolutions,
            body_records=body_records,
            comment_records=comment_records,
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


def apply_target(args: argparse.Namespace) -> int:
    plan_input = Path(args.plan)
    if plan_input.is_symlink() or not plan_input.is_file():
        raise ReviewError("apply-plan.json 不是普通文件")
    plan_path = plan_input.resolve()
    if plan_path.name != "apply-plan.json":
        raise ReviewError("--plan 必须指向本批次的 apply-plan.json")
    plan = _load_json_object(plan_path, label="apply-plan.json")
    if (
        plan.get("kind") != "pmai_lark_review_apply_plan"
        or plan.get("schema_version") != PLAN_SCHEMA_VERSION
        or plan.get("state") != "ready"
    ):
        raise ReviewError("apply-plan.json 尚未 seal 为 ready")

    manifest_path = plan_path.parent / "review.json"
    resolutions_path = plan_path.parent / "resolutions.json"
    target_path = plan_path.parent / "target.md"
    for path, label in (
        (manifest_path, "review.json"),
        (resolutions_path, "resolutions.json"),
        (target_path, "target.md"),
    ):
        if path.is_symlink() or not path.is_file():
            raise ReviewError(f"{label} 不是本批次普通文件")
    manifest = _load_manifest(manifest_path)
    if manifest.get("batch_id") != plan.get("batch_id"):
        raise ReviewError("apply-plan.json 与 review.json 批次不匹配")
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
    if decision_routing_resolutions != plan.get("decision_routing"):
        raise ReviewError("decision 归档路由与 seal 结果不一致")
    required = plan.get("required_items") or {}
    body_items = required.get("body") if isinstance(required, dict) else None
    comment_items = required.get("comments") if isinstance(required, dict) else None
    if not isinstance(body_items, list) or not isinstance(comment_items, list):
        raise ReviewError("apply-plan.json 缺少 required_items")
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
        coverage_path.is_symlink()
        or preview_path.is_symlink()
        or not coverage_path.is_file()
        or not preview_path.is_file()
        or _file_digest(coverage_path)
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

    markdown_input = Path(args.markdown)
    if markdown_input.is_symlink() or not markdown_input.is_file():
        raise ReviewError("apply 目标 markdown 不是普通文件")
    markdown_path = markdown_input.resolve()
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

    replace_markdown_body(markdown_path, target_body, expected_text=current_raw)
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
    plan_input = Path(plan_arg)
    if (
        plan_input.is_symlink()
        or not plan_input.is_file()
        or plan_input.resolve() != expected_plan_path
    ):
        raise ReviewError(f"{label} 必须使用本批次的 apply-plan.json")
    plan_path = plan_input.resolve()
    plan = _load_json_object(plan_path, label="apply-plan.json")
    schema_pair = (
        _int(manifest.get("schema_version")),
        _int(plan.get("schema_version")),
    )
    if (
        plan.get("kind") != "pmai_lark_review_apply_plan"
        or schema_pair
        not in {
            (SCHEMA_VERSION, PLAN_SCHEMA_VERSION),
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
        resolutions_path.is_symlink()
        or target_path.is_symlink()
        or not resolutions_path.is_file()
        or not target_path.is_file()
        or _file_digest(resolutions_path)
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
        coverage_path.is_symlink()
        or not coverage_path.is_file()
        or not isinstance(binding, dict)
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
        or _int(plan.get("schema_version")) != PLAN_SCHEMA_VERSION
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

    target_units = [
        (unit.kind, unit.normalised_text)
        for unit in markdown_semantic_units(str(context.get("body") or ""))
    ]
    remote_units = [
        (unit.kind, unit.normalised_text)
        for unit in markdown_semantic_units(str(remote_markdown.get("content") or ""))
    ]
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
) -> dict[str, Any]:
    path = manifest_path.parent / "remote-verification.json"
    if path.is_symlink() or not path.is_file():
        raise ReviewError("缺少本批 remote-verification.json；请先运行 verify-sync")
    value = _load_json_object(path, label="remote-verification.json")
    document = value.get("document")
    markdown_hash = str(value.get("remote_markdown_exact_sha256") or "")
    if (
        value.get("kind") != REMOTE_VERIFICATION_KIND
        or value.get("schema_version") != REMOTE_VERIFICATION_SCHEMA_VERSION
        or value.get("batch_id") != manifest.get("batch_id")
        or value.get("plan_ready_token") != plan.get("ready_token")
        or value.get("target_base") != "remote_native_snapshot"
        or value.get("content_projection_match") is not True
        or float(value.get("remote_accounted_ratio") or 0) != 1.0
        or float(value.get("remote_format_accounted_ratio") or 0) != 1.0
        or value.get("original_references_preserved") is not True
        or not isinstance(document, dict)
        or str(document.get("doc_id") or "") != doc_id
        or _int(document.get("verified_revision_id")) != published_revision
        or not re.fullmatch(r"[0-9a-f]{64}", markdown_hash)
    ):
        raise ReviewError("remote-verification.json 与当前 ready plan / 发布 revision 不一致")
    return value


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
    """Upgrade v1 receipts in memory without inventing missing server timestamps."""
    schema_version = _int(value.get("schema_version"))
    if schema_version == COMMENT_ACTIONS_SCHEMA_VERSION:
        upgraded = json.loads(json.dumps(value, ensure_ascii=False))
        upgraded.setdefault("execution_mode", "single")
        upgraded.setdefault("performance", _empty_comment_performance())
        actions = upgraded.get("actions")
        if not isinstance(actions, list):
            raise ReviewError("comment-actions.json actions 必须是数组")
        for action in actions:
            if not isinstance(action, dict):
                raise ReviewError("comment-actions.json action 必须是对象")
            action.setdefault("reply_write_ack_sha256", None)
            action.setdefault(
                "reply_evidence_mode",
                "legacy_stable_readback" if action.get("reply") is not None else None,
            )
        return upgraded
    if schema_version != 1:
        raise ReviewError("comment-actions.json schema_version 不受支持")
    upgraded = json.loads(json.dumps(value, ensure_ascii=False))
    upgraded["schema_version"] = COMMENT_ACTIONS_SCHEMA_VERSION
    upgraded["execution_mode"] = "single"
    upgraded["performance"] = _empty_comment_performance()
    actions = upgraded.get("actions")
    if not isinstance(actions, list):
        raise ReviewError("comment-actions.json actions 必须是数组")
    for action in actions:
        if not isinstance(action, dict):
            raise ReviewError("comment-actions.json action 必须是对象")
        status = str(action.get("status") or "")
        solved_time = _int(action.get("solved_time"))
        action["solve_evidence_mode"] = (
            "server_time" if status in {"completed", "reopen_requested", "reopened"}
            and solved_time is not None else None
        )
        action["reply_evidence_mode"] = (
            "legacy_stable_readback" if action.get("reply") is not None else None
        )
        action["reply_write_ack_sha256"] = None
        action["solve_write_ack_sha256"] = None
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
        ):
            raise ReviewError("comment-actions.json action 与本批评论合同不一致")
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
        solved_status = status in {"completed", "reopen_requested", "reopened"}
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
            if reply is not None and solver_user_id != str(reply.get("user_id") or ""):
                raise ReviewError(f"评论 {comment_id} 的回复作者与 solver 不一致")
        elif (
            solver_user_id
            or solved_time is not None
            or after_fence is not None
            or solve_evidence_mode
            or (solve_write_ack is not None and status != "solve_requested")
        ):
            raise ReviewError(f"评论 {comment_id} 尚未完成却包含完成证据")
        elif solve_write_ack is not None:
            _require_sha256(
                solve_write_ack,
                label=f"评论 {comment_id} solve_write_ack_sha256",
            )
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
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ReviewError("comment-actions.json 不是本批次普通文件")
    if not path.exists():
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
        if isinstance(expected_reply, dict) and solver_user_id != str(
            expected_reply.get("user_id") or ""
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
    elif solve_write_ack is not None:
        action["solve_evidence_mode"] = "write_ack_and_stable_readback"
    else:
        action["solve_evidence_mode"] = "legacy_stable_readback"
    action["after_fence_sha256"] = after_fence_sha256
    action["status"] = "completed"


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
    if action.get("solve_write_ack_sha256") is None:
        raise ReviewError("solve_requested 回执缺少系统解决写响应，不能由 reopen 接管")
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
    if status == "solve_requested":
        if bool(current.get("is_solved")):
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
        _verify_action_comment(action, current, expect_solved=True)
        return
    raise ReviewError(f"批量评论不接受状态 {status or 'missing'}")


def complete_comments(args: argparse.Namespace) -> int:
    """整批回复并解决评论，只在批次首尾读取稳定全量围栏。"""
    batch_started = time.monotonic()
    scan_counters_before = _comment_scan_counters()
    document_fetches = 0
    reply_writes = 0
    solve_writes = 0
    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        args.manifest,
        args.plan,
        label="complete-comments",
    )
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
            execution_mode="batch",
        )
    elif actions_value.get("execution_mode") != "batch":
        raise ReviewError(
            "当前 comment-actions.json 来自单项入口；请先用 complete-comment 恢复旧操作"
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
        "status": "completed",
        "execution_mode": "batch",
        "batch_id": manifest.get("batch_id"),
        "doc_id": doc_id,
        "comment_ids": ordered_ids,
        "comment_count": len(ordered_ids),
        "receipt": str(actions_path),
        "performance": actions_value["performance"],
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
                if allow_reopen_states and comment_id in (reopen_comment_ids or set()):
                    _verify_reopen_action_comment(
                        action,
                        current,
                        expect_solved=True,
                    )
                else:
                    _verify_action_comment(action, current, expect_solved=True)
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


def reopen(args: argparse.Namespace) -> int:
    """在 checkpoint 失败后，受批次约束地重开本次系统已解决的评论。"""
    manifest_path, manifest, plan_path, plan = _load_ready_batch(
        args.manifest,
        args.plan,
        label="reopen",
    )
    context = _published_target_context(manifest, plan, label="reopen")
    markdown_path = Path(context["markdown_path"])
    requested_markdown = Path(args.markdown)
    if requested_markdown.is_symlink() or not requested_markdown.is_file():
        raise ReviewError("reopen 目标 markdown 不是普通文件")
    if requested_markdown.resolve() != markdown_path:
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
    markdown_input = Path(args.markdown)
    if markdown_input.is_symlink() or not markdown_input.is_file():
        raise ReviewError("checkpoint 目标 markdown 不是普通文件")
    if markdown_input.resolve() != markdown_path:
        raise ReviewError("review.json 与 checkpoint 目标 markdown 不匹配")
    raw = str(context["raw"])
    frontmatter = context["frontmatter"]
    body = str(context["body"])
    manifest_doc_id = str(context["doc_id"])
    published_revision = int(context["published_revision_id"])
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
        if actions_value.get("execution_mode") == "batch":
            for action in actions_value["actions"]:
                if action.get("status") != "completed":
                    raise ReviewError(
                        f"评论 {action.get('comment_id')} 缺少 completed 回执"
                    )
                if action.get("before_fence_sha256") != initial_fence:
                    raise ReviewError("批量评论回执没有绑定统一初始围栏")
                if action.get("after_fence_sha256") != current_receipt_fence:
                    raise ReviewError("批量评论回执没有绑定统一最终围栏")
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
        )
        expected_remote_hash = str(verification["remote_markdown_exact_sha256"])
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
        expected_remote_hash = _sha256_text(
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
        _sha256_text(str(final_remote_document.get("content") or "")),
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
    write_frontmatter(markdown_path, updated, body, expected_text=raw)
    print(json.dumps({
        "markdown_path": str(markdown_path),
        "lark_reviewed_revision_id": revision,
        "lark_reviewed_comment_at": comment_time,
        "lark_reviewed_comment_ids": sorted(comment_ids),
        "lark_reviewed_at": reviewed_at,
        "comment_actions": str(actions_path) if actions_value is not None else None,
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
    markdown_input = Path(args.markdown)
    if markdown_input.is_symlink() or not markdown_input.is_file():
        raise ReviewError(f"baseline 目标 markdown 不是普通文件: {markdown_input}")
    markdown_path = markdown_input.resolve()
    revision = _int(args.revision_id)
    if revision is None or revision < 0:
        raise ReviewError("baseline 需要非负 revision-id")
    raw = markdown_path.read_text(encoding="utf-8")
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
    write_frontmatter(markdown_path, updated, body, expected_text=raw)
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
    complete_batch_parser.set_defaults(handler=complete_comments)

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
