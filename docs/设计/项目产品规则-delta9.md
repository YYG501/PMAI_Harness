# delta-9 · 跨功能产品行为规则 + 设计规范与组件复用 (v1)

> **状态**：v1（2026-05-21）—— v0 经 GSD UI-SPEC 对照 + PM「组件不复用」实证修订：gap-check 重 framed 为「组件复用关口」、新增「DESIGN.md 模板升级」、§0 facet (B) sharpen。§1 七题全收口；§2 + §3 成文。
> **日期**：2026-05-21
> **作者**：PM + AI
> **来源**：delta-7 设计会话拆出；GSD UI-SPEC 对照（ChatBuilder `.codex/get-shit-done/workflows/ui-phase.md` + `01-UI-SPEC.md`）。
> **依赖方**：`task-spec重构.md` v2 §2.4（跨模块反馈改指本 delta）。

---

## §0 原始痛点（PM + AI 共写，后续 review **不可反向修改**）

> ⚠️ 任何后续 review / autoplan / dual voice 都**不能**给本节加东西、不能重新定义痛点。

### §0.1 痛点（1-3 句）

项目级规范有两类 —— **设计规范**（界面长什么样 + 现有组件清单，家 = `DESIGN.md`）与**跨功能产品行为规则**（全项目级「产品在 X 情况下应有 Y 行为」的规则）。两个结构性问题：

- **(A) 跨功能产品行为规则没有家** —— 现役只能塞进 task 的「跨功能产品规则」节、靠 task-spec **同模块** grep 传播，装不下「全项目级」的。
- **(B) 没有「现有组件清单」+ 没有「req 开建前查清单」的关口** —— `DESIGN.md` 现役是 6 段占位骨架、靠 close-task 事后被动 promote；新 req 在设计阶段动手时，既没有一份「全项目已做过哪些组件」的清单可查，也没有关口逐个判「这个该复用 / 该新建」。**直接后果：组件不复用**（executor 不知道前面 req 做过什么、又造一个）+ 设计规范不全。

### §0.2 触发场景

| # | 场景描述 | 证据（仓内可查 / 实证）|
|---|---|---|
| 1 | 跨功能产品行为规则被塞 task「跨功能产品规则」节、靠同模块传 —— 装不下全项目级 | `input-flow.md` §9.4；`task-spec/SKILL.md:112`；`task-spec重构.md` v2 §2.4 显式 DEFER |
| 2 | PM 在 delta-7 设计会话质疑「跨模块反馈 close-req 后失效」→ 查清其本质非 req 级事件 | 本次对话 2026-05-21；`req级事件流-delta7.md` §0.4 / §Y |
| 3 | `DESIGN.md` 只靠 close-task 事后 promote、本身是占位骨架 —— 新 req 开建时无机制保证设计规范已就位 | `input-flow.md` §9.4；`templates/DESIGN.md.tmpl`（6 段 `<!-- 占位 -->` 骨架）|
| 4 | **PM 实际遇到组件不复用** —— executor 构建新 req UI 时重造已有组件 | 本次对话 2026-05-21 PM 原述 |

### §0.3 根因（解决什么底层 mechanism）

两个机制缺失：**(a) 归位** —— 跨功能产品行为规则没有结构位；**(b) 共享清单 + 复用/完整性关口** —— 没有「现有组件 inventory」、也没有「req 开建前查 inventory 判复用 vs 新建」的关口。**组件不复用是 (b) 的直接症状**。

「视觉规范 → `DESIGN.md`」已证「项目级规范 + 项目级文档」可行；GSD 的 `ui-phase` 实证「设计阶段一道前置关口、产物锁死后才让 planner 拆 task」可行 —— delta-9 把这两块补齐。

### §0.4 不解决什么（防膨胀）

