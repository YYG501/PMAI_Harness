# TODOS

> 只放**开放项**：待决策 / 已 defer 待触发 / 阻塞中。
> 条目一旦实施完成或被废弃，**从本文件移除** —— 溯源由 git history + `CHANGELOG.md` + `docs/归档/` 设计文档承担，不在 TODO 清单里留「已完成存根」。

---

## v2: 状态物化到 worktree 生命周期 — ✅ 已落地（2026-05-30，CHANGELOG 474fff5）

> 下方为历史设计上下文；实际落地与原计划的差异见本节末「✅ 已落地」条。

**What:** 把 task 状态从「markdown 字段」升级为「文件系统约束」。具体（2026-05-08「待验收」合并入「执行中」后简化）：
- `/task-confirm`（待执行→执行中）才 `git worktree add`
- 注：「执行中」覆盖 AI 实现期 + PM 验收期；commit 不切状态；如要在 PM 验收期 lock，需在 commit 后用文件标记区分「实现完毕等 PM」vs「PM 打回等 AI」
- PM 打回不切状态（task 仍是「执行中」），AI 续修；如有 lock 需 unlock
- `/close-task`（已完成 → 删 worktree）`git worktree remove`

**Why:** v1 的防御链（check-branch.sh 状态 gate、adapter 层 gate、/task-execute 入口校验）都依赖 agent 读 task 文件的状态字段并尊重它。如果 agent 不读 task 文件、只按 orchestrator 给的 prompt 盲干，状态字段对它就是摆设。物化后，agent 想跳过状态机就**物理上没地方写代码**——worktree 不存在或只读。

**Pros:**
- 真正 fail-closed：任何 agent、任何执行器都绕不过
- 自然表达 serial 约束——同时只能有一个 worktree 处于"可写"
- 跨 task 代码污染（上次事件 task-005 worktree 里混进 task-001~004 代码）物理不可能

**Cons:**
- 改动面：`create-task-worktree.sh`、`task-transition.py`、`close-task.sh`、`build-execution-prompt.py`、`/task-submit` skill 五处耦合调整
- `git worktree lock` 对外部 executor（Codex）未验证——Codex 在 workspace-write 模式下是否遵守 lock 需测
- `chmod -R a-w` 兜底方案需处理 dev server 的生成物目录（`.next/`、`dist/`）
- 生命周期变化后 `/task-execute` 的 pending-manual 续跑（`.pending-manual-*.json`）语义需要重想

**Context（2026-04-22 事件复盘）:**
- 19:18–20:16 约 1 小时，某 Codex suborchestrator 一口气实现 task-001→006
- task-005 commit `chore: bring in task-001~004 code` 和 task-006 `seed: 集成 task-001~005 全部实现`说明**worktree 边界被当场折断**
- 所有 task 状态字段停在"待执行"，PM 未见验收信息
- 这次用 v1 的 adapter gate + close-task 事件流审计（I-CT7/I-CT8）兜底；数据还不足支撑架构大改，先观察

**Depends on / blocked by:**
- v1 护栏上线后积累 3-5 次真实事件数据再决定
- 或 v1 防御被证明存在结构性漏洞
- 需验证 `git worktree lock` 对 Codex CLI 的约束力

**下次接任者要知道:**
- 当前 worktree lifecycle：`create-task-worktree.sh` 在 `/task-confirm` 时建
- serial 约束（I-TT2）只在 `task-transition.py` 的 `待执行→执行中` 时校验——不走 transition 就没校验
- `git worktree lock` 是 git 自带功能，会拦 `git worktree remove` 但不会拦 fs-level 写入；真实约束力需 POC
- chmod 方案和 lock 方案的 tradeoff 要考虑

