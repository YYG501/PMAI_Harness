---
name: task-spec
description: |
  Stage 6：按 task-plan.md 为单个 task 生成详细 task 文档，等待 PM 确认后再进入 /task-confirm。
---

# /task-spec

## When To Use

- PM 在 stage 6 调用，参数是 task id（如 `/task-spec task-001`）
- 用于从 `task-plan.md` 中的单行 task 生成一个完整的 `tasks/task-NNN-<slug>.md`

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-spec"
```

## Workflow

### 步骤 1：校验 task-plan.md ↔ tasks/ 一致性

读取 `$ACTIVE_REQ_DIR/task-plan.md` 中的 task id 列表，并扫描 `$ACTIVE_REQ_DIR/tasks/task-NNN-*.md`。

校验差异：
- `task-plan.md` 有、`tasks/` 没有：提示 PM 这些 task 尚未生成详细文档。
- `tasks/` 有、`task-plan.md` 没有：提示 PM 这些 task 文件已脱离计划。

发现差异时先暂停，要求 PM 选择：

```
检测到 task-plan.md 与 tasks/ 不一致：
- plan 有但 tasks/ 缺失：[task-id 列表]
- tasks/ 有但 plan 缺失：[task 文件列表]

请选择处理方式：
A) 保留 task-plan.md，删除多余 task 文件
B) 保留 tasks/，请先手动把缺失条目补回 task-plan.md
C) 暂停，我手动处理
```

PM 未选择前不生成新文件。

<!-- TODO Batch 2: depends on task-plan SKILL change -->

### 步骤 2：读取 task 元数据

从 `task-plan.md` 中定位参数指定的 `<task-id>`，提取：
- id
- 标题
- 所属模块（一个或多个业务模块，或 `基础设施`）
- 一句简述 / description
- 依赖和执行顺序提示（如有）

如果找不到 `<task-id>`，停止并提示 PM 先修正 `task-plan.md`。

### 步骤 3：拉取相关 solution.md 内容

读取 `$ACTIVE_REQ_DIR/solution.md`，按「所属模块 / 功能 / task 标题关键词」匹配相关章节。

输出 task 文档时只引用路径和章节，不大段复制原文；把相关内容转写为：
- 用户使用流程
- 功能清单
- 实现指引 - 关键逻辑
- 用例数据（如 solution.md 提供，写入最相关的 task section，不新增独立顶层 section）

### 步骤 4：读取当前模块规格状态

对每个业务模块读取 `$REPO_ROOT/docs/modules/<module>.md`（如存在），重点查看：
- 已有功能清单
- 所属模块章节是否已存在
- 与当前 task 可能重复或需要延续的三级功能

如果模块规格不存在，记录为「待由后续 doc-update 沉淀创建」，不要在本 skill 中创建模块规格。

### 步骤 5：收集同模块已完成 task 的 PM 反馈

扫描 `$ACTIVE_REQ_DIR/tasks/task-*.md` 中状态为「已完成」且所属模块与当前 task 有交集的文件。

从这些文件的 `## PM 反馈` section 抽取可复用经验，写入当前 task 的「实现指引」：

```
- **易错点 / 禁止项**：[反馈摘要]（来自 task-XXX 的 PM 反馈）
```

只抽取仍然适用于当前 task 的行为规则、验收偏差和禁止项；不要搬运已解决的单点 bug。

### 步骤 6：基础设施 task 走简化路径

如果 `所属模块` 为 `基础设施`：
- `所属模块章节` 留空
- `用户使用流程` 填 `无（基础设施 task）`
- `功能清单` 填 `无（基础设施 task）`
- `产物预览` 填 `无（基础设施 task）`
- `验收标准` 必须填写可验证条件（例如脚手架可启动、脚本可运行、API client 可调用）
- 明确告知 PM：

```
本 task 不触发 module 规格 merge（按 Q1 决议）。
```

基础设施 task 只生成 task 文件，不创建或修改 `docs/modules/*.md`。

### 步骤 6.5：根据 task 类型生成产物预览

按以下规则判断 task 类型并生成对应的产物预览，写入 task 文件的 `## 产物预览` section：

**判定优先级（从上往下匹配）**：

1. **UI task** — 审查工具含 `/design-review`，或 task 描述涉及 `页面 / 组件 / 界面 / 前端 / UI / view / component`：
   → 生成 **ASCII 线框图**
2. **纯文档 task** — 审查工具为空，且 task 描述含 `文档 / PRD / 规格 / 说明 / spec / readme`：
   → 生成 **bullet 树形大纲**
3. **其他**（基础设施 / 后端 / 全栈）：
   → 写 `无（[类型] task）`

#### UI 线框图生成要求

**输入**：
- solution.md 该 task 涉及的页面描述
- 步骤 5 收集的「用户使用流程」场景
- Glob 扫描同模块已有页面（如 `src/pages/<module>/*.tsx`），参考布局风格

**输出**：用 markdown code block + ASCII 字符画线框图，必须包含：
- 顶部信息区（标题 / 状态 Badge / 副信息）
- 主区域分块（Tab / 列表 / 表单 / 弹窗等）
- 关键操作入口位置（按钮名称 + 大致位置）

**禁止**：像素值、字号、颜色、动效曲线、具体组件库类名。

**创意自由度边界**（DESIGN.md §创意自由度）：
- 信息层级（哪个先看哪个后看）→ **低自由度**：agent 实现时必须遵守线框图的层级
- 视觉细节（卡片样式 / 间距 / 颜色 / 微交互）→ **高自由度**：agent 实现时自由发挥

#### 大纲生成要求

