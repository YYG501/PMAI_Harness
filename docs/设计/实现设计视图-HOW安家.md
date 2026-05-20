<!-- /autoplan restore point: <LOCAL_GSTACK_HOME>/projects/PM-AI-Workflow/main-autoplan-restore-20260520-173742.md -->
# req 级实现设计视图（delta-8 · HOW 安家）(v1)

> **状态**：v1（2026-05-20）—— §1-§6 据 §X Round 1（14 ACCEPT finding）+ 4 个 User Challenge 决议修订完成。待 PM 复核 / 实施（建议实施前重跑 /plan-eng-review）。§X Round 1 = v0 的 autoplan 6-voice review 记录，保留作历史。最小落地包 = delta-2+3+4+8。
> **日期**：2026-05-20
> **作者**：PM + AI
> **来源**：`管线重构-GSD-review.md` §4 delta-8 + §8 实施顺序第 3 步；`PRD-solution-对调.md` v1.1 §X review（UC-2 / F8 —— delta-8 与 delta-2+4 同批落地，是最小可落地包成员）

---

## §0 原始痛点（PM + AI 共写，后续 review **不可反向修改**）

> ⚠️ 本节经 **PM + AI 共写、2026-05-20 锁定**。后续任何 review / autoplan 都不能给本节加东西、不能重新定义范围；如需改 §0，PM 显式 v0 → v1 重开。
> 锁定依据：`管线重构-GSD-review.md` §4 delta-8 的研究结论（PM 已在 §4.2 判 delta-8 通过）。

### §0.1 痛点（1-3 句）

delta-3 让 task 合同变「纯实现」、HOW 被挤出 task；delta-4 把 `req-solution` 上移项目级、承载 req 级 HOW 的 `solution.engineering.md` 被砍。两者叠加后，「这个 req 用什么架构、照哪些现有代码 / 模式写、为什么这么选」这层 **req 级 HOW** 没有任何结构化归宿。

### §0.2 触发场景

> delta-8 是 delta-3 + delta-4 的**结构连带**，不是 PM 单点踩坑。触发证据是「现有 `solution.engineering.md` 承载 HOW + delta-3/4 移除其两个寄生宿主」这一结构事实，非 incident。必要性显式挂 delta-3（见 §6）。

| # | 场景描述 | 证据（结构性 / 仓内可查）|
|---|---|---|
| 1 | delta-4 砍 `solution.engineering.md` → req 级工程层约束（数据结构 / 派生规则 / 组件路径 / 算法消费规则 / 易错点）无容器 | `templates/solution.engineering.md.tmpl` 现存 10 章工程合同；`PRD-solution-对调.md` v1.1 §X F8 |
| 2 | delta-3 让 task-spec 只留实现规格 → 跨 task 共享的 req 级 HOW（架构取向、照哪些代码写）无处安放 | `管线重构-GSD-review.md` §4 delta-8 研究结论 |
| 3 | req 级 HOW 当前寄生在 `solution.engineering`；delta-4 后若不安家 → task-spec / task-execute 各自重新推导架构，重复且易漂移 | `管线重构-GSD-review.md` §4 delta-8「无家可归」诊断 |

### §0.3 根因（解决什么底层 mechanism）

req 级 HOW（实现设计层）今天**寄生**在 `solution.engineering.md`（per-req 工程合同），从来不是独立结构位。delta-4 一砍 `solution.engineering`、delta-3 一掏空 task 合同，这层内容同时失去两个寄生宿主。根因 = **req 级实现设计从未有过自己的结构位**。

### §0.4 不解决什么（防膨胀）

| 衍生 / 假设场景 | 为什么不在本文档 |
|---|---|
| task-spec 内部重构 | = delta-3，单独设计文档 |
| project 级顶层方案 / req 级 PRD | = delta-2+4（`PRD-solution-对调.md`）|
| modulespec 维护 | = D13（已落地）；modulespec 是模块级稳定档，与 req 级一次性实现设计不同层 |
| 把实现设计拆成 GSD 式 3 文件 | §5 已定：单文件（GSD 3 文件 = agent 边界产物，我们无此架构）|
| 选型论证强制化 | §5：选型论证是可选段，不强制 |

