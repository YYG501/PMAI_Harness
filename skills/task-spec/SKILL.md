---
name: task-spec
description: |
  Stage 6：按 task-plan.md 为单个 task 生成单文件 typed contract（$REPO_ROOT/templates/task.md.tmpl）——
  内部分 PM 确认区 / 执行区 / 审计区三区；读 prd.md（WHAT）+ implementation-design.md（HOW）。
  等待 PM 在唯一确认门定稿后推进 /task-confirm。
---

# /task-spec

## When To Use

- PM 在 stage 6 调用，参数是 task id（如 `/task-spec task-001`）
- 用于从 `task-plan.md` 中的单行 task 生成完整的 `tasks/task-NNN-<slug>.md`（单文件 typed contract）

## 单文件 typed contract（delta-3）

task-spec 产 **1 个物理文件** `tasks/task-NNN-<slug>.md`（不再产 `.engineering.md`）。
文件头部带 `<!-- task_format: single-typed-v3 -->` 标记，内部分三区：

| 区 | 含哪些段 | lint |
|---|---|---|
| **PM 确认区** | 任务卡（含 executor/model）/ task 级范围 / task 级验收清单 / PM 反馈承接清单 | `check-doc-pm-view.py` scoped 模式（只校验本区，守 PM-view 写作纪律）|
| **执行区** | 启动前必读 / 实现规格 / 实现设计引用（HOW-ID 行 + 占位值）/ 约束与易错 / 自测说明 / 工程层验收 / 状态转换说明 | 字段格式校验；允许工程内容 |
| **审计区** | 文档偏差 / 自审记录 / 历史档案 | 不 lint |

PM 在确认门**只读且只需读 PM 确认区**即可判 scope。三区由 region 标记
（`<!-- region: PM-CONFIRM begin/end -->` 等）界定。

## PM 视图规则

