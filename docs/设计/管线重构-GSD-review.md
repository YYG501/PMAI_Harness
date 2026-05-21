# v3.5 管线重构方案 · PM 已判断 (v2)

> **状态**：PM 已判断（2026-05-20）；2026-05-21 /plan-eng-review 复核修订 §5 / §8（delta-7 拉入最小落地包,详见 §Y）
> **日期**：2026-05-20
> **作者**：PM + AI

---

## §1 这份方案是什么

- **来源**：PM 在真实项目 ChatBuilder 完整跑了一遍 GSD（get-shit-done），据此 review 本仓 v3.5 管线。
- **性质**：对 v3.5 管线的 7 处改动方案，PM 逐条判断（§4.2 判断表）。
- **决策原则**：**以本次讨论的结论为准**；旧文档（2026-05-17 GSD 借鉴、D13 等）只作参考与事实校验，不 override 本次讨论。§0 痛点锁不作为否决依据。

---

## §2 核心结论：架构对，不重写

v3.5 现有 21-skill 管线与 GSD **同形**。结论：**改 delta，不重写**。

```
v3.5 现有                      GSD 对应
new-req（brief）               QUESTIONING
req-analysis                   RESEARCH
req-solution                   ROADMAP / PLAN
task-plan                      PLAN-PHASE 拆分
task-spec → task-confirm       task 详规
task-execute → task-verify     EXECUTE / VERIFY
close-task → close-req         TRANSITION
```

---

## §3 目标管线全貌

```
【建项目】
 newproject ─→ init-project（建骨架）
      或
 brownfield ─→ codebase-audit（扫码建现状档）★新建
        ↓
 project-solution（一个 skill，内部两段）★改造自 req-solution
   · 讨论方向（复用 analysis 提问法；可选 office-hours / plan-ceo-review）
   · 输出：项目方案 + 计划态 roadmap（单文件）
        ↓  roadmap 排出 req 序列
┌────────────── 每个 req（串行）──────────────┐
│ new-req（brief）                            │
│ req-analysis（全量 / 增量分支）              │
│ PRD（req 级规格，stage 3 定稿冻结）           │
│   └ 有 UI → 补 UI 规范（design-consultation）│
│ 拆 task → task-plan.md                      │
│ task ×N（纯实现 + 原子 commit）               │
│   ├ batch 模式：全做完                       │
│   └ 逐个模式：每 task 自动+手动验收 → 提改     │
│ close-req：反向对齐 PRD + modulespec 沉淀     │
└──────────────────────────────────────────────┘
        ↓ 下一个 req（newreq）
```

### §3.1 task 详化时机 · lazy + 两模式

**每个 task 的详细 spec（task-spec）一律 lazy** —— 轮到哪个 task 才详写它，两个模式都一样，不批量提前写完。

| 产物 | 何时出 | 两模式差异 |
|---|---|---|
| task 清单（task-plan）+ 实现设计视图（delta-8）| 一次性提前出 | 无 |
| 每个 task 的详细 spec（task-spec）| lazy，一个个出 | 无 |
| **PM 验收闸门** | —— | **逐个 vs 最后一次（唯一区别）** |

- **逐个模式**：每个 task 做完 → 自动 + 手动验收 → PM 提改 → 才进下一个
- **batch 模式**：task 连着做，中间不停 PM 闸门，最后一次性验收

**为什么 task-spec 坚持 lazy**：批量提前写死 → task-3 的文档在 task-1 执行前就冻好，task-1 一旦发现问题、task-3 即过期（GSD 实证：`01-03-PLAN` 至今写着 `npm`，项目早已切 pnpm）。lazy 写 → task-3 临开工才详化、看当下现状，无 stale。

**GSD 对照（容忍 vs 规避）**：GSD 批量写、靠重机器**容忍** staleness（能 deviate 的 executor + debugger + verifier 一整张安全网）。我们框架轻，背不起那张网，选 lazy **规避** —— 让 stale 无从发生。同 §6.1：没有 agent 架构，就别用 agent 架构的兜底法。

---

## §4 改动清单（PM 已判断 2026-05-20 —— 结果见 §4.2 / §8）

