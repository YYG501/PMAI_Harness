"""Deterministic semantic and native-format accounting for Lark review batches."""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from bisect import bisect_left
from collections import defaultdict, deque
from dataclasses import asdict, dataclass
from typing import Any
from xml.etree import ElementTree


REMOTE_COVERAGE_KIND = "pmai_lark_review_remote_coverage"
REMOTE_COVERAGE_SCHEMA_VERSION = 2
NATIVE_SNAPSHOT_KIND = "pmai_lark_review_remote_native_snapshot"
NATIVE_SNAPSHOT_SCHEMA_VERSION = 1

_HEADING_RE = re.compile(r"^(#{1,9})\s+(.*)$")
_LIST_RE = re.compile(r"^([ \t]*)([-+*]|\d+[.)])\s+(.*)$")
_TABLE_SEPARATOR_RE = re.compile(r"^\s*\|?(?:\s*:?-{3,}:?\s*\|)+\s*$")
_INLINE_LINK_RE = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
_INLINE_MARK_RE = re.compile(r"(?:\*\*|__|~~|`|\*|_)")
_SPACE_RE = re.compile(r"\s+")
_RESOURCE_ATTRS = {
    "token",
    "src",
    "doc-id",
    "sheet-id",
    "task-id",
    "chat-id",
    "src-token",
    "src-block-id",
}
_EVIDENCE_KINDS = {"format_rule", "comment", "decision", "pm_exception"}
_DISPOSITIONS = {"rewritten", "removed"}
_FORMAT_DISPOSITIONS = {"preserved", "removed_with_content"}


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _normalise_semantic_text(value: str) -> str:
    value = unicodedata.normalize("NFKC", value)
    return _SPACE_RE.sub(" ", value).strip()


def _normalise_native_match_text(value: str) -> str:
    """Project Markdown to visible text only for matching it to native blocks."""
    value = unicodedata.normalize("NFKC", value)
    value = _INLINE_LINK_RE.sub(lambda match: match.group(1), value)
    value = _INLINE_MARK_RE.sub("", value)
    return _SPACE_RE.sub(" ", value).strip()


def _mask_inline_image_destinations(value: str) -> str:
    """Mask image destinations while preserving alt text and Markdown structure."""
    output: list[str] = []
    cursor = 0
    length = len(value)
    while cursor < length:
        start = value.find("![", cursor)
        if start < 0:
            output.append(value[cursor:])
            break
        output.append(value[cursor:start])
        alt_end = start + 2
        escaped = False
        while alt_end < length:
            char = value[alt_end]
            if char == "]" and not escaped:
                break
            if char == "\\" and not escaped:
                escaped = True
            else:
                escaped = False
            alt_end += 1
        if alt_end >= length or alt_end + 1 >= length or value[alt_end + 1] != "(":
            output.append(value[start : start + 2])
            cursor = start + 2
            continue
        destination_end = alt_end + 2
        depth = 1
        escaped = False
        while destination_end < length:
            char = value[destination_end]
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    break
            destination_end += 1
        if destination_end >= length:
            output.append(value[start : start + 2])
            cursor = start + 2
            continue
        output.append(f"![{value[start + 2:alt_end]}](pmai:image-resource)")
        cursor = destination_end + 1
    return "".join(output)


def markdown_verification_projection(markdown: str) -> list[tuple[str, str, str]]:
    """Return a stable content projection; native XML owns image identity."""
    projection: list[tuple[str, str, str]] = []
    for unit in markdown_semantic_units(markdown):
        text = unit.text
        if unit.kind != "code":
            text = _mask_inline_image_destinations(text)
        projection.append(
            (
                unit.kind,
                _normalise_semantic_text(text),
                unit.structure_signature,
            )
        )
    return projection


def _unit_id(kind: str, normalised: str, occurrence: int) -> str:
    digest = _sha256_text(f"{kind}\0{normalised}")[:16]
    return f"remote-{kind}-{digest}-{occurrence}"


def _section_signature(section_path: list[str]) -> tuple[str, ...]:
    return tuple(_normalise_semantic_text(item) for item in section_path)


def _structure_signature(
    kind: str,
    *,
    heading_level: int | None = None,
    list_ordered: bool | None = None,
    list_indent: int | None = None,
    table_role: str | None = None,
) -> str:
    if kind == "heading":
        return f"heading:level={heading_level}"
    if kind == "list_item":
        ordered = "ordered" if list_ordered else "unordered"
        return f"list_item:{ordered}:indent={list_indent}"
    if kind == "table_row":
        return f"table_row:role={table_role}"
    return kind


