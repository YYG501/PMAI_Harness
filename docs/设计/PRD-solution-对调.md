<!-- /autoplan restore point: <LOCAL_GSTACK_HOME>/projects/PM-AI-Workflow/main-autoplan-restore-20260520-151958.md -->
# PRD / solution 分层对调（delta-2 + delta-4）(v1)

> **状态**：v1（2026-05-20）—— §2/§3/§4 据 §X Round 1（18 ACCEPT finding）+ 3 个 User Challenge 决议修订完成；原 vp-1（CONTEXT→PROJECT 改名）拆出独立 commit；待 PM 复核 / 实施（建议实施前重跑 /plan-eng-review）。§X Round 1 = v0 的 review 记录，保留作历史。
> **日期**：2026-05-20
> **作者**：PM + AI
> **来源**：`管线重构-GSD-review.md` §8 实施顺序第 1 步（delta-2 + delta-4，地基，一起做）

---

## §0 原始痛点（PM + AI 共写，后续 review **不可反向修改**）

> ⚠️ 后续 review / autoplan 不能给本节加东西、不能重新定义范围。

### §0.1 现状的结构问题

1. **`req-solution`（stage 3）一个 skill 背两件不同层的事** —— 既做项目级的"顶层方案设计"，又做 req 级的"功能规格"。两种本不同层的职责缠在一个 skill 里。
2. **`prd-writing` 把 PRD 放在 close-req（事后、可选产出）** —— PRD 这个"req 功能规格"角色被搁在最没用的位置：它没有前置、没在驱动 task。

### §0.2 决策依据（PM 决策驱动，非实证踩坑）

本设计来自 `管线重构-GSD-review.md` §4 delta-2 + delta-4，PM 2026-05-20 判定通过。PM 的判断：
- "顶层方案设计"属于**项目级**，不该挤在每个 req 里重做。
- req 级真正该有的是"功能规格 = PRD"，且它该**前置、驱动 task**，不是收尾产物。

### §0.3 要改的 mechanism

把 `req-solution` 拆开、按层归位：
- 顶层方案职责 → **上移到 new-project**，成 `project-solution`
- req 级功能规格 → 由 **PRD 接**（`prd-writing` 前移到 stage 3）

### §0.4 不解决什么（防膨胀）

| 衍生场景 | 为什么不在本文档 |
|---|---|
| task-spec 的重构 | = delta-3，单独设计文档 |
| HOW / 实现设计视图 | = delta-8，单独设计文档 |
| task-plan / task-execute / close-task 下游核心 | 本对调不动它们 |
| brownfield 入口 | = delta-1，已 DEFER |
| project-solution 做工程孪生双文件 | 总览 §6 已定：不做，单文件 |

---

## §1 要定的设计问题（逐题过）

| # | 设计问题 | 状态 |
|---|---|---|
| Q1 | **stage 结构** —— req-solution 原是 stage 3，移走后 PRD 接 stage 3？req-stage-gate 推进逻辑、stage 编号怎么调 | ✓ 已定（见 §2.1）|
| Q2 | **PRD 吸收 task-spec 的哪些 PM 内容** —— task-spec PM 视图 section 哪些上移进 PRD、什么颗粒度。与 delta-3 强耦合 | ✓ 已定（见 §2.2）|
| Q3 | **project-solution 产出 vs CONTEXT.md** —— project-solution 产"项目方案 + roadmap"，框架已有 CONTEXT.md（项目定位/用户/技术栈/路线）。重叠吗？谁写谁 | ✓ 已定（见 §2.3）|
| Q4 | **project-solution 内部两段怎么落** —— 讨论段（复用 analysis 提问法）+ 输出段；office-hours / ceo-plan 可选挂在哪 | ✓ 已定（见 §2.4）|
| Q5 | **prd-writing 改造范围** —— 从 close-req §2a 前移到 stage 3：输入、产出、与 delta-6 反向对齐的衔接 | ✓ 已定（见 §2.5）|
| Q6 | **过渡** —— 现有用 req-solution 的消费仓（ExampleConsumerApp）怎么平滑过渡 | ✓ 已定（见 §2.6）|

---

## §2 方案主体

### §2.1 stage 结构（Q1 已定）

- **stage 数不变，仍 7。** project-solution 去 new-project 段（pre-req，不占 req stage；与现有 `init-project` 的关系见 §2.4）。
- **Stage 3 换芯**：方案设计（req-solution）→ 功能规格（PRD / prd-writing）。
  ```
  1 感受  2 分析  3 功能规格(PRD)  4 设计系统  5 规划  6 执行  7 关闭
  ```
