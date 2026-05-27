# delta-9 · 跨功能产品行为规则 + 设计规范与组件复用 (v2)

> **状态**：v2 设计完成（2026-05-21）—— v1 经 /gstack-plan-eng-review 全审（§X Round 1，9 ACCEPT / 1 DEFER），§2/§3 据 finding 修订：gap-check 产物不写冻结 PRD（D9-1）、gap-check 与 skippable stage 4 解耦（D9-2）、加 legacy DESIGN.md 迁移 vp（D9-3）、vp-2 补 worktree-clean blast radius（D9-4）、§2.2 加 scope 字段 + §2.4 改章节-grep（D9-6）、delta-8 输入加 DESIGN.md（D9-7）、prd-writing 加候选 promote 入口（D9-8）、vp-6 升 per-vp test matrix（D9-9）。§0 锁定不动。**可实施**。
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

### §2.2 规则条目结构（Q2 · v2 据 §X D9-6 修订）

`PRODUCT-RULES.md` = **全项目规则的扁平清单**（无模块分区 —— 模块级的 → modulespec）。每条：

```markdown
### <一句话标题>
- 规则：<产品在 X 情况下应 / 不应 Y>
- scope：全局 | 域限定:<关键词>
- 来源：req-NNN / task-NNN（YYYY-MM-DD）
```

- **`scope` 字段**（§X D9-6 新增）—— 取值「全局」或「域限定:<关键词>」。供 §2.4 task-spec 章节-grep 收敛用：「全局」规则每 task 必读、「域限定」规则按 task 关键词 grep 命中才读。**跨功能规则按定义标「全局」、永不漏读**；只有明确只约束某域的规则才标「域限定」。v1 原写「无 scope 字段」，§X D9-6 推翻 —— 否则 task-spec 全文读累积式文件、长项目 per-task 读取成本隐性涨。
- **无「状态」字段** —— 规则全是常驻；加入即生效，过时由 PM 手动改 / 删。

### §2.3 谁写（Q3 · v2 据 §X D9-4 / D9-8 修订）

两个写入口（皆 PM-selective —— AI 预判 + PM 逐条选，不 auto）：

- **① close-task PM-selective promote** —— close-task 收尾扫该 task `## PM 反馈`（delta-3 后在审计区·历史档案），**逐条让 PM 选**哪些「跨功能产品行为规则」promote 到 `PRODUCT-RULES.md`。与 close-task 步骤 1.5「视觉规范 → `DESIGN.md`」同型 —— delta-9 给 close-task 加一条平行 selective promote。
  - **⚠️ blast radius（§X D9-4）**：步骤 1.5 patch `DESIGN.md` 是 patch-不-commit、靠 carry-forward 带到 req worktree；现役 close-task 步骤 2.1 worktree-clean 检查 + `close-task.sh` carry-forward 只白名单 `docs/DESIGN.md`。delta-9 加 PRODUCT-RULES promote 必须**同步把 `docs/PRODUCT-RULES.md` 加进** close-task SKILL §2.1 worktree-clean 白名单 + `close-task.sh` carry-forward / clean-check —— 否则未 commit 的 PRODUCT-RULES.md 拌倒 worktree-clean（commit `6382baf` 已为 DESIGN.md 修过同类 bug）。详 §3 vp-2。
- **② prd-writing 规划期 candidate promote**（§X D9-8 新增）—— prd-writing @ stage 3 写 PRD 时，若发现「全项目跨功能产品行为规则」（非某 task 的 PM 反馈、而是规划期讨论里浮出），PM-selective promote 到 `PRODUCT-RULES.md`。补「规划期发现的规则无沉淀路径」缺口。由 delta-9 自己在 umbrella step 6 加（patch 已重写完的 prd-writing，**不并入 delta-2+4 vp-3** —— `PRODUCT-RULES.md` 由 vp-1 在 step 6 创建，delta-2+4 vp-3 在 step 2 forward-ref 不到）。详 §3 vp-3。

