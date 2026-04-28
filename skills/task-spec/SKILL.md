---
name: task-spec
description: |
  Stage 6：按 task-plan.md 为单个 task 同时生成 PM 视图（templates/task.md.tmpl）+ 工程合同（templates/task.engineering.md.tmpl）两文件，等待 PM 确认后再进入 /task-confirm。
---

# /task-spec

## When To Use

- PM 在 stage 6 调用，参数是 task id（如 `/task-spec task-001`）
- 用于从 `task-plan.md` 中的单行 task 生成完整的 `tasks/task-NNN-<slug>.md`（PM 视图）+ `tasks/task-NNN-<slug>.engineering.md`（工程合同）

## PM 视图规则（必读）

本 skill 生成的文档须遵守 `skills/_shared/PM-VIEW-RULES.md`。
特别注意：
- **§三 PM 视图写作规则**（明确指代 / 正向描述 / 禁工程词 / 禁像素颜色 / 禁反向约束）
- **§五 功能清单格式**（强制三列表 + 数字编号列表）
- **§六 关键产品决策格式**
- **§七 章节顺序约束**（按 `templates/task.md.tmpl` + `templates/task.engineering.md.tmpl`）
- **§九 输入流约束**（必读上游 stage 文档 + 项目级文档；输入清单见下方 Required Inputs）
- **§9.4 PM 反馈三类分流**（正向规则 → 跨功能产品规则 / 反向约束 → 工程合同 §6 / 决策记录 → 关键产品决策）

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-spec"
```

## Required Inputs

按 `PM-VIEW-RULES.md §9.1` 表格执行。

### 写 task-NNN-<slug>.md（PM 视图）必读

**上游 stage 文档**：
- `$ACTIVE_REQ_DIR/brief.md`
- `$ACTIVE_REQ_DIR/analysis.md`
- `$ACTIVE_REQ_DIR/task-plan.md`（取本 task 元数据）
- `$ACTIVE_REQ_DIR/solution.md`（PM 视图，按"所属模块 / 功能 / task 标题关键词"匹配章节）
- 同模块已完成 task 的 PM 视图文件（`tasks/task-*.md`）

**项目级文档**（仓库存在则**必读**）：
- `$REPO_ROOT/docs/CONTEXT.md`
- `$REPO_ROOT/docs/DESIGN.md`
- `$REPO_ROOT/docs/prd.md`
- `$REPO_ROOT/docs/modules/<module>.md`（当前 task 所属模块）
- `$REPO_ROOT/prototypes/`（按相关性扫现有页面 / 组件，反向校验 + 判断已存在能力）

**不读**：`solution.engineering.md` / 任何 `.engineering.md`（防止工程内容渗透 PM 视图）

### 写 task-NNN-<slug>.engineering.md（工程合同）补充输入

- `$ACTIVE_REQ_DIR/analysis.md`
- `$ACTIVE_REQ_DIR/solution.engineering.md`（按章节匹配，写入对应工程合同章节）
- 同模块已完成 task 的 `.engineering.md`（如有）
- `$REPO_ROOT/docs/DESIGN.md` / `docs/prd.md` / `docs/modules/<module>.md`
- `$REPO_ROOT/prototypes/`

## Workflow

### 步骤 0：读 PM-VIEW-RULES.md（强制）

打开 `skills/_shared/PM-VIEW-RULES.md`，重点理解 §三 / §五 / §六 / §七 / §九。

### 步骤 1：校验 task-plan.md ↔ tasks/ 一致性

读取 `$ACTIVE_REQ_DIR/task-plan.md` 中的 task id 列表，并扫描 `$ACTIVE_REQ_DIR/tasks/task-NNN-*.md`（PM 视图主文件）。

校验差异：
- `task-plan.md` 有、`tasks/` 没有：提示 PM 这些 task 尚未生成详细文档。
- `tasks/` 有、`task-plan.md` 没有：提示 PM 这些 task 文件已脱离计划。
- **`task-NNN-*.md` 存在但 `task-NNN-*.engineering.md` 缺失（成对校验）**：提示 PM 工程合同缺失。

发现差异时先暂停，要求 PM 选择处理路径，未选择前不生成新文件。

### 步骤 2：读取 task 元数据

从 `task-plan.md` 中定位参数指定的 `<task-id>`，提取：
- id / 标题 / 所属模块 / 所属模块章节 / summary / 依赖

如果找不到 `<task-id>`，停止并提示 PM 先修正 `task-plan.md`。

### 步骤 3：读取所有必读输入

按上方 Required Inputs 列出的文件**逐一读取**：
- 上游 stage 文档（brief / analysis / task-plan / solution PM 视图 / 同模块已完成 task 的 PM 视图）
- 项目级文档（CONTEXT / DESIGN / prd / modules / prototypes）

**特别注意**：
- 项目级文档列为"必读"——AI 不得以"觉得不必要"为由跳过
- `prototypes/` 必读（PM-VIEW-RULES §9.3）：
  - 判断当前 task 涉及的现有页面 / 组件 / 已落地能力
  - 反向校验上游文档：原型已删除 / 砍掉的工程概念不引入 PM 视图

### 步骤 4：基础设施 task 走简化路径

如果 `所属模块` 为 `基础设施`：
- `所属模块章节` 留空
- `用户使用流程` 填 `无（基础设施 task）`
- `功能清单` 填 `无（基础设施 task）`
- `产物预览` 填 `无（基础设施 task）`
- `验收清单` 必须填写可验证条件
- 工程合同的 §4 功能清单工程版同样填 `无（基础设施 task）`，但其它章节（启动前必读 / 实现指引 / 工程层验收清单）正常填

明确告知 PM：

```
本 task 不触发 module 规格 merge（按 Q1 决议）。
```

基础设施 task 仍生成两文件（PM 视图 + 工程合同），但模块规格沉淀路径由 doc-update 跳过。

### 步骤 5：收集同模块已完成 task 的 PM 反馈，按三类分流

**核心改动**：不再整段搬到「实现指引-易错点」。按 PM-VIEW-RULES §9.4 分三类：

扫描 `tasks/task-*.md` 中状态为「已完成」且所属模块与当前 task 有交集的文件，从其 `## PM 反馈` section 抽取条目。