- **req-stage-gate「Stage 2→3」整段重写**：调 `prd-writing`，不调 `req-solution`。
- **连带 ①——Stage 3 瘦身（必须连带下游契约迁移）**：砍掉 solution 双文件机器（`solution.md ↔ solution.engineering.md` reconcile hash 同步 + 工程文档行数 lint）。**但 `solution.md` 是现役下游契约**——`req-transition.py`、`task-plan`、`task-spec`、`close-req`、`status-view.py` 都读它（review F1）。所以「砍 solution」不能独立完成：vp-4 升级为「stage 3 契约迁移」，把全部 live reader 一次性切到 `prd.md`；HOW 的新家由 delta-8 同批落地（见 §3 / §4）。task-spec 的双文件 reconcile 不在此列，归 delta-3。
- **连带 ②——CONTEXT 6 节强制门前移**：从 stage 3→4 前移到 new-project（项目级文档由 project-solution 产出时填）。stage 3→4 不再设此门；已有项目的兜底见 §2.3 legacy readiness gate。
  > 注：`docs/CONTEXT.md → docs/PROJECT.md` 改名（原 vp-1）已据 review UC-1 从本 delta 拆出，作独立 cleanup commit。本文档下文一律用现役文件名 `docs/CONTEXT.md`。

### §2.2 PRD 吸收 task-spec 的 PM 内容（Q2 已定）

**一条线**：「这个 req 要做成什么样」（产品 / 功能 / 验收）→ PRD；「这个 task 怎么执行、到哪了」→ 留 task。

task-spec PM 视图 10 个 section 的去向（**用章节锚点名定位，不用编号——PRD 有 9 章 / 11 章两形，编号不稳定，review F18**）：

| section | 去向 |
|---|---|
| 📋 功能清单 | → PRD §六 功能需求 |
| ✅ 验收清单 | → PRD §七 验收标准 |
| 🧪 自测说明 | → PRD §七 验收标准（并入）|
| 📐 产物预览 | → PRD §六 功能需求 的「原型」列 / 原型节 |
| 🔤 占位字典 | → PRD 附件节 |
| 📦 范围 | 拆：req 级 → PRD §五 非目标 + §六；task 级（这个 task 改哪）→ 留 task |
| 🎯 关键产品决策 | **结果** → PRD §四 需求分析 / §六；**备选 + 理由** → delta-7 req 事件流的 `decision` 事件（见结论 1）|
| 🚦 跨功能产品规则 | **内容** → PRD §四 设计原则块；**收集机制**（per-task 反馈传播）→ delta-3/6/7。⚠️ review F11：`task-spec` 现读同模块已完成 task 的 `## PM 反馈`（同 req 内反馈唯一通道），delta-3 前必须保留这条 same-req feedback lane，不能只靠 close-req 反向对齐（对后续 task 太晚）|
| 📌 任务卡 | 留 task |
| 📁 历史档案 | 留 task |

**两个结论：**
1. **决策备选 + 理由 → delta-7 req 事件流，不新增独立文件**（review UC-3 / F12）。原方案借 GSD 的 DISCUSSION-LOG 独立文件——但 GSD 用独立文件是因为 33-agent 架构「文件边界 = agent 边界」，单线程框架无此约束（同 umbrella §4 delta-8 拒绝 GSD 三文件拆分的理由）。决策的备选 + 理由写成 delta-7 `.runs/events/req-*.jsonl` 的 `decision` 事件；如需人类视图，那是该事件流的渲染，不是第四套独立时间线（PRD 变更日志 / req events / stage_history 已三套）。PRD 只装决策结果。
2. **PRD 章节结构不动** —— task-spec 内容全折进 PRD 现有结构（标准 9 章；identity / 权限类 11 章——§2.2 routing 用章节名锚定即可兼容两形）；旧锁"不改 `req-prd.md.tmpl` 章节结构"无需推翻。delta-2 只改 PRD 的 header / 生命周期声明（见 §2.5 / Q5）。

注：跨功能产品规则是 PM-AI-Workflow 特有的（GSD 无对应物 —— GSD 的 CONTEXT 决策是 upfront 锁定，非 per-task 反馈累积）。

### §2.3 project-solution 产出 vs 项目级文档（Q3 已定 + review 修正）

