#!/usr/bin/env python3
"""gen-mock-board.py — 从变体清单生成 mockup 看版（单页并排比稿画廊）

设计真相源：「分档运行与沉淀层」设计 §1.3（四叉已拍定）。

核心纪律：
  - `<repo>/mockups/manifest.json` 是变体清单，**唯一真相源**。
  - `<repo>/mockups/index.html` 是**纯生成物**，永远不手改 —— 改 manifest.json 再重生成。
  - 看版 = **单页比稿画廊**：各变体的画面**内联铺在同一页并排比**（图片嵌缩略图、
    HTML 嵌缩放预览），点击进入统一查看页；查看页带返回目录和打开页面入口。
  - 按“需求 → 轮次 → 方向”组织：最新需求和最新轮次优先，旧轮折叠。
  - 同一轮内 featured 方向排在前面；已退役方向仍折叠留存。
  - 新条目显示本轮目标、时间、核心做法、适用场景和主要取舍；旧条目兼容读取。

用法：
  python3 scripts/gen-mock-board.py <repo_root>

  默认读 <repo_root>/mockups/manifest.json，写 <repo_root>/mockups/index.html。
  manifest 不存在或无变体 → 生成"暂无变体"的空看版，不报错（exit 0）。

manifest schema（每条变体）：
  path        相对 mockups/ 的路径（图片 .png/.jpg/.webp/.svg 或页面 .html / 目录）
  explores    探索什么（一句话）
  good_parts  好东西 / 可合并候选（一句话）
  status      状态：活跃 / 待合并 / 已退役
  requirement 来自哪个需求 / 模块（看版按它分组；旧数据可从 round 兜底推断）
  title       可选，卡片标题
  round       出自哪轮（只表示探索轮次，不再承担需求分组）
  round_goal  本轮共同要判断的产品问题
  created_at  首次生成时间（ISO 8601）
  updated_at  最后修改时间（ISO 8601，排序依据）
  approach    核心做法
  best_for    适合什么判断或情境
  tradeoffs   主要取舍
  featured    bool，是否值得留的精选版（看版高亮）
  retired_note  可选，状态=已退役 时记"已并入主原型(位置/commit)"

纯标准库，无第三方依赖。
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import quote


# 状态枚举（设计 §1.3 拍定）。活跃 / 待合并 进高亮区，已退役 进折叠区。
STATUS_ACTIVE = "活跃"
STATUS_PENDING_MERGE = "待合并"
STATUS_RETIRED = "已退役"

# 内联预览：按扩展名判画面类型
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".avif"}
HTML_EXTS = {".html", ".htm"}
QUALITY_SCHEMA_VERSION = 2

GENERATED_BANNER = (
    "本文件由 scripts/gen-mock-board.py 从 mockups/manifest.json 生成。"
    "勿手改 —— 改 manifest.json 再重新生成。"
)

VIEWER_FILENAME = "viewer.html"


def load_manifest(manifest_path: Path) -> dict:
    """读 manifest.json。不存在 / 空 / 坏 JSON → 返回 {'variants': []}（不报错）。"""
    if not manifest_path.exists():
        return {"variants": []}
    raw = manifest_path.read_text(encoding="utf-8").strip()
    if not raw:
        return {"variants": []}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        # 坏 JSON 也降级成空看版（看版是导航页，不该因清单语法错而整页崩）
        return {"variants": [], "_parse_error": True}
    if not isinstance(data, dict):
        return {"variants": []}
    variants = data.get("variants")
    if not isinstance(variants, list):
        data["variants"] = []
    return data


def verify_current_quality(repo_root: Path, variants: list[dict]) -> None:
    """Fail before rendering when a schema-v2 variant lacks valid visual evidence."""
    checker = Path(__file__).resolve().with_name("mockup-quality.py")
    grouped: dict[tuple[str, str], set[str]] = {}
    for index, variant in enumerate(variants):
        if variant.get("schema_version") != QUALITY_SCHEMA_VERSION:
            continue
        required = ("path", "design_basis", "visual_audit")
        missing = [
            key
            for key in required
            if not isinstance(variant.get(key), str) or not variant[key].strip()
        ]
        if missing:
            raise RuntimeError(f"第 {index + 1} 条新版设计稿缺少质量字段：{', '.join(missing)}")
        grouped.setdefault(
            (variant["design_basis"].strip(), variant["visual_audit"].strip()),
            set(),
        ).add(f"mockups/{variant['path'].strip()}")

    if grouped and not checker.is_file():
        raise RuntimeError("mockup-quality.py 不存在，无法生成新版看版")
    for (basis, audit), paths in sorted(grouped.items()):
        command = [
            sys.executable,
            str(checker),
            "verify",
            "--repo",
            str(repo_root),
            "--contract",
            f"mockups/{basis}",
            "--report",
            f"mockups/{audit}",
        ]
        for path in sorted(paths):
            command.extend(["--variant", path])
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if result.returncode != 0:
            reason = (result.stderr or result.stdout).strip()
            raise RuntimeError(reason or "mockup 质量证据未通过")


def _esc(value) -> str:
    """转义成 HTML 文本（None / 缺字段 → 空串）。"""
    if value is None:
        return ""
    return html.escape(str(value))


def _esc_attr(value) -> str:
    """转义成 HTML 属性值。"""
    if value is None:
        return ""
    return html.escape(str(value), quote=True)


def _is_featured(variant: dict) -> bool:
    return bool(variant.get("featured"))


def _field(variant: dict, key: str) -> str:
    """取字段；缺失 / 空 → 占位破折号。"""
    val = variant.get(key)
    if val is None or (isinstance(val, str) and not val.strip()):
        return "—"
    return _esc(val)


def _raw_field(variant: dict, key: str) -> str:
    val = variant.get(key)
    if val is None:
        return ""
    if isinstance(val, str):
        return val.strip()
    return str(val).strip()


def _derive_requirement_from_round(round_value: str) -> str:
    """老清单只有 round 时，尽量从“宠物导入与创作第一轮”里提取需求名。"""
    value = (round_value or "").strip()
    if not value:
        return ""
    derived = re.sub(
        r"\s*第?\s*([0-9]+|[一二三四五六七八九十百]+)\s*轮\s*(探索|设计稿|方案)?\s*$",
        "",
        value,
    ).strip()
    if derived and derived != value:
        return derived
    if re.fullmatch(r"r\d+|round\s*\d+", value, flags=re.IGNORECASE):
        return ""
    return value


def _requirement_label(variant: dict) -> str:
    return (
        _raw_field(variant, "requirement")
        or _raw_field(variant, "module")
        or _derive_requirement_from_round(_raw_field(variant, "round"))
        or "未归类需求"
    )


def _round_label(variant: dict) -> str:
    round_value = _raw_field(variant, "round")
    if not round_value:
        return "轮次未记录"
    requirement = _requirement_label(variant)
    if requirement and round_value.startswith(requirement):
        suffix = round_value[len(requirement):].strip(" ：:-")
        if suffix:
            return suffix
    return round_value


def _card_title(variant: dict) -> str:
    explicit = _raw_field(variant, "title")
    if explicit:
        return explicit
    explores = _raw_field(variant, "explores")
    if explores:
        return explores
    path = _raw_field(variant, "path")
    if not path:
        return "未命名设计稿"
    name = Path(path.rstrip("/")).stem or Path(path.rstrip("/")).name
    return name or path


def _search_text(variant: dict) -> str:
    keys = [
        "requirement",
        "module",
        "title",
        "approach",
        "best_for",
        "tradeoffs",
        "feedback_note",
        "explores",
        "good_parts",
        "round_goal",
        "status",
        "round",
        "created_at",
        "updated_at",
        "path",
        "retired_note",
    ]
    return " ".join(_raw_field(variant, key) for key in keys if _raw_field(variant, key))


def _display_card_title(variant: dict) -> str:
    title = _card_title(variant)
    round_label = _round_label(variant)
    if title.startswith(round_label):
        title = title[len(round_label):].strip(" ：:-")
    title = re.sub(
        r"^(?:方案|方向)?\s*[A-Z](?:\d+)?\s*[：:]\s*",
        "",
        title,
        flags=re.IGNORECASE,
    ).strip()
    return title or _card_title(variant)


def _variant_letter(variant: dict, fallback_index: int) -> str:
    title = _card_title(variant)
    patterns = (
        r"(?:方案|方向)\s*([A-Z](?:\d+)?)",
        r"(?:第[^\s：:]+轮|r\d+|round\s*\d+)\s*([A-Z](?:\d+)?)\s*[：:]",
        r"^([A-Z](?:\d+)?)\s*[：:]",
    )
    for pattern in patterns:
        match = re.search(pattern, title, flags=re.IGNORECASE)
        if match:
            return match.group(1).upper()
    if fallback_index < 26:
        return chr(ord("A") + fallback_index)
    return str(fallback_index + 1)


def _parse_timestamp(value: str) -> datetime | None:
    raw = (value or "").strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _activity(variant: dict) -> tuple[datetime | None, str]:
    for key in ("updated_at", "created_at"):
        raw = _raw_field(variant, key)
        parsed = _parse_timestamp(raw)
        if parsed is not None:
            return parsed, raw
    return None, ""


def _latest_activity(variants: list[dict]) -> tuple[datetime | None, str]:
    candidates = [_activity(variant) for variant in variants]
    candidates = [candidate for candidate in candidates if candidate[0] is not None]
    if not candidates:
        return None, ""
    return max(candidates, key=lambda candidate: candidate[0].timestamp())


def _format_timestamp(value: str, *, short: bool = False) -> str:
    parsed = _parse_timestamp(value)
    if parsed is None:
        return "时间未记录"
    if short:
        return f"{parsed.month}月{parsed.day}日 {parsed:%H:%M}"
    return f"{parsed.year}年{parsed.month}月{parsed.day}日 {parsed:%H:%M}"


def _chinese_number(value: str) -> int | None:
    digits = {
        "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
        "六": 6, "七": 7, "八": 8, "九": 9,
    }
    if not value:
        return None
    if value.isdigit():
        return int(value)
    if value == "十":
        return 10
    if "十" in value:
        tens, ones = value.split("十", 1)
        tens_value = digits.get(tens, 1) if tens else 1
        ones_value = digits.get(ones, 0) if ones else 0
        return tens_value * 10 + ones_value
    return digits.get(value)


def _round_number(label: str) -> int | None:
    match = re.search(
        r"(?:第\s*)?([0-9]+|[一二三四五六七八九十]+)\s*轮|(?:r|round)\s*([0-9]+)",
        label or "",
        flags=re.IGNORECASE,
    )
    if not match:
        return None
    return _chinese_number(match.group(1) or match.group(2))


def _stable_id(prefix: str, label: str) -> str:
    slug = re.sub(
        r"[^\w\u4e00-\u9fff]+",
        "-",
        label,
        flags=re.UNICODE,
    ).strip("-").lower()
    if not slug:
        slug = hashlib.sha1(label.encode("utf-8")).hexdigest()[:10]
    return f"{prefix}-{slug[:80]}"


def _preview_kind(path: str) -> str:
    """据扩展名判内联预览方式：image / html / other（目录、无扩展名等）。"""
    ext = ("." + path.rsplit(".", 1)[1].lower()) if "." in path.rsplit("/", 1)[-1] else ""
    if ext in IMAGE_EXTS:
        return "image"
    if ext in HTML_EXTS:
        return "html"
    return "other"


def _viewer_href(path: str, title: str = "") -> str:
    """统一查看页地址。path/title 放 query，避免给每个变体生成独立壳页。"""
    href = f"{VIEWER_FILENAME}?path={quote(path or '', safe='')}"
    if title:
        href += f"&title={quote(title, safe='')}"
    return href


def _preview_html(path: str, title: str = "", *, eager: bool = False) -> str:
    """渲染卡片顶部的内联画面。图片→<img>；HTML→缩放 <iframe>；其它→占位。

    外层是指向统一查看页的 <a>（新标签打开），点画面后可返回目录。
    """
    if not path:
        return (
            '<div class="preview preview-missing"><span>（未登记路径）</span></div>'
        )
    href = _esc_attr(_viewer_href(path, title))
    source = _esc_attr(path)
    kind = _preview_kind(path)
    loading = "" if eager else ' loading="lazy"'
    if kind == "image":
        return (
            f'<a class="preview" href="{href}" target="_blank" rel="noopener" '
            f'title="点开看原图">'
            f'<img src="{source}"{loading} alt=""></a>'
        )
    if kind == "html":
        # iframe 缩放成缩略图；pointer-events:none 让外层 <a> 接住点击。
        return (
            f'<a class="preview preview-html" href="{href}" target="_blank" rel="noopener" '
            f'title="点开看完整页面">'
            f'<iframe src="{source}"{loading} tabindex="-1" scrolling="no"></iframe>'
            f'<span class="preview-html-hint">点开看完整稿</span></a>'
        )
    # 目录 / 未知类型：给个可点占位
    return (
        f'<a class="preview preview-other" href="{href}" target="_blank" rel="noopener">'
        f'<span>{_esc(path)}<br><small>点开查看</small></span></a>'
    )


def render_variant_card(variant: dict, *, letter: str, eager: bool = False) -> str:
    """渲染单条变体卡片：预览、核心做法、适用场景与主要取舍。"""
    path = variant.get("path") or ""
    featured = _is_featured(variant)
    status = variant.get("status") or ""
    title = _display_card_title(variant)
    approach = _raw_field(variant, "approach") or _raw_field(variant, "explores")
    best_for = _raw_field(variant, "best_for") or _raw_field(variant, "good_parts")
    tradeoffs = _raw_field(variant, "tradeoffs") or "未记录"
    feedback_note = _raw_field(variant, "feedback_note")

    card_classes = ["variant-card"]
    if featured:
        card_classes.append("featured")
    if status == STATUS_RETIRED:
        card_classes.append("retired")

    badges = []
    if featured:
        badges.append('<span class="badge badge-featured">已选</span>')
    status_badge = _status_badge(status)
    if status_badge:
        badges.append(status_badge)
    badge_html = f'<span class="badges">{"".join(badges)}</span>' if badges else ""

    if path:
        open_link = f'<a class="open-link" href="{_esc_attr(_viewer_href(path, title))}" target="_blank" rel="noopener">查看完整稿</a>'
    else:
        open_link = '<span class="open-link open-link-missing">未登记路径</span>'

    facts = [
        ("核心做法", approach or "未记录", ""),
        ("适合", best_for or "未记录", ""),
        ("主要取舍", tradeoffs, " tradeoff"),
    ]
    if feedback_note:
        facts.append(("PM 反馈", feedback_note, ""))
    facts_html = "".join(
        f'<div class="field"><span class="field-label">{label}</span>'
        f'<span class="field-value{extra_class}">{_esc(value)}</span></div>'
        for label, value, extra_class in facts
    )

    retired_note = ""
    if status == STATUS_RETIRED and variant.get("retired_note"):
        retired_note = (
            f'<div class="field retired-note">'
            f'<span class="field-label">归档说明</span>'
            f'<span class="field-value">{_field(variant, "retired_note")}</span></div>'
        )

    search_text = _search_text(variant)

    return f"""          <article class="{' '.join(card_classes)}" data-featured="{str(featured).lower()}" data-search-text="{_esc_attr(search_text)}">
            {_preview_html(path, title, eager=eager)}
            <div class="variant-body">
              <header class="variant-head">
                <div class="variant-title-wrap"><span class="variant-letter">{_esc(letter)}</span><h3>{_esc(title)}</h3></div>
                {badge_html}
              </header>
{facts_html}{retired_note}              <div class="card-actions">{open_link}</div>
            </div>
          </article>"""


def _status_badge(status: str) -> str:
    if status == STATUS_PENDING_MERGE:
        return '<span class="badge badge-status status-pending">准备纳入</span>'
    if status == STATUS_RETIRED:
        return '<span class="badge badge-status status-retired">已归档</span>'
    if status and status != STATUS_ACTIVE:
        return f'<span class="badge badge-status status-{_status_slug(status)}">{_esc(status)}</span>'
    return ""


def _status_slug(status: str) -> str:
    return {
        STATUS_ACTIVE: "active",
        STATUS_PENDING_MERGE: "pending",
        STATUS_RETIRED: "retired",
    }.get(status, "other")


def _group_by_requirement(variants: list[dict]) -> list[dict]:
    grouped: dict[str, dict] = {}
    for index, variant in enumerate(variants):
        label = _requirement_label(variant)
        group = grouped.setdefault(
            label,
            {"label": label, "variants": [], "indices": []},
        )
        group["variants"].append(variant)
        group["indices"].append(index)

    groups = list(grouped.values())
    for legacy_index, group in enumerate(groups, start=1):
        latest, raw = _latest_activity(group["variants"])
        group["latest"] = latest
        group["latest_raw"] = raw
        group["id"] = _stable_id("requirement", group["label"])
        group["legacy_index"] = legacy_index
        group["max_round"] = max(
            (_round_number(_round_label(variant)) or -1 for variant in group["variants"]),
            default=-1,
        )

    groups.sort(
        key=lambda group: (
            group["latest"] is not None,
            group["latest"].timestamp() if group["latest"] is not None else float("-inf"),
            max(group["indices"]),
            group["max_round"],
        ),
        reverse=True,
    )
    return groups


def _group_by_round(variants: list[dict]) -> list[dict]:
    grouped: dict[str, dict] = {}
    for index, variant in enumerate(variants):
        label = _round_label(variant)
        group = grouped.setdefault(
            label,
            {"label": label, "variants": [], "indices": []},
        )
        group["variants"].append(variant)
        group["indices"].append(index)

    groups = list(grouped.values())
    for group in groups:
        latest, raw = _latest_activity(group["variants"])
        group["latest"] = latest
        group["latest_raw"] = raw
        group["number"] = _round_number(group["label"])
        group["goal"] = next(
            (
                _raw_field(variant, "round_goal")
                for variant in group["variants"]
                if _raw_field(variant, "round_goal")
            ),
            "未记录",
        )

    groups.sort(
        key=lambda group: (
            group["latest"] is not None,
            group["latest"].timestamp() if group["latest"] is not None else float("-inf"),
            group["number"] is not None,
            group["number"] or -1,
            max(group["indices"]),
        ),
        reverse=True,
    )
    return groups


def render_board(data: dict, manifest_rel: str) -> str:
    """生成完整 index.html 文本。"""
    variants = [v for v in data.get("variants", []) if isinstance(v, dict)]
    groups = _group_by_requirement(variants)

    total = len(variants)
    parse_error = data.get("_parse_error")

    if total == 0:
        body = _render_empty(parse_error)
    else:
        sections = [
            _render_requirement_group(index, group)
            for index, group in enumerate(groups, start=1)
        ]
        body = "\n".join(sections)

    sidebar = _render_sidebar(groups)
    return _html_shell(body, total, manifest_rel, sidebar)


def _render_requirement_group(index: int, group: dict) -> str:
    label = group["label"]
    variants = group["variants"]
    group_id = group["id"]
    rounds = _group_by_round(variants)
    round_sections = "\n".join(
        _render_round(group_id, round_group, latest=round_index == 0)
        for round_index, round_group in enumerate(rounds)
    )
    latest_label = _format_timestamp(group["latest_raw"])
    return f'''      <section class="requirement-group" id="{_esc_attr(group_id)}" data-group="{_esc_attr(group_id)}" data-legacy-group="req-{group["legacy_index"]}" hidden>
        <header class="page-head">
          <div class="page-title">
            <h1>{_esc(label)}</h1>
            <div class="page-meta">{len(variants)} 版 · {len(rounds)} 轮 · 最近更新 {_esc(latest_label)}</div>
          </div>
          <div class="view-switch" role="group" aria-label="显示范围">
            <button class="active" type="button" data-mode="all">全部轮次</button>
            <button type="button" data-mode="selected">只看已选</button>
          </div>
        </header>
{round_sections}
        <p class="group-no-results" data-group-empty hidden>这个需求下没有匹配的方案</p>
      </section>'''


def _render_round(requirement_id: str, group: dict, *, latest: bool) -> str:
    variants = group["variants"]
    active = [variant for variant in variants if variant.get("status") != STATUS_RETIRED]
    retired = [variant for variant in variants if variant.get("status") == STATUS_RETIRED]
    active.sort(key=lambda variant: 0 if _is_featured(variant) else 1)
    retired.sort(key=lambda variant: 0 if _is_featured(variant) else 1)
    original_positions = {id(variant): index for index, variant in enumerate(variants)}

    cards = "\n".join(
        render_variant_card(
            variant,
            letter=_variant_letter(variant, original_positions[id(variant)]),
            eager=latest,
        )
        for variant in active
    )
    retired_cards = "\n".join(
        render_variant_card(
            variant,
            letter=_variant_letter(variant, original_positions[id(variant)]),
        )
        for variant in retired
    )
    round_id = f'{requirement_id}-{_stable_id("round", group["label"])}'
    latest_class = " latest" if latest else ""
    collapsed_class = "" if latest else " collapsed"
    latest_badge = '<span class="latest-label">最新</span>' if latest else ""
    action = "收起" if latest else "展开"
    expanded = "true" if latest else "false"
    content_parts = []
    if cards:
        content_parts.append(f'<div class="grid">\n{cards}\n          </div>')
    if retired_cards:
        content_parts.append(
            f'<details class="retired-drawer">\n'
            f'            <summary>已归档设计稿 <span class="count">{len(retired)}</span></summary>\n'
            f'            <div class="grid">\n{retired_cards}\n            </div>\n'
            f'          </details>'
        )
    content = "\n          ".join(content_parts)
    return f'''        <section class="round{latest_class}{collapsed_class}" id="{_esc_attr(round_id)}" data-round="{_esc_attr(group["label"])}">
          <header class="round-head">
            <div>
              <div class="round-title-row"><h2 class="round-title">{_esc(group["label"])}</h2>{latest_badge}</div>
              <div class="round-time">{_esc(_format_timestamp(group["latest_raw"]))}</div>
            </div>
            <button class="toggle-round" type="button" aria-label="{action}{_esc_attr(group["label"])}" aria-expanded="{expanded}">⌄</button>
            <p class="round-question"><strong>本轮要判断：</strong>{_esc(group["goal"])}</p>
          </header>
          <div class="round-content">
          {content}
          </div>
        </section>'''


def _render_sidebar(groups: list) -> str:
    if not groups:
        items = '<li class="nav-empty">暂无设计稿</li>'
    else:
        items = "\n".join(
            f'            <li data-nav-for="{_esc_attr(group["id"])}">'
            f'<a href="#{quote(group["id"], safe="-._~")}" data-requirement-link="{_esc_attr(group["id"])}">'
            f'<span class="requirement-row"><strong>{_esc(group["label"])}</strong><span>{len(group["variants"])} 版</span></span>'
            f'<small>{_esc(_format_timestamp(group["latest_raw"], short=True))}</small></a></li>'
            for group in groups
        )
    return f"""    <aside class="board-sidebar" aria-label="设计稿目录">
      <div class="sidebar-title"><span class="sidebar-mark">稿</span><strong>设计稿看板</strong></div>
      <label class="search-box">
        <span aria-hidden="true">⌕</span>
        <input type="search" data-search placeholder="搜索方案或轮次" autocomplete="off">
      </label>
      <div class="nav-label">最近更新</div>
      <nav>
        <ul>
{items}
        </ul>
      </nav>
      <p class="no-results" data-empty-results hidden>没有匹配的设计稿</p>
    </aside>"""


def _render_empty(parse_error: bool) -> str:
    note = ""
    if parse_error:
        note = (
            '        <p class="parse-error">设计稿清单解析失败，'
            "已按空看版渲染。修好清单后再刷新。</p>\n"
        )
    return (
        '      <section class="group group-empty">\n'
        f"{note}"
        '        <p class="empty-note">暂无设计稿。<br>'
        "出完设计稿后，这里会按需求自动归类。</p>\n"
        "      </section>"
    )


def _html_shell(body: str, total: int, manifest_rel: str, sidebar: str) -> str:
    return f"""<!DOCTYPE html>
