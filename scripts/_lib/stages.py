"""Single source of truth for req stage metadata .

stage 名 / 推进前要求的产出文件 散落在 req-transition.py / status-view.py /
CLAUDE.md.tmpl 等处。F13 把可被脚本引用的部分抽进本模块，脚本统一 import。
（CLAUDE.md.tmpl 是模板 prose、无法 import，只能文本同步。）

stage 3 命名演化：「方案设计」→「功能规格」→「需求方案」（产物 solution.md → prd.md）；
stage 5 命名演化：「模块规格 + task 拆分」→「实现设计 + task 拆分」（implementation-design.md + task-plan.md）。
背景：PM 视角下 3 = 需求方案（WHAT），5 = 实现设计（HOW），二分清楚；「功能规格」/「模块规格」
偏工程文档化味，跟 PM 心智对不上。
"""

from __future__ import annotations

STAGE_NAMES: dict[int, str] = {
    1: "描述需求",
    2: "需求分析",
    3: "需求方案",
    4: "设计系统建立",
    5: "实现设计 + task 拆分",
    6: "task 执行",
    7: "req close",
}

# Stage N 推进前要求这个产出文件存在（forward transition 前置校验）。
# stage 4 的产出是 docs/DESIGN.md，单独校验，不在此表。
#
# 双用途说明：本字典同时承担两个角色 ——
#  1) `req-transition.py` 推进 stage N→N+1 前的前置校验文件名
#  2) `_lib.state.get_stage_source` helper 在 `.req-meta.json` 无
#     `stage{N}_source` 字段时的**默认 fallback** 文件名
# 因此 schema 锁定为 `dict[int, str]`（单一默认产物）；多产物分流（如 stage 2
# 的 office-hours 分支产 `stage2-office-hours.md`）通过 `.req-meta.json` 的
# `stage{N}_source` 字段在 req 级 override，不升级本表为 list/multi-path。
# .md §1.3 / §2 / 。
STAGE_OUTPUT_FILES: dict[int, str] = {
    1: "brief.md",
    2: "analysis.md",
    3: "prd.md",
    5: "task-plan.md",
}

# stage 3 旧产物（在飞旧 req 兼容判别用）—— 见 req-transition.py 文件存在性判别。
LEGACY_STAGE3_OUTPUT = "solution.md"