→ review 中任何 finding 指向以上场景的，默认 DEFER（除非 PM 显式接受拉进 §0）。

---

## §1 方案概述

新增独立 skill **`/implementation-design`**，在 stage 5「拆 task」之前产出一份 req 级**实现设计文档**单文件（`implementation-design.md`，落 `$ACTIVE_REQ_DIR/`），承接原 `solution.engineering.md` 的 req 级 HOW 内容。

- **producer = 独立 skill**（review UC-1）—— 不让 `task-plan`「顺带产出」。`task-plan` 是 lint 强制的 PM 视图拆分 skill（`check-doc-pm-view.py` 禁工程词、description 明写「单一文件、不生成工程合同分文件」），让它兼产 TS-laden 工程 artifact = delta-2+4 §0.1 给 `req-solution` 修过的「一个 skill 背两层」反模式。GSD 亦把产 HOW 的 `gsd-pattern-mapper` 与拆 task 的 `gsd-planner` 分成两个 agent。
- **消费 = task-spec 上游**（review UC-4）—— `task-spec` 读 `implementation-design.md`、按 HOW-ID 挑出当前 task 相关行、写进自包含的 `task.engineering.md`；`task-execute` 只读 task 工程合同，**不直读** `implementation-design.md`。对齐 GSD：executor 只读自包含的 plan，pattern artifact 是 planner 的上游。

**性质 = relocation**：`solution.engineering` 已覆盖大部分 req 级 HOW，delta-8 把它挪到独立文件 + 独立 producer。逐章归宿见 §3.4 的 10-章归宿表（review D8-1：实测 7 章迁入 / 1 章归 DESIGN.md / 1 章删除）。

### §1.1 设计问题（§1 五题收口 —— v1 含 4 UC 修订）

| # | 设计问题 | v1 决议 |
|---|---|---|
| Q1 | 文件名 | **`implementation-design.md`**（落 `$ACTIVE_REQ_DIR/`），由独立 `/implementation-design` skill 产出 |
| Q2 | schema 定到多细 | 段框架 + **可消费 schema（HOW-ID 等）现在定**（§3.3）—— review D8-7：3 个粗粒度段名无法被现役 grep 命中，schema 不可延后 |
| Q3 | task-spec 消费机制 | **HOW-ID 行级锚** —— task-spec 按 `HOW-ID` + 适用关键词挑行（精化原「章节锚点」，review D8-7）|
| Q4 | 选型论证 | **折进段1 每行的决策字段**（选择/备选/理由/约束失效条件）—— review UC-3 重开：不做可选默认空大段，否则不满足 §0 的「为什么这么选」 |
| Q5 | stage 衔接 | `/implementation-design`（stage 5、task-plan 前）产出；PRD（stage 3 冻结）；task-spec（stage 6）读 PRD(WHAT) + implementation-design(HOW) |

---

## §2 与现有机制的关系

| 机制 | 处理 | 备注 |
|---|---|---|
| `/implementation-design`（新 skill）| **新建** | stage 5 拆 task 前调；产 `implementation-design.md`（review UC-1）|
| `solution.engineering.md` / `.tmpl` | delta-4 砍 | 10 章逐章归宿见 §3.4 表 |
| `task-plan` | **delta-8 不动** | task-plan 保持纯 PM 视图拆分 skill；它不产、不读 implementation-design（delta-2+4 单独处理它的 prd.md 迁移）|
| `task-spec` | **改** | 读 `implementation-design.md`、按 HOW-ID 挑当前 task 相关行、写进自包含 `task.engineering.md`（与 delta-3 的 task-spec 重构协同，见 §4.1）|
| `task-execute` | **delta-8 不动** | 只读 task 工程合同，不直读 implementation-design（review UC-4）|
| `build-execution-prompt.py` | **delta-8 不动** | 执行信封仍只输出 PM 视图 + task 工程合同 2 路径（review D8-3：UC-4 决议后零改）|
| `modulespec`（D13）| **不变** | modulespec 是模块级稳定档；implementation-design 是 req 级一次性 HOW，两层不同 |
| req 级 PRD（delta-2）| **不变** | PRD = req 级功能规格（WHAT）；implementation-design = req 级 HOW。WHAT / HOW 分离，互相引用不重抄 |