- **项目级文档暂用现役 `docs/CONTEXT.md`**（review UC-1）。原 vp-1「`CONTEXT.md → PROJECT.md` 全量改名」已从本 delta 拆出作独立 cleanup commit——理由：§0 痛点是结构职责错配，不是文件名错；改名 footprint 实测 172 处 / 30+ 文件（含 `_lib/state.py`、`_lib/term-detector.py`、`migrate-context-v4.py`、测试 fixture），且框架同步 SOP 只同步 scripts/skills/templates/agents、不动业务实例文档（review F7），改名走不了普通 sync、需单独设计消费仓 migration。本 delta 不背这个成本。下文一律用 `docs/CONTEXT.md`。
- **project-solution 写 `docs/CONTEXT.md`** —— 它就是项目顶层方案，**不另立"项目方案"文档**。现有 6 节（项目名 / 产品定位 / 用户画像 / 产品路线 / 技术栈 / 业务术语表）够用。
- **roadmap = 独立轻量文件**（计划态 req 序列）—— 不塞进 CONTEXT.md。理由：roadmap 操作性（随 req 推进更新、newreq 读它挑下一个），CONTEXT.md 稳定基线，生命周期不同。
  - **review F14**：CONTEXT.md 现有「产品路线」节与 roadmap 职责重叠。定法：CONTEXT.md「产品路线」节保留为**里程碑 / 大方向**（稳定基线），roadmap 装**计划态 req 队列**（操作态）；project-solution 产出时同时填两者并说明分工。这是内容职责切分，vp-2 显式包含——不是「机械改名」能带过的。
- **project-solution 产出 = `docs/CONTEXT.md` + `roadmap`（2 个文件）。**
- **不设独立 research 阶段** —— GSD 的 research 大半是重新组织 PM 已说的内容；技术栈选型在 project-solution 讨论里定、记进 CONTEXT.md 技术栈节。
- **落实 §2.1 连带点 ②**：CONTEXT.md 由 project-solution 在 new-project 产出 + 自带确认门 → stage 3→4 的 6 节 catch-all 强制门**撤掉**。
- **legacy readiness gate（review F10，新增）**：已有项目不补跑 project-solution（§2.6），其 `CONTEXT.md` 也不再被 stage 3→4 门每 req 复查——一旦旧 CONTEXT.md 有空节 / 过时，将再无硬门。兜底：框架同步后，已有项目首次跑 new-req（或 stage-gate）时检查 `CONTEXT.md` 6 节，缺节则触发一次 mini-fill（复用 project-solution 的 6 节填充段 + 精简模式）。新项目走 project-solution 确认门、已有项目走 legacy readiness gate，两路都不漏。
- 层级对照：`docs/CONTEXT.md`（项目级）对应 GSD 的 PROJECT.md 之位；req 级 PRD 对应 GSD per-phase CONTEXT.md 之位。（命名层面的对齐 = 拆出的独立 cleanup commit 的事，不在本 delta。）

### §2.4 project-solution 内部结构（Q4 已定 + review 修正）

**与 `init-project` 的关系（review F2）**：仓里没有 `new-project` skill，只有 `init-project`（一次性脚手架：建骨架 / 脚本 / git）。project-solution 是**独立新 skill**，PM 在 `/init-project` 之后调 `/project-solution`；`init-project` 保持纯脚手架性质不变，只把 SKILL.md 收尾的 handoff 从「运行 /new-req」改成「运行 /project-solution」。vp-2 显式包含这条 handoff 改动。

project-solution = **一个 skill**（项目级一次性，不用 req 的 stage-gate 机器）。内部：

```
段 1 · 讨论方向
   复用 analysis 的提问法（分批提问 / 追问 / 收敛）
   可选：PM 自跑 office-hours / plan-ceo-review，结论带回讨论
   收敛前 —— 未决问题闸门
段 2 · 输出
   产 docs/CONTEXT.md（6 节）+ roadmap
确认门
   PM 定稿；兼 CONTEXT.md 6 节齐不齐检查（替代旧 stage 3→4 门）；
   继承旧 CONTEXT 门的「精简 / 详细」模式选择 + 「PM 不知道写啥时 AI 给精简默认值」逃生阀
```

- 「复用 analysis 提问法」= 复用提问方法 / 纪律，不是字面调用 req-analysis（scope 不同）。
- **未决问题闸门 scan target（review F5）**：`check-open-questions.py` 缺 `## 未决问题` section 时静默退出 0——直接对 CONTEXT.md 跑 = 闸门形同虚设。定法：project-solution 段 1 把未决问题写进一份讨论暂存文件（含 `## 未决问题` section，如 `docs/.project-solution-open-questions.md`），闸门对它跑；并给 `check-open-questions.py` 加 `--require-section` 模式——该模式下缺 section 必须 fail（不静默放行）。vp-2 / vp-7 显式包含脚本改动 + 测试。
- office-hours / plan-ceo-review 保持 gstack 官方默认，PM 自跑。
- **不设 analysis-reviewer 式第二视角评审** —— 项目方向的第二视角由 PM 可选自跑的 plan-ceo-review 担任。
- **fast-path（review F15）**：精简模式让 PM 一句话 / 一角色 / 一条术语起手即可过门，trivial 项目不被前置仪式拖住（与上方确认门的逃生阀同源）。

### §2.5 prd-writing 改造范围（Q5 已定 + review 重估）

