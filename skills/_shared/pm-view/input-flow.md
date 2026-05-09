# §九 输入流约束（信息来源 / 反向校验 / 反馈分类）

> 本文件是 [`PM-VIEW-RULES.md`](../PM-VIEW-RULES.md) §9.1 - §9.6 的物理拆分。§9.7 跨 skill 共享原则单独抽到 [`cross-skill.md`](./cross-skill.md)。

本文件约束各 skill 写文档前**读哪些上游产物**，以及**怎么读**——避免工程化内容沿 stage 链路渗透到 PM 视图。

## 9.1 各 skill 必读输入清单（全 stage 权威表）

本表是框架内"哪个 skill 该读什么"的**单一权威来源**。各 SKILL.md 的"必读输入"段引用本表（"按 §9.1 中本 skill 对应行/段执行"），不再独立维护。

**核心约束**：
- PM 视图文档之间互相喂入时**只读对方的 PM 视图层**（即主文件），**不读** `*.engineering.md`
- 项目级权威产物按本表等级读，AI 不得以"觉得不必要"为由跳过 🟢 必读项

**等级图例**：
- 🟢 全文必读
- 🟡 章节 grep（按 §9.1.1 / §9.3.1 强约束执行）
- ⚪ 按需 lazy（写不出来回查）
- ❌ 显式不读

### Stage 0：项目初始化
- `init-project`：PM 输入（项目名 / 目录），无大文件
- `new-req`：PM-VIEW-RULES §四 brief 严格度行 🟢

### Stage 2：req-analysis
- 🟢 `brief.md`
- 🟢 `docs/CONTEXT.md`（如存在）
- 🟢 `docs/prd.md`（如存在 → **必读**——分析新需求必须基于已有产品规格基线，避免重复设计 / 与已有功能冲突）

### Stage 3：req-stage-gate
- 仅 `$ACTIVE_REQ_STAGE` 元数据 + advisor 调用，无大文件读

### Stage 4：req-solution

**first-gen / PM 视图**
- 🟢 `PM-VIEW-RULES.md`（步骤 0，仅 1 次/会话）
- 🟢 `brief.md` / `analysis.md`
- 🟢 `docs/CONTEXT.md` / `docs/DESIGN.md` / `docs/prd.md`
- 🟢 `docs/modules/INDEX.md` + 全部 `docs/modules/*.md`
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ❌ 任何 `.engineering.md`

**first-gen / 工程合同**
- 🟢 `analysis.md` / `docs/DESIGN.md` / `docs/modules/<本 req 涉及模块>.md`
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ⚪ 上游 `.engineering.md`

**revise（PM 视图）**
- 🟢 `solution.md` 主文件 + chat 中 PM 修改要求
- ⚪ 其他全部按需

**reconcile**
- 🟢 `solution.md` + `solution.engineering.md` hash + `git diff`
- 🟡 hash 不一致才扩大读：`analysis.md` / `DESIGN.md` / 当前模块 / `prototypes/<相关>`（§9.3.1）

**review 触发**（PM 显式触发任意 review skill 前 / AI 内部 review 前；caller = stage-gate）
- 🟢 `solution.md` PM 视图主文件
- 🟢 `solution.engineering.md` 全文（review 必须双读，不容忍 stale）
- caller 在向 PM 输出"推荐 review"区块**前**先比对 hash → 不一致则先调 reconcile 模式同步两文件 → 再让 review 进入

### Stage 5：task-plan
- 🟢 `PM-VIEW-RULES.md`（步骤 0）
- 🟢 `analysis.md` / `solution.md`（PM 视图）
- ⚪ `brief.md`（按需——已被 analysis / solution 消化两层；偶尔回查初衷）
- 🟢 `docs/CONTEXT.md` / `docs/prd.md`
- ⚪ `docs/DESIGN.md`（按需——视觉决策不影响 task 拆分粒度，仅在拆边界涉及视觉差异时回查）
- 🟢 `docs/modules/INDEX.md` + 全部 `docs/modules/*.md`
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ❌ `solution.engineering.md` / 任何 `.engineering.md`

### Stage 6：task-spec