**2026-05-29 office-hours 重构决议（plan-eng-review，= 重构任务 #8）**：
- PM 拍板：自动托管（AI 自动建 / merge / 删 task worktree、PM 零窗口切换）**早上、随阶段 0 做**（不再 defer 等数据攒够）。
- spike 验收标准升级：除 happy-path（自动建/merge/删），**必须复现 2026-04-22 串台事故场景 + 证明物化约束（worktree lock / chmod）挡得住**——本「状态物化」即采纳作加固。
- ✅ **已落地（2026-05-30，CHANGELOG 474fff5 + 84fed8a）**：worktree lock（建即 lock、close/discard/cleanup 删前 unlock）+ **一 task 一执行器结构化防线**（2026-04-22 串台根因 = 一执行器干多 task，结构上禁掉）+ **并行多 task 编排**（/pmai-next 按 task-plan 串/并/混派发）。回归测试 `test-worktree-lock.sh`，基线 535 全绿。
  - **与原计划的差异**：原 v2 的 `chmod` 物理写约束**不适合并行**（同 uid 多执行器无法互相只读）→ 改用结构化防线（一 task 一执行器 + dispatch 越界保护）防跨 task 串台，`git worktree lock` 专管移除竞态。
  - **真 Codex POC 已跑（2026-05-30）→ C（config 收窄）死、PM 拍 A（接受残留）**：codex `workspace-write` 实测放行整个 `$HOME`（cwd / `writable_roots` 都收不窄）、`git lock` 不拦 fs 写 → **外部执行器无法靠 config 物理隔离**；chmod 也不适合并行（同 uid）。防线 = 结构化（一 task 一执行器 + 越界保护），挡历史事故形态足够；真物理隔离（容器 / 独立 uid）对单人工具不成比例、不做。**别再试 config 收窄（已证死）。**

---

## DX backlog (来自 plan-devex-review 2026-04-25)

来源：`docs/归档/废弃/设计-stage5-6-task循环.md` 的 plan-devex-review 产出。这些 friction 不在该 plan scope 内，作为后续独立改进点。

### Discover stage (新 PM 第一次接触框架)
- **D1**：README.md 极简，没说"如何 init project"——PM 第一次看 README 不知道下一步
- **D2**：缺 stage 1-7 流程图——PM 不知道整个流程长什么样
- **D3**：缺 skill 命令汇总（cancel-req / close-req / quick-fix / ...）——PM 要 ls skills/ 才能看到全集

### Install stage
- **I1**：gstack 是硬依赖但 README 没提——PM 第一次跑 init-project 才知道要装 gstack
- **I2**：init-project.sh 必须在框架仓里跑（不是业务项目里），容易搞错位置

### Hello World stage (PM 第一个 req 跑通的 TTHW)
- **HW1**：要走 stage 1-4 才到 task-plan 阶段——TTHW 几小时（office-hours 六问拖时间）
- **HW2**：新设计在 stage 5 进一步切（先 task-plan.md，后 task-spec），意味着更多 round trip 才"看到第一个 task 跑通"
- **HW3**：PM 走第一个 req 时大概率没用过 stage 5/6 任何一次，每个新 skill 的语义需边走边学

### Debug stage
- **DB1**：错误信息用 INVARIANTS 编号（I-CT7 / I-CT8 等），对 PM 不友好——失败时不知道是哪一步漏了

### Upgrade（独立子设计）
- **UP**：框架同步自动化 — 当前是 `框架同步-SOP.md` 手动流程（hotfix 阶段过渡），结构稳定后改自动化
  - 设计文档：`docs/归档/完成/设计-框架同步.md`（v1 定稿 2026-04-26）
  - 范围：S1 sync 脚本 + manifest / S2 worktree impact 报告 / S3 module lazy migration
  - **不覆盖**：v1 项目首次迁移（结构差异大，单独再开 req 做一次性迁移脚本）
  - **下一步**：按设计 §12 phase P1→P4 实施

---

## Eng backlog (来自 plan-eng-review 2026-04-25)

来源：`docs/归档/废弃/设计-stage5-6-task循环.md` 的 plan-eng-review 产出。本 plan scope 外，作为后续改进点。