---

## §3 form：`implementation-design.md` 的结构

### §3.1 文件性质（review D8-11 / D8-14）

`implementation-design.md` 是**工程合同性质的内部 artifact**，不是 PM 视图：

- **PM 默认不看** —— 模板 header 照搬 `solution.engineering.md.tmpl` 的「本文件是工程合同，PM 默认不看」声明 + 允许工程内容清单（TS 类型 / 字段 / 像素 / 反向约束）。
- **不跑 PM-view lint** —— `check-doc-pm-view.py` 跳过 `implementation-design.md`（同它已跳过 `.engineering.md`）。
- **无独立 PM 确认门** —— 不进 stage-gate 确认门展示；stage 5 确认门只列 `task-plan.md`。

### §3.2 段结构

单文件，内部分段（design-level 框架；字段 schema 见 §3.3）：

- **段 1 · 架构决策表** —— 这个 req 用什么架构 / 技术选择。承接 `solution.engineering` ch1 数据结构 + ch2 派生状态规则。
- **段 2 · 文件·模式索引** —— 照哪些现有代码 / 模式写。承接 ch3 组件实现路径 + ch4 Mock 改造 + ch5 关键算法消费规则。
- **段 3 · 约束与验收** —— 易错点 / 反向约束 + 工程层验收清单。承接 ch6 + ch10（review D8-12：易错点必须有明确归属段）。
- **段 4 · 审计与修订记录** —— plan-review 沉淀 + 修订留痕（review D8-9）。承接 ch7；或改写入 delta-7 req 事件流、本段只渲染引用。

### §3.3 可消费 schema（review D8-7 —— vp-1 现在定，不延后）

段 1 / 段 2 每条 HOW 是一行，带稳定字段，供 task-spec 定向消费：

| 字段 | 说明 |
|---|---|
| `HOW-ID` | 稳定行级锚（如 `HOW-03`）；task-spec 按 ID 引用，不靠章节标题 grep |
| 适用模块 / 适用 task 关键词 | task-spec 据此挑出当前 task 相关的 HOW 行 |
| 决策内容 | 段1：**选择 / 备选 / 理由 / 约束失效条件**（review UC-3：每行必带，允许写「无非平凡备选」但不默认空）；段2：文件路径 / 模式 |
| 来源 | 承接自 solution.engineering 哪章 / 新增 |
| 消费者 | task-spec |

「定向引用」= task-spec 按 `HOW-ID` + 适用关键词挑行（review D8-7：精化原 Q3「章节锚点」—— 3 个粗粒度段名无法被现役 `input-flow.md §9.1.1` 的 `^### 关键词` grep 命中，改用 HOW-ID 行级锚）。

### §3.4 `solution.engineering` 10 章归宿表（review D8-1 —— 不可延后，它决定段结构）

| solution.engineering 章 | 归宿 |
|---|---|
| ch1 数据结构定义 | → 段1 架构决策表 |
| ch2 派生状态规则 | → 段1 架构决策表 |
| ch3 组件实现路径 | → 段2 文件·模式索引 |
| ch4 Mock 数据改造清单 | → 段2 文件·模式索引 |
| ch5 关键算法消费规则 | → 段2 文件·模式索引 |
| ch6 易错点 / 反向约束 | → 段3 约束与验收 |
| ch7 plan-review 沉淀 | → 段4 审计与修订记录（或 delta-7 事件流）|
| ch8 autoplan 修订点 / 决策表 | **删除** —— per-artifact 审计噪音，req 级不留 |
| ch9 a11y / 视口 / 视觉规范细则 | → `DESIGN.md`（项目级视觉规范，非 req 级 HOW）|
| ch10 工程层验收清单 | → 段3 约束与验收 |

