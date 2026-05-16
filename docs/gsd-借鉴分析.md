<!-- /autoplan restore point: <LOCAL_GSTACK_HOME>/projects/PM-AI-Workflow/main-autoplan-restore-20260516-214321.md -->
# GSD-Ref 借鉴分析与落地方案

> **来源**：`<LOCAL_HOME>/Desktop/Projects/gsd-ref/` —— 工程团队 AI 编码工作流框架（npm 包 `get-shit-done-cc`，被 Amazon / Google / Shopify / Webflow 工程师在用）
> **目的**：抽取 GSD 设计精髓，结合 PM-AI-Workflow 的 PM 单人定位做"该不该抄、怎么抄"的判断
> **版本**：v3（2026-05-16，基于 autoplan Phase 1+3+3.5 评审反馈精简修订）
> **作者**：PM + AI
> **v3 修订重点**（基于 §8 autoplan review 33 finding）：
> - 顶部加 **§0.4 Reader Map**（缓解 DX T5：900 行无 TOC 找章节难）
> - **§3 各被 §8 finding 命中的子节加状态 banner**（缓解 DX T1：§3 与 §8 不 reconcile）
> - **§7.2 重写为"先决策清账 → 再实施"3 步队列**（缓解 DX T3：原 §7.2 启动会撞 §8 待决项）
> - §3.x 具体 schema 重写**延后到 PM 决策具体 finding 后再做**，不在 v3 内强行写（避免再一轮膨胀）
> - v2 修订重点保留：重排代码层 P0 / 修过满表述 / 修技术细节

**Changelog**：
- **v3.8（本版，2026-05-17）：codex review 落 6 finding 修订 — (1) §10.3 加 STALE banner + 删除"砍 I-DC1/I-AD5"误判句（v3.4 RV1 推翻）；(2) Reader Map "下周做什么"入口由 §7.2+§8 改指 §10.7；(3) §1.4 GSD hook 描述按 gsd-ref 实物纠正（12 脚本含 1 worker helper，事件含 statusLine/SessionStart/PreToolUse/PostToolUse，Gemini AfterTool）；(4) Context Monitor `AfterTool` → `PostToolUse`（Claude Code 主入口）；(5) Codex hook adapter 前提更新（codex-cli 0.130.0 `hooks` 已 `stable`，PAIN_LINK 弱暂停）；(6) skill 数 21 → 20（filesystem 实测）+ manifest 起手要求"从 filesystem 生成不手填"**
- **v3.7（2026-05-17）：补全 §10.7 漏项 — 之前只列 8 actionable + 5 暂停 + 10 废弃 = 23 项，对照 §2 矩阵原 28 项 + autoplan 新增发现漏 9 项。补全后总表：8 actionable + 1 已部分实施 + 5 暂停（PAIN 弱）+ 10 等触发条件 + 10 废弃 = 34 项**
- **v3.6（2026-05-17）：(1) 文档从 archive/ 移回 docs/ 作为事实来源；(2) §10.7 重写 — 去掉 Wave / P1/P2/P3 分组，直接平铺 8 个可借鉴项 + 总体优先级排序（1-8 名）；(3) 每项内容补全（目标 / PAIN_LINK / EVIDENCE / 工作量 / 实施要点 / 启动条件 / 风险）**
- **v3.5（2026-05-17）：(1) 新增 Wave 5.0c ADR 格式（grep verify GSD `docs/adr/` 10+ ADR，PMAI 此文档自身 1476 行散落决策即反例）；(2) 新增 §10.7 ROI 优先级最终整理 — 按 ROI 重排 P1/P2/P3，取代以前按 Wave 编号排序；(3) 推荐启动顺序明确：P1 3 项 ≤ 2 天独立可立即做**
- **v3.4（2026-05-17）：v3.3 后 PM 要求复审划分合理性，落 5 finding。关键修订：(1) Wave 5.1 根因错位 — "借 STATE.md 砍 I-DC1" 是误判，集中 mutation 入口解 state 字段一致性，不解 markdown 文档落盘；(2) Wave 5.1 工作量 1-2 天 → 3-5 天；(3) Wave 1 4 项从"🟡 保留"改为 ⏸️ 暂停（按 §0 痛点锁原则）；(4) Wave 5.2 优先级 🔴 高 → 🟡 中；(5) Wave 3 拆分 — Context Monitor + extract-learnings 提升，Read Injection 保持暂停**
- **v3.3（2026-05-17）：PM 拍板 D-v32-1=B → 3 项真痛点借鉴（#2 mutation 入口 / #3 lark-adapter / #4 SKILL 5 段骨架）作为 Wave 5 加入；Wave 1-2 保留原计划，Wave 3 ⏸️ 暂停 / Wave 4 ❌ 废弃。Wave 1.5/2 的"扩范围"标记回退（合并到 Wave 5 #4 一起做）**
- **v3.2（2026-05-16）：autoplan round 2 + PM pin 真痛点 → frame 转向"踩坑驱动"。新增 §10「痛点驱动借鉴对照」作为最新权威结论。前 §1-§9 内容降级为"研究素材"，Wave 1-4 排序不再推进，按 §10 判断重新决策**
- v3.1（2026-05-16）：Wave 1 开工前 PM 审核 + grep 现状落 5 finding（§3.2/§3.3/§3.4/§3.11/§8.5/§8.8 修订）。**关键发现**：§3.3 与现有 `agents/analysis-reviewer.md` 输出契约冲突；§3.4 与 `input-flow.md §9.1` 重叠；GATES.md 工作量低估 50%
- v3（2026-05-16）：autoplan 评审反馈精简版（reader map + errata banner + §7.2 重写）
- v2（2026-05-16）：codex 第二轮评审反馈修订（重排优先级 / 修过满表述）
- v1（2026-05-16）：首版

---

## §0.4 Reader Map（v3 新增）

**1300+ 行文档，30 秒找到你要看的章节：**

| 你的问题 | 跳哪节 |
|---|---|
| **看最新权威结论（v3.2 痛点驱动重新对齐 — 推荐起手）** | **§10** ⭐ |
| 这是什么、为什么写 | §0.1 / §0.2 |
| **下周做什么**（最高频问题） | **§10.7 ROI 排序起手清单（v3.6 最终决策视图）⭐** |
| §7.2 / §8 errata / §8.x finding | 历史审查材料，**最终结论已并入 §10.7**；只在追溯决策由来时查 |
| 某项设计为什么排 P0/P1/P2 | §2 矩阵 |
| 想落地某项 P0/P1 | §3.x（**先看 §8.5 errata index 看是否 BLOCKED**）|
| 想知道某项 P2 何时触发 | §6 触发条件 |
| 我不抄 GSD 的哪些设计、理由 | §4 |
| PMAI 哪些设计比 GSD 强 | §5 |
| autoplan review 完整 finding | §8.1-§8.6 |
| v2/v3 决策历史 | §8.6 decision audit + 顶部 changelog |

**🚨 启动前必读 banner**：本文档 §3 多个落地方案被 §8 review 发现真实 bug，**§3 任何子节顶部如有 `⚠️ Review 状态` 标记，必须先看 §8 对应 finding**。否则按 §3 落地会照错误契约执行。

---

## §0 背景与定位

### 0.1 两个项目的根本差异

| 维度 | PM-AI-Workflow | GSD |
|---|---|---|
| 服务对象 | **PM 单人产品工作** | **工程团队 AI 编码** |
| 规模 | 20 skill / 1 subagent / 340 测试 | 67 命令 / 33 subagent / 500+ 测试 / npm 包 / 4 国语言 |
| 哲学 | 小而紧（CLAUDE.md 明说"不是团队 SOP / CI 平台"）| 大而全 |
| 状态机 | 7 stage + 4 task 状态 | 6 phase + wave 并行 |
| 隔离 | git worktree per req/task；req 内多 task 已支持并行 | git worktree per phase 可选；multi-workstream 并行 |
| 分发 | 私人工具，框架同步 SOP | 公开 npm 包 |

两个项目解决的是**同一类问题**："AI agent 在多阶段工作中失控 / 漂移 / scope creep"。但目标用户不同，所以借鉴必须裁剪。

### 0.2 本文档解决什么

读完 GSD 6 个维度（架构 / 工作流 / agent / 防御 / 思维方法 / 特殊模式）+ 比对 PM-AI-Workflow 现状后，给出三类判断：
1. **确定要借的设计**（带具体落地方案）
2. **裁剪后借的设计**（去掉 GSD 特化部分）
3. **明确不借的设计**（避免被"看起来很酷"诱惑）

不解决：GSD 内部架构细节（如 SDK / TypeScript 双实现），那些是 GSD 自己的负担，但**它背后的思想（query registry / mutation 分类 / golden parity）值得吸收**，见 §4.1。

### 0.3 本文档不解决什么（防止后续 review 把这些拉进来）

| # | 衍生场景 | 为什么不解决 |
|---|---|---|
| 1 | "把 GSD 67 个命令逐条评估" | 大多数是团队 / 编码场景特化，PM 单人无需 |
| 2 | "复制 GSD 的 SDK / TypeScript 双实现" | 见 §4.1（**思想吸收 ≠ 代码复制**）|
| 3 | "完整实现 MVP / Spike / Spec / UI / Secure 阶段变体" | 见 §4.2，等触发条件 |
| 4 | "把 PM-AI 改造成 GSD 的子集" | 两者哲学不同，PM-AI 当前架构有自己的优势（见 §5） |

---

## §1 GSD 核心设计精髓（6 维度）

### 1.1 架构层

GSD 在 **prompt / CLI / SDK / state** 四个位置画了明确边界（`docs/ARCHITECTURE.md:22-66`）：

| 边界 | 职责 |
|---|---|
| Prompt 层 | `commands/gsd/*.md` + `workflows/*.md` —— 编排逻辑 |
| Agent 边界 | 每个 agent 拿 200K 全新上下文，避免 context rot |
| CLI / SDK 边界 | 双实现单一分发策略（ADR-3524 "Hard Seam"） |
| State 持久化 | 全部 markdown，无数据库，git 可追溯 |

**关键 idea**：
- "**Absent = Enabled**" —— config.json 缺键默认开启（`settings.md:34`），新项目开箱即用
- **STATE.md** 作为唯一共享内存 + 文件锁原子 CAS + 四层读取优先级避免 stale 推荐
- **Manifest + Drift Detection**：`docs/INVENTORY-MANIFEST.json` 记录所有 agent / command / reference，6 个 CI 测试锁 filesystem ↔ manifest 一致

### 1.2 工作流编排

每个 workflow.md 用**统一 XML 骨架**（`workflows/new-project.md:1-53`）：
```xml
<purpose>...</purpose>
<philosophy>...</philosophy>
<required_reading>
  @~/.claude/get-shit-done/references/thinking-models-planning.md
  @./CONTEXT.md
</required_reading>
<process>
  <step name="..." priority="first">...</step>
</process>
<success_criteria>...</success_criteria>
```

**`<required_reading>` 是 prompt contract**（`mandatory-initial-read.md`）：
> "If the prompt contains a `<required_reading>` block, you MUST use the Read tool to load every file listed there before performing any other actions."

注意：这是 **prompt contract，不是 runtime 可证明的行为**。lint 只能查"skill 是否声明了 `<required_reading>`"，无法证明"AI 实际执行 Read 了"——除非有 transcript / tool-call 审计。

**Artifact 角色分工**明确，每个文件有显式的消费方 / 非消费方：
- `PROJECT.md` / `REQUIREMENTS.md` / `CONTEXT.md` / `PLAN.md` / `SUMMARY.md` / `STATE.md` —— AI 消费
- `DISCUSSION-LOG.md` —— **明确不被下游消费**（人类审计用），避免过程噪音污染上下文

### 1.3 Agent 协作

33 个 agent 分 9 类（researcher / synthesizer / planner / executor / verifier / checker / mapper / auditor / utility），共同遵守 `agent-contracts.md`：

**Completion Markers**（agent 输出契约层面的退出信号）：
- `gsd-planner`: `## PLANNING COMPLETE`
- `gsd-executor`: `## PLAN COMPLETE` / `## CHECKPOINT REACHED`
- `gsd-verifier`: `## Verification Complete`
- `gsd-plan-checker`: `## VERIFICATION PASSED` / `## ISSUES FOUND`

Orchestrator 把 marker 当 agent 输出的约定段落消费，**不依赖语义判断**。

**Wave 并行执行**（`gsd-planner.md:1024-1042`）：
- plan 声明 `files_modified: [...]` + `depends_on: [...]`
- 同 wave plan 必须 `files_modified` 零交集，否则自动推到下一 wave
- 每个 executor 拿 fresh 200K context（orchestrator 不污染）

**Revision Loop + Stall Detection**（`revision-loop.md:18-35`）：
- 最多 3 轮
- 任意两轮 issue 数没下降立刻 escalate（挡 "AI 反复纠结同一处"）

### 1.4 防御层

**`hooks/` 下 12 个脚本**（含 1 个 worker helper `gsd-check-update-worker.js`），注册事件包含 `statusLine` / `SessionStart` / `PreToolUse` / `PostToolUse`（Claude Code），Gemini 用 `AfterTool` 替代 `PostToolUse`。大部分 advisory（不阻断），只有 commit validator 是 fail-closed。

**Read Injection Scanner**（`hooks/gsd-read-injection-scanner.js`）三层防御：
1. 11 条标准 prompt injection pattern
2. 4 条"压缩存活" pattern（防止"压缩时保留此指令"绕过 context compaction）
3. Unicode 隐形字符（零宽 + 标签块）

**Context Monitor** 35% / 25% 双阈值，CRITICAL 自动 spawn 子进程记录 stopped_at。

**Gates 4 类分类**（`get-shit-done/references/gates.md`）：

| 类型 | 行为 | 恢复 |
|---|---|---|
| Pre-flight | 前置不满足 block | 修补前置后重试 |
| Revision | 质量不达标回生产者 | 有迭代上限 + 停滞检测 |
| Escalation | 不可解暴露给用户 | 用户选路径后恢复 |
| Abort | 立刻停止保留状态 | 用户排查后从 checkpoint 重启 |

**Anti-Patterns 30 条**（`universal-anti-patterns.md`）分 6 类。最辛辣的：
> "#12 Checklist walking is the #1 anti-pattern"
> "#15 禁止直接 Write/Edit STATE.md，必须走 SDK CLI"

**Planner-Antipatterns** 含 `scope reduction prohibition`、`source audit` 等工程约束，挡 AI 偷偷削减范围（这是 PMAI 当前没有等价机制的地方）。

### 1.5 思维方法

**Thinking Models 5 件套**（`thinking-models-{debug,execution,planning,research,verification}.md`），每个 cluster 4-6 个 mental model：
- Pre-Mortem / MECE / Constraint Analysis（planning）
- Circle of Concern / Chesterton's Fence / First Principles（execution）
- Inversion / Confirmation Bias Counter（verification）
- Fault Tree / Hypothesis-Driven / Occam's Razor（debug）
- First Principles / Steel Man / Survivorship Bias（research）

**关键设计**：所有 model 都是 **decision-point triggered**（非 imperative checklist）。每个 model 有 "When to think" / "When NOT to think" 退出条件。

**Questioning Discipline**（`questioning.md`）：
> "Project initialization is dream extraction, not requirements gathering. You're a thinking partner, not an interviewer."

4 条 discipline：Start open / Follow energy / Challenge vagueness / Make abstract concrete。
明确禁止：Checklist walking / Canned questions / Premature constraints / Asking about user's tech experience。

**SPIDR 拆任务法**：Spike / Paths / Interfaces / Data / Rules，每种维度独立切分。

### 1.6 特殊模式（阶段变体）

主线流程 `new-project → discuss → plan → execute → verify → ship`，阶段变体是"前后插模块"：

| 变体 | 解决什么 | 关键产物 |
|---|---|---|
| **MVP** | 强制按功能切片拆，禁止单独的 schema / API task | SKELETON.md（架构契约）+ User Story regex 校验 |
| **Spike** | 探索性实验，不污染主代码库 | `.planning/spikes/` 独立目录 + 经验沉淀到 spike-findings skill |
| **Spec** | 用 Ambiguity 评分（4 维度加权）量化清晰度才能进 plan | SPEC.md + 5 视角采访（researcher / simplifier / boundary keeper / failure analyst / seed closer）|
| **UI** | plan 前先锁 UI-SPEC.md，防设计债 | UI-SPEC.md + ui-researcher + ui-checker revision loop |
| **Secure** | 验证 PLAN.md 的 threat register dispositions 真的实现了 | SECURITY.md + security-auditor |

---

## §2 可借鉴点矩阵

按优先级 + 工作量 + 收益分类。✅ = 抄；🟡 = 裁剪后抄；❌ = 不抄。

**v2 重排说明**：v1 把 P0 全设为"纯文档不动代码"，漏了 GSD 代码层真正高价值的框架自守机制。v2 新增"P0-代码层"（4 项），原"纯文档 P0"作为补充层。

> ⚠️ **v3 PM 决议（D4 T1=A，2026-05-16）**：autoplan 三 phase 三重确认 P0 排序错。**实际执行优先级**：**P0-补充（prompt 层）先做**，**P0-代码层 schema 准备好但延后实施**（D5=A 已要求按 §8 errata 重写 schema）。下表的"P0-代码层"标号保留，但**实际启动顺序按 §8.8 v3 PM 决议 + Wave 排序**——不要按本表顺序开工。

### P0-代码层 — 立即做（框架自守硬机制，本周）

