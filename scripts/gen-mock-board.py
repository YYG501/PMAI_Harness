#!/usr/bin/env python3
"""gen-mock-board.py — 从变体清单生成 mock 看版导航页

设计真相源：「分档运行与沉淀层」设计 §1.3（四叉已拍定）。

核心纪律：
  - `<repo>/mocks/manifest.json` 是变体清单，**唯一真相源**。
  - `<repo>/mocks/index.html` 是**纯生成物**，永远不手改 —— 改 manifest.json 再重生成。
  - 看版按状态分组：活跃 / 待合并 高亮在上；已退役 折叠灰显在下（<details>）。
  - featured 变体视觉突出。
  - 每条渲染 5 字段；路径渲染成可点的相对链接（点开能看那个 mock）。

用法：
  python3 scripts/gen-mock-board.py <repo_root>

  默认读 <repo_root>/mocks/manifest.json，写 <repo_root>/mocks/index.html。
  manifest 不存在或无变体 → 生成"暂无变体"的空看版，不报错（exit 0）。

manifest schema（每条变体）：
  path        相对 mocks/ 的路径（可点开的 mock 文件 / 目录）
  explores    探索什么（一句话）
  good_parts  好东西 / 可合并候选（一句话）
  status      状态：活跃 / 待合并 / 已退役
  round       出自哪轮（探索轮次 / req 标识）
  featured    bool，是否值得留的精选版（看版高亮）
  retired_note  可选，状态=已退役 时记"已并入主原型(位置/commit)"

纯标准库，无第三方依赖。
"""
import argparse
import html
import json
import sys
from pathlib import Path


# 状态枚举（设计 §1.3 拍定）。活跃 / 待合并 进高亮区，已退役 进折叠区。
STATUS_ACTIVE = "活跃"
STATUS_PENDING_MERGE = "待合并"
STATUS_RETIRED = "已退役"

# 高亮区状态顺序（待合并排在活跃前 —— 待合并是更接近沉淀的状态，先看）
HIGHLIGHT_ORDER = [STATUS_PENDING_MERGE, STATUS_ACTIVE]

GENERATED_BANNER = (
    "本文件由 scripts/gen-mock-board.py 从 mocks/manifest.json 生成。"
    "勿手改 —— 改 manifest.json 再重新生成。"
)


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


def render_variant_card(variant: dict) -> str:
    """渲染单条变体卡片（5 字段 + 可点路径 + featured 标记）。"""
    path = variant.get("path") or ""
    featured = _is_featured(variant)
    status = variant.get("status") or ""

    card_classes = ["variant-card"]
    if featured:
        card_classes.append("featured")
    if status == STATUS_RETIRED:
        card_classes.append("retired")

    featured_badge = '<span class="badge badge-featured">★ 精选</span>' if featured else ""
    status_badge = (
        f'<span class="badge badge-status status-{_status_slug(status)}">{_esc(status)}</span>'
        if status
        else ""
    )

    # 路径渲染成可点链接（相对 mocks/，点开能看那个 mock）。无 path → 纯文本占位。
    if path:
        path_html = f'<a class="variant-path" href="{_esc_attr(path)}">{_esc(path)}</a>'
    else:
        path_html = '<span class="variant-path variant-path-missing">（未登记路径）</span>'

    retired_note = ""
    if status == STATUS_RETIRED and variant.get("retired_note"):
        retired_note = (
            f'<div class="field retired-note">'
            f'<span class="field-label">退役说明</span>'
            f'<span class="field-value">{_field(variant, "retired_note")}</span></div>'
        )

    return f"""        <article class="{' '.join(card_classes)}">
          <header class="variant-head">
            {path_html}
            <span class="badges">{status_badge}{featured_badge}</span>
          </header>
          <div class="field"><span class="field-label">探索什么</span><span class="field-value">{_field(variant, "explores")}</span></div>
          <div class="field"><span class="field-label">好东西</span><span class="field-value">{_field(variant, "good_parts")}</span></div>
          <div class="field"><span class="field-label">出自哪轮</span><span class="field-value">{_field(variant, "round")}</span></div>
{retired_note}        </article>"""


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