### delta-1 · brownfield 入口 `DEFER`
- **决策**：defer —— 无近期具体的 brownfield 项目，探索确认没有便宜捷径。
- **设计已锁（触发即用）**：brownfield = 扫代码出「代码现状档」（章节照 GSD map-codebase 的 7 维度：stack / 集成 / 架构 / 结构 / 约定 / 测试 / 隐患；带防 secret 扫描）→ 然后走和新项目**一样的** project-solution 讨论（被现状档喂着）。和 GSD 的 `map-codebase → new-project` 同构。
- **触发条件**：真有已有项目要接入框架时启动。

### delta-2 · PRD 角色前移 `★中`
- **现状**：`prd-writing` 在 close-req 时作为可选产出。
- **提案**：PRD 前移到 req 的 stage 3，成为 req 级功能规格、驱动 task；吸收原 task-spec 的 PM 视图内容（产品决策 / 功能清单 / 验收）；stage 3 定稿后冻结。
- **动**：`prd-writing` 改造 + 前移；重连它与 req-solution、task-spec 的关系。

### delta-3 · task-spec 重构 `★中`
- **现状**：`task-spec` 为每个 task 产出 PM 视图 + 工程合同双文件。
- **提案**：PM 内容并入 PRD（见 delta-2）；task 只留实现规格（怎么做 + 怎么算做对）；删 5 个啰嗦点（详见 §4.1）。
- **动**：`task-spec` 重构。
- **参考**：delta-3 以本次诊断的 5 个缺陷为准。旧文档记 task-spec 588 行（本次诊断读到 1100+）—— 动手前顺手核一下实际行数即可，不影响 delta-3 成立。

### delta-4 · solution 提升项目级 `★中`
- **现状**：`req-solution` 是 per-req 的 stage 3 skill，产 solution.md + solution.engineering.md 双文件。
- **提案**：改造成 `project-solution`，移到 new-project；一个 skill 内部两段（讨论方向 → 输出项目方案 + 计划态 roadmap）；单文件（砍工程孪生）；讨论段可选挂 office-hours / plan-ceo-review。
- **动**：`req-solution` → `project-solution`。
- **事实**：项目级 roadmap 这个概念，2026-05-17 那轮有一份 #21「PROJECT-STATE.md」设计（当时 defer、未落地）—— 可复用那份设计思路，不从白纸起。

### delta-5 · newreq 增量分析 `·小 ~4h`
- **现状**：`req-analysis` 按"从零完整分析"设计。
- **提案**：加"全量 / 增量"分支；项目已有时的新 req 走增量分析（聚焦新增、不重扫）。
- **动**：`req-analysis` 小改。

### delta-6 · A 反向对齐 `·小`
- **现状**：close 阶段 doc-update 把变更沉淀进 modulespec（D13 方案，已落地）。
- **提案**：close-req 收尾反向对齐 ——（a）PRD 转 as-built；（b）modulespec 沉淀。PRD req 内冻结，收尾一次性对齐，git commit 留痕。
- **动**：`close-req` 小改（仅 PRD 反向对齐部分）。
- **事实**：✅ modulespec 反向更新 = D13，已落地实现 —— 该部分直接复用，不重建。真正要新做的只有 PRD 反向对齐。

### delta-7 · req 级事件流 `·小`
- **现状**：事件流只到 task 级（`.runs/events/<task>.jsonl`），req 级只有 stage_history。
- **提案**：加 req 级事件流 `.runs/events/req-*.jsonl`；兼作 delta-6 中 PRD 反向对齐所需"调整日志"的存放处。
- **动**：新增 req 级事件流。

### delta-8 · req 级「实现设计」HOW 安家 `delta-3 通过则必做`
- **定性**（研究结论）：delta-8 不是"借不借 GSD"，是 **delta-3 + delta-4 的连带后果** ——
  - delta-3 让 task 变"纯实现" → HOW 被挤出 task 合同
  - delta-4 把 req-solution 上移到项目级 → 现在装 req 级 HOW 的 `solution.engineering.md` 没了
  - 叠加：req 级 HOW（这个 req 用什么架构、照哪些代码写）无家可归