→ 7 章迁入 implementation-design、1 章归 DESIGN.md、1 章删除；ch1-5 是迁移主体。vp-1 动手前按此表核 `solution.engineering.md.tmpl` 实际内容（尤其 ch6/ch10 实际体量）。

**为什么单文件不分 GSD 式多文件**：GSD 分多文件是因每 artifact 配专属 agent（文件边界 = agent 边界）；我们的 `/implementation-design` 是主 AI 一气写完，无此架构，分多文件 = cargo-cult（同 umbrella §4 delta-8）。

---

## §4 实施清单

| vp | 改什么 | 依据 |
|---|---|---|
| vp-1 | 新建 `templates/implementation-design.md.tmpl` —— 4 段结构（§3.2）+ 可消费 schema（§3.3 HOW-ID 等）+ PM-invisible header（§3.1）；`check-doc-pm-view.py` 加 `implementation-design.md` 跳过 | §3 |
| vp-2 | 新建 `/implementation-design` skill —— stage 5 拆 task 前调；读 brief + analysis + PRD + CONTEXT，按 §3.4 归宿表产 `implementation-design.md` | §1 §2（UC-1）|
| vp-3 | `task-spec` 改：从「读 solution.engineering」改成「读 `implementation-design.md`、按 HOW-ID 挑当前 task 相关行、写进自包含 `task.engineering.md`」。`task-execute` / `build-execution-prompt.py` **零改**（UC-4）| §2（UC-4 / D8-7）|
| vp-4 | 模板引用更新 + 测试 + SOP —— `task.engineering.md.tmpl` §3 / `CLAUDE.md.tmpl` 去 solution.engineering 引用；test matrix（见下）；`框架同步-SOP.md` 补迁移段 + operator breadcrumb（≤3 行：implementation-design 是内部 AI 参考、PM 无需处理）| §2 §6（D8-10/D8-13）|

**vp-4 test matrix（review D8-10）：**

| 测什么 | 动作 |
|---|---|
| 模板 schema | `implementation-design.md.tmpl` 4 段 + HOW-ID 字段齐 |
| producer | `/implementation-design` 按 §3.4 归宿产出 `implementation-design.md` |
| task-spec 派生 | task-spec 按 HOW-ID 挑行、写进自包含 `task.engineering.md` |
| 执行信封不变 | `build-execution-prompt.py` 仍只输出 2 路径；非 Claude 执行器仍只读 task 两文件（review D8-3）|
| 旧-req-compat（IRON 回归）| 旧 req 有 `solution.engineering.md` / 新 req 有 `implementation-design.md` 均能跑完 |
| grep residual | 全仓无现役 `solution.engineering.md` 引用残留 |
| baseline | 明确新基线数 |

### §4.1 落地顺序与文件 ownership（review D8-8）

UC-2 把 delta-3 纳入 → **真实落地包 = delta-2+3+4+8**。三个 delta 都改 `task-spec`：delta-2+4 vp-4b（切 `prd.md`）/ delta-3（task-spec 内部重构，单独设计文档）/ delta-8 vp-3（改读 `implementation-design.md`）。

**落地顺序**：delta-2+4（stage 3 契约迁移，地基）→ delta-3（task-spec 重构）→ delta-8 vp-3 在 delta-3 的 task-spec 新形态上加「读 implementation-design」。delta-8 vp-1 / vp-2（模板 + 新 skill）与 delta-2+4 无文件冲突，可先行。

---

## §5 砍掉 / 不做的机制清单（防 review 回写）

1. ❌ 不分 GSD 式多文件 —— 单文件多段（§3.2）
2. ❌ 不让 task-plan 兼产 implementation-design —— 独立 `/implementation-design` skill（UC-1）
3. ❌ task-execute 不直读 implementation-design —— 只读 task 工程合同（UC-4）
4. ❌ 不引入专属 agent —— `/implementation-design` 主线程一气产出
5. ❌ 不动 `modulespec`（D13）—— 不同层
6. ❌ implementation-design 不重复 PRD 的 WHAT —— 引用，不重抄
7. ❌ 选型论证不做成可选默认空大段 —— 折进段1 每行的决策字段（UC-3）

