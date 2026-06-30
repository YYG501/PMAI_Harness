#!/usr/bin/env python3
"""gen-mock-board.py — 从变体清单生成 mockup 看版（单页并排比稿画廊）

设计真相源：「分档运行与沉淀层」设计 §1.3（四叉已拍定）。

核心纪律：
  - `<repo>/mockups/manifest.json` 是变体清单，**唯一真相源**。
  - `<repo>/mockups/index.html` 是**纯生成物**，永远不手改 —— 改 manifest.json 再重生成。
  - 看版 = **单页比稿画廊**：各变体的画面**内联铺在同一页并排比**（图片嵌缩略图、
    HTML 嵌缩放预览），点击进入统一查看页；查看页带返回目录和打开页面入口。
  - 按需求分组：同一需求下的多版设计稿放在一起，避免跨需求混成一堆。
  - 每个需求内：活跃 / 待合并 放上面；已退役 折叠在下（<details>）。
  - featured 变体视觉突出。

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
  featured    bool，是否值得留的精选版（看版高亮）
  retired_note  可选，状态=已退役 时记"已并入主原型(位置/commit)"

纯标准库，无第三方依赖。
"""
import argparse
import html
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote


# 状态枚举（设计 §1.3 拍定）。活跃 / 待合并 进高亮区，已退役 进折叠区。
STATUS_ACTIVE = "活跃"
STATUS_PENDING_MERGE = "待合并"
STATUS_RETIRED = "已退役"

# 高亮区状态顺序（待合并排在活跃前 —— 待合并是更接近沉淀的状态，先看）
HIGHLIGHT_ORDER = [STATUS_PENDING_MERGE, STATUS_ACTIVE]

# 内联预览：按扩展名判画面类型
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".avif"}
HTML_EXTS = {".html", ".htm"}

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
        return ""
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
        "explores",
        "good_parts",
        "status",
        "round",
        "path",
        "retired_note",
    ]
    return " ".join(_raw_field(variant, key) for key in keys if _raw_field(variant, key))


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


def _preview_html(path: str, title: str = "") -> str:
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
    if kind == "image":
        return (
            f'<a class="preview" href="{href}" target="_blank" rel="noopener" '
            f'title="点开看原图">'
            f'<img src="{source}" loading="lazy" alt=""></a>'
        )
    if kind == "html":
        # iframe 缩放成缩略图；pointer-events:none 让外层 <a> 接住点击。
        return (
            f'<a class="preview preview-html" href="{href}" target="_blank" rel="noopener" '
            f'title="点开看完整页面">'
            f'<iframe src="{source}" loading="lazy" tabindex="-1" scrolling="no"></iframe>'
            f'<span class="preview-html-hint">点开看完整稿</span></a>'
        )
    # 目录 / 未知类型：给个可点占位
    return (
        f'<a class="preview preview-other" href="{href}" target="_blank" rel="noopener">'
        f'<span>{_esc(path)}<br><small>点开查看</small></span></a>'
    )


