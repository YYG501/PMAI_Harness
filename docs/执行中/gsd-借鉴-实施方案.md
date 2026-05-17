<!-- /autoplan restore point: <LOCAL_GSTACK_HOME>/projects/PM-AI-Workflow/main-autoplan-restore-20260517-214638.md -->
# GSD 借鉴 — 实施方案 (v3)

> **状态**：待执行 / PM 已逐项判定锁定 + autoplan v2 Eng/DX 实施细节修订 + v3 砍「决策」独立类别
> **日期**：2026-05-17
> **作者**：PM + AI
> **来源**：从 `docs/归档/完成/gsd-借鉴-研究分析.md` v3.10 §10.7 抽取；v1 PM 1-1 判定；v2 autoplan Phase 1+3+3.5 落实施细节；v3 砍「决策」独立类别
> **服务对象**：主仓 framework 开发者（PM + AI）；不进消费仓同步 SOP

---

**Changelog**：
- **v3（本版，2026-05-17）：砍「决策」独立类别** —— PM 反馈"5 个相关位置太乱 + ADR 是 PMAI 自创方言"。砍 docs/决策-索引.md + docs/设计/_模板-决策.md + docs/归档/完成/modulespec-维护/决策.md（独特"触发重新评估条件"3 条已 merge 进同目录主方案.md §Y 决议日志段）。下一步实施清单 3 项 → 2 项（原 #1 ADR 决策记录格式整段砍：已通过文档目录整理 + 主方案 §Y 决议日志段解决，不再需要单独"决策"文件类别）。框架决策散落痛点已通过本 session commits 82a329a/ac2abcd 文档目录整理 + 主方案模板 §Y 段解决。
- **v2（2026-05-17）：autoplan 评审落实施细节** —— Phase 1 CEO dual voices (codex+claude subagent) 7/8 维度 CONFIRMED user challenge，PM 选 Y（接受 #1 缩 + #2 #3 保持重版）；Phase 3 Eng dual voices 9/10 维度 CONFIRMED 实施细节修订；Phase 3.5 DX single voice 落 5 细节 finding。Final Gate PM 选 A（接受全部默认 + Choice 1 lark-adapter functional API）。
- **v1（2026-05-17）：PM 1-1 判定后从 docs/归档/完成/gsd-借鉴-研究分析.md v3.10 §10.7 抽取**

---

## §0 背景（PM 已锁定，不可反向修改）

### §0.1 这份文档存在的原因

`docs/归档/完成/gsd-借鉴-研究分析.md` 是研究分析（1683 行 / v3.10 / 10 轮迭代 / 含 28 项原始候选 + 7 项 §10.7 落选项推导链）。研究阶段已完成，但研究文档太长不适合直接当"下一步做什么"的执行依据。

本文档是抽取后的纯实施清单——2 项要做的、按什么节奏做、不做的那 4+ 项是什么 + 为什么不做。

### §0.2 真痛点（按 `_模板-方案.md` §0 痛点锁原则）

| # | 痛点 | EVIDENCE（实证）|
|---|---|---|
| 1 | lark-cli 未来出现第二个调用脚本时会重复 4 连 fix 历史 | 现状 16 处 lark-cli 调用全在 `scripts/publish-to-lark.py`；PM 确认会写第二个（weekly report / memory sync 等） |
| 2 | AI 跨 skill 读 state 不一致 | autoplan v2 修正：实际 4 个 Python script + 1 段 jq 读 `.req-meta.json`（不是"10 skill 各自 grep"）；`status-view.py` 输出是 PM 视觉格式不是 AI 解析；schema 变多处都要改 |

> **v3 已解痛点**：原痛点「框架决策散落、格式不统一」已通过本 session commits 82a329a + ac2abcd 文档目录整理（按生命周期分 设计/执行中/归档[完成/废弃]）+ `_模板-方案.md` §Y 决议日志段解决；不再需要独立"决策"文件类别。