→ 任何 review finding 想恢复以上任一条，必须 PM 显式更新 §0 并 v1 → v2。

---

## §6 风险与待验

- **最小落地包 = delta-2+3+4+8**（review UC-2）—— delta-3 才让 task-spec 改读新视图；缺 delta-3，task-spec/task-execute 落地即读已删的 `solution.engineering`。四个 delta 同批，落地顺序见 §4.1。
- **delta-3 设计文档未就绪** —— delta-8 vp-3 依赖 delta-3 的 task-spec 新形态。缓解：delta-3 设计文档需先于实施定稿（与 `PRD-solution-对调.md` v1.1 §4 同一前置）。
- **本设计文档需先于实施定稿** —— 砍 `solution.engineering` 必须同时有 `implementation-design` 这个 HOW 新家。
- **待验 —— §3.4 归宿表逐章核实**：§3.4 的 10 章归宿是 review 的逐章判定，vp-1 动手前用 `solution.engineering.md.tmpl` 实际内容复核，尤其 ch6 易错点 / ch10 验收清单的实际体量是否撑得起独立段 3。

---

## §X Review Findings（autoplan / dual voice 输出落这里）

### Round 1 — 2026-05-20 — /gstack-autoplan（6 voices：CEO Codex+Claude · Eng Codex+Claude · DX Codex+Claude）

> **review 范围**：delta-8 v0（§0 已 PM 锁定）。`管线重构-GSD-review.md` §4 delta-8 + `PRD-solution-对调.md` v1.1 视为锁定上下文。
> **设计评分**：CEO 4-5/10 · Eng 4-5/10 · DX 6-7/10。**结论**：§0 成立；§1-§6 非 implementation-ready（与 delta-2+4 v0 同档）。需据本表 + 4 UC 决议修订成 v1。两个 Eng 声音均判「不建议 / 还不能按 v0 实施」。