| # | 衍生 / 假设场景 | 为什么不在 §0 范围 |
|---|---|---|
| 1 | 用词 / 术语规则 | → `CONTEXT.md` 业务术语表，不进 `PRODUCT-RULES.md` |
| 2 | 视觉规范的 close-task 事后 promote 机制本身 | 已有；delta-9 加事前 gap-check + promote 改 selective，不删现役 |
| 3 | 模块级的规则 / 功能 spec | → 该模块 `modulespec`（D13）；`PRODUCT-RULES.md` 只装全项目级 |
| 4 | req 级 `decision` / `adjustment` | = delta-7 |
| 5 | 同模块前瞻反馈 / 决策结果本身 | delta-3 §2.4 lane / PRD §四 |
| 6 | **GSD 式「每 req 重新生成整份 DESIGN.md」** | 明确不做 —— `DESIGN.md` 一份累积；重新生成 = 打散共享组件清单 = reuse 死。我们 req 粒度细，多数 req 复用现有规范 |

→ **review 中任何 finding 指向以上场景的，默认 DEFER**。

---

## §1 设计问题（七题全收口）

| # | 设计问题 | 决议 |
|---|---|---|
| Q1 | `PRODUCT-RULES.md` 形态 | ✓ §2.1 |
| Q2 | 规则条目结构 | ✓ §2.2 |
| Q3 | 谁写 | ✓ §2.3 |
| Q4 | 谁读 | ✓ §2.4 |
| Q5 | 识别机制 | ✓ §2.5 |
| Q6 | 设计阶段 gap-check（= 组件复用关口）| ✓ §2.6 + §2.7 |
| Q7 | 衔接与边界 | ✓ §2.8 |

---

## §2 方案主体

### §2.1 `PRODUCT-RULES.md` 形态（Q1）

- **新建 `docs/PRODUCT-RULES.md`** —— 项目级、markdown、规则累积式文档，装**全项目跨功能产品行为规则**。与 `docs/DESIGN.md` 平级。
- **不是事件流** —— 活的规则文档（读 + 累积 + 偶尔修订），不是 append-only jsonl（jsonl 是 delta-7）。
- **不扩 `DESIGN.md` / 不塞 `CONTEXT.md`** —— 设计规范 ≠ 产品行为规则；`CONTEXT.md` 是稳定基线。

### §2.2 规则条目结构（Q2）

`PRODUCT-RULES.md` = **全项目规则的扁平清单**（无模块分区 —— 模块级的 → modulespec）。每条：

```markdown
### <一句话标题>
- 规则：<产品在 X 情况下应 / 不应 Y>
- 来源：req-NNN / task-NNN（YYYY-MM-DD）
```

- **无「状态」「scope」字段** —— 规则全是全项目、常驻；加入即生效，过时由 PM 手动改 / 删。

### §2.3 谁写（Q3）

- **close-task PM-selective promote** —— close-task 收尾扫该 task `## PM 反馈`，**逐条让 PM 选**哪些「跨功能产品行为规则」promote 到 `PRODUCT-RULES.md`（PM 选，不 auto）。
- 与 close-task 步骤 1.5「视觉规范 → `DESIGN.md`」同型 —— delta-9 给 close-task 加一条平行 selective promote。

### §2.4 谁读（Q4）

| 读者 | 何时 | 读什么 |
|---|---|---|
| task-spec | 生成每个 task 时 | `PRODUCT-RULES.md` 全文（扁平清单，体量小）|
| prd-writing | 写 PRD 时（stage 3）| `PRODUCT-RULES.md` 全文 —— PRD 一次写对、不违背常驻规则 |

`PRODUCT-RULES.md` 进 task-spec + prd-writing 必读清单。

### §2.5 识别机制（Q5）

close-task 收尾逐条过 `## PM 反馈`：**AI 预判去向 + PM 确认 / 改**（不纯 AI 自动分类，避免误报；不让 PM 冷启动）。delta-9 关心的是识别「全项目跨功能产品行为规则」一类 → `PRODUCT-RULES.md`。完整多去向 routing 见 §2.8。

