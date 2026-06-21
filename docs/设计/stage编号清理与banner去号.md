# stage 编号清理与 banner 去号 (v0)

> **状态**：**已落地（2026-06-04）** / §Y 方向已拍（选项1 + banner 纳入）/ 机械清理 + 新 lint hook / 待 PM 总审归档
> **日期**：2026-06-01
> **作者**：PM + AI
> **触发**：消费仓一个 AI 在推进时连续抢跑 + 把 req stage「推过头一格」（1→2→3），根因追到框架 prose 里残留的旧编号。

---

## §0 原始痛点（PM + AI 共写，后续 review **不可反向修改**）

> ⚠️ 任何后续 review / autoplan 都不能给本节加东西、不能重新定义痛点。

### §0.1 痛点（1-3 句）

per-req 状态机权威是 `stages.py` 的 **4 阶段**（1 范围确认 / 2 build / 3 复审 / 4 沉淀），但 runtime AI 实际读的 SKILL prose 里同时散落着**三套不同的编号**——六步概念号 ①-⑥、内部 stage 1-4、以及坍缩重构没清干净的旧 7-stage 实现号（4A / 5 / 6 / 7）。三套编号名字重合（build / 复审 / 沉淀 两边都有）、序号不对齐（六步③build = 内部 stage 2）、且**没有任何一处映射表**，于是 AI 把概念步号 / 旧编号当成 stage 号去推进状态机，推过头。

### §0.2 触发场景

| # | 场景描述 | 实证证据 |
|---|---|---|
| 1 | AI 跑 task-plan→task-spec 流程时把 req stage 推过头一格（1→2→3，本该停在 build=2） | 消费仓 transcript：AI 读到 `task-plan/SKILL.md:320`「具体 task 文档由 **stage 6** 的 /pmai-task-spec」，按旧编号推进 → 越过 build 推到复审 |
| 2 | brownfield 接入时 AI 按旧编号判断「推不到 stage 5」而误判流程 | `codebase-audit/SKILL.md:146`「PM 第一个 req 推不到 **stage 5**」——4 阶段机没有 stage 5 |
| 3 | banner 把内部 stage 号直接打给 PM 看 | `banner-rules.md:24`「Stage **2/4**: build」与 `stages.py:15-16`「banner 已转产品轴、**不再播 Stage N/M**」直接冲突 |

### §0.3 根因（解决什么底层 mechanism）

stage 号是**内部状态标记**（`stages.py:16` 自述「不再 PM-facing」），却漏进了 ① runtime AI 读来做推进决策的 prose、② 打给 PM 看的 banner。六步坍缩重构只改了 `stages.py` / `.sh` 门，**没清 prose 里的旧编号**——而 prose 才是 runtime 真正读的东西（吻合此前 stage 重构 review 的教训：SKILL prose 改了 ≠ 落地）。

### §0.4 不解决什么（显式列，防 review 拉进来）

| # | 衍生 / 假设场景 | 为什么不在 §0 范围 |
|---|---|---|
| 1 | quick-fix 的 drift-scan 产物链重写（brief/analysis/prd → req-plan 新机适配） | 这是 quick-fix 整段逻辑停在旧 7-stage 的**更深 stale**，独立 blast radius，单独议题（见 §5 DEFER）。本次只清编号，不动 quick-fix 产物链语义 |
| 2 | 「六步」这个命名是否退役 | PM 已决策**保留**（六步是概念叙事层，去裸数字后不再误导 runtime；改名 blast 90+ 处 + 真相源设计文档，不值） |
| 3 | PM 视图 banner 的整体文案重做 | 本次只去 stage 号，不重做 banner 的产品轴叙事 |

---

## §1 方案概述

一句话：**让 runtime 永远不需要在 prose 里手算 stage 号。**

三招：
1. **prose 去裸数字** —— 引用阶段一律用名字（范围确认 / build / 复审 / 沉淀），裸 `stage N` 只准出现在 `.py` / `.sh` 代码和 `.req-meta.json` 字段里；
2. **钉一处映射表** —— `input-flow.md §9` 六步框加一列「= 内部 stage N」，作为六步概念号 ↔ 内部 stage 的唯一翻译真相源；
3. **banner 去 stage 号** —— 改 `state.py:433` 单点生成行 + banner-rules 规范，banner 不再给 PM 看 `Stage 2/4`；
4. **加 lint hook** —— 拦 prose 里的裸 `stage\s*\d`，从此回不去。

