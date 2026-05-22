# req 级事件流（delta-7） (v1)

> **状态**：v1 设计完成（2026-05-21）—— v0 经 /gstack-plan-eng-review 全审（§X Round 1，6 ACCEPT / 1 DEFER），§2/§3/§4 据 finding 修订：文件改落 tracked 路径（D7-1）、信封字段 `ts`→`timestamp`（D7-3）、vp-3 close-task promote 补 phase/格式/排序（D7-2）、decision 事件加 stage-3 确认门渲染（D7-5）、vp-4 升 per-vp test matrix（D7-6）。§0 锁定不动。**可实施**。
> **日期**：2026-05-21
> **作者**：PM + AI
> **来源**：`管线重构-GSD-review.md` §4 delta-7 + §8（2026-05-21 /plan-eng-review codex#4 把 delta-7 拉入最小落地包）。
> **依赖方**：`PRD-solution-对调.md` v1.2 §2.2（决策备选/理由 → delta-7 `decision` 事件）、delta-6（close-req 反向对齐读「调整日志」= delta-7 `adjustment` 事件）。
> **范围变更**：原 v0 含第三类「跨模块反馈」；2026-05-21 PM 决议 —— 跨模块反馈本质是**项目级前瞻产品规则**、非 req 级事件，移出 delta-7、另立 **delta-9**（详 §0.4 / §Y）。

---

## §0 原始痛点（PM + AI 共写，后续 review **不可反向修改**）

> ⚠️ 任何后续 review / autoplan / dual voice 都**不能**给本节加东西、不能重新定义痛点。
> 如出现"新发现的痛点"，要么走另一个 D-* 设计文档，要么 PM 主动决策更新 §0。

### §0.1 痛点（1-3 句）

delta-7 是 delta-2+4 / delta-6 的**结构连带**：新管线把两类 req 级、内容性、按时间 append 的数据 —— 决策的**备选 + 理由**、执行期对 PRD 的**调整** —— 都明确指向「delta-7 req 事件流」，但这个事件流不存在。框架现有事件流只到 task 级（`.runs/events/<task-stem>.jsonl`，`task-events.py`），req 级只有 `.req-meta.json` 的 stage_history（纯状态转换、不装内容）。

> **§0 re-scope 注**：原 §0（2026-05-21 首锁）含第三类「跨模块反馈」。同日 PM 决议 —— 跨模块反馈本质是**项目级前瞻产品规则**（适用范围超出发起 task 的模块、是「应/不应」规则、向前管未写的 task），不是 req 级事件；放进 req 级事件流是 scope 错配。移出 delta-7、另立 delta-9。本节据此 re-scope 为 2 类。

### §0.2 触发场景

> delta-7 的痛点是**结构连带**（同 delta-8 §0 模式），不是 PM 单点 incident。证据为其余 delta 文档对「delta-7 事件流」的明确指向 —— 仓内可查。

| # | 场景描述 | 证据（结构性 / 仓内可查）|
|---|---|---|
| 1 | PRD §四只装决策**结果**，决策的备选 + 理由无结构位 | `PRD-solution-对调.md` v1.2 §2.2 结论 1：备选 + 理由 → delta-7 `decision` 事件，「PRD 只装决策结果」|
| 2 | close-req 反向对齐 PRD 需要「执行期做了哪些调整」的来源 | `管线重构-GSD-review.md` §4 delta-7：req 级事件流「兼作 delta-6 PRD 反向对齐所需『调整日志』的存放处」|

**两条均为结构连带**（非 incident）；证据为其余 delta 文档的明确指向，仓内可查。

### §0.3 根因（解决什么底层 mechanism）

req 级缺一个**内容性事件流**。task 级有 `.runs/events/<task-stem>.jsonl` 装执行 / 转换 / 审计事件；req 级只有 stage_history，只装**状态转换**、不装**内容**。决策理由 / 调整 都是 req 级、内容性、append-only 的数据 —— 没有对应结构位，只能寄生（塞 PRD 正文 = `PRD-solution-对调.md` §0.1 修过的反模式；塞 task 文件 = `task-spec重构.md` §0 修过的反模式）。