**first-gen / PM 视图**
- 🟢 `PM-VIEW-RULES.md`（步骤 0，不重读）
- 🟢 `task-plan.md`（取本 task 行 + 自检与状态摘要）
- 🟢 `solution.md` PM 视图（**first-gen 整文件读，§9.1.1 逃生口**）
- 🟢 `docs/CONTEXT.md` / `docs/prd.md` / `docs/modules/<本 task 模块>.md`
- 🟡 `docs/DESIGN.md`（按 task 涉及功能 grep 相关章节，§9.1.1）—— PM 视图禁像素颜色，仅引用产品级视觉决策稀疏
- 🟡 同模块已完成 `task-*.md` 仅 grep `## PM 反馈` 段（§9.1.1）
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ⚪ `brief.md` / `analysis.md`
- ❌ 任何 `.engineering.md`

**first-gen / 工程合同**
- 🟢 `docs/DESIGN.md` / `docs/modules/<本 task 模块>.md`
- 🟡 `analysis.md` 工程层段 / `solution.engineering.md` 章节匹配（§9.1.1）
- 🟡 `prototypes/<相关页面>`(§9.3.1)
- ⚪ 同模块已完成 `task-*.engineering.md`

**revise / PM 视图（痛点场景）**
- 🟢 `task-NNN.md` 主文件 + chat 中 PM 修改要求
- 🟡 `solution.md` 章节 grep（§9.1.1 revise 模式）
- 🟡 同模块 `task-*.md` `## PM 反馈` 段（§9.1.1）
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- 🟢 `docs/CONTEXT.md` / `docs/prd.md` / `docs/modules/<本 task 模块>.md`
- 🟡 `docs/DESIGN.md`（同 first-gen，按 task 涉及功能 grep，§9.1.1）
- ⚪ `brief.md` / `analysis.md`
- ❌ 任何 `.engineering.md`

**reconcile**：见步骤 12.5 reconcile 派生流程

**review 触发**（PM 显式触发任意 review skill 前 / AI 内部 review 前；caller = task-spec 步骤 11.0 / 步骤 12 修改分支回流前）
- 🟢 本 task PM 视图主文件
- 🟢 本 task `task-NNN-*.engineering.md` 全文（review 必须双读，不容忍 stale）
- caller 在向 PM 输出"推荐 review"区块**前**先比对 hash → 不一致则先调步骤 12.5 reconcile 同步两文件 → 再让 review 进入（review skill 按 PM 视图主文件顶部「📂 文档结构」段跟踪文件引用，跨双文件读全）

### Stage 6.5：task-confirm
- 🟢 本 task 两文件（成对校验）
- 🟢 依赖 task 状态

### Stage 6.6：task-execute
- 🟢 本 task 两文件（PM 视图 + 工程合同）
- 🟢 工程合同 §3 启动前必读列表（逐个读）
- 🟢 `docs/DESIGN.md`（**强制 cat 全文**——task-001 反模式 evidence，视觉一致性护身符）
- 🟢 `docs/modules/<本 task 模块>.md`
- 🟢 `prototypes/<相关页面>`（**实现参考，不应用 §9.3.1**，全文 Read——写新页面"长一样"需要全局结构感）

### Stage 6.7：task-submit
- 🟢 本 task 两文件

### Stage 7.1：close-task
- 🟢 本 task 两文件
- 🟢 task worktree 改动代码（≤3 文件全读，多文件分批）
- 🟢 `docs/DESIGN.md`（步骤 1.5 视觉规范类 PM 反馈第四类反推沉淀，参见 §9.4）

### Stage 7.2：doc-update
- 🟢 本 task PM 视图主文件
- 🟢 `docs/modules/<本 task 模块>.md`
- 🟢 工程合同 §10 文档偏差表
- 🟢 task worktree 改动代码（步骤 1.6 模块规格对账，逐行核对实际实现是否匹配——不读代码就不能对账；读法同 Stage 7.1 close-task）
- 🟡 偏差涉及的原文（前后 5 行）

### Stage 7.3：close-req
- 🟡 `solution.md` §📌 方案摘要（步骤 1 close-report 需求概述源；**不读 brief.md**——brief 是 stage 1 初稿，close-req 时已被 7 个 stage 演化推翻）
- 🟢 `tasks/*.md` 遍历摘要
- 🟡 `solution.md` §🔧 实现深度变更段（步骤 2c 项目级同步判定）
- 🟡 `$REPO_ROOT/CLAUDE.md` 「## 工程结构约束」段（步骤 2c 比对项）
- 🟡 `tasks/discarded/*.md` 摘要

