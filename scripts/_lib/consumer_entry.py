#!/usr/bin/env python3
"""Plan safe updates for the PMAI-managed consumer startup block."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path


START_MARKER = "<!-- PMAI:BEGIN consumer-startup -->"
END_MARKER = "<!-- PMAI:END consumer-startup -->"
REQUIRED_LEGACY_RULES = {"claude", "preamble", "project_hooks", "status"}


class ConsumerEntryError(RuntimeError):
    pass


@dataclass(frozen=True)
class EntryPlan:
    status: str
    path: Path
    strategy: str | None = None
    reason: str | None = None
    current_text: str | None = None
    rendered_text: str | None = None

    @property
    def can_apply(self) -> bool:
        return self.status == "stale" and self.rendered_text is not None

    def contract(self) -> dict[str, object]:
        payload: dict[str, object] = {
            "status": self.status,
            "path": "AGENTS.md",
        }
        if self.strategy:
            payload["strategy"] = self.strategy
        if self.reason:
            payload["reason"] = self.reason
        payload["repair_available"] = self.can_apply
        return payload


def _single_section(text: str, heading: str) -> tuple[int, int] | None:
    matches = list(re.finditer(rf"(?m)^{re.escape(heading)}[ \t]*\n", text))
    if len(matches) != 1:
        return None
    start = matches[0].start()
    next_heading = re.search(r"(?m)^## [^#].*$", text[matches[0].end() :])
    end = len(text) if next_heading is None else matches[0].end() + next_heading.start()
    return start, end


def _marked_span(text: str) -> tuple[int, int] | None:
    if text.count(START_MARKER) != 1 or text.count(END_MARKER) != 1:
        return None
    start = text.index(START_MARKER)
    end = text.index(END_MARKER)
    if end <= start:
        return None
    return start, end + len(END_MARKER)


def _template_contract(template_path: Path) -> tuple[str, str]:
    try:
        template = template_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ConsumerEntryError(f"无法读取当前 AGENTS.md 模板: {template_path}") from exc
    marker_span = _marked_span(template)
    section_span = _single_section(template, "## Startup")
    if marker_span is None or section_span is None \
        or marker_span[0] < section_span[0] or marker_span[1] > section_span[1]:
        raise ConsumerEntryError("当前 AGENTS.md 模板缺少唯一的 Startup 托管区块")
    return template[marker_span[0] : marker_span[1]], template[section_span[0] : section_span[1]]


def _managed_rule_kind(block: str) -> str | None:
    kinds: list[str] = []
    if "读 `CLAUDE.md`" in block and "Host Mapping" in block:
        kinds.append("claude")
    if "skill-preamble.sh" in block:
        kinds.append("preamble")
    if "install-project-hooks.sh" in block or "install-codex-hooks.sh" in block:
        kinds.append("project_hooks")
    if "manage-kimi-hooks.py" in block or "KIMI_CODE_HOME" in block:
        kinds.append("kimi")
    if "install-opencode-commands.sh" in block:
        kinds.append("opencode")
    if "/pmai-status" in block and "下一步" in block:
        kinds.append("status")
    if len(kinds) > 1:
        raise ConsumerEntryError("旧 Startup 中有一条规则混合了多个 PMAI 托管职责")
    return kinds[0] if kinds else None


def _looks_like_unknown_pmai_rule(block: str) -> bool:
    return any(
        token in block
        for token in (
            "PMAI",
            "/pmai-",
            "$pmai-",
            "/skill:pmai-",
            "PMAI_HOME",
            "skill-preamble",
            "install-project-hooks",
            "install-codex-hooks",
            "install-opencode-commands",
            "manage-kimi-hooks",
        )
    )


def _legacy_rendered_text(text: str, template_section: str) -> str:
    section_span = _single_section(text, "## Startup")
    if section_span is None:
        raise ConsumerEntryError("旧 AGENTS.md 缺少唯一的 ## Startup，不能自动迁移")
    section_start, section_end = section_span
    section = text[section_start:section_end]
    header_match = re.match(r"^## Startup[ \t]*\n", section)
    if header_match is None:
        raise ConsumerEntryError("旧 AGENTS.md 的 Startup 标题无法解析")
    body = section[header_match.end() :]

    trailing_heading = re.search(r"(?m)^#{3,6} .*$", body)
    list_region = body if trailing_heading is None else body[: trailing_heading.start()]
    trailing_custom = "" if trailing_heading is None else body[trailing_heading.start() :]
    item_matches = list(re.finditer(r"(?m)^\d+\.[ \t]+", list_region))
    if not item_matches:
        raise ConsumerEntryError("旧 Startup 没有可识别的编号规则，不能自动迁移")

    prefix = list_region[: item_matches[0].start()]
    prefix_lines = [
        line
        for line in prefix.splitlines(keepends=True)
        if line.strip() and line.strip() != "会话开始时按顺序做："
    ]
    custom_parts = ["".join(prefix_lines)] if prefix_lines else []
    managed_kinds: set[str] = set()
    for index, match in enumerate(item_matches):
        end = item_matches[index + 1].start() if index + 1 < len(item_matches) else len(list_region)
        block = list_region[match.start() : end]
        kind = _managed_rule_kind(block)
        if kind is not None:
            if kind in managed_kinds:
                raise ConsumerEntryError(f"旧 Startup 重复声明了 {kind} 托管规则")
            managed_kinds.add(kind)
        elif _looks_like_unknown_pmai_rule(block):
            raise ConsumerEntryError("旧 Startup 含无法确定归属的 PMAI 规则，需要人工确认")
        else:
            custom_parts.append(block)

    if not REQUIRED_LEGACY_RULES.issubset(managed_kinds):
        missing = ", ".join(sorted(REQUIRED_LEGACY_RULES - managed_kinds))
        raise ConsumerEntryError(f"旧 Startup 缺少可验证的历史托管规则: {missing}")
    if trailing_custom.strip():
        if _looks_like_unknown_pmai_rule(trailing_custom):
            raise ConsumerEntryError("旧 Startup 的自定义段落含无法归属的 PMAI 规则")
        custom_parts.append(trailing_custom)

    custom_text = "".join(custom_parts).strip("\n")
    rendered_section = template_section.rstrip("\n") + "\n"
    if custom_text:
        rendered_section += f"\n### 项目启动补充\n\n{custom_text}\n"
    rendered_section += "\n"
    return text[:section_start] + rendered_section + text[section_end:]


def plan_consumer_entry(repo_root: Path, template_path: Path) -> EntryPlan:
    root = Path(os.path.abspath(os.path.normpath(str(repo_root))))
    path = root / "AGENTS.md"
    managed_block, template_section = _template_contract(template_path)
    if not os.path.lexists(path):
        return EntryPlan("missing", path, reason="AGENTS.md 不存在")
    if path.is_symlink():
        return EntryPlan("unsafe", path, reason="AGENTS.md 是 symlink，拒绝自动写入")
    if not path.is_file():
        return EntryPlan("unsafe", path, reason="AGENTS.md 不是普通文件")
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return EntryPlan("unreadable", path, reason="AGENTS.md 无法按 UTF-8 读取")

    start_count = text.count(START_MARKER)
    end_count = text.count(END_MARKER)
    if start_count or end_count:
        span = _marked_span(text)
        if span is None:
            return EntryPlan("unsafe", path, reason="PMAI Startup 托管标记重复、缺失或顺序错误")
        section_span = _single_section(text, "## Startup")
        if section_span is None or span[0] < section_span[0] or span[1] > section_span[1]:
            return EntryPlan("unsafe", path, reason="PMAI Startup 托管区块不在唯一的 ## Startup 章节内")
        current_block = text[span[0] : span[1]]
        if current_block == managed_block:
            return EntryPlan("current", path, strategy="managed_block", current_text=text)
        rendered = text[: span[0]] + managed_block + text[span[1] :]
        return EntryPlan(
            "stale",
            path,
            strategy="managed_block",
            current_text=text,
            rendered_text=rendered,
        )

    try:
        rendered = _legacy_rendered_text(text, template_section)
    except ConsumerEntryError as exc:
        return EntryPlan("unsafe", path, reason=str(exc), current_text=text)
    return EntryPlan(
        "stale",
        path,
        strategy="legacy_migration",
        current_text=text,
        rendered_text=rendered,
    )