### §2.4 谁读（Q4 · v2 据 §X D9-6 修订）

| 读者 | 何时 | 读什么 |
|---|---|---|
| task-spec | 生成每个 task 时 | 全部 `scope=全局` 规则 + 按当前 task 模块/功能关键词 **grep 命中**的 `scope=域限定` 规则（§2.2 scope 字段；不再全文读 —— §X D9-6）|
| prd-writing | 写 PRD 时（stage 3）| `PRODUCT-RULES.md` 全文 —— PRD 一次写对、不违背常驻规则（prd-writing per-req 跑一次、非 per-task，全文读可接受）|

- task-spec 的章节-grep 复用 `input-flow.md §9.1.1` 的 `^### 关键词` grep 机制；`scope=全局` 永远纳入（跨功能规则不漏），`scope=域限定` 才按 task 关键词筛 —— 收敛但不漏跨功能规则。
- `PRODUCT-RULES.md` 进 task-spec + prd-writing 必读清单 —— 由 delta-9 vp-3 在 umbrella step 6 后置增补已重写完的两个 skill（非参与其 rewrite，§3 vp-3 / §X D9-5）。

### §2.5 识别机制（Q5）

close-task 收尾逐条过 `## PM 反馈`：**AI 预判去向 + PM 确认 / 改**（不纯 AI 自动分类，避免误报；不让 PM 冷启动）。delta-9 关心的是识别「全项目跨功能产品行为规则」一类 → `PRODUCT-RULES.md`。完整多去向 routing 见 §2.8。

### §2.6 设计阶段 gap-check = 组件复用关口（Q6 · v2 据 §X D9-1 / D9-2 / D9-3 修订）

gap-check 的本质 = **每个 req 一道「逐组件判复用 vs 新建」的关口**（不只「查规范全不全」）。

| 维度 | 设计 |
|---|---|
| 何时 | **每 req 无条件跑**（§X D9-2）—— stage 4 拆两块：**(必跑) gap-check 组件复用关口** +**(可选) DESIGN.md 视觉规范更新**。现役 Stage 3→4 gate「PM 说不用 → 跳过 stage 4」只跳过后者；gap-check 不受「设计系统要不要更新」影响。触发条件 =「每 req 都要建界面/组件」（永真），不是「设计要不要改」。v1 原把 gap-check 整个挂 stage 4、随 stage 4 被跳过 —— §X D9-2 推翻（否则组件复用关口在 reuse-heavy req 上永不触发，恰是该修的场景）|
| 怎么做 | 读 PRD（stage 3 产出）枚举本 req 要建的**界面 / 交互 / 组件**；逐个对 `DESIGN.md` 的组件 inventory 判定 |
| 逐组件判定 | inventory 里**有** → **复用**（设计输出指向它）；**没有** → **新建** + 加进 `DESIGN.md` inventory |
| 缺设计规范 | 缺的（布局 / 交互 / 无障碍 / 新组件）→ AI 列、PM 逐个表态：补（写进 `DESIGN.md`）/ 显式跳过 |
| 产物 | gap-check 是**交互关口** —— 产物 = PM 在 chat 逐组件表态这个过程本身 + **新建组件入 `DESIGN.md` inventory**（持久化的只有这个）。**不单独落 per-req 文件、不写 PRD**（§X D9-1）—— v1 原写「记进 PRD 原型节」，但 delta-2+4 §2.5「PRD stage 3 定稿冻结」、F19 禁写回冻结 PRD 基准；gap-check stage 4 跑、晚于 stage 3，写不进。复用决策的下游需求由 delta-8 `/pmai-implementation-design` 读 `DESIGN.md` inventory 承接（§2.8 / delta-8 §X Round 3 X2）|
| 硬度 | 不硬卡出 stage 4，但**强制 PM 对每个「缺 / 新建」逐个表态** —— 不能 silent 忽略 |
| 前提 | `DESIGN.md` 须先升级成「有明确块的具体合约」（§2.7）；**已有项目的 `docs/DESIGN.md` 经 legacy 迁移升级**（§X D9-3 —— 框架同步只动模板、不动业务实例文档，旧项目 `docs/DESIGN.md` 须经 legacy readiness gate mini-upgrade，否则 gap-check 无 inventory 可查。见 §3 vp-4b）|

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
- **`input-flow.md §9.4` routing 表的最终结构由 delta-9 收口**（§X 连带）—— 现役四类被 supersede；delta-3 只改 task-spec 的 relevance 消费逻辑、不独立改 §9.4 表，delta-9 vp-6 画出合并后的 §9.4 全表（含 delta-3 的 relevance 维度 + 本 §2.8 多去向 routing）。单一 owner = delta-9，避免两 delta 各改一半、最终态无人画。
- delta-3 §2.4「跨模块反馈」已改指 delta-9（已落地）。
- **gap-check 的复用决策喂给 delta-8**（§X D9-7）—— delta-8 `/pmai-implementation-design`（stage 5）输入加 `DESIGN.md` 组件 inventory，§2 文件·模式索引据此写「复用现有组件 X」，与 gap-check（stage 4 先更新 inventory）读同一份、顺序天然一致。
- **与 GSD 的差异**：GSD 每 phase 重生成 UI-SPEC；我们一份累积 `DESIGN.md` + 每 req gap-check —— req 粒度细，累积清单才是 reuse 的底座。