### Stage 7.4：prd-writing
- 🟢 `brief.md` / `analysis.md` / `solution.md`
- 🟡 `tasks/task-*.md` 遍历——`grep -nE "^## (📋 功能清单|🎯 关键产品决策|✅ 验收清单)" tasks/*.md` 命中三段后局部读（§9.1.1）。任务卡 / 历史档案 / PM 反馈对 PRD 价值低，不读
- 🟢 `docs/CONTEXT.md` / `docs/DESIGN.md` / `docs/prd.md` / `docs/modules/INDEX.md`
- 🟢 `docs/modules/<本 req 涉及模块>.md`
- 🟡 `prototypes/<相关页面>`(§9.3.1)
- ⚪ 其他 `docs/modules/*.md`
- ❌ 任何 `.engineering.md`

### Stage 7.5：project-prd-update
- 🟢 本 req `prd.md`
- 🟢 `docs/prd.md`

### 轻量 skill（不进 §9.1 主表）

以下 skill 没有 PM 视图链路职责，SKILL.md "必读输入" 段独立维护，不引用本表：

| skill | 必读 |
|---|---|
| `cancel-req` | 仅 req 元数据 |
| `task-status` | 仅 stage / task 状态 + 最后事件 |
| `publish-to-lark` | 仅参数指定的目标文档 |
| `quick-fix` | 🟢 参数指定文档 / ⚪ 关联文档 |

### 9.1.1 "按章节匹配" 操作语义（强约束）

§9.1 表中标 🟡 "章节 grep" 的文件 → **禁止** 整文件 Read。读法：

1. `grep -nE "^### .*(<关键词1>|<关键词2>)" <文件>` 命中相关章节标题
2. 按命中行号 + 下一个同级或更高级 header 之间的区间 offset/limit Read
3. 关键词从当前 task 标题 / 所属模块 / 功能名提取

适用：`solution.engineering.md` / 同模块 `task-*.md`（`## PM 反馈` 段）/ `docs/DESIGN.md`（task-spec PM 视图）/ `tasks/task-*.md`（prd-writing 三章节遍历）。

**solution.md（PM 视图）特殊**——逃生口：
- **first-gen 模式**：整文件读（顶端核心产物，需要全局视野）
- **revise 模式**：按 §🎯 / §📦 / §✅ 章节 grep 局部读

### 9.1.2 grep 不命中的 fallback 读法（防"0 行读"丢失）

按 §9.1.1 grep 章节标题时，若 0 命中（关键词与文件章节命名不匹配），不要直接放弃读。按文件类型走 fallback：

| 文件 | 命中 0 时 fallback |
|---|---|
| `docs/DESIGN.md`（task-spec PM 视图）| 读「页面模板」+「动效规范」+「间距系统」三个通用章节（约 100-150 行），不读颜色 / 字体细节 |
| `solution.engineering.md` | 读 §1 数据结构 + §2 派生状态 + §6 易错点 三个稳态章节（约 200 行），不读全文 |
| `tasks/task-*.md`（prd-writing 三章节遍历）| 0 命中说明该 task 没有 §📋 / §🎯 / §✅——按需追问 PM「该 task 是否真无可写入 PRD 的功能 / 决策 / 验收」|
| 同模块 `task-*.md`（`## PM 反馈` 段）| 0 命中即说明无反馈，跳过即可（不 fallback）|

**为什么不机械追问 PM**：fallback 读的章节是预先盘点过的"业务关键词稀疏但确实需要的通用规则"。每次都追问 PM 增加心智负担；预设 fallback 把判断收敛到设计期。

**理由 1**：PM 视图文档若读了 .engineering.md，工程内容会被沿链路复制下去——当前 task spec 把 solution §五派生状态规则（代码层）等内容搬到自身实现指引就是因为不分层读。

**理由 2**：项目级文档列为"应读"时 AI 容易跳过，导致 skill 闭门造车。本表用 🟢/🟡/⚪/❌ 等级明确化，避免 AI 按"觉得不必要"自由裁量。

## 9.2 工程合同的喂入时机

工程合同层只在以下时机被读：
- `task-execute` 启动 agent 时显式 inject 到 prompt（agent 读完才动手）
- `task-confirm` 校验两文件成对存在
- `task-spec` 生成 task 工程合同时按章节匹配 `solution.engineering.md`
- **review 触发**：任何 review skill 进入前，由 caller skill（stage-gate stage 2→3 / task-spec 步骤 12）先 reconcile（如 hash stale），再让 review 双读 PM 视图 + 工程合同（§9.6.1 / §9.6.5）

PM 视图生成链路（§9.1 表格中标 ❌ 的行）一律不读 .engineering.md；review 是双读模式不在此限。

## 9.3 原型代码作为反向校验源（task-plan / task-spec / prd-writing 必读）