| 维度 | 现状 → 改成 |
|---|---|
| 位置 | stage 6 / close → **stage 3** |
| 角色 | 事后评审材料 → **前置、驱动 task 的规格** |
| 输入 | `brief.md` + `analysis.md` + `docs/CONTEXT.md`（+ 已有 `docs/modules/` 如存在）|
| 产出 | PRD（章节结构不动，§2.2 内容折进）|
| header / 全文 | 改：stage 3 定稿冻结 / close-req 收尾反向对齐 / 驱动规格；**清掉 SKILL.md 全文的「阶段 6」「交回 close-req」框架文案**（review F16）|

**⚠️ review F3：vp-3 不是「改 header / 改输入」，是 prd-writing 核心 workflow 重写。** 现有 prd-writing 架构性地围绕「原型 / task 完成后写 PRD + 反向校验原型」：步骤 2「原型为权威依据」、步骤 2.5「§六 拆分预处理把原型 page>Tab 结构重组为动作组」、「原型」列、「以原型为准」规则——stage 3 时**没有原型、没有 task**，这些全部失去输入。改造必须：
- **步骤 0**：close-req 时代的「req 级 / 独立 / 补差」三选一对话——stage-3 模式由 stage-gate 固定为「req 级」，跳过步骤 0 对话。
- **步骤 2 / 2.5**：原型反向校验、§六 拆分预处理改为**从 analysis.md 的功能分解派生** §六 层级（动词锚定规则保留，但重组对象从「原型 UI 结构」换成「analysis 功能清单」）；「原型」列在 stage 3 留空，由 delta-6 close-req 反向对齐时回填。
- **新增 term-detector 步（review F4）**：现役 per-req 业务词催补在 `req-solution` 步骤 3.5（req-solution 退场后丢失）。prd-writing 写完 PRD 后跑 `term-detector.py` 扫 PRD 名词解释节、patch `docs/CONTEXT.md` 业务术语表。vp-4 同时清掉 req-stage-gate stage 3→4 里依赖 `solution.md`「📖 新业务词」marker 的 grep（marker 源消失）。
- **确认门归属（review F6）**：现 prd-writing 自带步骤 0 / 步骤 2.5 / 步骤 4 三个 PM 确认；req-stage-gate Stage 2→3 还有自己的确认门 → stage 3 会变 4 个 PM 门（现状只有 1 个），与 delta-3 §4.1③ 正在修的「确认门重叠」反模式同形。定法：prd-writing 加 **stage-3 orchestrated 模式**——跳步骤 0、删步骤 4 最终确认，步骤 2.5 §六 拆分只在 AI 判断有歧义时才询问；stage 3 只保留 **req-stage-gate 一个 PM 定稿确认门**。

- **"PRD 吸收 task-spec 内容"= 接管归属，非拷贝**：task-spec 晚于 PRD，拷不了；PRD 由 prd-writing 在 stage 3 从 analysis 现写，task-spec（delta-3 后）改成读 PRD。
- **与 delta-6 衔接**：PRD stage 3 定稿冻结 → 执行期 task 按它做 → close-req 时 delta-6 反向对齐。prd-writing 本身不做反向对齐。⚠️ review F19（转 delta-6）：delta-6 的反向对齐**不可把元数据写回冻结的 PRD 基准**——hash 自指风险，参 memory `reconcile-no-self-reference`。

### §2.6 现有消费仓过渡（Q6 已定 + review 修正）

- **原则**：新 req 用新结构，在飞的旧 req 跑完旧的。建议消费仓在「无 stage ≤3 在飞 req」时机同步。
- **⚠️ review UC-2 / F1：「下游 stage 4-7 不变」是错误前提，已废。** 砍 `solution.md` 会打断 `req-transition.py`（`STAGE_OUTPUT_FILES[3]` / `STAGE_NAMES[3]`）、`task-plan`、`task-spec`、`close-req`、`status-view.py`——它们都把 `solution.md` 当现役契约输入。本 delta 因此包含 **stage 3 契约迁移**（见 §3 vp-4）：把全部 live reader 一次性切到 `prd.md`，stage 3 名「方案设计」→「功能规格」。
- **⚠️ review UC-2 / F8：delta-8（req 级 HOW / 实现设计视图安家）与本 delta 同批落地。** 砍 `solution.engineering.md` 后，req 级 HOW（数据模型 / 模块边界 / 实现约束）无归宿——delta-8 是它的新家。**delta-2+4+8 是最小可落地包**，不可只落 delta-2+4。
- **在飞旧 req 兼容**：`req-transition.py` 对旧 req（`.req-meta.json` 标旧流程、已有 `solution.md`）允许跑完旧路径；新 req 走 `prd.md`。
- **project-solution 只对新项目跑**：已存在的项目（如 ExampleConsumerApp）不补跑——其项目级语境兜底走 §2.3 legacy readiness gate。
- **req-solution → project-solution** 随框架同步；在飞旧 req 的 `solution.md` 留作历史产物。
- `docs/CONTEXT.md → docs/PROJECT.md` 改名**不在本 delta**（UC-1 拆出），消费仓不需为本 delta 做改名迁移。