def _order_preserved_unit_ids(
    matches: list[tuple[SemanticUnit, SemanticUnit]],
) -> set[str]:
    """Return one longest set of exact matches whose relative order is unchanged."""
    if not matches:
        return set()
    tails: list[int] = []
    tail_positions: list[int] = []
    predecessors = [-1] * len(matches)
    for position, (_, target) in enumerate(matches):
        insertion = bisect_left(tails, target.index)
        if insertion > 0:
            predecessors[position] = tail_positions[insertion - 1]
        if insertion == len(tails):
            tails.append(target.index)
            tail_positions.append(position)
        else:
            tails[insertion] = target.index
            tail_positions[insertion] = position

    preserved: set[str] = set()
    cursor = tail_positions[-1]
    while cursor >= 0:
        preserved.add(matches[cursor][0].unit_id)
        cursor = predecessors[cursor]
    return preserved


@dataclass(frozen=True)
class SemanticUnit:
    unit_id: str
    kind: str
    structure_signature: str
    index: int
    line_start: int
    line_end_exclusive: int
    section_path: list[str]
    text: str
    normalised_text: str
    native_match_text: str
    exact_sha256: str


def markdown_semantic_units(markdown: str) -> list[SemanticUnit]:
    """Split PMAI markdown into conservative, stable semantic blocks."""
    lines = markdown.replace("\r\n", "\n").replace("\r", "\n").splitlines()
    raw_units: list[tuple[str, str, int, int, list[str], str]] = []
    headings: list[str] = []
    paragraph: list[str] = []
    paragraph_start = 0
    in_fence = False
    fence_start = 0
    fence_lines: list[str] = []

    def flush_paragraph(end: int) -> None:
        nonlocal paragraph
        if not paragraph:
            return
        text = "\n".join(paragraph).strip()
        if text:
            raw_units.append(
                (
                    "paragraph",
                    _structure_signature("paragraph"),
                    paragraph_start,
                    end,
                    list(headings),
                    text,
                )
            )
        paragraph = []

    for index, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            flush_paragraph(index)
            if not in_fence:
                in_fence = True
                fence_start = index
                fence_lines = [line]
            else:
                fence_lines.append(line)
                raw_units.append(
                    (
                        "code",
                        _structure_signature("code"),
                        fence_start,
                        index + 1,
                        list(headings),
                        "\n".join(fence_lines),
                    )
                )
                in_fence = False
                fence_lines = []
            continue
        if in_fence:
            fence_lines.append(line)
            continue
        heading = _HEADING_RE.match(line)
        if heading:
            flush_paragraph(index)
            level = len(heading.group(1))
            title = heading.group(2).strip()
            headings = headings[: level - 1]
            headings.append(title)
            raw_units.append(
                (
                    "heading",
                    _structure_signature("heading", heading_level=level),
                    index,
                    index + 1,
                    list(headings),
                    title,
                )
            )
            continue
        listed = _LIST_RE.match(line)
        if listed:
            flush_paragraph(index)
            marker = listed.group(2)
            raw_units.append(
                (
                    "list_item",
                    _structure_signature(
                        "list_item",
                        list_ordered=marker[0].isdigit(),
                        list_indent=len(listed.group(1).expandtabs(4)),
                    ),
                    index,
                    index + 1,
                    list(headings),
                    listed.group(3).strip(),
                )
            )
            continue
        if line.strip().startswith("|"):
            flush_paragraph(index)
            if not _TABLE_SEPARATOR_RE.match(line):
                cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
                is_header = (
                    index + 1 < len(lines)
                    and _TABLE_SEPARATOR_RE.match(lines[index + 1]) is not None
                )
                raw_units.append(
                    (
                        "table_row",
                        _structure_signature(
                            "table_row",
                            table_role="header" if is_header else "data",
                        ),
                        index,
                        index + 1,
                        list(headings),
                        " | ".join(cells),
                    )
                )
            continue
        if not line.strip():
            flush_paragraph(index)
            continue
        if not paragraph:
            paragraph_start = index
        paragraph.append(line)

    if in_fence:
        raw_units.append(
            (
                "code",
                _structure_signature("code"),
                fence_start,
                len(lines),
                list(headings),
                "\n".join(fence_lines),
            )
        )
    flush_paragraph(len(lines))

    occurrences: dict[tuple[str, str], int] = defaultdict(int)
    units: list[SemanticUnit] = []
    for index, (kind, structure, start, end, section_path, text) in enumerate(raw_units):
        normalised = _normalise_semantic_text(text)
        if not normalised:
            continue
        key = (kind, normalised)
        occurrences[key] += 1
        units.append(
            SemanticUnit(
                unit_id=_unit_id(kind, normalised, occurrences[key]),
                kind=kind,
                structure_signature=structure,
                index=index,
                line_start=start + 1,
                line_end_exclusive=end + 1,
                section_path=section_path,
                text=text,
                normalised_text=normalised,
                native_match_text=_normalise_native_match_text(text),
                exact_sha256=_sha256_text(text),
            )
        )
    return units