### §2.6 设计阶段 gap-check = 组件复用关口（Q6）

gap-check 的本质 = **每个 req 一道「逐组件判复用 vs 新建」的关口**（不只「查规范全不全」）。

| 维度 | 设计 |
|---|---|
| 何时 | **stage 4（设计系统）** —— req 进设计阶段时跑 |
| 怎么做 | 读 PRD（stage 3 产出）枚举本 req 要建的**界面 / 交互 / 组件**；逐个对 `DESIGN.md` 的「组件规范 / 设计规范」inventory 判定 |
| 逐组件判定 | inventory 里**有** → **复用**（设计输出指向它）；**没有** → **新建** + 加进 `DESIGN.md` inventory |
| 缺设计规范 | 缺的（布局 / 交互 / 无障碍 / 新组件）→ AI 列、PM 逐个表态：补（写进 `DESIGN.md`）/ 显式跳过 |
| 产物 | 一份 **per-req 组件复用清单**（本 req：复用 A / B、新建 C），记进 PRD 原型节（与产物预览同处，codex#5）|
| 硬度 | 不硬卡出 stage 4，但**强制 PM 对每个「缺 / 新建」逐个表态** —— 不能 silent 忽略 |
| 前提 | `DESIGN.md` 须先升级成「有明确块的具体合约」（§2.7）—— 否则 gap-check 无 inventory 可查 |

**这道关口怎么解「组件不复用」**：每个 req 动手前,被强制逐组件查一遍现有 inventory —— 有就复用、没有才新建并入库。inventory 随 req 累积越来越全,reuse 率随之上升。

### §2.7 `DESIGN.md` 模板升级（借鉴 GSD UI-SPEC）

现役 `templates/DESIGN.md.tmpl` = 6 段 `<!-- 占位 -->` 骨架，粗、无强制结构、gap-check 无可查。升级（借 GSD `UI-SPEC.md` 的合约形态）：

- **补块** —— 加 **布局合约 / 响应式 / 无障碍**（纯视觉层块，我们缺、GSD 有）。
- **「组件规范」段 → 共享组件 inventory** —— 每个组件一条目（名 / 用途 / 长什么样 / 出处 req），累积。**这就是 §2.6 gap-check 查的那份清单。**
- **占位 → 具体合约** —— 每个值具体化（hex / px / size-weight），执行期不许偏离（GSD 叫 Contract，不是 guideline）。
- **加 Checker Sign-Off** —— `DESIGN.md` 定稿过一道几维检查（借 GSD `gsd-ui-checker` 的 6 维思路）。
- **保留「创意自由度」段** —— GSD UI-SPEC **没有**这块；我们独有（防 agent 一板一眼），不丢。
- **不照搬** —— GSD 的「交互合约 / 文案合约」不全搬：功能交互归 PRD、文案 / 术语归 PRD + `CONTEXT.md` 术语表；`DESIGN.md` 只管**视觉层交互**（hover / 动效 / 焦点环）与**文案呈现规则**。
- **一份累积、不每 req 重生成**（§0.4.6）。

### §2.8 衔接与边界（Q7）

**close-task 时 PM 反馈的完整多去向 routing**（delta-9 新增「产品行为规则」一条）：

| 反馈类型 | 去向 | 谁管 |
|---|---|---|
| 视觉 / 设计 / 交互样式 / 新组件 | `DESIGN.md` | 现役 close-task 1.5 + delta-9 gap-check（§2.6）|
| 用词 / 术语 | `CONTEXT.md` 业务术语表 | `term-detector`（现役）|
| 全项目跨功能产品行为规则 | `PRODUCT-RULES.md` | **delta-9（§2.3）**|
| 模块级规则 / 功能 spec | 该模块 `modulespec` | D13 / doc-update（现役）|
| task-local / 同模块前瞻 | 留 task 文件 | delta-3 §2.4 同模块 lane |