---

## §3 实施清单（v2 据 §X Round 1 修订）

| vp | 改什么 | 依据 |
|---|---|---|
| vp-1 | 新建 `docs/PRODUCT-RULES.md` + `templates/PRODUCT-RULES.md.tmpl`（全项目跨功能产品行为规则，扁平清单；条目含 `scope` 字段 = 全局/域限定）| §2.1 §2.2 |
| vp-2 | **close-task 加 selective promote** —— 收尾扫 `## PM 反馈`（delta-3 后在审计区·历史档案），AI 预判 + PM 逐条选「产品行为规则」→ `PRODUCT-RULES.md`。**显式补 blast radius**（§X D9-4）：close-task SKILL §2.1 worktree-clean 检查 + `close-task.sh` carry-forward / clean-check 都加 `docs/PRODUCT-RULES.md` 白名单（对齐现役 `docs/DESIGN.md` 处理）| §2.3 §2.5（D9-4）|
| vp-3 | **task-spec + prd-writing 接 `PRODUCT-RULES.md`** —— ① task-spec 必读清单加 `PRODUCT-RULES.md`（按 §2.4 scope 章节-grep 读）；② prd-writing 必读清单加 `PRODUCT-RULES.md` 全文 + 加 candidate PRODUCT-RULES promote 入口（§2.3 ②）。⚠️ 本 vp 在 umbrella step 6 **后置增补**已重写完的 task-spec / prd-writing（非参与其 rewrite）；delta-3 §3 + delta-2+4 §3 ownership 表已登记 | §2.3 §2.4（D9-5/D9-8）|
| vp-4 | **`DESIGN.md` 模板升级** —— `templates/DESIGN.md.tmpl` 从占位骨架 → 具体合约：补 布局/响应式/无障碍 块；「组件规范」段做成累积式组件 inventory（条目 schema）；各块具体值化；加 Checker Sign-Off；保留「创意自由度」段 | §2.7 |
| vp-4b | **legacy DESIGN.md 迁移**（§X D9-3 新增）—— 已有项目 `docs/DESIGN.md` 仍旧 6 段骨架（框架同步只动模板、不动业务实例）；复用 delta-2+4 legacy readiness gate 模式（挂 `new-req`，首次跑检测 `docs/DESIGN.md` 结构、缺新块则一次性 mini-upgrade 成带 inventory 块的新结构）—— 否则 gap-check 在已有项目上无 inventory 可查 | §2.6 §2.7（D9-3）|
| vp-5 | **设计阶段 gap-check = 组件复用关口**（§X D9-1 / D9-2 修订）—— stage 4 拆「必跑 gap-check +（可选）DESIGN.md 视觉规范更新」，gap-check **每 req 无条件跑**、不随 stage 4 skippable；读 PRD 枚举界面/组件、逐个对 `DESIGN.md` inventory 判复用/新建、缺则强制 PM 表态；新建组件入 `DESIGN.md` inventory，**不写 PRD、不落 per-req 文件** | §2.6（D9-1/D9-2）|
| vp-6 | **测试 + SOP + 连带**（per-vp test matrix，见下）—— `框架同步-SOP.md` 补 delta-9 段；`input-flow.md §9.4` routing 表由本 vp 收口画出合并后全表（delta-3 只改 task-spec relevance 逻辑，§X 连带）| §2.8 |