---

## §3 实施清单

> review 后调整（§X Round 1）：原 vp-1（CONTEXT→PROJECT 改名）拆出作独立 cleanup commit（UC-1）；vp-2/3/4/7 重估范围；vp-6 加 legacy readiness gate。vp 编号保留不变（与 §X 决议引用对齐）。delta-8 单独设计文档，与本 delta 同批落地（UC-2）。

| vp | 改什么 | 依据 |
|---|---|---|
| ~~vp-1~~ | **拆出本 delta**（UC-1）—— `docs/CONTEXT.md → docs/PROJECT.md` 全量改名作独立 cleanup commit，在 delta-2+4 验证通过后单独做。本 delta 用现役 `CONTEXT.md`。 | §2.3 |
| vp-2 | **`req-solution` → `project-solution`** —— 独立新 skill（在 `/init-project` 后调；`init-project` SKILL.md handoff 改指 `/project-solution`）：内部两段、产 `docs/CONTEXT.md` + roadmap、砍工程孪生、确认门兼 6 节检查 + 精简/详细模式 + 默认值逃生阀；未决问题闸门写暂存文件 + `check-open-questions.py` 加 `--require-section` | §2.3 §2.4（F2/F5/F15）|
| vp-3 | **`prd-writing` 前移 stage 3（核心 workflow 重写，非 header 改）** —— 改输入（brief+analysis+CONTEXT）；步骤 0/2/2.5 重写（无原型，§六 从 analysis 派生）；加 stage-3 orchestrated 模式（单一确认门）；加 term-detector 步；清全文「阶段 6」框架文案 | §2.5（F3/F4/F6/F16）|
| vp-4 | **req-stage-gate Stage 2→3 重写 + stage 3 契约迁移** —— 调 prd-writing；砍 solution 双文件 reconcile + 行数 lint + stage 3→4 的 6 节门 + 📖 marker grep；`req-transition.py`（`STAGE_OUTPUT_FILES[3]=prd.md`、`STAGE_NAMES[3]=功能规格`、可执行错误信息）/ `task-plan` / `task-spec` / `close-req` / `status-view.py` / `CLAUDE.md.tmpl` 全切 `prd.md`；抽单一 stage-metadata 表；剥离 `check-engineering-doc-size.py` solution 分支；旧 req 兼容判断 | §2.1 §2.6（F1/F13/F17）|
| vp-5 | **新产物模板** —— `roadmap` 模板（DISCUSSION-LOG 不做，UC-3 改 delta-7 事件）；`req-prd.md.tmpl` header 生命周期声明改写（章节结构不动）| §2.2 §2.3 §2.5 |
| vp-6 | **`req-prd.md.tmpl` header 改写 + legacy readiness gate** —— PRD header 生命周期声明；已有项目首次 new-req / stage-gate 时检查 CONTEXT.md 6 节、缺节触发 mini-fill | §2.2 §2.5 §2.3（F10）|
| vp-7 | **测试 + SOP** —— per-vp test matrix（见下）；`框架同步-SOP.md` 补 delta-2+4+8 迁移段；PM operator docs sweep（≤10 行新 happy path）| §2.6（F9/F16）|

**vp-7 test matrix**（review F9——原「测试」一行不足以守住本次重构）：

| 测什么 | 动作 |
|---|---|
| `req-transition.py` stage 3 | `STAGE_OUTPUT_FILES[3]=prd.md`；更新 `test-req-transition.sh` stage-3 fixture |
| dead suites | 从 `run-all.sh` 移除 `test-reconcile-pm-view-immutability.sh`、`test-engineering-doc-size.sh`（solution 部分）|
| new suites | project-solution 结构测试；prd-writing@stage3 fixture（brief+analysis+CONTEXT → prd.md，无原型）；legacy readiness gate |
| fixtures | `req-stage-gate` Stage 2→3 单一确认门断言；`check-open-questions --require-section` |
| baseline | 明确新基线数（现 269）|

**实施顺序**：vp-2 / vp-3 / vp-4（核心三件，互相咬合，一起做，且与 delta-8 同批）→ vp-5 / vp-6（模板 + legacy gate）→ vp-7（测试 + SOP）。vp-1（改名）拆出，独立排在 delta-2+4 验证通过之后。

---

## §4 风险与待验