| # | Severity | Finding 摘要 | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| D8-1 | Critical | 10→3 章归宿表被 §6 defer，但它就是设计本身：实测 `solution.engineering` 10 章只 5 章干净映射 3 段，ch6-10（易错点/plan-review沉淀/autoplan trail/a11y/工程验收）无归宿；ch7 是 live-routed（`task-spec:178`）丢 = 回归；「relocation 70-80%」按章数实为 ~55% | §0.1 §0.3 | `templates/solution.engineering.md.tmpl`（10 章）、`task-spec/SKILL.md:178` | **ACCEPT** — 10→3 归宿表移进 §3（逐章标 段1/2/3 / DESIGN.md / 删除），不可 defer |
| D8-2 | Critical | shipping-unit 自相矛盾 —— delta-2+4+8 不含 delta-3，而 delta-3 才让 task-spec 改读新视图 → task-spec/task-execute 落地即读已删的 solution.engineering | §0.3 | `管线重构:213-215`、`实现设计视图:101,119` | **ACCEPT** — UC-2：真实落地包扩成 **delta-2+3+4+8** 四者同批 |
| D8-3 | Critical | `build-execution-prompt.py`（实际 HOW 注入机制，只输出 PM 视图 + task 工程合同 2 路径）不在 vp 表；非 Claude 执行器看不到 implementation-design.md | §0.3 | `build-execution-prompt.py:84-141`、`test-executors.sh:235` | **ACCEPT** — UC-4 决议后 task-execute 不直读 implementation-design → `build-execution-prompt.py` **零改**；finding 转为 vp-test 显式断言执行信封不变、非 Claude 执行器仍只读 task 两文件 |
| D8-4 | High | task-plan 是错误宿主 —— lint 强制 PM 视图 skill（`check-doc-pm-view.py` 禁工程词、description「单一文件不生成工程合同分文件」、Rules:222 明禁）；产 TS-laden 工程 artifact = delta-2+4 §0.1 修过的同一反模式。GSD 亦把 HOW（pattern-mapper）与拆 task（planner）分开 | §0.3 | `task-plan/SKILL.md:4,154-161,222`、`GSD-参考调研.md §1.3` | **ACCEPT** — UC-1：HOW 由**独立 `/implementation-design` skill** 产出（1 文件）；task-plan 保持纯 PM 视图拆分不变 |
| D8-5 | High | task-execute 直读 implementation-design = 执行期第二 HOW 源、与 task 工程合同无 precedence | §0.3 | `task-execute/SKILL.md:281-330`、`实现设计视图:71` | **ACCEPT** — UC-4：implementation-design 只作 **task-spec 上游**；task-spec 把当前 task 的 HOW 写进自包含 task.engineering.md；task-execute 只读 task 合同（对齐 GSD executor 只读自包含 plan）|
| D8-6 | High | 选型论证默认空与 §0 冲突 —— §0.1 明列「为什么这么选」为 HOW 缺口，§3/Q4 设可选默认空 → 设计没满足自己锁定的 §0 | §0.1 | `实现设计视图:17,60,107-108` | **ACCEPT** — UC-3（重开 Q4）：架构决策表每行带最小决策字段（选择/备选/理由/约束失效条件），允许写「无非平凡备选」但不默认空 |
| D8-7 | High | 「3 段 + 章节锚点」与现役 §9.1.1 章节 grep（按 `^### 关键词` 命中 task/模块/功能名）不兼容 —— 3 个粗粒度段无 `###` anchor / row id → 整读或 0 命中 | §0.3 | `input-flow.md:180,196`、`实现设计视图:58,82` | **ACCEPT** — vp-1 现在定真可消费 schema（HOW-ID / 适用模块 / 适用 task 关键词 / 来源 / 消费者 / 优先级）；精化 Q3「章节锚点」为 HOW-ID 锚 |
| D8-8 | High | 跨 delta 撞同文件 —— task-plan/task-spec 被 delta-8 + delta-2+4 同批改、无 sequencing；vp-3 forward-ref 未设计的 delta-3 | §0.3 | `实现设计视图:96-98`、`PRD-solution-对调:172-173` | **ACCEPT** — §4 加「落地顺序与文件 ownership」段；UC-2 把 delta-3 纳入同批后，vp-3 可对齐 delta-3 真实形态而非 forward-ref |
| D8-9 | Medium | implementation-design 无 review/audit 生命周期（旧 solution.engineering 有 ch7 plan-review沉淀 + ch8 autoplan 决策表）| §0.3 | `solution.engineering.md.tmpl:156-205` | **ACCEPT** — implementation-design 加「审计与修订记录」最小节，或写入 delta-7 req 事件流 |
| D8-10 | Medium | vp-4「测试 + SOP」一行 —— 与 delta-2+4 v0 F9 同病 | §0.3 | `实现设计视图:99`、`tests/run-all.sh` | **ACCEPT** — vp-4 列 per-vp test matrix（模板 schema / producer 产出 / task-spec 派生 / 旧-req-compat IRON 回归 / grep residual / baseline）|
| D8-11 | Medium | implementation-design.md 的 PM-invisible 契约未写死 —— 模板可能被按 PM 视图规则建错；「视图」命名误导 | §0.3 | `solution.engineering.md.tmpl:6`、`实现设计视图:49` | **ACCEPT** — §3 写死：implementation-design 是工程合同性质、PM 默认不看、模板照搬 solution.engineering 的工程内容豁免；不跑 PM-view lint |
| D8-12 | Medium | §2 说易错点搬入视图、§3 三段不列它 —— 内部矛盾 | §0.3 | `实现设计视图:62,82-86` | **ACCEPT** — §3 三段明确易错点 / 反向约束的归属段 |
| D8-13 | Medium | `task.engineering.md.tmpl` §3 / `CLAUDE.md.tmpl` 硬编码 solution.engineering 引用未进 vp 表；返工 PM 缺 breadcrumb | §0.3 | `task.engineering.md.tmpl`、`CLAUDE.md.tmpl:124-127` | **ACCEPT** — vp 表纳入两模板的引用更新；vp-4 加 operator breadcrumb（≤3 行：implementation-design 是内部 AI 参考、PM 无需处理）|
| D8-14 | Low | 实现设计视图无 PM 确认门（正确，但需明说）| §0.3 | `实现设计视图:104-108` | **ACCEPT** — §3 明说 implementation-design 不设独立 PM 确认门、不进 stage-gate 确认门展示 |

