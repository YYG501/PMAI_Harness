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
- **§五 功能清单格式**（标题 + 角色限定一句话 + 业务规则编号 + 字段口径独立表；业务规则只说 what，禁 how/why/字段口径混入）
- **§六 关键产品决策格式**
- **§七 章节顺序约束**（按 `templates/task.md.tmpl` + `templates/task.engineering.md.tmpl`）
- **§九 输入流约束**（必读上游 stage 文档 + 项目级文档；输入清单见下方 Required Inputs）
- **§9.4 PM 反馈三类分流**（正向规则 → 跨功能产品规则 / 反向约束 → 工程合同 §6 / 决策记录 → 关键产品决策）
- **§9.6 双文件 lazy sync**：首次生成两文件 + hash；PM 在步骤 12 选 B 修改时只动 PM 视图、工程合同保持 stale；PM 选 A 后由步骤 12.5 reconcile 同步

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

打开 `skills/_shared/PM-VIEW-RULES.md`，重点理解 §三 / §五 / §六 / §七 / §九（含 §9.6 双文件 lazy sync）。

### 步骤 0.5：判别调用模式

| 模式 | 触发条件 | 走哪些步骤 |
|---|---|---|
| **first-gen** | `tasks/task-NNN-<slug>.md` 不存在 | 步骤 1–12（完整流程）|
| **revise** | task PM 视图已存在；PM 之前选过 B 现在再次进入 | 步骤 1 / 3 / 5 / 6 / 8 / 10 / 10.5 / 11 / 12（**只**改 PM 视图，**不动**工程合同；hash 自然 stale）|
| **reconcile** | 步骤 12 PM 选 A 后由本 skill 自身在步骤 12.5 自动进入 | 仅步骤 12.5（不改 PM 视图，对齐工程合同）|

实际判别：
- 先扫文件存在性 → 决定 first-gen vs 已存在
- 已存在 + 当前调用是 stage 6 PM 重新进入：MODE=revise（步骤 9 写工程合同被跳过；hash 留 stale）
- 步骤 12 PM 选 A → 进入步骤 12.5（reconcile，仅 inline 执行）

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
- 功能清单遵守 §五格式（N · 功能名 + 「使用角色」一句 + 业务规则编号 + 字段口径独立表；§5.2 / §5.3 写作约束）

**模板替换**：
- `{{TASK_NUMBER}}` → 三位数编号
- `{{TASK_NAME}}` → task 标题
- `{{TASK_SLUG}}` → 英文 kebab-case slug
- `{{REVIEW_TOOLS}}` → 根据 task 类型给默认值
- `{{CREATED_DATE}}` → 当前日期 YYYY-MM-DD
- `{{REQ_ID}}` / `{{REQ_SLUG}}` → 来自当前 req 元数据

### 步骤 9：写 task-NNN-<slug>.engineering.md（工程合同）

> **仅 first-gen 模式执行**。revise 模式跳过本步骤（不动工程合同，hash 自然 stale，等步骤 12.5 reconcile）。

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

**hash 写入**（PM-VIEW-RULES §9.6.2）：

```bash
PM_VIEW_HASH=$(shasum -a 256 "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md" | cut -c1-12)
# 写入工程合同顶部模板占位 {{PM_VIEW_HASH}} → 替换为 $PM_VIEW_HASH
```

写完后核对工程合同顶部 `<!-- synced_pm_view_hash: <12 字符> -->` 注释存在且与 PM 视图实际 hash 一致。

**§3 启动前必读**应包含：
1. `solution.md` §X 的相关章节
2. `solution.engineering.md` §Y 的相关章节
3. `task-plan.md` §三 风险条目 + §四 自检与状态摘要（反模式 / 验收 GAP）
4. 项目级文档（CONTEXT / DESIGN / 当前模块 spec）
5. 同模块已完成 task 的 PM 视图 + 工程合同
6. 涉及的现有 prototype 文件路径

#### §5 实现指引：项目级 + req 级 prose 合并（4.5d.4 修订）

§5 实现指引由两层 prose 段落合并而成（**不是 enum 字段，不机械冲突阻断**）：

**A 层 项目级（CLAUDE.md「## 工程结构约束」段）**