每条反馈按特征分类（参见 PM-VIEW-RULES §9.4 表）：

| 反馈类型 | 识别特征 | 写入位置 |
|---|---|---|
| **正向规则** | "统一用 X" / "全文用 Y" / "应该按 Z 处理" | 当前 task PM 视图的 `## 🚦 跨功能产品规则` 节 |
| **反向约束** | "禁用 X" / "不要 Y" / "不允许 Z" | 当前 task 工程合同的 `## 6. 易错点 / 禁止项` 节 |
| **决策记录** | "改为 X" / "二审决定 Y" / "重做为 Z" | 当前 task PM 视图的 `## 🎯 关键产品决策` 节（备选方案列标注"已被 PM 反馈推翻"）|

**禁止**：把 PM 反馈整段搬到工程合同的「实现指引」section（这是当前的反模式）。

只抽取仍然适用于当前 task 的条目；不要搬运已解决的单点 bug。

### 步骤 6：拉取相关 solution 内容并按视图分流

读取 `solution.md`（PM 视图）和 `solution.engineering.md`（工程合同），按"所属模块 / 功能 / task 标题关键词"匹配相关章节。

分流规则：

| solution 来源 | 写入位置 |
|---|---|
| `solution.md` §🎯 关键产品决策 中与当前 task 相关的决策 | 当前 task PM 视图 §🎯 关键产品决策 |
| `solution.md` §📦 交付物清单 | 当前 task PM 视图 §📦 范围 |
| `solution.md` §🖼 页面 UI 骨架 | 当前 task PM 视图 §📐 产物预览（线框图）|
| `solution.md` §✅ 验收标准 | 当前 task PM 视图 §✅ 验收清单 |
| `solution.engineering.md` §1 数据结构 / §2 派生状态 / §3 组件路径 | 当前 task 工程合同 §4 功能清单工程版 |
| `solution.engineering.md` §6 易错点 / §7 plan-review 沉淀 | 当前 task 工程合同 §6 易错点 / §7 plan-review 沉淀 |

**只引用路径和章节，不大段复制原文**；把相关内容**转写**为 task 级可验收内容。

### 步骤 7：生成产物预览

按 task 类型判断并生成对应的产物预览：

**判定优先级**（从上往下匹配）：

1. **UI task** — 审查工具含 `/design-review`，或 task 描述涉及 `页面 / 组件 / 界面 / 前端 / UI / view / component`：
   → 生成 **ASCII 线框图**
2. **纯文档 task** — 审查工具为空，且 task 描述含 `文档 / PRD / 规格 / 说明 / spec / readme`：
   → 生成 **bullet 树形大纲**
3. **其他**（基础设施 / 后端 / 全栈）：
   → 写 `无（[类型] task）`