`task-plan` / `task-spec` / `prd-writing` 三个 skill 必须读 `prototypes/` 现有原型代码：

**目的**：用原型实际行为反向校验上游文档描述。

**读法**：
- 按"所属模块 + 文件路径"匹配，不全量读
- 重点关注：现有页面的字段 / 交互方式 / 已落地组件 / UI 文案

**发现不一致时的处理**：
| 情况 | 处理 |
|---|---|
| 原型已删除 / 砍掉某个工程概念，但上游文档（solution / analysis）还在写 | PM 视图以**原型为准**；上游文档的工程化措辞放进**工程合同的反向约束**（如"UI 文案禁用「含子」概念—原型已无对应控件"）|
| 原型与文档命名不一致（字段名 / 按钮名 / 状态名）| PM 视图以**原型为准**；产物末尾备注"原型与文档不一致，已采用原型现状"|
| 原型实现细节（reducer / props / 组件路径）出现在上游 solution 中 | 这些细节**只放工程合同**；PM 视图描述功能行为 |

**避坑**：原型里有但上游文档没写的"工程概念"（如 V4.1 里的 `includeDescendants`、"含子"复选框），属于工程层细节——
- 不要把它们引入 PM 视图当作功能要求
- 如果原型已砍掉、PM 决策不再支持，必须在工程合同的反向约束里显式标注

### 9.3.1 prototype 读取强约束（>500 行禁止整文件 Read）

prototype 文件 > 500 行 → **禁止** 整文件 Read。读法：

1. 先列**上游工程概念清单**（从 brief / analysis / solution / task-plan 中提取字段名 / 控件名 / 状态名 / 操作名）
2. 对每个概念在 prototype 范围内 grep：`grep -nE "<概念>" prototypes/<相关文件>`
3. **grep 命中**：Read offset = 命中行 -10, limit = 30
4. **grep 不命中**：列出已搜关键词清单 + 追问 PM「这个概念是否真不存在于原型里」。**禁止** AI 自行判定为"已砍掉"——可能是 false negative（关键词中英文不一致："额度" vs "quota" vs "allocation"；控件用 className 而非语义命名；概念名拆词等）。判断留给 PM。

例外：< 500 行的小 prototype 文件可全文 Read。

**理由**：原型 page.tsx 经常 2000+ 行，整文件 Read 浪费 90% 上下文。grep 命中段直接局部读；grep 不命中**不能**机械判为"原型已砍掉"——这种判断是 prose-as-judgment，需要 PM 拍板。

**例外 — task-execute**：task-execute 步骤 2.1 的 prototype 读法是「参考已有组件结构与布局模式」（写新页面"长一样"），属于**实现参考**而非反向校验，需要全局结构感 → 保留整文件读，**不应用本节约束**。

## 9.4 PM 反馈的四类分流（task-spec 读前三类 + close-task 读第四类）

PM 反馈在 task PM 视图的 `## PM 反馈` section 内必须分**四类**之一标注。两个 skill 分工读：

- **task-spec** 读"同模块已完成 task 的 PM 反馈"（前三类）→ 写入下一个 task 的相应 section
- **close-task 步骤 1.5** 读"本 task 的 PM 反馈"（第四类）→ 反推到 `docs/DESIGN.md`

| PM 反馈类型 | 识别特征 | 写入位置 | 消费者 |
|---|---|---|---|
| **正向规则**（统一文案 / 统一行为）| "统一用 X" / "全文用 Y" / "应该按 Z 处理" | 下一个 task 的「跨功能产品规则」节 | task-spec |
| **反向约束**（禁止做某事 / 不要再这样写）| "禁用 X" / "不要 Y" / "不允许 Z" | 下一个 task 的工程合同「易错点 / 禁止项」节 | task-spec |
| **决策记录**（PM 反馈推动了某个产品选择改变）| "改为 X" / "二审决定 Y" / "重做为 Z" | 下一个 task 的「关键产品决策」节（备选方案列标注"已被 PM 反馈推翻"）| task-spec |
| **视觉规范**（控件 / 间距 / 图标 / 配色 / 弹窗模式 / 输入控件类视觉决策）| "spinner 改 +/-" / "ⓘ 用 lucide" / "chip 灰胶囊改 box" / "footer baseline 对齐" | `docs/DESIGN.md` 对应章节（PM 在 close-task 步骤 1.5 逐条选 Y-rule / Y-task-note / N）| close-task |