读 `$REPO_ROOT/CLAUDE.md` 的 `## 工程结构约束` section（含 auto-detected 标的内容 = init-project 注入；删 auto-detected 标后视为 PM 手填，框架不再覆盖）。

四档行为：

| 段内容 | A 层取值 |
|---|---|
| `prototype` 档（auto-detected: prototype 标）| prototype 派生模板：代码组织约束 + 实现深度 prose 指引（数据层 / 权限 / API / 测试 / 边界态 / 多端 / 演示路径）|
| `system` 档（auto-detected: system 标）| 同上 system 档 |
| `custom` 档（auto-detected: custom 标 / PM 手填骨架）| PM 自由编辑的 prose 段落（按当前内容采用） |
| `unknown` 档 / 段不存在 / placeholder 未替换 | **fallback**：警告 PM「项目级约束缺失或未定，建议跑 init-project 或 detect-project-structure 先补」，但不阻断；A 层取空，按 B 层单源生成 |

**B 层 req 级覆盖（solution.md「## 🔧 本轮实现深度变更」段）**

读 `$ACTIVE_REQ_DIR/solution.md` 的 `## 🔧 本轮实现深度变更` section：

- 内容是「无变更」/ 留空 / section 不存在 → B 层取空，§5 按 A 层单源生成
- 内容含变更描述（自由文本）→ B 层取该 prose 段，作为对 A 层的覆盖项

**合并语义（无机械冲突阻断）**

task-spec **不再做项目级 vs req 级的冲突检测**——任何组合都按 prose 合并直接拼到工程合同 §5。冲突场景（如项目级 prototype + req 级要做完整系统）由 PM 在多个时机自决：
- task-execute 看代码 / 看原型时：发现实际实现需要调整时，按业务层偏差路径走（task PM 视图「📁 历史档案 → 业务层偏差」 + close-task → /doc-update）
- close-req 步骤 2c：决定 req 级深度变更**是否同步到项目级 CLAUDE.md**（影响后续 req）

task-spec 只如实合并不阻断；冲突的处理在 task-execute / close-req / close-task 等下游环节，不在 task-spec。

**拼接结果写入工程合同 §5**：

```markdown
## 5. 实现指引

### 工程结构约束（项目级，A 层）

[CLAUDE.md「## 工程结构约束」段全文；{prototype-root} 已替换为实际值。
A 层缺失时本节写「项目级未定 — A 层缺失，按 req 级单源生成」]

### 本轮实现深度变更（req 级，B 层）

[solution.md「## 🔧 本轮实现深度变更」section 原文。
B 层为「无变更」时本节写「无变更（沿用 A 层）」]

### 具体实现要求

[基于 A + B 合并的有效深度生成 task 级 actionable 指引：
 - A 层是项目默认风格（prose 段落）
 - B 层 prose 描述本 req 的覆盖项（如有）
 - AI 在 task-execute 写代码时按 B 层覆盖 + A 层兜底执行]
```

如步骤 12 PM 选 B（修订 PM 视图）：本步骤跳过；步骤 12.5 reconcile 时按当前 A + B 重新拼接。

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

### 步骤 10.5：自动跑启发式 lint

人工自检之后，调用 `check-doc-pm-view.py` 做机器校验作为兜底：

```bash
python3 "$REPO_ROOT/.claude/scripts/check-doc-pm-view.py" \
  "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md"
```

处理输出：
- **0 errors + 0 warnings**：进入步骤 11
- **有 warnings**：向 PM 展示，PM 决定是否修
- **有 errors**：逐条修复后回到步骤 8 重写违规章节，再重跑 lint；连续 3 次 lint 仍有 error 时停下询问 PM
- 进入步骤 11 时若仍有未修复 errors，必须**显式告知** PM 哪几条未修 + 一句话原因

工程合同 (`task-NNN-<slug>.engineering.md`) 不跑 lint（脚本自动跳过 `.engineering.md`）。

### 步骤 11：输出"推荐 review 工具"区块（不自动调任何 review）+ 派生 review-input bundle

按 task 类型给出推荐清单。**AI 不得自动调用任何 review skill**（I-RV1）。

