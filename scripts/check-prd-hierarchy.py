#!/usr/bin/env python3
"""check-prd-hierarchy.py: 扫描 prd.md §六 功能需求表格的二级/三级功能命名，
flag UI 词违规（按 skills/prd-writing/SKILL.md「层级划分原则」+「UI 词汇黑名单」）。

二级功能应是用户动作组（列表 / 搜索 / 筛选 / 操作 / 创建 / 导入 / 详情）；
三级功能应是动作子项，命名以动词锚定（分配 / 调整 / 撤销 / 启用 / 吊销 / 查看）。
含 UI 容器词（弹窗 / 面板 / 视图 / 视角 / 入口 / 字段 / 段 / 区块 / 菜单 / 顶部 /
行级 / 池行 / Tab / Drawer / 紧凑形态）的命名是违规——这些是 UI 实现描述，
应下沉到需求描述列编号项。

用法:
    python3 scripts/check-prd-hierarchy.py <prd.md 路径>

退出码:
    0 = 无违规
    1 = 有违规（违规列表写到 stdout）
    2 = 文件读取/解析错误
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


# UI 词必抓黑名单（cell 含这些 substring 即 flag）
UI_BLACKLIST_SUBSTRING: set[str] = {
    "弹窗", "Dialog", "dialog",
    "面板",
    "视图", "视角",
    "入口",
    "区块",
    "Tab", "tab",
    "Drawer", "drawer",
    "紧凑形态",
    "池行",
}

# 启发式 pattern（避免黑名单 substring 误伤已合并到正确动作里的词，如"导入"含"入"——
# 这里用 anchor 做更精确匹配："X 入口" 抓尾缀「入口」是 UI 词，"操作菜单" 抓尾缀「菜单」）
UI_HEURISTIC_PATTERNS: list[str] = [
    r".+弹窗$",       # X弹窗
    r".+面板$",       # X面板（除"产品授权项 & 使用情况合并区块"等用法）
    r".+入口$",       # X入口
    r".+字段$",       # X字段（"列表字段" / "基本字段" / "来源字段"）
    r".+视图$",       # X视图
    r".+视角$",       # X视角
    r".+Dialog$",
    r".+Drawer$",
    r".+段$",         # X段（"租户直接开通段"），但白名单豁免「阶段」「段落」等业务词
    r"^顶部.+",       # 顶部X
    r"^底部.+",       # 底部X
    r"^行级.+",       # 行级X
    r".+菜单$",       # 操作菜单 / X菜单
    r".+Tab$",        # XTab / X Tab
    r"^Tab.+",        # TabX / Tab X
    r".+池树$",       # X池树（"部门视角池树" / "许可证视角池树"）
]

# 合法动作组白名单（cell 完全等于这些词时豁免，即使被黑名单 substring 误抓也放行）
ACTION_WHITELIST: set[str] = {
    "列表", "搜索", "筛选", "详情", "概览",
    "创建", "编辑", "删除", "复制",
    "操作", "状态变更", "启用停用", "发布下架",
    "分配", "取消分配", "调整分配", "授权", "移除",
    "导入", "导出", "上传", "下载",
    "配置", "设置", "偏好",
    "刷新", "推荐",
    "查看", "查看详情",
    "/",  # markdown 表格里"无三级功能"的占位符
    "",   # 续行 rowspan 模式下的空 cell
}


def strip_markdown(text: str) -> str:
    """去掉 cell 内的 markdown 格式（**bold** / [text](url) / `code`），保留纯文本。"""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"\*(.+?)\*", r"\1", text)
    text = re.sub(r"`(.+?)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    return text.strip()


def find_section_six(lines: list[str]) -> tuple[int, int] | None:
    """返回 §六 功能需求段的 [start, end) 行索引；未找到返回 None。"""
    start = None
    end = None
    for i, line in enumerate(lines):
        if re.match(r"^##\s*六、?\s*功能需求", line):
            start = i
        elif start is not None and re.match(r"^##\s*七、?", line):
            end = i
            break
    if start is None:
        return None
    return start, end if end is not None else len(lines)


def find_tables(lines: list[str], start: int, end: int) -> list[tuple[int, int, list[str]]]:
    """在 [start, end) 范围内找所有 markdown 表格，返回 [(header_idx, table_end_idx, header_cells)]。"""
    tables: list[tuple[int, int, list[str]]] = []
    i = start
    while i < end - 1:
        line = lines[i]
        if line.startswith("|") and re.match(r"^\|[\s\-:|]+\|\s*$", lines[i + 1]):
            header = parse_cells(line)
            j = i + 2
            while j < end and lines[j].startswith("|"):
                j += 1
            tables.append((i, j, header))
            i = j
            continue
        i += 1
    return tables


def parse_cells(line: str) -> list[str]:
    """parse | a | b | c | -> ['a', 'b', 'c'] (strip leading/trailing pipes + whitespace)。"""
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def detect_columns(header: list[str]) -> tuple[int | None, int | None]:
    """识别表头里"二级功能"和"三级功能"列的索引。"""
    l2_idx = next((i for i, h in enumerate(header) if "二级功能" in strip_markdown(h)), None)
    l3_idx = next((i for i, h in enumerate(header) if "三级功能" in strip_markdown(h)), None)
    return l2_idx, l3_idx


def is_violation(cell_value: str) -> tuple[bool, list[str]]:
    """判断 cell 内容是否含 UI 词违规。返回 (violated, hit_reasons)。"""
    v = strip_markdown(cell_value)
    if v in ACTION_WHITELIST:
        return False, []

    hits: list[str] = []
    # 黑名单 substring
    for word in UI_BLACKLIST_SUBSTRING:
        if word in v:
            hits.append(f"含黑名单词「{word}」")

    # 启发式 pattern
    for pat in UI_HEURISTIC_PATTERNS:
        if re.match(pat, v):
            hits.append(f"匹配 UI 词形态 /{pat}/")

    return (bool(hits), hits)


def scan(path: Path) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        print(f"ERROR: 读取 {path} 失败: {e}", file=sys.stderr)
        return 2

    lines = text.splitlines()
    section = find_section_six(lines)
    if section is None:
        print(f"WARN: {path} 不含 §六 功能需求段，跳过检查", file=sys.stderr)
        return 0

    start, end = section
    tables = find_tables(lines, start, end)
    if not tables:
        print(f"WARN: {path} §六 没有 markdown 表格，跳过检查", file=sys.stderr)
        return 0

    violations: list[dict] = []
    seen_l2: dict[str, int] = {}  # 同一二级名首次出现行号（去重）
    seen_l3: dict[str, int] = {}  # 同一三级名首次出现行号（按二级 scope 去重，简化为全局去重）
    for tbl_start, tbl_end, header in tables:
        l2, l3 = detect_columns(header)
        if l2 is None or l3 is None:
            continue
        for row_idx in range(tbl_start + 2, tbl_end):
            cells = parse_cells(lines[row_idx])
            if max(l2, l3) >= len(cells):
                continue
            for label, col in (("二级", l2), ("三级", l3)):
                cell = cells[col]
                violated, hits = is_violation(cell)
                if not violated:
                    continue
                # 去重：同一名称重复出现只报第一次
                seen = seen_l2 if label == "二级" else seen_l3
                if cell in seen:
                    continue
                seen[cell] = row_idx + 1
                violations.append({
                    "line": row_idx + 1,
                    "level": label,
                    "value": cell,
                    "hits": hits,
                })

    if violations:
        print(f"§六 功能需求层级违规：{len(violations)} 处去重命名（同名重复只报一次）")
        print()
        for v in violations:
            hits_str = " | ".join(v["hits"])
            print(f"  L{v['line']:>4}  {v['level']}：「{v['value']}」  ← {hits_str}")
        print()
        print("修正方向（详见 skills/prd-writing/SKILL.md「层级划分原则」）：")
        print("  · 二级功能 = 用户动作组（列表 / 搜索 / 筛选 / 操作 / 创建 / 导入 / 详情）")
        print("  · 三级功能 = 动作子项，命名以动词锚定（分配 / 调整 / 撤销 / 启用 / 吊销 / 查看）")
        print("  · 角色视角差异 / UI 视图切换 / UI 形态规则 / 弹窗实现细节 → 写进需求描述列编号项")
        print()
        print("白名单豁免：列表 / 搜索 / 筛选 / 详情 / 概览 / 创建 / 编辑 / 删除 / ...（完整清单见脚本 ACTION_WHITELIST）")
        return 1

    print(f"§六 层级检查通过：{path}")
    return 0


def main() -> None:
    ap = argparse.ArgumentParser(
        description="扫描 prd.md §六 表格，flag 二级 / 三级 UI 词违规",
    )
    ap.add_argument("path", help="prd.md 文件路径")
    args = ap.parse_args()

    code = scan(Path(args.path))
    sys.exit(code)


if __name__ == "__main__":
    main()