### A2: 多 req 并行 merge module 规格的 markdown conflict
- **What**: 多 req 同时 stage 6 时，doc-update 沉淀同一 module 规格会在 git merge 时撞 markdown 表格 + 编号需求列表的 conflict
- **Why**: 当前决议 (D) Defer——PM 单人多 req 并行频率低，先 ship 撞了再说
- **可能解法**：
  - 加功能稳定 id（推翻 Q5 决议）
  - 文件锁串行化（限制同 module 并行）
  - 自定义 merge driver 处理表格行
- **触发条件**：撞上 2+ 次后启动设计

### C-fix1: doc-update 长期拆分
- **What**: doc-update 现在身兼 "对账模式"（处理文档偏差）+ "沉淀模式"（merge 功能清单）
- **Why**: 两件事概念不同、code path 不同（已经在 §1.5/1.6 分流，但越加越多）。如果以后还要加第三种（比如沉淀 user story 进 user-flow.md），doc-update 会变成超大 skill
- **可能解法**：拆成 doc-deviation（处理偏差）+ doc-sink（沉淀），各自独立 SKILL.md
- **触发条件**：plan-eng-review 发现 doc-update 加任何新职责时启动

---

## v3.5 探测档延迟决策（来自 plan-eng-review 2026-04-29 / 阶段 4.5）

来源：`docs/归档/完成/实施计划-实现程度与格式对齐.md` 阶段 4.5（项目级工程结构约束 — 探测档）。完整档功能延后做，先看探测档跑过 1-2 个真实 req 的实证再决定。

### TD-1: 探测档 → 完整档（compare + restructure-suggest）
- **What**: 在探测档基础上加 `scripts/compare-structure-to-intent.py`（生成改造建议报告）+ `skills/restructure-suggest/SKILL.md`（PM 主动调用重做对比）
- **Why**: 探测档让 detect 自动写 CLAUDE.md，但**不主动给改造建议**。已有项目结构与 PM 意图错配时（如 ExampleConsumerApp system 风格 + PM 想做原型），目前只能 PM 自己读 CLAUDE.md auto-detected 段判断是否需要改造
- **Pros**: PM 看到具体"砍 framework/page/Template / 保留 components/ui"等可执行建议；改造作为普通 req 走完整流程
- **Cons**: +1 天工程；首次手填或手动 compare 的成本可能就够了（YAGNI）；启发式生成"改造建议"可能误判
- **Context**: ExampleConsumerApp 与 AI 对话已经手动得出过类似建议（"砍 framework/page/Template / framework/hooks / framework/context / modules/pages/ / modules/*/lib/store"，"保留 components/ui / framework/layout / app/ / framework/config"）—— 那次对话证明这件事**可以人工做**，但是否值得自动化要看 PM 第二次第三次想用时的痛感
- **触发条件**: 探测档跑过 ≥ 1 个真实 req 后，PM 实际撞到"想知道现状 vs 意图差距"的需求
- **Depends on**: 阶段 4.5 探测档已上线 + 至少 1 个真实 req 用过新流程

### TD-2: 旧 req（已 confirmed task）应对 5.0 新增 CLAUDE.md「工程结构约束」段
- **What**: 当前兼容档让旧 task 跳过项目级工程结构约束读取。新决策：让旧 task 也按字段级 hash 同步新约束
- **Why**: 5.0 上线后，旧 req 的 task-execute 不读 CLAUDE.md「工程结构约束」段——AI 实现时按旧 prompt 走，可能仍抽 Template。但旧 task 已经跑了一半，强制同步可能破坏已 confirmed 契约
- **Pros**: 全项目一致；旧 task 也享受工程结构约束
- **Cons**: 字段级 stale 可能频繁触发；PM 要为旧 task 做 ack-stale 决策（PM 心智上升）
- **Context**: 类似 v3 阶段 8.3 字段级 stale 的设计，但作用对象是 CLAUDE.md「工程结构约束」段而不是 solution.md「本轮实现程度」字段
- **触发条件**: 探测档跑过且发现"旧 task 实现跟新 task 工程结构差异明显"
- **Depends on**: 阶段 4.5 + 阶段 8.3 字段级 stale 机制都已上线