**vp-6 test matrix（§X D9-9）**：

| 测什么 | 动作 |
|---|---|
| PRODUCT-RULES.md / DESIGN.md 升级模板 | 模板结构齐；PRODUCT-RULES 条目含 `scope` 字段 |
| close-task promote | fixture：扫 `## PM 反馈` → PM-selective promote 到 `PRODUCT-RULES.md` |
| **worktree-clean 不被拌倒（D9-4 / 6382baf-class 回归）** | close-task 留未 commit 的 `docs/PRODUCT-RULES.md` → 步骤 2.1 worktree-clean 不报 dirty |
| gap-check 每 req 必跑（D9-2 回归）| fixture：PM 在 Stage 3→4 选「不更新设计系统」→ gap-check 仍触发、不被跳过 |
| gap-check 对未升级 DESIGN.md（D9-3）| 已有项目旧 6 段 DESIGN.md → legacy 迁移 mini-upgrade 后 gap-check 有 inventory 可查 |
| task-spec scope-grep 读 | `scope=全局` 规则必纳入、`scope=域限定` 按关键词 grep 命中才读 |
| prd-writing candidate promote | fixture：stage 3 发现全项目规则 → PM-selective promote |
| **in-flight 旧 req（IRON 回归）** | delta-9 落地前在飞的 req 无 `PRODUCT-RULES.md`、旧 DESIGN.md → task-spec / prd-writing 读侧容错、不报错 |
| baseline | 明确新基线数（现 269）|

**落地顺序**：vp-4 / vp-4b（DESIGN.md 升级 + legacy 迁移，gap-check 的前提）→ vp-1 / vp-5（PRODUCT-RULES.md / gap-check）→ vp-2 / vp-3（写 / 读）→ vp-6（测试 + 连带）。delta-9 整体在 umbrella §8 step 6，vp-3 后置增补已重写完的 task-spec / prd-writing。

**消费侧衔接**：close-task / task-spec / prd-writing / req-stage-gate（stage 4）/ delta-8 `/pmai-implementation-design` —— 与 delta-2+4、delta-3、delta-8 撞同文件，整包实施按 delta-3 §3 ownership 表 + umbrella §8 协调。

---

## §X Review Findings（autoplan / dual voice 输出落这里）

> 每条 finding 按 `_模板-方案.md` §X 格式。**PAIN_LINK = NONE 且 EVIDENCE = ASSUMED 的 finding 默认 DEFER**。

### Round 1 — 2026-05-21 — /gstack-plan-eng-review（delta-9 v1 全审 · 含 codex outside-voice）

> **review 范围**：delta-9 首次 eng-review。`管线重构-GSD-review.md` §0/§6.1/§8 锁定基线（读不审）；前置读现役 `templates/DESIGN.md.tmpl` / `skills/req-stage-gate`(stage 3→4 / stage 4) / `skills/close-task` / `_shared/pm-view/input-flow.md §9.4` / `skills/task-spec`。