**UI 线框图填写规则**：
- 用 markdown code block + ASCII 字符表达**信息层级 + 主要区块布局**
- 标注顶部信息区 / Tab / 主区域分块 / 关键操作入口位置
- **禁止**：像素值（24px）、字号、颜色码、emoji 视觉、组件库类名（Tailwind 等）→ 这些进 task.engineering.md §8

**大纲填写规则**：用 markdown bullet list 树形（嵌套 `-`），章节层级 2-3 级，章节名用产品视角的业务名（不是文件名 / 类名）。

### 步骤 8：写 task-NNN-<slug>.md（PM 视图）

按 `templates/task.md.tmpl` 生成 `$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md`：

**章节顺序**（强制，由 PM-VIEW-RULES §七锁定）：
1. 📌 任务卡（10 秒理解）
2. 🎯 关键产品决策
3. 📐 产物预览
4. 📋 功能清单
5. 🚦 跨功能产品规则
6. 📦 范围（改 / 不改）
7. ✅ 验收清单（PM 走查）
8. 📁 历史档案（执行日志 / PM 反馈）

**写作约束**（违反将由 `check-doc-pm-view.py` 报错）：
- 每个名词带完整指代前缀（PM-VIEW-RULES §3.1）
- 不出现像素值 / 颜色码 / Emoji 视觉（§3.2）→ 进 task.engineering.md §8
- 不出现反向约束（"禁止 / 不允许"，§3.4）→ 进 task.engineering.md §6
- 不出现工程词（reducer / dispatch / props / hook / TS 类型签名）→ 进 task.engineering.md §4
- 功能清单遵守 §五格式（N · 功能名 + 三列表 + 数字编号列表）

**模板替换**：
- `{{TASK_NUMBER}}` → 三位数编号
- `{{TASK_NAME}}` → task 标题
- `{{TASK_SLUG}}` → 英文 kebab-case slug
- `{{REVIEW_TOOLS}}` → 根据 task 类型给默认值
- `{{CREATED_DATE}}` → 当前日期 YYYY-MM-DD
- `{{REQ_ID}}` / `{{REQ_SLUG}}` → 来自当前 req 元数据

### 步骤 9：写 task-NNN-<slug>.engineering.md（工程合同）

按 `templates/task.engineering.md.tmpl` 生成 `$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.engineering.md`：

**章节顺序**（按模板锁定）：
1. 元信息扩展（executor / model）
2. 状态转换说明（agent 必读）
3. 启动前必读
4. 功能清单工程版（实现层细节）
5. 实现指引
6. 易错点 / 禁止项
7. plan-design-review / plan-eng-review 沉淀
8. a11y / 视口 / 视觉规范细则
9. 工程层验收清单
10. 文档偏差（execution agent 填写）
11. 自审记录

**写作约束**：
- 允许所有工程内容（TS 类型 / 字段名 / 像素 / 颜色 / 反向约束 / V1-V26 review 沉淀等）
- 唯一原则：不重复 PM 视图已有的功能行为描述

**§3 启动前必读**应包含：
1. `solution.md` §X 的相关章节
2. `solution.engineering.md` §Y 的相关章节
3. `task-plan.md` 风险条目 + `task-plan.engineering.md` §1 反模式 / §2 验收 GAP
4. 项目级文档（CONTEXT / DESIGN / 当前模块 spec）
5. 同模块已完成 task 的 PM 视图 + 工程合同
6. 涉及的现有 prototype 文件路径

### 步骤 10：自检（按 PM-VIEW-RULES §八 8 项）

写完后对 PM 视图主文件逐条检查：
- [ ] 章节顺序符合 templates/task.md.tmpl
- [ ] 所有名词带完整指代前缀
- [ ] 无像素值 / 颜色码 / Emoji 视觉
- [ ] 无反向约束
- [ ] 无组件实现名
- [ ] 无设计意图解释
- [ ] 抽象动词都搭配具体效果
- [ ] 功能清单符合统一格式（§五）

任一项未通过 → 修复后重新自检。

### 步骤 11：输出"推荐 review 工具"区块（不自动调任何 review）

按 task 类型给出推荐清单。**AI 不得自动调用任何 review skill**（I-RV1）。

业务模块 task 推荐区块：

```
✅ task 文件已生成：
  PM 视图：<task-pm-view-path>
  工程合同：<task-engineering-path>

可选 review（PM 自行选跑，跑完贴结论我帮你 append 事件）：
  /plan-eng-review     — 架构、数据流、边界、依赖合理性
  /plan-design-review  — 交互与视觉层问题、UI 完整性
  /autoplan            — 上述两个的批量打包

跑哪几个由你决定，全跳也可以。
```