### TD-3: 多 prototype-root 项目（monorepo / 多产品仓）增强
- **What**: 当前 detect 仅识别**第一个** prototype-root（`prototypes/src/` 或 `src/`）。未来支持 monorepo / 多产品仓——按 `apps/<app>/src/` 或类似路径分别管理
- **Why**: PM-AI-Workflow 当前服务的项目大多是单仓单原型（如 ExampleConsumerApp），但未来可能服务 monorepo
- **Pros**: 支持复杂仓库结构
- **Cons**: 复杂度上升（每个 app 一份 CLAUDE.md「工程结构约束」段？还是一份全局段配多 root？）；当前 PM 单仓单原型已够
- **Context**: 阶段 4.5.1 detect schema 的 `scan_roots_default` 已列 `apps/*/src/`，但只取第一个命中的根。增强方向是返回多个 root 让 PM 选
- **触发条件**: PM-AI-Workflow 实际服务过 monorepo 项目
- **Depends on**: 阶段 4.5 已上线

### TD-4: detect 信号 schema 加版本号 + migration 脚本
- **What**: 当前 schema 用 `schema_version: 1` 字段标版本，但**没有 migration 脚本**——schema 演进时旧项目 CLAUDE.md auto-detected 段不会自动升级
- **Why**: schema 在 v1 阶段尚稳定，但若未来加新信号（如检测 `services/` 层 / `react-query` 用法等），旧 CLAUDE.md auto-detected 段会和新 schema 不匹配
- **Pros**: 未来 schema 演进有明确 migration 路径
- **Cons**: 现在还在 v1，未来 v2 才需要——典型 YAGNI；写一份 migration 脚本约 0.5 天
- **Context**: 类似 v3 阶段 1 的 fixture v1/v2 双轨思路
- **触发条件**: 实际触发 schema_version: 2（schema 加新信号或改信号语义）
- **Depends on**: schema 真有第二个版本

### TD-X1: task-spec revise 触发条件门（步骤 5/6 用 git log 比对跳过过期数据）
- **What**: revise 模式步骤 5/6 当前按 §9.1.1 grep 强约束执行；进一步收敛——加触发条件门：自上次 task PM 视图最后一次 commit 以来，同模块 task 是否有新 close 事件 / prd.md 或 implementation-design.md 是否有 commit。无变更则整段跳过
- **Why**: revise 痛点场景已 8008 → 4400（省 45%）；TD-X1 上线可再省 ~300 行（同模块 task PM 反馈段 + prd / implementation-design 章节 grep 在大多数 revise 场景没新内容）
- **Pros**: revise 更轻量；触发机制可机器判（git log）
- **Cons**: 触发条件机制要落地（mtime 不可靠必须 git log）；增加 revise 判别复杂度
- **Context**: docs/归档/完成/设计-skill读取收敛.md §3 不做项理由；reconcile 已用 hash 收敛过可借鉴
- **触发条件**: 实测 transcript 显示 P0+P1+P2+§4.4 落地后 revise 仍超 5000 行
- **Depends on**: docs/归档/完成/设计-skill读取收敛.md 全部落地（已 commit be47fca）