def render_variant_card(variant: dict) -> str:
    """渲染单条变体卡片：内联画面 + 方案标题 + 少量 PM 需要看的字段。"""
    path = variant.get("path") or ""
    featured = _is_featured(variant)
    status = variant.get("status") or ""
    title = _card_title(variant)
    explores = _raw_field(variant, "explores")
    good_parts = _raw_field(variant, "good_parts")
    round_label = _round_label(variant)

    card_classes = ["variant-card"]
    if featured:
        card_classes.append("featured")
    if status == STATUS_RETIRED:
        card_classes.append("retired")

    badges = []
    if featured:
        badges.append('<span class="badge badge-featured">已选方向</span>')
    status_badge = _status_badge(status)
    if status_badge:
        badges.append(status_badge)
    if round_label:
        badges.append(f'<span class="badge badge-round">{_esc(round_label)}</span>')
    badge_html = f'<span class="badges">{"".join(badges)}</span>' if badges else ""

    if path:
        open_link = f'<a class="open-link" href="{_esc_attr(_viewer_href(path, title))}" target="_blank" rel="noopener">查看完整稿</a>'
    else:
        open_link = '<span class="open-link open-link-missing">未登记路径</span>'

    direction = ""
    if explores and explores != title:
        direction = (
            f'<div class="field"><span class="field-label">方向</span>'
            f'<span class="field-value">{_esc(explores)}</span></div>'
        )

    good_parts_html = ""
    if good_parts:
        good_parts_html = (
            f'<div class="field"><span class="field-label">可取之处</span>'
            f'<span class="field-value">{_esc(good_parts)}</span></div>'
        )

    retired_note = ""
    if status == STATUS_RETIRED and variant.get("retired_note"):
        retired_note = (
            f'<div class="field retired-note">'
            f'<span class="field-label">归档说明</span>'
            f'<span class="field-value">{_field(variant, "retired_note")}</span></div>'
        )

    search_text = _search_text(variant)

    return f"""          <article class="{' '.join(card_classes)}" data-search-text="{_esc_attr(search_text)}">
            {_preview_html(path, title)}
            <div class="variant-body">
              <header class="variant-head">
                <h3>{_esc(title)}</h3>
                {badge_html}
              </header>
{direction}{good_parts_html}{retired_note}              <div class="card-actions">{open_link}</div>
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


def _split_by_status(variants: list):
    """分三堆：高亮区（活跃/待合并，按 HIGHLIGHT_ORDER 排）/ 已退役 / 其它未知状态。

    featured 在各自堆内排到前面（视觉突出）。
    """
    highlight = []
    retired = []
    other = []
    for v in variants:
        if not isinstance(v, dict):
            continue
        status = v.get("status")
        if status == STATUS_RETIRED:
            retired.append(v)
        elif status in HIGHLIGHT_ORDER:
            highlight.append(v)
        else:
            other.append(v)

    # 高亮区排序：先按状态枚举顺序（待合并 → 活跃），同状态内 featured 排前。
    # list.sort 稳定，所以同键的相对顺序保留 manifest 原序。
    def status_rank(v):
        try:
            return HIGHLIGHT_ORDER.index(v.get("status"))
        except ValueError:
            return len(HIGHLIGHT_ORDER)

    highlight.sort(key=lambda v: (status_rank(v), 0 if _is_featured(v) else 1))
    retired.sort(key=lambda v: (0 if _is_featured(v) else 1))
    return highlight, retired, other


def _group_by_requirement(variants: list):
    groups = []
    seen = {}
    for variant in variants:
        if not isinstance(variant, dict):
            continue
        label = _requirement_label(variant)
        if label not in seen:
            seen[label] = []
            groups.append((label, seen[label]))
        seen[label].append(variant)
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
            _render_requirement_group(index, label, group_variants)
            for index, (label, group_variants) in enumerate(groups, start=1)
        ]
        body = "\n".join(sections)

    sidebar = _render_sidebar(groups)
    return _html_shell(body, total, manifest_rel, sidebar)


def _render_requirement_group(index: int, label: str, variants: list) -> str:
    highlight, retired, other = _split_by_status(variants)
    active_like = highlight + other
    group_id = f"req-{index}"
    parts = [
        f'      <section class="group requirement-group" id="{group_id}" data-group="{_esc_attr(group_id)}">',
        '        <div class="requirement-head">',
        f'          <h2>{_esc(label)} <span class="count">{len(variants)} 版</span></h2>',
        "        </div>",
    ]
    if active_like:
        cards = "\n".join(render_variant_card(v) for v in active_like)
        parts.append(f'        <div class="grid">\n{cards}\n        </div>')
    if retired:
        cards = "\n".join(render_variant_card(v) for v in retired)
        parts.append(
            f'        <details class="retired-drawer">\n'
            f'          <summary>已归档设计稿 <span class="count">{len(retired)}</span></summary>\n'
            f'          <div class="grid">\n{cards}\n          </div>\n'
            f"        </details>"
        )
    parts.append("      </section>")
    return "\n".join(parts)


def _render_sidebar(groups: list) -> str:
    if not groups:
        items = '<li class="nav-empty">暂无设计稿</li>'
    else:
        items = "\n".join(
            f'            <li data-nav-for="req-{index}">'
            f'<a href="#req-{index}">{_esc(label)}'
            f'<span>{len(group_variants)}</span></a></li>'
            for index, (label, group_variants) in enumerate(groups, start=1)
        )
    return f"""    <aside class="board-sidebar" aria-label="设计稿目录">
      <div class="sidebar-title">目录</div>
      <label class="search-box">
        <span>搜索</span>
        <input type="search" data-search placeholder="输入方向、亮点或轮次" autocomplete="off">
      </label>
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
        '        <p class="empty-note">暂无变体。<br>'
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
</style>
</head>
<body>
  <div class="board-shell">
{sidebar}
    <main class="board-main">
      <header class="board-head">
        <h1>设计稿看板</h1>
        <p class="sub">这里收着 {total} 版设计稿。先按左侧需求定位，也可以直接搜索方案方向或亮点。</p>
      </header>
{body}
    </main>
  </div>
  <script>
    (() => {{
      const input = document.querySelector("[data-search]");
      if (!input) return;
      const cards = Array.from(document.querySelectorAll(".variant-card"));
      const groups = Array.from(document.querySelectorAll(".requirement-group"));
      const empty = document.querySelector("[data-empty-results]");
      const normalize = (text) => (text || "").trim().toLowerCase();

      const applyFilter = () => {{
        const query = normalize(input.value);
        let visibleCards = 0;

        cards.forEach((card) => {{
          const haystack = normalize(card.dataset.searchText + " " + card.textContent);
          const matched = !query || haystack.includes(query);
          card.hidden = !matched;
          if (matched) visibleCards += 1;
        }});

        groups.forEach((group) => {{
          const hasVisibleCard = !!group.querySelector(".variant-card:not([hidden])");
          group.hidden = !hasVisibleCard;
          const navItem = document.querySelector(`[data-nav-for="${{group.dataset.group}}"]`);
          if (navItem) navItem.hidden = !hasVisibleCard;
          group.querySelectorAll("details").forEach((details) => {{
            if (query && details.querySelector(".variant-card:not([hidden])")) {{
              details.open = true;
            }}
          }});
        }});

        if (empty) empty.hidden = visibleCards !== 0;
      }};

      input.addEventListener("input", applyFilter);
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

    # 机器关口：变体若用了非英文 key（如中文「路径/探索什么」），这里只认英文 key →
    # 会被静默渲染成"—"占位。检测"既无 path 又无任何已知英文 key"的条目并 stderr 报警，
    # 不静默吞（防结构化底料漂移，见 memory build_fidelity_two_causes）。
    _KNOWN_KEYS = {
        "path",
        "requirement",
        "module",
        "title",
        "explores",
        "good_parts",
        "status",
        "round",
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
            f"（应为 path/requirement/title/explores/good_parts/status/round/featured）——"
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