PM 确认区遵守 `skills/_shared/PM-VIEW-RULES.md`（写作纪律：明确指代 / 正向描述 /
禁工程词 / 禁像素颜色 / 禁反向约束）。执行区允许所有工程内容，不跑 PM-view lint。
- `_shared/pm-view/writing-rules.md`（§三 写作规则）—— 只约束 PM 确认区
- `_shared/pm-view/section-order.md`（§七 章节顺序，按 `task.md.tmpl`）

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-spec"
```

## Required Inputs

| 输入 | 用途 |
|---|---|
| `task-plan.md` | task 元数据 |
| `prd.md`（delta-2）| req 级 WHAT —— 挑当前 task 切片转写进执行区·实现规格 + PM 确认区·验收 |
| `implementation-design.md`（delta-8）| req 级 HOW —— 按 `HOW-ID` + 适用关键词挑当前 task 相关行；**段 1.5「原型简化项」按 PRD 锚点 join 当前 task**（v2 D5）：命中 → 实现规格 + 验收按简化后写 + 受影响验收项行内 `[SIMP-N]` 标签 |
| `docs/PROJECT.md` / `docs/DESIGN.md` / `docs/modules/` | 项目级背景 |
| `docs/PRODUCT-RULES.md`（delta-9）| 跨功能产品行为规则 —— 读全部 `scope=全局` 规则 + 按当前 task 模块 / 功能关键词 grep 命中的 `scope=域限定` 规则（§9.1.1 章节-grep；`scope=全局` 永远纳入、不漏跨功能规则）。命中的规则写进执行区·约束与易错 |
| 前序「已完成」task 的「PM 反馈」段 | same-req 反馈 lane（§步骤 5 relevance 二分）|
| **stage 2 真相源**（A 分支 `analysis.md` / B 分支 `stage2-office-hours.md`；路径由 `get_stage_source(req_dir, 2)` 解析）| ⚪ 按需 lazy fallback —— 不默认读；PRD 切片不足时回读对应章节并在 chat 告知 PM |

特别遵守 `input-flow.md §9.1.1` 章节匹配强约束（按章节 grep 局部读，不整文件 Read 大文件）。

## Workflow

### 步骤 1：校验 task-plan.md ↔ tasks/ 一致性

读 `$ACTIVE_REQ_DIR/task-plan.md` 的 task id 列表，扫 `$ACTIVE_REQ_DIR/tasks/task-NNN-*.md`。

校验差异：
- `task-plan.md` 有、`tasks/` 没有：提示这些 task 尚未生成详细文档。
- `tasks/` 有、`task-plan.md` 没有：提示这些 task 文件已脱离计划。

发现差异时先暂停，要求 PM 选择处理路径。

### 步骤 2：读取 task 元数据

从 `task-plan.md` 定位参数指定的 `<task-id>`，提取：id / 标题 / 所属模块 / 所属模块章节 /
summary / 依赖。找不到 → 停止并提示 PM 先修正 `task-plan.md`。

### 步骤 3：读取所有必读输入

按上方 Required Inputs 逐一读取。**特别注意**：
- 项目级文档列为"必读"，AI 不得以"觉得不必要"为由跳过。
- `prd.md` 是 WHAT（req 级功能规格）；`implementation-design.md` 是 HOW（req 级实现设计）。
  两者分工：实现规格从 PRD 切片转写，实现设计引用从 implementation-design 按 HOW-ID 挑。
- **stage 2 真相源**（A 分支 `analysis.md` / B 分支 `stage2-office-hours.md`，路径由 `get_stage_source(req_dir, 2)` 解析）不默认读；仅当 PRD 切片不足以写清 task 时回读对应章节，并在 chat 告知 PM「PRD 此切片不足，已回读 stage 2 真相源 §X」。

### 步骤 4：基础设施 task 走简化路径

`所属模块` 为 `基础设施` 时：`所属模块章节` 留空；执行区·实现规格填可执行的脚手架要求；
PM 确认区·验收清单必须填可验证条件；告知 PM「本 task 不触发 module 规格 merge」。

### 步骤 5：收集前序 PM 反馈，按 relevance 二分（delta-3 §2.4）

扫前序「已完成」task 文件的「PM 反馈」段（按 `input-flow.md §9.1.1`：grep `^### 反馈`
/ `^## .*PM 反馈` 命中行后局部读，**不整文件 Read**）。同 req 内 + closed/ 下旧 task 都扫。

每条反馈按 **relevance 二分**（不是 sentiment 三类 —— 单文件后投递地址只有一个）：

| relevance | 判别 | 处理 |
|---|---|---|
| **适用当前 task** | 反馈涉及的模块 / 功能落在当前 task 范围内 | 写进执行区·约束与易错段（标来源 task）|
| **不适用** | 反馈涉及别的模块 / 功能 | 留在原 task 文件不动 |

relevance 具体可判（模块 / 功能是否落在当前 task 范围），不需解读语气。

**每条反馈都写进 PM 确认区·「PM 反馈承接清单」**（一行：来源 task / 原文摘要 /
relevance / 处理结果 / 一句理由）—— 让「不适用」对 PM 可观测、可纠误判。无前序反馈 →
写「无前序 PM 反馈」。

> **跨模块反馈 = 已知 gap**：属「全项目跨功能产品行为规则」的反馈，relevance 二分装不下 ——
> 由 close-task PM-selective promote 到 `docs/PRODUCT-RULES.md`（delta-9）；task-spec 不在此处理。

### 步骤 6：从 prd.md 挑切片 + implementation-design.md 按 HOW-ID 挑行 + 段 1.5 SIMP 行 join

**`prd.md`（WHAT）**：按"所属模块 / 功能 / task 标题关键词"匹配 PRD §六 功能需求 /
§七 验收标准的相关章节（`input-flow.md §9.1.1` 章节 grep 局部读）。挑出当前 task 切片：
- PRD §六 功能需求相关条目 → 转写为执行区·实现规格（task 级可执行规格 + 实现层细节）
- PRD §七 验收标准相关条目 → 转写为 PM 确认区·task 级验收清单