边界要点：
- `PRODUCT-RULES.md` 只装全项目级；模块级 → `modulespec`。
- 用词 / 术语不进 `PRODUCT-RULES.md`。
- 现役四类（`input-flow.md` §9.4）被 supersede —— delta-3 + delta-9 共同改写。
- delta-3 §2.4「跨模块反馈」已改指 delta-9（已落地）。
- **与 GSD 的差异**：GSD 每 phase 重生成 UI-SPEC；我们一份累积 `DESIGN.md` + 每 req gap-check —— req 粒度细，累积清单才是 reuse 的底座。

---

## §3 实施清单

| vp | 改什么 | 依据 |
|---|---|---|
| vp-1 | 新建 `docs/PRODUCT-RULES.md` + 模板（全项目跨功能产品行为规则，扁平清单）| §2.1 §2.2 |
| vp-2 | close-task 加 selective promote —— 收尾扫 `## PM 反馈`，AI 预判 + PM 逐条选「产品行为规则」→ `PRODUCT-RULES.md` | §2.3 §2.5 |
| vp-3 | task-spec + prd-writing 必读清单加 `PRODUCT-RULES.md` | §2.4 |
| vp-4 | **`DESIGN.md` 模板升级** —— `templates/DESIGN.md.tmpl` 从占位骨架 → 具体合约：补 布局/响应式/无障碍 块；「组件规范」段做成累积式组件 inventory（条目 schema）；各块具体值化；加 Checker Sign-Off；保留「创意自由度」段 | §2.7 |
| vp-5 | **设计阶段 gap-check = 组件复用关口** —— stage 4 加一步：读 PRD 枚举界面/组件、逐个对 `DESIGN.md` inventory 判复用/新建、缺则强制 PM 表态、产 per-req 组件复用清单 | §2.6 |
| vp-6 | 测试 + SOP + 连带 —— `PRODUCT-RULES.md` / `DESIGN.md` 升级模板测试；close-task promote、gap-check fixture；`框架同步-SOP.md` 补 delta-9 段；`input-flow.md` §9.4 routing 改写（与 delta-3 协调）| §2.8 |

**落地顺序**：vp-4（DESIGN.md 升级，gap-check 的前提）→ vp-1 / vp-5（PRODUCT-RULES.md / gap-check）→ vp-2 / vp-3（写 / 读）→ vp-6（测试 + 连带）。

**消费侧衔接**：close-task / task-spec / prd-writing / req-stage-gate（stage 4）—— 与 delta-2+4、delta-3 撞同文件，整包实施按 umbrella §8 协调。

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
| 2026-05-21 | §0 锁定；Q1-Q5 逐题过；PM re-scope（设计规范 ≠ 产品规则、selective 沉淀、gap-check 纳入）| 见 §2.1-§2.5 |
| 2026-05-21 | PM 钉死定义：`PRODUCT-RULES.md` = 全项目跨功能产品行为规则；用词→术语表、模块级→modulespec | §0 / §2 定义贯通 |
| 2026-05-21 | v0 → **v1**：GSD UI-SPEC 对照（ChatBuilder `.codex` vendored GSD）—— GSD 有专门 `ui-phase` + per-phase UI-SPEC（11 块具体合约 + 6 维 Checker）。借鉴：① gap-check 重 framed 为「**组件复用关口**」（逐组件判复用/新建 + 产 per-req 复用清单），对症 PM 实证的「组件不复用」；② 新增 vp-4「`DESIGN.md` 模板升级」（补块 + 具体合约化 + 组件 inventory + Checker；保留我们独有的「创意自由度」）；③ §0 facet (B) sharpen（补「组件清单」缺口 + §0.2 场景 4 实证）；④ §0.4 明确不抄 GSD「每 req 重生成」。delta-9 v0 → v1 设计完成 | §0 / §2.6 / §2.7 / §3 |

---

**End of delta-9 · 跨功能产品行为规则 + 设计规范与组件复用 v1**