def render_board(data: dict, manifest_rel: str) -> str:
    """生成完整 index.html 文本。"""
    variants = [v for v in data.get("variants", []) if isinstance(v, dict)]
    highlight, retired, other = _split_by_status(variants)
    active_like = highlight + other  # 未知状态也当"非退役"放上面（不静默吞）

    total = len(variants)
    parse_error = data.get("_parse_error")

    if total == 0:
        body = _render_empty(parse_error)
    else:
        sections = []
        if active_like:
            cards = "\n".join(render_variant_card(v) for v in active_like)
            sections.append(
                f'      <section class="group group-active">\n'
                f'        <h2>活跃 · 待合并 <span class="count">{len(active_like)}</span></h2>\n'
                f"{cards}\n"
                f"      </section>"
            )
        else:
            sections.append(
                '      <section class="group group-active">\n'
                '        <h2>活跃 · 待合并 <span class="count">0</span></h2>\n'
                '        <p class="empty-note">暂无活跃 / 待合并变体。</p>\n'
                "      </section>"
            )
        if retired:
            cards = "\n".join(render_variant_card(v) for v in retired)
            sections.append(
                f'      <section class="group group-retired">\n'
                f'        <details>\n'
                f'          <summary>已退役 <span class="count">{len(retired)}</span>（留存可翻，不进活跃高亮）</summary>\n'
                f"{cards}\n"
                f"        </details>\n"
                f"      </section>"
            )
        body = "\n".join(sections)

    return _html_shell(body, total, manifest_rel)


def _render_empty(parse_error: bool) -> str:
    note = ""
    if parse_error:
        note = (
            '        <p class="parse-error">⚠️ manifest.json 解析失败（JSON 语法错误），'
            "已按空看版渲染。修好 manifest.json 再重新生成。</p>\n"
        )
    return (
        '      <section class="group group-empty">\n'
        f"{note}"
        '        <p class="empty-note">暂无变体。<br>'
        "探索期生成 mock 后，往 <code>manifest.json</code> 加一条、"
        "重跑 <code>gen-mock-board.py</code>，这里就会列出来。</p>\n"
        "      </section>"
    )


def _html_shell(body: str, total: int, manifest_rel: str) -> str:
    return f"""<!DOCTYPE html>
<!--
  {GENERATED_BANNER}
-->
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mock 变体看版</title>
<style>
  :root {{
    --bg: #f6f7f9;
    --card: #ffffff;
    --ink: #1f2328;
    --muted: #6a737d;
    --line: #e1e4e8;
    --accent: #2563eb;
    --featured: #f59e0b;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 2rem 1.5rem; background: var(--bg); color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC",
                 "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
    line-height: 1.55; max-width: 960px; margin-inline: auto;
  }}
  header.board-head {{ margin-bottom: 1.5rem; }}
  header.board-head h1 {{ margin: 0 0 .35rem; font-size: 1.5rem; }}
  header.board-head .sub {{ color: var(--muted); font-size: .9rem; }}
  header.board-head .sub code {{
    background: #eef0f2; padding: .05rem .35rem; border-radius: 4px; font-size: .85em;
  }}
  .group {{ margin-bottom: 2rem; }}
  .group h2 {{ font-size: 1.05rem; border-bottom: 2px solid var(--line); padding-bottom: .4rem; }}
  .group-active h2 {{ border-bottom-color: var(--accent); }}
  .count {{
    display: inline-block; min-width: 1.4em; text-align: center;
    background: var(--line); color: var(--muted); border-radius: 999px;
    font-size: .8rem; padding: 0 .45em; margin-left: .35rem; vertical-align: middle;
  }}
  details > summary {{
    cursor: pointer; font-size: 1.05rem; font-weight: 600; color: var(--muted);
    padding: .4rem 0; border-bottom: 2px solid var(--line); list-style: revert;
  }}
  details[open] > summary {{ margin-bottom: 1rem; }}
  .variant-card {{
    background: var(--card); border: 1px solid var(--line); border-radius: 10px;
    padding: 1rem 1.1rem; margin-top: 1rem;
  }}
  .variant-card.featured {{
    border-color: var(--featured); border-left-width: 5px;
    box-shadow: 0 1px 4px rgba(245,158,11,.18);
  }}
  .variant-card.retired {{ opacity: .62; background: #fafbfc; }}
  .variant-head {{
    display: flex; align-items: baseline; justify-content: space-between;
    gap: .75rem; flex-wrap: wrap; margin-bottom: .6rem;
  }}
  .variant-path {{ font-weight: 600; font-size: 1rem; color: var(--accent); text-decoration: none; word-break: break-all; }}
  .variant-path:hover {{ text-decoration: underline; }}
  .variant-path-missing {{ color: var(--muted); font-style: italic; }}
  .badges {{ display: inline-flex; gap: .4rem; flex-shrink: 0; }}
  .badge {{ font-size: .72rem; padding: .12rem .5rem; border-radius: 999px; white-space: nowrap; }}
  .badge-featured {{ background: var(--featured); color: #fff; }}
  .badge-status {{ border: 1px solid var(--line); color: var(--muted); }}
  .badge-status.status-active {{ background: #dcfce7; border-color: #86efac; color: #166534; }}
  .badge-status.status-pending {{ background: #dbeafe; border-color: #93c5fd; color: #1e40af; }}
  .badge-status.status-retired {{ background: #f3f4f6; color: #6b7280; }}
  .field {{ display: flex; gap: .6rem; font-size: .9rem; padding: .15rem 0; }}
  .field-label {{ flex-shrink: 0; width: 5em; color: var(--muted); }}
  .field-value {{ color: var(--ink); }}
  .retired-note .field-label {{ width: 5em; }}
  .empty-note {{ color: var(--muted); background: var(--card); border: 1px dashed var(--line);
    border-radius: 10px; padding: 1.5rem; text-align: center; }}
  .empty-note code {{ background: #eef0f2; padding: .05rem .35rem; border-radius: 4px; }}
  .parse-error {{ color: #b91c1c; background: #fef2f2; border: 1px solid #fecaca;
    border-radius: 8px; padding: .75rem 1rem; }}
</style>
</head>
<body>
  <header class="board-head">
    <h1>Mock 变体看版</h1>
    <p class="sub">探索期并行原型集 · 共 {total} 个变体 · 真相源 <code>{_esc(manifest_rel)}</code>（本页自动生成，勿手改）</p>
  </header>
{body}
</body>
</html>
"""