### TD-X2: docs/modules/* INDEX 索引化（first-gen 阶段 modules 全文必读 → INDEX + 涉及模块）
- **What**: 当前 §9.1 让 prd-writing / implementation-design / task-plan 必读全部 modules/*.md。砍成"INDEX.md 必读 + 本 req 涉及模块全文 + 其他 grep 按需"
- **Why**: req-003 实测 modules 总 ~4900 行，拆 task / 写 PRD 实际只用涉及模块 + 索引。砍后 prd-writing / implementation-design / task-plan 各省 ~3000 行
- **Pros**: 大头节省；"全局复用判断"靠 INDEX + grep 也能覆盖
- **Cons**: 依赖 INDEX 完整性（如果 INDEX 没及时更新会漏掉新模块）
- **Context**: docs/归档/完成/设计-skill读取收敛.md §3.1 R3 已记
- **触发条件**: INDEX 完整性机制落地后（如 INDEX hash 比对 / 写入时机自动更新）
- **Depends on**: INDEX 维护机制

### TD-X3: 基于实测 transcript 二次审视激进收敛
- **What**: 跑一次真实 task-spec revise（在 req-003 worktree），抓 transcript 验证实际节省。若 < 30%，再考虑激进收敛（砍 DESIGN / brief / analysis 必读）
- **Why**: 设计文档算账估 45%，但 AI 实际行为可能偏离（grep 关键词选错 / 偶尔补 offset 续读 / lint round-trip 仍触发）
- **Pros**: 数据驱动决策，不靠估算
- **Cons**: 要真跑一次，耗 PM 时间
- **Context**: docs/归档/完成/设计-skill读取收敛.md §5.2 实测验证段
- **触发条件**: P0+P1+P2+§4.4 上线后第一个真实 task-spec revise
- **Depends on**: 已 commit be47fca

---

## 框架分发与全局安装（架构级，2026-05-26 PM 提出）

**设计文档**：[`docs/设计/框架分发与全局安装.md`](docs/设计/框架分发与全局安装.md)（v0 草稿，等 PM 锁 §0）。下面只留一句话索引 + 待决策点；完整内容看设计文档。

**What:** 重新设计框架的"安装 → 初始化"入口，让起新消费仓**不再依赖 cwd 在生成器仓里**。参考 GSD npm 包形态：装一次到全局 / 项目，然后任意位置跑 init。

**Why:** 当前 PM-AI-Workflow 这个仓同时背两个角色——
1. 生成器开发仓（演化 `scripts/skills/templates/`）
2. 消费仓启动器（PM 起新项目时 `cd` 进来跑 `/init-project`）

角色混淆代价：起新项目要 `cd ~/Projects/PM-AI-Workflow` 反直觉；分发给别人用 = 不可能（他们没这个仓）；框架仓 dirty working tree 时不该兼任 launcher；与 GSD 等同类工具的心智模型不一致。

**3 个候选模式：**

| 模式 | 怎么用 | 工作量 |
|---|---|---|
| A. npm/brew 全局包 | `pmai install -g` → `cd <anywhere>` → `pmai init` | 大：打包发布 / 版本管理 / 升级通道 |
| B. install.sh 一行 | `cd <new-dir>` → `curl <url>/install.sh \| bash` → `/init-project` | 中：托管 install 脚本 + 升级机制 |
| C. 当前 hack | `cd PM-AI-Workflow` → `/init-project` | 0，但持续承受反直觉 |

**Depends on / blocked by:**
- 跟 `框架同步-SOP.md`（hotfix 阶段过渡 SOP）整合：安装模式应同时承载初次 install + 后续 sync upgrade
- 跟 `docs/归档/完成/设计-框架同步.md` §5 sync 脚本设计协调（manifest 机制可复用）
- 看 DX backlog `I2`（init-project.sh 必须在框架仓里跑，容易搞错位置）—— 同一根因，可并入

**下次接任者要知道:**
- 当前 hack：`/init-project` skill 通过 cwd 在生成器仓获得加载权；阶段 A 收"落地路径"绝对路径；产物全落到该路径，框架仓 working tree 不受污染
- 触发讨论时点：PM 有几次起新消费仓的体感后；或下游有第二人要用框架时
- 不要先把 `框架同步-SOP.md` 实施了 —— 它跟本条都涉及"框架资产怎么进消费仓"，应一起想

---

**注**：TD-5（DESIGN.md vs CLAUDE.md「工程结构约束」边界文档）已直接落到 CLAUDE.md.tmpl 段顶部注释（阶段 4.5.3），不进 TODOS。
