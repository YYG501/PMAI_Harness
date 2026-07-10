"""Single source of truth for active work stage display metadata.

当前 stage 只是 v1 兼容展示提示：
- 「项目底座」是项目级、init 时建，不是 per-work stage。
- v2 权威状态是 lifecycle：designing → ready_to_build → building → iterating
  → final_check → landed → documenting → complete。
- prototype / product 共用 lifecycle，只切换 build target 和验收适配器。
- PM 定稿后 `/pmai-build` 自动完成 final_check、landing 和 landed 后文档编译；
  `/pmai-build-close` 只作为兼容与恢复入口。

stage 名供 status-view / banner / skills 文案复用。不存在单独的 stage 推进脚本。

显示已转产品轴（banner/status 播报"产品现状 + 主原型状态 + 本次增量"，不再播
"Stage N/M"），故 stage 编号是**内部状态标记**、不再 PM-facing。
"""

from __future__ import annotations

# v1 per-work 展示阶段数。项目底座不计入（项目级）。
MAX_STAGE: int = 4

STAGE_NAMES: dict[int, str] = {
    1: "设计",
    2: "build",
    3: "复审",
    4: "沉淀",
}

# build contract v2 lifecycle is the preferred PM-facing state. `stage` stays
# readable for v1 consumer repositories and old timeline fixtures.
LIFECYCLE_NAMES: dict[str, str] = {
    "designing": "需求讨论",
    "ready_to_build": "设计已定",
    "building": "构建中",
    "iterating": "看结果并修改",
    "final_check": "最终检查",
    "landed": "已进入主线，待更新文档",
    "documenting": "更新正式文档",
    "complete": "完成",
}

# Stage N 的默认文档产物映射，仅供展示/提示代码引用。
# 当前只有「设计」有法定文档产物（spec.md）；build / 复审 / 沉淀不靠
# 单一 .md 文件做机器闸门。
STAGE_OUTPUT_FILES: dict[int, str] = {
    1: "spec.md",
}