**禁止**：
1. 把 PM 反馈整段搬到「实现指引-易错点」（PM 视图被反向约束污染的旧反模式）
2. **把视觉规范类反馈塞到工程合同 §6 易错点**（task-001 R6 修了 9 项但没沉淀进 DESIGN.md 的真实反模式——下一个 task 起新 dialog 时 LLM 没参考、重新踩同样坑）

**举例**：
- "统一用「可开通」，不混用「还能开通」「可开 N 人」" → 正向规则 → 跨功能产品规则
- "禁用「含子」/ `includeDescendants` 概念，原型已砍掉" → 反向约束 → 工程合同
- "二审改：聚合行展开看证 breakdown，不是平铺" → 决策记录 → 关键产品决策
- "数字 input 禁用 native spinner 用 +/- 按钮" → **视觉规范** → docs/DESIGN.md §九 9.2
- "弹窗影响范围多维度数字用 box grid 不要 chip 灰胶囊" → **视觉规范** → docs/DESIGN.md §九 9.11

## 9.5 信息流图

```
brief.md（PM 视图，不拆）
   │
   ▼
analysis.md（PM 视图，不拆）
   │
   ▼
solution.md（PM 视图）─────┬─lazy sync─► solution.engineering.md
   │                       │              △
   │  + DESIGN / modules / │              │（task-execute / task-confirm 容忍 stale；
   │    prototypes 反向校验│              │  review 触发自动 reconcile；gate 兜底 reconcile）
   ▼                       │              │
task-plan.md(单文件）      │              │
   │  + prototypes 反向校验│              │
   │  + 末尾自检与状态摘要 │              │
   ▼                       │              │
task-NNN.md（PM 视图）──────┘              │
   △                                      │
   │  + 同模块 PM 反馈分三类               │
   │  + prototypes 反向校验                │
   │                                      │
   ▼                                      │
task-NNN.engineering.md ◄──lazy sync──────┘
   △
   │（按章节匹配 solution.engineering.md，
   │  reconcile 由 task-spec 步骤 12.5 触发）

prd.md（PM 视图，不拆，最终交付）
   △
   │  ← 读 brief / analysis / solution（PM 视图）/ tasks（PM 视图）
   │  ← prototypes 反向校验
```

## 9.6 双文件 lazy sync（reconcile 契约）

适用文档：`solution.md` ↔ `solution.engineering.md` / `tasks/task-NNN-*.md` ↔ `tasks/task-NNN-*.engineering.md`。

### 9.6.1 总原则

PM 在 stage 内反复改 PM 视图时，工程合同**不立即同步**。工程合同允许暂时落后于 PM 视图（"已知 stale"），由 gate 通过时的 **reconcile 步骤**统一对齐。

| 时机 | 行为 |
|---|---|
| 首次生成（skill 第一次产 PM 视图）| 同时写 PM 视图 + 工程合同；工程合同顶部写入当时 PM 视图的 hash |
| 中途 PM 改 PM 视图 | 只改 PM 视图主文件；**不动**工程合同；hash 自然变 stale |
| 中途 PM 提交独立工程层信息（review 沉淀 / autoplan 输出 / 视觉规范补充）| 立即写入工程合同对应章节（§7 / §8 / §9 等"独立来源"章节）；**不更新** hash（PM 视图未动）|
| gate 通过的瞬间 | 触发 reconcile：比对 hash → stale 则重派生工程合同里"PM 视图驱动"的章节 → 更新 hash → 才允许 `req-transition.py` / 推 `/task-confirm` |
| **review 触发**（PM 显式触发 `/plan-*-review` / `/qa` / `/review` 等任意 review skill 前；AI 内部 review 前）| caller skill（stage-gate / task-spec）**先比对 hash → stale 则先调 reconcile** 同步两文件 → 才允许向 PM 输出"推荐 review"区块；review 必须双读 PM 视图 + 工程合同；**不容忍 stale** |
| passive read-side（task-execute / task-confirm）| 容忍读到 stale 工程合同；不阻塞、不 warn（这两个走 gate 同步语义，read 时必经过 reconcile）|

### 9.6.2 hash 标记格式

工程合同顶部元信息块下方插入 HTML 注释：

```markdown
<!-- synced_pm_view_hash: <12 字符> -->
```

计算方式（PM 视图主文件全文）：

```bash
shasum -a 256 <pm-view-file> | cut -c1-12
```

首次生成时填入计算结果。reconcile 完成后用最新 PM 视图重算并覆盖旧 hash。**不允许**手动改 hash；不允许 PM 改 PM 视图时顺手刷 hash。