#### 11.0 派生 review-input bundle（落档完成后机械执行）

两文件刚写完，PM 视图 / 工程合同状态相对稳定。AI **机械跑**一次 build-review-input.py，把推荐 review 类型的 bundle 都派生到 `.runs/`，PM 跑 review skill 时直接拿路径用，不用现场拼参数。

业务模块 task：

```bash
python3 .claude/scripts/build-review-input.py "<task-pm-view-file>" --review eng     2>/dev/null
python3 .claude/scripts/build-review-input.py "<task-pm-view-file>" --review design  2>/dev/null
```

基础设施 task（去掉 design）：

```bash
python3 .claude/scripts/build-review-input.py "<task-pm-view-file>" --review eng 2>/dev/null
```

每条命令输出 stdout 一行 bundle 绝对路径；AI 收下后塞进步骤 11 推荐区块输出。**bundle 是派生 artifact**，PM 改 PM 视图 / 工程合同后**会 stale**——见步骤 11.1 重生策略。

#### 11.1 推荐区块（业务模块 task）

```
✅ task 文件已生成：
  PM 视图：<task-pm-view-path>
  工程合同：<task-engineering-path>

review-input bundle（派生 artifact，已为你拼好；PM 视图 / 工程合同改动后请重跑 build-review-input.py 派生新 bundle）：
  Eng：    .runs/review-input-<task>-eng.md
  Design： .runs/review-input-<task>-design.md

可选 review（PM 在主窗口对 bundle 跑，跑完贴结论我帮你 append 事件）：
  /plan-eng-review     — 架构、数据流、边界、依赖合理性
  /plan-design-review  — 交互与视觉层问题、UI 完整性
  /autoplan            — 上述两个的批量打包

跑哪几个由你决定，全跳也可以。详细 bundle 约定见 skills/_shared/REVIEW-INPUT-BUNDLE.md。
```

#### 11.2 推荐区块（基础设施 task，去掉 design）

```
✅ task 文件已生成：
  PM 视图：<task-pm-view-path>
  工程合同：<task-engineering-path>

review-input bundle：
  Eng： .runs/review-input-<task>-eng.md

可选 review（PM 在主窗口对 bundle 跑，跑完贴结论我帮你 append 事件）：
  /plan-eng-review     — 脚手架/共用能力的设计合理性

跑哪几个由你决定，全跳也可以。
```

#### 11.3 PM 跑完 review 后的事件 append（机械记录，I-RV2）

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

#### 11.4 PM 跑了 review 后的修改决策（仅当 PM 选择跑了）

PM 跑完 review 决定采纳发现：

- 修改 PM 视图主文件 / 工程合同 → 提示 PM 是否要重新跑对应 review → 跑完再 append 事件（最后一条为准）

PM 看完不改 / 不跑 review：直接进步骤 12。事件流缺事件不阻塞推进（I-RV2，task-confirm 不再 hard gate）。

### 步骤 12：展示生成结果并等待 PM 确认

向 PM 展示摘要和两文件路径，不直接进入执行：

```
已生成 task 详细文档：
  PM 视图：<绝对路径>
  工程合同：<绝对路径>（hash: <前 12 字符>，可能 stale 等待 reconcile）

摘要：
- Task: task-NNN-<slug>
- 所属模块：[模块]
- 所属模块章节：[章节]
- 用户使用流程 / 功能清单：[N 个场景 / N 节] / 基础设施 task 为无
- PM 反馈分流：[正向规则 X 条 / 反向约束 Y 条 / 决策记录 Z 条 / 无]
- review：[PM 已跑 /plan-eng-review pass / 未跑 /plan-design-review / 全跳]

A) 确认，进入步骤 12.5 同步工程合同后推动 /task-confirm <task-pm-view-file>
B) 我要修改 task 文档（PM 视图改 / 工程合同独立来源章节改）
C) 放弃本次生成（两文件一起删）
```

PM 选 A → 进入步骤 12.5 reconcile → 完成后推 /task-confirm。
PM 选 B → 进入"修改回流"分支：
- 改 PM 视图内容 → 重写 PM 视图主文件，**不动工程合同**（hash 留 stale），自检 + lint 后回到步骤 12 重新等 PM 确认
- 改工程合同独立来源章节（§7 plan-review 沉淀 / §11 自审记录）→ 直接改对应章节，**不更新 hash**，回到步骤 12