**`implementation-design.md`（HOW）**：按 `HOW-ID` + 适用模块 / 适用 task 关键词，挑出
当前 task 相关的 HOW 行，写进执行区·「实现设计引用」段（带原 HOW-ID 便于追溯）。
task-execute 只读 task 单文件、不跨文件回查 implementation-design —— 所以 HOW 行必须
在此挑全。

**`implementation-design.md` 段 1.5「原型简化项」按 PRD 锚点 join 当前 task**（v2 D5）：
段 1.5 是 `implementation-design.md` 内的特殊段，不带 HOW-ID 而带 `SIMP-ID`。join 规则：

1. 列出当前 task 从 PRD §六 挑出的章节锚（如「§六 6.3 用户登录」「Story 4」）
2. 对段 1.5 每条 SIMP 行的「PRD 锚点」字段做章节号 + 功能名匹配；命中 → 本条 SIMP 适用当前 task
3. 命中的 SIMP 行：
   - 把「原型本次计划简化为」内容**改写进**执行区·实现规格的对应功能段（task 级实现要求按
     原型简化后写，不是按 PRD 全量写）—— executor 按简化版实施
   - 把「真实需求」引用挂在该实现规格段尾，提示 executor「PRD 的真实需求是 X，本期计划简化为 Y」
   - PM 确认区·task 级验收清单的受影响验收项行内追加 `[SIMP-N]` 标签（D6）
4. 0 命中 → 当前 task 无关简化项，按 PRD 全量写

**只引用、转写，不大段复制原文**。

### 步骤 7：派生 task-scoped 自测说明 + 占位值（UI task 必做，非 UI task 跳过）

task-spec 从 `prd.md §七` 验收标准派生 **task-scoped 自测说明**写进执行区·自测说明段
（让 task 文件对 task-verify 自包含）：
- 每个 task 涉及的页面路径 → 1 条主路径流程（"打开 /X → 期望 ..."）
- 自动追加冷启动 smoke 作为最后一条流程
- 非 UI task → 自测说明段填「无（[类型] task）」

如本 task 含 UI 占位词，把 task-scoped 占位值表内联进执行区·「实现设计引用」段
（executor 不跨文件回查 PRD 原型节）。

### 步骤 8：写单文件 typed contract（三区）

按 `$REPO_ROOT/templates/task.md.tmpl` 生成 `$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md`。

**模板替换**：`{{TASK_NUMBER}}` / `{{TASK_NAME}}` / `{{TASK_SLUG}}` / `{{REVIEW_TOOLS}}` /
`{{CREATED_DATE}}` / `{{REQ_ID}}` / `{{REQ_SLUG}}`；保留 `<!-- task_format: single-typed-v3 -->`
标记 + 三区 region 标记。

**三区写作约束**：
- **PM 确认区**（任务卡 / 范围 / 验收清单 / PM 反馈承接清单）：守 PM-view 写作纪律 ——
  每个名词带完整指代前缀；不出现像素 / 颜色 / Emoji 视觉；不出现反向约束；不出现工程词。
- **执行区**（实现规格 / 实现设计引用 / 约束与易错 / 自测说明 / 工程层验收 / 启动前必读 /
  状态转换说明）：允许所有工程内容（TS 类型 / 字段名 / 像素 / 颜色 / 反向约束）。
- **审计区**（文档偏差 / 自审记录 / 历史档案）：保留模板骨架，executor 执行期填。
  ⚠️ **「文档偏差」「自审记录」两 section 必须保留** —— `task-transition.py`「执行中→已完成」
  gate 读它们。

**写头部前必查**（错一项步骤 9 字段校验会拦截重写）：
- [ ] 标题 `# Task NNN: ...` 下方只有 `<!-- task_format -->` 标记，**无** frontmatter 段
- [ ] 状态字段在 `## 📌 任务卡` 表格里（`| **状态** | 待执行 |`）
- [ ] 状态值是 4 态之一：待执行 / 执行中 / 已完成 / 已废弃
- [ ] 不用中文引号（`「」`）包字段；依赖列表是结构化 `- task-NNN (说明)`