| # | Severity | Finding 摘要 | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| D9-1 | Critical | §2.6 gap-check 产物「记进 PRD 原型节」，但 delta-2+4 §2.5「PRD stage 3 定稿冻结」、§2.2 §6.1 原型节只由 close-req 回填、F19 禁写回冻结 PRD 基准（hash 自指）。gap-check 在 stage 4 写 stage-3 冻结的 PRD = 撞冻结契约 | §0.1 | delta-2+4 §2.5 / §2.2 / §X F19 | **ACCEPT** — gap-check 不单独落文件：产物 = PM 在 chat 逐组件表态（关口本来形态）+ 新建组件入 `DESIGN.md` inventory（已有）。§2.6 产物行改写、删「记进 PRD 原型节（codex#5）」整句、不补替代文件 |
| D9-2 | Critical | §2.6 gap-check 挂 stage 4，但现役 `req-stage-gate/SKILL.md:325` Stage 3→4 gate：PM 说「不用/跳过」→ stage 4 整个跳过 → 组件复用关口在「PM 觉得设计不用动」的 reuse-heavy req 上永不触发，恰是 §0.1(B) 该修的场景 | §0.1(B) | `req-stage-gate/SKILL.md:325,341-345` | **ACCEPT** — gap-check 与 stage 4 skippable 解耦、每 req 无条件跑；stage 4 拆「必跑 gap-check 组件复用关口 +（可选）DESIGN.md 视觉规范更新」；§2.6 何时 + §3 vp-5 重表述（触发条件 = 每 req 都建界面/组件，非「设计要不要改」）|
| D9-3 | High | vp-4 升级的是 `DESIGN.md.tmpl`（模板），框架同步 SOP 只同步 scripts/skills/templates/agents、不动业务实例文档（delta-2+4 §2.3/F7）→ 已有项目 `docs/DESIGN.md` 仍旧 6 段骨架、无 inventory 块，gap-check「无 inventory 可查」 | §0.1(B) | delta-2+4 §2.3 / §X F7、`templates/DESIGN.md.tmpl` | **ACCEPT** — 加 legacy DESIGN.md 迁移 vp，复用 delta-2+4 legacy readiness gate 模式（挂 new-req，首次跑检测 DESIGN.md 结构、缺新块则一次性 mini-upgrade）|
| D9-4 | High | vp-2 close-task PRODUCT-RULES promote 与步骤 1.5「视觉规范→DESIGN.md」同型，但现役步骤 2.1 worktree-clean 检查（`close-task/SKILL.md:290`）+ close-task.sh carry-forward 是 `docs/DESIGN.md` 专属白名单 → 未 commit 的 PRODUCT-RULES.md 会拌倒 worktree-clean（commit `6382baf` 已为 DESIGN.md 修过同类 bug）| §0.1 | `close-task/SKILL.md:290`、`close-task.sh:138-178`、commit `6382baf` | **ACCEPT** — vp-2 显式补 blast radius：close-task SKILL §2.1 + close-task.sh worktree-clean / carry-forward 都加 `docs/PRODUCT-RULES.md` 白名单 |
| D9-5 | High | vp-3 独立 patch task-spec + prd-writing 必读清单，但 delta-3 §3 ownership「delta-3 独占 task-spec 重写」、delta-2+4 vp-3 重写 prd-writing，delta-9 不在任何 ownership 表（对照 delta-7 vp-2 / delta-8 vp-3 皆 fold 进 owner）| §0.3 | delta-3 §3 ownership 表 | **ACCEPT** — delta-9 vp-3 保持独立（整体 step 6、patch 已重写完的 skill、只加 reading-list 行 = 后置轻量增补，非参与 rewrite）；delta-3 §3 + delta-2+4 §3 加登记行注明「delta-9 vp-3 后置增补 reader」。不 fold（fold 会逼 delta-9 vp-1 前移、撕碎 delta-9 跨 step）|
| D9-6 | Medium | §2.4 task-spec「生成每个 task 时」全文读 `PRODUCT-RULES.md`，该文件 §2.2 累积式只增（无 scope 字段、靠 PM 手动剪）→ 长项目 per-task 读取成本隐性涨（框架 reading-convergence 是 active 关注，memory `feedback_skill_reading_convergence` / TODOS TD-X 组）| §0.3 | §2.2 / §2.4、memory `feedback_skill_reading_convergence` | **ACCEPT** — 改章节-grep 收敛：§2.2 每条规则加 scope 字段「全局」/「域限定:<关键词>」；task-spec 读全部「全局」+ grep 命中的域限定规则（跨功能规则标全局、永不漏；域限定才 grep 跳过）。§2.2「无 scope 字段」+ §2.4 读取逻辑改写 |
| D9-7 | High（codex outside-voice）| delta-8 `/pmai-implementation-design` producer 输入（brief+analysis+PRD+CONTEXT）无 `DESIGN.md` → implementation-design §2 文件·模式索引自行重推「照哪些现有组件写」，与 gap-check 组件复用关口脱节、可能复发「组件不复用」于 HOW 层 | §0.1(B) | delta-8 §4 vp-2 | **ACCEPT** — delta-8 vp-2 `/pmai-implementation-design` 输入加 `DESIGN.md`（组件 inventory）；gap-check（stage 4）先更新 inventory、implementation-design（stage 5）后读，顺序天然一致（连带改 delta-8，见其 §X Round 3）|
| D9-8 | Medium（codex outside-voice）| §2.3 PRODUCT-RULES.md 只有 close-task 一个写入口；prd-writing 读它却不能写 → 规划期（stage 3/4）发现的全项目产品行为规则若非某 task 的 PM 反馈则无沉淀路径 | §0.1 | §2.3 / §2.4 | **ACCEPT** — prd-writing（stage 3）加 candidate PRODUCT-RULES promote 入口（PM-selective，同 close-task selective 模式）；由 **delta-9 自己在 umbrella step 6 加**（patch 已重写完的 prd-writing，同 D9-5 reading-list 后置增补）。**不并入 delta-2+4 vp-3** —— `PRODUCT-RULES.md` 由 delta-9 vp-1 在 step 6 创建，delta-2+4 vp-3（step 2）引用不到，会 forward-reference |
| D9-9 | High | vp-6「测试 + SOP + 连带」无 per-vp test matrix（delta-2/3/4/8 皆有）；缺 IRON in-flight-req 回归（在飞 req 无 PRODUCT-RULES.md、旧 DESIGN.md → 读侧容错）+ skippable-stage-4 触发 / 未升级 DESIGN.md 行为 / 6382baf-class worktree-clean 回归 | §0.3 | delta-2+4 §X F9 先例 | **ACCEPT** — vp-6 升级为完整 per-vp test matrix（含上述 GAP）；IRON in-flight-req 回归 + 6382baf-class 回归按 REGRESSION RULE 强制加 |
| D9-10 | — | umbrella §8 把 delta-9 排 step 6（delta-2+4 step 2 / delta-3 step 4 之后）→ delta-9 只能二次 patch 已重写的 prd-writing/task-spec；req-stage-gate 被 delta-2+4/8/9 三 delta 改、无 ownership 行 | — | codex#1 | **DEFER** — 本轮 umbrella §8「读不审」；连同 delta-7/9 排序、req-stage-gate ownership、整包验收留到整包复跑 /plan-eng-review 重评 |