根因 = **req 级没有「内容性事件流」这个结构位**。

### §0.4 不解决什么（防膨胀）

| # | 衍生 / 假设场景 | 为什么不在 §0 范围 |
|---|---|---|
| 1 | 跨模块反馈 / 项目级产品规则 | 2026-05-21 PM 决议拆出 → **delta-9**（项目级前瞻产品规则安家）；delta-7 不管它 |
| 2 | 重做 / 改 task 级事件流 | `.runs/events/<task>.jsonl` + `task-events.py` 已有；delta-7 是**抬到 req 级**，不动 task 级 |
| 3 | 替代 stage_history | stage_history 装状态转换；delta-7 装内容。两者并存，不替代 |
| 4 | 决策**结果**本身的归宿 | = PRD §四（delta-2+4 已定）；delta-7 只装备选 + 理由 |
| 5 | 实时 dashboard / 通知 / 提醒 | delta-7 = append-only jsonl + 按需渲染，不做实时推送 |

→ **review 中任何 finding 指向以上场景的，默认 DEFER**（除非 PM 显式接受拉进 §0）

---

## §1 要定的设计问题（逐题过）

| # | 设计问题 | 状态 |
|---|---|---|
| Q1 | **文件形态** —— 路径（`.runs/events/req-*.jsonl`）、一 req 一文件、jsonl；与 `task-events.py` 对齐 | ✓ 已定（见 §2.1）|
| Q2 | **事件 schema** —— 2 类（`decision` / `adjustment`）+ 各类字段 | ✓ 已定（见 §2.2）|
| Q3 | **谁 append** —— 各事件类型的写入点 | ✓ 已定（见 §2.3）|
| Q4 | **谁读** —— 消费点 | ✓ 已定（见 §2.4）|
| Q5 | **人类视图** —— 要不要 renderer（jsonl → 可读时间线）？还是只 jsonl + 消费 skill 按需渲染 | ✓ 已定（见 §2.5）|
| Q6 | **与 task 级事件流 / stage_history 的边界** —— 三套时间线各装什么、不重叠 | ✓ 已定（见 §2.6）|

> 原 §1 为七题；原 Q5「跨模块反馈传播机制」随 feedback 移出 delta-7 而**撤销**（→ delta-9）；原 Q6/Q7 顺位为 Q5/Q6。

---

## §2 方案主体

### §2.1 文件形态（Q1 已定 · v1 据 §X D7-1 修订）

- **路径**：`requirements/active/<reqid>/req-events.jsonl` —— 一 req 一文件，落 req 目录、**被 git 跟踪**，随 req 分支正常 commit，close-req 时随 req 分支 merge 回主分支。
- **不落 `.runs/events/`**（v0 原方案，§X D7-1 推翻）—— `.runs/` 在 `.gitignore:17`、全仓 0 tracked 文件；放那里则「随 req 分支 merge 回主分支」不可能、req close 后 `.runs/` 连同 decision 事件被清，PM 永远查不到历史决策理由。v0 选 `.runs/events/` 唯一动机是「与 task-events.py 同目录」，但那个对齐恰恰继承了 gitignore + 临时性 —— 对「PM 关闭后还要查决策理由」的 req 级数据是错的。task 级事件流正因 `.runs/` 不可提交，才由 `close-task.sh` 专门归档进 tracked 路径；delta-7 直接落 tracked 路径、无需归档机器。
- **格式**：jsonl，append-only，一行一 JSON 事件 —— schema 与 `task-events.py` 一致（字段名见 §2.2），零新格式。
- **持久化天经地义** —— `decision`（这个 req PRD 的理由）和 `adjustment`（被 close-req 消费）都是真·req 级数据，被 git 跟踪、随 req 分支留存；decision 事件 close 后仍可查（§2.5 人类视图的前提）。
- **代码复用**：沿用 `task-events.py` 的 `now_iso()` / 文件读写；扩 `task-events.py` 还是新建 `req-events.py` 由 Q3 定。
- **不做「全项目一条 req 流」** —— 那样 close-req 要过滤、跨 req 混读；一 req 一文件，close-req 直接读自己 req 的文件。