### §0.3 不解决什么（防 review 把这些拉进来）

| # | 衍生场景 | 为什么不在 §0 范围 |
|---|---|---|
| 1 | "把所有 GSD 67 命令 33 agent 都评估一遍" | 已在研究阶段砍掉 14 项废弃 + 5 项暂停 + 12 项等触发；本实施阶段只做 §10.7 锁定的 2 项 |
| 2 | "改造 SKILL.md 格式" | 跟 Claude Code 官方标准无冲突但是 PMAI 自创"方言"，违反 memory `feedback_gstack_keep_official`；之前 commit be47fca 落地的 PM-VIEW-RULES §9.1 单一权威源方案已是当前可行最优 |
| 3 | "集中 mutation 入口（写层统一）" | 现状 `/task-status` + I-DC1/I-AD5 三道防线已够；真痛点在读层（本文档 #2 覆盖）不在写层；PMAI 1-2 天 grok mutation_lib 是 D13 同模式 trap |
| 4 | "建独立『决策』文件类别 / 索引 / 模板"（v3 新增「不解决」）| 5 个相关位置太乱 + ADR 是 PMAI 自创方言；`_模板-方案.md` §Y 决议日志段已能记决策；不强求文件级独立 |

---

## §1 实施清单（2 项）

### 实施 #1: lark-adapter 单一入口 + lint（b 方案 + autoplan v2 实施细节）

**目标**：未来出现第二个调 lark-cli 的脚本（PM 确认会写：weekly report / memory sync / 等）时不重复 4 连 fix 历史

**v2 修订**（Eng consensus + DX finding）：
- API 形态：**functional + module-level**（PM Choice 1 选 A）
- **必须封装 cwd workaround**：lark-cli 对 `@绝对路径` 有 bug，需 `cwd=markdown.parent` + `@./filename`；adapter API 强制接 `Path`，禁止接 `@...` 字符串
- API surface 实际是 **~5 个核心方法**（不是 16）：`version() / auth_status() / auth_check(scopes) / docs_create_from_markdown() / docs_update_from_markdown() / api_json()`
- lint 扫**三类 pattern**：`["lark-cli"` / `'lark-cli'` / `subprocess.*lark-cli`
- lint allowlist：`scripts/_lib/lark_adapter.py` 自身 + SKILL.md 教学段（grep `^[^#]*\blark-cli\s+(docs|api|auth)\b`）
- 必须先加 **fixture shim**：fake `lark-cli` 脚本回 JSON fixture，跑 `publish_first_time` + `publish_overwrite` + `merge_cells_for_doc` smoke
- 加 `python -m _lib.lark_adapter doctor` 子命令：PM 在 chat 里直接复制粘贴跑（DX finding 4）

**实施清单（~0.5-0.7d）**：
- 抽 `scripts/_lib/lark_adapter.py`（functional API + cwd workaround 强制）
- 写 fake `lark-cli` shim + `tests/test-lark-adapter.sh`
- 重构 `publish-to-lark.py` 调 adapter（业务逻辑不动 - parse_frontmatter / target resolution / 表格 merge 编排保留）
- 写 lint 脚本扫三类 pattern + allowlist
- 加 `__main__ doctor` 子命令
- 跑回归（重点：JSON shape 兼容 + cell merge 顺序）

**不做**：
- 不抄 GSD SDK 双实现（`docs/归档/完成/gsd-借鉴-研究分析.md` §4.1 已决拒绝）
- 不抽 publish 业务层（`publish_doc/publish_sheet` 大而全 functional API 现在是过早抽象）

**风险**：低（adapter 多一层间接，但有 lint + fixture 锁住未来不退化）

---

### 实施 #2: 读层 `_lib/state.py`（v2 重大修订：扩展 task_parser，不新建）