- **提案**：「拆 task」步骤（task-plan）顺带产出一份 req 级**实现设计**视图，承接原 solution.engineering 的 HOW 内容。
- **性质**：主要是 **relocation，不是 net-add** —— `solution.engineering` 今天已覆盖约 70-80% 的 HOW；delta-8 是把它挪到新位置。唯一真新增 = "选型论证"（为什么选 X 不选 Y），作可选段。
- **form 已定 = 1 份 doc**：req 级「实现设计」单文件，内部分 3 段（架构决策表 / 文件·模式索引 / 可选选型论证）。GSD 分 3 文件是因为它每个 artifact 配一个专属 agent（gsd-phase-researcher / gsd-pattern-mapper / gsd-planner，各拿 fresh context）—— 文件边界 = agent 边界。我们的 task-plan 是主 AI 一气写完，没有那个架构，照抄 3 文件 = cargo-cult。
- **必要性挂 delta-3**：delta-3 通过 → delta-8 必做；delta-3 否（task 继续背 HOW）→ delta-8 可选。
- **动**：`task-plan` 加产出；`task-spec` / `task-execute` 改成引用这份视图（定向读，不整读）。

### §4.1 delta-3 的 5 个啰嗦点

| # | 缺陷 | 处理 |
|---|---|---|
| ① | PM 反馈三类分流（规则隐式、AI 执行率低、PM 错分）| 简化二分 |
| ② | hash 同步把框架层状态泄漏进 skill 逻辑 | 移到框架 hook |
| ③ | task-spec 与 task-confirm 确认门重叠 | 单一确认门 |
| ④ | PM 视图 / 工程合同双功能清单失同步 | delta-2 后自动消（PM 内容并入 PRD，清单一份）|
| ⑤ | task 间反馈隐式流动 | delta-2 后自动消（反馈走 req 收尾反向对齐）|

> task-spec 有 6 样 GSD PLAN 没有的东西（双视图 / 占位字典 / 决策表 / 自动 UAT / 跨功能规则 / 历史档案）—— 决策密集型框架的存在理由。delta-3 是**留思路、删啰嗦**，不换成 GSD 格式。

### §4.2 判断表

| # | 改动 | 量级 | PM 判断（2026-05-20）|
|---|---|---|---|
| 1 | brownfield codebase-audit | ★大 | **DEFER** —— 设计已锁，触发即用 |
| 2 | PRD 角色前移 | ★中 | **通过** |
| 3 | task-spec 重构 | ★中 | **通过** —— ①②③ 全改；动手前核行数 |
| 4 | solution 提升项目级 | ★中 | **通过** |
| 5 | newreq 增量分析 | ·小 | **通过** |
| 6 | A 反向对齐（仅 PRD 部分新做）| ·小 | **通过** |
| 7 | req 级事件流 | ·小 | **通过** |
| 8 | HOW 安家（实现设计视图）| ·中 | **通过** —— 随 delta-3 |

---

## §5 复用映射

| 处理 | skill |
|---|---|
| **原样复用**（~14）| new-req · req-stage-gate · task-plan · task-confirm · task-execute · task-verify · task-submit · close-task · cancel-req · task-status · doc-update · publish-to-lark · term-detector · init-project |
| **改造**（5）| req-analysis（加增量分支）· req-solution → project-solution · prd-writing（前移成 req 驱动规格）· task-spec（重构）· quick-fix（2026-05-21 eng-review A1：引用 solution.md / solution.engineering.md / req-solution,delta-2+4 后须迁 prd.md + 决策性编辑路由改指 stage-3 prd-writing）|
| **新建**（1）| codebase-audit |

零 skill 从头重写。

---

## §6 明确不做

1. ❌ 不重写管线 —— v3.5 架构已对（§2）
2. ❌ 不抄 GSD STATE.md —— 框架已有单一真相源（`.req-meta.json` + `_lib/state.py`）
3. ❌ 不引入 wave / 并行 —— 单人串行不需要
4. ❌ project-solution 不要工程孪生双文件 —— 项目级方案是 PM 战略，单文件
5. ⏸️ threat_model / 跨 req 风险表、blocker 自动提醒、req 粒度判据 —— 实证再决定，现在不投入

### §6.1 设计原则 · agent 边界

