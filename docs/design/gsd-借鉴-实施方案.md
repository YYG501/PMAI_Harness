# GSD 借鉴 — 实施方案 (v1)

> **状态**：待执行 / PM 已逐项判定锁定
> **日期**：2026-05-17
> **作者**：PM + AI
> **来源**：从 `docs/archive/gsd-借鉴分析.md` v3.10 §10.7 抽取（研究素材 + 决策推导链原文档已存档）
> **服务对象**：主仓 framework 开发者（PM + AI）；不进消费仓同步 SOP

---

## §0 背景（PM 已锁定，不可反向修改）

### §0.1 这份文档存在的原因

`docs/archive/gsd-借鉴分析.md` 是研究分析（1683 行 / v3.10 / 10 轮迭代 / 含 28 项原始候选 + 7 项 §10.7 落选项推导链）。研究阶段已完成，但研究文档太长不适合直接当"下一步做什么"的执行依据。

本文档是抽取后的纯实施清单——3 项要做的、按什么节奏做、不做的那 4 项是什么 + 为什么不做。

### §0.2 真痛点（按 `_TEMPLATE-design-doc.md` §0 痛点锁原则）

| # | 痛点 | EVIDENCE（实证）|
|---|---|---|
| 1 | 框架决策散落、格式不统一 | `docs/design/` 5 份 + `docs/archive/design/` 21 份 + RUNTIME.md 394 行 + TODOS.md 399 行；查 D13 "为什么砍 stage 5/6/7/8/9" 要翻 3 处 |
| 2 | lark-cli 未来出现第二个调用脚本时会重复 4 连 fix 历史 | 现状 16 处 lark-cli 调用全在 `scripts/publish-to-lark.py`；PM 确认会写第二个（weekly report / memory sync 等） |
| 3 | AI 跨 skill 读 state 不一致 | 7 skill 走 `/task-status`（PM 视觉格式），10 skill 各自 grep raw state；schema 变 10 处都要改 |

### §0.3 不解决什么（防 review 把这些拉进来）

| # | 衍生场景 | 为什么不在 §0 范围 |
|---|---|---|
| 1 | "把所有 GSD 67 命令 33 agent 都评估一遍" | 已在研究阶段砍掉 14 项废弃 + 5 项暂停 + 12 项等触发；本实施阶段只做 §10.7 锁定的 3 项 |
| 2 | "改造 SKILL.md 格式" | 跟 Claude Code 官方标准无冲突但是 PMAI 自创"方言"，违反 memory `feedback_gstack_keep_official`；之前 commit be47fca 落地的 PM-VIEW-RULES §9.1 单一权威源方案已是当前可行最优 |
| 3 | "集中 mutation 入口（写层统一）" | 现状 `/task-status` + I-DC1/I-AD5 三道防线已够；真痛点在读层（本文档 #3 覆盖）不在写层；PMAI 1-2 天 grok mutation_lib 是 D13 同模式 trap |
| 4 | "把决策回填扩到 archive/design/ 21 份废稿" | 触发条件式补：PM 某次查不到决策根因时再为那个决策补 ADR |

---

## §1 实施清单（3 项）

### 实施 #1: ADR 格式 + `docs/adr/`（c 方案：模板 + D1-D15 回填）

**目标**：建立重大设计决策的标准 anchor，解决"格式不统一"

**两阶段拆分**：

**阶段 1A：模板 + ADR-0001（0.5d）**
- 建 `docs/adr/` 目录
- 写 `ADR-TEMPLATE.md`（4 段：背景 / 决策 / 后果 / 状态）
- 写 ADR-0001 = D13 modulespec 维护方案（源材料：`docs/design/modulespec-重写方案.md` + `docs/design/prd-modulespec-重构.md` + `docs/design/d13-验证脚本.md` + RUNTIME.md D13 段）
- 写 `docs/adr/README.md` ADR 索引

**阶段 1B：回填 D1-D15（1-1.5d 独立可分批）**
- 翻 RUNTIME.md + TODOS.md + `docs/design/` + `archive/design/` 拉出 D1-D15 每条决策
- 每条 ~30-40 行 ADR 文档（机械回填，不重写决策推理过程）
- 回填 ADR-0002 到 ADR-0016（ADR 编号 = ADR 写入时间顺序，不等于 D-编号）
- archive/design/ 21 份废稿 **不批量回填**（触发条件式）

**跟现有 `_TEMPLATE-design-doc.md` 的关系**：
- D-* 设计文档（现有）：大改 / 多 vp / 需要 §0 痛点锁 → 完整 §0-§7 结构
- ADR（新建）：单点决策 / 记录"为什么砍了 X / 选 A 不选 B" → 1 页 4 段
- 并存，按规模选

**范围**：只给主仓；不进 framework 同步 SOP，不进消费仓

**风险**：低（不动现有代码）

---

### 实施 #2: lark-adapter 单一入口 + lint（b 方案）

**目标**：未来出现第二个调 lark-cli 的脚本（PM 确认会写：weekly report / memory sync / 等）时不重复 4 连 fix 历史

**实施要点**：
- 抽 `scripts/_lib/lark_adapter.py`（把 `publish-to-lark.py` 中 16 处 lark-cli 调用搬过来 + 封装接口）
- `publish-to-lark.py` 改成调 adapter，业务逻辑不动
- 写 `tests/test-lark-adapter.sh`：校验全仓没有任何 `subprocess.run(["lark-cli", ...])` 直调（除了 adapter 自己）
- 未来第二个 lark 集成脚本只能走 adapter