| # | 设计 | 借法 | 工作量 | 收益 |
|---|---|---|---|---|
| **23** | **SKILL size budget lint**（≤ 400 行警告，超必须拆 references 或写理由）| ✅ 抄思想 | 1-2 小时 | 防 SKILL.md 持续膨胀。当前 task-spec 588 / task-execute 548 / doc-update 442 / close-task 425 已超 |
| **24** | **Mutation registry** —— `scripts/MUTATIONS.md` 列所有写盘脚本 + 写哪些文件 + 是否发事件 + 是否要 clean tree | ✅ 抄 GSD "mutation 分类"思想 | 半天 | 显式契约，挡 AI 偷偷加写盘脚本绕过 INVARIANTS |
| **25** | **task-status 补 blocking reasons** —— `status-view.py` 已有 `suggest_next_action`，但缺"为什么阻塞"输出 | 🟡 增量补 | 1-2 小时 | PM 看一眼就知道"下一步是什么 + 为什么不能继续" |
| **26** | **Inventory drift 测试扩展** —— 覆盖 skills / scripts / templates / tests / agents 全部 entity，不只是 README | ✅ 抄 GSD 6 个 drift 测试思想 | 半天 | 防加新 entity 时忘了同步任何一处 |

### P0-补充 — 同步做（纯文档不动代码）

| # | 设计 | 借法 | 工作量 | 收益 |
|---|---|---|---|---|
| 1 | `<required_reading>` XML 块替换"步骤 0：读 X" | ✅ 抄语法 + lint **声明**（不机械验证读完） | 0.5 天 | 结构化前置约束 + lint 可查"是否声明" |
| 2 | `GATES.md` 把 60 条 I-* 按 4 类二次归类 | ✅ 抄分类法 | 1 小时 | 写新 skill 时有词汇 |
| 4 | analysis-reviewer 加 Completion Marker | ✅ 抄 agent 输出契约（不写 shell grep） | 30 分钟 | agent 输出可机械检测段落 |
| 5 | Artifact 角色分工表（含"不被消费"列） | ✅ 抄 | 1 小时 | 挡 AI 读过程档案污染上下文 |

**v2 注**：原 P0-#3（INVENTORY.json + drift 测试）合并进新 P0-#26（扩展覆盖范围）。

### P1 — 2 周内做（小代码量）

| # | 设计 | 借法 | 工作量 | 收益 |
|---|---|---|---|---|
| 27 | **Evidence-first 呈交块** —— task-submit 明确分离 `verified` / `claimed` / `unverified` / `PM-walkthrough` 字段 | ✅ 抄 GSD verifier stance | 半天 | 挡 AI "我做了" 含糊表述，PM 看 diff 前就知道哪些被验证、哪些没 |
| 6 | Prompt Injection 防御 —— 三步走 | 🟡 移植规则不抄代码 | 1-2 天 | 见 §3.6 |
| 7 | `_shared/thinking/` 5 件套（思维模型） | 🟡 选 7-8 个 model 改 PM 视角 | 2-3 天 | memory 沉淀进 skill 公共契约 |
| 8 | `_shared/anti-patterns/` 5 个文件 | 🟡 GSD 30 条改 PM 单人场景 | 1 天 | 同上 |
| 9 | `_shared/thinking/questioning-discipline.md` | ✅ 抄 4 条 + 反模式 | 0.5 天 | 挡 AI checklist walking |
| 10 | `/extract-learnings` 命令（PM 显式触发，不自动跑） | ✅ 抄 + 改触发方式 | 1 天 | D13 那种总结自动化；满足 I-RV1 |
| 11 | Context Monitor 提醒（50% / 70% 警告） | 🟡 简化版（无自动 record） | 0.5 天 | 防 context 耗尽崩盘 |
| 12 | Subagent 类型白名单（禁通用 subagent 写 PM 文档） | ✅ 抄约束 | 30 分钟 | 挡 AI spawn Explore 绕过规则 |

### P2 — 等触发条件再做（中重型）

| # | 设计 | 触发条件 |
|---|---|---|
| 13 | `/health` 命令 + `--repair` | 当 `check-worktree-residue.py` 误报多到烦时 |
| 14 | Revision Loop 二次 review（上限 2 轮 + 停滞检测） | 当 reviewer 改完 analysis 出现质量回退案例时 |
| 15 | CHANGELOG 4-section 格式 + Reverted 标记 | 下次"撤回上版决策"发生时 |
| 16 | ADR 格式 + `docs/adr/` | 下次重大设计决策时起手 |
| 17 | `solution-reviewer` subagent | 当 solution 出现"PM 验收时才发现结构问题"案例时 |
| 18 | `plan-checker` subagent | 当 task 拆分反模式发生时 |
| 19 | `files_modified` 字段 + 冲突 lint | 当并行 task 真的撞到同文件时 |
| 20 | SPIDR 拆任务 PM 版（场景 / 角色 / 状态） | 当 task-plan 反模式频发时 |
| 21 | PROJECT-STATE.md（项目级 roadmap + recent_decisions） | 当跨 req 决策重复发生时 |
| 22 | Spec-phase Ambiguity 评分 4 维度 | 当 analysis 阶段 PM 反复说"还说不清楚"时 |
| **28** | **Python Query registry —— `scripts/_lib/queries/` 集中 state 读取**（D7=2 PM 决议）| **新脚本读 state 时第 3 次出现重复 parse 逻辑**（不限定 task_parser，包含 .req-meta.json / events.jsonl / worktree 任意 state 来源）|

---

## §3 落地方案（P0 + P1 详细）

### §3.0 P0-代码层 4 项

#### 3.0.1 #23 — SKILL size budget lint

**目标**：防 SKILL.md 持续膨胀。当前最长的 4 个：task-spec 588 / task-execute 548 / doc-update 442 / close-task 425。GSD 同样面对此问题，用 `surface budget` 思想处理（ADR-0011）。

**实现**：

```python
# scripts/lint-skill-size.py
THRESHOLD = 400  # 警告线
HARD_CAP = 600   # 拒绝合入

# 检查规则：
# 1. SKILL.md 行数 > THRESHOLD：检查是否有同目录 references/ 子目录
#    - 有 references/ → 警告但通过
#    - 无 references/ → fail，提示拆分
# 2. SKILL.md 行数 > HARD_CAP：直接 fail
# 3. SKILL.md 顶部声明 # noqa: skill-size <理由> → 豁免（需 PM 决议留痕）
```

配套：
- `tests/test-skill-size.sh` 调上面脚本
- 给 4 个已超阈值的 skill 加豁免声明 + TODO 拆分计划写进 `TODOS.md`

**工作量**：1-2 小时

---

#### 3.0.2 #24 — Mutation Registry

> ⛔ **v3 状态：BLOCKED**（被 §8.2 Codex-F1 + Subagent-F1 命中）
> 下面 schema 示例**事件契约写反**（req-transition.py 不发 stage_changed / close-task.sh 删 events 又 append）+ **脚本数严重低估**（写"12-15"，实际 ≥ 25）。
> **PM 决策前不要按下面表格落地**。落地前 grep 真实写盘脚本清单 + 修事件契约 + "clean tree"列改为引用 I-DC1 编号而非双源登记。详见 §8.2 / §8.5 errata。

**目标**：显式契约——所有写盘脚本必须登记。挡 AI 偷偷加写盘脚本绕过 INVARIANTS。GSD 在 ADR-3524 之后用 `lint-shared-module-handsync.cjs` 机械校验"哪些模块可写"。

**实现**：

新建 `scripts/MUTATIONS.md`：

```markdown
# 写盘脚本登记表

> 任何写文件 / 改 .req-meta.json / 改 task 状态字段的脚本必须登记本表。
> 加新脚本忘了登记 → CI fail（见 tests/test-mutation-registry.sh）。

| 脚本 | 写哪些文件 / section | 是否发事件 (events.jsonl) | 前置：clean tree? | INVARIANTS |
|---|---|---|---|---|
| `task-transition.py` | task.md 的「状态」字段 + events.jsonl | ✅ status_changed | ✅ I-DC1 | I-TT* |
| `req-transition.py` | .req-meta.json 的 stage 字段 + events.jsonl | ✅ stage_changed | ✅ I-DC1 | I-RT* |
| `close-task.sh` | req 分支 merge + 归档 .runs/ | ❌（消费 events） | ✅ I-CT2 | I-CT* |
| `close-req.sh` | main 分支 merge + 归档目录移动 | ❌ | ✅ I-CR4 | I-CR* |
| `apply-req-doc.sh` | task worktree 文件（drift apply） | ❌ | N/A | - |
| `task-events.py` | events.jsonl append | ✅（本身就是事件入口）| ❌ | I-CT7/I-CT8 |
| ... | ... | ... | ... | ... |
```

配套测试 `tests/test-mutation-registry.sh`：
```bash
# 1. 扫 scripts/*.{sh,py} 找所有 write_text / git commit / mv 等模式
# 2. 提取出写盘脚本清单
# 3. 对比 MUTATIONS.md 列表
# 4. 不一致 fail（列出未登记的脚本）
```

**工作量**：~~半天~~ → **延后实施**（按 §8.8 Q1=d 决议"等真实实施时再写 schema"——D4=A 决定代码层后做，schema 重写跟实施一起做更准。本节内容作为**未来实施备忘**，触发条件见 §6 触发条件表）

---

#### 3.0.3 #25 — task-status 补 blocking reasons

> ⚠️ **v3 状态：NEEDS REVISION**（被 §8.2 Codex-F3 + Subagent-F4 命中）
> 下面建议改 tuple 返回值是单 active 视角，**会破坏 status-view.py:579 + :638 两个 renderer**（都按字符串 print）+ 与多 active req 分支冲突。
> 落地时改 dataclass `NextAction(action, blocking)` + 同步更新两个 renderer。blocking_reason 来源限定 PM 决策类（未决问题 / dependency / manual 等待），不要把 audit-events 那种事中校验提前到 status-view。详见 §8.2 / §8.5 errata。

**目标**：现状 `status-view.py:400 suggest_next_action()` 已输出"下一步：X"，但缺"为什么不能继续"。增量改 `suggest_next_action()` 返回值，加 blocking 信息。

**改动**：

```python
# scripts/status-view.py:400
def suggest_next_action(meta, tasks, req_dir) -> tuple[str, str | None]:
    """返回 (next_action, blocking_reason)"""
    # 现状只返回 next_action 字符串
    # 改成返回二元组：next + blocking 原因（如有）
    
    # 示例：
    # ("/task-spec task-005", None)  # 顺畅推进
    # ("/close-task task-003", "task-003 状态=已完成但 worktree 仍有未 commit 改动")
    # ("等 PM 决策", "未决问题 #2 未回答")
```

输出格式：
```
下一步：/task-spec task-005
⚠️ 阻塞：task-004 状态=执行中但事件流缺 execution_started（I-CT7 风险，建议先 /task-status --task task-004 排查）
```

**工作量**：1-2 小时

---

#### 3.0.4 #26 — Inventory drift 测试扩展

> ⚠️ **v3 状态：NEEDS REVISION**（被 §8.2 Codex-F5 + Subagent-F1 命中）
> 下面把 scripts/templates/tests 全登记会与现有 `tests/run-all.sh` curated suite **双源冲突**——新增测试需双改 inventory + run-all 入口。lint 全扫又会误伤 _lib/exec-adapters/test fixture/install-hooks 等不该登记的实用脚本。
> 落地时缩成"公共实体与契约实体"清单（skills/agents/对外脚本/mutation入口）；测试改为验证 `run-all.sh` 包含应运行的 suite。详见 §8.2 / §8.5 errata。

**目标**：原 v1 P0-#3 只覆盖 skill 列表，扩展到全部 entity。

**新建**：

```json
// INVENTORY.json
{
  "skills": ["new-req", "req-analysis", ..., "init-project"],    // 21 个
  "agents": ["analysis-reviewer"],
  "scripts": ["task-transition.py", "req-transition.py", ...],   // ~40 个
  "templates": ["CLAUDE.md.tmpl", "task.md.tmpl", ...],          // ~17 个
  "shared_refs": [
    "skills/_shared/PM-VIEW-RULES.md",
    "skills/_shared/pm-view/writing-rules.md",
    ...
  ],
  "tests": ["test-task-transition.sh", "test-close-task.sh", ...]
}
```

```python
# scripts/check-inventory-drift.py
# 1. 扫文件系统：skills/*/SKILL.md / agents/*.md / scripts/*.{sh,py} / templates/* / tests/*.sh
# 2. 对比 INVENTORY.json 各数组
# 3. 不一致 fail，列出多出 / 缺失
```

```bash
# tests/test-inventory-drift.sh
python3 scripts/check-inventory-drift.py || exit 1
```

**工作量**：半天

---

### §3.1 P0-补充 #1 — `<required_reading>` XML 块

> ⚠️ **v3 状态：NEEDS REVISION**（被 §8.2 Codex-F2 命中）
> 下面"所有 PM 视图 SKILL.md 必含" + lint 扫所有 SKILL.md 与"改动范围只列 6 个 skill"**矛盾**——项目实际 21 skill。两种实现都不能同时满足文档和 §7.3 验证标准。
> 落地时加 `skill_structure.yml` manifest 标注 `pm_view / requires_required_reading / requires_read_echo`；lint 只按 manifest 执行。详见 §8.2 errata。

**目标**：把现有 SKILL.md 的"步骤 0：读 X / Y / Z"统一改成结构化 XML 块。

**注意（v2 修正）**：这是 prompt contract，不是 runtime 可证明的行为。lint **只能查"是否声明"**，不能证明 AI 实际 Read 了文件。

**三层落地**：

| 层 | 实现 | 可证 / 可观测 |
|---|---|---|
| 1. 结构化声明 | 所有 PM 视图 SKILL.md 必含 `<required_reading>` 块 | ✅ lint 可证 |
| 2. lint 强制 | `scripts/lint-skill-structure.py` 扫所有 SKILL.md，缺块 fail | ✅ CI 可证 |
| 3. 高风险 skill 回显 | task-spec / close-req / req-solution 在步骤 0 之后必须输出"已读：[列文件]" | 🟡 可观测（PM 在 chat 看到）|

**改动范围**：

| 文件 | 改动 |
|---|---|
| `skills/req-analysis/SKILL.md` | 步骤 0 改 `<required_reading>` |
| `skills/req-solution/SKILL.md` | 同上 + 步骤 0.5 加"已读回显" |
| `skills/task-plan/SKILL.md` | 同上 |
| `skills/task-spec/SKILL.md` | 同上 + 步骤 0.5 加"已读回显" |
| `skills/prd-writing/SKILL.md` | 同上 |
| `skills/close-req/SKILL.md` | 同上 + 步骤 0.5 加"已读回显" |
| `scripts/lint-skill-structure.py` | **新建**：每个 SKILL.md 必须有 `<required_reading>` |
| `tests/test-skill-structure.sh` | **新建**：调 lint 脚本 |
| `_shared/PM-VIEW-RULES.md` | 顶部加一段"如何写 `<required_reading>` 块 + 何时要求'已读回显'" |

**XML 块约定**：
```xml
<required_reading>
  @skills/_shared/pm-view/writing-rules.md
  @skills/_shared/PM-VIEW-RULES.md  # §五 / §六
  @skills/_shared/pm-view/section-order.md
</required_reading>
```

**契约一句话**（贴在每个 SKILL.md 顶部）：
> "本 skill 含 `<required_reading>` 块的，AI 必须用 Read 工具实际打开每个文件。**高风险 skill（task-spec / close-req / req-solution）额外要求步骤 0 之后输出"已读：[文件清单]"让 PM 可观测**。"

**工作量**：0.5 天

---

### §3.2 P0-补充 #2 — GATES.md 分类索引

> 🟡 **v3.1 修正**：v3 估时 1h 偏乐观。grep 现状 `INVARIANTS.md`：11 类前缀（I-G/I-CT/I-CR/I-CA/I-CB/I-AD/I-DC/I-RV/I-TT/I-RT + 已废弃 I-PR），自称 60 条但实际唯一编号 ~72；且 GATES.md 范围**不止 I-* 60 条**——现有运行时机制（analysis-reviewer 三选一、未决问题闸门、Stage 1→2 review）属 Revision/Escalation Gate 但**不在 INVARIANTS.md 里**，需一并登记。**重估工作量 1.5-2h**。

**目标**：把 INVARIANTS.md 60 条 I-* + 运行时 review/escalation 机制按 GSD 4 类 gate 归档。

**新建** `GATES.md`（与 `INVARIANTS.md` 平级）：

```markdown
# 闸门分类（与 INVARIANTS.md 互引）

## Pre-flight Gate（前置不满足直接 block）
| 编号 | 出处 | 一句话 | Recovery |
|---|---|---|---|
| I-DC1 | task-spec / task-confirm / req-transition | dispatch 前文档落盘必须 clean | auto-commit 兜底，或 PM 手动 commit |
| I-CR1 | close-req.sh | req stage 必须 = 7 | 走 req-stage-gate 推进到 7 |
| ... | ... | ... | ... |

## Revision Gate（质量不达标回生产者）
| analysis-reviewer | req-stage-gate Stage 1→2 | 4 角度评审 | AI 改 / PM 自改 / 接受现状 |

## Escalation Gate（不可解 → 暴露给 PM 决策）
| 未决问题闸门 | req-stage-gate Stage 2→3 | analysis 含未决问题必须 PM 答完 | PM 答完 |

## Abort Gate（立刻停止保留状态）
| I-CT7 | close-task.sh | 事件流必须证明状态机完整推进 | 排查 status_changed 事件缺失 |
| I-CT8 | close-task.sh | code commit 时间戳必须晚于"执行中"事件 | 重做 task |
```

**工作量**：1 小时

---

### §3.3 P0-补充 #4 — Completion Marker

> 🔴 **v3.1 重写**（覆盖 v2/v1 方案）：grep 现状 `agents/analysis-reviewer.md:78-119` 已有完整输出契约（`**总体判断**：PASS / NEEDS_REVISION` + 4 评审角度 + `## 给主线 AI 的下一步建议`），且 `skills/req-analysis/SKILL.md:152,204` 强制贴原文+禁转述。引入 GSD 风格 `## REVIEW COMPLETE` 会产生**两套结尾段冲突**。改成"对齐已有契约 + lint 校验"。

**目标**：把 agent 现有自由输出契约**固化成机械可校验的模板**，方便后续新增 agent 时复用同套契约。