def _xml_root(content: str) -> ElementTree.Element:
    cleaned = re.sub(r"^\s*<\?xml[^>]*>\s*", "", content)
    try:
        return ElementTree.fromstring(f"<pmai-document>{cleaned}</pmai-document>")
    except ElementTree.ParseError as exc:
        raise ValueError(f"飞书 full XML 无法解析: {exc}") from exc


def _element_style_shape(element: ElementTree.Element) -> dict[str, Any]:
    return {
        "tag": element.tag,
        "attrs": {
            key: value
            for key, value in sorted(element.attrib.items())
            if key != "id" and key not in _RESOURCE_ATTRS
        },
        "children": [_element_style_shape(child) for child in list(element)],
    }


def native_block_inventory(content: str) -> list[dict[str, Any]]:
    root = _xml_root(content)
    inventory: list[dict[str, Any]] = []
    for element in root.iter():
        block_id = str(element.attrib.get("id") or "")
        if not block_id:
            continue
        exact_xml = ElementTree.tostring(element, encoding="unicode", short_empty_elements=True)
        style_shape = json.dumps(
            _element_style_shape(element),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        resources: list[dict[str, str]] = []
        for child in element.iter():
            for key, value in child.attrib.items():
                if key in _RESOURCE_ATTRS and value:
                    resources.append({"attribute": key, "value": value})
        inventory.append(
            {
                "block_id": block_id,
                "tag": element.tag,
                "text": _normalise_semantic_text("".join(element.itertext())),
                "exact_sha256": _sha256_text(exact_xml),
                "format_sha256": _sha256_text(style_shape),
                "resources": sorted(resources, key=lambda item: (item["attribute"], item["value"])),
            }
        )
    return inventory


def build_native_snapshot(document: dict[str, Any]) -> dict[str, Any]:
    content = str(document.get("content") or "")
    inventory = native_block_inventory(content)
    resource_pairs = {
        (item["attribute"], item["value"])
        for block in inventory
        for item in block["resources"]
    }
    return {
        "kind": NATIVE_SNAPSHOT_KIND,
        "schema_version": NATIVE_SNAPSHOT_SCHEMA_VERSION,
        "document": document,
        "native": {
            "content_sha256": _sha256_text(content),
            "block_count": len(inventory),
            "resource_count": len(resource_pairs),
            "blocks": inventory,
        },
    }


def _resolution_evidence(value: object) -> tuple[dict[str, str] | None, str | None]:
    if not isinstance(value, dict):
        return None, "缺少 evidence"
    kind = str(value.get("kind") or "")
    evidence_id = str(value.get("id") or "")
    reason = str(value.get("reason") or "").strip()
    if kind not in _EVIDENCE_KINDS or not evidence_id or not reason:
        return None, "evidence 必须绑定格式规则、评论、决定或 PM 明确例外"
    return {"kind": kind, "id": evidence_id, "reason": reason}, None


def build_remote_coverage(
    remote_markdown: str,
    target_markdown: str,
    *,
    native_snapshot: dict[str, Any],
    resolutions: list[dict[str, Any]],
    batch_id: str,
    remote_revision_id: int,
) -> dict[str, Any]:
    remote_units = markdown_semantic_units(remote_markdown)
    target_units = markdown_semantic_units(target_markdown)
    target_by_section_signature: dict[
        tuple[str, str, str, tuple[str, ...]], deque[SemanticUnit]
    ] = defaultdict(deque)
    target_by_id = {unit.unit_id: unit for unit in target_units}
    for unit in target_units:
        target_by_section_signature[
            (
                unit.kind,
                unit.normalised_text,
                unit.structure_signature,
                _section_signature(unit.section_path),
            )
        ].append(unit)

    target_matches: dict[str, SemanticUnit] = {}
    matched_target_ids: set[str] = set()
    unmatched_remote_units: list[SemanticUnit] = []
    for remote in remote_units:
        signature = (
            remote.kind,
            remote.normalised_text,
            remote.structure_signature,
            _section_signature(remote.section_path),
        )
        matching = target_by_section_signature.get(signature)
        target = matching.popleft() if matching else None
        if target is not None:
            target_matches[remote.unit_id] = target
            matched_target_ids.add(target.unit_id)
        else:
            unmatched_remote_units.append(remote)

    remaining_remote_by_signature: dict[
        tuple[str, str, str], list[SemanticUnit]
    ] = defaultdict(list)
    remaining_target_by_signature: dict[
        tuple[str, str, str], list[SemanticUnit]
    ] = defaultdict(list)
    for remote in unmatched_remote_units:
        remaining_remote_by_signature[
            (remote.kind, remote.normalised_text, remote.structure_signature)
        ].append(remote)
    for target in target_units:
        if target.unit_id not in matched_target_ids:
            remaining_target_by_signature[
                (target.kind, target.normalised_text, target.structure_signature)
            ].append(target)

    cross_section_match_ids: set[str] = set()
    for signature, remote_candidates in remaining_remote_by_signature.items():
        target_candidates = remaining_target_by_signature.get(signature, [])
        if len(remote_candidates) != 1 or len(target_candidates) != 1:
            continue
        remote = remote_candidates[0]
        target = target_candidates[0]
        if _section_signature(remote.section_path) == _section_signature(target.section_path):
            continue
        target_matches[remote.unit_id] = target
        matched_target_ids.add(target.unit_id)
        cross_section_match_ids.add(remote.unit_id)

    remaining_targets_by_content: dict[
        tuple[str, str], list[SemanticUnit]
    ] = defaultdict(list)
    for target in target_units:
        if target.unit_id not in matched_target_ids:
            remaining_targets_by_content[(target.kind, target.normalised_text)].append(
                target
            )
    structural_change_ids = {
        remote.unit_id
        for remote in remote_units
        if remote.unit_id not in target_matches
        and any(
            target.structure_signature != remote.structure_signature
            for target in remaining_targets_by_content.get(
                (remote.kind, remote.normalised_text), []
            )
        )
    }

    same_section_matches = [
        (remote, target_matches[remote.unit_id])
        for remote in remote_units
        if remote.unit_id in target_matches
        and remote.unit_id not in cross_section_match_ids
    ]
    order_preserved_ids = _order_preserved_unit_ids(same_section_matches)

    resolution_by_id = {
        str(item.get("remote_unit_id") or ""): item
        for item in resolutions
        if isinstance(item, dict) and str(item.get("remote_unit_id") or "")
    }
    duplicate_ids = len(resolution_by_id) != len(
        [item for item in resolutions if isinstance(item, dict) and item.get("remote_unit_id")]
    )
    if duplicate_ids:
        raise ValueError("resolutions.json 的 remote_coverage 存在重复 remote_unit_id")

    native_blocks = (native_snapshot.get("native") or {}).get("blocks")
    if not isinstance(native_blocks, list):
        raise ValueError("remote-native.json 缺少 native.blocks")
    native_by_text: dict[str, deque[str]] = defaultdict(deque)
    for block in native_blocks:
        if isinstance(block, dict) and str(block.get("text") or ""):
            native_by_text[str(block["text"])].append(str(block.get("block_id") or ""))

    entries: list[dict[str, Any]] = []
    used_resolution_ids: set[str] = set()
    accounted = 0
    preserved = 0
    moved = 0
    rewritten = 0
    removed = 0
    unassigned = 0
    high_risk_count = 0
    native_format_dispositions: dict[str, tuple[str, dict[str, str]]] = {}

    for remote in remote_units:
        target = target_matches.get(remote.unit_id)
        native_candidates = native_by_text.get(remote.native_match_text)
        native_ids = [native_candidates.popleft()] if native_candidates else []
        if target is not None:
            disposition = (
                "moved"
                if remote.unit_id in cross_section_match_ids
                or remote.unit_id not in order_preserved_ids
                else "preserved"
            )
            entries.append(
                {
                    "remote": asdict(remote),
                    "disposition": disposition,
                    "target_unit_ids": [target.unit_id],
                    "native_block_ids": native_ids,
                    "evidence": {"kind": "rule", "id": "semantic_identity", "reason": "目标中存在相同语义单元"},
                    "format_disposition": "preserved",
                    "accounted": True,
                    "format_accounted": True,
                    "structural_change": False,
                }
            )
            accounted += 1
            if disposition == "moved":
                moved += 1
                if remote.unit_id in cross_section_match_ids or remote.kind in {
                    "heading",
                    "table_row",
                }:
                    high_risk_count += 1
            else:
                preserved += 1
            for block_id in native_ids:
                native_format_dispositions[block_id] = (
                    "preserved",
                    {
                        "kind": "rule",
                        "id": "native_block_untouched",
                        "reason": "目标保留远端语义，精细回写不得重建对应原生 block",
                    },
                )
            continue

        supplied = resolution_by_id.get(remote.unit_id)
        entry: dict[str, Any] = {
            "remote": asdict(remote),
            "disposition": "unassigned",
            "target_unit_ids": [],
            "native_block_ids": native_ids,
            "evidence": None,
            "format_disposition": "unassigned",
            "accounted": False,
            "format_accounted": False,
            "structural_change": remote.unit_id in structural_change_ids,
        }
        if supplied is not None:
            used_resolution_ids.add(remote.unit_id)
            disposition = str(supplied.get("disposition") or "")
            target_ids = supplied.get("target_unit_ids")
            format_disposition = str(supplied.get("format_disposition") or "")
            evidence, evidence_error = _resolution_evidence(supplied.get("evidence"))
            valid_targets = (
                isinstance(target_ids, list)
                and bool(target_ids)
                and all(isinstance(item, str) and item in target_by_id for item in target_ids)
            )
            if disposition == "removed":
                valid_targets = target_ids == []
            expected_format_disposition = (
                "removed_with_content" if disposition == "removed" else "preserved"
            )
            if (
                disposition in _DISPOSITIONS
                and valid_targets
                and evidence_error is None
                and format_disposition == expected_format_disposition
            ):
                entry.update(
                    disposition=disposition,
                    target_unit_ids=target_ids,
                    evidence=evidence,
                    format_disposition=format_disposition,
                    accounted=True,
                    format_accounted=True,
                )
                if disposition == "rewritten":
                    entry["structural_change"] = bool(
                        entry["structural_change"]
                    ) or any(
                        (
                            target_by_id[target_id].kind,
                            target_by_id[target_id].structure_signature,
                        )
                        != (remote.kind, remote.structure_signature)
                        for target_id in target_ids
                    )
                accounted += 1
                if disposition == "removed":
                    removed += 1
                else:
                    rewritten += 1
                for block_id in native_ids:
                    native_format_dispositions[block_id] = (
                        format_disposition,
                        evidence or {},
                    )
            else:
                if disposition == "rewritten" and not valid_targets:
                    entry["resolution_error"] = "改写必须绑定至少一个当前 T 的有效语义单元"
                else:
                    entry["resolution_error"] = evidence_error or (
                        "改写必须保留原生格式；删除只能随已确认内容一起移除格式"
                    )
        if not entry["accounted"]:
            unassigned += 1
            for block_id in native_ids:
                native_format_dispositions[block_id] = ("unassigned", {})
        if remote.kind in {"heading", "table_row"} or bool(
            entry["structural_change"]
        ):
            high_risk_count += 1
        entries.append(entry)

    native_format_entries: list[dict[str, Any]] = []
    format_accounted = 0
    format_preserved = 0
    for block in native_blocks:
        if not isinstance(block, dict):
            continue
        block_id = str(block.get("block_id") or "")
        disposition = native_format_dispositions.get(block_id)
        if disposition is None:
            disposition = (
                "preserved",
                {
                    "kind": "rule",
                    "id": "native_only_block_untouched",
                    "reason": "远端原生块不承载被改写的 Markdown 语义，精细回写必须原样保留",
                },
            )
        format_disposition, format_evidence = disposition
        format_is_accounted = format_disposition in _FORMAT_DISPOSITIONS
        native_format_entries.append(
            {
                "block_id": block_id,
                "tag": block.get("tag"),
                "format_sha256": block.get("format_sha256"),
                "resources": block.get("resources") or [],
                "format_disposition": format_disposition,
                "evidence": format_evidence,
                "accounted": format_is_accounted,
            }
        )
        if format_is_accounted:
            format_accounted += 1
        if format_disposition == "preserved":
            format_preserved += 1

    unknown_resolution_ids = sorted(set(resolution_by_id) - used_resolution_ids)
    total = len(remote_units)
    changed = moved + rewritten + removed + unassigned
    changed_ratio = changed / total if total else 0.0
    preview_required = bool(
        changed >= 10
        or (total >= 20 and changed_ratio >= 0.15)
        or high_risk_count > 0
    )
    native_total = len(native_format_entries)
    return {
        "kind": REMOTE_COVERAGE_KIND,
        "schema_version": REMOTE_COVERAGE_SCHEMA_VERSION,
        "batch_id": batch_id,
        "target_base": "remote_native_snapshot",
        "target_base_revision": remote_revision_id,
        "entries": entries,
        "native_format_entries": native_format_entries,
        "unknown_resolution_ids": unknown_resolution_ids,
        "summary": {
            "remote_unit_count": total,
            "accounted_count": accounted,
            "preserved_count": preserved,
            "moved_count": moved,
            "rewritten_count": rewritten,
            "removed_count": removed,
            "unassigned_count": unassigned,
            "remote_accounted_ratio": accounted / total if total else 1.0,
            "remote_preserved_ratio": (
                (preserved + moved) / total if total else 1.0
            ),
            "format_accounted_count": format_accounted,
            "format_preserved_count": format_preserved,
            "native_block_count": native_total,
            "format_unassigned_count": native_total - format_accounted,
            "remote_format_accounted_ratio": (
                format_accounted / native_total if native_total else 1.0
            ),
            "remote_format_preserved_ratio": (
                format_preserved / native_total if native_total else 1.0
            ),
            "preview_required": preview_required,
            "pm_confirmation_required": False,
            "high_risk_structural_count": high_risk_count,
        },
        "target_units": [asdict(unit) for unit in target_units],
    }


def render_remote_preview(coverage: dict[str, Any]) -> str:
    """Render a compact PM-facing preview for remote semantics changed by T."""
    summary = coverage.get("summary") or {}
    lines = [
        "# 飞书目标稿预览\n",
        "\n",
        f"- 目标底稿：飞书 revision {coverage.get('target_base_revision')} 原生快照\n",
        f"- 内容覆盖率：{float(summary.get('remote_accounted_ratio') or 0):.2%}\n",
        f"- 格式归位率：{float(summary.get('remote_format_accounted_ratio') or 0):.2%}\n",
        f"- 未归位：{int(summary.get('unassigned_count') or 0)} 项\n",
        "\n",
        "## 发生位置或内容变化的飞书内容\n",
        "\n",
    ]
    changed = [
        item
        for item in coverage.get("entries") or []
        if isinstance(item, dict)
        and item.get("disposition") != "preserved"
    ]
    if not changed:
        lines.append("无。\n")
        return "".join(lines)
    target_by_id = {
        str(item.get("unit_id") or ""): item
        for item in coverage.get("target_units") or []
        if isinstance(item, dict)
    }
    for item in changed:
        remote = item.get("remote") or {}
        evidence = item.get("evidence") or {}
        section = " / ".join(remote.get("section_path") or []) or "文档正文"
        target_ids = item.get("target_unit_ids") or []
        target = target_by_id.get(str(target_ids[0])) if target_ids else None
        movement = ""
        if item.get("disposition") == "moved" and isinstance(target, dict):
            target_section = " / ".join(target.get("section_path") or []) or "文档正文"
            movement = (
                f"- 移动：{section} 第 {int(remote.get('index') or 0) + 1} 项"
                f" → {target_section} 第 {int(target.get('index') or 0) + 1} 项\n"
            )
        lines.extend(
            [
                f"### {remote.get('unit_id')}\n",
                "\n",
                f"- 位置：{section}\n",
                f"- 处置：{item.get('disposition')}\n",
                movement,
                f"- 格式：{item.get('format_disposition')}\n",
                f"- 依据：{evidence.get('kind') or '未归位'} / {evidence.get('id') or '-'} / {evidence.get('reason') or '-'}\n",
                "\n",
                "```text\n",
                str(remote.get("text") or ""),
                "\n```\n\n",
            ]
        )
    return "".join(lines)
