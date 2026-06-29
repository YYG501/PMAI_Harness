"""Single source of truth for active work stage display metadata.

当前 stage 只是 UI 展示提示：
- 「项目底座」是项目级、init 时建（PRODUCT-STATE / DESIGN / 主原型），不是 per-work stage。
- 活跃工作展示收敛成 4 个阶段：
    1 设计      —— `/pmai-design` 产出模块三件套，`spec.md` 是 build 锚点
    2 build     —— `/pmai-build` 对着模块 `spec.md` 在 prototype/ 建
    3 复审      —— 覆盖审计 / 视觉门 / 行为审 + PM 体验迭代
    4 沉淀      —— `/pmai-build-close` 更新 PRODUCT-STATE / PRODUCT-RULES / 模块规格并收尾

stage 名供 status-view / banner / skills 文案复用。不存在单独的 stage 推进脚本。

显示已转产品轴（banner/status 播报"产品现状 + 主原型状态 + 本次增量"，不再播
"Stage N/M"），故 stage 编号是**内部状态标记**、不再 PM-facing。
"""

from __future__ import annotations

# per-work 展示阶段数。项目底座不计入（项目级）。
MAX_STAGE: int = 4

STAGE_NAMES: dict[int, str] = {
    1: "设计",
    2: "build",
    3: "复审",
    4: "沉淀",
}

# Stage N 的默认文档产物映射，仅供展示/提示代码引用。
# 当前只有「设计」有法定文档产物（spec.md）；build / 复审 / 沉淀不靠
# 单一 .md 文件做机器闸门。
STAGE_OUTPUT_FILES: dict[int, str] = {
    1: "spec.md",
}