### §2.2 事件 schema（Q2 已定）

**2 个事件类型** —— 对应 §0 re-scope 后的两类 req 级内容性数据（§0.4 防膨胀：不加 §0 未点名的类型；跨模块反馈已移 delta-9）。

**公共信封**（每条 jsonl 行）：`{"event":<类型>, "timestamp":<iso>, "req":<reqid>, "source":<skill@stage>, ...类型字段}` —— `event` / `timestamp` 字段名对齐 `task-events.py`（`task-events.py:74` 实际用 `timestamp`，非 `ts`；v0 写 `ts` 是 §X D7-3 修订项）。`req` 字段对应 task-events 的 `task` 字段（故意平行）。

| 类型 | 何时写 | 类型字段 |
|---|---|---|
| `decision` | prd-writing @ stage 3 做决策时 | `decision`（一句话标题）· `prd_anchor`（PRD §四 哪条结果）· `chosen` · `alternatives`[] · `rationale` |
| `adjustment` | 执行期 task 对 PRD 的偏离 | `from_task` · `prd_anchor`（哪条被调）· `before`（PRD 原定）· `after`（实际做成）· `reason` |

- **decision vs adjustment 的界**：`decision` = PRD 成文时（stage 3）「为什么这么选」；`adjustment` = 执行期「实际偏离 PRD」。同样关于 PRD，但成文时 vs 执行期，分两类。
- **无 `feedback` 类型** —— 跨模块反馈 = 项目级前瞻产品规则，移出 delta-7（→ delta-9）。

### §2.3 谁 append（Q3 已定 · v1 据 §X D7-2 / D7-5 修订）

| 事件 | 写入点 | 说明 |
|---|---|---|
| `decision` | **prd-writing @ stage 3** | PRD 成文后，为每条决策 append 一条 —— 结果留 PRD §四，备选 / 理由进事件。**PM binding 确认**（§X D7-5）：stage 3 PRD 定稿确认门同时渲染本次新增 decision 摘要（备选 / 理由），PM 确认 PRD 一并确认 decision payload —— 否则 AI 写的「为什么这么选」无 binding confirmation（同 delta-8 codex#6 同型）。不新增门，并进 delta-2+4 已收口的 stage-3 单一确认门 |
| `adjustment` | **close-task Phase 2（req worktree）**| 把该 task 审计区「文档偏差」promote 成 req `adjustment` 事件 |

- **代码**：新建 `scripts/req-events.py`，与 `task-events.py` 平行（`append` / `list` 子命令）；共用 `now_iso()` 等抽 `_lib/` 或各留一份。
- **close-task = adjustment 的 promote 点 · 三个落地约束（§X D7-2）** ——
  1. **Phase 2 写**：close-task 两阶段 —— Phase 1 在 task worktree、Phase 2（`close-task.sh`）在 req worktree；`req-events.jsonl` 在 req 目录 → promote 必须在 **Phase 2**，由 `close-task.sh` 调 `req-events.py append`（merge task 分支后读 task 文件「文档偏差」）。
  2. **格式三态**：「文档偏差」位置随 task 格式变 —— v2 双文件在 `engineering.md §10`、v3 单文件在审计区；promote 读取复用 **delta-3 §2.7 的 `detect_format` 三态**判别，不自己复刻。
  3. **排序**：本 vp（vp-3）随 delta-3 close-task 塌缩一起做（umbrella §8 step 4 内），不在 delta-3 之前 —— 否则 step-1 写的代码只认 v2 老位置、delta-3 落地后对 v3 全失效。见 §3 落地顺序。
- task-execute / task-verify 期间的偏差先落 task 文件（delta-3 审计区），close-task 收尾时一次性 promote 到 req 流。

### §2.4 谁读（Q4 已定）

| 事件 | 消费者 | 怎么用 |
|---|---|---|
| `adjustment` | **delta-6 close-req** | 反向对齐 PRD → as-built 的来源：读全 req 的 `adjustment` 事件、逐条把 PRD 改成实际做成的样子 |
| `decision` | **PM 人类视图**（§2.5）| 留痕 + 给 PM 查「当初为什么这么选」；无下游 skill 机器消费者 |