**为什么 planning / 决策类 skill 不 agent 化**（task-spec / req-solution / req-analysis 跑在主线程）：

| 工作类型 | 走哪里 | 例子 |
|---|---|---|
| 自主的机械活 | → agent（一次性 context）| task-execute、analysis-reviewer |
| 协作 / 决策 | → 主线程 | task-spec、req-solution、req-analysis |

> 「例子」列是举例、非穷举。同一原则套其余 skill：`analysis-reviewer` 已是 agent；`task-verify` 自动 UAT 是机械活、但归属看下方「第二根轴」；`codebase-audit`（delta-1，DEFER）触发时其扫码 fan-out 按本原则用 agent。

**第一根轴 · 协作 vs 机械** —— planning 类留主线程，三条理由：
1. **对话只能在主线程** —— planning skill 是来回的（确认 / 答未决问题 / 改），agent 是 fire-and-forget，塞不进来回对话。GSD 同此：QUESTIONING 也是主线程，只 agent 化自主活。
2. **框架价值 = PM 在环里** —— GSD agent 模型让 orchestrator"只收行数、不收内容"，故意把 PM 挡在细节外换吞吐；本框架反过来（PM 视图 / 确认门 / 未决问题闸门），就是让 PM 在产品决策里面。planning agent 化 = 丢掉协作过程 = 把本框架变成 GSD。
3. **编排机器太重** —— GSD 33 agent + 编排层是平台规模，单人工具不需要。

**已知权衡**：planning 在主线程的代价 = context 会涨 / 重复读。本方案不靠 agent 隔离治它，靠 delta-8（小实现设计视图 + 定向读）+ 现有「必读清单收敛」—— 更轻。未来若要进一步，可考虑把 planning 的"纯读 + 起草"段 agent 化（agent 起草、PM 主线程审），但默认不做。

**第二根轴 · 运行时能力** —— 「机械活 → agent」不等于「折进 executor」。本框架的 executor 可插拔（`resolve-executor.py` / `build-execution-prompt.py` 执行信封，可为 Claude / Codex / Cursor），能力集不保证一致。一个 task 的生命周期跨三种角色：

| 角色 | 干什么 | 跑在哪 |
|---|---|---|
| orchestrator | 备执行信封、派活、收口 commit | Claude 主线程 |
| executor | 写代码 | 可插拔（Claude agent / Codex / Cursor）；不保证有浏览器 |
| verifier（task-verify）| 浏览器 UAT | 需 `gstack-browse` → 只能 Claude/gstack 侧（主线程即可，不强求独立 agent）|

（上表「自主机械活」格里的 `task-execute`，细看就是 orchestrator + executor 两段。）

→ 判据：**机械 + executor 可移植**（纯写代码 / git）→ 可在 executor 内；**机械 + 需 Claude/gstack 专有工具**（如 `gstack-browse`）→ 必须留 Claude 侧。`task-verify` 属后者 —— 它在 executor 的产出（worktree + dev server）之上跑，与「谁是 executor」无关，不折进 executor 边界。

---

## §7 参考背景（旧文档 —— 仅参考，不约束本方案）

> 以下来自旧文档。本方案以本次讨论为准，下列只供 PM 判断时参考。

- **2026-05-17 已有一轮 GSD 借鉴**（`docs/归档/完成/gsd-借鉴-*`，10 轮迭代、PM 1-1 判定）。最终 backlog 2 项：lark-adapter 单一入口 + 读层 state.py（~1 天）。**独立一条线，与本 7-delta 不冲突，PM 另行决定做不做。**
- **delta-6 的 modulespec 反向更新已实现**（D13 方案，`docs/归档/完成/modulespec-维护/`）—— 本方案该部分直接复用。
- **delta-3 的 task-spec 行数待核**（诊断 1100+ vs 那轮记录 588）—— 动手前先核实。

---

## §8 实施顺序（PM 已判断 2026-05-20）

判断结果：delta-2/3/4/5/6/7/8 全部**通过**；delta-1 **DEFER**；2-item backlog **单独排**。