**汇总**：9 ACCEPT（D9-1~D9-9）/ 1 DEFER（D9-10，转整包复跑）。D9-1/D9-2 为 Critical（照字面实施撞冻结 PRD / 修复永不触发）。D9-7 / D9-8 为 codex outside-voice 新增。delta-9 v1 → 待修订 v2。

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-21 | 文档创建；delta-9 从 delta-7 拆出（跨模块反馈本质非 req 级事件）| — |
| 2026-05-21 | §0 锁定；Q1-Q5 逐题过；PM re-scope（设计规范 ≠ 产品规则、selective 沉淀、gap-check 纳入）| 见 §2.1-§2.5 |
| 2026-05-21 | PM 钉死定义：`PRODUCT-RULES.md` = 全项目跨功能产品行为规则；用词→术语表、模块级→modulespec | §0 / §2 定义贯通 |
| 2026-05-21 | v0 → **v1**：GSD UI-SPEC 对照（ChatBuilder `.codex` vendored GSD）—— GSD 有专门 `ui-phase` + per-phase UI-SPEC（11 块具体合约 + 6 维 Checker）。借鉴：① gap-check 重 framed 为「**组件复用关口**」（逐组件判复用/新建 + 产 per-req 复用清单），对症 PM 实证的「组件不复用」；② 新增 vp-4「`DESIGN.md` 模板升级」（补块 + 具体合约化 + 组件 inventory + Checker；保留我们独有的「创意自由度」）；③ §0 facet (B) sharpen（补「组件清单」缺口 + §0.2 场景 4 实证）；④ §0.4 明确不抄 GSD「每 req 重生成」。delta-9 v0 → v1 设计完成 | §0 / §2.6 / §2.7 / §3 |
| 2026-05-21 | /gstack-plan-eng-review delta-9 v1 全审（§X Round 1，含 codex outside-voice）：9 ACCEPT（D9-1 gap-check 产物不落文件、D9-2 gap-check 与 skippable stage 4 解耦、D9-3 加 legacy DESIGN.md 迁移 vp、D9-4 vp-2 补 worktree-clean blast radius、D9-5 vp-3 后置登记 ownership、D9-6 PRODUCT-RULES 改章节-grep + 加 scope 字段、D9-7 delta-8 输入加 DESIGN.md、D9-8 prd-writing 加候选 PRODUCT-RULES promote 入口、D9-9 vp-6 升 per-vp test matrix）/ 1 DEFER（D9-10 umbrella §8 排序转整包复跑）。下一步据 §X 修订 v2 | 文档 v1 → 待修订 v2 |
| 2026-05-21 | **v2 修订完成**：§2.2 加 `scope` 字段；§2.3 加 prd-writing 规划期 candidate promote 入口 + close-task promote 补 worktree-clean blast radius；§2.4 改 scope 章节-grep；§2.6 gap-check 与 skippable stage 4 解耦 + 产物不写冻结 PRD；§2.8 §9.4 表归 delta-9 收口 + gap-check 喂 delta-8；§3 vp 表（+vp-4b legacy 迁移）+ per-vp test matrix。§0 不动 | 文档 v1 → **v2**，可实施 |