- **`decision` = 纯留痕 + PM 查** —— 无下游 skill 机器消费者；delta-6 close-req 做 PRD 反向对齐用 `adjustment`、不回读 `decision`。`decision` 的价值全在 §2.5 人类视图。

### §2.5 人类视图（Q5 已定）

- **无独立 renderer skill / 文档** —— `req-events.py` 的 `list` 子命令（平行 `task-events.py` 已有的 `list`）即人类视图，PM 按需跑。
- `list` 把 jsonl 折叠成可读时间线（按 `ts` 排，`decision` / `adjustment` 分组）。
- **不自动推送**（§0.4）。close-req 收尾摘要可提一句「本 req 记录 N 条 decision / M 条 adjustment，`req-events.py list` 看」—— 轻量指针，非 dashboard。

### §2.6 与 task 事件流 / stage_history 的边界（Q6 已定）

三套时间线，按「对谁 × 装哪一面」分清，零重叠：

| 时间线 | 对谁 | 装哪一面 | 位置 |
|---|---|---|---|
| `stage_history` | req | **生命周期**（stage 1→2→…→close/cancel 推进；`req-transition.py` 每次转换 append）| `.req-meta.json` |
| task events | task | **生命周期 + 执行 + 审计**（transition / execution_* / CT7-CT8）| `.runs/events/<task-stem>.jsonl` |
| **req events**（delta-7）| req | **内容**（决策理由 `decision` / PRD 调整 `adjustment`）| `requirements/active/<reqid>/req-events.jsonl`（tracked）|

- **req 生命周期 = `stage_history`** —— req 不「执行」（执行在 task 层、由 task events 记），req 的生命就是它在 7 个 stage 间推进。delta-7 **不碰** stage_history（§0.4 已锁：不替代它）。
- **对称视角**：req 有两条流（生命周期 `stage_history` + 内容 delta-7）；task 一条合并流（生命周期/执行/审计同在 `.runs/events/<task>.jsonl`），task 的「内容」在 task 文件里。各取所需。
- **唯一连接点**：task 的「文档偏差」是 task 文件审计区的内容，close-task 把它 promote 成 req `adjustment` 事件 —— 「task 文件内容 → req 事件」的提升，**不双写**（不同时记成 task 事件）。

---

## §3 实施清单（v1 据 §X Round 1 修订）

| vp | 改什么 | 依据 |
|---|---|---|
| vp-1 | 新建 `scripts/req-events.py` —— `append` / `list` 子命令；2 类事件 schema（`decision` / `adjustment`）+ 公共信封（`timestamp` 字段，对齐 task-events.py）；文件落 `requirements/active/<reqid>/req-events.jsonl`（tracked）；复用 `task-events.py` 的 `now_iso()` 等（抽 `_lib/` 或各留一份，vp-1 定）| §2.1 §2.2 §2.5 |
| vp-2 | **`decision` 事件写入 + PM 确认** —— prd-writing @ stage 3 PRD 成文后为每条决策 append `decision` 事件；stage-3 PRD 定稿确认门同时渲染本次新增 decision 摘要供 PM 一并确认（§X D7-5）。⚠️ 本 vp **并入 delta-2+4 vp-3**（delta-2+4 §X Round 4 X1 已登记吸收），不二次独立改 prd-writing | §2.2 §2.3 |
| vp-3 | **`adjustment` 事件写入** —— close-task **Phase 2**（`close-task.sh`）把 task 审计区「文档偏差」promote 成 req `adjustment` 事件；格式判别复用 delta-3 §2.7 `detect_format` 三态。⚠️ 本 vp **随 delta-3 close-task 塌缩一起做**（§X D7-2），不在 delta-3 之前；delta-3 §3 ownership 表已补 close-task 行登记三 delta 合改 | §2.2 §2.3 |
| vp-4 | **测试 + SOP**（per-vp test matrix，见下）；`框架同步-SOP.md` 补 delta-7 段；close-req 收尾摘要加 req-events 计数指针（§2.5）；明确新基线数 | §2.5 §2.6 |