**最小落地包 = delta-2+3+4+7+8**（2026-05-21 /plan-eng-review 修订：codex outside-voice 查出 delta-2+4 §2.2 决策理由、delta-3 §2.4 跨模块反馈均已归 delta-7 事件流 —— delta-7 不在包内则第一批 req 决策理由无家；delta-7 由「后续轮次」拉入最小包）。

推荐实施顺序（按依赖；delta-8 拆 vp 交错进 delta-3 两侧）：

| 步 | 做什么 | 依赖 |
|---|---|---|
| 1 | delta-7 —— req 级事件流（独立 infra，先建：后续 delta 的决策理由 / 反馈有家）| — |
| 2 | delta-2 + delta-4 —— PRD / solution 对调（地基，一起做）| delta-7 |
| 3 | delta-8 vp-1/vp-2 —— implementation-design 模板 + skill（与 delta-2+4 无文件冲突，可先行）| delta-4 |
| 4 | delta-3 —— task-spec 重构（一次性吸收 prd.md + implementation-design 两个上游 reader）| delta-2 + delta-8 vp-1/2 |
| 5 | delta-8 vp-3（并入 delta-3 vp-3）+ vp-4 收尾 | delta-3 |
| 6 | delta-6 —— A 反向对齐 | delta-2 + delta-7 |
| 7 | delta-5 —— newreq 增量分析（独立小项，随时）| — |

> 步 1-5 = **最小落地包 delta-2+3+4+7+8**，须同批落地、不可拆单独 ship。步 6-7 为后续轮次。

- **delta-7 聚焦设计文档待补** —— delta-7 拉入最小包后仍需按 `_模板-方案.md` 开一份聚焦设计文档（§0 痛点锁 PM 共写），先于实施定稿。
- **2-item backlog**（lark-adapter 单一入口 + 读层 state.py）：独立线，不并这轮、不阻塞管线重构；动手前先核实 `_lib/state.py` 是否已实现。
- 每个通过的 delta → 各开一份聚焦设计文档（`_模板-方案.md`）落地。

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-20 | GSD-review 完成；7-delta 方案 v1 成形；PM 决定按决策意见推进、痛点锁不作否决 | 待 PM 逐条判断 §4.2 |
| 2026-05-20 | PM 定调：以本次讨论为准，旧文档仅参考 | §1 决策原则、§7 已更新 |
| 2026-05-20 | 新增 delta-8（研究项）：实现设计阶段是否补「HOW 功课」层 | 待研究 |
| 2026-05-20 | delta-8 研究完：定性为 delta-3+4 连带后果（req 级 HOW 安家），主要是 relocation；必要性挂 delta-3 | delta-8 转真 delta |
| 2026-05-20 | delta-8 form 定为 1 份 doc —— GSD 分 3 文件是 agent 架构产物（文件=agent 边界），我们无此架构 | form 收敛 |
| 2026-05-20 | PM 判断（委托 AI 推荐）：delta-2~8 全通过、delta-1 DEFER、2-item backlog 单独排；实施顺序见 §8 | 方案 → v2，进入实施 |
| 2026-05-20 | 记入 agent 边界设计原则：planning/决策类 skill 不 agent 化（协作在主线程），自主机械活才 agent 化 | §6.1 新增 |
| 2026-05-20 | 记入 task 详化时机：lazy（两模式都不批量写死），两模式仅差 PM 验收闸门；GSD 容忍 / 我们规避 staleness | §3.1 新增 |
| 2026-05-21 | §6.1 补「第二根轴 · 运行时能力」：executor 可插拔（Claude/Codex/Cursor）能力集不一，机械步是否折进 executor 取决于是否需 Claude/gstack 专有工具；task-verify 因需 gstack-browse 留 Claude 侧。「例子」列标注非穷举 | §6.1 扩充 |
| 2026-05-21 | /plan-eng-review 复核 delta-2+3+4+8 包（13 finding，含 codex outside-voice 2 Critical）：§5 quick-fix 移入「改造」（A1）；§8 重排 —— delta-7 拉入最小落地包（codex#4）、delta-8 vp 交错进 delta-3 两侧（F7）。13 finding 决议分别落 delta-2+4 / delta-3 / delta-8 各 §X，delta-7 待开聚焦设计文档 | §5 / §8 修订 |

---

**End of v3.5 管线重构方案 v1**
