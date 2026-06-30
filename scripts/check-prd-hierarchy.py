#!/usr/bin/env python3
"""check-prd-hierarchy.py: 扫描 PRD 体例 / 4 列功能表 preset 的层级 + 描述风格 + 表格结构违规。

本脚本不作为模块 spec.md、规则收口、状态分类、流程叙述或字段口径文档的通用 lint；
这些文档先按 spec-writing 的功能需求写法选择器决定组织方式。

类 1 — §六 层级（按 skills/spec-writing/SKILL.md「层级划分原则」+ UI 词汇黑名单）：
二级功能应是用户动作组（列表 / 搜索 / 筛选 / 操作 / 创建 / 导入 / 详情）；
三级功能应是动作子项，命名以动词锚定（分配 / 调整 / 撤销 / 启用 / 吊销 / 查看）。
含 UI 容器词（弹窗 / 面板 / 视图 / 视角 / 入口 / 字段 / 段 / 区块 / 菜单 / 顶部 /
行级 / 池行 / Tab / Drawer / 紧凑形态）的命名是违规。

类 2 — 描述风格（按 references/writing-rules.md「描述风格规则」全篇扫描）：
- 视觉细节越界（颜色 hex / Badge / 视觉弱化 / destructive / warning ...）
- URL 路由 / 技术细节（?view= / <licenseId> / ▾▸↔）
- 排版分隔符（「」中文方角引号 / 中点 ·）
- 否定式描述（无 ⋮ / 不再 X / 不是 X）
- 工程黑话（触发-弹窗 / 锚定 / 池行末 / 账本 / 跟随失效 / 同口径 / 漂移 / focus trap ...）

类 3 — §六 表格结构（按 _shared/PM-VIEW-RULES.md §5.1「续行 rowspan + 内联编号」）：
需求描述列不允许用 <br/> / <br> 把多条编号塞同一单元格 —— 每条编号一行，
第 2 条起的前 3 列留空（视觉等同 rowspan，纯 markdown 也能渲染）。

用法:
    python3 scripts/check-prd-hierarchy.py <PRD 体例或 4 列功能表文档路径>

退出码:
    0 = 无违规
    1 = 有违规（违规列表写到 stdout，分类 1 / 2 / 3 输出）
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

# 启发式 pattern
UI_HEURISTIC_PATTERNS: list[str] = [
    r".+弹窗$",
    r".+面板$",
    r".+入口$",
    r".+字段$",
    r".+视图$",
    r".+视角$",
    r".+Dialog$",
    r".+Drawer$",
    r".+段$",
    r"^顶部.+",
    r"^底部.+",
    r"^行级.+",
    r".+菜单$",
    r".+Tab$",
    r"^Tab.+",
    r".+池树$",
]

# 合法动作组白名单
ACTION_WHITELIST: set[str] = {
    "列表", "搜索", "筛选", "详情", "概览",
    "创建", "编辑", "删除", "复制",
    "操作", "状态变更", "启用停用", "发布下架",
    "分配", "取消分配", "调整分配", "授权", "移除",
    "导入", "导出", "上传", "下载",
    "配置", "设置", "偏好",
    "刷新", "推荐",
    "查看", "查看详情",
    "/",
    "",
}


def strip_markdown(text: str) -> str:
    """去掉 cell 内的 markdown 格式。"""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = re.sub(r"\*(.+?)\*", r"\1", text)
    text = re.sub(r"`(.+?)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    return text.strip()


def find_section_six(lines: list[str]) -> tuple[int, int] | None:
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
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def detect_columns(header: list[str]) -> tuple[int | None, int | None]:
    l2_idx = next((i for i, h in enumerate(header) if "二级功能" in strip_markdown(h)), None)
    l3_idx = next((i for i, h in enumerate(header) if "三级功能" in strip_markdown(h)), None)
    return l2_idx, l3_idx


def is_violation(cell_value: str) -> tuple[bool, list[str]]:
    v = strip_markdown(cell_value)
    if v in ACTION_WHITELIST:
        return False, []

    hits: list[str] = []
    for word in UI_BLACKLIST_SUBSTRING:
        if word in v:
            hits.append(f"含黑名单词「{word}」")

    for pat in UI_HEURISTIC_PATTERNS:
        if re.match(pat, v):
            hits.append(f"匹配 UI 词形态 /{pat}/")

    return (bool(hits), hits)


# ============================================================================
# 类 2 — 描述风格违规（全篇扫描）
# ============================================================================

# Pattern 格式: (regex, reason, hint)
# - reason: 违规类型简短说明
# - hint: 具体改写建议(空字符串 = 删)

VISUAL_PATTERNS: list[tuple[str, str, str]] = [
    (r"#[0-9A-Fa-f]{6}\b", "颜色 hex 码", "删(颜色由 DESIGN.md 决定)"),
    (r"视觉弱化", "视觉描述", '改写为"只展示段头,不展示操作按钮"等行为约束'),
    (r"警示图标", "视觉描述", "删图标颜色,保留破坏性等级(轻/中/重档)"),
    (r"\bdestructive\b", "工程词", '改写为"重档"'),
    (r"\bwarning\b", "工程词", '改写为"中档"'),
    (r"主色填充", "视觉描述", "删(视觉细节)"),
    (r"加粗加红", "视觉描述", '改写为"需视觉强调"或删'),
    (r"\bBadge\b", "视觉部件", '改写为"标识"或删'),
    (r"ghost 按钮", "按钮变体", "删 ghost 修饰,直接 [按钮名]"),
    (r"明文按钮", "按钮变体", "删 明文 修饰,直接 [按钮名]"),
    (r"紧凑形态", "形态描述", "删(PM 补图)"),
    (r"简化形态", "形态描述", "删(PM 补图)"),
]

URL_PATTERNS: list[tuple[str, str, str]] = [
    (r"\?view=", "URL 参数", "删(实现层,改写业务行为)"),
    (r"\?tab=", "URL 参数", "删(实现层,改写业务行为)"),
    (r"&license=", "URL 参数", "删(实现层)"),
    (r"<\w+Id>", "路由占位符", "删(实现层)"),
    (r"[▾▸↔▼▶]", "图标 Unicode 字符", '改写为"段头支持折叠展开"等业务行为'),
]

PUNCT_PATTERNS: list[tuple[str, str, str]] = [
    (r"「", "中文方角引号", '改用 ASCII 双引号 "..."'),
    (r"」", "中文方角引号", '改用 ASCII 双引号 "..."'),
    (r" · ", "中点 ·", "改用顿号、"),
]

NEG_PATTERNS: list[tuple[str, str, str]] = [
    (r"无\s*⋮", "否定式(暴露否决方案)", "删,直接描述当前方案"),
    (r"不再有", "否定式(暴露旧方案)", "删,直接描述当前"),
    (r"不再展示", "否定式", "删(不写就是不展示)"),
    (r"不再拆", "否定式", '改写为"为单一合并区块"等正面描述'),
    (r"不再渲染", "否定式", "删,直接描述当前"),
    (r"不是\s*destructive", "否定式", "删(视觉细节本身就该删)"),
]

JARGON_PATTERNS: list[tuple[str, str, str]] = [
    (r"触发(?:弹窗|对应弹窗|开通弹窗|二次确认|分配弹窗|调整弹窗)", "工程黑话", '改写为"点击后打开 X"'),
    (r"锚定", "工程黑话", '改写为"定位到"'),
    (r"池行末", "位置工程词", '改写为"每一行额度池"'),
    (r"顶部右(?:侧|上)", "位置工程词", '改写为"页面顶部"或具体业务对象'),
    (r"focus trap", "工程黑话", '改写为"焦点收敛在弹窗内"'),
    (r"\bloading\b", "工程黑话", '改写为"加载中..."或"校验中..."'),
    (r"\bdisabled\b", "工程黑话", '改写为"置灰"或"不可点"'),
    (r"\bremove\b", "工程黑话(英文)", '改写为"删除"'),
    (r"池树", "工程黑话", "删,具体说明展示什么"),
    (r"账本", "工程黑话", '改写为"记录"/"数字"/"累计数字"'),
    (r"跟随失效", "抽象动作短语", '改写为"一并失效"/"连带失效"'),
    (r"同口径", "工程黑话", '改写为"数字一致"'),
    (r"漂移", "工程黑话", '改写为"不一致"'),
    (r"由.{1,10}承载", "工程黑话(由X承载)", '改写为"X 包含"或"由 X 提供"'),
    (r"完整使用全貌", "抽象表达", '改写为"完整使用情况"'),
    (r"一步可达", "工程黑话", '改写为"点击 [详情] 即可查看"或删'),
    (r"不承载", "工程黑话", '改写为"只用于"(如"详情只用于查看")'),
    (r"绕过.{1,10}中介", "抽象表达", '改写为"不走 X 这一层"'),
    (r"想\S{1,20}请走", "PM 指令视角", '改写为业务行为视角("X 需通过 Y 操作")'),
]

ALL_STYLE_PATTERNS: list[tuple[str, list[tuple[str, str, str]]]] = [
    ("视觉细节", VISUAL_PATTERNS),
    ("URL/技术细节", URL_PATTERNS),
    ("排版分隔符", PUNCT_PATTERNS),
    ("否定式", NEG_PATTERNS),
    ("工程黑话", JARGON_PATTERNS),
]


def check_table_structure(
    lines: list[str], section: tuple[int, int]
) -> list[dict]:
    """类 3 — §六 表格结构：扫描需求描述列内 <br/> / <br> 滥用。

    PM-VIEW-RULES.md §5.1 续行 rowspan：每条编号一行，第 2 条起的前 3 列留空。
    禁止用 <br/> 把多条编号塞单格（视觉等同但违反 rowspan 规则）。
    """
    violations: list[dict] = []
    start, end = section
    tables = find_tables(lines, start, end)
    if not tables:
        return violations

    br_pattern = re.compile(r"<br\s*/?>", re.IGNORECASE)
    numbered_pattern = re.compile(r"\b[1-9]\d?\.\s*")  # 1. / 2. / 10. 编号

    for tbl_start, tbl_end, header in tables:
        # 找需求描述列（兼容 "需求描述" / "需求描述列"）
        desc_idx = next(
            (i for i, h in enumerate(header) if "需求描述" in strip_markdown(h)),
            None,
        )
        if desc_idx is None:
            continue
        for row_idx in range(tbl_start + 2, tbl_end):
            cells = parse_cells(lines[row_idx])
            if desc_idx >= len(cells):
                continue
            cell = cells[desc_idx]
            br_hits = br_pattern.findall(cell)
            if not br_hits:
                continue
            # 多条编号塞一格：<br> 紧邻或包裹「N.」编号 → 命中
            # 单纯 <br> 用于格内换行（如长描述断行）也算违规（违反 §5.1）
            num_count = len(numbered_pattern.findall(cell))
            violations.append({
                "line": row_idx + 1,
                "br_count": len(br_hits),
                "numbered_count": num_count,
                "cell_preview": (cell[:60] + "...") if len(cell) > 60 else cell,
            })
    return violations


def check_style(lines: list[str]) -> list[dict]:
    """全篇扫描描述风格违规。返回违规列表。

    Fenced code block (```) 内的行整体跳过 —— §六「原型」节 ASCII 原型图
    包在 fenced block 里，会含 ▾ / · 等界面字符（界面元素，非工程黑话）。
    """
    violations: list[dict] = []
    in_fenced = False
    for line_idx, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            in_fenced = not in_fenced
            continue
        if in_fenced:
            continue
        if line.startswith("---"):
            continue
        for category, patterns in ALL_STYLE_PATTERNS:
            for pattern, reason, hint in patterns:
                for m in re.finditer(pattern, line):
                    violations.append({
                        "line": line_idx + 1,
                        "category": category,
                        "value": m.group(0),
                        "reason": reason,
                        "hint": hint,
                        "context": line[:80] + ("..." if len(line) > 80 else ""),
                    })
    return violations


def scan(path: Path) -> int:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        print(f"ERROR: 读取 {path} 失败: {e}", file=sys.stderr)
        return 2

    lines = text.splitlines()

    # 类 1: §六 层级检查
    section = find_section_six(lines)
    section_violations: list[dict] = []
    if section is not None:
        start, end = section
        tables = find_tables(lines, start, end)
        if tables:
            seen_l2: dict[str, int] = {}
            seen_l3: dict[str, int] = {}
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
                        seen = seen_l2 if label == "二级" else seen_l3
                        if cell in seen:
                            continue
                        seen[cell] = row_idx + 1
                        section_violations.append({
                            "line": row_idx + 1,
                            "level": label,
                            "value": cell,
                            "hits": hits,
                        })

    # 类 2: 描述风格检查
    style_violations = check_style(lines)

    # 类 3: §六 表格结构检查（续行 rowspan vs <br> 单格）
    table_violations: list[dict] = []
    if section is not None:
        table_violations = check_table_structure(lines, section)

    has_violations = (
        bool(section_violations) or bool(style_violations) or bool(table_violations)
    )

    if section_violations:
        print(f"━━━ 类 1 — §六 功能需求层级违规:{len(section_violations)} 处去重命名 ━━━")
        print()
        for v in section_violations:
            hits_str = " | ".join(v["hits"])
            print(f'  L{v["line"]:>4}  {v["level"]}: "{v["value"]}"  ← {hits_str}')
        print()
        print("修正方向 (详见 skills/spec-writing/SKILL.md「层级划分原则」):")
        print("  · 二级功能 = 用户动作组（列表 / 搜索 / 筛选 / 操作 / 创建 / 导入 / 详情）")
        print("  · 三级功能 = 动作子项，命名以动词锚定（分配 / 调整 / 撤销 / 启用 / 吊销 / 查看）")
        print("  · 角色视角差异 / UI 视图切换 / UI 形态规则 / 弹窗实现细节 → 写进需求描述列编号项")
        print()

    if style_violations:
        by_category: dict[str, list[dict]] = {}
        for v in style_violations:
            by_category.setdefault(v["category"], []).append(v)

        print(f"━━━ 类 2 — 描述风格违规：{len(style_violations)} 处 ━━━")
        for category in ("视觉细节", "URL/技术细节", "排版分隔符", "否定式", "工程黑话"):
            items = by_category.get(category, [])
            if not items:
                continue
            print()
            print(f"  [{category}] {len(items)} 处")
            for v in items[:20]:
                print(f'    L{v["line"]:>4}  "{v["value"]}"  ← {v["reason"]}')
                print(f"          → {v['hint']}")
            if len(items) > 20:
                print(f"    (... 还有 {len(items) - 20} 处同类违规未展示)")
        print()
        print("修正方向 (详见 skills/_shared/pm-view/writing-rules.md §3.12 描述风格规则):")
        print("  · 视觉细节 → 删 (DESIGN.md 范畴,PM 自己补图)")
        print("  · URL/技术细节 → 删 (实现层,PRD 写业务行为)")
        print('  · 排版分隔符 → 「」改 "...",· 改顿号、')
        print("  · 否定式 → 直接描述当前方案,不暴露否决过的设计")
        print("  · 工程黑话 → 业务自然语言 (生僻描述词 = 工程黑话)")
        print()

    if table_violations:
        print(
            f"━━━ 类 3 — §六 表格结构违规：{len(table_violations)} 处 <br/> 单格塞编号 ━━━"
        )
        print()
        for v in table_violations:
            print(
                f'  L{v["line"]:>4}  <br> x{v["br_count"]}  编号项 x{v["numbered_count"]}'
                f'  cell: "{v["cell_preview"]}"'
            )
        print()
        print("修正方向 (详见 skills/_shared/PM-VIEW-RULES.md §5.1):")
        print("  · 续行 rowspan 模式：每条编号一行，第 2 条起前 3 列留空")
        print("  · 禁用 <br/> / <br> 把多条编号塞单格（违反 §5.1）")
        print("  · 示例:")
        print("    | 二级 | 三级 | 角色 | 1. 第一条 |")
        print("    |      |      |      | 2. 第二条 |")
        print("    |      |      |      | 3. 第三条 |")
        print()

    if has_violations:
        return 1

    print(f"✓ lint 通过：{path}")
    print(f"  · §六 层级：通过")
    print(f"  · 描述风格（视觉/URL/排版/否定/工程黑话）：通过")
    print(f"  · §六 表格结构（续行 rowspan）：通过")
    return 0


def main() -> None:
    ap = argparse.ArgumentParser(
        description="扫描 prd.md：§六 层级 + 描述风格违规",
    )
    ap.add_argument("path", help="prd.md 文件路径")
    args = ap.parse_args()

    code = scan(Path(args.path))
    sys.exit(code)


if __name__ == "__main__":
    main()