**不做**：
- 不抄 GSD SDK 双实现（`docs/archive/gsd-借鉴分析.md` §4.1 已决拒绝）

**工作量**：0.5-1d

**风险**：低（adapter 多一层间接，但有 lint 锁住未来不退化）

---

### 实施 #3: 读层 `_lib/state_reader.py`（b 方案：完整抽 lib）

**目标**：让 AI 跨 skill 用统一接口读 state；当前是"PM 看 `/task-status` 视觉视图，AI 各 skill 各自 grep raw state"双轨制

**EVIDENCE（grep 现状）**：
- 7 个 skill 调用 `status-view.py` 或 `/task-status`：cancel-req / task-execute / task-status / task-spec / task-confirm / input-flow / executor-dispatch
- 7 个 skill 直接读 `.req-meta.json`
- 10 个 skill 直接 grep task.md 状态字段
- `status-view.py` 输出是 PM 视觉友好格式（emoji + 中文 + format print），不是 AI 解析友好的结构化数据

**实施要点（b 方案）**：
- 新建 `scripts/_lib/state_reader.py`，把所有 state 读取逻辑抽到 lib
  - `read_req_meta(req_path) → dict`
  - `read_task_status(task_path) → str`
  - `read_task_events(task_path) → list[dict]`
  - `list_active_reqs() → list[dict]`
  - `get_overall_state() → dict`（status-view.py 需要的结构化数据）
- `status-view.py` 改成走 state_reader 拿数据再 render（PM 视图层）
- 所有 grep raw state 的 skill 改成调 state_reader（10 skill 各自的 grep 全删）
- 加 `tests/test-state-reader.sh` 校验 schema

**为什么是读层不是写层**：
- 写层（mutation_lib）已在 §0.3 列入"不解决"
- 真痛点在 AI 跨 skill 读不一致；schema 变 10 处都要改

**工作量**：1d（涉及 10+ skill 调用点改造，比 a 方案 `status-view.py --json` 重）

**风险**：低（只是把已有读逻辑统一抽出，不动数据本身；但涉及多 skill 改动需逐个验证）

---

## §2 启动建议（3 阶段节奏）

| 阶段 | 任务 | 估时 | 类型 | 并行性 |
|---|---|---|---|---|
| 1 | #1 ADR 模板 + ADR-0001 (D13) | 0.5d | 文档 | ✅ 跟 #3 并行 |
| 1 | #3 state_reader.py (b 方案) | 1d | 代码 | ✅ 跟 #1 并行 |
| 2 | #1 ADR 回填 D1-D15 | 1-1.5d | 文档（机械回填可分批）| — |
| 3 | #2 lark-adapter + lint | 0.5-1d | 代码 | — |

**总计 ~2.5-4d CC**

### 推荐起手

**先做 #1 ADR 模板（0.5d）**：
- 最独立（不动现有代码）
- 立即收益（本文档 + D13 模式有 anchor）
- 跑通模板再决定回填节奏

#3 state_reader.py 是大改动（涉及 10+ skill 调用点），值得 fresh context 干。

---

## §3 不在范围内（PM 已决）

### ❌ 砍（明确不做）

| 项 | 原因 |
|---|---|
| `skill_structure.yml` manifest | 跟 commit be47fca 落地的 PM-VIEW-RULES §9.1 单一权威源方案冲突；触发双源漂移 |
| `<required_reading>` XML 块显式化 | 违反"单一权威源"原则；散到 20 SKILL.md = 把 §9.1 内容散回各文件 |
| SKILL 5 段骨架（强制 skill 同构） | Claude Code 标准之上长 PMAI"方言"；违反 memory `feedback_gstack_keep_official` |
| 集中 mutation 入口（写层 mutation_lib） | 现状 `/task-status` + 三道防线已够；真痛点在读层（本文档 #3 覆盖）|

### ⏸️ 挪等触发（暂不做）

| 项 | 触发条件 |
|---|---|
| `/extract-learnings` 命令 | 重新设计 auto memory 边界后再启动；需先答"消费仓 LEARNINGS.md vs 主仓 auto memory 16 条 vs 现 close-req 归档" |
| Context Monitor hook（50%/70% 警告） | PM 连续 ≥ 3 次因没注意 Claude Code statusline 导致 req 未收口 |

---

## §4 决策路径（关键节点）

| 节点 | 决策 |
|---|---|
| v3.10 PM 1-1 判定 | 主表 7 项 → 3 项；4 项砍 + 1 项 DEFER；新增 #3 读层 state_reader |
| #1 选 c 方案 | 解决"格式不统一"必须模板 + 回填 D1-D15；archive 触发式不批量 |
| #2 选 b 方案 | 抽 adapter + lint，因 PM 确认会写第二个 lark 脚本 |
| #3 选 b 方案 | 完整抽 lib（比 a 选项 `--json` 重但一次性重构干净） |

---

## §5 不变量约束（实施时需保持）

- 不动 I-DC1 / I-AD5 三道防线（即使做 #3 state_reader 也不碰）
- 不抄 GSD SDK 双实现（§4.1 已决）
- ADR 不进 framework 同步 SOP（只主仓用）
- state_reader 是 read-only lib，不引入 mutation 路径
- 所有改动按 `framework 同步-SOP.md` 流程同步到消费仓（如 #2 lark-adapter 改动）；ADR 不同步

---

**End of GSD 借鉴 — 实施方案 v1**