「六步」名字**原样保留**。

## §2 与现有机制的关系

| | 内容 |
|---|---|
| **保留** | 「六步」概念叙事（①-⑥）；`stages.py` 内部 stage 1-4；gap-check 机制（已确认仍在，归属 build 读 DESIGN + 复审覆盖审计/视觉门查 inventory） |
| **改** | prose 里的旧编号 / 裸数字 → 阶段名；banner 去 stage 号；input-flow §9 加映射列 |
| **砍** | banner 的 `Stage <N>/<T>:` 字段 |
| **新增** | `hooks/check-stage-number-jargon.cjs` + settings.json 注册 |

## §3 实施清单（逐处 现状 → 改法，给 PM 审的 diff 计划）

### 3.A 死编号（旧 7-stage 幽灵，机制还在，重写成新机措辞）

| 文件:行 | 现状 | 改成 |
|---|---|---|
| `task-plan/SKILL.md:320` | 「具体 task 文档由 **stage 6** 的 /pmai-task-spec 生成」 | 「…由 **build 阶段** 的 /pmai-task-spec 生成」 |
| `publish-to-lark/SKILL.md:10` | 「prd-writing 在 **stage 6** 结束模板调用」 | 「prd-writing 在**沉淀阶段**结束模板调用」 |
| `publish-to-lark/SKILL.md:186` | 「prd-writing 在 **stage 6** 结束模板加」 | 「prd-writing 在**沉淀阶段**结束模板加」 |
| `codebase-audit/SKILL.md:144,146,167,182,184,186` | 反复「**stage 4 4A** gap-check」「推不到 **stage 5**」「stage 4 4A 累积」 | gap-check 归属改新机：「**build 阶段读 DESIGN / 复审的覆盖审计·视觉门**查 inventory」；「推不到 stage 5」→「**build 阶段隐性 break**」；「stage 4 4A 累积」→「**复审累积**」 |
| `term-detector/SKILL.md:20` | 「req 推进到 **stage 7** 之后」 | 「req 推进到**沉淀阶段**之后」 |
| `term-detector/SKILL.md:36` | 「两份词典在 **stage 5** 是并集读」 | 「…在 **build 阶段**是并集读」 |
| `term-detector/SKILL.md:24` | 「stage2-office-hours（已退场）」 | 历史注记，已标「已退场」；去裸号或保留加注（低优先） |
| `implementation-design/templates/*.tmpl:40-46,85,114` | 「stage 4→5」「**stage 6** 入口总览」「stage 4 gap-check」 | 该模板整体已 DEPRECATED；建议一并清编号或在 DEPRECATED 头注强调「以下编号为旧 7-stage 语境」（低优先，但仍是雷） |

### 3.B 合法内部引用，名字化

| 文件:行 | 现状 | 改成 |
|---|---|---|
| `cancel-req/SKILL.md:55` | 「**stage 1/2** cancel 时无 prd.md」 | 「**范围确认 / build 阶段** cancel 时无 prd.md」 |

### 3.C banner 去 stage 号

| 文件:行 | 现状 | 改成 |
|---|---|---|
| `scripts/_lib/state.py:433` | `f"━━━ PMAI ► {skill} ▸ Stage {stage}/{MAX_STAGE}: {stage_name} ━━━"` | `f"━━━ PMAI ► {skill} ▸ {stage_name} ━━━"`（去 `Stage N/T:`，单点生成，blast 最小） |
| `banner-rules.md:14,18,24,25,26` | §1.1 格式 `Stage <N>/<T>: <Name>` + §1.2 例子 | 格式改 `━━━ PMAI ► <SKILL> ▸ <Name> ━━━`，例子同步去号 |
| `status-view.py:145,259` 注释 | 描述性提到「Stage N/M」 | 注释同步措辞（非 PM-facing，低优先） |