**vp-4 test matrix（§X D7-6）**：

| 测什么 | 动作 |
|---|---|
| `req-events.py` append/list | `append` 写一行合法 jsonl、`list` 折叠成时间线；信封字段 `timestamp` 对齐 task-events.py |
| 文件落 tracked 路径 | `req-events.jsonl` 落 `requirements/active/<reqid>/`、随 req 分支 commit；close-req merge 回主分支后文件仍在（decision 事件 close 后可查）|
| decision 写入 | prd-writing @ stage 3 fixture：PRD 成文 → 每条决策一条 `decision` 事件；stage-3 确认门渲染 decision 摘要 |
| adjustment 写入（v2/v3）| close-task Phase 2 promote「文档偏差」→ `adjustment` 事件，**v2 双文件 task 与 v3 单文件 task 各测一遍**（格式三态）|
| **in-flight 旧 req（IRON 回归）** | delta-7 落地前在飞的 req 无 `req-events.jsonl` → close-req 读 `adjustment` 容错文件缺失、不报错 |
| 边界回归 | req events 不与 task events / stage_history 重叠（§2.6 三套时间线）|
| baseline | 明确新基线数（现 269）|

**落地顺序**（umbrella §8 step 1 + §X D7-2 调整）：vp-1（脚本 + tracked 文件位置，独立 infra，最先）→ vp-2 随 delta-2+4 vp-3 落地 → **vp-3 随 delta-3 close-task 塌缩一起做（umbrella §8 step 4 内，不在 delta-3 之前）** → vp-4 收尾。

**消费侧**（delta-7 不实现、仅登记衔接）：delta-6 close-req 读 `adjustment` 做 PRD 反向对齐 —— 属 delta-6 设计文档。

---

## §4 风险与待验（v1 据 §X Round 1 修订）

- **prd-writing 多 delta 触碰** —— vp-2（decision-append + stage-3 确认门渲染）并入 delta-2+4 vp-3，delta-2+4 §X Round 4 X1 已登记吸收；delta-2+4 实施 prd-writing 重写时按其 vp-3 正文执行即含 decision-append。
- **close-task 多 delta 触碰** —— vp-3 与 delta-3（文件塌缩）+ delta-9 vp-2（PRODUCT-RULES promote）合改 close-task；delta-3 §3 ownership 表已补 close-task 行收口三者排序，实施时按该表执行。
- **umbrella §8 排序（§X D7-7，DEFER）** —— delta-7 vp-3 排序经 D7-2 已调（随 delta-3）；umbrella §8 整体排序 + req-stage-gate ownership 整包实施时按 delta-3 §3 ownership 表执行，本文档不再单列。
- **`req-events.py` ↔ `task-events.py` 代码共用边界** —— `now_iso()` 等抽 `_lib/` 还是各留一份，vp-1 动手时定（体量极小，不阻塞设计）。

---

## §X Review Findings（autoplan / dual voice 输出落这里）

> 每条 finding 按 `_模板-方案.md` §X 格式。**PAIN_LINK = NONE 且 EVIDENCE = ASSUMED 的 finding 默认 DEFER**。

### Round 1 — 2026-05-21 — /gstack-plan-eng-review（delta-7 v0 全审 · 含 codex outside-voice）

> **review 范围**：delta-7 v0 首次 eng-review（从未审过）。`管线重构-GSD-review.md` §0/§6.1/§8 视为锁定基线（读不审）；前置读现役 `scripts/task-events.py` / `skills/close-task` / `skills/prd-writing`。