- **契约迁移漏 reader** —— `solution.md` / `solution.engineering.md` 引用面广。缓解：vp-4 改完全仓 grep `solution.md` / `solution.engineering.md` 验证无现役残留（在飞旧 req 的历史产物除外）。
- **delta-8 未就绪** —— delta-2+4 依赖 delta-8（HOW 安家）同批落地；delta-8 单独设计文档若未先成形，本 delta 不能落。缓解：delta-8 设计文档先于实施定稿。
- **在飞 req 撞同步** —— 同步时若有 req 在 stage 2-3，该 req 走 `req-transition.py` 兼容判断跑完旧路径；可接受，PM 需知情。
- **prd-writing 重写规模** —— vp-3 是核心 workflow 重写（review F3），非小改；动手前先核 prd-writing 实际行数与步骤 2/2.5 的原型依赖范围。
- **待验** —— PRD 现有章节（9 / 11 章）是否真够装 task-spec 全部 PM 内容；消费仓真实跑一个 req 后复核。

---

## §X Review Findings（autoplan / dual voice 输出落这里）

### Round 1 — 2026-05-20 — /gstack-autoplan（6 voices：CEO Codex+Claude · Eng Codex+Claude · DX Codex+Claude）

> **review 范围**：主审本文档（delta-2+4 详细设计）。`管线重构-GSD-review.md` 的 7-delta 判断 + 本文档 §0 痛点锁视为 binding，未重新质疑。
> **设计评分**：CEO 4/10 · Eng 5/10 · DX 5/10。**结论**：§0 问题框架成立；§2/§3 非 implementation-ready —— 照 vp-1..vp-7 字面实施会让 `req-transition.py --to 4` 必败。需据本表修订成 v1。

