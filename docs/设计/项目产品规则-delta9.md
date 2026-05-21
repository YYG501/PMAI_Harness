# delta-9 · 跨功能产品行为规则 + 设计规范完整性 (v0)

> **状态**：v0 设计完成（2026-05-21）—— §0 已锁定；§1 七题全收口；§2 + §3 成文。待 review / 实施。
> **日期**：2026-05-21
> **作者**：PM + AI
> **来源**：delta-7 设计会话（2026-05-21）拆出；经 PM 多轮 re-scope 定形。
> **依赖方**：`task-spec重构.md` v2 §2.4（跨模块反馈原 DEFER 到 delta-7，改指本 delta）。

---

## §0 原始痛点（PM + AI 共写，后续 review **不可反向修改**）

> ⚠️ 任何后续 review / autoplan / dual voice 都**不能**给本节加东西、不能重新定义痛点。

### §0.1 痛点（1-3 句）

项目级规范有两类 —— **设计规范**（界面长什么样，家 = `DESIGN.md`）与**跨功能产品行为规则**（全项目级「产品在 X 情况下应有 Y 行为」的规则，如「危险操作二次确认」「列表默认可搜索」「异步操作有 loading 态」）。两个结构性问题：

- **(A) 跨功能产品行为规则没有家** —— 现役只能把它塞进 task 的「跨功能产品规则」节、靠 task-spec **同模块** grep 传播，装不下「全项目级」的跨功能行为规则。
- **(B) 没有「req 开建前保证设计规范齐」的关口** —— `DESIGN.md` 现役全靠 close-task 事后被动 promote 累积；新 req 在设计阶段动手时，没有机制 check 它要建的界面所需的设计规范是否已就位。

### §0.2 触发场景

| # | 场景描述 | 证据（仓内可查 / 实证）|
|---|---|---|
| 1 | 跨功能产品行为规则被塞 task「跨功能产品规则」节、靠同模块传 —— 装不下全项目级 | `input-flow.md` §9.4 四类分流；`task-spec/SKILL.md:112` 同模块 grep；`task-spec重构.md` v2 §2.4 显式 DEFER |
| 2 | PM 在 delta-7 设计会话（2026-05-21）质疑「跨模块反馈 close-req 后失效」→ 查清其本质非 req 级事件 | 本次对话 2026-05-21；`req级事件流-delta7.md` §0.4 / §Y |
| 3 | `DESIGN.md` 只靠 close-task 事后 promote 视觉规范 —— 新 req 开建时无机制保证它需要的设计规范已在 `DESIGN.md` | `input-flow.md` §9.4（视觉规范第四类 close-task 反推 DESIGN.md）|

### §0.3 根因（解决什么底层 mechanism）

项目级规范缺两个机制：**(a) 归位** —— 跨功能产品行为规则没有结构位（设计规范有 `DESIGN.md`、跨功能行为规则无对应文档）；**(b) 完整性关口** —— 没有在 req 设计阶段 check 设计规范齐不齐的机制，全靠事后被动累积。「视觉规范 → `DESIGN.md`」已证「项目级规范 + 项目级文档」可行 —— delta-9 把它补全（跨功能行为规则给家）并加事前完整性关口。

### §0.4 不解决什么（防膨胀）

| # | 衍生 / 假设场景 | 为什么不在 §0 范围 |
|---|---|---|
| 1 | 用词 / 术语规则（「统一用 X」「不混用 Y」）| → `CONTEXT.md` 业务术语表（术语表 = 规范词 + 禁用变体），**不进 `PRODUCT-RULES.md`** |
| 2 | 视觉 / 设计 / 交互样式 | → `DESIGN.md`；delta-9 加事前 gap-check + promote 改 selective，不改 `DESIGN.md` 格式 |
| 3 | 模块级的规则 / 功能 spec | → 该模块 `modulespec`（D13）；`PRODUCT-RULES.md` 只装全项目级 |
| 4 | req 级 `decision` / `adjustment` | = delta-7 |
| 5 | 同模块前瞻反馈 | delta-3 §2.4 同模块 lane 已装 |
| 6 | 决策**结果**本身的归宿 | = PRD §四（delta-2+4 已定）|

→ **review 中任何 finding 指向以上场景的，默认 DEFER**（除非 PM 显式接受拉进 §0）

---

## §1 设计问题（七题全收口）