| # | Severity | Finding 摘要 | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| D7-1 | Critical | §2.1 req-events 落 `.runs/events/req-*.jsonl`，但 `.runs/` 是 gitignored（`.gitignore:17`，全仓 0 tracked）→「随 req 分支 merge 回主分支」「decision 随 req 归档」不可能；req close 后 `.runs/` 连同 decision 事件被清，PM 永远查不到历史决策理由 | §0.1 | `.gitignore:17`、`close-task.sh:245-314`（task events 归档进 tracked 路径，正因 `.runs/` 不可提交）| **ACCEPT** — req-events 改落 `requirements/active/<reqid>/req-events.jsonl`（被 git 跟踪、随 req 分支 commit/merge）；§2.1 删「与 task-events.py 同目录」对齐 + §3 vp-1 改 |
| D7-2 | High | vp-3 close-task adjustment-promote 漏 phase / 格式 / 排序：close-task 两阶段（Phase 1 task worktree、Phase 2 req worktree），req-events 文件在 req 目录；delta-3 后「文档偏差」从 engineering.md §10 搬到单文件审计区、须兼容 v2/v3；umbrella §8 把 delta-7 排 step 1 早于 delta-3 step 4，step-1 写的 close-task 代码读 v2 老位置 | §0.1 | close-task 两阶段结构、delta-3 §2.7 三态 | **ACCEPT**（codex#4 cross-model 一致）— vp-3 改挂 delta-3 之后，Phase-2（close-task.sh 调 req-events.py），格式判别复用 delta-3 §2.7 detect_format 三态；delta-7 §3 落地顺序 + umbrella §8 step + delta-3 §3 ownership 表据此调 |
| D7-3 | Medium | §2.2 公共信封字段名 `ts` 并声称「`event` / `ts` 字段名对齐 task-events.py」，但 `task-events.py:74` 实际用 `timestamp` | §0.3 | `task-events.py:74` | **ACCEPT** — 信封 `ts` → `timestamp`，真对齐；§2.1「零新格式」成立 |
| D7-4 | Medium | vp-2「并入 delta-2+4 vp-3」但 delta-2+4 §3 vp-3 正文未列 decision-event-append（对照 delta-3 vp-3 正文明写「吸收 delta-2+4 vp-4b + delta-8 vp-3」）| §0.1 | delta-2+4 §3 vp-3 | **ACCEPT** — delta-2+4 vp-3 正文补「吸收 delta-7 vp-2 decision-event-append」（连带改 delta-2+4，见其 §X Round 4）|
| D7-5 | High（codex outside-voice）| decision 事件由 AI 写、无 PM binding 确认：PRD §四只装结果、备选/理由进 decision 事件；stage 3 唯一 PM 定稿门确认 PRD、不渲染 decision payload →「为什么这么选」无 binding confirmation（同 delta-8 codex#6 同型）| §0.1 | §2.3 / §2.4、delta-2+4 §2.2 | **ACCEPT** — Stage 3 PRD 定稿确认门同时渲染本次新增 decision 摘要（备选/理由），PM 确认 PRD 一并确认 decision payload；不新增门（兼容 delta-2+4 单一确认门）；随 vp-2 并入 delta-2+4 vp-3 |
| D7-6 | High | vp-4「测试 + SOP」仅一行 prose，无 per-vp test matrix（delta-2/3/4/8 皆有）；缺 IRON in-flight-req 回归（delta-7 落地前在飞的 req 无 req-events 文件 → close-req 读 adjustment 须容错文件缺失）| §0.3 | delta-2+4 §X F9 / delta-8 §X D8-10 先例 | **ACCEPT** — vp-4 升级为完整 per-vp test matrix（脚本 append/list、decision/adjustment fixture、close-task promote v2/v3、文件落 tracked 路径 + commit/merge 验证、边界回归）；IRON in-flight-req 回归按 REGRESSION RULE 强制加 |
| D7-7 | — | umbrella §8 把 delta-7 与 delta-9 排序、req-stage-gate 三-delta（delta-2+4/8/9）ownership 未收口 | — | codex#1 | **DEFER** — 本轮 umbrella §8「读不审」（锁定基线）；连同 delta-9 排序、整包验收一起留到 delta-2+3+4+7+8+9 整包复跑 /plan-eng-review 重评 |