**改动**：

**A. `agents/analysis-reviewer.md`** —— **不加新模板**。现状 line 82-119 的输出格式已是契约（包含 `**总体判断**：PASS / NEEDS_REVISION` + `## 给主线 AI 的下一步建议`），仅在文件**顶部 frontmatter 后**加一行注释作为 lint 锚点：
```markdown
<!-- completion-marker: 总体判断 / 给主线 AI 的下一步建议 -->
```

**B. `skills/req-analysis/SKILL.md`** —— **不改流程**。现状 line 138-205 已强制贴原文+按 verdict 三选一。仅在步骤 4 末尾加一行验证：
> "若 reviewer 输出**缺失 `**总体判断**：` 行或 `## 给主线 AI 的下一步建议` 段**，提醒 reviewer 按 agent 输出契约补全（不重跑评审，只补缺失段）。"

**C. `scripts/lint-agent-files.py`（新建）**：
```python
# 扫 agents/*.md：
# 1. 提取 frontmatter 后的 <!-- completion-marker: ... --> 注释
# 2. 按注释列出的 section 名校验文档中"输出格式"段是否含这些 section
# 3. 缺失 fail，列出 agent 名 + 缺失 section
```

**D. `tests/test-agent-files.sh`（新建）** 调 lint 脚本。

**为何不引入 GSD `## REVIEW COMPLETE`**：
- 现状 PM 已看完整原文做三选一，机械检测段落价值低
- 双套模板会让 reviewer 输出冗余（"## 给主线 AI 的下一步建议" + "## REVIEW COMPLETE"）
- 现有契约本身已经"fail-closed"——缺 verdict 行就是错误输出

**工作量**：30 分钟（实施内容变了但量不变）

---

### §3.4 P0-补充 #5 — Artifact 角色分工表

> 🟡 **v3.1 修正**（默认采用选项 a）：grep 现状 `skills/_shared/pm-view/input-flow.md:7-9` 已是 §9.1 "各 skill 必读输入清单（全 stage 权威表）"——本质就是"哪个 skill 读哪些 artifact"的**单一权威源**。直接在顶部加新表会触发**双源漂移** + input-flow.md 从 386 → 430+ 行（接近未来 SKILL size 警告线）。
>
> **三选项**（推荐 a）：
> - **a) 在 §9.1 现有表加"❌ 明确不消费"子列** —— 复用单一权威源，不增长文件结构 ✅ 推荐
> - b) 新建 `skills/_shared/pm-view/artifact-roles.md` 独立文件，与 §9.1 互引
> - c) 照原方案加 input-flow.md 顶部（不推荐，触发 size 问题）

**目标**：明确每份文档"谁消费 / 谁明确不消费"，挡 AI 读过程档案污染上下文。

> 🔍 **autoplan round 2 修正（grep 现状）**：第一轮审核漏了一步 grep。实地 `grep -n "❌" skills/_shared/pm-view/input-flow.md` 显示**现有已有 6 处 ❌ marker**（line 19/41/69/82/98/147），全部针对 `.engineering.md` 排除。
> 所以 v3.1 §3.4 原表述 "现有 §9.1 只列 🟢/🟡/⚪ 三档" **不准确** —— ❌ pattern 已存在，缺的是**业务文档类**反向约束（brief / analysis / solution 在何 skill 不该读）。
>
> **Wave 1 #3 实施 done-definition**（避免实施时分歧）：
> - **不是新增一列**，而是**扩展现有 ❌ pattern**——每个 stage 段补"❌ 业务文档类：xxx"行
> - 每个 skill 段必须至少有一个 ❌ 行 OR 显式 `❌ 无（本 skill 是入口）` 标记
> - 已存在的 `❌ 任何 .engineering.md` 保留不动，新增 ❌ 与之并列

**核心增量是"业务文档类 ❌"维度**——现有 ❌ 只覆盖工程合同读取边界，缺业务文档（brief/analysis/solution/.runs）在下游 skill 的明确不读项。

**改动（选项 a 默认方案）**：

`skills/_shared/pm-view/input-flow.md` §9.1 现有按 stage 列的清单中，每个 skill 段末加一行 `❌ 明确不读：`（与现有 ❌ `.engineering.md` 行并列），覆盖以下高优先级业务文档类反向约束：

| skill | ❌ 明确不读项（v3.1 新增反向约束） |
|---|---|
| `task-execute` | `brief.md`（用 solution.md 代替）/ `analysis.md`（同）/ 上一轮 `历史档案 段` |
| `close-task` | `brief.md` / `analysis.md` / `solution.md`（已在 task spec 沉淀）|
| `req-solution`（PM 视图）| 任何 `.engineering.md`（line 41 已有，保留）|
| `task-plan` | 任何 `.engineering.md`（line 69 已有，保留）|
| PM chat 渲染 | `.runs/events/<task>.jsonl`（过程噪音）|

**为何不照搬原表**：
- 现有 §9.1 是"按 skill 视角"的完整清单（line 21-130），覆盖 7 个 stage
- 原方案按 artifact 视角列 8 行——信息量小于现有按 skill 表，且与现有表互不引用容易漂移
- 真正缺的是"❌ 明确不读"反向列，不是再来一张正向表

**工作量**：1 小时

**Wave 2 依赖更新**（替代 §8.8 原 Wave 1→2 描述）：
- Wave 2 P0-#1 `<required_reading>` XML 块**真实依赖** = §9.1 表加完"❌ 明确不读"列后，把每个 skill 步骤 0 的隐式约束**显式化**为 XML 块（不需要重新发明 Artifact 表）

---

### §3.5 P1-#27 — Evidence-first 呈交块（v2 新增）

> 🚫 **v3 PM 决议：DEFER 整节，不实施**（D6 T3=B，2026-05-16）
>
> **决议理由**：CEO+Eng 跨 phase 三重确认"无 enforcement 是更精致的谎言载体"。PM 现有 task-execute 步骤 11 呈交块 + recommended review 已足够。**不引入更精致的伪执行渠道**——这跟 memory `feedback_skill_must_actually_invoke` 完全对齐。
>
> **回头看条件**：若未来 `task-events.py` 支持 `verification_emitted` 事件类型 + hook 自动 append cmd/exit/output_hash + cite event ID 强制 lint 三件套**全部齐备**，可再评估是否实施本节。
>
> **下面内容作为 DEFER 备忘留存**（决策痕迹有价值，不删除）：
>
> ---
>
> （原 v2 设计：抄 GSD verifier stance —— "不信我做了，只列可观察行为 + 验证命令 + 未验证项 + PM 走查路径"）

**目标**：抄 GSD verifier stance —— "不信我做了，只列可观察行为 + 验证命令 + 未验证项 + PM 走查路径"。

**现状**：`task-execute` 步骤 11 的呈交验收信息块已包含 diff 摘要 + 推荐 review，但**没有显式分离"已验证 vs 自称完成"**。

**改动**：`skills/task-execute/SKILL.md` 步骤 11 呈交块模板加 4 个固定 section：

```markdown
## 验收呈交（v2 evidence-first 版）

### ✅ 已验证（agent 跑过具体命令 / 看到具体输出）
- 单测：`pytest tests/test-foo.py` → 12 pass / 0 fail
- 类型检查：`pyright src/foo.py` → 0 errors
- dev server：访问 `http://localhost:3000/admin/users` 看到列表

### 📋 自称完成但未独立验证（claimed）
- "用户体验流畅"——主观判断，需 PM 走查
- "代码风格符合项目" ——没跑 lint，需 PM 确认是否要跑

### ⚠️ 明确未验证（unverified）
- 移动端响应式（本机没测试设备）
- 跨浏览器兼容（只测了 Chrome）

### 🚶 PM 走查路径（按这个顺序点）
1. 打开 http://localhost:3000/admin/users
2. 看顶部计数 = "共 N 用户"
3. 点表头排序，验证升降序切换
4. 删一行，看刷新后不存在