### 3.D 映射表（唯一翻译真相源）

`input-flow.md:7-15` 六步框加「= 内部 stage」列：

```
① 项目底座  = 项目级（非 per-req stage，init 时建）
② 范围确认  = stage 1
③ build     = stage 2
④ 复审 + ⑤ 体验迭代 = stage 3
⑥ 沉淀      = stage 4
```

### 3.E lint hook

新建 `hooks/check-stage-number-jargon.cjs`（仿 `check-sync-asset-jargon.cjs`）：
- **拦**：`skills/**/*.md` 里裸 `stage\s*\d` / `Stage\s*\d`
- **allowlist**：代码块内（```…```）、`MAX_STAGE` / `stage_\w` / `STAGE_` / `{stage}` 等代码标识符、`.req-meta.json` 字段名
- 注册到 `.claude/settings.json` PreToolUse（`git commit` 时触发，命中则拦下并喂回提醒）

## §4 砍掉的机制（防 review 加回来）

- banner 的 `Stage <N>/<T>:` 字段 —— stage 号不再 PM-facing，banner 只显阶段名。

## §5 风险与待验

| # | 风险 / 待验 | 处理 |
|---|---|---|
| 1 | **`init-project/SKILL.md:74-78` 的 `A/5 B/5 C/5 D/5` 是 init 项目级 phase 号，不是 per-req stage 号** | 严格说不在「Stage N/T」范围。**待 PM 定**：要不要一起去号（倾向也去，但单列不擅自动） |
| 2 | **`new-req/SKILL.md` 的 `4A-4D` 是步骤 4 的子步「拉 worktree」，与旧 stage-4-4A 同名不同义** | lint / 重写时**别误伤**——这是合法的子步编号 |
| 3 | lint allowlist 边界 | 需在实现时核对：banner 去号后无需给 `Stage N/T` 开口子；代码块 / 代码标识符要放行 |
| 4 | **quick-fix DEFER** — `quick-fix/SKILL.md:98,155,156,166,168,182,195` 的「决策性修订走 stage 3 prd revise」整套 drift-scan 产物链停在旧 7-stage（brief/analysis/prd 当活产物）。新机 brief/analysis 已退场、真相源是 req-plan、prd 沉淀按需 | **本次不改**（§0.4.1）。改它要先决定 quick-fix 对新机产物链的态度，是独立议题。本次仅在 §3 不触碰这几处 |
| 5 | 框架资产改动纪律 | 同 commit 带 `CHANGELOG.md` 未发布条 + 视情况更 `RUNTIME.md`；新 hook 注册进 settings.json |

## §6 实证支撑

消费仓 transcript：AI 已连续 3 次抢跑（脑补 PM 决策 / 空参数 AskUserQuestion 报错），第 4 次「推过头一格」（1→2→3）。AI 自查归因到「task-plan 文案里残留的六步 / stage 6 旧说法」——经核验，真正的 stale 在 `task-plan/SKILL.md:320`（SKILL prose，AI 跑 skill 时读），不在生成出的 `task-plan.md` 产物（模板干净）。

---

## §X Review Findings

> 每条 finding 按下表。PAIN_LINK = NONE 且 EVIDENCE = ASSUMED 的默认 [DEFER]。

### Round 0 — 待 PM 共写锁 §0 后开 review

| # | Severity | Finding 摘要 | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| — | — | （待填） | | | |

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-06-01 | PM 拍板：选项1（去裸数字 + 映射表 + lint，保留「六步」名） | 见 §1 |
| 2026-06-01 | PM 拍板：banner 纳入本次，去 stage 号 | 见 §3.C |
| 2026-06-04 | **落地实现**：§3.A 死编号重写 + §3.B 名字化 + §3.C banner 去号（state.py + status-view Active 渲染）+ §3.D input-flow 映射表 + §3.E `hooks/check-stage-number-jargon.cjs` + R1 init 阶段号去号 | quick-fix 产物链旧编号 DEFER（§0.4.1 独立 blast radius）；基线 588/0；待 PM 总审归档 |

---

**End of stage 编号清理与 banner 去号 v0**