**汇总**：6 ACCEPT（D7-1~D7-6）/ 1 DEFER（D7-7，转整包复跑）。D7-2 经 codex outside-voice 独立命中（cross-model 一致）；D7-5 为 codex outside-voice 新增。delta-7 v0 → 待修订 v1。

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-21 | 文档创建（AI 起草 v0）；§0 待 PM 共写锁定；§1 七题待逐题过 | — |
| 2026-05-21 | §0 经 PM 确认锁定（痛点 = 结构连带，证据为其余 delta 的明确指向）| §0 锁定 |
| 2026-05-21 | Q1-Q4 逐题过定稿（文件形态 / schema / 谁 append / 谁读）；走到原 Q5「跨模块反馈传播」时 PM 质疑「orphan 在 close-req 后就没用了」→ 引出「feedback 目前根本没正面定义」| 见 §2.1-§2.4 |
| 2026-05-21 | **PM 决议：cross-module feedback 定义 = 项目级前瞻产品规则**（适用范围超发起 task 的模块、是「应/不应」规则、向前管未写的 task），本质非 req 级事件 → **移出 delta-7、另立 delta-9**。§0 据此 re-scope 为 2 类（decision / adjustment）；原 Q5 撤销、Q2 三类→两类、Q1/Q3/Q4 去 feedback 行；delta-7 回到 umbrella 给的「·小」。**连带**：delta-3 v2 §2.4「跨模块反馈 DEFER 到 delta-7」待改指 delta-9（delta-3 v2→v3）；umbrella 最小落地包 delta-2+3+4+7+8 待 +delta-9 | §0 re-scope；§1/§2 返工 |
| 2026-05-21 | Q5（人类视图 = `req-events.py list`，无独立 renderer）/ Q6（边界：stage_history = req 生命周期、task events = task、req events = req 内容）逐题过定稿；§1 六题全收口，§2 + §3 + §4 成文。**delta-7 v0 设计完成** | 设计定稿 |
| 2026-05-21 | /gstack-plan-eng-review delta-7 v0 全审（§X Round 1，含 codex outside-voice）：6 ACCEPT（D7-1 文件改落 tracked 路径、D7-2 vp-3 改挂 delta-3 之后、D7-3 字段名 `ts`→`timestamp`、D7-4 delta-2+4 vp-3 补认领、D7-5 decision 并进 stage-3 确认门、D7-6 vp-4 升 per-vp test matrix）/ 1 DEFER（D7-7 umbrella §8 排序转整包复跑）。下一步据 §X 修订 v1 | 文档 v0 → 待修订 v1 |
| 2026-05-21 | **v1 修订完成**：§2.1 文件改落 `requirements/active/<reqid>/req-events.jsonl`（tracked）；§2.2 信封 `ts`→`timestamp`；§2.3 close-task promote 补 Phase-2 / 三态格式 / 排序三约束 + decision 加 stage-3 确认门渲染；§2.6 req events 路径同步；§3 vp 表 + per-vp test matrix；§4 风险改写。§0 不动 | 文档 v0 → **v1**，可实施 |

---

**End of req 级事件流（delta-7）v1**

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| Eng Review | `/plan-eng-review` | Architecture & tests（required）| 1 | revised | R1 (2026-05-21 v0 全审，含 codex outside-voice): 7 finding — 1 Critical / 3 High / 2 Medium / 1 DEFER；6 ACCEPT 已落 v1、1 DEFER 转整包 |
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | skipped — §0 痛点 + scope 由 umbrella §4.2/§8 PM 已判（2026-05-20 binding），delta-7 经 codex#4 拉入最小包 |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | skipped — 无 UI scope（新建脚本 / 改 skill，不建界面）|

- **CODEX:** codex outside-voice 跑过 —— 独立命中 D7-2（cross-model 一致）+ 新增 D7-5（decision 事件无 PM binding 确认）。
- **CROSS-MODEL:** D7-2（vp-3 排序）两模型独立落到同一结论 = 高置信。
- **UNRESOLVED:** 0 本轮内待决；1 DEFER（D7-7，umbrella §8 排序转整包复跑 /plan-eng-review）。
- **VERDICT:** delta-7 **v1** — 首次 eng-review，§0 成立（结构连带痛点）；§X Round 1 的 6 ACCEPT 已落进 §2/§3/§4，文档 v0→v1、**可实施**；1 DEFER（D7-7 umbrella §8 排序）整包实施时按 delta-3 §3 ownership 表执行。
