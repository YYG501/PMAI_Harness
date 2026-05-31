"""Single source of truth for req stage metadata（六步重构后）.

六步重构（office-hours 收敛）后的状态机：
- 「① 项目底座」是项目级、init 时建（PRODUCT-STATE / DESIGN / 主原型），**不是 per-req stage**。
- per-req 生命周期收敛成 4 个阶段（原 7-stage 坍缩）：
    1 范围确认  —— 三条上坡路产出 req-plan.md（范围清单 + 决策页），PM 拍板
    2 build     —— 在 prototype/ 栈内建（mode 中立：原型 / 真系统按工程结构约束的层）
    3 复审      —— 三道机器审（覆盖审计 / 视觉门 / 行为审）+ 体验迭代 → 呈交闸门 PM 验收
    4 沉淀      —— 更新 PRODUCT-STATE + merge 主原型回 main（+ 按需 prd-writing 出 PRD）

stage 名 / 推进前要求的产出文件 散落在 req-transition.py / status-view.py /
CLAUDE.md.tmpl 等处，脚本统一 import 本模块。（CLAUDE.md.tmpl 是模板 prose，
无法 import，文本同步。）

显示已转产品轴（banner/status 播报"产品现状 + 主原型状态 + 本次增量"，不再播
"Stage N/M"），故 stage 编号是**内部状态标记**、不再 PM-facing。
"""

from __future__ import annotations

# per-req 阶段数（坍缩后）。① 项目底座不计入（项目级）。
MAX_STAGE: int = 4

STAGE_NAMES: dict[int, str] = {
    1: "范围确认",
    2: "build",
    3: "复审",
    4: "沉淀",
}

# Stage N 推进前要求这个产出文件存在（forward transition 前置校验）。
#
# 双用途说明（沿用重构前契约）：
#  1) `req-transition.py` 推进 stage N→N+1 前的前置校验文件名
#  2) `_lib.state.get_stage_source` helper 在 `.req-meta.json` 无
#     `stage{N}_source` 字段时的**默认 fallback** 文件名
# schema 锁定为 `dict[int, str]`（单一默认产物）。
#
# 六步里只有第 1 步「范围确认」有法定文档产物（req-plan.md）；
# build / 复审 的"产出"是 prototype 代码 + 三道审证据，无单一 .md 前置文件
# （闸门由 PM 验收 + task demo 确认把守，不靠文件存在性）；
# 沉淀 的产物（PRODUCT-STATE 更新 / merge / 按需 PRD）由 close-req 流程把守。
STAGE_OUTPUT_FILES: dict[int, str] = {
    1: "req-plan.md",
}