**目标**：让 AI 跨 skill 用统一接口读 state；当前是"PM 看 `/task-status` 视觉视图，AI 各 skill 各自 grep raw state"双轨制

**v2 重大修订**（Eng consensus critical finding）：
- **不新建 `state_reader.py`，改为「扩展 `_lib/task_parser.py` 升格为 `_lib/state.py`」**
  - 理由：现有 `task_parser.py` 已是 task 元数据 v1/v2 兼容层（`get_task_status / get_task_branch / get_task_meta / read_section`）；新建 state_reader 会引入双权威源
  - 做法：在 task_parser.py 基础上新增 `read_req_meta / list_active_reqs / read_task_events / get_overall_state`，整体 rename 为 `state.py`
- **`status-view.py` 必须反向 import state.py dogfood**
  - 否则 status-view 仍是另一套 truth → 讽刺地复现正要解决的"双轨"问题
  - status-view.py 改成纯 render 层；扫描 / parse / 聚合逻辑全走 state.py
- EVIDENCE 修正：实际 4 Python script + 1 段 jq 读 `.req-meta.json`（不是"10 skill 各自 grep"）
- API 最小面（DX finding 2 要求每函数说明 None 3 种语义 + 异常边界 + doctest）：
  - `read_req_meta(req_dir, strict=True) -> dict`
  - `list_active_reqs(repo_root, cwd=None, strict=False) -> {items, warnings}`
  - `read_task_meta(task_path) -> dict | None`（沿用 task_parser）
  - `read_task_status(task_path) -> str | None`（沿用 task_parser）
  - `read_task_events(repo_root, task_id, tail=None) -> list[dict]`（注：事件文件在 repo root `.runs/events/<task>.jsonl`，不是 task path 下）
  - `read_task_plan(req_dir) -> dict | None`
  - `list_tasks(req_dir) -> list[dict]`
  - `get_overall_state(repo_root, cwd=None, strict=False) -> dict`（status-view.py 直接消费）
- **错误契约 strict/tolerant 分模式**：
  - 单文件 reader（`read_req_meta` / `read_task_meta`）默认 **strict** 抛 `StateReadError(path, reason)`
  - 聚合扫描（`list_active_reqs` / `get_overall_state`）默认 **tolerant** 返回 `warnings`
  - `status-view.py` 渲染 warning；skill 可显式选 strict
- **active req 探测算法统一**：现 `status-view.py:200` 只扫 `.worktrees/req-*`，`skill-preamble.sh:112` 用 `git worktree list` helper 优先；两套不统一会导致 main / req / task 窗口看到不同 active req → state.py 必须采用 worktree-list 语义，让 preamble + status-view 共用
- 加 `python -m _lib.state doctor <req>` 子命令：打印当前文件 vs 期望 schema diff（DX finding 4）

**实施清单（~0.5d）**：
- 把 `_lib/task_parser.py` 扩展并 rename 为 `_lib/state.py`
- 把 `status-view.py:133-211` 的 `_collect_active_from / find_all_active_reqs` lift-and-shift 到 state.py
- status-view.py 改成纯 render 层（消费 `state.get_overall_state()`）
- 改 `req-transition.py:37` `task-transition.py:438` `acceptance-handoff.md:13` 一段 jq 走 state.py（实际 4 script + 1 jq）
- `skills/_shared/pm-view/input-flow.md §9.1` 表头加一段：「凡涉及 task 元数据 / req-meta / events 的读取一律走 `_lib/state.py`，不在本表中重复列；本表只管 markdown 内容读取」（DX finding 3）
- 加 `__main__ doctor` 子命令
- 加 unit test 覆盖：v1/v2 task / multi active / task worktree cwd / missing+corrupt meta / pending spec / discarded task / 事件缺失+坏 JSON

**为什么是读层不是写层**：
- 写层（mutation_lib）已在 §0.3 列入"不解决"
- 真痛点在 AI 跨 skill 读不一致；schema 变多处都要改