**输入**：
- 步骤 3 拉的 solution.md 相关节
- 步骤 5 的功能清单内容
- 用户使用流程场景

**输出**：用 markdown bullet list 树形（嵌套 `-`），章节层级 2-3 级：

```markdown
- 第 1 章：[章节名]
  - 1.1 [子节]
  - 1.2 [子节]
- 第 2 章：[章节名]
  - 2.1 ...
```

#### 其他 task 类型

跳过此 section 的内容生成，写：
- 后端/API task：`无（后端 task）`
- 全栈 task：`无（全栈 task；线框图见同 req 的 UI task）`
- 其他：`无（[类型推断] task）`

### 步骤 7：生成 task 文件

读取 `$REPO_ROOT/templates/task.md.tmpl`，生成 `$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md`。

替换规则：
- `{{TASK_NUMBER}}` → 三位数编号（001, 002, ...）
- `{{TASK_NAME}}` → task 标题
- `{{TASK_SLUG}}` → 英文 kebab-case slug
- `{{REVIEW_TOOLS}}` → 根据 task 类型给默认值
- `{{MODULE_NAME}}` → 主所属模块；基础设施 task 填 `基础设施`
- `{{CREATED_DATE}}` → 当前日期 YYYY-MM-DD

填写要求：
- 顶部 `所属模块` 和 `所属模块章节` 必填（基础设施 task 的章节留空）。
- 跨模块 task 的 `所属模块章节` 使用 `模块A:章节X, 模块B:章节Y` 格式。
- `## 依赖` section 必须使用结构化 task ID 列表，供 `/task-confirm` 主防线和 `/task-execute` 兜底层机器解析：
  ```markdown
  ## 依赖
  - task-002 (列表页 — 需要它的 list state 接口)
  - task-003 (详情页 — 需要它的 detail fetcher)
  ```
  无依赖时仍写 `无`。不允许写成自然语言描述，例如 `依赖 task-2 和 task-3` 或 `需要先完成列表页和详情页`。机器解析规则只提取 `task-NNN`。
- 业务模块 task 必须填写 `用户使用流程` 和 `功能清单`。
- 功能清单使用三级功能块格式：`### N · [三级功能名]` + 三列表格 + 编号需求列表。
- 功能清单只写功能行为、数据规则、角色权限；禁止写字号、颜色、像素值、组件库具体实例。
- `实现指引` 只写对实现有帮助的 bullets；没有内容的 bullet 直接省略。
- `验收标准`：业务模块 task 可省略；基础设施 task 必填。
- 保留模板中的状态机引导、执行日志、文档偏差、自审记录、PM 反馈等 section。

<!-- TODO Batch 2: depends on task-plan SKILL change -->

### 步骤 8：默认 review（task-spec 写完后，PM 确认前）

按 task 类型默认跑 review，发现直接贴 chat（讨论性，不写盘）：

- **业务模块 task** → 自动调用 `/plan-eng-review` + `/plan-design-review`，审阅刚生成的 `tasks/task-NNN-*.md`。
- **基础设施 task** → 只调用 `/plan-eng-review`，跳过 `/plan-design-review`（无 UI 内容可审）。

review 处理规则：

- review 发现存在 → 在 chat 中直接呈现 eng / design 视角的发现清单。
- PM 选择回去改 → 修改 `tasks/task-NNN-*.md` → 按本步骤规则重跑对应 review（eng 改了重跑 eng，design 改了重跑 design）→ 再走步骤 9。
- PM 选择忽略 review 发现继续 → 直接进步骤 9。

review 是讨论性的，不属于子 skill；不写盘、不入未决问题闸门。

### 步骤 9：展示生成结果并等待 PM 确认

review 走完（或 PM 选择忽略发现）后，只向 PM 展示摘要和文件路径，不直接进入执行：

```
已生成 task 详细文档：<绝对路径>

摘要：
- Task: task-NNN-<slug>
- 所属模块：[模块]
- 所属模块章节：[章节]
- 用户使用流程：[场景数 / 基础设施 task 为无]
- 功能清单：[三级功能数 / 基础设施 task 为无]
- 易错点来源：[N 条 PM 反馈 / 无]
- review：eng [PASS/有发现已处理/PM 忽略]，design [PASS/有发现已处理/PM 忽略/跳过(基础设施)]

A) 确认，下一步执行 /task-confirm <task-file>
B) 我要修改 task 文档
C) 放弃本次生成
```

PM 选择 A 后，才提示并推动 `/task-confirm <task-file>`；PM 未确认前不得进入执行。

## Rules

- 一次只生成一个 task 文件；不支持批量生成。
- 不编辑其他 task 文件；如一致性校验发现多余 task，只能在 PM 选择后删除明确列出的多余文件。
- 不创建、不修改 `docs/modules/*.md`；模块规格沉淀由 `/doc-update` 在 task 通过后处理。
- 不修改 `task-plan.md`；如果元数据缺失或不一致，提示 PM 先修正。
- 不复制 solution.md 大段原文，只引用路径和章节，并转写为 task 级可验收内容。
- 只有 PM 确认生成结果后，才推动 `/task-confirm`。
- 基础设施 task 必须明确说明：`本 task 不触发 module 规格 merge（按 Q1 决议）`。
- 业务模块 task 的功能清单必须能被后续 doc-update 按「所属模块章节 + 三级功能名」匹配。
- 业务模块 task 默认跑 `/plan-eng-review` + `/plan-design-review`；基础设施 task 只跑 `/plan-eng-review`。review 不可静默跳过，PM 可在看到发现后选择"忽略发现继续"。