| # | Severity | Finding 摘要 | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| F1 | Critical | 下游契约断裂：砍 solution.md/.engineering.md，但 req-transition.py / task-plan / task-spec / close-req / status-view.py 仍读它；§2.6「下游 stage 4-7 不变」不成立 | §0.3 | `req-transition.py:31-36,238-242`、`task-plan/SKILL.md:162`、`task-spec/SKILL.md:162-180`、`close-req/SKILL.md:66,192` | **ACCEPT** — UC-2：vp-4 升级为「stage 3 契约迁移」，一次性迁移全部 live reader 到 prd.md |
| F2 | Critical | project-solution 的 host 不存在：设计反复说「new-project」，仓里只有 init-project；vp-2 未定二者关系（新 skill / 折叠进 init-project）| §0.3 | `skills/init-project/SKILL.md`（无 new-project / project-solution）、§3 vp-2 | **ACCEPT** — vp-2 必须明确 project-solution 与 init-project 的关系与 handoff |
| F3 | Critical | prd-writing 改造被低估：现 prd-writing 架构性依赖「原型/task 完成后写 PRD + 反向校验原型」；stage 3 无原型，步骤 2/2.5 失去输入。vp-3「改 header/输入」低估 3-5 倍 | §0.1.2 | `prd-writing/SKILL.md:4,17,86,88,308`、`req-prd.md.tmpl:3` | **ACCEPT** — vp-3 重估为 prd-writing 核心 workflow 重写（步骤 0/2/2.5/3.5 全改）|
| F4 | High | per-req 业务词催补（term-detector）静默丢失：req-solution 步骤 3.5 每 req 跑 detector patch CONTEXT.md；split 后无新家 | §0.1.1 | `req-solution/SKILL.md:164-173`、`_lib/term-detector.py:170` | **ACCEPT** — vp-3 给 prd-writing 加 term-detector step；vp-4 清 req-stage-gate stage 3→4 的 📖 marker grep |
| F5 | High | project-solution 未决问题闸门无 scan target：§2.4 说复用 check-open-questions.py，但 PROJECT.md/roadmap 无 `## 未决问题` section，脚本缺 section 时静默退出 0 | §0.3 | `check-open-questions.py:17-20,99-101`、`test-check-open-questions.sh:99-110` | **ACCEPT** — §2.4 定唯一 scan 文件 + 脚本加 --require-section 模式 |
| F6 | High | 确认门叠加：prd-writing 自带步骤 0/2.5/4 三个确认 + req-stage-gate Stage 2→3 确认门 → stage 3 从 1 个 PM 门变 4 个；与 delta-3 §4.1③ 正在修的反模式同形 | §0.1.2 | `prd-writing/SKILL.md:22-54,88,147`、`req-stage-gate/SKILL.md:164-190` | **ACCEPT** — vp-3 加 prd-writing「stage-3 orchestrated」模式：跳步骤 0、删步骤 4 确认，stage-gate 单一确认门 |
| F7 | High | vp-1 改名 footprint 被低估（实测 172 处 / 30+ 文件，含 _lib/state.py、migrate-context-v4.py）；框架同步 SOP 只同步 scripts/skills/templates/agents，不动业务实例文档 → 改名走不了普通 sync | §0.3 | grep `CONTEXT.md`、`框架同步-SOP.md:30-39,386-393`、`check-context-sections.py:110` | **ACCEPT** — UC-1：vp-1 从 delta-2+4 拆出作独立 cleanup commit；拆出后单独设计 footprint 枚举 + 消费仓 migration |
| F8 | High | delta-2+4 单独落地 ship 一个无人消费的 PRD（task-spec delta-3 才读）；HOW 的新家 delta-8 未落地，solution 的数据模型/模块边界/UI 骨架/实现约束无归宿 | §0.1.2 | `管线重构:119,213-215`、`req-solution/SKILL.md:129,196` | **ACCEPT** — UC-2：delta-8（HOW 安家）与 delta-2+4 同批落地；delta-2+4+8 为最小可落地包 |
| F9 | High | vp-7 测试预算仅一行：test-reconcile-pm-view-immutability / test-engineering-doc-size 成 dead suite，需新增 ~3 suite，269 基线 delta 未评估 | §0.3 | §3 vp-7、`tests/run-all.sh`、`tests/test-engineering-doc-size.sh` | **ACCEPT** — vp-7 列 per-vp test matrix + 明确新基线数 |
| F10 | High | 已有项目永久绕过项目级完整性门：stage 3→4 的 6 节门撤掉 + 已有项目不补跑 project-solution → 旧 PROJECT.md 空/弱时再无硬门 | §0.1.1 | §2.3、§2.6、`req-stage-gate/SKILL.md:277-321` | **ACCEPT** — 加 legacy readiness gate：同步后 PROJECT.md 缺节则首次 new req 触发 mini-fill |
| F11 | Medium | 同 req 内 task 间反馈传播会丢：task-spec 读同模块已完成 task 的 `## PM 反馈`；close-req 反向对齐对 task-2 学 task-1 太晚；§4.1⑤「自动消」不成立 | §0.1.1 | `task-spec/SKILL.md:112,128`、`管线重构:138` | **ACCEPT** — delta-3 前保留 same-req feedback lane，或前置 delta-7 req 事件流供 task-spec 读 |
| F12 | Medium | DISCUSSION-LOG 是 cargo-cult + 第 4 套决策时间线：GSD 有它因 33-agent 架构「文件=agent 边界」，单线程框架无此约束；write-only、owner 含糊 | §0.4 | §2.2/§2.4/§2.5、`管线重构:114,126` | **ACCEPT** — UC-3：不新增独立文件，决策备选改写成 delta-7 req 事件流的 decision 事件；vp-5 砍 DISCUSSION-LOG 模板 |
| F13 | Medium | stage 名/产物硬编码散落 req-transition.py / status-view.py / CLAUDE.md.tmpl；vp-4「改 prose」覆盖不全 | §0.3 | `req-transition.py:19-34`、`status-view.py:31-39`、`CLAUDE.md.tmpl:124-127` | **ACCEPT** — 抽单一 stage-metadata 表（name/output_file/review_target），脚本模板统一引用 |
| F14 | Medium | roadmap 与 PROJECT.md「产品路线」节重叠未定：CONTEXT.md.tmpl 已有产品路线节；roadmap 出现后该节去留未说，vp-1「机械改名」会偷偷变成内容改动 | §0.3 | `templates/CONTEXT.md.tmpl`（产品路线节）、§2.3 | **ACCEPT** — §2.3 明确 roadmap 出现后 PROJECT.md 产品路线节的去留 |
| F15 | Medium | 无 fast-path：project-solution 加前置仪式（讨论+未决问题闸门+确认门）；旧 CONTEXT 门的精简/详细模式 + 「AI 给默认值」逃生阀未承接 | §0.3 | `req-stage-gate/SKILL.md:304-321`、§2.4 | **ACCEPT** — project-solution 确认门继承精简/详细模式 + AI 默认值 affordance |
| F16 | Medium | 无 PM operator 迁移说明：返工 PM 一次撞 4 个概念变更无 breadcrumb；prd-writing/SKILL.md 全文仍是「阶段 6」框架 | §0.1.2 | `prd-writing/SKILL.md:409-432`、§2.6 | **ACCEPT** — vp-7 加 PM operator docs sweep（≤10 行新 happy path）；prd-writing 清「阶段 6」文案 |
| F17 | Medium | check-engineering-doc-size.py 的 solution 分支在 vp-4 后成孤儿死代码 | §2.1①| `check-engineering-doc-size.py:38,96,128` | **ACCEPT** — vp-4 顺手剥离脚本的 solution.engineering.md 处理（task 逻辑留 delta-3）|
| F18 | Low | PRD 9/11 章双形：identity/权限类 PRD 是 11 章，§2.2 routing 引用的章节号（§九 等）不稳定 | §2.2 | `prd-writing/SKILL.md:259-289` | **ACCEPT** — §2.2 routing 用稳定章节锚点（名称）不用编号 |
| F19 | Low | 跨 delta 提示：PRD「stage 3 定稿冻结 → close-req 反向对齐」契约，delta-6 实现时反向对齐不可写回冻结的 PRD 基准（hash 自指风险）| §2.5 | §2.5、memory `feedback_reconcile_no_self_reference` | **DEFER** — 非 delta-2+4 范围，转 delta-6 设计文档作约束提示 |