### ⚙️ 可选深度审查
- `/qa` 跑功能 QA
- `/review` 看 commit diff 安全性
```

**配套约束**（写进 `task-execute/SKILL.md`）：
> "禁止把'代码已实现 / 功能已完成 / 测试已通过'写成笼统断言，必须分流到上面 4 个 section。`unverified` 一项不能为空——任何 task 都有未验证的角落（边缘 case / 极端输入 / 并发场景），列出来让 PM 知道盲区。"

**工作量**：半天（含改 fixture + 加测试断言"呈交块必含 4 个固定 section"）

---

### §3.6 P1-#6 — Read Injection Scanner（v2 修正三步走）

**目标**：挡 prompt injection 攻击。

**v2 修正**：v1 建议"直接抄 hook 代码"不合适——Claude 和 Codex 的 hook schema 不同，PMAI 有 Codex executor adapter（`exec-adapters/codex.sh`）。直接抄变成 "Claude-only 且不可测"。

**正确三步走**：

| 步 | 动作 | 工作量 |
|---|---|---|
| 1 | `scripts/check-prompt-injection.py` —— 移植 GSD 规则（11 条标准 + 4 条压缩存活 + Unicode），advisory 模式（不阻断），脚本可独立跑 | 1 天 |
| 2 | `tests/fixtures/injection-samples/` —— 写 ~10 个含 injection pattern 的文档样本 + `tests/test-prompt-injection.sh` | 0.5 天 |
| 3a | Claude hook adapter `.claude/hooks/claude-pm-injection-scanner.js` —— 包装步骤 1 脚本，按 Claude hook schema 注册 PostToolUse Read | 0.5 天 |
| 3b | Codex hook adapter —— 同上但按 Codex schema（codex-cli 0.130.0 `features list` 中 `hooks` 已 `stable=true`）| 已可适配，当前因 PAIN_LINK 弱暂停 |

**误报排除清单**：`requirements/active/` + `docs/` + `prototypes/` + `skills/_shared/anti-patterns/` 本身（防自伤）

**Hook 行为**：severity HIGH → 弹警告到 chat（advisory，不阻断 Read）。

**工作量**：1-2 天（不含 Codex adapter；Codex hooks 已 `stable`，需另适配 schema，PAIN_LINK 弱暂停）

---

### §3.7 P1-#7 — `_shared/thinking/` 5 件套

> ⚠️ **v3 状态：NEEDS REVISION**（被 §8.2 Codex-F4 + Subagent-F3 命中）
> §3.7 `_shared/thinking/` 与 §3.8 `_shared/anti-patterns/` **高度重叠**——planning-thinking 的"MECE / Pre-Mortem"与 anti-patterns/planning 的"AI 偷削范围"是同一规则正反两面；questioning-discipline.md 同时在两目录被双重列入。多入口管同组规则会出现 `<required_reading>` 重复引用或漂移。
> 落地时二选一：（a）合并到 5 个文件（每文件含正反两节，按生命周期阶段 solution/planning/execution/verification/questioning）；（b）保留两目录但每条规则唯一 owner（thinking 文件放正向触发，anti-patterns 文件只放反例并被前者引用）。详见 §8.5 errata。

**目标**：把私人 memory 里的 judgment / 反模式沉淀到 skill 公共契约。

（内容同 v1，未改。简化版见此）

**新建 5 个文件**：

| 文件 | 内容 |
|---|---|
| `_shared/thinking/solution-thinking.md` | Pre-Mortem / Reversibility / Steel Man / MECE |
| `_shared/thinking/planning-thinking.md` | MECE / Pre-Mortem / Constraint Analysis |
| `_shared/thinking/execution-thinking.md` | Circle of Concern / Chesterton's Fence / First Principles |
| `_shared/thinking/verification-thinking.md` | Inversion / Confirmation Bias Counter |
| `_shared/thinking/questioning-discipline.md`（**v2 注**：原 P1-#9，归入此节）| Start open / Follow energy / Challenge vagueness / Make concrete + 反模式 |

每个文件 ≤ 200 行，按需引用进 `<required_reading>` 块。每个 model 必带 "When to think" / "When NOT to think" 退出条件，**不当强制 checklist**。

**工作量**：2-3 天（含 questioning-discipline）

---

### §3.8 P1-#8 — `_shared/anti-patterns/` 5 件套

> ⚠️ **v3 状态：NEEDS REVISION**（与 §3.7 联动，见上）

（内容同 v1，未改）

**新建 5 个文件**：

| 文件 | 内容来源 |
|---|---|
| `_shared/anti-patterns/universal.md` | GSD 30 条改 PM 单人场景 |
| `_shared/anti-patterns/planning.md` | memory + GSD `planner-antipatterns.md` |
| `_shared/anti-patterns/questioning.md` | "Checklist walking" + 3 类反模式 |
| `_shared/anti-patterns/state-mutation.md` | task-transition / req-transition 强制入口 |
| `_shared/anti-patterns/writing.md` | `writing-rules.md` 禁止条款 |

**工作量**：1 天

---

### §3.9 P1-#10 — `/extract-learnings` 命令（v2 修正触发方式）

**目标**：D13 那种"总结教训"自动化。

**v2 修正**：v1 写"`/close-req` 后自动跑"违反 `INVARIANTS.md` I-RV1（AI 不得自动调用 review 类工具）。改成 **PM 显式触发**：

**触发方式**：
1. `/close-req` 完成时**列推荐**："建议跑 `/extract-learnings` 沉淀本 req 经验"（不自动跑）
2. PM 显式输入"沉淀经验 / 总结这轮 / 跑 extract-learnings"才执行

**3 类沉淀内容**：

| 类型 | 是什么 | 防什么 |
|---|---|---|
| **Decision** | 这个 req 拍板的关键产品决策 | 下次重新讨论同一议题 |
| **Pattern** | 可复用的实现 pattern | 下次重新设计同一结构 |
| **Surprise** | 实际遇到的反直觉问题 | 下次重新踩同一坑 |

**实现**：

```
skills/extract-learnings/SKILL.md（新建）
scripts/extract-learnings.sh（新建）
tests/test-extract-learnings.sh（新建）
LEARNINGS.md（业务仓产出，模板放 templates/）
```

**配套**：
- 在 `INVARIANTS.md` I-RV* 段补一条 I-RV4："`/extract-learnings` 是 review 类工具的一种，遵循 I-RV1 推荐 + PM 显式触发"
- `skills/close-req/SKILL.md` 末尾推荐区块加一行

**工作量**：1 天

---

### §3.10 P1-#11 — Context Monitor

（内容同 v1，未改。简化版无自动 record。）

```javascript
// .claude/hooks/pm-context-monitor.js
// PostToolUse 钩子读 context usage（Claude Code 是 PMAI 主入口；Gemini 走 AfterTool 时需另注册 adapter）：
// 50%: "📊 上下文已用 50%，建议本 req 结束后开新会话"
// 70%: "⚠️ 上下文 70%，建议立即走 close-req 然后开新会话"
```

**工作量**：0.5 天

---

### §3.11 P1-#12 — Subagent 类型白名单

> 🟢 **v3.1 修正**：grep 现状 `cross-skill.md` 30 行 7 条规则，方向兼容；但 `skills/_shared/anti-patterns/` **目录不存在**（Wave 4 才建）。配套 anti-pattern 文件**延后到 Wave 4**，cross-skill.md 加 TODO 注释指向。

**新增约束**（写进 `_shared/pm-view/cross-skill.md` 第 8 条规则）：
> "PM 视图 skill 内禁止 spawn Explore / general-purpose subagent 做'调研后写 PM 文档'。spawn subagent 只能用于'只读侦察'（找文件位置、grep 关键词），不能让它产出 PM 视图文档。"
>
> `<!-- TODO Wave 4: 配套 anti-pattern 沉淀进 _shared/anti-patterns/universal.md -->`

**Wave 4 待补**：anti-pattern 文件创建时把以上 TODO 解开，把规则的"反例形式"沉淀进 universal.md。

**工作量**：30 分钟

---

## §4 明确不借鉴的（也是决策）

### 4.1 SDK / TypeScript 双实现（v2 修正：不引入产品，吸收思想）

**GSD 现状**：`sdk/` 目录是完整的 TypeScript + Vitest npm 包。同时存在 `get-shit-done/bin/gsd-tools.cjs` 旧 CJS 实现（被 `@deprecated` 标但删不掉，47 个 workflow.md 还在调用）。维护双实现成本极高，靠 `lint-shared-module-handsync.cjs` 在 PR 时机械校验。

**不引入的**：
- TypeScript build step + node_modules + Vitest 基础设施
- npm 包发布
- 双实现同步负担

**值得吸收的轻量思想**（直接落进 PMAI 现有 shell + python）：

| GSD SDK 思想 | PMAI 落地 |
|---|---|
| **Query registry** —— 所有"读 state / 算 progress"集中注册 | `scripts/_lib/` 已有雏形（`task_parser.py` `worktree.sh`），扩成 `_lib/queries/` 集中读 |
| **Mutation 分类** —— 显式声明哪些操作写盘、哪些只读 | **P0-#24 已纳入**（`MUTATIONS.md`）|
| **Event emission 策略** —— 哪些 mutation 必须 emit 事件 | 已有 `task-events.py`，把"哪些 mutation 必发事件"显式登记进 MUTATIONS.md |
| **Golden parity test** —— 同一逻辑两种实现必须输出一致 | **不适用**（PMAI 没双实现），但 fixture 测试理念可用 |

**判断**：GSD 必须做 SDK 因为它要做平台（"engineers at Amazon/Google/Shopify"），PMAI 不是平台。但 query registry / mutation 分类 / 事件契约这些**轻量思想可以吸收**，不需要 TypeScript 包装。

### 4.2 阶段变体（MVP / Spike / Spec / UI / Secure）

| 变体 | 不抄理由 | 何时回头看 |
|---|---|---|
| MVP（垂直切片 + SKELETON） | quick-fix 已覆盖轻量场景；MVP 中间档暂无诉求 | ExampleConsumerApp dogfood 5+ req 后，若"做原型给老板看"场景 quick-fix 容纳不下 |
| Spike | 你的 `/quick-fix` + worktree 隔离已覆盖；"独立探索区"概念可以用 `requirements/explorations/` 轻量目录替代 | 当 PM 出现"想试个想法但不确定要不要开 req"的频次 ≥ 3 次/月时 |
| Spec（Ambiguity 评分 + 5 视角采访）| 4 维度 + 权重公式对 PM 太工程化 | 5 视角采访 pattern 已纳入 P1-#9（questioning-discipline） |
| UI-phase | PM 不主管 UI 设计细节；gstack `/design-consultation` `/design-shotgun` 已覆盖 | 永不（gstack 是更优解） |
| Secure-phase | PM 不主管安全 | 永不 |

### 4.3 多语言分发 + npm 包

GSD 有 4 国语言 README + npm 包发布。PMAI 是私人工具，永不需要。

### 4.4 67 命令式可配置性（`/settings` `/config` `/workspace` 等）

GSD 用 `.planning/config.json` + "Absent = Enabled" 让用户开关 workflow.research / workflow.verifier 等。

**不抄理由**：PMAI 20 skill 硬编码 + 简单容易演进。"想全局关掉某机制"诉求一次都没出现过。等真出现再说。

### 4.5 Workstream 多工作流并行（v2 修正）

GSD 有 `.planning/active-workstream` 概念，支持**多个独立工作流并行**（不同业务 / 不同租户）。

**v2 修正**：v1 写"PM 一个人不并行"与现状冲突——`README.md:87` 明确说 v4 已支持 req 内 task 并行（开多新窗口跑 `/task-execute`）。

**正确表述**：
- ✅ PMAI **已支持** req 内 task 并行（worktree 天然隔离）
- ❌ **不引入** GSD 的 multi-workstream（多 active req 并行 / 跨业务隔离）—— PM 单人单业务，无诉求

---

## §5 PM-AI 比 GSD 强 / 弱的地方（v2 修正对称分析）

**v2 修正**：v1 列了 7 处"PMAI 强"过满（如"GSD 没机制挡 review 只加不砍"——实际 GSD `planner-antipatterns.md` 有 `scope reduction prohibition`；"PMAI 扫文件系统不会 stale"——并发写时也可能漂）。改成对称分析：

### PMAI 在以下场景更优（PM 单人痛点驱动）

| PMAI 设计 | 为什么对 PM 单人更优 |
|---|---|
| **§0 痛点锁 + PAIN_LINK / EVIDENCE 字段** | 挡 D13 那种"5 轮 autoplan 把 2h 方案放大成 30h+"的 review 膨胀。GSD 也有 `scope reduction prohibition` 但方向相反（挡缩水，不挡膨胀）|
| **memory feedback 闭环 + 跨项目自动加载** | 比 GSD markdown 反模式档更轻量 + 跨项目复用 |
| **task-execute 沙盒边界自检（cd reset 检测）** | 你踩过具体的 Claude Code 沙盒坑 + 沉淀防御；GSD 无此场景 |
| **`_shared/` 单源 + 按消费方拆 6 子文件** | 按 PM 视图工作流自然分层；GSD references 多但更松 |
| **CLAUDE.md = 主要约束 + hook = 补充检查双层分工** | 明确告诉 AI"为什么有 hook + 为什么有 CLAUDE.md"；GSD 几乎全靠 hook + prompt |

### GSD 在以下场景更优（工程团队 source audit）

| GSD 设计 | PMAI 缺什么 |
|---|---|
| **`scope reduction prohibition` + `source audit`**（planner-antipatterns）| PMAI 没等价机制挡"AI 偷偷削减范围以求通过 review" |
| **Verifier stance —— evidence-first** | PMAI task-submit 呈交块缺 verified / claimed / unverified 显式分离（**P1-#27 已纳入**）|
| **STATE.md 文件锁 + 4 层读取优先级** | PMAI 扫文件系统当 source of truth，**并发写时也可能漂**（虽然 PM 单人场景几乎不触发） |
| **Mutation registry + drift test** | PMAI 没有"所有写盘脚本登记表"（**P0-#24 已纳入**）|
| **Hook + tests 双层防 frontmatter / size 漂移** | PMAI 没 SKILL size 上限（**P0-#23 已纳入**）|
| **Agent completion markers 强契约** | PMAI 只有 1 个 subagent，没沉淀契约（**P0-#4 已纳入**）|

**关键洞察**：v1 写得过于单边。**PMAI 和 GSD 哲学不同**——PMAI 优势在"PM 单人痛点驱动 + 单一真相源"，GSD 优势在"细粒度边界 + 三层防御 enforcement + 工程合规"。借鉴方向已对齐：**借 GSD 的具体机制（特别是框架自守层），不借它的规模和复杂度**。

---

## §6 后续触发条件（什么时候回头看 P2）

P2 列表（§2 #13-#22）按"什么实证事件出现就实施"组织：

| 触发事件 | 对应动作 |
|---|---|
| `check-worktree-residue.py` 误报 ≥ 3 次 | P2-#13 `/health` 命令 |
| reviewer 改完 analysis 出现质量回退 | P2-#14 Revision Loop 二次 review |
| 撤回上版决策（类似 D13 v3→v2） | P2-#15 CHANGELOG 4-section + Reverted 标记 |
| 重大设计决策起手 | P2-#16 ADR 格式 + `docs/adr/` |
| solution 出现"PM 验收时才发现结构问题" | P2-#17 `solution-reviewer` subagent |
| task 拆分反模式发生 | P2-#18 `plan-checker` subagent |
| 并行 task 撞同文件 | P2-#19 `files_modified` 字段 + 冲突 lint |
| task-plan 反模式频发 | P2-#20 SPIDR PM 版 |
| 跨 req 决策重复发生 | P2-#21 PROJECT-STATE.md |
| analysis 阶段 PM 反复说"还说不清楚" | P2-#22 Ambiguity 评分 4 维度 |

**审视频率**：每完成 5 个真实 req 走完整流程后，PM 复盘一次本表，触发了的实施、没触发的继续等。

---

## §7 结论与下一步

### 7.1 v3.1 核心清单（按 §8.8 D4=A + D6=B 重写）

> ⚠️ **v3.1 重写**（覆盖 v2 / v1 排序）：v2 把"代码层 P0 框架自守"放前 5 件，但 **§8.8 D4=A 决"prompt 层先做，代码层延后"** + **D6=B 决"Evidence-first DEFER"** → v2 5 件中 4 件需调整。

**新 v3.1 核心 5 件（prompt 层为主，可立即开工）**：

| 优先 | 项 | 类型 | Wave | 工作量 |
|---|---|---|---|---|
| 1 | **Completion Marker**（P0-#4）| agent 契约 + lint | Wave 1 | 30min |
| 2 | **GATES.md 4 类归类**（P0-#2）| 文档分类 | Wave 1 | 1.5-2h |
| 3 | **Artifact 角色分工 §9.1 反向列**（P0-#5）| skill 契约 | Wave 1 | 1h |
| 4 | **Subagent 类型白名单**（P1-#12）| 跨 skill 约束 | Wave 1 | 30min |
| 5 | **`<required_reading>` XML 块**（P0-#1）| prompt 结构化 | Wave 2 | 0.5d |

**Wave 3 也值得做（独立 hook + 命令）**：
- Context Monitor（P1-#11）—— 50%/70% 警告
- `/extract-learnings`（P1-#10）—— PM 显式触发
- Read Injection Scanner（P1-#6）—— 三步走

**延后到代码层 Wave（按 D4=A + Q1=d 等真实实施触发）**：
- Mutation Registry（P0-#24）—— ⛔ BLOCKED 待 §8.5 errata schema 重写
- Inventory drift 全覆盖（P0-#26）—— ⚠️ NEEDS REVISION
- SKILL size budget lint（P0-#23）—— v2 唯一无 finding 的代码层项，可单独提前
- task-status blocking reasons（P0-#25）—— ⚠️ NEEDS REVISION

**整节 DEFER（按 D6=B）**：
- Evidence-first 呈交块（P1-#27）—— 见 §3.5 DEFER banner

### 7.2 下一步动作（v3 重写：3 步队列，先决策清账再实施）

> ⛔ **启动前提**：§8 共 28 个待 PM 决 finding（25 PAIN_LINK + 5 跨 phase 主题）必须先答完，否则按下面"开干"会撞 §8 阻塞项翻车。**v2 原 §7.2 "本周做 P0" 已 STALE**。

**v3 执行队列（3 步）**：

#### 步骤 1：决策清账（先答 §8 finding，半天工作量）

按主题批量决策（不要逐条；同主题 finding 一次拍）：

| 主题 | 关联 finding | PM 决策（一行）| 决议 |
|---|---|---|---|
| T1 P0 排序错（3 phase 三重确认）| CEO C-F2/S-F2 + Eng C-F2/C-F3/S-F4 + DX C-F3/S-F3 | P0 是改 prompt 层（评审防膨胀 + Evidence enforcement）还是代码层（Mutation/Inventory/size）？ | ___ |
| T2 §3 代码 bug | Eng C-F1/C-F2/C-F3/C-F5 + Subagent F1/F4 | Mutation/required_reading/status-view/Inventory 4 个 §3.x 是按 §8 errata 重写 schema 再做，还是直接 DEFER 等真实需求触发？ | ___ |
| T3 Evidence-first enforcement | CEO S-F4 + Eng S-F2 | Evidence-first 是补 `verification_emitted` 事件 + lint 后再做，还是 DEFER（避免名实分离）？| ___ |
| T4 §4 砍太快 | CEO C-F4/C-F5/C-F6 + S-F3/S-F6 | Spike / Query registry / Ambiguity / SPIDR PM 版 / Absent=Enabled / 触发式 secure checklist 哪些升级到 P2 触发条件？ | ___ |
| T5 文档自身未关闭 | DX 全部 10 finding | reader map（已加✓）/ §3 banner（已加✓）/ §7.2 重写（本节✓）/ 多套标签正交化（待 v4）/ cross-doc 引用规范（待 v4）| ___ |

#### 步骤 2：选定可立即实施清单（基于步骤 1 决策）

按 §8.5 errata index — **当前 v3 中 7 项可直接做**（无 §8 finding 阻塞）：

| # | 项 | 工作量 | 顺序 |
|---|---|---|---|
| P0-#23 | SKILL size budget lint | 1-2h | 第 1 个做 |
| P0-#2 | GATES.md 4 类归类 | 1h | 第 2 个做 |
| P0-#4 | Completion Marker（agent 契约+lint）| 30min | 第 3 个做 |
| P0-#5 | Artifact 角色分工表 | 1h | 第 4 个做 |
| P1-#6 | Read Injection Scanner（3 步走）| 1-2 天 | 决策清账后做 |
| P1-#10 | `/extract-learnings`（PM 显式触发）| 1 天 | 决策清账后做 |
| P1-#11 | Context Monitor（50%/70%）| 0.5 天 | 决策清账后做 |
| P1-#12 | Subagent 类型白名单 | 30min | 决策清账后做 |

**总计可立即实施 ≈ 1 天**（不含 P1-#6/#10）；含 P1 约 4 天。

#### 步骤 3：dogfood + 触发条件复盘

1. 跑通上面 ✅ 清单后，dogfood 5 个真实 req
2. 复盘 §6 触发条件表，决定 P2 哪些进
3. P2 实施按触发条件 lazy 启动，永不提前

---

**v3 关键变化**：**没有"本周做 P0"了**——所有"开工"都先经过步骤 1 决策清账。原 v2 §7.2 "本周做 P0-代码层 4 项" 已被 §8.2 证伪（Mutation/status-view/Inventory/required_reading 都 BLOCKED 或 NEEDS REVISION）。

### 7.3 验证标准（v3.1 修正：按 D4=A / D5=A+Q1=d / D6=B 同步剔除延后项）

> ⚠️ **v3.1 修正**：v2 验证表混入 Mutation Registry / Inventory drift / status-view blocking / Evidence-first 等已被 D4/D5/D6 决议延后或 DEFER 的项。本表只保留 **Wave 1+2+3 完成后真实可验证的指标**。

**Wave 1+2+3 完成后**（约 4-5 天 CC）的可观测指标：

| 项 | 可观测的方式 | Wave |
|---|---|---|
| 所有 `agents/*.md` 含 `<!-- completion-marker: ... -->` 注释 + 对应 section | ✅ `bash tests/test-agent-files.sh` 通过 | 1 |
| `GATES.md` 存在且覆盖 INVARIANTS.md 60 条 + 4-5 条运行时 gate | ✅ 文件存在 + 人工抽查 | 1 |
| `input-flow.md §9.1` 每个 skill 段含 `❌ 明确不读` 反向列 | 🟡 PM 抽查 + grep `❌ 明确不读` | 1 |
| `cross-skill.md` 含 Subagent 类型白名单第 8 条 | 🟡 PM 抽查 | 1 |
| 所有 PM 视图 SKILL.md 步骤 0 含 `<required_reading>` XML 块 | ✅ `bash tests/test-skill-structure.sh` 通过 | 2 |
| 任何 `Read` 工具读到 injection pattern 弹警告 | 🟡 PM 在 chat 看到 advisory（不阻断）| 3 |
| `/extract-learnings` 仅 PM 显式触发（不自动跑）| 🟡 `INVARIANTS.md` I-RV4 + PM 验证（**非自动化测试**）| 3 |
| `/close-req` 完成后呈交块含 LEARNINGS 推荐 | 🟡 PM 在 chat 看到 | 3 |
| 任何 context 用量 ≥ 50% 收到提醒 | 🟡 PM 在 chat 看到 | 3 |

**Wave 4 完成后**（按合并方案选定再补）：
| `_shared/thinking/` 与 `_shared/anti-patterns/` 单 owner 不重叠 | 🟡 PM 抽查 + grep 互引 | 4 |

**已 DEFER / 延后到代码层 Wave 的项（不在本表）**：
- ~~MUTATIONS.md 登记~~ → §3.0.2 延后到真实实施
- ~~Inventory drift 测试覆盖 5 类 entity~~ → §3.0.4 延后
- ~~`/task-status` 含 blocking reasons~~ → §3.0.3 延后
- ~~SKILL.md 行数 ≤ 400~~ → §3.0.1 单独可提前（4 个已超阈值 skill 有豁免计划）
- ~~`/close-req` 呈交块含 verified/claimed/unverified 分流~~ → §3.5 整节 DEFER（D6=B）

**图例**：✅ = 自动化测试可证；🟡 = 运行时可观测但不可自动证明

---

---

## §8 Autoplan Review Findings (Round 1, 2026-05-16)

> 触发：2026-05-16，PM 显式调用 `/gstack-autoplan`。
> 防膨胀：所有 finding 强制带 PAIN_LINK + EVIDENCE，PAIN_LINK=NONE 且 EVIDENCE=ASSUMED 默认 DEFER。

### §8.1 Phase 1 — CEO 战略 Dual Voice

#### Codex CEO Voice（6 finding）

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 默认决议 |
|---|---|---|---|---|---|
| C-F1 | High | 并行 task `files_modified / depends_on` 应该提到 P1-lite，不能等撞文件再补 | §2 #19 | `README.md:87` v4 已支持并行 + `INVARIANTS.md:217-218` | **待 PM 决** |
| C-F2 | High | P0 顺序错——应先做"评审防膨胀机制落地化"（PAIN_LINK + EVIDENCE + source audit 上升为 P0A），再做 Mutation Registry / Inventory / size lint | §7.1 | `docs/design/modulespec-重写方案.md:150-165` D13 5 轮膨胀实证 | **待 PM 决** |
| C-F3 | Medium | 缺对称防线 "Scope Integrity Contract"——AI 也可能为过 review 偷偷缩 scope 删原始痛点覆盖 | §5（GSD 比 PMAI 强 scope reduction prohibition）| `docs/gsd-借鉴分析.md:135,733` | **待 PM 决** |
| C-F4 | Medium | §4.2 把 Spike 用 `/quick-fix` 覆盖太快——Spike 价值是"先用可逆实验拿证据"，D13 验证脚本本质就是手写 Spike | §4.2 | `docs/design/d13-验证脚本.md:116-123` | **待 PM 决** |
| C-F5 | Medium | §4.1 拒绝 TS 但 Query registry 没具体落地——`scripts/_lib/queries/` Python 版应 P1（Mutation 管写、Query 管读，成对落地）| §4.1 / §5 | `INVARIANTS.md:11-24` 60 条 + ~40 脚本现状 | **待 PM 决** |
| C-F6 | Low | UI/Secure-phase "永不" 太绝对——auth/PII/payment/admin destructive 时应有 5 行 secure checklist | NONE | ASSUMED | **DEFER**（PAIN_LINK=NONE） |

#### Claude Subagent CEO Voice（7 finding）

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 默认决议 |
|---|---|---|---|---|---|
| S-F1 | High | "PM 单人 ≠ 不需要团队机制"——多窗口并行 / 跨会话续接 / AI agent 链交接 = "伪团队"场景，§4/§5 多处"PM 单人不需要"判断需重审 | §4.5 / §5 | `README.md:87` + `RUNTIME.md` 存在的理由 + worktree+events.jsonl 已是团队机制本质 | **待 PM 决** |
| S-F2 | High | v2 把代码层放 P0 是**对 codex 评审的过度反应**——代码层是框架洁癖（让仓库健康），prompt 层才是 PM 看得到的价值（防 AI 假执行 / 偷缩范围）。建议 v3：P0a = prompt 层、P0b = 代码层、叙述上别把代码层叫"核心" | §7.1 | `docs/gsd-借鉴分析.md:174-194,767-783` + memory `feedback_skill_must_actually_invoke` | **待 PM 决** |
| S-F3 | High | Ambiguity 评分（Spec phase）+ SPIDR 拆任务被推到 P2——但 memory 里 `feedback_design_pain_guard` `feedback_task_split_antipatterns` 已经沉淀对应反模式，"频发"已触发 | §4.2 / P2 #20 #22 | memory `feedback_design_pain_guard` + `feedback_task_split_antipatterns` 4 条 | **待 PM 决** |
| S-F4 | Medium | Evidence-first 呈交块**漏了执行端 enforcement**——AI 可机械填表"✅ 已验证：pytest 通过"但根本没跑。需 tool-call audit（events.jsonl + cite event ID/timestamp），否则就是更精致的谎言载体 | §3.5 | memory `feedback_skill_must_actually_invoke` | **待 PM 决** |
| S-F5 | Medium | GSD 是公开 npm 包有强反馈循环，PMAI 反馈只有你一人——"PM 单人不需要 X"可能是早期 anchoring。若未来想开源/分享，§4 全部判断需重审 | §0.1（PMAI 定位）/ §6（dogfood 复盘）| `docs/gsd-借鉴分析.md:663-681,729-740` + `CLAUDE.md` "PM 单人" 定位 | **待 PM 决** |
| S-F6 | Medium | "Absent = Enabled" 被一笔带过，但它是**新手友好性的关键设计**。框架同步 SOP 第 3 次出现"忘了同步开关"时该引入 `pmai.config.json` | §4.4 | `docs/gsd-借鉴分析.md:697-701` + `框架同步-SOP.md` hotfix 阶段 | **待 PM 决** |
| S-F7 | Low | 文档 817 行违反正在引入的 SKILL size budget（警告 400 / 上限 600）——v1→v2 修订只加不减，应反向操作"每加一段问能删哪段" | NONE | ASSUMED | **DEFER**（PAIN_LINK=NONE） |

#### CEO Dual Voice Consensus Table

| 维度 | Codex | Claude subagent | Consensus |
|---|---|---|---|
| 1. P0 排序当前是否对？ | ❌（缺评审防膨胀机制落地） | ❌（代码层放 P0 是过度反应） | **CONFIRMED 错** — 两 voice 都质疑，但建议方向不同（Codex 加 PAIN_LINK 落地；Claude 把 prompt 层提回） |
| 2. PM 单人 premise 是否过窄？ | 部分（F1 主张 files_modified） | ❌（F1 "伪团队"概念） | **CONFIRMED 过窄** — Codex 集中在并行机制；Claude 抽象到"伪团队" |
| 3. §4 是否有"砍太快"的判断？ | F4 Spike / F5 SDK Query registry / F6 UI Secure | F3 Ambiguity / SPIDR / F6 Absent=Enabled | **CONFIRMED 多处** — 两 voice 各指出独立"砍太快"案例 |
| 4. v2 是否完整？ | F2 P0 / F3 Scope Integrity | F4 Evidence-first audit / F7 文档自身膨胀 | **DISAGREE** — 关注点不同，但都指向"v2 还有未覆盖盲点" |
| 5. 6 个月 regret 场景？ | F2 框架自守先做的代价 | F5 PM 单人 anchoring + F6 没集中配置面 | **CONFIRMED 存在** — 两 voice 都识别 |
| 6. 评审 ROI 高于膨胀风险？ | 5 条带 PAIN_LINK + 1 条 DEFER | 6 条带 PAIN_LINK + 1 条 DEFER | **CONFIRMED 高** — §0 痛点锁机制有效，绝大多数 finding 带证据 |

**汇总**：13 finding，11 个带 PAIN_LINK（待 PM 决），2 个 DEFER（C-F6 + S-F7）。CONFIRMED 4/6 维度。

### §8.2 Phase 3 — Eng 实施 Dual Voice

> Eng 视角找的是"v2 落地方案有没有实施 bug"——Codex 和 subagent **都主动读了 scripts/ 实际代码**，质量比 CEO 更高（CEO 是抽象判断，Eng 找到代码层真实问题）。

#### Codex Eng Voice（5 finding，全部带 PAIN_LINK + EVIDENCE，0 DEFER）

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 默认决议 |
|---|---|---|---|---|---|
| C-F1 | High | Mutation Registry 示例**事件契约写反**——文档说 `req-transition.py` 发 `stage_changed` 但代码只写 .req-meta.json；说 `close-task.sh` 只消费 events 但脚本删 events 后又 append `task_closed`。照表落地会固化错误契约，影响 close-task 事件归档和 I-CT7 审计语义 | §3.0.2 / §7.3 | `docs/gsd-借鉴分析.md:273-278` + `scripts/req-transition.py:283-293` + `scripts/close-task.sh:299-306` | **待 PM 决** |
| C-F2 | High | `required_reading` **覆盖范围矛盾**——文档说"所有 PM 视图 SKILL.md 必含"，lint 又说扫所有 SKILL.md，但改动范围只列 6 个 skill；项目实际 21 skill。两种实现都不能同时满足文档和 §7.3 验证标准 | §3.1 / §7.3 | `docs/gsd-借鉴分析.md:19,371-386` | **待 PM 决** |
| C-F3 | Medium | P0-#25 改 `suggest_next_action()` 签名会破坏现有 2 个 renderer（579 / 638 两处都是 `print(next_action)`）；§7.3 又把 `/task-status` 标 🟡 但现有 `tests/test-status-view.sh` 已自动化，应升级到 ✅ | §3.0.3 / §7.3 | `docs/gsd-借鉴分析.md:300-310,808` + `scripts/status-view.py:400-437,579-639` + `tests/test-status-view.sh:115-147` | **待 PM 决** |
| C-F4 | Medium | `questioning-discipline` **抽象边界泄漏**——§2 #9 作为独立 P1 / §3.7 又说归入 `_shared/thinking/` / §3.8 同时新建 `_shared/anti-patterns/questioning.md` / §7.2 仍把 #9 排在 #7/#8 之前。三个入口管同组规则，`<required_reading>` 易重复引用或漂移 | §3.7 / §3.8 / §7.2 | `docs/gsd-借鉴分析.md:202-204,568-574,588-592,789-791` | **待 PM 决** |
| C-F5 | Medium | Inventory drift 方案把 scripts / templates / tests / shared_refs 全手工列入 `INVENTORY.json`，与现有 `tests/run-all.sh` curated suite 冲突——新增测试需双改 inventory + run-all 入口 | §3.0.4 | `docs/gsd-借鉴分析.md:327-348` + `tests/run-all.sh:6-54` | **待 PM 决** |

#### Claude Subagent Eng Voice（5 finding，全部带 PAIN_LINK + EVIDENCE，0 DEFER）

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 默认决议 |
|---|---|---|---|---|---|
| S-F1 | High | §3.0.2 估算"约 12-15 个写盘脚本" **严重低估**——实际 scripts/ 下 ≥ 25 个脚本会写盘（apply-req-doc / audit-task-events / check-branch / cancel-req / create-* / cleanup-pending / finalize-review / publish-to-lark / quick-fix / init-project / install-hooks / build-execution-prompt / derive-structure-templates / inject-structure-segment / classify-failure / run-bg / skill-preamble 等）。lint grep 模式（write_text / git commit / mv）会把 _lib/exec-adapters/test fixture 全部命中，初次接入 CI 红。"clean tree"列与 I-DC1 已有三道防线**双源登记** | §3.0.2 / §3.0.4 | `docs/gsd-借鉴分析.md:263-289,329-357` + `scripts/` 实际文件清单 + `INVARIANTS.md I-DC1` | **待 PM 决** |
| S-F2 | High | §3.5 Evidence-first 4 section 只是 prompt 模板膨胀，**没有执行端 enforcement**——AI 可照填"✅ 已验证: pytest 12 pass"而没真跑（memory `feedback_skill_must_actually_invoke` 已记录此 pattern）。audit-task-events.py 不审 `verified_command_run` 类事件；§3.5 "unverified 不能为空"无对应 lint。**名实分离更危险**——PM 会更容易相信 | §3.5 / §8.1 S-F4 | `skills/task-execute/SKILL.md:434-451` + `INVARIANTS.md:191-192 I-RV1/RV2` + `scripts/audit-task-events.py` | **待 PM 决** |
| S-F3 | Medium | `_shared/thinking/` + `_shared/anti-patterns/` 高度重叠——planning-thinking 的"MECE / Pre-Mortem" 与 anti-patterns/planning 的"AI 偷削范围"是**同一规则正反两面**；questioning-discipline.md 同时在两目录（§3.7 表注 #9 归 thinking，§3.8 又列 questioning.md）。多入口管同组规则会出现"thinking 被 `<required_reading>` 引用但 anti-patterns 没引用"或反过来的漏读 | §3.7 + §3.8 | §3.7 表 5 件套 + §3.8 表 5 件套 + 已有 `skills/_shared/PM-VIEW-RULES.md` 与 `pm-view/` 6 子文件 | **待 PM 决** |
| S-F4 | Medium | §3.0.3 改 `suggest_next_action` 返回 tuple 是**单 active 视角**，但 status-view 已支持多 active req（`render_status` 中 `len(active) > 1` 分支）。改签名不同步两个调用点会输出 tuple repr。示例文案"事件流缺 execution_started（I-CT7 风险）"**与 audit-task-events.py 职责重叠**——这是 close-task 关口的事，status-view 提前 echo 会产生 false-positive blocking | §3.0.3 | `scripts/status-view.py:400-437,583-653` | **待 PM 决** |
| S-F5 | Medium | §7.3 验证表**口径不一致**——P1-#6 Read Injection 已有 fixture+test 但标 🟡 应升 ✅；`/extract-learnings` 仅 PM 显式触发 标 ✅ 但实际靠 I-RV4 + PM 验证（不是自动化测试）。"我写了文档"和"测试可证"被混在一栏 | §3.6 / §7.3 | `docs/gsd-借鉴分析.md:541-554,802-810` | **待 PM 决** |

#### Eng Dual Voice Consensus Table

| 维度 | Codex | Claude subagent | Consensus |
|---|---|---|---|
| 1. Mutation Registry 落地有 bug？ | F1（事件契约写反 + 双源漂移）| F1（写盘脚本数低估 + lint 误伤 + 与 I-DC1 双源）| **CONFIRMED 严重** — 不同角度，但都说"照 §3.0.2 落地即翻车" |
| 2. Evidence-first 缺执行端 enforcement？ | — | F2（无 audit / 无 lint / 名实分离更危险）| **单 voice 但极重要** — 联动 CEO §8.1 S-F4 = 跨 phase 主题（见 §8.4） |
| 3. 抽象泄漏（thinking/anti-patterns/questioning 多入口）？ | F4（4 处入口管同组规则）| F3（thinking 与 anti-patterns 同一规则正反两面）| **CONFIRMED 严重** — 两 voice 完全同方向，建议合并入口 |
| 4. P0-#25 status-view 改动有 ordering bug？ | F3（破坏 2 个 renderer + §7.3 标 🟡 不对）| F4（破坏多 active 渲染 + 与 audit-events 职责重叠）| **CONFIRMED 严重** — 两 voice 都说改签名会破坏现有 renderer，但 subagent 多挖一条职责重叠 |
| 5. Inventory drift 范围错？ | F5（与 run-all curated 冲突）| F1 包含（lint grep 模式误伤）| **CONFIRMED** — 两 voice 都说当前方案过宽 |
| 6. §7.3 验证标准口径乱？ | F3 部分（标 🟡 应升 ✅）| F5（专门列 4 项不一致）| **CONFIRMED** — Subagent 系统化指出，Codex 局部触及 |

**汇总**：10 finding，全部带 PAIN_LINK + EVIDENCE（0 DEFER）。CONFIRMED 5/6 维度。**质量比 CEO 高一档**——Eng 找到的是"代码层真实可执行性 bug"，CEO 找到的是"抽象判断盲点"。Eng F1/F2/F3/F4 不解决，§3 多数 P0 项落地即翻车。

### §8.3 Phase 3.5 — DX/读者体验 Dual Voice

> DX 视角对一份研究文档转向"文档自身可读性 + PM 行动可执行性 + future-self 续接"，不再是工程产品 TTHW。**5/5 维度全 CONFIRMED**——这是三 phase 中 consensus 最强的，揭示的是**文档结构问题**（非内容判断问题）。

#### Codex DX Voice（5 finding）

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 默认决议 |
|---|---|---|---|---|---|
| C-F1 | High | §3 落地方案与 §8 review 严重冲突——§8 是 inline trail 但**没有变成主文 errata**。读者必须 mental diff：到底听 §7，还是听 §8？直接拉高 TTHW | §7 / §8 | `docs/gsd-借鉴分析.md:767-793` + `:855` + `:892-899` | **待 PM 决** |
| C-F2 | Medium | 870+ 行文档**无 TOC / reader map / Start here 层**。§2/§3/§6/§7/§8 各自有价值但读者需自己判断该跳哪里（战略 vs 实施 vs 触发 vs 待决 = 四种问题）| §0 后 | `docs/gsd-借鉴分析.md:1-43,170-222,226-660,744-761,765-813,821-899` | **待 PM 决** |
| C-F3 | High | §7.2 "本周做 P0" 但**第一步其实是决策清账，不是直接实现**——§8 有 11+10 待 PM 决，PM 照 §7.2 开工会撞上 §8 阻塞项 | §7.2 / §8 | `docs/gsd-借鉴分析.md:789-791` + `:832-848` + `:872-886` | **待 PM 决** |
| C-F4 | Medium | cross-doc 引用三类来源（PMAI 本仓 / GSD 外仓 / MEMORY key）**没统一引用规范**，读者不知道某短路径相对哪个 root | §3 / §5 多处 | `docs/gsd-借鉴分析.md:51,61-107,844-848` | **待 PM 决** |
| C-F5 | Medium | **多套标签混用没正交化**：P0-代码层 / P0-补充 / P1 / P2 / DEFER / 待 PM 决 / CONFIRMED / ✅🟡 同时叠加在同一读者路径。一个条目可能同时是 P0 + ✅ + 待 PM 决 + CONFIRMED 有问题 | §2 / §7 / §8 | `docs/gsd-借鉴分析.md:176-209,801-813,832-899` | **待 PM 决** |

#### Claude Subagent DX Voice（5 finding）

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 默认决议 |
|---|---|---|---|---|---|
| S-F1 | High | §3 落地方案与 §8 review **严重冲突且 §3 原文无修正标记**——读者按 §7.2 执行会照 §3 错误契约落地，再读 §8 才知道是错的。"等于让每个读者重复一次 review"。future-self 半年后接续几乎必然踩坑 | §3.0.2 / §3.0.3 / §3.1 / §8.2 | `docs/gsd-借鉴分析.md:273-278,300-310,371-386` + §8.2 已 CONFIRM 但 §3 未加 banner | **待 PM 决** |
| S-F2 | High | 900 行**无 TOC**——"PM 想知道 P0-#24 当前落地状态"需要 6 跳起步（§2 一句话 → §3.0.2 方案 → §5 PMAI 弱项 → §7.1 优先级 → §8.2 review bug → §7.3 可观测）| 整篇 / §0 后 | `docs/gsd-借鉴分析.md:1-11` 无目录 + 多处 §X 跨引用 | **待 PM 决** |
| S-F3 | High | §7.2「建议顺序」与 §8 review **完全脱节**——§7.2 是"plan 视图"，§8 是"review 视图"，无 reconcile 步骤。PM 看 §7.2 就动手 = 没看 §8；看了 §8 = 不知道哪些 finding 已 PM 拍板 | §7.2 + §8 | `docs/gsd-借鉴分析.md:785-793` + `:821-899` | **待 PM 决** |
| S-F4 | Medium | 多层优先级标签（P0-代码层 / P0-补充 / P1 / P1-lite / P2 / DEFER）**缺图例和决策树**。"为何 P1-#27 进核心 5 件而其他 P1 没进" 选取标准不明 | §2 / §7.1 | `docs/gsd-借鉴分析.md:176-223,767-783` + §8.1 C-F1 提出 P1-lite + §8.1 S-F2 提出 P0a/P0b | **待 PM 决** |
| S-F5 | Medium | cross-doc 引用模糊**违反作者自定 EVIDENCE 标准**——§8 finding 全带 `scripts/req-transition.py:283-293` 精度，§3 落地方案引现有文件清一色只给路径无行号 | §3 / §8 标准不一 | `docs/gsd-借鉴分析.md:300,652` + 对比 §8 双 voice 全带 file:line | **待 PM 决** |

#### DX Dual Voice Consensus Table

| 维度 | Codex | Subagent | Consensus |
|---|---|---|---|
| 1. §3 与 §8 没有 reconcile？ | F1（§8 不是 errata 要 mental diff）| F1（§3 原文无 banner，每个读者重复 review）| **CONFIRMED 严重** — 完全同方向 |
| 2. 缺 TOC / reader map？ | F2（10 行 reader map）| F2（30 行 TOC 含 anchor）| **CONFIRMED** — 都说要补 |
| 3. §7.2 vs §8 决策路径脱节？ | F3（启动撞 §8 待决项）| F3（§7.2 加门或标 STALE）| **CONFIRMED 严重** — 完全同方向 |
| 4. 多套优先级标签缺图例？ | F5（正交化拆四字段）| F4（图例 + 选取标准明写）| **CONFIRMED** — 都说要清理 |
| 5. cross-doc 引用规范？ | F4（PMAI/GSD/MEMORY 三前缀）| F5（§3 违反自己 §8 EVIDENCE 标准）| **CONFIRMED 严重** — 不同方向同一痛点 |

**汇总**：10 finding，全部带 PAIN_LINK + EVIDENCE（0 DEFER）。**CONFIRMED 5/5 维度（三 phase 中最强 consensus）**。DX 揭示的是**文档自身结构问题**（非内容判断）——这意味着：即使 CEO/Eng 提的所有 finding 都不动，光是 DX 提的 reconcile + TOC + decision path 三件事不解决，**文档就处于"未关闭 PR"状态，PM 半年后接续会踩坑**。

### §8.4 Cross-Phase Themes（横跨 2+ phase 的高信号问题）

> 当同一问题被独立的 CEO / Eng / DX 三个角度各自挖出，信号强度远高于单 phase。下表是从 33 finding 提炼的 5 大跨 phase 主题：

| 主题 | 出现 phase | 关键 finding | 行动方向 |
|---|---|---|---|
| **T1：P0 排序错** | CEO + Eng + DX（间接） | CEO C-F2/S-F2（应先做评审防膨胀机制） + Eng C-F3/S-F4（status-view 改签名破坏现有 renderer） + DX C-F3/S-F3（§7.2 启动撞 §8 待决项） | **MUST**：v3 重排，把 prompt 层（评审防膨胀机制）+ §8 待决项决策放在代码层之前 |
| **T2：§3 落地方案有真实代码 bug** | Eng + DX | Eng C-F1/S-F1（Mutation Registry 事件契约写反 + 脚本数低估）+ Eng C-F2（required_reading 范围矛盾）+ Eng C-F3/S-F4（status-view 改签名）+ DX C-F1/S-F1（§3 与 §8 冲突）| **MUST**：v3 重写 §3.0.2 / §3.0.3 / §3.1，**实施前 grep 真实代码再写表**，行号精度对齐 §8 EVIDENCE 标准 |
| **T3：Evidence-first 名实分离风险** | CEO + Eng | CEO S-F4（无 tool-call audit 是更精致谎言载体）+ Eng S-F2（无 audit / 无 lint / 名实分离更危险）| **MUST**：v3 给 §3.5 配 `verification_emitted` 事件 + lint，否则不写 Evidence-first 章节（不引入更精致的伪执行渠道）|
| **T4：§4 多处"不借鉴"判断砍太快** | CEO 内部多 finding | CEO C-F4（Spike）+ C-F5（Query registry）+ C-F6（UI/Secure 永不太绝对）+ S-F3（Ambiguity/SPIDR 已触发）+ S-F6（Absent=Enabled）| **SHOULD**：v3 重审 §4，把以下条目从"永不借"改成 P2 触发条件：Query registry / Ambiguity 评分（轻量版）/ SPIDR PM 版 / Absent=Enabled / 触发式 secure checklist。Spike → 轻量 `exploration` 模式 |
| **T5：文档自身结构未关闭** | DX 内部完全 confirm | DX C-F1/S-F1（§3 与 §8 没 reconcile）+ C-F2/S-F2（无 TOC）+ C-F3/S-F3（§7.2 vs §8 决策脱节）+ C-F4/S-F4（多套标签未正交化）+ C-F5/S-F5（cross-doc 引用规范）| **MUST**：v3 加 §0.4 reader map + §3 子节加 review 状态 banner + §7.2 重写为"先决策清账 → 再实施"3 步队列 + 正交化优先级/决策/证据/验证 4 字段 |

**主题强度**：T1/T2/T5 **跨 phase 三重确认** → 不可绕过；T3 跨 CEO+Eng → 强；T4 单 CEO 内部多 finding → 中-强。

### §8.5 Errata Pointer Index（缓解 DX T5 "§3 vs §8 未 reconcile"）

> 直到 v3 写完前，PM 或 future-self 读 §3 落地方案时**必须先查这张表**，看相关 §3.x 是否已被 §8 finding 命中。

| §3 段 | 状态 | 被哪些 finding 命中 | 阻塞建议 |
|---|---|---|---|
| §3.0.1（SKILL size budget lint） | ✅ 可实施 | 无 critical finding | 可直接做（按 D4=A 仍延后到代码层 Wave，除非单独提前）|
| §3.0.2（Mutation Registry） | ⛔ BLOCKED + 🕓 延后 | §8.2 Codex-F1 + Subagent-F1 + **v3.1 Q1=d 决议等真实实施时再写** | schema 重写跟实施一起做更准 |
| §3.0.3（task-status blocking） | ⚠️ NEEDS REVISION + 🕓 延后 | §8.2 Codex-F3 + Subagent-F4 + v3.1 Q1=d | 同上 |
| §3.0.4（Inventory drift） | ⚠️ NEEDS REVISION + 🕓 延后 | §8.2 Codex-F5 + Subagent-F1 + v3.1 Q1=d | 同上 |
| §3.1（required_reading） | ⚠️ NEEDS REVISION | §8.2 Codex-F2 + **v3.1 Finding-5（Wave 1→2 依赖描述）** | 真实依赖 = §3.4 选项 a 落地后把 §9.1 表"显式化"为 XML，非"重新发明 Artifact 表" |
| §3.2（GATES.md） | ✅ 可实施（v3.1 工作量 1h→1.5-2h）| **v3.1 Finding-3**：60 条 I-* + 4-5 条运行时 gate，11 类前缀，工作量低估 50% | 可直接做但留 buffer |
| §3.3（Completion Marker） | ✅ 可实施（v3.1 **方案重写**）| **v3.1 Finding-1**：与 `agents/analysis-reviewer.md:78-119` 已有契约冲突 | 不引入 GSD marker；改对齐已有 `**总体判断**` + `## 给主线 AI 的下一步建议` |
| §3.4（Artifact 角色分工表） | ✅ 可实施（v3.1 **默认选项 a**）| **v3.1 Finding-2**：与 `input-flow.md §9.1` 重叠 | 选 a 在 §9.1 加"❌ 明确不读"列，避免双源 |
| §3.5（Evidence-first 呈交块） | ⛔ BLOCKED + 🚫 DEFER | §8.1 S-F4 + §8.2 S-F2 + **§8.8 D6=B 整节 DEFER** | 不实施；§3.5 内容作为备忘留存 |
| §3.6（Read Injection Scanner） | ✅ 可实施 | 仅 §8.2 S-F5 提 §7.3 应升 ✅ | 可直接做 |
| §3.7（_shared/thinking/） | ⚠️ NEEDS REVISION | §8.2 Codex-F4 + Subagent-F3（抽象边界泄漏，与 §3.8 重叠）| Wave 4：合并或唯一 owner |
| §3.8（_shared/anti-patterns/） | ⚠️ NEEDS REVISION | 同上 | 同上 |
| §3.9（`/extract-learnings`） | ✅ 可实施 | 仅 §8.2 S-F5 提 §7.3 标 🟡 而非 ✅ | 可直接做 |
| §3.10（Context Monitor） | ✅ 可实施 | 无 finding | 可直接做 |
| §3.11（Subagent 类型白名单） | ✅ 可实施（v3.1 anti-pattern 延后 Wave 4）| **v3.1 Finding-4**：`_shared/anti-patterns/` 目录不存在 | cross-skill.md 加约束 + TODO 注释，Wave 4 补 anti-pattern |

**汇总（v3.1 修订）**：15 个 §3.x 子节中 —
- **7 个 ✅ 可立即开工**（§3.0.1 / §3.2 / §3.3 / §3.4 / §3.6 / §3.9 / §3.10 / §3.11）—— 注：§3.0.1 按 D4=A 仍延后到代码层 Wave
- **3 个 🕓 延后到代码层 Wave**（§3.0.2 / §3.0.3 / §3.0.4，按 Q1=d）
- **2 个 ⚠️ NEEDS REVISION 等 Wave 4 决策**（§3.7 / §3.8）
- **1 个 ⚠️ Wave 2 依赖更新**（§3.1）
- **1 个 🚫 DEFER**（§3.5）

**v3 原表 bug**：§8.5 错位标 §3.9=questioning / §3.10=extract / §3.11=Context / §3.12=Subagent，实际编号 §3.9=extract / §3.10=Context / §3.11=Subagent（无 §3.12）。v3.1 已修复。

### §8.6 Decision Audit Trail（auto-decided 部分）

> Autoplan 6 决策原则只 auto-decide 了 3 个 DEFER finding（PAIN_LINK=NONE + EVIDENCE=ASSUMED）。其余 28 个 PAIN_LINK finding 全部归为 **User Challenge**（反驳作者 v2 已做的判断），按 autoplan 协议**不 auto-decide**，全部 surface 到 PM。

| # | Finding | 决策 | Principle | 理由 |
|---|---|---|---|---|
| 1 | CEO Codex F6（UI/Secure 永不太绝对）| **DEFER** | §0 痛点锁 + PAIN_LINK=NONE | 无具体证据，留作 §4 触发条件参考 |
| 2 | CEO Subagent F7（文档 817 行违反 SKILL size budget）| **DEFER** | §0 痛点锁 + PAIN_LINK=NONE | 自指悖论（文档自身评论文档大小），可在 v3 优化时顺手处理 |
| 3 | 无第三条（其他 DEFER 已在 §8.1-§8.3 标注）| - | - | - |

**待 PM 决策的 finding**：28 条（CEO 11 + Eng 10 + DX 7 实质待决，DX 还有 3 条已纳入 errata index）。

### §8.7 v3 修订完成签名（2026-05-16）

**已在 v3 落地（缓解 T1/T2/T5 三 MUST 主题）**：

| 改动 | 命中 finding | 状态 |
|---|---|---|
| 顶部加 v3 changelog + §0.4 Reader Map | DX T5 C-F2/S-F2 缺 TOC | ✅ |
| §3.0.2 加 ⛔ BLOCKED banner（Mutation Registry）| Eng T2 C-F1/S-F1 | ✅ |
| §3.0.3 加 ⚠️ NEEDS REVISION banner（task-status）| Eng T2 C-F3/S-F4 | ✅ |
| §3.0.4 加 ⚠️ NEEDS REVISION banner（Inventory drift）| Eng T2 C-F5/S-F1 | ✅ |
| §3.1 加 ⚠️ NEEDS REVISION banner（required_reading 覆盖矛盾）| Eng T2 C-F2 | ✅ |
| §3.5 加 ⛔ BLOCKED banner（Evidence-first 缺 enforcement）| CEO T3 S-F4 + Eng T3 S-F2 | ✅ |
| §3.7/§3.8 加 ⚠️ NEEDS REVISION banner（抽象重叠）| Eng T2 C-F4/S-F3 | ✅ |
| §7.2 重写为"3 步队列：先决策清账 → 再实施"| DX T5 C-F3/S-F3 + T1 跨 phase | ✅ |

**v3 未处理（延后到 PM 决策具体 finding 后再做）**：

| 未做 | 原因 | 处理方式 |
|---|---|---|
| §3.0.2 Mutation Registry schema 重写 | 需先 grep 真实写盘脚本清单（25+ 个），不在 v3 范围 | PM 在 §7.2 步骤 1 答完 T2 决策后实施 |
| §3.5 Evidence-first 三件套（verification_emitted 事件 + lint + 呈交块 lint）| 需先做 events 契约扩展 | PM 答完 T3 决策后实施 |
| §2 矩阵正交化 4 字段（Priority/Decision/Evidence/Verification）| 涉及 §2 表结构重写 | v4 处理 |
| cross-doc 引用规范（PMAI:/GSD:/MEMORY: 前缀）| 涉及全文引用扫描 | v4 处理 |
| T4 §4 砍太快条目重审 | SHOULD 不是 MUST，需 PM 决策每条是否升级到 P2 | PM 在 §7.2 步骤 1 答完 T4 决策后处理 |

**v3 净改动**：约 240 行新增（reader map 25 行 + §8.1-§8.7 trail 215 行）+ 7 个 banner（约 50 行）+ §7.2 重写（约 50 行）= 文档从 817 行（v2）→ ~1150 行（v3）。

**autoplan workflow 状态**：DONE_WITH_CONCERNS
- 完成：Phase 1 CEO（13 finding）/ Phase 3 Eng（10 finding）/ Phase 3.5 DX（10 finding）/ Phase 4 Final Gate（PM 选 A revise → 已落 v3）
- 跳过：Phase 2 Design（UI scope <2 阈值）
- 后续需 PM 做：步骤 1 决策清账（5 主题 × 一行决议）→ 步骤 2 按 §8.5 errata index 选 7 项可直接做的开工 → 步骤 3 dogfood 5 req 复盘 §6

---

### §8.8 PM 决策清账（2026-05-16，§7.2 步骤 1）

按 §7.2 v3 重写的 3 步队列，PM 在 autoplan 完成后做的 5 主题决策（D4-D7 + T5 已 v3 落地）：

| # | 主题 | PM 决策 | 影响 | 后续动作 |
|---|---|---|---|---|
| **D4 T1** | P0 排序错（跨 3 phase 三重确认）| **A：prompt 层先做** | §2 矩阵需重排：代码层 P0 → DEFERRED / SCHEMA-READY；prompt 层 P0/P1 上升为执行主线 | 待排期 |
| **D5 T2** | §3 NEEDS REVISION/BLOCKED 4 项怎么处理 | **A：按 errata 重写 schema 再做**（4 项全改） | §3.0.2 Mutation Registry / §3.0.3 task-status / §3.0.4 Inventory / §3.1 required_reading 都要按 §8 errata 重写 schema，但 T1=A 决定不立即实施——**schema 重写 = 为未来实施准备** | 待排期（1.5 天 CC，含 grep 25+ 真实写盘脚本）|
| **D6 T3** | Evidence-first 呈交块是否实施 | **B：DEFER 全部** | §3.5 整节不实施。理由：CEO+Eng 警告"无 enforcement 是更精致谎言载体"；PM 现有 task-execute 步骤 11 呈交块 + recommended review 已足够 | §3.5 标 DEFER（细节待定：删除 vs 备忘留存）|
| **D7 T4** | §4 哪些"永不借"升级到 P2 | **只加 2）Query registry**（不选 1/3/4）| §2 P2 列表新增 1 项 + §6 触发条件表新增 1 行。其他 3 项保持"永不借"——1) Spike (quick-fix 已覆盖) / 3) Ambiguity+SPIDR (analysis-reviewer + memory `feedback_task_split_antipatterns` 已覆盖) / 4) Absent=Enabled (PM 现诉求 0 次) | §2 / §6 增量更新 |
| **T5** | 文档自身未关闭（DX 5 维度全 CONFIRMED）| **已在 v3 落地** | §0.4 Reader Map + §3 errata banner + §7.2 重写 3 步队列 | 已完成 |

**关键决策一致性**：
- D4=A + D5=A 一致——"代码层后做"+"为代码层后做准备好 schema"
- D6=B 跟 PM memory `feedback_skill_must_actually_invoke`（skill 必须实际调用不能凭记忆模拟）**完全对齐**——拒绝引入更精致的伪执行渠道
- D7 修订（不选 3）跟 PM 实地认知一致——"3 跟 analysis-reviewer 重叠 80%"是 PM 自己识别（autoplan 主线 AI 缺少这个上下文才会建议）

**未在 v3 落地的影响**（已在下方 Q1-Q5 细节决策中处理）：
- ~~§2 矩阵按 T1=A 重排~~ → Q5=b 加 banner（已落 §2 顶部）
- §3.0.2 / §3.0.3 / §3.0.4 / §3.1 schema 重写 → Q1=d 延后到真实实施时再做
- ~~§3.5 DEFER 整节如何处理~~ → Q2=b 标 DEFER 备忘留存（已改 §3.5）
- ~~§2 P2 + §6 触发条件加 Query registry 一条~~ → 已落 §2 #28 + §6 表

#### Q1-Q5 细节决策（PM 按推荐全选，2026-05-16）

| # | 问题 | PM 选择 | 落地动作 |
|---|---|---|---|
| **Q1** | D5 schema 重写工作量何时排期 | **d) 等真实实施时再写** | schema 提前写≠提前用；T1=A 决定代码层后做，schema 重写跟实施一起做更准 |
| **Q2** | D6 后 §3.5 整节怎么处理 | **b) 标 DEFER 备忘留存** | §3.5 顶部加 🚫 DEFER banner + 回头看条件；原内容作为备忘保留（决策痕迹有价值） |
| **Q3** | prompt 层多个项执行顺序 | **a) AI 排好序 PM 审** | 见下方 Wave 排序方案 |
| **Q4** | Query registry 触发条件 | **b) 新脚本读 state 时第 3 次出现重复 parse 逻辑** | 比"复制 task_parser"更精确，包含读 .req-meta.json / events.jsonl / worktree 任意 state 来源 |
| **Q5** | §2 矩阵是否按 T1=A 重排 | **b) 不重排只加 banner 提示** | §2 顶部加 ⚠️ banner 指向 §8.8 + Wave 排序；避免连锁引用变化 |

#### Q3 prompt 层 Wave 排序方案（PM 待审）

按 dependency + 工作量 + ROI 排成 4 个 Wave：

**Wave 1：纯文档基础（v3.1 重估 3.5-4.5h）—— 不依赖任何已有改动**

> 🟡 **v3.1 修订**：grep 现状后落 5 finding（详见 §3.2/§3.3/§3.4/§3.11 顶部 banner + §8.5 errata index）。原 v3 估 3-4h 偏乐观，主要是 GATES.md 工作量被低估 + §3.3/§3.4 实施方案需重写。

| 顺序 | 项 | v3 估时 | v3.1 估时 | 备注 |
|---|---|---|---|---|
| 1 | P0-#4 Completion Marker | 30min | 30min | **方案重写**：对齐 `agents/analysis-reviewer.md` 已有契约，不引入 GSD `## REVIEW COMPLETE`（详 §3.3 banner）|
| 2 | P0-#2 GATES.md 4 类归类 | 1h | **1.5-2h** | 60 条 I-* + 4-5 条运行时 gate；11 类前缀（详 §3.2 banner）|
| 3 | P0-#5 Artifact 表 | 1h | 1h | **默认选项 a**：在 §9.1 现有表加"❌ 明确不读"列，避免与 input-flow.md 双源（详 §3.4 banner）|
| 4 | P1-#12 Subagent 类型白名单 | 30min | 30min | cross-skill.md 加第 8 条 + TODO 注释；anti-pattern 配套延后 Wave 4（详 §3.11 banner）|

**Wave 1.5：skill_structure.yml manifest 设计（autoplan round 2 新增，2-3h）—— Wave 2 真正 prereq**

> 🔍 **autoplan round 2 发现的 SPOF**：v3.1 §3.1 banner 写"加 `skill_structure.yml` manifest 限定 lint 范围"，但 grep 验证：
> - `find . -name 'skill_structure.yml'` → 无输出
> - `scripts/lint-skill-structure.py` → missing
> - `tests/test-skill-structure.sh` → missing
>
> manifest 完全不存在，又是 Wave 2 lint 实施的硬依赖。**不能合并进 Wave 2 的 0.5 天估时**——manifest 设计本身要决定：哪些 skill 标 `pm_view`、哪些标 `requires_required_reading`、`requires_read_echo` 阈值如何定。设计错 = Wave 2 lint 误伤或漏扫。

| 顺序 | 项 | 工作量 | 备注 |
|---|---|---|---|
| 4.5 | `skill_structure.yml` manifest 设计 | 2-3h | 列出 20 skill 的分类：`pm_view: bool` / `requires_required_reading: bool` / `requires_read_echo: bool` / `risk_level: high/normal`；PM 一句话确认分类是否对（首版从 `find skills -maxdepth 2 -name SKILL.md` 生成，不手填）|

**Wave 2：required_reading（半天）—— 依赖 Wave 1 #3 选项 a + Wave 1.5 manifest 落地**

| 顺序 | 项 | 工作量 | 备注 |
|---|---|---|---|
| 5 | P0-#1 `<required_reading>` XML 块 | 0.5 天 | **v3.1 依赖修正 + autoplan round 2 修正**：依赖 Wave 1 #3（§9.1 加 ❌ 列）+ Wave 1.5（manifest）双前置；本步把现有"必读输入"显式化为 XML（不是重新发明 Artifact 表），lint 按 manifest 执行（按 §8.2 Codex-F2 errata）|

**Wave 3：独立 hook + 命令（2-3 天）—— 不依赖前面 Wave**

| 顺序 | 项 | 工作量 | 备注 |
|---|---|---|---|
| 6 | P1-#11 Context Monitor hook（50%/70% 警告）| 0.5 天 | 独立 hook |
| 7 | P1-#10 `/extract-learnings` 命令 + LEARNINGS.md | 1 天 | 独立 skill；按 D6 决议非 auto-trigger，PM 显式调 |
| 8 | P1-#6 Read Injection Scanner（3 步走：script + fixture + Claude hook adapter）| 1-2 天 | 独立 hook，最重 |

**Wave 4：思维系列合并（3-4 天）—— 需先决策合并形态**

| 顺序 | 项 | 工作量 | 备注 |
|---|---|---|---|
| 9 | P1-#7/#8/#9 thinking + anti-patterns + questioning 合并 | 3-4 天 | **需先解决 §3.7/§3.8 NEEDS REVISION**（按 §8.2 Codex-F4/Subagent-F3 二选一：合并到 5 个生命周期文件 vs 保留两目录 + owner 唯一化）|

**总工作量**：约 6-8 天 CC（**autoplan round 2 修正**：Wave 1 = 3.5-4.5h；**Wave 1.5 manifest = 2-3h（新增 SPOF prereq）**；Wave 1+1.5+2 ≈ 1.5 天可启动；**Wave 3/4 估时不再承诺**——按 codex F1 建议等 Wave 1+2 落地后重估）

**关键依赖（autoplan round 2 修正）**：
- Wave 2 (P0-#1) **真实依赖** = Wave 1 #3 选项 a + **Wave 1.5 manifest 双前置**
- Wave 4 (P1-#7/#8/#9) 依赖**先做架构决策**（5 件套合并方案）
- Wave 3 各项独立，可并行或穿插 Wave 1/1.5/2
- **承诺边界**：只承诺 Wave 1+1.5+2 估时（共 ~1.5 天）；Wave 3/4 复盘后重估

---

## §9 v3.1 修订 changelog（2026-05-16 PM 审核 + grep 现状）

**触发**：PM 在 Wave 1 开工前要求审核 v3 方案。AI 按 memory `feedback_autoplan_preread_existing_skill` 教训，先 grep `agents/` / `skills/_shared/pm-view/` / `INVARIANTS.md` 现状，再对照 v3 落地方案逐项审。

**5 个 finding（带 PAIN_LINK + EVIDENCE）**：

| # | Severity | Finding | EVIDENCE | 落地 |
|---|---|---|---|---|
| F1 | 🔴 HIGH | §3.3 与 `agents/analysis-reviewer.md:78-119` 已有输出契约冲突 | grep agents/ 现状 + req-analysis SKILL.md:152,204 已强制贴原文 | §3.3 整段重写，不引入 GSD marker |
| F2 | 🟠 MED | §3.4 与 `input-flow.md §9.1` 双源 | input-flow.md:7-9 已是单一权威源 + 文件 386 行接近 size 警告 | §3.4 默认选项 a：在 §9.1 加"❌ 明确不读"列 |
| F3 | 🟠 MED | §3.2 GATES.md 工作量低估 50% | INVARIANTS.md 11 类前缀 + 不止 60 条；含非 I-* 运行时 gate | §3.2 工作量 1h → 1.5-2h |
| F4 | 🟡 LOW | §3.11 配套 anti-pattern 文件不存在 | `_shared/anti-patterns/` 目录未建（Wave 4 才建）| §3.11 配套延后 + cross-skill.md 加 TODO |
| F5 | 🟠 MED | Wave 1→2 依赖描述不准确 | §9.1 已是 required_reading 等价物 | §8.8 Wave 1→2 依赖重写 |

**"已决未同步"3 处补修**：

| # | 决议 | 矛盾位置 | 落地 |
|---|---|---|---|
| 1 | D4=A（prompt 层先做）+ D6=B（Evidence DEFER）| §7.1 "v2 核心 5 件" 含 4 代码层 + 1 Evidence | §7.1 重写为 v3.1 核心清单（Wave 1+2 5 件）|
| 2 | Q1=d（schema 等真实实施再写）| §7.3 验证表含 MUTATIONS / Inventory drift / status-view blocking 标 ✅ | §7.3 重写为 Wave 1+2+3 完成后可观测项 |
| 3 | Q1=d | §3.0.2 工作量"半天"假设立即做 | §3.0.2 工作量改为"延后实施" |

**附带修复**：§8.5 errata index 表 §3.9/§3.10/§3.11/§3.12 编号错位（v3 bug，实际 §3.9=extract / §3.10=Context / §3.11=Subagent，无 §3.12）。

**v3.1 净改动**：约 100 行新增（10 处 Edit）+ §9 changelog（本节 ≈ 40 行）。

---

**End of GSD 借鉴分析 v3.1**

---

## §10 痛点驱动借鉴对照（v3.2，autoplan round 2 后）

> **本节是 v3.2 最新权威结论**。前 §1-§9 是按"GSD 6 维度全面分析"组织的研究素材，方向是伪需求驱动；本节按 PM 真痛点（消费仓踩坑修复 vs GSD 原始设计）重新对齐。
>
> **frame 转变**：
> - 之前：GSD 有 X，看 PMAI 能不能借 → 28 项矩阵 + Wave 1-4
> - 现在：PMAI 踩了 Y 坑修了补丁，看 GSD 在类似场景的原始设计是否更优 → 5 个具体对照

### §10.1 起源

PM 真需求（原话）："我目前在消费仓中遇到的很多问题，都是因为我的框架的一些设计不合理，踩坑了……我们解决这些坑的方式，可能有两种情况，第一是没有找到最好的方案，第二是我们只修了一个小问题，但是背后其实是整个框架设计有问题。"

→ **不是"全面研究 GSD"，而是"我的补丁治标还是治本，GSD 设计层有没有更优解"**。

### §10.2 5 个真痛点 vs 文档已记录借鉴 — 速查表

| # | 真痛点（已修 commit）| 文档对应借鉴项（§2 / §3）| 覆盖度 | 状态 |
|---|---|---|---|---|
| 1 | D13 modulespec 重写 / autoplan review 把 2h 放大到 30h+<br/>(commits: b85e35c → 17fa007) | §2 P1-#7 thinking models（Wave 4）+ §5 承认 GSD 有 `scope-reduction-prohibition` | ⚠️ 方向反 | 🟢 **不需借鉴** — PMAI §0 痛点锁已自解 |
| 2 | I-DC1 文档落盘 3 道防线 / task-005 文案偏差事故<br/>(commit: 3c27a33) | **无**（§1.1 / §5 提到 STATE.md 单一权威源思想但**未列入借鉴矩阵**）| ❌ 遗漏 | 🔴 **真漏 — 应补借鉴** |
| 3 | publish-to-lark 4 连 fix / lark-cli 1.0.27 升级<br/>(commits: 3474d64, 1dc080a, 2896e2c, 3b91ced) | §4.1 明确拒绝 SDK 双实现 + §2 P0-#24 mutation registry（对照不严格）| ❌ 无替代 | 🔴 **真漏 — 应补借鉴** |
| 4 | close-task / close-req 对称化重构<br/>(commits: 9e9316f + e5a56c0 + 133c32d) | §2 P0-#1 `<required_reading>` XML 块（GSD 5 段骨架借了 1 段）| 🟡 借了但太窄 | 🟡 **扩展借鉴范围** |
| 5 | PM-VIEW-RULES + 3 个超大 SKILL.md 拆 references<br/>(commit: ea2dc82) | §2 P0-#23 SKILL size budget lint（Wave 代码层延后）| ✅ 对得上 | ✅ **保持现状** |

**覆盖统计**：
- ✅ 1 项对得上（#5）
- 🟡 1 项借了但太窄（#4）
- 🔴 2 项真漏，文档完全没对应借鉴方案（#2 / #3）
- 🟢 1 项不需借鉴（#1，PMAI 自解）

**关键洞察**：文档审了 2 轮 + Wave 1-4 排好，**但真正能治本的 2 个借鉴方向（#2 STATE.md 思想 / #3 外部 API adapter 层）完全不在 Wave 任何位置**。Wave 1-4 全是"GSD 看着重要"的边角料（GATES.md 分类、Subagent 白名单、anti-pattern 文件），不是 PMAI 最痛的方向。

### §10.3 详细判断（actionable 3 项）

> ⚠️ **STALE 警告**：本节为 v3.2 推导历史，**最终结论以 §10.6 RV1 + §10.7 #8 为准**。下文 #2 末尾"如果借鉴成立，可以砍掉 I-DC1 / I-AD5 三道防线"已在 v3.4 RV1 被推翻——mutation 入口只解 state 字段一致性，**不解 I-DC1 markdown 落盘问题**，三道防线必须保留。本节保留仅为审计推导链；落地前请直接看 §10.7。

#### 🔴 #2 STATE.md 单一权威源思想（真漏，应借鉴）

**痛点**：`scripts/req-transition.py` + `task-transition.py` + `close-task.sh` 等都按"扫文件系统 + 多步写"实现状态变更，**没有 atomic CAS**。task-005 文案偏差事故的根因正是"task 文档/状态/事件流"三者不是原子写。

**现修方式**：I-DC1 + I-AD5 + 三道防线（task-spec 12.6 / task-confirm fork / req-transition），每道防线 grep + auto-commit 兜底——**3 层 invariant 防一个根因**。

**GSD 设计**（grep 现状验证）：
- 唯一 state 文件 `STATE.md`
- 写盘走 SDK CLI（禁止直接 Write/Edit STATE.md，反模式 #15）
- 文件锁 + atomic CAS + 4 层读取优先级
- 任何 mutation 必须经 mutation registry 登记

**根因对比**：
- PMAI：state 分散在 .req-meta.json / task.md 状态字段 / events.jsonl / worktree 物理状态，**任意两个之间都可能 drift**
- GSD：state 集中 STATE.md，原子写从根上不存在 drift

**借鉴建议**（轻量版，不是抄 STATE.md 文件本身）：
- 不引入新 STATE.md 文件（PMAI 现有 4 处 state 改造成本高）
- **借鉴的是"集中 mutation 入口 + 原子写"思想** → 把所有 state mutation 走 `_lib/mutation_lib.py`（已部分存在），强制原子 commit + audit hook
- 工作量预估：1-2 天（合并现有 transition 脚本的 mutation 路径）
- ~~如果借鉴成立，可以**砍掉 I-DC1 / I-AD5 三道防线**（从设计层规避）~~ **❌ v3.4 RV1 已推翻**：mutation 入口只解 state 字段一致性（task 状态/events.jsonl drift），**不解 I-DC1 markdown 文档落盘问题**（后者是 git working tree + 编辑时机问题）。**I-DC1 / I-AD5 三道防线必须保留**。详见 §10.6 RV1 + §10.7 #8 "🔴 关键警告"。

#### 🔴 #3 外部 API adapter 层（真漏，应借鉴）

**痛点**：lark-cli 1.0.27 升级一次 → publish-to-lark 4 个连环 fix。每升一次都要 patch 多个调用点。

**现修方式**：每个调用点单独 fix。无 adapter 层。

**GSD 设计**（grep 现状验证）：
- GSD 用 SDK 双实现（TS + CJS）—— §4.1 PMAI 已明确拒绝（理由：包发布成本太高）
- 但 GSD ADR-3524 `lint-shared-module-handsync.cjs` 思想可借：**单一外部依赖入口 + 接口契约 lint**

**借鉴建议**（轻量版，不抄双实现）：
- 把所有 lark-cli 调用集中到 `scripts/_lib/lark_adapter.py`（已部分存在，需强化）
- 加 `tests/test-lark-adapter.sh` 校验：所有 publish/sheet/wiki 类操作只走 adapter，禁止直接 `subprocess.run(["lark-cli", ...])`
- lark-cli 升级时只改 adapter 一处
- 工作量预估：0.5-1 天

#### 🟡 #4 skill template / skill 同构原则（借鉴范围太窄）

**痛点**：close-task vs close-req 设计不对称，反复差异维护。

**现修方式**：commit 9e9316f 重构为"统一两 phase 模式"——**事后对齐**而非**起手就同构**。

**GSD 设计**（grep 现状验证）：
- 每个 workflow.md 用统一 XML 5 段骨架：`<purpose>` / `<philosophy>` / `<required_reading>` / `<process>` / `<success_criteria>`
- 强制所有 workflow 同构

**文档已借**：§2 P0-#1 借了 `<required_reading>` 一段（5 段中的 1 段）

**借鉴扩展建议**：
- 把 P0-#1 从"只加 `<required_reading>` 块"扩展为"强制 SKILL.md 5 段骨架"
- 配套 `scripts/lint-skill-structure.py`（v3.1 已规划，但只 lint 1 段）扩到 5 段都校验
- 对应到 `skill_structure.yml` manifest（Wave 1.5）—— 每个 skill 标注哪些段必须有
- 工作量预估：原 P0-#1 0.5 天 → 扩展后 1 天

### §10.4 对原 §2 矩阵 / Wave 1-4 排序的影响

**应废 / 应保留**：

| 原 Wave 项 | 处理 (v3.4) | 理由 |
|---|---|---|
| Wave 1 #1 Completion Marker | ⏸️ **暂停** (v3.4 改) | 按 §0 痛点锁：PAIN_LINK 弱关联 = 默认 DEFER |
| Wave 1 #2 GATES.md 分类 | ⏸️ **暂停** (v3.4 改) | 同上 — 无害但 ROI 不正 |
| Wave 1 #3 Artifact §9.1 反向列 | ⏸️ **暂停** (v3.4 改) | 同上 |
| Wave 1 #4 Subagent 白名单 | ⏸️ **暂停** (v3.4 改) | 同上 |
| Wave 1.5 skill_structure.yml | 🟡 保留原计划 | v3.3 PM 决策：扩范围动作合并到 Wave 5.3 一起做 |
| Wave 2 `<required_reading>` | 🟡 保留原计划 | v3.3 PM 决策：扩范围动作合并到 Wave 5.3 一起做 |
| Wave 3 拆分 (v3.4 改)| — | v3.4 拆分：Context Monitor / extract-learnings 提升 / Read Injection 保持暂停 |
|   └─ Context Monitor | 🟢 **提升 Wave 5.0a** | 真 PAIN_LINK 强 — PM 每个长会话都遇到 |
|   └─ `/extract-learnings` | 🟢 **提升 Wave 5.0b** | 真 PAIN_LINK 强 — D13 那种"总结教训"手动做过 |
|   └─ Read Injection Scanner | ⏸️ **保持暂停** | PM 单人场景几乎不触发 |
| Wave 4 thinking/anti-patterns/questioning | ❌ **废弃** | #1 已 PMAI 自解，不需 GSD |
| **Wave 5 痛点驱动新增 (v3.3 + v3.4 修订)** | 🔴 **新增** | PM 拍板 D-v32-1=B 后入计划 — 详见 §10.5 |

**v3.4 工作量重算**：
- ~~Wave 1~~（4 项暂停）: 0
- Wave 1.5 manifest: 2-3h
- Wave 2 required_reading: 0.5d
- **Wave 5.0a Context Monitor**: 0.5d
- **Wave 5.0b /extract-learnings**: 1d
- **Wave 5.1 mutation 入口（v3.4 工作量重估）**: 3-5 天
- Wave 5.2 lark-adapter: 0.5-1d
- Wave 5.3 SKILL 5 段骨架: 1d
- **合计**：~6.5-9 天（vs v3.3 的 4.5-5.5 天；增加因 Wave 5.1 重估 + Wave 5.0 提升）

### §10.5 Wave 5 痛点驱动新增（PM 决策 D-v32-1=B，2026-05-17）

**D-v32-1 PM 拍板**：✅ **B — 保留原 Wave 1-2 + 3 项真痛点借鉴作为 Wave 5 补充**

未选 A（重排）理由：Wave 1-2 边角项保留无害，工作量小（1.5 天）；未选 C（先 smoke test）理由：3 项一起规划，方便统一排期。

**Wave 5 详细清单（v3.4 修订）**：

| Wave 5 # | 项 | 工作量 | 优先级 | 启动条件 / 真实收益 |
|---|---|---|---|---|
| **5.0a (v3.4 提升)** | 🆕 **Context Monitor**（50%/70% 警告 hook）| 0.5 天 | 🟡 中 | 独立 hook；解 PM 长会话 context 爆痛点 |
| **5.0b (v3.4 提升)** | 🆕 **`/extract-learnings` 命令**（PM 显式触发）| 1 天 | 🟡 中 | 独立 skill；解 D13 那种总结手动做痛点 |
| **5.0c (v3.5 新增)** | 🆕 **ADR 格式 + `docs/adr/`**（试写 ADR-0001 = D13 决策追溯）| 0.5 天 | 🔴 高 | 独立目录；**即时 evidence — 本文档 1476 行决策散落即反例**；GSD `docs/adr/` 10+ ADR verify 通过 |
| **5.1 (v3.4 修订)** | 🆕 **集中 mutation 入口 + 原子写**（借 GSD STATE.md 思想轻量版）| **3-5 天**（v3.4 重估） | 🔴 高 | 独立；**v3.4 根因修正**：解 state 字段一致性（task 状态 / events.jsonl drift），**不解 I-DC1 markdown 落盘** — 后者是 git working tree + 编辑时机问题，本项无法砍 I-DC1 三道防线 |
| **5.2 (v3.4 修订)** | 🆕 **lark-adapter 单一入口 + lint**（借 GSD ADR-3524 思想，不抄 SDK 双实现）| 0.5-1 天 | 🟡 中（v3.4 降级）| 独立；lark-cli 升级频率低（≈ 一年 1-2 次）→ ROI 真实但不紧急 |
| 5.3 | 🆕 **SKILL 5 段骨架**（合并 Wave 1.5 + Wave 2 扩范围）| 1 天 | 🟡 中 | 依赖 Wave 1.5 + Wave 2 已完成；PMAI 现有 6 段结构已 80% 对齐 GSD 5 段，**实质是显式化已有结构 + lint manifest**，不是引入 XML 重写 |

**Wave 5 实施顺序建议（v3.4）**：
1. **Wave 5.0a + 5.0b 可任一时间穿插** — 独立小项
2. **Wave 5.1 + 5.2 可并行** — 都是独立模块改造
3. **Wave 5.3 排在 Wave 1.5+2 之后** — 5 段骨架需要先有 manifest + required_reading 基础

**回头看条件**：
- Wave 5.1 落地后：观察 state drift 类事故是否消失（**不包括 I-DC1 markdown 类事故，那需要另外的解**）
- Wave 5.2 落地后：观察下次 lark-cli 升级是不是只改 adapter 一处
- Wave 5.3 落地后：观察新 skill 创建时是不是天然同构

**v3.4 下一步**：PM 排期。建议优先级：
- **第一档（小投入高 ROI，可立即穿插）**：Wave 5.0a Context Monitor（0.5d）+ Wave 5.0b extract-learnings（1d）
- **第二档（中投入解真痛点）**：Wave 5.2 lark-adapter（0.5-1d）+ Wave 5.3 SKILL 5 段骨架（1d，需 Wave 1.5/2 先做）
- **第三档（重投入需先 PoC 验证）**：Wave 5.1 mutation 入口（3-5d）— 建议先用 1 天做 PoC，确认根因诊断后再投入剩余工作量

---

### §10.6 v3.4 复审 Finding 简表（2026-05-17）

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 落地位置 |
|---|---|---|---|---|---|
| RV1 | 🔴 Critical | Wave 5.1 根因诊断错位 — "借 STATE.md 砍 I-DC1" 是误判 | I-DC1 真痛点 = task-005 文案偏差事故；GSD STATE.md 解 state mutation；两个不同问题 | `INVARIANTS.md I-DC1` 定义 + GSD `STATE.md + atomic CAS` 架构；I-DC1 防 markdown 编辑 + dispatch 时机，不是 state 字段写 | §10.5 5.1 "真实收益" 列已修正 |
| RV2 | 🟠 High | Wave 5.1 工作量 1-2 天严重低估 | D13 同模式 "2h 评估 → 30h 实施" | 涉及 ≥ 6 个核心脚本（task-transition / req-transition / close-task/req / audit-task-events / _lib/）+ GSD STATE.md 是多年沉淀 | §10.5 5.1 工作量 → 3-5 天 |
| RV3 | 🟠 High | Wave 1 4 项"🟡 保留"逻辑不一致 | §0 痛点锁原则：PAIN_LINK 弱关联 = 默认 DEFER | §10.4 自己写"跟真痛点关联弱"+ memory `feedback_design_pain_guard` | §10.4 表 → 4 项改 ⏸️ 暂停 |
| RV4 | 🟡 Medium | Wave 5.2 优先级过高 | lark-cli 升级频率低（一年 1-2 次） | 上次 1.0.27 升级到现在已几个月无事；adapter 也要维护 | §10.5 5.2 优先级 🔴 → 🟡 |
| RV5 | 🟡 Medium | Wave 3 一刀切暂停过度 | Context Monitor + extract-learnings 有真 PAIN_LINK | PM 每个长会话遇到 context 爆 + D13 总结手动做过 | Wave 3 拆分：5.0a + 5.0b 提升 / Read Injection 保持暂停 |

**v3.4 净改动**：约 +50 行（changelog 1 行 + §10.4 表更新 + §10.5 修订 + §10.6 新增）。文档总 ~1500 行。

**v3.4 后状态**：所有 Wave 划分按"§0 痛点锁 + 真根因"对齐，无两可态。Wave 5.1 启动前需做 1 天 PoC 验证根因诊断。

---

## §10.7 可借鉴项总体优先级排序（v3.6，2026-05-17）

> **本节是 v3.6 最终决策视图**。去掉 Wave / P1/P2/P3 分组（按 PM 要求），直接平铺所有可借鉴项 + 按 ROI 排 1-8 名。
>
> **看本节就够，不需要翻 §10.4 / §10.5 / §10.6**。
>
> 排序依据：PAIN_LINK 强度 + 工作量小 + 独立无依赖 + 启动风险低 → 综合 ROI。

### 可借鉴项总表（按优先级排序）

| 排名 | 项 | 工作量 | PAIN_LINK | 启动条件 | 风险 |
|---|---|---|---|---|---|
| 1 | **ADR 格式 + `docs/adr/`** | 0.5 天 | 🔴 强 — 本文档自身 1500+ 行决策散落即反例 | 独立，立即可启动 | 低 |
| 2 | **Context Monitor hook**（50%/70% 警告）| 0.5 天 | 🔴 强 — PM 每个长会话都遇到 context 爆 | 独立 hook | 低 |
| 3 | **lark-adapter 单一入口 + lint** | 0.5-1 天 | 🟢 中 — lark-cli 升级 4 连 fix 历史；频率 1-2 次/年 | 独立 | 低 |
| 4 | **`/extract-learnings` 命令** | 1 天 | 🟢 中 — D13 那种总结手动做过 | 独立 skill | 低 |
| 5 | **`skill_structure.yml` manifest** | 2-3 小时 | 🟢 中 — v3.1 §8.2 揭示 skill 总数 ≠ 6 skill lint 范围矛盾（当前 20 skill）| 独立 | 低 |
| 6 | **`<required_reading>` XML 块显式化** | 0.5 天 | 🟢 中 — 防御性必读规则散落难统一 | 依赖 #5 | 低 |
| 7 | **SKILL 5 段骨架**（强制 skill 同构）| 1 天 | 🟢 中 — close-task/close-req 对称化是事后补丁 | 依赖 #5 + #6 | 低-中 |
| 8 | **集中 mutation 入口 + 原子写** | 1d PoC + 2-4d 实施 | 🟢 中 — state drift 类事故 | 建议 #1-#5 落地后再启动 | 🔴 高 |

---

### 每项详细

#### 1. ADR 格式 + `docs/adr/`

- **目标**：建立重大设计决策的标准 anchor，让 future-self 接续不用 grep 半天
- **EVIDENCE**：GSD `docs/adr/` 10+ ADR（grep verify `0001-dispatch-policy-module.md` 等），编号清晰 + 模块化
- **实施要点**：
  - 建 `docs/adr/` 目录 + ADR 模板（背景 / 决策 / 后果 / 状态）
  - 试写 ADR-0001：D13 modulespec 维护方案
  - 顶部 README 加 ADR 索引
- **风险点**：低 — 不动现有代码

#### 2. Context Monitor hook

- **目标**：PM 长会话避免 context 爆掉后才发现
- **EVIDENCE**：GSD `hooks/` 含 context monitor 35%/25% 双阈值机制；本对话即是 PM 痛点证据
- **实施要点**：
  - `.claude/hooks/pm-context-monitor.js` PostToolUse 钩子读 context usage（Claude Code 是主入口；Gemini 入口才用 `AfterTool` adapter）
  - 50% 提醒"建议本 req 结束后开新会话"
  - 70% 警告"立即走 close-req 然后开新会话"
  - 简化版（无自动 record）
- **风险点**：低 — 仅 advisory 不阻断

#### 3. lark-adapter 单一入口 + lint

- **目标**：lark-cli 升级时只改 adapter 一处，不再 N 个调用点连环 fix
- **EVIDENCE**：commits 3474d64 / 1dc080a / 2896e2c / 3b91ced 一次升级 4 连 fix；GSD ADR-3524 `lint-shared-module-handsync.cjs` 思想
- **实施要点**：
  - 集中所有 lark-cli 调用到 `scripts/_lib/lark_adapter.py`（已部分存在，需强化）
  - `tests/test-lark-adapter.sh` 校验禁止直接 `subprocess.run(["lark-cli", ...])`
  - **不抄 GSD SDK 双实现**（§4.1 已决拒绝）
- **风险点**：低 — adapter 本身要维护，但比 N 处 patch 好

#### 4. `/extract-learnings` 命令

- **目标**：把每 req 的 Decision / Pattern / Surprise 3 类经验沉淀
- **EVIDENCE**：memory `feedback_design_pain_guard` 等 16 条 memory 都是手动沉淀的结果
- **实施要点**：
  - 新建 `skills/extract-learnings/SKILL.md` + `scripts/extract-learnings.sh`
  - **非 auto-trigger**（按 §8.8 D6 反对精致谎言原则）— PM 显式输入"沉淀经验"才执行
  - `close-req` 完成时**列推荐**，不自动跑
  - 输出到业务仓 `LEARNINGS.md`
  - `INVARIANTS.md` 加 I-RV4 约束
- **风险点**：低 — PM 显式触发

#### 5. `skill_structure.yml` manifest

- **目标**：建立 20 skill 分类基础，为后续 lint / 同构提供依据
- **EVIDENCE**：grep `find skill_structure.yml` = 无输出（不存在）；v3.1 §3.1 banner 已规划；现状 `find skills -maxdepth 2 -name SKILL.md` = 20
- **实施要点**：
  - 新建 `skill_structure.yml`：`pm_view: bool` / `requires_required_reading: bool` / `requires_read_echo: bool` / `risk_level: high/normal`
  - PM 一句话确认分类是否对
- **风险点**：低 — 仅配置文件

#### 6. `<required_reading>` XML 块显式化

- **目标**：把现有 SKILL.md 步骤 0 隐式必读改成结构化 XML 块，便于 lint
- **EVIDENCE**：GSD workflow.md `<required_reading>` 已是 prompt contract；memory `feedback_skill_reading_convergence` 揭示规则散落
- **实施要点**：
  - lint 按 #5 manifest 范围执行（不一刀切 20 skill）
  - 现状 `input-flow.md §9.1` 已是单一权威源，本步只是显式化为 XML
- **风险点**：低

#### 7. SKILL 5 段骨架

- **目标**：所有 skill 同构（不再像 close-task/close-req 那样事后对齐），防新 skill 不对称
- **EVIDENCE**：close-task/close-req 对称化重构 commits（9e9316f / e5a56c0 / 133c32d）是事后对齐；GSD 5 段 XML 骨架强制同构；PMAI 现有 6 段结构已 80% 对齐
- **实施要点**：
  - 不是引入 XML 重写（PMAI SKILL 中文段落式），是**显式化已有结构**
  - 把现有"必读输入 / 步骤 / 硬约束 / 出口条件"统一映射到 5 段
  - `scripts/lint-skill-structure.py` 扩到 5 段都校验
  - 按 #5 manifest 限定范围
- **风险点**：低-中 — 20 skill 都要加注，内容不动

#### 8. 集中 mutation 入口 + 原子写

- **目标**：把分散在 task-transition / req-transition / close-task / close-req / events 等的 state mutation 集中到统一入口
- **EVIDENCE**：GSD STATE.md 集中 state + 文件锁 atomic CAS + 4 层读取优先级
- **🔴 关键警告（v3.4 RV1 已落）**：
  - 真实收益 = **state 字段一致性**（task 状态 / events.jsonl drift）
  - **不解 I-DC1 markdown 文档落盘问题**——后者是 git working tree + 编辑时机问题，本项**不能砍 I-DC1 三道防线**
  - 之前 v3.2 §10.3 #2 写"可砍 I-DC1 三道防线"是误判
- **实施要点**：
  - **PoC（1 天）**：选 task-transition.py 一个 mutation 路径，改成走 `_lib/mutation_lib.py` + 加 audit hook，验证 (a) 是否真能简化代码 (b) 是否破坏现有 60+ I-* invariant 任何一条
  - **实施（2-4 天）**：PoC 通过后，扩展到 req-transition / close-task / close-req 全部 mutation
- **风险点**：🔴 高 — 涉及 ≥ 6 个核心脚本 + 60+ invariant 联动；GSD STATE.md 是多年沉淀，PMAI 1-2 天 grok 是 D13 同模式 trap

---

### ✅ 已部分实施（治标，lint 机制延后）

| 项 | 现状 | 待补 |
|---|---|---|
| SKILL size budget lint（§2 #23）| ea2dc82 commit 已拆 references 治标（task-spec 588 / task-execute 548 / doc-update 442） | lint 机制（≤400 警告 / ≤600 hard cap） |

### ⏸️ 暂停（不主动推进，PAIN_LINK 弱关联）

| 项 | 原因 |
|---|---|
| Completion Marker（agent 输出契约，§2 #4）| PAIN_LINK 弱关联；现 analysis-reviewer 已有契约 |
| GATES.md 4 类归类（§2 #2）| 无害但 ROI 不正 |
| Artifact §9.1 反向列（§2 #5）| 与现有 ❌ pattern 重叠 |
| Subagent 类型白名单（§2 #12）| 防御性约束，PM 单人场景未触发 |
| Read Injection Scanner（§2 #6）| PM 单人场景几乎不触发 |

### 🕓 等触发条件再启动（P2 触发式 + Q1=d 延后）

| 项 | 触发条件 |
|---|---|
| `/health` 命令 + `--repair`（§2 P2 #13）| `check-worktree-residue.py` 误报 ≥ 3 次 |
| Revision Loop 二次 review + 停滞检测（§2 P2 #14）| reviewer 改完 analysis 出现质量回退；与 #1 ADR 互补，先看 #1 效果 |
| CHANGELOG 4-section + Reverted 标记（§2 P2 #15）| 撤回上版决策时（类似 D13 v3→v2）|
| solution-reviewer subagent（§2 P2 #17）| solution 出现"PM 验收时才发现结构问题" |
| plan-checker subagent（§2 P2 #18）| task 拆分反模式发生时 |
| 并行 task `files_modified` + 冲突 lint（§2 P2 #19）| 并行 task 撞同文件 |
| PROJECT-STATE.md（§2 P2 #21）| 跨 req 决策重复发生 |
| Query registry（§2 P2 #28）| 新脚本读 state 第 3 次重复 parse 逻辑 |
| task-status blocking reasons（§2 P0 #25）| Q1=d 决议等真实实施时再写 schema |
| Inventory drift 全覆盖测试（§2 P0 #26）| Q1=d 决议等真实实施时再写 schema |

### ❌ 废弃（明确不做）

| 项 | 原因 |
|---|---|
| thinking + anti-patterns + questioning 合并 | PMAI §0 痛点锁已自解 review 膨胀 |
| Evidence-first 呈交块（verified/claimed/unverified）| §8.8 D6=B — 无 enforcement = 精致谎言载体 |
| GSD SDK 双实现 + TypeScript + npm 包发布 | §4.1 — PMAI 单人无诉求 |
| MVP / Spike / Spec / UI / Secure 阶段变体 | §4.2 — 触发条件未满足 |
| 多语言 README + npm 分发 | §4.3 — 永不需要 |
| 67 命令式可配置（pmai.config.json）| §4.4 — PM 现 0 次诉求 |
| multi-workstream 多工作流并行 | §4.5 — PM 单人单业务 |
| Ambiguity 评分 4 维度 / SPIDR PM 版 | §8.8 D7 — analysis-reviewer + memory 已覆盖 |
| Absent=Enabled 配置模式 | §8.8 D7 — PM 现 0 次诉求 |
| 触发式 UI/Secure checklist | §8.8 D7 — PM 不主管 UI/Secure |

---

### 总工作量表

| 范围 | 项数 | 工作量 |
|---|---|---|
| 可借鉴项 #1-#5 (独立可立即做) | 5 项 | **3-3.5 天** |
| 可借鉴项 #6-#7 (依赖 #5 串行) | 2 项 | 1.5 天 |
| 可借鉴项 #8 (高风险，建议 #1-#5 后) | 1 项 | 1d PoC + 2-4d 实施 |
| ✅ 已部分实施 | 1 项 | lint 延后 |
| ⏸️ 暂停（PAIN 弱）| 5 项 | 0 |
| 🕓 等触发条件 | 10 项 | 0 |
| ❌ 废弃 | 10+ 项 | 0 |
| **全部启动合计** | 8 项 | **~6-9 天 CC** |

---

### 启动建议

**马上开 #1 ADR 格式 + 试写 D13 ADR-0001**：
- 0.5 天独立投入
- 立即收益（这个文档自身能 archive 干净）
- 验证 ADR 模式对 PMAI 是否真有效
- 不动现有代码，零风险

**推荐节奏**：
- 第一周：#1 + #2 + #3 + #4 + #5（独立项，3-3.5 天）
- 第二周：#6 + #7（依赖 #5 串行，1.5 天）
- 第三周：根据前两周结果决定是否启动 #8 PoC

---

**End of GSD 借鉴分析 v3.7**