| # | 设计问题 | 决议 |
|---|---|---|
| Q1 | `PRODUCT-RULES.md` 形态 | ✓ §2.1 |
| Q2 | 规则条目结构 | ✓ §2.2 |
| Q3 | 谁写 | ✓ §2.3 |
| Q4 | 谁读 | ✓ §2.4 |
| Q5 | 识别机制 | ✓ §2.5 |
| Q6 | 设计阶段 gap-check | ✓ §2.6 |
| Q7 | 衔接与边界 | ✓ §2.7 |

---

## §2 方案主体

### §2.1 `PRODUCT-RULES.md` 形态（Q1）

- **新建 `docs/PRODUCT-RULES.md`** —— 项目级、markdown、规则累积式文档，装**全项目跨功能产品行为规则**。与 `docs/DESIGN.md` 平级（DESIGN.md = 设计规范，PRODUCT-RULES.md = 跨功能产品行为规则）。
- **不是事件流** —— 活的规则文档（读 + 累积 + 偶尔修订），不是 append-only jsonl（jsonl 是 delta-7）。

### §2.2 规则条目结构（Q2）

`PRODUCT-RULES.md` = **全项目规则的扁平清单**（无模块分区 —— 跨功能产品行为规则天然全项目；模块级的 → modulespec，见 §2.7）。每条：

```markdown
### <一句话标题>
- 规则：<产品在 X 情况下应 / 不应 Y>
- 来源：req-NNN / task-NNN（YYYY-MM-DD）
```

- **无「状态」字段、无「scope」字段** —— 规则全是全项目、常驻；加入即生效，过时由 PM 手动改 / 删（同 `DESIGN.md`）。

### §2.3 谁写（Q3）

- **close-task PM-selective promote** —— close-task 收尾扫该 task 的 `## PM 反馈`，**逐条让 PM 选**哪些「跨功能产品行为规则」promote 到 `PRODUCT-RULES.md`（PM 选，不 auto —— 「向上沉淀有选择」）。
- 与 close-task 步骤 1.5「视觉规范 → `DESIGN.md`」同型 —— delta-9 给 close-task 加一条平行的 selective promote。
- 单一写入点 = close-task；PM 可随时手动编辑 `PRODUCT-RULES.md`。

### §2.4 谁读（Q4）

| 读者 | 何时 | 读什么 |
|---|---|---|
| task-spec | 生成每个 task 时 | `PRODUCT-RULES.md` 全文（扁平清单，体量小）|
| prd-writing | 写 PRD 时（stage 3）| `PRODUCT-RULES.md` 全文 —— PRD 一次写对、不违背常驻规则 |

`PRODUCT-RULES.md` 进 task-spec + prd-writing 必读清单。

### §2.5 识别机制（Q5）

close-task 收尾，逐条过 `## PM 反馈`：**AI 预判每条去向、PM 确认 / 改**（不纯 AI 自动分类——避免误报，memory `judgment-pattern-not-mechanization`；不让 PM 冷启动）。delta-9 关心的是识别出「**全项目跨功能产品行为规则**」这一类 → promote 到 `PRODUCT-RULES.md`。完整的多去向 routing 见 §2.7。

### §2.6 设计阶段 gap-check（Q6）

| 维度 | 设计 |
|---|---|
| 何时 | **stage 4（设计系统）** —— req 进设计阶段时跑 |
| 怎么做 | 读 PRD（stage 3 产出）枚举本 req 要建的界面 / 交互类型；对每个 check `DESIGN.md` 有无对应设计规范 |
| AI 提、PM 决 | AI 列「`DESIGN.md` 缺 X、Y 的规范」，PM 逐个表态：补（写进 `DESIGN.md`）/ 显式跳过 |
| 硬度 | **不硬卡出 stage 4**，但**强制 PM 对每个缺口逐个表态**（补 / 显式跳过）—— 不能 silent 忽略（对齐 memory `feedback_open_questions_gate` 精神）|
| 范围 | **只 check `DESIGN.md`**；`PRODUCT-RULES.md` 是常驻规则、直接读（Q4），无「本 req 没覆盖」一说 |

### §2.7 衔接与边界（Q7）

**close-task 时 PM 反馈的完整多去向 routing**（delta-9 只新增其中一条）：

| 反馈类型 | 去向 | 谁管 |
|---|---|---|
| 视觉 / 设计 / 交互样式 | `DESIGN.md` | 现役 close-task 步骤 1.5 + delta-9 gap-check（§2.6）|
| 用词 / 术语 | `CONTEXT.md` 业务术语表 | `term-detector`（现役）|
| 全项目跨功能产品行为规则 | `PRODUCT-RULES.md` | **delta-9（§2.3）**|
| 模块级的规则 / 功能 spec | 该模块 `modulespec` | D13 / doc-update（现役）|
| task-local / 同模块前瞻 | 留 task 文件 | delta-3 §2.4 同模块 lane |

