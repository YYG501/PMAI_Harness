#!/usr/bin/env python3
"""publish-to-lark: 把本地 markdown 发布到飞书云文档，自动合并表格相同内容 cell。

由 spec-writing 等 skill 调用，PM 也可手动运行。详细行为见
skills/publish-to-lark/SKILL.md。

所有 `lark-cli` 子进程调用走 `scripts/_lib/lark_adapter.py`（v3 §1 #1 实施）；
本文件保留业务编排：parse_frontmatter / target resolution / 表格 merge_cells。
不要再直接 spawn `lark-cli` —— lint 会拦截。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

# 让 _lib 可以 import（publish-to-lark.py 自身在 scripts/，_lib 是同级子目录）
_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.lark_adapter import (  # noqa: E402
    MIN_LARK_CLI_VERSION,
    LarkAdapterError,
    api_json,
    auth_check,
    auth_status,
    docs_create_from_markdown,
    docs_fetch,
    docs_update_from_markdown,
    markdown_body_hash,
    parse_frontmatter,
    version,
    write_frontmatter,
)

CONFIG_PATH = Path(".claude/lark-publish.json")


# ---------- 输出 ----------

def die(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def warn(msg: str) -> None:
    print(f"WARN: {msg}", file=sys.stderr)


def info(msg: str) -> None:
    print(msg)


# ---------- Preflight ----------

def preflight(target_kind: str | None, config_present: bool, args_complete: bool) -> None:
    # 1. lark-cli 在 PATH + 2. 版本检查
    try:
        ver = version()
    except LarkAdapterError as e:
        die("lark-cli 未安装或不可用。安装方式见 https://github.com/larksuite/lark-cli")
    if not ver:
        die("无法解析 lark-cli 版本输出")
    if ver < MIN_LARK_CLI_VERSION:
        ver_s = ".".join(str(x) for x in ver)
        min_s = ".".join(str(x) for x in MIN_LARK_CLI_VERSION)
        die(f"lark-cli 版本 {ver_s} 低于最低要求 {min_s}；请升级")

    # 3. 登录态
    ok, detail = auth_status()
    if not ok:
        die(f"飞书 CLI 未登录。运行 lark-cli auth login（详见 lark-shared skill）。详情: {detail}")

    # 4. scope 检查（lark-cli ≥1.0.27 使用精确子 scope 名称）
    scopes = ["docx:document:write_only"]
    if target_kind == "wiki":
        scopes.append("wiki:node:retrieve")
    elif target_kind == "folder":
        scopes.append("drive:file:upload")
    ok, detail = auth_check(scopes)
    if not ok:
        warn(f"auth check 报告缺少 scope: {','.join(scopes)}（可能是 CLI 升级后 token metadata 未刷新的误报）；"
             f"将继续执行，由实际 API 调用兜底。如真正缺权限请跑 lark-cli auth login --scope \"{' '.join(scopes)}\"。详情: {detail}")

    # 5. 配置或参数
    if not (config_present or args_complete):
        # 检测 templates/lark-publish.json.tmpl 是否存在,如果有 → 提供具体的 init 命令
        tmpl_candidates = [
            Path(".claude/templates/lark-publish.json.tmpl"),
            Path("templates/lark-publish.json.tmpl"),
        ]
        tmpl_path = next((p for p in tmpl_candidates if p.exists()), None)

        if tmpl_path:
            print("━━━ 配置缺失 ━━━", file=sys.stderr)
            print(f"  .claude/lark-publish.json 不存在,但模板 {tmpl_path} 已就位。", file=sys.stderr)
            print(f"  init 命令:", file=sys.stderr)
            print(f"    cp {tmpl_path} .claude/lark-publish.json", file=sys.stderr)
            print(f"    # 然后编辑 .claude/lark-publish.json,把 REPLACE_WITH_*_TOKEN 替换为真实 token", file=sys.stderr)
            print(f"  自动 cp 模板 (token 仍为占位符,需 PM 编辑填) ? [y/N] ", file=sys.stderr, end="")
            sys.stderr.flush()
            try:
                ans = input().strip().lower()
            except EOFError:
                ans = ""
            if ans in ("y", "yes"):
                Path(".claude").mkdir(exist_ok=True)
                import shutil
                shutil.copy(tmpl_path, ".claude/lark-publish.json")
                print(f"  ✓ 已 cp {tmpl_path} → .claude/lark-publish.json", file=sys.stderr)
                print(f"  ⚠️  下一步: 编辑 .claude/lark-publish.json 把 REPLACE_WITH_*_TOKEN 替换为真实", file=sys.stderr)
                print(f"     wiki node token / folder token,然后重新跑 publish-to-lark。", file=sys.stderr)
                die("init 完成。请编辑配置文件填 token 后重新跑。", code=2)
            else:
                die("已取消 init。请手工 cp 模板 + 填 token,或传 --target-token + --target-kind + --title。")
        else:
            die("配置缺失。复制 templates/lark-publish.json.tmpl 到 .claude/lark-publish.json 并填 token; "
                "或手动传 --target-token + --target-kind + --title")


# ---------- HTML 表格预检 ----------

_FENCE_RE = re.compile(r"```.*?```", re.DOTALL)


def warn_if_html_tables(text: str) -> None:
    """飞书 lark-cli 只认 GFM 管道表格（`| ... |`）；正文里裸 HTML `<table>` 会被
    压成纯文本——标签全剥掉、单元格内容黏成一段，表格行列结构彻底丢失。

    扫到就大声警告 + 给行号（先剔除 ``` 围栏代码块，避免代码示例里的 <table> 误报）。
    不阻断发布：旧 PRD 可能仍含 HTML 表格，硬拦会让它们发不出去；警告 + 行号
    确保 PM 看见、不再"悄悄塌掉"。新写的 PRD 一律用管道表格（见 spec-writing）。
    """
    masked = _FENCE_RE.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    hits = [i + 1 for i, line in enumerate(masked.splitlines())
            if "<table" in line.lower()]
    if not hits:
        return
    warn(f"检测到 {len(hits)} 处 HTML <table>（行 {', '.join(map(str, hits))}）。"
         f"飞书发布只支持 GFM 管道表格（| ... |）——HTML <table> 会被压成纯文本、"
         f"行列结构全丢。请改成管道表格：需要跨行合并的列首行写值、续行留空，发布时"
         f"自动合并；权限矩阵这类不该合并的表，表前加 <!-- lark:no-merge --> 标记。")


# ---------- no-merge 标记 ----------

_NO_MERGE_RE = re.compile(r"<!--.*?lark:no-merge.*?-->", re.IGNORECASE)


def _is_pipe_table_row(line: str) -> bool:
    """GFM 管道表格行：strip 后以 `|` 开头。"""
    return line.lstrip().startswith("|")


def parse_table_skip_flags(body: str) -> list[bool]:
    """按出现顺序扫 body 里的 GFM 管道表格，返回每张表「是否跳过合并」。

    一张表的紧邻上文（跳过空行）若含 `<!-- lark:no-merge -->` 注释 → True。
    用途：权限矩阵这类「数据表」——每个单元格（`✅` / 空）都是独立数据，
    空格表示「无权限」而非「上一行续行」，绝不能被启发式合并吞掉。作者在表前
    标注后，merge_cells_for_doc 原样跳过这张表。

    返回列表顺序 = body 里表格出现顺序；merge_cells_for_doc 按下标对齐文档侧
    table block（文档 block 顺序与 markdown 表格顺序一致）。
    """
    lines = body.splitlines()
    n = len(lines)
    flags: list[bool] = []
    i = 0
    while i < n:
        if _is_pipe_table_row(lines[i]):
            j = i - 1
            while j >= 0 and not lines[j].strip():
                j -= 1
            flags.append(j >= 0 and bool(_NO_MERGE_RE.search(lines[j])))
            while i < n and _is_pipe_table_row(lines[i]):
                i += 1
        else:
            i += 1
    return flags


# ---------- Review baseline ----------


def _document_from_fetch(payload: dict) -> dict:
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, dict):
        data = payload
    document = data.get("document") if isinstance(data, dict) else None
    return document if isinstance(document, dict) else {}


def _revision_id(value: object) -> int | None:
    try:
        return int(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


def _docx_token(value: object) -> str | None:
    text = str(value or "").strip()
    if "://" not in text:
        return None
    parts = [part for part in urlparse(text).path.split("/") if part]
    if "docx" not in parts:
        return None
    index = parts.index("docx")
    return parts[index + 1] if index + 1 < len(parts) else None


def capture_review_baseline(
    doc_id: str,
    body: str,
    *,
    written_revision: int | None,
) -> tuple[int | None, str]:
    """确认写入 revision 仍是当前版本，并绑定本次本地源正文 hash。"""
    source_hash = markdown_body_hash(body)
    if written_revision is None:
        warn(
            "写操作未返回可验证 revision；本次发布已成功，但不建立评审基线，"
            "避免把未知飞书版本与本地正文配成一对"
        )
        return None, source_hash
    try:
        document = _document_from_fetch(docs_fetch(doc_id))
        fetched_doc_id = str(document.get("document_id") or "")
        if fetched_doc_id != doc_id:
            raise LarkAdapterError(
                "validation",
                f"发布后回读返回了其它文档: expected={doc_id}, actual={fetched_doc_id or 'unknown'}",
            )
        fetched_revision = _revision_id(document.get("revision_id"))
        if fetched_revision != written_revision:
            raise LarkAdapterError(
                "concurrent_update",
                "发布后飞书 revision 已变化，可能发生了远端并发编辑",
            )
    except LarkAdapterError as exc:
        warn(f"未能记录飞书评审 revision；本次发布已成功，后续评审将按旧文档降级处理。详情: {exc}")
        return None, source_hash
    return written_revision, source_hash


def clear_review_baseline(markdown_path: Path, *, expected_text: str) -> None:
    """远端已可能部分写入时，清除不再可信的旧发布基线。"""
    try:
        frontmatter, body = parse_frontmatter(expected_text)
        next_frontmatter = dict(frontmatter)
        next_frontmatter.pop("lark_published_revision_id", None)
        next_frontmatter.pop("lark_published_source_hash", None)
        write_frontmatter(
            markdown_path,
            next_frontmatter,
            body,
            expected_text=expected_text,
        )
    except (LarkAdapterError, OSError) as exc:
        warn(f"远端更新不完整，且无法清除旧评审基线: {exc}")


# ---------- 配置 / 目标解析 ----------

def load_config():
    if not CONFIG_PATH.exists():
        return None
    try:
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        die(f"{CONFIG_PATH} JSON 解析失败: {e}")


def infer_module_from_path(markdown_path: Path) -> str | None:
    """Infer module slug from docs/modules/<module>/<doc>.md when frontmatter omits it."""
    parent = markdown_path.parent
    if parent.name and parent.parent.name == "modules":
        return parent.name
    return None


def render_title(template: str, fm: dict, markdown_path: Path) -> str:
    ctx = {**fm, "filename": markdown_path.stem}
    if not ctx.get("module"):
        module = infer_module_from_path(markdown_path)
        if module:
            ctx["module"] = module
    keys = re.findall(r"\{(\w+)\}", template)
    missing = [k for k in keys if k not in ctx or not ctx[k]]
    if missing:
        die(f"title_template {template!r} 占位符 {missing} 在 markdown frontmatter 中缺失；"
            f"请补 frontmatter 或手动 --title")
    return template.format(**{k: ctx[k] for k in keys})


def resolve_target(args, fm: dict, markdown_path: Path) -> dict:
    config = load_config()

    if args.target_token and args.target_kind:
        kind, token = args.target_kind, args.target_token
    elif args.type and config:
        defaults = (config.get("default_targets") or {}).get(args.type)
        if not defaults:
            die(f"配置 .claude/lark-publish.json 中没有 type='{args.type}' 的条目")
        kind, token = defaults["kind"], defaults["token"]
        if "REPLACE_WITH" in str(token):
            die(f"type='{args.type}' 的 token 还是模板占位符 {token}，请编辑 {CONFIG_PATH}")
    else:
        die("无法决定目标位置：用 --type + 配置文件，或同时传 --target-token + --target-kind")

    if args.title:
        title = args.title
    elif args.type and config:
        tpl = (config.get("default_targets") or {}).get(args.type, {}).get("title_template", "{filename}")
        title = render_title(tpl, fm, markdown_path)
    else:
        title = markdown_path.stem

    return {"kind": kind, "token": token, "title": title}


# ---------- 发布 ----------

def build_doc_url(doc_id: str) -> str:
    host = os.environ.get("LARK_DOCS_HOST", "feishu.cn")
    return f"https://{host}/docx/{doc_id}"


def publish_first_time(markdown_path: Path, target: dict):
    info(f"创建飞书文档: title={target['title']!r} kind={target['kind']}")
    try:
        data = docs_create_from_markdown(
            markdown_path,
            title=target["title"],
            target={"kind": target["kind"], "token": target["token"]},
        )
    except LarkAdapterError as e:
        die(f"lark-cli docs +create 失败: {e.detail}")

    inner = data.get("data") or {}
    doc_id = (
        inner.get("doc_id")                                          # ≥1.0.27
        or (inner.get("document") or {}).get("document_id")         # 旧版嵌套
        or (data.get("document") or {}).get("document_id")
        or data.get("document_id")
    )
    if not doc_id:
        die(f"无法从 lark-cli docs +create 返回提取 doc_id: {data}")

    url = inner.get("doc_url") or build_doc_url(doc_id)
    document = (
        inner.get("document")
        or data.get("document")
        or {}
    )
    revision = _revision_id(document.get("revision_id")) if isinstance(document, dict) else None
    info(f"文档已创建: {url}")
    return doc_id, url, revision


def publish_overwrite(
    markdown_path: Path,
    doc_id: str,
    *,
    expected_revision: int | None,
    expected_local_text: str,
):
    info(f"覆盖飞书文档: doc_id={doc_id}")
    try:
        if expected_revision is None:
            current = _document_from_fetch(docs_fetch(doc_id))
            if str(current.get("document_id") or "") != doc_id:
                raise LarkAdapterError("validation", "覆盖前回读返回了其它文档")
            expected_revision = _revision_id(current.get("revision_id"))
            if expected_revision is None:
                raise LarkAdapterError("validation", "覆盖前无法取得飞书 revision")
        if markdown_path.read_text(encoding="utf-8") != expected_local_text:
            raise LarkAdapterError(
                "concurrent_update",
                "覆盖前本地 markdown 已变化，拒绝发送混合版本",
            )
        update_result = docs_update_from_markdown(
            markdown_path,
            doc_id=doc_id,
            mode="overwrite",
            revision_id=expected_revision,
        )
    except LarkAdapterError as e:
        if e.kind == "incomplete_update":
            clear_review_baseline(markdown_path, expected_text=expected_local_text)
        die(f"lark-cli docs +update 失败: {e.detail}")
    update_document = _document_from_fetch(update_result or {})
    written_revision = _revision_id(update_document.get("revision_id"))
    return doc_id, build_doc_url(doc_id), written_revision


# ---------- Cell 合并 ----------

def lark_api(method: str, path: str, params: dict | None = None, data: dict | None = None):
    try:
        response = api_json(method, path, params=params, data=data)
    except LarkAdapterError as e:
        raise RuntimeError(f"lark-cli api {method} {path} failed: {e.detail}") from e
    if not isinstance(response, dict):
        raise RuntimeError(f"lark-cli api {method} {path} 返回的 JSON 顶层不是对象")
    code = response.get("code")
    if response.get("ok") is False or code not in (None, 0):
        raise RuntimeError(f"lark-cli api {method} {path} 返回失败 envelope: {response}")
    return response


def revisioned_lark_write(
    method: str,
    path: str,
    *,
    revision_id: int,
    data: dict,
    label: str,
) -> int:
    """用当前 revision 写一次，并只返回响应中可验证的新 revision。"""
    response = lark_api(
        method,
        path,
        params={"document_revision_id": revision_id},
        data=data,
    )
    response_data = response.get("data")
    next_revision = _revision_id(
        response_data.get("document_revision_id")
        if isinstance(response_data, dict)
        else None
    )
    if next_revision is None:
        raise RuntimeError(f"{label} 未返回 document_revision_id")
    if next_revision <= revision_id:
        raise RuntimeError(
            f"{label} 返回的 revision 未前进: before={revision_id}, after={next_revision}"
        )
    return next_revision


def get_all_blocks(doc_id: str) -> list[dict]:
    blocks: list[dict] = []
    page_token = None
    while True:
        params: dict = {"page_size": 500}
        if page_token:
            params["page_token"] = page_token
        resp = lark_api("GET", f"/open-apis/docx/v1/documents/{doc_id}/blocks", params=params)
        items = (resp.get("data") or {}).get("items") or []
        blocks.extend(items)
        page_token = (resp.get("data") or {}).get("page_token")
        if not page_token:
            break
    return blocks


TEXT_CONTAINERS = (
    "text", "heading1", "heading2", "heading3", "heading4", "heading5",
    "heading6", "heading7", "heading8", "heading9", "bullet", "ordered",
    "code", "quote", "todo", "callout",
)


def cell_text(block: dict, blocks_by_id: dict) -> str:
    parts: list[str] = []
    for key in TEXT_CONTAINERS:
        sec = block.get(key)
        if sec and "elements" in sec:
            for elem in sec["elements"]:
                tr = elem.get("text_run")
                if tr:
                    parts.append(tr.get("content", ""))
    for child_id in block.get("children", []) or []:
        child = blocks_by_id.get(child_id)
        if child:
            parts.append(cell_text(child, blocks_by_id))
    return "".join(parts).strip()


def find_merge_ranges(grid: list[list[str]], existing: set):
    """前 N-1 列（leading cols）的合并范围。非空 cell 吸收下方相同内容 cell + 下方空 cell（续行 rowspan 效果）。
    最后一列（需求描述）走 find_desc_group_ranges，不在此处理。"""
    ranges: list[dict] = []
    if not grid:
        return ranges
    rows = len(grid)
    cols = len(grid[0]) if rows else 0
    if cols < 1:
        return ranges
    leading_cols = cols - 1
    for col in range(leading_cols):
        run_start = 0
        while run_start < rows:
            if (run_start, col) in existing:
                run_start += 1
                continue
            content = grid[run_start][col]
            if not content:
                run_start += 1
                continue
            run_end = run_start + 1
            while (run_end < rows
                   and (run_end, col) not in existing
                   and (grid[run_end][col] == content or grid[run_end][col] == "")):
                run_end += 1
            if run_end - run_start > 1:
                ranges.append({
                    "row_start_index": run_start,
                    "row_end_index": run_end,
                    "column_start_index": col,
                    "column_end_index": col + 1,
                })
            run_start = run_end
    return ranges


def find_desc_group_ranges(grid: list[list[str]], existing: set):
    """末列（需求描述）的合并范围。row group = 锚点行（任一前 N-1 列非空）+ 下方所有续行（前 N-1 列全空）。
    单行 group 不合并；多行 group 才合并，需要先把内容合并到锚点 cell。"""
    ranges: list[dict] = []
    if not grid:
        return ranges
    rows = len(grid)
    cols = len(grid[0]) if rows else 0
    if cols < 2 or rows < 2:
        return ranges
    desc_col = cols - 1

    def is_continuation(r: int) -> bool:
        return all(grid[r][c] == "" for c in range(desc_col))

    group_start = 0
    for r in range(1, rows):
        if not is_continuation(r):
            if r - group_start > 1:
                ranges.append({
                    "row_start_index": group_start,
                    "row_end_index": r,
                    "column_start_index": desc_col,
                    "column_end_index": desc_col + 1,
                })
            group_start = r
    if rows - group_start > 1:
        ranges.append({
            "row_start_index": group_start,
            "row_end_index": rows,
            "column_start_index": desc_col,
            "column_end_index": desc_col + 1,
        })
    # 过滤掉与已有 merge_info 冲突的 range
    return [
        rng for rng in ranges
        if not any(
            (r, rng["column_start_index"]) in existing
            for r in range(rng["row_start_index"], rng["row_end_index"])
        )
    ]


# block_type 整数 → 类型特定字段名映射（Feishu docx block schema）
BLOCK_TYPE_TO_KEY: dict[int, str] = {
    2: "text",
    3: "heading1", 4: "heading2", 5: "heading3", 6: "heading4",
    7: "heading5", 8: "heading6", 9: "heading7", 10: "heading8",
    11: "heading9", 12: "bullet", 13: "ordered", 14: "code",
    15: "quote", 17: "todo", 19: "callout",
}


def block_to_creation_spec(block: dict) -> dict | None:
    """把读取到的 block 反序列化为 POST /children 接受的 creation spec。
    保留 block_type + 对应类型的内容字段（含 elements 富文本格式）；剥掉 block_id / parent_id / children。"""
    bt = block.get("block_type")
    if not bt:
        return None
    key = BLOCK_TYPE_TO_KEY.get(bt)
    if not key or key not in block:
        return None
    return {"block_type": bt, key: block[key]}


def get_cell_child_specs(cell_block: dict, blocks_by_id: dict) -> list[tuple[str, dict]]:
    """返回 cell 内所有可重建的子 block：(child_id, creation_spec)。"""
    out: list[tuple[str, dict]] = []
    for child_id in cell_block.get("children", []) or []:
        child = blocks_by_id.get(child_id)
        if not child:
            continue
        spec = block_to_creation_spec(child)
        if spec is not None:
            out.append((child_id, spec))
    return out


def merge_leading_with_clear(
    doc_id: str,
    table_block_id: str,
    cells_array: list,
    cols: int,
    blocks_by_id: dict,
    rng: dict,
    revision_id: int,
) -> int:
    """前 N-1 列合并:清空非锚点 cell children + merge_table_cells。

    飞书 merge_table_cells API 只设 row_span / col_span,被合并的非锚点 cell 内容仍存在,
    渲染时会叠加显示在锚点 cell。必须先 batch_delete 非锚点 cell 的 children,再 merge。

    与 merge_desc_group_with_content 区别:前 N-1 列锚点已有内容(且非锚点是相同 / 空),
    不需要拷贝 children 到锚点,直接清空非锚点即可。
    """
    start = rng["row_start_index"]
    end = rng["row_end_index"]
    col = rng["column_start_index"]

    # 1) 清空非锚点 cell 的 children (避免渲染叠加)
    for r in range(start + 1, end):
        non_anchor_id = cells_array[r * cols + col]
        non_anchor_cell = blocks_by_id.get(non_anchor_id)
        if not non_anchor_cell:
            continue
        count = len(non_anchor_cell.get("children", []) or [])
        if count == 0:
            continue
        revision_id = revisioned_lark_write(
            "DELETE",
            f"/open-apis/docx/v1/documents/{doc_id}/blocks/{non_anchor_id}/children/batch_delete",
            revision_id=revision_id,
            data={"start_index": 0, "end_index": count},
            label=f"清空 leading cell children cell={non_anchor_id}",
        )

    # 2) merge_table_cells
    return revisioned_lark_write(
        "PATCH",
        f"/open-apis/docx/v1/documents/{doc_id}/blocks/{table_block_id}",
        revision_id=revision_id,
        data={"merge_table_cells": rng},
        label=f"merge_table_cells (leading) range={rng}",
    )


def merge_desc_group_with_content(
    doc_id: str,
    table_block_id: str,
    cells_array: list,
    cols: int,
    blocks_by_id: dict,
    rng: dict,
    revision_id: int,
) -> int:
    """把 desc col row group 的非锚点 cell 的内容拷贝到锚点 cell，清空原 cell，再 merge。"""
    start = rng["row_start_index"]
    end = rng["row_end_index"]
    desc_col = rng["column_start_index"]

    anchor_cell_id = cells_array[start * cols + desc_col]
    anchor_cell = blocks_by_id.get(anchor_cell_id)
    if not anchor_cell:
        raise RuntimeError(f"找不到锚点 cell block: {anchor_cell_id}")

    # 1) 一次性收集所有非锚点 cell 的 child specs（含富文本 elements）
    all_specs: list[dict] = []
    cells_to_clear: list[tuple[str, int]] = []  # (cell_id, child_count)
    for r in range(start + 1, end):
        non_anchor_id = cells_array[r * cols + desc_col]
        non_anchor_cell = blocks_by_id.get(non_anchor_id)
        if not non_anchor_cell:
            continue
        child_specs = get_cell_child_specs(non_anchor_cell, blocks_by_id)
        if not child_specs:
            continue
        all_specs.extend(spec for _, spec in child_specs)
        cells_to_clear.append((non_anchor_id, len(non_anchor_cell.get("children", []) or [])))

    # 2) 锚点 cell 末尾追加所有非锚点的 children 拷贝（一次 POST）
    if all_specs:
        anchor_child_count = len(anchor_cell.get("children", []) or [])
        revision_id = revisioned_lark_write(
            "POST",
            f"/open-apis/docx/v1/documents/{doc_id}/blocks/{anchor_cell_id}/children",
            revision_id=revision_id,
            data={"children": all_specs, "index": anchor_child_count},
            label=f"拷贝 children 到锚点 cell={anchor_cell_id}",
        )

        # 3) 清空非锚点 cell 的 children（Feishu batch_delete = DELETE + start_index/end_index）
        for cell_id, count in cells_to_clear:
            if count == 0:
                continue
            revision_id = revisioned_lark_write(
                "DELETE",
                f"/open-apis/docx/v1/documents/{doc_id}/blocks/{cell_id}/children/batch_delete",
                revision_id=revision_id,
                data={"start_index": 0, "end_index": count},
                label=f"清空原 cell children cell={cell_id}",
            )

    # 4) merge_table_cells
    return revisioned_lark_write(
        "PATCH",
        f"/open-apis/docx/v1/documents/{doc_id}/blocks/{table_block_id}",
        revision_id=revision_id,
        data={"merge_table_cells": rng},
        label=f"merge_table_cells（需求描述列）range={rng}",
    )


def merge_cells_for_doc(
    doc_id: str,
    skip_flags: list[bool] | None,
    revision_id: int | None,
) -> tuple[int, int, int | None]:
    if revision_id is None:
        warn("写操作未返回 revision；跳过表格合并，避免在未知版本上继续写入")
        return 0, 1, None
    try:
        blocks = get_all_blocks(doc_id)
    except RuntimeError as e:
        warn(f"拉 block 列表失败: {e}；跳过合并步骤")
        return 0, 1, None

    blocks_by_id = {b["block_id"]: b for b in blocks}
    table_blocks = [b for b in blocks if "table" in b]

    # skip_flags 按下标对齐 markdown 表格顺序；数量对不上说明对齐不可靠 —— 弃用
    # 标记、按启发式合并所有表（content 不会丢，最坏只是该跳过的表被合并了）
    if skip_flags is not None and len(skip_flags) != len(table_blocks):
        warn(f"no-merge 标记数（{len(skip_flags)}）与文档表格数（{len(table_blocks)}）"
             f"不符，本次忽略 no-merge 标记")
        skip_flags = None

    success = 0
    failure = 0

    for idx, table in enumerate(table_blocks):
        if skip_flags is not None and skip_flags[idx]:
            continue
        prop = (table.get("table") or {}).get("property") or {}
        cells = (table.get("table") or {}).get("cells") or []
        rows = prop.get("row_size", 0)
        cols = prop.get("column_size", 0)
        if rows < 2 or cols < 1 or len(cells) < rows * cols:
            continue

        existing: set = set()
        for m in (prop.get("merge_info") or []):
            r0 = m.get("row_index", 0)
            c0 = m.get("column_index", 0)
            rs = m.get("row_span", 1) or 1
            cs = m.get("col_span", 1) or 1
            for r in range(r0, r0 + rs):
                for c in range(c0, c0 + cs):
                    existing.add((r, c))

        grid: list[list[str]] = []
        for r in range(rows):
            row: list[str] = []
            for c in range(cols):
                cell_id = cells[r * cols + c]
                cell_block = blocks_by_id.get(cell_id)
                row.append(cell_text(cell_block, blocks_by_id) if cell_block else "")
            grid.append(row)

        # 前 N-1 列:必须先清空非锚点 cell children, 再 merge_table_cells
        # 否则飞书 docx 渲染时 rowspan 内所有非锚点 cell 内容会叠加显示在锚点 cell
        cells_array = (table.get("table") or {}).get("cells") or []
        for rng in find_merge_ranges(grid, existing):
            try:
                revision_id = merge_leading_with_clear(
                    doc_id,
                    table["block_id"],
                    cells_array,
                    cols,
                    blocks_by_id,
                    rng,
                    revision_id,
                )
                success += 1
            except RuntimeError as exc:
                warn(f"表格合并写入失败，停止后续写入: {exc}")
                failure += 1
                return success, failure, None

        # 末列（需求描述）：续行 row group 需要先把 children 拷贝到锚点 cell 再 merge
        for rng in find_desc_group_ranges(grid, existing):
            try:
                revision_id = merge_desc_group_with_content(
                    doc_id,
                    table["block_id"],
                    cells_array,
                    cols,
                    blocks_by_id,
                    rng,
                    revision_id,
                )
                success += 1
            except RuntimeError as exc:
                warn(f"表格合并写入失败，停止后续写入: {exc}")
                failure += 1
                return success, failure, None

    return success, failure, revision_id


# ---------- Main ----------

def main() -> None:
    ap = argparse.ArgumentParser(prog="publish-to-lark",
                                 description="把本地 markdown 发布到飞书云文档")
    ap.add_argument("markdown", help="markdown 文件路径")
    ap.add_argument("--type", help="文档类型 (prd/spec/other)")
    ap.add_argument("--target-token", help="覆盖目标 token (wiki node 或 folder)")
    ap.add_argument("--target-kind", choices=["wiki", "folder"], help="目标位置类型")
    ap.add_argument("--title", help="覆盖标题")
    ap.add_argument("--no-merge-cells", action="store_true", help="跳过表格合并")
    args = ap.parse_args()

    md_path = Path(args.markdown).resolve()
    if not md_path.exists():
        die(f"markdown 文件不存在: {md_path}")

    text = md_path.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)
    warn_if_html_tables(text)
    filename = md_path.stem
    frontmatter_doc_id = fm.get("lark_doc_id")
    existing_url_token = _docx_token(fm.get("lark_doc_url"))
    if frontmatter_doc_id and existing_url_token and frontmatter_doc_id != existing_url_token:
        die(
            "frontmatter 的 lark_doc_id 与 lark_doc_url 指向不同文档，"
            "请先修正文档绑定再发布"
        )
    existing_doc_id = frontmatter_doc_id or existing_url_token

    args_complete = bool(args.target_token and args.target_kind and args.title)
    config_present = CONFIG_PATH.exists()

    target_kind_for_scope = args.target_kind
    if not target_kind_for_scope and args.type and config_present:
        cfg = load_config()
        target_kind_for_scope = ((cfg.get("default_targets") or {}).get(args.type) or {}).get("kind")
    if not target_kind_for_scope and existing_doc_id:
        target_kind_for_scope = "wiki"  # 覆盖路径，scope 至少包含 docx

    preflight(target_kind_for_scope, config_present, args_complete or bool(existing_doc_id))

    if existing_doc_id:
        info(f"检测到 frontmatter 中 lark_doc_id={existing_doc_id}，走覆盖路径")
        doc_id, url, written_revision = publish_overwrite(
            md_path,
            existing_doc_id,
            expected_revision=_revision_id(fm.get("lark_published_revision_id")),
            expected_local_text=text,
        )
        first_time = False
    else:
        target = resolve_target(args, fm, md_path)
        doc_id, url, written_revision = publish_first_time(md_path, target)
        first_time = True

    if args.no_merge_cells:
        info("跳过表格合并（--no-merge-cells）")
        merge_s, merge_f = 0, 0
    else:
        info("扫描表格 cell 合并...")
        merge_s, merge_f, written_revision = merge_cells_for_doc(
            doc_id,
            parse_table_skip_flags(body),
            written_revision,
        )
    baseline_revision, baseline_source_hash = capture_review_baseline(
        doc_id,
        body,
        written_revision=written_revision,
    )
    fm_written = False
    try:
        latest_text = md_path.read_text(encoding="utf-8")
        latest_fm, latest_body = parse_frontmatter(latest_text)
        latest_doc_id = latest_fm.get("lark_doc_id")
        latest_url_token = _docx_token(latest_fm.get("lark_doc_url"))
        identity_conflict = (
            (bool(latest_doc_id) and latest_doc_id != doc_id)
            or (bool(latest_url_token) and latest_url_token != doc_id)
        )
        if identity_conflict:
            warn(
                "发布期间本地文档绑定已变化，跳过 frontmatter 回填以免写到错误文档；"
                f"飞书侧文档已发布，URL={url}"
            )
        else:
            new_fm = dict(latest_fm)
            new_fm["lark_doc_id"] = doc_id
            if first_time:
                new_fm["lark_doc_url"] = url
                new_fm["lark_published_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
            if baseline_revision is not None and markdown_body_hash(latest_body) != baseline_source_hash:
                warn(
                    "发布后本地正文又发生变化；保留本地修改，但不把旧飞书 revision 与新正文绑定"
                )
                baseline_revision = None
            if baseline_revision is not None:
                new_fm["lark_published_revision_id"] = baseline_revision
                new_fm["lark_published_source_hash"] = baseline_source_hash
            else:
                # 新发布已经成功，旧基线不再代表当前发布点；清掉整对字段才能安全降级。
                new_fm.pop("lark_published_revision_id", None)
                new_fm.pop("lark_published_source_hash", None)
            write_frontmatter(md_path, new_fm, latest_body, expected_text=latest_text)
            fm_written = True
    except (LarkAdapterError, OSError) as e:
        warn(f"frontmatter 回写失败: {e}；飞书侧文档已发布，URL={url}，请手动回填")

    info("")
    info("飞书文档已发布")
    info(f"URL: {url}")
    info(f"合并 cell: 成功 {merge_s} 处 / 失败 {merge_f} 处")
    info(f"本地 frontmatter: {'已回填' if fm_written else '未更新 — 见上方警告'}")
    if baseline_revision is not None:
        info(f"评审基线: revision {baseline_revision} / source hash {baseline_source_hash[:12]}")


if __name__ == "__main__":
    main()
