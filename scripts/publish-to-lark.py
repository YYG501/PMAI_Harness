#!/usr/bin/env python3
"""publish-to-lark: 把本地 markdown 发布到飞书云文档，自动合并表格相同内容 cell。

由 prd-writing 等 skill 调用，PM 也可手动运行。详细行为见
skills/publish-to-lark/SKILL.md。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

MIN_LARK_CLI_VERSION = (1, 0, 27)
CONFIG_PATH = Path(".claude/lark-publish.json")


# ---------- 输出 ----------

def die(msg: str, code: int = 1) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def warn(msg: str) -> None:
    print(f"WARN: {msg}", file=sys.stderr)


def info(msg: str) -> None:
    print(msg)


# ---------- 子进程 ----------

def run(cmd: list[str], check: bool = True):
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError:
        die(f"命令未找到: {cmd[0]}")
    if check and res.returncode != 0:
        raise subprocess.CalledProcessError(res.returncode, cmd, res.stdout, res.stderr)
    return res


# ---------- Preflight ----------

def parse_version(s: str):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", s)
    if not m:
        return None
    return tuple(int(x) for x in m.groups())


def preflight(target_kind: str | None, config_present: bool, args_complete: bool) -> None:
    # 1. lark-cli 在 PATH + 2. 版本检查
    res = run(["lark-cli", "--version"], check=False)
    combined = (res.stdout or "") + (res.stderr or "")
    if res.returncode != 0 and not parse_version(combined):
        die("lark-cli 未安装或不可用。安装方式见 https://github.com/larksuite/lark-cli")
    ver = parse_version(combined)
    if not ver:
        die(f"无法解析 lark-cli 版本输出: {combined!r}")
    if ver < MIN_LARK_CLI_VERSION:
        ver_s = ".".join(str(x) for x in ver)
        min_s = ".".join(str(x) for x in MIN_LARK_CLI_VERSION)
        die(f"lark-cli 版本 {ver_s} 低于最低要求 {min_s}；请升级")

    # 3. 登录态
    res = run(["lark-cli", "auth", "status"], check=False)
    if res.returncode != 0:
        detail = (res.stderr or res.stdout or "").strip()
        die(f"飞书 CLI 未登录。运行 lark-cli auth login（详见 lark-shared skill）。详情: {detail}")

    # 4. scope 检查（lark-cli ≥1.0.27 使用精确子 scope 名称）
    scopes = ["docx:document:write_only"]
    if target_kind == "wiki":
        scopes.append("wiki:node:retrieve")
    elif target_kind == "folder":
        scopes.append("drive:file:upload")
    res = run(["lark-cli", "auth", "check", "--scope", " ".join(scopes)], check=False)
    if res.returncode != 0:
        detail = (res.stderr or res.stdout or "").strip()
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


# ---------- Frontmatter ----------

FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n?(.*)\Z", re.DOTALL)


def parse_frontmatter(text: str):
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    fm: dict[str, str] = {}
    for line in m.group(1).splitlines():
        line = line.rstrip()
        if not line or line.lstrip().startswith("#") or ":" not in line:
            continue
        k, v = line.split(":", 1)
        fm[k.strip()] = v.strip()
    return fm, m.group(2)


def write_frontmatter(path: Path, fm: dict, body: str) -> None:
    lines = ["---"]
    for k, v in fm.items():
        lines.append(f"{k}: {v}")
    lines.append("---")
    text = "\n".join(lines) + "\n" + (body if body.startswith("\n") else "\n" + body)
    path.write_text(text, encoding="utf-8")


# ---------- 配置 / 目标解析 ----------

def load_config():
    if not CONFIG_PATH.exists():
        return None
    try:
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        die(f"{CONFIG_PATH} JSON 解析失败: {e}")


def render_title(template: str, fm: dict, filename: str) -> str:
    ctx = {**fm, "filename": filename}
    keys = re.findall(r"\{(\w+)\}", template)
    missing = [k for k in keys if k not in ctx or not ctx[k]]
    if missing:
        die(f"title_template {template!r} 占位符 {missing} 在 markdown frontmatter 中缺失；"
            f"请补 frontmatter 或手动 --title")
    return template.format(**{k: ctx[k] for k in keys})


def resolve_target(args, fm: dict, filename: str) -> dict:
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
        title = render_title(tpl, fm, filename)
    else:
        title = filename

    return {"kind": kind, "token": token, "title": title}


# ---------- 发布 ----------

def build_doc_url(doc_id: str) -> str:
    host = os.environ.get("LARK_DOCS_HOST", "feishu.cn")
    return f"https://{host}/docx/{doc_id}"


def publish_first_time(markdown_path: Path, target: dict):
    # lark-cli 对 @<绝对路径> 的 markdown 处理有 bug,改用 @./<文件名> + cwd=父目录绕过
    cmd = ["lark-cli", "docs", "+create",
           "--title", target["title"],
           "--markdown", f"@./{markdown_path.name}"]
    if target["kind"] == "wiki":
        cmd.extend(["--wiki-node", target["token"]])
    elif target["kind"] == "folder":
        cmd.extend(["--folder-token", target["token"]])
    else:
        die(f"未知 target.kind: {target['kind']}（应为 wiki 或 folder）")

    info(f"创建飞书文档: title={target['title']!r} kind={target['kind']}")
    try:
        res = subprocess.run(cmd, cwd=str(markdown_path.parent),
                             capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        die(f"lark-cli docs +create 失败: {e.stderr}")

    try:
        data = json.loads(res.stdout)
    except json.JSONDecodeError:
        die(f"lark-cli docs +create 返回非 JSON: {res.stdout[:300]}")

    doc_id = (
        (data.get("data", {}).get("document", {}) or {}).get("document_id")
        or (data.get("document", {}) or {}).get("document_id")
        or data.get("document_id")
    )
    if not doc_id:
        die(f"无法从 lark-cli docs +create 返回提取 document_id: {data}")

    url = build_doc_url(doc_id)
    info(f"文档已创建: {url}")
    return doc_id, url


def publish_overwrite(markdown_path: Path, doc_id: str):
    info(f"覆盖飞书文档: doc_id={doc_id}")
    # lark-cli 对 @<绝对路径> 的 markdown 处理有 bug,改用 @./<文件名> + cwd=父目录绕过
    cmd = ["lark-cli", "docs", "+update",
           "--doc", doc_id,
           "--markdown", f"@./{markdown_path.name}",
           "--mode", "overwrite"]
    try:
        subprocess.run(cmd, cwd=str(markdown_path.parent),
                       capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        die(f"lark-cli docs +update 失败: {e.stderr}")
    return doc_id, build_doc_url(doc_id)


# ---------- Cell 合并 ----------

def lark_api(method: str, path: str, params: dict | None = None, data: dict | None = None):
    cmd = ["lark-cli", "api", method, path]
    if params:
        cmd.extend(["--params", json.dumps(params)])
    if data:
        cmd.extend(["--data", json.dumps(data)])
    res = run(cmd, check=False)
    if res.returncode != 0:
        raise RuntimeError(f"lark-cli api {method} {path} failed: {(res.stderr or res.stdout).strip()}")
    try:
        return json.loads(res.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(f"lark-cli api {method} {path} 返回非 JSON: {res.stdout[:200]}")


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
) -> bool:
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
        try:
            lark_api(
                "POST",
                f"/open-apis/docx/v1/documents/{doc_id}/blocks/{non_anchor_id}/children/batch_delete",
                data={"start_index": 0, "end_index": count},
            )
        except RuntimeError as e:
            warn(f"清空 leading cell children 失败 cell={non_anchor_id}: {e};继续 merge")

    # 2) merge_table_cells
    try:
        lark_api(
            "PATCH",
            f"/open-apis/docx/v1/documents/{doc_id}/blocks/{table_block_id}",
            data={"merge_table_cells": rng},
        )
        return True
    except RuntimeError as e:
        warn(f"merge_table_cells (leading) 失败 range={rng}: {e}")
        return False


def merge_desc_group_with_content(
    doc_id: str,
    table_block_id: str,
    cells_array: list,
    cols: int,
    blocks_by_id: dict,
    rng: dict,
) -> bool:
    """把 desc col row group 的非锚点 cell 的内容拷贝到锚点 cell，清空原 cell，再 merge。"""
    start = rng["row_start_index"]
    end = rng["row_end_index"]
    desc_col = rng["column_start_index"]

    anchor_cell_id = cells_array[start * cols + desc_col]
    anchor_cell = blocks_by_id.get(anchor_cell_id)
    if not anchor_cell:
        warn(f"找不到锚点 cell block: {anchor_cell_id}")
        return False

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
        try:
            lark_api(
                "POST",
                f"/open-apis/docx/v1/documents/{doc_id}/blocks/{anchor_cell_id}/children",
                data={"children": all_specs, "index": anchor_child_count},
            )
        except RuntimeError as e:
            warn(f"拷贝 children 到锚点 cell 失败: {e}；跳过本 group merge")
            return False

        # 3) 清空非锚点 cell 的 children（Feishu batch_delete = POST + start_index/end_index）
        for cell_id, count in cells_to_clear:
            if count == 0:
                continue
            try:
                lark_api(
                    "POST",
                    f"/open-apis/docx/v1/documents/{doc_id}/blocks/{cell_id}/children/batch_delete",
                    data={"start_index": 0, "end_index": count},
                )
            except RuntimeError as e:
                warn(f"清空原 cell children 失败 cell={cell_id}: {e}；锚点已含拷贝，继续 merge")

    # 4) merge_table_cells
    try:
        lark_api(
            "PATCH",
            f"/open-apis/docx/v1/documents/{doc_id}/blocks/{table_block_id}",
            data={"merge_table_cells": rng},
        )
    except RuntimeError as e:
        warn(f"merge_table_cells（需求描述列）失败 range={rng}: {e}")
        return False

    return True


def merge_cells_for_doc(doc_id: str):
    try:
        blocks = get_all_blocks(doc_id)
    except RuntimeError as e:
        warn(f"拉 block 列表失败: {e}；跳过合并步骤")
        return 0, 0

    blocks_by_id = {b["block_id"]: b for b in blocks}
    table_blocks = [b for b in blocks if "table" in b]

    success = 0
    failure = 0

    for table in table_blocks:
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
            ok = merge_leading_with_clear(
                doc_id, table["block_id"], cells_array, cols, blocks_by_id, rng,
            )
            if ok:
                success += 1
            else:
                failure += 1

        # 末列（需求描述）：续行 row group 需要先把 children 拷贝到锚点 cell 再 merge
        for rng in find_desc_group_ranges(grid, existing):
            ok = merge_desc_group_with_content(
                doc_id, table["block_id"], cells_array, cols, blocks_by_id, rng,
            )
            if ok:
                success += 1
            else:
                failure += 1

    return success, failure


# ---------- Main ----------

def main() -> None:
    ap = argparse.ArgumentParser(prog="publish-to-lark",
                                 description="把本地 markdown 发布到飞书云文档")
    ap.add_argument("markdown", help="markdown 文件路径")
    ap.add_argument("--type", help="文档类型 (prd/task-spec/analysis/other)")
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
    filename = md_path.stem
    existing_doc_id = fm.get("lark_doc_id")

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
        doc_id, url = publish_overwrite(md_path, existing_doc_id)
        first_time = False
    else:
        target = resolve_target(args, fm, filename)
        doc_id, url = publish_first_time(md_path, target)
        first_time = True

    if args.no_merge_cells:
        info("跳过表格合并（--no-merge-cells）")
        merge_s, merge_f = 0, 0
    else:
        info("扫描表格 cell 合并...")
        merge_s, merge_f = merge_cells_for_doc(doc_id)

    fm_written = False
    if first_time:
        new_fm = dict(fm)
        new_fm["lark_doc_id"] = doc_id
        new_fm["lark_doc_url"] = url
        new_fm["lark_published_at"] = datetime.now().astimezone().isoformat(timespec="seconds")
        try:
            write_frontmatter(md_path, new_fm, body)
            fm_written = True
        except OSError as e:
            warn(f"frontmatter 回写失败: {e}；飞书侧文档已发布，URL={url}，请手动回填")

    info("")
    info("飞书文档已发布")
    info(f"URL: {url}")
    info(f"合并 cell: 成功 {merge_s} 处 / 失败 {merge_f} 处")
    if first_time:
        info(f"本地 frontmatter: {'已回填' if fm_written else '回填失败 — 见上方警告'}")


if __name__ == "__main__":
    main()