边界要点：
- **`PRODUCT-RULES.md` 只装全项目级** —— 模块级的东西 → 该模块 `modulespec`（避免「一个模块两个家」）。
- **用词 / 术语 不进 `PRODUCT-RULES.md`** —— 那是业务术语表的活。
- **现役四类（`input-flow.md` §9.4）被 supersede** —— delta-3 §2.4 已把前三类 → relevance 二分；delta-9 把 close-task routing 定为上表多去向。§9.4 由 delta-3 + delta-9 共同改写。
- **delta-3 §2.4「跨模块反馈 DEFER 到 delta-7」→ 改指 delta-9** —— 连带 todo（delta-3 v2→v3）。

---

## §3 实施清单

| vp | 改什么 | 依据 |
|---|---|---|
| vp-1 | 新建 `docs/PRODUCT-RULES.md` + 模板（全项目跨功能产品行为规则，扁平清单，条目 = 规则文本 + 来源）| §2.1 §2.2 |
| vp-2 | close-task 加 selective promote —— 收尾扫 `## PM 反馈`，AI 预判 + PM 逐条选「跨功能产品行为规则」→ `PRODUCT-RULES.md`（平行现役 视觉规范→DESIGN.md）| §2.3 §2.5 |
| vp-3 | task-spec + prd-writing 必读清单加 `PRODUCT-RULES.md` | §2.4 |
| vp-4 | **设计阶段 gap-check** —— stage 4 加一步：读 PRD 枚举本 req 界面、check `DESIGN.md` 覆盖、列缺口、强制 PM 逐个表态（补 / 跳过）| §2.6 |
| vp-5 | 测试 + SOP + 连带 —— `PRODUCT-RULES.md` 模板测试 / close-task promote fixture / gap-check fixture；`框架同步-SOP.md` 补 delta-9 段；连带：delta-3 §2.4 改指 delta-9（v2→v3）、`input-flow.md` §9.4 routing 改写（与 delta-3 协调）| §2.7 |

**落地顺序**：vp-1（建文档）→ vp-2 / vp-3 / vp-4（写入 / 读取 / gap-check，互相独立）→ vp-5（测试 + 连带收尾）。

**消费侧衔接**：close-task / task-spec / prd-writing / req-stage-gate（stage 4）—— delta-9 与 delta-2+4（prd-writing）、delta-3（task-spec / input-flow.md §9.4）撞同文件，整包实施时按 umbrella §8 顺序协调。

---

## §X Review Findings（autoplan / dual voice 输出落这里）

> 每条 finding 按 `_模板-方案.md` §X 格式。**PAIN_LINK = NONE 且 EVIDENCE = ASSUMED 的 finding 默认 DEFER**。

### Round N — <YYYY-MM-DD> — <reviewer voice>

| # | Severity | Finding 摘要 | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| - | - | （待 review）| - | - | - |

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-21 | 文档创建；delta-9 从 delta-7 拆出（跨模块反馈本质非 req 级事件）| — |
| 2026-05-21 | §0 首次锁定（痛点 = 跨模块产品规则无家）；Q1-Q4 逐题过 | 见 §2.1-§2.4 |
| 2026-05-21 | **PM re-scope**：① 设计规范 ≠ 产品规则 —— 设计规范归 `DESIGN.md`；② 向上沉淀改 PM-selective；③「设计阶段 gap-check」纳入 delta-9 | §0 重锁两 facet；§1 加 Q6 |
| 2026-05-21 | **PM 钉死定义**：`PRODUCT-RULES.md` = **全项目跨功能产品行为规则**（「产品在 X 情况应有 Y 行为」）；用词/术语 → `CONTEXT.md` 术语表（不进 PRODUCT-RULES）；模块级 → modulespec（PRODUCT-RULES 无模块段，refines Q2）| §0/§2 定义贯通；Q7 收口 |
| 2026-05-21 | Q5（识别：AI 预判 + PM 确认）/ Q6（gap-check）/ Q7（衔接与边界 + 多去向 routing）逐题过定稿；§1 七题全收口，§2 + §3 成文。**delta-9 v0 设计完成** | 设计定稿 |

---

**End of delta-9 · 跨功能产品行为规则 + 设计规范完整性 v0**