<!--
  {GENERATED_BANNER}
-->
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>设计稿看板</title>
<style>
  :root {{
    --bg: #f4f5f7;
    --card: #ffffff;
    --ink: #14181d;
    --muted: #6a737d;
    --line: #e3e6ea;
    --line-soft: #eef0f2;
    --accent: #2563eb;
    --featured: #f59e0b;
    --preview-bg: #fbfcfd;
    --radius: 8px;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 0 2rem 2rem 0; background: var(--bg); color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
                 "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    line-height: 1.55;
  }}
  [hidden] {{ display: none !important; }}
  .board-shell {{
    max-width: none; margin: 0; display: grid;
    grid-template-columns: 250px minmax(0, 1fr); gap: 1.6rem; align-items: start;
  }}
  .board-sidebar {{
    position: sticky; top: 0; min-height: 100vh; background: var(--card);
    border: 1px solid var(--line); border-left: 0;
    border-radius: 0 var(--radius) var(--radius) 0;
    padding: 2rem 1rem 1rem; box-shadow: 0 1px 2px rgba(20,24,29,.04);
  }}
  .sidebar-title {{
    font-size: .85rem; font-weight: 700; color: var(--ink);
    margin-bottom: .8rem;
  }}
  .search-box {{ display: block; margin-bottom: 1rem; }}
  .search-box span {{
    display: block; color: var(--muted); font-size: .76rem; margin-bottom: .35rem;
  }}
  .search-box input {{
    width: 100%; height: 2.35rem; border: 1px solid var(--line);
    border-radius: var(--radius); padding: 0 .75rem; background: #fff;
    color: var(--ink); font: inherit; font-size: .88rem; outline: none;
  }}
  .search-box input:focus {{
    border-color: var(--accent); box-shadow: 0 0 0 3px rgba(37,99,235,.12);
  }}
  .board-sidebar ul {{ list-style: none; padding: 0; margin: 0; display: grid; gap: .25rem; }}
  .board-sidebar a {{
    display: flex; align-items: center; justify-content: space-between; gap: .75rem;
    min-height: 2.1rem; padding: .35rem .45rem; border-radius: 6px;
    color: var(--ink); text-decoration: none; font-size: .9rem;
  }}
  .board-sidebar a:hover {{ background: #eef3ff; color: var(--accent); }}
  .board-sidebar a span {{
    flex-shrink: 0; color: var(--muted); font-size: .74rem;
    background: var(--line-soft); border-radius: 999px; padding: .05rem .45rem;
  }}
  .nav-empty, .no-results {{ color: var(--muted); font-size: .86rem; margin: .5rem 0 0; }}
  .board-main {{ min-width: 0; max-width: 1260px; padding-top: 2rem; }}
  header.board-head {{ margin-bottom: 2rem; }}
  header.board-head h1 {{ margin: 0 0 .4rem; font-size: 1.6rem; letter-spacing: 0; }}
  header.board-head .sub {{ color: var(--muted); font-size: .9rem; }}
  .group {{ margin-bottom: 2.4rem; }}
  .requirement-head h2 {{
    font-size: 1.05rem; margin: 0 0 1.1rem; padding-bottom: .45rem;
    border-bottom: 2px solid var(--accent);
  }}
  .count {{
    display: inline-block; min-width: 1.4em; text-align: center;
    background: var(--line); color: var(--muted); border-radius: 999px;
    font-size: .8rem; padding: 0 .45em; margin-left: .35rem; vertical-align: middle;
  }}
  details > summary {{
    cursor: pointer; font-size: 1.05rem; font-weight: 600; color: var(--muted);
    padding: .45rem 0; border-bottom: 2px solid var(--line); list-style: revert;
    margin-bottom: 1.1rem;
  }}

  /* 单页并排画廊：自适应网格，各变体的画面摊在一页里比 */
  .grid {{
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
    gap: 1.4rem;
  }}

  .variant-card {{
    background: var(--card); border: 1px solid var(--line); border-radius: var(--radius);
    overflow: hidden; display: flex; flex-direction: column;
    box-shadow: 0 1px 2px rgba(20,24,29,.04);
    transition: box-shadow .15s ease, transform .15s ease;
  }}
  .variant-card:hover {{ box-shadow: 0 6px 22px rgba(20,24,29,.1); transform: translateY(-2px); }}
  .variant-card.featured {{
    border-color: var(--featured);
    box-shadow: 0 0 0 2px rgba(245,158,11,.28), 0 6px 22px rgba(245,158,11,.14);
  }}
  .variant-card.retired {{ opacity: .6; }}

  /* 内联画面区 */
  .preview {{
    display: block; height: 230px; background: var(--preview-bg);
    border-bottom: 1px solid var(--line-soft); position: relative; overflow: hidden;
    text-decoration: none; color: var(--muted);
  }}
  .preview img {{
    width: 100%; height: 100%; object-fit: contain; object-position: center; display: block;
  }}
  .preview-html iframe {{
    width: 1280px; height: 800px; border: 0; background: #fff;
    transform: scale(.34); transform-origin: top left; pointer-events: none;
  }}
  .preview-html-hint, .preview-missing span, .preview-other span {{
    position: absolute; left: 0; right: 0; bottom: 0;
    background: rgba(20,24,29,.62); color: #fff; font-size: .72rem;
    padding: .25rem .5rem; text-align: center;
  }}
  .preview-missing, .preview-other {{
    display: flex; align-items: center; justify-content: center; text-align: center;
    font-size: .85rem;
  }}
  .preview-missing span, .preview-other span {{
    position: static; background: none; color: var(--muted); padding: 0;
  }}
  .preview-other small {{ color: var(--accent); }}

  .variant-body {{ padding: .85rem 1rem 1rem; display: flex; flex-direction: column; gap: .1rem; }}
  .variant-head {{
    display: flex; align-items: flex-start; justify-content: space-between;
    gap: .6rem; flex-wrap: wrap; margin-bottom: .55rem;
  }}
  .variant-head h3 {{
    margin: 0; font-size: .98rem; line-height: 1.35; font-weight: 650; color: var(--ink);
  }}
  .badges {{ display: inline-flex; gap: .35rem; flex-shrink: 0; }}
  .badge {{ font-size: .7rem; padding: .12rem .5rem; border-radius: 999px; white-space: nowrap; }}
  .badge-featured {{ background: var(--featured); color: #fff; }}
  .badge-status {{ border: 1px solid var(--line); color: var(--muted); }}
  .badge-status.status-active {{ background: #dcfce7; border-color: #86efac; color: #166534; }}
  .badge-status.status-pending {{ background: #dbeafe; border-color: #93c5fd; color: #1e40af; }}
  .badge-status.status-retired {{ background: #f3f4f6; color: #6b7280; }}
  .badge-round {{ background: #eef0f2; color: var(--muted); }}
  .field {{ display: flex; gap: .55rem; font-size: .86rem; padding: .12rem 0; }}
  .field-label {{ flex-shrink: 0; width: 4.75em; color: var(--muted); }}
  .field-value {{ color: var(--ink); }}
  .card-actions {{ margin-top: .7rem; }}
  .open-link {{
    color: var(--accent); font-size: .86rem; font-weight: 600; text-decoration: none;
  }}
  .open-link:hover {{ text-decoration: underline; }}
  .open-link-missing {{ color: var(--muted); font-weight: 400; }}
  .empty-note {{ color: var(--muted); background: var(--card); border: 1px dashed var(--line);
    border-radius: var(--radius); padding: 1.8rem; text-align: center; }}
  .empty-note code {{ background: #eef0f2; padding: .05rem .35rem; border-radius: 4px; }}
  .parse-error {{ color: #b91c1c; background: #fef2f2; border: 1px solid #fecaca;
    border-radius: 8px; padding: .75rem 1rem; }}
  @media (max-width: 860px) {{
    body {{ padding: 1rem; }}
    .board-shell {{ display: block; }}
    .board-sidebar {{
      position: static; min-height: auto; margin-bottom: 1.2rem;
      border-left: 1px solid var(--line); border-radius: var(--radius); padding: 1rem;
    }}
    .board-main {{ max-width: none; padding-top: 0; }}
    .grid {{ grid-template-columns: 1fr; }}
  }}

  /* 轮次版看板：需求 → 轮次 → 方案。 */
  body {{
    min-width: 320px; padding: 0; font-family: "Avenir Next", "PingFang SC", "Microsoft YaHei", sans-serif;
    font-size: 14px; line-height: 1.6; letter-spacing: 0;
  }}
  button, input {{ font: inherit; letter-spacing: 0; }}
  .board-shell {{ min-height: 100vh; grid-template-columns: 260px minmax(0,1fr); gap: 0; }}
  .board-sidebar {{
    height: 100vh; min-height: 0; overflow-y: auto; padding: 28px 18px;
    background: #fbfbfc; border: 0; border-right: 1px solid var(--line); border-radius: 0; box-shadow: none;
  }}
  .sidebar-title {{ display: flex; align-items: center; gap: 10px; margin: 0 8px 24px; font-size: 16px; }}
  .sidebar-mark {{
    width: 26px; height: 26px; display: grid; place-items: center; border-radius: 6px;
    background: var(--ink); color: #fff; font-size: 12px; font-weight: 800;
  }}
  .search-box {{
    display: flex; align-items: center; gap: 8px; height: 38px; margin-bottom: 22px;
    padding: 0 11px; border: 1px solid var(--line); border-radius: 7px; background: var(--card);
  }}
  .search-box:focus-within {{ border-color: #8ea5df; box-shadow: 0 0 0 3px rgba(49,89,198,.1); }}
  .search-box > span {{ display: inline; margin: 0; color: #9299a3; }}
  .search-box input {{ width: 100%; height: auto; padding: 0; border: 0; border-radius: 0; outline: 0; background: transparent; }}
  .search-box input:focus {{ box-shadow: none; }}
  .nav-label {{ margin: 0 8px 8px; color: #9299a3; font-size: 11px; font-weight: 700; }}
  .board-sidebar ul {{ gap: 5px; }}
  .board-sidebar a {{
    display: grid; align-items: initial; min-height: 0; gap: 5px; padding: 10px 11px;
    border: 1px solid transparent; border-radius: 7px; color: var(--ink); font-size: 14px;
  }}
  .board-sidebar a:hover {{ background: #f0f2f5; color: var(--ink); }}
  .board-sidebar a.active {{ background: var(--card); border-color: var(--line); box-shadow: 0 1px 2px rgba(24,32,43,.04); }}
  .requirement-row {{ display: flex; justify-content: space-between; gap: 10px; color: var(--ink); }}
  .requirement-row > span {{ padding: 0; background: transparent; border-radius: 0; color: #9299a3; font-size: 12px; font-weight: 400; }}
  .board-sidebar small {{ color: #9299a3; font-size: 11px; }}
  .board-main {{ min-width: 0; width: 100%; max-width: 1460px; padding: 36px clamp(24px,4vw,64px) 80px; }}
  .page-head {{ display: flex; align-items: flex-end; justify-content: space-between; gap: 24px; margin-bottom: 32px; }}
  .page-title h1 {{ margin: 0 0 4px; font-size: clamp(25px,3vw,34px); line-height: 1.25; letter-spacing: 0; }}
  .page-meta {{ color: var(--muted); font-variant-numeric: tabular-nums; }}
  .view-switch {{ display: flex; flex-shrink: 0; padding: 3px; border-radius: 7px; background: #e9ecf0; }}
  .view-switch button {{
    min-height: 32px; padding: 0 12px; border: 0; border-radius: 5px;
    background: transparent; color: var(--muted); cursor: pointer;
  }}
  .view-switch button.active {{ background: var(--card); color: var(--ink); box-shadow: 0 1px 2px rgba(24,32,43,.08); }}
  .round {{ margin-bottom: 34px; border-top: 1px solid var(--line); }}
  .round.latest {{ margin-inline: -18px; padding-inline: 18px; border-top: 3px solid var(--ink); }}
  .round-head {{ display: grid; grid-template-columns: minmax(0,1fr) auto; gap: 12px 24px; padding: 18px 0 16px; }}
  .round-title-row {{ display: flex; align-items: center; flex-wrap: wrap; gap: 9px; }}
  .round-title {{ margin: 0; font-size: 19px; line-height: 1.35; }}
  .latest-label {{
    display: inline-flex; align-items: center; min-height: 23px; padding: 0 7px;
    border-radius: 5px; background: var(--ink); color: #fff; font-size: 11px; font-weight: 700;
  }}
  .round-time {{ margin-top: 3px; color: #9299a3; font-size: 12px; font-variant-numeric: tabular-nums; }}
  .round-question {{ grid-column: 1/-1; max-width: 880px; margin: 0; color: var(--muted); }}
  .round-question strong {{ color: var(--ink); font-weight: 650; }}
  .toggle-round {{
    width: 34px; height: 34px; display: grid; place-items: center; border: 1px solid var(--line);
    border-radius: 6px; background: var(--card); color: var(--muted); cursor: pointer;
  }}
  .round.collapsed .round-content {{ display: none; }}
  .round.collapsed .toggle-round {{ transform: rotate(-90deg); }}
  .grid {{ grid-template-columns: repeat(2,minmax(0,1fr)); gap: 18px; padding-bottom: 6px; }}
  .variant-card {{
    min-width: 0; border-radius: 8px; box-shadow: 0 1px 2px rgba(24,32,43,.04), 0 10px 28px rgba(24,32,43,.05);
    transition: none;
  }}
  .variant-card:hover {{ transform: none; box-shadow: 0 1px 2px rgba(24,32,43,.04), 0 10px 28px rgba(24,32,43,.05); }}
  .variant-card.featured {{ border-color: #88a0de; box-shadow: 0 1px 2px rgba(24,32,43,.04), 0 10px 28px rgba(24,32,43,.05); }}
  .preview {{ width: 100%; height: auto; aspect-ratio: 16/9; background: #eef0f3; }}
  .preview-html iframe {{ width: 400%; height: 400%; transform: scale(.25); }}
  .variant-body {{ padding: 17px 18px 16px; gap: 0; }}
  .variant-head {{ gap: 14px; min-height: 48px; margin-bottom: 14px; flex-wrap: nowrap; }}
  .variant-title-wrap {{ display: flex; align-items: flex-start; gap: 10px; min-width: 0; }}
  .variant-letter {{
    width: 27px; height: 27px; flex: 0 0 27px; display: grid; place-items: center;
    border: 1px solid #cbd0d7; border-radius: 6px; color: var(--muted); font-size: 12px; font-weight: 800;
  }}
  .featured .variant-letter {{ background: var(--accent); border-color: var(--accent); color: #fff; }}
  .variant-head h3 {{ margin: 1px 0 0; font-size: 16px; line-height: 1.45; overflow-wrap: anywhere; }}
  .badges {{ gap: 5px; }}
  .badge {{ min-height: 25px; display: inline-flex; align-items: center; padding: 0 8px; border-radius: 5px; font-size: 11px; font-weight: 700; }}
  .badge-featured {{ background: #eef2ff; color: var(--accent); }}
  .badge-status.status-pending {{ background: #eaf7f0; border-color: #b9ddca; color: #257a55; }}
  .field {{ display: grid; grid-template-columns: 74px minmax(0,1fr); gap: 12px; padding: 10px 0; border-top: 1px solid var(--line-soft); }}
  .field-label {{ width: auto; color: #9299a3; font-size: 12px; font-weight: 650; }}
  .field-value {{ color: #343a43; overflow-wrap: anywhere; }}
  .field-value.tradeoff {{ color: #a05d00; }}
  .card-actions {{ display: flex; justify-content: flex-end; margin: 0; padding-top: 12px; border-top: 1px solid var(--line-soft); }}
  .open-link {{ font-size: 13px; font-weight: 650; }}
  .retired-drawer {{ margin-top: 18px; }}
  .retired-drawer > summary {{ cursor: pointer; color: var(--muted); padding: 8px 0; border-bottom: 1px solid var(--line); }}
  .group-no-results {{ padding: 48px 0; color: var(--muted); text-align: center; }}

  @media (max-width: 980px) {{
    body {{ padding: 0; }}
    .board-shell {{ display: grid; grid-template-columns: 220px minmax(0,1fr); }}
    .board-sidebar {{ position: sticky; height: 100vh; margin: 0; padding-inline: 13px; border: 0; border-right: 1px solid var(--line); border-radius: 0; }}
    .board-main {{ padding-top: 36px; }}
    .grid {{ grid-template-columns: 1fr; }}
  }}
  @media (max-width: 720px) {{
    .board-shell {{ display: block; }}
    .board-sidebar {{ position: static; width: 100%; height: auto; padding: 16px; border-right: 0; border-bottom: 1px solid var(--line); }}
    .sidebar-title {{ margin: 0 0 14px; }}
    .search-box {{ margin-bottom: 14px; }}
    .nav-label {{ display: none; }}
    .board-sidebar ul {{ display: flex; overflow-x: auto; padding-bottom: 2px; }}
    .board-sidebar li {{ flex: 0 0 180px; }}
    .board-main {{ padding: 26px 16px 56px; }}
    .page-head {{ align-items: flex-start; flex-direction: column; }}
    .view-switch {{ align-self: stretch; }}
    .view-switch button {{ flex: 1; }}
    .round.latest {{ margin-inline: 0; padding-inline: 0; }}
    .field {{ grid-template-columns: 66px minmax(0,1fr); gap: 8px; }}
    .variant-head {{ flex-direction: column; min-height: 0; }}
    .badges {{ margin-left: 37px; }}
  }}
</style>
</head>
<body>
  <div class="board-shell">
{sidebar}
    <main class="board-main">
{body}
    </main>
  </div>
  <script>
    (() => {{
      const input = document.querySelector("[data-search]");
      if (!input) return;
      const groups = Array.from(document.querySelectorAll(".requirement-group"));
      const links = Array.from(document.querySelectorAll("[data-requirement-link]"));
      const empty = document.querySelector("[data-empty-results]");
      const normalize = (text) => (text || "").trim().toLowerCase();
      let activeMode = "all";
      let activeGroup = "";

      const groupFromHash = () => {{
        let raw = "";
        try {{ raw = decodeURIComponent(window.location.hash.slice(1)); }}
        catch (_) {{ raw = window.location.hash.slice(1); }}
        const direct = groups.find((group) => group.id === raw);
        if (direct) return direct.id;
        const legacy = groups.find((group) => group.dataset.legacyGroup === raw);
        return legacy ? legacy.id : "";
      }};

      const setActiveGroup = (groupId, updateHash = false) => {{
        activeGroup = groupId;
        groups.forEach((group) => {{ group.hidden = group.id !== activeGroup; }});
        links.forEach((link) => {{
          link.classList.toggle("active", link.dataset.requirementLink === activeGroup);
        }});
        if (updateHash && groupId) {{
          history.replaceState(null, "", `#${{encodeURIComponent(groupId)}}`);
        }}
      }};

      const applyFilter = () => {{
        const query = normalize(input.value);
        const visibleGroups = [];

        groups.forEach((group) => {{
          const cards = Array.from(group.querySelectorAll(".variant-card"));
          cards.forEach((card) => {{
            const haystack = normalize(card.dataset.searchText + " " + card.textContent);
            const matchesQuery = !query || haystack.includes(query);
            const matchesMode = activeMode === "all" || card.dataset.featured === "true";
            card.hidden = !(matchesQuery && matchesMode);
          }});
          group.querySelectorAll(".round").forEach((round) => {{
            const hasVisibleCard = !!round.querySelector(".variant-card:not([hidden])");
            round.hidden = !hasVisibleCard;
            if (query && hasVisibleCard) round.classList.remove("collapsed");
            round.querySelectorAll("details").forEach((details) => {{
              if (query && details.querySelector(".variant-card:not([hidden])")) details.open = true;
            }});
          }});
          const hasVisibleCard = !!group.querySelector(".variant-card:not([hidden])");
          if (hasVisibleCard) visibleGroups.push(group.id);
          const groupEmpty = group.querySelector("[data-group-empty]");
          if (groupEmpty) groupEmpty.hidden = hasVisibleCard;
          const navItem = document.querySelector(`[data-nav-for="${{group.dataset.group}}"]`);
          if (navItem) navItem.hidden = !hasVisibleCard;
        }});

        if (!visibleGroups.includes(activeGroup)) activeGroup = visibleGroups[0] || "";
        setActiveGroup(activeGroup);
        if (empty) empty.hidden = visibleGroups.length !== 0;
      }};

      document.querySelectorAll(".toggle-round").forEach((button) => {{
        button.addEventListener("click", () => {{
          const round = button.closest(".round");
          const collapsed = round.classList.toggle("collapsed");
          button.setAttribute("aria-expanded", String(!collapsed));
          button.setAttribute("aria-label", `${{collapsed ? "展开" : "收起"}}${{round.dataset.round}}`);
        }});
      }});

      document.querySelectorAll("[data-mode]").forEach((button) => {{
        button.addEventListener("click", () => {{
          activeMode = button.dataset.mode;
          document.querySelectorAll("[data-mode]").forEach((item) => {{
            item.classList.toggle("active", item.dataset.mode === activeMode);
          }});
          applyFilter();
        }});
      }});

      links.forEach((link) => {{
        link.addEventListener("click", (event) => {{
          event.preventDefault();
          setActiveGroup(link.dataset.requirementLink, true);
        }});
      }});

      activeGroup = groupFromHash() || (groups[0] && groups[0].id) || "";
      setActiveGroup(activeGroup);
      input.addEventListener("input", applyFilter);
      window.addEventListener("hashchange", () => {{
        const next = groupFromHash();
        if (next) setActiveGroup(next);
      }});
    }})();
  </script>
</body>
</html>
"""


def render_viewer() -> str:
    """生成统一查看页：所有卡片点进来都有返回目录和打开页面。"""
    return f"""<!DOCTYPE html>
<!--
  {GENERATED_BANNER}
-->
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>查看设计稿</title>
<style>
  :root {{
    --bg: #f4f5f7;
    --card: #ffffff;
    --ink: #14181d;
    --muted: #6a737d;
    --line: #e3e6ea;
    --accent: #2563eb;
    --danger: #b91c1c;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; background: var(--bg); color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
                 "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    min-height: 100vh; display: grid; grid-template-rows: auto 1fr;
  }}
  .viewer-bar {{
    position: sticky; top: 0; z-index: 10; min-height: 56px;
    display: flex; align-items: center; gap: .75rem; padding: .65rem 1rem;
    background: rgba(255,255,255,.96); border-bottom: 1px solid var(--line);
    box-shadow: 0 1px 2px rgba(20,24,29,.04);
  }}
  .viewer-title {{
    min-width: 0; flex: 1; font-size: .95rem; font-weight: 650;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }}
  .viewer-actions {{ display: inline-flex; gap: .5rem; flex-shrink: 0; }}
  .viewer-actions a {{
    display: inline-flex; align-items: center; min-height: 2.1rem;
    padding: 0 .75rem; border: 1px solid var(--line); border-radius: 6px;
    color: var(--ink); background: #fff; text-decoration: none; font-size: .86rem;
    font-weight: 600;
  }}
  .viewer-actions a.primary {{
    border-color: var(--accent); background: var(--accent); color: #fff;
  }}
  .viewer-actions a:hover {{ filter: brightness(.98); }}
  .stage {{
    min-height: 0; display: flex; align-items: stretch; justify-content: center;
    padding: 1rem;
  }}
  .stage iframe, .stage img {{
    width: 100%; height: calc(100vh - 88px); border: 1px solid var(--line);
    border-radius: 8px; background: #fff; box-shadow: 0 1px 2px rgba(20,24,29,.04);
  }}
  .stage img {{ object-fit: contain; padding: 1rem; }}
  .error {{
    margin: auto; max-width: 560px; background: #fff; border: 1px solid #fecaca;
    border-radius: 8px; padding: 1rem; color: var(--danger);
  }}
  @media (max-width: 680px) {{
    .viewer-bar {{ align-items: stretch; flex-direction: column; }}
    .viewer-actions {{ width: 100%; }}
    .viewer-actions a {{ flex: 1; justify-content: center; }}
    .stage {{ padding: .75rem; }}
    .stage iframe, .stage img {{ height: calc(100vh - 130px); }}
  }}
</style>
</head>
<body>
  <header class="viewer-bar">
    <div class="viewer-title" data-title>查看设计稿</div>
    <nav class="viewer-actions" aria-label="查看操作">
      <a href="index.html">返回目录</a>
      <a class="primary" href="#" target="_blank" rel="noopener" data-open>打开页面</a>
    </nav>
  </header>
  <main class="stage" data-stage></main>
  <script>
    (() => {{
      const params = new URLSearchParams(window.location.search);
      const path = (params.get("path") || "").trim();
      const title = (params.get("title") || "查看设计稿").trim();
      const stage = document.querySelector("[data-stage]");
      const titleNode = document.querySelector("[data-title]");
      const open = document.querySelector("[data-open]");
      const imageExt = /\\.(png|jpe?g|webp|gif|svg|avif)$/i;

      titleNode.textContent = title || "查看设计稿";

      const showError = (message) => {{
        stage.innerHTML = "";
        const box = document.createElement("div");
        box.className = "error";
        box.textContent = message;
        stage.appendChild(box);
        open.removeAttribute("href");
      }};

      if (!path || path.includes("..") || path.startsWith("/") || /^[a-z]+:/i.test(path)) {{
        showError("这个设计稿路径无效，请回到目录页重新打开。");
        return;
      }}

      open.href = path;
      if (imageExt.test(path)) {{
        const img = document.createElement("img");
        img.src = path;
        img.alt = title || "";
        stage.appendChild(img);
      }} else {{
        const frame = document.createElement("iframe");
        frame.src = path;
        frame.title = title || "设计稿";
        stage.appendChild(frame);
      }}
    }})();
  </script>
</body>
</html>
"""


def main():
    parser = argparse.ArgumentParser(
        description="从 mockups/manifest.json 生成 mockups/index.html 看版导航页"
    )
    parser.add_argument("repo_root", help="项目根目录（读 <repo_root>/mockups/manifest.json）")
    parser.add_argument(
        "--manifest",
        default=None,
        help="覆盖 manifest 路径（默认 <repo_root>/mockups/manifest.json）",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="覆盖输出路径（默认 <repo_root>/mockups/index.html）",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    mockups_dir = repo_root / "mockups"
    manifest_path = Path(args.manifest).resolve() if args.manifest else mockups_dir / "manifest.json"
    out_path = Path(args.out).resolve() if args.out else mockups_dir / "index.html"

    data = load_manifest(manifest_path)
    try:
        verify_current_quality(
            repo_root,
            [variant for variant in data.get("variants", []) if isinstance(variant, dict)],
        )
    except RuntimeError as exc:
        print(f"❌ 看版未生成：{exc}", file=sys.stderr)
        raise SystemExit(1) from exc

    # 机器关口：变体若用了非英文 key（如中文「路径/探索什么」），这里只认英文 key →
    # 会被静默渲染成"—"占位。检测"既无 path 又无任何已知英文 key"的条目并 stderr 报警，
    # 不静默吞（防结构化底料漂移，见 memory build_fidelity_two_causes）。
    _KNOWN_KEYS = {
        "path",
        "requirement",
        "module",
        "title",
        "approach",
        "best_for",
        "tradeoffs",
        "feedback_note",
        "explores",
        "good_parts",
        "status",
        "round",
        "round_goal",
        "created_at",
        "updated_at",
        "schema_version",
        "design_basis",
        "visual_audit",
        "featured",
        "retired_note",
    }
    _suspect = [
        i
        for i, v in enumerate(data.get("variants", []))
        if isinstance(v, dict) and v and not (_KNOWN_KEYS & set(v.keys()))
    ]
    if _suspect:
        print(
            f"⚠️ manifest.json：第 {_suspect} 条变体没有任何已知英文 key"
            f"（应为 path/requirement/title/approach/best_for/tradeoffs/"
            f"status/round/round_goal/created_at/updated_at/featured）——"
            f"可能误用了中文 key，会渲染成空。请改成英文 key。",
            file=sys.stderr,
        )

    # 看版页与 manifest 同在 mockups/ 时，引用名用 manifest.json；否则用相对/绝对名
    try:
        manifest_rel = manifest_path.relative_to(out_path.parent).as_posix()
    except ValueError:
        manifest_rel = manifest_path.name

    board_html = render_board(data, manifest_rel)
    viewer_html = render_viewer()

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(board_html, encoding="utf-8")
    viewer_path = out_path.parent / VIEWER_FILENAME
    viewer_path.write_text(viewer_html, encoding="utf-8")

    n = len([v for v in data.get("variants", []) if isinstance(v, dict)])
    print(f"✅ 看版已生成: {out_path}（{n} 个变体，含查看页 {viewer_path.name}）")


if __name__ == "__main__":
    main()