---

**End of delta-9 · 跨功能产品行为规则 + 设计规范与组件复用 v2**

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| Eng Review | `/plan-eng-review` | Architecture & tests（required）| 1 | revised | R1 (2026-05-21 v1 全审，含 codex outside-voice): 10 finding — 2 Critical / 5 High / 2 Medium / 1 DEFER；9 ACCEPT 已落 v2、1 DEFER 转整包 |
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | skipped — §0 痛点 + scope 经 PM re-scope（§Y 2026-05-21）锁定，delta-9 经 codex#4/9 拉入最小包 |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | skipped — delta-9 改 skill/模板/脚本本身不建界面（它定义的是别人怎么建界面）|

- **CODEX:** codex outside-voice 跑过 —— 新增 D9-7（delta-8 不消费组件复用决策）+ D9-8（PRODUCT-RULES 无规划期写入口）。
- **CROSS-MODEL:** D9-7 / D9-8 为 codex 独立发现，本轮单模型评审未命中 —— 已 ACCEPT 并入。
- **UNRESOLVED:** 0 本轮内待决；1 DEFER（D9-10，umbrella §8 delta-9 排序 + req-stage-gate ownership 转整包复跑）。
- **VERDICT:** delta-9 **v2** — 首次 eng-review，§0 成立；§X Round 1 的 9 ACCEPT（含 2 Critical：撞冻结 PRD / 修复挂可跳过 stage）已落进 §2/§3，文档 v1→v2、**可实施**；1 DEFER（D9-10 umbrella §8 排序）整包实施时按 delta-3 §3 ownership 表执行。