PM 未确认前不得进入执行。

### 步骤 12.5：reconcile 工程合同（PM 选 A 后内联执行）

**触发**：步骤 12 PM 选 A。本步骤由 task-spec 自身内联执行，**不另调 skill**。

按 PM-VIEW-RULES §9.6.4 执行：

1. **算 hash**：
   ```bash
   PM_VIEW="$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md"
   ENG="$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.engineering.md"
   PM_VIEW_HASH_NOW=$(shasum -a 256 "$PM_VIEW" | cut -c1-12)
   PM_VIEW_HASH_OLD=$(grep -oE 'synced_pm_view_hash: [a-f0-9]{12}' "$ENG" | awk '{print $2}')
   ```
2. **一致** → 输出 `reconcile: no-op（PM 视图未变）`，进入步骤 13
3. **不一致** → 进入派生流程：
   a. 再读必读输入：`analysis.md` / `solution.engineering.md`（按章节匹配）/ 同模块已完成 task 的 `.engineering.md` / `docs/DESIGN.md` / `docs/modules/<module>.md` / `prototypes/`
   b. 比对 PM 视图 diff（`git diff` 或 chat 上下文中 PM 报告的修改范围）
   c. 重派生 PM 视图驱动章节（PM-VIEW-RULES §9.6.3）：§3 启动前必读 / §4 功能清单工程版 / §5 实现指引 / §6 易错点（PM 反馈反向部分）/ §8 视觉规范（PM 视图像素/颜色派生部分）/ §9 工程层验收清单
   d. 不动独立来源章节：§7 plan-review 沉淀 / §10 文档偏差 / §11 自审记录；如发现独立章节里引用的功能名 / 章节号已被 PM 视图修改，**只改引用、不改主体**
   e. 把工程合同顶部 `synced_pm_view_hash` 改为 `$PM_VIEW_HASH_NOW`
   f. 在工程合同末尾追加 `<!-- reconcile <YYYY-MM-DD HH:MM>: <旧 hash> → <新 hash>; 变更范围: <一行说明> -->`；同步在 PM 视图主文件末尾「📁 历史档案」加一行 `<YYYY-MM-DD> reconcile：工程合同已对齐 PM 视图（<旧 hash> → <新 hash>）`
4. 自检（PM-VIEW-RULES §9.6.6）
5. **重新派生 review-input bundle**：reconcile 后 PM 视图 / 工程合同都更新了，旧 bundle 已 stale；重跑步骤 11.0 的 build-review-input.py 把 `.runs/review-input-<task>-{eng,design}.md` 都刷一遍（业务模块 task 跑两个 / 基础设施 task 跑 eng）
6. 输出 reconcile 完成信号：
   ```
   ✅ task-NNN-<slug>.engineering.md reconcile 完成
   - hash: <旧> → <新>
   - 变更章节：[列出更新的 §]
   - 独立来源章节未动：§7 / §10 / §11
   - review-input bundle 已重派生：.runs/review-input-<task>-{eng,design}.md
   ```

### 步骤 13：推动 /task-confirm

reconcile 完成后才推：

```
✅ 双文件已对齐，下一步运行 /task-confirm <task-pm-view-file>
```

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
- **lazy sync 强制**（PM-VIEW-RULES §9.6）：PM 在步骤 12 选 B 修改 PM 视图时，**禁止顺手重写工程合同**（hash 必须留 stale）；只有步骤 12 选 A 后的步骤 12.5 才能重写工程合同 PM 视图驱动章节。
- **reconcile 边界**：步骤 12.5 禁止动 PM 视图主文件内容（仅允许在「📁 历史档案」append 一行 reconcile 记录）；禁止动工程合同独立来源章节（§7 / §10 / §11）的主体。
- **hash 不得手动改**：任何模式下不允许手动编辑工程合同顶部 `synced_pm_view_hash`，只能由步骤 9（首生成）或步骤 12.5（reconcile）写入。