### 步骤 9：自检 + lint + 字段校验

#### 9.A 机器抓不到的语义判断（必查 —— 只针对 PM 确认区）

- [ ] PM 确认区每个名词带完整指代前缀；抽象动词搭配具体效果
- [ ] task 级范围 / 验收能独立判 scope（不依赖执行区内容）
- [ ] PM 反馈承接清单每条 relevance 判定正确（模块 / 功能确实落在 / 不落在 task 范围）

#### 9.B 执行区完整性（必查）

- [ ] 实现规格覆盖 PRD 切片的所有功能条目；实现设计引用挑全相关 HOW-ID 行
- [ ] 文档偏差 / 自审记录两 section 骨架在（gate 锚点）

#### 9.C scoped PM-view lint（机器兜底）

```bash
PRE_LINT_HASH=$(shasum -a 256 "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md" | cut -c1-12)
python3 "$REPO_ROOT/.claude/scripts/check-doc-pm-view.py" \
  "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md"
```

scoped 模式只校验 PM 确认区（执行区 / 审计区允许工程内容、自动跳过）。处理输出：
- 0 errors + 0 warnings → 进步骤 10
- 有 warnings → 每条**显式判定**（要么修，要么给 PM 一句话理由）；禁止默默 ack
- 有 errors → 回步骤 8 重写违规章节，再重跑；连续 3 次仍有 error 停下询问 PM

#### 9.D 字段校验（防假执行产物）

```bash
python3 "$REPO_ROOT/.claude/scripts/task-transition.py" \
  "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md" --validate-fields-only
```

退出 1 → 按 stderr 回步骤 8 重写 task 文件头部（任务卡表格 `| **状态** | 待执行 |`、
无 frontmatter 段、状态值合法），再回步骤 9 全跑一遍。

### 步骤 10：展示确认门并等待 PM 确认（单一确认门）

> delta-3：task-spec 步骤 10 是 PM 在整个 task 生命周期的**唯一确认门**（task-confirm
> 已删自己的启动确认门）。

**确认门前置依赖检查**：扫本 task `## 依赖` 列的 task 状态。有未完成依赖 → 在确认门
chat 先告知 PM「本 task 依赖 task-MMM 未完成，task-confirm 会拦下」，避免 PM 在「以为
能启动」预期下被 task-confirm 依赖 gate 弹回。

向 PM 一次输出确认门（遵守 `feedback_confirmation_gates.md`：路径 + 一句话摘要；
PM 只读 PM 确认区即可判 scope）：

```
Stage 6（task 执行）— task-NNN <slug> 待确认

✅ task 文件：<绝对路径>

📋 摘要
   <所属模块> / 实现规格 N 节 / PM 反馈承接 承接 X 条·不适用 Z 条 / <依赖状态一句>

📊 可选 review（你自跑，跑完贴结论我帮你 append 事件）
   /plan-eng-review     — 架构 / 数据流 / 边界 / 依赖合理性
   /plan-design-review  — 交互 / 视觉层问题（UI task）
   跑哪几个你定，全跳也行。

你确认的是 task 的 scope / 验收 / 反馈承接（PM 确认区），不是逐条背书实现细节。
这版 task 内容是否可以定稿？如还要调整请直接说；确认后推进到 /task-confirm。
```

基础设施 task 去掉 design review 行。

**PM 回答分流**（按自然语言意图）：
- PM 确认（OK / 通过 / 没问题）→ 进步骤 11
- PM 给修改意见 → 按反馈改对应区，回步骤 9 自检 + lint，再回步骤 10 重新询问
- PM 放弃（不要这个 task）→ 删 task 文件，提示 PM 同步从 `task-plan.md` 删条目