### 9.6.3 章节分类（哪些归 reconcile，哪些不归）

工程合同的章节分两类：

**PM 视图驱动章节**（reconcile 时按需重派生）：
- `solution.engineering.md`：§1 数据结构 / §2 派生状态 / §3 组件路径 / §4 mock / §5 算法 / §6 易错点（PM 视图反向条目派生部分）/ §10 工程层验收清单
- `task.engineering.md`：§3 启动前必读 / §4 功能清单工程版 / §5 实现指引 / §6 易错点（PM 反馈反向部分）/ §8 视觉规范（PM 视图像素/颜色派生部分）/ §9 工程层验收清单

**独立来源章节**（reconcile 不动，由各自来源直接写入）：
- `solution.engineering.md`：§7 plan-review 沉淀 / §8 autoplan 输出 / §9 a11y/视口/视觉（DESIGN.md 派生部分）
- `task.engineering.md`：§7 plan-review 沉淀 / §10 文档偏差（execution agent 写）/ §11 自审记录（PM 跑 review 后 append）

### 9.6.4 reconcile 步骤（标准动作）

skill 在 reconcile 模式下执行：

1. 计算 PM 视图当前 hash：`shasum -a 256 <pm-view-file> | cut -c1-12`
2. 读工程合同顶部 `synced_pm_view_hash`
3. **一致** → no-op，结束
4. **不一致** → 进入更新流程：
   a. 用 PM 视图最新内容 + 上游产物（`analysis.md` / 上游 `.engineering.md` / `docs/modules/*.md` / `prototypes/`）重派生**PM 视图驱动章节**的内容
   b. 不动**独立来源章节**（§7 / §8 等）；如发现独立来源章节的引用与新 PM 视图脱节（章节编号变了 / 功能名变了），同步修引用，但不重派生主体
   c. 把工程合同顶部 `synced_pm_view_hash` 改为最新 hash
   d. PM 视图主文件「📁 历史档案」/ 工程合同末尾追加一行：`<YYYY-MM-DD HH:MM> reconcile：<旧 hash> → <新 hash>`，并简述变更范围
5. 输出"reconcile 完成"信号，把控制权交回调用方（stage-gate / task-spec 步骤 12.5）

### 9.6.5 read-side 行为分类

read-side 分两类，stale 容忍度不同：

**A. passive read-side（task-execute / task-confirm）—— 容忍 stale**

- `task-execute` 启动 agent 时读到的工程合同**可能是 stale 版本**（PM 视图已改但还没到 gate）。这是允许的——因为 PM 视图未到 gate 意味着 task 还没 confirm，agent 还没启动。task-execute 走到时必然已经过 reconcile。
- **禁止**：passive read-side 在读取前自动跑 reconcile（会破坏"gate 才同步"语义）。

**B. review 触发（evaluative read）—— 不容忍 stale，自动 reconcile**

- PM 显式触发 `/plan-eng-review` / `/plan-design-review` / `/qa` / `/review` / `/autoplan` 等任意 review skill 前，**或** AI 在内部对产物做评估性读取前——caller skill（stage-gate / task-spec）必须先比对 hash，**stale 则自动调 reconcile** 同步两文件，才允许 review 进入；review 一律双读 PM 视图 + 工程合同。
- 理由：review 是 evaluative read（生成评审输出 / finding），缺工程合同信息不全；stale 工程合同会让 review 找出"已被 PM 视图删除"的旧概念产生噪声 finding。
- review 完毕后 PM 在 chat 报告 review 发现，AI 按 §9.6.1 表格行为：纯 PM 视图层修订写 PM 视图（hash 重新 stale 等下次 review/gate 触发再 reconcile）、纯工程层沉淀写工程合同 §7。
- **review 触发的 reconcile 是 §9.6.1 "禁止 read-side 自动 reconcile" 的明示例外**——A 类禁止，B 类必须。

### 9.6.6 自检（生成 / reconcile 后）

工程合同写完或 reconcile 完成后自检：
- [ ] 顶部 `<!-- synced_pm_view_hash: ... -->` 注释存在且 12 字符
- [ ] hash 与 PM 视图主文件 `shasum -a 256 | cut -c1-12` 一致
- [ ] PM 视图驱动章节没有出现"已被 PM 视图删除"的旧概念
- [ ] 独立来源章节（§7 / §8）未被 reconcile 误改

---

> 跨 skill 共享原则（§9.7）见 [`cross-skill.md`](./cross-skill.md)。
