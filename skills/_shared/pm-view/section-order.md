# §七 章节顺序约束（按文档类型）

> 本文件是 [`PM-VIEW-RULES.md`](../PM-VIEW-RULES.md) §七 的物理拆分。配套阅读：主文件 §五（功能清单格式）/ §六（关键产品决策格式）。

## `task-plan.md` 章节顺序（单文件）

```
1. 📌 拆分摘要
2. 一、Task 列表
3. 二、执行顺序与并行性
4. 三、风险
5. 四、自检与状态摘要（反模式自检 5 条 + 验收 GAP 清单 + 模块规格状态）
---
6. 📁 历史档案（变更记录）
```

`task-plan.md` 不拆双文件——§四 是 task-plan 自身的轻量自检结论 + task-spec / doc-update 会消费的状态索引，不是 PM 阅读层内容也不需要独立文件存档。

## `tasks/task-NNN.md` 章节顺序（delta-3：单文件 typed contract）

task-spec 产**单文件 typed contract**（头部 `<!-- task_format: single-typed-v3 -->`），
内部分三区，由 region 标记界定。章节顺序：

```
<!-- region: PM-CONFIRM begin -->   ← PM 确认区（PM 在确认门读这一区；scoped PM-view lint）
1. 📌 任务卡（含 executor / executor_model / 审查工具 字段）
2. 📦 范围（改 / 不改）
3. ✅ 验收清单（PM 走查）
4. 📥 PM 反馈承接清单
<!-- region: PM-CONFIRM end -->

<!-- region: EXEC begin -->          ← 执行区（executor 实现依据；允许工程内容；不跑 PM-view lint）
5. 🔁 状态转换说明
6. 🚦 启动前必读
7. 🔧 实现规格
8. 🧩 实现设计引用（HOW-ID 行 + task-scoped 占位值）
9. ⚠️ 约束与易错
10. 🧪 自测说明（task-verify 自动跑；非 UI task 写「无」）
11. ✔️ 工程层验收
<!-- region: EXEC end -->

<!-- region: AUDIT begin -->         ← 审计区（executor / PM 填；不 lint）
12. 📋 文档偏差（task-transition「执行中→已完成」gate 锚点 + delta-7 adjustment-promote 源）
13. 🔍 自审记录（同上 gate 锚点）
14. 📁 历史档案（执行日志 / PM 反馈 / plan-review 沉淀）
<!-- region: AUDIT end -->
```

> 旧 v2 双文件（PM 视图 `.md` + 工程合同 `.engineering.md`）已废 —— task-spec 双→单文件
> 塌缩（delta-3）。WHAT 移 `prd.md`（关键产品决策 / 产物预览 / 功能清单 / 跨功能规则）、
> HOW 移 `implementation-design.md`，task 文件只留 task 级 typed contract。在飞旧 v2 task
> 跑完旧的、不回迁。

## `brief.md` / `analysis.md` / `prd.md`

各 skill 内已定义章节，本文件不重复约束（这三份不拆文件、章节已稳定）。