**风险**：低（扩展现有 lib + dogfood status-view，不动数据本身）

---

## §2 启动建议

| 阶段 | 任务 | 估时 | 类型 |
|---|---|---|---|
| 1 | #2 state.py（扩 task_parser + dogfood status-view）| ~0.5d | 代码 |
| 2 | #1 lark-adapter + lint + fixture | ~0.5-0.7d | 代码 |

**总计 ~1-1.2d CC**

**推荐起手**：先做 #2 state.py（架构改造影响更广，fresh context 干），然后 #1 lark-adapter。每个阶段独立 commit。

---

## §3 不在范围内（PM 已决）

### ❌ 砍（明确不做）

| 项 | 原因 |
|---|---|
| `skill_structure.yml` manifest | 跟 commit be47fca 落地的 PM-VIEW-RULES §9.1 单一权威源方案冲突；触发双源漂移 |
| `<required_reading>` XML 块显式化 | 违反"单一权威源"原则；散到 20 SKILL.md = 把 §9.1 内容散回各文件 |
| SKILL 5 段骨架（强制 skill 同构） | Claude Code 标准之上长 PMAI"方言"；违反 memory `feedback_gstack_keep_official` |
| 集中 mutation 入口（写层 mutation_lib） | 现状 `/task-status` + 三道防线已够；真痛点在读层（本文档 #2 覆盖）|
| 独立「决策」文件类别 / 索引 / 模板（v3 砍）| 5 个相关位置太乱 + ADR 是 PMAI 自创方言；`_模板-方案.md` §Y 决议日志段已能记决策；不强求文件级独立 |

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
| v1 抽取 | 从 archive/gsd-借鉴分析.md §10.7 抽出 #1 c (ADR) + #2 b (lark-adapter) + #3 b (state_reader) 三项 |
| v2 autoplan Phase 1 CEO | dual voices 7/8 维度 CONFIRMED user challenge；PM 选 Y（接受 #1 缩 + #2 #3 保持重版） |
| v2 autoplan Phase 3 Eng | dual voices 9/10 维度 CONFIRMED 实施细节：#3 改"扩 task_parser 不新建"；#2 必须封装 cwd workaround；#3 工作量 1d → 0.5d |
| v2 autoplan Phase 3.5 DX | single voice 5 finding：命名约定 / INDEX 单文件 / docstring 完备度 / §9.1 加表头 |
| v2 Final Gate | PM 选 A：接受全部默认 + #2 API 选 functional + module-level |
| **v3（本版）** | PM "好乱啊" → 砍「决策」独立类别（5 个相关位置太多）；实施 3 项 → 2 项 |

---

## §5 不变量约束（实施时需保持）

- 不动 I-DC1 / I-AD5 三道防线（即使做 #2 state.py 也不碰）
- 不抄 GSD SDK 双实现（archive §4.1 已决）
- state.py 是 read-only lib，不引入 mutation 路径
- 所有改动按 `框架同步-SOP.md` 流程同步到消费仓（#1 lark-adapter 改动需要同步；#2 state.py 由消费仓决定）

---

## §6 Cross-Phase Themes（autoplan v2 沉淀）

两个独立 reviewer 在不同 phase 多次命中的共识：

1. **「不重新发明，扩展现有」**（Phase 3 Eng + DX 共识）
   - state.py 扩 task_parser（不新建 state_reader）
   - v3 砍「决策」独立类别（用方案模板 §Y 段，不另建文件类）

2. **「显式化已有 workaround」**（Phase 3 Eng + DX 共识）
   - cwd workaround 必须封装进 adapter 强制
   - 历史归档不批量回填要写明
   - docstring 边界（None 3 种语义 + 异常）必须 explicit

3. **「dogfood」**（Phase 3 Eng critical）
   - status-view 必须反向 import state.py，否则讽刺复现双轨

---

**End of GSD 借鉴 — 实施方案 v3**