**汇总**：ACCEPT 18 条（F1-F18）/ DEFER 1 条（F19，转 delta-6）/ 待 PM 决策 0 条（3 个 User Challenge 已 PM 决议，见 §Y）。

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-20 | 文档创建；§0 待 PM 共写锁定；§1 设计问题待逐题过 | — |
| 2026-05-20 | §0 经 PM 确认锁定 | §0 不可再反向修改；进 §1 Q1 |
| 2026-05-20 | Q1（stage 结构）已定：7 stage 不变、stage 3 换芯成 PRD、stage 3 瘦身、CONTEXT 门前移 | 见 §2.1 |
| 2026-05-20 | Q2（PRD 吸收内容）已定：结果→PRD、备选→新增 req DISCUSSION-LOG、PRD 章节结构不动 | 见 §2.2 |
| 2026-05-20 | Q3（project-solution 产出）已定：写 PROJECT.md + 独立 roadmap、6 节够用、不设 research 阶段、强制门前移 | 见 §2.3 |
| 2026-05-20 | `docs/CONTEXT.md` 改名 `docs/PROJECT.md` —— 修掉与 GSD 命名交叉 | 见 §2.3；属 delta-2/4 实施范围 |
| 2026-05-20 | Q4（project-solution 内部）已定：一个 skill，讨论段→输出段→确认门 | 见 §2.4 |
| 2026-05-20 | Q5（prd-writing 改造）已定：前移 stage 3、改 header、输入 brief+analysis+PROJECT、产 PRD + DISCUSSION-LOG | 见 §2.5 |
| 2026-05-20 | Q6（消费仓过渡）已定；§1 六题全收口，§3 实施清单成形（7 vp）| delta-2/4 设计完成 |
| 2026-05-20 | /gstack-autoplan 6-voice review 完成（§X Round 1）—— 19 finding：3 critical / 7 high / 7 medium / 2 low；评分 CEO 4 · Eng 5 · DX 5 | §2/§3 非 implementation-ready，待修订 v1 |
| 2026-05-20 | UC-1 PM 决议：vp-1（CONTEXT→PROJECT 改名）从 delta-2+4 拆出，作独立 cleanup commit | delta-2+4 用现有 CONTEXT.md；§3 vp 清单移除 vp-1 |
| 2026-05-20 | UC-2 PM 决议：扩大 delta-2+4 scope —— vp-4 升级为 stage 3 契约迁移，delta-8（HOW 安家）同批落地 | delta-2+4+8 为最小可落地包 |
| 2026-05-20 | UC-3 PM 决议：DISCUSSION-LOG 不新增独立文件，改成 delta-7 req 事件流的人类视图 | §2.2 / vp-5 调整 |
| 2026-05-20 | §X F1-F18 ACCEPT、F19 DEFER（转 delta-6）；下一步 PM 据 §X 修订 §2/§3 成 v1 | 见 §X Round 1 |
| 2026-05-20 | v1 修订完成：§2.1-§2.6 / §3 / §4 据 §X Round 1（18 ACCEPT）+ 3 UC 决议改写；vp-1 拆出、vp-4 升级契约迁移、DISCUSSION-LOG 改 delta-7 事件、prd-writing 重估为 workflow 重写 | 文档 v0 → v1 |

---

**End of PRD / solution 分层对调 v1**

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` (via /autoplan) | Scope & strategy | 1 | issues_open | 4/10 — 前提确认，§2 设计 3/3 维度 flagged，4 critical gap |
| Eng Review | `/plan-eng-review` (via /autoplan) | Architecture & tests | 1 | issues_open | 5/10 — 下游契约断裂；19 finding（3 critical）|
| DX Review | `/plan-devex-review` (via /autoplan) | Operator experience | 1 | issues_open | 5/10 — stage-3 operator UX 回退（1→4 确认门）|
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | skipped — 无 UI scope（建 skill/模板/脚本，不建界面）|

- **CROSS-MODEL:** 6 voices（Codex ×3 + Claude subagent ×3）。收敛度异常高 —— 两个模型独立、无共享上下文，落到同样的 3 个 critical（new-project 不存在 / 下游契约断裂 / prd-writing 低估），均带 file:line 证据。
- **UNRESOLVED:** 0 —— 3 个 User Challenge 已 PM 决议；18 finding ACCEPT，1 DEFER。
- **VERDICT:** v0 **非 implementation-ready**。§0 前提确认成立；§2/§3 需据 §X Round 1（18 ACCEPT finding + 3 UC 决议）修订成 v1。修订后重跑 /autoplan 或 /plan-eng-review 再实施。
