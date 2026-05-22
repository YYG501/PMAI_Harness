"""Single source of truth for req stage metadata (delta-2+4 F13).

stage 名 / 推进前要求的产出文件 散落在 req-transition.py / status-view.py /
CLAUDE.md.tmpl 等处。F13 把可被脚本引用的部分抽进本模块，脚本统一 import。
（CLAUDE.md.tmpl 是模板 prose、无法 import，只能文本同步。）

delta-2+4 换芯：stage 3「方案设计」→「功能规格」，产物 solution.md → prd.md。
"""

from __future__ import annotations

STAGE_NAMES: dict[int, str] = {
    1: "感受问题",
    2: "需求分析",
    3: "功能规格",
    4: "设计系统建立",
    5: "模块规格 + task 拆分",
    6: "task 执行",
    7: "req close",
}

# Stage N 推进前要求这个产出文件存在（forward transition 前置校验）。
# stage 4 的产出是 docs/DESIGN.md，单独校验，不在此表。
STAGE_OUTPUT_FILES: dict[int, str] = {
    1: "brief.md",
    2: "analysis.md",
    3: "prd.md",
    5: "task-plan.md",
}

# stage 3 旧产物（在飞旧 req 兼容判别用）—— 见 req-transition.py 文件存在性判别。
LEGACY_STAGE3_OUTPUT = "solution.md"