基础设施 task 推荐区块（去掉 design）：

```
✅ task 文件已生成：
  PM 视图：<task-pm-view-path>
  工程合同：<task-engineering-path>

可选 review（PM 自行选跑，跑完贴结论我帮你 append 事件）：
  /plan-eng-review     — 脚手架/共用能力的设计合理性

跑哪几个由你决定，全跳也可以。
```

#### 11.1 PM 跑完 review 后的事件 append（机械记录，I-RV2）

PM 在 chat 里报告"跑了 /plan-eng-review，pass，发现 N 条"之类结论后，AI 调以下命令记录事件作为审计痕迹：

```bash
python3 .claude/scripts/task-events.py append "<task-pm-view-file>" \
  --type plan_review_completed \
  --tool /plan-eng-review \
  --result pass \
  --payload "{\"finding_count\": <发现条数>, \"finding_summary\": \"<一句话摘要>\"}"
```

> 事件追加在 PM 视图主文件上（`task-NNN-*.md`），不追加在 `.engineering.md`。

**禁止**（I-RV3）：先 append 后跑、跳过 PM 直接 append、凭文档对照模拟出 review 结论。append 必须发生在 PM 明确报告结果之后。

#### 11.2 PM 跑了 review 后的修改决策（仅当 PM 选择跑了）

PM 跑完 review 决定采纳发现：

- 修改 PM 视图主文件 / 工程合同 → 提示 PM 是否要重新跑对应 review → 跑完再 append 事件（最后一条为准）

PM 看完不改 / 不跑 review：直接进步骤 12。事件流缺事件不阻塞推进（I-RV2，task-confirm 不再 hard gate）。

### 步骤 12：展示生成结果并等待 PM 确认

向 PM 展示摘要和两文件路径，不直接进入执行：

```
已生成 task 详细文档：
  PM 视图：<绝对路径>
  工程合同：<绝对路径>

摘要：
- Task: task-NNN-<slug>
- 所属模块：[模块]
- 所属模块章节：[章节]
- 用户使用流程 / 功能清单：[N 个场景 / N 节] / 基础设施 task 为无
- PM 反馈分流：[正向规则 X 条 / 反向约束 Y 条 / 决策记录 Z 条 / 无]
- review：[PM 已跑 /plan-eng-review pass / 未跑 /plan-design-review / 全跳]

A) 确认，下一步执行 /task-confirm <task-pm-view-file>
B) 我要修改 task 文档（指出改 PM 视图还是工程合同）
C) 放弃本次生成（两文件一起删）
```

PM 选择 A 后，才提示并推动 `/task-confirm <task-pm-view-file>`；PM 未确认前不得进入执行。

## Rules

- 一次只生成一个 task 的两个文件（PM 视图 + 工程合同）；不支持批量生成。
- 两文件成对出现，PM 视图主文件路径不变（`task-NNN-<slug>.md`），工程合同同目录同 slug + `.engineering.md` 后缀。
- 不编辑其他 task 文件；如一致性校验发现多余 task，只能在 PM 选择后删除明确列出的多余文件（成对删除）。
- 不创建、不修改 `docs/modules/*.md`；模块规格沉淀由 `/doc-update` 在 task 通过后处理。
- 不修改 `task-plan.md`；如果元数据缺失或不一致，提示 PM 先修正。
- 不复制 solution 大段原文，只引用路径和章节，并转写为 task 级可验收内容。
- 只有 PM 确认生成结果后，才推动 `/task-confirm`。
- 基础设施 task 必须明确说明：`本 task 不触发 module 规格 merge（按 Q1 决议）`。
- 业务模块 task 的功能清单必须能被后续 doc-update 按「所属模块章节 + 三级功能名」匹配。
- AI 不得自动调任何 plan review skill（I-RV1）；只在步骤 11 输出推荐清单，PM 自跑。
- PM 报告 review 结论后才 append `plan_review_completed` 事件（I-RV3）；禁止"先 append 后跑"或凭文档对照模拟。
- 事件流仅作审计记录（I-RV2），缺事件不阻止 task-confirm 启动；review 发现是否采纳由 PM 自行决定。
- **PM 反馈分流强制**：抽取同模块已完成 task 的 PM 反馈时，必须按 PM-VIEW-RULES §9.4 分三类分别写入；禁止整段搬到工程合同「实现指引」。
- **跳过项目级文档"必读"被禁止**：CONTEXT / DESIGN / prd / modules / prototypes 仓库存在则必读，AI 不得跳过。
