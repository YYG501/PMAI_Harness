# req 级实现设计视图（delta-8 · HOW 安家）(v0)

> **状态**：v0 —— §0 经 PM + AI 共写并锁定（2026-05-20）；§1 五个设计问题全收口；待 review（autoplan / plan-eng-review）。前置：与 delta-2+4 同批落地（见 §6）。
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

「拆 task」步骤（`task-plan`，stage 5）顺带产出一份 req 级**实现设计视图**单文件（`implementation-design.md`，落 `$ACTIVE_REQ_DIR/`），承接原 `solution.engineering.md` 的 HOW 内容。`task-spec` / `task-execute` 从「整读 `solution.engineering`」改成「**定向引用**实现设计视图」。

**性质 = relocation，不是 net-add**：`solution.engineering` 今天已覆盖约 70-80% 的 HOW，delta-8 把它挪到新位置 + 改在 task-plan 时机产出。唯一真 net-add = 可选的「选型论证」段。

### §1.1 设计问题（§1 五题已收口 —— 2026-05-20）

| # | 设计问题 | 决议 |
|---|---|---|
| Q1 | 文件名 | **`implementation-design.md`**（落 `$ACTIVE_REQ_DIR/`）|
| Q2 | 3 段 schema 定到多细 | **只定 3 段框架**（见 §3）；字段级 schema 留 vp-1 模板设计时定 |
| Q3 | task-spec / task-execute「定向引用」机制 | **章节锚点引用** —— 按 §段锚点定向读，跟仓内「只读 `tasks/*.md` 的 §📋/§🎯/§✅ 三段」同一模式 |
| Q4 | 选型论证段是否默认产出 | **可选段、默认空**（umbrella §4 delta-8 已定）|
| Q5 | 与 delta-2+4 的 stage 衔接 | `task-plan`（stage 5）产出；PRD（stage 3 冻结）；task-spec（stage 6）读 PRD(WHAT) + 实现设计视图(HOW)，无冲突 |

---

## §2 与现有机制的关系

| 机制 | 处理 | 备注 |
|---|---|---|
| `solution.engineering.md` / `.tmpl` | delta-4 砍 | 其 10 章里的 req 级 HOW（数据结构定义 / 派生状态规则 / 组件实现路径 / Mock 改造 / 关键算法消费规则 / 易错点反向约束）→ 挪进实现设计视图 |
| `task-plan` | **改** | 拆 task 时顺带产出实现设计视图 |
| `task-spec` | **改** | 从「读 `solution.engineering`」改成「**章节锚点定向引用**实现设计视图」（与 delta-3 协同）|
| `task-execute` | **改** | 执行时按 §段锚点定向读实现设计视图，不整读 |
| `modulespec`（D13）| **不变** | modulespec 是模块级稳定档；实现设计视图是 req 级一次性 HOW，两层不同 |
| req 级 PRD（delta-2）| **不变** | PRD = req 级功能规格（WHAT）；实现设计视图 = req 级 HOW。WHAT / HOW 分离，互相引用不重抄 |

---

## §3 form：实现设计视图的结构（umbrella 已定 = 1 文件 3 段）

单文件，内部 3 段：

- **段 1 · 架构决策表** —— 这个 req 用什么架构取向、技术选择（承接 `solution.engineering` 的「数据结构定义 / 派生状态规则」等）。
- **段 2 · 文件·模式索引** —— 照哪些现有代码 / 模式写（承接「组件实现路径 / Mock 改造清单 / 关键算法消费规则」）。
- **段 3 · 选型论证（可选）** —— 为什么选 X 不选 Y。唯一真 net-add；默认空，有非平凡取舍时才填。

以上 3 段是 design-level 框架（Q2 决议）；每段的字段级 schema 由 vp-1 模板设计时定，参照 `solution.engineering.md.tmpl` 现有 10 章。task-spec / task-execute 按 §段锚点定向引用（Q3 决议）—— 故 3 段锚点须稳定。

**为什么不分 3 文件**：GSD 分 3 文件是因为每个 artifact 配一个专属 agent（文件边界 = agent 边界）；我们的 `task-plan` 是主 AI 一气写完，无此架构，分 3 文件 = cargo-cult（同 umbrella §4 delta-8 / `PRD-solution-对调.md` §2.2 拒绝 GSD 多文件拆分的同一理由）。

---

## §4 实施清单

| vp | 改什么 | 依据 |
|---|---|---|
| vp-1 | 实现设计视图模板（`templates/`，3 段结构）| §3 |
| vp-2 | `task-plan` 加产出实现设计视图 | §1 §2 |
| vp-3 | `task-spec` / `task-execute` 改**章节锚点定向引用**实现设计视图（与 delta-3 协同）| §2（Q3）|
| vp-4 | 测试 + `框架同步-SOP.md` 补迁移段 | §6 |

**依赖**：与 delta-2+4 同批落地（`PRD-solution-对调.md` v1.1 review UC-2）；vp-3 与 delta-3 协同。

---

## §5 砍掉 / 不做的机制清单（防 review 回写）

1. ❌ 不分 GSD 式 3 文件 —— 单文件 3 段
2. ❌ 选型论证不强制 —— 可选段，默认空
3. ❌ 不引入专属 agent —— `task-plan` 主线程一气产出
4. ❌ 不动 `modulespec`（D13）—— 不同层
5. ❌ 实现设计视图不重复 PRD 的 WHAT —— 引用，不重抄

→ 任何 review finding 想恢复以上任一条，必须 PM 显式更新 §0 并 v0 → v1。

---

## §6 风险与待验

- **必要性挂 delta-3**（umbrella §4 delta-8）：delta-3 通过 → delta-8 必做；delta-3 若否（task 继续背 HOW）→ delta-8 可选。当前 delta-3 已 PM 判定通过（umbrella §4.2），故 delta-8 必做。
- **与 delta-2+4 同批**：`PRD-solution-对调.md` v1.1 §X review 把 delta-8 列为 delta-2+4 最小可落地包成员（砍 `solution.engineering` 必须同时有 HOW 新家）。**本设计文档需先于 delta-2+4 实施定稿。**
- **待验 —— solution.engineering 10 章归宿表**：动手前做一张表，逐章判定 `solution.engineering.md.tmpl` 10 章里多少是「req 级 HOW」（挪进实现设计视图）、多少该直接删或归别处（如 a11y / 视口 / 视觉细则可能归 `DESIGN.md`）。
- **relocation 比例**（70-80%）是 umbrella 估计，动手前核实。

---

## §X Review Findings（autoplan / dual voice 输出落这里）

> 每条 finding 必须按下表格式。**PAIN_LINK = NONE 且 EVIDENCE = ASSUMED 的 finding 默认 [DEFER]**，不进方案主体。

| # | Severity | Finding 摘要 | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| - | - | （待 review）| - | - | - |

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-20 | 文档创建（AI 起草）；§0 待 PM 共写并锁定；§1 五个设计问题待逐题过 | — |
| 2026-05-20 | §0 经 PM + AI 共写并锁定；§1 五题收口 —— Q1 `implementation-design.md`、Q2 只定 3 段框架（字段留 vp-1）、Q3 章节锚点定向引用、Q4 选型论证可选默认空、Q5 stage 衔接确认 | delta-8 v0 进入可 review 状态 |

---

**End of req 级实现设计视图（delta-8）v0**