**🔒 binding-contract tamper 检测**（单文件最小 tamper-hash，§2.8 A2）：

PM 确认后退出步骤 10 前算一次 hash 自检：

```bash
POST_LINT_HASH=$(shasum -a 256 "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md" | cut -c1-12)
```

- PM 全部判定保留（0 项修）→ `POST_LINT_HASH` 必须 == 步骤 9.C 的 `PRE_LINT_HASH`。
  不等 = AI 偷改了 PM 决策保留的内容（违例）→ `git checkout` 还原 → 重算 → 仍违例停下告知 PM。
- PM 有部分项选修 → 所有修改严格对应 PM「修」清单，不许"顺手 normalize"任何 PM 没同意改的
  内容（去反引号 / 合并空行 / 统一术语大小写等）。AI"代码合法 / 风格统一"压力不能凌驾 PM 决策。

**🚫 PM chat 输出禁词**：`hash` / 12 位 hash 值 / `lint` / `warnings` / `步骤 N` 等内部
状态词不出现在 PM 看的 chat 文字里。lint 处理完毕直接进确认门，不复述。

PM 未确认前不得进入执行。

### 步骤 11：落盘 + 推 /task-confirm

PM 确认后，把 task 文件 commit 到 req 分支（保证 task-confirm fork 时取到 PM 确认终态，
非 working tree stale 版本；I-DC1）：

```bash
source "$REPO_ROOT/.claude/scripts/_lib/dirty-check.sh"
TASK_FILE="$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md"
auto_commit_docs "$REQ_WORKTREE" "task-NNN-<slug>: spec sealed" "$TASK_FILE"
```

`auto_commit_docs` 在文件与 HEAD 一致时静默 noop；pathspec 严格限定本 task 单文件，
不卷入其他 working tree 改动。commit 失败 → 不推 task-confirm，把错误原文给 PM。

落盘完成后推：

```
✅ task 已定稿，下一步运行 /task-confirm <task 文件路径>
```

## Rules

- 一次只生成一个 task 的**一个文件**（单文件 typed contract）；不支持批量生成。
- 不再产 `.engineering.md`；不写 hash 注释 / reconcile 元数据（单文件无第二份可同步）。
- 不编辑其他 task 文件；不创建 / 修改 `docs/modules/*.md`；不修改 `task-plan.md`。
- 不复制 prd.md / implementation-design.md 大段原文，只引用 + 转写为 task 级可验收内容。
- 只有 PM 在步骤 10 确认后才推 `/task-confirm`。
- 基础设施 task 必须说明：`本 task 不触发 module 规格 merge`。
- AI 不得自动调任何 review skill（I-RV1）；只在确认门给可选 review 清单，PM 自跑。
- **relevance 二分强制**：前序 PM 反馈按 relevance（适用 / 不适用）二分；每条都登记进 PM 反馈承接清单。
- **跳过项目级文档"必读"被禁止**：PROJECT / DESIGN / prd / implementation-design / modules 存在则必读。
- **binding-contract 纪律保留**（§2.8）：删的是双文件 hash 同步机器，不是删「PM 在确认门
  判定保留的内容 AI 不得改」。revise 仍守「只改 PM 要求改的、不顺手 normalize」。
- **单文件模板必须保留「文档偏差」「自审记录」section**：否则 `task-transition.py`
  「执行中→已完成」gate 失锚点、对所有新 task 必败。
- **强制落盘（I-DC1）**：步骤 11 必须 commit task 文件到 req 分支再推 task-confirm。
- **PM chat 输出禁词**：`hash` / `lint` / `warnings` / `步骤 N` / commit hash 等内部记账词
  不出现在 PM 看的 chat。

## 文档结构

三区结构 + 章节顺序的单一真相源 = `$REPO_ROOT/templates/task.md.tmpl`（含每段填写
规则注释）。本 skill 不在内部复制章节定义。章节顺序另见
`_shared/pm-view/section-order.md` §七。