**汇总**：ACCEPT 14 条 / DEFER 0 / 待 PM 决策 0（4 个 User Challenge 已 PM 决议，见 §Y）。UC-4 决议反向消解了 D8-3 的 critical（task-execute 不直读 → 执行信封零改）。

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-20 | 文档创建（AI 起草）；§0 待 PM 共写并锁定；§1 五个设计问题待逐题过 | — |
| 2026-05-20 | §0 经 PM + AI 共写并锁定；§1 五题收口 —— Q1 `implementation-design.md`、Q2 只定 3 段框架（字段留 vp-1）、Q3 章节锚点定向引用、Q4 选型论证可选默认空、Q5 stage 衔接确认 | delta-8 v0 进入可 review 状态 |
| 2026-05-20 | /gstack-autoplan 6-voice review 完成（§X Round 1）—— 14 finding：3 critical / 5 high / 5 medium / 1 low；评分 CEO 4-5 · Eng 4-5 · DX 6-7 | §1-§6 非 implementation-ready，待修订 v1 |
| 2026-05-20 | UC-1 PM 决议：HOW 由独立 `/implementation-design` skill 产出，不塞 task-plan（对齐 GSD pattern-mapper≠planner）| §1/§2/§3/§4 调整 |
| 2026-05-20 | UC-2 PM 决议：真实落地包扩成 delta-2+3+4+8 四者同批 | §4 / §6 |
| 2026-05-20 | UC-3 PM 决议（重开 Q4）：选型论证不默认空，架构决策表每行带最小决策字段（选择/备选/理由/约束）| §3 |
| 2026-05-20 | UC-4 PM 决议：implementation-design 只作 task-spec 上游，task-execute 只读 task 工程合同（对齐 GSD executor）| §2 / §3 |
| 2026-05-20 | §X D8-1~D8-14 全 ACCEPT；下一步 PM 据 §X + 4 UC 决议修订 §1-§6 成 v1 | 见 §X Round 1 |
| 2026-05-20 | v1 修订完成：§1-§6 据 §X Round 1（14 ACCEPT）+ 4 UC 决议改写 —— 独立 `/implementation-design` skill、task-spec 上游消费（task-execute 零改）、§3.4 加 10-章归宿表、段1 每行带决策字段、§3.3 定 HOW-ID schema、§4.1 加落地顺序 | 文档 v0 → v1 |

---

**End of req 级实现设计视图（delta-8）v1**

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` (via /autoplan) | Scope & strategy | 1 | issues_open | 4-5/10 — 前提确认；§1-§6 3/3 维度 flagged |
| Eng Review | `/plan-eng-review` (via /autoplan) | Architecture & tests | 1 | issues_open | 4-5/10 — "v0 还不能实施"；14 finding（3 critical）|
| DX Review | `/plan-devex-review` (via /autoplan) | Operator experience | 1 | issues_open | 6-7/10 — delta-8 PM-invisible 是对的；3 文档精度 finding |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | skipped — 无 UI scope（建 skill/模板/脚本，不建界面）|

- **CROSS-MODEL:** 6 voices（Codex ×3 + Claude subagent ×3），收敛度高 —— 两模型独立落到同样的 critical（10-章 map / shipping-unit / build-execution-prompt.py）。GSD 参考（`GSD-参考调研.md` §1.3）佐证 UC-1（pattern-mapper≠planner）+ UC-4（executor 只读自包含 plan）。
- **UNRESOLVED:** 0 —— 14 finding 全 ACCEPT；4 个 User Challenge 已 PM 决议。
- **VERDICT:** delta-8 v0 **非 implementation-ready**（与 delta-2+4 v0 同档）。§0 成立；§1-§6 需据 §X Round 1（14 ACCEPT finding + 4 UC 决议）修订成 v1。修订后重跑 /plan-eng-review 再实施。最小落地包 = **delta-2+3+4+8**。