def main():
    parser = argparse.ArgumentParser(
        description="从 mocks/manifest.json 生成 mocks/index.html 看版导航页"
    )
    parser.add_argument("repo_root", help="项目根目录（读 <repo_root>/mocks/manifest.json）")
    parser.add_argument(
        "--manifest",
        default=None,
        help="覆盖 manifest 路径（默认 <repo_root>/mocks/manifest.json）",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="覆盖输出路径（默认 <repo_root>/mocks/index.html）",
    )
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    mocks_dir = repo_root / "mocks"
    manifest_path = Path(args.manifest).resolve() if args.manifest else mocks_dir / "manifest.json"
    out_path = Path(args.out).resolve() if args.out else mocks_dir / "index.html"

    data = load_manifest(manifest_path)

    # 机器关口：变体若用了非英文 key（如中文「路径/探索什么」），这里只认英文 key →
    # 会被静默渲染成"—"占位。检测"既无 path 又无任何已知英文 key"的条目并 stderr 报警，
    # 不静默吞（防结构化底料漂移，见 memory build_fidelity_two_causes）。
    _KNOWN_KEYS = {"path", "explores", "good_parts", "status", "round", "featured", "retired_note"}
    _suspect = [
        i
        for i, v in enumerate(data.get("variants", []))
        if isinstance(v, dict) and v and not (_KNOWN_KEYS & set(v.keys()))
    ]
    if _suspect:
        print(
            f"⚠️ manifest.json：第 {_suspect} 条变体没有任何已知英文 key"
            f"（应为 path/explores/good_parts/status/round/featured）——"
            f"可能误用了中文 key，会渲染成空。请改成英文 key。",
            file=sys.stderr,
        )

    # 看版页与 manifest 同在 mocks/ 时，引用名用 manifest.json；否则用相对/绝对名
    try:
        manifest_rel = manifest_path.relative_to(out_path.parent).as_posix()
    except ValueError:
        manifest_rel = manifest_path.name

    board_html = render_board(data, manifest_rel)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(board_html, encoding="utf-8")

    n = len([v for v in data.get("variants", []) if isinstance(v, dict)])
    print(f"✅ 看版已生成: {out_path}（{n} 个变体）")


if __name__ == "__main__":
    main()
